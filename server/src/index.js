import 'dotenv/config';
import express from 'express';
import cors from 'cors';
import admin from 'firebase-admin';
import pg from 'pg';
import { readFileSync } from 'node:fs';

const { Pool } = pg;
if (!process.env.DATABASE_URL || (!process.env.FIREBASE_SERVICE_ACCOUNT_PATH && !process.env.FIREBASE_SERVICE_ACCOUNT_JSON)) {
  throw new Error('DATABASE_URL and a Firebase service account are required.');
}
const serviceAccount = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT_JSON ?? readFileSync(process.env.FIREBASE_SERVICE_ACCOUNT_PATH, 'utf8'));
admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
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
    req.user = await admin.auth().verifyIdToken(token);
    next();
  } catch (_) { res.status(401).json({ error: 'Invalid Firebase token' }); }
}

async function membership(teamId, uid) {
  const { rows } = await pool.query('SELECT role FROM team_members WHERE team_id=$1 AND firebase_uid=$2', [teamId, uid]);
  return rows[0]?.role;
}

app.get('/health', async (_, res) => { await pool.query('SELECT 1'); res.json({ ok: true }); });
app.get('/v1/teams', authenticate, async (req, res) => {
  const { rows } = await pool.query(`SELECT t.id, t.name, m.role FROM teams t
    JOIN team_members m ON m.team_id=t.id WHERE m.firebase_uid=$1 ORDER BY t.created_at`, [req.user.uid]);
  res.json({ teams: rows });
});
app.post('/v1/teams', authenticate, async (req, res) => {
  const name = String(req.body?.name ?? '').trim();
  if (!name) return res.status(400).json({ error: 'Team name is required' });
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const team = await client.query('INSERT INTO teams(name) VALUES($1) RETURNING id,name', [name]);
    await client.query('INSERT INTO team_members(team_id,firebase_uid,role) VALUES($1,$2,$3)', [team.rows[0].id, req.user.uid, 'admin']);
    await client.query('COMMIT');
    res.status(201).json({ ...team.rows[0], role: 'admin' });
  } catch (error) { await client.query('ROLLBACK'); throw error; } finally { client.release(); }
});
app.get('/v1/teams/:teamId/records', authenticate, async (req, res) => {
  const role = await membership(req.params.teamId, req.user.uid);
  if (!role) return res.status(403).json({ error: 'Team access denied' });
  const { rows } = await pool.query('SELECT record_type, record_id, payload, updated_at FROM team_records WHERE team_id=$1 ORDER BY updated_at DESC', [req.params.teamId]);
  res.json({ records: rows });
});
app.put('/v1/teams/:teamId/records/:type/:id', authenticate, async (req, res) => {
  const role = await membership(req.params.teamId, req.user.uid);
  if (!['admin', 'member'].includes(role)) return res.status(403).json({ error: 'Write access denied' });
  await pool.query(`INSERT INTO team_records(team_id,record_type,record_id,payload,updated_by) VALUES($1,$2,$3,$4,$5)
    ON CONFLICT(team_id,record_type,record_id) DO UPDATE SET payload=EXCLUDED.payload,updated_at=now(),updated_by=EXCLUDED.updated_by`,
    [req.params.teamId, req.params.type, req.params.id, req.body, req.user.uid]);
  res.status(204).end();
});
app.listen(process.env.PORT || 8080, () => console.log('Canton Fair API listening'));
