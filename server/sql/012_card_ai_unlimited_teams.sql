-- Supersedes the daily cap and account allowlist from 011.
-- All current/future members of every team, including viewers, may use card AI.
-- No daily application cap. OpenAI billing and provider limits still apply.
begin;
create or replace function public.reserve_card_ai_request(p_user uuid, p_request uuid, p_team uuid default null)
returns boolean language plpgsql security definer set search_path = public
as $$
begin
  if p_user is null or p_request is null then return false; end if;
  -- A selected team must include this caller. Personal-workspace requests also
  -- require membership of at least one team; a bare signup grants no AI access.
  if not exists (
    select 1 from public.team_members
    where user_id = p_user and (p_team is null or team_id = p_team)
  ) then return false; end if;
  -- Retain atomic duplicate-request protection, but do not count daily usage.
  insert into public.card_ai_usage(user_id, request_id) values (p_user, p_request)
    on conflict do nothing;
  return found;
end;
$$;
revoke all on function public.reserve_card_ai_request(uuid, uuid, uuid) from public, anon, authenticated;
grant execute on function public.reserve_card_ai_request(uuid, uuid, uuid) to service_role;
commit;
