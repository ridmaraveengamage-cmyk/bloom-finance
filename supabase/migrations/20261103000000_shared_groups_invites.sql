-- Bloom Finance: real shared groups with invite links.
-- A shared group is one document (data) that every member can read and edit; membership and invites are
-- only changed through the functions below, so people can't add themselves or others directly.
create table public.bloom_groups (
  id         uuid primary key default gen_random_uuid(),
  owner      uuid not null default auth.uid() references auth.users(id) on delete cascade,
  data       jsonb not null check (pg_column_size(data) < 2000000),
  version    bigint not null default 1 check (version > 0),
  updated_at timestamptz not null default now()
);
create table public.bloom_group_members (
  group_id  uuid not null references public.bloom_groups(id) on delete cascade,
  user_id   uuid not null references auth.users(id) on delete cascade,
  role      text not null default 'member' check (role in ('owner','member')),
  joined_at timestamptz not null default now(),
  primary key (group_id, user_id)
);
create table public.bloom_group_invites (
  code       text primary key check (char_length(code) between 10 and 40),
  group_id   uuid not null references public.bloom_groups(id) on delete cascade,
  created_by uuid not null references auth.users(id) on delete cascade,
  member_ref text check (char_length(member_ref) <= 40),
  expires_at timestamptz not null default now() + interval '7 days',
  used_by    uuid references auth.users(id) on delete set null,
  used_at    timestamptz
);
create index bloom_group_members_user on public.bloom_group_members(user_id);

create function public.is_bloom_member(g uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.bloom_group_members where group_id = g and user_id = auth.uid())
$$;

create function public.bloom_groups_guard() returns trigger language plpgsql as $$
begin
  if new.owner <> old.owner then raise exception 'The owner can''t be changed'; end if;
  if new.version <> old.version + 1 then raise exception 'Version must increase by one'; end if;
  new.updated_at := now();
  return new;
end $$;
create trigger bloom_groups_guard before update on public.bloom_groups for each row execute function public.bloom_groups_guard();

alter table public.bloom_groups enable row level security;
alter table public.bloom_group_members enable row level security;
alter table public.bloom_group_invites enable row level security;
create policy bloom_groups_read   on public.bloom_groups for select using (public.is_bloom_member(id));
create policy bloom_groups_edit   on public.bloom_groups for update using (public.is_bloom_member(id)) with check (public.is_bloom_member(id));
create policy bloom_groups_delete on public.bloom_groups for delete using (owner = auth.uid());
create policy bloom_members_read  on public.bloom_group_members for select using (public.is_bloom_member(group_id));
-- invites: no direct access at all; only through the functions
revoke all on public.bloom_groups, public.bloom_group_members, public.bloom_group_invites from anon;
grant select, update, delete on public.bloom_groups to authenticated;
grant select on public.bloom_group_members to authenticated;

-- helper: set or clear the uid of one member inside the group document
create function public.bloom_set_member_uid(p_data jsonb, p_member text, p_uid uuid) returns jsonb
language sql immutable as $$
  select jsonb_set(p_data, '{members}', coalesce((
    select jsonb_agg(case when m->>'id' = p_member
                          then (case when p_uid is null then m - 'uid' else m || jsonb_build_object('uid', p_uid) end)
                          else m end order by i)
    from jsonb_array_elements(coalesce(p_data->'members','[]'::jsonb)) with ordinality as x(m, i)), '[]'::jsonb))
$$;

