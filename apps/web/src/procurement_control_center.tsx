import { useMemo, useState } from 'react';
import type { JsonRecord, TeamRecord } from './types';

type Stage = 'New' | 'Reviewing' | 'Quotation requested' | 'Compared' | 'Shortlisted' | 'Approved' | 'Rejected';
const stages: Stage[] = ['New', 'Reviewing', 'Quotation requested', 'Compared', 'Shortlisted', 'Approved', 'Rejected'];

const value = (payload: JsonRecord, keys: string[]) => {
  for (const key of keys) {
    const item = payload[key];
    if (typeof item === 'string' && item.trim()) return item.trim();
    if (typeof item === 'number') return String(item);
  }
  return '';
};
const numeric = (payload: JsonRecord, keys: string[]) => {
  const parsed = Number(value(payload, keys));
  return Number.isFinite(parsed) ? parsed : null;
};
const supplier = (record: TeamRecord) => ['supplier', 'exhibitor'].includes(record.record_type);
const productOrQuote = (record: TeamRecord) => ['product', 'quote'].includes(record.record_type);
const name = (record: TeamRecord) => value(record.payload, ['name', 'supplier_name', 'company_name', 'product_name', 'title']) || 'Unnamed record';
const stageOf = (record: TeamRecord): Stage => stages.includes(value(record.payload, ['procurement_stage', 'status']) as Stage)
  ? value(record.payload, ['procurement_stage', 'status']) as Stage : 'New';
const dateLabel = (value: string) => new Date(value).toLocaleDateString();
const monday = (date: string) => {
  const value = new Date(date); const day = value.getDay();
  value.setDate(value.getDate() - ((day + 6) % 7));
  return value.toISOString().slice(0, 10);
};
const download = (name: string, content: string, type = 'text/csv;charset=utf-8') => {
  const blob = new Blob([content], { type }); const url = URL.createObjectURL(blob);
  const link = document.createElement('a'); link.href = url; link.download = name; link.click(); URL.revokeObjectURL(url);
};
const csv = (rows: string[][]) => rows.map((row) => row.map((item) => `"${item.replaceAll('"', '""')}"`).join(',')).join('\n');

