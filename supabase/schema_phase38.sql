-- KodaRE — Phase 38 schema: target completion date on Maintenance tickets.
-- Run this once in your Supabase project's SQL Editor (Project → SQL Editor → New query).
-- Safe to re-run.
--
-- Adds a user-entered "target completion" date to maintenance_tickets, separate from the
-- app's auto-computed "actual completion" date (which is derived from the ticket's activity
-- log once it reaches Completed/Closed, and is never directly editable). Target completion is
-- the date staff expect/plan for the work to be done by, set from the ticket drawer or the
-- "New ticket" form.

alter table maintenance_tickets
  add column if not exists target_completion_date date;

comment on column maintenance_tickets.target_completion_date is
  'User-entered expected/target completion date. Distinct from actual completion, which is
   derived automatically from the activity log and not stored as its own column.';
