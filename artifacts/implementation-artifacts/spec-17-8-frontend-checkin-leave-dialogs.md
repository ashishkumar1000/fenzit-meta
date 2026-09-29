---
title: 'Check-in leave/holiday confirmation dialogs — FR-9 pre-flight on the Today screen: full-day-leave confirm-and-cancel, half-day pass-through, wire-driven 409 fallback, confirmLeaveCancel wired'
type: 'feature'
created: '2026-09-29'
status: 'reviewed'
review_loop_iteration: 1
baseline_commit: '17-7 tree (lands only after 17-7 is committed — D0)'
context:
  - '{project-root}/artifacts/planning-artifacts/epics-attendance-leave.md'
  - '{project-root}/artifacts/planning-artifacts/prds/prd-Fenzo-attendance-2026-09-25/prd.md'
  - '{project-root}/artifacts/planning-artifacts/ux-designs/ux-Fenzo-2026-09-25-attendance-leave/DESIGN.md'
  - '{project-root}/artifacts/planning-artifacts/ux-designs/ux-Fenzo-2026-09-25-attendance-leave/EXPERIENCE.md'
  - '{project-root}/artifacts/implementation-artifacts/spec-16-3-and-16-4-frontend-location-and-check-in.md'
  - '{project-root}/artifacts/implementation-artifacts/spec-17-1-to-17-4-backend-leave-management.md'
---

# Spec — Story 17-8: Check-in Leave/Holiday Confirmation Dialogs (Frontend + one additive BE read)

- **Story:** 17-8 — the last Epic 17 story. One spec, one review, one commit.
- **Repo:** fenzo-app + ONE small additive BE change shipped first (§1 — the 16-4 prerequisite precedent: the pre-flight AC needs a fact no shipped read carries on the summary surface).
- **Status:** Spec revised after adversarial review v1 (§7): wire-truth lens (8 findings, SHIP-WITH-PATCHES), UX/state lens (13 findings, NEEDS-REWORK → all localised patches), UX design pass (RN-Alert-source-verified; 6 amendments). All patched; §6's five questions settled — zero open questions ship.
- **Sources:** epics-attendance-leave.md §17.8 (three ACs: full-day dialog, half-day pass-through, 409 fallback); PRD FR-9 (dialog string verbatim at prd.md:217); UX EXPERIENCE.md (CheckInOutButton pre-flight, Voice & Tone) + DESIGN.md (pre-flight = native dialog; the "button itself untouched" note vs the shipped spinner is an inherited 16-4 divergence — noted, out of scope); spec-16-3-and-16-4 (D2 capture, D4 ladder, D5 holiday dialog latch, D10 posture, D12 refreshes); spec-17-1-to-17-4 (D3 day-context leave seam, D11 the gate + auto-cancel).
- **UI copy rule:** plain simple English; the dialog title is PRD-verbatim.

## 1. Fix-placement analysis (incl. the additive BE change)

The AC's pre-flight ("a dialog appears **before any GPS fix is requested**") needs today's leave facts ON THE DEVICE before the POST. Honest fact table (wire lens #1 corrected the draft):

| Fact | Has today |
|---|---|
| `isWeeklyOff` / `isHoliday` / `isWorkingDay` | `me/summary.today` (16-3/16-4 D1) — the shipped holiday dialog runs on it |
| Today's leave as DISPLAY facts | `GET /attendance/me/day-statuses` (shipped in 18-1/18-2) — but unusable for the gate: status `leave`/`half_day_leave` covers APPROVED only, pending is a marker, `first_half` vs `second_half` is indistinguishable, it needs range params and a second request, and its today-cell defers on rule-10 boundaries |
| **The raw gate facts (`pending\|approved` × `full_day\|first_half\|second_half`) on the summary** | **NOWHERE** — `day-context` computes them only inside the check-in transaction (17-4 D3); the summary shares only the pure pickers, and its reads are supabase-js admin reads while the existing `findActiveLeaveForDate` is typed to a pg-transaction client |

| Concern | Layer | Why |
|---|---|---|
| Today's leave facts on the summary | **BE** (additive `today.leaveState` + `today.leavePart`) | AD-22: the day-context seam is the one implementation; the summary read MIRRORS its semantics (wire lens #2: it is a NEW supabase-client read — employee+date, `state in ('pending','approved')`, part via the request join, `maybeSingle` under the at-most-one partial index — with a parity note against `findActiveLeaveForDate`, `day-context.read.ts:106-108`; not a zero-SQL reuse). No schema change. Naming byte-parity: `leaveState: 'pending'\|'approved'\|null`, `leavePart: 'full_day'\|'first_half'\|'second_half'\|null` (day-context's own names). |
| **BE comment sweep (same commit):** `check-in-out.dto.ts:19-20` ("ignored until Epic 17") and `constants.ts:33-35` ("no writer until Epic 17") are stale since 17-4 D11 | **BE** | False comments mislead the next reader; one-line fixes in the D1 commit. |
| Pre-flight predicate, dialog, latch, fallback | **FE** | Presentation states; the server's gate stays the authority (NFR-2). |

