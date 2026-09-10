---
stepsCompleted: [1, 2, 3]
inputDocuments:
  - /Users/ashish.kumar/.claude/plans/fluttering-giggling-cascade.md  # deep-recon validation + second-pass review (2026-09-10)
  - "no PRD.md exists for this feature; FRs/NFRs derived from Ashish's design decisions (conversation, 2026-09-10) validated by deep-recon against fenzo-app, fenzit-be and the live Supabase DB (project pnlvreaijzslfymlnoti)"
  - "second-pass recon sweeps (BE + FE, 2026-09-10) — new touchpoints + test surface, recorded in the plan file's 'Second-pass review' section"
---

# Fenzo - Epic Breakdown: Skill-Driven Workflow Redesign

## Overview

This document provides the epic and story breakdown for the **skill-driven workflow redesign** spanning `fenzit-be` (backend) and `fenzo-app` (frontend). Today the job workflow is one hardcoded 6-step chain (`WorkflowStep` enum + `STEP_ORDER`) and "what kind of work" is expressed through three competing vocabularies (`service_type` DB CHECK enum, free-text `tenant_skills`, `tenants.service_categories`). The redesign replaces all of this with: a fixed global `skills` table (seeded by developers), one skill per job / many per technician, a per-skill workflow defined as ordered steps JSON (`workflow_templates`), and a generic workflow engine that reads the job's stamped template instead of hardcoded step lists. No formal PRD exists; requirements below are derived from the agreed design decisions, validated against real code and the live DB.

**Pre-launch context:** the product is not live — no real users, only test data (27 jobs, 20 users, 10 tenants). Any destructive migration, data reset, or breaking API shape change is allowed. No compat shims, no backfills — clean cutover per change.

## Requirements Inventory

### Functional Requirements

FR1: The system stores skills in a fixed global `skills` table (id, name, is_active) seeded exclusively by developer migrations; owners and technicians can never create, edit, or delete skills through any API or UI.

FR2: Every job carries exactly one skill (`jobs.skill_id` FK), selected by the owner at job creation; the field is required — a job cannot be created without a skill.

FR3: A technician carries many skills (`user_skills` retargeted from free-text `tenant_skills` to global `skills` ids), selected during technician invite; one skill may belong to many technicians.

FR4: Each skill has a workflow defined as an ordered steps JSON (`workflow_templates`: skill_id, version, steps JSONB), authored by developers via seed migrations — no owner-facing workflow editing.

FR5: Each step in the template JSON carries its attributes: key (slug), label, requires_photo, requires_signature, sets_status, and advances_on (e.g. `photo_confirm`) — per-step behaviour is data, not code.

FR6: A job stamps its workflow template id + version at creation; workflow validation for the job's lifetime reads THAT stamped version's steps, never the live template.

FR7: The workflow engine is generic: step-ordering validation reads the job's stamped template (first not-yet-completed step in the template's order is the only legal target), replacing `STEP_ORDER` + the effective-chain flag logic; a fresh job's first advance is the template's first step.

FR8: The photo-confirm auto-advance (currently hardcoded in `confirm_attachment` SQL as `in_progress → photos_uploaded`) becomes a step attribute: the RPC reads the job's stamped template and auto-advances only to the step whose `advances_on` is `photo_confirm`, keeping the same transaction, activity-log, and notification side effects.

FR9: The photo cap (5) continues to be enforced, sourced from the step attribute rather than a job-level flag where the template model makes it step data.

FR10: The backend exposes `GET /skills` (read-only, for authenticated users) so FE can render skill names, labels, and technician matching; job creation takes `skillId` in the payload.

FR11: The backend includes the job's workflow steps (keys, labels, current index, per-step photo/signature behaviour) in job responses so the FE renders the stepper, action bar, and gates dynamically without hardcoded step lists.

FR12: The new-job technician picker filters the roster by exact skill id (job's skill ∈ technician's skillIds) replacing the `serviceCategories` string-normalization matching; EditJob technician reassignment stays unfiltered (explicit decision, 2026-09-10).

FR13: Job status mapping remains driven by step data (`sets_status` attribute): the first step starts the job (`in_progress`), the final step completes it, intermediate steps leave status unchanged; `completed_at` stamps on the completing advance.

FR14: The existing error and idempotency contracts are preserved generically: 422 `INVALID_WORKFLOW_STEP` with `currentStep` echoed, PT409 `JOB_NOT_MODIFIABLE` (terminal + compare-and-set), same-step no-op replay dedup, and 24h idempotency-key replay on workflow + attachment endpoints.

