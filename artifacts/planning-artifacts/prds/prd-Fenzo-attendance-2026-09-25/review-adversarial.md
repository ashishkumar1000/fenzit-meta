# Adversarial Review — Attendance & Leave PRD

- **Reviewed:** `prd.md`, `addendum.md`, `.memlog.md` (2026-09-25)
- **Reviewer stance:** hostile. The aim is to break the rules, not to praise them.

**Verdict: NOT READY for architecture/epics.** The happy paths are clear. The rules break when two things happen on the same date: a half-day leave plus a missing checkout, an owner correction plus a later holiday change, a pending leave plus a check-in, or an office timing edit plus today's check-in. Three findings would lead two engineers to build data models that do not work together. Fix the critical and high items before `bmad-create-architecture`.

**Counts:** Critical 3 · High 14 · Medium 20 · Low 9 · **Total 46**

---

## Critical

### C-1. Owner "set Day status directly" has no precedence against the computed engine
- **Where:** FR-21 ("set the Day status directly"), FR-10 consequence ("Adding or removing a Holiday, or making an Attendance correction, recomputes the affected dates immediately"), FR-10 "Every Tracked employee-date has exactly one Day status".
- **Scenario:** On the 14th the Owner corrects Priya from Checkout missing to **Present** (UJ-4). On the 20th the Owner adds a retroactive Holiday on the 14th. FR-10 step 2 now gives **Worked on holiday**, and the recompute runs "immediately". Does the manual Present survive? Engineer A stores the override as a pinned status, so it stays Present and Days worked keeps the +1. Engineer B stores only corrected times and recomputes, so it becomes Worked on holiday and Days worked loses 1. The same happens when the Owner sets a status to **Leave** or **Absent** directly, when there is no leave request behind it and the leave count and FR-17 history disagree.
- **Also undefined:** which of the 10 statuses are allowed as correction targets. Can the Owner set "Holiday"? "Not tracked"? "Leave" with no Leave request? "Half-day leave" with which half? Does a correction on times recompute the Late/Early flags?
- **Fix:** Decide one model. The recommended one: a correction may change only Check-in/Check-out times (the status is always derived) **or** set a pinned status override that sits at precedence 0 in FR-10 and survives all recomputes, with the allowed targets limited to {Present, Half day, Absent}. Leave must always come through a Leave request, never a status override. State whether corrected times recompute Late/Early.

### C-2. Holiday and Weekly-off changes over existing leave: behaviour depends on a storage choice the PRD never makes
- **Where:** FR-20 bullets 2 and 3, FR-18, FR-19, FR-12 bullet 1, addendum `leave_request_days`.
- **Scenario A (holiday removal):** Arjun has Approved leave Mon–Fri. The Owner adds a Holiday on Wed. FR-20 says the date is "removed from the leave count". Then the Owner removes the Holiday. FR-20 says Wed "does not turn into leave automatically". But if Engineer A kept the `leave_request_days` row for Wed and just excluded it at read time, Wed silently goes back to **Leave**. If Engineer B deleted the row, Wed becomes **Absent**, with no notification to Arjun (FR-22 has no "holiday removed" event), even though he was never expected at work.
- **Scenario B (weekly-off change):** Arjun has Approved leave Fri–Mon with Sat+Sun off, so the count is 2 days. From next week the Owner makes Saturday a working day. Is Saturday now Leave (the count becomes 3 without Arjun agreeing), or Absent, or a Working day he must attend? FR-18/19 say nothing. The opposite case, where a new Weekly off falls inside an approved range, has no "frees that day + notify" rule, unlike Holidays.
- **Scenario C:** A Holiday is added over a **Pending** leave date. FR-20 only covers Approved.
- **Fix:** Store the leave per date, frozen at approval, as `leave_request_days` with a per-day state (active / freed_by_holiday / freed_by_weekly_off / cancelled / revoked / auto_cancelled). Define one rule for every calendar change (holiday add or remove, weekly-off add or remove) × every leave state (Pending, Approved) × past or future, plus who is notified. Add "Holiday removed" and "Weekly off changed over your leave" events to FR-22.

