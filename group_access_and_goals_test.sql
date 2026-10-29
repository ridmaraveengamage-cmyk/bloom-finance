-- Tests for group access modes, group overview and savings goals. Run on a TEST database after both migrations.
\set ON_ERROR_STOP 1
\set QUIET 1
\pset tuples_only on
\o /dev/null
create or replace function pg_temp.ok(cond boolean, label text) returns void language plpgsql as $$
begin if cond then raise notice 'PASS  %', label; else raise exception 'FAIL  %', label; end if; end $$;
create or replace function pg_temp.fails(sql text, label text) returns void language plpgsql as $$
begin
  begin execute sql; exception when others then raise notice 'PASS  % (blocked: %)', label, left(sqlerrm, 70); return; end;
  raise exception 'FAIL  % (statement was allowed)', label;
end $$;

reset role;
insert into auth.users (id, email) values
 ('dddddddd-0000-0000-0000-000000000004','d@example.com'),
 ('eeeeeeee-0000-0000-0000-000000000005','e@example.com'),
 ('ffffffff-0000-0000-0000-000000000006','f@example.com');
set role authenticated;

-- E has two accounts and a card
select set_config('request.jwt.claim.sub','eeeeeeee-0000-0000-0000-000000000005',false), set_config('request.jwt.claim.email','e@example.com',false);
insert into accounts (id,kind,name,currency,opening_minor) values ('e0000000-0000-0000-0000-0000000000e1','bank','E Bank','LKR',1000000),('e0000000-0000-0000-0000-0000000000e2','savings','E Hidden','LKR',7000000);
insert into cards (id,name,bank,last4,expiry,currency,opening_owed_minor) values ('e0000000-0000-0000-0000-0000000000c1','E Card','HNB','1111','01/29','LKR',200000);

-- ---------------------------------------------------------------- partial-access group
select set_config('request.jwt.claim.sub','dddddddd-0000-0000-0000-000000000004',false), set_config('request.jwt.claim.email','d@example.com',false);
insert into accounts (kind,name,currency,opening_minor) values ('bank','D Bank','LKR',500000);
insert into groups (id,name,type,currency,access_mode) values ('88888888-0000-0000-0000-000000000001','Partial fam','Family','LKR','partial');
select pg_temp.ok((select share_level from group_members where user_id = auth.uid() and group_id='88888888-0000-0000-0000-000000000001') = 'none', 'partial group: creator shares nothing by default');
insert into group_members (id,group_id,invited_email,display_name) values ('88888888-0000-0000-0000-0000000000e1','88888888-0000-0000-0000-000000000001','e@example.com','E');

select set_config('request.jwt.claim.sub','eeeeeeee-0000-0000-0000-000000000005',false), set_config('request.jwt.claim.email','e@example.com',false);
select accept_invite('88888888-0000-0000-0000-0000000000e1');
select pg_temp.ok((select share_level from group_members where id='88888888-0000-0000-0000-0000000000e1') = 'none', 'partial group: joining shares nothing');
update group_members set share_level='selected' where id='88888888-0000-0000-0000-0000000000e1';
insert into group_shares (member_id,item_type,item_id) values ('88888888-0000-0000-0000-0000000000e1','account','e0000000-0000-0000-0000-0000000000e1');

select set_config('request.jwt.claim.sub','dddddddd-0000-0000-0000-000000000004',false), set_config('request.jwt.claim.email','d@example.com',false);
select pg_temp.ok((select cash_and_bank from member_overview('88888888-0000-0000-0000-000000000001','88888888-0000-0000-0000-0000000000e1')) = 1000000,
  'selected: overview totals include ONLY the shared account (10,000, not the hidden 70,000)');
select pg_temp.ok((select card_debt from member_overview('88888888-0000-0000-0000-000000000001','88888888-0000-0000-0000-0000000000e1')) = 0, 'selected: unshared card not counted');
select pg_temp.ok((select members_included from group_overview('88888888-0000-0000-0000-000000000001')) = 1, 'group overview counts only members who share (D shares nothing)');
select pg_temp.ok((select net_worth from group_overview('88888888-0000-0000-0000-000000000001')) = 1000000, 'group overview = what E shares');
update group_members set share_level='overview' where user_id = auth.uid() and group_id='88888888-0000-0000-0000-000000000001';
select pg_temp.ok((select members_included from group_overview('88888888-0000-0000-0000-000000000001')) = 2, 'after D shares an overview, both are included');
select pg_temp.ok((select net_worth from group_overview('88888888-0000-0000-0000-000000000001')) = 1500000, 'combined net worth = D 5,000 + E shared 10,000');
select pg_temp.fails($$select * from member_totals('88888888-0000-0000-0000-0000000000e1')$$, 'the internal totals function cannot be called directly');

-- outsider
select set_config('request.jwt.claim.sub','ffffffff-0000-0000-0000-000000000006',false), set_config('request.jwt.claim.email','f@example.com',false);
select pg_temp.fails($$select * from group_overview('88888888-0000-0000-0000-000000000001')$$, 'non-member cannot see the group overview');

