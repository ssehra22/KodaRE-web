-- KodaRE — data cleanup: clear fabricated loan/debt data (all properties)
-- The Financial report and each property's Loan tab were showing loan lender, balance,
-- rate, and maturity figures that were never real — leftover sample/placeholder values from
-- the original prototype that got carried into the live database when it was first seeded.
-- Confirmed with Sonia (Aug 3, 2026): clear ALL loan fields, ALL properties, so the app goes
-- honestly blank until real loan data is entered per property via its Loan tab.
-- Safe to re-run (idempotent — setting already-null columns to null is a no-op).

update properties set
  loan_initial   = null,
  loan_remaining = null,
  loan_lender    = null,
  loan_contact   = null,
  loan_acct_no   = null,
  loan_orig_date = null,
  loan_rate      = null,
  loan_rate_type = null,
  loan_term_mo   = null,
  loan_maturity  = null,
  loan_payment   = null,
  loan_escrow    = null,
  loan_lien      = null,
  loan_prepay    = null;
