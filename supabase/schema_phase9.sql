-- KodaRE — Phase 9 schema: Trash bin / restore safety net for Vendors and Maintenance Tickets.
-- Run this once in your Supabase project's SQL Editor (Project → SQL Editor → New query).
-- Safe to re-run.
-- Additive only — adds one nullable column to each table. Existing rows are unaffected
-- (deleted_at stays null, meaning "not deleted").
--
-- Why: deletes on vendors and tickets used to be permanent (hard delete). Going forward,
-- "Delete" instead stamps deleted_at with the current time and the row stays in the
-- database, hidden from normal views. A Senior Admin can browse Trash and Restore it
-- (clears deleted_at) or Delete permanently (a real, irreversible delete) at any time.

alter table vendors add column if not exists deleted_at timestamptz;
alter table maintenance_tickets add column if not exists deleted_at timestamptz;
