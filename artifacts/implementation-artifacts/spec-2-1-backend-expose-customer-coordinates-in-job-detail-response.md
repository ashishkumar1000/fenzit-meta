---
title: 'Backend — Expose customer coordinates in job detail response'
type: 'feature'
created: '2026-09-07'
status: 'done'
review_loop_iteration: 1
context: []
baseline_commit: 'a7f659377ece9fa23be4ead7fd1133440deef5fb'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** Epic 1 (Story 1.3) persists `latitude`/`longitude` on the `customers` table, but the technician-facing job-detail endpoint (`GET /jobs/:id`) still returns only `address`/`city` on the embedded customer profile — the app has no way to build the precise coordinate-based maps link Story 2.2 needs.

**Approach:** Strictly additive read-path extension. Extend the one customer read in `getJobDetail()` (select string + row type + response mapping) to carry the two nullable columns end-to-end as `latitude`/`longitude`. No migration (columns already exist), no new endpoint, no new service method, no behavior change for customers without coordinates — their fields come back `null` and everything else in the response is byte-identical to today.

## Boundaries & Constraints

**Always:**
- Extend all four customer-profile touchpoints in `jobs.service.ts` in one pass: `CustomerProfile` (`:70-77`), `CustomerProfileRow` (`:139-146`), the select string (`:707`), and `toDetailResponse()`'s customer mapping (`:832-839`). Miss any one and TypeScript or PostgREST silently drops the fields.
- Both fields are `number | null` in the response — mirror the exact snake→camel mapping style already used for `address`/`city` (`latitude: customer.latitude` etc.); PostgREST returns `DOUBLE PRECISION` columns as JSON numbers.
- A customer with null coordinates returns `latitude: null, longitude: null` in the response — never a fabricated value, never omitted keys (clients rely on stable shape).
- The rest of the job-detail response is unchanged — this story adds two keys inside `customer` and touches nothing else (no order change, no other field).

**Ask First:** None — column names, types, and nullability are fixed by Story 1.3's migration (`20260905000005_add_customer_structured_address.sql`); the response field names must match the `customers` API shape (`latitude`/`longitude`, camelCase at the boundary) so Story 2.2's `openMaps` can consume them without renaming.

**Never:**
- Do not write any DB migration — `latitude`/`longitude` already exist on `customers` (nullable, `DOUBLE PRECISION`) from Story 1.3; re-adding them breaks migration history.
- Do not touch `findOrCreateByPhone` (`customers.service.ts:175-264`) or any customer write path — this story is read-only on customers.
- Do not add coordinates to the job **list** response (`GET /jobs`) or any other endpoint — only `GET /jobs/:id`'s embedded customer profile is in scope (that is what Story 2.2 consumes; list responses stay lean).
- Do not touch `fenzo-app` — Story 2.2 updates `src/services/resources/jobs.ts`'s `JobDetailCustomer` type there. This story only defines the backend shape that 2.2 will mirror.
- Do not add range/format re-validation on read — validation already happened at write time (Story 1.3 DTO `@Min`/`@Max`); re-validating reads is redundant.
- No Swagger DTO change — the jobs controller uses coarse `@ApiResponse` annotations without a typed response schema (`jobs.controller.ts:36-65`); there is no response DTO file to update.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Customer with coordinates | Job whose customer has non-null `latitude`/`longitude` (saved via Story 1.3) | `200`, `customer.latitude`/`customer.longitude` are the persisted numbers | N/A |
| Customer without coordinates | Both columns `null` (legacy customer, or created with none of the 5 structured fields) | `200`, `customer.latitude`/`customer.longitude` are `null`; rest of response identical to today | N/A |
| Partial data | Only `latitude` persisted (allowed by Story 1.3 — fields independently optional) | Each field independently `number \| null`; no cross-field fabrication | N/A |
| Existing error paths | Missing customer row (`PGRST116`), upstream read error, cross-tenant ID | Unchanged: same `404`/`500`/tenant-filter behavior as today (`jobs.service.ts:729-758`) | N/A |
| Additive contract | Any existing consumer (`fenzo-app` job detail, sync, workflow) | Response is strictly additive — two new nullable keys inside `customer`; no existing key changes type or value | N/A |

</frozen-after-approval>

## Code Map

