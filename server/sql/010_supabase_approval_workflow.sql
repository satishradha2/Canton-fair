-- Approval workflow records are stored in team_records so they sync with the
-- existing cloud workspace. This script reserves the allowed approval states.

create or replace function public.validate_approval_record(payload jsonb)
returns boolean
language sql
immutable
as $$
  select coalesce(payload->>'status', '') in
    ('submitted', 'approved', 'rejected', 'changes_requested');
$$;

grant execute on function public.validate_approval_record(jsonb) to authenticated;
