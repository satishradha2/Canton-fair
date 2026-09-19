import 'dotenv/config';
import express from 'express';
import cors from 'cors';
import { createClient } from '@supabase/supabase-js';
import pg from 'pg';

const { Pool } = pg;
if (!process.env.DATABASE_URL || !process.env.SUPABASE_URL || !process.env.SUPABASE_SERVICE_ROLE_KEY) {
  throw new Error('DATABASE_URL, SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required.');
}
const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY, {
  auth: { autoRefreshToken: false, persistSession: false },
});
const databaseUrl = new URL(process.env.DATABASE_URL);
const isLocalDatabase = ['localhost', '127.0.0.1', '::1'].includes(databaseUrl.hostname);
const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: isLocalDatabase ? false : { rejectUnauthorized: false },
});
const app = express();
app.use(cors());
app.use(express.json({ limit: '2mb' }));

async function authenticate(req, res, next) {
  try {
    const token = req.headers.authorization?.replace(/^Bearer\s+/i, '');
    if (!token) return res.status(401).json({ error: 'Missing bearer token' });
    const { data, error } = await supabase.auth.getUser(token);
    if (error || !data.user) throw new Error('Invalid Supabase token');
    req.user = data.user;
    next();
  } catch (_) { res.status(401).json({ error: 'Invalid Supabase token' }); }
}

async function membership(teamId, uid) {
  const { rows } = await pool.query('SELECT role FROM team_members WHERE team_id=$1 AND user_id=$2', [teamId, uid]);
  return rows[0]?.role;
}

app.get('/health', async (_, res) => { await pool.query('SELECT 1'); res.json({ ok: true }); });
app.get('/v1/teams', authenticate, async (req, res) => {
  const { rows } = await pool.query(`SELECT t.id, t.name, m.role FROM teams t
    JOIN team_members m ON m.team_id=t.id WHERE m.user_id=$1 ORDER BY t.created_at`, [req.user.id]);
  res.json({ teams: rows });
});
app.post('/v1/teams', authenticate, async (req, res) => {
  const name = String(req.body?.name ?? '').trim();
  if (!name) return res.status(400).json({ error: 'Team name is required' });
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const team = await client.query('INSERT INTO teams(name) VALUES($1) RETURNING id,name', [name]);
    await client.query('INSERT INTO team_members(team_id,user_id,role) VALUES($1,$2,$3)', [team.rows[0].id, req.user.id, 'admin']);
    await client.query('COMMIT');
    res.status(201).json({ ...team.rows[0], role: 'admin' });
  } catch (error) { await client.query('ROLLBACK'); throw error; } finally { client.release(); }
});
app.get('/v1/teams/:teamId/records', authenticate, async (req, res) => {
  const role = await membership(req.params.teamId, req.user.id);
  if (!role) return res.status(403).json({ error: 'Team access denied' });
  const { rows } = await pool.query('SELECT record_type, record_id, payload, updated_at FROM team_records WHERE team_id=$1 ORDER BY updated_at DESC', [req.params.teamId]);
  res.json({ records: rows });
});
app.put('/v1/teams/:teamId/records/:type/:id', authenticate, async (req, res) => {
  const role = await membership(req.params.teamId, req.user.id);
  if (!['admin', 'member'].includes(role)) return res.status(403).json({ error: 'Write access denied' });
  await pool.query(`INSERT INTO team_records(team_id,record_type,record_id,payload,updated_by) VALUES($1,$2,$3,$4,$5)
    ON CONFLICT(team_id,record_type,record_id) DO UPDATE SET payload=EXCLUDED.payload,updated_at=now(),updated_by=EXCLUDED.updated_by`,
    [req.params.teamId, req.params.type, req.params.id, req.body, req.user.id]);
  res.status(204).end();
});
app.patch('/v1/teams/:teamId/records/:type/:id', authenticate, async (req, res) => {
  const role = await membership(req.params.teamId, req.user.id);
  if (!['admin', 'member'].includes(role)) return res.status(403).json({ error: 'Write access denied' });
  const changes = req.body?.changes;
  if (!changes || Array.isArray(changes) || typeof changes !== 'object') {
    return res.status(400).json({ error: 'A changes object is required' });
  }
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const existing = await client.query(`SELECT payload,updated_at FROM team_records
      WHERE team_id=$1 AND record_type=$2 AND record_id=$3 FOR UPDATE`,
      [req.params.teamId, req.params.type, req.params.id]);
    if (!existing.rows[0]) {
      await client.query('ROLLBACK');
      return res.status(404).json({ error: 'Record not found' });
    }
    const expectedUpdatedAt = req.body?.expectedUpdatedAt;
    if (expectedUpdatedAt && new Date(expectedUpdatedAt).getTime() !== new Date(existing.rows[0].updated_at).getTime()) {
      await client.query('ROLLBACK');
      return res.status(409).json({ error: 'This record changed elsewhere. Refresh before saving.' });
    }
    const updated = await client.query(`UPDATE team_records
      SET payload=$1,updated_at=now(),updated_by=$2
      WHERE team_id=$3 AND record_type=$4 AND record_id=$5
      RETURNING record_type,record_id,payload,updated_at`,
      [{ ...(existing.rows[0].payload ?? {}), ...changes }, req.user.id,
        req.params.teamId, req.params.type, req.params.id]);
    await client.query('COMMIT');
    res.json(updated.rows[0]);
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally { client.release(); }
});
app.listen(process.env.PORT || 8080, () => console.log('Canton Fair API listening'));