### C-3. Removed or deleted technicians are not covered at all
- **Where:** Nowhere. Glossary "Employee", FR-5 ("can't be archived until they are reassigned"), NFR-6 ("never hard-deleted").
- **Scenario:** A tracked technician leaves the business and the Owner deletes or deactivates the user through the existing users flow. (1) If `attendance_records`/`leave_requests` FK to `users` with `ON DELETE CASCADE`, the history and audit trail disappear, which breaks NFR-6. (2) If FKs are `RESTRICT`, the Owner can't delete the user at all. (3) Their enrolment still points at the Andheri Office, so Andheri can never be archived (FR-5). (4) Their Pending leave sits in the Owner's queue forever (FR-13 says Pending never expires). (5) Reminders keep firing for a user who can't log in. (6) The monthly grid either hides them, so the month's totals change after the fact, or shows a ghost row.
- **Fix:** Add an FR: removing or deactivating a technician ends the enrolment on that date, which releases the office assignment. Pending leave is auto-closed with a system reason. Future Approved leave days are dropped. History is kept, and FKs use `RESTRICT` or soft-delete. Past months still show the person, marked "Removed".

---

## High

### H-1. Half-day leave (precedence step 5) swallows Checkout missing, Absent and the dashboard flag
- **Where:** FR-10 steps 5, 6, 7; memlog line 15 ("No check-out by midnight = Checkout missing, counted as half day, flagged on owner dashboard until corrected"); FR-21 last bullet.
- **Scenario:** Priya has Second-half leave. She checks in at 10:00 and forgets to check out (checkout reminders are suppressed on Second-half leave days by FR-23, so this is likely). Step 5 fires before step 7, so the status is **Half-day leave** and the worked half is evaluated with no Worked hours. Is that 0 or 0.5? The memlog says Checkout missing = half day, and the PRD is silent. The Owner-dashboard "Checkout missing" flag never appears, because the status is not Checkout missing, and that silently drops the memlog decision.
- **Fix:** Make the half-day-leave result a composite: `Half-day leave + {worked half: Present-half / Absent-half / Checkout missing}`. Define the Checkout-missing half as 0.25 or 0.5 (pick one). Always raise the dashboard flag when a Check-in has no Check-out.

### H-2. "Half the Hours rules" is ambiguous, and there is no rule for when the second half starts
- **Where:** FR-10 step 5 ("half the Hours rules: worked ≥ Full-day hours ÷ 2 → 0.5"), memlog line 23 ("hours rule halved"), FR-7 (no Late on First-half leave), FR-8 (no Early on Second-half leave), FR-23.
- **Scenario 1:** Full 8 h / Half 4 h. Priya is on First-half leave and works 3 h. Engineer A uses only Full÷2 = 4 h, so she gets 0. Engineer B halves both thresholds (4 h → 0.5, 2 h → 0.25), so she gets 0.25. "Half the Hours rules" (plural) invites B, while the formula says A.
- **Scenario 2:** On First-half leave, when is she late? There is no Late flag at all, so checking in at 17:30 and leaving at 21:30 (4 h) earns 0.5 worked with no flag. Nothing defines the half-day boundary (the midpoint of Start/End?). There is no check-in reminder, so she is never nudged.
- **Scenario 3:** On Second-half leave she checks in at 10:00 and out at 11:00. No Early flag, worked 1 h, so she gets 0. Is the missing half **Absent 0.5**? The FR-25 "Absent" column counts days, so it can't show 0.5.
- **Fix:** Define `half-day boundary = Start + (End − Start)/2`. First-half leave means Late is measured against the boundary + cut-off and the check-in reminder fires at boundary + cut-off. Second-half leave means Early is measured against the boundary. Give one explicit threshold table for half-day-leave days, and say whether Absent can be 0.5.

### H-3. Totals don't reconcile, and the UJ-4 example is arithmetically impossible
- **Where:** UJ-4, FR-11, FR-25, Glossary "Days worked".
- **Scenario:** UJ-4 has Weekly offs 8 (Sat+Sun), so the month is Sept 2026 (30 days) or similar. 21.5 worked + 2 leave + 8 WO + 1 holiday + 1 worked-on-holiday + 0 absent = **33.5 > 30**. Working days = 30 − 8 − 1 = 21, yet Days worked + Leave = 23.5. The 0.5 in 21.5 implies a Half day or a half-day leave, but then where is the other 0.5? Absent is 0. With no invariant, each engineer counts Half days, Checkout missing and half-day leave in different columns (is Checkout missing inside "Half days" or not? FR-25 lists both).
- **Fix:** State an invariant and test it: `Σ per-date weights = number of tracked dates`, where each date splits into {worked, leave, absent, weekly off, holiday} weights that sum to 1. Worked on holiday is a count on top of its WO/Holiday weight. Fix the UJ-4 numbers so they satisfy it. Say whether Checkout missing is also counted in "Half days".

