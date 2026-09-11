---
title: 'Story 4.3: Workflow templates and skill-tagged jobs'
type: 'feature'
created: '2026-09-11'
status: 'done'
baseline_commit: 'ec5a9c97c5ece1bc5a613804badb0a3b8fa5b95b'
review_loop_iteration: 0
context:
  - 'workspace/core/backend/fenzit-be/project-context.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** A job carries no skill and no workflow identity — "what kind of work" is a hardcoded 6-step chain (`STEP_ORDER`) plus a `jobs.service_type` CHECK enum whose values don't even match the skills catalog (`other` has no skill; `cleaning` has no ServiceType). Every job follows the same chain; the engine cannot vary per trade.

**Approach:** One migration creates `workflow_templates` (skill_id, version, steps JSONB, unique per skill+version) with a v1 seed per skill mirroring today's 6-step shape, adds `jobs.skill_id` (required FK) + `workflow_template_id`/`workflow_template_version`, and drops `service_type` + its CHECK. Job creation takes `skillId`: the app validates it against active `skills` rows and `create_job_with_log` stamps the skill's latest template version at insert. Advance engine untouched (Story 4.4). Pre-launch clean cutover — `jobs` currently has 0 rows, no backfill.

## Boundaries & Constraints

**Always:**
- Write AND apply the migration via Supabase MCP (file + `apply_migration`); include a guarded test-data reset (`TRUNCATE jobs CASCADE`) before the column adds so any environment converges (live DB verified 0 job rows).
- FKs RESTRICT for `jobs.skill_id` and `jobs.workflow_template_id` (skills/templates are never API-deleted).
- The stamp is resolved inside the RPC (latest version for the skill, `ORDER BY version DESC LIMIT 1`) and is immutable: no create/PATCH code path writes it again.
- RPC rework avoids the overload trap: `DROP FUNCTION` the old `create_job_with_log` then `CREATE` the new one in the same migration (precedent `20260905000004_drop_stale_rpc_overloads.sql`).
- Advance path stays untouched: `workflow.service.ts` (`STEP_ORDER`, `validateStep`, status mapping), `advance_workflow_step`, `confirm_attachment` — Story 4.4. `current_step` stays `NULL` at creation.
- `require_completion_photo`/`require_completion_signature` flags survive this story (columns + create-RPC params kept; dropped in 4.4).
- Docs updated in the same change; `bun run test` AND `bun run test:e2e` green before any commit.

**Ask First:**
- Any step key/label/attribute beyond mirroring today's chain, or any new error contract (missing-template must be a plain failure, not a new error code).
- Adding skill/template data to job or history/sync responses (read surfaces are Story 4.5 — this story only removes `serviceType`).
- A second migration, or touching `skills` DDL/seed UUIDs.

**Never:**
- No shims, no dual fields, no backfills, no compat view for `service_type`.
- No template CRUD API or owner-facing workflow editing — seeds via migration only.
- No FE changes; no `fenzo-app` work.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Create with valid skillId | active `skills` uuid, v1 seed exists | job row: `skill_id` set, stamp = latest template id+version; response has no `serviceType` | N/A |
| skillId unknown/inactive | uuid absent from `skills` or `is_active = false` | rejected before RPC | 400 |
| skillId shape violations | missing / non-uuid | DTO validation rejects | 422 |
| skill without template | valid skill, no `workflow_templates` row | RPC raises (seed guarantee makes this unreachable) | 500 |
| History/sync/list reads | `service_type` dropped | field gone from selects, mappings, DTOs | N/A |
| DB after migration | inspect via MCP | `workflow_templates` (6 v1 rows, unique skill+version), `jobs.service_type` + `jobs_service_type_check` gone | N/A |

</frozen-after-approval>

## Code Map

