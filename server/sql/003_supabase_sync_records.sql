-- Run after 002_supabase_create_team.sql in Supabase SQL Editor.
-- Each client supplies a stable UUID record_id. Writes are rejected when the
-- server has a newer version, so the mobile app can show a conflict instead
-- of silently losing a teammate's edit.
alter table public.team_records
  add column if not exists version integer not null default 1;

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
declare
  existing public.team_records%rowtype;
begin
  if auth.uid() is null or not public.is_team_member(target_team) then
    raise exception 'Team access is required';
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
