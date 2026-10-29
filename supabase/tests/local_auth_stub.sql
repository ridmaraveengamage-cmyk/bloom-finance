-- FOR LOCAL TESTING ONLY on plain PostgreSQL. Never run this on your Supabase project (Supabase already has auth).
-- Minimal stand-in for Supabase's auth schema so the migration can be tested on plain PostgreSQL.
create schema auth;
create table auth.users (id uuid primary key, email text, raw_user_meta_data jsonb default '{}');
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
create function auth.email() returns text language sql stable as $$ select nullif(current_setting('request.jwt.claim.email', true), '') $$;
do $$ begin if not exists (select 1 from pg_roles where rolname=$q$anon$q$) then create role anon nologin; end if; if not exists (select 1 from pg_roles where rolname=$q$authenticated$q$) then create role authenticated nologin; end if; end $$;
grant usage on schema public, auth to anon, authenticated;
grant execute on function auth.uid(), auth.email() to anon, authenticated;
