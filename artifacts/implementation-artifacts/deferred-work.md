- source_spec: `artifacts/implementation-artifacts/spec-1-1-backend-address-autosuggest-endpoint.md`
  summary: RESOLVED (2026-09-09) — `GooglePlacesProvider` implemented and live: the live-credential check passed (2026-09-08, see the spec-google-places-live-provider entries below), and `places.module.ts` now binds it as the `PlacesProvider` DI default via a config factory (`createPlacesProvider` returns the Google provider whenever `GOOGLE_PLACES_API_KEY` is set, falling back to `MockPlacesProvider` otherwise) — so test/dev environments without a key keep the deterministic mock.
  evidence: Split off Story 1.1's spec to stay under the token ceiling, and because `GOOGLE_PLACES_API_KEY` has no real value yet — the live provider can't be exercised against real Google traffic until the user supplies a key, so it can't usefully ship (or be verified) alongside the module scaffold. The narrowed spec ships `PlacesModule` fully wired end-to-end with `MockPlacesProvider` as the DI default, satisfying every AC testable without a live key; swapping in `GooglePlacesProvider` is a follow-up `useClass` change with no other code impact once the key exists.
  followup_note: |
    A real API key was later supplied and manually verified against live Google endpoints (2026-09-05), confirming/correcting the assumed contract for this deferred provider:
    - Autocomplete (New) response is nested one level deeper than assumed: `suggestions[].placePrediction.{placeId, text.text, structuredFormat, types}` — NOT a flat `{placeId, text}`. `GooglePlacesProvider.autosuggest()` must read `s.placePrediction.placeId` / `s.placePrediction.text.text` and map into our own normalized `{placeId, text}` contract (the normalized shape in the epics/spec is our own endpoint's output, not Google's raw shape — no conflict, just the mapping detail).
    - Place Details (New) with the Essentials field mask (`id,formattedAddress,location,addressComponents,postalAddress`) works with no billing/tier error, and `location{latitude,longitude}`, `postalAddress.postalCode`, and an `addressComponents` entry typed `locality` all appear as assumed — for a specific-enough place.
    - Important edge case: for a broader/less-specific `placeId` (e.g. a sublocality-level result), `postalAddress` can be **entirely absent** from the response (not just missing `postalCode`), while `locality` may still be present. `GooglePlacesProvider.resolve()` must read pincode as `postalAddress?.postalCode ?? null`, never assume `postalAddress` exists — this is consistent with the already-approved AC that `pincode` is nullable, just flags a real code path to test.
    - `sessionToken` in the Autocomplete request body is accepted with no error.
    - The sandboxed dev environment's egress proxy does TLS interception (`curl` needed `-k` to reach `googleapis.com`); this is a local dev-sandbox artifact only, not expected in the deployed backend's runtime.

- source_spec: `artifacts/implementation-artifacts/spec-1-1-backend-address-autosuggest-endpoint.md`
  summary: RESOLVED (2026-09-08) — Backend-side minimum query length on `GET /places/autosuggest`: `AutosuggestQueryDto.q` now carries `@MinLength(3)` (exported as `MIN_AUTOSUGGEST_QUERY_LENGTH`), mirroring the FE 3-char debounce gate; sub-3-char queries get 422 before any provider call.
  evidence: Surfaced during step-04 review (Blind Hunter layer). Today only the frontend enforces the 3-char minimum before firing a call; a direct API caller (buggy client, script, or future integration) could bypass that and fire single/two-character queries straight at the backend. Once the real `GooglePlacesProvider` is wired in, this becomes a real billing exposure, not just a wasted mock call. Not blocking for Story 1.1 (mock-only, no real Google cost yet) — worth adding when the deferred `GooglePlacesProvider` item is picked up.

- source_spec: `artifacts/implementation-artifacts/spec-1-1-backend-address-autosuggest-endpoint.md`
  summary: RESOLVED (2026-09-08) — `Retry-After` header on places 429s: the 429 body now carries `retryAfterSeconds` (the window), which `GlobalExceptionFilter` lifts into a `Retry-After` response header (never sent as a body field). Applied to both autosuggest and resolve limiters.
  evidence: Surfaced during step-04 review (Blind Hunter layer). Without it, a typeahead client has no signal for how long to back off before retrying, and will likely just retry immediately, defeating the point of the limiter. Not required by Story 1.1's approved AC/I-O matrix (which only specifies the 429 status + error code), so not blocking — a client-experience polish for a later pass.

- source_spec: `artifacts/implementation-artifacts/spec-1-1-backend-address-autosuggest-endpoint.md`
  summary: RESOLVED (2026-09-08) — Rate-limit budgets moved to config/env: 4 optional Joi-validated vars (`PLACES_{AUTOSUGGEST,RESOLVE}_RATE_LIMIT_{MAX,WINDOW_SECONDS}`, declared in app.module.ts, documented in .env.example), read via ConfigService in `PlacesService.rateLimitBudget()` with fallback to the exported default constants (60s; 30 autosuggest / 10 resolve).
  evidence: Surfaced during step-04 review (Blind Hunter layer). Already flagged transparently as a judgment call in the spec's own Spec Change Log at implementation time ("easy to retune later") — this entry just tracks the follow-up so it isn't forgotten. Low priority; not a defect, a tunability nice-to-have.

- source_spec: `artifacts/implementation-artifacts/spec-1-2-backend-address-resolve-endpoint.md`
  summary: RESOLVED (2026-09-08) — Format/length validation on the `placeId` path parameter of `GET /places/resolve/:placeId`: new `PlaceIdParamsDto` (regex `^[A-Za-z0-9_-]{10,255}$`, validated by the global ValidationPipe) rejects malformed IDs with 422 before any provider call. Pattern verified compatible with real Google IDs, all mock fixtures, and the `__simulate_resolve_error__` sentinel; well-formed-but-unknown IDs still take the 502 path.
  evidence: Surfaced during step-04 review (Blind Hunter + Edge Case Hunter layers). Today `MockPlacesProvider`'s prototype-safe fixture lookup (fixed in this story's patch pass) already maps any bad `placeId` to the documented 502 path, so there's no defect with the mock — but once the deferred `GooglePlacesProvider` lands, an unbounded/malformed `placeId` reaching Google's API becomes a real billing/network-cost exposure, mirroring the already-deferred min-query-length item for autosuggest.

- source_spec: `artifacts/implementation-artifacts/spec-1-2-backend-address-resolve-endpoint.md`
  summary: RESOLVED (2026-09-08) — `PlacesService`'s rate-limit-store-failure log line is now per-endpoint: `enforceRateLimit` interpolates its `label` param into the message (`Places rate-limit store failed to increment (autosuggest|resolve):`), so autosuggest vs resolve store failures are distinguishable in logs. Provider-failure branches already had distinct messages.

- source_spec: `artifacts/implementation-artifacts/spec-1-2-backend-address-resolve-endpoint.md`
  summary: RESOLVED (2026-09-09) — `Retry-After` on places 429s now reports the time REMAINING in the window, not its full length: `PlacesRateLimitStore.increment()` returns `{ count, windowRemainingSeconds }` (ceil of remaining ms, minimum 1; a fresh window reports the full ttl), `PlacesService` puts `windowRemainingSeconds` in the 429 body's `retryAfterSeconds`, and the existing GlobalExceptionFilter lift into the `Retry-After` header is unchanged. Pinned by unit tests (mid-window trip asserts `retryAfterSeconds: 7`), store tests (ceil computation + ≥1 floor), and a ranged e2e assertion.
  evidence: The store-API change deferred here ("needs increment() to also return the key's TTL") is exactly what shipped — implemented as a result object rather than a second method/exposed TTL.

- source_spec: `artifacts/implementation-artifacts/spec-1-2-backend-address-resolve-endpoint.md`
  summary: RESOLVED (2026-09-08) — `PlacesService.resolve()`'s runtime guard now also rejects geographically-invalid coordinates (latitude outside `[-90,90]`, longitude outside `[-180,180]`) to the same 502 `PLACES_UPSTREAM_ERROR` as the NaN/Infinity check, with unit tests for the out-of-range and boundary-value (±90/±180 accepted) cases.
  evidence: Surfaced during the 2026-09-08 places-hardening review (Blind Hunter layer, deferred). No known provider path produces out-of-range-but-finite values; the range check is defense-in-depth beyond the requested NaN guard.
  evidence: Surfaced during step-04 review (Blind Hunter layer). Both endpoints already map to the correct `502 PLACES_UPSTREAM_ERROR` response, so this is a production log-triage clarity improvement, not a functional defect — low priority polish.

- source_spec: `artifacts/implementation-artifacts/spec-1-2-backend-address-resolve-endpoint.md`
  summary: RESOLVED (2026-09-08) — Runtime guard added in `PlacesService.resolve()`: non-finite (`NaN`/`Infinity`) `latitude`/`longitude` from any provider now maps to the documented 502 `PLACES_UPSTREAM_ERROR` (with a specific log line) instead of silently violating the "always real numbers" contract.
  evidence: Surfaced during step-04 review (Blind Hunter layer). Currently an unenforced doc-comment-only invariant on the `ResolvedPlace` interface; not exploitable via `MockPlacesProvider` (its fixtures are fixed, valid numbers), but becomes a real risk once the deferred `GooglePlacesProvider` parses external JSON and could return `NaN`/`undefined` for a malformed upstream response.

- source_spec: `artifacts/implementation-artifacts/spec-1-3-backend-persist-structured-address-on-customer-creation.md`
  summary: RESOLVED (2026-09-08) — `findOrCreateByPhone` now accepts and persists the 5 structured-address fields (`formattedAddress`, `pincode`, `latitude`, `longitude`, `placeId`): `NewCustomerDto` mirrors `CreateCustomerDto`'s validators, `FindOrCreateCustomerInput` and the insert in `customers.service.ts` were extended, unit + e2e tests pin the chain through the whitelist ValidationPipe. Deploy order: additive backend change → `fenzit-be` merges/deploys first; the visible behavior waits for the fenzo-app FE story (address picker on the job-creation flow), which can land anytime after.
  evidence: Implemented directly from the deferred item (no spec). BMAD code review (2026-09-08, 3 layers) passed with patches applied (e2e happy-path through POST /jobs, legacy-shape test fix, this doc entry). Open follow-up surfaced by review: when the phone already exists, the dedup path still ignores supplied address data (pre-existing for address/city, widened by this change) — decide update-vs-ignore when the FE wiring story lands.

