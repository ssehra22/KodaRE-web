-- KodaRE — Phase 14 schema: Loan detail fields for Properties (Scope §4.4 Loan & Debt Tracking).
-- Run this once in your Supabase project's SQL Editor (Project → SQL Editor → New query).
-- Safe to re-run.
-- Additive only — new nullable columns. Existing rows get null (shows as blank/editable).
--
-- Why: the property Loan tab used to read from a static, hardcoded sample list that only
-- covered a handful of properties and wasn't editable or persisted anywhere. It now reads
-- and writes directly to the property record (same admin-editable pattern as the rest of
-- Overview/Details), so any owned property can have its loan info entered and saved.
-- loan_initial and loan_remaining already existed (principal/current balance); this adds
-- the remaining loan detail fields.

alter table properties add column if not exists loan_lender text;
alter table properties add column if not exists loan_contact text;
alter table properties add column if not exists loan_acct_no text;
alter table properties add column if not exists loan_orig_date text;
alter table properties add column if not exists loan_rate numeric(5,3);
alter table properties add column if not exists loan_rate_type text;
alter table properties add column if not exists loan_term_mo integer;
alter table properties add column if not exists loan_maturity text;
alter table properties add column if not exists loan_payment numeric(10,2);
alter table properties add column if not exists loan_escrow numeric(10,2);
alter table properties add column if not exists loan_lien text;
alter table properties add column if not exists loan_prepay text;
