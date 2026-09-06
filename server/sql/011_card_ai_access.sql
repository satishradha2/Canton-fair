-- Apply manually in Supabase before deploying card-ai. No card content stored.
begin;
create table if not exists public.card_ai_access (
  user_id uuid primary key references auth.users(id) on delete cascade,
  enabled boolean not null default false,
  daily_limit integer not null default 30 check (daily_limit between 1 and 300)
);
create table if not exists public.card_ai_usage (
  user_id uuid not null references auth.users(id) on delete cascade,
  request_id uuid not null,
  created_at timestamptz not null default now(),
  primary key (user_id, request_id)
);
create index if not exists card_ai_usage_day on public.card_ai_usage(user_id, created_at);
alter table public.card_ai_access enable row level security;
alter table public.card_ai_usage enable row level security;
revoke all on public.card_ai_access, public.card_ai_usage from public, anon, authenticated;

create or replace function public.reserve_card_ai_request(p_user uuid, p_request uuid, p_team uuid default null)
returns boolean language plpgsql security definer set search_path = public
as $$
declare max_requests integer;
begin
  perform pg_advisory_xact_lock(hashtextextended('card-ai:' || p_user::text, 0));
  select daily_limit into max_requests from public.card_ai_access
    where user_id = p_user and enabled;
  if max_requests is null then return false; end if;
  if p_team is not null and not exists (
    select 1 from public.team_members where team_id = p_team and user_id = p_user
      and role in ('admin', 'member')
  ) then return false; end if;
  if (select count(*) from public.card_ai_usage where user_id = p_user
      and created_at >= (date_trunc('day', now() at time zone 'UTC') at time zone 'UTC')) >= max_requests then
    return false;
  end if;
  insert into public.card_ai_usage(user_id, request_id) values (p_user, p_request)
    on conflict do nothing;
  return found;
end;
$$;
revoke all on function public.reserve_card_ai_request(uuid, uuid, uuid) from public, anon, authenticated;
grant execute on function public.reserve_card_ai_request(uuid, uuid, uuid) to service_role;
commit;
