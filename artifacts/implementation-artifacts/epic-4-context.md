# Epic 4 Context: Skill-Based Job Core (Backend)

<!-- Compiled from planning artifacts. Edit freely. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Epic 4 rebuilds the backend's answer to "what kind of work is this job?" around a single trustworthy vocabulary. Today that question is answered by three competing mechanisms (a hardcoded 6-step `WorkflowStep` chain, a `service_type` DB CHECK enum, and free-text per-tenant `tenant_skills`). This epic replaces them with a fixed global `skills` table (developer-seeded only), one skill per job, many skills per technician, and a per-skill workflow template stored as ordered steps JSON that the job stamps at creation. A generic workflow engine then validates every advance against the job's stamped template instead of hardcoded step lists, and the photo-confirm auto-advance becomes a step attribute. It delivers the complete API-level contract the frontend cutover (Epic 5) builds on. Pre-launch: no real users, so destructive migrations, data resets, and breaking API changes are all allowed — clean cutover, no shims, no backfills. (Note: no PRD, architecture, or UX design doc exists for this feature; these requirements come from the agreed design decisions validated against the live code and DB.)

## Stories

- Story 4.1: Global skills catalog with read-only API
- Story 4.2: Technician skills cut over to the global catalog
- Story 4.3: Workflow templates and skill-tagged jobs
- Story 4.4: Generic workflow engine and attachment auto-advance
- Story 4.5: Read surfaces, docs, and test cutover

## Requirements & Constraints

- Skills live in a fixed global `skills` table seeded exclusively by developer migrations. Owners and technicians can never create, edit, or delete skills through any API or UI — the only write path is a migration.
- Every job carries exactly one skill, required at creation. A technician carries many skills (min 1 / max 20 / unique), selected at technician invite. One skill may belong to many technicians.
- Each skill has a workflow template (`workflow_templates`: skill_id, version, steps JSONB, unique per skill+version), authored by developers via seed migrations. Each step carries: key (slug), label, requires_photo, requires_signature, sets_status, advances_on (e.g. `photo_confirm`) — per-step behaviour is data, not code.
- A job stamps its template id + version at creation; that stamp is immutable for the job's lifetime. All workflow validation for the job reads the stamped version's steps, never the live template.
- The engine is generic: the only legal advance target is the first not-yet-completed step in template order; a fresh job's first advance is the template's first step. Status mapping is step-driven: first step → `in_progress`, the `sets_status: 'completed'` step finishes the job and stamps `completed_at`, intermediate steps leave status unchanged.
- The photo-confirm auto-advance reads the stamped template and fires only on the step whose `advances_on` is `photo_confirm`, inside the same transaction as today, keeping activity-log and owner-notification INSERTs (with the self-notify guard). Steps without the attribute never auto-advance.
- The photo cap (5) is enforced from the step attribute (not the job-level flags) across app count, SQL confirm count, and error mapping in attachments + webhooks services.
- `GET /skills` is read-only for any authenticated user (id + name). Job creation takes `skillId` in the payload.
- Job responses (detail, list, sync) include the stamped template's steps — key, label, requires_photo, requires_signature, current index — plus the job's skill id/name, so the FE renders steppers, action bars, and gates dynamically.
- Preserved generically: 422 `INVALID_WORKFLOW_STEP` echoing `currentStep`, PT409 → 409 `JOB_NOT_MODIFIABLE` (terminal + compare-and-set), same-step no-op replay dedup, 24h idempotency-key replay on workflow + attachment endpoints. Notifications/activity log record step keys generically (`event_type` = step slug, `step_<key>` events).
- Resilience: `current_step` stays free TEXT; a non-null value not present in the stamped template must reject all advances (corrupt-data guard), never reset the workflow.
- Dropped in this epic: `tenant_skills` (table + CRUD API), `jobs.service_type` (+ CHECK constraint), `users.skill_type`, `tenants.service_categories` (+ signup seeding in `setupCompany`), and the job-level `require_completion_photo`/`require_completion_signature` flags (columns + create/PATCH params). Stale RPC overload definitions are dropped explicitly in the same migration that re-issues the RPCs.
- Test data is resettable; no backfills. Migration completion may reset existing test jobs.

## Technical Decisions

- Pre-launch clean cutover: one change per repo, destructive migrations allowed, no transition shims, no dual fields.
- Atomicity is preserved from the current RPC generations: `FOR UPDATE` row lock, compare-and-set on `current_step`, PT409 SQLSTATE guards, activity log + owner notification INSERTs inside the same advance transaction. The reworked `confirm_attachment` RPC generations are superseded in one migration.
- Skills seed (confirmed at story time): 6 trades — Plumbing, Electrical, AC Service, AC Installation, Pest Control, Cleaning — in this order, names stored as display labels. Seed rows use fixed UUIDs (deterministic across environments; later stories' seeds and fixtures reference these ids) plus a `sort_order` column to pin seed order (timestamps cannot order same-transaction inserts). Uniqueness is case-insensitive on name.
- The `GET /skills` route is replaced in place: the old tenant-scoped owner-only GET cannot coexist with the new global route. In Story 4.1 the GET serves the global catalog to any authenticated user while old POST/DELETE tenant CRUD keep running until Story 4.2 drops them — a transient merge window where the FE skills screens read stale shapes (accepted, no shims).
- Workflow templates mirror today's 6-step chain shape per skill unless a skill genuinely needs a different chain; template steps are validated against the corrupt-value guard model.
- No triggers, views, or analytics reference workflow columns; the new schema introduces none. The R2 worker is untouched.
- Docs ship in the same change: api-contracts.md, data-models.md (including fixing the stale `sequence_index` claim), architecture.md, project-overview.md, development-guide.md. All affected BE specs are rewritten or retired in the same change; `bun run test` must be green before any commit.
- Code stays small and modular (~300 lines per file): engine, template model, and API layer split across focused files.

## Cross-Story Dependencies

- Story 4.1 is purely additive and must land first: 4.2's `user_skills` retarget and 4.3's template seeds reference the fixed skill UUIDs from 4.1's seed migration.
- Story 4.2 drops `tenant_skills` and its CRUD (which 4.1 deliberately left running) and removes the `service_categories` seeding path — it depends on the skills table only, not on templates.
- Story 4.3 introduces `workflow_templates` + `jobs.skill_id` + stamping; Story 4.4's engine and `confirm_attachment` rework depend on stamped templates existing; Story 4.5's read surfaces depend on 4.3/4.4's shapes.
- Epic 5 (FE) builds purely on Epic 4 and ships after it: `fenzit-be` merges and deploys first, `fenzo-app` second. Epic 4 stands alone as API-complete.