### H-4. Checking out is penalised: a Checkout missing day earns more than an honest short day
- **Where:** Glossary "Days worked", FR-10 steps 6 and 7.
- **Scenario:** Employee A checks in at 10:00, checks out at 13:00 (3 h, below Half 4 h), and gets **Absent = 0**. Employee B checks in at 10:00, walks away and never checks out, and gets **Checkout missing = 0.5**. The rules reward not checking out. Owners who never correct flags will pay for it. SM-4 (checkout completeness) will look fine while the data is gamed.
- **Fix:** Either count Checkout missing as 0 until corrected (still flagged), or keep 0.5 but add a rule that repeated Checkout missing triggers an Owner notification. At least record the risk in §6/§10. This was a memlog decision, but the PRD should state the known abuse path.

### H-5. Changing Office time or Hours rules today: "from the date of the change" includes today, and nothing says what that means
- **Where:** FR-5 ("Changes to timing and Hours rules apply from the date of the change. Past Day statuses are not recomputed").
- **Scenario:** Start is 10:00, Priya checks in at 10:30 (Late 30). At 11:00 the Owner changes Start to 11:00. Today is not "past", so is Priya still Late? The Late flag was stored at check-in (FR-7 "stored with the Check-in"), but NFR-2 says flags are computed on the server, which could mean at read time. Other effects: the checkout reminder (End + 30) was scheduled against the old times, the owner summary for today at 10:15 already fired, and the "revoke/cancel today before Start time" cut-off (FR-14) moves after the Employee already missed it. Changing Full-day hours at 17:00 from 8 to 9 changes today's status for everyone.
- **Fix:** Rule: timing or Hours-rules edits take effect **from tomorrow** (or from a date the Owner picks ≥ tomorrow). Today always uses a snapshot of the rules as they were at 00:00. Store `rules_version_id` on each attendance record.

### H-6. Pending leave + Check-in on the same date: approval creates an illegal state
- **Where:** FR-9 (auto-cancel only for *Approved*), FR-12 ("A past date where the Employee has a Check-in can't be requested"), FR-13 (approve), FR-10 step 4 ("no Check-in").
- **Scenario:** Arjun applies for leave Mon–Wed (Pending). On Tue he comes in and checks in. Nothing happens, because FR-9 covers only Approved. On Thu Rakesh approves. The request now contains Tue, a date with a Check-in, which FR-12 forbids at submission. Is Tue Leave or Present? Is the Working-day count 3 or 2? Same with **today**: FR-12 blocks leave only on a *past* date with a Check-in, so Arjun can check in at 10:00 and then apply for a full-day leave for today at 15:00.
- **Fix:** At approval, drop any date that has a Check-in (auto-cancelled, with a note to the Owner), or block approval with an error. Make the Check-in block in FR-12/FR-16 apply to "today or past". Apply FR-9 auto-cancel to Pending dates too.

### H-7. Pending leave with past dates can never be withdrawn by the Employee
- **Where:** FR-15 ("Pending → Cancelled entirely, if no date has passed"), FR-13 ("never auto-expires").
- **Scenario:** Arjun back-dates leave for last Mon–Tue (allowed by FR-12), then realises it was a mistake. FR-15 lets him cancel Pending only "if no date has passed", and every date has passed. The Owner ignores it. It stays Pending forever, the days stay Absent with a "Leave pending" marker, and the Owner gets a daily pending reminder forever (FR-23). The case of a Pending request whose range is partly in the past (Mon–Fri, today is Wed) is also undefined: can he cancel the whole thing, only Thu–Fri, or nothing?
- **Fix:** A Pending request can always be withdrawn by the Employee in full (nothing was granted). The split rule applies only to Approved requests.

