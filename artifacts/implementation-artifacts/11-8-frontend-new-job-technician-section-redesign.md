# Story 11.8: New Job technician section redesign — mirror the customer/skill sections

Status: done  # implemented + device-confirmed 2026-09-20; tests green; BMAD 4-layer review closed same day (1 decision + 9 patches applied, 3 defers, 11 dismissed)
baseline_commit: 4444498 (fenzo-app)

## Story

As an owner creating a job,
I want the Assign technician section to look and behave like the Skill and
Customer sections (tiles, search, Browse all),
so that assigning a technician is as fast and familiar as the other picks.

## Acceptance Criteria

> Amended 2026-09-20 to the as-shipped design (user's on-device iteration
> after implementation: two tiles instead of five, inline picker title
> instead of a SectionHead eyebrow, "N technicians" chip copy, advisory
> below the picker, plus banding and sibling-picker restyles). The original
> wording is preserved in git history.

1. **Technician section on New Job mirrors the Skill/Customer sections** —
   the horizontal tile scroll is replaced by a new `TechnicianPicker`
   (feature-local, see Dev Notes) with:
   - a header row: an inline section title ("Technician" — naming itself on
     one line with the chip, the same treatment the iteration gave the Skill
     and Customer sections, which dropped their `SectionHead` eyebrows) +
     count chip ("N technicians" / "1 technician", no "1 technicians"; white
     pill — `onPrimary` ground with a `palette.gray200` hairline, matching
     CustomerPicker; SkillPicker deliberately keeps its sunken chip) + a
     "Browse all" link (`ChevronRight`, primary) that pushes
     `SelectTechnicians`;
   - a search `Input` (leading `Search` icon) filtering the tiles client-side
     via a pure `filterTechnicians` helper (name OR phone digits — same
     semantics as `filterCustomers`; the current picker filters name-only);
   - a 3-column tile grid showing the **first 2** tile candidates plus a
     **"+N More technicians"** tile that also opens `SelectTechnicians`
     (2 tiles + the more tile fill exactly one complete row —
     `VISIBLE_TILES = 2`, user-confirmed across all three pickers);
     tiles: DS `Avatar` (initials) + name (2 lines) + "Invited" caption when
     `status === 'invited'` (kept from the current tiles — a just-invited
     technician must not look identical to an installed one; also announced
     in the tile's accessibility label) + solid primary
     check badge; selected styling identical to CustomerPicker
     (`primarySoft` background, primary border, primary label, badge).
2. **Tile roster unchanged in behavior** — tiles show the same
   `technicianOptions` the section offers today: skill-matching technicians
   first, falling back to the full roster only when nobody matches (with the
   existing "No technician is tagged with this skill — showing everyone"
   advisory kept, rendered **below** the picker — a user tweak from the
   device iteration; the original slot (above the picker) is in git
   history). The user confirmed: keep the skill filter on the New Job
   surface. No recency sort — roster order stays the profile's order (the
   user confirmed; technicians have no lastJobDate to sort by).
3. **Selected-technician pinning** — if the selection is outside the first
   two (via Browse all or an invite), it is pinned to the front of the idle
   grid, so the default surface always shows who the job is for.
