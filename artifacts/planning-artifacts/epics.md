---
stepsCompleted: [1, 2, 3]
inputDocuments:
  - artifacts/planning-artifacts/architecture/architecture-address-autosuggest-2026-09-05/ARCHITECTURE-SPINE.md
  - artifacts/planning-artifacts/architecture/architecture-address-autosuggest-2026-09-05/.memlog.md
  - artifacts/planning-artifacts/research/technical-google-places-api-address-autocomplete-c-2026-09-05/research.md
  - artifacts/planning-artifacts/ux-designs/ux-Fenzo-2026-09-05-address-autosuggest/DESIGN.md
  - artifacts/planning-artifacts/ux-designs/ux-Fenzo-2026-09-05-address-autosuggest/EXPERIENCE.md
  - "no PRD.md exists for this feature; FRs/NFRs derived from the user's original feature request (conversation, 2026-09-05) with user's explicit sign-off to proceed without a separate PRD"
---

# Fenzo - Epic Breakdown

## Overview

This document provides the epic and story breakdown for the **Address Autosuggest for Add Customer** feature — Google Places API (New) integration spanning `fenzo-app` (frontend) and `fenzit-be` (backend), decomposing the finalized architecture spine (AD-1 through AD-10) into implementable stories. No formal PRD exists for this feature-sized piece of work; requirements below are derived from the original feature request and the architecture spine.

## Requirements Inventory

### Functional Requirements

FR1: When adding a customer, the user can tap the "Address / map location" field in the Add Customer bottomsheet to open a dedicated full-screen address search.
FR2: On the address search screen, typing in the search input triggers debounced address suggestions fetched from the backend (which proxies Google Places) — no results fetch fires before a minimum character count is reached.
FR3: Search results display as a selectable list of matching addresses (place name / description text).
FR4: Selecting an address from the list closes the search screen and returns to the Add Customer bottomsheet with the selected address (and City/Area) populated.
FR5: After a selection, the user can still manually edit the address text (and City/Area) before submitting — the picker never locks the field.
FR6: Submitting "Add customer" sends the resolved address data (formatted address, pincode, latitude, longitude, place id) to the backend alongside the existing customer fields.
FR7: The backend persists the structured address data (formatted address, pincode, latitude, longitude, place id) against the customer record, in addition to the existing free-text address/city/area handling (unchanged).
FR8: The backend exposes an autosuggest endpoint that proxies Google Places Autocomplete (New), region-restricted to India, requiring a session token.
FR9: The backend exposes a resolve endpoint that proxies Google Place Details (New) to return place name, formatted address, pincode, and lat/long for a selected suggestion, using the same session token to close the billing session.
FR10 *(gap identified during this breakdown, then scoped concretely against real code — not covered by any existing AD)*: On the technician job-detail screen (`TechJobDetailContent.tsx`), tapping the existing "Open in maps" address row must navigate using the customer's saved coordinates when available, not just a text-search guess.
  - **This affordance already exists today** — `openMaps(address, city)` in `src/utils/linking.ts` builds a `maps:0,0?q=<address, city>` / `geo:0,0?q=<address, city>` text-search deep link. It works, but is only as accurate as the free-text address string.
  - **Scoped change:** `openMaps` gains optional `latitude`/`longitude` params; when present, build a coordinate-based deep link (precise) instead of the text-query fallback (kept for customers with no saved coordinates — backward compatible, never a regression).
  - **Data plumbing needed (not yet present):** the technician job-detail API response's embedded customer object doesn't carry coordinates today. `fenzit-be`'s `jobs.service.ts` `CustomerProfile` type/query (~line 75-76, assembled ~line 837-838) has `address`/`city` only — needs `latitude`/`longitude` added to its select + response mapping. `fenzo-app`'s `src/services/resources/jobs.ts` customer type (~line 218-219) needs the matching fields. `TechJobDetailContent.tsx` then passes `detail.customer.latitude`/`longitude` into the updated `openMaps` call.

### NonFunctional Requirements

