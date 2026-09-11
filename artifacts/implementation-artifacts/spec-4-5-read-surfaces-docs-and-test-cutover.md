---
title: 'Story 4.5: Read surfaces, docs, and test cutover'
type: 'feature'
created: '2026-09-11'
status: 'ready-for-dev'
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

- `src/jobs/jobs.service.ts` -- the core widening. `JobRow` L110-127 + `JobResponse` L35-55 gain `skill: {id, name}` and `workflowTemplate: {version, steps}`; `JOB_DETAIL_COLUMNS` L173-174 + list inline select L566-571 add the embeds `skills!inner(id, name), workflow_templates(version, steps)`; `toResponse` L882-901 maps them + computes `currentStepIndex` from the parsed steps + `current_step` (reuse `indexOfCurrent` from `workflow-template.model.ts` L~); `toDetailResponse` L848-878 passes through; `getJobDetail` L673-846 and `createJob`/`updateJob` selects must fetch the embeds so their `toResponse` paths carry real values (create/update re-fetch the row with the embeds)
- `src/jobs/workflow-template.model.ts` -- reuse: `parseTemplateSteps` + `indexOfCurrent` (no new model code expected)
- `src/jobs/workflow.service.ts` -- its return path `jobsService.toResponse(rows[0])` L232 now needs the skill embed: add `skill_id, skills!inner(id, name)` to the select at L81 (template embed already there); corrupt-embed posture unchanged
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
- [ ] `src/jobs/jobs.service.ts` + `workflow.service.ts` -- widen `JobRow`/`JobResponse` + all selects (detail, list, create, update); `toResponse` maps skill/template + `currentStepIndex`; advance select gains the skills embed
- [ ] `src/users/users.service.ts` -- profile job rows carry the same fields; stale freeze comment updated
- [ ] `src/sync/sync.service.ts` + `sync-response.dto.ts` + `src/customers/customers.service.ts` + `customer-detail-response.dto.ts` -- sync payload + job-history `skillName`
- [ ] Tests -- update the six fragile shape-pin files + base fixtures per Code Map; new field-presence tests (detail/list/sync/history/profile); `test/fixtures/v1-template.ts` consolidation
- [ ] Docs -- all six files per Code Map, same change
- [ ] Full gate: `bun run test --no-watchman`, `bun run test:e2e --no-watchman`, `bun run typecheck` all green

**Acceptance Criteria:**
- Given a job (fresh or mid-workflow), then `GET /jobs/:id`, `GET /jobs`, `POST /sync`, `POST /jobs/:id/workflow`, and the profile job rows all return `skill {id, name}`, `workflowTemplate {version, steps(key, label, requiresPhoto, requiresSignature, setsStatus, advancesOn)}`, and `currentStepIndex` (null until the first advance).
- Given the customer job-history endpoint, then each row carries `skillName` and the endpoint's existing envelope/cursor is unchanged.
- Given `GET /skills`, then the response is unchanged and documented as the label lookup.
- Given a skill marked inactive, then job reads still return its name.
- Given the docs diff, then all six docs files describe the current model with none of the stale claims (wrong migration numbers, "all four epics delivered", per-tenant skills, `WorkflowStep` enum, `rpc_` prefix) remaining, and the job-response shape is documented.
- Given the whole diff, then no existing response field was renamed/removed and the full suite + typecheck pass green.

## Spec Change Log

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

PostgREST embeds do all the joining — no RPC or SQL change: `skills!inner(id, name)` on `jobs.skill_id` (FK guarantees presence; `!inner` keeps TS mapping total), `workflow_templates(version, steps)` on `jobs.workflow_template_id` (same embed the advance engine already uses at `workflow.service.ts:81`, so the join path is proven). The `indexOfCurrent` helper already in `workflow-template.model.ts` computes the index; a null `current_step` maps to null, and a `current_step` not present in the parsed steps (corrupt row) maps to null too on the read path — reads never 500 on corrupt data (the advance path keeps its 422 guard; divergence is deliberate: reads are soft, writes are strict).

Sync payload note (out of scope, recorded): `SyncJobDto` has always lacked `completedAt` (a pre-existing drift vs `JobResponse`) — leave as-is; Epic 5's FE sync work can raise it if the field is needed.

Cross-repo ordering: additive backend change → this repo merges/deploys FIRST, then `fenzo-app` consumes the shapes in Epic 5 (5-1..5-4). The existing `requireCompletion*` rollout note in api-contracts.md stays until the FE cutover lands.