---
name: Fenzit — Address Autosuggest
description: Behavioral companion to DESIGN.md — how the address search screen and the technician maps affordance actually work.
status: final
created: '2026-09-05'
updated: '2026-09-05'
sources:
  - artifacts/planning-artifacts/architecture/architecture-address-autosuggest-2026-09-05/ARCHITECTURE-SPINE.md
  - artifacts/planning-artifacts/epics.md
  - workspace/core/frontend/fenzo-app/src/theme/DESIGN_SYSTEM.md
  - workspace/core/frontend/fenzo-app/src/components/TechnicianPicker.tsx (precedent for empty-vs-no-match, row selection)
  - workspace/core/frontend/fenzo-app/src/utils/linking.ts (existing openMaps affordance, FR10)
  - "Baymard Institute, Autocomplete Design (baymard.com/blog/autocomplete-design) — mobile suggestion-count and chrome-minimization research"
---

## Foundation

**Form factor:** mobile only — React Native, iOS + Android, phone-first (matches the rest of Fenzit; no tablet/web surface for this feature). **UI system:** the existing Fenzit Design System (`fenzo-app/src/theme`, `src/components/ui`) — see the companion `DESIGN.md` for the three new component deltas this feature adds. **Navigation:** React Navigation native-stack, pushed as a new route (already fixed by architecture AD-8, not a UX decision) — not a sheet, not a modal.

## Information Architecture

One new screen: **`AddressPickerScreen`**, pushed on top of whichever screen currently hosts an open `AddCustomerSheet` (`CustomersScreen` or `NewJobScreen`). No new tab, no new stack root — it's a leaf screen reached only from the bottomsheet's address field, and it only ever returns to where it came from (back gesture or a completed selection, never a deep link elsewhere).

One existing screen gets a small behavioral upgrade, no new IA: `TechJobDetailContent`'s customer address row (FR10) — same screen, same position, smarter underlying deep link.

## Voice and Tone

Sentence case throughout, plain English, no jargon — matching the rest of the app's voice ("you", direct, warm).

| Moment | Copy |
| --- | --- |
| Screen title | "Search address" |
| Search input placeholder | "Search for an address" |
| Below-threshold hint (1–2 chars typed) | "Keep typing to search" |
| No results | "No addresses found for “{query}”." |
| No-results action | "Enter address manually" |
| Network/provider error | "Couldn't load suggestions. Check your connection." |
| Error action | "Retry" |
| Resolve failure (after tapping a row) | "Couldn't get that address. Try again." |

No copy is shown at zero characters typed — the screen opens quiet, keyboard already up, nothing to react to yet.

## Component Patterns

