---
name: holidays-console-redesign
title: Holidays console redesign — per-office holidays, calendar UI, schedule page, inspector sidebar
date: 2026-11-26
sources:
  - Stitch project 1904834121279645727 "Holiday Calendar UX Redesign" (4 screens: main page, Add Holiday modal, Full Annual Holiday Schedule, Calendar Date Inspector Flyout)
  - workspace/core/backend/fenzit-be (attendance holidays table, RPCs, controller/service)
  - workspace/core/frontend/fenzit-web (AdminHolidaysPage, adminBrowseLoaders, LeaveCalendarGrid)
companions:
  - design-mapping.md
  - ../../planning-artifacts/holidays-console-redesign-2026-11-26/PLAN.md
---

# SPEC — Holidays console redesign

## Why

The console's Holidays page is a read-only chip list, and holidays are strictly tenant-wide. The approved Stitch design turns Holidays into a first-class management surface — a month calendar, a full annual schedule, an add/edit modal with per-office applicability, and a date-inspector sidebar with live impact data — which requires the backend to model office scoping and expose real headcount/leave-impact data.

## Capabilities

- **CAP-1 — Create holiday with office applicability.** Admin can create a holiday (name, optional description, date, scope `all` or `offices` + selected office ids) from the console.
  intent: one holiday per date per tenant; applicability decides which offices are closed.
  success: POST `/api/v1/attendance/holidays` accepts the new fields, persists applicability atomically, returns 409 on an existing date; the modal flow completes end-to-end in the browser against a real tenant.
- **CAP-2 — Edit (incl. date) and delete.** Admin can edit every holiday field including the date (409 on same-date collision) and delete the holiday.
  intent: replace the legacy name-only PATCH and remove the date-immutability contract; writes leave the legacy PL/pgSQL RPCs (no new PL/pgSQL).
  success: PATCH `/api/v1/attendance/holidays/:id` accepts name/description/date/scope/officeIds; DELETE still 204; future-dated create/edit/delete push-notify affected employees.
- **CAP-3 — Holidays page per design.** Year switcher, month calendar with holiday-marked dates, upcoming-holiday banner, upcoming list with Edit/Remove, past-holidays archive, total-days stat, long-weekend breaks card.
  intent: implement the Stitch main screen with real tenant data; clicking a calendar date opens the holiday modal (add on empty date, edit pre-filled on a holiday date).
  success: browser-verified against localhost with real holidays rendered on the calendar and every card populated.
- **CAP-4 — Full Annual Holiday Schedule page.** Stats row, office filter, month filter, month-grouped table (name+description, observed date & day, duration impact, offices, headcount, edit action), branch office coverage bars, Print, Export Calendar (.ics).
  intent: implement the Stitch schedule screen as route `/admin/company/holidays/schedule`; clicking a list item opens the inspector sidebar (CAP-5).
  success: browser-verified with month grouping, filters, coverage bars, and a working .ics download.
- **CAP-5 — Date-inspector sidebar with real data.** Holiday facts, on-leave progress (approved leave vs tracked staff for that date), offices-closed chips with staff counts, next upcoming holiday, Edit Date / Edit Details / Delete actions.
  intent: real data, not mock numbers.
  success: GET impact endpoint returns approved-leave count + per-office staff counts for the date; sidebar renders them; verified in browser.
- **CAP-6 — Per-office day-status correctness.** An employee's `holiday` day-status applies only when the holiday covers their office (scope `all`, or their office assignment covering that date is in `holiday_offices`).
  intent: payroll LOP, leave debits, and reports inherit correct per-employee behaviour via day statuses; employee self-summary "upcoming holidays" list respects the same rule.
  success: unit specs prove scoped-holiday lookup per employee (assigned/office-less/scope-all); existing day-status/payroll suites stay green.

## Constraints

- **No PL/pgSQL.** No new stored procedures, functions, or triggers; migrations are DDL-only (payroll idiom: deny-by-default RLS, service_role grants); atomic multi-row writes via `pgPool.withTransaction` or a guarded UPDATE.
- **One holiday per date per tenant** (existing unique constraint stays); office applicability is `scope` + join rows, never duplicate rows per date.
- **Design fidelity with house tokens:** layout/structure of the 4 Stitch screens as-is; colours map to existing console design tokens; demo emoji and mock numbers ("94 employees") are replaced by real data.
- **Roles:** management actions stay owner/console-gated (`attendance.manage`); existing nav position of Holidays (between Jobs and Leave) is kept.
- **No email:** the "Send email notice" checkbox is omitted; the existing push-notification fan-out for future-dated holidays is preserved and becomes office-scoped.

## Non-goals

- Email notifications for holidays (no transport exists; owner declined building one now).
- Mobile (fenzit-app) holiday UI — BE responses stay backward-compatible so the app keeps working.
- Half-day holidays, holiday "types"/classifications beyond the single official-company-holiday concept.
- Employee-facing (member console) holiday pages beyond what exists today.

## Success signal

Owner opens localhost preview, creates an office-scoped holiday via the modal, sees it on the calendar and schedule, opens the inspector from a schedule row, and the affected offices' employees get correct holiday day-statuses (verified by BE specs). All four Stitch screens recognisably implemented.

## Open questions

None — all resolved by the owner on 2026-11-26 (see `.memlog.md`).
