---
epic: 9
story_id: "9-1"
title: "Frontend: full-screen attachment viewer (gallery view) for captured photos and signature"
status: done
created: 2026-09-14
updated: 2026-09-14
acceptance_criteria:
  - AC1: "Tapping a successfully loaded photo tile in EITHER detail grid (owner `AttachmentGrid`, technician `PhotoSection`'s confirmed tiles) opens a full-screen viewer positioned on that photo; tapping a failed tile, in-flight tile, add tile, or placeholder tile does nothing"
  - AC2: "Tapping a successfully loaded customer-signature tile opens the viewer on the signature page; the viewer is ONE pager — photos in arrival order, signature last — so the user can swipe from photos to the signature without re-entering"
  - AC3: "Viewer supports horizontal swipe paging (1 image per swipe, snapped), pinch zoom (1x–3x), double-tap zoom toggle, pan while zoomed, swipe-to-dismiss at 1x (image fades with the drag, spring-back below threshold); zoom resets on page change and on open; while zoomed, dragging pans the image and never dismisses or pages"
  - AC4: "Header shows a close button (top-left, ≥44px target, X icon) and a centre counter ('2 of 6'); the signature page's counter is replaced by the label 'Customer signature'; Android hardware back closes the viewer; the status bar is hidden while open"
  - AC5: "Before an image loads the page shows a spinner and stays swipeable; if an image fails to load (expired presigned URL) the page shows the grid's placeholder vocabulary — sunken panel, ImageOff glyph, 'Tap refresh' — with no retry button inside the viewer (refetch via pull-to-refresh remains the only retry)"
  - AC6: "Tappable tiles get accessibilityRole 'imagebutton' with labels 'View photo N of M' / 'View customer signature'; the viewer's counter is an accessibilityLiveRegion='polite' node; press feedback on tappable tiles is scale or opacity only — no new persistent icon, badge, or border on any tile"
  - AC7: "Zero regression: in-flight/failed/add-tile behaviour, retry wiring, URL-keyed remount, and onError state machines in all three grid components are byte-identical to before; the viewer is purely additive and lives in ONE shared component used by both audiences"
blocking: []
spec_refs:
  - "UX design: BMAD UX agent spec, 2026-09-14 (embedded in this story's Changes + Dev Notes)"
  - "Research: BMAD research agent verdict, 2026-09-14 (react-native-image-viewing@0.2.2 vendored, MIT)"
  - "src/services/resources/jobs.ts:224 — JobAttachment (type 'photo' | 'signature', url: string | null presigned R2, 1-hour TTL, may be null, never persist)"
  - "src/theme/DESIGN_SYSTEM.md — tokens, motion band 120–320ms, shadow.sheet, sentence case, ≥44px targets"
baseline_commit: 07989fa8d1a9bde6a8d139bed619c6475ece08cd
---

## Tasks / Subtasks

