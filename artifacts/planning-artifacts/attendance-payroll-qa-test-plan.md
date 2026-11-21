# Epic 25 — Attendance + Payroll QA: Test Plan & Case Suite

Owner-commissioned epic (2026-11-20). Overnight autonomous execution run declared 2026-11-20
("you are on your own, complete all tasks by morning") — the owner-confidence gate (story 25-3)
is satisfied by presenting THIS document in the morning report; owner may veto/adjust after reading.

Repos: `workspace/core/backend/fenzit-be` (BE) · `workspace/core/frontend/fenzit-web` (W) ·
`workspace/core/frontend/fenzit-app` (M) · Supabase `pnlvreaijzslfymlnoti` (DB).
BE base for execution: `https://fenzit-be-1.onrender.com/api/v1` (Render direct; CF worker
`api.fenzit.com` sits in front in prod).

---

## §1 World reference — "PayrollQA Works" (deterministic seed)

All ids are `md5('pqa-…')` UUIDs; tenant id `f40051bd-bc59-0264-bd3b-1afffc625aa8`
(`md5('pqa-tenant')`). **Today during execution = 2026-11-21.**

### 1.1 Identities & logins

| Who | Phone | JWT at `exec/tokens/<phone>.json` |
|---|---|---|
| Owner (company_admin) | 7700099000 | ✅ minted |
| Viewer (viewer role) | 7700099001 | ✅ |
| Employees | 7700000001 … 7700000200 | 29 minted (n1,2,3,4,5,6,11,31,51,71,76,82,106,121,136,140,141,142,145,151,153,160,161,171,176,186,196,197,198,200) |

Master OTP 1039 works on live BE (OTP_DEV_ECHO). `employeeCode` = EMP-001…EMP-202 (owner/viewer take 001-002 slots).

### 1.2 Attendance config

- **Offices** (id → facts): HQ Whitefield `12.9698,77.7500` r=100m, 09:00-18:00, late grace 15m, full 8h, half 4h · Hoskote Warehouse `13.0750,77.7950` r=250m, 08:30-17:30 · Mysuru Branch `12.2958,76.6394` r=500m, 10:00-19:00. Rules valid `[2026-09-01,)`.
- **Office assignment map** (verified): HQ → n1-160 + n191-195 (P-O: HQ until 2026-10-14, Hoskote from 2026-10-15) · Hoskote → n161-175 · Mysuru → n186-190, n196-200.
- **Weekly-off**: tenant default `[7]` (Sunday, ISO). Overrides: n71-80 `[5,6,7]` (Fri/Sat/Sun), n191-192 `[6]` (Sat), n199 `[]` (works all 7 days).
- **Holidays**: 2026-10-02, 2026-11-01 (Sun), 2026-11-10, 2026-11-24.
- **Enrolments**: 190 (n151-160 never enrolled); `enabled_at` = each employee's join day 06:00 IST (2026-09-01 … 2026-10-31). Enrolment+assignment pairs satisfy the deferred coverage guard.

### 1.3 Persona map (n = employee number; punches verified via live monthly API)

| Bucket | n | Design | Verified October monthly outcome |
|---|---|---|---|
| P-A | 1-10 | Model: punches every day incl. Sun+holidays; in 09:10 / out 18:10 (Mon out 18:30) | worked 26, workedOnHoliday 5 (4 Sun + Oct 2), late 0, absent 0 |
| P-B | 11-30 | ½-day-by-hours Oct 7 (09:05→13:30, 265 min), checkout-missing Nov 6 | worked 25.5, halfDays 1, late 0 |
| P-C | 31-50 | In 09:40 / out 18:40 (**late 20m**), Fridays 08:45→17:10 (early, 505 min → present) | worked 26, lateCount 22 |
| P-D | 51-70 | Short Tuesdays Oct 6, 20, Nov 3, 17 (09:05→11:50, 165 min < 240 → absent-with-punches) | worked 24, absent 2 |
| P-E | 71-90 | Leave takers (weekly-off [5,6,7]); requests g71-g82 below | per request |
| P-F | 91-105 | No punch Mon+Thu (unpunched → absent LOP) | worked 17, absent 9 (Mon 4 + Thu 5) |
| P-G | 106-120 | Check-in but no check-out on Mondays (paid, flagged) | worked 22, checkoutMissing 4 |
| P-H | 121-135 | Rejected/cancelled/revoked leave requests (days punched → present) | present on those days |
| P-I | 136-150 | Adversarial attempts: g136 2× mocked unacked (Oct 14/16), g137 low_accuracy 180m, g138 1× mocked **acknowledged**, g139 stale_fix 45s, g140 3× stale_fix counted + **armed block** `blocked_until ≈ Nov 22` + 1× rate_limited | days present; flags per above |
| P-J | 151-160 | Never enrolled (no attendance UI, no assignment); n151 has structure (skip `never_enrolled`); n152 structure + join 2026-12-01 (skip `empty_window`); n153-160 no structure (skip `not_configured`) | excluded from monthly roster |
| P-K | 161-170 | Enrolled (Hoskote), no salary structure → payroll skip `not_configured` | normal attendance |
| P-L | 171-175 | Join 2026-10-25 (Hoskote, 08:30 start → 09:05 punch = **late 35m** every day) | worked 6 (Oct 26-31), late 6 |
| P-M | 176-185 | Join 2026-10-31 (one payable day in Oct) | worked 1 |
| P-N | 186-190 | Exit 2026-11-15 (Mysuru) — final-run window Nov 1-15 | worked 26 (Oct) |
| P-O | 191-195 | Office move HQ→Hoskote on 2026-10-15; n191-192 weekly-off `[6]` (work Sundays) | Oct 5 records at HQ; Sundays worked |
| P-P | 196-200 | Exclusions/omissions: n196 PF-excluded + no UAN; n197 no PAN (+PF-excluded, DB-verify); n198 has UAN → exclusion-refusal test; n199 works all 7; n200 normal | n196/n199/n200 at Mysuru |

