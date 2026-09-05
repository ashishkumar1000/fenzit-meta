---
title: 'Backend — Address autosuggest endpoint'
type: 'feature'
created: '2026-09-05'
status: 'done'
review_loop_iteration: 0
context: []
baseline_commit: '517f9ee53c715c251cb30544f2445b4e1b1ebaeb'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** Owners typing a customer's address free-text produce error-prone, unverifiable addresses; the Google API key must never reach the mobile client, so address search needs a server-side proxy.

**Approach:** Add a new, DB-less `PlacesModule` to `fenzit-be` exposing `GET /places/autosuggest?q=&sessionToken=`, fully wired end-to-end (auth, rate limiting, DTOs, DI) with `MockPlacesProvider` as the default binding — following the existing `OtpDeliveryProvider` DI-swap convention. The real `GooglePlacesProvider` integration is deferred (see `deferred-work.md`) since `GOOGLE_PLACES_API_KEY` has no value yet and can't be verified against live traffic until supplied.

## Boundaries & Constraints

**Always:**
- Auth: same global `JwtAuthGuard` + `@Roles(Role.OWNER)` convention as every other Owner-only endpoint (guards are global via `APP_GUARD`; only `@Roles(Role.OWNER)` is needed on the controller method).
- `PlacesProvider` is an abstract class; `MockPlacesProvider` is the only implementation in this spec, registered via the same custom-token `useClass` pattern as `OtpDeliveryProvider` in `auth.module.ts`. Its method signature (`autosuggest(query, sessionToken, region: 'IN')`) must be shaped so a future `GooglePlacesProvider` slots in with zero controller/service changes.
- `GOOGLE_PLACES_API_KEY` is added to the Joi schema in `app.module.ts` as required, read via `ConfigService.getOrThrow` — added now even though unused by the mock, so boot-time validation and the env contract are in place for the deferred provider.
- Rate limit per-tenant on a dedicated cache key `places:rate:{tenantId}:autosuggest`, returning `429 RATE_LIMITED` when tripped — independent budget from the future resolve endpoint (Story 1.2), reusing the existing global `CacheModule` (`CACHE_MANAGER`).
- `PlacesModule` is DB-less: no `SupabaseModule` import, no dependency on `CustomersModule`.
- An empty mock result returns `200 {suggestions: []}`, never an error.
- Response shape: `{ suggestions: [{ placeId, text }] }`.

**Ask First:** None for this narrowed spec — `MockPlacesProvider` as the sole/default binding was already confirmed by splitting off the live integration.

**Never:** Do not implement `GooglePlacesProvider` or any real Google network call in this spec (deferred). Do not implement `/places/resolve/:placeId` (Story 1.2) or any customer schema/persistence change (Story 1.3).

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Happy path | Valid JWT+Owner, `q="andheri w"`, `sessionToken=<uuid>` | `MockPlacesProvider` returns fixture suggestions; `200 {suggestions: [{placeId, text}, ...]}` | N/A |
| No auth | Missing/invalid JWT or non-Owner role | Rejected before handler runs | 401/403 via global `JwtAuthGuard`/`RolesGuard` |
| Empty mock result | Query matches no fixture | `200 {suggestions: []}` | Never an error |
| Rate limit tripped | Same tenant exceeds `places:rate:{tenantId}:autosuggest` budget | Request rejected before calling the provider | `429 RATE_LIMITED` |
| Provider throws | Mock simulates a provider-level failure | No suggestions available | `502 PLACES_UPSTREAM_ERROR` (proves the error-mapping path a real provider will also use) |

</frozen-after-approval>

## Code Map

