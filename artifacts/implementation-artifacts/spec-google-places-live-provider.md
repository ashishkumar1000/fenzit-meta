---
title: 'Backend — Real GooglePlacesProvider (live Google Places integration)'
type: 'feature'
created: '2026-09-05'
status: 'done'
review_loop_iteration: 0
context: []
baseline_commit: 'eb425d1a4e8669aaaa567e176d104dd25d6d69ea'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** `PlacesModule` only has `MockPlacesProvider` bound (`places.module.ts:16-19`) — no request ever reaches real Google, even though `GOOGLE_PLACES_API_KEY` is already required in the env schema (`app.module.ts:44`) and a real key has since been supplied and manually verified against live Google endpoints (2026-09-05, `deferred-work.md`).

**Approach:** Add `GooglePlacesProvider` (`src/places/google-places.provider.ts`) implementing `autosuggest()`/`resolve()` over Bun's native `fetch` + `AbortSignal.timeout(4000)`, using the exact response shapes confirmed during manual verification. `PlacesModule`'s `PlacesProvider` binding becomes `NODE_ENV`-conditional (`useFactory`): `GooglePlacesProvider` in production, `MockPlacesProvider` everywhere else — mirroring the `NODE_ENV !== 'production'` gate convention already in `mock-places.provider.ts`, so today's e2e suite (which boots the full `AppModule` with no `PlacesProvider` override) keeps exercising the mock unchanged.

## Boundaries & Constraints

**Always:**
- `GooglePlacesProvider` has the same injectable shape as `MockPlacesProvider`: `constructor(private readonly configService: ConfigService)`, reads `GOOGLE_PLACES_API_KEY` via `getOrThrow`.
- API key is sent only as the `X-Goog-Api-Key` header — never logged, never in a query string or response body.
- Autosuggest maps Google's actual nested response `suggestions[].placePrediction.{placeId, text.text}` into `PlaceSuggestion[] {placeId, text}` — never expose Google's raw shape to callers. Always sends `includedRegionCodes: ['IN']` and the caller's `sessionToken`.
- Resolve always uses field mask `id,formattedAddress,location,addressComponents,postalAddress` (Essentials tier only, already approved in Story 1.2 — never add `displayName`/Pro-tier fields). Reads `pincode` as `postalAddress?.postalCode ?? null` (never assumes `postalAddress` exists — confirmed absent entirely for some places) and `city` from the `addressComponents` entry typed `locality`, `?? null` if absent.
- If Google returns a valid place with `location` absent, `resolve()` throws — never a null-coordinate success (same contract `MockPlacesProvider` already honors).
- Any HTTP-level failure (non-2xx, network error, timeout/abort) from either method throws a plain `Error` — `PlacesService`'s existing generic catch-and-map-to-502 logic (`places.service.ts:52-65,84-92,134-150`) requires zero changes.
- `PlacesModule`'s `PlacesProvider` binding becomes a `useFactory` keyed on `NODE_ENV === 'production'`, injecting `ConfigService` — decided with the human up front specifically so the existing e2e suite (`NODE_ENV` not `'production'` under Jest) keeps resolving `MockPlacesProvider`, unchanged.
- `MockPlacesProvider` itself is untouched.

**Ask First:** None — the DI-selection mechanism (`NODE_ENV`-conditional vs. a dedicated env var vs. unconditional swap) was already resolved with the human before this spec was drafted.

**Never:** Do not add request/response logging that could leak the API key. Do not add a new HTTP-mocking dependency (`nock`/`msw`) — stub Bun's global `fetch` directly in tests (`jest.spyOn(global, 'fetch')`); none exists in this repo today. Do not change `MockPlacesProvider`, `PlacesService`'s error mapping, or any DTO/response shape.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Happy path autosuggest | Valid query/sessionToken, `NODE_ENV=production` | Google 2xx mapped to `PlaceSuggestion[]` | N/A |
| Happy path resolve | Valid placeId/sessionToken, `NODE_ENV=production`, `location` present | `ResolvedPlace {...}` returned | N/A |
| Resolve — `location` absent | Google 200, valid place, no `location` | Provider throws | Maps to existing 502 `PLACES_UPSTREAM_ERROR` |
| Resolve — `postalAddress` absent | Google 200, no `postalAddress` block at all | `pincode: null`, other fields present | N/A |
| Upstream non-2xx | Google returns 4xx/5xx | Provider throws | Maps to existing 502 |
| Timeout | Google doesn't respond within 4000ms | `AbortSignal` fires, provider throws | Maps to existing 502 |
| Non-production env | `NODE_ENV !== 'production'` | Module binds `MockPlacesProvider`; `GooglePlacesProvider` never instantiated/called | N/A |

</frozen-after-approval>

## Code Map

- `workspace/core/backend/fenzit-be/src/places/places-provider.ts:16-23,30-41` -- reference only; `ResolvedPlace`/`PlaceSuggestion`/abstract method signatures `GooglePlacesProvider` must implement exactly
- `workspace/core/backend/fenzit-be/src/places/google-places.provider.ts` -- new file; `GooglePlacesProvider extends PlacesProvider`, Bun `fetch` + `AbortSignal.timeout(4000)` for both methods
- `workspace/core/backend/fenzit-be/src/places/mock-places.provider.ts:106-113` -- reference only; constructor/`ConfigService` pattern to mirror (file itself untouched)
- `workspace/core/backend/fenzit-be/src/places/places.module.ts:16-19` -- change `PlacesProvider` binding from `useClass: MockPlacesProvider` to a `NODE_ENV`-conditional `useFactory` (`inject: [ConfigService]`)
- `workspace/core/backend/fenzit-be/src/places/places.service.ts:52-65,84-92,134-150` -- reference only; existing generic error mapping already sufficient, no change
- `workspace/core/backend/fenzit-be/src/app.module.ts:44` -- reference only; `GOOGLE_PLACES_API_KEY` already required
- `workspace/core/backend/fenzit-be/src/places/google-places.provider.spec.ts` -- new; mirrors `mock-places.provider.spec.ts`'s shape (top-level describe + nested `resolve` describe), stubs `global.fetch` via `jest.spyOn`
- `workspace/core/backend/fenzit-be/test/places.e2e-spec.ts` -- no change expected; boots full `AppModule` with no `PlacesProvider` override, so must keep passing unchanged once the module binding is `NODE_ENV`-conditional

