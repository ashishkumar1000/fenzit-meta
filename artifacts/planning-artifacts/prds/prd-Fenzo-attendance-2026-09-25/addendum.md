# Addendum — Attendance & Leave PRD

Technical notes and feasibility findings that inform architecture. These are not requirements; the PRD is the source of truth for behaviour.

**How to read this:** §A is the feasibility check, §B is the reuse-vs-build split, and §C holds the reviewer-pass notes. §C is the latest word. Where §A or §B overlaps with §C, the row points to §C instead of repeating it.

## A. Feasibility check (2026-09-25, against current code)

| Area | What exists today | Feasible for v1? | Note |
|---|---|---|---|
| A0. Distance check | **No distance validation exists anywhere on the backend.** Story 7-4 only checks the coordinate range and flags accuracy > 100 m; it never blocks. The frontend has a haversine in `utils/distanceUtils.ts` for display | Yes, build new | Compute distance in SQL inside the check-in/out RPC (server authority; see §C1 Distance). Frontend haversine is only for the live "you are X m away" hint. |
| A1. GPS capture | `react-native-nitro-geolocation` in fenzo-app; location permission and capture flow already built for workflow steps (stories 7-5 … 7-10) | Yes | Reuse the permission helper only. Attendance gets its own capture call and screens (NFR-12). |
| A2. Office pin on a map | No map library (`react-native-webview` is present but unused). Address picker: Google Places autosuggest → `/places/resolve/:placeId` returns lat/lng | Yes, new dependency | **In v1 scope (FR-5).** Add a map library with a draggable pin and radius circle (library and keys: see §C2 Maps). Places search reuses the existing backend endpoints. Architecture to confirm the library and key setup. |
| A3. Fake-GPS detection | `react-native-nitro-geolocation` 1.4.3 exposes `mocked?: boolean` and `provider` (Android `isMock`); the current compat wrapper drops them | Yes, Android and iOS 15+ | **In v1 scope (FR-7).** Android: `isMock`/`isFromMockProvider`. iOS 15+: `isSimulatedBySoftware` (`CLLocation+GeolocationMetadata.swift`); app minimum is iOS 15.1. Attendance capture uses the modern API and sends `mocked` and `provider` to the server (see §C2 Location capture contract). |
| A4. Scheduled reminders | `pg_cron` already used (idempotency and notifications cleanup) | Yes | A per-minute or per-5-minute pg_cron job can create reminder rows (§B1 plans every 5 min). Idempotent via a unique key on (recipient, type, date); see §C1 Notifications for the `dedupe_key` design. |
| A5. Midnight "Checkout missing" / Absent | — | Yes | Compute Day status on read (§C1 Day status); no nightly finalisation job needed. |
| A6. In-app notifications | `notifications` table + realtime broadcast; `job_id` nullable (20260920000008). **Owner-only today:** the realtime token endpoint is owner-only; the frontend has no technician bell, list or socket; cards are grouped by job and a tap opens JobDetail | Yes, with work | Generalise so technicians can use the existing screen and badge (FR-27): nullable `jobId` in DTOs, event-type registry on the app, role-agnostic realtime bridge. Details in §C1 Notifications, §C1 Realtime for technicians and §C2. |
| A7. Push later | `pushed_at` column is the push-outbox marker | Yes (later) | No attendance change needed when push lands (NFR-10). |
| A8. Atomic state + notification | RPC pattern (`supabase.rpc`, SECURITY DEFINER) is the project standard | Yes | Leave transitions and check-in/out should each be one RPC, following the report-RPC grant pattern (§C1 RPC template). |
| A9. Idempotency | Per-route opt-in `IdempotencyInterceptor` + log table (key optional, best-effort) | Yes, with a DB guard | Reuse on check-in/out and leave writes with the key required; a unique `request_id` constraint is the real guard (§C1 Idempotency). |
| A10. Monthly export (later) | Async reports module with PDF renderer | Yes (later) | Out of v1 scope. It fits the existing report registry. |
| A11. Timezone | No tenant timezone field today; IST hard-coded in several utils | Yes | Add `tenants.timezone` (default `Asia/Kolkata`), validated; compute dates in SQL (§C1 Timezone). |

