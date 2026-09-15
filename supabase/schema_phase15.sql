-- KodaRE — Phase 15 schema: Real user roles (Scope §3.2 Permissions Matrix).
-- Run this once in your Supabase project's SQL Editor (Project → SQL Editor → New query).
-- Safe to re-run.
--
-- Why: Supabase's Authentication panel manages logins (email/password) but has no concept
-- of KodaRE's three roles (Senior Admin / Office Staff / Field Staff). Today the role switcher
-- in the app top bar is just a UI convenience — it isn't tied to who's actually signed in, and
-- anyone signed in could click it and get Senior Admin's view. This creates a real roles table
-- and locks the app down to read each signed-in user's actual assigned role.
--
-- How role assignment works day to day:
--   1. You still create the person's login the same way you do today — Supabase dashboard →
--      Authentication → Users → Add user (email + password).
--   2. The first time that person signs into KodaRE, the app automatically adds them to the
--      list below with the safe default role "office" (Office Staff).
--   3. You (Senior Admin) open KodaRE → User Management and change their role there. That's
--      the "R/W Senior Admin only" User Management capability from §3.2 — enforced below.
--
-- role values match the app's internal role keys: 'admin' (Senior Admin), 'office' (Office
-- Staff), 'caregiver' (Field Staff).

create table if not exists user_roles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  email text not null,
  name text,
  role text not null default 'office' check (role in ('admin','office','caregiver')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists user_roles_email_idx on user_roles (lower(email));

-- Helper functions used by RLS policies here and in phase16. security definer so they can read
-- user_roles even from inside policies ON user_roles itself, without infinite recursion.
create or replace function public.current_user_role()
returns text
language sql
security definer
stable
set search_path = public
as $$
  select role from user_roles where user_id = auth.uid();
$$;

create or replace function public.current_role_is_admin()
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select coalesce((select role from user_roles where user_id = auth.uid()) = 'admin', false);
$$;

create or replace function public.current_role_is_admin_or_office()
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select coalesce((select role from user_roles where user_id = auth.uid()) in ('admin','office'), false);
$$;

alter table user_roles enable row level security;

drop policy if exists "user_roles_select_self_or_admin" on user_roles;
create policy "user_roles_select_self_or_admin" on user_roles
  for select using (auth.uid() = user_id or current_role_is_admin());

-- First-login self-registration: a signed-in user may create their OWN row, but only ever
-- with the safe default role 'office' — they cannot self-promote to admin or Field Staff.
drop policy if exists "user_roles_self_insert_office_only" on user_roles;
create policy "user_roles_self_insert_office_only" on user_roles
  for insert with check (auth.uid() = user_id and role = 'office');

drop policy if exists "user_roles_admin_insert_any" on user_roles;
create policy "user_roles_admin_insert_any" on user_roles
  for insert with check (current_role_is_admin());

drop policy if exists "user_roles_admin_update_any" on user_roles;
create policy "user_roles_admin_update_any" on user_roles
  for update using (current_role_is_admin());

drop policy if exists "user_roles_admin_delete_any" on user_roles;
create policy "user_roles_admin_delete_any" on user_roles
  for delete using (current_role_is_admin());

-- IMPORTANT — one-time manual step after running this migration:
-- This table starts empty, so there is no admin yet and the chicken-and-egg "only an admin can
-- promote someone to admin" rule would otherwise lock everyone out. Run this once, filling in
-- your own login email, to seed yourself as the first Senior Admin:
--
--   insert into user_roles (user_id, email, name, role)
--   select id, email, 'Sonia Sehra', 'admin' from auth.users where email = 'YOUR-LOGIN-EMAIL@example.com'
--   on conflict (user_id) do update set role = 'admin';
--
-- After that, everyone else can be managed from KodaRE's User Management screen (Senior Admin only).
