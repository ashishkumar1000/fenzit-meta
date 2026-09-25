---
title: 'Generalize the notifications backend for technicians + additive entity/dedupe columns'
type: 'feature'
created: '2026-09-25'
status: 'done'
review_loop_iteration: 0
baseline_commit: 'd5c3b91'
context:
  - '{project-root}/artifacts/implementation-artifacts/epic-14-context.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** The realtime notification channel is owner-only — `GET /auth/realtime-token` 403s technicians — and the `notifications` table lacks the additive `entity_type`/`entity_id`/`dedupe_key` columns that later attendance/leave epics need for deep-linking and DB-guaranteed dedupe (AD-13). Without both, later epics have no channel to notify technicians through.

**Approach:** One migration adds the three nullable columns plus a partial unique index on `dedupe_key`; the realtime-token route opens to technicians (AD-18 gate is satisfied by story 14-1); `NotificationResponse` gains `entityType`/`entityId` additively. Everything else (RLS, topic policy, REST scoping) is already role-agnostic — investigation confirmed it — so the change is intentionally small.

## Boundaries & Constraints

**Always:**
- Migration files live in `fenzit-be/supabase/migrations/` AND are applied via Supabase MCP (next number: `20260925000005`).
- DTO change is additive only — `jobId` and every existing field stay; `entityType`/`entityId` are nullable and camelCase.
- Authorization for technicians rests on the existing server-side controls: RLS `notifications_read_own` (`sub = user_id`) and the `realtime.messages` topic policy (both already `sub`-keyed). Do not add a topic claim to the token.
- Update `docs/api-contracts.md` in the same change.

**Ask First:**
- If opening the route requires any change to the legacy `advance_workflow_step` RPC (it must not — rule 6 forbids extending it), HALT.
- If the realtime topic-isolation probe cannot run against the real DB (channel subscription), HALT and propose the fallback before substituting a weaker check.

**Never:**
- No new DB functions/RPCs (project-context rule 6); no new notification insert paths; no job-event notifications for technicians (explicit epic non-goal).
- No breaking change to any Owner-facing field or to existing job/report notification rows.
- No polling fallback, no push notifications, no attendance event types yet (AD-13 registry is a later-epics artifact).

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Technician requests realtime token | Valid technician JWT (14-1 merged) | 200 `{ token, expiresAt }`; claims exactly `{ sub: techId, role: 'authenticated', exp: now+3600 }` | 401 unauthenticated (unchanged) |
| Owner requests realtime token | Valid owner JWT | 200 — response and claims unchanged | — |
| Technician lists notifications | Tech JWT; own + other users' rows in same tenant | Only own rows, camelCase DTO incl. `entityType`/`entityId` (null when unset) | — |
| Foreign-topic subscription | Technician subscribes `user:<otherId>:notifications` with their own valid token | No rows ever delivered (`realtime.messages` policy denies) | silent (no error surface) |
| Duplicate dedupe_key | Second INSERT with same non-null `dedupe_key` | Rejected by the partial unique index | constraint violation |
| Existing insert paths | Job RPC + report inserts (new columns unset) | Rows identical to today; new columns NULL; all existing tests green | — |

</frozen-after-approval>

## Code Map

Investigation evidence (subagent sweep + live-DB findings from 14-1, 2026-09-25):

