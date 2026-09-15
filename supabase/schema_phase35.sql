-- KodaRE — Phase 35 schema: make maintenance_tickets.description mandatory.
--
-- DO NOT RUN THIS YET. Four existing rows (MT-1027, MT-1029, MT-1030, MT-1031) currently have
-- a blank description — this constraint will reject the migration outright while any row is
-- blank. Fix those four first (Maintenance → open the ticket → Description is editable for
-- Senior Admin), then re-run the check below. Once it returns zero rows, run the ALTER TABLE
-- statement beneath it.
--
-- Why this is needed: the app-side form already required a description on desktop and in
-- bulk upload, but the mobile "Report an issue" flow's Describe step never actually enforced
-- it — its Continue button was wired to always be enabled regardless of what was typed. On
-- top of that, attaching a photo while on that step triggered a re-render that rebuilt the
-- description textarea from stale state, silently discarding anything already typed. Both are
-- fixed in index.html now (the Continue button is gated on non-empty text, and the re-render
-- captures the live textarea value first) — this constraint is the backstop so no future route
-- into this table, present or not yet written, can leave description blank.

-- Run this first — confirms the table is actually clean before the constraint goes on:
--   select id, ticket_no, title, description, created_at from maintenance_tickets
--   where description is null or trim(description) = '' order by created_at desc;

alter table maintenance_tickets
  add constraint maintenance_tickets_description_required
  check (description is not null and trim(description) <> '');

-- If you'd rather backfill the four existing rows with a placeholder instead of retyping the
-- real text (which can't be recovered — it was lost before it ever reached the database, not
-- stored anywhere to restore from), this does that. Only the four rows already confirmed
-- blank are touched. Run BEFORE the ALTER TABLE above, not after.
--   update maintenance_tickets
--   set description = 'No description on file — lost to a bug in the mobile report flow, fixed Aug 10, 2026.'
--   where id in (
--     'e587e7a6-8fa1-402f-ad83-e8f17fd4afe4', -- MT-1031
--     '2bb0038d-84a1-43be-9338-9b4ca457b58c', -- MT-1030
--     '947cb4a6-4bb3-4ada-86ca-d7221d560d77', -- MT-1029
--     'd81d0e63-af3b-4dd4-9a8e-851b77ba2766'  -- MT-1027
--   );