### H-8. "Split" vs "partial Revoked" are two different data models
- **Where:** Glossary "Leave request… Revoked (can be partial)", FR-14 ("the request is split"), FR-15 ("split"), UJ-3 "Revoked (Thu–Fri)", FR-17.
- **Scenario:** After a Wed revoke of Mon–Fri, Engineer A creates two requests: Mon–Wed Approved and Thu–Fri Revoked. Engineer B keeps one request with state Revoked (partial) and per-day states. FR-17 then shows either two rows or one row with a mixed state. The Working-day count, FR-11 leave totals, notification deep links (FR-22 "opens the related leave") and the "overlap with Pending or Approved" check (FR-12) all behave differently. For example, can Arjun now apply again for Thu under B? Is the Thu row "Revoked" and so not blocking?
- **Fix:** Pick one. The recommended choice: one request with per-day state. The request-level state is derived (Approved / Partially revoked / Partially cancelled / Revoked / Cancelled). Overlap checks use only active day rows.

### H-9. Enabling mid-day makes today tracked, and the employee is Absent by midnight
- **Where:** FR-2 ("Enabling sets an effective date (today)"), UJ-1 Resolution ("live … from today"), FR-10 step 8.
- **Scenario:** Rakesh finishes the wizard at 16:30. The 5 employees have not installed the update or seen the onboarding. They never checked in today, so at midnight they are all **Absent** for day 1. The monthly summary shows 1 Absent each through no fault of theirs. Enabling at 23:50 is even worse.
- **Fix:** Effective date = tomorrow by default (the Owner may pick today). Or: the enable date is tracked, but a date with no Check-in on the enable date is Not tracked.

### H-10. Disabling mid-day and disabling with open leave are undefined
- **Where:** FR-2 ("Dates after disabling show as Not tracked"), FR-3.
- **Scenario:** Priya checks in at 10:00, and the Owner disables her at 12:00. Is today tracked? Can she still check out? If not, is today Checkout missing? Her Approved leave next week and her Pending leave: do they stay in the Owner's queue, get notified or cancelled? What happens if she is re-enabled the same day (two enrolment periods covering one date, and NFR-4 "one Office per date")? Reminders already scheduled for today?
- **Fix:** Disable takes effect from tomorrow. Today stays tracked and check-out stays allowed. Future leave days are dropped with a system reason and the Employee is notified. Pending requests are closed. Only one enable/disable change per employee per day.

### H-11. The checkout reminder breaks for "not late" and "very late"
- **Where:** FR-23 row 2 ("End time + actual minutes late"), memlog line 31, Glossary "Late".
- **Scenario 1:** Start 10:00, cut-off 15. Priya checks in at 10:12. She is not Late (inside grace), but she is "actually" 12 minutes late. Is the reminder at 18:00 or 18:12? The memlog says "actual minutes late", while the Late flag only exists after the cut-off.
- **Scenario 2:** She checks in at 16:30 (390 min late), so the reminder falls at 00:30 the *next day*. That is after the midnight Checkout-missing finalisation, so it either never fires or fires for a closed day.
- **Scenario 3:** She checks in on a Weekly off or Holiday. FR-23 says no reminders on WO/Holiday, so she never gets a checkout reminder and Checkout missing is almost certain.
- **Fix:** `reminder_at = End + max(0, check_in − Start)`, capped at 23:30 (or before the finalisation). Say explicitly whether Worked-on-holiday days get a checkout reminder (they should: at check-in + Full-day hours).

### H-12. Tenant timezone is editable? No one says
- **Where:** NFR-5, Glossary "Tenant timezone", addendum A11.
- **Scenario:** If an Owner (or support) changes the timezone from Asia/Kolkata to Asia/Dubai, then records stored in UTC with the date derived at read time move to different dates. A 23:30 IST check-out becomes the next day. Past Checkout missing and Present statuses change without anyone touching them. NFR-5 promises "no schema change later", but DST zones have 23 h and 25 h days and nonexistent local times (for example Start 02:30 on the spring-forward day).
- **Fix:** Store `local_date` on every attendance and leave-day row at write time (it never changes). Make the timezone owner-read-only in v1 (support-only change, forward-only). Add a DST rule note or say DST zones are out of scope.

### H-13. No tenant-level "turn off the module", yet NFR-12 relies on one
- **Where:** NFR-12 ("Turning it off (or never enabling it) leaves the field flow exactly as it is"), FR-1/FR-2 (only per-employee disable), memlog line 6.
- **Scenario:** The Owner wants to stop using Attendance. The only way is to disable every employee. The entry point stays, the pending-leave reminder keeps firing, and archiving the last Office leaves a module that is "enabled" with zero Offices. Glossary: "A tenant has one or more Offices".
- **Fix:** Add FR: the Owner can switch the module off (all enrolments end tomorrow, reminders stop, history stays read-only, re-enable goes back into the wizard or settings). Block archiving the last Office while the module is on, or define the zero-Office state.

