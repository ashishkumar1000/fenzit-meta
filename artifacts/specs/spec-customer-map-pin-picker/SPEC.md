---
id: SPEC-customer-map-pin-picker
companions:
  - touchpoints.md
sources: []
---

> **Canonical contract.** This SPEC and the files in `companions:` are the complete, preservation-validated contract for what to build, test, and validate. Source documents listed in frontmatter are for traceability — consult them only if you need narrative rationale or prose color this contract intentionally omits.

# Customer address via the map-pin picker (reuse of the office picker, no radius)

## Why

A pain to solve. When adding an office, the owner pins the exact spot on a map; when adding a customer, the address is a Google-Places search that lands on a street, not on the shop's gate. Field staff navigating to a customer therefore get approximate destinations. The office flow already proved the pin-picker UX; this work extends it to customers so every customer record can carry exact coordinates — without touching the backend, which already stores them.

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

## Constraints

- Zero backend changes: the `customers` table already has nullable `latitude`/`longitude`/`place_id`/`formatted_address`/`pincode` (migration `20260905000005`), and the FE `CreateCustomerRequest` already accepts them.
- The office flow must behave exactly as today: return to `OfficeForm`, radius clamp 50–1000 m, `gpsVerified` semantics, diff-gated rule edits.
- Preserve the static-pin/pan-under map pattern — no draggable native `Marker` (deliberate Fabric-spike finding); react-native-maps with Google provider and the app's light style.
- Reverse geocode never blocks Confirm: all its fields are nullable, fall back to raw coordinates, fire only on settle.
- Picker returns follow the repo's navigate-back-with-params idiom: pop to the `returnTo` target with a picked payload, caller reads once in an effect, then clears.
- `gpsVerified` stays office-only; customer picks never set it.
- The radius stepper and geofence circle render only in office mode — never in customer mode.

## Non-goals

- No Edit Customer — customers are create-only today (no PATCH endpoint); editing a misplaced pin is future work.
- No backend/API/database changes of any kind.
- No technician-side changes.
- No radius/geofence concept for customers.
- No redesign of the office picker UX.

## Success signal

An owner creates a customer whose saved record carries exact map-pinned coordinates plus a readable reverse-geocoded address, while every existing office add/edit flow (including radius) still works unchanged.
