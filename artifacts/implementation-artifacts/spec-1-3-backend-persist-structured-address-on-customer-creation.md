---
title: 'Backend — Persist structured address on customer creation'
type: 'feature'
created: '2026-09-05'
status: 'done'
review_loop_iteration: 1
context: []
baseline_commit: 'eb425d1a4e8669aaaa567e176d104dd25d6d69ea'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** After an owner resolves an address via Story 1.2's `/places/resolve/:placeId`, the app has a `ResolvedPlace` (formatted address, pincode, coordinates, place id) but `POST /customers` has nowhere to save it — only the free-text `address`/`city` fields persist today.

**Approach:** Add 5 nullable columns to the `customers` table (additive Supabase migration) and 5 matching optional fields to `CreateCustomerDto`, named identically to `ResolvedPlace` (`src/places/places-provider.ts:16-23`) so no renaming happens at the boundary. Extend the existing single insert/select/response mapping in `customers.service.ts` to carry the 5 fields end-to-end (write on create, read back on create/detail/list) — no new endpoints, no new service methods.

## Boundaries & Constraints

**Always:**
- Migration is additive only: 5 nullable columns (`formatted_address TEXT`, `pincode TEXT`, `latitude DOUBLE PRECISION`, `longitude DOUBLE PRECISION`, `place_id TEXT`), no `NOT NULL`, no `DEFAULT`, following the style of `supabase/migrations/20260903000002_add_jobs_completed_at.sql`.
- All 5 DTO fields are independently optional (`@IsOptional()`), mirroring the existing `address`/`city` pattern (`@Transform(trim)` + `@IsString()` + `@MaxLength()` for strings; `@IsNumber()` for `latitude`/`longitude` — no existing numeric-optional example in this file, this introduces the first one).
- `createCustomer()` (`customers.service.ts:116-166`) maps each new field the same way existing optional fields are mapped: `field: dto.field ?? null`.
- `CUSTOMER_COLUMNS` (`:100-101`), `CustomerRow`/`CustomerResponse` (`:22-32`, `:88-98`), and `toResponse()` (`:535-557`) all gain the 5 fields, so the same create call's response — and later `GET /customers/:id` / `GET /customers` — can read back what was just persisted, not just write it silently.
- `customer-detail-response.dto.ts` gains the 5 fields (matching types/nullability) so Swagger/OpenAPI reflects what `toResponse()` now returns.
- A request with none of the 5 fields succeeds exactly as today (all 5 stored as `null`).

**Ask First:** None — field names, types, and nullability are fixed by `ResolvedPlace`'s existing shape; this is a mechanical extension of one existing mapping, not a new decision.

**Never:** Do not touch `findOrCreateByPhone` (`customers.service.ts:175-264`) or its own parallel insert (`:213-226`) — that path is job-creation-triggered customer creation and is out of this story's scope. Do not add an `area` column — the client-side concatenation-into-`address` convention is unchanged. Do not change `CustomerListItem`'s existing fields, only add to it. Do not require `latitude`/`longitude` together (either may be sent alone) — only add range/format checks per the `Always` bullet below, no cross-field requirement.

