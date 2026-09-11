# Epic 5 Context: Skill-Driven Experience (Frontend)

<!-- Compiled from planning artifacts. Edit freely. Regenerate with compile-epic-context if planning docs change. -->

## Goal

The backend (Epic 4, already shipped) replaced the old hardcoded 6-step workflow and three competing "kind of work" vocabularies (`service_type`, `tenant_skills`, `service_categories`) with a fixed global skills catalog and per-skill workflow templates stamped onto each job. Epic 5 is the frontend cutover to those new shapes: the owner picks a skill (not a service-category tile) when creating a job, the technician picker matches by exact skill id, and every FE surface that currently renders steps from hardcoded lists — technician stepper, action bar, photo/signature gates, owner job-detail, job cards, history, and notifications — instead renders from the job's own template-steps API data. The epic finishes by deleting the retired skills-CRUD screens/APIs and old step/service-type vocabulary, and bringing FE docs and tests in line. This is purely FE work; it builds on Epic 4's API contract and does not touch the backend.

## Stories

- Story 5.1: ✓ Job creation with skill picker and exact technician matching (DONE)
- Story 5.2: ✓ Dynamic technician workflow from template steps (DONE)
- Story 5.3: ✓ Owner-side step display and edit flow cleanup (DONE)
- Story 5.4: ✓ Deletions, docs, and FE test cutover (DONE)

## Requirements & Constraints

- The new-job technician picker must filter the roster by exact skill-id match (job's skill must be in the technician's skillIds) — no string normalization. Edit-job technician reassignment stays unfiltered; this is a deliberate, already-made decision, not something to revisit.
- Job creation sends `skillId` in the payload; the skill picker (fed by `GET /skills`) is a required selection before proceeding, replacing the service-category tile grid.
- Job API responses (detail, list, sync, customer job-history) now carry the job's stamped workflow steps — key, label, current index, and per-step `requires_photo`/`requires_signature`/`sets_status`/`advances_on` — plus the job's skill id/name. All FE step rendering, gating, and status-progression logic must be driven by this data, not by any hardcoded step list or service-type mapping.
- Step behavior is data, not code: photo-confirm auto-advance, the 5-photo cap, and status transitions (start-on-first-step, complete-on-final-step) are all attributes on the step object, not special-cased logic.
- Unknown/custom step keys must keep working via the existing graceful raw-text fallback wherever step labels are rendered (stepper, notifications, history) — never crash on an unrecognized key.
- Error/idempotency contracts from the backend are unchanged and must keep working: 422 `INVALID_WORKFLOW_STEP` echoes `currentStep`, 409 maps to `JOB_NOT_MODIFIABLE`, same-step replay is a no-op, and the offline-queue idempotency key (from Epic 4 groundwork) still applies against the new step model.
- Clean cutover only: no compat shims, no dual old/new fields, no reading the legacy `service_type`/`tenant_skills`/`service_categories`/completion-flag vocabulary anywhere in FE by the end of this epic. Pre-launch product — breaking changes are fine, no migration path needed for existing data.
- All FE specs touching the old vocabulary (~250 assertions across ~35 files) must be rewritten or retired in the same change, with `bun run test` green before any commit.
- FE planning artifacts (api-contracts, prd, epics, ui-design-spec) get a redesign note in this epic; the Epic-4 offline-queue spec (story 4-2) must be re-specced against template steps as part of this epic's doc work.
- Keep files modular, roughly a 300-line ceiling per file — split the data-driven step model, API layer, and screen logic rather than growing one large file.

## Technical Decisions

- Four separate hardcoded copies of step vocabulary currently exist in FE and must consolidate into one data-driven model sourced from the job's template steps: the technician `stepperModel`, the owner `JobDetailScreen`'s `STEP_ORDER`/`STEP_LABELS`, `eventLabels`, and the `notificationBanner`/`notificationCard` models.
- Several special-cased behaviors become generic step-attribute checks instead of hardcoded branches: the `photos_uploaded` non-tappable stepper exception, the `photoHint` branch, the signature positional-422 reconcile in `useWorkflowAdvance`, and the "Step N of N" owner copy.
- Being deleted in this epic: `SkillsScreen`, `AddSkillSheet`, the More-screen skills row/route, `useSkills`'s create/remove paths (becomes read-only over `GET /skills`), `ServiceTypePicker`, the `toJobServiceType` translation chain, the `WorkflowStepApi` 6-value union, the `JobServiceType` map, and `skillService`'s write paths — all under `src/services/resources/` and related screens.
- Signup/onboarding's business-type → `serviceCategories` mapping is removed from `AuthFlow`, `constants.ts`, and `authApi.ts`.
- `editJobModel`'s photo/signature-requirement draft/`buildPatch` handling is removed — that behavior now comes entirely from the job's template, not an owner-set toggle.
- Owner-side screens (`JobCard`, `TodaysJobsSection`, `HistoryRow`, `TechJobDetailContent`) replace `SERVICE_TYPE_LABEL`/`serviceTypeToIcon` lookups with the skill label from the job/skills data.

## UX & Interaction Patterns

- No dedicated UX design spec exists for this feature. Visual design carries over from existing screens: the skill picker takes over the same required-selection slot the service-category tile grid occupied; the stepper's visual model is unchanged — only its data source changes from hardcoded lists to the job's template steps.

## Cross-Story Dependencies

- All of Epic 5 depends on Epic 4 (backend), which is already merged and deployed — the new skills/workflow-templates API shapes this epic consumes already exist in production.
- Within the epic, natural build order follows the story numbering: 5.1 (skill picker + `skillId` payload) establishes the new job-creation path; 5.2 and 5.3 make technician and owner surfaces data-driven against template steps; 5.4 (deletions, docs, test cutover) should land last, since it removes the old vocabulary that earlier stories are migrating away from.
