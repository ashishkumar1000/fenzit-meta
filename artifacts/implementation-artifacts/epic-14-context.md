# Epic 14 Context: Security Prerequisite & Technician Notification Access

<!-- Compiled from planning artifacts. Edit freely. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Open the existing notification system to technicians for the first time, so every technician has a real-time notification bell and inbox — the same one the Owner already uses, made role-aware — ready to receive attendance/leave events the moment later epics start emitting them. Before the realtime token opens to technicians, the pre-existing security gaps in the job flow must be closed: job RPCs are currently publicly executable with the app's keys, and the self-update RLS policy lets a user edit privileged columns on their own row. Fixing those first is an architecture-mandated gate, not optional hardening.

## Stories

- Story 14.1: Revoke public EXECUTE on job RPCs and column-limit `users_update_own` (Backend)
- Story 14.2: Generalize the notifications backend for technicians (Backend)
- Story 14.3: Technician notification bell, badge & role-aware inbox (Frontend)

## Requirements & Constraints

- The shared inbox is one screen and one backend serving both Owner and technician — never a second inbox. Role differences are only which events appear and where a tap leads.
- Every technician sees the notification bell with an unread badge from day one, regardless of attendance/tracked status; the badge count always matches the list.
- A technician can access only their own notifications — enforced server-side, including the realtime channel. A technician must not be able to subscribe to another user's topic or the tenant-wide owner topic even with a crafted request.
- The `GET /auth/realtime-token` endpoint must accept technicians after the security story merges, issuing a token scoped to their own notifications topic only. No polling fallback is built.
- Notifications that are not about jobs (attendance, leave, reports) always appear in the list; existing Owner job/report notifications look and behave exactly as before — regression-verified.
- Backend notification DTO changes are additive only; no breaking change to existing Owner-facing fields. `job_id` stays nullable so the job workflow RPC is untouched.
- Out of scope: new job-related notifications for technicians (e.g. "job assigned to you") — the generalized inbox just makes them easy to add later.
- No push notifications in v1: events are seen when the app is open, but payloads must be self-contained and event types stable (push-ready design).
- Success criteria: job integration tests pass unchanged after the RPC grants are revoked; RLS probes assert technicians cannot write privileged columns or reach others' notification topics; the inbox renders correctly with zero notifications.

## Technical Decisions

- Security fix is the merge-order gate: the RPC-grant/column-limit migration must land before the realtime token endpoint opens to technicians and before any attendance frontend ships. Both items come from the repo's deferred-work list and must be marked resolved there (with story/migration reference) once this epic merges.
- Revoked EXECUTE means job RPCs become callable only via the service-role/admin client; app code paths that call them must already route through the backend — verify end-to-end, not just by grant inspection.
- The self-update policy is column-limited to profile-type fields only; `role`, `tenant_id` and other privileged columns become unwritable via direct client updates.
- Additive nullable columns on the notifications table (`entity_type`, `entity_id`, `dedupe_key`) plus a partial unique index on `dedupe_key` give later epics a DB-guaranteed dedupe mechanism (used by reminders and repeated-event notifications) and a deep-link target that works without a job id.
- Realtime topic per user is `user:<id>:notifications`; the token endpoint change is gated explicitly on the security story.
- Every new behavior needs a direct-call probe in the existing RLS isolation integration spec (technician-token attempts on privileged columns and foreign topics must be rejected).

## UX & Interaction Patterns

- The bell/badge in the tab bar is the existing, always-present notifications entry point — visible to every technician regardless of attendance access; it is not part of the (later) conditional Attendance tab.
- Tapping the bell opens the existing notifications screen, generalized to be role-aware — no new screen, no duplicate inbox.
- Empty state reuses the existing EmptyState with unchanged copy ("No notifications yet").
- A frontend event-type registry keyed on event type decides each row's card, deep link and which stores to refetch; unknown types render a generic card and never touch job UI. Job and report rows keep their current behaviour exactly.
- The realtime bridge, notifications hook and status banner are generalized from owner/job-specific to role-agnostic — no duplicated bridge code.
- No placeholder or fake attendance data anywhere in this epic — the inbox is simply ready for real events later epics emit.

## Cross-Story Dependencies

- Story 14.1 → 14.2: the realtime token work is explicitly blocked until the security migration merges.
- Story 14.2 → 14.3: the frontend bell/inbox needs the backend token and role-aware endpoints first.
- Epic 14 → all later attendance epics: the realtime channel and generalized inbox are the delivery infrastructure every attendance/leave notification rides on; the epics' release order starts with this epic's security prerequisite before any attendance frontend ships.