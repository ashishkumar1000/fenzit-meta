---
name: overview-exec-dashboard
title: Overview page revamp — executive dashboard (attendance trend, jobs & approvals, workforce analytics)
date: 2026-11-27
sources:
  - Stitch project 12976873967605867584 "Attendance and Jobs Dashboard UX" (screen: Fenzit - Executive Dashboard with Employee Pulse Analytics)
  - workspace/core/backend/fenzit-be (attendance dashboard/grid engine, job-reports module, members/memberships, tenants)
  - workspace/core/frontend/fenzit-web (AdminCompanyPage + adminCompanyLoader, jobReportsApi, companyApi)
companions:
  - design-mapping.md
owner-directives:
  - "Implement exactly on the overview page; the design should look as it is."
  - "Remove the items in the attached screenshots (pulse tiles, link cards) and the Per employee card — complete revamp."
  - "If data is missing, extend the BE API."
  - "Use BMAD."
  - "NO test cases and NO code review until the feature is done and the owner has tested it."
---

# Overview executive-dashboard revamp

## Story

As the company owner, on /admin/company I see an executive dashboard — a subscription
banner and three live charts (attendance trend, jobs & approvals flow, workforce
analytics) — instead of tiles and tables, so the page reads like a command centre.

## The mock, section by section

1. Greeting header (unchanged) — breadcrumb, "Hello, {name}", Owner pill (star), lede.
2. Subscription banner — Active chip + plan chip + valid-until + billing line + Manage Plan button.
3. Attendance Trend card — daily distribution of team attendance over the range.
4. Jobs & Approvals card — weekly cumulative flow comparison + turnaround efficiency.
5. Employee Overview & Analytics card — workforce headcount/invite/pending-approval series.

Everything else from the old page is gone (see design-mapping.md "Removed").

## API contract (BE changes — owner pre-authorised)

### 1. `GET /api/v1/job-reports/owner` — two new response sections

```jsonc
{
  // …existing range/headline/pipeline/perEmployee/employeesWithPermissionNoJobs…
  "trend": {
    "buckets": [                       // 5 equal slices of the window, cumulative AT each slice end
      { "from": "2026-10-23", "to": "2026-10-29",
        "employeeCreated": 4, "employeeApproved": 2, "employeeAutoApproved": 1, "ownerCreated": 3 }
    ],
    // approved / (approved + rejected) over the window — the pipeline's approvalRate re-surfaced
    "turnaroundEfficiency": 0.924      // null when nothing was decided
  },
  "workforce": {
    "buckets": [                       // 5 equal slices; values AS OF each slice end
      { "from": "2026-10-23", "to": "2026-10-29",
        "totalEmployees": 100, "activeEmployees": 59, "pendingInvites": 41, "needsApproval": 19 }
    ]
  }
}
```

- Jobs trend buckets are CUMULATIVE outcomes (mock lines rise to the right; legend = window totals).
- Workforce semantics (documented honestly in the response doc):
  - `totalEmployees` — memberships created on/before the day, excluding rows removed before it
    (removal dated by `updated_at`, best available).
  - `activeEmployees` / `pendingInvites` — current-status back-projection (activation history is
    not tracked); the mock's near-flat lines are the honest shape for real data.
  - `needsApproval` — exact: jobs created ≤ day and not decided (decided_at null or > day),
    cancelled excluded (a cancel stamps decided_at).
- Jobs data rides the SAME `loadWindowJobs` rows (no second query); workforce needs one extra
  memberships read (created_at/updated_at/status) and one light jobs read that spans before the
  window start (pending jobs can be older than the window).

### 2. `GET /api/v1/attendance/trend?from&to` — new endpoint (attendance module)

```jsonc
{
  "range": { "from": "2026-10-23", "to": "2026-11-21" },
  "days": [                             // one row per IST day, inclusive
    { "date": "2026-10-23", "tracked": 7, "checkedIn": 6, "notCheckedIn": 0,
      "shortDay": 1, "late": 2, "onLeave": 1 }
  ]
}
```