4. **Dedicated `SelectTechniciansScreen`** (route `SelectTechnicians`)
   mirroring `SelectCustomersScreen`:
   - header ("Select technicians" title + back), subheader with count chip
     ("N total") and a "Clear" action (disabled when nothing pending);
   - search field filtering client-side via `filterTechnicians`;
   - single-select rows over the **full roster** (not skill-filtered — user
     confirmed): `Avatar` (technician name) + name + skills caption
     (comma-joined `skills`, hidden when empty) + `technicianPhone` +
     "Invited" caption when invited + 26px circle toggle; when a `skillId`
     was handed over, rows whose `skillIds` include it carry a small
     "Matches skill" marker (primary text on `primarySoft` pill, DS tokens
     only) so the recommendation stays visible without filtering;
   - sticky "Apply selection" footer button, disabled until a row is picked;
     Apply returns via `navigation.popTo('NewJob', { selectedTechnicianId },
     { merge: true })`; Clear returns with `{ selectedTechnicianId: null }`
     immediately (a job cannot be submitted without a technician, so the
     section falls back to its unselected state — same decision semantics as
     the customer section's Clear);
   - loading / error / empty states copied from `SelectCustomersScreen`
     (spinner on first load, error + "Try again", distinct empty-roster vs
     no-search-match copy).
5. **Tile order = profile order; picker rows = store order** — no new sorting
   helper; the section, the tiles and the picker rows all read the profile
   roster as-is.
6. **"Add new technician" link kept** — the inline row stays under the picker
   (same `setAddSheetVisible(true)` → `AddTechnicianSheet` → invite →
   `loadMyProfile({ force: true })` → auto-select newcomer flow, untouched).
7. **Degraded states preserved** (`renderTechnicians()` in NewJobScreen):
   spinner while the profile's first load is in flight; error + "Try again"
   (`refreshProfile`) when the profile failed with nothing to show;
   "No technicians yet" copy (Add-new is the way forward) when loaded and
   empty; stale rows stay usable on a failed refresh.
8. **Selection return consumed correctly** — NewJobScreen's `useEffect` reads
   `route.params?.selectedTechnicianId`: a string patches
   `draft.technicianId`, `null` clears it, `undefined` is a no-op; the param
   is cleared with `navigation.setParams({ selectedTechnicianId: undefined })`
   after consumption (mirror of `selectedCustomerId` / `selectedSkillId`).
9. **All existing selection logic untouched** — `handleSkillChange` still
   clears a technician who doesn't carry the new skill; the skill-Clear path
   still nulls both; `canSubmit` still requires all three ids; progressive
   disclosure (section hidden until a skill is picked) unchanged.
10. **No backend change** — everything reads the shared profile roster
    (`GET /users/me` via `useMyProfile`); no service or endpoint work.
11. **Tests**: existing tests are updated only as needed to keep the suite
    green under the new UI; comprehensive new tests are written **after the
    user confirms the feature on device** (test-timing rule — never with the
    feature).

## Tasks / Subtasks

- [x] Task 1: `filterTechnicians` + `technicianPhone` helpers (AC: 1, 4)
  - [x] In `src/features/technicians/format.ts` (create if missing):
        `filterTechnicians(options, query)` — pure, name OR digit-substring
        phone, mirroring `filterCustomers` discipline (trim, lowercase,
        digits-only compare); `technicianPhone(technician)` — dial code +
        digits, mirroring `customerPhone`. Export from the technicians
        barrel.
- [x] Task 2: feature-local `TechnicianPicker` component (AC: 1, 2, 3)
  - [x] New file `src/features/newJob/components/TechnicianPicker.tsx`,
        modeled on `CustomerPicker.tsx` (same header/count-chip/search/grid/
        check-badge structure and styles; `VISIBLE_TILES = 2` after the
        user's on-device iteration, originally 5). Props
        `{ title, options, value, onChange, onBrowseAll }` (CustomerPicker
        naming, plus the inline section title the iteration added to all
        three pickers).
  - [x] Tiles: `Avatar` (initials) + name + "Invited" caption + check badge;
        selected styling = `primarySoft` bg + primary border + primary label.
        Selection pinned to front when outside the first two. Single-select
        tap-to-select; tapping the selected tile again clears (carry over the
        current picker's toggle-to-clear semantics).
  - [x] Search filters via `filterTechnicians(options, query)`; empty-match
        copy `No technicians match "…"`.
- [x] Task 3: `SelectTechniciansScreen` (AC: 4, 5)
  - [x] New file `src/features/newJob/SelectTechniciansScreen.tsx`, modeled
        on `SelectCustomersScreen.tsx` (pendingId state, Apply/Clear `popTo`
        with `{ merge: true }`, KeyboardAvoidingView footer, identical status
        states).
  - [x] Rows read the profile roster (`useMyProfile`); row = `Avatar` + name +
        skills caption + `technicianPhone` + "Invited" + skill-match marker +
        circle toggle.
- [x] Task 4: Navigation wiring (AC: 4, 8)
  - [x] `src/navigation/types.ts`: add `SelectTechnicians:
        { selectedTechnicianId?: string | null; skillId?: string } | undefined`
        and extend `NewJob` params with
        `selectedTechnicianId?: string | null`.
  - [x] `RootNavigator.tsx`: register `SelectTechnicians` (headerShown false)
        next to `SelectCustomers`.
  - [x] `src/features/newJob/index.ts`: export `SelectTechniciansScreen`.
- [x] Task 5: `NewJobScreen` rework (AC: 1, 6, 7, 8, 9)
  - [x] Swap the `src/components/TechnicianPicker` import for the new
        feature-local one; pass `onBrowseAll` (navigate to
        `SelectTechnicians` with `selectedTechnicianId` + `skillId`).
  - [x] Add the `selectedTechnicianId` consume-and-clear `useEffect` (mirror
        the `selectedCustomerId` one).
  - [x] Keep `renderTechnicians()` degraded states, the Add-new row + sheet +
        auto-select, `handleSkillChange`, `canSubmit` and progressive
        disclosure exactly as they are; keep the noSkillMatch advisory copy
        but rendered **below** the picker (user's device iteration — the
        original slot was above).
  - [x] Beyond this story's original scope, done on the user's instruction
        during the device iteration: `SECTION_BANDS`/`sectionBand(index)`
        alternating band colours per section, `radius.lg` + padding on the
        section cards, and the inline `title` + white count chip on
        SkillPicker and CustomerPicker (their `VISIBLE_TILES` also went
        5 → 2, see the Test record).
- [x] Task 6: Existing-test maintenance (AC: 11) — update
    `NewJobScreen.test.tsx` (and any test asserting the old technician tiles)
    minimally so the suite passes; no new test cases yet.
- [x] Task 7: Docs — update the New Job screen doc-comment block and the
    `src/components/TechnicianPicker.tsx` doc-comment (its "tiles" variant is
    now EditJobSheet-only); no other docs describe this section.

## Dev Notes

### The pattern being copied (read these two files first)

- `src/features/newJob/components/CustomerPicker.tsx` — presentational
  picker: header row (inline section title + count chip on `radius.pill` —
  white `onPrimary` ground with a `palette.gray200` hairline after the
  2026-09-20 iteration; SkillPicker deliberately keeps its sunken chip —
  plus "Browse all" `Pressable`), search `Input` with `leadingIcon`,
  3-column tile grid (`onLayout`-measured row width, gap `spacing.s3`),
  `VISIBLE_TILES = 2` (originally 5 — the user tightened all three pickers
  to 2 tiles + the more tile = one complete row),
  `tile` styles (minHeight 84, `borderSubtle` on `surfaceCard`, `radius.lg`),
  selected tile (`primarySoft` bg, primary border 1.5, primary label), pinned
  selection, `checkBadge` (18×18 primary circle with 12px `Check`),
  `tileMore` ("+N" in `typography.heading` + label on `surfaceSunken`),
  `noMatch` copy. Copy the final styles verbatim — they carry the 11-5
  restyle lessons (light tint, not solid fill).
- `src/features/newJob/SelectCustomersScreen.tsx` — full-screen browser:
  `SafeAreaView edges={['top']}`, header (back `ArrowLeft` + title), subheader
  (count chip "N total" + disabled-able "Clear"), subtitle, search, FlatList
  rows, `KeyboardAvoidingView` + sticky footer `Button` (disabled until
  pending), and the two `popTo('NewJob', …, { merge: true })` calls — Apply
  sends the pending id, Clear sends `null` immediately.

### Name-collision warning

Two components will briefly share the name `TechnicianPicker`:

- `src/components/TechnicianPicker.tsx` — KEEP untouched; after this story
  its only consumer is `EditJobSheet` (rows variant). Do not delete or restyle
  it (user confirmed: New Job only).
- `src/features/newJob/components/TechnicianPicker.tsx` — NEW, mirrors its
  newJob siblings (SkillPicker/CustomerPicker live in the same folder).

NewJobScreen imports switch to the feature-local one. Watch the import paths
carefully — the wrong path compiles but renders the wrong picker.

### What changes vs what must be preserved (NewJobScreen.tsx)

Current state (lines ~219–248, 488–540, 604–615): roster `profile.technicians`
→ `matchingTechnicians` (exact `skillIds` id membership) → `noSkillMatch`
fallback → `technicianOptions`; `renderTechnicians()` degraded states +
`TechnicianPicker` (horizontal tiles) + Add-new row. To preserve exactly:

- `allTechnicians` / `matchingTechnicians` / `noSkillMatch` /
  `technicianOptions` memos — untouched (the tile roster stays skill-filtered
  with fallback).
- `handleSkillChange` (lines ~258–273) — technician cleared when the new
  skill isn't carried — untouched.
- Skill-Clear path nulls `technicianId` with the skill — untouched.
- `handleAddTechnicianSubmit` (lines ~349–362) — `addTechnician` (POST
  /auth/invite) → `loadMyProfile({ force: true })` → auto-select newcomer by
  phone match if they carry the skill — untouched. Note: the auto-select
  patches `draft.technicianId` directly, so the newly selected tile must be
  visible — pinning (AC 3) covers this when the grid is searched.
- `canSubmit` (all three ids required), progressive disclosure gate
  (`draft.skillId ?`), Notes section — untouched.

What to remove: the `src/components/TechnicianPicker` import (only). The
section's degraded-state copy stays in `renderTechnicians()`; the advisory
text and the picker swap slots 1:1.

### Reuse — do NOT reinvent

- `filterCustomers` discipline for the new `filterTechnicians` — same
  trim/lowercase/digit-substring approach; do not write a third filter style.
- `Avatar` (components/ui) — tile chip and picker row.
- `useMyProfile` (`src/features/profile/useMyProfile.ts`) — the roster store:
  `profile.technicians`, `isLoading`/`error`, `loadMyProfile` (throttle/join
  safe), `refreshProfile`. Both NewJobScreen and the new Select screen
  subscribe to it — do NOT use `useTechnicians` (that store carries
  `invite_<inviteId>` placeholder ids during an in-flight invite, which must
  never be POSTed; the profile roster is the server-id source of truth —
  commit 4444498 hydrates it from the profile for its own consumers, this
  story stays on the profile like NewJobScreen already does).
- `SectionHead` stays above the picker (no inline title in the picker header).

### Navigation facts (React Navigation 7)

- Return MUST be `navigation.popTo('NewJob', { selectedTechnicianId }, {
  merge: true })` — plain `navigate` pushes a duplicate screen in v7
  (learned in 11-5; see both Select screens' file docs).
- NewJob consumes the param once, then `setParams({ selectedTechnicianId:
  undefined })` — same pattern as the other three params.
- `skillId` is handed to `SelectTechnicians` at navigate-time as a plain
  read-only param (marks matching rows); it is NOT part of the Apply/Clear
  return and is not consumed-and-cleared by NewJob.

### Data facts

- `ProfileTechnician` (`src/services/resources/users.ts:76-96`): `{ id, name,
  countryCode, phoneNumber (digits, no dial code), status ('invited'
  observed), skills: string[] (names), skillIds: string[] (parallel), createdAt }`.
  `skills`/`skillIds` are parallel arrays — the skills caption and the
  skill-match marker read the id array, the caption reads the names.
- No `lastJobDate` on technicians — no recency sort exists; the user
  confirmed store order.
- Owner-only surface (`GET /users/me` with technician JWT has no
  `technicians` array); the technician app never renders this section, so no
  role handling is needed.

### Project Structure Notes

- New files follow the 11-7 convention: screen in `src/features/newJob/`,
  picker presentational in `components/`; pure helpers in the technicians
  feature's format module.
- Keep relative imports (whole codebase does; the CLAUDE.md alias guidance is
  aspirational — 11-5/11-7 kept relative).
- Design tokens only — no hardcoded colors/spacing; copy CustomerPicker
  styles rather than inventing.
- File sizes stay well under the ~300-line guideline by mirroring.

### Test timing (project rule)

Implement → **user confirms on device** → then write tests → then BMAD code
review. This story's implementation updates existing tests only to keep
`bun run test` green (fenzo-app's jest script — never bare `bun test`). New
tests (`TechnicianPicker.test.tsx` feature-local,
`SelectTechniciansScreen.test.tsx`) come as a follow-up after confirmation.

### Previous-story intelligence (11-5, 11-7 — same pattern)

- Count chip must handle singular ("1 technician") — 11-7 review flagged
  "1 customers".
- Selected-tile restyle is light tint + primary border/label/badge — copy
  CustomerPicker's final styles as they are today.
- `popTo` vs `navigate` regression — covered in Navigation facts above.
- Empty-book copy on the Select screen must align with NewJobScreen's own
  empty copy for the same store (11-7 review patch).
- Trailing newlines on every new file (11-7 review patch).
- Test mocks must use `jest.requireActual` for the format helpers rather than
  hand-reimplementing them (11-7 review patch).

## Dev Agent Record

### Agent Model Used

Claude (GLM) via Claude Code, 2026-09-20

### Completion Notes List

- **Design iteration after first device check (2026-09-20, user-driven):**
  1. Section bands — every New Job section became a rounded band
     (`radius.lg` + padding) whose background alternates round-robin
     between `surfaceCard` and `surfaceSunken` (`SECTION_BANDS` in
     NewJobScreen); count chips and "+N more" tiles gained a hairline
     `borderSubtle` outline so they read on both band colours.
  2. One-line headers — Customer and Technician sections dropped their
     `SectionHead` (the eyebrow duplicated the picker header); the pickers
     gained SkillPicker's `title` prop — title + count chip + Browse all on
     one line. Date & time and Notes keep `SectionHead`.
  3. User's own tweaks on top: count chips restyled white
     (`colors.onPrimary`) with a `palette.gray200` border; section renamed
     `title="Technician"`; the noSkillMatch advisory moved BELOW the picker;
     Date & time / Notes left with `SectionHead` (user confirmed the look).
- Implemented exactly per the Dev Notes; no new dependencies, no BE change.
- `filterTechnicians` + `technicianPhone` added to a new
  `src/features/technicians/format.ts`, exported from the barrel; both mirror
  the customers helpers' discipline.
- Feature-local `TechnicianPicker` copies CustomerPicker's styles verbatim;
  tiles add the "Invited" caption (kept from the old tiles), selection is
  toggle-to-clear (`onChange(null)` on re-tap — carried from the old picker,
  unlike the customer picker whose tap simply replaces the pick).
- `SelectTechniciansScreen` mirrors `SelectCustomersScreen` including the v7
  `popTo(..., { merge: true })` return; rows carry the full roster with
  "Matches skill" pills when the caller handed over `skillId`, plus skills
  caption and phone. Empty-roster copy aligned with NewJobScreen's.
- NewJobScreen: `selectedTechnicianId` consumed-and-cleared in its own
  `useEffect`; `handleBrowseTechnicians` passes `?? undefined` for both
  params (absent ≠ pre-cleared). Skill-memos, invite auto-select,
  `handleSkillChange`, `canSubmit`, progressive disclosure untouched.
- `src/components/TechnicianPicker.tsx` untouched except its doc-comment
  (tiles variant is now EditJobSheet-only).
- **Tests**: existing suites updated only (legacy `__tests__/new-job-screen`
  mock path moved to the feature-local picker + prop renames
  onSelect/technicians/selectedId → onChange/options/value;
  `NewJobScreen.test.tsx` auto-select assertions moved to `value`, and its
  `../technicians` mock now spreads `jest.requireActual` so the picker's real
  `filterTechnicians` runs). Per the test-timing rule, NO new test cases were
  written during implementation.
- `bun run tsc --noEmit` — clean. `bun run test` — 990/991; the single
  failure (`__tests__/api-client.test.ts`) is the pre-existing local-config
  one (user's uncommitted `src/config/index.ts`), untouched.

### Test record (2026-09-20, after device confirmation)

- **Design change picked up from the user's working tree before writing
  tests:** `VISIBLE_TILES` 5 → 2 in all three pickers (Skill, Customer,
  Technician — user confirmed intentional). New idle-grid shape: 2 tiles +
  the "+N more" tile fill exactly one complete row (COLUMNS = 3 divides
  2 + 1); a pinned selection still replaces within the two. The three
  picker test suites and the stale "five tiles / 2 complete rows" doc
  comments were updated to match.
- New suites, mirroring the 11-7 precedent (stores mocked, pure helpers run
  for real):
  - `src/features/newJob/components/TechnicianPicker.test.tsx` (13 tests):
    offered-order tiles, two-tile cap + "+N" tile, count chip singularised,
    inline title, Browse all, toggle-to-clear (`onChange(null)` on re-tap),
    name/phone search + no-match copy, pinning beyond the first two,
    selection visible under a matching search, "Invited" caption.
  - `src/features/newJob/SelectTechniciansScreen.test.tsx` (15 tests): full
    roster rows (name/skills/phone/total chip), caller's selection
    pre-selected, skillId marks matches without filtering, "Invited"
    caption, search + phone-digit match + no-match copy, single-select
    replace + re-tap keep, Apply disabled→popTo with the pending id
    (merge), Clear disabled→popTo with null, back = plain goBack, spinner /
    empty-roster / error-retry states.
  - `filterTechnicians` / `technicianPhone` have no standalone unit file —
    they run for real inside both component suites (same discipline as the
    customers helpers).
- After the VISIBLE_TILES alignment: `bun run tsc --noEmit` clean;
  `bun run test` 1018/1019 (+28 new tests) — the only failure remains the
  pre-existing `api-client` local-config one.

### Review Findings (2026-09-20, BMAD 4-layer review)

- [x] [Review][Decision] Count-chip treatment diverges across the three pickers — RESOLVED (user, 2026-09-20): leave as-is — the difference is deliberate; note it in SkillPicker so the next reader knows Customer/Technician's white chip isn't drift. [<file:src/features/newJob/components/SkillPicker.tsx:190, src/features/newJob/components/CustomerPicker.tsx:189, src/features/newJob/components/TechnicianPicker.tsx:197>]
- [x] [Review][Patch] New Job↔SelectTechnicians round trip untested on the New Job side — nothing covers `handleBrowseTechnicians` params (current selection + skillId), the Apply-string effect, the null-Clear drop, or the param reset; sibling SelectSkills/SelectCustomers suites cover their equivalents. Add 3 tests mirroring those suites. [src/features/newJob/NewJobScreen.tsx:179-186, 379-383]
- [x] [Review][Patch] Trailing newlines missing on 5 new/edited files (SelectTechniciansScreen.tsx, components/TechnicianPicker.tsx, technicians/format.ts, both new test files) — explicit 11-7 review carry-over. [<file:src/features/newJob/SelectTechniciansScreen.tsx>]
- [x] [Review][Patch] Story doc drift — ACs/Dev Notes still describe the pre-iteration design (first 5 tiles, "N available" chip, no inline title, advisory above the picker) while the as-shipped code is the user-confirmed 2-tile / "N technicians" / inline-title / advisory-below version; Tasks also don't cover the Skill/Customer chip restyles or SECTION_BANDS banding. Update AC 1, AC 2 naming, Task 2/Task 5 and Dev Notes to as-shipped. [<file:artifacts/implementation-artifacts/11-8-frontend-new-job-technician-section-redesign.md>]
- [x] [Review][Patch] "Invited" caption and "Matches skill" pill not announced to screen readers — SelectTechniciansScreen row label carries name/skills/phone but not the pill/caption; TechnicianPicker tile label is the name alone. [src/features/newJob/SelectTechniciansScreen.tsx:113, src/features/newJob/components/TechnicianPicker.tsx:135]
- [x] [Review][Patch] Stale comment — "the helpers have no suite of their own yet" is false the same commit that adds TechnicianPicker.test (which runs the real `filterTechnicians`). [src/features/newJob/NewJobScreen.test.tsx:132-134]
- [x] [Review][Patch] Stale test name — "separates the sections with eyebrow headers and dividers" now describes only Date & time / Notes; the picker sections assert inline titles in the same test body. Rename. [src/features/newJob/NewJobScreen.test.tsx:346]
- [x] [Review][Patch] Feature TechnicianPicker doc comment says the section name is "Assign technician" but the rendered title is "Technician". [src/features/newJob/components/TechnicianPicker.tsx:28-30]
- [x] [Review][Patch] Garbled doc block in the old (EditJobSheet) picker — "tiles (default) — horizontal tile row. EditJobSheet's territory now:" breaks the original two-layout structure. Tidy. [src/components/TechnicianPicker.tsx:4-9]
- [x] [Review][Patch] Unspaced import `{colors, palette, radius, spacing, typography}` inconsistent with every other import in the codebase (three pickers). [src/features/newJob/components/TechnicianPicker.tsx:41]
- [x] [Review][Defer] Dial-code digits in search fail to match (query "+91 9000000002" → digits "919000000002" not in the stored bare number) [src/features/technicians/format.ts:31] — deferred, pre-existing (identical semantics in filterCustomers; deliberate mirror)
- [x] [Review][Defer] Tile-grid machinery (header/chip/search/3-col grid/pinning/no-match) is now a third near-identical copy across the three pickers [src/features/newJob/components/TechnicianPicker.tsx] — deferred, pre-existing pattern (accepted per-story mirror across 11-5/11-7/11-8; extraction is a follow-up story)
- [x] [Review][Defer] SelectTechniciansScreen at ~403 lines vs the ~300-line guideline [src/features/newJob/SelectTechniciansScreen.tsx] — deferred, pre-existing (mirrors the accepted SelectCustomersScreen ~360)

## References

- [Source: fenzo-app src/features/newJob/components/CustomerPicker.tsx] —
  the pattern being mirrored (styles, header, grid, pinning).
- [Source: fenzo-app src/features/newJob/SelectCustomersScreen.tsx] — picker
  page pattern (pending state, Apply/Clear, popTo, degraded states).
- [Source: fenzo-app src/components/TechnicianPicker.tsx] — the current
  picker; "Invited" caption logic and toggle-to-clear semantics carried over;
  rows variant stays for EditJobSheet.
- [Source: fenzo-app src/features/newJob/NewJobScreen.tsx lines 219–248,
  258–273, 349–362, 488–540, 604–615] — current technician section + memos +
  invite flow.
- [Source: fenzo-app src/features/profile/useMyProfile.ts] — roster store.
- [Source: fenzo-app src/services/resources/users.ts lines 76–96] —
  ProfileTechnician shape.
- [Source: fenzo-app src/features/customers/format.ts] — filterCustomers /
  customerPhone to mirror.