# Touchpoints — human-readable IDs

Implementation map proven by the 2026-10-15 code sweep + adversarial review (line refs re-verified by the reviewer). BE = `workspace/core/backend/fenzit-be`, FE = `workspace/core/frontend/fenzo-app`. Dev agent re-verifies each before editing.

## CAP-1 — owner job-number surfacing (FE only)

| Site | File | Today → Target |
|---|---|---|
| Owner job list card | `src/features/jobs/components/JobCard.tsx:136,154,178` | add job number line on the meta row (persistent, not fallback) |
| Owner job detail header | `src/features/jobDetail/JobDetailScreen.tsx:295` | customer name stays primary; `JB-…` becomes a persistent secondary line (replace the `|| jobNumber` fallback) |
| FE job model | `src/services/resources/jobs.ts:136-141` | already carries `jobNumber` — no change |

## CAP-2 — employee_code allocation (DB only, ONE migration)

| Piece | Spec |
|---|---|
| Column | `users.employee_code TEXT NULL` + named `CONSTRAINT users_tenant_employee_code_unique UNIQUE (tenant_id, employee_code)` |
| Counter | `employee_sequences (tenant_id PK, last_seq INT)` mirroring `job_sequences` (`supabase/migrations/20260621000002_create_jobs.sql:64-72`): RLS enabled, zero policies |
| Function | `set_employee_code()` SECURITY DEFINER, `SET search_path = public` (house precedent `increment_job_counter` — shipped form; body refs fully qualified anyway); `REVOKE EXECUTE ON FUNCTION … FROM PUBLIC, anon, authenticated` in the SAME migration (house rule from `20260925000001`; no service_role grant — never RPC-called) |
| Trigger | `BEFORE INSERT OR UPDATE ON users`: fires only when `NEW.tenant_id IS NOT NULL AND NEW.employee_code IS NULL AND (TG_OP = 'INSERT' OR OLD.employee_code IS NULL)` — write-once guard; allocation via row-locked `INSERT … ON CONFLICT (tenant_id) DO UPDATE SET last_seq = employee_sequences.last_seq + 1 RETURNING last_seq` (pattern of `increment_job_counter`, `20260621000003_rpc_create_job_with_log.sql:9-24`); format `'EMP-' || lpad(seq::text, 3, '0')` |
| Backfill (same migration, after trigger) | per tenant: number users by `created_at ASC, id ASC` starting `EMP-001`; then `INSERT employee_sequences … ON CONFLICT DO UPDATE` with each tenant's max |
| Coverage | all writers — NestJS (findOrCreateUser, invite), integration-seed raw SQL, backfill itself (explicit codes → trigger no-ops) |
| Trigger-name check | no existing trigger/function on `users` (reviewer F1 verified); `20260925000004` revoked client TRIGGER privilege only — postgres-role migration unaffected |

## CAP-3 — DTOs, FE, PDFs

| Surface | File | Change |
|---|---|---|
| Roster DTO | BE `src/users/users.service.ts` — `TechnicianSummary` `:68-77`, `UserProfileBase` `:79-86`, `TechnicianListRow` `:202-210`, own-row select `:255`, `listTechnicians` select `:432` | add `employeeCode` to selects + DTOs |
| Profile embed | BE `src/users/users.service.ts:147-153,745-751` | **out of scope** — job-row technician embed stays without `employeeCode` (its spec tests use exact `toEqual`) |
| Leave list | BE `src/attendance/leave.repository.ts:496-499,536-549` (raw SQL already joins users — add `u.employee_code`), `src/attendance/leave-read.service.ts:392`, `src/attendance/leave.model.ts:50-68` | attach `employeeCode` beside `employeeName` on the owner list view only; write/preview responses unchanged (employeeName precedent) |
| Attendance PDF | BE `src/reports/registry/attendance.data.ts:246-253` (`'id, name'` → widen), `attendance.template.ts:206-212,273-289` | `NAME · EMP-004` inline in the two summary tables, two-line in the day register; columns wrap, never overflow; missing-row fallback `'—'` |
| Job-activity PDF | BE `src/reports/registry/technician-job-activity.data.ts:215-216` + `.template.ts` section titles | code in the per-technician section title (`Ravi · EMP-002`); flags + attendance exceptions/rejection rows stay NAME-ONLY (review round-1 decision: the code sits in the section directly above; joining flags would churn spec fixtures for no display value) |
| BE test fixtures | `attendance.template.spec.ts`, `technician-job-activity.template.spec.ts`, `technician-job-activity.flags.spec.ts` | intentional mechanical fixture updates; type the field optional-with-fallback to keep edits minimal |
| Roster row | FE `src/features/technicians/components/TechnicianRow.tsx:28,31` | `EMP-004` line, fail-hidden when absent |
| Leave row | FE `src/features/attendance/leave/LeaveRequestRow.tsx:114-129` | code beside name, fail-hidden |
| FE types | `src/features/technicians/types.ts` (`Technician`, `ProfileTechnician`), `src/services/resources/attendanceLeave.ts:124`, `src/services/resources/users.ts:163-202` (`MyProfile`) | `employeeCode?` OPTIONAL — invite flow fabricates locals without it (`useTechnicians.ts:203-224`), hydration fills it later (`:124-134`) |
| Docs | BE `docs/api-contracts.md:190,248` | document `employeeCode` on users/me responses |

## Guardrails (reviewer-verified safe)

- `jobs` / `job_sequences` / `increment_job_counter` / `create_job_with_log`: untouched.
- Notification payloads + realtime broadcast (`users` NOT in `supabase_realtime` publication), R2 keys, sync endpoint (jobs-only): untouched.
- `PATCH /users/me` DTO whitelist is `{ name }` only — code not user-settable; `setup_tenant_for_owner` is the only tenant-attach UPDATE (owner allocation moment).
- No `.snap` files in FE; existing FE tests assert structure/behavior, not row text.
- No committed generated DB types, no CI workflows — nothing goes stale.
- Tenant-less login stubs (709 of 842 rows in prod today): valid, codeless, excluded from backfill.
- Known properties (review rounds 1–2, accepted): failed invites burn a counter value → gaps in the EMP sequence (monotonic never-reuse holds; codes are gapless nowhere); a future support-SQL `employee_code` write above the counter could 23505 and be misreported by the invite flow as "phone already registered" (only reachable via manual writes — constraint is named `users_tenant_employee_code_unique` for triage); JobCard/technician cards share one component, so technician lists show the job number too (improvement, not breakage).
