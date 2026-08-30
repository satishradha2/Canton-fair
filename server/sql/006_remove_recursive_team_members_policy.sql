-- Removes the legacy recursive policy shown in pg_policies as
-- "Admins manage members". The safe replacement already exists.
drop policy if exists "Admins manage members" on public.team_members;
