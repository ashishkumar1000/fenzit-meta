---
title: 'Hierarchy data model and manager assignment (24-1)'
type: 'feature'
created: '2026-11-26'
status: 'done'
baseline_commit: 'e86f41aba31851c9daa5ee6b319c3aa8c9347bc1'
review_loop_iteration: 1
context:
  - 'workspace/core/backend/fenzit-be/project-context.md'
  - 'artifacts/specs/spec-company-hierarchy/SPEC.md'
  - 'artifacts/implementation-artifacts/24-1-port-parity.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** A company is flat: the owner sees and approves everything, and nothing records who reports to whom. Stories 24-2 to 24-5 need a reporting tree as their foundation.

**Approach:** Add `memberships.manager_id` ("Reports to"), assign or clear it in one guarded transaction (admin target, cycle, depth), re-parent a removed member's direct reports, and surface the manager, upward chain and subtree headcount on the member payloads.

## Boundaries & Constraints

**Always:** one pointer per member, on `memberships`; the member assigned may be invited, active or deactivated, never removed; the manager must be an active, enabled, same-company member; an admin may serve but never be assigned one; no self, no cycle, and the deepest descendant after the write is at most 20 levels; every check and the write run in one transaction under the tenant lock, with the caller re-checked after the lock, a guarded write and a plain-English refusal; removal re-parents direct reports to the removed member's manager when that manager is still active (else unassigned) and clears the removed member's own pointer; promotion to `company_admin` clears the promoted member's own pointer; one audit row per changed membership, including every re-parented report; zero RPC and zero PL/pgSQL — DDL-only migration, direct `audit_log` inserts; fields additive; cross-company ids answer not found.

**Resolved (owner, 2026-11-26):** (1) promoting a member who already has a "Reports to" to `company_admin` clears their own pointer in the same transaction — they become L1, their reports stay under them. (2) the contract says the composite FK targets `users(id, tenant_id)`, but `users.tenant_id` was dropped in `20261020000004`; the FK targets `memberships(user_id, tenant_id)` and the deviation is recorded.

**Never:** subtree visibility or approval routing (24-2/24-3/24-4); app or web UI (24-5/24-6); re-parent on deactivation or role change; a new RPC; more than one manager per person; level labels (L1/L2) in any payload or copy.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| HAPPY_PATH | owner assigns an active member as manager of an invited/active member | updated payload with manager, chain and headcount; one audit row naming the owner | — |
| ADMIN_AS_MANAGER | the chosen manager is an active `company_admin` | allowed; their reports form L2 | — |
| ADMIN_TARGET | the member being assigned is a `company_admin` | refused, nothing written | 409 `MEMBER_IS_ADMIN` |
| SELF | `managerId` equals the member | refused | 422 `VALIDATION_ERROR` |
| MANAGER_INACTIVE | manager is invited, deactivated, removed or disabled | refused | 422 `MANAGER_NOT_ACTIVE` |
| CROSS_COMPANY | manager id belongs to another tenant | not found, no existence leak | 404 `RESOURCE_NOT_FOUND` |
| CYCLE | proposed manager is a descendant of the member | refused | 409 `HIERARCHY_CYCLE` |
| DEPTH | deepest descendant after the write would exceed 20 levels | refused | 409 `HIERARCHY_DEPTH` |
| CLEAR | `managerId` is null | 200; chain and headcount recomputed; audit only if it changed | — |
| TARGET_REMOVED | the member being assigned is `removed` or absent | not found | 404 `RESOURCE_NOT_FOUND` |
| REMOVE_WITH_REPORTS | remove a member with N direct reports | member removed; each report re-parents to their manager; one audit row per report | — |
| REMOVE_TO_INACTIVE | the removed member's own manager is deactivated/disabled/removed | reports become unassigned rather than inheriting a dead pointer | — |
| REMOVE_SELF_POINTER | remove a member who has a manager | the removed row's `manager_id` becomes null | — |
| PROMOTE_TO_ADMIN | promote a member who has a "Reports to" | role changes and their own pointer clears in one write | — |
| INVITE_WITH_MANAGER | invite with `managerId` | membership carries the pointer; it shows on the member list, not in the invite response | invalid manager gets the same refusals |
| INVITE_ADMIN_WITH_MANAGER | invite with `role: company_admin` and `managerId` | refused | 409 `MEMBER_IS_ADMIN` |
| LAST_ADMIN | remove, demote or deactivate the only active admin | unchanged existing refusal | 409 `LAST_ADMIN` |

</frozen-after-approval>

## Code Map