- `src/auth/auth.controller.ts:152-185` -- the gate: `@Roles(Role.OWNER)` at line 153 on `GET realtime-token`; 403-for-technician doc comment at line 181. THE thing to open.
- `src/auth/auth.service.ts:212-230` -- `mintRealtimeToken(user)` already role-agnostic: claims `{ sub, role: 'authenticated', exp }`, TTL 3600s (const line 48), signed with `SUPABASE_JWT_SECRET`, no `signAsync` options object (a payload `exp` + `expiresIn` option would throw — comment 224-228). No change expected.
- `src/auth/auth.controller.spec.ts:30-37` -- asserts `@Roles` metadata equals `[Role.OWNER]`; must be updated with the gate.
- `src/auth/auth.service.spec.ts:822-880` -- token claim-shape/TTL tests; stay green untouched.
- `src/notifications/notifications.controller.ts:25-28` -- four routes deliberately NOT role-gated (recipient scoping is the authorization) — already technician-safe, no change.
- `src/notifications/notifications.service.ts` -- every method double-scoped `.eq('tenant_id', ...).eq('user_id', ...)`, service-role client, keyset pagination; `toResponse()` (last private method) is where `entityType`/`entityId` mapping goes.
- `src/notifications/dto/notification-response.dto.ts` -- `{ id, jobId, eventType, payload, readAt, createdAt }`; add `entityType: string | null`, `entityId: string | null`.
- DB baseline `supabase/migrations/20260909000002_notifications_table.sql` -- table, RLS ENABLE + SELECT-only policy `notifications_read_own` (44-48), AFTER INSERT trigger `notifications_broadcast_changes()` (54-73) broadcasting to topic `'user:' || NEW.user_id || ':notifications'`, realtime.messages policy `notifications_topic_recipient_only` (77-83) authorizing any sub-holder for their own topic — all already role-agnostic. `job_id` made nullable by `20260920000008`.
- `supabase/migrations/20260913000002_advance_workflow_step_location_params.sql:101-114` -- owner-recipient job INSERT inside the locked legacy RPC (never notify technicians today; do not touch, rule 6).
- `src/reports/engine/report-notifications.ts:31-46` -- app-side service-role insert pattern; the sanctioned pattern for future event inserters (reference only).
- `test/notifications.e2e-spec.ts` -- `techJwt` helper (53-62); currently asserts technician gets 200 + empty list (line 284) — extendable post-confirmation.
- `test/integration/rls-isolation.integration.spec.ts` -- `mintJwt(userId, tenantId, role)` (line 29; JWT carries `tenantId` claim, realtime token does not), `maybeIt` gate (line 38); no realtime topic probe exists yet — this story adds the first ones.
- Next migration number: `20260925000005` (latest is `20260925000004_revoke_references_trigger_on_users.sql`).
- `docs/api-contracts.md:81-104` (realtime-token documented as owner-only) and `:476-492` (list item shape) -- update both.

## Tasks & Acceptance

**Execution:**
- [x] `supabase/migrations/20260925000005_notifications_entity_dedupe_columns.sql` -- `ALTER TABLE public.notifications ADD COLUMN entity_type TEXT, ADD COLUMN entity_id UUID, ADD COLUMN dedupe_key TEXT;` (all nullable, no FK — entity_id is polymorphic) + `CREATE UNIQUE INDEX notifications_dedupe_key_uniq ON public.notifications (dedupe_key) WHERE dedupe_key IS NOT NULL;` -- AD-13's DB-guaranteed dedupe + deep-link target. Apply via Supabase MCP; verify columns/index live.
- [x] `supabase/migrations/20260925000006_notifications_entity_pair_check.sql` -- `CHECK ((entity_type IS NULL) = (entity_id IS NULL))` on `notifications` (applied via Supabase MCP, verified live; all 25 existing both-NULL rows unaffected) -- (review patch) the polymorphic deep-link pair is meaningless half-set. Next migration number: `20260925000007`.
- [x] `src/auth/auth.controller.ts` -- `@Roles(Role.OWNER)` → `@Roles(Role.OWNER, Role.TECHNICIAN)`; update the route's comment (403-for-technician note is now stale; cite AD-18/14-1 as the satisfied gate) -- opens the channel to technicians; token scoping is already server-enforced by the `sub`-keyed `realtime.messages` policy, so no token change.
- [x] `src/auth/auth.controller.spec.ts` -- update the `@Roles` metadata assertion to `[Role.OWNER, Role.TECHNICIAN]` -- keep the guard contract pinned.
- [x] `src/notifications/dto/notification-response.dto.ts` + `src/notifications/notifications.service.ts` (`toResponse()`) -- add nullable `entityType`/`entityId` to `NotificationResponse` and map them from the row -- additive DTO change per AD-13.
- [x] `docs/api-contracts.md` -- realtime-token now issues to technicians (own topic only); list item shape gains `entityType`/`entityId` -- docs in the same change.
- [x] Post-user-confirmation tests (per test-timing rule, only after the user confirms the feature works): `auth` unit tests for the widened gate; `notifications.service.spec` cases for `entityType`/`entityId` mapping; `notifications.e2e-spec.ts` technician list non-empty + foreign rows excluded; `rls-isolation.integration.spec.ts` probes — technician subscribes own topic → own INSERT broadcast received; technician (own valid token) subscribes foreign `user:<id>:notifications` topic → nothing delivered; duplicate `dedupe_key` insert rejected.

