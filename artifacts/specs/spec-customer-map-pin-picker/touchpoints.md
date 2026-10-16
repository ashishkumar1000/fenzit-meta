# Touchpoints — code map for SPEC-customer-map-pin-picker

FE-only (`workspace/core/frontend/fenzo-app`). Paths relative to repo root. No BE file changes.

## Screens and components involved

| File | Role in this change |
|---|---|
| `src/features/attendance/offices/OfficeMapPickerScreen.tsx` | Currently hardcodes `popTo('OfficeForm', { pickedLocation }, { merge: true })` and unconditional radius UI. Parametrize with a `mode` + return target; return payload and radius rendering become mode-dependent. |
| `src/features/attendance/offices/PickerBottomCard.tsx` | Bottom panel with reverse-geocode row, radius stepper, Confirm. Radius block hidden in customer mode. |
| `src/features/attendance/offices/PickerMapArea.tsx` | MapView + static centre pin + Circle. Geofence Circle renders only in office mode. Component props are already plain (`pin`, `radiusM`, callbacks, `mapRef`) — reuse as-is where possible. |
| `src/features/attendance/offices/RadiusStepper.tsx` | Office-only; untouched. |
| `src/features/customers/AddCustomerScreen.tsx` | Address field must open the picker screen instead of (or in addition to) hosting the sheet; applies the picked result into `PickedAddressSnapshot` + reverse-geocoded text; already keeps snapshot independent of `address`/`city`/`area` state. |
| `src/features/customers/components/AddressPickerField.tsx` | Entry-point control; becomes the tap target that navigates to the picker. |
| `src/features/addressPicker/AddressPickerSheet.tsx` | Shared search sheet, already opened inside the office picker. Customer mode keeps the manual-entry fallback visible (`onManualAddress` supplied); office mode keeps hiding it. |
| `src/navigation/types.ts` + `src/navigation/RootNavigator.tsx` | Route params for the picker (`initialLatitude?`, `initialLongitude?`, `radiusM` today) need a mode/return-target; `AddCustomer` gains a picked-location payload param read-once-then-clear. Route naming (rename vs. keep `OfficeMapPicker`) is the implementer's call — office behavior must not change. |
| `src/features/customers/requestMapping.ts` | `toCreateCustomerRequest` already maps structured fields; `area` merges into the address line. Pin path sends `latitude`/`longitude`/`formattedAddress`/`pincode` (+`city` when present), `placeId` only from search resolves. |

## Data shapes (verified)

- `ReverseGeocodedAddress` (`src/services/resources/places.ts`): `{ formattedAddress, city, pincode }` — each nullable; every-field-null means "no address", caller falls back to raw coordinates. Fired settle-only via `placesService.reverse(lat, lng, signal)`.
- `ResolvedPlace` (search path): `{ placeId, formattedAddress, city, pincode, latitude, longitude }` — `city`/`pincode` null when the place lacks them.
- `PickedAddressSnapshot` (`AddressPickerField.tsx`): `{ formattedAddress, pincode, latitude, longitude, placeId }` — the customer-side payload shape to keep filling.
- `PickedOfficeLocation` (`src/types/office.ts`): `{ latitude, longitude, radiusM, gpsVerified? }` — office return shape, unchanged.

## Idioms to follow

- Navigate-back-with-params: picker `popTo(returnRoute, { payload }, { merge: true })`; caller reads the param in an effect, read-once-then-clear. Precedents: `pickedLocation` (OfficeForm), `selectedSkillId` (SelectSkills), `SelectTechnicians.returnTo`.
- One screen per route, feature-folder colocation, `*Model.ts` for pure logic, services as plain function objects in `src/services/resources/`.
- Story-numbered doc comments (e.g. "Story 15-4") — continue the style.
