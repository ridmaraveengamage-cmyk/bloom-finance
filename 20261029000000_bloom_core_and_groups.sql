-- Bloom Finance: core data model, groups, invitations and per-member sharing.
-- Every table holding private data has Row Level Security (RLS) switched on.
-- Money is stored in whole minor units (e.g. cents) as bigint. Currencies are ISO codes.
-- Ledger rule (same as the app): every transaction subtracts amount + interest from its
-- "from" account, adds amount to its "to" account, adds amount to a card's debt when the card
-- pays, subtracts amount from a card/loan when it is repaid. All balances are derived, never stored.

create extension if not exists pgcrypto;

-- ============================================================ Personal data
create table public.profiles (
  id            uuid primary key references auth.users(id) on delete cascade,
  display_name  text check (char_length(display_name) <= 60),
  base_currency char(3) not null default 'LKR' check (base_currency ~ '^[A-Z]{3}$'),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create table public.accounts (
  id           uuid primary key default gen_random_uuid(),
  owner_id     uuid not null default auth.uid() references auth.users(id) on delete cascade,
  kind         text not null check (kind in ('bank','savings','cash')),
  name         text not null check (char_length(name) between 1 and 40),
  bank         text check (char_length(bank) <= 60),
  branch       text check (char_length(branch) <= 60),
  country      text check (char_length(country) <= 60),
  holder_name  text check (char_length(holder_name) <= 60),
  account_no   text check (account_no ~ '^[0-9A-Za-z \-]{4,34}$'),
  currency     char(3) not null check (currency ~ '^[A-Z]{3}$'),
  opening_minor bigint not null default 0,
  archived     boolean not null default false,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  unique (owner_id, name),
  unique (id, owner_id)
);

create table public.cards (
  id            uuid primary key default gen_random_uuid(),
  owner_id      uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name          text not null check (char_length(name) between 1 and 40),
  bank          text not null check (char_length(bank) between 1 and 60),
  last4         char(4) not null check (last4 ~ '^[0-9]{4}$'),   -- full card numbers are never stored
  expiry        char(5) not null check (expiry ~ '^(0[1-9]|1[0-2])/[0-9]{2}$'),
  currency      char(3) not null check (currency ~ '^[A-Z]{3}$'),
  limit_minor   bigint not null default 0 check (limit_minor >= 0),
  opening_owed_minor bigint not null default 0 check (opening_owed_minor >= 0),
  annual_fee_minor   bigint not null default 0 check (annual_fee_minor >= 0),
  interest_rate numeric(5,2) check (interest_rate >= 0 and interest_rate < 100),
  archived      boolean not null default false,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  unique (owner_id, name),
  unique (id, owner_id)
);

create table public.assets (
  id         uuid primary key default gen_random_uuid(),
  owner_id   uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name       text not null check (char_length(name) between 1 and 50),
  type       text not null,
  currency   char(3) not null check (currency ~ '^[A-Z]{3}$'),
  note       text check (char_length(note) <= 80),
  created_at timestamptz not null default now(),
  unique (id, owner_id)
);

create table public.asset_valuations (
  asset_id    uuid not null,
  owner_id    uuid not null default auth.uid(),
  valued_on   date not null,
  value_minor bigint not null check (value_minor >= 0),
  primary key (asset_id, valued_on),
  foreign key (asset_id, owner_id) references public.assets(id, owner_id) on delete cascade
);

create table public.liabilities (
  id            uuid primary key default gen_random_uuid(),
  owner_id      uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name          text not null check (char_length(name) between 1 and 50),
  type          text not null,
  lender        text check (char_length(lender) <= 50),
  currency      char(3) not null check (currency ~ '^[A-Z]{3}$'),
  opening_minor bigint not null check (opening_minor >= 0),
  interest_rate numeric(5,2) check (interest_rate >= 0 and interest_rate < 100),
  instalment_minor bigint not null default 0 check (instalment_minor >= 0),
  note          text check (char_length(note) <= 80),
  created_at    timestamptz not null default now(),
  unique (id, owner_id)
);

create table public.transactions (
  id             uuid primary key default gen_random_uuid(),
  owner_id       uuid not null default auth.uid() references auth.users(id) on delete cascade,
  type           text not null check (type in ('income','expense','transfer','repay','loanpay','withdraw','deposit')),
  transfer_kind  text check (transfer_kind in ('own','fam_out','ext_out','fam_in','ext_in')),
  amount_minor   bigint not null check (amount_minor >= 0),
  interest_minor bigint not null default 0 check (interest_minor >= 0),
  occurred_on    date not null,
  from_account   uuid,
  from_card      uuid,
  to_account     uuid,
  to_card        uuid,
  to_liability   uuid,
  method         text check (method in ('cash','bank','card','cheque')),
  bank_via       text check (bank_via in ('Debit card','Online transfer','Automatic deduction')),
  category       text check (char_length(category) <= 40),
  subcategory    text check (char_length(subcategory) <= 40),
  party          text check (char_length(party) <= 60),
  note           text check (char_length(note) <= 60),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  -- references must belong to the same owner (composite foreign keys)
  foreign key (from_account, owner_id) references public.accounts(id, owner_id),
  foreign key (to_account,   owner_id) references public.accounts(id, owner_id),
  foreign key (from_card,    owner_id) references public.cards(id, owner_id),
  foreign key (to_card,      owner_id) references public.cards(id, owner_id),
  foreign key (to_liability, owner_id) references public.liabilities(id, owner_id),
  check (amount_minor + interest_minor > 0),
  check (interest_minor = 0 or type = 'loanpay'),
  check (from_account is null or to_account is null or from_account <> to_account),
  -- each type has exactly the fields it needs
  check (case type
    when 'income'   then to_account is not null and from_account is null and from_card is null and to_card is null and to_liability is null
    when 'expense'  then num_nonnulls(from_account, from_card) = 1 and to_account is null and to_card is null and to_liability is null and method is not null
    when 'transfer' then to_card is null and to_liability is null and from_card is null and transfer_kind is not null and case transfer_kind
                         when 'own' then from_account is not null and to_account is not null
                         when 'fam_out' then from_account is not null and to_account is null
                         when 'ext_out' then from_account is not null and to_account is null
                         else from_account is null and to_account is not null end
    when 'repay'    then from_account is not null and to_card is not null and to_account is null and from_card is null and to_liability is null
    when 'loanpay'  then from_account is not null and to_liability is not null and to_account is null and from_card is null and to_card is null
    else /* withdraw, deposit */ from_account is not null and to_account is not null and from_card is null and to_card is null and to_liability is null
  end)
);
create index on public.transactions (owner_id, occurred_on);

create table public.budgets (
  owner_id    uuid not null default auth.uid() references auth.users(id) on delete cascade,
  category    text not null check (char_length(category) <= 40),
  limit_minor bigint not null check (limit_minor > 0),
  primary key (owner_id, category)
);

create table public.custom_categories (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid not null default auth.uid() references auth.users(id) on delete cascade,
  kind        text not null check (kind in ('income','expense')),
  category    text not null check (char_length(category) between 1 and 40),
  subcategory text check (char_length(subcategory) between 1 and 40)
);
create unique index on public.custom_categories (owner_id, kind, lower(category), lower(coalesce(subcategory,'')));

-- ============================================================ Groups
create table public.groups (
  id         uuid primary key default gen_random_uuid(),
  name       text not null check (char_length(name) between 1 and 50),
  type       text not null check (type in ('Family','Friends','Household','Trip or event','Business or project','Other')),
  currency   char(3) not null check (currency ~ '^[A-Z]{3}$'),
  created_by uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now()
);

create table public.group_members (
  id            uuid primary key default gen_random_uuid(),
  group_id      uuid not null references public.groups(id) on delete cascade,
  user_id       uuid references auth.users(id) on delete set null,   -- null until the invite is accepted
  invited_email text not null check (invited_email = lower(invited_email) and invited_email like '%_@_%'),
  display_name  text not null check (char_length(display_name) between 1 and 40),
  role          text not null default 'member' check (role in ('owner','admin','member','viewer')),
  status        text not null default 'invited' check (status in ('invited','active','declined','left','removed')),
  -- what THIS member shares with the group about their own finances (only they can change it)
  share_level   text not null default 'none' check (share_level in ('none','overview','selected','full')),
  invited_by    uuid default auth.uid(),
  joined_at     timestamptz,
  created_at    timestamptz not null default now(),
  unique (group_id, invited_email),
  unique (group_id, user_id),
  unique (id, group_id)
);

-- items a member chose to share when share_level = 'selected'
create table public.group_shares (
  member_id uuid not null references public.group_members(id) on delete cascade,
  item_type text not null check (item_type in ('account','card','asset','liability')),
  item_id   uuid not null,
  primary key (member_id, item_type, item_id)
);

create table public.group_tasks (
  id           uuid primary key default gen_random_uuid(),
  group_id     uuid not null references public.groups(id) on delete cascade,
  name         text not null check (char_length(name) between 1 and 50),
  budget_minor bigint not null default 0 check (budget_minor >= 0),
  created_by   uuid not null default auth.uid(),
  created_at   timestamptz not null default now(),
  unique (id, group_id)
);

create table public.group_expenses (
  id           uuid primary key default gen_random_uuid(),
  group_id     uuid not null references public.groups(id) on delete cascade,
  task_id      uuid,
  description  text not null check (char_length(description) between 1 and 60),
  amount_minor bigint not null check (amount_minor > 0),
  occurred_on  date not null,
  paid_by      uuid not null,
  created_by   uuid not null default auth.uid(),
  created_at   timestamptz not null default now(),
  unique (id, group_id),
  foreign key (task_id, group_id) references public.group_tasks(id, group_id),
  foreign key (paid_by, group_id) references public.group_members(id, group_id)
);

create table public.group_expense_splits (
  expense_id  uuid not null,
  group_id    uuid not null,
  member_id   uuid not null,
  share_minor bigint not null check (share_minor >= 0),
  primary key (expense_id, member_id),
  foreign key (expense_id, group_id) references public.group_expenses(id, group_id) on delete cascade,
  foreign key (member_id, group_id) references public.group_members(id, group_id)
);

create table public.group_settlements (
  id           uuid primary key default gen_random_uuid(),
  group_id     uuid not null references public.groups(id) on delete cascade,
  from_member  uuid not null,
  to_member    uuid not null,
  amount_minor bigint not null check (amount_minor > 0),
  occurred_on  date not null,
  created_by   uuid not null default auth.uid(),
  created_at   timestamptz not null default now(),
  check (from_member <> to_member),
  foreign key (from_member, group_id) references public.group_members(id, group_id),
  foreign key (to_member, group_id)   references public.group_members(id, group_id)
);

create table public.audit_log (
  id       bigint generated always as identity primary key,
  group_id uuid references public.groups(id) on delete cascade,
  actor    uuid default auth.uid(),
  action   text not null,
  detail   jsonb not null default '{}',
  at       timestamptz not null default now()
);

-- ============================================================ Helper functions
-- SECURITY DEFINER helpers read membership without triggering RLS recursion.
create function public.is_active_member(gid uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from group_members where group_id = gid and user_id = auth.uid() and status = 'active');
$$;

create function public.can_write_group(gid uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from group_members where group_id = gid and user_id = auth.uid()
                 and status = 'active' and role in ('owner','admin','member'));
$$;

create function public.is_group_admin(gid uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from group_members where group_id = gid and user_id = auth.uid()
                 and status = 'active' and role in ('owner','admin'));
$$;

-- Can the current user see p_owner's item? Only through a group they are BOTH active in,
-- where p_owner shares everything ('full') or chose this item ('selected').
create function public.can_view_item(p_owner uuid, p_type text, p_item uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select p_item is not null and exists (
    select 1 from group_members viewer
    join group_members own on own.group_id = viewer.group_id
    where viewer.user_id = auth.uid() and viewer.status = 'active'
      and own.user_id = p_owner and own.status = 'active' and own.user_id <> auth.uid()
      and (own.share_level = 'full'
           or (own.share_level = 'selected' and exists (
                 select 1 from group_shares s where s.member_id = own.id and s.item_type = p_type and s.item_id = p_item))));
$$;

create function public.can_view_all(p_owner uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from group_members viewer
    join group_members own on own.group_id = viewer.group_id
    where viewer.user_id = auth.uid() and viewer.status = 'active'
      and own.user_id = p_owner and own.status = 'active' and own.user_id <> auth.uid()
      and own.share_level = 'full');
$$;

create function public.owns_item(p_type text, p_item uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select case p_type
    when 'account'   then exists (select 1 from accounts    where id = p_item and owner_id = auth.uid())
    when 'card'      then exists (select 1 from cards       where id = p_item and owner_id = auth.uid())
    when 'asset'     then exists (select 1 from assets      where id = p_item and owner_id = auth.uid())
    when 'liability' then exists (select 1 from liabilities where id = p_item and owner_id = auth.uid())
    else false end;
$$;

-- ============================================================ Derived balances (respect RLS of the caller)
create view public.account_balances with (security_invoker = true) as
select a.id, a.owner_id, a.name, a.kind, a.currency,
       a.opening_minor
       + coalesce((select sum(t.amount_minor) from transactions t where t.to_account = a.id), 0)
       - coalesce((select sum(t.amount_minor + t.interest_minor) from transactions t where t.from_account = a.id), 0) as balance_minor
from accounts a;

create view public.card_balances with (security_invoker = true) as
select c.id, c.owner_id, c.name, c.currency, c.limit_minor,
       c.opening_owed_minor
       + coalesce((select sum(t.amount_minor) from transactions t where t.from_card = c.id), 0)
       - coalesce((select sum(t.amount_minor) from transactions t where t.to_card = c.id), 0) as owed_minor
from cards c;

create view public.liability_balances with (security_invoker = true) as
select l.id, l.owner_id, l.name, l.type, l.currency,
       l.opening_minor - coalesce((select sum(t.amount_minor) from transactions t where t.to_liability = l.id), 0) as outstanding_minor
from liabilities l;

-- "Overview only" sharing: totals for one member, without exposing any individual record.
create function public.member_overview(p_group uuid, p_member uuid)
returns table (currency char(3), cash_and_bank bigint, other_assets bigint, card_debt bigint, loans bigint, net_worth bigint)
language plpgsql stable security definer set search_path = public as $$
declare v_user uuid;
begin
  if not is_active_member(p_group) then raise exception 'Not a member of this group'; end if;
  select user_id into v_user from group_members
   where id = p_member and group_id = p_group and status = 'active' and share_level in ('overview','selected','full');
  if v_user is null then raise exception 'This member does not share an overview with the group'; end if;
  return query
  with a as (select ab.currency, sum(ab.balance_minor) v from account_balances ab where ab.owner_id = v_user group by 1),
       o as (select s.currency, sum((select v.value_minor from asset_valuations v where v.asset_id = s.id order by v.valued_on desc limit 1)) v
               from assets s where s.owner_id = v_user group by 1),
       c as (select cb.currency, sum(cb.owed_minor) v from card_balances cb where cb.owner_id = v_user group by 1),
       l as (select lb.currency, sum(lb.outstanding_minor) v from liability_balances lb where lb.owner_id = v_user group by 1),
       cur as (select x.currency from a x union select x.currency from o x union select x.currency from c x union select x.currency from l x)
  select cur.currency,
         coalesce(a.v,0)::bigint, coalesce(o.v,0)::bigint, coalesce(c.v,0)::bigint, coalesce(l.v,0)::bigint,
         (coalesce(a.v,0) + coalesce(o.v,0) - coalesce(c.v,0) - coalesce(l.v,0))::bigint
  from cur left join a using (currency) left join o using (currency) left join c using (currency) left join l using (currency);
end $$;

-- ============================================================ Invitations
create function public.accept_invite(p_member uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  update group_members set user_id = auth.uid(), status = 'active', joined_at = now()
   where id = p_member and status = 'invited' and invited_email = lower(auth.email());
  if not found then raise exception 'No pending invitation for this account'; end if;
end $$;

create function public.decline_invite(p_member uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  update group_members set status = 'declined'
   where id = p_member and status = 'invited' and invited_email = lower(auth.email());
  if not found then raise exception 'No pending invitation for this account'; end if;
end $$;

-- ============================================================ Triggers
create function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into profiles (id, display_name) values (new.id, left(coalesce(new.raw_user_meta_data->>'full_name', ''), 60))
  on conflict (id) do nothing;
  return new;
end $$;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();

create function public.add_group_owner() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into group_members (group_id, user_id, invited_email, display_name, role, status, joined_at, invited_by)
  values (new.id, new.created_by, lower(coalesce(auth.email(), new.created_by::text || '@owner.local')),
          coalesce((select nullif(display_name,'') from profiles where id = new.created_by), 'Owner'),
          'owner', 'active', now(), new.created_by);
  insert into audit_log (group_id, action) values (new.id, 'group_created');
  return new;
end $$;
create trigger groups_add_owner after insert on public.groups for each row execute function public.add_group_owner();

-- Only the member can change what they share; only admins can change roles or remove people;
-- the owner can't be removed or demoted; leaving or removal stops sharing immediately.
create function public.guard_member_update() returns trigger
language plpgsql security definer set search_path = public as $$
declare me boolean := old.user_id is not null and old.user_id = auth.uid();
declare adm boolean := is_group_admin(old.group_id);
begin
  if auth.uid() is null then return new; end if;   -- service/maintenance context
  -- accepting or declining an invitation (via accept_invite / decline_invite)
  if old.status = 'invited' and old.user_id is null and old.invited_email = lower(auth.email())
     and ((new.status = 'active' and new.user_id = auth.uid()) or (new.status = 'declined' and new.user_id is null))
     and new.role = old.role and new.share_level = 'none' then
    return new;
  end if;
  if new.group_id <> old.group_id or new.user_id is distinct from old.user_id or new.invited_email <> old.invited_email then
    raise exception 'This change is not allowed';
  end if;
  if new.share_level <> old.share_level and not me and new.status not in ('left','removed') then
    raise exception 'Only the member can change what they share';
  end if;
  if new.status in ('left','removed') then
    new.share_level := 'none';        -- leaving or removal always stops sharing
  elsif new.share_level <> 'none' and new.status <> 'active' then
    raise exception 'Only active members can share';
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
create trigger group_members_guard before update on public.group_members for each row execute function public.guard_member_update();

create function public.log_member_insert() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.role <> 'owner' then
    insert into audit_log (group_id, action, detail) values (new.group_id, 'member_invited', jsonb_build_object('member', new.id, 'role', new.role));
  end if;
  return new;
end $$;
create trigger group_members_log after insert on public.group_members for each row execute function public.log_member_insert();

-- splits must add up to the expense amount (checked at commit, so splits can be inserted one by one)
create function public.check_expense_splits() returns trigger
language plpgsql security definer set search_path = public as $$
declare e uuid := coalesce(new.expense_id, old.expense_id); total bigint; amt bigint;
begin
  select amount_minor into amt from group_expenses where id = e;
  if amt is null then return null; end if;
  select coalesce(sum(share_minor),0) into total from group_expense_splits where expense_id = e;
  if total <> amt then raise exception 'Splits (%) must add up to the expense amount (%)', total, amt; end if;
  return null;
end $$;
create constraint trigger splits_sum after insert or update or delete on public.group_expense_splits
  deferrable initially deferred for each row execute function public.check_expense_splits();

-- ============================================================ Row Level Security
alter table public.profiles             enable row level security;
alter table public.accounts             enable row level security;
alter table public.cards                enable row level security;
alter table public.assets               enable row level security;
alter table public.asset_valuations     enable row level security;
alter table public.liabilities          enable row level security;
alter table public.transactions         enable row level security;
alter table public.budgets              enable row level security;
alter table public.custom_categories    enable row level security;
alter table public.groups               enable row level security;
alter table public.group_members        enable row level security;
alter table public.group_shares         enable row level security;
alter table public.group_tasks          enable row level security;
alter table public.group_expenses       enable row level security;
alter table public.group_expense_splits enable row level security;
alter table public.group_settlements    enable row level security;
alter table public.audit_log            enable row level security;

-- Own data: full control. Others: read-only, and only what was shared with a group they share.
create policy own_profile on public.profiles for all using (id = auth.uid()) with check (id = auth.uid());

create policy accounts_read  on public.accounts for select using (owner_id = auth.uid() or can_view_item(owner_id, 'account', id));
create policy accounts_write on public.accounts for insert with check (owner_id = auth.uid());
create policy accounts_upd   on public.accounts for update using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create policy accounts_del   on public.accounts for delete using (owner_id = auth.uid());

create policy cards_read  on public.cards for select using (owner_id = auth.uid() or can_view_item(owner_id, 'card', id));
create policy cards_write on public.cards for insert with check (owner_id = auth.uid());
create policy cards_upd   on public.cards for update using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create policy cards_del   on public.cards for delete using (owner_id = auth.uid());

create policy assets_read  on public.assets for select using (owner_id = auth.uid() or can_view_item(owner_id, 'asset', id));
create policy assets_write on public.assets for insert with check (owner_id = auth.uid());
create policy assets_upd   on public.assets for update using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create policy assets_del   on public.assets for delete using (owner_id = auth.uid());

create policy valuations_read  on public.asset_valuations for select using (owner_id = auth.uid() or can_view_item(owner_id, 'asset', asset_id));
create policy valuations_write on public.asset_valuations for insert with check (owner_id = auth.uid());
create policy valuations_upd   on public.asset_valuations for update using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create policy valuations_del   on public.asset_valuations for delete using (owner_id = auth.uid());

create policy liabilities_read  on public.liabilities for select using (owner_id = auth.uid() or can_view_item(owner_id, 'liability', id));
create policy liabilities_write on public.liabilities for insert with check (owner_id = auth.uid());
create policy liabilities_upd   on public.liabilities for update using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create policy liabilities_del   on public.liabilities for delete using (owner_id = auth.uid());

create policy tx_read on public.transactions for select using (
  owner_id = auth.uid() or can_view_all(owner_id)
  or can_view_item(owner_id, 'account', from_account) or can_view_item(owner_id, 'account', to_account)
  or can_view_item(owner_id, 'card', from_card) or can_view_item(owner_id, 'card', to_card)
  or can_view_item(owner_id, 'liability', to_liability));
create policy tx_write on public.transactions for insert with check (owner_id = auth.uid());
create policy tx_upd   on public.transactions for update using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create policy tx_del   on public.transactions for delete using (owner_id = auth.uid());

create policy budgets_own on public.budgets for all using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create policy cats_own    on public.custom_categories for all using (owner_id = auth.uid()) with check (owner_id = auth.uid());

-- Groups
create policy groups_read on public.groups for select using (
  is_active_member(id)
  or exists (select 1 from group_members m where m.group_id = groups.id and m.status = 'invited' and m.invited_email = lower(auth.email())));
create policy groups_create on public.groups for insert with check (created_by = auth.uid());
create policy groups_update on public.groups for update using (is_group_admin(id)) with check (is_group_admin(id));
create policy groups_delete on public.groups for delete using (exists (
  select 1 from group_members m where m.group_id = groups.id and m.user_id = auth.uid() and m.role = 'owner' and m.status = 'active'));

create policy members_read on public.group_members for select using (
  is_active_member(group_id) or user_id = auth.uid() or (status = 'invited' and invited_email = lower(auth.email())));
create policy members_invite on public.group_members for insert with check (
  is_group_admin(group_id) and status = 'invited' and user_id is null and role in ('admin','member','viewer') and share_level = 'none');
create policy members_update on public.group_members for update using (
  is_group_admin(group_id) or user_id = auth.uid()) with check (is_group_admin(group_id) or user_id = auth.uid());
create policy members_delete_invite on public.group_members for delete using (is_group_admin(group_id) and status in ('invited','declined'));

create policy shares_read on public.group_shares for select using (exists (
  select 1 from group_members m where m.id = member_id and (m.user_id = auth.uid() or is_active_member(m.group_id))));
create policy shares_add on public.group_shares for insert with check (
  owns_item(item_type, item_id) and exists (
    select 1 from group_members m where m.id = member_id and m.user_id = auth.uid() and m.status = 'active' and m.share_level = 'selected'));
create policy shares_remove on public.group_shares for delete using (exists (
  select 1 from group_members m where m.id = member_id and m.user_id = auth.uid()));

create policy tasks_read on public.group_tasks for select using (is_active_member(group_id));
create policy tasks_add  on public.group_tasks for insert with check (can_write_group(group_id) and created_by = auth.uid());
create policy tasks_upd  on public.group_tasks for update using (can_write_group(group_id)) with check (can_write_group(group_id));
create policy tasks_del  on public.group_tasks for delete using (is_group_admin(group_id) or created_by = auth.uid());

create policy exp_read on public.group_expenses for select using (is_active_member(group_id));
create policy exp_add  on public.group_expenses for insert with check (can_write_group(group_id) and created_by = auth.uid());
create policy exp_upd  on public.group_expenses for update using (is_group_admin(group_id) or created_by = auth.uid()) with check (can_write_group(group_id));
create policy exp_del  on public.group_expenses for delete using (is_group_admin(group_id) or created_by = auth.uid());

create policy split_read on public.group_expense_splits for select using (is_active_member(group_id));
create policy split_add  on public.group_expense_splits for insert with check (can_write_group(group_id));
create policy split_upd  on public.group_expense_splits for update using (can_write_group(group_id)) with check (can_write_group(group_id));
create policy split_del  on public.group_expense_splits for delete using (can_write_group(group_id));

create policy settle_read on public.group_settlements for select using (is_active_member(group_id));
create policy settle_add  on public.group_settlements for insert with check (can_write_group(group_id) and created_by = auth.uid());
create policy settle_del  on public.group_settlements for delete using (is_group_admin(group_id) or created_by = auth.uid());

create policy audit_read on public.audit_log for select using (is_active_member(group_id));
-- no insert/update/delete policies: the audit log is written only by triggers

-- ============================================================ Privileges
revoke all on all tables in schema public from anon;
grant select, insert, update, delete on all tables in schema public to authenticated;
revoke insert, update, delete on public.audit_log from authenticated;
grant select on public.account_balances, public.card_balances, public.liability_balances to authenticated;
revoke execute on all functions in schema public from public, anon;
grant execute on function public.accept_invite(uuid), public.decline_invite(uuid), public.member_overview(uuid, uuid),
  public.is_active_member(uuid), public.can_write_group(uuid), public.is_group_admin(uuid),
  public.can_view_item(uuid, text, uuid), public.can_view_all(uuid), public.owns_item(text, uuid) to authenticated;
