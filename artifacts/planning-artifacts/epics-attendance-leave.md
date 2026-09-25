---
stepsCompleted: [1, 2, 3, 4]
inputDocuments:
  - artifacts/planning-artifacts/prds/prd-Fenzo-attendance-2026-09-25/prd.md
  - artifacts/planning-artifacts/prds/prd-Fenzo-attendance-2026-09-25/addendum.md
  - artifacts/planning-artifacts/ux-designs/ux-Fenzo-2026-09-25-attendance-leave/DESIGN.md
  - artifacts/planning-artifacts/ux-designs/ux-Fenzo-2026-09-25-attendance-leave/EXPERIENCE.md
  - artifacts/planning-artifacts/architecture/architecture-attendance-leave-2026-09-25/ARCHITECTURE-SPINE.md
---

# Fenzo - Epic Breakdown (Attendance & Leave)

## Overview

This document provides the epic and story breakdown for the **Attendance & Leave** module — a new, optional module spanning `fenzit-be` (backend) and `fenzo-app` (frontend), decomposing the finalized PRD (FR-1–FR-28, NFR-1–NFR-12), UX design contract (DESIGN.md/EXPERIENCE.md) and architecture spine (AD-1–AD-26) into implementable stories.

## Requirements Inventory

### Functional Requirements

