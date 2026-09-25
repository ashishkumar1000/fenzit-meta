# Rubric Review — Architecture Spine: Attendance & Leave

- **Spine:** `ARCHITECTURE-SPINE.md` (draft, 2026-09-25)
- **Reviewer role:** rubric walker (good-spine checklist)
- **Evidence base:** PRD `prd-Fenzo-attendance-2026-09-25/prd.md`; fenzit-be `project-context.md`, `docs/architecture.md`, `render.yaml`, `src/common/**`, `src/auth/**`, `src/notifications/**`, `src/users/users.controller.ts`, `src/telemetry/app-metrics.ts`, `supabase/migrations/**`; fenzo-app `package.json`, `src/features/notifications/**`, `src/features/technicianApp/geolocation.ts`, `src/services/**`, installed `react-native-nitro-geolocation`; npm registry (2026-09-25); `deferred-work.md`.

## Verdict

**Pass with required fixes.** The spine is strong: it fixes most real divergence points (time model, day-status engine, locking, RPC shape, notification contract) and it matches the brownfield code closely. But a few Rules can't be enforced as written or leave gaps that two stories would fill in different ways (idempotency of rejected attempts, rate-limit counting, access-state refetch, derived leave status, timezone CHECK). Fix the HIGH and MEDIUM items before epics are cut.

## 1. Brownfield claim verification

| Claim in spine | Finding | Status |
| --- | --- | --- |
| `createAdmin().rpc()` is the write path | `admin.rpc(...)` used in `jobs.service.ts`, `workflow.service.ts`, `auth.service.ts`, `attachments.service.ts`, `webhooks.service.ts` | Verified |
| Grant pattern from migration `20260920000005` | `claim_report_request` revokes EXECUTE from `public`, `anon`, `authenticated`; `SECURITY DEFINER`, `set search_path to 'public'` | Verified |
| RLS claim style `auth.jwt() ->> 'tenantId'` / `->> 'sub'` | Used across users, customers, jobs, attachments, report_requests, notifications migrations | Verified (see F-4 for a role gap) |
| `PTxxx` SQLSTATE convention (PT409, PT422) | `jobs.service.ts` maps PT409/PT422; `reports.service.ts` uses PT429 | Verified |
| `GlobalExceptionFilter` envelope `{ statusCode, error_code, message, ...extra }` | Matches. Note: `retryAfterSeconds` is **stripped from the body and moved to a `Retry-After` header** (see F-6) | Verified with caveat |
| `PaginatedResponse { data, nextCursor, hasMore }` | `src/common/dto/paginated-response.dto.ts` matches | Verified |
| New `CursorScope` values | `CursorScope` is a string union in `src/common/utils/cursor.util.ts`; payload is `(id, createdAt)` keyset | Verified |
| OTel counter through `AppMetrics` | `AppMetrics` today has **only** `httpDuration` + `recordHttpRequest`; no counter exists. Needs an interface extension (see F-8) | Partly true |
| pg_cron unschedule-then-schedule pattern | `20260909000004_notifications_cleanup.sql`, `20260621000012_*` | Verified |
| `IdempotencyInterceptor` behaviour | Opt-in per route, key optional, 24 h window, best-effort insert after success (racy) — spine's decision not to reuse it is sound | Verified |
| `/users/me` exists | `GET /users/me` (owner + technician), heavy role-branched payload incl. jobs page + jobCounts | Verified (see F-2) |
| `notifications` columns | `id, tenant_id, user_id, job_id (nullable since 20260920000008), event_type, payload, read_at, pushed_at, created_at`; sub-based SELECT policy; broadcast trigger to `user:<id>:notifications` | Verified |
| `GET /auth/realtime-token` | Exists, `@Roles(Role.OWNER)`; token carries only `{ sub, role: 'authenticated', exp }` (no `tenantId`) | Verified |
| Notifications backend is shared/role-agnostic | `NotificationsController` has no `@Roles`; every query is `tenant_id + user_id` scoped | Verified — technician inbox needs no BE change beyond the token |
| `getIstDayRange` | `src/common/utils/ist-day-range.util.ts` | Verified |
| `fenzo-app/src/services/location/` | **Does not exist.** The existing helper is `src/features/technicianApp/geolocation.ts` (compat API + permission helper) | Wrong path (see F-7) |
| "generic `Skeleton`" | Only `features/reports/components/ReportSkeleton.tsx` exists | New generalisation, OK |
| App uses `useSyncExternalStore` stores | `useCustomers`, `useAuth`, `useMyProfile`, etc. | Verified |
| Bun 1.4.0 | `packageManager: bun@1.4.0`, Dockerfile `oven/bun:1.4.0` (project-context.md still says 1.3.13 — stale doc, not a spine issue) | Verified |

