# 21 — Attendance Report (second report type): implementation record

**Date:** 2026-10-03 (overnight autonomous run) · **Status:** implemented, review-triaged, device-verified; deployment pending final commit consent flow.

## What shipped

Second report type `attendance_report` in the reports registry (Epic 12 engine), spec `artifacts/specs/spec-attendance-report/`, epic `artifacts/planning-artifacts/epics-attendance-report.md`.

### Backend (fenzit-be)

- **21-1 — engine extraction + contract widening**
  - `src/common/day-status/` now owns the day-status engine: `office-rules.ts` (daterange pickers), `keys.ts` (status/marker vocabulary), `day-context.ts`, `day-status.model.ts` (the FR-10 rules), `grid-reader.ts` (`readDayStatusGrid` + batched SQL), `monthly-summary.model.ts`. Attendance imports repointed; `me-summary.model` / `enrolments-response.model` / `day-status-response.model` re-export shims keep the old import surfaces. Zero behaviour change (1,428 pre-existing tests untouched-green).
  - `ReportParams.office_ids` added (DTO `officeIds`); `ReportFetchContext` gained `pg` (transaction client, opened by the pipeline around every fetch) and `maxRows`; `ReportDefinition` gained `maxTechnicianIds` (job keeps 25; attendance 200) and `validateAccess` (create-time DB checks).
  - `attendance.definition.ts`: shared 92-day IST range validation, office membership (archived allowed), enrolment membership, module gate → 400 `ATTENDANCE_NOT_ENABLED` (new ErrorCode). Registered in `report-registry.ts`.
- **21-2 — fetcher + metrics**
  - `attendance.data.ts`: employee scope = explicit ids or all enrolled (range-overlap); the grid read through the SHARED `readDayStatusGrid` on the pipeline's pg transaction; per-DAY office filtering via `ctx.officeId` snapshot; employee-day oversize guard (`REPORT_MAX_ATTENDANCE_ROWS`, default 25,000) before any grid read; explicit zero-day employees keep a row; rejection audit (non-ok attempts, IST window, in-scope employees only); register built only ≤ 31 days; exceptions via `computeAttendanceExceptions` (cap 200).
  - `attendance.metrics.ts`: `summariseAttendanceRange` rides `summariseEmployeeMonth` (parity by construction) + report-only formulas (expected days EXCLUDE approved leave — owner ruling; attendance rate; worked hours; avg hrs/day; late minutes; early outs; corrections; unacknowledged fake-location days). `registerCode` maps the 12 statuses to the register alphabet.
- **21-3 — template**
  - `attendance.template.ts` + kit helper `data-table.ts` (generic branded table; job-table's visual system without job-specific cells). Normative section order: header → overall cards (3×4) → offices → employees-attendance → employees-discipline&hours → needs attention → weekly trend (>1 week) → day register (≤ 31 d) + legend → leave summary (when any) → rejected punches (when any) → empty page when nobody in scope. Zero template math.

### Frontend (fenzo-app)

- `reportModel.ts`: `REPORT_TYPES` catalog, `availableReportTypes(attendanceEnabled)` gate, `reportTypeLabel`, per-type `scopeLabel` (job rows keep technician scope; attendance rows read `N offices · M employees`).
- `ReportRequestForm.tsx`: the anticipated registry-fed Select; attendance type swaps in Offices (live offices, archived excluded) + Employees (enrolments roster, enrolled-only) MultiSelects; job type keeps Technicians.
- `ReportsScreen.tsx`: gate read from the `/users/me` profile mirror (`profile.attendance.attendanceEnabled`); scope options lazy-load once on first attendance selection (un-latching retry on failure); submit sends `officeIds` and follows the OFFERED type (gate-flip fallback); form reset per existing AC.
- `ReportRow.tsx` / `reports.ts` service: per-type titles, `officeCount` on list items, `officeIds` in create body + status params.

## Review + triage (gate before commit)

Two lenses (edge-case hunter; verification-gap with mutation-verified demonstrations) → 17 findings; verdicts and actions in `21-attendance-report-code-review-2026-10-03.md`. Key patches: paged reads ordered (`order('id')`), rejection audit scoped to in-scope employees, `enrolledFrom` from the unfiltered grid, FE stale-type + latch-retry fixes, plus 8 new/extended specs pinning every review-proven surface. Final: **BE 1,489 green · FE 2,970+ green** (api-client base-URL pin failure was the temporary local-BE config flip, reverted pre-commit).

## Device verification (Pixel 6, local BE via adb reverse, OTP dev-echo login as Ayush/owner)

1. Reports screen renders the type Select; both types offered (attendance enabled).
2. Selecting Attendance swaps to Offices + Employees pickers; real tenant offices (Hero wala, Jhaji's Home, Yuka, Yuka1) and the enrolled roster load.
3. Multi-office selection ("2 selected") + Generate → history row "Attendance report · Queued · 27 Sep – 3 Oct 2026 · 2 offices · all employees".
4. Local worker generated in seconds → row flips Ready (5s polling).
5. Tap → fresh presigned R2 URL → PDF opens (Chrome viewer, 9 pages).
6. Content verified on-device: branded header with scope line; overall cards (102 in scope, 406.5 expected days, 0.4% rate, 86.7 h, 95 late/6929 min, 291 absent, 3.5 leave, 10 missed check-outs, 3 half days, 4 corrections, 2 fake-location attempts); offices table with per-day attribution (Hero wala vs Yuka rows); needs-attention with absent-streak alarms + the fake-location attempt (Loadtest H04, 2026-10-02); day register with colour-coded codes + legend; leave summary (Suresh 1.5 approved + 1 half-day); rejected punches (too far/low accuracy/fake location/rate-limited buckets).
7. Parity is structural (same engine + summariser); spot values consistent with the in-app monthly grid semantics.

## Follow-ups (deferred, recorded)

- Bound the fetch's Supabase-side reads (AbortSignal/timeout) or move them out of the pg transaction — pool-slot exposure if PostgREST hangs.
- `resolveTenantToday` duplicates `enrolments.repository.tenantToday` (NFR5 layering forces it) — pin in sync via a shared fixture test if it ever drifts.
- CSV/Excel export (renderer swap) — first fast-follow.
- Day register for 92-day ranges (landscape) if owners ask.
