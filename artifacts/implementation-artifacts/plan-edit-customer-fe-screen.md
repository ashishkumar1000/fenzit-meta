---
title: 'Edit Customer — FE edit mode on the shared AddCustomerScreen'
type: 'feature'
ticket: ''
created: '2026-10-17'
baseline_revision: '49ef61f20790221ccb438ef600698a3f22d62d31'
status: 'done'
route: 'full'
route_source: 'pinned'
review: 'thorough'
review_source: 'pinned'
lenses_ran: []
review_loop_iteration: 1
context:
  - 'artifacts/specs/spec-edit-customer/SPEC.md'
  - 'artifacts/specs/spec-edit-customer/brownfield.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** Owners can create customers but cannot correct them (wrong name, moved customer, misspelled address) — the BE PATCH endpoint shipped (fenzit-be `7b7eefb`, live-verified); the app has no way to call it.

**Approach:** Reuse `AddCustomerScreen` for add+edit (OfficeFormScreen precedent): a `customerId` route param switches it to edit mode — load-and-seed via `getById`, phone read-only, copy switches, map-pin prefill, and a diff-based PATCH via a new `customerService.update()`. Entry: an Edit affordance on `CustomerDetailScreen`. No new screen, no new route.

## Boundaries & Constraints

**Always:**
- The phone (number + dial code) is display-only in edit mode; no user path may put `phoneNumber`/`countryCode` in an update payload.
- Diff PATCH: a key is sent only when its value changed vs the seeded baseline. Empty diff → no network call, plain back.
- Location block on a NEW pick replaces the block as a unit: `latitude`/`longitude` always set; `formattedAddress`/`pincode`/`placeId` set-or-explicit-null (a stale pin's line/pincode/placeId must never survive a re-pin). A manual-entry pick (no snapshot) over a pinned customer clears all five with nulls.
- CAP-5: `addressDetails` is cleared ONLY when the user empties the Flat field (explicit null); a re-pin never touches it.
- Edit seed comes from `getById` (list rows lack coordinates); loading/404/error views follow the OfficeFormScreen load precedent.
- The add flow (no `customerId`) must behave exactly as today.

**Never:**
- No new screens or routes; no changes to `MapPinPickerScreen` (it already accepts `initialLatitude/initialLongitude` in `customer` mode); no phone-editing UI; no delete-customer; no tests this session (repo rule: tests after the user confirms on device — log the defer instead).

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Edit entry | owner taps Edit on customer detail | screen opens seeded (name/phone/city/address line/Flat/pin preview), title "Edit customer", button "Save changes", phone not editable | load fail → OfficeFormScreen-style views |
| Save with changes | form differs from baseline | `customerService.update(id, patch)` with only changed keys; 200 → `upsertCustomer` + `loadCustomers({force:true})` → goBack to detail (refetches on focus) | banner per error map; form keeps edits |
| Save with no changes | form identical to baseline | empty patch → no request, plain goBack | — |
| Re-pin location | new map pick with snapshot | block replaced; absent block fields sent as explicit nulls; `addressDetails` untouched | — |
| Manual-entry pick over pinned customer | pick returns no snapshot, baseline had block | all five block keys explicit null; `addressDetails` untouched | — |
| Clear Flat field | `addressDetails` emptied (baseline had one) | explicit `addressDetails: null` | — |
| Phone in edit mode | read-only field | never editable; never in any payload | — |
| Customer gone mid-edit | PATCH → 404 | banner "no longer available"; form stays for retry/back | error banner |
| Add flow unchanged | no `customerId` param | existing add behavior byte-identical; all existing tests green | existing copy |

</frozen-after-approval>

## Code Map

Repo root: `workspace/core/frontend/fenzit-app` (React Native, no react-query; fetch client + module stores; jest via bun).

- `src/features/customers/AddCustomerScreen.tsx` — the screen being extended. 9 bare useState fields (77-91); `canSubmit` (189-193); `buildRequest` (195-219); header title (240) + Save button (378) hardcoded add copy; MapPinPicker navigate (289) passes only `{ mode: 'customer' }`; discard guard reads `isDirtyRef` (146-185); pickedAddress read-once effect (133-139).
- `src/features/customers/requestMapping.ts` — pure payload mapping (its stated purpose). `toCreateCustomerRequest` merges `street + ', ' + area` → `address` (23-48). Add the edit-side pure functions here: seed mapper + `buildCustomerUpdatePatch`.
- `src/features/customers/useCreateCustomer.ts` — POST chain: submitting/submit-error state, in-flight back guard (60-73), reset-epoch guard (84-91), error copy map (26-40), post-success `upsertCustomer` + `loadCustomers({force:true})` + popTo/goBack (97-119). Extend with an update branch.
- `src/features/customers/useCustomers.ts` — store: `upsertCustomer` (replaces by id), `loadCustomers({ force: true })` — imported directly, already used by the create path.
- `src/services/resources/customers.ts` — `customerService = { create, list, listAll, getById }` (215-220); `CustomerDetail` (133-157) lacks `pincode/latitude/longitude/placeId` — extend optional. `apiClient.patch` exists (used by `holidays.ts:67`).
- `src/navigation/types.ts` — `AddCustomer` params (149-152): add optional `customerId?: string` (present = edit; params all-optional by merge-return convention). `AddCustomerReturnRouteName` (273) unchanged — edit post-save is plain `goBack()` (same branch as `'Customers'`).
- `src/features/customerDetail/CustomerDetailScreen.tsx` — header row (280-292: back + title, room on the right); identity Card (225-254); refetches on focus (147-151) so returning from edit auto-refreshes. Add header-right Edit affordance.
- `src/features/attendance/offices/OfficeFormScreen.tsx` — COPY PRECEDENT, do not modify: `officeId` param = edit; load-and-seed effect with 404 view (73-96); copy switches (210, 260); diff `buildUpdatePatch` + empty-patch skip (120-133); `initialLatitude` prefill (243).
- `src/features/mapPinPicker/MapPinPickerScreen.tsx` — reads `initialLatitude/initialLongitude/radiusM/mode` (76-85); skips Android GPS auto-center when initial coords present (151). No changes.
- `src/components/ui/Input.tsx` — forwards `editable` (40, 62, 103) — phone read-only is `editable={false}` + `disabled` styling; no component changes.
- Tests (must stay green, not extended this session): `src/features/customers/AddCustomerScreen.test.tsx` (~25 add-flow cases), `CustomersScreen.test.tsx`.

## Tasks & Acceptance

**Execution:**
- [ ] `src/services/resources/customers.ts` — add `UpdateCustomerRequest` (all keys optional; text/coord keys accept `null` for explicit clear) + `update(id, patch)` → `apiClient.patch<CreatedCustomer>('/customers/${id}', patch)`; extend `CustomerDetail` with optional `pincode/latitude/longitude/placeId`; refresh the file doc (update now exists; ApiService promotion still waits for delete).
- [ ] `src/navigation/types.ts` — add `customerId?: string` to `AddCustomer` params with a doc comment (presence = edit mode; NewJob merge-returns never carry it).
- [ ] `src/features/customers/requestMapping.ts` — add pure `toCustomerFormSeed(detail)` (form values + reconstructed `PickedAddressSnapshot` when coordinates exist + previewLine) and `buildCustomerUpdatePatch(current, baseline)` implementing the frozen diff rules.
- [ ] `src/features/customers/useCreateCustomer.ts` — accept `customerId?: string`; branch `handleSubmit` to `update()` when present (payload typed as the update patch); edit-specific error copy (404 "no longer available", 403 owner-only, 422 details, 400 company setup — 409/duplicate copy stays add-only); same reset-epoch guard, back guard, `upsertCustomer` + `loadCustomers({force:true})`, plain `goBack()` (edit is never pushed from NewJob).
- [ ] `src/features/customers/AddCustomerScreen.tsx` — edit mode: load-and-seed via `getById` with loading/404/error views (OfficeFormScreen precedent); copy switches ("Edit customer"/"Save changes"); phone `editable={false}`; `isDirty` and `hasLocation` computed against the seeded baseline in edit; `buildRequest` branches to the patch builder; MapPinPicker navigation passes `initialLatitude/initialLongitude` from the CURRENT snapshot when present; submit → create vs patch.
- [ ] `src/features/customerDetail/CustomerDetailScreen.tsx` — header-right Edit affordance (Pencil IconButton, accessibility label "Edit customer") → `navigate('AddCustomer', { customerId })`.

**Acceptance Criteria:**
- Given an owner on a customer detail, when they tap Edit, the form opens seeded with the server's values and the phone field is not editable.
- Given edited fields, when they save, exactly one PATCH carrying only the diff is sent, and the detail screen on return shows the edited values.
- Given an untouched form, when they save, no request fires and the screen pops.
- Given a customer with completed jobs, when edited and saved, the job records are untouched (BE guarantee) and the app surfaces the edit on the next reads (store upsert + detail refetch).
- Given the add flow (no `customerId`), when the existing suite runs, every add-flow test passes unchanged.

## Implementation Notes

- FEATURE COMPLETE (2026-10-17, user-confirmed): device pass done (seed, read-only phone, untouched-save no-op, rename round-trip + revert, discard copy, add-flow unchanged); CAP-3 live e2e on the production stack — throwaway customer + real job driven through the full 6-step workflow (incl. a real photo via presign/confirm), MD5 of the entire `jobs` row byte-identical across the customer edit (updated_at untouched), only the live-joined customer fields + the by-design fresh presigned URL differed; phone showed the completed job's original service location with the edited customer card; throwaway rows deleted and verified zero. fenzit-app `63e6ce1`, fenzit-be `7b7eefb` (endpoint) + `ee986ce` (tests).
- The edit-mode test pass remains the one open follow-up, tracked in deferred-work.md.

- Repo rule: no new tests this session — edit-mode coverage is deferred to immediately after the user confirms the flow on device (same pattern as the BE plan; log in deferred-work.md at present time).

## Plan Change Log
## Plan Change Log

- 2026-10-17 (post-build, test-pass review F2 — no loopback, recorded for coherence): review triage row BH2 patched the edit save to SKIP `upsertCustomer` (the PATCH response carries no jobCount/lastJobDate; upserting zeroed the row's stats and reordered the list). The frozen AC's tail ("the app surfaces the edit on the next reads (store upsert + detail refetch)") names the superseded mechanism — the functional outcome (edit visible on next reads) is unchanged and is delivered by `loadCustomers({ force: true })` (list) + CustomerDetail's on-focus refetch (detail), now pinned by the edit-mode tests. Known-bad state avoided: reverting to the frozen mechanism would corrupt list rows. KEEP: the skip-upsert edit branch and both refetch paths must survive any re-derivation.

## Review Triage Log

- Review pass 1 (thorough: blind-hunter, edge-case-hunter, verification-gap, intent-alignment; 2026-10-17): verdicts — high 1, medium 2, low 8 (2 rejected as unreachable, tests-out-of-scope rejected on the frozen Never). All surviving entries route to patch (loopback 1; no intent_gap/bad_plan — the frozen block already settled the big one). Rows:
  - [BH1+ECH1/8/11+VG+IA] **high → patch**: the frozen "empty diff → no network call, plain back" rule exists only as prose — `onSubmit` has no emptiness gate and `canSubmit` no dirty term, so an untouched seeded form PATCHes `{}` → BE 400 "Nothing to update" → company-setup error copy on the most common edit action (open, glance, Save). Four lenses converged independently; verified against the diff and BE service. Fix: OfficeFormScreen's exact gate.
  - [BH2+ECH2] **medium → patch**: edit save rides `upsertCustomer`, which replaces the store row and defaults jobCount 0 / lastJobDate null and reorders the list — corrupt-until-refresh, permanent if the force refresh fails (its catch swallows). Fix: edit branch skips upsert (force refresh + focus refetch cover visibility; stale-but-real beats fake-correct).
  - [ECH4] **medium → patch**: `canSubmit` keeps the create-flow location requirement in edit — a customer with no saved location (job-created rows) can never save an unrelated name fix. Fix: drop the hasLocation term when the seeded baseline itself had none.
  - [BH7+ECH5] **low → patch**: seeded phone must not be re-validated against PHONE_LENGTH (immutable field; legacy short rows would dead-end Save with no hint).
  - [ECH3] **low → patch**: seed-load 403 renders "check your connection" — group with 404 as notFound, mirroring CustomerDetailScreen's own 404||403 grouping.
  - [ECH6] **low → patch**: baseline built from untrimmed server values while the builder trims current — pre-trim-transform legacy rows would count untouched forms as dirty. Fix: trim the four baseline strings.
  - [BH8] **low → patch**: header Edit renders on the notFound detail view (tap = guaranteed second 404). Fix: hide it there.
  - [BH11] **low → patch**: discard-dialog copy is add-flavored ("details you entered"); edit speaks of changes.
  - [BH6+ECH9] **low → patch**: load-error copy says "try again" with no retry control — reword to "go back and try again" (re-entry is the retry).
  - [BH10] **low → patch**: read-only phone shows no UI explanation — Input's `helper` prop, one line.
  - [BH5+IA] **low → patch (comment)**: onSubmit comment calls the null-baseline guard "the office form's fail-loud branch" but returns silently — reword to what it is (unreachable-in-practice belt).
  - [ECH7] **low → reject**: one-sided seeded coordinates drop the pin in the seed — unreachable through the app (the only writer is the FE, which always sends the pair), and the fix adds branches for an impossible state.
  - [ECH9-param] **low → reject**: `customerId: ''` classifying as add mode — no caller or deep link can produce an empty-string param; fix adds a guard for an impossible state.
  - [BH3/BH4/VG1-4/IA-test-surface] **out of scope → reject**: zero edit-mode tests is the frozen Never (tests after on-device confirmation); the defer is already logged in deferred-work.md.
  - [BH12] **low → reject**: hook naming / duplicated error-map skeleton — rename churn across import sites is more than a direct correction; taste.
  - Review pass 2 (quick, 2026-10-17 — the deferred edit-mode test pass, 5 findings, all patch): [T1] the "phone keys structurally absent" service test inspected a runtime literal (types erased) and pinned nothing — deleted; header corrected (phone immutability is compile-time + screen-pinned). [T2] frozen AC's "store upsert" mechanism superseded by the BH2 skip-upsert patch — Plan Change Log entry records the deviation. [T3] BH7 short-phone carve-out unpinned — test added. [T4] ECH3 403-seed grouping + the error-copy map (403/422/400/fallback) + spinner view unpinned — tests added. [T5] focus-refetch return path unpinned — customer-detail test captures useFocusEffect and pins the second fetch.
  Test pass: 44 new tests across 4 files; suite 3077/3077; typecheck clean. (fenzit-app 098aa55)

## Design Notes

**Seed/diff mapping (the non-obvious part).** The BE stores one merged `address` line (`street, area` at create), so seeding puts the whole stored line back into Street and leaves Area empty — un-merging is lossy; a doc comment on the seed mapper records this. `buildCustomerUpdatePatch` compares against the seeded baseline object, not per-keystroke state:

```
// current = live form state; baseline = seed snapshot
if (mergedAddress(current) !== (baseline.address ?? '')) patch.address = mergedAddress(current) || null;
if (city changed)  patch.city  = current.city  || null;
if (details changed) patch.addressDetails = current.details || null;  // explicit-null clear
if (current.snapshot !== baseline.snapshot) {           // a new pick happened
  if (current.snapshot) { block keys from pick, absent → null }
  else if (baseline.hadBlock) { all five block keys null }
}
```

`baseline.snapshot` is the reconstructed seed snapshot object (stable ref); "no new pick" is reference equality. Name diffs as a plain string (never null).

## Verification

**Commands:**
- `bun run typecheck` (fenzit-app) -- expected: no errors
- `bun jest src/features/customers src/features/customerDetail` -- expected: all existing suites green, zero edits to test files
- `bun jest` -- expected: full unit suite green

**Manual checks (on the attached phone, owner session):**
- Edit Peter's customer from detail: rename + re-pin + clear Flat, save; detail shows edits; Customers list updated.
- Reopen edit, save untouched → no PATCH in logs, straight back.
- Add-customer flow from Customers header still works end to end.
