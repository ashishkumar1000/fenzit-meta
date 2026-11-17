# Canonical fixture — SPEC-payroll

Authoritative for every payroll test and journey leg. Tests import these rows verbatim; a success criterion saying "the fixture" means this document. Companion of `SPEC.md`.

## Base tenant & month

- Tenant timezone: `Asia/Kolkata`. Run month: **2026-10** (31 days; Sundays = weekly off: Oct 4, 11, 18, 25; public holidays: none).
- Payroll config: LOP divisor **fixed-26**; PF-covered **on**; PT head flat **₹200/month**; no other heads; PF wage ceiling config **₹25,000** (raised from ₹15,000 effective 17 Sep 2026 — Cabinet 16.09.2026, EPFO FAQ, PIB 31.10.2026); TDS slab config = new regime, standard deduction ₹75,000 (annual), slabs per FY 2026-27 config rows.

## Employee A (base variant)

- Technician role, employee code `EMP-001`, PAN present, designation "Field Technician", joined **2026-09-01** (full-month October employment).
- Structure effective 2026-09-01: basic ₹20,000; HRA = 40% of basic → ₹8,000. Monthly structure amount **₹28,000**.
- Leaves (approved): 2 casual on Oct 6–7 (**paid** type); 3 full days Oct 13/14/15 (**unpaid** type); 1 unpaid **half-day** Oct 12 (second half, approved leave part). All on working days.

### Expected numbers — base variant

| Line | Value |
|---|---|
| Monthly structure amount | 28,000.00 |
| Daily wage (unrounded) | 28,000 ÷ 26 = 1,076.923076… |
| Payable days | min(31, 26) = **26** |
| LOP-equivalent days | 3 unpaid + 0.5 half-day = **3.5** |
| Earnings | 1,076.923076… × (26 − 3.5) = **24,230.77** |
| PF — employee deduction | 12% × min(20,000, 25,000) = **2,400.00** |
| PF — employer share | 2,400.00 (recorded, **not** deducted) |
| TDS estimate | slab(28,000 × 12 − 75,000 = 261,000 taxable → below the ₹4,00,000 basic exemption) = **0.00** |
| PT (flat head) | **200.00** |
| Deduction-cap basis | 24,230.77 post-LOP gross; 50% = 12,115.39 (not binding) |
| **Net** | 24,230.77 − 2,400.00 − 0.00 − 200.00 = **21,630.77** |
| Slip number | unique per tenant per salary period (e.g. `PS-2026-10-0001`) |

Payslip day-count fields: payable days 26; LOP days 3.5; paid-typed leave days 2; weekly offs 4 (paid). (Presentation format is story-level; the money rows above are the assertions.)

## Variants

**B — percentage head:** add head "insurance" = 2% of **gross** (payable post-LOP): 0.02 × 24,230.77 = **484.62**; net = 21,630.77 − 484.62 = **21,146.15**.

**C — proration (PF on period wages):** Employee B joined **2026-10-20**, same structure, no leaves: payable = min(12 calendar days, 26) = 12 → earnings **12,923.08**; prorated basic = 20,000 × 12/26 = **9,230.77** (under the ceiling) → PF = 12% × 9,230.77 = **1,107.69**; net = 12,923.08 − 1,107.69 − 200 = **11,615.39**. Variant C2: joined 2026-09-01, exit **2026-10-10**: payable = min(10, 26) = 10 → earnings **10,769.23**; prorated basic = 7,692.31 → PF **923.08**; net = 10,769.23 − 923.08 − 200 = **9,646.15**. (Basis: EPF Act s.2(b)/s.6 — contribution on basic wages actually paid for the period; EPFO HQ circular 27.01.2017 — pro-rata with the ceiling applied to the period wage; greytHR/Keka implement the same.)

**D — 50% cap + override:** from base variant, admin overrides TDS to **₹12,000** (with liability acknowledgment) and adds the variant-B insurance head: total deductions = PF 2,400 + 12,000 + 484.62 + 200 = **15,084.62** > cap 12,115.39 → deductions clamped to **12,115.39**; net = **12,115.38**; excess **2,969.23** raised as a recovery line surfaced on the next run's payslip.

**E — join-on-2nd with LOP (formula-conflict guard):** employee joined **2026-10-02**, 1 unpaid LOP day on Oct 5: payable = min(30, 26) = 26, LOP 1 → earnings = 1,076.923076… × 25 = **26,923.08** (not 28,000 − 30/26-based arithmetic; this pins the single formula). PF note: this joiner's prorated basic (₹19,230.77) is **below** the ₹25,000 ceiling → auto-PF applies: 12% × 19,230.77 = **2,307.69** (variant E asserts earnings; the PF leg is covered by variant C's arithmetic). The excluded-joiner rule bites only above the ceiling — a joiner with period basic > ₹25,000 who was never an EPF member is excluded (opt-in via Para 26(6) declaration); anyone who was **ever** an EPF member must be covered regardless of wage.

