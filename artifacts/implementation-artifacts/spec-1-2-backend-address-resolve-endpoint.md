---
title: 'Backend — Address resolve endpoint'
type: 'feature'
created: '2026-09-05'
status: 'done'
review_loop_iteration: 0
context: []
baseline_commit: 'e621167d7748f364f541e3e327737013d67a1d56'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** After an owner picks a suggestion from address autosuggest (Story 1.1), the app only has a `placeId` and short text — it still needs the formatted address, pincode, and coordinates to save a verified address against the customer, without the Google API key ever reaching the client.

**Approach:** Add `GET /places/resolve/:placeId?sessionToken=` to the existing `PlacesModule`, proxying Google Place Details (New) via a new `PlacesProvider.resolve()` method on the same abstract-provider/DI-swap seam Story 1.1 established, with `MockPlacesProvider` as the only binding today (real `GooglePlacesProvider` remains deferred, per `deferred-work.md`).

## Boundaries & Constraints

**Always:**
- Same auth as Story 1.1: global `JwtAuthGuard` + `@Roles(Role.OWNER)`.
- `PlacesProvider.resolve(placeId, sessionToken, region: 'IN'): Promise<ResolvedPlace>` is a new abstract method alongside the existing `autosuggest()` — zero changes to `autosuggest()`'s signature or behavior.
- Response shape: `ResolvedPlace { placeId, formattedAddress, city: string|null, pincode: string|null, latitude: number, longitude: number }`. `city`/`pincode` are `null` when absent, never omitted or `''`.
- The contract guarantees `latitude`/`longitude` are always real numbers when `resolve()` resolves successfully — a provider that cannot obtain coordinates for an otherwise-valid place must throw (never return a null/placeholder coordinate), so this maps to the same `502 PLACES_UPSTREAM_ERROR` path as any other provider failure.
- Independent rate-limit budget from autosuggest, same `PlacesRateLimitStore.increment()` instance, key suffix `:resolve` (store already prefixes with `places:rate:`) — reuse the existing tenant-key fallback (`user.tenantId ?? user.userId`).
- `PlacesModule` stays DB-less; no new imports.
- Reuse the existing `ErrorCode.RATE_LIMITED` / `ErrorCode.PLACES_UPSTREAM_ERROR` — no new error codes.

**Ask First:** None — this narrows an already-approved epic story with no new architectural decisions.

**Never:** Do not implement `GooglePlacesProvider` or a real Google network call (deferred). Do not touch `POST /customers` or any customer schema/persistence field (Story 1.3). Do not add a 404/`RESOURCE_NOT_FOUND` path — out of this story's approved AC; an unresolvable `placeId` is a provider failure (502), not a distinct not-found case.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Happy path | Valid JWT+Owner, known `placeId`, `sessionToken=<uuid>` | `MockPlacesProvider` returns fixture; `200 ResolvedPlace {...}` | N/A |
| Nullable fields | `placeId` whose fixture lacks a pincode/city (sublocality-level result) | `200` with `pincode: null` and/or `city: null`, never `''`/omitted | N/A |
| No auth | Missing/invalid JWT or non-Owner role | Rejected before handler runs | 401/403 via global guards |
| Rate limit tripped | Same tenant exceeds `places:rate:{tenantId}:resolve` budget | Request rejected before calling the provider | `429 RATE_LIMITED` |
| Provider throws (incl. location absent) | Mock simulates failure, or `placeId` matches no fixture | No resolved place available | `502 PLACES_UPSTREAM_ERROR` |
| Missing `sessionToken` | Query param omitted or blank | Rejected before handler runs | `422` validation error |

</frozen-after-approval>

## Code Map