## B. Separation from the field flow (NFR-12) — reuse vs build new

Decision (delegated to Claude, product not live): **separate tables and separate API routes for everything attendance-specific; reuse the shared platform pieces (auth, errors, idempotency, notifications, design system), and generalise them where they are job- or owner-specific today.** One notifications inbox is kept, not a second one, so users see all alerts in one place.

### B1. Backend (fenzit-be)

| Reuse as-is | Generalise (small refactor, behaviour unchanged for jobs) | Build new |
|---|---|---|
| Global `JwtAuthGuard` + `RolesGuard`, `@Roles`, `@CurrentUser`, `RequestUser` | `NotificationRow/Response.jobId` → nullable; add `entity_type` + `entity_id` columns to `notifications` (§C1 Notifications) | `src/attendance/` module, routes under `/api/v1/attendance/*` |
| `GlobalExceptionFilter`, `ErrorCode` enum, PTxxx → HTTP mapping | `GET /auth/realtime-token` → allow technicians (own topic only). **Blocked** by deferred security items (§C1 Realtime for technicians) | Tables: `attendance_settings` (per tenant), `attendance_offices`, `attendance_enrolments` (effective-dated incl. future start date, office assignment), `attendance_records` (check-in/out), `attendance_corrections` (audit), `leave_requests` + `leave_request_days`, `weekly_off_rules` (tenant + employee, effective-dated), `holidays`, `attendance_attempts` (rejected attempts + fake-GPS count), `attendance_day_overrides` (Owner corrections, keyed by employee + date, works with no record), `attendance_office_rules` (effective-dated timings/hours rules), `attendance_setup_progress` (wizard resume) |
| `VALIDATION_PIPE_OPTIONS`, trim transformers | `CursorScope` union: add attendance/leave scopes | SECURITY DEFINER RPCs: check-in, check-out (distance in SQL), leave apply/approve/reject/revoke/cancel/on-behalf, correction, holiday change. Each writes state + audit + notification atomically (§C1 RPC template, Stored-procedure count) |
| `PaginatedResponse`, cursor util | `UsersService.listTechnicians` → shared method for enrolment picker | `tenants.timezone` (§C1 Timezone) + timezone-aware day-range logic in SQL (existing IST util left alone for jobs) |
| `IdempotencyInterceptor` on check-in/out and leave writes, key required (§C1 Idempotency) | `/users/me` → expose `attendanceEnabled` (tenant) + `attendanceAccess` (`none` / `upcoming` / `active` / `history_only`) and `attendanceStartDate` (technician) | pg_cron SQL functions: reminders (every 5 min, per tenant timezone) |
| `notifications` table, broadcast trigger, cleanup cron, list/unread/mark-read | Accuracy threshold (100 m) → shared constant | Day status engine + monthly summary queries (SQL view/function) |
| Report-RPC pattern (§C1 RPC template), `hasInvalidCoordinates` | | RLS deny-by-default on every new table (owner: own tenant; technician: own rows) |

**Do not touch:** `advance_workflow_step`, `workflow.service.ts`, `activity_logs` (job_id NOT NULL — attendance gets its own audit table), `jobs.service` response mapping, `sync.service`, report claim/lease RPCs, existing IST "today" logic for jobs.

**Scheduler choice:** pg_cron over the in-process report worker. Reminders are pure DB work, survive deploys, and inserting a notification fires realtime automatically.

### B2. Frontend (fenzo-app)

