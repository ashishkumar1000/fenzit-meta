# Spec — Stories 19-1, 19-2, 19-3 (+ 18-5 fold-in): Scheduled Reminders & Read Views (Backend)

- **Stories:** 19-1 (scheduled reminders on pg_cron) + 19-2 (owner dashboard read) + 19-3 (monthly & self-view read) — one shared spec, one dev pass, one review, one commit (user decision 2026-09-29; the 17-1..17-4 / 18-1+18-2 precedent). **18-5 (office rule mandatory with a prefilled default) folds in** — its BE half is one gate, and its FE half (a prefill) is two edited lines, so a separate story would cost more than the work.
- **Repos:** 19-1..19-3 → fenzit-be only. 18-5 spans BOTH repos by design (FE prefill in fenzo-app, BE gate in fenzit-be) → **two commits, two repos, fenzit-be deploys first** (cross-repo ordering).
- **Status:** user sign-off received 2026-09-29 ("both as recommended" — D4's NFR-9 gauge ratified; §8 finding 1 resolved to Option A: checkout reminder fires at Expected end + actual late minutes, `late = 0` for punctual check-ins). **Implementation complete 2026-09-29** — migrations 04+05 applied live via Supabase MCP, cron verified (all jobs scheduled), registry + NestJS surface + docs updated, `nest build` clean. **BMAD `/bmad-code-review` (group A: migrations + src) COMPLETE 2026-09-29** — 5 decisions resolved by the user, 16 patches applied, 1 deferred (pre-existing), 13 dismissed; both batteries green after the patches: unit + mocked e2e **90 suites / 1400 tests**, real DB **28 suites / 535 tests** (commit consent pending). `/bmad-code-review` before any commit; commits only on explicit consent.
- **User decisions locked 2026-09-29:** Epic 19 BE before Epic 17 FE; 19-1..19-3 in ONE shared spec; 18-5 folds into it (fold-in decision 2026-09-29).
- **Sources:** epics-attendance-leave.md §Stories 19.1/19.2/19.3 (ACs quoted where they bind); ARCHITECTURE-SPINE.md AD-5, AD-7, AD-10, AD-13, AD-14, AD-16, AD-17, AD-22, AD-24 (n/a — no previews), AD-25, AD-26, NFR-7, NFR-9, NFR-10, the Consistency Conventions table (Routes row: `dashboard`, `monthly`, `me/*`); PRD FR-23, FR-24, FR-25, FR-26 (testable consequences quoted), FR-22 (reminders ARE in the closed notification list per FR-23's "A Reminder appears in the in-app notification list"), SM-2/SM-4/SM-C2 (reminder volume bounded to FR-23's four types — nothing else may emit).
- **Carried deviation (not new, per AD-3's amendment of 2026-09-27 and the 16-1/17-1/18-1 precedents):** there is **no `attendance_day_statuses` or `attendance_day_context` SQL object** — Epics 16–18 shipped NestJS-first; AD-22 is the TypeScript `DayContext` (`src/attendance/day-context.ts`) and FR-10 lives in `day-status.model.ts`. **19-2/19-3 therefore aggregate in TypeScript over the existing engine read** (`readDayStatusGrid` — its own doc pins "every Epic 19 aggregate reads rows only from here"). **19-1 is the sanctioned exception in the other direction:** AD-14 (locked) mandates the reminder job as a PL/pgSQL function on pg_cron — a DB function cannot import TypeScript, so `attendance_run_reminders()` re-derives the AD-22 fact subset it needs in SQL from the **same tables** the TS assemblers read, and a real-DB **parity probe** pins the equivalence (§6). This is the one sanctioned SQL-side behaviour in Epics 16–19; it is stated here so the next reader doesn't rediscover it.

## 1. Fix-placement analysis (per the root-CLAUDE.md rule)

| Concern | Layer | Why |
|---|---|---|
| `attendance_run_reminders()` + three pg_cron schedules | **DB** (migration) | pg_cron jobs execute SQL — an in-process scheduler is forbidden (AD-14's whole point: the single Render instance double-fires/misses across deploys). This is the one sanctioned stored computation. |
| Reminder dedupe | **DB** (existing partial unique index on `notifications.dedupe_key`, 20260925000005) | "guaranteed by the database, not the job's own logic" (FR-23) + a re-run job must be free. |
| Dashboard tiles/flags aggregation | **BE** (TypeScript over `readDayStatusGrid` + two targeted marker reads) | The engine is the single FR-10 source; aggregation is arithmetic over already-read rows (18-1 D1/AD-3 amendment). |
| Monthly & self-view summaries | **BE** (one aggregation module shared by owner + me routes) | FR-11's "totals always match" is guaranteed by **one implementation**, not by two functions agreeing. |
| 18-5 BE validator (rule present at completion) | **DB** (`attendance_complete_setup` gate) | The completion gate is DB-owned (FR-1, 15-2/20260927000008): tracking must not turn on against a rule-less office no matter which client called. |
| 18-5 FE prefill | **fenzo-app** (`emptyOfficeForm()` / `formFromDetail()` defaults) | The gap the user ruled on is the form: times are mandatory but start blank; a prefilled default is presentation concern, server values still authoritative. |
| NFR-9 reminder metrics | **BE** (OTel ObservableGauge over `cron.job_run_details`) | Resolves the spine's open NFR-9 decision (line 510): the gauge polls at export time — **no timer in the web service** (AD-14 posture), no new table (AD-26: no new infrastructure), and the 7-day prune keeps `job_run_details` bounded by design. |

## 2. Design decisions (locked before implementation; user sign-off points marked)

**D1 — One migration creates `attendance_run_reminders()` and the three pg_cron jobs** (`supabase/migrations/20260929000004_attendance_run_reminders.sql`, applied via Supabase MCP). Unschedule-then-schedule pattern (20260621000012 convention; pg_cron does not enforce unique names). Job names and schedules:

| jobname | schedule | body |
|---|---|---|
| `attendance-run-reminders` | `*/5 * * * *` | `SELECT public.attendance_run_reminders();` |
| `cron-job-run-details-cleanup` | `0 3 * * *` | delete from `cron.job_run_details` where `start_time < now() - interval '7 days'` |
| `attendance-attempts-coordinate-cleanup` | `10 3 * * *` | `update public.attendance_attempts set latitude = null, longitude = null, accuracy_m = null where outcome <> 'ok' and attempted_at < now() - interval '90 days' (and latitude is not null)` |

- The three are AD-14's complete list (reminders every 5 min; the two daily prunes — `cron.job_run_details` > 7 days; rejected-attempt coordinates > 90 days, AD-26, explicitly left for Epic 19 by 20260928000002's header). The prunes are inline scheduled SQL (the 20260621/20260909 convention — no stored function). The coordinate prune is **idempotent and null-safe** (re-nulling old rows is free; AD-26 keeps coordinates on `outcome = 'ok'` rows forever — the record's dispute value).
- The function is `SECURITY DEFINER SET search_path = public` with the **AD-3 grant triple in the same file** (`REVOKE … FROM PUBLIC, anon, authenticated; GRANT EXECUTE … TO service_role`). The cron runner runs it as a superuser context — pg_cron jobs execute as the scheduling role (postgres), which owns the inserts; the grant triple still ships per convention (it governs who may EXECUTE from SQL surfaces).

**D2 — The reminder function: due facts, per tenant, per the FR-23 timing table.** `attendance_run_reminders()` takes no arguments and returns void. Outer loop: `FOR` over tenants with `attendance_settings.enabled = true AND setup_completed_at IS NOT NULL`, each iteration wrapped in its own inner `BEGIN … EXCEPTION WHEN OTHERS THEN RAISE WARNING …; END` — one tenant's failure never stops the others (AD-14); per-tenant failures surface as a WARNING carrying the tenant id and reminder context (never coordinates — reminders involve none).

Per tenant ("today" and all wall-clock arithmetic = `now() AT TIME ZONE <tenant tz>`; timezone from `tenants.timezone`, the stored IANA name), the function reads **only the same fact tables the TS day-context assemblers read** (`attendance_settings`, `attendance_enrolments`, `attendance_office_assignments` + `attendance_offices` (active) + `attendance_office_rules` covering today, `attendance_weekly_off_defaults`/`_overrides`, `holidays`, `leave_request_days` (active today, state `pending`/`approved`, part full_day/first_half/second_half), `attendance_records` for today, `attendance_day_overrides` (active, `deleted_at IS NULL`)):

- **Tracked** predicate mirrors AD-22/FR-2 including the enable-day grace: enrolment covers today ∩ assignment covers today ∩ covering office not archived ∩ setup completed ∩ enabled ∩ (NOT (enabled_at is today AND enabled_at time is after today's Start time AND no check-in yet)) — an employee skipped by the grace gets no reminder on their enable day.
- **"You haven't checked in" → the employee** when: tracked, working day (weekly-off override or default neither covers today, nor is today a `holidays` row), **no approved full-day leave** covers today (approved or pending **first-half** does not suppress — pending never suppresses, AD-14's approved-only letter), no check-in today (record check-in **or** an active times-override `manual_checkin_at`; an active status-only override short-circuits instead — see the override rule below), and the tenant wall time is **past the day's due instant**, which is:
  - Expected **start + late cut-off** on a normal working day (rule time = `start_minute + late_cutoff_minutes`, the rule row's columns);
  - **Midpoint + late cut-off** on a **first-half** approved-leave day (FR-23's table; midpoint = start + (end − start)/2 truncated to the minute — the same formula `DayContext.midpointMinute` uses).
- **"You haven't checked out" → the employee** when: tracked, **working day** (no reminders on weekly offs or holidays — FR-23's literal consequence), has a check-in today (record or times-override), no check-out today (record checkout or override `manual_checkout_at`), and now ≥ **Expected end + actual late minutes** — `late_minutes = greatest(0, checkin_minute − (start + cutoff))`, the same math `computeLateMinutes` runs (no rule covering → no reminder: no thresholds to be late against). On a **second-half** approved-leave day the due instant is **Midpoint + actual late minutes** (FR-23's alternative arm). This applies to punctual check-ins too (`late = 0` → due at Expected end): FR-23's "…if still not checked out" is the binding condition; the AC's "checked in late" is the example arm, not a gate (fidelity note — the punctual-but-never-checked-out employee is precisely a `checkout_missing` case, and only the late one losing a *shifted* time would punish honesty).
- **Daily not-checked-in summary → the tenant's owners** (users of the tenant with role `owner`), **once per Office per day**: for each active office having tracked employees with a covering rule, when wall time ≥ **Start time + late cut-off**, count the office's tracked employees with no check-in today and no approved full-day leave; `n > 0` → one reminder per owner: "«n» employees haven't checked in at «office»". Owners whose own tracked-employee membership puts them in the counted population are still owners for the summary (the recipient rule and the counted population are independent sets — same as the fake-location fan-out).
- **Pending-leave reminder → the tenant's owners, once per day**, when wall time ≥ **10:00 AM tenant-local** and the tenant has ≥ 1 `pending` leave request: payload carries `pendingCount`. Keyed `…:<workDate>` → at most once per day regardless of how long pendings stay pending.
- **Every insert** follows the shipped fake-location insert shape (`insert into public.notifications (tenant_id, user_id, job_id, event_type, payload, entity_type, entity_id, dedupe_key) values (…) on conflict (dedupe_key) where dedupe_key is not null do nothing`) — the **partial unique index is the dedupe guarantee** (AD-13's "the database guarantees this, so a re-run job never creates duplicates"). `job_id` null; `pushed_at` untouched (NFR-10's outbox marker stays push-side).
- **Payloads are self-contained camelCase** (AD-13/NFR-10): `reminder_checkin` `{ workDate }`; `reminder_checkout` `{ workDate, checkinAt }`; `reminder_not_checked_in` `{ officeName, notCheckedInCount, workDate }`; `pending_leave` `{ pendingCount }`. `entity_type` is `'attendance'` for the three attendance reminders and `'leave'` for the pending-leave reminder; `entity_id` per the FE deep-link targets (attendance → the office id for summaries / null for self-reminders; leave → the screen link is by entity kind; FE mirrors in the Epic 19 FE registry extension).
- **A re-run within the 5-minute window** is free everywhere: every insert carries a `dedupe_key` that embeds tenant + recipient + work_date ([:office_id] owner summaries) — `ON CONFLICT DO NOTHING` absorbs every replay (the AC's database-guaranteed dedupe, in **live-DB key convention**: keys are tenant-prefixed `<tenantId>:<eventType>:<recipientId>:<…>` because the partial unique index is global on `dedupe_key` alone — the 14-2 recipient-prefix ruling reconciles AD-13's short sketch).

**D3 — Registry + event types (extended, never invented per-emitter).** `ATTENDANCE_NOTIFICATION_EVENT` gains exactly four entries, registry-documented with recipients, payloadFields and dedupeKeyShape (the registry is the source of truth; `notification-events.spec.ts` and the FE mirror diff test extend in the same change):

| Event type | Recipient | Dedupe key |
|---|---|---|
| `attendance.reminder_checkin` | A tracked employee, at most once per work_date | `<tenantId>:attendance.reminder_checkin:<recipientId>:<workDate>` |
| `attendance.reminder_checkout` | A tracked employee, at most once per work_date | `<tenantId>:attendance.reminder_checkout:<recipientId>:<workDate>` |
| `attendance.reminder_not_checked_in` | Each tenant owner, at most once per office per work_date | `<tenantId>:attendance.reminder_not_checked_in:<recipientId>:<workDate>:<officeId>` |
| `leave.pending_reminder` | Each tenant owner, at most once per day | `<tenantId>:leave.pending_reminder:<recipientId>:<workDate>` |

These are NFR-10 wave-tagged in the registry: check-in/check-out reminders = **Wave 1** (time-sensitive); owner summary + pending-leave = **Wave 2** (informational). The FE registry mirror and card rendering are the Epic 19 FE stories' work — BE-first is safe because AD-19 renders unknown types as generic cards without touching job UI. **Reminder reminders are the only notifications written outside a NestJS/RLS transaction today — stated honestly:** the pg_cron job is its own transaction scope (each per-tenant sub-block commits independently, so a half-succeeded tenant batch cannot straddle); the realtime broadcast trigger fires on commit as always.

**D4 — NFR-9: reminder metrics via an OTel ObservableGauge over `cron.job_run_details` (resolves spine line 510 — user sign-off point).** `src/telemetry/app-metrics.ts` gains two observable gauges, `attendance.reminder_job.runs` and `attendance.reminder_job.last_run_age_seconds`, computed by an `ObservableCallbackInstrument` whose callback runs the read-only SQL `select status, count(*) … from cron.job_run_details where jobname = 'attendance-run-reminders' and start_time > now() - interval '24 hours' group by status` (plus last finished run's age) through the existing admin/pg client at **export time** (the PeriodicExportingMetricReader already owns the tick; no `@nestjs/schedule`, no `setInterval`, no new run-log table — AD-14's posture and AD-26's "no new infrastructure" both hold). Failed runs also land in `cron.job_run_details` (pg_cron records the failing job's status and error), so Grafana needs nothing else. **Why the gauge wins over a run-log table:** the table already exists and is already pruned to 7 days by this same migration; a second table would double the signal's storage and its own cleanup for the identical data — and the spine's option (a) becomes strictly the smaller change now that the TS-first reality is known.

**D5 — Owner dashboard: `GET /api/v1/attendance/dashboard?officeId=`** — owner only, no idempotency header (AD-6's letter, 18-2 precedent), no query date (FR-24 is **today only**; the tiles are a snapshot of `attendance_today()`). **No new SQL functions** — the read runs `readDayStatusGrid(tx, tenantId, trackedTodayEmployeeIds, today, today)` (the 50×31 budget's read, applied to one day) inside one `withTransaction`, after resolving today's tracked employee set (enrolment ∩ assignment ∩ active office covering today — the exact gate-2 predicate of `attendance_complete_setup`), with the **optional `officeId` filter applied as "today's covering assignment office"** (DTO `@IsUUID` → 422; unknown office id → 200 with zeros + empty lists, never 404 — a filter is not an entity fetch). Upcoming-start-date employees are excluded from every count automatically (the engine marks them `not_tracked` for today — FR-2's rule, consumed not re-implemented).

- **Tiles** (FR-24, all derived from the same grid rows — one source):
  - `tracked`: employees tracked today (grid rows where `ctx.tracked`);
  - `checkedIn`: rows with a check-in instant today (status `in_progress`, `present`, `half_day`, `worked_on_holiday`, or a checked-in `half_day_leave`);
  - `notCheckedIn`: status `not_checked_in_yet`;
  - `late`: rows with `isLate` true (late minutes > 0; never true on off-day statuses — the engine keeps Late null there);
  - `onLeave`: status `leave` or `half_day_leave` (leaveCredit ≥ 0.5 today).
  Documented overlap: a checked-in `half_day_leave` row counts in **both** `checkedIn` and `onLeave` — the tiles are answers to five separate questions, not partitions of tracked (the FE 19-4 tiles add no summing invariant, so none is promised).
- **Flags strip — targeted reads, parity-pinned:** the unresolved past-day flags are NOT fetched via the full grid (a since-enable window has no 62-day bound and no NFR-7 budget); instead two narrow SQL reads inside the same transaction: (a) **Checkout missing** — `attendance_records` with `work_date < today`, check-in set and check-out null, where no active `attendance_day_overrides` row adjudicates the pair (status override, or a times-override with `manual_checkout_at`) — exactly the rows engine rule 8 marks (a times-only override with check-in and no checkout is still missing); (b) **Fake location attempt** — `attendance_attempts` rows with `outcome = 'mocked' AND acknowledged_at IS NULL`, grouped per employee-date with attempt counts. Both shapes clear exactly when the spec says they do: (a) when a correction lands (18-2, engine recomputes live), (b) when the owner acknowledges (18-2's `ackAttempts`, AD-10). **A parity probe in the integration suite runs both the grid (rule-8-derived markers) and the targeted SQL over a seeded window and pins equality** — the same "two engines must not drift" shape 18-1 used for the 16-4 parity probe (the 15-9 lesson; the targeted read exists for perf, and the probe is what keeps it from re-deriving differently).
- Response `{ date, counts: { tracked, checkedIn, notCheckedIn, late, onLeave }, flags: { checkoutMissing: CheckoutMissingRow[], fakeLocationAttempt: FakeLocationRow[] } }` — names resolved from `users` in one extra round-trip per flag read. Flag rows: `{ employeeId, employeeName, workDate, officeName }` (+ `attemptCount` for fake-location), ascending by workDate then name. Unpaged: flags clear as they're handled, the population is tenant-bounded, and the route is one dashboard screen's single load (NFR-7's ≤ 3 s budget is a monthly-view budget — the dashboard's flags read touches only unresolved rows; review flags any need for pagination then).

**D6 — Monthly & self-view: owner `GET /attendance/monthly`, technician `GET /attendance/me/monthly`.** One aggregation implementation, two routes (`src/attendance/monthly-summary.model.ts` — pure; `monthly.ts` service/controller split keeps files ≤ ~300). Query: `from`, `to` (tenant-local `YYYY-MM-DD`), `to ≤ tenant-today`, span ≤ **31 days** (`ATTENDANCE_INVALID_RANGE`, new usage of the 18-x enum entry — a month, and the NFR-7 budget's shape; 422 otherwise; owner `officeId` optional `@IsUUID`). Owner route resolves its employee set: every enrolment covering ANY date of the requested range (so a mid-month joiner still gets their covered dates), the grid read over `employeeIds × [from, to]`, then aggregates.

- **One summary row per Tracked employee** (FR-25), fields all computed from the same grid rows — **no separate computation, no second implementation of anything**:
  `daysWorked` = Σ `daysWorked` (FR-11 credits — present 1, half_day 0.5, half-day-leave earned half 0.5, checkout_missing 0); `halfDays` = count status `half_day`; `lateCount` = count `isLate`; `leave` = Σ `leaveCredit` (half days as 0.5); `weeklyOffs` = count `weekly_off`; `holidays` = count `holiday`; `workedOnHoliday` = Σ `workedOnHolidayCredit`; `absent` = count `absent`; `checkoutMissing` = count rows with the `checkout_missing` marker (rule 8 — a later correction flips it live, FR-25's contract).
  Row keys: `{ employeeId, employeeName, officeId, officeName, summary }`; office = the assignment covering **today** (the roster's current office — the filter predicate; a past-month office move is out of monthly scope, the day detail drill-down shows per-date offices). Response `{ from, to, employees: [...] }` — no pagination (bounded by the tenant's tracked roster; NFR-7's 50-employee month loads through the grid's batched reads, its p95 pinned in the integration suite exactly as 18-x did).
- **Self view** — identity from the JWT only (`@CurrentUser()`), `requireAttendanceReadAccess` gate (AD-17: `none` → 403 `ATTENDANCE_NOT_TRACKED`; `history_only` reads honestly return the own-records rows — the 18-x me-route precedent). `GET /attendance/me/monthly?from=&to=` returns the **same summary shape for the caller alone** (server-side scoping, not UI hiding — FR-26's testable line), plus:
  - `weeklyOffs`: the employee's **today-effective** weekly-off weekdays as a flat `number[]` (amended per review decision 2026-09-29: the flat shape cannot carry per-date variation, so "across the range" was imprecise — the calendar's per-date grading still rides the grid rows; defaults + the override **replacing** them **for today**, the `pickWeeklyOffDays` contract, imported, not re-derived);
  - `upcomingHolidays`: tenant holidays from today, next 10, `{ holidayDate, holidayName }` (read from the same facts read the engine uses; no owner-gating on a read re-invented);
  - leave history is **NOT duplicated** — `GET /attendance/me/leave` (17-3) already serves it paginated; me/monthly returns none.
- **FR-11 parity is structural, then pinned:** owner-monthly and me-monthly call the **same aggregation function over the same grid rows** — different row-level filtering only (owner: many employees; me: the JWT's employee only). Integration probe: seed a month, read both routes, compare summaries element-wise — the "Days worked: X so far" total (19-6's running total) is the same number the owner sees (FR-11).
- `GET /attendance/monthly` (owner) employee rows include **history-only and disabled employees with any tracked day in the range** (FR-28: "the Owner can still see it in the monthly view and summaries"); dates after disable read `not_tracked` naturally and drop out of every count — while the me route for a history-only employee returns their own data unchanged.

**D7 — 18-5: office rule mandatory with a prefilled default (fenzo-app + fenzit-be).**

- **fenzo-app** (tiny): `emptyOfficeForm()` and the `formFromDetail()` no-rule fallback prefill `startTime: '09:30'`, `endTime: '18:30'` alongside the existing cutoff-15/8/4 defaults (the 15-3 BE `OFFICE_*_DEFAULT` constants are the hours/cutoff anchors; the times get FE-local default consts mirrored in the DTO constants). Placeholders, mandatory DTO, cross-field validators and the wizard's drift gate (`liveOfficesMissingRule`) are untouched — the change is the two seed values, so an owner tapping through Add-office ships a valid rule by default and can never blank it silently.
- **fenzit-be** (defence in depth): `attendance_complete_setup` gains **gate 3 — every active office must have a rule covering today** (`not exists (active office without a covering rule)` → PT422 hint `ATTENDANCE_SETUP_INCOMPLETE`; review decision 2026-09-29 replaced the terse "tenant % has an office without timings" with an **owner-friendly message** that tells the owner WHY and what to do: "attendance setup could not be completed: office «%» has no timing rule covering today. Add a rule for this office, then try again." — gates 1–2 got the same owner-friendly treatment; the terse tenant-id text lives on only in the SQL `detail`). Migration `20260929000005_attendance_complete_setup_rule_gate.sql` (one concern per file; the 20260927000008 re-create precedent). This closes the sanctioned-path gap at the moment tracking turns on, regardless of which client completes the wizard; the read path's permissive arm + `logger.warn` (18-1 D2) stays as the drift detector after completion.

**D8 — No notifications beyond FR-23's four, no events, no route sprawl — verified, not assumed.** The registry grows by exactly the four D3 entries; FR-22's closed list gains nothing else. The only routes added sit under the spine's pre-approved `dashboard`, `monthly`, `me/*` allowlist words — the Routes row is amended by this spec only to spell the exact three additions (`attendance/dashboard`, `attendance/monthly`, `attendance/me/monthly` alongside `me`), mirroring the 18-1 Routes-row amendment pattern. `docs/api-contracts.md` gains all three route rows + the registry/keys in the same change.

## 3. API contract summary (full text lands in `docs/api-contracts.md` in the same change)

| Route | Role | Success | Errors |
|---|---|---|---|
| `GET /api/v1/attendance/dashboard?officeId=` | owner | 200 `{ date, counts: { tracked, checkedIn, notCheckedIn, late, onLeave }, flags: { checkoutMissing[], fakeLocationAttempt[] } }` | 422 `VALIDATION_ERROR` (malformed officeId); 403 `FORBIDDEN` (technician) |
| `GET /api/v1/attendance/monthly?from=&to=&officeId=` | owner | 200 `{ from, to, employees: [{ employeeId, employeeName, officeId, officeName, summary }] }` | 422 `ATTENDANCE_INVALID_RANGE`/`VALIDATION_ERROR` |
| `GET /api/v1/attendance/me/monthly?from=&to=` | technician | 200 `{ from, to, summary, weeklyOffs, upcomingHolidays }` | 403 `ATTENDANCE_NOT_TRACKED` (access `none`); 422 `ATTENDANCE_INVALID_RANGE`/`VALIDATION_ERROR` |
| — no new write routes; `attendance_complete_setup` behaviour (gate 3) is a DB-internal change | — | — | — |

`monthly.summary` keys (shared owner/me shape): `{ daysWorked, halfDays, lateCount, leave, weeklyOffs, holidays, workedOnHoliday, absent, checkoutMissing }` (FR-25's field list verbatim). Swagger decorators per the 15-2/17-2/18-1 house pattern; every response model gets a spec file (house rule).

## 4. Code layout (files ≤ ~300 lines, house structure)

```
supabase/migrations/
  20260929000004_attendance_run_reminders.sql           # fn + 3 cron jobs (AD-3 triple in-file) ✓ applied
  20260929000005_attendance_complete_setup_rule_gate.sql # 18-5 gate 3 ✓ applied
src/attendance/
  notification-events.ts    # (existing registry) + the 4 reminder entries (AD-13) ✓
  reminder-metrics.ts       # NFR-9 binder: registers app-metrics' query seam from onModuleInit
                            #   (REPLACES the planned reminders.model.ts — no due-instant math
                            #   exists in TS; the DB function owns the timing, the gauges only
                            #   read cron.job_run_details)
  monthly-summary.model.ts  # pure: per-employee aggregation over DayGridRow[] (owner + me share it)
  monthly.ts                # MonthlyService (owner + me reads over readDayStatusGrid; range gates)
  monthly.controller.ts     # @Controller('attendance') monthly + me/monthly routes
  monthly-response.model.ts
  dashboard.ts              # DashboardService (tiles over the engine grid; flags targeted reads)
  dashboard.controller.ts   # @Controller('attendance') dashboard route
  dashboard-response.model.ts
  dto/monthly-query.dto.ts; dto/dashboard-query.dto.ts
src/telemetry/app-metrics.ts  # two ObservableGauges reading cron.job_run_details (D4) ✓
src/common/pg/pg-pool.factory.ts  # hardening (user's pool-pattern check): connectionTimeoutMillis
                                  #   10 s + TCP keepAlive — survives NAT-dropped idle connections
                                  #   between the 5-min cron ticks
docs/api-contracts.md      # the three routes + the reminder registry/keys (same change) ✓
test/attendance-dashboard.e2e-spec.ts; test/attendance-monthly.e2e-spec.ts  # HTTP boundary (post-confirmation)
test/integration/attendance-reminders.integration.spec.ts                   # real DB (post-confirmation)
```

**Change log:**
- 2026-09-29 — implementation pass: migrations 04+05 applied via Supabase MCP; registry
  extended (4 events + 4 entries, wave tags); NestJS surface built and `nest build` clean;
  docs/api-contracts.md updated. §4 layout note: `reminders.model.ts` (planned pure
  due-instant math) replaced by `reminder-metrics.ts` — the reminder timing lives wholly in
  the DB function (19-1 is SQL-side by AD-14); the TS side only wires the NFR-9 gauges.
  Flags read: the targeted checkout-missing SQL mirrors rule 8 fully (effectiveInstants
  per-field substitution incl. override-only days, and rule 2's tracked gate) so the §6
  parity probe can hold; the officeId filter scopes flags by TODAY's covering assignment
  office (consistent with the tiles' predicate).
- 2026-09-29 — code-review pass (BMAD `/bmad-code-review`, group A: migrations + src)
  amendments — all five decisions resolved by the user, all patches applied ("apply every
  patch"):
  - **D1 (cross-midnight due instants):** declared OUT OF SCOPE — every due minute is a
    wall-minute of ONE tenant-local day; a schedule ending past 24:00 would mis-fire
    against the wrong half of the day. Scope note pinned above Arm 1 in migration 04.
  - **D2 (deep-link pair shapes):** the SHIPPED shapes stand — self-reminders ride
    `('attendance', employee_id)` per AD-13, pending-leave rides the all-NULL pair (the
    `notifications_entity_pair_chk` CHECK requires either both or neither). D2's bullet
    "entity_id … null for self-reminders / entity_type `'leave'`" above is corrected by
    this note — the registry documentation is the source of truth.
  - **D3 (gate messages):** gates 1–3 of `attendance_complete_setup` rewritten to
    owner-friendly messages (gate 3 names the offending office and the remedy; gates 1–2
    same treatment; tenant ids go only in the SQL `detail`). Migration 05 edited in
    place and re-applied live (drift-checked by function-hash).
  - **D4 (`weeklyOffs`):** D6's wording amended above — the shipped today-effective pick
    is the contract; the flat shape cannot carry per-date variation.
  - **D5 (unbounded reads):** shipped unbounded (bounded-shape option was estimated
    1.5–2 h and judged premature pre-launch; the tenant-bounded roster is the implicit
    cap) — risk noted in `docs/api-contracts.md`.
  - Patch items applied alongside: flag reads ride EFFECTIVE instants + the settings
    gate; checkedIn tile's half_day_leave gate; enrolment dedupe in the reminder facts
    (oldest covering period wins — matches the TS pick); gauge SQL contract (counts on
    the 24-hour window, age on the 7-day prune-bounded window, never-run job → NO
    series) + logged catch; HTTP-boundary e2e for the three routes (roles/pipe/DTO);
    gate-3 rejection probe with the exact message; seeded weeklyOffs/holiday probe;
    gauge observation-path spec; `@IsUUID` 'all'; response-model spec files; trailing
    newlines; model-spec fixtures stamped from the row's date.

## 5. Ripple effects on existing behaviour (must verify, not assume)

| Surface | Risk | Verification |
|---|---|---|
| `notifications` inserts (jobs, leave RPCs, fake-location) | a global dedupe index collides with new keys | keys are tenant-prefixed like every existing writer; integration probe inserts a re-run and asserts row count unchanged |
| Realtime broadcast on `notifications` | cron-function inserts broadcast as system events | the AFTER INSERT trigger fires per commit; e2e pin reads the row via the REST list |
| `readDayStatusGrid` (18-x) | dashboard/me-monthly reuse drifting the read | no change to `day-status.read.ts`; aggregation imports it |
| me/summary (16-4) todayRecord | untouched | contract unchanged; parity already pinned in 18-x suite |
| `attendance_complete_setup` (15-2/15-7) | new gate 3 rejection | e2e/integration: completion fails PT422 while any active office lacks a covering rule; existing gates 1/2 unchanged |
| `cron.job_run_details` prune | pg_cron's own diagnostics | prune runs daily; gauge handles a briefly-empty window |
| Existing pg_cron jobs | schedule drift | unschedule-then-schedule only for the new names; the three existing jobs untouched |
| Tenants with `attendance_settings.enabled = false` or setup incomplete | no reminders, still pruned | reminders loop skips; coordinate prune is tenant-agnostic (AD-26) |

## 6. Test plan (written AFTER the user confirms the walkthrough — never upfront)

QA mindset per the house rule. For 19-1 the unit of truth is TIME plus TENANT isolation — the integration spec drives pg_cron's *function* directly (the schedule is a one-row pin): reminder firing exactly at/before the due instant and not one step before (start+cutoff; midpoint+cutoff on first-half leave; end+0/actual-late on working days; midpoint+late on second-half leave; 10:00 pending-leave boundary), the four dedupe keys' conflict absorption (re-run twice → row count identical), working-day/untracked/enable-day-grace absence arms, an approved full-day leave suppressing while **pending** full-day leave does NOT, one tenant's failure not blocking the next (a corrupted-tenant seed; the others still remind), `ON CONFLICT` against a pre-seeded stale row, the coordinate prune (rejected row > 90 days → lat/lng/accuracy null; `ok` row kept; 89-day boundary kept), `job_run_details` prune at the 7-day boundary, and the parity probe — for a seeded tenant-date set, the reminder function's due-facts predicate agrees with `readDayStatusGrid`+`computeDayStatus` (tracked, off-day, leave-state and check-in/out presence per row; the drift-closure for AD-22's TS/SQL split). For 19-2/19-3: office filter zeroes other offices; upcoming-start exclusions from every count; flags clear via a correction and via `acknowledge`; counts recomputed only from today's rows; monthly across a mid-month joiner/disabler; the FR-11 owner↔me totals parity probe; a future-`to` 422; span 31 vs 32; `history_only` me access reading past data only; foreign-employee impossible-by-construction (JWT identity); the 50×31 monthly perf probe; malformed UUID/date → 422s.

## 7. Out of scope (explicit)

- The Epic 19 FE stories (19-4..19-6) — dashboard/monthly/self-view UI, the FE registry mirror, `components/ui/Skeleton` generalisation.
- Push delivery (NFR-10's outbox marker stays un-written), a run-log metrics table (rejected — D4), materialisation (AD-10's contingency), any new write route.
- Removal of technicians (FR-28's future feature — the reminders' recipient predicate already excludes removed employees through the tracked predicate's enrolment/assignment gates).
- Leave quotas, month lock, export, per-office timezone, multiple shifts (PRD §7.2).
- Reminders beyond FR-23's four-row table (SM-C2 caps reminder volume at exactly this set).

## 8. Adversarial spec review (BMAD) — 2026-09-29, 4 lenses, all patches applied

**A. Ambiguity/completeness lens**
1. **[Patch applied — user ratification point] Punctual check-in checkout-reminder timing.** The FR-23 formula ("Expected end + actual minutes late … if still not checked out") vs the AC's "checked in late and hasn't checked out by Expected end + their actual late minutes" — read literally, the AC would never remind a punctual employee who forgot checkout (exactly the `checkout_missing` population). D2 resolves for FR-23: due at Expected end + actual late minutes, `late = 0` for punctual → due at Expected end. **Needs user sign-off.**
2. **[Resolved] Dedupe-key collision audit:** `reminder_checkin`/`reminder_checkout` keys omit officeId because an employee has at most one covering-office assignment for today (EXCLUDE-constrained) — no collision; `reminder_not_checked_in` includes officeId as FR-23 dedupes per office. No other pairing collides and cross-tenant isolation holds via the tenant prefix (the index is global).
3. **[Pinned] Summary vs first-half leave:** an employee on approved first-half leave IS counted in the owner summary at Start + cut-off (they factually haven't checked in by then); their own reminder just fires later (midpoint + cutoff). FR-23's summary sentence makes no leave exception — stated in D2.
4. **[Pinned] Timezone:** verified — `tenants.timezone` is `TEXT NOT NULL DEFAULT 'Asia/Kolkata'` with a BEFORE INSERT/UPDATE trigger validating against `pg_timezone_names` (20260926000001), and the `attendance_today(p_tenant_id)` helper already exists; the function reuses both, no DST branch needed (single-tenant-tz model, no DST tenants pre-launch).

**B. Consistency-with-sources lens**
5. **[Patch applied] D3's registry entries verified against the live registry shape** (`notification-events.ts`): every existing entry's dedupeKeyShape is tenant-prefixed; the four new keys match that convention, and the `leave.pending_reminder` type follows the `leave.` prefix family with `LEAVE_ENTITY_TYPE`. The registry's own header ("every later … 19 reminders") is honoured.
6. **[Patch applied] Error codes verified present in the enum:** `ATTENDANCE_SETUP_INCOMPLETE` (line 29), `ATTENDANCE_NOT_TRACKED` (line 50), `ATTENDANCE_INVALID_RANGE` (line 67) — no enum additions needed by this spec.
7. **[Noted] AD-22 literal letter vs shipped TS reality:** the carried-deviation header states it up front (no SQL `attendance_day_statuses`/`attendance_day_context`; 19-2/19-3 are TS over `readDayStatusGrid`; 19-1's `attendance_run_reminders()` re-derives the fact subset in SQL with a parity probe). Any reader landing on the stale spine wording is redirected by this spec.
8. **[Resolved] "No new tables" tension:** the reminders story adds zero tables; the AD-26 prunes and NFR-9's gauge both run off existing objects (`attendance_attempts`, `cron.job_run_details`).

**C. Testability lens**
9. **[Pinned] Boundary set for the reminder arms is enumerable:** every timing rule has a concrete due instant (start+cutoff; midpoint+cutoff; end+late; midpoint+late; 10:00) — §6 names the at-instant/not-before tests for each, plus the dedupe re-run and tenant-failure isolation arms.
10. **[Pinned] Parity probe is executable:** `readDayStatusGrid` + `computeDayStatus` are plain TS — the integration spec can seed tenants, call the SQL function, call the TS engine over the same facts, and compare per-row predicates. Drift between the SQL reminder predicate and the TS day-status engine is thereby caught, not assumed.
11. **[Resolved] Pending-leave reminder dedupes on `<workDate>`,** not on the pending set: a request arriving after 10:00 stays silent until tomorrow (one per day), matching FR-23's "once a day" — a deliberate consequence a tester must assert (late-arriving requests do not back-fill a same-day reminder).

**D. Implementability lens**
12. **[Patched] Gauge frequency cost (NFR-9):** an ObservableGauge callback runs one tiny SELECT per export tick (default 60 s reader) against `cron.job_run_details` (~288 rows/day, 7-day-pruned) — stated in D4 so no reviewer rediscovers it; no caching needed. If the reader interval is changed later, the query stays O(tiny).
13. **[Resolved] Race within the 5-min window:** a leave approval or check-in landing between the function's fact read and its insert may fire one reminder a stale-fact snapshot implied. This is AD-14's sanctioned up-to-5-min lag, and the dedupe key prevents any follow-up run from repeating it — accepted, documented in D2.
14. **[Pinned] Gate 3's date basis:** gate 3 tests "covering today" = `attendance_today(p_tenant_id)` — the same tenant-local basis as gates 1/2, so a near-midnight completion never flips days mid-gate.
15. **[Resolved] `formFromDetail` fallback prefill:** only the no-rule fallback gets the 09:30/18:30 defaults; an explicit rule keeps its own values — the two-line change cannot clobber owner-entered data.
### Review Findings — 2026-09-29 (BMAD `/bmad-code-review`, group A: migrations + src)

- [x] [Review][Decision] Cross-midnight due instants never fire — RESOLVED (D1, user): declared OUT OF SCOPE; scope note pinned above Arm 1 in migration 04
- [x] [Review][Decision] Deep-link pair shapes contradict D2's letter and are unsatisfiable under `notifications_entity_pair_chk` — RESOLVED (D2, user): shipped shapes stand; D2's letter corrected by note in the change log
- [x] [Review][Decision] Gate-3 exception message — RESOLVED (D3, user): owner-friendly messages naming the offending office + the fix; gates 1–2 same treatment; migration 05 edited in place, re-applied live, drift-checked
- [x] [Review][Decision] `weeklyOffs` is the today-effective weekday set, not D6's "across the range" — RESOLVED (D4, user): keep today-effective; D6's wording amended
- [x] [Review][Decision] Unbounded reads — RESOLVED (D5, user): shipped unbounded (bounded option 1.5–2 h judged premature pre-launch); risk noted in `docs/api-contracts.md`
- [x] [Review][Patch] Checkout-missing flag read gates on raw instants, not effective ones — applied [src/attendance/dashboard-flags.ts:88-110]
- [x] [Review][Patch] Flag reads omit the settings gate (enabled + setup_completed_at) — applied [src/attendance/dashboard-flags.ts:113-127]
- [x] [Review][Patch] checkedIn tile over-counts half_day_leave with no check-in — applied; the tile gates half_day_leave rows on an EFFECTIVE check-in [src/attendance/dashboard.ts:31-37,91]
- [x] [Review][Patch] Arm-3 office-summary count inflated by overlapping enrolment rows — applied (dedupe: oldest covering period wins, the TS pick) [supabase/migrations/20260929000004_attendance_run_reminders.sql]
- [x] [Review][Patch] Gauge SQL always returns one 0/0/NULL row (never-run job exports a wrong-zero series) — applied (`having max(d.end_time) is not null`; live re-applied) [src/telemetry/app-metrics.ts:98-105]
- [x] [Review][Patch] Age gauge's 24-hour window drops/shrinks the last run — applied (age rides the 7-day prune-bounded window) [src/telemetry/app-metrics.ts:98-105]
- [x] [Review][Patch] Empty gauge-read catch logs nothing though the comment claims log visibility — applied (logger.warn) [src/telemetry/app-metrics.ts:125-129]
- [x] [Review][Patch] No HTTP-boundary test executes the three new routes (roles/pipe/DTO 422s) — applied (test/attendance-reads.e2e-spec.ts) [src/attendance/dashboard.controller.ts, monthly.controller.ts]
- [x] [Review][Patch] Gate-3 rejection direction untested (no covering rule → PT422) — applied (probe pins code + hint + the exact D3 message) [test/integration/attendance-enrolments.integration.spec.ts]
- [x] [Review][Patch] weeklyOffs/upcomingHolidays only asserted empty (no seeded assertion) — applied (probe seeds an override + a holiday and pins both) [test/integration/attendance-dashboard.integration.spec.ts]
- [x] [Review][Patch] Gauge observation path (batch callback → observers) never executed by any test — applied (src/telemetry/app-metrics.spec.ts) [src/telemetry/app-metrics.ts]
- [x] [Review][Patch] `p_now` signature amendment under-recorded in the spec change log — applied (this change-log section records it)
- [x] [Review][Patch] @IsUUID('4') stricter than the spec's @IsUUID — applied ('all') [src/attendance/dto/dashboard-query.dto.ts:16, monthly-query.dto.ts:29]
- [x] [Review][Patch] Response models shipped with no spec files (spec §3 rule) — applied (dashboard-response.model.spec.ts, monthly-response.model.spec.ts) [src/attendance/dashboard-response.model.ts, monthly-response.model.ts]
- [x] [Review][Patch] Missing trailing newline on every new file in the change — applied (all files end with a newline) [multiple]
- [x] [Review][Patch] monthly-summary.model.spec fixtures hard-code record work_date while row date varies — applied (fixtures stamped from the row's derived date) [src/attendance/monthly-summary.model.spec.ts]
- [x] [Review][Defer] tenants.timezone write-side lacks IANA validation — invalid stored tz reaches the dashboard read and 500s [src/attendance/dashboard-flags.ts:201-213] — deferred, pre-existing
