-- KodaRE — Phase 24 schema:
-- Office Staff can now see which Field Staff are assigned to which property (Scope §3.2
-- matrix: "Property assignment to caregivers" = Office Staff R, Senior Admin R/W — the write
-- side was already Senior Admin only via Phase 18; this adds the read side for Office Staff).
--
-- Office Staff cannot read user_roles directly (Phase 15's "self_or_admin" policy is
-- unchanged and stays that way — Office Staff still can't browse the full user/role roster,
-- see Senior Admin accounts, or see anyone's role). Instead, this adds a narrow, security-
-- definer function that returns ONLY the name/email of Field Staff (role = 'caregiver')
-- who are assigned to a property, for callers who are Office Staff or Senior Admin. It
-- can't be used to see Office/Admin accounts or anyone's role — just "which Field Staff
-- covers this property," which is exactly what the matrix asks for.
-- Run this once in your Supabase project's SQL Editor, AFTER schema_phase21.sql. Safe to re-run.

create or replace function public.property_assignment_roster()
returns table(property_id uuid, user_id uuid, name text, email text)
language sql
stable
security definer
set search_path = public
as $$
  select upa.property_id, upa.user_id, ur.name, ur.email
  from user_property_assignments upa
  join user_roles ur on ur.user_id = upa.user_id
  where ur.role = 'caregiver'
    and current_role_is_admin_or_office();
$$;

grant execute on function public.property_assignment_roster() to authenticated;
