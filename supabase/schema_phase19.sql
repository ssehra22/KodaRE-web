-- KodaRE — Phase 19 schema: real photo/file attachments on Maintenance Tickets.
-- Replaces the fake "Add a photo" toggle in the mobile Field Staff flow (which only ever set
-- a boolean/counter on the ticket — no real file was ever captured, uploaded, or stored) with
-- a genuine attachment table + Storage bucket, separate from the existing "invoices" bucket
-- (vendor invoices) and "documents" bucket (per-property deeds/leases/etc.) — this one is
-- per-ticket, for photos of the issue and any other file a Field Staff or Office Staff person
-- wants to attach directly to a maintenance ticket.
-- Run this once in your Supabase project's SQL Editor, AFTER schema_phase18.sql.
-- Safe to re-run.

-- ================= Ticket attachments =================
create table if not exists ticket_attachments (
  id uuid primary key default gen_random_uuid(),
  ticket_id uuid not null references maintenance_tickets(id) on delete cascade,
  kind text not null default 'photo' check (kind in ('photo','file')),
  file_name text not null,
  file_path text not null,
  file_size integer,
  uploaded_by text,
  created_at timestamptz not null default now()
);
create index if not exists idx_ticket_attachments_ticket on ticket_attachments(ticket_id);

alter table ticket_attachments enable row level security;

-- Helper: which property does this ticket belong to? Used below so Field Staff can be scoped
-- to attachments on tickets for properties they're assigned to (same rule as the tickets
-- themselves, from Phase 18) without duplicating that join everywhere.
create or replace function public.ticket_property(tid uuid)
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select property_id from maintenance_tickets where id = tid;
$$;

drop policy if exists "select_ticket_attachments" on ticket_attachments;
create policy "select_ticket_attachments" on ticket_attachments for select using (
  current_role_is_admin_or_office() or current_user_assigned_to_property(public.ticket_property(ticket_id))
);
-- Field Staff can attach their own photos/files (e.g. from the mobile report flow or when
-- adding a completed-work photo later); Office/Admin can attach for any ticket.
drop policy if exists "insert_ticket_attachments" on ticket_attachments;
create policy "insert_ticket_attachments" on ticket_attachments for insert with check (
  current_role_is_admin_or_office() or current_user_assigned_to_property(public.ticket_property(ticket_id))
);
-- Deleting an attachment (mistake, wrong photo, etc.) is Office/Admin only — matches the
-- pattern used for Documents and Team Notes.
drop policy if exists "delete_ticket_attachments" on ticket_attachments;
create policy "delete_ticket_attachments" on ticket_attachments for delete using (
  current_role_is_admin_or_office()
);

-- ================= Storage bucket =================
-- Path convention: {ticket_id}/{timestamp}_{filename} — the policies below parse the ticket_id
-- back out of the path via storage.foldername() to apply the same property-scoping as the
-- table rows above.
insert into storage.buckets (id, name, public)
values ('ticket_attachments', 'ticket_attachments', false)
on conflict (id) do nothing;

drop policy if exists "select_ticket_attachments_storage" on storage.objects;
create policy "select_ticket_attachments_storage" on storage.objects for select using (
  bucket_id = 'ticket_attachments' and (
    current_role_is_admin_or_office()
    or current_user_assigned_to_property(public.ticket_property(((storage.foldername(name))[1])::uuid))
  )
);
drop policy if exists "insert_ticket_attachments_storage" on storage.objects;
create policy "insert_ticket_attachments_storage" on storage.objects for insert with check (
  bucket_id = 'ticket_attachments' and (
    current_role_is_admin_or_office()
    or current_user_assigned_to_property(public.ticket_property(((storage.foldername(name))[1])::uuid))
  )
);
drop policy if exists "delete_ticket_attachments_storage" on storage.objects;
create policy "delete_ticket_attachments_storage" on storage.objects for delete using (
  bucket_id = 'ticket_attachments' and current_role_is_admin_or_office()
);
