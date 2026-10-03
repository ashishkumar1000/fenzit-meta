# Attendance Report — design notes (BE / FE / DB mapping)

How the contract maps onto the existing system. File references are evidence anchors for dev stories, not prescriptions to edit line numbers.

## Layer ownership (fix-placement analysis)

- **DB: no change.** Every field exists: `attendance_records` (day rows with office/rule snapshots, check-in/out pairs), `attendance_attempts` (outcomes incl. `mocked`, `too_far`, `low_accuracy`), `leave_request_days` (state), `attendance_day_overrides` (active corrections), `attendance_offices` + `attendance_office_rules`, `attendance_enrolments`/`attendance_office_assignments` (effective-dated), `attendance_settings` (module flag). Only read paths are new.
- **BE: the feature.** One new registry definition + template + fetcher; minimal params widening; shared-engine extraction.
- **FE: form + gating.** Type select, office/employee pickers, per-type labels; zero lifecycle changes.

## BE (fenzit-be)

### Registry extension point
`src/reports/registry/report-definition.ts` — new definition object `{ type: 'attendance_report', label: 'Attendance report', validateParams, fetchData, buildDocument }` + one `register()` entry in `report-registry.ts`. Engine, API, worker, R2 keys (`{tenantId}/reports/{requestId}.pdf`), presign, retry, notifications all type-agnostic already (Epic 12; PRD §8 named this growth path).

### Params contract widening
- `ReportParams` gains `office_ids: string[]` (empty = all offices). Raw DTO (`CreateReportRequestDto`) gains `officeIds?: string[] | null`; `technicianIds` is reused as the employee filter — one wire shape across types, `params` jsonb untouched.
- Attendance `validateParams`: shared `validateReportDateRange` (92-day IST cap, no future end — `report-params.util.ts`); office ids must resolve in the tenant's `attendance_offices` (archived allowed — history lives in their snapshots) else 400; technician ids must be tenant technicians **with an enrolment** (`attendanceStartDate` set) else 400; tenant `attendance_settings.enabled` + `setup_completed_at` required else 400 `ATTENDANCE_NOT_ENABLED`.
- Job-report definition untouched (its `technician_ids` validation stays role-based; `office_ids` stays absent → all-offices is meaningless for it and ignored with a 400 if sent — pick per dev story, note the choice).

### Fetcher + engine reuse (the parity constraint)
- `readDayStatusGrid` (`src/attendance/day-status.read.ts:174`) takes a pg `PoolClient`; the fetcher gets a Supabase admin client. The day-status assembly must not be duplicated.
- **Plan:** extract the pure chain — `day-context.ts` (pure time/grading fns), `day-status.model.ts`, `day-status-response.model.ts` keys, `monthly-summary.model.ts` — into a shared module (e.g. `src/common/day-status/` or `src/lib/attendance-engine/`); attendance and reports both import it. The Supabase-side read (records/attempts/leave/overrides/assignments/rules/holidays/enrolments paging, ≤ 1000/chunk like `technician-job-activity.data.ts`) assembles `DayStatusInput` rows and MUST be verified row-for-row against `readDayStatusGrid` on the same tenant fixtures (test: both readers produce identical outcomes for a seeded period).
- Aggregation via a new metrics module calling `summariseEmployeeMonth` + the formula set in [report-content.md](report-content.md) (worked hours, early outs, late minutes, expected days, per-office grouping). Office attribution per day: `attendance_records.office_id` snapshot, fallback covering `attendance_office_assignments` for that date.
- Employee-day count guard: enrolled employees × tracked days in scope > `REPORT_MAX_ATTENDANCE_ROWS` (new env, default 25,000) → `report_too_large` before any PDF work. Scale check: biggest real tenant = 103 × 92 ≈ 9.5k rows.
- PDF payload: pre-aggregated section values (overall cards, office rows, employee rows, exceptions, weekly chunks, register grid when ≤ 31 days, leave rows, rejection counts) — the template does zero math (12-5 rule).

### Template
New `registry/attendance.template.ts` composing brand-kit helpers (`pageHeader`, `summaryCardRow`, `sectionTitle`, tables, `flagList`, `emptyState*`); new kit helpers where needed (office/employee summary tables, register grid, exceptions list) — structure only, all colours/fonts/icons from the kit (FR-T2). Inter fonts already bundled.

## FE (fenzo-app)

- **Type catalog + gating:** `reportModel.ts` gains a types catalog (`technician_job_activity` always; `attendance_report` gated on the owner profile mirror `attendanceEnabled` — `services/resources/users.ts:135-147`). `ReportRequestForm.tsx:5-7` fixed row becomes the anticipated registry-fed Select.
- **Pickers:** attendance type swaps the technician MultiSelect for (a) offices MultiSelect fed by `officesService` list (`services/resources/offices.ts`) and (b) employees MultiSelect fed by `enrolmentsService` list (`services/resources/enrolments.ts`), filtered client-side to `attendanceStartDate != null` (v1 does NOT narrow the picker by chosen offices — report semantics are per-day anyway; review 2026-10-03). Range pickers + 92-day validation (`MAX_RANGE_DAYS = 92`) reused as-is.
- **History:** `ReportRow.tsx:48` hard-coded title parameterized to the request's type label; scope label gains the `N offices · M employees` form. Polling (5s while in-flight), presign-on-tap (10s timeout), retry, idempotency key, cursor pagination, Realtime events — all reused untouched.
- **API client:** `services/resources/reports.ts` — `createReport` body gains optional `officeIds`; type constant for `attendance_report`; no new endpoints.

## Scale & failure envelope

| Guard | Value | Source |
|---|---|---|
| Range | ≤ 92 days inclusive, IST | shared util |
| Employee-days | ≤ 25,000/report | new env, fetcher-enforced |
| In-flight requests | 3/tenant | existing trigger |
| Exceptions rows | ≤ 200 + "+N more" | template rule |
| Register | only ≤ 31-day ranges | template rule |
| Worker concurrency / attempts | 1 / 3 | existing env |

Worst realistic case (103 employees, 92 days): ~9.5k grid rows, one arithmetic pass, employee tables ~103×2 rows — well inside the 512 MB envelope; register skipped (92 > 31).

## Story slicing (non-binding, for the epic doc)

1. BE — engine extraction + params widening + attendance validation/registry entry (tests: validation matrix, parity fixtures).
2. BE — fetcher + metrics (tests: office attribution mid-move, mid-period enrolment, oversize guard, parity vs `readDayStatusGrid`).
3. BE — template + kit helpers (tests: section presence/suppression rules, register cutoff, exceptions cap).
4. FE — type select + gating + pickers + labels (jest per `fenzo-fe-jest-gotchas`).
5. QA — device walkthrough (owner device), parity spot-check vs monthly grid, e2e suites update.

Per standing rules: BMAD code review + step-03 triage after build; consent before any commit; backend-first ordering.
