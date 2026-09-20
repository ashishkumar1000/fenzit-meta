# Story 12.3: Backend — generation engine + in-process worker

Status: ready-for-dev
baseline_commit: 18ea107 (fenzit-be) + the staged 12-1/12-2 work on top of it
(migrations 48–51 + the `src/reports/` module, uncommitted)

> **Implemented 2026-09-20.** Migration 52 applied (`notifications.job_id`
> nullable, advisors show nothing new). Engine shipped as designed:
> `engine/` (worker, pipeline, guarded-UPDATE claims, notifications,
> PdfRenderer port + stub), `StorageService.putObject`, definition contract
> extended with optional `fetchData`/`buildDocument`,
> `REPORT_LEASE_SECONDS` + `REPORT_WORKER_CONCURRENCY` env vars, module
> README. Typecheck clean. **Live-verified against the running dev server:**
> a probe request inserted via SQL was picked up by the real worker within
> seconds — claimed (attempt_count 1), failed cleanly at the definition
> seam (no fetcher until 12-5) with `report_generation_failed`, terminal
> notification inserted with `job_id: null` (`report_failed`, payload
> reportId/label/status/errorCode, no URLs); recovery predicate + guarded
> claim verified via SQL probes (probe rows cleaned up). End-to-end success
> (PDF bytes) waits on 12-4/12-5 as planned.

> **Deviation from the PRD/epic text, decided before dev (2026-09-20):** the
> PRD's "ready stamp + notification insert commit in one transaction" assumed
> the claim RPC era. After the de-stored-procedure pass (migration 51) there
> are no report RPCs, and the user asked to keep stored procedures minimal
> and business logic in the backend. So the terminal stamp and the
> notification insert are **two app-level steps** in the worker: stamp the
> terminal status first, then insert the notification with the admin client;
> a notification failure is logged and dropped (the PRD's own fallback —
> history polling — covers the gap, and a worker crash between the two steps
> lands in the same "notification dropped, list shows the truth" bucket).
> The claim itself is the **guarded UPDATE** from migration 51's header
> comment, not a claim RPC. Read AC 5 and the PRD's one-transaction clause as
> superseded on that point.

## Story

As an **owner**,
I want my queued report to generate automatically and finish with a stored PDF or a clear failure,
So that I never have to retry or wonder.

## Acceptance Criteria

1. **Poll worker** — **Given** the app is running **When** the worker ticks
   (every `REPORT_POLL_INTERVAL_SECONDS`, default 5) **Then** it finds
   candidate rows (`status = 'queued'`, oldest first) and drives
   `queued → generating → ready | failed` through the full pipeline;
   concurrency is capped (default 1 — one render at a time, sequential poll
   loop); the worker starts on app bootstrap and shuts down cleanly
   (`OnApplicationBootstrap` / `OnModuleDestroy`, interval cleared). Each log
   entry carries: `tenantId`, `reportRequestId`, `currentStatus`, `timestamp`
   (ISO 8601 UTC), log level (info for poll ticks, warn for claim conflicts,
   error for failures); never log params or user data.
2. **Atomic claim (de-SP)** — **Given** one or more workers/racers **When**
   claiming a `queued` row **Then** the claim is a single guarded UPDATE via
   the admin client: `update report_requests set status='generating',
   locked_until = <now + lease>, attempt_count = attempt_count + 1
   where id = ? and (status = 'queued' OR (status = 'generating' AND 
   locked_until < now()))` — so exactly one caller gets a row back and the 
   loser sees zero rows updated (atomic in Postgres, no RPC; migration 51's 
   header comment is the design of record); a stale worker never double-runs 
   a request.
3. **Pipeline + R2 upload** — **Given** a claimed request **When** generation
   runs **Then** the definition's fetcher produces the payload, the
   `PdfRenderer` port renders PDF bytes, and `StorageService.putObject`
   (new method — S3 `PutObjectCommand` with the buffer, the first real
   server-side upload in the service) uploads to the deterministic key
   `{tenantId}/reports/{requestId}.pdf` **strictly before** the ready stamp;
   **R2 `PutObjectCommand` overwrites idempotently** (verify S3 docs that 
   same-key upload replaces without versioning); lease recovery re-uploads 
   to the same key so orphaned PDFs self-heal; then `r2_key`, `file_size_bytes`, 
   `completed_at` stamp with `status = 'ready'`. There is never a partial 
   or linkless "ready".