create function public.create_bloom_group(p_data jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare gid uuid;
begin
  if auth.uid() is null then raise exception 'Please log in first'; end if;
  insert into bloom_groups(owner, data) values (auth.uid(), p_data) returning id into gid;
  insert into bloom_group_members(group_id, user_id, role) values (gid, auth.uid(), 'owner');
  return gid;
end $$;

create function public.create_bloom_invite(p_group uuid, p_member text default null) returns text
language plpgsql security definer set search_path = public as $$
declare c text;
begin
  if not public.is_bloom_member(p_group) then raise exception 'Only group members can invite people'; end if;
  c := replace(gen_random_uuid()::text, '-', '');
  insert into bloom_group_invites(code, group_id, created_by, member_ref) values (c, p_group, auth.uid(), p_member);
  return c;
end $$;

create function public.preview_bloom_invite(p_code text)
returns table(group_name text, inviter text, member_name text, status text)
language plpgsql stable security definer set search_path = public as $$
declare inv bloom_group_invites; g bloom_groups;
begin
  if auth.uid() is null then raise exception 'Please log in first'; end if;
  select * into inv from bloom_group_invites where code = p_code;
  if not found then return query select null::text, null::text, null::text, 'invalid'; return; end if;
  select * into g from bloom_groups where id = inv.group_id;
  return query select g.data->>'name',
    (select username from profiles where id = inv.created_by),
    (select m->>'name' from jsonb_array_elements(g.data->'members') m where m->>'id' = inv.member_ref),
    case when exists (select 1 from bloom_group_members where group_id = g.id and user_id = auth.uid()) then 'member'
         when inv.expires_at < now() then 'expired'
         when inv.member_ref is not null and inv.used_by is not null then 'used'
         else 'ok' end;
end $$;

create function public.accept_bloom_invite(p_code text) returns uuid
language plpgsql security definer set search_path = public as $$
declare inv bloom_group_invites; g bloom_groups; uname text; claimed boolean := false;
begin
  if auth.uid() is null then raise exception 'Please log in first'; end if;
  select * into inv from bloom_group_invites where code = p_code for update;
  if not found then raise exception 'This invite link isn''t valid'; end if;
  if exists (select 1 from bloom_group_members where group_id = inv.group_id and user_id = auth.uid()) then return inv.group_id; end if;
  if inv.expires_at < now() then raise exception 'This invite link has expired. Ask for a new one.'; end if;
  if inv.member_ref is not null and inv.used_by is not null then raise exception 'This invite link has already been used'; end if;
  select * into g from bloom_groups where id = inv.group_id for update;
  select coalesce(username, 'New member') into uname from profiles where id = auth.uid();
  insert into bloom_group_members(group_id, user_id, role) values (g.id, auth.uid(), 'member');
  if inv.member_ref is not null and exists (select 1 from jsonb_array_elements(g.data->'members') m where m->>'id' = inv.member_ref and not (m ? 'uid')) then
    g.data := public.bloom_set_member_uid(g.data, inv.member_ref, auth.uid()); claimed := true;
    update bloom_group_invites set used_by = auth.uid(), used_at = now() where code = p_code;
  end if;
  if not claimed then
    g.data := jsonb_set(g.data, '{members}', coalesce(g.data->'members','[]'::jsonb) ||
      jsonb_build_array(jsonb_build_object('id', 'u' || left(replace(auth.uid()::text,'-',''), 12), 'name', coalesce(uname,'New member'), 'uid', auth.uid(), 'share', 'none', 'items', '[]'::jsonb)));
  end if;
  update bloom_groups set data = g.data, version = version + 1 where id = g.id;
  return g.id;
end $$;

create function public.leave_bloom_group(p_group uuid) returns void
language plpgsql security definer set search_path = public as $$
declare g bloom_groups; mid text;
begin
  select * into g from bloom_groups where id = p_group for update;
  if not found or not public.is_bloom_member(p_group) then raise exception 'You''re not in this group'; end if;
  if g.owner = auth.uid() then raise exception 'You created this group, so you can delete it but not leave it'; end if;
  select m->>'id' into mid from jsonb_array_elements(g.data->'members') m where m->>'uid' = auth.uid()::text;
  delete from bloom_group_members where group_id = p_group and user_id = auth.uid();
  if mid is not null then update bloom_groups set data = public.bloom_set_member_uid(g.data, mid, null), version = version + 1 where id = p_group; end if;
end $$;

create function public.remove_bloom_member(p_group uuid, p_user uuid) returns void
language plpgsql security definer set search_path = public as $$
declare g bloom_groups; mid text;
begin
  select * into g from bloom_groups where id = p_group for update;
  if not found or g.owner <> auth.uid() then raise exception 'Only the person who created the group can remove members'; end if;
  if p_user = auth.uid() then raise exception 'You can''t remove yourself'; end if;
  select m->>'id' into mid from jsonb_array_elements(g.data->'members') m where m->>'uid' = p_user::text;
  delete from bloom_group_members where group_id = p_group and user_id = p_user;
  if mid is not null then update bloom_groups set data = public.bloom_set_member_uid(g.data, mid, null), version = version + 1 where id = p_group; end if;
end $$;

revoke all on function public.create_bloom_group(jsonb), public.create_bloom_invite(uuid,text), public.preview_bloom_invite(text),
  public.accept_bloom_invite(text), public.leave_bloom_group(uuid), public.remove_bloom_member(uuid,uuid), public.is_bloom_member(uuid) from public, anon;
grant execute on function public.create_bloom_group(jsonb), public.create_bloom_invite(uuid,text), public.preview_bloom_invite(text),
  public.accept_bloom_invite(text), public.leave_bloom_group(uuid), public.remove_bloom_member(uuid,uuid), public.is_bloom_member(uuid) to authenticated;
