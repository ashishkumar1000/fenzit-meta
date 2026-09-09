---
title: 'Backend — Notifications table + in-RPC insert + Realtime broadcast trigger'
type: 'feature'
created: '2026-09-09'
status: 'done'
review_loop_iteration: 1
context: []
baseline_commit: '81a0abae8d0acad7bf3acf4f9ea58e5dd1f25031'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** When a technician advances a job's workflow, the owner learns about it only via focus-refetch (15s TTL) or pull-to-refresh. There is no notification path at all — no table, no event, nothing. Phase 1 of the owner-notifications architecture discussion (2026-09-08) fixes this with Supabase Realtime.

**Approach:** Pure SQL-migration story — **zero NestJS code changes**. (1) New `notifications` table with per-recipient RLS — deliberately shaped as the future **push outbox**: every row carries a stable `event_type` and a self-sufficient `payload`, plus a nullable `pushed_at` column that the Phase 2 push worker will use as its delivery marker; (2) extend RPC `advance_workflow_step` to insert one notification for the tenant owner inside the existing transaction (atomicity for free, AR-10-compliant); (3) an AFTER INSERT trigger on `notifications` calls `realtime.broadcast_changes(...)` — the **Broadcast from Database** pattern, which is Supabase's 2026-recommended method (Postgres Changes is explicitly discouraged for new apps: single-threaded, authorizes every event against every subscriber, ~3,000-subscriber ceiling); (4) a `TO public` recipient-only policy on `realtime.messages` for Realtime authorization; (5) a third pg_cron job pruning notifications older than 30 days.

