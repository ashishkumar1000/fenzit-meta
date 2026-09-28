# Spec — Stories 16-1 & 16-2: Check-in & Check-out (Backend)

- **Stories:** 16-1 (check-in, day-context helper, attempt logging) + 16-2 (check-out) — done together in one pass, one review, one commit (user decision, 2026-09-28).
- **Repo:** fenzit-be only. No frontend change (16-3/16-4 come later).
- **Status:** Implemented against this spec; BMAD code review + triage follows.
- **Sources:** epics-attendance-leave.md §Epic 16; ARCHITECTURE-SPINE.md AD-3 (amended), AD-4, AD-5, AD-6, AD-7, AD-9, AD-13, AD-15, AD-20, AD-22, AD-26; PRD FR-2, FR-7, FR-8.

## 1. Fix-placement analysis (per the root-CLAUDE.md rule)

Every requirement in these two stories lands **BE + DB**; the FE is untouched:

| Concern | Layer | Why |
|---|---|---|
| Durable attempt/record state, uniqueness guards | **DB** (two plain tables) | Only the database can enforce `UNIQUE` idempotency and one-record-per-day across processes and retries. |
| Distance, accuracy, mocked, rate-limit decisions | **BE** (TypeScript, inside one pg transaction) | PRD: "the server makes the decision"; device values are never trusted. Computation is arithmetic over already-fetched rows — no SQL authoring needed. |
| Two-level advisory locking | **DB helpers that already exist** (`attendance_lock_tenant`, `attendance_lock_employee`, migration 20260926000003) | Called from TS inside the transaction; zero new SQL. |
| "Today" | **DB helper that already exists** (`attendance_today`) | AD-7 single source; reused verbatim. |
| Day context (tracked/office/rules/weekly-off/holiday/midpoint/cut-off) | **BE** (TypeScript module) — NOT a `attendance_day_context()` SQL function | See D1. |
| Fake-location owner alert | **BE** (plain INSERT into `notifications` in the same transaction) | Same-transaction side effect per AD-13; a plain parameterised INSERT, not a function. |
| Late / early-checkout / worked-minutes arithmetic | **BE** (pure functions) | AD-9 says computed on read; Epic 18's read function will import the same pure helpers. |

## 2. Design decisions (locked before implementation)

**D1 — `attendance_day_context` is a TypeScript module, not a SQL function.**
The spine sketched it as SQL, but AD-3's amendment (user decision, 2026-09-27) narrows Epic 16–19 to NestJS-first: *"Every new stored function must be justified in its story spec … Prefer a single guarded UPDATE or plain admin-client write even at the cost of an extra round-trip."* Justification applied here: the day context is a **read-path** helper with exactly one consumer today (check-in/out). No multi-row write, no same-transaction side effect, nothing that makes app code unsafe. The user's standing instruction ("write as little RPC/SQL as possible — I am not good at SQL") and the 15-7 precedent both point the same way. **AD-22's real contract — one place computes these facts, everyone else reads them — is preserved**: `src/attendance/day-context.ts` becomes the only implementation, and Epics 17 (leave), 18 (day statuses), 19 (reminders) extend/import it instead of re-deriving. If a later epic proves a set-returning SQL shape is required (e.g. pg_cron reminders joining it server-side), that story justifies it then.

**D2 — Zero new SQL functions.** The migration is DDL only: two tables, indexes, grants, `updated_at` triggers (reusing `update_updated_at_column()`). Locking and today-resolution reuse the two existing helpers. Check-in/out are single pg transactions in NestJS via `PgPoolFactory.withTransaction` (the 15-7 pattern): shared tenant lock → exclusive employee lock (AD-5), every statement parameterised.

**D3 — Rejection priority (single `outcome` per attempt).** When multiple rules fail, exactly one outcome is recorded, in this order: `stale_fix` → `low_accuracy` → `too_far` → `mocked`. Rationale: a stale fix invalidates every other judgement; an inaccurate fix makes distance untrustworthy, so accuracy gates distance; mocked is evaluated last so the monthly fake-location alert counts only attempts whose location was otherwise valid (a too-far-and-mocked attempt is recorded as `too_far`). All four count identically toward the rate limit, so ordering does not change limiting behaviour.

