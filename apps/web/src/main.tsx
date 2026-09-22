import { useEffect, useMemo, useState } from 'react';
import { createRoot } from 'react-dom/client';
import type { User } from '@supabase/supabase-js';
import { createRecord, isConfigured, loadRecords, loadTeams, supabase, updateRecord } from './api';
import { SourcingWorkspace } from './sourcing_workspace';
import { VisitEvidenceWorkspace } from './visit_evidence_workspace';
import { ProcurementControlCenter } from './procurement_control_center';
import { ProcurementCompletionTools } from './procurement_completion_tools';
import type { JsonRecord, Team, TeamRecord, WorkspaceView } from './types';
import './styles.css';

const viewMeta: Record<WorkspaceView, { label: string; types: string[] }> = {
  overview: { label: 'Overview', types: [] },
  suppliers: { label: 'Suppliers', types: ['supplier', 'exhibitor'] },
  products: { label: 'Products', types: ['product'] },
  visits: { label: 'Visit evidence', types: ['visit_session', 'recording', 'contact', 'attachment', 'meeting', 'activity'] },
  shortlist: { label: 'Shortlist', types: ['product'] },
  trips: { label: 'Trips & hall visits', types: ['trip', 'visit_session'] },
  contacts: { label: 'Contacts', types: ['contact'] },
  followups: { label: 'Follow-ups', types: ['meeting'] },
  activity: { label: 'Team activity', types: ['activity'] },
  procurement: { label: 'Procurement review', types: ['quote', 'product'] },
  reports: { label: 'Reports & analytics', types: [] },
  fieldTools: { label: 'Field tools', types: [] },
  routes: { label: 'Route planner', types: ['visit_plan'] },
  categories: { label: 'Product categories', types: ['product_category'] },
};

const sidebarViews: WorkspaceView[] = ['overview', 'suppliers', 'trips', 'routes', 'categories', 'fieldTools', 'procurement', 'reports'];

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
  'assignment', 'product_category_assignment',
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
  notes: 'Notes', note: 'Note', body: 'Notes', transcript: 'Transcript', file_name: 'File name',
  subject: 'Subject', status: 'Status', started_at: 'Started', ended_at: 'Ended',
  export_markets: 'Export markets', factory_location: 'Factory location',
  city: 'City', start_date: 'Start date', end_date: 'End date', due_date: 'Due date',
  outcome: 'Outcome', assignee_email: 'Assigned to', priority: 'Priority',
  quote_type: 'Quote type', valid_until: 'Valid until', supplier_commitment: 'Supplier commitment',
  route_status: 'Route status', planned_visit_at: 'Planned visit', trip_record_id: 'Trip',
};

const visibleFieldKeys = new Set(Object.keys(fieldLabels));

function businessTypeLabel(record: TeamRecord): string {
  const labels: Record<string, string> = {
    supplier: 'Supplier', exhibitor: 'Exhibitor', product: 'Product', contact: 'Contact',
    meeting: 'Meeting', recording: 'Recording', attachment: 'Attachment',
    activity: 'Activity', trip: 'Trip', visit_session: 'Visit', quote: 'Quotation',
    visit_plan: 'Route stop', product_category: 'Product category',
  };
  return labels[record.record_type] ?? 'Business';
}

function isInternalRecord(record: TeamRecord): boolean {
  return internalRecordTypes.has(record.record_type) || record.payload._deleted === true;
}

function isSupplierRecord(record: TeamRecord): boolean {
  return record.record_type === 'supplier' || record.record_type === 'exhibitor';
}

