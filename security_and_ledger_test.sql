-- Bloom Finance database tests: ledger rules, data isolation, groups, invitations and sharing.
-- Run against a test database AFTER the migration. Stops at the first failure.
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

-- three users
reset role;
insert into auth.users (id, email, raw_user_meta_data) values
 ('aaaaaaaa-0000-0000-0000-000000000001','a@example.com','{"full_name":"Ridma"}'),
 ('bbbbbbbb-0000-0000-0000-000000000002','b@example.com','{"full_name":"Kasun"}'),
 ('cccccccc-0000-0000-0000-000000000003','c@example.com','{}');
select pg_temp.ok((select count(*) from profiles) = 3, 'profiles created automatically on sign-up');

-- ---------------------------------------------------------------- User A: ledger
set role authenticated;
select set_config('request.jwt.claim.sub','aaaaaaaa-0000-0000-0000-000000000001',false), set_config('request.jwt.claim.email','a@example.com',false);
insert into accounts (id,kind,name,currency,opening_minor) values ('a0000000-0000-0000-0000-0000000000a1','bank','A Bank','LKR',10000000),('a0000000-0000-0000-0000-0000000000a2','cash','A Cash','LKR',50000);
insert into cards (id,name,bank,last4,expiry,currency,limit_minor,opening_owed_minor) values ('a0000000-0000-0000-0000-0000000000c1','A Visa','BOC','4417','08/28','LKR',5000000,1000000);
insert into liabilities (id,name,type,currency,opening_minor) values ('a0000000-0000-0000-0000-0000000000f1','A Loan','Personal loan','LKR',5000000);
insert into transactions (type,amount_minor,occurred_on,from_account,method,category) values ('expense',500000,'2026-10-01','a0000000-0000-0000-0000-0000000000a1','bank','Food');
insert into transactions (type,amount_minor,occurred_on,from_card,method,category) values ('expense',400000,'2026-10-02','a0000000-0000-0000-0000-0000000000c1','card','Shopping');
insert into transactions (type,amount_minor,occurred_on,from_account,to_card) values ('repay',600000,'2026-10-03','a0000000-0000-0000-0000-0000000000a1','a0000000-0000-0000-0000-0000000000c1');
insert into transactions (type,transfer_kind,amount_minor,occurred_on,from_account,to_account) values ('transfer','own',700000,'2026-10-04','a0000000-0000-0000-0000-0000000000a1','a0000000-0000-0000-0000-0000000000a2');
insert into transactions (type,amount_minor,interest_minor,occurred_on,from_account,to_liability) values ('loanpay',400000,100000,'2026-10-10','a0000000-0000-0000-0000-0000000000a1','a0000000-0000-0000-0000-0000000000f1');
select pg_temp.ok((select balance_minor from account_balances where name='A Bank') = 7700000, 'bank: 100,000 − 5,000 − 6,000 repay − 7,000 transfer − 5,000 loan = 77,000');
select pg_temp.ok((select balance_minor from account_balances where name='A Cash') = 750000, 'cash: 500 + 7,000 transfer = 7,500');
select pg_temp.ok((select owed_minor from card_balances where name='A Visa') = 800000, 'card: 10,000 + 4,000 purchase − 6,000 repay = 8,000');
select pg_temp.ok((select outstanding_minor from liability_balances where name='A Loan') = 4600000, 'loan: 50,000 − 4,000 principal (interest not deducted) = 46,000');
select pg_temp.fails($$insert into transactions (type,amount_minor,occurred_on,from_account,from_card,method) values ('expense',1,'2026-10-01','a0000000-0000-0000-0000-0000000000a1','a0000000-0000-0000-0000-0000000000c1','bank')$$, 'expense cannot use an account AND a card');
select pg_temp.fails($$insert into transactions (type,amount_minor,occurred_on,from_account,to_account) values ('income',1,'2026-10-01','a0000000-0000-0000-0000-0000000000a1','a0000000-0000-0000-0000-0000000000a2')$$, 'income cannot come from your own account');
select pg_temp.fails($$insert into transactions (type,amount_minor,interest_minor,occurred_on,from_account,method) values ('expense',1,5,'2026-10-01','a0000000-0000-0000-0000-0000000000a1','bank')$$, 'interest only allowed on loan payments');
select pg_temp.fails($$insert into transactions (type,transfer_kind,amount_minor,occurred_on,from_account,to_account) values ('transfer','own',1,'2026-10-01','a0000000-0000-0000-0000-0000000000a1','a0000000-0000-0000-0000-0000000000a1')$$, 'transfer to the same account');
select pg_temp.fails($$insert into transactions (type,amount_minor,occurred_on,to_account) values ('income',0,'2026-10-01','a0000000-0000-0000-0000-0000000000a1')$$, 'zero amount');
select pg_temp.fails($$insert into cards (name,bank,last4,expiry,currency) values ('Bad','X','4111111111111111','08/28','LKR')$$, 'full card number rejected');

