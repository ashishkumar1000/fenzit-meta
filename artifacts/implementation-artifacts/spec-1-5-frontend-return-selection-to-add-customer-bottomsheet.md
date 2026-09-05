---
title: 'Frontend — Return selection to Add Customer bottomsheet'
type: 'feature'
created: '2026-09-05'
status: 'done'
review_loop_iteration: 1
context: []
baseline_commit: 'd04f605b54878e37cdfd6eb7a736eec0897db604'
---

## Spec Change Log

- **2026-09-06 — Renegotiated after step-04 review (Acceptance Auditor layer).** The frozen Intent below originally described a `pendingAddress` route-param handoff between a pushed `AddressPickerScreen` and a bottomsheet-based `AddCustomerSheet`. On a physical device, pushing a full-screen stack route on top of `AddCustomerSheet`'s presented native modal was found to silently dismiss that modal (native dismissal is invisible to JS state) — discovered and fixed live during implementation. The Intent, Boundaries, and I/O matrix below have been rewritten to describe the shipped architecture (`AddressPickerSheet` nested-modal + `AddCustomerScreen` full-page route + callback props, no route param) rather than reverting to the broken design. Renegotiation approved by the story owner during code review; see the Review Findings subsection under Tasks & Acceptance for the full finding.

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** Story 1.4 built `AddressPickerScreen`, a pushed stack route that resolves and navigates back with `{ pendingAddress: ResolvedPlace }` — but pushing that stack route on top of `AddCustomerSheet`'s presented native modal was found (on a physical device) to silently dismiss the modal, since a native sheet's dismissal never touches JS state. Nothing opened the picker from `AddCustomerSheet` and nothing read the result back either way.

**Approach:** Re-platform both screens onto a design compatible with a single native-modal layer. `AddressPickerScreen` becomes `AddressPickerSheet` — a `Sheet`-based (TrueSheet) modal nested directly inside its host, opened/closed via `visible`/`onClose` props, resolving via an `onResolved(place: ResolvedPlace)` callback instead of navigating anywhere. `AddCustomerSheet` becomes `AddCustomerScreen` — a full-page route (so it can own `AddressPickerSheet` as its own nested modal without a second modal-over-modal conflict), pushed from `CustomersScreen`/`NewJobScreen` with `returnRouteName`, returning via `goBack()` (`'Customers'`) or a `createdCustomerId` param (`'NewJob'`). The free-text address stays editable and non-mandatory; the five resolved fields are still sent on submit only when a resolve snapshot exists.

## Boundaries & Constraints

**Always:**
- `AddressPickerSheet` takes `visible: boolean`, `onClose: () => void`, `onResolved: (place: ResolvedPlace) => void` props — rendered as a nested modal directly inside `AddCustomerScreen`, never navigated to and never route-aware.
- `AddCustomerScreen` is a full-page route (`RootStackParamList.AddCustomer: { returnRouteName: AddCustomerReturnRouteName }`, `AddCustomerReturnRouteName = 'Customers' | 'NewJob'`) that owns `AddressPickerSheet` directly. Its `handleAddressResolved` callback populates: `address` state ← `formattedAddress`, `city` state ← `city` (only if non-null; `area` is untouched, `ResolvedPlace` has no area data), plus local snapshot state `formattedAddress/pincode/latitude/longitude/placeId` for submission.
- The snapshot fields are decoupled from further hand-edits to the `address`/`city` text inputs — editing address text after populate never clears or resyncs the snapshot (matches the additive-column backend design; free text and structured snapshot are separate fields end to end).
- On populate, trigger a brief (~200ms) `Animated.timing` soft primary-tint border highlight on the address field. No toast/snackbar.
- `returnRouteName` decides post-save behavior: `'Customers'` → `navigation.goBack()` (the shared `useCustomers` store already reflects the new row via `upsertCustomer`, so no return param is needed); `'NewJob'` → `navigation.navigate({ name: 'NewJob', params: { createdCustomerId }, merge: true })`.
- `CreateCustomerRequest` (`services/resources/customers.ts`) gains the same 5 optional fields, 1:1 name match with backend `CreateCustomerDto` (already present, Story 1.3) — sent conditionally, only when a resolved snapshot exists. `toCreateCustomerRequest` (`requestMapping.ts`) is the one place this omission rule lives.
- An Owner who never opens the picker submits successfully with only today's fields — the 5 new fields are always optional end to end.

