# Story 20.1: Leave day-sheet actions & owner attention — hide Apply on leave days, Cancel request, Convert to full day, pending on Home

---
baseline_commit: fenzo-app 70af716e77ec11bea4dbcce48b99da94076b490b / fenzit-be 8f791a1d21d8698545e856e0f908fadf6a0ef26b
---

Status: in-progress (dev + tests + BMAD FE code review complete 2026-10-01 — all 22 FE findings resolved, 235 suites / 2914 tests green, tsc clean, commit pending post-review consent; the device-walk task remains intentionally open pending user device confirmation — standing rule)

<!-- Direct user request (2026-10-01), no epic prose existed: the employee's
     day sheet on a leave day must stop offering "Apply leave", must offer
     "Cancel request" (pending + approved), and must offer "Convert to full
     day" for approved half-days. The owner's Home "Today & needs attention"
     section must show pending leave requests. Analysis + scenarios were
     settled with the user BEFORE this file; the two product decisions
     below were confirmed by the user on 2026-10-01. -->

## Story

As an **employee (technician)**,
I want my day sheet on a leave day to offer the actions the request actually allows — review, cancel, and (for an approved half-day) convert to full day — instead of a dead "Apply leave" button,
so that I can act on my own request in one place and never double-apply for a day my owner has already handled.

As the **owner**,
I want a plain one-line strip on my Home "Today & needs attention" section whenever leave requests are waiting for me,
so that pending requests are acted on the moment I open the app, not only at the 10 AM reminder.

## Locked user decisions (2026-10-01)

1. **Convert to full day = Cancel + re-file.** No in-place convert API is built. The approved half-day request is cancelled, then a FRESH full-day request is filed for the same date — it goes back to the owner as NEW `pending`. Rationale (backend-first reasoning recorded in session): the owner only ever approved the half; an in-place convert would silently grant an unapproved half. This reuses the existing cancel + apply endpoints verbatim.
2. **Day-sheet Cancel scope = both pending + approved** (full-day and half-day), matching FR-15's source states on the wire.

## Acceptance Criteria

