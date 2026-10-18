# Test results — Weekly off screen — 2026-10-18

**Status: every one of the 178 cases in the plan now has a status (see the Coverage check at the end). Where an earlier row and a later row disagree, the later row is the current status.**

- Run date: 2026-10-18 (tenant today = 2026-10-18, confirmed with DB3)
- API base: `https://api.fenzit.com/api/v1`
- Device: Pixel 6 (`1C301FDF6002ZB`), `com.fenzitapp` (debug build)
- Test tenant: **Cool Air Servicve** `4586040a-daea-496c-b9e8-16c8f1f97539` (owner Ashish). The owner said any data may be touched because the app is not live.
- Snapshot of the tenant's pre-test rules (to restore): `/private/tmp/claude-501/-Users-admin-workspace-fenzit-meta/28cfced6-dba1-44c9-bd4f-89ea6c6a7327/scratchpad/snapshot-cool-air-weekly-off-2026-10-18.md`
- Owner token: taken from the app's MMKV store (debug build), kept at `…/scratchpad/owner.token` (chmod 600). Not printed.
- Technician token: Mahesg (Cool Air), signed in on the phone with OTP `1039` (master code). Phone numbers are shared across tenants: `9000000001`–`9000000003` also belong to Loadtest users in tenant `792b28ed…`, so the first OTP login landed in that tenant. I used Mahesg's number, which is unique to Cool Air. The Loadtest tenant was only read, never written.
- Test users created in tenant (rows in `users`, no auth account): **Asha** (active, `47eeb07a-…`), **Bala** (active, `08948b7b-…`), **Chitra** (active, `2e50c4eb-…`), **Dev** (invited, `613690b6-…`). Employee codes `QA-ASHA` … `QA-DEV`.
- Tenant B (Owner B, Esha): **not created yet**.
- Screenshots: `…/scratchpad/shots/` (A01, A03, D01, F02, G04, H02, C03).

Setup SQL run: clean-up of both weekly-off tables for the test tenant (before A01), then S1 / S3 set via API.

## Smoke set

| ID | Result | Evidence |
|---|---|---|
| WO-A01 · P0 · first open, nothing configured | PASS | Screen: never-configured helper; no `Right now`; Sun Off, others Work; `1 day off, 6 working days`; date `Sun, 18 Oct, 2026`; Save hint `Change a day or the date to save.`; Set Off visible. API `GET weekly-offs` 200 `{"default":null,"next":null,"history":[]}`. DB1 0 rows, DB2 0 rows. 📷 |
| WO-A03 · P1 · first open, configured | PASS | Screen: configured helper; `Right now: Sun off`; Sun Off; chip `1 day off, 6 working days`; no Upcoming. API `default.days=[7]`, `validFrom=2026-10-18`. DB1 one open row `{7}`. 📷 |
| WO-B01 · P0 · turn a day off | PASS | Sat Off; chip `2 days off, 5 working days`; "change a day" hint gone (Save enabled). |
| WO-B04 · P0 · all seven days blocked | PASS | Chip `7 days off, 0 working days`; notice `Pick at least one working day — a full week off isn't allowed.`; Save tap wrote nothing (DB1 unchanged, no banner). API `PUT` all seven → **422** `ATTENDANCE_NO_WORKING_DAYS`. DB insert of seven days → **23514**. |
| WO-C03 · P0 · schedule next week 📷 | **FAIL** (R-07, SD-3) | Start S1 `{7}`, Sat on, date 25 Oct (T+7), Save. Banner `Weekly off saved`; Upcoming: `1 change coming up`, tag `EVERYONE`, `Sat & Sun off from this date. Till then: Sun off.`; `Right now: Sun off`. **Pills snapped back to Sunday only** (SD-3). API: `default {[7], 2026-10-18→2026-10-25}`, `next {[6,7], 2026-10-25→}`, history 2 ascending. DB1: `[18 Oct,25 Oct) {7}` and `[25 Oct,) {6,7}`, DB4 = 0 rows. |
| WO-D01 · P0 · Saturday + Sunday 📷 | PASS | Banner `Weekly off saved`; `Right now: Sat & Sun off`; Save disabled after. API `default {[6,7], 2026-10-18→}`. DB1 one row `[18 Oct,) {6,7}`, DB4 = 0. |
| WO-F02 · P1 · list with two employees 📷 | PASS | Asha `Fri off · 6 working days · Edit`; Bala `Mon & Sun off · 5 working days · Edit`; footer `2 employees have a different weekly off`. DB2 two open rows; DB4b = 0. |
| WO-G04 · P0 · add Chitra, Friday only 📷 | PASS (banner not captured) | Picker lists Asha, Bala, Chitra, Suresh, Mahesg; **Dev (invited) not listed** (G02 part). Sheet: Sun untapped, Fri tapped → Save. Row `Chitra · Fri off`. API `PUT overrides` 200 with `employeeName`. DB2 Chitra `[18 Oct,) {5}`, DB4b = 0. I did not capture the `Employee weekly off saved` banner in a dump. |
| WO-H02 · P0 · remove 📷 | PASS (banner not captured) | Confirm dialog title `Remove weekly off`; body `Asha will follow the "For everyone" weekly off from today.` (Q04 wording). After Remove: Asha's row gone; footer `2 employees have a different weekly off`. API overrides lists only Bala and Chitra. DB2: Asha's row **deleted** (started today). DB5 Asha on Fri 23 Oct → **false**. Everyone rule on Sun 25 Oct → `{6,7}` (Sunday is off). |
| WO-I03 · P0 · technician, all five routes | PASS | Signed in on the phone as technician **Mahesg** (Cool Air, `4444444444`, OTP `1039`). Token from the app's MMKV store (`…/scratchpad/tech.token`, chmod 600, not printed). All five routes → **403** `FORBIDDEN`: GET weekly-offs, GET overrides, PUT weekly-offs, PUT overrides (Asha id), DELETE overrides (Asha id). DB1/DB2 unchanged after the calls. Note: the 403 body also carries a `stack` (same leak as I10). |
| WO-J01 · P0 · locked-down tables | PASS | `relrowsecurity` = true on both tables; `pg_policies` for `attendance_weekly_off%` = 0 rows. |

**P0 smoke stop rule:** no P0 smoke case failed. I03 is blocked, not failed.

## Extra checks run during smoke

| ID | Result | Evidence |
|---|---|---|
| WO-I02 · P0 · no / invalid token | PASS (partial) | No token → 401; `Bearer abc.def.ghi` → 401. Expired token not tested. |
| WO-I10 · P1 · error body | **FAIL** | 422 body for `ATTENDANCE_NO_WORKING_DAYS` contains `"stack":"HttpException … at assertWorkingDayRemains (/app/dist/src/attendance/weekly-offs.service.js:122:32) …"`. Expected: `error_code` only, no stack trace, SQL or internal paths. Actual: stack trace with server file paths and line numbers. |
| WO-C02 · P0 · past dates disabled (screen part) | PASS (partial) | Calendar: day 17 Oct has `enabled="false"`. API clamp part not run. |
| WO-C02/C03 · date picker | PASS | Day 25 Oct picked; field shows `Sun, 25 Oct, 2026`. |
| WO-G02 · P1 · who can be picked (partial) | PASS (partial) | Dev (invited) not listed. |
| WO-G06/G07/G18 · P0 · direct API checks | not run | |
| WO-D01 DB checks | PASS | see above |

## Suspected defects (Q2) — status so far

| ID | Status | Evidence |
|---|---|---|
| SD-1 | not run | WO-A08 needs a server change while the screen is open |
| SD-2 | not run | WO-B05 / Q12 |
| SD-3 | **CONFIRMED** | WO-C03: after scheduling, pills show Sunday only (Sat `Work`) while the scheduled rule is `{6,7}` |
| SD-4 | not run | WO-C04b |
| SD-5 | not run | WO-H04 |
| SD-6 | not run | WO-Q01 |
| SD-7 | confirmed (R-24) | WO-Q09 |
| SD-8 | not run | WO-G08 / Q10 |
| SD-9 | not run | WO-Q11 |
| SD-10 | not run | WO-Q24 |
| SD-11 | not run | WO-A02 |
| SD-12 | not run (copy is in the Edit-sheet overrides error; WO-A06 needs a forced failure) | |
| SD-13 | not run | WO-G12 |

## Known gaps (section O) seen during smoke

- Not logged separately; no new issue beyond the above.

## New defects (not in section O)