**F — structure revision:** revision effective 2026-11-01 (basic ₹22,000 → HRA 8,800 → 30,800): October re-run keeps base numbers; November run uses 30,800. A mid-month revision dated 2026-10-15 takes effect from the **next run** (whole-month rule).

**G — edges:** zero active employees → run completes, zero payslips, `no_employees` status · employee with no effective structure → skipped, listed `not_configured`, no payslip · never-enrolled employee (no attendance grid) → skipped with warning · checkout_missing day → paid pending correction, flagged in run summary · leave on Oct 27 (after the 25th cutoff) → appears in the November run · off-cycle ₹5,000 bonus to employee A in unlocked October → re-run keeps one payslip, bonus line included in gross and in the cap basis.

## Statutory notes on this fixture

- PF base = basic wages **actually paid for the period** (EPF Act s.2(b)/s.6; SC *ESIC v. M.M. Suri* 2019 — "actually paid" in the ESI context; practitioner practice greytHR/Keka/tax2win aligns); mid-month pro-rata with the ceiling applied to the period wage per EPFO circular **N-12/17/08/P&R/Part/110241 (08.08.2018)** — substance corroborated by practitioner worked examples (tax2win: 15,000 × 8/30 for a 22nd-of-month joiner); the earlier "27.01.2017 HRM-4(2)17/2014" citation could not be located in any indexed source and is dropped.
- **PF wage ceiling = ₹25,000, effective 17 September 2026** (notification **S.O. 5109(E)** dated 17.09.2026, per EPFO's own FAQ "Revision of EPFO Statutory Wage Ceiling" — table: effective 17 Sep 2026, revised ₹25,000, earlier ₹15,000, ~51 lakh additional employees; Cabinet approval 16.09.2026; KPMG flash alert 2026-249, 28.09.2026; applies to EPF, EPS and EDLI). Statutory config must keep the historical ₹15,000 (pre-17.09.2026) for older-period runs.
- Excluded-employee / new-joiner rule: the **judicial line (SC *Pioneer India Entertainment* 2019 → Kerala HC *Sivasankaran* 2018/19 → *Vivekananda Vidyamandir*) holds that post-first-coverage joiners above the ceiling CANNOT claim exclusion — enrollment is the default**; the exclusion reading is EPFO's contested administrative position (Feb 2025 circular withdrawn Apr 2025; Jul 2025 draft unnotified). Product default: enroll; the exclusion path is an admin configuration with an EPFO-flux warning; anyone **ever** an EPF member is always covered. (The 2025 "*P.F. Commissioner v. E. Sivasankaran*" citation was a miscitation — an excluded-**establishment** case — and is deleted.)
- 15-day convention, operative form: **≥15 wage-days in the month → contribution on the full period wage (ceiling-capped); <15 days → pro-rata** (ceiling ÷ 30 × payable days, non-working days non-contributory) — from the HRM-4(2)17/2014/SS-III order series (27.01.2017; exact order number /125 vs /1584 unconfirmed) and EPF Scheme 1952 membership practice (epfindia.gov.in EPF_Coverage.pdf). Divergence recorded: v1 computes exact payable days; the 15-day-full-month branch is tracked under the spec's PF Open Questions.
- PF wage-base authority: EPF Act **s.2(b)(ii)** (basic + DA + retaining allowance); the *M.M. Suri* case is an ESI ruling and is not cited as PF authority.
- TDS basis verified for FY 2026-27 (runs under the **Income-tax Act, 2025**, effective April 2026): new-regime slab table unchanged by Budget 2026 (0–4L nil, 4–8L 5%, 8–12L 10%, 12–16L 15%, 16–20L 20%, 20–24L 25%, >24L 30% — Bajaj table read this run; PIB Budget-2026 summary lists no direct-tax slab change), standard deduction **₹75,000** unchanged; rebate is **s.157** (renumbered 87A): resident-only, ₹60,000 = 100% of tax on income up to ₹12L, marginal relief above ₹12L; 4% health & education cess. Taxable ₹2,61,000 sits entirely in the nil slab → annual tax ₹0 → monthly TDS ₹0 (rebate not even required). Method: estimate annual tax, spread over **remaining months**, re-estimate and re-spread on revision (CalcGuru, Jul 2026); new regime is the default when the employee makes no declaration.
