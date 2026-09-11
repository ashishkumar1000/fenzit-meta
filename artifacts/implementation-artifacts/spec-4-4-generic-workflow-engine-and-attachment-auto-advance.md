---
title: 'Story 4.4: Generic workflow engine and attachment auto-advance'
type: 'feature'
created: '2026-09-11'
status: 'done'
baseline_commit: 'b3105c1af21e96dc7bff764a19ad6fbab9a665a3'
review_loop_iteration: 0
context:
  - 'workspace/core/backend/fenzit-be/project-context.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** The advance engine is hardcoded to one 6-step chain (`STEP_ORDER` + `workflow-step.enum.ts`) and reads the job-level `require_completion_photo`/`require_completion_signature` flags; the templates stamped onto jobs in Story 4.3 are unused at advance time, and `confirm_attachment`'s auto-advance hard-codes `in_progress` → `photos_uploaded`. Per-skill templates can't vary behaviour, and per-step attributes are dead data.

**Approach:** The engine reads the job's stamped template steps (key/label/requires_photo/requires_signature/sets_status/advances_on). The only legal advance target is the first not-yet-completed step in template order (`current_step` NULL → first step); `p_new_status` = the target step's `sets_status` (null keeps current status; RPC's existing `completed_at` stamping covers `completed`). `confirm_attachment`'s auto-advance delegates to `advance_workflow_step` for the template step whose `advances_on = 'photo_confirm'` (fires on first photo + expected predecessor). Job-level flag columns + create/PATCH params are dropped; `workflow_templates.steps` gains a validator-function CHECK (Story 4.3 defer).

## Boundaries & Constraints

**Always:**
- One migration (file written AND applied via Supabase MCP): drop the two flag columns; `DROP FUNCTION` + re-issue `create_job_with_log` and `update_job_with_log` without their flag params (overload-drop precedent `20260905000004`); re-issue `confirm_attachment` with the template-driven auto-advance; add an IMMUTABLE `workflow_steps_valid(jsonb)` validator + CHECK on `workflow_templates.steps` (per-step object shape: non-empty text `key`/`label`, boolean `requires_photo`/`requires_signature`, `sets_status` in ('in_progress','completed')|null, `advances_on` in ('photo_confirm')|null).
- `advance_workflow_step` RPC is NOT modified — it is already generic (`p_step`, `p_new_status`, compare-and-set, activity log, owner notification + self-notify guard, `completed_at` stamp).
- Preserved contracts: 422 `INVALID_WORKFLOW_STEP` echoing `currentStep`; same-step replay dedup (no RPC, full job response); PT409 → 409 `JOB_NOT_MODIFIABLE` (terminal + compare-and-set); 24h idempotency-key replay on workflow + attachment upload endpoints; activity log `step_<key>` events; notifications `event_type` = bare step slug.
- Corrupt-data guard: a non-null `current_step` not present in the stamped template's steps rejects every advance (422), never resets the workflow.
- Auto-advance fires only when the stamped template HAS a `photo_confirm` step AND the confirmed photo is the job's first (COUNT = 1) AND `current_step` equals that step's immediate template predecessor (or is NULL when it is the first step). A delegated advance's PT409 on a terminal job is logged and swallowed — the attachment insert itself must still succeed.
- Photo cap stays unconditional: 5 photos per job, same app-side count, same SQL confirm count, same error mapping (409 `PHOTO_LIMIT_EXCEEDED`) in `attachments` + `webhooks`.
- New TS module stays small (~300-line rule): a `workflow-template.model` (parse/validate stamped steps, next-step, `sets_status`, `photo_confirm` lookup) separate from the engine service.
- Docs updated in the same change; `bun run test` AND `bun run test:e2e` green before any commit.

**Ask First:**
- Any change to `advance_workflow_step`, `workflow_templates` DDL, or skill/template seed UUIDs.
- A second migration.
- Any response-shape addition (template steps/skill in job responses are Story 4.5).

**Never:**
- No step-skipping/effective-chain logic: the template's ordered steps ARE the chain; `requires_photo`/`requires_signature` become FE action gates (Story 4.5), not chain filters.
- No photo-cap template gating (decided: unconditional cap-5).
- No confirm-path inline auto-advance SQL: delegation to `advance_workflow_step` only (decided: owner gets the notification, self-notify guarded).
- No FE changes; no `fenzo-app` work; no template CRUD.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| First advance (fresh job) | `current_step` NULL, requested = steps[0] | RPC called; `p_new_status` = steps[0].sets_status (`in_progress`) | N/A |
| Next advance | requested = steps[i+1] | RPC called; `p_new_status` = steps[i+1].sets_status ?? null | N/A |
| Skip / out-of-order | requested ≠ next step | no RPC call | 422 `INVALID_WORKFLOW_STEP` + currentStep |
| Corrupt current_step | non-null value absent from stamped steps | every advance rejected; `current_step` untouched | 422 |
| Same-step replay | requested == `current_step` | full job response, RPC not called | N/A |
| First photo confirm | COUNT(photo)=1 AND `current_step` = predecessor of the `photo_confirm` step | attachment returned; job auto-advances in same transaction (activity log + owner notification, self-notify guarded) | N/A |
| Photo step not next | COUNT=1 but `current_step` elsewhere in template | confirm succeeds, no auto-advance | N/A |
| Confirm on terminal job | status completed/cancelled, photo step pending | attachment confirmed; delegated advance raises PT409 → logged + swallowed | N/A |
| 6th photo | 5 already confirmed | unchanged cap behaviour | 409 `PHOTO_LIMIT_EXCEEDED` |
| Flags dropped | create/PATCH payload with `requireCompletion*`, or any job read | fields rejected as unknown (DTO whitelist), columns/RPC params/selects/DTOs/response fields gone | 422 (DTO) |

</frozen-after-approval>

## Code Map

- `src/jobs/workflow.service.ts` -- the engine. Delete `STEP_ORDER` L21-28 + `inChain` gating; `WorkflowJobRow` L31-39 loses flags, gains `workflow_template_id`/`workflow_template_version` + the stamped steps (join `workflow_templates` on id+version); select L112-114; `validateStep` L63-91 → template model lookup (successor + corrupt guard); status mapping L200-205 → target step's `sets_status`; rest of `advanceWorkflowStep` L93-250 (dedup L159-175, 422 L180-196, RPC call L209-216) keeps its shape
- `src/jobs/workflow-template.model.ts` -- NEW: parse + validate stamped steps (mirrors the DB CHECK), `nextStep(current)`, `setsStatusOf(key)`, `photoConfirmStep()`; consumed by workflow.service + (SQL-side) confirm rework needs no TS
- `src/jobs/enums/workflow-step.enum.ts` -- DELETE (importers: `workflow.service.ts:16`, `src/jobs/dto/advance-workflow.dto.ts:3`, spec L16); `advance-workflow.dto.ts` step becomes validated slug string (e.g. `^[a-z0-9_]{1,64}$`)
- `src/jobs/dto/create-job.dto.ts` L81,86 + `src/jobs/dto/update-job.dto.ts` L12-16,27-28 -- drop flag fields (+ stale PATCH comment)
- `src/jobs/jobs.service.ts` -- flags out of `JobResponse` L51-52, `JobRow` L125-126, `JOB_DETAIL_COLUMNS` L177-178, createJob RPC args L342-343, updateJob editable subset L403-404, update RPC args L489-490, list select L582, `toResponse` L909-910
- `src/sync/sync.service.ts` L31-32,65-66 + `src/sync/dto/sync-response.dto.ts` L27-28 -- drop flags
- `src/jobs/attachments.service.ts` -- cap count L118-144 + `PHOTO_LIMIT_EXCEEDED` mapping L277-283 unchanged; `confirmUpload` RPC call L246-255 unchanged (RPC signature intact)
- `src/webhooks/webhooks.service.ts` L75-111 -- unchanged: same RPC, acks `PHOTO_LIMIT_EXCEEDED`/`UPLOAD_NOT_FOUND`/`UPLOAD_EXPIRED`
- Migrations -- flags origin `20260621000002` L22 + `20260905000001`; flag RPC params `20260905000002`/`000003`; current `advance_workflow_step` `20260909000003` (terminal+compare-and-set L41-53, status/completed_at L62-69, activity log L72-75, notification+self-notify L78-95) — untouched; current `confirm_attachment` `20260621000014` (cap raise L164-171 stays; hard-coded auto-advance L184-205 replaced by delegation); overload precedent `20260905000004`; template DDL/steps/stamp `20260911000002` L32-96 (seed UUIDs recorded in `docs/data-models.md` — reference, never regenerate)
- Tests -- unit: `workflow.service.spec.ts` (fixtures L33-62 lose flags/gain template steps; validateStep table L107-155 → template-driven; advance describe L157-409), `attachments.service.spec.ts` (cap L165, PHOTO_LIMIT L298), `webhooks.service.spec.ts` L54-126, `jobs.service.spec.ts` (RPC param asserts), `sync.service.spec.ts`; e2e: `jobs.e2e-spec.ts` workflow L1413-1700 + attachments L1715-1990 (fixtures L90-91), `idempotency.e2e-spec.ts` L89-309, `conflict-resolution.e2e-spec.ts` L37,175-270, `sync.e2e-spec.ts` L34-35,136-137; integration: `rls-isolation.integration.spec.ts` L414-434 (drop flag asserts), `sync.integration.spec.ts` L37,156-184
- Docs -- `docs/data-models.md` (jobs L115-143 flags L133-134 gone; activity_logs L147-156 stale `action`/`workflow_advanced` → `event_type`/`step_<key>`; workflow_templates L292-336 add CHECK + auto-advance rule; RPC table L337-347), `docs/api-contracts.md` (create body flags L263-264 gone; workflow ordering L332-365 → template-driven; confirm auto-advance + notification L377-395), `docs/architecture.md` L147-160 (state machine; stale `workflow_advanced` L160; `rpc_confirm_attachment` naming drift L170,184,277), `docs/project-overview.md` L17 ("6-step workflow" → template-driven phrasing)

## Tasks & Acceptance

**Execution:**
- [x] `supabase/migrations/20260911000003_generic_workflow_engine.sql` + MCP apply -- drop flag columns; re-issue `create_job_with_log`/`update_job_with_log` without flag params; re-issue `confirm_attachment` with delegation auto-advance; `workflow_steps_valid()` + CHECK
- [x] `src/jobs/workflow-template.model.ts` (new) + `src/jobs/workflow.service.ts` -- template-driven validateStep + sets_status mapping; delete `workflow-step.enum.ts`; retarget `advance-workflow.dto.ts`
- [x] Flag removal sweep -- `create-job.dto.ts`, `update-job.dto.ts`, `jobs.service.ts`, `sync.service.ts`, `sync-response.dto.ts` (plus `users.service.ts` JOB_COLUMNS)
- [x] Unit + e2e + integration specs -- per Code Map (validateStep table rebuilt around template steps; flag fields stripped from fixtures/assertions; job fixtures carry the template embed the engine now reads)
- [x] Docs (data-models, api-contracts, architecture, project-overview) -- same change

**Acceptance Criteria:**
- Given the migration applied, then via Supabase MCP: flag columns absent, both create/update RPCs carry no flag params, the steps CHECK rejects a malformed steps row, and `advance_workflow_step` is byte-identical to `20260909000003`.
- Given a job stamped template T, then its advances follow T's order (first advance = T's first step, `p_new_status` = target's `sets_status`, intermediate steps keep status, the `sets_status:'completed'` step stamps `completed_at`).
- Given a corrupt `current_step`, then every advance gets 422 `INVALID_WORKFLOW_STEP` echoing `currentStep` and the row is never reset.
- Given the first photo confirm reaching the `photo_confirm` step's predecessor, then the job auto-advances in the confirm transaction with activity log `step_<key>` and an owner notification (self-notify guarded); given a terminal job, the advance failure is logged and the confirm still succeeds.
- Given the whole diff, then no reference to `require_completion_photo`/`require_completion_signature`/`requireCompletion*` remains outside migration history, and no step key or `advances_on` value appears hardcoded in TS or SQL.
- Given a fresh clone, `bun run test` and `bun run test:e2e` pass green.

## Spec Change Log

## Design Notes

Delegation sketch for `confirm_attachment`'s auto-advance (replaces `20260621000014` L184-205): after the photo attachment INSERT, read the stamped template once (`JOIN workflow_templates` on the job's stamp), find `steps->` index whose `advances_on = 'photo_confirm'`; if found AND `v_photo_count = 1` AND the previous template step's key = `current_step` (or the photo step is first and `current_step IS NULL`), call `advance_workflow_step(p_job_id, p_tenant_id, p_actor_id, v_key, (steps->v_i->>'sets_status'), p_expected_current_step := v_prev_key)`; a PT409 raise from the delegated call is caught, logged, and swallowed (attachment already inserted). The RPC's terminal/compare-and-set/notification/completed_at semantics come along unchanged.

