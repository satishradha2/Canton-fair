-- Run this in Supabase Dashboard > SQL Editor after creating the teams tables.
-- It creates the team and makes the signed-in creator its administrator atomically.
create or replace function public.create_team(team_name text)
returns table (id uuid, name text, role text)
language plpgsql
security definer
set search_path = public
as $$
declare
  created_team public.teams%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Sign in is required';
  end if;

  if coalesce(trim(team_name), '') = '' then
    raise exception 'A team name is required';
  end if;

  insert into public.teams (name, owner_id)
  values (trim(team_name), auth.uid())
  returning * into created_team;

  insert into public.team_members (team_id, user_id, role)
  values (created_team.id, auth.uid(), 'admin');

  return query
  select created_team.id, created_team.name, 'admin'::text;
end;
$$;

grant execute on function public.create_team(text) to authenticated;
