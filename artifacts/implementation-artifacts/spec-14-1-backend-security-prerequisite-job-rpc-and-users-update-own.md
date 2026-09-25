---
title: 'Security prerequisite — revoke public EXECUTE on DB functions and column-limit users_update_own'
type: 'chore'
created: '2026-09-25'
status: 'done'
review_loop_iteration: 0
baseline_commit: 'ceff94816a77cd9d418b918a9db15b51412347d3'
context:
  - '{project-root}/artifacts/implementation-artifacts/epic-14-context.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** All 10 functions in the public schema grant EXECUTE to `anon`, `authenticated` and PUBLIC, so anyone holding the app's publishable key can call the job RPCs directly (bypassing NestJS) — they trust caller-supplied tenant/actor IDs. Separately, `users_update_own` is a row-only RLS policy while `anon`/`authenticated` hold full table UPDATE grants, so a token holder can update any column of their own row, including `role` and `tenant_id` (next login mints an owner/cross-tenant JWT). Both are deferred-work items that must merge before story 14-2 opens the realtime token to technicians (AD-18 gate).

**Approach:** One migration revokes EXECUTE on all public-schema functions from PUBLIC/anon/authenticated, keeping the explicit `service_role` and owner grants (same pattern migration 20260920000005 used for `claim_report_request`). A second migration replaces `users_update_own` with a column-limited policy `(name)` and pairs it with column-level grants — `REVOKE UPDATE ... FROM anon, authenticated; GRANT UPDATE (name) ... TO authenticated` — because an RLS column-list policy alone would still admit a combined `SET name = 'x', role = 'owner'` update; the grant-level check does not. Extend the RLS isolation integration spec with direct-call probes for both fixes and mark the two deferred-work items resolved.

## Boundaries & Constraints

**Always:**
- Write migration files in `fenzit-be/supabase/migrations/` AND apply them via Supabase MCP (never ad-hoc SQL).
- Keep the `service_role` and `postgres` (owner) EXECUTE grants intact — every app RPC call site routes through `createAdmin()`, so nothing breaks.
- Column-level UPDATE on `users` goes to `authenticated` only; `anon` loses UPDATE entirely.
- Preserve `users_read_own_or_null_tenant` and `users_insert_only_service_role` untouched.

**Ask First:**
- If any existing test or app flow fails because something calls these functions under a non-service-role role, HALT and report before widening grants back.
- If the live-DB probe shows new functions or changed grants beyond what this spec investigated.

**Never:**
- No changes to fenzo-app, the notifications/report tables, or any other policy/grant (SELECT/INSERT/DELETE/TRUNCATE on `users` stay as-is).
- No new RLS policies beyond the `users_update_own` replacement; no new Postgres roles.
- Do not "fix" by dropping the functions or making them `SECURITY DEFINER` — grant/ACL work only.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Anon/authenticated direct RPC call | JWT-scoped PostgREST call to e.g. `advance_workflow_step` | Request rejected — permission denied (Postgres 42501) | Probe asserts error present |
| Service-role RPC call | `createAdmin()` client calls any job RPC | Unchanged — job flows work end to end | Existing job suites must stay green |
| Authenticated combined self-update | `.from('users').update({ name, role, tenant_id })` with own JWT | Rejected — needs UPDATE grant on every SET column | Probe asserts error present |
| Authenticated name-only self-update | `.from('users').update({ name })` with own JWT, own (or absent) row | Allowed at grant/RLS level (0 rows for absent row, no error) | Probe asserts error null |
| Trigger/constraint function invocation | notifications insert, jobs insert via SECURITY DEFINER RPC | Unchanged — trigger calls are privilege-exempt; CHECK eval runs as function owner | Existing suites stay green |

</frozen-after-approval>

## Code Map

Investigation evidence (live DB via Supabase MCP, 2026-09-25):

