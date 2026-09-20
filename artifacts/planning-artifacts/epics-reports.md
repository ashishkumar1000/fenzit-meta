---
stepsCompleted: [1, 2]
inputDocuments:
  - artifacts/planning-artifacts/prds/prd-fenzo-reports-2026-09-18/prd.md
  - artifacts/planning-artifacts/prds/prd-fenzo-reports-2026-09-18/addendum.md
  - artifacts/planning-artifacts/prds/prd-fenzo-reports-2026-09-18/assets/fenzit-logo.png
  - "no dedicated Architecture.md or UX design contract for this feature — the PRD addendum carries the architecture decisions (PDF engine, module pattern, env vars, BE/FE pattern recon) and the PRD §6 carries the frontend UX requirements"
---

# Fenzo - Epic Breakdown (Report Module — Owner PDF Reports)

## Overview

This document provides the epic and story breakdown for the **Report Module — Owner PDF Reports** feature (PRD: `prds/prd-fenzo-reports-2026-09-18/prd.md`), decomposing its requirements into implementable stories across `fenzit-be` (backend report module) and `fenzo-app` (owner Reports screen). No dedicated Architecture or UX document exists; the PRD's addendum carries the architecture decisions and pattern recon, and PRD §6 carries the frontend UX requirements — both are treated as first-class requirement sources here.

## Requirements Inventory

### Functional Requirements

**Backend — report request API**

FR1: `POST /api/v1/reports` (owner role only) creates a report request: body `report_type` (default `technician_job_activity`), `start_date`, `end_date` (ISO dates; validated, max range 92 days inclusive, start ≤ end, "not in the future" evaluated on the IST clock), optional `technician_ids[]` (absent/empty = all technicians of the tenant; validated to belong to the tenant and be technicians; max 25). Creates a `report_requests` row (`status: queued`), returns `201 { id, status, createdAt }`, and honours the existing `x-idempotency-key` convention (replays the same request, never a duplicate PDF; a user-visible retry uses a fresh key).

FR2: The in-flight cap (NFR-3: max 3 queued+generating per tenant) is enforced atomically — count + insert in one transaction, so concurrent submissions cannot exceed it. The max-jobs cap (config `REPORT_MAX_JOBS`, default 5,000) is enforced at fetch time — exceeding fails the request with `report_too_large`, never silent truncation. v1 error codes: `report_range_too_large`, `report_too_many_technicians`, `report_in_flight_limit`, `report_too_large`, `report_generation_failed`, `report_presign_failed`.

FR3: `GET /api/v1/reports/:id` (owner role only, tenant-scoped) returns `{ id, reportType, params, status, createdAt, completedAt, file?, error? }`; when `status: ready`, `file` carries a fresh short-lived presigned R2 URL (default TTL 10 min, config `REPORT_PRESIGN_TTL_SECONDS`), file size, and filename. Never leaks another tenant's row (404). If the row is `ready` but presigning transiently fails → 500 with `report_presign_failed`.

FR4: `GET /api/v1/reports` (owner role only, tenant-scoped) lists report history, keyset pagination (existing `PaginatedResponse` envelope, page size 20, cursor = last `(created_at, id)`), newest first: id, type, range, technician count, status, `error_code`, createdAt, completedAt — a failed report is a 200 with `status: failed`, not an ApiError.

**Backend — template machine**

FR5: Shared brand kit in one file used by every report — owns the Fenzit logo (`assets/fenzit-logo.png`, 360×360 PNG, copied into the module), project theme tokens, Inter fonts (Regular 400 / SemiBold 600 / Bold 700, bundled as base64 vfonts for pdfmake), and reusable page chrome: branded header band, section-card styles, table styles, status colours, footer (page numbers, generation timestamp, Fenzit wordmark). No template hard-codes a colour, font, or the logo.

FR6: One template file per report type — a template describes layout (summary cards, tables, section ordering) as a structured document pulling all styling from the brand kit; `technician_job_activity` ships the first template.

**Backend — generation engine**

