import { useEffect, useState } from 'react';
import type { ReactNode } from 'react';
import { supabase } from './api';
import type { TeamRecord } from './types';

interface Options {
  teamId: string; types: string[]; query: string;
  filterField?: string; filterValue?: string; shortlisted?: boolean;
  revision?: unknown;
}

export function useServerPagination(options: Options) {
  const [page, setPage] = useState(1);
  const [size, setSize] = useState(25);
  const [rows, setRows] = useState<TeamRecord[]>([]);
  const [total, setTotal] = useState(0);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [retry, setRetry] = useState(0);
  const identity = JSON.stringify([options.teamId, options.types, options.query,
    options.filterField, options.filterValue, options.shortlisted]);
  const [activeIdentity, setActiveIdentity] = useState(identity);
  const requestedPage = identity === activeIdentity ? page : 1;
  useEffect(() => { setActiveIdentity(identity); setPage(1); }, [identity]);
  useEffect(() => {
    let active = true;
    setBusy(true); setError(''); setRows([]);
    const timer = window.setTimeout(() => {
      void (async () => {
        if (!supabase || !options.teamId) throw new Error('Select a team workspace.');
        const { data, error: failure } = await supabase.rpc('page_team_records', {
          target_team: options.teamId, record_types: options.types,
          search_text: options.query, page_offset: (requestedPage - 1) * size,
          page_size: size, filter_field: options.filterField ?? '',
          filter_value: options.filterValue ?? '', only_shortlisted: options.shortlisted ?? false,
        });
        if (failure) throw new Error(failure.code === 'PGRST202'
          ? 'Server pagination is not installed. Apply supabase/record_pagination.sql first.' : failure.message);
        if (!active) return;
        const count = Number(data?.total ?? 0);
        setTotal(count);
        setRows((data?.rows ?? []).map((row: TeamRecord) => ({ ...row, version: Number(row.version) })));
        const last = Math.max(1, Math.ceil(count / size));
        if (requestedPage > last) setPage(last);
      })().catch((reason: unknown) => {
        if (active) setError(reason instanceof Error ? reason.message : 'Could not load this page.');
      }).finally(() => { if (active) setBusy(false); });
    }, 200);
    return () => { active = false; window.clearTimeout(timer); };
  }, [identity, requestedPage, size, options.revision, retry]);
  return { rows, total, busy, error, page: requestedPage, size,
    setPage, setSize: (value: number) => { setSize(value); setPage(1); },
    retry: () => setRetry((value) => value + 1) };
}

export function PageControls({ state }: { state: ReturnType<typeof useServerPagination> }) {
  const pages = Math.max(1, Math.ceil(state.total / state.size));
  const first = state.total === 0 ? 0 : (state.page - 1) * state.size + 1;
  return <nav aria-label="Record pagination" style={{ display: 'flex', flexWrap: 'wrap',
    alignItems: 'center', gap: 12, padding: '16px 0' }}>
    <span role="status">{state.busy ? 'Loading...' : `Showing ${first}-${Math.min(state.page * state.size, state.total)} of ${state.total}`}</span>
    <label>Rows <select value={state.size} disabled={state.busy}
      onChange={(event) => state.setSize(Number(event.target.value))}>
      {[25, 50, 100].map((size) => <option key={size} value={size}>{size}</option>)}
    </select></label>
    <button disabled={state.busy || state.page === 1} onClick={() => state.setPage(state.page - 1)}>Previous</button>
    <label>Page <select aria-label="Page number" value={state.page} disabled={state.busy}
      onChange={(event) => state.setPage(Number(event.target.value))}>
      {Array.from({ length: pages }, (_, index) => <option key={index} value={index + 1}>{index + 1}</option>)}
    </select> of {pages}</label>
    <button disabled={state.busy || state.page >= pages} onClick={() => state.setPage(state.page + 1)}>Next</button>
    {state.error && <div role="alert">{state.error} <button onClick={state.retry}>Retry</button></div>}
  </nav>;
}

export function ServerRecordList({ renderItem, ...options }: Options & {
  renderItem: (record: TeamRecord) => ReactNode;
}) {
  const state = useServerPagination(options);
  return <><PageControls state={state} />{state.rows.map(renderItem)}
    {!state.busy && !state.error && state.total === 0 && <p>No matching records. Clear or change your search.</p>}
  </>;
}
