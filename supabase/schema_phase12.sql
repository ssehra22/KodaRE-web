-- KodaRE — Phase 12 schema: Comments & User Notes for Properties.
-- Run this once in your Supabase project's SQL Editor (Project → SQL Editor → New query).
-- Safe to re-run.
-- Additive only — two nullable text columns. Existing rows get null (shows as blank).
--
-- Why: the property Details tab replaced House Manager / Operating Program with a
-- Comments field (visible to other users) and a User Notes field (private to the
-- entering user), matching the same Comments/User Notes pattern already used on
-- Vendors. These two columns store that data.

alter table properties add column if not exists comments text;
alter table properties add column if not exists user_notes text;