- source_spec: `artifacts/implementation-artifacts/spec-1-3-backend-persist-structured-address-on-customer-creation.md`
  summary: Consider server-side re-verification of client-submitted `placeId`/`latitude`/`longitude`/`formattedAddress` against the Places provider before persisting, instead of trusting the create-customer payload wholesale.
  evidence: Surfaced during step-04 review (Verification Gap layer). Today nothing stops a client from submitting a `placeId` that doesn't correspond to the given coordinates/address — `createCustomer` never calls `PlacesProvider.resolve()` again to cross-check. Not a blocker (the resolve endpoint already validated the data once, client-side, in the same user flow), but worth a security/data-integrity look once the real `GooglePlacesProvider` is live and re-validation has a real cost/benefit tradeoff to weigh.

- source_spec: `artifacts/implementation-artifacts/spec-1-3-backend-persist-structured-address-on-customer-creation.md`
  summary: RESOLVED (2026-09-08) — `GET /customers` list 200 response now documents its schema: new `CustomerListItemDto` (mirrors the service's `CustomerListItem`, including the 5 structured-address fields plus `jobCount`/`lastJobDate`), composed into the generic `PaginatedResponse` envelope via the allOf/`getSchemaPath` pattern (no swagger CLI plugin, so `type:` can't take a generic).
  evidence: Surfaced during step-04 review (Blind Hunter layer). Pre-existing gap on the list endpoint that this story's fields fall into — cosmetic/documentation only, not a functional defect.

- source_spec: `artifacts/implementation-artifacts/spec-google-places-live-provider.md`
  summary: RESOLVED (2026-09-08) — One real end-to-end hit of `GooglePlacesProvider` against live Google: **LIVE CHECK PASSED**. `autosuggest("MG Road Bengaluru")` returned 5 suggestions with the nested `placePrediction` mapping correct; `resolve()` on the first returned real coordinates (12.9730884, 77.616979), city `Bengaluru` from the `locality` component, and `pincode: null` — a route-level place has no `postalAddress`, exercising exactly the `?? null` path predicted on 2026-09-05. Essentials-tier field mask produced no billing/tier error.
  evidence: Run via a throwaway bun script (deleted after use) instantiating the provider directly from the user's terminal. New environment fact: the TLS interception (`SELF_SIGNED_CERT_IN_CHAIN`) is machine-wide, NOT sandbox-only — the user's own terminal hits the same corporate proxy; the one-off ran with `NODE_TLS_REJECT_UNAUTHORIZED=0`. No code change needed; deployed runtime unaffected.

- source_spec: `artifacts/implementation-artifacts/spec-google-places-live-provider.md`
  summary: RESOLVED (2026-09-08) — Both edge cases now pinned in `google-places.provider.spec.ts`: a malformed `suggestions[]` entry (null/absent `placePrediction`, missing `placeId` or `text`) is silently dropped while well-formed entries survive; and the FIRST `locality` component wins when Google returns several (documents the `.find()` behaviour).
  evidence: Surfaced during step-04 review (Edge Case Hunter layer). Neither is a known defect — the current behavior (drop malformed suggestions, take first `locality` match) is reasonable and matches the spec's intent — but there's no regression test pinning either choice today.

- source_spec: `artifacts/implementation-artifacts/spec-1-4-frontend-address-search-screen.md`
  summary: RESOLVED (2026-09-09) — the stale error banner now clears the moment the input changes, not ~300ms later: a `useEffect` keyed on `query` in `useAddressAutosuggest.ts` clears `autosuggestError` immediately (and blanks the error-path's leftover empty-list state, guarded so ordinary typing with visible results never blanks the list mid-debounce); the resolve-failed banner clears on input the same way. Regression-pinned: banner-drop test (positive phase assertion) and a mid-debounce list-persistence test in `useAddressAutosuggest.test.tsx`.
  evidence: The guarded-blanking nuance (blank only when an error was actually showing, else the banner-free state re-classifies as a bogus 'no-results') was surfaced and pinned by the 2026-09-09 batch review.

- source_spec: `artifacts/implementation-artifacts/spec-1-4-frontend-address-search-screen.md`
  summary: RESOLVED (2026-09-09) — shared `src/utils/isAbort.ts` (barrel-exported) replaced all 4 local copies (`useAddressAutosuggest.ts`, `JobDetailScreen.tsx`, `TechJobDetailScreen.tsx`, `CustomerDetailScreen.tsx`); unit tests pin the `status === 0 && code === 'CANCELLED'` conjunction including discriminating negatives.

- source_spec: `artifacts/implementation-artifacts/spec-1-4-frontend-address-search-screen.md`
  summary: RESOLVED (2026-09-09) — icon-only header back buttons sized to the ≥44px touch-target minimum via the theme's `touch.min` token (explicit `minWidth`/`minHeight`, icon centred, `hitSlop={8}` kept): `NewJobScreen.tsx` first, then the same pattern's remaining copies found by review — `AddCustomerScreen.tsx`, `JobDetailScreen.tsx`, `TechJobDetailScreen.tsx`, `CustomerDetailScreen.tsx` (each inspected; only genuinely sub-44px icon-only buttons touched). Note: the original item named `AddressPickerScreen`, a screen replaced by `AddressPickerSheet` in Story 1.5 — the gap actually lived in the sibling screens that copied the pattern.
  evidence: Surfaced during step-04 review (Blind Hunter layer). Copied verbatim from `NewJobScreen.tsx`'s existing back button — a pre-existing gap in that screen that this story's pattern-reuse propagates, not a defect newly introduced by this story's own logic.

- source_spec: `artifacts/implementation-artifacts/spec-1-5-frontend-return-selection-to-add-customer-bottomsheet.md`
  summary: RESOLVED (2026-09-09) — follow-up story filed: `artifacts/implementation-artifacts/spec-1-6-frontend-addresspickersheet-scrollable-list.md` (status `backlog`). Tracks `AddressPickerSheet`'s suggestion list rendering without a `ScrollView`/`FlatList` (plain `.map()` into a `View`, no in-sheet scrolling for a long result list), the original on-device `scrollable` finding, and the re-evaluation order once react-native-true-sheet moves upstream. The underlying scroll fix itself remains open under that story.
  evidence: Surfaced during step-04 review (Blind Hunter layer). A deliberate, accepted trade-off made live during this session after `react-native-true-sheet`'s `scrollable` binding was found to leave real, successfully-fetched results invisible on-device (see the file's own doc comment and git history) — not a regression, but the "real fix pending an upstream resolution" has no tracked follow-up ticket today.

- source_spec: `artifacts/planning-artifacts/research/technical-client-side-image-compression-before-upl-2026-09-07/research.md`
  summary: RESOLVED (2026-09-08) — Gallery photos uploading uncompressed (up to 10 MB each). Fixed in fenzo-app commit `e7a3189` ("feat(technicianApp): downscale photo picks to 2048px q0.8 at the picker"): `photoPicker.ts` now exports `MAX_DIMENSION = 2048` + `PHOTO_QUALITY = 0.8` and passes them to BOTH `launchCamera` and `launchImageLibrary`; the 10 MB `validateAsset` check stays as a backstop. No new library added (react-native-image-resizer stayed ruled out), per the research decision.
  evidence: Research follow-up tracked outside the story files (BMAD deep-recon 2026-09-07 picked zero-dependency picker built-ins over any new library). Tests in `photoPicker.test.ts`. Only optional leftover from the research's verification gate: the on-device smoke test (iPhone HEIC "High Efficiency" photo via gallery multi-select + Android orientation check) — low risk since BE already accepts `image/heic`.

- source_spec: `artifacts/implementation-artifacts/spec-2-1-backend-expose-customer-coordinates-in-job-detail-response.md`
  summary: RESOLVED (2026-09-07) — No technician-role coverage for the new `latitude`/`longitude` fields in `getJobDetail`. Fixed directly (user-approved follow-up outside the story): both the unit technician test (`jobs.service.spec.ts` "allows a technician to view their own assigned job") and the e2e AC4 technician test (`jobs.e2e-spec.ts`) now assert the full `customer` object via `toEqual`, including the coordinates. Suites re-run green (69 unit / 96 e2e jobs).
  evidence: Surfaced during step-04 review (Blind Hunter layer). Pre-existing repo-wide pattern (the AC4 e2e test has always asserted just the id); not a defect in this story's change, a general test-depth gap.

- source_spec: `artifacts/implementation-artifacts/spec-2-1-backend-expose-customer-coordinates-in-job-detail-response.md`
  summary: WON'T DO (user decision, 2026-09-07) — Job-detail read hard-codes `latitude, longitude` in the customers select; any environment where the Story 1.3 migration hasn't applied gets a PostgREST schema error → 500 on the whole endpoint. User decided to take no action: the live database is in good shape (verified clean during review), and a migration/deploy-verification strategy will be considered later, once the product is complete.
  evidence: Surfaced during step-04 review (Verification Gap layer). Same coupling exists for Story 1.3's own read-back and every other select in the repo; live project verified clean via Supabase MCP during review. Migration-before-deploy is the repo workflow. If revisited post-launch, the lightest fix is a pre-deploy SQL check that verifies the required columns exist.

## Deferred from: code review (2026-09-08) — findOrCreateByPhone structured-address fields

