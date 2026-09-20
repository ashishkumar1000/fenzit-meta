# Story 12.6: Frontend — Owner Reports screen (fenzo-app)

Status: review (implemented + device-confirmed + tested 2026-09-21)
baseline: fenzit-be 12-1..12-5 implemented (uncommitted, in `review`); this story
consumes their API (`POST /api/v1/reports`, `GET /api/v1/reports`,
`GET /api/v1/reports/:id`).

> Implemented 2026-09-20 — see the notes block at the bottom for what shipped.

## Story

As an **owner**,
I want a Reports screen where I request a Technician Job Report and watch it
generate in a live history list,
So that I can open the finished PDF without leaving the app.

## Scope (from epics-reports.md, FR3/FR19–FR22, NFR4 UI surface)

- `Reports` route + entry tile in the More tab (owner-only).
- Request form: report type (only `technician_job_activity` exists — show its
  title), IST date pickers (start/end, ≤ 92 days inclusive, no future IST
  dates), technician MultiSelect (empty = all), Generate button gated on
  valid form.
- Fresh `x-idempotency-key` per submit (never reuse).
- History list: newest first, status chips (queued / generating / ready /
  failed), failed rows show friendly error copy from `errorCode`.
- Refresh: 5 s list-polling while any row is queued/generating + Supabase
  Realtime refresh on `report_ready` / `report_failed` notifications.
- Ready row → tap opens `GET /reports/:id` presigned URL via
  `Linking.openURL` (fresh URL per tap — never cached).
- Design-system states: skeleton loading, empty state, error banner, offline
  boundary. Tiered `useReports` store.

## API contract (consumed)

- `POST /reports` body `{ reportType?, startDate, endDate, technicianIds? }`
  → `201 { id, status, createdAt }`; errors: `REPORT_RANGE_TOO_LARGE`,
  `REPORT_TOO_MANY_TECHNICIANS`, `REPORT_IN_FLIGHT_LIMIT` (429),
  `VALIDATION_ERROR`.
- `GET /reports` → `PaginatedResponse<ReportListItemResponse>` (`data`,
  `nextCursor`, `hasMore`), page 20, newest first. **Note:** cursor uses 
  `(created_at DESC, id DESC)` per 12-2 AC 5.
- `GET /reports/:id` → `ReportStatusResponse` 
  `{ id, reportType, params, status, createdAt, completedAt, file?, error? }` 
  where `file` contains `{ url (presigned), size, filename }` when status=ready,
  and `error` contains `{ code }` when status=failed (matches 12-2 AC 4).

## Acceptance criteria

1. Owner sees the Reports tile; technician does not (route gated by role).
2. Form validates before Generate enables: start ≤ end, range ≤ 92 days,
   end not in the future on the IST clock.
3. Submit posts with a fresh idempotency key; duplicate submit (retry) does
   not create a second row; `REPORT_IN_FLIGHT_LIMIT` shows a clear message.
4. History list shows all my requests newest-first with status chips 
   (Queued, Generating, Ready, Failed); failed rows show friendly copy per 
   error code, not a raw code.
5. A queued/generating row transitions to ready without a manual pull
   (polling and/or Realtime) within ~5 s of completion.
6. Tapping a ready row opens the PDF in the system viewer (fresh presigned
   URL fetched at tap time).
7. Loading / empty / error states all use the design system; no blank screen.

## Notes

- Tests after the user confirms the feature on device (project test-timing
  rule); BMAD code review after tests, commit after review approval.

