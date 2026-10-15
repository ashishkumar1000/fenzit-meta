---
id: SPEC-human-readable-ids
companions:
  - touchpoints.md
sources: []
---

# Human-Readable Business IDs (job numbers surfaced, employee codes added)

## Why

A pain to solve: owners and technicians cannot cite a job or a person — the only durable identifiers are UUIDs, and the owner app hides the one human reference that exists. Jobs already allocate `JB-YYYY-NNNN` per tenant, but owner job cards show no identifier and the owner detail header prefers the customer name. Users (842 in prod) have no human identifier at all — screens and PDFs identify people by name + phone only. Support conversations, roster management, and printed reports all lack a stable way to say "this job" or "this employee".

## Capabilities

- **CAP-1**
  - **intent:** Owner can read a job's `JB-YYYY-NNNN` reference on every owner-app job surface (list card, detail header) so they can cite and track jobs.
  - **success:** On device, the customer name stays primary in the detail header with the job number as a persistent secondary line (not a `||` fallback), and each Jobs list card shows the job number on its meta row — verified visible for jobs that have a customer name.
- **CAP-2**
  - **intent:** Every tenant-scoped user automatically receives a unique, never-reused `EMP-NNN` employee code at creation, with UUID primary keys untouched.
  - **success:** A `users` insert with `tenant_id` allocates the next code safely under concurrent inserts; `UNIQUE (tenant_id, employee_code)` holds; all existing users are backfilled in per-tenant `created_at` order; a `users` row with NULL `tenant_id` remains valid with a NULL code.
- **CAP-3**
  - **intent:** People are referenced by code wherever the product lists or prints them: roster rows, owner leave request rows, the attendance report PDF, the technician job-activity PDF, and the user DTOs behind them.
  - **success:** API responses (`TechnicianSummary`, profile/`users/me`, owner leave list rows) include `employeeCode`, and the FE roster row plus both PDFs render it next to the person's name; rows without a code (fresh invites, tenant-less users) render nothing rather than a placeholder.

## Constraints

- Additive-only: new nullable column, new counter table, new trigger/function, additive DTO fields. Existing API contracts, RLS, sync, realtime payloads, deep links, R2 keys, and UUID PKs are unchanged.
- Codes are tenant-scoped business references: uniqueness per `(tenant_id, employee_code)` (named constraint `users_tenant_employee_code_unique`); cross-tenant duplicates acceptable; codes are never used for authorization.
- Codes are write-once: once set, an `employee_code` is never cleared or re-allocated by the trigger (guard on `OLD.employee_code IS NULL`), keeping the never-reused property even under future manual/support SQL.
- Allocation is race-safe via a row-locked counter upsert (the `job_sequences` pattern); the counter is monotonic, so codes of removed users are never reused.
- Allocation lives in the DB (trigger), not NestJS — a deliberate deviation from project-context rule 6 ("business logic in NestJS"): ID infrastructure must also cover raw-SQL writers (backfill, integration seeds, support SQL) that bypass the app, following the sanctioned `update_updated_at_column` trigger precedent. New DB function follows house convention: `SECURITY DEFINER`, pinned `search_path`, `REVOKE EXECUTE` from public/anon/authenticated in its own migration.
- Ship as ONE migration, in order: trigger/function first, then backfill (`created_at ASC, id ASC` per tenant), then set each tenant counter to its backfilled max — single transaction, so no live insert can land between backfill and counter init.
- Rollback is forward-only (house style): a follow-up migration drops the trigger, function, index, column, and counter table.
- `jobs.job_number` scheme stays exactly as shipped: `JB-YYYY-NNNN`, yearly reset, per-tenant counter.
- FE `employeeCode` fields are optional; display is fail-hidden (absent code renders no line). Freshly invited technicians show no code until the next roster hydration from `/users/me`.
- Leave write/preview responses stay without the code (matching the existing `employeeName` precedent, which appears only on owner list reads); the profile job-row technician embed does not carry `employeeCode`.
- Nothing-existing-breaks gate: BE unit suites, the e2e baseline, and FE jest must finish at/above the current green baseline; only intentional display-driven test-fixture updates are allowed (known candidates: attendance/job-activity template specs).

## Non-goals

- No customer codes (`C-NNN`) this round.
- No cross-tenant/global uniqueness and no tenant prefix inside codes.
- No UI to edit or reassign codes.
- No change to job-number generation, notification payloads, or deep links.

## Success signal

On the owner's live device: every job card/detail shows its `JB-…` number and the roster shows `EMP-…` codes, while all suites stay green and no existing screen, API consumer, or report regresses.

## Assumptions

- Codes display alongside the person's name, never replace it; `EMP-` + 3-digit zero-pad grows naturally past 999 (`EMP-1000`). Nothing sorts by code (roster sorts by `created_at`).
- The owner's own code may appear in profile payloads, but no profile UI renders the own code this round; roster and PDFs are the primary displays.
- Backfill starts each tenant's oldest user at `EMP-001` (`created_at ASC, id ASC` tiebreak); tenant-less login stubs are excluded and stay codeless until a tenant is attached.

## Open Questions

- None blocking — owner approved the scheme (`EMP-001` per-tenant, yearly job-number reset kept, no tenant prefix, no customer codes) on 2026-10-15.
