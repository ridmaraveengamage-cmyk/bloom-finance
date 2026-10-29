-- Tests for sign-up profile details. Run on a TEST database after all migrations.
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
insert into auth.users (id, email, raw_user_meta_data) values
 ('a1000000-0000-0000-0000-000000000001','ridma@example.com','{"username":"ridma.g","phone":"+94771234567","country":"Sri Lanka"}'),
 ('a1000000-0000-0000-0000-000000000002','copy@example.com','{"username":"RIDMA.G","phone":"0771234567","country":"Sri Lanka"}'),
 ('a1000000-0000-0000-0000-000000000003','google@example.com','{"full_name":"Kasun Perera"}');
select pg_temp.ok((select username||'|'||phone||'|'||country from profiles where id='a1000000-0000-0000-0000-000000000001') = 'ridma.g|+94771234567|Sri Lanka', 'sign-up details saved to the profile');
select pg_temp.ok((select username is null and phone is null and country = 'Sri Lanka' from profiles where id='a1000000-0000-0000-0000-000000000002'), 'taken username (any capitals) and badly formatted phone are left empty, sign-up still works');
select pg_temp.ok((select username is null and display_name = 'Kasun Perera' from profiles where id='a1000000-0000-0000-0000-000000000003'), 'Google/Apple sign-up: profile created, details to be completed');
set role anon;
select pg_temp.ok(username_available('new.user') and not username_available('Ridma.G') and not username_available('x'), 'signed-out form can check username availability (taken, too short)');
select pg_temp.fails($$select username from profiles$$, 'signed-out visitors cannot read profiles');
set role authenticated;
select set_config('request.jwt.claim.sub','a1000000-0000-0000-0000-000000000003',false), set_config('request.jwt.claim.email','google@example.com',false);
update profiles set username='kasun.p', phone='+94712345678', country='Sri Lanka' where id = auth.uid();
select pg_temp.ok((select username from profiles where id = auth.uid()) = 'kasun.p', 'user completes their own profile');
select pg_temp.fails($$update profiles set username='ridma.g' where id = auth.uid()$$, 'cannot take someone else''s username');
select pg_temp.fails($$update profiles set phone='0771234567' where id = auth.uid()$$, 'phone must be in international format');
select pg_temp.fails($$update profiles set username='no spaces!' where id = auth.uid()$$, 'username format enforced');
select pg_temp.ok((select count(*) from profiles) = 1, 'users see only their own profile');
with u as (update profiles set country='India' where id='a1000000-0000-0000-0000-000000000001' returning 1) select pg_temp.ok(count(*) = 0, 'cannot change another user''s profile') from u;
reset role;
\o
\echo ALL TESTS PASSED
