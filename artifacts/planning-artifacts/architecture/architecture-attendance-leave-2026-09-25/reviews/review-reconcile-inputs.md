---
review: reconcile-inputs
target: ARCHITECTURE-SPINE.md (Attendance & Leave, draft 2026-09-25)
sources:
  - prds/prd-Fenzo-attendance-2026-09-25/prd.md
  - prds/prd-Fenzo-attendance-2026-09-25/addendum.md
  - ux-designs/ux-Fenzo-2026-09-25-attendance-leave/EXPERIENCE.md
date: 2026-09-25
altitude: feature (only items that let two epics/stories diverge, or that break an NFR)
---

# Reconcile review — sources vs Architecture Spine

## Verdict

The spine is strong on the big structural calls (DB-centric core, one RPC per write, advisory locks, effective-dated ranges, compute-on-read day status). But it misses about eight quiet rules that need a home at spine level, and three of its decisions contradict a source without saying that they replace it. None of this needs a redesign. It needs additions and explicit "supersedes" notes before the epics are cut.

Counts: 2 critical-adjacent (high) contradictions, 7 high gaps, 9 medium, 8 low.

---

## 1. Contradictions (spine vs source)

### C-1 [HIGH] AD-18 polling fallback vs FR-27 "real time", plus a scope conflict inside the PRD
- **Source:** FR-27 says the technician "receives their attendance/leave Notifications and Reminders in real time". FR-22 says "The app shows new Notifications live while it is open". NFR-1 says the job-RPC gap "must be reviewed before FR-27 gives technicians a realtime token". PRD §7.2 lists "Fixing the existing job functions' database access gap" as **out of scope**.
- **Spine:** AD-18 gates the technician token on two `deferred-work.md` fixes, and says "Until then, the technician inbox works through list/unread polling on foreground". The release order places the fixes at step 2, but nothing makes them a required deliverable of this initiative.
- **Problem:** Polling on foreground does not meet FR-27 or FR-22 "live while open". The PRD also contradicts itself: the fix is out of scope, yet it is a hard gate for an in-scope FR. Without a decision, the inbox epic and the security-fix work can ship in any order, and FR-27 quietly degrades.
- **Fix:** Make AD-18 say: "The two deferred fixes (revoke EXECUTE on the existing job RPCs; column-limit `users_update_own`) are a **blocking in-initiative story** that must merge before fenzo-app attendance ships. Foreground polling is a dev-time interim only and is not an acceptable shipped state for FR-27." Raise the §7.2 conflict with the PM so the out-of-scope line is narrowed to "general hardening of job RPCs beyond the two gate items". If the PM would rather ship with polling, record that as a signed-off FR-27 deviation in the spine.

### C-2 [MEDIUM] AD-6 drops `IdempotencyInterceptor`; the addendum says reuse it
- **Source:** Addendum A9 and B1 ("`IdempotencyInterceptor` on check-in/out and leave writes, key required"), and §C1 Idempotency ("make the key required on these routes, and store a `request_id`…").
- **Spine:** AD-6 says "`IdempotencyInterceptor` is **not** applied to attendance routes."
- **Assessment:** The spine's choice is better. The addendum itself lists the interceptor's flaws: racy lookup-then-run, result stored after response, key not scoped to user. But the spine does not say it replaces the addendum, so a dev reading the addendum will add the interceptor anyway.
- **Fix:** Add to AD-6: "Supersedes addendum A9/B1/§C1 'reuse IdempotencyInterceptor'. Reason: two layers can disagree, and the interceptor is racy and not user-scoped. Required-key enforcement is done by a route-level guard/DTO check, not by the interceptor." Also say which component returns the 422 for a missing key (a small attendance guard or pipe), so the check-in story and the leave story do not each build their own.

### C-3 [LOW] AD-15 replaces the addendum's rate-limit suggestion
- **Source:** Addendum §C1 says "reuse the Places rate-limit pattern (config-driven budgets)".
- **Spine:** AD-15 says it is counted in SQL from `attendance_attempts`, and "The Places in-memory rate limiter is not reused". The thresholds are SQL constants that change by migration.
- **Assessment:** The spine's choice is justified (the state survives restarts, and it agrees with the audit rows). The only issue is that the replacement is not called out.
- **Fix:** Add "Supersedes addendum §C1 Rate limit" plus a one-line reason. State that "config-driven" becomes "migration-driven SQL constant" on purpose. See G-3 for the real semantic bug in AD-15.