FR15: Notifications and activity logs continue to record step keys generically (`event_type` = step slug, `step_<key>` activity events) with the owner-notification INSERT remaining in the advance transaction; custom step keys flow through unchanged.

FR16: These are retired in this redesign: `tenant_skills` (table + CRUD API + FE skills screens), `jobs.service_type` (+ CHECK constraint), `users.skill_type` (legacy column), `tenants.service_categories` (column + signup mapping + seeding), job-level `require_completion_photo` / `require_completion_signature` flags (columns + create/PATCH params + owner toggles), and the FE lossy category→`service_type` translation chain.

FR17: Reworked RPCs (`create_job_with_log`, `update_job_with_log`, `advance_workflow_step`, `confirm_attachment` variants) accept template-aware params (skill_id, template stamp, step attributes) and stale overload definitions are dropped explicitly in the same migration.

### NonFunctional Requirements

NFR1 (Clean cutover): No transition shims, no dual fields, no backfills — pre-launch; all schema/API/FE changes cut over in one change per repo, destructive migrations allowed, test data resettable.

NFR2 (Atomicity): Step advances and photo-confirm auto-advance keep single-transaction atomicity: `FOR UPDATE` row lock, compare-and-set on `current_step`, custom SQLSTATE PT409 guards, activity log + notification INSERTs in the same transaction.

NFR3 (Error contract): The FE-parsed error shapes survive generically — 422 `INVALID_WORKFLOW_STEP` body carries `currentStep` (echoed by the global exception filter, parsed by `apiError.workflowCurrentStep()`), PT409 maps to 409 `JOB_NOT_MODIFIABLE`.

NFR4 (Resilience to unknown data): `current_step` stays free TEXT with the corrupt-value guard preserved (a non-null current_step not present in the stamped template must reject all advances, never reset the workflow).

NFR5 (Cross-repo ordering): `fenzit-be` ships first, `fenzo-app` second; each repo is its own commit(s) on main, never the meta-repo.

NFR6 (Test parity): All affected spec/e2e files are rewritten or retired in the same change — BE (skills.e2e, jobs.service.spec, invite.e2e, conflict-resolution.e2e, idempotency.e2e, customers specs, auth/users specs, notifications/sync specs, workflow.service.spec) and FE (~250 step/skill vocabulary assertions across 35 files) — with `bun run test` green in both repos before any commit.

NFR7 (Docs in the same change): BE docs (api-contracts.md, data-models.md incl. fixing the stale `sequence_index` claim, architecture.md workflow state machine, project-overview.md, development-guide.md) and FE planning artifacts are updated or marked historical; story artifacts from prior epics get a redesign note, not a rewrite.

NFR8 (Small modular code): ~300-line limit per file; the generic engine, template model, and API layer are split across focused files.

### Additional Requirements

- Seed data authored as migrations: global `skills` seed rows (start with the current trades: plumbing, electrical, AC service, AC installation, pest control, cleaning/housekeeping — final list confirmed at story time) and one `workflow_templates` row per skill (v1), mirroring today's 6-step chain shape unless a skill genuinely needs a different chain.
- The live `advance_workflow_step` definition (migration 20260909000003) supersedes two earlier generations — the new definition must preserve the owner-notification INSERT + activity-log INSERT inside the same transaction.
- Reworked `confirm_attachment` RPC generations (…09/13/14) are superseded in one migration; the photo-confirm auto-advance reads the stamped template.
- No triggers, views, materialized views, or analytics code reference workflow columns today (verified) — the new schema introduces none either.
- The Cloudflare R2 worker has no step/skill coupling — untouched.
- Epic-4 groundwork (offline queue, `useWorkflowAdvance` enqueue seam, `attachmentUploadModel` confirm-replay entry) is designed against template steps; spec doc `4-2-offline-action-queue-idempotent-replay.md` is re-specced before any Epic-4 work.
- FE step-vocabulary consolidation: the four duplicated copies (technician stepperModel, owner JobDetailScreen STEP_ORDER/STEP_LABELS, eventLabels, notificationBanner/Card models) become data-driven from the job's template steps; unknown steps keep the existing graceful raw-text fallbacks.
- FE photo/signature special-casing (photos_uploaded non-tappable exception, signature positional 422 reconcile, photoHint branch, "Step N of N") is replaced by step-attribute-driven logic.
- FE signup/owner onboarding drops the `businessTypes → serviceCategories` mapping (`AuthFlow.tsx`, `constants.ts`, `authApi.ts`) and the company-setup seeding path in BE `setupCompany` is removed.

