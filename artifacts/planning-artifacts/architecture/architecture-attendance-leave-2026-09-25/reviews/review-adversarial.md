---
title: Adversarial review — Attendance & Leave architecture spine
reviewed: ARCHITECTURE-SPINE.md (draft, 2026-09-25)
lens: "Construct two units one level down that each obey every AD to the letter yet still build incompatibly"
inputs: spine, prd.md, fenzit-be brownfield (src/notifications, src/users, src/common, supabase/migrations)
date: 2026-09-25
---

# Adversarial Review — Attendance & Leave Spine

## Verdict

The spine is strong on single-function atomicity, but it doesn't bind the **shared primitives** that many RPCs need: day context, leave transitions, enrolment changes, lock mode, the notification contract and read-function grants. So independent stories can each follow every AD and still build incompatible pieces. There are 14 holes: 1 critical, 5 high, 6 medium, 2 low. Each hole below has a proposed new or tightened AD.

Severity key: **Critical** = data leak or silent corruption in production. **High** = two stories will very likely build incompatible code. **Medium** = likely rework or a user-visible mismatch. **Low** = friction or merge conflicts.

---

## H-1 [Critical] Read functions and helpers are outside the EXECUTE-revoke rule

**Unit A — "Owner dashboard / monthly" story.** It builds `attendance_day_statuses(p_tenant_id, p_employee_ids, p_from, p_to)` as `SECURITY DEFINER` (it has to read across RLS for the owner path through the admin client). Per AD-16 it "verifies `p_tenant_id`": it checks that the employee ids belong to `p_tenant_id`. AD-3's revoke rule covers only writes that touch more than one row-set, so this story leaves the default `EXECUTE` grant to `PUBLIC` in place. The same goes for `attendance_access`, `attendance_today` and any helper such as `attendance_is_working_day`.

**Unit B — "RLS isolation probes" story.** Per AD-3 it adds "a direct-call probe for each new function" to the write-RPC list only, and it passes.

**Divergence.** `p_tenant_id` is a parameter the caller controls. With the public anon key (or a technician realtime token once AD-18 opens), anyone can call `rpc('attendance_day_statuses', {p_tenant_id: <victim>, p_employee_ids: [...]})` through PostgREST and read another tenant's attendance. "Verifies p_tenant_id" only checks the caller against their own input. The brownfield reality makes this worse: migration `20260920000005` says in its own comment that "EXECUTE is granted to PUBLIC by default", and the older RPCs still grant it.

**AD fix (tighten AD-3, add AD-3a):**
> **AD-3a — Every new attendance function is service-role-only.** Every function created by an attendance migration — write RPC, read function, internal helper, trigger function or cron entry point — has `REVOKE EXECUTE ... FROM PUBLIC, anon, authenticated` in the same migration file that creates it. Read functions are `SECURITY DEFINER SET search_path = public` and are called only through `createAdmin().rpc()`. Internal helpers (for example `attendance_day_context`, `leave_transition_days`, `attendance_notify`) are also never called by NestJS. The RLS isolation spec enumerates `pg_proc` for every function whose name matches `^(attendance|leave|holiday)_` and asserts that `anon` and `authenticated` lack EXECUTE on it. The probe is driven by the catalogue, not by a hand-kept list, so a new function can't slip through.

---

## H-2 [High] No shared "day context" primitive. Check-in, leave, reminders, access and day status each work out "is this a working day / what is expected start"

**Unit A — "Check-in/out" story.** Inside `attendance_check_in` it works out: whether today is tracked, the office, the active `attendance_office_rules`, whether today is a weekly off (override first, then default), whether it is a holiday (for "no Late flag"), whether it is a first-half leave day, and so Expected start = Midpoint. It writes these as local `SELECT`s.

**Unit B — "Day-status engine" story.** It builds `attendance_day_statuses` with its own CTEs for the same facts. AD-10 says it is the "only implementation of the FR-10 **priority order**". It does not say it is the only implementation of the **inputs** to that order.