## 2. Findings

Severity: HIGH = two units will diverge or data will be wrong; MEDIUM = Rule not enforceable as written or a real gap; LOW = polish.

### F-1 [HIGH] Replays and counting of rejected check-in attempts are not defined (AD-4, AD-6, AD-15)

- AD-6 puts `UNIQUE (tenant_id, request_id)` "on the row it creates" — for check-in that is `attendance_records`. A **rejected** attempt creates only an `attendance_attempts` row, which has no uniqueness. A network retry of the same rejected request (same key) inserts a second attempt, so it counts twice toward the 5/10-min rate limit and toward the "3rd mocked attempt of the month" Owner alert. The PRD's alert then fires from retries, not real attempts.
- AD-15 does not say whether a `rate_limited` outcome is itself a "rejected attempt". If it is, every tap during the block extends the block forever. If it isn't, the spine must say so.
- **Fix:** add to AD-6: "`attendance_attempts` also carries `request_id` with `UNIQUE (tenant_id, request_id)`; a replay of a rejected request returns the stored outcome with no new row." Add to AD-15: "`rate_limited` outcomes are recorded but are excluded from the count; the block ends 10 min after the 5th counted rejection; `retryAfterSeconds` is computed from that anchor."

### F-2 [HIGH] AD-17 refetch conflicts with AD-19 "never triggers job refetches"

- AD-17 says the app refetches `/users/me` on foreground and on **every** `attendance.*` / `leave.*` notification. `/users/me` returns the full role-branched profile including the jobs page and `jobCounts`. So every leave notification causes a job-data refetch — exactly what AD-19 and FR-27 forbid ("never triggers a job refresh"), and it is also expensive.
- **Fix:** add a light `GET /api/v1/attendance/me/access` (both roles) that returns only `{ attendanceEnabled, attendanceAccess, attendanceStartDate }` from `attendance_access()`. `/users/me` carries the same three fields for the initial load. Refetch on notification/foreground calls only the light route, into an attendance-owned store.

### F-3 [MEDIUM] `tenants.timezone` CHECK "against `pg_timezone_names`" is not valid Postgres (AD-7)

- Postgres CHECK constraints can't contain subqueries, so `CHECK (timezone IN (SELECT name FROM pg_timezone_names))` fails at migration time. Each story author will pick a different workaround.
- **Fix:** state the mechanism: a `BEFORE INSERT OR UPDATE` trigger on `tenants` (or a `tenant_timezone_is_valid(text)` function used in CHECK that tries `now() AT TIME ZONE p_tz` inside an exception block). Say which one.

### F-4 [MEDIUM] Owner SELECT policy has no role predicate (AD-16)

- The Owner policy is `tenant_id = (auth.jwt() ->> 'tenantId')::uuid`. Technician login JWTs carry the **same** `tenantId` claim (`auth.service.ts` signs `{ sub, tenantId, role }` for both roles). Today this is not directly reachable (the login JWT's `role` isn't a Postgres role, and the realtime token has no `tenantId`), but the rule as written would grant a technician tenant-wide reads of coordinates and attendance the moment any token carries both. Deny-by-default should not depend on that accident.
- **Fix:** Owner policy = `tenant_id = (auth.jwt() ->> 'tenantId')::uuid AND auth.jwt() ->> 'role' = 'owner'`. Add a technician-token probe for each new table to `rls-isolation.integration.spec.ts`.

### F-5 [MEDIUM] Values the app would otherwise compute are not pinned to the server

AD-2 lists what is SQL-only but misses these, so the app story and the backend story will each invent their own:

- **Request-level leave status** (AD-11 "derived from its day states") — who derives it, and what label a mix of approved + revoked days gets (FR-14/FR-17 "Revoked with reason and dates").
- **Working-day count shown before submitting leave** (FR-12 "5 working days") — AD-2 makes working-day counts SQL-only, but no route gives the app a preview, so the app will count locally.
- **FR-9 leave-day confirmation** — the server auto-cancels today's leave on any check-in. A stale app that didn't show the prompt will cancel leave silently.
- **FR-4 "onboarding shows once per Employee"** — server or device? Not decided (switching phones differs).
- **Fix:** (a) the leave read function returns `status` (single derived value, rule defined in SQL) plus per-state date lists; (b) add `GET /attendance/me/leave/preview?from&to&part` (and Owner variant) returning the working-day count and blocking reasons; (c) add `p_confirm_leave_cancel boolean` to `attendance_check_in` and outcome `leave_confirmation_required` (same for holiday/weekly-off confirmation if the server should enforce it); (d) store `onboarded_at` server-side and expose it in the access state.

