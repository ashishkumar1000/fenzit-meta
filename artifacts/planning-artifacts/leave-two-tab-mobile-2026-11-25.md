# Leave two-tab mobile surface (Stitch "Two-Tab Screen UX Redesign") — plan

Date: 2026-11-25 · Repo: `fenzit-app` only (API + web already shipped) · Stitch project `470446784646785367`, mobile screens `Leave Types` + `Leave Requests`.
Status: adversarial plan review folded (13 patched / 0 deferred / 0 rejected; 1 accepted-with-reason: `attendanceLeave.ts` stays one file — the single attendance-leave API module, +~60 lines over 439, sibling split would fragment the service object).

## Goal

Replace the owner Leave pane's interior (today: "Apply on behalf" CTA + Pending|All segmented list) with the design's two-tab surface — **Types | Requests** — implemented over the shipped BE endpoints, dropping every design element the API cannot source. Web console (`fenzit-web` AdminLeavePage) is the semantic reference; the Stitch mobile HTML is the visual reference.

## Verified API surface (fenzit-be)

- `GET /attendance/leave/types` → `LeaveTypeView[]` (fixed catalog + read-only legacy remnants, `configurable` flag).
- `PATCH /attendance/leave/types/:id` → values-only: `accrualDays` (0–366, ≤2 decimals; 0 refuses on comp_off), `carryForward` + `allowOverBalance` (**monthly types only**), `paid`, `enabled`. 409 `LEAVE_TYPE_NOT_CONFIGURABLE` on remnants; 422 on bad values; 404/403 possible.
- `GET /attendance/leave` — `status` (`pending|approved|revoked|cancelled|rejected`), `employeeId`, `q` (server-side search: name/code/reason, trim, ≤100 chars — BE 422s longer), `from/to`, cursor pages ≤50, newest first. Rows carry optional `leaveTypeId/leaveTypeCode/leaveTypeName/officeName` + `employeeName/Code/AvatarUrl`.
- `GET /attendance/leave/summary` → `{ activeEmployees, counts: Record<DerivedLeaveStatus, number> }` — the pill counts (web's source).
- `POST .../approve|reject|revoke` as shipped; reject reason optional, revoke reason REQUIRED.
- **No** create/delete type route; **no** reconsider route; **no** total in the pagination envelope; `revoked` (owner revoke) vs `cancelled` (employee cancel) are distinct wire statuses.

## Design → implementation mapping

### Dropped (API-unavailable or host-owned chrome)

| Design element | Why dropped |
|---|---|
| Standalone header (greeting, role pill, bell, avatar) + bottom nav (Home/Leave/Team/Settings) | The pane lives under host-owned chrome; app tab bar exists |
| "Add Type" chip-button | Fixed catalog — types cannot be created |
| Sort menu ("Newest first") | BE list is newest-first only — no second order to switch to |
| "Reconsider" on rejected cards | No BE route |
| "Team coverage limit exceeded" note | Rejection reason is not in the request view (coverage endpoint exists — noted as future detail-sheet work in `deferred-work.md`, trigger: next `LeaveDetailSheet` touch) |
| Toast on revoke | App revoke goes through the reason-required RevokeSheet (shipped); success announces via AccessibilityInfo |
| "Live updates" pulse | No live channel; focus/foreground refresh contract stands in |
| "Self-withdrawn by employee" note under a **revoked** row | Wire truth is owner-revoke — the honest note reads "Revoked by admin" (design text kept for `cancelled`, where it is true) |

### Kept with derivation

- Chip sub-labels: monthly → "{annualized = days×12} d / yr · Active|Off"; annual → "{days} d / yr"; comp_off → "As earned"; disabled → "Off".
- "N configured" chip-count line = `rows.filter(r => r.configurable).length` (legacy remnants excluded).
- Type tag on request cards from `leaveTypeName` (absent on legacy rows → tag hidden).
- "Planned absence" mini-tag on approved cards whose `startDate > istTodayDate()` (pure string compare per AD-7; today from `utils/istDate.ts`).
- "N total · M need review" line derived from `/summary` counts; hidden while a search narrows the list (web's round-4 rule) and when counts failed.

## Write lifecycle (P1 decision — named per action)

- **Approve = the only direct write, inline on the card** (input-less, state-guarded own-retry). Pane-level D2: `writeLatch`; 409 `LEAVE_NOT_PENDING` → `InlineNotice` above the list ("already handled") + `markStale` on every filter + `fetchFirst(active)` + `loadMyProfile({force:true})` (the badge mirror); offline → action-named copy from `leaveWriteOfflineMessage`; success → remove/replace row + mark all filters stale + badge mirror + announce.
- **Decline and Revoke stay sheet-hosted** — both invite text input (reject reason optional; revoke reason REQUIRED): the buttons open `LeaveDetailSheet` (reject stage) / the sheet's revoke stage; the sheet keeps its shipped write posture (latch, handled notice, offline copy, split previews, balances).
- Card tap → `LeaveDetailSheet` detail stage (unchanged).

## File plan (fenzit-app)

1. `src/services/resources/attendanceLeave.ts` — add `q` to `listOwnerLeave`; add `patchLeaveType(id, values)`, `leaveSummary()`; extend `LeaveRequestRow` with optional `leaveTypeId/leaveTypeCode/leaveTypeName/officeName`; add `LeaveStatusCounts`.
2. `features/attendance/leave/leaveTypesModel.ts` (new, pure) — catalog order (earned, sick, bereavement, comp_off, then legacy), chip model, per-type draft map, dirty/diff calc, changed-fields-only PATCH body (sleeping-rule hold: only `enabled` ships while off), label copy per mode.
3. `features/attendance/leave/LeaveTypesPane.tsx` (new; editor card split into `LeaveTypeEditorCard.tsx` if the 300-line budget strains) — chips row + "N configured" + config card. **Drafts survive chip switches** (per-type draft map — the web keeps every editor mounted so an unsaved edit never vanishes; mobile reaches the same guarantee with a draft map). Failure paths: server message verbatim in `InlineError` above Save, draft preserved, latch released; offline → transport line; 404/403 → refetch catalog and drop the stale editor.
4. `features/attendance/leave/LeaveRequestCard.tsx` (new) — the design's card anatomy: avatar + status glyph, name, EMP-code · office, status pill, date strip + "N working days" chip, type tag + reason quote, action row (pending → Decline(sheet)/Approve(inline); approved → Revoke(sheet); terminal → quiet note: revoked → "Revoked by admin", cancelled → "Self-withdrawn by employee", rejected → none).
5. `features/attendance/leave/useLeaveRequests.ts` (new hook; reducer lives in `requestsModel.ts` to keep the hook lean) — per-**filter** pages (all + 5 statuses); page state is per **(filter, committed q)** — a committed `q` (trimmed, ≤100 chars, debounced) resets every filter's page to a fresh first page and cursors never cross q values (the D1 invariant generalized); `/summary` counts fetch — **failure → counts go quiet (pills and totals render bare), never an error banner over the list, retried on next focus/refresh**; focus/foreground refresh + stale marks; pull-to-refresh; cursor load-more. Writes mark every filter stale.
6. `features/attendance/leave/requestsModel.ts` (new) — filter list, web's pill labels verbatim (`pending`→"Needs review", `revoked`→"Self-cancelled", `cancelled`→"Cancelled"), status-pill mapping for cards, empty-state copy, the page reducer + failure classifiers reuse.
7. `OwnerLeaveScreen.tsx` — rewrite interior: Types|Requests `SegmentedControl`; Types pane + Requests pane (search field + horizontal filter chip row + totals line + card list); keep dual hosting (pushed `OwnerLeave` route + embedded pane), keep Apply-on-behalf CTA as a compact row on the Requests pane (shipped feature the design omits — retaining parity), keep `LeaveDetailSheet` + balances slot + sheet-hosted writes, keep viewer guard.
8. `features/more/MoreScreen.tsx` — the "Leave" `MoreRow` pushing `OwnerLeave` (owner direction 2026-11-25: the Account section hosts the entry; screens live there).
9. `navigation/types.ts` — `OwnerLeave` params `{ tab?: 'requests' | 'types' }`; **both** landing channels remap: `notificationTapModel` and `useApplyOnBehalf` (`{ tab: 'all' }` today) → `tab: 'requests'`, preserving `consumeTabParam`'s unconditional-fetch semantics (the born-approved request must be visible on landing).
10. Dead code — restricted: delete `useOwnerLeaveQueue.ts` (+ its test) and the **queue-state slice** of `ownerLeaveModel.ts` (`LeaveTab`, `OwnerLeaveState`, reducer) only; `classifyLeaveWriteFailure` and the other shared exports stay (four surfaces import them); `LeaveHistorySection` stays (live — the employee's own Leave section).

Copy: design's words where the API can source them; web's words where the design is silent or wrong for the type's mode (monthly-only toggles, "Grant per year", "No rate — days come from approved comp-off earns", rate error "Up to 366, at most 2 decimals.", off-sleep semantics). Pill wording mirrors the shipped web console exactly (the design's own words per web comment).

## Semantics carried from the shipped web editor (mobile render)

- Enable switch off → every other row sleeps (disabled + dimmed); a drafted rule stays in its input and ships when the type wakes; only the `enabled` change posts while asleep.
- Save posts changed fields only; disabled until dirty; busy → "Saving…"; success mark "Saved."; unchanged PATCH is a no-op answer.
- Stepper ±0.5 (not the mock's ±1/integers), clamp 0–366, ≤2 decimals, numeric equality dirty-check ("1.0" == "1"); monthly shows the annual conversion line.
- Legacy remnant (`configurable: false`): rows disabled + "Read-only" chip; PATCH would 409.

## Test timing (house rule)

- **Existing** tests pinning removed/changed behavior (`OwnerLeaveScreen.test.tsx`, `ownerLeaveModel.test.ts`, `leaveNotificationModel.test.ts`) are updated or deleted **in the same implementation change** — the deferral rule covers new tests, never a red suite.
- **New** tests stay deferred until the owner confirms the build on device; intended then: model tests (chip/dirty/PATCH-body derivation, q×cursor reset), hook tests (per-filter isolation, counts-quiet rule), card tests (action branches), screen tests (two-tab switch, viewer guard). Suite runs `bun run test` (never bare `bun test`).

## Sequence

Implement → Metro debug build on the attached Pixel 6 for the owner's look-and-feel check → owner yes → tests → `/bmad-code-review` → triage → commit (ask first; fenzit-app repo only).
