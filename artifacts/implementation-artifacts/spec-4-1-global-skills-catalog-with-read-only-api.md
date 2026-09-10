---
title: 'Backend — Global skills catalog with read-only API'
type: 'feature'
created: '2026-09-10'
status: 'done'
review_loop_iteration: 1
context: []
baseline_commit: '8675e8c229853c760b600b32d104daaa01e22693'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** "What kind of work" is expressed today through two competing vocabularies: a free-text per-tenant `tenant_skills` table (owner CRUD) and a hardcoded `jobs.service_type` CHECK enum. The skill-driven workflow redesign needs ONE fixed platform-wide vocabulary that jobs are tagged with and technicians carry. Story 4.1 lays the foundation: a global `skills` table seeded exclusively by developer migrations, plus a read-only `GET /skills` for any authenticated user. Everything else (user_skills retarget, template stamping, drops) is Stories 4.2-4.5.

**Confirmed seed list (story time, 2026-09-10, Ashish):** 6 trades — `Plumbing`, `Electrical`, `AC Service`, `AC Installation`, `Pest Control`, `Cleaning` (in this order; `'Other'` is retired — it was a lossy catch-all). Names are stored exactly as these display labels; the FE picker renders them verbatim in seed order.

**Route-collision decision (story time):** the old tenant-scoped `GET /skills` (owner-only, reads `tenant_skills`) cannot coexist with the new global `GET /skills` — same path, same method, two controllers. So in THIS story the `GET /skills` route is REPLACED: it now serves the global catalog to any authenticated user. The old `POST /skills` and `DELETE /skills/:id` (tenant CRUD) stay running untouched until Story 4.2 drops them with the `tenant_skills` table. Pre-launch (NFR1): the FE skills screens read stale shapes in the merge window until Epic 5 rebuilds them — accepted, no shims.

## Boundaries & Constraints

**Always:**
- **Migration first, as a file:** `supabase/migrations/20260910000001_create_global_skills.sql` creates the table, seeds it, and adds RLS; then apply it via the Supabase MCP (`apply_migration` with the same SQL). Never ad-hoc SQL without the migration file (project-context rule 3).
- **Table shape (per epics FR1, amended by review round 1 — see Change Log):**
  ```sql
  CREATE TABLE skills (
    id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    name       TEXT        NOT NULL,
    sort_order INT         NOT NULL,
    is_active  BOOLEAN     NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
  );
  CREATE UNIQUE INDEX skills_name_unique ON skills (lower(name));
  ```
  Case-insensitive uniqueness mirrors the `tenant_skills` pattern (`tenant_skills_tenant_id_name_unique`) so 'ac service' and 'AC Service' can never both exist. `sort_order` (added by review round 1, Ashish-approved 2026-09-10) pins the documented seed order — all rows in one INSERT share one transaction-stable `now()`, so `created_at` cannot order them.
- **Seed rows use FIXED UUIDs** (deterministic across environments — Stories 4.2/4.3 will reference these ids in their own seed migrations and fixtures; `gen_random_uuid()` for a reference table makes cross-migration seeds non-reproducible). Plain `INSERT`s in seed order, each with its `sort_order` (table was created in this same migration — no `ON CONFLICT` needed):
  ```sql
  INSERT INTO skills (id, name, sort_order) VALUES
    ('<fixed-uuid-1>', 'Plumbing', 1),
    ('<fixed-uuid-2>', 'Electrical', 2),
    ('<fixed-uuid-3>', 'AC Service', 3),
    ('<fixed-uuid-4>', 'AC Installation', 4),
    ('<fixed-uuid-5>', 'Pest Control', 5),
    ('<fixed-uuid-6>', 'Cleaning', 6);
  ```
  Generate six v4 UUIDs once (e.g. `bunx uuid` or any generator) and hardcode them.
