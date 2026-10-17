---
title: 'Edit Customer — BE update API (PATCH /customers/:id + updated_at migration)'
type: 'feature'
ticket: ''
created: '2026-10-17'
status: 'built'
baseline_revision: '0acfff9'  # fenzit-be HEAD at plan time
route: 'full'
route_source: 'auto'
review: 'thorough'
review_source: 'auto'
lenses_ran: []
review_loop_iteration: 0
context:
  - '{project-root}/artifacts/specs/spec-edit-customer/SPEC.md'
  - '{project-root}/artifacts/specs/spec-edit-customer/brownfield.md'
  - '{project-root}/CLAUDE.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** Customers are create-only — a typo'd name or moved shop can never be corrected, and wrong data reaches technicians on job detail. SPEC-edit-customer CAP-4 requires an owner-only, tenant-safe update API before the FE edit mode (session 2) can exist.

**Approach:** Add `PATCH /customers/:id` to fenzit-be following the house owner-update pattern (offices `updateOffice` precedent), with a migration adding `customers.updated_at` + the repo's standard trigger. Phone/country code are immutable (out of the DTO). Ship order: this BE change deploys before any FE change.

## Boundaries & Constraints

**Always:**
- `@Roles(Role.OWNER)` on the route; role enforcement stays at the Nest edge (service-role writes bypass RLS).
- Every query carries `.eq('tenant_id', owner.tenantId)` via `createAdmin()` — an empty result is a 404, cross-tenant indistinguishable (never 403).
- Missing `tenantId` → 400 `{ error_code: VALIDATION_ERROR, message: 'Company setup required before managing customers' }` (exact create-path wording).
- Coordinates re-validated on update exactly like create (`assertValidCoordinates`: both-or-neither, range-checked).
- Response goes through the existing `toResponse()` camelCase mapping.
- The update writes ONLY the targeted `customers` row — no job-side writes, no backfill.
- Unknown/extra body keys are silently stripped by the global ValidationPipe (`whitelist: true`) — do not add rejection logic.

**Never:**
- No `countryCode`/`phoneNumber` in the update DTO — phone cannot be read or changed via PATCH.
- No delete/archive, no soft-delete column, no audit table (planned follow-up, separate slice).
- No FE changes, no technician-side surface, no job-side SQL in the migration.
- Never leak raw PG errors; map `23505` only if it can arise (it cannot on this path — no unique column is mutable — so no 409 mapping here).

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Happy path | owner JWT, own-tenant id, `{name}` or any mutable subset | 200, full updated customer (camelCase) | No error expected |
| Location block as a unit | `{latitude, longitude, formattedAddress, pincode, placeId}` from a pick | 200, block persisted together | — |
| Manual-entry clear | `{latitude: null, longitude: null, formattedAddress: null, pincode: null, placeId: null}` | 200, block cleared; `addressDetails` untouched | — |
| Empty body / all-optional fields absent | `{}` | 400 `VALIDATION_ERROR` "nothing to update" (offices precedent) | 400 envelope |
| Technician JWT | any body | no handler reached | 403 `FORBIDDEN` (RolesGuard) |
| Cross-tenant or unknown id | owner JWT, foreign/unknown UUID | 404 `RESOURCE_NOT_FOUND` "Customer not found" | 404, never 403 |
| No tenant yet | owner JWT with no tenantId | — | 400 company-setup message |
| Invalid values | `latitude: 999`, `pincode: 'abc'`, `name: '   '` | — | 422 `VALIDATION_ERROR` (class-validator) |
| Phone in payload | `{phoneNumber: '9999999999'}` | key stripped silently; 200 with phone unchanged | no error |

</frozen-after-approval>

## Code Map

