# Story 5.4 Spec: Deletions, Docs, and FE Test Cutover

**Epic:** 5 — Skill-Driven Experience (Frontend)  
**Status:** ready-for-dev  
**Acceptance Criteria Layer:** Requirements & Test Matrix

---

## Story Goal

Complete the Epic 5 cutover by:
1. **Delete** retired skill-CRUD screens, APIs, and old vocabulary (service_type, tenant_skills, service_categories)
2. **Update** all FE planning docs and re-spec the offline-queue model against template steps
3. **Rewrite/retire** ~250 test assertions across ~35 files that reference the old vocabulary

Finish with `bun run test` green, all dependencies on the legacy vocabulary removed, and FE surfaces reading only from job template steps.

---

## Requirements

### R1: Code Deletions

Delete the following FE code paths entirely (no compat shims):
- **Screens:** `SkillsScreen.tsx`, `AddSkillSheet.tsx`, the More-screen skills row and its route
- **API layer:** `useSkills` hook's create/remove paths (becomes read-only over `GET /skills`); `useSkills.ts` retains only the `getSkills()` call
- **Models:** `ServiceTypePicker.tsx`, `toJobServiceType` translation chain (all parts), `WorkflowStepApi` 6-value union, `JobServiceType` map, `skillService`'s write paths
- **Signup/onboarding:** `AuthFlow` business-type → `serviceCategories` mapping, related constants in `constants.ts`, and `authApi.ts` write paths
- **Owner draft handling:** `editJobModel`'s photo/signature-requirement draft and `buildPatch` logic (behavior now comes from the job's template, not an owner-set toggle)
- **Icon lookups:** All `SERVICE_TYPE_LABEL`/`serviceTypeToIcon` usage in owner-side screens (`JobCard`, `TodaysJobsSection`, `HistoryRow`, `TechJobDetailContent`) — replace with skill label from job/skills data

**Diff Target:** Every file under `src/` containing a reference to `service_type`, `serviceType`, `ServiceType`, `tenant_skills`, `service_categories`, `serviceCategories`, `SERVICE_TYPE_LABEL`, `serviceTypeToIcon`, or the old `WorkflowStepApi` shape must be modified or deleted entirely. Zero residual references.

### R2: Documentation Updates

#### R2a: Planning Artifacts Re-design
- **File:** `docs/epics/epic-5-skill-driven-experience-frontend.md` (or its equivalent in the project docs tree)
  - Remove or strike out all references to the deprecated service-type/service-category vocabulary
  - Update interaction patterns and data-flow diagrams to show skills + template steps as the single source of truth
  - Update the technician workflow narrative to reflect data-driven step rendering
  
- **File:** `docs/api-contracts.md` (if it exists)
  - Ensure the skills and job-detail response shapes reflect the new contract (job detail now includes skillId/skillName and full template steps)
  - Document that `service_type`/`service_categories` fields are removed from all job responses
  - Add a migration note explaining the cutover from hardcoded lists to data-driven templates