- **RLS:** `ALTER TABLE skills ENABLE ROW LEVEL SECURITY;` plus exactly one policy — `CREATE POLICY "skills_authenticated_read" ON skills FOR SELECT TO authenticated USING (true);`. No INSERT/UPDATE/DELETE policies → writes are service-role only (the service-role client bypasses RLS, same pattern as `country_codes_public_read` in `20260909000001`). This table is global on purpose — do NOT add a tenant filter to the policy.
- **GET route reads through the JWT-scoped client, not the admin client (amended by review round 1 — see Change Log):** `skillsService.listGlobalSkills(user)` mints a short-lived `role: 'authenticated'` JWT carrying the caller's `sub` (same claim shape as `AuthService.mintRealtimeToken` — the app's own `owner`/`technician` role claims are NOT Postgres roles, so PostgREST would reject the raw app JWT) and calls `this.supabaseClientFactory.create(<minted token>)` `.from('skills').select('id, name').eq('is_active', true).order('sort_order', { ascending: true })`. This keeps the RLS `authenticated` read policy actually exercised by the endpoint (AC-verifying). Do NOT silently switch to `createAdmin()`; the RLS policy working is part of the AC.
- **Controller:** keep the `@Controller('skills')` module path. `GET /skills` is `@Roles(Role.OWNER, Role.TECHNICIAN)` + `@ApiBearerAuth()` (any authenticated user — roles guard is a global `APP_GUARD`, no `@UseGuards` anywhere in `src/`). The old company-setup guard (`if (!owner.tenantId) throw`) is REMOVED for the GET — the catalog is global, readable before/without tenant context.
- **Response envelope stays `{ skills: Skill[] }`** with each skill `{ id, name }` (camelCase boundary naming, same envelope as the old GET so the FE shape change is only field-level). `is_active`, `created_at`, `updated_at` are NOT exposed — the FE has no use for them and the table is developer-managed.
- **Old tenant CRUD stays in the module until 4.2:** `skills.service.ts` keeps `createSkill` (POST) and `deleteSkill` (DELETE) reading `tenant_skills` exactly as today; the old `listSkills` (tenant-scoped) is DELETED — its route is replaced. `CreateSkillDto` stays. `app.module.ts` needs no change (module already registered).
- **Test updates in the same change:** rewrite the GET blocks in `src/skills/skills.service.spec.ts` (global list via JWT client, `is_active` filter, seed order, error mapping) and `test/skills.e2e-spec.ts` (GET: owner AND technician JWTs → 200 `{ skills: [...] }`; 401 with no JWT; POST/DELETE blocks unchanged). GET mocks target the `skills` table.
- **Docs in the same change (NFR7):** `docs/api-contracts.md` — rewrite the `### Skills (per-tenant catalog)` section: `GET /api/v1/skills` is now the global catalog `[Bearer JWT, any role]`, `POST`/`DELETE` marked "deprecated — dropped in Story 4.2"; add a `### Skills (global catalog)` note describing the developer-seeded contract (no create/update/delete endpoint exists). `docs/data-models.md` — add a `### skills` table entry (after `country_codes`-style reference tables; global, developer-seeded, RLS read-only).

**Ask First:** None — table shape, seed list, RLS pattern, and envelope all have direct precedent (`tenant_skills` migration, `country_codes` RLS, existing skills module).

**Never:**
- No create/update/delete endpoint for the global catalog — skills are developer-seeded only (FR1). Never expose a write path through ANY API or UI.
- No drops in this story — do not touch `tenant_skills`, `user_skills`, `jobs.service_type`, `users.skill_type`, `tenants.service_categories`, or any RPC. Purely additive except the one replaced GET route (see Intent).
- Do not add `workflow_templates`, `jobs.skill_id`, or any template columns — that is Story 4.3.
- Do not seed skills through `setupCompany` or any signup path — seeding exists only in the migration.
- Do not touch `fenzo-app` — Epic 5 consumes this endpoint.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Owner JWT | `GET /skills` | `200 { skills: [{ id, name }, ...6 rows] }` in seed order (Plumbing, Electrical, AC Service, AC Installation, Pest Control, Cleaning) | N/A |
| Technician JWT | `GET /skills` | Same `200` seeded list — any authenticated user, no role restriction | N/A |
| No JWT | `GET /skills` | `401` (global `JwtAuthGuard`) | `401` |
| Deactivated skill | Row with `is_active = false` | Excluded from `GET /skills` (service-role can still see it in DB) | N/A |
| Old POST still works | `POST /skills { name }` with owner JWT | `201` — unchanged tenant CRUD against `tenant_skills` (transient until 4.2) | existing contract |
| Old DELETE still works | `DELETE /skills/:id` owner JWT | `200 { success: true }` — unchanged | existing behavior |
| Duplicate name write at DB level | Any direct insert of an existing name (different case) | Rejected by `skills_name_unique` (lower(name)) | DB-level only; no API path |
| Empty DB (seeds not applied) | `GET /skills` before migration | `200 { skills: [] }` — never an error | N/A |

