-- Run this in the Supabase SQL Editor after the team/RLS scripts.
-- Files use the path: <team-id>/<attachment-record-id>/file.<extension>.

insert into storage.buckets (id, name, public)
values ('team-attachments', 'team-attachments', false)
on conflict (id) do update set public = false;

drop policy if exists "Team members can read team attachments" on storage.objects;
drop policy if exists "Team members can upload team attachments" on storage.objects;
drop policy if exists "Team members can update team attachments" on storage.objects;
drop policy if exists "Team members can delete team attachments" on storage.objects;

create policy "Team members can read team attachments"
on storage.objects for select to authenticated
using (
  bucket_id = 'team-attachments'
  and public.is_team_member((storage.foldername(name))[1]::uuid)
);

create policy "Team members can upload team attachments"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'team-attachments'
  and public.is_team_member((storage.foldername(name))[1]::uuid)
);

create policy "Team members can update team attachments"
on storage.objects for update to authenticated
using (
  bucket_id = 'team-attachments'
  and public.is_team_member((storage.foldername(name))[1]::uuid)
)
with check (
  bucket_id = 'team-attachments'
  and public.is_team_member((storage.foldername(name))[1]::uuid)
);

create policy "Team members can delete team attachments"
on storage.objects for delete to authenticated
using (
  bucket_id = 'team-attachments'
  and public.is_team_member((storage.foldername(name))[1]::uuid)
);