**Unit C — "Reminders" story.** AD-14 says it uses "the same helpers as AD-10", but no AD names or owns those helpers. So the reminder story either calls `attendance_day_statuses` for every tenant every 5 minutes (too slow and the wrong shape: it needs due times, not statuses), or writes its own third copy.

**Unit D — "Leave apply" story.** It counts working days, rejects ranges that are all off days, and applies the "today before Office Start" cut-off. That is a fourth copy.

**Concrete divergences:**
- **Midpoint rounding.** 10:00–17:45 gives a midpoint of 13:52:30. One copy does `start + (end-start)/2` as `TIME` (13:52:30). Another truncates to the minute. The reminder fires at 14:07 while the Late flag starts at 14:08.
- **Holiday + weekly off + override precedence.** One copy lets an override *add to* the default. Another lets the override *replace* it. FR-19 says "wins", which reads as replace, but nothing binds that.
- **FR-2 enable-day grace** ("enabled after today's Start time → Not tracked unless checks in"). Day status implements it. Reminders don't, so the employee gets a "you haven't checked in" reminder on the day they were enabled, which FR-2 forbids. The dashboard's "Not checked in yet" count also includes them.
- **Setup not complete.** No AD says that enrolments written during the wizard (before `setup_completed`) produce no reminders or statuses, or that `attendance_access` returns `none` for them.

**AD fix (new AD-10a; tighten AD-10 and AD-14):**
> **AD-10a — One day-context primitive feeds every rule.** `attendance_day_context(p_tenant_id, p_employee_ids uuid[] | NULL, p_from date, p_to date)` (internal, EXECUTE revoked) returns one row per employee-date with: `tracked bool` (enrolment covers the date, tenant setup completed, and the FR-2 enable-day grace applied), `office_id`, `office_rules_id`, `start_time`, `end_time`, `midpoint` (defined as `start + ((end - start) / 2)`, truncated to the whole minute), `late_cutoff_min`, `full_day_min`, `half_day_min`, `is_weekly_off` (the override **replaces** the default; the default applies only when no override range covers the date), `holiday_id`, `is_working_day`, `leave_day_id`, `leave_state`, `leave_part ∈ {full, first_half, second_half}`, `expected_start`, `expected_end`. `attendance_day_statuses`, `attendance_check_in/out`, every `leave_*` RPC (working-day count, all-off rejection, Start-time cut-off), `attendance_run_reminders`, `attendance_access` and the dashboard **must** read these facts from this function and must not re-query the rule tables. An integration spec asserts that, for a fixture month, the check-in's `expected_start`/`late_minutes` snapshot and the reminder due time agree with `attendance_day_context` for every date.

---

## H-3 [High] Four writers of `leave_request_days` with no shared transition path

**Unit A — "Check-in" story (FR-9).** Inside `attendance_check_in` it runs `UPDATE leave_request_days SET state='cancelled' WHERE employee_id=... AND leave_date=today`. It then inserts a `leave_events` row with `actor_id = employee` and a notification `leave.cancelled` to the Owner. This is legal: it runs under the employee lock and in one transaction.

**Unit B — "Leave cancel/revoke" story.** It writes `leave_cancel` and `leave_revoke`, each with its own `leave_events` shape (`affected_dates date[]`) and its own notification payload.

**Unit C — "Removal" (FR-28, later) and "disable enrolment" (FR-2).** These also cancel future leave, with a system actor and *no* notification to the employee.

**Divergences:**
- The Owner receives `leave.cancelled` ("Leave cancelled by Arjun") instead of `leave.auto_cancelled_on_check_in`. Or they receive both, because the check-in story emits one and a trigger emits the other.
- `leave_events` gets one row per date from one writer and one row per request with `date[]` from another. The FR-17 history view then can't render one timeline.
- The trigger guard (AD-11) allows `approved → cancelled` whatever the cause. So nothing stops a check-in-cause cancel on a **half-day** leave, which FR-9 forbids.
- **Off-day rows.** AD-11 stores one row for *every* calendar date, off days included. The revoke story revokes only "working future dates" and leaves off-day rows `approved`. Later a holiday is removed on that date, AD-11 recounts it as leave, and the employee is silently on leave on a revoked date. Another story revokes all dates, and the two disagree.

