import { useMemo, useState } from 'react';
import type { TeamRecord } from './types';

type EvidenceKind = 'visit' | 'contact' | 'meeting' | 'recording' | 'attachment' | 'activity' | 'other';

const labels: Record<EvidenceKind, string> = {
  visit: 'Visits', contact: 'Contacts', meeting: 'Meetings', recording: 'Recordings',
  attachment: 'Attachments', activity: 'Activities', other: 'Other evidence',
};

function kindOf(record: TeamRecord): EvidenceKind {
  const type = record.record_type.toLowerCase();
  if (type === 'recording') return 'recording';
  if (type === 'attachment') return 'attachment';
  if (type === 'contact') return 'contact';
  if (type === 'meeting') return 'meeting';
  if (type === 'activity') return 'activity';
  if (type === 'visit_session' || type === 'visit') return 'visit';
  return 'other';
}

function field(record: TeamRecord, keys: string[]) {
  for (const key of keys) {
    const value = record.payload[key];
    if (typeof value === 'string' && value.trim()) return value.trim();
    if (typeof value === 'number') return String(value);
  }
  return '';
}

function title(record: TeamRecord, kind: EvidenceKind) {
  return field(record, ['title', 'name', 'contact_name', 'subject', 'file_name', 'supplier_name']) || labels[kind];
}

function summary(record: TeamRecord, kind: EvidenceKind) {
  const value = field(record, ['summary', 'notes', 'body', 'transcript', 'email', 'phone', 'file_name']);
  if (value) return value.length > 150 ? `${value.slice(0, 147)}...` : value;
  return `${labels[kind]} captured from the field.`;
}

export function VisitEvidenceWorkspace({
  records, query, onOpen,
}: {
  records: TeamRecord[];
  query: string;
  onOpen: (record: TeamRecord) => void;
}) {
  const [filter, setFilter] = useState<EvidenceKind | 'all'>('all');
  const evidence = useMemo(() => records.filter((record) => {
    const kind = kindOf(record);
    if (kind === 'other') return false;
    if (filter !== 'all' && filter !== kind) return false;
    const haystack = `${record.record_type} ${JSON.stringify(record.payload)}`.toLowerCase();
    return haystack.includes(query.trim().toLowerCase());
  }), [filter, query, records]);
  const counts = useMemo(() => records.reduce<Record<EvidenceKind, number>>((total, record) => {
    const kind = kindOf(record);
    if (kind !== 'other') total[kind] += 1;
    return total;
  }, { visit: 0, contact: 0, meeting: 0, recording: 0, attachment: 0, activity: 0, other: 0 }), [records]);

  return <section className="evidence-module">
    <header className="evidence-head"><div><p className="eyebrow">FIELD EVIDENCE REVIEW</p><h3>Conversations and visit proof</h3><p>Review evidence captured by the team without changing original mobile records.</p></div><div className="evidence-total"><strong>{evidence.length}</strong><span>matching items</span></div></header>
    <div className="evidence-filters"><button className={filter === 'all' ? 'active' : ''} onClick={() => setFilter('all')}>All <b>{Object.values(counts).reduce((sum, count) => sum + count, 0)}</b></button>{(Object.keys(labels) as EvidenceKind[]).filter((kind) => kind !== 'other').map((kind) => <button key={kind} className={filter === kind ? 'active' : ''} onClick={() => setFilter(kind)}>{labels[kind]} <b>{counts[kind]}</b></button>)}</div>
    <div className="evidence-list">{evidence.map((record) => { const kind = kindOf(record); return <button className="evidence-item" key={`${record.record_type}:${record.record_id}`} onClick={() => onOpen(record)}><span className={`evidence-icon ${kind}`}>{kind.slice(0, 1).toUpperCase()}</span><span className="evidence-copy"><strong>{title(record, kind)}</strong><small>{summary(record, kind)}</small></span><span className="evidence-meta"><em>{labels[kind]}</em><small>{new Date(record.updated_at).toLocaleDateString()}</small></span><span>›</span></button>; })}{evidence.length === 0 && <div className="empty"><strong>No visit evidence matches the current filter.</strong><span>New mobile captures will appear after team sync completes.</span></div>}</div>
  </section>;
}
