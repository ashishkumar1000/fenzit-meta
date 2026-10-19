---
workflowType: 'testarch-test-design'
artifact: 'QA execution recipe — Weekly off screen'
created: '2026-10-18'
status: 'draft — awaiting executor agent'
---

# Test Design for QA: Weekly off screen (Attendance → Settings → Weekly off)

**Purpose:** a manual functional tester's recipe. Every case says **what to test**, **how to test it** (numbered steps), **what you should see**, **what the API should return** and **what to check in the database**.

**Format:** BMAD test-design QA template (priority P0–P3, entry/exit criteria, not-in-scope), with every case written as a self-contained block.

**Sources:** specs 15-5 (backend) and 15-6 (app), `docs/api-contracts.md`, the weekly-off redesign (app commit `2866003`, 2026-10-18), and the live screen on the Pixel 6.

---

## 1. Executive summary

**Scope:** the Weekly off screen only — the *For everyone* card, the *Upcoming changes* panel, and *Employee-wise weekly off* (list, Set/Edit sheet, Remove). Plus its five API routes and two database tables.

**Not in scope** (accepted): Holidays screen; attendance check-in; day-status engine (only 7 spot checks in section M); employee onboarding; push notifications (weekly off sends none).

**Risks that drive priority**

| ID | Risk | Priority |
|---|---|---|
| R1 | Wrong weekly off silently changes who is marked Absent / Weekly off | P0 |
| R2 | A 7-day week off saved (nobody works) | P0 |
| R3 | An employee-wise weekly off does not replace the everyone rule, or leaks to another tenant | P0 |
| R4 | Past dates rewritten, or overlapping ranges (history corrupted) | P0 |
| R5 | Double tap / retry creates duplicate or conflicting rows | P1 |
| R6 | Owner sees success when the save failed (or the reverse) | P1 |
| R7 | Technician reaches owner data | P0 |
| R8 | Confusing copy for non-technical owners; unclear why Save is disabled | P2 |
| R9 | Accessibility and small-screen layout | P2 |

**Coverage:** about 180 cases (roughly 40 P0, 90 P1, 45 P2, 8 P3), including 30 added after a code review (section Q) and 13 suspected defects to confirm (Q2).

**Case types:** **F** = functional (happy path) · **N** = negative (wrong input, failure, forbidden) · **C** = corner / boundary / ordering / timing.

### Entry criteria
- [ ] Latest `fenzit-be` is deployed to the test API **before** the app build (backend deploys first).
- [ ] App build installed on the Pixel 6 (`com.fenzitapp`), signed in as the test owner.
- [ ] Test tenant with the data in section 3. Never test on a real customer tenant.
- [ ] Supabase MCP works against project `pnlvreaijzslfymlnoti`; owner and technician tokens available.

### Exit criteria
- [ ] All P0 pass. All P1 pass or have an accepted, logged defect.
- [ ] No open high-severity defect. Section O (known gaps) is not re-reported.
- [ ] The DB invariants (section 2.4) held after every write case.

---

## 2. How to run

### 2.1 Rules for the executing agent
1. **Do not change app or backend code.** If the result differs from *Expected*, mark FAIL and write actual vs expected. Never adjust the expected result to match what you saw.
2. Device is `adb` Pixel 6 (`~/Library/Android/sdk/platform-tools/adb`). Before **every tap**, check the foreground app: `adb shell dumpsys window | grep mCurrentFocus` — the owner may be using the phone. `uiautomator dump` bounds are authoritative; a dump taken straight after a write can be stale, wait ~1 s. After an app code change, force-stop and relaunch.
3. Supabase MCP `execute_sql` returns only the **last statement's rows** — run one query per call.
4. After every write case: run the DB check in the case **and** the standing invariants (2.4).
5. Reset between cases with the clean-up SQL (2.3) unless the case says **continues from previous**.
6. Take a screenshot for every FAIL and for every case marked 📷.

### 2.2 Vocabulary
- **T** = tenant "today" = `select attendance_today(':tenant')` (Query DB3). Always use this, **never the phone's date**.
- **Day numbers (ISO):** 1 Mon · 2 Tue · 3 Wed · 4 Thu · 5 Fri · 6 Sat · 7 Sun. `days` always means days **off**.
- **Everyone rule** = the tenant default (table `attendance_weekly_off_defaults`).
- **Employee rule** = one person's own weekly off (table `attendance_weekly_off_overrides`; the app calls it "employee-wise weekly off"). While it covers a date it **replaces** the everyone rule for that person.
- **Open-ended range** `[2026-10-19,)` = starts on that date and never ends.
- **No row = all 7 days are working days** (for the everyone rule).

### 2.3 Reusable commands

API (`$BASE` = API base ending `/api/v1`, `$OWNER`/`$TECH` = bearer tokens, `$EMP` = employee id):
```bash
curl -s -H "Authorization: Bearer $OWNER" $BASE/attendance/weekly-offs
curl -s -H "Authorization: Bearer $OWNER" $BASE/attendance/weekly-offs/overrides
curl -s -X PUT -H "Authorization: Bearer $OWNER" -H 'Content-Type: application/json' -d '{"days":[6,7]}' $BASE/attendance/weekly-offs
curl -s -X PUT -H "Authorization: Bearer $OWNER" -H 'Content-Type: application/json' -d '{"days":[5]}' $BASE/attendance/weekly-offs/overrides/$EMP
curl -s -X DELETE -H "Authorization: Bearer $OWNER" "$BASE/attendance/weekly-offs/overrides/$EMP"
```

Database (replace `:tenant`, `:emp`, `:d`):

| Query | SQL |
|---|---|
| **DB1** everyone rule rows | `select id, valid, days, created_at, updated_at from attendance_weekly_off_defaults where tenant_id=':tenant' order by lower(valid);` |
| **DB2** employee rule rows | `select id, employee_id, valid, days from attendance_weekly_off_overrides where tenant_id=':tenant' order by employee_id, lower(valid);` |
| **DB3** tenant today | `select attendance_today(':tenant');` |
| **DB4** overlap check (must be 0 rows) | `select a.id,b.id from attendance_weekly_off_defaults a join attendance_weekly_off_defaults b on a.tenant_id=b.tenant_id and a.id<b.id and a.valid && b.valid;` |
| **DB4b** same for employees | `select a.id,b.id from attendance_weekly_off_overrides a join attendance_weekly_off_overrides b on a.employee_id=b.employee_id and a.id<b.id and a.valid && b.valid;` |
| **DB5** is this weekday off for this person on this date? (true/false) | `select (extract(isodow from date ':d')::int = any(coalesce((select days from attendance_weekly_off_overrides where employee_id=':emp' and valid @> date ':d'),(select days from attendance_weekly_off_defaults where tenant_id=':tenant' and valid @> date ':d'),'{}'::integer[]))) as is_off;` — pass a real calendar date (e.g. the next Sunday after T) |

Clean-up (test tenant only):
```sql
delete from attendance_weekly_off_overrides where tenant_id=':tenant';
delete from attendance_weekly_off_defaults  where tenant_id=':tenant';
```

### 2.4 Standing DB invariants (check after EVERY write case)
1. DB4 and DB4b return **0 rows** (no overlapping ranges).
2. Every `days` array is sorted, has no duplicates, uses only 1–7, and has fewer than 7 items.
3. **No row starts before T** because of this action (the past is never created or edited).
4. Only the test tenant's rows changed; another tenant's row counts are unchanged.
5. `updated_at` moved only on rows this action touched.

### 2.5 Result log (one line per case)
`ID · PASS | FAIL | BLOCKED · actual result · evidence (screenshot path / API body / SQL output)`

---

## 3. Test data and starting states

| Item | Value |
|---|---|
| Tenant A | test company, timezone Asia/Kolkata |
| Owner A | signed in on the phone |
| Employees | **Asha, Bala, Chitra** (active), **Dev** (invited, not yet active) |
| Tenant B | second company: **Owner B**, **Esha** (for isolation checks) |

**Starting states** (create with API calls after clean-up):
- **S0** — nothing saved (no rows in DB1 or DB2).
- **S1** — S0 + `PUT {"days":[7]}` → everyone off on Sunday from T.
- **S2** — S1 + `PUT overrides/Asha {"days":[5]}` → Asha off on Friday from T.
- **S3** — S2 + `PUT overrides/Bala {"days":[1,7]}`.

## 4. Exact copy on the screen (assert these strings)

| Place | Text |
|---|---|
| Header | `Weekly off` |
| Badge | `FOR EVERYONE` |
| Helper (never configured) | `No weekly off set yet. By default Sunday is shown off — pick the days you'd like off. Save to apply for everyone.` |
| Helper (configured) | `Pick the days everyone is off. Days not picked count as working days.` |
| Current line (configured only) | `Right now: Sun off` · `Right now: Sat & Sun off` · `Right now: Mon, Tue & Wed off` · `Right now: No day off` |
| Pills | letters `M T W T F S S`, each with `Work` or `Off` under it; accessible names Monday … Sunday |
| Chip | `1 day off, 6 working days` · `2 days off, 5 working days` · `6 days off, 1 working day` · `0 days off, 7 working days` |
| Seven picked | `Pick at least one working day — a full week off isn't allowed.` |
| None picked | `No day is off. If you save, everyone will work all 7 days.` |
| Date block | `STARTING DATE` · field `Date: Mon, 19 Oct, 2026` · `Starts from the beginning of this day` · `Choose today or a later date` |
| Save | button `Save schedule`; when disabled: `Change a day or the date to save.` |
| Saved | `Weekly off saved` (disappears after about 1.5 s) |
| Upcoming | `UPCOMING CHANGES` · `1 change coming up` / `N changes coming up` · tag `EVERYONE` · `Sat off from this date. Till then: Sun off.` |
| Employee block | `EMPLOYEE-WISE WEEKLY OFF` · button `Set Off` · `Give a different weekly off to one person.` |
| Employee row | name · `Sun off` / `Mon & Sun off` · `6 working days` · `Edit` · scheduled: `From Mon, 26 Oct, 2026: Sat off` |
| Footer | `2 employees have a different weekly off` |
| Sheet titles | `Set weekly off` (add) · `Edit weekly off` (edit; employee name under the title) |
| Sheet picker | `Pick an employee` |
| Sheet date hint | `Starting <date>` · `Starting today (<date>) if you leave it blank` |
| Sheet none-picked hint | `Pick at least one day off — or leave it empty if <name> works all 7 days.` |
| Sheet add hint | `Choose an employee to save.` · `Change the days off to save.` |
| Remove | button `Remove weekly off` → dialog title `Remove weekly off`, buttons `Remove` / cancel |
| Employee banners | `Employee weekly off saved` · `Employee weekly off removed` |
| Errors | `Couldn't save. Try again.` · `Couldn't load weekly off. Check your connection and try again.` · `Could not refresh. This is what you saw last time.` · `Couldn't load overrides. Check your connection and try again.` |

---

# CASES

## Section A — Opening the screen and its states

