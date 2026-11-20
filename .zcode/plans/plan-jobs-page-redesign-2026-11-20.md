# Jobs page redesign — the owner's Jobs Dispatch mockup, console pattern

## Context

Second page in the owner's console redesign queue (owner, 2026-11-17: "This are the design for JObs and attendence page … pick this one by one .. don't ask for my approval .. do extensive testing"). The mockup (recovered from the session image cache) shows the Jobs Dispatch page: greeting + page actions, tab strip with count badges, four stat tiles, a dark create-banner, and a "Jobs Pipeline" card — status chips, search, Skill + Priority dropdowns, Latest/Soonest sort, and a table of Job / Customer / Status / Step / Skill / Employee / Priority / Scheduled. Same design language the customers page shipped (BE 7c4ccc6, FE e2ae14c+a46eece).

Today the owner's Jobs tab fetches four cursor-scoped pages client-side (`fetchJobs` merge), searches only the loaded rows, has no server paging, no skill/priority filters, no stats tiles, no export. The redesign moves the owner's jobs tab onto a paged endpoint — the `/customers/page` playbook, BE-first.

**Mockup → reality calls** (mirroring the customers round): tile sub-analytics (↑14%, 98.2% on-time, avg-32-min), Quick Dispatch, Bulk Import, Dispatch Template, Live-Sync badge, auto-refresh, list/grid toggle, and checkbox bulk select have no product backing → deferred to the ledger. Tab labels stay Jobs / Approval / Activity / Report (content exists behind each). The dark create-banner ships with real copy and one "Create a job" button.

## BE (fenzit-be) — one migration + one endpoint

**Migration** `supabase/migrations/20261120000000_jobs_overview.sql` — `create or replace view public.jobs_overview with (security_invoker = true)`:

- `jobs LEFT JOIN customers (name) LEFT JOIN users (name) LEFT JOIN skills (name) LEFT JOIN workflow_templates (version, steps)` on `skill_id + workflow_template_version`
- Carries: id, job_number, tenant_id, customer_id, technician_id, service_location, scheduled_start, scheduled_end, status, priority, description, completed_at, current_step, skill_id, created_at, updated_at, customer_name, technician_name, skill_name, template_version, template_steps (jsonb)
- Searchable/sortable as plain columns — no PostgREST embed-filter guesswork. Grants hygiene block (customers precedent 20261117130000): revoke all from anon/authenticated, grant select to service_role.

**Endpoint** `GET /jobs/page` — `@Can('job.read_all')` (owner-facing; employees keep `job.read_own` and the untouched cursor `GET /jobs`), declared **between** `@Get()` and `@Get(':id')` (route-order comment precedent):

- `dto/jobs-page-query.dto.ts`: `page` (int ≥1), `pageSize` (1–100), `search` (1–80), `status` (IsIn the six statuses), `skillId` (@IsUUID('loose') — the repo-wide validator convention 20703e9), `priority` (IsIn normal/urgent), `sort` (IsIn `latest`/`soonest`; default `latest`)
- `getJobsPage()` mirrors `getCustomersPage` exactly: `filtered()` builder over `jobs_overview` with `.eq('tenant_id', …)`; search = sanitized `.or(job_number/description/service_location/customer_name/technician_name/skill_name .ilike.*)`; `Promise.all([paged list with count:'exact', stats])`; PGRST103 → head recount + empty page + honest total; id tiebreak on every sort; `soonest` = `scheduled_start asc, nullsLast`.
- `stats = { total, inProgress, pendingApproval, completed30d }` — four head-count queries in one `Promise.all` (tiny payloads, one wall-clock RTT; the whole-tenant fold would grow with job volume). `completed30d` = `completed_at >= now() − 30d`.
- Rows map to the existing FE `JobRow` shape: `currentStepIndex` computed server-side via `parseTemplateSteps(template_steps)` + `currentStepIndexForRead` (helpers already in `src/jobs/workflow-template.model.ts`), `workflowTemplate: { version: template_version, steps }`.

## FE (fenzit-web) — owner jobs tab onto the console pattern

