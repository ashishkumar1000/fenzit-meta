---
title: 'Story 5.2: Dynamic technician workflow from template steps'
type: 'feature'
created: '2026-09-11'
status: 'done'
baseline_commit: '9d488d4b1258ff15e3d1e66a069a5a3e380b5e73'
review_loop_iteration: 1
context:
  - 'artifacts/planning-artifacts/epics-skill-workflow-redesign.md'
  - 'artifacts/implementation-artifacts/epic-5-context.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** The technician's stepper (`stepperModel`/`WorkflowStepper`) and action bar (`workflowActionBarModel`/`useWorkflowAdvance`) all still run on the OLD fixed 6-step chain (`STEP_ORDER`, literal `'photos_uploaded'` checks, the dead global `requireCompletionSignature` flag — BE dropped the column in Epic 4, confirmed zero backend references, so the "Customer signature" card never renders today). Every job now carries its OWN per-skill template (`ApiJob.workflowTemplate.steps[]` + `currentStepIndex`, typed by Story 5.1, unread by any UI yet) — any skill whose template differs from the old 6 steps renders and behaves wrong.

**Approach:** Rebuild `stepperModel`/`WorkflowStepper`/`workflowActionBarModel`/`useWorkflowAdvance` to read only `workflowTemplate.steps` + `currentStepIndex`: `buildStepper` walks the template positionally (no skip logic — a stamped template has no optional steps); action-bar label/photo-hint come from the step's own `label`/`advancesOn`; the advance hook's signature-reroute *detection* and its 422-reconcile both key off the job's own template instead of literal strings and `STEP_ORDER`. (The signature-CAPTURE screen itself — `useSignatureSave`, `SignatureScreen`, the `Signature` route's step-key param — is split into a follow-up story; see Design Notes.)

## Boundaries & Constraints

