- source_spec: `artifacts/implementation-artifacts/spec-1-1-backend-address-autosuggest-endpoint.md`
  summary: Implement `GooglePlacesProvider` — the real Google Places Autocomplete (New) integration (Bun `fetch`, field mask/region params, upstream error mapping) — as the live DI binding for `PlacesProvider`.
  evidence: Split off Story 1.1's spec to stay under the token ceiling, and because `GOOGLE_PLACES_API_KEY` has no real value yet — the live provider can't be exercised against real Google traffic until the user supplies a key, so it can't usefully ship (or be verified) alongside the module scaffold. The narrowed spec ships `PlacesModule` fully wired end-to-end with `MockPlacesProvider` as the DI default, satisfying every AC testable without a live key; swapping in `GooglePlacesProvider` is a follow-up `useClass` change with no other code impact once the key exists.
  followup_note: |
    A real API key was later supplied and manually verified against live Google endpoints (2026-09-05), confirming/correcting the assumed contract for this deferred provider:
    - Autocomplete (New) response is nested one level deeper than assumed: `suggestions[].placePrediction.{placeId, text.text, structuredFormat, types}` — NOT a flat `{placeId, text}`. `GooglePlacesProvider.autosuggest()` must read `s.placePrediction.placeId` / `s.placePrediction.text.text` and map into our own normalized `{placeId, text}` contract (the normalized shape in the epics/spec is our own endpoint's output, not Google's raw shape — no conflict, just the mapping detail).
    - Place Details (New) with the Essentials field mask (`id,formattedAddress,location,addressComponents,postalAddress`) works with no billing/tier error, and `location{latitude,longitude}`, `postalAddress.postalCode`, and an `addressComponents` entry typed `locality` all appear as assumed — for a specific-enough place.
    - Important edge case: for a broader/less-specific `placeId` (e.g. a sublocality-level result), `postalAddress` can be **entirely absent** from the response (not just missing `postalCode`), while `locality` may still be present. `GooglePlacesProvider.resolve()` must read pincode as `postalAddress?.postalCode ?? null`, never assume `postalAddress` exists — this is consistent with the already-approved AC that `pincode` is nullable, just flags a real code path to test.
    - `sessionToken` in the Autocomplete request body is accepted with no error.
    - The sandboxed dev environment's egress proxy does TLS interception (`curl` needed `-k` to reach `googleapis.com`); this is a local dev-sandbox artifact only, not expected in the deployed backend's runtime.

- source_spec: `artifacts/implementation-artifacts/spec-1-1-backend-address-autosuggest-endpoint.md`
  summary: Consider a backend-side minimum query length (defense-in-depth) on `GET /places/autosuggest`, not just the frontend's client-side 3-character debounce gate (Story 1.4 / UX-DR3).
  evidence: Surfaced during step-04 review (Blind Hunter layer). Today only the frontend enforces the 3-char minimum before firing a call; a direct API caller (buggy client, script, or future integration) could bypass that and fire single/two-character queries straight at the backend. Once the real `GooglePlacesProvider` is wired in, this becomes a real billing exposure, not just a wasted mock call. Not blocking for Story 1.1 (mock-only, no real Google cost yet) — worth adding when the deferred `GooglePlacesProvider` item is picked up.

- source_spec: `artifacts/implementation-artifacts/spec-1-1-backend-address-autosuggest-endpoint.md`
  summary: Add a `Retry-After` response header on the `429 RATE_LIMITED` response from `GET /places/autosuggest`.
  evidence: Surfaced during step-04 review (Blind Hunter layer). Without it, a typeahead client has no signal for how long to back off before retrying, and will likely just retry immediately, defeating the point of the limiter. Not required by Story 1.1's approved AC/I-O matrix (which only specifies the 429 status + error code), so not blocking — a client-experience polish for a later pass.

- source_spec: `artifacts/implementation-artifacts/spec-1-1-backend-address-autosuggest-endpoint.md`
  summary: Move the autosuggest rate-limit budget (`RATE_LIMIT_WINDOW_SECONDS = 60`, `RATE_LIMIT_MAX = 30` in `places.service.ts`) from hardcoded module constants to config/env, so it can be retuned without a redeploy.
  evidence: Surfaced during step-04 review (Blind Hunter layer). Already flagged transparently as a judgment call in the spec's own Spec Change Log at implementation time ("easy to retune later") — this entry just tracks the follow-up so it isn't forgotten. Low priority; not a defect, a tunability nice-to-have.

