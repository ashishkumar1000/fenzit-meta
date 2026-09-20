# Story 12.2: Backend — reports module skeleton + request API

Status: ready-for-dev
baseline_commit: 18ea107 (fenzit-be; note: migrations
`20260920000004_create_report_requests.sql` + `20260920000005_rpc_claim_report_request.sql`
from story 12-1 are staged but uncommitted on top of it)

> **Implemented 2026-09-20 — with one deviation from the Dev Notes.** The
> "Atomic count+insert pattern" section below proposes a SECURITY DEFINER RPC
> for the in-flight cap. The user asked to keep stored procedures to a minimum
> ("try using stored procedure less"), so the cap ships as a **BEFORE INSERT
> trigger** instead (migration 51, superseding the create-RPC of migration 50
> and dropping 12-1's claim RPC too): `report_requests_in_flight_guard` takes
> a per-tenant advisory xact lock, counts `queued|generating`, and raises
> `PT429` at ≥ 3. The service inserts plainly and maps `error.code === 'PT429'`
> → 429 `REPORT_IN_FLIGHT_LIMIT`. Everything else (module skeleton, registry,
> DTO→400 mapping, keyset list, presign-on-ready status) shipped as written.

## Story

As an **owner**,
I want to submit a report request and see its status and history through the API,
So that report generation starts and stays trackable.

## Acceptance Criteria

1. **Create endpoint** — **Given** `POST /api/v1/reports` with a valid body
   (type, IST-valid range ≤ 92 days inclusive, ≤ 25 tenant technicians)
   **When** submitted by an owner with `x-idempotency-key` **Then** it returns
   `201 { id, status: 'queued', createdAt }` and creates the
   `report_requests` row via the owner-JWT INSERT policy (12-1's RLS); a
   replay with the same key returns the original response, never a duplicate
   row (the existing `IdempotencyInterceptor` 24 h replay — reused as-is).
2. **Create validation** — **Given** an invalid create (range > 92 days,
   start > end, a future date on the **IST clock**, unknown `report_type`,
   > 25 or non-tenant / non-technician ids, empty `technician_ids` on a 
   tenant with zero technicians) **When** submitted **Then** 400
   with the mapped code (`report_range_too_large`,
   `invalid_technician_selection`, …). Absent/empty `technician_ids` means
   **all technicians** — validate that the tenant has at least one 
   technician; if zero, return 400 `invalid_technician_selection`.
3. **Atomic in-flight cap** — **Given** 3 requests already `queued` +
   `generating` for the tenant **When** a 4th is submitted (including racing
   submissions) **Then** it is rejected with `report_in_flight_limit` — and
   the count + insert is **one transaction**, so concurrent submissions can
   never exceed the cap (NFR3).
4. **Status endpoint** — **Given** `GET /api/v1/reports/:id` **When** called
   by the owning tenant **Then** it returns
   `{ id, reportType, params, status, createdAt, completedAt, file?, error? }`;
   when `ready`, `file` carries a fresh presigned R2 URL (TTL from
   `REPORT_PRESIGN_TTL_SECONDS`), size and filename; another tenant's id →
   404 (no existence leak); presign failure handling:
   - **Persistent R2 object loss (missing/deleted):** run S3 `HeadObject`
     on the key — if 404, return `410 Gone` (file truly missing).
   - **Transient presign failure:** if `HeadObject` returns 5xx or timeout,
     return `500 report_presign_failed` (retry-able).
   Technician role → 403 (via the `@Roles` guard).
   **Note:** the worker (12-3) does not exist yet, so no row can be `ready`
   in this story — the presign code path is built and expected to be
   unexercisable until 12-3 lands.
5. **History list endpoint** — **Given** `GET /api/v1/reports` **When**
   called **Then** a keyset-paginated `PaginatedResponse` (page 20, cursor on
   the last `(created_at DESC, id DESC)` pair, newest first, endpoint-scoped cursor);
   a `failed` report is a normal 200 row carrying `error_code`, never an
   ApiError.
6. **Registry + definition contract** — **Given** the registry **When** a
   definition is inspected **Then** it carries a stable `type` id, a label
   and a param schema (validated on create at POST time — unknown `report_type` → 400);
   `technician_job_activity` is registered as the first definition; the create 
   path consults the registry to validate the type exists before inserting; 
   registering a new type = one definition file + one registry entry with 
   **zero engine/API changes**; the module imports only `common/` + `storage` 
   (NFR5 — nothing from `jobs/`, `customers/`, etc.; data access through the 
   Supabase client directly).
7. **Env vars** — **Given** config **When** the app boots **Then**
   `REPORT_PRESIGN_TTL_SECONDS` (600), `REPORT_POLL_INTERVAL_SECONDS` (5),
   `REPORT_MAX_JOBS` (5000), `REPORT_MAX_ATTEMPTS` (3) are in the Joi env
   schema (boot fails if missing).
8. **Backend-only story, no app code** — **Given** this story merges,
   **When** reviewed, **Then** it ships only the `src/reports/` module +
   env/error-code additions plus docs; the worker/engine and the first
   template come in 12-3/12-4/12-5, the fenzo-app screen in 12-6. Additive
   backend change — merges/deploys before any fenzo-app story per the
   cross-repo ordering rule.

## Tasks / Subtasks

- [ ] Task 1: Module wiring (AC: 6)
  - [ ] `src/reports/reports.module.ts` + `reports.controller.ts` — mirror
        `src/jobs/jobs.module.ts` + `jobs.controller.ts` (NestJS v11 + Fastify
        v5; the global `api/v1` prefix is already app-wide in `main.ts`).
  - [ ] Sub-layout: `service/`, `dto/`, `reports-definitions/` (engine/ and
        renderer/ are 12-3/12-4 concerns — create the dirs only when their
        stories land, keeping this story small-modular).
  - [ ] Module imports only `common/` + `storage` (NFR5).
- [ ] Task 2: DTOs + validation (AC: 1, 2)
  - [ ] `dto/create-report-request.dto.ts` — `report_type` (default
        `technician_job_activity`), `start_date`, `end_date` (ISO date
        strings), `technician_ids[]` (optional).
  - [ ] Service-layer validation: range ≤ 92 days inclusive, start ≤ end,
        not-in-future evaluated on the **IST clock** (no date library —
        mirror `fenzo-app`'s IST math; reuse the
        `IST_OFFSET_MS` convention from
        `src/common/utils/ist-day-range.util.ts`); `technician_ids` validated
        to belong to the tenant and be technicians, max 25.
  - [ ] `dto/report-response.dto.ts` + `dto/report-list-query.dto.ts` (cursor
        param) — Swagger decorators on controller + DTOs.
- [ ] Task 3: Service + atomic in-flight cap (AC: 1, 3)
  - [ ] `service/reports.service.ts`: tenant-scoped reads/writes via the
        Supabase client (`tenantId` from `@CurrentUser()` at the service
        layer; RLS is the second layer — 12-1's policies).
  - [ ] Atomic count+insert enforcing the cap (max 3 `queued`+`generating`
        per tenant) → `report_in_flight_limit`: one transaction (single SQL
        statement via an RPC or a serializable-transaction insert-where-
        guard) so racing submissions cannot exceed it — see Dev Notes.
- [ ] Task 4: Endpoints (AC: 1, 4, 5)
  - [ ] `POST /api/v1/reports` — `@Roles(Role.OWNER)`, `@CurrentUser()`,
        idempotent via the existing `IdempotencyInterceptor` wiring (copy how
        `jobs.controller.ts` opts in); validate `report_type` exists in registry 
        before creating row (unknown → 400); returns `201 { id, status, createdAt }`.
  - [ ] `GET /api/v1/reports/:id` — owner-only, tenant-scoped; when `ready`,
        mint a fresh presigned URL via `StorageService` (TTL
        `REPORT_PRESIGN_TTL_SECONDS`) + size + filename. Presign failure
        handling: on presign error, run S3 `HeadObject` on the key — if 404,
        return `410 Gone` (file missing); if 5xx or timeout, return `500
        report_presign_failed` (transient). Other tenant's id → 404.
  - [ ] `GET /api/v1/reports` — keyset pagination via
        `src/common/dto/paginated-response.dto.ts` +
        `src/common/utils/cursor.util.ts` (add a `reports-list` `CursorScope`,
        cursor on `created_at DESC, id DESC` for newest-first ordering),
        page 20; failed rows carry `error_code` as plain data.
- [ ] Task 5: Registry + first definition (AC: 6)
  - [ ] `reports-definitions/report-definition.ts` — the definition contract
        (stable `type` id, label, param schema validated on create).
  - [ ] `reports-definitions/technician-job-activity.definition.ts` + the
        registry map it registers into. The fetcher/template bodies are
        12-5's job — this story ships the contract + registration only.
- [ ] Task 6: Error codes (AC: 2, 3, 4)
  - [ ] Add to `src/common/enums/error-code.enum.ts`:
        `report_range_too_large`, `invalid_technician_selection`,
        `report_in_flight_limit`, `report_too_large`,
        `report_generation_failed`, `report_presign_failed`.
- [ ] Task 7: Env vars (AC: 7)
  - [ ] Add `REPORT_PRESIGN_TTL_SECONDS` (600),
        `REPORT_POLL_INTERVAL_SECONDS` (5), `REPORT_MAX_JOBS` (5000),
        `REPORT_MAX_ATTEMPTS` (3) to the Joi `validationSchema` in
        `src/app.module.ts` (number with default, following the
        `MAX_ATTACHMENT_SIZE_BYTES` shape).
  - [ ] **Note:** `REPORT_LEASE_SECONDS` and `REPORT_WORKER_CONCURRENCY`
        are worker-only (story 12-3) — do not add them here.
- [ ] Task 8: Docs (small-modular rule: docs updated in the same change)
  - [ ] A short `src/reports/README.md` (or module header comment) capturing
        the module layout, the registry contract and the dependency rule —
        the 12-3/12-5 stories read it first. This story seeds the doc; the
        **full extensibility checklist is 12-5's deliverable** (task 5,
        building on the contract defined here).
  - [ ] Keep every file to one responsibility (~300-line limit per the
        project rule).

## Dev Notes

### Repo and tooling facts

- Repo is **fenzit-be** (`workspace/core/backend/fenzit-be`); commit there,
  never in the meta-repo. Work on `main` (no branches), never commit or push
  without the user's explicit say-so, and run the BMAD code review before any
  commit.
- **bun only** — `bun install`, `bun run`; never npm/yarn/pnpm; and per
  memory fenzit-be has **no lockfile**: never generate or commit `bun.lock`
  there.
- **All DB access goes through the Supabase MCP tools** (project convention).
  The `report_requests` table + RLS + claim RPC already exist from story
  12-1 (migrations `20260920000004` + `20260920000005`, applied). This story
  adds **no migrations** — the create path inserts through the owner-JWT
  INSERT policy the 12-1 migration defined.

### Real files to mirror (recon — read these first)

- `src/jobs/jobs.module.ts` + `src/jobs/jobs.controller.ts` — the module +
  controller skeleton to copy: Swagger decorators, `@Roles(Role.OWNER)`,
  `@CurrentUser()` with `RequestUser`, the idempotency opt-in, and the
  "`:id` route stays below the parameterless `@Get()`" ordering note.
- `src/common/enums/error-code.enum.ts` — where the six report codes go.
- `src/common/enums/role.enum.ts`,
  `src/common/decorators/roles.decorator.ts` +
  `src/common/guards/roles.guard.ts` (+ `jwt-auth.guard.ts`) — the
  owner-only 403 path (FR14).
- `src/common/decorators/current-user.decorator.ts` +
  `src/common/interfaces/request-user.interface.ts` — the `tenantId` /
  `userId` claims the service scopes by.
- `src/common/interceptors/idempotency.interceptor.ts` — the 24 h replay
  interceptor; FR1 honours the existing `x-idempotency-key` convention
  as-is, no new machinery.
- `src/common/dto/paginated-response.dto.ts` +
  `src/common/utils/cursor.util.ts` — the existing envelope + keyset cursor
  util. The `CursorScope` union needs a new `'reports-list'` entry (cursor
  keys on `created_at`); copy the `jobs-list` usage in `jobs.service.ts`.
- `src/common/utils/ist-day-range.util.ts` — the existing no-date-library
  IST math (`IST_OFFSET_MS = 5.5h`, UTC-component arithmetic) to mirror for
  "today in IST" when validating "not in the future".
- `src/storage/storage.service.ts` + `storage.module.ts` — the AWS SDK v3
  R2 service the status endpoint's presign goes through (read-presign exists;
  `PutObjectCommand` for uploads is 12-3's addition — do not add it here).
- `src/common/factories/supabase-client.factory.ts` +
  `src/supabase/supabase.module.ts` — how the service obtains its Supabase
  client.
- `src/app.module.ts` — the Joi `validationSchema` where the four
  `REPORT_*` env vars land (follow the `MAX_ATTACHMENT_SIZE_BYTES`
  number-with-default shape).
- `src/common/filters/global-exception.filter.ts` — the global
  `{ statusCode, error_code, message }` shape the new codes flow through.

### IST date math without a date library

- Validate `start_date`/`end_date` as plain ISO `YYYY-MM-DD` strings; no
  date library anywhere. "Not in the future" compares the IST wall-clock
  date to `end_date`: derive "today in IST" the way
  `ist-day-range.util.ts` does (shift `now` by `IST_OFFSET_MS`, then read
  UTC components). Never compare against the UTC server date — it would
  reject a same-day IST range for part of the day (PRD §4 date semantics).
- The 92-day cap counts days **inclusively** (start and end both count).

### Atomic count+insert pattern (backend-first)

- The in-flight cap (max 3 `queued`+`generating` per tenant) must be
  enforced so **racing submissions cannot exceed it** — a plain count-then-
  insert through the Supabase client is a check-then-act race (NFR3, FR2).
- Preferred: one atomic SQL statement — an insert guarded by the count,
  e.g. a small SECURITY DEFINER RPC `request_report_request(...)` that
  runs `INSERT ... SELECT ... WHERE (SELECT count(*) FROM report_requests
  WHERE tenant_id = <jwt tenant> AND status IN ('queued','generating')) < 3`
  and raises the repo's `PT<http-status>` SQLSTATE convention on cap failure
  (the `rpc_update_job_with_log` / `confirm_attachment` guard idiom from
  12-1's Dev Notes; the service layer maps `PT429` →
  `report_in_flight_limit`). Tenant comes from `auth.jwt()` inside the
  function — never a parameter — and `EXECUTE` is revoked from
  `anon`/`authenticated`, matching the 12-1 claim-RPC discipline.
- If a migration-based RPC is chosen, it goes through the Supabase MCP
  (`apply_migration`) and its header comment documents the cap semantics.
  A plain client-side count is **not** an acceptable substitute.

### Registry + definition contract

- The create path validates `report_type` against the registry (unknown →
  400) and applies the definition's param schema — the API knows nothing
  about specific reports (FR9). Registering a type = one definition file +
  one registry entry, zero engine/API changes.
- `technician_job_activity` registers now with its param schema; its data
  fetcher and template/payload builder are 12-5's bodies — this story ships
  the contract and the registration seam only (the fetcher/builder fields
  may be typed but unimplemented until 12-4/12-5 land).
- Module imports only `common/` + `storage` — nothing from `jobs/`,
  `customers/`, etc.; report data access goes through the Supabase client
  directly (NFR5).

### Dependency note (expected incompleteness)

- The worker/engine and real-file presigning come in 12-3/12-5. In this
  story no row can ever be `ready` (nothing generates), so the status
  endpoint's `file` branch — and `report_presign_failed` — are built but
  un-exercisable. That is expected and fine: the story works independently
  and enables the future stories. `report_too_large` /
  `report_generation_failed` likewise land as enum codes now; their
  enforcement lives in 12-3/12-5.

### Pre-launch freedom

- App/backend are not live (project memory): no compat shims, no
  additive-old-shape dance. If a DTO shape or endpoint response turns out
  wrong during dev, change it outright rather than layering a v2.

### Test timing (project rule)

Implement → **user confirms the feature works** (sanity-check through the
API/Swagger) → only then write tests → then BMAD code review. **No test
suites are written in this story.** Per the epics coverage map (NFR7), the
in-flight-cap-under-concurrency suite belongs to 12-3, registry/params
specs to 12-5 — and none are written before the user confirms the
end-to-end feature on device.

### References

- [Source: artifacts/planning-artifacts/epics-reports.md — Story 12.2
  definition + FR1–FR4, FR9, FR14, NFR3/NFR5 rows in the FR Coverage Map] —
  the story definition and the 12-1 → 12-2 → 12-3 ordering.
- [Source: artifacts/planning-artifacts/prds/prd-fenzo-reports-2026-09-18/prd.md
  §5.1 FR-1/FR-2/FR-3, §4 date semantics, §7 NFR-3] — endpoint contracts,
  body shape, caps (92 days, 25 technician ids, in-flight 3), error codes,
  presign TTL, keyset pagination, IST clock.
- [Source: artifacts/planning-artifacts/prds/prd-fenzo-reports-2026-09-18/addendum.md
  §2, §3] — module skeleton layout, registry + strategy pattern,
  idempotency/error-shape/auth recon, env vars, independence seam.
- [Source: artifacts/implementation-artifacts/12-1-backend-report-requests-schema-and-claim-rpc.md]
  — the sibling story this one builds on (table, RLS, claim RPC, PT<status>
  convention).
- [Source: fenzit-be src/jobs/jobs.module.ts, src/jobs/jobs.controller.ts] —
  the module/controller skeleton to mirror.
- [Source: fenzit-be src/common/dto/paginated-response.dto.ts,
  src/common/utils/cursor.util.ts] — the envelope + keyset cursor to reuse.
- [Source: fenzit-be src/common/interceptors/idempotency.interceptor.ts] —
  the 24 h `x-idempotency-key` replay convention.
- [Source: fenzit-be src/common/utils/ist-day-range.util.ts] — the
  no-date-library IST math convention.
- [Source: fenzit-be src/storage/storage.service.ts] — the R2 presign path
  for the status endpoint.
- [Source: fenzit-be src/app.module.ts] — the Joi env schema.