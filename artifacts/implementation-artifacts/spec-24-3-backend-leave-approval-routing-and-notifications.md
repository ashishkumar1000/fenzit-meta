---
title: 'Leave approval routing and notifications (24-3)'
type: 'feature'
created: '2026-11-27'
status: 'approved'
baseline_commit: '9619cca'
review_loop_iteration: 1
context:
  - 'workspace/core/backend/fenzit-be/project-context.md'
  - 'artifacts/specs/spec-company-hierarchy/SPEC.md'
  - 'artifacts/specs/spec-company-hierarchy/approval-routing.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** All leave is decided by admins. The tree exists but nothing routes a request: a manager with reports still cannot approve their team's leave, and every admin is notified of every submission.

**Approach:** Compute the resolved approver set from the tree at **action time** (`approval-routing.md`): the nearest eligible manager above the requester, or all active admins when the walk falls back (D12); an admin's own filing is decided by that admin (D11); a manager's on-behalf filing routes up and never to the actor (D14). Decision rights and submission notifications follow the set. Requests stay pending until someone decides — never auto-approved. Tree changes that alter a pending request's set emit set-difference notices.

## Boundaries & Constraints

**Always:** the resolved set is derived, never stored on the request; the walk skips the requester, the filing actor, and inactive/removed/disabled members; an active member with no manager is a valid single approver, and stepping up from an unassigned member yields the fallback set of all active admins except the actor; a revisit means a corrupt tree and an exhausted walk means an ownerless company — both refuse at action time with plain English, and at submission suppress the approver notification with a logged warning (the request stays pending); any active admin keeps the override on any company request; the walk and the decision write share one transaction and the existing advisory locks; each recipient gets one notification per event (recipient-aware dedupe key); the actor never self-notifies; existing request/response shapes stay additive.

**Resolved (owner, 2026-11-27):**

1. **Reminder routing is deliberately deferred in this pass.** `leave.pending_reminder` is emitted by the pg_cron function `attendance_run_reminders` (currently notifying the office/company-wide set). Rewriting that PL/pgSQL safely — while keeping the attendance legs and the 10:00 wall-time gate untouched — is a separate, riskier change than the request-time routing this story owns, so the function is **left exactly as it is**. Consequence, recorded as the one known gap: a pending request's daily reminder still goes to the old office audience until that function is ported. Request-time routing, decision rights, the submission snapshot and the reassignment notices are all complete and unaffected.
2. **The submission snapshot gets a column.** `leave_events.resolved_approvers uuid[]` (DDL only) records the set at submission; routing stays derived at action time.
3. **On-behalf still informs the employee.** A manager's on-behalf filing notifies the resolved approver set *and* keeps today's employee notification; an admin's on-behalf filing stays created-decided and notifies the employee only (today's behaviour).
4. **Fallback means a set.** Any member of the fallback set may decide; the first decision wins and closes the request for everyone (existing state guard), and the audit row records the actor.
5. **Two new error codes** — `NOT_AN_APPROVER` (403) and `APPROVER_UNRESOLVED` (409) — so the app can render "waiting for someone else" distinctly from corruption/permission.

**Never:** job routing or `decide_pending_job` (24-4); storing an approver on the request; auto-approval; changing day-state transitions, the overlap index, or the attendance-reminder legs; notifying admins outside the set; notifying the actor of their own filing; UI.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| SINGLE_MANAGER | member's nearest active manager, not the actor | that manager decides; notifications go to them alone | — |
| UNASSIGNED_MANAGER | nearest eligible candidate has no manager | that member is the single approver | — |
| FALLBACK | the walk steps up from an unassigned member | all active admins except the actor; any may decide | — |
| ADMIN_SELF | an active admin files their own leave | stays pending; that admin decides; no submission notification | — |
| ADMIN_OVERRIDE | any active admin acts on any request | allowed regardless of the set | — |
| ON_BEHALF_MANAGER | a manager files for a report | routes above the subject, skipping the actor; employee still notified | — |
| ON_BEHALF_ADMIN | an admin files on behalf | created decided (today); employee notified | — |
| NOT_YOURS | an active member outside the set tries to decide | refused, plain English | 403 `NOT_AN_APPROVER` |
| OWNERLESS | no active admin and the walk exhausts | request stays pending; submission notification suppressed + warn; decision refused | 409 `APPROVER_UNRESOLVED` |
| CORRUPT_TREE | the walk revisits a member | refused | 409 `APPROVER_UNRESOLVED` (message names the tree) |
| REQUESTER_MOVES | a pending request's set changes after a tree write | newly resolved members get "now awaiting your approval"; members that left get "no longer yours to approve" | — |
| DEACTIVATED_APPROVER | the set member is deactivated while pending | the walk recomputes on the next action; fallback covers it | — |
| DECISION_NOTIFY | approve / reject / revoke | the requester is notified as today | — |
| REMINDER | daily pending reminder | **deferred** — the pg_cron function keeps today's audience (see Resolved #1) | — |

