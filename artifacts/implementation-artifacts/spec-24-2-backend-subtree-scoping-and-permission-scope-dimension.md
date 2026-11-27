---
title: 'Subtree scoping and the permission scope dimension (24-2)'
type: 'feature'
created: '2026-11-27'
status: 'done'
baseline_commit: '3523452'
review_loop_iteration: 1
context:
  - 'workspace/core/backend/fenzit-be/project-context.md'
  - 'artifacts/specs/spec-company-hierarchy/SPEC.md'
  - 'artifacts/specs/spec-company-hierarchy/stories.yaml'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** The reporting tree exists, but every read is still flat. A manager cannot see the leave or the jobs of the people who report to them, so "Your team" has nothing behind it.

**Approach:** Add one subtree helper over the pg pool (recursive CTE, depth-capped, deduplicated) and a scope dimension in `permissions.ts` (`tenant` vs `subtree`, derived from the role — never a new role value). A manager's leave and job reads widen to their own subtree; admins, viewers and members without reports keep exactly today's behaviour. Cross-branch reads answer not found, never 403.

## Boundaries & Constraints

**Always:** one subtree helper, used by both the permission-scope decision and every service read, so the layers cannot drift; the helper is depth-capped at the shared `MAX_HIERARCHY_DEPTH` and deduplicated, so a corrupt loop cannot spin; managers are never a role value; subtree rights are additive to the role's rights (D13); the scope lives in the service layer because reads use the service-role client; an explicit id outside the caller's scope answers `404` (no existence leak); a member with no reports gets today's response; attachment URLs are minted only after the job-detail scope gate; no RPC and no PL/pgSQL; existing API shapes stay additive.

**Resolved (owner, 2026-11-27):**

1. **Leave attachments do not exist** in this codebase (no table, route, service or key prefix; confirmed repo-wide). The story's "leave attachments" clause is therefore a no-op here and is recorded as such — job attachments are the only attachment surface, and detail scoping covers them because signing happens after the gate.
2. **Members without reports answer `403` on the team list and coverage**, exactly as today, rather than an empty 200. A manager with reports sees `self ∪ subtree`.
3. **Viewers** keep their existing reads (`job.read_all` = whole company, no leave read). They gain `leave.read_team` only so a viewer *assigned as a manager* can read team leave (D13); their existing job access is already wider and unchanged.
4. **Job uploads/confirmations stay assignee-only** (`403` as today). Subtree visibility is a read right; the story's "attachments" means the detail payload's signed URLs, not write access.
5. **Leave summary/balances and the jobs page/stats stay admin-only** — they are aggregates, not scoped row reads. A manager's list is scoped; the console counters remain owner surfaces.

**Never:** approval routing or decision rights (24-3/24-4); notifications; cross-branch visibility ("up" or sideways); RLS policies; UI; changing the leave day-state or overlap machinery; a new role.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| MANAGER_LEAVE_LIST | manager with a subtree calls `GET /attendance/leave` | the page holds only rows whose employee is self or in the subtree | — |
| MANAGER_LEAVE_FILTER | manager passes `employeeId` inside the subtree | page narrows to that person | — |
| LEAVE_FILTER_OUTSIDE | manager passes `employeeId` from another branch | refused | 404 `RESOURCE_NOT_FOUND` |
| LEAVE_COVERAGE_IN | manager reads `.../:id/coverage` for a subtree request | coverage answers as it does for an admin | — |
| LEAVE_COVERAGE_OUT | same, for a request outside the subtree | refused | 404 `LEAVE_REQUEST_NOT_FOUND` |
| NO_REPORTS_LEAVE | employee with no reports calls the team list or coverage | unchanged: refused | 403 `FORBIDDEN` |
| ADMIN_LEAVE | company admin or platform admin | whole company, unchanged; no subtree lookup | — |
| MANAGER_JOB_LIST | manager with a subtree calls `GET /jobs` | only jobs whose technician is self or in the subtree | — |
| MANAGER_JOB_FILTER | manager passes `technicianId` in the subtree | list narrows; outside the subtree is refused | 404 `RESOURCE_NOT_FOUND` |
| MANAGER_JOB_DETAIL | manager reads a subtree job | full detail incl. attachment URLs, minted after the gate | — |
| JOB_DETAIL_OUTSIDE | manager reads a job from another branch | refused; no existence leak | 404 `RESOURCE_NOT_FOUND` |
| NO_REPORTS_JOBS | employee with no reports | unchanged self-scope; client `technicianId` still ignored | — |
| VIEWER_JOBS | viewer (with or without reports) | unchanged: `job.read_all` remains whole-company | — |
| UPLOAD_OTHER_JOB | manager requests/confirms an attachment on a report's job | unchanged: refused (writes stay assignee-only) | 403 `FORBIDDEN` |
| CORRUPT_LOOP | a hand-written loop in the tree | the walk terminates at the cap and dedupes ids | — |

