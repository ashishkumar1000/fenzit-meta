# Plan — Employee Profile page redesign, 5 tabs (fenzit-web + fenzit-be)

Date: 2026-11-21 · Owner approved the plan in-session; designs finalised in Stitch 2026-11-20
(project 1594154886874615054 — Employee Profile Rajuu EMP-004, one screen per active tab).

## Context

The web console has no employee detail page today — only the list page
(`/admin/company/employees`) with inline quick-edit cells. This story implements the approved
design: header card + tabs **Master Record | Jobs | Attendance | Leave | Payroll**, one active
tab rendered, every section grounded in real endpoints/tables (honest empty states where the
data doesn't exist).

Owner decisions (2026-11-21):
- **Build membership deactivate/reinstate now** (design shows a Deactivate action; no endpoint
  exists today).
- **Build a punch-records endpoint** so the Attendance tab shows real check-in/out rows.
- **Keep** the list-page quick-edit cells; the row name links to the profile.

Layer calls (fix-placement rule): member detail + deactivate = **BE**; jobs-by-employee filter =
**BE** (additive param on `GET /jobs/page`); punches = **BE** (read over existing
`attendance_records`); tabs/panels/empty-states = **FE**; **no DB migration anywhere**
(`jobs_overview` already exposes `technician_id`; `attendance_records` exists).

Sibling patterns to mirror: payroll page (`AdminPayrollPage.tsx`, `payrollLoaders.ts` — `?tab=`
Links, per-tab loader, `Slice`/`settle`), jobs page (URL-state builders, labels module,
own-header shell), employment resource route (open read + save action, reused dialog).

## BE (fenzit-be) — additive only, **ZERO new RPCs** (AD-3 standing rule: new reads = NestJS services over existing tables/views or plain SQL views; never Postgres functions)

> Plan-review triage (2026-11-21) folded below — reviewer verdict: design sound, 17 findings
> (1 P1, 10 P2, 6 P3); all patched into this doc except where marked as ledger decisions.

0. **One migration is required (plan-review P1):** `memberships_status_check` is a DB CHECK
   (`status in ('invited','active','removed')`, migration `20261020000001_roles_new_structure.sql`)
   — no code path can write `'deactivated'` past it. Add exactly one migration:
   `ALTER TABLE memberships DROP CONSTRAINT memberships_status_check` + re-ADD including
   `'deactivated'` (constraint widening only — consistent with the no-RPC rule; the owner
   approved building deactivation, which is impossible without this).

1. `GET /members/:userId` (`member.read`) — single `MemberView` via the `listCompanyMembers`
   read path for one id (name, phone, email, avatar, employeeCode, status, role, joinedOn,
   canCreateJobs, jobApprovalRequired, skills). **No statutory fields** — those stay exclusively
   behind `GET /members/:userId/employment` (23-1 privacy invariant). Cross-tenant or removed →
   404. Controller-spec permission-table row. **Route placement:** declared after
   `GET /members/page` (Fastify prefers static over parametric; ParseUUIDPipe backstops a stray
   literal — jobs controller's route-order discipline).
2. `PATCH /members/:userId/active` `{ active: boolean }` — membership deactivate/reinstate:
   - New permission `member.deactivate` (owner-only, **outside `ADMIN_PERMISSIONS`**, same
     exclusion shape as `member.employment`).
   - `active:false`: only `status='active'` → `'deactivated'`; `active:true`: only
     `'deactivated'` → `'active'`; invited/removed → 409; **self-deactivation → 403**
     (mirrors `change_member_role`/`remove_member` refusal idioms).
   - **Race-free last-active-owner guard (plan-review P2):** the shipped LAST_ADMIN guard lives
     inside the role/remove RPCs, not in service code — so this endpoint runs as ONE pg
     transaction (PgPool, the enrolments-repository pattern) taking the **exclusive tenant lock**
     (`attendance_lock_tenant($1, true)` — same lock space the roles RPCs use), re-reading the
     member, counting other active admins, and writing a guarded `UPDATE … WHERE status =
     <expected>`; zero new SQL functions.
   - Access loss is automatic (`membership-resolver.ts:57` counts only `status='active'`), and
     the **login path must treat `'deactivated'` like the removed branch** (plan-review P2:
     `auth.service.ts` currently admits any `status <> 'removed'` to a normal company session →
     a deactivated user would get a 403-storm zombie session) — include deactivated in the
     former-member condition at login.
   - Audit entries carry action + employee_code only (existing `write_audit_row` RPC, the
     `updateEmployment` pattern).
   - Status enum → `'invited'|'active'|'deactivated'|'removed'`; `deactivated` added to the
     `/members/page` status filter; the filter's 422 message updated to name it.
3. `GET /attendance/punches?employeeId&from&to` (`attendance.read`) — rows from
   `attendance_records` (workDate, checkinAt, checkinDistanceM, checkoutAt, checkoutDistanceM,
   officeId), newest first, span cap ≤ 62 days (day-statuses precedent), tenant-scoped, foreign
   employeeId → 404.
4. `GET /jobs/page` — add optional `technicianId` (IsUUID) filtering the view's `technician_id`;
   when present, **scope the stats queries to that technician** (whole-company stats would lie
   on a profile page). Legacy cursor `/jobs` untouched (mobile).
5. **Deactivated write-guards (plan-review P2):** enrolment enable/office-reassign and
   on-behalf leave writes currently accept `status <> 'removed'` — they must refuse a
   deactivated member (clear 409/422); the enrolments roster passes `'deactivated'` through as
   `memberStatus` instead of collapsing it to `'invited'` (read side; mobile mis-render is a
   ledger note).
6. Members-module hygiene (plan-review corrected): the `''` → `null` employment normalisation
   is **already shipped** (`members.service.ts` `normalisedText` over `EMPLOYMENT_TEXT_FIELDS`)
   — the ledger item gets marked RESOLVED with that evidence (remaining one-off cleanup of any
   already-stored `''` rows is a separate plain-SQL decision, checked at implementation). The
   real doc fix: sync **all three** stale `@ApiQuery` enums on `/members/page` (jobSetting,
   sort, and the status message once `'deactivated'` joins) with the DTO.
6. Tests: members/jobs/attendance `*.spec.ts` (permission tables + service behaviour); suites
   green before push.

## FE (fenzit-web)

1. Route `company/employees/:userId` (lazy) in `src/app/routes.tsx` + `shouldRevalidate` that
   revalidates on tab change, month change, **or any action result on this route** (plan-review
   P2: the attendance idiom's tab-only predicate would swallow the deactivate fetcher's
   refresh — verify the exact react-router 8.4 `shouldRevalidate` arg names via Context7 before
   coding). `AdminPage.tsx`: own-header matcher gains a one-line prefix rule for the param'd
   profile path (extract the matcher if it grows — AdminPage is already ~340 lines).
2. `src/features/admin/employeeProfileLoaders.ts` (payroll idiom): whitelisted tab Set
   (`master|jobs|attendance|leave|payroll`), per-tab dispatch, every section `settle()`d into
   `Slice`, stale `:userId` → `{state:"not-found"}` (honest empty page), `?month=` validated
   `YYYY-MM` (default current) for attendance.
3. `src/pages/AdminEmployeeProfilePage.tsx` + `src/features/admin/components/employee/*Panel.tsx`
   (one file + css module per tab):
   - Header card: Avatar, name, EMP chip, status pill, "Joined" (from `createdAt` — no new
     field name), phone, "+ Add designation" (opens the reused `EmploymentDialog`), flag
     badges; Assign Job → `/admin/company/jobs/new?technician=<id>` (owner-facing address of
     the shared new-job page); Edit Profile → `EmploymentDialog`; **no Deactivate on the
     viewer's own profile** (self-deactivation is refused by the BE); Deactivate / Reinstate
     via profile action (`intent=activate`, deactivate asks for confirmation).
   - MasterRecordPanel: statutory grid with honest "— Add" affordances opening the dialog;
     read-only skills chips; "Complete master setup" EPF notice when PAN/PF/UAN/bank incomplete.
   - JobsPanel: chips from the technician-scoped stats + DataTable (JB number → job detail).
   - AttendancePanel: Office assignment card (enrolments roster pick) + Shift rules card
     (office rules) + Punch history card (new endpoint; honest empty state).
   - LeavePanel: balance cards from the balances endpoint with accrual captions built from the
     balance rows themselves (`LeaveBalanceView` already carries `accrualMode`/`accrualDays` —
     no separate types fetch, plan-review P3); requests table
     (`GET /attendance/leave?employeeId=`, first page).
   - PayrollPanel: structure card read-only (existing `fetchStructures`) + "Manage salary in
     Payroll" deep link (`/admin/company/payroll?tab=structures&employee=<id>`); payslips card
     (new `fetchPayslips` — the endpoint is month-scoped, so N recent months in parallel with
     per-month `settle()`, rows filtered client-side by `user_id === profileUserId`; honest
     "No payslips yet").
4. API fns: `fetchMember`, `setMemberActive`, `fetchPunches`, `fetchLeaveBalances`,
   `fetchLeaveRequests`, `fetchPayslips` (`apiFetch` + Bearer, literal `/api/v1/...`);
   `JobsPageQuery.technicianId`.
5. List page: `MembersTable` name cell links to the profile; "Deactivated" in the status
   filter + `toneForStatus`/`humanize`; **deactivated row cells** — Employment cell stays
   (view/edit still valid), JobSettings cell hidden (the BE settings write requires
   `status='active'`); the full deactivated sweep touches six FE spots (`MemberRow.status`
   union, `MembersStatusFilter`, `STATUS_FILTERS` loader Set, `STATUS_CHIPS`, `TONES`,
   cell gates).
6. Picker sweep: the new-job technician picker already filters `status === 'active'`, so
   deactivated is excluded automatically once BE returns them; add the `?technician=`
   preselect (loader reads the param, `<select defaultValue>` when it matches a real active
   technician); audit remaining `status !== "removed"` rosters for deactivation correctness.
7. Copy in `employeeProfileLabels.ts`; failed branch keeps an h1 (console-wide ledger item);
   no toasts — inline status/alert per console conventions.

## Ledger at plan time (mockup → reality calls)

- "+ Add Skill" omitted — no admin skill-write endpoint exists (future story).
- Leave balances cover accrual-bearing types only (BE contract excludes Comp-Off).
- Deactivation on mobile: the technician app loses access cleanly at login/next request (BE
  login-path change in BE.2 handles the zombie-session case), but **mis-renders are accepted
  for now** — the mobile owner roster maps any non-active status to "offline"
  (`useTechnicians.ts:141`) and `JobSettingsSheet` shows editable switches for a deactivated
  employee whose save 404s; the enrolments roster gains a real "deactivated" `memberStatus`
  that mobile may not render specially yet. Small mobile guard rides a later mobile story.
- Employment `''`-hygiene ledger item (deferred-work.md:1269) resolved as already-shipped
  (evidence recorded during BE step); one-off cleanup of stored `''` rows stays a separate
  decision.
- List-page quick-edit cells intentionally kept (owner decision 2026-11-21) — duplicate edit
  entry points across list/profile accepted for now, noted for a later cleanup.

## Sequence

1. This plan doc → **adversarial plan review** (fresh-context reviewer) → triage (patch /
   ask-owner / accept-with-reason) → fold patches before code.
2. BE implement (migration + endpoints + guards) → **local probe** (owner token, master OTP
   1039 recipe; owner confirms it works) → write the members/jobs/attendance specs → jest
   suites green → commit + push fenzit-be **first** (additive; consent at the step; no
   lockfile; pull --rebase first). [Test-timing rule order, plan-review P2.]
3. FE implement → owner manual pass → FE spec additions → gates (`bun test`, tsc,
   format:check, lint, check:styles, design-system check) → BMAD two-lens review
   (edge-case-hunter + verification-gap) → step-03 triage → patches → record in plan +
   `artifacts/implementation-artifacts/deferred-work.md`.
4. Commit FE (explicit paths) + push; plan/ledger commit in fenzit-meta.

## Verification

- BE probes: member detail (200 / 404 cross-tenant / no statutory fields in the response);
  deactivate → test-tenant dummy (e.g. TestEmpThree) loses access at next request → reinstate
  restores; last-active-owner 409; punches (span cap, ordering); jobs `?technicianId=` rows +
  scoped stats + legacy `/jobs` byte-stable.
- FE: manual pass against the Stitch screens at 360/768/1280; `?tab=` deep links; Master
  Record dialog round-trip; deactivate confirm + pill; Assign Job preselect; Payroll deep
  links; employees list regression.
- Suites: BE jest members/jobs/attendance + FE full bun suite; no e2e baseline drift.

## Code Review

### 2026-11-24 (post-hoc — the review the 21 Nov commits shipped without)

Two-lens BMAD review (edge-case-hunter + verification-gap) over BE `1da8594` (+ jobs `214ee60` spot-check) and FE `7340a05..e2bd99a`; 25 findings triaged: 1 decision-needed (resolved → patch below), 20 patch, 1 defer, 5 rejected. **All 21 patches applied 2026-11-24** — BE gates: jest 3477/3477 (192 suites) + tsc clean; FE gates: bun 1195/1195 (95 files), typecheck, format:check, lint (2 pre-existing warnings), check:styles, design-system. Uncommitted at owner consent gate.

**Severity grades (triage-owned):** 1 high, 14 medium, 6 low.

- [x] [Review][Patch] Deactivated members still accept time-corrections and leave-balance adjustments — `employeeExistsInTenant` filters only `status <> 'removed'`, so the 4 correction write-sites (`corrections.service.ts:159,281,341,401`) and 2 balance sites (`leave-balance.service.ts:380,419`) keep working for parked members, while enrolments and on-behalf leave were given 409 `MEMBERSHIP_STATE` guards in this same commit. **Owner decision 2026-11-24 (per recommendation): refuse both with 409 `MEMBERSHIP_STATE`** — corrections change graded attendance (money) and balances are forward-looking; the reinstate→correct→deactivate loop covers the rare fix-a-parked-member's-record case [corrections.service.ts + leave-balance.service.ts] (medium)
- [x] [Review][Patch] setActive (deactivate/reinstate txn) ships with zero behavioral coverage — no test for self-403, wrong-state 409, last-admin 409, guarded update, happy round-trip [src/members/members.service.ts:421-522] (HIGH)
- [x] [Review][Patch] getMember untested — nothing pins 404 on cross-tenant id nor the no-statutory-fields response shape [src/members/members.service.ts:377-404] (medium)
- [x] [Review][Patch] auth sign-in predicate change (`.neq('removed')` → `.in(['invited','active'])`) unobservable — arg-blind fakes; reverting to the old predicate passes every test [src/auth/auth.service.ts:442,463] (medium)
- [x] [Review][Patch] GET /attendance/punches zero coverage — ordering, punch-only filter, 404 no-leak, 422 span cap all unpinned [src/attendance/punches.read.ts:57-126] (medium)
- [x] [Review][Patch] enrolments deactivated guard dead in tests — spec fake returns status-less employee rows, guard branch never executes [src/attendance/enrolments.service.ts:435-441] (medium)
- [x] [Review][Patch] leave on-behalf deactivated 409 untestable — spec fake hard-wires `{ status: 'active' }`, no override hook [src/attendance/leave.service.ts:197-212] (medium)
- [x] [Review][Patch] `?technicianId=` filter + scoped stats unverified — no getJobsPage tests; dropping the filter or the stats forwarding fails nothing [src/jobs/jobs.service.ts:1226,1254,1315-1360] (medium)
- [x] [Review][Patch] jobs technician validation accepts a deactivated employee — `findCompanyMember` default excludes only `removed`; new work can be assigned to someone who cannot sign in [src/jobs/jobs.service.ts:496-510] (medium)
- [x] [Review][Patch] profile `shouldRevalidate` vetoes the loader on `:userId` change — same tab+month under a different employee renders the previous employee's data under the new URL [src/app/routes.tsx:252-257] (medium)
- [x] [Review][Patch] shift-rules card shows a future-dated rule as today's — `currentRule` picks the last revision without a `validFrom <= today` filter, diverging from the BE's pick [src/features/admin/components/employee/ProfileAttendancePanel.tsx:160-166] (medium)
- [x] [Review][Patch] Leave tab silently truncates past page one — table renders `requests.data.data` without reading `hasMore`; ninth-and-later requests invisible under a "Newest first" meta [src/features/admin/components/employee/ProfileLeavePanel.tsx:51-60] (medium)
- [x] [Review][Patch] shift-rules card labels a failed enrolment fetch "not enrolled" — `assigned` conflates `enrolment.ok === false` with "no enrolment row" [src/features/admin/components/employee/ProfileAttendancePanel.tsx:101-104] (low)
- [x] [Review][Patch] non-UUID `:userId` renders connection-error instead of the honest not-found state — BE `ParseUUIDPipe` answers 400, loader maps only 404 [src/features/admin/employeeProfileLoaders.ts:130-131] (low)
- [x] [Review][Patch] employees-page deactivated visibility untested — kit `stats()` lacks `deactivated`, no deactivated fixture; Deactivated chip/filter and MembersTable status gating can regress silently [src/testing/employeesPageKit.tsx:73-90, src/features/admin/components/MembersTable.tsx:222,231] (medium)
- [x] [Review][Patch] Assign Job `?technician=` preselect chain untested — loader mapping and select defaultValue unpinned; preselect can ship dead [src/features/admin/meCreateJobLoaders.ts:110-113, src/pages/AdminMeNewJobPage.tsx:209] (medium)
- [x] [Review][Patch] Payroll empty-structures test passes on a lying `200 {}` catch-all stub — never exercises the 404 branch the empty state is built from (the exact trap `e2bd99a` removed elsewhere) [src/pages/AdminEmployeeProfilePage.test.tsx:195] (medium)
- [x] [Review][Patch] attendance month-nav link hrefs untested — a broken `shiftMonth` silently degrades to current-month [src/features/admin/components/employee/ProfileAttendancePanel.tsx:114,120] (low)
- [x] [Review][Patch] own-header prefix for the profile route unobserved — greeting-h1 stacking regression would ship uncaught [src/pages/AdminPage.tsx:230-233] (low)
- [x] [Review][Patch] profile employment-dialog wiring (open/load/round-trip) untested — EPF "Complete master setup" and every "+ Add" can dead-end silently [src/pages/AdminEmployeeProfilePage.tsx:75-79] (medium)
- [x] [Review][Patch] employees summary tile copy not extended — reads "N active, M invited" while `stats.deactivated` exists; parked members invisible in headline counts [src/pages/AdminEmployeesPage.tsx:71] (low)
- [x] [Review][Defer] `MemberFact['status']` union stale — type says `'invited'|'active'|'removed'` but raw DB status (now possibly `'deactivated'`) flows in; behavior today correct (only `=== 'active'` checked), widen when job-reports is next touched [src/job-reports/job-report-rules.ts:35] — deferred: latent developer-facing type lie, no behavioral harm today

**Rejected appendix:**
- [F6 payslip months all-or-nothing] — `low`; deliberate reality call ledgered at plan time (`deferred-work.md`, commit c38a163) with the per-month-degradation recipe recorded.
- [F7 `?technician=` missing `encodeURIComponent`] — `false`; `member.userId` is a UUID (hex + hyphens), a query metacharacter cannot occur.
- [F9 "the only place PAN/PF/UAN/bank appear" claim] — rejected; the text lives in this plan doc's Context prose, not code — fixing it means editing the plan under review.
- [BE-O1 plan-vs-migration discrepancy] — `false`; this plan's step 0 (plan-review P1) explicitly mandates the `memberships_status_check` migration — the verifier quoted the stale Context prose; the migration was applied and verified in prod.
- [FE-O2 empty employeeCode pill] — `false`; `memberships.employee_code` is trigger-generated for every tenant row, which every profiled member has.