**D4 — `already_checked_out` completes the AD-4 catalogue.** The spine catalogue omits the symmetric replay case of `already_checked_in`: a second check-out on a day already checked out, presented with a fresh idempotency key. Added as `409 ATTENDANCE_ALREADY_CHECKED_OUT`. (Same-key replays never reach this — they return the stored outcome, AD-6.)

**D5 — Fake-location notification dedupe key follows the registry convention.** AD-13's spine text (`fake_location:<employee_id>:<yyyy-mm>`) predates the 14-2 convention the registry itself documents: the partial unique index is **global** on `dedupe_key` alone, so tenant and recipient must be embedded or cross-tenant fan-outs collide. Key: `<tenantId>:attendance.fake_location:<ownerId>:<employeeId>:<yyyy-mm>`. Recipient: `tenants.owner_id` (the single owner, per the 3.1 notify-owner precedent). Registry entry `FAKE_LOCATION: 'attendance.fake_location'` with payload `employeeName`, `month`, `attemptCount`; `entity_type 'attendance'`, `entity_id = employee id`.

**D6 — Rate limit lives in the attempts table (AD-15).** Constants locked in code (PRD delegated the values): window 10 minutes, 5 counted rejections, block 10 minutes. Only `too_far`/`low_accuracy`/`mocked`/`stale_fix` count. The 5th counted rejection inside the window writes `blocked_until = attempted_at + 10 min` on its own attempt row; while any `blocked_until > now()` exists for the employee, attempts are recorded as `rate_limited` (not counted) and answered `429` + `Retry-After` (the filter already lifts `retryAfterSeconds` into the header — verified in `global-exception.filter.ts`). Window/block queries are plain parameterised SELECT/INSERT — no functions.

**D7 — Office with no rule covering today still checks in.** Rules are effective-dated and the EXCLUDE constraint prevents overlap but not gaps. If no rule covers today: check-in proceeds (office pin + radius are non-effective-dated), `officeRulesId`/`startTime`/`endTime`/`midpoint` are null, and `lateMinutes` / `earlyCheckout` surface as null/false rather than a fabricated rule. Same honest-null treatment `me/summary` already ships.

**D8 — Both endpoints answer `201` on success** per the AD-4 catalogue row (`ok → 201`), even though check-out UPDATES the record.

**D9 — Attempt rows.** Every call that passes DTO + idempotency-key validation writes exactly one `attendance_attempts` row, whatever the outcome (`ok` included) — that is AD-6's "every check-in/out call, accepted or rejected". A missing or malformed `X-Idempotency-Key` is a `422` at the controller boundary with **no** attempt row (the dedupe key is part of the row's uniqueness; there is nothing to key it by). Rejected attempts store the submitted coordinates (the PRD's owner dispute view needs them); AD-26's 90-day coordinate prune is pg_cron work deferred to Epic 19.

**D10 — Enable-day grace cannot block a check-in.** FR-2: "Not tracked [on the enable day] **unless the Employee checks in today** (then it's evaluated as normal)." The call being processed *is* the check-in, so the check-in path's `tracked` test is: enrolment covers today AND `attendance_settings.setup_completed_at` IS NOT NULL AND `enabled = true`. The full grace predicate (enabled-at wall-clock after that day's Start AND no check-in → not tracked) is implemented in the day-context module with a `hasCheckIn` parameter and unit-tested now — Epic 18/19 consume it; the kill switch (`enabled = false`) forces `not_tracked` (raw-truth rule: never read the module flag for per-employee state beyond this gate).

**D11 — Instants in responses carry the tenant offset** (`2026-09-28T10:22:00+05:30`), per AD-7's explicit wire rule ("fenzo-app formats the wall-clock parts of that string … and never converts to the device timezone"). This deliberately differs from 15-7/15-10's `toISOString()` (UTC `Z`) metadata instants (`enabledAt`, `onboardedAt`) — those are display-relative metadata; check-in/out times are wall-clock-meaningful and must render without the FE knowing the tenant timezone. Small `Intl`-based util (`toTenantOffsetIso`), no timezone library (AD-7).

