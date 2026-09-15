-- KodaRE — Phase 4 schema: human-readable ticket numbers for Maintenance.
-- Run this once in your Supabase project's SQL Editor (Project → SQL Editor → New query).
-- Safe to re-run.
-- Additive only — doesn't touch any existing data.
--
-- Why: maintenance_tickets.id is a UUID (needed internally for relationships/security),
-- which isn't practical to read aloud, type into an email, or reference with a vendor.
-- This adds a short sequential number (MT-1001, MT-1002, ...) purely for people to
-- reference a specific ticket by, shown in the ticket detail view. The UUID stays the
-- real primary key underneath — nothing about how tickets are stored or linked changes.

create sequence if not exists maintenance_ticket_no_seq start 1001;

-- Adding this column with a DEFAULT nextval(...) backfills every existing ticket with its
-- own sequential number in the same step (Postgres evaluates the default once per row for
-- volatile defaults like nextval()), so nothing needs a separate backfill pass.
alter table maintenance_tickets add column if not exists ticket_no integer not null default nextval('maintenance_ticket_no_seq');

create unique index if not exists idx_maintenance_tickets_ticket_no on maintenance_tickets(ticket_no);