-- ---------------------------------------------------------------- User B: isolation
select set_config('request.jwt.claim.sub','bbbbbbbb-0000-0000-0000-000000000002',false), set_config('request.jwt.claim.email','b@example.com',false);
insert into accounts (id,kind,name,currency,opening_minor) values ('b0000000-0000-0000-0000-0000000000b1','bank','B Bank','LKR',2000000),('b0000000-0000-0000-0000-0000000000b2','savings','B Secret Savings','LKR',900000);
insert into transactions (type,amount_minor,occurred_on,from_account,method,category) values ('expense',10000,'2026-10-05','b0000000-0000-0000-0000-0000000000b1','bank','Food'),('expense',20000,'2026-10-06','b0000000-0000-0000-0000-0000000000b2','bank','Health');
select pg_temp.ok((select count(*) from accounts) = 2, 'B sees only own 2 accounts');
select pg_temp.ok((select count(*) from transactions) = 2, 'B sees only own transactions');
select pg_temp.ok((select count(*) from account_balances) = 2, 'balance view respects RLS');
select pg_temp.fails($$insert into transactions (type,amount_minor,occurred_on,from_account,method) values ('expense',1,'2026-10-01','a0000000-0000-0000-0000-0000000000a1','bank')$$, 'B cannot spend from A''s account');
select pg_temp.fails($$insert into accounts (owner_id,kind,name,currency) values ('aaaaaaaa-0000-0000-0000-000000000001','bank','Planted','LKR')$$, 'B cannot create records as A');
with u as (update accounts set opening_minor = 0 where id = 'a0000000-0000-0000-0000-0000000000a1' returning 1) select pg_temp.ok(count(*) = 0, 'B cannot update A''s account') from u;

-- ---------------------------------------------------------------- Groups and invitations
select set_config('request.jwt.claim.sub','aaaaaaaa-0000-0000-0000-000000000001',false), set_config('request.jwt.claim.email','a@example.com',false);
insert into groups (id,name,type,currency) values ('99999999-0000-0000-0000-000000000009','Family','Family','LKR');
select pg_temp.ok((select role||'/'||status from group_members where user_id = auth.uid()) = 'owner/active', 'creator becomes active owner');
insert into group_members (id,group_id,invited_email,display_name,role) values
 ('99999999-0000-0000-0000-0000000000b0','99999999-0000-0000-0000-000000000009','b@example.com','Kasun','member'),
 ('99999999-0000-0000-0000-0000000000c0','99999999-0000-0000-0000-000000000009','c@example.com','Nimali','viewer');
select pg_temp.fails($$insert into group_members (group_id,invited_email,display_name,role,status,user_id) values ('99999999-0000-0000-0000-000000000009','x@example.com','X','member','active','cccccccc-0000-0000-0000-000000000003')$$, 'cannot add someone as active without their acceptance');
select pg_temp.fails($$insert into group_members (group_id,invited_email,display_name,role) values ('99999999-0000-0000-0000-000000000009','y@example.com','Y','owner')$$, 'cannot invite a second owner');

select set_config('request.jwt.claim.sub','cccccccc-0000-0000-0000-000000000003',false), set_config('request.jwt.claim.email','c@example.com',false);
select pg_temp.fails($$select accept_invite('99999999-0000-0000-0000-0000000000b0')$$, 'C cannot accept B''s invitation');
select pg_temp.ok((select count(*) from group_members) = 1, 'invited C sees only their own invite, not the member list');

select set_config('request.jwt.claim.sub','bbbbbbbb-0000-0000-0000-000000000002',false), set_config('request.jwt.claim.email','b@example.com',false);
select pg_temp.ok((select count(*) from groups) = 1, 'B can see the group they were invited to');
select pg_temp.fails($$insert into group_tasks (group_id,name) values ('99999999-0000-0000-0000-000000000009','x')$$, 'B cannot act in the group before accepting');
select accept_invite('99999999-0000-0000-0000-0000000000b0');
select pg_temp.ok((select status from group_members where user_id = auth.uid()) = 'active', 'B accepted and is active');
select pg_temp.ok((select share_level from group_members where user_id = auth.uid()) = 'none', 'B shares nothing by default');