### C-4 [HIGH] AD-9 snapshots Late/Early flags, but FR-7 and FR-10 need them re-judged when leave or holiday context changes
- **Source:** FR-7 says "There's no Late flag on a Weekly off or Holiday". FR-10 consequence: "Adding or removing a Holiday … updates the affected dates immediately, including past dates". FR-7 and FR-8 say that on a First-half or Second-half leave day, Expected start or Expected end moves to the Midpoint. FR-12 and FR-16 allow past-date leave (up to 7 days back) and on-behalf leave.
- **Spine:** AD-9 stores `expected_start`, `expected_end`, `late_minutes` and `early_checkout` at write time. AD-10 "uses the snapshot for dates that have a record".
- **Problem:** Three cases break:
  1. The Owner adds a past Holiday on a day the employee checked in late. The frozen `late_minutes` keeps a Late flag on a Holiday, which FR-7 forbids.
  2. A second-half leave for today is approved after check-in. The frozen `expected_end` is the End time, not the Midpoint, so Early checkout is wrong.
  3. A holiday is removed again. Now the flag should come back.
  
  The dashboard/monthly epic and the check-in epic will disagree about who owns the flags.
- **Fix:** Change AD-9 so it snapshots the **rules** (office_id, office_rules_id, Start/End/cut-off/hours values, distance, radius, fix metadata), not the **judgements**. Late minutes and Early checkout are then derived in `attendance_day_statuses()` from the snapshotted rules plus the leave/holiday/weekly-off context on that date at read time. The check-in response can still return the "Late by 22 min" computed at write time, using the same SQL helper.

---

## 2. Gaps — source requirements that did not land in the spine

### G-1 [HIGH] "Enabled after today's Start time → today is Not tracked unless they check in" (FR-2) has no data model
- **Source:** FR-2 bullet 5. FR-10 rule 2 ("including the enable-day rule in FR-2"). EXPERIENCE "Enrolment rows" says it is handled entirely server-side, and "today renders as Not tracked everywhere (Dashboard tiles, calendar)".
- **Spine:** AD-8 stores enrolment as a `daterange`. A date range cannot tell "enabled at 09:00" from "enabled at 15:00". AD-10 and AD-14 do not mention the rule.
- **Risk:** The day-status engine, the reminders job (a "haven't checked in" reminder could fire on the enable day) and the dashboard's Not-checked-in tile will each invent their own handling.
- **Fix:** Add to AD-8: `attendance_enrolments.enabled_at timestamptz NOT NULL` (server `now()`). Add to AD-10 and AD-14: "If `lower(valid) = work_date` and `enabled_at` (in tenant local time) is later than that date's Expected start, the date is Not tracked unless a check-in or correction exists, and no reminder or not-checked-in count applies." Decide it once, in a shared SQL helper (for example `attendance_is_tracked(emp, date)`), which both AD-10 and AD-14 call. Also say whether this applies to the wizard-completion enrolments (UJ-1). It should.

### G-2 [HIGH] Replayed or rejected attempts are not idempotent, so the rate limit and the 3rd-fake-attempt alert double-count
- **Source:** FR-7 ("Repeated taps are safe: the same request replayed does not create duplicates"). NFR-3.
- **Spine:** AD-6 stores `request_id` only "on the row it creates" (`attendance_records`). AD-4 inserts an `attendance_attempts` row for every rejection. Nothing dedupes attempts by key.
- **Risk:** One network retry of a mocked request becomes two `mocked` attempts. That pushes the employee towards the 5-in-10-min block and can fire the Owner's "3rd fake-location attempt" alert early. This breaks FR-7's alert semantics and NFR-3.
- **Fix:** Add to AD-6: `attendance_attempts.request_id` with `UNIQUE (tenant_id, request_id)`. A replayed key returns the originally committed outcome (ok or rejected) with no new attempt row. Add a client rule to AD-20/AD-21: "one idempotency key per user tap (per fresh fix); reuse it only for a transport retry of the same payload".

