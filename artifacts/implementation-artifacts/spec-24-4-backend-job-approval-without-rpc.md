---
title: 'Job approval without RPC (24-4)'
type: 'feature'
created: '2026-11-27'
status: 'done'
baseline_commit: 'af43023'
review_loop_iteration: 2
context:
  - 'workspace/core/backend/fenzit-be/project-context.md'
  - 'artifacts/specs/spec-company-hierarchy/SPEC.md'
  - 'artifacts/specs/spec-company-hierarchy/approval-routing.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** The job decision path is still the `decide_pending_job` PL/pgSQL function, owned-only. A manager with reports cannot decide their team's pending jobs, and `job.submitted` still fans out to every active admin. The epic's zero-RPC rule cannot hold while this path lives in the database.

**Approach:** Move the decision to a NestJS transaction with the **same endpoint contract** (`POST /jobs/:id/approval`, same body/response). The decision right is the resolved approver set from the tree walk (24-3), with the admin override and admin self-decide. `job.submitted` goes to the resolved set, not all admins. Tree changes that alter a pending job's set emit the same set-difference notices as leave, and the submission audit row records the set at submission. The RPC stays in the database but is no longer called; story 24-7 retires it later.

## Boundaries & Constraints

**Always:** the walk is the same `approval-routing.ts` helper (requester = creator, actor = creator, so the creator is never an approver); any active admin keeps the override; the walk and the decision write share one transaction holding the same `attendance_lock_tenant(..., false)` shared lock as leave decisions (tree writes take it exclusively); the job row is locked with `FOR UPDATE`; the status guard is `UPDATE ... WHERE status = 'pending_approval'` so exactly one decision wins a race; one `activity_logs` row is written in the same step; a second decision answers 409 `JOB_NOT_PENDING` (no own-retry 200 — the documented lost-response reconciliation is the conflict); submission and reassignment notifications preserve the existing payloads and add recipient-aware dedupe keys; cross-company ids stay 404; the actor never self-notifies.

**Resolved (owner, 2026-11-27):**

1. **Job error codes keep the endpoint contract.** A member outside the resolved set answers 403 `FORBIDDEN` (the epic-22 contract), not `NOT_AN_APPROVER`; an unresolvable walk answers 409 `APPROVER_UNRESOLVED` (the new, additive code shared with leave) because `JOB_NOT_PENDING` would misdescribe a routing failure.
2. **The submission snapshot is `activity_logs.resolved_approvers uuid[]`** (DDL only). The create RPC is untouched; the snapshot is written immediately after it commits, best-effort like the submission alert, because the create path is not the path this story moves off RPC. Null means nobody was asked (ownerless/corrupt or a non-pending create).
3. **Job reassignment events are `job.approver_added` / `job.approver_removed`** — the job family's own names, not the leave events — with job copy (`Job awaiting your approval` / `No longer yours to approve`) and the same per-write dedupe suffix.
4. **`job.approve` becomes tree-derived**: granted to employees and viewers (a manager is an employee; a viewer assigned as a manager keeps D13 rights). The service enforces the set; the guard only lets the request reach it.
5. **The RPC stays callable** until 24-7; this story only stops calling it. Existing integration suites that exercise the RPC remain green.

**Never:** retire the RPC; change the request/response shape; touch job create/update RPCs, workflow steps, attachments or state machine; job on-behalf or manager job creation (future stories); UI.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| SINGLE_MANAGER | creator's nearest active manager decides | job scheduled/rejected; creator notified | — |
| FALLBACK | walk steps up from an unassigned member | any active admin except the creator decides | — |
| ADMIN_OVERRIDE | any active admin decides | allowed regardless of the set | — |
| ADMIN_SELF | creator promoted to admin while pending | that admin decides their own job | — |
| NOT_YOURS | outside the set | refused, plain English | 403 `FORBIDDEN` |
| OWNERLESS / CORRUPT | walk unresolved | refused | 409 `APPROVER_UNRESOLVED` |
| NOT_FOUND | unknown / other company | not found | 404 `RESOURCE_NOT_FOUND` |
| NOT_PENDING | already decided, including own retry | refused | 409 `JOB_NOT_PENDING` |
| RACE | two decisions concurrently | one wins; the other 409 | 409 `JOB_NOT_PENDING` |
| SUBMISSION | employee creates a pending job | resolved set notified (not all admins); `activity_logs` snapshot | warn + suppress on unresolved |
| REQUESTER_MOVES | tree write changes a pending job's set | added members notified, removed members notified | — |
| DECISION_NOTIFY | approve / reject | creator notified as today | — |

</frozen-after-approval>

## Code Map

- `src/attendance/approval-routing.ts` — reuse the walk; rename the pg wrapper to `resolveApprovers` (generic) and keep leave callers on it.
- `src/jobs/jobs.service.ts` — `decidePendingJob` becomes a `PgPoolFactory` transaction; submission resolves the set and writes the snapshot; alerts follow the set.
- `src/jobs/pending-job-notifications.ts` — `alertApproversOfSubmission(admin, job, recipientIds)`; add the two approver events.
- `src/attendance/approval-reassignment.ts` — pending-job snapshots + set-difference emission alongside the leave reader.
- `src/members/members.service.ts` — the four tree writes also diff pending jobs.
- `src/common/permissions/permissions.ts` (+ spec) — `job.approve` for employees/viewers.
- `src/push/push-copy.ts` — copy for the two job approver events.
- `supabase/migrations/20261127000002_activity_logs_resolved_approvers.sql` — DDL only.
- `test/integration/` — extend the pending-job journey for routing and reassignment; keep the RPC suites green.
- Live HTTP + DB probe for the manager/employee/admin routes and the `activity_logs`/`notifications` evidence.

