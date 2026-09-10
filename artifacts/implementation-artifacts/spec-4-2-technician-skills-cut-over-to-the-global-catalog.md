---
title: 'Story 4.2: Technician skills cut over to the global catalog'
type: 'feature'
created: '2026-09-11'
status: 'done'
baseline_commit: '802eb4cf15ebece988508aacd9ee09a077d82408'
review_loop_iteration: 0
context:
  - 'workspace/core/backend/fenzit-be/project-context.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** Technician skills still run on the per-tenant `tenant_skills` vocabulary: invite payloads validate against tenant rows, three read embeds join through `tenant_skills`, signup auto-seeds tenant skills from `tenants.service_categories`, and the tenant-scoped skills CRUD API (left running by Story 4.1) still writes that table. Story 4.1's global `skills` catalog must become the only skill source.

**Approach:** One migration retargets `user_skills.skill_id` to the global `skills` table, drops `tenant_skills` and `tenants.service_categories` (plus the RPC param that writes it), and rewrites `user_skills` RLS. Code: invite validation moves to the global `skills` table, the tenant CRUD endpoints are deleted (global GET kept), the signup seeding path is removed, and all skill embeds join `skills` directly. Response shapes stay as they are (names + ids where they exist today). Pre-launch clean cutover — no shims, no backfills; `tenant_skills` has 0 rows.

## Boundaries & Constraints

**Always:**
- Keep `SkillsController.listGlobalSkills` + `SkillsService.listGlobalSkills` and its minted-JWT read path exactly as shipped in 4.1; do not touch `skills` table DDL, its RLS policy, or the seed UUIDs.
- Invite `skillIds` validation rules stay min 1 / max 20 / unique / UUID; existence check now runs against global `skills` (active rows only).
- Write and apply the migration via Supabase MCP (file + `apply_migration`); run `test/integration/rls-isolation.integration.spec.ts` after the RLS change (launch blocker AR-20).
- Docs (`data-models.md`, `api-contracts.md`, `architecture.md`) updated in the same change; `bun run test` green before any commit.
- `fenzit-be` ships first; `fenzo-app` cutover is a later story.

**Ask First:**
- Any change to the `GET /skills` response shape or to `TechnicianSummary`/`TechnicianProfileResponse`/`ProfileTechnicianEmbed`/`TechnicianEmbed` skill fields (shapes must survive this story unchanged).
- Any deviation from the one-migration approach (e.g. needing a second migration).

**Never:**
- No compat shims, no dual fields, no backfills, no transition period for the dropped tables/columns.
- No changes to `jobs.service_type`, job flags, workflow RPCs, or template work (Stories 4.3/4.4); no FE changes.
- Do not add skill create/edit/delete paths — the global catalog stays developer-seeded only.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Invite with valid global skill ids | `POST /auth/invite`, `skillIds` ⊆ active `skills` rows | users row + `user_skills` rows referencing `skills.id`; response as today | N/A |
| Invite with unknown/inactive skill id | `skillIds` containing a uuid absent from `skills` (or `is_active = false`) | invite rejected before user insert | 400, message no longer references tenant ownership |
| Invite skillIds shape violations | empty / >20 / duplicates / non-uuid | rejected by DTO validation | 422 (unchanged) |
| Skills tenant CRUD removed | `POST /skills`, `DELETE /skills/:id` | routes no longer exist | 404 |
| Global catalog unchanged | `GET /skills`, any authenticated user | same response as 4.1 | unchanged |
| setupCompany | `POST /auth/company` (payload no longer has `serviceCategories`) | tenant created via reworked RPC; no tenant-skill seeding, no category write | RPC failure → existing 500 path |
| Skill embeds | owner profile technicians list, own-profile skills, profile job embeds, job-detail technician embed | names (+ids where present today) sourced from `user_skills → skills` join | empty skills → `[]` as today |
| Cross-tenant skill access | user_skills read/write with other tenant's JWT under RLS | denied | RLS blocks (integration test) |

</frozen-after-approval>

## Code Map