function isProductRecord(record: TeamRecord): boolean {
  return record.record_type === 'product';
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
    <p className="eyebrow">FAIR EXPERT / SOURCING WORKSPACE</p>
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
  const activeTeam = teams.find((team) => team.id === teamId);
  const canWrite = activeTeam?.role !== 'viewer';

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
    if (view === 'reports') return false;
    if (view === 'overview' && !isType(record, [
      'supplier', 'exhibitor', 'product', 'contact', 'meeting', 'recording', 'activity', 'trip', 'visit_session', 'quote',
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
    shortlist: records.filter((record) => !isInternalRecord(record) && isShortlisted(record)).length,
    evidence: records.filter((record) => !isInternalRecord(record) && isType(record, viewMeta.visits.types)).length,
  }), [records]);

  const exportBusinessCsv = () => {
    const fields = ['Record type', 'Name', 'Supplier', 'Category', 'Hall', 'Booth', 'Contact', 'Email', 'Phone', 'Price', 'Currency', 'MOQ', 'Lead time', 'Status', 'Updated'];
    const quote = (value: unknown) => `"${String(value ?? '').replaceAll('"', '""')}"`;
    const rows = records.filter((record) => !isInternalRecord(record)).map((record) => [
      businessTypeLabel(record),
      recordName(record),
      valueOf(record.payload, ['supplier_name', 'company_name']),
      valueOf(record.payload, ['category', 'industry']),
      valueOf(record.payload, ['hall', 'hall_number']),
      valueOf(record.payload, ['booth']),
      valueOf(record.payload, ['contact_name', 'name']),
      valueOf(record.payload, ['email']),
      valueOf(record.payload, ['phone', 'whatsapp']),
      valueOf(record.payload, ['quoted_price']),
      valueOf(record.payload, ['price_currency']),
      valueOf(record.payload, ['moq']),
      valueOf(record.payload, ['lead_time']),
      valueOf(record.payload, ['status', 'outcome']),
      dateLabel(record.updated_at),
    ].map(quote).join(','));
    const blob = new Blob([[fields.map(quote).join(','), ...rows].join('\n')], { type: 'text/csv;charset=utf-8' });
    const url = URL.createObjectURL(blob);
    const anchor = document.createElement('a');
    anchor.href = url; anchor.download = 'fair-expert-business-export.csv'; anchor.click();
    URL.revokeObjectURL(url);
  };

  const createSharedRecord = async (recordType: string, payload: JsonRecord) => {
    if (!teamId || !canWrite) {
      setError('This workspace is read-only for your account.');
      return;
    }
    setBusy(true); setError('');
    try {
      const created = await createRecord(teamId, recordType, payload);
      setRecords((current) => [created, ...current]);
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : 'Could not create the shared record.');
    } finally { setBusy(false); }
  };

  const createRouteStop = async (details: { tripId: string; supplier: string; hall: string; booth: string; category: string; note: string }) => {
    if (!teamId || !canWrite) {
      setError('This workspace is read-only for your account.');
      return;
    }
    setBusy(true); setError('');
    try {
      const createdAt = new Date().toISOString();
      const supplier = await createRecord(teamId, 'supplier', {
        name: details.supplier, supplier_name: details.supplier, company_name: details.supplier,
        trip_record_id: details.tripId, hall: details.hall, booth: details.booth,
        category: details.category, created_at: createdAt,
      });
      const participation = await createRecord(teamId, 'supplier_participation', {
        supplier_record_id: supplier.record_id, trip_record_id: details.tripId, created_at: createdAt,
      });
      const booth = await createRecord(teamId, 'exhibitor_booth', {
        supplier_participation_record_id: participation.record_id, hall: details.hall,
        booth: details.booth, zone: '', created_at: createdAt,
      });
      const route = await createRecord(teamId, 'visit_plan', {
        exhibitor_booth_record_id: booth.record_id, priority: '1', selected: '1',
        notes: details.note, route_status: 'Planned', planned_visit_at: createdAt, created_at: createdAt,
      });
      setRecords((current) => [route, booth, participation, supplier, ...current]);
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : 'Could not create the route stop.');
    } finally { setBusy(false); }
  };

  const selectedSupplier = selected ? (isSupplierRecord(selected) ? selected : relatedSupplier(selected, records)) : undefined;
  const productCategories = useMemo(() => records
    .filter((record) => record.record_type === 'product_category')
    .map((record) => valueOf(record.payload, ['name']))
    .filter(Boolean)
    .sort((left, right) => left.localeCompare(right)), [records]);
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
      <div className="brand"><span className="brand-mark">FE</span><div><strong>Fair Expert</strong><small>Sourcing workspace</small></div></div>
      <nav>{sidebarViews.map((key) => <button key={key} className={view === key ? 'nav-item active' : 'nav-item'} onClick={() => setView(key)}>{viewMeta[key].label}</button>)}</nav>
      <div className="sidebar-footer"><span className="sync-dot" /> Shared team data<br /><small>Mobile captures sync here</small></div>
    </aside>
    <section className="workspace">
      <header className="topbar">
        <div><p className="eyebrow">DESKTOP MANAGEMENT</p><h2>{viewMeta[view].label}</h2></div>
        <div className="topbar-actions"><select value={teamId} onChange={(event) => setTeamId(event.target.value)} aria-label="Team workspace">{teams.map((team) => <option value={team.id} key={team.id}>{team.name} ({team.role})</option>)}</select><button onClick={() => void refresh()} disabled={busy}>Refresh</button><button onClick={exportBusinessCsv} disabled={!records.length}>Export business CSV</button><button onClick={() => void supabase?.auth.signOut()}>Sign out</button></div>
      </header>
      {error && <div className="notice error">{error}</div>}
      <div className="notice">Mobile is reserved for field capture. Use this workspace for review, follow-ups, procurement decisions, reports, and shared team management.</div>
      {!canWrite && <div className="notice warning">This team role is read-only. Ask an administrator to change your role before creating route stops or product categories.</div>}
      {view === 'overview' && <section className="metrics">
        <Metric label="Suppliers" value={metrics.suppliers} caption="Team records" />
        <Metric label="Products" value={metrics.products} caption="Captured at booths" />
        <Metric label="Shortlisted" value={metrics.shortlist} caption="Ready for review" />
        <Metric label="Visit evidence" value={metrics.evidence} caption="Contacts, media and notes" />
      </section>}
      {view === 'fieldTools' ? <FieldToolsWorkspace onNavigate={setView} /> : view === 'routes' ? <RoutePlanner records={records} canWrite={canWrite} busy={busy} onCreateRoute={createRouteStop} /> : view === 'categories' ? <CategoryMaster records={records} canWrite={canWrite} busy={busy} onCreate={createSharedRecord} /> : view === 'reports' ? <ReportsWorkspace records={records} metrics={metrics} onExport={exportBusinessCsv} /> : <>
        <section className="content-head"><div><h3>{view === 'overview' ? 'Recent synchronized activity' : viewMeta[view].label}</h3><p>{busy ? 'Loading shared records...' : `${scoped.length} matching record${scoped.length === 1 ? '' : 's'}`}</p></div><input className="search" value={search} onChange={(event) => setSearch(event.target.value)} placeholder="Search names, products, fields..." /></section>
        {(view === 'suppliers' || view === 'products' || view === 'shortlist') && <SourcingWorkspace mode={view} records={records} query={search} onOpen={(record) => { setSelected(record); setEditing(false); }} />}
        {view === 'visits' && <VisitEvidenceWorkspace records={records} query={search} onOpen={(record) => { setSelected(record); setEditing(false); }} />}
        {view === 'procurement' && <ProcurementControlCenter records={records} role={activeTeam?.role ?? 'member'} onOpen={(record) => { setSelected(record); setEditing(false); }} onUpdate={async (record, changes) => { const updated = await updateRecord(teamId, record, changes); setRecords((current) => current.map((item) => item.record_type === updated.record_type && item.record_id === updated.record_id ? updated : item)); }} />}
        {view === 'procurement' && <ProcurementCompletionTools team={activeTeam} records={records} onOpen={(record) => { setSelected(record); setEditing(false); }} />}
        <section className={(view === 'suppliers' || view === 'products' || view === 'shortlist' || view === 'visits') ? 'record-table secondary-table' : 'record-table'}>
          <div className="table-row table-heading"><span>Record</span><span>Type</span><span>Updated</span><span /></div>
          {!busy && scoped.length === 0 && <div className="empty"><strong>No matching synchronized records</strong><span>Mobile captures will appear here after team sync completes.</span></div>}
          {scoped.map((record) => <button className="table-row record-row" key={`${record.record_type}:${record.record_id}`} onClick={() => { setSelected(record); setEditing(false); }}><span><strong>{recordName(record)}</strong><small>{valueOf(record.payload, ['category', 'hall', 'booth', 'model_code']) || 'Open details'}</small></span><span><em>{businessTypeLabel(record)}</em>{isShortlisted(record) && <b>Shortlisted</b>}</span><span>{dateLabel(record.updated_at)}</span><span aria-hidden="true">›</span></button>)}
        </section>
      </>}
    </section>
    {selected && (selectedSupplier ? <SupplierMasterPanel supplier={selectedSupplier} records={records} initialRecord={selected} onClose={() => { setSelected(null); setEditing(false); }} onEdit={beginEdit} /> : <aside className="detail-panel"><button className="close" onClick={() => { setSelected(null); setEditing(false); }}>Close</button><p className="eyebrow">{businessTypeLabel(selected)}</p><h3>{recordName(selected)}</h3><p className="muted">Updated {dateLabel(selected.updated_at)}</p>{editKeys.length > 0 && !editing && <button className="edit-button" onClick={beginEdit}>Edit synchronized fields</button>}{editing ? <form className="edit-form" onSubmit={saveEdit}>{editKeys.map((key) => <label key={key}>{fieldLabels[key] ?? key}{key === 'shortlisted' ? <input checked={draft[key] === true || draft[key] === 1 || draft[key] === '1'} onChange={(event) => setDraft((current) => ({ ...current, [key]: event.target.checked }))} type="checkbox" /> : key === 'category' && isProductRecord(selected) ? <select value={String(draft[key] ?? '')} onChange={(event) => setDraft((current) => ({ ...current, [key]: event.target.value }))}><option value="">Choose a category</option>{productCategories.map((category) => <option key={category} value={category}>{category}</option>)}</select> : key === 'specs' ? <textarea value={String(draft[key] ?? '')} onChange={(event) => setDraft((current) => ({ ...current, [key]: event.target.value }))} /> : <input value={String(draft[key] ?? '')} onChange={(event) => setDraft((current) => ({ ...current, [key]: event.target.value }))} />}</label>)}<div className="form-actions"><button type="button" onClick={() => setEditing(false)}>Cancel</button><button className="primary" disabled={busy}>Save reviewed changes</button></div></form> : <dl>{visibleDetails(selected).map(([key, value]) => <div key={key}><dt>{fieldLabels[key]}</dt><dd>{String(value ?? '—')}</dd></div>)}</dl>}</aside>)}
  </main>;
}

