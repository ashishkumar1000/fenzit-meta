---
title: "PRD: Report Module — Owner PDF Reports (async, R2, pluggable engine)"
status: final
created: 2026-09-18
updated: 2026-09-18
scope: cross-repo (fenzit-be primary, fenzo-app owner UI)
owner: Ashish Kumar
---

# PRD: Report Module — Owner PDF Reports

## 0. Document Purpose

This PRD defines a **new independent report module** in `fenzit-be` plus the
owner-facing **Reports screen** in `fenzo-app`. An owner requests a branded PDF
report about the people working for them (their technicians) over a date range;
the backend generates it asynchronously, uploads it to Cloudflare R2, and hands
back a download link. Tenants are strictly isolated — an owner can only ever
see/download reports about their own tenant's data.

The module is designed as a **pluggable report engine**: today it ships one
report type (Technician Job Activity); future report types (customer report,
business summary, …) are added by registering a new report definition — never
by rewriting the engine, the API, or old reports. The module is also kept
**structurally independent** so it can later be lifted out of the NestJS app
and run as a standalone service with minor changes.

Supporting research (PDF engine comparison, architecture patterns, alternatives
considered) lives in `addendum.md` alongside this PRD.

## 1. Vision

An owner opens the Reports screen, picks a date range and optionally narrows to
specific technicians, and taps Generate. The app confirms the request
immediately and shows it as "generating"; moments later the report is ready and
the owner downloads a clean, company-branded PDF — summary numbers up top, a
per-technician breakdown below — usable for their business decisions. Adding a
second or third kind of report later is a matter of registering a new
definition, not a new project.

## 2. Users and Stakeholders

| User | Need |
|---|---|
| **Owner** (primary) | See what their technicians did over a period — jobs completed, cancelled, urgent work, timeliness — as a shareable branded PDF. |
| **Technician** | No access. Reports are owner-only. |
| **Future / platform** | Developers adding new report types; a future standalone deployment of the module. |

### 2.1 Glossary

| Term | Meaning |
|---|---|
| **Report definition** | One small file per report type: stable `type` id, label, param schema, tenant-scoped data fetcher, template reference. Registered in the registry (FR-5). |
| **Engine** | The machinery that knows nothing about specific reports: state machine, claim, pipeline, R2 upload, API (FR-4, FR-7). |
| **Registry** | The `report_type → definition` map the engine looks up at run time. |
| **Template** | A report's layout file (cards, tables, section order) — structure only, no styling (FR-T2). |
| **Brand kit** | The one shared file owning the logo, theme tokens, fonts, and page chrome used by every template (FR-T1). |
| **`PdfRenderer` port** | The rendering interface (`render(doc) → PDF bytes`) behind which pdfmake (v1) or a future implementation sits (FR-6). |
| **Claim / lease** | The atomic `queued → generating` transition that stamps a `locked_until` lease, so a crashed worker's row can be re-claimed and never double-run (FR-7). |
| **Presigned URL** | Short-lived R2 read URL minted per request (FR-2). |

## 3. Scope

**In scope (this phase):**
- `fenzit-be`: a new self-contained `reports` module — request/state machine, pluggable report registry + engine, pdfmake-based PDF renderer, R2 upload, REST API (create, get status, list history), ready notification row, DB migration (`report_requests`).
- `fenzo-app`: owner-only Reports feature — entry tile in the Account tab, request form (date range + optional technician multi-select), request history list with live status, polling while work is pending, open-PDF via presigned URL, full loading/error/empty states.

**Out of scope (deferred):**
- Scheduled/recurring reports, email/WhatsApp delivery, CSV export.
- Additional report types (listed in §8 as the extension roadmap — designed for, not built).
- True device push (FCM/APNs) — readiness uses polling + the existing Realtime-backed in-app notification.
- Report retention policy / auto-deletion of R2 objects (pre-launch: reports persist; policy added later).
- Chart graphics inside the PDF (unlocked with the Puppeteer renderer swap, §8).

## 4. First Report: Technician Job Activity Report

Content is deliberately **summary-first, not a data dump** — the owner gets
business signal, and new sections can be added to the definition later.

**Layout (single PDF, one section per selected technician, "Overall" first):**