- [x] Task 1 — vendor the viewer source (AC1, AC3): copy the MIT `src/` of `react-native-image-viewing@0.2.2` (~10 small TS files) into `src/components/ImageViewer/` with a VENDORED header comment (origin, version, license, local changes list); delete the dead `components/Modal/Modal.android.js` + `Modal.ios.js` overlay (nothing imports it) and the deprecated-`SafeAreaView` `ImageDefaultHeader`/`ImageDefaultFooter` (we always pass our own header); add per-image `onError` tracking so failed pages render the failure placeholder instead of spinning forever (AC5); **no bun install — zero new dependency** *(DEVIATION — see Completion Notes 1–3: the user had already installed `react-native-image-viewing@0.2.2` as a dependency before dev started; Task 1 was executed as "dependency + bun patch" instead of vendoring, adding the AC5 onError path via the patch)*
- [x] Task 2 — `colors.backdropDark` token (AC4): add `'rgba(17, 24, 39, 0.96)'` to `src/theme/colors.ts` with a one-line comment ("full-screen image viewer backdrop"); reference only from the viewer, never a raw rgba in a component
- [x] Task 3 — `src/components/AttachmentViewer.tsx` (AC2–AC5, AC7): shared wrapper — RN `Modal` (`transparent`, `animationType="fade"`, `statusBarHidden`, `onRequestClose={onClose}`) over the vendored ImageViewing; own `HeaderComponent` (close `IconButton` + `X` 24px `colors.onPrimary` left, counter/label `typography.label` `colors.onPrimary` centre, live region); own `FooterComponent` = null (no chrome); signature page renders on a white card (`colors.surfaceCard`, `radius.lg`, `spacing.s4` inset, `shadow.md`, `spacing.s2` inner padding, image `contain`) while photos render contain directly on `backdropDark`; mount ONCE per screen and control only via `visible` — never drive `imageIndex` from state while open (flicker guard, research §1) *(DEVIATIONS — see Completion Notes 4, 7, 8: full-bleed white signature page instead of inset card; lib-owned Modal makes the wrapper's own Modal redundant; fixed header top inset)*
- [x] Task 4 — technician wiring (AC1, AC2, AC7): `TechJobDetailContent.tsx` owns the viewer state (it has both `photos` and `signature`) and passes an `onViewPhoto(index)` callback to `PhotoSection` and an `onView` callback to `SignatureTile`; wrap `PhotoSection`'s `ConfirmedTile` image branch and `SignatureTile`'s white card in `Pressable` (`accessibilityRole="imagebutton"`, press-scale 0.97 with `motion.durationFast`); `SignatureTile`'s "Tap refresh" placeholder branch stays a plain View *(DEVIATION — see Completion Notes 5: opacity press feedback instead of scale, per AC6's "scale or opacity")*
- [x] Task 5 — owner wiring (AC1, AC2, AC7): `AttachmentGrid.tsx` owns its viewer state internally (it receives all attachments including the signature); wrap `PhotoTile`'s image branch and the `SignatureTile` row's white card in `Pressable` with the same roles/labels/press feedback; the optional Re-capture ghost Button sits OUTSIDE the card and keeps its own press target untouched
- [x] Task 6 — tests + device checklist (all ACs): unit/component tests for the tappable-tile contract (image branch pressable, placeholder/retry/add branches not) and AttachmentViewer rendering (open/close, counter, signature card, failure placeholder); manual device checklist per Dev Notes (Android pinch anchor, post-zoom recenter, swipe-to-close, no flicker, hardware back) *(automated part done; manual device checklist left for the user — see the unchecked Testing item)*

### Review Findings

**Code review 2026-09-14 (BMAD 3-layer: adversarial-blind + edge-case + acceptance-audit). 11 dismissed as noise/documented; counts below.**

- [x] [Review][Decision] iOS status bar is NOT hidden; header ignores the notch [AttachmentViewer.tsx:41-44] — RESOLVED 2026-09-14: user chose (a) — render `<StatusBar hidden />` in the header + safe-area-aware top inset on iOS (to be applied with the patch batch). Original: AC4's "status bar hidden while open" holds on Android only (the lib's StatusBarManager returns null on iOS); `HEADER_TOP = spacing.s5` (20px fixed) means the close button/counter can sit under the iOS status bar/notch. Options: (a) render `<StatusBar hidden />` in the header + safe-area-aware top inset on iOS; (b) accept pending device-checklist verification.
- [x] [Review][Decision] Closing the viewer skips its fade-out [AttachmentViewer.tsx:49-59] — RESOLVED 2026-09-14: user chose (a) — keep the Modal mounted through the lib's own `visible=false` exit fade (to be applied with the patch batch). Original: `onClose` unmounts the session synchronously, so `animationType="fade"` animates only the open. Options: (a) keep the Modal mounted through the lib's own `visible=false` exit fade; (b) accept the instant close.
- [x] [Review][Patch] Owner grid opens the FIRST signature; the technician screen the LAST [AttachmentGrid.tsx:35] — APPLIED 2026-09-14: `viewerListOf` takes the last captured signature (`.slice(-1)[0]`), test added ("opens the viewer on the LAST captured signature (re-capture wins)").
- [x] [Review][Patch] Negative `initialIndex` passes the stale-open guard [AttachmentViewer.tsx:56] — APPLIED 2026-09-14: `initialIndex < 0` added to the guard, test added.
- [x] [Review][Patch] Failure-page height frozen at import time [AttachmentViewer.tsx:210] — APPLIED 2026-09-14: `useWindowDimensions().height` on the placeholder, frozen style height removed.
- [x] [Review][Patch] imagebutton role not gated on the handler [PhotoSection.tsx ConfirmedTile, AttachmentGrid.tsx PhotoTile] — APPLIED 2026-09-14: role/label/press gated on the handler at both sites (SignatureTile already was); PhotoSection gating test added.
- [x] [Review][Patch] `memo(ActiveViewer)` defeated by fresh `onClose` at both call sites [AttachmentGrid.tsx:150, TechJobDetailContent.tsx:271] — APPLIED 2026-09-14: `closeViewer = useCallback(() => setViewer(null), [])` at both call sites.
- [x] [Review][Patch] Pin `react-native-image-viewing` to exact `0.2.2` [package.json:32] — APPLIED 2026-09-14: caret dropped, exact `0.2.2`.
- [x] [Review][Patch] Dead test helper `imageUris` [AttachmentViewer.test.tsx:48-53] — APPLIED 2026-09-14: removed.
- [x] [Review][Patch] Five new files lack trailing newlines — APPLIED 2026-09-14: all five now end with `\n`.
- [x] [Review][Patch] Spinner-colour deviation undocumented [story Completion Notes 2] — APPLIED 2026-09-14: documented in Completion Note 2.
- [x] [Review][Patch] Testing section claims a "spinner while loading" test that does not exist — APPLIED 2026-09-14: test added ("spins the brand primary while an image loads") asserting `loadingColor === colors.primary`.
- [x] [Review][Patch] CLAUDE.md's new "Library research" rule is not in the story File List — APPLIED 2026-09-14: added to the File List as MODIFIED.
- [x] [Review][Defer] iOS VoiceOver announcement of page changes — `accessibilityLiveRegion` is Android-only [AttachmentViewer.tsx:142] — deferred, pre-existing platform gap; AC6 met as written. Reason: enhancement beyond AC scope.
- [x] [Review][Defer] Viewer-list derivation re-implemented in three places (drift risk) [AttachmentGrid.tsx:31-40, TechJobDetailContent.tsx:90-98, PhotoSection.tsx viewable] — deferred, pure refactor; currently consistent. Reason: no behavior defect today.

