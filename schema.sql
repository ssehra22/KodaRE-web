-- KodaRE — Phase 1 schema: Maintenance module
-- Run this once in your Supabase project's SQL Editor (Project → SQL Editor → New query).
-- Safe to re-run: uses "if not exists" / "or replace" throughout.

create extension if not exists pgcrypto;

-- Minimal properties table — just enough for the Maintenance module to reference a
-- property by id/name. The full Properties module (address, ownership, sqft, etc.)
-- is a later phase; this table will be extended (not replaced) when that phase lands.
create table if not exists properties (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  created_at timestamptz not null default now()
);

create table if not exists maintenance_tickets (
  id uuid primary key default gen_random_uuid(),
  property_id uuid not null references properties(id) on delete restrict,
  title text not null,
  description text,
  notes text not null default '',
  status text not null default 'Open' check (status in ('Open','In progress','Completed','Closed')),
  urgency text not null check (urgency in ('Emergency','Urgent','Low')),
  service_category text,
  service_type text,
  vendor text,
  cost numeric(10,2),
  invoice_number text,
  invoice_file_url text,
  invoice_file_name text,
  invoice_total numeric(10,2),
  payment_status text check (payment_status is null or payment_status in ('Match Proposed','Ready for Payment','Paid')),
  reporter text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Activity/audit trail per ticket (replaces the prototype's static "days ago" log —
-- real timestamps are stored, and "3d ago" style text is computed client-side at render time).
create table if not exists maintenance_ticket_activity (
  id uuid primary key default gen_random_uuid(),
  ticket_id uuid not null references maintenance_tickets(id) on delete cascade,
  action text not null,
  detail text,
  created_at timestamptz not null default now()
);

create index if not exists idx_maintenance_tickets_property on maintenance_tickets(property_id);
create index if not exists idx_maintenance_ticket_activity_ticket on maintenance_ticket_activity(ticket_id);

-- Keep updated_at current on every edit
create or replace function set_updated_at() returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

drop trigger if exists trg_maintenance_tickets_updated_at on maintenance_tickets;
create trigger trg_maintenance_tickets_updated_at
before update on maintenance_tickets
for each row execute function set_updated_at();

-- Row Level Security: internal team only (single shared role for now, per current scope).
-- Any signed-in user can read/write; there is no public/anonymous access.
alter table properties enable row level security;
alter table maintenance_tickets enable row level security;
alter table maintenance_ticket_activity enable row level security;

drop policy if exists "authenticated_select_properties" on properties;
create policy "authenticated_select_properties" on properties for select using (auth.role() = 'authenticated');
drop policy if exists "authenticated_insert_properties" on properties;
create policy "authenticated_insert_properties" on properties for insert with check (auth.role() = 'authenticated');
drop policy if exists "authenticated_update_properties" on properties;
create policy "authenticated_update_properties" on properties for update using (auth.role() = 'authenticated');

drop policy if exists "authenticated_select_tickets" on maintenance_tickets;
create policy "authenticated_select_tickets" on maintenance_tickets for select using (auth.role() = 'authenticated');
drop policy if exists "authenticated_insert_tickets" on maintenance_tickets;
create policy "authenticated_insert_tickets" on maintenance_tickets for insert with check (auth.role() = 'authenticated');
drop policy if exists "authenticated_update_tickets" on maintenance_tickets;
create policy "authenticated_update_tickets" on maintenance_tickets for update using (auth.role() = 'authenticated');
drop policy if exists "authenticated_delete_tickets" on maintenance_tickets;
create policy "authenticated_delete_tickets" on maintenance_tickets for delete using (auth.role() = 'authenticated');

drop policy if exists "authenticated_select_activity" on maintenance_ticket_activity;
create policy "authenticated_select_activity" on maintenance_ticket_activity for select using (auth.role() = 'authenticated');
drop policy if exists "authenticated_insert_activity" on maintenance_ticket_activity;
create policy "authenticated_insert_activity" on maintenance_ticket_activity for insert with check (auth.role() = 'authenticated');

-- Storage bucket for invoice files (drag-and-drop / click-to-upload attachments).
-- Creates a private bucket; only signed-in users can upload/read.
insert into storage.buckets (id, name, public)
values ('invoices', 'invoices', false)
on conflict (id) do nothing;

drop policy if exists "authenticated_read_invoices" on storage.objects;
create policy "authenticated_read_invoices" on storage.objects for select
  using (bucket_id = 'invoices' and auth.role() = 'authenticated');
drop policy if exists "authenticated_upload_invoices" on storage.objects;
create policy "authenticated_upload_invoices" on storage.objects for insert
  with check (bucket_id = 'invoices' and auth.role() = 'authenticated');
drop policy if exists "authenticated_delete_invoices" on storage.objects;
create policy "authenticated_delete_invoices" on storage.objects for delete
  using (bucket_id = 'invoices' and auth.role() = 'authenticated');

-- Seed your real properties here once — replace with your actual property names,
-- or add them later from the app once the Properties module is wired up (Phase 2).
-- insert into properties (name) values ('Fox-1'), ('Monticello');