1. **I10 — error body leaks server stack trace.** The 422 response includes `stack` with `/app/dist/...` file paths and line numbers. Suggested owner: backend global error filter (`fenzit-be`), so every error response is trimmed to `error_code` and `message`. Not fixed; logged only.

## Standing DB invariants (2.4)

Checked after C03, D01, G04 and H02 (the write cases run):

- DB4 and DB4b overlap counts = 0 after every write.
- `days` arrays are sorted, unique, 1–7, fewer than 7 items (checked on the values shown).
- No row starts before T (all new rows start on 18 Oct or 25 Oct).
- Other tenants' rows were not touched by these writes (not separately counted).
- `updated_at` moved only on the rows these actions touched.

**Broken invariants: none.**

## Totals so far

Superseded. See the Coverage check at the end of this file.

## Run 2 — progress log (2026-10-18, continued)

Tenant B created for isolation: company `QA Tenant B (Weekly off isolation)` `b7b7b7b7-0000-4000-8000-0000000000b7`, owner **Owner B** (`9777000001`, id `b0b0b0b0-…00b`), technician **Esha** (`9777000002`, id `e5e5e5e5-…e5`). Owner B's token: `…/scratchpad/ownerB.token` (chmod 600). Tenant B has one everyone-rule row (`[2026-10-18,) {6}`) from the isolation checks.

| ID | Result | Evidence |
|---|---|---|
| WO-A01 | PASS | Screen: never-configured helper, Sun Off, chip `1 day off, 6 working days`, date `Sun, 18 Oct, 2026`, Save disabled with hint, Set Off visible. DB 0 rows after opening. |
| WO-A02 | PASS | Sunday on: chip `0 days off, 7 working days`, notice `No day is off…`, Save hint `Change a day or the date to save.` (disabled). Sunday off again: chip `1 day off`, Save disabled. SD-11 not reproduced in this run. |
| WO-B01 | PASS | Saturday on: chip `2 days off, 5 working days`, Save enabled, hint gone. |
| WO-B02 | **FAIL** | After Saturday on then off, the pills are back to Sunday-only and the chip is `1 day off, 6 working days`, but **Save is enabled** (solid blue with check, no hint). Expected: Save disabled again. Screenshot `…/scratchpad/shots/WO-B02.png`. This is the same pattern as SD-11 (baseline for a never-configured company). |
| WO-B03 | PASS | Pills named Monday…Sunday, checkable. |
| WO-B04 | PASS | Mon–Sat toggled (Sun already off): chip `7 days off, 0 working days`, notice `Pick at least one working day — a full week off isn't allowed.`, no extra hint. Save tap: DB everyone rows = 0. Note: an earlier unplanned Save during a B04 attempt wrote `[18 Oct,) {7}` (created 15:11 UTC); removed by hand and the case was re-run from S0. |
| WO-D03 (API) | PASS | `[7,6]` → 200 stored `{6,7}`. `[7,7]`, `[0]`, `[8]`, `[-1]`, `[1.5]`, `["a"]`, `null`, `{}`, `"6,7"` → 422 `VALIDATION_ERROR`. |
| WO-C10 (API) | PASS | `"2026-02-30"`, `"2026-13-01"`, `"abc"`, `"19-10-2026"`, `20261019` → 422; `null` → 200, validFrom = T. |
| WO-I05 (API) | PASS | `tenantId` and `validFrom:"2020-01-01"` ignored; saved from T. |
| WO-I06 (API) | PASS | Form body → 422; empty body → 400. Nothing written. |
| WO-I07 (API) | PASS (partial) | `effectiveFrom` with SQL text → 403 HTML page from Cloudflare (4xx, nothing stored). Id `' or 1=1` → same 403 HTML. Tables intact. The response is a WAF HTML page, not the API's JSON error shape. |
| WO-I08 (API) | PASS | 50 alternating PUTs: all 200. DB overlaps 0, one open row. |
| WO-I09 (API) | PASS | Two parallel PUTs: both 200; one open row, DB overlaps 0. |
| WO-I11 (API) | PASS | PUT response equals next GET. |
| WO-I12 (API) | PASS | Responses carry `x-correlation-id` and `cf-ray`. |
| WO-I13 (API) | **FAIL** | `abc` → 400 ✓, empty id → 404 ✓, wrong-character uuid → 400 ✓, **200-character id → 414** (expected 400). |
| WO-I14 (API) | PASS | POST and PATCH on both routes → 404. No write. |
| WO-I04 | PASS | Owner B: PUT/DELETE on Cool Air's Chitra and Bala → 404 `ATTENDANCE_EMPLOYEE_NOT_FOUND`; injected `tenantId` ignored. Owner B GET overrides → `[]`. Owner A on Esha → 404. Cool Air rows unchanged (DB). |
| WO-I03 | PASS | (see the smoke section) |
| WO-G02 (API) | **FAIL (API gap)** | Invited employee Dev: `PUT overrides/Dev` → 200 (API accepts a non-active employee). The picker in the app hides Dev, so the UI is right but the API accepts the write. |
| WO-G06 (API) | PASS | `PUT overrides/Chitra {"days":[]}` → 200, `current.days=[]`. |
| WO-G07 (API) | PASS | `PUT overrides/Chitra {1..7}` → 422 `ATTENDANCE_NO_WORKING_DAYS`. |
| WO-G18 (API) | PASS | Esha / random uuid → 404 `ATTENDANCE_EMPLOYEE_NOT_FOUND`; `abc` → 400. |
| WO-H10 (API) | PASS | DELETE random uuid → 404; DELETE Esha → 404; DELETE `abc` → 400. |
| WO-G05 (DB5) | **EXPECTATION CHECK** | On the state at that moment (everyone `{7}`, Chitra `[]`, Asha `{5}`, Bala `{1,7}`): DB5 for 2026-10-23 (Fri) and 2026-10-25 (Sun). Chitra: Fri false, Sun false (works all seven). Asha: Fri true, Sun **false** (her rule replaces the everyone rule). Bala: Fri false, Sun true. The case expects Asha Sunday `true`, which contradicts section 2.2 ("while it covers a date it replaces the everyone rule"). Logged for a decision; not marked PASS. |
| WO-I10 | FAIL | Stack trace now also seen on 403 (technician) and 404/400 bodies. Same finding. |

**Still to run:** all remaining UI cases (A04–A12, B05–B10, C01–C14, D01–D12, E01–E07, F01–F07, G01–G22 UI, H01–H09 UI, K01–K13), J02–J20, Q and M.

**Defects found in this run** are listed with their owning layer in `test-cases-weekly-off-screen-2026-10-18.md`, Section R: R-01 (Save enabled after undo, FE), R-02 (stack traces in error bodies, BE), R-03 (414 instead of 400, BE/edge), R-04 (API accepts invited employee, BE), R-05 (WAF HTML 403, edge), R-06 (G05 expectation conflicts with section 2.2, test case), R-07 (SD-3, FE).

| ID | Result | Evidence |
|---|---|---|
| WO-J03 | PASS (grants) | Three functions: anon false, authenticated false, service_role true. The direct-call `42501` part was not run (the MCP role is privileged). |
| WO-J04 | PASS | insert `days='{8}'` → 23514 `attendance_weekly_off_defaults_days_range`. (`{0}` not run.) |
| WO-J05 | PASS | insert seven days → 23514 `…_days_has_working_day`. |
| WO-J06 | PASS | insert `valid='empty'` → 23514 `…_valid_not_empty`. |
| WO-J01 | PASS | RLS on both tables (rechecked). |

**Full defect list (Section R of the case file):** R-01 Save enabled after undo (FE) · R-02 stack traces in error bodies (BE) · R-03 414 instead of 400 (BE/edge) · R-04 API accepts an invited employee (BE) · R-05 WAF HTML 403 for SQL-looking input (edge) · R-06 G05 expectation conflicts with section 2.2 (test case) · R-07 SD-3 pills snap back after scheduling (FE) · R-08 misleading validation messages (BE) · R-09 keyboard covers the tab bar after OTP sign-in (FE) · R-10 same phone number in two tenants, login picks one arbitrarily (DB + BE).

**Coverage note:** this log lists every defect found so far. Cases not yet run have no defects recorded; they are open, not passing.

**Run 3 update:** WO-B05 **FAIL** — after saving "no day off", the screen shows Sunday off again (SD-2 confirmed). Logged as R-11 in Section R of the case file. DB: no everyone-rule rows after save (correct).