- source_spec: `artifacts/implementation-artifacts/spec-1-2-backend-address-resolve-endpoint.md`
  summary: Add format/length validation on the `placeId` path parameter of `GET /places/resolve/:placeId` (and URL-encoding/charset handling for real Google Place IDs), as defense-in-depth before the real `GooglePlacesProvider` makes an actual network call per request.
  evidence: Surfaced during step-04 review (Blind Hunter + Edge Case Hunter layers). Today `MockPlacesProvider`'s prototype-safe fixture lookup (fixed in this story's patch pass) already maps any bad `placeId` to the documented 502 path, so there's no defect with the mock — but once the deferred `GooglePlacesProvider` lands, an unbounded/malformed `placeId` reaching Google's API becomes a real billing/network-cost exposure, mirroring the already-deferred min-query-length item for autosuggest.

- source_spec: `artifacts/implementation-artifacts/spec-1-2-backend-address-resolve-endpoint.md`
  summary: Give `PlacesService`'s rate-limit-store-failure log message per-endpoint/per-branch specificity (it currently logs the identical text `'Places rate-limit store failed to increment:'` for both `autosuggest()` and `resolve()`, and doesn't distinguish a store failure from a provider failure in the log line itself).
  evidence: Surfaced during step-04 review (Blind Hunter layer). Both endpoints already map to the correct `502 PLACES_UPSTREAM_ERROR` response, so this is a production log-triage clarity improvement, not a functional defect — low priority polish.

- source_spec: `artifacts/implementation-artifacts/spec-1-2-backend-address-resolve-endpoint.md`
  summary: Add a runtime guard (e.g. `Number.isFinite`) on `ResolvedPlace.latitude`/`longitude` before `PlacesService.resolve()` returns, so a provider bug can't silently violate the documented "always real numbers, never null/placeholder" contract.
  evidence: Surfaced during step-04 review (Blind Hunter layer). Currently an unenforced doc-comment-only invariant on the `ResolvedPlace` interface; not exploitable via `MockPlacesProvider` (its fixtures are fixed, valid numbers), but becomes a real risk once the deferred `GooglePlacesProvider` parses external JSON and could return `NaN`/`undefined` for a malformed upstream response.

- source_spec: `artifacts/implementation-artifacts/spec-1-3-backend-persist-structured-address-on-customer-creation.md`
  summary: Extend `findOrCreateByPhone` (the job-creation "new customer" dedup/create path in `customers.service.ts`) and its `NewCustomerDto`/`FindOrCreateCustomerInput` to accept and persist the same 5 structured-address fields that `POST /customers` now does.
  evidence: Surfaced independently by all three step-04 review layers (Blind Hunter, Edge Case Hunter, Verification Gap) — strong convergent signal. This path was explicitly scoped out of Story 1.3 (`Never` clause), but it means a customer created via "add job with new customer" can never get structured-address data, an inconsistency between two customer-creation entry points sharing the same table/response contract. `NewCustomerDto`'s own doc comment says it "mirrors" `CreateCustomerDto`, and the global `ValidationPipe` (`whitelist: true`) silently strips any of the 5 fields if a caller sends them today.

- source_spec: `artifacts/implementation-artifacts/spec-1-3-backend-persist-structured-address-on-customer-creation.md`
  summary: Consider server-side re-verification of client-submitted `placeId`/`latitude`/`longitude`/`formattedAddress` against the Places provider before persisting, instead of trusting the create-customer payload wholesale.
  evidence: Surfaced during step-04 review (Verification Gap layer). Today nothing stops a client from submitting a `placeId` that doesn't correspond to the given coordinates/address — `createCustomer` never calls `PlacesProvider.resolve()` again to cross-check. Not a blocker (the resolve endpoint already validated the data once, client-side, in the same user flow), but worth a security/data-integrity look once the real `GooglePlacesProvider` is live and re-validation has a real cost/benefit tradeoff to weigh.

