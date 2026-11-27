---
title: 'The manager''s branch reads its own team — directory, team job queue, report balances, routed reminders'
type: 'feature'
created: '2026-11-27'
status: 'done'
route: 'full'
route_source: 'auto'
review: 'thorough'
review_source: 'auto'
lenses_ran:
  - 'blind-hunter'
  - 'edge-case-hunter'
  - 'verification-gap'
  - 'intent-alignment'
review_loop_iteration: 1
baseline_commit: '03ef0c6'
baseline_revision: '03ef0c6'
context:
  - 'artifacts/specs/spec-company-hierarchy/SPEC.md'
  - 'artifacts/specs/spec-company-hierarchy/approval-routing.md'
  - 'artifacts/implementation-artifacts/epic-24-context.md'
  - 'artifacts/implementation-artifacts/spec-24-5a-backend-manager-signals.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** 24-5a answered "do I have a team?" and "can I decide this?", but a manager still cannot read their own branch: there is no member directory to fill an apply-on-behalf picker (`GET /members` is admin-only), a viewer-manager's job queue cannot be limited to their team, a report's leave balances answer 403, and the daily pending-leave reminder still goes to every active admin with a tenant-wide count (CAP-4/D7).

**Approach:** Extend the existing read contracts, add one filter, and move the reminder recipients onto the resolved-approver walk: `team.members[]` on `/users/me`, `teamOnly` on `GET /jobs`, subtree-scoped balances behind the existing `leave.read_team` grant, and a SQL approver helper that mirrors `approval-routing.ts` for the pg_cron reminder.

## Boundaries & Constraints

**Always:**
- Reuse the shipped walk/scope helpers; `members` and every team read scope must resolve to the SAME set (one definition of the subtree walk). A member with no reports gains no new surface.
- An id outside the caller's branch answers exactly like a missing one (404) — no existence leak. A member with no reports keeps today's 403 on team reads.
- Additive fields only; no existing response key changes meaning. `team.members` lists the actionable subtree: it can be smaller than `team.headcount`, which counts the roster's shape (a disabled member's reports are counted but not actionable — `readMemberHierarchy` walks through a disabled node, `readSubtreeMemberIds` prunes it).
- The SQL approver walk mirrors `resolveApproversWithTree` exactly: an ACTIVE, enabled admin requester → self (nobody notified, checked before the actor rule); nearest active, enabled member above the requester; actor excluded; unassigned/left-company → all active admins minus actor; visited-set loop guard plus the depth cap; corrupt/unresolved → nobody, with a warning.
- Reminder dedupe keys keep their shape (`<tenant>:leave.pending_reminder:<user>:<date>`), so one digest per recipient per day.
- The reminder helper is not PUBLIC-executable: `revoke all … from public, anon, authenticated; grant execute … to service_role`.

**Never:**
- No `leave.create_on_behalf` grant for VIEWER (G6 — owner/product decision; the app hides on-behalf for viewers).
- No new approval-queue endpoint and no new queue fields — `GET /jobs` already carries `decision` and `createdBy`.
- No team pending counts (G7), no named approver (G9), no `hasTeam` on `/users/me/access` (G10) — polish or app-side refresh policy, recorded in Design Notes.
- Don't add `members` to `MemberHierarchy`/`emptyHierarchy` (every `/members` row spreads those); the new type lives on the profile only.
- Don't touch the decide POSTs, the members write paths, RLS, or the week-off/holiday rules.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Team directory | employee or viewer manager, 2 live reports | `/users/me` `team.members` = 2 rows `{userId,name,employeeCode,status,avatarUrl}` | directory read fails → `members: []`, profile still 200 |
| Admin profile | company admin / platform admin | `team.members` = `[]` (roster is `GET /members`) | — |
| Disabled member in branch | report of a disabled manager is active | count is in `headcount`, absent from `members` | — |
| Team jobs queue | viewer-manager, `?scope=all&status=pending_approval&teamOnly=true` | only jobs assigned below the caller, each with its `decision` | `technicianId` outside subtree → 404 |
| Team queue, no reports | `teamOnly=true`, empty subtree | empty page (never self-only, never the company) | — |
| Team filter off | viewer, no `teamOnly` | tenant-wide (unchanged) | — |
| Report balances | manager opens a report's leave detail | 200 with balance rows | no reports → 403; outside branch → 404 |
| Routed reminder | employee A reports to manager M | M gets one `leave.pending_reminder` with M's count | unrelated admin gets none |
| On-behalf | M filed for A | walk starts at A with actor M, so M is excluded | nothing resolves → nobody |
| Unassigned employee | no manager | all active admins except the filing actor | no active admin → nobody |
| Admin's own leave | pending | self-decided, no reminder | — |

