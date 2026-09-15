-- KodaRE — Phase 3 schema: Property Disposition Checklist (Scope §4.13) and
-- Initial Licensing Checklist (Scope §4.3).
-- Run this once in your Supabase project's SQL Editor (Project → SQL Editor → New query).
-- Safe to re-run: uses "if not exists" / "or replace" throughout.
-- Additive only — never deletes anything, and won't touch existing Properties/Maintenance/
-- Vendors/Leases/Compliance data.

create extension if not exists pgcrypto;

create or replace function set_updated_at() returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

-- One row per property. `items` holds the whole checklist as a JSON map keyed by field
-- label (matching DISPOSITION_CHECKLIST / LICENSING_CHECKLIST in index.html), each value
-- shaped like {"s":"pending|done|na","t":"free-text note"}. Using JSON here (rather than
-- one column per field) means adding/renaming/reordering checklist items later — like we
-- just did for Licensing — never requires another migration.
create table if not exists disposition_checklists (
  id uuid primary key default gen_random_uuid(),
  property_id uuid not null unique references properties(id) on delete cascade,
  items jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
drop trigger if exists trg_disposition_checklists_updated_at on disposition_checklists;
create trigger trg_disposition_checklists_updated_at
before update on disposition_checklists
for each row execute function set_updated_at();

create table if not exists licensing_checklists (
  id uuid primary key default gen_random_uuid(),
  property_id uuid not null unique references properties(id) on delete cascade,
  items jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
drop trigger if exists trg_licensing_checklists_updated_at on licensing_checklists;
create trigger trg_licensing_checklists_updated_at
before update on licensing_checklists
for each row execute function set_updated_at();

create index if not exists idx_disposition_checklists_property on disposition_checklists(property_id);
create index if not exists idx_licensing_checklists_property on licensing_checklists(property_id);

-- Row Level Security: same policy shape as every other table — internal team only,
-- single shared "authenticated" role, no public/anonymous access.
alter table disposition_checklists enable row level security;
alter table licensing_checklists enable row level security;

drop policy if exists "authenticated_select_disposition_checklists" on disposition_checklists;
create policy "authenticated_select_disposition_checklists" on disposition_checklists for select using (auth.role() = 'authenticated');
drop policy if exists "authenticated_insert_disposition_checklists" on disposition_checklists;
create policy "authenticated_insert_disposition_checklists" on disposition_checklists for insert with check (auth.role() = 'authenticated');
drop policy if exists "authenticated_update_disposition_checklists" on disposition_checklists;
create policy "authenticated_update_disposition_checklists" on disposition_checklists for update using (auth.role() = 'authenticated');
drop policy if exists "authenticated_delete_disposition_checklists" on disposition_checklists;
create policy "authenticated_delete_disposition_checklists" on disposition_checklists for delete using (auth.role() = 'authenticated');

drop policy if exists "authenticated_select_licensing_checklists" on licensing_checklists;
create policy "authenticated_select_licensing_checklists" on licensing_checklists for select using (auth.role() = 'authenticated');
drop policy if exists "authenticated_insert_licensing_checklists" on licensing_checklists;
create policy "authenticated_insert_licensing_checklists" on licensing_checklists for insert with check (auth.role() = 'authenticated');
drop policy if exists "authenticated_update_licensing_checklists" on licensing_checklists;
create policy "authenticated_update_licensing_checklists" on licensing_checklists for update using (auth.role() = 'authenticated');
drop policy if exists "authenticated_delete_licensing_checklists" on licensing_checklists;
create policy "authenticated_delete_licensing_checklists" on licensing_checklists for delete using (auth.role() = 'authenticated');