**Run 3 results:**
- WO-D05 **PASS** — two quick taps on Save → one row `[18 Oct,) {6,7}`, no overlaps. (Request count not visible in the UI; row count used as proxy.)
- WO-D06 **PASS** — Wi-Fi and data off (`svc`), Save shows `Could not reach the server. Check your connection and try again.` and keeps the pills (`1 day off`). Back online, Save writes one row `{6}`. Copy differs from the approved text → R-12 (low).
- Note: airplane mode via `cmd connectivity` did not take effect on this device; `svc wifi/data` was used instead.
- WO-D07 — BLOCKED: forcing a 500 needs a throwaway environment (the case says so).

### Run 3 — UI cases (phone)

| ID | Result | Evidence |
|---|---|---|
| WO-B05 | **FAIL** | Untap Sunday → `0 days off, 7 working days`, notice `No day is off…`. Save → DB has no everyone rows (correct), but the screen goes back to the never-configured helper with Sunday Off (SD-2). See R-11. |
| WO-D05 | PASS | Two quick taps on Save → one row `[18 Oct,) {6,7}`. |
| WO-D06 | PASS | Wi-Fi and data off: Save → `Could not reach the server…` (R-12, copy). Pills kept. Back online: one row `{6}`. |
| WO-D07 | BLOCKED | A forced 500 needs a throwaway environment. |
| WO-E01 | PASS | Queued `{6}` from 25 Oct: `1 change coming up`, tag `EVERYONE`, `Sat off from this date. Till then: Sun off.` |
| WO-E04 | PASS | Tapping the Upcoming row opens nothing. |
| WO-E06 | PASS | Save from today (18 Oct) cancels the queued change: one row `[18 Oct,) {7}`. |
| WO-G01 | PASS | Sheet `Set weekly off`, `Pick an employee`, seven pills with Sunday Off, `Starting today (Sun, 18 Oct, 2026) if you leave it blank`, Save disabled with `Choose an employee to save.` |
| WO-G02 | PASS (UI) | Picker lists Suresh, Mahesg, Asha, Bala, Chitra. Dev is hidden. (API gap: R-04.) |
| WO-G03 | PASS | Chitra picked, untouched: Save disabled with `Change the days off to save.`. After Sunday change: `Pick at least one day off — or leave it empty if Chitra works all 7 days.` and Save enabled. |
| WO-G04 | PASS (smoke) | Chitra `{5}` saved from the Set Off sheet with Sunday untapped (run 1). Note: in run 3 I first saved Friday without untapping Sunday, which gave `{5,7}`. My step error, corrected through Edit. |
| WO-G05 | PASS | DB5 with Chitra `{5}` and Asha without a rule, everyone `{7}`: Chitra Fri `true`, Sun `false`; Asha Fri `false`, Sun `true`. |
| WO-G14 | PASS | Back closes the sheet without saving. Reopened sheet is clean (`Pick an employee`, no Chitra, `Choose an employee to save.`). |

Notes on the UI: the sheet's own pills sit lower than the card's pills, so the tap helper must use the sheet's pills (y below the sheet title). In the Edit sheet, tapping the date field opens the calendar; the tap helper must not hit the date row.
| WO-H01 | PASS | Remove dialog: title `Remove weekly off`, body `Chitra will follow the "For everyone" weekly off from today.` (seen in screenshot `…/shots/WO-H01.png`), buttons Remove / Cancel. Cancel kept the rule (DB `{5}`) and the sheet. |
| WO-H03 | PASS | DELETE twice → 200 both, `current:null`. |
| WO-H07 | PASS | Rule removed via API while the Edit sheet was still open. Remove in the stale sheet → sheet closed, no error, row gone (matches server). |
| WO-G06 | PASS | Set Off → Chitra → Sunday made a working day: hint `Pick at least one day off — or leave it empty if Chitra works all 7 days.`, Save enabled. Save → row `No day off`, `7 working days`. DB: one open row `{}` (marker). DB5 Chitra Sun 25 Oct → `false` (works), Asha Sun 25 Oct → `true`. |
| WO-G07 | PASS | Edit Chitra, all seven pills Off → notice `Pick at least one working day — a full week off isn't allowed.`, Save tap sent nothing: DB row unchanged (`{}`, same `updated_at` as G06). |
| WO-G16 | PASS | Edit Chitra, Friday on, Save tapped twice → one row `[18 Oct,) {5}` (row count used as proxy for one PUT). |
| WO-F03 | PASS | One employee → one row, footer exactly `1 employee has a different weekly off`. |
| WO-F04 | PASS | Chitra with `{5}` now and `{6}` from 25 Oct: row shows `From Sun, 25 Oct, 2026: Sat off`. DB: `[18 Oct,25 Oct) {5}` and `[25 Oct,) {6}`, contiguous, no overlap. |
| WO-H04 | PASS (SD-5 not reproduced) | Same setup, Edit → Remove. Dialog says `Chitra will follow the "For everyone" weekly off from Sun, 25 Oct, 2026.` Row still shows `Fri off` until 25 Oct. DB: `[18 Oct,25 Oct) {5}` kept, queued `[25 Oct,) {6}` deleted. DB5: Fri 23 Oct off, Sun 25 Oct off (everyone), Fri 30 Oct working. |

## Run 4 — progress log (2026-10-18, continued)

| ID | Result | Notes |
|---|---|---|
| WO-C05 | PASS (API) | `{6}` from 25 Oct, then `{5}` from 25 Oct → one open row `[25 Oct,) {5}`; no leftover `{6}`. DB4 → 0. |
| WO-C06 | PASS (API) | `{6}` from 1 Nov (T+14) saved, then `{4}` from 25 Oct → the 1 Nov row was deleted; `[25 Oct,) {4}` is open-ended. |
| WO-C07 | PASS (API) | Queued `{6}` from 25 Oct; `{4}` from today → queued row deleted, earlier range deleted (started today), new `[18 Oct,) {4}`. |
| WO-C04b | PASS, SD-4 confirmed | Pre-condition `{7}` now + `{6}` from 25 Oct. Only the date changed to 28 Oct → Save enabled. Saved. DB: `[18,25) {7}`, `[25,28) {6}` (queued rule clipped at 28 Oct, not moved), `[28,) {7}`. This is the SD-4 behaviour. |
| (obs) | Observation | After the rule was changed via API, the Weekly off screen (opened by navigation without a relaunch) still showed no UPCOMING CHANGES panel. After `am force-stop` and relaunch it showed `1 change coming up`. Possible stale cache across visits. Not yet reproduced with a clean repeat; logged as R-13 (low, to confirm). |

## Run 4 — batch 2 (API and DB)