**`search-header`** — the existing screen-header row, reused verbatim (`IconButton` back chevron + `SafeAreaView`/`StatusBar` per `CustomerDetailScreen`/`TechJobDetailScreen`), with the title slot swapped for the existing `Input`. Auto-focuses on mount (`Sheet`'s own `onDidPresent`-timing lesson applies here too: focus after the screen has actually finished presenting, not synchronously on mount, to avoid the same class of bug `Sheet` already documents avoiding with `autoFocus`). Back chevron always active, always returns with no `pendingAddress` (identical to a no-op cancel, whether pressed after zero or many characters typed).

**`suggestion-row`** — `TechnicianPicker`'s existing "rows" variant, reused verbatim (bordered card, `Pressable`, `accessibilityRole="button"`), with its `Avatar` slot swapped for `MapPin` and its trailing `checkCircle` swapped for an activity spinner while resolving. `accessibilityLabel` = the row's full formatted address text (not just the short name — a screen reader user needs the disambiguating detail sighted users get from the secondary line). Disabled (not just visually, but to touch input) from the moment it's pressed until its resolve call settles, one row at a time — selecting a different row while one is resolving isn't offered as an interaction (there's only ever one in-flight resolve, matching the single-session-token model in AD-3).

**`EmptyState` / `InlineError`** — both reused verbatim from `components/ui`, no new container. `EmptyState` replaces the list area entirely for no-results and full-blocking-error states (nothing to show underneath it). `InlineError` appears below an intact, still-interactive list for a resolve failure — it never replaces the list, per its own documented contract.

## State Patterns

The screen has exactly these states, in this order of precedence (a later state in this list always wins if somehow two conditions are simultaneously true):

1. **Idle** (0 chars) — blank list area, no message, keyboard up.
2. **Below threshold** (1–2 chars) — "Keep typing to search" hint, no network call fired yet (this is the client-side debounce/min-length gate, AD-6 — it is a UX-visible state, not just an invisible cost optimization).
3. **Loading** (≥3 chars, debounce settled, autosuggest call in flight) — small spinner in the search input's trailing slot; the *previous* result list (if any) stays visible and dimmed slightly rather than being cleared and replaced with a blank screen — avoids a jarring flash on every keystroke-triggered refetch. Baymard's out-of-order-response caution applies: a response for a stale query (superseded by further typing before it returned) is discarded, never rendered, even if it arrives after a newer request's response.
4. **Results** — the suggestion list, up to what the backend returns (no client-side truncation beyond what the backend's `autosuggest` response already contains).
5. **No results** — `EmptyState` (icon: `Search`, title "No addresses found", description names the query, `ctaVariant="secondary"` `ctaLabel="Enter manually"` → back-navigates), shown only once the in-flight request for the *current* text has actually settled empty (never shown speculatively while still loading).
6. **Error** (nothing loaded at all) — `EmptyState` (icon: `AlertTriangle`, title "Couldn't load suggestions", description "Check your connection.", `ctaVariant="primary"` `ctaLabel="Retry"`) — covers both a network failure and a `502 PLACES_UPSTREAM_ERROR`/`429 RATE_LIMITED` from the backend before any results exist. Copy doesn't distinguish the cause (the user can't act differently on any of them).
7. **Resolving** (a row was tapped) — the tapped row shows its spinner, all rows disabled, search input disabled too (no point letting someone start a new search while a selection is being confirmed). This is the one state where the *whole* screen, not just a row, goes briefly non-interactive.
8. **Resolve failed** — the tapped row's spinner is replaced with nothing (row returns to idle); `InlineError` appears below the still-intact list ("Couldn't get that address. Try again.") without clearing the results — the user can tap the same row again or a different one, matching `InlineError`'s existing "screen keeps its data" contract.

## Interaction Primitives

- Debounce: ~300ms after the last keystroke (AD-6's number; this is where it becomes visible as the gap between typing stopping and the Loading state appearing).
- Minimum length: 3 characters (AD-6) — below this, no network call, ever, regardless of how long the user pauses.
- Back gesture (iOS swipe-back, Android hardware/gesture back) behaves identically to the header's back chevron — always a no-op cancel back to the bottomsheet, never intercepted or confirmed ("are you sure?" is not needed here — nothing destructive happens by leaving).
- Selecting a row is the only way forward; there is no "confirm" step after tapping a suggestion (tap = commit to resolving that address) — matches the single-tap-selects pattern already established by `TechnicianPicker`.
- List scrolling: standard native scroll, no pull-to-refresh (there's nothing to refresh — a new query is a new debounce cycle, not a manual refresh gesture).

## Accessibility Floor

- All interactive elements meet the 44px floor (`touch.min`); the search input and rows exceed it (48px / 56px respectively) per DESIGN.md.
- Screen reader: on entering the Results state, announce the count ("5 addresses found") via an accessibility live region on the list container, mirroring how a screen-reader user would otherwise have to guess whether the list changed after typing.
- Dynamic type: primary/secondary suggestion text and all status copy must reflow (not truncate to illegibility) under the largest standard accessibility text size — `numberOfLines` limits are for visual scanability at default sizes, not a hard accessibility ceiling.
- Color is never the only signal: the error state pairs `{colors.danger}` text with the word "error"-equivalent copy ("Couldn't load..."), never a bare red dot or icon alone.

## Key Flows

### Flow 1 — Ramesh adds a new customer on-site
Ramesh runs a pest-control business in Andheri West. A new customer calls while he's at the shop; he opens the app, taps "+ Add" on Customers, fills in the name and phone, then taps "Address / map location." The full-screen search opens with the keyboard already up. He types "andheri w" — at 3 characters the list starts filling in behind a brief spinner; by "andheri wes" three real addresses are showing. He taps the second one, "Andheri West, Mumbai" — the row shows a brief spinner (his connection is patchy, this takes a second and a half) — then the screen pops him straight back to the bottomsheet, where the address field now reads the full formatted address and City/Area have filled in "Mumbai" / "Andheri West." He notices the field visibly changed (**climax beat**: the soft border pulse on return catches his eye even though he wasn't staring at that field) — he taps in and adds a landmark by hand ("near Metro station, 2nd floor"), then taps "Add customer."

### Flow 2 — No signal, no problem
Priya is adding a customer in a basement service area with no signal. She taps the address field, types "12 mg road" — after the debounce, nothing loads; after a few seconds the screen shows "Couldn't load suggestions. Check your connection." with Retry. She doesn't retry — she taps the back chevron, and the bottomsheet's address field is exactly as she left it (empty). She types the address by hand instead and finishes adding the customer with no coordinates saved — the customer is created successfully either way (NFR4: the Places flow is never mandatory).

### Flow 3 — A technician navigates precisely
Karan is dispatched to a job and opens the job detail screen. Under "Customer," he sees the address row exactly as it's always looked — pin icon, address text, navigation icon — and taps it. Because this customer's address was added through the new picker, the app opens his maps app centered on the exact saved coordinates rather than guessing from the text string; he gets turn-by-turn directions straight to the building rather than to the nearest text-match. For an older customer added before this feature shipped (no saved coordinates), the same row looks and behaves identically, just falling back to the original text-search deep link — Karan can't tell the difference from the UI, and doesn't need to.

## Responsive & Platform

- iOS: swipe-back gesture enabled (nothing on this screen needs to block it). Keyboard avoidance matches `AddCustomerSheet`'s existing `keyboardShouldPersistTaps="handled"` convention so a tap on a suggestion row while the keyboard is up registers on the first tap, not a dismiss-then-retap.
- Android: hardware/gesture back behaves identically to iOS swipe-back and the header chevron (see Interaction Primitives) — no custom `BackHandler` override needed beyond what React Navigation already provides for a pushed screen.
- No landscape-specific layout — phone portrait only, matching the rest of the app.

## Open Questions

- **"Use my current location" quick-add** at the top of the results list (GPS + reverse geocode) is a well-established pattern in comparable apps and would help an owner adding a walk-in customer's own location, but requires a geolocation-permission flow that isn't in the architecture spine. Deferred — flagging for a product decision, not designed here.
- **Highlighting the matched portion** of each suggestion's text (a Baymard-recommended pattern) depends on whether Google's Autocomplete response actually carries match-offset data within the fields the architecture spine's contract requests — not confirmed. Deferred as a visual enhancement, not blocking.
- **App backgrounded mid-resolve**: what happens if the user leaves the app between tapping a suggestion and the resolve call returning — resume silently, drop the selection, or surface a stale-error on return? Not specified; flagging as an edge case for implementation-time decision.
