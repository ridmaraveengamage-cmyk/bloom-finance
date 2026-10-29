-- Tests for personal / group tags on transactions. Run on a TEST database after all migrations.
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
insert into auth.users (id, email) values ('11111111-0000-0000-0000-000000000011','g@example.com'),('22222222-0000-0000-0000-000000000022','h@example.com'),('33333333-0000-0000-0000-000000000033','i@example.com');
set role authenticated;
-- G owns a group (partial, shares nothing) and invites H
select set_config('request.jwt.claim.sub','11111111-0000-0000-0000-000000000011',false), set_config('request.jwt.claim.email','g@example.com',false);
insert into accounts (id,kind,name,currency,opening_minor) values ('70000000-0000-0000-0000-000000000001','bank','G Bank','LKR',1000000);
insert into groups (id,name,type,currency) values ('77777777-0000-0000-0000-000000000001','Trip','Trip or event','LKR');
insert into group_members (id,group_id,invited_email,display_name) values ('77777777-0000-0000-0000-0000000000a1','77777777-0000-0000-0000-000000000001','h@example.com','H');
insert into transactions (id,type,amount_minor,occurred_on,from_account,method,category,note) values
 ('71000000-0000-0000-0000-000000000001','expense',50000,'2026-10-10','70000000-0000-0000-0000-000000000001','bank','Transport','Fuel for trip'),
 ('71000000-0000-0000-0000-000000000002','expense',90000,'2026-10-11','70000000-0000-0000-0000-000000000001','bank','Health','Private');
insert into transaction_groups (transaction_id,group_id) values ('71000000-0000-0000-0000-000000000001','77777777-0000-0000-0000-000000000001');
select pg_temp.ok((select balance_minor from account_balances where id='70000000-0000-0000-0000-000000000001') = 860000, 'tagged expense still counts in personal balance');
select set_config('request.jwt.claim.sub','22222222-0000-0000-0000-000000000022',false), set_config('request.jwt.claim.email','h@example.com',false);
select pg_temp.ok((select count(*) from transactions where owner_id='11111111-0000-0000-0000-000000000011') = 0, 'before accepting: H sees none of G''s transactions');
select accept_invite('77777777-0000-0000-0000-0000000000a1');
select pg_temp.ok((select string_agg(note, ',') from transactions where owner_id='11111111-0000-0000-0000-000000000011') = 'Fuel for trip', 'member sees ONLY the tagged transaction');
select pg_temp.ok((select count(*) from accounts where owner_id='11111111-0000-0000-0000-000000000011') = 0, 'tagging shares the transaction, not the account');
select pg_temp.ok((select count(*) from transaction_groups) = 1, 'member sees the tag');
with u as (update transactions set amount_minor=1 where id='71000000-0000-0000-0000-000000000001' returning 1) select pg_temp.ok(count(*) = 0, 'member cannot edit a tagged transaction') from u;
select pg_temp.fails($$insert into transaction_groups (transaction_id,group_id,owner_id) values ('71000000-0000-0000-0000-000000000002','77777777-0000-0000-0000-000000000001','11111111-0000-0000-0000-000000000011')$$, 'member cannot tag someone else''s transaction');
select set_config('request.jwt.claim.sub','33333333-0000-0000-0000-000000000033',false), set_config('request.jwt.claim.email','i@example.com',false);
insert into accounts (id,kind,name,currency,opening_minor) values ('70000000-0000-0000-0000-000000000003','bank','I Bank','LKR',1);
insert into transactions (id,type,amount_minor,occurred_on,to_account,category) values ('71000000-0000-0000-0000-000000000003','income',1,'2026-10-12','70000000-0000-0000-0000-000000000003','Gift');
select pg_temp.fails($$insert into transaction_groups (transaction_id,group_id) values ('71000000-0000-0000-0000-000000000003','77777777-0000-0000-0000-000000000001')$$, 'cannot tag to a group you are not in');
select pg_temp.ok((select count(*) from transactions where owner_id <> auth.uid()) = 0, 'outsider sees no tagged transactions');
-- untagging and leaving hide it again
select set_config('request.jwt.claim.sub','22222222-0000-0000-0000-000000000022',false), set_config('request.jwt.claim.email','h@example.com',false);
update group_members set status='left' where id='77777777-0000-0000-0000-0000000000a1';
select pg_temp.ok((select count(*) from transactions where owner_id='11111111-0000-0000-0000-000000000011') = 0, 'after leaving, tagged transactions are hidden');
select set_config('request.jwt.claim.sub','11111111-0000-0000-0000-000000000011',false), set_config('request.jwt.claim.email','g@example.com',false);
delete from transaction_groups where transaction_id='71000000-0000-0000-0000-000000000001';
select pg_temp.ok((select count(*) from transaction_groups) = 0, 'owner can untag (mark personal again)');
reset role;
\o
\echo ALL TESTS PASSED