**Always (amended, iteration 1):** `latitude` additionally validates `@Min(-90)`/`@Max(90)`; `longitude` additionally validates `@Min(-180)`/`@Max(180)`; `pincode` additionally validates a 6-digit Indian PIN pattern (`@Matches(/^[1-9][0-9]{5}$/)`) when present.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Full structured address | All 5 fields present, valid types, valid JWT+Owner | `201`, customer row has all 5 columns populated, response DTO includes them | N/A |
| Legacy request (today's shape) | None of the 5 fields sent | `201`, identical to pre-story behavior, 5 columns `null` in DB and response | N/A |
| Partial fields | Only some of the 5 present (e.g. `placeId` + `latitude`/`longitude`, no `pincode`) | `201`, provided fields persisted, absent ones `null` | N/A |
| Wrong type | `latitude`/`longitude` sent as non-numeric string | Request rejected before insert | `422` validation error |
| Read-back | `GET /customers/:id` or `GET /customers` for a customer created with structured fields | Response includes the 5 fields with persisted values | N/A |

</frozen-after-approval>

## Code Map

- `workspace/core/backend/fenzit-be/supabase/migrations/<new-timestamp>_add_customer_structured_address.sql` -- new additive migration, 5 nullable columns, style of `20260903000002_add_jobs_completed_at.sql`
- `workspace/core/backend/fenzit-be/src/customers/dto/create-customer.dto.ts:37-49` -- add 5 optional fields after `city`, mirroring `address`'s decorator stack for strings, new `@IsNumber()` pattern for `latitude`/`longitude`
- `workspace/core/backend/fenzit-be/src/customers/customers.service.ts:22-32,88-101,116-166,535-557` -- `CustomerRow`, `CustomerResponse`, `CUSTOMER_COLUMNS`, `createCustomer()` insert payload (`:129-141`), `toResponse()` -- add the 5 fields through every one of these in the same mapping style already used for `address`/`city`
- `workspace/core/backend/fenzit-be/src/customers/dto/customer-detail-response.dto.ts:46-50` -- add 5 fields after `city` (types/nullability matching `ResolvedPlace`)
- `workspace/core/backend/fenzit-be/src/places/places-provider.ts:16-23` -- reference only; `ResolvedPlace` shape the new fields must name-match exactly (`placeId`, `formattedAddress`, `pincode`, `latitude`, `longitude`)
- `workspace/core/backend/fenzit-be/src/customers/customers.service.spec.ts:76-157` -- extend `createCustomer` describe block (sibling to the existing "null-out optional fields when omitted" case, `:95-116`)
- `workspace/core/backend/fenzit-be/test/customers.e2e-spec.ts:89-231` -- extend `POST /api/v1/customers` describe block (sibling to AC1 success case `:90-110` and AC7 whitelist-strip test `:188-230`)

## Tasks & Acceptance

**Execution:**
- [x] `supabase/migrations/20260905000005_add_customer_structured_address.sql` -- add 5 nullable columns to `customers` -- schema prerequisite for everything else
- [x] `src/customers/dto/create-customer.dto.ts` -- add `formattedAddress?`, `pincode?`, `latitude?`, `longitude?`, `placeId?` with validation decorators -- accepts the new optional input
- [x] `src/customers/customers.service.ts` -- extend `CustomerRow`, `CustomerResponse`, `CUSTOMER_COLUMNS`, `createCustomer()`'s insert payload, and `toResponse()` with the 5 fields -- persists and reads back the new data (also extended `CustomerListItem`/`listCustomers` mapping, judged in-scope per frozen Intent's "read back on create/detail/list")
- [x] `src/customers/dto/customer-detail-response.dto.ts` -- add the 5 fields -- keeps Swagger contract accurate
- [x] `src/customers/customers.service.spec.ts` -- unit tests: full fields, legacy (none), partial fields, read-back via `toResponse()`
- [x] `test/customers.e2e-spec.ts` -- e2e tests: `201` with all 5 fields (verify in response), `201` with none (unchanged legacy behavior), `422` on non-numeric `latitude`/`longitude`

**Acceptance Criteria:**
- Given the migration is applied, when `POST /customers` is called with `CreateCustomerDto` including any of the 5 new optional fields, then the customer record is created with those fields persisted alongside `name`/`address`/`city`
- Given `POST /customers` is called with none of the 5 new fields, then it still succeeds exactly as before — no new field is required
- Given a customer created with structured fields, when read back via the create response or `GET /customers/:id`/`GET /customers`, then the 5 fields are present with their persisted values
- Given no `area` column exists anywhere in this change, then the existing client-side `area`-into-`address` concatenation convention is untouched

## Spec Change Log