### 1.4 Leave world (requests g↔n: g71=n71 … g82=n82, g121=n121, g122=n122, g123=n123)

| Req | n | Type | Dates | State | Expected effect |
|---|---|---|---|---|---|
| g71 | 71 | Earned | Oct 20-21 | approved | 2 working-day debit |
| g72 | 72 | Sick | Nov 5 | approved | 1 debit; revoke-refusal test (all dates past) |
| g73 | 73 | Earned | Oct 28 → Nov 3 | approved | **ownership-span**: debit = 4 working days (Oct 28, 29 + Nov 2, 3; Oct 30 Fri = n71? no — n73 weekly-off {5,6,7} → Oct 30 Fri, 31 Sat, Nov 1 Sun off → 0) |
| g74 | 74 | Earned | Nov 27-28 | **pending** | owner-approve happy path; Nov 28 Sat → debit 1 |
| g75 | 75 | Sick | Nov 23 | **pending** | owner-reject happy path |
| g76 | 76 | Bereavement | Oct 12-13 | approved | annual grant 5 → remaining 3 |
| g77 | 77 | Earned **first_half** | Nov 13 | approved + punch 14:00→18:10 (250 min) | half_day_leave, debit 0.5 |
| g78 | 78 | Earned | Nov 7 (Sat) | approved | 0 debit (weekly-off overlap); day graded weekly_off |
| g79 | 79 | Sick | Oct 15 | rejected | day present (punched) |
| g80 | 80 | Earned | Oct 8-9 | cancelled | day present |
| g81 | 81 | Earned | Oct 5-6 | revoked | day present |
| g82 | 82 | **Comp-Off** | Nov 4 | approved | zero comp-off balance → overdraw |
| g121 | 121 | Sick | Oct 12 | rejected | day present |
| g122 | 122 | Earned | Oct 19-20 | cancelled | day present |
| g123 | 123 | Earned | Nov 2-3 | revoked | day present |

Leave catalog (fixed 4): Earned (monthly 1.00, CF on) · Sick (monthly 0.50) · Bereavement (annual grant 5) · Comp-Off (no accrual). Manual credits: n71 Earned **+3.00**, n72 Earned **−1.00**. FY = April-March.

### 1.5 Payroll config

- Components: **Basic salary** `4697cb8f-…` (isBasic) · HRA `eb2597f1-…` · Conveyance `6acbfbaf-…` · Special Allowance `62370ef6-…`.
- Structures (180: n1-150 ∪ n151,n152,n171-200), effective 2026-09-01. Basic tier = n%10 (0→15000, 1→25000, 2→30000, 3→45000, 4→60000, 5→80000, 6→35000, 7→20000, 8→50000, 9→12000). HRA = formula `40% of Basic` when n%3=0, else flat 6000. Conveyance flat 1600. Special = formula `10% of Basic` when n%5=0, else flat 2000.
- Deduction heads: **Staff Welfare** flat 200.00 eff 2026-09-01 · **Transport Levy** 2.00% of gross eff **2026-11-01** (→ absent in Oct payslips, present in Nov).
- PF: covered eff 2026-09-01; exclusions n196 + n197 (DB-verify n197). PF = 12% × min(earned basic, ceiling ₹25,000).
- Calendar: eff 2026-09-01 → divisor `fixed-26`, cutoffDay 25, payDate 1. TDS = FY2026-27 statutory slabs + ₹75k std deduction + s.157 rebate + 4% cess (compute expected from `GET /payroll/tds-config` at execution).

### 1.6 Monthly-summary column semantics (observed from live API, Oct 2026)

`daysWorked` = Σ day-credits (half day = 0.5; worked-on-weekly-off/holiday **not** included) · `halfDays` · `lateCount` (in > start+grace) · `leave` = approved full-day-leave days · `weeklyOffs` = **unworked** weekly-off days · `holidays` = unworked holidays · `workedOnHoliday` = worked days on weekly-off **or** holiday · `absent` · `checkoutMissing`. Rows = 190 tracked employees (P-J excluded).

### 1.7 Run-month framing

- **October 2026 run** — completed month. LOP ownership: Oct dates ≤ cutoff 25 → Oct run; Oct 26-31 → **November** run as prior-period.
- **November 2026 run** — executed mid-month (~Nov 21): owns Nov 1-25 + prior Oct 26-31; Nov 21+ future not graded. Payable = divisor 26 − LOP (full-month employment).
- Skip taxonomy (payroll): `missing_join_date → not_configured → empty_window → never_enrolled`. **Expected Oct/Nov baseline: payslips 180, skips 20** = never_enrolled(n151) + empty_window(n152) + not_configured(n153-160, n161-170).