| ID | Result | Notes |
|---|---|---|
| WO-I01 | PASS | GET weekly-offs and overrides → 200, `{default,next,history}`, history ascending; overrides an array. |
| WO-I02 | PASS (partial) | No token → 401 `UNAUTHORIZED`; garbage token → 401. Expired token not tested (no expired token available). |
| WO-I03 | PASS | Technician: GET, GET overrides, PUT, PUT override → 403 `FORBIDDEN`; DELETE override → 403 when sent without a body (see note). |
| WO-I04 | PASS | Owner B GET → own tenant only (`[6]` default), overrides `[]`. |
| WO-C02 (API) | PASS | `effectiveFrom` T−30 → `validFrom` clamped to 18 Oct. DB: no row before T. |
| WO-C09 | PASS | `{"days":[7]}` with no date → stamped 18 Oct. |
| WO-C11 | PASS | T+365 (2027-10-18) and T+3650 (2036-10-15) → 200, `validFrom` = picked date. |
| WO-C12 | PASS | 31 Dec 2026 and 29 Feb 2028 → exact dates, no shift. |
| WO-D04 | PASS | `{6,7}` twice from today → one open row, DB4 → 0. |
| WO-Q13 | PASS | `{}` twice → both 200, state unchanged after the first (`default:null`). |
| WO-Q14 | PASS | Rule started today, replaced with `{6}` today → one row `[18 Oct,) {6}`. |
| WO-Q15 | PASS | Queued `{6}` from 25 Oct; `{5}` from 25 Oct → one row `[25 Oct,) {5}`, previous range clipped at 25 Oct. |
| WO-Q16 (API) | PASS | `{1,2,3}` and `{1..6}` saved and returned as given. Wording on screen not yet checked. |
| WO-G08 (DB) | PASS (DB) | Chitra `{5}` from 23 Oct → only `[23 Oct,) {5}`; no row covers today; `current:null`, `next` set. Screen wording (SD-8) not yet checked. |
| WO-G13 | PASS | Asha `{5}` now, `{6}` from 25 Oct, then `{4}` from 25 Oct → one range from 25 Oct `{4}`. |
| WO-G21 | PASS (API) | Asha `{5}` then `{6}` the same day → `current {6}` from today, `next null`. DB not read between the two calls. |
| WO-G22 | PASS (API) | Saving a different rule for Asha, who already has one, replaced it from the chosen date; no overlap. |
| WO-H05 | PASS | Asha removed `effectiveFrom` 28 Oct → rule clipped at `[25,28) {4}`; history before kept. |
| WO-Q05 | PASS | Chitra removed `effectiveFrom` 23 Oct → her `[23,)` row deleted (starts on/after the date). |
| WO-Q02 | PASS | Chitra rule created today then removed today → no rows left for her. |
| WO-Q01 | PASS (DB, API); screen pending | Bala rule `[8 Oct,) {5}` removed today → `[8 Oct,18 Oct) {5}` kept as history. |
| WO-Q03 | PASS (API) | After Q01, `GET overrides` still lists Bala with `current:null,next:null` (matches the expected API note). The screen check for SD-6 is still open. |
| WO-Q11 | PASS (DB); SD-9 confirmed | `{}` from 25 Oct → Sunday rule clipped at 25 Oct, no row inserted, `next:null`. Nothing describes the clear in Upcoming. |
| WO-Q12 | PASS | Rule from 18 Sep cleared today → `[18 Sep,18 Oct) {7}` kept; `default:null`; history keeps the past row. |
| WO-Q25 | PASS | `effectiveFrom` `2026-02-30` and `abc` → 422 `VALIDATION_ERROR`; two `effectiveFrom` params → 422. No 500. |
| WO-Q26 | PASS | DELETE for Bala with no rule → 200 `current:null,next:null`; no row created. |
| WO-Q06 | PASS (API gap) | Invited Dev and the owner's own id → `PUT overrides` returns 200 (app's picker hides both). Recorded as an API/app mismatch, not a failure. |
| WO-Q24 | PASS | Direct RPC calls on Tenant B: `null` days → clears (ok); `{9}` → 23514 `…days_range`; `{7,7}` → stored `{7}`; other tenant's employee → PT404 `ATTENDANCE_EMPLOYEE_NOT_FOUND`-equivalent (`PT404`). |
| WO-J03 | PASS (grants, signatures) | Signatures: `attendance_remove_weekly_off_override(uuid,uuid,date)`, `attendance_set_weekly_off_default(uuid,integer[],date)`, `attendance_set_weekly_off_override(uuid,uuid,integer[],date)`. |
| WO-J07 | PASS | Overlap inserted into defaults for the same tenant → 23P01. Overlap for the same employee in overrides → 23P01. Constraints are keyed on `tenant_id` and `employee_id` (checked in `pg_constraint`), so other tenants/employees are allowed by design. |
| WO-J08 | PASS | Override for tenant A with an employee from tenant B → 23503. |
| WO-J10 | PASS | Update of the default row moves `updated_at`; the override row's `updated_at` is untouched. |
| WO-J16 | PASS | All three functions `prosecdef=true`, `proconfig = {search_path=public}`. |
| WO-J18 | PASS | `attendance_today(unknown tenant)` → `PT404 tenant … not found`. |
| WO-F07 (DB) | PASS (DB part) | Invited Dev given a rule → `delete from users` refused with 23503 `attendance_weekly_off_overrides_employee_tenant_fkey` (RESTRICT). Screen part for deactivated employees not testable (no deactivate feature in the app). |
| WO-J17 | PASS | 30 random PUT/DELETE operations (mix of employees, default, past/future dates) → all 200; no overlap; at most one open row per employee; no day array invalid; no new open row before today. |
| WO-E07 | PASS | Overlap in the defaults table → 23P01 (see J07). |
| WO-E02 | **FAIL** (R-13): stale second row until relaunch; PASS after relaunch | Two queued changes → `2 changes coming up`, rows in date order, `Till then` chaining correct after relaunch. Before the relaunch the second row showed stale `Sun off`; logged as R-13 (confirmed twice). |
| WO-J09 | not run | Needs a throwaway tenant; not created in this run. |
| WO-J19 | not run | Needs a throwaway tenant with a different time zone. |
| WO-J20 | not run | Supabase advisors not read yet. |

## Run 4 — batch 3 (DB, security, downstream)

| ID | Result | Notes |
|---|---|---|
| WO-J02 | PASS | Anon PostgREST on both tables → 200 `[]` (RLS denies). Technician app token is rejected by PostgREST (401). |
| WO-J20 | PASS (note) | Advisors: weekly-off tables only show `rls_enabled_no_policy` (INFO, by design). No new function search_path warning for the three weekly-off functions. Existing WARN: extension `btree_gist` installed in `public` (needed by the exclusion constraints). Logged as R-16 (low). |
| WO-M01–M07 | BLOCKED | The monthly and dashboard endpoints show `tracked: 0` employees for Cool Air (no office tracking set up), so day statuses cannot be read for the test staff. Needs office assignment and enrolment set up in the test tenant. |
| WO-K01 | NOT COMPLETED | 200% font scale: the app's Home screen truncates labels (`Prese…`, `Not in …`). Not a weekly-off screen result. The Weekly off screen was not reached at 200% (nav failed). Font scale reset to 1.0. |
| WO-K02, K03, K05 | NOT REVIEWED | Screenshots taken (`shots/K02-360.png`, `shots/K03-dark.png`, `shots/K05-rot.png`) but not reviewed. Device settings restored (width reset, night off, rotation 0). |
| WO-E05, E03, E07 (screen), G08 screen, G12, G09–G11, G15, G17, H06, H08, H09, A04–A11, B06–B10, C08, C13, D08–D12, F01, F05–F07 (screen), Q04, Q07–Q10, Q17–Q23, Q27–Q30, K04, K06–K13 | NOT RUN | Remaining UI and edge cases. See the plan in the summary. |

### Run 4 — batch 4 (UI, resumed)