### H-14. The 3rd fake-GPS notification is fired by a *failed* operation, which contradicts FR-22's atomicity rule
- **Where:** FR-7 bullets 4–5, FR-22 consequence ("no Notification is sent for a change that failed"), NFR-3.
- **Scenario:** A mocked check-in is rejected, so the RPC raises an error and rolls back. The attempt row and the 3rd-attempt Notification roll back with it. Nothing is recorded, and the threshold is never reached. If the engineer instead commits then errors, it breaks FR-22 as written. Also undefined: do idempotent replays of the same rejected request count as 1 or N attempts? Do check-*out* attempts count? Is the "calendar month" in tenant timezone? Can the Owner clear or dismiss the flag?
- **Fix:** Model a rejected mock attempt as a successful write of an `attendance_rejections` row that returns a business error code (no exception rollback). State that FR-22's rule covers state changes, not rejection logging. Count by distinct idempotency key. Count both check-in and check-out. Use the tenant-timezone month.

---

## Medium

### M-1. Late minutes: measured from Start or from Start + cut-off? And the second boundary
- **Where:** Glossary "Late" ("records the minutes late"), FR-7, UJ-2.
- **Scenario:** 10:22 check-in with a 15-min grace. UJ-2 says "Late by 22", but an engineer reading the glossary might store 7. Is 10:15:30 late? "After Start + cut-off" is measured to the second or to the minute?
- **Fix:** Glossary: "minutes late = floor((check_in − Start) / 60 s); Late flag when check_in ≥ Start + cut-off + 1 min" (or whatever is chosen). Same for Early checkout.

### M-2. Worked on holiday: hours rules, Checkout missing and Early flag are undefined
- **Where:** FR-10 step 2, FR-11, FR-7 (no Late on WO/Holiday).
- **Scenario:** Check-in on a Holiday, no check-out, so the status is Worked on holiday with "Worked hours" = undefined. The Checkout-missing flag never shows. Is 20 minutes of work on a Sunday one "Worked on holiday"? Does the Early checkout flag apply?
- **Fix:** Worked on holiday requires a Check-out, otherwise it is "Worked on holiday + Checkout missing" (flag). State a minimum (≥ Half-day hours?) or explicitly "any Check-in counts". No Early flag.

### M-3. Today's status after Check-in and before midnight is missing from the precedence list
- **Where:** FR-10 steps 7 and 9.
- **Scenario:** 14:00, Priya is checked in and not checked out. Step 6 needs a Check-out, step 7 needs midnight, step 9 covers only "before any Check-in". The self view and dashboard show... nothing defined.
- **Fix:** Add a step: "Today, checked in, not checked out → 'Checked in' (not final)". Also add the non-final labels to the glossary ("Not checked in yet", "Checked in", "Leave pending").

### M-4. Reminder dedupe key contradicts the per-Office owner summary
- **Where:** FR-23 row 3 ("once per Office per day") vs consequence ("at most once per recipient per day per type"), addendum A4 key (recipient, type, date).
- **Scenario:** Rakesh has Andheri and Thane, both 10:00 + 15. The first summary takes the (Rakesh, summary, date) key, and Thane's summary is dropped as a "duplicate".
- **Fix:** Key = (recipient, type, local_date, office_id nullable).

### M-5. Pending-leave dates vs reminders, dashboard "on leave" and owner summary
- **Where:** FR-23 row 1 ("no full-day leave"), FR-24 ("on leave"), FR-10 step 8.
- **Scenario:** Arjun has a Pending leave for today. Does he get "You haven't checked in"? Is he in the Owner's "3 employees haven't checked in" count? Is he in the dashboard's "on leave" count? One engineer reads "leave" as any leave, another as Approved only.
- **Fix:** Say "Approved" everywhere a leave suppresses something. Show Pending as its own dashboard bucket ("Leave pending").

