# Plan — Story 23-5: Deduction heads and statutory engine (BE)

- **Status:** built → review (2026-11-17, overnight run 2)
- **Story:** epic-23 id 5 (BE) · CAP-6 · spec: artifacts/specs/spec-payroll/ (SPEC.md CAP-6, canonical-fixture.md = test oracle, statutory-verification.md = legal citations)

## Intent

The run engine (story 6) needs two more config surfaces and the pure statutory math: company-level **deduction heads** (flat or percentage, basis basic|gross, computed on the EARNED basis amount), the **PF-covered switch** as effective-dated config with per-employee exclusions, and the **statutory computation module** — PF on earned basic with the effective-dated wage ceiling (₹15,000 until 2026-09-16, ₹25,000 from 2026-09-17, S.O. 5109(E)) and the new-regime FY 2026-27 TDS estimator (Income-tax Act 2025 slabs, ₹75,000 standard deduction, resident-only s.157 rebate with marginal relief, 4% cess). Zero RPC — DDL migration only, all logic NestJS, the math as pure functions the run engine calls.

## Scope matrix (this story vs story 6)

| In 23-5 | Out (lands with 23-6's run engine) |
|---|---|
| Heads CRUD + month-start resolution fn | Applying heads to payslips |
| PF switch rows + resolution fn + exclusions | The covered-decision per employee per run |
| Pure PF/TDS math (fixture-oracle unit tests) | LOP/window inputs feeding it |
| TDS config read endpoint | Spread/re-spread bookkeeping, overrides, 50% cap, recovery lines |

The story text's "a 2026-09 run resolves ₹15,000 (PF 1,800.00)" is asserted here as PURE-module tests on the September inputs (earned basic 19,230.77 → PF 1,800.00) — the run-shaped assertions (variant B/H net pays) land in story 6's journey legs.

## Schema (migration 20261117220000_deduction_heads_pf_and_exclusions.sql)

- `payroll_deduction_heads` — id uuid pk, tenant_id fk→tenants cascade, name text not null, kind text not null check (kind in ('flat','percent')), amount text not null (flat money; percent 0<p≤100, ≤2dp), basis text check (basis in ('basic','gross')) — percent-only, effective_from date not null, active boolean not null default true, timestamps; unique (tenant_id, name, effective_from). Deny-by-default RLS, service_role only.
- `payroll_pf_config` — tenant_id fk, effective_from date, covered boolean not null, timestamps; unique (tenant_id, effective_from). Same RLS.
- `payroll_pf_exclusions` — tenant_id uuid not null, membership_id uuid not null, excluded boolean not null, updated_at timestamptz not null default now(), unique (tenant_id, membership_id), composite FK through memberships (id, tenant_id) (house rule). Same RLS.

## Code map

- `src/payroll/statutory.ts` (NEW, pure, no I/O) —
  - `PF_RATE = 0.12`; `PF_CEILING_ROWS: [{ from: '2014-09-01', amount: '15000.00' }, { from: '2026-09-17', amount: '25000.00' }]` (statutory constants in CODE, not admin-editable tables — a compliance foot-gun otherwise; statutory-verification.md: "The config carries both values, effective-dated").
  - `pfWageCeiling(month: string): MoneyText` — resolve at month-start (≤ YYYY-MM-01).
  - `pfDeduction(earnedBasic: MoneyText, ceiling: MoneyText): { employee; employer }` — roundMoney(0.12 × min(earned, ceiling)); employer = employee (recorded, never deducted).
  - `FY_2026_27` — slabs 0–4L nil · 4–8L 5% · 8–12L 10% · 12–16L 15% · 16–20L 20% · 20–24L 25% · >24L 30%; `standardDeduction: '75000.00'`; rebate s.157: threshold 12L, ₹60,000 = 100% of tax ≤ 12L, marginal relief above; `cessRate = 0.04`.
  - `annualTax(taxableAnnual: MoneyText): { tax; rebate; marginalRelief; cess; total }` — slab walk; taxable ≤ 12L → rebate = tax (capped 60,000 = the slab tax at exactly 12L) → 0; above 12L → relief = max(0, (tax + cess) − (taxable − 12,00,000)); total = tax + cess − relief.
  - `tdsPerMonth(totalAnnual: MoneyText, months: number): MoneyText` — roundMoney(total / months); months < 1 refused.
  - Assumption documented: resident-only (Indian SME payroll; new regime is the default without a declaration — statutory-verification.md). 15-day EPFO joiner convention: v1 ships exact earned basic; divergence documented per the story (the plan closes the Open Question, not inherits it).
- `src/payroll/deduction-heads.service.ts` (NEW) — calendar-service idiom: list (name asc, effective_from asc), save (same name+date replace; identical no-op; audit `payroll.head_saved`), deactivate (active=false; a deactivated head drops out of resolution). Validation: percent needs basis, needs 0<p≤100 (≤2dp); flat needs NO basis, amount money > 0; invented date refused. Exported `resolveHeadsForMonth(rows, month)` — per name resolveEffective(rows-of-name, month), drop inactive; consumed by 23-6.
- `src/payroll/pf-config.service.ts` (NEW) — covered-switch rows (list + save, calendar idiom, audit `payroll.pf_config_saved`) + exported `resolvePfCovered(rows, month)` (absent rows → false). Exclusion service on the same file? No — separate small service `payroll-pf-exclusion.service.ts`: read (absent → false), save (exclusion=true REFUSED for an ever-member — UAN or PF account number populated on the membership row — 422 naming the rule; false always allowed; audit `payroll.pf_exclusion_set`). Exported pure rule for 23-6: `employeePfCovered({ everMember, switchCovered, excluded })` = everMember || (switchCovered && !excluded).
- `src/payroll/dto/payroll-deductions.dto.ts` (NEW) — head DTOs (tri-state idiom: absent → default, null → refused), PF config DTOs, exclusion DTO, `TdsConfigView`.
- `src/payroll/payroll-heads.controller.ts` (NEW) — GET/POST/PUT /payroll/deduction-heads, PUT .../:headId/deactivate — all @Can('payroll.config').
- `src/payroll/payroll-statutory.controller.ts` (NEW) — GET/PUT /payroll/pf-config, GET/PUT /payroll/employees/:userId/pf-exclusion, GET /payroll/tds-config (read-only view of the FY 2026-27 constants) — @Can('payroll.config').
- Module wiring + audit via the shared `writeAuditRow`.

## Fixture-oracle unit tests (statutory.spec.ts — the heart)

- PF: variant A 12% × min(17,307.69, 25,000) = **2,076.92** · variant C 12% × 9,230.77 = **1,107.69** · variant H ceiling binds 12% × min(2,00,000, 25,000) = **3,000.00** · September month `pfWageCeiling('2026-09')` = 15,000 → 12% × 19,230.77 → **1,800.00** · October → 25,000 · boundary 2026-09-16 row vs 2026-09-17 row · employer = employee, both '2076.92'.
- TDS: fixture A taxable 1,21,000 → **0.00** (rebate) · fixture H taxable 16,05,000 → tax 1,21,000, cess 4,840, relief 0, total **1,25,840.00**, ÷6 → **20,973.33** · ≤12L with tax (11L → tax 50,000 → rebate → 0) · near-threshold marginal relief 12,05,000 → payable **5,000.00** · just above (13,00,000 → total 78,000, relief 0) · slab boundaries 4L/8L/12L/16L/20L/24L exact · spread ÷1, ÷6, months<1 refused.
- Heads resolution: 2026-10 → PT 200; after a 2026-11-01 revision → 250; deactivated drops out; per-name independence.
- Pf covered resolution: absent rows → false; mid-month-dated switch invisible to its own month; ever-member rule truth table.

## Journey legs (~5)

1. Heads: flat PT ₹200 + percent insurance 2% gross (variant B) persist; percent-without-basis refused; flat-with-basis refused; percent 0/150 refused; invented date refused; same-date replace + no-op (audit counts); deactivate.
2. Heads list shows both rows; a 2026-11-01 PT revision row coexists (resolution pinned by unit tests).
3. PF config: PUT covered-on effective 2026-09-01; same-date replace; no-op; audit count.
4. Exclusion: employeeA (UAN populated) refused 422 naming ever-member; a never-member saved 200, DB row assert; save false → no write.
5. TDS config GET returns the exact FY 2026-27 constants (slabs, 75,000, 12L/60,000 rebate, 4% cess).

## Acceptance criteria

- Pure module reproduces every statutory number the fixture pins (A/C/H/September-ceiling rows above) — verified by unit tests importing the fixture values verbatim.
- Heads/PF/exclusion config surfaces behave per the calendar idiom (month-start resolution, same-date replace, no-op, audit).
- `bun run test`, typecheck, lint, journey (extended) all green except the known sync/users baseline reds.

## Design notes

- **Statutory constants live in code, not tables:** the ceiling and slabs are statute, not policy — an admin-editable surface would be a compliance foot-gun; the pure module pins them with the fixture's own numbers as tests. If a future notification changes them, it is a one-line code change with a dated row.
- **Heads mirror the components idiom** (active flag mutable, effective-dated amounts) so the resolution semantics stay one vocabulary across payroll config.
- **The covered decision stays split:** ever-membership (data) + switch resolution (month-start) + exclusion (config) meet in `employeePfCovered` — pure, truth-table-tested, consumed by 23-6.
- **No rounding-chain surprises:** every fixture number here is exact under half-up-once; the module rounds ONCE per emitted money figure (reuse formula.ts roundMoney/moneyText).

## Verification

- `bun run test src/payroll` — all green.
- Journey: `node --env-file=.env node_modules/.bin/jest --config ./test/jest-e2e.json test/payroll-journey.e2e-spec.ts`.
- `bun run typecheck`, `bunx eslint` on touched files.

## Plan Change Log

## Review Triage Log

## Implementation Notes

## Code Review

### 2026-11-18 (overnight run)

**Code review complete.** 0 decision-needed, 13 patch, 2 defer, 2 rejected. (Two rounds: 4 ponytail lens agents — correct/safe/fast+lean/tested — plus the BMAD thorough workflow with edge-case-hunter and verification-gap lenses; every claim verified at source before a verdict; the claims file's "no NaN emission" claim was FALSIFIED by the hunter — tdsPerMonth emitted 'NaN' — and fixed.)

- [x] [Review][Patch] The deactivate route was unreachable — the view/HEAD_COLUMNS omitted `id`, so no client could learn the handle [deduction-heads.service.ts, dto] — APPLIED: id exposed on the view; the journey deactivate leg now uses the API-visible id.
- [x] [Review][Patch] An identical re-save over a RETIRED head revision was a silent no-op — the head stayed retired with no audit [deduction-heads.service.ts:106] — APPLIED: the no-op requires active===true; a re-save re-enacts (upsert sets active: true) and audits; unit test + reconciled API docs.
- [x] [Review][Patch] pfWageCeiling silently mis-resolved a malformed month ('2026-9' → ₹25,000 for September — verified empirically) [statutory.ts:34] — APPLIED: isMonthKey guard + throw; three unit rows.
- [x] [Review][Patch] tdsPerMonth emitted "NaN"/"Infinity" for non-finite input (the module's own refuse-loudly claim was falsified) [statutory.ts:183] — APPLIED: isFinite + non-negative guard; unit rows.
- [x] [Review][Patch] Non-uuid :headId/:userId answered 500 instead of the siblings' ParseUUIDPipe contract [controllers] — APPLIED: ParseUUIDPipe on all three params.
- [x] [Review][Patch] resolveHeadsForMonth / resolvePfCovered accepted malformed months (lexical mis-resolution) [services] — APPLIED: isMonthKey guards + unit rows.
- [x] [Review][Patch] Negative statutory inputs passed silently (pfDeduction/annualTax/tdsPerMonth) — APPLIED: non-negative refusals + unit rows.
- [x] [Review][Patch] Head name had no length cap (sibling components cap 60) — APPLIED: @MaxLength(60) + DB CHECK (char_length 1-60) via migration 20261117230000.
- [x] [Review][Patch] payroll_pf_config had no PK — APPLIED: id uuid PK (calendar idiom) via migration 20261117230000.
- [x] [Review][Patch] Both list GETs had no happy-path observer (the plan's leg was dropped) — APPLIED: journey GETs assert the heads list (name/date order, amounts, id) and the pf-config list equals the PUT answer; resolves the API-doc contradiction on re-enact semantics.
- [x] [Review][Patch] 403 sweep missed the deactivate route + three GETs (the "every write route" comment was false) — APPLIED: employee AND platform-admin tokens probe all five, with DB active-row-count guards.
- [x] [Review][Patch] PF-config/exclusion audit counts unobserved (plan leg dropped) — APPLIED: journey asserts payroll.pf_config_saved = 1, payroll.pf_exclusion_set = 2.
- [x] [Review][Patch] Coverage: PF divisor-table rows (2,120.00/2,129.03) + half-day 2,030.77; percent boundaries 100/0.01; 12-digit flat boundary; same-name different-date second revision; pf-config same-date replace; saveError 500s ×3; truth table 8/8; whitespace-name refusal; true .xx5 spread case — APPLIED (unit rows).

**Rejected** (with refutations):
- Exclusion-save race (UAN gained between probe and upsert) — false at the run level: employeePfCovered checks everMember FIRST, so any exclusion flag is inert for an ever-member regardless of the race; the config-time refusal is advisory hardening, not the enforcement point.
- Fast+lean F6 (toView mapper consolidation) — note-only; the run engine (23-6) lands the consumers; extracting now would churn three services for zero behavior.

**Deferred** (ledgered in deferred-work.md): empty-string UAN/PF-account data hygiene (23-1 employment save); roundMoney epsilon-comment overclaim (shipped 23-3 code).

**Verification after all patches:** 267/267 payroll unit tests (11 suites), 42/42 journey legs (real DB), typecheck clean, eslint clean on touched files, full suite at baseline reds only (sync/users 6). Story-6 handoff notes: everMember derivation lives inline in pf-exclusion.service (export it when the run engine consumes it); resolveEffective tie rule is last-in-array-wins (documented in effective-dating.ts).
