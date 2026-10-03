# Attendance Report — Deep Negative / Edge / Corner QA (2026-10-03)

QA bug bash on the shipped Attendance Report (Epic 21), run adversarially the
morning after release. Method: static attack-matrix read of the whole request
path (DTO → validateParams → resolveTechnicianIds → validateAccess → insert →
pipeline), then 25 live negative probes against **production**, a dedicated
**scratch-tenant** cross-tenant probe set, 4-way **concurrency** + idempotency
probes, and 3 **engine corner** probes as jest cases against the real grid
reader. Every finding below was verified before triage (no reviewer
false-alarms); all probe data was deleted afterwards (see Cleanup).

**State: fixes are LOCAL (fenzit-be working tree), NOT committed.** Per the
consent rule they await the user's review. Production still has the old
500-on-malformed-id behaviour until these ship.

---

## Confirmed defects (fixed)

### D1 (P2) — Malformed ids in scope arrays caused HTTP 500 (and a misleading 400)
- **Probe**: `technicianIds: ["not-a-uuid"]` and `technicianIds: ["", "  "]`
  on `POST /reports` → **500 INTERNAL_SERVER_ERROR** "Failed to validate
  report technicians". `officeIds: ["not-a-uuid"]` → 400 but with the
  server-sounding copy "Failed to verify the selected offices".
- **Root cause**: client-supplied id strings reached PostgREST `.in()`
  unvalidated; `22P02 invalid input syntax for uuid` mapped to the generic
  500 path. Client input must never produce a 5xx (and each one pages the
  error log).
- **Fix placement — BE owns it** (the API boundary owns input hygiene; the FE
  already sends only real uuids; DB has nothing to do):
  - `resolveTechnicianIds` (reports.service.ts): UUID-shape gate after the
    cap, before membership → 400 `technicianIds must all be valid technician
    ids`. Placed after the cap so an oversized list always gets the cap
    message.
  - `attendance.definition.ts validateParams`: same gate for office ids →
    400 `officeIds must all be valid office ids`.
  - Shared `isUuidShape` helper in report-params.util.ts (any-version UUID
    shape; membership continues to do the real check).
- **Verified**: local BE probe → both 400s with the new copy; a well-formed
  office id still queues. Regression specs in reports.service.spec.ts and
  attendance.definition.spec.ts.

### D2 (P3) — Rejections audit silently widened to the whole roster
- **Probe (spec)**: office filter matching NO employee (all rows filtered
  out) → `fetchRejections` fell back from `summaryIds` to the **entire
  roster**. The template's empty page happened to discard it, so no user-
  visible wrong data — but it was a wasted full-roster read sitting on a
  false invariant.
- **Fix (BE, one line + comment)**: audit is now always exactly
  `summaryIds` — **audit ⊆ shown employees, always**. Spec pins that an
  office filter matching nobody reads zero attempts.

### D4 (doc) — DTO comment over-promised
- `startDate: 12345` (type violation) → ValidationPipe **422**, while the DTO
  comment claimed "every failure maps to a 400 … rather than a generic 422".
  Comment corrected (value-level failures → 400 with error codes; shape-level
  → 422 field messages). No code change — both are handled by the app client.

## Observations (recorded, not fixed)

### D3 — Idempotency replay ignores the request body (platform-wide)
- Same `X-Idempotency-Key` + **different body** on `POST /reports` silently
  replays the FIRST response (no new row). Stripe would 4xx with an
  idempotency error. Scoped (key, tenant, path) — a body-hash check is the
  hardening. **Deferred**: pre-existing platform behaviour (FR-17), the app
  mints a fresh key per intent (useReports.ts), so no app-visible risk.
  Worth a small platform story if a public API ever opens.

### Notes that need no action
- Non-uuid `GET /reports/:id` → 400 (ParseUUIDPipe); unknown/foreign →
  indistinguishable 404 — correct no-leak posture.
- A selected employee whose users row vanishes after validation degrades to
  the raw uuid in the PDF name column (graceful; requires an impossible
  validateAccess-vs-fetch race).
- Six small orphan PDFs remain in R2 from the probe rows (keys derive from
  deleted request ids — unreachable, harmless).
- Device pass skipped deliberately: all fixes are BE-only; the FE is byte-
  identical to last night's device-verified release build.

## Verified solid (attack matrix results, 25 live probes)

