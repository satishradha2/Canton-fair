create table if not exists public.record_edit_locks (
  team_id uuid not null references public.teams(id) on delete cascade,
  record_type text not null,
  record_id text not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  expires_at timestamptz not null,
  primary key (team_id, record_type, record_id)
);

alter table public.record_edit_locks enable row level security;
drop policy if exists "Team members can view locks" on public.record_edit_locks;
create policy "Team members can view locks" on public.record_edit_locks for select
using (public.is_team_member(team_id));

create or replace function public.acquire_edit_lock(
  target_team uuid, target_record_type text, target_record_id text)
returns table(user_id uuid, user_email text, expires_at timestamptz)
language plpgsql security definer set search_path = public, auth as $$
declare current_lock public.record_edit_locks%rowtype;
begin
  if not public.is_team_member(target_team) then raise exception 'not_a_team_member'; end if;
  perform pg_advisory_xact_lock(
    hashtextextended(target_team::text || ':' || target_record_type || ':' || target_record_id, 0));
  delete from public.record_edit_locks where expires_at < now();
  select * into current_lock from public.record_edit_locks
    where team_id = target_team and record_type = target_record_type and record_id = target_record_id;
  if current_lock.user_id is not null and current_lock.user_id <> auth.uid() then
    return query select current_lock.user_id, coalesce(u.email, ''), current_lock.expires_at
      from auth.users u where u.id = current_lock.user_id;
    return;
  end if;
  insert into public.record_edit_locks(team_id, record_type, record_id, user_id, expires_at)
    values(target_team, target_record_type, target_record_id, auth.uid(), now() + interval '5 minutes')
    on conflict(team_id, record_type, record_id) do update
      set user_id = auth.uid(), expires_at = excluded.expires_at;
  return query select auth.uid(), coalesce(auth.jwt() ->> 'email', ''), now() + interval '5 minutes';
end $$;

create or replace function public.release_edit_lock(
  target_team uuid, target_record_type text, target_record_id text)
returns void language sql security definer set search_path = public as $$
  delete from public.record_edit_locks where team_id = target_team
    and record_type = target_record_type and record_id = target_record_id
    and user_id = auth.uid();
$$;

revoke all on function public.acquire_edit_lock(uuid,text,text) from public;
grant execute on function public.acquire_edit_lock(uuid,text,text) to authenticated;
revoke all on function public.release_edit_lock(uuid,text,text) from public;
grant execute on function public.release_edit_lock(uuid,text,text) to authenticated;
