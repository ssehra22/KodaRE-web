-- KodaRE — Phase 34 schema: let a signed-in user actually save their own name.
-- Run this once in your Supabase project's SQL Editor, AFTER schema_phase15.sql. Safe to re-run.
--
-- Bug this fixes: the "What should we call you?" prompt (added in the app) kept reappearing on
-- every sign-in/refresh, and the greeting kept showing an email address instead of a name, for
-- anyone who isn't Senior Admin. Root cause: schema_phase15.sql gave user_roles a SELECT policy
-- for your own row, an INSERT policy for your own row (self-registration on first login), and
-- an UPDATE policy — but that UPDATE policy is "current_role_is_admin()" only. There has never
-- been a policy letting a person update their OWN row. Every Office Staff/Field Staff person's
-- attempt to save their own name via `update user_roles set name = ... where user_id = ...` has
-- always matched zero rows under Row Level Security. Supabase/PostgREST does not treat "RLS
-- silently matched nothing" as an error, so the app had no way to know the write did nothing —
-- it looked exactly like a successful save from the client's point of view, which is why this
-- was hard to catch just by watching the UI. (The app-side fix adds a .select() to that update
-- and checks the returned row count, so a future policy regression like this will surface a real
-- error message instead of failing silently again — but the actual bug is the missing policy
-- below.)
--
-- This adds a narrow self-update policy scoped to id = auth.uid(), plus a trigger that keeps it
-- narrow: a non-admin can change their own name (and the new name_prompt_dismissed flag below),
-- but NOT their own role or email through this path — role changes still require Senior Admin
-- via User Management, exactly as before. Without that trigger, a simple "you can update your
-- own row" policy would also let anyone promote themselves to Senior Admin, which is not the
-- intent here.

-- Tracks whether this person clicked "Skip for now" on the name prompt, so declining it once
-- doesn't mean being asked again on every future sign-in (same nagging problem, different form).
-- A Senior Admin can still set a name for someone from User Management at any time — see the
-- app-side change alongside this migration.
alter table user_roles add column if not exists name_prompt_dismissed boolean not null default false;

drop policy if exists "user_roles_self_update_own_row" on user_roles;
create policy "user_roles_self_update_own_row" on user_roles
  for update using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create or replace function public.enforce_user_roles_self_update_columns()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if current_role_is_admin() then
    return new;
  end if;
  if new.role is distinct from old.role
     or new.email is distinct from old.email
     or new.user_id is distinct from old.user_id
  then
    raise exception 'You can only update your own name — role and email changes require Senior Admin (User Management)';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_enforce_user_roles_self_update on user_roles;
create trigger trg_enforce_user_roles_self_update
  before update on user_roles
  for each row execute function enforce_user_roles_self_update_columns();