**D12 — Late / early formulas (shared with Epic 18).** All arithmetic on tenant-local wall-clock minutes via `Intl` parts from `tenants.timezone`:
- `late = checkinMinuteOfDay > startMinuteOfDay + lateCutoffMinutes` (late cut-off is the grace window after Start; `lateCutoffMinutes = 0` → late strictly after Start). `lateMinutes = max(0, checkin − (start + cutoff))`.
- `earlyCheckout = checkoutMinuteOfDay < endMinuteOfDay`; `earlyCheckoutMinutes = end − checkout` (whole minutes, truncated).
- `midpoint = start + (end − start) / 2`, truncated to the minute (AD-22) — computed in the context now (unit-tested), consumed by 16-2's response seam and Epic 17's second-half-leave rule (leave state is null until Epic 17, so expected-end = rule end today).
- `workedMinutes = trunc((checkoutAt − checkinAt) / 60000)` from the stored instants (not wall-clock), so a tz change mid-day cannot corrupt it.

**D13 — Check-out on a weekly-off/holiday/any tracked day uses the same gates** as check-in (same office radius, accuracy, mocked, stale, idempotency, rate-limit budget). `not_checked_in` (409) when no record exists for today.

**D14 — `confirmLeaveCancel` is accepted and ignored.** AD-24's `leave_confirmation_required` outcome is added to the enum/`ErrorCode` for seam completeness but has no trigger path until Epic 17 builds the leave model. The DTO accepts the optional flag so 16-4's client can send it from day one without a contract change.

**D15 — Uniqueness as last guard.** The service pre-checks under the exclusive employee lock (so the common double-tap path returns a clean committed outcome), and `UNIQUE (employee_id, work_date)` + `UNIQUE (tenant_id, request_id)` remain the race backstop; a surprising `23505` maps to the corresponding outcome rather than a 500.

## 3. Data model (migration `20260928000002_attendance_check_in_out_tables.sql`)

One migration, DDL only, 15-7 grants hygiene throughout (RLS on, **no** policies, `REVOKE ALL … FROM anon, authenticated` — Supabase default grants would otherwise leave inert write grants; explicit `GRANT` to `service_role` only).

```sql
create table public.attendance_attempts (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid not null references public.tenants (id) on delete cascade,
  employee_id   uuid not null,
  request_id    uuid not null,                        -- AD-6 (the X-Idempotency-Key)
  kind          text not null check (kind in ('check_in','check_out')),
  outcome       text not null check (outcome in (
                  'ok','too_far','low_accuracy','mocked','stale_fix',
                  'rate_limited','not_tracked','already_checked_in',
                  'already_checked_out','not_checked_in')),
  latitude      double precision,
  longitude     double precision,
  accuracy_m    double precision,
  distance_m    double precision,
  radius_m      integer,
  mocked        boolean,
  provider      text,
  fix_age_ms    integer,
  blocked_until timestamptz,                          -- AD-15, set on the 5th counted rejection
  attempted_at  timestamptz not null default now(),
  created_at    timestamptz not null default now(),
  constraint attendance_attempts_tenant_request_uq unique (tenant_id, request_id)
);
-- composite tenant FK (15-7 pattern): employees cannot be orphaned across tenants
alter table public.attendance_attempts
  add constraint attendance_attempts_employee_tenant_fkey
  foreign key (employee_id, tenant_id)
  references public.users (id, tenant_id) on delete restrict;

create index attendance_attempts_employee_time_idx
  on public.attendance_attempts (employee_id, attempted_at desc);

create table public.attendance_records (
  id                    uuid primary key default gen_random_uuid(),
  tenant_id             uuid not null references public.tenants (id) on delete cascade,
  employee_id           uuid not null,
  work_date             date not null,                -- tenant-local (AD-7) = attendance_today
  office_id             uuid not null,                -- AD-9 snapshot
  office_rules_id       uuid,                         -- null when no rule covers today (D7)
  radius_m              integer not null,
  checkin_at            timestamptz not null,         -- server now() only
  checkin_attempt_id    uuid not null,
  checkin_lat           double precision not null,
  checkin_lng           double precision not null,
  checkin_accuracy_m    double precision not null,
  checkin_distance_m    double precision not null,
  checkin_mocked        boolean not null,
  checkin_provider      text,
  checkout_at           timestamptz,
  checkout_attempt_id   uuid,
  checkout_lat          double precision,
  checkout_lng          double precision,
  checkout_accuracy_m   double precision,
  checkout_distance_m   double precision,
  checkout_mocked       boolean,
  checkout_provider     text,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  constraint attendance_records_employee_work_date_uq unique (employee_id, work_date),  -- AD-6 last guard
  constraint attendance_records_checkout_pair_check
    check ((checkout_at is null) = (checkout_attempt_id is null))
);
-- composite FKs: (employee_id, tenant_id) → users; (office_id, tenant_id) → attendance_offices;
-- office_rules_id → attendance_office_rules (id); checkin/checkout_attempt_id → attendance_attempts.
```