### G-3 [HIGH] AD-15's sliding-window count does not give FR-7's "wait 10 minutes", and which outcomes count is undefined
- **Source:** FR-7: "after 5 rejected attempts within 10 minutes, the Employee must wait 10 minutes". FR-7 also says "Every rejected attempt (distance, accuracy or fake location) is still recorded". EXPERIENCE shows a live countdown "Try again in 9:42".
- **Spine:** AD-15 says "counts rejected attempts in the last 10 minutes … At 5 or more it returns `rate_limited` with the remaining seconds of a 10-minute block."
- **Problems:**
  1. A sliding count lifts the block once the oldest of the 5 leaves the window. Five rejections spread over 9 minutes then block for only about 1 minute.
  2. It does not say whether `rate_limited`, `stale_fix`, `already_checked_in`, `not_checked_in` or `not_tracked` outcomes are "rejected attempts". If `rate_limited` counts, mashing the button extends the block forever.
  3. It does not say whether check-in and check-out share one budget.
- **Fix:** Rewrite AD-15:
  - The block starts at the 5th counted rejection and ends 10 minutes later (`blocked_until = 5th_rejection_at + 10 min`, derived from the attempts or stored).
  - Only `too_far`, `low_accuracy`, `mocked` and `stale_fix` count.
  - `rate_limited` attempts are logged (for NFR-9) but never count.
  - One shared budget covers check-in and check-out.
  - `retryAfterSeconds = blocked_until - now()`.
  - Only `mocked` outcomes count toward the FR-7 3rd-attempt alert, and a replayed key never counts (see G-2).

### G-4 [HIGH] No server-side "preview" reads, so the frontend will compute rules itself (breaks AD-2 and NFR-2)
- **Source:** EXPERIENCE says the leave form's "working-day count recalculates live as dates change, before submission". The Revoke sheet "shows exactly which dates will be revoked versus which stay Approved", using the Start-time cut-off. The Cancel dialog shows the same split. The Holiday add/remove warning names the affected employees. The Office archive block shows "{n} employees are still assigned here". Reassignment pre-fills tomorrow "if already checked in today". FR-12 says "The app shows the number of Working days in the range".
- **Spine:** AD-2 says working-day counts, cut-offs and so on live only in SQL, and fenzo-app computes no rule. But the spine defines no read function or route that returns these before a write. The only read function is `attendance_day_statuses`.
- **Risk:** The leave-UI story will compute working days on the device from weekly offs and holidays, and the revoke story will compute the split on the device. Both will drift from the RPC and break AD-2 in the story most likely to be built first.
- **Fix:** Add an AD (or extend AD-2): "Every UI preview of a rule outcome comes from a server dry-run read function that shares the same SQL helpers as the write RPC." Name them at spine level: `leave_preview(p_tenant, p_employee, p_from, p_to, p_part)` returns the dates, the working-day count and the FR-12 rejection codes. `leave_action_preview(p_request, p_action ∈ {revoke, cancel})` returns the dates-affected and dates-kept groups. `attendance_holiday_impact(p_tenant, p_date)` returns the affected employees with approved leave. The archive-blocker count and the "checked in today" check for reassignment can be part of the existing office and enrolment reads. Add the routes under Conventions → Routes (for example `leave/preview`).

### G-5 [HIGH] Office archive rule (FR-5, FR-28) is missing
- **Source:** FR-5: "An Office with Tracked employees assigned can't be archived until they are reassigned. Removed employees don't block archiving." FR-28 last bullet. EXPERIENCE "Office archive" pattern.
- **Spine:** There is no archive state on `attendance_offices` and no archive RPC. AD-3 lists "office name" as a plain single-row write, and a dev could treat archive the same way.
- **Risk:** Archive racing a reassignment or a future-dated enrolment. An archived office left assignable. Check-ins judged against an archived office.
- **Fix:** Add an `archived_at` column to `attendance_offices`. Add an `attendance_office_archive` RPC under the tenant lock (AD-5). It blocks when any enrolment for the office overlaps `[today, infinity)`, **including future-dated (upcoming) enrolments**. A closed enrolment (disable, or removal later) does not block. Archived offices are rejected by the enrolment and reassignment RPCs, and are excluded from new-office pickers. History keeps its FK (`ON DELETE RESTRICT` already stated).

