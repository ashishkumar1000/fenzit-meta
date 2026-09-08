---
title: 'Frontend — AddressPickerSheet scrollable suggestion list'
type: 'followup'
created: '2026-09-09'
status: 'backlog'
origin: 'deferred-work.md — code review (2026-09-08), AddressPickerSheet follow-up item'
context: []
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** `AddressPickerSheet` renders its suggestion list as a plain `.map()` into a `View` — there is no `ScrollView`/`FlatList`, so a long result list overflows the bottom sheet with no way to scroll. This was a deliberate, accepted trade-off made live during Story 1.5: `react-native-true-sheet`'s `scrollable` prop was found to leave real, successfully-fetched results invisible on-device (see the doc comment on `AddressPickerSheet.tsx` and the git history around it). The accepted stop-gap ships, but the real fix has had no tracked follow-up until this file.

**Approach (when picked up):** Re-evaluate `react-native-true-sheet`'s `scrollable` binding against the then-current library version (check the upstream issue tracker first — if the invisibility bug is fixed upstream, the fix is likely a one-liner restoring `scrollable`). If still broken upstream, evaluate alternatives in this order:

1. A plain `ScrollView` with `nestedScrollEnabled` inside the sheet (works on Android; verify iOS sheet-gesture interplay on-device).
2. A bounded-height `FlatList` (virtualization matters only if suggestion lists get long; autosuggest is capped small, so `ScrollView` is probably sufficient).
3. Cap visible rows + an in-sheet "see more" affordance (worst case — changes UX).

**Ask First:** Any change to the sheet's scroll/gesture behaviour must be smoke-tested on a real device (the original `scrollable` failure was only visible on-device, never in the simulator).

**Never:** Do not silently re-add `scrollable` without the on-device check — that is the exact regression this follow-up exists to prevent.

## Acceptance

- A suggestion list taller than the sheet's content area is fully scrollable inside the sheet.
- All 8 address-picker phases still render correctly inside the sheet (especially resolve-failed banner over an intact list).
- On-device smoke test passes: iOS sheet drag-to-dismiss does not swallow list scrolls and vice versa; results remain visible with `scrollable`-equivalent behaviour enabled.

</frozen-after-approval>

## Notes

- Blocked on: react-native-true-sheet upstream resolution (or a decision to switch sheet libraries).
- Related: `spec-1-5-frontend-return-selection-to-add-customer-bottomsheet.md` (where the trade-off was accepted), `src/features/addressPicker/AddressPickerSheet.tsx` (doc comment documents the original on-device finding).
