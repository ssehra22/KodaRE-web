-- KodaRE — Combined schema catch-up: Phases 6 through 12.
-- Run this once in your Supabase project's SQL Editor (Project → SQL Editor → New query).
-- Safe to re-run in full, and safe even if you've already run some of these individually —
-- every statement below is additive ("if not exists" / "add column if not exists") except
-- the one metro type conversion in Phase 8, which is also idempotent (re-running it on an
-- already-jsonb column is a no-op).

-- ===== Phase 6: Vendor Directory drill-down additions (Scope §4.9) =====
alter table vendors add column if not exists service_type text;
alter table vendors add column if not exists comments text;
alter table vendors add column if not exists user_notes text;
alter table vendors add column if not exists properties text;

-- ===== Phase 7: Reference Lists persistence (Service Category, Service Type, etc.) =====
create extension if not exists pgcrypto;

create or replace function set_updated_at() returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

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

-- ===== Phase 8: Vendor Metro becomes multi-select (Scope §4.9) =====
-- Guarded so this is a true no-op if you already ran schema_phase8.sql on its own —
-- it only converts the column if it's still plain text.
do $$
begin
  if (select data_type from information_schema.columns where table_name='vendors' and column_name='metro') = 'text' then
    alter table vendors
      alter column metro type jsonb
      using case
        when metro is null or metro = '' then '[]'::jsonb
        else jsonb_build_array(metro)
      end;
  end if;
end $$;

alter table vendors alter column metro set default '[]'::jsonb;

-- ===== Phase 9: Trash bin / restore for Vendors and Maintenance Tickets =====
alter table vendors add column if not exists deleted_at timestamptz;
alter table maintenance_tickets add column if not exists deleted_at timestamptz;

-- ===== Phase 10: persist Property Status (New Transaction / Active / At risk) =====
alter table properties add column if not exists status text;

-- ===== Phase 11: HOA/Condo type indicator for owned properties =====
alter table properties add column if not exists hoa_type text;

-- ===== Phase 12: Comments & User Notes for Properties =====
alter table properties add column if not exists comments text;
alter table properties add column if not exists user_notes text;