## Code Map

- `supabase/migrations/20260910000001_create_global_skills.sql` -- NEW: table (with `sort_order`) + fixed-UUID seeds (with `sort_order` 1-6) + unique index + RLS policy; applied via Supabase MCP `apply_migration` (same SQL) after the file is written
- `src/skills/skills.service.ts` -- UPDATE: `listSkills` (tenant-scoped) DELETED; new `listGlobalSkills(user: RequestUser): Promise<{ id: string; name: string }[]>` mints an `authenticated`-role token (via the global `JwtService`) and reads via `factory.create(<minted token>)` (see Boundaries); `createSkill` / `deleteSkill` untouched
- `src/skills/skills.controller.ts` -- UPDATE: `GET /skills` handler replaced — now `@Roles(Role.OWNER, Role.TECHNICIAN)`, returns `{ skills: [{ id, name }] }`; `POST` / `DELETE` routes and their Swagger docs kept verbatim (transient until 4.2)
- `src/skills/dto/create-skill.dto.ts` -- REFERENCE (no change): still used by POST
- `src/skills/skills.module.ts` -- REFERENCE (no change)
- `src/skills/skills.service.spec.ts` -- UPDATE: GET block rewritten for the global catalog (JWT-client asserted — spy must show `create(rawJwt)`, never `createAdmin`, on the GET path; seed order; `is_active` filter; 500 mapping); POST/DELETE blocks kept
- `test/skills.e2e-spec.ts` -- UPDATE: GET tests rewritten (owner + technician → 200 seeded shape; 401; mocks on `skills` table); POST/DELETE tests kept
- `src/common/factories/supabase-client.factory.ts` -- REFERENCE (no change): `create(jwt)` exists today with zero callers — this story becomes its first caller
- `src/common/interfaces/request-user.interface.ts` -- REFERENCE (no change): `RequestUser { userId; tenantId: string | null; role; rawJwt }`
- `docs/api-contracts.md` -- UPDATE: Skills section rewritten per Boundaries
- `docs/data-models.md` -- UPDATE: `### skills` entry (global reference table, developer-seeded, RLS authenticated-read); migration table gains row 32 for the new migration
- `test/integration/rls-isolation.integration.spec.ts` -- UPDATE if the file's table list is enumerable: add `skills` (read allowed for any tenant JWT, write denied). If the harness doesn't enumerate tables, note the gap in Dev Agent Record instead of force-fitting (AR-20: RLS changes get tested — the e2e 401/role coverage + JWT-client read path is the minimum)

## Tasks & Acceptance

**Execution:**
- [x] Migration file + MCP apply: table, seeds (6 fixed-UUID rows), unique index, RLS policy
- [x] Service: `listGlobalSkills` via JWT client; old tenant `listSkills` deleted
- [x] Controller: GET route cutover (roles OWNER+TECHNICIAN); POST/DELETE untouched
- [x] Unit spec rewrite (skills.service.spec.ts) + e2e GET block rewrite (test/skills.e2e-spec.ts)
- [x] Docs: api-contracts.md + data-models.md