## Tasks & Acceptance

**Execution:**
- [x] `src/places/google-places.provider.ts` -- implement `GooglePlacesProvider` (`autosuggest()`, `resolve()`, Bun `fetch`, timeout, response-shape mapping, error throwing) -- the live integration
- [x] `src/places/places.module.ts` -- swap `PlacesProvider` binding to a `NODE_ENV`-conditional `useFactory` -- production uses the real provider, everything else keeps using Mock
- [x] `src/places/google-places.provider.spec.ts` -- unit tests covering the I/O matrix via stubbed `global.fetch` -- verifies mapping/error-handling with no real network calls
- [x] `test/places.e2e-spec.ts` -- run existing suite unmodified and confirm it still passes -- proves the conditional binding doesn't disturb current coverage

**Acceptance Criteria:**
- Given `NODE_ENV=production`, when `PlacesModule` resolves `PlacesProvider`, then it is a `GooglePlacesProvider` instance backed by `GOOGLE_PLACES_API_KEY`
- Given `NODE_ENV!=='production'`, then `PlacesProvider` resolves to `MockPlacesProvider`, unchanged from today
- Given a real Google autosuggest call succeeds, then the nested `placePrediction` shape is normalized to `{placeId, text}`
- Given a real Google resolve call succeeds with `location` present, then `ResolvedPlace {...}` is returned with `pincode`/`city` null-safe per the `postalAddress`/`addressComponents` edge cases
- Given a real Google resolve call succeeds but `location` is absent, then the provider throws — never a null-coordinate success
- Given any Google HTTP failure/timeout, then the provider throws a plain `Error`, requiring zero changes to `PlacesService`'s existing 502 mapping

## Design Notes

This is the first real outbound-HTTP provider in the codebase (no `fetch`/`AbortSignal` precedent exists elsewhere, confirmed by investigation) — tests stub Bun's global `fetch` manually (`jest.spyOn(global, 'fetch').mockResolvedValue(...)` / `mockRejectedValue(...)`) rather than following an existing pattern, and no new HTTP-mocking dependency is introduced.

## Verification

**Commands:**
- `bun run test -- places` -- expected: `google-places.provider.spec.ts` passes alongside existing `mock-places.provider.spec.ts`/`places.service.spec.ts`
- `bun run test:e2e -- places` -- expected: unchanged pass (Jest's `NODE_ENV` stays non-production, so Mock is exercised)
- `bun run build` -- expected: no TypeScript errors

**Manual checks (if no CLI):**
- With a real `GOOGLE_PLACES_API_KEY` and `NODE_ENV=production` locally, hit `/places/autosuggest` and `/places/resolve/:placeId` once each against real Google to confirm end-to-end wiring through this new provider code (the shapes themselves were already manually verified 2026-09-05, per `deferred-work.md`). Attempted from the sandboxed dev environment; blocked by the same TLS-interception artifact already documented in `deferred-work.md` (`SELF_SIGNED_CERT_IN_CHAIN`). Not run — automated coverage (below) pins the mapping logic; a real end-to-end hit would need to run from outside the sandbox.

## Suggested Review Order

- **DI binding — the core risk area.** `PlacesModule`'s binding is now `NODE_ENV`-conditional; a broken condition here would silently send production traffic to the mock or vice versa. The factory was extracted to a named export specifically so this branch has direct unit coverage, not just e2e-by-implication.
  [`places.module.ts:12-19`](../../workspace/core/backend/fenzit-be/src/places/places.module.ts#L12)
  [`places.module.spec.ts`](../../workspace/core/backend/fenzit-be/src/places/places.module.spec.ts)
- **Live provider — request construction and response mapping.** API key only in the `X-Goog-Api-Key` header; field mask restricted to Essentials tier; nested Google response shapes normalized to this codebase's own contract.
  [`google-places.provider.ts`](../../workspace/core/backend/fenzit-be/src/places/google-places.provider.ts)
- **Null-safety on `pincode`/`city` (amended after review).** Empty-string values from Google now normalize to `null`, matching `ResolvedPlace`'s documented contract ("never omitted or `''`") — the original pass only handled `undefined`/absent.
  [`google-places.provider.ts:163`](../../workspace/core/backend/fenzit-be/src/places/google-places.provider.ts#L163)
- **Error/timeout behavior.** Any non-2xx or aborted `fetch` throws a plain `Error`; confirmed `PlacesService`'s existing 502 mapping needs zero changes.
  [`google-places.provider.ts:79-151`](../../workspace/core/backend/fenzit-be/src/places/google-places.provider.ts#L79)
- **Test coverage.** Full I/O matrix (happy paths, absent `postalAddress`, no-`locality` component, empty-string normalization, `location`-absent throw, non-2xx, timeout) plus the DI-binding branch.
  [`google-places.provider.spec.ts`](../../workspace/core/backend/fenzit-be/src/places/google-places.provider.spec.ts)
  [`places.module.spec.ts`](../../workspace/core/backend/fenzit-be/src/places/places.module.spec.ts)
</content>
