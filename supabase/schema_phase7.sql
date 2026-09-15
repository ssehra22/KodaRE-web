-- KodaRE — Phase 7 schema: Reference Lists persistence (Service Category, Service Type,
-- and every other picklist in Assumptions → Reference Lists).
-- Run this once in your Supabase project's SQL Editor (Project → SQL Editor → New query).
-- Safe to re-run: uses "if not exists" / "or replace" throughout.
-- Additive only — one small shared table, doesn't touch any existing data.
--
-- Why: these lists previously lived only in each browser's local storage, so edits made
-- on one device never showed up on another, and "Reset demo data" wiped them. This table
-- makes them real, shared, and durable — matching how Properties/Vendors/Tickets/
-- checklists already work.

create extension if not exists pgcrypto;

create or replace function set_updated_at() returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

-- One row per list. `key` is 'CAT' for Service Category, 'SVC_TYPES' for Service Type, or
-- the matching REF_LISTS key (e.g. 'propStage', 'metro', 'workQuality', ...) for everything
-- else in Reference Lists. `data` holds the whole list as JSON — an {icon-map} object for
-- CAT, a plain array of values for everything else.
create table if not exists reference_lists (
  id uuid primary key default gen_random_uuid(),
  key text not null unique,
  data jsonb not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
drop trigger if exists trg_reference_lists_updated_at on reference_lists;
create trigger trg_reference_lists_updated_at
before update on reference_lists
for each row execute function set_updated_at();

alter table reference_lists enable row level security;

drop policy if exists "authenticated_select_reference_lists" on reference_lists;
create policy "authenticated_select_reference_lists" on reference_lists for select using (auth.role() = 'authenticated');
drop policy if exists "authenticated_insert_reference_lists" on reference_lists;
create policy "authenticated_insert_reference_lists" on reference_lists for insert with check (auth.role() = 'authenticated');
drop policy if exists "authenticated_update_reference_lists" on reference_lists;
create policy "authenticated_update_reference_lists" on reference_lists for update using (auth.role() = 'authenticated');
drop policy if exists "authenticated_delete_reference_lists" on reference_lists;
create policy "authenticated_delete_reference_lists" on reference_lists for delete using (auth.role() = 'authenticated');