- `src/auth/otp-delivery.provider.ts:1-3`, `mock-otp-delivery.provider.ts:5-13` -- abstract-provider + mock pattern to mirror for `PlacesProvider`/`MockPlacesProvider`
- `src/auth/auth.module.ts:15-22` -- DI registration convention (`{provide: X, useClass: Y}`) -- mirror for `PlacesProvider` and the rate-limit store
- `src/auth/otp-session-store.ts:9-21`, `in-memory-otp-session.store.ts:8,31-55` -- abstract + concrete rate-limit store shape (`increment(key, ttlSeconds)`, `@Inject(CACHE_MANAGER) cache: Cache`) -- mirror with key prefix `places:rate:`
- `src/app.module.ts:26-47` -- Joi env schema; add `GOOGLE_PLACES_API_KEY: Joi.string().required()` next to `SUPABASE_URL` (line 31)
- `src/app.module.ts:52-55,82-89` -- global `CacheModule` (already global) and `APP_GUARD` (`JwtAuthGuard`+`RolesGuard`) -- no new imports/decorators needed beyond `@Roles`
- `src/common/decorators/roles.decorator.ts:1-5`, `src/common/enums/role.enum.ts:1-4` -- `@Roles(Role.OWNER)`
- `src/customers/customers.controller.ts:34-48` -- example decorator stack to mirror
- `src/customers/dto/create-customer.dto.ts` -- `class-validator` DTO convention to mirror for `AutosuggestQueryDto`
- `src/customers/dto/customer-detail-response.dto.ts:1-40` -- response DTO pattern to mirror for the suggestions shape
- `src/skills/` (module/controller/service/dto files) -- structural template for `src/places/`
- `src/customers/customers.module.ts:1-11` -- confirms `PlacesModule.imports` should stay empty (no `SupabaseModule`)
- `src/auth/auth.service.spec.ts:24-39` -- Jest convention for mocking abstract-class methods -- mirror for `PlacesService` spec (run via `bun run test`, not `bun test`)

## Tasks & Acceptance

**Execution:**
- [x] `src/places/places-provider.ts` -- abstract `PlacesProvider` with `abstract autosuggest(query, sessionToken): Promise<{placeId, text}[]>` -- shaped for a future `GooglePlacesProvider` to slot in unchanged
- [x] `src/places/mock-places.provider.ts` -- `MockPlacesProvider extends PlacesProvider`, deterministic fixture suggestions plus a way to simulate a thrown error (for the 502 test case)
- [x] `src/places/places-rate-limit.store.ts` -- in-memory store mirroring `InMemoryOtpSessionStore.increment()`, keyed `places:rate:{tenantId}:autosuggest`
- [x] `src/places/dto/autosuggest-query.dto.ts` -- `AutosuggestQueryDto` (`q`, `sessionToken`, both `@IsString() @IsNotEmpty()`, plus `@Transform(trim)` + `@MaxLength(100)` per code review — see Spec Change Log)
- [x] `src/places/dto/autosuggest-response.dto.ts` -- response DTO for `{ suggestions: [{placeId, text}] }`
- [x] `src/places/places.service.ts` -- `PlacesService`, injects `PlacesProvider` + rate-limit store, checks/increments budget, maps provider errors → `502 PLACES_UPSTREAM_ERROR`, trips → `429 RATE_LIMITED`
- [x] `src/places/places.controller.ts` -- `PlacesController`, `@Get('autosuggest') @Roles(Role.OWNER)`, validates DTO, delegates to service
- [x] `src/places/places.module.ts` -- `PlacesModule` (empty `imports`; providers: `{provide: PlacesProvider, useClass: MockPlacesProvider}`, rate-limit store, service, controller); register in `app.module.ts`
- [x] `src/app.module.ts` -- add `GOOGLE_PLACES_API_KEY: Joi.string().required()`; import/register `PlacesModule`
- [x] `src/places/places.service.spec.ts` -- unit tests for the I/O matrix, mocking `PlacesProvider`/store per `auth.service.spec.ts`
- [x] `test/places.e2e-spec.ts` -- e2e spec (per `test/skills.e2e-spec.ts` convention, `app.inject(...)` against the real HTTP pipeline) asserting 401 (no JWT), 403 (Technician JWT), and 200 happy path (Owner JWT, real query, bound `MockPlacesProvider`) for `GET /places/autosuggest` -- covers the "No auth" Matrix row that the service-level spec alone doesn't exercise; extended per code review to also drive the real `PlacesRateLimitStore` to its limit (429) and cover missing/empty `sessionToken` (422)
- [x] `src/places/places-rate-limit.store.spec.ts` -- unit tests for the real `PlacesRateLimitStore` class (mocking only `CACHE_MANAGER`) -- added per code review; previously only exercised via a fully-mocked `useValue` in `places.service.spec.ts`
- [x] `src/places/mock-places.provider.spec.ts` -- unit tests for the real, DI-bound `MockPlacesProvider` (fixture match, empty result, `SIMULATE_PROVIDER_ERROR_QUERY` sentinel rejection, and non-production gating) -- added per code review