-- sharing levels
select set_config('request.jwt.claim.sub','aaaaaaaa-0000-0000-0000-000000000001',false), set_config('request.jwt.claim.email','a@example.com',false);
select pg_temp.ok((select count(*) from accounts where owner_id = 'bbbbbbbb-0000-0000-0000-000000000002') = 0, 'share none: A sees none of B''s accounts');
select pg_temp.fails($$select * from member_overview('99999999-0000-0000-0000-000000000009','99999999-0000-0000-0000-0000000000b0')$$, 'share none: no overview either');
select pg_temp.fails($$update group_members set share_level='full' where id='99999999-0000-0000-0000-0000000000b0'$$, 'A (owner) cannot change what B shares');

select set_config('request.jwt.claim.sub','bbbbbbbb-0000-0000-0000-000000000002',false), set_config('request.jwt.claim.email','b@example.com',false);
update group_members set share_level='overview' where user_id = auth.uid();
select set_config('request.jwt.claim.sub','aaaaaaaa-0000-0000-0000-000000000001',false), set_config('request.jwt.claim.email','a@example.com',false);
select pg_temp.ok((select net_worth from member_overview('99999999-0000-0000-0000-000000000009','99999999-0000-0000-0000-0000000000b0')) = 2900000 - 30000, 'overview: A sees B''s net worth total (29,000 − 300 spent)');
select pg_temp.ok((select count(*) from accounts where owner_id = 'bbbbbbbb-0000-0000-0000-000000000002') = 0, 'overview: still no individual accounts');
select pg_temp.ok((select count(*) from transactions where owner_id = 'bbbbbbbb-0000-0000-0000-000000000002') = 0, 'overview: still no transactions');

select set_config('request.jwt.claim.sub','bbbbbbbb-0000-0000-0000-000000000002',false), set_config('request.jwt.claim.email','b@example.com',false);
update group_members set share_level='selected' where user_id = auth.uid();
insert into group_shares (member_id,item_type,item_id) values ('99999999-0000-0000-0000-0000000000b0','account','b0000000-0000-0000-0000-0000000000b1');
select pg_temp.fails($$insert into group_shares (member_id,item_type,item_id) values ('99999999-0000-0000-0000-0000000000b0','account','a0000000-0000-0000-0000-0000000000a1')$$, 'B cannot share an account they don''t own');
select set_config('request.jwt.claim.sub','aaaaaaaa-0000-0000-0000-000000000001',false), set_config('request.jwt.claim.email','a@example.com',false);
select pg_temp.ok((select string_agg(name, ',') from accounts where owner_id = 'bbbbbbbb-0000-0000-0000-000000000002') = 'B Bank', 'selected: A sees only the shared account');
select pg_temp.ok((select string_agg(category, ',') from transactions where owner_id = 'bbbbbbbb-0000-0000-0000-000000000002') = 'Food', 'selected: A sees only that account''s transactions');
with u as (update accounts set name='hacked' where id='b0000000-0000-0000-0000-0000000000b1' returning 1) select pg_temp.ok(count(*) = 0, 'shared means read-only: A cannot edit B''s account') from u;
with u as (delete from transactions where owner_id='bbbbbbbb-0000-0000-0000-000000000002' returning 1) select pg_temp.ok(count(*) = 0, 'A cannot delete B''s shared transactions') from u;
select pg_temp.ok((select name from accounts where id='b0000000-0000-0000-0000-0000000000b1') = 'B Bank', 'B''s account name unchanged');

select set_config('request.jwt.claim.sub','bbbbbbbb-0000-0000-0000-000000000002',false), set_config('request.jwt.claim.email','b@example.com',false);
update group_members set share_level='full' where user_id = auth.uid();
select set_config('request.jwt.claim.sub','aaaaaaaa-0000-0000-0000-000000000001',false), set_config('request.jwt.claim.email','a@example.com',false);
select pg_temp.ok((select count(*) from accounts where owner_id = 'bbbbbbbb-0000-0000-0000-000000000002') = 2, 'full: A sees all of B''s accounts');
select pg_temp.ok((select count(*) from transactions where owner_id = 'bbbbbbbb-0000-0000-0000-000000000002') = 2, 'full: A sees all of B''s transactions');
select pg_temp.ok((select count(*) from accounts where owner_id = 'aaaaaaaa-0000-0000-0000-000000000001') = 2, 'sharing is one-way: A''s own 2 accounts');
select set_config('request.jwt.claim.sub','bbbbbbbb-0000-0000-0000-000000000002',false), set_config('request.jwt.claim.email','b@example.com',false);
select pg_temp.ok((select count(*) from accounts where owner_id = 'aaaaaaaa-0000-0000-0000-000000000001') = 0, 'B still sees none of A''s accounts (A shares nothing)');

