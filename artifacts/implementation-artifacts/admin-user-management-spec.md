# Spec: Admin user management (staff-only) — search by phone, remove/purge people and companies

Status: parked 2026-10-26 — the day-to-day need (QA cleanup) is covered by the owner-only super CLI (fenzit-be/scripts/super.tsx); this spec revives when fenzit staff need search/purge in production. Product decisions confirmed by the product owner (2026-10-26).
Repos: `fenzit-be` (backend first), `fenzit-web` (website)
Date: 2026-10-26
Depends on: `roles-and-access-spec.md` (roles, memberships, permissions, audit log). This spec follows its decisions and adds to them.

## Goal

A fenzit staff member (the `platform_admin` flag, never a company membership) opens the web admin page and sees a left panel with "User Management". On the right, they type a phone number and search. An exact match resolves to any user — company owner or technician — and lays out that person's company roster: the owner's details first, then every technician's details. Each row carries two actions: **Remove** (soft, reversible) and **Delete** (hard, destructive). Removing an owner removes all their technicians the same soft way. Hard-deleting an owner wipes the whole company — its jobs, customers, attendance history, memberships, people and audit rows.

## Decisions already made (product owner, 2026-10-26)

1. **A new API is required.** Nothing today searches users by phone, shows staff a company roster, or purges a company. Existing pieces are reused (permissions guard, `user.disable` permission pattern, `X-Company-Id` validation, platform-audit interceptor), but the endpoints are new. The roles spec already anticipated unbuilt staff endpoints ("the staff create-and-list-companies endpoints are not built yet").
2. **Search finds owners and technicians.** Any user of any company resolves; searching a technician's number shows the same roster view. "Customer" means the company owner (Fenzit's business customer). Job customers (the `customers` table) are out of scope.
3. **Exact phone match.** The entered number is normalised and matched in full (country code + number). Phone is globally unique (`users_phone_key`), so the result is one person and their company roster.
4. **Two delete actions, soft and hard.** Soft remove = disable the account + mark live memberships `removed` (existing states; reversible via staff enable + re-invite; all jobs/attendance/audit history intact — roles spec decision 32). Hard delete = physically purge rows and the login identity.
5. **Owner delete cascades.** Soft-removing an owner soft-removes every technician of the company too. Hard-deleting an owner wipes the whole company: tenant row, jobs, customers, attendance and leave history, memberships, the people (and their login identities), and that company's audit-log rows.
6. **Audit rows are left untouched** (product owner revised the earlier "purge them too" on 2026-10-26). A hard purge never writes to `audit_log` — no row is added, changed or deleted by the purge. The purge's own record is the interceptor's existing post-write row (actor-scoped, tenant NULL — `platform-audit.interceptor.ts`). To make this possible, the three RESTRICT foreign keys on `audit_log` (`actor_user_id`, `tenant_id`, `target_user_id`) are dropped, superseding the roles-spec decision that held them: audit rows keep their historical UUIDs as plain data, outliving the purged people and company they point at. The append-only trigger, the indexes and the RLS lockdown stay exactly as they are.

## What exists and is reused

- `@Can()` permission guard, `Permission` union, `ROLE_PERMISSIONS`, `PLATFORM_WIDE_PERMISSIONS` (staff permissions that need no company).
- `users.disabled` (refused at login with a generic 401) and membership `status = 'removed'` (former members get "no access", never company setup) — the soft states already work end to end.
- `remove_member` / `invite_member` RPC patterns (in-database audit, reactivation keeps employee code and history).
- The platform-audit interceptor: every staff write is logged after success.
- The web `/admin` route with its loader (`canOpenAdmin`: `platformAdmin` or `company_admin`), the login/session service, `apiFetch`, design-system components.

## Backend (`fenzit-be`) — ships first

