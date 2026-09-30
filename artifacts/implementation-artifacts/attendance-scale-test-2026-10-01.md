# Attendance module — exhaustive scale test (2026-10-01 overnight run)

**Context:** 19-6 shipped (Epic 19 closed: fenzit-be `8f791a1`, fenzo-app `add0b49`, meta `545cf40`). The user directed: seed 100 dummy employees (50/office), rigorously device-test the whole attendance module at that scale, verify the DB via Supabase MCP at every step, fix findings at the owning layer (BE/FE/DB), and leave a morning report.

**Scale fixture (production, tenant `792b28ed` = Ayush):** `Loadtest H01–H50` → Hero wala (`25d66e88…`), `Loadtest Y01–Y50` → Yuka (`c597dde7…`); phones `+91 9000000001–9000000100`; all active with periods `[2026-09-30,∞)` + covering assignments (the same anchor as the real employees). **102 tracked employees total** with Arya+Suresh. Dummies CAN log in on the dev build (their phones exist; the DEV OTP chip shows) — used for clean employee-side probes without touching real employees' state. Removal recipe: `delete from attendance_enrolments/attendance_office_assignments where employee_id in (select id from users where name like 'Loadtest%'); delete from users where name like 'Loadtest%'` (+ any attendance_records left from probing).

## Surfaces × checks (execution log inline)

### Owner side (device: dev build, owner Ayush)
1. **Home tile → hub** — tile gates on the tenant flag (19-5a). [state]
2. **Dashboard (19-4)** @102: KPI tiles (Tracked should read 102), Flags strip, office filter (Hero 51 / Yuka 51), load/render behavior, payload sanity.
3. **Monthly (19-5)** @102: September list (all-zero chips for dummies — honest), office filter counts, param-load skeleton, drill-down → RealMonthPane, day sheet; **correction write on a DUMMY day** (real write path, dummy data) → chips update; flag-row deep-link.
4. **Leave (17-x)**: pending queue; on-behalf apply for a dummy → approve → revoke (full write cycle on dummy data, DB-verified: request + events + day-statuses).
5. **Enrolments (15-x)**: roster @102; picker (cap?); enable→disable→enable cycle on a dummy (history_only round trip through the OWNER path).
6. **Offices (15-x)**: read both lists; (writes only if a scratch-safe path exists).
7. **Settings (15-x)**: weekly offs + holidays screens render (reads; no rule writes — they'd move REAL employees' statuses).
8. **Notifications/deep-links**: an attendance card lands on its target.

