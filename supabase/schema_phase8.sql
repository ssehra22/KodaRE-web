-- KodaRE — Phase 8 schema: Vendor Metro becomes multi-select (Scope §4.9).
-- Run this once in your Supabase project's SQL Editor (Project → SQL Editor → New query).
-- Safe to re-run.
-- Converts the existing `vendors.metro` column from a single text value to a jsonb array,
-- so a vendor can serve more than one Metro. Any existing single value (e.g. "Harrisburg")
-- is automatically converted into a one-element array (["Harrisburg"]) — nothing is lost.

alter table vendors
  alter column metro type jsonb
  using case
    when metro is null or metro = '' then '[]'::jsonb
    else jsonb_build_array(metro)
  end;

alter table vendors alter column metro set default '[]'::jsonb;