- `workspace/core/backend/fenzit-be/src/jobs/jobs.service.ts:70-77` -- `CustomerProfile` interface: add `latitude: number | null; longitude: number | null;` after `city`
- `workspace/core/backend/fenzit-be/src/jobs/jobs.service.ts:139-146` -- `CustomerProfileRow` interface: add snake_case `latitude: number | null; longitude: number | null;`
- `workspace/core/backend/fenzit-be/src/jobs/jobs.service.ts:707` -- `admin.from('customers').select(...)`: append `latitude, longitude` to the select string (same single query, no extra round-trip)
- `workspace/core/backend/fenzit-be/src/jobs/jobs.service.ts:832-839` -- `toDetailResponse()` customer mapping: add the two camelCase fields
- `workspace/core/backend/fenzit-be/src/jobs/jobs.service.spec.ts:758-990` -- `getJobDetail` describe block: extend `customerOk` fixture (`:79`) and the happy-path assertion (`:871-910`); add a null-coordinates case
- `workspace/core/backend/fenzit-be/test/jobs.e2e-spec.ts:762-953` -- `GET /api/v1/jobs/:id` describe block: extend the response-shape assertion with the two new fields (both populated and null cases)
- Reference: `supabase/migrations/20260905000005_add_customer_structured_address.sql` -- columns this story reads (do not touch)
- Reference: `workspace/core/frontend/fenzo-app/src/services/resources/jobs.ts:213-221` -- `JobDetailCustomer` type Story 2.2 will extend to mirror this response shape (do not touch here)

## Tasks & Acceptance

**Execution:**
- [x] `src/jobs/jobs.service.ts` -- extend `CustomerProfile`, `CustomerProfileRow`, the customers select string, and `toDetailResponse()`'s customer mapping with `latitude`/`longitude` -- the entire backend change
- [x] `src/jobs/jobs.service.spec.ts` -- unit tests: populated-coordinates happy path, null-coordinates customer, mapping integrity of the other `customer` fields
- [x] `test/jobs.e2e-spec.ts` -- e2e: `GET /jobs/:id` response includes the two fields (populated + null), rest of response unchanged

**Acceptance Criteria:**
- Given a job whose customer has saved `latitude`/`longitude`, when the technician's job-detail endpoint is called, then the response's `customer` object includes `latitude`/`longitude` with the persisted values
- Given a customer with no saved coordinates, when job detail is returned, then `latitude`/`longitude` are `null` — never fabricated — and the rest of the response is unchanged
- Given any existing consumer, the response is strictly additive: no existing field changes name, type, or value

### Review Findings

