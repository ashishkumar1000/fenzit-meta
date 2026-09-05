---
name: Fenzit — Address Autosuggest
description: Full-screen address search/picker for Add Customer, plus a minor polish on the technician job-detail maps affordance. Inherits 100% from the existing Fenzit Design System (fenzo-app/src/theme, src/components/ui) — reuses EmptyState, InlineError, IconButton, Input, and TechnicianPicker's row-card style verbatim; introduces no new visual components.
status: final
created: '2026-09-05'
updated: '2026-09-05'
colors:
  primary: '#1A56DB'
  surface-page: '#F9FAFB'
  surface-card: '#FFFFFF'
  text-strong: '#111827'
  text-muted: '#6B7280'
  border-subtle: '#E5E7EB'
  danger: '#C92A2A'
typography:
  body:
    note: 'Fenzit typography.body — 16px, never smaller on inputs (iOS zoom guard)'
  body-sm:
    note: 'Fenzit typography.bodySm — secondary/meta lines'
  label:
    note: 'Fenzit typography.label — field labels, section titles'
  caption:
    note: 'Fenzit typography.caption — helper/status text under the search input'
rounded:
  md: 10px
  lg: 14px
  pill: 9999px
spacing:
  '2': 8px
  '3': 12px
  '4': 16px
components:
  search-header:
    reuses: 'the existing screen-header row (SafeAreaView edges=[top] + StatusBar dark-content + IconButton variant=ghost size=md wrapping ChevronLeft) verbatim from CustomerDetailScreen.tsx / TechJobDetailScreen.tsx — no new header shape'
    delta: 'the header row''s title-Text slot is replaced with the existing Input component (leadingIcon Search 18px {colors.text-muted}) instead of a static title — the only new thing is which content fills that slot'
    input-trailing: 'the existing Input''s trailing slot holds a clear (X) affordance when text is present, or a small activity indicator while a request for the current text is in flight'
  suggestion-row:
    reuses: 'TechnicianPicker''s existing "rows" variant card style verbatim (listRow style: borderWidth 1 {colors.border-subtle}, {rounded.lg}, {colors.surface-card} background, {spacing.2} gap between rows) — this app has no full-bleed/hairline list anywhere, so this screen does not invent one'
    leading-icon: 'MapPin, 18px, {colors.text-muted} (replaces TechnicianPicker''s Avatar slot, which doesn''t apply to an address)'
    primary-text: 'label role, {colors.text-strong}, numberOfLines=1 (matches TechnicianPicker''s listName)'
    secondary-text: 'caption role, {colors.text-muted}, numberOfLines=1 (matches TechnicianPicker''s listSkills)'
    trailing-state: 'TechnicianPicker''s trailing checkCircle slot is replaced with nothing (idle) or a small activity spinner (resolving) — this screen has no persistent multi-select, so no check mark is ever shown'
    pressed-state: 'identical to TechnicianPicker''s listRowSelected tint, applied only for the press-duration (no lingering selected state once the screen navigates away)'
  no-content-state:
    reuses: 'the existing EmptyState component (components/ui/EmptyState.tsx) verbatim — the same one used by the Technicians/Jobs/Customers zero-data screens and CustomerDetailScreen''s not-found view'
    usage: 'no-results (icon: Search, ctaVariant=secondary, ctaLabel="Enter manually") and full-blocking network/provider error (icon: AlertTriangle or CloudOff, ctaVariant=primary, ctaLabel="Retry") — both are "nothing to show" states per EmptyState''s existing role'
  resolve-failure-banner:
    reuses: 'the existing InlineError component (components/ui/InlineError.tsx) verbatim — a failure while usable content (the suggestion list) is still on screen, exactly the case its own docstring describes'
    usage: 'appears below the list when a tapped row''s resolve call fails; the list stays intact and interactive, matching InlineError''s "screen keeps its data" contract'
---

## Brand & Style