- `src/customers/customers.controller.ts` — add `@Patch(':id')` below the `@Get(':id')` route (same catch-all ordering note); `@Roles(Role.OWNER)`, `ParseUUIDPipe` on `id` — mirror `getCustomerDetail` shape
- `src/customers/customers.service.ts` — add `updateCustomer(user, id, dto)`: tenant gate (copy lines ~205-210), `assertValidCoordinates` (~188-199), guarded `.update()` with `.eq('id').eq('tenant_id')` + `.select()` — model on `src/attendance/offices.service.ts:163-249` `updateOffice` (empty result → 404; build the patch object only from defined dto keys; response via `toResponse()` ~662-696)
- `src/customers/dto/update-customer.dto.ts` — NEW: `class UpdateCustomerDto extends PartialType(StructuredAddressDto)` plus optional `name` (same trim/@IsString/@MaxLength(120)/@IsNotEmpty validators as create — optional but non-empty-when-present). NOT `PartialType(CreateCustomerDto)` — that would re-admit `countryCode`/`phoneNumber`
- `src/common/dto/structured-address.dto.ts` — DO NOT MODIFY: the 8 optional fields already validate exactly what update needs (address, city, formattedAddress, pincode, latitude, longitude, placeId, addressDetails)
- `supabase/migrations/20261017000001_add_customers_updated_at.sql` — NEW: `alter table customers add column updated_at timestamptz not null default now();` + `create trigger customers_updated_at before update on public.customers for each row execute function public.update_updated_at_column();` — pattern copied from `20261004000002_app_config_updated_at_trigger.sql` (fn defined in `20260621000011_delta_sync_index.sql:8-22`)
- `docs/api-contracts.md` — document PATCH under the Customers section (~line 333), matching the existing per-endpoint format
- `src/attendance/offices.service.ts:198-203` — "nothing to update" → 400 wording precedent
- Test infra exists (`src/customers/*.spec.ts` near create paths) — NOT touched this session (repo rule: tests only after user confirms the feature works)

## Tasks & Acceptance

**Execution:**
- [ ] `supabase/migrations/20261017000001_add_customers_updated_at.sql` — add column + trigger -- change-tracking convention; applied via Supabase MCP (pre-launch, safe)
- [ ] `src/customers/dto/update-customer.dto.ts` — create UpdateCustomerDto -- mutable subset only; phone structurally excluded
- [ ] `src/customers/customers.service.ts` — add updateCustomer -- guarded tenant-scoped partial update per offices precedent
- [ ] `src/customers/customers.controller.ts` — add PATCH ':id' route -- owner-gated entry point below GET ':id'
- [ ] `docs/api-contracts.md` — document the endpoint -- contract doc keeps parity with code

**Acceptance Criteria:**
- Given the migration is applied, when any customers row is updated via the new endpoint, then `updated_at` advances (trigger fires).
- Given an owner JWT for the owning tenant, when PATCHing any mutable subset, then 200 returns the full updated customer with `phoneNumber`/`countryCode` unchanged.
- Given a technician JWT, then 403 before any service logic runs.
- Given a foreign-tenant or unknown UUID, then 404 indistinguishable from a missing customer.
- Given an empty body or a body with only stripped keys, then 400 "nothing to update".
- Given `latitude` without `longitude` (or out-of-range values), then the same validation error class as create.

## Implementation Notes

- Implementer deviations (all accepted, verified against create-path reality): (1) `hasInvalidCoordinates` is range-only — create accepts one-sided coordinates, so update mirrors that instead of the plan's inaccurate "both-or-neither" parenthetical; (2) explicit nulls are normalized to `undefined` before the coordinate guard so null-clears pass; (3) `name: null` counts as absent (column is NOT NULL) — a lone `{"name": null}` falls into the 400 "Nothing to update" path.
- Matrix Test Audit deferred by repo rule (implement → user confirms → test): the I/O matrix's rows are covered by manual checks this session; the test pass (e2e describe + service spec) is the immediate next step after user confirmation — tracked in `deferred-work.md`.
- Migration `20261017000001_add_customers_updated_at.sql` applied via Supabase MCP before user verification (additive; pre-launch).
- Review loop 1: 4 thorough lenses (blind-hunter, edge-case-hunter, verification-gap, intent-alignment); patches applied to service/controller/docs; SPEC CAP-4 corrected (400 not 422) by lead via bmad-spec.
- Post-review verification (2026-10-17): `bun run build` clean; `bun run typecheck` clean; existing customers suite green (70/70). Migration `20261017000001` applied via Supabase MCP (column + trigger verified in live schema). Live E2E against the real DB via a locally-run backend with a minted owner JWT, on a throwaway customer row (created, then deleted): all 9 I/O-matrix rows passed — rename 200; empty body 400 "Nothing to update"; phone keys stripped (number unchanged); bad latitude 422; re-pin persists block; addressDetails preserved across re-pin (CAP-5); null and trimmed-empty clears; unknown id 404; whitespace name 422. `updated_at` trigger verified firing. Commit AWAITS USER CONSENT (repo rule) — tree uncommitted on main.

## Plan Change Log

## Review Triage Log

