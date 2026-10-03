-- Additive migration. Does not delete business records or login accounts.
begin;
alter table public.team_records add column if not exists created_by uuid references auth.users(id);
-- Only untouched records have a provable creator from the existing editor column.
-- The exclusive lock prevents application writes while trigger guards are paused
-- for this metadata-only maintenance. Every original trigger mode is restored;
-- a failure rolls back both the backfill and trigger changes atomically.
lock table public.team_records in access exclusive mode;
do $backfill$
declare
  guard record;
  original_guards jsonb;
  before_records text;
  after_records text;
begin
  select md5(coalesce(jsonb_agg(to_jsonb(r) - 'created_by'
    order by r.team_id, r.record_type, r.record_id)::text, '[]'))
    into before_records from public.team_records r;
  select coalesce(jsonb_agg(jsonb_build_object('name', tgname, 'mode', tgenabled)), '[]')
    into original_guards from pg_trigger
    where tgrelid = 'public.team_records'::regclass and not tgisinternal and tgenabled <> 'D';
  for guard in select * from jsonb_to_recordset(original_guards) as g(name text, mode text) loop
    execute format('alter table public.team_records disable trigger %I', guard.name);
  end loop;
  update public.team_records set created_by = updated_by
    where created_by is null and version = 1;
  for guard in select * from jsonb_to_recordset(original_guards) as g(name text, mode text) loop
    execute format('alter table public.team_records enable %s trigger %I',
      case guard.mode when 'A' then 'always' when 'R' then 'replica' else '' end, guard.name);
  end loop;
  select md5(coalesce(jsonb_agg(to_jsonb(r) - 'created_by'
    order by r.team_id, r.record_type, r.record_id)::text, '[]'))
    into after_records from public.team_records r;
  if before_records is distinct from after_records then
    raise exception 'Ownership backfill changed business data; migration rolled back';
  end if;
end $backfill$;

create or replace function public.guard_record_creator()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Sign in required for business record writes'; end if;
  if not public.is_team_writer(coalesce(new.team_id, old.team_id)) then
    raise exception 'Workspace write access required';
  end if;
  if tg_op = 'INSERT' then
    new.created_by := auth.uid();
    return new;
  end if;
  if not public.is_team_admin(old.team_id) and old.created_by is distinct from auth.uid() then
    raise exception 'View only: only the creator or a workspace administrator can edit this record';
  end if;
  if tg_op = 'DELETE' then return old; end if;
  if new.team_id <> old.team_id or new.record_type <> old.record_type or new.record_id <> old.record_id then
    raise exception 'Record identity cannot be changed';
  end if;
  new.created_by := old.created_by;
  return new;
end $$;
drop trigger if exists guard_record_creator on public.team_records;
create trigger guard_record_creator before insert or update or delete on public.team_records
for each row execute function public.guard_record_creator();

-- Restrictive policies supplement existing policies, including direct API writes.
drop policy if exists record_creator_update on public.team_records;
create policy record_creator_update on public.team_records as restrictive for update to authenticated
using (public.is_team_admin(team_id) or created_by = auth.uid())
with check (public.is_team_admin(team_id) or created_by = auth.uid());
drop policy if exists record_creator_delete on public.team_records;
create policy record_creator_delete on public.team_records as restrictive for delete to authenticated
using (public.is_team_admin(team_id) or created_by = auth.uid());

drop policy if exists attachment_creator_update on storage.objects;
create policy attachment_creator_update on storage.objects as restrictive for update to authenticated
using (bucket_id <> 'team-attachments' or owner_id = auth.uid()::text
  or public.is_team_admin((storage.foldername(name))[1]::uuid))
with check (bucket_id <> 'team-attachments' or owner_id = auth.uid()::text
  or public.is_team_admin((storage.foldername(name))[1]::uuid));
drop policy if exists attachment_creator_delete on storage.objects;
create policy attachment_creator_delete on storage.objects as restrictive for delete to authenticated
using (bucket_id <> 'team-attachments' or owner_id = auth.uid()::text
  or public.is_team_admin((storage.foldername(name))[1]::uuid));

create or replace function public.create_team(team_name text)
returns table(id uuid, name text, role text)
language plpgsql security definer set search_path = public as $$
declare created_team public.teams%rowtype;
begin
  if not exists(select 1 from public.team_members m where m.user_id = auth.uid() and m.role = 'admin') then
    raise exception 'Only an existing workspace administrator can create workspaces';
  end if;
  if coalesce(trim(team_name), '') = '' then raise exception 'Workspace name required'; end if;
  insert into public.teams(name, owner_id) values(trim(team_name), auth.uid()) returning * into created_team;
  insert into public.team_members(team_id, user_id, role) values(created_team.id, auth.uid(), 'admin');
  return query select created_team.id, created_team.name, 'admin'::text;
end $$;

create or replace function public.rename_team(target_team uuid, team_name text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_team_admin(target_team) then raise exception 'Administrator access required'; end if;
  if coalesce(trim(team_name), '') = '' then raise exception 'Workspace name required'; end if;
  update public.teams set name = trim(team_name) where id = target_team;
end $$;

create or replace function public.delete_empty_team(target_team uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform 1 from public.teams where id = target_team for update;
  if not public.is_team_admin(target_team) then raise exception 'Administrator access required'; end if;
  if exists(select 1 from public.team_records where team_id = target_team)
    or exists(select 1 from storage.objects where bucket_id = 'team-attachments' and (storage.foldername(name))[1] = target_team::text)
    or exists(select 1 from public.phone_cleanup_requests where team_id = target_team)
    or exists(select 1 from public.phone_cleanup_events where team_id = target_team) then
    raise exception 'Workspace is not empty. No records, files or accounts were deleted';
  end if;
  delete from public.team_members where team_id = target_team;
  delete from public.teams where id = target_team;
end $$;
revoke all on function public.create_team(text), public.rename_team(uuid,text), public.delete_empty_team(uuid) from public;
grant execute on function public.create_team(text), public.rename_team(uuid,text), public.delete_empty_team(uuid) to authenticated;
notify pgrst, 'reload schema';
commit;
