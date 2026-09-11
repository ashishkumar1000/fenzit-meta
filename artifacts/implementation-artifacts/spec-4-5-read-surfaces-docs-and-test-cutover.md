---
title: 'Story 4.5: Read surfaces, docs, and test cutover'
type: 'feature'
created: '2026-09-11'
status: 'done'
baseline_commit: '0704105fa17d60e5b3da206a930cdd01fbe80ea2'
review_loop_iteration: 0
context:
  - 'workspace/core/backend/fenzit-be/project-context.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** The template-driven engine (Story 4.4) reads the stamped template internally but discards it on the way out — NO read surface (job detail, list, sync, customer job-history, profile job rows) exposes `skill_id`, the skill name, the template version, or the template steps. The FE (Epic 5) has no source for the `requires_photo`/`requires_signature` action gates or the stepper; the customer job-history rows carry no skill label (`service_type` was dropped in 4.3 and nothing replaced it); the docs still carry stale claims (wrong migration numbers, "all four epics delivered", "per-tenant skill catalog", dead `WorkflowStep` enum, `rpc_` prefix) and never document the job-response shape at all.

**Approach:** Widen the shared `JobResponse`/`JobRow` contract with two embeds — `skill: {id, name}` and `workflowTemplate: {version, steps: [...]}` — plus a computed `currentStepIndex` (null until the first advance), so detail, list, profile job rows, and every `toResponse` path (create/update/advance) carry the same shape. `SyncJobDto` gains the same fields; the customer job-history rows gain `skillName`. `GET /skills` is already the label lookup (`{skills: [{id, name}]}` — `name` IS the display label; no code change). All DB reads ride existing PostgREST FK embeds (`skills`, `workflow_templates` on the job's stamp) — NO migration. Docs sweep across all six docs files; tests updated for the widened shapes.

## Boundaries & Constraints

**Always:**
- Additive only: new response fields never rename or remove an existing field; preserved contracts (422 `INVALID_WORKFLOW_STEP` echoing `currentStep`, same-step replay dedup, PT409 → 409 `JOB_NOT_MODIFIABLE`, 24h idempotency replay, activity log `step_<key>`, notifications, photo cap 409) untouched.
- Steps in API responses are mapped to camelCase — `{key, label, requiresPhoto, requiresSignature, setsStatus, advancesOn}` — matching the camelCase convention of the rest of the job payloads; `currentStepIndex` is 0-based, null while `current_step` is null.
- A job's skill name renders regardless of `skills.is_active` (historical jobs keep their label — no is_active filter on job embeds; only `GET /skills` filters).
- Every producer of `JobResponse` selects the embeds — missing-embed is defensive-mapped to null fields in TS, never a 500 (FK + immutable stamp + no template delete path make it unreachable; the belt-and-braces mapping keeps reads soft).
- Docs updated in the same change; `bun run test` AND `bun run test:e2e` green + `bun run typecheck` clean before any commit; `test/integration/rls-isolation.integration.spec.ts` untouched (always-skipped, already new-model).

**Ask First:**
- Any migration, any DDL, any change to `advance_workflow_step`/`confirm_attachment` RPCs, or to the `skills`/`workflow_templates` seed rows.
- Any change to the `GET /skills` response shape or route.
- Exposing template steps on any surface beyond the ones this story names (e.g. a template-inspection endpoint).
- Removing the `JobResponse`-shape freeze comment contract in `users.service.ts` (update its wording instead — Story 3.9's freeze predates the stamp model).

**Never:**
- No FE changes, no `fenzo-app` work (Epic 5 owns the FE cutover; the api-contracts rollout note about `requireCompletion*` stays until then).
- No breaking change: old clients (fenzo-app today) keep working untouched — this is the additive step of the cross-repo ordering rule (BE adds shape → FE switches in Epic 5).
- No template CRUD, no skill write endpoints, no new dependencies.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Job detail read | `GET /jobs/:id` | `skill: {id, name}` + `workflowTemplate: {version, steps[camelCase]}` + `currentStepIndex` alongside existing fields | N/A |
| Fresh job (no advance yet) | `current_step` NULL | `currentStepIndex: null`, steps list still complete | N/A |
| Mid-workflow job | `current_step` = steps[i].key | `currentStepIndex: i` | N/A |
| Job list page | `GET /jobs` (both scopes) | every row carries the same skill/template fields (keyset pagination unchanged) | N/A |
| Advance response | `POST /jobs/:id/workflow` | unchanged advance semantics; the returned `JobResponse` now also carries the new fields | existing 422/409 contracts intact |
| Sync payload | `POST /sync` | same skill/template fields per job (existing fields untouched) | N/A |
| Customer job-history | `GET /customers/:id` | each row adds `skillName` (label), existing 4 fields + cursor unchanged | N/A |
| Profile job rows | `GET /users/me`, owner technicians | same new fields (ProfileJobResponse extends JobResponse) | N/A |
| Inactive skill on a job | `skills.is_active = false` | job reads still return the skill name (label is historical) | N/A |
| Template embed missing | defensive posture (unreachable) | new fields null; response still 200 | no 500 on a read |
| `GET /skills` | label lookup | unchanged `{skills: [{id, name}]}`; docs state name = display label | existing 401/404 behaviour |

</frozen-after-approval>

## Code Map

Repo: `workspace/core/backend/fenzit-be` (all code changes land here; commit in fenzit-be).

- `src/jobs/jobs.service.ts` -- the core widening. `JobRow` L110-127 + `JobResponse` L35-55 gain `skill: {id, name}` and `workflowTemplate: {version, steps}`; `JOB_DETAIL_COLUMNS` L173-174 + list inline select L566-571 add the embeds `skills(id, name), workflow_templates(version, steps)` (superseded — plain left embeds per Change Log 1, NOT the `!inner` first written here); `toResponse` L882-901 maps them + computes `currentStepIndex` from the parsed steps + `current_step` (reuse `indexOfCurrent` from `workflow-template.model.ts` L~); `toDetailResponse` L848-878 passes through; `getJobDetail` L673-846 and `createJob`/`updateJob` selects must fetch the embeds so their `toResponse` paths carry real values (create/update re-fetch the row with the embeds)
- `src/jobs/workflow-template.model.ts` -- reuse: `parseTemplateSteps` + `indexOfCurrent` (no new model code expected)
- `src/jobs/workflow.service.ts` -- its return path `jobsService.toResponse(rows[0])` L232 now needs the skill embed: add `skill_id, skills(id, name)` to the select at L81 (plain left embed per Change Log 1; template embed already there); corrupt-embed posture unchanged
- `src/users/users.service.ts` -- profile job rows: `JOB_COLUMNS` L30-31 + the profile jobs select in `embedProfileJobs` L529-641 gain the same embeds; `ProfileJobResponse` L106-126 inherits the fields via `JobResponse`; update the stale freeze comment L102-105 (Story 3.9) to the new wording; technician skill embeds (L275-296, L389-407) untouched
- `src/sync/sync.service.ts` L29-34 select + mapping, and `src/sync/dto/sync-response.dto.ts` L15-33 `SyncJobDto` -- add skill + template steps + currentStepIndex (camelCase)
- `src/customers/customers.service.ts` -- `getJobHistory` L542-591: select L550 adds `skills(name)` embed on `jobs.skill_id`; `JobHistoryItem` L115-127 + mapping L583-588 add `skillName`; DTO `src/customers/dto/customer-detail-response.dto.ts` `JobHistoryItemDto` L9-24 gains the field
- `src/skills/skills.service.ts` + `skills.controller.ts` -- NO code change (`name` already the label); docs only. Epic AC4's "skills.e2e retired" is ALREADY DONE — Story 4.2 rewrote `test/skills.e2e-spec.ts` to the new model (CRUD-404 removal guards + global-catalog reads); keep it as-is, do not retire or rewrite it further
- `src/jobs/jobs.controller.ts`, `attachments.service.ts`, `webhooks.service.ts`, all DTOs, migrations -- untouched (no DB change)
- Tests -- fragile shape pins to update: `src/jobs/jobs.service.spec.ts` L464 (list item exact toEqual) + select assertion ~L446 + `jobRow` fixture ~L40-56 (gains embeds; also detail/create fixtures), `src/customers/customers.service.spec.ts` L622, L734 (jobHistory toEqual + history fixture gains skill name), `test/customers.e2e-spec.ts` L709-723, `src/sync/sync.service.spec.ts` L31 trap pin + L74-85 payload shape (+ fixture embeds), `test/sync.e2e-spec.ts` payload asserts ~L126, `src/jobs/workflow.service.spec.ts` fixtures L26+ (rows gain the skills embed), `test/jobs.e2e-spec.ts` base `jobRow` fixture (gains embeds) + new assertions on detail/list/sync fields, `src/users/users.service.spec.ts` profile job fixtures (gains embeds). Additive-safe pins (nested toEqual) need no change. New tests: detail/list/sync/history responses carry skill + steps + `currentStepIndex` (null on fresh job); inactive-skill name still returned
- Fixture dedup (4.4 defer): extract the 6-step v1 chain from `test/jobs.e2e-spec.ts` L1424-1437, `test/idempotency.e2e-spec.ts` L43, `test/conflict-resolution.e2e-spec.ts` L60, `test/integration/sync.integration.spec.ts` L40 into `test/fixtures/v1-template.ts`; the two `src/` unit copies (`src/jobs/workflow.service.spec.ts` L26, jobs.service fixture) stay inline (jest rootDir src boundary) — note as acceptable
- Docs -- per-file fixes: `docs/api-contracts.md` (L398-399 migration refs 13/14 → 16 + 20/21; NEW job-response shape section documenting skill/workflowTemplate/currentStepIndex + the jobHistory `skillName`; PATCH L326-337 note the flags-only-PATCH 422; `GET /skills` section L200-210 note name = display label), `docs/architecture.md` (L191 + L298 migration refs 13/14 → 16 + 20/21; L263-275 Epic Coverage Map — replace the stale "all four planned epics delivered" framing and add the skills/template redesign rows; L104 pg_cron mis-attributed to Story 4.2 — migration 12 predates it), `docs/data-models.md` (L242 same pg_cron attribution fix; add a short read-surface note: skill + stamped template exposed on job reads; `sequence_index` is already clean — nothing to do), `docs/project-overview.md` (L7 "fixed workflow" → template-driven; L12-13 stale epic-coverage claim; L61 "Per-tenant skill catalog" → global catalog), `docs/development-guide.md` (add the skill-seed-ships-its-template-row rule + steps-shape CHECK note to Common Tasks/RPC recipe), `docs/source-tree-analysis.md` (L38 dead auth enums line; L57 `WorkflowStep` enum gone; L52 `rpc_advance_workflow_step` → `advance_workflow_step`; L103 "22 migrations" → 38; L112 filename typo; L114 skills.e2e is read-only now; add missing `notifications`/`places` e2e entries)

## Tasks & Acceptance

**Execution:**
- [x] `src/jobs/jobs.service.ts` + `workflow.service.ts` -- widen `JobRow`/`JobResponse` + all selects (detail, list, create, update); `toResponse` maps skill/template + `currentStepIndex`; advance select gains the skills embed
- [x] `src/users/users.service.ts` -- profile job rows carry the same fields; stale freeze comment updated
- [x] `src/sync/sync.service.ts` + `sync-response.dto.ts` + `src/customers/customers.service.ts` + `customer-detail-response.dto.ts` -- sync payload + job-history `skillName`
- [x] Tests -- update the six fragile shape-pin files + base fixtures per Code Map; new field-presence tests (detail/list/sync/history/profile); `test/fixtures/v1-template.ts` consolidation
- [x] Docs -- all six files per Code Map, same change
- [x] Full gate: `bun run test --no-watchman`, `bun run test:e2e --no-watchman`, `bun run typecheck` all green

**Acceptance Criteria:**
- Given a job (fresh or mid-workflow), then `GET /jobs/:id`, `GET /jobs`, `POST /sync`, `POST /jobs/:id/workflow`, and the profile job rows all return `skill {id, name}`, `workflowTemplate {version, steps(key, label, requiresPhoto, requiresSignature, setsStatus, advancesOn)}`, and `currentStepIndex` (null until the first advance).
- Given the customer job-history endpoint, then each row carries `skillName` and the endpoint's existing envelope/cursor is unchanged.
- Given `GET /skills`, then the response is unchanged and documented as the label lookup.
- Given a skill marked inactive, then job reads still return its name.
- Given the docs diff, then all six docs files describe the current model with none of the stale claims (wrong migration numbers, "all four epics delivered", per-tenant skills, `WorkflowStep` enum, `rpc_` prefix) remaining, and the job-response shape is documented.
- Given the whole diff, then no existing response field was renamed/removed and the full suite + typecheck pass green.

### Review Findings

- [x] [Review][Patch] Advance/PATCH/detail/list e2e never assert the Story 4.5 fields on a jobs response — make the advance test's RPC row bare and its `jobRefetch` row embed-bearing, then assert `skill`/`workflowTemplate`/`currentStepIndex` on the advance body; assert the same fields on the PATCH and detail/list bodies [test/jobs.e2e-spec.ts]
- [x] [Review][Patch] `updateJob`'s re-fetch→embeds mapping has no unit test (create's is tested; PATCH's identical path is not) — mirror the create-route test [src/jobs/jobs.service.spec.ts]
- [x] [Review][Patch] Sync select's new embed columns are pinned nowhere — add the same select-string assertion the change applies to list/detail/profile [src/sync/sync.service.spec.ts]
- [x] [Review][Patch] Profile-surface field-presence test missing — only the select string is pinned, the mapped profile rows are never asserted to carry `skill`/`workflowTemplate`/`currentStepIndex` [src/users/users.service.spec.ts]
- [x] [Review][Patch] No soft-read test for a missing skill embed in the job-history path (`skillName: null`) [src/customers/customers.service.spec.ts]
- [x] [Review][Patch] Sync keeps a hand-copied job column list instead of composing from the exported `JOB_COLUMNS` — future columns silently miss the sync payload [src/sync/sync.service.ts:33-41]
- [x] [Review][Patch] `SyncWorkflowStep`/`SyncWorkflowTemplate` duplicate the model's `WorkflowStepResponse` shape field-for-field — alias to the model type so the two cannot drift [src/sync/dto/sync-response.dto.ts:22-35]
- [x] [Review][Patch] The to-one skill-embed normalizer exists three times (jobs.service private, customers.service inline, sync.service inline) — export one helper from `workflow-template.model.ts` and reuse [src/jobs/jobs.service.ts:998, src/customers/customers.service.ts:588, src/sync/sync.service.ts:62]
- [x] [Review][Patch] `JobHistoryItem.skillName` comment says null is "unreachable under the FK" — wrong: jobs created before the skill column existed have NULL `skill_id` (docs document exactly this null case) [src/customers/customers.service.ts:118-121]
- [x] [Review][Patch] `test/fixtures/v1-template.ts` is missing its trailing newline (trips prettier/lint) [test/fixtures/v1-template.ts]
- [x] [Review][Patch] Fixture comment "six identical steps per skill" is misleading — the six steps are distinct; the point is they're identical across skills [test/fixtures/v1-template.ts:2]
- [x] [Review][Patch] `GET /customers/:id` response line still documents the stale envelope `{ customer, jobs: JobSummary[], nextCursor }`, directly contradicting the new Story 4.5 block's `jobHistory` envelope [docs/api-contracts.md:247]
- [x] [Review][Patch] `currentStepIndex` second null case (corrupt/unknown `current_step` → null on reads) documented nowhere [docs/api-contracts.md:284, docs/data-models.md]
- [x] [Review][Patch] Rollout note says the app stops sending `requireCompletion*` "in its Story 4.5 change" — the FE cutover is Epic 5, not 4.5 [docs/api-contracts.md:292-295]
- [x] [Review][Patch] Dangling colon at the end of the rewritten project-overview intro (the bullet list it introduced was deleted) [docs/project-overview.md:15]
- [x] [Review][Patch] Source-tree documents `src/auth/enums/` — the directory does not exist in the repo [docs/source-tree-analysis.md:38-39]
- [x] [Review][Patch] Source-tree annotates the skills module "Story 4.2" — the global-catalog read-only API was Story 4.1 (sprint-status: `4-1-global-skills-catalog-with-read-only-api`) [docs/source-tree-analysis.md:62]
- [x] [Review][Patch] "Seed a new skill" recipe omits `skills.sort_order`, which pins the GET /skills picker order [docs/development-guide.md:135-145]
- [x] [Review][Patch] Epic Coverage Map's trailing "no Epic 3/4 retro yet" is ambiguous now that two rows are numbered 4 [docs/architecture.md:288]
- [x] [Review][Patch] Spec Design Notes still prescribe the rejected `!inner` embeds, contradicting this spec's own Change Log item 1 [spec-4-5-read-surfaces-docs-and-test-cutover.md:144]
- [x] [Review][Defer] RPC-write → re-fetch race window (concurrent mutation between RPC and re-fetch can make the response report a newer state) — deferred, pre-existing two-query posture; a snapshot fix needs an RPC/migration change, which is Ask-First in this spec [src/jobs/jobs.service.ts:942-963]
- [x] [Review][Defer] FK embeds are never executed against real PostgREST anywhere (all suites mock the factory) — deferred, pre-existing verification posture; the suggested fix touches `test/integration/rls-isolation.integration.spec.ts`, which this story's boundaries keep untouched [src/jobs/jobs.service.ts:213-215]

## Spec Change Log

- 2026-09-11 (dev): `skills!inner` → **plain left embeds** (`skills(id, name)`, `workflow_templates(version, steps)`). The Code Map suggested `!inner`, but `!inner` silently drops list rows whose skill embed is missing and 404s detail reads — that breaks the frozen I/O matrix's soft-read row ("new fields null; response still 200"). Plain left embeds keep the row; missing embeds map to null fields in TS. Documented in `jobs.service.ts` next to `JOB_COLUMNS`.
- 2026-09-11 (dev): create/update/advance write RPCs return bare `jobs` rows (no embeds, `RETURNS SETOF jobs`). Instead of merging pre-fetched embeds into the RPC row, every write path re-fetches the row with `JOB_COLUMNS` via the new `JobsService.refetchWithEmbeds` helper; a failed re-fetch degrades to the RPC row (embed fields null) — a successful write is never turned into a 500.
- 2026-09-11 (dev): `test/fixtures/v1-template.ts` consolidation covers the four `test/` copies; the two `src/` inline copies (`jobs.service.spec`, `workflow.service.spec`) remain — jest's src rootDir boundary keeps `test/` imports out of reach there (accepted per Code Map).

## Dev Agent Record

**Implementation notes:**

- `JOB_COLUMNS` (renamed from `JOB_DETAIL_COLUMNS`, exported) is the single select string — `id … skill_id, skills(id, name), workflow_templates(version, steps)` — reused by detail, list, profile (`users.service` imports it), the workflow replay fetch, and the post-write re-fetch.
- `toResponse` maps the embeds through `normalizeSkillEmbed` (postgrest-js types to-one embeds as arrays even when they arrive as objects) and `currentStepIndexForRead` (reuses `indexOfCurrent`; corrupt/unknown `current_step` → null on reads — soft, per the frozen matrix; only the advance path keeps its 422/500 guards).
- Corrupt-template posture on reads: unreadable `steps` → `workflowTemplate: null` + `currentStepIndex: null`, response still 200 (unit-tested).
- Sync payload: same three fields on `SyncJobDto` (step keys stay snake_case; the other step fields are camelCase).
- Customer job-history: `skills(name)` embed → `skillName` (object-or-array normalized).

**Debug log (test surgery, condensed):**

- Unit: mockAdmin needed a `jobs` maybeSingle branch for `refetchWithEmbeds`; exact `toEqual` pins needed the three new fields; workflow spec's jobsService mock needed a `refetchWithEmbeds` passthrough; the fallback test's RPC row had to be bare (real RPC rows carry no embeds).
- postgrest-js to-one embed typing: casts need `as unknown as JobRow[]` (jobs.service, users.service).
- jobs.e2e: `dualChain` helper (terminal resolves through `.single()` AND `.maybeSingle()`); PATCH/newCustomer tests need their `jobs` re-fetch mock to return the post-edit row; the workflow advance tests needed `jobRefetch` (gate fetch = pre-advance row, re-fetch = advanced row) — and the chain must be built ONCE per mock (a fresh chain per `from('jobs')` call restarts the queue).
- Final gate: unit 28 suites / 444 tests green; e2e 14 suites / 252 passed + 6 skipped (unchanged skips); typecheck clean.

## File List

- `src/jobs/jobs.service.ts` — JobRow/JobResponse widened, JOB_COLUMNS, refetchWithEmbeds, toResponse mapping
- `src/jobs/workflow-template.model.ts` — stepToResponse + currentStepIndexForRead (+ WorkflowStepResponse)
- `src/jobs/workflow.service.ts` — replay select → JOB_COLUMNS; advance returns re-fetched row
- `src/jobs/jobs.service.spec.ts`, `src/jobs/workflow.service.spec.ts` — pins + new tests
- `src/users/users.service.ts` + spec — profile rows via JOB_COLUMNS; freeze comment; profile embed-select pin
- `src/sync/sync.service.ts`, `src/sync/dto/sync-response.dto.ts`, `src/sync/sync.service.spec.ts` — payload widening
- `src/customers/customers.service.ts`, `src/customers/dto/customer-detail-response.dto.ts`, `src/customers/customers.service.spec.ts` — jobHistory skillName
- `test/fixtures/v1-template.ts` (new), `test/jobs.e2e-spec.ts`, `test/customers.e2e-spec.ts`, `test/sync.e2e-spec.ts`, `test/idempotency.e2e-spec.ts`, `test/conflict-resolution.e2e-spec.ts`, `test/integration/sync.integration.spec.ts`
- `docs/api-contracts.md`, `docs/architecture.md`, `docs/data-models.md`, `docs/project-overview.md`, `docs/development-guide.md`, `docs/source-tree-analysis.md`

## Design Notes

Response shape (documented verbatim in api-contracts.md):

```jsonc
// added to every JobResponse (detail, list, sync, profile rows, advance result)
"skill": { "id": "<uuid>", "name": "Plumbing" },
"workflowTemplate": {
  "version": 1,
  "steps": [
    { "key": "en_route", "label": "En route", "requiresPhoto": false, "requiresSignature": false, "setsStatus": "in_progress", "advancesOn": null }
    // ... full ordered chain
  ]
},
"currentStepIndex": 2   // null until the first advance
```

PostgREST embeds do all the joining — no RPC or SQL change: plain left embeds `skills(id, name)` and `workflow_templates(version, steps)` on `jobs` (NOT `!inner` — see Change Log 1: `!inner` silently drops list rows whose skill embed is missing, breaking the I/O matrix's soft-read row; a plain left embed keeps the row and the TS mapping degrades missing embeds to null fields), with `workflow_templates` using the same embed the advance engine already uses at `workflow.service.ts:81`, so the join path is proven. The `indexOfCurrent` helper already in `workflow-template.model.ts` computes the index; a null `current_step` maps to null, and a `current_step` not present in the parsed steps (corrupt row) maps to null too on the read path — reads never 500 on corrupt data (the advance path keeps its 422 guard; divergence is deliberate: reads are soft, writes are strict).

Sync payload note (out of scope, recorded): `SyncJobDto` has always lacked `completedAt` (a pre-existing drift vs `JobResponse`) — leave as-is; Epic 5's FE sync work can raise it if the field is needed.

Cross-repo ordering: additive backend change → this repo merges/deploys FIRST, then `fenzo-app` consumes the shapes in Epic 5 (5-1..5-4). The existing `requireCompletion*` rollout note in api-contracts.md stays until the FE cutover lands.- 2026-09-11 (review): **Review patch round applied** — all 20 `patch` findings resolved (3-layer review: 0 decision-needed, 20 patch, 2 defer, 10 dismissed). Code reuses: sync select composes from the exported `JOB_COLUMNS`; `SyncWorkflowStep`/`SyncWorkflowTemplate` aliased to the model's `WorkflowStepResponse`/`WorkflowTemplateResponse` (now shared from `workflow-template.model.ts`); one `normalizeSkillEmbed` helper exported from the model, replacing the three inline copies (jobs/customers/sync); `JobHistoryItem.skillName` comment corrected (NULL `skill_id` rows are the real null case). Tests: advance e2e mocks a bare RPC row + embed-bearing re-fetch and asserts skill/template/index (index 0); PATCH/list/detail bodies assert the Story 4.5 fields; `updateJob` re-fetch unit test; sync select-string pin; profile field-presence passthrough test; job-history null-skill + array-embed tests (5 new unit tests, 449 total). Docs: stale customer-detail envelope fixed, second `currentStepIndex` null case documented, rollout note corrected to Epic 5, dangling colon, source-tree phantom `auth/enums/` + Story 4.1 attribution, dev-guide `sort_order`, unambiguous retro line, spec Design Notes `!inner` contradiction aligned with Change Log 1. Fixture: trailing newline + comment reworded. Gates after patches: unit 28 suites/449 tests, e2e 14 suites/252 passed + 6 skipped, typecheck clean. Status → done; sprint synced.
