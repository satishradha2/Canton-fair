-- Match the RPC's declared text result to auth.users.email (varchar).
begin;
create or replace function public.list_team_members(target_team uuid)
returns table(user_id uuid, email text, role text)
language plpgsql security definer set search_path = public, auth
as $$
begin
  if not public.is_team_member(target_team) then
    raise exception 'Team access is required';
  end if;
  return query
  select members.user_id, coalesce(users.email::text, ''::text), members.role
  from public.team_members as members
  join auth.users as users on users.id = members.user_id
  where members.team_id = target_team
  order by members.role = 'admin' desc, users.email asc;
end;
$$;
commit;
