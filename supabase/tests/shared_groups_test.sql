\set ON_ERROR_STOP 1
\set QUIET 1
\o /dev/null
create or replace function pg_temp.ok(cond boolean, label text) returns void language plpgsql as $$
begin if cond then raise notice 'PASS  %', label; else raise exception 'FAIL  %', label; end if; end $$;
create or replace function pg_temp.fails(sql text, label text) returns void language plpgsql as $$
begin begin execute sql; exception when others then raise notice 'PASS  % (blocked: %)', label, left(sqlerrm,70); return; end; raise exception 'FAIL  % (allowed)', label; end $$;
create or replace function pg_temp.as_user(u text) returns void language plpgsql as $$ begin perform set_config('request.jwt.claim.sub',u,false); end $$;
reset role;
insert into auth.users(id,email) values ('71000000-0000-0000-0000-0000000000a1','g_owner@x.com'),('72000000-0000-0000-0000-0000000000b2','g_kasun@x.com'),('73000000-0000-0000-0000-0000000000c3','g_stranger@x.com'),('74000000-0000-0000-0000-0000000000d4','g_nimali@x.com');
update profiles set username='ridma' where id='71000000-0000-0000-0000-0000000000a1';update profiles set username='kasun' where id='72000000-0000-0000-0000-0000000000b2';update profiles set username='nimali' where id='74000000-0000-0000-0000-0000000000d4';
create temp table t(k text primary key, v text);grant all on t to authenticated, anon;
set role authenticated;
select pg_temp.as_user('71000000-0000-0000-0000-0000000000a1');
insert into t select 'g', create_bloom_group('{"id":"g1","name":"Family","members":[{"id":"m1","name":"Ridma","uid":"71000000-0000-0000-0000-0000000000a1"},{"id":"m2","name":"Kasun"}],"exps":[]}');
select pg_temp.ok((select count(*) from bloom_groups)=1,'owner creates a shared group');
select pg_temp.ok((select role from bloom_group_members where user_id=auth.uid())='owner','owner is recorded as owner');
insert into t select 'inv_k', create_bloom_invite((select v from t where k='g')::uuid,'m2');
insert into t select 'inv_open', create_bloom_invite((select v from t where k='g')::uuid,null);
select pg_temp.fails($$select * from bloom_group_invites$$,'invite codes are not readable directly');
-- stranger cannot see group or invite people
select pg_temp.as_user('73000000-0000-0000-0000-0000000000c3');
select pg_temp.ok((select count(*) from bloom_groups)=0,'non-members cannot see the group');
select pg_temp.fails(format($$select create_bloom_invite(%L,null)$$,(select v from t where k='g')),'non-members cannot create invites');
with u as (update bloom_groups set data='{}', version=version+1 returning 1) select pg_temp.ok(count(*)=0,'non-members cannot edit the group') from u;
select pg_temp.fails(format($$insert into bloom_group_members(group_id,user_id) values (%L,auth.uid())$$,(select v from t where k='g')),'nobody can add themselves directly');
-- kasun previews and accepts the invite meant for "Kasun"
select pg_temp.as_user('72000000-0000-0000-0000-0000000000b2');
select pg_temp.ok((select group_name||'/'||inviter||'/'||member_name||'/'||status from preview_bloom_invite((select v from t where k='inv_k')))='Family/ridma/Kasun/ok','preview shows group, inviter and who it is for');
select accept_bloom_invite((select v from t where k='inv_k'));
select pg_temp.ok((select count(*) from bloom_groups)=1,'after accepting, Kasun sees the group');
select pg_temp.ok((select m->>'uid' from bloom_groups, jsonb_array_elements(data->'members') m where m->>'id'='m2')='72000000-0000-0000-0000-0000000000b2','Kasun is linked to the existing "Kasun" member');
select pg_temp.ok((select jsonb_array_length(data->'members') from bloom_groups)=2,'no duplicate member was added');
with u as (update bloom_groups set data=jsonb_set(data,'{exps}','[{"id":"e1","amt":500}]'), version=version+1 where version=(select version from bloom_groups) returning version) select pg_temp.ok(count(*)=1,'members can edit the shared group') from u;
with u as (update bloom_groups set data='{}', version=2 where version=1 returning 1) select pg_temp.ok(count(*)=0,'a stale edit (old version) is rejected') from u;
select pg_temp.fails($$update bloom_groups set data='{}', version=99$$,'version cannot jump');
select pg_temp.fails($$delete from bloom_groups$$||'',''||'members cannot delete the group') where false;
with d as (delete from bloom_groups returning 1) select pg_temp.ok(count(*)=0,'members cannot delete the group') from d;
select pg_temp.fails(format($$select remove_bloom_member(%L,'71000000-0000-0000-0000-0000000000a1')$$,(select v from t where k='g')),'members cannot remove people');
-- stranger tries the used single-person link
select pg_temp.as_user('73000000-0000-0000-0000-0000000000c3');
select pg_temp.ok((select status from preview_bloom_invite((select v from t where k='inv_k')))='used','a personal link cannot be reused');
select pg_temp.fails(format($$select accept_bloom_invite(%L)$$,(select v from t where k='inv_k')),'accepting a used personal link is blocked');
select pg_temp.ok((select status from preview_bloom_invite('nonsense-code-123'))='invalid','unknown codes are reported as invalid');
-- nimali joins with the open link: added as a new member with her username
select pg_temp.as_user('74000000-0000-0000-0000-0000000000d4');
select accept_bloom_invite((select v from t where k='inv_open'));
select pg_temp.ok((select count(*) from bloom_groups, jsonb_array_elements(data->'members') m where m->>'name'='nimali' and m->>'uid'='74000000-0000-0000-0000-0000000000d4')=1,'open link adds a new member with their username');
select accept_bloom_invite((select v from t where k='inv_open'));
select pg_temp.ok((select jsonb_array_length(data->'members') from bloom_groups)=3,'accepting twice does not duplicate');
select leave_bloom_group((select v from t where k='g')::uuid);
select pg_temp.ok((select count(*) from bloom_groups)=0,'after leaving, the group is no longer visible');
-- expired link
reset role;update bloom_group_invites set expires_at=now()-interval '1 day' where code=(select v from t where k='inv_open');set role authenticated;
select pg_temp.as_user('73000000-0000-0000-0000-0000000000c3');
select pg_temp.fails(format($$select accept_bloom_invite(%L)$$,(select v from t where k='inv_open')),'expired links are blocked');
-- owner removes kasun, owner cannot leave, owner deletes
select pg_temp.as_user('71000000-0000-0000-0000-0000000000a1');
select pg_temp.fails(format($$select leave_bloom_group(%L)$$,(select v from t where k='g')),'the owner cannot leave (only delete)');
select remove_bloom_member((select v from t where k='g')::uuid,'72000000-0000-0000-0000-0000000000b2');
select pg_temp.ok((select count(*) from bloom_group_members)=1,'owner removes a member');
select pg_temp.ok((select m ? 'uid' from bloom_groups, jsonb_array_elements(data->'members') m where m->>'id'='m2')=false,'removed member stays in the history but is unlinked');
select pg_temp.as_user('72000000-0000-0000-0000-0000000000b2');
select pg_temp.ok((select count(*) from bloom_groups)=0,'removed member can no longer see the group');
select pg_temp.as_user('71000000-0000-0000-0000-0000000000a1');
with d as (delete from bloom_groups returning 1) select pg_temp.ok(count(*)=1,'owner deletes the group') from d;
-- shares privacy: a member's shared figures disappear when they leave or are removed
select pg_temp.as_user('71000000-0000-0000-0000-0000000000a1');
insert into t select 'g2', create_bloom_group('{"id":"g2","name":"Trip","members":[{"id":"o","name":"Ridma","uid":"71000000-0000-0000-0000-0000000000a1"}],"shares":{}}');
insert into t select 'inv2', create_bloom_invite((select v from t where k='g2')::uuid,null);
select pg_temp.as_user('72000000-0000-0000-0000-0000000000b2');
select accept_bloom_invite((select v from t where k='inv2'));
with u as (update bloom_groups set data=jsonb_set(data,'{shares,72000000-0000-0000-0000-0000000000b2}','{"lvl":"overview","T":{"LKR":{"net":100}}}'), version=version+1 where id=(select v from t where k='g2')::uuid returning 1) select pg_temp.ok(count(*)=1,'member publishes shared figures') from u;
select leave_bloom_group((select v from t where k='g2')::uuid);
select pg_temp.as_user('71000000-0000-0000-0000-0000000000a1');
select pg_temp.ok(not ((select data->'shares' from bloom_groups where id=(select v from t where k='g2')::uuid) ? '72000000-0000-0000-0000-0000000000b2'),'leaving deletes their shared figures');
with d as (delete from bloom_groups where id=(select v from t where k='g2')::uuid returning 1) select pg_temp.ok(count(*)=1,'cleanup') from d;
reset role; set role anon;
select pg_temp.fails($$select * from bloom_groups$$,'signed-out visitors cannot read groups');
reset role;
\o
\echo ALL TESTS PASSED