NFR1 (Cost control): Every autosuggest/resolve call pair must share one client-generated session token (AD-3); the resolve call's field mask must never request a Pro/Enterprise-tier field (AD-5); both endpoints must be independently rate-limited server-side (AD-6); the frontend must debounce (~300ms) and enforce a minimum query length (~3 chars) before calling autosuggest at all (AD-6).
NFR2 (Scope restriction): Address search results must be restricted to India (`includedRegionCodes: ['IN']`) (AD-5).
NFR3 (Security): The Google Places API key must be IP-restricted, server-side only, and must never reach the mobile client (AD-10).
NFR4 (Backward compatibility): A customer must still be creatable with only manual free-text address/city/area and none of the new structured fields — the Places flow is additive, never mandatory (AD-7).
NFR5 (Resilience): A Places/Google outage or own-rate-limit trip must never block customer creation — the free-text address fields remain the standing fallback at all times (AD-9).
NFR6 (Authorization): Both new Places endpoints require the same auth as customer creation — authenticated JWT + Owner role only (AD-4).

### Additional Requirements (from Architecture Spine)

- New `fenzit-be` feature module `PlacesModule` (`src/places/`), DB-less (depends only on the global `CacheModule`, no `SupabaseModule` dependency) (AD-1).
- Abstract `PlacesProvider` class + `GooglePlacesProvider` (Bun native `fetch`, `AbortSignal.timeout(4000)`) + `MockPlacesProvider`, mirroring the existing `OtpDeliveryProvider`/`OtpSessionStore` DI-swap convention; `resolve()` returns the normalized `ResolvedPlace` shape, never Google's raw JSON (AD-2).
- Two endpoints: `GET /places/autosuggest?q=&sessionToken=` and `GET /places/resolve/:placeId?sessionToken=`, both behind `JwtAuthGuard` + `@Roles(Role.OWNER)` (AD-4).
- `location` absent on an otherwise-valid `placeId` is treated as a provider failure (`502 PLACES_UPSTREAM_ERROR`), never a null-coordinate success (AD-4). `city`/`pincode` are always `string | null`, never omitted or `''` (AD-4/AD-5).
- Per-endpoint rate-limit cache keys (`places:rate:{tenantId}:autosuggest`, `places:rate:{tenantId}:resolve`) reusing the existing `in-memory-otp-session.store.ts` increment-counter pattern; short-TTL result caching (reuse global 300s `CacheModule` TTL) keyed on query text/region (`autosuggest`) and `placeId` (`resolve`) (AD-6).
- Customer schema migration (Supabase MCP, additive SQL): `formatted_address TEXT`, `pincode TEXT`, `latitude DOUBLE PRECISION`, `longitude DOUBLE PRECISION`, `place_id TEXT` — all nullable. **No `area` column** — the existing `CustomersScreen.tsx`/`NewJobScreen.tsx` convention of concatenating `area` into `address` before `POST /customers` is deliberate and stays unchanged (AD-7).
- `CreateCustomerDto` (BE) and `CreateCustomerRequest` (FE) both gain 5 new optional fields: `formattedAddress`, `pincode`, `latitude`, `longitude`, `placeId` (AD-4/AD-7).
- `GOOGLE_PLACES_API_KEY` added to the existing Joi env schema in `app.module.ts`, consumed via `ConfigService.getOrThrow` — IP-restricted server key; **user supplies the actual key value at implementation time, not yet provided** (AD-10).
- New `fenzo-app` feature folder `src/features/addressPicker/`: `AddressPickerScreen.tsx`, `useAddressAutosuggest.ts` (debounce + session-token lifecycle), new generic `src/hooks/useDebounce.ts` (none exists today), `src/services/resources/places.ts`.
- Navigation/data-return: `AddressPickerScreen` → `navigation.navigate('Customers' | 'NewJob', { pendingAddress })` (fully serializable) → hosting screen reads `route.params.pendingAddress` in `useEffect`, feeds `AddCustomerSheet`, clears via `navigation.setParams({ pendingAddress: undefined })` — mirrors the existing `JobsScreen.tsx:161` precedent; explicitly **not** a callback-in-params design (AD-8).
- `AddCustomerSheet`'s local state extends with optional `formattedAddress`/`pincode`/`latitude`/`longitude`/`placeId`; the free-text `address` input is never made read-only (AD-8/AD-9).
- No starter template — both repos are existing brownfield codebases; this feature ratifies their existing conventions rather than introducing new ones.
- Evaluated and explicitly rejected: Address Validation API as an alternative session terminator (net cost increase for this app's expected usage; user confirmed missing-flat-number data quality isn't currently a pain point) — no action item, recorded for traceability only.

