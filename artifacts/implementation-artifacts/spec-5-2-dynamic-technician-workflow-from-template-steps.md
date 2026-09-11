---
title: 'Story 5.2: Dynamic technician workflow from template steps'
type: 'feature'
created: '2026-09-11'
status: 'draft'
review_loop_iteration: 0
context:
  - 'artifacts/planning-artifacts/epics-skill-workflow-redesign.md'
  - 'artifacts/implementation-artifacts/epic-5-context.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** The technician's stepper (`stepperModel`/`WorkflowStepper`), action bar (`workflowActionBarModel`), advance hook (`useWorkflowAdvance`), and signature-save hook (`useSignatureSave`) all still run on the OLD fixed 6-step chain (`STEP_ORDER`, literal `'photos_uploaded'`/`'signature_captured'` checks, the dead global `requireCompletionPhoto`/`requireCompletionSignature` flags — BE dropped both columns in Epic 4, confirmed zero backend references, so the "Customer signature" card never renders today). Every job now carries its OWN per-skill template (`ApiJob.workflowTemplate.steps[]` + `currentStepIndex`, typed by Story 5.1, unread by any UI yet) — any skill whose template differs from the old 6 steps renders and behaves wrong.

**Approach:** Rebuild the technician stack to read only `workflowTemplate.steps` + `currentStepIndex`: `buildStepper` walks the template positionally (no skip logic — a stamped template has no optional steps); action-bar label/photo-hint come from the step's own `label`/`advancesOn`; the signature reroute and both 422-reconcile paths key off the target step's `requiresSignature` / membership in the job's own template instead of literal strings and `STEP_ORDER`.

## Boundaries & Constraints

