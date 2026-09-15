-- KodaRE — Phase 16 schema: Enforce the §3.2 Permissions Matrix at the database level.
-- Run this once in your Supabase project's SQL Editor, AFTER schema_phase15.sql.
-- Safe to re-run.
--
-- Why: phase15 gave the app a real user_roles table. This phase replaces the old blanket
-- "any signed-in user can do anything" policies with role-aware ones, so the permission rules
-- are enforced by the database itself — not just hidden buttons in the UI. Today, anyone signed
-- in could open the browser console and write directly to Supabase regardless of their role;
-- after this migration, the database rejects it.
--
-- What this does cover (table-level, matches §3.2 directly):
--   - Everyone signed in can still read (R) the operational tables.
--   - Only Office Staff and Senior Admin can create/edit records (W) — Field Staff
--     stay read-only, except they can still submit a new maintenance ticket (§3.2's "W/R*").
--   - Only Senior Admin can delete anything, or touch Reference Lists at all (§3.2: "Office
--     Staff and Field Staff have no access" to the Assumptions/Reference Lists area).
--
-- What this does NOT cover, and why (documented limitations, not oversights):
--   - §3.2 draws some lines WITHIN a single table (e.g., on Properties: Office Staff can R/W
--     basic info but only Read cost-basis/loan/valuation fields). Row-level security can't see
--     column-level distinctions, so those specific fields are protected by a trigger below
--     instead (a real, database-enforced rule — just a different mechanism than a policy).
--   - "Field Staff access is scoped to properties they're assigned to" needs a
--     property-to-field-staff assignment relationship, which doesn't exist yet as a feature (no
--     UI builds that assignment today). Until that's built, a Field Staff member's read access isn't
--     narrowed to only their properties. Flagging this so it isn't mistaken for an oversight —
--     worth a follow-up phase once "Property assignment to Field Staff" is a real feature.
--   - "Vendor visibility flagged for Field Staff" (approved vendors only) has the same gap —
--     no visibility-flag column exists on vendors yet.
--   - "Reports — financial/executive: Senior Admin only" is enforced today the way it always
--     has been (client-side, since reports are computed from the tables above, not their own
--     table) — this migration doesn't change that.

-- ================= Properties =================
drop policy if exists "authenticated_select_properties" on properties;
create policy "authenticated_select_properties" on properties for select using (auth.role() = 'authenticated');
drop policy if exists "authenticated_insert_properties" on properties;
drop policy if exists "office_admin_insert_properties" on properties;
create policy "office_admin_insert_properties" on properties for insert with check (current_role_is_admin_or_office());
drop policy if exists "authenticated_update_properties" on properties;
drop policy if exists "office_admin_update_properties" on properties;
create policy "office_admin_update_properties" on properties for update using (current_role_is_admin_or_office());
drop policy if exists "admin_delete_properties" on properties;
create policy "admin_delete_properties" on properties for delete using (current_role_is_admin());

-- Column-level backstop: cost basis, valuation, and loan fields are Office Staff read-only /
-- Senior Admin read-write (§3.2 "Property cost basis & purchase history" and "Loans & debt").
create or replace function public.enforce_property_financial_columns()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if current_role_is_admin() then
    return new;
  end if;
  if new.purchase_price is distinct from old.purchase_price
     or new.total_buyer_costs is distinct from old.total_buyer_costs
     or new.loan_initial is distinct from old.loan_initial
     or new.loan_remaining is distinct from old.loan_remaining
     or new.value is distinct from old.value
     or new.loan_lender is distinct from old.loan_lender
     or new.loan_contact is distinct from old.loan_contact
     or new.loan_acct_no is distinct from old.loan_acct_no
     or new.loan_orig_date is distinct from old.loan_orig_date
     or new.loan_rate is distinct from old.loan_rate
     or new.loan_rate_type is distinct from old.loan_rate_type
     or new.loan_term_mo is distinct from old.loan_term_mo
     or new.loan_maturity is distinct from old.loan_maturity
     or new.loan_payment is distinct from old.loan_payment
     or new.loan_escrow is distinct from old.loan_escrow
     or new.loan_lien is distinct from old.loan_lien
     or new.loan_prepay is distinct from old.loan_prepay
  then
    raise exception 'Only Senior Admin can change cost basis, valuation, or loan fields (Scope §3.2)';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_enforce_property_financial_columns on properties;
create trigger trg_enforce_property_financial_columns
  before update on properties
  for each row execute function enforce_property_financial_columns();

-- ================= Maintenance tickets =================
-- Field Staff may still create (submit) a ticket — §3.2 lists this capability as "W/R*".
drop policy if exists "authenticated_select_tickets" on maintenance_tickets;
create policy "authenticated_select_tickets" on maintenance_tickets for select using (auth.role() = 'authenticated');
drop policy if exists "authenticated_insert_tickets" on maintenance_tickets;
drop policy if exists "any_role_insert_tickets" on maintenance_tickets;
create policy "any_role_insert_tickets" on maintenance_tickets for insert with check (auth.role() = 'authenticated');
drop policy if exists "authenticated_update_tickets" on maintenance_tickets;
drop policy if exists "office_admin_update_tickets" on maintenance_tickets;
create policy "office_admin_update_tickets" on maintenance_tickets for update using (current_role_is_admin_or_office());
drop policy if exists "authenticated_delete_tickets" on maintenance_tickets;
drop policy if exists "admin_delete_tickets" on maintenance_tickets;
create policy "admin_delete_tickets" on maintenance_tickets for delete using (current_role_is_admin());

-- Column-level backstop: Priority is Senior-Admin-only to edit once a ticket exists (refinement
-- (2) in the "validated in the interactive prototype" list) — Office Staff view it read-only.
-- Setting priority when FIRST submitting a ticket is unaffected (this only fires on UPDATE).
create or replace function public.enforce_ticket_priority_admin_only()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if current_role_is_admin() then
    return new;
  end if;
  if new.urgency is distinct from old.urgency then
    raise exception 'Only Senior Admin can change ticket priority (Scope §3.2)';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_enforce_ticket_priority on maintenance_tickets;
create trigger trg_enforce_ticket_priority
  before update on maintenance_tickets
  for each row execute function enforce_ticket_priority_admin_only();

-- ================= Maintenance ticket activity (log entries) =================
-- Anyone who can create a ticket also needs to write its first "Logged"/"Reported" activity row.
drop policy if exists "authenticated_select_activity" on maintenance_ticket_activity;
create policy "authenticated_select_activity" on maintenance_ticket_activity for select using (auth.role() = 'authenticated');
drop policy if exists "authenticated_insert_activity" on maintenance_ticket_activity;
drop policy if exists "any_role_insert_activity" on maintenance_ticket_activity;
create policy "any_role_insert_activity" on maintenance_ticket_activity for insert with check (auth.role() = 'authenticated');

-- ================= Vendors =================
drop policy if exists "authenticated_select_vendors" on vendors;
create policy "authenticated_select_vendors" on vendors for select using (auth.role() = 'authenticated');
drop policy if exists "authenticated_insert_vendors" on vendors;
drop policy if exists "office_admin_insert_vendors" on vendors;
create policy "office_admin_insert_vendors" on vendors for insert with check (current_role_is_admin_or_office());
drop policy if exists "authenticated_update_vendors" on vendors;
drop policy if exists "office_admin_update_vendors" on vendors;
create policy "office_admin_update_vendors" on vendors for update using (current_role_is_admin_or_office());
drop policy if exists "authenticated_delete_vendors" on vendors;
drop policy if exists "admin_delete_vendors" on vendors;
create policy "admin_delete_vendors" on vendors for delete using (current_role_is_admin());

-- Column-level backstop: Service Category (Default) / Service Type (Default) are Senior-Admin-
-- only to change, per your earlier instruction — Office Staff can still edit everything else
-- about a vendor record.
create or replace function public.enforce_vendor_defaults_admin_only()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if current_role_is_admin() then
    return new;
  end if;
  if new.trade is distinct from old.trade or new.service_type is distinct from old.service_type then
    raise exception 'Only Senior Admin can change a vendor''s Service Category (Default) or Service Type (Default)';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_enforce_vendor_defaults on vendors;
create trigger trg_enforce_vendor_defaults
  before update on vendors
  for each row execute function enforce_vendor_defaults_admin_only();

-- ================= Leases =================
drop policy if exists "authenticated_select_leases" on leases;
create policy "authenticated_select_leases" on leases for select using (auth.role() = 'authenticated');
drop policy if exists "authenticated_insert_leases" on leases;
drop policy if exists "office_admin_insert_leases" on leases;
create policy "office_admin_insert_leases" on leases for insert with check (current_role_is_admin_or_office());
drop policy if exists "authenticated_update_leases" on leases;
drop policy if exists "office_admin_update_leases" on leases;
create policy "office_admin_update_leases" on leases for update using (current_role_is_admin_or_office());
drop policy if exists "authenticated_delete_leases" on leases;
drop policy if exists "admin_delete_leases" on leases;
create policy "admin_delete_leases" on leases for delete using (current_role_is_admin());

-- ================= Certificates & inspections (Compliance) =================
drop policy if exists "authenticated_select_certificates" on certificates;
create policy "authenticated_select_certificates" on certificates for select using (auth.role() = 'authenticated');
drop policy if exists "authenticated_insert_certificates" on certificates;
drop policy if exists "office_admin_insert_certificates" on certificates;
create policy "office_admin_insert_certificates" on certificates for insert with check (current_role_is_admin_or_office());
drop policy if exists "authenticated_update_certificates" on certificates;
drop policy if exists "office_admin_update_certificates" on certificates;
create policy "office_admin_update_certificates" on certificates for update using (current_role_is_admin_or_office());
drop policy if exists "authenticated_delete_certificates" on certificates;
drop policy if exists "admin_delete_certificates" on certificates;
create policy "admin_delete_certificates" on certificates for delete using (current_role_is_admin());

drop policy if exists "authenticated_select_inspections" on inspections;
create policy "authenticated_select_inspections" on inspections for select using (auth.role() = 'authenticated');
drop policy if exists "authenticated_insert_inspections" on inspections;
drop policy if exists "office_admin_insert_inspections" on inspections;
create policy "office_admin_insert_inspections" on inspections for insert with check (current_role_is_admin_or_office());
drop policy if exists "authenticated_update_inspections" on inspections;
drop policy if exists "office_admin_update_inspections" on inspections;
create policy "office_admin_update_inspections" on inspections for update using (current_role_is_admin_or_office());
drop policy if exists "authenticated_delete_inspections" on inspections;
drop policy if exists "admin_delete_inspections" on inspections;
create policy "admin_delete_inspections" on inspections for delete using (current_role_is_admin());

-- ================= Purchase / Disposition / Licensing checklists =================
drop policy if exists "authenticated_select_purchase_checklists" on purchase_checklists;
create policy "authenticated_select_purchase_checklists" on purchase_checklists for select using (auth.role() = 'authenticated');
drop policy if exists "authenticated_insert_purchase_checklists" on purchase_checklists;
drop policy if exists "office_admin_insert_purchase_checklists" on purchase_checklists;
create policy "office_admin_insert_purchase_checklists" on purchase_checklists for insert with check (current_role_is_admin_or_office());
drop policy if exists "authenticated_update_purchase_checklists" on purchase_checklists;
drop policy if exists "office_admin_update_purchase_checklists" on purchase_checklists;
create policy "office_admin_update_purchase_checklists" on purchase_checklists for update using (current_role_is_admin_or_office());
drop policy if exists "authenticated_delete_purchase_checklists" on purchase_checklists;
drop policy if exists "admin_delete_purchase_checklists" on purchase_checklists;
create policy "admin_delete_purchase_checklists" on purchase_checklists for delete using (current_role_is_admin());

drop policy if exists "authenticated_select_disposition_checklists" on disposition_checklists;
create policy "authenticated_select_disposition_checklists" on disposition_checklists for select using (auth.role() = 'authenticated');
drop policy if exists "authenticated_insert_disposition_checklists" on disposition_checklists;
drop policy if exists "office_admin_insert_disposition_checklists" on disposition_checklists;
create policy "office_admin_insert_disposition_checklists" on disposition_checklists for insert with check (current_role_is_admin_or_office());
drop policy if exists "authenticated_update_disposition_checklists" on disposition_checklists;
drop policy if exists "office_admin_update_disposition_checklists" on disposition_checklists;
create policy "office_admin_update_disposition_checklists" on disposition_checklists for update using (current_role_is_admin_or_office());
drop policy if exists "authenticated_delete_disposition_checklists" on disposition_checklists;
drop policy if exists "admin_delete_disposition_checklists" on disposition_checklists;
create policy "admin_delete_disposition_checklists" on disposition_checklists for delete using (current_role_is_admin());

drop policy if exists "authenticated_select_licensing_checklists" on licensing_checklists;
create policy "authenticated_select_licensing_checklists" on licensing_checklists for select using (auth.role() = 'authenticated');
drop policy if exists "authenticated_insert_licensing_checklists" on licensing_checklists;
drop policy if exists "office_admin_insert_licensing_checklists" on licensing_checklists;
create policy "office_admin_insert_licensing_checklists" on licensing_checklists for insert with check (current_role_is_admin_or_office());
drop policy if exists "authenticated_update_licensing_checklists" on licensing_checklists;
drop policy if exists "office_admin_update_licensing_checklists" on licensing_checklists;
create policy "office_admin_update_licensing_checklists" on licensing_checklists for update using (current_role_is_admin_or_office());
drop policy if exists "authenticated_delete_licensing_checklists" on licensing_checklists;
drop policy if exists "admin_delete_licensing_checklists" on licensing_checklists;
create policy "admin_delete_licensing_checklists" on licensing_checklists for delete using (current_role_is_admin());

-- ================= Reference Lists (Assumptions area) =================
-- §3.2 refinement: "Office Staff and Field Staff have no access" refers to the Assumptions
-- *screen* (already hidden from their nav in the app) and to editing the lists. The underlying
-- values (Service Category, Stage, Metro, etc.) feed dropdowns used everywhere in the app by
-- every role, so read access has to stay open — only writes are Senior-Admin-only.
drop policy if exists "authenticated_select_reference_lists" on reference_lists;
create policy "authenticated_select_reference_lists" on reference_lists for select using (auth.role() = 'authenticated');
drop policy if exists "authenticated_insert_reference_lists" on reference_lists;
drop policy if exists "admin_insert_reference_lists" on reference_lists;
create policy "admin_insert_reference_lists" on reference_lists for insert with check (current_role_is_admin());
drop policy if exists "authenticated_update_reference_lists" on reference_lists;
drop policy if exists "admin_update_reference_lists" on reference_lists;
create policy "admin_update_reference_lists" on reference_lists for update using (current_role_is_admin());
drop policy if exists "authenticated_delete_reference_lists" on reference_lists;
drop policy if exists "admin_delete_reference_lists" on reference_lists;
create policy "admin_delete_reference_lists" on reference_lists for delete using (current_role_is_admin());

-- ================= Invoice files (storage) =================
-- §3.2 "Expenses & invoices": Office Staff and Senior Admin R/W, Field Staff no access.
drop policy if exists "authenticated_read_invoices" on storage.objects;
drop policy if exists "office_admin_read_invoices" on storage.objects;
create policy "office_admin_read_invoices" on storage.objects for select
  using (bucket_id = 'invoices' and current_role_is_admin_or_office());
drop policy if exists "authenticated_upload_invoices" on storage.objects;
drop policy if exists "office_admin_upload_invoices" on storage.objects;
create policy "office_admin_upload_invoices" on storage.objects for insert
  with check (bucket_id = 'invoices' and current_role_is_admin_or_office());
drop policy if exists "authenticated_delete_invoices" on storage.objects;
drop policy if exists "office_admin_delete_invoices" on storage.objects;
create policy "office_admin_delete_invoices" on storage.objects for delete
  using (bucket_id = 'invoices' and current_role_is_admin_or_office());
