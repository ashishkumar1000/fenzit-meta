---
title: 'Frontend — Address search screen'
type: 'feature'
created: '2026-09-05'
status: 'done'
review_loop_iteration: 0
context: []
baseline_commit: 'a55c80d8e1d4b963a3af3550a8f94197719720e5'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** Owners have no way to search and verify an address; Stories 1.1–1.3 built the backend autosuggest/resolve/persist endpoints, but nothing in `fenzo-app` calls them yet.

**Approach:** Build a standalone, pushed `AddressPickerScreen` backed by a new `useAddressAutosuggest` hook and `placesService` resource. On resolve, it navigates back to whichever route pushed it, returning `{ pendingAddress: ResolvedPlace }` via params. Wiring it into `AddCustomerSheet` (the tap-to-open trigger and reading `pendingAddress` back) is Story 1.5, not this one.

## Boundaries & Constraints

**Always:**
- `AddressPicker` route registered in `RootNavigator.tsx`/`types.ts` (`headerShown: false`, pushed not modal), receiving `{ returnRouteName: keyof RootStackParamList }` in its own route params.
- New `src/services/resources/places.ts`: `placesService.autosuggest(query, sessionToken, signal)` → `GET /places/autosuggest`, `placesService.resolve(placeId, sessionToken, signal)` → `GET /places/resolve/:placeId`; mirror `customers.ts`'s plain-object/`apiClient` convention; errors surface as `ApiError`, never swallowed.
- New `src/hooks/useDebounce.ts` — hand-written debounce (no debounce library is installed; do not add one).
- `useAddressAutosuggest` generates one UUID v4 session token per screen mount, reused for every autosuggest call and the terminating resolve call; ~300ms debounce; minimum 3-char query gate; one `AbortController` per request so a stale response for a superseded query is discarded; error mapping follows `useCustomers.ts`'s `(error as ApiError)?.message` convention.
- Screen implements the 8 states from `epic-1-context.md` verbatim (Idle → Below-threshold → Loading → Results → No-results → Error → Resolving → Resolve-failed). Suggestion rows reuse `TechnicianPicker`'s row-card style verbatim (`MapPin` icon instead of avatar, spinner instead of check mark while resolving). No-results/Error use `EmptyState`; Resolve-failed uses `InlineError` over an intact list.
- On successful resolve, screen returns to `returnRouteName` passing `{ pendingAddress: ResolvedPlace }` in that route's params (`navigation.navigate({ name, params, merge: true })` or equivalent).
- Back gesture / header chevron / "Enter manually" CTA are plain no-op cancels (`navigation.goBack()`), no confirmation.
- Accessibility: live-region suggestion-count announcement on entering Results; `accessibilityLabel` is the full formatted address; 44px touch floor via existing DS tokens.

**Ask First:** None — `epic-1-context.md` already fixes the return-data mechanism and the interaction spec; this is a mechanical build of an already-approved design.

**Never:** Do not modify `AddCustomerSheet.tsx`, `CustomersScreen.tsx`, or `NewJobScreen.tsx` — reading `pendingAddress` back, clearing it, and the tap-to-open trigger are Story 1.5. Do not add a debounce or uuid package.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Below threshold | User types 1–2 chars | "Keep typing to search" shown, no network call | N/A |
| Debounced happy path | 3+ char query, provider returns suggestions | Results render ~300ms after last keystroke, count announced | N/A |
| Stale response discarded | Query changes while a request is in-flight | Only the latest query's response is ever rendered | N/A |
| No results | Query matches nothing | `EmptyState`, "Enter manually" CTA → `goBack()` | N/A |
| Autosuggest failure | `placesService.autosuggest` rejects | `EmptyState`, "Retry" CTA re-fires the last query | Message from `ApiError` |
| Resolve happy path | Suggestion tapped | Row disabled + spinner, then navigates back with `pendingAddress` | N/A |
| Resolve failure | `placesService.resolve` rejects | `InlineError` banner over an intact, still-interactive list | Message from `ApiError` |

</frozen-after-approval>

## Code Map

