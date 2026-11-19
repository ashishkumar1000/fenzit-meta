# Plan — Story 23-10: Web payroll configuration (fenzit-web)

- **Status:** plan → adversarial review
- **Story:** epic-23 id 10 · fenzit-web · baseline_revision a46eece (clean tree)
- **Context:** plan-23-1/3/4/5 (the BE contracts this consumes); the shipped fenzit-be controllers are the wire truth. Companion story 23-11 takes runs/lock/off-cycle/audit — NOT here.

## Intent

**Problem:** every epic-23 payroll config surface (employment data, salary components, salary structures, deduction heads, the PF switch and per-employee exclusions, the payroll calendar and state-rules flag) is API-only. The owner cannot set up pay without curl. The mobile stories (12/14) need balances and payslips, not config — the web console is the config surface.

**Approach:** one new console page `/admin/company/payroll` (owner-only), tabs like the jobs page (URL-owned `?tab=`, the loader fetches only the active tab's data): **Components** (library CRUD), **Structures** (per-employee effective-dated revisions + a constrained formula builder), **Deductions** (heads CRUD + deactivate-with-confirm), **Statutory** (PF switch rows, per-employee PF exclusion picker, read-only TDS constants), **Calendar** (dated calendar rows + a month-status probe + the state-rules notified flag). Employment data lands on the existing Employees page as a per-row dialog backed by a React Router **resource route** (`company/employees/employment` — loader for the GET, action for the PATCH), so the dialog loads fresh data on open and the table refreshes after a save. Zero BE changes — every endpoint shipped in 23-1/3/4/5.

## Boundaries & Constraints

**Always:** the house page idiom — loader owns data (no `useEffect` fetching; ESLint bans it), URL owns all state (tab, employee, month), every list renders loading/empty/failed states, dialogs are native `<dialog>` + `showModal()` with `fetcher` submissions and inline `role="status"`/`role="alert"` results, CSS modules only (`className={styles.x}`, never string literals), plain-English copy says "Employee". New API wrappers live in `src/features/admin/payrollApi.ts` (views in `src/features/admin/payrollViews.ts`) typed from the BE views. Money renders via a shared formatter (Number → ₹, `Intl` en-IN); money inputs normalize to 2dp text (`"20000.00"`) before send. **BE-4xx messages are shown verbatim via the error BODY:** `ApiError.message` is always the generic "Request failed with status N" (api.ts:120-125) — the BE's plain-English copy rides `error.body.message`, so the payroll action error helper narrows `body` to `{message: string}` and prefers that for 400–499 EXCEPT 403 (the guard's message is developer copy; `messageForError`'s FORBIDDEN line is better there), falling back to `messageForError` otherwise — a deliberate exception to the errorMessages.ts "never show ApiError.message" note, which was written before the payroll BE carried user copy. Mutations ride the page action (one action, `intent`-keyed) except the employment dialog, which posts to its own resource route. Client-side guards are wire-shape only (required fields, amount shape, one line per component); a duplicate-name annotation is advisory only — the save always sends and the BE's 409 copy is the truth. Every domain refusal (February reason, basic-missing, cycle chain, in-use list, ever-member exclusion) stays with the BE — the client renders its copy, never re-implements it. The formula builder's 0 < p ≤ 100 bound is a UI rule (the BE accepts wider shapes); AST tests pin what the builder emits (JSON numbers, `{kind:'percent-of'|'binary'|'component'|'const'}` per formula.ts), not a claimed BE constraint.

**Never:** no run trigger, lock, off-cycle, audit or payslip UI (23-11); no BE changes; no new shared design tokens (locked design system); no raw-JSON formula editing (the builder covers percent-of-component ± const — nested ASTs are accepted-by-BE but not offered; noted in the plan as a v1 limit); no DELETE on components (BE has deactivate only); no direct renders of PAN/DOB/bank in any list — the employment data shows ONLY inside the per-employee dialog; no `git add -A`-style commits from the meta root (commit in fenzit-web with explicit paths).

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Payroll nav | owner opens `/admin` | "Payroll" section link present (after Employees); member/staff never see it; hand-typed `/admin/company/payroll` as member → redirect `/admin` | — |
| Tab deep link | `?tab=structures` | structures tab renders; unknown tab → components | — |
| Components list | GET `/payroll/components` | table name-asc: name, Basic pill when isBasic, active state; empty state names Basic-salary-first | failed → retry line |
| Add component | dialog POST `{name, isBasic?}` | 201 → list refetches; duplicate 409 → BE message | inline alert |
| Edit component | dialog PATCH `{name?, isBasic?, active?}` | tri-state body (untouched key absent); BASIC_COMPONENT_EXISTS / SALARY_COMPONENT_IN_USE messages shown | inline alert |
| Deactivate referenced | PATCH active:false, referenced | BE 409 lists employees — shown verbatim | inline alert |
| Structures picker | `?employee=<uuid>` | Dropdown of active/invited employees (name + code); no employee chosen → picker-only empty state; unknown uuid → the loader maps the BE 404 to the same picker-only empty state (a genuinely failed fetch still renders the retry line) | — |
| Structure revisions | GET `/members/:userId/salary-structures` | dated rows oldest-first with computed amounts; empty → "no structure yet" | — |
| Save structure | PUT `{effectiveFrom, lines}` — amount line or built AST | 200 → list refetches; computed amounts shown | inline alert (cycle/negative/zero-div/missing-basic verbatim) |
| Editor on a deactivated component | a prefilled revision line references a since-deactivated component | the line renders pinned (read-only, marked "component is deactivated") with an explanation — a save carrying it is refused 422 by the BE, so the owner drops the line or reactivates first; the picker lists active components only | inline explanation, no silent round-trip failure |
| Formula builder | mode Formula: percent (0<p≤100) + of-component + optional ± const | emits `{kind:'percent-of',...}` / `{kind:'binary',...}` AST; const rounded 2dp | client guards shape only |
| Duplicate component line | picker hides/drops already-chosen components | client-enforced; BE 422 backstop | — |
| Heads | GET list; POST `{name, kind, amount, basis?, effectiveFrom}`; PUT `:headId/deactivate {confirm:true}` | percent row shows basis; percent-without-basis blocked client-side with hint; flat-with-basis blocked client-side; deactivate needs the confirm checkbox | BE 422 verbatim |
| PF switch | GET rows; PUT `{effectiveFrom, covered}` | rows list + save form; empty list → "PF is off" card | BE 422 verbatim |
| PF exclusion | GET `/payroll/employees/:userId/pf-exclusion`; PUT `{excluded}` | picker + current state + toggle; the epoch `updatedAt` (1970 sentinel) renders as "never set", never a date; ever-member refusal shown verbatim | inline alert |
| TDS card | GET `/payroll/tds-config` | read-only: tax year, regime, standard deduction, slab table, rebate, cess | failed → quiet line |
| Calendar | GET rows; PUT `{effectiveFrom, divisorConvention?, cutoffDay?, payDate?}` | dated rows (absent fields = defaults noted in the hint); cutoff 29 / payDate 8 → BE February/CoW messages verbatim | inline alert |
| Month status | `?month=YYYY-MM` probe input | GET `/payroll/months/:month` card: resolved divisor/cutoff/payDate + governing row date or "defaults", firstPayrollMonth, notRunnableReason | 400 → hint |
| State rules | GET/PUT `/payroll/state-rules {notified}` | toggle card with last-updated | inline alert |
| Employment dialog | Employees page row → dialog opens → GET via resource route `?userId=` | all 15 fields prefilled; save sends a computed-diff PATCH: a field rides the body ONLY when its value differs from the loaded value, and an emptied touched field sends `""` (the BE's trim-clears semantics) — untouched fields are never in the body, so nothing can be accidentally cleared; employeeCode emptied is blocked with a hint (BE: never clearable) | 409 code-taken / EMPLOYMENT_RECORD_CHANGED verbatim; PAN/IFSC shape hints |
| Employment refresh | save done | resource route re-loaded + page revalidated (code column reflects the change) | — |

## Code Map

- `src/features/admin/payrollViews.ts` (NEW ~140 lines) — the BE view types, camelCase exactly as the services map them.
- `src/features/admin/payrollApi.ts` (NEW ~240 lines) — typed wrappers: components GET/POST/PATCH; structures GET/PUT; heads GET/POST/deactivate; pf-config GET/PUT; pf-exclusion GET/PUT; tds-config GET; calendar GET/PUT; month-status GET; state-rules GET/PUT; employment GET/PATCH.
- `src/features/admin/payrollLoaders.ts` (NEW ~230 lines) — `adminPayrollLoader` (requireConsoleRole ["owner"], tab switch, per-tab fetches: structures tab also loads members+components; statutory tab loads members for the exclusion picker; calendar tab honors `?month=` and maps a 404 structures read to the picker-only empty state), `payrollEmploymentLoader` (resource GET, `requireConsoleRole(request, ["owner"])` — the resource URL carries PAN/DOB/bank and must never leak past the role gate), `payrollEmploymentAction` (resource PATCH).
- `src/features/admin/payrollAction.ts` (NEW ~260 lines) — the page action, intent-keyed: `component-create` / `component-update` / `structure-save` / `head-save` / `head-deactivate` / `pf-config-save` / `pf-exclusion-save` / `calendar-save` / `state-rules-save`; shared `beActionError` helper (narrow `error.body.message` for 400–499 except 403, `messageForError` fallback).
- `src/pages/AdminPayrollPage.tsx` + `.module.css` (NEW ~250 lines) — TopBar + greeting + `<Tabs>` (components/structures/deductions/statutory/calendar) + per-tab panel delegation; failed-state early return.
- `src/features/admin/components/payroll/` (NEW dir) — `ComponentDialogs.tsx`, `StructureEditor.tsx`, `HeadForm.tsx`, `StatutoryPanel.tsx`, `CalendarPanel.tsx`, `EmploymentDialog.tsx`, each ≤ ~300 lines and **each with its own paired `<Name>.module.css` + the exact `import styles from "./<Name>.module.css";` line (check:styles enforces the pairing on every non-test tsx under src/features; importing another file's module does not satisfy it)**.
- `src/features/admin/components/MembersTable.tsx` (PATCH) — new "Payroll" column: active employees get an Employment cell (dialog trigger); invited/removed rows stay `—`.
- `src/app/routes.tsx` (PATCH) — `company/payroll` child (lazy page+loader, action) + `company/employees/employment` resource child (loader+action, no Component).
- `src/features/admin/adminLoader.ts` (PATCH) — sectionsFor(owner) gains Payroll; `src/pages/AdminPage.tsx` (PATCH) — GLYPHS entry + SECTION_BLURBS blurb; `src/app/pageMeta.ts` (PATCH) — CLIENT_ONLY_TITLES entry; **`src/pages/AdminPage.test.tsx` (PATCH) — its `sectionsFor("owner")` `toEqual` pin gains the Payroll path.**
- `src/testing/payrollPageKit.tsx` (NEW) — renderAt + honest fakes for every payroll endpoint (components/structures/heads/pf/calendar/month/tds/state-rules/employment), `setUpPayrollPageTests()`, `lastSent(method, path)` helper.
- Tests (NEW, colocated): `AdminPayrollPage.tabs.test.tsx`, `.components.test.tsx`, `.structures.test.tsx`, `.deductions.test.tsx`, `.statutory.test.tsx`, `.calendar.test.tsx`, `EmploymentDialog.test.tsx` — wire-contract assertions (exact method/path/body via `sentRequests()`), dialog flows, error rendering, tri-state PATCH bodies, AST shape pins, nav gating (member redirect).

## Tasks & Acceptance

**Execution:**
- [ ] payrollApi.ts wrappers + types (the wire contract in one file).
- [ ] payrollLoaders.ts + payrollAction.ts + beActionError.
- [ ] AdminPayrollPage + module.css + the five tab panels + dialogs.
- [ ] EmploymentDialog + MembersTable column + resource route.
- [ ] routes.tsx + adminLoader.ts + AdminPage.tsx + pageMeta.ts wiring.
- [ ] payrollPageKit + the seven test files; `bun run test` green, `bun run typecheck` clean, `bun run lint` clean, format/check:styles/check:design-system pass.
- [ ] Browser pass on the dev server against the LIVE BE: login 9717331820 + master OTP 1039, walk every tab (reads asserted against real data; writes exercised only with clearly-labeled test rows and cleaned up after), then Employment dialog on a test row.

**Acceptance Criteria:**
- Every config surface of 23-1/3/4/5 is reachable from the console with owner-only gating; a member token never renders the page or fires its endpoints.
- Each wire contract is pinned by a test: exact paths, exact tri-state bodies (untouched key absent on PATCH; absent-means-default on calendar PUT), formula AST shape for the builder's two forms.
- BE plain-English refusals reach the user verbatim (test-pinned with a faked 422 carrying the February reason).
- The employment dialog round-trips: open loads, save PATCHes, the table's code column refreshes, employeeCode-clear is refused with a hint before send.
- Full pre-commit gauntlet green (the husky suite: lint, format:check, check:styles, check:design-system, typecheck, test).

## Design Notes

- **One page, five tabs, loader-per-tab:** the jobs-page idiom — a tab change is navigation so the backend is asked only for the tab on screen. Payroll config is used in short bursts per concern; five tiny routes would scatter the nav.
- **Resource route for employment:** the dialog needs a GET-on-open and the table needs a post-save refresh; a `company/employees/employment` child with loader+action (no Component) is the React Router idiom for both, and the layout's `shouldRevalidate` already skips non-`/admin` fetches so the layout loader never double-fires.
- **BE messages verbatim, and why:** epic-23's BE wrote its rejections as product copy and journey-pins them (February reason, CoW s.17, cycle chains, in-use employee lists). Re-mapping them through errorMessages.ts would throw the copy away; the payroll helper therefore shows ApiError.message for 4xx and falls back to the shared mapping for 5xx/unknown. Flagged for the reviewer.
- **The builder's v1 limit:** percent-of-component ± const covers HRA (40% of basic), attendance bonus and typical small-company structures. Deeper ASTs (percent-of-formula, × ÷ chains) validate and evaluate fine on the BE; the editor just does not offer them yet. A later story can widen the builder without any wire change.
- **Client guards are wire-shape only:** every domain rule lives server-side; the client renders refusals rather than duplicating them, so a BE copy change is never double-edited.

## Verification

**Commands (fenzit-web, bun only):**
- `bun run test` — all suites green.
- `bun run typecheck` — clean.
- `bun run lint` — clean.
- `bun run format:check && bun run check:styles && bun run check:design-system` — clean.
- Browser pass per Tasks; screenshots recorded to artifacts.

## Plan Change Log

- 2026-11-19 (adversarial plan review, fresh-context reviewer — 11 findings, all verified at source, all folded): [P1] the verbatim-error mechanism corrected — ApiError.message is the generic status line; the BE copy lives in `error.body.message` (api.ts:120-125), helper narrows the body and excludes 403. [P2] every new component file carries its own paired module.css (check:styles pairing rule, scripts/lib/css-modules-check.ts:35-57). [P2] structure editor renders a deactivated-component line pinned/read-only with an explanation instead of a doomed round-trip; picker filters to active components. [P2-decision] employment PATCH body = computed-diff (field rides only when its value differs from the loaded value; emptied touched field sends `""` = the BE's trim-clears; untouched keys absent — the safest of the two shapes the BE supports). [P3] AdminPage.test.tsx sectionsFor pin added to the wiring task. [P3] structures loader maps BE 404 → picker-only empty state. [P3] employment resource loader gated `requireConsoleRole(request, ["owner"])`. [P3] 0<p≤100 named as a UI rule; AST tests pin the emitted shape. [P3] PF-exclusion epoch sentinel renders "never set". [P3] duplicate-name check is advisory-only, never blocks the send. [P3] payrollApi split into api + views files; page trimmed via panel delegation (~300-line rule).

## Review Triage Log

## Implementation Notes

- **Build state (2026-11-19, autonomous overnight run, pre-review):** all code landed — payrollViews/Api/Action/Loaders/Format, six payroll components + css, AdminPayrollPage + css, the employment resource route, MembersTable Employment column (active employees only — an owner's own row stays button-free, matching the pinned settings-dialog contract), GlyphPayroll, nav + pageMeta + routes wiring (payroll child + employment resource child). TextInput widened additively (type date/month, inputMode decimal, name optional). One plan deviation recorded: `ComponentDialogs.tsx` became `ComponentsPanel.tsx` (the panel owns the table); the panels use local select elements inside dialogs rather than the search Dropdown (the pickers on Structures/Statutory use the house Dropdown; the dialog-internal selects are form fields, not filters).
- **Test kit + suites:** payrollPageKit (honest fake with method-keyed refusals, pageOf reuse for /members/page) + 7 files / 45 tests. Full suite 1028 tests / 87 files: all green except the two AdminAttendancePage failures, PROVEN pre-existing by a clean-worktree run at baseline a46eece (same 2 failures, 983 tests). A one-off load-flake (3 employees settings-dialog timeouts while 4 review agents ran) did not reproduce on rerun.
- **Live browser pass (dev server → LIVE BE api.fenzit.com, login 9717331820 + master OTP 1039, owner "Beta Yela"):** logged in; every tab walked. Components: empty state → live POST created "Basic salary" (isBasic) — the company's real first component, verified in the list with its Basic pill (screenshot saved). Structures: picker live. Deductions: empty state live. Statutory: PF-off card, per-employee exclusion picker, TDS FY 2026-27 constants exact (slabs, ₹75,000, s.157 rebate text, 4% cess). Calendar: defaults line + month probe 2026-11 resolved live (fixed-26/25/1, governed by defaults, first payable month 2026-09 from the real join dates, not locked); state-rules epoch renders "(never set)". Employees page: Employment column live; the dialog opened on a real active employee (EMP-075) with all four field groups prefilled from the GET (read-only check — nothing saved).
- **Wire-contract pins of note:** component PATCH sends only changed keys; structure PUT body carries the built ASTs (percent-of and binary + const) as JSON numbers; calendar PUT omits empty fields (absent = default); head deactivate sends {confirm:true}; employment PATCH is a computed diff (changed fields only; "" = clear; employeeCode clear blocked pre-send).

## Code Review

### 2026-11-19 (BMAD 4-lens round: blind-hunter, edge-case-hunter, verification-gap, intent-alignment — all fresh-context, all claims verified at source)

**Code review complete.** Convergent triage: 12 patch groups applied and re-verified, 4 accepted-with-reason, 0 deferred, 0 rejected-as-false. Two lenses independently found the same P1 (employment clear verb), which is the round's headline.

- [x] [P1][patch] Employment clear-flow sent `""` where the BE's clear verb is JSON `null` — shaped fields (joinDate/exitDate/dateOfBirth/pan/ifscCode) refuse `""` outright (class-validator @Matches), so clearing a joining date — the run-skip path the hint advertises — always 422'd. The resource action now maps an emptied touched field to `null` (employeeCode stays a string: the dialog blocks its clear and the BE re-refuses as backstop); comments in EmploymentDialog/payrollApi corrected; the clear test now pins `{fatherName: null, joinDate: null, pan: null}` (blind-hunter + intent-alignment, converged).
- [x] [P1][patch] Both member-gate tests were vacuous — mutation-verified by the lens (they pass with `requireConsoleRole` DELETED; `waitFor` passes on its first tick before the lazy loader fires). Rewritten to assert `router.state.location.pathname === "/admin"` + no payroll/employment fetch fired (verification-gap).
- [x] [P1][patch] Cross-employee structure save — the editor state survived Back/Forward employee changes (only the Dropdown's onChange reset it), so the save form could post employee B's userId with employee A's lines. `EditorState` now carries `employeeId` and the card renders/saves only while the URL names the same employee (edge-case-hunter).
- [x] [P2][patch] PF-switch errors were computed then dropped — no code rendered `result.message` (the empty-date refusal and every BE 4xx were invisible). Error + saved lines now render in-card; save disabled until the date is filled; busy covers the loading phase (blind-hunter + edge-case-hunter).
- [x] [P2][patch] A cleared component name was silently excluded from the diff while the dialog showed "Saved." — `nameCleared` guard with inline error + disabled save (the employment `codeCleared` idiom) (blind-hunter).
- [x] [P2][patch] The structure editor's date hint contradicted month-start resolution ("first governs the month this date starts" — the BE resolves at month start, so a mid-month date first governs the NEXT month). Reworded to the BE rule (blind-hunter).
- [x] [P2][patch] `normalizePercent` rounded 0.001 → 0, violating its own 0 < p ≤ 100 contract (runtime-verified by the lens) — bound re-checked after rounding (edge-case-hunter).
- [x] [P2][patch] A stored formula the builder cannot express degraded to a silent empty Amount — now a "Stored formula: …" caption; leaving Amount empty rides the stored formula unchanged, typing an amount replaces it (edge-case-hunter + intent-alignment).
- [x] [P2][patch] The kit never emulated the BE's 404s, so the stale-employee test passed for the wrong reason — the fake now 404s member ids not on the team (structures/exclusion/employment reads); +2 mapping tests; page-level failed-path retry-line test added (verification-gap + blind-hunter).
- [x] [P2][patch] StructuresPanel was 614 lines against the plan's ≤~300 promise — split; `StructureEditor.tsx` (+ paired css) as the plan's Code Map named (intent-alignment).
- [x] [P2][patch] The employment post-save table refresh was real but unpinned — test now counts `/members/page` GETs +1 after the dialog closes (verification-gap).
- [x] [P3][patch] Batch: busy windows cover the loading phase on every page-level submit; the deactivate refusal renders INSIDE the dialog with a done-mark + Close (was behind the backdrop); the PF-exclusion card remounts per picked employee (no result bleed across employees); the percent-of operand select excludes pinned lines; unknown component names fall back to the BE-resolved componentName; date defaults use `istToday()` (was UTC); "Moving the mark" (the BE refuses instead of moving), "Printed on payslips" (payslips ship in 23-11) and the heads "absent fields take their defaults" (a calendar contract pasted into the wrong dialog) copy fixed; percent rows trim "2.00%"→"2%"; the missing-Basic hint survives an inactive Basic (the state where the save is certainly refused); stale "Saved." on a reopened edit dialog removed (per-open remount); pinned-line comment/test renamed to the honest contract.

**Accepted with reasons (no action):**
- The month-probe card renders `locked` (intent lens: not in the plan matrix) — read-only data riding the shipped 23-4 view contract; the copy is true ("permanently"); 23-11 owns the lock UI.
- `react-refresh/only-export-components` warn ×2 (helpers exported beside components) — the repo's documented warn-level rule; lint exits 0.
- Head percent bounds are not FE-enforced (hint promises 0–100) — the BE owns the domain refusal and its copy renders verbatim; the plan's rule is that the client renders refusals, never re-implements them.
- Month-probe input/URL desync and a well-shaped month's 404 reading as the retry line — cosmetic; the BE never 404s a real month; noted for 23-11's surfaces.

**Rejected:** none — every finding verified at source before triage; no false alarms this round.

**Verification after all patches:** `bun run typecheck` clean; `bun run lint` 0 errors (2 known warns); format/check:styles/check:design-system pass; full suite 1030 tests / 87 files — 1028 green, the only 2 failures being the AdminAttendancePage pair PROVEN pre-existing by a clean-worktree run at baseline a46eece; live browser pass repeated findings (PF error now renders — exercised via the empty-date refusal).
