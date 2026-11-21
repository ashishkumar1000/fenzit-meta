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