#### WO-A01 · P0 · F — First open, nothing configured 📷
- **What to test:** a company that never set a weekly off sees Sunday as a suggestion only; nothing is saved by opening the screen.
- **Pre-condition:** S0.
- **How to test:** 1) More → Attendance → Settings → Weekly off. 2) Read the whole screen top to bottom. 3) Tap `Save schedule`.
- **Expected (screen):** never-configured helper; **no** `Right now` line; Sunday pill `Off`, other six `Work`; chip `1 day off, 6 working days`; date = today; **Save disabled**, hint `Change a day or the date to save.`; no Upcoming panel; Employee block visible with `Set Off`; tapping the disabled Save does nothing.
- **Expected (API):** `GET weekly-offs` → 200 `{default:null,next:null,history:[]}` (never 404). No PUT was sent.
- **Check in DB:** DB1 and DB2 → **0 rows** (opening must not seed Sunday).

#### WO-A02 · P0 · C — Touching the Sunday suggestion on a never-configured company
- **What to test:** what Save does after the owner taps the suggested Sunday off and on again (spec 15-6: "tap-then-untap returns to the starting state and Save stays disabled").
- **Pre-condition:** S0, screen open.
- **How to test:** 1) Tap Sunday (becomes Work). Look at Save and the chip. 2) Tap Sunday again (back to Off). Look at Save.
- **Expected (screen):** after step 1: chip `0 days off, 7 working days`, notice `No day is off…`; Save **disabled** (nothing is saved, so "no weekly off" is already the state). After step 2: chip `1 day off, 6 working days`. **Per the spec Save should be disabled again; by the code (the saved baseline for a never-configured company is empty, not Sunday) Save becomes enabled and would save Sunday.** Record exactly what you see — enabled = **SD-11** (section Q2). Either way no request is sent until Save is tapped.
- **Expected (API):** no PUT unless you tap Save.
- **Check in DB:** DB1 → 0 rows (if you did not tap Save). If you tap Save: one row `[T,)` `{7}`.

#### WO-A03 · P1 · F — First open, already configured 📷
- **Pre-condition:** S1.
- **What to test:** saved rule is shown correctly.
- **How to test:** open the screen.
- **Expected (screen):** configured helper; `Right now: Sun off`; Sunday `Off`; chip `1 day off, 6 working days`; Save disabled; no Upcoming panel.
- **Expected (API):** `default.days=[7]`, `default.validFrom` ≤ T.
- **Check in DB:** DB1 → one row, open-ended, `days={7}`.

#### WO-A04 · P2 · C — Loading state
- **What to test:** slow network never shows a blank or frozen screen.
- **How to test:** throttle network (or airplane mode, then switch on at once), open the screen.
- **Expected (screen):** placeholder/skeleton (`Loading attendance` for screen readers) until data arrives; then the real content replaces it; no flash of wrong data.
- **Expected (API):** one GET `weekly-offs` and one GET `overrides`.
- **Check in DB:** nothing changes.

#### WO-A05 · P1 · N — Cannot load at all
- **What to test:** first load fails (no internet).
- **How to test:** sign in with network on, go to Settings (not yet Weekly off); turn airplane mode on; open Weekly off. Then airplane off and tap Retry. (Do not kill the app offline — sign-in itself would fail.)
- **Expected (screen):** the card shows `Couldn't load weekly off. Check your connection and try again.` with a **Retry** button, and the employee block shows its own `Couldn't load overrides. …` with its own Retry; after Retry the normal screen shows. No crash, no endless spinner.
- **Expected (API):** request fails client-side; after retry 200.
- **Check in DB:** nothing changes.

#### WO-A06 · P1 · N — Only the employee list fails
- **What to test:** the two blocks fail independently.
- **How to test:** make only `GET …/overrides` fail (proxy/mock; if impossible mark **BLOCKED**).
- **Expected (screen):** the everyone card works; the Employee block shows `Couldn't load overrides. Check your connection and try again.` — **not** the "no overrides" empty text.
- **Check in DB:** nothing changes.

#### WO-A07 · P1 · N — Refresh fails but old data stays
- **Pre-condition:** S2 loaded on screen.
- **How to test:** airplane on; pull down to refresh; then airplane off and pull again.
- **Expected (screen):** existing rows stay visible; banner `Could not refresh. This is what you saw last time.` (default card) or `Could not refresh. This is the list you saw last time.` (employee block) — each with its own **Retry** button; Retry (or a successful pull) clears the banner.
- **Check in DB:** nothing changes.

#### WO-A08 · P1 · F — Pull to refresh shows outside changes
- **Pre-condition:** S1 on screen.
- **How to test:** change the rule to `{6,7}` through the API; pull down on the phone.
- **Expected (screen):** `Right now: Sat & Sun off` updates. **Code note:** the pills/chip are seeded **once** on first load (`useWeeklyOffDefaultForm`, `hasLoadedRef`), so they may keep showing the old Sunday-only selection while `Right now` shows the new rule. Record exactly what you see; a mismatch is **suspected defect SD-1** (section Q2).
- **Check in DB:** DB1 shows `{6,7}` from T.

#### WO-A09 · P2 · C — Coming back to the screen reloads
- **How to test:** leave the screen, change data through the API, come back.
- **Expected (screen):** `Right now`, Upcoming and the employee list show the new data without manual refresh (the pills follow the SD-1 note in WO-A08).

#### WO-A10 · P2 · C — Old slow response must not overwrite a newer one
- **How to test:** throttled network. Open the screen, leave and return twice quickly; between visits change the rule through the API.
- **Expected (screen):** the final screen shows the **latest** server data, never an older response.

#### WO-A11 · P2 · F — Navigation
- **How to test:** More → Attendance (two tiles: Offices, Settings) → Settings → Weekly off. Use the back arrow at each level.
- **Expected (screen):** each back lands on the previous screen; no crash; hardware back also works.

#### WO-A12 · P0 · N — Employee (technician) must not see owner data
- **What to test:** a non-owner cannot read or change weekly offs.
- **How to test:** 1) Log in as an employee and try to reach the screen. 2) With `$TECH` call all five routes (GET default, GET overrides, PUT default, PUT override, DELETE override). 3) Call one route with no token.
- **Expected (screen):** no weekly-off data is ever shown (known gap: the app may let them reach the screen and show a "check your connection" error — log it, don't fail on the copy).
- **Expected (API):** `403` on every route for technician; `401` with no token.
- **Check in DB:** DB1/DB2 unchanged.

---

## Section B — Day pills (For everyone card)

#### WO-B01 · P0 · F — Turn a day off
- **Pre-condition:** S1.
- **How to test:** tap **Saturday**.
- **Expected (screen):** Sat shows `Off`; chip `2 days off, 5 working days`; Save enabled; the "change a day" hint is gone.
- **Check in DB:** nothing yet (not saved).

#### WO-B02 · P0 · C — Undo returns to the saved state
- **How to test:** continue; tap Saturday again.
- **Expected (screen):** chip back to `1 day off, 6 working days`; Save **disabled** again.

#### WO-B03 · P1 · F — Every pill works and is named correctly
- **How to test:** tap each pill once, then read names with `uiautomator dump` or TalkBack.
- **Expected (screen):** all seven toggle; the two S pills have different names (Saturday / Sunday), the two T pills (Tuesday / Thursday); they announce as checkable (multi-select), not radio.

#### WO-B04 · P0 · N — All seven days off is blocked
- **What to test:** FR-18, at least one working day must remain.
- **How to test:** 1) Select all seven pills. 2) Try to Save. 3) Call the API directly: `PUT {"days":[1,2,3,4,5,6,7]}`.
- **Expected (screen):** chip `7 days off, 0 working days`; notice `Pick at least one working day — a full week off isn't allowed.`; Save disabled; **no** extra hint under Save (the notice already explains).
- **Expected (API):** no request from the app; direct PUT → `422` `ATTENDANCE_NO_WORKING_DAYS`.
- **Check in DB:** unchanged. Also try `insert … days '{1,2,3,4,5,6,7}'` directly → fails with check violation `23514`.

#### WO-B05 · P0 · F — Clear all days (everyone works all 7 days)
- **Pre-condition:** S1.
- **How to test:** 1) Untap Sunday. 2) Read the screen. 3) Tap Save.
- **Expected (screen):** chip `0 days off, 7 working days`; notice `No day is off. If you save, everyone will work all 7 days.`; Save enabled. After Save: `Weekly off saved`. **Code note:** after a clear the server default is `null`, so the screen treats the company as "never configured": it shows the never-configured helper, **no** `Right now` line, and snaps the pills back to the Sunday suggestion (`Off`). Record exactly what you see — a screen that shows Sunday off while the DB means "everyone works all 7 days" is **suspected defect SD-2** (section Q2).
- **Expected (API):** `PUT {"days":[]}` → 200.
- **Check in DB:** DB1: the open Sunday row is **clipped at T or removed**; **no new row** with empty days is created for the everyone rule. DB4 → 0 rows.

#### WO-B06 · P1 · C — Maximum allowed: six days off
- **How to test:** select Mon–Sat (Sun working), Save.
- **Expected (screen):** chip `6 days off, 1 working day` (singular "day"); saves normally.
- **Check in DB:** DB1 → `days={1,2,3,4,5,6}`.

#### WO-B07 · P1 · C — Tapping very fast
- **How to test:** tap one pill 11 times quickly.
- **Expected (screen):** final state matches odd/even taps; chip text always matches the pills; no stuck state.

#### WO-B08 · P1 · C — Everything locks while saving
- **How to test:** throttled network; change a day; Save; at once try to tap pills and the date field.
- **Expected (screen):** Save shows a loading state; pills and date field ignore taps until the save ends.
- **Check in DB:** one write only.

#### WO-B09 · P2 · C — Chip announced to screen readers
- **How to test:** TalkBack on; toggle a day.
- **Expected:** the new chip text is announced (Android). iOS VoiceOver gap is in section O.

#### WO-B10 · P2 · C — Small pill tap target
- **How to test:** tap near the left/right edge of the first and last pill.
- **Expected (screen):** each tap registers once (pills are ~39 dp wide — known, section O).

---

## Section C — Starting date

#### WO-C01 · P0 · F — Default date is the tenant's today
- **How to test:** open the screen; read the date field; run DB3.
- **Expected (screen):** field `Date: <weekday, d Mon, yyyy>` equals DB3's date.
- **Check in DB:** DB3 equals the date shown.

#### WO-C02 · P0 · N — Past dates cannot be chosen
- **How to test:** open the calendar; try to tap yesterday and earlier. Then, by API: `PUT {"days":[6],"effectiveFrom":"<T minus 30>"}`.
- **Expected (screen):** all dates before today are disabled.
- **Expected (API):** 200 but **clamped** — the response's `validFrom` equals T, not T−30.
- **Check in DB:** new row `lower(valid)=T`. No row starts in the past.