- `companyApi.ts`: `fetchJobsPage(token, filters)` + `JobsPageResult`/`JobsStats` + `JobsSort`/`JobsStatusFilter` types (customers twins).
- `jobsUrl.ts` — clone of `customersUrl`: params `status` `q` `skill` `priority` `sort=soonest` `pageSize` `page`; defaults omitted; every filter change restarts page 1. Existing deep-link params (tab, edit, employeeId, olderThan, cursor, range, rejectedCursor) untouched.
- `jobsLabels.ts` — status/priority/sort display words (single copy source).
- Loader (`adminBrowseLoaders.ts`): `readJobsFilters` (unknown → default, page clamp, `JOBS_PAGE_SIZES = [10, 25, 50]`); owner `jobs` tab swaps `fetchJobs` for `fetchJobsPage` + `fetchSkillOptions` (settle — a catalog failure degrades the dropdown, never the page) + `selfName`; member tabs and the other owner tabs unchanged; `ownerPipeline` stays for the Approval tab badge.
- New components (each with paired CSS module — the house per-page clone pattern): `JobsFilterBar` (status chips with counts, Clear all, SearchBox ⌘K, Skill dropdown, Priority dropdown, Latest/Soonest toggle), `JobsPager` (RowsPerPage + Pager + Go-to), `JobsExport` (whole-book CSV walk ≤100/page, BOM, guardFormula, progress), `JobsTable` (Job cell title+number link, Customer cell Avatar + name + service-location sub-line, Status pill, Step, Skill, Employee, Priority, Scheduled), `JobsCreateBanner` (dark gradient CTA, real copy, Create a job → /admin/company/jobs/new).
- `AdminJobsPage.tsx` rewrite, owner tabs: `PAGES_WITH_OWN_HEADER += /admin/company/jobs` (path-level, so the header renders on every jobs tab, both roles) — TopBar breadcrumb "Console › Jobs", greeting + Owner pill + role lede, owner page actions (Create job + Download list), tab strip (Jobs tab badge = stats.total, Approval badge = pipeline.pending), then on the Jobs tab: 4 ConsoleTiles (Total jobs / In progress / Job approvals / Completed (30 days), honest captions), create banner, filter card, paged table, footer "Showing X–Y of Z". Approval/Activity/Report tabs and the whole member view keep their content, now under the own header.
- Avatar import reuse; skeleton/empty/failed states like customers; 700px breakpoint.

## Sequence

1. **BE**: migration via Supabase MCP → local BE probe (owner token, master OTP 1039): every filter/sort/search/page-bounds; legacy `GET /jobs` byte-stable.
2. **BE commit + push** (`git commit --only` src/jobs + migration — payroll agent shares this repo; pull --rebase first). Render deploys.
3. **FE**: implement; dev server 5173 already runs.
4. **Tests** (extensive, owner's standing instruction): FE `jobsUrl.test.ts` (clone employeesUrl.test.ts), loader filter reading, JobsTable cells, JobsExport walk/guard/stamp, page shell; BE `jobs-page-query.dto.spec.ts` + `getJobsPage` service spec (filters, sorts, PGRST103, stats, row mapping incl. step index from jsonb). Gates: format:check, tsc, eslint, check:styles, design-system, full bun test; BE jest jobs suites.
5. **BMAD code review** (edge-case-hunter + verification-gap) on the FE diff → step-03 triage (source-verify every finding, twin-parity defers) → patches → record in this plan + `artifacts/implementation-artifacts/deferred-work.md`.
6. **FE commit + push** (`--only` my files).

## Verification

- View: `select * from jobs_overview limit 5` via MCP; counts match `jobs` table.
- Endpoint: each status chip, skill/priority filter, both sorts, search per field, page past end (PGRST103), pageSize bounds; 403 without job.read_all; mobile list `GET /jobs?scope=…` byte-stable.
- Browser: owner at 360/390/768/1280 — banner, tiles, chips, dropdowns, search, pager, CSV; tab badges; no double h1; deep links (approval queue params) still land.
