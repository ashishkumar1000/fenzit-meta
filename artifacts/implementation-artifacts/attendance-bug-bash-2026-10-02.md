# Attendance bug bash — night of 2026-10-02 (LIVE, in progress)

Manual functional + security pass over shipped attendance surfaces (Epics 14–20), Pixel 6 (serial 1C301FDF6002ZB),
dev build com.fenzitapp 1.0.0 (lastUpdateTime 00:29), production API https://api.fenzit.com + production DB
(Supabase pnlvreaijzslfymlnoti). Tester: ZCode agent, DB-first verification per standing rule.
Scope: find + document only — **no code fixes applied tonight**.

**STATUS: COMPLETE (03:15 IST) — device restored to the owner (Ayush) login; no code fixes applied; nothing committed.**

---

## ⚠️ Environment incident (read first)

A **second, stale agent session was still driving the same device + DB** during the first ~50 min of this bash:

- Host had `claude --model glm-5.3-flash:cloud` (PID 98316, started 10:03 the previous morning) and a
  **scrcpy mirror of the Pixel 6 attached since 23:21** (killed by me at 02:10).
- Its fingerprints: 4 correction writes as **Ayush** at 01:52–01:54 IST with notes
  `Bugbash: flip to present` / `Bugbash: past leave day correction probe` (+2 removals) on H02/Arya; random
  input injections into my foreground app ~02:05–02:09 (a clock picker opened by itself); explains the
  "touch-dead" taps, the phantom "Add technician" sheet, and back-key no-ops earlier in the night.
- **Action taken (least-destructive):** `kill -STOP 98316` (SIGSTOP — reversible with `kill -CONT 98316`);
  scrcpy killed. Nothing deleted. **Owner should review that session in the morning** (it may hold uncommitted
  work) and decide `CONT` vs kill.
- Consequence for evidence quality: **device-side timings/tap-behaviour before 02:10 are contaminated**.
  DB-side evidence with request/response captures is clean. Items marked [re-test] below.

## Findings

### F1 — P0 · `verifyOtp` accepts ANY 6-digit code (production, live-verified)
- The deferred W1 item ("verifyOtp accepted ANY 6-digit code — Epic 10 to close") is **still open in production**.
- Evidence (02:04 IST): `POST /api/v1/auth/otp/verify {"otpSessionId":"ab160a96-…","otpCode":"000000"}`
  → **HTTP 200** with a valid JWT (`role: technician`, tenant 792b28ed, sub a66e3d57… = Loadtest H07/H08 batch).
- Consequence: anyone can log in as any enrolled phone number without the SIM. All role-gating (403s — see
  F5 passes) is moot because any role's token is mintable.
- Suggested fix placement: **BE** (auth service verify step — bind the code to the session, constant-time
  compare, attempt counter). Epic 10's OTP hardening should absorb this; do not wait for DLT.
- [re-test after fix]: wrong code ×5 → lockout/429; expired reuse → 401 (replay now correctly 401s: `OTP_EXPIRED`,
  "OTP session not found or expired" ✓).

### F2 — P0 · `send-otp` response echoes the OTP in production (full owner takeover proven)
- Evidence (02:06 IST): `POST /api/v1/auth/otp/send {"countryCode":"+91","phoneNumber":"1234567890"}` →
  `{"otp_session_id":"…","expires_at":"…","otp":"106842"}` — then verify with the echoed code →
  **HTTP 200, `role: owner`, user "Ayush"**. Complete tenant takeover without the SIM.
- The FE dev chip expects this field (`__DEV__` banner fed by response OTP) — the BE must **strip `otp` when
  not in a dev context** (or gate on a debug header/build flag). Fix placement: **BE**.
- F1 + F2 together = production auth is currently bypassable twice over. Recommend an emergency BE patch
  before any external testing/launch activity.