function Metric({ label, value, caption }: { label: string; value: number; caption: string }) {
  return <article className="metric"><span>{label}</span><strong>{value}</strong><small>{caption}</small></article>;
}

function FieldToolsWorkspace({ onNavigate }: { onNavigate: (view: WorkspaceView) => void }) {
  const tools: Array<[WorkspaceView, string, string]> = [
    ['routes', 'Route planner', 'Create manual stops and organise supplier visits by hall and booth.'],
    ['categories', 'Product categories', 'Maintain the shared category master used during product entry.'],
    ['suppliers', 'Supplier workspace', 'Review suppliers, contacts, products, and visit evidence.'],
    ['trips', 'Trips and hall visits', 'Review trips, visits, and fair locations.'],
    ['procurement', 'Procurement review', 'Compare quotations, pipeline decisions, and supplier scorecards.'],
    ['reports', 'Reports and analytics', 'Review sourcing progress and export business records.'],
  ];
  return <section className="tools-workspace"><div className="tools-hero"><p className="eyebrow">WEB FIELD OPERATIONS</p><h3>Everyday field tools, available at your desk.</h3><p>These controls use the same shared team records and role permissions as the mobile workflow.</p></div><div className="tools-grid">{tools.map(([view, title, detail]) => <button key={view} className="tool-card" onClick={() => onNavigate(view)}><strong>{title}</strong><span>{detail}</span><b>Open</b></button>)}</div></section>;
}