| Attack | Result |
| --- | --- |
| No token / technician token (POST + GET) | 401 / 403 |
| Unknown type, blank type defaulting | 400 / defaults to job report |
| `2026-02-30`, `2026-9-03`, number startDate | 400 / 400 / 422 |
| start > end, end in future (IST) | 400 |
| 93-day range vs 92-day boundary | 400 REPORT_RANGE_TOO_LARGE / (92 accepted by unit) |
| Job report with officeIds | 400 "not a valid filter for this report" |
| 201 employees (attendance) / 26 technicians (job) | 400 caps 200 / 25 |
| Cross-tenant office id / technician id (scratch tenant) | 400, tenant-scoped |
| Cross-tenant report GET + retry | 404, no leak |
| Attendance on a never-enabled tenant (live) | 400 ATTENDANCE_NOT_ENABLED |
| Retry a READY report | 409 REPORT_NOT_RETRYABLE |
| 4 concurrent creates | 3×201 + 429 REPORT_IN_FLIGHT_LIMIT (declarative trigger held) |
| Idempotency same key+body | replayed same id, one row |
| Garbage list cursor | 400 "Invalid cursor" |
| Empty roster end-to-end (real grid reader) | honest empty shape; template prints the empty page |
| Oversize guard boundary | exactly 25,000 employee-days proceeds; 25,001 refuses pre-read |
| Register >31 days | skipped (registerDays null) |

## Test + cleanup record

- BE suite: **95 suites / 1,494 tests green** (was 1,489; +3 QA corners,
  +2 shape-gate specs; fixture ids in old specs upgraded to uuid-shaped so
  they still exercise membership, not the new shape gate).
- Changed files: reports.service.ts, attendance.definition.ts,
  report-params.util.ts, attendance.data.ts, create-report-request.dto.ts
  (comment), attendance.data.spec.ts, reports.service.spec.ts,
  attendance.definition.spec.ts.
- Production cleanup: 6 probe report_requests rows, the idempotency_log
  entry, the scratch tenant + owner user + its notification row — all
  deleted (verified 0 rows remain). Nothing else touched.

---

## Code review of the QA fixes (2026-10-03, bmad-code-review, 2 lenses)

Diff reviewed: the 8 uncommitted fenzit-be files (520-line patch). Self-check
before the lenses: tsc clean, 95/95 suites (1,494), FE repo untouched, diff
read hunk-by-hunk.

| # | Finding (lens) | Verdict after source verification | Action |
| --- | --- | --- | --- |
| 1 | `"<uuid>\n"` passes the shape gate because JS `$` matches before a trailing newline → 500 hole survives (edge-case lens, kind:claim "high") | **false** — JavaScript `$` without `/m` matches only at end-of-input (Python/PCRE semantics); verified empirically: `RE.test('uuid\n')` → false, as do CR/space/leading-newline variants | none (recorded) |
| 2 | The new pg-stub comment claims the array-param filtering is load-bearing; no assertion depends on it — the grid reader already materialises rows only for in-scope `employeeIds` (verification lens, other) | **true** (doc-only) | comment corrected to "prophylactic, not load-bearing"; spec re-run green |

Post-review state: **95 suites / 1,494 tests green** on the exact reviewed
tree. Reviewer-confirmed solid: gate order dedupe→cap→shape→membership
pinned by the 26-ids cap test and the no-DB-call shape test; rejections
tightening mutation-checked (the NOBODY spec fails if the fallback
returns); the stub filter escapes rows without `employee_id` (office rules,
weekly-off defaults); job-report specs never route through
`resolveTechnicianIds`; the DTO 422 copy matches the pipe's configured
`errorHttpStatusCode`.

## Ship + device QA round on the release build (2026-10-03 afternoon)

Fixes shipped (fenzit-be eaae57d, Render-deployed, prod-probed live: all
three malformed-id probes now 400 with the new copy, sane create still
queues), release APK re-confirmed and installed on the Pixel 6 (the phone
still had the debug build — uninstall + fresh install of the signed
release, so one re-login was needed).

Device QA round (release build, production API, all PASS):