### F3 — P1 · Correction save UX: multi-minute spinner on device [re-test in clean conditions]
- First UI save (checkout 09:00→13:00 on H02 today) spun ~3 min and then showed a **correct** inline server
  error (`checkinAt cannot be in the future` — it was 01:56 IST; the punch instants are later "today"). The
  validation itself is correct behaviour.
- Second UI save (H02 Oct 1) spun 2+ min and never landed (no DB row); contaminated by the parallel session's
  injections at 02:05–02:09 (a picker got opened over the spinner).
- Clean API re-measure (owner token): PUT correction = **5.3–7.8 s** per call (4 probes, uniform; also affects
  reads: monthly read 7.1 s). So BE is uniformly slow (~5–8 s), not minutes — the FE experience of minutes
  needs a clean re-test. Even 5–8 s per write is worth a Render/DB look before scale-out.
- Positive: server error copy surfaces inline in the sheet, Save re-enables, no data written on rejection ✓.

### F4 — P2 · Recurring touch-dead state on the device [re-test]
- Multiple taps (back key, month arrow, list rows, "Correct day") silently ignored ~01:36–01:49; recovered
  only by force-stop + relaunch (the documented 17-8 remedy). **Contaminated by the parallel session** — but
  it matches 17-8 §6's prior independent occurrence, so likely a real intermittent defect (JS-thread stall?).
- Recommend: re-test on a quiet device; if it reproduces, capture `adb shell dumpsys input` + React Native
  JS thread state at the moment of deadness.

### F5 — PASS · Authorization matrix (API, live)
- Technician token (Loadtest H08) → owner surfaces all **403**: `GET attendance/dashboard`, `GET
  attendance/monthly`, `GET attendance/corrections`, `POST leave/:id/approve`, `PUT corrections/:emp/:date` ✓