function RoutePlanner({ records, canWrite, busy, onCreateRoute }: { records: TeamRecord[]; canWrite: boolean; busy: boolean; onCreateRoute: (details: { tripId: string; supplier: string; hall: string; booth: string; category: string; note: string }) => Promise<void> }) {
  const trips = records.filter((record) => record.record_type === 'trip');
  const routes = records.filter((record) => record.record_type === 'visit_plan');
  const categories = records.filter((record) => record.record_type === 'product_category')
    .map((record) => valueOf(record.payload, ['name']))
    .filter(Boolean)
    .sort((left, right) => left.localeCompare(right));
  const [tripId, setTripId] = useState(''); const [supplier, setSupplier] = useState(''); const [hall, setHall] = useState(''); const [booth, setBooth] = useState(''); const [category, setCategory] = useState(''); const [note, setNote] = useState('');
  const submit = async (event: React.FormEvent) => { event.preventDefault(); if (!tripId || !supplier.trim() || !hall.trim()) return; await onCreateRoute({ tripId, supplier: supplier.trim(), hall: hall.trim(), booth: booth.trim(), category: category.trim(), note: note.trim() }); setSupplier(''); setHall(''); setBooth(''); setCategory(''); setNote(''); };
  return <section className="operations-layout"><div className="operations-hero"><p className="eyebrow">ROUTE PLANNER</p><h3>Create a practical hall-by-hall visit route.</h3><p>Members and administrators can add manual stops. Viewers can review the shared route.</p></div><div className="operations-grid"><form className="operations-card" onSubmit={(event) => void submit(event)}><h4>Add manual route stop</h4><label>Trip<select value={tripId} onChange={(event) => setTripId(event.target.value)} disabled={!canWrite || busy} required><option value="">Select trip</option>{trips.map((trip) => <option key={trip.record_id} value={trip.record_id}>{recordName(trip)}</option>)}</select></label><label>Supplier or stop name<input value={supplier} onChange={(event) => setSupplier(event.target.value)} disabled={!canWrite || busy} required /></label><div className="two-fields"><label>Hall<input value={hall} onChange={(event) => setHall(event.target.value)} disabled={!canWrite || busy} required /></label><label>Booth<input value={booth} onChange={(event) => setBooth(event.target.value)} disabled={!canWrite || busy} /></label></div><label>Product category<select value={category} onChange={(event) => setCategory(event.target.value)} disabled={!canWrite || busy || !categories.length}><option value="">{categories.length ? 'Choose a category' : 'Create a category first'}</option>{categories.map((item) => <option key={item} value={item}>{item}</option>)}</select></label>{!categories.length && <p className="muted">Open <strong>Product categories</strong> in the sidebar to create the first category.</p>}<label>Route note<textarea value={note} onChange={(event) => setNote(event.target.value)} disabled={!canWrite || busy} /></label><button className="primary" disabled={!canWrite || busy || !trips.length}>{busy ? 'Saving...' : 'Add to route'}</button>{!trips.length && <p className="muted">Create or synchronize a trip first.</p>}</form><section className="operations-card"><h4>Planned route stops <span>{routes.length}</span></h4><div className="master-list">{routes.map((route) => <article key={route.record_id}><strong>{recordName(route)}</strong><span>Hall {valueOf(route.payload, ['hall']) || 'not recorded'}{valueOf(route.payload, ['booth']) ? ` · Booth ${valueOf(route.payload, ['booth'])}` : ''}</span><small>{valueOf(route.payload, ['category', 'notes']) || 'Planned stop'}</small></article>)}{!routes.length && <p className="muted">No route stops yet. Add the first stop above.</p>}</div></section></div></section>;
}

function CategoryMaster({ records, canWrite, busy, onCreate }: { records: TeamRecord[]; canWrite: boolean; busy: boolean; onCreate: (recordType: string, payload: JsonRecord) => Promise<void> }) {
  const categories = records.filter((record) => record.record_type === 'product_category'); const [name, setName] = useState('');
  const submit = async (event: React.FormEvent) => { event.preventDefault(); const value = name.trim(); if (!value) return; await onCreate('product_category', { name: value, normalized_name: value.toLowerCase(), archived: '0', created_at: new Date().toISOString() }); setName(''); };
  return <section className="operations-layout"><div className="operations-hero"><p className="eyebrow">PRODUCT MASTER</p><h3>Shared product categories.</h3><p>Categories created here are available to product capture on web and mobile.</p></div><div className="operations-grid"><form className="operations-card" onSubmit={(event) => void submit(event)}><h4>Create product category</h4><label>Category name<input value={name} onChange={(event) => setName(event.target.value)} disabled={!canWrite || busy} placeholder="Example: Home decor" required /></label><button className="primary" disabled={!canWrite || busy}>{busy ? 'Saving...' : 'Create category'}</button></form><section className="operations-card"><h4>Available categories <span>{categories.length}</span></h4><div className="master-list">{categories.map((category) => <article key={category.record_id}><strong>{valueOf(category.payload, ['name'])}</strong><span>Available for product capture</span></article>)}{!categories.length && <p className="muted">No categories yet. Create the first category above.</p>}</div></section></div></section>;
}