---

## §2 Capability inventory (what actually ships, per layer)

### 2.1 BE (guard chain: JwtAuthGuard → PermissionsGuard → SubscriptionExpiryGuard; roles = permission sets; the ONLY rate limiter is the attendance punch 429)

**Attendance**: setup wizard `GET/POST/PATCH /attendance/setup`, `POST /attendance/setup/complete` · offices `GET/POST /attendance/offices`, `GET/PATCH /:id`, `POST /:id/archive`, `GET /:id/archive/preview` · weekly-offs `GET/PUT /attendance/weekly-offs`, `GET /overrides`, `PUT/DELETE /overrides/:employeeId` · holidays `GET/POST /attendance/holidays`, `GET /impact`, `PATCH/DELETE /:id` · enrolments `GET /attendance/enrolments`, `PUT /:employeeId`, `PUT /:employeeId/office`, `DELETE /:employeeId` · punch `POST /attendance/me/check-in|check-out` (X-Idempotency-Key UUIDv4 → 422; validation ladder stale_fix > low_accuracy > too_far > mocked → 422 codes `ATTENDANCE_TOO_FAR/LOW_ACCURACY/MOCK_LOCATION/STALE_FIX`; 429 `ATTENDANCE_RATE_LIMITED` + Retry-After; checkout 409 `ATTENDANCE_NOT_CHECKED_IN/ALREADY_CHECKED_OUT`) · corrections `PUT/DELETE /attendance/corrections/:employeeId/:workDate`, `GET /attendance/corrections`, `POST /attendance/attempts/acknowledge`, `GET /attendance/me/corrections` · day statuses `GET /attendance/day-statuses`, `GET /attendance/me/day-statuses` · monthly `GET /attendance/monthly` (span ≤ 31 days), `GET /attendance/me/monthly` · dashboard `GET /attendance/dashboard`.

**Leave**: types `GET/PATCH /attendance/leave/types[/:id]` · admin `GET /attendance/leave`, `GET /:employeeId/balances`, `POST /credits`, `POST /:id/approve|reject|revoke`, `GET /:id/preview`, `PATCH /:requestId/type`, `GET/POST /on-behalf[/preview]` (born-approved) · self `GET/POST /attendance/me/leave`, `GET /types|balances|preview`, `GET /:id/preview`, `POST /:id/cancel`.

**Payroll**: components `GET/POST /payroll/components`, `PATCH/PUT /:id` · structures `GET/PUT /members/:userId/salary-structures` · heads `GET/POST /payroll/deduction-heads`, `PUT /:headId/deactivate` · statutory `GET/PUT /payroll/pf-config`, `GET/PUT /payroll/employees/:userId/pf-exclusion`, `GET /payroll/tds-config` · calendar/lock `GET/PUT /payroll/calendar`, `GET /payroll/months/:month`, `POST/GET /payroll/months/:month/lock`, `GET /payroll/audit`, `GET/PUT /payroll/state-rules` · runs `POST /payroll/runs` (202 async), `GET /payroll/runs[/:runId]`, `PUT /payroll/employees/:userId/run-override` (tds|pf_employee, liability ack) · off-cycle `POST/GET /payroll/off-cycle-lines`, `PATCH/DELETE /:id` (staged only) · payslips `GET /payroll/payslips?month=`, `GET /payroll/payslips/me[/:month]`, `POST /payroll/payslips/me/:month/pdf`, `POST /payroll/payslips/:membershipId/:month/pdf` · reports `POST /reports` (attendance|technician-job-activity|payslip; ≤92 days; IST future check), `GET /reports[/:id]`, `POST /:id/retry`, queue `GET /reports/queue/status`, `POST /reports/queue/pause|resume`. **PDF-only exports (no CSV endpoint); presigned R2 URLs ~10 min.**

**Lock contract**: `POST /payroll/months/:month/lock` permanent; 409 `PAYROLL_MONTH_LOCKED` / `PAYROLL_RUN_IN_PROGRESS` / `PAYROLL_MONTH_NOT_RUN`; freezes corrections + leave apply/approve/revoke/re-type by date ownership; re-run of completed month allowed (destroy-and-replace payslips).

### 2.2 Web admin (`/admin/*`, role-gated loaders)

- `/admin/company` Overview — pulse tiles, flags line, read-only leave card, job report, link cards.
- `/admin/company/attendance` (owner) — tabs month|report; 4 tally tiles; table (Employee/Office/Worked/Half/Late/Leave/Absent); chips All/Present/Late/Absent; office + sort + pager; **client-side CSV export** (11 columns); Report tab = ReportExportCard (From/To, Download report, history Download/Retry). **Month fixed to current month — no switcher.**
- `/admin/company/holidays` — **read-only** list.
- `/admin/company/employees` — tiles, filters, invite dialog, Export CSV, Job settings, Employment details dialog (joinDate/exitDate/PAN/DOB/UAN/PF/bank…).
- `/admin/company/payroll` (owner) — 7 tabs: Components · Structures (formula editor) · Deductions · Statutory (PF + exclusions + TDS read-only) · Calendar (rows + month probe + state rules) · Runs (MonthCard, Run payroll/Run again, in-flight Refresh — **no polling**, summary card, lock dialog, override dialog, off-cycle read-only list, run history) · Audit.
- `/admin/me` (member) — identity, attendance facts, this-month, my leave (read-only).
- Staff `/admin/inspect` — read-only dossier incl. attendance/leave/offices.
- **Confirmed web gaps**: no day-grid, no corrections UI, no leave approval/request UI, no offices/weekly-off/enrolment UI, holidays read-only, **no payslip view/PDF**, no report-queue pause UI, off-cycle staging read-only.

