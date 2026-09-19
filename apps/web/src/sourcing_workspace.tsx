import { useMemo, useState } from 'react';
import type { TeamRecord } from './types';

type Mode = 'suppliers' | 'products' | 'shortlist';

const text = (record: TeamRecord, keys: string[]) => {
  for (const key of keys) {
    const value = record.payload[key];
    if (typeof value === 'string' && value.trim()) return value.trim();
    if (typeof value === 'number') return String(value);
  }
  return '';
};

const productRecord = (record: TeamRecord) => record.record_type === 'product';
const supplierRecord = (record: TeamRecord) =>
  record.record_type === 'supplier' || record.record_type === 'exhibitor';
const shortlisted = (record: TeamRecord) =>
  record.payload.shortlisted === true || record.payload.shortlisted === 1 || record.payload.shortlisted === '1';

export function SourcingWorkspace({
  mode, records, query, onOpen,
}: {
  mode: Mode;
  records: TeamRecord[];
  query: string;
  onOpen: (record: TeamRecord) => void;
}) {
  const [filter, setFilter] = useState('');
  const [selectedProducts, setSelectedProducts] = useState<string[]>([]);
  const suppliers = useMemo(() => records.filter(supplierRecord), [records]);
  const supplierNames = useMemo(() => new Map(suppliers.map((record) => [
    record.record_id,
    text(record, ['name', 'supplier_name', 'company_name']) || 'Unnamed supplier',
  ])), [suppliers]);
  const categories = useMemo(() => Array.from(new Set(records.filter(productRecord)
    .map((record) => text(record, ['category'])).filter(Boolean))).sort(), [records]);
  const halls = useMemo(() => Array.from(new Set(suppliers
    .map((record) => text(record, ['hall', 'hall_number'])).filter(Boolean))).sort(), [suppliers]);
  const normalizedQuery = query.trim().toLowerCase();
  const visibleSuppliers = suppliers.filter((record) => {
    const haystack = `${text(record, ['name', 'supplier_name', 'company_name'])} ${text(record, ['hall', 'hall_number'])} ${text(record, ['booth'])} ${text(record, ['category', 'country'])}`.toLowerCase();
    return (!filter || filter === text(record, ['hall', 'hall_number'])) && haystack.includes(normalizedQuery);
  });
  const products = records.filter(productRecord).filter((record) => {
    if (mode === 'shortlist' && !shortlisted(record)) return false;
    const haystack = `${text(record, ['name', 'product_name'])} ${text(record, ['category'])} ${text(record, ['model_code'])} ${text(record, ['specs'])}`.toLowerCase();
    return (!filter || filter === text(record, ['category'])) && haystack.includes(normalizedQuery);
  });
  const selected = products.filter((record) => selectedProducts.includes(record.record_id));
  const toggleProduct = (record: TeamRecord) => setSelectedProducts((current) =>
    current.includes(record.record_id)
      ? current.filter((id) => id !== record.record_id)
      : current.length < 3 ? [...current, record.record_id] : current,
  );

  if (mode === 'suppliers') return <section className="sourcing-module">
    <div className="module-toolbar"><div><strong>{visibleSuppliers.length} suppliers</strong><span> Filter by hall, then open a supplier to review its synchronized record.</span></div><select value={filter} onChange={(event) => setFilter(event.target.value)}><option value="">All halls</option>{halls.map((hall) => <option key={hall}>{hall}</option>)}</select></div>
    <div className="sourcing-grid supplier-grid"><div className="grid-head"><span>Supplier</span><span>Location</span><span>Category</span><span>Contact</span><span /></div>{visibleSuppliers.map((record) => <button className="grid-row" key={record.record_id} onClick={() => onOpen(record)}><span><strong>{text(record, ['name', 'supplier_name', 'company_name']) || 'Unnamed supplier'}</strong><small>{text(record, ['legal_company_name', 'country']) || 'Supplier profile'}</small></span><span>{[text(record, ['hall', 'hall_number']), text(record, ['booth'])].filter(Boolean).join(' / ') || 'Not recorded'}</span><span>{text(record, ['category', 'industry']) || 'Unclassified'}</span><span>{text(record, ['contact_name', 'email', 'phone']) || 'No contact captured'}</span><span>Open ›</span></button>)}{visibleSuppliers.length === 0 && <Empty label="No suppliers match this hall or search." />}</div>
  </section>;

  return <section className="sourcing-module">
    <div className="module-toolbar"><div><strong>{products.length} {mode === 'shortlist' ? 'shortlisted' : 'captured'} products</strong><span> Compare up to three products without changing source records.</span></div><select value={filter} onChange={(event) => setFilter(event.target.value)}><option value="">All categories</option>{categories.map((category) => <option key={category}>{category}</option>)}</select></div>
    {selected.length > 0 && <section className="comparison-tray"><div><p className="eyebrow">COMPARISON SET</p><strong>{selected.length} product{selected.length === 1 ? '' : 's'} selected</strong><small>Select up to three items to compare commercial facts.</small></div>{selected.map((record) => <article key={record.record_id}><strong>{text(record, ['name', 'product_name']) || 'Unnamed product'}</strong><span>{text(record, ['quoted_price']) || 'No price'} {text(record, ['price_currency'])}</span><span>MOQ {text(record, ['moq']) || '—'} · {text(record, ['lead_time']) || 'Lead time unknown'}</span></article>)}</section>}
    <div className="sourcing-grid product-grid"><div className="grid-head"><span>Product</span><span>Supplier</span><span>Commercial terms</span><span>Category</span><span /></div>{products.map((record) => { const supplierId = text(record, ['supplier_record_id', 'exhibitor_record_id']); const supplier = supplierNames.get(supplierId) || text(record, ['supplier_name', 'company_name']) || 'Supplier not linked'; const productName = text(record, ['name', 'product_name']) || 'Unnamed product'; return <div className="grid-row" key={record.record_id}><label className="compare-check"><input type="checkbox" checked={selectedProducts.includes(record.record_id)} onChange={() => toggleProduct(record)} disabled={!selectedProducts.includes(record.record_id) && selectedProducts.length >= 3} /><span className="sr-only">Compare {productName}</span></label><button className="row-open" onClick={() => onOpen(record)}><strong>{productName}</strong><small>{text(record, ['model_code']) || 'No model/SKU'}</small></button><span className={supplier === 'Supplier not linked' ? 'warning-text' : ''}>{supplier}</span><span>{text(record, ['quoted_price']) || 'Price pending'} {text(record, ['price_currency'])}<small>MOQ {text(record, ['moq']) || '—'} · {text(record, ['lead_time']) || 'Lead time pending'}</small></span><span>{text(record, ['category']) || 'Unclassified'}{shortlisted(record) && <b>Shortlisted</b>}</span><button className="open-link" onClick={() => onOpen(record)}>Open ›</button></div>; })}{products.length === 0 && <Empty label="No products match this category or search." />}</div>
  </section>;
}

function Empty({ label }: { label: string }) {
  return <div className="empty"><strong>{label}</strong><span>Field captures will appear after mobile sync completes.</span></div>;
}