**Live-DB facts verified via Supabase MCP (2026-09-09, project `pnlvreaijzslfymlnoti`):**
- `realtime.broadcast_changes` and `realtime.send` exist; `supabase_realtime` publication is empty (nothing to clean up; broadcast-from-database does not use the publication).
- All existing RLS policies are `TO public` (not `TO authenticated`) — this convention **sidesteps the custom-JWT role-claim problem** (`role: 'owner'|'technician'` ≠ Supabase's `authenticated`). The `tenants_read_own` policy already uses `auth.jwt() ->> 'sub'` — sub-based policies are proven working with fenzit-be's custom JWT.
- `pg_cron` active with 2 jobs (`idempotency-log-cleanup`, `attachment-uploads-cleanup`) — add a third.
- No `notifications` table exists. `tenants.owner_id` (unique FK → users.id) is the recipient path.

## Boundaries & Constraints

**Always:**
- Write the notification INSERT inside RPC `advance_workflow_step` **after** the activity_logs INSERT, in the same transaction — a step advance that commits must produce exactly one notification; a rejected advance (PT409, not-found) must produce zero.
- Recipient is `tenants.owner_id` joined from `v_job.tenant_id` — never from the request, never the actor.
- Skip self-notification: `AND t.owner_id <> p_actor_id` (an owner who is somehow also the assigned technician must not notify themselves).
- Key the `realtime.messages` policy on `auth.jwt() ->> 'sub'` and topic shape `user:<uuid>:notifications` (`split_part(realtime.topic(), ':', 2)`) — mirror the live project's `TO public` convention.
- Payload carries what the banner needs without a refetch: `job_number`, `step`, `technician_name` (from `users` via `p_actor_id`).
- **Push-readiness contract:** the payload must be self-sufficient to compose a push notification later (title/body from `event_type` + `payload` alone, zero additional queries) — Phase 2's FCM worker reads these rows as its queue and marks them `pushed_at`. `event_type` values are exactly the workflow-step vocabulary (`on_my_way`, `arrived`, …) — stable strings, never free text.

**Ask First:**
- **Task 0 spike gate:** run **immediately after the `notifications`-table migration lands, before the RPC migration** — a private-channel join is only authorized once the `realtime.messages` policy exists (zero policies today), so a pre-migration spike would test nothing. Verify Realtime accepts fenzit-be's custom HS256 JWT (signed with `SUPABASE_JWT_SECRET`, claims `sub`/`tenantId`/`role`, **no `exp`**). Method: mint a token, connect via `supabase-js` in a scratch bun script, join a private channel, confirm `SUBSCRIBED` + a test broadcast arrives; also connect with the anon key only and confirm silence. Two environment facts from previous spikes apply: (1) the dev machine's egress proxy does TLS interception — the script will hit `SELF_SIGNED_CERT_IN_CHAIN` and needs `NODE_TLS_REJECT_UNAUTHORIZED=0` (run via the user's terminal, exactly like the 2026-09-08 Google Places live check); (2) delete the scratch script after the spike. If the missing `exp` is rejected, the fallback is minting with an `exp` (a BE change to token minting — come back before touching auth code). If the whole custom-JWT path is rejected, stop and re-discuss (fallback designs exist, do not improvise).

**Never:**
- No new REST endpoints, no NestJS module, no service/controller/DTO changes in **this** story — the FE consumes the broadcast payload directly; the REST read endpoints (`GET /notifications`, unread-count, mark-read) are **Story 3.2's scope** (added 2026-09-09), not a hypothetical future story.
- Do not add notifications for the owner's cancel/edit path (`rpc_update_job_with_log`) — this story is technician workflow advances only; extending to owner-cancel is a separate story.
- Do not use `postgres_changes` (WAL subscription on the notifications table) — the trigger + `realtime.broadcast_changes` broadcast pattern is the chosen architecture.
- Do not add an INSERT/UPDATE policy for clients on `notifications` — clients never write it; the RPC runs SECURITY DEFINER. The only client-facing path is the SELECT policy and the `realtime.messages` policy.
- Do not touch `fenzo-app` — Story 3.2 consumes this. Do not touch the JWT minting code unless the Task 0 spike forces it (Ask First).

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Happy path | Technician advances a valid step | 1 `notifications` row (owner = tenant owner, `event_type` = step, payload with `job_number`/`technician_name`), broadcast emitted to `user:<owner_id>:notifications` | N/A |
| Rejected advance | PT409 (terminal status / step race) or not-found/cross-tenant | Transaction rolled back — zero notification rows, zero broadcasts | N/A |
| Owner == actor | `tenants.owner_id = p_actor_id` | No notification row (self-notification guard) | N/A |
| Anon subscriber | Channel join with anon key only, no user JWT | Policy matches zero topics — no events received (this is the RLS-as-security-boundary guarantee; verify explicitly in Task 0) | N/A |
| Wrong-recipient JWT | Valid JWT whose `sub` ≠ topic owner | No events on another user's topic (`split_part` mismatch) | N/A |
| Broadcast consumer down | Owner app offline/killed | Row persists regardless; owner catches up via existing focus-refetch (at-most-once delivery is accepted by design) | N/A |
| Table growth | Notifications accumulate | pg_cron job `notifications-cleanup` deletes rows older than 30 days (hourly, mirroring `idempotency-log-cleanup`) | N/A |

</frozen-after-approval>

## Code Map

**Migration numbering (verified 2026-09-09):** repo convention is `YYYYMMDD` date prefix + 6-digit sequence, e.g. `20260909000002_notifications_table.sql`. `20260909000001_enable_rls_users_country_codes.sql` exists (uncommitted, applied live as `20260908205411`) — so this story's three migrations take `20260909000002` / `000003` / `000004`. Never edit an applied migration; `CREATE OR REPLACE` in a new file.

- `supabase/migrations/20260909000002_notifications_table.sql` -- NEW: `notifications` table (`id` uuid default gen_random_uuid(), `tenant_id` uuid NOT NULL FK, `user_id` uuid NOT NULL FK → users, `job_id` uuid NOT NULL FK → jobs `ON DELETE CASCADE` (a deleted job's notifications are dead rows — cascade keeps job deletes unblocked; Story 3.4's "orphaned job" edge then only has to cover the *unreachable* case), `event_type` text NOT NULL, `payload` jsonb NOT NULL default '{}', `read_at` timestamptz null, `pushed_at` timestamptz null, `created_at` timestamptz NOT NULL default now()), RLS **enabled**, SELECT policy `notifications_read_own` = `TO public USING (auth.jwt() ->> 'sub' = user_id::text)` (mirror the live `tenants_read_own` sub-based precedent), index `(user_id, created_at desc)`, trigger function + AFTER INSERT trigger, and the `realtime.messages` policy `notifications_topic_recipient_only` = `TO public FOR SELECT USING (realtime.topic() LIKE 'user:%:notifications' AND split_part(realtime.topic(), ':', 2) = auth.jwt() ->> 'sub')`
  - **Live-verified trigger-call shape (2026-09-09):** `realtime.broadcast_changes` signature is `(topic_name text, event_name text, operation text, table_name text, table_schema text, new record, old record, level text DEFAULT 'ROW')`. Trigger: `AFTER INSERT ON notifications FOR EACH ROW EXECUTE FUNCTION ...` with body `PERFORM realtime.broadcast_changes('user:' || NEW.user_id || ':notifications', TG_OP, TG_OP, TG_TABLE_NAME, TG_TABLE_SCHEMA, NEW, OLD);` — note `TG_OP` is passed as **both** `event_name` and `operation`, so the wire event name for this table is always `'INSERT'` (the trigger is AFTER INSERT only) — Story 3.3's FE subscribes with `on('broadcast', { event: 'INSERT' })`. The function is `SECURITY DEFINER`-callable by any role; the trigger function itself must `SET search_path = ''` (Supabase's own realtime functions use this — unqualified `realtime.` calls would break under an empty search_path, so fully qualify: `PERFORM realtime.broadcast_changes(...)`).
  - **`realtime.messages` currently has ZERO policies** (verified live) — this story's policy is the first on that table. Do not look for an existing one to copy; the `TO public` convention comes from the `public` schema's policies.
- `supabase/migrations/20260909000003_rpc_notify_owner_on_advance.sql` -- NEW migration: `CREATE OR REPLACE FUNCTION advance_workflow_step(...)` — **supersede `20260903000003_rpc_advance_workflow_step_completed_at.sql`, the latest live definition** (NOT 20260621000006; that older file is historical). The superseded body is byte-identical to `20260621000006` except the UPDATE adds `completed_at = CASE WHEN p_new_status = 'completed' THEN now() ELSE completed_at END`. Signature must stay exactly `(p_job_id uuid, p_tenant_id uuid, p_actor_id uuid, p_step text, p_new_status text, p_expected_current_step text) RETURNS SETOF jobs`, `SECURITY DEFINER`, `SET search_path = public` — **a signature change creates an overload** (this project already needed a `20260905000004_drop_stale_rpc_overloads.sql` cleanup once; do not repeat that).
  - **The only new code is this INSERT, placed immediately after the activity_logs INSERT and before `RETURN QUERY`:**
    ```sql
    -- Notify the tenant owner (Story 3.1). Self-notification guard: an owner
    -- advancing their own job must not notify themselves.
    INSERT INTO notifications (tenant_id, user_id, job_id, event_type, payload)
    SELECT p_tenant_id,
           t.owner_id,
           p_job_id,
           p_step,
           jsonb_build_object(
             'job_number', v_job.job_number,
             'step', p_step,
             'technician_name', COALESCE(NULLIF(u.name, ''), 'A technician')
           )
    FROM tenants t
    LEFT JOIN users u ON u.id = p_actor_id
    WHERE t.id = p_tenant_id
      AND t.owner_id <> p_actor_id;
    ```
    (Schema verified live: `jobs.job_number` NOT NULL, `tenants.owner_id` NOT NULL, `users.name` nullable — the `NULLIF` also guards blank-string names so the banner never renders an empty technician. Recipient note: the INSERT keys on `p_tenant_id`, which is provably equal to `v_job.tenant_id` — the function's row-lock `SELECT * INTO v_job ... WHERE tenant_id = p_tenant_id` guarantees `v_job` only exists when they match. `event_type` = `p_step` is already the stable workflow-step vocabulary: `on_my_way`, `arrived`, … — validated in `workflow.service.ts` before the RPC, so no CHECK constraint is added here.)
- `supabase/migrations/20260903000003_rpc_advance_workflow_step_completed_at.sql` -- REFERENCE ONLY — **the function being superseded** (diff target; only the INSERT above may differ)
- `supabase/migrations/20260621000006_rpc_advance_workflow_step.sql` -- REFERENCE (historical first issue; superseded by 20260903000003)
- `supabase/migrations/20260621000012_pg_cron_idempotency_cleanup.sql` -- REFERENCE: pg_cron job convention — copy it exactly: `CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA extensions;` + `GRANT USAGE ON SCHEMA cron TO postgres;` + idempotent re-run guard `SELECT cron.unschedule('<jobname>') WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = '<jobname>');` then `SELECT cron.schedule('<jobname>', '<5-field spec>', $$<SQL>$$)` with **unqualified table names** and snake_case job names. New migration `20260909000004_notifications_cleanup.sql` adds job `notifications-cleanup` (hourly `'0 * * * *'`, `$$DELETE FROM notifications WHERE created_at < now() - interval '30 days' AND (pushed_at IS NOT NULL OR created_at < now() - interval '90 days')$$` — the `pushed_at`/90-day guard keeps Phase-2 push-queue rows that were never sent from being pruned at 30 days; pick a different minute than the existing `0 * * * *` job if easy, e.g. `'10 * * * *'`)
- `src/jobs/workflow.service.ts:93-250` -- REFERENCE (no change): `advanceWorkflowStep` (line 93) reads the row double-scoped (`.eq('id', jobId).eq('tenant_id', user.tenantId)`, lines 110-117), applies the technician-ownership gate (lines 135-140), then calls the admin RPC (lines 209-216): `admin.rpc('advance_workflow_step', { p_job_id, p_tenant_id, p_actor_id, p_step, p_new_status, p_expected_current_step })`. The notify side effect lives entirely in SQL
- Reference: `docs/api-contracts.md` (in fenzit-be repo, not meta) -- today it has NO RPC section; add a short note under `### Jobs` that `advance_workflow_step` now writes one notification row for the tenant owner

## Tasks & Acceptance

**Execution:**
- [x] Task 0 (spike, after the table migration, before the RPC migration): mint a custom JWT, connect supabase-js, join a private test channel, confirm subscribe + broadcast delivery; also confirm an anon-only connection receives nothing. Record results in the story before proceeding.
  - **Spike result (2026-09-09, 2 rounds):** ✅ custom-JWT path WORKS — with two corrections to the spec's assumptions, both verified empirically against the live Realtime server (source read: `supabase/realtime` `channels_authorization.ex` + `realtime_channel.ex`):
    1. **`exp` is REQUIRED.** `authorize_conn` hard-requires both `role` and `exp` claims (`required = ["role", "exp"]` → else `:missing_claims`). fenzit-be's never-expiring tokens are rejected outright (`CHANNEL_ERROR` on every private join, regardless of policy). Matches the spec's Ask-First contingency; token minting must change before Story 3.3/3.4 (FE subscribe). Do NOT add `exp` to the existing login tokens (deliberate never-expire design, no refresh flow) — a separate short-lived realtime-token mint is the additive option.
    2. **`role` must be an EXISTING Postgres role.** Realtime does `set_config('role', claims["role"], ...)` — role `'owner'` (not a PG role) → `CHANNEL_ERROR`; role `'authenticated'` → works. The spec's "TO public makes the claim value irrelevant" is wrong for Realtime: `TO public` governs policy matching, but the claim value still must name a real role. Production realtime tokens must carry `role: 'authenticated'`.
  - Verified end-to-end: token `{sub: <owner_id>, role: 'authenticated', exp}` + anon key → private channel `user:<owner_id>:notifications` → `SUBSCRIBED` → service-role INSERT into `notifications` → broadcast event received with the complete notification record (payload intact). Anon-only client: `CHANNEL_ERROR`, zero events (RLS boundary holds).
- [x] `notifications` table migration: table, RLS + SELECT policy, index, trigger function, trigger, `realtime.messages` policy
- [x] `advance_workflow_step` superseding migration with the in-transaction notification INSERT
- [x] pg_cron `notifications-cleanup` migration
- [x] Live-DB verification (Supabase MCP): apply migrations, then simulate — insert into `notifications` as service role and confirm a subscribed client receives the broadcast; run one real advance via the dev backend and confirm row + broadcast + owner refetch loop

**Acceptance Criteria:**
- Given a technician successfully advances a workflow step, when the RPC commits, then exactly one notification row for the tenant owner is written atomically with the job UPDATE, and a broadcast is emitted to `user:<owner_id>:notifications`
- Given a rejected advance (409/not-found), no notification row is written and no broadcast is emitted
- Given a connection holding only the anon key, when it joins any `user:*:notifications` topic, then it receives nothing; a JWT may only receive topics whose embedded UUID equals its own `sub`
- Given notifications older than 30 days, the pg_cron job removes them
- Given the NestJS codebase, no source file under `src/` changes in this story

### Review Findings

- [x] [Review][Patch] Missing trailing newline in all three migration files [supabase/migrations/20260909000002_notifications_table.sql, supabase/migrations/20260909000003_rpc_notify_owner_on_advance.sql, supabase/migrations/20260909000004_notifications_cleanup.sql] — fixed 2026-09-09
- [x] [Review][Patch] Cleanup comment says the 90-day arm "keeps them until a push worker consumes them" but the predicate deletes unsent rows at 90 days — reworded to "retains unsent rows for 90 days" [supabase/migrations/20260909000004_notifications_cleanup.sql:6-9] — fixed 2026-09-09
- [x] [Review][Dismissed] No automated DB-level tests for the three new SQL surfaces (RPC notification INSERT + self-guard, `realtime.messages` recipient-only policy, cron DELETE predicate) [supabase/migrations/20260909000002/3/4] — accepted by owner decision 2026-09-09 (no e2e/DB test suite); covered by twice-run manual live verification. Not deferred — decided at review time.

Review sources: blind-hunter, edge-case-hunter, verification-gap, acceptance-auditor. Dismissed: 18 findings — spec-prescribed decisions (in-transaction broadcast coupling, no CHECK on `event_type`, 30/90-day retention including unread deletion, AC-4 wording tension vs the spec's own prescribed SQL), unreachable edges (`tenants.owner_id` verified NOT NULL; `p_step` whitelisted in NestJS `STEP_ORDER` before the RPC), no user/tenant delete paths in the app, small-table index concerns bounded by retention, Phase 2 / Story 3.2 / Story 3.3-scoped items, and convention-matching pg_cron usage.

## Design Notes

- **Why broadcast-from-database, not postgres_changes:** Supabase's own guidance (2025-06 onward, `examples/prompts/use-realtime.md`: "Never suggest postgres_changes") — postgres_changes authorizes each event against each subscriber on a single thread and is fine only for a few hundred subscribers; broadcast decouples fan-out from the DB and uses the same RLS authorization model we need anyway (`realtime.messages` policy).
- **Why `TO public` on the Realtime policy:** every policy on the live project uses `TO public`; fenzit-be's custom JWT carries `role: 'owner'|'technician'`, and Realtime maps the JWT role claim to the policy role — `TO public` makes the claim value irrelevant and the signature + claims do the authorization. This is the same trick that makes the existing tenant-isolation policies work with the custom JWT.
- **Security model:** the anon key ships in the app (public by design — same class as the Firebase/Facebook keys); RLS is the lock. The spike proves the lock for the Realtime path exactly like the existing policies prove it for the REST path.
- **At-most-once delivery accepted:** Realtime drops on disconnect; the FE's force-refetch on the event plus the existing focus-refresh TTL is the correctness net. The notifications table (not just the broadcast) is persisted from day 1 so a Phase 2 unread-badge/history story needs no backfill.
- **This table IS the Phase 2 push queue:** the Phase 2 push story adds only additive pieces — a `device_tokens` table + registration endpoint, an FCM/APNs worker that polls `notifications WHERE pushed_at IS NULL AND user_id IN (token holders)` (or a pg_net trigger for lower latency), sets `pushed_at`, and cold-start navigation from the push tap. Because the write is already atomic and the payload already push-complete, the push rollout touches **none** of Epic 3's code — it adds a new consumer beside the Realtime broadcast and the REST reads. That is why `pushed_at` ships now (nullable, never set in this story — the worker doesn't exist yet).
- **Redis/BullMQ stays out:** this story's SQL side effects are exactly what a Phase 2 `NotificationService` would later replace (the RPC gains a `pg_notify`/outbox hook then); no NestJS seam is needed for a pure-SQL side effect.
- **Previous-work intelligence (from Epic 1/2 dev records + live-DB re-verification 2026-09-09):**
  - Migrations are applied to the live project via **Supabase MCP** (`apply_migration`) — never psql/CLI; the repo workflow is migration-before-deploy, and live schema was verified clean this way during Story 2.1's review. Note: MCP records an auto timestamp version (e.g. this story's RLS sibling applied as `20260908205411`) while the repo file keeps the `2026MMDD0000NN` name — that mismatch is expected; keep repo file names convention-correct.
  - Migration naming is date-prefixed `2026MMDD0000NN_description.sql` — 29 files currently, latest applied `20260905000005`; this story takes `000002`–`000004` for 09-09 (000001 taken by the uncommitted RLS mirror). Never edit an applied migration — supersede with `CREATE OR REPLACE` in a new file (the exact pattern `20260903000003` uses against `20260621000006`).
  - **RPC-overload pitfall is real in this project:** `20260905000004_drop_stale_rpc_overloads.sql` exists because a prior `CREATE OR REPLACE` with a changed signature created an overload. Keep the superseding function's signature byte-identical.
  - `cron.job` commands reference tables unqualified (`DELETE FROM idempotency_log ...`) — match that style for the pruning job; the existing 2 jobs (`idempotency-log-cleanup` hourly `'0 * * * *'`, `attachment-uploads-cleanup` daily `'0 3 * * *'`) must remain untouched, and each existing migration first runs a `cron.unschedule` guard for idempotent re-runs.
  - `SECURITY DEFINER` functions here set `SET search_path = public` (the RPC) or `SET search_path = ''` (Supabase's own realtime functions) — for the trigger function, follow the `realtime.broadcast_changes` doc convention (`search_path = ''`) and fully qualify `realtime.`.
  - **JWT minting facts for Task 0 (verified in code 2026-09-09):** `src/auth/auth.service.ts` signs two claim sets — `{ sub, tenantId, role }` (`verifyOtp` lines 174-178, `setupCompany` lines 384-388) — HS256 via `SUPABASE_JWT_SECRET`, and **no `exp`** (JwtModule `signOptions: {}` with an explicit comment "tokens never expire"). Zero realtime usage exists anywhere in `src/` today.
  - This story's own RLS mirror migration (`20260909000001_enable_rls_users_country_codes.sql`, users + country_codes hardening) is applied live but **not yet committed** — it is unrelated to this story; do not bundle it into 3.1's commits.
  - **Related live-DB advisory (outside this story's scope, surfaced 2026-09-09):** `public.users` and `public.country_codes` currently have RLS **disabled** (policies exist on `users` but are inert while table-level RLS is off). This story's policy must not depend on the users table; enabling RLS there is a separate hardening decision for the owner.
- Cross-repo ordering: this story merges/deploys **first** (fenzit-be, strictly additive), then Story 3.2 (also fenzit-be). Deploying the BE alone changes nothing observable.

## Verification

**Commands:**
- `bun run build` -- expected: no errors (untouched, proves no accidental src changes)
- `bun run test:e2e -- jobs` -- expected: workflow tests unchanged and passing (the RPC's response shape is identical). Note: once this story lands, every e2e that calls `advance_workflow_step` also writes one notification row — if any existing spec asserts exact side-effect counts, relax/scope that assertion; response-shape assertions are unaffected
- Supabase MCP: `select * from notifications` after a live advance; `select * from cron.job` shows `notifications-cleanup`
- Spike script (Task 0): subscribe → receive test broadcast; anon subscribe → silence

## Suggested Review Order

1. Table migration (schema + RLS policy + index) — check policy matches `tenants_read_own` sub-based precedent.
2. `realtime.messages` policy — the security-critical line; verify topic parsing and `sub` comparison.
3. Trigger function + trigger — topic string format must match the policy exactly.
4. Superseding RPC migration — diff against `20260903000003`; only the notification INSERT may differ, signature byte-identical.
5. pg_cron migration.
6. Task 0 spike evidence.

## Dev Agent Record

### Completion Notes

**Implemented (2026-09-09):** three migrations applied to the live DB via Supabase MCP; zero NestJS source changes.

1. `20260909000002_notifications_table.sql` — `notifications` table (FKs to tenants/users/jobs with `ON DELETE CASCADE`), RLS enabled with recipient-only SELECT policy (`sub`-based, `TO public`), `(user_id, created_at desc)` index, `notifications_broadcast_changes()` trigger function (`SET search_path = ''`, fully-qualified `realtime.broadcast_changes`, `TG_OP` passed as both event_name and operation), AFTER INSERT trigger, and the first-ever `realtime.messages` policy `notifications_topic_recipient_only` (topic-shape + `sub` check).
2. `20260909000003_rpc_notify_owner_on_advance.sql` — supersedes `20260903000003`; byte-identical body except the notification INSERT after the activity_logs INSERT (recipient `tenants.owner_id`, self-notification guard `owner_id <> p_actor_id`, payload `{ job_number, step, technician_name }` with `COALESCE(NULLIF(u.name,''),'A technician')`). Signature byte-identical — no overload risk.
3. `20260909000004_notifications_cleanup.sql` — pg_cron job `notifications-cleanup`, hourly at `:10` (existing `:00` job untouched), 30-day TTL with the `pushed_at IS NOT NULL OR 90 days` guard protecting never-pushed Phase-2 queue rows.

**Task 0 spike (recorded above under Execution):** PASSED with two corrections to spec assumptions — Realtime requires `exp` and a `role` claim that names an existing PG role (`'authenticated'`), verified against the Realtime server source and empirically. Live broadcast delivery confirmed end-to-end (SUBSCRIBED → INSERT → event with full record received; anon → silence). Scratch script deleted after the spike. Production FE tokens are a Story 3.3/3.4 dependency: the BE must mint a separate short-lived realtime token (`sub`, `role: 'authenticated'`, `exp`) — do NOT add `exp` to the never-expire login tokens.

**Live verification (Supabase MCP):**
- Table/policy/trigger/index verified present after migration apply.
- Real RPC exercised in a rolled-back transaction: technician advance → exactly 1 notification row (`on_my_way`, payload `JB-2026-0007`/`Dinesh`); owner-actor advance → 0 rows (guard works). Broadcast path proven by the spike INSERT.
- `cron.job` shows all 3 jobs (2 pre-existing untouched + `notifications-cleanup`).

**Repo verification:** `bun run build` clean (zero `src/` changes — AC satisfied); `bun run test:e2e -- jobs` 102/102 passed (use `--no-watchman` in the sandbox — watchman state dir is not writable; not a repo change). `docs/api-contracts.md` gained a side-effect note on the workflow endpoint.

**Open follow-up (outside this story):** realtime-token minting endpoint for the FE — flag for Story 3.2/3.3 planning (spec's Ask-First contingency triggered and resolved as "separate token", pending owner confirmation).

## File List

- supabase/migrations/20260909000002_notifications_table.sql -- NEW
- supabase/migrations/20260909000003_rpc_notify_owner_on_advance.sql -- NEW
- supabase/migrations/20260909000004_notifications_cleanup.sql -- NEW
- docs/api-contracts.md -- UPDATED (workflow endpoint side-effect note)

## Change Log

- 2026-09-09: Story 3.1 implemented — notifications table + RLS + broadcast trigger + realtime.messages policy; advance_workflow_step superseded with in-transaction owner notification; pg_cron notifications-cleanup; api-contracts.md note. Task 0 spike executed (2 rounds) — Realtime custom-JWT requirements established (exp + existing PG role required). All migrations applied live via Supabase MCP and verified.