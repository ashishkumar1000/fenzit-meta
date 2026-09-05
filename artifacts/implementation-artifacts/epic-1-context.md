# Epic 1 Context: Verified Address Capture for New Customers

<!-- Compiled from planning artifacts. Edit freely. Regenerate with compile-epic-context if planning docs change. -->

## Goal

When adding a customer, owners need a fast way to capture a real, verified address instead of relying on error-prone free text. This epic adds a Google Places–backed address search to the Add Customer flow: the owner searches, picks a suggestion, and the app saves an exact formatted address, pincode, and coordinates against the customer record — while manual free-text entry always remains available as a fallback, so search never becomes a blocker. It spans both `fenzit-be` (proxy endpoints + schema) and `fenzo-app` (picker UI) as one epic because the split has no independent user value on either side. This epic's captured coordinates are what Epic 2 (technician precise-navigation) later builds on.

## Stories

- Story 1.1: Backend — Address autosuggest endpoint
- Story 1.2: Backend — Address resolve endpoint
- Story 1.3: Backend — Persist structured address on customer creation
- Story 1.4: Frontend — Address search screen
- Story 1.5: Frontend — Return selection to Add Customer bottomsheet

## Requirements & Constraints

- Address search is reached by tapping the "Address / map location" field in the Add Customer bottomsheet, opening a dedicated full-screen search with live, debounced suggestions.
- Selecting a suggestion returns the resolved address (and City/Area) to the bottomsheet, but the address text always stays manually editable afterward — the picker never locks a field.
- Submitting "Add customer" sends the resolved structured fields (formatted address, pincode, latitude, longitude, place id) alongside existing customer fields; a customer must still be creatable with only the existing free-text fields and none of the new ones (Places is additive, never mandatory).
- Cost control: one client-generated session token must be shared across every autosuggest call and the terminating resolve call for a search session; the resolve field mask must never include a Pro/Enterprise-tier field; both endpoints are independently rate-limited server-side; the frontend must debounce (~300ms) and enforce a minimum query length (~3 chars) before firing any autosuggest call.
- Search scope is restricted to India, server-side and not client-configurable.
- The Google Places API key must never reach the mobile client — server-side only, IP-restricted.
- A Places/Google outage or a tripped rate limit must never block customer creation — free-text fields remain the standing fallback.
- Both new endpoints require the same auth as customer creation (authenticated JWT + Owner role only).

## Technical Decisions