</frozen-after-approval>

## Code Map

- `src/attendance/approval-routing.ts` — `resolveLeaveApprovers(tx, tenantId, requesterId, actorId)` → `self | single | fallback | unresolved | corrupt`; `mayDecide(set, callerId, isAdmin)`.
- `src/attendance/leave.service.ts` — call the walk inside `actTransact` after the locks (decision right) and in `applyTransact` (notification + snapshot); on-behalf branches.
- `src/attendance/leave-transition.ts` — recipients per event; the new set-difference notices.
- `src/attendance/notification-events.ts` + `src/push/push-copy.ts` — the two reassignment events.
- `src/common/enums/error-code.enum.ts` — `NOT_AN_APPROVER`, `APPROVER_UNRESOLVED`.
- `src/members/members.service.ts` — after `setManager` / `changeRole` / `remove` / `setActive`, emit the set-difference notices for the affected subtree's pending requests.
- `supabase/migrations/20261127000001_leave_events_resolved_approvers.sql` — the snapshot column only (DDL). `attendance_run_reminders` is untouched (Resolved #1).
- `test/integration/attendance-leave.integration.spec.ts` — fixtures gain a manager chain and a second admin; new probes.

## Tasks & Acceptance

**Execution:**
- [x] routing helper + unit tests (single, unassigned, fallback, admin self, actor skip, inactive climb, revisit, exhausted).
- [x] decision rights in approve/reject/revoke + error codes.
- [x] submission notifications + `resolved_approvers` snapshot.
- [x] reassignment notices from the four tree writes.
- [x] ~~reminder function replacement~~ — deferred (Resolved #1); `attendance_run_reminders` untouched.
- [x] journey suite: green baseline recorded (31/31 at HEAD), then probes 32–34 (single-manager routing, on-behalf routing, creator-admin revoke) — 34/34 green.

**Acceptance Criteria:**
- Given a manager with a report, when the report files leave, then the manager is the only approver notified and can approve; an admin also can (override).
- Given an admin's own request, when it is filed, then no submission notification is emitted and the admin decides it.
- Given a manager who files on behalf of a report, when the request is created, then it routes above the subject (never to the actor) and the employee is informed.
- Given a member outside the set, when they try to decide, then they get a plain-English 403 and nothing changes.
- Given an ownerless company, when leave is filed, then no approver notification is sent (a warning is logged) and the request stays pending; a decision attempt is refused, never auto-approved.
- Given a re-parent while a request is pending, then the new approver gets "now awaiting your approval" and the old one "no longer yours to approve", once each.

## Design Notes

- The walk loads the company's memberships once and walks in memory (visiting set + depth cap), so a corrupt loop cannot spin; the fallback admins are read in the same query.
- Decision actor for D14 is `leave_requests.created_by` — the person who filed — not the requester; that is what excludes a manager from deciding their own on-behalf filing.
- The reassignment notices are emitted only for pending requests whose requester is the changed member or inside their pre-change subtree; the requester ids are captured before the write (a removal re-parents the reports, so the post-write subtree no longer contains them), the new sets are read after. A non-live requester (removed/deactivated/disabled) is skipped: their request belongs to the removal flow.
- An admin change widens the affected requesters to every live member: an admin is the fallback approver for every request whose walk ends without a manager, and those requesters are not in the admin's subtree. The diff drops the ones whose set did not actually move.
- Dedupe keys keep `<tenant>:<event>:<recipient>:<requestId>:<tree-write-uuid>`; the per-write suffix lets A→B→A notify again, and a set member who is also an admin still gets one row, not two.
- A created-decided (admin on-behalf) filing skips the walk entirely and records `resolved_approvers = null`; the column is null whenever nobody was asked (self-decided, ownerless, corrupt). The employee notification payload carries `status` (`pending`/`approved`) so the copy can tell "filed for you" from "booked for you".
- AD-6 own retries answer before the approver gate (a reorg must not turn a committed decision's retry into 403), and an on-behalf idempotency replay answers before the subtree/D10 gates (an at-least-once client never sees not-found for its own create).
- The on-behalf preview answers an inline `{ ok:false, errorCode, message }` outside the subtree — previews never 404. UUIDs are lowercased at the boundaries (`employeeId`, routing walk keys) so a mixed-case client id cannot read as a not-found or a corrupt tree.
- Reminders stay with `attendance_run_reminders` — deferred, documented, and called out as the residual gap. The snapshot column exists so a future port can read the set the request was filed against.

## Verification

**Commands:**
- `bun run typecheck` (only the pre-existing `allow-bodiless-delete.ts` error); `bunx jest src/attendance src/members src/common src/jobs src/auth --runInBand` → 1988 green.
- `node --env-file=.env node_modules/.bin/jest --config ./test/jest-e2e.json test/integration/attendance-leave.integration.spec.ts --runInBand` → 34/34 green (31-probe baseline + probes 32–34 added by this story).
- Live probe against the `.env` DB (real HTTP, real DB): owner + second admin + manager + report; setup and enrolment through the routes; file leave as report; assert only the manager is notified; approve as manager; non-approver 403; on-behalf (fresh + subtree 404); re-parent and assert both notices; promotion-to-admin set change; admin on-behalf then creator revoke. All checks passed.
- DB: `notifications` (recipient + event per request), `leave_events.resolved_approvers` (submission snapshot vs. derived routing), `audit_log` (manager/role writes).

**Implementation decisions discovered by the verification (recorded, not silent):**
- **`leave.approve` is now granted to employees and viewers.** The guard can no longer be the approver filter — a manager is an employee, so an admin-only grant made manager approval unreachable. The resolved-approver walk and admin override in `actTransact` decide; anyone outside the set gets 403 `NOT_AN_APPROVER`. This is the D13 "rights are tree-derived" reading: a viewer assigned as a manager keeps the decision right, and a non-manager viewer still fails the service check.
- **The admin override is evaluated before the unresolved refusal.** `approval-routing.md` says any active admin may act "regardless of the walk's outcome"; the previous order made an admin unable to revoke an admin-created on-behalf request (the creator is the actor, so the walk resolved to ownerless). The 409 `APPROVER_UNRESOLVED` still answers non-admins.
- **BMAD review folds (adversarial + edge-case + verification-gap lenses):** removal captures requesters pre-write so a re-parented report's pending request still notifies its new approver (and the removed member, now inactive, is not notified); non-live requesters are skipped; an admin change widens to fallback-routed requesters; the dedupe key gains a per-write UUID; AD-6 own retries and on-behalf replays answer before the routing/scope gates; created-decided filings skip the walk and write a null snapshot; the preview refusal is inline; UUIDs are normalised. New unit coverage: members `remove`/`changeRole`/`setActive` notices, reject/revoke refusals, corrupt-tree submission/decision branches, a distinct unassigned-manager matrix row, and the on-behalf `status` payload/push title.
- **ADMIN_SELF through `/me/leave` is not reachable**, because only `employee`-role members can be attendance-tracked. The live shape is a requester promoted to admin while a request is pending (probe 34): the tree write releases the old approver and the promoted admin decides their own request. The no-submission-notification rule is pinned in the unit tests.

