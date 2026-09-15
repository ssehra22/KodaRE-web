-- KodaRE — Phase 28 schema: lightweight error log (adapted from reshab-platform's error_log
-- pattern, scaled down for KodaRE's single-file/no-server-actions architecture).
--
-- reshab writes errors via server-side code running with a service-role key, which bypasses
-- RLS entirely. KodaRE has no equivalent server-side layer for this — every write comes
-- straight from the browser using the signed-in person's own session — so this table needs an
-- INSERT policy that any authenticated user can use (Field Staff included: an error they hit
-- is exactly the kind least likely to get reported to you directly). Reading and resolving
-- stays Senior Admin only, since message text can include property/vendor/ticket details.
--
-- Every " failed: " toast anywhere in the app (save/delete/restore/upload failures — the
-- existing convention almost every error.message already goes through) is now written here
-- automatically by toast()/logError() in index.html. Nothing needs to change per-feature.
--
-- Run this once in your Supabase project's SQL Editor. Safe to re-run.

create table if not exists public.error_log (
  id          uuid primary key default gen_random_uuid(),
  at          timestamptz not null default now(),
  message     text not null,
  path        text,               -- which screen it happened on, e.g. 'tickets', 'vendors'
  user_id     uuid references auth.users(id) on delete set null,
  user_email  text,
  user_role   text,
  resolved_at timestamptz,
  resolved_by uuid references auth.users(id) on delete set null
);

comment on table public.error_log is
  'Background failures, auto-logged from every " failed: " toast in index.html. Senior Admin read/resolve only. See Phase 28.';

create index if not exists error_log_recent_idx on public.error_log (at desc);
create index if not exists error_log_open_idx on public.error_log (at desc) where resolved_at is null;

alter table public.error_log enable row level security;

drop policy if exists "authenticated insert error log" on public.error_log;
create policy "authenticated insert error log" on public.error_log
  for insert
  with check (auth.role() = 'authenticated');

drop policy if exists "senior admin read error log" on public.error_log;
create policy "senior admin read error log" on public.error_log
  for select using (current_role_is_admin());

drop policy if exists "senior admin resolve error log" on public.error_log;
create policy "senior admin resolve error log" on public.error_log
  for update using (current_role_is_admin())
  with check (current_role_is_admin());

grant select, insert, update on public.error_log to authenticated;