-- ---------------------------------------------------------------- all-access group
select set_config('request.jwt.claim.sub','dddddddd-0000-0000-0000-000000000004',false), set_config('request.jwt.claim.email','d@example.com',false);
insert into groups (id,name,type,currency,access_mode) values ('88888888-0000-0000-0000-000000000002','All fam','Family','LKR','all');
select pg_temp.ok((select share_level from group_members where user_id = auth.uid() and group_id='88888888-0000-0000-0000-000000000002') = 'full', 'all-access group: creator shares everything');
insert into group_members (id,group_id,invited_email,display_name) values ('88888888-0000-0000-0000-0000000000e2','88888888-0000-0000-0000-000000000002','e@example.com','E');
select set_config('request.jwt.claim.sub','eeeeeeee-0000-0000-0000-000000000005',false), set_config('request.jwt.claim.email','e@example.com',false);
select pg_temp.ok((select access_mode from groups where id='88888888-0000-0000-0000-000000000002') = 'all', 'invitee can see the group is all access before accepting');
select accept_invite('88888888-0000-0000-0000-0000000000e2');
select pg_temp.ok((select share_level from group_members where id='88888888-0000-0000-0000-0000000000e2') = 'full', 'accepting an all-access invite means sharing everything');
select pg_temp.fails($$update group_members set share_level='overview' where id='88888888-0000-0000-0000-0000000000e2'$$, 'all access: a member cannot share less while in the group');
select set_config('request.jwt.claim.sub','dddddddd-0000-0000-0000-000000000004',false), set_config('request.jwt.claim.email','d@example.com',false);
select pg_temp.ok((select count(*) from accounts where owner_id='eeeeeeee-0000-0000-0000-000000000005') = 2, 'all access: D sees all of E''s accounts');
select pg_temp.ok((select net_worth from group_overview('88888888-0000-0000-0000-000000000002')) = 500000 + 1000000 + 7000000 - 200000, 'all access: combined overview includes everything');

-- switching modes
update groups set access_mode='partial' where id='88888888-0000-0000-0000-000000000002';
select pg_temp.ok((select share_level from group_members where id='88888888-0000-0000-0000-0000000000e2') = 'full', 'switching to partial does not silently change anyone''s sharing');
update groups set access_mode='all' where id='88888888-0000-0000-0000-000000000001';
select pg_temp.ok((select share_level from group_members where id='88888888-0000-0000-0000-0000000000e1') = 'selected', 'switching to all does not force anyone to share more');
select pg_temp.ok((select count(*) from audit_log where action='access_mode_changed') = 2, 'access-mode changes are logged');

select set_config('request.jwt.claim.sub','eeeeeeee-0000-0000-0000-000000000005',false), set_config('request.jwt.claim.email','e@example.com',false);
update group_members set status='left' where id='88888888-0000-0000-0000-0000000000e2';
select set_config('request.jwt.claim.sub','dddddddd-0000-0000-0000-000000000004',false), set_config('request.jwt.claim.email','d@example.com',false);
select pg_temp.ok((select count(*) from accounts where owner_id='eeeeeeee-0000-0000-0000-000000000005') = 1, 'after E leaves the all-access group, D sees only what E shares elsewhere');

-- ---------------------------------------------------------------- goals
select set_config('request.jwt.claim.sub','eeeeeeee-0000-0000-0000-000000000005',false), set_config('request.jwt.claim.email','e@example.com',false);
insert into savings_goals (id,name,target_minor,currency,linked_account) values ('60000000-0000-0000-0000-000000000001','Emergency fund',30000000,'LKR','e0000000-0000-0000-0000-0000000000e2');
insert into goal_moves (goal_id,occurred_on,amount_minor) values ('60000000-0000-0000-0000-000000000001','2026-10-20',5000000),('60000000-0000-0000-0000-000000000001','2026-10-21',-1000000);
select pg_temp.ok((select sum(amount_minor) from goal_moves) = 4000000, 'goal holds 50,000 − 10,000 = 40,000');
select pg_temp.ok((select balance_minor from account_balances where id='e0000000-0000-0000-0000-0000000000e2') = 7000000, 'goals never change account balances');
select pg_temp.fails($x$do $d$ begin insert into goal_moves (goal_id,occurred_on,amount_minor) values ('60000000-0000-0000-0000-000000000001','2026-10-22',-5000000); set constraints all immediate; end $d$$x$, 'cannot take out more than the goal holds');
select pg_temp.fails($$insert into savings_goals (name,target_minor,currency,linked_account) values ('USD goal',100,'USD','e0000000-0000-0000-0000-0000000000e1')$$, 'linked account must use the goal''s currency');
select pg_temp.fails($$insert into savings_goals (name,target_minor,currency) values ('Zero',0,'LKR')$$, 'target must be above zero');
select set_config('request.jwt.claim.sub','dddddddd-0000-0000-0000-000000000004',false), set_config('request.jwt.claim.email','d@example.com',false);
select pg_temp.ok((select count(*) from savings_goals) = 0 and (select count(*) from goal_moves) = 0, 'other users never see your goals');
select pg_temp.fails($$insert into goal_moves (goal_id,owner_id,occurred_on,amount_minor) values ('60000000-0000-0000-0000-000000000001','eeeeeeee-0000-0000-0000-000000000005','2026-10-23',1)$$, 'others cannot add to your goals');
reset role; set role anon;
select pg_temp.fails($$select * from savings_goals$$, 'signed-out visitors cannot read goals');
reset role;
\o
\echo ALL TESTS PASSED