- `supabase/migrations/20260920000005_rpc_claim_report_request.sql` -- the repo's established revoke pattern (lines 54-62): `revoke execute ... from public/anon/authenticated`, service_role keeps its own grant. Follow it.
- `pg_proc` (live): 10 public functions, ALL with ACL `{=X,postgres=X,anon=X,authenticated=X,service_role=X}` -- `advance_workflow_step`, `confirm_attachment`, `create_job_with_log`, `increment_job_counter`, `notifications_broadcast_changes`, `report_requests_in_flight_guard`, `setup_tenant_for_owner`, `update_job_with_log`, `update_updated_at_column`, `workflow_steps_valid`. `claim_report_request`/`create_report_request` were dropped by migration 20260920000007 — not in scope.
- `pg_policies` on `users` (live): `users_update_own` = row-only UPDATE policy, `USING`/`WITH CHECK` on `auth.jwt() ->> 'sub' = id::text`. `information_schema.role_table_grants`: `anon` + `authenticated` hold SELECT/INSERT/UPDATE/DELETE/TRUNCATE on `users`.
- `src/jobs/jobs.service.ts:368,511`, `src/jobs/workflow.service.ts:224`, `src/jobs/attachments.service.ts:246`, `src/webhooks/webhooks.service.ts:75`, `src/auth/auth.service.ts:341` -- every RPC call site uses `createAdmin()` (service-role). Revoking `authenticated` EXECUTE breaks nothing.
- `src/users/users.service.ts:345-351` (`updateMyProfile`) and every other `users`-table write -- all via `createAdmin()`; nothing relies on the `users_update_own` policy today. Self-service column = `name` only.
- `supabase/migrations/20260619000001_create_users_table.sql:37-41` -- current `users_update_own` definition; `update_updated_at_column` trigger is a BEFORE-row trigger modifying `NEW` in memory (no ACL check on `updated_at`).
- `test/integration/rls-isolation.integration.spec.ts` -- probe home: `maybeIt` gate (skips unless real `SUPABASE_URL`), `mintJwt(userId, tenantId, role)` helper; JWT `role` claim must be `'authenticated'` (Postgres role). Extend with the new probes here.
- `artifacts/implementation-artifacts/deferred-work.md:545-548` -- the two items this story resolves (mark them done with story/migration reference).
- Next migration numbers: `20260925000001`, `20260925000002`.

## Tasks & Acceptance

**Execution:**
- [x] `supabase/migrations/20260925000001_revoke_public_execute_on_db_functions.sql` -- `REVOKE EXECUTE ON FUNCTION <each of the 10> FROM PUBLIC, anon, authenticated;` (30 explicit statements: 10 functions × 3 roles, signatures taken from live `pg_proc` — no overloads remain) -- closes the direct-call hole (deferred-work item 1).
- [x] `supabase/migrations/20260925000002_column_limit_users_update_own.sql` -- `DROP POLICY users_update_own`, recreate; `REVOKE UPDATE ON public.users FROM anon, authenticated; GRANT UPDATE (name) ON public.users TO authenticated;` -- closes the privilege-column hole (deferred-work item 2). DEVIATION: PostgreSQL 17 does not support column lists on `CREATE POLICY` (live-probed: 42601) — the policy is recreated with an identical row-level definition and the column limit is carried entirely by the grant-level check, which the spec identified as the operative control. Documented in the migration header and deferred-work.md.
- [x] `test/integration/rls-isolation.integration.spec.ts` -- add probes: (1) authenticated-token direct call to `advance_workflow_step` → permission-denied; (2) authenticated-token `users` combined update `SET name, role, tenant_id` → rejected; (3) authenticated-token `users` name-only update (absent row) → no error; plus an anon-key direct RPC probe -- pins both fixes as regression tests per NFR-1.
- [x] `artifacts/implementation-artifacts/deferred-work.md` -- strike/annotate the two 2026-09-25 items as resolved with story 14-1 + migration references (fenzit-meta repo, not fenzit-be).
- [x] Apply both migrations via Supabase MCP, then verify ACLs live (`pg_proc.proacl`, `role_table_grants`, `pg_policies`) -- migrations must run clean before tests.

