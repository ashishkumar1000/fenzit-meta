# Epic 23 regression matrix — 23-12 payslips + 23-14 leave balances + the "FE must not allow an unapplyable request" ruling

Overnight regression run 2026-11-20 (owner asleep, autonomy granted). Every
scenario lists: how it's pinned (unit/screen test), what the server owns,
and the device evidence (screenshots `/tmp/d*.png`, DB rows noted where the
scenario writes).

## 0. The case inventory the owner asked to "handle all" (the submit-gate ruling)

The FE must PREVENT submitting a request the server would refuse — visible
feedback, submit gated. Architecture: the BE preview
(`GET /attendance/leave/preview` + the NEW owner route
`GET /attendance/leave/on-behalf/preview`) runs the WRITE path's entire
validation ladder (type → shape → payroll-lock → facts → balance) via
`previewApplyTransact`, so there is ONE server truth and no FE balance
math. The FE renders `ok:false` verdicts verbatim and gates `canSubmit`
on `preview.status !== 'rejected'`. Transport failures fail OPEN (the BE
re-verdicts at POST).

| # | Case | Owner surface | Employee surface | Pin |
|---|------|---------------|------------------|-----|
| 1 | Insufficient balance | on-behalf verdict + Approve gated | apply verdict + submit gated | useLeaveApply (rejected preview → canSubmit false, tap no-op); ApplyOnBehalfScreen (verbatim + disabled) |
| 2 | Locked payroll month | verdict at preview | verdict at preview | leave-read.service.spec (locked → ok:false, span facts NOT evaluated) |
| 3 | Disabled leave type | picker sheet disables (0-balance accrual types) + preview refuses | same | LeaveTypePickerSheet tests; preview ladder (LEAVE_TYPE_DISABLED) |
| 4 | Foreign/unknown type id | n/a (picker is catalog-backed) | n/a | preview answers 200 ok:false RESOURCE_NOT_FOUND (D13: previews never 404) |
| 5 | Overlap with an existing request | verdict | verdict | preview ladder (facts → LEAVE_OVERLAP) |
| 6 | Already-off / checked-in conflict | verdict | verdict | preview ladder |
| 7 | On-behalf without a picked member | canSubmit false (picker mandatory) | n/a | existing canSubmit guard |
| 8 | Comp-Off / allow-over / no-config types | never balance-gated | never balance-gated | typeSelectable (allowOverBalance / accrualMode 'none' → selectable) |
| 9 | Transport failure during preview | neutral line, submit stays enabled | same | useLeaveApply (transport → canSubmit true) |
| 10 | Stale preview race | seq latch drops late responses | seq latch | useLeaveApply (A→B→A test), useApplyOnBehalf (same pattern) |

## A. Employee leave apply (23-14)

| # | Scenario | Class | Expected | Where verified |
|---|----------|-------|----------|----------------|
| A1 | Catalog loads; 0-balance accrual type disabled in sheet | negative | Bereavement (0 left) renders ", not available", unselectable; first pickable type is auto-selected (no "No type" state) | device + LeaveTypePickerSheet tests |
| A2 | Balances card compact rows, highlight picked type | positive | remaining/caption copy via balanceRemainingCopy/balanceCaption | device |
| A3 | Preview ok → "N working days" chip | positive | workingDaysCopy verbatim, live region polite | device + LeaveApplyScreen tests |
| A4 | Range needs more than left → verdict verbatim + submit disabled | negative | "Not enough Sick balance — you have 7 days left and this request needs 8 days" style message; button disabled; tap is a no-op | device (Dec 1–14 = 8 working days vs Sick 7) + useLeaveApply pin |
| A5 | Locked payroll month dates | negative | server's locked-month message at preview; submit gated | unit (BE spec) + device if a locked month exists |
| A6 | Overlapping request | negative | overlap message at preview | device |
| A7 | Comp-Off apply with zero balance | corner | selectable, preview NOT balance-gated (allow-over/none semantics) | unit + device |
| A8 | Airplane-mode preview | corner | neutral "can't reach" line, submit ENABLED (fails open; POST re-verdicts) | unit pin |
| A9 | Happy path single day | positive | announce + success, list shows new pending row | device + DB row check |
| A10 | Half-day part (first/second) | corner | preview returns the part; wire part matches | unit |
| A11 | Back-date floor | negative | picker blocks < today−7; older manual date → server LEAVE_TOO_OLD inline | unit |

## B. Owner on-behalf (23-14 owner leg)