- `src/navigation/types.ts:36-46` -- add `AddressPicker: { returnRouteName: keyof RootStackParamList }`; add optional `pendingAddress?: ResolvedPlace` to the param entries Story 1.5 will consume
- `src/navigation/RootNavigator.tsx:21-50` -- register `AddressPicker` (`headerShown: false`)
- `src/services/resources/places.ts` (new) -- mirror `customers.ts:13,43-46`; `ResolvedPlace` type matches backend shape from `spec-1-2-backend-address-resolve-endpoint.md` line 24
- `src/services/resources/index.ts:8-11` -- `export { placesService } from './places';`
- `src/hooks/useDebounce.ts` (new, first hook in this dir) + `src/hooks/index.ts` export
- `src/features/addressPicker/useAddressAutosuggest.ts` (new) -- session token, debounce, gate, abort-sequencing, error mapping per `useCustomers.ts:107-120`
- `src/features/addressPicker/AddressPickerScreen.tsx` (new) -- header/back per `NewJobScreen.tsx:416-426`; rows per `TechnicianPicker.tsx:131-159,223-267`; `EmptyState` (`components/ui/EmptyState.tsx:13-25`); `InlineError` (`components/ui/InlineError.tsx:17-22`)
- `src/features/addressPicker/useAddressAutosuggest.test.ts`, `AddressPickerScreen.test.tsx` (new) -- mirror `AddCustomerSheet.test.tsx` conventions

## Tasks & Acceptance

**Execution:**
- [x] `src/navigation/types.ts` -- add `AddressPicker` + `pendingAddress` param types -- defines the return-data contract
- [x] `src/navigation/RootNavigator.tsx` -- register the route -- makes the screen reachable
- [x] `src/services/resources/places.ts` + `index.ts` -- autosuggest/resolve calls -- backend integration point
- [x] `src/hooks/useDebounce.ts` + `index.ts` -- generic debounce -- used by the autosuggest hook
- [x] `src/features/addressPicker/useAddressAutosuggest.ts` -- session token, debounced search, resolve -- core data logic
- [x] `src/features/addressPicker/AddressPickerScreen.tsx` -- 8-state UI, row reuse, return-with-params -- user-facing screen
- [x] Unit/component tests for both new files, covering the I/O matrix

**Acceptance Criteria:**
- Given `AddressPicker` is pushed with a `returnRouteName`, when a suggestion resolves, then navigation returns to that route with `{ pendingAddress: ResolvedPlace }` in its params
- Given one session token is generated per screen mount, then every autosuggest call and the terminating resolve call send that identical token
- Given a query is superseded before its response arrives, then only the latest query's results are ever rendered
- Given `AddCustomerSheet`, `CustomersScreen`, and `NewJobScreen` are unmodified by this story, then existing Add Customer behavior is unaffected

## Design Notes

No `uuid` package exists in this repo. Hand-roll a v4 generator, or use `crypto.randomUUID()` if verified available in the RN/Hermes runtime at implementation time — do not add a dependency for this alone.

## Verification