### UX Design Requirements

A full UX design contract now exists: `ux-designs/ux-Fenzo-2026-09-05-address-autosuggest/DESIGN.md` + `EXPERIENCE.md`. It reuses existing components verbatim (`EmptyState`, `InlineError`, `IconButton`, `Input`, `TechnicianPicker`'s row-card style) — no new visual components introduced.

UX-DR1: `AddressPickerScreen` header reuses the existing screen-header pattern (`SafeAreaView edges={['top']}` + `StatusBar dark-content` + `IconButton variant="ghost"` wrapping `ChevronLeft`, copied from `CustomerDetailScreen.tsx`/`TechJobDetailScreen.tsx`), with the title slot replaced by an auto-focused search `Input`.
UX-DR2: Suggestion rows reuse `TechnicianPicker`'s existing "rows" variant card style verbatim (bordered card, `MapPin` leading icon in place of `Avatar`, no trailing check — a spinner in that slot while resolving instead).
UX-DR3: Eight defined screen states in strict precedence — Idle, Below-threshold (1–2 chars, "Keep typing to search"), Loading (previous results stay visible, dimmed, during refetch), Results, No-results (`EmptyState`, CTA "Enter manually"), Error/nothing-loaded (`EmptyState`, CTA "Retry"), Resolving (whole screen non-interactive), Resolve-failed (`InlineError` over an intact list).
UX-DR4: Selecting a suggestion triggers the resolve call *before* navigating back — never an optimistic instant pop; the tapped row is disabled with a spinner until resolve settles, one row at a time.
UX-DR5: No toast/snackbar acknowledgment on return to `AddCustomerSheet` — a brief (~200ms) soft primary-tinted border pulse on the address `Input` is the sole "something changed" signal, matching the design system's motion durations.
UX-DR6: FR10's technician maps row gets **no visual change** (no "precise vs. approximate" badge) — only the underlying deep link improves; adding a distinction the technician can't act on would be visual noise.
UX-DR7 (deferred, not in this feature): "Use my current location" quick-add, and highlighting the matched query substring in suggestion text — both flagged as open questions in `EXPERIENCE.md`, not designed or scoped here.

### FR Coverage Map

| Requirement | Covered by (AD / component) |
| --- | --- |
| FR1 | AD-8 (`AddressPickerScreen` navigation entry point) |
| FR2 | AD-6 (FE debounce + min-chars), AD-4 (`/places/autosuggest`) |
| FR3 | AD-4 (`suggestions[]` response shape) |
| FR4 | AD-8 (`pendingAddress` return pattern) |
| FR5 | AD-8, AD-9 (address field always editable) |
| FR6 | AD-4 (`POST /customers` amendment) |
| FR7 | AD-7 (schema migration) |
| FR8 | AD-2, AD-4, AD-5 (`/places/autosuggest`) |
| FR9 | AD-2, AD-4, AD-5 (`/places/resolve/:placeId`) |
| FR10 | **Not covered by any AD** — scoped directly against `linking.ts`/`TechJobDetailContent.tsx` (FE) and `jobs.service.ts` (BE); see Epic 3 |
| NFR1–NFR6 | AD-3, AD-4, AD-5, AD-6, AD-7, AD-9, AD-10 respectively |

## Epic List

### Epic 1: Verified Address Capture for New Customers
When adding a customer, owners can search for a real address (restricted to India), pick it from suggestions, and have exact coordinates saved — while always able to type the address by hand if search doesn't find it. Spans both repos (`fenzit-be` proxy + schema, `fenzo-app` picker UI) as one epic — splitting by repo would be a technical-layer split with no independent user value on either side. Stories within this epic are sequenced backend-first, per this meta-repo's cross-repo deploy rule (additive backend change ships before the frontend that depends on it).
**FRs covered:** FR1, FR2, FR3, FR4, FR5, FR6, FR7, FR8, FR9
**NFRs covered:** NFR1, NFR2, NFR3, NFR4, NFR5, NFR6

### Epic 2: Precise Navigation to Saved Addresses
When a customer's address has saved coordinates, technicians tapping "open in maps" on a job get routed to the exact location instead of a text-search guess — with zero behavior change for existing customers who don't have coordinates yet (safe, backward-compatible fallback). Builds on Epic 1's captured data for its full value, but ships safely on its own (falls back to today's exact behavior with no coordinates present) — a separate user (technician, not owner) getting a separate, independently shippable outcome.
**FRs covered:** FR10