| Check | Result |
| --- | --- |
| Fresh-install onboarding → Skip → login | clean; master OTP 816001 auto-submits |
| Transient network failure on Send OTP | clean inline error "Could not reach the server…", button recovers, retry succeeds |
| Report type dropdown | both types; form + copy switch correctly (Offices/Employees vs Technicians) |
| Happy path 27 Sep–3 Oct, all scope | "Report queued" banner → Queued row → Ready in ~40 s → tap → presigned R2 PDF opens (10 pages, real data) |
| >92-day boundary (1 Jul → 3 Oct = 95 d) | Generate disabled + red "Range exceeds 92 days" |
| Exactly 92 days (4 Jul → 3 Oct) | gate releases, button enabled |
| Empty state (Jhaji's Home filter, 20–26 Sep) | 1-page PDF, header "0 tracked", boxed "No attendance data for these dates" — this is the D2-fixed path rendering honestly |
| 429 in-flight cap from the device | red inline "You have a report generating. Wait for it to finish before creating another.", no row created |
| "Generating"/"Queued"/"Ready" chips | all three observed live in history |
| Tab sweep (Home/Jobs/Customers/Account) | all load, no crash |

Findings from the round (no code changed — both need the owner's call):

1. **Decision-needed — "(no office)" bucket counts untracked days.**
   The 27 Sep–3 Oct all-scope PDF shows an offices row "(no office) · 103
   employees · all zeros" next to Hero wala (51) / Yuka (51) — the same
   103 people double-listed. SQL confirms every enrolled employee HAS an
   assignment overlapping the window; the bucket is per-day gaps where the
   assignment starts mid-window (enrolment precedes assignment), which are
   untracked days with no office snapshot. Math is honest; the label reads
   like broken data. Recommendation: drop null-office buckets whose rows
   are all untracked (or count `employees` from tracked rows only) —
   needs the owner's call since it changes displayed data and the spec's
   "one row per distinct snapshot office" wording.
2. **Copy nit — Account → Reports row still says "Job reports (PDF)"**
   although the screen now offers two report types (FE copy only).
3. **Observation — the Reports form resets to defaults after a successful
   submit** (dates back to the 7-day default, scopes cleared). Possibly a
   remount; harmless but worth a deliberate look if owners chain reports.

Cleanup: the 6 curl-created 1-day rows from the 429 probe deleted; the two
reports queued from the device UI (2:52 happy-path, 2:59 empty-state) are
left in history — they are indistinguishable from real usage. App left on
the Home tab.

## Round 2 — deeper scenarios (2026-10-03 evening): P1 rendering defect found & fixed

**P1 — both employee tables silently missing from the production PDF.**
The full page-by-page visual pass of the 10-page 103-employee report (on
device) found: page 3 completely blank, NO "Employees — attendance" /
"Employees — discipline & hours" tables anywhere. Root cause:
attendance.template.ts's `kept()` helper wrapped section titles + ENTIRE
tables in `{ unbreakable: true }` — pdfmake silently clips an unbreakable
block taller than one page. The job-report template (which invented
kept()) documents the rule "never wrap a table" and obeys it; the
attendance template violated it for six tables. 2-employee test fixtures
could never see it. Also latent: offices table (≤51 rows at the cap) and
leave/rejections tables.

**Fix (BE, uncommitted):** all six tables pushed as SIBLINGS of their
titles (dataTable repeats its header row across page breaks by design);
kept() survives only for the Overall card row and the ≤6-item flag list —
the job report's documented pattern. Trade-off (deferred, cosmetic): a
section title can now strand at a page bottom; accepted in exchange for
never losing rows, matching the job report's existing behavior.

**Proof:** mutation-first regression spec failed on the pre-fix code
([104,104,104] unbreakable violations = attendance/discipline/leave
tables); post-fix the same report renders **17 pages (was 10)** and the
device shows both employee tables complete (Loadtest Y41–Y50, Ravi,
Suresh rows; discipline table with late minutes/early outs/attendance %).
Verified end-to-end via a local-BE render before deploy.

**BMAD 2-lens review of the fix — 3 patches applied, 1 deferral:**
1. Guard blind spot (patched): the first guard fixture only grew the
   employee axis — a half-revert shipped green (proven by mutation in
   /tmp). New spec case grows offices=8, weeks=8, rejections=8,
   exceptions=8 so the >6 filter bites on every unwrapped site.
2. Job template unprotected (patched): same guard mirrored into
   technician-job-activity.template.spec.ts with a 12-job / 8-flag
   fixture (a reintroduced kept() around jobsTable had shipped green).
3. Fixture nit (patched): `employeesInScope: 103` was a dead property
   (lives at scope.employeesInScope; silent TS2353) — scope now
   overridden properly.
4. Deferred (cosmetic): possible title-stranded-at-page-bottom after the
   unwrap — consistent with the job report's existing behavior.

Also verified this round: report_ready notifications land in the owner's
feed (the "you'll be notified" promise); "Generating" chip renders live;
Reports screen has no tab bar (pushed screen — back navigation only).

**State: tsc clean, 95 suites / 1,497 tests green (+2 guards). The fix is
UNCOMMITTED — awaiting the owner's ship consent** (production currently
renders the clipped 10-page PDF for big tenants; tenants ≤ ~35 employees
are unaffected).

## Round 3 — owner-persona audit + external research (2026-10-03 night)

Method: internet research on attendance/payroll report best practices
(payroll linkage, late-mark grace conventions, regularization, the classic
UTC/date-boundary and text-overflow bug classes), then a raw-data audit —
hand-computing the PDF's numbers from attendance_records / rules /
corrections for the exact employees whose rows looked odd on device
(Arya, Ravi, Suresh, Loadtest H01).

**Audit verdict: NO arithmetic bugs.** Every oddity traced exactly to a
rule: H01's "617 min late" = 19:32 punch vs 09:00+15 cutoff (exact);
Ravi's all-zero row = 20:38 check-in with no check-out (late yes, no
credit, correctly not absent); Suresh's 02:30 IST punch landed on the
correct IST work_date (the timezone boundary class is clean); Arya's
5.1 h = owner-added 08:57→14:00 checkout (corrections integrate
correctly), graded half-day against Hero wala's 4 h threshold.

