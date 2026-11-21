# 00 — Executive Summary: Frappe HRMS Benchmark → Fenzit Payroll V1

**Date**: 2026-11-21 · Overnight research run (3 research agents + browser UI pass + synthesis)
**Question**: What do Frappe HRMS's must-haves that Fenzit lacks, how do they implement them, and what should Payroll V1 cover?
**Answer in one line**: Fenzit's engine core is sound and ahead in audit/lock/cap semantics; the gaps are **statutory breadth (PT, PF employer split, ESI), outputs & delivery (register, bank advice, payslip email), and console completeness on APIs that already exist** — plus one time bomb: **TDS FY 2026-27 constants hardcoded, breaking April 2027**.

---

## The report set

| File | Read this for |
|---|---|
| **00-EXEC-SUMMARY.md** | This overview — verdicts and scope |
| **01-frappe-docs-feature-inventory.md** | What Frappe advertises: 47 verified doc pages, 60-row verdict table, Frappe→plain-English glossary |
| **02-frappe-payroll-engine-internals.md** | How Frappe implements it: engine pipeline with file:line quotes, tax engine, 24 verified gotchas, lean-reimplementation notes, test anchors |
| **03-fenzit-payroll-current-state.md** | What Fenzit actually has today: 50 BE files + 16 migrations + web/app surfaces, India-SMB checklist (PRESENT/PARTIAL/ABSENT), top-10 absences |
| **04-ui-ux-reference.md** | Frappe's UI/UX: desk + ESS SPA screens, 34 screenshots in `ui-shots/`, affordance-gap table, Sally takeaways |
| **05-gap-analysis-v1-plan.md** | **The plan**: consolidated matrix, what to borrow / not copy, 9 implementation-ready work items with acceptance criteria |

Method note: every claim traces to code or docs read this session (Frappe clone at `workspace/external/frappe-hrms` @ `ea4158c4`; Fenzit BE/WEB/APP repos). No public Frappe demo exists — UI research used official product shots + docs + the ESS Vue source; noted honestly in 04.

---

## Headline verdicts

### Where Fenzit is already BETTER (protect these — do not "catch up" to Frappe)
1. **Permanent month lock** (Frappe: cancel deletes slips — mutable history)
2. **Append-only audit trail** w/ actor attribution (Frappe: doc versioning only)
3. **Ownership-LOP + payroll-date gate** for backdated corrections (Frappe: recompute-at-slip-time + submit-time guard)
4. **50% deduction cap + recovery roll-forward** (Frappe: negative net → slip silently skipped in bulk runs — a verified bug-shaped gotcha)
5. **Computed PF with dated ceiling ₹15k→₹25k** (Frappe core: no PF math at all — admins write formulas)
6. Advisory-lock serialization, idempotency keys, native multi-tenancy + RLS, native RN app vs Frappe's PWA

### The real gaps (all verified in our code, not assumed)
| # | Gap | Evidence | Why it matters |
|---|---|---|---|
| 1 | **TDS FY hardcoded 2026-04…2027-03** | engine:167-168, statutory.ts:132-176 | Every slip computes wrong tax from 2027-04-01 — time bomb |
| 2 | **No Professional Tax state engine** | `payroll_state_rules` is one boolean; only flat heads | Most common small deduction in India; every tenant needs it |
| 3 | **PF employer split wrong** — employer recorded as mirror of employee | statutory.ts:52-55 ("v1: no EPS split") | Stored employer figure is factually incorrect today |
| 4 | **No salary register / bank advice exports** | reports registry holds payslip + attendance only | Owner's monthly operational loop (register → bank) uncovered |
| 5 | **No payslip email** | notifications module has zero payroll hooks | Office staff without the app never learn a payslip exists |
| 6 | **Admin payslip viewer missing** — API shipped, web never built it | GET /payroll/payslips unused by console | Cheapest win: pure UI on a shipped API |
| 7 | **Off-cycle staging UI missing** — API shipped, list is read-only | ledgered debt (deferred-work.md) | Owners can't stage bonuses/deductions from the console |
| 8 | **No run preview** — enqueue computes AND commits in one step | run enqueue contract | Owner sees numbers only after money is committed |
| 9 | **No ESI / LWF / gratuity / declarations / old regime** | nothing anywhere | Real, but none block a monthly run — V1.x/LATER with triggers |
| 10 | **No unmarked-day semantics surfaced** (Frappe's `consider_unmarked_attendance_as`) | run-lop.ts | Missed punches are constant in field service; semantics must be explicit |

### Frappe patterns worth copying (and their sources)
- Two-number discipline per payslip line (`default_amount` vs prorated `amount`) → makes YTD + tax projection trivial (02 §2.1)
- Single proration point; dependent formulas inherit prorated bases — never double-prorate (02 §2.2–2.3)
- Tax = annual projection spread per period, subtracting tax already paid → mid-year events self-correct (02 §2.5)
- Additional Salary as ONE off-cycle channel with source traceability (02 §4.3)
- Attendance completeness gate before submit — minus Frappe's own bug where the gate ignores its setting (02 §3.2, §8.3)
- Payslip email fires at exactly ONE layer (run-level flag) or it doubles (02 §8.12)
- Expense reimbursements are NEVER paid through salary — tax cleanliness (01 row 27)

### And what NOT to copy
Frappe's `_safe_eval` sandbox (keep Fenzit's compiled AST), Journal-Entry machinery (exports instead), multi-currency, non-monthly frequencies, flexible-benefit engine, withholding cycles, Payroll Correction + Arrear parallel doctypes, Redis caching layers (02 §7.2 has the full list with reasons).