- `supabase/migrations/20260620000004_tenant_skills.sql` -- origin of `tenant_skills` (L2-11, unique index L10), `user_skills` (L14-18, FK → tenant_skills), `users.skill_type` drop (L21 — column already gone; doc residue only), RLS `tenant_skills_tenant_isolation` / `user_skills_tenant_isolation` (L24-45, subquery through tenant_skills)
- `supabase/migrations/20260910000001_create_global_skills.sql` -- 4.1: `skills` table, unique indexes, `skills_authenticated_read`, fixed seed UUIDs (KEEP untouched)
- `supabase/migrations/20260619185741_create_tenants_and_rpc.sql` -- `tenants.service_categories` column (L12) + `setup_tenant_for_owner` RPC (L40-95: param L41, insert L65/69, upsert L76, return L91)
- `src/skills/skills.controller.ts` -- single controller: POST (L31-42) and DELETE (L63-77) die; GET global (L44-61) stays
- `src/skills/skills.service.ts` -- `createSkill` (L37-80) + `deleteSkill` (L120-172) deleted; `listGlobalSkills` (L92-118) stays
- `src/skills/dto/create-skill.dto.ts` -- deleted with POST
- `src/auth/auth.service.ts` -- `inviteTechnician` L229-332: skillIds validation vs tenant_skills L259-280 (retarget, drop `.eq('tenant_id')`), user_skills insert L313-318 (unchanged mechanics); `setupCompany` L334-427: RPC call L346 (drop param), response mapping L374 (drop field), seed block L396-418 (delete)
- `src/auth/dto/invite-technician.dto.ts` -- `skillIds` L46 (rules unchanged); copy L45 says "tenant skill UUIDs" — update
- `src/auth/dto/setup-company.dto.ts` -- remove `serviceCategories` (~L71-77)
- `src/auth/auth.controller.ts` -- stale Swagger "invalid skillType" L113 — fix while here
- `src/users/users.service.ts` -- retarget embeds: technicians list L357-392 (embed L364), `getOwnSkills` L394-414 (L399-403 + tenant filter), `flattenSkills` L416-424, profile job embeds L552-556; drop `service_categories` from profile select L250-256 (L253) + mapping L275; types L154-171, `TenantSummary` L48, `TenantRow` L148, `TenantResponse` shapes in auth.service L31
- `src/jobs/jobs.service.ts` -- job-detail skills embed L717-726 (drop tenant filter), `UserSkillRow` L162-166, flatten L784-792, wiring L831-843
- `src/skills/skills.service.spec.ts` -- keep listGlobalSkills block (L129-277); delete create/delete suites
- `src/auth/auth.service.spec.ts` -- invite validation tests ~L575-780 retarget; setupCompany seed tests L455-560 removed
- `src/users/users.service.spec.ts`, `src/jobs/jobs.service.spec.ts` -- embed mocks re-point to `skills`
- `test/skills.e2e-spec.ts` -- delete POST (L68-163) + DELETE (L237-330) blocks; KEEP GET block (L164-236)
- `test/invite.e2e-spec.ts` -- ownership-check mock (L63-134) → global skills check; unknown-uuid 400 case (L248-259) stays
- `test/jobs.e2e-spec.ts`, `test/company.e2e-spec.ts`, `test/auth.integration.spec.ts` -- embed/fixture updates
- `test/integration/rls-isolation.integration.spec.ts` -- replace tenant_skills/user_skills policy cases with the new `user_skills` policy
- `docs/data-models.md` -- tenant_skills section L165-175, user_skills L177-185, RLS summary L303-304, tenants L85, migration table (rows 04/07 notes; keep rows 22-34 complete, add the new migration)
- `docs/api-contracts.md` -- tenant skills section L212-233 (remove), stale `skillType` L105/L111 (fix), `serviceCategories` in company contract L119 (remove); global Skills section L187-210 stays
- `docs/architecture.md` -- domain diagram L138-141 (TenantSkill entities gone; Technician ── skills via user_skills)

## Tasks & Acceptance

