CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS teams (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS team_members (
  team_id UUID NOT NULL REFERENCES teams(id) ON DELETE CASCADE,
  firebase_uid TEXT NOT NULL,
  role TEXT NOT NULL CHECK (role IN ('admin', 'member', 'viewer')),
  PRIMARY KEY (team_id, firebase_uid)
);
CREATE TABLE IF NOT EXISTS team_records (
  team_id UUID NOT NULL REFERENCES teams(id) ON DELETE CASCADE,
  record_type TEXT NOT NULL,
  record_id TEXT NOT NULL,
  payload JSONB NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_by TEXT NOT NULL,
  PRIMARY KEY (team_id, record_type, record_id)
);
CREATE INDEX IF NOT EXISTS team_records_type_updated_idx ON team_records(team_id, record_type, updated_at DESC);