- **New permission** `user.manage`: staff-only. Added to the `Permission` union and granted only to `PLATFORM_ADMIN`; listed in `PLATFORM_WIDE_PERMISSIONS` (no company membership needed).
- **`GET /admin/users/lookup?phone=…`** (`user.manage`): normalises and matches `(country_code, phone_number)` exactly. 404 when no person has the number. Returns the person (id, name, phone, role: owner/technician/staff/none, disabled, membership status) plus, when they belong to a company, the company summary (id, name, state, created at) and the full roster: owner first, then technicians — id, name, phone, employee code, membership status, disabled.
- **`POST /admin/users/:userId/remove`** (`user.manage`, soft): disables the account and marks live memberships `removed`, via a new staff RPC following the `remove_member` pattern (service-role client, explicit tenant, in-DB audit row). On the owner of a company, it soft-removes every active member of that company in the same transaction. Refuses the staff actor's own account. No LAST_ADMIN guard — staff is deliberately overriding, and the action is audited.
- **`DELETE /admin/users/:userId`** (`user.manage`, hard): physically purges the person and their login identity (auth admin delete) plus audit rows that reference them. Refused with 409 `USER_HAS_JOBS` when any job still references them — staff wipes the company instead (this is the one case hard-delete refuses; decide-able again at review). Refuses staff actors and platform admins.
- **`DELETE /admin/companies/:tenantId`** (`user.manage`, hard): the owner/company wipe. One SECURITY DEFINER RPC `staff_purge_company(uuid)` that purges in dependency order — job children, jobs, customers, attendance and leave tables, notifications, idempotency log, employee sequences, tenant skills, memberships, the company's users, the tenant row — and returns the purged user ids so the endpoint deletes each auth identity. `audit_log` is never touched (decision 6). The append-only audit trigger needs no change.
- **The purge's own audit record** is the interceptor's post-write row, written with `tenant_id` NULL (a staff actor has no company), so it succeeds against the already-deleted tenant and survives the wipe.
- **Hard delete is refused for staff accounts** in every path; a staff identity is never purgeable through this feature.
- Swagger operation summaries, `error_code` envelope, and the platform-audit interceptor apply as everywhere else.

## Web (`fenzit-web`) — ships after the backend deploys

- **`/admin` becomes a two-pane layout.** Left panel navigation: "User Management" for staff. A company admin still opens `/admin` and sees the existing placeholder (their tools come later); only a `platformAdmin` response from `GET /users/me` renders the staff pane.
- **Right pane — search:** country code + number input, exact match, explicit empty state ("No person with this number"), loading and error states per house rules.
- **Right pane — roster:** company card (name, id, created) above the roster list — owner row first, technician rows after, each showing name, phone, employee code, status badge (invited/active/removed) and a disabled badge.
- **Row actions:** "Remove" (soft) and "Delete" (hard), each behind a confirm dialog that states the consequence — soft: "account disabled, history kept, reversible"; hard: "permanently deleted, cannot be undone". The owner row's hard action is labelled "Delete company" and its dialog names the company and everything that goes with it.
- After any action the roster is refetched; a purged company returns to the empty search state.

## Out of scope

- Job-customer (`customers` table) search and deletion.
- Partial/last-digits phone search; name search.
- Staff create-and-list-companies endpoints (roles spec backlog).
- Company admin tools in the left panel (placeholder stays).
- Any mobile-app change.
- Re-designing the audit log beyond the guarded purge bypass.

## Database impact

No new tables, columns or indexes. Three changes, all in migration files applied via Supabase MCP after approval:

1. **Drop the three foreign keys on `audit_log`** (`actor_user_id`, `tenant_id`, `target_user_id` → users/tenants, all `ON DELETE RESTRICT`). Audit rows are never written by the purge (decision 6), so the keys' only remaining effect would be blocking the wipe of purged people and their company. The columns, indexes, append-only trigger and RLS lockdown stay.
2. **New SECURITY DEFINER functions** `staff_remove_member(uuid)` (soft) and `staff_purge_company(uuid)` (hard wipe, dependency-ordered), revoked from public/anon/authenticated, granted to `service_role` — the `setup_tenant_for_owner` pattern. No new RLS policies: the endpoints run through the service-role client.
3. **Not schema but part of the DB work**: the purge endpoint deletes each purged person's auth identity via the Supabase admin API. Without it, the next OTP request from that phone mints a fresh `public.users` row (`auth.service.ts` first-login insert) and the person resurrects.

## Open items to confirm during plan/review

- Audit-log display niceness, not a regression: `GET /audit-log` reads `audit_log` with a flat select and no joins (`members.service.ts:139`), so rows about purged people/companies stay visible after a purge; they just show raw UUIDs. Resolving purged entities to "(deleted)" labels is optional polish for a later round.
- Where staff accounts appear in search results (spec assumption: staff and platform admins are returned by lookup with role "staff" but carry no company roster and no delete actions).

## Order of work

1. Spec approved by the product owner (this file).
2. `fenzit-be`: audit-trigger bypass migration, `user.manage` permission, staff RPCs, the three endpoints; local checks green. Migrations applied to the remote database only after approval.
3. `fenzit-be` deployed first (additive change; nothing existing breaks).
4. `fenzit-web`: admin layout, search, roster, actions. Local build and typecheck green.
5. User confirms the flow works locally (search → roster → soft remove → hard purge on a dummy company).
6. Tests written for both repos (tester mindset: cross-tenant leakage, disabled/removed login behaviour, purge completeness, guard-bypass reachability).
7. `/bmad-code-review` in each repo; commit only after consent; `fenzit-be` deploys before `fenzit-web`.
