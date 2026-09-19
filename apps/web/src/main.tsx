import { useEffect, useMemo, useState } from 'react';
import { createRoot } from 'react-dom/client';
import type { User } from '@supabase/supabase-js';
import { isConfigured, loadRecords, loadTeams, supabase, updateRecord } from './api';
import { SourcingWorkspace } from './sourcing_workspace';
import { VisitEvidenceWorkspace } from './visit_evidence_workspace';
import type { JsonRecord, Team, TeamRecord, WorkspaceView } from './types';
import './styles.css';

const viewMeta: Record<WorkspaceView, { label: string; types: string[] }> = {
  overview: { label: 'Overview', types: [] },
  suppliers: { label: 'Suppliers', types: ['supplier', 'exhibitor'] },
  products: { label: 'Products', types: ['product'] },
  visits: { label: 'Visit evidence', types: ['visit_session', 'recording', 'contact', 'attachment', 'meeting', 'activity'] },
  shortlist: { label: 'Shortlist', types: ['product'] },
  operations: { label: 'Operations', types: [] },
};

function valueOf(payload: JsonRecord, keys: string[]): string {
  for (const key of keys) {
    const value = payload[key];
    if (typeof value === 'string' && value.trim()) return value.trim();
    if (typeof value === 'number') return String(value);
  }
  return '';
}

function recordName(record: TeamRecord): string {
  return valueOf(record.payload, ['name', 'supplier_name', 'company_name', 'title', 'product_name', 'contact_name', 'subject']) || `${businessTypeLabel(record)} record`;
}

const internalRecordTypes = new Set([
  'visit_plan', 'assignment', 'product_category', 'product_category_assignment',
  'exhibitor_booth', 'supplier_participation',
]);

const fieldLabels: Record<string, string> = {
  name: 'Name', supplier_name: 'Supplier', company_name: 'Company',
  legal_company_name: 'Legal company name', contact_name: 'Contact name',
  role: 'Role', phone: 'Phone', whatsapp: 'WhatsApp', wechat: 'WeChat',
  email: 'Email', country: 'Country', hall: 'Hall', booth: 'Booth',
  category: 'Category', industry: 'Industry', model_code: 'Model / SKU',
  specs: 'Description and specifications', quoted_price: 'Quoted unit price',
  price_currency: 'Currency', moq: 'Minimum order quantity', lead_time: 'Lead time',
  payment_terms: 'Payment terms', shortlisted: 'Shortlisted', summary: 'Summary',
  notes: 'Notes', body: 'Notes', transcript: 'Transcript', file_name: 'File name',
  subject: 'Subject', status: 'Status', started_at: 'Started', ended_at: 'Ended',
  export_markets: 'Export markets', factory_location: 'Factory location',
};

const visibleFieldKeys = new Set(Object.keys(fieldLabels));

function businessTypeLabel(record: TeamRecord): string {
  const labels: Record<string, string> = {
    supplier: 'Supplier', exhibitor: 'Exhibitor', product: 'Product', contact: 'Contact',
    meeting: 'Meeting', recording: 'Recording', attachment: 'Attachment',
    activity: 'Activity', trip: 'Trip', visit_session: 'Visit',
  };
  return labels[record.record_type] ?? 'Business';
}

function isInternalRecord(record: TeamRecord): boolean {
  return internalRecordTypes.has(record.record_type) || record.payload._deleted === true;
}

function visibleDetails(record: TeamRecord): Array<[string, unknown]> {
  return Object.entries(record.payload).filter(([key, value]) =>
    visibleFieldKeys.has(key) && ['string', 'number', 'boolean'].includes(typeof value));
}

function isShortlisted(record: TeamRecord): boolean {
  return record.payload.shortlisted === true || record.payload.shortlisted === 1 || record.payload.shortlisted === '1';
}

function isType(record: TeamRecord, names: string[]): boolean {
  return names.includes(record.record_type);
}

function dateLabel(value: string): string {
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? 'Not available' : date.toLocaleString();
}

function Login({ onError }: { onError: (message: string) => void }) {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [busy, setBusy] = useState(false);
  const submit = async (event: React.FormEvent) => {
    event.preventDefault();
    if (!supabase) return;
    setBusy(true);
    try {
      const { error } = await supabase.auth.signInWithPassword({
        email: email.trim(), password,
      });
      if (error) throw error;
    } catch (error) {
      onError(error instanceof Error ? error.message : 'Could not sign in.');
    } finally {
      setBusy(false);
    }
  };
  return <main className="login-shell"><section className="login-card">
    <p className="eyebrow">CANTON FAIR / SOURCING WORKSPACE</p>
    <h1>Bring the fair back to your desk.</h1>
    <p className="muted">Review synchronized supplier and product evidence without taking field-entry work away from the team.</p>
    <form onSubmit={submit}>
      <label>Work email<input value={email} onChange={(event) => setEmail(event.target.value)} type="email" required /></label>
      <label>Password<input value={password} onChange={(event) => setPassword(event.target.value)} type="password" required /></label>
      <button className="primary" disabled={busy}>{busy ? 'Signing in...' : 'Sign in securely'}</button>
    </form>
  </section></main>;
}

