# 21 — Attendance Report: code review + triage record (2026-10-03)

BMAD code-review workflow (thorough): two lenses over the uncommitted BE + FE diffs
(`/tmp/review-be.diff` 4,943 lines · 58 files; `/tmp/review-fe.diff` 866 lines · 10 files),
plan context `artifacts/planning-artifacts/epics-attendance-report.md` + spec
`artifacts/specs/spec-attendance-report/`. The verification-gap lens mutation-tested each
demonstration (applied the regression, ran the suite, restored the tree).

## Triage (normalized 17 findings → verdicts; grouped where one defect)

| # | Source | Finding | Verdict | Action |
|---|--------|---------|---------|--------|
| 1 | edge-case | FE: stale `reportType` submitted after a mid-session gate flip (form falls back to job pickers, submit doesn't) | medium — real, reachable on profile refresh | **patched** — submit + form follow `availableTypes` (fallback to first offered), `rawReportType` kept separate |
| 2 | edge-case | FE: one failed offices/enrolments load latched empty pickers (`scopeLoadedRef` never reset) | medium | **patched** — un-latch on failure; re-selecting the type retries |
| 3 | edge-case | BE: fetch holds 1 of 5 pool connections across unbounded Supabase reads (no HTTP timeout) | medium — bounded by worker concurrency 1; pre-existing exposure class for Supabase-side hangs | **defer** — follow-up: bound fetch duration (AbortSignal) or move Supabase reads outside the tx; recorded in epic follow-ups |
| 4 | edge-case | BE: `.range()` offset pagination without `.order()` → page skew under concurrent writes | medium | **patched** — `.order('id')` on users/enrolments/attempts paged reads |
| 5 | edge-case | BE: office-scoped report audits rejections for OUT-of-scope employees | medium | **patched** — audit runs over in-scope employees (`summaryIds`); test pins the `.in('employee_id', [E2])` shape |
| 6 | edge-case | BE: `enrolledFrom` computed from the office-FILTERED rows → mid-range office move mislabeled as mid-period join | low | **patched** — annotation reads the unfiltered grid |
| 7 | edge-case | claim: FE employee picker "narrowed by chosen offices" | false — spec said "optionally", never implemented | **doc fixed** — design-notes now says v1 does not narrow |
| 8 | edge-case | claim: "rejection counts read in the same transaction" | false as written — audit is a Supabase read outside the tx (day flags + leave rows ARE in-tx) | **doc fixed** — epic 21-2 wording corrected |
| 9–16 | verification-gap | 8 unpinned surfaces (mutation-verified green under regression): service never exercises `validateAccess`; per-definition `maxTechnicianIds` cap untested through the service; job-report strict `officeIds` rejection unpinned; registry registration unpinned; FE screen gate read + submit payload unverified; fetcher Supabase query shapes (`.filter('valid','ov',…)` / `.neq('outcome','ok')` / IST window) unasserted; `officeCount` non-null mapping untested; `REPORT_MAX_ATTENDANCE_ROWS` env key unpinned | medium each (the lens proved each regression ships green) | **all patched** — new/extended specs: reports.service (validateAccess 400 + queued + non-enrolled 400 + 26-person cap), report-registry.spec, technician-job-activity.definition.spec (officeIds), report-pipeline.spec (env-configured maxRows), attendance.data.spec (call-shape recorder + shape tests), ReportsScreen.test (useMyProfile mock: gate on/off + payload seam) |
| 17 | verification-gap (other) | `resolveTenantToday` duplicates `enrolments.repository.tenantToday` byte-for-byte, nothing pins them in sync (NFR5 forbids common→attendance import) | low | **defer** — acceptable duplication forced by layering; noted in epic follow-ups |

Final state: fenzit-be 1,489 tests green · fenzo-app suite green after patches (api-client
base-URL pin failure was the TEMPORARY local-BE config flip for the device build — reverted
before commit). The verification lens independently confirmed: re-export shims are exercised
through the old paths, the grid/parity decisions are pinned, no stale `readDayStatusGrid`
imports remain.