### FR Coverage Map

FR1: Epic 1 - Address search entry point from the Add Customer bottomsheet
FR2: Epic 1 - Debounced autosuggest fetch (min-chars gate)
FR3: Epic 1 - Suggestion list rendering
FR4: Epic 1 - Selection returns address/City/Area to the bottomsheet
FR5: Epic 1 - Address remains manually editable after selection
FR6: Epic 1 - Resolved address data submitted with customer creation
FR7: Epic 1 - Backend persists structured address data
FR8: Epic 1 - Backend autosuggest endpoint (Places Autocomplete New proxy)
FR9: Epic 1 - Backend resolve endpoint (Place Details New proxy)
FR10: Epic 2 - Technician maps affordance uses saved coordinates when available
NFR1-NFR6: Epic 1 - Cost control, region restriction, security, backward compatibility, resilience, authorization constraints on Epic 1's endpoints/data

## Epic 1: Verified Address Capture for New Customers

Owners can search for a real address (India-restricted) when adding a customer, pick it, and have exact coordinates saved — free-text entry always remains available as a fallback.
**FRs:** FR1–FR9 · **NFRs:** NFR1–NFR6 · **UX-DRs:** UX-DR1–UX-DR5
Stories sequenced backend-first (`fenzit-be` → `fenzo-app`), per this meta-repo's cross-repo deploy ordering rule.

### Story 1.1: Backend — Address autosuggest endpoint

As a mobile client (Owner-authenticated),
I want a backend endpoint that proxies Google Places Autocomplete (New),
So that I can get address suggestions without the Google API key ever reaching the device.

**Acceptance Criteria:**

**Given** a valid JWT with Owner role and a query string ≥1 character
**When** `GET /places/autosuggest?q=&sessionToken=` is called
**Then** the request is forwarded to Google Places Autocomplete (New) with `includedRegionCodes: ['IN']` and the given session token, and the response is normalized to `{suggestions: [{placeId, text}]}`
**And** a request without a valid JWT/Owner role is rejected (401/403), matching existing `JwtAuthGuard`/`@Roles(Role.OWNER)` behavior
**And** the endpoint is rate-limited per-tenant on a dedicated cache key (`places:rate:{tenantId}:autosuggest`), returning `429 RATE_LIMITED` when tripped
**And** an empty Google result returns `200 {suggestions: []}`, never an error
**And** `GOOGLE_PLACES_API_KEY` is read via `ConfigService.getOrThrow`, added to the existing Joi env schema, and never appears in any response body or log line
**And** `MockPlacesProvider` exists and is swappable via the same DI convention as `OtpDeliveryProvider`, so the endpoint is testable without a live Google key

### Story 1.2: Backend — Address resolve endpoint

As a mobile client (Owner-authenticated),
I want a backend endpoint that proxies Google Place Details (New) for a chosen suggestion,
So that I get the formatted address, pincode, and coordinates while keeping the session-token billing scoped correctly.

**Acceptance Criteria:**

**Given** a valid `placeId` and the same `sessionToken` used for the preceding autosuggest calls
**When** `GET /places/resolve/:placeId?sessionToken=` is called
**Then** the request uses field mask `id,formattedAddress,location,addressComponents,postalAddress` (Essentials tier only) and returns `ResolvedPlace {placeId, formattedAddress, city: string|null, pincode: string|null, latitude: number, longitude: number}`
**And** `pincode` is read from `postalAddress.postalCode`; `city` is read from the `addressComponents` entry typed `locality`
**And** if Google returns a valid place with `location` absent, the endpoint returns `502 PLACES_UPSTREAM_ERROR` — never a null-coordinate success
**And** the endpoint is rate-limited independently from autosuggest (`places:rate:{tenantId}:resolve`)
**And** it requires the same JWT + Owner-role auth as Story 1.1

### Story 1.3: Backend — Persist structured address on customer creation

As an Owner,
I want the structured address I picked to be saved against the customer record,
So that the technician and future lookups can use exact coordinates, not just free text.

**Acceptance Criteria:**

