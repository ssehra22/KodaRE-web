-- Phase 33 — verified ticket creator, separate from the editable "Reporter" name.
--
-- Why this exists: the "Reporter" field on a maintenance ticket was, until this phase, an
-- editable free-text field that defaulted to a hardcoded name ("Sonia S.") in the desktop
-- Add Ticket form regardless of who was actually signed in. That's fixed on the app side
-- (index.html now reads the signed-in user through one function, currentUserDisplayName(),
-- and the Reporter field is read-only). This migration adds the piece that can't be fixed
-- in the app alone: a column that records the *actual authenticated identity* of whoever
-- created the ticket, captured automatically at insert time, that Reporter can be checked
-- against later. Reporter stays human-editable (someone logging a ticket on a resident's
-- behalf may legitimately want it to say someone else's name) — created_by_email is not
-- editable anywhere in the app and is the more trustworthy of the two for any compliance
-- question about who actually used the system.
--
-- Existing tickets (everything created before this column existed) will have
-- created_by_email = null. There is no way to reconstruct that after the fact — nothing in
-- the schema up to this point recorded which authenticated user created a given row, so a
-- ticket's true creator for historical rows can only come from someone's own memory of who
-- logged it, not from the database. See the review query at the bottom of this file.

alter table maintenance_tickets add column if not exists created_by_email text;

comment on column maintenance_tickets.created_by_email is
  'Email of the authenticated user who created this ticket, captured automatically from the session at insert time. Null for tickets created before Phase 33 (Aug 2026) or Reporter cannot be relied on for verification. Not editable from the UI -- use this, not Reporter, when attribution needs to be verifiable.';

-- ---------------------------------------------------------------------------------------
-- Review query -- run this yourself in the Supabase SQL editor to see which existing
-- tickets have no verified creator on file (i.e. every ticket created before this phase).
-- This does NOT tell you who actually created each one -- it only tells you which rows are
-- relying solely on the free-text Reporter field, so you know which ones to sanity-check
-- against your own memory of who logged them, particularly any attributed to "Sonia S."
-- that you don't recall entering yourself.
-- ---------------------------------------------------------------------------------------
-- select id, ticket_no, reporter, title, created_at
-- from maintenance_tickets
-- where created_by_email is null
-- order by created_at desc;

-- Narrower version -- just the ones that say "Sonia S." specifically, oldest first so you
-- can cross-check against when multi-user access actually started:
-- select id, ticket_no, reporter, title, created_at
-- from maintenance_tickets
-- where reporter = 'Sonia S.' and created_by_email is null
-- order by created_at asc;
