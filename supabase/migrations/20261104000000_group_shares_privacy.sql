-- When someone leaves or is removed, their shared financial figures are deleted from the group straight away.
create or replace function public.leave_bloom_group(p_group uuid) returns void
language plpgsql security definer set search_path = public as $$
declare g bloom_groups; mid text;
begin
  select * into g from bloom_groups where id = p_group for update;
  if not found or not public.is_bloom_member(p_group) then raise exception 'You''re not in this group'; end if;
  if g.owner = auth.uid() then raise exception 'You created this group, so you can delete it but not leave it'; end if;
  select m->>'id' into mid from jsonb_array_elements(g.data->'members') m where m->>'uid' = auth.uid()::text;
  delete from bloom_group_members where group_id = p_group and user_id = auth.uid();
  update bloom_groups set data = (case when mid is null then g.data else public.bloom_set_member_uid(g.data, mid, null) end) #- array['shares', auth.uid()::text],
    version = version + 1 where id = p_group;
end $$;

create or replace function public.remove_bloom_member(p_group uuid, p_user uuid) returns void
language plpgsql security definer set search_path = public as $$
declare g bloom_groups; mid text;
begin
  select * into g from bloom_groups where id = p_group for update;
  if not found or g.owner <> auth.uid() then raise exception 'Only the person who created the group can remove members'; end if;
  if p_user = auth.uid() then raise exception 'You can''t remove yourself'; end if;
  select m->>'id' into mid from jsonb_array_elements(g.data->'members') m where m->>'uid' = p_user::text;
  delete from bloom_group_members where group_id = p_group and user_id = p_user;
  update bloom_groups set data = (case when mid is null then g.data else public.bloom_set_member_uid(g.data, mid, null) end) #- array['shares', p_user::text],
    version = version + 1 where id = p_group;
end $$;
