---
id: SPEC-attendance-report
companions:
  - report-content.md
  - design-notes.md
  - ../../planning-artifacts/prds/prd-fenzo-reports-2026-09-18/prd.md
sources:
  - ../../planning-artifacts/epics-reports.md
---

> **Canonical contract.** This SPEC and the files in `companions:` are the complete, preservation-validated contract for what to build, test, and validate. Source documents listed in frontmatter are for traceability — consult them only if you need narrative rationale or prose color this contract intentionally omits.

# Attendance Report — second report type in the owner Reports section

## Why

**A pain to solve + an opportunity.** The owner's Reports section today offers only the Technician Job Report, so an owner has no downloadable record of who showed up, who was late, who never checked out, and whose punch attempts looked faked — the exact questions the attendance module (live since 2026-10-01, biggest tenant 103 employees across 4 offices) now generates data for every day. The reports engine already carries a pluggable registry built for a second type, so the opportunity is to give the owner full workforce visibility for near-zero new infrastructure.

## Capabilities

- **CAP-1 — Gated report offering**
  - **intent:** The owner sees an "Attendance report" option in the Reports section exactly when their tenant's attendance module is enabled; the job report stays always visible.
  - **success:** With attendance enabled, Reports offers both types; with it disabled (or setup incomplete), the attendance option is absent and a direct API submit is rejected with `ATTENDANCE_NOT_ENABLED`.

- **CAP-2 — Scoped request**
  - **intent:** The owner requests an attendance report for any combination of all/single/multiple offices and all/single/multiple employees, over any date range up to 92 days inclusive ending today (IST).
  - **success:** Every valid scope combination queues a request; unknown office/employee ids, ranges > 92 days, future end dates, and attendance-disabled tenants are rejected with specific error codes before any generation work.

- **CAP-3 — Full-visibility PDF**
  - **intent:** The generated PDF answers, in one document: overall attendance health, office-level comparison, per-employee attendance/discipline/hours, what needs attention, weekly trajectory, leave taken, and (for ranges ≤ 31 days) the day-by-day register.
  - **success:** For a real tenant period, the PDF renders all sections in [report-content.md](report-content.md) and every number equals the in-app monthly grid's number for the same employee and period (parity spot-check).

- **CAP-4 — Shared lifecycle**
  - **intent:** Attendance requests live in the same history, polling, download, retry, and notification machinery as job reports, with per-type labels and scope summaries.
  - **success:** An attendance request appears in the unified history with an "Attendance report" title and an offices × employees scope label; ready rows download via fresh presigned URL, failed rows offer retry, and no new FE flows beyond the request form exist.

## Constraints

- **Same-engine parity:** every reported aggregate derives only from the day-status engine's outcomes (`computeDayStatus` + the monthly summariser). Re-implemented arithmetic is rejected in review — the 15-9 drift class stays closed.
- **Registry self-containment (NFR5):** the fetcher reads via the admin Supabase client; engine/API changes are limited to widening the params contract with `office_ids`.
- **Owner-only and tenant-isolated:** `@Roles(Role.OWNER)`, service-level tenant filters, and `report_requests` RLS unchanged.
- **Free-tier envelope:** in-process worker, 512 MB, ≤ 25,000 employee-days per report (`REPORT_MAX_ATTENDANCE_ROWS`), existing PDF memory discipline (report_too_large, terminal ordering).
- **Zero DB migrations expected:** attendance records, attempts, leave, overrides, offices, and enrolments already carry every field the report needs; any deviation must be justified in the dev story.
- **Effective-dated office attribution:** an employee may count under different offices within one range (per-day record snapshot, fallback covering assignment) — no "one office per employee" simplification.

## Non-goals

- No CSV/Excel export in v1 (PDF only; CSV is the first fast-follow).
- No scheduled/recurring or emailed reports.
- No punch-location maps, punch photos, or signatures inside the PDF.
- No leave balances (no balance model exists yet).
- No report retention/auto-deletion change (still deferred from the reports PRD §8/§10).
- No technician-facing report access.

## Success signal

An owner of the 103-employee tenant downloads a 3-month, all-offices attendance PDF and can answer without opening any other screen: who didn't show up, who was repeatedly late, who never checked out, which office has the worst attendance, and whether anyone attempted fake-location punches — and every number matches the in-app monthly grid.

## Assumptions

- "Reports section" = the owner's More-tab → Reports screen; the attendance report joins the same screen and the same history list (no new screens).
- An "employee" is a technician-role user with an enrolment; the request form's employee picker lists enrolled employees only (`attendanceStartDate` set).
- Archived offices remain valid filter targets — their history lives in snapshotted records.
- v1 copy is plain English per the standing UX-pass rule.

All three open questions were resolved by the owner on 2026-10-03 (leave excluded from the attendance-rate denominator; day register stays ≤ 31 days; rejected-punch audit counts all attempts with unacknowledged mocked ones driving the alarm) — the decisions are baked into the formulas and rules in [report-content.md](report-content.md).
