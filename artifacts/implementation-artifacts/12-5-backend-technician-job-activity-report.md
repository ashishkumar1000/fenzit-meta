# Story 12.5: Backend — Technician Job Activity report (fetcher + metrics + template)

Status: ready-for-dev
baseline_commit: 18ea107 (fenzit-be) + the staged 12-1..12-4 work on top of it
(migrations 48–52, full `src/reports/` module incl. brand kit + PdfmakeRenderer — uncommitted)

> **Implemented 2026-09-20.** Fetcher (`technician-job-activity.data.ts`:
> IST day bounds with exclusive upper bound, paged jobs query with embedded
> customer/skill names, chunked technician-name + attachment-count reads,
> `REPORT_MAX_JOBS` → `report_too_large`), metrics (`…metrics.ts`, pure),
> flags (`…flags.ts`, pure), template (`…template.ts`) and the definition
> wired end to end. `ReportFetchContext` gained `maxJobs` (pipeline passes
> `REPORT_MAX_JOBS` from ConfigService — definitions stay DI-free).
>
> **User-directed additions mid-story** ("include every important detail +
> flag concerns the owner should look into"): a **Needs attention** section
> (overdue open jobs, urgent jobs still open, completed jobs with no
> photo/signature proof, cancellations) and richer content — scope line in
> the header ("All technicians · N jobs in range"), completed date+time in
> the table, the full 8-metric set as two card rows at every level. Kit grew
> `sectionTitle` / `emptyStateRow` / `emptyStateBlock` / `flagList` and an
> optional `pageHeader` subtitle (kit still owns all styling).
>
> Typecheck clean. **Verified end to end 2026-09-20**: a probe request
> (worker path) ran claim → fetch → render → R2 upload (44.8 KB PDF at the
> deterministic key) → `ready` stamp → `report_ready` notification; probe
> row + notification cleaned up afterwards. Visual PDF check via the user.
>
> Two follow-up user requests, both shipped in the same pass:
> (a) plain English throughout (title "Technician Job Report", simple
> metric labels, "Planned time"/"Finish time"/"Proofs" column headers,
> full-sentence flag details); (b) Lucide icons in the PDF — the same
> icons the FE renders via lucide-react-native, extracted to
> `brand-kit/assets/icons/*.svg` (ISC license) and rendered through a new
> kit file `brand-icons.ts` as recolored pdfmake `svg` nodes (vector, no
> raster step): one icon per metric card, per section title and per
> "Needs attention" row.
>
> Two runtime fixes found during verification (both outside the story's
> planned scope): (1) `PdfmakeRenderer` used named ESM imports from
> `'pdfmake'`, but pdfmake 0.3's server entry is a CJS singleton
> (`module.exports = new pdfmake()`) — named imports fail at module load in
> Bun; now requires the instance directly and types the surface locally.
> (2) Brand-kit assets (logo PNG, Inter TTFs) weren't copied to `dist/`,
> crashing any compiled run at `brand-assets.ts` module load;
> `nest-cli.json` now copies `brand-kit/assets/**/*` to `dist/src/`
> (per-asset `outDir`) so `__dirname/assets` resolves next to the compiled
> JS in dev, prod and from-source runs.
>
> **UI-polish pass 2026-09-20** (BMAD UX critique + pdfmake research agents):
> metric cards rebuilt as light-fill `columns` cards with a coloured top
> accent bar; table headers quieted to the brand tint; job table → 7 fixed-
> width columns (Date + Planned time merged, "20 Sep 16:30" dates); status
> cells tinted with their status colour; zebra-only body (per-row rules
> dropped); flag rows severity-coloured (urgent red / no-proof amber /
> cancelled muted) with a per-item `color` on `FlagItem`; sentence-case card
> labels with larger values; short header accent bar instead of a full-width
> rule; section titles glued to their first block via small `unbreakable`
> stacks (pdfmake has no keep-with-next). `page-chrome.ts` (~440 lines) split
> into `page-header.ts` / `summary-cards.ts` / `job-table.ts` / `sections.ts`
> behind a `page-chrome.ts` barrel — templates still import from one place.
> Typecheck clean; visual PDF check via the user.

## Story

As an **owner**,
I want a branded Technician Job Activity PDF for a date range,
So that I can review technician performance without opening the app's data.

## Acceptance Criteria

1. **Definition completed, minimal engine change (FR9/NFR6)** — **Given** the
   definition **When** registered **Then** `technician-job-activity.definition.ts`
   now implements `fetcher` + `buildDocument`; the engine gains `maxJobs`
   parameter in `ReportFetchContext` (passed from `REPORT_MAX_JOBS` config
   via the pipeline), and definitions stay DI-free; no API or migration changes.
2. **Tenant-scoped fetcher (FR16)** — **Given** a claimed request **When** the
   fetcher runs **Then** it pulls jobs whose `scheduled_start` falls inside the
   IST day bounds (`start_date` 00:00 IST inclusive → `end_date`+1 00:00 IST
   exclusive, so `end_date` is inclusive), joined to customers, skills and
   technician users, with photo/signature attachment counts per job. **Edge case:**
   if the tenant has zero technicians and empty `technician_ids` was passed (meaning 
   "all technicians"), the create endpoint rejects with 400 before reaching this fetcher.
   **Pagination strategy (Option A):** The fetcher loops through jobs in pages 
   (PostgREST's default 1000-row limit) — on each page, check cumulative total 
   against `REPORT_MAX_JOBS` (5000). The fetcher accepts **up to and including** 
   5000 rows; if cumulative total exceeds 5000, fail with `report_too_large` 
   (never silent truncation). Once all jobs fit under the cap, batch-fetch all 
   technician names (chunked, per AC 2 task) and all attachment counts (chunked) 
   in bulk — the fetcher returns the complete dataset for the PDF.
3. **Report layout (FR15)** — **Given** the PDF **When** rendered **Then** it
   shows the branded header (tenant company name + address, logo, report
   title, date range, IST generation timestamp in the footer), the **Overall**
   summary-card section first, then one section per selected technician
   (summary card scoped to that technician + job table: job number, scheduled
   date, customer, skill, status, scheduled time, completed time, attachment
   count).
4. **Metrics match PRD §4 (FR17)** — **Given** metrics **When** computed
   **Then** on-time % = on-time completed ÷ completed jobs (completed-only
   denominator, zero completed → "—"; on-time = `completed_at <= scheduled_end`; 
   jobs with null `scheduled_end` excluded entirely from on-time calculation — 
   excluded from both numerator and denominator); total assigned, completed, 
   cancelled, open (scheduled + in_progress), urgent completed, distinct 
   customers served (all statuses), photos + signatures captured.
5. **Edge cases (FR18)** — **Given** a selected technician with zero jobs in
   range **When** rendered **Then** their section still appears (zeroed
   summary card, empty-state table row); **Given** the selection has zero jobs
   overall **When** rendered **Then** the request succeeds as `ready` with an
   explicit "No jobs in this period" page — success, not failure. **Tenant zero 
   technicians:** if the tenant has zero technicians, create endpoint (12-2) 
   rejects with 400 before any request reaches this story — no PDF is generated 
   for an empty tenant.

## Tasks / Subtasks

- [ ] Task 1: Fetcher (AC: 2)
  - [ ] `registry/technician-job-activity.data.ts` — data shapes + the
        fetcher: tenant row (`company_name`, `address`), paged jobs query
        (embeds `customers(name)`, `skills(name)`), chunked technician-name
        fetch, chunked attachment-count fetch (photo/signature), IST bounds.
- [ ] Task 2: Metrics (AC: 4)
  - [ ] `registry/technician-job-activity.metrics.ts` — `computeMetrics(jobs)`
        returning the PRD §4 metric set (pure function over fetched jobs).
- [ ] Task 3: Template (AC: 3, 5)
  - [ ] `registry/technician-job-activity.template.ts` — `buildDocument`
        composing only brand-kit helpers (pageHeader / summaryCardRow /
        jobsTable / pageFooter); Overall first, then per-technician sections;
        zero-jobs and empty-technician content rules.
  - [ ] Kit additions (kit still owns all styling): `sectionTitle`,
        `emptyStateRow`, `emptyStateBlock` in `page-chrome.ts`; jobsTable
        status-colour lookup normalizes display labels ("In progress" →
        `in_progress`).
- [ ] Task 4: Wiring (AC: 1)
  - [ ] `ReportFetchContext` gains `maxJobs` (from `REPORT_MAX_JOBS` via
        ConfigService in the pipeline) — definitions stay DI-free.
  - [ ] Definition implements canonical field names: `fetcher` and
        `templateBuilder` (per 12-3 AC 7 standardization, not fetchData/buildDocument).
- [ ] Task 5: Docs + extensibility checklist (AC: 1, NFR6)
  - [ ] `src/reports/README.md` — first report shipped, fetcher/metrics/
        template layout, measured NFR2 note when measured. **Add the 
        extensibility checklist** (NFR-6 from the PRD): step-by-step 
        instructions for adding a second report type (new definition file, 
        registry entry, param schema, fetcher, template) that require **zero** 
        engine/API/migration changes. Verify checklist by creating a 
        follow-up story outline (not implemented, just outlined).
  - [ ] `bun run typecheck` clean; end-to-end live verification (real
        request → worker → PDF in R2 → ready row + notification), with user
        eyeballing the PDF.

## Dev Notes

### Repo and tooling facts

- Repo is **fenzit-be**; work on `main`; review/commit parked (build now).
- **Schema verification required:** Before writing the fetcher, verify that 
  the following schema facts from this story's dev notes match the actual 
  schema (created in 12-1's migration and validated in 12-2):
  - `jobs` table: `job_number`, `technician_id` (single, NOT NULL), 
    `scheduled_start`, `scheduled_end` (nullable), `completed_at`, 
    `priority` (normal|urgent), `status` (scheduled|in_progress|completed|cancelled), 
    `customer_id`, `skill_id` (nullable)
  - `customers.name`, `skills.name` (resolved via job FK)
  - `users.name` for technician names
  - `attachments.attachment_type` IN ('photo','signature')
  - Cross-check these against the actual `schema.sql` or migrations before 
    finalizing the fetcher query.
- All DB reads via the admin Supabase client in `ReportFetchContext` — the
  module never imports from `jobs/`/`customers/` etc. (only shared enums
  like `JobStatus` values are mirrored, not imported, if needed — check
  whether importing from `src/jobs/enums` violates NFR5; prefer local
  literal unions in the data file).
- `REPORT_MAX_JOBS` (default 5000) is already in the Joi schema
  (app.module.ts:90); the pipeline must pass it into the fetch context.
- Schema facts (verified in code): `jobs` has `job_number`,
  `technician_id` (single, NOT NULL), `scheduled_start`, `scheduled_end`
  (nullable), `completed_at`, `priority` (normal|urgent), `status`
  (scheduled|in_progress|completed|cancelled), `customer_id`, `skill_id`
  (nullable, FK to skills); `customers.name`; `skills.name` (jobs.service
  embeds `skills(id, name)` so the relationship resolves); `users.name` for
  technicians; `attachments.attachment_type` IN ('photo','signature'),
  keyed by `job_id`; `tenants.company_name`, `tenants.address`.

### Design decisions already made

- `ReportFetchContext` carries `maxJobs` — the definition files stay pure
  functions over the context; no ConfigService in the registry layer.
- Data model: fetcher returns `{ tenant, range, technicians, jobs }` — the
  template needs the range for the header, so the fetcher (which sees
  params) includes it; `buildDocument(data)` stays single-argument.
- IST day bounds computed from the calendar dates directly
  (`new Date('YYYY-MM-DDT00:00:00+05:30')`), no date library (12-2 pattern).
- Metrics are a pure module over `FetchedJob[]` so tests later (after device
  confirmation, per the test-timing rule) need no DB.
- On-time: `completed_at <= scheduled_end`; the "—" rule covers both
  zero-completed and all-null-`scheduled_end` cases.
- **Pagination (not user-facing):** Report generation is one-off bulk fetch.
  The fetcher loops through job pages (PostgREST's 1000-row default) until
  it has all jobs, checking total against REPORT_MAX_JOBS on each iteration.
  Once all jobs fit (under 5000), it bulk-fetches names + counts in chunked
  batches. There is no "next page" returned to a caller; the complete dataset
  is assembled and returned as-is for the PDF.

### References

- [Source: artifacts/planning-artifacts/epics-reports.md — Story 12.5]
- [Source: PRD §4 (report content + metric definitions), §5.2 FR15–FR18;
  addendum §5 — layout/metric notes]
- [Source: artifacts/implementation-artifacts/12-3-...md, 12-4-...md] — the
  engine seam (fetchData/buildDocument) and the brand-kit helpers this story
  composes.