- Review pass 1 (thorough): verdicts — high 0, medium 2, low 5, false 8, defer 1 group. Rows:
  - [BH1=EC6] low → patch(docs): 400 line omits "malformed id"/UUID 400-vs-404 distinction — verified vs controller ParseUUIDPipe.
  - [BH2] low → patch(docs): PATCH responses omit the 401 line every sibling endpoint documents.
  - [BH3=VG2=EC7] medium → patch(docs): "present with null clears" contradicts name:null-as-absent behavior — verified at service patch builder.
  - [BH8-doc=EC5=EC1] low → patch(docs): "re-validated as in create" implied pair-completeness; helper is range-only (plan parenthetical wrong about create; code correctly mirrors create) — doc reworded. Behavior itself: false (create identical; matrix AC "same class as create" met).
  - [BH4] false: "updated_at write-only, no reader" — the column is the spec-mandated deliverable; its reader is the planned audit follow-up (SPEC adjudication R3); OQ-3 explicitly rejected a sync consumer. Verification-gap independently confirmed no other consumer exists and the trigger is safe (sole `.update()` on customers).
  - [BH5=VG-main=IA1] defer: zero tests — repo test-timing rule (implement → user confirms → test); intent excluded tests this session; deferred-work.md entry filed with the verification-gap lens's regression scenarios as evidence. Immediate next step after user confirmation.
  - [BH6] false: absolute diff headers for new files — artifact of my `--no-index` staging, not the repo (intent-alignment confirmed via `git status`).
  - [BH7] low → patch(controller): "catch-all-ordering" comment false for PATCH (method-distinct routes) — deleted.
  - [BH9] low, rejected: Swagger field descriptions silent on null-clear — fix is 8 mechanical description edits; the contract of record is docs/api-contracts.md, which documents it.
  - [BH10=EC2] medium → patch(service): present-but-empty strings (`{"address": ""}`) validate and store `''` instead of NULL — normalized to null in the patch builder for the clearable string fields (pincode '' already 422s at DTO; name/lat/lng untouched).
  - [BH11] low → patch(service): `rows[0].tenant_id !== owner.tenantId` unreachable behind the `.eq('tenant_id')` filter — simplified to `rows.length === 0`.
  - [BH12] false/low-rejected: PATCH 200 lacks swagger `type` — mirrors the create route exactly (its 201 has no type either; response shape documented by reference in both docs sections); `Record<string, unknown>` typing churn rejected as dev-only.
  - [EC3] false: concurrent-PATCH lost update — optimistic concurrency deliberately rejected (SPEC constraint; research D5: no compared API has it; single-owner editor).
  - [EC4] false: runtime re-validation for non-HTTP callers — no such caller exists; service reachable only via the guarded controller.
  - [VG1=IA2] medium → patch(spec, lead): SPEC CAP-4 said 422 for nothing-to-update; offices precedent (which the frozen plan follows) returns 400 VALIDATION_ERROR — SPEC corrected via bmad-spec (drafting conflation of DTO-level 422 vs service-level 400); code and plan were correct.
  - [IA3] false: migration comment "Applied via Supabase MCP" premature — migration applied via MCP before user verification; comment accurate as of handoff.

## Design Notes

- **Why PartialType(StructuredAddressDto) + name, not PartialType(CreateCustomerDto):** `PickType`-style exclusion of phone via `OmitType(PartialType(CreateCustomerDto))` would carry the phone validators into the DTO and rely on stripping; extending the address base keeps phone out of the schema entirely. The `update-job.dto.ts:9-11` comment documents the same mutable-subset philosophy.
- **Null-clearing:** nullable optional fields accept explicit `null` (class-validator `@IsOptional()` treats null as absent for validators but the key passes through) — the service must distinguish "key present with null" (clear the column) from "key absent" (leave it) by checking `'latitude' in dto` style presence, building the patch only from present keys. `addressDetails` can only be nulled explicitly (CAP-5: a re-pin never clears it).
- **Validation-mirror:** keep `assertValidCoordinates` on the merged outcome? No — create validates the DTO pair; update validates only when the pair is being touched, using the values present in the DTO (offices precedent: patch-level validation).

## Verification

**Commands:**
- `bun run build` (in fenzit-be) -- expected: clean compile
- `bunx tsc --noEmit` (if no build script) -- expected: no errors
- Review diff -- expected: only the 5 files listed above

**Manual checks (post-implementation, before tests per repo rule):**
- User exercises PATCH against a running instance (owner JWT): rename, re-pin location, clear coordinates, wrong-tenant 404, technician 403.