**Acceptance Criteria:**
- Given the migration applied, when `information_schema`/`pg_indexes` are inspected, then the three nullable columns and the partial unique index exist, and existing job/report notification rows are byte-identical apart from NULL new columns.
- Given story 14-1 merged, when an authenticated technician calls `GET /api/v1/auth/realtime-token`, then they receive 200 with a token whose claims are exactly `{ sub, role: 'authenticated', exp }` (same 3600s TTL as owners).
- Given a technician token, when they subscribe to another user's `user:<id>:notifications` topic, then no notification row is ever delivered to that subscription (pinned by a real-DB probe).
- Given a technician calls the list/unread-count/mark-read endpoints, then only their own notifications return, in the same shape Owners get, including `entityType`/`entityId`.
- Given all existing suites run after the change, then every previously green suite stays green (additive change; no Owner-facing behavior changed).

## Design Notes

Why the token carries no topic claim: `realtime.messages` RLS (`notifications_topic_recipient_only`) already authorizes each subscriber by `auth.jwt() ->> 'sub'` against `split_part(realtime.topic(), ':', 2)` — a foreign or tenant-wide topic is denied server-side regardless of what the client asks for. Adding a topic claim would duplicate that control.

Realtime broadcast delivers the raw DB row (snake_case) while REST maps to camelCase in `toResponse()` — that split is pre-existing and out of scope; only the REST DTO gains the new fields.

## Verification

**Commands:**
- `cd fenzit-be && bun run test` -- expected: all previously green suites stay green.
- `cd fenzit-be && bunx tsc --noEmit` -- expected: clean.
- Supabase MCP `execute_sql` -- expected: columns + partial unique index present; `pg_indexes` shows `notifications_dedupe_key_uniq`.

**Manual checks (if no CLI):**
- DONE 2026-09-25 — live probe run by the orchestrator with the user's confirmation, all green:
  1. Backend started locally (nest watch); minted a technician login JWT for probe user Ravi (`b397b757`, tenant `c343d7f0`).
  2. `GET localhost:3000/api/v1/auth/realtime-token` with the technician JWT -> **HTTP 200** `{token, expiresAt}`; claims `{sub, role: 'authenticated', exp = now+3600}`. (Previously 403.)
  3. bun + supabase-js probe replicating fenzo-app's client exactly (`accessToken` callback, `config: { private: true }` channels): subscribed to `user:<ravi>:notifications` (own) and `user:<owner>:notifications` (foreign, owner id `ea4a0d86`).
  4. Inserted 2 probe rows (Ravi + owner) via service-role -> **own topic received the INSERT broadcast** (record.user_id = Ravi, probe payload visible, new `entity_id` column present in the raw row); **foreign topic delivered nothing** (private-channel subscription to the owner topic was not authorized — the deny path).
  5. Raw broadcast payload shape (for the later RLS/integration tests): `{ id, table, record: { ...row snake_case incl. entity_id }, ... }` — delivery is BINARY-framed.
  6. Both probe rows deleted; probe script lived in /tmp (nest watcher had picked up an in-repo temp file — keep future probes out of the repo tree).
  - Pre-existing local-env note: ReportWorker tick errors locally with "Node.js detected but native WebSocket not found" (Node 20 vs supabase-js requirement) — unrelated to this story, fine on Render's runtime.