- Dedup path drops supplied structured-address data when the phone already exists (`customers.service.ts` found-customer branch) — pre-existing for `address`/`city`, widened by the 5 new fields; decide update-vs-ignore when the fenzo-app FE wiring story lands.
- Whitespace-only strings pass validation and persist as `''` instead of null for `formattedAddress`/`placeId` (and pre-existing `address`/`city`) — fix at a shared transform, not per-DTO.
- RESOLVED (2026-09-08) — Validator-rejection tests for the new `NewCustomerDto` fields on the jobs path: 5 parametrized e2e cases in `jobs.e2e-spec.ts` (5-digit pincode, latitude > 90, longitude < -180, whitespace-only name, 2-digit phoneNumber) all assert 422 `VALIDATION_ERROR`, guarding against DTO copy-paste divergence.
- RESOLVED (2026-09-09) — File-local `trim` helper copies extracted to the shared `src/common/utils/trim.transformer.ts`. The original 3 copies (create-customer.dto, new-customer.dto, create-job.dto) plus 3 more identical copies found during the follow-up check (users/dto/update-profile.dto, users/dto/get-profile-query.dto, jobs/dto/list-jobs-query.dto) all import the shared helper now; full unit suite green after the swap.
- RESOLVED (2026-09-09) — Runtime range/NaN guard on customer-creation coordinates at the service interface: shared `hasInvalidCoordinates` (`src/common/utils/validate-coordinates.ts`) behind `CustomersService.assertValidCoordinates`, called by BOTH `findOrCreateByPhone` and `createCustomer` (review found the manual-create path equally exposed). Rationale note (corrected 2026-09-09): the DTO layer DOES reject NaN/out-of-range values (class-validator 0.15 `@IsNumber()` fails on NaN) — the guard is defense-in-depth for direct service callers that bypass the ValidationPipe, mirroring the `PlacesService.resolve` guard. Unit tests: 6 bad-coordinate cases per path + all four boundary corners accepted.
- RESOLVED (2026-09-09) — Four-way duplication of the structured-address field list collapsed: `StructuredAddressDto` base class (shared by `CreateCustomerDto` and `NewCustomerDto`, validators inherited), `StructuredAddressFields` interface (on `FindOrCreateCustomerInput`), and `structuredAddressColumns()` (single insert mapping). Residual nuance — the DTO class and service interface remain two parallel shapes — is tracked under the 2026-09-09 review defers below.

## Deferred from: code review (2026-09-09) — second easy-win batch (no spec)

Status after the same-day follow-up checks (2026-09-09): 4 of the original 8 resolved, 4 remain open.

RESOLVED (2026-09-09, follow-up checks):

- RESOLVED — Inherited-validator pinning: the jobs path was already pinned by e2e (the 2026-09-08 parametrized 422 cases — latitude > 90, longitude < -180, 5-digit pincode — are all inherited `StructuredAddressDto` validators firing through `NewCustomerDto`), and a new `structured-address.dto.spec.ts` now pins inheritance itself (MaxLength, pincode regex, range checks on a subclass). Fact-check finding: class-validator 0.15 REJECTS NaN via `@IsNumber()` — the earlier "NaN passes the DTO layer" claim (from the review and repeated in the coordinate-guard justification) was wrong; affected code comments were corrected. The service guard stands as defense-in-depth for direct (no-ValidationPipe) callers, not as a NaN hole fix.
- RESOLVED — OTP Retry-After parity: `InMemoryOtpSessionStore.increment()` now returns `{ count, windowRemainingSeconds }` (mirroring the places store's contract, including the ceil/≥1 floor), and the `requestOtp` 429 body carries `retryAfterSeconds`, which `GlobalExceptionFilter` lifts into the `Retry-After` header. `RATE_LIMIT_EXCEEDED` was deliberately kept distinct from the places `RATE_LIMITED` (both pre-date this work; changing it would break FE error matching). Pinned in `auth.service.spec.ts`.
- RESOLVED — DTO-layer cross-module import: `StructuredAddressDto` moved from `customers/dto/` to `common/dto/` (with its spec); `CreateCustomerDto` and `NewCustomerDto` now both import from `common` — the jobs→customers DTO dependency is gone, matching the service layer's stated boundary rationale.
- RESOLVED — 400-vs-422 status split: documented as intentional. Service-layer `BadRequestException` + `VALIDATION_ERROR` is an established repo convention ("Company setup required", "Unknown country code"); the DTO layer's 422 at the HTTP edge is the whitelist ValidationPipe's shape. The layers answer different questions (edge validation vs service-interface backstop), so no harmonization.

Still open (structural / flake-risk — not actionable now):

- `StructuredAddressFields` (interface in `customers.service.ts`) and `StructuredAddressDto` (class in `common/dto/`) remain two parallel shapes a new structured-address field must be added to by hand — only the insert-column mapping is single-source today. Collapsing via `type StructuredAddressFields = StructuredAddressDto` is possible but couples the service interface to the swagger-decorated class — taste call.
- Identity fields (`name`/`countryCode`/`phoneNumber`) and their validators are still copy-pasted between `CreateCustomerDto` and `NewCustomerDto`. TS classes are single-inheritance and both already extend `StructuredAddressDto` — an identity base would have to sit ABOVE the address base, putting identity fields on the address DTO. Needs composition-based validators or a decorators-per-mixin approach.
- e2e Retry-After assertion is a `[1, WINDOW]` range, so it passes on the pre-fix full-window behaviour too; exact behaviour is pinned only at the unit layer (`retryAfterSeconds: 7`). Tightening to a fresh-window band risks CI flake.
- `PlacesRateLimitStore.increment` (and now `InMemoryOtpSessionStore.increment`) are get-then-set (non-atomic): two concurrent increments can both read undefined and undercount — pre-existing single-process design; serialize per-key or move to atomic INCR when the Phase 2 Redis store lands.

## Deferred from: code review of Epic 3 story specs (2026-09-09)

- ~~Uncommitted-but-applied migration `workspace/core/backend/fenzit-be/supabase/migrations/20260909000001_enable_rls_users_country_codes.sql` (users + country_codes RLS) has no owner commit~~ **Resolved 2026-09-09** — committed in fenzit-be as `9af01bb` (own commit, not bundled into Story 3.1).

## Deferred from: code review of spec-3-3-frontend-owner-live-job-status-updates (2026-09-09)

- No recovery path for a dead socket — `CHANNEL_ERROR`/`TIMED_OUT` are log-only and `CLOSED` is unhandled in the subscribe callback (`useOwnerNotifications.ts:154-158`); supabase-js auto-reconnect covers most transient drops, auth-rejection loops would not recover until a background/foreground cycle. Revisit when Story 3.4 adds push.
- No event-type filtering — every INSERT broadcast on the owner topic renders a job-status banner (`useOwnerNotifications.ts:106`); fine while the trigger fans only job-status rows, but Story 3.4's notification list will need type/operation filtering.
- `handleJobStatusEvent` is a closure inside the hook with a `(topic, message)` signature, not the exported pure `handleJobStatusEvent(payload)` the Design Note prescribed as the Phase 2 seam — reshape it when the FCM data-message handler lands in Story 3.4.

## Deferred from: code review of spec-3-4-frontend-notifications-bell-list-deeplink (2026-09-09)

- Notifications list rows never re-render their relative timestamps while the
  screen sits open — a row showing "Just now" stays that way until the data
  changes (focus/pull-to-refresh fixes it). Polish: needs an interval tick;
  accepted as cosmetic for now. [fenzo-app src/features/notifications/components/NotificationRow.tsx]

- source_spec: `artifacts/implementation-artifacts/spec-4-1-global-skills-catalog-with-read-only-api.md`
  summary: Repo-wide — real-DB integration tests (`test/integration/*.spec.ts`) are skipped in every normal verification run (`jest.env.setup.ts` stubs `SUPABASE_URL`, and the unit jest config never collects `test/integration`), so schema/RLS drift is caught only when someone sets real credentials or via manual Supabase MCP spot-checks; no CI exists to run them. Surfaced by Story 4.1's verification-gap review layer; the pattern pre-dates this story (it is the AR-20 harness pattern).
  evidence: `test/jest.env.setup.ts:3` sets `SUPABASE_URL='https://test.supabase.co'` for the whole e2e config, `IS_REAL_DB` gates every `maybeIt`, `package.json` unit config has `rootDir: "src"`, and the pre-push hook runs only typecheck. Story 4.1 mitigated its own drift risk by asserting the exact six seeded rows in order inside the `maybeIt` block (they fail the moment real creds are provided), but a standing way to run them regularly (a bun script, a pre-deploy hook, or CI) is still missing repo-wide.

## Deferred from: code review of spec-4-1-global-skills-catalog-with-read-only-api (2026-09-10)

- E2E mocks are never reset between tests — `mockCreate`/`mockCreateAdmin` are created once in `beforeAll`, `jest-e2e.json` has no `clearMocks`, and `mockJwtClient` only replaces return values, so mock state and call history leak across the GET and POST/DELETE blocks in `test/skills.e2e-spec.ts`. Harmless today by coincidence (POST/DELETE use `createAdmin`), fragile for Story 4.2's edits. Pre-existing harness pattern (beforeAll mocks pre-date this story's diff).
- Mint-contract duplication — `SkillsService.listGlobalSkills` re-implements `AuthService.mintRealtimeToken`'s claim shape and the jsonwebtoken gotcha (payload `exp`, no `expiresIn` option) from scratch, and `POSTGREST_TOKEN_TTL_SECONDS` is exported but unconsumed. Both sites currently document that they mirror each other, so drift risk is noted, not hidden; a shared mint helper (and dropping/using the export) is a refactor candidate for a later story.

## Deferred from: code review of spec-4-2-technician-skills-cut-over-to-the-global-catalog (2026-09-11)

- source_spec: `artifacts/implementation-artifacts/spec-4-2-technician-skills-cut-over-to-the-global-catalog.md`
  summary: The retargeted FK `user_skills.skill_id → skills(id) ON DELETE RESTRICT` has no test asserting its guard behaviour — a DELETE of a skill row that technicians still reference must fail (23503), not silently strip assignments (the whole rationale for RESTRICT over CASCADE in migration 35). The RLS suite covers reads/writes of user_skills but never attempts a skill DELETE.
  evidence: `supabase/migrations/20260911000001_tenant_skills_cutover.sql:16-19` (RESTRICT), `test/integration/rls-isolation.integration.spec.ts` (no DELETE probe on skills); surfaced by the Story 4.2 blind-hunter review layer, judged low severity — the constraint is declarative and the migration applied cleanly.

