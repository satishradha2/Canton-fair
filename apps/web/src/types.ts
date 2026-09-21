export type JsonRecord = Record<string, unknown>;

export interface Team {
  id: string;
  name: string;
  role: 'admin' | 'member' | string;
}

export interface TeamRecord {
  record_type: string;
  record_id: string;
  payload: JsonRecord;
  updated_at: string;
  version: number;
}

export type WorkspaceView =
  | 'overview'
  | 'suppliers'
  | 'products'
  | 'visits'
  | 'shortlist'
  | 'trips'
  | 'contacts'
  | 'followups'
  | 'activity'
  | 'procurement'
  | 'reports'
  | 'fieldTools'
  | 'routes'
  | 'categories';