</frozen-after-approval>

## Code Map

- `src/common/members/hierarchy.ts` — `readSubtreeMemberIds(tx, tenantId, managerId)`: capped, deduplicated descendants (excludes the root, excludes `removed`).
- `src/common/permissions/permissions.ts` — `leave.read_team` grant (employee + viewer); `readScopeFor(role)` → `'tenant' | 'subtree'`. Single source for the scope dimension.
- `src/attendance/leave.controller.ts` — the list and coverage routes accept `leave.read_all` or `leave.read_team`.
- `src/attendance/leave-read.service.ts` — scope the owner list (`employeeIds`), refuse an out-of-scope filter, scope coverage after the request read.
- `src/attendance/leave.repository.ts` — `listLeaveRequests` gains an `employeeIds` predicate (`= any`), parameterised.
- `src/jobs/jobs.service.ts` — employee-with-reports scope in `listJobs` (default and `technicianId`) and `getJobDetail`; pool injected for the subtree read.
- `src/jobs/jobs.module.ts` — import `PgModule`.
- Unit specs: `hierarchy.spec.ts`, `job-role-grants.spec.ts`, `leave-read.service.spec.ts`, `leave.repository.spec.ts`, `jobs.service.spec.ts`, `leave-controllers.spec.ts`.

## Tasks & Acceptance

**Execution:**
- [ ] helper — `readSubtreeMemberIds`, capped and deduped.
- [ ] permissions — `leave.read_team`, `readScopeFor`; grant pins.
- [ ] leave — list/coverage guard + service scoping; repository `employeeIds`.
- [ ] jobs — service scope for list and detail; module wiring.
- [ ] specs — every matrix row.
- [ ] live probe + DB check.

**Acceptance Criteria:**
- Given a manager with two reports and a request from another branch, when the manager lists leave, then only their own and their reports' rows return and the other branch's request is absent.
- Given the same manager, when they read coverage for a report's request, then it answers; for the other branch's request it answers not found.
- Given an employee with no reports, when they open the team list, then the answer is the same 403 as today.
- Given a manager with a subtree, when they list jobs or open a subtree job, then the subtree's jobs are visible (with attachment URLs when any) and another branch's job is not found.
- Given a viewer, when they list jobs, then they still see the whole company.

## Design Notes

- The scope dimension has two halves that cannot drift: the guard enforces the **role** half through `permissions.ts` (`leave.read_team` on the two leave routes), and the service enforces the **row** half through `readScopeFor(role, companyWidePermission)` plus `readSubtreeMemberIds`. The guard cannot resolve a subtree per request (it has no pool and must stay stateless); the service owns the rows because reads use the service-role client. `readScopeFor` takes the resource's company-wide permission, so a viewer's `job.read_all` is never narrowed (D13 additive) while `leave.read_all` is admin-only.
- The subtree walk seeds at the caller and returns descendants only; callers add `self`. `union` plus a JS `Set` makes a corrupt loop terminate with unique ids.
- `employeeIds = any(...)` keeps one SQL statement; the cursor stays `OWNER_LIST_SCOPE` because paging re-applies the scope on every page.
- Job attachment URLs are minted in `getJobDetail` after the ownership gate, so scoping the detail automatically scopes the signed links; upload/confirm keep their assignee-only check.
- A manager's list may be empty (no rows yet), which is a 200 — the 403 is only for a caller with no reports at all, and it carries the guard's verbatim "Insufficient permissions" body.
- Surfaces deliberately left admin-only: leave summary/balances and preview, jobs page/stats, job attachment upload/confirm/report and device sync. Coverage is readable for a subtree request but its roster stays office/company-wide — CAP-5 wants "who else on the team is off", not a subtree-only roster.
- Subtree rows are non-removed, non-disabled memberships (matching the headcount's "not part of the team"); deactivated members stay visible because their leave history still exists.
- Known limits recorded rather than engineered around: the job list's team ids ride the PostgREST URL (a team in the hundreds would approach the URL limit — move the predicate into `jobs_overview` if it ever bites); the subtree walk and the list read are two READ COMMITTED statements, so a reassignment landing between them can still show the old branch on that one page, self-healing on the next request; job reads now depend on the pg pool being reachable, which attendance writes already require.

## Verification

**Commands:**
- `bun run typecheck` — expected: clean (the repo-wide `allow-bodiless-delete` error is pre-existing).
- `bunx jest src/members src/auth src/common src/attendance src/jobs --runInBand` — expected: all specs pass.
- `bun run lint` on touched files — expected: no new findings.
- Live: `SMS_DELIVERY_PROVIDER=mock` server against the `.env` DB; probe creates a company, activates a manager and two reports, files leave and jobs for both branches, signs in as the manager and checks list/detail/coverage scope.
- DB: confirm the probe's rows and that no request outside the subtree is reachable.