1. **Branded header** — tenant company name and address; the Fenzit logo
   from the brand kit (styled text header band as fallback); report title;
   date range; generated-at (IST); Fenzit wordmark footer.
2. **Overall summary card** — across the selection: total jobs assigned,
   completed, cancelled, still open (scheduled/in_progress), urgent jobs
   completed, on-time completion %, distinct customers served, photos +
   signatures captured.
3. **Per-technician section** — the same summary card scoped to that
   technician, followed by a **job table**: job number, scheduled date, customer
   name, skill, status, scheduled time, completed time, attachment count.
4. **Footer** — page numbers, generation timestamp, confidential note.

**Data source (tenant-scoped):** jobs whose `scheduled_start` falls inside the
date range (IST day bounds), joined to `customers` (name), `skills` (name),
`users` (technician name), with attachment counts from `attachments`.
On-time = `completed_at` ≤ `scheduled_end` (metric defined below).
([ASSUMPTION] Range filters on `scheduled_start` — the alternative, filtering
on activity events in the period, is heavier and ambiguous; revisit only if
owners ask.)

**Metric definitions ([ASSUMPTION] — shape decided now, tuned after first use):**

- **On-time %** = on-time completed jobs ÷ *completed* jobs in range
  (completed-only denominator; open and cancelled jobs are excluded). Zero
  completed jobs → the card shows "—", never 0% or NaN.
- A completed job with a null `scheduled_end` (data gap) is excluded from the
  on-time metric.
- **Summary totals:** total assigned = all jobs in range; completed and
  cancelled = by status; open = scheduled + in_progress; urgent jobs completed
  = `priority = 'urgent'` among completed (the source field for "urgent" is
  `jobs.priority`); distinct customers served = all statuses; photos +
  signatures captured = `attachments` with `type IN ('photo', 'signature')` on
  those jobs.
- A selected technician with **zero jobs in range still gets their section**
  (zeroed summary card, empty table with an empty-state row) — the owner
  explicitly asked for them.
- A selection with **zero jobs overall** → `ready` PDF with an explicit
  "No jobs in this period" page. The request succeeded; this is not a failure.
- **Date semantics:** `end_date` is inclusive; the 92-day cap counts days
  inclusively; "not in the future" is evaluated on the **IST clock** (matching
  `utils/istDate`) — never the UTC server clock, which would reject a
  same-day IST range for part of the day.
- **Header identity:** tenant `company_name` and `address` from the
  `tenants` table; v1 renders no tenant-supplied logo — the Fenzit logo from
  the brand kit leads the header (styled text band fallback unchanged).

## 5. Features — Backend (report module)

### 5.1 Report request API

- **FR-1 — Create report request.** `POST /api/v1/reports`, owner role only.
  Body: `report_type` (default `technician_job_activity`), `start_date`,
  `end_date` (ISO dates; validated, max range 92 days, start ≤ end, not in the
  future), `technician_ids[]` optional — absent/empty means *all technicians of
  the tenant*. Validates IDs belong to the tenant and are technicians. Creates
  a `report_requests` row (`status: queued`), returns `201 { id, status, createdAt }`.
  Honours the existing `x-idempotency-key` convention (replays the same
  request, never a duplicate PDF).
  - **Caps:** max 25 `technician_ids` per request; the in-flight cap (NFR-3)
    enforced **atomically** — count + insert in one transaction, so concurrent
    submissions cannot exceed it; max-jobs cap at fetch time (config, default
    5,000) — exceeding fails the request (`report_too_large`), never silent
    truncation.
  - **v1 error codes:** `report_range_too_large`, `report_too_many_technicians`,
    `report_in_flight_limit`, `report_too_large`, `report_generation_failed`,
    `report_presign_failed`.
  - **Idempotency:** duplicate protection only — a user-visible retry uses a
    fresh key (FR-13 generates one per submit attempt), so a failed request is
    never hard-stuck behind its key.
- **FR-2 — Get report status.** `GET /api/v1/reports/:id`, owner role only,
  tenant-scoped. Returns `{ id, reportType, params, status, createdAt,
  completedAt, file?, error? }`. When `status: ready`, `file` carries a
  **fresh short-lived presigned R2 URL** (default TTL 10 min, config-driven),
  file size, and filename. Never leaks another tenant's row (404). If the row
  is `ready` but presigning transiently fails → `500` with
  `report_presign_failed` (FE offers Retry; FR-13).
