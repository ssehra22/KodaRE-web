-- KodaRE — data cleanup: clear fabricated compliance data (certificates & inspections)
-- Same root cause as the loan cleanup: the Compliance report was showing certificate and
-- inspection records (Fire safety certs, Group home/IDD waiver licenses, Certificates of
-- Occupancy, various inspections) that are leftover sample/placeholder rows from the original
-- prototype, seeded into the live database and never replaced with real records.
-- This DELETES every row in both tables (unlike the loan cleanup, these are standalone
-- records, not optional fields on a property, so there's no "blank" version to keep).
-- Confirmed with Sonia (Aug 3, 2026). Safe to re-run (idempotent — deleting an empty table is a no-op).

delete from inspections;
delete from certificates;
