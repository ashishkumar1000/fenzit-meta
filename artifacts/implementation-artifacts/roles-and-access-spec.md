# Spec: Roles and access (draft)

Status: approved. Steps 1 to 4 built and tested on Fenzit-dev only (not committed, live database untouched). 45 decisions recorded, no open questions.
Repos: `fenzit-be` (owns the rules), then `fenzit-web` and `fenzit-app` (follow the rules)
Date: 2026-10-20

Terms: "company" and "tenant" mean the same thing. Product text says company. Code and the database say tenant (`tenants`, `tenant_id`, `tenantId`).

## Roles

| Role | Scope | Who it is for |
|---|---|---|
| `platform_admin` | All companies | Fenzit staff. Can do anything, and every action is logged. |
| `company_admin` | One company | Runs a company. Replaces today's `owner`. |
| `employee` | One company | Field or office staff who do their own work. Replaces today's `technician`. Tracked for attendance. |
| `viewer` | One company | Read-only. Sees company data and changes nothing. |

## Membership model

- A user record holds identity only: phone, email, name.
- A `memberships` table links a user to a company with one role and a status (`invited`, `active`, `removed`). It also holds the employee code (decision 25). At launch a person has one membership (decisions 4 and 11). The table allows more, so this can be relaxed later.
- `platform_admin` is a flag on the user, not a membership in each company. It is set only by fenzit staff.
- No membership means no access to that company. Deny by default.
- The database holds no users or companies today (decision 12), so no data is converted. The migration creates the new structure only. In code and constraints, `owner` becomes `company_admin` and `technician` becomes `employee`.

### Invite, setup and login rules

- **Invite** (by phone): find the user by country code and phone. If none exists, create an identity-only user. If the user has a non-removed membership in any company, refuse with 409 `DUPLICATE_RESOURCE`. Otherwise create a membership with status `invited`. Two invites for the same phone at once end in the same 409 (the database unique-violation error 23505 is mapped to it).
- **Company setup:** refused with 409 for a user who already has an active membership. Otherwise it creates the company and a `company_admin` membership in one database transaction (decision 17).
- **Login:** finds the one user row for the phone. A first sign-in changes an `invited` membership to `active`. A user with no active membership (new, or only `removed`) gets a token and the "no company" state. They can reach company setup only.
- **After removal:** the next request from a removed member is refused with 403 `FORBIDDEN`. The apps treat it as signed out.

## Enforcement

- **Membership is read on every request.** The backend looks up the caller's active membership (company and role) and the `platform_admin` flag from the database on each request, never from the token. The login token carries identity only: user ID and the marker in decision 23. Token expiry stays as it is for now (decision 6). A removed member loses access on the next request.
- **Every backend query is filtered by company and membership.** The backend uses the service-role client in many places, which bypasses row-level security (RLS). Company isolation therefore comes from the application code. Every new endpoint must filter by company, and the review checks this. RLS policies are a second layer for direct client access, not the main protection.
- **Deny by default.** Every endpoint must declare the permission it needs (decision 20), or be marked public or open to any member on purpose. An endpoint with none of these is refused. Today's `RolesGuard` lets any signed-in user through when no role is declared, so this changes.
- **A `viewer` is refused on every write**, in the backend and in the database policies (decision 22). Hiding buttons in the app is not enough.
- **Shortcut logins are for development only** (decisions 9 and 30). They can sign in as any role, and during development they may set the `platform_admin` flag. They are removed before go-live, and that removal blocks the release.
- **Audit.** Platform admin changes to a company's data, and every role change, are written to the audit log (decisions 16 and 27).
- **Company admin limits** are in decisions 8 and 27.
- **Platform admin and a company** (proposed default for decision 13): the request names the company in an `X-Company-Id` header. The header is honoured only when the `platform_admin` flag is set, and the backend checks that the company exists. A platform admin's backend queries use the service-role client with an explicit company filter. RLS does not apply to them.
- **Impersonation** is out of scope for this build.

## Corrections from the review (2026-10-20)

Checked against fenzit-be and the live database (project `Fenzit-Be`, ap-south-1).

1. **Token:** the login token currently stores `role` and `tenantId` and has no expiry (`src/auth/auth.service.ts`, the `signAsync` calls). Change it to carry identity only, and read membership per request. Expiry stays as it is for now.
2. **Row-level security does not protect the backend.** The service-role client is used across the attendance, offices, holidays, weekly-offs, corrections and me-attendance services. Keep the company filter in every query.
3. **Role names are hardcoded in three places:** the database check on `users.role` (currently `owner`, `technician`), `APP_ROLES` in `src/common/guards/jwt-auth.guard.ts`, and the `Role` enum in `src/common/enums/role.enum.ts`. After decision 21 the database check moves to `memberships.role`, `APP_ROLES` is removed (decision 23), and the enum is renamed. The migration and code change together.
4. **The setup code still writes `owner`:** `src/auth/auth.service.ts` sets the role to `owner` in the company setup code (around lines 532 and 592). The database function `setup_tenant_for_owner` does not write a role value (checked against the live database). The service code must write `company_admin` after the migration. The function's name can stay.
5. **Advisor findings to fix in the same migration:**
   - Four database functions have a mutable search path: `leave_request_days_state_guard`, `setup_tenant_for_owner`, `update_updated_at_column`, `workflow_steps_valid`. Set a fixed search path on each.
   - 21 tables have row-level security enabled but no policies. This is safe for backend-only tables, and the spec keeps them that way. Checked 2026-10-20: neither `fenzit-app` nor `fenzit-web` reads any of the 21 tables directly. The app's realtime channel is a per-user topic, not table changes. The list is recorded for the review.
