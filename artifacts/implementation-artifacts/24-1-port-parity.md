# 24-1 — port parity, audit and test checklist

Companion to `spec-24-1-backend-hierarchy-data-model-and-manager-assignment.md`.
Load before touching `members.service.ts` or `auth.service.ts`.

## Port parity (authoritative source: `20261020000005_roles_review_fixes.sql`)

`20261020000002` is superseded; copying it silently regresses two shipped fixes.

- **Caller check.** `users.platform_admin = true` **or** an `active` `company_admin` membership of `tenantId`; the caller must exist and not be disabled. Platform admins reach this path because `permissions.ts` grants `member.remove` / `member.change_role` to `PLATFORM_ADMIN` and staff pass `X-Company-Id`.
- **Re-check after the lock.** Repeat the caller check *after* `attendance_lock_tenant` — they may have been demoted, removed or disabled while waiting. `setActive` does not do this; do not copy that omission.
- **LAST_ADMIN.** A co-admin counts only when their membership is `active` **and** `users.disabled = false`. Applies before demotion and before removal.
- **Self.** `changeRole` / `remove` keep today's `403 FORBIDDEN`. `setManager` and the invite both use `422 VALIDATION_ERROR` for `managerId === userId`.
- **No-op.** A same-role call writes no row and returns the current values.
- **Removed target.** `status <> 'removed'` in the `for update` guard; miss → `404 RESOURCE_NOT_FOUND`.
- **Tenant.** Missing tenant on the caller → `400 VALIDATION_ERROR` ("Company setup required"), matching the other company-scoped write endpoints; a tenant id that names no company row → `404 RESOURCE_NOT_FOUND`.
- **Manager states.** An absent manager id, or one from another company → `404 RESOURCE_NOT_FOUND`. A manager whose membership is `invited`, `deactivated` or `removed`, or whose account is disabled → `422 MANAGER_NOT_ACTIVE`. A `company_admin` **target** refuses assignment with `409 MEMBER_IS_ADMIN`; clearing a stray admin pointer is allowed.

## Audit rows (reproduce `write_audit_row`, do not call it)

Columns: `actor_user_id`, `actor_is_platform_admin`, `tenant_id`, `action`, `target_user_id`, `details`.

Also reproduce its guards before inserting: actor exists and is not disabled; `actor_is_platform_admin` is read from the actor's `users` row (never trusted from the JWT); every target user exists; the action is non-blank and at most 80 characters. The invite's audit entry carries `manager_id` alongside `role` / `reactivated`.

- Actions: `member.manager_change` (`{old_manager_id, new_manager_id}`), `member.reparent` (`{old_manager_id, new_manager_id, removed_manager_id}`), keep `member.role_change` / `member.remove` names.
- Re-parent fan-out: one `insert … select` over the affected rows, not a loop of inserts (the pool sets `statement_timeout = 10000`).

## Hierarchy reads

- `headcount` — everyone strictly below the member; excludes self, `removed` memberships and disabled users.
- `directReports` — immediate reports only; CAP-6's "Priya's 3 direct reports".
- `chain` — manager ids + names walking upward, nearest first, stopping at an unassigned member.
- Cast counts with `::int`; `pg` returns `count(*)` as a string.
- `CompanyMember` in `src/common/members/company-members.ts` is the shared reader for 15 modules — do not add fields there.

## Tests that pin the old behaviour

| File | What changes |
|---|---|
| `src/members/members.service.spec.ts` | rewrite the `change_member_role` / `remove_member` RPC assertions; `getMember` exact key set; add platform-admin caller, disabled caller, disabled co-admin, re-parent fallback, depth, cycle, admin target, disabled target, promotion-clears-pointer, post-lock re-check order, list/listPaged hierarchy merge |
| `src/members/members.controller.spec.ts` | `REQUIRED` map gains `setManager: ['member.manager']` |
| `src/auth/auth.service.spec.ts` | invite response stays `{invite_id, employee_code, sms_status}` (`toEqual`); add admin+manager, removed manager, self-manager rows |
| permission spec (`job-role-grants.spec.ts` pattern) | `PLATFORM_ADMIN` does **not** hold `member.manager` |

## Out of scope

Dropping `remove_member` / `change_member_role` (they stay, unused), subtree visibility, routing, UI, notifications.