- `supabase/migrations/20260621000002_create_jobs.sql` -- `service_type` L14-15 + CHECK; `status`/`current_step`/flags L18-22
- `supabase/migrations/20260905000002_rpc_create_job_with_log_signature.sql` -- current 14-param RPC L8-55: `p_service_type` L13, insert L40-48 (`current_step=NULL`), job_number L34-35, `job_created` log L51-52
- `supabase/migrations/20260905000004_drop_stale_rpc_overloads.sql` -- overload-drop precedent L10-24
- `supabase/migrations/20260910000001_create_global_skills.sql` -- `skills` DDL + 6 seed UUIDs (KEEP untouched); FK target confirmed
- `src/jobs/dto/create-job.dto.ts` -- `serviceType` L45-47 → `skillId` (IsUUID)
- `src/jobs/enums/service-type.enum.ts` -- DELETE; `src/jobs/enums/workflow-step.enum.ts` stays (4.4 retires it)
- `src/jobs/jobs.service.ts` -- `JobResponse.serviceType` L43, `JobRow` L121, `JOB_DETAIL_COLUMNS` L181, list select L556, createJob RPC call L306-321 (`p_service_type` L311), `toResponse` L877
- `src/jobs/dto/update-job.dto.ts` -- L11 stale comment says serviceType immutable in PATCH — update copy
- `src/customers/customers.service.ts` -- `JobHistoryItem.serviceType` L120, `JobHistoryRow` L128, history select L552, mapping L590; `src/customers/dto/customer-detail-response.dto.ts` L26
- `src/users/users.service.ts` -- `JOB_COLUMNS` L31 includes `service_type`
- `src/sync/sync.service.ts` -- delta select L30, mapping L60; `src/sync/dto/sync-response.dto.ts` L22 `SyncJobDto.serviceType`
- Specs/fixtures: `src/jobs/jobs.service.spec.ts` (L40,52,64,180 create-path assert, L168), `src/jobs/workflow.service.spec.ts` (L51 fixture only — chain tests stay), `src/customers/customers.service.spec.ts` (L543,629,636,666,699,721,746), `src/users/users.service.spec.ts` (L113,118), `src/sync/sync.service.spec.ts` (L42,46,63-64)
- E2E: `test/jobs.e2e-spec.ts` (L84,102,255 payloads; L314-319 invalid-serviceType → invalid-skillId; workflow describes untouched), `test/customers.e2e-spec.ts` (L710-809), `test/sync.e2e-spec.ts` (L29,33), `test/idempotency.e2e-spec.ts` (L105,239 fixtures only), `test/conflict-resolution.e2e-spec.ts` (L45-49 fixture only), `test/integration/sync.integration.spec.ts` (L48 real-DB fixture → seed with skill_id)
- Docs: `docs/data-models.md` (jobs DDL L114-135 incl. stale `sequence_index` L131, RPC table L291-293, skills section L246-275 — add workflow_templates), `docs/api-contracts.md` (stale job-create body L254-267 → `skillId`), `docs/architecture.md` (ERD L141-156), `docs/source-tree-analysis.md` (L57 ServiceType enum gone)

## Tasks & Acceptance

**Execution:**
- [x] `supabase/migrations/20260911000002_workflow_templates_skill_tagged_jobs.sql` + MCP apply -- guarded reset (`TRUNCATE jobs CASCADE`); create `workflow_templates` (id UUID PK, skill_id FK RESTRICT, version INT NOT NULL, steps JSONB NOT NULL CHECK `jsonb_typeof(steps) = 'array'`, timestamps, UNIQUE(skill_id, version), RLS SELECT-for-authenticated mirroring `skills_authenticated_read`); seed 6 v1 templates (fixed UUIDs, one per skill, identical chain); alter `jobs`: add `skill_id`/`workflow_template_id` NOT NULL FK RESTRICT + `workflow_template_version` INT NOT NULL; drop `service_type` + `jobs_service_type_check`; drop old `create_job_with_log`, re-issue with `p_skill_id` (no `p_service_type`) stamping latest version in the INSERT
- [x] `src/jobs/dto/create-job.dto.ts` + `src/jobs/enums/service-type.enum.ts` -- swap field, delete enum
- [x] `src/jobs/jobs.service.ts` -- strip `serviceType` from response type/row type/column lists/`toResponse`; createJob validates `skillId` against active `skills` (invite-precedent pattern) and passes `p_skill_id`
- [x] `src/customers/*`, `src/users/users.service.ts`, `src/sync/*` -- drop `service_type` from selects, mappings, DTO fields, types
- [x] Unit + e2e + integration specs -- per Code Map; workflow-chain tests unchanged except fixture cleanup
- [x] Docs (data-models, api-contracts, architecture, source-tree-analysis) -- same change; fix the stale `sequence_index` claim while in data-models