- `src/places/places-provider.ts:1-20` -- add `ResolvedPlace` interface (near `PlaceSuggestion`, line 4-7) and abstract `resolve(placeId, sessionToken, region: PlacesRegion): Promise<ResolvedPlace>` (after line 19), reusing the existing `PlacesRegion` type (line 2)
- `src/places/mock-places.provider.ts:17` -- mirror `SIMULATE_PROVIDER_ERROR_QUERY` pattern for a new `SIMULATE_RESOLVE_ERROR_PLACE_ID` sentinel, same `NODE_ENV !== 'production'` gate (lines 68-71); add `FIXTURE_RESOLVED_PLACES: Record<string, ResolvedPlace>` keyed by the same placeIds already in `FIXTURE_SUGGESTIONS` (lines 20-43: `mock-place-andheri-west-1`, `-2`, `mock-place-bandra-1`, `mock-place-koramangala-1`) plus one extra fixture with `pincode: null`/`city: null` for the nullable-matrix row; add `resolve()` after `autosuggest()` (after line 82) -- any placeId not in the fixture map (including the sentinel) throws, mirroring `autosuggest`'s error path
- `src/places/places-rate-limit.store.ts` -- no change; generic `increment(key, ttlSeconds)` (line 20) already reusable as-is
- `src/places/places.service.ts:7-12` -- add `RESOLVE_RATE_LIMIT_WINDOW_SECONDS = 60`, `RESOLVE_RATE_LIMIT_MAX = 10` (lower than autosuggest's 30 -- fires once per selection, not per keystroke); add `resolve(user, placeId, sessionToken): Promise<ResolvedPlace>` mirroring `autosuggest()` (lines 27-73) with rate-limit key `` `${tenantKey}:resolve` ``; extend `throwUpstreamError` (line 76) with a `userMessage` param so resolve's 502 body reads "Unable to resolve the selected address right now" instead of autosuggest's wording -- both call sites pass their own message
- `src/places/places.controller.ts:1,36-41` -- add `Param` to the `@nestjs/common` import (line 1); new `@Get('resolve/:placeId') @Roles(Role.OWNER)` handler mirroring `autosuggest()` (lines 22-41), `@Param('placeId') placeId: string` + `@Query() query: ResolveQueryDto`
- `src/places/places.module.ts` -- no change; `resolve()` reuses the existing `PlacesProvider` DI token and `PlacesRateLimitStore` provider
- `src/places/dto/autosuggest-query.dto.ts:17-26` -- copy the `sessionToken` field verbatim (same `@Transform(trim)`/`@IsString()`/`@IsNotEmpty()`/`@MaxLength(100)`) into new `src/places/dto/resolve-query.dto.ts` (`ResolveQueryDto`, `sessionToken` only)
- `src/places/dto/autosuggest-response.dto.ts` -- mirror pattern (plain `@ApiProperty()` fields, no validation decorators) into new `src/places/dto/resolve-response.dto.ts` (`ResolvedPlaceDto`: `placeId`, `formattedAddress`, `city: string | null`, `pincode: string | null`, `latitude: number`, `longitude: number`)
- `src/common/enums/error-code.enum.ts:14-15` -- no change; `RATE_LIMITED`/`PLACES_UPSTREAM_ERROR` already generic, reused as-is
- `src/places/places.service.spec.ts`, `src/places/mock-places.provider.spec.ts`, `test/places.e2e-spec.ts` -- existing `describe` blocks for `autosuggest`/`MockPlacesProvider`/e2e to mirror; add sibling `describe`/`it` blocks for `resolve` (see Tasks)
- `src/app.module.ts:21,44,80` -- no change; `PlacesModule` and `GOOGLE_PLACES_API_KEY` already registered

## Tasks & Acceptance

**Execution:**
- [x] `src/places/places-provider.ts` -- add `ResolvedPlace` interface + abstract `resolve(placeId, sessionToken, region)` method
- [x] `src/places/mock-places.provider.ts` -- add `SIMULATE_RESOLVE_ERROR_PLACE_ID` sentinel (non-production gated), `FIXTURE_RESOLVED_PLACES` map (including one nullable-fields fixture), `resolve()` method
- [x] `src/places/dto/resolve-query.dto.ts` -- `ResolveQueryDto` (`sessionToken` only, same validation as autosuggest's)
- [x] `src/places/dto/resolve-response.dto.ts` -- `ResolvedPlaceDto` response shape
- [x] `src/places/places.service.ts` -- `RESOLVE_RATE_LIMIT_WINDOW_SECONDS`/`RESOLVE_RATE_LIMIT_MAX` constants, `resolve()` method (rate-limit check/increment, provider delegation, error mapping), parametrize `throwUpstreamError`'s user-facing message
- [x] `src/places/places.controller.ts` -- `GET /places/resolve/:placeId` handler (`@Roles(Role.OWNER)`, `@Param`, `@Query`), matching `@ApiResponse` decorators (401/403/422/429/502)
- [x] `src/places/places.service.spec.ts` -- unit tests for the I/O matrix (happy path, nullable fields, rate-limit, provider-failure, rate-limit-store-throws)
- [x] `src/places/mock-places.provider.spec.ts` -- unit tests for the real `resolve()` (fixture match incl. nullable fixture, sentinel rejection, production-gate, unknown-placeId rejection)
- [x] `test/places.e2e-spec.ts` -- extend with `describe('GET /api/v1/places/resolve/:placeId', ...)`: 401, 403, 200 happy path, 200 nullable fields, 422 missing `sessionToken`, 429 (real rate limiter driven to `RESOLVE_RATE_LIMIT_MAX`), 502 provider failure

**Acceptance Criteria:**
- Given a valid JWT with Owner role, a known `placeId`, and `sessionToken`, when `GET /places/resolve/:placeId?sessionToken=` is called, then it returns `200 ResolvedPlace {placeId, formattedAddress, city, pincode, latitude, longitude}`
- Given a request without a valid JWT or Owner role, then it is rejected 401/403 via the existing global guards
- Given the `places:rate:{tenantId}:resolve` budget is exhausted, then it returns `429 RATE_LIMITED` without calling the provider, independent of the autosuggest budget
- Given the provider throws (including an otherwise-valid place with no resolvable location), then the endpoint returns `502 PLACES_UPSTREAM_ERROR`, never a null-coordinate `200`
- Given a resolved place with no pincode or city, then those fields are `null`, never omitted or `''`

## Design Notes

`resolve()` mirrors `autosuggest()`'s shape end-to-end (rate-limit → provider call → error mapping) so a future `GooglePlacesProvider` slots into both methods identically. `MockPlacesProvider`'s fixture map reuses the same `placeId`s already returned by `autosuggest`'s fixtures, so a full mock autosuggest→resolve round trip is testable without inventing parallel IDs. An unrecognized `placeId` (never issued by autosuggest) and the explicit error sentinel both throw the same generic error — the mock has no way to distinguish "not found" from "upstream failure" any more meaningfully than a real Google error would without deeper parsing, and this story's approved AC only requires the 502 path, not a 404.

## Verification

**Commands:**
- `bun run test -- places` -- expected: `places.service.spec.ts` and `mock-places.provider.spec.ts` pass, covering the resolve I/O matrix
- `bun run test:e2e -- places` -- expected: new resolve `describe` block passes alongside existing autosuggest cases
- `bun run build` -- expected: no TypeScript errors

## Suggested Review Order

**Provider contract: the new `resolve()` seam**

- `ResolvedPlace` contract and abstract `resolve()` signature added alongside `autosuggest()` — same DI-swap seam, zero change to the existing method.
  [`places-provider.ts:16`](../../workspace/core/backend/fenzit-be/src/places/places-provider.ts#L16)

- Mock `resolve()` implementation: sentinel error path, then a prototype-safe fixture lookup (`hasOwnProperty` guard added during code review — an unguarded `FIXTURE_RESOLVED_PLACES[placeId]` lookup would have let a placeId like `'constructor'` return an inherited `Object.prototype` value instead of throwing).
  [`mock-places.provider.ts:142`](../../workspace/core/backend/fenzit-be/src/places/mock-places.provider.ts#L142), [`mock-places.provider.ts:159`](../../workspace/core/backend/fenzit-be/src/places/mock-places.provider.ts#L159)

**Request flow: independent rate limit, provider call, error mapping**

- `resolve()` service method, using the shared `enforceRateLimit` helper (extracted during code review to remove duplication with `autosuggest()`'s identical inline block) with its own `:resolve` budget/key.
  [`places.service.ts:68`](../../workspace/core/backend/fenzit-be/src/places/places.service.ts#L68), [`places.service.ts:104`](../../workspace/core/backend/fenzit-be/src/places/places.service.ts#L104)

**HTTP surface: route, path param, DTOs**

- `GET /places/resolve/:placeId` handler, now with an `@ApiParam` for the path segment (added during code review for Swagger completeness).
  [`places.controller.ts:53`](../../workspace/core/backend/fenzit-be/src/places/places.controller.ts#L53), [`places.controller.ts:59`](../../workspace/core/backend/fenzit-be/src/places/places.controller.ts#L59)

- Response DTO nullable fields (`city`, `pincode`).
  [`resolve-response.dto.ts:3`](../../workspace/core/backend/fenzit-be/src/places/dto/resolve-response.dto.ts#L3)

**Tests (peripherals)**

- Prototype-pollution regression test and the mock autosuggest→resolve round-trip test, both added during code review.
  [`mock-places.provider.spec.ts:130`](../../workspace/core/backend/fenzit-be/src/places/mock-places.provider.spec.ts#L130)

- E2E: real rate limiter driven to `RESOLVE_RATE_LIMIT_MAX`, nullable-fields happy path, and the 502 paths.
  [`places.e2e-spec.ts:172`](../../workspace/core/backend/fenzit-be/test/places.e2e-spec.ts#L172)