function ReportsWorkspace({ records, metrics, onExport }: { records: TeamRecord[]; metrics: { suppliers: number; products: number; shortlist: number; evidence: number }; onExport: () => void }) {
  const businessRecords = records.filter((record) => !isInternalRecord(record));
  const typeCounts = new Map<string, number>();
  for (const record of businessRecords) {
    const label = businessTypeLabel(record);
    typeCounts.set(label, (typeCounts.get(label) ?? 0) + 1);
  }
  const shortlistRate = metrics.products === 0 ? 0 : Math.round((metrics.shortlist / metrics.products) * 100);
  return <section className="reports-workspace">
    <div className="reports-hero"><div><p className="eyebrow">TEAM DECISION BRIEF</p><h3>Fair progress at a glance</h3><p>Desktop reporting uses shared supplier, product, visit, and follow-up records from your team workspace.</p></div><button className="primary report-export" onClick={onExport}>Download business CSV</button></div>
    <div className="report-metrics"><Metric label="Supplier coverage" value={metrics.suppliers} caption="Supplier records captured" /><Metric label="Product review" value={metrics.products} caption="Products ready for comparison" /><Metric label="Shortlist conversion" value={shortlistRate} caption={`${metrics.shortlist} shortlisted products`} /><Metric label="Visit evidence" value={metrics.evidence} caption="Contacts, media and notes" /></div>
    <div className="report-grid"><article className="report-card"><p className="eyebrow">RECORD COVERAGE</p><h3>Workspace breakdown</h3><div className="breakdown-list">{[...typeCounts.entries()].sort((a, b) => b[1] - a[1]).map(([label, count]) => <div key={label}><span>{label}</span><strong>{count}</strong></div>)}{typeCounts.size === 0 && <p className="muted">No synchronized business records yet.</p>}</div></article><article className="report-card"><p className="eyebrow">TEAM ACTION</p><h3>Suggested desktop review</h3><ul><li>Compare shortlisted products before requesting final quotations.</li><li>Review follow-ups and meeting outcomes with the supplier owner.</li><li>Use visit evidence to validate contacts, product images, and notes.</li></ul></article></div>
  </section>;
}

function SupplierMasterPanel({ supplier, records, initialRecord, onClose, onEdit }: { supplier: TeamRecord; records: TeamRecord[]; initialRecord?: TeamRecord; onClose: () => void; onEdit: () => void }) {
  const supplierName = recordName(supplier).toLowerCase();
  const related = records.filter((record) => {
    if (record.record_id === supplier.record_id || isInternalRecord(record)) return false;
    const parentId = valueOf(record.payload, ['supplier_record_id', 'exhibitor_record_id', 'owner_record_id']);
    if (parentId === supplier.record_id) return true;
    const namedSupplier = valueOf(record.payload, ['supplier_name', 'company_name']).toLowerCase();
    return Boolean(namedSupplier) && namedSupplier === supplierName && ['contact', 'product', 'meeting', 'recording', 'attachment', 'activity', 'quote', 'visit_session'].includes(record.record_type);
  });
  const group = (types: string[]) => related.filter((record) => types.includes(record.record_type));
  const contacts = group(['contact']);
  const products = group(['product', 'quote']);
  const visits = group(['visit_session', 'meeting', 'activity']);
  const productRecords = products.filter((record) => record.record_type === 'product');
  const productNames = new Map(productRecords.map((record) => [record.record_id, recordName(record)]));
  const productMedia = records.filter((record) => record.record_type === 'attachment' && !isInternalRecord(record) && productNames.has(valueOf(record.payload, ['owner_record_id'])));
  const catalogues = group(['attachment']).filter((record) => valueOf(record.payload, ['kind']) === 'catalogue');
  const evidence = [...group(['recording', 'attachment']).filter((record) => valueOf(record.payload, ['kind']) !== 'catalogue'), ...productMedia.filter((record) => !related.some((item) => item.record_id === record.record_id))];
  const [inspectedRecord, setInspectedRecord] = useState<TeamRecord>(initialRecord ?? supplier);
  const directEvidence = evidence.filter((record) => !productMedia.some((media) => media.record_id === record.record_id));
  return <aside className="detail-panel supplier-master"><button className="close" onClick={onClose}>Back to suppliers</button><p className="eyebrow">SUPPLIER MASTER</p><h3>{recordName(supplier)}</h3><p className="muted">Everything captured for this supplier, in one place.</p><button className="edit-button" onClick={onEdit}>Edit supplier profile</button><div className="master-layout"><div className="master-main"><MasterSection title="Supplier profile" records={[supplier]} onSelect={setInspectedRecord} selectedRecordId={inspectedRecord.record_id} /><MasterSection title="Contacts" records={contacts} empty="No contacts captured yet." onSelect={setInspectedRecord} selectedRecordId={inspectedRecord.record_id} /><ProductList products={productRecords} media={productMedia} inspectedRecordId={inspectedRecord.record_id} onSelect={setInspectedRecord} /><MasterSection title="Catalogue vault" records={catalogues} empty="No supplier catalogues archived yet." onSelect={setInspectedRecord} selectedRecordId={inspectedRecord.record_id} /><MasterSection title="Visits & follow-ups" records={visits} empty="No visits or follow-ups captured yet." onSelect={setInspectedRecord} selectedRecordId={inspectedRecord.record_id} /><MasterSection title="Photos, cards & recordings" records={directEvidence} productNames={productNames} empty="No supplier photos, cards, or recordings captured yet." onSelect={setInspectedRecord} selectedRecordId={inspectedRecord.record_id} /></div><RecordInspector record={inspectedRecord} records={records} /></div></aside>;
}

