-- Bloom Finance: cloud sync. Each account's Bloom data is stored as one document.
-- Only the signed-in owner can read or change their row (Row Level Security).
-- "version" increases on every save so one device can never silently overwrite another's newer changes.
create table public.user_app_state (
  user_id    uuid primary key default auth.uid() references auth.users(id) on delete cascade,
  data       jsonb not null,
  version    bigint not null default 1 check (version > 0),
  device     text check (char_length(device) <= 80),
  updated_at timestamptz not null default now(),
  check (pg_column_size(data) < 5000000)
);
create function public.touch_app_state() returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  if new.version <> old.version + 1 then raise exception 'Version must increase by one'; end if;
  return new;
end $$;
create trigger app_state_touch before update on public.user_app_state for each row execute function public.touch_app_state();
alter table public.user_app_state enable row level security;
create policy app_state_own on public.user_app_state for all using (user_id = auth.uid()) with check (user_id = auth.uid());
revoke all on public.user_app_state from anon;
grant select, insert, update, delete on public.user_app_state to authenticated;