export function ProcurementControlCenter({
  records, role, onOpen, onUpdate,
}: {
  records: TeamRecord[];
  role: string;
  onOpen: (record: TeamRecord) => void;
  onUpdate: (record: TeamRecord, changes: JsonRecord) => Promise<void>;
}) {
  const [query, setQuery] = useState('');
  const [hall, setHall] = useState('');
  const [country, setCountry] = useState('');
  const [category, setCategory] = useState('');
  const [owner, setOwner] = useState('');
  const [stage, setStage] = useState('');
  const [priority, setPriority] = useState('');
  const [selected, setSelected] = useState<string[]>([]);
  const [bulkOwner, setBulkOwner] = useState('');
  const [comparisonProduct, setComparisonProduct] = useState('');
  const [timelineSupplier, setTimelineSupplier] = useState('');
  const [busy, setBusy] = useState(false);
  const canControl = role.toLowerCase() === 'admin';

  const suppliers = useMemo(() => records.filter(supplier), [records]);
  const commercial = useMemo(() => records.filter(productOrQuote), [records]);
  const options = useMemo(() => ({
    halls: [...new Set(suppliers.map((record) => value(record.payload, ['hall', 'hall_number'])).filter(Boolean))].sort(),
    countries: [...new Set(suppliers.map((record) => value(record.payload, ['country'])).filter(Boolean))].sort(),
    categories: [...new Set(commercial.map((record) => value(record.payload, ['category'])).filter(Boolean))].sort(),
    owners: [...new Set(suppliers.map((record) => value(record.payload, ['assignee_email', 'owner_email', 'owner'])).filter(Boolean))].sort(),
    products: [...new Set(commercial.map((record) => value(record.payload, ['name', 'product_name'])).filter(Boolean))].sort(),
  }), [suppliers, commercial]);
  const visible = useMemo(() => suppliers.filter((record) => {
    const payload = record.payload;
    const haystack = `${name(record)} ${JSON.stringify(payload)}`.toLowerCase();
    return (!query || haystack.includes(query.toLowerCase()))
      && (!hall || value(payload, ['hall', 'hall_number']) === hall)
      && (!country || value(payload, ['country']) === country)
      && (!category || value(payload, ['category', 'industry']) === category)
      && (!owner || value(payload, ['assignee_email', 'owner_email', 'owner']) === owner)
      && (!stage || stageOf(record) === stage)
      && (!priority || value(payload, ['priority']) === priority);
  }), [suppliers, query, hall, country, category, owner, stage, priority]);
  const selectedSuppliers = suppliers.filter((record) => selected.includes(record.record_id));
  const selectedProduct = comparisonProduct || options.products[0] || '';
  const comparisons = commercial.filter((record) => value(record.payload, ['name', 'product_name']) === selectedProduct)
    .map((record) => ({ record, price: numeric(record.payload, ['quoted_price', 'unit_price', 'price']) }))
    .sort((a, b) => (a.price ?? Infinity) - (b.price ?? Infinity));
  const weeklyWinners = useMemo(() => {
    const groups = new Map<string, { record: TeamRecord; price: number; week: string }>();
    for (const record of commercial) {
      const product = value(record.payload, ['name', 'product_name']);
      const price = numeric(record.payload, ['quoted_price', 'unit_price', 'price']);
      if (!product || price == null) continue;
      const week = monday(record.updated_at); const key = `${week}|${product.toLowerCase()}`;
      const previous = groups.get(key);
      if (!previous || price < previous.price) groups.set(key, { record, price, week });
    }
    return [...groups.values()].sort((a, b) => b.week.localeCompare(a.week) || a.price - b.price);
  }, [commercial]);
  const timeline = useMemo(() => {
    const chosen = suppliers.find((record) => record.record_id === timelineSupplier) ?? visible[0];
    if (!chosen) return { supplier: undefined, records: [] as TeamRecord[] };
    const supplierName = name(chosen).toLowerCase();
    return { supplier: chosen, records: records.filter((record) => {
      if (record.record_id === chosen.record_id) return true;
      const parent = value(record.payload, ['supplier_record_id', 'exhibitor_record_id', 'owner_record_id']);
      return parent === chosen.record_id || value(record.payload, ['supplier_name', 'company_name']).toLowerCase() === supplierName;
    }).sort((a, b) => b.updated_at.localeCompare(a.updated_at)) };
  }, [records, suppliers, timelineSupplier, visible]);
  const overdueFollowups = records.filter((record) => record.record_type === 'meeting' && value(record.payload, ['follow_up_date', 'due_date']) && new Date(value(record.payload, ['follow_up_date', 'due_date'])) < new Date()).length;
  const quotePending = suppliers.filter((record) => stageOf(record) === 'Quotation requested').length;
  const opportunityCount = weeklyWinners.length;

  const updateSelected = async (changes: JsonRecord) => {
    if (!selectedSuppliers.length || !canControl) return;
    setBusy(true);
    try { await Promise.all(selectedSuppliers.map((record) => onUpdate(record, changes))); }
    finally { setBusy(false); }
  };
  const toggle = (record: TeamRecord) => setSelected((current) => current.includes(record.record_id)
    ? current.filter((id) => id !== record.record_id) : [...current, record.record_id]);
  const exportSuppliers = () => download('supplier-procurement-pack.csv', csv([
    ['Supplier', 'Hall', 'Country', 'Owner', 'Stage', 'Priority', 'Category', 'Updated'],
    ...selectedSuppliers.map((record) => [name(record), value(record.payload, ['hall']), value(record.payload, ['country']), value(record.payload, ['assignee_email', 'owner_email', 'owner']), stageOf(record), value(record.payload, ['priority']), value(record.payload, ['category', 'industry']), record.updated_at]),
  ]));
  const exportComparison = () => download('quote-comparison.xls', csv([
    ['Product', 'Supplier', 'Quoted price', 'Currency', 'MOQ', 'Lead time', 'Payment terms', 'Winner'],
    ...comparisons.map((item, index) => [selectedProduct, value(item.record.payload, ['supplier_name', 'company_name']), item.price?.toString() ?? '', value(item.record.payload, ['price_currency', 'currency']), value(item.record.payload, ['moq']), value(item.record.payload, ['lead_time']), value(item.record.payload, ['payment_terms']), index === 0 ? 'Lowest price' : '']),
  ]), 'application/vnd.ms-excel');

  return <section className="procurement-center">
    <header className="procurement-hero"><div><p className="eyebrow">PROCUREMENT CONTROL CENTER</p><h3>Turn fair captures into supplier decisions.</h3><p>Compare commercial terms, govern supplier progression, and preserve an auditable decision trail.</p></div><span className={canControl ? 'role-badge admin' : 'role-badge'}>{canControl ? 'Admin controls enabled' : 'Review-only team member'}</span></header>
    <div className="procurement-metrics"><Metric label="Suppliers captured" value={suppliers.length} caption="Shared supplier records" /><Metric label="Quotes pending" value={quotePending} caption="Awaiting commercial response" /><Metric label="Lowest-price opportunities" value={opportunityCount} caption="Weekly product winners" /><Metric label="Overdue follow-ups" value={overdueFollowups} caption="Action required" /></div>
    <section className="procurement-panel"><div className="panel-head"><div><p className="eyebrow">SMART SEARCH</p><h4>Supplier decision queue</h4></div><button onClick={() => setSelected(visible.map((record) => record.record_id))}>Select visible</button></div><div className="filter-grid"><input value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Supplier, product, certificate, note..." />{([['Hall', hall, setHall, options.halls], ['Country', country, setCountry, options.countries], ['Category', category, setCategory, options.categories], ['Assigned staff', owner, setOwner, options.owners], ['Pipeline', stage, setStage, stages], ['Priority', priority, setPriority, ['High', 'Medium', 'Low']]] as const).map(([label, current, change, items]) => <label key={label}><span>{label}</span><select value={current} onChange={(event) => change(event.target.value)}><option value="">All</option>{items.map((item) => <option key={item}>{item}</option>)}</select></label>)}</div><div className="bulk-bar"><strong>{selectedSuppliers.length} selected</strong><select value={bulkOwner} onChange={(event) => setBulkOwner(event.target.value)} disabled={!canControl}><option value="">Assign owner...</option>{options.owners.map((item) => <option key={item}>{item}</option>)}</select><button disabled={!canControl || !bulkOwner || busy} onClick={() => void updateSelected({ assignee_email: bulkOwner })}>Assign owner</button><button disabled={!canControl || busy} onClick={() => void updateSelected({ procurement_stage: 'Quotation requested', quotation_requested_at: new Date().toISOString() })}>Request quotation</button><button disabled={!canControl || busy} onClick={() => void updateSelected({ procurement_stage: 'Shortlisted', shortlisted: true })}>Shortlist</button><button disabled={!selectedSuppliers.length} onClick={exportSuppliers}>Export selected</button></div><div className="supplier-queue">{visible.map((record) => <article key={record.record_id} className="queue-row"><input type="checkbox" checked={selected.includes(record.record_id)} onChange={() => toggle(record)} /><button className="queue-open" onClick={() => onOpen(record)}><strong>{name(record)}</strong><small>{[value(record.payload, ['hall']), value(record.payload, ['country']), value(record.payload, ['category', 'industry'])].filter(Boolean).join(' · ') || 'Supplier details'}</small></button><span>{value(record.payload, ['assignee_email', 'owner_email', 'owner']) || 'Unassigned'}</span><select value={stageOf(record)} disabled={!canControl || busy} onChange={(event) => void onUpdate(record, { procurement_stage: event.target.value })}>{stages.map((item) => <option key={item}>{item}</option>)}</select><span className={`priority ${value(record.payload, ['priority']).toLowerCase()}`}>{value(record.payload, ['priority']) || 'Normal'}</span></article>)}{!visible.length && <p className="muted">No suppliers match these filters.</p>}</div></section>
    <div className="procurement-columns"><section className="procurement-panel"><div className="panel-head"><div><p className="eyebrow">COMPARISON MATRIX</p><h4>Commercial terms by supplier</h4></div><button onClick={exportComparison} disabled={!comparisons.length}>Export Excel</button></div><label className="comparison-choice">Product<select value={selectedProduct} onChange={(event) => setComparisonProduct(event.target.value)}>{options.products.map((item) => <option key={item}>{item}</option>)}</select></label><div className="matrix-wrap"><table><thead><tr><th>Supplier</th><th>Price</th><th>MOQ</th><th>Lead time</th><th>Payment terms</th><th>Certificates</th><th>Samples</th></tr></thead><tbody>{comparisons.map((item, index) => <tr key={item.record.record_id} className={index === 0 && item.price != null ? 'winner' : ''}><td>{value(item.record.payload, ['supplier_name', 'company_name']) || 'Supplier pending'}{index === 0 && item.price != null && <b>Lowest</b>}</td><td>{item.price ?? '—'} {value(item.record.payload, ['price_currency', 'currency'])}</td><td>{value(item.record.payload, ['moq']) || '—'}</td><td>{value(item.record.payload, ['lead_time']) || '—'}</td><td>{value(item.record.payload, ['payment_terms']) || '—'}</td><td>{value(item.record.payload, ['certificates', 'certifications']) || 'Not captured'}</td><td>{value(item.record.payload, ['sample_requirements', 'sample_status']) || 'Not captured'}</td></tr>)}</tbody></table></div></section><section className="procurement-panel"><div className="panel-head"><div><p className="eyebrow">WEEKLY LOWEST QUOTES</p><h4>Winning supplier by product</h4></div></div><div className="winner-list">{weeklyWinners.slice(0, 12).map((item) => <button key={`${item.week}-${item.record.record_id}`} onClick={() => onOpen(item.record)}><span><strong>{value(item.record.payload, ['name', 'product_name'])}</strong><small>Week of {item.week}</small></span><b>{item.price} {value(item.record.payload, ['price_currency', 'currency'])}</b><em>{value(item.record.payload, ['supplier_name', 'company_name']) || 'Supplier pending'}</em></button>)}{!weeklyWinners.length && <p className="muted">Add quoted prices to compare weekly supplier winners.</p>}</div></section></div>
    <div className="procurement-columns"><section className="procurement-panel"><div className="panel-head"><div><p className="eyebrow">SUPPLIER SCORECARD</p><h4>Commercial and sourcing readiness</h4></div></div><div className="scorecards">{visible.slice(0, 8).map((record) => <article key={record.record_id}><button onClick={() => onOpen(record)}><strong>{name(record)}</strong></button>{[['Pricing', value(record.payload, ['pricing_score', 'quoted_price'])], ['Quality', value(record.payload, ['quality_score'])], ['Response speed', value(record.payload, ['response_speed_score'])], ['Reliability', value(record.payload, ['reliability_score'])], ['Compliance', value(record.payload, ['compliance_score', 'certifications'])], ['Follow-up', value(record.payload, ['follow_up_status', 'priority'])]].map(([label, score]) => <div key={label}><span>{label}</span><b>{score || 'Not captured'}</b></div>)}</article>)}</div></section><section className="procurement-panel"><div className="panel-head"><div><p className="eyebrow">SUPPLIER TIMELINE</p><h4>Complete record history</h4></div></div><select value={timeline.supplier?.record_id ?? ''} onChange={(event) => setTimelineSupplier(event.target.value)}>{suppliers.map((record) => <option key={record.record_id} value={record.record_id}>{name(record)}</option>)}</select><div className="timeline">{timeline.records.map((record) => <button key={`${record.record_type}-${record.record_id}`} onClick={() => onOpen(record)}><time>{dateLabel(record.updated_at)}</time><span><strong>{record.record_type.replaceAll('_', ' ')}</strong><small>{name(record)}</small></span></button>)}{!timeline.records.length && <p className="muted">Choose a supplier to review their complete timeline.</p>}</div></section></div>
    <section className="procurement-panel audit-panel"><div><p className="eyebrow">TEAM CONTROLS & ACTIVITY AUDIT</p><h4>Assignments and decision accountability</h4><p className="muted">Desktop controls respect the signed-in team role. Every field change remains in the synchronized activity trail; final permission enforcement remains on the server.</p></div><div className="audit-list">{records.filter((record) => record.record_type === 'activity').slice(0, 8).map((record) => <button key={record.record_id} onClick={() => onOpen(record)}><span>{dateLabel(record.updated_at)}</span><strong>{value(record.payload, ['action', 'title', 'name']) || 'Team activity'}</strong><small>{value(record.payload, ['note', 'details', 'body'])}</small></button>)}{!records.some((record) => record.record_type === 'activity') && <p className="muted">Activity records will appear as the team captures and reviews suppliers.</p>}</div></section>
  </section>;
}

function Metric({ label, value, caption }: { label: string; value: number; caption: string }) {
  return <article className="metric"><span>{label}</span><strong>{value}</strong><small>{caption}</small></article>;
}