4. **Failure semantics** — **Given** any generation failure (fetch, render,
   upload, DB stamp) **When** it happens **Then** the row becomes `failed`
   with a stable `error_code` (`report_generation_failed`, or
   `report_too_large` from the fetcher later); failures are logged with
   tenant/request context and never secrets.
5. **Notification (app-level two-step)** — **Given** the terminal stamp
   committed **When** the worker inserts the notification **Then** it goes
   only to `requested_by` (never all owners) via the admin client with
   `event_type = 'report_ready' | 'report_failed'`, a payload carrying:
   `{ reportId: UUID, reportType: string, reportLabel: string, status: 'ready'|'failed', errorCode?: string }`
   (the report's `type`, the definition's `label` field e.g. 'technician_job_activity',
   and status enum, no URLs) and `job_id` NULL (migration 52 makes `notifications.job_id` 
   nullable; the Realtime broadcast trigger fans it out untouched). **Edge 
   case: if `requested_by` user was deleted**, the FK would fail; the worker 
   logs the failure and drops the notification (no retry) — the FE history 
   polling is the fallback, so the user still discovers the ready report on 
   next poll. A notification failure or a crash between stamp and notify is 
   logged and dropped — the FE history polling is the fallback, so no retry 
   machinery (supersedes the PRD's one-transaction clause, see the deviation 
   blockquote).
6. **Lease crash recovery** — **Given** a deploy killed the worker
   mid-render **When** the next poll runs **Then** a row stranded
   `generating` past its `locked_until` lease is **checked before re-running**:
   if `attempt_count + 1 > REPORT_MAX_ATTEMPTS` (default 3, so after 3 failed
   attempts the row is terminal and will not be re-run), mark it `failed` with
   `report_generation_failed` instead of re-claiming. Otherwise, re-claim by
   the same guarded UPDATE with the lease predicate
   (`where id = ? and status = 'generating' and locked_until < now()`),
   increment `attempt_count`, and re-run — re-uploading to the **same**
   deterministic R2 key (the orphan self-heals).
7. **Engine knows no specific report** — **Given** the engine **When**
   reviewed **Then** it calls only the registry definition contract
   (`type`, `label`, `paramSchema`, `fetcher`, `templateBuilder` — the contract 
   fields 12-5 fills); with nothing implemented yet the definition raises a typed
   not-implemented error and the row fails with `report_generation_failed`
   — expected and fine until 12-4/12-5 land. **Definition contract 
   standardization:** All future definitions use canonical names (`fetcher`, 
   `templateBuilder`, not `fetchData`/`buildDocument` or other variants).
   The `PdfRenderer` **port** (interface) is defined in this story, the pdfmake 
   implementation is 12-4's; the module still imports only `common/` + 
   `storage` (NFR5).