**AD fix (new AD-11a):**
> **AD-11a — One leave-transition helper.** All `leave_request_days` state changes go through an internal `leave_transition_days(p_tenant_id, p_employee_id, p_request_id, p_dates daterange, p_to_state, p_cause, p_actor_id, p_reason)`. It asserts that the employee lock is already held (for example by checking `pg_locks`). It transitions **every** row in `p_dates`, including off-day rows. It appends exactly **one** `leave_events` row `{request_id, cause, from_state, to_state, dates daterange[] , actor_id, reason}`, and it emits the notification that the cause-to-event table in `notification-events.ts` maps. `p_cause ∈ {apply, apply_on_behalf, approve, reject, employee_cancel, owner_revoke, checkin_auto_cancel, disable, removal}`. The trigger guard also checks cause-specific legality: `checkin_auto_cancel` only on `leave_part = full`; `employee_cancel` / `owner_revoke` only on dates later than `attendance_today()`, or on today before `expected_start` from AD-10a. `disable` and `removal` emit no employee notification. No RPC updates `leave_request_days` directly.

---

## H-4 [High] Request-level leave status: "derived" but no one owns the derivation

**Unit A — "Leave list API" story.** It derives the status in TypeScript from the day rows: `any pending → Pending; else any approved → Approved; else …`.

**Unit B — "Pending-leave reminder" (SQL) and "Owner pending queue" (SQL filter plus pagination).** Each writes its own `EXISTS (… state='pending')`.

**Unit C — "App leave card" story.** It needs "Revoked (Thu–Fri)" and "Approved (Mon–Wed)", and derives segments on the device.

**Divergences.**
- A request that is Approved Mon–Wed and Revoked Thu–Fri shows as "Approved" in TS, while the app shows "Partially revoked".
- A pending request whose only pending rows are now off days (a holiday was added) still counts in the reminder but has 0 working days.
- The pending queue can't paginate on a TS-derived value.
- Deriving in TS or on the app also breaks AD-2 in spirit (counting working days).

**AD fix (tighten AD-11):**
> Request-level status is computed only by the SQL read function `leave_request_summaries(p_tenant_id, p_employee_id | NULL, p_status | NULL, cursor)`. It returns `{status ∈ {pending, approved, rejected, cancelled, revoked, partially_revoked, partially_cancelled}, segments: [{state, from, to}], workingDays, pendingWorkingDays}`. Precedence: `pending` if any *working* day is pending. Otherwise, if the approved days sit alongside revoked/cancelled days, return `partially_*`. Otherwise return the single remaining state. Off days never decide the status. The pending queue, the pending-leave reminder and FR-17 all use it. NestJS and fenzo-app never derive status.

---

## H-5 [High] Enrolment and office assignment in one effective-dated table: the mutation rules are undefined

**Unit A — "Office reassignment" story (FR-6).** "Move to Thane from 1 Nov": it closes `[start, 1 Nov)` (Andheri) and inserts `[1 Nov, ∞)` (Thane).

**Unit B — "Disable employee" story (FR-2).** On 20 Oct it closes the *current* range at the disable date, exactly as AD-8 says ("close the current range and insert the next"). It does not touch the future Thane row. **On 1 Nov the employee is silently re-tracked.**

**Unit C — "Change/cancel future start date" (FR-2).** It needs to move the **lower** bound of a future range. AD-8 only says "only the upper bound of a past range may change". It says nothing about future ranges, so one story updates in place and another closes to an empty range (`[d,d)` is legal under EXCLUDE and leaves junk).

