-- Private token storage for supplier self-service and management share links.
create table if not exists public.external_share_tokens (
  id uuid primary key default gen_random_uuid(),
  token_hash text not null unique check (length(token_hash) = 64),
  team_id uuid not null references public.teams(id) on delete cascade,
  created_by uuid not null references auth.users(id) on delete cascade,
  mode text not null check (mode in ('supplier_request','read_only')),
  title text not null,
  payload jsonb not null default '{}'::jsonb,
  response jsonb,
  responded_at timestamptz,
  expires_at timestamptz not null,
  revoked_at timestamptz,
  created_at timestamptz not null default now()
);
alter table public.external_share_tokens enable row level security;
revoke all on public.external_share_tokens from anon, authenticated;
create index if not exists idx_external_share_team on public.external_share_tokens(team_id, created_at desc);