### M-6. Revoke or cancel of today: whose Start time, and what about half-day?
- **Where:** FR-14 bullets 1–2, memlog line 44.
- **Scenario:** Arjun has Second-half leave today. The Owner revokes at 12:00, after Start (10:00) but before the half-day boundary. It is blocked, even though the leave half has clearly not started. After an Office reassignment today, which Office's Start applies? If Start was edited today (H-5), which value? Also, UJ-3's edge case says cancelling on Wednesday frees only Thu–Fri. That holds only if it is after 10:00. Before 10:00, Wed is cancellable too, so the UJ is wrong without a time.
- **Fix:** Cut-off = start of the leave half (Start for full or First-half, the half-day boundary for Second-half), using the Office assigned on that date and today's rules snapshot. Add a clock time to UJ-3.

### M-7. Can the Employee cancel leave the Owner imposed on their behalf?
- **Where:** FR-15, FR-16.
- **Scenario:** The Owner applies on-behalf leave for Priya next Monday (maybe as a disciplinary day off). FR-15 lets the Employee cancel "a Pending or Approved Leave request", so Priya cancels it. Is that intended?
- **Fix:** State it. Recommended: on-behalf leave can be cancelled only by the Owner (revoke).

### M-8. Mistaken past Approved leave can never be undone
- **Where:** FR-14 (future only), FR-16 (on-behalf, back-dated 7 days, "revocable"), memlog line 21.
- **Scenario:** The Owner applies on-behalf leave for last Tuesday for the wrong employee. Revoke is future-only, and correction (FR-21) changes attendance, not leave. The wrong leave is permanent, and "revocable" in FR-16 is empty for back-dated leave.
- **Fix:** Allow the Owner to revoke past Approved leave days within the same 7-day window (reason required, audit), or allow a correction to void a leave day.

### M-9. Two half-day leaves on one date
- **Where:** FR-12 overlap rule, half-day rules.
- **Scenario:** Priya applies First-half for Tue, then Second-half for Tue. Do they "overlap"? If allowed, the status is what, "Half-day leave" twice = Leave? If rejected, she must cancel and re-apply as a full day.
- **Fix:** Reject with the message "Apply a full day instead", or merge. State it.

### M-10. "7 days back" has no inclusive/exclusive definition
- **Where:** FR-12, FR-16, memlog line 20.
- **Scenario:** Today is the 25th. Is the 18th allowed? Engineer A allows today−7 inclusive, Engineer B allows only the 19th onwards. Is the limit evaluated at submission or at approval? (Pending never expires, so approval can happen 30 days later.)
- **Fix:** "earliest allowed date = today − 7 (inclusive), checked at submission only".

### M-11. Leave on Not tracked dates (before enablement or after disable)
- **Where:** FR-12, FR-2.
- **Scenario:** Priya was enabled 2 days ago and applies back-dated leave for 5 days ago (inside the 7-day window). Those dates are Not tracked. Is it accepted? FR-10 step 1 wins, so it is shown as Not tracked while the leave list shows Approved days. The totals disagree.
- **Fix:** Leave dates must lie inside a tracked period. Also say what a future leave beyond a known disable date does.

### M-12. Accuracy threshold (100 m) is larger than the minimum Radius (50 m)
- **Where:** FR-5 (Radius 50–1000), FR-7 (accuracy ≤ 100 m).
- **Scenario:** Radius 50 m, reported accuracy 95 m, computed distance 40 m. It passes, but the true position may be 135 m away. The Owner set 50 m for strictness and gets 145 m.
- **Fix:** Either minimum Radius ≥ 100 m, or rule `distance ≤ Radius` and `accuracy ≤ max(Radius, 30 m)`. Or accept the gap and document it in §7.2.

### M-13. Fake-GPS flag is client-reported, but NFR-2 claims server authority
- **Where:** FR-7 ("The app sends the mock flag to the server, and the server makes the decision"), NFR-2.
- **Scenario:** A modified APK or a direct API call sends `mocked: false` or omits it. The server "decides" on a value the client controls.
- **Fix:** Treat a missing `mocked` from Android as a rejection. State in §7.2 that it is a deterrent, not a guarantee, like iOS.

### M-14. Office reassignment: "effective-dated" in memlog, but "from the date it's made" in PRD
- **Where:** FR-6, memlog line 28 ("office assignment changes effective-dated").
- **Scenario:** The Owner wants Priya to move to Thane from the 1st of next month. The PRD allows only "now" (today or tomorrow depending on check-in). This drops scheduling. Also, if reassigned before check-in today but after the check-in reminder, the reminder named the wrong Office.
- **Fix:** Allow a picked effective date ≥ today (≥ tomorrow if checked in). Align with the memlog wording.

