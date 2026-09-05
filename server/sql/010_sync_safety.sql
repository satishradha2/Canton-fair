-- Apply after 009 in the Supabase SQL Editor, before distributing this app.
-- Local database migration 22 runs automatically. This server migration does not.
begin;

create or replace function public.sync_protocol_version()
returns integer language sql stable as $$ select 2; $$;
revoke all on function public.sync_protocol_version() from public;
grant execute on function public.sync_protocol_version() to authenticated;

-- All client record writes go through the serialized CAS RPC below.
revoke insert, update, delete on public.team_records from public, anon, authenticated;

create or replace function public.guard_team_record()
returns trigger language plpgsql security definer set search_path = public
as $$
declare
  prior jsonb := '{}'::jsonb;
  requested jsonb := new.payload;
  relation record;
  parent_type text;
  parent_id text;
  plan jsonb;
  supplier jsonb;
  verification jsonb;
  latest_quote jsonb;
  admin_user boolean;
begin
  if auth.uid() is null or not public.is_team_writer(new.team_id) then
    raise exception 'Team write access is required';
  end if;
  admin_user := public.is_team_admin(new.team_id);
  if tg_op = 'UPDATE' then
    if new.team_id <> old.team_id or new.record_id <> old.record_id or new.record_type <> old.record_type then
      raise exception 'Record identity is immutable';
    end if;
    prior := old.payload;
  end if;
  if jsonb_typeof(requested) <> 'object' then raise exception 'Invalid payload'; end if;
  if new.record_type not in ('trip','sourcing_brief','supplier','contact','product','meeting','quote','sample','attachment','activity') then
    raise exception 'Unsupported record type';
  end if;

  if coalesce((requested->>'_deleted')::boolean, false) then
    if new.record_type = 'quote' and prior->>'approval_status' in ('Approved','Rejected') and not admin_user then
      raise exception 'Only an admin may delete a reviewed quote';
    end if;
    -- Refuse to lose children created/edited on another device. The client
    -- sends child tombstones first, then parents, while holding the team lock.
    if exists (
      select 1 from public.team_records r
      where r.team_id = new.team_id and not coalesce((r.payload->>'_deleted')::boolean, false)
        and not (r.record_type = new.record_type and r.record_id = new.record_id)
        and (
          (new.record_type = 'trip' and r.record_type in ('supplier','sourcing_brief') and r.payload->>'trip_record_id' = new.record_id) or
          (new.record_type = 'supplier' and r.record_type in ('contact','product','meeting','sample') and r.payload->>'supplier_record_id' = new.record_id) or
          (new.record_type = 'product' and r.record_type in ('meeting','quote','sample') and r.payload->>'product_record_id' = new.record_id) or
          (r.record_type = 'attachment' and r.payload->>'owner_record_type' = new.record_type and r.payload->>'owner_record_id' = new.record_id)
        )
    ) then raise exception 'Delete or reassign child records before deleting this parent'; end if;
    return new;
  end if;

  -- Every shared relationship is a cloud ID in the same team, never a device ID.
  for relation in select * from (values
    ('trip_record_id', 'trip'),
    ('supplier_record_id', 'supplier'),
    ('product_record_id', 'product')
  ) as relations(field_name, record_type)
  loop
    parent_id := requested->>relation.field_name;
    if parent_id is not null and not exists (
      select 1 from public.team_records r where r.team_id = new.team_id
        and r.record_type = relation.record_type and r.record_id = parent_id
        and not coalesce((r.payload->>'_deleted')::boolean, false)
    ) then raise exception 'A referenced parent is missing or deleted'; end if;
  end loop;
  if new.record_type = 'supplier' and nullif(requested->>'trip_record_id','') is null then
    raise exception 'Supplier trip is required';
  end if;
  if new.record_type in ('contact','product','meeting','sample') and nullif(requested->>'supplier_record_id','') is null then
    raise exception 'Supplier is required';
  end if;
  if new.record_type = 'quote' and nullif(requested->>'product_record_id','') is null then
    raise exception 'Quote product is required';
  end if;
  if new.record_type = 'attachment' then
    parent_type := requested->>'owner_record_type';
    parent_id := requested->>'owner_record_id';
    if parent_type not in ('supplier','contact','product') or parent_type is null or parent_id is null or not exists (
      select 1 from public.team_records r where r.team_id = new.team_id
      and r.record_type = parent_type and r.record_id = parent_id
      and not coalesce((r.payload->>'_deleted')::boolean, false)
    ) then raise exception 'Attachment owner is invalid'; end if;
    if coalesce(requested->>'storage_path','') not like new.team_id::text || '/%' then
      raise exception 'Attachment belongs to another team';
    end if;
  end if;

  if new.record_type = 'quote' then
    if coalesce(requested->>'approval_status','Draft') not in ('Draft','Pending approval','Approved','Rejected','Changes requested') then
      raise exception 'Invalid approval status';
    end if;
    if (requested->>'approval_status' in ('Approved','Rejected','Changes requested') or
        prior->>'approval_status' in ('Approved','Rejected'))
       and (requested->'approval_status', requested->'approval_comment', requested->'approved_by', requested->'approved_at')
       is distinct from (prior->'approval_status', prior->'approval_comment', prior->'approved_by', prior->'approved_at')
       and not admin_user then
      raise exception 'Only a team admin can make or change a review decision';
    end if;
    if prior->>'approval_status' = 'Approved' and
       (requested - array['approval_status','approval_comment','approved_by','approved_at']) is distinct from
       (prior - array['approval_status','approval_comment','approved_by','approved_at']) then
      raise exception 'Create a new revision instead of editing an approved quote';
    end if;
    if requested->>'approval_status' = 'Rejected' and
       nullif(btrim(requested->>'approval_comment'),'') is null then
      raise exception 'A rejection reason is required';
    end if;
    if requested->>'approval_status' in ('Approved','Rejected') and
       (requested->'approval_status', requested->'approved_by', requested->'approved_at')
       is distinct from (prior->'approval_status', prior->'approved_by', prior->'approved_at') then
      if requested->>'approved_by' is distinct from (auth.jwt()->>'email') or
          nullif(requested->>'approved_at','') is null then
        raise exception 'Reviewer identity and decision timestamp are required';
      end if;
    end if;
  end if;

  if new.record_type = 'product' then
    plan := coalesce(nullif(requested->>'purchase_readiness_json','')::jsonb, '{}'::jsonb);
    if plan->>'status' = 'Approved for order' and
        requested->'purchase_readiness_json' is distinct from prior->'purchase_readiness_json'
        and not admin_user then
      raise exception 'Only a team admin can approve an order';
    end if;
    if plan->>'status' in ('Ready to order','Approved for order') then
      select r.payload into supplier from public.team_records r
      where r.team_id = new.team_id and r.record_type = 'supplier'
        and r.record_id = requested->>'supplier_record_id';
      verification := coalesce(nullif(supplier->>'verification_json','')::jsonb, '{}'::jsonb);
      select r.payload into latest_quote from public.team_records r
      where r.team_id = new.team_id and r.record_type = 'quote'
        and r.payload->>'product_record_id' = new.record_id
        and not coalesce((r.payload->>'_deleted')::boolean, false)
        and coalesce((r.payload->>'is_sample_quote')::integer, 0) = 0
      order by (r.payload->>'created_at')::timestamptz desc nulls last, r.record_id desc
      limit 1;
      if not exists (
        select 1 from public.team_records r where r.team_id = new.team_id and r.record_type = 'sample'
          and r.payload->>'product_record_id' = new.record_id and r.payload->>'status' = 'Approved'
          and not coalesce((r.payload->>'_deleted')::boolean, false)
      ) or coalesce(latest_quote->>'approval_status','') <> 'Approved'
        or (nullif(latest_quote->>'valid_until','')::timestamptz < now())
        or coalesce((requested->>'moq')::numeric,0) <= 0
        or nullif(btrim(requested->>'lead_time'),'') is null
        or nullif(btrim(requested->>'payment_terms'),'') is null
        or coalesce(verification->>'status','') <> 'Approved'
        or coalesce(verification->>'payment_risk','false') in ('true','1')
        or coalesce(verification->'flags'->>'payment_risk','false') in ('true','1')
      then raise exception 'Resolve purchase-readiness blockers first'; end if;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists guard_team_record on public.team_records;
