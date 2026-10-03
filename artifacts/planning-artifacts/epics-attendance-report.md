# Fenzo — Epic Breakdown (Attendance Report — second report type)

Source of truth: `artifacts/specs/spec-attendance-report/` (SPEC.md + report-content.md + design-notes.md; owner decisions resolved 2026-10-03). Repos: `fenzit-be` (backend), `fenzo-app` (frontend).

## Overview

Adds an **Attendance Report** as the second type in the existing reports registry (Epic 12 engine): owner-scoped PDF over offices × employees × date range (≤ 92 days IST), sharing the job report's request/history/retry/download lifecycle, with every number derived from the shared day-status engine (the FR-11 parity contract).

## Decisions carried in (spec)

- DB: zero migrations. BE: definition + fetcher + template + minimal contract widening. FE: type select + gating + pickers + labels.
- Parity by construction: the grid reader (`readDayStatusGrid`) moves to `src/common/day-status/` so Epic 18/19 reads and the report fetcher call THE SAME function (NFR5 kept: reports imports only common/).
- Gating: tenant attendance module flag; BE rejects with `ATTENDANCE_NOT_ENABLED`, FE hides via the users/me mirror.
- Caps: range 92 days IST (shared util), employee-days ≤ `REPORT_MAX_ATTENDANCE_ROWS` (default 25,000) → `report_too_large`, in-flight 3 (existing trigger), explicit employee list ≤ 200 (`maxTechnicianIds` per definition; job keeps 25).
- Owner-confirmed: leave excluded from the attendance-rate denominator; day register only ≤ 31-day ranges; rejected-punch audit counts all attempts (unacknowledged mocked drive alarms).

## Stories

### 21-1 — BE: shared day-status core + params widening + attendance definition shell
- Extract `src/common/day-status/`: `office-rules.ts` (OfficeRuleRow, WeeklyOffRow, DateRange, parseDateRange, rangeCovers, pickRuleForDate, pickWeeklyOffDays — from me-summary.model/enrolments-response.model), `keys.ts` (STATUS/MARKER keys + types), `day-context.ts`, `day-status.model.ts`, `grid-reader.ts` (readDayStatusGrid + row types + tenant-today resolve), `monthly-summary.model.ts`, with their spec files. Attendance imports rewritten; behaviour unchanged (whole attendance suite green).
- Contract widening: `officeIds` on the DTO, `office_ids` in canonical params, `pg` transaction client + `maxRows` on ReportFetchContext, optional `validateAccess` + `maxTechnicianIds` on the definition contract; `ATTENDANCE_NOT_ENABLED` error code; response params carry `officeIds`.
- `attendance_report` definition shell: validateParams (shared range util; office ids exist in tenant offices incl. archived; employees enrolled) + validateAccess (module enabled) + registry entry.
- AC: job-report flow unchanged (its suite green); attendance submit validation matrix tested (range/ids/module flag).

### 21-2 — BE: attendance fetcher + metrics
- Fetcher: employee scope = explicit ids or all enrolled; grid via the shared reader; per-day office attribution (ctx.officeId) with office_ids as a per-day filter; mocked-attempt day flags and leave day rows ride the grid transaction; the rejected-punch audit reads via the admin Supabase client outside it (review 2026-10-03); employee-day cap → `report_too_large`.
- Metrics module: overall/office/employee/weekly aggregations per report-content.md formulas (expected days exclude leave; rate 1-decimal; hours from non-null workedMinutes).
- AC: parity test — fetcher aggregates equal `summariseEmployeeMonth` outputs on seeded fixtures; mid-period enrolment + mid-period office move fixtures; oversize guard test.

### 21-3 — BE: attendance PDF template + brand-kit helpers
- Sections per report-content.md order; new kit helpers (office table, employee summary tables, register grid, exceptions list) — structure only, kit styling; register gated ≤ 31 days; exceptions cap 200 + "+N more"; empty-scope page.
- AC: template unit tests (section presence/suppression, cap, zero-states); PDF renders on fixtures.

### 21-4 — FE: type select + gating + pickers + labels
- Type catalog fed by available types (job always; attendance on profile `attendanceEnabled`); office MultiSelect (offices service) + employee MultiSelect (enrolments roster, enrolled-only, narrowed by chosen offices for convenience); scope labels `N offices · M employees`; per-type history row titles; body sends `officeIds`.
- AC: jest (form gating, validation, labels, store shaping per reportModel tests); no lifecycle changes.

### 21-5 — QA: device + parity + suites
- Device walkthrough on the Pixel 6 (gating visible/hidden states, request → history → download), parity spot-check PDF vs monthly grid for the same period, e2e suites updated if the wire contract changed.

## Guardrails

- Standing: consent before commits; BMAD code review + step-03 triage before merge; backend-first; bun only; plain-English copy.
- Envelope: worker concurrency 1, pool max 5 (reports borrow one tx client during fetch), 512 MB, existing terminal ordering + lease recovery untouched.
