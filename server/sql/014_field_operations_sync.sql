-- Enables the field-operations record types added by mobile database v23.
-- Run after 010_sync_safety.sql.
begin;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public'
      and tablename = 'team_records'
  ) then
    alter publication supabase_realtime add table public.team_records;
  end if;
end $$;

drop trigger if exists guard_team_record on public.team_records;
drop trigger if exists guard_field_operation_record on public.team_records;
drop trigger if exists guard_field_operation_parent_delete on public.team_records;

-- Keep the established commercial and approval guard for its original types.
create trigger guard_team_record before insert or update on public.team_records
for each row when (new.record_type in
  ('trip','sourcing_brief','supplier','contact','product','meeting','quote','sample','activity'))
execute function public.guard_team_record();

create or replace function public.guard_field_operation_record()
returns trigger language plpgsql security definer set search_path = public
as $$
declare
  parent_type text;
  parent_id text;
begin
  if auth.uid() is null or not public.is_team_writer(new.team_id) then
    raise exception 'Team write access is required';
  end if;
  if tg_op = 'UPDATE' and
      (new.team_id <> old.team_id or new.record_id <> old.record_id or new.record_type <> old.record_type) then
    raise exception 'Record identity is immutable';
  end if;
  if jsonb_typeof(new.payload) <> 'object' then raise exception 'Invalid payload'; end if;
  if new.record_type not in
      ('attachment','supplier_comment','rfq','expense','due_diligence') then
    raise exception 'Unsupported record type';
  end if;
  if coalesce((new.payload->>'_deleted')::boolean, false) then return new; end if;

  if new.record_type in ('supplier_comment','due_diligence') then
    parent_id := new.payload->>'supplier_record_id';
    if parent_id is null or not exists (
      select 1 from public.team_records r where r.team_id = new.team_id
        and r.record_type = 'supplier' and r.record_id = parent_id
        and not coalesce((r.payload->>'_deleted')::boolean, false)
    ) then raise exception 'Supplier is required'; end if;
  end if;

  if new.record_type = 'expense' then
    parent_id := new.payload->>'trip_record_id';
    if parent_id is not null and not exists (
      select 1 from public.team_records r where r.team_id = new.team_id
        and r.record_type = 'trip' and r.record_id = parent_id
        and not coalesce((r.payload->>'_deleted')::boolean, false)
    ) then raise exception 'Expense trip is invalid'; end if;
    parent_id := new.payload->>'supplier_record_id';
    if parent_id is not null and not exists (
      select 1 from public.team_records r where r.team_id = new.team_id
        and r.record_type = 'supplier' and r.record_id = parent_id
        and not coalesce((r.payload->>'_deleted')::boolean, false)
    ) then raise exception 'Expense supplier is invalid'; end if;
  end if;

  if new.record_type = 'rfq' then
    parent_id := new.payload->>'trip_record_id';
    if parent_id is not null and not exists (
      select 1 from public.team_records r where r.team_id = new.team_id
        and r.record_type = 'trip' and r.record_id = parent_id
        and not coalesce((r.payload->>'_deleted')::boolean, false)
    ) then raise exception 'RFQ trip is invalid'; end if;
  end if;

  if new.record_type = 'attachment' then
    parent_type := new.payload->>'owner_record_type';
    parent_id := new.payload->>'owner_record_id';
    if parent_type not in ('supplier','contact','product','expense')
        or parent_id is null or not exists (
      select 1 from public.team_records r where r.team_id = new.team_id
        and r.record_type = parent_type and r.record_id = parent_id
        and not coalesce((r.payload->>'_deleted')::boolean, false)
    ) then raise exception 'Attachment owner is invalid'; end if;
    if coalesce(new.payload->>'storage_path','') not like new.team_id::text || '/%' then
      raise exception 'Attachment belongs to another team';
    end if;
  end if;
  return new;
end;
$$;

create trigger guard_field_operation_record before insert or update on public.team_records
for each row when (new.record_type in
  ('attachment','supplier_comment','rfq','expense','due_diligence'))
execute function public.guard_field_operation_record();

create or replace function public.guard_field_operation_parent_delete()
returns trigger language plpgsql security definer set search_path = public
as $$
begin
  if not coalesce((new.payload->>'_deleted')::boolean, false) then return new; end if;
  if exists (
    select 1 from public.team_records r
    where r.team_id = new.team_id
      and not coalesce((r.payload->>'_deleted')::boolean, false)
      and not (r.record_type = new.record_type and r.record_id = new.record_id)
      and (
        (new.record_type = 'trip' and r.record_type in ('rfq','expense')
          and r.payload->>'trip_record_id' = new.record_id) or
        (new.record_type = 'supplier' and r.record_type in
          ('supplier_comment','due_diligence','expense')
          and r.payload->>'supplier_record_id' = new.record_id) or
        (new.record_type = 'expense' and r.record_type = 'attachment'
          and r.payload->>'owner_record_type' = 'expense'
          and r.payload->>'owner_record_id' = new.record_id)
      )
  ) then raise exception 'Delete or reassign child records before deleting this parent'; end if;
  return new;
end;
$$;

create trigger guard_field_operation_parent_delete before update on public.team_records
for each row when (new.record_type in ('trip','supplier','expense'))
execute function public.guard_field_operation_parent_delete();

commit;
