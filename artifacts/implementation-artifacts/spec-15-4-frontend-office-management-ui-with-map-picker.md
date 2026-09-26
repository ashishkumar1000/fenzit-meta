---
title: 'Offices management UI with map picker — office list, add/edit, full-screen picker & reverse-geocode proxy'
type: 'feature'
created: '2026-09-26'
status: 'done'
review_loop_iteration: 0
context:
  - '{project-root}/artifacts/planning-artifacts/epics-attendance-leave.md'
  - '{project-root}/artifacts/planning-artifacts/ux-designs/ux-Fenzo-2026-09-25-attendance-leave/EXPERIENCE.md'
  - '{project-root}/artifacts/implementation-artifacts/spec-15-3-backend-offices-and-office-rules.md'
  - '{project-root}/artifacts/implementation-artifacts/spec-google-places-live-provider.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** `attendance_offices` and its rules exist server-side (15-3, live at `ffdebf1`) but the Owner app has no way to see, create, edit, or archive an Office — `attendance_complete_setup` (15-2) requires at least one Office, so the setup wizard (15-8) can never be finished without this screen, and FR-5's map-based placement has no UI at all. The 15-1 spike validated `react-native-maps` (centre-pin pattern, live radius circle) but used keyless Nominatim for search/reverse geocoding, which must not ship.

**Approach:** Three owner-only screens in a new `src/features/attendance/offices/` — **Offices list** (full list fetch, client-side name search, archived section), **Office form** (add/edit: name, pin/radius via the map, timing/hours rule fields), and a **full-screen map picker** (centre-pin + live `colors.primary` circle + radius stepper, three entry paths). Address search reuses the existing `AddressPickerSheet`/`useAddressAutosuggest` stack (`/places/autosuggest` + `/places/resolve/:placeId`, server-side key, already live). One small additive `fenzit-be` piece ships first: `GET /places/reverse` — a server-side Google Geocoding API reverse proxy so the pin's address row is a real resolved address, retiring the spike's Nominatim. The map picker screen replaces `MapSpikeScreen` as the map-library consumer; the spike is deleted in this story once the real picker is device-confirmed.

**Scope decisions locked with the user (2026-09-26):**
- The **fenzit-be reverse-geocode proxy is in-story** and ships first (additive change, per cross-repo ordering). Autosuggest/resolve already exist live (`spec-google-places-live-provider`) — only reverse geocoding is new.
- Office list gets **no pagination**: the endpoint stays unbounded and the screen fetches the full list, filtering client-side by name. Offices are physical branches — tens per tenant, not thousands. Revisit server-side pagination only if a tenant ever exceeds ~100 offices (not a tracked work item until then).
- Search on the map screen reuses `AddressPickerSheet` as-is; manual address entry is hidden there (a hand-typed address has no coordinates, so it cannot move the pin) via a new optional prop — existing Add-Customer behaviour unchanged.
- The **archive-blocker "shortcut into the Employees list filtered to this Office"** shows the blocking count in this story, but the navigation target does not exist until 15-9 — the shortcut tap lands in 15-9/15-10 (recorded in deferred-work).
- The spike deletion (MapSpikeScreen + `mapSpike/` + routes + Today test button + temporary `initialRouteName`) is a final task of this story, after device confirmation.
- **No address persistence**: `attendance_offices` stores coordinates only (15-3 schema frozen); the resolved address is picker-time display, never saved.

## Boundaries & Constraints

**Always:**
- Cross-repo ordering: the additive `/places/reverse` endpoint merges/deploys **first** (fenzit-be), then the fenzo-app story — state it in the hand-off.
- All UI on design-system tokens/components (`@theme`, `@components/ui`), relative imports (aliases not yet adopted), ~300-line file limit, one screen per route, sentence-case copy, no emoji.
- Map picker follows the validated 15-1 spike pattern: pin is a static React overlay at screen centre (`pointerEvents: 'none'`), the map pans under it, settled centre read from `onRegionChangeComplete` — never a draggable native `Marker` (spike finding: long-press-to-lift undiscoverable, drag janky on Fabric).
- The geofence `Circle` (stroke `colors.primary`, soft fill ≈16% opacity) redraws live as the radius stepper/slider changes — no separate preview step (UX-DR3). Stepper/slider is a standard accessible control announcing the value on every change ("Radius, 100 metres").
- The **final pin position** is what's saved — a search result only moves the map to a starting point (EXPERIENCE.md, Office map picker).
- Radius range mirrors the DB (50–1000 m, 15-3 CHECKs); the stepper clamps client-side so 422 never happens in practice. Default for a new office: 100 m (BE create default).
- Reverse-geocode (pin address row) fires **on settle only** — one call per settled centre, latest-wins abort (the `useAddressAutosuggest` abort pattern), never per-frame while panning. On failure or "no address here", the row falls back to the raw coordinates; never blocks confirming.
- Current-location path requests a **fresh** high-accuracy fix (no cached), behind the existing permission patterns from Stories 7-5/7-6; the permission status is checked before `getCurrentPosition` (the 15-1 iOS-carry-forward — attempted in this story, both platforms).
- Map-unavailable fallback (AC): if the map errors or the network is down, the map area shows a plain "Map unavailable" message — current-location and address-search still work; never freeze, never fail silently.
- Office create/edit submits to the 15-3 routes: `POST /attendance/offices` (201), `PATCH /attendance/offices/:id` (profile fields plain; rules fields → the effective-dated RPC; a complete rules set is required — partial set is a 400, already pinned server-side). Edit-mode copy for rule changes states "Changes take effect from tomorrow" (server-enforced).
- Archive: `POST /attendance/offices/:id/archive` (204). On 409 `ATTENDANCE_OFFICE_ARCHIVE_BLOCKED` show the inline blocking-employee count from `blockers` in the error extra (EXPERIENCE.md, Office archive) — with a "Review employees" action only once the Employees-list route exists (15-9); until then the count message renders without the shortcut.
- Delete the spike in the same story it's replaced — files, route registrations in `RootNavigator`/`TechnicianRootNavigator`/`types.ts`, the temporary `initialRouteName`, and the TodayScreen test button.

**Ask First:**
- If `GOOGLE_PLACES_API_KEY` cannot have the **Geocoding API** enabled on its restrictions (console change) — confirm before adding a fallback `GOOGLE_GEOCODING_API_KEY` env var.
- If `react-native-maps`' Circle live-redraw misbehaves with this screen's re-mount cadence, the re-key remount workaround from the spike is the sanctioned escape hatch — confirm before relying on it as the norm.
- If iOS map rendering can't be device-validated (needs the Xcode machine), confirm carrying that validation forward rather than silently skipping.