function ProductList({ products, media, inspectedRecordId, onSelect }: { products: TeamRecord[]; media: TeamRecord[]; inspectedRecordId: string; onSelect: (record: TeamRecord) => void }) {
  return <section className="master-section"><h4>Products & quotations<span>{products.length}</span></h4>{products.length === 0 ? <p className="master-empty">No products captured yet. Add products from this supplier on mobile.</p> : <div className="product-list">{products.map((product) => <button type="button" key={product.record_id} className={inspectedRecordId === product.record_id ? 'product-card active' : 'product-card'} onClick={() => onSelect(product)}><ProductThumbnail record={media.find((item) => valueOf(item.payload, ['owner_record_id']) === product.record_id)} /><span><strong>{recordName(product)}</strong><small>{valueOf(product.payload, ['model_code']) || valueOf(product.payload, ['category']) || 'Product details captured'}</small><em>{[valueOf(product.payload, ['quoted_price']), valueOf(product.payload, ['price_currency'])].filter(Boolean).join(' ') || 'Price pending'} · MOQ {valueOf(product.payload, ['moq']) || '—'}</em></span><b>{isShortlisted(product) ? 'Shortlisted' : 'Open details'}</b></button>)}</div>}</section>;
}

function ProductThumbnail({ record }: { record?: TeamRecord }) {
  const path = record ? valueOf(record.payload, ['storage_path']) : '';
  const [url, setUrl] = useState('');
  useEffect(() => { let active = true; setUrl(''); if (!path || !supabase) return () => { active = false; }; void supabase.storage.from('team-attachments').createSignedUrl(path, 3600).then(({ data }) => { if (active && data?.signedUrl) setUrl(data.signedUrl); }); return () => { active = false; }; }, [path]);
  return <span className="product-thumb">{url ? <img src={url} alt="Product" /> : <span>NO IMAGE</span>}</span>;
}

function RecordInspector({ record, records }: { record: TeamRecord; records: TeamRecord[] }) {
  const isProduct = record.record_type === 'product';
  const media = isProduct ? records.filter((item) => item.record_type === 'attachment' && !isInternalRecord(item) && valueOf(item.payload, ['owner_record_id']) === record.record_id) : [];
  const supplier = record.record_type === 'contact' ? relatedSupplier(record, records) : undefined;
  const inheritedContactFields = supplier ? contactFields(capturedBusinessFields(supplier.payload.field_capture_json)) : {};
  const payload = { ...inheritedContactFields, ...capturedBusinessFields(record.payload.field_capture_json), ...capturedBusinessFields(record.payload.profile_json), ...populatedPayload(record.payload) };
  const fields = Object.entries(payload).filter(([key, value]) => isDisplayableInspectorField(key, value));
  return <aside className="supplier-inspector"><p className="eyebrow">{`${masterRecordKind(record)} inspector`.toUpperCase()}</p><h4>{masterRecordTitle(record)}</h4>{isProduct ? <div className="product-status"><span>{valueOf(record.payload, ['category']) || 'Uncategorized'}</span><span>{isShortlisted(record) ? 'Shortlisted' : 'Not shortlisted'}</span></div> : null}{record.record_type === 'attachment' ? <MediaMasterItem record={record} inspector /> : <dl className="inspector-fields">{fields.length === 0 ? <p className="master-empty">No additional details were captured for this record.</p> : fields.map(([key, value]) => <div key={key}><dt>{fieldLabel(key)}</dt><dd>{formatInspectorValue(key, value)}</dd></div>)}</dl>}{isProduct ? <MasterSection title="Product media" records={media} empty="No product images or documents captured yet." /> : null}</aside>;
}

function populatedPayload(payload: JsonRecord): JsonRecord {
  const fields: JsonRecord = {};
  for (const [key, value] of Object.entries(payload)) {
    if (value !== null && value !== undefined && value !== '') fields[key] = value;
  }
  return fields;
}

function contactFields(payload: JsonRecord): JsonRecord {
  const allowed = new Set(['contact_name', 'designation', 'email', 'phone', 'mobile', 'whatsapp', 'wechat', 'website']);
  return Object.fromEntries(Object.entries(payload).filter(([key]) => allowed.has(key))) as JsonRecord;
}

function relatedSupplier(record: TeamRecord, records: TeamRecord[]): TeamRecord | undefined {
  const supplierId = valueOf(record.payload, ['supplier_record_id', 'exhibitor_record_id', 'supplier_id']);
  if (supplierId) return records.find((item) => item.record_id === supplierId && isSupplierRecord(item));
  const supplierName = valueOf(record.payload, ['supplier_name', 'company_name']).toLowerCase();
  return supplierName ? records.find((item) => isSupplierRecord(item) && recordName(item).toLowerCase() === supplierName) : undefined;
}

