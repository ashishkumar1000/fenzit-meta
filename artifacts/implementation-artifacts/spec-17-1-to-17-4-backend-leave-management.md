# Spec — Stories 17-1..17-4: Leave Management (Backend)

- **Stories:** 17-1 (leave data model & apply) + 17-2 (approve/reject) + 17-3 (revoke & cancel with split logic) + 17-4 (apply on behalf & check-in auto-cancel, FR-9) — done together in one pass, one review, one commit (user decision, 2026-09-29; the 16-1+16-2 precedent). The four stories share one data model and one transition writer; splitting them would mean three rewrites of the same files.
- **Repo:** fenzit-be only. No frontend change (17-5..17-8 come later). Backend deploys first (cross-repo ordering).
- **Status:** Spec for implementation; BMAD code review + triage follows implementation.
- **Sources:** epics-attendance-leave.md §Epic 17; ARCHITECTURE-SPINE.md AD-3 (amended), AD-5, AD-6, AD-7, AD-11, AD-13, AD-16, AD-22, AD-23, AD-24; PRD FR-9, FR-12–FR-17 (exact testable consequences quoted where they bind).
- **Ratified letter deviations (adversarial spec review, 2026-09-29):** where AD-2/AD-11/AD-16 say "computed in SQL" / "no TypeScript derives it" / "SELECT policies", this epic ships the TypeScript relocation the AD-3 amendment mandates for Epics 16–19 (the 16-1 D1 precedent). Each contract is preserved as "one implementation everyone shares" (`leave.model.ts`, `leave-transition.ts`, the day-context module) and the deny-by-default grants/RLS posture is kept. AD-23's `disable` rule is read literally: **all** pending leave is cancelled (the "future" qualifier binds to approved leave only, per the FR-28 parallel).

## 1. Fix-placement analysis (per the root-CLAUDE.md rule)

Every requirement lands **BE + DB**; the FE is untouched:

| Concern | Layer | Why |
|---|---|---|
| Durable leave state, overlap block, idempotency | **DB** (three plain tables + one partial unique index + one `UNIQUE`) | Only the database can enforce uniqueness/overlap across processes and retries (16-2 precedent). |
| Illegal state transitions | **DB** (one guard trigger per AD-11 — the single new SQL function, justified in D2) | The state machine must hold for EVERY writer, including future `disable`/`removal` stories and manual SQL — not just the TS path that remembers to check. |
| Apply validation (5 rejection rules), split math, derived status, previews | **BE** (TypeScript) | Arithmetic/lookups over already-read rows — no SQL authoring needed (AD-3 amendment: NestJS-first). |
| `leave_transition_days` (AD-23 single writer) | **BE** (TypeScript module) | See D2 — mirrors the 16-1 D1 day-context precedent. |
| Leave facts in the day context (AD-22 completion) | **BE** (extend `day-context.read.ts`) | One more parameterised read in the existing module; check-in is the consumer. |
| All notifications | **BE** (plain INSERTs in the same transaction, registry-driven) | AD-13; 16-1 fake-location precedent. |
| Request-level status + working-day count on reads | **BE** (pure derivation, one implementation) | See D5 — AD-11's "no app code derives it" contract, relocated to one TS module per the AD-3 amendment. |

## 2. Design decisions (locked before implementation)

**D1 — One migration, DDL + one guard trigger. `leave_requests`, `leave_request_days`, `leave_events`.** Shapes per AD-11 and the spine's Structural Seed. Days rows exist for every calendar date in the range **including off days** (weekly off / holiday) — they carry the span; the working-day count excludes them on read. `leave_requests.UNIQUE (tenant_id, request_id)` is AD-6's idempotency row. The overlap blocker is the partial unique index `(employee_id, leave_date) WHERE state IN ('pending','approved')`. Grants hygiene exactly per 20260928000002 (RLS on, NO policies, `REVOKE ALL … FROM anon, authenticated`, grant `service_role` only).

**D2 — `leave_transition_days` is a TypeScript module, not a SQL function.** The spine sketches SQL, but AD-3's amendment (2026-09-27) makes Epic 16+ NestJS-first: every new stored function must be justified in plain English, and none of these writes needs one — they are parameterised UPDATE/INSERT statements inside the caller's transaction (15-7/16-1 precedent, zero-RPC track record). AD-23's contract is preserved in TS: `src/attendance/leave-transition.ts` is the **only** code that changes `leave_request_days.state`; it (a) re-takes the AD-5 employee lock (reentrant no-op when held — the assertion becomes self-enforcing; a caller that skipped the lock still serialises correctly), (b) updates exactly the requested dates (including off days), pinning the **source states in the UPDATE's WHERE** (`and state = any($n::text[])`) and asserting the affected rowcount — a raced transition cannot double-fire even though the guard trigger admits same→same writes, (c) appends ONE `leave_events` row, (d) inserts the notification the AD-13 registry maps to its cause. Callers must decide-read **under** the lock (read request → take locks → re-read actionable days → decide → transition); the guard trigger alone would let a stale reader rewrite rows to their current state and append a duplicate event. The DB-side guard trigger (D1) is the one stored function this epic adds, named `leave_request_days_state_guard()` so the `^(attendance|leave)_` pg_proc scan keeps holding, justified per the amendment: AD-11 explicitly mandates "a trigger guard rejects illegal transitions", and the state machine must survive writers that don't go through TS (Epic 19 cron, manual fixes) — a TS-only guard would re-plant the trap the trigger exists to close.