### 2.3 Mobile (com.fenzit; employee stack + owner stack)

- Employee: Today punch host (prescreen probe, offline blocks at tap+confirm, dialogs holiday/full-day-leave/service-off/permission-off, `ATTENDANCE_LEAVE_CONFIRMATION_REQUIRED` → confirm-cancel-leave retry, rate-limit countdown, ALREADY_* → silent refetch) · Attendance tab (access-driven: active/upcoming/history_only; tab unregistered when none) · AttendanceIntro onboarding · My Month calendar + DayDetailSheet (readOnly; markers corrected/leave_pending/checkout_missing/fake_location_attempt; correction quote) · LeaveApply (type sheet, zero-balance muted, halves single-date-only, live preview, balances card) · Leave history + detail + CancelSheet + future-half-day→full-day ConvertStage.
- Owner: Attendance tab Today|Monthly|Leave panes · AttendanceDashboard (6 tiles, flag strips, office filter) · Monthly rows + employee month drill-down (day sheet → **Correct day** status-XOR-instants form + history) · setup wizard, Offices/MapPinPicker, Enrolments, WeeklyOff, Holidays screens · OwnerLeave queue (approve/reject/revoke, balances card) · ApplyOnBehalf (born-approved).
- Employee payroll: Payslips list (locked months, PDF badge) · detail (earnings/deductions mapped sources, as-of-lock balances, warnings) · PDF poll ≤60s.
- **Mobile gaps**: no payroll admin surfaces, no leave-type editor, no standalone balances screen, no fake_location notification card (deliberate), no offline punch queue, no employee self-correction.

### 2.4 DB

No native enums (CHECKs) · coverage guard `23514 ATTENDANCE_ASSIGNMENT_GAP` (DEFERRABLE) · `leave_request_days_state_guard` · partial unique `(employee_id, leave_date) WHERE pending/approved` · RLS deny-by-default (no policies) on attendance/leave/payroll tables · `leave_events.seq` GENERATED ALWAYS.

---

## §3 Conventions

- **IDs**: `H-n` happy · `C-n` corner · `E-n` end-to-end · `N-n` negative. **Layers**: W web · M mobile-device · BE API · DB SQL.
- **Verdicts**: PASS · FAIL (expected ≠ actual, evidence quoted) · BLOCKED (setup impossible) · SKIP (out of window) — every case gets a ledger row with evidence + timestamp.
- **Execution protocol**: documentation-only during the wave (standing owner rule); failures triaged after the wave → batch fixes with FE/BE/DB placement analysis → BMAD review → commits (overnight autonomy grant).
- **Order sensitivity** (§5 phase plan): October lock happens LAST (all Oct re-run cases precede it); November mutations re-run November.
- Case-count: **H 44 · C 44 · E 44 · N 60 = 192** (requirement was ≥40 each).

---

## §4 Execution prerequisites (done / to-do)

- [x] 31 QA JWTs (`exec/tokens/`) · live BE reachable · monthly API reconciled vs seed
- [ ] `QA Desk Office`: read device GPS → create office via API (r=300m) → assign n200 (punch device cases)
- [ ] Complete attendance setup state if `GET /attendance/setup` shows incomplete
- [ ] Metro debug build → Pixel 6 (M cases) · Vite dev server 5173 → live API (W cases)

---

## §5 Happy-path cases (44)