### G-6 [HIGH] FR-9 auto-cancel needs a server-side confirmation, not only the app dialog
- **Source:** FR-9: "the Check-in is allowed **after the Employee confirms**". EXPERIENCE pre-flight uses "today's already-known Day status", which can be stale (for example, the Owner applies leave on behalf, or approves leave, after the screen loaded).
- **Spine:** The sequence diagram does the "leave-day auto-cancel" unconditionally inside `attendance_check_in`.
- **Risk:** Stale client state means leave is silently cancelled without consent. This is also a server-authority gap: the server makes a destructive side effect based on a dialog it never saw.
- **Fix:** Add `p_confirm_leave_cancel boolean` to the check-in RPC (and `confirmLeaveCancel` to the body). If a full-day pending or approved leave exists for today and the flag is false, return a new committed outcome `leave_confirm_required`. It is not a rejection, so it does not count toward the rate limit, and it gets its own 409/422 `ErrorCode`. The app then shows the FR-9 dialog and retries with a new key. The holiday "Check in anyway?" dialog can stay UX-only, because it has no side effect.

### G-7 [HIGH] Setup-wizard state vs live rows: what exists before completion, and who is visible
- **Source:** FR-1: progress is saved after each step, and resumes on any device. "Until the wizard is completed, no Employee sees any attendance UI." "Can't be finished without ≥1 Office and ≥1 Tracked employee." EXPERIENCE: a failed step save shows an inline retry and does not advance.
- **Spine:** It has `attendance_setup_progress`, `attendance_complete_setup` and `attendanceEnabled` ("tenant setup complete"). But it does not say whether wizard steps write **real** offices, rules, weekly offs, holidays and enrolments (through the normal RPCs), or drafts inside the progress row. It does not say that `attendance_access()` returns `none` for every technician, and that pg_cron skips the tenant, until completion.
- **Risk:** The wizard epic and the offices/enrolment epics build two write paths. Or enrolments written at step 5 make technicians see the tab before the Owner presses "Enable". Or the step-4 holiday "notify all tracked employees" fires during the wizard.
- **Fix:** Add to AD-17 (or a new AD):
  - Wizard steps write real rows through the same RPCs as Settings.
  - `attendance_setup_progress` stores only the step pointer.
  - `attendance_complete_setup` (under the tenant lock) re-validates ≥1 non-archived office and ≥1 enrolment with an office, then sets `attendance_settings.enabled_at`.
  - `attendance_access()`, `attendance_day_statuses()`, reminders and all employee-facing notifications treat a tenant with `enabled_at IS NULL` as fully off.
  - Enrolments created during the wizard start from the completion date. G-1 applies.

### G-8 [MEDIUM] Canonical notification event catalogue is not fixed
- **Source:** The FR-22 event table (10 events), the FR-23 reminder table (4 reminders), the NFR-10 wave assignment per event, and FR-22's rule "tapping opens the related leave or day".
- **Spine:** AD-13 says "each is registered once … in `src/attendance/notification-events.ts`, mirrored by the fenzo-app registry", but lists no event names, recipients, entity types or deep-link targets. Only two examples are given.
- **Risk:** This is a cross-repo contract. The backend emitters (spread over leave, holiday, check-in and reminder stories) and the app registry (the inbox story) are built by different epics, and the names will drift (`leave.cancelled` vs `leave.cancelled_by_employee`).
- **Fix:** Add a table to the spine (or a companion `notification-events` contract) with, for each of the 14 events: `eventType`, recipient rule, emitting RPC or job, `entity_type`/`entity_id`, deep-link target, wave, and `dedupe_key` pattern where one applies. Include the fake-location alert key `fake_location:<emp>:<YYYY-MM>` and the fan-out rule for "new future Holiday → all Tracked employees": active on that holiday date, or active today? Decide which.

### G-9 [MEDIUM] FR-28 auto-cancel with no notification vs the AD-13 "no state change without its notification" invariant
- **Source:** FR-28: "Pending leave and future Approved leave are cancelled automatically. No Notification goes to the removed technician." FR-22 says every state change carries its notification.
- **Spine:** Deferred says "FR-28 rules are enforced through enrolment closing (AD-8) when it is built". AD-13 has no exception. AD-11 `leave_events` has an `actor` but no system actor.
- **Risk:** A later "remove technician" story either emits notifications to a removed user (FR-28 violation) or quietly breaks AD-13. Leave cancelled by the system has no valid `actor_id`.
- **Fix:** Add now (cheap):
  - An FR-28 exception line in AD-13.
  - `leave_events.actor_kind ∈ {employee, owner, system}`, with `actor_id` nullable only for `system`, and a reason code (`auto_cancel_checkin`, `auto_cancel_removed`).
  - Name the future hook (`attendance_offboard_employee`) that closes the enrolment, cancels leave and suppresses notifications to the removed user.
  
  The same `system` actor covers the FR-9 auto-cancel.