**Acceptance Criteria:**
- Given migrations run, the DB has `skills` (id, name unique case-insensitive, is_active, timestamps) with exactly the 6 confirmed seed rows, RLS allows SELECT for any authenticated JWT and allows no client writes
- Given any authenticated user (owner or technician), `GET /skills` returns the seeded list as `{ skills: [{ id, name }] }` in seed order; no create/update/delete endpoint exists for the global catalog
- Given the old tenant-skills endpoints, `POST`/`DELETE /skills` still behave exactly as before (nothing breaks; no drops in this story)

</frozen-after-approval>

## Spec Change Log

### 2026-09-10 — Review round 1 (step-04 loopback, review_loop_iteration → 1)

**Triggering findings (3 reviewers + dev-agent live verification):**
1. `GET /skills` read via `factory.create(user.rawJwt)` — but PostgREST switches to the DB role named in the JWT's `role` claim, the app's JWTs carry `role: 'owner'/'technician'`, and those Postgres roles do not exist (verified live: `SET LOCAL ROLE owner` → 22023; `pg_roles` has only anon/authenticated/service_role). The endpoint would 500 for every authenticated user.
2. Seed order unguaranteed: one multi-row INSERT → one transaction-stable `now()` on all rows → `.order('created_at')` has no tiebreaker, so the frozen "in seed order" AC could not be delivered (found by all three reviewers).

**Human resolutions (Ashish, 2026-09-10):** (1) mint a short-lived `role: 'authenticated'` token carrying the caller's `sub` (same claim shape as `mintRealtimeToken`) — app JWTs untouched; (2) add a `sort_order INT` column, seed 1-6, order by `sort_order`.

**Amended (non-frozen amendments approved as frozen-block renegotiations):** Boundaries table shape + seed SQL + GET-route bullet; Code Map service line; Design Notes ordering rationale; Verification MCP checks.

**Known-bad state avoided:** shipping an endpoint that 500s for every user; documenting a seed-order contract the schema cannot guarantee.

**KEEP instructions (must survive any re-derivation):** fixed seed UUIDs (never regenerate); exactly one RLS policy `skills_authenticated_read` SELECT TO authenticated; case-insensitive unique index `lower(name)`; old POST/DELETE tenant CRUD verbatim (until 4.2); old tenant `listSkills` deleted; envelope `{ skills: [{ id, name }] }`; controller handler `async` with awaited service call (NestJS awaits only top-level promises); e2e never asserts `createAdmin` not called (global idempotency interceptor calls it on ordinary requests); POST/DELETE e2e blocks untouched; `maybeIt` real-DB integration pattern with stub-env skip; `--no-watchman` for jest under the sandbox; data-models migration inventory kept complete (rows 22-34).

**Patches applied in the same round:** docs roles wording + 403 (api-contracts + Swagger); api-contracts intro contradiction reword; log wording aligned ("Failed to list skills"); stray `auth.controller.spec.ts` IDE reformat reverted; seed UUID table + sort_order + is_active note in data-models; removed-fields/handoff note in api-contracts; integration test asserts exact seed order + anon → 0 rows.

## Design Notes

- **Why the old GET is replaced, not parallel:** NestJS cannot have two `@Get()` handlers on the same `@Controller('skills')` path — first-registered wins silently, which is a trap worse than an explicit cutover. The old GET (owner-only, per-tenant) is superseded by a strictly wider read (any authenticated user, global) — nothing that legitimately used the old GET loses access to more than it should see.
- **Why keep POST/DELETE one more story:** Story 4.2's tracked AC retires them together with the `tenant_skills` table in one clean migration — splitting the retirement mid-way (CRUD in 4.1) would desync the tracked epics.
- **Why JWT client on the read:** the AC's RLS clause ("read for any authenticated user") is only real if the endpoint's read path is subject to RLS. `createAdmin()` would make the policy dead code and the AC untestable. This is also the first `factory.create(jwt)` caller — if it misbehaves (e.g. the custom JWT lacks a required claim for the `authenticated` role), that is a real finding to surface, not to route around.
- **Why `sort_order` ordering, not name ordering:** the confirmed trade list order (AC tiles first) is the seed order; `name` ordering would shuffle it to ('AC Installation', 'AC Service', 'Cleaning', ...). The FE picker shows seed order, pinned by `sort_order` (amended in review round 1: `created_at` ordering was unguaranteed — a single INSERT stamps one `now()` on all rows).
- **Why fixed seed UUIDs:** Stories 4.2 (`user_skills` retarget) and 4.3 (`workflow_templates` seeds) must reference stable skill ids in their own migrations; random UUIDs would make those seeds environment-dependent.
- **Epic context:** purely additive foundation — 4.2 retargets `user_skills` and drops `tenant_skills` + this module's POST/DELETE; 4.3 adds templates + `jobs.skill_id`; 4.4 the engine; 4.5 read surfaces/docs/test cutover. Cross-repo ordering (NFR5): fenzit-be first, fenzo-app second.

