-- Tests for cloud sync storage. Run on a TEST database after all migrations.
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
insert into auth.users (id, email) values ('51000000-0000-0000-0000-000000000001','s1@example.com'),('52000000-0000-0000-0000-000000000002','s2@example.com');
set role authenticated;
select set_config('request.jwt.claim.sub','51000000-0000-0000-0000-000000000001',false), set_config('request.jwt.claim.email','s1@example.com',false);
insert into user_app_state (user_id, data, version) values ('51000000-0000-0000-0000-000000000001','{"accounts":[{"id":"a1","name":"BOC"}],"tx":[]}',1);
select pg_temp.ok((select data->'accounts'->0->>'name' from user_app_state) = 'BOC', 'owner saves and reads their data');
with u as (update user_app_state set data='{"accounts":[],"tx":[]}', version=2 where user_id=auth.uid() and version=1 returning version) select pg_temp.ok(count(*)=1, 'save with the expected version succeeds') from u;
with u as (update user_app_state set data='{}', version=2 where user_id=auth.uid() and version=1 returning version) select pg_temp.ok(count(*)=0, 'a stale device (old version) cannot overwrite newer data') from u;
select pg_temp.fails($$update user_app_state set version=9 where user_id=auth.uid()$$, 'version cannot jump');
select set_config('request.jwt.claim.sub','52000000-0000-0000-0000-000000000002',false), set_config('request.jwt.claim.email','s2@example.com',false);
select pg_temp.ok((select count(*) from user_app_state)=0, 'another user cannot see it');
with u as (update user_app_state set data='{}', version=3 where user_id='51000000-0000-0000-0000-000000000001' returning 1) select pg_temp.ok(count(*)=0, 'another user cannot change it') from u;
select pg_temp.fails($$insert into user_app_state (user_id,data) values ('51000000-0000-0000-0000-000000000001','{}')$$, 'another user cannot create a row for someone else');
reset role; set role anon;
select pg_temp.fails($$select * from user_app_state$$, 'signed-out visitors cannot read anything');
reset role;
\o
\echo ALL TESTS PASSED
