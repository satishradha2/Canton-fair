-- Prevent concurrent team devices from creating an identical product record.
-- The business key is supplier + normalized product name + normalized model/SKU.
-- Products without a model/SKU are therefore protected by supplier + name.
begin;

create or replace function public.guard_product_business_key()
returns trigger language plpgsql security definer set search_path = public
as $$
declare
  supplier_id text := nullif(btrim(new.payload->>'supplier_record_id'), '');
  product_name text := lower(btrim(coalesce(new.payload->>'name', '')));
  model_code text := lower(btrim(coalesce(new.payload->>'model_code', '')));
begin
  if coalesce((new.payload->>'_deleted')::boolean, false) then
    return new;
  end if;

  if supplier_id is null or product_name = '' then
    raise exception 'Product supplier and name are required';
  end if;

  if exists (
    select 1
    from public.team_records existing
    where existing.team_id = new.team_id
      and existing.record_type = 'product'
      and existing.record_id <> new.record_id
      and not coalesce((existing.payload->>'_deleted')::boolean, false)
      and existing.payload->>'supplier_record_id' = supplier_id
      and lower(btrim(coalesce(existing.payload->>'name', ''))) = product_name
      and lower(btrim(coalesce(existing.payload->>'model_code', ''))) = model_code
  ) then
    raise exception 'Duplicate product for this supplier and model/SKU';
  end if;

  return new;
end;
$$;

drop trigger if exists guard_product_business_key on public.team_records;
create trigger guard_product_business_key
before insert or update on public.team_records
for each row when (new.record_type = 'product')
execute function public.guard_product_business_key();

revoke all on function public.guard_product_business_key() from public;
commit;
