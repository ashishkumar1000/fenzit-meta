# Story 11.7: New Job customer section redesign — mirror the skill section

Status: done
baseline_commit: b34f17a (fenzo-app)

## Story

As an owner creating a job,
I want the Customer section to look and behave like the Skill section (tiles, search, Browse all),
so that picking a customer is as fast and familiar as picking a skill.

## Acceptance Criteria

1. **Customer section on New Job mirrors the Skill section** — the `Select`
   dropdown is replaced by a `CustomerPicker` section with:
   - a header row: inline "Customer" title + count chip ("N customers", same
     pill treatment as SkillPicker's "N available") + "Browse all" link
     (`ChevronRight`, primary) that pushes `SelectCustomers`;
   - a search `Input` (leading `Search` icon) that filters the whole customer
     store **client-side** via the existing `filterCustomers` helper (name OR
     phone digits — same semantics as the Customers tab);
   - a 3-column tile grid showing the **first 3** customers (most-recent-first,
     AC 4) plus a **"+N More customers"** tile that also opens `SelectCustomers`;
   - selected-tile styling identical to the SkillPicker follow-up restyle
     (11-5): `primarySoft` background, primary border, primary label, solid
     primary check badge in the corner.
2. **Selected-customer pinning** — if the selection is outside the first 3
   (via Browse all or search), it is pinned to the front of the idle grid, so
   the default surface always shows what the job is for.
3. **Dedicated `SelectCustomersScreen`** (route `SelectCustomers`) mirroring
   `SelectSkillsScreen`:
   - header ("Select customers" title + back), subheader with count chip
     ("N total") and a "Clear" action (disabled when nothing pending);
   - search field filtering client-side via `filterCustomers`;
   - single-select rows: `Avatar` (customer name) + name + `customerLocation`
     (city · address) + `customerPhone` + 26px circle toggle; tapping a row
     replaces the pending selection;
   - sticky "Apply selection" footer button, disabled until a row is picked;
     Apply returns via `navigation.popTo('NewJob', { selectedCustomerId },
     { merge: true })`; Clear returns with `{ selectedCustomerId: null }`
     immediately;
   - loading / error / empty states copied from `SelectSkillsScreen` (spinner
     on first load, error + "Try again", distinct empty-catalog vs
     no-search-match copy).
4. **Tile order = most recent first** — tile candidates sort by `lastJobDate`
   descending (nulls last), ties and all-null lists fall back to name A→Z.
   Sorting is a pure helper (`sortCustomersByRecency` in
   `src/features/customers/format.ts`, exported from the customers barrel);
   the Customers tab and the picker page keep the store's order — only the
   tiles are reordered.
5. **"Add new" link kept** — the "Customer not in list? Add new" row stays
   under the picker (same `handleAddCustomer` → `AddCustomer` with
   `returnRouteName: 'NewJob'` → `createdCustomerId` consumed as today).
6. **Degraded states mirror the skills section** (`renderCustomers()` in
   NewJobScreen): spinner while first load is in flight; error + "Try again"
   button when the store failed with nothing to show; "No customers yet"
   status (the Add-new link is the way forward) when loaded and empty; stale
   rows stay usable on a failed refresh.
7. **Selection return consumed correctly** — NewJobScreen's `useEffect` reads
   `route.params?.selectedCustomerId`: a string patches `draft.customerId`,
   `null` clears it (section shows placeholder state), `undefined` is a
   no-op; the param is cleared with `navigation.setParams({
   selectedCustomerId: undefined })` after consumption.
8. **No backend change** — everything reads the shared `useCustomers` store
   (`GET /customers` via `listAll`); no service or endpoint work in this
   story.
9. **Progressive disclosure untouched** — the Customer section still appears
   only after a skill is picked; skill→technician filtering unchanged.
10. **Tests**: existing tests are updated only as needed to keep the suite
    green under the new UI; comprehensive new tests are written **after the
    user confirms the feature on device** (test-timing rule — never with the
    feature).

## Tasks / Subtasks

- [x] Task 1: `sortCustomersByRecency` helper (AC: 4)
  - [x] Add to `src/features/customers/format.ts`: pure sort — `lastJobDate`
        desc (nulls last), then `name` locale-compare A→Z; export from the
        customers barrel.
- [x] Task 2: `CustomerPicker` component (AC: 1, 2)
  - [x] New file `src/features/newJob/components/CustomerPicker.tsx`, modeled
        on `SkillPicker.tsx` (same header/count-chip/search/grid/check-badge
        structure and styles; `VISIBLE_TILES = 3`).
  - [x] Tiles: avatar-initials chip (reuse DS `Avatar`) + name (2 lines) +
        check badge; "+N More customers" tile opens Browse all; selected
        styling = `primarySoft` bg + primary border + check badge.
  - [x] Search filters via `filterCustomers(options, query)`; empty-match copy
        `No customers match "…"`; selection pinned to front when outside the
        first 3.
- [x] Task 3: `SelectCustomersScreen` (AC: 3)
  - [x] New file `src/features/newJob/SelectCustomersScreen.tsx`, modeled on
        `SelectSkillsScreen.tsx` (pendingId state, Apply/Clear `popTo` with
        `{ merge: true }`, KeyboardAvoidingView footer, identical status
        states).
  - [x] Rows read the shared `useCustomers` store; row = `Avatar` + name +
        `customerLocation` + `customerPhone` + circle toggle.
- [x] Task 4: Navigation wiring (AC: 3, 7)
  - [x] `src/navigation/types.ts`: add `SelectCustomers:
        { selectedCustomerId?: string | null } | undefined` and extend
        `NewJob` params with `selectedCustomerId?: string | null`.
  - [x] `RootNavigator.tsx`: register `SelectCustomers` (headerShown false).
  - [x] `src/features/newJob/index.ts`: export `SelectCustomersScreen`.
- [x] Task 5: `NewJobScreen` rework (AC: 1, 5, 6, 7, 9)
  - [x] Replace the `Select` + placeholder/helper block with
        `renderCustomers()` (spinner / error+retry / empty / picker) and the
        `CustomerPicker`; keep the Add-new row and `handleAddCustomer`.
  - [x] Add the `selectedCustomerId` consume-and-clear `useEffect` (mirror the
        `selectedSkillId` one).
  - [x] Remove the now-dead `customerOptions` memo, `customerPlaceholder` /
        `customerHelper`, and the `Select` import if unused.
  - [x] Keep `serviceLocation` derivation and the customers retry button
        behavior (folded into the new degraded states).
- [x] Task 6: Existing-test maintenance (AC: 10) — update
    `NewJobScreen.test.tsx` (and any test asserting the customer `Select`)
    minimally so the suite passes; no new test cases yet.
- [x] Task 7: Docs — update the New Job screen doc-comment block; no other
    docs describe this section (small-modular-code rule: docs in the same
    change).

### Review Findings

BMAD code review 2026-09-20 (4 layers: blind-hunter, edge-case-hunter,
verification-gap, acceptance-auditor). 13 findings dismissed after code
verification (by-design mirrors of the skills twin, unreachable store
states, pre-launch edge cases); 10 patches applied:

- [x] [Review][Patch] Stale "first three" comment in CustomerPicker contradicts VISIBLE_TILES = 5 [src/features/newJob/components/CustomerPicker.tsx:67]
- [x] [Review][Patch] `selectedCustomerId` effect comment references a "placeholder" that no longer exists [src/features/newJob/NewJobScreen.tsx:141]
- [x] [Review][Patch] Count chip reads "1 customers" — no singular handling [src/features/newJob/components/CustomerPicker.tsx:90]
- [x] [Review][Patch] Empty-book copy points at an indirect, differently-worded path; align with NewJobScreen's own empty copy [src/features/newJob/SelectCustomersScreen.tsx:198]
- [x] [Review][Patch] Missing trailing newline in 5 new/changed files
- [x] [Review][Patch] Misindented line in CustomerPicker.test.tsx header comment [src/features/newJob/components/CustomerPicker.test.tsx:12]
- [x] [Review][Patch] NewJobScreen.test.tsx customers mock hand-reimplements `filterCustomers`/`sortCustomersByRecency` instead of `jest.requireActual` [src/features/newJob/NewJobScreen.test.tsx:53]
- [x] [Review][Patch] Missing test: customer round trip in NewJobScreen (Browse-all carries `draft.customerId`; Apply applies the returned id and clears the param; Clear drops the customer) [src/features/newJob/NewJobScreen.test.tsx]
- [x] [Review][Patch] Missing test: customer section loading / error / empty states in NewJobScreen (the skills section's equivalents are tested) [src/features/newJob/NewJobScreen.test.tsx]
- [x] [Review][Patch] Missing test: SelectCustomersScreen first-load spinner and empty-address-book copy [src/features/newJob/SelectCustomersScreen.test.tsx]

## Dev Notes

### The pattern being copied (read these two files first)

- `src/features/newJob/components/SkillPicker.tsx` — presentational picker:
  header row (inline title + `radius.pill` count chip on `surfaceSunken` +
  "Browse all" `Pressable`), search `Input` with `leadingIcon`, 3-column tile
  grid (`onLayout`-measured row width, gap `spacing.s3`), `tile` styles
  (minHeight 84, `borderSubtle` on `surfaceCard`, `radius.lg`), selected tile
  (`primarySoft` bg, primary border 1.5), `iconChip` (40×40, `surfaceSunken`,
  selected = `palette.blue100`), `checkBadge` (18×18 primary circle with 12px
  `Check`), `tileMore` ("+N" in `typography.heading` + label on
  `surfaceSunken`), `noMatch` copy.
- `src/features/newJob/SelectSkillsScreen.tsx` — full-screen browser:
  `SafeAreaView edges={['top']}`, header (back `ArrowLeft` + title), subheader
  (count chip "N total" + disabled-able "Clear"), subtitle, search, FlatList
  rows (44×44 icon chip, name, description, 26px circle toggle),
  `KeyboardAvoidingView` + sticky footer `Button` (disabled until pending),
  and the two `popTo('NewJob', …, { merge: true })` calls — **Apply sends the
  pending id, Clear sends `null` immediately** (comment explains why: "no
  skill" is a decision too).

### What changes vs what must be preserved (NewJobScreen.tsx)

Current state: Customer section = `SectionHead title="Customer"` + `Select`
(options from `customerOptions` memo, placeholder/helper degrade copy,
`disabled` on zero options, `sheetTitle`) + Add-new link + error retry.
The param plumbing to preserve exactly:
- `createdCustomerId` consume-and-clear `useEffect` (lines ~117–122) —
  unchanged.
- `handleAddCustomer` → `navigation.navigate('AddCustomer',
  { returnRouteName: 'NewJob' })` — unchanged; `AddCustomerScreen` already
  `upsertCustomer(created)` + `popTo('NewJob', { createdCustomerId }, {
  merge: true })`, so a fresh customer is immediately selectable in the store.
- `serviceLocation` memo (address + city of the selected customer) —
  unchanged; still drives `POST /jobs`.
- Progressive disclosure gate (`draft.skillId ?`) and skill/technician logic
  — untouched.

What to remove: the `customerOptions` memo, `customerPlaceholder` /
`customerHelper`, the `Select` JSX block and its import (and `UserPlus`-less
imports as needed). The degraded-state copy moves into `renderCustomers()`
mirroring `renderSkills()`: `customersLoading && customers.length === 0` →
spinner; `customersError && length === 0` → message + Try again
(`refreshCustomers`); `customersLoaded && length === 0` → "No customers yet"
copy (Add-new is the CTA); else the picker. Stale rows on a failed refresh
stay on screen (store retains them by design).

### Reuse — do NOT reinvent

- `filterCustomers` (customers/format.ts) — the section search AND the picker
  page search both use it (name OR digit-substring phone; mirrors backend
  `q`). Do not write a new filter.
- `customerLocation`, `customerPhone` (customers/format.ts) — row meta.
- `Avatar` (components/ui) — tile chip and picker row.
- `useCustomers` store — both screens subscribe; `loadCustomers` is
  join/throttle-safe, so no extra GET. NewJobScreen already destructures
  `customers / isLoading / error / hasLoaded / refresh` — keep that.
- `SectionHead` for the section eyebrow stays (NewJobScreen keeps
  `<SectionHead title="Customer" />` above the picker — SkillPicker's inline
  title pattern is NOT needed here because Customer already has a SectionHead;
  pass no `title` prop, or the header shows title + chip + Browse all without
  a duplicate name).

### Navigation facts (React Navigation 7)

- Return MUST be `navigation.popTo('NewJob', { selectedCustomerId }, {
  merge: true })` — plain `navigate` pushes a duplicate screen in v7 (learned
  the hard way in 11-5; see SelectSkillsScreen file doc).
- NewJob consumes the param once, then `setParams({ selectedCustomerId:
  undefined })` — same pattern as `selectedSkillId` / `createdCustomerId`.
- Route registration order in RootNavigator is irrelevant to behavior; put
  `SelectCustomers` next to `SelectSkills` for readability.

### Data facts

- `Customer = ApiCustomer`: `{ id, name, countryCode, phoneNumber, address,
  city, jobCount, lastJobDate }`; `lastJobDate` is nullable (fresh rows via
  `upsertCustomer` default it to `null`) — the sort must tolerate nulls and
  unparseable dates (treat as null; `new Date(iso)` NaN check).
- The store holds ALL pages (`listAll`, up to 20×50) — client-side search is
  the established pattern (CustomersScreen file doc documents this as
  deliberate).
- Owner-only endpoint (technician JWT → 403); the technician surface never
  sees this section, so no new screen needs role handling.

### Project Structure Notes

- New files follow the feature convention: screens + components inside
  `src/features/newJob/`, picker presentational component in
  `components/`. Pure sort helper lives in `src/features/customers/format.ts`
  (pure functions, shared by both features' surfaces).
- Keep relative imports (whole codebase does; no alias adoption in this
  story).
- Design tokens only — no hardcoded colors/spacing; copy `SkillPicker`
  styles rather than inventing.
- File sizes stay well under the ~300-line guideline by mirroring (not
  growing) the existing patterns.

### Test timing (project rule)

Implement → **user confirms on device** → then write tests → then BMAD code
review. This story's implementation updates existing tests only to keep
`bun run test` green (fenzo-app's jest script — never bare `bun test`). New
tests (`CustomerPicker.test.tsx`, `SelectCustomersScreen.test.tsx`) come as a
follow-up after confirmation.

### Previous-story intelligence (11-5, same pattern)

- Selected-tile restyle landed as light tint + primary chip/label (NOT solid
  primary fill — it drowned icon/label). Copy the final styles from
  SkillPicker as they are today.
- `popTo` vs `navigate` regression — covered in Navigation facts above.
- Section separation: sections use DS `SectionHead` (hairline + eyebrow);
  Customer keeps its `SectionHead`, so the picker header omits the inline
  title (count chip + Browse all only) unless the dev finds the header reads
  bare — in that case pass `title` and remove the duplication consciously.
- 11-5 cutover showed DB-driven icons matter for skills; customers have no
  icon field — initials avatar is the tile identity, matching CustomerRow.

### References

- [Source: fenzo-app src/features/newJob/components/SkillPicker.tsx] — the
  pattern being mirrored (styles, header, grid, pinning).
- [Source: fenzo-app src/features/newJob/SelectSkillsScreen.tsx] — picker
  page pattern (pending state, Apply/Clear, popTo, degraded states).
- [Source: fenzo-app src/features/newJob/NewJobScreen.tsx lines 117–138,
  170–208, 334–338, 401–447, 546–578] — current customer section + param
  plumbing.
- [Source: fenzo-app src/features/customers/useCustomers.ts] — shared store;
  `upsertCustomer` null-tolerant derived fields.
- [Source: fenzo-app src/features/customers/format.ts] —
  `filterCustomers`/`customerLocation`/`customerPhone` to reuse; where
  `sortCustomersByRecency` goes.
- [Source: fenzo-app src/navigation/types.ts, RootNavigator.tsx] — route
  wiring pattern.
- [Source: fenzit-be src/customers/customers.controller.ts,
  list-customers-query.dto.ts] — `GET /customers` already supports `q` +
  cursor + limit; no BE change (context only, nothing to ship).

## Dev Agent Record

### Agent Model Used

Claude (GLM) via Claude Code, 2026-09-20

### Debug Log References

- `bun run test` — 943/944 passing; the single failure
  (`__tests__/api-client.test.ts` "pins the production endpoint") is
  pre-existing, caused by the user's uncommitted local change to
  `src/config/index.ts` (`API_HOST` → `http://192.168.1.218:3000`), not by
  this story. Left untouched.
- `bun run lint` — no ESLint configuration exists in fenzo-app; not a gate.
- `bun run tsc --noEmit` — clean.

### Completion Notes List

- Implemented exactly per the story's Dev Notes; no new dependencies.
- `sortCustomersByRecency` added to `customers/format.ts` (pure,
  non-mutating, NaN-tolerant — same comparator discipline as
  `selectTodayJobs`).
- `CustomerPicker` mirrors `SkillPicker` styles verbatim (tiles, count chip,
  check badge, "+N more"); tiles use the DS `Avatar` (initials on a
  name-derived tint) instead of the skill icon chip; the avatar tint is kept
  on selection (badge + border already mark it).
- `CustomerPicker` header omits the inline title — the Customer `SectionHead`
  eyebrow already names the section, so a title would double it (story Dev
  Notes anticipated this).
- `SelectCustomersScreen` mirrors `SelectSkillsScreen` including the React
  Navigation 7 `popTo(..., { merge: true })` return; rows keep the store's
  order (only the caller's tiles are recency-sorted).
- "Clear" on the picker page returns `selectedCustomerId: null` — a job
  cannot be submitted without a customer, so the section falls back to its
  placeholder state, same decision semantics as the skill screen's Clear.
- NewJobScreen: `selectedCustomerId` consumed-and-cleared in its own
  `useEffect`; `customerOptions`/`customerPlaceholder`/`customerHelper` and
  the `Select` import removed; `serviceLocation`, Add-new link and
  progressive disclosure untouched.
- **Tests**: existing suites updated only (mock gains
  `filterCustomers`/`sortCustomersByRecency` stand-ins + customer fixture;
  assertions moved from the old `sheetTitle: 'Customer'` probe to
  accessibility probes / a stubbed `CustomerPicker`). Per the test-timing
  rule, NO new test cases were written during implementation.
- The user's uncommitted `src/config/index.ts` change was preserved
  untouched.
- **Device-check follow-up (2026-09-20):** with `VISIBLE_TILES = 3` the
  "+N more" tile dangled alone on a second row (3 tiles + 1 more = 4 items in
  a 3-column grid). User chose the skill-grid fix: `VISIBLE_TILES = 5`, so
  the grid is always 2 complete rows — identical rhythm to SkillPicker.
- **Tests written after device confirmation (2026-09-20):** the user
  confirmed the feature on device, then the three suites were added —
  `CustomerPicker.test.tsx` (12 render/selection/search/pinning tests),
  `SelectCustomersScreen.test.tsx` (13 screen-contract tests),
  `__tests__/customers-recency.test.ts` (7 pure-sort tests). Final tally:
  981/982 passing; the single failure (`__tests__/api-client.test.ts`) is
  the pre-existing local-config one, untouched.
- **BMAD code review (2026-09-20, 4 layers):** 13 findings dismissed after
  code verification (by-design mirrors of the skills twin, unreachable store
  states, pre-launch edge cases); 10 patches applied — stale "three"
  comment, two "placeholder" comment drifts, "1 customers" singular,
  empty-book copy aligned with NewJobScreen's, trailing newlines, test
  header indent, NewJobScreen.test customers mock switched to real
  `filterCustomers`/`sortCustomersByRecency` via `jest.requireActual`, and
  the 3 verification gaps closed with new tests (customer Apply/Clear round
  trip + Browse-all handoff in NewJobScreen; customer loading/error/empty
  states; SelectCustomersScreen spinner + empty-book copy). See the Review
  Findings section above.

### File List

- src/features/customers/format.ts (modified — `sortCustomersByRecency`)
- src/features/customers/index.ts (modified — barrel export)
- src/features/newJob/components/CustomerPicker.tsx (new)
- src/features/newJob/SelectCustomersScreen.tsx (new)
- src/features/newJob/NewJobScreen.tsx (modified — section rework)
- src/features/newJob/index.ts (modified — barrel export)
- src/navigation/types.ts (modified — `SelectCustomers` route + `NewJob` param)
- src/navigation/RootNavigator.tsx (modified — route registration)
- src/features/newJob/NewJobScreen.test.tsx (modified — existing suite +
  review-gap tests: round trip, degraded states)
- __tests__/new-job-screen.test.tsx (modified — existing legacy suite)
- src/features/newJob/components/CustomerPicker.test.tsx (new — post-device-
  confirmation)
- src/features/newJob/SelectCustomersScreen.test.tsx (new — post-device-
  confirmation)
- __tests__/customers-recency.test.ts (new — post-device-confirmation)