Plus: `updated_at` triggers on both tables, indexes (`checkout_attempt_id`), the REVOKE/GRANT block, and a file-header comment noting AD-26's prune cron arrives with Epic 19.

## 4. API contract (new routes on `MeAttendanceController`, role TECHNICIAN, identity from JWT only)

### POST `/api/v1/attendance/me/check-in` and `POST /api/v1/attendance/me/check-out`

Headers: `X-Idempotency-Key: <uuid v4>` — required; missing/malformed → `422 VALIDATION_ERROR`, no attempt row (D9).

Body (identical shape both routes — AD-20's capture object):

```json
{
  "latitude": 19.076,          // required, [-90, 90]
  "longitude": 72.8777,        // required, [-180, 180]
  "accuracyM": 12.5,           // required, >= 0
  "mocked": false,             // optional boolean|null (null = not detected)
  "provider": "fused",         // optional string|null, informational only
  "fixAgeMs": 1200,            // required, >= 0 (client-computed fix age)
  "confirmLeaveCancel": true   // optional, accepted and ignored until Epic 17 (D14)
}
```

Success `201` (check-in):

```json
{
  "workDate": "2026-09-28",
  "checkinAt": "2026-09-28T10:22:00+05:30",
  "lateMinutes": 0,
  "isLate": false,
  "dayContext": { "isWeeklyOff": false, "isHoliday": false, "holidayName": null, "isWorkingDay": true }
}
```

Success `201` (check-out):

```json
{
  "workDate": "2026-09-28",
  "checkinAt": "2026-09-28T10:22:00+05:30",
  "checkoutAt": "2026-09-28T19:30:00+05:30",
  "workedMinutes": 548,
  "earlyCheckout": false,
  "earlyCheckoutMinutes": null,
  "dayContext": { "isWeeklyOff": false, "isHoliday": false, "holidayName": null, "isWorkingDay": true }
}
```

Error catalogue (AD-4 + D4; every rejection below is a **committed** attempt row first, then the mapped exception; `too_far` carries `distanceM` + `radiusM`; `rate_limited` carries `retryAfterSeconds` → `Retry-After` header):

| Outcome | HTTP | ErrorCode |
|---|---|---|
| `too_far` | 422 | `ATTENDANCE_TOO_FAR` |
| `low_accuracy` | 422 | `ATTENDANCE_LOW_ACCURACY` |
| `mocked` | 422 | `ATTENDANCE_MOCK_LOCATION` |
| `stale_fix` | 422 | `ATTENDANCE_STALE_FIX` |
| `rate_limited` | 429 | `ATTENDANCE_RATE_LIMITED` |
| `already_checked_in` | 409 | `ATTENDANCE_ALREADY_CHECKED_IN` |
| `already_checked_out` | 409 | `ATTENDANCE_ALREADY_CHECKED_OUT` |
| `not_checked_in` | 409 | `ATTENDANCE_NOT_CHECKED_IN` |
| `not_tracked` | 403 | `ATTENDANCE_NOT_TRACKED` |
| `leave_confirmation_required` | 409 | `ATTENDANCE_LEAVE_CONFIRMATION_REQUIRED` (enum only until Epic 17, D14) |

Idempotent replay (same key): the stored attempt is returned/rethrown exactly as the first call answered — no second row, no side effect (AD-6). An `ok` replay rebuilds the response from the record via `checkin_attempt_id`/`checkout_attempt_id`.

### Service sequencing (single `withTransaction`, both routes)

```
lockTenantShared → attendance_lock_employee(employee)          -- AD-5 order
today = attendance_today(tenant)                               -- AD-7
replay? attempt by (tenant_id, request_id) → rebuild & answer   -- AD-6, no writes
blocked? max(blocked_until) > now → record rate_limited → 429   -- AD-15 (not counted)
ctx = buildDayContext(tx, tenant, employee, today)              -- D1 module
not tracked? (D10 gate) → record not_tracked → 403
kind == check_in  && record exists today → record already_checked_in → 409
kind == check_out && no record today    → record not_checked_in → 409
kind == check_out && already out        → record already_checked_out → 409
stale (fixAgeMs > 30000)                → record stale_fix → 422        -- AD-20
accuracyM > 100                         → record low_accuracy → 422
haversine(pin, fix) > radius_m          → record too_far (+distanceM/radiusM) → 422
mocked == true                          → record mocked → 422
   └ 3rd 'mocked' this calendar month → INSERT notification (D5 key) ON CONFLICT DO NOTHING
   └ 4 counted rejections already in window → blocked_until on this row   -- AD-15
accepted:
  check_in  → INSERT attempt(ok) + INSERT attendance_records (snapshot, AD-9)
  check_out → INSERT attempt(ok) + UPDATE record checkout snapshot
build response (late/early/worked per D12, offset instants per D11)
COMMIT
```

Rejection priority D3; every INSERT is a plain parameterised statement.

## 5. Code layout (files ≤ 300 lines, house structure)

| File | Contents |
|---|---|
| `attendance/constants.ts` (new) | `CHECKIN_MAX_ACCURACY_M = 100`, `FIX_MAX_AGE_MS = 30000`, `RATE_WINDOW_MIN = 10`, `RATE_MAX_COUNTED = 5`, `RATE_BLOCK_MIN = 10`, outcome lists. |
| `attendance/geo.ts` (new) | Haversine distance (metres) — pure. |
| `attendance/day-context.ts` (new) | D1 module: pg reads (enrolment, assignment→office, rule, weekly-offs, holiday, settings, tenant tz, enable-day grace input) + pure pickers **reusing** `rangeCovers`/`pickRuleForDate`/`pickWeeklyOffDays` from `me-summary.model.ts` so summary and context cannot drift. Exposes `DayContext` + wall-clock math (`minuteOfDayInTz`, `midpointMinute`, `lateMinutes`, `earlyCheckoutMinutes`). |
| `attendance/check-in-out.repository.ts` (new) | All statement functions: attempts insert/replay-read/blocked-read/counted-count/monthly-mocked-count, records insert/update/find, notification insert. |
| `attendance/check-in-out.model.ts` (new) | Response types, offset-instant util, outcome→exception mapping (the route contract). |
| `attendance/check-in-out.service.ts` (new) | The sequencing above; `HttpException` per catalogue. |
| `attendance/dto/check-in-out.dto.ts` (new) | One DTO with class-validator, used by both routes. |
| `me-attendance.controller.ts` | Two new `@Post` routes (Swagger decorators per house style). |
| `common/enums/error-code.enum.ts` | +10 codes (catalogue + `ATTENDANCE_LEAVE_CONFIRMATION_REQUIRED`). |
| `attendance/notification-events.ts` | +`FAKE_LOCATION` registry entry (D5) — registry stays the source of truth; FE mirrors later. |

## 6. Ripple effects on existing behaviour (must verify, not assume)

- **FR-6 self-activation:** `enrolments.service` already probes `attendanceRecordsExist(tx)` and `hasCheckInOn(...)` — the moment the migration lands, "reassignment applies from tomorrow if the employee checked in today" goes live. The enrolments integration journey must gain a probe for this, and the deferred roster prefill (deferred-work.md) stays deferred (FE work).
- **RLS isolation spec:** `rls-isolation.integration.spec.ts` scans `pg_proc` for `^(attendance|leave)_` functions — with zero new functions the scan result is unchanged; add table-denial probes for the two new tables (anon/authenticated cannot SELECT/INSERT even though Supabase default grants exist).
- **`me/summary`, access view, wizard:** untouched — no migration touches their tables.

## 7. Test plan

**Unit (jest, `bun run test`) — new specs:**
- `geo.spec.ts` — haversine: zero distance, known city pair (±1 m), antipodal sanity.
- `day-context.spec.ts` — grace predicate matrix (enable-day × enabled-at vs start × hasCheckIn), rule/weekly-off/holiday picking incl. gap (null rule) and override-replaces-default, midpoint truncation, late/early math incl. cutoff 0 and minute truncation, wall-clock extraction across a DST-ambiguous zone is out of scope (IST fixed offset; Asia/Kolkata asserts).
- `check-in-out.model.spec.ts` — offset-instant formatting (+05:30), outcome→exception mapping table (status + error_code + extras), `workedMinutes` truncation.
- `check-in-out.service.spec.ts` — mocked `PoolClient` journey per outcome: replay short-circuit, rate-limit block window math (4-then-5th sets blocked_until; 6th recorded-not-counted), not-tracked gate, check-in ok (record fields + late), already_checked_in, not_checked_in, already_checked_out, early checkout, mocked → 3rd-month notification insert (and 2nd does not), D3 priority, transaction rollback on error.
- `check-in-out.repository.spec.ts` — SQL text contracts: parameterised statements only, FK-safe column lists, dedupe `ON CONFLICT DO NOTHING`.
- DTO spec — validation matrix incl. missing idempotency key handling at controller (422, no attempt row).
- Controller spec — route wiring, role guard, header extraction.

**Real-DB integration (`test:e2e:real`, journey spec `attendance-check-in-out.integration.spec.ts`)** — fixtures per the 15-7 harness (admin client + raw pg, unique phones, FK-safe cleanup): tenant + owner + technician, office (radius 100) + rule, settings completed, enrolment + assignment covering today.

1. Setup incomplete → check-in `403 ATTENDANCE_NOT_TRACKED` (attempt row exists with outcome).
2. Weekly-off-today override → check-in allowed (`isWeeklyOff: true` in response); restore.
3. Holiday-today row → check-in allowed (`isHoliday: true`); remove.
4. Inside radius, good fix → `201`; DB row snapshot matches (office, rule, radius, server time, lat/lng/accuracy/distance/mocked/provider); `lateMinutes` correct vs rule.
5. Replay same key → identical 201, still ONE attempt row + ONE record.
6. Second check-in, new key → `409 ALREADY_CHECKED_IN` (recorded, not counted).
7. `too_far` (coords ~10 km) → 422 with `distanceM`/`radiusM`; attempt stores coordinates.
8. `low_accuracy` (150 m) → 422, counted.
9. `stale_fix` (fixAgeMs 40 000) → 422, counted.
10. `mocked` ×3 (across the month key) → on the 3rd: notification row exists with the D5 dedupe key, exactly once even when a 4th mocked lands.
11. Rate limit: 5 counted within window → 5th sets `blocked_until`; 6th → 429 + `Retry-After` header + `rate_limited` row not counted; after window passes (blocked_until manually backdated) → accepted again.
12. Check-out before check-in-when-none (fresh employee) → `409 NOT_CHECKED_IN`.
13. Check-out early (before rule end) → `earlyCheckout: true` + minutes; same row updated (not a second row); `workedMinutes` matches instants.
14. Check-out again, new key → `409 ALREADY_CHECKED_OUT`.
15. FR-6 ripple: with today's record present, enrolments reassign endpoint now applies from tomorrow (probes the 15-7 self-activating code path).
16. RLS: anon/authenticated-keyed queries against both new tables are denied.

**Typecheck + full suites:** `bun run typecheck`, `bun run test`, `bun run test:e2e` (non-real e2e must stay green/skipped without env).

## 8. Out of scope (explicit)

- Leave outcomes (`leave_confirmation_required` trigger), second-half-leave midpoint override — Epic 17 (seam per D14/D12).
- Day-status/days-worked read functions — Epic 18 (imports D12 pure math).
- AD-26 coordinate prune + reminders pg_cron — Epic 19.
- Push delivery of the fake-location alert (AD-13 `pushed_at` outbox stays unwritten).
- FE capture service and Today screen — 16-3/16-4.

## 9. Change Log (implementation record, 2026-09-29)

All green before review: unit 72 suites / 1134 tests; real-DB e2e 20 suites / 397 tests (journey = 17 probes); typecheck clean; migration applied live via MCP.

- **[Journey-found, FIXED] Rejections must throw AFTER commit.** The first implementation threw the mapped exception inside `withTransaction`, rolling the committed attempt row back — the exact AD-4 violation the journey caught on its first real run. Restructured: the transaction returns `{ response } | { rejection }` and `run` throws after COMMIT. Unit specs could not catch this (no real rollback); the journey did its job.
- **[Journey-found, FIXED] `attendance_attempts.updated_at` column added.** The migration attached the house `updated_at` trigger but the table lacked the column — any future UPDATE failed with `record "new" has no field "updated_at"`. Corrected in the migration file and applied live via MCP.
- **[Journey-found, FIXED] Parameter type casts.** `attempted_at at time zone $2` and `jsonb_build_object(..., $4, ...)` cannot infer parameter types server-side (`could not determine data type of parameter $4`); explicit `::text`/`::int`/`::uuid` casts added in the repository.
- **[Test-only]** Journey budget miscount fixed (3rd mocked must BE the 5th counted rejection: stale_fix probe moved to a second technician); replay compared at second precision (offset strings truncate ms); anon SELECT asserts an error (REVOKE ALL, not RLS-empty).
- **[Doc]** api-contracts.md gained the check-in/out section (contract above); the FR-6 "checked-in-today reassign" primitives are now live (probed in the journey); the roster-prefill FE affordance in deferred-work.md remains deferred.

## 10. BMAD code review triage (2026-09-29) — 3 lenses × step-03

Three independent review agents (blind bug-hunter, edge-case/contract hunter, acceptance auditor) reviewed the full diff; every finding was source-verified before action. Acceptance verdict: **all 11 ACs MET, SHIP-WITH-PATCHES**. Ledger after dedupe:

**Patched (16)** — the review earned its keep:
1. **CRITICAL — `@Body()` was missing on both route handlers**: `dto` arrived `undefined` over HTTP → 500 on every real call. Unit tests called handlers directly and the journey drove the service directly, so nothing caught it. Fixed + pinned by a route-args metadata test (`RouteParamtypes.BODY:2`).
2. **HIGH — day-context rule query passed `''` as a uuid** when no assignment covers → `22P02` → 500 exactly for never-enrolled technicians (the `not_tracked` population). Fixed (NULL + `$1::uuid`) + a never-enrolled journey probe.
3. `fixAgeMs` lacked `@Max` — values ≥ 2³¹ 500'd on the int4 column (22003). Capped at 86 400 000 + DTO spec.
4. Idempotency replay probe is now **employee-scoped** — another employee's key can no longer leak their record.
5. Spec D15 implemented: a raced key (23505 from a *different* employee) maps to a committed `409 DUPLICATE_RESOURCE`, not a 500.
6. AD-15/D5 arithmetic now runs on the **DB clock** (`dbNow`; month key from `to_char(now() at time zone …)`) — app/DB skew could stretch the block and double-fire the monthly alert.
7. `rate_limited` replays answer the still-live block's remaining seconds, not a stale 1.
8. `leave_confirmation_required` admitted by the outcome CHECK + constants now (Epic 17's first writer cannot 23514).
9. Registry strings bound as parameters in the alert INSERT (no hardcoded event text).
10. `checkin_attempt_id` index added (the ok-replay rebuild reads it).
11. `provider` whitespace normalised to null; dead `attemptWasOk` removed.
12. File-size rule restored: split into `check-in-out.rejections.ts`, `check-in-out.replay.ts`, `check-in-out.records.repository.ts`, `day-context.read.ts` (all ≤ 300 lines).
13. `check-in-out.repository.spec.ts` added (SQL-text contracts incl. parameterisation, employee-scoped probe, ON CONFLICT, 23505 mapping).
14. `dto/check-in-out.dto.spec.ts` added (validation matrix).
15. Tests: D3 full-ladder priority, `workedMinutes` sub-minute truncation, grace minute-truncation pinning.
16. Journey: never-enrolled probe + endpoint-level FR-6 probe (real `reassignOffice` — view keeps today's office, new assignment starts tomorrow).

**Deferred (3):** `too_far` replay degrades the office name in the message ("your office") — the faithful status/code/numbers survive; storing the name would cost a schema column for presentation. Check-out must land on the same tenant-local date (overnight shifts are not in the PRD; documented in api-contracts). The rls-isolation file did not gain table probes — the journey's live RLS probe covers the same ground.

**Dismissed (3, with reasons):** enable-day check-out answers `409 not_checked_in` rather than `403 not_tracked` (more actionable for the app; D10's grace predicate is the read-side/Epic-18 contract); tenant timezone is not snapshotted on records (AD-7 makes it the single clock; `workedMinutes` is instant-based and tz-safe); grace compares truncated minutes (pinned as intended by tests).

**Final:** 74 suites / 1158 unit + 20 suites / 399 real-DB e2e (19 journey probes), typecheck clean; migration + two corrective applies live via MCP.