#### WO-C03 · P0 · F — Schedule a change for next week 📷
- **Pre-condition:** S1.
- **How to test:** 1) Tap Saturday on (Sat + Sun). 2) Date → T+7. 3) Save.
- **Expected (screen):** `Weekly off saved`; **UPCOMING CHANGES** appears: `1 change coming up`, tag `EVERYONE`, `Sat & Sun off from this date. Till then: Sun off.`; `Right now` still `Sun off`. **Code note:** after the save the form is re-seeded from the server's **current** rule and the queued date, so the pills go back to Sunday-only and the date field shows T+7. Record it (SD-3, section Q2).
- **Expected (API):** GET → `default.days=[7]`, `next.days=[6,7]`, `next.validFrom=T+7`, `history` ascending (2 items).
- **Check in DB:** DB1 → row 1 `[…,T+7)` `{7}` (upper bound clipped to T+7); row 2 `[T+7,)` `{6,7}`. DB4 → 0 rows.

#### WO-C04 · P1 · C — Only the date changed (nothing queued)
- **What to test:** changing only the date, with the same days and no queued change.
- **Pre-condition:** S1 (no queued change).
- **How to test:** leave the pills, change only the date to T+3; look at Save.
- **Expected (screen):** by the code (`effectiveDateChanged` is only true when a queued change exists) Save stays **disabled** — saving the same days from a later date would change nothing. Record what you see.
- **Check in DB:** DB1 unchanged.

#### WO-C04b · P1 · C — Reschedule a queued change (date only)
- **Pre-condition:** `{7}` now, `{6}` queued for T+7. Open the screen fresh.
- **How to test:** note the pills and the date field (the code seeds the date field with T+7 but the pills with the **current** rule `{7}`); change **only** the date to T+10; Save.
- **Expected (screen):** Save becomes enabled by the date change; after Save Upcoming shows one change from T+10.
- **Check in DB:** the RPC deletes ranges starting on/after T+10 and clips the covering one — so the pills' days (`{7}`) start at T+10 and the old `{6}` range (T+7) is clipped to end at T+10 (it keeps running T+7→T+10). If the owner expected the queued `{6}` to simply move to T+10, report **SD-4** (section Q2).

#### WO-C05 · P0 · C — Same future date saved twice (no leftover rows)
- **How to test:** save `{6}` from T+7; then save `{5}` from T+7.
- **Expected (screen):** Upcoming shows one change: `Fri off from this date…`.
- **Check in DB:** exactly **one** range starts at T+7 with `{5}`; the `{6}` row is gone. DB4 → 0.

#### WO-C06 · P1 · C — An earlier change wipes later queued changes
- **How to test:** save `{6}` from T+14; then save `{5}` from T+7.
- **Expected (screen):** Upcoming lists only the T+7 change.
- **Check in DB:** the T+14 range is **deleted**; T+7 range `{5}` is open-ended.

#### WO-C07 · P1 · C — Change effective today while one is queued
- **Pre-condition:** `{7}` now and `{6}` queued for T+7.
- **How to test:** select Thu only, date today, Save.
- **Expected (screen):** Upcoming panel disappears; `Right now: Thu off`.
- **Check in DB:** queued row deleted; the earlier range is clipped at T (or deleted if it started today); new `[T,)` `{4}`.

#### WO-C08 · P1 · C — After saving, Save locks again
- **How to test:** change a day, Save with today's date, watch Save when the banner ends.
- **Expected (screen):** Save is **disabled** (no phantom change). Only **one** PUT was sent.

#### WO-C09 · P1 · C — Days changed, date untouched
- **How to test:** change days only and Save.
- **Expected (API):** request has no `effectiveFrom` (or today); BE stamps T.
- **Check in DB:** new row starts at T.

#### WO-C10 · P1 · N — Bad dates through the API
- **How to test:** `PUT {"days":[6],"effectiveFrom":X}` for X = `"2026-02-30"`, `"2026-13-01"`, `"abc"`, `"19-10-2026"`, `20261019`, `null`.
- **Expected (API):** `422 VALIDATION_ERROR` for each invalid one **except `null`**, which the validator treats as "not provided" → 200 with date = today (`@IsOptional` ignores null).
- **Check in DB:** unchanged each time.

#### WO-C11 · P2 · C — Far future
- **How to test:** pick T+365; via API T+3650.
- **Expected (screen):** saves; Upcoming lists it; date text not cut off.
- **Check in DB:** `lower(valid)` equals the chosen date.

#### WO-C12 · P2 · C — Month and year ends, leap day
- **How to test:** choose 31 Dec and 29 Feb (a leap year) as dates; Save each (clean up between).
- **Expected:** the exact date picked appears in the field and in the DB (no one-day shift).
- **Check in DB:** `lower(valid)` = picked date.

#### WO-C13 · P1 · C — Phone set to another time zone
- **How to test:** set the phone's time zone to e.g. America/New_York at a time when its date differs from IST; open the screen.
- **Expected (screen):** "today" in the date field and the cut-off for Upcoming follow **IST / the tenant** (match DB3), not the phone.

#### WO-C14 · P2 · C — Midnight while the screen is open (BLOCKED if clock can't be controlled)
- **How to test:** leave the screen open across IST midnight (or move the phone clock with the real server date unchanged — then only the app side is tested).
- **Expected (screen):** the earliest selectable date moves forward; a queued change that has now started leaves Upcoming after a refresh.

---

## Section D — Saving the everyone rule

#### WO-D01 · P0 · F — Happy path: Saturday + Sunday 📷
- **Pre-condition:** S0.
- **How to test:** 1) Leave Sunday off, tap Saturday. 2) Date = today. 3) Save. 4) Wait 2 s.
- **Expected (screen):** loading → `Weekly off saved` → banner disappears in ~1.5 s; pills show Sat+Sun `Off`; `Right now: Sat & Sun off`; Save disabled again.
- **Expected (API):** `PUT` 200; then a `GET` (the app reloads after saving) returns the new rule.
- **Check in DB:** DB1 → one row `[T,)` `days={6,7}`. DB4 → 0.

#### WO-D02 · P1 · F — First ever save with a non-Sunday choice
- **Pre-condition:** S0.
- **How to test:** untap Sunday, tap Wednesday, Save.
- **Expected (DB):** DB1 → one row `{3}`; **no** Sunday row exists.

#### WO-D03 · P1 · N — Odd input via the API
- **How to test:** PUT with `{"days":[7,6]}`, `{"days":[7,7]}`, `{"days":[0]}`, `{"days":[8]}`, `{"days":[-1]}`, `{"days":[1.5]}`, `{"days":["a"]}`, `{"days":null}`, `{}`, `{"days":"6,7"}`, and a `days` array of 1000 items.
- **Expected (API):** `[7,6]` → 200 and stored as `{6,7}`; every other one → `422 VALIDATION_ERROR`.
- **Check in DB:** only the `[7,6]` case wrote a row, sorted `{6,7}`.

#### WO-D04 · P1 · C — Saving the same thing again
- **How to test:** by API, send `{"days":[6,7]}` twice in a row.
- **Expected (API):** both 200.
- **Check in DB:** still **one** open range, no duplicate, DB4 → 0.

#### WO-D05 · P0 · C — Double tap on Save
- **How to test:** change a day; tap `Save schedule` twice as fast as you can (repeat 3 times with `adb shell input tap` twice back-to-back).
- **Expected (API):** exactly **one** PUT per attempt.
- **Check in DB:** one new range per save; DB4 → 0.

#### WO-D06 · P0 · N — Internet drops while saving
- **How to test:** change a day; airplane mode on; Save; then airplane off and Save again.
- **Expected (screen):** a red error banner (`Couldn't save. Try again.` or the server message); pills and date **keep what you chose**; second Save succeeds with `Weekly off saved`.
- **Check in DB:** after the first Save: unchanged. After the second: one change.

#### WO-D07 · P1 · N — Server error (5xx) (BLOCKED unless a throwaway env allows it)
- **How to test:** force a 500 on the PUT.
- **Expected (screen):** error banner, form kept, retry possible.
- **Check in DB:** unchanged.

#### WO-D08 · P1 · C — Save worked but the reload failed
- **How to test:** let the PUT succeed and fail the next GET.
- **Expected (screen):** treated as **success** (the owner is not told it failed and is not made to repeat it).
- **Check in DB:** the change exists exactly once.

#### WO-D09 · P2 · C — Old error disappears
- **How to test:** cause an error (D06), then change a pill.
- **Expected (screen):** the old red banner does not stay on a later successful save.

#### WO-D10 · P1 · C — Two owners editing at the same time
- **How to test:** two sessions on the same tenant. A saves `{6}`; B (stale screen) saves `{5}` today.
- **Expected:** both succeed, last write wins; A sees B's rule after refresh.
- **Check in DB:** one open range; DB4 → 0; no `23P01` error text in any response.

#### WO-D11 · P1 · N — Token expired
- **How to test:** expire the owner token; tap Save.
- **Expected (screen):** app refreshes the session or asks to sign in; nothing is lost silently; after sign-in the save can be repeated.
- **Check in DB:** no partial write.

#### WO-D12 · P1 · N — Owner without a company / company removed
- **How to test:** call PUT with an owner token that has no tenant; call GET with a token of a deleted tenant.
- **Expected (API):** no tenant → `400 VALIDATION_ERROR`; deleted tenant → `404 ATTENDANCE_TENANT_NOT_FOUND`.
- **Check in DB:** no rows created anywhere.

---

## Section E — Upcoming changes panel

#### WO-E01 · P1 · F — One queued change
- **Pre-condition:** `{7}` now, `{6}` from T+7.
- **How to test:** read the panel.
- **Expected (screen):** `1 change coming up`; one row with the long date, tag `EVERYONE`, `Sat off from this date. Till then: Sun off.`

