-- Run this full script in Supabase SQL Editor if error 42P17 persists.
-- It replaces all recursive team policies with security-definer membership checks.
create or replace function public.is_team_member(target_team uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.team_members
    where team_id = target_team and user_id = auth.uid());
$$;

create or replace function public.is_team_admin(target_team uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.team_members
    where team_id = target_team and user_id = auth.uid() and role = 'admin');
$$;

drop policy if exists "Members can view teams" on public.teams;
drop policy if exists "Users can create teams" on public.teams;
drop policy if exists "Members can view members" on public.team_members;
drop policy if exists "Admins can manage members" on public.team_members;
drop policy if exists "Members can access records" on public.team_records;
drop policy if exists "Members can write records" on public.team_records;
drop policy if exists "Members can update records" on public.team_records;

create policy "Members can view teams" on public.teams for select
  using (public.is_team_member(id));
create policy "Users can create teams" on public.teams for insert
  with check (auth.uid() = owner_id);
create policy "Members can view members" on public.team_members for select
  using (public.is_team_member(team_id));
create policy "Admins can manage members" on public.team_members for all
  using (public.is_team_admin(team_id)) with check (public.is_team_admin(team_id));
create policy "Members can access records" on public.team_records for select
  using (public.is_team_member(team_id));
create policy "Members can write records" on public.team_records for insert
  with check (public.is_team_member(team_id));
create policy "Members can update records" on public.team_records for update
  using (public.is_team_member(team_id)) with check (public.is_team_member(team_id));

grant execute on function public.is_team_member(uuid) to authenticated;
grant execute on function public.is_team_admin(uuid) to authenticated;