- Use Google Autocomplete (New) for the type-ahead suggestion list and Place Details (New) to resolve a picked suggestion — not Text Search, which doesn't fit incremental partial-input typing.
- New backend feature module `PlacesModule` (`src/places/`) is DB-less: depends only on the global `CacheModule`, no `SupabaseModule` access, no cross-imports with `CustomersModule`. Abstract `PlacesProvider` class with `GooglePlacesProvider` (Bun native `fetch`, `AbortSignal.timeout(4000)`) and `MockPlacesProvider`, following the same DI-swap convention as the existing `OtpDeliveryProvider`. `resolve()` always returns the normalized `ResolvedPlace` shape — callers never see Google's raw JSON.
- Session token is frontend-owned and generated (UUID v4) when the picker opens; backend is a stateless passthrough and never fabricates or reuses one. It's a required, DTO-validated field on both endpoints.
- API contract: `GET /places/autosuggest?q=&sessionToken=` → `{ suggestions: [{ placeId, text }] }`; `GET /places/resolve/:placeId?sessionToken=` → `ResolvedPlace { placeId, formattedAddress, city: string|null, pincode: string|null, latitude: number, longitude: number }`. `city`/`pincode` are never omitted or empty string, only `null` when absent. If Google returns a valid place with `location` absent, that's a `502 PLACES_UPSTREAM_ERROR`, never a null-coordinate 200. Both routes sit behind the existing `JwtAuthGuard` + `@Roles(Role.OWNER)`.
- Resolve field mask is fixed to `id,formattedAddress,location,addressComponents,postalAddress` (Essentials tier only) — never `displayName` (Pro tier, would silently upgrade billing). Read pincode from `postalAddress.postalCode` (more reliable than parsing `addressComponents`), city from the `addressComponents` entry typed `locality`. Autosuggest is always `includedRegionCodes: ['IN']`, not user-configurable.
- Cost control lives inside `PlacesModule`, not a shared utility: per-endpoint in-memory rate-limit counters (`places:rate:{tenantId}:autosuggest`, `places:rate:{tenantId}:resolve`, same pattern as the existing OTP store) as two independent budgets, `429 RATE_LIMITED` before calling Google; short-TTL result caching (reuse the global 300s `CacheModule` TTL) keyed on query text/region for autosuggest and on `placeId` for resolve. Note from research: because a typical debounced search stays under ~12 requests, the Essentials-only field mask does not unlock free session-wide Autocomplete billing (that only triggers on Pro/Enterprise Place Details) — Essentials-only is still the cheaper overall choice at this feature's expected volume, but it's a real trade-off worth knowing, not a free win.
- Customer schema migration (additive, nullable, via Supabase MCP): `formatted_address TEXT`, `pincode TEXT`, `latitude DOUBLE PRECISION`, `longitude DOUBLE PRECISION`, `place_id TEXT`. No new `area` column — the existing convention of concatenating `area` into `address` client-side before `POST /customers` is unchanged. `CreateCustomerDto` (BE) and `CreateCustomerRequest` (FE) both gain the same 5 fields, all optional.
- `GOOGLE_PLACES_API_KEY` is added to the existing Joi env schema, consumed via `ConfigService.getOrThrow`; IP-restricted server key; the actual key value is supplied at implementation time, not yet provided.
- New frontend feature folder `src/features/addressPicker/` (`AddressPickerScreen.tsx`, `useAddressAutosuggest.ts`) plus a new generic `src/hooks/useDebounce.ts` (none exists today) and `src/services/resources/places.ts`.
- Data return from picker to bottomsheet uses serializable `navigation.setParams`, not a callback-in-params or a global store: `AddressPickerScreen` navigates back with `{ pendingAddress: ResolvedPlace }`; the hosting screen (`CustomersScreen`/`NewJobScreen`) reads it in `useEffect`, feeds it into `AddCustomerSheet`, then clears it via `navigation.setParams({ pendingAddress: undefined })` — mirrors the existing `JobsScreen.tsx` precedent. `AddCustomerSheet`'s local state extends with the 5 optional fields; the free-text `address` input is never made read-only.

## UX & Interaction Patterns

- `AddressPickerScreen` is a pushed native-stack route (not a sheet/modal) reusing the existing screen-header pattern verbatim, with the title slot replaced by an auto-focused search `Input`. Suggestion rows reuse `TechnicianPicker`'s row-card style verbatim (`MapPin` leading icon instead of avatar, spinner in place of a check mark while resolving). No new visual components are introduced anywhere in this epic.
- Eight screen states in strict precedence: Idle (blank, keyboard up) → Below-threshold (1–2 chars, "Keep typing to search") → Loading (previous results stay visible, dimmed, during refetch; stale responses for a superseded query are discarded) → Results → No-results (`EmptyState`, CTA "Enter manually") → Error/nothing-loaded (`EmptyState`, CTA "Retry") → Resolving (whole screen non-interactive, one row at a time) → Resolve-failed (`InlineError` over an intact list, never clearing results).
- Tapping a suggestion triggers the resolve call before navigating back — never an optimistic instant pop; the tapped row is disabled with a spinner until resolve settles.
- Back gesture / header chevron / "Enter manually" all behave as a plain no-op cancel back to the bottomsheet — no confirmation needed, nothing destructive happens by leaving.
- On return to the bottomsheet, there is no toast/snackbar — a brief (~200ms) soft primary-tinted border pulse on the address `Input` is the sole "something changed" signal.
- Accessibility: on entering Results, announce the suggestion count via a live region; suggestion `accessibilityLabel` uses the full formatted address, not just the short name; all interactive elements meet the 44px touch floor.

## Cross-Story Dependencies

- Stories are sequenced backend-first per the meta-repo's cross-repo deploy rule: 1.1 and 1.2 (endpoints) and 1.3 (schema + persistence) must ship in `fenzit-be` before 1.4 and 1.5 (`fenzo-app` UI) can depend on them.
- Story 1.4 (search screen) depends on 1.1 (autosuggest) and 1.2 (resolve) being live; it uses the same session token across both calls per story.
- Story 1.5 (return-to-bottomsheet + submit) depends on 1.4's resolved data shape and on 1.3's persistence fields existing in `CreateCustomerDto`.
- This epic's persisted `latitude`/`longitude` (Story 1.3) is the data dependency for Epic 2 (technician precise-navigation), though Epic 2 ships independently and safely falls back to today's behavior when coordinates are absent.