### UX Design Requirements

No dedicated UX design contract exists for this feature (verified — existing `ux-designs/` folders belong to earlier features). Owner- and technician-facing rendering requirements are captured as FRs 10-12 and the FE consolidation bullet in Additional Requirements; visual design of existing screens carries over (skill picker replaces the service-category tile grid; stepper visual model unchanged, now data-driven).

### FR Coverage Map

| FR | Epic | Note |
|----|------|------|
| FR1 (skills table) | 4 | BE schema + seed + RLS |
| FR2 (job.skill_id) | 4 | create payload + RPC |
| FR3 (user_skills) | 4 | retarget to global skills |
| FR4/FR5 (templates + step attrs) | 4 | seed migrations |
| FR6 (template stamp) | 4 | at job creation |
| FR7 (generic engine) | 4 | validateStep rewrite |
| FR8 (advances_on) | 4 | confirm_attachment RPC |
| FR9 (photo cap from step data) | 4 | |
| FR10 (GET /skills, skillId) | 4 | BE API |
| FR11 (steps in job responses) | 4 | BE response shape |
| FR12 (picker filter) | 5 | FE |
| FR13 (sets_status) | 4 | engine + RPC |
| FR14 (error/idempotency contract) | 4 | BE preserves |
| FR15 (notifications/activity generic) | 4 | RPC side effects preserved |
| FR16 (drops) | 4 (BE drops) + 5 (FE deletions) | split by repo |
| FR17 (RPC rework + overload drop) | 4 | |
| FR1-FR11 FE-side delivery | 5 | FE cutover |

## Epic List

### Epic 4: Skill-Based Job Core (Backend)
The owner creates a job by selecting a skill from a fixed list; the job stamps its workflow template at creation; the workflow engine runs from the template — the hardcoded 6-step chain is gone.

**Delivers:** global `skills` table (seeded) + `workflow_templates` (steps JSON, v1 seed per skill) + `jobs.skill_id` + template stamping + generic engine (`validateStep`, `advance_workflow_step` with the advances_on attribute) + `confirm_attachment` RPC rework + `GET /skills` + steps in job responses + dropping all the old columns/tables (`tenant_skills`, `service_type`, `users.skill_type`, `service_categories`, the require flags) + RPC signature rework.

**FRs covered:** FR1-FR10, FR13-FR17

### Epic 5: Skill-Driven Experience (Frontend)
The FE switches to the new BE shapes — the owner sees a skill picker at job creation, the technician picker filters by exact skillId, the stepper / action bar / notifications all render from the job's template steps, and the old skills CRUD screens are deleted.

**FRs covered:** FR12 (exact skillId filtering), plus the FE-side delivery of FR1-FR11.

**Natural dependency:** Epic 5 builds purely on Epic 4 — that is why the BE merges and deploys first. Epic 4 stands alone (API-level functionality complete); Epic 5 completes the user-facing value.

## Epic 4: Skill-Based Job Core (Backend)

The owner creates a job by selecting a skill from a fixed list; the job stamps its workflow template at creation; the workflow engine runs from the template — the hardcoded 6-step chain is gone.

### Story 4.1: Global skills catalog with read-only API

As an **owner**, I want a fixed platform-wide list of skills (plumbing, electrical, AC service, etc.), so that job tagging and technician skills use one trustworthy vocabulary.

**Acceptance Criteria:**

**Given** migrations run, **When** I inspect the DB, **Then** a `skills` table exists (id, name unique, is_active, timestamps) with seed rows for the confirmed trade list, and RLS allows read for any authenticated user but writes only via service role.
**And** given any authenticated user, **When** they call `GET /skills`, **Then** they get the seeded list (id + name); no create/update/delete endpoint exists.
**And** given the old tenant-skills endpoints still running, **When** nothing touches the new table, **Then** nothing breaks (purely additive — no drops in this story).

### Story 4.2: Technician skills cut over to the global catalog

As a **technician**, I want my skills to reference the fixed global catalog, so that my skill list matches exactly what jobs will be tagged with.

**Acceptance Criteria:**