- Unauthenticated → **401** on dashboard + me/summary ✓
- Technician self-scopes → 200: `attendance/me/summary`, `attendance/me/access`, `users/me` ✓
- OTP session replay after consume → **401 OTP_EXPIRED** ✓
- (But see F1/F2 — gates only matter once tokens can't be minted.)

### F6 — PASS · Device walkthrough findings (owner side, uncontaminated steps)
- Leave pending queue correct: H01 16–28 Oct shows **"11 working days"** = 13 raw − 2 Sundays ✓ (weekly off
  = Sunday for Hero wala since the kept 20-2 mock).
- Leave detail sheet: Type/Dates/Working days/Status/Reason + Approve/Reject; reason quotes are deliberate FE
  styling (`“${reason}”` in LeaveDetailSheet.tsx:187) — dismissed as bug.
- **On-behalf apply (owner): submit = "Approve"** — request created approved in one step; FE landed back on
  All tab, top card "Loadtest H02 · 6–7 Oct 2026 · 2 working days · Approved"; DB row d818fc08
  (full_day, 2 approved days) ✓. Known copy debt applies ("working-days count appears once submitted" — shown
  on this form; 17-5's employee form has the live preview instead).
- Dashboard tiles partition invariant holds live: **12 checked-in + 3 not-checked-in + 86 short day + 1 on
  leave = 102 tracked** (10 open + 2 closed-≥4h present; H03+H04+Suresh punchless; Arya leave). "3 Sites" =
  3 active offices (Kadu off archived) ✓.
- Stale-cache note: on app resume the dashboard showed the previous session's numbers (10/90/1/1) until the
  Live Sync refresh — self-corrects in seconds; fine.
- Monthly: default month = **September 2026** (previous month) — check 19-5 spec intent; Next-month arrow
  correctly **disabled at October** (current month); Previous works. Month-pane cells: Sundays = weekly-off
  moon, approved leave days = blue leave icon, future = grey outline, today selected ✓. Sub-half-day punch
  days show the same red ⊗ as plain absent (Short day is a dashboard carve only, by design) — note as UX nit.
- Day detail (H02 Oct 2): Absent chip + Early·**240m** flag — verified against the rule (Hero wala 09:00–16:00
  ⇒ 12:00 checkout = 240 min early) ✓; punch pair + "3 h 00 m" + office shown; engine grade absent (3h < 4h
  floor) with the tile carving it to Short day ✓ (matches scale-test "1-minute day grades ABSENT" ruling).
- **Correction engine (API, timed):** valid times correction 200 (H03 Oct 1 09:00–13:00 → **half_day,
  daysWorked 0.5** — exactly-4h boundary grades half day ✓); XOR mix → 422 "Provide exactly one of status or
  check-in/check-out times" ✓; future date → 422 ATTENDANCE_FUTURE_DATE ✓; 501-char note → 422 ✓.
- Correction stage UX: opens on Status tab for punchless days, Times tab otherwise; XOR tabs; note gate
  (0/500 counter, required); Save disabled until valid ✓.

### F7 — Data-quality / fixture caveats (not bugs)
- Kept 20-2 fixture uses **future-dated instants for "today"** (punches up to 12:23 IST while real time was
  ~02:00) — blocks any correction touching those instants until real time passes them; dashboard reads fine.
- **Two distinct user rows named "Suresh"** (ids 80fa928d…, a644027a…) — one is likely a stray/legacy row
  (cf. the 17-6 stray tenantless owner incident; the keyboard suggestion list also showed `1234576890`,
  close to that stray). Worth an owner-side cleanup pass.
- `enrolments` = 109 rows vs 102 tracked today (upcoming/history-only rows) — expected by design.

### F12 — PASS · 20-1 write battery end-to-end on device
- **Convert to full day** (Loadtest H04, approved first-half 8 Oct): My month → day sheet → Convert CTA
  (after the AC-11 resolving shimmer) → confirm stage copy exactly per AC 4 ("Your half-day request for
  Thursday, 8 October will be cancelled, and a new full-day request will be sent. Your owner needs to
  approve it again. Your reason stays the same." + Now "Half day · Approved" → After "Full day · Waiting
  for approval") → "Cancel and send new request" fired the write: DB shows original 4a191110
  **cancelled** + NEW acc6e6e6 **full_day, same date, reason verbatim, pending** ✓. Post-write sheet:
  chips flip to "Not checked in yet" + "Leave pending", Convert CTA gone (pending never converts — AC 5 ✓),
  Cancel request remains ✓. Owner notified (fresh-apply path).
- **Owner month-detail day sheet correctly has NO leave CTAs** — initially looked like a wiring gap, but the
  20-1 spec scopes Cancel/Convert to the **me-scope** sheet (AC 2 "me-scope day", line 103/AC 13: "an owner
  sheet passing none of the new props renders byte-identically") — **dismissed by design**.
- Non-leave future day (Oct 15) shows "Apply leave" ✓; leave days hide it ✓ (AC 1).

### F13 — PASS · Parked probe closed: 18-4 offline-save (airplane-mode correction Save)
- Owner, correction stage on a past day, note typed, **airplane mode ON, Save** → inline blocking
  **"You're offline. Correcting attendance needs a working connection."**, no write (0 override rows), no
  silent queue, sheet stays on the stage for retry. This was the Epic-18 deferred device probe — now
  verified live. (FE handleSave's `isOfflineNow()` gate + OFFLINE_SAVE_MESSAGE.)

### F14 — PASS · Dashboard flags strip + FlagListSheet + flag drill-down
- Seeded one unacknowledged `mocked` attempt (Loadtest H04, today) → owner dashboard rendered the strip:
  **"Fake location attempt · CRITICAL · GPS spoofing blocked on 2 days. [2]"** (2 = H04 + a Suresh-row
  attempt from the kept parallel-session fixture); API read matches (`flags.fakeLocationAttempt` exactly).
- Strip → sheet lists per-employee rows ("Loadtest H04 · Hero wala · 1 attempt", "Suresh · Yuka · 1
  attempt"); row tap drills into the employee's month pane ✓.
- UX nit: short swipes over the tile grid often don't scroll the dashboard (the strip is below the fold);
  a long drag from the bottom works. Touch-competitiveness worth a look some day. Not a blocker.
- Partition invariant re-verified with flags present: 11 + 1 + 87 + 3 = 102 ✓.

### F15 — Data quality: the stray-row family is visible in the roster (owner cleanup recommended)
- Technicians roster shows **"Arya · 1234576890 · Active"** — the 17-6 mistyped-login stray (owner-like
  number, real-looking name). Combined with the **two distinct "Suresh" rows** (80fa928d… @Yuka, a644027a…
 — the second carries the mocked attempt seen in F14) there are at least 3 duplicate/stray employee rows.
  They pollute tiles/rosters and (see F1/F2) each is a login target. Recommend an owner-side dedupe pass.
- Also observed live twice tonight: `adb input text` fast-typing drops digits on the login phone field
  (caught '1243567890' before submitting; the 17-6 incident class is reproducible) — per-digit typing is
  the workaround; maybe FE should surface the parsed number more loudly before Send.

### Fixture additions tonight (all dummy-tagged; removal recipe)
```sql
-- this session's additions (everything below is dummy-tagged / probe data)
-- 1. H02 approved leave 6-7 Oct (on-behalf via app)
delete from leave_request_days where leave_request_id in (select id from leave_requests where employee_id in (select id from users where name like 'Loadtest H02') and reason = 'Sick leave' and start_date = '2026-10-06');
delete from leave_events where leave_request_id in (select id from leave_requests where employee_id in (select id from users where name like 'Loadtest H02') and reason = 'Sick leave' and start_date = '2026-10-06');
delete from leave_requests where employee_id in (select id from users where name like 'Loadtest H02') and reason = 'Sick leave' and start_date = '2026-10-06';
-- 2. H03 timed-probe correction (Oct 1, 09:00-13:00)
delete from attendance_corrections where employee_id = (select id from users where name = 'Loadtest H03') and note like 'Bugbash timed probe%';
delete from attendance_day_overrides where employee_id = (select id from users where name = 'Loadtest H03') and work_date = '2026-10-01';
-- 3. H03 FR-9 probe leave (2 Oct, approved, still approved — the too-far rejection correctly never cancelled it)
delete from leave_request_days where leave_request_id = '9ebb944e-769e-414e-9309-637bdf07ec1a';
delete from leave_events where leave_request_id = '9ebb944e-769e-414e-9309-637bdf07ec1a';
delete from leave_requests where id = '9ebb944e-769e-414e-9309-637bdf07ec1a';
-- 4. H04 convert-fixture pair (cancelled half 4a191110 + pending full acc6e6e6)
delete from leave_request_days where leave_request_id in ('4a191110-3fb9-4c71-8d77-36f6c8061f51','acc6e6e6-c52a-46b8-881c-a2213f81552e');
delete from leave_events where leave_request_id in ('4a191110-3fb9-4c71-8d77-36f6c8061f51','acc6e6e6-c52a-46b8-881c-a2213f81552e');
delete from leave_requests where id in ('4a191110-3fb9-4c71-8d77-36f6c8061f51','acc6e6e6-c52a-46b8-881c-a2213f81552e');
-- 5. seeded fake-location attempt (H04, today) — keep if you want the strip demo; else:
delete from attendance_attempts where id = 'd89acea7-6bb7-467a-8037-28a3f5999a63';
-- 6. H03 rate-limit attempt rows (6 too_far + 1 rate_limited tonight) — audit trail; delete only if wanted:
-- delete from attendance_attempts where employee_id = (select id from users where name='Loadtest H03') and attempted_at > '2026-10-01 20:50:00+00' and outcome in ('too_far','rate_limited');
```
(The 01:52–01:54 rows from the frozen parallel session were **left in place** — they carry its probe history;
the doc above lists them for the owner to review.)

### F8 — P2 · Rejected check-in on a leave day hides the approved-leave chip for minutes (self-heals)
- Device, employee Loadtest H03 (approved full-day leave today planted via on-behalf): FR-9 dialog fired
  exactly per spec; **"Don't check in"** wrote nothing (leave approved, 0 events, 0 attempts) ✓.
- **Confirm arm:** the confirm cancelled nothing server-side — the check-in attempt was rejected `too_far`
  (1356 m vs 150 m radius; attempt row logged ✓) and the server correctly did NOT cancel the leave
  (cancel is atomic with a successful check-in). **But the FE removed the "Approved" leave chip from the
  Today screen anyway** — and the wrong state persisted across a tab away/back remount (several minutes),
  while the DB kept `state='approved'`, 1 event (apply), 0 `checkin_auto_cancel` notifications.
- Self-heal observed: a later navigation (notification deep-link) restored the chip. The check-in pre-flight
  kept consulting live truth — the FR-9 dialog re-fired on every subsequent tap (wire-driven fallback ✓).
- Net effect: employee is told (implicitly) their leave is gone when it isn't — misleading for minutes.
  Fix placement: **FE** (don't drop the leave chip on the rejected path; only reflect server-confirmed cancel).

### F9 — PASS · Check-in gate ladder (device, live GPS)
- Too-far gate: exact server copy **"You are 1356 m from Hero wala. Move within 150 m."** ✓ (attempt rows:
  outcome `too_far`, distance 1356.13 m).
- Rate limit: 5 counted rejections in 10 min → `blocked_until = +10 min exactly` (21:03:13 → 21:13:13 UTC) ✓;
  a further tap logged outcome `rate_limited` harmlessly ✓; UI: button disabled + live ticking countdown
  **"Try again in 8:57"** (matches server award to the second) + red "Too many attempts. Try again in 10 min" ✓;
  countdown kept ticking correctly across screenshots (8:57 → 7:19) ✓.
- Offline gate: airplane mode → **"You're offline. Check-in needs a working connection."**; tap inert, no
  crash, no attempt row ✓ (this also covers the offline posture on top of an active rate-limit block).

### F10 — PASS · FR-9 pre-flight dialog (both arms) + leave-day carve
- Full copy verified: "You're on leave today. Checking in will cancel today's leave. Continue?" +
  "Your owner will be notified. Only today's leave is cancelled — your other leave days are not affected."
  Buttons: "Check in" / "Don't check in" ✓. Re-fires on every attempt while leave is live server-side ✓
  (dialog is server-truth-driven, not a one-shot latch).
- Employee day sheet on a leave day (Suresh, Half-day leave today): shows Half-day leave chip + Office +
  **"Cancel request"** and **no "Apply leave"** — the 20-1 carve ✓ (preview stage not confirmed — real
  employee's real leave, not cancelled tonight).

### F11 — PASS · Employee self-view (19-6) + FR-11 parity + notifications (14-x)
- My month (H03): Oct 1 = **Half day** (my 4h-exact correction — boundary grading visible to the employee ✓),
  Oct 2 = Leave ✓, Sundays = weekly-off moon (Oct 4 Holi+Sunday shows weekly_off per the both-rule ✓),
  "Days worked: 0.5 so far" with Worked 0.5 / 1 half day / 1 leave — **matches the owner monthly API for the
  same employee** (FR-11 one-aggregation parity) ✓. Forward month bound disabled ✓.
- Suresh self view: summary "1.5 leave" == owner monthly "leave: 1.5" ✓; day sheet on leave day per F10.
- Notifications (H03): "Leave applied for you · 2 Oct 2026 · 1 working day · 16m ago" from the on-behalf
  apply ✓; check-in reminder present, deduped (one card despite 5-min cron all day) ✓.
- Nits (not bugs): greeting renders only the first name token ("Good morning, Loadtest" for "Loadtest H03");
  "Active (0)" vs two unread-dot cards (Active/Completed taxonomy vs read-state — confirm intended);
  "Leave applied for you" deep link lands on the Attendance tab (closest technician leave surface — confirm
  registry intent; owner-side cards should still be checked against their targets).

---

## Test log (chronological, condensed)

| Time (IST) | Step | Result |
|---|---|---|
| 01:20 | Device + DB snapshot; fixture intact (100 dummy punch rows "today", 100 dummies, 16 leave requests) | ✓ |
| 01:21 | Launch app → resumed straight into owner dashboard; partition 5+0+45+1=51 @ Hero wala | ✓ |
| 01:24 | Dashboard doesn't scroll — confirmed content fits (no flags: none exist today); not a bug | ✓ |
| 01:26 | Home → "Leave requests to review" strip present with pending count | ✓ |
| 01:27 | Leave queue: 1 pending (H01 16–28 Oct · 11 working days) — matches DB | ✓ |
| 01:29 | Detail sheet facts + Approve/Reject render | ✓ |
| 01:34 | On-behalf apply H02 6–7 Oct full day "Sick leave" → created **approved** (DB d818fc08) | ✓ |
| 01:41 | Monthly (owner): September default; › bound at October ✓; rows + chips render | ✓ |
| 01:44 | H02 month pane: weekly-off/leave/future chips correct; day sheet: Absent + Early·240m (verified vs rule) | ✓ |
| 01:47–01:49 | Touch-dead state begins; force-stop + relaunch recovers | F4 |
| 01:52–01:54 | (parallel session's 4 correction writes as Ayush — NOT this session) | incident |
| 01:54 | Correction stage: XOR tabs, note gate, Save gating | ✓ |
| 01:56–01:59 | UI save #1 (future-instant) → server inline error after ~3 min spinner | F3 |
| 02:04–02:09 | UI save #2 spins; parallel-session injections contaminate | F3/F4 |
| 02:10 | Frozen stale session (SIGSTOP 98316), scrcpy killed | incident |
| 02:04–02:06 | API: wrong-OTP login 200 (F1); OTP echo + owner takeover (F2) | F1/F2 |
| 02:08–02:11 | API: authz matrix 403/401/200 as expected; replay 401 | F5 |
| 02:12 | API: correction probes 200/422×3 (timed 5.3–7.8 s); 4h-exact → half_day 0.5 | F6 |
| 02:20 | Suresh smoke: FR-4 intro, My month "1.5 leave" == owner read (parity), leave-day sheet carve | F10/F11 |
| 02:23–02:31 | H03 leg: FR-9 dialog both arms; "Don't check in" writes nothing; confirm → too_far 1356 m | F8/F9/F10 |
| 02:31 | 5th rejection → blocked_until +10:00 exactly; extra tap = rate_limited; UI countdown 8:57 ticking | F9 |
| 02:36 | Airplane mode → offline gate copy; tap inert | F9 |
| 02:37 | H03 My month: Oct 1 half-day (my 4h correction), Oct 2 leave chip (contrast w/ F8), parity ✓ | F11 |
| 02:38 | Notifications: "Leave applied for you" card + deduped reminder; deep-link lands on Attendance tab | F11 |
| 02:42 | Leave-apply: FE picker disables >7-day-past dates; API: LEAVE_BEFORE_START_DATE, LEAVE_OVERLAP 409 | F6 |
| 02:50–02:53 | Flags strip "CRITICAL · 2" + FlagListSheet rows + employee drill-down; partition 102 holds | F14 |
| 02:56 | 18-4 parked probe: offline Save blocked inline, 0 rows written | F13 |
| 03:05–03:09 | Convert to full day end-to-end (H04): confirm copy, DB cancel+re-file verbatim reason, post-write "Leave pending" | F12 |

## Morning checklist for the owner
1. **Decide on the frozen session** (`kill -CONT 98316` to resume, or kill it) — it may hold uncommitted work.
2. **Fix the two P0 auth holes (F1/F2) in the BE** — one-line-class changes, no DLT dependency.
3. Review the stray/duplicate employee rows (F15) — "Arya 1234576890", two "Suresh" rows.
4. Triage F3 (BE latency 5–8 s/call) and F8 (leave-chip optimistic hide) for the fix queue.
5. Run the removal recipe above if/when done with tonight's fixtures.