### G-10 [MEDIUM] Disabling an employee (FR-2) with open or future leave and a future office move is undefined
- **Source:** FR-2: "Disabling keeps all history, now read-only. Dates after disabling show as Not tracked." It says nothing about pending or future-approved leave, future reassignment ranges, or future weekly-off overrides. FR-28 defines this only for removal.
- **Spine:** Silent.
- **Risk:** The Pending queue shows requests for untracked dates. The FR-23 pending-leave reminder counts them. A later re-enable brings back stale approved leave.
- **Fix:** Decide at spine level (and confirm with the PM): the disable RPC closes the enrolment and any future office/override ranges, and cancels pending and future leave dates after the disable date as `system` (the FR-28 behaviour, but with the Owner as actor and the employee notified), or leaves them in place. Record the choice so the enrolment and leave epics agree.

### G-11 [MEDIUM] "Fake location attempt" and "Checkout missing" flags "until handled" have no lifecycle
- **Source:** FR-24: "flags from past days **until handled**: Checkout missing and Fake location attempt". FR-7: "The Owner sees a 'Fake location attempt' flag on that Employee's day in the dashboard and monthly view". EXPERIENCE: the flags strip navigates to a filtered list of employee-dates.
- **Spine:** AD-10 returns "flags" but does not say it includes attempt-derived flags. There is no concept of "handled" for fake-location (a correction handles Checkout missing, but nothing handles a fake attempt). There is no lookback bound for the dashboard.
- **Risk:** The dashboard story invents an acknowledgement table, or scans all history (hurting NFR-7).
- **Fix:** State in AD-10 that `fake_location_attempt` is a flag derived from `attendance_attempts` (outcome `mocked`). Define "handled":
  - Checkout missing is handled when a correction exists.
  - Fake-location is handled when the Owner dismisses it (a single-row `attendance_flag_acknowledgements`, keyed `(employee_id, work_date, flag)`), or when the flag ages out after N days.
  
  Pick one, and bound the dashboard's lookback (for example the current and previous month) for NFR-7.

### G-12 [MEDIUM] NFR-9: reminder-job failures and per-tenant isolation
- **Source:** NFR-9: "reminder job runs **and failures** are logged and exposed as metrics".
- **Spine:** AD-14 has one cron and one function for all tenants. Deferred moves metrics to the reminders story.
- **Risk:** One tenant's bad data (for example an invalid timezone row, or an exception in a helper) makes the whole `attendance_run_reminders()` transaction fail, so every tenant loses reminders silently. Deciding the metric path per story is fine. Isolation is not a per-story choice.
- **Fix:** Add to AD-14: each tenant is evaluated in its own `BEGIN … EXCEPTION` block. Failures are written to an `attendance_job_runs` table (run_at, tenant_id, reminders_created, error). NFR-9 metrics then read that table, so the gauge-vs-table choice is resolved now.

### G-13 [MEDIUM] NFR-7 has no measurement gate or read-shape constraint
- **Source:** NFR-7: check-in ≤ 2 s p95, and the monthly view for 50 Tracked employees ≤ 3 s p95.
- **Spine:** AD-10 allows materialisation "only if NFR-7 fails in measurement", but says nothing about when or how it is measured. It does not require the monthly list, dashboard and calendar to call `attendance_day_statuses` **once** with an employee array (no N+1 per employee). It names no supporting indexes for the effective-dated lookups.
- **Fix:** Add to AD-10:
  - Every read route makes exactly one set-based call per screen.
  - Required indexes: gist on each `valid`, plus `(tenant_id, employee_id, work_date)` on records, overrides, attempts and leave days.
  - An integration perf check seeds 50 employees × 31 days and asserts that the function's time budget holds before the monthly-view story is done.

### G-14 [MEDIUM] Pending leave: effect on reminders and the dashboard "on leave" tile is not pinned
- **Source:** FR-10 rule 9 / FR-13: pending leave counts as **Absent** with a "Leave pending" marker. FR-9: a Pending full-day leave triggers the check-in dialog. FR-23: the check-in reminder fires with "no full-day leave" (pending or approved is not stated). FR-24: the "on leave" tile.
- **Spine:** AD-10 returns "leave markers" but does not say how AD-14 and the dashboard treat pending.
- **Fix:** One sentence in AD-10/AD-14 (with PM confirmation): "Only **approved** full-day leave suppresses the check-in reminder and counts in 'On leave'. Pending shows as the 'Leave pending' marker, is not counted as leave, and does not suppress reminders". Or the opposite. Just state it once.