## Verification

**Commands:**
- `bun run test -- skills` — expected: new unit spec passes, POST/DELETE specs unregressed
- `bun run test:e2e -- skills` — expected: GET block passes, POST/DELETE blocks unregressed
- `bun run build` / `bun run typecheck` — expected: clean
- `bun run lint` — expected: clean on touched `src/` files
- Supabase MCP: after `apply_migration`, verify with a SELECT (6 rows, correct names in `sort_order` 1-6) and RLS spot-checks (SELECT under an `authenticated`-role claim → 6 rows in seed order; SELECT under `anon` → 0 rows; INSERT under a JWT → permission denied; `SET LOCAL ROLE owner` → role does not exist, proving the app's own JWT shape is PostgREST-incompatible)

## Suggested Review Order

**PostgREST token fix (the story's sharpest edge)**

- The mint: PostgREST needs a real DB role, so the read uses a short-lived `role: 'authenticated'` token, not the raw app JWT
  [`skills.service.ts:92`](../../workspace/core/backend/fenzit-be/src/skills/skills.service.ts#L92)

- JWT-scoped client still called with a real token; admin client never used on the read
  [`skills.service.spec.ts:137`](../../workspace/core/backend/fenzit-be/src/skills/skills.service.spec.ts#L137)

**Schema + seed order**

- Table with `sort_order`; comment explains why `created_at` cannot pin order
  [`20260910000001_create_global_skills.sql:7`](../../workspace/core/backend/fenzit-be/supabase/migrations/20260910000001_create_global_skills.sql#L7)

- Fixed UUIDs with `sort_order` 1-6 — Stories 4.2/4.3 depend on these ids
  [`20260910000001_create_global_skills.sql:32`](../../workspace/core/backend/fenzit-be/supabase/migrations/20260910000001_create_global_skills.sql#L32)

**API cutover**

- GET returns the global catalog via an awaited service call; POST/DELETE stay verbatim
  [`skills.controller.ts:44`](../../workspace/core/backend/fenzit-be/src/skills/skills.controller.ts#L44)

**Tests**

- e2e GET block: owner/technician/401/empty; POST/DELETE blocks untouched
  [`skills.e2e-spec.ts:164`](../../workspace/core/backend/fenzit-be/test/skills.e2e-spec.ts#L164)

- Real-DB drift check: exact seeded rows in order, anon → 0 rows, writes denied
  [`rls-isolation.integration.spec.ts:92`](../../workspace/core/backend/fenzit-be/test/integration/rls-isolation.integration.spec.ts#L92)

**Docs**

- Contract: new shape, removed-fields + handoff note, scoped no-write claim, 403
  [`api-contracts.md:185`](../../workspace/core/backend/fenzit-be/docs/api-contracts.md#L185)

- Data model: shape, seed-UUID table, is_active as migration-only hook
  [`data-models.md:250`](../../workspace/core/backend/fenzit-be/docs/data-models.md#L250)

## Dev Agent Record

### Agent Model Used

Claude Code (glm-5.3-flash:cloud) — implemented directly in-session; the Agent tool (subagent dispatch) was unavailable this run (safety classifier outage), so the workflow's no-subagent fallback was used.

### Debug Log References

- `bun run test -- skills` — 14/14 pass; `bun run test:e2e -- skills` — 14/14 pass (both runs also passed after a mid-run stash mishap was recovered)
- `bun run test --no-watchman` (full unit suite) — 28 suites, 449/449 pass
- `bun run typecheck` + `bun run build` — clean
- `bun run lint` — 493 errors repo-wide vs 497 on the pre-change baseline (measured via a stash round-trip): no new lint debt introduced; repo-wide lint failures are pre-existing
- Supabase MCP live checks (project pnlvreaijzslfymlnoti): 6 seed rows in order; `pg_policies` shows exactly one SELECT policy for `authenticated`; simulated JWT read (SET ROLE authenticated + request.jwt.claims) → 6 rows; simulated JWT INSERT → 42501 "row-level security policy" denied; case-variant insert 'plumbing' → 23505 on `skills_name_unique`

### Completion Notes List

- Implementation notes (dev-agent decisions taken within the frozen boundaries):
  - The e2e GET spec does NOT assert `createAdmin` was never called: the global idempotency interceptor calls `createAdmin()` on ordinary requests, so that assertion is impossible at the e2e layer. The JWT-client guarantee is asserted precisely in the unit spec (supabaseClientFactory spy).
  - Controller `listGlobalSkills` is `async` and awaits the service before wrapping in `{ skills: ... }` — NestJS awaits only top-level returned promises, so nesting the raw promise produced `{ skills: {} }` in e2e (caught by the e2e run, fixed).
  - `test/integration/rls-isolation.integration.spec.ts` does not enumerate tables (it targets `tenants` directly), but a `skills` row was added in the same style rather than just noting the gap: real-DB test asserting any authenticated JWT can read the catalog and a client write is denied (skipped with the rest when SUPABASE_URL is the stub, exercised by the MCP spot-checks above in this run).
  - `docs/data-models.md`: the migration inventory was stale (21 rows vs 34 actual migrations). Brought fully up to date — the new migration is **row 34**, not row 32 as the Code Map estimated.
  - Seed UUIDs (fixed, do not regenerate): Plumbing d89d67f7-c0fe-42f8-9f76-c1660c98ce97, Electrical 77d9450a-f9a4-4992-a82a-cdf27063e9e9, AC Service 65f33480-b37e-47e2-a4a0-0155b156cc7a, AC Installation 95f021b0-a973-45fc-b73f-db0dc5afd4a0, Pest Control 71cc840c-3663-489e-bbf2-867d92c46619, Cleaning 72f67596-fec7-4ae8-a6f1-fceabaef0d7d
  - Pre-existing watchman failures under the sandbox: pass `--no-watchman` to jest invocations (e2e script needs it appended).
- Matrix coverage: Owner/Technician/No-JWT/Empty-DB rows covered by e2e GET block; is_active-filter row covered by unit spec (query-level `.eq('is_active', true)` assertion — exclusion happens in the DB, which the live RLS spot-check exercised); Old POST/DELETE rows covered by the retained e2e blocks; DB duplicate-name row verified live via MCP (23505).

### Review Round 1 (step-04)

- 3 reviewer layers ran (blind-hunter 15 findings, edge-case-hunter 8, verification-gap 2+1 note) → deduped to 17 findings → 2 intent_gaps (JWT role claim vs PostgREST; seed-order unguaranteed), 8 patches, 1 defer, 7 rejects. `review_loop_iteration` → 1; both intent_gaps resolved by Ashish (authenticated-token mint; `sort_order` column) — see Spec Change Log.
- The most serious finding was NOT caught by any reviewer — it surfaced while verifying their claims: the app's JWT `role: 'owner'` names a Postgres role that does not exist, so PostgREST would reject every call and `GET /skills` would 500 for every user. Proven live: `pg_roles` has only `anon`/`authenticated`/`service_role`; `SET LOCAL ROLE owner` → `22023 role "owner" does not exist`; the earlier verification's simulated-JWT spot-check had used a hand-built `role: 'authenticated'` claim, masking the app's real JWT shape.
- Post-fix live MCP checks (migration dropped + re-applied with `sort_order`): 6 rows with `sort_order` 1-6; `SET LOCAL ROLE authenticated` + request.jwt.claims → all 6 names in seed order; `SET LOCAL ROLE anon` → 0 rows; authenticated INSERT → 42501 denied.
- Verification re-run after patches: `bun run test -- skills` 14/14; `bun run test:e2e -- skills` 14/14; full unit suite 28 suites 449/449; `bun run typecheck` + `bun run build` clean; eslint on the 5 touched src/test files 21 errors vs 24 at baseline (no new lint debt; repo-wide failures pre-existing).
- The stray `src/auth/auth.controller.spec.ts` IDE reformat was reverted — File List below updated accordingly.

### Review Round 2 (bmad-code-review, 2026-09-10)

- 4 reviewer layers (blind-hunter 17, edge-case-hunter 6, verification-gap 2+1 note, acceptance-auditor 1+1) → 27 raw → 23 unique → 11 patches (all applied), 2 defers (appended to deferred-work.md), 10 dismissed. Findings + resolutions in the Review Findings section above.
- Highest-consequence fixes: (1) the integration test's RLS write probe was **vacuous** — it omitted `sort_order`, so the insert failed with a not-null violation (23502) regardless of RLS; the probe now supplies `sort_order` and asserts the error code is exactly 42501 (proven live: INSERT with sort_order → 42501). (2) `schema_migrations` still recorded the obsolete pre-`sort_order` migration (`20260910171911`) beside the corrected one — both history rows deleted and the migration re-applied clean (live: 3 unique indexes incl. `skills_sort_order_unique`; authenticated → 6 rows in seed order; anon → 0; INSERT → 42501). (3) `sort_order` is now UNIQUE so a future seed migration cannot silently break the pinned order. (4) The integration test's READ now runs the **real production chain** — real `SkillsService` + `JwtService` + `SupabaseClientFactory` — so the mint→PostgREST contract that round 1 proved broken is exercised by a runnable test, not only manual MCP probes; `jest.env.setup.ts` now uses `??=` so exporting real credentials actually enables the real-DB suite.
- Also: unit test for the no-tenant boundary (owner without tenantId still reads the catalog); three docs gaps closed in data-models.md (RLS Posture Summary gains a global reference-tables entry; `updated_at` documented as inert; broken seed-table cell fixed); two migration comments corrected (policy-scope comparison, RLS-vs-grants wording).
- Verification re-run after round 2: skills unit 15/15 (was 14, +1); full unit 28 suites 450/450; full e2e 14 suites 258 passed / 3 skipped (real-DB); typecheck + build clean; eslint on the touched files: 5 errors in the unit spec vs 9 at HEAD (no new lint debt).
- MCP note: `apply_migration` records history rows under the name with an apply-time version, so the recorded versions (`20260910*`) do not match the file's `20260910000001` prefix — consistent with earlier MCP-applied migrations in this project; name + statements are what matter and are now clean (single `create_global_skills` row).

### File List

- supabase/migrations/20260910000001_create_global_skills.sql (NEW — applied via Supabase MCP, re-applied after review round 1)
- src/skills/skills.service.ts (UPDATE — listSkills deleted; listGlobalSkills mints an authenticated-role token via JwtService and reads via factory.create(token), ordered by sort_order)
- src/skills/skills.controller.ts (UPDATE — GET cutover to global catalog, async handler, 403 Swagger response; POST/DELETE verbatim)
- src/skills/skills.service.spec.ts (UPDATE — listGlobalSkills block: minted token + sort_order assertions)
- test/skills.e2e-spec.ts (UPDATE — GET block rewritten; POST/DELETE kept; mockCreate wired)
- test/integration/rls-isolation.integration.spec.ts (UPDATE — skills real-DB test via the real SkillsService chain; write probe supplies sort_order + asserts 42501)
- test/jest.env.setup.ts (UPDATE — Supabase vars stub only when unset, `??=`)
- docs/api-contracts.md (UPDATE — global catalog section + deprecated POST/DELETE section + handoff note)
- docs/data-models.md (UPDATE — ### skills entry with sort_order + seed UUID table; migration inventory rows 22-34 filled)

### Review Findings (bmad-code-review, 2026-09-10 — 4 layers, review_mode=full)

Layers: blind-hunter (17), edge-case-hunter (6), verification-gap (2+1 note), acceptance-auditor (1+1) → 27 raw → 23 unique after dedupe → **11 patch, 2 defer, 10 dismissed**.

- [x] [Review][Patch] Integration-test RLS write probe is vacuous: insert omits `sort_order`, so it fails with a not-null violation (23502) regardless of RLS and `writeError not toBeNull()` proves nothing — supply `sort_order` and assert the error code is 42501 [test/integration/rls-isolation.integration.spec.ts:138]
- [x] [Review][Patch] `sort_order` has no UNIQUE constraint — a future seed migration inserting a duplicate value silently breaks the pinned order; add UNIQUE(sort_order) [supabase/migrations/20260910000001_create_global_skills.sql:14]
- [x] [Review][Patch] Stale duplicate migration-history row: `schema_migrations` records `20260910171911_create_global_skills` (old pre-sort_order SQL) alongside the corrected `20260910174759` — a fresh replay would create the table without `sort_order` then fail; delete the stale row (pre-launch, safe) [supabase_migrations.schema_migrations]
- [x] [Review][Patch] `listGlobalSkills` never executed against real PostgREST: the integration test hand-builds its own `role:'authenticated'` JWT + client instead of calling the service (and its query omits `.eq('is_active', true)`), so the exact mint→PostgREST contract that round 1 proved broken is still only manually verified — instantiate the real `SkillsService` (real factory + JwtService) in the integration test [test/integration/rls-isolation.integration.spec.ts:101]
- [x] [Review][Patch] `test/jest.env.setup.ts` unconditionally overwrites `SUPABASE_URL` et al. with the stub, so the real-DB integration suite is always `it.skip` and its own "set real values to run" header is unreachable — use `??=` so exported real credentials take effect [test/jest.env.setup.ts:3]
- [x] [Review][Patch] The "readable without tenant context" boundary is untested: old AC9 (400 when owner has no tenantId) was deleted, nothing asserts a null-tenant owner still gets 200 — add a unit test [src/skills/skills.service.spec.ts]
- [x] [Review][Patch] RLS Posture Summary in data-models.md was not updated for `skills` — the new global reference table has no entry in the summary [docs/data-models.md]
- [x] [Review][Patch] Migration comment "same pattern as country_codes_public_read" is inaccurate — that policy is TO public (anon included), `skills_authenticated_read` is deliberately TO authenticated only; reword to avoid inviting a wrong-scope copy [supabase/migrations/20260910000001_create_global_skills.sql:27]
- [x] [Review][Patch] "Writes are service-role only" is overstated: default grants for anon/authenticated still exist, the denial is RLS-only — reword to "denied via RLS, not via grants" [supabase/migrations/20260910000001_create_global_skills.sql:26]
- [x] [Review][Patch] `updated_at` is inert (no trigger, no write path — deactivation is migration-only) but documented as a normal column; add the doc note that it always equals `created_at` [docs/data-models.md]
- [x] [Review][Patch] Seed-UUID table in data-models.md has a broken cell — `| AC Installation|` missing the padding space [docs/data-models.md]
- [x] [Review][Defer] E2E mocks are never reset between tests (mockCreate/mockCreateAdmin in beforeAll, no clearMocks) — pre-existing harness pattern, fragile for Story 4.2's edits — deferred, pre-existing
- [x] [Review][Defer] Mint-contract duplication: `listGlobalSkills` re-implements `mintRealtimeToken`'s claim shape + jsonwebtoken gotcha; `POSTGREST_TOKEN_TTL_SECONDS` exported unconsumed — shared-mint-helper refactor candidate — deferred, refactor candidate