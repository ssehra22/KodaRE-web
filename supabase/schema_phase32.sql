-- KodaRE — Phase 32 schema: close the Field Staff RLS gap on Leases & Rent and the
-- Purchase/Disposition/Licensing checklists (Scope §3.2 Permissions Matrix).
--
-- The matrix lists no Field Staff row at all for these four areas, so per Sonia's direction
-- they get zero Field Staff access. The app's UI already enforces this — Field Staff's mobile
-- nav has no Leases, Acquisition, Disposition, or Licensing screen — but the database itself
-- was left open: every SELECT policy on these four tables was "authenticated_select_*" using
-- (auth.role() = 'authenticated'), which allows ANY signed-in user, including Field Staff. A
-- Field Staff account calling the Supabase API directly (bypassing the app's UI entirely)
-- could still read all of it. This was called out as a known follow-up in schema_phase18.sql
-- ("closing that fully would mean adding the same kind of role check here").
--
-- What this does: tightens the SELECT policy on all four tables to Office Staff / Senior Admin
-- only, matching the insert/update/delete policies these tables already had (those were never
-- open to Field Staff in the first place — only read access had the gap).
--
-- Run this once in your Supabase project's SQL Editor. Safe to re-run.

-- ================= Leases & Rent =================
drop policy if exists "authenticated_select_leases" on leases;
create policy "office_admin_select_leases" on leases for select using (
  current_role_is_admin_or_office()
);

-- ================= Purchase (Acquisition) Checklist =================
drop policy if exists "authenticated_select_purchase_checklists" on purchase_checklists;
create policy "office_admin_select_purchase_checklists" on purchase_checklists for select using (
  current_role_is_admin_or_office()
);

-- ================= Disposition Checklist =================
drop policy if exists "authenticated_select_disposition_checklists" on disposition_checklists;
create policy "office_admin_select_disposition_checklists" on disposition_checklists for select using (
  current_role_is_admin_or_office()
);

-- ================= Initial Licensing Checklist =================
drop policy if exists "authenticated_select_licensing_checklists" on licensing_checklists;
create policy "office_admin_select_licensing_checklists" on licensing_checklists for select using (
  current_role_is_admin_or_office()
);