## Deferred from: code review of spec-4-3-workflow-templates-and-skill-tagged-jobs (2026-09-11)

- source_spec: `artifacts/implementation-artifacts/spec-4-3-workflow-templates-and-skill-tagged-jobs.md`
  summary: `workflow_templates.steps` JSONB is validated only as an array (`jsonb_typeof(steps) = 'array'`) — per-step shape (required keys, non-null labels, valid boolean/enum values, first/last step sanity) and the enumerated value domains for `advances_on`/`sets_status` are unchecked. Story 4.4's engine becomes the first consumer of these fields; when it lands, add a stricter CHECK (or a seed-time validation in the migration) so a malformed template row fails loudly instead of at advance time.
  evidence: `supabase/migrations/20260911000002_workflow_templates_skill_tagged_jobs.sql:35` (array-only CHECK), Design Notes step shape in the spec (keys/labels/`advances_on: "photo_confirm"` are conventions, not constraints); surfaced by the Story 4.3 blind-hunter review layer — Story 4.4 owns the step semantics, so the domain validation belongs with that story.
- source_spec: `artifacts/implementation-artifacts/spec-4-3-workflow-templates-and-skill-tagged-jobs.md`
  summary: `jobs.workflow_template_version` is an INT copied from the template row, but no composite FK ties `(workflow_template_id, workflow_template_version)` to `workflow_templates(id, skill_id, version)` — a hypothetical buggy writer could stamp a version number that doesn't exist on the referenced template. Only the RPC writes the stamp today (resolved inside the RPC via the latest-version lookup), so there is no actual writer that can desync; revisit composite-FK hardening if any future code path writes the stamp directly.
  evidence: `supabase/migrations/20260911000002_workflow_templates_skill_tagged_jobs.sql:91-93` (plain INT column, single-column FK on id only); surfaced by the Story 4.3 edge-case-hunter review layer, judged not actionable now — the immutable-stamp invariant is enforced by the RPC being the only writer.

## Deferred from: code review (2026-09-11) — code review of spec-4-4-generic-workflow-engine-and-attachment-auto-advance.md

- Only PT409 is swallowed in `confirm_attachment`'s delegated auto-advance; any other error raised inside `advance_workflow_step` rolls back the whole transaction including the attachment insert, contradicting the "attachment always commits" header claim. Practically unreachable today: the migration-36 array CHECK + `workflow_steps_valid` close the malformed-steps raise path, `activity_logs.actor_id` is nullable (migration 8), and the notification insert is filtered out rather than attempted with a NULL actor. Widening the catch to `WHEN OTHERS` would swallow genuine bugs and deviates from the frozen design notes.
- `confirm_attachment`'s SQL auto-advance has no permanent automated test — all specs that touch the endpoint mock the RPC. Verified live this session via three rolled-back MCP scenarios (advance fires / no-op / terminal PT409 swallow); a lasting integration test needs the same real-DB infra the always-skipped RLS isolation suite waits on.
- TS parser / SQL CHECK divergence: the validator compares `key`/`label` via `->>` (text coercion), so a JSON number passes the CHECK while `parseTemplateSteps` requires `typeof === 'string'` and 500s the advance. Fails safe and unreachable post-CHECK; tightening the validator requires a new migration (Ask First per spec).
- `workflow_steps_valid` permits degenerate template authoring: mid-chain `sets_status: 'completed'` terminal-locks the rest of the chain, multiple `advances_on: 'photo_confirm'` steps resolve to the first, and a chain can strand a job in `scheduled`. Authoring-contract gap for future templates; the 6 v1 seeds are sane.
- Create-path flag payload (`requireCompletion*`) is silently stripped by the whitelist (201) rather than 422-rejected — matches the DTO-whitelist mechanism the matrix names and is the safer behaviour for the backend-first deploy; the matrix's blanket 422 wording holds on the PATCH path (flag-only PATCH → empty-PATCH 422).
- TS parser parity unit tests (65-char key, whitespace label, non-object array entries, JSON nulls) not added — belt-and-braces for a post-CHECK-unreachable path.
- `V1_TEMPLATE_STEPS` test fixture duplicated across 5 spec files (unit, e2e ×3, integration) — no shared fixture root spans those test roots; a seed-shape drift needs 5 coordinated edits.
- `project-overview.md` still says "all four planned epics delivered" while the sprint now tracks Epic 5 — pre-existing text adjacent to this change's one-line update.
- Owner notification is skipped when a first photo is confirmed on the Worker path (D1, accepted by Ashish): `webhooks.service.ts` calls `confirm_attachment` with `p_actor_id: null`, so the delegated `advance_workflow_step` still advances the workflow and writes the activity log (actor is nullable), but its notification guard `t.owner_id <> p_actor_id` filters out every row when the actor is NULL — no notification row is written. The primary technician-app path notifies as specified; the advance and the attachment both commit correctly on the Worker path. Fixing it would need either skipping the auto-advance for NULL actors (job state lags) or a synthetic system user as actor.

---

# Migrated deferred work (2026-09-11) — single-sprint consolidation

Everything below was migrated verbatim from the child repos' repo-local
`deferred-work.md` files on 2026-09-11, when the meta sprint became the only
active sprint. From now on this file is the ONLY deferred-work log. The child
repo files now carry a RETIRED pointer and are no longer updated. Story IDs
below refer to the child repos' own local story numbering (fenzo-app epics 1–5,
fenzit-be epics 1–4), NOT to this sprint's epic numbering.

## From: fenzo-app repo-local deferred-work.md

## Deferred from: code review of 1-1-wire-jobs-list-to-get-jobs (2026-09-03)

- ~~**App.test.tsx fails to boot**~~ — **Fixed 2026-09-03.** Three stacked fixes, each unblocking the next: (1) worklets mock + css/native/proxy `setCSSEventHandler` noop in `jest.setup.js` (reanimated 4.6's own mock imports the real source, whose native initializer crashes in jest); (2) `__mocks__/react-native-bootsplash.ts` (TurboModule can't exist in jest); (3) `__mocks__/react-native-mmkv.ts` (Map-backed) + `@react-native-community/datetimepicker` added to the `transformIgnorePatterns` ESM allowlist. Baseline is now green: 5/5 suites, 43/43 tests.
- ~~**JobsScreen has no component test**~~ — **Fixed 2026-09-03** (`__tests__/JobsScreen.test.tsx`, 7 tests). The boot-mock work above made the scaffolding trivial: the real screen mounts with the real `useJobs` store (`jobService` mocked at the module boundary), profile/customers stubbed to static data, and `useFocusEffect` reduced to "run once mounted". Covers: loading spinner, name resolution, failed-no-data (banner + Retry refetch), failed-refresh-with-data (dismissible banner, rows kept), per-filter empty-state copy, `onEndReached` pagination, and "New job" navigation.
- **401 forced-logout clears no stores** — `setOnUnauthorized` is exported from `src/services/api/apiClient.ts` but never registered anywhere in the app, so an expired session forces nothing. Global session-expiry handling is Story 5.3's scope; when wiring it, clear the jobs store (tenant-scoped data must not survive auth expiry) alongside profile/customers/technicians.
- **Technician-side screens render placeholder-heavy cards** — TodayScreen/HistoryScreen pass no `customerName`/`technicianName`, so cards fall back to service-type labels and a literal 'Technician' avatar. Story 3.1 owns the technician card variant; the arrays are empty today.

## Deferred from: code review of 1-2-owner-job-detail-screen (2026-09-03)

- **Activity timeline event class is colour-only** — the step/completed/cancelled/neutral distinction on timeline dots is conveyed only by dot colour; no text or accessibility label carries it, which fails colour-blind and screen-reader users. Fix with an `accessibilityLabel` on each timeline row (e.g. include the event class wording) when accessibility polish lands.
- **Detail dates render in the device timezone** — `dateLine`/`timestampLabel` format UTC `scheduledStart`/`createdAt` via `toLocaleDateString('en-IN', …)` with no timezone pin, so the displayed day can shift on non-IST devices (early-morning IST slots land on the previous day in UTC-land). Decide the canonical display timezone (probably IST) before launch and pin it centrally, not per-call.
- **Stale technician TODOs now point at an existing screen** — `TodayScreen.tsx:31-33` and `HistoryScreen.tsx:22-24` still say "navigate to a job detail screen once it exists"; that screen now exists (`JobDetail` route). Harmless today (lists are stub-empty), and Story 3.2 owns the technician-side adoption — but the comment should be cleared when that lands so it doesn't mislead.

## Deferred from: code review of 1-1-wire-jobs-list-to-get-jobs, params-serializer follow-up (2026-09-03)

- ~~**Backend query-parser contract has no pinned test**~~ — **Fixed 2026-09-03** (`fenzit-be/src/jobs/dto/list-jobs-query.dto.spec.ts`, 10 tests). Fastify's `inject()` pins the parser dialect (repeat style → string/array, bracket style survives as a literal `status[]` key), plus end-to-end DTO tests through a pipe config mirroring `main.ts` — including the trap case: `?status[]=bogus` validates as an empty query (200), while `?status=bogus` is a 422. fenzit-be suite: 18 suites, 262 tests green.

## Deferred from: code review of 1-3-edit-reassign-cancel-job (2026-09-04)
- ~~Zero-length schedule window (end == start) parity with server unverified~~ — **Resolved 2026-09-04.** Backend rule confirmed in fenzit-be source: createJob (`jobs.service.ts` ~L228) and the update RPC (`20260621000004_rpc_update_job_with_log.sql`, PT422 on the *effective* window) both reject with strict `<`, so a zero-length window is allowed server-side — exactly matching `scheduleWindowError`. Parity pinned by a new model test (both directions).
- ~~ApiError.message typed string but can arrive as an array~~ — **Resolved 2026-09-04 (pulled forward from Story 5.4).** Normalized at the source: `toApiError` now flattens the ValidationPipe's array form (join with '. ') before it reaches any caller, so `ApiError.message` stays a plain `string` and all consumers stay type-safe. Pinned by `__tests__/api-error.test.ts` (3 tests). The model-level `flattenApiMessage` stays as a defensive belt for errors that bypass `toApiError`.
- ~~No e2e/testID/accessibility hooks on EditJobSheet controls~~ — **Resolved 2026-09-04.** Added `testID` hooks: `edit-job-save`, `edit-job-priority-{normal|urgent}`, `edit-job-form-error`, `technician-row-<id>` (rows variant) and `technician-tile-<id>` (tiles variant); `Button` now forwards a `testID` to its Pressable. Sheet test pins the hooks so they can't silently regress.

