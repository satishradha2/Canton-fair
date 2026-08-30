-- Run after 007 and 008 in the Supabase SQL Editor.
-- Adds mobile member management and makes the viewer role read-only.

create or replace function public.is_team_writer(target_team uuid)
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
      and role in ('admin', 'member')
  );
$$;

grant execute on function public.is_team_writer(uuid) to authenticated;

create or replace function public.list_team_members(target_team uuid)
returns table (user_id uuid, email text, role text)
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if not public.is_team_member(target_team) then
    raise exception 'Team access is required';
  end if;

  return query
  select members.user_id, coalesce(users.email, ''), members.role
  from public.team_members as members
  join auth.users as users on users.id = members.user_id
  where members.team_id = target_team
  order by members.role = 'admin' desc, users.email asc;
end;
$$;

create or replace function public.update_team_member_role(
  target_team uuid,
  target_user uuid,
  member_role text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare existing_role text;
begin
  if not public.is_team_admin(target_team) then
    raise exception 'Only team admins can update members';
  end if;
  if member_role not in ('admin', 'member', 'viewer') then
    raise exception 'Invalid team role';
  end if;

  select role into existing_role
  from public.team_members
  where team_id = target_team and user_id = target_user;
  if not found then
    raise exception 'Team member not found';
  end if;
  if existing_role = 'admin' and member_role <> 'admin'
    and (select count(*) from public.team_members
         where team_id = target_team and role = 'admin') <= 1 then
    raise exception 'A team must keep at least one admin';
  end if;

  update public.team_members
  set role = member_role
  where team_id = target_team and user_id = target_user;
end;
$$;

create or replace function public.remove_team_member(
  target_team uuid,
  target_user uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare existing_role text;
begin
  if not public.is_team_admin(target_team) then
    raise exception 'Only team admins can remove members';
  end if;
  if target_user = auth.uid() then
    raise exception 'Use another admin to remove your own access';
  end if;

  select role into existing_role
  from public.team_members
  where team_id = target_team and user_id = target_user;
  if not found then
    raise exception 'Team member not found';
  end if;
  if existing_role = 'admin'
    and (select count(*) from public.team_members
         where team_id = target_team and role = 'admin') <= 1 then
    raise exception 'A team must keep at least one admin';
  end if;

  delete from public.team_members
  where team_id = target_team and user_id = target_user;
end;
$$;

grant execute on function public.list_team_members(uuid) to authenticated;
grant execute on function public.update_team_member_role(uuid, uuid, text) to authenticated;
grant execute on function public.remove_team_member(uuid, uuid) to authenticated;

drop policy if exists "Members can write records" on public.team_records;
drop policy if exists "Members can update records" on public.team_records;

create policy "Members can write records" on public.team_records for insert
with check (public.is_team_writer(team_id));

create policy "Members can update records" on public.team_records for update
using (public.is_team_writer(team_id))
with check (public.is_team_writer(team_id));

create or replace function public.upsert_team_record(
  target_team uuid,
  target_record_type text,
  target_record_id text,
  target_payload jsonb,
  expected_version integer default null
)
returns table (version integer, updated_at timestamptz)
language plpgsql
security definer
set search_path = public
as $$
declare existing public.team_records%rowtype;
begin
  if auth.uid() is null or not public.is_team_writer(target_team) then
    raise exception 'Team write access is required';
  end if;

  select * into existing from public.team_records
  where team_id = target_team and record_type = target_record_type
    and record_id = target_record_id;

  if found and expected_version is not null and existing.version <> expected_version then
    raise exception 'sync_conflict';
  end if;

  insert into public.team_records (team_id, record_type, record_id, payload, updated_by, version)
  values (target_team, target_record_type, target_record_id, target_payload, auth.uid(), 1)
  on conflict (team_id, record_type, record_id) do update set
    payload = excluded.payload,
    updated_by = auth.uid(),
    updated_at = now(),
    version = public.team_records.version + 1
  returning public.team_records.version, public.team_records.updated_at
  into version, updated_at;

  return next;
end;
$$;

grant execute on function public.upsert_team_record(uuid, text, text, jsonb, integer) to authenticated;

drop policy if exists "Team members can upload team attachments" on storage.objects;
drop policy if exists "Team members can update team attachments" on storage.objects;
drop policy if exists "Team members can delete team attachments" on storage.objects;

create policy "Team members can upload team attachments"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'team-attachments'
  and public.is_team_writer((storage.foldername(name))[1]::uuid)
);

create policy "Team members can update team attachments"
on storage.objects for update to authenticated
using (
  bucket_id = 'team-attachments'
  and public.is_team_writer((storage.foldername(name))[1]::uuid)
)
with check (
  bucket_id = 'team-attachments'
  and public.is_team_writer((storage.foldername(name))[1]::uuid)
);

create policy "Team members can delete team attachments"
on storage.objects for delete to authenticated
using (
  bucket_id = 'team-attachments'
  and public.is_team_writer((storage.foldername(name))[1]::uuid)
);