**Execution:**
- [x] `supabase/migrations/20260911000001_tenant_skills_cutover.sql` + MCP apply -- in one migration: drop old FK, add `user_skills.skill_id → skills(id)`; replace `user_skills_tenant_isolation` (scope through `users.tenant_id` instead of the tenant_skills subquery); drop `tenant_skills` (its policy goes with the table); drop `tenants.service_categories`; drop + recreate `setup_tenant_for_owner` without `p_service_categories` (CREATE OR REPLACE cannot change a param list)
- [x] `src/skills/*` -- remove POST/DELETE handlers, service methods, and `create-skill.dto.ts`; keep the global GET path verbatim
- [x] `src/auth/auth.service.ts` + `dto/*` + `auth.controller.ts` -- invite validation vs active `skills` rows; delete seed block; remove `serviceCategories` from DTO, RPC call, response mapping; fix stale Swagger copy
- [x] `src/users/users.service.ts` + `src/jobs/jobs.service.ts` -- re-point the four embeds to `user_skills → skills(!inner)` and drop obsolete tenant filters; drop `service_categories` from profile read/mapping/types; response shapes unchanged
- [x] unit specs (skills/auth/users/jobs) -- delete/retarget per Code Map
- [x] e2e + integration specs (skills/invite/jobs/company/auth/rls-isolation) -- same
- [x] `docs/data-models.md`, `docs/api-contracts.md`, `docs/architecture.md` -- retire tenant CRUD contract, fix stale copy, re-diagram, add migration row

**Acceptance Criteria:**
- Given the migration applied, when inspecting via Supabase MCP, then `tenant_skills` and `tenants.service_categories` are absent, `user_skills.skill_id` references `skills(id)`, and `user_skills` RLS denies cross-tenant access.
- Given an owner invites a technician, when `skillIds` contains global skill uuids, then the created `user_skills` rows reference `skills.id`; an inactive/unknown uuid yields 400 before any user row is created.
- Given `setupCompany` runs, then no tenant-skill seeding occurs and no `service_categories` value is written or returned.
- Given the read surfaces (owner technicians embed, own skills, profile job embeds, job-detail technician embed), when queried, then skills come from the retargeted join with unchanged response shapes.
- Given a fresh clone, when `bun run test` runs (including `rls-isolation.integration.spec.ts`), then all suites pass with no reference to `tenant_skills` outside migration history.

## Spec Change Log

## Review (step-04, 2026-09-11) — 3 review layers, 32 findings → 5 patches / 1 defer / 26 rejected

Blind-hunter (15), edge-case-hunter (9), verification-gap (2 + newline note). Deduped and triaged:

**Patched (all re-verified green):**
1. Real-DB embed probe added (`rls-isolation.integration.spec.ts`) — `user_skills → skills!inner` was verified only against mocks; a broken PostgREST relationship would 500 the three embed reads while every mock-based suite stays green.
2. RLS user_skills probe strengthened — the INSERT denial used a nonexistent user, so 42501 fired on user-existence, not tenancy. Now seeds (service role) a real technician under a real tenant + a user_skills row: cross-tenant SELECT must exclude the seeded row, cross-tenant INSERT → 42501, and the positive WITH CHECK path (same-tenant insert) is exercised; cleanup in `finally`.
3. "Owner A" probe minted `role: 'owner'` → `'authenticated'` (same 22023 fix as round-0).
4. Trailing newlines restored on 5 files (4 TS + the migration SQL).
5. `docs/source-tree-analysis.md` skills block was stale (per-tenant catalog, POST/DELETE routes, CreateSkillDto, SkillType enum) — rewritten for the global-catalog posture. This doc was outside the spec's docs task list.

**Deferred (1):** untested RESTRICT FK behaviour → `deferred-work.md`.