**Fixed (uncommitted, with the kept() fix):** the footer said
"Private — contains customer details" on the attendance report — it
contains EMPLOYEE data. pageFooter() now takes the privacy note; the job
report keeps the customer wording (true there), attendance passes
"Private — contains employee details". Spec added. 95 suites / 1,498
tests, tsc clean.

**Findings for the owner (decisions / improvements, no code changed):**
1. **"Avg hrs/day" can exceed "Worked hours"** (Arya: 5.1 h total, 10.2 h
   avg) — the average divides by day CREDIT (half-day = 0.5), which is
   why a half-day reads double. Options: divide by days-with-hours, or
   relabel "avg per credited day".
2. **Punched-in days grade as ABSENT** when the span is under the office
   half-day threshold (H01: punched 19:32–19:33 → 'A' in the register
   plus "617 min late"). Defensible (1 minute ≠ work) but owners WILL
   dispute it — consider a distinct code or note.
3. **No "Payable days" column** — the #1 figure owners compute from
   attendance reports (worked + paid leave − LOP). All ingredients exist;
   adding the derived column is a policy decision.
4. **Weekly trend weeks start on the range's first weekday** (a 27 Sep
   start = Sunday-start weeks); Indian business expectation is Mon-start.
5. **Alarm fatigue**: 43 "absent streak" alarms for load-test employees
   who have never punched once. Consider suppressing the streak alarm
   for employees with zero attendance history ever.
6. Carried from round 1: the "(no office) · 103 employees · all zeros"
   bucket; Account → "Job reports (PDF)" copy; form resets after submit.

## Round 4 — decisions implemented & SHIPPED (2026-10-03, evening)

Owner delegated the calls ("take your best decision"). Implemented and
shipped (BE 624580e, FE c742a0b — Render deployed, production-verified):
1. avgHoursPerDay over days-with-hours (same-instant 0-minute punches
   excluded from the divisor per review) — spec pinned incl. the null arm.
2. Weekly trend chunks Monday-start — labels pinned ('1 Sep – 6 Sep' for
   a Tue-start range).
3. Offices table drops all-untracked buckets; headcount counts tracked
   rows only — both pinned.
4. Footer call site pinned: the built doc's footer callback must carry
   'Private — contains employee details'.
5. FE: Account row now "Job & attendance reports (PDF)".
DEFERRED with reasons: payable-days column (needs the tenant's payroll
policy — LOP/leave-paid rules are the owner's call), punched-but-absent
grading (follows the owner's own office thresholds; changing it changes
payroll meaning), absent-streak alarm noise (logic correct; the noise is
43 load-test employees in the tenant — data hygiene).

BMAD 2-lens review of this round: 6 findings, ALL patched (span>0 guard;
tracked-only headcount; bare-table unbreakable escape in both walkers;
attendance footer call-site pin; avg null-arm pin; axis coverage was
already in). Production probe on the deploy: the same 27 Sep–3 Oct report
renders 17 pages (~153 KB) — was 10 clipped pages. BE 95 suites / 1,501
tests, FE 235 suites / 2,971 tests, tsc clean both.

Probe row + its notification deleted after verification. Release APK
rebuilt with the FE copy; on-device visual pass of the new render pending
the owner's return (phone left with them).
