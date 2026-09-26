---
title: 'Technician notification bell, badge & role-aware inbox (Frontend)'
type: 'feature'
created: '2026-09-26'
status: 'done'
review_loop_iteration: 1
baseline_commit: '5578412'
context:
  - '{project-root}/artifacts/implementation-artifacts/epic-14-context.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** The notification frontend is owner-only — the bell (with unread badge) exists only in owner surfaces (Jobs header, Home header, Account tile), the `Notifications` route exists only in the owner stack, `realtimeToken.ts` hard-blocks technicians from token exchange, and `OwnerRealtimeBridge`/`useOwnerNotifications` are gated on `session?.role === 'owner'` and refetch owner stores. A technician has no notification entry point at all, so Epic 14's backend channel (14-2, shipped) has no consumer.

**Approach:** One inbox, made role-aware — never a second inbox. The realtime token skip for technicians is removed; the bridge generalizes to role-agnostic (mounted in both trees, deciding per role which stores to refetch and whether a banner applies); the shared `NotificationsScreen` renders in the technician stack behind a header bell on the technician Today screen; an event-type registry keyed on `eventType` decides each row's card, deep link and stores-to-refetch per role. Owner behaviour is verified unchanged (regression).

## Boundaries & Constraints

**Always:**
- Bell + unread badge visible to every technician from day one, regardless of attendance/tracked status (FR-27). Badge count always matches the list (same `useNotifications` store both roles already share).
- Header bell on the technician Today screen (user decision 2026-09-26), mirroring the owner's Jobs-header bell: `IconButton` + Bell icon + conditional badge, ≥44px touch target, `navigate('Notifications')`.
- Event-type registry (per AD-19/UX-DR7) decides per role: card component, deep-link target, stores to refetch. Job cards deep-link to `TechJobDetail` for technicians (user decision 2026-09-26); report cards remain owner-only; **unknown event types with no deep-link target (no `jobId`) render a generic card and never touch job UI; when the backend attaches a `jobId` it is the authoritative deep link even for an unknown type** (amended 2026-09-26, human renegotiation of the review decision). Empty-state CTA ('Go to jobs') is hidden for technicians.
- Empty state reuses the existing `EmptyState`; the title is unchanged ("No notifications yet") and the description is role-based — technicians see "Updates for you will show up here." (amended 2026-09-26, human renegotiation of the review decision).
- Generalize `OwnerRealtimeBridge` → role-agnostic bridge (single bridge component, no duplicated bridge code), mounted in both App.tsx branches; rename `useOwnerNotifications` accordingly or wrap it; remove the `isCurrentUserTechnician()` skip in `realtimeToken.ts`.
- Technician-side event handling: with no job/report events emitted to technicians (epic non-goal), a technician event today refetches the shared notification stores (list + unread count) and shows no job banner; the registry is where later epics plug in.
- Update stale role comments/docs in the same change (`navigation/types.ts` "Owner-only notification history", `useNotifications.ts` header, `ProfileScreen.tsx` "no Notifications row" note, owner-flavored channel helper names in `supabaseRealtime.ts`).
- Relative imports (codebase convention — no aliases until adopted wholesale).

**Ask First:**
- If making the shared `NotificationsScreen` role-aware requires restructuring the owner navigation tree (beyond adding a `Notifications` route to `TechnicianRootStackParamList` + navigator), HALT and propose the alternative.
- If removing the technician token skip changes the `realtimeToken` cache/reset contract in a way that touches owner flows, HALT and present the design before proceeding.
- If the shared screen needs a breaking change to `ApiNotification`/`notificationService` wire format (backend is already additive-only per 14-2), HALT.

**Never:**
- No second inbox screen, no duplicate bridge code, no new backend change (14-2 shipped the token route + DTOs — this story is fenzo-app only).
- No polling fallback, no push notifications, no attendance/leave event types or placeholder/fake attendance data anywhere.
- No job-event notifications rendered for technicians (epic non-goal — "job assigned to you" is out of scope).
- No design-token hard-coding; all UI via `@theme` tokens + `@components/ui` (existing bell pattern in JobsScreen is the reference).

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Technician opens app (any attendance state) | Valid technician session | Bell + unread badge visible on Today header; 0 unread → no badge | — |
| Technician taps bell | Any | Opens the existing Notifications screen rendered in the technician stack (same component, not a copy) | — |
| Technician inbox empty | Zero notifications | Existing `EmptyState`, unchanged copy "No notifications yet"; no CTA (technician) | — |
| Owner inbox unchanged | Owner session | Jobs/Home header bells, Account tile, screen behaviour, banners identical to today (regression-verified) | — |
| Realtime event → technician | `user:<techId>:notifications` INSERT (none exist yet in this epic) | Shared stores refetch (list + unread count); no job banner; registry-driven — later epics add types without bridge changes | Token 401 → `registerReset` clears cache (existing wiring, role-blind) |
| Realtime event → owner | Job-status / report events | Exactly today's behaviour: job banner for job events, refetch of owner stores, report events → loadReports + unread count | — |
| Unknown `eventType` row | Any role | Generic card renders; tap does nothing job-specific; never touches job UI | — |
| Technician token exchange | Technician JWT → `GET /auth/realtime-token` | Token issued (14-2 backend), scoped to own topic; FE no longer short-circuits | 401 → existing reset path |
| Foreign-topic subscription attempt | Technician + crafted topic | Not possible via FE code (topic derived from own session user id); RLS denies server-side (14-2 verified) | — |
| App backgrounded / resumed | Either role | Existing foreground-only lifecycle unchanged (AppState listener, teardown on background) | — |