**Rejected highlights (premise false or out of frozen scope):** "recreated RPC lost SECURITY DEFINER/search_path/grants" — the original never had any of them (verified in migration 20260619185741; EXECUTE→PUBLIC is Postgres's default grant; advisor warning pre-existing); "orphaned test body / SEED_SKILLS undefined" — suite compiles and ran 5/5 on the real DB; "FK add fails on orphaned rows" — old FK targeted the empty tenant_skills; "invalid-UUID tenantId cast" — same pre-existing cast pattern as every policy since Story 1.3; inactive-skill display and deactivate-race — no deactivation path exists (developer-seeded catalog) and embed shapes are frozen unchanged.

## Matrix Test Audit (step-03 exit, 2026-09-11)

Every I/O matrix row mapped to a test that RAN green in this session:

| Matrix row | Covering test(s) | Result |
|---|---|---|
| Invite valid global skill ids | `auth.service.spec.ts` — skills-table check mocked at 2nd `.from('skills')` call with `.eq('is_active', true)` asserted; `invite.e2e-spec.ts` AC1 201 path | PASS |
| Invite unknown/inactive skill id | `auth.service.spec.ts` "not in the global catalog" → 400; `invite.e2e-spec.ts` AC5 → 400 | PASS |
| Invite skillIds shape violations (empty/non-uuid) | `invite.e2e-spec.ts` AC3 (empty → 422), AC4 (non-uuid → 422) | PASS |
| Skills tenant CRUD removed | `test/skills.e2e-spec.ts` — POST → 404, DELETE → 404 | PASS |
| Global catalog unchanged | `skills.service.spec.ts` (7 tests) + `test/skills.e2e-spec.ts` GET block (4 tests) | PASS |
| setupCompany (no seeding, no category write) | `auth.service.spec.ts` — RPC params assert no `p_service_categories`; "should not seed tenant skills" asserts no `tenant_skills` call; `company.e2e-spec.ts` 201/200 | PASS |
| Skill embeds unchanged shape | `users.service.spec.ts` + `jobs.service.spec.ts` (embed mocks re-pointed, select-column asserts) + `test/jobs.e2e-spec.ts` detail AC1 | PASS |
| Cross-tenant skill access | `rls-isolation.integration.spec.ts` new `user_skills` case (read → empty, write → 42501) | PASS (real DB) |

Cross-tenant row: the sandbox blocks DNS to `*.supabase.co`, so the real-DB run happened on the user's terminal: full `rls-isolation.integration.spec.ts` 5/5 pass, including the new `user_skills` case. The policy was additionally probed live via Supabase MCP with `SET LOCAL ROLE authenticated` + JWT claims (cross-tenant SELECT → 0 rows, INSERT → `42501`). One pre-existing real-DB bug fixed in passing: the "Owner B" tenants probe minted a JWT with the app role `'owner'` as the JWT `role` claim — PostgREST switches to that Postgres role, which does not exist (`22023`). Both that test and the new `user_skills` probes now mint `role: 'authenticated'` (the 4.1 minted-read pattern). The "Owner A" positive test remains env-gated (`TEST_OWNER_A_USER_ID`) as it has been since Story 1.3.

## Implementation Notes (2026-09-11)

- `bun run test` (unit, rootDir src): 28 suites, 439 tests green. `bun run test:e2e` (test/ dir, separate jest config): 14 suites, 250 passed / 4 skipped. The spec's "bun run test green" command alone does not include the test/ suites — both scripts are needed.
- `bunx tsc --noEmit` is NOT clean — 18 errors, all pre-existing at the baseline commit (files untouched by this story: cloudflare-worker, jobs/places/notifications/users dto+service specs, notifications e2e; the `users.service.spec.ts:848` erroring block is byte-identical to the baseline). Recorded here because the Verification section expected "no type errors" — that was never true at the baseline; fixing pre-existing spec type errors is out of this story's scope.
- RLS integration: `test/integration/rls-isolation.integration.spec.ts` skips its real-DB tests unless SUPABASE_URL is exported before Jest runs (`jest.env.setup.ts` only stubs unset vars). Added a `user_skills` policy case (cross-tenant read → empty, write outside tenant → 42501). Verified against the real DB: 5/5 tests pass (run on the user's terminal with a 30s test timeout; the sandbox cannot resolve `*.supabase.co`).
## Design Notes

- The new `user_skills` policy must keep the tenant-scoping guarantee without `tenant_skills`: scope via the owning user's tenant, e.g. `USING (EXISTS (SELECT 1 FROM users u WHERE u.id = user_skills.user_id AND u.tenant_id = (auth.jwt() ->> 'tenantId')::uuid))`. Keep it FOR ALL to preserve the current write/read posture.
- The app's ordinary paths use the admin client (service_role bypasses RLS), but the RLS policy is still required: tables stay RLS-on with a correct policy (AR-20) and non-admin access (e.g. future minted-JWT reads) must stay tenant-safe.
- Embed retargets are mechanical: `user_skills(tenant_skills(id, name))` → `user_skills(skills(id, name))`; `tenant_skills!inner(...)` → `skills!inner(...)`; drop every `.eq('tenant_skills.tenant_id', ...)` — global skills carry no tenant.

## Verification

**Commands:**
- `bun run test` -- expected: all unit + e2e suites green (use `--no-watchman` under the sandbox)
- `bunx tsc --noEmit` -- expected: no type errors
- Supabase MCP `list_tables` -- expected: `tenant_skills` gone, `tenants` without `service_categories`, `user_skills` FK → `skills`

**Manual checks (if no CLI):**
- `test/integration/rls-isolation.integration.spec.ts` passes against the real DB (needs real credentials; skipped otherwise — record as a defer if skipped)
- `docs/data-models.md` migration inventory stays complete (rows 22-34 intact + new row)
## Suggested Review Order

**Schema cutover (entry point)**

- One migration retargets the FK, rewrites RLS, drops the dead vocabulary
  [`20260911000001_tenant_skills_cutover.sql:14`](../../workspace/core/backend/fenzit-be/supabase/migrations/20260911000001_tenant_skills_cutover.sql#L14)

- RLS now scopes via the owning user's tenant (USING + WITH CHECK, FOR ALL)
  [`20260911000001_tenant_skills_cutover.sql:26`](../../workspace/core/backend/fenzit-be/supabase/migrations/20260911000001_tenant_skills_cutover.sql#L26)

- Drops + slimmed RPC — `CREATE OR REPLACE` can't change a param list
  [`20260911000001_tenant_skills_cutover.sql:48`](../../workspace/core/backend/fenzit-be/supabase/migrations/20260911000001_tenant_skills_cutover.sql#L48)

**Write path — invite validation**

- skillIds now validate against active global-catalog rows
  [`auth.service.ts:258`](../../workspace/core/backend/fenzit-be/src/auth/auth.service.ts#L258)

- setupCompany RPC call lost `p_service_categories`; seeding block deleted
  [`auth.service.ts:341`](../../workspace/core/backend/fenzit-be/src/auth/auth.service.ts#L341)

**Read path — embeds re-pointed to the global join**

- Technician roster embed joins `skills` directly (shape unchanged)
  [`users.service.ts:359`](../../workspace/core/backend/fenzit-be/src/users/users.service.ts#L359)

- Own-profile + batched embeds drop the tenant filter (global skills carry none)
  [`users.service.ts:395`](../../workspace/core/backend/fenzit-be/src/users/users.service.ts#L395)

- Job-detail technician embed — same retarget, one `eq` left
  [`jobs.service.ts:721`](../../workspace/core/backend/fenzit-be/src/jobs/jobs.service.ts#L721)

**API surface**

- Tenant skills CRUD deleted; only the 4.1 global GET survives
  [`skills.controller.ts:1`](../../workspace/core/backend/fenzit-be/src/skills/skills.controller.ts#L1)

**Contracts & docs**

- Invite contract: global catalog UUIDs, 400 for unknown/inactive
  [`api-contracts.md:105`](../../workspace/core/backend/fenzit-be/docs/api-contracts.md#L105)

- Migration 35 row + retired tenant_skills section + new RLS summary
  [`data-models.md:49`](../../workspace/core/backend/fenzit-be/docs/data-models.md#L49)

**Verification**

- Real-DB probes: seeded cross-tenant deny, positive WITH CHECK, embed resolves
  [`rls-isolation.integration.spec.ts:177`](../../workspace/core/backend/fenzit-be/test/integration/rls-isolation.integration.spec.ts#L177)

- Invite mocks assert the catalog check (`from('skills')` + `is_active`)
  [`auth.service.spec.ts:512`](../../workspace/core/backend/fenzit-be/src/auth/auth.service.spec.ts#L512)

- POST/DELETE routes now assert 404; GET block kept verbatim
  [`skills.e2e-spec.ts:60`](../../workspace/core/backend/fenzit-be/test/skills.e2e-spec.ts#L60)
