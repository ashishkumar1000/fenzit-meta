# Digest — code audit vs spec-payroll (round 3), researcher 1
2026-11-16. Repos: workspace/core/backend/fenzit-be (NestJS + Supabase, 146 migrations), workspace/core/frontend/fenzit-app (RN), workspace/core/frontend/fenzit-web (React admin).

## A. Existing payroll code — MISSING (essentially zero)
No payroll/salary/payslip/CTC/LOP/deduction/component tables, columns, or functions anywhere in fenzit-be migrations or src. Touchpoints are incidental: "Payroll Processing" is a bookable job service catalog entry (20261107000007, name collision only); attendance.metrics.ts:240 comment "Missing check-outs — payroll blockers."; fenzit-web pricing test asserts copy does NOT mention payroll. No payroll UI stubs in either frontend.

## B. Attendance & leave data model the run would consume — EXISTS (rich)
- Per-day rows: `attendance_records` — one row per employee per work_date, unique (employee_id, work_date), checkin/checkout + geofence (20260928000002). Attempts audit in `attendance_attempts`.
- **Per-day status engine (shared, NFR5-locked): `src/common/day-status/`** — day-status.model.ts, grid-reader.ts, keys.ts. 12 status keys incl. present, half_day, absent, half_day_leave, leave, weekly_off, holiday, checkout_missing; markers incl. corrected. This is the payroll input.
- Half-day exists TWICE: leave_requests.part ∈ full_day|first_half|second_half (20260929000001); attendance_day_overrides.status ∈ present|half_day|absent (20260929000002). 0.5 credit already in monthly-summary.model.ts (leaveCredit: full=1, half=0.5).
- **Monthly aggregates precedent: summariseEmployeeMonth (src/common/day-status/monthly-summary.model.ts)** — daysWorked, halfDays, leave, weeklyOffs, holidays, absent, checkoutMissing. Report-grade but NOT LOP: no paid-vs-unpaid leave, no divisor, no money.
- Leave: leave_requests (range, part, free-text reason, request_id idempotency), leave_request_days (per-date state pending→approved/rejected/cancelled/revoked, trigger-guarded), leave_events audit. **MISSING: leave TYPE catalog (no casual/sick/unpaid) — run cannot distinguish paid vs unpaid leave today.**
- Off days: attendance_weekly_off_defaults/overrides + public.holidays (tenant_id, holiday_date, name). Tenant timezone exists (20260926000001).
- **Join/exit dates — MISSING**: no date_of_joining/exit on users or memberships. Proxies: memberships.status invited|active|removed + created_at (20261020000001); attendance_enrolments.valid daterange (20260927000007) surfacing attendance_ended_on (20260930000001, rewritten 20261020000003). True employment start/end does not exist.
- **LOP computation — MISSING** (nothing named LOP anywhere).
- Roles rewrite: users.tenant_id/role/status DROPPED (20261020000004); membership via memberships (user_id, tenant_id, role, status, employee_code). Audit FKs point at (user_id, tenant_id) on memberships/users(id,tenant_id) — payroll must join through memberships.

## C. Per-company settings pattern — EXISTS
- Canonical: `attendance_settings (tenant_id PK, enabled, setup_completed_at)` + attendance_setup_progress (20260926000002) — RLS enabled, NO policies (deny-by-default), all access via NestJS admin client with explicit tenant filter. Mirror this.
- Per-member toggles + SECURITY DEFINER setter RPC + audit: memberships.can_create_jobs / job_approval_required via set_member_job_settings (20261112000001).
- Global-only config: app_config key/value (20261004000001, src/app-config/) — wrong shape for per-company settings. No tenant settings JSON column on tenants.

## D. Audit-trail precedent — EXISTS
- `public.audit_log` (20261020000001:107-159): actor_user_id, actor_is_platform_admin, tenant_id nullable, action ≤80 chars, target_user_id, details jsonb; append-only trigger blocks update/delete/truncate; read granted to authenticated; service read GET audit-log @Can('audit.read') (members.controller.ts:190, members.service.ts:387).
- Domain-specific append-only precedents: leave_events, attendance_corrections (actor, note, old/new jsonb, seq — 20260929000002), job logs, invite SMS audit.

