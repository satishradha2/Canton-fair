-- Repair deployments with migration 018 but missing 014/015 trigger routing.
-- Preserves the original commercial guard and the mobile field-work guard.
begin;

create or replace function public.guard_field_operation_record()
returns trigger language plpgsql security definer set search_path = public
as $$
declare parent_id text; parent_type text;
begin
  if auth.uid() is null or not public.is_team_writer(new.team_id) then
    raise exception 'Team write access is required';
  end if;
  if tg_op = 'UPDATE' and
      (new.team_id <> old.team_id or new.record_id <> old.record_id or new.record_type <> old.record_type) then
    raise exception 'Record identity is immutable';
  end if;
  if jsonb_typeof(new.payload) is distinct from 'object' then raise exception 'Invalid payload'; end if;
  if new.record_type not in
      ('attachment','supplier_comment','rfq','expense','due_diligence','workflow_item') then
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
  if new.record_type in ('expense','rfq','workflow_item') then
    foreach parent_type in array array['trip','supplier','product','contact'] loop
      if new.record_type = 'rfq' and parent_type <> 'trip' then continue; end if;
      if new.record_type = 'expense' and parent_type not in ('trip','supplier') then continue; end if;
      parent_id := new.payload->>(parent_type || '_record_id');
      if parent_id is not null and not exists (
        select 1 from public.team_records r where r.team_id = new.team_id
          and r.record_type = parent_type and r.record_id = parent_id
          and not coalesce((r.payload->>'_deleted')::boolean, false)
      ) then raise exception 'Field operation parent is invalid'; end if;
    end loop;
  end if;
  if new.record_type = 'attachment' then
    parent_type := new.payload->>'owner_record_type';
    parent_id := new.payload->>'owner_record_id';
    if parent_type is null or parent_type not in ('supplier','contact','product','expense')
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
        (new.record_type = 'trip' and r.record_type in ('rfq','expense','workflow_item')
          and r.payload->>'trip_record_id' = new.record_id) or
        (new.record_type = 'supplier' and r.record_type in
          ('supplier_comment','due_diligence','expense','workflow_item')
          and r.payload->>'supplier_record_id' = new.record_id) or
        (new.record_type = 'product' and r.record_type = 'workflow_item'
          and r.payload->>'product_record_id' = new.record_id) or
        (new.record_type = 'contact' and r.record_type = 'workflow_item'
          and r.payload->>'contact_record_id' = new.record_id) or
        (new.record_type = 'expense' and r.record_type = 'attachment'
          and r.payload->>'owner_record_type' = 'expense'
          and r.payload->>'owner_record_id' = new.record_id)
      )
  ) then raise exception 'Delete or reassign child records before deleting this parent'; end if;
  return new;
end;
$$;

create or replace function public.guard_supported_sync_record()
returns trigger language plpgsql security definer set search_path = public
as $$
begin
  if new.record_type is null or new.record_type not in
    ('trip','sourcing_brief','supplier','contact','product','meeting','quote','sample','activity',
     'attachment','supplier_comment','rfq','expense','due_diligence','workflow_item',
     'product_category','supplier_participation','exhibitor_booth','visit_plan',
     'visit_session','product_category_assignment') then
    raise exception 'Unsupported record type: %', new.record_type;
  end if;
  return new;
end;
$$;

-- Fail transactionally if the mobile validator has not been installed.
do $$
begin
  if not exists (select 1 from pg_trigger
    where tgrelid = 'public.team_records'::regclass
      and tgname = 'guard_mobile_field_work' and tgenabled = 'O') then
    raise exception 'Apply migration 018 before this repair';
  end if;
end;
$$;

drop trigger if exists guard_team_record on public.team_records;
create trigger guard_team_record before insert or update on public.team_records
for each row when (new.record_type in
  ('trip','sourcing_brief','supplier','contact','product','meeting','quote','sample','activity'))
execute function public.guard_team_record();

drop trigger if exists guard_field_operation_record on public.team_records;
create trigger guard_field_operation_record before insert or update on public.team_records
for each row when (new.record_type in
  ('attachment','supplier_comment','rfq','expense','due_diligence','workflow_item'))
execute function public.guard_field_operation_record();

drop trigger if exists guard_field_operation_parent_delete on public.team_records;
create trigger guard_field_operation_parent_delete before update on public.team_records
for each row when (new.record_type in ('trip','supplier','product','contact','expense'))
execute function public.guard_field_operation_parent_delete();

drop trigger if exists guard_supported_sync_record on public.team_records;
create trigger guard_supported_sync_record before insert or update on public.team_records
for each row execute function public.guard_supported_sync_record();

revoke all on function public.guard_field_operation_record() from public;
revoke all on function public.guard_field_operation_parent_delete() from public;
revoke all on function public.guard_supported_sync_record() from public;
commit;

