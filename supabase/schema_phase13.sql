-- KodaRE — Phase 13 schema: Trash bin / restore for Properties.
-- Run this once in your Supabase project's SQL Editor (Project → SQL Editor → New query).
-- Safe to re-run.
-- Additive only — one nullable timestamp column, same pattern already used for
-- vendors.deleted_at and maintenance_tickets.deleted_at (see schema_phase9.sql).
--
-- Why: Senior Admin can now delete a property from the prototype. Deleting soft-deletes
-- it (sets deleted_at) so it moves to the Trash view, where it can be restored or
-- permanently deleted — it does not disappear immediately. Maintenance tickets, leases,
-- certificates, etc. that reference the property are left as-is (same non-cascading
-- behavior as deleting a vendor); they'll just show "—" for the property name until/unless
-- the property is restored.

alter table properties add column if not exists deleted_at timestamptz;