## E. employee_code (EMP-NNN) — PARTIAL (auto-only; owner-set/editable MISSING)
- Home: memberships.employee_code, unique (tenant_id, employee_code), kept for life (20261020000001:71).
- Allocation: set_employee_code() SECURITY DEFINER trigger memberships_set_employee_code (rewritten 20261020000003:1061-1086; counter employee_sequences; write-once; 'EMP-' || lpad(seq, GREATEST(3,len))). Original users version + backfill 20261015000001 (later dropped from users).
- invite_member (20261020000002) takes no code param — always auto-assign. No function/controller rewrites an existing code anywhere (grep clean; web reads only: companyApi.ts:31,64,89; leave.repository.ts:532; auth.service.ts:623).

## F. fenzit-web — structure solid; payroll UI MISSING
- React Router registry src/app/routes.tsx; admin subtree /admin (inspect, account, reports, deletion-requests, config, company, me, company/customers|employees|jobs|approvals|holidays|attendance). Feature-first src/features/<name>/, CSS Modules, loaders/actions (no TanStack Query), tokens.css.
- Pages to mirror: AdminCompanyPage, AdminConfigPage, AdminHolidaysPage, AdminAttendancePage (incl. "Report" tab queuing attendance PDF, AdminAttendancePage.tsx:74-77).
- PDF: web does NOT render PDFs; consumes backend async report queue (poll status → presigned R2 URL). Payslip PDF should follow the existing report pipeline, not new web-side PDF code.

## G. fenzit-app — download precedent EXISTS; payslips MISSING
- ReportsScreen + src/services/resources/reports.ts: queue report, poll, fresh presigned URL, openUrl (src/utils/linking.ts). Profile/documents: src/features/profile/, editProfile/, more/MoreScreen.tsx.
- Employee attendance/leave self-service built: src/features/attendance/me/* (monthly grid, summary, leave actions) — payslip surface sits next to it. Zero payslip hits.

## H. RLS / storage patterns — EXISTS
- RLS house pattern: newer tables RLS enabled with NO policies + revoke all from public/anon/authenticated + grant to service_role; all reads/writes via NestJS service client with explicit tenant_id filters (20260926000002, 20260928000002, 20260929000001, 20261020000001 headers). Older JWT-claim policies remain on users/tenants; security_invoker view precedent (attendance_access_state). House rules: every new function revokes public EXECUTE; composite (id, tenant_id) FKs prevent cross-tenant orphans.
- Storage: Cloudflare R2 presigned URLs (src/storage/storage.service.ts, CLOUDFLARE_R2_*). Full PDF pipeline precedent: src/reports/ (README: request row → in-process worker engine/report-worker.ts → pdfmake-renderer.ts → R2 upload → owner polls for fresh presigned URL). NOT Supabase Storage.

## I. Conflicts / surprises
1. **Biggest data gap: no employment dates (join/exit) and no paid/unpaid leave types** — auto-proration and LOP-from-leaves cannot be computed from current schema alone.
2. Day-status engine is report-grade already — run should consume summariseEmployeeMonth-style aggregates; LOP divisor and money absent.
3. attendance_day_overrides half_day is a status/credit, not a pay amount.
4. "Payroll Processing" service-catalog entry — naming/grep noise only.
5. employee_code auto-only; owner-set/editable unimplemented; codes live on memberships (payroll FKs must go through memberships).
6. Two audit idioms coexist (generic audit_log vs per-domain append-only) — payroll must pick one; both precedented.
7. **No month-level freeze concept** — only advisory locks attendance_lock_tenant/attendance_lock_employee (20260926000003) for intra-transaction concurrency.
8. Payroll calendar inputs partially exist (holidays, weekly offs, timezone); cut-off/pay-date settings missing.
9. House decision: NestJS-first, no app-facing RPCs (AD-3 amendment, noted in 20260929000001 header) — payroll run follows same pattern.