**Unit D — "FR-2 enable-day grace".** It is implemented as "range lower = today AND row created_at > today's start_time → today not tracked". Then a *same-day office reassignment before check-in* inserts a new row with lower = today and created_at after Start. **Today flips to Not tracked** for someone who was already being tracked. This follows from putting "tracked period" and "office assignment" in one table.

**AD fix (tighten AD-8, add AD-8a):**
> **AD-8a — Enrolment mutation algebra.** Tracked periods and office assignment are kept apart: `attendance_enrolments(employee_id, valid, enabled_at timestamptz)` holds tracked periods, and `attendance_office_assignments(employee_id, office_id, valid)` holds the office. Every enrolment date must be covered by exactly one assignment (checked by a constraint trigger). The FR-2 grace uses only `attendance_enrolments.enabled_at`. All changes go through one RPC per table, `attendance_set_enrolment(p_employee_id, p_from, p_enabled bool)` / `attendance_assign_office(p_employee_id, p_from, p_office_id)`, with these semantics: *effective_from* = `max(p_from, today)`, bumped to tomorrow if the employee has a check-in today. **Every** range with lower ≥ effective_from is deleted (future ranges are unjudged and may be deleted or rewritten). The range covering effective_from has its upper bound set to effective_from. The new range is inserted. Empty ranges are forbidden (`CHECK (NOT isempty(valid))`). Disabling truncates both tables. The same algebra applies to office rules and weekly-off tables.

---

## H-6 [High] Lock protocol: tenant-wide RPCs vs employee RPCs don't serialise

**Unit A — "Holiday add" story.** It takes `attendance:tenant:<id>` as AD-5 says. It inserts the holiday, then notifies (a) every tracked employee (FR-20) and (b) each employee with approved leave on that date ("Holiday added over approved leave"). It doesn't take employee locks, because AD-5 only says a function that "needs both" takes them, and it mutates no employee row.

**Unit B — "Leave approve" story.** It takes only the employee lock, as AD-5 says for "RPCs acting on one employee".

**Divergences.**
- The two locks don't conflict. So if the approve commits after the holiday RPC's snapshot, the employee never gets the "Holiday added over approved leave" notification. The same race applies between office-rule change and check-in (which rules the Late snapshot used), and between weekly-off change and leave apply (working-day count and "all days off" rejection).
- If Unit A *does* lock every tracked employee in ascending order while an employee RPC ever touches tenant data under its own lock and then asks for the tenant lock, you get a deadlock.
- The report module's existing lock key is `hashtextextended(p_tenant_id::text, 0)`, with no namespace. It doesn't collide with the attendance keys, but it shows keys aren't registered anywhere.

**AD fix (tighten AD-5):**
> Every employee-scoped attendance/leave RPC first takes `pg_advisory_xact_lock_shared(hashtextextended('attendance:tenant:'||tenant_id,0))`, then the exclusive employee lock. Every tenant-wide RPC (holidays, weekly-off default, office rules/archive, bulk enrolment, setup completion) takes the **exclusive** tenant lock and, unless it changes per-employee rows, takes **no** employee locks. A tenant-wide RPC that changes per-employee rows (bulk enrolment) then takes employee locks in ascending `employee_id` order. No function asks for the tenant lock after an employee lock. Lock keys are declared once as SQL functions `attendance_lock_tenant(uuid, shared bool)` / `attendance_lock_employee(uuid)`, and RPCs call only these.

---

## H-7 [Medium-High] Notification contract: no single source of truth for payload, entity or dedupe

**Unit A — backend `notification-events.ts`.** AD-13 registers each event's *name and wave*. The SQL RPCs build the payload with hand-written `jsonb_build_object(...)`.

**Unit B — fenzo-app registry (AD-19).** It "mirrors" the names and renders cards from payload keys it guesses.