</frozen-after-approval>

## Code Map

Investigation evidence (subagent sweep, 2026-09-26, baseline 5578412):

- `src/services/realtimeToken.ts:45-50,70` — `isCurrentUserTechnician()` short-circuits technicians to `null`; THE functional blocker. Cache + `REFRESH_MARGIN_MS = 60_000` + `registerReset(clearRealtimeToken)` are role-blind; the technician-skip test in `realtimeToken.test.ts` flips with this.
- `src/features/notifications/OwnerRealtimeBridge.tsx:24-30` — 31 lines: `isOwner` gate → `useOwnerNotifications({ enabled: isOwner })` → `<StatusBanner banner={banner} />`. Mounted in `src/App.tsx` owner branch only (inside `NavigationContainer`, sibling of `RootNavigator`); technician branch renders `TechnicianRootNavigator` with no bridge.
- `src/features/notifications/useOwnerNotifications.ts` — topic `user:<userId>:notifications` (L177) via `getOwnerChannel(userId)` (`supabaseRealtime.ts:71-85`, names owner-flavored, mechanism role-agnostic); broadcast INSERT handler L196-198; `handleJobStatusEvent` L131-167 refetches `loadJobs`/`loadMyProfile`/`loadUnreadCount` (+ `loadReports` for report events L145-149) and shows banner; foreground-only lifecycle L72-76, L221-227. No cache — live refetch only.
- `src/components/StatusBanner.tsx` — pure presentation, renders whatever banner object it's given; owner-shaped only through its inputs. Reusable as-is.
- `src/features/notifications/NotificationsScreen.tsx` — root-stack route, `CompositeScreenProps<…RootStackParamList,'Notifications'…, BottomTabScreenProps<MainTabParamList>>` (L67-70); focus-load L88-93, cursor pagination, pull-to-refresh, Mark-all-read L223-230; `handleCardPress` L111-130 (report → `Reports`, job → `JobDetail`); empty state L302-311 with CTA "Go to jobs" → `Jobs` tab; filter-matched-empty L296-300; error `InlineError`+Retry L237-246.
- Bell reference implementation: `src/features/jobs/JobsScreen.tsx:279-290` (IconButton + `bellBadgeLabel(unreadCount)`); technician Today screen builds its own header (`headerShown: false` throughout the tech tree).
- Nav types: `src/navigation/types.ts` — `RootStackParamList.Notifications` owner-only ("Owner-only notification history (bell tap)" comment); no route in `TechnicianRootStackParamList`; technician tree = `TechnicianRootNavigator` (Today / TechJobDetail / Signature / LocationCapture) + `TechnicianTabs` (Today / History / Profile).
- Role source: `src/features/auth/useAuth.ts` — MMKV session store, `Session = { role: 'owner' | 'technician', tenantId }` (`authApi.ts:58`).
- Already role-agnostic (reusable untouched): `useNotifications` store (recipient-scoped server-side; list/unread-count/mark-read/mark-all-read, optimistic mutations, throttles, reset registry), `notificationService` resource, `StatusBanner`, shared `TabBar`, UI primitives, 401-reset wiring, `supabaseRealtime` singleton.
- Tests touching this surface: `useOwnerNotifications.test.ts` (15), `OwnerRealtimeBridge.test.tsx` (4), `StatusBanner.test.tsx` (7), `notifications-screen.test.tsx` (25), `useNotifications.test.ts` (21), `realtimeToken.test.ts` (7), `supabaseRealtime.test.ts` (6), `notifications.test.ts` (6), bell surfaces in JobsScreen/HomeScreen/MoreScreen suites. Tests are written AFTER user device-confirmation (project rule — never upfront).
### Review Findings

<!-- BMAD adversarial code review 2026-09-26 (4 layers: blind-hunter, edge-case-hunter, verification-gap, acceptance-auditor) -->

