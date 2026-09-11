---
title: 'Story 5.1: Job creation with skill picker and exact technician matching'
type: 'feature'
created: '2026-09-11'
status: 'done'
baseline_commit: 'a1a3663fffb51509084fc5c3d4c53c9efab27c7d' # fenzo-app
review_loop_iteration: 0
followup_review_recommended: true
deferred:
  - summary: >-
      JobCard and the other serviceType display consumers crash on live
      backend data — `serviceTypeToIcon(job.serviceType)` throws
      `TypeError: t.startsWith` because BE stopped returning `serviceType`
      in 4.3 while the FE still renders it unguarded.
    evidence: |-
      format.ts `serviceTypeToIcon(t)` does `t.startsWith('ac_')` with no
      undefined guard, and JobCard.tsx:70 calls it on every card row. With
      the deployed BE (4.5), `ApiJob.serviceType` is absent, so any job
      render path that reaches JobCard's icon line throws. Pre-existing
      live break from the accepted Epic-4 merge window; surfaced by this
      story's review, not caused by it (consumers untouched here by design).
    location: >-
      src/features/jobs/format.ts:28; src/features/jobs/components/JobCard.tsx:70
    severity: high
  - summary: >-
      `ApiJob.serviceType` is typed as a required field although the backend
      has omitted it since 4.3, so every test fixture fabricates a value the
      wire never carries.
    evidence: |-
      The FE type misstates the response; making it optional (or removing it
      with its readers) is Story 5.3's display sweep — the spec deliberately
      keeps it so 5.3's consumers keep compiling.
    location: >-
      src/services/resources/jobs.ts (ApiJob.serviceType)
    severity: low
  - summary: >-
      The Skills screen still offers owner-facing CRUD (AddSkillSheet, row
      delete buttons, "add your first skill" copy) against endpoints that
      404 since 4.2, including stale delete-confirmation copy about a
      technician-skill cascade that no longer exists.
    evidence: |-
      POST/DELETE /skills are dead routes; every add/delete attempt from the
      screen fails. Story 5.4 deletes the write paths and the screen; this
      story's spec explicitly scoped SkillsScreen out (Ask First).
    location: >-
      src/features/skills/SkillsScreen.tsx:194
    severity: medium
  - summary: >-
      useSkills write paths keep stale docs and a competing order contract —
      `addSkill`'s sorted insert re-sorts the seed-ordered catalog, and the
      addSkill/removeSkill docstrings plus the NewSkillInput comment still
      describe the dropped tenant-CRUD endpoints (409 cascade, 404-on-delete
      semantics).
    evidence: |-
      Write paths are Story 5.4 deletions and were deliberately untouched
      (Ask First boundary); the tension only matters until they die.
    location: >-
      src/features/skills/useSkills.ts (addSkill/removeSkill)
    severity: medium
  - summary: >-
      AuthFlow's post-setupCompany token replacement (marked CRITICAL in the
      source) has no test assertion — the new AuthFlow.test.tsx covers only
      the payload shape and the business-type validation.
    evidence: |-
      Reviewer verified no test asserts `setAuthToken` is called with the
      fresh token after company setup. Pre-existing test debt; the behavior
      itself is unchanged by this story.
    location: >-
      src/features/auth/AuthFlow.tsx
    severity: low
context:
  - 'artifacts/planning-artifacts/epics-skill-workflow-redesign.md'
  - 'workspace/core/frontend/fenzo-app/project-context.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** The new-job flow still runs on the pre-Epic-4 vocabulary. The "what kind of job" tiles are built from `tenant.serviceCategories` (a column the backend DROPPED in 4.2 — the FE type still declares it, so the field is `undefined` at runtime); submission translates the category through the lossy `toJobServiceType` chain into a `serviceType` enum the backend no longer accepts (create body carries `skillId` since 4.3); technician matching fuzzy-compares free-text skill names against category codes; and the create payload still sends `requireCompletion*` flags the backend strips since 4.4. Separately, Epic 4 changed `GET /skills` to return `{skills: [{id, name}]}` in seed order while the FE's `ApiService.list()` unwraps the body as a plain array — the FE skills read path is silently broken against the deployed backend today (the accepted Epic-4 merge window; this story closes it).

**Approach:** The new-job screen switches to a skill picker fed by the global catalog (`GET /skills` via the existing `useSkills` store), the draft carries `skillId`, the technician picker filters the roster by exact `skillIds` id membership (no string normalization) for new-job creation only, and the create payload sends `skillId` — deleting `ServiceTypePicker`, the `toJobServiceType`/`JOB_SERVICE_TYPE_BY_CATEGORY` translation chain, and the signup `businessTypes → serviceCategories` mapping. The FE stops sending `serviceCategories` on company setup and `requireCompletion*` on create, closing the api-contracts rollout note.

## Boundaries & Constraints