**Divergences.**
- The revoke RPC writes `{dates: ['2026-10-01','2026-10-02']}` while the app card reads `{from, to}`. Both follow "self-contained camelCase".
- `entity_type`/`entity_id` values (`leave_request` vs `leave`) and the deep-link target format are not fixed.
- `NotificationResponse` (src/notifications/dto) exposes neither `entityType` nor `entityId`. `NotificationRow.job_id` is typed `string`. AD-1's list of allowed generalisations covers only "jobId nullable", so the app can't deep-link without a payload field that one story adds and another doesn't.
- **dedupe_key.** AD-14 fixes the grammar for reminders only. The fake-location alert (AD-4, "deduped per employee+month") gets an ad-hoc key, for example `fake_gps:<emp>:2026-10` vs `attendance.fake_location:<emp>:<YYYY-MM>`.
- `notifications-cleanup` (migration `20260909000004`) deletes rows after 30 or 90 days. So once pushed rows die at 30 days, the monthly dedupe (which relies on the row still existing) can fire again at the end of a 31-day month.
- Notification `createdAt` is returned as a UTC string, while AD-7 says attendance instants carry the tenant offset. The same screen then shows two time conventions.

**AD fix (tighten AD-13):**
> `src/attendance/notification-events.ts` is the **single source of truth**. For each event it declares `{eventType, wave, recipient ∈ {owner, employee}, entityType ∈ {leave_request, attendance_day, holiday}, payload: <TS type>, deepLink: (payload) => route, dedupe: 'none' | template}`. A migration seeds `attendance_notification_types(event_type, entity_type, payload_keys text[])` from the same list. The only notification writer is the internal SQL `attendance_notify(p_tenant_id, p_user_id, p_event_type, p_entity_id, p_payload, p_dedupe_scope)`, which rejects unknown types or missing keys. The dedupe grammar for all events is `<event_type>:<recipient_id>:<scope>` (scope = `YYYY-MM-DD` work_date, `YYYY-MM` month, or `office_id:YYYY-MM-DD`). The fake-location alert fires only when that month's `mocked` count **equals** 3, so dedupe is a backstop and not the only guard. `NotificationResponse` gains nullable `entityType`/`entityId` as an allowed AD-1 generalisation. fenzo-app types its registry from a generated copy of the payload types. A contract test checks that the TS registry and the SQL seed agree.

---

## H-8 [Medium] Idempotency keys vs rejected outcomes vs rate limit

**Unit A — app "Check-in" story.** It generates one idempotency key per *logical* check-in intent and reuses it on retry after a `too_far` (AD-6: "retries … never create duplicates").

**Unit B — "Check-in RPC" story.** It stores `request_id` on the `attendance_attempts` row too, so that a rejected replay "returns the original result". Now the employee who walks 50 m closer and retries gets `too_far` replayed **forever**.

Alternatively, the RPC story counts every non-ok outcome in AD-15's "rejected attempts", including `rate_limited`, `already_checked_in` and `not_tracked`. Then each tap during the block inserts another attempt, and the 10-minute block never ends.

**AD fix (tighten AD-6 and AD-15):**
> `request_id` is stored only on the success row (`attendance_records.check_in_request_id` / `check_out_request_id`) and never on `attendance_attempts`. A replay of a *rejected* key is re-evaluated. fenzo-app mints a new key per tap and reuses it only for a transport-level retry of the same HTTP request. Only `too_far`, `low_accuracy`, `mocked` and `stale_fix` insert attempts and count toward AD-15. `rate_limited`, `already_checked_in`, `not_checked_in` and `not_tracked` insert nothing. A key reused with a different payload hash returns 422 `ATTENDANCE_IDEMPOTENCY_MISMATCH`.

---

## H-9 [Medium] FR-9 and weekly-off confirmation vs AD-20's "exactly the request body"

**Unit A — app story.** It shows "You're on leave today. Checking in will cancel today's leave" and "It's a holiday. Check in anyway?". To know this it reads today's leave and holiday state on the client (a rule decision on the device, against AD-2) or from a `me/today` read. Then it sends the AD-20 body **unchanged**, because AD-20 says the capture output "is exactly the check-in/out request body".

