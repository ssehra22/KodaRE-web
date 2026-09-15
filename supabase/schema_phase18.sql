-- KodaRE — Phase 18 schema: Field Staff property-scoping (Scope §3.2 asterisked rule:
-- "Field StaffCaregiver 'R' access is scoped to properties they are assigned to").
-- Run this once in your Supabase project's SQL Editor, AFTER schema_phase17.sql.
-- Safe to re-run.
--
-- What this does:
--   - Adds a real user_property_assignments join table (named per the scope doc's own data
--     model section) so a Field Staff person can be assigned one or more properties.
--   - Rewrites read (select) policies on Properties, Compliance (certificates/inspections),
--     and Maintenance tickets so a Field Staff login only sees rows for their assigned
--     properties. Office Staff and Senior Admin are unaffected — they still see everything,
--     per the matrix (only Field Staff's "R" is scoped).
--   - Adds a "posted" flag to Documents (Field Staff should not see unposted documents) and
--     an "approved" flag to Vendors (Field Staff should only see vendors flagged approved),
--     and scopes their read policies accordingly.
-- What this deliberately does NOT touch: Leases & Rent and the Purchase/Disposition/Licensing
-- checklists. The Permissions Matrix has no Field Staff row for these at all, so per your
-- direction they get zero access — their select policies stay "authenticated only" which in
-- practice means Office Staff/Senior Admin only, since the app's UI never shows those nav
-- items to Field Staff in the first place. (If a Field Staff account ever called the API
-- directly it would still see these today — closing that fully would mean adding the same
-- kind of role check here. Flagging as a known follow-up, not done in this migration.)

-- ================= Property assignments =================
create table if not exists user_property_assignments (
  user_id uuid not null references user_roles(user_id) on delete cascade,
  property_id uuid not null references properties(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, property_id)
);
create index if not exists idx_upa_property on user_property_assignments(property_id);

alter table user_property_assignments enable row level security;

-- A person can see their own assignments; Office Staff/Senior Admin can see everyone's
-- (matches matrix: "Property assignment to caregivers" = Office Staff R, Senior Admin R/W).
drop policy if exists "select_own_or_office_admin_assignments" on user_property_assignments;
create policy "select_own_or_office_admin_assignments" on user_property_assignments
  for select using (user_id = auth.uid() or current_role_is_admin_or_office());
-- Only Senior Admin can actually make/remove an assignment.
drop policy if exists "admin_insert_assignments" on user_property_assignments;
create policy "admin_insert_assignments" on user_property_assignments
  for insert with check (current_role_is_admin());
drop policy if exists "admin_delete_assignments" on user_property_assignments;
create policy "admin_delete_assignments" on user_property_assignments
  for delete using (current_role_is_admin());

-- Helper: is the signed-in user assigned to this specific property? (No admin/office bypass
-- baked in here on purpose — callers combine this with current_role_is_admin_or_office()
-- explicitly, so each policy below stays readable about who it's actually scoping.)
create or replace function public.current_user_assigned_to_property(pid uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists(
    select 1 from user_property_assignments where user_id = auth.uid() and property_id = pid
  );
$$;

-- ================= Properties — Field Staff scoped read =================
drop policy if exists "authenticated_select_properties" on properties;
create policy "authenticated_select_properties" on properties for select using (
  current_role_is_admin_or_office() or current_user_assigned_to_property(id)
);

-- ================= Compliance: certificates & inspections =================
drop policy if exists "authenticated_select_certificates" on certificates;
create policy "authenticated_select_certificates" on certificates for select using (
  current_role_is_admin_or_office() or current_user_assigned_to_property(property_id)
);
drop policy if exists "authenticated_select_inspections" on inspections;
create policy "authenticated_select_inspections" on inspections for select using (
  current_role_is_admin_or_office() or current_user_assigned_to_property(property_id)
);

-- ================= Maintenance tickets =================
-- Field Staff can still submit (insert) a ticket for any property per the existing phase16
-- policy — this only scopes what they can READ back afterward to their assigned properties.
drop policy if exists "authenticated_select_tickets" on maintenance_tickets;
create policy "authenticated_select_tickets" on maintenance_tickets for select using (
  current_role_is_admin_or_office() or current_user_assigned_to_property(property_id)
);

-- ================= Documents — add "posted" flag =================
-- Field Staff should not see unposted (draft) documents at all, even for their own property.
alter table documents add column if not exists posted boolean not null default false;

drop policy if exists "authenticated_select_documents" on documents;
create policy "authenticated_select_documents" on documents for select using (
  current_role_is_admin_or_office()
  or (posted and current_user_assigned_to_property(property_id))
);

-- ================= Vendors — add "approved" flag + geography scoping =================
-- Field Staff should only see vendors flagged approved AND that serve the metro area of at
-- least one property they're assigned to. Existing office_admin_* insert/update/delete
-- policies from phase16 already let Office Staff/Senior Admin set this flag — no new write
-- policy needed.
alter table vendors add column if not exists approved boolean not null default false;

drop policy if exists "authenticated_select_vendors" on vendors;
create policy "authenticated_select_vendors" on vendors for select using (
  current_role_is_admin_or_office()
  or (
    approved and exists (
      select 1 from user_property_assignments upa
      join properties p on p.id = upa.property_id
      where upa.user_id = auth.uid()
        and p.metro is not null
        and (vendors.metro ? p.metro)
    )
  )
);
