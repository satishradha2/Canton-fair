import { createClient } from '@supabase/supabase-js';
import type { JsonRecord, Team, TeamRecord } from './types';

const url = import.meta.env.VITE_SUPABASE_URL;
const anonKey = import.meta.env.VITE_SUPABASE_ANON_KEY;

export const supabase = url && anonKey ? createClient(url, anonKey) : null;

function client() {
  if (!supabase) throw new Error('Supabase is not configured.');
  return supabase;
}

export async function loadTeams(): Promise<Team[]> {
  const { data, error } = await client()
    .from('team_members')
    .select('team_id, role, teams(name)')
    .order('team_id');
  if (error) throw new Error(error.message);
  return (data ?? []).map((row) => {
    const team = Array.isArray(row.teams) ? row.teams[0] : row.teams;
    return {
      id: row.team_id,
      name: typeof team?.name === 'string' ? team.name : row.team_id,
      role: row.role,
    };
  });
}

export async function loadRecords(teamId: string): Promise<TeamRecord[]> {
  const { data, error } = await client()
    .from('team_records')
    .select('record_type, record_id, payload, updated_at, version')
    .eq('team_id', teamId)
    .order('updated_at', { ascending: false });
  if (error) throw new Error(error.message);
  return (data ?? []).map((row) => ({
    record_type: row.record_type,
    record_id: row.record_id,
    payload: row.payload as JsonRecord,
    updated_at: row.updated_at,
    version: Number(row.version),
  }));
}

export async function updateRecord(
  teamId: string,
  record: TeamRecord,
  changes: JsonRecord,
): Promise<TeamRecord> {
  const payload = { ...record.payload, ...changes };
  const { data, error } = await client().rpc('upsert_team_record', {
    target_team: teamId,
    target_record_type: record.record_type,
    target_record_id: record.record_id,
    target_payload: payload,
    expected_version: record.version,
  });
  if (error) {
    if (error.message.includes('sync_conflict')) {
      throw new Error('This record changed elsewhere. Refresh before saving.');
    }
    throw new Error(error.message);
  }
  const result = Array.isArray(data) ? data[0] : data;
  return {
    ...record,
    payload,
    version: Number(result?.version ?? record.version + 1),
    updated_at: String(result?.updated_at ?? new Date().toISOString()),
  };
}

export const isConfigured = () => Boolean(supabase);