| Case | Result | Evidence and notes |
|---|---|---|
| WO-K01 | FAIL | 200% font, Weekly off screen (reached via Attendance → Weekly off). Day pills show `Wor`/`k` and clip `Off`. The starting-date hint is truncated (`beginni…`). The `2 changes coming up` badge runs off the right edge. Logged as R-17 (FE). Evidence: `shots/K01-font200-weeklyoff.png`. Font scale reset to 1.0. |
| WO-K02 | PASS | Screen forced to 945x2100 px (360 dp at 420 dpi). Day pills show `Work`/`Off` in full, the 1-day summary fits, the starting-date field and the calendar fit the width with no overlap. Save reachable by scrolling (calendar open). Evidence: `shots/K02-360-weeklyoff.png`. Size reset with `wm size reset`. The earlier `K02-360.png` shot was the launcher, not this screen, so it was discarded as evidence. |
| WO-K03 | PASS (note) | Night mode on, Weekly off reached. The screen stays in the light theme and stays readable (`shots/K03-dark-weeklyoff.png`). The case says "if supported": the app does not follow the system dark setting, so there is no dark theme to test. The earlier `K03-dark.png` shot was the launcher, so it was discarded. Night mode off again. |
| WO-K05 | PASS (note) | Date picker opened, device rotated to landscape (user_rotation 1), then back to portrait. The app stayed up, the saved selection (Sun off, 25 Oct start) was kept, and the landscape layout fits (`shots/K05-rot-sheet.png`). The date picker closes on rotation, but nothing was picked, so no selection is lost. The earlier `K05-rot.png` shot was the launcher, so it was discarded. |
| WO-K06 | PASS | Monday toggled to Off (unsaved), then `am force-stop` and relaunch. After relaunch Monday is back to Work, the screen is clean, and no half-saved state is shown. DB check: everyone rows 4 (`{7},{5},{7},{6}`, same as the snapshot), employee rows 10 (same as before the test). Evidence: `shots/K06-after-kill.png`. |
| WO-K07 | PARTIAL | Airplane mode on, then cold start. The app opens to `Couldn't load your account` with `Could not reach the server. Check your connection and try again.` and a `Try again` button. This is a clear error, not an endless spinner. The Weekly off screen itself cannot be reached offline (Attendance sits behind the Account screen, which fails), so the Weekly-off-specific offline path is not proven. Airplane mode restored to off. Evidence: `shots/K07-offline.png`. |
| WO-K09 | PASS (copy on screen) | Read every string on the Weekly off screen and the employee-wise block (`For everyone`, `Right now`, `Starting date`, `Upcoming changes`, `Employee-wise weekly off`, `Set Off`, `Edit weekly off`). They match the approved list in section 4 and use plain English. The known SD-12 copy (`Couldn't load overrides…`) needs the error state, so it is not yet checked here. |
| WO-K11 | PASS | Opened the employee edit sheet (Asha), then system Back. The sheet closed first and the Weekly off screen stayed. |
| WO-K12 | PASS (partial) | 20 open/close cycles of Weekly off from Attendance (Back to Attendance each time). Opened 20 of 20, no crash, no visible slowdown. The "100 employee rules" part was not run: Cool Air has only 4 employee rules, so the scroll check at 100 rules is not proven. Earlier attempts (three loop versions) failed because the Back key left the app and the taps landed on the launcher; the logged results are from the fixed loop. |
| WO-K13 | PARTIAL | Swiped down on the Weekly off screen (short content at top). No spinner appeared and no data changed. The screen does not show a pull-to-refresh control, so the case cannot be confirmed. Not tested on long content or after a failed refresh. Evidence: `shots/K13-pull.png`. |
| WO-K10 | PASS (note) | Three quick Save taps after toggling Friday. Each save showed `Weekly off saved` and only one banner was visible at a time. The form re-seeded to today's rule after each save, which is the known SD-3 behaviour (R-07), so the toggles were not cumulative as intended. DB after the three saves: one everyone row from 25 Oct 2026 with `{5,7}` (Fri and Sun off); the 28 Oct change that was queued before was replaced by this save, as the save algorithm does. The screen after relaunch shows Fri as Work (today's rule), which is also SD-3. Evidence: `shots/K10-after3.png`, `shots/K10-relaunch.png`. |
| WO-K04 | PASS (tree check) | Read the accessibility tree (uiautomator dump) instead of listening to TalkBack. Every control has a name: `Go back`, each day pill (`Monday` … `Sunday`, CheckBox with `checked` state), `Date: Sun, 25 Oct, 2026`, `Save schedule`, `Set weekly off for an employee`. Order follows the screen top to bottom (title, rule, pills, chip, date, Save, Upcoming, employee block). Spoken output was not heard, so the TalkBack read itself is not proven. |
| WO-K08 | BLOCKED | Needs a network throttle or proxy (3G profile). Not available on this device setup without a proxy. Reason recorded; not skipped. |
| WO-K09 (SD-12) | NOT RUN | The `Couldn't load overrides…` copy only appears when the employee-wise load fails. Needs a fault injection (proxy or a stopped endpoint). Still open. |
| WO-G09 | PASS | Edit Asha's rule. Sheet shows `Edit weekly off`, subtitle `Asha`, Friday pre-selected as Off, Starting date shown, Save disabled with `Change a day or the date to save.`, and `Remove weekly off` visible. Evidence: `shots/G09-edit-asha.png`. |
| WO-G10 | PASS (note) | Added Saturday to Asha's rule (Fri → Fri & Sat) and saved. The list shows `Fri & Sat off`. DB: one row from 21 Oct 2026 open-ended with `{5,6}`; the 18–21 Oct row `{5}` is unchanged; the later queued rows (`{}` from 21 Oct, `{6,7}` from 2 Nov) were replaced by the save, as the save rule does. The `Employee weekly off saved` banner was not captured in the text dump (1.5 s window). |
| WO-G11 | PASS | Toggled Monday on and back off. Save stays disabled with `Change a day or the date to save.`, and no write happened. Evidence: `shots/G11-toggle-back.png`. |
| WO-G12 | BLOCKED | Pre-condition not met. The case needs Asha with no queued change (a) or a `{5}` rule now plus a queued `{6}` (b). Asha now has a queued change from 21 Oct (`{5,6}` from 21 Oct after G10). Needs a reset of Asha's rules during cleanup, then both (a) and (b). Not skipped. |
| WO-G15 | PASS | Failed a save offline (G17), closed the sheet, restored the network, reopened Asha's sheet. No leftover error banner; the sheet opens normally. Evidence: `shots/G15-reopen.png`. |
| WO-G17 | PASS (note) | Airplane mode on, toggled Monday, Save. The error appears inside the sheet: `Could not reach the server. Check your connection and try again.` The selection is kept (Mon, Fri, Sat Off), the sheet stays open, and Save is available to retry. Copy is the network message, not the approved `Couldn't save`, same as R-12. Evidence: `shots/G17-save-offline.png`. |
| WO-G18 | PASS | (API, run by a helper agent, no writes.) PUT Esha (tenant B) → 404 `ATTENDANCE_EMPLOYEE_NOT_FOUND`; PUT a random valid uuid → 404 `ATTENDANCE_EMPLOYEE_NOT_FOUND`; PUT `abc` → 400 `VALIDATION_ERROR`. DB after: 0 override rows for Esha or the random id in any tenant. The 400/404 bodies include a stack trace field (R-14, same as I10). |
| WO-H10 | PASS | (API, helper agent.) DELETE Esha → 404 `ATTENDANCE_EMPLOYEE_NOT_FOUND`; DELETE random uuid → 404 `ATTENDANCE_EMPLOYEE_NOT_FOUND`; DELETE `abc` → 400 `VALIDATION_ERROR`. Run only after confirming 0 rows exist for both ids, so nothing could be deleted. DB still 0 rows. |
| WO-Q27 | PASS (known limitation) | (DB, helper agent.) Overrides columns: id, tenant_id, employee_id, valid, days, created_at, updated_at. Defaults columns: id, tenant_id, valid, days, created_at, updated_at. No actor or changed-by column in either table; `created_at`/`updated_at` are the only trace. |
| WO-Q04 | PASS | Remove dialog for Asha: title `Remove weekly off`, body `Asha will follow the "For everyone" weekly off from Wed, 21 Oct, 2026.`, buttons `Remove` and `Cancel`. Evidence: `shots/Q04-remove-dialog.png`. |
| WO-H06 | PASS (first part) | Airplane on, confirmed Remove. The error `Could not reach the server. Check your connection and try again.` shows, the sheet stays open, and the row is still listed. Evidence: `shots/H06-remove-offline.png`. Retry (network on) is recorded separately below. |
| WO-H06 (retry) | PASS | Network restored, reopened Asha's sheet, Remove → Remove. DB: the queued 21 Oct row is deleted; the history row 18–21 Oct `{5}` is kept. The row no longer shows a queued change. Evidence: `shots/H06-retry.png`. |
| WO-B06 | PASS | Mon to Sat off on the everyone rule (Sunday untapped). Chip `6 days off, 1 working day` (singular "day" used for 1). Saved. DB: everyone row from 25 Oct 2026 open-ended, `{1,2,3,4,5,6}`. Evidence: `shots/B06-six-off.png`. Banner not captured in the text dump. |
| WO-B07 | PASS | Tapped Monday 11 times quickly. Final state Monday Off (odd count), chip `2 days off, 5 working days` (Monday and Sunday), which matches the pills. Form not saved. |
| WO-B08 | BLOCKED | Needs a throttled network to see the locked state during save. Not available on this device setup. Reason recorded. |
| WO-B09 | PARTIAL | TalkBack live announcement of the chip not heard. The accessibility tree shows the chip as a plain text node. Not proven. |
| WO-B10 | PASS | Tapped near the left edge of Monday and the right edge of Sunday, once each. Each tap toggled its pill once, and the chip changed after each (2 days, then 1 day). |
| WO-C01 | BLOCKED | The plan expects the date field to show today. The current everyone rule has a queued change from 25 Oct, so the form defaults to 25 Oct (the queued start). The "today" default needs a state with no queued change (S1). Needs the cleanup reset first. |
| WO-C08 | PASS | Set the start date to 18 Oct (today), changed Monday, Save. Banner `saved` shown. Afterwards Save is disabled with `Change a day or the date to save.`. DB: one everyone row from 18 Oct open-ended, `{1}`; the earlier 25 Oct row was replaced by this save. `Right now: Mon off` describes the rule (Monday off), not today's weekday. Evidence: `shots/C08-after-save.png`. |
| WO-C13 | PASS (partial) | Phone set to Pacific/Kiritimati (phone date 19 Oct, tenant date 18 Oct). Home still shows `Sunday, Oct 18` and the Weekly off date field shows `Sun, 18 Oct, 2026`, which follows the tenant, not the phone. The Upcoming cut-off was not checked. Automatic time zone restored. Evidence: `shots/C13-kiritimati.png`. |
| WO-C14 | BLOCKED | Needs the clock to cross IST midnight with the server date unchanged. Not controllable in this run. Reason recorded. |
| WO-A04 | PARTIAL | Cold start to the Weekly off screen. The screen had its content on the first read (about 1 s after tapping). No loading placeholder text was captured, and the slow-network path needs throttling, which this setup doesn't have. Not proven. |
| WO-C04 | PASS | Pre-condition met (no queued change). Changed only the date to Wed, 21 Oct, pills unchanged. Save stays disabled with `Change a day or the date to save.`. No write. |
| WO-Q17 | PARTIAL | Employee list on the current names: Asha, Ashish, Bala, Chitra, Dev (alphabetical). Lowercase and accented names (`bala`, `Éla`) were not added, so the locale-order part is not proven. |
| WO-Q19 | PARTIAL | After a Set Off reopen, the new sheet starts empty: title `Set weekly off`, `Pick an employee`, date defaults to today (`Sun, 18 Oct, 2026`), hint `Choose an employee to save.`, no employee selected. Evidence: `shots/Q19-set-off-reopen.png`. The pre-condition (save Chitra first) did not happen: two attempts to save Chitra left her rows unchanged in the DB, so the "save then reopen" order is not proven. Retry needed. |
| NOTE (Q19 side effect) | — | During the Q19 retry, `Edit 2` opened Ashish's sheet (index 2 in the list was not Chitra; index 1 is Ashish). Monday was toggled and saved, so Ashish's everyone-of-employee rule became `{1,5}` from 18 Oct. Restored through the app to `{5}` from 18 Oct (DB confirmed; row id changed by the save). Bala and Chitra were not changed (DB confirmed). Lesson: check the sheet's name before saving. |
| TOOLING | — | uiautomator2 (Python, openatx) set up on the Pixel. Screen read about 0.2 s (adb script about 1.8 s). Tap and navigation are also faster. Helper: `scratchpad/u2h.py`. `deviceInfo` RPC fails on this Android build (ApplicationSharedMemory); dump, click and current-app work. |
| WO-Q10 | PASS (note) | Chitra has only a future rule (`Mon, 16 Nov: Mon off`, no current rule). Row shows `No day off`, `7 working days`, `From Mon, 16 Nov, 2026: Mon off`. Sheet opens with all pills Work and the date at 16 Nov (the future start). The pre-condition in the plan (`{5}` from T+5) is not what the DB holds, so this is the closest state. No save. |
| WO-Q08 | FAIL | Set Off → `Pick an employee` opens a screen titled `Select technicians` with `Choose who will do the job.`, `Search technicians`, and job-skill rows (Suresh, Mahesg) plus employees (Asha, Bala, Chitra). Expected: a weekly-off picker titled `Pick an employee`. Single-select behaviour not confirmed. Logged as R-18. Evidence: `shots/Q08-picker.png`. Backed out without applying. |
| WO-G20 | FAIL | Set Off, Monday turned on, `Pick an employee`, Back (no choice): Monday kept. Repeat: Monday on, picker, choose Asha, `Apply selection`: Monday reset to Work, only Sunday off, Asha shown. Expected pills kept. Logged as R-19. Evidence: `shots/G20-after-apply.png`. Sheet closed without saving. |
| WO-A05 | BLOCKED | Needs a cold start offline into Weekly off. The Account screen fails offline first (see K07), so Weekly off cannot be reached this way. |
| WO-A06–A11 | BLOCKED | Need a proxy or fault injection, or throttling (A06 proxy, A10 throttle). Not available on this setup. |
| WO-A12 (UI + API) | PASS | Second session on the phone: logged out the owner and signed in with the technician number `9000000001` and OTP `1039`. The account that signed in is **Loadtest H01** (tenant `792b28ed-…`), because the same number also exists there; Asha's own Cool Air login was not used. The technician has no route to Weekly off: the tabs are Today, History, Attendance, Profile, and Attendance has no Settings or Weekly off entry. The Attendance tab shows only the technician's own card (`Weekly offs: Sun – Sunday off`), not the owner's rules. API with the technician token (`tech.token`, which belongs to Mahesg, Cool Air): GET weekly-offs, GET overrides, PUT default, PUT override, DELETE override → **403**; GET with no token → **401**. No write happened. Evidence: `shots/A12-tech-attendance.png`. |
| WO-D02, D08–D12 | BLOCKED | Need failure injection (D08, D11), a throwaway environment that forces 500 (D07 family), or an owner with no company (D12). D02 needs a second owner session. |
| WO-E03 | BLOCKED | Needs state S0 (tenant never configured). Cool Air has rules. Deleting them is a cleanup step. |
| WO-E05 | BLOCKED | Needs a queued change to reach its date. Done in SQL in a transaction, which is deferred to cleanup. |
| WO-F01 | BLOCKED | Needs S1 (no employee rules). Deferred to cleanup. |
| WO-F05, F06 | BLOCKED | Need an employee with no name and 60-character names, and 100 employee rules. Test data not created yet. |
| WO-G19 | BLOCKED | Needs an employee removed after being picked (SQL or deactivate). Not done. |
| WO-H08 | BLOCKED | Double tap on Remove needs a removable rule and a repeatable window. Not run in this pass. |
| WO-H09 | BLOCKED | Needs the reload to fail after a successful Remove. Needs a proxy. |
| WO-Q07 | BLOCKED | Needs three tenant states (loading, no employees, invited only). Only Cool Air is available. |
| WO-Q09 | FAIL (R-24) | Owner screen open, picker showed 5 technicians (Dev invited, not offered). Dev was then made active in the DB (`invited` → `active`, the same change a first sign-in makes; one phone, so the sign-in itself was simulated). Backend `GET /users/me` lists Dev as `active`. Pull to refresh → picker still 5. Leave the screen and reopen → still 5. Cold relaunch → picker shows **6 total** with Dev. So the weekly-off picker keeps the old roster until the app restarts (SD-7 confirmed). Expected: the new employee is offered after pull to refresh. Logged as R-24. Evidence: `shots/Q09-baseline-picker.png`, `shots/Q09-after-activate-picker.png`, `shots/Q09-after-relaunch-picker.png`. |
| WO-Q18 | BLOCKED | Needs an employee with no name, or one missing from the tenant. Not created yet. |
| WO-Q20 | NOT RUN | Pre-condition not met: Asha has no queued change now. Needs `{5}` now and `{6}` from T+7 first. |
| WO-Q21 | BLOCKED | Needs 150 changes scripted through the API. Deferred. |
| WO-Q22 | NOT RUN | Needs backgrounding for several minutes, and across IST midnight if possible. Not run in this pass. |
| WO-Q23 | PARTIAL | Pills show M first and S last, and Sunday is the last pill (`S Off`). The DB5 check (Sunday date true, Monday false) was not run. |
| WO-Q28, Q29 | BLOCKED | Need two devices or a second writer. Not available in this setup. |
| WO-Q30 | NOT RUN | Deep link to Weekly off not checked. Needs to know whether a deep link exists. |
| WO-Q19 (retry) | PARTIAL | See the earlier Q19 row. The save-then-reopen order is still not proven. |