## Deferred from: code review of 1-4-home-stats-refresh (2026-09-04)

- **`useJobs.ts` keeps its own `15_000` throttle literal** — `FOCUS_REFRESH_TTL_MS` now exists in `src/constants` for exactly this, but `useJobs.ts` (story 1-2's file) still hard-codes the literal, so the "single place" claim in the constant's doc comment isn't true yet. Migrate it to the constant when Stories 2.2/3.1 adopt the TTL.
- ~~**`fetchProfile` catch doesn't handle non-ApiError rejections**~~ — **Fixed 2026-09-04.** The catch now falls back to 'Something went wrong' when the rejection carries no usable message (`||`, not `??` — an empty/undefined message must not render as no-banner), pinned by a test covering both a TypeError passthrough and an undefined rejection. Sibling stores `useJobs.ts`/`useCustomers.ts` carry the same pattern — fix them the same way if/when touched. — if `getMe` rejects with a TypeError/abort/syntax error, `(error as ApiError).message` is undefined and falsy, so a failed refresh renders no error banner while `profile` is retained — looks like success. Fix: fall back to a generic message in the catch. Pre-existing behaviour, surfaced incidentally by this review.
- **Repo has no ESLint config** — `bun run lint` fails with "couldn't find a configuration file" for every story, so lint is never a real gate. Set up an ESLint (or Biome) config once, repo-wide.

- **`totalJobs` sum duplicated between HomeScreen and HomeHeader** — `src/screens/HomeScreen.tsx` (~L114) and `src/components/HomeHeader.tsx` (~L33) each independently sum the same five `jobCounts` buckets; a bucket added later in only one copy would drift the header total from the tiles. Pass the precomputed total into `HomeHeader` instead.

## Deferred from: code review of 1-5-jobs-timeline-scopes (2026-09-04)

- **`upsertJob` row can be overwritten by an in-flight page-1 response** —
  `src/features/jobs/useJobs.ts` (~L230-236): a create/cancel triggers `upsertJob` (prepend for
  today-scope rows) while a page-1 refetch is still in flight; when the stale response lands it
  replaces the list and drops the upserted row. Pre-existing pattern, not introduced by this
  story. Mitigation today: the throttled focus refetch picks the row back up on next focus.
  Fix direction: version/generation-tag in-flight fetches so stale responses can't clobber.
- **`upsertJob` IST-midnight boundary edge** — `src/features/jobs/useJobs.ts` (~L231): a job
  confirmed right at the IST day boundary is guard-rejected (correctly, per the day guard) and
  vanishes from Today until the next focus refetch triggers a reload. Same pre-existing
  pattern family as the race above; fix both together if ever worth it.
- **`list()` sends `date` alongside a non-today scope unguarded** —
  `src/services/resources/jobs.ts` (~L275-284): the client-side type permits `date` with
  `scope=upcoming|overdue|history`, which the server 422s. The store never sends `date`, so
  it's unreachable today; note it as a contract shape to tighten (client-side type narrowing)
  if a caller ever combines the two.

## Deferred from: code review of 2-1-customer-detail-with-job-history (2026-09-04)

- **`dateLine` is now copy-pasted in three screens** — `JobDetailScreen` started it ("12 Aug 2026" via
  `toLocaleDateString('en-IN', …)`), and Story 2-1's `CustomerDetailScreen` + `HistoryRow` followed the
  precedent. Unify into one shared formatter (e.g. `src/utils` or `features/jobs/format.ts`) and pin the
  display timezone in the same move — same family as the 1-2 deferred "detail dates render in the device
  timezone" item.
- **Test coverage beyond Task 5's scope** — the call action (`openTel`), the back button and its
  `canGoBack() === false` → MainTabs fallback, 403-as-not-found, and the load-more failure branch are
  untested in `__tests__/customer-detail-screen.test.tsx`. Add when the screen is next touched.
- **History rows carry no accessibility role/label** — a tap target announcing only its text children;
  include jobNumber + status in an `accessibilityLabel` when accessibility polish lands (same family as
  the 1-2 timeline-label item).
- **Relative imports repo-wide** — CLAUDE.md mandates the `@components`/`@theme` alias imports, but every
  feature file (pre-existing) uses relative paths; Story 2-1 followed precedent. Repo-wide alias migration
  is a standalone cleanup, not a per-story fix.

## Deferred from: code review of 3-2-technician-job-detail (2026-09-04)

- **No accessibilityLiveRegion / image accessibility roles on new surfaces** — the photos grid and
  signature tile render images without `accessibilityRole="image"` / meaningful labels, and state
  transitions (loading → error → loaded) have no live region. Same gap family as the 1-2 deferred
  "timeline event class is colour-only" item — fix accessibility polish repo-wide in one pass.
- **No testIDs on new interactive surfaces** — stepper rows (inert this story, pressable in 3.3),
  History disclosure header, maps row, and error-view Retry have no `testID` hooks. Add them when
  Story 3.3 wires interactivity and the rows need to be driven in tests (same pattern as the 1-3
  EditJobSheet hooks).

## Deferred from: code review of 3-4-photo-capture-upload-r2 (2026-09-05)

- **`limitReached` is a one-way latch** — set on a 409 from presign/confirm, never reset even if a
  later refetch shows fewer than 5 photos; harmless until a photo-delete feature exists, then the
  flag needs a reset path (derive from `photos.length` or clear on refetch).
- **Per-file confirm fires its own full detail refetch** — 4 parallel picks → up to 4 chained silent
  `load(false)` calls; the screen's inflight chaining softens the churn. Batch/debounce if a device
  run shows it.
- **Just-confirmed photo vanishes from the grid until the refetch lands** — the done tile is dropped
  before the refetched detail includes it (brief flicker; the limit briefly under-counts in the same
  window; server 409 is the backstop). Revisit if visible on device.
- **Presign 422 (disallowed mime) is offered a Retry that deterministically fails** — the pipeline
  distinguishes 409/410 but has no retryable-vs-permanent notion.
- **Photo tiles carry no accessibility labels** — confirmed/in-flight/failed tiles announce nothing
  meaningful; same repo-wide a11y-polish family as the 1-2 and 3-2 deferred items.

## Deferred from: second code-review pass over 3-4-photo-capture-upload-r2 (2026-09-05, BE cross-check)

- **5-photo cap can be exceeded by parallel uploads (fenzit-be)** — the limit is counted at presign
  (`attachments.service.ts` ~L118-145, confirmed photos only) and again at confirm (RPC
  `20260621000014`, `SELECT COUNT(*) >= 5` then INSERT), but two overlapping confirms can both read
  4 under READ COMMITTED and both insert — the migration's own comment concedes this. The FE's
  parallel uploads reach the path directly (pick 3 files at 4/5 → 6-7 rows, no 409 ever fires).
  Real fix: a UNIQUE/exclusion constraint in a BE migration; FE-side confirm serialization would
  only narrow, not close, the window.
- **Confirm endpoint lacks the idempotency interceptor (fenzit-be)** — presign and workflow-advance
  have `@UseInterceptors(IdempotencyInterceptor)`; confirm does not, so its `X-Idempotency-Key`
  header is silently ignored. Harmless today (FE mints fresh keys; re-executed confirm is safe —
  the RPC returns the existing row). Fix is one line on the controller, or leave the FE comment
  (now corrected 2026-09-05) documenting the status quo.
- **410/failed confirm after a successful PUT orphans the R2 object (fenzit-be)** — the single
  restart mints a fresh presign (new UUID key), so the first PUT's object is never referenced again.
  The daily cron deletes only the `attachment_uploads` staging row; neither repo deletes storage
  objects and the bucket has no lifecycle rule. Same leak on any confirm failure/network death
  post-PUT. Fix direction: an R2 bucket lifecycle rule, or delete-on-abandon in the BE.
- **Confirm never verifies the R2 object or its size (fenzit-be)** — the backend trusts the
  client-reported `sizeBytes` (bounded ≤ 50 MB) with no HEAD of the object and no content-length in
  the signed URL; confirm can create an attachment row for a missing object. Hardening gap — the FE
  throws on any non-ok PUT so the happy path never hits it.
- **Client-side expiry pre-check trusts the device clock** — `deps.now()` vs the server-issued
  `expiresAt`: a device ≥15 min fast fails every upload with "presign expired" before any request.
  Kept as a deliberate fail-safe (avoids PUTting into a dead URL); revisit only if a device ever
  shows it.

## Deferred from: code review of 1-6-job-requirement-toggles (2026-09-05)

- **Deploy-order hazard: `ApiJob.requireCompletionSignature` is required on the client** — if fenzo-app deploys
  before fenzit-be 3-8, every job row carries `undefined` for the field (seeds `undefined` into drafts, diffs
  truthy against `false` → phantom "changed" flags on first save). Cross-repo ordering rule (BE first) covers
  it; keep BE-first explicit in the 1-6 hand-off.
- **Signature toggle is inert until Story 3-5 ships** — owner can set `requireCompletionSignature`, but the
  technician app doesn't consume it yet. Expected sequencing (3-5 is ready-for-dev, revised to depend on the
  field), not a defect.
- **Fixture duplication across 11 test files** — every new required `ApiJob` field touches all fixtures; a
  shared `makeJob()` factory would stop the churn. Pre-existing pattern family; standalone cleanup.
