# Attendance office setup: device walkthrough and UX findings (rev 4)

Device: Pixel 6 (Android), fenzit-app build on device, 2026-10-18.

Sources, merged in this revision:
- **Walkthrough A** (first run, wizard path): Account & settings → Attendance → setup wizard → Offices → Add office → steps 2–5 → Enable attendance → Settings. Evidence: `scratchpad/flow/`.
- **Code check** (BMAD review, adversarial + edge-case lenses): each claim checked against `fenzit-app/src/features/attendance/`.
- **Walkthrough B** (independent agent, no sight of A's findings; setup already complete, so it tested Offices, forms, picker, roster, Settings, holidays, failure paths). Evidence: `scratchpad/fresh/`.

Evidence folders, absolute: `/private/tmp/claude-501/-Users-admin-workspace-fenzit-meta/9e1c84e0-8821-49f5-b4d1-868e7627612d/scratchpad/flow` and `.../scratchpad/fresh`.

Status key: **Confirmed** = seen on device (and code where noted). **Code-only** = supported by source, not re-seen after the change. **Suspected** = needs a repro.

## Corrections to rev 1
- Former finding "Track attendance for X doesn't show state" is **withdrawn**. That text is the switch's label. After waiting 6 s the status text and switch matched; the rev 1 dump was stale.
- Former finding "radius not carried back" was **wrong about the data**: the form stores the radius (`OfficeFormScreen.tsx:107`). The real gap is that no form screen displays it (finding 4).
- Former finding "GPS Verified after a drag" is **not a clean bug**. Code clears the badge on a manual pan (`MapPinPickerScreen.tsx:185`) and B saw it absent after a drag. The real problem is that it is unpredictable without a drag (finding 7).

## What works
- Setup gate sends an owner with no setup to the wizard. Continue on step 1 is disabled and says why.
- Empty submit shows both the name and pin errors. A whitespace-only name is rejected; leading spaces are trimmed.
- Duplicate name (any case, trailing spaces) shows "That name is already used by another office".
- Airplane mode on Create shows "Could not reach the server. Check your connection and try again." A triple tap on Create after reconnecting made one office, not three.
- Rotation and backgrounding keep the form. Font scale 1.3 was clean.
- Step 4 offers Continue and "Skip for now". Enable attendance completes setup and lands on Attendance home.
- Status text and switch agree on employee rows once the write settles.

## Findings

| # | Sev | Status | Where | Finding | Evidence |
|---|---|---|---|---|---|
| 1 | High | Code-only (seen in A) | Offices route opened from wizard step 1, zero offices | Empty state broken: icon floats over the header, title, description and chrome missing. Cause: `EmptyState` root is `flex: 1` (`EmptyState.tsx:97`) inside `styles.content`, which has no flex (`OfficesScreen.tsx:116`). B could not re-test (offices exist). No jest test can catch a layout collapse. | flow/w_offices_route.png/.xml |
| 2 | High | Confirmed (A+B+code) | Add/Edit office, all text fields | Errors do not clear when the value becomes valid: name, late, half-day, and the duplicate-name error all stay until the next Create tap. Cause: `onChange` (`OfficeFormScreen.tsx:67`) never touches `errors`; only the location error clears, on pick (`:110`). | flow/office_named.png, fresh/w3.png, w4.png, f4.png |
| 3 | High | Confirmed (B) | Add office, number fields | Keyboard covers Late after, Full-day and Half-day. The form does not scroll the focused field into view, so the owner types blind. | fresh/f3.png |
| 4 | High | Confirmed (A+B+code) | Add/Edit office, Location card | Form shows raw coordinates ("12.97991, 77.73984"). Address is already resolved in the picker (`useReverseAddress`) but only latitude/longitude cross back (`OfficeFormScreen.tsx:100–111`, card at `OfficeLocationCard.tsx:44`). Radius is shown nowhere in the form; it appears only in the Offices list after saving, or by reopening the map. | fresh/conf1.png, conf2.png, ed1.png; flow/picker_after_confirm.png |
| 5 | Med | Confirmed (B) | Pin picker | Place title is a plus code ("XPJQ+3WM") even after choosing a search result such as "Koramangala, Bengaluru" (title "WJPF+3RV"). The chosen name is lost. | fresh/map3.png, s2.png |
| 6 | Med | Confirmed (B) | Add/Edit office, rule fields | "Late cut-off must be 0–120 minutes" shows for 1.5, which is inside that range. Hours accept decimals (7.5 / 3.5); minutes do not. Message should say "whole number". Numeric keypad offers "-" and ".". | fresh/e6.png |
| 7 | Med | Confirmed (B), cause suspected | Location card badge | "GPS Verified" is unpredictable: same coordinates, Confirm without moving, badge showed in one run and not in two. Code sets it only through `applyFix` (locate-me) (`MapPinPickerScreen.tsx:126`) and clears it on a manual pan unless the move is within about 11 m of the fix (`:185`). Hypothesis: the picker auto-locates on open and the badge depends on whether the fix landed before Confirm. Needs a repro. | fresh/conf1.png, r0.png, r1.png |
| 8 | Med | Suspected (code) | Pin picker, default pin | Picker starts at a hardcoded Bangalore centre (`MapPinPickerScreen.tsx:62`). Confirming without moving the map may save that centre as the office location and skip the "Place the pin" error. Not tested on device. | none |
| 9 | Med | Confirmed (A+B) | Account → Attendance → Settings | Entry points do not match content. Attendance card: "Who's in, leave & monthly review" (no hint of offices). Settings tile: "Weekly off & holidays", but its screen is "Attendance settings" and lists Team attendance first. Per-employee office lives under Attendance → Settings → Team attendance. | flow/settings_tile.xml, fresh/a1.png, home.png |
| 10 | Med | Confirmed (B) | Holidays sheets | Sticky Save bar overlaps the footnote on Add and covers the Name input on Edit. Add shows "Name is required." on open, before the owner types. | fresh/ha1.png, he1.png |
| 11 | Med | Confirmed (A) | Wizard step 1 office card | Card shows name and hours only. No address, pin status or radius. Owner cannot confirm where the office is. | flow/wizard_after_office.png |
| 12 | Med | Confirmed (A) | Wizard step 2 "Timings & hours" | Repeats the step 1 office list and Add button. Title promises timing editing, but timing is reached only by tapping a card. Steps 1 and 2 overlap. | flow/step2.xml |
| 13 | Med | Confirmed (A+B) | Terms throughout | "Late after (minutes)", "Full-day hours", "Half-day hours", "Team attendance" have no explanation or example. "tenant default" appears in Weekly off copy; "Any planned change for them is also removed" in the tracking-off dialog. | flow/office_form_1.png, fresh/of1.png, wo1.png |
| 14 | Med | Confirmed (A) | Wizard navigation | Step 1's top-left control is "Exit setup"; steps 2–5 use "Previous step" (`SetupWizardScreen.tsx:294`). Same position, different meaning. | flow/*.xml |
| 15 | Low | Confirmed (B) | Archive office | Dialog says only "X will stop tracking attendance. This cannot be undone." No mention of assigned employees; archived cards cannot be tapped or restored. | fresh/ar1.png, ac2.png |
| 16 | Low | Confirmed (B) | Edit office | Backing out with unsaved changes drops them silently, no prompt. | fresh |
| 17 | Low | Confirmed (B) | Edit / Add office layout | "Archive office" link is below the fold, clipped by the gesture bar until scrolled. On Add, the Create button is pushed onto the nav bar when the server-error banner shows. | fresh/ed1.png, air2.png |
| 18 | Low | Confirmed (B) | Weekly off | Save is disabled with no reason (main screen and employee-wise sheet). Date shown as ISO "2026-10-18". Sheet Save spans the full width with no margins. | fresh/wo1.png, ew1.png |
| 19 | Low | Confirmed (B) | Holidays | List and edit sheet show ISO dates. Edit sheet says "Date is immutable after creation". Delete dialog says "Future dates notify tracked employees" (ambiguous) and its close X is on the left, unlike other dialogs. | fresh/hs2.png, de1.png |
| 20 | Low | Confirmed (B) | Team attendance | Unassigned employee's switch copy says "They check in near their office" with no office set. Turning tracking on has no confirmation (asks for office, then assigns). Change office sheet does not mark the current office; picking it reads "Move to X" and succeeds as a no-op. | fresh/team.png, tg2.png, co1.png, co2.png |
| 21 | Low | Confirmed (B) | Office cards | Shift hours appear twice per card; stray "|" after the first row. Raw coordinates also appear in the list rows (`OfficeListRow.tsx:39`). | fresh/off1.png |
| 22 | Low | Confirmed (B) | Pin picker | "Drag map to set pin" shows even when a pin is already set. Radius 50–1000 m in 50 m steps; the −/+ buttons look the same at both limits. | fresh/map4.png, rmax, rmin |
| 23 | Low | Confirmed (B) | Half-day rule | Half-day error appears only once full-day is valid (half 10 with full 0 shows only the full-day error). | fresh/e1.png, e4.png |
| 24 | Low | Confirmed (A) | Wizard | Same action named three ways: "Manage offices" (step 1, once an office exists), "Add office" (step 2), "Add office" (empty Offices route). Two different empty-state descriptions for the same "no offices" case. | flow/step2.xml |
| 25 | Low | Confirmed (A) | Wizard layout | Stepper circles run to about 10 px from the screen edges; rule is a 16 dp gutter. | flow/wizard_after_office.png |
| 26 | Low | Confirmed (A) | Enable attendance | No completion confirmation; lands silently on Attendance home. | flow/after_enable.xml |
| 27 | Low | Confirmed (B) | Theme | App stays light when the system is set to dark. | fresh |
| 28 | Low | Suspected | Accessibility | Number inputs may lack a TalkBack label (dump shows value only). Map has no accessibility tree in `uiautomator` ("could not get idle state"). Neither verified with TalkBack. | picker_1.png |
| 29 | Low | Suspected (B) | Holidays | Overlap warning ("overlaps Suresh's approved leave") showed for 31 Oct; may be stale after changing the date. Leave screen not checked. | fresh |

## Resolution status (rev 3)

All changes are in `fenzit-app`, uncommitted. Full `src` suite 2795 passing and `tsc` clean at the last run.

| Finding | Outcome | Device-verified |
|---|---|---|
| 1–12 | Fixed earlier: Offices empty state, error clearing, keyboard scroll, Location card with address and radius, place names, rule messages, picker badge and default pin, entry-point wording, holiday sheets, merged four-step wizard, richer office cards. Two limits found in code review: (a) finding 4 is fixed on **Add**; **Edit** office still shows coordinates until the pin is re-picked, because a saved office has no stored address. (b) Finding 1 was rebuilt as a new `OfficesEmptyState` screen, not the one-line wrapper first proposed | Most yes. Not re-tested: 1, 6, 11, 12 (6, 11, 12 need an account with unfinished setup) |
| 13 | Fixed: "tenant default" is now "default weekly off"; late-after and full/half-day fields have helper text with an example; tracking-off dialog reworded | Code only |
| 14 | Fixed: every wizard step uses one "Back" label | Code only |
| 15 | Fixed: archive dialog says it cannot be restored and needs no assigned employees | Code only |
| 16 | Fixed: "Discard changes?" prompt on Edit and Add office (`useUnsavedChangesGuard`); Save and Archive skip it | Edit: yes. Add and Save path: no |
| 17 | Archive link: no change needed (scrolls). Create button on the nav bar: the form now keeps the bottom safe area and avoids the keyboard | Code only; checked on Pixel 6 only |
| 18 | Fixed: Weekly off shows why Save is disabled, long dates, footer margins | Code only |
| 19 | Fixed: Holidays show long dates; delete dialog reworded | Code only |
| 20 | Fixed: unassigned employee copy, current office disabled in the Change office sheet | Code only |
| 21 | Fixed earlier with the new office card | Yes |
| 22 | Fixed: chip reads "Drag map to move pin" once a pin exists. The −/+ buttons were already disabled at 50 and 1000. Radius now moves in 1 m steps (was 50 m) and presets are 100/150/200/250 m (was 100/200/500): a product decision to confirm | Code only |
| 23 | Fixed: half-day error shows alongside a full-day error | Code only |
| 24 | Fixed: "Add office" and one empty-state description everywhere | Code only |
| 25 | No change needed | n/a |
| 26 | Fixed: green "Attendance is on" notice on Attendance home after Enable (5 s, announced to screen readers) | No: needs unfinished setup |
| 27 | Skipped by product owner (dark theme) | n/a |
| 28 | Fixed: every text field is named by its label with helper or error as hint; map has a spoken label pointing to search and current location | No: needs TalkBack |
| 29 | Not a bug: guards and tests already exist | n/a |
| 30 | Fixed: owner with only archived offices no longer sees a blank area | Yes |

Also built beyond the findings: wheel time picker (replaces the OS clock dial), Attendance hub and Home Pulse card (one extra `GET /attendance/dashboard` call on Home focus), shared `GradientSurface` and its patterns, tile backdrop on Quick Actions, Holidays redesign, "Add office" banner, Home "No jobs" card.

Dropped by the user: "enable all / disable all" in Team attendance.

## Code review (BMAD, three passes)
Run on the uncommitted `fenzit-app` changes: 12 reviewer runs (blind, edge-case, verification-gap, acceptance, per pass). Patched: picker `placed` needs both coordinates; Confirm notice announced to screen readers; scroll-into-view timer cleanup; address chip limited to two lines; no "Invalid Date" in office rows; no zero-size SVG on cards; one date format for holidays (list, sheet, spoken label); long dates in the Remove-override dialog; unique gradient ids; empty-label guard on `Input`; footer clearance released when a footer goes; Pulse hook drops old numbers when attendance is turned off; "only office" message in Change office; stale comments. 112 + about 90 tests added across the review.

Open decisions for the product owner (not changed):
- Edit office shows coordinates for offices saved before addresses existed, until their pin is re-picked (see the address section above).
- Radius stepper 1 m steps and presets; 950 taps end to end.
- Wizard step 1 "Back" leaves setup without asking; the label no longer says so.
- "Geofence" / "(Geofenced)" wording on the first-run hero and Location card is jargon.
- Keyboard padding on Android was checked on one phone (Pixel 6, Android 15) only.
- `TimePickerSheet.tsx` is 309 lines, just over the ~300 guideline.

## Recommendations (UX lens)

**Fix first (frontend, one owning change each)**
1. **Offices empty state (finding 1).** Give the empty branch a `flex: 1` wrapper in `OfficesScreen.tsx`. Leave `EmptyState` alone; other screens rely on its behaviour. Check on device.
2. **Clear errors on input (finding 2).** Clear the matching `errors` key inside `onChange`, and the duplicate-name error when the name changes. One change covers every field.
3. **Keyboard (finding 3).** Use a keyboard-avoiding scroll container on the office form, and scroll the focused rule field into view.
4. **Show the pin as a place (findings 4, 5, 21).** Pass the resolved address and radius back from the picker. Show address, radius and "Pin placed" on the Location card, the wizard card and the list row. Use a readable place name instead of a plus code, and replace raw coordinates everywhere.
5. **Predictable badge (findings 7, 8).** Show "GPS Verified" only when the pin is the device fix at Confirm; otherwise "Pin placed on map". Do not default the pin to a fixed city: start at the device location, or require the owner to move the pin before Confirm.

**Then**
6. **Merge steps 1 and 2 (findings 11, 12).** Step 1 creates and lists offices. Step 2 edits timings inline or goes away.
7. **One label per action (finding 24).** "Add office" everywhere; "Edit" for an existing office.
8. **Name the entry plainly (finding 9).** Rename the Settings tile ("Setup & settings"), or split it. Subtitle should match the content. Mention offices on the Attendance card.
9. **Explain rules where they are set (findings 6, 13).** Whole-number minutes, helper text with an example ("Full day: 8 h worked. Half day: 4 h worked."). Remove "tenant default" and "planned change" jargon.
10. **Safer destructive and exit actions (findings 14–16).** One back control on every wizard step, or an Exit that asks before discarding. Unsaved-changes prompt on Edit office. Archive dialog names the affected employees.
11. **Layout and copy polish (findings 10, 17–23, 25, 26).** Holiday sheet Save bar, ISO dates, Weekly off Save reason, duplicate shift hours, picker hints, stepper inset, completion confirmation.
12. **Accessibility (finding 28).** Label the number inputs; run TalkBack on the picker. Dark mode is a product decision (finding 27).

Ask the user who reported "confusing" which step lost them. The merge-steps suggestion is my judgement, not evidence from them.

## Web references
- Shopify partner guide, setup wizard and progress patterns: https://www.shopify.co.nz/partners/blog/improving-your-shopify-apps-onboarding-flow
- Appcues, mobile onboarding best practices: https://appcues.com/blog/mobile-onboarding-best-practices
- Vendor geofence setup, map pin with address search and a radius circle: https://apps.odoo.com/apps/modules/19.0/geofence_attendance
- greytHR, mobile geofence setup with a device-location-off screen: https://www.greythr.com/help-ess-mobile/attendance-updates/configure-geofence-attendance

## Office pin address (added after rev 3)
Asked for by the product owner: store the pin's address and show it in the app.
- **Backend (fenzit-be `958ad30`, deployed first):** new nullable `attendance_offices.formatted_address` (CHECK 1–500 characters after trim), accepted on create and update, returned on list, create and detail. Display text only; latitude and longitude stay the single source for geofence checks. No RPC changed. A pin sent without an address clears the stored one; an address sent without a pin is a 400. 1605 backend tests pass; the CHECK was verified on the real database.
- **App (fenzit-app `9d28e20`):** the picker's address is saved with the office; a rename resends it; re-picking the same spot with no lookup result keeps the saved address; moving the pin with no address drops it. Offices card shows a shortened address on a soft street-map chip (no pin icon, no glow); the spoken label has the full address. Existing offices stay empty until their pin is re-picked.
- **Closes** the open decision "Edit office shows coordinates, not an address" for any office saved or re-picked from now on.
- **Review (BMAD, 3 reviewers on the address diff):** 4 patched — address-only change now triggers the discard prompt; address trimmed and capped at 500 before sending; card footer no longer renders an icon with no text; two stale comments. Rest dismissed (not in this diff or covered by the earlier passes) or deferred (no test yet for the focus-scroll and time-preset wiring in the rule fields).
- **Tests:** 43 address tests plus 13 from the review; full app suite 226 suites, 3012 tests, typecheck clean. Device-checked on the Pixel 6 against the deployed backend (Mana office: coordinates, then address after a re-pick; card layout).
- **Not device-checked:** the review patches (discard prompt, footer), a rename-only edit, TalkBack.
- **Still open:** setup wizard step 1 office card shows "Pin set · 100 m radius" and no address; asked, not answered.

## Not covered
- Very long office name; Offices search box (hidden below 9 active offices, `OfficesScreen.tsx:42`).
- TalkBack pass on the finding 28 labels, the map, and the new wheel time picker (adjustable wheels).
- Finding 26 notice on an account with unfinished setup.
- Saving a weekly-off change or an employee-wise override.
- Moving an employee between offices; reusing an archived office's name.
- Landscape with keyboard open.
- Add office from wizard step 2.
- Re-test of finding 1 (Offices empty state) on device.

## Test data left on the tenant
- "Test Office A" (active, Suresh assigned), "QA Rules" (active), "QA Dup" (archived).
- Mahesg is back to not tracked, no office.
- Device settings restored (font scale, night mode, airplane mode, rotation).
