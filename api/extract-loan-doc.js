// KodaRE — Vercel serverless function: read an uploaded loan document with AI and draft the
// Loan tab's fields for review. Never writes to the database itself — it only returns a draft;
// the browser shows it for review and the actual save happens through the normal, already
// Senior-Admin-only property update path (see approveLoanExtraction() in index.html).
//
// Why this has to live server-side: it needs an Anthropic API key (to read the document) and
// the Supabase "service_role" (secret) key (to fetch the document file and look up the caller's
// role, bypassing RLS safely). Neither key can ever be shipped to the browser.
//
// Setup (one-time, done by you in the Vercel dashboard — never in this file or the git repo):
//   Vercel Project → Settings → Environment Variables → add BOTH:
//     ANTHROPIC_API_KEY        = your key from console.anthropic.com → API Keys
//     SUPABASE_SERVICE_ROLE_KEY = the "secret" key from Supabase → Project Settings → API
//   Redeploy after adding them (Vercel picks up new env vars on the next deploy).
//
// Only Senior Admin can call this (checked below) — matches the app's rule that Office Staff
// can upload loan documents but only Senior Admin can approve what KodaRE reads from them.

const SUPABASE_URL = 'https://ybjsbxswsuuxmoxdhvkt.supabase.co';
const ANON_KEY = 'sb_publishable_K1BE_CGLkreR0p03Ocwq2w_HW8CuhnT';

const LOAN_FIELD_KEYS = [
  'loanLender', 'loanContact', 'loanAcctNo', 'loanOrigDate', 'loanInitial',
  'loanRate', 'loanRateType', 'loanTermMo', 'loanMaturity', 'loanPayment',
  'loanEscrow', 'loanRemaining', 'loanLien', 'loanPrepay'
];

const EXTRACTION_PROMPT = `You are reading a real estate loan/mortgage document for a property management company. Extract ONLY what is explicitly stated in the document — never guess, estimate, or fabricate a value. If a field isn't stated in the document, use null for it.

Return ONLY a single JSON object (no markdown, no explanation, no code fences) with exactly these keys:
{
  "loanLender": string or null — the lending institution's name,
  "loanContact": string or null — a contact name/phone/email for the lender, if stated,
  "loanAcctNo": string or null — the loan or account number,
  "loanOrigDate": string or null — origination/closing date, written like "Mar 2021" (month + year, or full date if that's all that's given),
  "loanInitial": number or null — original principal amount, as a plain number with no "$" or commas,
  "loanRate": number or null — interest rate as a plain number, e.g. 6.25 for 6.25%, no "%" sign,
  "loanRateType": string or null — e.g. "Fixed", "ARM", "5/1 ARM",
  "loanTermMo": number or null — loan term in months as a plain number (convert years to months if stated in years),
  "loanMaturity": string or null — maturity date, written like "Mar 2051",
  "loanPayment": number or null — monthly principal & interest payment, plain number no "$",
  "loanEscrow": number or null — monthly escrow amount, plain number no "$", if stated,
  "loanRemaining": number or null — current outstanding balance, plain number no "$", only if this document actually states a current/remaining balance (an original note or closing disclosure usually only has the original principal — don't copy the original principal into this field),
  "loanLien": string or null — lien position, e.g. "1st", "2nd",
  "loanPrepay": string or null — prepayment penalty terms, in a short phrase, or "None" if the document explicitly says there is none
}`;

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

  // ---- 1) Identify the caller from their session token ----
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

  // ---- 2) Confirm the caller is Senior Admin — only admins can read/approve loan documents ----
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
  if (callerRole !== 'admin') { res.status(403).json({ error: 'Only Senior Admin can read loan documents with AI.' }); return; }

  // ---- 3) Validate the request + look up the document ----
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

  const typeInfo = extToMediaType(doc.file_name);
  if (!typeInfo) {
    res.status(400).json({ error: 'KodaRE can only read PDF or photo (JPG/PNG) files right now — this file is a ' + (doc.file_name.split('.').pop() || 'unknown') + '. Try re-uploading as a PDF or a photo of the document.' });
    return;
  }

  // ---- 4) Download the file from Storage ----
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

  const MAX_BYTES = 15 * 1024 * 1024; // keep well under Claude's per-file limits
  if (fileBuffer.length > MAX_BYTES) {
    res.status(400).json({ error: 'This file is too large to read automatically (over 15MB). Try a smaller scan or a text-based PDF instead of a large image scan.' });
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
          content: [contentBlock, { type: 'text', text: EXTRACTION_PROMPT }]
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

  // ---- 6) Parse the JSON out of Claude's reply (strip code fences if present) ----
  let fields;
  try {
    const cleaned = claudeText.replace(/^```(?:json)?/i, '').replace(/```$/, '').trim();
    const parsed = JSON.parse(cleaned);
    fields = {};
    LOAN_FIELD_KEYS.forEach(k => { fields[k] = (k in parsed) ? parsed[k] : null; });
  } catch (e) {
    res.status(502).json({ error: 'KodaRE could not make sense of what the AI returned. Try again, or enter the fields manually this time.' });
    return;
  }

  res.status(200).json({ ok: true, fields, documentName: doc.file_name });
};