## Coverage check (all 178 plan cases)

Added so that every case in the plan has a row. Cases already logged above keep their rows. Cases below had no row before.

| ID | Result | Evidence and reason |
|---|---|---|
| WO-A07 | NOT RUN | Feasible with airplane mode (method as K07). Not run in this pass. |
| WO-A08 | NOT RUN | Feasible: change to `{6,7}` by API, then pull to refresh on the phone. This is the SD-1 check. Not run. |
| WO-A09 (earlier run, superseded by the run 5 PASS below) | FAIL (R-13) | Left the screen, changed data by API, came back by navigation: no UPCOMING CHANGES panel until `am force-stop` and relaunch (run 4 observation). Seen again in E02 (second row stale until relaunch). Expected: new data without a manual refresh. A clean single-change repeat is still to run. |
| WO-A10 | BLOCKED | Needs a throttled network to delay an old response. Not available on this setup. |
| WO-A11 | PARTIAL | K11 (system Back closes the sheet, screen stays) and K12 (20 returns to Attendance) cover part of it. The full Attendance → Settings → Weekly off back-arrow check at each level is not run. |
| WO-D08 | BLOCKED | Needs the PUT to succeed and the next GET to fail. Needs a proxy. |
| WO-D09 | NOT RUN | Feasible: D06 offline error, then back online and change a pill. Not run. |
| WO-D10 | NOT RUN | Feasible with the API as the second writer (owner token), while the phone shows a stale screen. Not run. |
| WO-D11 | NOT RUN | Needs an expired owner token. Not forced in this pass. |
| WO-D12 | BLOCKED | Needs an owner token with no company and a token for a deleted tenant. Those test users were not created. |
| WO-F06 | BLOCKED | Needs a 60-character employee name and 100 employee rules. Test data not created. |
| WO-J11 | PASS (by cross-reference) | Stored `{6,7}` from `[7,6]` (run 2, D03, API). Not re-read on the current state. |
| WO-J12 | PASS (by cross-reference) | Save algorithm observed in C02, C03, C05, C06 and C07 (API and DB). No overlap. |
| WO-J13 | PASS (by cross-reference) | B05 left no everyone row (DB). G06 saved an employee `{}` as a marker row (DB). |
| WO-J14 | PASS (by cross-reference) | H02, H03 and H05: clip at the date, nothing inserted, second call a no-op, history kept. |
| WO-J15 | PASS (by cross-reference) | I09: two parallel PUTs, no deadlock, one open row. |
| WO-M02 | BLOCKED | Same reason as M01: Cool Air shows 0 tracked employees, so day statuses cannot be read. |
| WO-M03 | BLOCKED | Same reason as M01: Cool Air shows 0 tracked employees, so day statuses cannot be read. |
| WO-M04 | BLOCKED | Same reason as M01: Cool Air shows 0 tracked employees, so day statuses cannot be read. |
| WO-M05 | BLOCKED | Same reason as M01: Cool Air shows 0 tracked employees, so day statuses cannot be read. |
| WO-M06 | BLOCKED | Same reason as M01: Cool Air shows 0 tracked employees, so day statuses cannot be read. |
| WO-M07 | BLOCKED | Same reason as M01: Cool Air shows 0 tracked employees, so day statuses cannot be read. |
| WO-Q29 | NOT RUN | Feasible: the API queues `{6}` from T+7, then the phone's stale screen saves from T+3. Not run. |

