# Attendance Report — PDF content catalog

Load-bearing content contract for CAP-3. Section order, metric definitions, and formulas are normative; layout mechanics (column splits, font sizes) belong to the dev story, composed only from brand-kit helpers.

## Research basis

Standard monthly attendance reporting practice (LarkSuite time-attendance guide, Lystloc field-staff monthly reports, standard attendance-sheet practice) converges on: workdays + clock in/out times + total hours, absences, late arrivals, early departures, half days, leaves, attendance rate %, and tardiness counts, organised as summary-first then per-employee detail. Fenzit's GPS-punch model adds signals generic tools lack: geofence rejections, fake-location attempts, missed check-outs, and manual corrections — the report's differentiator. Research-only ideas deliberately dropped for v1: break-time tracking (not captured), overtime (no OT config), leave balances (no model), payroll export (CSV fast-follow).

## Section order

1. **Header** (existing `pageHeader`): tenant name, "Attendance Report", period, scope line (`All offices · All employees` / `2 offices · 24 employees`), footer as-is.
2. **Overall summary cards** — up to 3 rows of 4 (`summaryCardRow`), plain-English labels:
   - Row 1: Employees in scope · Expected working days · Attendance rate % · Total worked hours
   - Row 2: Late arrivals (days) · Absent days · Leave days · Missed check-outs
   - Row 3: Half days · Extra days worked (holiday credit) · Corrections applied · Fake-location attempts
   - Caption rule (12-5 precedent): captions only carry real derived info (e.g. "3.1 hrs/day avg"), never filler.
3. **Office summary** table (always rendered; one row when a single office is in scope):
   `Office | Employees | Days worked | Absent | Leave | Late | Attendance % | Worked hrs`
4. **Employee summary** — the core; two stacked tables sharing one employee ordering (alphabetical, or grouped by office when offices ≤ 3):
   - **Attendance**: `Employee | Office(s) | Days worked | Full | Half | Absent | Leave | Weekly offs | Holidays | Worked on holiday`
   - **Discipline & hours**: `Employee | Late days | Late minutes | Early outs | Missed check-outs | Worked hrs | Avg hrs/day | Attendance % | Corrections | Fake-GPS`
   - Employees enrolled mid-period get a "from 12 Sep" annotation on their name; employees with zero expected days in range show an explicit "—" row rather than being dropped.
5. **Needs attention** (`flagList`, severity colours per kind — mirrors the job report's section):
   - Fake-location attempt (alarm, red) — `employee · date(s)`
   - Missed check-out (warning, amber) — payroll blocker framing
   - Absent streak ≥ 3 consecutive expected days (alarm)
   - Late ≥ 3 days in range (warning)
   - Correction applied (informational, muted) — `date · what changed`
   - Empty range → existing `emptyStateBlock`.
6. **Weekly trend** table: one row per 7-day chunk from range start: `Week (dates) | Attendance % | Days worked | Absent | Late | Leave`.
7. **Day register** — **only when range ≤ 31 days**: grid of employees × dates with single-char codes, legend row underneath. Codes: `P` present · `H` half day · `A` absent · `L` leave · `Hl` half-day leave · `W` worked on holiday · `O` weekly off · `★` holiday · `M` checkout missing · `·` not tracked / not checked in yet / in progress. Today's column renders `·` for every employee regardless of state.
8. **Leave summary**: `Employee | Approved (days credit) | Pending | Half-day leaves` — rendered only when any leave day rows exist in scope.
9. **Rejected punches audit** — rendered only when rejected attempts exist in scope: `Employee | Too far | Low accuracy | Fake location | Rate-limited | Other` (counts by outcome from `attendance_attempts`), plus a caption "Attempts never became attendance records".

## Metric definitions (normative formulas)

Derived per tracked grid row (enrolment covers the date) from the day-status engine's `DayStatusOutcome`; scope levels (overall / office / employee) aggregate the same per-row values:

- **Tracked day**: grid row with `ctx.tracked` true. Untracked days contribute to nothing (not even weekly offs — 19-3 precedent).
- **Expected working days** = tracked days − weekly_off days − holiday days (no check-in) − approved leave credits. **(Owner-confirmed 2026-10-03: leave stays out of the denominator.)**
- **Attendance rate %** = Σ daysWorked ÷ Σ expected × 100, 1 decimal; rendered as "—" when expected = 0. Days-worked credit includes half-day-leave earned halves and half days (0.5 steps), matching the monthly grid.
- **Worked hours** = Σ workedMinutes ÷ 60, 1 decimal, over rows with non-null workedMinutes. Open/missing-checkout days contribute nothing to hours — their count is visible in Missed check-outs (deliberate under-count, shown next to its cause).
- **Late days / late minutes**: rows with `isLate` (count) and Σ `lateMinutes`. Suppressed on off-day statuses by engine rule — report inherits, never recomputes.
- **Early outs**: rows with `earlyCheckout` true.
- **Missed check-outs**: rows whose markers include `checkout_missing`.
- **Corrections applied**: rows whose markers include `corrected`.
- **Fake-location attempts**: count from `attendance_attempts` (`outcome = 'mocked'`) in scope, regardless of acknowledgement (**owner-confirmed 2026-10-03**); the day-level `fake_location_attempt` marker (unacknowledged only) drives the Needs-attention alarm, acknowledged attempts stay counts-only.
- **Rejected punches**: `attendance_attempts.outcome ∈ {too_far, low_accuracy, mocked, rate_limited, stale_fix, …}` grouped by outcome; `ok` attempts excluded.
- **Leave summary**: Σ `leaveCredit` (approved) per employee; pending days from pending `leave_request_days` covering the range (status counts, not credits).

## Layout rules

- Portrait A4 only (engine constant); the ≤ 31-day register cutoff is owner-confirmed (2026-10-03) — a landscape register for longer ranges is out of v1.
- Employee tables paginate naturally (pdfmake table breaking); a register never wraps inside `unbreakable` stacks (12-5 `kept()` discipline, small stacks only).
- Exceptions list caps at 200 rows with a final "+N more — narrow the filters" line.
- Every number rendered must be traceable to a grid-row outcome; the template never derives attendance math itself (it receives pre-aggregated values from the fetcher's metrics module).
