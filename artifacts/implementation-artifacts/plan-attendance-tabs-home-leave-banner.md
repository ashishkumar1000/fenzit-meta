---
title: 'Attendance page as three tabs; Home leave-review banner'
type: 'feature'
ticket: ''
created: '2026-10-23'
status: 'built'
baseline_revision: '3fc75933e83098dab2fb60fb52d961d9c63eff47'
review: 'thorough'
review_source: 'pinned'
route: 'full'
route_source: 'pinned'
review: ''
review_source: ''
lenses_ran: []
review_loop_iteration: 0
context:
  - 'artifacts/specs/spec-attendance-tabs-home-leave-banner/SPEC.md'
  - 'artifacts/specs/spec-attendance-tabs-home-leave-banner/ui-map.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** The owner's Attendance footer-tab page makes the three daily reads (Today / Monthly / Leave) a two-tap drill via tiles, and pending leave decisions surface on Home only as a thin pointer row. Per SPEC-attendance-tabs-home-leave-banner (contract) the page becomes a segmented Today | Monthly | Leave control (Today active on entry, Leave carrying a red pending badge), and Home gets a leave-hue banner "N leave requests / Action pending approval" with an explicit Review button.

**Approach:** Re-render `AttendanceTabHomeScreen` with the DS `SegmentedControl` switching the three existing leaf screens in place (conditional render, `embedded` prop hides their back headers / top SafeArea); Review navigates to the `Attendance` tab route with `{ tab: 'leave' }`. Restyle the shipped `LeaveReviewStrip` into the banner (visual supersession of 20-1 AC 12 inside this story). App-only; no backend change — the count rides the `/users/me` mirror.

## Boundaries & Constraints

**Always:**
- The shipped setup banner behaviour stands unchanged (one light `GET /attendance/setup` per focus, latest-wins, owner-only, silent on failure) and sits above the segmented control.
- Viewer (`canWrite=false`) gets exactly Today + Monthly — no Leave tab, no badge, no banner, no gate GET.
- Leaf screens keep working as pushed root-stack screens (dual-hosting); badges/params only affect the tab page.
- Design-system tokens only; ≤300 lines/file; explicit loading/empty states preserved (panes keep their own).
- Badge count = mirror `pendingLeaveRequests`, absent at 0; refreshes on focus.

**Never:**
- No backend/API/deep-link change; no leaf-screen content redesign; no setup-state change; no hub/footer/Customers/technician change; no Home restructure beyond the banner.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Owner enters tab page | setup done, N≥0 | Today pane active, segmented control, no setup banner | Panes own their load/error postures |
| Owner taps Monthly / Leave | pane switch | Content swaps in place; leaf screen mounts fresh (its focus-fetch runs) | Pane's own error/retry UI |
| Review from Home | N>0, admin, attendanceEnabled | Lands on Attendance tab with Leave pre-selected | none |
| Review param while page already mounted | tab:'leave' | Effect selects Leave, then clears the param (next Review still works) | invalid/absent param ignored |
| Badge | count 2 | Red badge "2" on Leave segment; absent at 0 | absent mirror → no badge |
| Viewer | canWrite=false | Today+Monthly segments only; no badge/banner/gate GET | — |
| Failed focus GET | network/403 | Page renders without setup banner; tabs unaffected | silent |
| Setup incomplete owner | setupCompletedAt null | Banner above segmented control → wizard | — |

</frozen-after-approval>

## Code Map