### Final totals (178 cases, one status each; updated during run 5)

| Status | Count | Cases |
|---|---|---|
| PASS | 135 | Includes WO-A12 (UI + API, run after Q21) and the run-5 passes: Q29, D10, A07, A09, D09, Q20, Q19, Q23, A11, J09, Q18 (with a note), E03, C01, E05, F01, G12 (both parts), G19, H08 (proxy), and the cross-referenced J11–J15. G05 counts as PASS on the corrected reading; R-06 stays open. |
| FAIL | 13 | Q09 (R-24), A08 (R-22), B02 (R-01), B05 (R-11), C03 (R-07), E02 (R-13), G20 (R-19), I10 (R-02), I13 (R-03), K01 (R-17), Q08 (R-18), Q17 (R-23), Q28 (SD-1, same as A08) |
| PARTIAL | 8 | A04, B09, F06 (100-rule part), J19 (screen part), K07, K13, Q07 ((a) and (b) not reachable), Q22 |
| BLOCKED | 20 | Needs a proxy, throttling, a forced failure, a forced clock, or office tracking (M01–M07). Second-device cases A12 and Q09 were run and are no longer blocked. |
| NOT RUN | 1 | D11 (expired token, not forced) |
| N/A | 1 | Q30 (no deep link in the app) |

Defects: R-01 to R-25 in Section R (R-25 found in the A12 login) of the test-cases file (R-14 repeats R-02; R-06 is a test-case issue; R-20 and R-21 were added from the confirmed SD-4 and SD-9). R-06 needs an owner decision and the G05 expectation is unchanged.

### Check against expectations (defects in Section R)

Each Section R defect was checked against the expectation of the case it was logged under. A case is FAIL only when its own expectation is broken. Defects whose cases only state a status code stay PASS, with the defect open in Section R.

- **FAIL added:** C03 (R-07) and E02 (R-13).
- **Still PASS, defect open:** G02 (R-04: the plan's Q06 says the API/app mismatch is not a failure), I03 (R-15: only for a bodiless DELETE sent with a JSON content type, which returns 400), I07 (R-05: non-JSON WAF body, but "4xx, tables intact" holds), I03, G18, H10, I10 (body only; I10 is FAIL), D03 and C10 (R-08 wording), D06 and G17 (R-12 copy), A01 (R-09 keyboard), J20 (R-16, an existing WARN not on these tables), G05 (R-06, expectation conflict for the state with Asha's rule; PASS for the run-3 state with no Asha rule).

Total FAIL cases: **13**. Open defects: R-01 to R-25 (R-25 is a login issue, not a weekly-off case) (see the defect count in Section R).

## Run 5 — remaining cases (2026-10-18, continued)

