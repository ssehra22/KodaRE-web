-- KodaRE — Phase 39 schema: "paid via credit card" indicator on Maintenance tickets.
-- Run this once in your Supabase project's SQL Editor (Project → SQL Editor → New query).
-- Safe to re-run.
--
-- Adds a simple yes/no indicator, shown as a checkbox column immediately right of Payment
-- in the Maintenance table, for whether this ticket's payment was made via credit card.
-- Independent of the Payment status value itself.

alter table maintenance_tickets
  add column if not exists paid_by_credit_card boolean not null default false;

comment on column maintenance_tickets.paid_by_credit_card is
  'Whether this ticket''s payment was made via credit card. Simple indicator, independent of
   payment_status.';
