# Story 9: Frontend — NewJobScreen location toggle

**Repo:** fenzo-app
**Checkpoints:** `done_checkpoint: true` — this is the last story in the epic; feature-complete once merged.

## Source

- SPEC.md, CAP-1 (frontend half) — owner-facing toggle for whether technicians must share GPS location on this job's steps.
- SPEC.md, Success signal — "An owner creates a job with the location toggle left at its default (ON) ... Turning the toggle OFF at creation means no step on that job ever prompts for location."
- stories.yaml, id "9".

## Acceptance Criteria

1. A single switch, labeled **"Require technician location when completing steps"**, is added to `NewJobScreen.tsx`, defaulting to **ON**.
2. The switch's value is wired to `captureLocationOnSteps` on the create-job payload (the field Story 8 adds to `CreateJobRequest`).
3. No location-picker UI is added — none exists today for jobs, and none is needed here: CAP-1 is a boolean toggle, not a coordinate picker.
4. Turning the toggle OFF at creation and submitting persists `capture_location_on_steps = false` on the created job; end-to-end, no step on that job ever prompts a technician for location (verifies against Story 4's backend gate, which reads this same flag).
5. Leaving the toggle at its default and submitting persists `capture_location_on_steps = true`.

## Implementation Notes

- File: `src/features/newJob/NewJobScreen.tsx` (626 lines). Confirmed there is no existing location/address picker on this screen today — a comment in the file flags a *different*, unrelated gap (no editable `service_location` text field). This story does not touch that; `serviceLocation` stays derived exactly as it is now.
- Add the switch near the other job-creation toggles/options on the screen, reusing whichever switch component and copy/spacing conventions the screen already uses for its existing options — do not introduce a new switch primitive.
- No new screen, modal, or navigation step — this is one control on the existing create-job form.

## Dependencies

- **Story 8** (wire location into `advanceWorkflow` + job types) should land first, since it's what adds `captureLocationOnSteps` to `CreateJobRequest`/`ApiJob`.
- Implicitly, the full backend slice (**Stories 1–4**) must already be merged and deployed — per the fenzo-meta cross-repo ordering rule, this frontend story assumes the backend column/DTO/validation already exist in the environment it's tested against.

## Testing Notes

- Component test: switch renders default ON.
- Component test: toggling OFF and submitting sends `captureLocationOnSteps: false` in the create-job request body.
- Component test: leaving it ON and submitting sends `captureLocationOnSteps: true`.
- Manual end-to-end pass after merge (this is the epic's feature-complete checkpoint): create a job with the toggle ON, complete a `requires_location` step as a technician, and confirm — via Supabase — that the resulting `activity_logs` row's `metadata` carries the captured latitude/longitude/accuracy.