### F-6 [MEDIUM] `retryAfterSeconds` body vs `Retry-After` header contradiction; app can't read extras

- AD-4 and the sequence diagram put `retryAfterSeconds` in the 429 body. `GlobalExceptionFilter` deletes `retryAfterSeconds` from the body and sets a `Retry-After` header instead (Conventions row says header). Also fenzo-app's `apiError.ts` parses only `error_code` and `message`, so `distanceM` / `radiusM` / `Retry-After` are dropped today.
- **Fix:** AD-4: "429 carries `Retry-After` header only (existing filter behaviour); 422 carries `distanceM`, `radiusM` in the body." Add "`ApiError` exposes extra body fields and the `Retry-After` header" to AD-1's list of allowed shared generalisations.

### F-7 [MEDIUM] Location module path doesn't exist; move of the permission helper is undecided (AD-1, AD-20)

- `src/services/location/` doesn't exist. The permission helper and the job compat capture live together in `src/features/technicianApp/geolocation.ts`, imported by `LocationCaptureScreen` (which AD-1 says must not change). One story may move the helper, another may duplicate it.
- The library's `mocked` and `provider` are **optional** in 1.4.3 types; the server behaviour when `mocked` is absent isn't decided.
- **Fix:** AD-20: "Create `src/services/location/attendanceCapture.ts` (modern API). Extract `requestLocationPermission` into `src/services/location/permission.ts` and re-export it from `features/technicianApp/geolocation.ts` so job imports don't change." State "`mocked` absent → treated as `false`, recorded as `null`" (or reject — pick one).

### F-8 [LOW] `AppMetrics` has no counter

- Add to AD-1's allowed generalisations: "extend `AppMetrics` with `recordAttendanceRejection(outcome)` counter". Otherwise the metric story edits telemetry ad hoc.

### F-9 [MEDIUM] Outcome → ErrorCode table is deferred but it is a cross-repo contract

- Deferred says "exact attendance ErrorCode list ... story-level". The app maps codes to messages (FR-7 has specific copy per reason). If the backend and app stories name codes differently, they diverge.
- **Fix:** move the outcome → `ErrorCode` → HTTP table into AD-4 (e.g. `too_far → ATTENDANCE_TOO_FAR 422`, `low_accuracy → ATTENDANCE_LOW_ACCURACY`, `mocked → ATTENDANCE_MOCKED_LOCATION`, `stale_fix`, `rate_limited → ATTENDANCE_RATE_LIMITED 429`, `already_checked_in`, `not_checked_in`, `not_tracked`, `leave_confirmation_required`). Keep only non-check-in codes story-level.

### F-10 [MEDIUM] Operational envelope is thin

| Dimension | Spine | Gap / fix |
| --- | --- | --- |
| Deployment & environments | "No new service", release order, Maps key per build | There is one Render service with `autoDeploy: true` and one Supabase project (no staging seen); migrations are applied through Supabase MCP. State that attendance migrations go to the live DB ahead of the API deploy and must be safe with the old API running. |
| Migrations / rollback | "Additive" only | State: forward-only migrations; rollback = revert API deploy + leave tables in place; the module stays dark because no tenant has `attendanceEnabled`. Say whether there is a global kill switch (e.g. `attendance_settings`/env flag) or explicitly none. |
| Data retention | Leave/attendance "never hard-deleted" | `attendance_attempts` stores raw coordinates with no retention decision (NFR-11 privacy). Decide (e.g. keep forever for the flag history, or null out lat/lng after N days while keeping outcome). Note that attendance notifications fall under the existing 30/90-day `notifications-cleanup` job — say that deep links from old rows may 404 gracefully. |
| Ops / monitoring | Reminder metrics deferred | OK to defer, but add: pg_cron job name (`attendance-reminders`), schedule, and that failures show in `cron.job_run_details`. |
| App version compatibility | Not covered | Older owner builds drop non-job, non-report events in `NotificationsScreen`, while the unread badge still counts them (badge ≠ list). Decide: minimum app version before a tenant can enable attendance, or accept the mismatch. |

### F-11 [MEDIUM] AD-18 fallback leaves FR-27 unmet and ambiguous to build