#### WO-E02 · P1 · F — Two queued changes
- **How to test:** save `{6}` from T+7, then `{5}` from T+14 (the second must not delete the first).
- **Expected (screen):** `2 changes coming up`, rows in date order; second row `Fri off from this date. Till then: Sat off.` (the "till then" is the previous queued rule, not today's).
- **Check in DB:** three contiguous ranges `[x,T+7)`, `[T+7,T+14)`, `[T+14,)`. DB4 → 0.

#### WO-E03 · P2 · C — Queued change when nothing was ever configured
- **Pre-condition:** S0.
- **How to test:** save `{6}` from T+7; read the row.
- **Expected (screen):** record the exact text. Known: it says `Till then: No day off` although the screen suggested Sunday (section O).

#### WO-E04 · P2 · N — Panel cannot be edited
- **How to test:** tap rows of the panel.
- **Expected (screen):** nothing opens; (there is no cancel button — see E06 for the workaround).

#### WO-E05 · P1 · C — Queued change reaches its date
- **How to test:** wait for the date, or in SQL (test tenant, one transaction) delete the old covering row and set the queued row's `valid` to `daterange(current_date, null)`; refresh. (Updating only one row breaks the no-overlap rule and fails with `23P01`.)
- **Expected (screen):** panel disappears; `Right now` shows the new days.

#### WO-E06 · P1 · F — Cancel a queued change by saving an earlier one
- **How to test:** with a queued change, save the current days again from today.
- **Expected (screen):** panel disappears.
- **Check in DB:** the queued range is deleted.

#### WO-E07 · P3 · N — The database refuses a bad history
- **How to test:** in SQL (test tenant) try to insert a second everyone-rule row whose dates overlap an existing one.
- **Expected (DB):** the insert fails with `23P01` (no overlap allowed); the screen is unaffected after refresh.

---

## Section F — Employee-wise weekly off: the list

#### WO-F01 · P1 · F — Empty list
- **Pre-condition:** S1.
- **How to test:** scroll to Employee-wise weekly off.
- **Expected (screen):** heading, `Set Off`, subtitle; the exact empty text `No employee-wise weekly offs yet. Everyone follows the "For everyone" weekly off above.`; **no** footer count.
- **Check in DB:** DB2 → 0 rows.

#### WO-F02 · P1 · F — List with two employees 📷
- **Pre-condition:** S3.
- **How to test:** read both rows and the footer.
- **Expected (screen):** Asha — `Fri off`, `6 working days`, `Edit`; Bala — `Mon & Sun off`, `5 working days`, `Edit`; footer `2 employees have a different weekly off`.
- **Expected (API):** `GET overrides` returns both, each with `employeeName`, `current`, `next`.
- **Check in DB:** DB2 → two open rows.

#### WO-F03 · P2 · C — Footer with exactly one employee
- **Pre-condition:** S2.
- **Expected (screen):** one row; footer reads exactly `1 employee has a different weekly off`.

#### WO-F04 · P1 · F — Scheduled change visible on the row
- **Pre-condition:** Asha `{5}` now, `{6}` from T+7.
- **Expected (screen):** her row shows `From <date>: Sat off`.
- **Check in DB:** DB2 → `[T,T+7)` `{5}` and `[T+7,)` `{6}`.

#### WO-F05 · P2 · C — Employee with no name
- **How to test:** (test tenant) employee whose name is empty.
- **Expected (screen/API):** shows the phone number with a **single** `+` (e.g. `+918528529632`, never `++91…`); if neither exists, `Unknown employee`.

#### WO-F06 · P2 · C — Long names and many people
- **How to test:** employee name of 60 characters; 100 employee rules.
- **Expected (screen):** text is cut cleanly, nothing overlaps; list scrolls smoothly; footer count is right.

#### WO-F07 · P2 · C — Employee deactivated or deleted
- **How to test:** if the product has a way to deactivate an employee, do it for Asha and open the screen (otherwise skip that half). In SQL try `delete from users where id=':emp'`.
- **Expected:** screen does not crash (record whether the row stays); the hard delete is **refused** while Asha has weekly-off rows (foreign key `ON DELETE RESTRICT`, error `23503`; if another table's key refuses it first, note which).

---

## Section G — Set / Edit an employee's weekly off (sheet)

#### WO-G01 · P1 · F — Open the add sheet 📷
- **How to test:** tap `Set Off`.
- **Expected (screen):** sheet `Set weekly off`; `Pick an employee`; seven pills with Sunday shown off; hint `Starting today (<date>) if you leave it blank`; Save disabled with `Choose an employee to save.`

#### WO-G02 · P1 · C — Who can be picked
- **How to test:** open the picker.
- **Expected (screen):** Asha, Bala, Chitra are listed; **Dev (invited)** is not.  (With no employees `Set Off` is disabled, so the sheet can't be opened — see WO-Q07.)

#### WO-G03 · P1 · C — Save needs a deliberate day choice
- **How to test:** pick Chitra; do not touch pills; check Save; then tap Sunday off and on.
- **Expected (screen):** Save disabled until a pill is touched; after the off→on touch Save is **enabled** (Sunday-only is then savable).

#### WO-G04 · P0 · F — Add: Friday only 📷
- **Pre-condition:** S1.
- **How to test:** 1) `Set Off`. 2) Pick Chitra. 3) Untap Sunday, tap Friday. 4) Save.
- **Expected (screen):** sheet closes; Chitra's row `Fri off`, `6 working days`; banner `Employee weekly off saved`; footer `1 employee…`.
- **Expected (API):** `PUT overrides/<Chitra> {"days":[5]}` → 200 with `employeeName`.
- **Check in DB:** DB2 → one row for Chitra `[T,)` `{5}`. DB1 unchanged.

#### WO-G05 · P0 · F — Employee rule replaces, not adds to, the everyone rule
- **Pre-condition:** everyone `{7}`; Chitra `{5}`.
- **How to test:** run DB5 for Chitra and for Asha, once with a **Sunday** date and once with a **Friday** date (both on/after T).
- **Expected (DB):** Chitra: Sunday → `false` (a **working** day for her), Friday → `true`. Asha: Sunday → `true`, Friday → `false` **only while Asha has no rule of her own**; if she has one, her rule replaces the everyone rule, so use her rule's days (corrected 2026-10-19, R-06).

#### WO-G06 · P0 · C — "Works all seven days" for one person
- **Pre-condition:** everyone has Sunday off.
- **How to test:** `Set Off` → Chitra → untap every day → Save.
- **Expected (screen):** hint `Pick at least one day off — or leave it empty if Chitra works all 7 days.`; Save enabled; row shows `No day off`, `7 working days`.
- **Check in DB:** DB2 → one open row `days={}` (a marker row **is** stored here); DB5 for Chitra on a Sunday date → `false` (works), and DB5 for Asha on the same Sunday → `true`.

#### WO-G07 · P0 · N — Seven days for one person
- **How to test:** select all seven pills in the sheet; try Save; call `PUT overrides/<id> {"days":[1..7]}`.
- **Expected (screen):** notice `Pick at least one working day — a full week off isn't allowed.`; Save disabled.
- **Expected (API):** `422 ATTENDANCE_NO_WORKING_DAYS`.
- **Check in DB:** unchanged; a direct insert of seven days fails `23514`.

#### WO-G08 · P1 · F — Add with a future start
- **How to test:** Chitra `{5}` from T+5.
- **Expected (screen):** hint `Starting <date>`; after Save the row shows the scheduled change `From <date>: Fri off` — and, because nothing applies today, also `No day off` / `7 working days` (suspected defect SD-8).
- **Check in DB:** DB2 → only `[T+5,)` — **no row covering today**; DB5 for Chitra on a Friday before T+5 → `false`, and on a Friday from T+5 → `true`.

#### WO-G09 · P1 · F — Open an existing rule
- **Pre-condition:** S2.
- **How to test:** tap `Edit` on Asha.
- **Expected (screen):** `Edit weekly off`, subtitle `Asha`; Friday pre-selected; employee cannot be changed; `Remove weekly off` visible; Save disabled.

#### WO-G10 · P1 · F — Edit days
- **How to test:** Friday → Friday + Saturday; Save.
- **Expected (screen):** row `Fri & Sat off`; banner `Employee weekly off saved`.
- **Check in DB:** open range from T now `{5,6}`; earlier history (if any) unchanged; DB4b → 0.

#### WO-G11 · P1 · C — Edit but change nothing
- **How to test:** toggle a pill and toggle it back.
- **Expected (screen):** Save disabled (no pointless re-save).

#### WO-G12 · P1 · C — Change only the date of an existing rule
- **Pre-condition:** run it twice: (a) S2 — Asha has no queued change; (b) Asha `{5}` now + `{6}` queued for T+7.
- **How to test:** keep the days, change only the date (a: to T+4; b: to T+10); look at Save; if enabled, Save.
- **Expected (screen):** (a) by the code Save stays **disabled** (the date counts as a change only when a queued change exists; the same days from a later date would change nothing). The 15-6 review promised "a date-only reschedule can be saved" — if you expected Save enabled in (a), log it as **SD-13**. (b) Save is **enabled**; after Save the pills' days (`{5}`) start at T+10 and the old `{6}` is clipped to end at T+10; read the row and compare it with DB2.
- **Check in DB:** (b) Asha's `{5}` range runs to T+10, the queued `{6}` range is clipped to end at T+10 (it keeps T+7→T+10), a new `[T+10,)` `{5}` exists; DB4b → 0.

#### WO-G13 · P1 · C — Replace a scheduled change
- **Pre-condition:** Asha `{5}` now + `{6}` from T+7.
- **How to test:** Edit; set `{4}` from T+7; Save.
- **Expected (DB):** only one range from T+7 `{4}`; DB4b → 0.

#### WO-G14 · P1 · C — Close without saving
- **How to test:** change pills, swipe the sheet down / tap outside; reopen.
- **Expected (screen):** no request sent; reopened sheet shows saved state, not the abandoned edits.

#### WO-G15 · P2 · C — No old error in a reopened sheet
- **How to test:** cause a failed save (airplane), close the sheet, reopen it with network on.
- **Expected (screen):** no leftover error banner.

#### WO-G16 · P0 · C — Double tap Save in the sheet
- **How to test:** tap Save twice quickly.
- **Expected (API):** exactly one PUT. **Check in DB:** one change; DB4b → 0.

#### WO-G17 · P1 · N — Save fails in the sheet
- **How to test:** airplane on; Save.
- **Expected (screen):** error inside the sheet; selection kept; sheet stays open; retry works.
- **Check in DB:** unchanged until success.

#### WO-G18 · P0 · N — Someone else's employee / bad id (API)
- **How to test:** `PUT overrides/<Esha (tenant B)>`, `PUT overrides/<random valid uuid>`, `PUT overrides/abc`.
- **Expected (API):** first two → `404 ATTENDANCE_EMPLOYEE_NOT_FOUND`; third → `400`.
- **Check in DB:** no row for Esha or the random id (tenant isolation).

#### WO-G19 · P2 · N — Employee removed after picking
- **How to test:** pick Chitra in the sheet; remove her via API/SQL (or deactivate); Save.
- **Expected (screen):** inline error; picker usable again; no crash.
- **Check in DB:** no new row.

#### WO-G20 · P2 · C — Picker round trip
- **How to test:** set pills, open the picker, come back without choosing; then choose someone.
- **Expected (screen):** pills and date are kept; chosen name appears; reopening the sheet later starts clean.

#### WO-G21 · P1 · C — Saving twice on the same day
- **How to test:** Chitra `{5}`, then Chitra `{6}` the same day.
- **Expected (DB):** one open range `{6}`; DB4b → 0.