</frozen-after-approval>

## Code Map

- `src/common/members/hierarchy.ts` — `readSubtreeMemberIds` (~160) becomes `readSubtreeMemberDirectory(...).map(r => r.userId)`; the new walk keeps that function's exact predicate (removed and disabled pruned at every rung) and selects `user_id, name, employee_code, status, avatar_key`. One walk definition, so the directory and every scope can never drift.
- `src/users/users.service.ts` — `UserProfileBase.team` (~131), `readOwnTeam` (~330), profile assembly (~407). Add `TeamSummary = MemberHierarchy & { members: TeamMemberSummary[] }` and `emptyTeamSummary()`; keep `emptyHierarchy()` untouched.
- `src/common/members/member-avatars.ts` — `presignAvatarUrls` + `avatarUrlFor` for the directory links (signing is local, no network call).
- `src/jobs/dto/list-jobs-query.dto.ts` — add `teamOnly?: boolean` with an explicit string→boolean `@Transform` (no implicit conversion in the pipe) so `?teamOnly=yes` is a 422.
- `src/jobs/jobs.service.ts` — `listJobs` row scope (~1384) and `teamScope` (~497). Add `subtreeScope(user)` that never consults the role (the existing `teamScope` returns null for VIEWER and for an empty subtree) and intersects with it when `teamOnly` is set; the outside-`technicianId` 404 moves so it applies on that path too.
- `src/attendance/leave.controller.ts` — balances route `@Can('leave.read_all')` (~73) → `@Can('leave.read_all', 'leave.read_team')` (the guard takes ANY of the list).
- `src/attendance/leave-balance.service.ts` — `readEmployeeBalances` (~377); mirror `scopedEmployeeIds` in `leave-read.service.ts` (~277): scope check FIRST (no existence oracle), then tenant scope passes / subtree scope checks self+descendants.
- `supabase/migrations/20261127000003_leave_pending_reminder_routing.sql` — new `attendance_leave_approvers(tenant, requester, actor) returns uuid[]` plus a text patch of the reminder's pending block, anchored on the LIVE body (the one after `20261020000006` and `20261020000009`; the `20261020000003` text no longer exists). The `20261020000006/09` pattern: exact old text, raise when not found exactly once.
- `src/attendance/dto/leave.dto.ts` (~204) — `from`/`to` are owner-list-route capabilities, not admin-only.
- `test/integration/attendance-reminders.integration.spec.ts` — its `leaveRequest` helper seeds `created_by = OWNER`, which the new walk reads as "an admin filed for an unassigned employee" → actor excluded → nobody notified. Seed `created_by = employeeId` (honest self-filing) and keep the assertions; update the two comments that call the digest "tenant-wide".
- `test/integration/attendance-reminder-routing.integration.spec.ts` — new real-DB suite for the routing matrix.
- Existing unit assertions that break and must be updated: `src/users/users.service.spec.ts` (~853, ~1078, ~1096).

## Tasks & Acceptance

**Execution:**
- [ ] `src/common/members/hierarchy.ts` -- add the subtree directory walk and make `readSubtreeMemberIds` delegate to it -- one definition of "the caller's branch".
- [ ] `src/users/users.service.ts` -- add `TeamSummary.members`, fill it for EMPLOYEE and VIEWER callers, degrade to `[]` on its own failure -- one boot payload, no extra round trip on the team screen.
- [ ] `src/jobs/dto/list-jobs-query.dto.ts` + `src/jobs/jobs.service.ts` -- add `teamOnly` and a role-blind `subtreeScope` -- a viewer's team queue must not show the whole company, and an empty team must not fall back to self.
- [ ] `src/attendance/leave.controller.ts` + `src/attendance/leave-balance.service.ts` -- widen and scope the balances route -- the team detail sheet already calls it.
- [ ] `supabase/migrations/20261127000003_leave_pending_reminder_routing.sql` -- route the reminder to the resolved set with its own count, log unresolved tenants, lock the helper down -- CAP-4/D7 is a live behaviour gap, not a test gap.
- [ ] `src/attendance/dto/leave.dto.ts` -- correct the from/to comment -- the docs must match the route's real callers.
- [ ] Unit specs: the three `team` assertions plus new cases for directory shape/failure, viewer `teamOnly`, empty subtree, outside-`technicianId` 404, balances 403/404 — and the new real-DB reminder suite (routed, on-behalf excluded, fallback, corrupt, dedupe).

