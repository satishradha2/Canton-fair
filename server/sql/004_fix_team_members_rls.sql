-- Fixes Postgres error 42P17: infinite recursion in the team_members policy.
-- Run in Supabase SQL Editor after the earlier team migrations.
create or replace function public.is_team_member(target_team uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.team_members
    where team_id = target_team
      and user_id = auth.uid()
  );
$$;

grant execute on function public.is_team_member(uuid) to authenticated;
