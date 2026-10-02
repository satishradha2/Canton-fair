-- Additive approval/audit contract. Does not delete or modify team_records,
-- storage objects, authentication accounts, roles or team memberships.
begin;
create table if not exists public.phone_cleanup_requests (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null references public.teams(id),
  requested_by uuid not null references auth.users(id),
  requested_email text not null default '', device_id text not null,
  manifest_hash text not null, summary jsonb not null, reason text not null,
  status text not null default 'pending' check (status in ('pending','approved','rejected','executing','completed')),
  reviewed_by uuid references auth.users(id), review_note text,
  created_at timestamptz not null default now(), reviewed_at timestamptz,
  completed_at timestamptz
);
create table if not exists public.phone_cleanup_events (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null references public.teams(id),
  actor uuid not null references auth.users(id), device_id text not null,
  manifest_hash text not null, summary jsonb not null,
  approval_id uuid references public.phone_cleanup_requests(id),
  result jsonb, created_at timestamptz not null default now(), completed_at timestamptz
);
alter table public.phone_cleanup_requests enable row level security;
alter table public.phone_cleanup_events enable row level security;
drop policy if exists cleanup_request_read on public.phone_cleanup_requests;
create policy cleanup_request_read on public.phone_cleanup_requests for select to authenticated
  using (public.is_team_member(team_id) and (requested_by=auth.uid() or public.is_team_admin(team_id)));
drop policy if exists cleanup_event_read on public.phone_cleanup_events;
create policy cleanup_event_read on public.phone_cleanup_events for select to authenticated
  using (public.is_team_member(team_id) and (actor=auth.uid() or public.is_team_admin(team_id)));
revoke all on public.phone_cleanup_requests, public.phone_cleanup_events from public, anon, authenticated;
grant select on public.phone_cleanup_requests, public.phone_cleanup_events to authenticated;

create or replace function public.request_phone_cleanup(target_team uuid, target_device text,
  snapshot_hash text, summary jsonb, request_reason text) returns uuid
language plpgsql security definer set search_path=public as $$
declare result uuid;
begin
  if auth.uid() is null or not public.is_team_member(target_team) then raise exception 'Team access required'; end if;
  if length(target_device) not between 16 and 128 or snapshot_hash !~ '^[a-f0-9]{64}$'
    or jsonb_typeof(summary) is distinct from 'object' or length(btrim(request_reason)) not between 1 and 1000
    then raise exception 'Invalid cleanup request'; end if;
  insert into public.phone_cleanup_requests(team_id,requested_by,requested_email,device_id,manifest_hash,summary,reason)
    values(target_team,auth.uid(),coalesce((select email from auth.users where id=auth.uid()),''),target_device,snapshot_hash,summary,btrim(request_reason)) returning id into result;
  return result;
end $$;

create or replace function public.review_phone_cleanup(request_id uuid, approve boolean, review_note text default '') returns void
language plpgsql security definer set search_path=public as $$
declare item public.phone_cleanup_requests%rowtype;
begin
  select * into item from public.phone_cleanup_requests where id=request_id for update;
  if item.id is null or auth.uid() is null or not public.is_team_admin(item.team_id) then raise exception 'Administrator approval required'; end if;
  if item.status <> 'pending' then raise exception 'This request has already been reviewed'; end if;
  update public.phone_cleanup_requests set status=case when approve then 'approved' else 'rejected' end,
    reviewed_by=auth.uid(), reviewed_at=now(), review_note=left(coalesce(review_phone_cleanup.review_note,''),1000) where id=request_id;
end $$;

create or replace function public.begin_phone_cleanup(target_team uuid, target_device text,
  snapshot_hash text, summary jsonb, approval_id uuid default null) returns uuid
language plpgsql security definer set search_path=public as $$
declare item public.phone_cleanup_requests%rowtype; result uuid;
begin
  if auth.uid() is null or not public.is_team_member(target_team) then raise exception 'Team access required'; end if;
  if length(target_device) not between 16 and 128 or snapshot_hash !~ '^[a-f0-9]{64}$'
    or jsonb_typeof(summary) is distinct from 'object' then raise exception 'Invalid snapshot'; end if;
  if approval_id is not null then
    select * into item from public.phone_cleanup_requests where id=approval_id for update;
    if item.id is null or item.team_id<>target_team or item.requested_by<>auth.uid()
      or item.device_id<>target_device or item.manifest_hash<>snapshot_hash or item.status<>'approved'
      or item.reviewed_at < now()-interval '7 days'
      then raise exception 'Approval is missing, expired or does not match this phone snapshot'; end if;
    update public.phone_cleanup_requests set status='executing' where id=approval_id;
  end if;
  insert into public.phone_cleanup_events(team_id,actor,device_id,manifest_hash,summary,approval_id)
    values(target_team,auth.uid(),target_device,snapshot_hash,summary,approval_id) returning id into result;
  return result;
end $$;

create or replace function public.complete_phone_cleanup(event_id uuid, result jsonb) returns void
language plpgsql security definer set search_path=public as $$
declare item public.phone_cleanup_events%rowtype;
begin
  select * into item from public.phone_cleanup_events where id=event_id for update;
  if item.id is null or item.actor<>auth.uid() or auth.uid() is null or not public.is_team_member(item.team_id) then raise exception 'Cleanup owner required'; end if;
  if item.completed_at is not null then return; end if;
  if jsonb_typeof(result) is distinct from 'object' then raise exception 'Invalid completion result'; end if;
  update public.phone_cleanup_events set result=complete_phone_cleanup.result,completed_at=now() where id=event_id;
  if item.approval_id is not null then update public.phone_cleanup_requests set status='completed',completed_at=now() where id=item.approval_id and status='executing'; end if;
end $$;
revoke all on function public.request_phone_cleanup(uuid,text,text,jsonb,text), public.review_phone_cleanup(uuid,boolean,text),
  public.begin_phone_cleanup(uuid,text,text,jsonb,uuid), public.complete_phone_cleanup(uuid,jsonb) from public, anon;
grant execute on function public.request_phone_cleanup(uuid,text,text,jsonb,text), public.review_phone_cleanup(uuid,boolean,text),
  public.begin_phone_cleanup(uuid,text,text,jsonb,uuid), public.complete_phone_cleanup(uuid,jsonb) to authenticated;
commit;
