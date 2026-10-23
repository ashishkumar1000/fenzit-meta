---
title: 'Owner footer restructure — Attendance tab replaces Customers'
type: 'feature'
ticket: ''
created: '2026-10-23'
status: 'built'
review: 'thorough'
review_source: 'auto'
baseline_revision: 'bf1ce379fb09b476df33b90dd90160929b8aa99b'
route: 'full'
route_source: 'auto'
review: ''
review_source: ''
lenses_ran: ['blind-hunter', 'edge-case-hunter', 'verification-gap', 'intent-alignment']
review_loop_iteration: 0
context:
  - '{project-root}/artifacts/specs/spec-owner-footer-attendance-nav/SPEC.md'
  - '{project-root}/artifacts/specs/spec-owner-footer-attendance-nav/nav-map.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** Attendance — the owner's daily surface — sits three taps deep (Account → Attendance → tile), while Customers occupies a permanent footer slot it doesn't earn. The owner footer wastes its highest-value slot.

**Approach:** Make the footer Home / Jobs / Attendance / Account (spec CAP-1). The new Attendance tab page carries the three existing tiles — Today, Monthly, Leave — plus a setup banner for incomplete-setup owners (CAP-2/3). Customers becomes a stacked screen opened from the Account tab's Customers row (CAP-4), the attendance hub becomes setup-only with its wizard gate intact (CAP-5), and Home's two attendance entries split targets — pulse card → Dashboard, plain tile → the tab (CAP-6, owner decision 2026-10-23). App repo only.

## Boundaries & Constraints

**Always:**
- Nav-level change only; reuse every existing screen/route unchanged (Dashboard, Monthly, OwnerLeave, wizard, offices/enrolments/weekly-off/holidays, CustomersScreen).
- Viewer visibility: `canWrite` gates the Leave tile and all setup surfaces; viewers see Today + Monthly on the tab page; the Account → Attendance row stays visible to all roles (viewers see only the view-only notice on the hub).
- The hub's focus gate is preserved verbatim: focus GET `/attendance/setup` → `replace('AttendanceSetupWizard')` while `setupCompletedAt === null` (owner-only, focused-check, latest-wins; any failure = no redirect).
- The stacked customer list keeps the route name `Customers` (`AddCustomerReturnRouteName` contract, types.ts:286).
- Banner posture mirrors the hub gate: latest-wins focus GET, silent on failure, never a redirect.

**Never:**
- No backend, fenzit-be, or fenzit-web changes; no technician-tab changes (TechnicianTabs untouched).
- No redesign of the Dashboard/Monthly/Leave screens; no embedded attendance content on the tab page (tiles only).
- No wizard auto-redirect from the Attendance tab page.
- No changes to Account rows other than the Attendance row's subtitle.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Owner taps Attendance tab, setup complete | focus GET `setupCompletedAt` set | Today/Monthly/Leave tiles; no banner | No error expected |
| Owner taps Attendance tab, setup incomplete | focus GET `setupCompletedAt` null | Tiles + prominent tappable setup banner → pushes `AttendanceSetupWizard` | GET failure: no banner, page renders, never redirects |
| Viewer taps Attendance tab | `canWrite` false; GET 403s | Today + Monthly only; no Leave, no banner | Silent failure (hub-gate posture) |
| Owner taps Account → Attendance, incomplete setup | focus GET incomplete | Existing gate replaces hub with wizard | Failure: hub renders (unchanged) |
| Account → Customers tap | row tap | Stacked list pushes with back affordance; back returns to Account | No error expected |
| Add customer from stacked list | Save with `returnRouteName: 'Customers'` | Returns to the stacked list (same route name) | Unchanged flow |
| Home today-pulse card tap | Enrolled tenant, pulse ready | `AttendanceDashboard` opens | Unchanged pulse failure fallback: plain tile |
| Home plain Attendance tile tap | Enrolled tenant, pulse not ready/failed | Attendance tab page opens (subtitle "Today, monthly & leave") | No error expected |

</frozen-after-approval>

## Code Map

