# 26-11 — Mobile payslip YTD hero

| | |
|---|---|
| Status | ready-for-dev (card created 2026-11-21) |
| Size | S (~0.5–1 day) |
| Layer | App (fenzit-app) |
| Depends on | 26-10 (YTD/breakup fields on the DTO) |
| Contract | 05 §6 quick-win · 04 §mobile · 03 §6 |

## Gap (evidence)

The mobile app shows payslip history + PDF (23-12, released 1.4.6/1.4.7) but nothing
answers "what have I earned/ been taxed this year?" — Frappe's ESS home leads with a
YTD hero reading the last slip's `year_to_date` + a FY selector
(frontend/src/views/salary_slip/Dashboard.vue; fields gross_pay/net_pay/year_to_date —
04 §mobile). Pure pattern-transfer; no new BE.

## Scope

1. Payslips home gains a YTD hero card: FY earnings, FY TDS (from 26-10 fields on the
   latest slip).
2. FY selector (April–March) filtering the history list + hero (older FYs read from
   that FY's slips).
3. Payslip detail: grouped earning/deduction sections (respecting 26-2 types via the
   DTO) — layout follows the existing payslip detail screen.
4. Sticky Download PDF action on detail (Frappe ESS pattern; current app already has
   download — make it sticky per the pattern if not already).
5. Honest empty states: months without slips, first-job employees, mid-year joiner
   (hero shows partial-year YTD with the joined-month context).

## Out of scope

Tax forecast/projection UI (deferred with declarations), regime display, dispute flow
(LATER), web console YTD (26-8 stays roster-only).

## Technical approach

- Consume the 26-10 DTO fields; no client-side YTD math (single source of truth on the
  slip — the app must never recompute payroll numbers).
- Locked-months-only visibility rule (existing 23-12 contract) untouched — the hero
  reads only from visible slips.
- RN structure: follow the existing payslips feature folder conventions
  (src/features/payslips/*); service layer via payrollPayslips resource.

## Acceptance criteria

1. Hero + selector render FY totals from the DTO; switching FY re-reads from that
   FY's slips (no cached-stale totals).
2. Grouped sections match the slip's lines exactly (no client aggregation).
3. Empty/edge states: no slips, mid-year joiner, FY with zero TDS.
4. **done_checkpoint: device pass** on the Pixel 6 (DEBUG build via Metro; screenshots
   over dumps — uiautomator lies).

## Test anchors

- App test files follow the 23-12 five-file pattern (RTR gotchas: JSX array children
  break exact Text matchers; drive via props on fresh root outside nested act).

## References

Frappe ESS: Dashboard.vue YTD hero + FY selector; Detail.vue sticky download +
`/api/method/hrms.api._download_pdf` (04 §mobile). ui-shots/mobile-salary.webp.

## Risks / gotchas

- Older-FY data exists only if those months ran under 26-1's parameterized table —
  the selector must degrade gracefully (hero hidden, list intact) when a FY has no
  breakup fields (pre-26-10 slips).
- Don't promise future-tax numbers in the hero (that's the deferred declarations
  cluster); YTD-to-date only.
