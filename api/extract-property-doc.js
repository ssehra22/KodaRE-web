// KodaRE — Vercel serverless function: read an uploaded Deed, Lease, Inspection Report, or
// "Other" (e.g. MLS one-pager, appraisal) document with AI and draft the matching property
// fields for review. Sibling to /api/extract-loan-doc.js (same auth/role pattern, same
// never-writes-to-the-database-itself design) — kept as a separate file so the loan flow,
// already confirmed working, is never touched by this addition.
//
// Which fields get drafted depends on the uploaded document's type:
//   Deed              -> Purchase record fields on the property's Overview tab
//   Lease              -> Lease record fields on the property's Overview tab
//   Inspection Report,
//   Other               -> Property characteristics on the Details tab (MLS one-pagers,
//                          appraisals, and inspection reports all commonly carry this info)
//
// Setup: same two Vercel environment variables as extract-loan-doc.js —
//   ANTHROPIC_API_KEY, SUPABASE_SERVICE_ROLE_KEY — nothing additional needed if those are
// already set up.
//
// Only Senior Admin can call this — Office Staff can upload these documents, but only Senior
// Admin can trigger AI reading and approve what it drafts, matching the rule for loan documents.

const SUPABASE_URL = 'https://ybjsbxswsuuxmoxdhvkt.supabase.co';
const ANON_KEY = 'sb_publishable_K1BE_CGLkreR0p03Ocwq2w_HW8CuhnT';

const DOC_TYPE_TO_KIND = {
  'Deed': 'deed',
  'Lease': 'lease',
  'Inspection Report': 'characteristics',
  'Other': 'characteristics'
};

const SCHEMAS = {
  deed: {
    keys: ['buyerLLC', 'county', 'purchaseDate', 'settlementDate', 'purchasePrice', 'totalBuyerCosts', 'taxId'],
    prompt: `You are reading a property deed or closing/settlement document for a property management company. Extract ONLY what is explicitly stated — never guess or fabricate. Use null for anything not stated.

Return ONLY a single JSON object (no markdown, no code fences, no explanation) with exactly these keys:
{
  "buyerLLC": string or null — the buyer/grantee entity name (often an LLC),
  "county": string or null,
  "purchaseDate": string or null — the deed/purchase date, in ISO format YYYY-MM-DD,
  "settlementDate": string or null — the settlement/closing date, in ISO format YYYY-MM-DD (same as purchaseDate if the document only gives one date),
  "purchasePrice": number or null — the stated sale/consideration price, plain number, no "$" or commas,
  "totalBuyerCosts": number or null — buyer's total closing costs, plain number, ONLY if this document itemizes them (most deeds don't — leave null rather than guessing),
  "taxId": string or null — the tax parcel/parcel ID number
}`
  },
  lease: {
    keys: ['landlord', 'rent', 'leaseType'],
    prompt: `You are reading a residential or commercial lease agreement for a property management company. Extract ONLY what is explicitly stated — never guess or fabricate. Use null for anything not stated.

Return ONLY a single JSON object (no markdown, no code fences, no explanation) with exactly these keys:
{
  "landlord": string or null — the landlord/lessor's name,
  "rent": number or null — the monthly rent amount, plain number, no "$" or commas,
  "leaseType": string or null — a short description of the lease type as the document itself would describe it (e.g. "Residential", "Corporate", "Month-to-month")
}`
  },
  characteristics: {
    keys: ['bedrooms', 'bathrooms', 'sqft', 'yearBuilt', 'levels', 'parkingType', 'typeStyle', 'constructionMaterial', 'zoning', 'propertyType', 'hoaCondo', 'hoaFee', 'hoaAssocName', 'municipality', 'schoolDistrict', 'taxId', 'mls', 'county'],
    prompt: `You are reading a property inspection report, appraisal, or MLS one-page property summary for a property management company. Extract ONLY what is explicitly stated — never guess or fabricate. Use null for anything not stated.

Return ONLY a single JSON object (no markdown, no code fences, no explanation) with exactly these keys:
{
  "bedrooms": number or null,
  "bathrooms": number or null — can be a decimal like 2.5,
  "sqft": number or null — square footage, plain number,
  "yearBuilt": number or null,
  "levels": number or null — number of stories/levels,
  "parkingType": string or null — e.g. "Attached garage", "Driveway", "Off-street lot",
  "typeStyle": string or null — e.g. "Colonial", "Ranch",
  "constructionMaterial": string or null — e.g. "Vinyl siding", "Brick",
  "zoning": string or null,
  "propertyType": string or null — e.g. "Single family",
  "hoaCondo": string or null — exactly "Yes" or "No" if stated, whether there's an HOA/condo association,
  "hoaFee": number or null — monthly HOA/condo fee, plain number,
  "hoaAssocName": string or null,
  "municipality": string or null,
  "schoolDistrict": string or null,
  "taxId": string or null,
  "mls": string or null — MLS number, only if this is an MLS sheet,
  "county": string or null
}`
  }
};

