create or replace function public.canton_fair_health()
returns jsonb
language sql
stable
security invoker
set search_path = public
as $$
  select jsonb_build_object(
    'ok', true,
    'schema_version', 17,
    'checked_at', now(),
    'record_types', jsonb_build_array(
      'trip', 'sourcing_brief', 'supplier', 'contact', 'product',
      'meeting', 'quote', 'sample', 'supplier_comment', 'rfq',
      'expense', 'due_diligence', 'attachment', 'activity', 'workflow_item'
    )
  );
$$;

revoke all on function public.canton_fair_health() from public;
grant execute on function public.canton_fair_health() to authenticated;