## Tasks & Acceptance

**Execution:**
- [x] decision transaction (locks, row lock, walk + gate, guarded update, activity row).
- [x] submission routing + `activity_logs` snapshot.
- [x] job set-difference notices from the four tree writes.
- [x] permissions grant + push copy.
- [x] unit + integration + live probe + DB verification.

**Acceptance Criteria:**
- Given a report's pending job, when their manager decides, then the job changes and the creator is notified; an admin outside the set is not notified of the submission.
- Given a member outside the resolved set, when they decide, then 403 and nothing changes.
- Given two concurrent decisions, then exactly one wins and the other gets 409.
- Given a re-parent while a job is pending, then the new approver gets "now awaiting your approval" and the old one "no longer yours to approve".
- Given an ownerless/corrupt tree, then the submission warning is logged, no approver is notified, and a decision is refused, never auto-approved.
- Given the endpoint, then the request and response shapes are unchanged.

## Design Notes

- The decision transaction mirrors leave: shared tenant advisory lock → job row lock → walk → gate → guarded update → activity row. The job is not employee-tracked, so there is no per-employee advisory lock.
- The walk reuses the leave helper after a generic rename; the requester and actor are both `jobs.created_by` (an owner-created job is never pending, and job on-behalf is out of scope).
- The snapshot update targets the `job_submitted` activity row (the create RPC writes `job_submitted`, not `job_created`, for a pending job), tenant-scoped, and logs a warning when it matches zero rows.
- The admin override is decided from the live approval tree read inside the decision transaction — not from the role on the token — so a demotion, deactivation, disable or removal that commits while the request waits on the lock cannot leave a stale admin deciding one more job.
- A pending job with a NULL `created_by` answers 409 `APPROVER_UNRESOLVED` with a no-creator reason to non-admins and stays decidable by a live admin.
- Submission routing takes one retry (transient lock timeout); a second failure only logs, because the create RPC has already committed and must not turn into a 500. A tree write that already emitted `job.approver_added` for the new approver suppresses the duplicate submission alert.
- Job set-difference notices skip the actor (an admin who makes themself the manager is not told about the job they just took over).
- Job notices use `notifications.job_id` (not `entity_id`) and the per-write UUID dedupe suffix; the leave events remain untouched.

## Verification

**Results (2026-11-27):**
- `bun run typecheck`: clean except the pre-existing `src/common/allow-bodiless-delete.ts(61,23) TS2345`.
- `bunx jest src/jobs src/members src/common src/attendance src/push src/auth src/job-reports --runInBand`: **2158/2158 passing, 104 suites**. New pins: decision lock order + guarded update + `for update`, live-tree admin (demoted/disabled), null creator, manager-above refusal, creator-not-technician routing, routing-failure survival, snapshot SQL (`job_submitted`, tenant-scoped), submission race dedupe, actor self-notice suppression, the job emitter's A→B→A→B dedupe keys, producer→consumer push copy, and the three previously untested tree write paths (`changeRole`, `remove`, `setActive`).
- Live HTTP + DB probe against the `.env` project (`pnlvreaijzslfymlnoti`), master OTP, server on `:3000`: **45/45 checks** — submission routed to the manager only; manager approves; outsider 403 `FORBIDDEN`; re-parent emits `job.approver_added`/`job.approver_removed`; admin override; promoted creator decides their own job; concurrent decisions → one 200 + one 409 `JOB_NOT_PENDING` with exactly one decision row; post-decision retry 409; cross-company 404 `RESOURCE_NOT_FOUND`; employee refused by the tenant queue and owner report while admins still read both.
- DB evidence: `activity_logs.resolved_approvers` = resolved set per pending job (`job_submitted` rows), one `job_approved`/`job_rejected` row per decision, notification rows only for the resolved recipients.
- Integration suites still skip against the live guarded project (`IS_REAL_DB` guard); the probe is the DB oracle in this environment.

## Review Folds (BMAD, 3 lenses)

Applied:
- adversarial: live-tree admin override (stale token role), NULL-creator reason, actor self-notice suppression, submission-alert dedupe after a racing tree write, one routing retry.
- edge-case: `job.reports` kept outside `ADMIN_PERMISSIONS` so platform admins do not inherit a company's queue/report; regression pins for manager-above refusal, technician-vs-creator routing, disabled admin, and the three non-`setManager` tree writes.
- verification-gap: push payload switched to the snake_case keys `pushCopyForEvent` reads (the camelCase payload produced an empty push body); `job.approve` no longer gates the tenant-wide owner surfaces; snapshot update tenant-scoped, counted and unit-pinned; lock/`FOR UPDATE`/guarded-update assertions; route permission metadata restored.

Deferred (recorded, not silently dropped):
- A removed/deactivated **creator's** pending job is skipped by the set-difference diff (same rule as leave since 24-3) and no flow cancels it. Owned by a future job-lifecycle story; the admin queue can still decide it.
- The integration suites remain skipped against the live project; the temporary probe is deleted at commit, so CI DB runs are the durable oracle once pointed at a test database.