6. **Users read policy:** `users_read_own_or_null_tenant` lets any signed-in user read rows whose company is empty. Those rows include phone numbers. Tighten it so a user reads only their own row, plus rows in their own company.
7. **Endpoint coverage (checked 2026-10-20):** 86 handlers in total.
   - 65 declare a role on the method.
   - 10 rely on a class-level `@Roles(Role.OWNER)`: four in corrections and six in leave.
   - 7 are public: the two OTP endpoints, app config, country codes, early access, health, and the webhook. The webhook checks a shared secret.
   - 4 notifications endpoints are open to any signed-in user on purpose. Each filters by the caller's own user ID (verified).
   - Every endpoint declares its access today. The deny-by-default change (decision 10) affects only future endpoints.
8. **Some endpoints are technician-only today** (checked 2026-10-20): `POST /sync` and every `attendance/me/*` endpoint. `GET /auth/realtime-token` allows owner and technician only. The permission table must keep these working for `employee` (decision 29). Also technician-only today: all of `attendance/me/leave`, and job workflow and attachment uploads. An owner can list and read jobs but cannot advance them.

## Draft permission table

Each row is a capability. Yes means allowed; "own" means only the caller's own records; "no" means refused. Anything not listed in this table is refused.

| Capability | platform_admin | company_admin | employee | viewer |
|---|---|---|---|---|
| Create and manage companies | yes | no | no | no |
| Create own company at first sign-up (`company.create_own`, only for a signed-in person with no membership, once) | no | no | no | no |
| Manage company settings | yes | yes | no | no |
| Invite users and change their roles | yes | yes | no | no |
| View all jobs, customers and reports in the company | yes | yes | no | yes |
| Create and change jobs | yes | yes | no | no |
| View own assigned jobs | no | no | yes (own) | no |
| Advance own assigned jobs (workflow steps and attachments) | no | no | yes (own) | no |
| Manage attendance for all employees | yes | yes | no | no |
| View attendance for all employees | yes | yes | no | yes |
| Mark own attendance and see own record | no | no | yes (own) | no |
| Apply for leave | no | no | yes (own) | no |
| View all leave requests in the company | yes | yes | no (own only) | no |
| Approve or reject leave | yes | yes | no | no |
| Create leave on behalf of an employee | yes | yes | no | no |
| View and edit own profile and skills | yes | yes | yes (own) | yes (own) |
| View customers | yes | yes | yes (read only; sync needs the rows) | yes |
| Create and change customers | yes | yes | no | no |
| View reports | yes | yes | no | yes |
| Request and retry reports (decision 39) | yes | yes | no | yes |
| Manage offices, holidays and weekly offs | yes | yes | no | no |
| Manage attendance device enrolment | yes | yes | no | no |
| Read skills and country codes | yes | yes | yes | yes |
| Search places (Google) | yes | yes | no | no |
| Change skills, places and country codes | yes | no | no | no |
| Sync own jobs to the app | no | no | yes (own) | no |
| Notifications (own) | yes | yes | yes (own) | yes (own) |
| Get a realtime token | yes | yes | yes | yes |
| Webhooks and app config changes (the storage webhook stays public and secret-checked; no admin tool today) | none today | no | no | no |
| Read the audit log | yes (all) | yes (own company) | no | no |

Audit log access: see decision 16. Step 0 of the work (decision 21) checks every endpoint against these rows and lists any that do not fit.

## Approved decisions (2026-10-20)