function capturedBusinessFields(rawCapture: unknown): JsonRecord {
  if (rawCapture === null || rawCapture === undefined || rawCapture === '') return {};
  try {
    const parsed: unknown = typeof rawCapture === 'string' ? JSON.parse(rawCapture) : rawCapture;
    const fields: JsonRecord = {};
    const aliases: Record<string, string> = {
      companyName: 'company_name', legalCompanyName: 'legal_company_name', legalName: 'legal_company_name', localCompanyName: 'local_company_name',
      localName: 'local_company_name', brandNames: 'brand_names', tradingNames: 'trading_names', supplierType: 'supplier_type', companyType: 'company_type',
      hall: 'hall', hallNumber: 'hall', booth: 'booth', boothNumber: 'booth', zone: 'zone', category: 'category',
      country: 'country', city: 'city', address: 'address', factoryLocation: 'factory_location', exportMarkets: 'export_markets',
      productionCapacity: 'production_capacity', employeeCount: 'employee_count', factorySize: 'factory_size', yearEstablished: 'year_established',
      oemOdm: 'oem_odm', factoryAuditStatus: 'factory_audit_status', website: 'website', websiteUrl: 'website', companyWebsite: 'website', web: 'website',
      websites: 'website', companyEmails: 'company_emails', companyPhones: 'company_phones', companyFax: 'company_fax', factoryAddress: 'factory_address', warehouseAddress: 'warehouse_address', productsServices: 'products_services', certifications: 'certifications', exportLicense: 'export_license', notes: 'notes', other: 'additional_notes',
      email: 'email', otherEmails: 'other_emails', phone: 'phone', phoneNumber: 'phone', telephone: 'phone', mobile: 'mobile', otherPhones: 'other_phones', whatsapp: 'whatsapp', whatsApp: 'whatsapp', wechat: 'wechat', weChat: 'wechat', fax: 'fax', directLine: 'direct_line',
      contactName: 'contact_name', contactPerson: 'contact_name', contactPersonName: 'contact_name', personName: 'contact_name', person: 'contact_name', localPerson: 'local_contact_name', designation: 'designation', contactRole: 'designation', role: 'designation', department: 'department', contactSocial: 'contact_social', language: 'preferred_language', contactNotes: 'contact_notes',
    };
    const visit = (value: unknown) => {
      if (!value || typeof value !== 'object') return;
      for (const [key, nestedValue] of Object.entries(value as Record<string, unknown>)) {
        const target = aliases[key] ?? aliases[`${key.charAt(0).toLowerCase()}${key.slice(1)}`];
        if (target && (typeof nestedValue === 'string' || typeof nestedValue === 'number') && String(nestedValue).trim()) fields[target] = nestedValue;
        if (nestedValue && typeof nestedValue === 'object' && !Array.isArray(nestedValue)) visit(nestedValue);
      }
    };
    visit(parsed);
    return fields;
  } catch {
    return {};
  }
}

function isDisplayableInspectorField(key: string, value: unknown) {
  const hiddenFields = new Set([
    'id', 'name', 'record_id', 'team_id', 'user_id', 'storage_path', 'owner_record_id', 'owner_record_type',
    'trip_record_id', 'created_at', 'updated_at', 'tabs_json', 'verification_json', 'field_capture_json',
    'decoded', 'verification', 'rating', 'trust_score', 'model_score', 'quality_score', 'planned_visit_at',
  ]);
  if (hiddenFields.has(key) || key.endsWith('_json') || key.endsWith('_id')) return false;
  if (value === null || value === undefined || value === '') return false;
  if (typeof value === 'object') return false;
  if (typeof value === 'number' && value === 0 && key.includes('score')) return false;
  return true;
}

function fieldLabel(key: string) {
  return key.replace(/([a-z])([A-Z])/g, '$1 $2').replace(/_/g, ' ').replace(/\b\w/g, (letter) => letter.toUpperCase());
}

function formatInspectorValue(key: string, value: unknown) {
  if (key === 'shortlisted') return value ? 'Yes' : 'No';
  if (key === 'completed' || key === 'is_completed') return value === true || value === 1 || value === '1' ? 'Yes' : 'No';
  if ((key.endsWith('_at') || key.endsWith('_date') || key.includes('date')) && typeof value === 'string') {
    const date = new Date(value);
    if (!Number.isNaN(date.getTime())) return date.toLocaleString(undefined, { dateStyle: 'medium', timeStyle: 'short' });
  }
  if (typeof value === 'boolean') return value ? 'Yes' : 'No';
  if (Array.isArray(value)) return value.join(', ');
  if (typeof value === 'object') return Object.entries(value as Record<string, unknown>).map(([nestedKey, nestedValue]) => `${fieldLabel(nestedKey)}: ${String(nestedValue)}`).join(' · ');
  return String(value);
}