#### R2b: Offline-Queue Spec Re-spec
- **File:** `artifacts/implementation-artifacts/spec-4-2-dynamic-technician-workflow-from-template-steps.md` (or similar)
  - Re-read the Story 4-2 offline-queue spec (Epic 4's groundwork)
  - Update the idempotency model and error-reconciliation examples to reflect the new template-step data shape
  - Ensure the spec documents that workflow advance, photo-confirm auto-advance, and step-gating all now derive from step attributes (not hardcoded logic)
  - Example: the `INVALID_WORKFLOW_STEP` 422 should show the new step-object shape in the error response, not the old 6-step enum

### R3: Test Cutover

All ~250 assertions across ~35 files that reference old vocabulary must be:
- **Rewritten** to use new data shapes (job template steps, skill IDs) where the test is still valid
- **Deleted** entirely if the test exercises removed code (e.g., "ServiceTypePicker renders 6 tiles" → gone)
- **Migrated** to new test locations if the behavior moved (e.g., step-label logic moves from a hardcoded `STEP_LABELS` map to the step object itself)

**Key test locations to audit:**
- `src/screens/**/*.test.tsx` — screens using old step/service-type rendering
- `src/services/**/*.test.ts` — service layer tests with old models
- `src/utils/**/*.test.ts` — utils tests referencing old translations/maps
- `src/hooks/**/*.test.ts` — hook tests with old data shapes
- `src/components/**/*.test.tsx` — component tests referencing old props or state

**Regression gates:**
- `bun run test` must run fully and show 0 failures
- Test file count may decrease (deleted test files for deleted code paths)
- Coverage reports should not regress for active code paths (new data-driven logic may have different coverage signature, but overall coverage must stay ≥X%, where X is the current baseline)

### R4: Cross-repo Coordination

The backend (Epic 4) already shipped the new shapes. This story is FE-only cutover and cleanup.
- **Do NOT** make any changes to `fenzit-be` in this story
- **Do NOT** wait for backend changes — the new API contract is live and stable

---

## Acceptance Criteria (AC)

| AC# | Criterion | Validation |
|-----|-----------|-----------|
| AC1 | All old skill-CRUD screens and write paths are deleted; zero residual `useSkills` create/remove calls exist | `grep -r "addSkill\|removeSkill\|createSkill" src/` returns 0 hits; `SkillsScreen.tsx` and `AddSkillSheet.tsx` do not exist |
| AC2 | All old step/service-type vocabulary references removed from FE surfaces | `grep -r "SERVICE_TYPE_LABEL\|serviceType\|service_type\|serviceCategories" src/screens/ src/components/` returns only comments/dead code; owner job-detail and cards render skill name from job object, not hardcoded maps |
| AC3 | Draft photo/signature toggles removed from owner job-creation/edit flow | `editJobModel` no longer has draft photo/signature fields; owner create/edit flows read step requirements from template, not draft state |
| AC4 | Technician stepper renders step labels/gating from template step objects, not hardcoded lists | Stepper component receives `templateSteps` prop and maps over it; no `HARDCODED_STEP_LABELS` or similar remain |
| AC5 | Notifications, history, and job cards render step labels via graceful fallback (unknown step keys don't crash) | Render step.label; unknown keys show a fallback text; no errors in console when a step key is not in a hardcoded map |
| AC6 | All test files rewritten/deleted; `bun run test` passes with 0 failures | Test output shows all suites passing; test count may be lower due to deleted test files |
| AC7 | FE planning docs updated; offline-queue spec re-read and amended if needed | Docs reflect skills + template steps as the source of truth; offline-queue spec shows template-step shapes in examples |
| AC8 | No dual old/new fields in any data model; all API response objects match the new contract | Job detail, list, sync, customer-history, and notification responses contain skillId/skillName and template steps; no `service_type`/`service_categories` fields |

---

## Implementation Steps

### Phase 1: Audit & Plan (Prep)
1. Grep for all old vocabulary (`service_type`, `serviceType`, etc.) to identify all affected files
2. List files to delete (SkillsScreen, AddSkillSheet, ServiceTypePicker, etc.)
3. List files to modify (screens that reference service types, models with old fields)
4. Triage test files: identify which tests can be rewritten vs. deleted

### Phase 2: Delete (Core)
1. Delete skill-CRUD screens and routes
2. Delete service-type-related models and translation chains
3. Delete write paths from `useSkills` and `skillService`
4. Remove photo/signature draft logic from `editJobModel`
5. Remove signup business-type → serviceCategories mapping

### Phase 3: Rewrite Surfaces (Core)
1. Update owner screens (JobCard, TodaysJobsSection, HistoryRow, TechJobDetailContent) to render skill label from job object, not hardcoded maps
2. Update technician stepper to render from template steps (already data-driven from stories 5-1/5-2, just double-check no hardcoded fallback remains)
3. Update notification/history renderers to use graceful fallback for unknown step keys

### Phase 4: Test Cutover (Core)
1. Delete test files for deleted screens/components
2. Rewrite test assertions to use new shapes (template steps, skill objects)
3. Add regression tests for graceful fallback (unknown step key doesn't crash)
4. Run `bun run test` and fix failures until green

### Phase 5: Docs & Sync (Cleanup)
1. Update epic-5-context.md and planning docs to reflect finished cutover
2. Re-read and amend spec-4-2 (offline-queue spec) if needed
3. Update sprint-status.yaml: mark 5-4 as done, epic-5 as done
4. Commit with all changes

---

## Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| Missed references to old vocabulary in a deep/rarely-used code path | Phase 1 audit must be exhaustive (grep + manual search); Phase 4 test run will catch stray references via failed assertions |
| Test files accidentally left with old data shapes | Each rewritten test must be code-reviewed; spot-check a sample after rewrite |
| Graceful fallback for unknown step keys only partially implemented | Add a regression test that explicitly renders a made-up step key and asserts the fallback text appears |
| Docs drift from code during rewrite | Update docs in the same commit as code changes; link planning docs to this spec so reviewers can verify alignment |

---

## Notes

- Pre-launch product: no migration path, no compat shims. A clean, hard cutover is correct.
- Keep the modular structure: even if cleanup consolidates code, maintain the ~300-line-per-file ceiling.
- Graceful fallback for unknown step keys is critical: the app already ships workflows with custom step keys, and a typo or future extension must not crash the app.
- This story lands last in Epic 5 — stories 5-1, 5-2, 5-3 already migrate code away from old vocabulary, so deletions here should be straightforward (no live callers of the deleted code).

---

## Rollout Criteria

- **Done:** All AC met, `bun run test` green, code review passed, sprint status updated
- **Deployed:** Story 5-4 merged to main in fenzo-app, pushed to the fenzo-app remote
