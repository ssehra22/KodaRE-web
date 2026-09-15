-- KodaRE — Phase 17 schema: real Documents storage, Team Notes, and the Life of Appliances
-- reference table — moves these three out of browser-only localStorage into Supabase.
-- Run this once in your Supabase project's SQL Editor, AFTER schema_phase16.sql.
-- Safe to re-run.

-- ================= Documents (Scope §4.1 Property Documents) =================
create table if not exists documents (
  id uuid primary key default gen_random_uuid(),
  property_id uuid not null references properties(id) on delete cascade,
  doc_type text not null,
  file_name text not null,
  file_path text not null,
  file_size integer,
  note text,
  uploaded_by text,
  created_at timestamptz not null default now()
);
create index if not exists idx_documents_property on documents(property_id);

alter table documents enable row level security;

drop policy if exists "authenticated_select_documents" on documents;
create policy "authenticated_select_documents" on documents for select using (auth.role() = 'authenticated');
drop policy if exists "office_admin_insert_documents" on documents;
create policy "office_admin_insert_documents" on documents for insert with check (current_role_is_admin_or_office());
drop policy if exists "office_admin_update_documents" on documents;
create policy "office_admin_update_documents" on documents for update using (current_role_is_admin_or_office());
drop policy if exists "admin_delete_documents" on documents;
create policy "admin_delete_documents" on documents for delete using (current_role_is_admin());

-- Storage bucket for property documents (deeds, leases, COs, inspection reports, photos).
insert into storage.buckets (id, name, public)
values ('documents', 'documents', false)
on conflict (id) do nothing;

drop policy if exists "office_admin_read_documents" on storage.objects;
create policy "office_admin_read_documents" on storage.objects for select
  using (bucket_id = 'documents' and current_role_is_admin_or_office());
drop policy if exists "office_admin_upload_documents" on storage.objects;
create policy "office_admin_upload_documents" on storage.objects for insert
  with check (bucket_id = 'documents' and current_role_is_admin_or_office());
drop policy if exists "office_admin_delete_documents_storage" on storage.objects;
create policy "office_admin_delete_documents_storage" on storage.objects for delete
  using (bucket_id = 'documents' and current_role_is_admin_or_office());

-- ================= Team Notes =================
create table if not exists team_notes (
  id uuid primary key default gen_random_uuid(),
  tag text not null default 'Note',
  pinned boolean not null default false,
  text text not null,
  created_by text,
  created_at timestamptz not null default now()
);

alter table team_notes enable row level security;

drop policy if exists "authenticated_select_team_notes" on team_notes;
create policy "authenticated_select_team_notes" on team_notes for select using (auth.role() = 'authenticated');
drop policy if exists "office_admin_insert_team_notes" on team_notes;
create policy "office_admin_insert_team_notes" on team_notes for insert with check (current_role_is_admin_or_office());
drop policy if exists "admin_delete_team_notes" on team_notes;
create policy "admin_delete_team_notes" on team_notes for delete using (current_role_is_admin());

-- ================= Life of Appliances reference table =================
-- Reuses the existing reference_lists table (same pattern already used for Service Category
-- and Service Type) — key 'LIFE_TABLE', data = {component: [avg_lifespan_years, replacement_cost]}.
-- Seeded here so the values match the app's hardcoded defaults; on conflict does nothing, so
-- this never overwrites edits you've already made in the Assumptions screen.
insert into reference_lists (key, data) values (
  'LIFE_TABLE',
  '{"HVAC":[25,10000],"Furnace":[20,6000],"Water heater":[15,2000],"Refrigerator":[10,1200],"Gas/electric range":[15,1200],"Oven":[15,1200],"Dishwasher":[10,800],"Microwave":[8,600],"Washing machine":[12,800],"Dryer":[12,800],"Carpeting":[10,0],"Roof":[25,11000]}'::jsonb
) on conflict (key) do nothing;
