---
title: 'Revoke & cancel with split-outcome preview — owner Revoke stage (reason-required, live split) and employee Cancel stage inside the 17-6 detail sheet'
type: 'feature'
created: '2026-09-29'
status: 'reviewed'
review_loop_iteration: 1
baseline_commit: '17-6 tree (this story lands only after 17-6 is committed — see D0)'
context:
  - '{project-root}/artifacts/planning-artifacts/epics-attendance-leave.md'
  - '{project-root}/artifacts/planning-artifacts/prds/prd-Fenzo-attendance-2026-09-25/prd.md'
  - '{project-root}/artifacts/planning-artifacts/ux-designs/ux-Fenzo-2026-09-25-attendance-leave/DESIGN.md'
  - '{project-root}/artifacts/planning-artifacts/ux-designs/ux-Fenzo-2026-09-25-attendance-leave/EXPERIENCE.md'
  - '{project-root}/artifacts/implementation-artifacts/spec-17-1-to-17-4-backend-leave-management.md'
  - '{project-root}/artifacts/implementation-artifacts/spec-17-6-frontend-leave-history-pending-queue.md'
---

# Spec — Story 17-7: Revoke & Cancel Sheets with Split-Outcome Preview (Frontend)

- **Story:** 17-7 only (check-in leave/holiday dialogs are 17-8). One spec, one review, one commit.
- **Repo:** fenzo-app only. BE shipped (17-1..17-4 + `3684775`); previews and split writes are live routes. Files ≤ 300 lines.
- **Status:** Spec revised after adversarial review v1 (§7): UX/state lens (11 findings, SHIP-WITH-PATCHES), wire-truth lens (8 findings, SHIP-WITH-PATCHES), UX design pass (6 amendments). All patched; §6's five open questions settled — zero open questions ship.
- **Sources:** epics-attendance-leave.md §17.7; PRD FR-14, FR-15, FR-22; UX EXPERIENCE.md ("Revoke sheet (Owner, FR-14)", "Cancel (Employee, FR-15)", Voice & Tone, Interaction Primitives, State Patterns) + DESIGN.md (revoke/cancel composition note, `danger.action`); spec-17-1-to-17-4 §2 D4/D7/D8 + §4; spec-17-6 (host surfaces: LeaveDetailSheet, per-tab/employee-list semantics, chip table, split block).
- **UI copy rule:** plain simple English; server messages verbatim except the mapped 409s (D5).

## 1. Fix-placement analysis

| Concern | Layer | Why |
|---|---|---|
| The split rule, source-state pinning, own-retry/409 semantics, previews | **BE** (shipped) | AD-23's single writer; the FE renders `actionDates`/`keepDates`, never computes the split. |
| Stage composition, split presentation, reason gate, confirm flows, list invalidation | **FE** | Presentation over shipped previews. |
| DB | **none** | |

## 2. Design decisions

**D0 — Sequencing.** Lands only after 17-6 is committed; wires into its real components. `leaveStatusModel.ts` (the range-label helper this story imports) is a 17-6 file — no second date-grammar implementation anywhere.

**D1 — Composition: a stage MORPH inside the existing detail Sheet (settled Q1 — not a stacked second Sheet).** Evidence: 17-6's Reject is already a two-stage swap inside `LeaveDetailSheet`; stacked TrueSheets are an untested native edge the repo has consistently routed around (the picker-over-sheet case went full-screen); one native sheet = one copy of `dismissible={false}`/latch/already-handled machinery; the success semantics (return to the refreshed detail view) are trivial in a morph. `RevokeSheet.tsx` / `CancelSheet.tsx` are **stage components rendered inside** the detail sheet's native `Sheet`; the sheet owns a stage enum (`detail → revoke | cancel → detail`) and swaps title/subtitle; stage state (reason, preview, errors) resets on every stage entry (the ReassignOfficeSheet fresh-state idiom). Fallback pinned: if the walkthrough finds the content-swap janky at the `['auto']` detent, the stage re-hosts in its own `Sheet` untouched — model and copy are component-agnostic. **Preview is refetched on EVERY stage entry, never cached** (the split is time-sensitive: cutoff, midnight). While loading: centred ActivityIndicator in the hero slot, confirm rendered disabled, reason editable.