8. **Env vars configured** — **Given** config **When** the app boots **Then**
   `REPORT_LEASE_SECONDS` (300 seconds; worker's claim lease duration) and
   `REPORT_WORKER_CONCURRENCY` (1; sequential processing) are in the Joi env
   schema (boot fails if missing). These are worker-specific; 12-2 adds
   separate vars for presigning and job limits.
9. **Backend-only story, no app code** — **Given** this story merges,
   **When** reviewed **Then** it ships the engine/worker, the migration 52
   (notifications.job_id nullable), the StorageService.putObject addition
   plus docs; the fenzo-app screen is 12-6. Additive backend change —
   merges/deploys before any fenzo-app story per the cross-repo ordering
   rule.

## Tasks / Subtasks

- [ ] Task 1: Migration 52 — notifications.job_id nullable (AC: 5)
  - [ ] `supabase/migrations/20260920000008_notifications_job_id_nullable.sql`
        (next sequence after 51): `alter table notifications alter column
        job_id drop not null;` — the FK + ON DELETE CASCADE stay; header
        comment documents why (report notifications have no job).
  - [ ] Apply via the Supabase MCP; run the security advisor after.
- [ ] Task 2: StorageService.putObject (AC: 3)
  - [ ] `putObject(key: string, contentType: string, body: Buffer):
        Promise<void>` on `src/storage/storage.service.ts` — real
        `PutObjectCommand` with `Body`, mirroring the existing presign
        methods' shape and logging.
- [ ] Task 3: Engine seam — definition contract extension + renderer port
      (AC: 7)
  - [ ] Extend `registry/report-definition.ts`: `fetcher` and
        `templateBuilder` fields (typed, optional until 12-5 implements
        them) — the engine treats a missing/throwing-not-implemented
        fetcher or builder as `report_generation_failed`.
  - [ ] `engine/pdf-renderer.port.ts` — the `PdfRenderer` port interface
        (`render(doc): Promise<Buffer>`); register a **stub provider** that
        throws not-implemented; 12-4 swaps in the pdfmake implementation.
- [ ] Task 4: Claim + pipeline (AC: 2, 3, 4, 6)
  - [ ] `engine/report-claims.ts` — the two guarded-UPDATE claim helpers
        (fresh `queued` claim; expired-lease recovery claim) through the
        admin client, returning the claimed row or null; constants for the
        lease duration (default 5 min, config `REPORT_LEASE_SECONDS`).
  - [ ] `engine/report-pipeline.service.ts` — run one claimed row end to
        end: claim → fetch → render → putObject → stamp ready (+ r2_key,
        file_size_bytes, completed_at); every failure path stamps
        `failed` + `error_code` in a guarded UPDATE
        (`where id = ? and status = 'generating'`) so a stale worker can
        never overwrite a recovered row; the max-attempts check happens
        **before** re-running a recovered row.
- [ ] Task 5: Poll worker (AC: 1)
  - [ ] `engine/report-worker.ts` — `OnApplicationBootstrap` starts the
        interval (`REPORT_POLL_INTERVAL_SECONDS`, default 5);
        `OnModuleDestroy` clears it; each tick: fetch candidate ids
        (`status='queued'` oldest-first, then expired-lease
        `generating`), claim + process sequentially (concurrency default 1
        via `REPORT_WORKER_CONCURRENCY`), never let a tick overlap itself
        (a simple `isRunning` guard); logs carry tenant/request context,
        never secrets.
- [ ] Task 6: Notification insert (AC: 5)
  - [ ] `engine/report-notifications.ts` — insert into `notifications` via
        the admin client after the terminal stamp (`job_id: null`, payload
        without URLs); wrap in try/catch — any failure (including FK violation
        if `requested_by` user was deleted) logs the error and drops the
        notification (no retry). The FE history polling fallback covers this.
- [ ] Task 7: Module + env wiring (AC: 8, 9)
  - [ ] Register the new providers in `reports.module.ts`; the module still
        imports only `SupabaseModule` + `StorageModule`.
  - [ ] Add `REPORT_LEASE_SECONDS` (300) and `REPORT_WORKER_CONCURRENCY` (1)
        to the Joi schema in `app.module.ts` (integer, positive, default —
        the 12-2 shape).
- [ ] Task 8: Docs (small-modular rule: docs updated in the same change)
  - [ ] `src/reports/README.md` — module layout, the registry contract now
        including fetcher/templateBuilder/renderer, the worker lifecycle,
        and the de-SP concurrency story (guarded UPDATEs, trigger cap).
  - [ ] Update `docs/data-models.md` (migration 52 row, notifications.job_id
        nullable) and `docs/api-contracts.md` only if the response shapes
        change (they should not).
  - [ ] Keep every file to one responsibility (~300-line limit).

## Dev Notes

### Repo and tooling facts

- Repo is **fenzit-be** (`workspace/core/backend/fenzit-be`); work on
  `main`, never commit/push without the user's say-so, BMAD review before
  any commit (currently deferred by the user — build now, review later).
- **bun only**; fenzit-be has **no lockfile** — never generate/commit
  `bun.lock`.
- **All DB access via the Supabase MCP** (`apply_migration`, `execute_sql`,
  `get_advisors`). Migration 52 (20260920000008) is this story's only migration.
- The `report_requests` schema is migration 20260920000004 (from 12-1; columns: 
  `locked_until`, `attempt_count`, `r2_key` unique nullable, `file_size_bytes`,
  `error_code`, `completed_at`); the in-flight guard trigger is migration 
  20260920000007 (from 12-2). Recovery never moves a terminal row back — the 
  guard trigger's comment already covers why the cap holds.

### Real files to read first

- `supabase/migrations/20260920000007_reports_drop_rpcs_in_flight_trigger.sql`
  — the guarded-UPDATE claim design of record (header comment documents the 
  claim semantics, PT SQLSTATE codes, and lease/recovery contract; the service 
  layer maps PT codes to HTTP statuses — see fenzit-be's 
  `src/workflow/workflow.service.ts` for precedent) + the in-flight trigger 
  the recovery path coexists with.
- `src/storage/storage.service.ts` — the S3 client this story adds
  `putObject` to (presigned `PutObjectCommand` exists; a real
  server-side upload with `Body` does not yet).
- `src/reports/reports.service.ts` + `registry/report-definition.ts` —
  the admin-client access idiom, the PT429 mapping, and the definition
  contract this story extends with `fetcher`/`templateBuilder`.
- `supabase/migrations/20260909000002_notifications_table.sql` — the
  notifications schema (`job_id` NOT NULL is what migration 52 relaxes;
  `event_type`/`payload` shape; the AFTER INSERT Realtime broadcast
  trigger that fans the report notification out — inserting via the admin
  client still fires it).
- `supabase/migrations/20260913000002_advance_workflow_step_location_params.sql`
  — the existing notification insert shape to mirror
  (event_type, payload keys, self-notification guard precedent).
- `src/app.module.ts` — the Joi env schema (add the two new vars in the
  12-2 shape).

### Design decisions already made (do not re-litigate)

- **No claim RPC** — the guarded UPDATE is atomic in Postgres; migration
  51's header comment is the design of record (user's de-SP decision).