| # | Scenario | Class | Expected | Where verified |
|---|----------|-------|----------|----------------|
| B1 | Cold entry auto-opens picker; TRACKED rows only; EMP-code/phone search | positive | Ghost (never enrolled) never offered | device + ApplyOnBehalfScreen tests |
| B2 | Target's balances card (viewer 'owner') | positive | Comp-Off caption "You approve each request" style | device |
| B3 | Preview fires with employeeId + effective leaveTypeId; count chip | positive | previewOnBehalf args pinned; "1 working day" chip | screen test (new pin) + device |
| B4 | Target insufficient balance → verdict verbatim + Approve gated | negative | server message; button disabled; no POST | screen test (new pin) + device |
| B5 | Target NOT_TRACKED | negative | inline server message, NO access refresh | screen test |
| B6 | Approve happy path | positive | born-approved "Approve", fresh idempotency key, lands OwnerLeave all; DB row approved + created_by = owner | device + DB |
| B7 | Target untracked employee picked then dates | corner | verdict mentions not-tracked semantics | unit (BE on-behalf preview validates TARGET) |

## C. Owner leave approvals (23-12/23-14 context)

| # | Scenario | Class | Expected |
|---|----------|-------|----------|
| C1 | Owner leave list tabs (all/pending) + pending badge | positive | pending row from A9/B6 visible |
| C2 | Approve/reject a request | positive | status flip + DB row updated |
| C3 | "Your leave balances" surface on owner Attendance tab | positive | balances card renders (Sally P2 pronoun decision deferred) |

## D. Payslips (23-12 employee leg)

| # | Scenario | Class | Expected |
|---|----------|-------|----------|
| D1 | Profile → Payslips row (technician only) | positive | list screen opens |
| D2 | Empty state before first lock | corner | "No payslips yet — yours will appear here after payroll runs." |
| D3 | Rows: month, net pay, paid/LOP, slip number, pdf badge | positive | Ready / Making PDF / PDF failed vocabulary |
| D4 | Detail: hero + earnings + deductions (machine labels) + balances-as-of-lock | positive | deductionLabel map (pf/TDS/head:/recovery:) |
| D5 | PDF three-state tap | positive | Download → Preparing → Open; failed → Try again; 12-tick honest stop |
| D6 | Owner sees NO payslips entry | negative | owner Profile has no Payslips row (payroll.own is employee-only) |

## E. Cross-cutting

| # | Scenario | Class | Expected |
|---|----------|-------|----------|
| E1 | Session expiry mid-flow | corner | 401 → auth screen |
| E2 | Logout clears payslip/leave local state | corner | no stale rows on next login |
| E3 | Indian rupee grouping | corner | ₹1,23,456 (2-2-3), two-decimal paisa, true minus |
| E4 | DB truth matches every device write | verification | Supabase MCP reads after each write |

## Suites at the time of this matrix

- fenzit-app: 4,476/4,476 (339 suites) green, `tsc --noEmit` clean
  (re-run after the final device pass, 2026-11-20 02:5x).
- fenzit-be: 3,439/3,439 green, `tsc -p tsconfig.build.json` clean
  (stale sync/users pins fixed: six jobCounts buckets incl. `pending`
  PENDING_APPROVAL; memberships-with-users-embed cols; sync select regex;
  +4 tests = the Story-1 IsUUID trap regression block below).

## F. The IsUUID trap — found by the regression pin, fixed house-wide (BE 20703e9, LIVE)

The regression pin I was asked to write exposed a deeper bug than the one it
pinned. Class-validator 0.15.1 delegates `@IsUUID()` to validator-lib, whose
`'all'` is NOT shape-only: it checks version 1–7 + 89AB variant and **rejects
83/173 REAL user ids** in the DB (hash-style seeded ids, e.g. Ajay EMP-080
`183c1349-8e1b-d7a6-d69e-be77cbc654a1`, version nibble 'd', variant 'd').
`'4'` is worse (82/173). Only `'loose'` (shape-only hex-dash) accepts
everything — and exactly matches NestJS `ParseUUIDPipe`'s `'all'`, which is
why `@Param('employeeId', ParseUUIDPipe)` routes always worked while
DTO-pinned routes 422'd ("employeeId must be a UUID").

- DB ground truth (Supabase pnlvreaijzslfymlnoti): users 82 v4 + 8 pass-'all'
  + 83 FAIL-'all' + 0 fail-'loose'; leave_types/skills/credits/requests/
  offices/jobs/tenants all clean v4 — the poison ids are exactly users.id
  (hand-seeded rows bypass gen_random_uuid()).
- Fix: `@IsUUID('loose')` on **all 26 id-carrying DTO sites** across 15 DTO
  files (leave, leave-balance, correction, leave-type, enrolment, dashboard,
  monthly, jobs, notifications, payroll-offcycle, job-reports, members,
  invite, verify-otp, webhooks/storage). Zero acceptance loss (loose ⊇ all ⊇
  v4); no security change (ids stay parameterized + RLS-scoped).
- Pin: `leave.dto.spec.ts` "Story 1 IsUUID trap" block (4 tests) — a '4' or
  bare-'all' re-introduction reproduces as the live 422.
- Deploy-proven: the 422 on `GET /attendance/leave/on-behalf/preview` for
  Ajay disappeared after Render picked up 20703e9.

## G. Overnight device evidence (Pixel 6, 2026-11-20 ~02:10–03:00)