### M-15. Weekly-off effective date in the past?
- **Where:** FR-18 ("from a date the Owner picks (default today). Dates before it are unchanged"), FR-10 last bullet, memlog line 24 ("history unchanged").
- **Scenario:** The Owner picks last Monday as the effective date. Is that allowed? If yes, the past recomputes, which breaks "history unchanged". If no, the PRD never says the date must be ≥ today. Choosing today after people checked in turns their Present into Worked on holiday mid-day. There is no way to edit or delete a scheduled future change.
- **Fix:** Effective date ≥ tomorrow (or ≥ today only if no one has checked in). Scheduled changes can be edited or deleted until they take effect.

### M-16. Retroactive Holiday add or remove silently rewrites Days worked for past months
- **Where:** FR-20 bullet 1, FR-10 consequence.
- **Scenario:** In October the Owner adds a Holiday for 2 Sept. Everyone who worked it changes from Present (counted in Days worked) to Worked on holiday (not counted), so September Days worked drop by 1 for them after the Owner has already used the numbers. Removing a past Holiday turns everyone who stayed home into **Absent**. No one is warned or notified (the FR-20 warning covers only leave ranges).
- **Fix:** Show an impact preview before saving a past-dated holiday change ("12 employee-days will change: 5 Present → Worked on holiday, 7 Holiday → Absent"). Limit it to the same 7-day window, or require confirmation.

### M-17. Previously-tracked Employee's history: PRD says viewable, addendum hides the entry point
- **Where:** FR-3 bullet 2 [ASSUMPTION] vs FR-3 main line ("sees it only while they are a Tracked employee") vs addendum B2 ("4th tab… shown only when enrolled", `/users/me.attendanceEnrolled`).
- **Scenario:** Priya is disabled. The tab is hidden (addendum, FR-3 main line), yet she "can still view past records" (FR-3 bullet). There is no path to get there.
- **Fix:** Tab shown when `enrolled OR has_history`, in read-only mode. Expose `attendanceHistory: boolean` in `/users/me`.

### M-18. Correction vs a live check-out on today's date
- **Where:** FR-21 ("any past or current date"), FR-8 ("Check out once").
- **Scenario:** At 17:00 the Owner corrects Priya's check-out to 18:00 (manual), because she said she would leave early. At 18:30 she taps Check out. Rejected because the pair already exists? Or does it overwrite the manual value? Or does the Owner's correction lose to the concurrent real event? NFR-3 covers concurrency on leave only, not attendance corrections vs check-in/out.
- **Fix:** Corrections only on past dates, or on today only after check-out. Add attendance-record row locking to NFR-3.

### M-19. Idempotency covers only check-in/out and leave submit
- **Where:** NFR-3, addendum A9.
- **Scenario:** The Owner taps "Apply on behalf" on flaky 4G. The retry hits the overlap rule and returns an error even though the first call succeeded, so the Owner thinks it failed. The same happens with approve (second call gets "only Pending can be approved"), revoke, cancel and correction (duplicate audit rows).
- **Fix:** Put an idempotency key on every mutating attendance/leave endpoint. A replay returns the original result.

### M-20. Memlog says "day Present" for check-in on leave; PRD silently weakens it
- **Where:** memlog line 22 ("allowed, day Present, leave auto-cancelled"), FR-9 ("Day status comes from attendance as normal").
- **Scenario:** Arjun checks in on his leave day at 16:00 and leaves at 17:00. By the memlog he is Present. By the PRD he is Absent (1 h), and he lost his leave too, which is worse than staying home. The auto-cancel into a "Cancelled" state also isn't a valid Employee/Owner transition (NFR-4 state machine), and the Employee gets no notification that their leave was cancelled (FR-22: Owner only).
- **Fix:** Confirm with the user which one. Probably keep "as normal", but add an "Auto-cancelled" day state, notify the Employee too, and consider restoring the leave if the Owner later removes the check-in by correction.

---

## Low

