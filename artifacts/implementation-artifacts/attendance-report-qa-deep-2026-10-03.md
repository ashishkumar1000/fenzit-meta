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