### Employee side (device: dummy login `+91 9000000001` = Loadtest H01)
9. **Tab**: intro gate (never onboarded → AttendanceIntro), summary, My month (fresh: October zeros → check-in → bridge flips today's cell + so-far), check-in GPS flow (real write), check-out, chips update.
10. **Leave apply (17-5)**: preview + submit for a dummy (real 201), history row appears.
11. **My month parity (FR-11)**: dummy's chips vs the owner's monthly row for the same employee+month — must match exactly.

### Cross-cutting
12. **Perf**: screen-load behavior at 102 (dashboard, monthly, enrolments roster, picker); any list without pagination becomes a finding (fix placement: BE payload/pagination first).
13. **DB verification**: every write cross-checked via MCP (counts, view rows, events, overrides).
14. **Bug loop**: per finding — fix placement analysis (BE/FE/DB by root cause + long-term contract) → fix → retest → note in the report.

## Findings log (final)

**Zero new bugs from the scale test.** Every surface worked at 102 tracked employees; every write was DB-verified via MCP. Dismissals below carried evidence before being closed.

| # | Surface | Result |
|---|---|---|
| 1 | Hub @102 | PASS — 5 production tiles, the Component-lab tile GONE (retirement device-verified) |
| 2 | Dashboard (19-4) @102 | PASS — Tracked 102 = Not-checked-in 100 + On-leave 1 (Arya) + 1 with a record (H01); Late 0; Sites pill 3; per-office tallies 51/51/0 exact; office filter refetch verified (51 → 49 not-in after applying Hero wala) |
| 3 | Monthly (19-5) @102 | PASS — 102-row list rendered; Arya's row = her exact September truth; H01 "0 worked · 1 absent" (single tracked day); drill-down › disabled-until-echo then enabled; office filter tallies |
| 4 | Correction write (18-4) | PASS on dummy data — the 18-4 stage (prefilled times) → note → Save → DB override + `attendance_corrections` audit row ("Loadtest correction probe") + morph-back; the sheet's identical-facts + owner-only "Correct day" entry rendered beside the employee's read-only posture (read-only vs write verified side by side) |
| 5 | Leave cycle (17-x) | PASS — employee apply (201, DB row + "1 working day" preview) → owner Pending queue shows it → Approve → `leave_events` apply→approve → queue "No pending requests"; notification card "Loadtest H01 applied for leave" → deep-link lands on the Leave screen |
| 6 | Enrolments (15-x) @102 | PASS — roster renders all 102 with offices; owner disable → `history_only` + `attendance_ended_on=2026-09-30` (view-computed); re-enable → office-pick step ("Where does Loadtest H01 work?") → `active` from 2026-10-01 |
| 7 | Geofence gates | PASS live — "You are 1357 m from Hero wala. Move within 150 m." (real distance); after the 17-8-pattern temp pin move: check-in succeeded at 3.6 m (`checkin_mocked=false`), checkout math exact ("Early by 713 min" = 16:00−4:07); **pin reverted + verified** |
| 8 | Check-in bridge (R1) | PASS live — today's calendar glyph swapped to checked-in IN PLACE on check-in (and again on checkout) with no remount; the summary chips stayed correct throughout (the 1-minute day grades ABSENT per the 4h half-day floor → 0 credit) |
| 9 | Notifications | PASS — 12 unread; fresh leave card; deep-link lands on Leave |
| 10 | 19-6 self view @scale | PASS (walkthrough §6 record) — both postures, R9 fixed + re-verified live |

**Dismissed with evidence (not bugs):**
- *Dummy's weekly offs "Fri" vs Arya's "Sun"* — the tenant default is `[5]` (Fri); Arya has a per-employee override `[7]` (`attendance_weekly_off_overrides`). Both screens render their wire truth.
- *Day sheet "Absent" with full check-in/out rows* — Hero wala's rules: full ≥ 7.00 h, half ≥ 4.00 h; worked 0h01m grades absent (flags retained). Engine-consistent; the owner monthly row and the employee sheet agree (FR-11, one aggregation).
- *Summary chips not refetching on check-in* — the bridge deliberately refreshes the day grid only; me/monthly heals on the next focus (30 s min-gap). The chips were correct throughout here; a grade-changing day (≥4 h) would be the case to watch, recorded as a designed seam.

**Scale/perf:** no pagination walls, no multi-second stalls observed on dashboard/monthly/enrolments at 102 rows; payload scale ≈ 102 × ~300 B for the monthly list — far under the egress tripwire.

**Fixture recipe (removal):** `delete from attendance_enrolments where employee_id in (select id from users where name like 'Loadtest%'); delete from attendance_office_assignments where employee_id in (select id from users where name like 'Loadtest%'); delete from attendance_records where employee_id in (select id from users where name like 'Loadtest%'); delete from leave_requests where employee_id in (select id from users where name like 'Loadtest%'); delete from users where name like 'Loadtest%'` (H01 also has 1 correction + override — same employee_id filter catches them). Leave H01's approved 5 Oct request or delete first — owner's choice.

**Release build:** `assembleRelease` BUILD SUCCESSFUL (14m39s), all 4 ABIs signed `CN=Fenzit Technology` (verify-release-signing OK). Pixel 6 APK: `~/Desktop/fenzit-release-arm64-1.0.0.apk` (+ all ABIs in `fenzo-app/android/app/build/outputs/apk/release/`). NOTE: a release build has no DEV OTP chip and production OTP delivery is still the Render-log mock (DLT pending, due 17/10) — a fresh release install cannot log in until SMS is live; installing over the dev app is also blocked by the different signing key. Best consumed once DLT lands.