## Context

When a job is done, photos and the customer's signature are captured — but tapping a thumbnail does nothing today. This story adds the read/inspect side: tap a captured photo (or the signature tile) and a **full-screen gallery viewer** opens with standard image-viewer gestures. Both audiences get the identical behaviour from ONE shared component in `src/components/` — owner detail (`AttachmentGrid`, mounted at `JobDetailScreen.tsx:507`) and technician detail (`PhotoSection` + `SignatureTile` inside `TechJobDetailContent.tsx`).

**Zero backend change.** `GET /jobs/:id` already returns every attachment with `url: string | null` — a presigned R2 read URL (1-hour TTL, minted per detail call, never persisted; `JobAttachment`, `src/services/resources/jobs.ts:224`). Up to 5 photos + 1 signature = at most 6 pages. A null/expired URL is already handled in the grids by the "Tap refresh" placeholder + refetch rule; the viewer inherits exactly that vocabulary.

**Product decisions locked (2026-09-14, via BMAD UX + research agents):**
- One pager including the signature (photos in arrival order, signature last). The grid fit difference (photos cover-fit squares, signature contain-fit on white) disappears in a viewer — full-screen viewers show everything aspect-fit; two viewers would duplicate all gesture/a11y logic for zero payoff.
- The signature renders on a **white card** inside the dark backdrop: signature ink is drawn for white paper; contain-fit on dark can drop pale strokes. The card preserves ink and still reads as "the signature document", matching its grid tile.
- Tappable = loaded confirmed photos + loaded signature ONLY. In-flight (mid-upload, pointer-events-none scrim), failed (its press IS the retry), add tile, and placeholder tiles must not open the viewer — one press target per tile, one meaning.
- No sharing, saving, editing, deleting, EXIF handling, prefetching, long-press shortcuts, or any action inside the viewer.

**Library verdict (BMAD research agent, 2026-09-14 — verified from the npm tarball, not docs):** `react-native-image-viewing@0.2.2` (jobtoday) is pure RN core JS — every import in `dist/` is `react`/`react-native`; zero runtime deps; MIT. Core `Modal` + `VirtualizedList` pager + `ScrollView`/`PanResponder`/`Animated` for pinch/double-tap/swipe-close. Pure JS = New Architecture safe by rule 4 of the CLAUDE.md library-research rule, no pod/gradle rebuild, no gesture-handler. Alternatives rejected: `react-native-gesture-image-viewer` (forces gesture-handler — a new native dep + rebuild, wrong trade for one screen) and `react-native-image-zoom` (no pager/modal — half a viewer left to build). Upstream is unmaintained since 2022-04-18 (86 open issues unanswered), so the source is **vendored into the repo** (~10 small TS files) rather than taken as a dependency — known bugs become in-repo debuggable problems, permanently under our control.

## Changes

fenzo-app only. One commit. **Zero new dependencies** (vendored MIT source; the only theme addition is one token).

### 1. NEW — `src/components/ImageViewer/` (vendored, Task 1)

