# 27-2 — Types tab master-detail restyle (web)

| | |
|---|---|
| Status | done — SHIPPED 2026-11-24 (fenzit-web b7caed5 Types tab to design + f982671 turned-off restyle; review patches 4d24e1a; pushed to main) |
| Size | M (~1–1.5 days) |
| Layer | Web (fenzit-web) — restyles the uncommitted pre-design build, **no BE** |
| Depends on | none (parallelizable with 27-3; state-disjoint) |
| Contract | design/types-live.jpg + design/types-turned-off.jpg · design/DESIGN-MAP.md (drops) · BE values-only PATCH (23-13, live) |

## Gap (evidence)

The uncommitted Types tab renders 4 independent `LeaveTypeCard` settings cards in a
grid — each with its own save button, no shared editor. The design (types-live.jpg) is
**master-detail**: a summary-card row on top (click a card to edit), ONE rules editor
below showing the selected type, one Save. The editor's fields map 1:1 onto the
already-built card, so this is a restyle + selection state, not new wire work.

## Scope

1. **Summary card row** — one card per configurable type: name, rate summary
   ("12 days / year" monthly·annual → show `accrualDays × 12`/yr for monthly per the
   design's conversion hint? NO — design shows "12 days / year" for a 1 day/mo type;
   render the annualized figure for monthly, the grant for annual, "As earned" for
   none), mode chip (Monthly Accrual / Annual Grant / Event Basis), Enabled/Off state
   (red "Turned Off" per types-turned-off.jpg), selected card highlighted + "Editing"
   affordance. Click = select (client state), NOT navigation.
2. **Rules editor** (below, for the selected type) — the existing `LeaveTypeCard`
   content, restructured as one wide panel: "Earned Leave Rules" header + mode badge +
   inactive/live state chip; toggle rows in the design's order (Enable with the red
   off-warning banner, Paid, rate block, carry-forward, over-balance); rate block gets
   the design's presets (0 / 1 / 1.5 / 2 days quick-set) + the "1 day/mo = 12 days/yr"
   conversion hint for monthly; single Save button; per-card error/saved copy survives
   as-is (fetcher per selected type).
3. **Remnants** (configurable=false rows) — keep the existing read-only line below the
   editor; the design has no concept of them.
4. **Right rail — per-type rates list only** (from the design's quota breakdown:
   "Earned Leave 12 days / yr · Sick Leave 10 days / yr · Bereavement 5 days / yr
   (Grant) · Comp Off Event-based"). The donut/team-pool number is DROPPED
   (DESIGN-MAP.md). The rail's "Upcoming time off" list lands with 27-4 (needs 27-1);
   leave the rail slot structurally ready for it.
5. Selection defaults to the first type in catalog order (earned, sick, bereavement,
   comp_off — the existing CODE_ORDER); unsaved-changes guard when switching cards
   (dirty editor → confirm or keep selection, same pattern as the job settings
   dialog's dirty handling).

## Out of scope

Team quota donut + "144 days/yr pool" (dropped), carry-forward "15 days cap" copy
(dropped — boolean only), any change to the PATCH contract or the loader/action pair,
the upcoming-rail data (27-4), mobile (deferred).

## Technical approach

- Selection = `useState` in `TypesPanel`; the loader keeps returning all rows (already
  does). Each type's editor state stays in its own component instance — mounting only
  the selected type's editor preserves the per-type fetcher idiom (one form, one
  result), which the current grid already proves.
- The editor is the existing `LeaveTypeCard` refactored: same hidden-inputs-only-when-
  dirty PATCH body, same validation (0–366, 2 decimals, mode guards), same
  MESSAGES_BY_CODE error path. Presets are three buttons that set the days state —
  no wire change.
- Files stay < ~300 lines: editor in its own component, rail in its own; CSS Modules
  strictly paired, tokens only. No `useEffect`.
- Off-warning banner copy (types-turned-off.jpg, adapted to Fenzit's fixed catalog):
  "When turned off, employees cannot see or request {name}. Existing approved leaves
  stay recorded, but new requests are blocked." — shown while `enabled` is false in the
  editor (pre-save state), matching the design.

## Acceptance criteria

1. Card row + editor render per types-live.jpg structure; selecting each of the 4
   types swaps the editor; mode-conditional fields stay exactly as built (comp_off: no
   rate; bereavement: no CF/over-balance).
2. Disabled type renders per types-turned-off.jpg: card "Turned Off", editor shows the
   warning banner; enabling + saving clears it.
3. Presets set the rate; the conversion hint shows the ×12 figure; dirty/PATCH
   changed-fields-only behavior unchanged (existing tests keep passing, re-pointed).
4. Remnants line still renders read-only below; rail rates list matches the 4 types'
   live values.

## Test anchors

- AdminLeavePage.test.tsx (to be written in this story if not yet present): selection
  swap, preset click → PATCH body carries the preset value, off-warning visibility,
  remnants read-only, mode guards (the existing loader/action contract tests).

## References

design/types-live.jpg, design/types-turned-off.jpg; the uncommitted
`LeaveTypeCard.tsx` / `AdminLeavePage.tsx` (the code being restyled).

## Risks / gotchas

- The design's "12 days / year" card summary is the ANNUALIZED figure of 1 day/mo —
  do not confuse it with `accrualDays` (1). Pin in tests: card shows 12, editor shows 1.
- The design's mock names (Casual/Personal/PTO, "Schema ID: earned") are filler — the
  fixed catalog's names/codes win.
- Unsaved-changes on card switch is the one behavior the design doesn't specify —
  pick the confirm-guard and pin it in tests (never silently discard an owner's edit).

## Code review (BMAD thorough, 2026-11-24) — this card's share

One review run over the whole epic FE diff (blind-hunter, edge-case-hunter,
verification-gap, intent-alignment); per-card blocks. This card: 2 patch ·
1 rejected-as-deliberate.

### Patched
- State chip tint now follows the LOCAL toggle (`data-live={enabled}`), not the
  saved value — text and tint can no longer disagree before a save (BH-4).
- Rate presets compare numerically with an empty-guard — typing "1.50" still
  lights the "1.5 days" preset; an empty input lights nothing (BH-16).

### Rejected
- ECH-6 "stale editor overwrites a concurrent save": the tab mounts one editor
  per type (`key={row.id}`, hidden when unselected) — card switches never leak
  state, and the concurrent-surface trade-off is the documented intent of the
  stay-mounted design.

### Cross-cutting (recorded here, first FE card)
- REGRESSION patched: the drive-by `"/admin/company/holidays"` entry in
  `PAGES_WITH_OWN_HEADER` stripped that page's only h1 (Holidays renders a bare
  SectionCard, no own header) — entry removed.
- Dead `leaveUrl(tab)` export deleted (never imported; tabs build their own
  addresses).
- The four leave error codes are now pinned in `errorMessages.test.ts`'s
  `it.each` (VG-2). Suite after the round: 1225 pass / 0 fail (was 1216).