FR-1: Owner enables the module via a 5-step guided wizard (Offices → Timings/hours → Weekly off → Holidays [skippable] → Employees); progress persists server-side and resumes; can't finish without ≥1 Office and ≥1 Tracked employee, each with an Office.
FR-2: Owner enables/disables attendance per Employee or in bulk, with a start date (today or future); pre-start dates show Not tracked; disabling keeps history read-only; re-enabling starts a new tracked period.
FR-3: Employee attendance entry-point has four states (none/upcoming/active/history_only); Owner always sees the entry point; notifications bell always visible regardless of state.
FR-4: First-entry onboarding shows intro + location-permission request + Office/timings summary; denied permission still allows viewing records/applying leave; shown once, summary stays reachable later.
FR-5: Owner manages Offices (create/edit/archive): pin via current-location/address-search/drag-pin (one map screen, live radius circle), Radius 50–1000m (default 100), Start/End time, Late cut-off 0–120min (default 15), Full/Half-day hours (default 8/4); timing changes apply from tomorrow; can't archive with Tracked employees assigned.
FR-6: Owner assigns/reassigns each Tracked employee to exactly one Office, effective today or a future date (tomorrow if already checked in today); past records keep the old Office.
FR-7: Employee checks in once/day inside Office radius, with server-side distance/accuracy/fake-GPS validation, rate limiting (5 rejections/10min → 10min block), DB-guaranteed idempotent single check-in; Late flag past Expected-start+cutoff; holiday/weekly-off check-in needs confirmation.
FR-8: Employee checks out once/day (after check-in), same location/idempotency rules; Early-checkout flag before Expected end; shows Worked hours.
FR-9: Check-in on a full-day leave date requires confirmation, then auto-cancels that date's leave (Owner notified); no auto-cancel on Half-day leave check-in.
FR-10: Single server-side 10-rule priority algorithm computes exactly one Day status per Tracked-employee-date; corrections always win; live recalculation, including past dates (no month lock).
FR-11: Days worked is a server-computed decimal sum per period (Present=1, Half day=0.5, etc.); Worked-on-holiday counted separately; Owner/Employee totals always match.
FR-12: Employee applies for leave (range/single date, full/half day, required reason ≤500 chars); live working-days count; past dates up to 7 days back; rejects off-day-only/overlapping/already-checked-in requests.
FR-13: Owner approves/rejects Pending leave (reason optional on reject); atomic on concurrent actions; Pending never auto-expires.
FR-14: Owner revokes Approved leave for not-yet-started dates (reason required); today revocable only before Office Start time; in-progress leave is split.
FR-15: Employee cancels Pending/Approved leave for not-yet-started dates, same cutoff/split rules as Revoke, no reason required.
FR-16: Owner applies leave on behalf of an Employee, approved immediately, same validation as FR-12; revocable like any Approved leave.
FR-17: Both Employee and Owner see full leave history/status; Owner sees a Pending queue.
FR-18: Owner sets tenant default Weekly-off (default Sunday, any combination), effective-dated; ≥1 working day/week must remain.
FR-19: Owner sets per-Employee Weekly-off override (wins over default), effective-dated, removable.
FR-20: Owner manages Holidays (date+name, add/edit/remove incl. past); recomputes affected Day statuses live; overlap with Approved leave warns Owner and notifies Employee.
FR-21: Owner corrects attendance for any date (times or direct status) with a required note; full audit trail; corrections skip location checks and always win over later recalculation.
FR-22: Defined Notification events (leave lifecycle, fake-location repeats, holiday changes) fire atomically with their state change; seen only when app opened (no push in v1).
FR-23: Scheduled Reminders (missed check-in/out, Owner's daily not-checked-in summary per Office, daily pending-leave summary at 10 AM) — DB-deduped, once per recipient/day/type.
FR-24: Owner dashboard shows today's snapshot (counts + persistent Checkout-missing/Fake-location flags), filterable by Office.
FR-25: Owner monthly view — Tracked-employee list with month summary, filterable by Office; tap opens per-date calendar + Day-detail sheet; every status/flag pairs icon + label.
FR-26: Employee self-view — own calendar, today's state, month summary, weekly offs, holidays, leave history; server-enforced own-data-only.
FR-27: Every technician gets the existing Owner notifications inbox generalized to be role-aware (same screen/backend); bell/badge visible to all technicians from day one.
FR-28: (Future-ready) Removed technician: attendance auto-off from removal date, history kept, pending/future leave auto-cancelled (no notification), reminders stop.

### NonFunctional Requirements

NFR-1: Tenant isolation & least privilege — deny-by-default RLS, server-side ID re-validation, no service-role key in app; includes fixing the existing job-RPC EXECUTE/`users_update_own` gap as a prerequisite.
NFR-2: Server authority — all rules/timestamps/status computed server-side, never trusted from client.
NFR-3: Atomicity & idempotency — state change + notification atomic; idempotency key required on check-in/out/leave; concurrent same-employee actions serialized.
NFR-4: Integrity constraints — DB-enforced uniqueness/no-overlap/valid-range constraints.
NFR-5: Timezone — tenant IANA timezone (default Asia/Kolkata), UTC storage, server-computed "today", 12-hour display.
NFR-6: Auditability — corrections/leave transitions recorded with actor/time/reason, never hard-deleted.
NFR-7: Performance — check-in/out ≤2s p95; monthly view (50 employees) ≤3s p95.
NFR-8: Resilience — clear offline/timeout/GPS-failure messages with retry; loading skeletons everywhere.
NFR-9: Observability — rejections/reminder-job runs logged as metrics; no raw coordinates in logs.
NFR-10: Push-ready — stable event types + self-contained payloads, push waves predefined, no logic change needed later.
NFR-11: Privacy — location captured only at check-in/out moment, never background-tracked.
NFR-12: Module separation — own entry points/screens/nav/routes/tables/event-types in both repos; job flow untouched; only design-system, location-permission helper and notifications list may be reused/generalized.

### Additional Requirements

- DB-centric domain core: Postgres owns all rules via SECURITY DEFINER RPCs (EXECUTE revoked from PUBLIC/anon/authenticated); NestJS is a thin shell (AD-1, AD-2, AD-3).
- New Postgres extension: `btree_gist`, for non-overlapping effective-dated ranges (AD-8).
- Two-level advisory-lock serialization (tenant + employee) on every attendance/leave RPC and the reminder job (AD-5).
- Idempotency via unique DB constraints (`request_id`, `(employee_id, work_date)`) — not the generic `IdempotencyInterceptor` (AD-6).
- Fixed check-in/out outcome→ErrorCode→HTTP catalogue; rejections never `RAISE`, always committed as attempt rows (AD-4).
- New tables: `attendance_settings`, `attendance_setup_progress`, `attendance_offices`, `attendance_office_rules`, `attendance_enrolments`, `attendance_office_assignments`, `attendance_weekly_off_defaults/overrides`, `holidays`, `attendance_attempts`, `attendance_records`, `attendance_day_overrides`, `attendance_corrections`, `leave_requests`, `leave_request_days`, `leave_events`, `attendance_onboarding`; additive columns on `notifications`.
- Key SQL functions: `attendance_day_context` (AD-22), `attendance_day_statuses` (AD-10), `leave_transition_days` (AD-23), `attendance_today`, `attendance_access`, preview functions (`leave_preview`, `leave_action_preview`, `attendance_holiday_impact`, `attendance_office_archive_blockers`), lock helpers `attendance_lock_tenant`/`attendance_lock_employee`.
- pg_cron: `attendance_run_reminders()` every 5 min + daily prunes of `cron.job_run_details` and rejected-attempt coordinates (AD-14, AD-26).
- **Security prerequisite story** (must merge before FR-27's realtime token and before the frontend release): revoke public EXECUTE on job RPCs, column-limit `users_update_own` (AD-18).
- New frontend deps: `react-native-maps` 1.29.8 (pinned) + `@react-native-community/netinfo` 12.0.1.
- A throwaway map spike (draggable Marker + onDragEnd, live Circle update, MapView.onPress) must pass before the office-picker story is built.
- New attendance-only location capture contract in `services/location`, separate from and non-disruptive to the existing job geolocation helper (AD-20).
- Fixed release order: (1) AD-18 security prerequisites, (2) fenzit-be attendance migrations + API, (3) fenzo-app.
- RLS: SELECT-only deny-by-default on every new table (owner: own tenant; technician: own rows), no write policies — all writes through SECURITY DEFINER RPCs (AD-16).
- Test requirement: extend `test/integration/rls-isolation.integration.spec.ts` with a direct-call probe for every new `attendance_*`/`leave_*` function; measure NFR-7 at 50 employees × 31 days in the integration suite before considering materialized day-status as a fallback.

### UX Design Requirements

UX-DR1: Extend the existing `Badge`/status-colour system with 12 new Day-status keys mapped onto the 5 existing hue families — no new colours, `tone="soft"` only; icon-distinctness must be visually verified at real render size (12px in calendar cells) across all same-hue pairs before build.
UX-DR2: Build a new `CheckInOutButton` component with 10 distinct states (ready-to-check-in/out, pre-flight confirm, resolving, blocked-with-reason, GPS-timeout, rate-limited-with-countdown, precise-location-off, permission-denied, done-today) — pessimistic UI only, never optimistic.
UX-DR3: Build a new full-screen Office map picker (`react-native-maps`) — draggable pin, live-updating geofence radius circle, 3 equivalent entry paths (current location/address search/drag), map-unavailable fallback, accessible non-visual equivalents (announcing radius slider, editable text/address pin fallback).
UX-DR4: Build a new `MonthCalendar` component — 7-column grid, icon-only status glyph per cell (~40px tap area), today outlined in primary colour, tap-through to a Day Detail sheet with full (not just latest) correction history.
UX-DR5: Generalize the existing `ReportSkeleton` into a shared `components/ui/Skeleton` used across all attendance lists/calendars.
UX-DR6: Reuse the existing `AuthFlow`/`StepIndicator` pattern for a server-resumable 5-step setup wizard, blocking the final "Enable attendance" action client-side until ≥1 Office and ≥1 assigned Employee exist (matching the server rule 1:1).
UX-DR7: Generalize the notifications experience into a role-aware shared inbox (no second inbox), an event-type registry (card, deep link, stores-to-refetch), and a role-agnostic realtime bridge; 4th "Attendance" tab and bell badge visible to every technician regardless of tracked state.
UX-DR8: Add offline detection (NetInfo) — blocking pre-check-in message, read-only offline banner for calendars/history (no offline queue).
UX-DR9: Enrolment/bulk-enable UI must never let a switch visually commit to "on" without an assigned Office (opens the office picker inline immediately); one-tap future start-date field (defaults to today).
UX-DR10: Leave apply form composed entirely from existing components with a live "X working days" recalculation; all 5 rejection cases surfaced inline on submit, never by pre-disabling the button.
UX-DR11: Revoke/Cancel sheets must show the computed split outcome (which dates stay vs change) to the acting user before they confirm.
UX-DR12: Accessibility floor — render a real-size throwaway calendar month covering all 12 statuses before build to verify icon distinctness; screen-reader announces date+status together and count+label on flag strips; weekly-off day pills carry distinct full accessible labels even where two pills share a visible letter.

### FR Coverage Map

FR-1: Epic 15 — setup wizard
FR-2: Epic 15 — enable/disable per employee or bulk
FR-3: Epic 15 — entry-point states
FR-4: Epic 15 — employee onboarding
FR-5: Epic 15 — office management + map picker
FR-6: Epic 15 — office assignment/reassignment
FR-7: Epic 16 — check-in
FR-8: Epic 16 — check-out
FR-9: Epic 17 — check-in on a leave day (moved from Epic 16 during story design: FR-9's auto-cancel needs `leave_transition_days`, which only exists once Epic 17 builds the leave data model — see note under Epic 17)
FR-10: Epic 18 — day status engine
FR-11: Epic 18 — days worked calculation
FR-12: Epic 17 — apply for leave
FR-13: Epic 17 — approve/reject leave
FR-14: Epic 17 — revoke leave
FR-15: Epic 17 — cancel leave
FR-16: Epic 17 — leave on behalf
FR-17: Epic 17 — leave history/status
FR-18: Epic 15 — tenant weekly off
FR-19: Epic 15 — per-employee weekly off override
FR-20: Epic 15 — holidays
FR-21: Epic 18 — attendance corrections
FR-22: satisfied incrementally inside Epics 15, 16 and 17 (each owning RPC inserts its own notification atomically, per AD-13) — not a standalone epic
FR-23: Epic 19 — reminders
FR-24: Epic 19 — owner dashboard
FR-25: Epic 19 — owner monthly view
FR-26: Epic 19 — employee self view
FR-27: Epic 14 — technician notification inbox
FR-28: satisfied by design in Epics 15 and 17 — no dedicated story (no removal feature exists yet)

## Epic List

### Epic 14: Security Prerequisite & Technician Notification Access
Every technician gets a working, real-time notification bell for the first time — the same inbox the Owner already has, made role-aware — ready to receive attendance/leave alerts the moment later epics start emitting them. First story is the NFR-1 security fix (revoke public EXECUTE on job RPCs, column-limit `users_update_own`), which architecture (AD-18) requires to merge before this epic's realtime token work.
**FRs covered:** FR-27

### Epic 15: Attendance Setup — Offices, Rules, Weekly Offs, Holidays & Enrollment
Owner can fully turn on and configure the module: add Offices with geofencing, set timing/hours rules, tenant + per-employee weekly offs, holidays, and enroll/assign employees via the setup wizard. Employees see the correct entry-point state and complete onboarding.
**FRs covered:** FR-1, FR-2, FR-3, FR-4, FR-5, FR-6, FR-18, FR-19, FR-20
*(Includes the holiday-change and weekly-off-change notifications as part of their own stories here, per AD-13.)*

### Epic 16: Check-in & Check-out
Tracked employees mark genuine, geofenced daily attendance in a few seconds; the Owner can trust every check-in because fake-GPS, distance and rate-limit checks all happen server-side.
**FRs covered:** FR-7, FR-8
*(Includes the fake-location-repeat notification as part of its story. FR-9, originally scoped here, moved to Epic 17 — see note below.)*
Depends on: Epic 15 (offices/enrollment must exist).

### Epic 17: Leave Management
Employees apply for leave (full or half day, past or future); Owners approve, reject, revoke or apply it on their behalf — with a complete, dispute-free history for both sides. Also covers FR-9 (check-in on a leave day), moved here from Epic 16 during story design, because the auto-cancel behaviour is written by `leave_transition_days`, the single leave-state writer this epic builds — it cannot exist before the leave data model does.
**FRs covered:** FR-9, FR-12, FR-13, FR-14, FR-15, FR-16, FR-17
*(Includes all leave-lifecycle notifications as part of their stories.)*
Depends on: Epic 15 (weekly-offs/holidays for working-day math) and Epic 16 (check-in must exist so FR-9's confirm-and-cancel flow has something to hook into).

### Epic 18: Day Status, Days Worked & Attendance Corrections
Every tracked day gets exactly one accurate, computed status and a running Days-worked total that Owner and Employee both see identically; the Owner can correct mistakes with a full, visible audit trail.
**FRs covered:** FR-10, FR-11, FR-21
Depends on: Epic 16 (check-in records) and Epic 17 (leave state) — the FR-10 priority order reads both.

### Epic 19: Reminders & Consolidated Views
Owner gets a live daily dashboard and a monthly consolidated report per employee with drill-down to a day calendar; Employee gets the same picture for themselves; both get automatic reminders so nobody has to remember to check back.
**FRs covered:** FR-23, FR-24, FR-25, FR-26
Depends on: Epics 14–18 (needs check-in, leave, day status and notification infra all present to summarize/remind on).

**Note on FR-28:** no dedicated story — there's no remove-technician feature to build yet. It's already satisfied by design (the effective-dating algorithm in Epic 15 and the leave-transition writer in Epic 17).

**Note on epic reordering:** the epic list approved in Step 2 had Epic 17 = Day Status and Epic 18 = Leave. While breaking Epic 16 into stories, a hard dependency surfaced — FR-9 (check-in on a leave day) needs the leave data model to exist first — so Leave Management and Day Status were swapped (Leave is now Epic 17, Day Status is now Epic 18) and FR-9 moved from Epic 16 to Epic 17. This keeps every epic dependent only on strictly earlier epics.

## Epic 14: Security Prerequisite & Technician Notification Access

Every technician gets a working, real-time notification bell for the first time — the same inbox the Owner already has, made role-aware — ready to receive attendance/leave alerts the moment later epics start emitting them.

### Story 14.1: Revoke public EXECUTE on job RPCs and column-limit `users_update_own` (Backend)

As a **backend engineer**,
I want the existing job RPCs' public EXECUTE grant revoked and the `users_update_own` RLS policy column-limited,
So that opening a realtime token to technicians in Story 14.3 doesn't also hand them a wider write surface than intended.

**Acceptance Criteria:**

**Given** the existing job RPCs (e.g. `advance_workflow_step` and any other job RPC currently callable with the app's public/anon or authenticated key)
**When** the migration for this story runs
**Then** `EXECUTE` on those RPCs is revoked from `PUBLIC`, `anon` and `authenticated`, and they remain callable only via the service-role (admin) client
**And** existing job flows (advance workflow, sync) continue to work unchanged end-to-end (verified by existing job integration tests passing)

**Given** the `users_update_own` RLS policy today allows an authenticated user to update any column on their own row
**When** the migration runs
**Then** the policy is column-limited so a user can update only the columns already intended for self-service (e.g. profile fields), and can no longer alter `role`, `tenant_id` or other privileged columns via a direct client update
**And** a new RLS spec probe (in `test/integration/rls-isolation.integration.spec.ts`) directly attempts a privileged-column update as an authenticated technician token and asserts it is rejected

**Given** this is a prerequisite from `deferred-work.md`
**When** this story merges
**Then** `deferred-work.md` is updated to mark both items resolved, with a reference to this story/migration

### Story 14.2: Generalize the notifications backend for technicians (Backend)

As a **technician**,
I want the backend to support delivering notifications to me directly (not just the Owner),
So that attendance/leave features in later epics have a role-aware channel to notify me through.

**Acceptance Criteria:**

**Given** the `notifications` table and its existing `job_id` (nullable) column
**When** this story's migration runs
**Then** additive nullable `entity_type`, `entity_id` and `dedupe_key` columns are added, plus a partial unique index on `dedupe_key`
**And** no existing job or report notification row or query is affected (verified by existing notification tests passing unchanged)

**Given** `GET /auth/realtime-token` today issues tokens only to Owners
**When** a technician (authenticated, valid JWT) calls this endpoint, and Story 14.1 has already merged
**Then** the technician receives a realtime token scoped only to their own topic (`user:<id>:notifications`)
**And** a technician cannot subscribe to another user's topic, or to the tenant-wide owner topic, even with a crafted request (covered by an RLS/integration test)

**Given** the notifications list/unread-count/mark-read endpoints are today implicitly owner-oriented
**When** a technician calls them
**Then** they return only that technician's own notifications, with the same shape (`entityType`/`entityId` included) as the Owner gets
**And** `NotificationResponse` DTOs are updated additively (no breaking change to existing Owner-facing fields)

### Story 14.3: Technician notification bell, badge & role-aware inbox (Frontend)

As a **technician**,
I want a notification bell with an unread badge and a working inbox screen,
So that I can see my own alerts the same way the Owner already sees theirs — even before any attendance features exist.

**Acceptance Criteria:**

**Given** the existing tab bar has no notification entry point for technicians today
**When** a technician opens the app after Story 14.2 has shipped
**Then** the notifications bell (with unread badge) is visible to every technician, regardless of attendance/tracked status
**And** tapping it opens the existing notifications screen, generalized to be role-aware, rather than a second/new inbox

**Given** the technician has zero notifications
**When** they open the inbox
**Then** they see the existing `EmptyState` ("No notifications yet") — unchanged copy from the Owner's empty state

**Given** `OwnerRealtimeBridge`, `useOwnerNotifications` and `StatusBanner` are today owner/job-specific
**When** this story ships
**Then** they are generalized to be role-agnostic (per AD-19), so a technician's realtime subscription works identically to the Owner's, without duplicating the bridge code
**And** existing Owner job/report notification behavior is verified unchanged (regression check)

**Given** no attendance/leave events exist yet at this point in the build
**When** a technician's inbox is empty of attendance content
**Then** nothing in this story renders placeholder or fake attendance data — the inbox is simply ready to receive real events from later epics

**Epic 14 summary:** 3 stories (2 backend, 1 frontend). Covers FR-27 in full, plus the NFR-1 security prerequisite that gates it.

## Epic 15: Attendance Setup — Offices, Rules, Weekly Offs, Holidays & Enrollment

Owner can fully turn on and configure the module: add Offices with geofencing, set timing/hours rules, tenant + per-employee weekly offs, holidays, and enroll/assign employees via the setup wizard. Employees see the correct entry-point state and complete onboarding.

### Story 15.1: Map library spike — validate drag pin and live radius circle (Frontend, technical spike)

As a **frontend engineer**,
I want to validate `react-native-maps` 1.29.8 on RN 0.87.1 Fabric before building the real Office map picker,
So that the office-picker story (2.4) isn't blocked mid-build by a library limitation.

**Acceptance Criteria:**

**Given** a disposable spike screen using `react-native-maps` on both Apple Maps (iOS) and Google Maps (Android)
**When** a default-pin draggable `Marker` is dragged and released
**Then** `onDragEnd` fires and updates the pin position with no custom child views required

**Given** the same spike screen
**When** the radius value changes (via a slider or stepper)
**Then** a `Circle`'s centre and radius redraw live with no visible lag or stale frame

**Given** a tap anywhere on the map
**When** `MapView.onPress` fires
**Then** the pin moves to the tapped location (this is the primary interaction, since Android drag needs a long-press first)

**Given** the Circle does not redraw correctly on either platform
**When** this is discovered during the spike
**Then** it is re-keyed (forcing a fresh mount) as the documented workaround, and this finding is recorded for Story 15.4

### Story 15.2: Attendance module foundation — timezone, settings & setup gating (Backend)

As an **owner**,
I want to start the attendance setup wizard and have my progress saved automatically,
So that I never lose setup progress if I close the app or switch devices.

**Acceptance Criteria:**

**Given** a tenant with no `timezone` set
**When** this story's migration runs
**Then** `tenants.timezone` is added (`TEXT NOT NULL DEFAULT 'Asia/Kolkata'`), validated by a trigger against `pg_timezone_names` (PT422 on an invalid name, not a CHECK constraint)

**Given** the attendance module does not exist yet
**When** this story ships
**Then** `attendance_settings` (per-tenant, `enabled` kill switch, `setup_completed_at`) and `attendance_setup_progress` (current wizard step) tables exist, along with `attendance_today(p_tenant_id)`, `attendance_lock_tenant(tenant_id, exclusive bool)` and `attendance_lock_employee(employee_id)` helpers (AD-5, AD-7)

**Given** an Owner completes the wizard's steps
**When** `attendance_complete_setup` is called
**Then** it succeeds only if at least one Office and one tracked Employee (with an assignment) exist, and sets `setup_completed_at`; before that, `attendance_access` (built in Story 15.7) reports nobody as tracked

**Given** all attendance functions created in this story
**When** their grants are inspected
**Then** every one is `SECURITY DEFINER SET search_path = public` with `EXECUTE` revoked from `PUBLIC, anon, authenticated` (AD-3), and a probe exists in `test/integration/rls-isolation.integration.spec.ts`

### Story 15.3: Offices & office rules (Backend)

As an **owner**,
I want to create, edit and archive Offices with their location, radius and timing rules,
So that check-in/out (Epic 16) has somewhere to validate against.

**Acceptance Criteria:**

**Given** the `btree_gist` extension is not yet enabled
**When** this story's migration runs
**Then** it is enabled, and `attendance_offices` (name, pin lat/lng, radius) and `attendance_office_rules` (effective-dated: start/end time, late cut-off, full/half-day hours) are created with the AD-8 non-overlap exclusion constraint

**Given** an Owner creates an Office with radius 100m, start 10:00, end 18:00, late cut-off 15min, full-day 8h, half-day 4h
**When** the create RPC runs
**Then** the row is saved with those defaults validated (radius 50–1000, late cut-off 0–120, half-day hours < full-day hours, end time after start time, both same-day)

**Given** an Owner edits an Office's timing/hours rules today
**When** the edit RPC runs
**Then** the new rule takes effect from tomorrow (AD-8 algorithm), and all past dates keep whatever rule was active on that date

**Given** an Office still has currently-Tracked employees assigned
**When** an Owner calls the archive RPC
**Then** it is rejected with the list of blocking employees (via `attendance_office_archive_blockers`, AD-24); once reassigned, archiving succeeds and sets `archived_at` (never a hard delete)

### Story 15.4: Office management UI with map picker (Frontend)

As an **owner**,
I want to add and edit Offices using a map to place the pin and see the geofence radius,
So that I can set up accurate check-in boundaries without guessing coordinates.

**Acceptance Criteria:**

**Given** the Office list/add/edit screens
**When** an Owner taps to set a pin
**Then** a full-screen map opens with three equivalent entry paths (current location, address search reusing the existing Address Autosuggest screen, drag pin) — per the Story 15.1 spike findings, tap-to-place is the primary path since Android drag needs a long-press

**Given** the Owner adjusts the radius stepper/slider on the map screen
**When** the value changes
**Then** the geofence circle (`colors.primary` stroke, soft fill) redraws live with no separate "preview" step (UX-DR3)

**Given** the map fails to load (no network or a map error)
**When** the Owner is on the picker screen
**Then** current-location and address-search still work, and the map area shows a plain "Map unavailable" message instead of freezing or erroring silently

**Given** an Owner tries to archive an Office with employees still assigned
**When** the archive action is blocked by the backend
**Then** the UI shows the blocking employee count with a shortcut into the Employees list filtered to that Office, not a dead-end error

### Story 15.5: Weekly offs & holidays (Backend)

As an **owner**,
I want to set the tenant's default weekly off days, per-employee overrides, and holidays,
So that the system knows which days are non-working before any day-status logic runs.

**Acceptance Criteria:**

**Given** no weekly-off default exists yet
**When** an Owner sets the tenant default to Saturday + Sunday effective today
**Then** `attendance_weekly_off_defaults` (effective-dated, AD-8) stores it, and the RPC rejects a selection leaving zero working days in the week (FR-18)

**Given** a per-employee weekly-off override
**When** an Owner sets or removes one
**Then** `attendance_weekly_off_overrides` stores it effective-dated, and removing it reverts that employee to the tenant default from the chosen date (FR-19)

**Given** an Owner adds a Holiday on a date that falls inside an Employee's Approved leave
**When** the holiday-add RPC runs
**Then** `holidays` (`UNIQUE (tenant_id, holiday_date)`) stores the row, `attendance_holiday_impact` (AD-24) correctly identifies the affected employee(s) beforehand for the UI warning, and a notification is sent to the affected Employee(s) in the same transaction (AD-13)

**Given** an Owner removes a Holiday that falls inside a Leave request's range
**When** the removal RPC runs
**Then** that date becomes Leave again (the leave request's stored range is unchanged — leave-counting is computed on read, not stored), and the affected Employee is notified

### Story 15.6: Weekly off & holiday settings UI (Frontend)

As an **owner**,
I want screens to manage weekly offs and holidays,
So that I can configure them outside the setup wizard too, any time.

**Acceptance Criteria:**

**Given** the tenant-default weekly-off screen
**When** an Owner tries to save a selection with zero working days left
**Then** the screen blocks the save with an inline message, mirroring the backend rule (FR-18)

**Given** the per-employee override list
**When** an Owner opens an employee's override row
**Then** they see the same 7-day-pill + effective-date pattern plus an explicit "Remove override" action (not just silently deleting the row)

**Given** the holidays list (Upcoming/Past grouping)
**When** an Owner adds or removes a date that overlaps an employee's approved leave
**Then** an inline amber warning names the affected employee(s) before they confirm — informational, not a hard block

### Story 15.7: Enrollment, office assignment & access state (Backend)

As an **owner**,
I want to enable/disable attendance per employee (or in bulk) and assign each to an Office,
So that only the right employees see attendance UI, from the right start date.

**Acceptance Criteria:**

**Given** `attendance_enrolments` and `attendance_office_assignments` (both effective-dated, AD-8) do not exist yet
**When** this story's migration runs
**Then** they are created with a constraint trigger ensuring every enrolled date is covered by exactly one office assignment

**Given** an Owner enables an Employee with a future start date (e.g. 1 Nov, before they've ever logged in)
**When** the enable RPC runs
**Then** the enrolment and assignment are created effective from that date; dates before it read as `Not tracked`, not `Absent`, and the Employee doesn't appear in Owner not-checked-in summaries until then

**Given** an Employee is enabled today after today's Office Start time
**When** `attendance_access` / day-status logic (built in Epic 18) later reads this date
**Then** today is `Not tracked` unless the Employee actually checks in today (FR-2's grace rule) — this story stores the `enabled_at` timestamp so that later logic can apply the rule

**Given** `attendance_access(p_tenant_id, p_user_id)` and `GET /api/v1/attendance/me/access`
**When** an Employee's enrolment changes
**Then** the function returns the correct one of `none | upcoming | active | history_only`, plus `attendanceStartDate` and `onboardedAt`, and `/users/me` exposes the same four fields for first load (AD-17)

### Story 15.8: Setup wizard (Frontend)

As an **owner**,
I want a guided 5-step wizard to turn on Attendance & Leave,
So that I don't have to hunt through separate settings screens to get started.

**Acceptance Criteria:**

**Given** the Owner has never run the wizard
**When** they open the Attendance entry point
**Then** it opens the wizard directly (not an empty dashboard), reusing the existing `AuthFlow`/`StepIndicator` shell (UX-DR6), five steps: Offices → Timings & hours → Weekly off → Holidays (skippable) → Employees

**Given** the Owner completes a step
**When** they move to the next one
**Then** that step's data is already persisted server-side (Story 15.2's `attendance_setup_progress`); closing the app and reopening resumes at the last incomplete step with no re-entry of earlier steps

**Given** no Office exists yet, or a selected Employee has no Office assigned
**When** the Owner reaches the final "Enable attendance" action
**Then** it stays disabled client-side, matching the server rule 1:1 (no submit-then-fail round trip)

**Given** a network drop while a step is being persisted
**When** this happens
**Then** the step's own screen shows an inline retry banner; the wizard doesn't advance and doesn't lose what was entered

### Story 15.9: Employee enrollment & reassignment UI (Frontend)

As an **owner**,
I want to bulk-enable/disable employees and reassign their Office from a settings screen (outside the wizard),
So that I can manage the team as it changes over time, not just during initial setup.

**Acceptance Criteria:**

**Given** the enrolment rows list (existing `Switch` + `TechnicianPicker` row style, UX-DR9)
**When** an Owner toggles an employee's switch to "on" without an Office picked
**Then** the office-assignment picker opens inline for that row immediately, and the switch does not visually commit to "on" until an Office is chosen

**Given** the start-date field on an enrolment row
**When** an Owner leaves it untouched
**Then** it defaults to today; picking a future date is one tap away via a small "Starts today" link that expands into a date picker

**Given** an Employee has already checked in today
**When** an Owner reassigns their Office
**Then** the effective-date field is pre-filled to tomorrow and today is disabled with an inline note ("Already checked in today — this takes effect from tomorrow")

### Story 15.10: Employee onboarding & entry-point states (Frontend)

As a **tracked employee**,
I want a short first-time intro and to see accurate attendance access states,
So that I understand what's expected of me and never see a stale or flickering entry point.

**Acceptance Criteria:**

**Given** a Tracked employee's first entry into the Attendance tab
**When** they open it
**Then** they see a short intro, a location-permission request, and a summary (Office, Start/End time, Late cut-off, Weekly offs); this shows once, but the summary stays reachable later

**Given** `attendanceAccess` is `upcoming`
**When** the Employee opens the Attendance tab
**Then** they see "Attendance starts on {date}" with Office/timings/weekly-offs, can complete onboarding early, but see no check-in control at all (absent, not disabled)

**Given** `attendanceAccess` is `none`
**When** an untracked technician opens the app
**Then** there's no 4th tab and no attendance UI anywhere — but the notifications bell (Epic 14) is still visible

**Given** an attendance notification arrives, or the app returns to foreground
**When** either happens
**Then** `attendanceAccess` is refetched so the tab/entry point never flickers or goes stale (AD-17)

**Epic 15 summary:** 10 stories (1 spike, 4 backend, 5 frontend). Covers FR-1, FR-2, FR-3, FR-4, FR-5, FR-6, FR-18, FR-19, FR-20 in full.

## Epic 16: Check-in & Check-out

Tracked employees mark genuine, geofenced daily attendance in a few seconds; the Owner can trust every check-in because fake-GPS, distance and rate-limit checks all happen server-side.

### Story 16.1: Check-in RPC, day-context helper & attempt logging (Backend)

As a **tracked employee**,
I want to check in once I'm at my Office,
So that my attendance for today is recorded accurately and I can't be disputed.

**Acceptance Criteria:**

**Given** the internal helper `attendance_day_context` does not exist yet
**When** this story ships
**Then** it is built (AD-22) returning, per employee-date: tracked/not, office/rules, start/end, midpoint, cut-off, weekly-off/holiday flags, working-day flag, and leave state — and this is the **only** place any of these facts are computed; check-in, and all later epics, read from it exclusively

**Given** an Employee inside their Office radius with a valid GPS fix
**When** they call `POST /attendance/me/check-in` with `X-Idempotency-Key`
**Then** `attendance_check_in()` takes the shared tenant lock then the employee lock (AD-5), computes distance server-side, and on success inserts one `attendance_records` row snapshotting `office_id`, `office_rules_id`, server timestamp, lat/lng, accuracy, distance, `mocked`, `provider` (AD-9) — never trusting the device clock

**Given** the distance exceeds the Office radius, accuracy is worse than 100m, or the location is flagged `mocked`
**When** check-in is attempted
**Then** the RPC does not `RAISE` — it records the attempt row and returns a committed outcome (`too_far` / `low_accuracy` / `mocked`), which the service maps to the AD-4 catalogue (422 with `distanceM`/`radiusM` where relevant)

**Given** 5 counted rejections (too_far/low_accuracy/mocked/stale_fix) occur within 10 minutes for the same employee
**When** the 5th one lands
**Then** `blocked_until` is set (that attempt's time + 10 min); further attempts return `rate_limited` (429 + `Retry-After`) until the window passes (AD-15)

**Given** an Employee has 3 or more `mocked` attempts in a calendar month
**When** the 3rd one is recorded
**Then** the Owner receives a Notification, deduped via `fake_location:<employee_id>:<yyyy-mm>` (AD-13) — sent exactly once for the month

**Given** a repeated request with the same idempotency key
**When** it is replayed
**Then** the stored outcome/result is returned with no second attempt row or side effect (`UNIQUE (tenant_id, request_id)`, AD-6); a second check-in on the same day is rejected via `UNIQUE (employee_id, work_date)`

**Given** today is a Weekly off or Holiday (no leave involved)
**When** an Employee checks in
**Then** the RPC allows it (it will read as `Worked on holiday` once Epic 18's day-status function exists) — the app-side confirmation dialog for this is built in Story 16.4

### Story 16.2: Check-out RPC (Backend)

As a **tracked employee**,
I want to check out once I've finished for the day,
So that my worked hours are recorded.

**Acceptance Criteria:**

**Given** an Employee has checked in today but not checked out
**When** they call `POST /attendance/me/check-out` from inside the Office radius with a valid fix
**Then** `attendance_check_out()` applies the same location/accuracy/fake-GPS/idempotency rules as check-in (Story 16.1), and stores the check-out timestamp/lat/lng/accuracy/distance on the same `attendance_records` row

**Given** the check-out happens before Expected end (or before the Midpoint on a Second-half leave day)
**When** the RPC evaluates it
**Then** the response includes an `earlyCheckout` flag with the minutes early, computed via `attendance_day_context`

**Given** an Employee has not checked in today
**When** they attempt to check out
**Then** the RPC returns `not_checked_in` (409), never a generic error

**Given** a successful check-out
**When** the response returns
**Then** it includes the Worked hours (checkout time minus check-in time) for the app to display immediately

### Story 16.3: Attendance-only location capture service (Frontend)

As a **frontend engineer**,
I want a dedicated, high-accuracy location capture contract for attendance,
So that check-in/out never reuses the job flow's cached, lower-accuracy fix, and the job flow is never affected by attendance's stricter rules.

**Acceptance Criteria:**

**Given** `react-native-nitro-geolocation` 1.4.3 (pinned) exposes `mocked`/`provider`
**When** `services/location`'s new attendance capture function is called
**Then** it requests `{accuracy: {android: 'high', ios: 'best'}, maximumAge: 0, timeout: 15000}` and returns `{ latitude, longitude, accuracyM, mocked, provider, fixAgeMs }` — never a cached fix (AD-20)

**Given** the existing job flow's `technicianApp/geolocation.ts` compat helper
**When** this story ships
**Then** it is left completely unchanged — attendance gets its own function, not a shared one with different parameters

**Given** the OS reports "Approximate"/"Precise off" location
**When** this state is detected
**Then** it's surfaced as its own distinct state, separate from "permission denied" (addendum §C2)

**Given** a GPS fix takes longer than the timeout
**When** this happens
**Then** the service surfaces a distinct timeout state, separate from "low accuracy" (a fix was never obtained here, versus one that was obtained and rejected)

### Story 16.4: CheckInOutButton & Today screen (Frontend)

As a **tracked employee**,
I want one clear button that shows exactly what to do next,
So that checking in and out is a one-tap action I never have to think about.

**Acceptance Criteria:**

**Given** the Today screen with no check-in yet today
**When** it renders
**Then** it shows the full-width `CheckInOutButton` (`cta.height` 56px) reading "Check in", plus a live muted-text distance hint below it (existing `utils/distanceUtils.ts` haversine, display-only per NFR-2)

**Given** today is a Weekly off or Holiday with no leave involved
**When** the Employee taps Check in
**Then** a confirm dialog appears ("It's a holiday. Check in anyway?"); on confirm, the GPS/submit flow proceeds; on dismiss, no request is sent at all

**Given** the button is in the Resolving state (GPS fix + server round-trip)
**When** this is happening
**Then** the button is disabled with a spinner for the entire duration, and the screen never shows "Checked in" before the server confirms (AD-21, no optimistic UI)

**Given** the server returns `too_far`, `low_accuracy`, or `mocked`
**When** the response arrives
**Then** the button returns to Ready state with the exact PRD-specified message shown below it, and retry is immediate

**Given** the server returns `rate_limited`
**When** the response arrives
**Then** the button itself is disabled with a live countdown ("Try again in 9:42") for the remainder of the window — not just an ignorable message

**Given** the Employee has checked in but not out
**When** they view the Today screen
**Then** the button reads "Check out"; after a successful checkout, the button is replaced entirely by a summary card (times + Worked hours) — never both visible at once

**Given** location permission is denied, or precise location is off
**When** the Employee views the Today screen
**Then** the button shows "Turn on location to check in" or "Turn on precise location to check in" respectively — each a distinct state, tapping opens the right remediation flow

**Given** the device is offline (NetInfo `isConnected: false`, added in this story — UX-DR8)
**When** the Employee opens the Today screen or taps Check in/out
**Then** a blocking offline message is shown before any network call is attempted — never a doomed request that times out; read-only screens elsewhere in the app may still show last-loaded data with an offline banner, but there's no offline queue for check-in/out

**Epic 16 summary:** 4 stories (2 backend, 2 frontend). Covers FR-7, FR-8 in full. FR-9 (check-in on a leave day) is covered in Epic 17, once the leave data model exists.

## Epic 17: Leave Management

Employees apply for leave (full or half day, past or future); Owners approve, reject, revoke or apply it on their behalf — with a complete, dispute-free history for both sides. Also closes out FR-9 (check-in auto-cancelling a leave day), which needed this epic's data model to exist.

### Story 17.1: Leave data model & apply (Backend)

As a **tracked employee**,
I want to apply for leave over a date range (or single date), full or half day,
So that my time off is recorded and the Owner can act on it.

**Acceptance Criteria:**

**Given** `leave_requests` and `leave_request_days` do not exist yet
**When** this story's migration runs
**Then** they are created — `leave_requests` holds the range/type/reason/`created_by`/`request_id`; `leave_request_days` holds one row per date with `state ∈ {pending, approved, rejected, cancelled, revoked}`, with a partial unique index on `(employee_id, leave_date) WHERE state IN ('pending','approved')` blocking overlaps

**Given** the internal helper `leave_transition_days` does not exist yet
**When** this story ships
**Then** it is built (AD-23) as the **only** function that ever changes a `leave_request_days` state; it asserts the employee lock is held, transitions every row in the affected span (including off days), appends one `leave_events` audit row, and inserts the AD-13-registry notification for its `p_cause`

**Given** an Employee submits a leave request for Mon–Fri with a reason
**When** `attendance_apply_leave` runs (using `attendance_day_context` from Epic 16 to know which dates are Weekly off/Holiday)
**Then** it creates the `leave_requests` row plus one `leave_request_days` row per date (all Pending), rejects if every date is already off ("These days are already off"), rejects if it overlaps a Pending/Approved request, rejects if a past date already has a check-in, and enforces the 7-day-back limit and the employee's own start-date floor

**Given** the working-day count needs to be shown before submission
**When** the app calls the `leave_preview` read function (AD-24)
**Then** it returns the same working-day count and validation outcome the real apply call would produce — sharing the exact same validation path, not a separate re-implementation

**Given** the reason field
**When** a request is submitted
**Then** it is required, free text, max 500 characters — enforced server-side regardless of what the client sends

### Story 17.2: Approve / reject leave (Backend)

As an **owner**,
I want to approve or reject a pending leave request,
So that I can control who's off and when, with the employee notified either way.

**Acceptance Criteria:**

**Given** a Pending leave request
**When** an Owner calls `attendance_leave_approve`
**Then** `leave_transition_days` transitions all its days to Approved (`p_cause = approve`), and the Employee is notified in the same transaction

**Given** an Owner calls `attendance_leave_reject` with an optional reason
**When** the request is still Pending
**Then** all its days move to Rejected, the Employee is notified with the reason if one was given, and the reason being empty is a valid reject (not a validation error)

**Given** two Owner sessions attempt to act on the same request at once
**When** both calls race
**Then** the employee lock (AD-5) serializes them — the first wins with an actual state change, the second sees the request is no longer Pending and returns a state-conflict response rather than double-applying

**Given** a Pending request whose dates have already passed
**When** nobody has acted on it
**Then** it never auto-expires — the request and its `leave_request_days` rows simply stay `pending` indefinitely, with no scheduled job or trigger that changes their state on its own (the "Absent + Leave pending" display is validated separately in Epic 18's day-status function, Story 18.1 — this story only guarantees the underlying state never silently changes)

### Story 17.3: Revoke & cancel leave with split logic (Backend)

As an **owner**,
I want to revoke an employee's approved leave for future dates,
So that I can pull someone back in without disturbing days that have already passed or started.

**Acceptance Criteria:**

**Given** an Approved leave spanning Mon–Fri, and today is Wednesday, before the Office Start time
**When** an Owner calls `attendance_leave_revoke` with a required reason
**Then** `leave_transition_days` (`p_cause = owner_revoke`) transitions only Thu–Fri to Revoked; Mon–Wed stay Approved; the Employee is notified with the exact revoked dates and reason

**Given** it is today, and the Office Start time has already passed
**When** an Owner attempts to revoke today's date
**Then** today is excluded from the revocable set — it's treated as already started (`leave_cutoff_passed`, from `attendance_day_context`)

**Given** an Employee wants to cancel their own Pending or Approved leave
**When** they call `attendance_leave_cancel` before the same Start-time cutoff
**Then** the same split rule applies (no reason required, unlike revoke), and the Owner is notified

**Given** the app needs to show the split outcome before the user confirms
**When** it calls `leave_action_preview` (AD-24)
**Then** it returns exactly which dates would stay vs change, computed via the same path the real revoke/cancel call uses

### Story 17.4: Leave on behalf & check-in auto-cancel (FR-9) (Backend)

As an **owner**,
I want to apply leave on behalf of an employee, and have a check-in automatically cancel a same-day leave after the employee confirms,
So that both flows stay consistent with the rest of the leave lifecycle.

**Acceptance Criteria:**

**Given** an Owner applies leave on behalf of an Employee
**When** `attendance_leave_apply_on_behalf` runs
**Then** it applies the same FR-12 validation rules as Story 17.1, but the request is Approved immediately (not Pending); the Employee is notified; it can later be revoked like any Approved leave (Story 17.3)

**Given** a full-day Approved or Pending leave exists today for an Employee
**When** they call check-in without `p_confirm_leave_cancel: true`
**Then** `attendance_check_in` (Epic 16's RPC, extended additively here) returns `leave_confirmation_required` (409) and changes nothing

**Given** the same situation, but the Employee confirms (`p_confirm_leave_cancel: true`)
**When** check-in proceeds
**Then** it calls `leave_transition_days(p_cause = checkin_auto_cancel)` for only that date, the rest of a multi-day leave request is untouched, and the Owner is notified ("{employee} checked in during approved leave; leave for {date} cancelled")

**Given** the leave day is a Half-day leave
**When** the Employee checks in
**Then** no confirmation dialog fires and nothing is auto-cancelled — check-in proceeds straight through as the working half

### Story 17.5: Leave apply form (Frontend)

As a **tracked employee**,
I want a simple form to apply for leave with a live working-day count,
So that I know exactly what I'm requesting before I submit.

**Acceptance Criteria:**

**Given** the leave apply form (`SegmentedControl` + `DateTimeFields` + `Input`, no new form component)
**When** the Employee changes the date range
**Then** the "X working days" count recalculates live via `leave_preview`, before submission

**Given** the Employee selects a single date
**When** they view the form
**Then** First half / Second half options appear; selecting a second date hides them and reverts to full-day with a brief inline note (not a silent surprise)

**Given** any of the 5 rejection cases (already-off, overlapping, >7-days-past, before-start-date, already-checked-in)
**When** the Employee taps Submit
**Then** the matching message is shown inline, never by pre-disabling the button (the range might mix valid and invalid dates)

### Story 17.6: Leave history & pending queue (Frontend)

As an **owner**,
I want a pending-leave queue and full leave history,
So that I can act on requests quickly and never lose track of what happened.

**Acceptance Criteria:**

**Given** the Owner's pending queue
**When** they tap a request row
**Then** a detail sheet opens with the full reason; Approve is a single tap with no confirmation; Reject shows an inline optional-reason field that appears only after Reject is pressed

**Given** an Employee or Owner views leave history
**When** the list loads
**Then** every request shows status (Pending/Approved/Rejected/Cancelled/Revoked), dates, working-day count and reason, matching FR-17 exactly

**Given** the Owner wants to apply leave on behalf of an employee
**When** they use the "Apply on behalf" action
**Then** the form shows "Approve" as its primary action label (not "Submit for approval"), since it applies immediately

### Story 17.7: Revoke & cancel sheets with split-outcome preview (Frontend)

As an **owner**,
I want to see exactly which dates will be revoked before I confirm,
So that I don't accidentally revoke a day that's already passed.

**Acceptance Criteria:**

**Given** the Revoke sheet
**When** it opens on an Approved request
**Then** it shows the split outcome up front ("Mon–Wed stay Approved · Thu–Fri will be revoked"), computed from `leave_action_preview`, and requires a reason before the confirm button unlocks

**Given** today has passed the Office Start time
**When** the Owner opens the Revoke sheet
**Then** today's date already appears in the "stays Approved" group with no separate error — the copy reflects the cutoff automatically

**Given** the Employee's Cancel dialog on an Approved-and-in-progress request
**When** it opens
**Then** it shows the same split-outcome presentation as Revoke, with no reason field (Cancel never requires one)

### Story 17.8: Check-in leave/holiday confirmation dialogs (Frontend)

As a **tracked employee**,
I want to be asked before checking in cancels my leave,
So that I never lose an approved day off by accident.

**Acceptance Criteria:**

**Given** today has a full-day Approved or Pending leave
**When** the Employee taps Check in on the Today screen (Epic 16's `CheckInOutButton`)
**Then** a pre-flight dialog appears before any GPS fix is requested: "You're on leave today. Checking in will cancel today's leave. Continue?"; on confirm, the button proceeds to the GPS/submit step with `confirmLeaveCancel: true`; on dismiss, no request is sent

**Given** today is a Half-day leave date
**When** the Employee taps Check in
**Then** no dialog appears at all — it proceeds straight to GPS/submit (FR-9's explicit exception)

**Given** the server returns `leave_confirmation_required` (which should not normally happen if the pre-flight check ran correctly)
**When** this response is received
**Then** the app treats it the same as the pre-flight dialog case, as a defensive fallback, rather than showing a generic error

**Epic 17 summary:** 8 stories (4 backend, 4 frontend). Covers FR-9, FR-12, FR-13, FR-14, FR-15, FR-16, FR-17 in full.

## Epic 18: Day Status, Days Worked & Attendance Corrections

Every tracked day gets exactly one accurate, computed status and a running Days-worked total that Owner and Employee both see identically; the Owner can correct mistakes with a full, visible audit trail.

### Story 18.1: Day status & days-worked function (Backend)

As an **owner or employee**,
I want every tracked day to show one clear, correct status,
So that there's never an argument over who was present, late, absent or on leave.

**Acceptance Criteria:**

**Given** `attendance_day_context` (Epic 16), `attendance_records` (Epic 16) and `leave_request_days` (Epic 17) all now exist
**When** `attendance_day_statuses(p_tenant_id, p_employee_ids, p_from, p_to)` is built
**Then** it is the **only** implementation of the FR-10 ten-rule priority order (correction wins → not-tracked → worked-on-holiday → weekly-off/holiday → leave → half-day-leave → present/half-day/absent → checkout-missing → past-absent → today's-in-progress-states), returning one row per employee-date with status, `late_minutes`, `early_checkout`, worked minutes, `days_worked`, `worked_on_holiday` credit, and markers (leave pending, corrected, fake-location attempt, checkout missing)

**Given** a date with a Check-in but no Check-out by midnight (tenant timezone)
**When** the function evaluates that date
**Then** it returns `Checkout missing`, counted 0 toward Days worked until a correction is made

**Given** a Weekly off or Holiday with a Check-in
**When** the function evaluates that date
**Then** it returns `Worked on holiday`, graded by the same Full/Half-day hour thresholds, counted separately from Days worked (not mixed in), per FR-11

**Given** a Holiday is added or removed after the fact, for a past date
**When** `attendance_day_statuses` is next called for that date
**Then** the status recomputes live and correctly (no month lock, no stored/stale value) — this is proven by an integration test that changes a Holiday then re-reads the function

**Given** 50 Tracked employees over 31 days
**When** the function is called for that whole range in the integration suite
**Then** it responds within the NFR-7 budget (≤3s p95); if it fails, this is the trigger to consider materializing day status later (AD-10) — not something silently ignored

### Story 18.2: Attendance corrections (Backend)

As an **owner**,
I want to correct an employee's attendance for any date with a required note,
So that mistakes (like a forgotten checkout) get fixed without losing the original record.

**Acceptance Criteria:**

**Given** `attendance_day_overrides` (`UNIQUE (employee_id, work_date)`) and `attendance_corrections` (audit) do not exist yet
**When** this story's migration runs
**Then** they are created; `attendance_day_overrides` holds the current override (status or manual times) and works even when no `attendance_records` row exists for that date

**Given** an Owner corrects a `Checkout missing` date to `Present`
**When** `attendance_correct_day` runs with a required note
**Then** it upserts the override, appends one `attendance_corrections` row (old value, new value, note, actor, time), and never modifies the original `attendance_records` row

**Given** a date already has an override
**When** a later Holiday is added or a Weekly-off rule changes for that date
**Then** the correction still wins — it is priority 1 in the FR-10 order (AD-12), and the Owner can correct it again if needed

**Given** a date is not a tracked date at all
**When** an Owner attempts a correction on it
**Then** the RPC rejects it (PT422) — corrections are only valid on tracked dates

### Story 18.3: MonthCalendar & Day Detail sheet (Frontend)

As an **owner or employee**,
I want a month calendar with a day detail view,
So that I can see the full picture for any date in one tap.

**Acceptance Criteria:**

**Given** the 12 Day-status keys added to the `Badge`/status-colour system (UX-DR1)
**When** any status renders anywhere in this module
**Then** it pairs a distinct icon with a text label — never colour alone; a throwaway calendar month covering all 12 statuses has been rendered at real size (12px) and every same-hue pair confirmed visually distinct before this story is considered done

**Given** the `MonthCalendar` component (UX-DR4)
**When** it renders a month
**Then** each cell shows an icon-only status glyph, today is outlined in `colors.primary`, and tapping any cell (including a future date) opens the Day Detail sheet

**Given** the Day Detail sheet
**When** it opens for a date with more than one correction over time
**Then** it shows the full correction history (who, when, old value, new value, note) as an expandable row — not only the most recent one

**Given** a screen reader
**When** a calendar cell is focused
**Then** it announces date + status label together (e.g. "15 September, Present"), never the icon alone

### Story 18.4: Correction sheet UI (Frontend)

As an **owner**,
I want a simple sheet to correct a day's attendance,
So that fixing a mistake takes seconds, not a support ticket.

**Acceptance Criteria:**

**Given** the Correction sheet (existing `Sheet` + `SegmentedControl` + `Input` + time fields)
**When** it opens for a date with existing data
**Then** it's pre-filled with whatever times already exist, so the Owner edits rather than re-enters from scratch

**Given** the note field is empty
**When** the Owner tries to save
**Then** "Save correction" stays disabled until at least one character is typed (same required-field pattern used elsewhere in the app)

**Given** a correction is saved successfully
**When** the sheet closes
**Then** both the calendar cell and any open summary totals update in place immediately, without requiring the screen to be reopened

**Epic 18 summary:** 4 stories (2 backend, 2 frontend). Covers FR-10, FR-11, FR-21 in full.

## Epic 19: Reminders & Consolidated Views

Owner gets a live daily dashboard and a monthly consolidated report per employee with drill-down to a day calendar; Employee gets the same picture for themselves; both get automatic reminders so nobody has to remember to check back.

### Story 19.1: Scheduled reminders (Backend)

As a **tracked employee or owner**,
I want to be reminded automatically if I forget to check in/out, and the owner reminded about pending leave,
So that nobody has to rely on memory alone.

**Acceptance Criteria:**

**Given** `attendance_run_reminders()` does not exist yet
**When** this story ships
**Then** it is scheduled via pg_cron every 5 minutes (unschedule-then-schedule migration pattern, AD-14), reads due facts only from `attendance_day_context`, and processes each tenant in its own `BEGIN … EXCEPTION` sub-block so one tenant's failure never stops the others

**Given** an Employee has not checked in by Expected start + late cut-off on a working day with no full-day leave
**When** the job runs
**Then** a "You haven't checked in" reminder is created for them, deduped via `reminder:<type>:<recipient_id>:<work_date>` — at most once per recipient per day per type, guaranteed by the database, not the job's own logic

**Given** an Employee checked in late and hasn't checked out by Expected end + their actual late minutes
**When** the job runs
**Then** a "You haven't checked out" reminder fires at that adjusted time, not a fixed Expected-end time

**Given** an Office has employees who haven't checked in by Start time + late cut-off
**When** the job runs once per Office per day
**Then** the Owner gets one summary reminder ("{n} employees haven't checked in at {office}"), deduped per Office per day

**Given** Pending leave requests exist for a tenant
**When** the job runs at/after 10:00 AM tenant-local time
**Then** the Owner gets one pending-leave reminder for the day, deduped the same way

**Given** a daily prune job
**When** it runs
**Then** `cron.job_run_details` older than 7 days and rejected-attempt coordinates older than 90 days are pruned (AD-26)

### Story 19.2: Owner dashboard read API (Backend)

As an **owner**,
I want a single endpoint for today's attendance snapshot,
So that the dashboard loads fast and always agrees with the underlying day-status logic.

**Acceptance Criteria:**

**Given** `attendance_day_statuses` (Epic 18) already exists
**When** the dashboard route is built
**Then** it aggregates that function's output for today only — counts of Tracked / In progress / Not checked in / Late / On leave — filterable by Office, with upcoming-start-date employees excluded from every count (FR-2's "doesn't appear in summaries" rule)

**Given** unresolved Checkout-missing or Fake-location-attempt flags from past days
**When** the dashboard loads
**Then** they're included and stay visible until handled — Checkout missing clears once corrected (Epic 18), Fake-location clears once the Owner acknowledges it (`acknowledged_at`, AD-10)

### Story 19.3: Monthly & self-view read API (Backend)

As an **owner or employee**,
I want a monthly summary per employee and my own month view,
So that month-end review takes one screen, not a spreadsheet.

**Acceptance Criteria:**

**Given** the Owner requests the monthly view for a past month
**When** the route is called
**Then** it returns one row per Tracked employee (Days worked, Half days, Late count, Leave, Weekly offs, Holidays, Worked on holiday, Absent, Checkout missing), filterable by Office, all derived from `attendance_day_statuses` — no separate computation

**Given** the Owner and an Employee view the same period
**When** both requests are compared
**Then** the totals returned match exactly (FR-11's "totals always match" rule) — same underlying function, different row-level filtering only

**Given** an Employee requests their own self-view
**When** the route is called
**Then** it returns only their own data — enforced server-side (not just hidden in the UI) — plus weekly offs, upcoming holidays and leave history

### Story 19.4: Owner dashboard UI (Frontend)

As an **owner**,
I want to open the app and immediately see who's in today,
So that I don't have to call around to find out.

**Acceptance Criteria:**

**Given** the Dashboard screen
**When** it loads
**Then** it shows KPI tiles (Tracked / Checked in / Not checked in / Late / On leave), non-interactive (tapping does nothing), arranged 3-per-row, plus a Flags strip (Checkout missing, Fake location attempt) using the exact `OverdueStrip` pattern from Home

**Given** the shared `ReportSkeleton` exists today but only for reports
**When** this story ships
**Then** it's generalized into `components/ui/Skeleton` (UX-DR5) and used here first; later stories in this epic reuse it rather than rebuilding loading states

**Given** the Flags strip
**When** an Owner taps a flag row
**Then** it navigates to a filtered list of the affected employee-dates — the one piece of "todo" navigation on this screen, distinct from the read-only KPI tiles

**Given** the Owner filters by Office
**When** the filter changes
**Then** all tiles and flags update to reflect only that Office's Tracked employees

### Story 19.5: Owner monthly view UI (Frontend)

As an **owner**,
I want to review the whole month for every employee, then drill into one person's calendar,
So that month-end review is one flow, not several screens stitched together.

**Acceptance Criteria:**

**Given** the monthly view opens
**When** it loads
**Then** it shows a list of Tracked employees (reusing `TechnicianPicker`'s row style: avatar, name, summary numbers), filterable by Office, with the shared `Skeleton` for loading

**Given** an Owner taps an employee row
**When** the row opens
**Then** it shows that employee's `MonthCalendar` (built in Epic 18), reused as-is — no second calendar implementation

**Given** the summary chips ("17.5 worked", "Late 3")
**When** they render
**Then** they are text + colour only, no icon — this is the one stated FR-25 exception, since a number and a word aren't confusable with a same-hue status glyph

### Story 19.6: Employee self-view UI (Frontend)

As a **tracked employee**,
I want to see my own month at a glance,
So that I know where I stand without asking the owner.

**Acceptance Criteria:**

**Given** "My Attendance"
**When** an active or history-only Employee opens it
**Then** they see their own `MonthCalendar`, today's check-in/out state (active only), month summary (same fields as the Owner's per-employee view), weekly offs, upcoming holidays, and leave history — all read-only except leave-apply and (while active) check-in/out

**Given** `attendanceAccess` is `history_only`
**When** the Employee opens this screen
**Then** it shows past data only, no check-in control, and a persistent note explaining why ("Attendance tracking ended on {date}")

**Given** the "Days worked: X so far" running total
**When** the month is in progress
**Then** it matches exactly what the Owner would see for the same employee and period (FR-11)

**Epic 19 summary:** 6 stories (3 backend, 3 frontend). Covers FR-23, FR-24, FR-25, FR-26 in full.

---

## Build & Story Count Summary

| Epic | Stories | FRs covered |
|---|---|---|
| 14. Security Prerequisite & Technician Notification Access | 3 | FR-27 |
| 15. Attendance Setup | 10 | FR-1, FR-2, FR-3, FR-4, FR-5, FR-6, FR-18, FR-19, FR-20 |
| 16. Check-in & Check-out | 4 | FR-7, FR-8 |
| 17. Leave Management | 8 | FR-9, FR-12–FR-17 |
| 18. Day Status, Days Worked & Corrections | 4 | FR-10, FR-11, FR-21 |
| 19. Reminders & Consolidated Views | 6 | FR-23, FR-24, FR-25, FR-26 |
| **Total** | **35** | **All 28 FRs** (FR-22 incremental across Epics 15/16/17; FR-28 satisfied by design) |

All 12 UX-DRs are covered: UX-DR1 (18.3), UX-DR2 (16.4), UX-DR3 (15.4), UX-DR4 (18.3), UX-DR5 (19.4), UX-DR6 (15.8), UX-DR7 (14.3), UX-DR8 (16.4), UX-DR9 (15.9), UX-DR10 (17.5), UX-DR11 (17.7), UX-DR12 (18.3).