- **FR-3 — List report history.** `GET /api/v1/reports`, owner role only,
  tenant-scoped, keyset pagination (existing `PaginatedResponse` envelope),
  newest first: id, type, range, technician count, status, `error_code`,
  createdAt, completedAt — `error_code` lets the FE render *why* an item
  failed (a failed report is a 200 with `status: failed`, not an ApiError).
  Page size 20; keyset cursor = last `(created_at, id)`.

### 5.2 PDF template machine

The PDF look is built from two layers, so branding lives in exactly one place
and a new report never re-invents styling:

- **FR-T1 — Shared brand kit (one file, used by every report).** Owns the
  Fenzit logo (copied from `fenzo-app/src/assets/branding/logo@3x.png` —
  360×360 PNG), the project theme tokens, fonts, and the reusable page
  chrome: branded header band, section-card styles, table styles, status
  colours, and the footer (page numbers, generation timestamp, Fenzit
  wordmark). No template ever hard-codes a colour, font, or the logo —
  changing brand look once updates every report.
- **FR-T2 — One template file per report type.** A template describes its
  report's layout (summary cards, tables, section ordering) as a structured
  document and pulls *all* styling from the brand kit. `technician_job_activity`
  ships the first template. Tomorrow's new report = new definition + new
  template file + one registry entry — no changes to the kit, engine, or old
  templates.

**Theme (from the Fenzit design system, applied to the PDF):** Primary
`#1A56DB`, Done `#06956F`, Scheduled `#D97706`, Cancelled `#C92A2A`,
background `#F9FAFB`, text `#111827`, Inter font family embedded as static
weights, light cool-gray borders/shadows, rounded card corners.

### 5.3 Generation engine

- **FR-4 — Async generation pipeline.** An in-process worker picks up
  `queued` requests (poll-backed, small concurrency cap) and runs the pipeline:
  `queued → generating → (ready | failed)`. On ready it uploads the PDF to R2
  (key pattern `{tenantId}/reports/{requestId}.pdf` via a direct
  `PutObjectCommand` added to `StorageService`), stores `r2_key` +
  `file_size_bytes`, and stamps `completed_at`. On failure it marks `failed`
  with a stable `error_code` — never a partial or linkless "ready" state.
  Failures are logged with tenant/request context but never leak secrets.
  - **Worker poll:** interval default 5 s (config-driven) — the BE worker
    poll, distinct from the FE list polling (FR-11).
  - **Terminal ordering:** R2 upload strictly before the ready stamp; ready
    stamp + notification insert commit in one transaction; a notification
    failure after commit is logged and dropped (history polling is the
    fallback UX). If the DB update fails after a successful upload, lease
    recovery re-runs the request and re-uploads to the same deterministic
    key, so the R2 orphan self-heals.
  - **Crash recovery:** the claim stamps a `locked_until` lease (FR-7); the
    poll loop re-claims rows whose lease has expired, tracked with
    `attempt_count`; max attempts (default 3) → `failed` with
    `report_generation_failed`. Every backend deploy kills the in-process
    worker mid-render, so this recovery path is routine, not exceptional
    (tested per NFR-7).
- **FR-5 — Pluggable report registry.** Each report type is a **definition
  unit**: stable `type` id, label, param schema (validated on FR-1), a
  tenant-scoped data fetcher, and a template/payload builder for the renderer.
  The engine (state machine, R2, API) knows nothing about specific reports.
  Registering a new report type = one definition file + one registry entry;
  zero engine changes. The module's only cross-domain dependencies are the
  shared `common/` layer and `storage` — nothing imports from `jobs/`,
  `customers/`, etc. (data access goes directly through the Supabase client).
- **FR-6 — PDF rendering.** v1 renderer implemented with **pdfmake** behind a
  `PdfRenderer` port (interface) owned by the module: report templates (FR-T2)
  emit a structured document through the brand kit (FR-T1); the renderer turns
  it into PDF bytes with the logo and Inter fonts bundled. Swapping in a
  different renderer implementation (Puppeteer / Gotenberg) later touches only
  the renderer adapter — see §8.