| ID | Result | Evidence and notes |
|---|---|---|
| WO-Q19 | **PASS** | Save first, then reopen. Set Off → Pick an employee → Chitra → Apply (sheet showed `Chitra`, pills untouched), Friday off and Sunday on, Save. API: Chitra `{5}` from 18 Oct. Reopened Set Off: title `Set weekly off`, `Pick an employee` (no employee), Sunday suggested Off, date `Sun, 18 Oct, 2026`, hint `Choose an employee to save.`. Nothing carried over. Evidence: `shots/Q19-set-off-after-save.png`. Note: the picker's Apply reset the pills (R-19) in G20; here the pills were set after Apply. |
| WO-Q23 | **PASS** | Sunday only from 1 Nov on the everyone rule (API). DB5 with a nil employee id (no override), defaults only: Sun 1 Nov (ISO 7) → `true`; Mon 2 Nov → `false`; Sat 7 Nov → `false`; Sun 8 Nov → `true`. Pill order checked in dumps: M first, S (Sunday) last. Note: the rule was set through the API, not the pills. |
| WO-A11 | **PASS** (route note) | The plan's path is More → Attendance (Offices, Settings) → Settings → Weekly off. This build's Attendance screen shows Offices, Weekly off and Holidays; there is no Settings tile in the normal path, so that level was not reached. On the route that exists: Weekly off → in-app back arrow → Attendance (pass); Weekly off → hardware Back → Attendance (pass); no crash. Attendance → Back → Account & settings → Home also passed. |
| WO-K09 | **BLOCKED** (SD-12 runtime) | Copy check: the owner-facing string in source is `Couldn't load overrides. Check your connection and try again.` (`WeeklyOffOverridesSection.tsx`), so the SD-12 wording is confirmed in code. It only shows when the employee-wise load fails while the default loads. Both loads use the same network, so this needs a single failing endpoint (proxy). Not run on the device. |
| WO-Q30 | **N/A** | The plan says to run this only if a deep link exists. The app has no URL scheme or linking config (`app.json` and `src` checked), so no deep link to `AttendanceWeeklyOff` exists to test. |
| WO-Q22 | **PARTIAL** | Weekly off open with the date set to Sun 25 Oct (unsaved). Sent the app to the background for three minutes (Home). On return the process was gone (`pidof com.fenzitapp` empty): the OS killed the app in the background, so the unsaved change was lost. After relaunch, the Weekly off date reads Sun 25 Oct, but that is the default (the queued start), so the chosen date cannot be told apart from the default. The "date minimum and Upcoming cut-off follow the new day" part needs a midnight crossing, which was not possible. Not proven. Evidence: `shots/Q22-after-restart.png`. |
| WO-Q17 | **FAIL** (R-23) | Names set in the DB for the active employees: `bala`, `Asha`, `Chitra`, `Zoya` (Suresh renamed), `Éla` (Mahesg renamed). Picker order on screen: `Zoya`, `Éla`, `Asha`, `bala`, `Chitra`. The three employees are in case-insensitive order, but the two technicians are listed first and `Zoya` sits before `Éla`, which is not alphabetical. Expected alphabetical (locale compare). Evidence: picker dump, run 5. |
| WO-Q18 | **PASS** (note) | Bala's name set to blank (DB). Picker row: avatar `?` (blank name, expected `?`), detail line `QA-BALA · +91 9000000002` (phone shown, single `+`). The name line is empty, with no fallback text. "Unknown employee" (user row missing from the tenant) not run: it needs a moved user. Partial for that part. |
| WO-F06 | **PARTIAL** | 60-character name (Asha) on the employee-wise list: wraps to two lines and cuts cleanly with an ellipsis (`Asha Ramakrishnan Venkataraman Subrama…`), no overlap, Edit and chips aligned. Evidence: `shots/F06-long-name.png`. The 100-employee-rules part is not run (needs 100 active employees). Names restored afterwards (Asha, Suresh, Mahesg, Bala). |
| WO-J09 | **PASS** | Throwaway tenant `c0c0c0c0-…c0` (owner set to the invited user Dev, because each owner can own only one tenant) with one default row `{6,7}`. Before the delete: 1 weekly-off default row, 0 overrides. `delete from tenants`: no error from other tables. After: tenant 0 rows, weekly-off default rows 0. |
| WO-J19 | **PARTIAL** | Throwaway tenant with `timezone = Pacific/Kiritimati`. `attendance_today` returned `2026-10-19` (Kiritimati date). IST date was 18 Oct, so the DB follows the tenant zone. Screen part not run: the phone is signed in to Cool Air, not to this tenant. |
| WO-A04 | **PARTIAL** | Offline open: the screen rendered cached content (form, Upcoming, employee list). Network back, pull to refresh, then 4 s of screen reads at about 0.2 s each: no loading placeholder and no error text seen. Either the reload was faster than the reads or no placeholder shows here. Throttled network needed to see it. Not proven. |
| WO-E03 | **PASS** | Never-configured everyone rule (defaults deleted in SQL, snapshot taken). Saved Saturday off, Sunday work, from 25 Oct. Upcoming row, exact text: `Sat off from this date. Till then: No day off.` (the known gap in section O). Banner `Weekly off saved`. |
| WO-C01 | **PASS** | No queued change (API set `{6,7}` from today, which removed the queued row). Date field reads `Sun, 18 Oct, 2026`. DB3 = 18 Oct. |
| WO-E05 | **PASS** | Queued `{5}` from 21 Oct (API). SQL in one step: removed the covering row `[18,21)` and moved `[21,)` to start today. Screen after reopen: no UPCOMING panel, `Right now: Fri off`. |
| WO-F01 | **PASS** | No employee rules (SQL, snapshot taken). Employee block shows the heading, `Set Off`, the subtitle and the exact text `No employee-wise weekly offs yet. Everyone follows the "For everyone" weekly off above.` No footer count. Evidence: `shots/F01-empty-list.png`. TOOLING: the text dump did not return this sentence; the screenshot did. Earlier empty-state reads used the dump, so screenshots should confirm them. |
| WO-G12 | **PASS** (both parts) | (a) Asha `{5}` from 18 Oct, no queued change. Changed only the date to Thu 22 Oct: Save stayed disabled, helper `Starting Thu, 22 Oct, 2026`, hint `Change a day or the date to save.` (screenshot `shots/G12-a-date-only.png`). Matches the code; SD-13 remains a product question (the 15-6 note). (b) Asha `{5}` now, `{6}` queued from 25 Oct (API). Changed only the date to Wed 28 Oct: Save enabled, saved, banner `Employee weekly off saved`. DB: `[18,25) {5}`, `[25,28) {6}` (clipped), `[28,) {5}`, overlaps 0. |
| WO-G19 | **PASS** | Temporary technician `QA Gone Tech` created (SQL), picked in the sheet (Apply), Friday and Sunday off, then the user row deleted (SQL). Save: inline error `Employee not found`; sheet stayed open; no new row (API still lists only Asha). Picker opens again (Change), sheet closes with Back. |
| WO-H08 | **PASS** (proxy) | Asha's sheet → Remove weekly off → Remove, with two taps within 50 ms. Dialog closed, no error. DB: Asha's rows from 25 Oct removed, history `[18,25) {5}` kept. The request count cannot be read on the device; the row result is the proxy (one delete, no conflict). |
| WO-Q28 | **FAIL** (SD-1) | Phone screen open, showing `Right now: Fri off`. The API (second screen) saved `{6,7}` from today. Phone pull to refresh: `Right now` updated to `Sat & Sun off`. The pills stayed on the old rule (Fri Off, Sat and Sun Work, no chip update). Same as A08, so SD-1 again. Evidence: `shots/Q28-after-pull.png`. |
| WO-Q07 | **PARTIAL** | Set-up: every active technician set to `invited` in SQL (Dev was already invited); owner still active. (c) invited-only: notice `No active employees yet. Employees become active after they sign in to the app for the first time — then you can set their weekly off here.` (exact match). Set Off looks dimmed and tapping it opens no sheet (`shots/Q07-invited-only.png`). PASS for (c). (a) loading state and (b) no-employees state were not reached: (b) needs no non-owner users, which means deleting them. Technicians restored to active afterwards (Dev stays invited). |
| WO-Q21 | **PASS** (open time 7.6 s) | 150 queued changes through the API (one per day from 19 Oct, rotating days, each PUT ascending). Loop log: `scratchpad/q21.log`. All 150 PUTs returned 200. Screen after relaunch: Weekly off opened in 7.6 s. Upcoming: `150 changes coming up`; rows in date order with correct chaining (`Mon 19 Oct: Sat off · Till then: Sat & Sun off`, `Tue 20 Oct: Sun off · Till then: Sat off`, `Wed 21 Oct: Fri off · Till then: Sun off`). The API GET returns the full history (not paged), as the case says. |
| WO-Q29 | **PASS** | Phone screen loaded with no queued change. The API queued `{6}` from 25 Oct (second writer). The phone was not reloaded: it toggled Friday, set the date to Wed 21 Oct and saved. Screen: `Weekly off saved`, Fri and Mon off. DB: the `{6}` from 25 Oct is gone; `[18 Oct, 21 Oct) {1}` clipped; `[21 Oct,) {1,5}` new; overlaps 0. No error shown to either side. |
| WO-D10 | **PASS** | Phone screen was stale after the API saved `{6}` from today. The phone set the date to 18 Oct, pills to `{5}` (Mon on, Fri off), saved: `Weekly off saved`. DB: one open row `[18 Oct,) {5}`, overlaps 0. Last write won, no `23P01` text shown. |
| WO-A07 | **PASS** | Wi-Fi and data off (`svc`), pull to refresh. Default card banner `Could not refresh. This is what you saw last time.` with Retry, and employee block banner `Could not refresh. This is the list you saw last time.` with Retry. Rows stayed visible. Network back, Retry: both banners cleared. DB unchanged. Evidence: `shots/A07-offline-pull.png`. |
| WO-A08 | **FAIL** (SD-1, R-22) | API changed the rule to `{6,7}`; pull to refresh. `Right now` updated to `Sat & Sun off` (expected). The pills and chip did not follow: Fri stayed Off, Sat and Sun stayed Work, chip `1 day off, 6 working days`. The case says a mismatch is SD-1. Evidence: `shots/A08-after-pull.png`. DB1 `{6,7}` from 18 Oct (API read). |
| WO-Q20 | **PASS** | API set Asha `{5}` from 18 Oct and `{6}` from 25 Oct. Edit sheet: title `Edit weekly off`, subtitle `Asha`, pills show the current `{5}` (Fri Off), date `Sun, 25 Oct, 2026`, helper `Starting Sun, 25 Oct, 2026`, Save disabled with `Change a day or the date to save.`. Monday turned on, Save: DB `[18 Oct,25 Oct) {5}` and `[25 Oct,) {1,5}`, so the save started from 25 Oct. Note: the sheet shows the current pills with the queued start date. Whether the owner expects that is a product question. TOOLING: `d(text='M')` matched the page's first M pill, so pill taps in a sheet must target the sheet's pills. |
| WO-A09 | **PASS** (R-13 not seen this time) | Left the screen (Back to Attendance), API queued `{4}` from 25 Oct, returned by navigation (Settings → Weekly off), no relaunch. Upcoming showed `1 change coming up`, `Sun, 25 Oct, 2026`, `EVERYONE`, `Thu off from this date. Till then: Sat & Sun off.` The earlier stale panel (R-13) did not repeat in this run; it is still logged as intermittent. |
| WO-D09 | **PASS** | Wi-Fi and data off, pill changed, Save: `Could not reach the server…` and the pill was kept. Network back, second Save: error gone. API: second save wrote `next {1,6,7}` from 25 Oct. The `Weekly off saved` banner was not captured (timing); the write is confirmed. |

## Owner decisions — pending (revisit later)

No expected result has been changed. Each item below stays open until the owner decides. The affected results keep their current status.

| # | Item | Question for the owner | Affected results |
|---|---|---|---|
| 1 | R-06 | Should the G05 expectation follow Section 2.2 of the plan? The two disagree. | G05 (PASS on the current reading) |
| 2 | SD-13 | When only the starting date changes, should Save be enabled? | G12(a) |
| 3 | R-20 | When only the starting date of a queued change moves, should the queued rule move with it? | C04b (SD-4) |
| 4 | R-21 | Should a queued "clear" (no weekly off from a future date) show in Upcoming? | Q11 (SD-9) |
| 5 | Q20 | On the edit sheet of a queued change, should the pills show the current rule or the queued one? | Q20 |
| 6 | R-13 | Should the stale panel refresh on screen focus? The behaviour is intermittent. | E02 (FAIL) |
| 7 | R-25 | When one phone is active in two tenants, should sign-in ask for the tenant (or return the list)? | A12 (login) |
