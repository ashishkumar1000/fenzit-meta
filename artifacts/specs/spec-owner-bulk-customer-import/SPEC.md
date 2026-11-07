---
id: SPEC-owner-bulk-customer-import
companions: [import-flow.md]
sources: []
---

> **Canonical contract.** This SPEC and the files in `companions:` are the complete contract for what to build, test, and validate.

# Staff bulk customer import (Excel, with per-row geocode)

## Why

Fenzit staff onboard existing owners by hand, one customer at a time. A staff member needs to load an owner's existing customer list from a spreadsheet, fix bad rows, and fill in map coordinates before submit. Scope is **staff only**: owners do not get this feature.

## Capabilities

- **CAP-1**
  - **intent:** Staff can upload an Excel or CSV file (required: name, address, phone; optional: latitude, longitude, city, state, pincode, address_details) for a searched owner's company and see a parsed preview. The screen shows the column format before upload and offers a sample file (.xlsx and .csv, headers plus one example row) to download, fill and upload.
  - **success:** A 50-row sheet produces a 50-row preview with per-row values and per-row errors. A malformed file shows a plain-English error and no rows.
- **CAP-2**
  - **intent:** Staff can edit any preview cell, and each row is re-validated by the server after an edit.
  - **success:** Editing a phone to a duplicate or invalid value marks that row, without touching other rows.
- **CAP-3**
  - **intent:** Staff can press "fetch location" on a row to fill latitude and longitude from all of its address parts (address, city, state, pincode) that are filled, and repeat after editing any of them.
  - **success:** A known address returns coordinates in the row. An unknown address shows "no location found" and leaves coordinates blank. Repeat fetch overwrites the previous coordinates.
- **CAP-4**
  - **intent:** Staff can submit the import. Valid rows are saved as customers of the chosen company. Rows whose phone matches an existing customer update that customer, changing only the fields the sheet fills in (name, address, coordinates). Phone never changes, and a blank cell never clears a stored value. Failed rows are returned with reasons and are not saved.
  - **success:** After submit, each valid row exists once for that company. A duplicate phone updates the existing customer and creates no second row. A failed row is reported with its reason, and valid rows are saved even when others fail.
- **CAP-5**
  - **intent:** The flow runs on the company that staff selected through phone lookup, and never on any other company.
  - **success:** Every request carries that company's id. A row written for company A never appears under company B.

## Constraints

- Staff only. Every new endpoint requires `user.manage` and an `X-Company-Id` header. A company owner's token is refused.
- The server owns validation, phone normalisation, tenant scope and duplicate rules. Client-side parsing is a convenience, and the server re-checks every row.
- The Google key stays on the server. The browser never calls Google.
- Web rules: CSS Modules, data loaded in loaders (no fetch in `useEffect`), exact-pinned dependencies. A new dependency must be at least two weeks old and listed in the standards stack table.
- Backend ships first. The change is additive. Schema changes are allowed (pre-launch).
- Limits: at most 500 rows and 5 MB per import. Accepted formats: `.xlsx` and `.csv`, same columns. Column format is in import-flow.md and is shown on the upload screen.

## Non-goals

- Owner-facing import, in any app or console.
- Formats other than `.xlsx` and `.csv`.
- Merging customers or deleting any customer. Duplicates update the matching customer only, and only in the fields the import sets.
- Creating jobs, or importing anything other than customers.
- Automatic geocoding without a staff action.
- Mobile app changes.
- Imports over 500 rows in one go. Larger lists are imported in several batches.

## Success signal

Staff search an owner by phone, upload a 50-row sheet with two bad phones and one unknown address, fix the bad rows, fetch the coordinates, and submit. The owner's customer list then shows the new rows with coordinates. The duplicate phone updates its existing customer, and the bad rows are reported with reasons.

## Decisions (confirmed by user)

- Duplicate phone: **update existing** customer. Only fields the sheet fills in change (name, address, coordinates). Phone never changes; a blank cell never clears a stored value.
- Commit: **partial, row by row**. Valid rows save; failed rows are returned with reasons.
- Address lookup: fetch location uses **every filled address part** (address, city, state, pincode, country India). The server builds the query, not the browser.
- State: **optional** sheet column (up to 100 characters), stored in a new nullable `customers.state` column (pre-launch schema change, same migration as `created_via`). Written by import only; manual create/edit forms are unchanged.
- Coordinates: **optional**. A row may save without lat/lng; the preview flags it as having no map pin.
- Geocode budget: **60 per minute per staff user**, separate from the reverse-geocode budget.
- Sample file: **browser-generated** from the same column list (no backend route). Offered as .xlsx and .csv. Its example row is marked as an example, so staff delete it before upload.
- Limits: **500 rows** and **5 MB** per import. Formats: `.xlsx` and `.csv`.
- Audit: **one import-batch record per run** (who, company, file name, row counts, outcome) plus the `bulk_import` tag on each new customer. Adds one table.
- Phone without a dial code: the staff member picks **one country for the whole sheet** before upload. Rows that already carry a dial code keep it, and a row whose code differs from the picked country is flagged.
- Parsing: the file is read **in the browser**. Rows go to the backend as JSON, so there is no upload route. The backend re-checks every row.
- Company choice: staff pick the company from the **phone lookup results**. Each company the person belongs to is a choice.
- Owner visibility: **yes**. The import writes one company audit entry, "Fenzit staff imported N customers", visible in the owner's audit log.

## Assumptions

- "Seed the data in db" means importing into the searched owner's company, not creating test fixtures.