function App() {
  const [user, setUser] = useState<User | null>(null);
  const [teams, setTeams] = useState<Team[]>([]);
  const [teamId, setTeamId] = useState('');
  const [records, setRecords] = useState<TeamRecord[]>([]);
  const [view, setView] = useState<WorkspaceView>('overview');
  const [search, setSearch] = useState('');
  const [selected, setSelected] = useState<TeamRecord | null>(null);
  const [editing, setEditing] = useState(false);
  const [draft, setDraft] = useState<JsonRecord>({});
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');

  useEffect(() => {
    if (!supabase) return;
    const { data } = supabase.auth.onAuthStateChange((_event, session) => {
      setUser(session?.user ?? null);
    });
    return () => data.subscription.unsubscribe();
  }, []);

  useEffect(() => {
    if (!user) return;
    setBusy(true);
    loadTeams().then((result) => {
      setTeams(result);
      setTeamId((current) => current || result[0]?.id || '');
    }).catch((reason) => setError(reason.message)).finally(() => setBusy(false));
  }, [user]);

  const refresh = async () => {
    if (!user || !teamId) return;
    setBusy(true); setError('');
    try { setRecords(await loadRecords(teamId)); }
    catch (reason) { setError(reason instanceof Error ? reason.message : 'Could not load workspace records.'); }
    finally { setBusy(false); }
  };

  useEffect(() => { void refresh(); }, [teamId]);

  const scoped = useMemo(() => records.filter((record) => {
    if (isInternalRecord(record)) return false;
    if (view === 'overview' && !isType(record, [
      'supplier', 'exhibitor', 'product', 'contact', 'meeting', 'recording', 'activity', 'trip', 'visit_session',
    ])) return false;
    if (view === 'shortlist' && !isShortlisted(record)) return false;
    const accepted = viewMeta[view].types;
    if (accepted.length && !isType(record, accepted)) return false;
    const haystack = `${record.record_type} ${recordName(record)} ${JSON.stringify(record.payload)}`.toLowerCase();
    return haystack.includes(search.trim().toLowerCase());
  }), [records, search, view]);

  const metrics = useMemo(() => ({
    suppliers: records.filter((record) => !isInternalRecord(record) && isType(record, viewMeta.suppliers.types)).length,
    products: records.filter((record) => !isInternalRecord(record) && isType(record, ['product'])).length,
    shortlist: records.filter(isShortlisted).length,
    evidence: records.filter((record) => !isInternalRecord(record) && isType(record, viewMeta.visits.types)).length,
  }), [records]);

  const exportRecords = () => {
    const blob = new Blob([JSON.stringify(records, null, 2)], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const anchor = document.createElement('a');
    anchor.href = url; anchor.download = `canton-fair-${teamId}-records.json`; anchor.click();
    URL.revokeObjectURL(url);
  };

  const editKeys = selected && isType(selected, ['product'])
    ? ['name', 'category', 'model_code', 'specs', 'quoted_price', 'price_currency', 'moq', 'lead_time', 'payment_terms', 'shortlisted']
    : selected && isType(selected, ['supplier', 'exhibitor'])
      ? ['name', 'supplier_name', 'company_name', 'hall', 'booth', 'category', 'country', 'factory_location', 'export_markets']
      : [];
  const beginEdit = () => {
    if (!selected) return;
    setDraft(Object.fromEntries(editKeys.map((key) => [key, selected.payload[key] ?? ''])));
    setEditing(true);
  };
  const saveEdit = async (event: React.FormEvent) => {
    event.preventDefault();
    if (!user || !teamId || !selected) return;
    const numberFields = new Set(['quoted_price', 'moq']);
    const changes = Object.fromEntries(Object.entries(draft).map(([key, value]) => [
      key,
      numberFields.has(key) && typeof value === 'string' && value.trim() ? Number(value) : value,
    ]));
    setBusy(true); setError('');
    try {
      const updated = await updateRecord(teamId, selected, changes);
      setRecords((current) => current.map((record) => record.record_type === updated.record_type && record.record_id === updated.record_id ? updated : record));
      setSelected(updated); setEditing(false);
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : 'Could not save the record.');
    } finally { setBusy(false); }
  };

  if (!isConfigured()) return <main className="login-shell"><section className="login-card">
    <p className="eyebrow">WORKSPACE SETUP</p><h1>Connect the desktop workspace.</h1>
    <p className="muted">Add the Supabase URL and anonymous browser key to <code>apps/web/.env.local</code>. Use the same Supabase project as mobile; the required variable names are in <code>.env.example</code>.</p>
  </section></main>;
  if (!user) return <Login onError={setError} />;

  return <main className="app-shell">
    <aside className="sidebar">
      <div className="brand"><span className="brand-mark">CF</span><div><strong>Canton Fair</strong><small>Sourcing workspace</small></div></div>
      <nav>{(Object.keys(viewMeta) as WorkspaceView[]).map((key) => <button key={key} className={view === key ? 'nav-item active' : 'nav-item'} onClick={() => setView(key)}>{viewMeta[key].label}</button>)}</nav>
      <div className="sidebar-footer"><span className="sync-dot" /> Shared team data<br /><small>Mobile captures sync here</small></div>
    </aside>
    <section className="workspace">
      <header className="topbar">
        <div><p className="eyebrow">DESKTOP MANAGEMENT</p><h2>{viewMeta[view].label}</h2></div>
        <div className="topbar-actions"><select value={teamId} onChange={(event) => setTeamId(event.target.value)} aria-label="Team workspace">{teams.map((team) => <option value={team.id} key={team.id}>{team.name} ({team.role})</option>)}</select><button onClick={() => void refresh()} disabled={busy}>Refresh</button><button onClick={exportRecords} disabled={!records.length}>Export data</button><button onClick={() => void supabase?.auth.signOut()}>Sign out</button></div>
      </header>
      {error && <div className="notice error">{error}</div>}
      <div className="notice">Mobile remains the field-capture tool. Use this workspace to review and manage synchronized supplier and product records.</div>
      {view === 'overview' && <section className="metrics">
        <Metric label="Suppliers" value={metrics.suppliers} caption="Team records" />
        <Metric label="Products" value={metrics.products} caption="Captured at booths" />
        <Metric label="Shortlisted" value={metrics.shortlist} caption="Ready for review" />
        <Metric label="Visit evidence" value={metrics.evidence} caption="Contacts, media and notes" />
      </section>}
      <section className="content-head"><div><h3>{view === 'overview' ? 'Recent synchronized activity' : viewMeta[view].label}</h3><p>{busy ? 'Loading shared records...' : `${scoped.length} matching record${scoped.length === 1 ? '' : 's'}`}</p></div><input className="search" value={search} onChange={(event) => setSearch(event.target.value)} placeholder="Search names, products, fields..." /></section>
      {(view === 'suppliers' || view === 'products' || view === 'shortlist') && <SourcingWorkspace mode={view} records={records} query={search} onOpen={(record) => { setSelected(record); setEditing(false); }} />}
      {view === 'visits' && <VisitEvidenceWorkspace records={records} query={search} onOpen={(record) => { setSelected(record); setEditing(false); }} />}
      <section className={(view === 'suppliers' || view === 'products' || view === 'shortlist' || view === 'visits') ? 'record-table secondary-table' : 'record-table'}>
        <div className="table-row table-heading"><span>Record</span><span>Type</span><span>Updated</span><span /></div>
        {!busy && scoped.length === 0 && <div className="empty"><strong>No matching synchronized records</strong><span>Mobile captures will appear here after team sync completes.</span></div>}
        {scoped.map((record) => <button className="table-row record-row" key={`${record.record_type}:${record.record_id}`} onClick={() => { setSelected(record); setEditing(false); }}><span><strong>{recordName(record)}</strong><small>{valueOf(record.payload, ['category', 'hall', 'booth', 'model_code']) || 'Open details'}</small></span><span><em>{businessTypeLabel(record)}</em>{isShortlisted(record) && <b>Shortlisted</b>}</span><span>{dateLabel(record.updated_at)}</span><span aria-hidden="true">›</span></button>)}
      </section>
    </section>
    {selected && <aside className="detail-panel"><button className="close" onClick={() => { setSelected(null); setEditing(false); }}>Close</button><p className="eyebrow">{businessTypeLabel(selected)}</p><h3>{recordName(selected)}</h3><p className="muted">Updated {dateLabel(selected.updated_at)}</p>{editKeys.length > 0 && !editing && <button className="edit-button" onClick={beginEdit}>Edit synchronized fields</button>}{editing ? <form className="edit-form" onSubmit={saveEdit}>{editKeys.map((key) => <label key={key}>{fieldLabels[key] ?? key}{key === 'shortlisted' ? <input checked={draft[key] === true || draft[key] === 1 || draft[key] === '1'} onChange={(event) => setDraft((current) => ({ ...current, [key]: event.target.checked }))} type="checkbox" /> : key === 'specs' ? <textarea value={String(draft[key] ?? '')} onChange={(event) => setDraft((current) => ({ ...current, [key]: event.target.value }))} /> : <input value={String(draft[key] ?? '')} onChange={(event) => setDraft((current) => ({ ...current, [key]: event.target.value }))} />}</label>)}<div className="form-actions"><button type="button" onClick={() => setEditing(false)}>Cancel</button><button className="primary" disabled={busy}>Save reviewed changes</button></div></form> : <dl>{visibleDetails(selected).map(([key, value]) => <div key={key}><dt>{fieldLabels[key]}</dt><dd>{String(value ?? '—')}</dd></div>)}</dl>}</aside>}
  </main>;
}

function Metric({ label, value, caption }: { label: string; value: number; caption: string }) {
  return <article className="metric"><span>{label}</span><strong>{value}</strong><small>{caption}</small></article>;
}

createRoot(document.getElementById('root')!).render(<App />);