- The SAME engine as the today-pulse: one `readDayStatusGrid(tx, tenant, trackedEmployeeIds,
  from, to)` read over the range candidate set, `computeDayStatus` per employee-day, the identical
  bucket partition (CHECKED_IN_STATUSES / ON_LEAVE_STATUSES / rule-7 short day / else
  not-checked-in; late qualifies checked-in). No second implementation of FR-10.
- Candidate set = enrolment ∩ assignment ∩ live office covering ANY day of the range (the grid
  grades each day's tracked-ness itself, as today() does via `ctx.tracked`).
- 422 on a bad window (reuse the resolveReportWindow rules: real dates, ≤366 days).
- Today's row uses the same partition as the pulse tiles, so the page can never disagree with
  the mobile dashboard.

### 3. Subscription facts — `tenants` columns + `/users/me` payload

- Migration: `plan_name text not null default 'Enterprise'`,
  `billing_cycle text not null default 'Annual'`, `auto_renews boolean not null default true`.
- `UserProfileBase.subscription` becomes `{ validUntil, planName, billingCycle, autoRenews }`.
- The FE derives the Active chip: validUntil null → "Active" (no end date), future → "Active",
  past → "Expired" (amber chip).

## FE changes (fenzit-web)

- `AdminCompanyPage` rebuilt to the mock: header (star Owner pill), subscription banner, three
  chart cards (hand-rolled SVG charts copying the mock's geometry: gridlines, dashed baselines,
  gradient areas, white-stroked end dots with `<title>` tooltips, weekly x-labels).
- Shared `?range=` preset drives all three cards: 7D → `range=7`, 30 Days → `range=30`,
  This Month → `range=this-month`; the date pill displays the resolved window (display-only,
  chevron decorative).
- Loader v2: `me` (subscription facts) + owner report (trend + workforce) + attendance trend —
  three settled slices; pulse and members fetches are GONE (nothing on the page uses them).
- Legend values: attendance — Tracked total, Checked In avg/day, Not Checked avg/day, Short Day
  total, Late/Leave total; jobs — window totals from headline; workforce — last bucket's values
  + Active workforce rate = active/total of the last bucket.
- CSV downloads (attendance + workforce) generated client-side from the fetched series.
- Links: Manage Plan → /pricing (v1; no billing page exists), Approval Rules →
  /admin/company/employees (per-member job approval settings live there), Manage Employees →
  /admin/company/employees.
- Empty/failed states: each chart degrades to its own retry card (existing page pattern); an
  empty series renders zero-lines honestly (Sally rule: no fake data).
- Tests: FROZEN by owner directive until the feature is owner-tested. Existing
  AdminCompanyPage.test.tsx assertions no longer describe the page; updating them is deferred
  work, recorded here so nothing silently rots.

## Non-goals

- The console sidebar/shell (mock's sidebar ≈ the existing one; Payroll nav already exists).
- Real per-day activation history for memberships (needs an events table — noted for later).
- A billing-management page behind "Manage Plan".
- Mobile app changes.

## Verification (after owner test, per directive)

- Localhost preview against live api.fenzit.com; owner walks the three charts + banner.
- Then (and only then): BMAD review + test-suite catch-up.

## As-built round 2 — 2026-11-28 payload slimming (owner overnight directive)

Owner: "we have removed lot of sections from UI ... we should remove those from the API as well
so that server don't send what is not required and db query can become easy ... make sure you
don't break the existing features."

### Consumer recon (the constraint that shaped everything)

- GET /job-reports/owner has THREE consumers, not one: the overview page (headline + trend +
  workforce), the jobs console page (fetches it on EVERY owner tab for the Approval badge —
  reads only `pipeline.pending`), and the SHIPPED MOBILE APP (useOwnerJobSummary reads `headline`
  + `pipeline.pending`, with a defensive `pipeline?.pending ?? 0`).
- Deliberately NOT slimmed, after consumer sweeps: the jobs list payload (the member "My Jobs"
  tab and the dossier still read currentStep/currentStepIndex/workflowTemplate), the members
  list (already lean), the holidays overview (fully used by both holiday pages + coverage card),
  /attendance/leave (the Leave page + the shell's badge), /attendance/holidays + impact (app).
- The slimming therefore touched ONLY the owner report.

### The contract

- GET /job-reports/owner is LIGHT by default: `{ range, headline, pipeline: { pending } }`.
- `?charts=true` adds `trend` + `workforce`. Chosen over a separate endpoint because the overview
  needs headline + charts from ONE window-jobs read; a second endpoint would double that read.
- The heavy reads (loadWorkforceMemberships + the 730-day pending history pool) run ONLY in the
  charts branch — the app's home and the jobs page's badge pay the old, light query cost.
- `pipeline: { pending }` keeps its name/shape for the shipped mobile app; the rest of the old
  pipeline (aged pending, rejection splits, approval rate, wait minutes, oldest job) is deleted
  from the rules layer (ownerPipeline, perEmployee, employeesWithPermissionNoJobs functions gone).
- turnaroundEfficiency still = approved/(approved+rejected), computed straight off countOutcomes.

### Bug found and fixed during spec-writing (tests first caught it)

- cumulativeJobFlow (shipped 2026-11-27) assigned each job to only the FIRST cut past its
  creation — per-slice increments, while its docblock + the FE chart claim cumulative as-of
  counts (workforceAtCuts already had true as-of semantics). Fixed: each job counts in every
  bucket whose cut is past its creation. The chart's rising lines now actually rise and the
  last bucket equals the headline totals.

### Tests (unfrozen; owner said "write test cases")

- NEW src/attendance/trend.spec.ts: window guards (bad date / inverted / >62d), honest zero day
  map, tracked gate, bucket partition with mocked engine + grid reader.
- job-reports.service.spec.ts: rewritten — light-vs-charts wire behavior (light = one jobs read +
  one memberships read; charts = two of each), cancelled-never-approved, window guards.
- job-report-rules.spec.ts: dead describes removed; new sliceWindow / cumulativeJobFlow /
  workforceAtCuts describes. 62 specs green (`bunx jest`), typecheck clean.
- FE: AdminCompanyPage.test.tsx fully rebuilt to the exec dashboard (stubbed TrendChart —
  happy-dom has no canvas; assertions ride the stub's recorded series props + the legend chips'
  accessible names); adminBrowseLoaders/AdminJobsQueue fixtures slimmed to the light shape;
  AdminPage/AdminJobsPage/AdminEmployeesPage assertions updated to the removed UI (settings note,
  create banner, Employment column); the 13 employment-dialog tests re-entered through the
  profile page's master-record banner ("Complete Employee Details" / "Open Anyway") after the
  team-table Employment column retired; EmploymentForm's saved copy made host-neutral ("Saved.
  The profile now shows the current details.").

### Deploy order note

- BE and FE for this feature are coupled: prod FE still runs the old page asserting the old
  fields, and the new page needs the new endpoints. Push BE and FE back-to-back (push = deploy
  on both) to keep the broken window to minutes.

## Code Review

### 2026-11-28 (BMAD code-review, BE diff; two lenses)

**Code review complete.** 0 decision-needed, 6 patch, 0 defer, 4 rejected. Applied autonomously per the owner's overnight directive ("run full BMAD code review on BE, fix the issues").

- [ ] [Review][Patch] /users/me subscription plan facts have no asserting test [src/users/users.service.spec.ts] — extend the owner-profile and platform-admin tests to assert planName/billingCycle/autoRenews against the fixture's tenant columns and the no-company defaults.
- [ ] [Review][Patch] charts=true service test only ever exercises empty data [src/job-reports/job-reports.service.spec.ts] — add jobs/memberships placed around slice boundaries and assert per-bucket numbers (pins cut derivation, the owner-created population, and removal history end to end).
- [ ] [Review][Patch] Trend↔pulse partition parity unasserted; dashboard docblock claims "consumed, never re-implemented" but trend re-implements it [src/attendance/dashboard.ts:65, src/attendance/trend.ts:134-148] — extract one shared bucket classifier both call.
- [ ] [Review][Patch] loadWorkforceMemberships does a single unpaged read — >1000 memberships silently truncate [src/job-reports/job-report-data.ts:200-227] — page it via pageAllRows like loadWindowJobs.
- [ ] [Review][Patch] workforce needsApproval counts every undecided job forever — auto-approved jobs (decided_at null for life) and owner-created jobs inflate the chart at every cut [src/job-reports/job-report-rules.ts workforceAtCuts] — exclude outcomes that are not genuinely pending; add a spec case.
- [ ] [Review][Patch] cumulativeJobFlow approved counts decisions not yet made at the cut [src/job-reports/job-report-rules.ts cumulativeJobFlow] — an approval made late inflates earlier buckets; count approved only in buckets whose cut is past decided_at; add a spec case.

Rejected appendix:
- E1 trend enrolment-only candidate gate — false: the predicate mirrors the engine's own tracked gate; an enrolled employee with no covering assignment reads not_tracked in the grid and would be skipped anyway.
- E2 62-day × large-roster grid performance — low, rejected: everyday presets stay ≤31 days (the monthly report already runs the same grid at 31 days on the full roster); a row-budget guard adds a new user-facing rejection surface for a rare path.
- E3 `?charts=` (empty string) 422s — false: the DTO documents charts ∈ {true,false}; rejecting an invalid value is the contract, and no client sends an empty value.
- E7 no-tenant /users/me fabricates Enterprise/Annual — false: the banner renders on the owner-only overview, and an owner requires company membership; login/mobile consumers of the no-tenant branch ignore the fields, and the FE defaults render identically.

### FE code review (2026-11-28, same run — 4 lens agents over a 3-chunk diff)

**Code review complete.** 0 decision-needed, 12 patch groups (all applied), 4 rejected. The full suite grew to 1470 green; tsc + css-modules pairing clean.

Applied patches:
- [Review][Patch] Legend hidden-series state lifted to the page [AdminCompanyPage.tsx] — the region's skeleton swap remounts the cards on every preset navigation, silently resetting legend toggles; a toggle is a view preference and now survives the swap. The animation sweep replaying over fresh data after the skeleton is the designed arrival, kept.
- [Review][Patch] downloadCsv's revoke deferred [AdminCompanyPage.tsx] — matched the repo's AttendanceExport pattern (a synchronous revoke can cancel the download in Safari).
- [Review][Patch] Verified orphans deleted: LinkCard + CSS, the five admin art components + CSS, fetchPulse/PulseResponse (the overview's retired reads), .navNote rules, the EmploymentCell export + its CSS, TrendChart's dead .chartSvg/.chartPoint classes and its unused `wide` prop.
- [Review][Patch] JobsTable's employee link guards an empty-string name to the dash; Help's copy button re-arms its timer on a second click; the payroll kit's member-record handler consults refusals and keeps the seeded email; the leave search gains max-width:100% beside the owner's 320px min-width.
- [Review][Patch] Nine test additions: chart series values asserted field-for-field against the stub boundary, both CSVs clicked and content-pinned, the Expired banner branch, a malformed trend body (degrades to the retry card like the report guard), literal fmtDayMonth pins, the jobs-table employee link's href + nameless fallback, the attendance link's href, the Help copy flow's clipboard writes + Copied flip, and absence pins for the retired create banner and Current-Step column.

Rejected appendix:
- Empty days/buckets arrays crash the axis — false: the BE returns ≥1 day/bucket for any valid loader-resolved window; the arrays cannot be empty through the contract.
- NaN validUntil shows Active — false: the tenants column is a timestamp or null on the wire.
- prefers-reduced-motion read once at import — low, rejected: a mid-session OS toggle is niche and a reload applies it; the listener adds a hook for no everyday user.
- Claims-file test count — the employment-dialog file holds 12 tests, not 13 (a review-artifact correction, no code change).

Deferred (documented): the real TrendChart component never mounts under test — bun hoists mock.module process-wide, so no test file can reach the unmocked component (tried in-file capture, afterAll re-registration, and query-string module instances; all fail against the hoisting). The chart layer's live behavior is verified on the dev server instead (audit screenshots, 2026-11-28). A Chart.register regression would ship green.

## As-built round 3 — 2026-11-28 `/users/me` boot-call batching

Follow-up to round 2: the boot call still paid one serial round trip per head read
(own row → membership → reporting tree → tenant facts → business-type pick) before
its stage-2 wave. The five head reads now fire in one `Promise.all`; the response
payload is unchanged. The gain is ESTIMATED from the slow-api audit's RTT floor
(~0.24 s per serialised hop, ~0.5–0.7 s off boot), **not measured** — a two-sample
warm before/after probe of `/users/me` is the open verification follow-up, recorded
in `deferred-work.md`.

### 2026-11-28 (BMAD code-review, BE `/users/me` batching diff; three lenses)

**Code review complete.** 0 decision-needed, 6 patch (all applied), 2 defer, 8 rejected.
Target: the uncommitted `fenzit-be` diff (`src/users/users.service.ts`,
`src/users/users.service.spec.ts`, `test/users.e2e-spec.ts`), no plan → no-plan mode.
Verification: typecheck clean; `src/users` 69/69; users e2e 10/10; the new batch test
was proven red against a serial mock (memberships/tenants left unstarted).

Applied patches:
- [Review][Patch] The docblock promised `Promise.all` "resolves every member" — corrected: the four `{data, error}` reads resolve and are checked in order; the business-type read rejects, so `Promise.all` is fail-fast on it and its shaped 500 preempts sibling logs on a co-failure. Rot-prone topology/cost claims and the 8-line prose trimmed; `2026-11-28` provenance tag added.
- [Review][Patch] `const membership` (`prefer-const`); the touched service is back to its one pre-existing lint error (`listTechnicians` unsafe-assignment).
- [Review][Patch] `tenant_business_types` had only an empty-success mock: added `businessTypes` on `mockAdmin`, a failure test (house 500), a non-empty display-order test, and the e2e now serves one chosen type and asserts `tenant.businessTypes` over the wire.
- [Review][Patch] The one-batch invariant is now pinned: mock terminals are lazy like supabase-js, the own row is held open, and the test asserts every head read started — proven red against the serial regression (memberships/tenants unstarted).

Deferred:
- [Review][Defer] The users e2e suite runs outside every gate (`.husky/pre-push` = typecheck only; no CI jest job; `bun run test` never loads `test/`) — HEAD's copy was red (4 tests), which this diff repaired silently. Pre-existing; changing the gate is a repo-wide decision with real-DB implications.
- [Review][Defer] The stage-2 profile reads (skills/jobs/counts/access, and the owner roster) are still independent-but-serial after the batch — pre-existing; folding them in needs its own error-precedence decision.

Rejected appendix:
- Dead `businessTypes ?? []` fallback — false: `loadTenantBusinessTypes` returns `data ?? []`, so it is unreachable; the ternary's nullable type is the only reason it exists.
- Two representations of "no team" — false: both paths produce the identical `emptyTeamSummary()` in the response; no caller sees a second shape.
- `OwnMembershipRow` declared inside the method — false: placement causes no harm; select-string sync applies equally to every module-scope row type.
- Wasted reads on the 500 path — low, not fixed: extra reads only on a rare error path; identity-read-first would re-serialise the call.
- Per-request concurrency 5→6 / pooler burst — false: stage 2 already fires 4–6 concurrent reads in `Promise.all`; no new peak class.
- No timeout/abort on a stalled read — false: the serial version had the same exposure; batching releases finished connections sooner.
- Membership removed mid-flight — false: the inconsistency window is narrower than the serial version's.
- Pool exhaustion from many simultaneous boots — false: same refutation as the concurrency finding.