**Acceptance Criteria:**
- Given a valid JWT with Owner role and a query, when `GET /places/autosuggest?q=&sessionToken=` is called, then `PlacesService` calls the DI-bound `PlacesProvider` and returns `{suggestions: [{placeId, text}]}`
- Given a request without a valid JWT or Owner role, then it is rejected 401/403 via the existing global guards
- Given the `places:rate:{tenantId}:autosuggest` budget is exhausted, then it returns `429 RATE_LIMITED` without calling the provider
- Given the provider returns zero candidates, then it returns `200 {suggestions: []}`, never an error
- Given `GOOGLE_PLACES_API_KEY` is unset, then the app fails fast at boot via Joi validation
- Given the provider throws, then the endpoint returns `502 PLACES_UPSTREAM_ERROR`

## Spec Change Log

- 2026-09-05 — Implemented. Judgment calls made where the spec left detail open (none change the frozen Intent/Boundaries):
  - Rate limit budget set to 30 requests / 60-second window per tenant (`PLACES_RATE_LIMIT_MAX`/`_WINDOW_SECONDS` in `places.service.ts`) — reasonable for typed-ahead autosuggest, easy to retune later.
  - `PlacesRateLimitStore` implemented as a single concrete injectable class (constructor-injects `CACHE_MANAGER`, method `increment(key, ttlSeconds)`), not split into abstract+concrete like `OtpSessionStore`/`InMemoryOtpSessionStore` — there's no DI-swap need for it (only `PlacesProvider` needs that), so it mirrors `SupabaseClientFactory`'s pattern instead (concrete class, mocked via `useValue` in tests).
  - `PlacesProvider.autosuggest` takes a third `region: 'IN'` parameter per the frozen Intent's method-signature note, even though the task-list line only shows two params.
  - Rate-limit key falls back to `user.userId` when `user.tenantId` is null (owner hasn't run company setup yet) so the endpoint never throws on a missing tenant.
  - `MockPlacesProvider` reads (but discards) `GOOGLE_PLACES_API_KEY` via `ConfigService.getOrThrow` in its constructor, satisfying the spec's "read via ConfigService.getOrThrow" bullet ahead of the deferred real provider.
  - Added `ErrorCode.RATE_LIMITED` and `ErrorCode.PLACES_UPSTREAM_ERROR` (distinct from the existing `RATE_LIMIT_EXCEEDED`) since the spec names these exact codes.
  - Added `GOOGLE_PLACES_API_KEY` placeholder values to `.env`, `.env.example`, and `test/jest.env.setup.ts` so local boot and the e2e test suite (which boots the full `AppModule`) don't break now that Joi requires it.
- 2026-09-05 — Matrix Test Audit gap found and fixed: the "No auth" I/O matrix row (401/403 via global guards) had no running test — `places.service.spec.ts` is a service-level spec that never exercises `JwtAuthGuard`/`RolesGuard`. Added `test/places.e2e-spec.ts` mirroring `test/skills.e2e-spec.ts` (`app.inject(...)` against the real HTTP pipeline, `ownerJwt()`/`techJwt()` helpers, `SupabaseClientFactory` overridden since `AppModule` instantiates it globally even though `PlacesModule` itself never uses it). Covers: 401 no JWT, 403 Technician JWT, 200 happy path against the bound `MockPlacesProvider`, 200 empty-suggestions path, 422 missing `q`. Note: this e2e spec runs via `bun run test:e2e -- places` (repo convention — e2e specs live under `test/` with their own Jest project config, `test/jest-e2e.json`, separate from the `src/`-scoped unit-test config `bun run test` uses), not `bun run test -- places`, which only reaches `src/**/*.spec.ts`.
- 2026-09-05 — Applied 6 real findings from the 3-layer code review (Blind Hunter, Edge Case Hunter, Verification Gap); remaining findings were rejected as intentional/spec-mandated or deferred (see `deferred-work.md`):
  1. `AutosuggestQueryDto` — added `@Transform(trim)` (mirroring `ListCustomersQueryDto`'s `q` field) + `@MaxLength(100)` on both `q` and `sessionToken`, so a whitespace-only value fails validation before it burns a rate-limit slot, instead of only being caught by the service's own internal `.trim()`-equivalent logic downstream.
  2. `PlacesService.autosuggest` — the `rateLimitStore.increment()` call is now wrapped in its own try/catch; any store failure (e.g. cache backend hiccup) maps to the same documented `502 PLACES_UPSTREAM_ERROR` envelope the provider-failure branch uses, instead of bubbling up as an undocumented generic 500. Both catch branches now share a private `throwUpstreamError()` helper.
  3. `MockPlacesProvider` — the `SIMULATE_PROVIDER_ERROR_QUERY` sentinel is now gated behind `process.env['NODE_ENV'] !== 'production'`, so a real Owner typing that literal string into a production address field can never trigger a fake upstream failure (MockPlacesProvider is the only bound provider in every environment today).
  4. `PlacesService`'s error logging — replaced `this.logger.error(message, { error })` (which logged `[object Object]` as the "trace" arg) with `error instanceof Error ? error.stack : String(error)`, matching how `GlobalExceptionFilter` extracts stack traces elsewhere in the repo. Centralized in the new `throwUpstreamError()` helper.
  5. Closed 3 test-coverage gaps where only mocks, never real code, were exercised: added `places-rate-limit.store.spec.ts` (real class, `CACHE_MANAGER` mocked) covering new-window/increment/expiry-preservation/per-key-isolation behavior; added `mock-places.provider.spec.ts` (real, DI-bound provider) covering the fixture match, empty result, the `SIMULATE_PROVIDER_ERROR_QUERY` sentinel actually rejecting, and the production-gate from fix #3; extended `test/places.e2e-spec.ts` with a case that drives the real rate limiter (via the real `CACHE_MANAGER`, not a mock) past `RATE_LIMIT_MAX` and asserts a genuine `429 RATE_LIMITED`, plus missing/empty `sessionToken` cases. Also added a `places.service.spec.ts` case for fix #2 (rate-limit store throwing → 502, provider never called).
  6. `places.module.ts` comment — corrected a factually wrong claim ("mirrors CustomersModule's own imports list, but empty" — `CustomersModule` actually imports `SupabaseModule`); reworded to state `PlacesModule` is unlike most other feature modules in not needing DB access.
  - Re-ran Verification commands after all patches: `bun run build` clean, `bun run test -- places` (15 tests, 3 suites) pass, `bun run test:e2e -- places` (8 tests) pass, full `bun run test` (345 tests, 23 suites) pass with no regressions.

## Design Notes

`PlacesModule` is deliberately DB-less, consistent with AD-2 from the architecture spine. `MockPlacesProvider` is the only binding in this spec — swapping in `GooglePlacesProvider` later is a `useClass` change in `places.module.ts` plus the deferred work item, no other code impact.

## Verification

**Commands:**
- `bun run test -- places` -- expected: `places.service.spec.ts` passes, covering happy path / empty result / rate-limit / provider-failure cases
- `bun run build` -- expected: no TypeScript errors, `PlacesModule` registers cleanly in `app.module.ts`

**Manual checks (if no CLI):**
- Confirm `GOOGLE_PLACES_API_KEY` appears in the Joi schema and the app fails fast at boot if unset

## Suggested Review Order

**Provider abstraction (the DI-swap seam)**

- Single-method abstract contract a future `GooglePlacesProvider` slots into with zero controller/service changes.
  [`places-provider.ts:14`](../../workspace/core/backend/fenzit-be/src/places/places-provider.ts#L14)

- Mock implementation bound today; its error-simulation sentinel is gated to non-production only.
  [`mock-places.provider.ts:46`](../../workspace/core/backend/fenzit-be/src/places/mock-places.provider.ts#L46)

- Sentinel constant plus the `NODE_ENV !== 'production'` gate added during code review.
  [`mock-places.provider.ts:17`](../../workspace/core/backend/fenzit-be/src/places/mock-places.provider.ts#L17), [`mock-places.provider.ts:69`](../../workspace/core/backend/fenzit-be/src/places/mock-places.provider.ts#L69)

**Request flow: rate limiting, provider call, error mapping**

- Core service logic: per-tenant rate-limit check, provider delegation, shared upstream-error mapping.
  [`places.service.ts:27`](../../workspace/core/backend/fenzit-be/src/places/places.service.ts#L27)

- Rate-limit store failure now caught here too, not just provider failure — closes the undocumented-500 gap.
  [`places.service.ts:40`](../../workspace/core/backend/fenzit-be/src/places/places.service.ts#L40)

- Shared helper: logs a real stack trace and throws the documented 502 envelope for both failure branches.
  [`places.service.ts:76`](../../workspace/core/backend/fenzit-be/src/places/places.service.ts#L76)

- In-memory counter backing the rate limit, mirroring the existing OTP store's increment pattern.
  [`places-rate-limit.store.ts:20`](../../workspace/core/backend/fenzit-be/src/places/places-rate-limit.store.ts#L20)

**HTTP surface: auth, validation, wiring**

- Route + auth decorator; delegates straight to the service with no extra logic.
  [`places.controller.ts:22`](../../workspace/core/backend/fenzit-be/src/places/places.controller.ts#L22)

- Query DTO — trim + max-length added during review so whitespace-only input fails validation, not the rate limiter.
  [`autosuggest-query.dto.ts:6`](../../workspace/core/backend/fenzit-be/src/places/dto/autosuggest-query.dto.ts#L6)

- Module wiring: DB-less by design, `MockPlacesProvider` bound as the current default.
  [`places.module.ts:10`](../../workspace/core/backend/fenzit-be/src/places/places.module.ts#L10), [`places.module.ts:18`](../../workspace/core/backend/fenzit-be/src/places/places.module.ts#L18)

- App-level registration and the new required env var enforced at boot.
  [`app.module.ts:44`](../../workspace/core/backend/fenzit-be/src/app.module.ts#L44), [`app.module.ts:80`](../../workspace/core/backend/fenzit-be/src/app.module.ts#L80)

- New error codes distinct from the existing OTP rate-limit code, named exactly per spec.
  [`error-code.enum.ts:14`](../../workspace/core/backend/fenzit-be/src/common/enums/error-code.enum.ts#L14)

**Tests (peripherals)**

- Service-level unit tests, including the review-added rate-limit-store-throws case.
  [`places.service.spec.ts:123`](../../workspace/core/backend/fenzit-be/src/places/places.service.spec.ts#L123)

- Real rate-limit store exercised directly (not mocked) — new per review.
  [`places-rate-limit.store.spec.ts:25`](../../workspace/core/backend/fenzit-be/src/places/places-rate-limit.store.spec.ts#L25)

- Real, DI-bound mock provider exercised directly, including the production-gate — new per review.
  [`mock-places.provider.spec.ts:54`](../../workspace/core/backend/fenzit-be/src/places/mock-places.provider.spec.ts#L54)

- E2E: real HTTP pipeline through auth guards and, since review, the real rate limiter driven to a genuine 429.
  [`places.e2e-spec.ts:145`](../../workspace/core/backend/fenzit-be/test/places.e2e-spec.ts#L145)

- Env placeholder for the new required var.
  [`.env.example:19`](../../workspace/core/backend/fenzit-be/.env.example#L19)