- DONE 2026-09-25 — post-confirmation tests (implementation subagent), all green:
  - `bun run test`: 52 suites, **716 passed** (714 pre-existing + 2 new mapping cases) — nothing regressed.
  - `bun run test:e2e` (stub env): 266 passed, 11 skipped, 2 failed — the 2 failures (`app.e2e-spec.ts`, `auth.integration.spec.ts`) are pre-existing, identical on the unmodified baseline; the new realtime probes are among the skipped without real env.
  - Integration spec against the **real DB** (`.env` exported): **12/12 passed**, including the new probes: (a) technician own-topic private channel → INSERT broadcast received with `record.user_id` match and `entity_type`/`entity_id` in the raw record; (b) same technician token on a foreign `user:<ownerId>:notifications` topic → zero events over the window; (c) duplicate non-null `dedupe_key` rejected with `23505` (NULL keys don't collide); (d) technician e2e list scoped to own rows; (e) technician `GET realtime-token` → 200 with exact claims + 3600s TTL.
  - Test-shaping findings documented in the integration spec comments: the channel name IS the topic (policy only authorizes `user:%:notifications`), and the first channel join can be denied before the `accessToken` callback resolves — realtime-js auto-rejoins, so the probe tolerates a transient `CHANNEL_ERROR` and waits for `SUBSCRIBED`.
  - Probe rows/users cleaned up (verified live: 0 leftover rows/users); `ws` + `@types/ws` added as devDependencies only (no lockfile committed, per repo rule).
- DONE 2026-09-25 — BMAD review (step-04: 3 review layers — blind-hunter, edge-case-hunter, verification-gap) + 7 patches applied, re-verified all green:
  - Patches: notifications pre-clean before users pre-clean (no cascade on `notifications.user_id`); foreign-topic probe now asserts the subscribe status settles on `CHANNEL_ERROR`/`TIMED_OUT` and is never `SUBSCRIBED` (4 s silence kept); e2e token test cross-checks decoded `exp` == `expiresAt`; api-contracts.md gained the broadcast envelope `{ id, table, record }`, the dedupe_key-is-DB-internal note, and the deploy-order note; mandatory tenant-prefixed dedupe_key format documented above the index; new migration `20260925000006_notifications_entity_pair_check.sql` (`CHECK ((entity_type IS NULL) = (entity_id IS NULL))`, applied via MCP, verified live in `pg_constraint`, all 25 existing rows both-NULL); new read-only real-DB probe pinning the list select string to the applied schema.
  - Defer entries logged in `deferred-work.md` (3): dedupe_key index scoping decision at first insert path; entity_type vocabulary (AD-13 registry); dangling entity_id cleanup when target rows are deleted.
  - Review found one new tsc error (TS2352 broadcast-cast in the probe, ×2) — fixed via `as unknown as` casts; re-ran: `bunx tsc --noEmit` **65 errors == baseline parity** (verified against a d5c3b91 baseline worktree), `bun run test` **716/716**, real-DB integration spec **13/13** (12 prior + the new select-pin probe).
  - Next migration number: `20260925000007`.

## Suggested Review Order

**The gate (entry point)**

- Widened `@Roles` opens the realtime channel to technicians; token itself unchanged (AD-18).
  [`auth.controller.ts:159`](../../workspace/core/backend/fenzit-be/src/auth/auth.controller.ts#L159)

**Schema: additive columns + dedupe**

- Three nullable columns (polymorphic, no FK) + the partial unique index; key-format convention above it.
  [`20260925000005_notifications_entity_dedupe_columns.sql:32`](../../workspace/core/backend/fenzit-be/supabase/migrations/20260925000005_notifications_entity_dedupe_columns.sql#L32)

- Review patch: DB-guaranteed pair invariant — the deep-link target is meaningless half-set.
  [`20260925000006_notifications_entity_pair_check.sql:7`](../../workspace/core/backend/fenzit-be/supabase/migrations/20260925000006_notifications_entity_pair_check.sql#L7)

**Additive DTO + mapping**

- `toResponse()` maps the new snake_case columns to camelCase, additive-only.
  [`notifications.service.ts:203`](../../workspace/core/backend/fenzit-be/src/notifications/notifications.service.ts#L203)

- Nullable `entityType`/`entityId` on the shared response shape.
  [`notification-response.dto.ts`](../../workspace/core/backend/fenzit-be/src/notifications/dto/notification-response.dto.ts)

**Contract docs**

- Realtime-token section now documents the technician opening, broadcast envelope, dedupe_key note, deploy order.
  [`api-contracts.md:81`](../../workspace/core/backend/fenzit-be/docs/api-contracts.md#L81)

**Probes (peripherals)**

- The three real-DB probes in one seeded scenario: own-topic delivery, foreign-topic denial (status settles, never SUBSCRIBED), dedupe 23505; plus the select-drift pin.
  [`rls-isolation.integration.spec.ts:1011`](../../workspace/core/backend/fenzit-be/test/integration/rls-isolation.integration.spec.ts#L1011)

- Technician e2e: own-rows-only list + realtime-token claims and `exp`↔`expiresAt` cross-check.
  [`notifications.e2e-spec.ts:520`](../../workspace/core/backend/fenzit-be/test/notifications.e2e-spec.ts#L520)

- Unit mapping cases and the widened-gate metadata assertion.
  [`auth.controller.spec.ts:30`](../../workspace/core/backend/fenzit-be/src/auth/auth.controller.spec.ts#L30)