-- KodaRE — Phase 29 schema: scoped audit log (Scope §5.2/§5.5 "Audit log of all sensitive
-- data changes").
--
-- Deliberately scoped, not exhaustive — matches the spec's own language ("sensitive data
-- changes"), not reshab-platform's broader implementation which logs nearly every write in the
-- app. Covers: edits to Senior-Admin-locked property/loan fields, Senior Admin role changes,
-- property-caregiver assignment changes ("themselves auditable events" per §5.2), and
-- permanent deletions (as opposed to soft-delete/trash, which is already tracked separately).
--
-- No IP column. The spec asks for "from what IP," but even reshab-platform's own
-- implementation — despite running server-side code that could read it from request headers —
-- never actually wires that up in practice. KodaRE writes straight from the browser with no
-- server hop at all, so there's no trustworthy way to capture a client's IP here; a client
-- could just send whatever it wants. Skipped rather than faked.
--
-- Immutable by design: insert-only policy, no update or delete policy granted to anyone
-- (matches "immutable history" in §5.5) — not even Senior Admin can edit or remove an entry
-- through the app.
--
-- Run this once in your Supabase project's SQL Editor. Safe to re-run.

create table if not exists public.audit_log (
  id          uuid primary key default gen_random_uuid(),
  at          timestamptz not null default now(),
  actor_email text,
  actor_role  text,
  action      text not null,       -- e.g. 'Updated property field', 'Changed role', 'Assigned property', 'Permanently deleted'
  object_type text not null,       -- 'property' | 'user_role' | 'property_assignment' | 'vendor' | 'ticket'
  object_ref  text,                -- human-readable label: property name, user email, vendor name, ticket ref
  field       text,                -- which field changed, if applicable (e.g. 'purchasePrice')
  old_value   text,
  new_value   text
);

comment on table public.audit_log is
  'Immutable trail of sensitive changes: locked property/loan fields, role changes, property assignments, permanent deletions. Senior Admin read only. See Phase 29.';

create index if not exists audit_log_recent_idx on public.audit_log (at desc);

alter table public.audit_log enable row level security;

drop policy if exists "authenticated insert audit log" on public.audit_log;
create policy "authenticated insert audit log" on public.audit_log
  for insert
  with check (auth.role() = 'authenticated');

drop policy if exists "senior admin read audit log" on public.audit_log;
create policy "senior admin read audit log" on public.audit_log
  for select using (current_role_is_admin());

-- No update or delete policy — nobody can modify or remove an entry through the app, by design.

grant select, insert on public.audit_log to authenticated;