create trigger guard_team_record before insert or update on public.team_records
for each row execute function public.guard_team_record();

create or replace function public.upsert_team_record_v2(
  target_team uuid, target_record_type text, target_record_id text,
  target_payload jsonb, expected_version integer default null
)
returns table (version integer, updated_at timestamptz)
language plpgsql security definer set search_path = public
as $$
declare existing public.team_records%rowtype;
begin
  if auth.uid() is null or not public.is_team_writer(target_team) then
    raise exception 'Team write access is required';
  end if;
  if expected_version is null or expected_version < 0 then
    raise exception 'A version is required. Upgrade the mobile app.';
  end if;
  -- Serialize team writes, including cross-record relationship checks.
  perform pg_advisory_xact_lock(hashtextextended(target_team::text, 0));
  select * into existing from public.team_records r
  where r.team_id = target_team and r.record_type = target_record_type
    and r.record_id = target_record_id for update;
  if found then
    if existing.version <> expected_version then raise exception 'sync_conflict'; end if;
    update public.team_records r set payload = target_payload,
      updated_by = auth.uid(), updated_at = now(), version = r.version + 1
    where r.team_id = target_team and r.record_type = target_record_type
      and r.record_id = target_record_id
    returning r.version, r.updated_at into version, updated_at;
  else
    if expected_version <> 0 then raise exception 'sync_conflict'; end if;
    insert into public.team_records(team_id,record_type,record_id,payload,updated_by,version)
    values(target_team,target_record_type,target_record_id,target_payload,auth.uid(),1)
    returning team_records.version, team_records.updated_at into version, updated_at;
  end if;
  return next;
end;
$$;
revoke all on function public.upsert_team_record_v2(uuid,text,text,jsonb,integer) from public;
grant execute on function public.upsert_team_record_v2(uuid,text,text,jsonb,integer) to authenticated;

revoke all on function public.upsert_team_record(uuid,text,text,jsonb,integer) from public, anon, authenticated;

-- Content-addressed attachment blobs must not be overwritten or removed by a
-- competing client. Retention cleanup is an administrative operation.
drop policy if exists "Team members can update team attachments" on storage.objects;
drop policy if exists "Team members can delete team attachments" on storage.objects;
commit;
