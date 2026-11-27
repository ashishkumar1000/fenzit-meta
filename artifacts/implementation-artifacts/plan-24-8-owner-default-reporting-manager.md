---
title: 'No member is without a reporting manager — the owner is the default'
type: 'feature'
created: '2026-11-27'
status: 'review'
commits:
  backend: '379b88f'
  web: 'c270b68'
  app: 'def4600'
migration: '20261127000005_owner_default_manager.sql — APPLIED to Fenzit-dev and Fenzit-Be (2026-11-27)'
route: 'full'
route_source: 'owner decision'
review: 'pending'
baseline_commit: 'c1ab204'
context:
  - 'artifacts/specs/spec-company-hierarchy/SPEC.md'
  - 'artifacts/specs/spec-company-hierarchy/approval-routing.md'
  - 'artifacts/implementation-artifacts/epic-24-context.md'
  - 'artifacts/implementation-artifacts/plan-24-6-web-manager-column-and-editing.md'
---

## Intent

**Problem:** "Reporting manager" is optional today, so a tenant can fill up with unassigned people — an invite that named no manager, a deliberate clear, a manager who resigned (deactivation leaves `manager_id` pointing at an inactive person; removal could leave it null). The owner sees a flat, partly broken tree and must repair it by hand, profile by profile.

**Decision (owner, 2026-11-27):** every non-admin member always has a manager. Whenever the pointer is missing for any reason, it becomes the **tenant owner**. The owner accepted the two costs: approvals for those people notify the owner only, and the Reports-to column stops distinguishing "never set" from "set to the owner".

**Rule:** the default is `tenants.created_by` (the company creator) while that membership is active and enabled; otherwise the earliest active admin (a creator can be deactivated or removed once another admin exists). Null only for a company with no active admin, which the last-admin rule makes unreachable. Admins never hold a pointer — they sit at the top.

**Schema note:** the roles restructure replaced `tenants.owner_id` with `tenants.created_by`. The first deploy of the helper named the old column; applying the backfill to the dev database first caught it (42703), and the fix shipped as `6cd735f`.

## Boundaries

- **Backend first.** This is a data-shape rule; the apps deploy after it.
- No new endpoint: the shipped contract keeps its shape, and `managerId: null` on `PATCH` now means "hand this person to the default" instead of "unassign".
- Admins, removed members and the ownerless case are untouched.
- The D12 fallback (an unassigned member's request goes to all active admins) stays in the routing walk as the safety net for a corrupt or ownerless tree; it simply stops being reachable through the normal write paths.

## Implementation (backend, this story)

| Surface | Change |
|---|---|
| `src/common/members/default-manager.ts` | `resolveDefaultManager(tx, tenantId, excludeUserId)` — owner first, then earliest active admin; excludes the person who is leaving |
| `MembersService.setManager` | a `null` request resolves to the default; admins stay null; the explicit id keeps every guard |
| `MembersService.setActive` (deactivation) | direct reports move to the leaver's own manager while they serve, else the default; one `member.reparent` audit row per report; the subtree's pending approvals are already in the before/after snapshot |
| `MembersService.remove` | the same helper replaces the old "unassigned" fallback |
| `AuthService.inviteMember` | no `managerId` on the invite resolves to the default (an admin invitee stays at the top) |
| `20261127000005_owner_default_manager.sql` | one-time backfill for existing nulls (invited, active, deactivated; never admins; never the row itself) + the column comment |

**Verification:** 3747 tests / 198 suites green; typecheck clean; prettier clean on the touched files; the new cases assert the deactivation re-parent in both directions, the clear-to-default, the "clear lands on the person already in place" no-op, the removal fallback, and the invite's default on the wire.

**App half (same day):** the picker's no-manager option is now "The company owner — the default when nobody else is chosen" (web `ManagerPicker`, mobile `ManagerPickerStage`); the invite helper reads "Default. You can change this later."; the job-settings sheet's unset label and accessibility label follow. A clear still sends an explicit null, which the server resolves — so the wire contract did not change, only its meaning. Web 1436/121 and app 4672/359 green.

## Still to do

1. **Done:** the backfill ran on both projects via `apply_migration` (`owner_default_manager`). Dev: 24 → 0 unassigned. Production: 364 → 0 unassigned; 0 self-pointers, 0 pointers to disabled users, 0 pointers outside the company. In PayrollQA Works 196 of 202 members now sit under the creator.
2. **Re-verify on the QA tenant** after the Render deploy of `6cd735f`: every employee should read the owner, and a deactivation should move the team.

## Live verification (2026-11-27, after the backfill and the `6cd735f` deploy)

Read-only query against both projects, plus a reversible write pass on the QA company:

| Check | `Fenzit-dev` | `Fenzit-Be` |
|---|---|---|
| Live members | 34 | 470 |
| Unassigned non-admins | 0 | 0 |
| Self-pointers | 0 | 0 |
| Pointers outside the company | 0 | 0 |
| Pointers to an inactive member | 0 | 0 |
| Pointers to a disabled user | 0 | 0 |

QA company (`PayrollQA Works`): 201 non-admins, **0 unassigned**, 196 under the creator, the other 5 with an explicit manager; the creator is an active admin. `GET /api/v1/members` as the owner returns the chain for every row.

Write pass on two employees, fully restored afterwards:

1. Clear Vijay Menon (EMP-036) → `200`, manager became the creator — this is the call that would have 500'd on the old column.
2. Assign Vijay to Anita Pillai (EMP-037) → chain read `Anita Pillai → PQA Owner Ashok Rao`.
3. Deactivate Anita → Vijay moved to **the creator** (Anita's own manager), not left dangling.
4. Reinstate Anita → active again; Vijay restored to the creator.

## Open question for the owner

An explicit **clear** now re-assigns the owner rather than unassigning. If a "really no manager" escape hatch is ever wanted (e.g. a restructure in progress), it is a one-line change in `setManager` — say so and it becomes a small follow-up.
