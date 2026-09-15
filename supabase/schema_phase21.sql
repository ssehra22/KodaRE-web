-- KodaRE — Phase 21 schema:
-- 1) Field Staff should NEVER see property-level Documents (deeds, leases, insurance
--    certificates, inspection reports, loan/mortgage paperwork) — confirmed with Sonia
--    Aug 4, 2026. Phase 18 had already hidden UNPOSTED documents from Field Staff, but still
--    let them see (the row/metadata for) POSTED documents at their assigned properties. This
--    removes that carve-out entirely: Documents are Office Staff / Senior Admin only, full
--    stop. Field Staff only ever deal with photos/files attached directly to a maintenance
--    ticket (proof of damage for repair) — that's the separate ticket_attachments feature from
--    Phase 19/20, which is unaffected by this change.
-- 2) Property records (all fields, every tab — Details, Acquisition, Disposition, Loan, etc.)
--    are edit-locked to Senior Admin at the database level, matching what the app's UI has
--    already enforced for a while (Office Staff sees every property field as read-only via
--    propTxt()). Office Staff could previously still have edited any property field, including
--    Loan & debt, by calling the API directly, bypassing the UI-only restriction — this closes
--    that gap so it's enforced by the database too, not just the interface.
-- Run this once in your Supabase project's SQL Editor, AFTER schema_phase20.sql. Safe to re-run.

-- ================= Documents — Field Staff: zero access, full stop =================
drop policy if exists "authenticated_select_documents" on documents;
create policy "authenticated_select_documents" on documents for select using (
  current_role_is_admin_or_office()
);

-- ================= Properties — Senior Admin only can edit (any field) =================
drop policy if exists "office_admin_update_properties" on properties;
create policy "admin_update_properties" on properties for update using (
  current_role_is_admin()
);