### 5.4 Data, state and isolation

- **FR-7 — `report_requests` table.** Migration adds: `id`, `tenant_id`,
  `requested_by` (FK users), `report_type`, `params` (jsonb, check-constrained
  to an object), `status` (`queued | generating | ready | failed`),
  `locked_until` (lease timestamp for crash recovery), `attempt_count`,
  `r2_key` (unique, nullable), `file_size_bytes`, `error_code` (nullable),
  `created_at`, `completed_at`. Deny-by-default RLS.
  - **Claim RPC** — performs the queued→generating transition; runs as
    `SECURITY DEFINER`, resolves the tenant from the JWT *inside* the
    function (never a client-supplied parameter), and has `EXECUTE` revoked
    from `anon`/`authenticated` (service-role-only call path, matching the
    existing RPC discipline) — an RLS-bypassing RPC callable by any
    authenticated user would be an isolation hole. Stamps `locked_until`
    (the lease FR-4 recovers from) using the repo's `PT<status>` SQLSTATE
    convention, so a crashed worker never double-runs a request.
- **FR-8 — Ready/failed notification.** On terminal status, insert a row in
  the existing `notifications` table — recipient: the `requested_by` user,
  not all owners — in the same transaction as the terminal status stamp
  (FR-4); the existing Realtime trigger fans it out to the bell/notification
  feed. Payload carries the report id and status; no URLs in the payload.
- **FR-9 — Tenant isolation everywhere.** Every read is scoped by the JWT's
  `tenantId` at the service layer and by RLS at the DB layer; technician role
  gets 403 on all report endpoints. Presigned URLs are minted only for rows
  matching the caller's tenant.

## 6. Features — Frontend (fenzo-app)

- **FR-10 — Reports screen (owner nav tree only).** New route `Reports` in the
  owner stack; entry via a "Reports" tile on the Account (More) tab (existing
  tile pattern). Screen shows: request form — date range (start/end pickers,
  composed from the existing `@react-native-community/datetimepicker` pattern,
  IST-correct via `utils/istDate`), technician multi-select (existing
  `MultiSelect` sheet; empty = all technicians), and a Generate button with
  proper disabled/`canSubmit` gating.
- **FR-11 — Report history list with live status.** Requests are shown newest
  first with status chips (`Generating…` / `Ready` / `Failed`). While any item
  is non-terminal, the feature polls the **list endpoint** (`GET
  /api/v1/reports`) every **5 s** and stops polling when everything is
  terminal or the screen is left (one mechanism — no per-item `:id` polling;
  one free-tier-friendly request per tick). A report-ready notification
  arriving over Realtime also triggers a store refresh (existing
  `OwnerRealtimeBridge` pattern).
- **FR-12 — Open the PDF.** Tapping a Ready item fetches the status endpoint
  (mints a fresh presigned URL) and opens it with `Linking.openURL` (system PDF
  viewer) via a helper in `utils/linking.ts`, with graceful failure toast.
  Tapping a Failed item shows the mapped error copy (from `error_code`) — it
  never attempts to open a PDF. No new download/viewer dependency.