**D2 — The split hero (AC: the outcome up front, at the moment of decision).** Two icon+text lines in existing list-row typography, directly under the sheet header, no box/card/tint (DESIGN.md: "no new visual element"), one accessible composite (model-emitted label, VoiceOver reads it as one sentence): **stays line first** (`CheckCircle2` in `colors.status.done.fg`): "{summary} stays|stay Approved|Pending (already started or past)" — plural rule 1-vs-2+, the stays-word derives from `keepDates[].state` (a Pending request's past days read "stay Pending" — wire lens #4; the literal "stay Approved" is revoke-context-only); **action line second** (`Undo2`/`CalendarX` in `colors.danger`, text stays ink): "{summary} will be revoked|cancelled" + " (including today)" when the actionable set contains today. Range summaries via `leaveStatusModel`'s shared helper (no weekday prefixes — the per-day block carries per-date precision; a second date grammar is banned). `keepDates[].reason` ('past'|'cutoff_passed') is **deliberately never branched on** — the one-time "(already started or past)" parenthetical covers both without the AC's banned per-date cutoff callout (model truth-table pins "reason is not branched on"). **Per-day chip block (17-6's, verbatim) renders inside the stage, split-only** — when `request.dates` mixes states beyond the hero's two groups (a check-in-auto-cancelled day inside an Approved request must be visible at the decision moment, or the sheet's arithmetic visibly doesn't add up). **Nothing-actionable, two shapes (wire lens #5):** `actionDates` empty + `keepDates` non-empty ⇒ hero swaps to `InlineNotice` neutral "Nothing can be revoked|cancelled — the whole request has already started." and the reason field + confirm are **hidden** (a permanently dead primary is a rote-click trap; Back/close are the exits); **both arrays empty** (stale sheet / zero source-state days) ⇒ the already-handled notice (D3) instead — the honest copy for a request that no longer has the assumed shape.

**D3 — Owner Revoke: entry, gate, confirm, outcomes.** Entry: 17-6's terminal Approved branch gains one action in the bottom action slot — `Button` `secondary` lg with `labelColor: colors.danger`, label **"Revoke leave"** (outline-danger entry = the landed Reject grammar; solid danger is reserved for the moment of commitment; `danger.action` is the DESIGN.md-sanctioned colour for revoke). Stage: title "Revoke leave", subtitle "{employeeName} · {date range}"; hero per D2; reason `Input` multiline ("Reason (required)" + asterisk, placeholder "Why is this leave being revoked?", maxLength 500, "{n} / 500" counter, ref-focused on stage mount); action row = full-width solid `danger` lg confirm + `ghost` lg **"Back"** (the safe exit) — confirm **disabled until `reason.trim() !== ''`** with `accessibilityState={{disabled}}` (the Correction-sheet gate; no error-shaming banner for an untouched field; the gate makes the wire's DTO 422 unreachable — verified `RevokeLeaveDto` trims + rejects empty-after-trim). Confirm label by context (settled Q3): whole-request (keepDates empty) ⇒ **"Revoke leave"**; split ⇒ **"Revoke remaining days"** (consequence-specific verb phrase, NN/g P1). Mechanics: submitting latch, `loading`, `dismissible={false}` + guarded `onClose` mid-write, Back disabled mid-write; `POST /attendance/leave/:id/revoke {reason}`.
**Outcomes (all 17-6 mechanics):** success ⇒ announce **"Leave revoked"** ⇒ stage morphs back to the refreshed detail view (chip flips grey Revoked only on a FULL revoke — a split revoke's derived status stays `approved` and 17-6's "· N of M days revoked" row suffix appears; **the success presentation is built from the WRITE response's `revokedDates`, never the preview**, and the arrays are optional on the wire — an own-retry 200 returns the bare view without them, so handlers never read them unconditionally); a preview/write divergence (e.g. an employee check-in auto-cancelled today between preview and confirm) is absorbed silently — the write is authoritative; `409 LEAVE_NOT_REVOKABLE` (cross-actor conflict — e.g. Arya cancelled in the owner's confirm window) ⇒ "This request was already handled" + OK that closes the WHOLE sheet (the detail view is stale too) + the row/list refetch per D5; own-retry 200 (same owner retrying after their own revoke — the single-owner tenant) ⇒ success path, second announce accepted; preview-fetch failure ⇒ non-dismissible `InlineError` ("You're offline. Revoking needs a working connection." / "Couldn't load the preview. Check your connection." / server verbatim) + `secondary` "Retry".