#### WO-G22 · P2 · N — Employee already has a rule
- **How to test:** `Set Off` → pick Asha (who has one) → save a different rule.
- **Expected:** record behaviour (it should replace Asha's rule from the chosen date, never create overlap).
- **Check in DB:** DB4b → 0.

---

## Section H — Remove an employee's weekly off

#### WO-H01 · P1 · F — Confirmation dialog
- **Pre-condition:** S2.
- **How to test:** Edit Asha → `Remove weekly off`; then choose cancel.
- **Expected (screen):** dialog titled `Remove weekly off` naming Asha and saying she goes back to the everyone schedule; cancel keeps the rule and the sheet.

#### WO-H02 · P0 · F — Remove 📷
- **How to test:** same, but confirm `Remove`.
- **Expected (screen):** sheet closes; Asha's row disappears; footer updates (no footer when none left); banner `Employee weekly off removed`.
- **Expected (API):** `DELETE` → 200, `current:null`.
- **Check in DB:** with S2 (the rule started today) Asha's row is **deleted**; if the rule started earlier it is **clipped at T** (see WO-Q01/Q02). Nothing is inserted either way; DB5 for Asha on a Friday from T → `false` (no longer her own off day) and on a Sunday from T → `true` (everyone rule); ranges **before** T are kept.

#### WO-H03 · P1 · C — Remove twice
- **How to test:** `DELETE` the same employee again.
- **Expected (API):** 200 (no-op, no error). **Check in DB:** unchanged.

#### WO-H04 · P1 · C — Remove when a future change is queued
- **Pre-condition:** Asha `{5}` now and `{6}` from T+7.
- **How to test:** Edit → Remove → confirm.
- **What the code does:** the Edit sheet seeds its date field with the queued date (T+7), the confirm text reads `Asha will follow the "For everyone" weekly off from <T+7 date>.`, and Remove sends `DELETE …?effectiveFrom=T+7`.
- **Expected (DB):** Asha's current `{5}` range is clipped at **T+7** and the queued `{6}` range is deleted; DB5 for Asha: a Friday before T+7 → `true`; a Friday from T+7 → `false` and a Sunday from T+7 → `true` (everyone rule).
- **Expected (screen):** row stays until T+7 (still `Fri off`, with no `From …` line). If instead the owner expected the rule to stop **today**, report **SD-5**. To remove from today, clear the date field first (or set it to today) then Remove — check the confirm text says `from today`.

#### WO-H05 · P2 · C — Remove from a future date (API)
- **How to test:** `DELETE …/overrides/$EMP?effectiveFrom=<T+10>`.
- **Expected (DB):** range `[…,T+10)`; DB5 for a Friday on/before T+9 → `true`; a Friday from T+10 → `false`.

#### WO-H06 · P1 · N — Remove fails
- **How to test:** airplane on; confirm Remove.
- **Expected (screen):** error shown; sheet stays; row still listed; retry works.
- **Check in DB:** unchanged until success.

#### WO-H07 · P1 · N — Already removed elsewhere
- **How to test:** delete Asha's rule by API, then confirm Remove in the stale sheet.
- **Expected (screen):** the remove is idempotent (the API returns 200 for a person who is still in the company), so it **succeeds**: sheet closes, banner `Employee weekly off removed`, list matches the server. An error here would be a defect. (A 404 appears only if the person left the company — see WO-G19.)

#### WO-H08 · P1 · C — Double tap Remove / Remove while saving
- **Expected (API):** one DELETE; Remove and Save are not tappable while a save is running.

#### WO-H09 · P2 · C — Remove worked but reload failed
- **Expected (screen):** treated as success (dialog and sheet close).

#### WO-H10 · P1 · N — Bad / foreign ids (API)
- **How to test:** DELETE for Esha (tenant B), a random uuid, `abc`.
- **Expected (API):** `404`, `404`, `400`. **Check in DB:** unchanged.

---

## Section I — API contract and security

| ID | Pri | Type | Test | How | Expected |
|---|---|---|---|---|---|
| WO-I01 | P0 | F | Shapes | `GET weekly-offs`, `GET …/overrides` for empty and filled tenants | 200; `{default,next,history}` (history ascending) and an array; empty is 200, never 404 |
| WO-I02 | P0 | N | No/invalid token | call each route with no token, an expired token, garbage | `401` |
| WO-I03 | P0 | N | Technician | all 5 routes with `$TECH` | `403` each; DB unchanged |
| WO-I04 | P0 | N | Tenant isolation | Owner B calls GET/PUT/DELETE; try putting `tenantId` of A in the body or query | Owner B only ever sees/changes tenant B; injected ids ignored; DB1/DB2 of A unchanged |
| WO-I05 | P1 | N | Unknown body fields | `PUT {"days":[7],"tenantId":"…","validFrom":"2020-01-01"}` | extra fields ignored or `422`; never applied; no past range |
| WO-I06 | P1 | N | Wrong content | send form data / text body / empty body | `4xx`, no write |
| WO-I07 | P1 | N | Injection | `effectiveFrom="2026-10-19'; drop table x;--"`, id `' or 1=1`, HTML in text | `4xx`; tables intact; nothing stored |
| WO-I08 | P1 | C | Burst | 50 rapid PUTs with alternating days | all 200 (or throttled); final state valid; DB4 → 0; no `23P01` in any body |
| WO-I09 | P0 | C | Two PUTs at the same instant | fire two PUTs in parallel | both succeed one after the other; one open range; DB4 → 0 |
| WO-I10 | P1 | N | Error body | trigger 422/404/400 | has `error_code`; no stack trace, SQL text or secrets |
| WO-I11 | P1 | C | Self-consistent responses | compare PUT response with the next GET | same data |
| WO-I12 | P2 | F | Headers | check logs for correlation/session ids on each call | present |
| WO-I13 | P1 | N | Malformed ids | `:employeeId` = `abc`, 200 characters, a uuid with one wrong character; and an empty id (`…/overrides/`) | `400` for the first three; empty id does not match a PUT/DELETE route → `404`; never a 500 |
| WO-I14 | P2 | C | Method misuse | `POST`/`PATCH` on the routes | `404`/`405`, no write |

## Section J — Database checks (direct)

| ID | Pri | Test | How | Expected |
|---|---|---|---|---|
| WO-J01 | P0 | Locked down tables | `select relrowsecurity from pg_class where relname in ('attendance_weekly_off_defaults','attendance_weekly_off_overrides')` and `select * from pg_policies where tablename like 'attendance_weekly_off%'` | RLS **true**; **0 policies** |
| WO-J02 | P0 | No direct client access | read both tables via PostgREST with the anon key and with an employee token | empty or denied; no data |
| WO-J03 | P0 | RPCs closed to clients | First list the real signatures: `select p.oid::regprocedure from pg_proc p where proname like 'attendance_%weekly_off%'`. Then for each, `select has_function_privilege('anon', '<signature>', 'execute')` (repeat for `authenticated` and `service_role`) | false / false / **true**; direct call → `42501` |
| WO-J04 | P1 | Day-number check | insert `days='{8}'`, `'{0}'` | fails `23514` |
| WO-J05 | P0 | Seven-day check | insert 7 days | fails `23514` |
| WO-J06 | P1 | Empty range check | insert `valid='empty'::daterange` | fails |
| WO-J07 | P0 | No overlap | insert an overlapping range for the same tenant / same employee | fails `23P01`; different tenant or employee is allowed |
| WO-J08 | P0 | Employee must belong to tenant | insert an override for tenant A with an employee of tenant B | fails `23503` |
| WO-J09 | P1 | Tenant removal | on a **throwaway** tenant, delete the tenant | its weekly-off rows disappear (if other tables block the delete, note it and skip) |
| WO-J10 | P2 | `updated_at` trigger | update a row | `updated_at` moves; other rows don't |
| WO-J11 | P1 | Sorted and unique | API `[7,6]` | stored `{6,7}` |
| WO-J12 | P0 | Save algorithm | cases C02, C03, C05, C06, C07 | past date clamps to T; covering range's end clipped; ranges starting on/after the date deleted; new open range inserted |
| WO-J13 | P0 | Empty-days difference | B05 vs G06 | everyone rule `[]` → **no row**; employee rule `[]` → **marker row** that beats the everyone rule |
| WO-J14 | P0 | Remove algorithm | H02, H03, H05 | clip at date, nothing inserted, second call no-op, history before kept |
| WO-J15 | P1 | Locking | I09 | no deadlock, no overlap |
| WO-J16 | P1 | Function hardening | `select proname, prosecdef, proconfig from pg_proc where proname like 'attendance_%weekly_off%'` | `prosecdef=true`; `search_path=public` set |
| WO-J17 | P1 | Long random sequence | run 30 random saves/removes (mix of dates) | DB4 and DB4b → 0 rows; days arrays valid; no row before T created |
| WO-J18 | P1 | Unknown tenant | `select attendance_today('00000000-0000-0000-0000-000000000000')` | error `PT404` / `ATTENDANCE_TENANT_NOT_FOUND` |
| WO-J19 | P2 | Other time zone | on a throwaway tenant set a time zone with a different date than IST | DB3 follows it; screen follows it |
| WO-J20 | P2 | Advisors | Supabase `get_advisors` security + performance | no new error for these tables |

## Section K — Usability, accessibility and resilience

| ID | Pri | Type | Test | How | Expected |
|---|---|---|---|---|---|
| WO-K01 | P2 | C | Large text | system font 130% and 200% | nothing clipped; drawings never cover text (known risk, section O) |
| WO-K02 | P2 | C | Small phone / split screen | 360 dp width, split-screen | no overlap; Save reachable by scrolling |
| WO-K03 | P3 | C | Dark mode (if supported) | switch theme | readable, drawings still faint |
| WO-K04 | P2 | F | TalkBack order | swipe through the screen | every control has a name; the reading order follows the visual order top to bottom (record any jump) |
| WO-K05 | P3 | C | Rotation | rotate with the sheet open | no crash, no lost selection |
| WO-K06 | P1 | C | App killed mid-edit | change pills, kill app, reopen | clean screen; no half-saved data (DB1 unchanged) |
| WO-K07 | P1 | N | Offline start | airplane mode before opening | clear error, never an endless spinner |
| WO-K08 | P2 | C | Slow network | 3G throttle | placeholders then data; buttons show loading; no double submit |
| WO-K09 | P1 | F | Plain wording | read every string against section 4 | plain business English, sentence case, no jargon, no Hindi words; disabled Save always says why. **Known exception to check:** the owner-facing error `Couldn't load overrides. Check your connection and try again.` uses the word "overrides" — against the plain-English rule (SD-12) |
| WO-K10 | P2 | C | Success banner | save 3 times quickly | one banner at a time, disappears by itself, not stacked |
| WO-K11 | P2 | F | Sheet vs keyboard | open sheet; use system back gesture | sheet closes first, not the whole screen; nothing hidden under system bars |
| WO-K12 | P3 | C | Repeat open/close | open and close the screen 20 times | no slowdown or growth; smooth scrolling with 100 employee rules |
| WO-K13 | P2 | C | Pull to refresh | pull on both short and long content | spinner stops, also after a failure |

## Section M — Downstream spot checks (only if day statuses can be read for the test tenant)

| ID | Pri | Test | Expected |
|---|---|---|---|
| WO-M01 | P0 | Everyone `{7}`; an employee with no own rule; a Sunday | shows **Weekly off** |
| WO-M02 | P0 | Asha own `{5}`, everyone `{7}` | Asha: Friday Weekly off, Sunday a **working** day; Bala unchanged |
| WO-M03 | P0 | Chitra own `{}` | Chitra never has a weekly off; others keep Sunday |
| WO-M04 | P1 | Rule changed from a future date | past dates keep old schedule; dates on/after use the new one |
| WO-M05 | P1 | Employee rule removed from T | follows the everyone rule from T; earlier dates keep old status |
| WO-M06 | P1 | Weekly off and holiday on the same day, no check-in | **Weekly off** wins |
| WO-M07 | P2 | Check-in on a weekly-off day | counted as worked on an off day, no Late flag |

---

## Section Q — Added after the code review (BE + DB + app)

I read the backend service, the three RPCs, the table migrations and the app hooks and sheets, and compared them with sections A–M. These cases cover behaviour the code has that the cases above did not.

### Q1. Added cases

#### WO-Q01 · P0 · C — Remove an employee rule that started BEFORE today 📷
- **What to test:** the row must disappear after Remove when the rule began on an earlier day. The RPC keeps the past part (clips at T instead of deleting), so the backend still lists the employee.
- **Pre-condition:** S0 + `insert into attendance_weekly_off_overrides (tenant_id, employee_id, valid, days) values (':tenant', ':asha', daterange(current_date - 10, null), '{5}')` (use T−10 from DB3).
- **How to test:** 1) Open the screen; Asha shows `Fri off`. 2) Edit → clear the date field (or choose today) → `Remove weekly off` → `Remove`. 3) Check the list. 4) `GET …/overrides`.
- **Expected (screen):** Asha's row **disappears**; footer gone or count reduced; banner `Employee weekly off removed`. A row that stays and says `No day off` / `7 working days` is **SD-6** (section Q2).
- **Expected (API):** per the code, the response is `{current:null,next:null}` and the list endpoint keeps returning Asha with `current:null,next:null`.
- **Check in DB:** DB2 → Asha's range is now `[T-10,T)` (kept as history, ended today). DB5 for Asha on a Friday from T → `false`; on a Friday before T → `true`.

