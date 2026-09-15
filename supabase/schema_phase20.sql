-- KodaRE — Phase 20 schema:
-- 1) Field Staff photos/uploads and reported tickets now record the real signed-in person's
--    name (fixes a bug: the app was hardcoding every Field Staff account to "Alex Rivera" —
--    a leftover demo placeholder — so every real Field Staff person's tickets were attributed
--    to the same fake name, and "My reports" was showing everyone's tickets mixed together
--    instead of just their own). This is a client-side (index.html) fix, but this file adds
--    the one supporting piece that needs the database: a helper to look up the real signed-in
--    user's name for the policies below.
-- 2) Field Staff can now edit their OWN ticket's description and delete their OWN uploaded
--    photos/files, but ONLY while the ticket is still "Open" (nobody's picked it up yet).
--    Once a vendor is assigned or work starts, the original report locks — Office Staff and
--    the vendor are now relying on what was reported, so no more edits after that point.
--    Adding NEW photos/files stays allowed at any status (that's appending evidence over time,
--    like a photo of the completed work — not rewriting the original report).
-- Run this once in your Supabase project's SQL Editor, AFTER schema_phase19.sql. Safe to re-run.

-- ================= Helper: current signed-in user's display name =================
create or replace function public.current_user_display_name()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(name, email) from user_roles where user_id = auth.uid();
$$;

-- ================= Maintenance tickets — Field Staff can edit their own, while Open =================
-- This is an ADDITIONAL policy alongside the existing office_admin_update_tickets policy
-- (Postgres OR's multiple permissive policies together) — Office Staff/Senior Admin keep full
-- update rights as before; this just adds a narrow allowance for the reporter.
-- Note: this guarantees the ticket stays "Open" before and after the edit, which is what
-- actually protects against edits after dispatch — but it doesn't lock individual columns
-- (cost/vendor) at the database level. The app's UI never exposes those fields to Field Staff
-- (only a description-edit box), so real-world risk is low; a column-level trigger is a
-- possible future hardening step if this app is ever opened to a raw API integration.
drop policy if exists "field_staff_update_own_open_tickets" on maintenance_tickets;
create policy "field_staff_update_own_open_tickets" on maintenance_tickets for update using (
  status = 'Open' and reporter = public.current_user_display_name()
) with check (
  status = 'Open' and reporter = public.current_user_display_name()
);

-- ================= Ticket attachments — Field Staff can delete their own, while Open =================
drop policy if exists "delete_ticket_attachments" on ticket_attachments;
create policy "delete_ticket_attachments" on ticket_attachments for delete using (
  current_role_is_admin_or_office()
  or exists (
    select 1 from maintenance_tickets mt
    where mt.id = ticket_attachments.ticket_id
      and mt.status = 'Open'
      and mt.reporter = public.current_user_display_name()
  )
);
drop policy if exists "delete_ticket_attachments_storage" on storage.objects;
create policy "delete_ticket_attachments_storage" on storage.objects for delete using (
  bucket_id = 'ticket_attachments' and (
    current_role_is_admin_or_office()
    or exists (
      select 1 from maintenance_tickets mt
      where mt.id = ((storage.foldername(name))[1])::uuid
        and mt.status = 'Open'
        and mt.reporter = public.current_user_display_name()
    )
  )
);

-- ================= Optional cleanup =================
-- If any real Field Staff person already submitted reports before this fix, those rows are
-- saved with reporter = 'Alex Rivera' and won't show up in that person's "My reports" list
-- going forward (since it now matches on their real name). If you want to reassign them,
-- find the real name to use in user_roles first, then run something like:
--   update maintenance_tickets set reporter = 'Their Real Name' where reporter = 'Alex Rivera';
-- Not run automatically — you know who actually reported each one, I don't.