Copy `react-native-image-viewing@0.2.2` `src/` (MIT — `ImageViewing.tsx`, `ImageViewing.android.tsx` / `.ios.tsx`, `components/ImageItem*`, `ImageLoading`, `hooks/*`, `utils/*`). Header comment on the barrel:

```
// VENDORED from react-native-image-viewing@0.2.2 (MIT, © JOB TODAY S.A.)
// https://github.com/jobtoday/react-native-image-viewing — upstream unmaintained
// since 2022. Local changes: (1) removed dead components/Modal overlay;
// (2) removed deprecated-SafeAreaView default header/footer; (3) added
// per-image onError → failure placeholder (upstream spins forever on error);
// (4) removed Dimensions-read remount trap — see AttachmentViewer.
```

- Keep the library's own behaviour: pinch (iOS `useZoomPanResponder`, Android `usePanResponder`), double-tap, swipe-to-close thresholds, `Modal onRequestClose` back handling.
- **Patch (required, AC5):** upstream `ImageItem` renders `ImageLoading` until `onLoad` and has NO `onError` path — a dead URL spins forever. Track load failure per image and render the failure placeholder (§3 styling) in its place. Keep the page swipeable while one page fails.
- Drop the `key={props.imageIndex}` remount trap at the wrapper level by never changing `imageIndex` while open (Task 3); the vendored source can stay as-is.

### 2. UPDATE — `src/theme/colors.ts` (Task 2)

```ts
// Full-screen image viewer backdrop — brand ink at 96%, essentially opaque.
backdropDark: 'rgba(17, 24, 39, 0.96)',
```

### 3. NEW — `src/components/AttachmentViewer.tsx` (Task 3)

```ts
type ViewerItem = { id: string; kind: 'photo' | 'signature'; url: string };
type Props = {
  visible: boolean;
  items: ViewerItem[];      // photos in arrival order, signature last (if present)
  initialIndex: number;     // index of the tapped tile
  onClose: () => void;
};
```

- Header: close `IconButton` (`X`, 24px, `colors.onPrimary`, target ≥ `touch.min`, `accessibilityLabel="Close"`, top-left inside `useSafeAreaInsets().top + spacing.s2`); centre counter "N of M" (`typography.label`, `colors.onPrimary`, `accessibilityLiveRegion="polite"`) — replaced by "Customer signature" on the signature page. Transparent header over `backdropDark`; no bar background.
- Signature page: white card (`colors.surfaceCard`, `radius.lg`, `spacing.s4` inset, `shadow.md`, image `contain` with `spacing.s2` padding). Photos: contain, centred, on `backdropDark`. Both under `statusBarHidden`.
- Failure placeholder: `colors.surfaceSunken` panel, `ImageOff` 20px `colors.textDisabled`, `typography.caption` `colors.textDisabled`, copy "Tap refresh" — identical to the grids' `Placeholder`.
- Loading: small `ActivityIndicator` `colors.onPrimary` until `onLoad`; the pager stays swipeable during load.
- Mount once per screen; open/close via `visible`; `initialIndex` set at open. If a snapshot index exceeds the item count at open, close gracefully (edge case §6.4 of the UX spec).

### 4. UPDATE — `src/features/technicianApp/components/PhotoSection.tsx` (Task 4)

- `ConfirmedTile`'s image branch gets the `Pressable` wrapper; a new `onViewPhoto?: (index: number) => void` prop (photo's index within the photo list) wired to it. `readOnly` terminal jobs behave identically — the viewer is read-only by nature.
- `InFlightTile`, `FailedTile`, `AddTile`: UNTOUCHED. The in-flight scrim keeps `pointerEvents="none"`; the failed tile's existing press stays the retry; the add tile stays the add affordance. No long-press-to-view anywhere — one press target per tile.

### 5. UPDATE — `src/features/technicianApp/components/SignatureTile.tsx` + `TechJobDetailContent.tsx` (Task 4)

- `SignatureTile`'s white card becomes pressable via a new optional `onView?: () => void`; the "Tap refresh" placeholder branch stays a plain `View`. URL-keyed remount (`key={signature.url ?? 'none'}`) untouched.
- `TechJobDetailContent` composes `items` (photos + last signature, arrival order) and owns the `<AttachmentViewer>` mount; the Re-capture ghost button stays exactly where it is, outside the card's press area.

### 6. UPDATE — `src/features/jobDetail/components/AttachmentGrid.tsx` (Task 5)

- Same treatment: `PhotoTile` image branch → `Pressable`; `SignatureTile` white card → `Pressable` (Re-capture button outside); placeholders stay plain; grid keys, `inRowsOfThree` chunking, and `onError → setFailed` logic byte-identical. Viewer state local to the component.