- [x] [Review][Decision] RESOLVED 2026-09-26: keep jobId-authoritative (user choice); frozen wording amended below. — Registry classifies unknown event types by `jobId` presence, not `eventType` — the frozen constraint says unknown event types render a generic card and never touch job UI, but `notificationEventAction` checks `jobId !== null` first: an unknown event carrying a jobId renders a tappable job card deep-linking into job UI (and a `report_*` row with a drifted jobId is 'report' for the owner but 'job' for the technician). The implementation and its test codify this as a deliberate design choice — needs human adjudication, not a silent patch.
- [x] [Review][Decision] RESOLVED 2026-09-26: keep the technician copy (user choice); frozen wording amended below. — Technician empty-state description copy changed — frozen constraint says the empty state reuses `EmptyState` with unchanged copy; this change adds `description={role === 'technician' ? 'Updates for you will show up here.' : …}`. Title stays "No notifications yet"; the description is technician-facing and arguably better than the owner line ("your technicians"), but it deviates from frozen wording.
- [x] [Review][Decision] RESOLVED 2026-09-26: separate fenzo-app commit for the test-only realignment, before the 14-3 commit (user choice). — Copy-drift test fixes ride in the 14-3 diff — the stale-copy test realignment (`reportModel.test.ts`, `ReportsScreen.test.tsx`, `ReportRequestForm.test.tsx`, `ReportRow.test.tsx`, `__tests__/useReports.test.ts`) is test-only (sources were already committed at HEAD; those suites were red at HEAD) but muddies the 14-3 regression story. Options: separate fenzo-app commit vs one combined commit.
- [x] [Review][Patch] APPLIED — Stage the untracked `src/features/technicianApp/TodayScreen.test.tsx` at commit — it is on disk but untracked, so `git diff HEAD` (and a naive `git commit -a`) silently drops the technician bell's own contract test. [src/features/technicianApp/TodayScreen.test.tsx]
- [x] [Review][Patch] APPLIED — Technician realtime branch untested — deleting the technician branch in `handleJobStatusEvent` (or falling through to the owner branch) fails no test; `useRealtimeNotifications.test.ts` is owner-only and `RealtimeBridge.test.tsx` mocks the hook. [src/features/notifications/useRealtimeNotifications.test.ts]
- [x] [Review][Patch] APPLIED — App.tsx technician-branch `RealtimeBridge` mount unpinned — removing `<RealtimeBridge />` from the technician branch fails no test (App smoke test has no session). [src/App.tsx:67]
- [x] [Review][Patch] APPLIED — Removed technician skip in `getRealtimeToken` unverified — every `realtimeToken.test.ts` fixture uses a single-segment JWT, so re-adding a role-based early return fails nothing. [src/services/realtimeToken.test.ts]
- [x] [Review][Patch] APPLIED — `buildReportCards` defaults `role` to 'owner' and re-declares the role union inline — a future caller omitting the role silently gets owner behaviour for a technician; make the param required and reuse `SessionRole`. [src/features/notifications/reportNotificationModel.ts:106]
- [x] [Review][Patch] APPLIED — Missing trailing newline on five new files — `RealtimeBridge.tsx`, `bellBadge.ts`, `GenericNotificationCard.tsx`, `notificationEventRegistry.ts`, `reportNotificationModel.ts`. Inconsistent with the codebase.
- [x] [Review][Patch] APPLIED — `ApiNotification.jobId` JSDoc duplicated verbatim (inserted above the pre-existing block). [src/services/resources/notifications.ts:31-41]
- [x] [Review][Patch] APPLIED — `SharedRoutes` comment misstates its premise — "The four lists share no route names" is false (`Notifications` is declared in both stacks by this story); role routing is enforced only at runtime. [src/features/notifications/NotificationsScreen.tsx:92]
- [x] [Review][Patch] APPLIED — `bellBadge.ts` doc claims Home header uses it — the Home header bell is a dot-only badge (`HomeHeader.tsx`), not a `bellBadgeLabel` consumer. [src/features/notifications/bellBadge.ts]
- [x] [Review][Patch] APPLIED — Registry doc grammar — "a later epics' new event types". [src/features/notifications/notificationEventRegistry.ts]
- [x] [Review][Defer] `failedReportCopy` doc comment contradicts behaviour (FR21: "never a raw code" vs the `Error (code: …)` fallback, and the two engine codes `REPORT_RANGE_TOO_LARGE`/`REPORT_PRESIGN_FAILED` lost their friendly lines) — deferred, pre-existing at HEAD (`reportModel.ts` untouched by this story); restore friendly lines in a small follow-up change. [src/features/reports/reportModel.ts:98]
- [x] [Review][Defer] Garbage date strings pass `validateRange` as a 0-day range (no explicit validity gate; `rangeDays` returns 0 for unparseable dates) — deferred, pre-existing at HEAD; form inputs are date-picker driven. [src/features/reports/reportModel.test.ts]
- [x] [Review][Defer] `mergeNotificationCards` comparator NaNs on an unparseable `latestCreatedAt` — deferred, pre-existing sort pattern (typed ISO server field). [src/features/notifications/reportNotificationModel.ts:163]
- [x] [Review][Defer] Badge pill markup duplicated between `JobsScreen` and `TodayScreen` (only the label fn was extracted to `bellBadge.ts`) — deferred, spec said mirror the owner bell; a shared pill component is later cleanup. [src/features/technicianApp/TodayScreen.tsx]
- [x] [Review][Defer] Unread generic cards cannot be individually marked read (inert by design) — deferred, later epics own generic rows; "Mark all read" covers them today. [src/features/notifications/components/GenericNotificationCard.tsx]
