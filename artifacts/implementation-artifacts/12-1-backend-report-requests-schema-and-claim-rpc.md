# Story 12.1: Backend — report_requests schema + guarded UPDATE claim

Status: ready-for-dev
baseline_commit: 18ea107 (fenzit-be)

> **Implemented 2026-09-20.** Table + RLS + worker indexes shipped as designed
> (migration 48). Claim logic is a single guarded UPDATE (no stored procedure):
> `UPDATE report_requests SET status='generating', locked_until = <lease>,
> attempt_count = attempt_count + 1 WHERE id = ? AND tenant_id = <tenant> AND
> (status = 'queued' OR (status = 'generating' AND locked_until < now()))`.
> Atomic in Postgres, no RPC needed for exactly-once pickup. PT-SQLSTATE
> convention and RLS envelope stand.

## Story

As a report engine,
I want a `report_requests` state-machine table with a deny-by-default RLS
envelope and an atomic guarded UPDATE claim mechanism,
so that queued requests are picked up exactly once — a crashed worker can
never double-run a report and no client can ever touch another tenant's rows.

## Acceptance Criteria

1. **`report_requests` migration** — a new fenzit-be migration (applied via
   the Supabase MCP) creates the table:
   - **Given** the migration is applied,
     **When** inspecting the table,
     **Then** it carries exactly: `id` (uuid PK), `tenant_id` (FK tenants,
     not null), `requested_by` (FK users, not null), `report_type` (text,
     not null), `params` (jsonb, not null, CHECK-constrained to a JSON
     object — `jsonb_typeof(params) = 'object'`), `status` (text,
     CHECK `IN ('queued','generating','ready','failed')`, default
     `'queued'`), `locked_until` (timestamptz, nullable — the lease),
     `attempt_count` (int, not null, default 0), `r2_key` (text, unique,
     nullable — unique so lease recovery re-uploads to the same key),
     `file_size_bytes` (bigint, nullable), `error_code` (text, nullable),
     `created_at` (timestamptz, default `now()`), `completed_at`
     (timestamptz, nullable).
   - **Given** the table exists,
     **When** inspecting the indexes,
     **Then** there is a `(tenant_id, created_at DESC)` index (the history
     list's keyset scan, FR4) and a partial index on
     `status = 'queued'` (`WHERE status = 'queued'`) — the worker's poll
     query, FR7.
2. **Deny-by-default RLS** — **Given** the table is created,
     **When** RLS is enabled, **Then** no client role can read or write
     anything unless a policy explicitly allows it:
   - `SELECT` + `INSERT` policies for owner JWTs scoped by
     `tenant_id = (auth.jwt() ->> 'tenantId')::uuid` (same predicate as
     `customers` / `attachments`);
   - **no** client-facing `UPDATE` or `DELETE` policy at all — status
     transitions happen only through the service-role client (guarded UPDATE
     from the worker; user mutations never ride a user JWT).
3. **Guarded UPDATE claim (service-role only)** — **Given** the worker runs
     a claim via the Supabase service-role client **When** it executes the
     guarded UPDATE **Then** it performs the `queued → generating` transition
     in one atomic statement: `UPDATE report_requests SET status = 'generating',
     locked_until = now() + INTERVAL 'X seconds', attempt_count = attempt_count + 1
     WHERE id = ? AND tenant_id = ? AND (status = 'queued' OR (status = 'generating'
     AND locked_until < now()))`. Claim succeeds if one row is updated; zero rows
     updated means the request is already-claimed or terminal (developer checks
     affected rows; if zero, treat as conflict). Atomic in Postgres, no RPC needed.
4. **Already-claimed / terminal conflict** — **Given** the target row is
     `generating` with an unexpired lease, `ready`, or `failed`,
     **When** the guarded UPDATE runs against it,
     **Then** zero rows are updated (the WHERE predicate doesn't match). The
     worker checks affected rows: if zero, the request was already claimed or
     is terminal — the worker logs and skips (no retry). A row stranded
     `generating` past its `locked_until` lease **is re-claimable** (the WHERE
     predicate includes expired leases), so 12-3's crash recovery needs no
     schema change (FR8).
5. **Tenant isolation** — **Given** any caller,
     **When** the guarded UPDATE executes (service-role only),
     **Then** it never touches a row outside the specified `tenant_id` parameter;
     RLS on the table is the second layer of isolation (FR14).
6. **Service-role only, client-safe** — **Given** a client JWT (owner or technician),
     **When** they try to UPDATE `report_requests` directly,
     **Then** the UPDATE is blocked by RLS (no UPDATE policy exists). Only
     the service-role backend client can mutate the table (12-3 worker).
7. **Backend-only story, no app code** — **Given** this story merges,
     **When** reviewed, **Then** it ships only the schema migration (DB
     work through the Supabase MCP) plus docs; the `src/reports/` module,
     endpoints and worker land in 12-2/12-3. Additive backend change —
     merges/deploys before any fenzo-app story per the cross-repo ordering
     rule.

## Tasks / Subtasks

- [ ] Task 1: `report_requests` migration (AC: 1)
  - [ ] New migration file in
        `fenzit-be/supabase/migrations/` (next sequence number in the
        `YYYYMMDD00000N` convention) creating the table with all columns
        and constraints exactly as AC 1 — apply via the Supabase MCP, not
        the CLI.
  - [ ] CHECK constraints: `params` object check + `status` enum check.
  - [ ] Indexes: `(tenant_id, created_at DESC)`; partial
        `WHERE status = 'queued'`.
- [ ] Task 2: RLS (AC: 2, 5, 6)
  - [ ] `ENABLE ROW LEVEL SECURITY` on `report_requests` (deny-by-default —
        no permissive-by-accident policies).
  - [ ] Owner `SELECT` + `INSERT` policies using the
        `(auth.jwt() ->> 'tenantId')::uuid` predicate (copy the established
        pattern from `20260621000001_create_customers_table.sql`).
  - [ ] Deliberately **no** `UPDATE`/`DELETE` policy; note in the migration
        header comment why (worker mutates via service-role guarded UPDATE only).
- [ ] Task 3: Claim mechanism documentation (AC: 3, 4)
  - [ ] Migration header comment documents: the guarded UPDATE logic, lease
        semantics, how crashed workers recover (expired lease re-claim), and
        how the 12-3 worker checks affected rows to detect conflicts.
  - [ ] No RPC created (claim logic is backend application code in 12-3, not
        a stored procedure).
- [ ] Task 4: Verification via Supabase MCP (AC: 1, 2)
  - [ ] Inspect the applied table/columns/indexes; confirm the CHECKs and
        the partial index.
  - [ ] Confirm policies: only SELECT/INSERT for owner JWTs; RLS enabled.
  - [ ] Run security advisor and fix any flags.
- [ ] Task 5: Docs (small-modular rule: docs updated in the same change)
  - [ ] Migration/RPC header comments carry the state machine, lease and
        isolation contract (the 12-3 engine story reads these first).
  - [ ] No fenzit-be module docs describe reports yet — the migration
        header comment is the doc of record for this story.

## Dev Notes

### Repo and tooling facts

- Repo is **fenzit-be** (`workspace/core/backend/fenzit-be`); commit there,
  never in the meta-repo. Work on `main` (no branches), never commit or
  push without the user's explicit say-so.
- **All DB work goes through the Supabase MCP tools** (project convention):
  `apply_migration` for the DDL, `execute_sql` for verification queries,
  `list_tables` / `get_advisors` for post-change checks. Do not hand-roll
  psql/CLI paths.
- **bun only** in fenzit-be — no npm/yarn/pnpm; and per memory, fenzit-be
  has **no lockfile**: never generate or commit `bun.lock` there.
- Migration naming follows the existing
  `supabase/migrations/YYYYMMDD00000N_<snake_description>.sql` sequence
  (latest: `20260920000003_add_skill_constraints.sql`). **All report migrations 
  use this same YYYYMMDD-prefixed convention** (12-1 through 12-3); do not 
  switch to sequential numbering (48, 49, etc.) — keep the timestamp scheme 
  consistent across the entire epic.

### Guarded UPDATE pattern (claim logic is app code, not a stored procedure)

- The claim is a single guarded UPDATE executed from the worker (story 12-3):
  `UPDATE report_requests SET status = 'generating', locked_until = ...,
  attempt_count = ... WHERE id = ? AND tenant_id = ? AND (status = 'queued'
  OR (status = 'generating' AND locked_until < now()))`. Atomic in Postgres.
- Worker checks affected rows after the UPDATE: if zero rows updated, the
  request was already claimed or is terminal — the worker logs and skips.
- This approach keeps business logic in the backend application (12-3 worker)
  instead of stored procedures, per the user's direction.
- `supabase/migrations/20260621000001_create_customers_table.sql` — the
  RLS policy idiom to copy for SELECT/INSERT owner policies.

### State machine and lease facts

- The table is the queue (no broker exists in fenzit-be and the free tier
  cannot run one — addendum §2). Status transitions:
  `queued → generating → ready | failed`; terminal states are `ready` and
  `failed`.
- `locked_until` is the lease the worker (12-3) recovers from: claim
  stamps it; the poll loop re-claims rows whose lease expired. That is why
  the claim's eligibility predicate is
  `status = 'queued' OR (status = 'generating' AND locked_until < now())`
  — build it into the RPC now so 12-3's crash recovery is engine-side
  only. `attempt_count` rides along in the same statement; the max-attempts
  policy (default 3, `REPORT_MAX_ATTEMPTS`) lives in the worker, not the
  RPC.
- `r2_key` is unique + nullable so lease recovery re-uploads to the same
  deterministic key `{tenantId}/reports/{requestId}.pdf` (R2 orphan
  self-heals, FR7/FR8). The R2 key pattern itself is engine-side (12-3);
  this story only guarantees uniqueness.
- The terminal stamp and the `notifications` insert are a 12-3
  transaction — **not** this RPC's job. The claim RPC does exactly one
  transition.

### RLS discipline (backend-first)

- Deny-by-default is the requirement, not a style choice: enable RLS and
  write only the policies named in AC 2. No client-facing UPDATE/DELETE
  policy — the worker mutates via the service-role client (RLS bypassed),
  never through a user JWT.
- The Supabase security advisors run after DDL — check
  `get_advisors` (type: security) once the migration lands and fix anything
  it flags before calling the story done.

### Pre-launch freedom

- App/backend are not live (project memory): schema changes are free,
  no compat shims, no additive-old-shape dance. If the first migration
  draft is wrong, drop/redo it rather than layering fixes — but still keep
  each applied migration a clean, readable unit.

### Test timing (project rule)

Implement → **user confirms the feature works** → only then write tests →
then BMAD code review. For this DB-only story the confirmation is the user
sanity-checking the table/RPC through the Supabase MCP. Per the epics
coverage map (NFR7), the isolation suite (including the RPC-privilege
audit) and the crash-recovery tests belong to story 12-3 — **no test suites
are written in this story**, and none are written before the user confirms
the end-to-end feature on device.

### References

- [Source: artifacts/planning-artifacts/epics-reports.md — Story 12-1,
  FR11/FR12 rows in the FR Coverage Map] — the story definition and the
  12-1 → 12-2 → 12-3 ordering.
- [Source: artifacts/planning-artifacts/prds/prd-fenzo-reports-2026-09-18/prd.md
  §5.4 FR-7] — column list, CHECK-constrained params, status enum,
  unique nullable `r2_key`, claim RPC requirements (SECURITY DEFINER,
  JWT-resolved tenant, EXECUTE revoked, `locked_until`, PT SQLSTATE).
- [Source: artifacts/planning-artifacts/prds/prd-fenzo-reports-2026-09-18/addendum.md
  §2, §3] — state-machine-on-a-table rationale; RPC convention
  (`PT<http-status>` SQLSTATE → service-layer mapping, see
  `confirm_attachment`); notification fanout is a later story.
- [Source: fenzit-be supabase/migrations/20260621000004_rpc_update_job_with_log.sql,
  20260621000006_rpc_advance_workflow_step.sql] — the PT SQLSTATE guard
  idiom.
- [Source: fenzit-be supabase/migrations/20260621000009_rpc_confirm_attachment.sql]
  — SECURITY DEFINER skeleton, header-comment discipline, service-layer
  mapping precedent.
- [Source: fenzit-be supabase/migrations/20260621000001_create_customers_table.sql]
  — the RLS owner-policy idiom (`auth.jwt() ->> 'tenantId'`) to copy.