**Given** the skills table exists, **When** the migration runs, **Then** `user_skills` is retargeted (`skill_id` FK → `skills.id`), existing invite data is discarded (pre-launch), and the `tenant_skills` table plus its CRUD API (`POST/GET/DELETE /skills` tenant-scoped, SkillsModule) are dropped.
**And** given an owner invites a technician, **When** the payload carries `skillIds`, **Then** validation checks ids against the global `skills` table (still min 1 / max 20 / unique), and the created technician's skill rows reference global ids.
**And** given `setupCompany` runs, **When** the company is set up, **Then** no tenant-skill seeding happens; `tenants.service_categories` column, the signup FE mapping's backend counterpart, and related embeds are removed.
**And** given `GET /users` / job-detail technician embeds, **When** skills are returned, **Then** they come from the retargeted join (global ids + names).

### Story 4.3: Workflow templates and skill-tagged jobs

As an **owner**, I want every job to carry one skill and the workflow template for that skill, so that the job follows its trade's own process from the moment it is created.

**Acceptance Criteria:**

**Given** migrations run, **When** I inspect the DB, **Then** a `workflow_templates` table exists (skill_id, version, steps JSONB, unique on skill_id+version) with a v1 seed chain per skill mirroring today's 6-step shape; each step carries key, label, requires_photo, requires_signature, sets_status, advances_on.
**And** given `jobs` is altered, **When** a job is created with `skillId`, **Then** `jobs.skill_id` is required (FK) and the job stamps `workflow_template_id` + `workflow_template_version` at creation; `service_type` and its CHECK constraint are dropped from `jobs`, and the create RPC + DTO accept `skillId`.
**And** given a skill has a template, **When** a job is created for it, **Then** the stamped version is immutable for that job's lifetime.
**And** given existing test data, **When** the migration completes, **Then** test jobs are reset (pre-launch, no backfill).

### Story 4.4: Generic workflow engine and attachment auto-advance

As a **technician**, I want my job to advance through its own skill's workflow steps, so that each trade follows exactly the steps that trade requires.

**Acceptance Criteria:**

**Given** a job with a stamped template, **When** a step advance is requested, **Then** validation reads the stamped template: the only legal target is the first not-yet-completed step in template order; a fresh job accepts the template's first step.
**And** given a step whose `advances_on` is `photo_confirm`, **When** the first photo is confirmed via `confirm_attachment`, **Then** the RPC auto-advances to that step in the same transaction with its activity log; steps without the attribute never auto-advance.
**And** given the photo cap, **When** photos are confirmed against the photo step, **Then** the cap (5) is enforced from the step's attribute (replacing the job-level flag source) across app count, SQL confirm count, and error mapping in attachments + webhooks services.
**And** given step data, **When** the first step advances, **Then** status becomes `in_progress`; the `sets_status: 'completed'` step finishes the job and stamps `completed_at`; intermediate steps leave status unchanged.
**And** given the old flags are dropped, **When** the create/PATCH RPCs are re-issued, **Then** `require_completion_photo/signature` params are gone and stale RPC overloads are dropped explicitly.
**And** given error/idempotency replay, **When** requests replay within 24h, **Then** 422 `INVALID_WORKFLOW_STEP` still echoes `currentStep`, PT409 still maps to `JOB_NOT_MODIFIABLE`, and the same-step no-op dedup still returns current state.
**And** given any advance, **When** it commits, **Then** the activity log (`step_<key>`) and owner notification INSERTs remain in the same transaction (self-notify guard preserved).
**And** given a `current_step` value not present in the stamped template, **When** any advance is attempted, **Then** it is rejected (corrupt-data guard).

### Story 4.5: Read surfaces, docs, and test cutover

As a **developer**, I want the read-side APIs, docs, and tests consistent with the new model, so that the FE cutover (Epic 5) has a complete, documented contract.

**Acceptance Criteria:**

**Given** a job response (detail, list, sync), **When** it is fetched, **Then** it includes the stamped template's steps (key, label, requires_photo, requires_signature, current index) plus the job's skill id/name; `GET /skills` serves the label lookup.
**And** given the customer job-history endpoint, **When** it returns rows, **Then** the skill label replaces `service_type`; sync payloads carry the same new shape.
**And** given BE docs, **When** this story merges, **Then** api-contracts.md, data-models.md (including fixing the stale `sequence_index` claim), architecture.md, project-overview.md, and development-guide.md describe the new model.
**And** given the full BE test suite, **When** `bun run test` runs, **Then** all rewritten/retired specs pass (skills.e2e retired; jobs.service.spec, invite.e2e, conflict-resolution, idempotency, customers, auth/users, notifications, sync updated to the new vocabulary).

## Epic 5: Skill-Driven Experience (Frontend)