**D4 — Employee Cancel: same stage, no reason (settled Q2/Q5).** Entry: 17-6's employee read-only detail branch gains **"Cancel request"** (never bare "Cancel" — on a sheet that reads as the dismissing action) for Pending/Approved, same slot and outline-danger treatment. Stage: title "Cancel this leave request?" (UX-verbatim), subtitle "{date range} · {n} working day(s)"; hero identical minus the reason field everywhere (FR-15); confirm labels "Cancel request" (whole) / "Cancel remaining days" (split); `previewCancel` on every entry; `POST /attendance/me/leave/:id/cancel` (no body). **The split rendering is unconditional-with-degenerate-form, not a branch (settled Q2):** the past-Pending case is a standing reality, not a transient edge (apply up to 7 days back + Pending never expires — probe 22), so `keepDates` non-empty renders the split with "stay(s) Pending"; keepDates-empty renders the single-line plain confirm. Documented deviation: EXPERIENCE's "reached from a history row" becomes sheet-entry — mirroring the owner side; 17-6 pre-built this sheet as the Cancel home; the row stays tappable-to-sheet so nothing is farther than one tap. Outcomes mirror D3: announce **"Leave cancelled"**; chip flips grey Cancelled on full cancel (partial cancels keep the derived chip + suffix, same derived-status truth); `409 LEAVE_NOT_CANCELLABLE` (e.g. the owner partially revoked in the employee's confirm window) ⇒ already-handled + whole-sheet close; own-retry 200 ⇒ success.

**D5 — Copy table (complete; simple English; server messages verbatim except the mapped 409s).**

| Context | String |
|---|---|
| Owner entry button / stage title | "Revoke leave" / "Revoke leave" |
| Stage subtitle | "{employeeName} · {date range}" |
| Stays line | "{summary} stays|stay Approved|Pending (already started or past)" |
| Revoke action line | "{summary} will be revoked" · + " (including today)" |
| Revoke nothing-actionable | "Nothing can be revoked — the whole request has already started." |
| Reason | label "Reason (required)" · placeholder "Why is this leave being revoked?" · counter "{n} / 500" |
| Revoke confirm (whole / split) | "Revoke leave" / "Revoke remaining days" |
| Employee entry button / stage title | "Cancel request" / "Cancel this leave request?" |
| Cancel stage subtitle | "{date range} · {n} working day(s)" |
| Cancel action line | "{summary} will be cancelled" · + " (including today)" |
| Cancel nothing-actionable | "Nothing can be cancelled — the whole request has already started." |
| Cancel confirm (whole / split) | "Cancel request" / "Cancel remaining days" |
| Shared | "Back" · "Retry" · "This request was already handled" · "OK" |
| Preview fail | offline "You're offline. Revoking|Cancelling needs a working connection." · transport "Couldn't load the preview. Check your connection." · else server verbatim |
| Write fail | the same offline strings · else server `ApiError.message` verbatim |
| Announcements | "Leave revoked" · "Leave cancelled" (failures ride the alert-role banners) |
| A11y hero composite | "3 days stay Approved, 14–16 Sep. 2 days will be revoked, 17–18 Sep." (model-emitted counts + lists) |

**D6 — Service + accessibility.** `attendanceLeave.ts` += `previewRevoke(id)`, `previewCancel(id)` (shapes `{action, actionDates, keepDates: {date, state, reason}[], request}` — verified field-exact; empty `actionDates` = 200 empty, never 409), `revokeLeave(id, reason)`, `cancelLeave(id)` (refreshed view + OPTIONAL `revokedDates`/`cancelledDates` — own-retry omits them). **A11y floor:** the hero is one composite with the model-emitted label; the async-arriving split announces via a polite live region (a screen-reader user must not hear a spinner and silence); the nothing-actionable notice announces; confirm carries `accessibilityState={{disabled}}` + the required label explains why; stage open/close swap the sheet title (announced via the sheet's header semantics); reading order = stays line → action line → per-day block → reason → confirm (the visual order); 44px everywhere; Dynamic Type reflow.

## 3. Code layout (files ≤ 300 lines)

| File | Contents |
|---|---|
| `services/resources/attendanceLeave.ts` | +D6 four functions (+optional split-array types). |
| `features/attendance/leave/leaveSplitModel.ts` (new) | Pure: group summaries (plural stays/stay, status-derived stays-word, "(including today)", both-empty predicate), the a11y composite label, "reason is not branched on" pin; imports the range helper from `leaveStatusModel.ts` (17-6) — no second date grammar. |
| `features/attendance/leave/LeaveSplitSummary.tsx` (new) | Shared presentational hero (icon+text lines + a11y composite) + per-day chip block hosting — one implementation for both stages (the 17-6 LeaveApplyFields extraction precedent). |
| `features/attendance/leave/RevokeSheet.tsx` (new) | D3 stage component (rendered inside the detail sheet's Sheet). |
| `features/attendance/leave/CancelSheet.tsx` (new) | D4 stage component (no reason). |
| `features/attendance/leave/LeaveDetailSheet.tsx` | 17-6's sheet: +stage enum, +entry actions (owner/Approved, employee/Pending-Approved), +title/subtitle swap, +refreshed-view absorption. **Growth budget:** if it exceeds 300 lines, the action row + stage wiring extract to `LeaveDetailActions.tsx` (the EnrolmentRowActions precedent) — decide at build, not after. |
| Tests | `leaveSplitModel` truth table (groups, plurals, both-empty, today-inclusive, composite label, reason-not-branched); stages: reason gate + accessibilityState, loading/fail-retry, nothing-actionable hides confirm, latch + dismissible mid-write, success (write-dates presentation), own-retry bare-view success, 409 whole-sheet close + refetch, divergence absorption; detail-sheet stage wiring + entry actions per role/state. |

## 4. Out of scope (explicit)

- Check-in leave/holiday dialogs — **17-8**.
- Any new split visual element; type-to-confirm; Undo (the counterpart's notification is server-side — an "undo" would re-notify and imply reversibility the wire doesn't have).
- Owner-side cancel / employee-side revoke (no such routes).

## 5. Device walkthrough plan (draft — user's device; production BE)

As **Ayush**: approve a multi-day leave as Arya → detail sheet shows the outline-danger "Revoke leave" entry → stage: split hero up front → empty reason keeps confirm disabled (with a11y state) → confirm "Revoke remaining days" ⇒ morph back to refreshed detail: **chip STAYS Approved + the row suffix "· N of M days revoked" appears** (the derived-status truth — a full-revoke variant is added to the script to also witness the grey flip) ⇒ both tabs stale; employee card arrives with the revoked dates. **Cutoff case re-sequenced (state lens #4: office rules take effect from TOMORROW — a 00:00 rule set today cannot flip today's split):** run the natural AC2 case at the office's real start time (today in stays-group after cutoff), and optionally set a 00:00 rule for a DAY-2 demo. **Already-handled replaced by the cross-actor races (wire lens #3 — same-actor API-revoke retries answer own-retry 200):** revoke-409 = Arya cancels (API) after the owner's preview loaded, owner confirms ⇒ already-handled + whole-sheet close; cancel-409 = owner partial-revokes (API) then Arya confirms her stale sheet. As **Arya**: cancel a plain future Pending request (single-line confirm), cancel an in-progress Approved request (split, no reason) ⇒ owner cards arrive; past-Pending split rendering witnessed. As-found restore: API-revoke any remaining approved probes, Reject pendings, **revert any office-rule change** (a leftover 00:00 rule corrupts every later check-in walkthrough), enrolments/logins restored.

## 6. Open questions

None — Q1 stage morph (D1, evidence-backed fallback pinned), Q2 degenerate-form split (D4), Q3 confirm labels (D3/D4), Q4 danger treatment (D3, DESIGN.md-sanctioned), Q5 single-confirm parity, no Undo (D4) — all settled in review (§7).

## 7. Adversarial spec review triage (2026-09-29) — 3 passes, step-03

UX/state lens (11 findings, SHIP-WITH-PATCHES) + wire-truth lens (8 findings, SHIP-WITH-PATCHES, no criticals) + UX design pass (6 amendments). Every finding source-verified (the reviewers' line cites + my reads of the derived-status order and the own-retry return shapes before accepting the two walkthrough corrections). **All 19 unique accepted and patched; 0 deferred; 0 dismissed.** Cross-lens convergences: the state lens read D3 as presupposing a stacked sheet; the UX pass argued the morph from repo evidence — resolved FOR the morph (better-evidenced, fallback pinned). The state lens's "confirm stays disabled" on nothing-actionable was amended by the UX pass to hide confirm+reason (dead-control rule) — adopted.

**Patched (state lens):** (1) HIGH five open questions → all settled (D1/D3/D4; Q4 from DESIGN.md `danger.action`, Q5 from Interaction Primitives, Q2's premise verified true via probe 22 + the 7-day floor). (2) HIGH draft copy table → the complete §5 table (plural rule, state-aware stays-word, parenthetical restored, cancel nothing-actionable, concrete offline strings, the one-line-vs-two-line contradiction resolved as two icon+text lines). (3) LOW `keepDates.reason` unrendered → explicit decision + model pin (D2). (4) HIGH cutoff walkthrough impossible same-session → re-sequenced + office-rule revert added to restore (§5). (5) MEDIUM 409 refetch + write-dates presentation + divergence absorption (D3). (6) MEDIUM Cancel nothing-actionable dead end → pinned incl. the request-stays-Pending acknowledgment (D2/D4). (7) MEDIUM employee-side list semantics → refetch first page + cursor reset + row replace (D4/17-6 semantics). (8) MEDIUM per-day chip block placement → inside the stage, split-only (D2). (9) MEDIUM undocumented deviations (sheet-entry Cancel; Pending-with-past split) → documented with rationale (D4). (10) MEDIUM a11y floor → enumerated (D6). (11) LOW shared `LeaveSplitSummary` extraction, ≤300 header, LeaveDetailSheet growth budget, leaveStatusModel dependency note (D0/§3).

**Patched (wire lens):** (1) MEDIUM own-retry 200 returns the BARE view — split arrays optional; handlers never read unconditionally (D6). (2) HIGH walkthrough's "chip flips Revoked" wire-false for split revokes (derived order reads approved first) → corrected + full-revoke variant added (D3/§5). (3) MEDIUM already-handled probes would own-retry 200 → replaced with the two cross-actor races (§5). (4) MEDIUM hardcoded "stay Approved" false for Pending keep-groups → state-aware (D2). (5) LOW nothing-actionable two shapes → keepDates-empty vs both-empty branches (D2). (6) LOW range helper lives in `leaveStatusModel` → import pinned (D0/D2). (7) LOW "verbatim except the mapped 409s" clause (D5 header). (8) LOW "transiently" framing → standing reality (D4). Verified true en route: preview shape field-exact; empty-actionDates = 200 never 409; exact-membership gates 403 both directions; revoke reason DTO-required (the FE gate makes the 422 unreachable); D8 split + `keepDates.reason` values + no-rule-⇒-actionable; write returns + own-retry cause-AND-actor semantics; 409 spellings; D0 coherence (LeaveDetailSheet absent at the 17-5 tree, created by 17-6 which explicitly defers the Approved branch to this story).
