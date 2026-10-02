# Attendance bug bash 2026-10-02 — Session B report (companion to `attendance-bug-bash-2026-10-02.md`)

**Read the main report first** — it carries the environment incident, the P0 auth pair (F1/F2), F3/F4/F8, and the
device walkthrough. This file is the **second agent session's independent pass** over the same night
(~01:15–03:15 IST): API-first negative/corner battery + DB truth + a shorter device pass before the collision.
**No fixes applied, nothing committed.**

## Authorship corrections for the main report's incident section

The two active sessions each saw the other as "the stale parallel session". True authorship of the contested rows:

| artefact | author |
|---|---|
| 4 correction writes 01:52–01:54 (`Bugbash: flip to present`, `Bugbash: past leave day correction probe`, +2 removals; seq 346–349) | **Session B (this file) — via API, owner token** |
| The "4h half-day probe" correction form + note + H03 login + H03's approved full-day leave today + H03's Oct 1 4h correction | **Session A (main report)** — device |
| Clock picker "opening by itself" ~02:05–02:09 on Session A's spinner | **Session B's adb taps** (check-in-field tap at 02:07) |
| Touch-dead windows ~01:36–01:49 / spinner never landing (F3 #2, F4) | mutual contention — both sessions were tapping the same UI; the underlying F4 deadness may still be real (17-8 precedent) but tonight's instances are contaminated in both directions |
| H02 Oct 6–7 "Sick leave" approved request (d818fc08) | Session A's 01:34 on-behalf apply (their log) — Session B's "accidental tap" theory was wrong; B only witnessed the completed form |

Net: the **SIGSTOP of PID 98316 stands as a real and useful find** (a genuinely stale 10:03 session with scrcpy),
and the two active sessions were contending with each other the whole night. Morning reading should treat
DB-audit rows as authoritative for who-wrote-what (actor ids + timestamps).

## Findings unique to this session

### B-BUG-1 — Reminder engine fires up to 30 s early (Low; BE SQL)

`attendance_run_reminders` computes `v_now_min = ((extract(epoch from (v_tick at time zone v_tz)) / 60)::int) % 1440`.
PG's `::int` **rounds** (554.98 → 555) instead of truncating, so any tick in `[threshold − 30 s, threshold)` already
satisfies every `v_now_min >= threshold` gate.

Live proof: `p_now = 09:14:59+05:30` (threshold 09:15:00 = Hero/Yuka start 09:00 + 15 m cutoff) fired **Arm 1
(Suresh check-in reminder) and Arm 3 (Yuka office summary) a minute early**; the isolated expression shows
09:14:30 already rounds up. Same skew applies to Arm 2 and the 10:00 pending-leave gate (fires from 09:59:30).
Cross-layer note: the TS engine's `minuteOfDayInTz` truncates — one clock, two semantics.
**Fix: floor/trunc the minute in the reminder SQL; dedupe keys make it safe.** Once-per-day-per-key, ≤30 s — Low,
but it contradicts FR-23's "at Start + Late cut-off" letter.

### B-OBS-1 — Correction sheet's check-in placeholder is value-indistinguishable (P3 UX)

The Times-arm check-in field renders a grey placeholder `09:00` (the office-rule start) that reads as a committed
value (committed values are near-black and carry the `Clear` affordance; pixel-darkness 349 vs 80). The form
correctly stays gated ("Pick a check-in time", Save disabled) while the tester believes a time is set — **both
sessions misread it independently tonight**. Gate itself correct; suggest a committed-state visual cue in the next
UX pass.

### B-POS — FR-9 is a server-enforced contract, not a dialog (verifying what 17-8's walkthrough couldn't)

17-8's walkthrough exercised the FR-9 dialog against a **pending** fixture. This session verified the
**approved-leave path** at the API: check-in on Arya's approved full-day Paternity today →
`409 ATTENDANCE_LEAVE_CONFIRMATION_REQUIRED` ("You have leave today. Confirm to cancel it and check in");
with `confirmLeaveCancel:true` → 201 + the full cascade in one transaction (day row `cancelled` for that date only,
`leave_events.checkin_auto_cancel` with actor = employee, owner notification `leave.checkin_auto_cancel`
`{employeeName, leaveDate}`). First-half leave + check-in deliberately does NOT auto-cancel (call site gates
`leavePart === 'full_day'` — spec D11). Recorded so the near-miss "bug" (first-half check-in keeps the leave)
is never re-filed. **Arya was fully restored afterwards** (record deleted; day row back to `approved` inside one
transaction with the guard trigger disabled → re-enabled, `tgenabled='O'` verified; event + notification removed).

## Corroborations of the main report (independent driver, same result)

- **F1/F2 auth pair** — B also logged in with an arbitrary wrong code (200 + JWT) and consumed the OTP echo as
  its login mechanism all night; agrees it is the known Epic-10 phase-1 placeholder and must die before launch.
  B adds: the send-side rate limit 429s exactly on the 6th rapid send; sessions are single-use (post-success
  codes answer `OTP_EXPIRED`); the lockout ladder is dead code while `isValid = true`.
- **F6 4h boundary** — B verified the same boundary through a different route (Yuka's 5.5 h threshold to the
  minute: 330 → half_day, 329 → absent; 0-minute punch → Short day; corrections arm exactly-240-min →
  `half_day`, daysWorked 0.5, DELETE recomputes). Both routes agree with the engine source.
- **F5 authz matrix** — B's independent matrix matches (403/401/200; plus cross-tenant employee read →
  404 no-existence-leak; day-statuses span 63 → 422 / 62 → ok / from>to → 422).