| Scenario | Evidence | DB |
|----------|----------|-----|
| B6 on-behalf Earned 1–14 Dec born-approved | d39–d41 (chip "8 working days" → row "Ajay Sinha · EMP-080 · 1–14 Dec 2026 · 8 working days · Approved") | 600289a4-bd80-43ae-8570-2c55a2e61363, created_by=Beta, 14 days approved; Earned consumed 14→6 |
| Double-submit POST re-verdict | d42–d43 | leave_requests count for the range stayed 1 |
| A4 insufficient (Sick 8 needed vs 7) | d58–d59 verbatim verdict + submit disabled | — |
| 62-day span cap (bonus rung) | d62 "Leave can cover at most 62 days at a time" | — |
| A6 overlap (Nov 25) | d63 verbatim "You already have a leave request covering one of these dates" | — |
| A7 Comp-Off zero balance | d64 picker (Comp-Off selectable, Bereavement disabled), d68 "1 working day" ok chip, d70 submit enabled, d71 pending row | 20c6cd3c…4b5d, day state pending |
| A9 Sick single day | d78 "1 working day" chip, d80 submit, d80b pending row | 4d160692…15c6, day state pending |
| D1 payslips list | d82: "October 2026 · 11 paid days · ₹15,512.91 · Ready · Slip PS-2026-10-0001" | matches payroll DB net |
| D2/D4 detail arithmetic | d83–d84: 17,741.94 gross − 2,229.03 deductions = 15,512.91 net EXACT; balances as-of-Oct-end (Earned 13, Sick 8.5) ≠ today's 6/7 → as-of-lock proven | — |
| D5 PDF | d85: Form-V wage slip via R2 signed URL in Chrome (EMP-080, PAN, UAN, bank, wage period, cut-off 25, "Fenzit · 1/2", private footer) → clean back to list (d86) | — |
| C1 queue + home banner | d91 home "2 leave requests · Action pending approval"; d95 Leave tab badge "2" + both pending rows with EMP-080 | — |
| C2 approve | d96 detail (Sick balance shows 6 = 7−1 pending → pending-aware display), d97 row left queue | 4d160692 day → approved; leave_events seq 3552 apply / 3553 approve (actor Beta) |
| C2 reject w/ reason | d98–d102 optional-reason reject (FR-13), queue → honest empty state | 20c6cd3c day → rejected; leave_events seq 3554 cause reject reason "Teamv" actor Beta |

## H. The Sally round (device findings in, review out, triaged, PATCHED)

Device-sourced observations fed to Sally; her review returned NO P1s (the
core contract — server-verdict gate, verbatim copy, balance display — held).
BMAD triage verified every finding's code claim before patching:

| # | Finding | Verdict | Result |
|---|---------|---------|--------|
| F1 | P2: the leave type is invisible on review surfaces (queue rows, detail sheet, events) — the wire's LeaveRequestView carries no type; BE-first change | **DEFER** (owner's earlier pronoun deferral pattern; needs BE toRequestView change) | recorded for the owner |
| F2 | PayslipsScreen: a failed refresh with rows on screen REPLACED the list with the error block (blank screen) | PATCH | full error only when no rows; otherwise banner + Retry above the KEPT rows (ListHeaderComponent) |
| F3 | Reason-preset pills ~33px tall vs the 44px touch minimum | PATCH | hitSlop {top/bottom 6, left/right 4} — stays inside the 8px wrap gap |
| F4 | ApplyOnBehalf: `showEmptyHint={false}` hardcoded — no "Pick dates…" hint ever | PATCH | `showEmptyHint={form.employee != null}` (picker is the first step; hint guides the next) |
| F5 | usePayslipDetail poll: a tick whose GET collides with an in-flight read resolved null → `?? 'none'` → poll SETTLED (button flipped) mid-generation | PATCH | null read = skipped tick (sleep + re-read); only a REAL read settles; cap still bounds |
| F6 | Hooks: catalog with types but NONE pickable → trigger fell back to `options[0]` (a disabled type dressed up as the selection) while the wire went untyped | PATCH | hooks expose `leaveTypeUnavailable`; fields render the neutral notice (untyped = the BE's paid-leave semantic, still preview-governed) |

Dismissed (verified as non-issues): the picker's disabled-state honesty
(Bereavement "0 days left" greyed matches the gate), the badge latency
(one RTT by design — `loadMyProfile({force:true})` already fires on every
decision; d97→d98 showed it settling), EmptyState dead `icon` prop (code
nit, unused prop path).

All patches tested (5 new pins: F2 keeps-rows banner, F3 hitSlop, F4 hint
gating, F5 collision-skip poll via the held-lane path, F6 notice + no
trigger) — suite 4,481/4,481 (339 suites), tsc clean.

**Shipped: fenzit-app 289c627 (23-14 leave) + 8ec4022 (23-12 payslips),
pushed to origin main.** Commits are pathspec-scoped per story.