**Acceptance Criteria:**
- Given the migration applied, when inspected via Supabase MCP, then `workflow_templates` exists with 6 v1 seed rows (unique per skill+version), `jobs` carries NOT NULL `skill_id`/`workflow_template_id`/`workflow_template_version` (FK RESTRICT), and `service_type` + its CHECK are absent.
- Given an owner creates a job with a valid active `skillId`, then the created job stamps that skill's latest template id + version at insert, and nothing later mutates the stamp.
- Given `skillId` unknown/inactive/missing/non-uuid, then 400 before the RPC or 422 from DTO validation respectively.
- Given every job/history/sync read, then no response carries `serviceType` and no select references `service_type`.
- Given a fresh clone, when `bun run test` and `bun run test:e2e` run, then all suites pass with no `service_type`/`serviceType` reference outside migration history.

## Spec Change Log

## Review (step-04, 2026-09-11) — 3 review layers, ~29 raw findings → 7 patches / 2 defers / rest rejected

Blind-hunter, edge-case-hunter, verification-gap layers over the full diff since baseline `ec5a9c9` (tracked + untracked). Deduped and triaged:

**Patched (suites re-run green after):**
1. `jobs.service.spec.ts` `skillsChain` eq assertions — the skill-lookup mock never asserted `.eq('id', …)`/`.eq('is_active', true)`, so a dropped filter would still pass the 400 test. Now asserts both (mirrors `auth.service.spec.ts:583`).
2. Real-DB RPC probe — `create_job_with_log` was verified only against mocks + a manual MCP smoke test; added an IS_REAL_DB-gated integration test executing the RPC with `p_skill_id` and asserting the stamp (`skill_id`, template id `8a3c4d5e-…`, version 1), idempotent seeding + `finally` cleanup.
3. `docs/data-models.md:338` — stale "advances `sequence_index`" (column never existed) → "advances `current_step`".
4. `docs/api-contracts.md` — POST /jobs response table gained the 500 line (missing-template raise → `INTERNAL_SERVER_ERROR`, unreachable by the v1 seeds).
5. `docs/data-models.md` workflow_templates section — operational rule added: every new skill seed must ship its template row in the same migration.
6. Migration comment reword — step-1 comment now states the `TRUNCATE jobs CASCADE` is unconditional by design (pre-launch wipe in every environment); comment-only, migration 36 already applied. Trailing newline added.
7. (batched with 6) migration header summary line matched the same reword.
8. Real-DB fixture fix (found on the user's terminal run): both new-probe and pre-existing user_skills seeding used `country_code: '+99'`, which violates `users_country_code_fkey → country_codes(dial_code)` — the catalog holds only real dial codes (`+91` used). All four probe seeds switched to `+91`; no phone-number collisions in the live DB (checked via MCP). The `+99` in the user_skills probe pre-dates this story — it passed 4.2's real-DB run (the catalog must have held a temporary `+99` row then, since removed), so the fixture was latent-broken and surfaced only now.

**Deferred (2) → `deferred-work.md`:** steps JSONB per-step shape validation (Story 4.4 owns the semantics); composite-FK hardening tying `(workflow_template_id, workflow_template_version)` to the template row.

**Rejected highlights (premise false or out of frozen scope):** "other job-response sections still document `serviceType`" — repo-wide grep found zero references; "is_active race between validation and RPC" — no skill-deactivation path exists (developer-seeded catalog, 4.1/4.2 posture); "old 14-param overload survives the DROP" — MCP verified exactly one RPC signature; "FE drift from dropped `serviceType`" — BE-first ordering is owned by Epic 5, accepted in the frozen intent; "RPC error leaks SQL details" — the generic 500 path already logs the message server-side without exposing it.

## Matrix Test Audit (step-03 exit, 2026-09-11)

Every I/O matrix row mapped to a test that RAN green in this session:

| Matrix row | Covering test(s) | Result |
|---|---|---|
| Create with valid skillId | `jobs.service.spec.ts` create-path (`p_skill_id` assert); `jobs.e2e-spec.ts` create ACs (valid skillId payload) | PASS |
| skillId unknown/inactive | `jobs.service.spec.ts:266` (miss on `.eq('is_active', true).maybeSingle()` → 400 before RPC); `jobs.e2e-spec.ts` AC6 well-formed-but-unknown → 400 | PASS |
| skillId shape violations | `jobs.e2e-spec.ts` AC6 non-UUID `skillId: 'teleportation'` → 422 (missing field exercises the same required-`@IsUUID` validator chain) | PASS |
| skill without template → 500 | `jobs.service.spec.ts:309` "throws 500 when the RPC returns an error" — the RPC's plain raise surfaces through exactly this generic path (raise itself verified live via MCP smoke test; unreachable by seed design) | PASS |
| History/sync/list reads | `customers.service.spec.ts`, `users.service.spec.ts`, `sync.service.spec.ts`, `customers/sync/idempotency/conflict-resolution.e2e-spec.ts` — all updated and green | PASS |
| DB after migration | Not jest-testable (mocked suites); verified live via Supabase MCP: 6 v1 template rows, `service_type`/CHECK gone, 3 NOT NULL columns + RESTRICT FKs, exactly 1 RPC overload | VERIFIED (MCP) |

## Implementation Notes (2026-09-11)

- `bun run test --no-watchman`: 28 suites, 441 tests green. `bun run test:e2e --no-watchman`: 14 suites, 251 passed / 6 skipped (5 pre-existing real-DB skips + 1 new: the patched real-DB RPC probe, IS_REAL_DB-gated). `bun run typecheck` clean.
- Live RPC smoke test (inside a rolled-back transaction): new `create_job_with_log` stamped template id + version 1, `status='scheduled'`, `current_step=NULL`, `job_created` log written.
- Migration 36's template seed UUIDs are recorded in `docs/data-models.md` — Stories 4.4/4.5 must reference them, never regenerate.
- Not committed: review (bmad-code-review) precedes any commit per standing rule.
- Real-DB integration run (user terminal, 2026-09-11): `rls-isolation.integration.spec.ts` 7/7 pass — including the new `create_job_with_log` stamp probe (AC Service skill → template `8a3c4d5e-…`, version 1). This completes the Verification section's manual check.

## Design Notes

Seed step shape (identical chain all 6 skills, v1; per-step behaviour is data):

```json
[
  {"key": "on_my_way", "label": "On My Way", "requires_photo": false, "requires_signature": false, "sets_status": "in_progress", "advances_on": null},
  {"key": "arrived", "label": "Arrived", "requires_photo": false, "requires_signature": false, "sets_status": null, "advances_on": null},
  {"key": "in_progress", "label": "In Progress", "requires_photo": false, "requires_signature": false, "sets_status": null, "advances_on": null},
  {"key": "photos_uploaded", "label": "Photos Uploaded", "requires_photo": true, "requires_signature": false, "sets_status": null, "advances_on": "photo_confirm"},
  {"key": "signature_captured", "label": "Signature Captured", "requires_photo": false, "requires_signature": true, "sets_status": null, "advances_on": null},
  {"key": "completed", "label": "Completed", "requires_photo": false, "requires_signature": false, "sets_status": "completed", "advances_on": null}
]
```

Labels are new (today only the FE hardcodes labels); these become the canonical label source the FE later reads. `advances_on: photo_confirm` on `photos_uploaded` encodes today's confirm-attachment auto-advance for Story 4.4 to read.

## Verification

**Commands:**
- `bun run test --no-watchman` -- expected: all unit suites green
- `bun run test:e2e --no-watchman` -- expected: all e2e suites green (both scripts needed; `bun run test` alone excludes test/)
- Supabase MCP `list_tables` + column/constraint SQL -- expected: `workflow_templates` present (6 rows), `jobs` without `service_type`/`jobs_service_type_check`, new FKs RESTRICT

**Manual checks (if no CLI):**
- `test/integration/rls-isolation.integration.spec.ts` passes against the real DB (sandbox blocks `*.supabase.co`; run on user terminal; new table's RLS is SELECT-only so the policy surface is unchanged, but confirm the suite still passes)
- `docs/data-models.md` migration inventory complete (prior rows intact + new row)

## Suggested Review Order

**Schema — the migration is the change's centre of gravity**

- Guarded reset: unconditional `TRUNCATE jobs CASCADE`, wipes test rows pre-launch by design
  [`20260911000002_workflow_templates_skill_tagged_jobs.sql:25`](../../workspace/core/backend/fenzit-be/supabase/migrations/20260911000002_workflow_templates_skill_tagged_jobs.sql#L25)

- `workflow_templates` — steps as data (JSONB array), unique per skill+version, read-only RLS
  [`20260911000002_workflow_templates_skill_tagged_jobs.sql:31`](../../workspace/core/backend/fenzit-be/supabase/migrations/20260911000002_workflow_templates_skill_tagged_jobs.sql#L31)

- v1 seeds: fixed UUIDs, identical 6-step chain, `advances_on: "photo_confirm"` parked for 4.4
  [`20260911000002_workflow_templates_skill_tagged_jobs.sql:55`](../../workspace/core/backend/fenzit-be/supabase/migrations/20260911000002_workflow_templates_skill_tagged_jobs.sql#L55)

- `jobs`: skill tag + NOT NULL stamp columns (RESTRICT), `service_type` + CHECK dropped
  [`20260911000002_workflow_templates_skill_tagged_jobs.sql:88`](../../workspace/core/backend/fenzit-be/supabase/migrations/20260911000002_workflow_templates_skill_tagged_jobs.sql#L88)

- RPC re-issued with `p_skill_id` — DROP then CREATE avoids the overload trap
  [`20260911000002_workflow_templates_skill_tagged_jobs.sql:118`](../../workspace/core/backend/fenzit-be/supabase/migrations/20260911000002_workflow_templates_skill_tagged_jobs.sql#L118)

**Create path — validation and stamping**

- DTO swaps `serviceType` for required `skillId` (`@IsUUID`)
  [`create-job.dto.ts:51`](../../workspace/core/backend/fenzit-be/src/jobs/dto/create-job.dto.ts#L51)

- skillId validated against active `skills` rows before the RPC — 400 on miss
  [`jobs.service.ts:324`](../../workspace/core/backend/fenzit-be/src/jobs/jobs.service.ts#L324)

- RPC call passes `p_skill_id`; the stamp itself is resolved inside the RPC, never by the app
  [`jobs.service.ts:337`](../../workspace/core/backend/fenzit-be/src/jobs/jobs.service.ts#L337)

**Read surfaces — serviceType fully retired**

- Job-detail column list loses `service_type` (advance engine untouched, Story 4.4)
  [`jobs.service.ts:177`](../../workspace/core/backend/fenzit-be/src/jobs/jobs.service.ts#L177)

- Customer history select + mapping drop the field
  [`customers.service.ts:547`](../../workspace/core/backend/fenzit-be/src/customers/customers.service.ts#L547)

- Sync delta select + mapping drop the field
  [`sync.service.ts:27`](../../workspace/core/backend/fenzit-be/src/sync/sync.service.ts#L27)

- Users embed column list drops it
  [`users.service.ts:31`](../../workspace/core/backend/fenzit-be/src/users/users.service.ts#L31)

**Real-DB verification (runs on the user's terminal)**

- RPC probe executes the real `create_job_with_log`, asserts the stamp end-to-end
  [`rls-isolation.integration.spec.ts:328`](../../workspace/core/backend/fenzit-be/test/integration/rls-isolation.integration.spec.ts#L328)

- Expected stamp: AC Service's v1 template id + version 1 (docs-recorded UUID)
  [`rls-isolation.integration.spec.ts:346`](../../workspace/core/backend/fenzit-be/test/integration/rls-isolation.integration.spec.ts#L346)

- Idempotent seeding + `finally` cleanup even on assertion failure
  [`rls-isolation.integration.spec.ts:404`](../../workspace/core/backend/fenzit-be/test/integration/rls-isolation.integration.spec.ts#L404)

**E2E + unit pinning**

- AC6: non-uuid `skillId` → 422 via DTO, well-formed-unknown → 400 before RPC
  [`jobs.e2e-spec.ts:335`](../../workspace/core/backend/fenzit-be/test/jobs.e2e-spec.ts#L335)

- Skill-lookup mock now asserts both `.eq` filters (review patch 1)
  [`jobs.service.spec.ts:266`](../../workspace/core/backend/fenzit-be/src/jobs/jobs.service.spec.ts#L266)

**Contracts & docs**

- Migration 36 row + jobs DDL + workflow_templates section + corrected RPC table
  [`data-models.md:50`](../../workspace/core/backend/fenzit-be/docs/data-models.md#L50)

- Create contract: `skillId` in, `serviceType` out; 500 line for the unreachable raise
  [`api-contracts.md:271`](../../workspace/core/backend/fenzit-be/docs/api-contracts.md#L271)