-- Additive server contract only. Run after migrations 010 through 017.
-- Existing clients retain protocol 2. Field-work clients negotiate separately.
begin;

create or replace function public.field_work_sync_version()
returns integer language sql stable as $$ select 1; $$;
revoke all on function public.field_work_sync_version() from public;
grant execute on function public.field_work_sync_version() to authenticated;

create or replace function public.guard_mobile_field_work()
returns trigger language plpgsql security definer set search_path = public
as $$
declare
  relation record;
  parent_id text;
  required_parent boolean;
  booth_payload jsonb;
  plan_payload jsonb;
begin
  if auth.uid() is null or not public.is_team_writer(new.team_id) then
    raise exception 'Team write access is required';
  end if;
  if tg_op = 'UPDATE' and
      (new.team_id <> old.team_id or new.record_id <> old.record_id
       or new.record_type <> old.record_type) then
    raise exception 'Record identity is immutable';
  end if;
  if jsonb_typeof(new.payload) is distinct from 'object' then
    raise exception 'Invalid field-work payload';
  end if;
  if coalesce((new.payload->>'_deleted')::boolean, false) then return new; end if;
  if new.payload ?| array['id','exhibitor_id','trip_id','participation_id',
      'booth_id','plan_id','product_id','category_id'] then
    raise exception 'Use cloud record references, not device-local IDs';
  end if;

  for relation in select * from (values
    ('supplier_participation','supplier'),
    ('supplier_participation','trip'),
    ('exhibitor_booth','supplier_participation'),
    ('visit_plan','exhibitor_booth'),
    ('visit_session','supplier_participation'),
    ('visit_session','exhibitor_booth'),
    ('visit_session','visit_plan'),
    ('product_category_assignment','product'),
    ('product_category_assignment','product_category')
  ) as relationships(child_type,parent_type)
  where child_type = new.record_type loop
    parent_id := nullif(new.payload->>(relation.parent_type || '_record_id'), '');
    required_parent := not (new.record_type = 'visit_session' and
      relation.parent_type in ('exhibitor_booth','visit_plan'));
    if parent_id is null then
      if required_parent then raise exception 'Missing field-work parent'; end if;
    elsif not exists (
      select 1 from public.team_records r
      where r.team_id = new.team_id and r.record_type = relation.parent_type
        and r.record_id = parent_id
        and not coalesce((r.payload->>'_deleted')::boolean, false)
    ) then raise exception 'Field-work parent is missing or deleted'; end if;
  end loop;

  if new.record_type = 'product_category' then
    if nullif(btrim(new.payload->>'name'),'') is null or
        nullif(btrim(new.payload->>'normalized_name'),'') is null or
        coalesce(new.payload->>'archived','') not in ('0','1') then
      raise exception 'Invalid category';
    end if;
    if exists (select 1 from public.team_records r where r.team_id = new.team_id
      and r.record_type = new.record_type and r.record_id <> new.record_id
      and not coalesce((r.payload->>'_deleted')::boolean, false)
      and r.payload->>'normalized_name' = new.payload->>'normalized_name') then
      raise exception 'Category name already exists; reconcile the category';
    end if;
  end if;

  if new.record_type = 'supplier_participation' and exists (
    select 1 from public.team_records r where r.team_id = new.team_id
      and r.record_type = new.record_type and r.record_id <> new.record_id
      and not coalesce((r.payload->>'_deleted')::boolean, false)
      and r.payload->>'supplier_record_id' = new.payload->>'supplier_record_id'
      and r.payload->>'trip_record_id' = new.payload->>'trip_record_id'
  ) then raise exception 'Supplier participation already exists'; end if;

  if new.record_type = 'exhibitor_booth' and exists (
    select 1 from public.team_records r where r.team_id = new.team_id
      and r.record_type = new.record_type and r.record_id <> new.record_id
      and not coalesce((r.payload->>'_deleted')::boolean, false)
      and r.payload->>'supplier_participation_record_id' =
        new.payload->>'supplier_participation_record_id'
      and coalesce(r.payload->>'hall','') = coalesce(new.payload->>'hall','')
      and coalesce(r.payload->>'zone','') = coalesce(new.payload->>'zone','')
      and coalesce(r.payload->>'booth','') = coalesce(new.payload->>'booth','')
  ) then raise exception 'Exhibitor booth already exists'; end if;

  if new.record_type = 'product_category_assignment' and exists (
    select 1 from public.team_records r where r.team_id = new.team_id
      and r.record_type = new.record_type and r.record_id <> new.record_id
      and not coalesce((r.payload->>'_deleted')::boolean, false)
      and r.payload->>'product_record_id' = new.payload->>'product_record_id'
  ) then raise exception 'Product category assignment already exists'; end if;

  if new.record_type = 'visit_plan' then
    if coalesce(new.payload->>'priority','') not in ('0','1','2') or
       coalesce(new.payload->>'selected','') not in ('0','1') then
      raise exception 'Invalid visit plan priority or selection';
    end if;
  end if;

  if new.record_type = 'visit_session' then
    if coalesce(new.payload->>'status','') not in
        ('in_progress','completed','cancelled') or
        nullif(new.payload->>'started_at','') is null then
      raise exception 'Invalid visit session';
    end if;
    perform (new.payload->>'started_at')::timestamptz;
    if new.payload->>'ended_at' is not null and
        (new.payload->>'ended_at')::timestamptz <
        (new.payload->>'started_at')::timestamptz then
      raise exception 'Visit cannot end before it starts';
    end if;
    if new.payload->>'exhibitor_booth_record_id' is not null then
      select r.payload into booth_payload from public.team_records r
      where r.team_id = new.team_id and r.record_type = 'exhibitor_booth'
        and r.record_id = new.payload->>'exhibitor_booth_record_id';
      if booth_payload->>'supplier_participation_record_id' is distinct from
          new.payload->>'supplier_participation_record_id' then
        raise exception 'Visit booth belongs to another participation';
      end if;
    end if;
    if new.payload->>'visit_plan_record_id' is not null then
      select r.payload into plan_payload from public.team_records r
      where r.team_id = new.team_id and r.record_type = 'visit_plan'
        and r.record_id = new.payload->>'visit_plan_record_id';
      select r.payload into booth_payload from public.team_records r
      where r.team_id = new.team_id and r.record_type = 'exhibitor_booth'
        and r.record_id = plan_payload->>'exhibitor_booth_record_id';
      if booth_payload->>'supplier_participation_record_id' is distinct from
          new.payload->>'supplier_participation_record_id' or
          (new.payload->>'exhibitor_booth_record_id' is not null and
           new.payload->>'exhibitor_booth_record_id' is distinct from
             plan_payload->>'exhibitor_booth_record_id') then
        raise exception 'Visit plan belongs to another participation or booth';
      end if;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists guard_mobile_field_work on public.team_records;