- **FR-13 — States per design system.** First-load spinner, `InlineError` +
  Retry on failure, `EmptyState` for no reports yet ("Generate your first
  report"), per-item error copy mapped from `error_code` values (FR-3); submit guarded
  against back-navigation while in flight. New `useReports` store follows the
  tiered store pattern and registers in the reset registry. Each submit
  attempt generates a **fresh `x-idempotency-key`** — a user-visible retry is
  a new request, never a 24 h stale replay of a failed one.

## 7. Non-Functional Requirements

- **NFR-1 — Resource safety.** Generation adds ≤ ~50 MB steady memory;
  concurrency capped (default 1 concurrent render); Chromium-free. Must run
  within Render free-tier limits (512 MB). Head-of-line blocking across
  tenants (one render delays the next) is accepted at v1 scale; revisit if
  NFR-2 is violated in practice.
- **NFR-2 — Performance.** A report of ≤ 1,000 jobs generates and uploads in
  < 10 s — **measured** on the free-tier instance in tests (0.1 CPU is the
  weakest box this feature will ever run on; verified, not assumed). ≤ 1,000
  jobs is the benchmark case, not an enforced limit — the enforced oversize
  guard is the FR-1 jobs cap (`report_too_large`).
- **NFR-3 — Range & abuse caps.** Max date range 92 days; max in-flight
  (queued+generating) requests per tenant: 3 — further requests rejected with
  a clear error code until earlier ones finish.
- **NFR-4 — Security.** Owner-only endpoints; tenant scoping at service + RLS;
  presigned URLs short-lived and minted per request; PDFs contain customer
  names/phones — never exposed cross-tenant; no service-role keys anywhere in
  the app.
- **NFR-5 — Module independence.** `src/reports/` is self-contained (module,
  controller, service, engine/, reports-definitions/, dto/, renderer/). It can
  be lifted to a standalone service with only: config/env wiring, DB client,
  R2 credentials, and the notification insert moved to an outbox/interface.
- **NFR-6 — Extensibility contract.** Adding a report type must not modify
  engine, API, migration, or any existing report definition; covered by a
  documented checklist in the module README.
- **NFR-7 — Tests.** Unit specs beside source (engine, registry, renderer,
  params validation); integration test for the state machine transitions and
  tenant isolation, matching repo conventions. The isolation suite includes
  the **RPC-privilege audit** (call the claim RPC with an owner JWT → refusal
  or no-op). The state-machine suite includes **crash recovery** (a row
  stranded `generating` past its lease → re-claimed → completes, or exhausts
  attempts → `failed`) and the **in-flight cap under concurrent
  submissions**.

## 8. Growth Path (documented, not built now)

1. **More report types** — register definitions: customer activity report,
   monthly business summary, outstanding-jobs report. No engine change.
2. **Renderer upgrade** — swap the pdfmake `PdfRenderer` implementation for a
   Puppeteer/HTML one (paid Render tier) or a Gotenberg service (module as its
   own machine) behind the same port; definitions stay untouched.
3. **Scheduling & delivery** — recurring reports (cron), email/WhatsApp
   delivery channels: the request/state model already carries `report_type`
   and `params`, so a scheduler is just another producer of requests.
4. **Retention policy** — lifecycle rules for `reports/` keys once there is a
   reason to expire them.

## 9. Success Metrics

- Owner requests a report and can open the PDF within 60 s end-to-end (p95
  ≤ 45 s).
- Zero cross-tenant reads/downloads in the isolation integration test.
- A second report type is added with **zero** changes under `src/reports/engine/`
  or to the API surface (validated in a follow-up story's acceptance) — and
  the new definition adds no new cross-module imports and no shared state
  (counter-constraint: extensibility in letter *and* substance).

## 10. Assumptions and Open Questions

- **[ASSUMPTION] One combined PDF** with an Overall + per-technician sections,
  even when the owner selects one technician (single section, no Overall
  card). Revisit if owners prefer one PDF per technician.
- **[ASSUMPTION] Date range filters on `scheduled_start`** (IST day bounds).
- **[ASSUMPTION] Range cap 92 days**, in-flight cap 3 (tune after first use).
- **[ASSUMPTION] Reports are kept in R2 indefinitely** for now (pre-launch);
  retention policy deferred.
- **[ASSUMPTION] Metric shapes (§4)** — on-time % over completed jobs only;
  zero completed → "—"; selected-but-empty technicians keep their section; a
  zero-job selection is a `ready` PDF with a "No jobs in this period" page.
  Tune after first use.
- **[ASSUMPTION] No delete/retry of past reports in v1** — regeneration is
  simply a new request; history grows until the deferred retention policy.
- **[ASSUMPTION] A system PDF viewer exists on the test devices** —
  `Linking.openURL` assumes one; the graceful-failure toast is the fallback
  (FR-12).
- **Logo: resolved 2026-09-18** — Fenzit logo copied from the app
  (`fenzo-app/src/assets/branding/logo@3x.png`, 360×360 PNG) into this run
  folder at `assets/fenzit-logo.png`; the build story moves it into the
  module's brand kit (see addendum §5).
- **[OPEN] Should owners see attachments/photos inline in future reports?**
  Deferred; only counts appear in v1.