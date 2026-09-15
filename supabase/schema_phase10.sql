-- KodaRE — Phase 10 schema: persist Property Status ("New Transaction" / "Active" / "At risk").
-- Run this once in your Supabase project's SQL Editor (Project → SQL Editor → New query).
-- Safe to re-run.
-- Additive only — one nullable column on properties. Existing rows get status = null, which
-- the app treats the same as "Active" (recomputed from open maintenance tickets as usual).
--
-- Why: Property Status used to be computed fresh every time the app loaded and was never
-- actually saved to the database — so a property sitting in "New Transaction" (formerly
-- "Onboarding") would silently flip back to "Active" the next time anyone reloaded the page.
-- This column lets "New Transaction" persist until the Acquisition/Lease checklist's Stage
-- reaches "Owned" or "Leased", at which point the app moves it to "Active" automatically
-- and saves that too.

alter table properties add column if not exists status text;