**Unit B — RPC story.** It auto-cancels leave whenever a check-in lands on a full-day leave date. An app build that is stale (or a leave approved a second after the screen loaded) cancels leave **without** the user having confirmed. FR-9 needs that confirmation.

**AD fix (tighten AD-4 and AD-20):**
> The check-in body is the AD-20 capture plus `acknowledged: ('leave_cancel' | 'off_day')[]`. `attendance_check_in` returns the committed, non-error outcome `confirmation_required` with `reasons[]` when the day (per AD-10a) needs an acknowledgement that the body lacks. It writes no attempt row for this outcome and it doesn't count toward the rate limit. The app shows its dialogs **only** in response to this outcome, or to the `todayPrompt` field of `GET /attendance/me/today`, which the server computes. The app never works it out.

---

## H-10 [Medium] Effective-dating in the setup wizard vs post-setup edits

**Unit A — "Setup wizard" story.** Step 2 saves office rules through the *same* rule RPC as later edits. "Applies from tomorrow" then makes the first rule start tomorrow, so on setup day there is no rule, and check-ins today fail or pick up nulls. Or the story writes the first rule directly as `[today, ∞)` using the AD-3 single-row exception ("office name"-style plain SQL).

**Unit B — "Office edit" story.** It enforces from-tomorrow. When the Owner re-edits step 2 on resume, each edit closes a range and creates `[tomorrow, ∞)` history rows for rules that never judged a single day.

**Other gaps.**
- The FR-18 weekly-off "effective from a date the Owner picks" could be a past date, which AD-8 forbids ("only the upper bound of a past range"). No AD says how the date is clamped.
- AD-17's `attendanceEnabled` depends on setup completion, but there's no rule that enrolments saved in wizard step 5 stay inert until completion (see H-2).

**AD fix (tighten AD-8):**
> Before `attendance_settings.setup_completed_at` is set, rule and enrolment writes **replace** the tenant's single range in place, with lower bound = the completion date, set by `attendance_complete_setup`. After completion, office rules apply from tomorrow, and weekly-off, enrolment and assignment changes apply from `max(picked, today)`. A past effective date is rejected with PT422 `ATTENDANCE_EFFECTIVE_DATE_IN_PAST`. The wizard calls the same RPCs as post-setup edits. Only the `attendance_setup_progress` step pointer uses the AD-3 single-row exception.

---

## H-11 [Medium] `attendance_day_statuses` inputs: who picks the employees, and what the office filter means

**Unit A — "Dashboard" story.** It picks employees in TS with `enrolments.valid @> today AND office_id = :office` and passes `p_employee_ids`.

**Unit B — "Monthly" story.** It picks employees whose enrolment *overlaps* the month, filtered by their *current* office.

**Divergence.** An employee reassigned Andheri to Thane on the 15th shows full-month totals under Thane in the monthly list but under Andheri on the dashboard until the 14th. Per-office totals no longer add up to the tenant total. Choosing "tracked in range" in TS is also a rule computation, which AD-2 bans.

**AD fix (tighten AD-10):**
> `attendance_day_statuses(p_tenant_id, p_employee_ids uuid[] | NULL, p_from, p_to, p_office_id uuid | NULL)`. NULL employees means every employee with any tracked date in the range. Each row carries that date's `office_id`. The office filter applies **per row** (each date is attributed to the office assigned that day), so an employee may show under two offices in one month, each with only those dates' totals. NestJS never picks the employee set itself.

---

## H-12 [Medium] State-guard idempotency returns 409 to a client whose action actually succeeded

**Unit A — RPC story.** It follows AD-6: approve on a request that is not pending returns PT409.

**Unit B — app story.** It follows AD-21 (pessimistic). A request times out, the user taps Approve again, gets 409 and shows "Couldn't approve". Yet the leave *is* approved, and the Owner may then reject it.