FR7: Async generation pipeline: an in-process worker (poll interval config `REPORT_POLL_INTERVAL_SECONDS`, default 5 s; concurrency capped, default 1) picks up `queued` requests and runs `queued → generating → (ready | failed)`. On ready it uploads the PDF to R2 (key `{tenantId}/reports/{requestId}.pdf` via a direct `PutObjectCommand` added to `StorageService`), stores `r2_key` + `file_size_bytes`, stamps `completed_at`. On failure it marks `failed` with a stable `error_code` — never a partial or linkless "ready" state. Failures logged with tenant/request context, never leaking secrets.

FR8: Terminal ordering and crash recovery: R2 upload strictly before the ready stamp; ready stamp + notification insert commit in one transaction; a notification failure after commit is logged and dropped (history polling is the fallback UX). If the DB update fails after a successful upload, lease recovery re-runs the request and re-uploads to the same deterministic key (R2 orphan self-heals). The claim stamps a `locked_until` lease; the poll loop re-claims rows whose lease has expired, tracked with `attempt_count`; max attempts (config `REPORT_MAX_ATTEMPTS`, default 3) → `failed` with `report_generation_failed`. Every backend deploy kills the in-process worker mid-render, so this recovery path is routine.

FR9: Pluggable report registry: each report type is a definition unit — stable `type` id, label, param schema (validated on create), a tenant-scoped data fetcher, and a template/payload builder. The engine (state machine, R2, API) knows nothing about specific reports. Registering a new report type = one definition file + one registry entry; zero engine changes. The module's only cross-domain dependencies are the shared `common/` layer and `storage` — nothing imports from `jobs/`, `customers/`, etc. (data access through the Supabase client directly).

FR10: PDF rendering: v1 renderer implemented with **pdfmake** behind a `PdfRenderer` port (interface) owned by the module; templates emit a structured document through the brand kit; the renderer turns it into PDF bytes with the logo and Inter fonts bundled. Swapping renderer implementations later touches only the renderer adapter.

**Backend — data, state and isolation**

FR11: `report_requests` table migration: `id`, `tenant_id`, `requested_by` (FK users), `report_type`, `params` (jsonb, check-constrained to an object), `status` (`queued | generating | ready | failed`), `locked_until` (lease timestamp), `attempt_count`, `r2_key` (unique, nullable), `file_size_bytes`, `error_code` (nullable), `created_at`, `completed_at`. Deny-by-default RLS.

FR12: **[DEVIATION: no RPC — guarded UPDATE]** Claim of queued→generating transition is performed via a single guarded UPDATE through the admin client, atomic in Postgres (no RPC; user decision to keep stored procedures minimal). The claim updates `status='generating'`, `locked_until=<now+lease>`, `attempt_count=attempt_count+1` where `id=? and (status='queued' OR (status='generating' AND locked_until<now()))` — stamps `locked_until` and ensures a crashed worker never double-runs a request (lease recovery re-claims expired rows).

