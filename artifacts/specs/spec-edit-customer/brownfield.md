# Brownfield findings — Edit Customer feasibility (code recon 2026-10-17)

Evidence base for SPEC.md. Paths are repo-relative: `BE` = `workspace/core/backend/fenzit-be`, `FE` = `workspace/core/frontend/fenzit-app`.

## Backend state (fenzit-be — NestJS + Supabase/Postgres)

- **Table** `customers` (BE `supabase/migrations/20260621000001_create_customers_table.sql:4-28`): `id, tenant_id, name, country_code, phone_number, address, city, created_via('manual'|'job_creation'), created_at`; unique index `customers_tenant_phone_unique (tenant_id, country_code, phone_number)`; tenant RLS policy (defense-in-depth only). Later migrations add nullable `formatted_address, pincode, latitude, longitude, place_id` (`20260905000005`) and `address_details VARCHAR(255)` (`20261016000002`). **No `updated_at` column, no status/soft-delete.**
- **API surface today**: only `POST /customers`, `GET /customers`, `GET /customers/:id` — all `@Roles(Role.OWNER)` (BE `src/customers/customers.controller.ts:39-126`). **No PATCH/PUT/DELETE exists anywhere** (also confirmed absent in `BE docs/api-contracts.md:298-333`). `created_via='job_creation'` customers come from `findOrCreateByPhone` (BE `src/customers/customers.service.ts:261-351`) and may carry only a merged address line.
- **Jobs→customer linkage** (BE `supabase/migrations/20260621000002_create_jobs.sql:11-13`): `jobs.customer_id` FK `ON DELETE RESTRICT` (a link, not a copy) plus **one denormalized snapshot column `jobs.service_location`** stamped at creation by `create_job_with_log` (BE `supabase/migrations/20260911000003_generic_workflow_engine.sql:127-187`). Customer name/phone are never copied onto the job. There is no `job_steps` table — steps live in the workflow-template JSONB stamped onto the job; `activity_logs`/`attachments` reference `job_id` only; notification payloads carry no customer fields.
- **Live-join surfaces** — where a customer edit *is* visible on past jobs:

  | Customer field | `GET /jobs/:id` (BE `src/jobs/jobs.service.ts:791-798, 920-931`) | `GET /sync` (BE `src/sync/sync.service.ts:20, 88-91`) | Reports (BE `src/reports/registry/technician-job-activity.data.ts:72-73, 284`) |
  |---|---|---|---|
  | name | changes | changes | changes |
  | phone / country code | changes | — | — |
  | address, city | changes | address changes | — |
  | latitude, longitude | changes | — | — |
  | formattedAddress, addressDetails | changes | — | — |
  | `jobs.service_location` | **never changes** (snapshot) | never changes | never changes |

  Immutable regardless of any edit: `service_location`, workflow stamp, `activity_logs`, `attachments`, notification payloads, generated report files.
- **Update conventions in repo** (a new PATCH must follow one of these):
  - *Pattern A — guarded supabase update*: `updateOffice` (BE `src/attendance/offices.service.ts:163-249`, controller `:id` PATCH `@Roles(Role.OWNER)`): tenant-scoped `.update(...).eq('id').eq('tenant_id').is('archived_at', null)`, empty result → 404, 23505 → 409, "nothing to update" → 400.
  - *Pattern B — SECURITY DEFINER RPC* with PTxxx SQLSTATEs (e.g. `update_job_with_log`, BE `20260911000003:206-294`), granted to `service_role` only.
  - PATCH-DTO precedent: `update-job.dto.ts:9-11` `PickType`s the mutable subset; `PATCH /jobs/:id` refuses non-scheduled jobs (409 `JOB_NOT_MODIFIABLE`).
  - `updated_at` convention: `update_updated_at_column()` trigger (BE `20260621000011_delta_sync_index.sql:8-22`, reused by `20261004000002`).
  - Error envelope `{ statusCode, error_code, message }` (BE `src/common/filters/global-exception.filter.ts:93-101`); "Company setup required" 400 for missing tenantId (BE `src/customers/customers.service.ts:205-210`); cross-tenant reads are 404, never 403 (BE `customers.service.ts:551-562`); coordinate validation helper `assertValidCoordinates` (BE `customers.service.ts:188-199`).
- **Technician sync caveat**: `GET /sync` delta is keyed on `jobs.updated_at` (BE `sync.service.ts:45`). A pure `customers` UPDATE does not bump any job row, so technicians do not receive edited customer data until that job row changes for another reason.
- **No triggers/audit on `customers`**; nothing syncs customer→jobs; no customer audit table (repo-wide trigger grep: jobs/notifications/users only).