**D3 — Day context completes its AD-22 leave seam.** `buildDayContext` gains one parameterised read: today's `leave_request_days` row in state `pending|approved` joined to its request's `part`. `DayContext.leavePart` stops being always-null and gains `leaveState: 'pending' | 'approved' | null`. The remaining AD-22 fields ship as pure helpers in `day-context.ts` — ONE implementation, unit-tested now, consumed by check-in and the leave split: `expectedStartMinute(ctx)` (the midpoint when `leavePart = 'first_half'`, else the rule start — FR-7's "Expected start is the Midpoint" on a first-half leave day) and `expectedEndMinute(ctx)` (the midpoint when `leavePart = 'second_half'`), plus `leaveCutoffPassed(ctx, nowMinute)`. This honours the 16-1 D12 seam hand-off ("Epic 17's second-half-leave rule") in this epic rather than deferring it.

**D4 — Previews share the validation path (AD-24).** The apply preview is the SAME service validation function with `persist: false`; the revoke/cancel previews call the SAME split computation the writes use. No re-implementation exists anywhere.

**D5 — Derived request status and working-day count: one pure TS module.** AD-11 assigns derivation to "the read function"; the AD-3 amendment relocates it to `leave.model.ts` as the single implementation (the D1 day-context precedent). `DERIVED_STATUS_ORDER = ['pending','approved','revoked','cancelled','rejected']` is exported and is THE source of the order: the model derives from it, and the repository's SQL `CASE` filter is generated from the same array (pinned by a repository SQL-text test asserting the states appear in order) so `?status=` can never disagree with the displayed status. Status order (first match): any day `pending` → **pending**; else any `approved` → **approved**; else any `revoked` → **revoked**; else any `cancelled` → **cancelled**; else **rejected**. Rationale: pending needs owner action most; an in-progress request (some days auto-cancelled) still shows its live state. Working-day count per request = dates in range that are working days (weekly-off/holiday facts re-read across the span) — holidays added later recompute honestly on read, per FR-14's "revoked dates become normal working days" and the 15-6 holiday-removal precedent.

**D6 — Error catalogue (new `ErrorCode` entries; PT-style mapping, HINT carries the code).**

| Situation | HTTP | ErrorCode |
|---|---|---|
| Half-day part on a multi-date range / end < start | 422 | `LEAVE_INVALID_RANGE` |
| Range starts > 7 days in the past | 422 | `LEAVE_TOO_OLD` |
| Any date before the employee's attendance start date | 422 | `LEAVE_BEFORE_START_DATE` |
| A past date — or today — in the range already has a check-in | 422 | `LEAVE_CHECKED_IN_CONFLICT` (message names the date) |
| Every date in the range is a weekly off or holiday | 422 | `LEAVE_ALREADY_OFF` ("These days are already off") |
| Range longer than 62 days | 422 | `LEAVE_INVALID_RANGE` (span cap, D15) |
| Overlaps a pending/approved leave day | 409 | `LEAVE_OVERLAP` (message names the date) |
| Request not found / another tenant's | 404 | `LEAVE_REQUEST_NOT_FOUND` |
| Approve/reject on a request with no pending days (not own retry) | 409 | `LEAVE_NOT_PENDING` |
| Revoke with no actionable approved dates (not own retry) | 409 | `LEAVE_NOT_REVOKABLE` |
| Cancel with no actionable pending/approved dates (not own retry) | 409 | `LEAVE_NOT_CANCELLABLE` |
| Guard trigger tripped (defensive — should be unreachable via TS) | 409 | `LEAVE_INVALID_TRANSITION` |
| Check-in needs leave confirmation (exists since 16-1) | 409 | `ATTENDANCE_LEAVE_CONFIRMATION_REQUIRED` |

Actor-not-tracked reuse: `ATTENDANCE_NOT_TRACKED` (403). On-behalf target outside the tenant reuses the existing `ATTENDANCE_EMPLOYEE_NOT_FOUND` (404). Reason-empty on apply/revoke is DTO `VALIDATION_ERROR` (422) — DTOs **trim and reject empty-after-trim**; empty reject reason is VALID (FR-13). The checked-in conflict covers today as well as past dates (FR-16's "no Check-in on those dates" is unqualified), which also makes the on-behalf-leave-today-after-check-in path impossible rather than merely awkward.

**D7 — Idempotency (AD-6).** Apply (`POST /attendance/me/leave`) and on-behalf (`POST /attendance/leave/on-behalf`) require `X-Idempotency-Key` (UUID v4, controller-gated like check-in); a replay returns the stored request view with **no second row**. The replay read is **caller-scoped** — `(tenant_id, request_id, employee_id)` for self-apply, `(tenant_id, request_id, created_by)` for on-behalf — exactly the 16-1 employee-scoping fix: another employee presenting a burned key must neither read the first request's view nor be blocked by it. A key raced across employees surfaces as `23505` on `leave_requests_tenant_request_uq` → 409 `DUPLICATE_RESOURCE` (house `duplicateKeyRejection` pattern); `23505` on `leave_request_days_active_uq` → 409 `LEAVE_OVERLAP`. Approve/reject/revoke/cancel are state-guarded: when the requested transition is no longer possible, the service compares the LAST `leave_events` row — **`order by seq desc limit 1`** (the table carries a `seq bigint generated always as identity`; uuid+now() alone cannot break ties) — same cause AND same actor → 200 with the current request view (own retry); anything else → 409 with the table above. Documented deviation from the 17-2 AC's literal wording ("the second sees … a state-conflict response"): the tenant has exactly one owner, so AD-6's own-retry rule governs — a parallel double-approve produces exactly ONE state change + ONE event, answered 200 twice (the second an own-retry), and the AC's underlying guarantee (never double-applied) is what the probe pins. An own-retry AFTER an intervening event by someone else is a 409 by design (the world moved; retrying blind would be wrong).

**D8 — The split rule (AD-23).** Actionable dates for revoke/cancel = `{ d : d > today } ∪ { today when leave_cutoff_passed(today) is false }`, intersected with the source states (revoke: `approved` only; cancel: `pending` + `approved`). `leave_cutoff_passed` uses `leaveCutoffPassed(ctx, nowMinute)` from the day-context module (D3) with **`nowMinute` taken from the DB clock** (`dbNow(tx)`, the 16-1 review precedent — app/DB skew at the cutoff boundary must not flip the split) compared against that day's Office Start; **when no rule covers today (D7 of 16-1), the cutoff is treated as NOT passed** (there is no office start to miss — the permissive reading; documented). Off days inside a request span are transitioned like any other day in that span (AD-23: "including off days") but only when they are in the source state and the actionable set — a Sunday `approved` row after today IS revoked/cancelled with the rest.

**D9 — Upcoming employees may apply (FR-12 exact).** The apply gate is NOT "tracked today" — PRD: "An **upcoming** Employee can apply for leave only for dates on or after their start date." Gate = attendance exists for the employee: setup completed AND module enabled AND an enrolment row covers today OR starts in the future → else 403 `ATTENDANCE_NOT_TRACKED`. The per-date floor = the enrolment start covering today, else the earliest future enrolment start (the same raw-truth source the access view anchors — never the module flag). Both limits then apply per range: `start_date ≥ max(today − 7 days, floor)` (7-day-back limit, tenant-local dates).

**D10 — On-behalf apply (FR-16).** Same validation path (D9's five rejections, same order), but the request is created with all days **approved** via the transition writer (`cause = apply_on_behalf`), `created_by` = the owner. The employee is notified; later revoke works like any approved leave. Owner scope: `employeeId` must resolve to a user in the owner's tenant (404 otherwise — no existence leak).

**D11 — Check-in × leave (FR-9).** Gate placement in `CheckInOutService.transact`, after the tracked gate and kind-state conflicts, BEFORE the office-pin resolution and D3 ladder — **`kind === 'check_in'` only** (FR-9 is a check-in rule; check-out keeps its 16-2 contract untouched): when `ctx.leaveState ≠ null` AND `ctx.leavePart = 'full_day'` AND `ctx.isWorkingDay` (see below) AND `!dto.confirmLeaveCancel` → committed attempt row `leave_confirmation_required` → 409. On the ACCEPTED path only (the location ladder passed — a `too_far` check-in must not touch leave), if the same condition holds with the flag set → transition ONLY today's row to `cancelled` (`cause = checkin_auto_cancel`), leave the rest of the request untouched, notify the owner. Half-day leave never gates and never cancels (FR-9's explicit exception); on half-day leave dates the check-in response's late/early math uses `expectedStartMinute`/`expectedEndMinute` (D3) — FR-7's midpoint rule goes live here, honouring the 16-1 D12 seam hand-off. `leave_confirmation_required` attempts are **not counted** toward the AD-15 rate-limit budget (the catalogue's counted list is closed). `isWorkingDay` in the gate condition: off-day rows exist inside a span (D1) but FR-9 is about the working day's leave — checking in on a weekly off/holiday inside a leave span proceeds with no dialog and touches nothing (day-status priority already handles that date; locking this here because it is otherwise a surprise dialog every weekend of a leave week).

**D12 — Disable ripple (AD-23 `disable` cause goes live).** The 15-7 `disableEnrolment` flow predates the leave tables; now that they exist, disable MUST cancel leave or a disabled employee keeps active leave forever (Epic 18 would show Leave on an untracked employee). Per AD-23's literal text — "Disable cancels pending and future approved leave" — ALL `pending` days are cancelled regardless of date (unqualified in AD-23 and in FR-28's parallel "Pending leave and future Approved leave are cancelled automatically"), and `approved` days with `leave_date ≥ effectiveFrom`. After the AD-8 plans: transition, `cause = disable`, actor NULL (system), one event per affected request, and notify the employee (AD-23: "and notifies the employee"). Same transaction, locks already held.

**D13 — Reads ship with this batch (FR-17 is Epic 17).** The FE stories need them and no later BE story carries them: `GET /attendance/me/leave` (own history), `GET /attendance/leave` (owner list; `status` filter for the pending queue, optional `employeeId`), plus previews (`GET /attendance/me/leave/preview` for apply, `GET /attendance/me/leave/:id/preview` for cancel, `GET /attendance/leave/:id/preview` for revoke). Derived status filtering in SQL via a `bool_or` aggregate subquery whose CASE order is GENERATED from D5's `DERIVED_STATUS_ORDER` (one source; parity pinned by a repository SQL-text test). Cursor pagination (house `PaginatedResponse`) with **two scopes** — `'leave-me-list'` and `'leave-owner-list'` — so a cursor minted on one endpoint can never be replayed against the other (cursor.util's containment contract). No `GET /:id` detail route — the list response already carries reason, dates and per-day states, and writes return the refreshed request view for in-place FE updates. Preview routes run the same access gate as their writes (403 when not tracked-eligible); an action preview with nothing actionable answers **200 with empty `actionDates`** (previews never 409 — the write is where the conflict is committed).

**D14 — Notifications (AD-13 registry is extended, never bypassed).** New `leave.*` events; recipient = `tenants.owner_id` for owner-facing events, the employee otherwise; `entity_type = 'leave'`, `entity_id = leave_request_id`; push wave per NFR-10; dedupe keys embed tenant + recipient (14-2 convention) and are unique per (cause, request [, date]) so the state machine's one-shot nature makes collisions impossible. Notification inserts copy the house `on conflict (dedupe_key) where dedupe_key is not null do nothing` clause verbatim:

| Event | Recipient | Wave | Payload fields | Dedupe key |
|---|---|---|---|---|
| `leave.applied` | owner | 1 | `employeeName`, `startDate`, `endDate`, `workingDays` | `<t>:leave.applied:<owner>:<reqId>` |
| `leave.applied_on_behalf` | employee | 1 | `startDate`, `endDate`, `workingDays` | `<t>:leave.applied_on_behalf:<employee>:<reqId>` |
| `leave.approved` | employee | 1 | `startDate`, `endDate`, `workingDays` | `<t>:leave.approved:<employee>:<reqId>` |
| `leave.rejected` | employee | 1 | `startDate`, `endDate`, `reason` | `<t>:leave.rejected:<employee>:<reqId>` |
| `leave.owner_revoked` | employee | 1 | `startDate`, `endDate`, `revokedDates[]`, `reason` | `<t>:leave.owner_revoked:<employee>:<reqId>` |
| `leave.employee_cancelled` | owner | 1 | `employeeName`, `startDate`, `endDate`, `cancelledDates[]` | `<t>:leave.employee_cancelled:<owner>:<reqId>` |
| `leave.cancelled_by_disable` | employee | 1 | `startDate`, `endDate`, `cancelledDates[]` | `<t>:leave.cancelled_by_disable:<employee>:<reqId>` |
| `leave.checkin_auto_cancel` | owner | 2 | `employeeName`, `leaveDate` | `<t>:leave.checkin_auto_cancel:<owner>:<reqId>:<date>` |

**D15 — Limits locked in code.** `LEAVE_MAX_PAST_DAYS = 7` and `LEAVE_REASON_MAX = 500` come from the PRD; `LEAVE_MAX_SPAN_DAYS = 62` is an **implementation DoS cap** (an unbounded range would insert unbounded day rows; ~2 months covers any real request; PRD sets no span limit — flagged here for the user to re-tune, one constant). Mirrored as DTO caps; >62 answers 422 `LEAVE_INVALID_RANGE` (catalogue row above). Array parameters in date predicates are always `::date[]`-cast (house `= any($n::text[])` precedent).

## 3. Data model (migration `20260929000001_attendance_leave_tables.sql`)

```sql
create table public.leave_requests (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid not null references public.tenants (id) on delete cascade,
  employee_id uuid not null,
  request_id  uuid not null,                    -- AD-6 (X-Idempotency-Key)
  start_date  date not null,
  end_date    date not null,
  part        text not null,                    -- full_day | first_half | second_half
  reason      text not null check (char_length(reason) between 1 and 500),
  created_by  uuid not null,                    -- actor (employee self or owner)
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  constraint leave_requests_part_check check (part = any (array[
    'full_day'::text, 'first_half'::text, 'second_half'::text])),
  constraint leave_requests_span_check check (end_date >= start_date),
  constraint leave_requests_tenant_request_uq unique (tenant_id, request_id)
);
-- composite FKs (15-7/16-1 pattern):
--   (employee_id, tenant_id) → users (id, tenant_id) on delete restrict
--   (created_by,  tenant_id) → users (id, tenant_id) on delete restrict

create table public.leave_request_days (
  id               uuid primary key default gen_random_uuid(),
  tenant_id        uuid not null references public.tenants (id) on delete cascade,
  leave_request_id uuid not null references public.leave_requests (id),
  employee_id      uuid not null,
  leave_date       date not null,
  state            text not null,               -- pending|approved|rejected|cancelled|revoked
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  constraint leave_request_days_state_check check (state = any (array[
    'pending'::text,'approved'::text,'rejected'::text,
    'cancelled'::text,'revoked'::text])),
  constraint leave_request_days_request_date_uq unique (leave_request_id, leave_date)
);
-- composite FK (employee_id, tenant_id) → users; FK leave_request_id on delete restrict
-- (AD-11: leave rows are never hard-deleted; tenant drops cascade via tenant_id).
create index leave_request_days_employee_date_idx on public.leave_request_days (employee_id, leave_date);
-- AD-11 overlap blocker:
create unique index leave_request_days_active_uq
  on public.leave_request_days (employee_id, leave_date)
  where state in ('pending','approved');

create table public.leave_events (               -- AD-23 audit, append-only
  id               uuid primary key default gen_random_uuid(),
  tenant_id        uuid not null references public.tenants (id) on delete cascade,
  leave_request_id uuid not null references public.leave_requests (id),
  employee_id      uuid not null,
  cause            text not null,               -- AD-23's 9 causes
  actor_id         uuid,                        -- null = system (disable/removal)
  reason           text,
  affected_dates   date[] not null default '{}',
  seq              bigint generated always as identity,  -- D7 "last event" ordering
  created_at       timestamptz not null default now(),
  constraint leave_events_cause_check check (cause = any (array[
    'apply'::text,'apply_on_behalf'::text,'approve'::text,'reject'::text,
    'employee_cancel'::text,'owner_revoke'::text,'checkin_auto_cancel'::text,
    'disable'::text,'removal'::text]))
);
-- composite FKs (employee_id, tenant_id) and (actor_id, tenant_id) → users; index (leave_request_id)
```

Plus the AD-11 guard trigger (the one new stored function, justified in D2, named `leave_request_days_state_guard()`): `BEFORE UPDATE OF state ON leave_request_days` allows same→same (no-op writes) and `pending→approved|rejected|cancelled`, `approved→revoked|cancelled`; anything else `RAISE EXCEPTION … USING ERRCODE='PT422', HINT='LEAVE_INVALID_TRANSITION'`. `updated_at` triggers reuse `update_updated_at_column()`. REVOKE/GRANT block per 20260928000002.

## 4. API contract

### Technician (`/api/v1/attendance/me/leave`, role TECHNICIAN, identity from JWT only)

| Route | Body/Query | Success | Notes |
|---|---|---|---|
| `GET …/me/leave/preview` | `?startDate&endDate?&part?` | 200 `{ ok: true, workingDays, totalDays, part, dates: [{ date, isWorkingDay, kind }] }` or 200 `{ ok: false, errorCode, message }` | D4: same validation, persists nothing. 200-on-rejection is deliberate — the FE renders the message inline (17-5). |
| `POST …/me/leave` | `{ startDate, endDate?, part?, reason }` + `X-Idempotency-Key` | 201 request view | AD-6 replay returns the stored view, no second row (caller-scoped, D7). |
| `GET …/me/leave` | `?cursor&limit` | 200 `PaginatedResponse<request view>` | Own history, newest first, scope `leave-me-list`. |
| `GET …/me/leave/:id/preview` | — | 200 `{ action: 'cancel', actionDates, keepDates, request }` | D4/D8; empty `actionDates` when nothing actionable (200, never 409). |
| `POST …/me/leave/:id/cancel` | — (no reason, FR-15) | 200 refreshed request view + `cancelledDates` | D7 state guard. |

### Owner (`/api/v1/attendance/leave`, role OWNER)

| Route | Body/Query | Success | Notes |
|---|---|---|---|
| `GET …/leave` | `?status?&employeeId?&cursor&limit` | 200 `PaginatedResponse<request view + employeeName>` | `status` filters the DERIVED status (D13) — `pending` is the queue. Scope `leave-owner-list`. |
| `GET …/leave/:id/preview` | — | 200 `{ action: 'revoke', actionDates, keepDates, request }` | D4/D8; empty `actionDates` when nothing actionable (200, never 409). |
| `POST …/leave/:id/approve` | — | 200 refreshed view | D7 guard. |
| `POST …/leave/:id/reject` | `{ reason? }` (optional, ≤500) | 200 refreshed view | Empty reason is valid (FR-13). |
| `POST …/leave/:id/revoke` | `{ reason }` required | 200 refreshed view + `revokedDates` | D8 split. |
| `POST …/leave/on-behalf` | `{ employeeId, startDate, endDate?, part?, reason }` + `X-Idempotency-Key` | 201 view (approved immediately) | D10. |

**Action-preview shape (both):** `actionDates: string[]` = exactly the dates the write would transition (source-state ∩ actionable-set, D8); `keepDates: { date, state, reason: 'past' | 'cutoff_passed' }[]` = source-state dates excluded by the split rule; plus the current request view — 17-7's "Mon–Wed stay Approved · Thu–Fri will be revoked" renders straight from it.

**Request view (both roles; owner list adds `employeeName`):** `{ id, employeeId, startDate, endDate, part, reason, status (derived), workingDays, createdBy, createdAt, dates: [{ date, state }] }` — `workingDays` recomputed on read (D5). Write responses additionally carry the action's split arrays (`revokedDates` / `cancelledDates`).

### Check-in extension (17-4, additive to 16-1's contract)

`confirmLeaveCancel` (accepted-and-ignored since 16-1 D14) goes live per D11: new committed outcome `leave_confirmation_required` → 409 `ATTENDANCE_LEAVE_CONFIRMATION_REQUIRED` (catalogue row already exists; outcome already admitted to the CHECK). Success response unchanged — a cancelled leave day surfaces via `dayContext` in later epics' reads, not by changing the 201 body.

### Service sequencing (each write = one `withTransaction`, 15-7/16-1 pattern)

```
apply / on-behalf:
  lockTenantShared → lockEmployee(target) → today
  replay? caller-scoped (tenant, request, employee|created_by) → stored view   -- AD-6, D7
  access gate (D9) → 403
  validation path (shared with preview, in order):               -- D4
    span/format → floor (D9) → 7-day-back → checked-in (≤today)
    → every-date-off → overlap                                   -- D6 order
  INSERT request + days (all pending | all approved via D2) + event + notification
  23505 by constraint name: leave_request_days_active_uq → 409 LEAVE_OVERLAP;
                            leave_requests_tenant_request_uq → 409 DUPLICATE_RESOURCE

approve/reject:
  read request by (tenant, id) → 404?
  → lockTenantShared + lockEmployee(request.employee)            -- AD-5 order
  → RE-READ actionable (pending) days under the lock → decide    -- D2 (read-decide-act atomic)
  none: last event (seq desc) same cause+actor → 200 view; else → 409
  transition(pending→approved|rejected, source-state pinned) + event + notification

revoke/cancel:
  read request → locks → re-read split (D8) under the lock
  empty: own-retry 200 / conflict 409 (D7)
  transition(actionable → revoked|cancelled, source-state pinned) + event + notification

check-in (D11, kind = check_in only):
  after kind-conflicts, before ladder:
  gate → committed leave_confirmation_required attempt → 409 (when applicable; not rate-counted)
  accepted path (ladder passed): transition(today → cancelled, checkin_auto_cancel)
                                 + owner notification
disable (D12): inside the 15-7 disable transaction, after the AD-8 plans:
  all pending days + approved days ≥ effectiveFrom → cancelled (disable, actor NULL)
  + one event per request + employee notification
```

## 5. Code layout (files ≤ 300 lines, house structure)

| File | Contents |
|---|---|
| `attendance/leave.constants.ts` (new) | States, causes, `LEAVE_MAX_PAST_DAYS/SPAN/REASON`. |
| `attendance/leave.model.ts` (new) | Request-view types, **derived status** (D5), working-day math, outcome→exception mapping (D6). |
| `attendance/leave.repository.ts` (new) | All statements: requests/days/events/notification inserts+reads, span facts (weekly-offs/holidays), overlap & checked-in probes, derived-status list query, replay read. |
| `attendance/leave-transition.ts` (new) | D2 — the only state writer: lock re-take, guarded UPDATE, one event row, registry-mapped notification. |
| `attendance/leave-validation.ts` (new) | D4 — the apply validation path (preview + apply share it) and the split computation (D8) for revoke/cancel + previews. |
| `attendance/leave.service.ts` (new) | Apply, on-behalf, approve, reject, revoke, cancel orchestration. |
| `attendance/leave-read.service.ts` (new) | Previews (apply/cancel/revoke) + lists. |
| `attendance/dto/leave.dto.ts` (new) | Apply/OnBehalf/Reject/Revoke DTOs + query DTOs. |
| `attendance/me-leave.controller.ts` (new) | Technician routes (`attendance/me/leave`). |
| `attendance/leave.controller.ts` (new) | Owner routes (`attendance/leave`). |
| `day-context.read.ts` / `day-context.ts` | +leave read (D3): `leaveState`, live `leavePart`. |
| `check-in-out.service.ts` / `check-in-out.model.ts` | +D11 gate and accepted-path auto-cancel (check_in only); late/early math via `expectedStartMinute`/`expectedEndMinute` (D3). |
| `enrolments.service.ts` | +D12 disable ripple. |
| `notification-events.ts` | +8 `leave.*` registry entries (D14). |
| `common/enums/error-code.enum.ts`, `common/utils/cursor.util.ts` | +`LEAVE_*` codes; +`'leave-list'` scope. |

## 6. Ripple effects on existing behaviour (must verify, not assume)

- **Check-in (16-1):** one new committed outcome + an accepted-path transition. Replays, rate limit and rejections untouched. The `leave_confirmation_required` outcome is already in the attempts CHECK and the outcome constants (16-1 review finding #8 anticipated this) — the first writer cannot 23514.
- **Disable (15-7):** gains the D12 leave sweep (ALL pending days + approved days from `effectiveFrom`). Existing access-state responses unchanged. Journey probe 21 pins both the immediate and the future-effective cases.
- **RLS isolation spec:** zero new functions except the guard trigger `leave_request_days_state_guard()` — the `^(attendance|leave)_` pg_proc scan picks it up by name, so its EXECUTE must be revoked from anon/authenticated in the same migration. Add table-denial probes for the three new tables.
- **`me/summary`, access view, wizard, weekly-offs, holidays:** untouched — no existing table or view changes.

## 7. Test plan

**Unit (jest, `bun run test`) — new specs:** `leave.model.spec.ts` (derived-status order incl. mixed sets, working-day math, view mappers, outcome→exception table), `leave-validation.spec.ts` (rejection ladder order, floor vs 7-day interplay, half-day pairing, span cap, split rule incl. cutoff passed/not/no-rule (D8), off-day actionability), `leave-transition.spec.ts` (lock re-take called, guarded UPDATE args, one event row, registry-mapped notification per cause, PT422 mapping), `leave.service.spec.ts` (mocked-`PoolClient` journeys: replay, every rejection, approve/reject guard + own-retry, revoke split + retry semantics, cancel, on-behalf approved-immediately, disable sweep), `leave.repository.spec.ts` (SQL text contracts: parameterisation, tenant/employee scoping, partial-index backstop mapping, derived-status SQL), `dto/leave.dto.spec.ts` (validation matrix), `me-leave.controller.spec.ts` + `leave.controller.spec.ts` (route wiring, role guards, **route-args metadata pinning for every POST — the 16-1 CRITICAL `@Body()` regression class**), `check-in-out.service.spec.ts` (extended: gate paths, confirm path cancels only today, half-day pass-through, `too_far`-with-confirm leaves leave intact), `day-context.spec.ts` (leave-state read wiring).

**Real-DB integration (`test:e2e:real`, journey spec `attendance-leave.integration.spec.ts`)** — 15-7/16-1 harness (admin client + raw pg, throwaway tenant, unique probe phones, FK-safe cleanup). Probes:

1. Apply happy range spanning a weekend → 201; day rows for EVERY date incl. off days, all pending; `workingDays` excludes the weekend; event row `apply`; owner notification with dedupe key, exactly once after a replay.
2. Replay same key → identical 201, still ONE request/events/notifications; ANOTHER employee presenting the same key → their own fresh apply (no leak, no block); a second employee racing the same key → 409 `DUPLICATE_RESOURCE`, not `LEAVE_OVERLAP` (constraint-name mapping, D7).
3. Single-date `first_half` → OK; multi-date `first_half` → 422 `LEAVE_INVALID_RANGE`; `end<start` → 422; 63-day span → 422 (62 OK).
4. Every-date-off (weekly-off single date; holiday single date) → 422 `LEAVE_ALREADY_OFF` with the exact message; mixed range including off days → OK.
5. Overlap pending → 409 `LEAVE_OVERLAP`; overlap approved (via on-behalf) → 409; apply over a REJECTED request's dates → OK (index admits).
6. 8-days-back → 422 `LEAVE_TOO_OLD`; exactly 7 → OK.
7. Start-date floor: backdated enrolment tech → dates before enrolment start → 422 `LEAVE_BEFORE_START_DATE`; upcoming employee (future enrolment) may apply from the start date, not before.
8. Past date with check-in (direct record insert) → 422 `LEAVE_CHECKED_IN_CONFLICT`; today-with-check-in → 422 (the ≤today rule, D6).
9. Preview = apply's twin: same `workingDays`, same rejection outcome for an invalid range, ZERO rows written (count before/after); preview for an untracked employee → 403 (same gate as the write).
10. Approve → all pending days approved, employee notified; same-owner retry → 200 own-retry with exactly ONE `approve` event row (the AD-6-vs-17.2-wording deviation, D7); reject-after-approve → 409 `LEAVE_NOT_PENDING`; parallel double-approve → exactly one state change + one event.
11. Reject with reason (notification carries it) and without (valid, no reason field).
12. On-behalf → created approved immediately, employee notified; validations still fire (overlap/too-old/checked-in ≤today); target in another tenant → 404 `ATTENDANCE_EMPLOYEE_NOT_FOUND`; revocable like any approved leave.
13. Revoke split (rule start 23:59 — cutoff never passed, so today IS actionable): approved range yesterday..+3 → today+yesterday stay, tomorrow+ revoked; notification carries exact `revokedDates` + reason; missing reason → 422. Re-run against a 00:00 rule (cutoff always passed): today flips into `keepDates` with `cutoff_passed`.
14. Revoke retry by same owner (nothing actionable left) → 200; cancel-by-employee in between → conflict 409.
15. Cancel pending (all future) → fully cancelled + owner notified; cancel approved in-progress → split; cancel with nothing actionable → 409/own-retry 200; revoke-vs-cancel race → serialised, exactly one state change, loser 409.
16. FR-9: approved full-day leave today → check-in without confirm → 409 `ATTENDANCE_LEAVE_CONFIRMATION_REQUIRED` + committed attempt row (not rate-counted), NOTHING changed (no record, days intact); with confirm → 201 + today's row cancelled ONLY (multi-day rest stays approved) + owner notification `checkin_auto_cancel` + record exists.
17. FR-9 half-day: half-day leave today → check-in (no flag) → 201, leave intact; first-half leave day's `lateMinutes` uses the midpoint (FR-7 via D3).
18. FR-9 pending leave: same gate fires; confirm cancels from pending.
19. FR-9 off-day: weekly-off check-in during an approved leave span → 201, no dialog outcome, no cancellation (D11).
20. `too_far` with `confirmLeaveCancel: true` → 422, leave untouched; check-OUT is never gated (D11 scoping).
21. Disable ripple (D12): pending leave (incl. past dates) + future-approved leave, disable today → ALL pending cancelled, approved cancelled from today, employee notified, event `disable` with NULL actor; future-effective disable leaves approved days before `effectiveFrom` approved.
22. No auto-expiry (17-2 AC): raw-insert a past-dated pending request, re-read through the list paths after other probes → still `pending` (no job, no trigger touched it).
23. Derived status + list: mixed request reads `approved` with per-day states; owner `?status=pending` queue; employee sees only own; cross-tenant id → 404; cursors are not interchangeable between the two list endpoints (scope tags).
24. Guard trigger: raw `UPDATE leave_request_days SET state='approved'` on a rejected row → PT422 error.
25. RLS: anon/authenticated SELECT/INSERT denied on all three tables.
26. Check-in replay AFTER auto-cancel (same key) → identical 201, no second transition; tenant-drop cleanup (afterAll) succeeds — the restrict-FK/cascade multi-path stays live-tested.

**Typecheck + full suites:** `bun run typecheck`, `bun run test`, `bun run test:e2e` (non-real stays green/skipped), then the live ladder: MCP-apply migration → journey vs local server → push → production probe.

## 8. Out of scope (explicit)

- Day statuses / "Absent + Leave pending" display — Epic 18 reads `leave_request_days` through the D3 context; this epic only guarantees the state never silently changes (17-2 AC).
- `removal` cause writer — no remove-technician feature exists (FR-28 honoured by design later).
- Half-day expected-start/midpoint override in check-in responses — Epic 18 grading concern.
- FE mirrors of the `leave.*` registry entries — 17-5..17-8.
- Push delivery (`pushed_at` outbox) — AD-13 deferred, unchanged.
- Leave types/quota, attachments — PRD §7.2 out of MVP.

## 9. Change Log (implementation record, 2026-09-29)

All green before review: unit 81 suites / 1278 tests; real-DB e2e 21 suites / 425 tests (journey = 26 probes); typecheck clean; migration + one corrective FK apply live via MCP.

- **[Journey-found, FIXED] Preview twin ordering.** The preview checked the span cap before the tracking gate while apply checked it after — an untracked employee with a 63-day span got 403 from POST but an inline range error from preview. The cap moved into `validateApplyShape` (both paths' first check), unifying the order.
- **[Journey-found, FIXED] Derived-status SQL scope.** The `bool_or` CASE was spliced into the outer SELECT too, where `state` does not exist — every list route 500'd. The outer query now reads `s.derived_status` from the subquery only.
- **[Journey-found, FIXED] `ATTENDANCE_NOT_TRACKED` answered 422** from `leaveRejectionToException` (the D6 table says 403). The journey's on-behalf probe caught it via the foreign-target ordering probe.
- **[Journey-found, FIXED] `ReadEnrolmentFloor` first draft ran three queries** (covering / min / future) with a redundant re-read; collapsed to one ordered read. (Superseded by the review's floor fix below.)
- **[Fixture lessons]** `attendance_office_rules` needs `valid` + `full_day_hours/half_day_hours` (numeric(4,2) = HOURS, not minutes; `end_time > start_time` is a CHECK); daterange params need explicit `::daterange` casts; `current_date` on the UTC server is NOT the tenant date in fixtures (the same trap the reviewed probe later exposed in production code).

## 10. BMAD code review triage (2026-09-29) — 3 lenses × step-03

Three independent review agents (blind bug-hunter, edge-case/contract hunter, acceptance auditor) reviewed the full diff; every finding was source-verified before action. Raw ledger: 9 + 10 + 12 findings → deduped to 19 unique. Acceptance verdict: **all ACs MET after patches, SHIP-WITH-PATCHES** (acceptance auditor's NEEDS-REWORK items all resolved below).

**Patched — production code (12):**
1. **HIGH (3 reviewers independently) — `findCheckedInDates` capped at UTC `current_date`**, not the tenant-local date: between local midnight and UTC midnight the "today with check-in → reject" rule silently failed. Now takes tenant `today` as a parameter (`least($4::date, $5::date)`); the repository spec's old `current_date` pin (a text-restating test) inverted to pin the fix.
2. **HIGH (DoS) — the 62-day span cap ran AFTER `enumerateDates`**, so a crafted multi-year range allocated millions of date strings before rejection. Cap moved into `validateApplyShape` (arithmetical, pre-enumeration); the facts-level and preview-inline duplicates removed — preview and apply now share one ordering.
3. **HIGH (contract) — write responses lacked the promised `revokedDates`/`cancelledDates`** arrays (spec §4 + Swagger promised; code discarded the transition's return). Now spread into the refreshed view; probe 16 pins it.
4. **HIGH (acceptance) — the D9 floor for a disabled-then-re-enabled employee** took the earliest enrolment EVER (a past-ended row), 403-ing a legitimate upcoming apply. Floor now prefers the earliest FUTURE start when nothing covers today; three unit cases pin it.
5. **MEDIUM — the D7 23505 mapping for `leave_request_days_active_uq` was never written** (dead constant; a raced day-INSERT would 500). The day INSERT now maps the constraint to `409 LEAVE_OVERLAP`.
6. **MEDIUM — `:id` params were unvalidated** → malformed ids hit `$2::uuid` → 22P02 → 500. `ParseUUIDPipe` on all six leave `:id` routes.
7. **MEDIUM — `limit=abc` reached SQL as `LIMIT NaN` → 500.** DTO gained `@IsInt @Min(1) @Max(50)` (house pattern).
8. **MEDIUM — the apply preview answered inline 200 for the untracked gate**; D13 says the preview runs the write's gate. Untracked → 403; range rejections stay inline (17-5 renders them).
9. **LOW — the D8 cutoff was reimplemented in the split**; now both consume the exported `isPastOfficeStart` (day-context stays the one implementation).
10. **LOW — `@IsDateString(strict)` admits full date-time strings**; DTO dates gained `@Matches(YYYY-MM-DD)` + calendar validity.
11. **LOW — on-behalf Swagger under-documented** 403/422; mirrored from the apply route.
12. **LOW — `leave_events.leave_request_id` FK relied on NO ACTION** while the header claims RESTRICT; explicit `on delete restrict` in the file + a corrective live apply.

**Patched — tests (8):** probe 13 asserts `previewRevoke` equals the write's split (the AD-24 twin claim, previously unpinned); probe 16 adds the cancel preview + `cancelledDates` response pin; probe 17 pins `blocked_until IS NULL` (the gate is not rate-counted), the mixed request deriving `approved`, and the FR-9 cancel split; probe 26 now DOES the replay-after-auto-cancel (identical 201, exactly one event) it always claimed; probes 3/4/10/15/22 gained the 62-day-OK, weekly-off already-off, reject-after-approve 409, revoke-vs-cancel race (exactly one event), and disabled-preview-403 cases; role-guard pins added (me handlers TECHNICIAN, owner controller class-level OWNER); the vacuous `'values'` repository assertion replaced with real parameterisation counts; the empty-span transition assertion pins the code; the unused `daterangeFor` helper removed.

**Deferred (3):** list pages do N+1 span-fact reads (bounded and correct; batch when FE 17-6 fixes the real query shape); a future-effective-disable journey probe (needs a re-enrolment dance; the sweep filter is unit-pinned); exact-message pins e2e (unit pins the wording the FE renders).

**Dismissed (2, with reasons):** `GET /attendance/me/leave` returning `employeeName` (the caller's own name — no leak, additive to the contract, FE 17-6 may use it); a "weekend-span" probe 1 variant (the workingDays math is pinned by the mixed-range probes; a weekend assertion would be date-dependent on the run day).

**Final:** unit 81 suites / 1278 tests; real-DB e2e 21 suites / 425 tests (26-probe journey); typecheck clean; migration + corrective FK apply verified live.