- **Relative imports in touched files** — new imports followed the file's existing relative style rather than
  the CLAUDE.md `@/` aliases; repo-wide alias migration already deferred from the 2-1 review.
- **Sheet controls not disabled while submitting** — the new Switches stay enabled during an in-flight save like
  every other sheet control (pre-existing pattern); if it matters, disable the whole form in one pass.

## Deferred from: code review of 3-5-signature-capture (2026-09-05)

- **Owner-side signature display picks the oldest attachment** — `AttachmentGrid.tsx:86` uses
  `attachments.find(...)`; after a technician re-capture the owner keeps seeing the first
  (oldest) signature image. Parity fix is the same `filter().slice(-1)` the technician side
  got in 3.5. Shipped with 1-6, outside the 3.5 diff.
- **Owner timeline still counts the fixed 6-step chain** — owner job detail renders
  "Step N of 6" from `STEP_ORDER.length`, so a signature-off job shows a 6-step chain to the
  owner while the technician rail shows 5. Owner-side, untouched in the 3.5 diff.
- **sprint-status 1-6 done-line lacks a commit hash** — unlike every sibling done story's
  comment. Doc nit, committed in c7a9e67.
- **Relative imports in new files** — `SignatureScreen`, `signatureExport`, `base64` follow
  each file's existing relative style rather than the CLAUDE.md `@/` aliases; part of the
  repo-wide alias migration already deferred from 1-6 and 2-1 reviews.

## Deferred from: code review of 5-3-session-expiry-global-401.md (2026-09-05)

- **A 401 from an OLD session can settle after a fresh re-login and wipe the new session** —
  `src/services/api/apiClient.ts`: the `handlingUnauthorized` dedup re-arms on a tick with no
  session-generation guard, so a late 401 from a request issued pre-logout can fire the global
  reset + `expireSession()` after the user has already logged back in, kicking them out again.
  Practically unreachable (old-session requests settle within the API timeout, well before a
  manual re-login completes), pre-existing. Fix needs per-request token identity — a rebuild of
  the interceptor that story 5.3 explicitly forbids. Worth a session-gen guard when Epic 4
  touches this code.
- **Reset registry has no ordering/async contract** — `src/services/resetRegistry.ts` runs resets
  in Set-insertion order, sync only. Today's resets are order-independent; Epic 4's sync store /
  action queue may need ordering or async semantics. Document the contract when that store lands.

## Deferred from: code review of 1-7-home-todays-jobs-section (2026-09-05)