| Reuse as-is | Generalise | Build new |
|---|---|---|
| `apiClient`, idempotency util, pagination | `technicianApp/geolocation.ts` → `services/location` hook: modern API, keep `mocked`/`provider`, services-enabled check, neutral permission copy (iOS/Android strings too). See §C2 Location capture contract | `features/attendance/` (owner + technician screens, stores, `*Model.ts`) and `services/resources/attendance.ts`, `leave.ts` |
| `utils/distanceUtils.ts` (live "X m away" hint) | Notifications: event-type registry (card, deep link, stores to refetch), role-agnostic realtime bridge (§C2 Realtime on the client, Shared inbox) | Technician entry to the **existing** notifications screen + bell badge (no new inbox; screen made role-aware) |
| `components/ui/*`, theme tokens, EmptyState, InlineError, Sheet, SegmentedControl, MultiSelect; feature components `DateTimeFields` and `TechnicianPicker` (single-select; see §C2 Reuse list corrections) | `ReportSkeleton` → generic `Skeleton` in `components/ui` | Month calendar component (employee list → per-employee calendar; §C2 Month view) |
| `useSyncExternalStore` store pattern + `resetRegistry` | `AuthFlow` step pattern + `StepIndicator` → shared wizard shell (owner setup, technician onboarding); resume is server-side (§C2 Wizard) | Office pin picker: full-screen map route (draggable pin + radius circle; §C2 Maps); the address search sheet opens from it |
| `addressPicker` (search → lat/lng) for office setup | `istDate` stays as-is for jobs; attendance shows server-provided local dates/times with no client timezone maths (§C2 Design tokens) | Offline detection (NetInfo) + banner (§C2 Offline) |
| `TabBar` (add icon entry) | Entry points: owner → `MoreScreen` tile + Home card (always visible); technician → 4th tab "Attendance", shown for `upcoming` / `active` / `history_only` | Conditional navigation from `/users/me` flags |

**Do not touch:** `LocationCaptureScreen` and the job advance flow, job screens, job notification grouping for job events.

## C. Technical notes from the reviewer pass (2026-09-25)

Full evidence with file:line is in `review-backend.md`, `review-frontend.md`, `review-database.md`, `review-adversarial.md` and `review-rubric.md`.

### C1. Backend / database
- **RPC template:** copy the **report RPCs** (EXECUTE revoked from `PUBLIC, anon, authenticated`; called only with the service role), **not** `advance_workflow_step` (it takes tenant/actor from the caller and is still publicly executable). Take tenant and actor from the verified JWT in NestJS; check every client-sent ID inside the RPC. Add a direct-call probe for each new function to `test/integration/rls-isolation.integration.spec.ts`.
- **Stored-procedure count:** the 2026-09-20 backend decision says "keep stored procedures to a minimum". Attendance knowingly needs ~10 (check-in, check-out, leave apply/approve/reject/revoke/cancel/on-behalf, correction, holiday change) because each must write state + audit + notification atomically. Record this as a conscious exception in the architecture.
- **Rejections must not RAISE:** a RAISE rolls back the attempt row and the 3rd-attempt alert. Check-in/out RPCs return an outcome (`ok | too_far | low_accuracy | mocked | rate_limited | ...`) and commit the attempt row; the service maps outcomes to HTTP errors.
- **Idempotency:** `IdempotencyInterceptor` is per-route opt-in, key optional, lookup-then-run (racy), the result is stored only after the response, and the key is not scoped to the user. For attendance: make the key required on these routes, and store a `request_id` with a unique constraint on the attendance/leave rows so the database is the real guard.
- **Rate limit:** reuse the Places rate-limit pattern (config-driven budgets) for check-in/out attempts (FR-7: 5 rejected in 10 min → 10 min wait).
- **Effective-dated rules:** enrolment/office assignment, Office rules and Weekly offs use date ranges with no-overlap exclusion constraints, so they need the `btree_gist` extension (not enabled today). Weekly offs: separate tenant-default and per-employee tables (or partial constraints), because a NULL `user_id` breaks the exclusion constraint.
- **Snapshot on write:** each check-in stores the Office id, Expected start, Late minutes and the rules version, so later rule changes never rewrite history.
- **Leave storage:** `leave_requests` (requested range, type, reason) + `leave_request_days` (one row per date with its own state). A partial unique index on (employee, date) where state in (Pending, Approved) blocks overlaps. Whether a date counts as leave is computed from Weekly offs/Holidays at read time, which gives the FR-10 "Holiday removed → Leave again" behaviour for free.
- **Day status:** compute on read (SQL function/view) from records + overrides + rules active on each date. No nightly finalisation job is needed for Checkout missing / Absent; pg_cron is only for reminders.
- **Concurrency:** take a per-employee advisory lock (or `FOR UPDATE` on the enrolment row) in every attendance/leave RPC so check-in vs approve, revoke vs cancel, holiday change vs check-in serialise.
- **Notifications:** add nullable `entity_type`, `entity_id` and `dedupe_key` columns; partial unique index on `dedupe_key` + `ON CONFLICT DO NOTHING` for reminders. Keep `job_id` nullable so `advance_workflow_step` needs no change. Notifications are an inbox, not a record (the 30–90 day cleanup is fine); the audit lives in attendance tables.
- **Timezone:** `tenants.timezone TEXT NOT NULL DEFAULT 'Asia/Kolkata'` with a CHECK against `pg_timezone_names`. The date for "today" is computed in SQL only (one source); don't mix a TypeScript util with SQL.
- **Distance:** a plain haversine SQL function is enough; PostGIS/earthdistance not needed.
- **Realtime for technicians:** `GET /auth/realtime-token` must allow technicians (own topic only). **Gated on the security prerequisite story** (existing RPC grants, `users_update_own` columns — originally in `artifacts/implementation-artifacts/deferred-work.md`), now in scope for this initiative (architecture AD-18).
- **Deploy order:** all backend changes are additive → merge/deploy `fenzit-be` first, then `fenzo-app`.