| ID | L | Data | Steps → Expected |
|---|---|---|---|
| H1 | W | owner | Login (OTP 1039) → `/admin/company` renders: 6 pulse tiles, flags line, leave card, link cards. |
| H2 | W | member n2 | Login → redirected to `/admin/me`; attendance facts + this-month + my leave render. |
| H3 | BE | Oct | `GET /attendance/monthly?from=2026-10-01&to=2026-10-31` → 190 rows; anchor rows match §1.3 (n1 26/5woH; n11 25.5+1; n31 26+22late; n51 24+2abs; n91 17+9abs; n106 22+4cm; n171 6+6late). |
| H4 | W | Oct | Attendance month tab: chips Present (≈135) / Late (20: P-C) / Absent (P-D 20 + P-F 15) filter the table; counts per BE. |
| H5 | W | Oct | Office dropdown Hoskote → rows = Hoskote-assigned only (n161-175 + P-O post-move). |
| H6 | W | Oct | Export CSV → 11 exact columns; row count = table roster; sample rows n1/n51/n77 match API. |
| H7 | W+BE | Oct1→Nov19 | Report tab → Download report (attendance_report) → 201 queued → poll to completed. |
| H8 | W+BE | H7 | History list shows the report; Download fetches presigned URL; PDF opens. |
| H9 | W+BE | Runs | Runs tab MonthCard: Divisor 26 / Cut-off 25 / Pay date 1 / Governed by 2026-09-01 calendar. |
| H10 | BE | Oct | `POST /payroll/runs {month:2026-10}` → 202; poll → completed; summary employees 200, payslips 180, skips 20 (1 never_enrolled + 1 empty_window + 18 not_configured). |
| H11 | BE+DB | Oct n1 | Payslip: Basic 15000.00, HRA 6000.00, Conv 1600.00, Spec 2000.00, head:Staff Welfare 200.00, pf_employee 1800.00, tds per config, net = gross − deductions; payable 26; no Transport Levy. |
| H12 | BE | Oct n51 | LOP 2 → payable 24; per-line ×24/26 half-up: 23076.92 / 9230.77 / 1476.92 / 1846.15; PF 12%×23076.92 = 2769.23. |
| H13 | BE | Oct n171 | Join Oct 25 → payable = engine's window metric (worked credits 6; calendar window 7) — assert payslip LOP/earnings consistent with whatever rule fires and DOCUMENT it; gross 38600. |
| H14 | BE | Oct n176 | Join Oct 31 → payable 1; per-line ×1/26: 1346.15 / 230.77 / 61.54 / 76.92. |
| H15 | BE | Oct n186 | Exit Nov 15 → full Oct payable 26, LOP 0; gross 52600. |
| H16 | BE | Oct n196 | PF-excluded → **no pf_employee line**; welfare + tds present. |
| H17 | BE | Oct n197 | No PAN: payslip renders; PF per exclusion state; TDS behavior (206AA or normal) DOCUMENTED. |
| H18 | BE | Oct | NO payslip carries a Transport Levy line (head eff 2026-11-01). |
| H19 | W | H10 | Runs tab summary card: Employees 200, Payslips 180, skipped pills, off-cycle 0/0; history row present. |
| H20 | W | — | Components tab lists 4; Basic salary flagged. |
| H21 | W | n3 | Structures tab: revision 2026-09-01, Basic 45000; HRA formula computed 18000.00; Special formula 4500.00. |
| H22 | W | — | Deductions tab: Staff Welfare flat 200 eff 2026-09-01; Transport Levy 2% gross eff 2026-11-01. |
| H23 | W | — | Statutory tab: PF covered eff 2026-09-01; exclusions show n196 (+n197 per DB); TDS slabs table renders FY2026-27. |
| H24 | W+BE | — | Calendar tab: row 2026-09-01 fixed-26/25/1; month probe `2026-10` Check → resolved values + state. |
| H25 | W | — | Audit tab lists config saves (+ run entry after H10). |
| H26 | BE | Oct (LAST) | `POST /payroll/months/2026-10/lock` → success; GET lock → record; month probe state locked. |
| H27 | W | Oct (LAST) | Runs tab LockCard → "Lock this month…" → confirm dialog → Locked badge. |
| H28 | BE | viewer | viewer: monthly 200; components 403; POST /reports 2xx; queue/pause 403. |
| H29 | M | owner | Attendance tab 3 panes render; setup banner state per `GET /attendance/setup`. |
| H30 | M | owner | Monthly pane: month chips (future disabled); Oct rows per §1.3; row tap → employee month. |
| H31 | M | owner | Today pane (fresh day, pre-punch): On attendance = tracked active count; Checked in 0; Not checked in = tracked; Late 0; On leave 0; flag strips empty/0. |
| H32 | M | n11 | Attendance tab active: punch card not-checked-in; summary office HQ 09:00-18:00 late 09:15 weekly-off Sun. |
| H33 | M | n11 | My Month (Nov): Nov 6 checkout_missing marker; legend; day sheet times. |
| H34 | M | n51 | My Month (Oct): Oct 6 + 20 absent badges; day sheet shows 09:05/11:50 + absent. |
| H35 | M | n71 | Leave balances card: Earned = accrual + 3 − availed(g71 2 + g73 4) ; Sick; Bereavement 5; Comp-Off 0. |
| H36 | M | n2 | LeaveApply: 4 types; Comp-Off muted (zero balance); live preview working-days. |
| H37 | M | n1 | Payslips list (after E1): October row net + Ready badge. |
| H38 | M | n1 | Payslip detail: earnings/deductions lines match API; PF — employee share / TDS / Staff Welfare; as-of-lock balances. |
| H39 | M | n1 | Payslip PDF: request → poll ≤ 60s → Open PDF renders. |
| H40 | BE | Oct | `GET /payroll/payslips?month=2026-10` → 180 snapshots (pre-lock preview allowed). |
| H41 | BE | today | `GET /attendance/dashboard` tiles structurally consistent with monthly roster. |
| H42 | BE | n2 | `GET /attendance/me/monthly` (Nov): own rows + weekly-off [7] + next 10 upcoming incl. Nov 24. |
| H43 | BE | n2 | `GET /attendance/me/summary`: office HQ, shift, late 15, weekly-off [7], today working. |
| H44 | BE | n76 | `GET /attendance/leave/:employeeId/balances`: Bereavement 5 − 2 = 3; Earned/Sick per accrual − availed. |

## §6 Corner cases (44)

