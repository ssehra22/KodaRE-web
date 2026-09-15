-- KodaRE — Phase 37 schema: drop the payment_status check constraint on maintenance_tickets.
-- Run this once in your Supabase project's SQL Editor (Project → SQL Editor → New query).
-- Safe to re-run.
--
-- Why: Payment Status was just wired up as a live Reference List (Assumptions > Reference
-- Lists > Payment Status) — Senior Admin can now add/remove/reorder its values from the app
-- itself, same as Metro, Vendor Work Quality, Property Stage, etc. already work. Those columns
-- were deliberately never given a database-level check constraint, for exactly this reason: a
-- fixed constraint has no way to know about a value an admin adds later through the UI, so it
-- keeps rejecting saves the app itself is happy to allow. payment_status still had one left
-- over from Phase 1 (schema.sql), written before Reference Lists existed — which is why saving
-- a ticket with a newly-added Payment Status value fails with:
--   Save failed: new row for relation "maintenance_tickets" violates check constraint
--   "maintenance_tickets_payment_status_check"
-- This drops that constraint so Payment Status behaves like every other live Reference List —
-- any value validation now happens in the app (via the Reference List itself), not in Postgres.

alter table maintenance_tickets drop constraint if exists maintenance_tickets_payment_status_check;
