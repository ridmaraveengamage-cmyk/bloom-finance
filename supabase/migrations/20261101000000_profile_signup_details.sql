-- Bloom Finance: sign-up details on the profile (username, mobile number, country).
-- Run after 20261031000000_transaction_group_tags.sql.

alter table public.profiles
  add column username text check (username ~ '^[A-Za-z0-9._]{3,30}$'),
  add column phone    text check (phone ~ '^\+[1-9][0-9]{6,14}$'),          -- international format, e.g. +94771234567
  add column country  text check (char_length(country) between 2 and 60);
create unique index profiles_username_unique on public.profiles (lower(username));

-- Sign-up sends username, phone and country as user metadata. They are copied into the profile when valid.
-- A missing, badly formatted or already-taken username is left empty (sign-up still succeeds) and the app
-- asks the person to finish their profile. Google and Apple sign-ups always go through that step.
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare m jsonb := coalesce(new.raw_user_meta_data, '{}'); u text := m->>'username'; p text := m->>'phone'; c text := m->>'country';
begin
  if u is null or u !~ '^[A-Za-z0-9._]{3,30}$' or exists (select 1 from profiles where lower(username) = lower(u)) then u := null; end if;
  if p is null or p !~ '^\+[1-9][0-9]{6,14}$' then p := null; end if;
  if c is null or char_length(c) not between 2 and 60 then c := null; end if;
  insert into profiles (id, display_name, username, phone, country)
  values (new.id, left(coalesce(m->>'full_name', m->>'name', u, ''), 60), u, p, c)
  on conflict (id) do nothing;
  return new;
end $$;

-- Lets the sign-up form say "username taken" before submitting. Reveals only yes/no, never who has it.
create function public.username_available(p_username text) returns boolean
language sql stable security definer set search_path = public as $$
  select p_username ~ '^[A-Za-z0-9._]{3,30}$'
     and not exists (select 1 from profiles where lower(username) = lower(p_username));
$$;
revoke execute on function public.username_available(text) from public;
grant execute on function public.username_available(text) to anon, authenticated;
