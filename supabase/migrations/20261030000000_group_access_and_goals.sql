-- Bloom Finance: group access modes, combined group overview, savings goals.
-- Run after 20261029000000_bloom_core_and_groups.sql.

-- ============================================================ Group access mode
-- all:     every member shares everything. Accepting an invite to such a group means agreeing to that.
-- partial: each member decides for themselves (none / overview / selected / full).
alter table public.groups add column access_mode text not null default 'partial' check (access_mode in ('all','partial'));

create or replace function public.accept_invite(p_member uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  update group_members m
     set user_id = auth.uid(), status = 'active', joined_at = now(),
         share_level = case when (select g.access_mode from groups g where g.id = m.group_id) = 'all' then 'full' else 'none' end
   where m.id = p_member and m.status = 'invited' and m.invited_email = lower(auth.email());
  if not found then raise exception 'No pending invitation for this account'; end if;
end $$;

create or replace function public.guard_member_update() returns trigger
language plpgsql security definer set search_path = public as $$
declare me boolean := old.user_id is not null and old.user_id = auth.uid();
declare adm boolean := is_group_admin(old.group_id);
declare all_mode boolean := (select access_mode = 'all' from groups where id = old.group_id);
begin
  if auth.uid() is null then return new; end if;   -- service/maintenance context
  -- accepting (share level set by the group's access mode) or declining an invitation
  if old.status = 'invited' and old.user_id is null and old.invited_email = lower(auth.email())
     and new.role = old.role
     and ((new.status = 'active' and new.user_id = auth.uid() and new.share_level = case when all_mode then 'full' else 'none' end)
          or (new.status = 'declined' and new.user_id is null and new.share_level = 'none')) then
    return new;
  end if;
  if new.group_id <> old.group_id or new.user_id is distinct from old.user_id or new.invited_email <> old.invited_email then
    raise exception 'This change is not allowed';
  end if;
  if new.status in ('left','removed') then
    new.share_level := 'none';                     -- leaving or removal always stops sharing
  else
    if new.share_level <> old.share_level and not me then
      raise exception 'Only the member can change what they share';
    end if;
    if new.share_level <> 'none' and new.status <> 'active' then
      raise exception 'Only active members can share';
    end if;
    if all_mode and new.share_level <> old.share_level and new.share_level <> 'full' then
      raise exception 'This group uses all access. To share less, leave the group or ask an admin to switch it to partial access';
    end if;
  end if;
  if new.role <> old.role then
    if me or not adm then raise exception 'Only an admin can change roles'; end if;
    if old.role = 'owner' or new.role = 'owner' then raise exception 'Ownership transfer is not supported yet'; end if;
  end if;
  if new.status <> old.status then
    if me and new.status = 'left' and old.role <> 'owner' and old.status = 'active' then null;
    elsif adm and not me and new.status = 'removed' and old.role <> 'owner' then null;
    else raise exception 'This status change is not allowed';
    end if;
  end if;
  if new.status in ('left','removed') then
    delete from group_shares where member_id = old.id;
  end if;
  insert into audit_log (group_id, action, detail)
  values (old.group_id, 'member_updated', jsonb_build_object('member', old.id,
          'role', jsonb_build_array(old.role, new.role), 'status', jsonb_build_array(old.status, new.status),
          'share_level', jsonb_build_array(old.share_level, new.share_level)));
  return new;
end $$;

-- the group creator's own sharing follows the access mode
create or replace function public.add_group_owner() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into group_members (group_id, user_id, invited_email, display_name, role, status, joined_at, invited_by, share_level)
  values (new.id, new.created_by, lower(coalesce(auth.email(), new.created_by::text || '@owner.local')),
          coalesce((select nullif(display_name,'') from profiles where id = new.created_by), 'Owner'),
          'owner', 'active', now(), new.created_by, case when new.access_mode = 'all' then 'full' else 'none' end);
  insert into audit_log (group_id, action, detail) values (new.id, 'group_created', jsonb_build_object('access_mode', new.access_mode));
  return new;
end $$;

-- log access-mode changes (switching to "all" does not change anyone's sharing; each member must agree by choosing "full")
create function public.log_group_update() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.access_mode <> old.access_mode then
    insert into audit_log (group_id, action, detail) values (new.id, 'access_mode_changed', jsonb_build_array(old.access_mode, new.access_mode));
  end if;
  return new;
end $$;
create trigger groups_log_update after update on public.groups for each row execute function public.log_group_update();

-- ============================================================ Totals a member shares
-- 'overview' and 'full' contribute everything; 'selected' contributes ONLY the items the member picked.
-- Internal: never callable by users directly (it does not check membership).
create function public.member_totals(p_member uuid)
returns table (currency char(3), cash_and_bank bigint, other_assets bigint, card_debt bigint, loans bigint)
language sql stable security definer set search_path = public as $$
  with m as (select id, user_id, share_level from group_members where id = p_member and status = 'active' and share_level <> 'none'),
  pick as (select s.item_type, s.item_id from group_shares s, m where s.member_id = m.id),
  a as (select ab.currency, sum(ab.balance_minor) v from account_balances ab, m
         where ab.owner_id = m.user_id and (m.share_level <> 'selected' or (('account', ab.id) in (select * from pick))) group by 1),
  o as (select s.currency, sum((select v.value_minor from asset_valuations v where v.asset_id = s.id order by v.valued_on desc limit 1)) v from assets s, m
         where s.owner_id = m.user_id and (m.share_level <> 'selected' or (('asset', s.id) in (select * from pick))) group by 1),
  c as (select cb.currency, sum(cb.owed_minor) v from card_balances cb, m
         where cb.owner_id = m.user_id and (m.share_level <> 'selected' or (('card', cb.id) in (select * from pick))) group by 1),
  l as (select lb.currency, sum(lb.outstanding_minor) v from liability_balances lb, m
         where lb.owner_id = m.user_id and (m.share_level <> 'selected' or (('liability', lb.id) in (select * from pick))) group by 1),
  cur as (select x.currency from a x union select x.currency from o x union select x.currency from c x union select x.currency from l x)
  select cur.currency, coalesce(a.v,0)::bigint, coalesce(o.v,0)::bigint, coalesce(c.v,0)::bigint, coalesce(l.v,0)::bigint
  from cur left join a using (currency) left join o using (currency) left join c using (currency) left join l using (currency);
$$;

create or replace function public.member_overview(p_group uuid, p_member uuid)
returns table (currency char(3), cash_and_bank bigint, other_assets bigint, card_debt bigint, loans bigint, net_worth bigint)
language plpgsql stable security definer set search_path = public as $$
begin
  if not is_active_member(p_group) then raise exception 'Not a member of this group'; end if;
  if not exists (select 1 from group_members where id = p_member and group_id = p_group and status = 'active' and share_level <> 'none') then
    raise exception 'This member does not share an overview with the group';
  end if;
  return query select t.currency, t.cash_and_bank, t.other_assets, t.card_debt, t.loans,
                      t.cash_and_bank + t.other_assets - t.card_debt - t.loans
               from member_totals(p_member) t;
end $$;

-- Combined overview of everyone who shares something with the group.
create function public.group_overview(p_group uuid)
returns table (currency char(3), cash_and_bank bigint, other_assets bigint, card_debt bigint, loans bigint, net_worth bigint, members_included int)
language plpgsql stable security definer set search_path = public as $$
begin
  if not is_active_member(p_group) then raise exception 'Not a member of this group'; end if;
  return query
  select t.currency, sum(t.cash_and_bank)::bigint, sum(t.other_assets)::bigint, sum(t.card_debt)::bigint, sum(t.loans)::bigint,
         sum(t.cash_and_bank + t.other_assets - t.card_debt - t.loans)::bigint, count(distinct gm.id)::int
  from group_members gm cross join lateral member_totals(gm.id) t
  where gm.group_id = p_group and gm.status = 'active' and gm.share_level <> 'none'
  group by t.currency;
end $$;

-- ============================================================ Savings goals
-- A goal sets money aside in the plan. It never moves money or changes balances.
create table public.savings_goals (
  id             uuid primary key default gen_random_uuid(),
  owner_id       uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name           text not null check (char_length(name) between 1 and 50),
  target_minor   bigint not null check (target_minor > 0),
  currency       char(3) not null check (currency ~ '^[A-Z]{3}$'),
  target_date    date,
  linked_account uuid,
  created_at     timestamptz not null default now(),
  unique (owner_id, name),
  unique (id, owner_id),
  foreign key (linked_account, owner_id) references public.accounts(id, owner_id) on delete set null (linked_account)
);

create table public.goal_moves (
  id           uuid primary key default gen_random_uuid(),
  goal_id      uuid not null,
  owner_id     uuid not null default auth.uid(),
  occurred_on  date not null,
  amount_minor bigint not null check (amount_minor <> 0),   -- positive = added, negative = taken out
  note         text check (char_length(note) <= 60),
  created_at   timestamptz not null default now(),
  foreign key (goal_id, owner_id) references public.savings_goals(id, owner_id) on delete cascade
);

-- a goal can never hold less than zero (checked at commit)
create function public.check_goal_not_negative() returns trigger
language plpgsql security definer set search_path = public as $$
declare g uuid := coalesce(new.goal_id, old.goal_id); total bigint;
begin
  if not exists (select 1 from savings_goals where id = g) then return null; end if;
  select coalesce(sum(amount_minor),0) into total from goal_moves where goal_id = g;
  if total < 0 then raise exception 'You can''t take out more than the goal holds'; end if;
  return null;
end $$;
create constraint trigger goal_not_negative after insert or update or delete on public.goal_moves
  deferrable initially deferred for each row execute function public.check_goal_not_negative();

-- a linked account must use the goal's currency
create function public.check_goal_account_currency() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.linked_account is not null and (select currency from accounts where id = new.linked_account) <> new.currency then
    raise exception 'The linked account must use the goal''s currency';
  end if;
  return new;
end $$;
create trigger goal_account_currency before insert or update on public.savings_goals for each row execute function public.check_goal_account_currency();

alter table public.savings_goals enable row level security;
alter table public.goal_moves    enable row level security;
create policy goals_own on public.savings_goals for all using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create policy goal_moves_own on public.goal_moves for all using (owner_id = auth.uid()) with check (owner_id = auth.uid());

-- ============================================================ Privileges
grant select, insert, update, delete on public.savings_goals, public.goal_moves to authenticated;
revoke all on public.savings_goals, public.goal_moves from anon;
revoke execute on function public.member_totals(uuid) from public, anon, authenticated;
revoke execute on function public.group_overview(uuid), public.log_group_update(), public.check_goal_not_negative(), public.check_goal_account_currency() from public, anon;
grant execute on function public.group_overview(uuid), public.member_overview(uuid, uuid), public.accept_invite(uuid) to authenticated;