- **Today's jobs section has no pagination / truncation notice** — `HomeScreen.tsx` passes only
  `profile.jobs.data` into `TodaysJobsSection`; `hasMore`/`nextCursor` are dropped. A tenant with
  more scheduled/in-progress jobs today than the backend's page size sees `jobCounts.today`
  (header tile) disagree with the list below it, with no "load more" or truncation signal. No AC
  in this story calls for pagination here — needs a UX decision (load-more vs. "view all in
  Jobs") before it's built.
- **`Card` doesn't forward `accessibilityRole`** — `src/components/ui/Card.tsx`'s `interactive`
  mode wraps its own `Pressable` but never accepts/forwards an `accessibilityRole` prop, so an
  accessible tappable card (this story's `OverdueStrip`, and `HomeHeader`'s pre-existing
  `StatCard`) has to hand-roll a `Pressable`-wraps-non-interactive-`Card` workaround instead of
  using `interactive` directly. Now two independent copies of the same workaround. Fix once by
  adding an `accessibilityRole` prop to `CardProps` and forwarding it on both the `View` and
  `Pressable` branches; migrate both call sites when next touched.
- **Relative imports in new files** — `TodaysJobsSection.tsx`, `OverdueStrip.tsx`,
  `selectTodayJobs.ts` follow each sibling file's existing relative style rather than the
  CLAUDE.md `@/` aliases; same repo-wide alias migration already deferred from 1-6/2-1/3-5
  reviews.

## From: fenzit-be repo-local deferred-work.md

## Deferred from: code review of 1-3-tenant-company-onboarding (2026-06-20)

- `users.tenant_id` not re-linked on idempotent re-call if it becomes NULL post-creation — RPC's `IF v_inserted THEN` skips FK update on the ON CONFLICT path. Admin data repair scenario; out of scope for Phase 1.
- RPC `setup_tenant_for_owner` callable directly by any authenticated user (no GRANT restriction) — security hardening deferred by user until project is complete.
- No max-length on `companyName`, `address`, `upiVpa` in `SetupCompanyDto` — unbounded TEXT; DoS hardening for Phase 2.
- GSTIN regex allows invalid state-code prefixes (first two digits not validated against Indian state codes 01–38) — full GSTIN checksum validation out of scope for Phase 1.
- `tenants` table has SELECT-only RLS; no explicit INSERT/UPDATE/DELETE deny policies documented — security deferred by user.
- AR-10 violation in `findOrCreateUser` (two sequential `.from()` calls) — pre-existing from Story 1.2, not introduced here.
- AR-20 RLS isolation tests always skipped in CI with stub credentials — no CI enforcement gate. Infrastructure gap to address before launch.
- `RolesGuard` spec does not assert `error_code: "FORBIDDEN"` in thrown exception — pre-existing Story 1.2 test gap.
- RPC errors mapped as `VALIDATION_ERROR` regardless of cause — internal DB errors indistinguishable from user input errors. Phase 2 error classification work.

## Deferred from: code review of 1-4-technician-invitation-auto-accept (2026-06-20)

- W1 — `verifyOtp` has `isValid = true` hardcoded; OTP code is never actually verified. Explicitly marked "Phase 2: replace with bcrypt.compare". Critical before any production deployment.
- W2 — `findOrCreateUser` TOCTOU race: two concurrent `verifyOtp` calls for a brand-new phone both get PGRST116 then both attempt INSERT; the second caller receives a 400. Pre-existing from Story 1.2.
- W3 — `country_codes` seed maps `+1` to `iso2='US'` only; Canada also uses `+1`. If `iso2` is used for routing or display, Canadian users will be misidentified. Low priority until country-specific logic is added.
- W4 — `name` field in `InviteTechnicianDto` accepts whitespace-only values (`@MinLength(1)` passes `" "`); add `@IsNotEmpty()` or `@Transform(() => value.trim())`.
- W5 — `invite_id` returned in 201 response is the raw `users.id` UUID (internal PK). Acceptable for Phase 1; consider an opaque token before public launch.


## Deferred from: code review of 1-6-update-invite-to-skill-ids (2026-06-20)

- JWT payload shape not asserted after `skill_type` removal — low risk, column dropped in Story 1.5 migration
- `user_skills` 23503 FK error (race-deleted skill) treated as generic 500 — acceptable TOCTOU trade-off, security hardening deferred
- TOCTOU: skill deleted between validation query and `user_skills` insert — architectural concern, pre-existing
- Re-invite of `status: 'invited'` technician blocked with misleading "already registered" 23505 — pre-existing from Story 1.4, needs a re-invite / upsert flow
- 3 sequential DB round-trips in `inviteTechnician()` with no transaction — architectural; ideally wrapped in a Postgres function or transaction

## Deferred from: code review of 2-1-create-customer (2026-06-21)

- C1 — `CustomersService.createCustomer()` uses the service-role client (`createAdmin()`), which bypasses RLS; the `customers_tenant_isolation` policy gives no protection on the write path. Tenant isolation rests entirely on the app setting `tenant_id: owner.tenantId`. Consistent with the skills/auth modules — same RLS-vs-app-layer reconciliation already tracked project-wide. Revisit when RLS is enforced before launch.
- C2 — `customers` text columns (`name`, `address`, `city`) are unbounded `TEXT`; only the DTO enforces `MaxLength`. The `created_via='job_creation'` value has no write path yet (arrives in Story 3.1). Add DB-level length CHECKs and confirm the job-creation insert path when it lands.

## Deferred from: code review of story 3-1-create-job (2026-06-21)

- J1 — AC1 (`job_created` activity-log persistence) and AC10 (sequential/race-safe job numbers, year rollover) are verified only by a manual rollback-wrapped DB block (Dev Agent Record), not by a committed regression test — the `create_job_with_log`/`increment_job_counter` RPCs are mocked in every unit/e2e test. Needs a real-Postgres integration test that runs the migrations and hammers `create_job_with_log` concurrently to assert gap-free numbers + the activity-log row. CI currently has no DB (same infra gap as the AR-20 RLS isolation tests, which are always skipped in CI). Address with the CI-DB enablement work.
- J2 — `create_job_with_log` trusts an app-supplied `p_year` (computed IST year). A wrong/ skewed clock or future caller could mint a job in the wrong `job_sequences` bucket. Harden by computing the year inside the RPC from `now() AT TIME ZONE 'Asia/Kolkata'`. Phase-1 single-instance constraint makes this low risk for now.
- J3 — `lpad(last_seq, 4, '0')` never truncates, so job numbers silently widen from `JB-2026-9999` to `JB-2026-10000` past 9,999 jobs per tenant per year, breaking any fixed-width `JB-YYYY-NNNN` parser. Decide whether to widen the documented format or cap; extremely unlikely to be hit in Phase 1.

## Deferred from: code review of story 3-2-list-jobs (2026-06-21)

- L1 — `GET /api/v1/jobs` filters by `scheduled_start` (IST day window) but sorts/cursors by `created_at DESC, id DESC` (per architecture.md:1041), and the only index is `idx_jobs_tenant_id_scheduled_start`. There is no index supporting the sort/keyset, so Postgres sorts the day-window rows in memory on every page and the cursor predicate re-filters rather than seeks. Acceptable while per-tenant-per-day cardinality is small (Phase 1); consider a `(tenant_id, created_at DESC, id DESC)` composite index in a perf pass to protect NFR-3 (list p95 < 300ms). Out of scope for this no-migration story.

## Deferred from: story 3-3-job-detail (2026-06-21)

- D1 (→ **Story 3.6**) — `GET /api/v1/jobs/:id` returns `attachments: []` as a stable placeholder. The `attachments` table, the abstract `StorageRepository.getPresignedReadUrl(key, 3600)` + `CloudflareR2StorageRepository`, and the upload/webhook flow are all introduced in Story 3.6 (none exist yet — only the four `CLOUDFLARE_R2_*` env vars are validated in `app.module.ts`). Story 3.6 must populate this endpoint's `attachments` with the real rows, each carrying a **freshly-generated R2 pre-signed read URL (1-hour TTL, regenerated every call, never cached/stored)**, and finalize the `JobAttachmentResponse` shape. This satisfies the epic AC "Given a job with 3 photo attachments → each URL is a fresh pre-signed read URL," which is intentionally out of scope for 3.3. [Source: 3-3-job-detail.md#Scope boundaries; architecture.md:175-226]

## Deferred from: story 3-4-edit-reassign-cancel-job (2026-06-21)

- E1 — `PATCH /api/v1/jobs/:id` uses the `COALESCE(p_field, existing)` pattern in `update_job_with_log`, so a `null` RPC param means "leave unchanged". The endpoint therefore **cannot clear a nullable field back to `null`** (`scheduledEnd`, `description`, `notesForTechnician`). The AC set only requires *setting* values, and class-validator's `@IsOptional` cannot distinguish an absent key from an explicit `null` anyway, so an explicit-clear contract was not built. If the product later needs "clear this field", add per-field `p_set_*` boolean flags (or a sentinel) to the RPC + DTO so absent vs. explicit-null are distinguishable. [Source: supabase/migrations/20260621000004_rpc_update_job_with_log.sql; src/jobs/dto/update-job.dto.ts]
- E2 — The atomicity of `update_job_with_log` (job UPDATE + `job_reassigned`/`job_cancelled` log in one transaction), the `PT409` not-modifiable raise, and the reassignment-metadata shape are verified only by a manual Supabase-MCP seed/exercise/cleanup pass during dev (Dev Agent Record), not by a committed regression test — the RPC is mocked in every unit/e2e test. Same CI-has-no-DB infra gap as J1/AR-20; fold into the CI-DB enablement work. [Source: 3-4-edit-reassign-cancel-job.md#Task 6]

## Deferred from: story 3-5-technician-workflow-step-advancement (2026-06-21)

- W1 (→ **Story 4.2**) — The `idempotency_log` 24-hour expiry has **no `pg_cron` cleanup job yet**; rows accumulate indefinitely. The `IdempotencyInterceptor` lookup filters `created_at > now() - 24h` so an un-pruned key never replays past its window, but the table grows without bound until Story 4.2 adds `DELETE FROM idempotency_log WHERE created_at < now() - interval '24 hours'` (hourly). [Source: epics.md line 747; supabase/migrations/20260621000005_create_idempotency_log.sql]
- W2 — `advance_workflow_step` atomicity (job UPDATE + `step_*` log in one transaction), the `PT409` raise (terminal status **and** the compare-and-set conflict), and the `idempotency_log` `UNIQUE(key, tenant_id)` behavior are verified only by a manual Supabase-MCP seed/exercise/cleanup pass during dev (Dev Agent Record), not by a committed regression test — both the RPC and the interceptor's DB calls are mocked in every unit/e2e test. Same CI-has-no-DB infra gap as J1/E2/AR-20; fold into the CI-DB enablement work. [Source: 3-5-technician-workflow-step-advancement.md#Task 10]
- W3 — Idempotency dedup is **read-through** (check `idempotency_log`, then run the handler, then insert the response). Two genuinely concurrent requests with the same key can both miss the lookup and both execute the step before either inserts; the second insert hits `23505` (swallowed) but the step/activity-log may be applied twice. The compare-and-set guard in `advance_workflow_step` makes the *second* advance fail (`PT409`) for the step case, so the practical double-apply window is closed for workflow steps, but the general interceptor (reused by Story 3.6 attachments) has no such backstop. The 24h replay scenario this targets (offline-sync retries) is sequential, not concurrent, so this is acceptable for Phase 1. A fully race-safe design would insert the key inside the same transaction as the side effect. [Source: src/common/interceptors/idempotency.interceptor.ts]
- W4 — `WorkflowService.advanceWorkflowStep` does a read-then-RPC (fetch job for validation, then call the RPC). The friendly step-ordering/terminal checks run on the read snapshot; the RPC re-guards authoritatively under `FOR UPDATE` (terminal status + compare-and-set), so the only consequence of a concurrent change is a `PT409` (mapped to 409), never a wrong write. No fix needed — documented so the two-call shape isn't mistaken for a TOCTOU bug. [Source: src/jobs/workflow.service.ts]

## Deferred from: code review of story 3-5-technician-workflow-step-advancement (2026-06-21)

- CR1 — `PT409` conflation: a terminal-status job (permanently not modifiable) and a lost compare-and-set race (transient, the job is still advanceable) both surface as `409 JOB_NOT_MODIFIABLE`. The client cannot distinguish "retry me" from "give up." Accepted per AC#18 for Phase 1; revisit if a client needs a retry signal (e.g. a distinct error_code or `Retry-After`). [Source: src/jobs/workflow.service.ts; migration 20260621000006_rpc_advance_workflow_step.sql]
- CR2 — The advanceable-status whitelist is duplicated and must be edited in lockstep: the service pre-check uses `JobStatus.SCHEDULED`/`IN_PROGRESS` and the RPC uses SQL `IN ('scheduled','in_progress')`. If the set of advanceable statuses ever changes, both sites must change together; nothing ties them. Low risk (the RPC is authoritative). [Source: src/jobs/workflow.service.ts; migration 20260621000006_rpc_advance_workflow_step.sql]
- CR3 — `GlobalExceptionFilter` casts `r['message'] as string` and emits it verbatim, but `ValidationPipe` produces `message: string[]`. Validation-error bodies therefore carry a `message` array rather than a single string. Pre-existing — predates this story's filter change; flagged during the 3.5 review. Decide a canonical envelope (join the array, or document the array shape) in an error-contract pass. [Source: src/common/filters/global-exception.filter.ts; src/main.ts ValidationPipe]

## Deferred from: story 3-6-job-attachment-upload-via-cloudflare-r2 (2026-06-21)

- A1 — **Worker Queue binding commented out**: `cloudflare-worker/wrangler.toml` has `# [[queues.consumers]]` commented out because Cloudflare Free plan has no Queue support. To migrate to the Worker webhook path on a paid plan: (a) uncomment the Queue binding, (b) add R2 event notification to queue in wrangler.toml, (c) implement `queue()` handler in `cloudflare-worker/src/index.ts`, (d) optionally remove the `POST /internal/webhooks/storage` HTTP endpoint. [Source: cloudflare-worker/wrangler.toml; cloudflare-worker/src/index.ts]
- A2 — **`sizeBytes` client-trusted**: The `sizeBytes` field in `ConfirmAttachmentDto` is supplied by the client and stored verbatim in `attachments.size_bytes`. For Phase 1 this is acceptable (the value is informational, not billed). Before production, derive the true file size server-side by calling `HeadObjectCommand` on the R2 key after the client's PUT completes, replacing the client-supplied value. [Source: src/jobs/attachments.service.ts; src/jobs/dto/confirm-attachment.dto.ts]
- A3 — **No cleanup job for expired `attachment_uploads` rows**: Staging rows with `status='expired'` or `status='pending'` past `expires_at` accumulate indefinitely. Add a pg_cron job (Story 4.2) to `DELETE FROM attachment_uploads WHERE expires_at < now() - interval '1 day'`. The `status` column and `expires_at` index make the query cheap. [Source: supabase/migrations/20260621000007_create_attachment_uploads.sql]
- A4 — **No R2 object cleanup on expired/abandoned uploads**: When a client uploads to R2 but never calls confirm (or confirms after expiry), the object stays in the bucket forever. Add an R2 lifecycle policy (object expiration after N days) in the Cloudflare dashboard, or run a periodic cleanup job that cross-references `attachment_uploads` with R2 keys. Phase 1 storage volumes make this low priority. [Source: src/storage/storage.service.ts]
- A5 — **Presigned URL one-per-file only**: The upload endpoint issues one presigned URL per request. A client uploading 5 photos must call the endpoint 5 times (serially or in parallel). Batching (return N URLs in one request) was evaluated and deferred to avoid adding scope; the client is expected to fire requests in parallel. [Source: src/jobs/jobs.controller.ts POST :id/attachments]

## Deferred from: code review of story 3-6-job-attachment-upload-via-cloudflare-r2 (2026-06-21)

- CR3.6-1 — **Idempotency replay returns a stale presigned URL after 15 min**: `@UseInterceptors(IdempotencyInterceptor)` on `POST /api/v1/jobs/:id/attachments` caches the full response (`presignedPutUrl`, `uploadId`, `expiresAt`) for 24h, but the presigned PUT URL TTL is only 900s. A replay past 15 minutes returns a dead URL with a 200. AC#19's contract is literally "return the original response", and this interacts with the shared `IdempotencyInterceptor` (same class as W3). A fully correct fix would either shorten the idempotency window for this route to the URL TTL or regenerate the URL on replay. [Source: src/jobs/jobs.controller.ts; src/common/interceptors/idempotency.interceptor.ts]
- CR3.6-2 — **RPC error mapping by `.message.includes()` diverges from the repo's `.code`/SQLSTATE convention**: `confirm_attachment` raises bare `RAISE EXCEPTION 'UPLOAD_NOT_FOUND'`/`'UPLOAD_EXPIRED'` (default SQLSTATE P0001), and both `AttachmentsService` and `WebhooksService` branch on `rpcError.message.includes(...)`. The sibling `advance_workflow_step` RPC uses `USING ERRCODE = 'PT409'` and the app branches on `error.code` — the stable, upgrade-safe convention. Message matching can mis-classify a 500 as a 404/410 (or vice-versa) if Postgres/PostgREST ever prefixes or localizes the message. Fix requires changing the RPC to raise custom SQLSTATEs AND the two services to branch on `code`. Fold into the error-contract pass (CR1/CR3). [Source: src/jobs/attachments.service.ts:240; src/webhooks/webhooks.service.ts:70; supabase/migrations/20260621000009_rpc_confirm_attachment.sql]
- CR3.6-3 — **`activity_logs.actor_id` made globally nullable weakens the NOT NULL invariant for all RPCs**: Migration 008 runs `ALTER TABLE activity_logs ALTER COLUMN actor_id DROP NOT NULL` so the webhook NULL-actor path (`p_actor_id = NULL`) can insert a `step_photos_uploaded` log. Only `confirm_attachment`'s auto-advance inserts NULL; every other RPC (`create_job_with_log`, `advance_workflow_step`, etc.) still expects a real actor, but the column-wide guardrail that would catch a NULL-actor bug is now gone. Consider re-tightening with a partial CHECK (`actor_id IS NOT NULL OR event_type = 'step_photos_uploaded'`) or a separate system-actor sentinel UUID. [Source: supabase/migrations/20260621000008_create_attachments.sql:30; supabase/migrations/20260621000002_create_jobs.sql:47]

## Deferred from: code review (re-review) of story 3-6-job-attachment-upload-via-cloudflare-r2 (2026-06-21)

- CR3.6-4 — **Idempotent re-confirm of a *replaced* signature uploadId returns 404 instead of 200**: When a signature is re-uploaded (AC#7), the upsert reassigns `attachments.upload_id` to the newest staging row. The older staging row stays `status='confirmed'` but no longer maps to any `attachments` row. Re-confirming that old uploadId (AC#9 idempotent path) does `SELECT ... WHERE upload_id = p_upload_id`, finds nothing → returns NULL `attachment_id` → the service's null-row guard 404s. No crash and no data corruption, but it contradicts the "idempotent re-confirm returns the original row" contract for the narrow stale-after-replace signature case. A design call is needed (e.g. resolve by job+type rather than upload_id in the idempotent branch for signatures, or keep upload_id stable across replace). [Source: supabase/migrations/20260621000009_rpc_confirm_attachment.sql:56; src/jobs/attachments.service.ts:296]

## Deferred from: code review of story 4-1-delta-sync-endpoint (2026-06-21)

- CR4.1-D1 — **Strict gt() boundary: row updated at exact `lastSyncedAt` timestamp is silently excluded**. `query.gt('updated_at', lastSyncedAt)` is strictly greater-than, so a row whose `updated_at` equals the stored `serverTime` is never delivered. Correct fix is `gte()`, but changes sync semantics and the `serverTime`-before-query strategy was deliberately chosen. Pre-existing design choice; acceptable for Phase 1. [Source: src/sync/sync.service.ts:35]
- CR4.1-D2 — **Trigger may double-set `updated_at` if service also sets it explicitly**: `trg_jobs_updated_at` fires `NEW.updated_at = now()` on every UPDATE. If any RPC or service also explicitly sets `updated_at`, both assignments run; the trigger's value wins (it runs last). Since all paths use server time, values converge and the result is correct. Low impact; flagged for awareness. [Source: supabase/migrations/20260621000011_delta_sync_index.sql:18]

## Deferred from: code review of story 4-2-idempotent-action-replay (2026-06-21)

- CR4.2-D1 — **AC1: no assertion that zero new activity log entries created on replay** — the test verifies the cached body is returned but does not count activity-log inserts. The interceptor design (handler never runs on hit) provides the logical guarantee; a full assertion would require complex mock instrumentation. Fold into the CI-DB enablement work.
- CR4.2-D2 — **AC2: no dedicated test for workflow step expiry path** — expiry is enforced in the interceptor's `gt('created_at', since)` filter; cron is table-hygiene only. The behavior is tested implicitly by the interceptor's own spec. Add an integration test in the CI-DB work.
- CR4.2-D3 — **`fail-open` DB error path not covered by a test** — the interceptor logs and falls through to the handler on lookup error; no test exercises `idempotencyLookup: { data: null, error: { ... } }`. Meaningful safety property; add in a future hardening pass.

## Deferred from: code review of story 4-3-server-side-conflict-resolution (2026-06-21)

- CR4.3-D1 — **F8: NULL `v_att_id` returned silently on signature `unique_violation` recovery race** — two concurrent confirms both reach the ELSE (no existing signature) branch; one loses with `unique_violation`; the recovery SELECT may find nothing if the winner's row is deleted in the same instant, returning NULL `attachment_id` with no error raised. Degenerate race with no practical impact in Phase 1; fold into the general `unique_violation` hardening pass. [Source: supabase/migrations/20260621000013_rpc_confirm_attachment_conflict.sql:120-126]

## Deferred from: code review of story 2-4-customer-detail-job-history (2026-09-03)

- CR2.4-D1 — **`decodeCursor` accepts semantically-invalid timestamps** — Bun's `Date.parse('2026-02-30T00:00:00Z')` rolls over to March 2 (no NaN) and `'1'` parses as a year, so a crafted cursor passes the charset + Date.parse validation and pushes an invalid timestamp into the PostgREST `.or()` predicate → Postgres parse error → 500 instead of the promised 400. Injection-safe (charset blocks structural chars); wrong status code only. Pre-existing shared util, not introduced by this story. Fix shape: tighten `TIMESTAMP_RE`/`decodeCursor` to a strict ISO-8601 format check. [Source: src/common/utils/cursor.util.ts:20]
- CR2.4-D2 — **`idx_jobs_customer_history` built without `CONCURRENTLY`** — plain `CREATE INDEX` takes a lock on `jobs` while building. Harmless pre-launch (index already applied live); adopt `CREATE INDEX CONCURRENTLY` repo-wide once there is real write traffic — the delta-sync migration (20260621000011) has the same gap, so fold both into one hardening pass. [Source: supabase/migrations/20260903000001_jobs_customer_history_index.sql:3]

## Deferred from: code review of story 3-7-jobs-timeline-scopes (2026-09-04)

- CR3.7-D1 — **`advance_workflow_step` `completed_at` stamping/backfill has zero execution-path test coverage** — every unit/e2e path mocks the RPC (`admin.rpc('advance_workflow_step', …)`) and no test/CI step applies `supabase/migrations/*.sql` (no `.github/workflows`, no migration script), so a wrong CASE condition or missed backfill would land undetected; the field the whole timeline feature is built on is verified only through fixtures. Fix needs a real-DB/migration test harness — fold into the CI-DB enablement work (same bucket as CR4.1/CR4.2 items). [Source: supabase/migrations/20260903000003_rpc_advance_workflow_step_completed_at.sql:56]
- CR3.7-D2 — **Backfill approximates completion time with `updated_at`** — `updated_at` is the row's last write, not necessarily the completion; a completed job later edited (notes, photo attach) backfills the later timestamp. No historical completion event exists to do better; accepted approximation, documented in the migration comment. [Source: supabase/migrations/20260903000002_add_jobs_completed_at.sql:2-6]
- CR3.7-D2b — **Keyset pagination drift when a job is rescheduled between pages** — `scheduled_start` is the keyset key for the upcoming/overdue/history scopes; a reschedule moves a row across the keyset boundary so a cursor walk can skip or duplicate it. Pre-launch, low traffic; revisit if reschedule-while-scrolling matters. [Source: src/jobs/jobs.service.ts:526-560]
- CR3.7-D3 — **Five head-count queries are non-transactional** — concurrent job advances between the five count queries can make `jobCounts` bucket sums disagree with each other/the total momentarily. Same pattern as the pre-3.7 profile payload; tolerable for a dashboard. [Source: src/users/users.service.ts:531-537]
- CR3.7-D4 — **New e2e scope tests compute `getIstDayRange()` after the request completes** — a run straddling IST midnight between the two calls would flake the gte/lt equality assertions. Tiny probability; a fix needs clock injection. [Source: test/jobs.e2e-spec.ts:540-556]

## Deferred from: code review of story 3-8-optional-signature-requirement-flags (2026-09-05)

- CR3.8-D1 — **e2e negative path (signature-skip → 422) uncovered** — the 422 reject is unit-tested only; the e2e suite covers the happy-path advance but not the reject wiring (exception filter, error shape). Same pattern as the pre-existing photo-skip 422. [Source: src/jobs/workflow.service.spec.ts, test/jobs.e2e-spec.ts]
- CR3.8-D2 — **Effective-chain workflow semantics absent from docs/data-models.md** — the doc records only the new column line; the effective-chain successor rule (which steps are required under which flags, walk-past behaviour) lives in code comments and the Swagger description. Story scoped docs to the one line. [Source: docs/data-models.md:118]
- CR3.8-D3 — **`current_step='completed'` untested in validateStep truth table** — `STEP_ORDER.find` returns undefined and every request is rejected (correct), but the row is not pinned; unreachable in practice behind the status guard in `advanceWorkflowStep`. [Source: src/jobs/workflow.service.spec.ts:109]
- CR3.8-D4 — **JSON-null flag PATCH counts as an edit** — `PATCH {"requireCompletionPhoto": null}` passes `@IsOptional`, counts in `hasEdit` (null !== undefined), reaches the RPC as NULL (no change) yet logs `job_updated` and bumps `updated_at`. Pre-existing semantics shared by every nullable PATCH field; flags extend the pattern consistently. [Source: src/jobs/jobs.service.ts:363-373]
- CR3.8-D5 — **Sync payload shape change has no client-versioning note** — `SyncJobDto` gains `requireCompletionSignature` additively; no schema/version marker for the offline mobile client. Pre-launch, additive. [Source: src/sync/dto/sync-response.dto.ts:29]

## Deferred from: code review of story 3-9 (2026-09-05)
- CR3.9-D1 — **Profile embed shapes mirror `toDetailResponse` by comment only** — `ProfileTechnicianEmbed`/`ProfileCustomerEmbed` (users.service.ts) re-declare the GET /jobs/:id detail embed fields with no shared type or parity test; a field added to the detail embed can drift from the profile embed with all suites green. Accepted coupling tradeoff (cross-module type import vs duplication); the mirror invariant is documented on both sides. [Source: src/users/users.service.ts:519-528, src/jobs/jobs.service.ts toDetailResponse]

