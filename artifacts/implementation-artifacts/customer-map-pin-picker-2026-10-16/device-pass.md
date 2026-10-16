# Device pass — customer map-pin picker (SPEC-customer-map-pin-picker)

**Date:** 2026-10-16 · **Device:** Pixel 6 `1C301FDF6002ZB` · **Build:** release arm64 from FE `25ac310` (+ trim fix), `adb install -r` in-place — owner login (Ayush, Business) survived. Second install adds the full-address multiline fix.
**Backend:** Render live. **Driver:** adb taps + screenshots (no human interaction).

| What | Evidence | Result |
|---|---|---|
| Update in-place, owner session preserved, home renders | `01-launch-after-update.png` | ✅ "Good afternoon, Ayush", no crash |
| Add Customer form shows new map entry point | `02-add-customer-form.png` | ✅ Address field reads "Tap to pin the location on a map" |
| CAP-1: field opens MapPinPicker, customer mode — NO radius stepper, NO geofence circle | `03-map-picker-customer.png` | ✅ "Place customer pin" header; search + locate-me only; reverse geocode row live ("Pinned near: 67/1, KG Halli… 560001") |
| Pan → settle → reverse geocode updates | `04-after-pan.png` | ✅ row re-resolved to ECC Rd, Whitefield area |
| CAP-3: Confirm auto-fills form — address text + City, Area untouched | `05-back-on-form-autofilled.png` | ✅ City "Bengaluru" auto-filled; address present |
| CAP-1 full round-trip: save with pinned location | `06-form-filled.png` → `07-after-save.png` | ✅ created (home "Add customer" tile 3→4 total), clean return to Home |
| **User finding — address tail-trimmed in the single-line field** ("…hitefield, Bengaluru…") | `05`/`06` | 🐞 fixed: design-system multiline variant; wraps in full |
| Fix verified: full address wraps, nothing trimmed; City auto-fill again | `08-map-picker-retest.png` → `09-form-full-address.png` | ✅ "Mana Placido Apartments, Pattandur Agrahara, Whitefield, Bengaluru, Karnataka 560066, India" shown in full across 3 lines |

Notes:
- The map ended up in Whitefield on both passes without an explicit pan landing there: the picker's designed **silent GPS fix** (Android, permission pre-granted) centres the map on the owner's area once the fix lands — the device is physically in Pattandur Agrahara. Not a bug; matches the 15-4 behavior doc.
- CAP-2 (search-inside-map with placeId) not driven here — Places search inside the picker was not exercised on-device; it is pinned by unit tests (`MapPinPickerScreen.customerPin.test.tsx`). Manual-entry fallback likewise unit-pinned only.
- Test data left behind: customer "Pin Test Customer" (+91 9900112233) with a Whitefield pin.
- Map preview row ("Pinned near:") intentionally stays a 2-line summary on the map screen; the full address lives on the form.

## CAP-5 pass — address details (second install, BE 9479c26 live)

**Build:** release arm64, FE `6d35173`. Backend `9479c26` pushed → Render auto-deploy; migration `20261016000002_add_customer_address_details.sql` applied via Supabase MCP **before** the app could send the field (BE strips unknown keys silently, so a stale backend would look like a successful save with the detail lost — the profile read-back is the proof).

| What | Evidence | Result |
|---|---|---|
| Baymard reveal under the multiline address field | `10-form-with-reveal.png` | ✅ "+ Add flat / building details" caption link; field hidden by default |
| Pin confirm → full address wraps, City auto-fills, reveal link intact | `11-after-pin.png` | ✅ |
| Reveal → "Flat / building / floor" optional input with example placeholder | `12-details-revealed.png` | ✅ |
| Detail typed, form complete | `13-details-filled.png` | ✅ "Shop 4, Gate 2" |
| Save → customer created, list row present | `14-customers-list.png` | ✅ top of the list |
| **Round-trip: detail read back from the live API on the profile** | `15-customer-detail-roundtrip.png` | ✅ own row under the location line — proves live BE has the column + contract, not a stripped field |

Technician job-detail rendering (details lead the maps row) and the owner job-detail customer-card line are pinned by unit tests (`TechJobDetailContent.test.tsx`); not driven on-device — needs a job for the test customer.

## Design-v2 pass — sectioned Add Customer (third install, FE 7eaa342 + BE 992ab68)

| What | Evidence | Result |
|---|---|---|
| Sectioned layout per the mock: two FormSectionCards, icon chips, subtitles, red "Required *" on the location card; preview box with "Set location >" pill; Flat/House + Street/Landmark + City/Area-Pincode fields; "Save customer" CTA | `16-design-v2-empty.png` | ✅ matches the mock |
| Required gate enforced: name + phone filled but NO location → Save stays disabled | `17-v2-gate-name-phone-only.png` | ✅ (gate asserted in unit tests; visually button dimmed) |
| Pin → preview box fills with the resolved line, button flips to "Change >", City auto-fills, Street stays EMPTY (resolved line no longer copied into free text — design-v2 semantics), Save enables | `18-v2-picked.png` | ✅ |
| Detail + street filled | `19-v2-filled.png` | ✅ "Shop 5, Gate 1" / "Near the big water tank" |
| Save → list row shows city · street text (v2 semantics: free text = user's street) | `20-v2-list.png` | ✅ |
| Profile round-trip: location row shows the RESOLVED line (formattedAddress preferred), details row shows "Shop 5, Gate 1" | `21-v2-profile.png` | ✅ both from the live API |

Note: an incoming call interrupted one typing pass — waited it out, no call was answered/declined.
Observation for later: list rows read `city · address` where address is now the user's street text — a pin-only customer's list row shows just the city. If that feels thin, `customerLocation` can prefer `formattedAddress` (the list API already returns it); deliberately not changed without a call.