The FE switches to the new BE shapes — the owner sees a skill picker at job creation, the technician picker filters by exact skillId, the stepper / action bar / notifications all render from the job's template steps, and the old skills CRUD screens are deleted.

### Story 5.1: Job creation with skill picker and exact technician matching

As an **owner**, I want to pick a skill when creating a job and see only technicians who have that skill, so that the right people are offered for the right job.

**Acceptance Criteria:**

**Given** the new-job flow, **When** I choose what kind of job to create, **Then** a skill picker fed by `GET /skills` replaces the service-category tiles; the selection is required before proceeding.
**And** given a selected skill, **When** the technician picker loads, **Then** the roster is filtered to technicians whose `skillIds` contain that skill id (exact match — no string normalization) for new-job creation; edit-job reassignment stays unfiltered (explicit decision).
**And** given submission, **When** I create the job, **Then** the payload sends `skillId` (the `toJobServiceType` translation chain and `ServiceTypePicker` are deleted).
**And** given signup/onboarding, **When** the owner sets up the company, **Then** the business-type → `serviceCategories` mapping is gone from `AuthFlow`, `constants.ts`, and `authApi.ts`.

### Story 5.2: Dynamic technician workflow from template steps

As a **technician**, I want my job's stepper, action buttons, and photo/signature flows to come from the job's actual template, so that each trade shows exactly its own steps.

**Acceptance Criteria:**

**Given** a job's template steps from the API, **When** the technician renders the stepper, **Then** steps, labels, count, and photo/signature behaviour all come from template data (`stepperModel`, `WorkflowStepper`, `workflowActionBarModel` become data-driven; the `photos_uploaded` non-tappable exception and the `photoHint` branch become step-attribute checks).
**And** given an advance or a 422, **When** the server responds, **Then** `useWorkflowAdvance` works generically (the `signature_captured` special-case and positional 422 reconcile become step-attribute driven) and the Epic-4 enqueue seam retains the idempotency key against the new step model.
**And** given photo confirm, **When** the server auto-advances, **Then** `useAttachmentUpload`/`attachmentUploadModel` handle the confirm-replay entry against the new advances_on model.
**And** given an unknown step key, **When** any model renders it, **Then** the existing graceful raw-text fallbacks still apply (no crash).

### Story 5.3: Owner-side step display and edit flow cleanup

As an **owner**, I want job detail, cards, and history to show skill-based steps, so that every screen reflects the job's actual trade process.

**Acceptance Criteria:**

**Given** the owner job-detail screen, **When** it renders, **Then** the "Step N of M" line and its local `STEP_ORDER`/`STEP_LABELS` copy are driven by the job's template steps (unknown steps keep the "Step 0" guard behaviour generically).
**And** given the edit flow, **When** I edit a job, **Then** the photo/signature requirement toggles and their `editJobModel` draft/`buildPatch` handling are removed (behaviour now comes from the template).
**And** given job card / home / customer history screens, **When** they render, **Then** the skill label lookup replaces `SERVICE_TYPE_LABEL`/`serviceTypeToIcon` (no undefined renders — `JobCard`, `TodaysJobsSection`, `HistoryRow`, `TechJobDetailContent`).
**And** given the notification surfaces, **When** a step notification arrives, **Then** `StageStepper`, `notificationBannerModel`, and `notificationCardModel` resolve step labels from the job's steps (raw-text fallback for unknown keys).

### Story 5.4: Deletions, docs, and FE test cutover

As a **developer**, I want the FE free of the old vocabulary and its tests/docs consistent, so that the codebase has one step/skill model only.

**Acceptance Criteria:**

**Given** the skills feature (SkillsScreen, AddSkillSheet, MoreScreen row, route, `useSkills` create/remove), **When** the cutover merges, **Then** they are deleted and `useSkills` becomes a read-only store over `GET /skills`; `AddTechnicianSheet` works unchanged against the global list.
**And** given the API layer, **When** the cutover merges, **Then** the `WorkflowStepApi` 6-value union, `JobServiceType` map, and `skillService` write paths are removed from `src/services/resources/`.
**And** given FE docs, **When** the cutover merges, **Then** planning artifacts (`api-contracts`, `prd`, `epics`, `ui-design-spec`) get a redesign note and the Epic-4 offline-queue spec (4-2) is re-specced against template steps.
**And** given the full FE suite, **When** `bun run test` runs, **Then** the ~250 old-vocabulary assertions across 35 files are rewritten/retired and the suite passes.