- **Iteration 1** — Triggered by: all three step-04 review layers (Blind Hunter, Edge Case Hunter, Verification Gap) independently flagged that `latitude`/`longitude` accepted any numeric value (e.g. `9999`) with no range check, and `pincode` had no format check — the original spec had explicitly excluded this under `Never`. Human approved relaxing that exclusion. Amended: `Never` clause no longer excludes range/format validation; added an `Always` bullet requiring `@Min(-90)/@Max(90)` on `latitude`, `@Min(-180)/@Max(180)` on `longitude`, and a 6-digit PIN pattern on `pincode`. Avoids: geographically invalid coordinates (e.g. out of Earth's range) and malformed pincodes being silently persisted. KEEP: all 5 fields remain independently optional — no both-or-neither requirement was added for `latitude`/`longitude` (explicitly rejected per new `Never` bullet), and the existing field-naming/mapping/read-back design from iteration 0 is unchanged.

## Design Notes

Field names deliberately mirror `ResolvedPlace` verbatim (no `formatted_address` vs `formattedAddress` mismatch to reconcile at the DTO boundary) so a future Story 1.5 (`fenzo-app` submitting `pendingAddress`) can spread `ResolvedPlace` fields directly into the customer-creation request body with no field-renaming glue code.

## Verification

**Commands:**
- `bun run test -- customers` -- expected: `customers.service.spec.ts` passes, covering full/legacy/partial field combinations
- `bun run test:e2e -- customers` -- expected: extended `POST /api/v1/customers` describe block passes (201 full, 201 legacy, 422 bad type)
- `bun run build` -- expected: no TypeScript errors

## Suggested Review Order

**Schema change**

- New additive migration: 5 nullable columns, no `NOT NULL`/`DEFAULT`, matching the repo's existing additive-migration style.
  [`20260905000005_add_customer_structured_address.sql:4`](../../workspace/core/backend/fenzit-be/supabase/migrations/20260905000005_add_customer_structured_address.sql#L4)

**Input validation (amended in review iteration 1)**

- `latitude`/`longitude` gain `@Min`/`@Max` geographic range checks, added after review flagged the gap against the original frozen scope.
  [`create-customer.dto.ts:79`](../../workspace/core/backend/fenzit-be/src/customers/dto/create-customer.dto.ts#L79)

- `pincode` gains a 6-digit Indian PIN `@Matches` pattern, same review-driven amendment.
  [`create-customer.dto.ts:72`](../../workspace/core/backend/fenzit-be/src/customers/dto/create-customer.dto.ts#L72)

- `formattedAddress` max length raised from 255 to 500 to avoid rejecting legitimate long Google-resolved addresses.
  [`create-customer.dto.ts:62`](../../workspace/core/backend/fenzit-be/src/customers/dto/create-customer.dto.ts#L62)

- `placeId` field, mirroring `ResolvedPlace`'s naming verbatim so no renaming glue code is needed at the Story 1.5 boundary.
  [`create-customer.dto.ts:96`](../../workspace/core/backend/fenzit-be/src/customers/dto/create-customer.dto.ts#L96)

**Persist → read-back mapping (single reused mapping point)**

- `CUSTOMER_COLUMNS` select list extended so the 5 fields come back on every read, not just written silently.
  [`customers.service.ts:120`](../../workspace/core/backend/fenzit-be/src/customers/customers.service.ts#L120)

- `createCustomer()` insert payload maps each optional DTO field to `null` when absent, same style as `address`/`city`.
  [`customers.service.ts:159`](../../workspace/core/backend/fenzit-be/src/customers/customers.service.ts#L159)

- `toResponse()` maps DB row back to the API response shape — the same function backing the create response, `GET /customers/:id`, and (via `listCustomers`) `GET /customers`.
  [`customers.service.ts:590`](../../workspace/core/backend/fenzit-be/src/customers/customers.service.ts#L590)

- `listCustomers()`'s own select/mapping, extended in the same judgment call (list read-back is in-scope per the frozen Intent's "read back on create/detail/list").
  [`customers.service.ts:307`](../../workspace/core/backend/fenzit-be/src/customers/customers.service.ts#L307), [`customers.service.ts:363`](../../workspace/core/backend/fenzit-be/src/customers/customers.service.ts#L363)

**API surface**

- `CustomerDetailResponseDto` gains the 5 fields so Swagger/OpenAPI matches what `toResponse()` now returns.
  [`customer-detail-response.dto.ts:56`](../../workspace/core/backend/fenzit-be/src/customers/dto/customer-detail-response.dto.ts#L56)

**Tests (peripherals)**

- e2e: full-fields `201`, legacy `201`, and the review-driven range/format `422` cases (out-of-range lat/lng, malformed pincode).
  [`customers.e2e-spec.ts:115`](../../workspace/core/backend/fenzit-be/test/customers.e2e-spec.ts#L115)

- Unit: full-fields and partial-fields persistence + read-back via `toResponse()`.
  [`customers.service.spec.ts:132`](../../workspace/core/backend/fenzit-be/src/customers/customers.service.spec.ts#L132)
</content>