**Acceptance Criteria:**
- Given an employee or viewer manager with reports, when the app reads `/users/me`, then `team.members` lists exactly the people below them with a name, employee code, status and photo link; an admin gets an empty list.
- Given a viewer-manager, when they request `GET /jobs?scope=all&status=pending_approval&teamOnly=true`, then only jobs assigned inside their subtree come back, and a viewer with no reports gets an empty page.
- Given a manager and a report, when they request that report's balances, then they get the same rows an admin gets; a stranger's id answers 404 and a member with no reports answers 403 before existence is checked.
- Given a pending leave request from employee A whose resolved approver is M, when the reminder tick runs at 10:00, then M — and only M — receives the digest, with the count of requests that resolve to M.
- Given an on-behalf request filed by M for A, when the tick runs, then M receives no reminder for it.
- Given any tenant, when the tick runs twice, then the dedupe key still absorbs the second run.

## Implementation Notes

## Plan Change Log

## Review Triage Log

### Plan review (2026-11-27, fresh-context adversarial, before any code)
Verdict APPROVE-WITH-PATCHES. 8 findings patched, 3 refuted.
- HIGH patched: the existing reminder suite seeds `created_by = OWNER`, so the mirrored walk would notify nobody — fixture and comments updated (task + Code Map).
- HIGH patched: `members.length === headcount` is false when a disabled member sits above live reports; invariant restated, directory reuses the scope predicate, one walk.
- HIGH patched: `teamScope` is a no-op for VIEWER (returns null on `job.read_all === 'tenant'`) and turns an empty subtree into self-only — new role-blind `subtreeScope`, empty page stated and tested.
- MEDIUM patched: directory for VIEWER justified (team screen, not the on-behalf picker), no silent cap, deterministic order.
- MEDIUM patched: `TeamSummary` lives on the profile only; `emptyHierarchy` untouched; the three exact-shape unit assertions listed.
- MEDIUM patched: SQL mirror made explicit for admin-before-actor, visited-set loop guard, unresolved warning, and the post-`…000009` anchor.
- LOW patched: helper grants; balances scope-first ordering; office-summary acceptance stated for D7.
- Refuted: null `created_by` (NOT NULL), `teamOnly` bypass via the today-OR branch/status/cursor, `@Can` any-of, `?teamOnly=yes` 422.

### Code review (2026-11-27, 4 thorough lenses on the staged diff)
Verdict: 12 patched, 9 accepted-with-reason, 4 refuted. Two lenses independently found the visited-set divergence; one found the stale registry prose.

