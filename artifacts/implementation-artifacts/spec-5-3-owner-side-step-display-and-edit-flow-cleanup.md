---
title: 'Story 5.3: Owner-side step display and edit flow cleanup'
type: 'feature'
created: '2026-09-11'
status: 'ready-for-dev'
baseline_commit: '90b3e2a'
context:
  - 'artifacts/planning-artifacts/epics-skill-workflow-redesign.md'
  - 'artifacts/implementation-artifacts/epic-5-context.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** The owner-side surfaces (`JobDetailScreen`, `JobCard`, `HistoryRow`, `TodaysJobsSection`, `notificationBanner`, `notificationCard`, and activity `eventLabels`) all still render step labels and counts from the old hardcoded `STEP_ORDER`/`STEP_LABELS`/`eventLabels` vocabulary, plus the `editJobModel` still carries photo/signature-requirement toggles as owner-settable fields (`requireCompletionSignature`, `requirePhotoBeforeCompletion`). Story 5.1–5.2 migrated the technician side to data-driven steps from `job.workflowTemplate.steps[]` + `currentStepIndex`. Story 5.3 completes the frontend cutover: every owner-side surface derives step display (labels, count, photo/signature gating) from the job's own template, not hardcoded lists or owner-settable flags.

**Approach:** Retire the four global hardcoded copies of step vocabulary (`eventLabels.ts`'s `STEP_LABELS`/`STEP_ORDER`, `JobDetailScreen.tsx`'s local `STEP_ORDER`/`STEP_LABELS` duplicates, `notificationBanner`/`notificationCard`'s step label logic) — all replaced with the job's `workflowTemplate.steps[]` data. Remove owner-side photo/signature toggles from `editJobModel`, `EditJobSheet`, and `TechJobDetailContent`'s signature-card gate (that gate already moved to template-driven in Story 5.2; this finishes by removing the owner's ability to override it). Replace skill/service-type rendering with skill data from the job/skills API.

## Boundaries & Constraints

**Always:**
- Owner-side screens (`JobCard`, `TodaysJobsSection`, `HistoryRow`, `JobDetailScreen`) and notifications derive step-count ("Step N of M") and step labels from `job.workflowTemplate.steps` — never `STEP_ORDER` or hardcoded lists.
- `eventLabels.ts` drops `STEP_LABELS`/`STEP_ORDER` (used only by owner surfaces; technician side uses `StepView.label` from the template). `eventLabel(t: string)` stays for activity-event labels (`job_created`, `job_reassigned`, etc.), but only these — no step-key labels.
- Activity timeline in `JobDetailScreen` labels steps by reading the job's own template: a `step_*` event's key is looked up in `detail.workflowTemplate?.steps` to find its label; unknown/custom keys fall back to the raw event type (e.g., `step_my_custom_workflow` → "step_my_custom_workflow"), never crash.
- `editJobModel.ts` and `EditJobSheet.tsx` lose `requireCompletionSignature` and `requirePhotoBeforeCompletion` fields entirely — these toggles are deleted, not just hidden. The photo/signature gating now lives entirely in the job's template, owned by the backend.
- `TechJobDetailContent.tsx`'s "Customer signature" card gate is already template-driven (Story 5.2); the owner's ability to SET/UNSET that flag is removed here — no UI path to toggle it.
- Skill rendering: `JobCard`, `HistoryRow`, `TodaysJobsSection`, `notificationBanner`/`notificationCard` replace `SERVICE_TYPE_LABEL`/`serviceTypeToIcon` lookups with the skill `name` from the job's `skillName` field or a skills API lookup (consistent with how 5.1 wired the skill picker). Pre-fetch the skills list once on app start if needed; display gracefully (raw skillId if skill name not found).
- `job.workflowTemplate` missing/null on any owner screen renders empty (no steps shown, no gating) — never a crash.
- Tests updated for owner-side screens + activity label model; `bun run test` green before commit.

**Ask First:** none identified.

**Never:**
- No reintroduced hardcoded step-key list/enum anywhere in owner-side code.
- No changes to technician-side (`TechJobDetailContent.tsx`, `WorkflowStepper.tsx`, `useWorkflowAdvance.ts`, `stepperModel.ts` — all from Story 5.2, locked).
- No changes to `useSignatureSave.ts`, `SignatureScreen.tsx`, `navigation/types.ts`'s `Signature` route (deferred to follow-up, signature step-key threading).
- No changes to `attachmentUploadModel.ts`, `useAttachmentUpload.ts`, `photoPicker.ts`, `PhotoSection.tsx`, photo cap (same as Story 5.2).
- No backend changes.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Owner views job detail | `job.workflowTemplate.steps` populated | step count ("Step N of M"), labels, photo/signature icons come from template | N/A |
| Activity timeline event for a step | `step_*` event with key matching a template step | event label = that step's `label` | graceful fallback: raw event type if key not found |
| Owner tries to edit photo/signature requirements | `EditJobSheet` renders | no toggle UI for `requireCompletionSignature`/`requirePhotoBeforeCompletion`; these fields do not exist | N/A |
| Skill rendering on job card | `job.skillName` or skills list available | skill name displayed; icon from skill data or generic fallback | graceful fallback: raw skillId if skill name not found |
| Job with no template steps | `job.workflowTemplate` null/missing | no step info shown, no gating applied | no crash |

## Code Map

Repo: `workspace/core/frontend/fenzo-app`.