**Never:**
- No Nominatim (or any keyless geocoding) in shipped code — the spike's `geocoding.ts` dies with the spike.
- No office create/edit calls from the meta-repo perspective of "wizard only" — this story ships the standalone offices screens; 15-8's wizard will deep-link/reuse them, not the reverse.
- No effective-dating UI for pin/radius edits — profile fields apply immediately (15-3's one-PATCH split); only the rules group carries the effective-from copy.
- No pagination, infinite scroll, or server-side `q` search on the office list in this story (locked decision above).
- No tests written before the user confirms the flow works on device (test-timing rule).

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| BE reverse geocode, addressable point | `GET /places/reverse?lat=&lng=`, owner JWT, Google 200 with results | 200 `{ formattedAddress, city, pincode }` (null-safe `city`/`pincode`, 15-3/1-2 pattern) | — |
| BE reverse geocode, no address (open water) | Google 200, zero results | 200 `{ formattedAddress: null, city: null, pincode: null }` — never a null-coordinate-style throw | — |
| BE reverse geocode upstream failure | Google non-2xx / timeout (4000ms abort) | Provider throws plain `Error` | 502 `PLACES_UPSTREAM_ERROR` (existing mapping); owner-only → 403 for technician |
| BE reverse geocode invalid input | lat/lng out of range, non-numeric, or empty (`?lat=&lng=`) | — | 422 at the ValidationPipe (DTO `@Min/@Max` bounds + empty-string guard), before the (billable) provider — renegotiated 2026-09-27, supersedes the frozen "non-finite input → 502" row |
| FE map picker opens from form | empty pin (add) or existing office pin (edit) | Full-screen map centred on initial pin (or last fix / India-bounded default when none), circle at current radius, bottom sheet per mockup | Map load failure → "Map unavailable" message in map area; sheet fully interactive |
| Owner taps "Use my current location" | permission granted | Fresh GPS fix → map animates centre to it; address row reverse-geocodes | Permission never granted → "Turn on location to place the pin" opening the existing permission flow; denied twice → deep-link OS Settings; fix timeout → its own message, distinct from denied |
| Owner searches an address | AddressPickerSheet presented | Existing 8-phase search UX, zero new search states; resolved place moves the map centre (starting point only) | Search/resolve errors already handled by the reused 8-state hook; no manual-entry row in this context |
| Owner pans the map | centre settles | Reverse geocode fires once on settle (latest-wins); address row updates ("Pinned near: …") | Reverse fails/no address → row shows "12.9731, 77.6170" (lat/lng); confirm still enabled |
| Owner changes radius | stepper −/+ (and preset chips 100/200/500 m) within 50–1000 — renegotiated 2026-09-27, replaces the frozen "(and slider)" wording (slider would have required adding @react-native-community/slider for little gain) | Circle redraws live, no preview step; value announced ("Radius, 100 metres") | Clamped at bounds; no API call until Confirm |
| Owner confirms | taps "Confirm location" | Returns `{ latitude, longitude, radiusM }` to the form (navigate-back-with-params, SelectSkills pattern) | — |
| Office list renders | any office count | Full list (owner-only): name + radius + today's timing summary; archived rows grouped read-only behind an "Archived" disclosure; client-side name filter appears once the list exceeds ~8 rows | Loading spinner — renegotiated 2026-09-27, replaces the frozen "Loading skeleton" wording (spinner chosen over grey placeholder rows for a small ~8-row list); error state with retry; empty state "No offices yet" with the Add CTA (the 15-2/15-3 gating means a first-run owner lands here) |
| Owner saves a new office | valid form | `POST` → 201 → back to list showing the new office; rules seeded `[today, ∞)` by the RPC | 409 name-taken → inline field error; 422 → per-field validation mirroring DB ranges; offline → graceful retry, no silent loss |
| Owner edits an existing office | form pre-filled; rule edits carry "takes effect from tomorrow" copy | `PATCH` → 200 | 404 (archived/unknown) → back to list with a notice; 400/422 per 15-3 contract |
| Owner archives an unblocked office | confirm dialog (standard destructive pattern) | `POST :id/archive` → 204 → row moves to Archived group | 409 with blockers → inline "{n} employees are still assigned here — reassign them first" (no dead-end error); shortcut wired in 15-9 |
| Map unavailable, owner uses search | map tiles failed | AddressPickerSheet still resolves → pin can be placed blind (address row shows resolved address); confirm works | Same as happy path — search never depends on tile rendering |

</frozen-after-approval>

## Code Map

Investigation evidence (2026-09-26; paths relative to `fenzo-app/` unless noted):

- **15-1 spike findings** — `src/screens/MapSpikeScreen.tsx:1-49` header: centre-pin pattern validated on Android Google Maps (Fabric, `react-native-maps` 1.29.8); Circle live-redraw confirmed, re-key only as escape hatch; iOS half wired (`provider="google"` both platforms, Podfile `react-native-maps/Google` subspec) but **not device-validated**; "15.4 should carry a tokenised light style" (`customMapStyle`); Nominatim `src/screens/mapSpike/geocoding.ts` is throwaway — real picker routes search + reverse geocode through `fenzit-be`.
- **Existing search surface to reuse** — `src/features/addressPicker/AddressPickerSheet.tsx` (bottom-sheet modal; props `{ visible, onClose, onResolved(ResolvedPlace), onManualAddress }`), `useAddressAutosuggest.ts` (session token, debounce, 8 phases, latest-wins abort), `SearchPhaseBody`, `src/services/resources/places.ts` (`placesService.autosuggest/resolve`, `ResolvedPlace` shape with `latitude/longitude/formattedAddress`). Change here: make `onManualAddress` optional — undefined hides the "Enter manually" fallback (additive; `AddCustomerScreen` unaffected).
- **BE places module** — `fenzit-be/src/places/places.controller.ts` (`@Controller('places')`, `@Get('autosuggest')`, `@Get('resolve/:placeId')`, owner-only): this story adds `@Get('reverse')` sibling. `places.service.ts`'s catch-and-map-to-502 needs zero changes (spec-google-places precedent). `places-rate-limit.store.ts` + the `PLACES_{AUTOSUGGEST,RESOLVE}_RATE_LIMIT_{MAX,WINDOW_SECONDS}` env pattern (app.module.ts) → mirror as `PLACES_REVERSE_RATE_LIMIT_{MAX,WINDOW_SECONDS}`.
- **BE provider** — `fenzit-be/src/places/places-provider.ts` abstract + `google-places.provider.ts` (key server-side only, never logged: `X-Goog-Api-Key` header for Places (New), `key=` query param for the legacy Geocoding API — renegotiated 2026-09-27, live-verified 2026-09-26) + `mock-places.provider.ts`: add `reverseGeocode(lat, lng)` to the interface; Google impl hits the Geocoding API (`maps.googleapis.com/maps/api/geocode/json?latlng=…`) with the same server key (Geocoding API enabled — Ask First if restricted); mock returns a fixed Bengaluru-style fixture; `MockPlacesProvider` keeps its no-network contract.
- **Backend office surface (15-3, live)** — `GET/POST /attendance/offices`, `GET/PATCH /attendance/offices/:id`, `POST …/:id/archive` (409 `ATTENDANCE_OFFICE_ARCHIVE_BLOCKED` with `blockers` in the filter's `extra`), `GET …/:id/archive/preview`; DTOs: name ≤80, radius 50–1000, cross-field time/hours checks (422). `docs/api-contracts.md` offices section is the FE contract source.
- **Nav pattern** — `src/navigation/types.ts` `RootStackParamList` (owner stack; MapSpike currently temporary `initialRouteName` — delete with the story): add `AttendanceOffices: undefined`, `OfficeForm: { officeId?: string } | undefined`, `OfficeMapPicker: { initialLatitude?: number; initialLongitude?: number; radiusM: number } | undefined` — the picker returns via the SelectSkills navigate-back-with-params pattern. Entry point: a row on the More tab (`src/features/more/MoreScreen.tsx`, owner-only).
- **Permission precedent** — Stories 7-5/7-6 (`LocationCapture` flow): permission config/consent patterns to mirror for the owner-side locate-me; spike's `PermissionsAndroid` usage is the Android half, `PermissionsAndroid`+iOS pre-check the new part.
- **Theme** — `src/theme/` tokens + `DESIGN_SYSTEM.md`; new tokenised map style (light, matching palette) goes in `src/theme/mapStyle.ts` — no inline style JSON in the screen.

## Tasks & Acceptance

**Execution (fenzit-be first):**
- [ ] `src/places/places-provider.ts` + `google-places.provider.ts` + `mock-places.provider.ts` — `reverseGeocode(lat, lng)` interface method + implementations (Geocoding API via Bun `fetch` + 4000ms abort; plain-`Error` throwing; key server-side only, never logged (`X-Goog-Api-Key` header for Places (New); `key=` query param for legacy Geocoding — renegotiated 2026-09-27)).
- [ ] `src/places/places.service.ts` + `places.controller.ts` + dto — `GET /places/reverse?lat=&lng=` (owner-only, rate-limited, 200 `{ formattedAddress, city, pincode }` with nulls, 502 on upstream failure); `docs/api-contracts.md` places section updated in the same change.
- [ ] Hand-off note: fenzit-be merges/deploys **first**.
- [ ] `src/theme/mapStyle.ts` — tokenised light Google Maps style JSON.
- [ ] `src/services/resources/offices.ts` — `officesService` over the shared `apiClient`: list (`includeArchived`), detail, create, patch, archive; maps 409 extra `blockers`; typed Office model in `src/types/`.
- [ ] `src/features/attendance/offices/OfficesScreen.tsx` (+ hook + row component) — list, client-side name search, Archived disclosure, Add CTA, empty/loading/error states.
- [ ] `src/features/attendance/offices/OfficeFormScreen.tsx` (+ small components) — add/edit: name, location summary row (resolved address or coordinates, opens picker), radius readout, rule fields with tomorrow-effective copy; archive action with confirm; 409 blocker count message.
- [ ] `src/features/attendance/offices/OfficeMapPickerScreen.tsx` (+ `useLocateMe` hook) — centre-pin + live circle + accessible radius stepper/slider; locate-me with permission pre-check; AddressPickerSheet entry; settle-only reverse geocode with lat/lng fallback; "Map unavailable" fallback; confirm returns coordinates via nav params.
- [ ] `AddressPickerSheet` — `onManualAddress` becomes optional (hide manual entry when absent); existing caller untouched.
- [ ] Navigation — three routes registered in `types.ts` + `RootNavigator`; More-tab row (owner-only).
- [ ] Delete the spike: `src/screens/MapSpikeScreen.tsx`, `src/screens/mapSpike/`, registrations in `RootNavigator`/`TechnicianRootNavigator`/`types.ts` (both stacks), the temporary `initialRouteName`, the TodayScreen test button — **after** the user confirms the real picker works on device.
- [ ] Post-confirmation tests (per test-timing rule): `offices.test.ts` (service), hook/screen tests mirroring `addressPicker`'s patterns, `places.service.spec`/provider-spec additions for `reverseGeocode` on the BE side; run full `bun run test` suites in both repos.

**Acceptance Criteria:**
- Given an owner on the Offices list, when they add an office and place the pin via any of the three paths (current location, address search, pan-to-place), then the confirmed pin position and radius are what the create payload carries — a search result is never the saved value by itself.
- Given the radius stepper changes value, then the geofence circle redraws live with no preview step, and each change is announced to screen readers.
- Given the map fails to load, then the "Map unavailable" message shows while current-location and address-search still function — no freeze, no silent failure.
- Given an archive attempt on an office with assigned employees (post-15-7), then the UI shows the blocking count inline rather than a dead-end error; the Employees-list shortcut follows in 15-9.
- Given the reverse-geocode proxy deployed, then `GET /places/reverse` is owner-only, rate-limited like its siblings, returns null-safe `formattedAddress/city/pincode`, and never exposes the Google key; the FE pin row shows a real address, falling back to coordinates.
- Given a signed-in technician, then none of the new screens or endpoints are reachable (403 / no routes).
- Given the spike is deleted, then nothing Nominatim-based remains, the temporary `initialRouteName` is gone, and the app boots to the pre-spike tab layout.
- Given all previously green suites run after the change, then every one stays green in both repos.

## Design Notes

**Why the BE piece is one endpoint, not a new module:** autosuggest/resolve already live in `PlacesModule` with a provider abstraction, rate-limit store, and 502 mapping; reverse geocoding is the same story shape (third-party passthrough → normalised contract) in the same module. A separate module would duplicate all four.

**Why Google Geocoding API rather than Places for reverse:** Places (New) has no reverse-geocode surface; the legacy Geocoding API is the standard server-side reverse lookup. It uses the same server key (no session tokens — billed per call), hence no `sessionToken` param and the standard per-endpoint rate limit instead.

**Why client-side search over the list:** per-tenant office counts are physical-branch scale (tens); an unbounded endpoint plus client-side filter avoids a BE change for a problem that cannot realistically occur at this scale — the recorded threshold (~100 offices) names when to revisit.

**Why reuse `AddressPickerSheet` rather than a new search screen:** the AC says "reusing the existing Address Autosuggest screen"; the sheet already owns the 8 search states, session tokens, and accessibility announcements — the only delta is hiding manual entry, which cannot produce a coordinate pin.

**Why settle-only reverse geocoding:** continuous reverse geocoding while panning would hammer the rate-limited endpoint (and Google billing); the address row is a confirmation aid, not a live feed — one call per settled centre, superseded calls aborted.

**Why the blocker shortcut is deferred:** the 409 path can never fire until 15-7 (fail-loud pre-enrolment), and the Employees list it points to is 15-9's screen; shipping a dead navigation target now would be worse than a count-only message. Named blocking story recorded in `deferred-work.md`.

## Verification

(to be filled during implementation — commands, device walkthrough, post-confirmation tests)

### BE /places/reverse — applied + walked live 2026-09-26 (pre-tests)

**Files:** `places-provider.ts` (`ReverseGeocodedAddress` + `reverseGeocode` abstract), `google-places.provider.ts` (legacy Geocoding API impl), `mock-places.provider.ts` (fixture-coords + Null-Island sentinel `SIMULATE_REVERSE_ERROR_POINT`), `places.service.ts` (`reverse()` + `REVERSE_RATE_LIMIT_*` 10/60s), `places.controller.ts` (`@Get('reverse')`, owner-only), `dto/reverse-query.dto.ts` + `dto/reverse-response.dto.ts` (new), `app.module.ts` (Joi env), `.env.example`, `docs/api-contracts.md` (new Places section — the Places endpoints had never been documented there; all three added).

**Live walkthrough** (Nest on :3000, owner/technician HS256 JWTs minted from `SUPABASE_JWT_SECRET`, throwaway scripts deleted after):
1. `?lat=19.1364&lng=72.8296` (owner) → `200` `{"formattedAddress":"102c, Shastri Nagar, Andheri West, Mumbai, Maharashtra 400053, India","city":"Mumbai","pincode":"400053"}` — real Google Geocoding through the new provider.
2. `?lat=0&lng=0` → `200` all-nulls — the ZERO_RESULTS → null-address contract.
3. `?lat=999` / `?lat=abc` → `422`.
4. 11th call in the window → `429` (Retry-After header).
5. Technician JWT → `403`; no JWT → `401`.
6. Pre-fix failure path: `502 PLACES_UPSTREAM_ERROR` with the provider's `Error` (incl. Google's `error_message`) logged with correlation_id.

**Two deviations found by the walkthrough (both folded in):**
- **Auth form:** legacy Geocoding ignores `X-Goog-Api-Key` (Places New convention) — key passed as the documented `key=` query param instead. URL is never logged; error messages carry only status + Google's `error_message`. The spec's "key only in headers" line is narrowed to "key never in logs/responses; header for Places (New), `key=` param for legacy Geocoding".
- **Ask-First resolution:** `REQUEST_DENIED` was first the key's API restriction — user enabled **Geocoding API** on the `fenzit-maps` key's API restrictions (console, 2026-09-26); no fallback `GOOGLE_GEOCODING_API_KEY` env needed. Secondary cause was the auth form above.

### FE screens — built 2026-09-26 (pre-device, pre-tests)

**Files (fenzo-app):** `src/theme/mapStyle.ts` (+ `LIGHT_MAP_STYLE` export in theme barrel) · `src/types/office.ts` (+ types barrel) · `src/services/resources/offices.ts` (`officesService.list/get/create/update/archive/archivePreview`, 409 blockers read from `ApiError.details.blockers` — the filter forwards non-envelope keys to the body's top level) + `reverse()` added to `places.ts` (+ resources barrel) · `src/features/attendance/offices/` — `OfficesScreen` (+ `useOffices`, `OfficeListRow`), `OfficeFormScreen` (+ `officeFormModel`, `OfficeLocationCard`, `OfficeRuleFields`), `OfficeMapPickerScreen` (+ `PickerMapArea`, `PickerBottomCard`, `RadiusStepper`, `useLocateMe`, `ScreenHeader`) · `AddressPickerSheet`/`SearchPhaseBody` — `onManualAddress`/`onEnterManual` now optional (manual entry hidden for the picker; AddCustomer unchanged) · `types.ts` (three routes: `AttendanceOffices` / `OfficeForm { officeId?, pickedLocation? }` / `OfficeMapPicker { initialLatitude?, initialLongitude?, radiusM }`) + `RootNavigator` registrations + More-tab "Offices" row.

**Deviations/decisions found during the build (all folded in):**
1. **Map-unavailable detection:** react-native-maps 1.29.8 exposes **no `onError` prop** — the fallback is detected as "onMapLoaded never fired within 10 s", which covers the network-down/tile-failure case the AC names. Locate-me and search stay functional over the fallback (pin state set directly, Confirm unaffected).
2. **Radius control = stepper + preset chips (100/200/500 m)** — the spec's "(and slider)" needs `@react-native-community/slider`, a native dependency not in the app; a native module added purely for this knob is out of proportion. Stepper steps 50 m and is clamped 50–1000; value announced ("Radius, N metres") per AC.
3. **Silent initial fix is Android-only** (spike precedent): iOS has no promptless permission check via the nitro API, so iOS opens on the India-bounded default; the locate button prompts on both platforms. `OfficeMapPicker` uses `PermissionsAndroid.check` only (no prompt on open).
4. **Edit PATCH sends only changed fields** — an unchanged rules save must not seed a redundant effective-dated row from tomorrow, so `officeFormModel.rulesChanged/profileChanged` gate what goes on the wire; a complete five-field set is still sent whenever any rule field changed.
5. **`src/types/office.ts` for the Office model** per the Code Map (types folder was empty/unused until now; resource file carries request shapes, matching `customers.ts`).
6. **jest.setup.js `react-native-maps` mock added:** `__tests__/App.test.tsx` was already failing at HEAD (pre-existing — the 15-1 spike's unmocked map import; verified by stash/unstash). The new map screens reach the same import, so the suite-wide mock was added now; **126 suites / 1215 tests green** (baseline was 125 + 1 broken). tsc clean.
7. **Edit-page polish (2026-09-26, user-supplied HTML/visual reference):** form restyled to sectioned cards — name input with building icon + required marker; location card with inset coordinates panel (primary pin chip, eyebrow + value, compass detail); timing card with clock icon title, "Changes take effect from tomorrow" as an info chip, and unit suffixes ("mins", "hrs") via a new `Input.trailingAdornment` prop; header gained `ScreenHeader.right` hosting a blue "Active" Badge (edit mode); Save/Archive buttons carry Check/Archive lucide icons. The "GPS Verified" chip is **real, not decorative**: `PickedOfficeLocation.gpsVerified` is set only when the confirmed pin came from the device's own fix (locate-me or the silent Android initial fix); a user pan or search result clears it (programmatic `animateToRegion` moves are matched on settle via a target ref so animations don't clear the flag), and an edit-loaded office hides the chip (unknown provenance). Deliberately not copied from the reference: no gradient save button (flat-design rule — primary Button), no uppercase label typography (the DS label style stands), "Grace period" renders as the Input helper below the field. Payload building moved to `officeFormModel` (`buildCreateRequest`/`buildUpdatePatch`) to keep the screen under 300 lines.

**Spike deletion + post-confirmation tests (2026-09-27, user go-ahead):**
- **Spike deleted:** `src/screens/MapSpikeScreen.tsx` + `src/screens/mapSpike/`, both-stack route registrations (owner `RootNavigator`, `TechnicianRootNavigator`), both `MapSpike` param types, the Today-screen test button (and its now-unused `Map` lucide import). `mapStyle.ts` doc comment de-referenced the deleted screen. tsc clean.
- **FE tests (51 new across 4 files):** `services/resources/offices.test.ts` (URLs/params/encoding + unwrapping contracts), `features/attendance/offices/officeFormModel.test.ts` (validation ranges vs the 422s, latest-rule pick from the ascending history, diff gates, complete-rules-set builders), `useOffices.test.tsx` (active/archived split, error surface, throttled focus refresh), `useLocateMe.test.tsx` (permission/fix pipeline, denied-twice Settings deep-link, timeout vs failed copy).
- **Real bug caught by the useOffices tests:** the throttled focus callback read state `hasLoaded` inside a `useCallback([fetchList])` — the memoised closure keeps the first render's `false` forever, so the throttle never throttled (every refocus refetched). Fixed with a `hasLoadedRef` mirror; the hook comment documents why.
- **BE tests (reverse geocode, previously zero coverage):** `places.service.spec.ts` new `describe('reverse')` (happy path, null-address passthrough, 429, provider/store 502s), `google-places.provider.spec.ts` new `reverseGeocode` describes (latlng + `key=` query-param auth, ZERO_RESULTS/empty-results → null-address, non-OK/non-2xx/timeout throws, empty-string → null normalization), `mock-places.provider.spec.ts` new `reverseGeocode` describes (fixture coords + tolerance, unknown point, Null-Island sentinel gated on NODE_ENV).

**Suite state (2026-09-27):** fenzo-app **130 suites / 1266 tests** green, tsc clean; fenzit-be **57 suites / 852 tests** green, tsc 65 = unchanged baseline (0 from `src/places`; the two pre-existing `places.service.spec.ts` mock-typing errors unchanged). Session gotcha: jest requires the `.nvmrc` Node on PATH (`export PATH="$HOME/.nvm/versions/node/v24.13.0/bin:$PATH"`) — recorded in agent memory.

**Next:** `/bmad-code-review` → commit (fenzit-be merges/deploys first; the 15-3 archive migration is already applied to production via MCP).

**Archive 500 fix (2026-09-26, during device walkthrough):** the device archive call returned 500 — root cause is a 15-3 issue, not FE: the `attendance_archive_office` blocker probe queried `attendance_office_assignments` (a 15-7 table) and failed at plan time (42P01, confirmed in production DB logs). Amended per `spec-15-3` Resolution — migration `20260926000008_archive_blocker_table_guard.sql` (branch on `to_regclass`, nested IF for lazy planning) applied via MCP and verified live in a rolled-back transaction. Archive now returns 204 pre-15-7; retry on device.

**Suite state:** unit 57 suites / 834 passed (baseline parity); tsc 65 = unchanged baseline (0 from `src/places`; the two pre-existing `places.service.spec.ts` mock-typing errors unchanged). Session gotcha: jest requires the `.nvmrc` Node on PATH (`export PATH="$HOME/.nvm/versions/node/v24.13.0/bin:$PATH"`) — recorded in agent memory.

**Next:** FE screens (list → form → map picker); post-confirmation tests for both sides after the user confirms the app flow on device.
### Review Findings — group 1/3: fenzit-be reverse geocode (BMAD 4-layer, 2026-09-27)

**Decision-needed**
- [x] [Review][Decision] Frozen "key only in headers, never in a query string" deviated for the Geocoding API — **resolved 2026-09-27: renegotiation recorded** — both frozen texts amended (Code Map line in this spec + constraint note in spec-google-places-live-provider.md); key never in logs/responses, header for Places (New), `key=` param for legacy Geocoding. without a recorded renegotiation — `google-places.provider.ts` sends `key=` in the query (live-verified 2026-09-26: header auth returns REQUEST_DENIED on the legacy Geocoding API); the frozen Code Map line in this spec and the frozen constraint in spec-google-places-live-provider.md still say headers-only.
- [x] [Review][Decision] I/O matrix row "non-finite input → 502" contradicted by the implementation — **resolved 2026-09-27: matrix amended** — upstream-failure row narrowed to non-2xx/timeout → 502; new row pins out-of-range/non-numeric/empty input → 422 at the DTO before the provider. — out-of-range/non-numeric/empty input is rejected 422 at the DTO and never reaches the provider; docs and the live walkthrough pin 422, but the frozen matrix row was never amended.

**Patch**
- [x] [Review][Patch] Archive-blocker guard checks only `attendance_office_assignments` — **fixed 2026-09-27** — guard now ANDs both `to_regclass` calls; corrected function also applied to production (via MCP; migration was not in prod's history),; the probe also references `attendance_enrolments` — guard both `to_regclass` calls or 15-7's rollout window can re-42P01 the archive [fenzit-be/supabase/migrations/20260926000008_archive_blocker_table_guard.sql:69-74]
- [x] [Review][Patch] `?lat=&lng=` silently coerces to Null Island (0,0) instead of 422 (`Number('') === 0`) — **fixed 2026-09-27** — `@Type` runs before `@Transform` in class-transformer, so the DTO drops `@Type` and converts inside `@Transform` (empty → undefined → 422; non-numeric stays a string → 422), — add an empty-string guard to `ReverseQueryDto` [fenzit-be/src/places/dto/reverse-query.dto.ts]
- [x] [Review][Patch] `GET /places/reverse` has no HTTP-boundary test — **added 2026-09-27** — `describe('GET /api/v1/places/reverse')` in test/places.e2e-spec.ts: 200 fixture, 200 null shape, 401/403, 422 (lat=90.1, empty params, missing lat), 502 sentinel, 429 via real limiter; e2e 32/32 green,, unlike its sibling routes — add an e2e describe in `test/places.e2e-spec.ts` mirroring resolve (200 fixture, 200 null shape, 401/403, 422 boundary values incl. lat=90.1 and empty params, 429, 502 via sentinel) [fenzit-be/test/places.e2e-spec.ts]
- [x] [Review][Patch] rls-isolation (c4) archive assertion still accepts the pre-migration 42P01 branch — **tightened 2026-09-27** — asserts `archiveError` null + archived_at stamped + idempotent re-archive, unconditionally, — tighten to assert archive succeeds unconditionally (comment already declares that outcome) [fenzit-be/test/integration/rls-isolation.integration.spec.ts:2044-2071]
- [x] [Review][Patch] Missing trailing newlines on 3 new files — **fixed 2026-09-27** — also api-contracts.md had one; all four files now end with a newline, [fenzit-be/src/places/dto/reverse-query.dto.ts, reverse-response.dto.ts, supabase/migrations/20260926000008]
- [x] [Review][Patch] Stale doc comment: "MockPlacesProvider is the only binding today" — **fixed 2026-09-27** — comment now names the actual bindings (Google outside tests, mock in tests), — GooglePlacesProvider has bound non-test since the live-provider story [fenzit-be/src/places/places-provider.ts:39-40]
- [x] [Review][Patch] api-contracts.md: show the null-address 200 JSON example — **added 2026-09-27** — null-address example follows the populated one, alongside the populated one (the payload the FE must handle for open-water pins) [fenzit-be/docs/api-contracts.md:68-89]

**Deferred**
- [x] [Review][Defer] `attendance_archive_office` accepts `p_actor_id` but never uses it — no audit trail of who archived an office — deferred, pre-existing 15-3 shape
- [x] [Review][Defer] Geocoding request sends no `language`/`region` param — formattedAddress locale uncontrolled — deferred
- [x] [Review][Defer] No cache/dedupe on reverse — repeated pan-settles re-hit Google; budget consumed even on upstream failure — deferred
- [x] [Review][Defer] city = locality-only (no sublocality/admin fallback) — rural pins may return null city; mirrors the pinned resolve contract; the meaning of "city" for the address row is a product call — deferred

Dismissed as noise: 4 (NODE_ENV-restore false positive — the spec restores it in afterEach; defensive WHERE on the final UPDATE — tenant lock is held; sentinel collision at (0,0) — confined to the mock/test binding, mirrors the existing sentinel precedent; duplicated fixture coordinates — conceptually distinct sets).
### Review Findings — group 2/3: fenzo-app production code (BMAD 4-layer, 2026-09-27)

**Decision-needed**
- [x] [Review][Decision] The 30s focus throttle blocks the very refetch the hook promises — **resolved 2026-09-27: option (b)** — drop the throttle entirely; focus always refetches (throttle constants, hasLoadedRef memo hack and throttle tests removed) — `useOffices` comment says "returning from the form re-fetches so a create/edit/archive is visible", but a create → goBack inside the 30s window skips the refetch and nothing else refreshes the list (no pull-to-refresh); 4 layers converged on this. [fenzo-app/src/features/attendance/offices/useOffices.ts:62-72]
- [x] [Review][Decision] Two frozen I/O-matrix rows deviate without amendment — **resolved 2026-09-27: option (a)** — both matrix rows amended below (stepper + preset chips; loading spinner) — (a) "stepper −/+ (and slider)" → implemented as stepper + preset chips (slider dropped, decision recorded in Verification only); (b) "Loading skeleton" → implemented as ActivityIndicator spinner on OfficesScreen/OfficeFormScreen. [spec I/O matrix rows: FE radius / office list renders]

**Patch**
- [x] [Review][Patch] Edit save is a silent no-op when the office failed to load (non-404): `handleSave` gates the PATCH on `detail`, so with `detail === null` it validates, does nothing, and goBack()s — user believes the save succeeded [fenzo-app/src/features/attendance/offices/OfficeFormScreen.tsx:113-126] — **fixed 2026-09-27** (fail-loud saveError branch; no goBack)
- [x] [Review][Patch] iOS silent initial fix contradicts its own comment: the platform check only gates Android, then `getCurrentPosition()` runs unconditionally on iOS — CoreLocation prompts at map open, exactly what the "no prompt" path documents against [fenzo-app/src/features/attendance/offices/OfficeMapPickerScreen.tsx:95-119] — **fixed 2026-09-27** (whole silent fix Android-only; iOS stays on the default)
- [x] [Review][Patch] Confirm mid-pan returns the previous settled centre: `handleConfirm` reads `settled` (only set on onRegionChangeComplete) while the visible centre pin is at `pin`; no isPanning guard [fenzo-app/src/features/attendance/offices/OfficeMapPickerScreen.tsx:188-201] — **fixed 2026-09-27** (confirm the live `pin` while panning, `settled` after settle)
- [x] [Review][Patch] Map failure is terminal: after the 10s deadline `mapFailed` unmounts MapView permanently — a slow (not failed) map never recovers; fallback panel has no Retry [fenzo-app/src/features/attendance/offices/OfficeMapPickerScreen.tsx:70-77] — **fixed 2026-09-27** (Retry re-mounts the map and restarts the load deadline)
- [x] [Review][Patch] `lateCutoffMinutes` cleared to empty validates as 0 (`Number('') === 0` passes 0–120) and silently saves a 0-minute grace period [fenzo-app/src/features/attendance/offices/officeFormModel.ts:98-101] — **fixed 2026-09-27** (empty/whitespace is its own error, checked before the 0–120 range)
- [x] [Review][Patch] `validateOfficeForm` has no radius check though its header claims "radius 50–1000 mirrored so a 422 can never happen" — the only 50–1000 guard is the untested RadiusStepper clamp [fenzo-app/src/features/attendance/offices/officeFormModel.ts:4,86-107] — **fixed 2026-09-27** (50–1000 check in the model, `radiusM` error key, pinned by tests)
- [x] [Review][Patch] `useLocateMe.locate()` has no catch around `requestLocationPermission()` — geolocation.ts rethrows permission-plumbing errors and the screen does `void handleLocate()`, surfacing as an unhandled rejection with no feedback [fenzo-app/src/features/attendance/offices/useLocateMe.ts:57-64] — **fixed 2026-09-27** (permission-plumbing errors map to the failed shape)
- [x] [Review][Patch] Locate-me fix is not guaranteed fresh/high-accuracy: `geolocation.getCurrentPosition` passes no options (no `enableHighAccuracy`, no `maximumAge: 0`), contradicting the "fresh high-accuracy fix (never cached)" constraint [fenzo-app/src/features/technicianApp/geolocation.ts:76-96] — **fixed 2026-09-27** ({enableHighAccuracy, maximumAge: 0, timeout}); also fixed while here: the compat layer passes a plain {code,message} object so String(error) printed "[object Object]" and the message-based classification never matched — now classified on the numeric geolocation-spec code (user-reported device log 2026-09-27)
- [x] [Review][Patch] `useOffices` has no stale-response guard — a slow refetch can resolve after a newer one and overwrite fresher list data (no sequence/abort) [fenzo-app/src/features/attendance/offices/useOffices.ts:44-58] — **fixed 2026-09-27** (latest-wins seq guard; slow earlier fetch can neither overwrite rows/error nor clobber isLoading)
- [x] [Review][Patch] Background refetch failure is invisible: `error` renders only when `!hasLoaded`, so a refetch failure after a successful load shows silently stale data with no inline notice [fenzo-app/src/features/attendance/offices/OfficesScreen.tsx:75-96] — **fixed 2026-09-27** (inline notice above the list when error && hasLoaded)
- [x] [Review][Patch] Orphaned search needle: the filter input unmounts below the 8-row threshold but `needle` keeps filtering — if active rows drop below the threshold while a query is set, rows stay filtered with no visible way to clear [fenzo-app/src/features/attendance/offices/OfficesScreen.tsx:48-52] — **fixed 2026-09-27** (needle applies only while the search box is on screen)
- [x] [Review][Patch] Uppercase label strings violate the mandatory sentence-case copy rule: "OFFICE NAME", "START TIME", "END TIME", "LATE CUT-OFF (minutes after start)", "FULL-DAY HOURS", "HALF-DAY HOURS" (typography.label has no textTransform — they render literal uppercase) [fenzo-app/src/features/attendance/offices/OfficeFormScreen.tsx:216, OfficeRuleFields.tsx:37-85] — **fixed 2026-09-27** (all six labels sentence case)
- [x] [Review][Patch] Radius preset chips are 32px tall — below the ≥44px touch-target floor (stepper buttons are correctly 44×44) [fenzo-app/src/features/attendance/offices/RadiusStepper.tsx:121] — **fixed 2026-09-27** (44px, matching the stepper buttons)
- [x] [Review][Patch] Badge token misuse: "GPS Verified" and "Active" reuse `status="progress"` (the job-state "In Progress" variant) for unrelated semantics — fixed DS vocabulary bypassed instead of extended [fenzo-app/src/features/attendance/offices/OfficeFormScreen.tsx:207, OfficeLocationCard.tsx:29] — **fixed 2026-09-27** (status="done" — the DS positive green; the job-state progress token untouched)
- [x] [Review][Patch] Archive confirm dialog uses the unsaved form name (renaming without saving shows the new name while archiving the old one); also a 409 with empty/missing `blockers` renders "0 employees are still assigned here" [fenzo-app/src/features/attendance/offices/OfficeFormScreen.tsx:133-166] — **fixed 2026-09-27** (detail name preferred; blockers-empty fallback copy)
- [x] [Review][Patch] Hard-coded radii bypass tokens: `borderRadius: 999` (OfficeRuleFields info chip) vs `radius.pill` used elsewhere in the same feature; `borderTopLeftRadius: 16` in PickerBottomCard [fenzo-app/src/features/attendance/offices/OfficeRuleFields.tsx:121, PickerBottomCard.tsx:66] — **fixed 2026-09-27** (radius.pill chip; radius.xl sheet card)
- [x] [Review][Patch] Accessibility gaps: archived OfficeListRow disabled without `accessibilityState={{ disabled: true }}`; RadiusStepper −/+ silently no-op at 50/1000 without disabled state [fenzo-app/src/features/attendance/offices/OfficeListRow.tsx, RadiusStepper.tsx] — **fixed 2026-09-27** (accessibilityState on the archived row; disabled+state on the stepper at 50/1000)
- [x] [Review][Patch] Hygiene: 24 changed files lack trailing newlines; duplicate `react-native` import in PickerBottomCard; inline `import('../../../navigation/types')` type in OfficesScreen where every sibling imports `RootStackParamList` at the top [multiple files] — **fixed 2026-09-27** (newlines, merged duplicate import, top-level RootStackParamList import)

**Deferred**
- [x] [Review][Defer] Reverse geocode fires on mount for the default/edit pin — one (billable) Geocoding call before any user intent — deferred, product/budget call (spec pins settle-only reverse)
- [x] [Review][Defer] Confirm always enabled in add mode — the untouched Bengaluru default can be committed without placing a pin — deferred, product UX call
- [x] [Review][Defer] Map-style hex values hand-synced to palette tokens with no token-pinning test (colors.test.ts convention not extended) — deferred

Dismissed as noise: technician-taps-Offices-row (MoreScreen is not mounted for technicians — the row is unreachable outside the owner stack); formFromDetail crash on malformed rules (server-guaranteed detail shape, typed contract); overnight-shift rejection (mirrors the 15-3 server end-after-start constraint, sibling-consistent); edit pre-fill from a pending future-dated rule (documented in the model's own doc comment).

### Review Findings — group 3/3: fenzo-app tests + spike deletion (BMAD 4-layer, 2026-09-27)

**Decision-needed**
- [x] [Review][Decision] Frozen task "hook/screen tests mirroring addressPicker's patterns" narrowed — **resolved 2026-09-27: option (a)** — targeted contract tests added now (pickedLocation handoff, placesService.reverse, More row, manual-entry hiding, offices error contracts); full screen-level suites deferred (deferred-work.md) to hook/model/service tests only — OfficesScreen/OfficeFormScreen/OfficeMapPickerScreen have no tests (save flows, 409 handling, archive flow, the pickedLocation popTo handoff all unverified; the narrowing is recorded in Verification but the frozen wording is not amended). [fenzo-app tests]

**Patch**
- [x] [Review][Patch] The pickedLocation handoff (picker popTo → form applies params + clears location error) has zero tests — the story's core flow can regress with the suite green; repo convention tests exactly this pattern in the SelectScreens [fenzo-app navigation between OfficeMapPickerScreen.tsx:191-201 and OfficeFormScreen.tsx:98-108] — **fixed 2026-09-27** (OfficeFormScreen.pickedLocation.test.tsx — pin applied + GPS chip, presence-based due to the React 19 duplicate-fiber quirk)
- [x] [Review][Patch] `placesService.reverse` has no tests — URL, lat/lng params, envelope unwrap and signal forwarding unpinned (autosuggest/resolve both have describes) [fenzo-app/src/services/resources/places.test.ts] — **fixed 2026-09-27** (URL/params, signal pass-through, no-signal case)
- [x] [Review][Patch] MoreScreen navigation-wiring test omits the new Offices row — the feature's only entry point can silently disappear or dead-end [fenzo-app/src/features/more/MoreScreen.test.tsx:145-164] — **fixed 2026-09-27** (Offices row → AttendanceOffices)
- [x] [Review][Patch] AddressPickerSheet is never tested without `onManualAddress` — the office picker's manual-entry hiding (this story's change) is unpinned; a revert shows a CTA whose submit path throws [fenzo-app/src/features/addressPicker/AddressPickerSheet.test.tsx] — **fixed 2026-09-27** (no-results CTA absent without onManualAddress; positive control kept)
- [x] [Review][Patch] No test exercises the offices service error contracts the file documents (409 name-taken, 409 archive-blocked with `details.blockers`) — an apiClient rejection propagating unchanged as ApiError is entirely uncovered [fenzo-app/src/services/resources/offices.test.ts] — **fixed 2026-09-27** (409 name-taken and 409 archive-blocked with details.blockers propagate unchanged, pinned by rejects.toBe)
- [x] [Review][Patch] Route registrations observed only at runtime — no test renders a navigator or asserts the Offices row's navigate target; a dropped Screen entry compiles and crashes at runtime [fenzo-app/src/navigation/RootNavigator.tsx:88-103] — **fixed 2026-09-27** (the MoreScreen row test pins the navigate target; full navigator smoke test stays deferred)
- [x] [Review][Patch] useLocateMe's timeout classification is pinned only against a mock literal the test supplies — nothing ties the real `geolocation.ts` rejection message ("Location request timed out") to the `'timed out'` substring the hook matches [fenzo-app/src/features/attendance/offices/useLocateMe.ts:70] — **resolved 2026-09-27** — the deferred geolocation contract suite owns this tie; the same session fixed the compat error classification on its numeric code (see group 2)
- [x] [Review][Patch] officeFormModel test gaps: empty `lateCutoffMinutes` (the Number('') bug), radius bounds, name exactly 80 chars, equal start/end times, non-numeric hours strings, unsorted rules history, buildUpdatePatch name trimming, `hasErrors` true branch, first-fetch rejection in useOffices, `refresh()` bypassing the throttle [fenzo-app test files] — **fixed 2026-09-27** (empty/whitespace cut-off, radius bounds, name=80, non-numeric hours, unsorted-history pin, PATCH name trim, hasErrors true branch, first-fetch rejection; the throttle-bypass item is moot — throttle removed by decision 1b, replaced by always-refetch + latest-wins tests)
- [x] [Review][Patch] offices.test.ts gaps: `encodeURIComponent` checked only on get (not update/archive/archivePreview); null-body fallback untested; the `archive` "unwraps the 204 envelope" assertion is vacuous (returns void unconditionally) [fenzo-app/src/services/resources/offices.test.ts] — **fixed 2026-09-27** (encodeURIComponent on update/archive/archivePreview, null-body fallback, archive now pins that the envelope is IGNORED)
- [x] [Review][Patch] Navigation types: the OfficeMapPicker comment claims radiusM is "required" but the params object is `| undefined` — the type does not enforce its own documented invariant [fenzo-app/src/navigation/types.ts] — **fixed 2026-09-27** (comment matches the optional params object)
- [x] [Review][Patch] Hygiene: all four new test files lack trailing newlines; `'./../api/apiClient'` mock specifier reads as a typo ('../api/apiClient'); useOffices.test imports React for JSX while useLocateMe.test relies on the automatic runtime — same folder, two conventions [fenzo-app test files] — **fixed 2026-09-27** ('../api/apiClient' specifier in both suites, trailing newlines, React import dropped from useOffices.test)
- [x] [Review][Patch] Stale spike reference in jest.setup.js comment ("the 15-1 spike already had this failure mode via MapSpikeScreen") — the spike screen no longer exists [fenzo-app/jest.setup.js:83] — **fixed 2026-09-27**

**Deferred**
- [x] [Review][Defer] geolocation.ts has no contract suite (timeout/permission error classification that useLocateMe's copy depends on) — deferred, separate small suite
- [x] [Review][Defer] Unmount-safety tests for useLocateMe (slow fix resolving after unmount) — deferred
- [x] [Review][Defer] Full-screen smoke test rendering RootNavigator's registrations — deferred (the MoreScreen row test covers the navigate target)
- [x] [Review][Defer] useOffices throttle near-boundary tests (29_999 vs 30_000ms) and retry-after-error assertions — deferred

Dismissed as noise: NaN coordinates from a fix (geolocation.ts validates undefined/missing; native never returns NaN); flush() fixed-tick helper (fragility note only, works today); MapSpike deletion completeness (verified complete by the auditor — zero references remain, initialRouteName restored, TodayScreen button and Map import removed); test counts and suite state (verified: 51 new tests, 130 suites / 1266 green).

Patch handling completed 2026-09-27 (fenzo-app, all group-2/group-3 patches applied): `bun run test` green — 131 suites / 1288 tests (was 130/1266 pre-patch; +1 suite pickedLocation handoff, +22 tests), `tsc --noEmit` clean. One runtime fix folded in from a user-reported device log: geolocation.ts now classifies the nitro compat error object on its numeric code.
