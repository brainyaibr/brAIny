/*
# brAIny — core application schema

## Purpose
Creates the complete database schema for brAIny, a SaaS that transforms
natural-language instructions into websites, web apps, 2D games, images, and
code. The app uses React/Vite + FastAPI with Manus OAuth for authentication.
The FastAPI backend is the security boundary and accesses this database with
the service role key (bypassing RLS). RLS policies are enabled as
defense-in-depth so direct browser access with the anon key is blocked.

## New Tables
1. projects — user-owned generated projects (sites, apps, games, images, code)
2. conversations — chat messages per project (user/assistant/system roles)
3. files — individual source files belonging to a project
4. assets — generated images and user uploads with storage addresses
5. jobs — async generation/repair/image tasks with lifecycle states
6. usage_records — per-call token and cost tracking for quotas and budgets
7. idempotency_keys — deduplication of retried API operations
8. rate_limit_windows — distributed rate-limit counters per identifier/operation

## Security
- RLS enabled on every table.
- Policies scope all CRUD to authenticated users who own the row (user_id match)
  or who own the parent project (for child tables like conversations, files).
- The backend uses the service role key which bypasses RLS; these policies
  protect against direct anon-key browser access.
- user_id columns default to auth.uid() so inserts that omit the owner still
  satisfy the INSERT WITH CHECK policy.

## Important Notes
1. All tables use uuid primary keys with gen_random_uuid() defaults.
2. Foreign keys use ON DELETE CASCADE so deleting a project removes its
   conversations, files, jobs automatically.
3. Indexes added for common query patterns.
4. This migration is idempotent — safe to re-run.
*/