- **No terminal-stamp RPC / no DB trigger for the notification** — the
  two-step app-level approach is the deliberate trade (see the deviation
  blockquote): keeps logic in backend code per the user's direction, and
  the notification gap is covered by the PRD's own fallback (FE history
  polling). Do not introduce an AFTER UPDATE trigger for this.
- **Sequential concurrency default 1** — NFR-1 accepts head-of-line
  blocking at v1 scale; the poll loop processes candidates one at a time.
- **Lease = 5 min default** — comfortably above the NFR-2 render budget
  (<10 s for ≤1,000 jobs) plus upload headroom.
- **Deterministic R2 key** — `{tenantId}/reports/{requestId}.pdf`; lease
  recovery re-uploads the same key so an R2 orphan from a failed stamp
  self-heals on the next attempt.

### Dependency note (expected incompleteness)

- With 12-4/12-5 not landed, every request that reaches the pipeline fails
  at the definition seam with `report_generation_failed` — that is the
  designed behaviour for this story (12-2's status endpoint already
  renders `failed` rows). End-to-end success arrives with 12-5.
- Tests follow the project rule: implement → user confirms the end-to-end
  feature (only possible after 12-4/12-5) → then the state-machine /
  crash-recovery suites (NFR7 assigns them here) → BMAD review.

### Pre-launch freedom

- App/backend are not live: shape changes are free, no compat shims. The
  notifications.job_id relaxation is pre-launch-legitimate (story 3-1's
  constraint is being widened, not shimmed).

### References

- [Source: artifacts/planning-artifacts/epics-reports.md — Story 12.3] —
  the story definition this file refines.
- [Source: artifacts/planning-artifacts/prds/prd-fenzo-reports-2026-09-18/prd.md
  §5.3 FR-4, §5.4 FR-7/FR-8, §7 NFR-1/NFR-2/NFR-7] — pipeline ordering,
  lease recovery, notification fanout, resource safety, test scope.
- [Source: artifacts/implementation-artifacts/12-1-backend-report-requests-schema-and-claim-rpc.md]
  — the schema story (table, lease, r2_key uniqueness).
- [Source: artifacts/implementation-artifacts/12-2-backend-report-module-skeleton-and-request-api.md]
  — the module skeleton + the de-SP deviation this story builds on.
- [Source: fenzit-be supabase/migrations/20260920000007_reports_drop_rpcs_in_flight_trigger.sql]
  — the guarded-UPDATE claim design of record.
- [Source: fenzit-be src/storage/storage.service.ts] — the R2 client.
- [Source: fenzit-be supabase/migrations/20260909000002_notifications_table.sql]
  — the notifications table the terminal notification inserts into.