**Commands:**
- `bun run test -- addressPicker` -- expected: new hook/screen tests pass
- `bun run build` (or the repo's typecheck script) -- expected: no TypeScript errors

**Manual checks (if no CLI):**
- Screen is not yet reachable from the live UI (no trigger wired until Story 1.5) — verify via component tests only.

## Suggested Review Order

**Data layer: session, debounce, abort-safety**

- Entry point — session token, debounce, gate, and the 8-state `phase` derivation in one place.
  [`useAddressAutosuggest.ts:51`](../../workspace/core/frontend/fenzo-app/src/features/addressPicker/useAddressAutosuggest.ts#L51)

- Session token minted via lazy `useState` initializer, not `useMemo` — guarantees never-regenerated for the mount's lifetime (review-driven fix).
  [`useAddressAutosuggest.ts:52`](../../workspace/core/frontend/fenzo-app/src/features/addressPicker/useAddressAutosuggest.ts#L52)

- `fetchSuggestions`: per-request `AbortController`, sequence-number guard so only the latest query's response ever lands.
  [`useAddressAutosuggest.ts:90`](../../workspace/core/frontend/fenzo-app/src/features/addressPicker/useAddressAutosuggest.ts#L90)

- `resolvePlace`: re-entrancy guard against double-tap, own `AbortController` aborted on unmount, both added during code review.
  [`useAddressAutosuggest.ts:172`](../../workspace/core/frontend/fenzo-app/src/features/addressPicker/useAddressAutosuggest.ts#L172), [`useAddressAutosuggest.ts:88`](../../workspace/core/frontend/fenzo-app/src/features/addressPicker/useAddressAutosuggest.ts#L88)

**Screen: 8-state render, gesture safety, navigation return**

- Phase switch driving the 8 UI states; `SuggestionList` extracted below as the shared row renderer.
  [`AddressPickerScreen.tsx:105`](../../workspace/core/frontend/fenzo-app/src/features/addressPicker/AddressPickerScreen.tsx#L105), [`AddressPickerScreen.tsx:234`](../../workspace/core/frontend/fenzo-app/src/features/addressPicker/AddressPickerScreen.tsx#L234)

- `handleSelect`: resolves, then returns to the caller's route with `pendingAddress` — the epic's setParams-based return contract.
  [`AddressPickerScreen.tsx:88`](../../workspace/core/frontend/fenzo-app/src/features/addressPicker/AddressPickerScreen.tsx#L88)

- `AddressPicker.returnRouteName` narrowed to an explicit union rather than a structurally-derived type — TS's optional-property structural typing would otherwise silently accept any route (review-driven fix, with rationale in the comment).
  [`navigation/types.ts:76`](../../workspace/core/frontend/fenzo-app/src/navigation/types.ts#L76)

- Route registration on the root stack.
  [`RootNavigator.tsx:52`](../../workspace/core/frontend/fenzo-app/src/navigation/RootNavigator.tsx#L52)

**Backend integration: places service**

- `autosuggest`/`resolve` calls, with the `?? []` defensive fallback added during review.
  [`places.ts:29`](../../workspace/core/frontend/fenzo-app/src/services/resources/places.ts#L29), [`places.ts:44`](../../workspace/core/frontend/fenzo-app/src/services/resources/places.ts#L44), [`places.ts:71`](../../workspace/core/frontend/fenzo-app/src/services/resources/places.ts#L71)

**Generic utility**

- Hand-rolled debounce — first hook in `src/hooks/`, no dependency added.
  [`useDebounce.ts:17`](../../workspace/core/frontend/fenzo-app/src/hooks/useDebounce.ts#L17)

**Tests (peripherals)**

- Session-token reuse across autosuggest + terminating resolve, and stale-response discarding — the two trickiest data-layer invariants.
  [`useAddressAutosuggest.test.tsx:117`](../../workspace/core/frontend/fenzo-app/src/features/addressPicker/useAddressAutosuggest.test.tsx#L117), [`useAddressAutosuggest.test.tsx:147`](../../workspace/core/frontend/fenzo-app/src/features/addressPicker/useAddressAutosuggest.test.tsx#L147)

- Resolve happy/failure paths, including the review-added re-entrancy/abort behavior.
  [`useAddressAutosuggest.test.tsx:211`](../../workspace/core/frontend/fenzo-app/src/features/addressPicker/useAddressAutosuggest.test.tsx#L211)

- Navigate-back-with-`pendingAddress` wiring, and the review-added live-region announcement coverage.
  [`AddressPickerScreen.test.tsx:183`](../../workspace/core/frontend/fenzo-app/src/features/addressPicker/AddressPickerScreen.test.tsx#L183), [`AddressPickerScreen.test.tsx:235`](../../workspace/core/frontend/fenzo-app/src/features/addressPicker/AddressPickerScreen.test.tsx#L235)

- New service-layer test closing the review-found gap: the real `places.ts` implementation was previously only ever exercised via a full mock.
  [`places.test.ts`](../../workspace/core/frontend/fenzo-app/src/services/resources/places.test.ts)
