// KodaRE — Vercel serverless function: read an uploaded vendor invoice with AI and propose
// which existing maintenance ticket(s) it covers. Scope §4.10 "Invoice matching": one invoice
// commonly spans multiple tickets (one vendor visit, several jobs) and typically covers a
// single property; the platform reads it, proposes ticket matches + a cost per matched ticket
// for staff to review, and never writes to the database itself — same never-writes-itself
// design as /api/extract-loan-doc.js and /api/extract-property-doc.js, adapted for a
// many-tickets target instead of a single property record.
//
// Unlike those two (Senior Admin only, because they draft Senior-Admin-locked property/loan
// fields), this one allows Office Staff too — "Expenses & invoices" is an Office Staff R/W
// row on the §3.2 permissions matrix, and reviewing vendor invoices is day-to-day Office Staff
// work, not a Senior-Admin-only action.
//
// Setup: same two Vercel environment variables as the other two readers —
//   ANTHROPIC_API_KEY, SUPABASE_SERVICE_ROLE_KEY — nothing additional needed if those are
// already set up (they were, as of the loan/property readers going in).
//
// Request body: { path: string (file path inside the 'invoices' storage bucket, already
//   uploaded by the client with the authenticated session), candidates: [{id, ref, title,
//   desc}] (candidate maintenance tickets — already filtered client-side to the selected
//   vendor, Completed/Closed, not yet invoiced, so this function only has to do description
//   matching, not vendor/status filtering) }
//
// Response: { ok:true, invoiceNumber, invoiceDate, total, items:[{description, amount,
//   matchedTicketId}], documentName }

const SUPABASE_URL = 'https://ybjsbxswsuuxmoxdhvkt.supabase.co';
const ANON_KEY = 'sb_publishable_K1BE_CGLkreR0p03Ocwq2w_HW8CuhnT';
const MAX_CANDIDATES = 60;

function extToMediaType(name) {
  const n = (name || '').toLowerCase();
  if (n.endsWith('.pdf')) return { kind: 'document', mediaType: 'application/pdf' };
  if (n.endsWith('.png')) return { kind: 'image', mediaType: 'image/png' };
  if (n.endsWith('.jpg') || n.endsWith('.jpeg')) return { kind: 'image', mediaType: 'image/jpeg' };
  if (n.endsWith('.webp')) return { kind: 'image', mediaType: 'image/webp' };
  if (n.endsWith('.gif')) return { kind: 'image', mediaType: 'image/gif' };
  return null;
}

function buildPrompt(candidates) {
  const list = candidates.slice(0, MAX_CANDIDATES).map(c =>
    `- id: ${c.id} | ref: ${c.ref || c.id} | title: ${(c.title || '').replace(/\s+/g, ' ')} | description: ${(c.desc || '').replace(/\s+/g, ' ')}`
  ).join('\n');

  return `You are reading a vendor invoice for a property-management company. One invoice commonly covers several separate maintenance jobs done by the same vendor, often at the same property, billed together.

Below is a list of candidate maintenance tickets already logged in KodaRE for this vendor (already filtered to the right vendor and to tickets that are Completed/Closed and not yet invoiced) — your job is only to match invoice line items to these by description, not to judge vendor or status.

Candidate tickets:
${list || '(no candidate tickets provided)'}

Important: the invoice's date will often NOT match when the ticket work was logged or completed in KodaRE — Koda's own ticket dates are sometimes estimated. Do NOT use dates to decide matches. Match on the description of the work only.

Read the invoice and extract:
1. The invoice number.
2. The invoice date.
3. The grand total amount due.
4. Every distinct job/task/line described in the invoice — even if the invoice gives only ONE lump total for everything with no per-job dollar breakdown, still separate out each distinct task, unit, or address mentioned as its own item (do not merge them into one).

For each item:
- "amount": the dollar amount for that specific item, ONLY if the invoice itself breaks out a dollar amount per line. If the invoice gives only one total for multiple jobs, use null (do not guess or split evenly).
- "matchedTicketId": the "id" of the single best-matching candidate ticket above, based on its description, if you're reasonably confident. Use null if no candidate is a good match, or if you're not confident.

Return ONLY a single JSON object (no markdown, no code fences, no explanation):
{
  "invoiceNumber": string or null,
  "invoiceDate": string or null — ISO format YYYY-MM-DD,
  "total": number or null — plain number, no "$" or commas,
  "items": [
    { "description": string, "amount": number or null, "matchedTicketId": string or null }
  ]
}`;
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

  // ---- 2) Confirm the caller is Office Staff or Senior Admin (not Field Staff) ----
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
  if (callerRole !== 'admin' && callerRole !== 'office') {
    res.status(403).json({ error: 'Only Office Staff or Senior Admin can read vendor invoices with AI.' });
    return;
  }

  // ---- 3) Validate the request ----
  const { path, candidates } = req.body || {};
  if (!path) { res.status(400).json({ error: 'Missing path.' }); return; }
  const fileName = String(path).split('/').pop();
  const typeInfo = extToMediaType(fileName);
  if (!typeInfo) {
    res.status(400).json({ error: 'KodaRE can only read PDF or photo (JPG/PNG) files right now — try re-uploading as a PDF or a photo of the invoice.' });
    return;
  }

  // ---- 4) Download the file ----
  let fileBuffer;
  try {
    const fileResp = await fetch(`${SUPABASE_URL}/storage/v1/object/invoices/${path}`, {
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

  // ---- 5) Ask Claude to read it and propose matches ----
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
        max_tokens: 2000,
        temperature: 0,
        messages: [{
          role: 'user',
          content: [contentBlock, { type: 'text', text: buildPrompt(Array.isArray(candidates) ? candidates : []) }]
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
  let result;
  try {
    const cleaned = claudeText.replace(/^```(?:json)?/i, '').replace(/```$/, '').trim();
    const parsed = JSON.parse(cleaned);
    const items = Array.isArray(parsed.items) ? parsed.items.map(it => ({
      description: it && it.description != null ? String(it.description) : '',
      amount: it && typeof it.amount === 'number' ? it.amount : null,
      matchedTicketId: it && it.matchedTicketId != null ? String(it.matchedTicketId) : null
    })) : [];
    result = {
      invoiceNumber: parsed.invoiceNumber != null ? String(parsed.invoiceNumber) : null,
      invoiceDate: parsed.invoiceDate != null ? String(parsed.invoiceDate) : null,
      total: typeof parsed.total === 'number' ? parsed.total : null,
      items
    };
  } catch (e) {
    res.status(502).json({ error: 'KodaRE could not make sense of what the AI returned. Try again, or match this invoice to tickets manually this time.' });
    return;
  }

  res.status(200).json({ ok: true, invoiceNumber: result.invoiceNumber, invoiceDate: result.invoiceDate, total: result.total, items: result.items, documentName: fileName });
};