This is a transactional utility screen, not a marketing surface — the same posture the rest of Fenzit already takes toward the "Add customer" bottomsheet it extends. Nothing here should compete for attention with the task: find the address, pick it, get back to the form. No illustrations, no empty-state artwork, no celebratory motion on selection. The screen earns trust by being fast, quiet, and honest about its own limits (it says plainly when it can't find something, and never blocks the person from typing the address themselves).

## Colors

All colors are the existing Fenzit palette, restated here only for the new components' sake — no new hues introduced.

- **Primary (`#1A56DB`)** — the back chevron's implicit tap affordance color is neutral (text-strong), but primary is reserved for the "Enter address manually" action link and any future primary action on this screen, exactly as it's reserved for actions elsewhere in the app.
- **Text Muted (`#6B7280`)** — secondary suggestion lines, the search icon, and neutral status copy ("Type at least 3 characters to search").
- **Danger (`#C92A2A`)** — only for the resolve-failure and network-error inline messages. Never for the plain "no results" state, which is a neutral outcome, not a failure.

## Typography

No new type roles. `label` for primary suggestion text and the action link, `caption` for secondary suggestion text and status copy, `body` for the search input itself (16px floor is non-negotiable — this is a text input, and the existing iOS-zoom guard applies here exactly as it does in `AddCustomerSheet`).

## Layout & Spacing

Rows keep `TechnicianPicker`'s existing rhythm: `{spacing.2}` gap between cards, `{spacing.3}`/`{spacing.4}` internal padding — no new spacing scale introduced. Search input sits in the existing header row with `{spacing.4}` horizontal padding, matching every other screen's gutter.

## Elevation & Depth

Flat, matching the rest of the app — suggestion rows carry the same 1px hairline border `TechnicianPicker`'s rows already use, no added shadow. No new elevation language.

## Shapes

The search input uses `{rounded.md}` (10px), identical to every other `Input` in the app. Suggestion rows use `{rounded.lg}` (14px), identical to `TechnicianPicker`'s existing row cards — not a new radius choice.

## Components

### `search-header`
Not a new header — the exact existing screen-header row (`SafeAreaView edges={['top']}`, `StatusBar barStyle="dark-content"`, `IconButton variant="ghost" size="md"` wrapping `ChevronLeft size={22} color={colors.textStrong} strokeWidth={2}`) copied verbatim from `CustomerDetailScreen.tsx`/`TechJobDetailScreen.tsx`. The only change: where those screens put a static title `Text`, this screen puts the existing `Input` component (auto-focused on mount, `leadingIcon={<Search />}`). The input's trailing slot holds a clear (×) affordance once text is present, or a small activity indicator while a request for the current text is in flight.

### `suggestion-row`
Not a new row style — `TechnicianPicker`'s existing "rows" variant card (`borderWidth: 1`, `{colors.border-subtle}`, `{rounded.lg}`, `{colors.surface-card}` background) with its `Avatar` slot swapped for a `MapPin` icon (an address has no avatar) and its trailing `checkCircle` swapped for either nothing (idle) or a small activity spinner (resolving) — this screen has no persistent multi-select, so no check mark is ever shown. Two lines of text (primary = short/main text, secondary = the fuller address) exactly as `TechnicianPicker`'s rows already show name + skills. Tapping a row disables the whole row's `Pressable` until its resolve call settles, preventing a double-tap from firing two resolves.

### `no-content-state` and `resolve-failure-banner`
No new components — `EmptyState` (`components/ui/EmptyState.tsx`) covers no-results and full-blocking errors (nothing to show), exactly as it already does for the Technicians/Jobs/Customers zero-data screens and `CustomerDetailScreen`'s not-found view. `InlineError` (`components/ui/InlineError.tsx`) covers a resolve failure while the suggestion list is still visible, exactly matching its own documented purpose.

## Do's and Don'ts

- **Do** reuse `EmptyState`, `InlineError`, `IconButton`, `Input`, and `TechnicianPicker`'s row card styling exactly as they already exist elsewhere in the app — this screen introduces no new visual components, only new content inside existing ones.
- **Do** keep the search input auto-focused and the keyboard up for the entire session on this screen — there is no other input to fill.
- **Do** disable a suggestion row the instant it's tapped, until its resolve call settles — prevents duplicate resolve calls from a double-tap and gives honest feedback that something is happening (resolve is a real network round-trip, not instant).
- **Do** let "Enter address manually" and the back gesture both simply return to the bottomsheet with nothing changed — never invent a fake selection to satisfy a state machine.
- **Don't** add a "precise location" vs. "approximate" badge to the technician's existing maps row (FR10) — the affordance's promise doesn't change, only its accuracy under the hood; a badge would be noise for a distinction the technician can't act on.
- **Don't** show a loading spinner or skeleton for the *list* before 3 characters are typed — there's nothing to load yet; showing motion for no reason contradicts the "quick and functional, never showy" motion rule.
- **Don't** invent a full-bleed/hairline-divider list — this app has no such pattern anywhere; `TechnicianPicker`'s bordered row cards are the established density for a scannable list.
