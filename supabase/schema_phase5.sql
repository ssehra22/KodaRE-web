-- KodaRE — Phase 5 schema: Property Acquisition Checklist (Scope §4.11, §4.15).
-- Run this once in your Supabase project's SQL Editor (Project → SQL Editor → New query).
-- Safe to re-run: uses "if not exists" / "or replace" throughout.
-- Additive only — never deletes anything, and won't touch existing Properties/Maintenance/
-- Vendors/Leases/Compliance/Disposition/Licensing data.

create extension if not exists pgcrypto;

create or replace function set_updated_at() returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

-- One row per property. `items` holds the whole checklist as a JSON map keyed by field
-- label (matching PURCHASE_CHECKLIST / RENTAL_CHECKLIST in index.html — the same table
-- covers both owned and leased properties, since each property only ever uses one of the
-- two lists), each value shaped like {"s":"pending|done|na","t":"free-text value"}.
-- Using JSON here (rather than one column per field) means adding/renaming/reordering
-- checklist items later — like the recent Status → Stage rename and the added "Licensed"
-- option — never requires another migration.
create table if not exists purchase_checklists (
  id uuid primary key default gen_random_uuid(),
  property_id uuid not null unique references properties(id) on delete cascade,
  items jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
drop trigger if exists trg_purchase_checklists_updated_at on purchase_checklists;
create trigger trg_purchase_checklists_updated_at
before update on purchase_checklists
for each row execute function set_updated_at();

create index if not exists idx_purchase_checklists_property on purchase_checklists(property_id);

-- Row Level Security: same policy shape as every other table — internal team only,
-- single shared "authenticated" role, no public/anonymous access.
alter table purchase_checklists enable row level security;

drop policy if exists "authenticated_select_purchase_checklists" on purchase_checklists;
create policy "authenticated_select_purchase_checklists" on purchase_checklists for select using (auth.role() = 'authenticated');
drop policy if exists "authenticated_insert_purchase_checklists" on purchase_checklists;
create policy "authenticated_insert_purchase_checklists" on purchase_checklists for insert with check (auth.role() = 'authenticated');
drop policy if exists "authenticated_update_purchase_checklists" on purchase_checklists;
create policy "authenticated_update_purchase_checklists" on purchase_checklists for update using (auth.role() = 'authenticated');
drop policy if exists "authenticated_delete_purchase_checklists" on purchase_checklists;
create policy "authenticated_delete_purchase_checklists" on purchase_checklists for delete using (auth.role() = 'authenticated');
