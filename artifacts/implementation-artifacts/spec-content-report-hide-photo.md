---
title: 'Report and hide job photos (Play user-content policy)'
type: 'feature'
created: '2026-11-02'
status: 'draft'
review_loop_iteration: 0
context: []
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** Owners can see technician photos, so Google Play requires a way to report a photo and a team that acts on reports. Nothing exists today.

**Approach:** Any user who can open a job can report one of its photos. Reports land in a queue that only Fenzit platform admins see. An admin either hides the photo (it disappears from job detail and sync) or dismisses the report.

## Boundaries & Constraints

**Always:** Backend (`fenzit-be`) owns all rules: who may report, dedupe, hiding, and filtering. The app only calls the endpoint and renders the result. Tables use deny-by-default RLS. Reporter identity comes from the JWT, never from the request body. Hidden photos are filtered in the server query, not in the app.

**Ask First:** (1) Reports do not hide the photo automatically. A reviewer must act. Confirm this is acceptable for launch. (2) No user blocking in this change; Play may ask for it later.

**Never:** Auto-hide on the first report (lets one user hide another's photo). Platform-admin UI in the app. Changing the 5-photo upload limit. Deleting the R2 object when hiding.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| HAPPY_PATH | Member with job access reports a photo with reason `inappropriate` | 201, report row `open`; photo still shown | N/A |
| REPEAT | Same user reports same photo again | 200, existing report returned, no duplicate | N/A |
| OTHER_TENANT | Photo from another company | 404 | RESOURCE_NOT_FOUND |
| NO_JOB_ACCESS | Technician reports photo on a job not assigned to them | 403 | FORBIDDEN |
| BAD_REASON | Reason not in the allowed list, or note over 500 chars | 422 | VALIDATION_ERROR |
| HIDE | Admin resolves `hide` | Photo `hidden_at` set; hidden from job detail and sync; all open reports on it become `hidden` | N/A |
| DISMISS | Admin resolves `dismiss` | Report `dismissed`; photo unchanged | N/A |
| NOT_ADMIN | Non-platform-admin calls queue or resolve | 403 | FORBIDDEN |
| ALREADY_RESOLVED | Admin resolves a report already not `open` | 409 | CONFLICT |

</frozen-after-approval>

## Code Map

- `supabase/migrations/20260621000008_create_attachments.sql` -- attachments table, RLS pattern to copy
- `supabase/migrations/20261028000000_contact_requests.sql` -- latest table with deny-by-default RLS, migration style reference
- `src/jobs/jobs.controller.ts` -- job routes; `@Can('job.read_all','job.read_own')` gates job detail
- `src/jobs/jobs.service.ts:~815` -- job detail attachment read; add `hidden_at IS NULL` filter
- `src/sync/sync.service.ts:22` -- `SYNC_JOB_COLUMNS` attachments embed; add hidden filter
- `src/jobs/attachments.service.ts` -- upload service; reuse `storageService.getPresignedReadUrl` for admin thumbnails
- `src/admin/admin.controller.ts` -- platform-admin routes, `@Can('user.manage')`; new report routes go beside these
- `src/common/permissions/permissions.ts` -- permission map; `user.manage` = platform admin only
- `workspace/core/frontend/fenzit-app/src/features/jobDetail/components/AttachmentGrid.tsx`, `src/components/AttachmentViewer.tsx` -- where Report button goes
- `workspace/core/frontend/fenzit-app/src/services/resources/attachments.ts` -- add `reportAttachment`

## Tasks & Acceptance

**Execution (backend, deploys first):**
- [ ] `supabase/migrations/<ts>_attachment_reports.sql` -- add `attachments.hidden_at`; create `attachment_reports` (id, attachment_id FK cascade, tenant_id, reporter_id, reason check, note ≤500, status check open|hidden|dismissed, reviewed_by, reviewed_at, created_at, UNIQUE(attachment_id, reporter_id)); RLS on, no policies -- storage of reports, service-role only
- [ ] `src/jobs/attachment-reports.service.ts` + DTO -- report (create or return existing), with job-access check via the same `job.read_all`/`job.read_own` rule
- [ ] `src/jobs/jobs.controller.ts` -- `POST /jobs/:id/attachments/:attachmentId/report`
- [ ] `src/admin/admin-reports.service.ts` + controller routes -- `GET /admin/attachment-reports?status=open`, `POST /admin/attachment-reports/:id/resolve` (`hide`|`dismiss`), `@Can('user.manage')`
- [ ] `src/jobs/jobs.service.ts`, `src/sync/sync.service.ts` -- exclude `hidden_at IS NOT NULL` photos

**Execution (app, after backend is live):**
- [ ] `src/services/resources/attachments.ts` -- `reportAttachment(jobId, attachmentId, reason, note?)`
- [ ] `src/components/AttachmentViewer.tsx` -- "Report photo" action opens reason sheet (4 reasons + optional note); submit shows loading, success message, and error with retry

**Acceptance Criteria:**
- Given a member who can open the job, when they report a photo, then a report row is stored and the photo still shows.
- Given the same member reports the same photo twice, then only one row exists and the second call returns 200.
- Given a platform admin resolves `hide`, when the job detail is loaded, then the photo is absent and the sync payload omits it.
- Given a company admin or employee calls the queue endpoint, then the response is 403.
- Given the app reports a photo while offline, then the user sees an error and can retry; no crash.

## Design Notes

Reason values: `inappropriate`, `harassment`, `spam`, `other`. Dedupe is a database UNIQUE constraint, so no RPC is needed (NestJS-first rule). The queue returns a signed read URL per photo, same TTL as job detail.

## Verification

**Commands:**
- `bun run lint` and `bun run test` in `fenzit-be` -- expected: pass (tests added only after user confirms the feature)
- `bun run test` in `fenzit-app` -- expected: pass
- Supabase MCP `get_advisors` -- expected: no new RLS warnings on `attachment_reports`

**Manual checks:**
- On Pixel 6: report a photo from a job, confirm the sheet closes with success; repeat and confirm no error.
- Hide via admin endpoint, reopen the job on the app, confirm the photo is gone.
