# 27-1 — `from`/`to` date-range filter on the owner leave list

| | |
|---|---|
| Status | ready-for-dev (card created 2026-11-24) |
| Size | S (~0.5–1 day) |
| Layer | BE (fenzit-be) — the epic's only API change, **build first** |
| Depends on | none |
| Contract | owner AskUserQuestion 2026-11-24 ("Add from/to params") · design/DESIGN-MAP.md §API decision |

## Gap (evidence)

`ListLeaveQueryDto` (src/attendance/dto/leave.dto.ts) accepts only `status`, `employeeId`,
`cursor`, `limit` — there is no way to ask "which requests overlap November?" The web
Calendar tab (27-4), its day drill-down, and the Types tab's "Upcoming time off" rail all
need a date-bounded read; the client-side workaround caps at `MAX_PAGE_SIZE` (50) and
silently misses rows.

## Scope

1. Two optional params on the **owner list** endpoint (`GET /api/v1/attendance/leave`):
   `from`, `to` — ISO dates (`YYYY-MM-DD`), `from <= to`, else 422 VALIDATION_ERROR.
2. Semantics: **overlap** — a request matches when `start_date <= to AND end_date >=
   from` (a request spanning the window edge matches; this is what a calendar needs).
3. Composes with the existing params: `status=approved&from&to` is the calendar read;
   cursor pagination and the derived-status filter keep working unchanged (the cursor
   scope/encode is untouched — the filter is two more WHERE conditions on the same
   keyset query in leave.repository.ts).
4. Employee-scope list (the employee's own history) does NOT need it — add only if it
   falls out of the same DTO for free; do not broaden the surface.
5. Swagger annotations on both params.

## Out of scope

Per-status counts, a dedicated `/leave/calendar` endpoint (owner: don't make the API
heavy — the param is the simple form), month-string params, timezone shifts (dates are
tenant-local ISO strings already used throughout the module).

## Technical approach

- DTO: two `@IsOptional() @IsString() @Matches(/^\d{4}-\d{2}-\d{2}$/)` fields (the
  module's existing date-param idiom — copy the apply-form's date validators).
- Repository: extend `listLeaveRequests` input + WHERE with the two conditions; the
  existing index on (tenant_id, …) + keyset order is unchanged — verify the planner
  doesn't regress the batched page read (leave-list N+1 lesson: the page read must stay
  O(page), and this change touches only the list query's WHERE).
- The read service threads the two params from the controller query into
  `listTransact` input — the same pass-through style as `status`/`employeeId`.

## Acceptance criteria

1. `status=approved&from=2026-11-01&to=2026-11-30` returns exactly the approved
   requests overlapping November — including one starting 2026-10-28 ending 2026-11-02
   (left-edge overlap) and one starting 2026-11-29 ending 2026-12-03 (right-edge).
2. `from > to` → 422; malformed dates → 422; omitting both → byte-identical behavior to
   today (regression: existing page + cursor tests keep passing untouched).
3. Cursor paging across a filtered window works (nextCursor still walks the filtered
   set; no rows skipped or repeated).
4. Tenant isolation: the filter never widens beyond the caller's tenant (existing RLS +
   tenant WHERE untouched).

## Test anchors

- leave-controllers.spec.ts / leave-read.service.spec.ts patterns for the list query —
  add the overlap matrix (inside/left-edge/right-edge/enclosing-window/no-overlap) and
  the compose-with-status case.

## Risks / gotchas

- The derived-status filter runs on `derived_status` computed from day rows — status +
  date compose fine, but pin a test: a partially-revoked November request with
  status=revoked still matches the November window.
- Deploy note: ship and verify live before any web story consumes it (fenzit-be deploys
  first — repo ordering rule).

## Code review (BMAD thorough, 2026-11-24)

Four-lens review of the 269-line diff (blind-hunter / edge-case / verification-gap /
intent-alignment), step-03 triage verified every claim at its cited line. Outcome:
**0 decision-needed · 5 patch · 0 defer · 5 rejected.** All 5 patches applied before
commit; full suite 3484/3484 + typecheck clean post-patch.

### Applied
- House validator swap: `from`/`to` moved off `@IsDateString({strict:true})` (admits
  datetimes/week-dates → lexicographic pairing misfires) onto
  `@Validate(AttendanceCalendarDateConstraint)` — exact YYYY-MM-DD shape + real
  calendar dates, the module's house idiom.
- Pair-required 422: `listForOwner` refuses a half-supplied window
  (`from` XOR `to` → 422 VALIDATION_ERROR "from and to must be sent together")
  before the transaction; DTO alone couldn't see the pairing.
- DTO spec window cases: well-formed window passes; garbage `from`, impossible
  `2026-02-30` (calendar-aware), and a datetime string all fail.
- `ListMeLeaveQueryDto extends OmitType(ListLeaveQueryDto, ['from','to'])` — the
  me-endpoint neither validates nor advertises the owner-only window (was silently
  stripping via whitelist, now the contract is explicit).
- Doc nits: overlap semantics spelled on both fields; OmitType javadoc.

### Rejected (with reasons)
- "One-sided test can't hit the service check" — unreachable post-pair-422 (the DTO
  passes one valid date alone, so only the service guard sees it; test now goes
  through the service and asserts no query ran).
- Behavioral/real-DB overlap matrix + param-mapping assertions on live SQL — semantics
  text-pinned in the DTO docs; mapping asserted literally in the read-service spec;
  live overlap behavior is this story's deploy-verify step (owner-ordered next).
- "Reserve from/to on the me-endpoint for future callers" — speculative; fields stay
  absent there by design.
- Two descriptive findings (doc phrasing) — non-defects.

Deploy: committed + pushed 2026-11-24 → Render auto-deploy → live window check
(status=approved&from&to) precedes any FE consumption.