function MasterSection({ title, records, empty, productNames = new Map<string, string>(), onSelect, selectedRecordId }: { title: string; records: TeamRecord[]; empty?: string; productNames?: Map<string, string>; onSelect?: (record: TeamRecord) => void; selectedRecordId?: string }) {
  return <section className="master-section"><h4>{title}<span>{records.length}</span></h4>{records.length === 0 ? <p className="master-empty">{empty}</p> : records.map((record) => record.record_type === 'attachment' ? <div key={`${record.record_type}:${record.record_id}`} className={selectedRecordId === record.record_id ? 'media-selectable active' : 'media-selectable'} onClick={() => onSelect?.(record)}><MediaMasterItem record={record} productName={productNames.get(valueOf(record.payload, ['owner_record_id']))} /></div> : <button type="button" className={selectedRecordId === record.record_id ? 'master-item selectable active' : 'master-item selectable'} key={`${record.record_type}:${record.record_id}`} onClick={() => onSelect?.(record)}><strong>{masterRecordTitle(record)}</strong><small>{masterRecordKind(record)}</small><p>{masterRecordSummary(record)}</p></button>)}</section>;
}

function MediaMasterItem({ record, productName, inspector = false }: { record: TeamRecord; productName?: string; inspector?: boolean }) {
  const storagePath = valueOf(record.payload, ['storage_path']);
  const kind = valueOf(record.payload, ['kind']).toLowerCase() || 'file';
  const [url, setUrl] = useState('');
  const [unavailable, setUnavailable] = useState(false);
  const [enlarged, setEnlarged] = useState(false);
  useEffect(() => {
    let active = true;
    setUrl(''); setUnavailable(false);
    if (!storagePath || !supabase) { setUnavailable(true); return () => { active = false; }; }
    void supabase.storage.from('team-attachments').createSignedUrl(storagePath, 3600).then(({ data, error }) => {
      if (!active) return;
      if (error || !data?.signedUrl) setUnavailable(true);
      else setUrl(data.signedUrl);
    });
    return () => { active = false; };
  }, [storagePath]);
  const image = kind === 'image' || kind === 'photo';
  return <article className={inspector ? 'master-item media-item inspector-media' : 'master-item media-item'}>{!inspector && <><strong>{masterRecordTitle(record)}</strong><small>{productName ? `Product photo · ${productName}` : masterRecordKind(record)}</small></>}{inspector && <small className="media-inspector-meta">Captured supplier evidence · {masterRecordKind(record)}</small>}{image && url && <button className="media-preview" type="button" onClick={() => setEnlarged(true)} aria-label={`Enlarge ${masterRecordTitle(record)} accessibility view`}><img src={url} alt={masterRecordTitle(record)} /><span>Open full-size image</span></button>}{kind === 'audio' && url && <audio controls src={url}>Audio preview unavailable.</audio>}{['catalogue', 'pdf', 'document'].includes(kind) && url && <p><a href={url} target="_blank" rel="noreferrer" download>Download archived catalogue</a></p>}<p>{inspector ? 'Review the original capture at full size when needed.' : masterRecordSummary(record)}{unavailable ? ' Media preview is not available yet; it remains safely stored with this supplier.' : ''}</p>{enlarged && url && <div className="media-lightbox" role="dialog" aria-modal="true" aria-label={masterRecordTitle(record)} onClick={() => setEnlarged(false)}><div className="lightbox-content" onClick={(event) => event.stopPropagation()}><button type="button" className="lightbox-close" onClick={() => setEnlarged(false)}>Close</button><img src={url} alt={masterRecordTitle(record)} /></div></div>}</article>;
}

function masterRecordTitle(record: TeamRecord): string {
  if (record.record_type === 'attachment') return (valueOf(record.payload, ['note', 'file_name', 'title', 'name']) || 'Captured attachment').replace(/\s*\|\s*(?:card|image|capture)_\d+$/i, '');
  if (record.record_type === 'recording') return valueOf(record.payload, ['title', 'name', 'subject']) || 'Voice note';
  if (record.record_type === 'meeting') return valueOf(record.payload, ['subject', 'title', 'outcome']) || 'Supplier meeting';
  if (record.record_type === 'visit_session') return valueOf(record.payload, ['title', 'hall', 'booth']) || 'Booth visit';
  return recordName(record);
}

function masterRecordKind(record: TeamRecord): string {
  if (record.record_type === 'attachment') return valueOf(record.payload, ['kind', 'category', 'attachment_type']) || 'Saved card, photo, or file';
  if (record.record_type === 'recording') return 'Recorded supplier note';
  if (record.record_type === 'meeting') return 'Visit follow-up';
  return `${businessTypeLabel(record)}${record.record_type === 'product' && valueOf(record.payload, ['model_code', 'category']) ? ` · ${valueOf(record.payload, ['model_code', 'category'])}` : ''}`;
}

function masterRecordSummary(record: TeamRecord): string {
  const details = visibleDetails(record)
    .filter(([key, value]) => !['name', 'supplier_name', 'company_name', 'title', ...(record.record_type === 'attachment' ? ['note'] : [])].includes(key) && String(value ?? '').trim())
    .slice(0, 4)
    .map(([key, value]) => `${fieldLabels[key]}: ${String(value)}`);
  if (details.length) return details.join(' · ');
  if (record.record_type === 'attachment') return 'Saved with this supplier for desktop review.';
  if (record.record_type === 'recording') return 'Voice note is available in visit evidence.';
  if (record.record_type === 'meeting') return 'No meeting notes or outcome captured yet.';
  return 'No additional details captured yet.';
}

createRoot(document.getElementById('root')!).render(<App />);
