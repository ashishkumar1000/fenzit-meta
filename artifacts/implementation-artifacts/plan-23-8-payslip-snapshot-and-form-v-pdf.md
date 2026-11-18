# Plan — Story 23-8: Payslip snapshot + Form V PDF (BE)

- **Status:** DONE (2026-11-18) — shipped in fenzit-be 9869922 + cbf3005 + 6f9ff6c; admin-panel UI for pause/resume is a future FE story
- **Story:** epic-23 id 8 (BE) · CAP-7 · zero-RPC, backend-first (fenzit-be)
- **Reviews:** 2 adversarial rounds pre-build (general reviewer + BMAD adversarial lens) — 3 P1 / 2 P2 / ~17 findings, all triaged; 14 patched into this plan pre-build, 2 consciously accepted (below), 1 owner decision taken (superseded-object delete).

## What already exists (23-6/23-7 — no rework)

- `payroll_payslips` stores the Form V + product snapshot **except two fields**: `establishment_address` and `days_worked` (both mandated by Form V / story-8's field list; the shipped engine stores `establishment_name` only and no days-worked column).
- **Slip numbers** allocate gap-free via `payroll_slip_sequences` ON CONFLICT from NestJS; a re-run **destroys and replaces** rows with new slip numbers (live-set gaps accepted per spec).
- Presigned URLs are minted per request, never stored (FR3).
- Post-lock `POST /reports/:id/retry` re-runs fetchData + buildDocument **from the snapshot row** → the file regenerates, amounts can never recompute.

## Fixture adjudication (owner-approved 2026-11-18)

- **September payable 25 → 26** — already applied to `canonical-fixture.md` (meta repo, 2026-11-18). Money unchanged (the ₹15k ceiling binds → PF 1,800.00 either way).
- **November gross 29,615.38 → 29,615.39 (net 26,876.93)** — applied in THIS story's **meta-repo commit** (the fixture doc lives in fenzit-meta, not fenzit-be — two commits, two repos; the fenzit-be commit carries code + journey legs, which already pin .39/.93).
- Rationale: per-line rounding is the spec's own rule ("half-up rounding applied once per payslip line") and keeps the printed break-up summing to the gross; the .38 shorthand left a slip whose lines don't add up.

## Schema (one additive migration, `payroll_payslips` only)

The reviews proved the original "schema: none" premise false — Form V mandates two fields the snapshot cannot hold. Migration adds to `payroll_payslips`:
- `establishment_address text` — copied from `tenants.address` at compute time (engine's tenant fetch selects `company_name, address`).
- `days_worked numeric(6,2)` — presentation-only present-day count (present days, `half_day` as 0.5 — the fixture's definition), computed by the engine alongside the day-count buckets it already builds.
- **No RLS changes** — payslip reads stay service-client with explicit tenant filters; the shipped deny-by-default policies (service_role-only grants, 20261118000000/020000) are untouched. Ownership predicates named below.

## Code map

- `src/common/permissions/permissions.ts` — new permission `payroll.own` (employee's own payslip self-service, mirrors `attendance.own`); granted to EMPLOYEE only (admin keeps `payroll.config`). Deliberately NOT in ADMIN_PERMISSIONS.
- `src/payroll/payroll-payslips.service.ts` (NEW) + `src/payroll/payroll-payslips.controller.ts` (NEW, `@Controller('payroll')`):
  - `GET /payroll/payslips?month=YYYY-MM` — `@Can('payroll.config')`: the month's payslips (admin previews pre-lock), each row with `pdf: {status, url?}`. Cross-tenant → zero rows (tenant filter).
  - `GET /payroll/payslips/me` — `@Can('payroll.own')`: own history, **only locked months** (inner join `payroll_month_locks`; ownership predicate `user_id = jwt user` + tenant filter). Pre-lock rows filtered, never leaked.
  - `GET /payroll/payslips/me/:month` — `@Can('payroll.own')`: one payslip; not locked / not run / not yours → **404 `RESOURCE_NOT_FOUND` plain English**, copy branched: a month outside the runnable bound says "Payroll for {month} hasn't been run for your company yet"; a runnable-but-not-locked month says it appears once payroll locks the month.
  - `POST /payroll/payslips/:membershipId/:month/pdf` — `@Can('payroll.config')`: admin PDF request, any month state. Validates a live payslip row, then **inserts the queued `report_requests` row itself** (type `payslip`, params `{month, membershipId, payslipId}`) — the payroll-side insert per the owner decision. `@UseInterceptors(IdempotencyInterceptor)` (house pattern). `PT429` from the in-flight trigger → 429 `REPORT_IN_FLIGHT_LIMIT` (existing code, reports-house message). Re-request allowed when the newest matching request is terminal (`failed`) — plain insert; dedupe only against queued/generating (the in-flight cap bounds damage).
  - `POST /payroll/payslips/me/:month/pdf` — `@Can('payroll.own')`: same insert path, gated on the month being **locked** + a live payslip (else 404 plain English). Same interceptor, same PT429 mapping, same failed-retry rule. Employee polls via their payslip GET (pdf.status/url) — they hold neither `report.read` nor `report.request`.
  - **PDF status/url join** — newest request matching the **full params** (PostgREST `.contains()` jsonb containment on `{month, membershipId, payslipId}` — so a re-run's new payslip never inherits the destroyed row's failed request), ordered `created_at desc, id desc`, limit 1. Four statuses to the FE: `none` | `queued` | `running` | `ready` (with `url`) | `failed`. Presign via `StorageService.presignReadUrl` (the no-HEAD variant — a `ready` row was stamped only after a successful upload, so the object exists by construction; a 25-row admin list must not pay 25 sequential R2 HEADs). Presign failure → `url` absent, not a row error.
- `src/reports/registry/payslip.definition.ts` + `payslip.data.ts` + `payslip.template.ts` (NEW) + one registry entry:
  - **Contract edit owned (not "zero engine change")**: `ReportParams` widens to a discriminated union / per-type optional fields in `report-definition.ts`; `toParamsResponse`/`toListItem` (`report-response.model.ts`) gain a `report_type === 'payslip'` branch (range/counts null, label from the definition) so the generic report history renders sparse-but-well-formed rows — journey-asserted.
  - `validateParams` is a **pure create-time function with no DB access** — it validates the payslip params shape only (month regex `^\d{4}-(0[1-9]|1[0-2])$`-bounded, uuid shape); row-existence/tenant checks live at the payroll-side insert AND are re-verified by `fetchData` on the worker path (tenant-scoped read by `payslipId`). The generic `POST /reports` route can never forge a payslip request (its `RawReportParams` shape fails validateParams → VALIDATION_ERROR).
  - `fetchData`: tenant-scoped read by `payslipId`; destroyed/replaced row → throw → clean `failed` request.
  - **Pre-upload supersession guard**: after the fetch and BEFORE the render (23-8 review patch 6 — fail cheap: no pdfmake CPU, no upload), re-read the payslip row tenant-scoped and verify it still exists with the same `slip_number`/`run_id` as fetched; mismatch → throw → clean `failed`. This closes the fetch→verify window (the story's "never delivered" guarantee; the residual verify→stamp window is best-effort — milliseconds of render+upload against an admin action, and the fetch-time path catches the same re-run ordered the other way).
  - `buildDocument`: Form V (pdfmake, brand-kit reuse):
    - **Date of issue = the resolved pay date** (deliberate house reading, recorded: the slip is deemed issued with the wage payment — electronic issuance per CoW rule 52). Rendered as the full date: the month after `salary_period`, day `pay_date` (the stored int), tenant timezone — **December→January rollover pinned**; asserted in the template unit spec.
    - Establishment name **+ address** from the snapshot columns.
    - Employee name, father's/mother's/spouse name, designation, UAN, bank account number.
    - Wage-rate break-up from `earning_lines`; **days worked** from the new snapshot column; total attendance = payable / LOP / paid days; overtime ₹0.00.
    - Gross wages payable = the stored `gross_earnings` (the sum of the rounded component lines).
    - Deductions: PF (`pf_employee`), **ESI** = the deduction line whose `source` normalises (trim, case-insensitive) to "esi", else ₹0.00 (best-effort name-matching, recorded as a conscious simplification — no ESI head is auto-detected beyond the name), others = TDS + the remaining heads.
    - Net wages paid. Product extras: employee code, PAN (**missing → blank**; the warning lives on the run summary, not the row — never fabricated), date of joining, slip number, payment date.
- `src/payroll/payroll.module.ts` — register the new controller/service. Reports/ changes = the registry entry + the owned params-contract widening.

## Regeneration semantics (story acceptance)

- Re-run of an unlocked month: existing destroy+replace + fresh slip numbers (shipped 23-6), **plus best-effort deletion of the superseded payslip-request R2 objects** (owner decision 2026-11-18; `StorageService.deleteObject` exists) — old URLs 404 immediately, and the story's "prior URL no longer serves the file" journey assertion is real. Deletion happens after the replace commits, outside the transaction; a missed delete degrades to the 600 s TTL, never to a wrong PDF.
- Queued PDF job whose snapshot was destroyed: pre-upload guard or fetch failure → clean `failed` row (never delivers a superseded PDF).
- Post-lock retry: renders from the permanent snapshot — file-only regeneration.

## Journey legs (extend `test/payroll-journey.e2e-spec.ts`)

1. **Snapshot field set** — assert the full Form V field set from the payslip row, now including `establishment_address` and `days_worked`; no PAN-warning expectation on the row (it lives on the run summary).
2. **Regeneration** — re-run an unlocked month → exactly one live row per employee, new slip number (counter advanced), old row id gone, **the prior request's R2 object deleted (old URL no longer serves)**.
3. **PDF end to end** — admin requests a payslip PDF → `awaitReport(requestId)` helper (poll `report_requests.status` until ready/failed; timeout ≥ several poll ticks) → ready with a working presigned URL (bytes start `%PDF`); the failed terminal also exercised. Env prerequisites named (`CLOUDFLARE_R2_*` + `REPORT_*`); absent env → loud skip marker, never a silent green.
4. **Employee leg** — own history shows the locked month only; direct pre-lock month → 404 (branched copy); out-of-bound month → the "hasn't been run yet" copy; PDF request + download works for self; the concrete cross-employee attempt: employee `POST /payroll/payslips/:otherMembershipId/:month/pdf` → **403** (permission — the `/me` routes cannot express the attack, that case is dropped as impossible); cross-tenant admin → zero rows.
5. **Superseded-safety, staged deterministically** — PDF request inserted → re-run completes (destroying the row) → await the request row → `failed`, regardless of worker-claim ordering (the pre-upload guard makes both orderings fail cleanly); plus the employee-retry leg: employee self-PDF fails → employee re-requests → ready.
6. **Generic history** — `GET /reports` returns a well-formed sparse row for a payslip request (no `undefined` leaking into JSON).

## Test timing

Journey legs are the acceptance anchor (standing payroll pattern). Unit specs (template field mapping incl. the December rollover, definition shape refusal, pre-upload guard) follow the review round, per the implement → confirm → test rule.

## Non-goals (this story)

- No web/mobile UI (23-10/23-11/23-12). No ESI computation. No PDF delivery by email/WhatsApp. No slip-number consecutiveness test over the live set.

## Plan Change Log

- **2026-11-18 (mid-build, owner-directed extension):** the per-tenant report-queue pause — decided live with the owner ("do both — API as well … we can use this API later"; "it will tell if paused, when it will resume, pause for ever"; "pause/resume should work per tenant"): table `report_queue_pauses` (one row per tenant, tenant-delete cascades), `GET /reports/queue/status` + `POST /reports/queue/pause` (minutes 1–1440 timed, omit = forever) + `POST /reports/queue/resume`, every worker filters paused tenants per tick, and `REPORT_WORKER_EXCLUSIVE=true` (test-only) exempts the e2e suite's own worker so the API fence protects against the deployed Render worker. Also fixes found mid-build: e2e R2 stub overwrite (`??=`), audit-actor defect (runs wrote no audit rows since 23-6 — `actorId: 'system'` against a uuid rpc; now the claim's `initiated_by`).
- **2026-11-18 (pre-build review round):** (1) one additive migration added (establishment_address + days_worked) — the "schema: none" premise was false; (2) params-contract widening owned explicitly (ReportParams union + report-response.model payslip branch) — NFR6 claim corrected; (3) row/tenant checks moved off validateParams (pure) to insert-time + fetchData re-verify; (4) PDF-status join pinned to full-params containment + id tiebreaker + presignReadUrl (no HEAD); (5) PT429 mapping + IdempotencyInterceptor + failed-retry rule on both POSTs; (6) pre-upload supersession guard added; (7) superseded-object deletion on replace (owner decision); (8) date-of-issue and ESI render rules pinned (2 conscious acceptances); (9) 404 copy branched + RESOURCE_NOT_FOUND named; (10) leg 4 cross-employee attempt pinned (403), impossible case dropped; (11) leg 3 env staging + awaitReport helper; (12) RLS posture line added; (13) two-commit note (fixture docs are meta-repo); (14) September amendment marked applied.
- **2026-11-18 (pre-commit BMAD code review, 4 lenses):** (1) migration file shipped (`20261118040000` — DDL was applied via MCP mid-build); (2) Form V statute corrected to CoW (Central) Rules, 2026 rule 52; (3) PF/TDS no longer double-render in the deductions table; (4) paused-tenant filter moved INTO the candidate query (head-of-line starvation); (5) `REPORT_WORKER_EXCLUSIVE` parsed strictly + production boot guard; (6) supersession verify moved before the render, residual window restated as best-effort; (7) `withPdf` filters by payslipId (no month-window cap); (8) requireTenant copy; (9) journey: history asserts shape not transient status, PDF legs gated on real R2 creds with a loud skip marker, employee-retry leg added; (10) owner decision: pause/resume gated on the new `report.queue` permission (ADMIN_PERMISSIONS), status read stays `report.read`. Six findings accepted-with-reason, six dismissed, seven folded into the planned unit-test step — all recorded under Review Findings below.
- **2026-11-18 (post-commit fixes, both shipped):** `cbf3005` — the queue status read answers ISO-Z like the pause POST (Postgres `+00:00` timestamptz round-trip normalised in `normalise()`); journey pause assertions pinned with `toMatchObject` (responses carry the panel's full state). Followed `9869922` (the story feature commit).
- **2026-11-18 (unit-test step, post-confirmation):** all seven review-folded test items shipped: worker pause-filter specs (SQL `not.in` on both candidate queries, empty set skips the filter, other tenants flow, exclusive worker never consults the pause, production boot guard); `report-queue.service` spec (expired pause reads as running, ISO-Z normalisation, fail-open worker read, pause/resume payloads + refusals); `verifyBeforeReady` pipeline tests (order fetch→verify→build pinned; destroyed row → clean FAILED, nothing built/rendered/uploaded; gate optional); PT429→429 on both payslip PDF POSTs (+ dedupe-return and failed-doesn't-block in the same spec); payslip template content spec (Form V statute, resolved pay date incl. December→January rollover, deduction single-render, head:/recovery: labels, ESI-absent ₹0.00); payslip definition shape-refusal spec; `GET /reports/:id` payslip branches (sparse params, `payslip_<month>.pdf`). Plus the audit-actor assertion added to the journey's 23-7 leg (run_completed entries carry the enqueuing owner). Journey 62/62; reports+payroll units 45 suites / 672 tests green.

### Review Findings (BMAD code review 2026-11-18 — pre-commit, 4 lenses: blind-hunter, edge-case-hunter, verification-gap, acceptance-auditor)

**Decision needed**
- [ ] [Review][Decision] Pause/resume gated on `report.request` — a VIEWER can pause the company's report queue indefinitely [src/reports/reports.controller.ts:80-113]. Recommended: new permission `report.queue` in ADMIN_PERMISSIONS (company admin + platform admin); status read stays `report.read`.

**Patch**
- [ ] [Review][Patch] Missing migration file — `payroll_payslips.days_worked`/`establishment_address` + `report_queue_pauses` applied via MCP only; repo replay breaks every run/pause route [supabase/migrations/]
- [ ] [Review][Patch] Form V header cites the wrong statute ("Contract Labour (R&A) Rules") — SPEC pins rule 52 of the Code on Wages (Central) Rules, 2026 [src/reports/registry/payslip.template.ts:201]
- [ ] [Review][Patch] PF and TDS double-rendered in the deductions table — `otherLines` excludes only ESI; the engine also stores `pf_employee`/`tds` lines [src/reports/registry/payslip.template.ts:145-147]
- [ ] [Review][Patch] Paused-tenant filter applied AFTER `limit(concurrency)` — one paused tenant starves every other tenant's queue; filter in the candidate query [src/reports/engine/report-worker.ts:98-107]
- [ ] [Review][Patch] `REPORT_WORKER_EXCLUSIVE` parsed as truthy string ('false' would pass) and no production guard [src/reports/engine/report-worker.ts:67-68]
- [ ] [Review][Patch] Supersession verify gate runs after the render — move before render; restate the residual verify→stamp window as best-effort [src/reports/engine/report-pipeline.service.ts:58-70]
- [ ] [Review][Patch] `withPdf` month-window capped at 500 requests — filter by `params->>payslipId` of the listed rows instead [src/payroll/payroll-payslips.service.ts:391-400]
- [ ] [Review][Patch] `requireTenant` 422 copy says "managing" on the status read [src/reports/report-queue.service.ts:173-181]
- [ ] [Review][Patch] Journey: history queued-status assertion races the worker — assert shape (null range/counts), not the transient status [test/payroll-journey.e2e-spec.ts]
- [ ] [Review][Patch] Journey: PDF legs run on stub creds (die mid-run) instead of the plan's loud skip marker; the leg-5 employee-retry leg is missing [test/jest.env.setup.ts, test/payroll-journey.e2e-spec.ts]

**Accepted with reason (recorded here per the ledger discipline)**
- [x] [Review][Accept] Dedupe is check-then-insert (two tabs double-tap can burn two in-flight slots) — house idiom shared with reports.service, consequence self-heals, pre-launch scale
- [x] [Review][Accept] Superseded history rows stay `ready` with a dead download — this IS the SPEC's "prior URL is invalidated"; the payslip surface always shows the live row's fresh PDF
- [x] [Review][Accept] `adminList` returns the full month roster (PII, no pagination) — admin-only route, roster-bounded, pre-launch
- [x] [Review][Accept] Test PDFs accumulate in the configured R2 bucket — dummy data, per-request-id keys, no collisions
- [x] [Review][Accept] `reportFilename` = `payslip_<month>.pdf` for every employee of a month — cosmetic download name; the R2 key is per-request
- [x] [Review][Accept] File sizes: payroll-payslips.service 513 / payslip.template 350 — cohesive feature; a split is mechanical churn for its own sake this story

**Folded into the story's planned unit-test step (test-timing rule — tests follow owner confirmation) — DONE 2026-11-18**
- [x] Worker pause-filter unit specs (paused tenant's claim skipped; expired pause claimable again)
- [x] `report-queue.service` spec (expired timed pause reads as running)
- [x] `verifyBeforeReady` destruction test (row destroyed after fetch → clean failed, nothing uploaded)
- [x] Audit-actor assertion: `payroll.run_completed` entry exists with the enqueuing owner (via the audit READ surface, before teardown deletes audit rows)
- [x] PT429→429 mapping on both payslip PDF POSTs
- [x] Template content spec (ESI line, deduction labels, December rollover) matching the sibling template specs
- [x] `GET /reports/:id` payslip branches (sparse params, payslip filename)

**Dismissed**
- [x] [Review][Dismiss] `pausedTenantIds` fails open — deliberate: fail-closed wedges the WHOLE queue on one transient read failure; a broken read 500s on the status API so the admin sees it
- [x] [Review][Dismiss] Audit rows vanish when `runActor` is null — dead path: `payroll_runs.initiated_by` is NOT NULL
- [x] [Review][Dismiss] Expired pauses never reaped — one row per tenant (PK); the per-tick expiry filter is trivial
- [x] [Review][Dismiss] `resume()` leaves `paused_by`/`paused_at` on the row — `normalise` surfaces them only while paused
- [x] [Review][Dismiss] `payroll.own` is EMPLOYEE-only — deliberate per plan ("Deliberately NOT in ADMIN_PERMISSIONS")
- [x] [Review][Dismiss] ESI matched by exact normalised name — the plan records this as a conscious simplification (line above the findings)
### Review Findings — unit-test step (BMAD code review 2026-11-18, second pass, test-only diff)

**Patch (all applied 2026-11-18):**
- [x] [Review][Patch] The supersession gate's own branches are tested nowhere — `verifyPayslipSnapshot`/`fetchPayslipReportData` only identity-checked; a neutered gate ships green (verification-gap DEMONSTRATED it). New `payslip.data.spec.ts`: verify — missing row / slip_number-run_id mismatch / read error each throw with the plain-English message; fetch — bad params guard, read error, missing row, success [src/reports/registry/payslip.data.ts]
- [x] [Review][Patch] Payslip registry registration unpinned (the exact 21-1 review gap repeated) — extend report-registry.spec to resolve `payslip` [src/reports/registry/report-registry.spec.ts]
- [x] [Review][Patch] Dedupe test never asserts "no second insert"; GENERATING and READY newest-request branches untested [src/payroll/payroll-payslips.service.spec.ts]
- [x] [Review][Patch] Dedupe read scoping unasserted — pin tenant eq, report_type eq, and the full-params contains triple [src/payroll/payroll-payslips.service.spec.ts]
- [x] [Review][Patch] Payslips error paths: newest-read error → 500 (no insert), slip-read error → 500 (not the branched 404), non-PT429 insert error → 500, requestPdfFor month/uuid validation branches [src/payroll/payroll-payslips.service.spec.ts]
- [x] [Review][Patch] Queue spec never asserts its filters — pin `.eq('paused', true)` on the worker read and `.eq('tenant_id', …)` on the row read (tenant isolation) [src/reports/report-queue.service.spec.ts]
- [x] [Review][Patch] Corrupt `paused_until` string (NaN) must read expired/running, never wedge the fence [src/reports/report-queue.service.spec.ts]
- [x] [Review][Patch] `pause(user, 0)` falsy-zero branch — make the service branch explicit (`minutes > 0`) and pin with a comment (unreachable over HTTP: DTO `@Min(1)`) [src/reports/report-queue.service.ts]
- [x] [Review][Patch] MAX_PAUSE test asserts a constant, not behaviour — retitle honestly and pin the DTO `@Min(1)/@Max(1440)` boundary instead [src/reports/report-queue.service.spec.ts, src/reports/dto/report-queue-pause.dto.ts]
- [x] [Review][Patch] "Renders each deduction ONCE" can't catch a double-render (`has()` is existence-only) — count occurrences exactly, like the sibling head:esi test [src/reports/registry/payslip.template.spec.ts]
- [x] [Review][Patch] ESI-absent ₹0.00 assertion vacuous (`'0.00'` substring matches any amount) — assert the exact cell [src/reports/registry/payslip.template.spec.ts]
- [x] [Review][Patch] PAN-missing → blank never tested; identity block (father/mother/spouse, designation, UAN, bank, join date) asserted nowhere; null-branch behaviours (days_worked → '—', wage-period fallback to salary_period, absent address, no warnings on slip) untested [src/reports/registry/payslip.template.spec.ts]
- [x] [Review][Patch] Non-string `month` in validateParams untested [src/reports/registry/payslip.definition.spec.ts]
- [x] [Review][Patch] Pipeline gate throwing a PLAIN Error (no error_code) must stamp the generic REPORT_GENERATION_FAILED — untested [src/reports/engine/report-pipeline.service.spec.ts]
- [x] [Review][Patch] getReportStatus FAILED payslip row untested (sparse params + error.code) [src/reports/reports.service.spec.ts]
- [x] [Review][Patch] Journey audit-actor assertion rides the capped 100-row read — `run_completed` is the OLDEST action; growth false-fails it. Companion DB-count assertion + actor check robust to the window [test/payroll-journey.e2e-spec.ts]
- [x] [Review][Patch] Stale verify-ordering comment in report-definition.ts ("after buildDocument + render") — the gate moved before the render; plan line 39's month regex `1[0-9]` contradicts the shipped `0[1-9]|1[0-2]`; plan line 41 still places the guard after buildDocument [src/reports/registry/report-definition.ts, plan doc]
- [x] [Review][Patch] Worker fence test name overstates ("nothing claims it" is vacuous with no candidate rows) — retitle to what it pins (the SQL filter args) [src/reports/engine/report-worker.spec.ts]
- [x] [Review][Patch] Trailing-newline hygiene: report-pipeline.service.spec.ts and report-worker.spec.ts end without a final newline [both spec files]

**Consciously accepted (with reason):**
- [x] [Review][Accept] The pause fence's real-DB `not.in` behaviour is executed by no test at any layer (journey's worker is exclusive; journey pause legs assert the API surface only) — the TS-layer pins are genuine; the PostgREST idiom is identical to sync.service's, which runs against real Postgres in production; a real-DB fence leg needs a second tenant + a non-exclusive worker — a separate concern if the fence ever misbehaves
- [x] [Review][Accept] listReports' sparse payslip history row (toListItem) unpinned — shares the `isRangeParams`/`toParamsResponse` path already pinned via getReportStatus; the journey history leg covers the rendered surface
- [x] [Review][Accept] The 23-8 audit-actor assertion lives inside the "23-7" journey leg title — the assertion carries an explicit "23-8 review fold" comment; titles stay leg-scoped by design
- [x] [Review][Accept] Verify context doesn't pin the same admin client as fetch — the pipeline passes the same factory return by construction
- [x] [Review][Accept] Extra-field stripping in validateParams "untested" — already pinned: the verbatim test uses exact `toEqual` on the returned triple, a leaked key would fail it