**Always:**
- `stepperModel`, `WorkflowStepper`, `workflowActionBarModel`, `useWorkflowAdvance`, `useSignatureSave` read ONLY `job.workflowTemplate.steps`/`currentStepIndex` for step data/order — never `STEP_ORDER`, `WorkflowStepApi`, or `requireCompletionPhoto`/`requireCompletionSignature`. Step keys become plain `string` throughout (delete `WorkflowStepApi`/`WorkflowStep`); `advanceWorkflow(id, step: string, ...)`.
- `buildStepper` drops the 'skipped' state entirely: `steps[0..currentStepIndex]` = 'done', `steps[currentStepIndex+1]` = 'next' (unless terminal), rest = 'locked'. `currentStepIndex: null` → nothing done, `steps[0]` is 'next' (covers both a fresh job and BE's soft corrupt-read null — same treatment, no special-casing).
- A step is non-tappable/auto-advance-only when `advancesOn !== null`; the action bar shows `photoHint` for `advancesOn === 'photo_confirm'`, else a button labelled by the step's own `label`.
- The signature reroute (`onCaptureSignature`) fires when the target step's `requiresSignature === true` (not a literal key match); the Signature screen navigation and `useSignatureSave`'s POST both carry that step's actual `key` through (route param, `useSignatureSave` param) — no hardcoded `'signature_captured'` anywhere.
- Both 422-reconcile paths (`useWorkflowAdvance`, `useSignatureSave`) check the server's `currentStep` against the JOB'S OWN `workflowTemplate.steps` (not `STEP_ORDER`); not found → discard the patch, refetch silently (`useWorkflowAdvance`) / re-throw as a real error (`useSignatureSave`, unchanged semantics).
- `TechJobDetailContent`'s "Customer signature" card gate becomes `detail.workflowTemplate?.steps.some(s => s.requiresSignature) && !isTerminal` (fixes the dead-flag bug as part of this cutover — it is squarely "photo/signature behaviour from template data").
- `job.workflowTemplate` missing/null renders an empty stepper and no action button — never a crash.
- Tests added for the three files with none today (`stepperModel`, `useWorkflowAdvance`, `useSignatureSave` — covered only indirectly via `SignatureScreen.test.tsx`) plus updates to the others; `bun run test` green before commit.

**Ask First:** none identified — investigation confirmed `attachmentUploadModel`/`useAttachmentUpload`/photo cap are template-independent (out of scope) and `classifyAdvanceError` needs no change.

**Never:**
- No reintroduced hardcoded step-key list/enum as the chain-order or label source.
- No changes to `attachmentUploadModel.ts`, `useAttachmentUpload.ts`, `photoPicker.ts`, `PhotoSection.tsx`, the 5-photo cap, or `classifyAdvanceError`.
- No changes to `eventLabels.ts` (owner-side `JobDetailScreen` shares it — Story 5.3) or `EditJobSheet`/`editJobModel`'s `requireCompletion*` toggles (explicitly Story 5.3's AC).
- No backend changes; no Epic-4 offline-queue module (confirmed not to exist yet — `useWorkflowAdvance`'s `'offline'` branch stays a bare comment, only the idempotency-key mechanics, already step-key-agnostic, carry over unchanged).

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Fresh job | `currentStepIndex: null` | `steps[0]` = 'next', rest 'locked', none 'done' | N/A |
| Mid-chain | `currentStepIndex: i` | `steps[0..i]` 'done', `steps[i+1]` 'next', rest 'locked' | N/A |
| Target step `advancesOn: 'photo_confirm'` | action bar renders | `photoHint` pill, non-tappable stepper row | N/A |
| Target step `requiresSignature: true` | tap 'next' | `useWorkflowAdvance` reroutes to `onCaptureSignature(stepKey)`, no POST | N/A |
| Advance 422, server `currentStep` in job's own template | reconcile | local state patched to that step, no error UI | N/A |
| Advance 422, server `currentStep` NOT in job's own template | reconcile | patch discarded, silent refetch | no crash |
| Signature save 422, target step index ≤ server's `currentStep` index | reconcile | treated as already recorded, pop | N/A |
| `job.workflowTemplate` null/missing | any render | empty stepper, no action bar | no crash |

</frozen-after-approval>

## Code Map

Repo: `workspace/core/frontend/fenzo-app`.

- `src/services/resources/jobs.ts` -- delete `WorkflowStepApi` (L41-47); `ApiJob.currentStep` (L183) and `advanceWorkflow`'s `step` param (L391) widen to `string`.
- `src/features/technicianApp/stepperModel.ts` -- rewrite: delete `STEP_ORDER`/`WorkflowStep`/`isEffectiveNext`; `StepperJob` = `Pick<JobDetail, 'workflowTemplate'|'currentStepIndex'|'status'>`; `StepState` drops `'skipped'`; `StepView` gains `label`/`advancesOn` (from the template step, so consumers stop needing separate lookups); `buildStepper` walks `workflowTemplate?.steps ?? []` positionally against `currentStepIndex`.
- `src/features/technicianApp/components/WorkflowStepper.tsx` -- drop `STEP_LABELS`/`eventLabels` import; label = `view.label`; tappability (L72) `view.step !== 'photos_uploaded'` → `view.advancesOn === null`; drop `'skipped'` glyph/caption branches (Glyph L120-122, RightCaption L134-136).
- `src/features/technicianApp/workflowActionBarModel.ts` -- delete `ADVANCE_LABELS` (L32-38); `actionBarAction` (L56-66): `next.step === 'photos_uploaded'` → `next.advancesOn === 'photo_confirm'`; button label = `next.label`. `classifyAdvanceError`/`AdvanceErrorPlan` untouched except `step: WorkflowStep` → `step: string`.
- `src/features/technicianApp/useWorkflowAdvance.ts` -- drop `STEP_ORDER` import; `advance(step: string)`: reroute condition (L81) `step === 'signature_captured'` → look up `detail.workflowTemplate?.steps.find(s => s.key === step)?.requiresSignature`, call `onCaptureSignature(step)`; reconcile membership check (L110) `STEP_ORDER.includes` → `detailRef.current?.workflowTemplate?.steps.some(s => s.key === currentStep)`; `onCaptureSignature: (stepKey: string) => void` (param type change, L52).
- `src/features/technicianApp/useSignatureSave.ts` -- drop `STEP_ORDER`/`WorkflowStep` import; accept `stepKey: string` in `Props`; `advanceWorkflow(jobId, stepKey, ...)` (L85-89) replaces the literal; reconcile (L98-102) compares indices within `detail.workflowTemplate.steps` (needs `detail`/template passed in, not just `jobId`) instead of `STEP_ORDER.indexOf`.
- `src/features/technicianApp/SignatureScreen.tsx` -- read `stepKey` from route params; pass to `useSignatureSave`.
- `src/navigation/types.ts` -- `Signature: { jobId: string }` (L77) → `{ jobId: string; stepKey: string }`.
- `src/features/technicianApp/TechJobDetailScreen.tsx` -- `onCaptureSignature`/`onRecaptureSignature` navigation (L227-229, L313-315) pass `stepKey` through.
- `src/features/technicianApp/components/TechJobDetailContent.tsx` -- signature-card gate (L197) `detail.requireCompletionSignature && !isTerminal` → `detail.workflowTemplate?.steps.some(s => s.requiresSignature) && !isTerminal`; `Props.onAdvance`/`pendingStep` type `WorkflowStep` → `string`.

**Untouched:** `attachmentUploadModel.ts`, `useAttachmentUpload.ts`, `photoPicker.ts`, `PhotoSection.tsx`, `eventLabels.ts`, `EditJobSheet.tsx`/`editJobModel.ts`, all owner-side screens.

**Tests:**
- NEW `stepperModel.test.ts`, `useWorkflowAdvance.test.ts` (no coverage today).
- UPDATE `SignatureScreen.test.tsx` (only existing `useSignatureSave` coverage) for the `stepKey`-driven POST/reconcile.
- UPDATE `workflowActionBarModel.test.ts`, `WorkflowStepper.test.tsx`, `TechJobDetailContent.test.tsx` for template-driven data + the fixed signature-card gate.
- Grep guard: zero `STEP_ORDER`/`WorkflowStepApi`/`ADVANCE_LABELS`/literal `'photos_uploaded'`/`'signature_captured'` in `src/features/technicianApp/**`.

## Tasks & Acceptance

**Execution:**
- [ ] `jobs.ts` -- widen `currentStep`/`advanceWorkflow` to `string`, delete `WorkflowStepApi`
- [ ] `stepperModel.ts` -- template-driven rewrite, drop `STEP_ORDER`/`isEffectiveNext`/'skipped'
- [ ] `WorkflowStepper.tsx` -- label/tappability from `StepView`, drop 'skipped' rendering
- [ ] `workflowActionBarModel.ts` -- drop `ADVANCE_LABELS`, derive label/photoHint from step data
- [ ] `useWorkflowAdvance.ts` -- signature reroute + reconcile keyed off the job's own template
- [ ] `useSignatureSave.ts` + `SignatureScreen.tsx` + navigation types + `TechJobDetailScreen.tsx` -- thread `stepKey` end to end
- [ ] `TechJobDetailContent.tsx` -- fix the dead signature-flag gate; type updates
- [ ] Tests per Code Map; `bun run test` green; grep guard clean

**Acceptance Criteria:**
- Given a job's template steps, when the technician renders the stepper, then step count/labels/order and photo/signature gating all come from `workflowTemplate.steps` + `currentStepIndex` — never a hardcoded list.
- Given an advance or a 422, when the server responds, then `useWorkflowAdvance` reroutes/reconciles by checking the target/server step against the job's own template, not a literal key or `STEP_ORDER`.
- Given photo confirm, when the server auto-advances, then the existing confirm-replay entry point (`attachmentUploadModel`) keeps working unchanged.
- Given a `currentStep` absent from the job's own template, when any model renders or reconciles it, then the existing graceful fallback (discard/refetch) applies — no crash.

## Design Notes

BE's `requiresPhoto`/`requiresSignature` are FE action gates, not chain filters — every job walks every step in its stamped template regardless of these flags (confirmed: `fenzit-be/src/jobs/workflow-template.model.ts` — `nextStepKey` is purely positional). This retires the old "skip an unrequired step" logic wholesale; a stamped template has no optional steps, so there is no replacement conditional to write, only deletion.

`currentStepIndex: null` deliberately conflates "fresh job" and "corrupt `current_step`" (BE's read path is intentionally softer than its write path, per `currentStepIndexForRead`'s doc comment). The FE must not try to distinguish them — both render identically as "nothing done, next = steps[0]," which is also what makes the "no crash on unknown state" requirement trivial to satisfy.

## Verification

**Commands:**
- `bun run test` (jest script — never bare `bun test`) -- expected: all suites green, including new/updated tests listed above.
- `bunx tsc --noEmit` -- expected: clean except the pre-existing baseline `src/config/index.ts` TS2591 (verified unrelated in Story 5.1).
- Grep guard (`STEP_ORDER`, `WorkflowStepApi`, `ADVANCE_LABELS`, `'photos_uploaded'`, `'signature_captured'` as literals) over `src/features/technicianApp/**` -- expected: zero hits.