**Patched**
- HIGH: SQL `attendance_leave_approvers` seeded its visited set empty while the TS walk seeds the requester — an on-behalf filing on a corrupt loop through the requester returned `[requester]` instead of unresolved. Seeded, plus a real-DB case (`CYC_EMPLOYEE`/`CYC_PARKED`).
- HIGH: `notification-events.ts` still described the reminder as "the tenant owner" — the registry is the FE mirror, updated, with the `pendingCount` meaning.
- HIGH: the widened balances route's grant was in no pin table — added `employeeBalances` to the `leave-controllers` `@Can` table.
- HIGH: `teamOnly` was never driven through the ValidationPipe — added `teamOnly` cases (`true`/`false`/422) to the DTO dialect spec.
- HIGH: the viewer leg of the directory gate had no test — added (a viewer may be a manager, D13).
- MEDIUM: the unresolved-approver warning fired on every five-minute tick after 10:00 (~168 lines/day) — gated to the 10:00 window (10:00–10:04).
- MEDIUM: a corrupt loop reaching the seed node again listed the caller in their own `team.members` / access scope — `d.node_id <> $2` in both projections.
- MEDIUM: `teamOnly`/`teamScope` compared `technicianId` case-sensitively against lowercase DB ids (the DTO accepts a loose uuid) — both lowered.
- MEDIUM: the directory projection re-joined memberships without the liveness predicate — the predicate is now in the join (defensive: `memberships_user_tenant_key` means one row per person, see refuted).
- LOW: `readSubtreeMemberIds` had lost its lean projection (it delegated and paid the directory's two joins/wide rows on the jobs/leave hot paths) — both readers now share one `SUBTREE_WALK` text with their own projection.
- LOW: `teamOnly` missing from the `GET /jobs` operation summary + its 404 note; `team` missing from the `/users/me` summary; the balances 404 prose now says "or is not an employee".
- LOW: real-DB coverage for the new directory query (joins, `status` cast, pruning, parked manager) added to the routing integration suite.

**Accepted with reason**
- The digest now costs one approver walk per pending request on each tick after 10:00 (the old shape was one aggregate). Bounded by the pending-request count, indexed lookups, and the dedupe key keeps inserts idempotent; a "today's digest exists" short-circuit is the follow-up if a tenant ever carries hundreds of pending requests.
- `teamOnly` builds an unbounded `in()` id list — the same documented trade-off the pre-existing `teamScope` makes (a branch in the hundreds is the trigger to push the predicate into the view).
- `teamOnly` is strict-below while CAP-2's "subtree" is self-plus-below; deliberate (a manager's own pending job routes above them) and pinned.
- `headcount` may exceed `members.length` (a disabled member's reports count but are not actionable) — documented on the type and in the tests; no second count field.
- The manager's own balance card is 403 through this route while they have no reports — `GET /attendance/me/leave/balances` is the self route; "today's 403 verbatim" is the CAP-2 requirement.
- A viewer report's balances 404 through this route (they hold no leave) — the 404 prose now says so.
- The SQL `v_max_steps := 21` mirrors `MAX_HIERARCHY_DEPTH + 1` by comment only; a text-parsing drift test is not worth its fragility.
- The hierarchy and the directory read in two transactions — deliberate: the directory's own try/catch must not be able to abort the hierarchy read.
- `presignAvatarUrls` per report on boot — signing is local (no network call), one per distinct key.

**Refuted**
- "A removed-then-reinvited person has two membership rows and the projection can read the stale one" — `memberships_user_tenant_key` is `unique (user_id, tenant_id)` (checked live), so the history row IS the row; the predicate stays as documentation.
- "A manager with reports can read an out-of-branch `technicianId`" — the branch test 404s before existence, as pinned.
- "The on-behalf POST accept side is not subtree-scoped" — it is (`leave.service.ts` `applyTransact`, non-admin path), and the preview is `self + below` because a picker never offers yourself while the accept side may.
- "`readOwnTeam`'s two reads can disagree" — see accepted (two transactions are the point).

**Pre-existing, out of scope (identical at the `03ef0c6` baseline, verified by stashing):** `test/jobs.e2e-spec.ts` 5 POST-create failures (422 on `POST /jobs`), `test/users.e2e-spec.ts` 4 failures (a 500 on the two tenant-profile cases, plus two stale `jobCounts`/access assertions). The e2e suite is red at HEAD; the 24-5b wire assertions were therefore kept out of those files.


## Design Notes

- **Directory on `/users/me`, not a new endpoint.** The Team screen and the apply-on-behalf picker are both opened after the profile loads; a second discovery call would need its own loading state for no benefit. Admins keep `[]` because `GET /members` already serves the roster and an owner's profile is fetched on every foreground. The list is unbounded (a branch is rarely hundreds deep) and ordered by name then id; a paged team directory is the follow-up if a single branch ever gets that large.
- **`teamOnly` is an explicit opt-in filter with strict-subtree meaning.** D13 says role rights are never narrowed; a caller asking for their team is asking for a filter. It lists people BELOW the caller only — a manager's own pending job routes above them, so it is never part of their approval queue.
- **The approver walk is SQL, not TS.** The reminder runs inside pg_cron with no Nest process; the helper is the smallest honest mirror, and the TS walk stays the source of truth (comment links both).
- **D7 is half-served by design:** `attendance.reminder_not_checked_in` (the office aggregate) still goes to the company admins. It is not per-requester — a manager has no "resolved set" for an office count — so it stays an owner/ops signal; only the leave digest moves.
- **Consciously accepted:** G6 (viewer on-behalf — product decision), G7 (team pending counts — the card can omit them), G9 (named approver — "waiting above you" satisfies CAP-5), G10 (no `hasTeam` field — the app refreshes `/users/me`; the server already 403s), G8 and G1 were void on re-check.

## Verification

**Commands:**
- `bun run typecheck` -- expected: clean — PASS
- `bun run lint` -- expected: clean — 1710 pre-existing errors at baseline (test files, `any`); every changed `src/` file is clean and both new/changed integration specs report 0
- `bunx jest` -- expected: all unit suites pass — PASS (198 suites, 3745 tests)
- `node --env-file=.env node_modules/.bin/jest --config ./test/jest-e2e.json attendance-reminder` -- PASS (3 suites, 20 tests, 4 skipped)
- `… attendance-leave` (real DB, the balances write paths) -- PASS (34 tests)
- `… jobs.e2e` / `users.e2e` -- 5 + 4 failures, identical at the `03ef0c6` baseline (verified by stashing); out of scope, recorded in the triage log.
- Live DB: `attendance_leave_approvers` answers `null` for the corrupt loop through the requester (both self-filed and on-behalf), `[owner]` for a deactivated manager's report, and the admin set (minus the actor) for an unassigned request; `attendance_run_reminders` is wired to the helper and the warning probe is gated to 10:00–10:04.

**Manual checks:**
- On the live API as a manager: `/users/me` shows the reports; `?teamOnly=true` narrows; a report's balances answer 200.
