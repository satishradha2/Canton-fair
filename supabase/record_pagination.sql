-- Read-only paging endpoint. Existing table RLS remains authoritative.
-- Apply in the project SQL editor before deploying the updated web portal.
create or replace function public.page_team_records(
  target_team uuid,
  record_types text[] default null,
  search_text text default '',
  page_offset integer default 0,
  page_size integer default 25,
  filter_field text default '',
  filter_value text default '',
  only_shortlisted boolean default false
) returns jsonb
language sql stable security invoker
set search_path = public
as $$
  with matches as (
    select record_type, record_id, payload, updated_at, version
    from public.team_records r
    where team_id = target_team
      and (record_types is null or cardinality(record_types)=0 or record_type=any(record_types))
      and record_type not in ('assignment','product_category_assignment','exhibitor_booth','supplier_participation')
      and coalesce(payload->>'_deleted', 'false') <> 'true'
      and (not only_shortlisted or coalesce(payload->>'shortlisted','false') in ('true','1'))
      and (filter_value='' or case filter_field
        when 'hall' then coalesce(nullif(payload->>'hall',''),payload->>'hall_number','')
        when 'category' then coalesce(payload->>'category','')
        else '' end = filter_value)
      and not exists (
        select 1 from regexp_split_to_table(lower(trim(coalesce(search_text,''))), '\s+') word
        where word<>'' and position(word in lower(r.payload::text || ' ' || r.record_type))=0
      )
  ), batch as (
    select * from matches
    order by updated_at desc, record_type, record_id
    limit least(greatest(page_size,1),100)
    offset greatest(page_offset,0)
  )
  select jsonb_build_object('total', (select count(*) from matches),
    'rows', coalesce((select jsonb_agg(to_jsonb(batch) order by updated_at desc, record_type, record_id)
      from batch), '[]'::jsonb));
$$;

revoke all on function public.page_team_records(uuid,text[],text,integer,integer,text,text,boolean) from public;
grant execute on function public.page_team_records(uuid,text[],text,integer,integer,text,text,boolean) to authenticated;
