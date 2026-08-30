-- Run in Supabase SQL Editor. Lets a team admin add an existing app user by email.
drop function if exists public.invite_team_member(uuid, text, text);

create function public.invite_team_member(
  target_team uuid,
  member_email text,
  member_role text default 'member'
)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  target_user auth.users%rowtype;
begin
  if not public.is_team_admin(target_team) then
    raise exception 'Only team admins can add members';
  end if;
  if member_role not in ('admin', 'member', 'viewer') then
    raise exception 'Invalid team role';
  end if;
  select * into target_user from auth.users as users
    where lower(users.email) = lower(trim(member_email));
  if not found then
    raise exception 'No account exists for this email yet';
  end if;
  insert into public.team_members (team_id, user_id, role)
  values (target_team, target_user.id, member_role)
  on conflict (team_id, user_id) do update set role = excluded.role;
  return;
end;
$$;

grant execute on function public.invite_team_member(uuid, text, text) to authenticated;