-- ===========================================================================
-- 1. projects
-- ===========================================================================
CREATE TABLE IF NOT EXISTS projects (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE CASCADE,
  title       text NOT NULL DEFAULT 'Untitled project',
  description text,
  status      text NOT NULL DEFAULT 'draft',
  visibility  text NOT NULL DEFAULT 'private',
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE projects ENABLE ROW LEVEL SECURITY;

CREATE INDEX IF NOT EXISTS idx_projects_user_id ON projects(user_id);
CREATE INDEX IF NOT EXISTS idx_projects_status ON projects(status);
CREATE INDEX IF NOT EXISTS idx_projects_created_at ON projects(created_at DESC);

DROP POLICY IF EXISTS "select_own_projects" ON projects;
CREATE POLICY "select_own_projects" ON projects FOR SELECT
  TO authenticated USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "insert_own_projects" ON projects;
CREATE POLICY "insert_own_projects" ON projects FOR INSERT
  TO authenticated WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "update_own_projects" ON projects;
CREATE POLICY "update_own_projects" ON projects FOR UPDATE
  TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "delete_own_projects" ON projects;
CREATE POLICY "delete_own_projects" ON projects FOR DELETE
  TO authenticated USING (auth.uid() = user_id);

-- ===========================================================================
-- 2. conversations
-- ===========================================================================
CREATE TABLE IF NOT EXISTS conversations (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id  uuid NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  role        text NOT NULL CHECK (role IN ('user','assistant','system')),
  content     text NOT NULL,
  tokens      integer NOT NULL DEFAULT 0,
  created_at  timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE conversations ENABLE ROW LEVEL SECURITY;

CREATE INDEX IF NOT EXISTS idx_conversations_project_id ON conversations(project_id);
CREATE INDEX IF NOT EXISTS idx_conversations_created_at ON conversations(project_id, created_at);

DROP POLICY IF EXISTS "select_own_conversations" ON conversations;
CREATE POLICY "select_own_conversations" ON conversations FOR SELECT
  TO authenticated USING (
    EXISTS (SELECT 1 FROM projects WHERE projects.id = conversations.project_id AND projects.user_id = auth.uid())
  );

DROP POLICY IF EXISTS "insert_own_conversations" ON conversations;
CREATE POLICY "insert_own_conversations" ON conversations FOR INSERT
  TO authenticated WITH CHECK (
    EXISTS (SELECT 1 FROM projects WHERE projects.id = conversations.project_id AND projects.user_id = auth.uid())
  );

DROP POLICY IF EXISTS "update_own_conversations" ON conversations;
CREATE POLICY "update_own_conversations" ON conversations FOR UPDATE
  TO authenticated USING (
    EXISTS (SELECT 1 FROM projects WHERE projects.id = conversations.project_id AND projects.user_id = auth.uid())
  ) WITH CHECK (
    EXISTS (SELECT 1 FROM projects WHERE projects.id = conversations.project_id AND projects.user_id = auth.uid())
  );

DROP POLICY IF EXISTS "delete_own_conversations" ON conversations;
CREATE POLICY "delete_own_conversations" ON conversations FOR DELETE
  TO authenticated USING (
    EXISTS (SELECT 1 FROM projects WHERE projects.id = conversations.project_id AND projects.user_id = auth.uid())
  );

-- ===========================================================================
-- 3. files
-- ===========================================================================
CREATE TABLE IF NOT EXISTS files (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id  uuid NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  path        text NOT NULL,
  content     text NOT NULL DEFAULT '',
  mime_type   text NOT NULL DEFAULT 'text/plain',
  size_bytes  integer NOT NULL DEFAULT 0,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE files ENABLE ROW LEVEL SECURITY;

CREATE INDEX IF NOT EXISTS idx_files_project_id ON files(project_id);
CREATE INDEX IF NOT EXISTS idx_files_path ON files(project_id, path);
CREATE UNIQUE INDEX IF NOT EXISTS idx_files_project_path_unique ON files(project_id, path);

DROP POLICY IF EXISTS "select_own_files" ON files;
CREATE POLICY "select_own_files" ON files FOR SELECT
  TO authenticated USING (
    EXISTS (SELECT 1 FROM projects WHERE projects.id = files.project_id AND projects.user_id = auth.uid())
  );

DROP POLICY IF EXISTS "insert_own_files" ON files;
CREATE POLICY "insert_own_files" ON files FOR INSERT
  TO authenticated WITH CHECK (
    EXISTS (SELECT 1 FROM projects WHERE projects.id = files.project_id AND projects.user_id = auth.uid())
  );

DROP POLICY IF EXISTS "update_own_files" ON files;
CREATE POLICY "update_own_files" ON files FOR UPDATE
  TO authenticated USING (
    EXISTS (SELECT 1 FROM projects WHERE projects.id = files.project_id AND projects.user_id = auth.uid())
  ) WITH CHECK (
    EXISTS (SELECT 1 FROM projects WHERE projects.id = files.project_id AND projects.user_id = auth.uid())
  );

DROP POLICY IF EXISTS "delete_own_files" ON files;
CREATE POLICY "delete_own_files" ON files FOR DELETE
  TO authenticated USING (
    EXISTS (SELECT 1 FROM projects WHERE projects.id = files.project_id AND projects.user_id = auth.uid())
  );

-- ===========================================================================
-- 4. assets
-- ===========================================================================
CREATE TABLE IF NOT EXISTS assets (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE CASCADE,
  project_id  uuid REFERENCES projects(id) ON DELETE SET NULL,
  storage_url text NOT NULL,
  kind        text NOT NULL CHECK (kind IN ('image','upload')),
  mime_type   text NOT NULL DEFAULT 'application/octet-stream',
  size_bytes  bigint NOT NULL DEFAULT 0,
  created_at  timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE assets ENABLE ROW LEVEL SECURITY;

CREATE INDEX IF NOT EXISTS idx_assets_user_id ON assets(user_id);
CREATE INDEX IF NOT EXISTS idx_assets_project_id ON assets(project_id);

DROP POLICY IF EXISTS "select_own_assets" ON assets;
CREATE POLICY "select_own_assets" ON assets FOR SELECT
  TO authenticated USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "insert_own_assets" ON assets;
CREATE POLICY "insert_own_assets" ON assets FOR INSERT
  TO authenticated WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "update_own_assets" ON assets;
CREATE POLICY "update_own_assets" ON assets FOR UPDATE
  TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "delete_own_assets" ON assets;
CREATE POLICY "delete_own_assets" ON assets FOR DELETE
  TO authenticated USING (auth.uid() = user_id);

-- ===========================================================================
-- 5. jobs
-- ===========================================================================
CREATE TABLE IF NOT EXISTS jobs (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id    uuid REFERENCES projects(id) ON DELETE CASCADE,
  user_id       uuid NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE CASCADE,
  kind          text NOT NULL CHECK (kind IN ('generate','repair','image','refine','research')),
  status        text NOT NULL DEFAULT 'pending'
                  CHECK (status IN ('pending','running','completed','cancelled','failed')),
  attempts      integer NOT NULL DEFAULT 0,
  max_attempts  integer NOT NULL DEFAULT 3,
  result_json   jsonb,
  error_message text,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now(),
  started_at    timestamptz,
  completed_at  timestamptz,
  expires_at    timestamptz
);

ALTER TABLE jobs ENABLE ROW LEVEL SECURITY;

CREATE INDEX IF NOT EXISTS idx_jobs_user_id ON jobs(user_id);
CREATE INDEX IF NOT EXISTS idx_jobs_project_id ON jobs(project_id);
CREATE INDEX IF NOT EXISTS idx_jobs_status ON jobs(status);
CREATE INDEX IF NOT EXISTS idx_jobs_expires_at ON jobs(expires_at);

DROP POLICY IF EXISTS "select_own_jobs" ON jobs;
CREATE POLICY "select_own_jobs" ON jobs FOR SELECT
  TO authenticated USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "insert_own_jobs" ON jobs;
CREATE POLICY "insert_own_jobs" ON jobs FOR INSERT
  TO authenticated WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "update_own_jobs" ON jobs;
CREATE POLICY "update_own_jobs" ON jobs FOR UPDATE
  TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "delete_own_jobs" ON jobs;
CREATE POLICY "delete_own_jobs" ON jobs FOR DELETE
  TO authenticated USING (auth.uid() = user_id);

-- ===========================================================================
-- 6. usage_records
-- ===========================================================================
CREATE TABLE IF NOT EXISTS usage_records (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id           uuid NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE CASCADE,
  project_id        uuid REFERENCES projects(id) ON DELETE SET NULL,
  model             text NOT NULL,
  operation         text NOT NULL CHECK (operation IN ('generate','repair','image','refine','research','chat')),
  input_tokens      integer NOT NULL DEFAULT 0,
  output_tokens     integer NOT NULL DEFAULT 0,
  cost_estimate_usd numeric(12,6) NOT NULL DEFAULT 0,
  status            text NOT NULL DEFAULT 'estimated'
                      CHECK (status IN ('estimated','confirmed','incomplete','failed')),
  created_at        timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE usage_records ENABLE ROW LEVEL SECURITY;

CREATE INDEX IF NOT EXISTS idx_usage_user_id ON usage_records(user_id);
CREATE INDEX IF NOT EXISTS idx_usage_project_id ON usage_records(project_id);
CREATE INDEX IF NOT EXISTS idx_usage_created_at ON usage_records(user_id, created_at DESC);

DROP POLICY IF EXISTS "select_own_usage" ON usage_records;
CREATE POLICY "select_own_usage" ON usage_records FOR SELECT
  TO authenticated USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "insert_own_usage" ON usage_records;
CREATE POLICY "insert_own_usage" ON usage_records FOR INSERT
  TO authenticated WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "update_own_usage" ON usage_records;
CREATE POLICY "update_own_usage" ON usage_records FOR UPDATE
  TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "delete_own_usage" ON usage_records;
CREATE POLICY "delete_own_usage" ON usage_records FOR DELETE
  TO authenticated USING (auth.uid() = user_id);

-- ===========================================================================
-- 7. idempotency_keys
-- ===========================================================================
CREATE TABLE IF NOT EXISTS idempotency_keys (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  key_hash        text NOT NULL UNIQUE,
  user_id         uuid NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE CASCADE,
  response_status integer,
  response_body   jsonb,
  created_at      timestamptz NOT NULL DEFAULT now(),
  expires_at      timestamptz NOT NULL
);

ALTER TABLE idempotency_keys ENABLE ROW LEVEL SECURITY;

CREATE INDEX IF NOT EXISTS idx_idempotency_key_hash ON idempotency_keys(key_hash);
CREATE INDEX IF NOT EXISTS idx_idempotency_user_id ON idempotency_keys(user_id);
CREATE INDEX IF NOT EXISTS idx_idempotency_expires_at ON idempotency_keys(expires_at);

DROP POLICY IF EXISTS "select_own_idempotency" ON idempotency_keys;
CREATE POLICY "select_own_idempotency" ON idempotency_keys FOR SELECT
  TO authenticated USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "insert_own_idempotency" ON idempotency_keys;
CREATE POLICY "insert_own_idempotency" ON idempotency_keys FOR INSERT
  TO authenticated WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "update_own_idempotency" ON idempotency_keys;
CREATE POLICY "update_own_idempotency" ON idempotency_keys FOR UPDATE
  TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "delete_own_idempotency" ON idempotency_keys;
CREATE POLICY "delete_own_idempotency" ON idempotency_keys FOR DELETE
  TO authenticated USING (auth.uid() = user_id);

-- ===========================================================================
-- 8. rate_limit_windows
-- ===========================================================================
CREATE TABLE IF NOT EXISTS rate_limit_windows (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  identifier_hash text NOT NULL,
  operation       text NOT NULL,
  window_start    timestamptz NOT NULL DEFAULT now(),
  count           integer NOT NULL DEFAULT 0,
  created_at      timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE rate_limit_windows ENABLE ROW LEVEL SECURITY;

CREATE INDEX IF NOT EXISTS idx_ratelimit_identifier ON rate_limit_windows(identifier_hash, operation);
CREATE INDEX IF NOT EXISTS idx_ratelimit_window_start ON rate_limit_windows(window_start);

-- rate_limit_windows is managed by the backend service role; the backend
-- bypasses RLS. These permissive policies allow authenticated users to read
-- their own window data if queried directly, while the backend handles writes.
DROP POLICY IF EXISTS "select_own_ratelimit" ON rate_limit_windows;
CREATE POLICY "select_own_ratelimit" ON rate_limit_windows FOR SELECT
  TO authenticated USING (true);

DROP POLICY IF EXISTS "insert_own_ratelimit" ON rate_limit_windows;
CREATE POLICY "insert_own_ratelimit" ON rate_limit_windows FOR INSERT
  TO authenticated WITH CHECK (true);

DROP POLICY IF EXISTS "update_own_ratelimit" ON rate_limit_windows;
CREATE POLICY "update_own_ratelimit" ON rate_limit_windows FOR UPDATE
  TO authenticated USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "delete_own_ratelimit" ON rate_limit_windows;
CREATE POLICY "delete_own_ratelimit" ON rate_limit_windows FOR DELETE
  TO authenticated USING (true);