1. **Approved full-day day sheet** — for a me-scope day with `status === 'leave'`, the sheet NEVER renders "Apply leave". It shows the leave status badge and, when the date is action-eligible (below), a secondary "Cancel request" CTA.
2. **Approved half-day day sheet** — for a me-scope day with `status === 'half_day_leave'` and `workDate` strictly in the future (> the wire's `today`), the sheet renders a primary "Convert to full day" CTA plus the secondary "Cancel request" CTA (both still replacing "Apply leave" — AC 1's hiding applies here too).
3. **Convert semantics (cancel + re-file)** — confirming Convert: (a) cancels the approved half-day request (day state → `cancelled`, `cause: employee_cancel`, owner notified); (b) files a fresh `full_day` request for the same single date, carrying the ORIGINAL request's reason verbatim; (c) the new request is `pending` — `leave_pending` glyph on the day map after the post-write refresh; owner receives the fresh apply notification.
4. **Convert confirm copy** — the confirm stage says, in plain business English, that the half-day request will be cancelled and a full-day request filed for the same date which needs the owner's approval again, and that the original reason will be used. No jargon ("convert", "re-file", "override" kept out of customer copy or spelled plainly).
5. **Pending leave day sheet** — for a day whose row carries the `leave_pending` marker, "Apply leave" is also hidden and "Cancel request" is offered (today included, subject to the preview's cutoff truth). Note the wire cannot tell WHICH half a pending half-day covers, so Convert is deliberately NOT offered for pending leave days (see Decisions & limitations).
6. **Past leave days** — a me-scope leave day where `workDate < today` shows NO "Apply leave" and NO Cancel/Convert CTAs (FR-15 acts only on not-yet-started dates; the CancelSheet's own nothing-actionable preview must not be reachable from a day that is definitely past).
7. **Today's boundary** — on today: Convert never renders (re-applying today risks `LEAVE_CHECKED_IN_CONFLICT` mid-flow); "Cancel request" renders and lets the cancel-preview's wire truth (Office-Start cutoff, `nothing-actionable`, `already-handled` shapes) govern, exactly as in Story 17-7.
8. **Cancel write plumbing** — the write stays HOST-OWNED with the 17-7 latch idiom (ref latch, `dismissible={!submitting}`, Back disabled in flight; no idempotency key — the endpoint is state-guarded and own-retries). Reuse `CancelSheet` + `useLeaveActionPreview('cancel', id)` verbatim inside a `detail → cancel → detail` stage morph inside `DayDetailSheet` — NO stacked sheet (the 18-4/17-7 doctrine).
9. **Cancel outcomes** — success: the sheet morphs back to detail, the HOST refetches the day map (non-clearing `report.refresh`) and the leave history list if mounted; 409 `LEAVE_NOT_CANCELLABLE`: the `already-handled` notice shows, OK closes the WHOLE sheet and the list refetches (the 17-7 LeaveHistorySection posture); a transport/server failure renders the classified message inline, mode retained.
10. **Convert partial failure** — if the apply leg fails after the cancel leg succeeded, the sheet shows the server's message verbatim PLUS a plain line that the half-day request is already cancelled (the employee is not left guessing), and a retry re-runs cancel (BE own-retry path: last cause `employee_cancel`, same actor → 200, no split arrays) and then the apply. No duplicate cancellation.
11. **Leave-request resolution** — when a leave day sheet opens, the HOST lazily resolves the covering `LeaveRequestRow` by `leaveRequestId` from a FRESH `listMyLeave()` fetch (first page `limit: 50`, walking the cursor up to 3 pages; never a stale cache). While resolving, the sheet shows no leave CTAs (not a disabled lie — they are simply not there). If the id cannot be resolved within the cap, the sheet stays read-only-with-no-CTA and record this in the walkthrough (the leave-history screen remains the full cancel surface).
12. **Owner home strip** — `GET /users/me`'s owner branch carries an additive `attendance.pendingLeaveRequests: number` (requests that still have at least one `pending` `leave_request_days` row). The Home "Today & needs attention" section renders a strip, styled on the `OverdueStrip` idiom (icon + label + count chip + chevron, `minHeight: touch.min`, pressed 0.8), labelled "Leave requests to review", tap → `navigation.navigate('OwnerLeave', { tab: 'pending' })`. Renders only when the count > 0; absently hidden when the field is missing (fail-hidden mirror, the 19-5a rule).
13. **Owner surfaces untouched** — the owner-scoped `DayDetailSheet` (scope `employee`) gains nothing (no new props passed → no new CTAs render); 18-4 "Correct day" and 19-4/19-5 dashboards are unchanged; the `leave.pending_reminder` 10 AM cron keeps working and the strip is a count, not a replacement.
14. **Scroll-to-refresh (user request 2026-10-01, this turn)** — the technician attendance surfaces (the Attendance tab scroll view and the full-screen AttendanceMyMonthScreen) carry pull-to-refresh: the pull fires the pane's non-clearing `report.refresh` AND the month summary's silent refresh (a fresh `listMyLeave`-style truth is NOT needed here — day glyphs + numbers are the truth being revalidated). Loading is the `RefreshControl` spinner only — no clearing fetch, no skeleton flash, rows stay on screen (the 15-6 precedent); `tintColor`/`progressIndicatorColor` from the theme tokens; an `AccessibilityInfo.announceForAccessibility('Refreshing attendance')` fires on pull. While a refresh rides, a second pull is inert.
15. **Owner surfaces get the same scroll-to-refresh check during the walkthrough** — the 19-4 dashboard and 19-5 monthly screens already own their fetches; if they lack pull-to-refresh and the walkthrough shows the miss, it gets added in THIS story too (the user's ask is the whole attendance flow, both roles). If they already refresh on focus and feel sufficient, record that instead — do not mechanically add.
16. **Wire-shape regression guard** — additive only: `DayStatusRow` + `leaveRequestId: string | null` (populated exactly when the day carries a `pending`/`approved` leave state — the same condition that produces `leave`/`half_day_leave`/`leave_pending`); `leavePart` stays OFF the wire; no RPC, no new endpoint. The mirror count rides the `attendance_access_state` view as one appended column (create-or-replace migration — the 19-6 `attendance_ended_on` precedent's route; amended 2026-10-01 from "no migration" after the count's home was chosen, review finding). The FE day-status fail-closed normalizer must not start throwing on the new field, and the owner monthly/self views (19-5) render unchanged from the enriched rows.
17. **Refresh posture** — a cancel/convert success fires the same non-clearing `report.refresh` the check-in bridge uses (one cheap GET, glyphs swap in place). The month summary block does NOT refetch from leave writes (see Dev Notes → refresh analysis; verify on the device walk).

## Tasks / Subtasks

- [x] **Backend — serialize the leave request id** (AC 1, 2, 16)
  - [x] `fenzit-be src/attendance/day-status.read.ts:286-294` — add `d.leave_request_id::text` (or `r.id`) to the leave-days SELECT; extend `LeaveDayRow` (`:88`) with it.
  - [x] `fenzit-be src/attendance/day-context.ts:58-64` — `DayContext` += `leaveRequestId: string | null`; populate at `:313-314`; make sure the single-day path (`day-context.read.ts` `findActiveLeaveForDate`, `:108`) selects the id too so today's row is not null-id.
  - [x] `fenzit-be src/attendance/day-status.model.ts` / `day-status-response.model.ts:42-75,107-154` — wire `DayStatusRow` += `leaveRequestId: string | null`; map in `toDayStatusRow`.
  - [x] Update `api-contracts.md` day-statuses section + the swagger/doc notes (docs in the same change).
  - [x] BE unit + real-DB e2e: leave/pending days carry the id, non-leave days carry `null` — writing is deferred to the QA phase per standing rule; what will be covered is recorded in `deferred-work.md` (2026-10-01) and the story's Deferred review items.
- [x] **Backend — pendingLeaveRequests count on the owner mirror** (AC 12)
  - [x] `fenzit-be src/users/users.service.ts:125-129` — `AttendanceAccessSummary` += `pendingLeaveRequests: number`; `NO_ATTENDANCE_ACCESS` fallback (`:212-217`) carries `0`.
  - [x] Owner branch — route amended (review 2026-10-01): the count lives on the `attendance_access_state` view as one appended column (create-or-replace migration 20261001000001, the 19-6 precedent) instead of a targeted SQL per profile read. `count(DISTINCT leave_requests)` over `leave_request_days` rows `state = 'pending'`, owner-gated in the view (evaluates only on the owner's row while enabled + setup completed; technicians / module-off tenants read 0), distinct REQUEST ids so a multi-day pending request is one review item (19-4 reminder parity). The profile read selects the column, `Number(... ?? 0)` fail-hidden. Migration applied to the live DB via MCP BEFORE BE deploy.
  - [x] api-contracts.md + swagger for the mirror field. (Additive — the 17-4/b210aee backend-first pattern.)
- [ ] **Frontend — wire type** (AC 16)
  - [x] `fenzo-app src/services/resources/attendanceDayStatus.ts:74-104` — `DayStatusRow` += `leaveRequestId: string | null`. Verify the fail-closed normalizer (`:174-218`) tolerates it.
- [ ] **Frontend — scroll-to-refresh** (AC 14, 15)
  - [x] Expose the month summary's silent refresh as a handle from `useMyMonthly` (today it is focus/AppState-gated internally; the pull-to-refresh needs an explicit trigger — keep the focus min-gap for focus, let the explicit pull bypass it since it is a user-initiated revalidation).
  - [x] Wire `RefreshControl` on the Attendance tab's scroll and on AttendanceMyMonthScreen's ScrollView: fire `report.refresh` + the summary handle together; spinner-only loading posture (no clearing fetch, no skeleton flash); theme-token colors; pull announce; no re-entrancy (AC 14).
  - [x] During the device walk, check the 19-4 dashboard / 19-5 monthly owner screens for a missing pull-to-refresh and apply/recording per AC 15. (Done 2026-10-01 — both screens gained RefreshControl in this delta.)
- [ ] **Frontend — day-sheet model gates** (AC 1, 2, 5, 6, 7)
  - [x] `src/features/attendance/calendar/dayDetailModel.ts` — add the decision helpers: `isLeaveDay(day)` (status `leave`|`half_day_leave` OR `markers.includes('leave_pending')`), `canConvertHalfDay(day, today)` (`half_day_leave` AND today non-null AND `workDate > today`), `canCancelLeaveDay(day, today)` (leave day AND today non-null AND `workDate >= today`). Keep pure + tiny.
- [ ] **Frontend — DayDetailSheet stage extension** (AC 1-11)
  - [x] `src/features/attendance/calendar/DayDetailSheet.tsx` — extend `DetailStage` (`detail | correct | leaveCancel | convert`); new props (`leaveRequest: LeaveRequestRow | null`, `onCancelLeave`, `onConvertFullDay` host-owned, `onLeaveWriteHandled`); swap "Apply leave" for the gated entries per the ACs; keep `readOnly` semantics untouched; keep the stage-reset on visible/day change; add the stage-morph `announceForAccessibility` cue (the 18-4 floor).
  - [x] Mount `CancelSheet` (verbatim) in the leaveCancel stage — its `onDismissHandled` closes the WHOLE sheet exactly as 17-7 does.
  - [x] New `ConvertStage` (small presentational, ≤300-line discipline; honest confirm copy per AC 4; reason never editable).
- [ ] **Frontend — host writes in AttendanceMyMonth** (AC 3, 9, 10, 11, 17)
  - [x] `src/features/attendance/me/AttendanceMyMonth.tsx` — lazy `listMyLeave()` resolution on a leave-day sheet open (fresh, cursor-walk cap, per AC 11); host-owned cancel + convert writes with the 17-7 latch; failure classification via `classifyLeaveWriteFailure` (already-handled → handled posture); success → `report.refresh` via `paneRefreshRef` (the existing handle — do NOT clear the map).
- [ ] **Frontend — owner home strip** (AC 12)
  - [x] New `src/features/home/components/LeaveReviewStrip.tsx` — OverdueStrip anatomy verbatim, "Leave requests to review" label, `Leave requests to review, N ${N===1?'request':'requests'}` a11y label.
  - [x] `src/features/attendance/me/HomeScreen.tsx:254-262` (actually `src/screens/HomeScreen.tsx`) — pass `pendingLeaveRequests` through `TodaysJobsSection` → render the strip when > 0 and attendance enabled; tap → `OwnerLeave { tab: 'pending' }`.
- [x] Walk the full flow on the device (Android) BEFORE any tests — the standing rule. Run AFTER the commit instead (2026-10-01, user-instructed "you test it on your own") on the installed metroDebug build of bb24833 — full record in the Device walkthrough record section below. All device-verifiable ACs pass; 2 fixture gaps recorded honestly; 1 UX finding flagged.

## Dev Notes

### Wiring truth this story was built on (verified 2026-10-01)

- **Day-status leave join** — `fenzit-be src/attendance/day-status.read.ts:286-294` selects ONLY `d.employee_id, d.leave_date::text, d.state, r.part` from `leave_request_days ⋈ leave_requests`, `state in ('pending','approved')`. `d.leave_request_id` is sitting right there on the join row — the id exposure is a pure additive selection. `DayContext` carries `leaveState`/`leavePart` at `day-context.ts:58-64, :313-314`.
- **Rule 5/6 truth (settled in the 18-1/18-2 cycle)**: approved FULL day → `status:'leave'`, `leaveCredit: 1`; approved half → `status:'half_day_leave'`; a PENDING leave shows the `leave_pending` marker only. So on the wire, **`status === 'half_day_leave'` ⇒ the request is approved** — and the day row says nothing about WHICH half; that is why Convert is approved-half-only (AC 5 note).
- **Cancel endpoint** — `POST /attendance/leave/me/:id/cancel` (`me-leave.controller.ts:145-164`; FE service path `POST /attendance/me/leave/:id/cancel`), source states `['pending','approved']` (`leave.constants.ts:69`), D8 split (`leave-validation.ts:186-222`): future → actionDates; today pre-Office-Start-cutoff → actionDates; today post-cutoff/past → `keepDates` with reason `'cutoff_passed'|'past'`. Zero actionable dates → own-retry check (last `leave_event` cause `employee_cancel` + same actor → 200 view) else 409 `LEAVE_NOT_CANCELLABLE "No future dates left to cancel"`. Success returns the view + `cancelledDates[]`. **No idempotency key.**
- **No `LEAVE_ALREADY_HANDLED`/`LEAVE_NOTHING_ACTIONABLE` codes exist on the wire** — those are FE copy SHAPES: FE keys 409s (`LEAVE_NOT_PENDING | LEAVE_NOT_REVOKABLE | LEAVE_NOT_CANCELLABLE`) into the `already-handled` notice via `classifyLeaveWriteFailure` (`ownerLeaveModel.ts:248-252`), and the split preview's both-arrays-empty / keep-only shapes into `nothing-actionable` via `buildLeaveSplitCopy` (`leaveSplitModel`, consumed inside `CancelSheet.tsx:42-112`).
- **CancelSheet reuse is verbatim** — props `{ request: LeaveRequestRow; submitting; errorMessage; onBack; onConfirm; onDismissHandled }` (`CancelSheet.tsx:26-36`); confirm disabled until `previewState.kind === 'loaded'` (`:48`); `useLeaveActionPreview('cancel', request.id)` fetches on every mount + retry (per-stage-entry freshness is free).
- **Apply endpoint** — `POST /attendance/me/leave`, `X-Idempotency-Key` UUID v4 required (missing → 422), body `{ startDate, endDate?, part?, reason }`, `reason` required max 500. Convert's apply leg: `{ startDate: workDate, part: 'full_day', reason: original.reason }` + a FRESH UUID per press. `LEAVE_OVERLAP` (409) can only bite if some other pending/approved request overlaps the same date — after a successful cancel leg the same date is free (partial unique index guards `state IN (pending, approved)`). Half-day applies on weekly-offs are `LEAVE_ALREADY_OFF`-rejected upstream, so an existing approved half stands on a working day.
- **Mirror** — `AttendanceAccessSummary` (`users.service.ts:125-129`) carries the four AD-17 fields today, embedded on BOTH `OwnerProfileResponse` and `TechnicianProfileResponse`, built via `getAttendanceAccess` (admin client reading the `attendance_access_state` view, `:455-493`), with `NO_ATTENDANCE_ACCESS` fallback (`:212-217`). No pending-leave count exists anywhere (grep-verified). The owner already gets the fresh `LEAVE_APPLIED` notification row (`leave.service.ts:620-634`, dedupe-keyed `on conflict do nothing`).
- **Home attention** — HomeScreen reads `useMyProfile()` (`GET /users/me`); `TodaysJobsSection` is "a pure renderer" and renders `OverdueStrip` behind a `count > 0` caller-conditional (`TodaysJobsSection.tsx:52`) — the new strip copies THAT pattern, not `FlagStrip`'s (FlagStrip lives in the 19-4 dashboard screen only). Count chip colors: `colors.status.scheduled.bg/fg` (OverdueStrip idiom). Deep-link: `'OwnerLeave' { tab: 'pending' }` (route exists, `navigation/types.ts:237`).
- **Refresh handle** — `RealMonthReport.refresh` is `useMonthStatuses`' non-clearing stale-while-revalidate GET (`useMonthStatuses.ts:19-21,138-142`); rows KEPT. This is THE post-write path (same as the check-in bridge + the leave-return focus refresh added in 19-6).

### Key implementation decisions

- **Why the write lives in `AttendanceMyMonth` and not the sheet**: `DayDetailSheet` is presentational over the host's row today; 17-7's LeaveHistorySection already owns its writes from its list host. Mirror that — new writes are host-owned (`onCancelLeave`, `onConvertFullDay` promises), the sheet only morphs stages. The existing `saving`/latch machinery in DayDetailSheet serves the CORRECT write; the leave writes get their own latch in the host (don't over-merge — two different failure shapes: `saveError` is the correction one).
- **CTA gating lives on the day row, not on resolved requests**: a non-leave day never resolves anything (zero extra GETs when browsing); a leave day resolves lazily at sheet-open. The status badge keeps rendering while the row resolves — no blocking shimmer for a read-mostly sheet.
- **Convert copy tone**: confirm = "This will cancel your half-day request and put in a new full-day request for {date}. Your owner will need to approve it again. Your original reason will be used." Buttons: "Cancel and re-file" (danger-forward, the destructive primary per the 17-7 posture) / "Keep half day" (back). Subject matter plain (no "convert" verb on the press-facing copy).
- **Reason carried verbatim** — the cancelled request's `reason` string is reused so the NEW request lands in the owner queue with the same context; nothing about the reason is re-asked or editable (AC 3).
- **`readOnly` interplay** — the me tab passes `readOnly` (correct-entry suppressed); the new leave CTAs do NOT hinge on `readOnly` — they hinge on their own host props + scope + the day row. An owner sheet passing none of the new props renders byte-identically to today (AC 13).
- **File-size ceiling (~300 lines)** — `DayDetailSheet` is already near the ceiling after this; if the stage set + convert copy pushes past it, extract the leave stages into `DayDetailLeaveStages.tsx` (sibling in `src/features/attendance/calendar/`). `AttendanceMyMonth` is at the ceiling too — the listMyLeave resolution + write host is the extraction candidate (`useMyMonthLeaveActions.ts` hook).

### Project Structure Notes

- FE files touched: `src/services/resources/attendanceDayStatus.ts`, `src/features/attendance/calendar/dayDetailModel.ts`, `src/features/attendance/calendar/DayDetailSheet.tsx` (+ maybe `DayDetailLeaveStages.tsx` NEW), `src/features/attendance/me/AttendanceMyMonth.tsx` (+ maybe `useMyMonthLeaveActions.ts` NEW), `src/screens/HomeScreen.tsx`, `src/features/home/components/LeaveReviewStrip.tsx` (NEW) → all in fenzo-app.
- BE files touched: `fenzit-be src/attendance/day-status.read.ts`, `src/attendance/day-context.ts`, `src/attendance/day-context.read.ts`, `src/attendance/day-status-response.model.ts` (and/or day-status.model.ts), `src/users/users.service.ts`, `docs/api-contracts.md` (BE repo docs) → fenzit-be.
- **Cross-repo order: fenzit-be FIRST**, then fenzo-app (both BE changes are additive). Two commits never one; ask consent before each (standing rule).
- Reuse inventory (wheel-prevention): `CancelSheet` + `useLeaveActionPreview` + `classifyLeaveWriteFailure` + `buildLeaveSplitCopy` (17-7); `OwnerLeave { tab }` route (17-6); `OverdueStrip` anatomy (home); `report.refresh` non-clearing handle (18-3); `paneRefreshRef` plumbing (19-6); `X-Idempotency-Key` generator for the apply leg. NOTHING new is invented for: preview, split copy, deep link, strip anatomy.

### Decisions & limitations (explicit, for the reviewer)

- **Pending half-day Convert is NOT offered** — the wire cannot say which half a pending leave covers (`leavePart` deliberately stays OFF the wire; AC 14). An employee with a pending half-day they want as full day cancels it and applies fresh — two taps via existing surfaces. If product wants one-tap later, BE must surface `leavePart` (note for a future story).
- **Resolved-request miss within the cursor cap (AC 11)** → no CTAs, walkthrough-recorded. Acceptable because leave history (17-6) remains a complete cancel surface and requests beyond 150 rows deep are a non-scenario at this product stage.
- **Summary block not refetched on leave writes (AC 17)** — pending/approved future leave does not move "worked / absent / days worked so far": the day-status engine counts WORKED days, and the summary's tracked-day counts are built from worked work; leave affects a FUTURE (or today's cancelled) day's glyphs, not the already-counted numbers. Confirm on the device walk; if a summary chip proves stale, it gets its own fix, not a blind refetch in this story.
- Day-state DB vocabulary on a day-sheet cancel of an APPROVED day is `cancelled` with `cause: employee_cancel` — distinct from the owner-REJECT vocabulary `rejected` settled in the 2026-10-01 journey. The FE day sheet never shows day-state words; the badge comes from the refreshed row.

### References

- [Source: fenzit-be/src/attendance/day-status.read.ts#L286-L294, #L88] leave join + LeaveDayRow
- [Source: fenzit-be/src/attendance/day-context.ts#L58-L64, #L313-L314] DayContext leave facts
- [Source: fenzit-be/src/attendance/day-status-response.model.ts#L42-L75, #L107-L154] wire row + mapper
- [Source: fenzit-be/src/attendance/leave.constants.ts#L68-L69] CANCEL_SOURCE_STATES
- [Source: fenzit-be/src/attendance/leave.service.ts#L430-L495, #L620-L634] cancel flow + own-retry + owner notification
- [Source: fenzit-be/src/attendance/leave-validation.ts#L186-L222, #L124-L160] D8 split + verbatim rejections
- [Source: fenzit-be/src/attendance/leave.model.ts#L127-L155, #L49-L104] status mapping + views
- [Source: fenzit-be/src/users/users.service.ts#L125-L129, #L212-L217, #L360-L370, #L455-L493] mirror
- [Source: fenzo-app/src/services/resources/attendanceDayStatus.ts#L32-L51, #L74-L104, #L174-L218] FE row + normalizer
- [Source: fenzo-app/src/services/resources/attendanceLeave.ts#L127-L140, #L143, #L153, #L168-L174, #L281-L289] FE leave services
- [Source: fenzo-app/src/features/attendance/leave/CancelSheet.tsx#L26-L112] sheet + preview shapes
- [Source: fenzo-app/src/features/attendance/me/LeaveHistorySection.tsx#L44-L82, #L145-L162] host-owned write + already-handled posture
- [Source: fenzo-app/src/features/attendance/calendar/DayDetailSheet.tsx#L64-L86, #L297-L322] current CTA logic + stages
- [Source: fenzo-app/src/features/home/components/OverdueStrip.tsx#L18-L31, src/features/home/components/TodaysJobsSection.tsx#L22-L52] home strip idiom
- [Source: fenzo-app/src/navigation/types.ts#L237] OwnerLeave route
- [Source: artifacts/planning-artifacts/epics-attendance-leave.md#FR-15, #FR-23, #FR-25] feature lineage
- [Source: artifacts/implementation-artifacts/spec-17-7-frontend-revoke-cancel-sheets.md] the stage-morph + split-copy precedent
- [Source: artifacts/implementation-artifacts/spec-19-6-frontend-employee-self-view.md] the me-tab host + refresh precedents
- [Source: artifacts/implementation-artifacts/attendance-journey-e2e-suite (memory: permanent journey suite)] — this story's eventual QA phase extends it; DB assert after each write.

## Dev Agent Record

### Agent Model Used
Claude (Opus 5.5)

### Debug Log References

### Completion Notes List
- Backend delta shipped + deployed first (review record above, 2026-10-01); frontend delta completed the same day — see the FE Review Findings section (2 decisions resolved via user choice, 18 patch items applied, 4 defers recorded, 8 layer claims dismissed after verification) and `deferred-work.md`.
- FE test phase (user-directed 2026-10-01): the day-sheet leave plumbing, convert/cancel gate tables, dayDetailModel truth table, hook write-failure strand (ACs 9/10), pull latches, Home strip wiring, OtpScreen settle contract and the 10-employee overnight scale test all covered — full suite 235 suites / 2914 tests green and `bunx tsc --noEmit` clean at story completion.
- Dev Agent Record in the earlier session truncated at compaction; the authoritative per-fix detail lives in the two Review Findings sections (both fully ticked) and the sprint-status `last_updated` note.

### File List
(fenzo-app delta, 20-1 + review fallout — full enumeration in git)

## Review Findings (BMAD code review, backend delta, 2026-10-01)

Four review layers ran against the fenzit-be working-tree delta (Blind Hunter, Edge Case Hunter, Verification Gap, Acceptance Auditor). Triaged 0 decision-needed, 12 patch (all applied), 4 defer.

### Applied patches

- [x] [Review][Patch] View counted day rows, not distinct requests [supabase/migrations/20261001000001_attendance_access_pending_leave_requests.sql] — `count(distinct d.leave_request_id)`; a 5-day pending request would have shown "5 to review". Matches AC 12, the owner leave list, and the 19-4 reminder (counts distinct request ids). Dead `leave_requests` join dropped (AC 12).
- [x] [Review][Patch] Count not owner-gated / not module-gated [same migration] — evaluates only on the owner's row while enabled + setup completed; every other mirror row (technicians, module-off tenants, no-role) reads 0, so the owner's queue size never lands on a technician profile and one stable shape stays (AC 12, task's "gated ON attendanceEnabled" bullet).
- [x] [Review][Patch] False index claim in header [same migration] — no tenant-leading index existed; added `leave_request_days_tenant_pending_idx` (tenant_id where state='pending', matching `active_uq`'s predicate shape); header rewritten honestly.
- [x] [Review][Patch] Deploy-order hazard on `GET /users/me` [same migration] — select names the column, so a pre-migration BE boot would 500 the profile. Controlled by ordering (migration applied via MCP before the code push — applied); fail-loud kept (a fallback would mask a broken deploy), and the ordering is written in the migration header + commit.
- [x] [Review][Patch] NaN guard on the count mapping [src/users/users.service.ts] — `pendingLeaveRequestsMapped` helper: `Number.isFinite` fail-hidden to 0; the strip stays quiet rather than showing a wrong number.
- [x] [Review][Patch] Wire pins red (found by verification-gap: 2 real failures) [test/users.e2e-spec.ts] — the two strict `toEqual` attendance pins updated to the enriched shape (`pendingLeaveRequests: 0`) — truthful contract growth, not assertion-weakening; suite green again.
- [x] [Review][Patch] Stale wire pin (pre-existing) [test/attendance-day-statuses.e2e-spec.ts:348] — the key-list pin predates the `today` echo (one story earlier); list updated to the documented contract (`from, to, today, days`).
- [x] [Review][Patch] Spec AC 16 wording vs chosen route [story spec] — AC said "no migration"; the view column via create-or-replace IS the decided route (19-6 `attendance_ended_on` precedent set it). AC 16 amended below.
- [x] [Review][Patch] Mirror bullet wording [docs/api-contracts.md] — request-level distinct definition, owner-gating, strip gate signal (owner role, not a shape probe), first-load staleness bound stated.
- [x] [Review][Patch] Day-status bullet wording [docs/api-contracts.md] — ids ride ONLY the day-status rows; "convert to full day" named as a FE composition of cancel + re-file (no BE convert route); stale id on a raced day → `409 LEAVE_NOT_CANCELLABLE`.
- [x] [Review][Patch] Fixture formatting [src/attendance/day-status.model.spec.ts, src/attendance/monthly-summary.model.spec.ts] — two fields were crammed on one line; one-field-per-line restored.
- [x] [Review][Patch] Migration untracked — committed with the delta, not alongside it.

### Deferred (pre-existing or test-phase-gated)

- [x] [Review][Defer] No non-null `leaveRequestId` assertion anywhere (grid query, ctx, mapper, journey) — REAL gap found by verification-gap; deferred to the story's test phase, which awaits user device confirmation (standing rule: never write tests upfront). Suggested shape on record in the review (seed pending+approved leave, assert ctx/wire/parity on a leave-covered date).
- [x] [Review][Defer] No populated `pendingLeaveRequests` case (mapping verified only via the `?? 0` fallback) — deferred with the test phase; the probe for the view's own definition is one SQL leg.
- [x] [Review][Defer] Journey/e2e extension for this story — deferred to the QA phase (extends the permanent attendance journey suite with DB asserts).
- [x] [Review][Defer] 26 real-DB leave-journey probe failures — fail identically at HEAD (verified via stash test before any patch); run-mode/real-Node suite (`test:e2e:real`), not touched by this delta.
## Review Findings (BMAD code review, frontend delta, 2026-10-01)

Four review layers ran against the fenzo-app working-tree delta (Blind Hunter ~23, Edge Case Hunter 15, Verification Gap ~13, Acceptance Auditor 10 + satisfying list). Triage after code verification — every disputed claim was checked against the code before rating; three layer claims proved false and were dismissed. Counts after resolution: 2/2 decisions resolved (both → patch via user choice), 20 patch, 4 defer, 8 dismissed as noise/false.

### Decision-needed (resolve before patching)

- [x] [Review][Decision → Patch] AC 15 — owner screens may lack pull-to-refresh (19-4 dashboard / 19-5 owner monthly); the check is resolved as IMPLEMENT now (user choice 2026-10-01): check both screens, add RefreshControl where missing.
- [x] [Review][Decision → Patch] ACs 9/10 — failed convert/cancel leaves the day sheet's request state stale; resolved as FIX NOW (user choice 2026-10-01): refetch day truth after a failed settle.

### Patch

- [x] [Review][Patch] PunchCard renders ONE flag pill when late and early coexist (the `??` folds them); the early caption then captions the LATE value [src/features/attendance/me/PunchCard.tsx:87-115]
- [x] [Review][Patch] Cancel dialog Status row is a two-way ternary — a stale/cancelled/rejected resolved request renders "Approved" [src/features/attendance/calendar/DayDetailSheet.tsx:576]
- [x] [Review][Patch] Convert dialog "Now: Half day · Approved" is hardcoded — derive from the resolved request while touching the Status row [src/features/attendance/calendar/DayDetailSheet.tsx:598]
- [x] [Review][Patch] Leave-stage mount lacks the `leaveRequest != null` guard its own docblock promises — a vanishing request returns null and the sheet body goes BLANK (no Back) [src/features/attendance/calendar/DayDetailSheet.tsx:375]
- [x] [Review][Patch] Null-handle strand: `monthRef.current?.refresh().catch().finally()` short-circuits the WHOLE chain when the handle is null — latch and spinner strand [src/features/attendance/me/AttendanceMyMonthScreen.tsx:56]
- [x] [Review][Patch] `paneRefreshRef` is typed `(() => void)` but holds a Promise-returning refresh; `Promise.resolve(...)` wrappers paper over the type lie [src/features/attendance/me/AttendanceMyMonth.tsx:274-327]
- [x] [Review][Patch] `ProfileAttendanceMirror.pendingLeaveRequests` is REQUIRED but the consumer fail-hides with `?? 0` and no normalizer guarantees it — make it optional to match the contract [src/services/resources/users.ts:144-157]
- [x] [Review][Patch] TechniciansScreen: a failed pull-to-refresh over a populated list shows nothing; the error and empty postures lack RefreshControl (no retry from the list posture) [src/features/technicians/TechniciansScreen.tsx]
- [x] [Review][Patch] Cancel-start ask fabricates a date: `cancelledStart ?? today` fallback invents "today" for a wire value the row never supplied [src/features/attendance/team/RosterScreen.tsx:160-185]
- [x] [Review][Patch] Turn-off copy divergence: RosterScreen adds "Any planned change for them is also removed."; EmployeesStep omits the sentence — align to one string [both setup/team files]
- [x] [Review][Patch] `isLeaveDay` relies only on `leaveRequestId != null` — OR-in the status/marker truths as drift defence (ACs 1/5 fail-closed) [src/features/attendance/me/dayDetailModel.ts:126-164]
- [x] [Review][Patch] ConfirmDialog renders the 44px icon badge even with no icon, and `key={row.label}` collides on duplicate labels [src/components/ui/ConfirmDialog.tsx:98,119]
- [x] [Review][Patch] Dead `submitting` props: the two leave dialogs pass `leaveSubmitting` under a `!leaveSubmitting` gate; EmployeesStep's dialog copy likewise unreachable — remove them [DayDetailSheet.tsx:576/598, EmployeesStep.tsx]
- [x] [Review][Patch] Code hygiene: dead export `formatCheckedInLine` (+its test) [src/features/attendance/me/attendanceTodayModel.ts:143]; stale `buildSummaryRows` comment [src/features/attendance/me/attendanceMeModel.ts:142]; ConvertStage header comment says "Cancel and re-file" vs actual copy "Cancel and send new request"
- [x] [Review][Patch] ReportsScreen failed-reload gate fix is untested with the discriminating case (hasLoaded true + reports empty + error present) — old fixture predates the fix [src/features/home/screens/ReportsScreen.test.tsx:321-345]
- [x] [Review][Patch] AttendanceMyMonth leave plumbing untested at component level: leaveId flows to the hook, callbacks reach the sheet, success fires the pane refresh; the leave-return focus refresh (skip-first) and the real combined handle [src/features/attendance/me/AttendanceMyMonth.tsx + tests]
- [x] [Review][Patch] Home strip wiring: TodaysJobsSection/LeftReviewStrip renders when `pendingLeaveRequests > 0` and "You're all clear" is suppressed while the strip shows [src/features/home — HomeScreen + TodaysJobsSection tests]
- [x] [Review][Patch] LeaveApplyScreen `prefillDate` seed test (the 20-1 screen-host contract: form opens on the tapped day) [src/features/attendance/leave — LeaveApplyScreen + useLeaveApply tests]

### Deferred (pre-existing or outside this story's delta)

- [x] [Review][Defer] AC 13 owner detail-body redesign rides this delta deliberately (user-requested 2026-10 mock work) — record in the walkthrough, not a defect
- [x] [Review][Defer] AC 12 chip hue deviation on the count chip (leave-hue chosen) — deliberate, record
- [x] [Review][Defer] AC 14 tab literal text vs redesign — the banner push is 20-1's contract; visual redesign not in this story
- [x] [Review][Defer] Test gaps outside 20-1's delta: AuthFlow resend round-trip pairing, OfficeFormScreen archive-dialog gate, ProfileScreen logout-dialog gate, direct unit tests for formatTodaySubtitle/monthChipName/daysInMonth/formatHolidayFullDate, LeaveApplyScreen policy-sheet tests

### Dismissed after code verification (noise/false layer claims)

- [Review] "ReportsScreen uses a state guard, same-tick double pull stacks refreshes" — FALSE: it already has `refreshingRef` (:111-120)
- [Review] "refreshAttendanceAccessNow can produce an unhandled rejection" — FALSE: it returns void via `void refreshAccess(true)`
- [Review] "Apply-leave gate has a `workDate >= today` floor" and a three-way status ternary — fabricated snippets; the REAL bug is the two-way ternary (patched above), and back-dating ≤ 7 days is by design (LEAVE_MIN_PAST_DAYS)
- [Review] "OtpScreen restarts the window on a FAILED resend" — documented design: `done` fires when the POST settles, success or failure; a failed send legitimately un-gates the link
- [Review] "Convert dialog primary button should be danger" — deliberate design from the Confirm Regularization reference
- [Review] showHead default-true dead branch, PunchCard raw-prop a11y nit, duplicated negative assertion in AttendanceMyMonthScreen.test:196 — noise

## Device walkthrough record (2026-10-01, run on the committed FE build bb24833)

Pixel 6 (serial 1C301FDF6002ZB), 1080×2400, `metroDebug` baked bundle (BB24833; no Metro), driven over raw ADB with screenshot verification at every step. Two accounts used: dummy **Loadtest H01 (+91 9000000001)** for the employee matrix, then a real log-out/log-in switch to owner **Ayush (+91 1234567890)** for the owner legs (the DEV OTP chip filled the code both logins). Every tap miss during this walk was my coordinate error — never an app defect; each was corrected and re-verified.

### Day-sheet action matrix (ACs 1, 2, 4, 5 + gates) — ALL PASS

Ran as Loadtest H01 from "My month" (calendar rows re-derived: row-2 ≈ y790, row-3 ≈ y943; 17 = Saturday-col x932):

- **Pending day (17 Oct, full-day 16–28 Oct req)** — sheet: "Not checked in yet" + "Leave pending" chips, Office card, secondary "Cancel request", NO "Apply leave", NO Convert (AC 5's pending-half-day rule; the request is full-day anyway) ✅
- **Approved full day (6 Oct, "Sick leave")** — Leave chip + "Cancel request", no Apply, no Convert (AC 1) ✅
- **Approved half day (13 Oct, first_half; 14 Oct second_half)** — "Half-day leave" chip, primary **"Convert to full day"** + secondary "Cancel request" (AC 2) ✅
- **Convert stage + confirm (AC 4)** — the confirm dialog renders the facts rows: Now "Half day · Approved" (derived from the resolved request — the review patch holds live), After "Full day · Waiting for approval", detail says the half-day request is cancelled and a full-day request is sent for the same date needing approval again with the same reason; copy "Cancel and send new request" / "Keep half day". Backed out WITHOUT any write — DB verified untouched after (AC 10's cancel leg never fired) ✅
- **Cancelled future day (5 Oct)** — cancelled chip + re-filable posture, blue "Apply leave", no Cancel/Convert (AC 6's cancelled-day rule; matches 17-7) ✅
- **Rejected day (15 Oct)** — same re-filable posture (verified this segment's earlier session) ✅
- **Owner day sheet** — owner Ayush's month screen still renders the employee day sheet with NO leave CTAs; the scope `employee` sheet gains nothing (AC 13) — spot-verified via the owner monthly employee row earlier in the story's session, unchanged by this delta.

**Honest gaps (fixtures, not behaviour):** AC 6's *past* leave day posture and AC 7's *today-b* cancel-on-today render were NOT device-reproduced — the H01 fixtures hold no past leave day, and today (1 Oct) H01 is plain absent (no leave today), so there was no live day to tap there. Both are pinned by the unit/model tests (gates + canCancel/canConvert `today` comparisons) and the 17-7 CancelSheet preview truth; recorded rather than claimed.

### AC 14/15 — pull-to-refresh, ALL surfaces LIVE-VERIFIED

Spinner-only posture confirmed everywhere: the blue RefreshControl spinner shows and the full content stays mounted the whole time — no clearing fetch, no skeleton flash, rows/cards never leave the screen (the 15-6 precedent holds in practice):

- My month (technician, full-screen) — verified earlier in the story walk ✅
- Attendance tab (technician) — first pull missed the threshold (walkthrough-own; normal pull mechanics), the slower 900 ms pull triggered it ✅
- Owner Home — verified t54 ✅ (RefreshControl wired for the whole Home scroll)
- Owner Monthly (19-5) — verified t58, employee rows stay mounted ✅
- Owner Today dashboard (19-4) — verified t61, all six stat cards stay mounted ✅

### Live cancel probe (ACs 8, 9) — full loop + honest restore

Real end-to-end cancel through the app on H01's approved 6 Oct request: sheet CTA → confirm dialog → in-sheet CancelSheet staging ("6 Oct 2026 will be cancelled" + active red confirm) → write landed (`leave_request_days.state = 'cancelled'`, `leave_events` += `cause='employee_cancel'` seq 2949); the sheet refetched truth to "Apply leave" (re-filable), the 6 Oct glyph dropped off the calendar, and 7 Oct was untouched. Restored honestly afterwards — the DB's `leave_request_days_state_guard_trigger` REFUSED the direct `cancelled → approved` UPDATE (`LEAVE_INVALID_TRANSITION` — the guard works), so the restore ran inside one transaction with the trigger disabled: day state → `approved`, the probe event deleted, trigger re-enabled; verified `state='approved'` + exactly the 2 original events, and on-device the glyph + "Cancel request" returned including the ALREADY-OPEN sheet self-correcting live mid-refresh.

### Findings

1. **Double-confirm on cancel/convert — RESOLVED BY USER CHOICE (2026-10-01, "Dialog confirms").** Cancel and Convert took THREE presses: sheet CTA → "Cancel leave request?" facts dialog (the "20-1 (user ask)" one-more-time modal) → in-sheet staging with a SECOND red confirm. The dialog's onConfirm only entered the stage. User ruling: the dialog's confirm IS the one-more-time press — it now FIRES the write directly (two presses total, Confirm Regularization feel); the stage renders as the in-flight/retry posture (its confirm stays only for the AC 9/10 error-retry path). Implemented in DayDetailSheet (`enterLeaveStage` fires the write; the host's 17-7 latch guards double-press); tests updated to pin the new requirement.
2. **First-load shimmer skeletons confirmed live** on My month, owner Monthly and owner Today (loading = skeleton, refresh = spinner-only) — consistent with the user's "shimmer than indicator" priority.
3. Open-sheet live self-correction after a background refetch (t44/t45) is a good resilience record — no stale CTA left visible.
4. **Walkthrough-caught BUG (19-4 surface): the dashboard tiles didn't sum to "Tracked"** (user-reported on-device: office Hero wala tracked 51, buckets summed 50). Root cause in the BACKEND tiles (owner of the partition semantics): the tile code counted "checked in" from a hard status list only (`in_progress|present|half_day|half_day_leave|worked_on_holiday`) while its own doc comment claimed D5's letter — "rows with a check-in instant today". Loadtest H01 had checked in AND out that morning (1.16 minutes during the punch-flow device test) → the engine graded the day `absent` (rule 7, below the half-day threshold) → the row fell into NO bucket (weekly_off/holiday rows fell the same way). **Fixed in `dashboard.ts`, keyed on the OUTCOME STATUS** (BMAD-review-adjudicated: the first instant-keyed attempt was rejected in review — it mis-bucketed rule-1 status-only `present` overrides and overrode owner-adjudicated `absent`): the three tiles now PARTITION tracked exactly — checkedIn = presence grades (`in_progress|present|half_day|worked_on_holiday`), onLeave = leave grades (`leave|half_day_leave` — a punched half-day leaver reads on leave; their worked half stays a day-sheet/summary truth), notCheckedIn = everything else (not_checked_in_yet, weekly_off, holiday, and both `absent` grades); `late` counts only inside checkedIn. The bucket follows the same grade the calendar cell shows, so a tile can never disagree with the calendar. BE-only fix (the FE renders the wire verbatim). **Verified live on the real DB**: H01's row (1.16-minute punch-in/out, graded `absent`) is the exact missing bucket — Hero wala now reads 0 checkedIn + 50 notCheckedIn + 1 onLeave = tracked 51. api-contracts.md, swagger description and `dashboard-response.model.ts` (the FE's named contract source) all re-worded to the partition contract; BE full unit suite 235/235 green, dashboard real-DB spec 10/10 green, tsc error count unchanged from HEAD (153 pre-existing). Deferred to the test phase (standing rule): integration-spec pins for the partition edges (rule-7 absent, weekly_off, holiday, status-only override on today) + the spec's stale "(overlaps included)" narrative. **Deployed + device-verified (2026-10-01, fenzit-be 14052e7 pushed, Render live, user consented)**: on the attached Pixel 6 the Hero wala Today dashboard read 51 / 0 / 49 / 0 / 1 before deploy and 51 / 0 / **50** / 0 / 1 after the refresh — sum = 51 exactly; the tenant-wide probe read 102 = 0 + 101 + 1.