**Always:**
- `stepperModel`, `WorkflowStepper`, `workflowActionBarModel`, `useWorkflowAdvance` read ONLY `job.workflowTemplate.steps`/`currentStepIndex` for step data/order — never `STEP_ORDER` or `requireCompletionSignature`. Step keys become plain `string` throughout (delete `WorkflowStepApi`/`WorkflowStep`); `advanceWorkflow(id, step: string, ...)`.
- `buildStepper` drops the 'skipped' state entirely: `steps[0..currentStepIndex]` = 'done', `steps[currentStepIndex+1]` = 'next' (unless terminal), rest = 'locked'. `currentStepIndex: null` → nothing done, `steps[0]` is 'next' (covers both a fresh job and BE's soft corrupt-read null — same treatment, no special-casing).
- A step is non-tappable/auto-advance-only when `advancesOn !== null`; the action bar shows `photoHint` for `advancesOn === 'photo_confirm'`, else a button labelled by the step's own `label`.
- `useWorkflowAdvance`'s signature reroute is DETECTED generically: look up the target step in `detail.workflowTemplate?.steps`; if `requiresSignature === true`, call `onCaptureSignature()` (signature UNCHANGED — no step-key argument yet, per the follow-up split) instead of POSTing.
- The 422-reconcile path in `useWorkflowAdvance` checks the server's `currentStep` against the JOB'S OWN `workflowTemplate.steps` (not `STEP_ORDER`); not found → discard the patch, refetch silently (unchanged behavior, generalized source).
- `TechJobDetailContent`'s "Customer signature" card gate becomes `detail.workflowTemplate?.steps.some(s => s.requiresSignature) && !isTerminal` (fixes the dead-flag bug — pure display data, no dependency on the signature-capture flow itself).
- `job.workflowTemplate` missing/null renders an empty stepper and no action button — never a crash.
- Tests added for the two files with none today (`stepperModel`, `useWorkflowAdvance`) plus updates to `workflowActionBarModel.test.ts`/`WorkflowStepper.test.tsx`/`TechJobDetailContent.test.tsx`; `bun run test` green before commit.

**Ask First:** none identified — investigation confirmed `attachmentUploadModel`/`useAttachmentUpload`/photo cap are template-independent (out of scope) and `classifyAdvanceError` needs no change.

**Never:**
- No reintroduced hardcoded step-key list/enum as the chain-order or label source.
- No changes to `useSignatureSave.ts`, `SignatureScreen.tsx`, `navigation/types.ts`'s `Signature` route, or `TechJobDetailScreen.tsx`'s capture/recapture navigation calls — split into a follow-up story (`deferred-work.md`); `onCaptureSignature`'s signature (`() => void`) stays exactly as-is.
- No changes to `attachmentUploadModel.ts`, `useAttachmentUpload.ts`, `photoPicker.ts`, `PhotoSection.tsx`, the 5-photo cap, or `classifyAdvanceError`.
- No changes to `eventLabels.ts` (owner-side `JobDetailScreen` shares it — Story 5.3) or `EditJobSheet`/`editJobModel`'s `requireCompletion*` toggles (explicitly Story 5.3's AC).
- No backend changes; no Epic-4 offline-queue module (confirmed not to exist yet — `useWorkflowAdvance`'s `'offline'` branch stays a bare comment, only the idempotency-key mechanics, already step-key-agnostic, carry over unchanged).

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Fresh job | `currentStepIndex: null` | `steps[0]` = 'next', rest 'locked', none 'done' | N/A |
| Mid-chain | `currentStepIndex: i` | `steps[0..i]` 'done', `steps[i+1]` 'next', rest 'locked' | N/A |
| Target step `advancesOn: 'photo_confirm'` | action bar renders | `photoHint` pill, non-tappable stepper row | N/A |
| Target step `requiresSignature: true` | tap 'next' | `useWorkflowAdvance` reroutes to `onCaptureSignature()`, no POST | N/A |
| Advance 422, server `currentStep` in job's own template | reconcile | local state patched to that step, no error UI | N/A |
| Advance 422, server `currentStep` NOT in job's own template | reconcile | patch discarded, silent refetch | no crash |
| `job.workflowTemplate` null/missing | any render | empty stepper, no action bar | no crash |

</frozen-after-approval>

## Code Map

Repo: `workspace/core/frontend/fenzo-app`.

- `src/services/resources/jobs.ts` -- delete `WorkflowStepApi` (L41-47); `ApiJob.currentStep` (L183) and `advanceWorkflow`'s `step` param (L391) widen to `string`.
- `src/features/technicianApp/stepperModel.ts` -- rewrite: delete `STEP_ORDER`/`WorkflowStep`/`isEffectiveNext`; `StepperJob` = `Pick<JobDetail, 'workflowTemplate'|'currentStepIndex'|'status'>`; `StepState` drops `'skipped'`; `StepView` gains `label`/`advancesOn` (from the template step, so consumers stop needing separate lookups); `buildStepper` walks `workflowTemplate?.steps ?? []` positionally against `currentStepIndex`.
- `src/features/technicianApp/components/WorkflowStepper.tsx` -- drop `STEP_LABELS`/`eventLabels` import; label = `view.label`; tappability (L72) `view.step !== 'photos_uploaded'` → `view.advancesOn === null`; drop `'skipped'` glyph/caption branches (Glyph L120-122, RightCaption L134-136).
- `src/features/technicianApp/workflowActionBarModel.ts` -- delete `ADVANCE_LABELS` (L32-38); `actionBarAction` (L56-66): `next.step === 'photos_uploaded'` → `next.advancesOn === 'photo_confirm'`; button label = `next.label`. `classifyAdvanceError`/`AdvanceErrorPlan` untouched except `step: WorkflowStep` → `step: string`.
- `src/features/technicianApp/useWorkflowAdvance.ts` -- drop `STEP_ORDER` import; `advance(step: string)`: reroute condition (L81) `step === 'signature_captured'` → `detail?.workflowTemplate?.steps.find(s => s.key === step)?.requiresSignature`, still calls `onCaptureSignature()` (no-arg, unchanged); reconcile membership check (L110) `STEP_ORDER.includes` → `detailRef.current?.workflowTemplate?.steps.some(s => s.key === currentStep)`.
- `src/features/technicianApp/components/TechJobDetailContent.tsx` -- signature-card gate (L197) `detail.requireCompletionSignature && !isTerminal` → `detail.workflowTemplate?.steps.some(s => s.requiresSignature) && !isTerminal`; `Props.onAdvance`/`pendingStep` type `WorkflowStep` → `string`.

**Untouched:** `useSignatureSave.ts`, `SignatureScreen.tsx`, `navigation/types.ts`, `TechJobDetailScreen.tsx`'s navigation calls (all follow-up, `deferred-work.md`), `attachmentUploadModel.ts`, `useAttachmentUpload.ts`, `photoPicker.ts`, `PhotoSection.tsx`, `eventLabels.ts`, `EditJobSheet.tsx`/`editJobModel.ts`, all owner-side screens.

**Tests:**
- NEW `stepperModel.test.ts`, `useWorkflowAdvance.test.ts` (no coverage today).
- UPDATE `workflowActionBarModel.test.ts`, `WorkflowStepper.test.tsx`, `TechJobDetailContent.test.tsx` for template-driven data + the fixed signature-card gate.
- Grep guard: zero `STEP_ORDER`/`WorkflowStepApi`/`ADVANCE_LABELS`/literal `'photos_uploaded'` in `src/features/technicianApp/**` (excluding `useSignatureSave.ts`, out of scope).

## Tasks & Acceptance

**Execution:**
- [ ] `jobs.ts` -- widen `currentStep`/`advanceWorkflow` to `string`, delete `WorkflowStepApi`
- [ ] `stepperModel.ts` -- template-driven rewrite, drop `STEP_ORDER`/`isEffectiveNext`/'skipped'
- [ ] `WorkflowStepper.tsx` -- label/tappability from `StepView`, drop 'skipped' rendering
- [ ] `workflowActionBarModel.ts` -- drop `ADVANCE_LABELS`, derive label/photoHint from step data
- [ ] `useWorkflowAdvance.ts` -- signature-reroute detection + reconcile keyed off the job's own template
- [ ] `TechJobDetailContent.tsx` -- fix the dead signature-flag gate; type updates
- [ ] Tests per Code Map; `bun run test` green; grep guard clean

**Acceptance Criteria:**
- Given a job's template steps, when the technician renders the stepper, then step count/labels/order and photo/signature gating all come from `workflowTemplate.steps` + `currentStepIndex` — never a hardcoded list.
- Given an advance or a 422, when the server responds, then `useWorkflowAdvance` reroutes/reconciles by checking the target/server step against the job's own template, not a literal key or `STEP_ORDER`.
- Given a `currentStep` absent from the job's own template, when any model renders or reconciles it, then the existing graceful fallback (discard/refetch) applies — no crash.

## Design Notes

BE's `requiresPhoto`/`requiresSignature` are FE action gates, not chain filters — every job walks every step in its stamped template regardless of these flags (confirmed: `fenzit-be/src/jobs/workflow-template.model.ts` — `nextStepKey` is purely positional). This retires the old "skip an unrequired step" logic wholesale; a stamped template has no optional steps, so there is no replacement conditional to write, only deletion.

`currentStepIndex: null` deliberately conflates "fresh job" and "corrupt `current_step`" (BE's read path is intentionally softer than its write path, per `currentStepIndexForRead`'s doc comment). The FE must not try to distinguish them — both render identically as "nothing done, next = steps[0]," which is also what makes the "no crash on unknown state" requirement trivial to satisfy.

**Split from the original draft (user decision, 2026-09-11):** the original spec also threaded a real step key through `onCaptureSignature`/`SignatureScreen`/`useSignatureSave` so the Signature screen would POST the job's actual signature-step key instead of the literal `'signature_captured'`. That work is deferred (`deferred-work.md`) to keep this spec inside the token guideline. Accepted interim gap: `useWorkflowAdvance`'s reroute *detection* becomes template-driven in this story, but the destination (`onCaptureSignature`) still takes no step key, so `useSignatureSave` keeps POSTing the literal `'signature_captured'` — correct only while a job's signature step happens to use that exact key (true for the seeded default template; not guaranteed for a future custom template). The follow-up closes this by threading `stepKey` through the whole chain.

## Verification

**Commands:**
- `bun run test` (jest script — never bare `bun test`) -- expected: all suites green, including new/updated tests listed above.
- `bunx tsc --noEmit` -- expected: clean except the pre-existing baseline `src/config/index.ts` TS2591 (verified unrelated in Story 5.1).
- Grep guard (`STEP_ORDER`, `WorkflowStepApi`, `ADVANCE_LABELS`, `'photos_uploaded'` as a literal) over `src/features/technicianApp/**` except `useSignatureSave.ts` -- expected: zero hits.

## Review Findings

### Decision Needed

- [x] [Review][Decision] **Spec constraint violation: deferred work implemented** — All 4 files marked "Never" in Story 5.2 spec are modified for signature-step key threading (navigation/types.ts, SignatureScreen.tsx, TechJobDetailScreen.tsx, useSignatureSave.ts). The spec explicitly deferred this work to a follow-up story. User explicitly requested this deferred work be done before Story 5.3.

### Patch

- [x] [Review][Patch] **AC 3 violation: throws instead of graceful fallback** [useSignatureSave.ts:94] — AC 3 requires graceful fallback when data absent, but code throws "Signature step key is missing" error. Should refetch or discard instead.
- [x] [Review][Patch] **Missing guard on params before destructuring** [SignatureScreen.tsx:42-46] — useRoute().params could be undefined; should validate before property access.
- [x] [Review][Patch] **Reconcile logic skipped when steps undefined** [useSignatureSave.ts:109-114] — No guard before steps.findIndex(); if steps is undefined, recorded stays false and error always throws instead of graceful fallback.
- [x] [Review][Patch] **currentStep not found in template masked as unrecorded** [useSignatureSave.ts:110] — findIndex returns -1 silently; step vocabulary mismatch not exposed as config error.
- [x] [Review][Patch] **stepKey not found in template masked as API failure** [useSignatureSave.ts:111] — findIndex returns -1; component receives wrong stepKey and error propagates as unrelated failure.
- [x] [Review][Patch] **Steps array out of order breaks index comparison** [useSignatureSave.ts:112] — If steps reordered at runtime, comparison yields incorrect reconciliation; false error thrown despite server success.
- [x] [Review][Patch] **No guard on detail?.workflowTemplate?.steps before find()** [TechJobDetailScreen.tsx:317] — Silent failure if template missing; no fallback navigation or error message.
- [x] [Review][Patch] **stepKey parameter never validated before navigation** [TechJobDetailScreen.tsx:227-229] — Undefined or null stepKey silently skips navigation; recapture silently does nothing.
- [x] [Review][Patch] **Silent failure when signature step not found in recapture** [TechJobDetailScreen.tsx:315-321] — Code does nothing instead of falling back to default navigation or showing error.
- [x] [Review][Patch] **Steps array recreated per render (stale closure risk)** [TechJobDetailScreen.tsx:229, useSignatureSave.ts:130] — detail.workflowTemplate.steps is new array reference each render; dependency array in useCallback causes unnecessary re-runs and potential stale closures.
- [x] [Review][Patch] **No validation that steps array has key property** [useSignatureSave.ts:110-111] — Code assumes shape; defensive check missing; crashes if object lacks key field.
- [x] [Review][Patch] **Assumes only one signature step per workflow** [TechJobDetailScreen.tsx:317] — Code finds first requiresSignature step; doesn't account for multiple or named signature steps.
- [x] [Review][Patch] **Test mock hardcodes stepKey without verifying template match** [SignatureScreen.test.tsx:34] — Test couples to naming convention; passes even if wrong key used.
- [x] [Review][Patch] **Test checks .toBeDefined() without validating content** [tech-job-detail-screen.test.tsx:509-514] — Doesn't verify stepKey matches step in steps array or that array is non-empty.