- `workspace/core/backend/fenzit-be/supabase/migrations/<new>.sql` — DDL only: `manager_id`; FK `(manager_id, tenant_id) → memberships(user_id, tenant_id)`; not-self CHECK; `(tenant_id, manager_id)` index.
- `src/common/members/hierarchy.ts` — one recursive-CTE helper: chain, headcount, direct count, cycle/depth probe.
- `src/members/members.service.ts` — `setManager`; ported `remove`/`changeRole`; fields on `MemberView`.
- `src/members/members.controller.ts` + `src/members/dto/set-manager.dto.ts` — `PATCH members/:userId/manager`.
- `src/auth/dto/invite-member.dto.ts` + `src/auth/auth.service.ts` (`runInviteTx`) — optional `managerId`.
- `src/common/permissions/permissions.ts` — `member.manager` in the company-admin-only set.
- `src/common/enums/error-code.enum.ts` — the four codes.

## Tasks & Acceptance

**Execution:**
- [ ] migration — DDL; not applied before review and owner consent.
- [ ] `setManager` — tenant lock, post-lock caller re-check, target/removed guard, admin target, manager active, cycle/depth, guarded update, audit.
- [ ] `remove` + `changeRole` — port per `24-1-port-parity.md`; re-parent, clear the removed pointer, promotion clears the member's pointer.
- [ ] `hierarchy.ts` — chain/headcount/direct count merged into the three member reads, no N+1.
- [ ] controller + DTO — expose the route.
- [ ] invite — validate `managerId` after the tenant lock; response shape unchanged.
- [ ] permissions + error codes.
- [ ] specs — every matrix row; the four pinned files are listed in `24-1-port-parity.md`.

**Acceptance Criteria:**
- Given an owner and a member, when the owner sets a valid manager, then the payload shows "Reports to", the full upward chain and the headcount, and an audit row names the owner.
- Given a descendant manager or a tree deeper than 20 after the write, when the owner saves, then the write is refused with the matching code and nothing changes.
- Given a member with direct reports, when the owner removes them, then every direct report's manager becomes the removed member's manager (or null when no longer active), each with its own audit row.
- Given an invite with a manager, when it succeeds, then the membership carries the pointer visible on the member list.

## Design Notes

- Lock order: `attendance_lock_tenant($1, true)`, then `select … for update`, then re-read caller and target. Sign-in's `invited → active` and the employment save are the only writers that skip this lock.
- Depth = level after the write + the member's own subtree depth ≤ 20, so story 2's capped CTE never truncates a legitimate branch.
- Audit actions `member.manager_change` / `member.reparent`; a same-pointer call writes nothing; fan-out inserts in one statement.
- `CompanyMember` stays untouched (15 consumers); hierarchy fields live on `MemberView` only.
- Removal keeps today's semantics (no leave sweep — `cancelLeaveOnDisable` belongs to attendance enrolment); the old functions remain but nothing calls them.

## Verification

**Commands:**
- `bun run typecheck` — expected: clean.
- `bunx jest src/members src/auth src/common/permissions --runInBand` — expected: all specs pass (jest, not `bun test`).
- `bun run lint` — expected: no new findings.
- Manual — inspect the migration for DDL-only content; apply through Supabase MCP only after review and owner consent.

## Review pass (BMAD thorough, 4 lenses)

Folded in after the first green run:

- **One write guard.** `assertManagerAssignable` (`src/common/members/manager-assignment.ts`) now serves both `PATCH …/manager` and the invite. It unifies the drift the two copies had: self is `422 VALIDATION_ERROR` on both paths, a `removed` manager is `422 MANAGER_NOT_ACTIVE` (the matrix row, not 404), and an active-but-disabled manager is refused on the invite path too.
- **Read cost.** `readMemberHierarchy` no longer seeds its walk from every live membership. Both walks start at the requested ids; the downward one carries its root, so a page costs its own branches, not the company. Duplicate rows from a corrupt loop are counted once; a self-ancestor is never rendered.
- **Audit parity.** `insertAuditRows` takes `actor_is_platform_admin` from the actor's `users` row (never the JWT) and validates the action (1–80 chars). The invite's audit entry records `manager_id`.
- **DTO.** `managerId` is `@IsDefined` — a missing key says "required" instead of "invalid UUID"; `null` still clears.
- **Target state.** A disabled or removed target is `404` before any write (previously the pointer was written and the response was 404). A disabled manager cannot land mid-transaction (`for share`).
- **Admin target.** Assignment stays `409 MEMBER_IS_ADMIN`; clearing a stray pointer is allowed.
- **Test gap closed.** list/listPaged hierarchy merge, post-lock caller re-check order, re-invite manager param, disabled target, admin-as-manager, admin clear, already-null clear, invited/deactivated target, exact depth boundary, chain/depth SQL caps.

Not changed, by decision: platform staff cannot reach `PATCH …/manager` (permission is company-admin-only); the ported PL/pgSQL functions stay installed but unused; the invite audit remains post-commit (pre-existing pattern); a post-commit read failure still surfaces as an error although the write committed.
