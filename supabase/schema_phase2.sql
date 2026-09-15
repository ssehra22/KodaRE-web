create extension if not exists pgcrypto;

create or replace function set_updated_at() returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

alter table properties add column if not exists addr text;
alter table properties add column if not exists own text;
alter table properties add column if not exists beds integer;
alter table properties add column if not exists bedrooms integer;
alter table properties add column if not exists bathrooms numeric(3,1);
alter table properties add column if not exists sqft integer;
alter table properties add column if not exists year_built integer;
alter table properties add column if not exists levels integer;
alter table properties add column if not exists metro text;
alter table properties add column if not exists county text;
alter table properties add column if not exists municipality text;
alter table properties add column if not exists school_district text;
alter table properties add column if not exists zoning text;
alter table properties add column if not exists property_type text;
alter table properties add column if not exists type_style text;
alter table properties add column if not exists construction_material text;
alter table properties add column if not exists parking_type text;
alter table properties add column if not exists hoa_condo text;
alter table properties add column if not exists hoa_fee numeric(10,2);
alter table properties add column if not exists hoa_assoc_name text;
alter table properties add column if not exists hoa_assoc_contact text;
alter table properties add column if not exists tax_id text;
alter table properties add column if not exists mls text;
alter table properties add column if not exists operating_program text;
alter table properties add column if not exists house_manager text;
alter table properties add column if not exists llc text;
alter table properties add column if not exists buyer_llc text;
alter table properties add column if not exists purchase_date date;
alter table properties add column if not exists settlement_date date;
alter table properties add column if not exists purchase_price numeric(12,2);
alter table properties add column if not exists total_buyer_costs numeric(12,2);
alter table properties add column if not exists loan_initial numeric(12,2);
alter table properties add column if not exists loan_remaining numeric(12,2);
alter table properties add column if not exists value numeric(12,2);
alter table properties add column if not exists landlord text;
alter table properties add column if not exists rent numeric(10,2);
alter table properties add column if not exists lease_type text;
alter table properties add column if not exists mgmt_assoc_name text;
alter table properties add column if not exists mgmt_contact_phone text;
alter table properties add column if not exists mgmt_portal text;
alter table properties add column if not exists mgmt_portal_login text;
alter table properties add column if not exists updated_at timestamptz not null default now();

drop trigger if exists trg_properties_updated_at on properties;
create trigger trg_properties_updated_at
before update on properties
for each row execute function set_updated_at();

create table if not exists vendors (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  trade text,
  ytd numeric(12,2) default 0,
  primary_secondary text,
  pricing text,
  area text,
  metro text,
  after_hours text,
  contact text,
  phone text,
  email text,
  portal text,
  login text,
  licenses text,
  lic_exp date,
  ins_exp date,
  w9 text,
  referred_by text,
  quality text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
drop trigger if exists trg_vendors_updated_at on vendors;
create trigger trg_vendors_updated_at before update on vendors for each row execute function set_updated_at();

create table if not exists leases (
  id uuid primary key default gen_random_uuid(),
  property_id uuid not null references properties(id) on delete cascade,
  landlord text,
  rent numeric(10,2),
  term text,
  start_label text,
  end_label text,
  next_due date,
  status text,
  escalated boolean not null default false,
  lease_details jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
drop trigger if exists trg_leases_updated_at on leases;
create trigger trg_leases_updated_at before update on leases for each row execute function set_updated_at();

create table if not exists certificates (
  id uuid primary key default gen_random_uuid(),
  property_id uuid not null references properties(id) on delete cascade,
  type text not null,
  authority text,
  cert_no text,
  issue_date date,
  exp_date date,
  cadence text,
  status text,
  responsible text,
  cost numeric(10,2),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
drop trigger if exists trg_certificates_updated_at on certificates;
create trigger trg_certificates_updated_at before update on certificates for each row execute function set_updated_at();

create table if not exists inspections (
  id uuid primary key default gen_random_uuid(),
  property_id uuid not null references properties(id) on delete cascade,
  type text not null,
  inspector text,
  scheduled date,
  completed date,
  result text,
  findings text,
  corrective text,
  due date,
  cost numeric(10,2),
  next_due date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
drop trigger if exists trg_inspections_updated_at on inspections;
create trigger trg_inspections_updated_at before update on inspections for each row execute function set_updated_at();

create index if not exists idx_leases_property on leases(property_id);
create index if not exists idx_certificates_property on certificates(property_id);
create index if not exists idx_inspections_property on inspections(property_id);

alter table vendors enable row level security;
alter table leases enable row level security;
alter table certificates enable row level security;
alter table inspections enable row level security;

drop policy if exists "authenticated_select_vendors" on vendors;
create policy "authenticated_select_vendors" on vendors for select using (auth.role() = 'authenticated');
drop policy if exists "authenticated_insert_vendors" on vendors;
create policy "authenticated_insert_vendors" on vendors for insert with check (auth.role() = 'authenticated');
drop policy if exists "authenticated_update_vendors" on vendors;
create policy "authenticated_update_vendors" on vendors for update using (auth.role() = 'authenticated');
drop policy if exists "authenticated_delete_vendors" on vendors;
create policy "authenticated_delete_vendors" on vendors for delete using (auth.role() = 'authenticated');

drop policy if exists "authenticated_select_leases" on leases;
create policy "authenticated_select_leases" on leases for select using (auth.role() = 'authenticated');
drop policy if exists "authenticated_insert_leases" on leases;
create policy "authenticated_insert_leases" on leases for insert with check (auth.role() = 'authenticated');
drop policy if exists "authenticated_update_leases" on leases;
create policy "authenticated_update_leases" on leases for update using (auth.role() = 'authenticated');
drop policy if exists "authenticated_delete_leases" on leases;
create policy "authenticated_delete_leases" on leases for delete using (auth.role() = 'authenticated');

drop policy if exists "authenticated_select_certificates" on certificates;
create policy "authenticated_select_certificates" on certificates for select using (auth.role() = 'authenticated');
drop policy if exists "authenticated_insert_certificates" on certificates;
create policy "authenticated_insert_certificates" on certificates for insert with check (auth.role() = 'authenticated');
drop policy if exists "authenticated_update_certificates" on certificates;
create policy "authenticated_update_certificates" on certificates for update using (auth.role() = 'authenticated');
drop policy if exists "authenticated_delete_certificates" on certificates;
create policy "authenticated_delete_certificates" on certificates for delete using (auth.role() = 'authenticated');

drop policy if exists "authenticated_select_inspections" on inspections;
create policy "authenticated_select_inspections" on inspections for select using (auth.role() = 'authenticated');
drop policy if exists "authenticated_insert_inspections" on inspections;
create policy "authenticated_insert_inspections" on inspections for insert with check (auth.role() = 'authenticated');
drop policy if exists "authenticated_update_inspections" on inspections;
create policy "authenticated_update_inspections" on inspections for update using (auth.role() = 'authenticated');
drop policy if exists "authenticated_delete_inspections" on inspections;
create policy "authenticated_delete_inspections" on inspections for delete using (auth.role() = 'authenticated');
