-- Bloom Finance: mark a transaction as personal (no tags) or related to one or more groups.
-- Tagging shares THAT transaction with the group's active members, read-only. It still counts in the owner's personal totals.
-- Run after 20261030000000_group_access_and_goals.sql.

alter table public.transactions add constraint transactions_id_owner unique (id, owner_id);

create table public.transaction_groups (
  transaction_id uuid not null,
  group_id       uuid not null references public.groups(id) on delete cascade,
  owner_id       uuid not null default auth.uid(),
  tagged_at      timestamptz not null default now(),
  primary key (transaction_id, group_id),
  foreign key (transaction_id, owner_id) references public.transactions(id, owner_id) on delete cascade
);
create index on public.transaction_groups (group_id);

-- Is p_user an active member of p_group? (internal helper)
create function public.user_active_in(p_group uuid, p_user uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from group_members where group_id = p_group and user_id = p_user and status = 'active');
$$;

-- The current user may see a tagged transaction if both they and its owner are active in a group it is tagged with.
create function public.can_view_tagged(p_tx uuid, p_owner uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from transaction_groups t
                 where t.transaction_id = p_tx and t.owner_id = p_owner
                   and user_active_in(t.group_id, auth.uid()) and user_active_in(t.group_id, p_owner));
$$;

create policy tx_read_tagged on public.transactions for select using (can_view_tagged(id, owner_id));

alter table public.transaction_groups enable row level security;
create policy tags_read on public.transaction_groups for select using (
  owner_id = auth.uid() or (is_active_member(group_id) and user_active_in(group_id, owner_id)));
create policy tags_add on public.transaction_groups for insert with check (owner_id = auth.uid() and is_active_member(group_id));
create policy tags_remove on public.transaction_groups for delete using (owner_id = auth.uid());

grant select, insert, delete on public.transaction_groups to authenticated;
revoke all on public.transaction_groups from anon;
revoke execute on function public.user_active_in(uuid, uuid) from public, anon;
revoke execute on function public.can_view_tagged(uuid, uuid) from public, anon;
grant execute on function public.user_active_in(uuid, uuid), public.can_view_tagged(uuid, uuid) to authenticated;