---

## Recommended V1 scope (9 work items, ≈20–28 agent-days)

Order respects dependencies; WI-H/I parallelize anytime.

| # | Work item | Size | One-line spec |
|---|---|---|---|
| WI-A | **TDS tax-year parameterization** | S–M | FY constants → `payroll_tax_years` table; refuse months without a row; bit-identical on today's fixture |
| WI-B | **Component type taxonomy** | M | Unified components w/ `type` (earning/deduction/employer), statutory tag, prorates flag — foundation for C/D/F |
| WI-C | **PT state engine** | M | Per-state slab rules table, month-start resolution, office-state auto-select, Feb-doubling, skip reasons |
| WI-D | **PF employer split** | S–M | EPS 8.33% + remainder on ceiling wage; fix mirror bug; employer cost in summary |
| WI-E | **Run preview + unmarked-day semantics + attendance gate** | M | Dry-run endpoint + console review step before commit; explicit `unmarked_days_as` setting |
| WI-F | **Salary register + bank advice exports** | M | Reuse reports registry + R2 presign; register totals must equal run summary exactly; YTD columns |
| WI-G | **Payslip email** | S–M | One layer only (run completion/lock); template + presigned link; off by default |
| WI-H | **Admin payslip viewer** | S | Console roster + PDF on the shipped API — no BE changes |
| WI-I | **Off-cycle staging UI** | S–M | Add-line sheet w/ 50%-cap impact preview; clears the ledgered debt |

BMAD shape: one epic, 9 stories in WI order, acceptance criteria in 05 §6. Statutory stories get table-driven test specs first. Definition of done: Frappe's 8 highest-value behaviours pinned as Fenzit specs (02 §7.6), canonical fixtures unchanged, all new tables RLS-guarded.

**Explicitly not in V1** (with post-V1 triggers, in 05 §7): ESI, LWF, declarations/old regime/HRA, gratuity, overtime, expense claims (recommend as a separate epic right after — agent 1 scored it V1, synthesis demotes it: zero payslip-line impact), advance request flow, auto-arrears, hold/release, draft/approve stage, ECR export, statutory hub UI.

---

## Decisions for the owner (when you wake up)

1. **Approve V1 = the 9 work items** (or strike any; each is independently shippable).
2. **WI-A first** — it's small and defuses April 2027; nothing else depends on deciding it.
3. **Expense claims as separate epic?** Agent 1 said V1; synthesis says separate (reasons in 05 §3.E). Your call.
4. **Unmarked-day default**: present (Frappe's default, pay silent days) vs absent (LOP). Current Fenzit behaviour needs a 5-minute verification; the setting should exist either way (WI-E).
5. **Email trigger**: at run completion or at lock? Pick one — the invariant is one email per member per run (WI-G).
6. **No code was written and nothing is committed** — all six reports are uncommitted files in `artifacts/planning-artifacts/payroll-v1-frappe-benchmark-2026-11-21/`. Implementation starts only on your word.
