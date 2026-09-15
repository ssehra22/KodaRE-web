-- KodaRE — Phase 11 schema: HOA/Condo type indicator for owned properties.
-- Run this once in your Supabase project's SQL Editor (Project → SQL Editor → New query).
-- Safe to re-run.
-- Additive only — one nullable column. Existing rows get hoa_type = null (shows as
-- "— select —" until someone picks HOA or Condo).
--
-- Why: HOA/Condo stays a Yes/No field (per Sonia's direction), but "Yes" alone doesn't say
-- whether it's an HOA or a Condo association — which matters for fees, contacts, and portal
-- info. This column stores that distinction. It only surfaces in the UI once HOA/Condo = Yes.

alter table properties add column if not exists hoa_type text;