- `src/navigation/MainTabs.tsx` -- the owner tab set; swap Customers → Attendance (new screen), fix order + doc comment.
- `src/navigation/types.ts` -- `MainTabParamList` (drop `Customers`, add `Attendance: undefined`); `RootStackParamList` (add `Customers: undefined`); `AddCustomerReturnRouteName` untouched.
- `src/navigation/RootNavigator.tsx` -- register stacked `Customers` route; import `CustomersScreen` from `../features/customers` (check `index.ts` export); update the "four bottom-tab screens" comment.
- `src/navigation/TabBar.tsx` -- `ICONS` already maps `Attendance → CalendarCheck` (shared with technician tabs); remove the now-unused `Customers: Users` entry + `Users` import.
- `src/features/attendance/home/AttendanceHomeScreen.tsx` -- source of the tile/eyebrow/banner vocabulary to reuse (`Tile`, `Eyebrow`, `InlineNotice`, `gateSeqRef` latest-wins focus pattern, `goBackSafely`); strip its "Every day" section, keep gate + `justEnabled` flash + view-only notice + "Set up" section; update doc comment + icon imports (`CalendarDays`/`Calendar` still used by setup tiles; drop `LayoutDashboard`/`CalendarOff`).
- `src/features/customers/CustomersScreen.tsx` -- header is title + Add button, no back; needs a back affordance now that it stacks (pattern: `goBackSafely` — `goBack()` or fall back to `navigate('MainTabs')`). All list/store logic unchanged.
- `src/features/more/MoreScreen.tsx` -- Attendance row subtitle → setup-focused copy; `navigate('Customers')` / `navigate('AttendanceHome')` targets stay valid (Customers resolves to the root stack; MoreScreen nav type is already composite).
- `src/features/customers/index.ts`, `src/features/attendance/home/index.ts` -- export surface updates.
- `src/screens/HomeScreen.tsx` -- TWO hub entries to retarget (CAP-6, build-review finding): `TodayPulseCard` onPress → `navigate('AttendanceDashboard')`; `plainAttendanceTile` onPress → `navigate('Attendance')` with subtitle → "Today, monthly & leave". Its tests (HomeScreen.test.tsx) pin `navigate('AttendanceHome')` today.
- `src/App.tsx` -- stale comment "MainTabs' Jobs/Customers/More routes" (~line 138) to update.
- Tests co-located per screen (react-test-renderer + jest): `AttendanceHomeScreen.test.tsx` (gate pattern + navigation mocks to copy), `MoreScreen.test.tsx` (asserts row targets), `CustomersScreen.test.tsx`. No existing test renders `MainTabs` — the plan adds a composition test.

## Tasks & Acceptance