**Shipping order:** BE lands → commit/push (auto-deploy) → FE consumes. The FE treats absence defensively: `today` present but `leaveState` absent ⇒ legacy ⇒ no dialog (the sub-field case, wire lens #8 — `normalizeTodayFacts` is a strict whitelist and MUST be extended or the fields vanish silently); `today` itself absent/undefined ⇒ legacy (16-4's existing signal).

## 2. Design decisions

**D1 — BE additive (shipped first): `me/summary.today` gains `leaveState` + `leavePart`.** Active state only; null otherwise (mirrors `todayRecord`). Reads: today's `leave_request_days` row in `pending|approved` joined to its request's `part` — the new supabase-client read mirroring the day-context seam, `maybeSingle` (at-most-one is index-guaranteed). `EMPTY_ME_SUMMARY.today` stays null-shaped. Controller swagger + `docs/api-contracts.md` updated. **Test matrix (state lens #12):** pending/approved × full/first/second; none → null; **cancelled/revoked → null** (the post-auto-cancel shape); **off-day-inside-leave → leaveState non-null with isWorkingDay false** (the read does not filter on working-day — exactly the shape the FE predicate must handle, and the BE gate already does).

**D2 — One predicate, byte-parity with the gate (settles the ladder-order question structurally).** The model gains one pure function and the hook consults nothing else for the leave branch:

```
needsLeaveConfirm(today, kind):
  kind === 'check_in'
  && today != null                      // undefined/absent fields = legacy → false
  && today.isWorkingDay === true
  && today.leaveState != null           // 'pending' | 'approved'
  && today.leavePart === 'full_day'
```

All four conjuncts of the 17-4 D11 gate (`check-in-out.service.ts:186-195`), mirrored 1:1 — a model test asserts byte-parity against the service condition (the draft's two-field key was not identical; wire lens #3). **`needsLeaveConfirm` and `needsHolidayConfirm` are provably mutually exclusive** (isWorkingDay conjunction): there IS no ladder-order rule to pin — leave+holiday can only ever surface the holiday dialog, exactly as the BE gate behaves. Half-day (`first_half`/`second_half`): **strictly nothing** — no dialog, no subtext, no copy anywhere (FR-9's letter; the gate is full_day-only, so pass-through is structural, Q4 settled). The drafting artifact "or second-half-??" is deleted (all three lenses flagged it).

**D3 — `confirmLeaveCancel: true` rides only the leave-dialog Continue path.** The FE service body gains the optional flag (BE DTO accepts it since 16-1 — no BE DTO change); it is NEVER sent from the holiday-dialog confirm or a normal working-day check-in. Every fresh tap re-runs `needsLeaveConfirm` at tap time — a remembered flag is never replayed silently.

**D4 — The 409 fallback is WIRE-DRIVEN, awaited inside the same press continuation (state lens #1/#2 — the draft's "re-run the pre-flight" was self-contradictory: the 409 fires precisely when the tap-time facts said no leave, so re-running them yields no dialog).** On `ATTENDANCE_LEAVE_CONFIRMATION_REQUIRED` (409; committed attempt row; budget-neutral — verified `COUNTED_OUTCOMES`): **show the leave dialog UNCONDITIONALLY, bypassing the pure facts function** — the exact same `Alert.alert`, byte-identical copy. Mechanics: the dialog is awaited inside the SAME `press` continuation via the shipped promise pattern (`confirmHolidayDialog(): Promise<boolean>`); `latch` and `dialogPending` are HELD across dialog + retry (a fire-and-forget re-dialog would release the button mid-fallback — the double-submit race the latch exists to prevent); the Continue handler re-runs the tap-time offline re-check (16-4's confirm-time re-check precedent); retry = **full fresh GPS capture + fresh idempotency key** (fresh-key is automatic in `submit`; fresh capture because the burned fix is stale by dialog-dismiss and would 422 `ATTENDANCE_STALE_FIX` — an error right after a second dialog is the worst posture on this surface; Q3 settled). **Terminal posture: a second 409 is a wiring regression** (a retry carrying the flag cannot 409 — the gate's `!confirmLeaveCancel` conjunct) ⇒ generic server-message error posture, NEVER another re-dialog (loop guard) + test. **Fallback-Cancel post-state: nothing renders** — the dialog was the communication; no error, no message. **The 16-4 holding string retires:** `messageForApiError`'s `ATTENDANCE_LEAVE_CONFIRMATION_REQUIRED` branch is deleted; the hook intercepts the code in `handleWriteError` (currently falls to default) — the AC copy lives in exactly one place, the dialog.

**D5 — Fact freshness, both directions.** The dialog reads tap-time summary facts (30 s min-gap + focus/foreground + forced refreshes per 16-4 D12); the server re-validates regardless (NFR-2). **Grant-staleness:** leave granted mid-session surfaces on the next refresh; until then the 409 fallback is the designed safety net — no urgency path on refresh timing. **Revoke-staleness (state lens #8):** facts say leave, owner revoked, tap ⇒ the dialog claims a cancellation that won't happen ⇒ Continue ⇒ the flag is inert (accepted-and-ignored unless the gate condition holds) and the check-in succeeds normally — accepted courtesy behaviour, pinned + tested (a flag-carrying submit against a no-leave day succeeds with no leave-cancelled outcome).

**D6 — Dialog design (UX pass; RN-Alert-source-verified).** Title **"You're on leave today. Checking in will cancel today's leave. Continue?"** (PRD-verbatim ask string). Body (one plain-English line, new copy — flagged for ratification; the user sees it live at the walkthrough): **"Your owner will be notified. Only today's leave is cancelled — your other leave days are not affected."** (universally true regardless of multi-day-ness — the FE cannot know span length from these fields; never says "approved" — leave may be pending). Buttons: **"Don't check in"** (`style: 'cancel'`, FIRST — safe button first = reading order; iOS cancel semantics; Android ignores style and the negative slot carries the safe role) / **"Check in"** (second). No `isPreferred` (no bolded default on either platform — a deliberate choice on a forfeit surface); no `style: 'destructive'` (check-in is legitimate forward action with a stated side effect; the owner notification makes it reversible-adjacent). **Ratified deviation from the draft's "Cancel"/"Continue"** (UX pass P2: outcome-specific labels; "Cancel" inside a dialog about cancelling leave misreads; sibling rhyme with the holiday dialog's "Check in"). **The state lens dissented** ("Cancel"/"Continue"; collision worry) — resolved FOR the UX pass: the research bar, the RN-source verification, and the user's UX-delegation grant; the dissent is recorded here. Platform mechanics (verified in the installed RN source): Android dialogs are **non-cancelable by default** — hardware back is a NO-OP while the dialog is up, both buttons always resolve the promise, the latch can never strand; `cancelable`/`onDismiss` are NEVER passed; "dismiss" = the Cancel button only, on both platforms (satisfies the AC). The native Alert self-announces on both platforms — no extra `AccessibilityInfo` call (the shipped holiday-dialog posture; the view's settled-outcome announcements already cover what follows).

## 3. Code layout (draft; files ≤ 300 lines)

| File | Contents |
|---|---|
| **fenzit-be**: `me-attendance.service.ts` (+ the new mirrored read), `me-summary-today.model.ts`, controller swagger, `docs/api-contracts.md`, `check-in-out.dto.ts` + `attendance.constants.ts` comment sweep (+ specs) | D1: two additive fields off a seam-parity read; the matrix of §1/D1 incl. off-day-inside-leave and post-cancel rows. |
| **fenzo-app**: `services/resources/attendanceMe.ts` | +`leaveState`/`leavePart` in `normalizeTodayFacts`' whitelist (else silently stripped) + the legacy sub-field semantics. |
| `services/resources/attendanceCheckIn.ts` | +`confirmLeaveCancel?: boolean` on the check-in body. |
| `features/attendance/today/attendanceTodayModel.ts` | +`needsLeaveConfirm` (the byte-parity predicate); DELETE the `ATTENDANCE_LEAVE_CONFIRMATION_REQUIRED` holding-string branch. |
| `features/attendance/today/useCheckInOut.ts` | D2–D4: the leave branch beside `needsHolidayConfirm`, the awaited wire-driven fallback (latch held), the flag plumb, the 409 intercept in `handleWriteError`. |
| Tests | Model: predicate parity (each conjunct, off-day-inside-leave, legacy absence, half-day false); hook: dialog fires pre-capture (no GPS call before it), Continue sends the flag + proceeds, Cancel/Dismiss sends nothing and releases the latch, half-day no dialog, 409 → unconditional re-dialog (facts function not consulted) with latch held → single fresh-capture retry with fresh key, second-409 → generic error never re-dialog, fallback-Cancel renders nothing, flag-carrying submit vs no-leave day succeeds normally. |

## 4. Out of scope (explicit)

- Day-status display of the cancelled leave; the midpoint in `todayRecord` (Epic 18).
- Check-OUT leave interactions (FR-9 is check-in only).
- The holiday dialog (shipped, 16-4) and the DESIGN.md "button untouched" spinner divergence (inherited 16-4 behaviour — noted for the record, not this story).

## 5. Device walkthrough plan (draft — user's device; BE deployed first)

As **Arya** (Active): owner applies on-behalf FULL-day leave for today via API **with Arya's app foregrounded and untouched** (the foreground refresh would otherwise foreclose the stale-facts precondition — state lens #11) → Check in ⇒ the dialog appears BEFORE the GPS step (no capture call — log-verifiable) → Android back inert (verified RN default; confirm on device) → "Don't check in" ⇒ nothing sent (DB: leave intact, no new attempt row), latch released, button ready → Check in → "Check in" ⇒ capture + submit with the flag ⇒ 201, today's leave row cancelled (DB-verified), owner card arrives, normal checked-in state. Half-day variant (on-behalf `first_half`): no dialog, straight to capture, leave intact after check-in. Fallback: same foregrounded-app precondition, tap before any refresh ⇒ 409 ⇒ the identical dialog ⇒ "Check in" ⇒ fresh capture ⇒ retry 201. **Second-409 never loops** (structural, but witnessed once). As-found restore: leave rows cleaned, the fallback probe's `leave_confirmation_required` attempt rows deleted, the owner `checkin_auto_cancel` notification removed, records/summary as-found, Ayush logged back in.

## 6. Open questions

None — Q1 buttons ("Don't check in"/"Check in", dissent recorded in §7), Q2 predicate parity (D2, structural), Q3 fresh capture (D4), Q4 half-day pass-through with zero nuance (D2), Q5 day-context-native naming (D1) — all settled in review.

## 7. Adversarial spec review triage (2026-09-29) — 3 passes, step-03

Wire-truth lens (8 findings, SHIP-WITH-PATCHES) + UX/state lens (13 findings, NEEDS-REWORK → localised patches) + UX design pass (RN-source-verified, 6 amendments). Every finding source-verified. **All 21 unique accepted and patched; 0 deferred; 0 dismissed. One inter-lens dissent resolved and recorded (D6 buttons — state lens's "Cancel"/"Continue" vs the UX pass's outcome-specific labels; resolved FOR the UX pass on research + RN-source + delegation grounds).**

**Patched (wire lens):** (1) HIGH the fact table now credits `me/day-statuses` honestly and justifies summary-today over it (no part enum, pending-as-marker, rule-10 deferral, range params, second request). (2) HIGH D1 reworded — a NEW supabase-client read mirroring the seam (the existing read is pg-tx-typed; the summary path is admin-client), parity note vs `findActiveLeaveForDate`. (3) MEDIUM the full four-conjunct predicate as THE key (draft omitted conjuncts). (4) MEDIUM "or second-half-??" artifact deleted. (5) MEDIUM Android-back claim demoted to a verified-mechanics pin (see D6; the UX pass's RN-source read settled it — non-cancelable default). (6) LOW stale BE comment sweep added to the D1 commit scope. (7) LOW holding-string retirement pinned in code (hook intercept + model branch deleted). (8) LOW normalizer sub-field legacy semantics pinned. Verified true en route: the gate's exact condition/placement, 409 mapping + budget-neutrality + committed attempt row, accepted-path auto-cancel scoping, DTO already accepting the flag, the shipped latch/re-check mechanics to extend, no notification→summary seam existing (D5's honest phrasing), swagger/api-contracts updates genuinely required, day-context-native field names.

**Patched (state lens):** (1) HIGH fallback made wire-driven, facts function never consulted (D4). (2) HIGH fallback awaited in the same press continuation, latch held, Continue re-runs the offline re-check (D4). (3) MEDIUM second-409 terminal posture + loop guard + test (D4). (4) MEDIUM predicate parity (dup of wire #3) + model byte-parity test. (5) MEDIUM dismissal mechanics corrected per the installed RN source + button descriptors byte-identical to the shipped pattern (D6). (6) MEDIUM all five open questions settled (D2/D4/D6 + §6). (7) MEDIUM artifact deletion (D2). (8) MEDIUM revoke-staleness pinned + test (D5). (9) LOW fallback-Cancel post-state + holding-string deletion (D4). (10) LOW DESIGN.md spinner divergence noted (§4). (11) LOW walkthrough preconditions + restore completeness (§5). (12) LOW D1 test matrix + post-cancel and off-day-inside-leave rows (D1). (13) INFO three ACs, not four — mapping 1:1 confirmed.

**Patched (design pass):** button labels + body line + emphasis posture (D6, dissent recorded); the mutually-exclusive-predicate insight that dissolved Q2 (D2); the same-dialog-verbatim fallback with latch-held + fresh-capture rationale (D4); half-day strict nothing (D2); a11y posture named as native self-announcement (D6); walkthrough additions (§5).