-- outsider and viewer
select set_config('request.jwt.claim.sub','cccccccc-0000-0000-0000-000000000003',false), set_config('request.jwt.claim.email','c@example.com',false);
select pg_temp.ok((select count(*) from accounts) = 0, 'invited-but-not-accepted C sees no one''s accounts');
select accept_invite('99999999-0000-0000-0000-0000000000c0');
select pg_temp.ok((select count(*) from accounts where owner_id = 'bbbbbbbb-0000-0000-0000-000000000002') = 2, 'C (now active) sees what B shares with the group');
select pg_temp.fails($$insert into group_tasks (group_id,name) values ('99999999-0000-0000-0000-000000000009','x')$$, 'viewer cannot add tasks');

-- shared expenses must split exactly
select set_config('request.jwt.claim.sub','aaaaaaaa-0000-0000-0000-000000000001',false), set_config('request.jwt.claim.email','a@example.com',false);
begin;
insert into group_expenses (id,group_id,description,amount_minor,occurred_on,paid_by) values ('eeeeeeee-0000-0000-0000-000000000001','99999999-0000-0000-0000-000000000009','Hotel',1000001,'2026-10-20',(select id from group_members where user_id=auth.uid()));
insert into group_expense_splits (expense_id,group_id,member_id,share_minor) values
 ('eeeeeeee-0000-0000-0000-000000000001','99999999-0000-0000-0000-000000000009',(select id from group_members where user_id=auth.uid()),333334),
 ('eeeeeeee-0000-0000-0000-000000000001','99999999-0000-0000-0000-000000000009','99999999-0000-0000-0000-0000000000b0',333334),
 ('eeeeeeee-0000-0000-0000-000000000001','99999999-0000-0000-0000-000000000009','99999999-0000-0000-0000-0000000000c0',333333);
commit;
select pg_temp.ok((select count(*) from group_expense_splits) = 3, 'expense with exact splits saved');
select pg_temp.fails($x$do $d$ begin
  insert into group_expenses (id,group_id,description,amount_minor,occurred_on,paid_by) values ('eeeeeeee-0000-0000-0000-000000000002','99999999-0000-0000-0000-000000000009','Bad',500,'2026-10-20','99999999-0000-0000-0000-0000000000b0');
  insert into group_expense_splits (expense_id,group_id,member_id,share_minor) values ('eeeeeeee-0000-0000-0000-000000000002','99999999-0000-0000-0000-000000000009','99999999-0000-0000-0000-0000000000b0',100);
  set constraints all immediate; end $d$$x$, 'splits that don''t add up are rejected');

-- leaving and removal end access immediately
select set_config('request.jwt.claim.sub','bbbbbbbb-0000-0000-0000-000000000002',false), set_config('request.jwt.claim.email','b@example.com',false);
update group_members set status='left' where user_id = auth.uid();
select pg_temp.ok((select share_level from group_members where user_id = auth.uid()) = 'none', 'leaving resets sharing to none');
select set_config('request.jwt.claim.sub','aaaaaaaa-0000-0000-0000-000000000001',false), set_config('request.jwt.claim.email','a@example.com',false);
select pg_temp.ok((select count(*) from accounts where owner_id = 'bbbbbbbb-0000-0000-0000-000000000002') = 0, 'after B leaves, A sees none of B''s accounts');
select pg_temp.fails($$update group_members set status='removed' where user_id='aaaaaaaa-0000-0000-0000-000000000001'$$, 'owner cannot be removed');
update group_members set status='removed' where id='99999999-0000-0000-0000-0000000000c0';
select set_config('request.jwt.claim.sub','cccccccc-0000-0000-0000-000000000003',false), set_config('request.jwt.claim.email','c@example.com',false);
select pg_temp.ok((select count(*) from group_expenses) = 0, 'removed member loses access to group data');
select pg_temp.ok((select count(*) from groups) = 0, 'removed member no longer sees the group');

-- audit log
select set_config('request.jwt.claim.sub','aaaaaaaa-0000-0000-0000-000000000001',false), set_config('request.jwt.claim.email','a@example.com',false);
select pg_temp.ok((select count(*) from audit_log where action='member_updated') >= 5, 'sharing and membership changes are logged');
select pg_temp.fails($$insert into audit_log (group_id,action) values ('99999999-0000-0000-0000-000000000009','fake')$$, 'users cannot write fake audit entries');
select pg_temp.fails($$delete from audit_log$$, 'users cannot delete audit entries');

-- signed-out visitors
reset role; set role anon;
select pg_temp.fails($$select * from accounts$$, 'signed-out visitors cannot read anything');
reset role;
\echo ALL TESTS PASSED