Corrupt-template posture: the DB CHECK guarantees shape at write time; the TS model's defensive validation (reject advances on a stamped template that fails parsing) is belt-and-braces for rows written before the CHECK existed.

## Verification

**Commands (all run green post-implementation):**
- `bun run test --no-watchman` -- 28 suites, 434 tests passed
- `bun run test:e2e --no-watchman` -- 14 suites, 252 passed, 6 skipped (pre-existing skips)
- `bun run typecheck` -- clean

**Supabase MCP checks (all inside rolled-back transactions — nothing persisted):**
- Flag columns gone from `jobs` (0 rows in information_schema for both names)
- RPC overloads exactly 1 each: create 12 params, update 10, confirm 5; `advance_workflow_step` byte-identical to `20260909000003`
- `workflow_templates_steps_shape` CHECK rejects: bad `advances_on`, duplicate keys, non-boolean flags, empty label, bad `sets_status`; accepts a valid custom 2-step chain; the 6 v1 seeds pass
- Confirm-path auto-advance probed live (Scenario A: first photo with `current_step` at the photo_confirm step's predecessor → attachment committed + `current_step` = `photos_uploaded` + one `step_photos_uploaded` activity log + one owner notification, self-notify guarded; Scenario B: `current_step` elsewhere → attachment committed, no advance; Scenario C: terminal job → attachment committed, PT409 swallowed, no advance, no error)

## Matrix Test Audit

| Matrix row | Covered by | Status |
|-----------|------------|--------|
| First advance (fresh job) | `workflow.service.spec.ts` "advances on_my_way → 200 (p_new_status in_progress, expected null)"; e2e `jobs.e2e-spec.ts` AC1 | ✅ green |
| Next advance | `workflow.service.spec.ts` "mid step (arrived) → p_new_status null" + "completed step → p_new_status completed"; e2e AC5.8 (photos_uploaded) / AC5.9 (completed) | ✅ green |
| Skip / out-of-order | `workflow.service.spec.ts` it.each table + "skipping a step → 422"; e2e AC6 + AC5 (template order forbids skipping); integration `sync.integration.spec.ts` AC2 (out-of-order + backward) | ✅ green |
| Corrupt current_step | `workflow.service.spec.ts` "corrupt current_step → 422 echoing it" | ✅ green |
| Same-step replay | `conflict-resolution.e2e-spec.ts` AC1 (no-op 200, RPC not called); `sync.integration.spec.ts` same-step no-op tests | ✅ green |
| First photo confirm | DB-verified via MCP Scenario A (activity log + owner notification in the same transaction) — the delegation lives in the SQL RPC, untestable through the mocked e2e layer | ✅ verified live |
| Photo step not next | DB-verified via MCP Scenario B (confirm OK, no advance) | ✅ verified live |
| Confirm on terminal job | DB-verified via MCP Scenario C (PT409 swallowed, attachment committed) | ✅ verified live |
| 6th photo | `attachments.service.spec.ts` cap + PHOTO_LIMIT mapping (unchanged); e2e `jobs.e2e-spec.ts` AC4 409 | ✅ green |
| Flags dropped | `jobs.service.spec.ts` rpcArgs not.toHaveProperty (create + update); `sync.service.spec.ts` + `sync.e2e-spec.ts` negative payload pins; e2e AC2.8 (flag PATCH → 422 via whitelist strip + empty-PATCH guard); `rls-isolation.integration.spec.ts` RPC probe without flag params | ✅ green |

## Implementation Notes

- Subagents were unavailable for most of the session (provider timeouts), so implementation ran directly per the workflow's fallback.
- The engine's corrupt-template posture (500 on unparseable steps / stamp version mismatch / missing embed) fires AFTER the 403/409 guards — earlier gates never need the template, which keeps the mock fixtures minimal.
- e2e/integration job fixtures must carry `workflow_template_version` + `workflow_templates(version, steps)` for any test that reaches the forward-advance path; same-step replays return before the parse and need no embed.
- AC16's old `step: 'teleport'` payload passed the new slug pattern (it is a valid key shape now), so the DTO-validation test was retargeted at `'Teleport Fast'` (pattern violation → 422).
- Cross-repo rollout (flags removal, recorded per review patch): breaking backend change → this repo (`fenzit-be`) merges/deploys FIRST; `fenzo-app` still sends/reads `requireCompletion*` until Story 4.5. Impact today: the ValidationPipe whitelist silently strips the flags on the create path (201, ignored); a PATCH carrying only the flags 422s with "No updatable fields provided". Story 4.5 (FE action gates) removes the app-side sends/reads.

### Review Findings

Three-layer adversarial review (blind-hunter, edge-case-hunter, verification-gap) + acceptance auditor, full mode. Contested claims verified against source before rating: `activity_logs.actor_id` is nullable (migration 8 `DROP NOT NULL`), migration 37 has NO null-actor skip guard and NO log on the no-template-row path, and the SQL validator coerces `key`/`label` via `->>` (the `jsonb_typeof` guards cover only the boolean/enum fields).

- [x] [Review][Decision] Worker-path confirm drops the owner notification — the webhook path calls `confirm_attachment` with `p_actor_id: null` (`src/webhooks/webhooks.service.ts:82`); the delegation to `advance_workflow_step` still runs, the activity log is written (actor nullable), but the notification guard `t.owner_id <> p_actor_id` filters everything out when the actor is NULL, so the owner never hears about the auto-advance. RESOLVED: accepted + documented (Ashish's call) — the Worker path is a reconciliation fallback, the advance and attachment both commit correctly, and the primary app path notifies as specified. Deferred entry added; docs note added.
- [x] [Review][Patch] No-template-row skip is silent — add a `RAISE LOG` on the `v_steps IS NULL` path [supabase/migrations/20260911000003_generic_workflow_engine.sql:477]
- [x] [Review][Patch] Missing trailing newlines in 5 changed files [src/jobs/dto/advance-workflow.dto.ts, src/jobs/workflow-template.model.ts, src/jobs/workflow.service.ts, src/jobs/workflow.service.spec.ts, supabase/migrations/20260911000003_generic_workflow_engine.sql]
- [x] [Review][Patch] architecture.md confirm summary omits the predecessor gating condition (reads as if every first photo advances regardless of `current_step`) [docs/architecture.md:168-171]
- [x] [Review][Patch] Cross-repo rollout note for the flags removal — fenzo-app still sends/reads `requireCompletion*`; record the backend-first order, the whitelist-strip/422-empty-PATCH impact, and the Story 4.5 follow-up [docs/api-contracts.md:264, spec Implementation Notes]
- [x] [Review][Patch] api-contracts workflow section: add the note that photo-optional jobs still walk all template steps (upload/signature gates are FE action gates, Story 4.5) [docs/api-contracts.md workflow endpoint]
- [x] [Review][Patch] Document the Worker-path notification gap: on a Worker-path first-photo confirm the auto-advance fires but the owner notification is skipped (NULL actor filters the guard); the advance and attachment commit correctly — accepted limitation (D1) [docs/api-contracts.md confirm endpoint, docs/architecture.md]
- [x] [Review][Defer] Only PT409 is swallowed; any other delegated-advance error rolls back the attachment insert — unreachable today (the array CHECK + nullable actor close the known raise paths; widening the catch would swallow genuine bugs and deviate from the frozen design notes)
- [x] [Review][Defer] SQL auto-advance has no permanent automated test — verified live this session via 3 rolled-back MCP scenarios; a lasting integration test needs real-DB infra (same gap as the always-skipped RLS suite)
- [x] [Review][Defer] TS parser / SQL CHECK divergence on non-string `key`/`label` (`->>` coerces a JSON number to text and passes; the TS parser requires typeof string → fails safe) — unreachable post-CHECK; fixing the validator needs a new migration (Ask First)
- [x] [Review][Defer] Validator permits degenerate template authoring (mid-chain `sets_status:'completed'` terminal-locks the chain; multiple `photo_confirm` steps resolve to the first; a chain can strand a job in `scheduled`) — authoring-contract gap for future templates, seeds are sane
- [x] [Review][Defer] Create-path flag payload is silently stripped (201) rather than 422 — matches the whitelist mechanism the matrix names and is the safer behaviour for the backend-first deploy; the matrix's 422 wording applies to the PATCH path
- [x] [Review][Defer] TS parser parity unit tests missing (65-char key, whitespace label, non-object array entries) — belt-and-braces for a post-CHECK-unreachable path
- [x] [Review][Defer] `V1_TEMPLATE_STEPS` fixture duplicated across 5 test files — no shared fixture root spans unit/e2e/integration
- [x] [Review][Defer] project-overview.md "all four planned epics delivered" reads stale next to the Epic 5 addition — pre-existing text adjacent to this change

8 further findings dismissed as noise or false positives after verification (docs are clean of flag residue; the claimed activity-log NOT-NULL abort is disproven by migration 8; photo-cap COUNT race, DROP-overload risk, PT409 doc jargon, COUNT reuse, template-exposure endpoint — pre-existing or explicitly out of scope per the frozen spec).