## Testing

- [x] Component: technician PhotoSection — confirmed tile press fires `onViewPhoto(i)`; in-flight/failed/add tiles render no new pressable (AC1, AC7) — `PhotoSection.test.tsx` (5 new tests, gallery describe)
- [x] Component: owner AttachmentGrid — photo + signature tiles press fires view callbacks; placeholder tiles inert (AC1, AC2, AC7) — `AttachmentGrid.test.tsx` (6 tests, NEW file)
- [x] Component: AttachmentViewer — renders header (close + counter), signature page card, spinner while loading, "Tap refresh" placeholder on failed image (AC4, AC5) — `AttachmentViewer.test.tsx` (12 tests, NEW file)
- [x] Unit: colors export includes `backdropDark` (AC token discipline) — `colors.test.ts`
- [ ] Manual on device (owner + technician, Android + iOS where possible): tap each tile type; swipe photo→photo→signature; pinch + double-tap + pan; swipe-to-dismiss (threshold + spring-back); hardware back; expired-URL page after 1h TTL; 1-photo job (counter hidden, single page); terminal read-only job; mid-upload job (in-flight tile inert); **Android pinch anchor (#226) and post-zoom recenter (#158) — if unacceptable, escalate to `@benschac/react-native-awesome-gallery` (Reanimated 4, New Arch) at the cost of adding gesture-handler**; swipe-to-close on RN 0.86 (#219 symptom); no flicker when opening (mount-once guard) *(pending — agent cannot run devices; see Completion Notes 12)*
- [x] Full suite (`bun run test`): baseline `main` (07989fa) already carries 31 pre-existing failures and 78 pre-existing `tsc --noEmit` errors (see story 7-10 Dev Agent Record) — the bar is "identical baseline failure set + all new tests passing", not a green suite — CONFIRMED: 31 failures / 7 suites, byte-identical baseline set (notifications models, legacy `__tests__`), none in story files; 791 passing includes all new tests; `tsc --noEmit` = 78 errors (exactly baseline count; the 6 story-introduced ones were fixed)

## Dev Notes

- **Relative imports everywhere** — no source file uses aliases (CLAUDE.md reality note 2026-09-09); match the surrounding code (`'../../../theme'` style from the feature components).
- **The flicker guard is the #1 integration trap.** Upstream remounts the whole viewer when the `imageIndex` prop changes (`key={props.imageIndex}`) — driving index from state causes the open issue #209 (image flicker on Android). Mount `<AttachmentViewer>` once with `initialIndex` fixed at open time; never update index while open. Swipes inside the viewer are internal to the library.
- **Status bar ownership:** the vendored lib's `StatusBarManager` hides the status bar for `presentationStyle="overFullScreen"` on Android and restores on unmount. The app must not also manage StatusBar for the same screen concurrently (double-hide/restore races).
- **No new native dependencies.** The vendored code imports only `react`/`react-native` core (verified by grep over the tarball dist). No gesture-handler, no pod/gradle rebuild. `reanimated` stays unused by this feature — do not add it for the vendored copy's sake.
- **Known upstream bugs accepted as trade-offs (Android-only, open since 2022/2025, unmerged PRs #191/#225):** pinch zooms from the image centre instead of the pinch point (#226) and the image can sit at top after zoom in/out (#158). iOS uses the smoother `useZoomPanResponder` path and is reportedly fine. These are documented, device-testable, and patchable in-repo precisely because the source is vendored. Escalation path if device testing fails: `@benschac/react-native-awesome-gallery`.
- **Presigned URLs are never persisted or passed between screens** — the viewer's `items` are built fresh from the current `detail.attachments` at open time. The viewer is a snapshot: if a confirm lands while it's open, the grid updates but the viewer keeps its snapshot; the user closes and re-taps (acceptable for ≤6 images, avoids mid-gesture list mutation).
- **Counter hidden when only one item** (single photo, no signature — or signature only). Label "Customer signature" still replaces the counter on that page.
- **Design system compliance:** tokens only (`colors.backdropDark` is the single addition), press-scale 0.97 with `motion.durationFast`/`easeStandard`, sentence-case copy ("Tap refresh", "Close", "Customer signature"), no emoji, ≥44px targets, `shadow.md` on the signature card.
- **Out of scope (do not build):** sharing/saving to gallery, editing/cropping/rotation, deletion, video, slideshows/auto-advance, EXIF correction, prefetch/caching layers, long-press shortcuts, owner re-capture changes (existing Re-capture button untouched), any backend change.

### Project Structure Notes

- `src/components/` is the documented home for app-specific reusable UI (JobCard, AnimatedBootSplash) — `AttachmentViewer.tsx` and the `ImageViewer/` vendored module live there, NOT under either feature folder, because both features import it.
- Vendored module mirrors the upstream file layout (`components/`, `hooks/`, `utils/`, barrel) so future cherry-picks of upstream fixes stay diffable; keep upstream copyright headers intact (MIT attribution).
- `features/` components stay dumb: they emit view callbacks; the viewer lives one level up (screen/feature content) exactly like `openMaps`/`copyPhone` wiring.

### References

- [Source: src/features/jobDetail/components/AttachmentGrid.tsx — PhotoTile/SignatureTile placeholders, chunking, Re-capture placement]
- [Source: src/features/technicianApp/components/PhotoSection.tsx — ConfirmedTile/InFlightTile/FailedTile/AddTile, MAX_PHOTOS]
- [Source: src/features/technicianApp/components/SignatureTile.tsx — white card, "Tap refresh" placeholder]
- [Source: src/services/resources/jobs.ts:224 — JobAttachment url presigned/never-persist rule]
- [Source: npm registry — react-native-image-viewing@0.2.2, peer deps react ≥16.11.0 / react-native ≥0.61.3, zero runtime deps, MIT]
- [Source: GitHub jobtoday/react-native-image-viewing issues #158, #209, #219, #226, #227 — accepted trade-offs and guards]
- [Source: src/theme/DESIGN_SYSTEM.md — token/motion/typography/touch rules]

## Dev Agent Record

### Agent Model Used

Claude Code session, model GLM-5.3-flash (cloud) — bmad-dev-story workflow, 2026-09-14.

### Debug Log References

- RED/GREEN per task; per-task runs: AttachmentViewer 12/12, colors.test 1/1, PhotoSection 5 new + 10 pre-existing green, SignatureTile 3/3, TechJobDetailContent 4 new + 12 pre-existing green, AttachmentGrid 6/6.
- Full suite `bun run test`: 93 suites (86 passed / 7 failed), 822 tests (791 passed / 31 failed) — failure set byte-identical to baseline main (07989fa): notificationBannerModel, notificationCardModel, useOwnerNotifications, StageStepper, notifications-screen, job-detail-screen, App — none touched by this story.
- `bunx tsc --noEmit`: 78 errors — exactly the baseline count; 6 story-introduced errors (AttachmentViewer ×3, AttachmentGrid ×2, TechJobDetailContent ×1) were caught and fixed during Task 6.
- Post-review re-run (2026-09-14, all 11 patches + both decisions applied): AttachmentViewer 15/15 (3 new tests), AttachmentGrid 7/7, SignatureTile 3/3, PhotoSection green incl. the new gating test, TechJobDetailContent green, colors.test green. Full suite re-run: 93 suites (86 passed / 7 failed), 827 tests (796 passed / 31 failed) — identical baseline failure set (31), 5 NEW passing tests, zero new failures. `tsc --noEmit`: 78 errors — exactly the baseline.
- Jest/Modal-mock note (exit-fade test): the jest Modal mock (`@react-native/jest-preset/jest/mocks/Modal.js`) hard-returns null on `visible === false` — on device the fade plays, under jest it cuts. The fade test therefore asserts the held-session prop (`animationType: 'fade'` + `visible: false` reaching the lib) instead of rendered sources during the window, then asserts release after the timer.
- Lint not runnable: `lint` script exists but no ESLint config is present (pre-existing gap, see story 7-10).
- Jest CLI note: jest 29 uses `--testPathPattern` (not `--testPathPatterns`).

### Completion Notes List

1. **Dependency instead of vendoring (deviation, user-directed):** the user installed `react-native-image-viewing@0.2.2` into `package.json`/`bun.lock` BEFORE dev started ("I am already installed this library"). Task 1's vendoring was reinterpreted as "take the dependency + a small bun patch". A patch over an already-user-approved dependency is not a HALT-triggering NEW dependency. The dead `components/Modal/` overlay and deprecated-`SafeAreaView` default header/footer from the vendoring plan are irrelevant — the npm dist tree has no such dead files to delete.
2. **The bun patch (`patches/react-native-image-viewing@0.2.2.patch`, 177 lines, 7 dist files)** adds what upstream lacks: (a) `ImageErrorComponent?: ComponentType` — AC5's failure placeholder (upstream spins forever on a failed image: no onError path at all); (b) `loadingColor?: string` — one brand spinner colour readable on both dark photo pages and the white signature page; (c) `getPageStyle?: (imageIndex: number) => ViewStyle` — per-page style so ONLY the signature page renders on the white card; (d) per-image `failed` state wired to `Animated.Image`'s `onError` in BOTH platform ImageItems (ios + android); (e) the lib's `if (!visible) return null` early-return removed (code review decision 2a) so `visible` reaches the Modal and closing plays the exit fade instead of a hard cut. **Spinner-colour DEVIATION from spec §3 (documented per code review 2026-09-14):** the spec named `colors.onPrimary` for the spinner; the code uses `colors.primary` via `loadingColor` — onPrimary is white and would vanish against the signature page's full-bleed white card, while brand primary reads on both the dark photo pages and the white card. The spec's onPrimary assumption predated the full-bleed signature-page deviation (Completion Note 4).
3. **Sandbox limitation (RESOLVED 2026-09-14):** bun's global-cache/tempdir writes are blocked in this session, so `bun patch`/`bun install` could not run; the patch was built manually (pristine cache copy → `git apply` → diff) with `patchedDependencies` added to `package.json` by hand. The user ran `bun install` outside the sandbox; the patch re-applied cleanly and node_modules was verified byte-identical to the patch's output against the pristine cache copy.
4. **Signature page: full-bleed white, not inset card (deviation):** the story's inset card (`radius.lg`, `spacing.s4` inset, `shadow.md`, inner padding) is NOT implementable through the lib's `getPageStyle` — the pager computes the image transform against SCREEN dimensions, so page margins/borderRadius would sit outside the transform area (image would overflow the card on zoom/pan). The patch's `getPageStyle` instead paints the full page `colors.surfaceCard` — the ink-contrast rationale (pale signature strokes on white) is fully preserved.
5. **Press feedback: opacity 0.85, not press-scale 0.97 (deviation):** AC6 explicitly permits "scale or opacity only"; opacity avoids adding a transform to tiles that already live in flex rows (scale would fight the flex layout's hit-slop edges).
6. **`viewerTotal` prop on PhotoSection:** the technician labels must match the viewer's counter, and the viewer list includes the signature page — so a 2-photo + signature job labels its tiles "View photo 2 of 3" (viewerTotal = viewer list length), while AttachmentGrid (which composes its own list) computes the same internally. Index mapping is unchanged: a photo's viewer index is its position among VIEWABLE photos (null-URL photos are excluded from both numbering and snapshot).
7. **Header top inset (revised 2026-09-14, code review decision 1a):** the header reads the iOS safe-area inset via `useSafeAreaInsets` (`insetTop + spacing.s5` on iOS; plain `spacing.s5` on Android where the lib's StatusBarManager already owns the status bar) and renders `<StatusBar hidden barStyle="light-content" />` on iOS while open — AC4's "status bar hidden" now holds on BOTH platforms (the lib's StatusBarManager returns null on iOS, so the app must manage it there; RN restores the previous bar state on unmount). SafeAreaProvider DOES reach the header: the app root mounts one (App.tsx) and `react-native-safe-area-context` context propagates into Modal children on iOS. Tests pin the padding with a zero top inset for determinism.
8. **Flicker guard (issue #209):** upstream remounts the whole viewer whenever `imageIndex` changes (`key={props.imageIndex}`). `AttachmentViewer` captures `{items, initialIndex}` ONCE per open (state keyed on `[visible]` only) and renders a `memo`ized `ActiveViewer`; parent re-renders and refetches mid-open cannot touch the pager. Covered by an explicit test.
9. **Single-item viewers hide the counter by design** (a "1 of 1" counter is noise); the close button marks open state in that case.
10. **Jest:** `react-native-image-viewing` (ESM `dist/`) was added to `jest.config.js`'s `transformIgnorePatterns`. Under `@react-native/jest-preset`'s Modal mock the whole pager renders, so the real library is exercised in tests; image loading itself never fires, so per-page states are driven via the Image's `onLoad`/`onError`. The AttachmentViewer suite emits a harmless `act()` warning from VirtualizedList's internal timer (upstream noise, suite passes).
11. **One test bug found and fixed during dev:** the TechJobDetailContent close test asserted a counter on a single-item viewer — the counter is hidden by design there; the test now asserts via the Close node.
12. **Manual device checklist is still pending** — the agent cannot run devices. Highest-risk upstream symptoms to verify on device: Android pinch anchor (#226), post-zoom recenter (#158), swipe-to-close (#219), no flicker on open.
13. **Relative imports** throughout (matching surrounding code; the CLAUDE.md alias mapping stays aspirational per the code-review reality note), tokens only — `colors.backdropDark`, `colors.primary`, `colors.onPrimary`, `colors.surfaceCard`, `spacing.*`, `radius.*`, `touch.min`, `typography.*` — no hardcoded design values.

### File List

- `patches/react-native-image-viewing@0.2.2.patch` (NEW — 7-file lib patch: ImageErrorComponent, loadingColor, getPageStyle, per-image onError; extended 2026-09-14 with the `visible` passthrough — the lib's `if (!visible) return null` early-return removed so the exit fade plays; 177 lines)
- `package.json` (MODIFIED — `patchedDependencies` + the library pinned to exact `0.2.2` per code review; the dependency itself was pre-installed by the user)
- `bun.lock` (MODIFIED — by the user's install; syncs on the pending `! bun install`)
- `jest.config.js` (MODIFIED — `react-native-image-viewing` in `transformIgnorePatterns`)
- `src/theme/colors.ts` (MODIFIED — `backdropDark` token)
- `src/theme/colors.test.ts` (NEW)
- `src/components/AttachmentViewer.tsx` (NEW — shared full-screen viewer)
- `src/components/AttachmentViewer.test.tsx` (NEW — 15 tests)
- `src/features/technicianApp/components/PhotoSection.tsx` (MODIFIED — `onViewPhoto`/`viewerTotal`, tappable ConfirmedTile)
- `src/features/technicianApp/components/PhotoSection.test.tsx` (MODIFIED — 6 new tests)
- `src/features/technicianApp/components/SignatureTile.tsx` (MODIFIED — `onView`, tappable captured branch)
- `src/features/technicianApp/components/SignatureTile.test.tsx` (NEW — 3 tests)
- `src/features/technicianApp/components/TechJobDetailContent.tsx` (MODIFIED — viewer state, viewerItems, viewer mount)
- `src/features/technicianApp/components/TechJobDetailContent.test.tsx` (MODIFIED — 4 new viewer tests)
- `src/features/jobDetail/components/AttachmentGrid.tsx` (MODIFIED — grid-owned viewer, tappable PhotoTile/SignatureTile)
- `src/features/jobDetail/components/AttachmentGrid.test.tsx` (NEW — 7 tests)
- `CLAUDE.md` (MODIFIED — "Library research — New Architecture first (MANDATORY)" rule; user-directed addition, declared in the File List per code review 2026-09-14)

## Change Log

- 2026-09-14: Story created (BMAD create-story, Ashish.kumar) — full-screen attachment viewer scoped as epic-9 story 9-1, frontend-only in fenzo-app. Design by BMAD UX agent (Sally); library verdict by BMAD research agent after tarball-level verification. No epics.md entry (epics 4+ are tracked as standalone story files per precedent).
- 2026-09-14: Implemented (BMAD dev-story, Ashish.kumar) — all 6 tasks done, status → review. DEVIATION: dependency + bun patch instead of vendoring (user pre-installed `react-native-image-viewing@0.2.2`); patch adds the AC5 onError path plus loadingColor and per-page getPageStyle. Further deviations documented in Completion Notes (full-bleed signature page, opacity press feedback, fixed header inset). Tests: all new suites green (27 new tests); full suite at identical baseline failure set (31); `tsc --noEmit` at exactly the 78-error baseline. Pending: user runs `! bun install` once (sandbox limitation) and the manual device checklist.
- 2026-09-14: Code review applied (BMAD code-review, Ashish.kumar) — all 11 review patches + both user decisions applied: iOS `<StatusBar hidden />` + safe-area-aware header inset (decision 1a), Modal kept mounted through the lib's `visible=false` exit fade (decision 2a; requires the patch to drop the lib's `if (!visible) return null` early-return), last-captured signature wins in the owner grid, negative-index stale-open guard, `useWindowDimensions` failure page, handler-gated imagebutton roles, `useCallback` onClose at both call sites, exact `0.2.2` pin, dead test helper removed, trailing newlines, spinner-colour deviation documented (Completion Note 2), spinner test added, CLAUDE.md declared in the File List. 2 defers recorded in deferred-work.md. Patch file regenerated to include the new hunk; story suites + full suite + tsc re-run against baselines (see Debug Log).
- 2026-09-14: Story completed and committed — user ran `bun install` (patch re-applied, verified byte-identical to the patch output); status → done; fenzo-app committed as `b1fc75a` on main. Remaining: manual device checklist (user-side) and this meta-repo artifacts commit.