**AD fix (tighten AD-6):**
> A state-guard PT409 carries `currentState` (and the request summary from H-4) in the error extras. fenzo-app treats a 409 whose `currentState` equals the action's target state as success, and refetches in both cases.

---

## H-13 [Low-Medium] `/users/me` extension and the module boundary

**Unit A — "Users" story.** It adds `attendanceAccess` by importing an `AttendanceAccessService` from `src/attendance`. AD-1's ban list names jobs, workflow, sync, reports and notifications, not users.

**Unit B — "Attendance" story.** It later adds a TS import from `users`, creating a circular module dependency. Or it changes the `attendance_access` return columns and silently breaks `/users/me`.

There is also a gap for the Owner: `attendance_access(tenant, owner_id)` has no enrolment, so it returns `none`. The Owner's entry point (FR-3: always visible) must use `attendanceEnabled` only, and nothing says so.

**AD fix (tighten AD-17):**
> `users.service` calls `admin.rpc('attendance_access', …)` directly and never imports from `src/attendance`, and `src/attendance` never imports `users`. The return columns (`attendance_enabled`, `attendance_access`, `attendance_start_date`) are a frozen contract, and a contract spec covers them. For `role = owner` the function returns `attendanceAccess = 'none'` always. fenzo-app shows the Owner entry point without conditions and uses `attendanceEnabled` only to choose between the wizard and the dashboard.

---

## H-14 [Low] Shared-file edits: `CursorScope`, `ErrorCode`, PTxxx to code mapping

- `CursorScope` (src/common/utils/cursor.util.ts) is a closed union, and the cursor payload is `(id, createdAt)` with `TIMESTAMP_RE` allowing only ISO timestamp characters. One story paginates leave by `leave_date` (fine) and another pages the monthly employee list by `name`. The regex rejects names, so that story forks a second cursor codec.
- Parallel stories each append to `ErrorCode` and pick overlapping names (`ATTENDANCE_TOO_FAR` vs `ATTENDANCE_OUT_OF_RADIUS`, one per check-in/check-out story).
- PT422 is raised for several different leave rules (overlap, all off days, more than 7 days back, check-in exists), but the service can map only `error.code`. Each story invents its own message-string parsing.

**AD fix (tighten Conventions / Errors; move "exact ErrorCode list" out of Deferred):**
> A foundation story adds **all** `ATTENDANCE_*`/`LEAVE_*` codes and new `CursorScope` values in one change, together with `attendance.constants.ts`'s `OUTCOME_TO_ERROR` map, which check-in and check-out share. Every attendance RAISE uses `USING ERRCODE = 'PT4xx', HINT = '<ERROR_CODE>'`, and one shared `mapRpcError()` in `src/attendance` reads `error.hint`. Attendance lists page only on `(created_at, id)` or `(date::timestamptz, id)`. The monthly employee list (≤ 50, NFR-7) isn't paginated.

---

## Coverage of the probe list

| Probe | Result |
| --- | --- |
| Office-rule effective-dating vs wizard writes | H-10 |
| Shared "working day / expected start" helper | H-2 (none mandated) |
| FR-9 auto-cancel vs leave RPCs sharing lock + events + notification | H-3, H-9 |
| Holiday fan-out vs AD-5 lock order | H-6 |
| Enrolment ranges vs office assignment, reassignment vs disable | H-5 |
| Request-level status derivation SQL vs TS | H-4 |
| Notification payload source of truth | H-7 |
| Day-status inputs with different offices / timezones | H-11. Timezone is tenant-wide (AD-7), so there's no hole there. |
| dedupe_key formats: fake-location vs reminder | H-7 |
| IdempotencyInterceptor absent vs other routes | H-8. The interceptor is not applied, which is fine. The hole is key reuse vs rejections. |
| `/users/me` owned by users vs attendance | H-13 |
| CursorScope / ErrorCode collisions | H-14 |
| (new) EXECUTE grants on read functions | H-1 |
| (new) 409 on retried state transition | H-12 |
