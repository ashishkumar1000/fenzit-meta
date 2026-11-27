# PLAN — Holidays console redesign (per-office holidays + 4 Stitch screens)

Spec: `_bmad-output/specs/spec-holidays-console-redesign-2026-11-26/SPEC.md` (+ `design-mapping.md`)
Date: 2026-11-26 · Owner answers folded in (full per-office / no email checkbox / real flyout data / Edit Date + Print + Export + descriptions)

**Layer ownership:** BE (`fenzit-be`) owns holiday semantics — applicability, collision, notification, day-status correctness. Web (`fenzit-web`) renders and never filters applicability client-side. DB migration is additive DDL only. **Order: BE first (merge/deploy first — additive, existing web+mobile keep working), then web.**

## Part A — Backend (fenzit-be)

### A1. Migration `supabase/migrations/20261126HHMMSS_holiday_office_scope.sql` (DDL only)
Header comment: "DDL only — zero functions and zero triggers; deny-by-default RLS with service_role grants."
1. `alter table public.holidays add column description text` (nullable; length capped in DTO).
2. `alter table public.holidays add column scope text not null default 'all'` + `check (scope in ('all','offices'))`. Existing rows keep working as `all`.
3. `create table public.holiday_offices (holiday_id uuid not null references public.holidays(id) on delete cascade, office_id uuid not null, tenant_id uuid not null references public.tenants(id) on delete cascade, primary key (holiday_id, office_id), created_at/updated_at timestamptz not null default now())` — with **composite FK** `(office_id, tenant_id) references public.attendance_offices (id, tenant_id)` after `alter table public.attendance_offices add constraint attendance_offices_id_tenant_id_key unique (id, tenant_id)` (house cross-tenant hardening — a plain `office_id` FK would let tenant A attach tenant B's office). No new trigger; holiday_offices rows are immutable after write (rewritten, never updated).
4. Index `holiday_offices_office_idx (office_id)`.
5. Deny-by-default RLS on `holiday_offices` + `grant … to service_role` (house pattern).
- Unique `(tenant_id, holiday_date)` on holidays **stays** → one holiday per date, 409 on collision (design is one-holiday-per-date).
- Apply via Supabase MCP only after the SQL is part of the reviewed diff (prod DB — additive, pre-launch).
- Legacy RPCs (`attendance_add_holiday`, `attendance_update_holiday`, `attendance_remove_holiday`) stay in place but become dead code — never called. NOT dropped (avoid touching PL/pgSQL objects). Ledger note.

### A2. `holidays.service.ts` rewrite — RPCs out, direct writes in
- **List** (existing `GET /attendance/holidays`, backward-compatible): rows gain `description`, `scope`, `officeIds: string[]` (batched second read of `holiday_offices`); existing `id/date/name` consumers (mobile, web chips page, web LeaveCalendarTab) unaffected.
- **New** `GET /attendance/holidays/overview?year=` — one call for both console pages: `{ holidays: […] (with offices), offices: [{id, name, staffCount}], unassignedCount }`. `staffCount` = **new** `select office_id, count(distinct e.employee_id)` join over enrolments ∧ assignments (pattern from `dashboard.ts readTrackedTodayEmployeeIds`, but grouped — that helper returns a flat id list and drops office-less employees, so it cannot yield unassigned counts) + an anti-join for `unassignedCount`. **Anchor: today** (headcount is current staff).
- **Impact** `GET /attendance/holidays/impact?date=` (exists) **extended additively** — keeps `date` and `affectedEmployees` exactly as shipped (the mobile app's add-sheet "overlaps approved leave" banner reads `res.data.affectedEmployees`), ADDS `holiday` (**null when the date has no holiday** — the app queries arbitrary candidate dates), `approvedLeaveCount`, `trackedCount`, `perOffice: [{officeId, name, staffCount, closed}]`, `unassignedCount`. Offices-closed set = holiday scope/office ids; per-office counts from assignments **covering the queried date**; approved leave from `leave_request_days.leave_date = date AND state='approved'` (existing seam).
- **Create** `POST` — body `{date, name, description?, scope?, officeIds?}`; **`scope` optional, defaults `'all'`** (mobile posts `{date, name}` only — a required scope would 400 every shipped app build). Validators: name ≤ 80, description ≤ 280, `scope in (all,offices)`, officeIds required non-empty iff scope=offices, all uuids ∈ tenant. `pgPool.withTransaction`: insert holiday + join rows; unique violation (23505) → 409 `ATTENDANCE_HOLIDAY_TAKEN`. Future-dated → notify (below).
- **Update** `PATCH /:id` — all fields incl. `date` (drops the old rejectDateKey 422 contract; mobile sends `{name}` only and keeps the date read-only, so nothing breaks); guarded UPDATE + join-row rewrite in one transaction; target date taken → 409; future-dated edits → notify.
- **Delete** `DELETE /:id` — 204; future-dated → office-scoped removed notification.
- **Notification fan-out (TS, replacing the RPC):** insert outbox rows into `public.notifications` (mechanism of the live RPC) — recipients = enrolled ∧ office-assigned with `a.valid @> <holiday date>` ∧ office not archived (`archived_at is null`), INNER-JOIN semantics identical to today's RPC; scope=offices filters to `a.office_id ∈ officeIds`. Gate on `attendance_settings.setup_completed_at is not null and enabled`. Payload `{holidayName, holidayDate}`, entity_type `'attendance'`, entity_id = holiday id, dedupe_key `<tenantId>:<event>:<recipientId>:<holidayId>` with `on conflict (dedupe_key) where dedupe_key is not null do nothing` (partial-unique-index format; TS writer precedent `check-in-out.repository.ts:217-219`); push sweep + `pushCopyForEvent` already render `attendance.holiday_added/removed`. Office-less enrolled employees get nothing (unchanged behaviour, deliberate).
- DTOs in `dto/holiday.dto.ts`; error mapping keeps existing codes. No idempotency interceptor (AD-6 unchanged; unique constraint is the retried-add guard).

### A3. Per-office day-status seam (the correctness change — FOUR direct read seams + leave facts)
Every direct reader of `public.holidays` must apply the same per-employee predicate: holiday applies iff `scope='all'` OR the employee's covering `attendance_office_assignments` office ∈ that holiday's `holiday_offices`.
- `src/attendance/day-context.read.ts` single-date holiday read: fetch `scope` + office ids and keep the holiday only if covered (assignment already read for office rules in the same `Promise.all` pass — reuse it, no extra round-trip).
- `src/common/day-status/grid-reader.ts` range read: holiday map becomes per-employee — load holiday rows (with office ids) for the range + the batch's covering assignments, filter in JS; keep the batched shape (no N+1).
- `src/attendance/monthly.ts` next-10-upcoming employee card: filter holidays by the employee's current assignment (needs an added assignment read).
- `src/attendance/me-attendance.service.ts` `readHolidayName` (technician today-card facts): the access row already carries `office_id` — keep the name only when scope='all' or `office_id ∈ holiday_offices`.
- **`src/attendance/leave.repository.ts` `readSpanFacts` / `readPageSpanFacts`** — these read `public.holidays` DIRECTLY (not the grid) to classify span days as working/weekly_off/holiday, feeding leave-apply validation and debit math (`leave.service.ts`, `leave-balance.service.ts`): apply the same per-employee filter in their existing batched shape (they already batch-load per-employee overrides — load covering assignments + `holiday_offices` for the range, filter in JS, no N+1).
- Payroll LOP and reports DO consume day statuses via `readDayStatusGrid` → inherit automatically once grid-reader is scoped (verify via existing suites).

### A4. Tests
- Existing `holidays.controller.spec.ts` / `holidays.service.spec.ts` / `attendance.e2e-spec.ts` holiday cases updated to the new contract (suite must stay green — that's implementation, not new tests). The date-immutability 422 cases are REWRITTEN, not weakened — the requirement itself is reversed by CAP-2 (owner-approved Edit Date).
- New specs named now, written AFTER owner confirms behaviour (test-timing rule): service-level per-office scoping (scope-all / scoped / office-less employee), create-transaction rollback, 409 collisions, impact counts.
- RLS isolation integration spec unaffected (no policy change) — run once anyway.

## Part B — Web (fenzit-web)

### B1. Data layer
- `companyApi.ts`: extend `HolidayRow` → `{id, date, name, description, scope, officeIds}`; add `fetchHolidaysOverview(token, year)`, `fetchHolidayImpact(token, date)`, `createHoliday`, `updateHoliday`, `deleteHoliday` (apiFetch house wrapper).
- `adminBrowseLoaders.ts`: `adminHolidaysLoader` reads `?year=` + `?month=` (URL state), fetches overview; new `adminHolidayScheduleLoader` (same data, schedule route); `adminHolidaysAction` handling create/update/delete via `withActionError` (house pattern; dialogs post through `useFetcher`).

### B2. Routes + nav
- `routes.tsx`: rework `company/holidays` page component; add a FLAT SIBLING route `company/holidays/schedule` (own lazy page + loader — admin routes are flat siblings; a nested child would need an `<Outlet/>` in AdminHolidaysPage). `shouldRevalidate` only skips refetch for client-side month paging (year changes refetch).
- Nav stays at its current position (Jobs → Holidays → Leave); `PAGES_WITH_OWN_HEADER` gains both paths (pages draw their own design headers); blurbs/title updated.

### B3. Page components (each ≤300 lines + CSS module)
- `AdminHolidaysPage` rework: year switcher pills (prev / current "Current" / next), month calendar card (Sunday-first grid, holiday cells = dot + name chip, `< Today >` nav, legend, IST footnote; **any date cell click → modal** — add mode empty, edit mode pre-filled), upcoming-banner (next holiday, "IN N DAYS"), upcoming list (Edit/Remove inline), past-holidays archive chips, "Total Paid Holidays — N Days Off" stat, "Long Weekend Breaks" card (NEW `holidaysMath.ts` modelled on `leaveDateMath.ts` — Fri/Mon-adjacent rule; "3 Days Off" chips).
- `HolidayModal` (native `<dialog>` + `JobSettingsDialog.module.css` pattern): name*, description, classification static card ("Official Company Holiday — Standard fully paid leave"), date* (istDateInput + weekday/Full Day readout), office applicability chips (All Offices = scope all; per-office multi-select; "N offices selected" counter). No email checkbox.
- `HolidaysSchedulePage`: stats row, office dropdown + month chips filters (client-side), month-grouped table (name+description, date-box + weekday, impact tag via holidaysMath, office names, headcount, edit pencil), branch office coverage bars, footer count; Print = `window.print()`; Export Calendar = generated `.ics` blob download (VCALENDAR with each holiday as an all-day event); **row click → inspector sidebar**.
- `HolidayInspectorSidebar` (right drawer, dimmed page, like LeaveDayModal panel pattern): top row status + Edit Date + close; long date + name chip + "Day off for …"; description card; Team Attendance & Leave progress (approvedLeaveCount/trackedCount from impact endpoint, fetched on open); offices-closed chips with staff counts + "Work from Home staff (N)" chip when unassignedCount > 0; next-upcoming-holiday row (click switches inspector to that date); footer Delete Holiday / Edit Holiday Details. Delete asks for confirm (dialog).

### B4. Token/copy fidelity
- Colours from `src/styles/tokens.css` (holiday status colours exist); no Material icon font — existing glyphs; en-IN/IST date formatting via existing `format.ts` helpers; "Employee" terminology; no emoji from the mock.

## Part C — Verification & gates
1. BE suites green (`bunx jest` for specs; e2e known time-bomb — only holiday suites judged).
2. Local run: BE (`bun run start:dev`) + web Vite 5173 proxying local BE; `.env.local` restored to live after the gate (standing gotcha).
3. Inbuilt browser walkthrough: create scoped holiday → calendar cell → edit via modal → schedule filters → inspector (real counts) → .ics → print preview.
4. **Owner inspection gate on localhost preview** — review/testing/commit only on explicit yes.
5. New tests (A4 + web page/loader tests) after owner confirms; then `/bmad-code-review` → triage → commit (BE first, then web; consent-gated).

## Deliberate cuts (ledgered, not silently dropped)
- Legacy holiday RPCs left in place unused (dropping = touching PL/pgSQL objects; a later cleanup story can `drop function`).
- **Attendance reminders stay tenant-wide:** the reminder PL/pgSQL (`attendance_run_reminders*`, roles-rewrite SQL) suppresses reminders whenever ANY holiday exists on the date — a one-office scoped holiday will silence reminders tenant-wide until that SQL is office-scoped in a later story (cannot be fixed here without authoring PL/pgSQL, which is banned).
- Mobile app holiday screens unchanged (additive BE responses keep them working — impact keeps `date`/`affectedEmployees`, create keeps `{date,name}` valid); they will show tenant-wide wording only until a mobile story.
- Long-weekend math is the design's Fri/Mon rule client-side; weekly-off-aware computation would need BE support — not in this story.

## Plan-review record
Adversarial review 2026-11-26 (fresh-context reviewer, code-verified): 12 findings — 3 P1 (leave-repository direct holidays reader; impact response breaking `affectedEmployees`; POST `scope` breaking mobile create), 4 P2 (me-attendance reader; reminder SQL tenant-wide gate → ledger; fan-out under-specified; composite-FK hardening), 5 P3 (overview query shape; holidaysMath wording; route sibling; impact `holiday` nullable; test-timing note). **All 12 accepted** — 10 folded as plan patches above, 2 as ledger entries (reminders, mobile wording). Verdict after folding: PLAN READY.