**Ask First:** None — mechanism, field names, and UX are already fixed by `epic-1-context.md` and the Story 1.4 spec; the re-platforming above is a mechanical consequence of the on-device conflict, not a UX change.

**Never:** Do not add a debounce/animation library — reuse `Animated` from `react-native`. Do not couple the free-text address edit to the structured snapshot (no re-resolve, no clearing).

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Picker skipped entirely | Owner never taps address field, submits with free-text only | Customer created with existing fields only, no 5 new fields sent | N/A |
| Resolve → populate | `AddressPickerSheet` resolves, calls `onResolved(place)` | `AddCustomerScreen`'s address+city populate, ~200ms border pulse, no toast; sheet closes | N/A |
| Hand-edit after populate | Owner edits address text post-populate | Free text reflects edit; structured snapshot (lat/lng/pincode/placeId/formattedAddress) still submitted unchanged | N/A |
| Submit with snapshot present | Snapshot present, Owner taps "Add customer" | Request includes `formattedAddress, pincode, latitude, longitude, placeId` alongside existing fields | N/A |
| Cancel back from picker | Owner uses close/drag-down/back or "Enter manually" in the sheet | No `onResolved` call; sheet closes via `onClose`, `AddCustomerScreen` state unchanged | N/A |

</frozen-after-approval>

## Code Map

_Updated 2026-09-06 to match the shipped architecture — see Spec Change Log above._

