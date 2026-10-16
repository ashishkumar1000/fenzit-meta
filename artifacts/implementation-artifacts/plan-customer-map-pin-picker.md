---
title: 'Customer address via the map-pin picker (office picker reuse, no radius)'
type: 'feature'
ticket: ''
created: '2026-10-16'
status: 'built'
route: 'oneshot'
route_source: 'auto'
review: 'quick'
review_source: 'auto'
lenses_ran:
  - quick
review_loop_iteration: 0
baseline_revision: '210156a0664568df91c6d9e7ef0446a6d1891093'
context:
  - '{project-root}/artifacts/specs/spec-customer-map-pin-picker/SPEC.md'
  - '{project-root}/artifacts/specs/spec-customer-map-pin-picker/touchpoints.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** Add Customer's address entry is Google-Places search only; an owner cannot pin a customer's exact location the way they already can for an office, so customer records end up with approximate (or null) coordinates and field staff navigate to the wrong spot.

**Approach:** Reuse the Add-Office map-pin picker as one shared parametrized screen — `mode: 'office' | 'customer'` plus a return target. Customer mode: tapping the Add Customer address field opens the picker; the radius stepper and geofence circle never render; Places search stays available inside the picker (a result moves the pin); the manual type-address fallback stays available (office mode keeps hiding it); Confirm pops back to AddCustomer with `{ latitude, longitude, formattedAddress, pincode, city?, placeId? }` where placeId exists only for search-resolved locations, and the form auto-fills the reverse-geocoded text (formattedAddress + pincode + city when Google returns one) while City/Area stay editable and hand-edits never clear the snapshot. `gpsVerified` stays office-only. Zero backend changes — `customers` already has nullable `latitude`/`longitude`/`place_id` columns and `CreateCustomerRequest` already accepts them. The office flow must behave exactly as before.

</frozen-after-approval>

## Implementation Notes

Oneshot route: the change is largely mechanical param-threading (hide radius, thread mode/returnTo, wire navigate + apply) reusing verified components and data shapes; all investigation is already distilled in the spec + touchpoints (see `context:`), and the user approved implementation up front, so it is implemented directly in this session.

Decisions and notes while implementing:
- Route renamed `OfficeMapPicker` → `MapPinPicker` with `mode: 'office' | 'customer'` (+ `MapPinPickerMode` export); the return target is mode-derived (office → OfficeForm, customer → AddCustomer) instead of a generic `returnTo` — only two callers exist, and this stays type-safe.
- Screen file renamed to `MapPinPickerScreen.tsx` (git mv), still under `attendance/offices/` next to its subcomponents.
- `PickedAddressSnapshot`/`PickedAddress` moved from `AddressPickerField.tsx` to `features/customers/types.ts` (navigation/types.ts imports the domain type, mirroring `PickedOfficeLocation` in `types/office.ts`); snapshot widened: `placeId`/`formattedAddress` nullable (pin drops carry no placeId; reverse geocode text can be null).
- Payload gate moved: `toCreateCustomerRequest` gates the structured block on `latitude`/`longitude` presence (was `placeId`), each text field gated on its own — a pin drop saves coords without placeId.
- Customer confirm-time snapshot freshness: reverse-geocode result is stored paired with the centre it resolved; Confirm uses it only if it matches the confirmed centre (ε 1e-4), preferring the resolved search place when the pin still sits on it (only that path carries placeId). An in-flight reverse contributes nothing rather than blocking.
- `AddressPickerField` is now presentational (onPress + `pickSignal` pulse trigger); the search sheet + manual fallback live solely in the picker screen (manual enabled only in customer mode). Placeholder/labels updated to map wording.
- `AddCustomer` params made all-optional (`| undefined`, the NewJob merge convention); screen defaults `returnRouteName` to `'Customers'` — merge returns carry only `pickedAddress`.
- Radius UI: `radiusM`/`onRadiusChange` optional on `PickerBottomCard` (stepper hidden when absent); `PickerMapArea.radiusM` optional (Circle gated).
- Repo quirks found: `bun run lint` is broken repo-wide (eslint config file never committed — pre-existing); `bun run test` only works with real node on PATH (Bun's node shim crashes jest-runtime in every suite — environmental). `bun x tsc --noEmit` clean; full jest run (240 suites / 3009 tests) green with node v24.13.0.
- Tests: `AddCustomerScreen.test.tsx` address-flow tests rewritten to pin the new contract (field navigates to `MapPinPicker` mode customer; picks arrive via `pickedAddress` param, read-once-clear; payload gating per pick origin incl. pin-with-no-placeId and no-address-fallback cases); sheet-based tests removed with the sheet. Office handoff test untouched and green.

## Review Triage Log

Quick lens (one pass, 4 findings, none against acceptance criteria):

- `addressPicker/index.ts` module doc still said the sheet is rendered from AddCustomerScreen — `low` (doc-rot caused by this diff; trivial fix) → **patched**: doc now names MapPinPickerScreen as the host.
- `AddressPickerSheet` `onManualAddress` prop doc claimed "AddCustomerScreen keeps passing it" — `low` (same doc-rot, now actively wrong) → **patched**: doc rewritten for the mode-driven wiring.
- `MapPinPickerScreen` read route params through an ad-hoc inline type, duplicating the mode union and downgrading required `mode` — `low` (developer-only; call sites stay compile-checked since the route type keeps `mode` required) → **patched**: cast is now `NonNullable<RootStackParamList['MapPinPicker']>`; no duplicated union.
- Producer side of the return contract (confirm-time resolved-vs-reverse selection, manual pop, radius-never-in-customer-mode) had no test coverage — `medium` (verification gap on new code) → **patched**: new `MapPinPickerScreen.customerPin.test.tsx` (6 tests) pins the producer contract; full screen-level suites stay deferred per 15-4 review decision 3a.

## Verification

**Commands:**
- `bun run typecheck` (or the repo's tsc script) -- expected: no errors
- `bun run lint` -- expected: no new violations
- repo unit-test script, if present -- expected: all pass