### C2. Frontend
- **Realtime on the client:** `services/realtimeToken.ts` refuses technicians; `OwnerRealtimeBridge`, `useOwnerNotifications` and `StatusBanner` are owner/job-specific. Make them role-agnostic.
- **Shared inbox:** `notificationCardModel.ts` drops rows with `jobId = null` (only report rows get cards), and the owner realtime handler shows "Job status updated" + refetches jobs for any non-report event. Add an event-type registry (card, deep link, stores to refetch) so attendance/leave rows render and never trigger job UI.
- **Location capture contract (attendance only):** modern `getCurrentPosition` with high accuracy, `maximumAge: 0` (fresh fix), a timeout, and it returns `mocked`, `provider`, accuracy and fix timestamp; the server rejects stale fixes. Handle Android "Approximate" / iOS "Precise off" as its own state (guide the user to turn on precise location), not as "denied". The existing compat helper (last-known fix of any age, balanced ~100 m accuracy) stays for the job flow unchanged.
- **Enrolment state:** `/users/me` returns `attendanceAccess: none | upcoming | active | history_only` (not a boolean), plus `attendanceStartDate`; refetch on app foreground and on attendance notifications to avoid tab flicker (3 → 4 tabs).
- **Maps:** `react-native-maps` works with RN 0.87 New Architecture; Apple Maps on iOS (no key), Google on Android (key restricted to each keystore's SHA-1). Office map is a full-screen route.
- **Month view:** per-employee summary list → per-employee calendar (a 50 × 31 grid is unusable on a phone). New month-calendar component needed.
- **Design tokens:** define colours + labels for all Day statuses and flags; 12-hour times per the design system; show server-provided local dates/times (no client timezone maths).
- **Wizard:** the `AuthFlow` step pattern has no resume; persist wizard progress on the server (FR-1).
- **Reuse list corrections:** `DateTimeFields` and `TechnicianPicker` are feature components, not in `components/ui`; `TechnicianPicker` is single-select → the enrolment picker needs multi-select (use `MultiSelect` or extend `TechnicianPicker`).
- **Offline:** add NetInfo + offline banner (none today).