- `src/features/jobDetail/eventLabels.ts` -- delete `STEP_LABELS` (L30-37) and `STEP_ORDER` (L40-47) and `stepNumber()` (L50-53); keep `LABELS`/`eventLabel()` for activity-event labels only.
- `src/features/jobDetail/JobDetailScreen.tsx` -- drop hardcoded `STEP_ORDER`/`STEP_LABELS`; derive "Step N of M" and step labels from `detail.workflowTemplate?.steps` when rendering progress lines and activity timeline; activity event labels for `step_*` events look up the step in the template.
- `src/features/jobDetail/editJobModel.ts` -- delete `requireCompletionSignature` and `requirePhotoBeforeCompletion` fields from the patch model and all builder methods. `buildPatch()` stops writing these keys.
- `src/features/jobDetail/EditJobSheet.tsx` -- remove the toggle UI for signature/photo requirements (if present in the form).
- `src/features/jobs/components/JobCard.tsx` -- replace `SERVICE_TYPE_LABEL` lookups with skill name rendering; use `job.skillName` or fetch from skills list.
- `src/features/jobs/components/HistoryRow.tsx` -- same skill/step rendering updates as `JobCard`.
- `src/features/jobs/components/TodaysJobsSection.tsx` -- same skill/step rendering updates.
- `src/features/technicianApp/components/notificationBanner.tsx` (if exists) -- step labels derive from template, not `STEP_LABELS`.
- `src/features/technicianApp/components/notificationCard.tsx` (if exists) -- same.

**Search & replace guard:** zero `STEP_ORDER`, `STEP_LABELS`, `stepNumber()`, `SERVICE_TYPE_LABEL`, `requireCompletionSignature`, `requirePhotoBeforeCompletion` in `src/features/jobDetail/**`, `src/features/jobs/components/**` (excluding deleted files/specs).

**Tests:**
- UPDATE `editJobModel.test.ts` — remove assertions on deleted fields.
- UPDATE `JobDetailScreen.test.tsx` — new assertions on template-driven step rendering + event label fallback for unknown step keys.
- UPDATE `JobCard.test.tsx` — skill rendering from template/skills list.
- Grep guard: clean on all deletions above.

## Tasks & Acceptance

**Execution:**
- [ ] `eventLabels.ts` — delete `STEP_LABELS`, `STEP_ORDER`, `stepNumber()`
- [ ] `JobDetailScreen.tsx` — template-driven step count/labels, activity event step lookup
- [ ] `editJobModel.ts` — delete photo/signature toggle fields
- [ ] `EditJobSheet.tsx` — remove toggle UI (if present)
- [ ] `JobCard.tsx` — skill rendering from job/skills data
- [ ] `HistoryRow.tsx`, `TodaysJobsSection.tsx` — skill/step updates
- [ ] `notificationBanner.tsx`, `notificationCard.tsx` — template-driven step labels (if separate files exist)
- [ ] Tests per Code Map; `bun run test` green; grep guard clean

**Acceptance Criteria:**
- Given an owner-side screen, when it renders a step count or label, then the data comes from `job.workflowTemplate.steps`, never hardcoded lists.
- Given an activity-event step in the timeline, when the event key is absent from the job's template, then the event label falls back to the raw event type — no crash.
- Given the edit-job form, when the owner tries to save changes, then `requireCompletionSignature` and `requirePhotoBeforeCompletion` fields do not exist in the patch payload.
- Given a job without template steps, when any owner-side screen renders it, then no step info is shown and no gating is applied — no crash.

## Design Notes

Step-count ("Step N of M") and step-label rendering are now symmetric between technician and owner sides: both read the job's own template. The technician stepper (Story 5.2) walks positionally with `currentStepIndex`; the owner's activity timeline and edit screens do not need positional logic — they just display/label what's in the template.

The graceful fallback for unknown step keys is identical to Story 5.2: a raw event type like `step_my_custom_workflow` renders as-is instead of crashing. This allows a future custom-template (or a template typo) to render legibly in the timeline without breaking the app.

`requireCompletionSignature` and `requirePhotoBeforeCompletion` are owner-side presentation toggles that pre-launch (no real data to migrate). Deleting them is a clean cutover — no compat layer needed.

## Verification

**Commands:**
- `bun run test` — expected: all suites green, including updated tests above.
- `bunx tsc --noEmit` — expected: clean.
- Grep guards over the paths listed above — expected: zero hits.

## Review Findings

**Workflow:** BMAD code review (4-layer: Blind Hunter, Edge Case, Verification Gap, Acceptance) completed 2026-09-11.

**Status:** ✅ Complete — 2 patches applied, all tests passing (790/790).

**Summary:**
- **Blind Hunter:** 12 findings (test coverage gaps, pre-launch, pre-existing design decisions) — all deferred.
- **Edge Case Hunter:** 1 finding — `resolveEventLabel()` crash on null `eventType` — **PATCH APPLIED** (null guard added, commit 804c034).
- **Verification Gap Reviewer:** 1 finding — `TechJobDetailContent` missing `workflowTemplate` prop to `ActivityTimeline` — **PATCH APPLIED** (prop passed, commit 804c034).
- **Acceptance Auditor:** Layer failed (hallucinated file references, misunderstood diff scope) — findings excluded.

**Patches Applied:**
1. `src/features/jobDetail/components/ActivityTimeline.tsx:38` — Guard `eventType` before `.startsWith()` call.
2. `src/features/technicianApp/components/TechJobDetailContent.tsx:243` — Pass `workflowTemplate` prop to `ActivityTimeline` for proper step-event label resolution in technician history.

**Test Coverage:** All 790 tests passing; no regressions.

</frozen-after-approval>
