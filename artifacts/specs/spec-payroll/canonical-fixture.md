# Canonical fixture — SPEC-payroll

Authoritative for every payroll test and journey leg. Tests import the **money rows and asserted day-counts** verbatim; a success criterion saying "the fixture" means this document. Companion of `SPEC.md`; legal citations live in `statutory-verification.md`.

## Base tenant & month

- Tenant timezone: `Asia/Kolkata`. Run month: **2026-10** (31 days; Sundays = weekly off: Oct 4, 11, 18, 25; public holidays: none).
- **First payroll month: 2026-09** (employee A's join month — the earliest among employees); runs for 2026-08 are rejected.
- Payroll config: LOP divisor **fixed-26**; PF-covered **on**; PT head flat **₹200/month**; no other heads; percentage heads compute on **earned** basis amounts.
- **PF wage ceiling config, effective-dated rows: ₹15,000 until 2026-09-16; ₹25,000 from 2026-09-17** (S.O. 5109(E)) — a run resolves the row effective for its run month's first day.
- TDS config = new regime, standard deduction ₹75,000 (annual), slabs per FY 2026-27 config rows.

## Employee A (base variant) — Form V seed fields

Employee role (`employee` — the post-rewrite membership role), employee code `EMP-001`, designation "Field Technician", department "Field Operations", DOB 1995-04-12, father's name "Ramesh Sharma", PAN `ABCPE1234F` (present), UAN `101234567890`, PF account `PY/ABC/12345/000`, bank account `1234567890`, IFSC `HDFC0001234`, bank name "HDFC Bank", joined **2026-09-01** (full-month October employment). Establishment name + address: tenant's.

- Structure effective 2026-09-01: basic ₹20,000 (designated basic component); HRA = 40% of basic → ₹8,000. Monthly structure amount **₹28,000**.
- Leaves (approved): 2 casual on Oct 6–7 (**paid** type); 3 full days Oct 13/14/15 (**unpaid** type); 1 unpaid **half-day** Oct 12 (second half, approved leave part). All on working days.

### Expected numbers — base variant

| Line | Value |
|---|---|
| Monthly structure amount | 28,000.00 |
| Daily wage (unrounded) | 28,000 ÷ 26 = 1,076.923076… |
| Payable days | min(31, 26) = **26** |
| LOP-equivalent days | 3 unpaid + 0.5 half-day = **3.5** |
| Earnings (post-LOP gross) | 1,076.923076… × 22.5 = **24,230.77** |
| Earned basic | 20,000 × 22.5/26 = **17,307.69** |
| PF — employee deduction | 12% × min(17,307.69, 25,000) = **2,076.92** |
| PF — employer share | 2,076.92 (recorded, **not** deducted) |
| TDS estimate | 28,000 × 7 (Sep–Mar, months of employment in FY) = 1,96,000 − 75,000 = 1,21,000 → below ₹4,00,000 = **0.00** |
| PT (flat head) | **200.00** |
| Deduction-cap basis / cap | 24,230.77 post-LOP gross → 50% = 12,115.39 (not binding) |
| **Net** | 24,230.77 − 2,076.92 − 0.00 − 200.00 = **21,953.85** |
| Slip number | unique per tenant per salary period (e.g. `PS-2026-10-0001`) |

**Asserted day-counts:** payable days 26; LOP days 3.5; **paid days 22.5** (payable − LOP-equivalent). Presentation-only: paid-typed leave days 2, weekly offs 4, days worked. **Reconciliation rule:** paid days = payable − LOP-equivalent; days worked counts present days with `half_day` as 0.5; the divisor cap discards excess calendar days — buckets are **not** required to sum to the month length.

## Variants

**B — percentage head (earned basis):** add head "insurance" = 2% of **gross** (earned basis: post-LOP gross): 0.02 × 24,230.77 = **484.62**; net = 21,953.85 − 484.62 = **21,469.23**. A basic-basis percentage head applies to the earned basic (17,307.69 under the same 2%).

**C — proration (window):** Employee B joined **2026-10-20**, same structure (**active membership**), no leaves: payable = min(12, 26) = 12 → earnings **12,923.08**; earned basic = 20,000 × 12/26 = **9,230.77** (under the ceiling) → PF = **1,107.69**; net = 12,923.08 − 1,107.69 − 200 = **11,615.39**. Variant C2: joined 2026-09-01, exit **2026-10-10** (**active membership** with exit_date — still in the run population for its exit month): payable = min(10, 26) = 10 → earnings **10,769.23**; earned basic = 7,692.31 → PF **923.08**; net = 10,769.23 − 923.08 − 200 = **9,646.15**.

**D — 50% cap + override:** from the base variant, admin overrides TDS to **₹12,000** (with liability acknowledgment) and adds the variant-B insurance head: total deductions = PF 2,076.92 + 12,000 + 484.62 + 200 = **14,761.54** > cap 12,115.39 → deductions clamped to **12,115.39**; net = **12,115.38**; excess **2,646.15** raised as a **recovery line** on the next run's payslip — subject to the same cap check, the unabsorbable remainder rolled forward, the run summary shows the outstanding balance, and the final run deducts the remainder if the employee exits.

**E — join-on-2nd with LOP (formula-conflict guard):** employee joined **2026-10-02**, 1 unpaid LOP day on Oct 5: payable = min(30, 26) = 26, LOP 1 → earnings = 1,076.923076… × 25 = **26,923.08**; earned basic = 20,000 × 25/26 = **19,230.77** → PF = **2,307.69**. **Enrollment policy (this pins CAP-6's default):** a joiner with period basic above ₹25,000 who was never an EPF member is **enrolled by default**; exclusion is an admin configuration (EPFO-flux warning); anyone ever an EPF member is covered at any wage.

**F — structure revision:** revision effective 2026-11-01 (basic ₹22,000 → HRA 8,800 → 30,800): an October re-run after the revision still uses the 2026-09-01 structure (month-start resolution — the whole-month rule); November uses 30,800. A mid-month revision dated 2026-10-15 is first used by November's run.

**G — edges:** zero active employees → run completes, zero payslips, `no_employees` status · employee with no effective structure → skipped, listed `not_configured`, no payslip · never-enrolled employee (no attendance grid) → skipped with warning · checkout_missing day → paid pending correction, flagged in run summary · **leave on Oct 27 (cut-off 25) → November run, LOP 1.0 — tabled below; October unchanged (LOP stays 3.5 — the date is not double-counted)** · **an owner and a removed member, each with a structure → no payslip rows** · **employee without PAN → blank PAN + run-summary warning; net unaffected; a fabricated PAN value fails** · **D + ₹5,000 bonus (tagged bonus): cap basis = 24,230.77 + 5,000 = 29,230.77 → cap 14,615.39; deductions 14,761.54 > cap → clamp 14,615.39, net 14,615.38, excess 146.15; PF unchanged at 2,076.92 (a bonus never joins the PF base)** · off-cycle ₹5,000 bonus to employee A in unlocked October → re-run keeps one payslip, bonus line included in gross and in the cap basis.

**G — November row (prior-period money):** structure 30,800 (F revision effective 2026-11-01); payable = min(30, 26) = 26; LOP 1.0 (the prior-period Oct-27 leave); earnings = 30,800/26 × 25 = **29,615.38**; earned basic = 22,000 × 25/26 = 21,153.85 → PF = **2,538.46**; TDS = 30,800 × 5 (Nov–Mar) − 75,000 → below ₹4,00,000 = **0.00**; PT 200 → **net 26,876.92**.

**H — above-ceiling joiner + computed TDS (projection clears the s.157 rebate threshold):** joined 2026-10-01, basic ₹2,00,000, HRA 40% → ₹80,000, gross **₹2,80,000**, never an EPF member → **enrolled by default** (no exclusion applied): PF = 12% × min(2,00,000, **25,000**) = **3,000.00** — the ceiling binds (not 12% of full basic); employer share 3,000 recorded; TDS **computed** — the projection is designed above ₹12L so the s.157 rebate cannot wipe it (a below-₹12L row must assert TDS 0.00): projection = 2,80,000 × 6 (Oct–Mar, months of employment in FY) = 16,80,000 − 75,000 = 16,05,000 taxable → tax = 20,000 (4–8L) + 40,000 (8–12L) + 60,000 (12–16L) + 1,000 (16–16.05L @ 20%) = 1,21,000 — above ₹12L, rebate inapplicable — + 4% cess 4,840 = 1,25,840 → ÷ 6 remaining months = **20,973.33/month**; PT 200; cap 50% × 2,80,000 = 1,40,000 not binding (total deductions 24,173.33) → **net 2,55,826.67**.

**I — absent-day LOP + paid half-day + out-of-window leave:** joined 2026-10-03, structure as A: 1 absent day (Oct 20, day-status `absent`, **no leave**) + 1 paid-typed half-day (Oct 10 — **no LOP**) + 1 unpaid leave approved **Oct 1–2** (before the join — outside the window, never LOPs): payable = min(29, 26) = 26; LOP = **1.0** (the absent day only); earnings = 1,076.923076… × 25 = **26,923.08**; earned basic = 19,230.77 → PF **2,307.69**; TDS 0.00 (28,000 × 6 = 1,68,000 − 75,000 = 93,000); net = 26,923.08 − 2,307.69 − 200 = **24,415.39**.

**Owner-corrected half-day (CAP-5):** from the base variant, the owner corrects one present working day (Oct 21) to `half_day` via the attendance-override path: LOP = 3.5 + 0.5 = **4.0**; earnings = 1,076.923076… × 22 = **23,692.31**; earned basic = 16,923.08 → PF **2,030.77**; net = 23,692.31 − 2,030.77 − 200 = **21,461.54** (the half-day LOP deduction = 538.46 = exactly half the single-day daily wage).

## Divisor conventions (CAP-4)

Same base facts (structure 28,000, basic 20,000, LOP 3.5) under each convention:

| Convention | Payable | Daily wage | Earnings | Earned basic | PF | PT | **Net** |
|---|---|---|---|---|---|---|---|
| fixed-26 (base) | 26 | 1,076.92 | 24,230.77 | 17,307.69 | 2,076.92 | 200 | **21,953.85** |
| fixed-30 | 30 | 933.33 | 24,733.33 | 17,666.67 | 2,120.00 | 200 | **22,413.33** |
| calendar | 31 | 903.23 | 24,838.71 | 17,741.94 | 2,129.03 | 200 | **22,509.68** |

Full-month-no-LOP sanity: earnings = the structure amount under every divisor (daily wage × divisor = 28,000). The three rows are distinct — no two conventions coincide.

## Effective dating

- A **2026-09** run month resolves the ₹15,000 ceiling (month-start Sep 1 < Sep 17): September's run window for A is Sep 1–25 (month M's own dates count only up to M's resolved cut-off; A joined Sep 1, so no prior-period days), payable = min(25, 26) = 25, earned basic = 20,000 × 25/26 = **19,230.77** → PF = 12% × min(19,230.77, 15,000) = **1,800.00** — the ceiling binds, so the value equals the full-month reading; the historical value's home. October resolves ₹25,000.
- Non-statutory policy (divisor, cut-off, pay date, heads) uses the same month-start resolution: a change saved mid-month is first used by the next month's run; an unlocked re-run of an earlier month uses that month's values.

## Statutory notes on this fixture

- PF base = **earned basic** (basic wages payable for the period: window-prorated, LOP-reduced) — EPF Act s.2(b)(ii)/s.6, citations and verification history in `statutory-verification.md`.
- Excluded-employee / enrollment-default policy: CAP-6 and `statutory-verification.md` (variant E's parenthetical carries the pinned policy).
- TDS FY 2026-27 verification (slabs, s.157, cess, spread method): `statutory-verification.md`; the 15-day joiner convention divergence: SPEC Open Questions.