## Frontend state (fenzit-app — React Native, no react-query; fetch client + module stores)

- **Add Customer** is a full-page native-stack route, design-v2 sectioned layout: `src/features/customers/AddCustomerScreen.tsx` (route `AddCustomer`, `src/navigation/RootNavigator.tsx:97-101`; params `{ returnRouteName?: 'Customers'|'NewJob'|'Home', pickedAddress? }`, `src/navigation/types.ts:149-152, 273`). Nine bare `useState` fields (name, phone, city, area, street, addressDetails, snapshot `PickedAddressSnapshot`, previewLine; lines 77-91). Validation `canSubmit` (189-193): name + 10-digit phone + location signal. Submit: `toCreateCustomerRequest` (`src/features/customers/requestMapping.ts:23-48` — merges `street + ", " + area` into one `address`) → `useCreateCustomer` (`src/features/customers/useCreateCustomer.ts:75-127`) → `customerService.create` → `POST /customers`. Carries tested guards: the discard dialog (146-166), in-flight back guard (`useCreateCustomer.ts:60-73`), read-once-then-clear `pickedAddress` (133-139). ~25 test cases pin behavior (`AddCustomerScreen.test.tsx:210-752`).
- **Entry points today**: CustomersScreen header Add (`CustomersScreen.tsx:84-85`), NewJobScreen (`NewJobScreen.tsx:369-370`, returns `createdCustomerId` via popTo-merge), HomeScreen quick action (`HomeScreen.tsx:103-105`).
- **Surfaces where Edit would live**: `CustomerDetailScreen.tsx` (owner-only route; identity row with Call IconButton at 234-240, header-right 280-292; refetches on focus 147-151, so returning from edit auto-refreshes). Customers rows (`CustomerRow.tsx`) are tap-only — no swipe/long-press actions.
- **Edit precedent to copy**: `OfficeFormScreen` (`src/features/attendance/offices/OfficeFormScreen.tsx`) — one route for add+edit; `officeId` param presence = edit; load-and-seed effect with 404 view (73-96); copy switches (`isEdit ? 'Edit office' : 'Add office'` 210, `'Save changes' : 'Create office'` 260); **diff PATCH** via `buildUpdatePatch` (120-133). Sheet alternative: `EditJobSheet` (`src/features/jobDetail/components/EditJobSheet.tsx`, diff `buildPatch`, re-seed only on visible-transition).
- **Data layer**: `customerService = { create, list, listAll, getById }` (`src/services/resources/customers.ts:215-220`); its own file doc (5-12) says promote to `ApiService` when update/delete exist. Store `useCustomers` (`src/features/customers/useCustomers.ts:53-84`) — `upsertCustomer` already replaces by id (185-193, but prepends → reorders list); invalidation convention after mutation: `upsertCustomer(updated)` + `loadCustomers({ force: true })` (`useCreateCustomer.ts:97-101`).
- **Known gaps an edit must close**: FE `CustomerDetail` type omits `pincode/latitude/longitude/placeId` although the BE detail response carries them (`customers.ts:133-157` vs BE `customer-detail-response.dto.ts:61-76`) — must extend or the map pin cannot prefill; edit entry must load via `getById` (list rows lack coordinates). `MapPinPicker` already accepts `initialLatitude/initialLongitude/radiusM` (`types.ts:178-183`, consumed `MapPinPickerScreen.tsx:76-85`) but AddCustomer passes none today.
- **Role gating is structural**: technician vs owner render different navigators (`App.tsx:88`); Customers/CustomerDetail exist only in the owner tree — no per-button role check needed; server 403 surfaces through the error mapping.

## Reuse verdict

Reusing AddCustomerScreen for edit is feasible with moderate, well-precedented surface area (OfficeFormScreen pattern): add `customerId` route param, load-and-seed, copy switches, branch submit to a new PATCH, prefill the picker, extend the detail type, add the entry affordance. The single hard dependency is the missing `PATCH /customers/:id` — the feature is blocked on that BE endpoint (FE cannot ship ahead of it; additive BE change deploys first per cross-repo ordering).

## History integrity verdict

The constraint "edit must not affect previous completed tasks and their data" holds for the **job record** (service_location snapshot, steps, attachments, logs, status — nothing writes to job-side tables on a customer edit). It does **not** hold for the customer fields **displayed** on historical job views: job detail, technician sync, and reports live-join `customers` at read time, so past jobs show current contact info after an edit. Resolved 2026-10-17: live-join display semantics adopted (see SPEC Constraints); freezing displayed info would have required a per-job customer snapshot migration — a different, larger scope.