function extToMediaType(name) {
  const n = (name || '').toLowerCase();
  if (n.endsWith('.pdf')) return { kind: 'document', mediaType: 'application/pdf' };
  if (n.endsWith('.png')) return { kind: 'image', mediaType: 'image/png' };
  if (n.endsWith('.jpg') || n.endsWith('.jpeg')) return { kind: 'image', mediaType: 'image/jpeg' };
  if (n.endsWith('.webp')) return { kind: 'image', mediaType: 'image/webp' };
  if (n.endsWith('.gif')) return { kind: 'image', mediaType: 'image/gif' };
  return null;
}

module.exports = async (req, res) => {
  if (req.method !== 'POST') { res.status(405).json({ error: 'Method not allowed' }); return; }

  const anthropicKey = process.env.ANTHROPIC_API_KEY;
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!anthropicKey || !serviceKey) {
    res.status(500).json({ error: 'Server not configured: add ANTHROPIC_API_KEY and SUPABASE_SERVICE_ROLE_KEY in Vercel → Settings → Environment Variables, then redeploy.' });
    return;
  }

  // ---- 1) Identify the caller ----
  const authHeader = req.headers.authorization || '';
  const callerToken = authHeader.startsWith('Bearer ') ? authHeader.slice(7) : null;
  if (!callerToken) { res.status(401).json({ error: 'Missing session token.' }); return; }

  let me;
  try {
    const meResp = await fetch(`${SUPABASE_URL}/auth/v1/user`, {
      headers: { apikey: ANON_KEY, Authorization: `Bearer ${callerToken}` }
    });
    if (!meResp.ok) { res.status(401).json({ error: 'Your session has expired — please sign in again.' }); return; }
    me = await meResp.json();
  } catch (e) {
    res.status(502).json({ error: 'Could not verify your session: ' + e.message });
    return;
  }

  // ---- 2) Confirm the caller is Senior Admin ----
  let callerRole;
  try {
    const roleResp = await fetch(`${SUPABASE_URL}/rest/v1/user_roles?user_id=eq.${me.id}&select=role`, {
      headers: { apikey: serviceKey, Authorization: `Bearer ${serviceKey}` }
    });
    const roleRows = await roleResp.json();
    callerRole = roleRows && roleRows[0] && roleRows[0].role;
  } catch (e) {
    res.status(502).json({ error: 'Could not verify your role: ' + e.message });
    return;
  }
  if (callerRole !== 'admin') { res.status(403).json({ error: 'Only Senior Admin can read property documents with AI.' }); return; }

  // ---- 3) Look up the document + decide what kind of extraction it needs ----
  const { documentId } = req.body || {};
  if (!documentId) { res.status(400).json({ error: 'Missing documentId.' }); return; }

  let doc;
  try {
    const docResp = await fetch(`${SUPABASE_URL}/rest/v1/documents?id=eq.${documentId}&select=*`, {
      headers: { apikey: serviceKey, Authorization: `Bearer ${serviceKey}` }
    });
    const docRows = await docResp.json();
    doc = docRows && docRows[0];
  } catch (e) {
    res.status(502).json({ error: 'Could not look up the document: ' + e.message });
    return;
  }
  if (!doc) { res.status(404).json({ error: 'Document not found.' }); return; }

  const kind = DOC_TYPE_TO_KIND[doc.doc_type];
  if (!kind) {
    res.status(400).json({ error: `KodaRE doesn't read "${doc.doc_type}" documents yet — only Deed, Lease, Inspection Report, and Other are supported right now.` });
    return;
  }
  const schema = SCHEMAS[kind];

  const typeInfo = extToMediaType(doc.file_name);
  if (!typeInfo) {
    res.status(400).json({ error: 'KodaRE can only read PDF or photo (JPG/PNG) files right now — try re-uploading as a PDF or a photo of the document.' });
    return;
  }

  // ---- 4) Download the file ----
  let fileBuffer;
  try {
    const fileResp = await fetch(`${SUPABASE_URL}/storage/v1/object/documents/${doc.file_path}`, {
      headers: { apikey: serviceKey, Authorization: `Bearer ${serviceKey}` }
    });
    if (!fileResp.ok) { res.status(502).json({ error: 'Could not download the file from storage.' }); return; }
    const arrayBuffer = await fileResp.arrayBuffer();
    fileBuffer = Buffer.from(arrayBuffer);
  } catch (e) {
    res.status(502).json({ error: 'Could not download the file: ' + e.message });
    return;
  }

  const MAX_BYTES = 15 * 1024 * 1024;
  if (fileBuffer.length > MAX_BYTES) {
    res.status(400).json({ error: 'This file is too large to read automatically (over 15MB). Try a smaller scan or a text-based PDF instead.' });
    return;
  }
  const base64Data = fileBuffer.toString('base64');

  // ---- 5) Ask Claude to read it ----
  const contentBlock = typeInfo.kind === 'document'
    ? { type: 'document', source: { type: 'base64', media_type: typeInfo.mediaType, data: base64Data } }
    : { type: 'image', source: { type: 'base64', media_type: typeInfo.mediaType, data: base64Data } };

  let claudeText;
  try {
    const claudeResp = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: {
        'x-api-key': anthropicKey,
        'anthropic-version': '2023-06-01',
        'content-type': 'application/json'
      },
      body: JSON.stringify({
        model: 'claude-sonnet-5',
        max_tokens: 1500,
        temperature: 0,
        messages: [{
          role: 'user',
          content: [contentBlock, { type: 'text', text: schema.prompt }]
        }]
      })
    });
    const claudeData = await claudeResp.json();
    if (!claudeResp.ok) {
      res.status(502).json({ error: 'AI reading failed: ' + (claudeData.error && claudeData.error.message ? claudeData.error.message : 'unknown error') });
      return;
    }
    claudeText = (claudeData.content || []).map(b => b.text || '').join('').trim();
  } catch (e) {
    res.status(502).json({ error: 'Could not reach the AI reading service: ' + e.message });
    return;
  }

  // ---- 6) Parse the JSON out of Claude's reply ----
  let fields;
  try {
    const cleaned = claudeText.replace(/^```(?:json)?/i, '').replace(/```$/, '').trim();
    const parsed = JSON.parse(cleaned);
    fields = {};
    schema.keys.forEach(k => { fields[k] = (k in parsed) ? parsed[k] : null; });
  } catch (e) {
    res.status(502).json({ error: 'KodaRE could not make sense of what the AI returned. Try again, or enter the fields manually this time.' });
    return;
  }

  res.status(200).json({ ok: true, kind, fields, documentName: doc.file_name });
};