> **Implemented 2026-09-20.** New feature folder `src/features/reports/`
> (`ReportsScreen`, `useReports` shared store, `reportModel` pure model,
> `components/ReportRequestForm` + `ReportRangeFields` + `ReportRow`),
> `services/resources/reports.ts` API resource, and wiring: `Reports` root
> route + Account-tab `MoreRow`, `openUrl` in `utils/linking.ts`, and a
> report branch in the owner notifications hook (`report_ready` /
> `report_failed` broadcasts force-refetch the reports store instead of
> raising the job-status banner; the bell count still refreshes).
>
> Design decisions: request dates are IST `YYYY-MM-DD` strings end to end
> (backend's vocabulary); Generate gated by the same validation the backend
> runs (start ≤ end, ≤ 92 days inclusive, no future IST dates); fresh
> idempotency key per submit; empty MultiSelect = all technicians; a ready
> row fetches a FRESH presigned URL at tap time (never cached); failed rows
> are normal rows with friendly copy per engine error code; 5 s store-level
> polling while any row is queued/generating, plus the Realtime hint.
>
> Typecheck clean; test suite green (1049 passing) except the pre-existing
> `api-client.test.ts` failure caused by the user's local LAN `API_HOST`
> override in `src/config/index.ts` (unrelated to this story). Device
> verification pending; tests for the new files after user confirms.

## Follow-up: story 12-7 — retry a failed report (2026-09-20)

Direct user request on the 12-6 screen ("give an option to retry the same
report and if it succeeds update the status"). Backend did not support it; built
on both sides, honouring the less-stored-procedures decision — the re-queue is a
plain guarded UPDATE from the app and the in-flight cap stays declarative.

**Backend (fenzit-be):**

- `POST /reports/:id/retry` (owner-only, idempotency-gated, 201/404/409/429):
  re-queues a FAILED row in place — `status → queued`, `error_code` /
  `completed_at` / `locked_until` cleared, `attempt_count → 0` (a deliberate
  human retry is a fresh run of the worker's attempt budget). Guarded on
  `status = 'failed'`, so a double-tap cannot re-queue twice (the losing call
  gets 409 `REPORT_NOT_RETRYABLE`); a non-failed row gets 409 up front. 3
  in-flight rows → PT429 → 429 `REPORT_IN_FLIGHT_LIMIT`, same as create.
- Migration `20260920000009_reports_retry_requeue`: widens
  `report_requests_in_flight_guard` (INSERT-only before, because "failed →
  queued never happens") to `before insert or update of status`. Count-neutral
  transitions (queued→generating claim, generating→queued lease recovery,
  generating→ready/failed stamps) are skipped explicitly — in a BEFORE UPDATE
  trigger the row still counts as generating, so re-checking them would falsely
  429 the third in-flight row's finishing stamp. Only INSERT and
  ready/failed→queued (retry) are checked.
- `ErrorCode.REPORT_NOT_RETRYABLE` added; build clean, endpoint verified in
  `dist`.

**Frontend (fenzo-app):**

- `reportService.retryReport(id, idemKey)` (fresh idempotency key per tap,
  same rule as create) + `retryReportRequest` in the `useReports` store
  (`retryingId` / `retryError`); on success the list is force-refetched — the
  SAME row flips to "Queued", no duplicate history entry, and 5 s polling
  arms itself via `hasPending`.
- Failed rows render a compact secondary **Retry** button under the friendly
  error copy (`ReportRow`, spins while in flight); retry failures surface in
  the banner above the history list (`ReportsScreen`).
- Typecheck clean. Device verification pending; tests after user confirms
  (test-timing rule), then BMAD review, then commit.

## Follow-up: dedicated report notification cards (2026-09-20/21)

The report worker's terminal notifications (`report_ready` / `report_failed`,
`job_id` NULL, payload `{reportId, reportType, reportLabel, status, errorCode}`)
used to collapse into a dead generic "Job status updated / View Job" card on
the Notifications screen. Built their own path — device-confirmed by the user
2026-09-21, tests written after confirmation, all green (BE 690/690, FE
1176/1177 with the 1 pre-existing LAN-config fail, tsc clean both repos).

**Backend (fenzit-be, part of 12-3's worker):** the engine inserts one
notification per terminal report status with `job_id` NULL and the payload
above.

**Frontend (fenzo-app):**

- `reportNotificationModel.ts` (new): one card per notification row (no job
  grouping possible), title "Report ready"/"Report failed", friendly message
  via `failedReportCopy`, status family done/cancelled, event type trusted
  over payload status, drift → fallback copy never a crash;
  `mergeNotificationCards` interleaves both card kinds by recency (stable).
- `notificationCardModel.ts`: `groupNotificationsByJob` skips `jobId === null`
  rows — report notifications never fold into a job card.
- `notificationBannerModel.ts`: new `notificationEventType(message)` (same
  two-level unwrap as `eventRowPayload`, dispatching on the row's
  `event_type`).
- `useOwnerNotifications.ts`: report events force-refetch the reports store +
  the bell unread count; no job-status banner, no jobs/profile refetch.
- `ReportNotificationCard.tsx` (new) dispatched from `NotificationCard` on
  `kind: 'report'`: icon + title, status banner, message, "View report"
  button — never the job timeline or "View Job".
- `NotificationsScreen.tsx`: report cards render under the **All** filter only
  (Active/Completed are job-status buckets); `counts.all` includes them;
  tapping navigates to the `Reports` root-stack route (never JobDetail);
  jobId-null rows never reach the template-lookup hook.

**Tests (2026-09-21, all new):** reportNotificationModel 21, hook routing +3,
eventType unwrap +7, jobId-null grouping +3, screen +7 (All-tab-only, counts,
Reports navigation, mark-read, job-card regression guard, template-cache
guard), ReportNotificationCard 6.