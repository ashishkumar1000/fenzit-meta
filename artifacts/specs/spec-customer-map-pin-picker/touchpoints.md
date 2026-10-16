# Touchpoints — code map for SPEC-customer-map-pin-picker

FE (`workspace/core/frontend/fenzo-app`) for CAP-1–4; CAP-5 (address details) spans BE (`workspace/core/backend/fenzit-be`) + FE. Paths relative to each repo root.

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

## CAP-5 touchpoints — address details (BE + FE)

**BE (`fenzit-be`):**
- `supabase/migrations/` — new `20261016<seq>_add_customer_address_details.sql`, one `ALTER TABLE customers ADD COLUMN address_details VARCHAR(255);` mirroring `20260905000005_add_customer_structured_address.sql` style.
- `src/common/dto/structured-address.dto.ts` — `addressDetails?` (`@IsOptional @Transform(trim) @MaxLength(255)`); shared by `CreateCustomerDto` AND `src/jobs/dto/new-customer.dto.ts`, so both create paths accept it.
- `src/customers/customers.service.ts` — single-source mapping: `StructuredAddressFields` (:47), `structuredAddressColumns` (:75), plus surface types/selects: `CustomerResponse` (:29), `CustomerListItem`/`ListRow` (:90/:106), list select (:361), `CustomerRow` (:145), `CUSTOMER_COLUMNS` (:158), `toResponse` (:674).
- `src/jobs/jobs.service.ts` — detail embed: customer select (:782-789), `CustomerProfile` (:96), `CustomerProfileRow` (:174), `toDetailResponse` (:911). Profile jobs-page embed (`users.service.ts:679`) deliberately stays lean.
- Swagger docs: `customer-list-item.dto.ts`, `customer-detail-response.dto.ts`; `docs/api-contracts.md` POST /customers body (also stale today), customers GET sections, job-detail embed (~:423).
- Tests: extend `customers.service.spec.ts` create block (all-present + only-provided), `structured-address.dto.spec.ts` (255-cap rejection, trim/passthrough), `jobs.service.spec.ts` if it pins the embed shape.

**FE (`fenzo-app`):**
- `src/services/resources/customers.ts` — `CreateCustomerRequest.addressDetails?`; `CreatedCustomer`/`CustomerDetail` gain `addressDetails: string | null` (list `ApiCustomer` stays narrow — the list API doesn't return address fields).
- `src/features/customers/types.ts` (`NewCustomerInput.addressDetails?`) + `requestMapping.ts` (distinct passthrough field — never merged into the address line; omitted when empty).
- `src/features/customers/components/AddressPickerField.tsx` — Baymard reveal under the address field: a "Add flat / building details" Pressable reveals an optional Input; details value owned by the screen, independent of pick origin and never cleared by a re-pick. No repo precedent for a reveal — mirror icon+text Pressable rows (`accessibilityRole="button"`, caption styling).
- `src/features/customers/AddCustomerScreen.tsx` — `addressDetails` state → `buildRequest`.
- `src/services/resources/jobs.ts` — `JobDetailCustomer.addressDetails: string | null` (:245-259).
- `src/features/technicianApp/components/TechJobDetailContent.tsx` mapsRow (:139-156) — detail renders as its own first line above the street/city line; `openMaps` unchanged (coords win).
- `src/features/customerDetail/CustomerDetailScreen.tsx` location metaRow (:243-250) + `format.ts` `customerLocation()` — show detail when present.
- `src/features/jobDetail/JobDetailScreen.tsx` Customer SectionCard (:364-434) — muted detail line when present.
