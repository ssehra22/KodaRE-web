-- KodaRE — Phase 36 schema: private per-user Notes on Maintenance tickets.
-- Run once in your Supabase project's SQL Editor, AFTER schema_phase20.sql (uses the
-- current_role_is_admin() helper added there). Safe to re-run.
--
-- What this is: the ticket drawer's existing "Notes" field is one shared value everyone can
-- see and edit — that field is being relabeled "Comments" in the app (no data migration
-- needed, same column). This adds a second, genuinely separate concept: a private note per
-- ticket per person. Each person only ever sees and edits their own row; Senior Admin can see
-- everyone's for oversight, but — unlike Comments — can't edit anyone else's note but their own.

create table if not exists ticket_user_notes (
  id uuid primary key default gen_random_uuid(),
  ticket_id uuid not null references maintenance_tickets(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  note text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
unique(ticket_id, user_id)
);

alter table ticket_user_notes enable row level security;

drop policy if exists "ticket_user_notes_select" on ticket_user_notes;
create policy "ticket_user_notes_select" on ticket_user_notes for select using (
  user_id = auth.uid() or current_role_is_admin()
);

-- Insert/update/delete are intentionally NOT opened up to current_role_is_admin() — admin
-- oversight in the app is read-only by design (see Phase 33 description). Only the row's own
-- author can ever write to it.
drop policy if exists "ticket_user_notes_insert_own" on ticket_user_notes;
create policy "ticket_user_notes_insert_own" on ticket_user_notes for insert with check (
  user_id = auth.uid()
);

drop policy if exists "ticket_user_notes_update_own" on ticket_user_notes;
create policy "ticket_user_notes_update_own" on ticket_user_notes for update using (
  user_id = auth.uid()
) with check (
  user_id = auth.uid()
);

drop policy if exists "ticket_user_notes_delete_own" on ticket_user_notes;
create policy "ticket_user_notes_delete_own" on ticket_user_notes for delete using (
  user_id = auth.uid()
);

create or replace function public.touch_ticket_user_notes_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_touch_ticket_user_notes on ticket_user_notes;
create trigger trg_touch_ticket_user_notes before update on ticket_user_notes
for each row execute function touch_ticket_user_notes_updated_at();