**Always:**
- Skill selection is REQUIRED before the technician section and before submission (same gating UX as the category today: no roster shown until a skill is chosen; submit blocked without one).
- Technician matching is exact id membership for new-job creation: `technician.skillIds.includes(selectedSkillId)` — never name/string comparison.
- Edit-job technician reassignment stays UNFILTERED (explicit decision, 2026-09-10): `EditJobSheet` keeps only its existing `status !== 'invited'` filter; no skill filter added there in this story.
- Zero-match roster keeps the advisory full-roster fallback with the existing `noSkillMatch` notice (user decision, 2026-09-11) — never an empty list in the new-job flow.
- `GET /skills` is consumed in seed order as the backend serves it (`sort_order` asc) — the store's client-side alphabetical sort is removed from the read path.
- Unknown/degraded states render gracefully: skills fetch failure shows the existing error/retry pattern; a technician with an empty `skillIds` simply never matches (no crash, no special case).
- FE tests updated in the same change; `bun run test` (jest script — never bare `bun test`) green before any commit.
- Docs touched by this story update in the same change (FE `_bmad-output/planning-artifacts/api-contracts.md` gets a redesign note only — full doc sweep is Story 5.4's).

**Ask First:**
- Any change to the `useSkills` store's write paths (`addSkill`/`removeSkill`) or the `SkillsScreen`/`AddSkillSheet` CRUD screens — they are Story 5.4 deletions; this story only fixes the READ path (`list` unwrapping + sort removal).
- Any change to `EditJobSheet`/`editJobModel` beyond leaving them untouched (photo/signature toggle removal is Story 5.3).
- Any change to `AddTechnicianSheet`'s skill selection or copy beyond what the global catalog makes stale (its cutover check is Story 5.4; it must keep working unchanged here).
- Replacing the `ApiJob`/`JobHistoryItem` dead `serviceType` field or any consumer of `serviceTypeLabel`/`serviceTypeToIcon` (cards, detail, history — Story 5.3).
- Any new dependency, any new store/hook beyond what the Code Map names, any change to the offline-queue/idempotency seam.

**Never:**
- No string normalization in skill matching — the `normalizeSkill`/`technicianHasSkill` name-matching helpers and the whole `serviceCategories.ts` file go away; nothing reintroduces a fuzzy match.
- No backend calls added beyond `GET /skills` (already exists) — no new endpoints, no mock servers.
- No changes to `fenzit-be` (backend is done and deployed first per NFR5; any discovered backend gap goes back to the meta sprint, not this story).
- No compat shims: no dual `serviceType`+`skillId` on the create payload, no fallback to category matching.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| New-job open, owner | `NewJobScreen` mount | Skill tiles render from `GET /skills` (seed order); loading/error branches mirror today's category-picker branches | fetch error → inline error + retry, not a blank grid |
| No skill chosen | submit attempt | Submission blocked; technician section not rendered ("choose a skill first" gate) | same validation UX as today's category gate |
| Skill chosen, roster has matches | `skillIds` contains the id | Picker shows only matching technicians | N/A |
| Skill chosen, no technician matches | roster non-empty, zero `skillIds` hits | Full roster behind the existing `noSkillMatch` notice (advisory fallback KEPT — user decision 2026-09-11); not a crash, not an empty list | notice state, never a crash |
| Skill chosen, empty roster | no technicians at all | existing empty-roster state | N/A |
| Technician selected, skill changed | mismatched selection | technician clears (existing behavior, now id-based) | N/A |
| Submission | `skillId: <uuid>` | `POST /jobs` body carries `skillId`; NO `serviceType`, NO `requireCompletionPhoto/Signature` | 400 unknown skill → surfaced via existing ApiError path |
| `GET /skills` response | `{skills: [{id, name}]}` envelope | store holds `[{id, name}]` in seed order | malformed/missing envelope → treated as fetch error, not a crash |
| Company setup | step-3 submit | `POST /auth/company` body has NO `serviceCategories` field; `BUSINESS_TYPES` selection UI and its ≥1 validation stay (profile data only, nothing downstream reads them) | unchanged validation |
| Logout / 401 reset | `clearSkills` | unchanged registry behavior | N/A |
| Unknown step/screen regression | any other consumer of the store (`AddTechnicianSheet`) | continues to work off the same store | N/A |

</frozen-after-approval>

## Code Map

Repo: `workspace/core/frontend/fenzo-app` (all changes land here; commit in fenzo-app; baseline `a1a3663`).

**Modify:**

- `src/features/newJob/NewJobScreen.tsx` -- tiles feed: replace `profile?.tenant.serviceCategories` + `resolveServiceCategories` (L103–106) with the `useSkills` store (`loadSkills()` on mount; `useSkills()` snapshot); draft field `serviceCategory` → `skillId` (types.ts L29); `matchingTechnicians` memo (L163–167) becomes `allTechnicians.filter(t => t.skillIds.includes(skillId))` — exact id match; the advisory `noSkillMatch` fallback (L174–179: degrade to full roster + notice) is KEPT as-is (user decision 2026-09-11 — see Design Notes), only its match test becomes id-based; `handleServiceCategoryChange` (L189–204) → skill-change handler with the same deselect-on-mismatch semantics (compare `skillIds.includes`); submit (L224–243) sends `skillId` instead of `serviceType: toJobServiceType(...)` (L227) — the create payload never carried `requireCompletion*` (edit-flow only, Story 5.3); `renderServiceTypes` (L298–341) renders the new `SkillPicker`; import of `toJobServiceType` from the jobs resource (L44) removed.
- `src/features/newJob/types.ts` -- `NewJobDraft.serviceCategory` → `skillId: string | null`; delete `ServiceType` interface (L11–17); re-check `index.ts` re-export (L5).
- `src/features/newJob/serviceCategories.ts` -- DELETE the whole file (`DISPLAY`, `resolveServiceCategory[ies]`, `normalizeSkill`, `technicianHasSkill`). AC says the picker replaces the tiles — this file only exists for them. Grep before deleting: no other importers expected (NewJobScreen + its tests only).
- `src/features/newJob/components/SkillPicker.tsx` -- NEW. Tile-grid skill picker fed by `Skill[]`. Deliberately modeled on the deleted `ServiceTypePicker` (same 3-column tile grid, `accessibilityState={{selected}}`, controlled `value`/`onChange`) with two deltas: options are `Skill` (id + name from the catalog) and no per-skill icon — skills carry no icon data, so tiles render the label alone (single neutral `Wrench` glyph kept for visual continuity; no per-code icon map). Keep it presentational like its predecessor.
- `src/services/resources/jobs.ts` -- `CreateJobRequest` (L64–84): replace `serviceType: JobServiceType` (L69) with `skillId: string` (UUID, global catalog — mirrors BE `POST /jobs` body); DROP `requireCompletionPhoto`/`requireCompletionSignature` from the create input (BE gone since 4.4, ValidationPipe strips them — closing the api-contracts rollout note); DELETE `JobServiceType`... **no — keep `JobServiceType` + `JOB_SERVICE_TYPE_BY_CATEGORY` (L392–402) deleted but ONLY what is safe**: delete `toJobServiceType` + `JOB_SERVICE_TYPE_BY_CATEGORY` + their doc block (L375–413) — their only production caller (NewJobScreen L227) and test usage (new-job-screen.test mock) die with this story. KEEP the `JobServiceType` enum + `ApiJob.serviceType` (L134) for Story 5.3 (its consumers — JobCard/HistoryRow/TechJobDetailContent/customer history — still compile against it; BE stopped returning it in 4.3, so the field is already dead data — removing it and its readers is 5.3's display sweep). `ApiJob` gains optional `skill?: {id: string; name: string} | null` + `workflowTemplate`/`currentStepIndex` typed per the Story 4.5 response shape (additive, consumed fully in 5.2/5.3).
- `src/services/resources/skills.ts` -- fix the broken read path: `SkillService extends ApiService` must override `list()` to unwrap the new envelope — `GET /skills` returns `{skills: [{id, name}]}` (seed order, active only; BE `skills.controller.ts` L41–47), but inherited `ApiService.list()` returns `res.data` as `T[]` and would hand the store the envelope OBJECT. Simplest: add a `listCatalog()` method (or override `list()`) doing `this.client.get<{skills: Skill[]}>('/skills').then(r => r.data.skills)`. `Skill` type slims to `{id: string; name: string}` (drop `tenantId`/`createdAt` — BE returns id+name only). Header comment rewritten to the global-catalog read-only contract. POST/DELETE inheritance stays until 5.4 (404 dead routes, unused by this story's code paths).
- `src/features/skills/useSkills.ts` -- read-path fixes ONLY: drop the `byName` sort in `fetchSkills` (L83–85, L102) — seed order is the picker's contract, render as-is; drop the stale "server order is unspecified" comment. `addSkill`/`removeSkill` keep their (now-moot) sorted-insert behavior untouched — write paths die in 5.4. `Skill` import updates to the slimmed type.
- `src/features/auth/constants.ts` -- DELETE `SERVICE_CATEGORY_BY_BUSINESS_TYPE` (L34–54) and its doc comment; remove from the `src/constants/index.ts` barrel re-export. `BUSINESS_TYPES` (L22–32) STAYS (signup UI keeps collecting business types as profile data; only the translation to category codes goes).
- `src/features/auth/AuthFlow.tsx` -- DELETE `serviceCategoriesFor` (L57–62) and the `serviceCategories` field from the `setupCompany` payload (L204–211); the ≥1-business-type validation (L192–199) is unchanged. `BusinessProfile.businessTypes` doc comment in `src/features/auth/types.ts` (L16) loses its "maps 1:1 to serviceCategories" claim.
- `src/services/resources/authApi.ts` -- `SetupCompanyRequest` drops `serviceCategories?: string[]` (L101) and its "seeds the company's initial skill list" comment (L96–100 — false since 4.2); `Tenant` drops `serviceCategories` (L113).
- `src/services/resources/users.ts` -- `ProfileTenant` drops `serviceCategories` (L40) (column dropped in 4.2; NewJobScreen was its only reader and stops reading it here).
- `src/features/newJob/components/ServiceTypePicker.tsx` -- DELETE (replaced by `SkillPicker`).

**Untouched on purpose:** `src/components/TechnicianPicker.tsx` (no skill logic inside; roster filtering is the screen's job — unchanged), `EditJobSheet`/`editJobModel` (5.3), `AddTechnicianSheet` (works off the fixed read path unchanged; copy touched only if it references tenant-created skills — prefer leaving for 5.4), `src/features/jobs/format.ts` + all `serviceTypeLabel`/`serviceTypeToIcon`/`SERVICE_ICON` consumers (5.3), `WorkflowStepApi` union/`skillService` write-path removal + `SkillsScreen` deletion (5.4), navigation routes (no route changes).

**Tests (same change):**

- `__tests__/new-job-screen.test.tsx` -- rewrite: mocks `ServiceTypePicker` → `SkillPicker` + the skills store instead of `toJobServiceType` (mock at L29 dies); the create assert (L186–192) becomes `skillId` reaching `jobService.create`; add: technician filtered by exact skillId when matches exist (a technician without the id is absent from the picker), full-roster advisory fallback when zero technicians have the skill (existing notice), mismatched technician cleared on skill change, submit blocked without a skill.
- `src/services/resources/jobs.test.ts` -- create body test (L62–77) pins `skillId`, asserts NO `serviceType`/`requireCompletion*` keys go out.
- `src/features/skills/useSkills.test.tsx` -- response-envelope unwrapping (mock `GET /skills` as `{skills: [...]}`), seed-order preservation (no alphabetical resort), keep throttling/404/reset tests.
- New: `SkillPicker` render/selection test mirroring the old ServiceTypePicker coverage if any (it had none standalone — cover the new component: renders labels, fires onChange, selected state).
- `__tests__/reset-registry-stores.test.tsx`, `__tests__/app-401-wiring.test.tsx`, `__tests__/useMyProfile.test.ts`, `__tests__/home-screen.test.tsx` (L82), `__tests__/more-screen.test.tsx` (L62), `src/services/resources/users.test.ts` (L34) -- drop the `serviceCategories: []` fixtures; verify no test still references the deleted mapping.
- Grep guard: `toJobServiceType`, `JOB_SERVICE_TYPE_BY_CATEGORY`, `SERVICE_CATEGORY_BY_BUSINESS_TYPE`, `serviceCategoriesFor`, `technicianHasSkill`, `resolveServiceCategories`, `ServiceTypePicker` → zero references after this story (JobServiceType enum itself remains for 5.3).

## Tasks & Acceptance

**Execution:**
- [ ] `SkillPicker.tsx` (new, presentational tile grid) + `newJob/types.ts` draft field rename
- [ ] `NewJobScreen.tsx` — skills-fed picker, exact-id roster filter, deselect-on-mismatch, `skillId` submission without `requireCompletion*`
- [ ] `skills.ts` — envelope-aware `list()` + slimmed `Skill`; `useSkills.ts` — sort removed from read path
- [ ] `jobs.ts` — create input gains `skillId`, drops the flags (type-only: NewJobScreen never sent them on create — they live only in the edit flow, Story 5.3); `toJobServiceType` chain deleted; `ApiJob` gains the 4.5 fields (additive)
- [ ] Signup — `constants.ts` mapping + barrel entry deleted; `AuthFlow` stops sending `serviceCategories`; `authApi.ts`/`users.ts`/`types.ts` fields + comments updated
- [ ] Delete `serviceCategories.ts` + `ServiceTypePicker.tsx`; grep guard clean
- [ ] Tests per Code Map; `bun run test` green; `bun run lint` clean; `bunx tsc --noEmit` clean (tsconfig.json exists; repo has no typecheck script)

**Acceptance Criteria (from epics-skill-workflow-redesign.md §5.1, verbatim semantics):**
- Given the new-job flow, when I choose what kind of job to create, then a skill picker fed by `GET /skills` replaces the service-category tiles; the selection is required before proceeding.
- Given a selected skill, when the technician picker loads, then the roster is filtered to technicians whose `skillIds` contain that skill id (exact match — no string normalization) for new-job creation; edit-job reassignment stays unfiltered (explicit decision). Zero-match roster degrades to the full roster behind the existing notice (user decision 2026-09-11, recorded in Design Notes).
- Given submission, when I create the job, then the payload sends `skillId` (the `toJobServiceType` translation chain and `ServiceTypePicker` are deleted).
- Given signup/onboarding, when the owner sets up the company, then the business-type → `serviceCategories` mapping is gone from `AuthFlow`, `constants.ts`, and `authApi.ts`.

## Design Notes

**Envelope fix is a real bug closure, not cleanup.** `GET /skills` changed shape in 4.1 (`{skills: [{id, name}]}`, id+name only) and 4.2 killed the old tenant GET. The FE `ApiService.list()` (`src/services/api/ApiService.ts` L94–105) returns `res.data` verbatim, so `fetchSkills()` has been receiving the envelope object against the live backend — the documented Epic-4 merge window. Unwrapping lives in `SkillService` (the resource owns the endpoint shape; `ApiService` stays generic), and the `Skill` type slims to what the endpoint actually returns. `AddTechnicianSheet` consumes the same store, so the fix repairs it too — verify its test still passes unchanged (its AC: "works unchanged against the global list").

**Advisory fallback KEPT (user decision 2026-09-11).** The story AC says the owner "sees only technicians who have that skill", and the original plan hard-filtered a no-match roster to an empty state with an invite hint. The user reviewed this and chose to keep today's behaviour: when zero technicians carry the selected skill id, the picker degrades to the FULL roster behind the existing `noSkillMatch` notice (NewJobScreen L174–179). So the fallback stays exactly as it is — only its match test changes from name-fuzzy to exact `skillIds.includes(skillId)`; the empty-roster branch (no technicians at all) is unchanged. The unfiltered edit flow remains the escape hatch as before.

**Icons.** Skills carry no icon data (name is the display label — api-contracts.md L206). The per-category icon map (`DISPLAY`) dies with `serviceCategories.ts`; tiles keep the grid layout for visual continuity with one neutral glyph. If review prefers text-only tiles, drop the glyph — one-line change.

**ApiJob widening, minimal.** This story only types the new fields (`skill`, `workflowTemplate`, `currentStepIndex`) so the contract is compile-visible; rendering them is 5.2/5.3. `ApiJob.serviceType` stays declared (dead at runtime since 4.3) so its Story-5.3 consumers keep compiling — removal lands with its readers, per the story split.

**Cross-repo ordering:** backend already ships first (Epic 4 done/deployed); this story is the FE consumption step — one repo, one commit series on main, no meta-repo commits.

## References

- [Source: artifacts/planning-artifacts/epics-skill-workflow-redesign.md#Epic-5 / Story 5.1, FR2/FR3/FR10/FR12]
- [Source: workspace/core/backend/fenzit-be/docs/api-contracts.md — GET /skills (envelope, seed order, name = label), POST /jobs body (`skillId`, flags gone, rollout note), job-read shape (Story 4.5 fields)]
- [Source: workspace/core/backend/fenzit-be/src/auth/dto/setup-company.dto.ts — no `serviceCategories` field since 4.2]
- [Source: workspace/core/backend/fenzit-be/src/skills/skills.controller.ts + skills.service.ts — `{skills: [{id, name}]}`, `sort_order` asc, `is_active` filter]
- [Source: fenzo-app exploration 2026-09-11 — NewJobScreen.tsx L42–44/L103–106/L163–204/L224–243/L298–341; jobs.ts L31–37/L64–84/L375–413; serviceCategories.ts; skills.ts; useSkills.ts L83–102; auth/constants.ts L44–54; AuthFlow.tsx L57–62/L187–233; authApi.ts L87–137; users.ts L40/L74–94]
- [Source: artifacts/implementation-artifacts/spec-4-5-read-surfaces-docs-and-test-cutover.md — response shapes + rollout note]

## Dev Agent Record

### Agent Model Used

GLM-5.3-Flash (cloud) via Claude Code agent, 2026-09-11.

### Debug Log References

- `bunx tsc --noEmit`: clean except one PRE-EXISTING baseline error
  `src/config/index.ts(27,22): error TS2591: Cannot find name 'process'` —
  verified identical on the clean baseline via `git stash -u` + re-run; not
  introduced by this story (repo has no typecheck script; tsconfig has no
  node types). Excluding that one file, tsc is clean.
- `bun run test` (jest script): **87 suites / 791 tests, all green** (incl.
  the matrix-row-9 AuthFlow coverage and the matrix-row-1 NewJobScreen
  tile-branch coverage added on review, plus the 10-patch review pass
  additions — useSkills failed-refresh retention, loadSkills-on-mount,
  advisory-fallback submit pairing, profile-error/loading roster branches).
- `bun run lint` (`eslint .`): CANNOT RUN — the repo has no ESLint
  configuration file (`.eslintrc*`/`eslint.config.*` never existed in git
  history; `git log --all` confirms). Pre-existing broken gate, unrelated to
  this story; caller/review should decide whether to add a config.
- Grep guard (`toJobServiceType`, `JOB_SERVICE_TYPE_BY_CATEGORY`,
  `SERVICE_CATEGORY_BY_BUSINESS_TYPE`, `serviceCategoriesFor`,
  `technicianHasSkill`, `resolveServiceCategories`,
  `resolveServiceCategory`, `ServiceTypePicker`, `serviceCategories`):
  ZERO hits in `src/**` and `__tests__/**`. Remaining hits are historical
  planning artifacts only (`_bmad-output/planning-artifacts/prds/.../prd.md`,
  `epics.md`) — Story 5.4's doc sweep — plus the intentional redesign note
  in `api-contracts.md`.
- `JobServiceType` enum + `ApiJob.serviceType` KEPT (Story 5.3 consumers:
  `format.ts`, `customers.ts` HistoryRow, `resources/index.ts` barrel).

### Completion Notes List

- **Implementation follows the Code Map exactly**: draft field
  `serviceCategory` → `skillId`; roster filter is exact
  `t.skillIds.includes(skillId)`; zero-match roster keeps the advisory
  full-roster fallback behind the existing `noSkillMatch` notice (user
  decision 2026-09-11); empty-roster state unchanged; deselect-on-mismatch
  now id-based; submission sends `skillId` and no `serviceType`/`requireCompletion*`.
- **`requireCompletion*` removed from the new-job flow entirely** (draft
  fields, the two switches in the "Job requirements" section, and the create
  body) — the old screen DID send them on create, contradicting the spec's
  note that the create payload never carried them; the I/O matrix
  ("NO requireCompletionPhoto/Signature") governs. The old "switches reach
  the create body" test is retired accordingly; `UpdateJobEditFields` (edit
  flow) keeps the flags for Story 5.3. `EditJobSheet`/`editJobModel` untouched.
- **Section copy updated**: section label "Service type" → "Skill"; gate copy
  "Choose a skill first…"; empty-catalog copy "No skills are available yet."
  (the global catalog is developer-seeded — no "add from Account" hint).
- **`SkillService.list()` override** (not `listCatalog()`): unwraps the
  `{ skills: [...] }` envelope, preserves seed order, and THROWS on a
  malformed/missing envelope so the store's catch branch surfaces it as a
  fetch error (I/O matrix row) instead of putting a broken value in the store.
- **`Skill` slimmed to `{id, name}`** — forced cascade the spec's
  "SkillsScreen untouched" boundary could not survive: `SkillsScreen.tsx`
  read `item.createdAt`, which the slimmed type (and the deployed backend
  since 4.1) no longer has. Removed the dead "Added <date>" render +
  `formatAdded` helper + unused `rowAdded` style (the render was already
  unreachable against the deployed backend). No test asserted that copy.
- **`ApiJob` widening kept minimal and optional** (`skill?`,
  `workflowTemplate?`, `currentStepIndex?` + new exported
  `WorkflowTemplateStep`): optional so the ~20 existing `ApiJob` fixtures
  across 12 test files compile unchanged; the spec's own wording ("optional
  `skill?`") is followed. Rendering lands in 5.2/5.3.
- **`useSkills` write paths untouched**: `addSkill`/`removeSkill` keep their
  sorted-insert behavior (its tests still pass, now seeded from seed-ordered
  read data); only the read path changed (no sort, no stale comment).
- **`AddTechnicianSheet`** untouched and its wiring tests pass unchanged
  (only its test's `Skill` fixtures slimmed to the new type — data, not
  behavior). Its stale "add one from the Skills screen" copy left for 5.4
  per the spec's prefer-leaving note.
- **Test fixture cleanup**: `serviceCategories: []` dropped from
  reset-registry/app-401/useMyProfile/home/more/users fixtures; `Skill`
  fixtures slimmed in reset-registry, SkillsScreen and AddTechnicianSheet
  tests. `src/features/newJob/NewJobScreen.test.tsx` (the AddCustomer wiring
  suite) gained a `../skills` store mock since the screen now reads the store.
- **New `SkillPicker.test.tsx`** covers label rendering, `accessibilityState`
  selected marking and `onChange` (tile query filters out Pressable's
  internal host nodes, which also carry `accessibilityRole: 'button'`).
- **`useSkills.test.tsx` rewritten to mock `apiClient` (not the service
  barrel)** so the REAL `SkillService.list()` envelope unwrap runs under
  test: envelope unwrapping, seed-order preservation (non-alphabetical wire
  order preserved verbatim), malformed-envelope → store error, plus all kept
  throttle/409/404/reset/autoLoad tests.
- `project-context.md` (listed in the spec frontmatter `context:`) does not
  exist at `workspace/core/frontend/fenzo-app/project-context.md` — no such
  file in the repo; the epics file was loaded as context instead.
- FE `_bmad-output/planning-artifacts/api-contracts.md` got ONLY the redesign
  note at the top (pointing at BE docs as authoritative until 5.4), per spec.
- **Review pass (10 patches, 2026-09-11) applied in one sync pass:**
  (1) NewJobScreen now destructures the degraded-state trio from
  `useMyProfile` (`isLoading`/`error`/`refresh`) and, past the skill gate,
  shows a roster spinner while `profileLoading && allTechnicians.length === 0`
  and an error + "Try again" (calling `refreshProfile`) when
  `profileError && allTechnicians.length === 0` — mirroring the skills-store
  tile branches, instead of the premature "No technicians yet" copy;
  (2) `GET /skills` malformed-envelope failures surface the user-facing copy
  `Couldn't load the job types. Please try again.` (new `SKILLS_SHAPE_ERROR`);
  (3) `isSkillRows` guard validates every envelope row has a string id/name
  before it is trusted as data; (4) both roster-filter reads are
  null-guarded — `(t.skillIds ?? []).includes(id)` — in the matching memo and
  the keep-check; (5) the skills spinner branch tightened to
  `skillsLoading && skills.length === 0` (dropped the unused
  `hasLoaded: skillsLoaded` destructure); (6) `loadSkills()` fires on screen
  mount (effect re-added with its import) so a cold start always fetches, and
  tests cover mount-fire + advisory-fallback submit pairing; (7) useSkills
  gains a "retains loaded rows on a failed refresh" test (stale tiles stay
  behind the error, `hasLoaded` stays true); (8) SkillsScreen.test's
  store-order fixture is deliberately non-alphabetical (`Wiring` before
  `Brake check`); (9) the api-contracts redesign note now also names the
  technician-embed `skillIds` field (what the roster filter matches on) and
  the optional 4.5 job embeds `skill`/`workflowTemplate`/`currentStepIndex`,
  still pointing at the BE doc as authoritative; (10) trailing EOF newlines
  restored on NewJobScreen.tsx, types.ts, SkillPicker.tsx, skills.ts,
  useSkills.test.tsx. No production behavior beyond patch 1/2/3/4/5/6
  changed — the rest is tests + docs.

### File List

Modified (fenzo-app paths):

- `src/features/newJob/NewJobScreen.tsx` — skills-fed `SkillPicker`, exact-id
  roster filter, deselect-on-mismatch, `skillId` submission, completion-flag
  switches + payload keys removed, profile-based tile branches replaced by
  skills-store branches; review patches: profile degraded-state
  spinner/error-retry branches, `(t.skillIds ?? [])` guards, mount
  `loadSkills()` effect, spinner branch tightened
- `src/features/newJob/types.ts` — `skillId` draft field; `ServiceType` deleted
- `src/features/newJob/index.ts` — barrel re-exports `NewJobDraft` only
- `src/services/resources/jobs.ts` — `CreateJobRequest` gains `skillId`, drops
  flags; `toJobServiceType` + `JOB_SERVICE_TYPE_BY_CATEGORY` deleted;
  `ApiJob` gains optional 4.5 fields; `WorkflowTemplateStep` added
- `src/services/resources/skills.ts` — envelope-unwrapping `list()` override,
  `Skill` slimmed, header rewritten to the global read-only contract; review
  patches: `isSkillRows` row validation + `SKILLS_SHAPE_ERROR` user-facing copy
- `src/features/skills/useSkills.ts` — seed-order read path (sort removed)
- `src/features/skills/SkillsScreen.tsx` — forced cascade only: dead
  `createdAt` "Added" render + helper + style removed
- `src/features/auth/constants.ts` — `SERVICE_CATEGORY_BY_BUSINESS_TYPE` deleted
- `src/features/auth/AuthFlow.tsx` — `serviceCategoriesFor` + payload field removed
- `src/features/auth/types.ts` — `businessTypes` doc comment corrected
- `src/services/resources/authApi.ts` — `SetupCompanyRequest`/`Tenant` drop `serviceCategories`
- `src/services/resources/users.ts` — `ProfileTenant` drops `serviceCategories`
- `src/features/newJob/NewJobScreen.test.tsx` — skills-store mock added
- `__tests__/new-job-screen.test.tsx` — rewritten to the 5.1 vocabulary;
  review patches: loadSkills-on-mount, advisory-fallback submit pairing,
  profile-error retry, loading-profile no-premature-copy tests
- `src/services/resources/jobs.test.ts` — create body pins `skillId`, asserts
  dropped keys absent
- `src/features/skills/useSkills.test.tsx` — rewritten (envelope/seed-order
  coverage via mocked `apiClient` + real `SkillService`); review patch:
  failed-refresh retention test
- `src/features/newJob/components/SkillPicker.test.tsx` — NEW (render/
  selection coverage)
- `src/features/auth/AuthFlow.test.tsx` — NEW (matrix row 9: setupCompany
  payload carries no `serviceCategories`; ≥1-business-type validation still
  blocks)
- `src/features/skills/SkillsScreen.test.tsx` — `Skill` fixtures slimmed;
  review patch: store-order fixture made deliberately non-alphabetical
- `src/features/technicians/components/AddTechnicianSheet.test.tsx`,
  `__tests__/reset-registry-stores.test.tsx` — `Skill` fixtures slimmed
  (+ reset-registry: `serviceCategories: []` dropped)
- `__tests__/app-401-wiring.test.tsx`, `__tests__/useMyProfile.test.ts`,
  `__tests__/home-screen.test.tsx`, `__tests__/more-screen.test.tsx`,
  `src/services/resources/users.test.ts` — `serviceCategories: []` dropped
- `_bmad-output/planning-artifacts/api-contracts.md` — redesign note only

Deleted:

- `src/features/newJob/serviceCategories.ts`
- `src/features/newJob/components/ServiceTypePicker.tsx`

Created:

- `src/features/newJob/components/SkillPicker.tsx`

Untouched on purpose (verified zero diff): `src/components/TechnicianPicker.tsx`,
`EditJobSheet`/`editJobModel`, `src/features/technicians/components/AddTechnicianSheet.tsx`,
`src/features/jobs/format.ts` + all `serviceTypeLabel`/`serviceTypeToIcon`
consumers, `SkillsScreen` CRUD behavior, `navigation` routes.
## Review Triage Log

### 2026-09-11 — Review pass
- intent_gap: 0
- bad_spec: 0
- patch: 11: (medium 1, low 10)
- defer: 8: (high 1, medium 2, low 5)
- reject: 8
- addressed_findings:
  - `[medium]` `[patch]` NewJobScreen dropped the profile degraded-state surface — a failed/in-flight `GET /users/me` rendered the misleading "No technicians yet" copy with no retry. Restored `isLoading`/`error`/`refresh` from `useMyProfile`; roster spinner while loading with nothing loaded, error + "Try again" on failure; screen tests added for both branches.
  - `[low]` `[patch]` `SkillService.list()` validated only `Array.isArray(skills)` — rows missing id/name passed through as data. Added `isSkillRows` guard; every row must carry a string id and name.
  - `[low]` `[patch]` The malformed-envelope `Error('GET /skills returned an unexpected shape')` leaked developer copy into the user-visible error banner. Replaced with user-facing copy ("Couldn't load the job types. Please try again.").
  - `[low]` `[patch]` `t.skillIds.includes(...)` could throw on a null/missing technician field, violating the Always "no crash" clause. Null-guarded with `(t.skillIds ?? [])` in both the matching memo and the skill-change keep-check.
  - `[low]` `[patch]` Retry-in-flight after a failed load showed the empty-catalog copy instead of a spinner — the spinner branch dropped its `!hasLoaded` condition (`skillsLoading && skills.length === 0`).
  - `[low]` `[patch]` Missing test: submit from the advisory fallback roster (picked pairing reaches the create body).
  - `[low]` `[patch]` Missing test: `loadSkills()` fires on NewJobScreen mount.
  - `[low]` `[patch]` The documented "failed refresh keeps the loaded rows" behavior was unpinned — store-level retention test added (stale rows stay behind the error, `hasLoaded` stays true).
  - `[low]` `[patch]` The renamed SkillsScreen store-order test was vacuous (fixture already alphabetical) — fixture made deliberately non-alphabetical.
  - `[low]` `[patch]` api-contracts.md redesign note was incomplete — now also names the technician-embed `skillIds` (the roster filter's match field) and the optional 4.5 job embeds.
  - `[low]` `[patch]` The diff dropped trailing EOF newlines on 5 files the baseline carried — restored and verified with `tail -c 1`.

Deferred items are recorded in the frontmatter `deferred:` list (Story 5.3: serviceType display consumers; Story 5.4: Skills CRUD surface + write-path docs; test debt: AuthFlow token replacement).

## Auto Run Result

Status: implementation complete; review pass complete (0 loopbacks, review_loop_iteration 0).

- **Summary:** The new-job flow cut over to the global skills catalog — skill picker fed by `GET /skills` (envelope-aware `SkillService.list()`, seed order), draft carries `skillId`, roster filtered by exact `skillIds` id membership with the advisory full-roster fallback kept (user decision 2026-09-11), create payload sends `skillId` with no `serviceType`/`requireCompletion*`, signup stops sending `serviceCategories`, and the dead translation chain (`toJobServiceType`/`JOB_SERVICE_TYPE_BY_CATEGORY`/`serviceCategories.ts`/`ServiceTypePicker`/`SERVICE_CATEGORY_BY_BUSINESS_TYPE`) is deleted. `ApiJob` gained the optional 4.5 embeds (`skill`/`workflowTemplate`/`currentStepIndex`).
- **Files changed:** 29 files (27 tracked modified/deleted + 2 new test files) — see the Dev Agent Record File List for the full annotated list. Highlights: `src/features/newJob/NewJobScreen.tsx`, new `src/features/newJob/components/SkillPicker.tsx`, `src/services/resources/{skills,jobs,authApi,users}.ts`, `src/features/skills/useSkills.ts`, `src/features/auth/{AuthFlow.tsx,constants.ts,types.ts}`, deleted `serviceCategories.ts` + `ServiceTypePicker.tsx`, new tests `SkillPicker.test.tsx`/`AuthFlow.test.tsx`, rewritten `__tests__/new-job-screen.test.tsx` + `useSkills.test.tsx`, FE `api-contracts.md` redesign note.
- **Review findings breakdown:** 4 review layers (blind hunter, edge-case hunter, verification-gap, intent-alignment). 11 findings patched (1 medium: profile degraded states; 10 low), 8 deferred (1 high: pre-existing `serviceTypeToIcon` crash on live BE data — Story 5.3; 2 medium + 5 low: Skills CRUD surface and write-path docs — Story 5.4; AuthFlow token test debt), 8 rejected as noise or spec-sanctioned. Follow-up review recommended: patched counts medium 1 / low 10 → score 3×1 + 1×10 = 13 ≥ 5 → **true**.
- **Verification performed:** `bun run test` — 87 suites / 791 tests, all green (re-run by the coordinator after the patch pass). `bunx tsc --noEmit` — clean except the pre-existing baseline `src/config/index.ts` TS2591 error (verified identical on the untouched baseline). `bun run lint` — unrunnable at baseline: the repo has never had an ESLint config (git history confirms); pre-existing broken gate, unchanged. Grep guard: zero references to all deleted symbols in `src/**` and `__tests__/**`. Matrix test audit: every I/O & Edge-Case Matrix row has a covering test that ran and passed.
- **Residual risks:** (1) the high-severity deferred item — JobCard's unguarded `serviceTypeToIcon` crash is live against the deployed backend today (pre-existing since 4.3); Story 5.3's display sweep must land before the app is used against real job data. (2) `bun run lint` is a dead gate repo-wide — adding an ESLint config is an open repo-level task outside this story. (3) SkillsScreen still renders dead CRUD UI until Story 5.4.