- source_spec: `artifacts/implementation-artifacts/spec-1-3-backend-persist-structured-address-on-customer-creation.md`
  summary: Add a `type:`/schema reference to the `GET /customers` list endpoint's `@ApiResponse` decorator (it has none today, unlike the detail endpoint which references `CustomerDetailResponseDto`), so the new structured-address fields (and existing `jobCount`/`lastJobDate`) are documented in the OpenAPI schema.
  evidence: Surfaced during step-04 review (Blind Hunter layer). Pre-existing gap on the list endpoint that this story's fields fall into — cosmetic/documentation only, not a functional defect.

- source_spec: `artifacts/implementation-artifacts/spec-google-places-live-provider.md`
  summary: Run one real end-to-end hit of `GooglePlacesProvider` (`NODE_ENV=production`) against live Google from outside the sandboxed dev environment, using the real `GOOGLE_PLACES_API_KEY` already in `.env`.
  evidence: Attempted from within the sandbox during step-04 verification; blocked by the same TLS-interception artifact already noted for the earlier manual `curl` verification (`SELF_SIGNED_CERT_IN_CHAIN`). Not blocking — `google-places.provider.spec.ts` pins the exact request/response mapping against the already-confirmed live response shapes via stubbed `fetch`, and `places.module.spec.ts` confirms the `NODE_ENV`-conditional binding resolves the right class. This is only the one remaining "did the real network path actually work" check, best run from the user's own terminal.

- source_spec: `artifacts/implementation-artifacts/spec-google-places-live-provider.md`
  summary: Add unit tests for two untested-but-plausibly-correct edge cases in `GooglePlacesProvider`: a malformed `suggestions[]` entry (missing `placePrediction`, or only one of `placeId`/`text` present) silently dropped rather than surfaced; and multiple `addressComponents` entries typed `locality` (currently the first one wins via `.find()`).
  evidence: Surfaced during step-04 review (Edge Case Hunter layer). Neither is a known defect — the current behavior (drop malformed suggestions, take first `locality` match) is reasonable and matches the spec's intent — but there's no regression test pinning either choice today.

- source_spec: `artifacts/implementation-artifacts/spec-1-4-frontend-address-search-screen.md`
  summary: After an autosuggest error/no-results/resolve-failed phase, the stale error banner/EmptyState stays on screen for the full ~300ms debounce window after the owner resumes typing, before clearing — reads as briefly unresponsive.
  evidence: Surfaced during step-04 review (Blind Hunter layer). `autosuggestError`/`resolveError` only clear inside `fetchSuggestions` or the below-threshold branch, not immediately on `query` change. Not a spec violation (no AC covers this), a UX polish item for a later pass.

- source_spec: `artifacts/implementation-artifacts/spec-1-4-frontend-address-search-screen.md`
  summary: `useAddressAutosuggest.ts`'s local `isAbort` helper duplicates logic the code comment says already exists in `JobDetailScreen` — extract to a shared `utils/` helper so a future abort-detection fix only needs to land in one place.
  evidence: Surfaced during step-04 review (Blind Hunter layer). Not a functional defect today; a simplification that would touch `JobDetailScreen.tsx`, outside this story's file boundary.

- source_spec: `artifacts/implementation-artifacts/spec-1-4-frontend-address-search-screen.md`
  summary: `AddressPickerScreen`'s header back button has no explicit min touch-target sizing (~40px effective via icon + hitSlop), under the design system's ≥44px minimum.
  evidence: Surfaced during step-04 review (Blind Hunter layer). Copied verbatim from `NewJobScreen.tsx`'s existing back button — a pre-existing gap in that screen that this story's pattern-reuse propagates, not a defect newly introduced by this story's own logic.

- source_spec: `artifacts/implementation-artifacts/spec-1-5-frontend-return-selection-to-add-customer-bottomsheet.md`
  summary: File a follow-up story for `AddressPickerSheet`'s suggestion list rendering without a `ScrollView`/`FlatList` (plain `.map()` into a `View`, no in-sheet scrolling for a long result list).
  evidence: Surfaced during step-04 review (Blind Hunter layer). A deliberate, accepted trade-off made live during this session after `react-native-true-sheet`'s `scrollable` binding was found to leave real, successfully-fetched results invisible on-device (see the file's own doc comment and git history) — not a regression, but the "real fix pending an upstream resolution" has no tracked follow-up ticket today.