**Execution:**
- [ ] `src/navigation/types.ts` -- param-list changes (drop tab `Customers`, add tab `Attendance`, add stack `Customers`) -- type-level restructure first; TS drives the rest.
- [ ] `src/features/attendance/home/AttendanceTabHomeScreen.tsx` + `AttendanceTabHomeScreen.test.tsx` -- NEW tab screen (basename `AttendanceTabScreen` is the technician tab screen in `features/attendance/me/`): own title-only header (do NOT touch shared `ScreenHeader` — its `onBack` is required; HomeHeader is the tab-root precedent), "Every day" eyebrow, three tiles (Today→`AttendanceDashboard`, Monthly→`AttendanceMonthly`, Leave→`OwnerLeave` owner-only), setup banner (tappable `Tile` with `CalendarCheck` medallion, above the eyebrow, only when owner && `setupCompletedAt === null`; focus GET copied verbatim from the hub INCLUDING the `if (!canWrite) return;` viewer skip; silent failure, never redirects). Tests: tiles render + navigate; banner shows/navigates/absent-on-complete/absent-on-GET-failure/absent-for-viewer.
- [ ] `src/navigation/MainTabs.tsx` -- four tabs Home/Jobs/Attendance/More(Account) -- the footer itself.
- [ ] `src/navigation/RootNavigator.tsx` + `src/features/customers/index.ts` + `src/features/attendance/home/index.ts` -- stacked `Customers` route + exports -- relocation of the list.
- [ ] `src/navigation/TabBar.tsx` -- drop `Customers: Users` + unused import; confirm `Attendance` icon works for owner tabs too -- shared-bar hygiene.
- [ ] `src/features/attendance/home/AttendanceHomeScreen.tsx` + test -- setup-only hub (remove Today/Monthly/Leave tiles + eyebrow; keep gate/flash/notice/Set-up; doc comment updated) -- CAP-5.
- [ ] `src/features/customers/CustomersScreen.tsx` + test -- back affordance prepended to the EXISTING header row (ChevronLeft IconButton; `goBackSafely`); Add button and list logic unchanged -- stacked-screen contract.
- [ ] `src/screens/HomeScreen.tsx` + `HomeScreen.test.tsx` -- pulse card → `AttendanceDashboard`, plain tile → `Attendance` with new subtitle; pin both in tests -- CAP-6.
- [ ] `src/navigation/MainTabs.test.tsx` (NEW) -- renders the four tabs in order with labels Home/Jobs/Attendance/Account -- CAP-1 has no other automated check.
- [ ] `src/App.tsx` -- update the stale "Jobs/Customers/More" comment -- comment-only, prevents future misdirection.
- [ ] `src/features/more/MoreScreen.tsx` + test -- Attendance row subtitle → "Offices, team, weekly off & holidays"; assert row targets still `Customers`/`AttendanceHome` -- copy + regression.
- [ ] Whole repo -- grep for any remaining `navigate('Customers')` / tab-route references (incl. `navigationRef.ts`) and update stragglers -- no orphaned tab navigations.

**Acceptance Criteria:**
- Given the owner app, when any tab is focused, then the footer shows exactly Home, Jobs, Attendance, Account in that order.
- Given an owner with completed setup, when the Attendance tab is tapped, then Today/Monthly/Leave open AttendanceDashboard/AttendanceMonthly/OwnerLeave respectively.
- Given an owner with incomplete setup, when the Attendance tab is focused, then the setup banner renders, tapping it opens the wizard, and no auto-redirect occurs; when the GET fails, the banner is absent and the page still renders.
- Given a view-only user, when the Attendance tab is focused, then Today and Monthly render and Leave and the banner do not.
- Given any user, when Account → Customers is tapped, then the list pushes as a stacked screen with a working back affordance; Add → save returns to it.
- Given an owner with incomplete setup, when Account → Attendance is tapped, then the wizard replaces the hub exactly as today.
- Given a technician session, when the app renders, then TechnicianTabs are unchanged.
- Given an enrolled tenant on Home, when the today-pulse card is tapped, then AttendanceDashboard opens; when the plain Attendance tile is tapped, then the Attendance tab page opens.

## Implementation Notes

## Plan Change Log

## Review Triage Log

Pass 1 (thorough: blind-hunter, edge-case-hunter, verification-gap, intent-alignment). Verdicts: 2 medium, 10 low, 10 false, 1 defer-route; 0 maybe-false.