- **F9 gates** — B's API-level ladder matches the device results exactly (`ATTENDANCE_TOO_FAR` with exact
  metreage, `ATTENDANCE_MOCK_LOCATION`, `ATTENDANCE_LOW_ACCURACY`, `ATTENDANCE_NOT_CHECKED_IN`,
  `ATTENDANCE_ALREADY_CHECKED_IN`).
- **F10 carve** — B verified Suresh's today sheet independently: Half-day leave chip + Cancel request,
  no Convert (today rule), no Apply, with the AC 11 lazy-resolution skeleton first.
- **F11 parity** — B's October monthly read matched the engine grade-for-grade for H01–H06/Arya
  (late riders, override-absents, in_progress + rule-9 splits all counted correctly).
- **F3 latency** — B observed the same slow screen settles on device (multi-second shimmers) but did not time
  the API; Session A's 5.3–7.8 s write / 7.1 s read measurement is the number to act on.

## Additional passes unique to this session (all PASS)

- **Rule 3 vs rule 7 on a live day**: planted a Friday weekly-off override (from today) on Y06 — their sub-half
  punch re-graded `worked_on_holiday` (credit 0), moved Short day → Checked in, Late rider suppressed; removed
  afterwards. Short day stays impossible on an off day (D-2's note, live-verified).
- **Rule-1/instants-only partition arms** (20-2 AC 3): status-only `absent` override on a punch day (H02) and on a
  no-record day (H03) → Not checked in; instants-only override under threshold (H04, 210 min) → Short day. The
  20-2 detection predicate held on every arm. Overrides removed after; sums stayed exact throughout.
- **Reminder boundary probes via the injected clock** (the RPC takes `p_now`): 09:14:59 arms-fire (B-BUG-1);
  10:30 tick → only the pending reminder, arms deduped; full-day leave / adjudicated / weekly-off / times-only-
  override suppressions all held (Arya suppressed, Yuka summary counted only Suresh, H04 counted as checked-in).
- **Holiday lifecycle**: create 201 → duplicate 409 `ATTENDANCE_HOLIDAY_TAKEN` → **fan-out exactly 102
  notifications, all distinct dedupe keys** → leave-on-holiday 422 `LEAVE_ALREADY_OFF` → remove 204 → second
  remove 404. Fan-out + cleanup notifications deleted.
- **Leave write battery**: past-before-tracking-start `LEAVE_BEFORE_START_DATE` (anchored at enrolment start);
  overlap 409 `LEAVE_OVERLAP`; weekly-off/holiday `LEAVE_ALREADY_OFF`; inverted range `LEAVE_INVALID_RANGE`;
  apply over a punch `LEAVE_CHECKED_IN_CONFLICT` (on-behalf and past dates both); on-behalf approve-immediate
  ×3; revoke of a fully-past request 409 `LEAVE_NOT_REVOKABLE`; same-actor double-cancel → 200 own-retry with
  exactly ONE `employee_cancel` event; cancelled-request preview → empty `actionDates` shape.
- **Idempotency**: replay returns the same request id; same key + different body safely returns the original;
  missing key → 422.
- **Dashboard partition under adversarial mutation**: through every fixture move (90 → 86 → 87 short-day,
  overrides in/out, leave flips, both sessions' fixtures combined) `checkedIn + notCheckedIn + onLeave +
  shortDay == tracked` exactly on every fetch; device tiles matched the wire byte-for-byte; Home strip counted
  H01's 13-day pending request as ONE (AC 12 DISTINCT semantics); "3 Sites" / Yuka1 empty state / picker
  subtitles (tracked · checked-in only) all held.
- **20-1 wire prereq**: `leaveRequestId` populated exactly on pending/approved leave days, null elsewhere.

## Fixture ledger (Session B's additions; Session A's are in the main report)

Kept: boundary punch times on Y01/Y02/Y04/Y05/Y06/H02's Oct 2 records (330/329/0/20/20/180 min);
Suresh's approved full-day Oct 1 + approved first-half Oct 2 on-behalf fixtures + his 11-second check-in/out
record; H01's cancelled Oct 6 + cancelled Nov 2–3 probe requests (history rows).
Removed during the night (verified restored): the Oct 26 probe holiday + 204 fan-out notifications; the three
reminder notifications; Arya's FR-9 probe (see B-POS); H03/H04 overrides; Y06's weekly-off override;
H01's Nov 2–3 request cancelled.
Final combined tile state (both sessions' kept fixtures): 102 = 11 + 1 (H04) + 3 (Arya, Suresh, H03) + 87, sum exact.
Full-night revert recipe, if wanted: reset the six boundary records' times, cancel Suresh's `ff383829…` /
`5b7a797a…` and H02's `d818fc08…` requests, delete Suresh's Oct 2 record — plus Session A's recipe.

## Not probed by this session (left to A or a quiet device)

AC 6's past-leave-day sheet render on device (fixture exists: Suresh's approved Oct 1; read side + gates verified),
FR-9 dialog UX (BE contract verified here; dialog device-verified in 17-8), airplane-mode copy (A's F9 covers it),
check-in rate-limit live block (A's F9 measured it exactly).

---

## Addendum — fixes shipped the same morning (2026-10-02, ~09:15–10:00 IST)

The user approved fixing the confirmed bugs. **No commit/push yet — awaiting consent.** All work is in `fenzit-be` (uncommitted); the reminder migration is ALREADY MCP-applied to production (live-verified; the repo file catches up at commit time).

### Fixed

1. **F1 (P0)** — `auth.service.ts verifyOtp` now does the real `bcrypt.compare(otpCode, session.otpHash)`; the accept-any-code placeholder is gone and the attempts/lockout ladder is live (5 wrong codes → locked; the correct code then answers `401 OTP_SESSION_LOCKED`). Unit + HTTP-integration coverage added, including the full lockout sequence over HTTP.
2. **F2 (P0)** — `sendOtp` returns `otp` **only** when env `OTP_DEV_ECHO=true` (default OFF). `jest.env.setup.ts` sets it for the HTTP tests (the same contract the app's `__DEV__` chip consumes). Swagger + api-contracts.md updated in the same change; `.env.example` documents the flag with a do-not-ship warning.
3. **B-BUG-1 (Low)** — migration `20261002000001_attendance_run_reminders_minute_floor.sql` floors the three seconds-carrying instant→minute conversions (tick clock, late-minute, enable-grace). MCP-applied; live single-statement probes: `09:14:59` fires **0** (pre-fix: 2), `09:15:00` fires **1** — the boundary is exact.
4. **Review hardening (EC-1)** — a failed verify now holds the session's REMAINING ttl (`OtpSession.expiresAt`) instead of granting a fresh 300 s per wrong guess.

### Review-driven test repairs (the lenses caught what my green suite hid)

- The `test:e2e` path was **red with my fix**: `test/auth.integration.spec.ts` + `test/invite.e2e-spec.ts` still pinned the accept-any-code contract (3 failing) and one "protected route" test passed vacuously through `@Public` `/health`. All repaired: the OTP-leg tests read the echoed code like a dev client, the any-code pin is inverted to `401 INVALID_OTP`, the JWT test targets `/auth/realtime-token`, and a full HTTP lockout sequence was added. `auth.integration` 10/10, `invite.e2e` 10/10.
- The reminder journey spec gained the seconds-carrying boundary probe (`14:29:59` fires nothing, `14:30:00` fires the displaced arm) — credential-gated (IS_REAL_DB), and the ONLY automated test that distinguishes the fix from the old rounding cast.

### Withdrawn

- **F8 (the other session's P2)** — "rejected check-in hides the approved-leave chip" does **not** reproduce as a state bug. Device repro ×2 (H03, approved full-day leave today): the LEAVE-section row was present at every checkpoint (+2/+6/+15/+30 s), `today.leaveState` has **no rendering consumer in the FE at all** (exhaustive grep — the only reader is the dialog predicate), and the API/DB returned the row throughout. The sighting was the two-line too-far message pushing the row to the viewport's bottom edge plus a mid-relayout uiautomator dump — the same misread both sessions made. No FE change made; re-open only with a screenshot showing the chip genuinely gone (not below the fold). Recorded in deferred-work.md.

### Triage of the review lenses (BMAD quick: edge-case-hunter + verification-gap)

Patched: VG-1 (red e2e), VG-2 (boundary probe), VG-3 (`.env.example`), EC-1 (TTL hold), EC-3 (env restore in tests). Deferred (recorded in deferred-work.md): EC-2 (non-atomic attempt ladder under concurrent verifies — the honest fix is an atomic store primitive; low risk pre-launch). Dismissed: EC-4 (rule-time casts — exact-by-construction via validated writers, documented in the migration header).

### Verification state

`bun run build` clean; src suite 1424/1424; `auth.service.spec` 36/36; `auth.integration` 10/10; `invite.e2e` 10/10. The migration is live in production; the auth fix goes live on the next Render deploy (push).

### ⚠️ Deploy note for the owner (action required before/with the pull)

Once this deploys, `OTP_DEV_ECHO` is unset on Render → the send response stops echoing the code → **the phone's DEV OTP chip disappears and device logins need the code from the Render logs** (the mock provider still logs `OTP for +91xxx: NNNNNN`). To keep the chip until DLT lands: set `OTP_DEV_ECHO=true` in Render's environment BEFORE deploying — and unset it the day SMS goes live.