1. `employee` is the same as today's technician. It covers field work and attendance.
2. `company_admin` is basically today's owner, with the same powers.
3. `viewer` can see customer phone numbers.
4. At launch, each person belongs to one company only. The membership table still allows more, so this can be relaxed later.
5. A user with no membership has no access to any company's data.
6. Token expiry stays as it is for now. Membership and the platform admin flag are still read on every request.
7. Role names change in one release: `owner` becomes `company_admin`, and `technician` becomes `employee`. The apps are not live, so the three-step rollout is not needed. This is a pre-launch exception to the three-step rule in `CLAUDE.md`.
8. Company admin limits: a company admin sets `company_admin`, `employee` or `viewer` only inside their own company. A company admin can never set the `platform_admin` flag, and the API does not allow it. A company admin cannot change memberships in any other company.
9. The shortcut logins (fixed email password and master OTP `1039`) can sign in as any role during development. They are removed before go-live.
10. Deny by default is enforced in code. An endpoint with none of `@Can`, `@Public` or `@AnyMember` is refused (`@Can` replaces `@Roles`, decision 20). Endpoints open to any signed-in member, such as the notifications endpoints, declare `@AnyMember()` and filter by the caller's own user ID. `@AnyMember()` means any signed-in user, with or without a membership, because company setup, `GET /users/me` and email linking are used before a user has a company.
11. At launch the database allows one membership per user (unique on user). This constraint is dropped when the one-company rule is relaxed. It ignores `removed` rows (decision 32).
12. The database change ships in the same release as the backend, with no separate migration step, since there is no live data. Order: backend (with database change), then apps.
13. A platform admin's request names the company it acts on. Without a name, the request covers platform-wide actions only, such as creating a company. Every platform admin change to a company's data is written to the audit log. The mechanism is in Enforcement.
14. A viewer can read attendance for all employees, read-only. An employee sees only their own attendance.
15. The permission table lists customers, reports, company setup data, device enrolment, reference data and platform-only settings.
16. The audit log is a new append-only table, `audit_log`. Each row holds who, what, which company and when. A row is written in the same database transaction as the change, so a change cannot happen without its row (how this is done: decision 31). Platform admins read all rows. A company admin reads only their own company's rows. No one can edit or delete a row.
17. Membership timing. An invite creates a membership with status `invited`, which becomes `active` on the person's first sign-in. Company setup creates a `company_admin` membership in the same transaction as the company. A company created by a platform admin gets its first `company_admin` by invite. A removed member keeps a row with status `removed`.
18. The website admin page opens for `company_admin` and `platform_admin`. `employee` and `viewer` see the "You do not have permission" message.
19. Superseded by decision 21, which removes `users.role` and `users.tenant_id` and lists the full work.
20. Endpoints check permissions, not role names. Each endpoint declares a permission such as `@Can('leave.approve')`. One map in code lists the permissions each role holds, so a new role is one change in that map. The map is a typed constant in the backend, reviewed like any code, not a database table, because custom roles per company are out of scope. Permission names follow `resource.action`. This replaces `@Roles(...)` on all 86 handlers in this release. `@Public()` and `@AnyMember()` stay. An endpoint with none of the three is refused (decision 10). Web and app screens use the same permission names, taken from the permission table.
21. `users.tenant_id`, `users.role` and `users.status` are dropped. A user record holds identity only. This is larger than first described. Objects that use these columns:
    - Database: 11 functions (including `setup_tenant_for_owner`, `advance_workflow_step` and the `attendance_*` functions), the `attendance_access_state` view, the `users_set_employee_code` trigger, the unique indexes `users_phone_per_tenant_unique`, `users_phone_no_tenant_unique`, `users_tenant_employee_code_unique` and `users_id_tenant_id_key`, the index `idx_users_tenant_id`, and the policies on `users` and `user_skills`.
    - Backend: 19 `from('users')` queries in 7 files, about 65 files that read `tenantId`, and 5 files that read `employee_code` (`leave.repository.ts`, `leave-read.service.ts`, `users.service.ts`, and the reports `attendance.data.ts` and `technician-job-activity.data.ts`).
    - Fifteen foreign keys on attendance and leave tables point at `users(id, tenant_id)` with `ON DELETE RESTRICT` (checked 2026-10-20): `attendance_weekly_off_overrides`, `attendance_enrolments`, `attendance_office_assignments`, `attendance_onboarding`, `attendance_attempts`, `attendance_records`, `attendance_day_overrides` (two), `attendance_corrections` (two), `leave_requests` (two), `leave_request_days` and `leave_events` (two). They keep an employee's records inside one company.
    - The `attendance_access_state` view tests `u.role = 'owner'` for the pending-leave count and reads `u.tenant_id` throughout. The `owner` literal becomes `company_admin`.
    - Changes that follow: phone becomes unique across the whole table (one identity per number). `memberships` gets a unique key on (user, company), and the fifteen foreign keys point at it instead, keeping `ON DELETE RESTRICT`. Memberships are never deleted (decision 32), so history stays valid. The employee-code trigger takes the company from the membership. The functions and the view read `memberships`.
    The order of work is under "Order of work".
