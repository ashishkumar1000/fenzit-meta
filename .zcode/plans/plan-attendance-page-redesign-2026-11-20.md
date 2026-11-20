# Attendance page redesign — the owner's Attendance & Timesheets mockup, console pattern

## Context

Third page in the owner's console redesign queue (owner, 2026-11-17: "This are the design for JObs and attendence page … pick this one by one .. don't ask for my approval .. do extensive testing"). Jobs shipped (BE 214ee60 / FE 1370f81); this is the Attendance & Timesheets mockup applied to `/admin/company/attendance`, the same console design language as customers/employees/jobs.

Today the page is two bare tabs under the shared layout: "This month" = one unpaginated DataTable of every employee's monthly tallies, "Report" = the Epic 21 `ReportExportCard` (which already implements the mockup's report card — From/To/office scope/Download + previous reports). The mockup adds: own shell with greeting + actions, four tiles, chips + office filter + Sort: Most Absent + pager on the month table, and per-row Timesheet actions.

## Mockup → reality calls

- **Tiles are month-scoped, not today-flavored.** The mockup's "94.2% / 1,346 on duty today" has no Fenzit backing. Honest tiles derived from the roster the loader already returns: **Worked days** (Σ daysWorked), **Half days & late** (Σ halfDays + Σ lateCount, sub "X half days · Y late"), **On approved leave** (Σ leave), **Absent graded** (Σ absent, danger tone).
- **Client-side chips/sort/office/pager — no BE work.** `/attendance/monthly` already returns the whole roster with full summaries, bounded by headcount (~150; built for 150 users). Filtering/sorting/paging in the browser adds no payload and no surface. Revisit only if headcount grows an order of magnitude.
- **Chips**: All | Present (daysWorked > 0) | Late (lateCount > 0) | Absent (absent > 0) — whole-roster counts, stable while filtered.
- **Sort**: Most absent (absent desc → lateCount desc → name asc, the mockup's default) | Name A–Z.
- **Office filter**: distinct `officeName` values (null → "No office"); all offices default.
- **Report tab stays the Epic 21 card** — it already matches the mockup (office scope, From/To, previous reports with Ready chips). No page action duplicates it; the header's mockup "Download PDF Summary" is that tab's job.
- **Deferred (no backing surface)**: Bulk Import, top-bar search + Live-Sync/auto-refresh chrome, Daily Punch Log tab (punch is the mobile app's surface), Leave & Absences tab (leave lives on jobs/me surfaces), per-row Timesheet link + kebab (no per-employee timesheet page exists), Report tab "2 Ready" badge (history is only fetched on the report tab), "Active Cycle" chip (the month window rides the card meta), "Rule Engine: Standard Enterprise v1.2" footnote flavor.
- **Page actions**: Export CSV (client-side single-shot — the roster is already whole-book; columns Employee, Office, Worked, Half days, Late, Leave, Weekly offs, Holidays, Absent, Missing check-outs; BOM + guardFormula on office/name; attendance.csv).

## FE changes (fenzit-web — no BE changes)

- `attendanceUrl.ts` (new): `ATTENDANCE_PATH`; params `chip` (absent|late|present), `office` (name or "none"), `sort=az`, `pageSize` ≠10, `page` >1; defaults omitted; every change restarts page 1. Clone of jobsUrl.
- `attendanceLabels.ts` (new): chip/sort words.
- `adminBrowseLoaders.ts`: `readAttendanceFilters` (chip/office whitelist from the row set is page-side — url reader whitelists shape only: chip ∈ set, sort ∈ set, page clamp 1..10000, pageSize 10/25/50, office trim/120); `AttendanceData` month variant gains `filters` (from URL). Loader month tab otherwise unchanged (same fetchMonthly).
- `components/AttendanceFilterBar.tsx` + css: chips with counts (no stats object — counts derived in page), office dropdown (showSearch false), sort dropdown, Clear all.
- `components/AttendancePager.tsx` + css: RowsPerPage (10/25/50) + Pager + go-to (jobs twins).
- `components/AttendanceExport.tsx` + css: ExportAttendanceButton, single-shot CSV (no walk), progress-free.
- `AdminAttendancePage.tsx` + css rewrite: own shell (TopBar breadcrumb "Console › Attendance", greeting + CrownIcon Owner pill + lede, pageActions Export CSV), Tabs (This month | Report) with the month window as the card meta, 4 ConsoleTiles, filter card (chips + office + sort), AttendanceTable rows (avatar + name; office chip; tallies; absent danger-toned; "Timesheet" column dropped), footer Showing X–Y of Z + pager; skeleton while navigating; empty states (no employees tracked / none match filters); failed branch keeps retry card (role always owner — loader is owner-only).
- `AdminPage.tsx`: PAGES_WITH_OWN_HEADER += "/admin/company/attendance".
- Keep the existing status-words footnote (the mockup carries it too).

## Tests

- `attendanceUrl.test.ts`: build/read round-trips, whitelist fallbacks, page clamp, page-restart rules.
- `AdminAttendancePage.test.tsx`: extend — tiles sums, chips + counts, chip/office/sort navigation → filtered client-side rows, pager + rows-per-page, showing line, CSV button, report tab shell + single h1, member/failed states (owner-only loader → failed branch).
- `AttendanceExport.test.tsx`: CSV rows, BOM, guardFormula, file name.

## Sequence

1. Implement FE (no BE dependency).
2. Full gates: `bun test`, tsc, format:check, lint, check:styles.
3. BMAD two-lens review (edge-case-hunter + verification-gap) on the diff → step-03 triage → patches.
4. Commit (explicit paths) + pull --rebase + push; ledger + memory updates.