- [x] [Review][Patch] Update `docs/api-contracts.md` job-detail customer embed [docs/api-contracts.md:120-124] — applied: profile-payload jobs-page embed documented as lean (`{ id, name, countryCode, phoneNumber, address, city }`) with an explicit note that the `GET /jobs/:id` detail embed now carries the extra `latitude`/`longitude` (shapes no longer identical); GET /jobs/:id section updated to the new embed shape.
- [x] [Review][Patch] Tighten the unit select-string test [src/jobs/jobs.service.spec.ts:921-941] — applied: test now asserts exactly one `customers` fetch (from-call-count of 1) and the exact select string `'id, name, country_code, phone_number, address, city, latitude, longitude'` (no more `stringContaining`).
- [x] [Review][Patch] Add a partial-coordinates unit test [src/jobs/jobs.service.spec.ts:943-963] — applied: new test covers I/O matrix row 3 (`latitude` set, `longitude` null) asserting independent pass-through with no cross-field fabrication.
- [x] [Review][Patch] Strengthen the additive-contract assertions in the null cases [src/jobs/jobs.service.spec.ts:958-960, test/jobs.e2e-spec.ts:886-893] — applied: both null cases now assert the full `customer` object via `toEqual` (id/name/countryCode/phoneNumber/address/city + nulls), so any mapping regression fails the test.
- [x] [Review][Patch] Live-schema smoke check for the new select columns [src/jobs/jobs.service.ts:713] — closed during review via Supabase MCP: `information_schema` on live project confirms `latitude`/`longitude` exist as nullable `double precision` on `customers`; PostgREST returns them as JSON numbers.
- [x] [Review][Defer] No technician-role coverage for the new fields [src/jobs/jobs.service.spec.ts:871-914] — deferred, pre-existing: the AC4/e2e technician path asserts only the job `id` (repo-wide pattern); the customer mapping is a shared code path already covered by the owner tests.
- [x] [Review][Defer] Job-detail 500s if the Story 1.3 migration hasn't run in an environment [src/jobs/jobs.service.ts:713] — deferred, pre-existing: adding columns to a select is the repo's established pattern (Story 1.3's own read-back has the same coupling); migration-before-deploy is the repo workflow, no runbook entry exists for any endpoint.

## Design Notes

### Dev Agent Record

**Agent Model Used:** claude (GLM) via Claude Code, BMAD dev-story workflow — 2026-09-07

**Implementation Plan:**

TDD red-green-refactor: wrote the 3 unit tests + 1 e2e test first (confirmed RED: 3 unit failures), then implemented the four touchpoints in `jobs.service.ts`, then confirmed GREEN. Implementation is exactly the four touchpoints from the Code Map — no other production code changed.

**Debug Log References:**

- Jest `watchman` is sandbox-blocked in this environment — ran all jest invocations with `--watchman=false`.
- Full e2e run shows 8 failures in `customers.e2e-spec.ts` and `sync.e2e-spec.ts`; verified via `git stash` round-trip that the same 8 fail at baseline commit `a7f6593` — pre-existing, unrelated to this story. No regressions introduced.
- `test/jobs.e2e-spec.ts` has pre-existing eslint `no-unsafe-*` debt (97 errors at baseline, file-wide `JSON.parse` → `any` convention); my additions follow the same file convention (+18 same-class findings). `src/jobs/jobs.service.ts` and its spec lint clean.

**Completion Notes List:**

- ✅ `CustomerProfile`, `CustomerProfileRow`, customers select string, `toDetailResponse()` mapping all carry `latitude`/`longitude` — single query, no extra round-trip.
- ✅ Both fields return `null` (not omitted) for customers without coordinates; every other field byte-identical.
- ✅ Unit tests: populated-coordinates happy path (with select-string assertion proving coordinates ride the same customers read), null-coordinates case with additive-contract assertion.
- ✅ e2e: single test covers populated + null in `GET /api/v1/jobs/:id` with unchanged remaining shape.
- ✅ ACs 1–3 satisfied; `fenzo-app` untouched (Story 2.2's scope).

### File List

- `src/jobs/jobs.service.ts` (modified — 4 touchpoints: `CustomerProfile`, `CustomerProfileRow`, select string, `toDetailResponse()` mapping)
- `src/jobs/jobs.service.spec.ts` (modified — fixture updated, 3 new tests: select-string/once-only, null-coordinates, partial-coordinates)
- `docs/api-contracts.md` (modified — GET /jobs/:id customer embed shape + profile-payload embed note, review patch 1)
- `test/jobs.e2e-spec.ts` (modified — fixture updated, 1 new test)

### Change Log

- 2026-09-07 — Story 2.1 implemented: additive `latitude`/`longitude` exposure in `GET /jobs/:id` customer profile, with unit + e2e coverage. Tests red→green; full suites pass except 8 pre-existing baseline failures in `customers`/`sync` e2e (verified unrelated via stash round-trip).
- 2026-09-07 — Code review (BMAD, 4 adversarial layers): 0 decision-needed, 5 patch, 2 defer, 11 dismissed. All 5 patch items applied (docs/api-contracts.md, tightened select-string test, partial-coordinates test, full-object null-case assertions in unit + e2e); 2 pre-existing-pattern items deferred to `deferred-work.md`. Re-ran suites after patches: unit 69 passed, jobs e2e 96 passed. Story marked done.

- The select string lives inside the `Promise.all` detail-assembly block (`jobs.service.ts:687-723`); adding two columns to it is free — no extra Supabase call, no N+1, consistent with AR-10 (the four reads in the parallel batch are already the established pattern).
- `admin` client (tenant-scoped via `.eq('tenant_id', user.tenantId)`) already RLS-safe for this read — extend the existing query rather than adding a second customers fetch.
- Field names deliberately match Story 1.3's `customers` API shape (`latitude`/`longitude`) and the `ResolvedPlace` naming convention — Story 2.2's `openMaps` consumes them with zero renaming glue.
- Cross-repo ordering: this story merges/deploys **first** (fenzit-be, additive), then Story 2.2 (fenzo-app) consumes the field. Additive change, so no three-step compat dance is needed.

## Verification

**Commands:**
- `bun run test -- jobs` -- expected: `jobs.service.spec.ts` passes, `getJobDetail` block covers populated + null coordinates
- `bun run test:e2e -- jobs` -- expected: extended `GET /api/v1/jobs/:id` block passes
- `bun run build` -- expected: no TypeScript errors

## Suggested Review Order

**The single production change** (four touchpoints, must all land together)

- `CustomerProfile` response type gains the two nullable fields.
  [`jobs.service.ts:70`](../../workspace/core/backend/fenzit-be/src/jobs/jobs.service.ts#L70)
- `CustomerProfileRow` DB row type gains the two snake_case fields.
  [`jobs.service.ts:139`](../../workspace/core/backend/fenzit-be/src/jobs/jobs.service.ts#L139)
- Customers select string gains `latitude, longitude`.
  [`jobs.service.ts:707`](../../workspace/core/backend/fenzit-be/src/jobs/jobs.service.ts#L707)
- `toDetailResponse()` maps them camelCase into the response.
  [`jobs.service.ts:832`](../../workspace/core/backend/fenzit-be/src/jobs/jobs.service.ts#L832)

**Tests**

- Unit: `getJobDetail` happy-path with populated coordinates, null-coordinates case, and `customerOk` fixture update.
  [`jobs.service.spec.ts:758`](../../workspace/core/backend/fenzit-be/src/jobs/jobs.service.spec.ts#L758)
- e2e: `GET /api/v1/jobs/:id` response shape with the two new fields.
  [`jobs.e2e-spec.ts:762`](../../workspace/core/backend/fenzit-be/test/jobs.e2e-spec.ts#L762)
</content>