- B1 blind-hunter "tab has no tenant-module gate" — **false** — the owner explicitly chose the always-visible tab with a setup banner over hiding/gating (decision 2026-10-23); pre-change hub tiles were equally ungated for enabled-false tenants; the banner covers never-setup tenants.
- B2 blind-hunter "tile-order contract deleted, not re-pinned" — **medium** — verified via gap lens demonstration: reordering tiles keeps every suite green; the deleted hub test was the only order pin. → patch.
- B3 blind-hunter "stale viewer comment in AttendanceHomeScreen" — **low** — verified present at lines 46-48, still describing Today/Monthly reads that moved away. → patch.
- B4 blind-hunter "pulse card lost setup-gate safety" — **false** — CAP-6 prescribes exactly this target (owner decision); pulse-ready + setup-incomplete requires the backend to serve pulse data for an un-setup tenant, and pulse failure falls back to the plain tile.
- B5 blind-hunter "banner first-paint window" — **false** — the designed posture (banner, never a gate/redirect, owner decision); an optimistic banner would flash for completed-setup owners; the hub renders its shim pre-redirect the same way.
- B6 blind-hunter "wizard completion strands owner on setup-only hub" — **low** — pre-existing wizard completion behavior (non-goal: no wizard changes); the hub shows the just-enabled flash and setup tiles, back returns to the tab. → defer.
- B7 blind-hunter "no test exercises the root-stack Customers registration" — **medium** — pre-verified by gap lens: deleting the registration keeps all 291 suites green; MoreScreen's navigate absorbs into a mock. → patch.
- B8 blind-hunter "Customers row behavior change undocumented" — **low** — comment-only; sibling Attendance row carries an explanatory block. → patch.
- B9 blind-hunter "viewer hub dead-end, no signpost" — **false** — the owner explicitly decided the viewer hub shows "just a view-only notice and no tiles" (2026-10-23).
- B10 blind-hunter "near-collision naming" — **false** — the name is the deliberate least-collision choice (technician screen owns `AttendanceTabScreen.tsx`); index.ts documents the rule.
- B11 blind-hunter "stale TabBar.test fixtures" — **low** — verified: fixture renders a footer that no longer ships (Customers falls back to HomeIcon); tests pass via fallback. → patch.
- B12 blind-hunter "banner icon chip invisible (surfacePage on surfacePage)" — **low, rejected** — matches the hub's Team-attendance tile vocabulary deliberately; visual quality is judged in the on-device pass, not by test assertion.
- E1 edge-case-hunter "deep-link fallback pushes MainTabs above Customers" — **low, rejected** — hypothetical (no deep-link config exists); the identical idiom ships in AttendanceHomeScreen/HolidaysScreen; "fixing" one screen diverges from the repo-wide pattern.
- E2 edge-case-hunter "setState after unmount" — **false** — React 18+ no-ops unmounted setState; no user-visible outcome.
- E3 edge-case-hunter "hanging GET freezes banner" — **false** — speculative (requires every GET to hang); identical exposure in the hub gate since inception; refocus re-GETs.
- E4 edge-case-hunter "isFocused guard dropped vs 'copied verbatim' claim" — **low** — verified: hub guards its decision with `navigation.isFocused()`, the tab copy does not; consequence is a transient banner flip while unfocused, self-correcting on refocus; one-line direct correction. → patch.
- V1 verification-gap "RootNavigator Customers registration untested" — **medium** — pre-verified with demonstration and disposition patch. → patch (same root cause as B7).
- V2 verification-gap "tile-order pin missing" — **medium** — pre-verified with demonstration and disposition patch. → patch (same root cause as B2).
- V3 verification-gap "pulse card + incomplete setup" — **false** — same refutation as B4.
- V4 verification-gap "TabBar fixture stale" — **low** — same as B11. → patch.
- INTENT intent-alignment report — descriptive, no defect findings: reading R1 (full restructure) implemented and extended to viewers per the recorded decisions; its D1/D5 cross-surface-test observations route under B7's patch; D2 (move-by-recreation tiles) and D3/D4 are confirmed intended behavior.

Grouped entries: [RootNavigator-registration-untested: B7+V1 (+INTENT D1/D5), medium → patch] · [tile-order-pin: B2+V2, medium → patch] · [isFocused-guard: E4, low → patch] · [stale-hub-comment: B3, low → patch] · [customers-row-comment: B8, low → patch] · [tabbar-fixture: B11+V4, low → patch] · [wizard-landing: B6, low → defer]. No intent_gap, no bad_plan → no loopback.

## Verification

**Commands:**
- `cd workspace/core/frontend/fenzit-app && bun run lint` -- expected: no errors
- `bun run test` (jest) -- expected: all suites pass, incl. the new AttendanceTabScreen suite
- `bunx tsc --noEmit` -- expected: no type errors

**Manual checks (on the attached phone, debug build + Metro for hot reload):**
- `bun run android` -- walk the ACs: footer order, tiles, banner (simulate incomplete setup only if a test tenant is available), viewer role, customers push/back, hub gate, technician tabs.