- `src/features/customers/AddCustomerScreen.tsx` (new; replaces the deleted `AddCustomerSheet.tsx`) -- full-page route; `handleAddressResolved` (L103-129) populates address/city + snapshot state and fires the border pulse; `addressPickerVisible` state + `AddressPickerSheet` nested modal (L314-318); `handleSubmit` (L150-199) builds the request via `toCreateCustomerRequest`, conditionally spreading the 5 resolved fields, then `upsertCustomer`+`loadCustomers({force:true})`, then `goBack()`/`navigate('NewJob', {createdCustomerId})` per `returnRouteName`
- `src/features/customers/requestMapping.ts` (new) -- `toCreateCustomerRequest`, the one place the "5 fields or none" omission rule lives
- `src/features/addressPicker/AddressPickerSheet.tsx` (renamed from `AddressPickerScreen.tsx`) -- `visible`/`onClose`/`onResolved` props instead of navigation; renders inside a DS `Sheet` (`detents={[0.9]}`, `dismissible={isInteractive}`)
- `src/features/addressPicker/useAddressAutosuggest.ts` -- gained `reset()` (mints a fresh session token + clears all state), called by `AddressPickerSheet` every time it opens (content stays mounted across opens, unlike the old per-mount pushed screen)
- `src/features/customers/CustomersScreen.tsx` -- `handleAdd` pushes `AddCustomer` with `returnRouteName: 'Customers'`; no `route`/`pendingAddress` consumption (the shared `useCustomers` store already reflects a new row via `upsertCustomer`)
- `src/features/newJob/NewJobScreen.tsx` -- pushes `AddCustomer` with `returnRouteName: 'NewJob'`; consumes `route.params?.createdCustomerId` on return, selects it in the draft, clears via `setParams`
- `src/navigation/types.ts` -- `RootStackParamList.AddCustomer: { returnRouteName: AddCustomerReturnRouteName }`; `RootStackParamList.NewJob: { createdCustomerId?: string } | undefined`; `AddCustomerReturnRouteName = 'Customers' | 'NewJob'` (replaces the old `AddressPickerReturnRouteName`); `MainTabParamList.Customers` stays `undefined` — no route param needed under this design
- `src/navigation/RootNavigator.tsx` -- registers `AddCustomer` (replacing the old `AddressPicker` route registration)
- `src/services/resources/customers.ts` -- `CreateCustomerRequest` gains the 5 optional fields; `create()` passthrough, no change needed
- `src/services/resources/places.ts` -- `ResolvedPlace` type (reference only, already exported via `services/resources/index.ts` → `services/index.ts` barrel)
- `src/components/ui/Sheet.tsx` -- gained a `dismissible` pass-through prop (step-04 review fix, see Review Findings) and `content.paddingTop` for grabber clearance
- `src/components/ui/Input.tsx` -- gained an `editable` prop (false blocks keyboard/typing without graying out, for `AddCustomerScreen`'s tap-to-open address field)
- Backend `fenzit-be` `src/customers/dto/create-customer.dto.ts` and `src/customers/customers.service.ts` -- reference only, confirmed done (Story 1.3), no changes

## Tasks & Acceptance

**Execution:**
- [x] `src/navigation/types.ts` -- add `pendingAddress` to `MainTabParamList.Customers`, extend `AddressPickerReturnRouteName` to `'NewJob' | 'Customers'` -- unblocks typed param reads on both host screens
- [x] `src/features/customers/components/AddCustomerSheet.tsx` -- add `onPressAddress`/`pendingAddress` props, 5-field snapshot state, populate `useEffect` + border-pulse `Animated`, extend `reset()`, wire address `Input` trigger, extend `handleSubmit` -- core sheet behavior
- [x] `src/features/customers/CustomersScreen.tsx` -- add `useRoute`, populate/clear `useEffect`, wire sheet props, extend `handleSubmitCustomer` -- Customers-tab host wiring
- [x] `src/features/newJob/NewJobScreen.tsx` -- destructure `route`, populate/clear `useEffect`, wire sheet props, extend `handleSubmitCustomer` -- NewJob host wiring
- [x] `src/services/resources/customers.ts` -- extend `CreateCustomerRequest` with the 5 optional fields -- backend contract match
- [x] Unit/component tests for `AddCustomerSheet` (populate, pulse trigger, hand-edit decoupling, submit payload) and both host screens' param-consume-and-clear effect

**Acceptance Criteria:**
- Given a resolve call in `AddressPickerSheet` succeeds, when it calls `onResolved(place)`, then `AddCustomerScreen`'s address `Input` and City populate from the resolved place with a ~200ms border pulse, and the sheet closes
- Given the Owner hand-edits the address text after populate, when they submit, then the edit is reflected in the free-text field while the structured snapshot fields are still sent unchanged
- Given an Owner who never opens the address picker, when they submit "Add customer" with only existing free-text fields, then the customer is created successfully with none of the 5 new fields sent

### Review Findings

- [x] [Review][Decision] Implementation architecture diverged from the frozen spec's Intent without a documented renegotiation — the shipped code deletes/renames `AddressPickerScreen.tsx` → `AddressPickerSheet.tsx` (pushed stack route → nested `Sheet` modal) and `AddCustomerSheet.tsx` → `AddCustomerScreen.tsx` (bottomsheet host form → full-page route), replacing the `pendingAddress` route-param handoff with `onClose`/`onResolved` callback props and a `createdCustomerId` return param. **Resolved:** renegotiated with the story owner — spec's Intent, Boundaries, I/O Matrix, Code Map, and AC1 rewritten in place to describe the shipped architecture (see Spec Change Log at the top of this file), rather than reverting to the buggy design.
- [x] [Review][Patch] Native swipe-down/Android-back gesture could dismiss `AddressPickerSheet` mid-resolve, desyncing JS state — `onClose` was stubbed to a no-op during `phase === 'resolving'` to block dismissal, but per `Sheet.tsx`'s documented caveat, drag-down/back used to dismiss the native sheet BEFORE `onClose` ran and couldn't be vetoed that way. **Fixed:** `Sheet` now accepts a `dismissible` prop (passes through to `TrueSheet`'s own `dismissible`, which blocks both paths at the native level), and `AddressPickerSheet` passes `dismissible={isInteractive}` — interactive dismissal is now genuinely blocked while a resolve is in flight, not just best-effort via `onClose`. [`src/components/ui/Sheet.tsx`, `src/features/addressPicker/AddressPickerSheet.tsx:212`]
- [x] [Review][Patch] `reset()` fires a spurious autosuggest call for the stale pre-reset query on sheet reopen, and is completely untested [`src/features/addressPicker/useAddressAutosuggest.ts:170-183`, `src/features/addressPicker/AddressPickerSheet.tsx:62-67`] — `reset()` sets `query` and a fresh `sessionToken` in the same render; `fetchSuggestions` depends on `[sessionToken]`, so the effect gated on `[debouncedQuery, fetchSuggestions]` re-fires on the still-stale (pre-reset) `debouncedQuery` before its own 300ms timer catches up, firing one unwanted billed autosuggest call under the new session token for the previous search text. `useAddressAutosuggest.test.tsx` has zero references to `reset`; `AddressPickerSheet.test.tsx` only asserts the mocked `reset` was called, never runs the real implementation. **Fixed:** `sessionToken` is now mirrored into a ref that `fetchSuggestions`/`resolvePlace` read instead of closing over the state value, so a token change alone no longer recreates `fetchSuggestions` or re-triggers the debounced-search effect. Added a `reset` describe block to `useAddressAutosuggest.test.tsx` covering both the token-regeneration contract and the no-spurious-refetch behavior.
- [x] [Review][Patch] Search input won't auto-focus after the first sheet open [`src/features/addressPicker/AddressPickerSheet.tsx:216`] — `Input` uses plain `autoFocus`, but `Sheet` keeps children mounted across opens/closes (own doc), so the `Input` only ever mounts once; the keyboard silently stops auto-appearing from the 2nd open onward. **Fixed:** dropped `autoFocus`, added an `inputRef` via `Input`'s existing `forwardRef`, and focus now fires from `Sheet`'s `onDidPresent` on every open.
- [x] [Review][Patch] Resolving-phase lockout lost its explicit test assertions in the screen→sheet rewrite [`src/features/addressPicker/AddressPickerSheet.test.tsx:156`] — the deleted `AddressPickerScreen.test.tsx` asserted the search `Input`'s `disabled` prop and the back button's `disabled` prop during a resolve; the replacement test only checks suggestion rows' `accessibilityState`, never the `Input`'s `disabled` prop or the `Sheet`'s `onClose` no-op contract. **Fixed:** the resolving test now also asserts `Input`'s `disabled` prop, `Sheet`'s `dismissible` prop, and that `Sheet`'s `onClose` no-ops.
- [x] [Review][Patch] A failed post-create list refresh is shown as a customer-creation failure [`src/features/customers/AddCustomerScreen.tsx:182-183`] — `handleSubmit` awaits `loadCustomers({ force: true })` inside the same `try` as `customerService.create`; `loadCustomers` does a real `GET /customers` fetch that can independently fail, and its rejection is caught and rendered via `createErrorMessage` as if the save itself failed — even though the customer was already created and already pushed into the local store via `upsertCustomer`. **Fixed:** wrapped the `loadCustomers` call in its own `.catch(() => {})`.
- [x] [Review][Patch] `editable={false}` doesn't block touch pass-through on the wrapped `TextInput` [`src/components/ui/Input.tsx:91-97`, `src/features/customers/AddCustomerScreen.tsx:276-293`] — the address field wraps a non-editable `Input` in a `Pressable` so a tap anywhere opens the picker, but `editable={false}` doesn't set `pointerEvents="none"` on the underlying `TextInput`, so on some platform/version combos the `TextInput` could still capture the touch instead of bubbling to the `Pressable`. **Fixed:** added `pointerEvents={!disabled && editable ? 'auto' : 'none'}` to the inner `TextInput`. Still recommend a quick on-device tap check on the address field — React Test Renderer can't simulate real touch/responder resolution.
- [x] [Review][Patch] Trim-on-submit is no longer covered by any test [`src/features/customers/AddCustomerScreen.test.tsx`] — the deleted `AddCustomerSheet.test.tsx` had a test typing padded whitespace (`'  Ramesh Kumar  '`) and asserting it was trimmed on submit; no test in the new file uses padded input, even though `handleSubmit` still calls `.trim()`. **Fixed:** added a trim-on-submit test.
- [x] [Review][Patch] Stale `useRoute`/`setParams` mock and comment in `__tests__/customers-screen.test.tsx:14-22` — the mock and its comment describe a `pendingAddress`/`AddressPicker` return-trip flow that this diff deletes entirely; `CustomersScreen` doesn't call `useRoute` or `navigation.setParams` at all under the current architecture. **Fixed:** removed the stale mock/comment.
- [x] [Review][Patch] Stale cross-reference to a deleted component [`src/features/jobDetail/components/EditJobSheet.tsx:5`] — its file doc still says its layout matches "the same layout as AddCustomerSheet," but `AddCustomerSheet` was deleted in this diff (replaced by the full-page `AddCustomerScreen`). **Fixed:** removed the cross-reference.
- [x] [Review][Defer] No linked follow-up ticket for the documented ScrollView-less suggestion list [`src/features/addressPicker/AddressPickerSheet.tsx`] — deferred, pre-existing session decision (accepted trade-off, see file doc); recommend filing a follow-up story so it isn't lost.

## Design Notes

Border pulse: an `Animated.Value` (0→1→0 via two chained `Animated.timing` calls, ~200ms total) interpolated to the `Input`'s border color between its default and a primary tint — no existing pulse to copy, follow the same `Animated`-from-`react-native` primitive already used for press-scale in `Button.tsx`/`Card.tsx`/`IconButton.tsx`.

## Verification

**Commands:**
- `bun run test -- AddCustomerScreen AddressPickerSheet CustomersScreen NewJobScreen useAddressAutosuggest` -- expected: new/updated tests pass
- `bun run build` -- expected: no TypeScript errors

## Suggested Review Order

_Updated 2026-09-06 to match the shipped architecture — see Spec Change Log above._

**`AddressPickerSheet`: nested modal, resolve, dismiss guard**

- `visible`/`onClose`/`onResolved` props replace the old pushed-route navigation contract; `reset()` re-mints the session token every time the sheet opens (content stays mounted while hidden).
  [`AddressPickerSheet.tsx:49`](../../workspace/core/frontend/fenzo-app/src/features/addressPicker/AddressPickerSheet.tsx#L49)

- `dismissible={isInteractive}` blocks native drag-down/Android-back dismissal at the `TrueSheet` level while a resolve is in flight (step-04 review fix).
  [`AddressPickerSheet.tsx:212`](../../workspace/core/frontend/fenzo-app/src/features/addressPicker/AddressPickerSheet.tsx#L212), [`Sheet.tsx`](../../workspace/core/frontend/fenzo-app/src/components/ui/Sheet.tsx)

**`AddCustomerScreen`: trigger, populate, submit**

- `handleAddressResolved` — seeds the free-text fields plus the independent structured snapshot, starts the border pulse, closes the sheet.
  [`AddCustomerScreen.tsx:103`](../../workspace/core/frontend/fenzo-app/src/features/customers/AddCustomerScreen.tsx#L103)

- Tap trigger — the whole address field (not just an icon) is wrapped in a `Pressable`, `disabled` during submit; `editable={false}` on the inner `Input` blocks keyboard/typing.
  [`AddCustomerScreen.tsx:276`](../../workspace/core/frontend/fenzo-app/src/features/customers/AddCustomerScreen.tsx#L276)

- `handleSubmit` — where the snapshot's presence gates whether the 5 fields are sent at all, and where a successful create pushes into the shared store before returning.
  [`AddCustomerScreen.tsx:150`](../../workspace/core/frontend/fenzo-app/src/features/customers/AddCustomerScreen.tsx#L150)

**Shared request mapping**

- `toCreateCustomerRequest` — the one place the "Places is additive" field-omission rule lives.
  [`requestMapping.ts:23`](../../workspace/core/frontend/fenzo-app/src/features/customers/requestMapping.ts#L23)

**Host screens: push and return**

- `CustomersScreen.handleAdd` pushes `AddCustomer` with `returnRouteName: 'Customers'`; no return param needed (shared `useCustomers` store).
  [`CustomersScreen.tsx:84`](../../workspace/core/frontend/fenzo-app/src/features/customers/CustomersScreen.tsx#L84)

- `NewJobScreen` pushes with `returnRouteName: 'NewJob'` and consumes `route.params?.createdCustomerId` on return, clearing it via `setParams`.
  [`NewJobScreen.tsx`](../../workspace/core/frontend/fenzo-app/src/features/newJob/NewJobScreen.tsx)

**Tests (peripherals)**

- Form bindings, address-field trigger/populate, trim-on-submit, and submit-with/without-snapshot.
  [`AddCustomerScreen.test.tsx`](../../workspace/core/frontend/fenzo-app/src/features/customers/AddCustomerScreen.test.tsx)

- `reset()`'s session-token/state-clear contract and the no-spurious-refetch-on-reopen case (step-04 review addition).
  [`useAddressAutosuggest.test.tsx`](../../workspace/core/frontend/fenzo-app/src/features/addressPicker/useAddressAutosuggest.test.tsx)

- Resolving-phase lockout (`Input.disabled`, `Sheet.dismissible`, `onClose` no-op) and the 8-phase render matrix.
  [`AddressPickerSheet.test.tsx`](../../workspace/core/frontend/fenzo-app/src/features/addressPicker/AddressPickerSheet.test.tsx)

- "Add" button navigation wiring for both host screens.
  [`CustomersScreen.test.tsx`](../../workspace/core/frontend/fenzo-app/src/features/customers/CustomersScreen.test.tsx), [`NewJobScreen.test.tsx`](../../workspace/core/frontend/fenzo-app/src/features/newJob/NewJobScreen.test.tsx)