| ID | L | Data | Steps → Expected |
|---|---|---|---|
| C1 | BE | g73/n73 | Oct payslip n73: g73 contributes **no Oct LOP/debit** (dates ≤25 owned? Oct 28-31 owned by Nov); Nov run: debit = 4 working days (Oct 28,29 + Nov 2,3); Oct 30/31 + Nov 1 = n73 weekly-off → 0. |
| C2 | BE+DB | g78/n78 | Leave on weekly-off: debit 0; day-status Nov 7 weekly_off (leave marker data-only). |
| C3 | BE | g77/n77 | Half-day leave + punch 250 min → half_day_leave; debit 0.5; monthly halfDays +1. |
| C4 | BE | g82/n82 | Comp-Off approved at zero balance → derived remaining −1.0 (Overdrawn by 1.0). |
| C5 | BE | n199 | Weekly-off `[]`: Sundays present; Oct worked 27-ish, LOP 0; monthly weeklyOffs 0. |
| C6 | BE | n191/192 | `[6]`: Saturdays weekly_off (Oct 3,10,17,24,31); Sundays present. |
| C7 | DB+BE | n191 | Records Oct 14 office HQ r100; Oct 15+ Hoskote r250 (boundary exact). |
| C8 | BE | n31 vs n1 | Late boundary: 09:40 → late 20m; 09:10 → late 0 (grace 15m). |
| C9 | BE | n11/n51/n31 | Three-tier worked grading: 265 min → half_day; 165 → absent; 505 → present. |
| C10 | BE | n106 | checkout_missing: LOP 0 (paid) + flag; Nov run payable 26. |
| C11 | BE+M | n151 | Untracked: access `none`; monthly roster excludes; mobile tab unregistered. |
| C12 | BE | n186-190 | Exit Nov 15: access → history_only; Nov run window Nov 1-15 → payable = engine metric on worked credits 12 (document rule). |
| C13 | BE | n197 | TDS without PAN — document (206AA vs normal). |
| C14 | BE | Oct+Nov | Transport Levy boundary: absent Oct, 2% × gross Nov (source head:Transport Levy). |
| C15 | BE | n198 | PF-exclusion refusal: PUT exclusion on UAN holder → 4xx. |
| C16 | BE | n1 | Divisor cap: worked credits 26 (=cap) → payable 26; no over-credit beyond 26. |
| C17 | W+BE | Dec | PUT calendar fixed-30 eff 2026-12-01 → Dec probe divisor 30; Oct probe still 26. |
| C18 | BE | types | PATCH earned accrual 1.00→1.25 → balances behavior DOCUMENTED (past months re-derived or not). |
| C19 | BE | n3 | Mid-month structure revision eff 2026-11-15 → Nov run structure choice DOCUMENTED. |
| C20 | BE | — | Rename Basic salary → next-run line label changes; old payslip immutable. |
| C21 | BE | — | Deactivate Transport Levy → Nov re-run drops the line. |
| C22 | BE | types | Over-balance toggle → apply-beyond-balance allowed/refused per policy. |
| C23 | BE+M | n2 | Nov 1 = Sunday + holiday: day-status label priority DOCUMENTED (weekly_off vs holiday). |
| C24 | BE | n1 | Rounding divergence probe: Σ per-line vs structure-total on n51 (35630.76 vs 35630.77) — document which the run stores. |
| C25 | DB+BE | seq | `payroll_slip_sequences` on first run (0001+) — numbering captured. |
| C26 | BE | n5 | TDS high-bracket math: annual 1,147,200 − 75k → slabs + cess, half-up; payslip tds = computed. |
| C27 | BE | n6 | Recovery roll-forward: stage −40000 → capped at 50% net, remainder rolls to Dec (document). |
| C28 | BE | n200 | Enrolment start-date change → future-effective only (no retroactive grading). |
| C29 | BE | n3 | Weekly-off override PUT future effectiveFrom → current + pending rows. |
| C30 | BE | Nov 24 | Holiday rename OK; DELETE Nov 24 → impact preview shrinks. |
| C31 | BE | HQ | Office PATCH: radius immediate; timing rules effective tomorrow (response semantics documented). |
| C32 | BE | n136 | `POST /attendance/attempts/acknowledge` → acknowledged_at set; dashboard flag reflects. |
| C33 | BE | n141 | 3rd mocked attempt in month crosses FAKE_LOCATION threshold → flag appears. |
| C34 | BE | n145 | too_far attempts uncounted → no rate-block; low_accuracy counted. |
| C35 | BE | n140 | Armed block: valid-coords punch → 429 + Retry-After. |
| C36 | BE | n1 | Idempotency replay: same key, different body → document (422 vs first-wins). |
| C37 | BE | n5 | Correction instants overnight (in 23:00 → out next-day 07:00) → accepted, worked 8h (document). |
| C38 | DB | — | Enrolment insert without assignment → 23514 ATTENDANCE_ASSIGNMENT_GAP at commit. |
| C39 | DB | — | Twin approved leave same employee/date → 23505 partial unique. |
| C40 | DB | — | `leave_request_days_state_guard`: invalid state → 23514. |
| C41 | DB | — | RLS: no policies on attendance/leave/payroll tables (deny-by-default). |
| C42 | W | Oct | Attendance month tab has no month switcher (fixed current month) — gap behavior documented. |
| C43 | M | — | fake_location surfaces ONLY as dashboard flag + day marker, never a notification card. |
| C44 | BE | n1 | `GET /attendance/me/monthly` weekly_off weekdays + next-10 list ordering correct. |

## §7 End-to-end cases (44)