#### WO-Q02 · P1 · C — Remove an employee rule that started TODAY
- **How to test:** create a rule today (G04), then Remove it the same day.
- **Expected (DB):** the row is **deleted completely** (it starts on/after T), DB2 → 0 rows for Asha; row gone from the screen.

#### WO-Q03 · P1 · C — Employee with only past ranges in the list API
- **How to test:** after Q01, call `GET …/overrides`.
- **Expected (API):** note whether the removed employee is returned with `current:null,next:null`; the app must not show them (see Q01).

#### WO-Q04 · P1 · F — Remove message wording
- **How to test:** Edit an employee with no queued change; tap Remove; read the dialog. Repeat with a date set in the field.
- **Expected (screen):** `<Name> will follow the "For everyone" weekly off from today.` / `… from <long date>.`; buttons `Remove` and `Cancel`; while the request runs the dialog shows a busy state.

#### WO-Q05 · P1 · C — Remove from the date shown in the sheet
- **How to test:** Edit an employee, change the date field to T+5, Remove → confirm.
- **Expected (API):** `DELETE …?effectiveFrom=T+5`. **Expected (DB):** range ends at T+5; DB5 for a Friday up to T+4 → `true` (own rule); a Friday from T+5 → `false`.

#### WO-Q06 · P1 · N — Cannot set a weekly off for an employee who is not active (app) — but the API allows it
- **How to test:** open the picker; confirm invited Dev is missing. Then by API: `PUT overrides/<Dev> {"days":[5]}`, `PUT overrides/<Owner A's own id> {"days":[5]}`.
- **Expected:** picker lists active employees only. API: both calls return **200** (the RPC only checks "member of this tenant"); the rows exist in DB2. Record this as an API/app mismatch (the app is stricter than the API), not a failure.
- **Check in DB:** DB2 rows exist for Dev and for the owner.

#### WO-Q07 · P1 · F — `Set Off` is disabled and says why (three messages)
- **How to test:** use three tenants (or toggle data): (a) while the team is still loading, (b) a company with **no** employees, (c) a company with only invited employees.
- **Expected (screen):** the button looks dimmed and cannot be tapped; an info notice shows: (a) `Loading your team…` (b) `No employees yet. Add an employee first, then set their weekly off here.` (c) `No active employees yet. Employees become active after they sign in to the app for the first time — then you can set their weekly off here.`

#### WO-Q08 · P1 · F — Employee picker screen
- **How to test:** tap `Set Off` → `Pick an employee`. In the picker: tap one row; tap another row; tap Apply; also test Back and the clear action without applying.
- **Expected (screen):** one selection at a time (tapping another row **replaces** it); `Apply selection` is disabled until one row is selected; after Apply you return to Weekly off and the sheet opens with that person; Back keeps the sheet's previous state and does not pick anyone; only active employees listed.

#### WO-Q09 · P2 · C — Team list is not refreshed by pull-to-refresh
- **How to test:** while the screen is open, have a new employee sign in for the first time (become active); pull to refresh on Weekly off; tap `Set Off`.
- **Expected:** record whether the new employee is offered. By the code the roster comes from the cached profile, not from the weekly-off requests (suspected stale roster, **SD-7**).

#### WO-Q10 · P1 · C — Open an employee rule that has only a FUTURE part
- **Pre-condition:** Chitra rule `{5}` starting T+5 only (G08).
- **How to test:** tap Edit on Chitra.
- **Expected (screen):** row shows `No day off`, `7 working days` and the `From <date>: Fri off` line (the current rule is null); the sheet opens with all pills `Work`, the date field = T+5. Record exactly (a row that says "No day off" for someone who really follows the everyone rule today is **SD-8**).

#### WO-Q11 · P1 · C — Clear all days with a FUTURE date (queued "no weekly off")
- **Pre-condition:** S1.
- **How to test:** untap Sunday, set the date to T+7, Save. Read Upcoming; run DB1.
- **Expected (DB):** the Sunday range is clipped at T+7 and **no new row** is inserted. **Expected (screen):** nothing in Upcoming describes the change (history has no future row) — record it (**SD-9**: a scheduled clear is invisible).

#### WO-Q12 · P1 · C — Clear today when the rule started earlier
- **Pre-condition:** S0 + a default `[T-30,)` `{7}` via SQL.
- **How to test:** clear all days, Save.
- **Expected (DB):** row becomes `[T-30,T)`; `GET weekly-offs` → `default:null`, `next:null`, `history` still contains the past row.

#### WO-Q13 · P2 · C — Clearing twice
- **How to test:** `PUT {"days":[]}` twice. **Expected:** both 200; state unchanged after the first.

#### WO-Q14 · P0 · C — A rule that started today is replaced, not duplicated
- **How to test:** S1 saved today; change to `{6}` with date today; Save.
- **Expected (DB):** the earlier row (which starts on T) is **deleted**, one row `[T,)` `{6}`; no `[T,T)` empty range (empty ranges violate the check).