- `src/features/attendance/home/AttendanceTabHomeScreen.tsx` — the page to convert: keep header + gate GET (gateSeqRef latest-wins) + setup banner Tile; replace Eyebrow+3 Tiles with SegmentedControl + active pane.
- `src/components/ui/SegmentedControl.tsx` — already supports `badge?: number` (red pill); needs an optional `icon` on `SegmentOption` (additive, mockup's calendar glyphs).
- `src/features/attendance/dashboard/AttendanceDashboardScreen.tsx` — pane 1: hide `DashboardHeader` (back+refresh; pull-to-refresh already exists, AC 15) and drop `edges={['top']}` when embedded.
- `src/features/attendance/monthly/AttendanceMonthlyScreen.tsx` — pane 2: hide `ScreenHeader`, same edges rule.
- `src/features/attendance/leave/OwnerLeaveScreen.tsx` — pane 3: hide `ScreenHeader` (the "Apply on behalf" CTA lives in the FlatList ListHeader, unaffected); viewer branch keeps its guard; embedded starts at 'pending' and must NOT consume `route.params.tab` (param collision with the page-level param — consume effect stays pushed-mode only).
- `src/navigation/types.ts` — `MainTabParamList.Attendance: undefined` → `{ tab?: 'today' | 'monthly' | 'leave' } | undefined`.
- `src/screens/HomeScreen.tsx` — `handlePressLeaveStrip` → `navigate('Attendance', { tab: 'leave' })`; strip gating (`isAdmin && attendanceEnabled && N>0`) unchanged.
- `src/features/home/components/LeaveReviewStrip.tsx` + `src/features/home/components/TodaysJobsSection.tsx` — strip → banner (leave-hue Card, glyph, "N leave requests" / "Action pending approval", Review button = sole press target); rename file/component to `LeaveReviewBanner`.
- `src/features/profile/useMyProfile.ts` — shared store: tab page subscribes for the badge; `loadMyProfile()` (throttled) on focus refreshes the count. Do NOT modify.
- Tests to update WITH the change (requirement superseded, not weakened): `AttendanceTabHomeScreen.test.tsx` (tiles→tabs), `TodaysJobsSection.leave.test.tsx` + `LeaveReviewStrip.test.tsx` (strip anatomy→banner).

## Tasks & Acceptance

**Execution:**
- [ ] `src/navigation/types.ts` — add the tab param type — Review target.
- [ ] `src/components/ui/SegmentedControl.tsx` — optional `icon?: ReactNode` before label — mockup glyphs, backward-compatible.
- [ ] `src/features/attendance/dashboard/AttendanceDashboardScreen.tsx` — `embedded?: boolean`: skip header, `edges={embedded ? [] : ['top']}` — dual-hosting.
- [ ] `src/features/attendance/monthly/AttendanceMonthlyScreen.tsx` — same — dual-hosting.
- [ ] `src/features/attendance/leave/OwnerLeaveScreen.tsx` — same + pushed-only param consume; initial tab from prop when embedded — dual-hosting.
- [ ] `src/features/attendance/home/AttendanceTabHomeScreen.tsx` — SegmentedControl (badge via `useMyProfile` + focus `loadMyProfile()`), conditional active pane, param consume-then-clear effect, `today|monthly|leave` state — CAP-1/CAP-3.
- [ ] `src/features/home/components/LeaveReviewBanner.tsx` (renamed) + `TodaysJobsSection.tsx` + `src/screens/HomeScreen.tsx` — banner visual + Review target — CAP-4.
- [ ] Update the three superseded test files to the new requirement (explicit note: requirement changed; assertions follow the requirement).
- [ ] `artifacts/specs/spec-attendance-tabs-home-leave-banner/.memlog.md` — build events appended (meta repo).

**Acceptance Criteria:**
- Given owner (setup done), when the Attendance tab opens, then Today's dashboard renders beneath an active "Today" segment with no tiles and no navigation push.
- Given owner taps Review on Home with N=2 pending, when it lands, then the Attendance tab shows the Leave pane with badge "2"; deciding both clears the badge on next focus.
- Given viewer, when the Attendance tab opens, then exactly Today+Monthly render; given N=0 or absent mirror or non-admin, Home renders no banner.
- Given pushed entries (Home pulse card → AttendanceDashboard; deep links → OwnerLeave), when used, then headers/back/SafeArea behave exactly as shipped.

**Named tests (write AFTER user confirms on device, per test-timing rule):**
- tab page: entry defaults Today; Review param lands Leave and is consumed (`setParams({ tab: undefined })`); badge mirrors count / absent at 0; viewer sees two segments; failed gate GET is silent.
- banner: renders at N>0 with count; absent at 0/non-admin; Review navigates with tab:'leave' (HomeScreen boundary).
- leaves: one embedded-mode render per leaf asserting the pushed header is absent and SafeArea `edges` is `[]` (added by review pass 1).

## Implementation Notes

- Checkpoint 1 satisfied by the owner's explicit "start development" instruction (2026-10-23); status set in-progress without a second halt.
- Verification: `bunx tsc --noEmit` clean (no tsc script exists in package.json); `bun run lint` fails pre-existing (no eslint config ever tracked — identical on untouched baseline); `bun run test` 292/292 suites, 3797/3797 tests green.
- Review pass 1 (thorough: edge-case-hunter + verification-gap) triaged 7 findings → 2 patches (setParams optional-call per the file's own no-op contract; forced profile-store refresh on leave-decision success so the badge/banner clear as decisions land), 1 false, 4 deferred (test-timing rule). Patches applied by the step-3 agent; full suite re-run after.
- Device verification (2026-10-23, Pixel 6 via uiautomator2, metroDebug @ Metro): three segments with calendar glyphs + red Leave badge "1" (real pending request, Nisha · EMP-004); in-place Monthly/Leave pane swaps with no back header and the footer tab bar intact; Review on Home's banner lands the tab pre-selected to Leave (proven with Today seeded first); the consumed param does not fight manual taps (Today persists across tab re-entry). Found + fixed during verification: the banner was unreachable on a FIRST-RUN Home (Ac Mantra has no jobs yet — HomeScreen's first-run branch never rendered TodaysJobsSection, where the banner lived; the 20-1 strip had the same hole). Patch: first-run branch renders LeaveReviewBanner when the count > 0; verified live on device, then re-verified after restart.
- Post-device test pass (owner-directed check complete): 18 tests added — Review-param seed/consume/garbage/re-seed, badge count/zero/absent-mirror, Home banner first-run + singular + zero + absent + established + `navigate('Attendance', { tab: 'leave' })` boundary, one embedded-chrome test per leaf (header absent, SafeArea edges `[]`). tsc clean; full suite 292/292 suites, 3815/3815 tests green. The four verification-gap deferrals from pass 1 are closed.

## Plan Change Log

## Review Triage Log

- Pass 1 (2026-10-23, thorough). Verdicts: 0 high, 1 medium, 1 low, 1 false, 4 defer-as-filed (verification gaps, pre-verified).
- edge-case-hunter: viewer arrives with valid `tab:'leave'` param → blank page — **false** — the only `navigate('Attendance', { tab })` call site is Home's Review handler, rendered only for admin + enabled + N>0; a viewer cannot produce the param (role is per-session, no deep links carry it).
- edge-case-hunter: `setParams` unguarded vs the file's documented outside-navigator no-op contract — **low** — contract break is real but unreachable in the app; one-char optional-call fix → **patched**.
- edge-case-hunter (claim): "deciding both clears the badge on next focus" — **medium** — verified real: `runWrite` success refreshes only the leave queue; the shared profile mirror (badge + Home banner) stays stale until an unrelated >15s-later refetch, contradicting the spec's "badge clears as decisions land" → **patched** (forced `loadMyProfile({ force: true })` on decision success).
- verification-gap: HomeScreen Review routing (`navigate('Attendance', { tab: 'leave' })`) asserted by no test — real gap — → **defer**: writing it now is forbidden by the house test-timing rule (implement → user confirms on device → tests); already named in the plan's Named tests.
- verification-gap: tab-page param seed/consume-then-clear untested — same → **defer** (named in plan).
- verification-gap: badge computation + focus refresh untested — same → **defer** (named in plan).
- verification-gap: leaf screens' `embedded` chrome-drop never rendered by any test — same → **defer**; **added to the plan's Named tests** (was missing there).

- Pass 2 (2026-10-23, device verification on Pixel 6 + post-device test pass). Verdicts: 1 finding, patched.
- device-check (not a lens): CAP-4 banner unreachable on a first-run Home (technicians but zero jobs → HomeScreen's first-run branch renders NoJobsCard only; the banner lived in TodaysJobsSection) — **medium** — verified live: badge showed 1 while Home showed no banner; every everyday owner meets it before their first job → **patched** (first-run branch renders LeaveReviewBanner when count > 0; barrel export added; device-verified, then covered by tests in the post-device pass). The four pass-1 test deferrals are closed by the post-device pass.

## Design Notes

- Pane switching = conditional render: each leaf screen's `useFocusEffect` fires on mount within the focused tab → "first focus is the initial load" holds per pane entry; no navigator rewiring, no new dependency (mockup's pill = the DS control).
- The tab page passes its composite `navigation` down to panes (they push `AttendanceEmployeeMonth` / `ApplyOnBehalf` onto the root stack exactly as pushed screens do). If tsc rejects the composite→stack assignment, one local, commented cast in the tab page — never `any` in the leaf screens.
- Badge gate mirrors HomeScreen's strip shape (fail-hidden `?? 0`); Leave segment exists only for `canWrite`.

## Verification

**Commands:**
- `cd workspace/core/frontend/fenzit-app && bun run lint` (or repo's tsc script) -- expected: clean
- `cd workspace/core/frontend/fenzit-app && bun run test` -- expected: all suites green (superseded tests updated, none weakened)
- Device: Pixel 6 via uiautomator2 — tab page shows three segments, Today active; Review lands Leave with badge; viewer path untestable on this device (owner account) — code-inspected only.

## Code Review

### 2026-10-23 (post-device /bmad-code-review, thorough: edge-case-hunter + verification-gap)

**Code review complete.** 0 decision-needed, 4 patch (applied), 2 defer, 1 rejected.

- [x] [Review][Patch] Decision-success mirror refresh unasserted — deleting `loadMyProfile({ force: true })` from the runWrite success path passes every suite; the approve and revoke success tests now assert the call [src/features/attendance/leave/OwnerLeaveScreen.test.tsx]
- [x] [Review][Patch] Tab-page focus mirror refresh unasserted — the focus listener's `loadMyProfile()` had no observer; a fireFocus test now asserts it [src/features/attendance/home/AttendanceTabHomeScreen.test.tsx]
- [x] [Review][Patch] A live role demotion strands a blank pane — sessionSync rewrites the session role on foreground, so `canWrite` can flip while `activeTab` is 'leave' (also reachable at mount via a viewer + `tab:'leave'` param): no pane rendered, no segment selected. Fixed with a derived clamp `visibleTab`, plus a demotion test [src/features/attendance/home/AttendanceTabHomeScreen.tsx]
- [x] [Review][Patch] Strip-naming drift — `onPressLeaveStrip`/`handlePressLeaveStrip` renamed to `…LeaveBanner` across TodaysJobsSection, HomeScreen and their tests [src/features/home/components/TodaysJobsSection.tsx]
- [x] [Review][Defer] SegmentedControl `icon` rendering has no observer [src/components/ui/SegmentedControl.tsx] — deferred: decorative glyphs, no functional contract; pin when the control gets its own suite
- [x] [Review][Defer] Review button loses the strip's count-bearing a11y label [src/features/home/components/LeaveReviewBanner.tsx] — deferred: restoring it needs `accessibilityLabel` forwarding on the DS Button (public surface; the `accessibilityState` precedent), a DS-extension decision; the count text stays adjacent and focusable meanwhile

**Rejected**
- sm button below the 44px touch floor (deletion finding) — **false**: Button's own docs declare "md/lg meet the 44px touch-target minimum" — sm (36px) is the documented compact size, used as a sole/compact press target across the attendance settings; the mockup's compact Review button replaced the old whole-row pointer deliberately.

Verification after patches: `bunx tsc --noEmit` clean; full suite 292/292 suites, 3817/3817 tests green.
