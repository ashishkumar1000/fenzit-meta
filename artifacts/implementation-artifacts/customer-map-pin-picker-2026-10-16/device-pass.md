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
