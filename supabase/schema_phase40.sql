-- KodaRE — Phase 40 schema: emergency-ticket acknowledgment, independent of status.
-- Run this once in your Supabase project's SQL Editor (Project → SQL Editor → New query).
-- Safe to re-run.
--
-- Lets a Senior Admin acknowledge an open emergency ticket from the Approvals queue without
-- forcing its status to "In progress" -- some emergencies are seen/triaged before anyone has
-- actually started the work, and status should reflect real work state, not just "someone
-- looked at this." Acknowledging while also starting work (moving status to "In progress")
-- remains available as a separate action and sets this same column.

alter table maintenance_tickets
  add column if not exists emergency_acknowledged_at timestamptz;

comment on column maintenance_tickets.emergency_acknowledged_at is
  'When a Senior Admin acknowledged this emergency ticket from the Approvals queue,
   independent of status. Null means not yet acknowledged. Setting this does not by itself
   change ticket status.';
