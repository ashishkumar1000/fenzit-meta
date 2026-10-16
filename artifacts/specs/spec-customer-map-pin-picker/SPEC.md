---
id: SPEC-customer-map-pin-picker
companions:
  - touchpoints.md
sources: []
---

> **Canonical contract.** This SPEC and the files in `companions:` are the complete, preservation-validated contract for what to build, test, and validate. Source documents listed in frontmatter are for traceability — consult them only if you need narrative rationale or prose color this contract intentionally omits.

# Customer address via the map-pin picker (reuse of the office picker, no radius)

## Why

A pain to solve. When adding an office, the owner pins the exact spot on a map; when adding a customer, the address is a Google-Places search that lands on a street, not on the shop's gate. Field staff navigating to a customer therefore get approximate destinations. The office flow already proved the pin-picker UX; this work extends it to customers so every customer record can carry exact coordinates — the picker itself needed no backend change (the `customers` table already stored coordinates), and the one sanctioned backend increment since (CAP-5) adds a single user-entered details column, because a resolved address alone doesn't get a technician through the final handoff.

## Capabilities

- **CAP-1** — Pin-drop address entry
  - **intent:** An owner adding a customer can set the customer's exact location by dropping a map pin instead of relying on search alone.
  - **success:** From Add Customer, tapping the address field opens the map-pin screen (no radius UI); confirming a pin returns to the form with coordinates; saving the customer persists `latitude`/`longitude` on the customer record.
- **CAP-2** — Search inside the map
  - **intent:** While picking on the map, the owner can search an address to move the pin.
  - **success:** A search result re-centers the pin; a location confirmed via search carries the resolved place's `placeId` and `formattedAddress`, while a pin-only location carries no `placeId`.
- **CAP-3** — Reverse-geocode auto-fill
  - **intent:** A dropped pin yields readable address text without typing.
  - **success:** After confirming a pin, the form shows the reverse-geocoded `formattedAddress` and `pincode` (and `city` when Google returns one); subsequent edits to city/area never clear the snapshot (additive behavior preserved).
- **CAP-4** — Manual fallback preserved
  - **intent:** The owner can still type an address when Places cannot find it.
  - **success:** The manual path saves address text with null coordinates and no `placeId`, exactly as today.
- **CAP-5** — Address details for the final handoff
  - **intent:** An owner can record extra location detail a resolved address lacks (flat, building, floor, landmark) so a technician can find the exact door.
  - **success:** The detail is saved into its own `customers.address_details` column (never merged into `address`/`formatted_address` text), flows through both create paths (`POST /customers` and the jobs `newCustomer` find-or-create), and reaches the technician on the job-detail navigation row plus the owner's customer/job surfaces; a re-pin never clears or overwrites it.

## Constraints

- CAP-1–4 remain frontend-only: the `customers` table already had nullable `latitude`/`longitude`/`place_id`/`formatted_address`/`pincode`, and the FE `CreateCustomerRequest` already accepted them. CAP-5 is the one sanctioned backend increment: a single nullable `address_details VARCHAR(255)` column plus contract passthrough.
- User-entered detail lives in its own column end to end — merging it into `address` or `formatted_address` text at storage is forbidden; BE trims and caps at 255, FE omits it when empty so the BE stores null.
- The detail input is optional, hidden behind an "Add flat / building details" reveal (Baymard address-line-2 pattern), clearly labeled optional, and applies to pin, search, and manual picks; a re-pick never clears it.
- The office flow must behave exactly as today: return to `OfficeForm`, radius clamp 50–1000 m, `gpsVerified` semantics, diff-gated rule edits.
- Preserve the static-pin/pan-under map pattern — no draggable native `Marker` (deliberate Fabric-spike finding); react-native-maps with Google provider and the app's light style.
- Reverse geocode never blocks Confirm: all its fields are nullable, fall back to raw coordinates, fire only on settle.
- Picker returns follow the repo's navigate-back-with-params idiom: pop to the `returnTo` target with a picked payload, caller reads once in an effect, then clears.
- `gpsVerified` stays office-only; customer picks never set it.
- The radius stepper and geofence circle render only in office mode — never in customer mode.

## Non-goals

- No Edit Customer — customers are create-only today (no PATCH endpoint); editing a misplaced pin or later-changing address details is future work.
- No structured column breakdown (separate flat_no/building/floor/landmark columns) — one free-text details field.
- No Google Address Descriptors enrichment of the reverse-geocode endpoint (future enhancement; not user-entered).
- No changes to the lean profile jobs-page customer embed (job detail is the carrier for the technician).
- No technician-side or office-flow changes beyond rendering the new field where it already shows customer address.

## Success signal

An owner creates a customer whose saved record carries exact map-pinned coordinates plus a readable reverse-geocoded address, while every existing office add/edit flow (including radius) still works unchanged.