- FR-27 requires real-time technician delivery. AD-18 says until the security fixes merge, technicians poll on foreground. The release order already puts the fixes before fenzo-app, so it's unclear whether the polling path is a built, shipped feature or dead code.
- **Fix:** decide one: (a) "Security fixes are a hard release blocker for the fenzo-app attendance release; no polling fallback is built", or (b) "Foreground/list polling is the permanent baseline for both roles; realtime is additive once the gate opens". Say which story owns the gate check.

### F-12 [LOW] Smaller rule gaps

- **AD-10 + AD-12:** say how manual-time corrections feed rule 7/8 (override times replace record times for grading; status overrides are rule 1).
- **FR-24 "flags from past days until handled":** "handled" is defined for Checkout missing (a correction) but not for Fake location attempt. Decide a dismiss action or a fixed look-back window (e.g. current month).
- **AD-14:** state catch-up semantics: a reminder fires at the first run at or after its due time, **same `work_date` only**; missed days are never back-filled.
- **AD-8:** "only the upper bound of a past range may change" — say whether a trigger enforces it or only the RPCs.
- **AD-13:** "the only other writer is the reminder job" — reword to "the only other writer of attendance/leave events"; `advance_workflow_step` and the report engine also write notifications.
- **btree_gist:** follow the repo's `CREATE EXTENSION IF NOT EXISTS ... WITH SCHEMA extensions` convention; say so in AD-8.
- **Status tags:** only AD-1..AD-3 carry `[ADOPTED]`; tag all ADs consistently.

## 3. Coverage (FR-1..28, NFR-1..12)

All FRs and NFRs are bound in frontmatter and mapped in the Capability map. Gaps are depth, not absence:

- FR-4 (onboarding once — F-5), FR-9 (server-side confirmation — F-5), FR-12 (working-day preview — F-5), FR-17 (derived status — F-5), FR-24 (flag "handled" — F-12), FR-27 (realtime gate — F-11).
- NFR-9 partially deferred (reminder metrics) — acceptable, isolated.
- NFR-11 privacy — capture rule is good; retention of stored coordinates missing (F-10).
- Capability map rows for NFR-2, 3, 4, 6, 7, 8, 10, 11 are missing from the table (they are covered by ADs; add rows for traceability).

## 4. Deferred list — can anything let two units diverge?

- Push delivery, materialisation, out-of-MVP items, remove-technician, job-RPC hardening: safe.
- Reminder metrics: safe (single story).
- **ErrorCode list: not safe** — cross-repo contract (F-9).
- **DTO field-level validation:** safe only because thresholds are fixed in Conventions.

## 5. Named tech currency (npm registry, 2026-09-25)

| Package | Spine | Latest | Note |
| --- | --- | --- | --- |
| react-native-maps | 1.29.8 | 1.29.8 (2026-09-20) | Current; RN 0.87 spike correctly flagged |
| @react-native-community/netinfo | 12.0.1 | 12.0.1 | Current |
| react-native-nitro-geolocation | 1.4.3 | **2.0.2** (2026-09-13) | Spine ratifies installed version — fine, but say "no upgrade to 2.x in this feature" so a story doesn't bump a major mid-stream |
| @nestjs/platform-fastify | 11.1.27 | **12.1.0** | Same — pin to 11.x for this feature |
| fastify | 5.8.5 | 5.12.5 | Minor behind, OK |
| @supabase/supabase-js | 2.108.2 / 2.116.0 | 2.117.1 | OK |
| btree_gist, pg_cron | — | Available on Supabase | OK |

## 6. Form checks

- **Decisions, not rationale:** mostly decision-shaped. `[ASSUMPTION]` tags (AD-8 pin not effective-dated, AD-20 `stale_fix`, thresholds by migration) are neither decided nor listed as open questions, and there is no Open Questions section. Either ratify them as decisions or add an Open Questions section.
- **Mermaid:** flowchart, erDiagram and sequenceDiagram all parse (checked syntax: node shapes, dotted labelled edge, ER cardinalities with quoted labels, `alt/else/end`).
- **Template comments:** none left.
- **Diagram vs text:** the ER diagram omits `tenants.timezone` and `attendance_attempts.request_id` (after F-1) — minor.

## 7. What is good (keep)

- AD-4 "rejections are committed outcomes" correctly solves the RAISE-rollback trap.
- AD-7 single time model and AD-10 single day-status function remove the largest divergence risk.
- AD-5 lock ordering is explicit and deadlock-safe.
- AD-6 not reusing the racy `IdempotencyInterceptor` is correct for this codebase.
- AD-18 correctly ties the technician realtime token to the two deferred security items; the brownfield evidence (token claims, `@Roles(OWNER)`) backs it.
- Cross-repo release order follows the meta-repo rule (additive backend first).
