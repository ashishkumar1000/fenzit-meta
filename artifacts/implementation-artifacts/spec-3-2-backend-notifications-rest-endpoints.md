---
title: 'Backend — Notifications REST endpoints (list, unread count, mark read)'
type: 'feature'
created: '2026-09-09'
status: 'done'
review_loop_iteration: 0
context: []
baseline_commit: '81a0abae8d0acad7bf3acf4f9ea58e5dd1f25031'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** Story 3.1 persists notifications and broadcasts them, but there is no way for the owner app to fetch the notification list (needed by the bell icon / notifications page, Story 3.4) or manage read state. Without REST endpoints the data exists but is unreachable for app-driven reads.

**Approach:** One small new NestJS module `src/notifications/` (mirroring the `places` module's provider-DI convention in shape, but simpler — no provider seam needed since reads go straight through the existing `createAdmin()` Supabase client with explicit tenant/user scoping). Four endpoints, all strictly additive, all recipient-scoped by the JWT `sub` claim:

- `GET /notifications?limit=&cursor=` — newest-first keyset pagination, reusing the house cursor util (see Code Map)
- `GET /notifications/unread-count` — `{ unreadCount: number }`
- `POST /notifications/mark-read` — `{ ids: string[] }`
- `POST /notifications/mark-all-read` — no body

List responses use the shared `PaginatedResponse` envelope (`{ data, nextCursor }`), exactly like customers/jobs lists — not a bespoke shape.

Deliberately **not** role-gated to OWNER: rows are recipient-scoped by `user_id = sub`, so whoever holds a valid JWT only ever sees their own rows (a technician's set is naturally empty today — only owners receive rows). This matches how RLS would behave and avoids a second authorization concept.

## Boundaries & Constraints

**Always:**
- Scope **every** query by both `.eq('tenant_id', user.tenantId)` and `.eq('user_id', user.userId)` — tenant scoping alone would leak across recipients within a tenant (owner + technician share `tenantId`). `RequestUser.tenantId` is **nullable** (`src/common/interfaces/request-user.interface.ts`) — if `tenantId` is null (user hasn't completed company setup), return empty list / count 0 / markedCount 0 without querying; a null `.eq('tenant_id', undefined)` would silently drop the filter.
- Follow the module conventions of the existing feature modules: `notifications.module.ts`, `notifications.controller.ts`, `notifications.service.ts`, DTOs with class-validator (`@IsUUID` each id, `@IsOptional() @Type(() => Number) @IsInt() @Min(1) @Max(50) limit`, default 20 applied in the service, max 50 — exact decorator shape from `src/jobs/dto/list-jobs-query.dto.ts` lines 130-135), wired as a plain entry in `app.module.ts` `imports` (after `PlacesModule`).
- **Auth is already global — do NOT add `@UseGuards(JwtAuthGuard)`.** `JwtAuthGuard` + `RolesGuard` are registered as `APP_GUARD` in `app.module.ts` (lines 111-118); no `@UseGuards` exists anywhere in `src/`. In the controller use `@ApiBearerAuth()` and inject the user via the `@CurrentUser()` param decorator (`src/common/decorators/current-user.decorator.ts`) typed as `RequestUser`. Deliberately do **not** add `@Roles(...)` — see Intent.
- `mark-read` sets `read_at = now()` only on rows where `read_at IS NULL` and `user_id = sub` — idempotent on already-read rows, no error for ids that don't exist or belong to another recipient (silently no-op; the response reports the count actually marked).
- Order list results `created_at desc, id desc` (stable keyset cursor; the existing `decodeCursor`/`rejectCursor` handles malformed cursors as 400). Use the house cursor machinery, not a bespoke param: `cursor` query param (base64url JSON `{ id, createdAt, scope }` via `src/common/utils/cursor.util.ts`), adding `'notifications-list'` to the `CursorScope` union. Query pattern mirrors `customers.service.ts:365-395`: PostgREST `.or('created_at.lt.<c>,and(created_at.eq.<c>,id.lt.<c>))'` + `limit(N+1)` + `hasMore` slice.
- Route prefix `@Controller('notifications')` under the global prefix `api/v1` (`main.ts:24-26`, `setGlobalPrefix('api/v1', ...)`) — effective `/api/v1/notifications`, same as `@Controller('customers')`.
- Error bodies follow the house shape `{ error_code: ErrorCode.X, message: '...' }` (`ErrorCode` enum in `src/common/enums/error-code.enum.ts`); malformed `cursor` → `BadRequestException` + the existing `rejectCursor` convention (400).

**Ask First:** None — endpoint shapes, pagination style, and error codes all have direct precedent in `customers`/`jobs` modules; the response field naming (camelCase at the boundary) follows `toDetailResponse()` convention.

**Never:**
- Do not gate endpoints to `@Roles(Role.OWNER)` — recipient-scoping by `sub` is the authorization (see Intent); adding role gating would break if the owner is also a technician in a solo tenant.
- Do not add delete endpoints or a "clear all" — pg_cron prunes (Story 3.1); deletion is not a product requirement.
- Do not join to `jobs`/`users` on the server per row at read time — Story 3.1's INSERT already denormalizes `job_number`/`technician_name` into `payload`; read it as-is. (If the payload turns out incomplete during implementation, fix the INSERT, not a read-time join.)
- Do not modify `advance_workflow_step` or any Story 3.1 SQL — that story is frozen.
- Do not touch `fenzo-app` — Story 3.4 consumes these endpoints.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Owner with notifications | `GET /notifications?limit=20` | `200`, `{ data: [...], nextCursor: string \| null }` (shared `PaginatedResponse` envelope) — newest first, `payload` returned verbatim (job_number, step, technician_name), `readAt` null for unread | N/A |
| Pagination | `cursor=<base64url from nextCursor>` | Next page strictly older than cursor; `nextCursor: null` on last page; malformed/foreign-scope cursor → 400 via `rejectCursor` | `400` |
| Invalid limit | `limit=999` / `limit=abc` | `422` — global ValidationPipe (`whitelist: true`, `errorHttpStatusCode: 422` in `src/common/validation-pipe-options.ts`); no custom exception factory | `422` |
| Unread count | Rows with and without `read_at` | `200 { unreadCount: n }` — only `read_at IS NULL` rows counted | N/A |
| Mark read | `POST mark-read { ids: [a, b] }` where `b` belongs to another user (or doesn't exist) | `200 { markedCount: 1 }` — only own, unread rows counted; no error for foreign/missing ids | N/A |
| Mark all read | `POST mark-all-read` | `200 { markedCount: n }` (0 if all read); idempotent repeat → `{ markedCount: 0 }` | N/A |
| Technician JWT | Any endpoint | `200` with empty list / 0 count / 0 marked — never an error, never another recipient's rows | N/A |
| Cross-tenant probing | Valid JWT, guessing ids/urls | All queries double-scoped (`tenant_id` + `user_id`); cross-tenant ids resolve to nothing | N/A |
| Empty state | Fresh user, zero rows | `200 { data: [], nextCursor: null }`, `unreadCount: 0` | N/A |
| No tenant yet | `RequestUser.tenantId === null` | Empty list / count 0 / markedCount 0 — short-circuit before any Supabase call (a null `.eq` value would silently drop the tenant filter) | N/A |

</frozen-after-approval>

## Code Map

- `src/notifications/notifications.module.ts` -- NEW: NestJS module (controller + service; no `CacheModule` — the global `CacheModule.register({ ttl: 300 })` in app.module is registration-only, the `APP_INTERCEPTOR` is `LoggingInterceptor`, so GETs are **not** cached — no cache-busting needed)
- `src/notifications/notifications.controller.ts` -- NEW: 4 routes on `@Controller('notifications')`, `@ApiBearerAuth()`, user via `@CurrentUser() user: RequestUser` (no `@UseGuards` — guards are global `APP_GUARD`s, `app.module.ts:111-118`)
- `src/notifications/notifications.service.ts` -- NEW: all Supabase reads/writes through `supabaseClientFactory.createAdmin()` (exact API: `SupabaseClientFactory` in `src/common/factories/supabase-client.factory.ts` — it has only `create(jwt)` [zero callers, do not use] and `createAdmin()`) with explicit `.eq('tenant_id', ...)` + `.eq('user_id', user.userId)` on every call
- `src/notifications/dto/` -- NEW: `NotificationResponse` (id, jobId, eventType, payload, readAt, createdAt — camelCase boundary naming per `toDetailResponse()` convention), `ListNotificationsQueryDto` (`limit`: `@IsOptional() @Type(() => Number) @IsInt() @Min(1) @Max(50)`, `cursor`: `@IsOptional() @Transform(trim) @IsString() @MaxLength(512)`), `MarkReadDto` (`ids: string[]` with `@IsArray()` + `@ArrayNotEmpty()` + `@ArrayMaxSize(100)` + `@IsUUID(undefined, { each: true })` — this is the one client-controlled unbounded input, so cap it; the service short-circuits to `markedCount: 0` without querying rather than ever building an empty `.in('id', [])`; strings trimmed via the shared `src/common/utils/trim.transformer.ts` — never write a seventh local trim copy)
- `src/common/utils/cursor.util.ts` -- UPDATE (smallest possible): add `'notifications-list'` to the `CursorScope` union; encode/decode/reject are reused as-is (`encodeCursor(id, createdAt, scope)`, base64url JSON; malformed or foreign-scope cursor → 400 via `rejectCursor`)
- `src/common/dto/paginated-response.dto.ts` -- REFERENCE (no change): reuse `new PaginatedResponse(items, nextCursor)` for the list envelope
- `src/app.module.ts` -- UPDATE: register `NotificationsModule` as a plain entry in `imports` (after `PlacesModule`, lines 94-103)
- `src/common/interfaces/request-user.interface.ts` -- REFERENCE (no change): `RequestUser { userId: string; tenantId: string | null; role: Role; rawJwt: string }`
- `src/customers/customers.controller.ts` + `src/customers/customers.service.ts` -- REFERENCE: route prefix, `@CurrentUser()` injection, admin-client scoping, error-shape conventions to mirror; `customers.service.ts:365-395` is the keyset-pagination template
- Reference: `docs/api-contracts.md` (in fenzit-be repo) -- add a `### Notifications` section under `## Endpoints` (after `### Jobs`), documenting the four endpoints, the `{ data, nextCursor }` envelope, and the 422-validation/400-cursor split; also add a note to `### Jobs` that `advance_workflow_step` now writes one notification row (Story 3.1 side effect)

## Tasks & Acceptance

**Execution:**
- [x] `src/notifications/` module: service with the 4 operations, controller with routes, DTOs
- [x] `cursor.util.ts`: add the `'notifications-list'` scope
- [x] `src/app.module.ts`: register the module
- [x] Unit tests (`src/notifications/notifications.service.spec.ts` — co-located, jest `rootDir: "src"` + `testRegex: .*\.spec\.ts$`): list pagination + cursor, unread count, mark-read idempotency + foreign-id no-op, double-scoping assertions (tenant + user filters on every call), null-tenantId short-circuit
- [x] e2e (`test/notifications.e2e-spec.ts` — jest-e2e.json also matches `.integration.spec.ts` files; specs live flat in `test/` beside `jobs.e2e-spec.ts`): owner happy path (list → unread-count → mark-read → count drops → mark-all-read → count 0), technician sees empty, validation 422s, malformed cursor 400. **Seeding:** insert fixture rows directly through `supabaseClientFactory.createAdmin()` — in this story nothing else writes `notifications` (the RPC INSERT is Story 3.1's, already deployed); do not drive full workflow advances per test
- [x] `docs/api-contracts.md`: `### Notifications` section

**Acceptance Criteria:**
- Given an owner JWT, `GET /notifications` returns only that recipient's rows, newest first, cursor-paginated, with payload/readAt/createdAt per row
- Given `GET /notifications/unread-count`, the count reflects `read_at IS NULL` rows for that recipient only
- Given `POST /notifications/mark-read` / `mark-all-read`, matching own rows get `read_at` set idempotently; foreign or missing ids never error and never leak
- Given any JWT, every query is scoped by tenant **and** recipient — no cross-recipient or cross-tenant read is possible
- Given the rest of the API, nothing existing changes — strictly additive module

### Review Findings

- [x] [Review][Patch] `trimArray` behavior untested — no test sends a whitespace-padded UUID and expects 200 `markedCount: 1`; the one behavior the shared transformer was written for is unverified (if `@Transform` is dropped or regresses, padded ids become 422s and no test fails) [test/notifications.e2e-spec.ts] — FIXED: padded-UUID success test added (asserts the trimmed id reaches `.in()`)
- [x] [Review][Patch] No 500-mapping unit tests for `markRead` / `markAllRead` — only `listNotifications` and `getUnreadCount` cover the DB-error → 500 path [src/notifications/notifications.service.spec.ts] — FIXED: 2 tests added
- [x] [Review][Patch] `limit` boundary values 1 and 50 never tested — validation batch covers only invalid values, so the `@Min(1)/@Max(50)` acceptance edge is untested [src/notifications/notifications.service.spec.ts] — FIXED: boundary test added (limit 1 → fetch 2, limit 50 → fetch 51)
- [x] [Review][Patch] No 401 test in the notifications e2e spec — house e2e specs (customers/jobs) assert `401` with no JWT; the documented contract for these routes is untested [test/notifications.e2e-spec.ts] — FIXED: parametrized 401 batch over all four endpoints added
- [x] [Review][Patch] Comment references a non-existent name — `toResponse` says "(toDetailResponse convention)" but the house mapper name is `toResponse` (as in `customers.service.ts`); `toDetailResponse` exists nowhere [src/notifications/notifications.service.ts:191] — FIXED: comment corrected

## Design Notes

- **Why no role guard:** recipient-scoping (`user_id = sub`) is a *stronger* isolation than role-gating for this resource, and it survives the edge case where a user is both owner and actor. Role checks stay for tenant-wide resources (jobs, customers) — this is not that.
- **Why cursor pagination, not offset:** pg_cron deletes rows continuously (30-day TTL), so offset pagination would skip/duplicate rows between pages; a `created_at` cursor is stable under both inserts (newest first — new rows don't shift old pages) and deletes.
- **Why the house cursor util, not a bare `before=timestamp`:** `src/common/utils/cursor.util.ts` already solves the same-timestamp tiebreak (id in the encoded payload), base64url-encodes, and validates scope — inventing a parallel param shape would fork the pagination conventions; FE `Paginated<T>` already speaks `{ data, nextCursor }`.
- **Why mark-read is POST, not PATCH:** bulk-id mutation, no full-resource update semantics; matches `advanceWorkflow`-style POST commands in the existing API.
- **Counts stay O(index):** `unread-count` hits the `(user_id, created_at desc)` index with a `read_at IS NULL` filter — at Phase 1 scale (per-user rows, 30-day TTL) this is trivially fast; no counter-cache needed.
- **Previous-work intelligence (from Epic 1/2 dev records + code re-verified 2026-09-09):**
  - **Shared DTO utilities exist — use them, don't re-copy:** `StructuredAddressDto` + `PaginatedResponse` live in `src/common/dto/` (the sanctioned cross-module DTO home); string inputs go through the shared `src/common/utils/trim.transformer.ts` (`trim` and `trimToUndefined` — six per-DTO `trim` copies were collapsed into it, adding a seventh is a review flag; `trimToUndefined` maps `''` → `undefined` so `?cursor=` is "not provided"). `src/common/utils/cursor.util.ts` + `cursor.util.spec.ts` is the pagination machinery.
  - **Swagger response DTOs:** there is no swagger CLI plugin; Swagger mounts at `api/docs` only when `NODE_ENV !== 'production'`; generic responses are composed via the allOf/`getSchemaPath` pattern (see `CustomerListItemDto` + `PaginatedResponse` in `customers`).
  - **400-vs-422 convention (verified in `src/common/validation-pipe-options.ts`):** the global ValidationPipe sets `whitelist: true`, `forbidNonWhitelisted: false`, `transform: true`, `errorHttpStatusCode: 422` — DTO rejections are **422** with no custom exception factory. Service-layer guards use Nest exceptions with `{ error_code: ErrorCode.X, message }` bodies (e.g. `BadRequestException` + `VALIDATION_ERROR`, `NotFoundException` + `RESOURCE_NOT_FOUND`, `ConflictException` + `DUPLICATE_RESOURCE`), forwarded by `GlobalExceptionFilter` (registered as `APP_FILTER`). Malformed cursors are 400 (existing `rejectCursor` behavior).
  - **Parametrized validator e2e cases are the house style** — pin invalid `limit`/`ids` values as parametrized 422 cases (mirroring the 2026-09-08 structured-address batch in `jobs.e2e-spec.ts`).
  - **Test environment facts:** scripts are `"test": "jest"` and `"test:e2e": "jest --config ./test/jest-e2e.json"` (run via bun); the full e2e suite has **8 pre-existing baseline failures** in `customers.e2e-spec.ts`/`sync.e2e-spec.ts` (verified at baseline `a7f6593` via stash round-trip during Story 2.1) — re-verify the baseline instead of chasing them; e2e spec files carry pre-existing `no-unsafe-*` eslint debt (file-wide `JSON.parse → any` convention — follow it in `notifications.e2e-spec.ts`, keep `src/notifications/` itself lint-clean). `lint` script runs eslint `--fix` on `{src,apps,libs,test}/**`; `typecheck` script exists (`tsc -p tsconfig.build.json --noEmit`) — run it before claiming done.
  - e2e specs live flat in `test/` (jobs/customers/sync already sit there) and `jest-e2e.json` discovers by pattern — a new `test/notifications.e2e-spec.ts` needs no config change.
- Cross-repo ordering: Story 3.1 (fenzit-be) merges/deploys first, then this story (fenzit-be, additive), then Stories 3.3/3.4 (fenzo-app). This story and 3.1 may merge together — both additive BE.

## Verification

**Commands:**
- `bun run test -- notifications` -- expected: new unit spec passes
- `bun run test:e2e -- notifications` -- expected: new e2e spec passes
- `bun run build` -- expected: clean
- `bun run lint` -- expected: clean on new files

## Suggested Review Order

1. `notifications.service.ts` — verify **every** Supabase call is double-scoped (tenant + user); this is the security review core.
2. DTOs — limit bounds, UUID validation, cursor type.
3. Controller — guard wiring, route prefix, error shapes match house convention.
4. Module registration.
5. Specs — pagination + idempotency + scoping coverage.
6. `docs/api-contracts.md`.

## Dev Agent Record

### Completion Notes

- All 4 operations implemented in one service; every Supabase call is double-scoped
  (`.eq('tenant_id', ...)` + `.eq('user_id', user.userId)`) — verified by dedicated
  assertions in both spec levels. `tenantId === null` short-circuits all four
  operations to empty/0 **before** any DB call (asserted via `from` never called).
- `mark-read` / `mark-all-read` update with `.is('read_at', null)` and count the
  rows the UPDATE actually returned (`markedCount`) — foreign/missing/already-read
  ids are silent no-ops by construction, no read-then-write round trip.
- Pagination mirrors `customers.service.ts` keyset template exactly: `limit(N+1)`
  peek row, `hasMore` slice, cursor minted from the last page row under scope
  `'notifications-list'`.
- One deviation-shaped addition: added a **shared `trimArray`** transformer to
  `src/common/utils/trim.transformer.ts` (spec prescribed the shared-trimmer rule;
  the existing `trim` helper is per-string and its `TransformFnParams` type does
  not support per-element mapping — a shared array variant honors the "no seventh
  local trim copy" rule better than an inline copy in `MarkReadDto`).
- House e2e debt followed as prescribed: `notifications.e2e-spec.ts` uses the
  file-wide `JSON.parse → any` convention (lint `no-unsafe-*` errors accepted,
  same as customers/jobs e2e specs); `src/notifications/` itself is lint-clean
  (verified with targeted eslint run).
- Validation results: unit 16/16 (`bun run test -- notifications`), e2e 24/24
  (`bun run test:e2e -- notifications`), full unit suite 436/436 (no regressions),
  `bun run build` clean, `bun run typecheck` clean, lint clean on all new `src/`
  files. (Note: jest needs `--no-watchman` under the sandbox — watchman state
  dir is blocked; not a code issue.)
- No e2e/live-DB verification of the endpoints against the deployed Supabase
  project — per owner decision 2026-09-09 (no e2e/DB test suite), manual live
  verification is the accepted coverage if the owner wants it before commit.

### File List

- `src/notifications/notifications.module.ts` — NEW
- `src/notifications/notifications.controller.ts` — NEW
- `src/notifications/notifications.service.ts` — NEW
- `src/notifications/dto/notification-response.dto.ts` — NEW
- `src/notifications/dto/list-notifications-query.dto.ts` — NEW
- `src/notifications/dto/mark-read.dto.ts` — NEW
- `src/notifications/dto/notification-count-response.dto.ts` — NEW
- `src/notifications/notifications.service.spec.ts` — NEW (16 unit tests)
- `test/notifications.e2e-spec.ts` — NEW (24 e2e tests)
- `src/common/utils/cursor.util.ts` — `'notifications-list'` added to `CursorScope`
- `src/common/utils/trim.transformer.ts` — shared `trimArray` transformer added
- `src/app.module.ts` — `NotificationsModule` registered (after `PlacesModule`)
- `docs/api-contracts.md` — `### Notifications` section added

### Change Log

- 2026-09-09: Story 3.2 implemented end-to-end (module + tests + docs); status → review.
- 2026-09-09: BMAD code review run (4 layers: blind-hunter, edge-case-hunter, verification-gap, acceptance-auditor). 5 patch findings, all fixed
  (padded-UUID e2e test, 500-mapping unit tests for mark-read/mark-all-read, limit boundary unit test, 401 e2e batch, stale comment); 15 dismissed
  after verification against code (cursor-injection and null-payload false positives — `decodeCursor` validates and `payload` is `NOT NULL DEFAULT '{}'`;
  index exists from Story 3.1; mock-based e2e accepted per owner decision 2026-09-09; rest house-consistent/cosmetic). Post-fix validation: unit 19/19,
  e2e 29/29, full suite 439/439, typecheck clean, `src/notifications/` lint-clean. Status → done.