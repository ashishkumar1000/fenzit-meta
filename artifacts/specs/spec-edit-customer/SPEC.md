---
id: SPEC-edit-customer
companions:
  - brownfield.md
sources: []
---

> **Canonical contract.** This SPEC and the files in `companions:` are the complete, preservation-validated contract for what to build, test, and validate. Source documents listed in frontmatter are for traceability — consult them only if you need narrative rationale or prose color this contract intentionally omits.

# Edit Customer (reuse the Add Customer screen)

## Why

A pain to solve. Customers are create-only today — a typo in a name, a moved shop, or a job-created customer with a rough address can never be corrected, so owners either recreate records (hitting the per-tenant unique phone) or live with wrong data that reaches technicians on job detail. The map-pin-picker spec (`spec-customer-map-pin-picker`) explicitly deferred Edit Customer as future work; this spec is that work. The owner is the only role affected: customers are an owner-only resource end to end.

## Capabilities

- **CAP-1** — Owner edits a customer
  - **intent:** An owner can open an existing customer, change its details (name, city, address/location, address details), and save — the phone number stays as-is.
  - **success:** From the customer detail screen the owner opens the form prefilled with the customer's current values (loaded via `getById`, never the list row) with the phone rendered read-only; saving persists via `PATCH /customers/:id` and the detail screen (focus refetch) and customers list show the updated values while the phone is unchanged.
- **CAP-2** — Location editing with map prefill
  - **intent:** When editing, the saved location renders in the form and prefills the shared map-pin picker, and re-picking behaves exactly as in create.
  - **success:** Opening the picker from edit mode centers on the customer's saved coordinates; a confirmed re-pin or Places search persists new coordinates; manual entry saves null coordinates without ever clearing `addressDetails`.
- **CAP-3** — Completed-job history integrity
  - **intent:** Editing a customer never alters the historical record of completed jobs.
  - **success:** After editing every editable customer field, all job-side rows referencing that customer (jobs incl. `service_location`, workflow stamp, `activity_logs`, `attachments`, notifications) are byte-identical before vs after; completed job detail still renders its original service location, steps, photos, and signatures.
- **CAP-4** — Owner-only, tenant-safe update API
  - **intent:** A PATCH endpoint updates a customer only for the caller's own tenant and only for owners, following house conventions.
  - **success:** Technician JWT → 403 `FORBIDDEN`; cross-tenant id → 404 `RESOURCE_NOT_FOUND` (never 403); a payload with no updatable field after validation → 400 `VALIDATION_ERROR` "Nothing to update" (service-level validation follows the offices precedent; DTO-level failures are 422); phone/country-code keys are not in the update DTO, so if a client sends them the global ValidationPipe strips them silently (house `whitelist` semantics — never a rejection) and the stored phone never changes; success returns the full updated customer in the existing response shape.

## Constraints

- Edit **reuses the Add Customer screen** — the `AddCustomer` route gains an optional `customerId` param (presence = edit mode, the `OfficeFormScreen` single-route precedent); no new screen. Existing add-flow tests must stay green unchanged (user direction; feasibility in `brownfield.md`).
- An edit writes **only** the targeted `customers` row — no writes to any job-side table, no backfill. Cross-repo ordering applies: the additive BE change (PATCH + `updated_at` migration) ships before the FE change.
- **Phone and country code are immutable in v1** (user decision): the update DTO `PickType`s only the mutable fields, so no edit can change or collide a phone number; the edit form shows the phone read-only. The mutable set is exactly the Add Customer form's remaining fields: `name`, `address`, `city`, `addressDetails`, and the picked-location block `latitude`/`longitude`/`formattedAddress`/`pincode`/`placeId`, which is written together from a confirmed pick (or cleared together by manual entry).
- **Past jobs render the customer's current contact info** (live-join display semantics, decided): job-detail embed, technician sync, and reports read `customers` live; the job's own record — `service_location` snapshot, workflow stamp, steps, attachments, logs — is the immutable historical truth. Technician sync staleness is accepted for pre-launch: edited customer data reaches technicians when the job row next changes (no customer-touch sync signal).
- BE update follows existing owner-update conventions: `@Roles(Role.OWNER)`; missing tenantId → 400 company-setup message; `createAdmin()` with explicit `.eq('tenant_id')` (service role bypasses RLS — drift note C1); empty result → 404 with cross-tenant indistinguishable; coordinates re-validated as in create; response via the existing camelCase mapping; `updated_at` column + `update_updated_at_column()` trigger per repo convention.
- FE update follows existing edit precedents: diff-based PATCH payload (`buildUpdatePatch` pattern, mutable fields only), entry affordance on `CustomerDetailScreen` (identity row or header-right, `returnRouteName: 'CustomerDetail'`), cache refresh via `upsertCustomer(updated)` + `loadCustomers({ force: true })`, FE `CustomerDetail` type extended to carry `pincode/latitude/longitude/placeId`, the form's tested guards (discard guard, in-flight back guard, read-once `pickedAddress`) preserved in both modes, and `MapPinPicker` office-mode behavior untouched. Create-flow's merge of street + area into one `address` column is kept; edit prefills the merged line into Street with Area empty.

## Non-goals

- No phone editing, re-verification, or phone-change merge flows in v1 (revisit when an owner needs to correct a customer's changed number — enabling it is a one-field DTO change on top of the existing duplicate check).
- No customer delete, archive, or deactivate.
- No technician-side edit or any customers surface for technicians.
- No per-job customer snapshot — past jobs display current customer contact info by decision; freezing history would be its own spec.
- No audit trail or change-history UI in this slice. Minimal customer edit history (who/when/old→new per changed field) is a **named follow-up backlog item**, not a silent gap — industry evidence: `artifacts/planning-artifacts/research/technical-industry-customer-record-edit-practices-2026-10-17/research.md` (HubSpot ships property history on all plans by default; Salesforce as opt-in).
- No duplicate-merge/dedup tooling (a phone collision stays a create-time 409, not a merge).
- No changes to the office add/edit flows that share `MapPinPicker`/`AddressPickerSheet`.

## Success signal

An owner opens any customer, corrects its name, address, or pin, saves, and sees the fix immediately on detail and list while the phone stays untouched — every completed job for that customer still shows its original service location, steps, photos, signatures, and logs (verified untouched at the row level), and every existing Add Customer test passes without modification.

## Assumptions

- "Owner" means the JWT role `owner`; the edit UI lives only in the owner navigation tree, so no extra client-side role gate beyond the server's 403.
- Pre-launch project: schema changes are allowed, so adding `customers.updated_at` carries no data-preservation burden.
- The create-flow merge of street + area into the single `address` column is kept; splitting it back on edit is rejected as lossy.