#### WO-Q15 · P1 · C — Saving a rule on the exact start day of a queued change
- **How to test:** queue `{6}` at T+7; save `{5}` with date T+7. **Expected (DB):** one range at T+7 `{5}`; the current rule clipped at T+7 (covered by C05; assert the previous range's `valid` upper bound = T+7).

#### WO-Q16 · P1 · F — Day names and wording for 3+ and 6 days
- **How to test:** save `{1,2,3}`, then `{1,2,3,4,5,6}`.
- **Expected (screen):** `Right now: Mon, Tue & Wed off`, then `Right now: Mon, Tue, Wed, Thu, Fri & Sat off`; employee row for 3 days `Mon, Tue & Wed off` with `4 working days`.

#### WO-Q17 · P2 · F — Employee list order
- **How to test:** create rules for employees named `bala`, `Asha`, `Chitra`, `Zoya`, `Éla`.
- **Expected (screen/API):** alphabetical by name (locale compare); ties stable; record how lowercase/accented names sort.

#### WO-Q18 · P2 · C — Employee name fallbacks
- **How to test:** employee with `name` empty → phone shown (`+91…`, single `+`); employee whose user row is missing from the tenant (moved) → `Unknown employee`; avatar initial for `Unknown employee` is `U`, for a blank name `?`.

#### WO-Q19 · P1 · C — Sheet reopened after a save
- **How to test:** save Chitra, then `Set Off` again immediately.
- **Expected (screen):** sheet starts empty (no employee picked, Sunday suggestion, blank date, no old error). Employee picked earlier does **not** stay selected.

#### WO-Q20 · P1 · C — Edit sheet seeds the date from the queued change
- **Pre-condition:** Asha `{5}` now, `{6}` from T+7.
- **How to test:** tap Edit.
- **Expected (screen):** pills show the **current** rule `{5}`, the date shows T+7, helper `Starting <T+7 date>`, Save disabled; changing only a pill (days) enables Save and the save goes from T+7. Record what the owner would expect (does the sheet show the queued rule or the current one?).

#### WO-Q21 · P2 · C — Large history
- **How to test:** make 150 changes (script the API with future dates). Open the screen.
- **Expected:** opens in a reasonable time; Upcoming lists every future change in order with correct "Till then" chaining; no crash. `GET` returns the whole history (it is not paged).

#### WO-Q22 · P2 · C — Long-running screen refreshes the tenant day
- **How to test:** leave the screen open, then background the app for several minutes and come back (also across IST midnight if possible).
- **Expected:** the date field's minimum and the Upcoming cut-off follow the new day; the date field keeps the owner's chosen date.

#### WO-Q23 · P2 · N — Weekday number mapping (Sunday is 7, Monday is 1)
- **How to test:** save only Sunday; run DB5 for a known Sunday date and for a Monday date.
- **Expected (DB/downstream):** Sunday date → `true`; Monday date → `false`. Also check the app's pills: first pill `M`, last `S` = Sunday.

#### WO-Q24 · P1 · N — DB functions called directly (service role / SQL)
- **How to test (throwaway tenant):** call the default RPC with `p_days = null`; with `{9}`; with `{7,7}`; with `{}` and a past date; call the override RPC for an employee of another tenant.
- **Expected (DB):** `null` is treated as **empty** (it clears — note it); `{9}` fails `23514` (the API would label this as no-working-days; DTO blocks it first); `{7,7}` stores `{7}`; past date clamps to T; other tenant's employee → `PT404`/`ATTENDANCE_EMPLOYEE_NOT_FOUND`.

#### WO-Q25 · P1 · C — Delete route with a date
- **How to test:** `DELETE …/overrides/$EMP?effectiveFrom=<bad>` (`2026-02-30`, `abc`, two `effectiveFrom` params).
- **Expected (API):** `422 VALIDATION_ERROR` for the bad dates; two params → record (must not 500). **Check in DB:** unchanged.

#### WO-Q26 · P1 · N — Remove for an employee who never had a rule
- **How to test:** `DELETE` for Bala who has no rows.
- **Expected (API):** 200 with `current:null,next:null`. **Check in DB:** no row created.

#### WO-Q27 · P2 · C — Audit trail
- **How to test:** after a change, look for who/when in the tables.
- **Expected:** there is **no** "changed by" column (the actor id was dropped on purpose); `created_at`/`updated_at` are the only trace. Record as a known limitation.

#### WO-Q28 · P2 · C — Two screens, same owner
- **How to test:** open the screen on two devices; save on one; pull to refresh on the other.
- **Expected:** second device shows the new `Right now` and Upcoming; pills per SD-1.

#### WO-Q29 · P1 · C — Save from a stale screen wipes a queued change made elsewhere
- **What to test:** a second device queued a change that this screen does not know about.
- **How to test:** device 1 has the screen open (no queued change shown). Device 2 (or the API) queues `{6}` from T+7. On device 1, without refreshing, change a pill and Save with the date T+3.
- **Expected (DB):** the save deletes every range that starts on/after T+3 — so device 2's `{6}` (T+7) is **deleted**, the covering range is clipped at T+3 and the new `{…}` starts at T+3. No error is shown to either owner. Record it as a known last-write-wins behaviour; the DB4 check must still return 0 rows.

#### WO-Q30 · P2 · C — Cold start straight into Weekly off with no history stack
- **How to test:** (if a deep link exists) open `AttendanceWeeklyOff` directly, tap back.
- **Expected (screen):** goes to the main tabs (fallback), no crash.

### Q2. Suspected defects found by reading the code — confirm on the device and log as FAIL/PASS

| ID | Suspicion | Why (code) | Confirm with |
|---|---|---|---|
| SD-1 | After the server rule changes elsewhere, pull-to-refresh / re-focus updates `Right now` but **not the pills** | the form is seeded once (`hasLoadedRef`) | WO-A08, A09 |
| SD-2 | After clearing all days and saving, the screen shows **Sunday off** again and the "never configured" helper | `fresh.default` is null → `[SUNDAY]`; `neverConfigured` true | WO-B05, Q12 |
| SD-3 | After scheduling a future change, pills snap back to the current rule instead of showing what was scheduled | re-seed from `fresh.default` | WO-C03 |
| SD-4 | Changing only the date of a queued change does not move the queued rule; it saves the pills' days from the new date | RPC deletes ranges on/after the date and clips the covering one | WO-C04b |
| SD-5 | Removing an employee rule that has a queued change removes only from the queued date (not today) because the sheet seeds the date | `useOverrideRemove` passes the field date | WO-H04, Q05 |
| SD-6 | After removing a rule that began before today, the employee may still appear as `No day off · 7 working days` | RPC keeps `[start,T)`; list endpoint still returns the employee; the row component shows every item | WO-Q01 |
| SD-7 | Newly active employees are not offered until the cached profile refreshes | roster from `useMyProfile` | WO-Q09 (confirmed, R-24) |
| SD-8 | Employee with only a future rule shows `No day off` today | `viewDays(null)` → `[]` | WO-Q10 |
| SD-9 | A queued "clear" (no weekly off from a future date) is invisible in Upcoming | clear inserts no row | WO-Q11 |
| SD-10 | Any database check failure on the save (for example a day outside 1–7 sent straight to the database) is reported as `ATTENDANCE_NO_WORKING_DAYS` | the service maps every `23514` to that code | WO-Q24 |
| SD-11 | On a never-configured company, touching Sunday off and on enables Save (spec says it should stay disabled) | baseline for a never-configured company is `[]`, the pills show `[7]` | WO-A02 |
| SD-12 | Error text `Couldn't load overrides…` uses jargon the owner never sees elsewhere (the rest says "employee-wise weekly off") | `WeeklyOffOverridesSection` | WO-A06, K09 |
| SD-13 | Date-only change on an existing employee rule with no queued change can't be saved (the 15-6 review promised it could) | `effectiveDateChanged` needs a queued change | WO-G12 |

---

## Section N — Suggested order
1. **Smoke (30 min):** A01, A03, B01, B04, C03, D01, F02, G04, H02, I03, J01.
2. **Screen functional:** sections A → H on the phone (reset with clean-up SQL between groups).
3. **API and DB:** sections I, J and Q.
4. **Non-functional:** K. 5. **Downstream:** M.

## Section O — Known gaps (record; do not report as new defects)
From `deferred-work.md` (2026-10-18) and the specs:
- Day pills ≈39 dp wide on 360 dp phones (documented exception).
- Background drawings use fixed sizes; may touch the badge at large font, tablets, split-screen.
- Date field announces `Date: …` (no accessibility label).
- Every `Edit` button reads just "Edit" to screen readers.
- Upcoming row says `Till then: No day off` when nothing was ever configured.
- iOS has no live announcement for the day-count chip.
- No technician navigation gate; their 403 shows generic "Check your connection" copy.
- Upcoming panel is read-only (no cancel button).
- Save response is read outside the lock; a simultaneous owner write can show in another owner's response (next read is right).

## Section P — Report template
```
Run date / app build / device / tenant id:
Totals: PASS n · FAIL n · BLOCKED n
FAIL list:   ID — expected vs actual — evidence
New defects (not in section O):
DB invariants (2.4) broken at: (case ids) or "none"
```

---

## Section R — Defects found in run 2 (open, for later fixing)

Logged from the 2026-10-18 device and API run. Expected results above were **not** changed. Results are in `test-results-weekly-off-screen-2026-10-18.md`. Each entry names the layer that should own the fix (FE = `fenzit-app`, BE = `fenzit-be`, DB = migration/RPC), per the project rule to fix the owning layer.

| ID | Case(s) | Status | Summary | Owner layer | Evidence |
|---|---|---|---|---|---|
| R-01 | WO-B02 (also SD-11, WO-A02) | **Fixed, verified on device 2026-10-19** (FE `6f4921b`) (was: Open) | On a never-configured company, tapping Sunday on then Saturday on/off returns the pills to Sunday-only, but **Save stays enabled** with no hint. Expected Save disabled. | FE (form baseline for a never-configured company should be "nothing saved", same as the Sunday suggestion rule) | `…/scratchpad/shots/WO-B02.png` |
| R-02 | WO-I10, WO-I03, WO-G18, WO-H10, WO-I13 | **Fixed, verified live 2026-10-19** (BE, c8c5968) (was: Open) | Every error body carries a `stack` field with server paths (`/app/dist/src/…`, line numbers), e.g. on 422 `ATTENDANCE_NO_WORKING_DAYS`, 403 `FORBIDDEN`, 404 `ATTENDANCE_EMPLOYEE_NOT_FOUND`, 400 `VALIDATION_ERROR`. | BE (one global exception filter: return only `error_code` and `message` outside dev) | API bodies in `test-results` run 2 |
| R-03 | WO-I13 | Fixed, verified live 2026-10-19 (BE `d9a938e`; shared router options and places e2e in BE `d5789d5` — a 256-char places id now gets the id-format 422, not 414) | A 200-character employee id returns **414** (URI too long) instead of **400**. The case expects 400. | BE (validate the id length in the route/pipe) or edge config; decide which layer returns 414 | curl `PUT …/overrides/aaaa…(200)` → 414 |
| R-04 | WO-G02 (API half), WO-Q07 | **Fixed, verified live 2026-10-19** (BE+DB, c8c5968; 422 `ATTENDANCE_EMPLOYEE_NOT_ACTIVE`) (was: Open) | `PUT overrides/<invited employee>` returns **200**. The app picker hides the invited employee, but the API accepts the write. | BE (the override service must require an active employee; the picker is only a UI guard) | Dev (`613690b6-…`, status `invited`) → 200 with `current.days=[5]` |
| R-05 | WO-I07 | Accepted 2026-10-19 (owner decision): the WAF HTML 403 for SQL-looking input is fine; nothing is stored. Clients should show a generic error for any non-JSON reply | A SQL-looking `effectiveFrom` and a SQL-looking id return a **Cloudflare WAF HTML 403 page**, not the API's JSON error shape. Nothing is stored (pass for "4xx, tables intact"), but clients get a non-JSON body. | Edge config (decide whether the WAF page is acceptable for API clients) | `<!DOCTYPE html>…` body on both calls |
| R-06 | WO-G05 | Resolved 2026-10-19: test expectation corrected (Sunday = working, `false`); product behaviour is right | The G05 expectation says Asha on a **Sunday** is `true` (off) while her employee rule covers that date. Section 2.2 says an employee rule **replaces** the everyone rule, so Sunday should be `false`. The expectation needs an owner decision; it was not changed. | Test case (not product) | DB5 output in run-2 log |
| R-07 | SD-3 (WO-C03) | **Fixed on device 2026-10-19** (FE `6f4921b`); owner decision R-07/R-20 still open (was: Confirmed earlier) | After scheduling a change, the pills snap back to Sunday-only while the rule is Sat & Sun. | FE (re-seed form only from the current rule and keep the queued change visible) | `test-results` smoke section |

**Not product bugs (test-run notes):** an unplanned Save during a B04 attempt wrote one `[18 Oct,) {7}` row; it was removed and the case was re-run from S0. Timing of the phone taps was corrected with a helper that taps the clickable pill, not the text inside it.

### R-08 to R-10 (found in the same run, added on review)

| ID | Case(s) | Status | Summary | Owner layer | Evidence |
|---|---|---|---|---|---|
| R-08 | WO-D03, WO-C10 | **Fixed, verified live 2026-10-19** (BE `bce1bd9`, one clear message per problem) (was: Open) | Validation messages are misleading. `{"days":{}}`-type bad input, `{}`, `null` and `"6,7"` all return 422 with the message `All days's elements must be unique` (plus the range message). The message names the wrong rule and mixes in unrelated text. The messages are raw class-validator output, not plain copy. | BE (validation messages: one clear message per field, plain English) | curl `PUT weekly-offs` with `{}` → 422, messages `["All days's elements must be unique", "each value in days must be one of…"]` |
| R-09 | WO-A01 (after login), general | **Fixed, verified on device 2026-10-19** (FE `6f4921b`) (was: Open) | After the OTP sign-in the keyboard stays open on the home screen and covers the bottom tab bar. Taps on the tabs do nothing until the keyboard is dismissed with Back. | FE (dismiss the OTP keyboard and focus when the screen changes) | Screenshot taken during the run (`…/scratchpad/shots/owner-home.png`); tap on Account at its measured centre had no effect until Back was pressed |
| R-10 | Login (OTP), tenant isolation | Deferred 2026-10-19 (owner decision: very rare corner case; not needed before launch). Planned fix when picked up: after OTP, if the number belongs to more than one company, return the list and show a company picker; remember the last choice; no in-app switch at first. Same issue as R-25 | The same phone number exists in two tenants (`9000000001`–`9000000003` belong to Cool Air and to tenant `792b28ed…`). OTP login with that number lands in whichever tenant it finds first. The `users` table has no uniqueness on phone within the same identity, so login is ambiguous. | DB (decide whether a phone is unique per account) + BE (login must choose or ask for the tenant) | Session after login: `{"role":"technician","tenantId":"792b28ed…"}` for number `9000000001`; the Cool Air user `Asha` has the same number |

**Also recorded (already in the list above):** R-01 consequence: because Save stayed enabled, one tap wrote an unplanned `{7}` row during the run. R-02 also covers 403, 404 and 400 bodies.

**Not run, so no defects recorded:** WO-A04–A12, B05–B10, C01–C14 (except C01–C03 smoke), D01–D12 (except the smoke), E01–E07, F01–F07, G01, G03, G05 (UI), G08–G22, H01, H03–H09, I02 (expired token), I07 (WAF only, see R-05), I10 (see R-02), J02, J03 (direct-call part), J07 onward, K01–K13, M, Q01–Q30, SD-1, SD-2, SD-4 to SD-13. These are open, not passing.

### R-11 (found by WO-B05, confirms SD-2)

| ID | Case(s) | Status | Summary | Owner layer | Evidence |
|---|---|---|---|---|---|
| R-11 | WO-B05 (SD-2) | **Fixed, verified live and on device 2026-10-19** (BE+DB `b6b0846`: `configured` flag, FE `6f4921b`) (was: Open) | Untap Sunday (no day off) and Save. The database correctly stores no everyone-rule row, but after the save the screen goes back to the never-configured helper with **Sunday shown Off** and chip `1 day off, 6 working days`. The owner's saved choice ("everyone works all 7 days") is not shown. The `Weekly off saved` banner was not seen in the dump (it may have gone within the 1.5 s window; not proven either way). | FE (re-seed the form from the saved state, not from the "no row" default) + BE/API (decide how "no row" and "empty days" are represented, so the client can tell "works all 7 days" from "never configured") | DB: no rows after save. UI texts after save: `No weekly off set yet…`, `1 day off, 6 working days`. |

### R-12 (found by WO-D06, copy)

| ID | Case(s) | Status | Summary | Owner layer | Evidence |
|---|---|---|---|---|---|
| R-12 | WO-D06 (copy, section 4) | Fixed, verified on device 2026-10-19 (FE `c2d8773`): offline Save shows `Couldn't save. Try again.` | When the phone has no network, Save shows `Could not reach the server. Check your connection and try again.` The approved copy list (section 4) says `Couldn't save. Try again.`. The case allows "or the server message", so the behaviour passes, but the copy is not the approved text. | FE (use the approved copy for save failures, not the network message) | Screen after offline Save, run 3 |

### R-13 (found by WO-C04b setup, screen refresh)

**Note 2026-10-19:** code read found no cache and a working focus refetch; the screen is a stack screen that remounts on entry. Not reproduced since; needs a device repro with the GET response logged (it may have been a stale test build).

| ID | Case(s) | Status | Summary | Owner layer | Evidence |
|---|---|---|---|---|---|
| R-13 | WO-C04b (pre-condition), section C, WO-E02 | Open, confirmed twice (medium) | After the everyone rule and its queued change were changed through the API, the Weekly off screen (opened by navigation, no relaunch) still showed no UPCOMING CHANGES panel. A force-stop and relaunch showed `1 change coming up`. Suspect the screen keeps cached data across visits and does not refetch on focus. Second reproduction in WO-E02: the 28 Oct row showed `Sun off` (an old `{7}` from C04b) while the server had `{5}`; after relaunch it showed `Fri off`. Owners can read a wrong day. | FE (refetch on screen focus or on navigation) | Run 4: `shots/C04b-open.png` vs `shots/C04b-relaunch2.png`; `shots/E02.png` vs `shots/E02-relaunch.png` |

### R-14 (WO-I10, already logged as FAIL in run 2; reconfirmed run 4)

**Status: Fixed, verified live 2026-10-19** (same fix as R-02).

Error bodies for 400, 401, 403, 404, 422 include a `stack` field with file paths and the framework name (for example `/app/dist/src/common/guards/jwt-auth.guard.js`). Owner: BE. Remove `stack` from error bodies in production.

### R-15 (low, API ordering)

**Status: Fixed, verified live 2026-10-19** (BE `d9a938e`; chunked-encoding gap closed in BE `d5789d5`). Technician bodiless DELETE with a JSON header, plain or chunked, gets 403; POST/PUT with an empty or malformed JSON body still gets 400.

A `DELETE` on an override with `Content-Type: application/json` and no body returns `400 VALIDATION_ERROR` ("Body cannot be empty") before the role check. A technician therefore gets 400, not 403. Owner: BE (the body parser should not fail a bodiless DELETE; the guard should run first).

### R-16 (low, DB hygiene)

**Status: Fixed, verified live 2026-10-19** (migration `20261019000002`, applied; BE commit pending). `btree_gist` now sits in `extensions`; the advisor warning is gone and writes to the exclusion-constrained tables still succeed.

Extension `btree_gist` sits in the `public` schema (Supabase advisor WARN `extension_in_public`). It is needed by the exclusion constraints; move it to an `extensions` schema. Owner: DB.

### R-17 (found by WO-K01, 200% font, layout)

**Status: Fixed, verified on device 2026-10-19** (FE `c2d8773`; Home screen and tab bar labels at 200% fixed in the next app commit). At 200% the pills, the date field and the upcoming-changes badge no longer clip (badge drops to its own line). Side finding: changing the font size crashed the app (react-native-screens fragment restore); fixed in FE `d3856f2`. The Home screen still clips some labels at 200% (`Prese…`, `Custome…`) — outside this screen.

At 200% system font the Weekly off screen clips text. The day pills wrap `Work` to `Wor` / `k` and cut off `Off` on Sunday. `Starts from the beginni…` is truncated in the starting-date field. The `2 changes coming up` badge runs past the right edge. Owner: FE (let pill labels shrink or stack, wrap the date hint, and let the badge wrap or drop to its own line). Evidence: `shots/K01-font200-weeklyoff.png`.

### R-18 (found by WO-Q08, copy and picker reuse)

**Status: Fixed, verified on device 2026-10-19** (FE, not yet committed). The weekly-off picker now reads `Pick an employee` / `Choose who this weekly off is for.` / `Search employees`, and lists active employees only. New Job keeps its own wording.

Tapping `Pick an employee` in the Set weekly off sheet opens a screen titled `Select technicians` with the subtitle `Choose who will do the job.` and a search box `Search technicians`. It lists technicians with job skills (Suresh, Mahesg) and employees together, with `Apply selection`. The plan expects the weekly-off picker to be titled `Pick an employee`, with one selection at a time. So the picker reuses the job-assignment screen's wording and list. Owner: FE (give the weekly-off picker its own title and copy and list only the active employees, as section 4 specifies). Evidence: `shots/Q08-picker.png`. Single-select behaviour was not confirmed (selection state could not be read).

### R-19 (found by WO-G20, picker round trip)

**Status: Fixed, verified on device 2026-10-19** (FE `ef100c9`). Choosing the first employee keeps the pills and date; swapping one employee for another still resets them.

In the Set weekly off sheet, the day pills are reset when an employee is applied from the picker. Steps: tap Monday (pill on), open `Pick an employee`, choose Asha, tap `Apply selection`. Monday shows Work again, and only the Sunday default is off. Going back from the picker without choosing keeps the pill. The expected result (section WO-G20) is that pills and date are kept after the choice. Owner: FE (keep the form state in the sheet when the picker returns, so the employee choice does not remount the form). Evidence: `shots/G20-after-apply.png`.

### R-20 (found by WO-C04b, SD-4 confirmed)

**Status: Fixed, verified live 2026-10-19** (migration `20261019000003`). Owner decision: saving the same days from a LATER date than a queued change moves that change; the rule before it stretches to the new date. Checked via API: `[19,25){5} [25,){6}` + save `{6}` from 28 gives `[19,28){5} [28,){6}`; from an earlier date (23) still works; with no earlier rule, moving gives a single rule from the new date. The employee-wise (override) save follows the same rule (migration `20261019000004`, BE `d5789d5`), including its empty-days marker. A queued "no day off" moves too (migration `20261019000005`, code-review patch).

Changing only the starting date of a queued change, with the days unchanged, does not move the queued rule. The save clips the queued rule at the new date and starts a new rule from there. Run result: `[18,25) {7}`, `[25,28) {6}` (queued rule clipped at 28 Oct, not moved), `[28,) {7}`. Whether this is the right behaviour is a product decision, so the expectation is not yet settled. Owner: FE + BE (decide what a date-only change means, then make the form and the save follow it). Evidence: results file, WO-C04b.

### R-21 (found by WO-Q11, SD-9 confirmed)

**Status: Fixed, verified live and on device 2026-10-19** (BE `ae3c4f0`). A queued clear now appears in `next` and `history` as an entry with `days: []`; the Upcoming panel shows `No day off from this date.`

A queued "clear" (no weekly off from a future date) does not show in the Upcoming panel. The DB change is correct (the covering rule is clipped, no row inserted), but the panel shows nothing for the clear. Owner: BE (return the clear as an entry in the change list, so every client shows it) and FE (show it in Upcoming). Evidence: results file, WO-Q11 (DB check).

### R-22 (found by WO-A08, SD-1 confirmed)

**Status: Fixed, verified on device 2026-10-19** (FE `6f4921b`). Pills and chip follow a server change after pull to refresh.

After the server rule changes on another device, pull to refresh updates `Right now` but not the day pills or the chip. The form is seeded once on first load (`hasLoadedRef`). Run result: `Right now: Sat & Sun off`, but Fri stayed Off, Sat and Sun stayed Work, and the chip read `1 day off, 6 working days`. Owner: FE (re-seed the form when the server rule changes, unless the owner has unsaved edits). Evidence: results file, WO-A08, `shots/A08-after-pull.png`.

### R-23 (found by WO-Q17, list order)

**Status: Fixed, verified on device 2026-10-19** (FE `c2d8773`). Picker is alphabetical; the New Job technician picker follows the same order.

The Set weekly off picker does not sort names alphabetically. Technicians with job skills are listed first, and `Zoya` comes before `Éla`. The employees below them (`Asha`, `bala`, `Chitra`) are in case-insensitive order. Owner: FE (sort the picker list with a locale compare inside each group), unless the order comes from the API, in which case BE. Evidence: results file, WO-Q17.

### R-24 (found by WO-Q09, SD-7 confirmed)

**Status: Fixed, verified on device 2026-10-19** (FE `6f4921b`). Picker refreshes the profile on focus and on open.

The Set weekly off picker keeps the old technician roster after a new employee becomes active. The owner's screen was open with five technicians. The employee was then made active (`invited` → `active`), and the backend `GET /users/me` lists them as active. Pull to refresh still shows five, and so does leaving and reopening the screen. Only a cold relaunch shows six, with the new employee. Owner: FE (refresh the roster when the weekly-off screen gains focus, or when the picker opens, not only at app start). Evidence: results file, WO-Q09, `shots/Q09-after-relaunch-picker.png`.

### R-25 (found during WO-A12 login, not a weekly-off case)

**Status: Deferred 2026-10-19 (owner decision: very rare corner case; not needed before launch). Planned fix when picked up: after OTP, if the number belongs to more than one company, return the list and show a company picker; remember the last choice; no in-app switch at first.**

The same phone number can be active in two tenants, and sign-in silently picks one of them. `9000000001` is Asha in Cool Air and "Loadtest H01" in another tenant. Sign-in chose Loadtest H01, because `auth.service.ts` takes the active row with the oldest `created_at`. The user gets no tenant choice and cannot reach the other tenant from that sign-in. The migration `20260620000003` allows the duplicate and notes that the lookup needs a tenant-aware step. Owner: BE (decide the tenant for a shared phone, e.g. ask for a tenant after OTP, or return the list), then FE (a tenant picker). Evidence: results file, WO-A12 row; `auth.service.ts` ~line 556–580.