### L-1. Glossary discipline: synonyms and undefined terms
- "Employee" / "Tracked employee" / "technician" / "employee" (lowercase) / "office staff" are mixed. FR-27 and NFR-12 say "technician". FR-7 says "employee, time, coordinates". FR-3 says "untracked Employee", which is not defined. FR-12 says "A Tracked employee can apply", but FR-17 says "the Employee sees".
- "Half day" (status) vs "half day" (leave duration) vs "Half-day leave" (status) vs "Half days" (summary column) are four meanings of one word.
- "Worked on holiday" also covers Weekly offs. A better name would be "Worked on off day".
- Undefined labels used as if they were statuses: "Not checked in yet", "Leave pending" marker, "Fake location attempt" flag, "manual", "Corrected by owner", "First-half leave day".
- "future dates" (glossary Revoke) vs "dates that have not started" vs "after today" vs "today before Start time" all describe the same cut-off differently. The glossary Revoke entry contradicts FR-14.
- **Fix:** One term per concept. Add the missing labels to §3. Rename the status to "Half day (worked)" or similar.

### L-2. Numbering and structure
- FR-27 sits between FR-23 and FR-24. There is no FR-25/26 collision, but the order is confusing. NFR-12 comes before NFR-11. The FR-22 table is titled "Leave event notifications" but has Holiday and fake-GPS rows.
- **Fix:** Renumber in reading order, or add a note. Rename the FR-22 heading.

### L-3. FRs with no testable consequences
- FR-17, FR-24 and FR-26 (beyond privacy) have no checkable rules. For example, does the FR-24 "on leave" count include half-day and Pending? FR-4 "short intro", NFR-8 "never freezes" and NFR-9 "beyond what's needed for debugging" can't be tested.
- **Fix:** Add concrete acceptance bullets (counts, filters, what is included, empty states).

### L-4. Worked hours rounding
- 7 h 59 m 59 s vs Full-day 8 h. Seconds or minutes? UJ-2 shows minutes.
- **Fix:** "Worked hours = floor to whole minutes; threshold comparison is on minutes."

### L-5. Check-in window has no lower bound, and check-out has no upper bound before midnight
- A check-in at 06:00 counts, and worked hours are inflated with nothing flagged. Is overtime silently counted? A check-out at 00:05 for yesterday is rejected ("no check-in today"). State that.
- **Fix:** Optional earliest check-in (for example Start − 2 h), or an explicit "any time from 00:00". State the post-midnight behaviour.

### L-6. Reminder precision vs a 5-minute cron
- FR-23 says "reminder at 18:40", but addendum A4 runs every 5 minutes. A test that expects the exact minute fails.
- **Fix:** "within 5 minutes after the target time".

### L-7. Check-in reminder fires at the exact moment the Employee becomes Late
- FR-23 row 1 = Start + cut-off = the Late threshold, so the reminder can never help avoid Late. It was a memlog decision, but it is worth a product check (for example Start − 10 min instead).

### L-8. Leave range has no maximum length or future horizon
- Leave for the next 400 days is accepted. Holidays for next year are not set yet, so the count shown at submission becomes stale. Is the "Working-day count" in FR-17 live or frozen at submission? Leaves spanning month ends: the monthly summary counts per date, but FR-17 shows one total. State both.
- **Fix:** Maximum range (for example 60 days), maximum horizon (for example 12 months). The count is live, and it is split per month in the monthly view.

### L-9. Holiday "edit" and multiple owners
- Is editing a Holiday's date a remove + add (with notifications and leave freeing)? Can a tenant have more than one Owner? FR-2 says "an Owner of the same tenant" while the glossary says "Owns one tenant". This matters for concurrent Owner actions and for who gets Owner notifications.
- **Fix:** Edit date = remove + add with the same side effects. State the single- or multi-owner assumption.

---

## Memlog cross-check summary

| Memlog decision | PRD status |
|---|---|
| L15 Checkout missing = half day, flagged until corrected | **Dropped on half-day-leave days** (H-1) and Worked-on-holiday days (M-2) |
| L22 Check-in on leave, "day Present" | **Weakened** to "status as normal" (M-20) |
| L23 "hours rule halved" | **Narrowed** to Full÷2 only; ambiguous (H-2) |
| L28 office assignment changes effective-dated | **Narrowed** to "from the date it's made" (M-14) |
| L31 checkout reminder at end + actual minutes late | Kept, but breaks on grace-period and late-night cases (H-11) |
| L21 on-behalf leave revocable | Not true for back-dated on-behalf leave (M-8) |
| L6 attendance optional / owner-enabled | No tenant-level off switch defined (H-13) |
| L24 weekly offs effective-dated, history unchanged | A past effective date is not forbidden (M-15) |
| L44 today cut-off at Start time | Kept; half-day and reassignment cases missing (M-6) |
| All others | Consistent |