**Given** the customers table migration has been applied (additive, nullable: `formatted_address TEXT`, `pincode TEXT`, `latitude DOUBLE PRECISION`, `longitude DOUBLE PRECISION`, `place_id TEXT`, via Supabase MCP)
**When** `POST /customers` is called with `CreateCustomerDto` including any of the 5 new optional fields
**Then** the customer record is created with those fields persisted alongside the existing `name`/`address`/`city` fields
**And** `POST /customers` called with none of the 5 new fields (today's existing request shape) still succeeds exactly as before — no new field is required
**And** no `area` column is added; the existing convention of concatenating `area` into `address` client-side stays untouched

### Story 1.4: Frontend — Address search screen

As an Owner,
I want a full-screen address search that shows live suggestions as I type,
So that I can quickly find and select a real address instead of typing one from scratch.

**Acceptance Criteria:**

**Given** the Owner is on the Add Customer bottomsheet (`AddCustomerSheet`)
**When** they tap the "Address / map location" field
**Then** `AddressPickerScreen` opens as a pushed native-stack route (per AD-8) with the search `Input` auto-focused and the keyboard already up (FR1)

**Given** the Owner is on `AddressPickerScreen` with the keyboard auto-focused
**When** they type fewer than 3 characters
**Then** no network call fires and a "Keep typing to search" hint shows (UX-DR3 below-threshold state)
**When** they type ≥3 characters and pause for ~300ms (debounce, via new `useDebounce.ts`)
**Then** `useAddressAutosuggest.ts` calls `/places/autosuggest` with a client-generated session token (UUID v4, reused for the resolve call) and renders results as `TechnicianPicker`-style rows (UX-DR2)
**And** a stale response (superseded by further typing) is discarded, never rendered
**And** an empty result set shows `EmptyState` ("No addresses found for '{query}'.", CTA "Enter address manually")
**And** a network/provider failure with nothing loaded shows `EmptyState` ("Couldn't load suggestions. Check your connection.", CTA "Retry")
**And** tapping a row calls `/places/resolve/:placeId` with the same session token, disabling that row (spinner) until it settles — a resolve failure shows `InlineError` below the still-intact list, never clearing results

### Story 1.5: Frontend — Return selection to Add Customer bottomsheet

As an Owner,
I want my picked address to land back in the Add Customer form, still editable,
So that I can add a landmark or correct a detail before saving, and I'm never blocked if I skip search entirely.

**Acceptance Criteria:**

**Given** a resolve call in `AddressPickerScreen` succeeds
**When** the screen returns to `CustomersScreen`/`NewJobScreen`
**Then** it does so via `navigation.navigate(..., { pendingAddress: ResolvedPlace })`, which the hosting screen reads in `useEffect`, feeds into `AddCustomerSheet`, and clears via `navigation.setParams({ pendingAddress: undefined })`
**And** the bottomsheet's address `Input`, plus City/Area, populate from `pendingAddress`, with a brief (~200ms) soft border pulse as the sole change signal (no toast)
**And** the Owner can still hand-edit the address text (and City/Area) after population — no field is locked
**And** submitting "Add customer" sends `formattedAddress`, `pincode`, `latitude`, `longitude`, `placeId` alongside the existing fields when present
**And** an Owner who never opens the address picker (back gesture/"Enter manually", or skips the field) can still successfully add a customer with only the existing free-text fields — the Places flow is never mandatory (NFR4/NFR5)

## Epic 2: Precise Navigation to Saved Addresses

When a customer's address has saved coordinates, technicians get exact-location maps navigation instead of a text-search guess — zero behavior change for older customers without coordinates.
**FRs:** FR10 · **UX-DRs:** UX-DR6
Sequenced backend-first, same cross-repo rule as Epic 1.

### Story 2.1: Backend — Expose customer coordinates in job detail response

As a mobile client (technician-facing),
I want the job detail API to include the customer's saved coordinates when present,
So that the app can build a precise maps link instead of guessing from address text.

**Acceptance Criteria:**

**Given** a job whose customer has `latitude`/`longitude` saved (from Epic 1's Story 1.3 data)
**When** the technician's job-detail endpoint is called
**Then** `jobs.service.ts`'s `CustomerProfile` type/query/mapping (currently `address`/`city` only, ~lines 61-76 and ~837-838) includes `latitude`/`longitude` in its select and response mapping
**And** a customer with no saved coordinates (nulls) returns the field as `null`/absent, never a fabricated value, and the rest of the response is unchanged
**And** no existing consumer of this endpoint's response breaks — this is a strictly additive field

### Story 2.2: Frontend — Precise maps navigation from job detail

As a technician,
I want tapping "open in maps" to route me to the exact saved location when available,
So that I get accurate turn-by-turn directions instead of a text-match guess.

**Acceptance Criteria:**

**Given** `TechJobDetailContent.tsx`'s existing address row (MapPin + address text + Navigation icon)
**When** the job's customer has `latitude`/`longitude` (from Story 2.1)
**Then** `openMaps` (in `src/utils/linking.ts`) is called with the coordinates and builds a coordinate-based deep link (`maps:{lat},{lng}?q={lat},{lng}` / `geo:{lat},{lng}?q={lat},{lng}`) instead of the text-query fallback
**And** when coordinates are absent, `openMaps` falls back to today's exact `maps:0,0?q=<address, city>` / `geo:0,0?q=<address, city>` text-search behavior — unchanged
**And** the row's visual appearance is identical in both cases — no "precise vs. approximate" badge (UX-DR6); only the underlying deep link differs
**And** `src/services/resources/jobs.ts`'s customer type (~lines 218-219) is updated to carry the new optional `latitude`/`longitude` fields matching Story 2.1's response shape

## Epic 3: Notify Owner When Technician Changes Job Status

When a technician advances a job's workflow (on_my_way → … → completed), the owner currently learns about it only by pulling to refresh. This epic adds live notification: the change is written as a per-recipient `notifications` row inside the existing RPC transaction, broadcast to the owner's app via Supabase Realtime (Broadcast from Database — the 2026-recommended pattern; Postgres Changes is explicitly discouraged for new apps due to single-threaded, per-subscriber RLS authorization), and the owner app force-refetches jobs on the event. No push notifications, no Redis — Phase 1 of the architecture discussion (2026-09-08, conversation-driven; no PRD; REST read endpoints for the bell/list page were added to scope 2026-09-09 as Story 3.2).

Requirements & constraints (conversation-derived, 2026-09-09; mixed functional requirements and constraints — the NFR-x labels are historical):
- NFR-A: On every successful technician workflow advance, exactly one `notifications` row is written for the tenant owner, atomically with the job UPDATE (same RPC transaction).
- NFR-B: The owner app receives the event live while foregrounded via a private Realtime channel authorized by RLS on `realtime.messages` keyed on `auth.jwt() ->> 'sub'` (recipient-only).
- NFR-C: Delivery is treated as a refetch hint, never a source of truth — existing focus-refetch (15s TTL) and pull-to-refresh remain the correctness net (Realtime is at-most-once).
- NFR-D: The anon/publishable key ships in the app (by design, not a secret); the `service_role` key and JWT secret stay server-side.
- NFR-E: Notifications are pruned (pg_cron, third job) so the table stays small.
- Out of scope: notifications for the owner's own cancel/edit path (`rpc_update_job_with_log`) — technician workflow advances only (recorded in Story 3.1's Never; a separate story if ever wanted).

- NFR-F: The owner's Jobs screen gets a bell icon opening a notifications list page (paginated, unread badge); tapping a notification marks it read and deep-links to that job's `JobDetail` screen.
- NFR-G (push-readiness): every piece ships so Phase 2 push (FCM/APNs) is additive-only — the `notifications` table doubles as the push outbox (`event_type` + self-sufficient `payload` + `pushed_at` delivery marker, written atomically from day 1); FE event handling is a single source-agnostic `handleJobStatusEvent(payload)` the socket calls today and the FCM handler calls tomorrow; the tap deep-link (`JobDetail`, `{ jobId }`) is the same one a push tap uses on cold start. Phase 2 adds a `device_tokens` table + registration endpoint, an FCM worker beside the broadcast, and nothing else changes.

Sequenced backend-first (cross-repo rule: additive BE changes merge/deploys first, then FE consumes them). Stories:
1. **3.1 (BE, pure SQL):** notifications table + in-RPC insert + Realtime broadcast trigger + pg_cron pruning.
2. **3.2 (BE):** REST endpoints — `GET /notifications` (paginated), `GET /notifications/unread-count`, `POST /notifications/mark-read`, `POST /notifications/mark-all-read`.
3. **3.3 (FE):** live updates — supabase-js client, foreground-only private-channel subscription on the owner's topic, force-refetch + banner on event.
4. **3.4 (FE):** bell icon + unread badge on the Jobs screen header, Notifications list screen, tap → mark-read → `JobDetail` deep link.

### Story 3.1: Backend — Notifications table + in-RPC insert + Realtime broadcast trigger

As the system,
I want every technician workflow advance to atomically write a notification row for the tenant owner and broadcast it to their Realtime topic,
So that the owner app can be notified live without any backend event-delivery module.

**Acceptance Criteria:**

**Given** a technician successfully advances a workflow step (RPC `advance_workflow_step`)
**When** the RPC's job UPDATE and activity_logs INSERT commit
**Then** exactly one `notifications` row for the tenant's owner (`tenants.owner_id`) is written in the same transaction, with `event_type` = the workflow step and a payload containing `job_number` and the technician's name
**And** a DB trigger on the notifications table calls `realtime.broadcast_changes('user:<owner_id>:notifications', ...)` so the event reaches a private Realtime channel
**And** the Realtime authorization policy on `realtime.messages` allows a JWT to receive only topics for its own `sub` (recipient-only), following the live project's `TO public` policy convention
**And** a subscriber holding only the anon key (no user JWT) receives nothing
**And** a pg_cron job prunes notifications older than 30 days

### Story 3.2: Backend — Notifications REST endpoints

As an Owner app,
I want REST endpoints to list notifications, get an unread count, and mark notifications read,
So that the bell icon and notifications page have data even when the app was offline when events fired.

**Acceptance Criteria:**

**Given** an authenticated owner JWT
**When** `GET /notifications` is called (with `limit`/`cursor` keyset pagination, house `cursor.util.ts` machinery)
**Then** it returns that user's notifications (newest first) with job number and step metadata resolved into the payload — tenant-scoped, RLS-equivalent filtering by `user_id = sub`
**When** `GET /notifications/unread-count` is called, then it returns the count of rows with `read_at IS NULL` for that user
**When** `POST /notifications/mark-read` is called with notification ids, or `POST /notifications/mark-all-read` with none, then the matching rows' `read_at` is set (idempotent)
**And** a technician JWT sees only their own (always-empty) set — the endpoints are recipient-scoped, not role-gated

### Story 3.3: Frontend — Owner live job-status updates via Supabase Realtime

As an Owner,
I want my app to react live when a technician changes a job's status,
So that I see updated job state without pulling to refresh.

**Acceptance Criteria:**

**Given** the owner app is foregrounded and a technician advances a workflow step on any of the owner's jobs
**When** the broadcast event arrives on the owner's private Realtime topic
**Then** the app force-refetches jobs (`loadJobs(..., { force: true })`) so the list reflects the new status within the same tick, and shows a brief banner naming the job and new step
**And** the subscription is foreground-only (torn down on background via `AppState`, resubscribed on foreground) and re-subscribes after a reconnect, with the existing focus-refresh remaining the correctness net
**And** the session's existing bearer JWT authorizes the channel via supabase-js's `accessToken` option — no Supabase auth, no stored Supabase session
**And** the subscription is cleaned up on global session reset (401 resetRegistry), and technicians get none of this (mounted only in the owner branch)

### Story 3.4: Frontend — Bell icon, notifications page, deep link to job

As an Owner,
I want a bell icon with an unread badge that opens a list of notifications, each tapping through to the job it's about,
So that I have a history of technician activity even for events that fired while my app was closed or offline.

**Acceptance Criteria:**

**Given** the owner's Jobs screen header
**When** the bell icon is rendered
**Then** it shows the unread count from `GET /notifications/unread-count` as a badge, refreshed on screen focus and after each live event from Story 3.3
**When** the bell is tapped
**Then** a Notifications screen opens: newest-first paginated list (cursor pagination, pull-to-refresh), each row showing the step, job number, technician name and relative time; unread rows visually distinguished
**When** a notification row is tapped
**Then** it is marked read (optimistically; badge updates), and the app navigates to `navigation.navigate('JobDetail', { jobId })` — the existing owner route — for the notification's job
**And** marking all read is available on the list screen, and technicians get no bell (owner-only surface)