Review-patch round (BMAD 3-layer review, 2026-09-25):
- [x] `supabase/migrations/20260925000003_default_privileges_no_public_execute.sql` -- global `ALTER DEFAULT PRIVILEGES FOR ROLE postgres REVOKE EXECUTE ON FUNCTIONS FROM public` (the schema-scoped form cannot subtract Postgres's hard-wired PUBLIC EXECUTE on PG17 — probed live) + schema-scoped revoke for anon/authenticated + explicit `GRANT EXECUTE ... TO service_role` on all 10 functions + `REVOKE UPDATE ON public.users FROM public` -- closes the future-function footgun; future postgres-created functions now get no PUBLIC grant by default.
- [x] `test/integration/rls-isolation.integration.spec.ts` -- four additions: behavioral denial pins for every RPC function (anon direct call → 42501; trigger-returning functions → PGRST202 not exposed as endpoints; `pg_catalog` unreachable over PostgREST so the pin is behavioral, not a pg_proc query), anon users-UPDATE denial, authenticated upsert denial, and a positive-path real-row name-only self-update (service-role seeded probe user, cleaned up in `finally`).
- [x] `project-context.md` -- new rule #5: every new or changed-signature DB function must revoke public EXECUTE + grant explicit service_role EXECUTE in its own migration (accurate mechanism: creation-time PUBLIC grant; CREATE OR REPLACE preserves ACLs; a changed signature mints a new pg_proc entry).

### Review Findings

Standalone `/bmad-code-review` (4 layers: blind-hunter, edge-case-hunter, verification-gap, acceptance-auditor), 2026-09-25.

- [x] [Review][Patch] `anon`/`authenticated` hold `REFERENCES` and `TRIGGER` table privileges on `public.users` (live-confirmed via `role_table_grants`) — SCOPE WIDENING SANCTIONED by user 2026-09-25: revoke both in migration 2 as the least-privilege completion of the UPDATE lockdown
- [x] [Review][Patch] Migration 1 header NOTE states the wrong `CREATE OR REPLACE` mechanism (claims replace re-grants EXECUTE to PUBLIC); migration 3's header in the same changeset explicitly corrects it — fix the stale NOTE so the changeset doesn't contradict itself [../../workspace/core/backend/fenzit-be/supabase/migrations/20260925000001_revoke_public_execute_on_db_functions.sql:38]
- [x] [Review][Patch] project-context.md rule 5 cites `20260925000001` as "the pattern" for revoke+grant, but that migration contains only revokes — the explicit service_role grants live in `20260925000003`; point at both [../../workspace/core/backend/fenzit-be/project-context.md:29]
- [x] [Review][Patch] Name-only absent-row probe asserts error is null but never asserts the returned data is an empty array, so it doesn't prove zero rows matched [../../workspace/core/backend/fenzit-be/test/integration/rls-isolation.integration.spec.ts:756]
- [x] [Review][Patch] Probe-user seed uses a hardcoded `phone_number` that can violate the live partial unique indexes on `(country_code, phone_number)` (confirmed live), failing before the `try` so the cleanup path never runs; `finally` delete error also unasserted [../../workspace/core/backend/fenzit-be/test/integration/rls-isolation.integration.spec.ts:764]
- [x] [Review][Patch] service_role positive-path EXECUTE is exercised for only 1 of 10 RPCs (`create_job_with_log`) — add a service-role `advance_workflow_step` probe reusing the seeded-job fixture so grant drift on the app's write path can't ship green [../../workspace/core/backend/fenzit-be/test/integration/rls-isolation.integration.spec.ts:632]
- [x] [Review][Patch] Behavioral catalog pin probes only the bare anon key — extend the per-function loop to an authenticated client so an `authenticated`-only re-grant is also caught [../../workspace/core/backend/fenzit-be/test/integration/rls-isolation.integration.spec.ts:852]
- [x] [Review][Patch] All three migration files are missing a trailing newline [../../workspace/core/backend/fenzit-be/supabase/migrations/20260925000003_default_privileges_no_public_execute.sql:88]
- [x] [Review][Defer] RLS isolation suite (incl. the new 14-1 probes) runs in no automated path — jest rootDir src, test:e2e credentials-gated, CI has no test job — deferred, pre-existing (already tracked under CI-DB enablement)
- [x] [Review][Defer] Default-privilege guard covers only `FOR ROLE postgres`; functions created by other roles (e.g. `supabase_admin`) in `public` keep their default grants — deferred, residual risk documented; app functions are created as postgres via MCP
- [x] [Review][Defer] Rule 5 compliance is not machine-checked (no lint scanning `pg_proc` for PUBLIC grants) — deferred, fold into the CI-DB enablement work

**Acceptance Criteria:**
- Given the migration applied, when `pg_proc` is inspected, then all 10 public functions show EXECUTE only for `postgres` (owner) and `service_role`, with PUBLIC/anon/authenticated revoked.
- Given the migration applied, when `pg_policies`/`role_table_grants` are inspected, then `users_update_own` is column-limited to `(name)` and `authenticated` holds only `UPDATE (name)` column privilege on `users`.
- Given the revokes, when the existing fenzit-be test suites run, then all previously passing suites still pass (job flows unaffected — they use the service-role client).
- Given a fresh RLS isolation run against the real DB, when the new probes execute, then direct RPC calls and privileged-column updates are rejected and name-only updates pass.

## Verification

**Commands:**
- `cd fenzit-be && bun run test` -- expected: all suites that were green before this change stay green (unit tests don't need the real DB).
- `cd fenzit-be && bunx tsc --noEmit` -- expected: clean (typecheck covers the edited spec file imports).
- Supabase MCP `execute_sql`: `select proname, proacl from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public'` -- expected: only `postgres=X` and `service_role=X` entries per function.

**Manual checks (if no CLI):**
- RLS isolation integration spec against the real Supabase project (real `SUPABASE_URL`/`SUPABASE_ANON_KEY`/`SUPABASE_JWT_SECRET` env) -- new probes pass, no other probe regressed.
## Suggested Review Order

**Direct-RPC hole — revoke public EXECUTE**

- The hole and its blast radius: 10 public functions were callable with the publishable key
  [`20260925000001_revoke_public_execute_on_db_functions.sql:1`](../../workspace/core/backend/fenzit-be/supabase/migrations/20260925000001_revoke_public_execute_on_db_functions.sql#L1)

- 30 explicit revokes, signatures taken from live pg_proc; service_role/owner grants kept
  [`20260925000001_revoke_public_execute_on_db_functions.sql:24`](../../workspace/core/backend/fenzit-be/supabase/migrations/20260925000001_revoke_public_execute_on_db_functions.sql#L24)

- Closes the future-function footgun: global ALTER DEFAULT PRIVILEGES (PG17 needs the global form to strip hard-wired PUBLIC EXECUTE)
  [`20260925000003_default_privileges_no_public_execute.sql:42`](../../workspace/core/backend/fenzit-be/supabase/migrations/20260925000003_default_privileges_no_public_execute.sql#L42)

- Explicit per-function service_role EXECUTE — app RPC path no longer depends on default-privilege history
  [`20260925000003_default_privileges_no_public_execute.sql:53`](../../workspace/core/backend/fenzit-be/supabase/migrations/20260925000003_default_privileges_no_public_execute.sql#L53)

**Privilege-column hole — column-limit users self-update**

- The mechanism: grant-level column check (RLS alone would admit SET name, role) + PG17 deviation note
  [`20260925000002_column_limit_users_update_own.sql:1`](../../workspace/core/backend/fenzit-be/supabase/migrations/20260925000002_column_limit_users_update_own.sql#L1)

- anon loses UPDATE entirely; authenticated cut to UPDATE(name); policy recreated unchanged
  [`20260925000002_column_limit_users_update_own.sql:37`](../../workspace/core/backend/fenzit-be/supabase/migrations/20260925000002_column_limit_users_update_own.sql#L37)

**Regression pins (real-DB gated)**

- Direct-RPC denial probe under minted authenticated JWT and bare anon key → 42501
  [`rls-isolation.integration.spec.ts:674`](../../workspace/core/backend/fenzit-be/test/integration/rls-isolation.integration.spec.ts#L674)

- Combined self-update rejected / name-only allowed (zero-row grant-level semantics)
  [`rls-isolation.integration.spec.ts:728`](../../workspace/core/backend/fenzit-be/test/integration/rls-isolation.integration.spec.ts#L728)

- Anon UPDATE denial, privileged upsert denial, positive-path real-row self-update with cleanup
  [`rls-isolation.integration.spec.ts:764`](../../workspace/core/backend/fenzit-be/test/integration/rls-isolation.integration.spec.ts#L764)

- Behavioral catalog pin: every public RPC denies anon direct calls; trigger functions unexposed (PGRST202)
  [`rls-isolation.integration.spec.ts:852`](../../workspace/core/backend/fenzit-be/test/integration/rls-isolation.integration.spec.ts#L852)

**Docs & bookkeeping**

- Contributor rule #5 for new/changed-signature DB functions (accurate mechanism)
  [`project-context.md:29`](../../workspace/core/backend/fenzit-be/project-context.md#L29)

- Both deferred-work items struck resolved with story/migration references
  [`deferred-work.md:545`](deferred-work.md#L549)