### G-15 [MEDIUM] Corrections on untracked dates break FR-10's "counts add up to tracked days"
- **Source:** FR-10 consequence: "the Day status counts add up to the number of tracked days". FR-21: correct "any past or current date".
- **Spine:** AD-12 makes a correction priority 1, above Not tracked (rule 2), and puts no guard on the date.
- **Fix:** Add to AD-12: the correction RPC rejects (PT422) dates outside any enrolment range and dates in the future. A correction on a tracked date stays priority 1.

### G-16 [LOW] Onboarding "shows once per Employee" (FR-4): where is this stored?
- If it is stored on the device, onboarding shows again after switching phones or reinstalling. That goes against the server-owned access model in AD-17.
- **Fix:** Add `onboarded_at` (per user, or per enrolment) to the `/users/me` fields in AD-17, set by a plain single-row write.

### G-17 [LOW] Reminder lag and missed runs
- AD-14 accepts up to 5 minutes of lag. UJ-2 and FR-23 give exact times (6:22 PM). The spine should also say what happens after a missed run (cron downtime): fire late within the same work_date (recommended, since the dedupe key makes it safe) or skip. Record the 5-minute lag as an accepted deviation from FR-23 "at defined times".

### G-18 [LOW] NFR-4 "valid radius/time ranges" as DB constraints
- The Conventions table makes thresholds "named SQL constants". NFR-4 asks for database **constraints**.
- **Fix:** State that radius 50–1000, late cut-off 0–120, `half_day_hours < full_day_hours`, both > 0, `end_time > start_time`, reason ≤ 500 chars, and the weekly-off "≥ 1 working day" rule are `CHECK` constraints, not only RPC checks.

### G-19 [LOW] Holiday uniqueness and edit semantics
- FR-20 add/edit/remove. There is no `UNIQUE (tenant_id, holiday_date)`, and a date change on edit is not defined as remove + add. That matters for the FR-22 notifications "holiday added over leave" and "holiday removed inside range".
- **Fix:** Add both to the FR-20 row or to AD-11/AD-13.

### G-20 [LOW] Owner dashboard freshness
- EXPERIENCE UJ-2 says the check-in is "mirrored on the owner's dashboard **in real time**". A check-in emits no owner notification, so nothing pushes it. The spine should say the dashboard refreshes on focus and on pull-to-refresh only, and that the UX wording is not a requirement. The other choice is to add a broadcast, which would be new scope.

### G-21 [LOW] UX adds an "Absent" KPI tile that FR-24 does not list
- EXPERIENCE "Dashboard KPI tiles" lists Absent. FR-24 does not. Today can never be final Absent (FR-10 rule 10), so the tile has no clear meaning for "today". Resolve this with UX and the PM. It affects the dashboard read contract.

### G-22 [LOW] AD-8 "only the upper bound of a past range may ever change" vs FR-2 "change or cancel a future start date"
- A range that has not started must be deletable and editable as a whole. State this explicitly, so the enrolment RPC does not refuse FR-2's future-start edits.

---

## 3. Checked and correctly landed (no action)

- Holiday-over-weekly-off precedence (FR-10 rule 4). This is owned by the single AD-10 function.
- Leave cut-off at the Office Start time, and the Midpoint (AD-2 list).
- The fake-location 3rd-attempt alert committed with the attempt, and deduped per employee+month (AD-4). The double-count risk is covered in G-2.
- Pending never auto-expires. Leave is stored per date, and "counts as leave" is decided on read (AD-11).
- Office rules apply from tomorrow, reassignment after check-in applies from tomorrow (AD-8), and past dates use the rules of that date (AD-8, AD-9 once C-4 is applied).
- NFR-11: location only on tap, never in the background (AD-20). No coordinates in logs (Conventions, AD-9).
- NFR-5 timezone model (AD-7). NFR-12 module boundary (AD-1). Shared inbox dispatch (AD-19). Access state from a single source (AD-17).
- Deploy order (additive BE first) matches the addendum §C1.

## 4. Correctly left to stories (not flagged)

Exact ErrorCode list, DTO field validation, literal copy strings (rate-limit copy), calendar glyph and icon distinctness, the map library spike, the 44 px exception for calendar cells, the half-day-toggle UX, and the pull-to-refresh placement.