FR13: **[DEVIATION: two-step, not transactional]** Ready/failed notification: on terminal status, insert a row in the existing `notifications` table — recipient: the `requested_by` user, not all owners — **two app-level steps** (stamp terminal status, then insert notification; not one transaction; a crash between the two or a notification failure is logged and dropped, with the FE history polling as the fallback — PRD's own fallback pattern). The existing Realtime trigger fans it out to the bell/notification feed. Payload carries the report id, status and label; no URLs in the payload.

FR14: Tenant isolation everywhere: every read scoped by the JWT's `tenantId` at the service layer and by RLS at the DB layer; technician role gets 403 on all report endpoints; presigned URLs minted only for rows matching the caller's tenant.

**Backend — first report content (technician_job_activity)**

FR15: Report layout (single PDF, one section per selected technician, "Overall" first): branded header (tenant company name and address from `tenants`; Fenzit logo from the brand kit; styled text header band fallback; report title; date range; generated-at in IST; Fenzit wordmark footer); Overall summary card; per-technician section (summary card scoped to that technician + job table: job number, scheduled date, customer name, skill, status, scheduled time, completed time, attachment count); footer with page numbers, generation timestamp, confidential note.

FR16: Data source (tenant-scoped): jobs whose `scheduled_start` falls inside the date range (IST day bounds), joined to `customers` (name), `skills` (name), `users` (technician name), with attachment counts from `attachments`.

FR17: Metric definitions: on-time % = on-time completed jobs ÷ completed jobs in range (completed-only denominator; zero completed → "—", never 0% or NaN; null `scheduled_end` excluded); total assigned = all jobs in range; completed/cancelled by status; open = scheduled + in_progress; urgent jobs completed = `priority = 'urgent'` among completed; distinct customers served = all statuses; photos + signatures captured = `attachments` with `type IN ('photo', 'signature')` on those jobs.

FR18: Edge-case content rules: a selected technician with zero jobs in range still gets their section (zeroed summary card, empty table with an empty-state row); a selection with zero jobs overall → `ready` PDF with an explicit "No jobs in this period" page (success, not failure); `end_date` inclusive; the 92-day cap counts days inclusively; v1 renders no tenant-supplied logo (Fenzit logo leads the header).

**Frontend (fenzo-app)**

FR19: Reports screen (owner nav tree only): new route `Reports` in the owner stack; entry via a "Reports" tile on the Account (More) tab (existing tile pattern). Screen shows the request form — date range (start/end pickers composed from the existing `@react-native-community/datetimepicker` pattern, IST-correct via `utils/istDate`), technician multi-select (existing `MultiSelect` sheet; empty = all technicians), and a Generate button with proper disabled/`canSubmit` gating.

FR20: Report history list with live status: requests shown newest first with status chips (`Generating…` / `Ready` / `Failed`). While any item is non-terminal, the feature polls the **list endpoint** every 5 s and stops polling when everything is terminal or the screen is left (one mechanism — no per-item `:id` polling). A report-ready notification arriving over Realtime also triggers a store refresh (existing `OwnerRealtimeBridge` pattern).

FR21: Open the PDF: tapping a Ready item fetches the status endpoint (mints a fresh presigned URL) and opens it with `Linking.openURL` (system PDF viewer) via a helper in `utils/linking.ts`, with graceful failure toast. Tapping a Failed item shows the mapped error copy (from `error_code`) — never attempts to open a PDF. No new download/viewer dependency.

FR22: States per design system: first-load spinner, `InlineError` + Retry on failure, `EmptyState` for no reports yet ("Generate your first report"), per-item error copy mapped from `error_code` values; submit guarded against back-navigation while in flight. New `useReports` store follows the tiered store pattern and registers in the reset registry. Each submit attempt generates a **fresh `x-idempotency-key`** — a user-visible retry is a new request, never a 24 h stale replay of a failed one.

### NonFunctional Requirements

NFR1: Resource safety — generation adds ≤ ~50 MB steady memory; concurrency capped (default 1 concurrent render); Chromium-free; must run within Render free-tier limits (512 MB). Head-of-line blocking across tenants is accepted at v1 scale; revisit if NFR2 is violated in practice.

NFR2: Performance — a report of ≤ 1,000 jobs generates and uploads in < 10 s, **measured** on the free-tier instance in tests (0.1 CPU is the weakest box this feature will ever run on; verified, not assumed). ≤ 1,000 jobs is the benchmark case; the enforced oversize guard is the FR1/FR2 jobs cap (`report_too_large`).

NFR3: Range & abuse caps — max date range 92 days; max in-flight (queued+generating) requests per tenant: 3 — further requests rejected with a clear error code until earlier ones finish.

NFR4: Security — owner-only endpoints; tenant scoping at service + RLS; presigned URLs short-lived and minted per request; PDFs contain customer names/phones — never exposed cross-tenant; no service-role keys anywhere in the app.

NFR5: Module independence — `src/reports/` is self-contained (module, controller, service, engine/, reports-definitions/, dto/, renderer/); liftable to a standalone service with only config/env wiring, DB client, R2 credentials, and the notification insert moved to an outbox/interface.

NFR6: Extensibility contract — adding a report type must not modify engine, API, migration, or any existing report definition; covered by a documented checklist in the module README.

NFR7: Tests — unit specs beside source (engine, registry, renderer, params validation); integration test for state-machine transitions and tenant isolation, matching repo conventions. The isolation suite includes the **RPC-privilege audit** (call the claim RPC with an owner JWT → refusal or no-op). The state-machine suite includes **crash recovery** (a row stranded `generating` past its lease → re-claimed → completes, or exhausts attempts → `failed`) and the **in-flight cap under concurrent submissions**.

### Additional Requirements

From the addendum (architecture decisions and pattern recon — no separate Architecture doc exists):

- **PDF engine decision:** pdfmake v1 behind the `PdfRenderer` port (Render free tier: 512 MB / 0.1 CPU makes Chromium-based rendering an OOM risk; pdfmake is pure JS, ~30–50 MB). Fonts must be embedded (bundled Inter TTFs as base64 vfonts — system fonts unavailable in Bun); `pageMargins` + `footer` for page numbers; logo via `image` node; long tables auto-paginate (layout, repeating header rows).
- **Architecture pattern:** registry + strategy + pipeline. State machine lives on the `report_requests` table (no broker/queue — no existing job system in fenzit-be; free tier can't run one). In-process worker polls `queued` rows; Postgres RPC does the atomic claim (queued→generating, `PT<status>` SQLSTATE).
- **Module skeleton:** `src/reports/` — `reports.module.ts` + `reports.controller.ts` (NestJS v11 + Fastify v5, global prefix `api/v1`, Swagger decorators, `@Roles(...)`, `@CurrentUser()`), plus `service/`, `engine/`, `reports-definitions/`, `dto/`, `renderer/`.
- **Auth:** global JWT guard; `tenantId` claim; `Role.OWNER` for all report routes.
- **Idempotency:** reuse `IdempotencyInterceptor` + `idempotency_log` (24 h replay) as-is.
- **Error shape:** global exception filter `{ statusCode, error_code, message }`; add report codes to `error-code.enum.ts`.
- **R2:** extend `src/storage/storage.service.ts` (AWS SDK v3) with a direct `PutObjectCommand` for report uploads (the backend uploads itself, unlike the client-uploads attachments flow).
- **RPC convention:** Postgres RPC with `PT<http-status>` SQLSTATE → mapped in the service layer (see `confirm_attachment`).
- **Notification fanout:** insert into `notifications` → existing AFTER INSERT trigger broadcasts on Realtime.
- **Env:** add `REPORT_PRESIGN_TTL_SECONDS` (600), `REPORT_POLL_INTERVAL_SECONDS` (5), `REPORT_MAX_JOBS` (5000), `REPORT_MAX_ATTEMPTS` (3) to the Joi schema.
- **Deploy:** Render docker runtime; `bun dist/src/main.js`.
- **Cross-repo ordering (CLAUDE.md):** additive backend ships first — all `fenzit-be` stories merge/deploy before the `fenzo-app` story.
- **Logo asset:** `prds/prd-fenzo-reports-2026-09-18/assets/fenzit-logo.png` (already copied from `fenzo-app/src/assets/branding/logo@3x.png`) — the brand-kit story moves it into the BE module.
- **Theme tokens for the PDF kit** (source of truth `fenzo-app/src/theme/colors.ts`): Primary `#1A56DB` (header band, section titles, table header row), Done `#06956F` (completed status, positive numbers), Scheduled `#D97706` (scheduled/in-progress), Cancelled `#C92A2A` (cancelled, failed), Background `#F9FAFB`, Text `#111827`, cool-gray borders.
- **Template machine layout:** brand kit exports helpers — `pageHeader(tenant, title, range)`, `summaryCardRow(cards)`, `jobsTable(rows)`, `pageFooter()` returning doc-definition fragments; each report template file composes only structure from these helpers.
- **Pre-launch freedom (memory):** app/backend not live — schema/shape changes allowed, no compat shims.

### UX Design Requirements

No UX design contract exists for this feature. The frontend UX requirements are carried by PRD §6 and are captured as FR19–FR22 above (owner-only nav entry, request form with date range + technician multi-select, history list with live status chips, open-PDF via presigned URL, design-system states) — no separate UX-DR list is needed.

### FR Coverage Map

Epic 12: Owner PDF Reports — all FRs covered by this single epic (ordered stories).

| FR / NFR | Story | Notes |
|---|---|---|
| FR1 | 12-2 | Create endpoint, validation, idempotency |
| FR2 | 12-2 | Atomic in-flight cap + API-level error codes; jobs cap at fetch in 12-5 |
| FR3 | 12-2 (+12-6) | Status endpoint + presigned URL; FE consumes in 12-6 |
| FR4 | 12-2 (+12-6) | History list endpoint; FE consumes in 12-6 |
| FR5 | 12-4 | Brand kit (logo, Inter fonts, theme tokens, page chrome helpers) |
| FR6 | 12-4 (+12-5) | Template-machine pattern; `technician_job_activity` template in 12-5 |
| FR7 | 12-3 | Engine pipeline: claim → generate → R2 upload → ready/failed |
| FR8 | 12-3 | Terminal ordering, lease crash recovery, attempt caps |
| FR9 | 12-2 (+12-5) | Registry + definition contract; first definition in 12-5 |
| FR10 | 12-4 | PdfRenderer port + pdfmake implementation |
| FR11 | 12-1 | `report_requests` migration + RLS |
| FR12 | 12-1 | SECURITY DEFINER claim RPC, PT<status> SQLSTATE |
| FR13 | 12-3 | Terminal stamp + notification insert in one transaction |
| FR14 | 12-1–12-3 (+12-6) | Isolation at RLS, service layer, and UI surface |
| FR15 | 12-5 | Report layout |
| FR16 | 12-5 | Data fetcher |
| FR17 | 12-5 | Metrics |
| FR18 | 12-5 | Edge-case content rules |
| FR19 | 12-6 | Reports screen + request form |
| FR20 | 12-6 | History list + 5 s list-polling + Realtime refresh |
| FR21 | 12-6 | Open PDF via presigned URL / failed-item error copy |
| FR22 | 12-6 | States, useReports store, fresh idempotency key |
| NFR1 | 12-3, 12-4 | Concurrency cap, memory discipline (pdfmake, no Chromium) |
| NFR2 | 12-5 | Measured <10 s benchmark for ≤1,000 jobs |
| NFR3 | 12-2 | 92-day range cap, atomic 3-request in-flight cap |
| NFR4 | 12-1–12-3, 12-6 | Owner-only, tenant scoping, short-lived presigned URLs |
| NFR5 | 12-2–12-5 | Self-contained `src/reports/` module, only common/ + storage imports |
| NFR6 | 12-5 | Extensibility checklist in module README |
| NFR7 | 12-3–12-5 | Tests AFTER user confirms the feature on device (project rule) |

Coverage notes:
- Every FR maps to exactly one primary story; FR3/FR14 and NFR3/NFR4 span API + engine + FE (isolation enforced at every layer).
- NFR7 tests are distributed across 12-3 (engine/state-machine/isolation), 12-4 (renderer), 12-5 (definition + integration) — but per the project test-timing rule, test writing happens only after the user confirms the feature end-to-end on device; story ACs reflect this sequencing.
- Success metric "a second report type is added with zero engine changes" is delivered as the documented extensibility checklist (12-5 README) — building a second type is out of scope per PRD §3.

## Epic List

### Epic 12: Owner PDF Reports

**Goal:** An owner requests a branded Technician Job Activity PDF over a date range (optionally narrowed to specific technicians), the backend generates it asynchronously and stores it in R2, and the owner opens it from a live history list — with a pluggable registry so future report types are one new definition file.

**FRs covered:** FR1–FR22, NFR1–NFR7 (all)

**Stories (execution order — all fenzit-be stories merge/deploy before the fenzo-app story, per CLAUDE.md cross-repo ordering rule):**

- **Story 12-1 (BE): Report request schema + claim RPC** — `report_requests` migration with deny-by-default RLS (FR11); SECURITY DEFINER claim RPC that resolves the tenant from the JWT inside the function, EXECUTE revoked from anon/authenticated, `locked_until` lease, `PT<status>` SQLSTATE convention (FR12).
- **Story 12-2 (BE): Report module skeleton + request API** — `src/reports/` module wiring; report registry + definition contract; `POST /api/v1/reports` create (validation, idempotency, atomic in-flight cap), `GET /:id` status with fresh presigned URL, `GET /` history keyset list (FR1–FR4, FR9, FR14 service layer, NFR3); report error codes in `error-code.enum.ts`; report env vars in the Joi schema.
- **Story 12-3 (BE): Generation engine + worker** — in-process poll worker; atomic claim usage; state machine `queued → generating → ready|failed`; R2 upload via `PutObjectCommand` on StorageService (upload strictly before ready stamp); lease crash recovery + attempt caps; terminal stamp + `notifications` insert in one transaction (FR7, FR8, FR13, NFR1, NFR7).
- **Story 12-4 (BE): PDF template machine** — brand kit (Fenzit logo asset into the module, Inter Regular/SemiBold/Bold as base64 vfonts, theme tokens, page chrome helpers `pageHeader`/`summaryCardRow`/`jobsTable`/`pageFooter`); `PdfRenderer` port + pdfmake implementation (FR5, FR6 pattern, FR10, NFR1).
- **Story 12-5 (BE): Technician Job Activity report** — first report definition: param schema, tenant-scoped data fetcher (IST day bounds, joins, attachment counts, jobs cap), metrics (on-time %, status counts, urgent completed, customers served, photos+signatures), template composed from brand-kit helpers, edge-case content rules; end-to-end pipeline; NFR2 measured benchmark; module README with the extensibility checklist (FR6, FR15–FR18, NFR2, NFR5, NFR6).
- **Story 12-6 (FE): Owner Reports screen** — `Reports` route + More tab tile; request form (IST date pickers, technician MultiSelect, Generate gating); history list with status chips + 5 s list-polling + Realtime refresh; open Ready PDF via status-endpoint presigned URL (`Linking.openURL`), failed-item error copy; design-system states; `useReports` tiered store; fresh idempotency key per submit (FR3/FR19–FR22, NFR4 UI surface).

**Dependencies:** strictly linear — 12-1 → 12-2 → 12-3 → 12-4 → 12-5 → 12-6; 12-6 ships only after all BE stories are deployed.

**DB access note:** all database work in these stories (migration, RLS, RPC) goes through the Supabase MCP tools, per project convention.

---

## Epic 12: Owner PDF Reports

**Goal:** An owner requests a branded Technician Job Activity PDF over a date range (optionally narrowed to specific technicians), the backend generates it asynchronously and stores it in R2, and the owner opens it from a live history list — with a pluggable registry so future report types are one new definition file.

**FRs covered:** FR1–FR22, NFR1–NFR7 (all)

### Story 12.1: Report request schema + claim RPC (fenzit-be)

As a **report engine**,
I want a `report_requests` table with a secure atomic claim RPC,
So that generation requests are persisted tenant-safely and never double-run.

**Acceptance Criteria:**

**Given** the migration is applied via Supabase MCP **When** I inspect `report_requests` **Then** it has `id` (uuid PK), `tenant_id` (FK), `requested_by` (FK users), `report_type`, `params` (jsonb, check-constrained to an object), `status` (check: `queued|generating|ready|failed`, default `queued`), `locked_until`, `attempt_count` (default 0), `r2_key` (unique, nullable), `file_size_bytes`, `error_code`, `created_at`, `completed_at`, with indexes on `(tenant_id, created_at desc)` and a partial index on `status = 'queued'`

**Given** RLS is enabled **When** a session queries without matching tenant/role **Then** zero rows return (deny-by-default); owner JWTs may select/insert only their tenant's rows; no client-facing UPDATE/DELETE policy (worker mutates via service-role/SECURITY DEFINER paths only)

**Given** the claim RPC **When** the worker calls it for a `queued` row **Then** it transitions to `generating`, stamps `locked_until`, and increments `attempt_count` in one atomic statement

**Given** the row is already `generating`/terminal **When** the claim RPC runs again **Then** it fails with the `PT<status>` SQLSTATE convention (no double-run)

**Given** the RPC is `SECURITY DEFINER` **When** audited **Then** it resolves the tenant from the JWT inside the function (never a parameter) and `EXECUTE` is revoked from `anon`/`authenticated`

### Story 12.2: Report module skeleton + request API (fenzit-be)

As an **owner**,
I want to submit a report request and see its status and history through the API,
So that report generation starts and stays trackable.

**Acceptance Criteria:**

**Given** `POST /api/v1/reports` with valid body (type, IST-valid range ≤ 92 days inclusive, ≤ 25 tenant technicians) **When** submitted by an owner with `x-idempotency-key` **Then** `201 { id, status: queued, createdAt }`; a replay with the same key returns the original response, never a duplicate row

**Given** an invalid create (range > 92 days, start > end, future date on the IST clock, unknown type, > 25 or non-tenant/non-technician ids) **When** submitted **Then** 400 with the mapped code (`report_range_too_large`, `report_too_many_technicians`, …)

**Given** 3 requests already queued+generating for the tenant **When** a 4th is submitted concurrently **Then** `report_in_flight_limit` — and the count+insert is one transaction, so racing submissions cannot exceed the cap

**Given** `GET /api/v1/reports/:id` **When** called by the owning tenant **Then** `{ id, reportType, params, status, createdAt, completedAt, file?, error? }`; when `ready`, `file` carries a fresh presigned URL (TTL from `REPORT_PRESIGN_TTL_SECONDS`), size, filename; another tenant's id → 404; transient presign failure → 500 `report_presign_failed`; technician role → 403

**Given** `GET /api/v1/reports` **When** called **Then** keyset-paginated `PaginatedResponse` (page 20, cursor on `(created_at, id)`), newest first; a `failed` report is a normal 200 row with `error_code`, not an ApiError

**Given** the registry **When** a definition is inspected **Then** registering a report type = one definition file + one registry entry, with zero engine/API changes; unknown `report_type` → 400; module imports only `common/` + `storage`

**Given** config **When** the app boots **Then** `REPORT_PRESIGN_TTL_SECONDS` (600), `REPORT_POLL_INTERVAL_SECONDS` (5), `REPORT_MAX_JOBS` (5000), `REPORT_MAX_ATTEMPTS` (3) are in the Joi env schema

### Story 12.3: Generation engine + worker (fenzit-be)

As an **owner**,
I want my queued report to generate automatically and finish with a stored PDF or a clear failure,
So that I never have to retry or wonder.

**Acceptance Criteria:**

**Given** the in-process worker **When** it runs **Then** it polls `queued` rows every `REPORT_POLL_INTERVAL_SECONDS` with concurrency capped (default 1), claims via the RPC, and drives `queued → generating → ready|failed`

**Given** a claimed request **When** generation succeeds **Then** the PDF is uploaded to R2 at `{tenantId}/reports/{requestId}.pdf` via `PutObjectCommand` **and** the upload strictly completes before the ready stamp; `r2_key` + `file_size_bytes` + `completed_at` stamp; ready stamp + `notifications` insert commit in one transaction

**Given** the terminal stamp **When** it commits **Then** the notification goes only to `requested_by` with the report id + status (no URLs); a notification failure after commit is logged and dropped (history polling is the fallback)

**Given** any generation failure **When** it happens **Then** the row becomes `failed` with a stable `error_code` — never a partial or linkless "ready"

**Given** a deploy killed the worker mid-render **When** the next poll runs **Then** the row stranded past its `locked_until` lease is re-claimed (`attempt_count++`) and re-runs, re-uploading to the same deterministic R2 key; exceeding `REPORT_MAX_ATTEMPTS` → `failed` with `report_generation_failed`

**Given** a failure **When** logged **Then** logs carry tenant/request context and never secrets; all worker data access is scoped to the claimed row's tenant

### Story 12.4: PDF template machine (fenzit-be)

As a **report template author**,
I want a shared brand kit and a `PdfRenderer` port,
So that every report is branded consistently and the renderer can be swapped later without touching templates.

**Acceptance Criteria:**

**Given** the brand kit module **When** inspected **Then** it owns the Fenzit logo (`assets/fenzit-logo.png` moved into the module), Inter Regular/SemiBold/Bold as base64 vfonts, theme tokens (`#1A56DB` primary, `#06956F` done, `#D97706` scheduled, `#C92A2A` cancelled, `#F9FAFB` bg, `#111827` text, cool-gray borders), and the helpers `pageHeader(tenant, title, range)`, `summaryCardRow(cards)`, `jobsTable(rows)`, `pageFooter()`

**Given** any template **When** reviewed **Then** no template hard-codes a colour, font, or the logo — all styling flows from the kit

**Given** the `PdfRenderer` port **When** the pdfmake implementation renders a doc definition **Then** it returns valid PDF bytes with embedded fonts and the logo, auto-paginating long tables with repeating header rows and page numbers in the footer

**Given** the dependency tree **When** inspected **Then** only pdfmake is added (no Chromium/browser dep) and the module still imports only `common/` + `storage`

### Story 12.5: Technician Job Activity report (fenzit-be)

As an **owner**,
I want a branded Technician Job Activity PDF for a date range,
So that I can review technician performance without opening the app's data.

**Acceptance Criteria:**

**Given** the definition **When** registered **Then** it carries the stable type id, label, and param schema; the engine, API, and migration needed zero changes

**Given** a request **When** the fetcher runs **Then** it pulls tenant-scoped jobs whose `scheduled_start` falls inside the range (IST day bounds, `end_date` inclusive), joined to customers, skills, users, and attachment counts; exceeding `REPORT_MAX_JOBS` fails with `report_too_large` — never silent truncation

**Given** the PDF **When** rendered **Then** it shows the branded header (tenant company name + address, logo, title, date range, generated-at IST, footer with page numbers + generation timestamp + confidential note), the **Overall** summary card section first, then one section per selected technician (summary card + job table: job number, scheduled date, customer, skill, status, scheduled time, completed time, attachment count)

**Given** metrics **When** computed **Then** on-time % = on-time ÷ completed jobs (completed-only denominator, zero completed → "—", null `scheduled_end` excluded); total assigned, completed, cancelled, open (scheduled + in-progress), urgent completed, distinct customers served, photos + signatures captured all match PRD §4 definitions

**Given** a selected technician with zero jobs in range **When** rendered **Then** their section still appears (zeroed summary card, empty-state table row); **Given** the selection has zero jobs overall **When** rendered **Then** the request succeeds as `ready` with an explicit "No jobs in this period" page

**Given** the module README **When** read **Then** it documents the extensibility checklist (add-a-report-type in steps, zero engine changes) and the NFR2 benchmark is **measured** (≤ 1,000 jobs < 10 s on the weakest box) and recorded

### Story 12.6: Owner Reports screen (fenzo-app)

As an **owner**,
I want a Reports screen where I request a report and download finished ones,
So that I can get my PDFs from my phone.

**Acceptance Criteria:**

**Given** the owner nav tree **When** opened **Then** a "Reports" tile on the Account (More) tab navigates to the new `Reports` route; technician accounts have no entry

**Given** the request form **When** used **Then** start/end date pickers are IST-correct (existing `istDate` utilities + datetimepicker pattern), technician multi-select uses the existing `MultiSelect` sheet (empty = all technicians), and Generate is disabled until valid (range ≤ 92 days, start ≤ end, not future)

**Given** Generate **When** tapped **Then** it POSTs with a **fresh `x-idempotency-key`** per attempt (never a stale 24 h replay), is guarded against double-submit, and the user lands on the history view

**Given** the history list **When** shown **Then** requests appear newest first with status chips (`Generating…` / `Ready` / `Failed`); while any item is non-terminal the feature polls the **list endpoint** every 5 s and stops when all terminal or the screen is left; a report-ready Realtime notification also triggers a store refresh

**Given** a Ready item **When** tapped **Then** the app fetches the status endpoint (mints a fresh presigned URL) and opens it with `Linking.openURL` via a `utils/linking.ts` helper, with a graceful failure toast; tapping a Failed item shows mapped error copy and never attempts to open a PDF

**Given** the screen states **When** rendered **Then** first-load spinner, `InlineError` + Retry, `EmptyState` ("Generate your first report"), per-item error copy mapped from `error_code`; a new `useReports` store follows the tiered store pattern and registers in the reset registry

---

**Story sequencing note:** backend stories 12.1–12.5 (fenzit-be) merge/deploy before frontend story 12.6 (fenzo-app) per the CLAUDE.md cross-repo ordering rule. Test suites are written only after the user confirms the feature on device (project test-timing rule).