| ID | L | Flow | Expected |
|---|---|---|---|
| E1 | M+BE+W+DB | THE anchor: run Oct → payslips → lock Oct → admin payslip PDF (n1) → device n1 list+detail+PDF | All legs succeed; DB rows consistent |
| E2 | M+BE+W | n2 applies Nov 25 (mobile) → owner approves (mobile) → statuses → web leave card | pending→approved; balance −1; day statuses flip |
| E3 | M+BE+DB | on-behalf approved leave today for n200 → device check-in → leave-confirm dialog → confirm | leave auto-cancelled + record created |
| E4 | M+BE | on-behalf born-approved for n4 (Nov 26) | approved immediately; queue shows |
| E5 | BE+DB | correct n52 Oct 6 → present → re-run Oct | n52 LOP 1, payable 25, slip re-issued |
| E6 | M+BE+DB | reassign n200 QA-office→Mysuru → device punch | too_far (proves geofence switch); reassign back |
| E7 | M+BE | n3 override [5,6,7] from next Mon → apply leave spanning Sat | preview 0 debit for Sat |
| E8 | M+BE+W | owner adds holiday Nov 22 (mobile) → n2 My Month → API check-in n200 on holiday | worked_on_holiday; CSV column reflects |
| E9 | W+BE | add component QA Bonus + line 1000 for n4 → re-run Nov | payslip line QA Bonus 1000.00 |
| E10 | W+BE | head QA Uniform flat 150 eff Nov → re-run Nov | head:QA Uniform on all 180 slips |
| E11 | W+BE | PF exclusion writes: n197 (idempotent) + n198 refused → re-run Nov | n197 no PF; refusal 4xx |
| E12 | W+BE | structure for n161 → re-run Oct | not_configured 17; payslips 181 |
| E13 | BE+DB | enrol n151 + office → re-run Oct | never_enrolled 0; n151 payslip payable 26 (past days not_tracked→paid) |
| E14 | W+BE | n152: join Oct 1 (employment dialog) + enrol → re-run Oct | empty_window 0; n152 payslip (not_tracked paid) |
| E15 | W+BE | TDS override n5 Nov (1234.56 + ack) → re-run Nov | slip tds 1234.56 + warning + audit |
| E16 | W+BE | PF override n6 Nov (999.99) → re-run Nov | slip pf_employee 999.99 |
| E17 | W+BE+M | off-cycle recovery −1000 n6 Nov → run | recovery:2026-11 line; detail sheet shows it |
| E18 | BE | queue pause 2min → queue report → resume | held while paused, completes after resume |
| E19 | BE+W/M | n142: 3 mocked attempts → dashboard flag → acknowledge | flag lists n142; marker persists |
| E20 | BE | n140 blocked → clear block (SQL) → punch | 429 then success |
| E21 | W+BE | CSV vs API cross-check (n1, n51, n77) | values equal |
| E22 | W+BE | attendance PDF opens; page-1 contains Oct rows | visual pass |
| E23 | M+BE | dashboard office filter = Mysuru | tiles scoped (n186-190,196-200,200-QA) |
| E24 | W+BE | monthly office filter Hoskote | rows = Hoskote set |
| E25 | M+BE+DB | balances triangle n71 (card = API = payslip as-of-lock) | all three equal post-run |
| E26 | W+M+BE+DB | n160 full lifecycle: employment join Oct 1 (web) + structure (web) + enrol+office (mobile) + device punch + Nov run | payslip appears; 4-layer chain |
| E27 | BE+M | lock cascade (after H26): correction Oct 409; on-behalf Oct date 409; revoke g71 409; mobile n1 payslip visible | all refusals correct codes |
| E28 | DB+BE | capture slip ids → re-run Oct | destroy-and-replace: new ids, count 180, numbering behavior documented |
| E29 | W+BE | calendar cutoff 20 eff 2026-12-01 → Dec probe | Dec 20; Oct/Nov unchanged |
| E30 | M | tap leave.applied notification | opens OwnerLeave pending tab |
| E31 | W | member opens /admin/company | redirect /admin/me |
| E32 | BE+W | viewer requests report + views history; pause refused | 2xx / 403 |
| E33 | BE | monthly Nov 1-30 | future days (Nov 21+) not graded |
| E34 | BE | dashboard ⊆ monthly consistency | structural match |
| E35 | W+BE+DB | n7 HRA formula → flat 9999 → re-run Nov; Oct slip unchanged | Nov uses 9999; Oct immutable |
| E36 | M | n2 approved future half-day → Convert to full day | old cancelled + new full-day request |
| E37 | BE | holiday check-in accepted (n200 at QA office on added holiday) | worked_on_holiday |
| E38 | W+BE | employment PAN edit n197 → saved | GET reflects; payslip PAN behavior documented |
| E39 | W/M+BE | presigned URL freshness | refetch-on-focus pattern verified (or SKIP: 10-min wait) |
| E40 | BE | idempotent on-behalf (same key ×2) | 1 request |
| E41 | BE+DB | audit completeness (run+lock+override) | entries with actor |
| E42 | M+BE | n72 (−1 credit) apply beyond balance | preview refuses (or over-balance policy documented) |
| E43 | BE | tenant isolation: QA token + foreign ids | 404/403; monthly returns only QA employees |
| E44 | BE | forged/expired token | 401 |

## §8 Negative cases (60)

