# UX spec — Map pin picker redesign (services-off + pinned states)

Date: 2026-10-18 · Author: Sally (BMAD UX) · Source: user's two mockups (services-off, pinned) + on-device current state
Approved by user (2026-10-18): top-bar search with sheet-on-focus · UX-corrected copy · office stepper stays in sheet · feature commit 49c2f08 is the baseline.

## What does NOT change (the contract underneath)

The four-state model, its wiring, and all behavioral tests: probe-first services check, remediation ladder (Android dialog → guarded intent → app settings; iOS openSettings), mount/foreground re-probe, auto re-locate on dialog success, verify-step blocking, copy semantics. This is a presentation-layer redesign of `MapPinPickerScreen` + `PickerMapArea` + `PickerBottomCard` only. `useLocateMe` / `deviceLocation` / tests' behavioral assertions stay.

## State A — services OFF (customer + office)

Bottom sheet, top to bottom:
1. **Warning card** (amber = `colors.status.scheduled` family): icon chip (location-off glyph, amber) + bold title **"Device location is turned off"** + body **"Turn on location in Settings so we can detect accurate doorstep coordinates."** (UX-corrected per research — never say "permission" here.)
2. **Approx. Area row**: pin glyph + `Approx. Area: <reverse geocode of current pin>` (muted) + blue **Change** link → focuses map for manual drag (dismisses nothing; simply a hint action — scrolls map/center visible). Reverse geocode runs on drag-settle even with services off (manual placement stays fully functional).
3. **Primary button** (full width, blue, crosshair glyph): **"Turn on device location"** → existing `enableServices` ladder.
4. **Secondary button** (full width, light/outline): **"Search or enter address manually"** → opens the existing AddressPickerSheet (decision: sheet-on-focus).
No generic error row in this state. Confirm stays available (manual placement never locked out).

## State B — pinned / healthy (customer + office)

1. **Status row**: green chip **"✓ PINNED LOCATION"** (success tokens) + right-aligned muted **"Drag map to refine"**.
2. **Address card**: leading building/glyph chip + **bold primary name** (first line of reverse geocode) + remaining address lines (muted, 2 lines max) + blue **Change** link (opens search sheet).
3. **Confirm button**: **"Confirm location →"** (arrow glyph).

## Map surface (both states)

1. **Search bar**: top of map, full-width rounded field (magnifier glyph, placeholder "Search address, street, landmark…", explicit **Search** chip button). Focus/submit → open AddressPickerSheet (existing). Keep the current floating "Search address" pill? No — replaced by the top bar.
2. **State chip over the pin**: services off → amber-tinted dark chip **"⚠ Drag map to set manually"**; pinned/healthy → dark chip **"● Exact pin location"** (green dot). Chip sits above the center pin; auto-hides while dragging, reappears on settle.
3. **Pin**: healthy = existing teardrop center pin. Services-off = crosshair "you-are-here" puck (ring + center dot + ground shadow) to signal drag-to-set semantics. Swap is state-driven, animated 150ms.
4. **Use my current location**: floating white pill, bottom-right above the sheet, crosshair glyph + label — same handler (`handleLocate`). **Hidden entirely in the services-off state** (user decision 2026-10-18: it cannot produce a fix, so it must not invite a dead tap); visible only in the pinned/healthy state.

## Office mode only

Geofence **RadiusStepper stays in the sheet**, between the address/pin area and Confirm (its current position), above the buttons. "GPS Verified" chip behavior unchanged.

## Errors (transient)

Generic failure/timeout row keeps today's pattern (plain error text + ghost [Open settings] after 2 denials) beneath the address row — restyled to match the new card spacing only. It must remain visually distinct from the amber services-off card.

## Header (customer + office)

Back chevron unchanged. The mockup's circular "?" help button: **deferred** (start simple — no target screen exists; revisit later).

## Accessibility

All new interactive elements get accessibilityRole/labels; the services-off card announcement reuses the existing AccessibilityInfo pattern (announce on state change). Touch targets ≥ 44px. Amber/success pairings from theme tokens only — no new colors.

## Live-session addendum (2026-10-18, user decisions during device review — override the sections above where they differ)

1. **"Use my current location" pill is HIDDEN in the services-off state** (it cannot produce a fix; no dead taps). Returns in the pinned state.
2. **No "Search or enter address manually" button** — the top search bar owns manual search.
3. **Beacon/ripple** on the puck dot (services-off): two staggered expanding-fading rings, ~2s loop, primary color, stops on unmount.
4. **Button hierarchy (state-based):** services-off → "Turn on device location" = solid primary, "Confirm location" = outline/secondary; healthy → Confirm = solid primary. One solid primary per state.
5. **Card color = RED (cancelled family), not amber** — the owner saw the strengthened amber live and chose red: services-off must read as "not good". Amber was the research recommendation; the owner's call overrides it (logged: NN/g amber-vs-red semantics acknowledged and consciously overruled).
6. Copy stays UX-corrected ("Turn on location in Settings…", never "permission").