create trigger guard_mobile_field_work before insert or update on public.team_records
for each row when (new.record_type in ('product_category','supplier_participation',
  'exhibitor_booth','visit_plan','visit_session','product_category_assignment'))
execute function public.guard_mobile_field_work();

create or replace function public.guard_mobile_field_parent_delete()
returns trigger language plpgsql security definer set search_path = public
as $$
begin
  if not coalesce((new.payload->>'_deleted')::boolean, false) then return new; end if;
  if exists (
    select 1 from public.team_records r
    join (values
      ('supplier_participation','supplier'), ('supplier_participation','trip'),
      ('exhibitor_booth','supplier_participation'), ('visit_plan','exhibitor_booth'),
      ('visit_session','supplier_participation'), ('visit_session','exhibitor_booth'),
      ('visit_session','visit_plan'), ('product_category_assignment','product'),
      ('product_category_assignment','product_category')
    ) as relations(child_type,parent_type) on relations.child_type = r.record_type
    where r.team_id = new.team_id and relations.parent_type = new.record_type
      and not coalesce((r.payload->>'_deleted')::boolean, false)
      and r.payload->>(relations.parent_type || '_record_id') = new.record_id
  ) then raise exception 'Delete or reassign field-work children before this parent'; end if;
  return new;
end;
$$;

drop trigger if exists guard_mobile_field_parent_delete on public.team_records;
create trigger guard_mobile_field_parent_delete before update on public.team_records
for each row execute function public.guard_mobile_field_parent_delete();

revoke all on function public.guard_mobile_field_work() from public;
revoke all on function public.guard_mobile_field_parent_delete() from public;
commit;