| ID | L | Attack | Expected |
|---|---|---|---|
| N1 | BE | check-in without X-Idempotency-Key | 422 |
| N2 | BE | idempotency key not UUID | 422 |
| N3 | BE | body missing lat/lng | 422 |
| N4 | BE | accuracyM negative | 422 |
| N5 | BE | owner token punches | 403 |
| N6 | BE | viewer token punches | 403 |
| N7 | BE | untracked employee punch (n153) | 4xx NOT_TRACKED |
| N8 | BE | double check-in | 409 ALREADY_CHECKED_IN |
| N9 | BE | check-out without check-in | 409 NOT_CHECKED_IN |
| N10 | BE | double check-out | 409 ALREADY_CHECKED_OUT |
| N11 | BE | monthly from>to | 422 |
| N12 | BE | monthly span 32 days | 422 |
| N13 | BE | monthly bogus employeeId | 404/403 |
| N14 | BE | leave apply no reason | 422 |
| N15 | BE | leave end<start | 422 |
| N16 | BE | half-day part on range | 422 |
| N17 | BE | disabled/unknown type | 422 |
| N18 | BE | over-balance apply | 422 preview+POST |
| N19 | BE | overlapping own pending/approved | 422/409 |
| N20 | BE | employee calls approve | 403 |
| N21 | BE | approve non-pending | 409 |
| N22 | BE | revoke empty reason | 422 |
| N23 | BE | cancel started leave | 422/409 |
| N24 | BE | revoke fully-past approved (g72) | 409/422 |
| N25 | BE | credits unknown employee | 404 |
| N26 | BE | run invalid month | 422 |
| N27 | BE | lock never-run Sep 2026 | 409 PAYROLL_MONTH_NOT_RUN |
| N28 | BE | lock already-locked Oct | 409/documented |
| N29 | BE | formula refs unknown component | 422 |
| N30 | BE | line with amount AND formula | 422 |
| N31 | BE | line with neither | 422 |
| N32 | BE | second isBasic component | 422 |
| N33 | BE | head flat+percent / negative | 422 |
| N34 | BE | PF exclusion UAN holder | 4xx (dup C15 — both executed) |
| N35 | BE | calendar cutoffDay 29 / payDate 8 | 422 |
| N36 | BE | off-cycle 3-decimals / 81-char label / bad month | 422 |
| N37 | BE | edit applied off-cycle line | 409 |
| N38 | BE | delete applied off-cycle line | 409 |
| N39 | BE | override bogus field / no ack | 422/403 |
| N40 | BE | payslip me bad month / n151 post-lock | 422 / 404 |
| N41 | BE | reports bad type / 93-day / future start / 26 offices | 422 |
| N42 | BE | retry completed report | 409 |
| N43 | BE | pause minutes 0 / viewer pause | 422 / 403 |
| N44 | BE | correction both+instants / future date / note 501 | 422 ×3 |
| N45 | BE | holiday duplicate date / rename-date | 422 |
| N46 | BE | office radius 30 / 1200; start ≥ end | 422 |
| N47 | BE | weekly-off days [0]/[8] | 422 |
| N48 | BE | weekly-off override untracked (n153) | 422 |
| N49 | BE | enrolment office for unenrolled (n153) | 422 |
| N50 | BE | invite duplicate phone | 409/422 |
| N51 | BE | employment PAN malformed | 422 |
| N52 | BE | cross-tenant id access | 404/403 |
| N53 | BE | forged/expired token | 401 |
| N54 | BE | punch during armed block, valid coords | 429 |
| N55 | BE | monthly for untracked id (n153) | 404/documented |
| N56 | BE | payslips month 2026-13 | 422 |
| N57 | BE | GET lock before lock | 404 (correct behavior) |
| N58 | BE | employee reads admin payslip list | 403 |
| N59 | BE | correction for untracked employee | 422 |
| N60 | BE | acknowledge attempts with none (n143) | 404/documented |

## §9 Execution phase plan

1. **P0** prereqs (QA office, setup state, Metro build, web dev server).
2. **P1** read-only BE/DB: H3-H9, H19-H25, H28, H40-H44, C7-C11, C16, C24-C44, N-non-mutating.
3. **P2** October baseline run → H10-H18, C1, C12(Oct), C14(Oct-part), C25, C26.
4. **P3** November baseline run → C10/C12/C13/C14(Nov), C27.
5. **P4** punch/attempt API cases: C32-C36, N1-N13, N54, E20, E37, E40, E43-E44.
6. **P5** mutations + re-runs: E5, E9-E17, E19, E26-E29, E35, E38, C17-C23, C28-C31, N29-N39, N44-N51.
7. **P6** web browser cases: H1, H4-H9, H19-H25, H27, E21-E24, E31-E32, C42.
8. **P7** device cases: H29-H39, E1(M-legs), E2-E4, E6-E8, E23, E25, E30, E36, E42, C11, C43.
9. **P8** October lock LAST: H26, H27, E27, N27, N28.
10. **P9** ledger consolidation → triage → batch fixes → review → commits → morning report.

Research substrate: 153 categorized internet scenarios (H/C/E/N × W/M/B/D) gathered during recon
(`epic-25` recon round, 2026-11-20) — happy-path flows, HRMS industry corner cases (half-day/LOP/
carry-forward/lock semantics), e2e lifecycle chains, and adversarial inputs; folded into the tables above.