22. Row-level security policies look up the caller's company and role from `memberships` through two shared database helpers, `current_company_id()` and `current_member_role()`, not from a token claim. Each helper reads `sub` from the token, is `stable`, has a fixed search path, and counts only memberships with status `active`. Policies call them once per query, as `(select current_company_id())`. `memberships` has an index on `user_id`. Policies for write actions also check the role, so a viewer cannot write through the database. The login token carries identity only. This covers the `sync` endpoint, which queries with the user's own token. A removed or changed membership takes effect on the next request in both the REST API and row-level security.
23. Every login token carries a marker, `typ: 'access'`, and the guard accepts a token only if it has that marker. Today the guard refuses realtime tokens and the Supabase service-role key only because their `role` claim is not `owner` or `technician` (`src/common/guards/jwt-auth.guard.ts`, `APP_ROLES`). Decision 22 removes the role claim from login tokens, so the marker replaces that check. Realtime tokens (`role: 'authenticated'`) and the service-role key have no marker and stay refused. Tokens issued before this release stop working once, which is fine because the product is not live and the users table is empty. `APP_ROLES` is removed.
24. `invited` lives only on `memberships.status` (`invited`, `active`, `removed`). We invite by phone number and sign in by OTP, so there is no emailed link or token, and a separate invitations table adds nothing. A separate invitations table with token and expiry is the common choice for emailed links ([Makerkit](https://makerkit.dev/docs/tanstack-supabase/development/database-architecture)), so revisit it if invites move to email links.
25. The employee code lives on `memberships`, unique per company (`company` plus `employee_code`). Every membership gets a code, as every user with a company does today (owners included). A person who joins a second company later keeps one login and gets a separate code there. Per-company attributes sit on the membership and the user record stays identity only ([Scalekit](https://docs.scalekit.com/fsa/data-modelling/), [FlightControl](https://flightcontrol.dev/blog/ultimate-guide-to-multi-tenant-saas-data-modeling), [Stytch](https://www.stytch.com/docs/b2b/guides/multi-tenancy)).
26. A `viewer` cannot read other people's leave requests. A viewer still reads attendance for all employees (decision 14). Leave can carry medical reasons, and the usual read-only role in HR products hides time-off requests ([Sage HR](https://support.sage.hr/en/articles/8295074-read-only-manager)). Giving a viewer leave access later is one permission change (decision 20).
27. No one can change their own role or remove themselves, including a company admin, and a company must always keep at least one active `company_admin`. The check runs on the server in the same transaction as the change. It locks the company's memberships first, so two admins demoting each other at the same moment cannot both pass (a per-company lock pattern already exists as `attendance_lock_tenant`). A platform admin can change another admin's role under the same rule. Role changes are written to the audit log (decision 16). Denying self role changes is standard ([Neo4j docs](https://github.com/neo4j/docs-operations/pull/1440), [Port.io](https://roadmap.port.io/ideas/p/guardrail-restrict-userport-role-changes-to-admins-only)).

28. A separate permission, `company.create_own`, lets a signed-in person with no active membership set up their own company once (`POST /auth/company`). It is refused for anyone who already has an active membership, so no one creates a second company (decision 4). Setup creates the company and a `company_admin` membership in one transaction (decision 17). "Create and manage companies" stays platform-only for staff-created companies. `POST /auth/company` is a create-or-update today (idempotent upsert, owner-only, checked 2026-10-20). After this release it accepts either `company.create_own` (a person with no membership creates their company) or `company.manage` (a `company_admin` updates their own company's profile). `setup_tenant_for_owner` is rewritten to create the membership instead of setting `users.tenant_id`, and keeps its one-company-per-creator rule through a unique `created_by` (decision 33).

29. Sync and own attendance stay `employee` only, as today. `POST /sync` returns the caller's own jobs and is refused for every other role. Check-in, check-out, attendance summary and onboarding (`attendance/me/*`) are `employee` only. `company_admin`, `platform_admin` and `viewer` do not mark their own attendance. Letting an admin be tracked for attendance is a separate later feature, because it also affects the `attendance_access_state` view and the reports. It would be one change in the permission map (decision 20) plus those checks.

30. Shortcut logins (the fixed email password and the master OTP `1039`) may set the `platform_admin` flag during development, so every screen can be tested as a platform admin. This replaces the rule that only fenzit staff set the flag, for development only. The product owner accepted this risk (2026-10-20), because the product is not live and has no real data. A forgotten shortcut would give anyone who knows the code access to every company, so removing both shortcuts is a go-live gate: the release does not ship until they are gone, and the review for the release checks it. In the final product the flag is set only by fenzit staff through a controlled path, and a company admin can never set it (decision 8).

31. Changes that must happen together or not at all run as database functions, because the REST client cannot run several steps as one unit. Five functions are approved (the fifth, `set_user_disabled`, is in decision 35), each described in plain English before it is written. The backend checks the caller's permission first (decision 20). Each function then enforces the data rules itself, so a bug in the backend cannot bypass them. Each runs as one all-or-nothing step and writes its audit row in that same step.
    1. **`invite_member`** takes the company, the caller, the phone number, the name, the role and the skills. It refuses a role of `platform_admin`, and refuses a user who has the `platform_admin` flag (decision 34). It finds the user by phone, or creates an identity-only user if there is none. It refuses with a duplicate error if that person already has a membership that is not `removed`, in any company. It then creates the membership as `invited`, gives it an employee code (decision 25), and writes the audit row. A person with a `removed` membership in the same company is reactivated, not duplicated (decision 32).
    2. **`change_member_role`** takes the company, the caller, the member and the new role. It locks the company's memberships first. It refuses if the caller is changing their own role, if the new role is `platform_admin`, or if the change would leave the company without an active `company_admin`. Otherwise it updates the role and writes the audit row with the old and new role.
    3. **`remove_member`** takes the company, the caller and the member. It uses the same lock and the same two refusals (self, last admin). It sets the membership to `removed` and writes the audit row. The person's jobs, attendance and leave records are kept.
    4. **`write_audit_row`** is the shared step that records who, what, which company and when. A platform admin's change to a company's data calls it inside the function that makes the change. It refuses a caller without the `platform_admin` flag and a company that does not exist. If step 0 finds platform admin changes beyond member management (for example, company settings or offices), each needs a function that calls this step. Step 0 lists them for review before any is written.
    Company setup already works this way (`setup_tenant_for_owner`) and keeps that pattern. Each function gets a fixed search path (correction 5) and a comment block in plain English in the migration.

32. The one-membership rule ignores `removed` rows. It is a unique index on the user, applied only where the status is not `removed`. A person can have many `removed` rows over time as history, and at most one live (`invited` or `active`) membership. A re-invite to the same company reactivates the old row: it becomes `invited` again with the new role, and keeps its employee code and history, with no new row. An invite to a different company creates a new row, and the old `removed` row stays as history. Removal never deletes a row, so attendance, leave and audit records keep pointing at a real membership.

33. `tenants.owner_id` is renamed `created_by`. It records who set the company up, for history only, and nothing uses it for access. The `tenants_read_own` policy is replaced so a person reads a company row through their active membership (`current_company_id()`, decision 22). A removed admin therefore loses the company row even if they created it. Platform admins read company rows through the backend (decision 13). Step 0 lists every place that reads `owner_id` so the rename misses none. The API field `ownerId` in the company response (`auth.service.ts:506`) becomes `createdBy`, and `fenzit-app` changes with it in the same release. Today `owner_id` is also the recipient of fake-location alerts and owner-facing leave events, which decision 36 changes.

34. A user with the `platform_admin` flag cannot have a membership in any company. `invite_member` and company setup refuse a platform admin user. Setting the flag on a user who has a live (`invited` or `active`) membership is refused. A fenzit staff member who needs to see a customer's view uses a second, separate account. This keeps platform powers and company membership apart, and avoids unclear audit entries and last-admin edge cases. During development, a shortcut login (decision 30) can set the flag only on a user with no live membership. Allowing both later means removing this rule and defining which one applies on a request.

35. `users.disabled` is added, a true/false column that defaults to false. A disabled person is refused at login (phone OTP and email) with the same generic 401 the website spec describes, and on every request even if they hold a valid token. The guard reads it per request, together with the membership and the `platform_admin` flag (decision 6). Only a platform admin can disable or re-enable a user, and each change is written to the audit log. Because the change and its audit row must happen together, this is a fifth database function, `set_user_disabled`, built the same way as the four in decision 31 and described in plain English in the migration. It refuses a caller without the `platform_admin` flag, and it refuses to disable the caller's own account.

36. Admin alerts go to every active `company_admin` of the company, not to `created_by`. This covers fake-location alerts and owner-facing leave events, which today read `tenants.owner_id` (`check-in-out.repository.ts:238`, `leave.repository.ts:456`, `leave.service.ts:619`). The recipient list is read from `memberships` (role `company_admin`, status `active`) when the event happens. A removed admin stops getting alerts at once, and a new admin starts getting them. The three places change from finding one recipient to finding a list. Step 0 checks for any other code that reads `owner_id` as a recipient.

37. Employees read their own jobs. A row "View own assigned jobs" is added to the table (employee, own only). `GET /jobs` and `GET /jobs/:id` keep today's rule: an employee sees only jobs assigned to them.
38. Places search (the paid Google API: autosuggest, resolve, reverse) is for `company_admin` and `platform_admin` only, as today. The table row is split: skills and country codes are readable by all four roles, places search is admin-only.
39. A viewer may request and retry reports (`POST /reports`, `POST /reports/:id/retry`). It is the one written exception to "a viewer is refused every write" (decision 22), because a report is a read-only output. The row-level policy on `report_requests` allows the viewer's insert and nothing else.
40. `tenants.created_by` has no unique constraint, and its key is `ON DELETE RESTRICT` (not cascade), so deleting a user can never delete a company. This replaces the "unique `created_by`" in decisions 28 and 33. One company per person is enforced by the unique live membership (decision 32), and company setup refuses anyone who already has one. Company setup stays safe to repeat: a second call finds the caller's membership and updates that company. The redundant index `idx_tenants_owner_id` is dropped.
41. Viewers get only the read endpoints in attendance: dashboard, day statuses, monthly, enrolments list, offices list and detail, holidays list and impact, weekly-offs list and overrides list, corrections list, and setup status. Everything else in those controllers is a write and is admin-only, including `POST /attendance/attempts/acknowledge`. A new table row, "Create leave on behalf of an employee" (`POST /attendance/leave/on-behalf`), is allowed for `platform_admin` and `company_admin` only.
42. A platform admin's company writes are audited in the same step as the change. Database functions call the audit step inside the function. Writes that already use the backend's own transaction (enrolments, corrections, leave) call `write_audit_row` inside it. The plain `supabase-js` writes (customers, reports, two office writes, `auth/invite`) move into the backend's own transaction so they can do the same. No stored procedure is added for this beyond the five in decisions 31 and 35.
43. Order of work: the nine claim-reading policies move to the start of step 2. The backend first writes memberships on invite and company setup, then the policies are rewritten to the helpers, then the token becomes identity only. Run the sync test after each of these three changes, so sync (which queries with the user's own token) never reads an empty result.

44. Build notes for step 1 (decided 2026-10-20 while writing the migrations; these refine earlier wording):
    - The two RLS helpers live in a `private` schema, so the public API cannot call them as functions. They are granted to `authenticated` and `service_role` only, because policies run as the caller. They count only an active membership of a person who is not disabled.
    - `write_audit_row` accepts any actor, not only platform admins, because company role changes are audited too (decision 27). It still refuses a caller who is neither a platform admin nor an active member of the company named. This replaces "refuses a caller without the `platform_admin` flag" in decision 31, item 4. The row records whether the actor was acting as platform admin at that moment.
    - Decision 16's "no one can edit or delete a row" is enforced by one small trigger function, `audit_log_append_only`, which stops any update, delete or truncate. With it, the database holds six new functions in `public`: the five approved ones plus this guard.
    - `users.role` becomes nullable until step 4, so an invite can create an identity-only user without an old-style role.
    - Keys from `memberships` and `audit_log` to `users` and `tenants` are `ON DELETE RESTRICT`.
    - The "a platform admin cannot hold a membership" rule (decision 34) is enforced inside `invite_member`, in company setup, and in the backend. There is no extra trigger for it.
    - A new API error code, `LAST_ADMIN`, is raised when a change would leave a company without an active `company_admin`. The backend adds it in step 2.
    - A company admin can read their own company's `audit_log` rows through a row-level policy. Platform admins read through the backend.

45. Build notes for steps 2 to 4 (decided 2026-10-20 while writing the backend and the step 3 and 4 migrations; these refine earlier wording):
    - **One cutover on dev.** The new structure, the policy rewrite, the token change and the column drop were built and tested together on `Fenzit-dev` instead of three separate states. Reason: an identity-only invited user has no `users.tenant_id`, so the old functions could not run beside the new invite for long. Migration files: `20261020000003_roles_rewrite_to_memberships.sql` (step 3) and `20261020000004_roles_drop_old_user_columns.sql` (step 4).
    - **Existing members are copied.** Step 3 copies every user that has a company into `memberships` (owner to `company_admin`, technician to `employee`, same status, same employee code), so the same file is safe on the live database, which holds one company and two users.
    - **The guard reads the database per request** through a small injectable class, `MembershipResolver`, so tests can replace it. It returns the person's active membership and the `platform_admin` and `disabled` flags. Unknown or disabled gives the same generic 401. A person with no active membership gets `role: null` and reaches only `@AnyMember` endpoints and company setup.
    - **Platform admin and a company** (decision 13 default confirmed): the `X-Company-Id` header is honoured only for the `platform_admin` flag and must name a company that exists (else 404). Without it, a company-scoped endpoint answers 403. A company member's header is ignored.
    - **Permission map.** 24 permissions, one typed constant (`src/common/permissions/permissions.ts`). `GET /skills`, `GET /auth/realtime-token`, `GET/PATCH /users/me` and notifications are `@AnyMember`. `GET /jobs` and `GET /jobs/:id` accept `job.read_all` or `job.read_own` and the service filters an employee to their own jobs.
    - **Sync was already broken for a real login token.** PostgREST rejected the old token (`role "technician" does not exist`), and the mocked tests hid it. Sync now mints a one-minute `{ sub, role: 'authenticated', exp }` token per request, so row-level security applies for real, and a real-database test proves it.
    - **Row-level security** (all `to authenticated`): company tables read by any member, written by `company_admin` and `employee` (customers by `company_admin` only, report requests inserted by all three roles). `user_skills` and `users` use a third private helper, `private.user_in_my_company(uuid)`, because a policy runs as the caller, who cannot read `memberships`. The `users` read policy no longer exposes rows with no company.
    - **`tenants.created_by`** keeps one non-unique index (`idx_tenants_created_by`) for the foreign key; the unique index is gone (decision 40).
    - **`setup_tenant_for_owner`** now takes a row lock on the user, refuses a platform admin or disabled user (403), refuses a person who is an employee, viewer or only invited elsewhere (409), updates the company when its own active admin calls again, and otherwise creates the company and the `company_admin` membership together. The employee code comes from a `BEFORE INSERT` trigger on `memberships` (the old trigger on `users` is gone).
    - **Alerts to every active admin.** `advance_workflow_step`, `attendance_run_reminders` (pending-leave and office-summary arms), the fake-location alert and the leave events that notify admins now loop over the active `company_admin` members. A new helper, `readCompanyAdminIds`, replaced the two `readOwnerId` copies.
    - **New endpoints.** `GET /members`, `PATCH /members/:userId/role`, `DELETE /members/:userId`, `POST /admin/users/:userId/disable|enable` and `GET /audit-log`, each backed by the step 1 functions. The staff create-and-list-companies endpoints are not built yet.
    - **`POST /auth/invite`** keeps its path, accepts an optional `role` (default `employee`; skills required only for an employee) and returns `{ invite_id, employee_code }`. `ownerId` in the company response is now `createdBy`. `GET /users/me` returns the same two shapes (company-wide and employee) with `role` renamed, plus `platformAdmin`; its roster field keeps the name `technicians`.
    - **Test data and audit rows.** `audit_log` rows are permanent and keep their user and company alive, so a test that writes audit rows leaves that user and company behind in the dev database. Tests that only seed rows clean up normally (memberships, then tenants, then users).

46. Code review corrections (decided 2026-10-20, take-your-best-decision):
    - **Customers are readable by every member** (employee included), because device sync needs the rows. Only company admins write them.
    - **Removal and the next request:** a removed member gets 403 on every permission-guarded route. They keep `@AnyMember` routes (notifications, `users/me`, realtime token), as decision 45 says.
    - **Activity log is append-only.** Members can add rows; nobody edits or deletes them.
    - **Platform-admin writes are audited by one backend interceptor** (row after a successful POST, PUT, PATCH or DELETE, with method and route). This replaces the "same step as the change" wording in decision 42 for writes that do not go through a member function. It is not in the same transaction as the write, so a failed audit insert is logged, not rolled back. Member functions still audit inside the database. A platform admin's member action may therefore show two rows.
    - **Platform admin and company profile:** `POST /auth/company` with `X-Company-Id` updates the named company (only the fields sent). It never creates one.
    - **"Who did it" columns** on leave requests, leave events, attendance corrections and day overrides point at `users(id)`, so a platform admin (who has no membership) can act. Employee columns still point at `memberships`.
    - **Repeat company setup** keeps any optional field (GSTIN, address, UPI) that is not sent.
    - **Reminders and the office summary** include only active, not-disabled members.
    - **Email shortcut login** signs in an existing user only. Setting an email or the platform-admin flag on a user is done by SQL on dev. It is removed at the go-live gate with the master OTP.

## Open questions

None outstanding. The seven questions from the step 0 inventory were answered on 2026-10-20 (decisions 37 to 43).

## Order of work after approval

All steps ship as one release (decision 7). Backend deploys first, then the apps. Run the real-database attendance journey suite after every backend step.

0. **Inventory (read-only): done 2026-10-20.** Result is in "Step 0 inventory" at the end of this file; its questions are decisions 37 to 43.
1. **Backend, new structure:** `memberships`, `audit_log`, the `platform_admin` flag, the helpers `current_company_id()` and `current_member_role()`, `users.disabled` (decision 35), and the database functions in decisions 31 and 35. Local tests only.
2. **Backend, code:** in this order, (a) invite and company setup write memberships, (b) rewrite the nine claim-reading policies to the helpers (decision 43), (c) token change (identity only, with the marker), membership read per request, the role-to-permission map and `@Can` on all 86 handlers, deny-by-default guard, company filter on every query, new role names, invite and setup rules.
3. **Backend, database rewrite:** functions, the view, keys, the employee-code trigger, phone uniqueness and the remaining policies use `memberships`. Function search-path fixes and the users read policy (correction 6).
4. **Backend, drop the old columns** (`users.role`, `users.tenant_id`, `users.status`), their indexes and the old check constraint, only after steps 2 and 3 pass locally. Then run the backend tests, the Supabase advisors, and a cross-company isolation test (company A cannot read company B on any endpoint).
5. **Backend, notifications:** verify the notifications endpoints declare `@AnyMember()` and filter by the caller's own user ID.
6. **Apps:** `fenzit-app` screens check `company_admin` and `employee` instead of `owner` and `technician`, and read `createdBy` instead of `ownerId`.
7. **Website:** the login and admin pages from `web-login-and-owner-admin-spec.md` use the new names.
8. **Tests, `/bmad-code-review` in each repo, and commit only after consent.**
9. **Go-live gate (before any production release):** remove the fixed email password and the master OTP `1039` (decisions 9 and 30), and confirm no code path outside fenzit staff tooling sets `platform_admin`.

## Step 0 inventory (2026-10-20)

Read-only. Taken from `Fenzit-dev` (a verified copy of the live schema) and the `fenzit-be` code on main. Nothing was changed. Counts below replace the estimates in decision 21 where they differ.

### 1. Database: functions (31 in `public`)

- **Read `users.tenant_id` (or join `users` for the company check): 10.** `attendance_add_holiday`, `attendance_complete_setup`, `attendance_enrolment_coverage_guard`, `attendance_holiday_impact`, `attendance_office_archive_blockers`, `attendance_remove_holiday`, `attendance_remove_weekly_off_override`, `attendance_set_weekly_off_override`, `set_employee_code` (trigger), `setup_tenant_for_owner` (also writes `users`).
- **Read `tenants.owner_id` as the alert recipient: 2.** `advance_workflow_step` (notifies the owner when someone else moves a job) and `attendance_run_reminders` (the pending-leave reminder every 5 minutes, and the weekly-off reminder). Decision 36 named only the three TypeScript places. **These two database functions are new findings and must also send to every active `company_admin`.** `setup_tenant_for_owner` also writes `owner_id`.
- Total to rewrite: 12 functions (decision 21 said 11).
- The other 19 functions do not touch the old columns. Several carry a `tenant_id` parameter or read `jobs.tenant_id`, which is unaffected.

### 2. Database: policies (16), view, trigger, indexes

- **Policies that read the `tenantId` token claim: 9.** `activity_logs`, `attachment_uploads`, `attachments`, `customers`, `idempotency_log`, `jobs`, `report_requests` (each `*_tenant_isolation`, all commands), `user_skills_tenant_isolation` (claim and `users.tenant_id`), `users_read_own_or_null_tenant` (claim and `users.tenant_id`). All nine move to `current_company_id()` (decision 22).
- **Reads `owner_id`: 1.** `tenants_read_own`.
- **Not affected: 6.** `country_codes_public_read`, `skills_authenticated_read`, `workflow_templates_authenticated_read`, `notifications_read_own`, `users_insert_only_service_role`, `users_update_own` (they use `sub` only). The `realtime.messages` policy also uses `sub` only.
- **View `attendance_access_state`:** reads `u.tenant_id` throughout, filters `where u.tenant_id is not null`, and tests `u.role = 'owner'` for the pending-leave count.
- **Trigger `users_set_employee_code`** (before insert or update on `users`) calls `set_employee_code()`, which reads `NEW.tenant_id` and builds `EMP-001`.
- **On `users`:** `users_id_tenant_id_key` (unique), `users_tenant_employee_code_unique` (constraint and index), `users_phone_per_tenant_unique`, `users_phone_no_tenant_unique`, `idx_users_tenant_id`, `users_tenant_id_fkey`, `users_role_check`, `users_status_check`.
- **On `tenants`:** `tenants_owner_id_fkey` (`ON DELETE CASCADE`), `tenants_owner_id_key` (unique), and `idx_tenants_owner_id`, which duplicates the unique index and can simply be dropped.

### 3. Database: foreign keys

- **The 15 composite keys in decision 21: confirmed, exactly 15**, all `ON DELETE RESTRICT`, all to `users(id, tenant_id)`. The list in decision 21 is correct.
- **Five single-column keys to `users(id)` are not affected:** `activity_logs.actor_id`, `jobs.technician_id`, `notifications.user_id`, `report_requests.requested_by`, `user_skills.user_id`. Note `jobs.technician_id` has no company check in the database. Today the backend checks it. After this work, "the assignee is an active employee of the same company" stays a backend check unless you want it added to the database later.

### 4. Backend: roles and guards

- 86 handlers: **7 public** (`config/app`, `country-codes`, `health`, `early-access`, `internal/webhooks/storage`, `auth/otp/send`, `auth/otp/verify`) and **79 signed-in**.
- Of the 79: **52 owner-only, 17 technician-only, 6 for both** (`GET /auth/realtime-token`, `GET /jobs`, `GET /jobs/:id`, `GET /skills`, `GET /users/me`, `PATCH /users/me`) and **4 with no role declared** (all of `notifications`, which `RolesGuard` lets through today).
- Files: `common/enums/role.enum.ts`, `common/guards/jwt-auth.guard.ts` (`APP_ROLES` line 32, claim check line 80, request user built at 89 to 90), `common/guards/roles.guard.ts`.
- Code that branches on the role: `auth.service.ts` (lines 299 to 332 login and activating an invite, 369 to 429 invite, 534 to 535 company setup, 550 to 607 find or create), `users.service.ts` (289 to 302, 343 to 397: `GET /users/me` returns a different shape per role; 441), `jobs.service.ts` (637, 672, 768: technicians see only their own jobs), `reports.service.ts:403` (lists technicians).

### 5. Backend: readers of the old columns

- **`.from('users')`: 19 queries in 7 files** (`auth.service.ts` 8, `users.service.ts` 4, `jobs.service.ts` 3, `weekly-offs.repository.ts`, `enrolments.service.ts`, `reports.service.ts`, `reports/registry/technician-job-activity.data.ts`). Matches decision 21.
- **Raw SQL on `public.users`: 9 places in 6 files** (not counted in decision 21). Three read the old columns: `enrolments.repository.ts:55` (`tenant_id`), `leave.repository.ts:416` (`tenant_id` and `role = 'technician'`) and `leave.repository.ts:475` (`tenant_id`). The other six (`monthly.ts`, `dashboard-flags.ts` twice, `corrections.repository.ts`, `leave.repository.ts:547`, `common/day-status/grid-reader.ts`) join `users` to get names. I did not open each join, so confirm at build time that none reads a dropped column.
- **`tenantId` from the request user: 140 uses in 29 non-test files.** Decision 21's "about 65 files" counted test files too.
- **`employee_code`: 8 non-test files**, not 5: `leave-read.service.ts`, `leave.repository.ts`, `leave.model.ts`, `users.service.ts`, `reports/registry/attendance.data.ts`, `attendance.template.ts`, `technician-job-activity.data.ts` and `technician-job-activity.template.ts`. The extra three only carry the field through.
- **`owner_id` readers (decision 36):** `readOwnerId` exists as two copies, `check-in-out.repository.ts:238-247` and `leave.repository.ts:456-465`. Callers: `check-in-out.leave.ts:42`, `check-in-out.rejections.ts:125`, `leave.service.ts:625`. `check-in-out.repository.ts:208-226` writes `ownerId` into the alert row. The API field `ownerId` is at `auth.service.ts:31` and `:506`. Both copies become one helper that returns a list.
- **Sync uses the user's own token:** `sync.service.ts:36` builds a client from `user.rawJwt` and reads `jobs`, `customers` and `attachments`. This is the only place RLS protects a backend read, which is why open question 7 matters.

### 6. Endpoints against the permission table

- **Fit the table as is: 56 of the 79 signed-in handlers.** This includes the 17 technician-only handlers (own attendance, own leave, own corrections and day statuses, workflow and attachment steps, sync), jobs create and change, customers, offices, holidays, weekly offs and enrolments writes, setup writes, leave approve, reject and revoke, company, invite, notifications, realtime token, skills and `users/me`. The 7 public handlers are outside the table.
- **Do not fit, and are listed in the open questions: 23.** Places (3, question 2), `GET /jobs` and `GET /jobs/:id` for employees (2, question 1), reports (4, question 3), and 14 in attendance (question 5): the 12 reads a viewer should get (dashboard, day statuses, monthly, enrolments list, offices list and detail, holidays list and impact, weekly offs list and overrides list, corrections list, setup status) and the 2 writes that need an explicit row (`attempts/acknowledge`, `leave/on-behalf`).
- **In the table but with no endpoint today (new work, not in the 86):** list members, change a role, remove a member, disable or enable a user, read the audit log, and staff create and list companies. Decisions 31 and 35 cover the first four through database functions; the audit read and the staff company endpoints need handlers.
- **`POST /internal/webhooks/storage`** is public today and is called by Supabase with its own secret. The table's "Webhooks and app config changes: platform_admin" row has no matching admin tool. Recommend the webhook stays public with its secret and the row is reworded to "none today".

### 7. Platform admin writes that need an audit row

About 30 write handlers are reachable by a platform admin (every "yes" row for `platform_admin` that is a write). They write three ways:

| How it writes | Handlers | Audit in the same step |
|---|---|---|
| **Database function** (`attendance_*`, `create_job_with_log`, `update_job_with_log`, `setup_tenant_for_owner`) | attendance setup (3), offices (3), holidays (3), weekly offs (3), jobs create and change (2), company (1) | Call the audit step inside the function. |
| **Backend database transaction** (`pg` pool) | enrolments (3), corrections (3), leave approve, reject, revoke, on-behalf (4) | Call `write_audit_row` inside the same transaction. No new function. |
| **Plain `supabase-js` insert or update** | customers (2), reports (2), two office writes, `auth/invite` | Cannot share a transaction with the audit row. Move to the backend transaction (open question 6). |

### 8. Net effect on the plan

- Scope grows slightly beyond the spec: 12 functions (not 11), the two alert-recipient database functions, nine claim-reading policies that sync depends on, the raw SQL readers, and about 30 audited write paths.
- Order of work changed as decided: the nine policies are rewritten before the token change (decision 43).
- The seven questions were answered on 2026-10-20 and are recorded as decisions 37 to 43. The permission table and the order of work are updated to match. No question is open.
