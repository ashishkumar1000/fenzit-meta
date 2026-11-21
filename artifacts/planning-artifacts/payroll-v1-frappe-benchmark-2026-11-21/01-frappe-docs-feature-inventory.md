# Frappe HR — Documentation-Based Feature Inventory (Payroll-Centred)

**Benchmark artifact for:** Fenzit payroll V1 planning (competitive gap analysis vs Frappe HR)
**Date:** 2026-11-21
**Subject:** Frappe HR / HRMS (open source, github.com/frappe/hrms), current stable line v15.64.x / v16.60.x (v16.60.0 released 2026-11-17)
**Method:** Every claim below was verified this session against the published documentation (docs.frappe.io/hr), the product site (frappe.io/hr), GitHub release notes (github.com/frappe/hrms/releases), or the local clone at `/Users/admin/workspace/fenzit-meta/workspace/external/frappe-hrms` (used only to corroborate doctype fields / report lists / PWA scope). Claims that could not be verified are marked **unverified**.

Verdicts ("Fenzit V1 verdict") are the author's judgment, grounded only in the Fenzit context: India SMB, field-service workforce (technicians + office staff), ~150 users, React-Native mobile app for attendance/leave/payslips, NestJS + Supabase backend, existing monthly payroll run engine with attendance-based LOP handling, payslips in mobile, PF-related bits and statutory state rules already started, small admin/owner team on a web console. They are **not** statements about what Fenzit already has.

---

## 0. Source map (what was read this session)

### Official docs pages fetched (docs.frappe.io/hr)
| # | Page | URL |
|---|------|-----|
| 1 | Introduction | https://docs.frappe.io/hr/introduction |
| 2 | Payroll Management (module hub) | https://docs.frappe.io/hr/payroll-management |
| 3 | Payroll Setup (end-to-end process) | https://docs.frappe.io/hr/payroll-setup |
| 4 | Payroll Period | https://docs.frappe.io/hr/payroll-period |
| 5 | Salary Component | https://docs.frappe.io/hr/salary-component |
| 6 | Salary Structure | https://docs.frappe.io/hr/salary-structure |
| 7 | Salary Structure Assignment | https://docs.frappe.io/hr/salary-structure-assignment |
| 8 | Payroll Entry | https://docs.frappe.io/hr/payroll-entry |
| 9 | Salary Slip | https://docs.frappe.io/hr/salary-slip |
| 10 | Payroll Settings | https://docs.frappe.io/hr/payroll-settings |
| 11 | Income Tax Slab | https://docs.frappe.io/hr/income-tax-slab |
| 12 | Setting Up Income Tax Deduction | https://docs.frappe.io/hr/setting-up-income-tax-deduction |
| 13 | Employee Tax Exemption Declaration | https://docs.frappe.io/hr/employee-tax-exemption-declaration |
| 14 | Employee Tax Exemption Proof Submission | https://docs.frappe.io/hr/employee-tax-exemption-proof-submission |
| 15 | Payroll Correction (LWP reversal) | https://docs.frappe.io/hr/payroll-correction |
| 16 | Arrears | https://docs.frappe.io/hr/arrears |
| 17 | Overtime | https://docs.frappe.io/hr/overtime |
| 18 | Additional Salary | https://docs.frappe.io/hr/additional-salary |
| 19 | Retention Bonus | https://docs.frappe.io/hr/retention-bonus |
| 20 | Employee Incentive | https://docs.frappe.io/hr/employee-incentive |
| 21 | Employee Benefit Application | https://docs.frappe.io/hr/employee-benefit-application |
| 22 | Employee Benefit Claim | https://docs.frappe.io/hr/employee-benefit-claim |
| 23 | Flexible Benefits | https://docs.frappe.io/hr/employee-flexible-benefits |
| 24 | Employee Other Income | https://docs.frappe.io/hr/employee-other-income |
| 25 | Leave Encashment via Salary Slips (how-to) | https://docs.frappe.io/hr/how-to-encash-unused-leaves-using-salary-slips |
| 26 | Payroll Entry with Timesheets | https://docs.frappe.io/hr/create-payroll-entry-with-timesheets |
| 27 | Working Days Calculation in Salary Slip | https://docs.frappe.io/hr/working-days-calculation-in-the-salary-slip |
| 28 | Leave Calculation in Salary Slip | https://docs.frappe.io/hr/leave-calculation-in-salary-slip |
| 29 | Employee Advance | https://docs.frappe.io/hr/employee-advance |
| 30 | Expense Claim | https://docs.frappe.io/hr/expense-claim |
| 31 | Full and Final Statement | https://docs.frappe.io/hr/full-and-final-statement |
| 32 | Gratuity | https://docs.frappe.io/hr/gratuity |
| 33 | Gratuity Rule | https://docs.frappe.io/hr/gratuity-rule |
| 34 | Loan | https://docs.frappe.io/hr/loan |
| 35 | Attendance | https://docs.frappe.io/hr/attendance |
| 36 | Employee Checkin | https://docs.frappe.io/hr/employee-checkin |
| 37 | Auto Attendance | https://docs.frappe.io/hr/auto-attendance |
| 38 | Shift Management | https://docs.frappe.io/hr/shift-management |
| 39 | Attendance Request | https://docs.frappe.io/hr/attendance-request |
| 40 | Leaves (section hub) | https://docs.frappe.io/hr/leaves |
| 41 | Leave Application | https://docs.frappe.io/hr/leave-application |
| 42 | Compensatory Leave Request | https://docs.frappe.io/hr/compensatory-leave-request |
| 43 | HR Settings | https://docs.frappe.io/hr/hr-settings |
| 44 | Human Resources Reports | https://docs.frappe.io/hr/human-resources-reports |
| 45 | User Permission Based on Hierarchy | https://docs.frappe.io/hr/user-permission-based-on-hierarchy |
| 46 | Employee | https://docs.frappe.io/hr/employee |
| 47 | Mobile App Installation | https://docs.frappe.io/hr/mobile-app-installation |

### Product / release sources
- Product site (feature grid, "India Payroll" banner): https://frappe.io/hr
- India Payroll product page: https://frappe.io/hr/india-payroll
- Release notes: https://github.com/frappe/hrms/releases/tag/v15.0.0 , /v16.0.0 , /v16.60.0
- India Payroll app repo + README: https://github.com/frappe/india-payroll (created 2026-04-09; latest release v16.2.0 on 2026-11-17)
- India Compliance app repo: https://github.com/resilient-tech/india-compliance (GST-centric)

### Local clone corroboration (paths, read-only)
- Payroll reports list: `/Users/admin/workspace/fenzit-meta/workspace/external/frappe-hrms/hrms/payroll/report/` (8 report folders)
- Payroll Settings flags: `/Users/admin/workspace/fenzit-meta/workspace/external/frappe-hrms/hrms/payroll/doctype/payroll_settings/payroll_settings.json`
- Salary Slip fields: `/Users/admin/workspace/fenzit-meta/workspace/external/frappe-hrms/hrms/payroll/doctype/salary_slip/salary_slip.json`
- Expense Claim fields: `/Users/admin/workspace/fenzit-meta/workspace/external/frappe-hrms/hrms/hr/doctype/expense_claim/expense_claim.json`
- India regional layer: `/Users/admin/workspace/fenzit-meta/workspace/external/frappe-hrms/hrms/regional/india/setup.py`, `utils.py`, `data/salary_components.json`
- Mobile PWA views: `/Users/admin/workspace/fenzit-meta/workspace/external/frappe-hrms/frontend/src/views/` (attendance, leave, expense_claim, employee_advance, salary_slip, notifications, profile)

---

## 1. How Frappe HR documents the payroll flow end-to-end

The canonical narrative lives in one page — **Payroll Setup** (https://docs.frappe.io/hr/payroll-setup) — which lays out a six-step process:

> 1. Define Payroll Period (optional) → 2. Define Income Tax Slab (optional) → 3. Create Salary Structure with Salary Components (Earnings/Deductions) → 4. Assign structures via Salary Structure Assignment → 5. Generate Salary Slips via Payroll Entry → 6. Book salaries in Accounts.

### Phase A — Setup (once per company / per year)

1. **Payroll Period** (https://docs.frappe.io/hr/payroll-period). Name + Start/End Date. Required only if you use flexible benefits or tax slabs. Multiple periods can exist (one per financial year), and the applicable Income Tax Slab is defined per period so law changes are handled by creating a new period + slab.
2. **Income Tax Slab** (https://docs.frappe.io/hr/income-tax-slab). Named slab with Effective From date, submitted; rows of From Amount/To Amount → rate; per-row *conditions* can test fields of Employee / Salary Structure / Salary Structure Assignment / Salary Slip (doc examples: age via `date_of_birth`, `gender`, `base`, `annual_taxable_earning`); an "Other Taxes and Charges" child table adds cess-like charges (min/max taxable bounds); "Allow Tax Exemptions" switch + "Standard Tax Exemption Amount" (proof-free flat exemption). Slab is attached to an employee via the Salary Structure Assignment (not globally).
3. **Salary Components** (https://docs.frappe.io/hr/salary-component). The building blocks — every Earning, Deduction, or Employer Contribution, with an Abbreviation used in formulas. Key per-component flags (documented): Amount based on formula vs fixed Amount; Condition (Python-like expression); Depends on Payment Days (prorates with LOP); Is Tax Applicable; Exempted from Income Tax; Variable Based On Taxable Salary (makes it the TDS component driven by the slab); Statistical Component; Do Not Include in Total; Is Additional Component (only payable via Additional Salary); Is Payable; Round to Nearest Integer; Deduct Full Tax on Selected Payroll Date; Is Flexible Benefit (+ Max Benefit Amount Yearly, Pay Against Benefit Claim, Only Tax Impact, Create Separate Payment Entry Against Benefit Claim); Accrual Component (accrued bonuses); Is Employer Contribution (third type — sits in its own "Employer Contributions" table in the structure, e.g. `BS * 0.12` employer PF). "Update Salary Structures" button pushes changed formulas into existing structures. Formula functions documented include `int, flt, round, rounded(…, rounding_method), ceil, floor, getdate(…).month` (the last used for month-varying items like Professional Tax).
4. **Salary Structure** (https://docs.frappe.io/hr/salary-structure). Company + Payroll Frequency (Monthly etc.), validity From date (only one active structure per employee per period), Earnings table + Deductions table (rows reference components; amount or formula per row; a `base` row is the anchor), Mode of Payment + Payment Account, "Salary Slip Based on Timesheet" switch (picks a component + Hour Rate), Leave Encashment Amount Per Day, Max Benefits amount. Post-submit actions: Assign (single), Bulk Assignments, Preview Salary Slip.
5. **Salary Structure Assignment** (https://docs.frappe.io/hr/salary-structure-assignment). Links Employee → Structure with From Date, plus per-employee Base and Variable amounts, and the chosen Income Tax Slab. Multiple dated assignments per employee are supported (revisions). Bulk path: "Bulk Salary Structure Assignment" tool with Grade/Department/Designation/Employee filters. Optional opening balances ("Taxable Earnings till Date" / "Tax Deducted till Date") are allowed only when no slips exist yet (Payroll Settings "Define Opening Balance for Earning and Deduction", https://docs.frappe.io/hr/payroll-settings).

### Phase B — Monthly run

6. **Payroll Entry** (https://docs.frappe.io/hr/payroll-entry). Bulk run: Payroll Frequency; optional filters Branch / Department / Designation / Project / (Grade filter added in v15 — release note https://github.com/frappe/hrms/releases/tag/v16.0.0 "Add employee grade filter in payroll entry"); checkboxes **Validate Attendance** and **Salary Slip Based on Timesheet**; Posting Date; Start/End dates; "Deduct Tax For Unclaimed Employee Benefits" and "Deduct Tax For Unsubmitted Tax Exemption Proof" checkboxes; Cost Center + Payment Account. Buttons: Get Employees → Create Salary Slips → View Salary Slips (individually editable, e.g. LWP) → Submit Salary Slip (bulk) → Make Bank Entry. Guards: duplicate slips are not re-created; slips submitted one-by-one do *not* create the accrual journal entry (bulk submit does).
7. **Salary Slip** (https://docs.frappe.io/hr/salary-slip). Auto-fetched from the structure; Start/End dates; attendance/leave-derived payment days (see §2d); YTD and MTD totals per slip and per component; "Salary Slip with Year to Date" print format; bulk email of slips on submission when "Email Salary Slip to Employee" is on, with optional sender + email template (Payroll Entry flow), plus a bulk email action from the Salary Slip list for stragglers. Timesheet-based slips are created from a submitted Timesheet via "Create Salary Slip".
8. **Accounting & disbursement** (https://docs.frappe.io/hr/payroll-entry, https://docs.frappe.io/hr/payroll-setup). Bulk submit books accrual: debit per-component expense heads, credit Payroll Payable. "Make Bank Entry" creates a *single* draft Journal Entry (deliberately one lump to protect privacy), debiting deduction/earnings per default accounts on components; the user fills reference no./date and submits. Cost-center precedence: Salary Structure Assignment (multiple cost centers allowed) → Employee's Payroll Cost Center → Department's → Payroll Entry's. Payroll Settings flag "Process Payroll Accounting Entry based on Employee" switches to per-employee entries.

### Phase C — Statutory & compliance

9. **Income tax** (https://docs.frappe.io/hr/setting-up-income-tax-deduction). Tax is computed annually on projected earnings minus declared exemptions, divided over pay cycles, through a Deduction component flagged "Variable Based On Taxable Salary". Exemption pipeline: Employee Tax Exemption Declaration (start of year) → Employee Tax Exemption Proof Submission (year-end, only applied in the *last* payroll unless the "Deduct Tax For Unsubmitted Tax Exemption Proof" flag is used) → categories/sub-categories (80C, 80G…) configured by the admin. HRA exemption (India) is built in: min of (actual HRA, rent − 10% of basic, 50%/40% of basic for metro/non-metro), with Basic+HRA components configured on the Company.
10. **India statutory schemes** — out of core. Verified split (see §2b): core hrms carries only generic tax + India custom fields (PF/PT component typing, PAN/IFSC, HRA settings); the new **India Payroll app** (frappe/india-payroll, v16) provides EPF/ESI/PT/LWF computation, TDS 24Q e-filing, Form 16, tax-regime selector, and filing registers (https://frappe.io/hr/india-payroll, https://github.com/frappe/india-payroll).

### Phase D — Off-cycle & exceptions

11. **Additional Salary** is the universal mechanism for anything paid outside the run: bonuses, arrears, gratuity, leave encashment, overtime (each of those features *generates an Additional Salary* on submission — verified per feature page cited in §2c/§2d).
12. **Arrears** (https://docs.frappe.io/hr/arrears) and **Payroll Correction** (LWP reversal, https://docs.frappe.io/hr/payroll-correction) are v16-era wrappers that also emit Additional Salary entries + Employee Benefit Ledger accruals.

**One-sentence flow (docs' own framing):** Periods and slabs define the year; components + structure + assignment define each employee; Payroll Entry mass-produces slips; bulk submit books the accounting; a bank journal entry pays; Additional Salary handles everything ad hoc; India statutory computation/reports are layered on by the India Payroll app.

---

## 2. Feature inventory

Legend: **[docs]** verified on docs.frappe.io/hr (page cited); **[clone]** verified in local clone file (path cited); **[rel]** verified in GitHub release notes (link cited); **[prod]** verified on frappe.io/hr.

### 2a. Core payroll run

| Feature | What Frappe docs say it does | Source |
|---|---|---|
| Payroll Period | Start/end window per financial year; anchor for tax slabs; required for flexible benefits/tax | https://docs.frappe.io/hr/payroll-period |
| Salary Component | Earning/Deduction/Employer Contribution types; formula+condition engine; ~15 behavioral flags (see §1.3); formula function library incl. month-conditional amounts | https://docs.frappe.io/hr/salary-component |
| Salary Structure | Frequency, Earnings/Deductions tables (amount or formula per row), payment account, timesheet mode, leave-encashment per-day rate, max benefits, single active structure per employee per period | https://docs.frappe.io/hr/salary-structure |
| Salary Structure Assignment | Employee+structure+From Date+Base+Variable+chosen tax slab; multiple dated revisions; opening taxable-earnings/tax-deducted balances | https://docs.frappe.io/hr/salary-structure-assignment ; https://docs.frappe.io/hr/payroll-settings |
| Bulk Salary Structure Assignment | Assign one structure to many employees filtered by Grade/Department/Designation/Employee | https://docs.frappe.io/hr/salary-structure-assignment ; https://docs.frappe.io/hr/salary-structure |
| Payroll Entry | Bulk monthly run with filters (Branch/Dept/Designation/Project/Grade), Get Employees → Create Slips → Bulk Submit → Make Bank Entry; Validate Attendance checkbox; tax flags; duplicate protection | https://docs.frappe.io/hr/payroll-entry |
| Salary Slip | Auto-computed earnings/deductions, YTD + MTD per component, payment days logic, leave details, print formats incl. YTD format, email on submit, list-view bulk email | https://docs.frappe.io/hr/salary-slip |
| Salary Slip totals & tax display | gross_pay / total_deduction / net_pay / rounded_total; income tax breakup section, current month income tax, future tax deductions, income from other sources, accrued benefits, employer contributions table | https://docs.frappe.io/hr/salary-slip + clone `hrms/payroll/doctype/salary_slip/salary_slip.json` |
| Income Tax Slab | Slab rows with From/To, per-slab conditions (age/gender/amount), cess table, exemption switch, standard exemption amount | https://docs.frappe.io/hr/income-tax-slab |
| Employer Contribution components | Third component type in dedicated structure table (e.g., employer PF 12% = `BS * 0.12`), part of CTC, not on slip earnings; feeds CTC Break-up report | https://docs.frappe.io/hr/salary-component |
| CTC computation | On assignment save, CTC = (per-cycle gross + employer contributions + non-payout earnings) × cycles; Employee CTC Break-up report | https://docs.frappe.io/hr/salary-component |
| Accrual components | "Accrual Component" flag for accrue-then-pay bonuses (e.g., 5% of basic monthly, paid after 10 months via Additional Salary); tracked in Employee Benefit Ledger; Accrued Earnings report | https://docs.frappe.io/hr/employee-flexible-benefits |
| Statistical components | Non-monetary reference values usable in formulas | https://docs.frappe.io/hr/salary-component |
| Payroll frequency support | Monthly et al.; frequency is optional for timesheet-based runs | https://docs.frappe.io/hr/create-payroll-entry-with-timesheets |
| Multi-company payroll | Company field on all payroll docs; company filter on dashboards (v16.60 Insights workbooks) | docs pages above + https://github.com/frappe/hrms/releases/tag/v16.60.0 |
| Job-offer-to-structure link | Job Offer can compute a salary break-up from a chosen Salary Structure (v16.60) | https://github.com/frappe/hrms/releases/tag/v16.60.0 |

### 2b. Tax & statutory (India + generic)

**Verified split — what lives where matters:**

| Layer | Contains | Evidence |
|---|---|---|
| **Core hrms (all countries)** | Income Tax Slab engine; TDS deduction component ("Variable Based On Taxable Salary"); exemption categories/sub-categories; Declaration & Proof Submission; Employee Other Income; HRA exemption calc (India-specific but in core); standard tax exemption amount; Income Tax Computation / Income Tax Deductions reports | https://docs.frappe.io/hr/income-tax-slab, /setting-up-income-tax-deduction, /employee-tax-exemption-declaration, /employee-tax-exemption-proof-submission, /employee-other-income; clone `hrms/payroll/report/` |
| **Core hrms India regional layer (built in)** | Custom fields only: Salary Component "Component Type" (Provident Fund / Additional PF / Provident Fund Loan / Professional Tax); Employee PAN, IFSC, salary mode, bank fields; Company Basic/HRA component settings; auto-created Indian Gratuity Rule; HRA exemption utils | clone `hrms/regional/india/setup.py`, `utils.py`, `data/salary_components.json` |
| **India Payroll app (separate app, frappe/india-payroll, 2026, for v16)** | EPF employee + VPF + wage ceiling + employer split reconstruction (EPF/EPS/EDLI/admin charges); ESI (wage ceiling incl. disability ceiling, decided on full monthly gross); Professional Tax (15+ states incl. Maharashtra Feb charge); LWF (14 states, monthly/half-yearly/annual); surcharge with marginal relief; old-vs-new regime comparator + regime write-back to assignment; quarterly TDS 24Q e-filing via Sandbox API; Form 16 generation; statutory registers with exports: PF Register (EPFO ECR), ESIC, PT, LWF, Bank Mandate | https://frappe.io/hr/india-payroll ; https://github.com/frappe/india-payroll (README) |
| **India Compliance app (resilient-tech/india-compliance)** | GST/e-invoice/e-way bill centric for ERPNext; **no** payroll PF/ESI/PT coverage on its repo page | https://github.com/resilient-tech/india-compliance |

| Feature (detail) | What docs say | Source | In which layer |
|---|---|---|---|
| Automatic monthly TDS | Deduction component + slab; annual tax split across 12 months; slab ignored if a formula is set on that component | https://docs.frappe.io/hr/setting-up-income-tax-deduction | core |
| Tax Exemption Declaration | Employee declares per sub-category, one per payroll period, HRA sub-form (metro flag, monthly rent) | https://docs.frappe.io/hr/employee-tax-exemption-declaration | core |
| Tax Exemption Proof Submission | Any number of proofs; applied in last payroll; "Deduct Tax For Unsubmitted Tax Exemption Proof" flag to force earlier true-up | https://docs.frappe.io/hr/employee-tax-exemption-proof-submission | core |
| Employee Other Income | Employee declares outside income (amount + source) per payroll period → feeds annual tax | https://docs.frappe.io/hr/employee-other-income | core |
| Deduct Tax For Unclaimed Employee Benefits | Flag on Payroll Entry / slip to tax unclaimed flexible benefits | https://docs.frappe.io/hr/setting-up-income-tax-deduction | core |
| Tax breakup display on slip | "display tax break up on salary slip" shipped in v15 | https://github.com/frappe/hrms/releases/tag/v15.0.0 | core |
| EPF / VPF / EPS / EDLI | Auto-computation, employer split reconstruction, ECR export | https://github.com/frappe/india-payroll README; https://frappe.io/hr/india-payroll | India Payroll app |
| ESI | Combined contribution, ceiling decided on full monthly gross | same | India Payroll app |
| Professional Tax | State-wise slabs, 15+ states, Maharashtra Feb special | same | India Payroll app |
| LWF | 14 states, correct frequency per state | same | India Payroll app |
| Surcharge + marginal relief | High-earner boundary smoothing | same | India Payroll app |
| Regime selector (old vs new) | Employee self-serve comparator; writes regime to assignment; manager can email employees | same | India Payroll app |
| TDS 24Q e-filing + Form 16 | Quarterly return via Sandbox API; Form 16 generation | https://github.com/frappe/india-payroll README | India Payroll app |
| Statutory filing registers | PF (EPFO ECR), ESIC, PT, LWF registers with export; Bank Mandate report | same | India Payroll app |
| Gratuity (India Payment of Gratuity Act rule auto-created) | 15/26 fraction rule example | https://docs.frappe.io/hr/gratuity-rule | core |

**Note on older history:** whether pre-v14 hrms shipped dedicated PF/ESI/PT doctypes is **unverified** this session (the current clone contains only the custom-field layer above). Do not rely on any claim about pre-v14 regional doctypes.

### 2c. Variable pay & adjustments

| Feature | What docs say | Source |
|---|---|---|
| Additional Salary | Ad-hoc earn/deduct for an employee on a Payroll Date; flags: Overwrite Salary Structure Amount, Deduct Full Tax on Selected Payroll Date; recurring via Is Recurring + From/To (monthly repeat); filter for inactive employees | https://docs.frappe.io/hr/additional-salary ; https://github.com/frappe/hrms/releases/tag/v15.0.0 |
| Retention Bonus | Wrapper doc (employee, payment date, amount, component) → auto-creates Additional Salary on submit | https://docs.frappe.io/hr/retention-bonus |
| Employee Incentive | Wrapper doc (employee, amount, payroll date, component) → auto-creates Additional Salary | https://docs.frappe.io/hr/employee-incentive |
| Flexible Benefits (concept) | Tax-exempt salary components (e.g., phone, fuel) paid pro-rata via salary or via claim; 3 payout modes: accrue-and-pay-at-period-end / accrue-and-pay-on-claim (+ optional auto-payout of unclaimed in final cycle) / claim-anytime-up-to-limit; monthly entitlement prorated by attendance if "Depends on Payment Days" | https://docs.frappe.io/hr/employee-flexible-benefits |
| Employee Benefit Application | Employee elects split across benefit components; one per payroll period; mandatory flag available in Payroll Settings; fallback to assignment if absent | https://docs.frappe.io/hr/employee-benefit-application ; clone `hrms/payroll/doctype/payroll_settings/payroll_settings.json` (`mandatory_benefit_application`) |
| Employee Benefit Claim | Lump-sum claim paid in next salary; unclaimed paid in final payroll; separate payment entry option per component | https://docs.frappe.io/hr/employee-benefit-claim |
| Employee Benefit Ledger | Per accrual/payout ledger entries per employee; accruals shown in slip "Accrued Benefits" table; Accrued Earnings report for pending payouts | https://docs.frappe.io/hr/employee-flexible-benefits |
| Leave Encashment | Per-structure per-day rate; Leave Encashment doc (within allocation window) auto-creates Additional Salary; encashable types flagged on Leave Type; also auto-encashment drafts on allocation expiry (HR Settings "Auto Leave Encashment"); v16 adds encashment via Payment Entry (outside salary) | https://docs.frappe.io/hr/how-to-encash-unused-leaves-using-salary-slips ; https://docs.frappe.io/hr/hr-settings ; https://github.com/frappe/hrms/releases/tag/v16.0.0 |
| Arrears (backdated structure revision) | Pick employee + structure + from-date; system diffs old vs new for past months; on submit creates Additional Salary for earnings/deductions and benefit-ledger accruals | https://docs.frappe.io/hr/arrears (v16 feature, PR #3560 in https://github.com/frappe/hrms/releases/tag/v16.0.0) |
| Payroll Correction (LWP reversal) | Reverse N LWP days for a chosen month; recalculates earnings/deductions/accruals; emits Additional Salary + ledger entries | https://docs.frappe.io/hr/payroll-correction (v16, PR #2942) |
| Overtime | Overtime Type master (hourly-rate or salary-component-derived rate, standard/holiday/weekend multipliers, daily caps); enabled per Shift Type; Overtime Slip fetches hours from attendance; approval → Additional Salary into matching cycle | https://docs.frappe.io/hr/overtime (v16, PR #2886) |
| Employee Other Income | (also tax input) — see §2b | https://docs.frappe.io/hr/employee-other-income |

### 2d. Payroll integrations (attendance / leave / timesheets / expenses / advances / exits)

| Feature | What docs say | Source |
|---|---|---|
| Payroll working-days engine | Two modes (HR/Payroll Settings "Calculate Payroll Working Days Based On"): **Leave** (approved leave applications; LWP types reduce payment days) or **Attendance** (Absent + Half-day + unmarked-as-absent reduce); "Include holidays in total working days" switch; "Consider Unmarked Attendance As" (Present/Absent); "Consider Marked Attendance on Holidays"; half-day fraction setting; DoJ/relieving-date clamping; formula: component amount × Payment Days ÷ Working Days | https://docs.frappe.io/hr/working-days-calculation-in-the-salary-slip ; https://docs.frappe.io/hr/payroll-settings |
| LWP handling | Components flagged Depends on Payment Days reduce by LWP days from Leave Applications ("Is Leave Without Pay" types) or attendance; half-day counts per fraction; "Payroll Correction" reverses mistaken LWP | https://docs.frappe.io/hr/leave-calculation-in-salary-slip ; https://docs.frappe.io/hr/payroll-correction |
| Timesheet-based salary | Structure flagged "Salary Slip Based on Timesheet" + Hour Rate; Payroll Entry (or per-timesheet "Create Salary Slip") sums submitted/billed timesheet hours in the window × rate; slips set timesheets to "Payslip" (no double pay); caps via "Max working hours against Timesheet" | https://docs.frappe.io/hr/create-payroll-entry-with-timesheets ; https://docs.frappe.io/hr/salary-slip |
| Timesheets themselves | Project-module timesheets (employee, activity, hours, project); prerequisite of the above | https://docs.frappe.io/hr/create-payroll-entry-with-timesheets |
| Attendance module | Statuses Present/Absent/On Leave/Half Day/WFH; marking via manual, bulk "Mark Attendance" (range), Employee Attendance Tool (one date × many employees), Upload Attendance (spreadsheet), Auto Attendance (from check-ins), Attendance Request, Leave Application; submitted docs; overtime fields on auto-attendance records | https://docs.frappe.io/hr/attendance |
| Employee Checkin | One doc per punch (IN/OUT), shift auto-attach, off-shift handling, device/biometric import, geolocation capture, shift-location radius rejection, mobile check-in toggle | https://docs.frappe.io/hr/employee-checkin ; https://docs.frappe.io/hr/hr-settings |
| Auto Attendance | Hourly job converts check-in groups to submitted attendance; thresholds for half-day/absent hours; late-entry/early-exit flags with grace; absent buffer; holiday lists; night shifts grouped by start date | https://docs.frappe.io/hr/auto-attendance |
| Shift management | Shift Type (windows, grace, auto-attendance, overtime), Shift Assignment, Shift Schedule (recurring patterns), Shift Request (employee-initiated), Shift Assignment Tool (bulk), Roster (calendar, swap/drag), Shift Location (geofence radius) | https://docs.frappe.io/hr/shift-management |
| Attendance Request | Employee marks worked-without-punch days (On Duty / WFH); warnings table pre-submit; HR-only submit; cancellation reverts linked records; creates Present/WFH records; half-day option | https://docs.frappe.io/hr/attendance-request |
| Leave system feeding payroll | Leave Types (incl. Is LWP, Is Compensatory, Allow Encashment, earned-leave types), Leave Period, Leave Policy + Policy Assignment (auto allocation), Leave Allocation, Leave Application (balance display, half-day, approvers per employee/department, block lists, backdated restriction, "cannot submit if salary already processed for the period"), Compensatory Leave Request (attendance Present on holiday → comp-off balance), Leave Ledger Entries, Earned Leave Schedule (v16), Leave Adjustment (v16) | https://docs.frappe.io/hr/leaves ; /leave-application ; /compensatory-leave-request ; https://github.com/frappe/hrms/releases/tag/v16.0.0 (Earned Leave Schedule PR #3509, Leave Adjustment PR #3336) |
| Holiday management | Holiday List master + Holiday List Assignment (employee or company; v15+), weekly-offs | https://docs.frappe.io/hr/working-days-calculation-in-the-salary-slip ; https://github.com/frappe/hrms/releases/tag/v16.0.0 (PR #3928) |
| Expense Claim | Employee-submitted claims; expense types; approver (per department/employee, auto-share, sanctioned vs claimed amounts, approve/reject with comments); expense taxes; accounting on submit; paid via Payment Entry (create from claim or allocate from Payment Entry); **docs explicitly: payment "should not be clubbed with Salary because the amount will then be taxable"** — no pay-via-salary path; advances offset against claims; Unclaimed Expense Claims report; project/task linkage | https://docs.frappe.io/hr/expense-claim ; clone `hrms/hr/doctype/expense_claim/expense_claim.json` (no salary-pay field) |
| Employee Advance | Advance request → approver submit → Payment Entry / Journal Entry; statuses Paid/Unpaid/Claimed/Returned/Partly; returned via payment; offset via Expense Claim; **no salary-recovery mechanism documented**; v16 ledger behavior + multicurrency | https://docs.frappe.io/hr/employee-advance |
| Employee loans | Loan Type → Loan Application → Loan with repayment schedule; "Repay from Salary" puts Loan Repayment line in slip; v15 moved loans out of hrms core to the Frappe Lending app ("Loan App separation changes", PR #616) | https://docs.frappe.io/hr/loan ; https://github.com/frappe/hrms/releases/tag/v15.0.0 |
| Gratuity | Gratuity Rule (slab-based fractions, min years, experience methods) → Gratuity doc auto-computes from relieving date; **Pay via Salary Slip** checkbox → Additional Salary; or Payment Entry | https://docs.frappe.io/hr/gratuity ; /gratuity-rule |
| Full & Final Statement | On exit: auto-pulls Payables (Salary Slip net_pay, Gratuity, Expense Claim, Bonus, Leave Encashment) and Receivables (Loan, Employee Advance), asset return/cost recovery, per-item settled flags, Create Journal Entry to close → status Paid; consumes payroll data rather than generating a run | https://docs.frappe.io/hr/full-and-final-statement |
| Employee exit basics | Relieving date mandatory for FnF; exit interview separate module | https://docs.frappe.io/hr/full-and-final-statement ; https://docs.frappe.io/hr/employee |

### 2e. Employee self-service (ESS) touchpoints

Verified scope of the bundled mobile PWA (installed at `<site>/hrms`, docs: https://docs.frappe.io/hr/mobile-app-installation): clone `frontend/src/views/` contains exactly — attendance, leave, expense_claim, employee_advance, salary_slip, notifications, profile (+ login/home/settings).

| ESS touchpoint | What docs/releases/clone show | Source |
|---|---|---|
| View & download payslips on mobile | PWA "view & download Salary Slips" (v16 PRs #822, #3321 PDF download) | https://github.com/frappe/hrms/releases/tag/v16.0.0 ; clone `frontend/src/views/salary_slip` |
| Email payslip to employee | Auto on submit + bulk list action | https://docs.frappe.io/hr/salary-slip |
| Encrypted payslip email | Password-protected PDF with policy like `SAL-{first_name}-{dob.year}` | https://docs.frappe.io/hr/payroll-settings |
| Apply leave / attendance on mobile | PWA leaves + attendance; check-in/out with geolocation | https://docs.frappe.io/hr/mobile-app-installation ; /employee-checkin ; clone views |
| Expense claims & advances on mobile | PWA expense_claim + employee_advance views, attachments, workflows | https://github.com/frappe/hrms/releases/tag/v16.0.0 (PRs #807, #1591) |
| Tax exemption declaration + proof submission | Employee-side docs (not PWA views — desk/portal) | https://docs.frappe.io/hr/employee-tax-exemption-declaration ; /employee-tax-exemption-proof-submission |
| Employee Other Income declaration | Employee-side doc | https://docs.frappe.io/hr/employee-other-income |
| Benefit application / claim | Employee-side docs | https://docs.frappe.io/hr/employee-benefit-application ; /employee-benefit-claim |
| Attendance Request (fix missed punch) | Employee raises, HR submits; mobile-supported | https://docs.frappe.io/hr/attendance-request |
| Comp-off request | Employee raises when holiday attendance Present | https://docs.frappe.io/hr/compensatory-leave-request |
| Leave encashment request | Via Leave Encashment doc (HR-triggered in the how-to) | https://docs.frappe.io/hr/how-to-encash-unused-leaves-using-salary-slips |
| Tax regime selector (India Payroll app) | Employee self-serve old-vs-new comparison + exemptions | https://frappe.io/hr/india-payroll |
| Profile / bank details / documents (v16.60) | Employee Profile page: edit personal info, bank-change request with proof, document upload, asset request | https://github.com/frappe/hrms/releases/tag/v16.60.0 |
| Push notifications | PWA push notifications (v15) | https://github.com/frappe/hrms/releases/tag/v16.0.0 (PR #1384) |
| Manager visibility of team docs | Reports-To hierarchy grants managers read on subordinates' claims/leaves/appraisals | https://docs.frappe.io/hr/user-permission-based-on-hierarchy |
| Employee Overview tab (v16.60) | Gross/net pay, attendance, leave balance, pending requests on employee form | https://github.com/frappe/hrms/releases/tag/v16.60.0 |

### 2f. Admin / operations

| Capability | What docs say | Source |
|---|---|---|
| Payroll Settings (singles doctype) | payroll_based_on (Leave/Attendance); consider_unmarked_attendance_as; include_holidays_in_total_working_days; consider_marked_attendance_on_holidays; daily_wages_fraction_for_half_day; max_working_hours_against_timesheet; disable_rounded_total; show_leave_balances_in_salary_slip; email_salary_slip_to_employee (+ sender + template + sender_copy); encrypt_salary_slips_in_emails + password_policy; mandatory_benefit_application; create_overtime_slip; process_payroll_accounting_entry_based_on_employee | https://docs.frappe.io/hr/payroll-settings ; clone `hrms/payroll/doctype/payroll_settings/payroll_settings.json` |
| HR Settings (payroll-adjacent) | retirement age; employee naming; expense approver mandatory; leave settings (auto leave encashment, restrict backdated leave applications, auto allocate leaves by policy, approver mandatory, notification templates); shift settings (multiple shifts/day); mobile check-in toggle | https://docs.frappe.io/hr/hr-settings |
| Employee master payroll fields | Salary mode (Bank/Cash/Cheque), bank name/AC/IBAN/IFSC (IFSC via India layer), CTC, salary currency, payroll cost center, employee advance account, attendance device ID, default shift, approvers (leave/expense/shift), reports-to, DoJ/relieving/retirement | https://docs.frappe.io/hr/employee |
| Roles & permissions | HR Manager / HR User / Employee (ESS) roles; Expense Approver & Leave Approver roles auto-granted from employee master; document share-on-approval; User Permissions restrict employees to own records | https://docs.frappe.io/hr/employee ; /expense-claim ; /leave-application |
| Hierarchy visibility | Reports-To based User Permission auto-grants managers their team's HR docs | https://docs.frappe.io/hr/user-permission-based-on-hierarchy |
| Payroll reports (core hrms) | Salary Register (net pay + components per employee), Bank Remittance (bank transactions per payroll entry), Income Tax Computation, Income Tax Deductions, Salary Payments via ECS, Salary Payments based on Payment Mode, Employee CTC Break-up, Accrued Earnings | clone `hrms/payroll/report/` ; https://docs.frappe.io/hr/human-resources-reports (Salary Register + Bank Remittance described) |
| HR/attendance reports | Monthly Attendance Sheet (shift-wise, grouping), Shift Attendance (v15), Employee Leave Balance, Employee Exits (v14, FnF pending filters), Loan Repayment, Employee Birthday, Employee working on a holiday | https://docs.frappe.io/hr/human-resources-reports |
| Dashboards (v16.60) | Insights workbooks for Payroll, Attendance, Expense Claims, HR, Lifecycle, Recruitment (when Insights installed); classic dashboards otherwise | https://github.com/frappe/hrms/releases/tag/v16.60.0 |
| Accounting integration | Journal Entries per run; per-employee accounting option; cost-center hierarchy; expense claims/advances/gratuity/FnF each book accounts; requires ERPNext accounting (Chart of Accounts prerequisite on claims/advances) | https://docs.frappe.io/hr/payroll-entry ; /expense-claim ; /employee-advance ; /full-and-final-statement |
| Data import | Employee bulk creation via Data Import (minimum columns documented); attendance upload | https://docs.frappe.io/hr/employee ; /attendance |
| Email/notification config | Payroll email sender + template; leave notification templates; email alerts on doc assignment | https://docs.frappe.io/hr/payroll-settings ; /hr-settings ; /expense-claim |
| Onboarding "Create Assignments" | One-click creation of Holiday List, Leave Policy, Salary Structure, Shift assignments for a new employee | https://docs.frappe.io/hr/employee |
| Setup wizard defaults | hrms ships setup.py seeding (e.g., India salary components JSON in regional layer) | clone `hrms/regional/india/data/salary_components.json` |
| India Payroll settings | Enable statutory deductions directly from payroll settings (app screenshot); work state per employee | https://frappe.io/hr/india-payroll |

---

## 3. Terminology map (Frappe term → plain English)

Shared vocabulary for the gap analysis. One line each; all verified in docs cited above.

| Frappe term | Plain English |
|---|---|
| Salary Component | A named pay line-item (earning, deduction, or employer contribution) with its formula/rules. |
| Salary Structure | A template combining components into a complete pay package with frequency and accounts. |
| Salary Structure Assignment | Attaches a structure to one employee from a date, with their actual base/variable amounts and tax slab. |
| Base / Variable | Fixed monthly pay vs at-risk pay stored per assignment. |
| Payroll Entry | The monthly batch job that creates all salary slips for a filter group of employees. |
| Salary Slip | The payslip: earnings, deductions, payment days, YTD/MTD totals, tax breakdown. |
| Payment Days | Days actually paid in the period (working days minus LWP/absence, clamped by DoJ/relieving). |
| Working Days | Total days in the slip period after holiday treatment. |
| Depends on Payment Days | Per-component flag: prorate this line by payment days (i.e., LOP-sensitive). |
| LWP (Leave Without Pay) | Unpaid leave; any Leave Type flagged "Is LWP" reduces pay via payment days. |
| Payroll Period | The financial-year window for which slabs/benefits/exemptions apply. |
| Income Tax Slab | Rate table + conditions + cess for one payroll period, chosen per employee on the assignment. |
| Variable Based On Taxable Salary | Flag that turns a deduction component into the auto-TDS line driven by the slab. |
| Exempted from Income Tax | Component flag: deduct from taxable income without any proof/declaration (e.g., PT). |
| Standard Tax Exemption Amount | Flat, proof-free exemption applied to everyone on a slab. |
| Tax Exemption Declaration | Employee's start-of-year statement of planned investments/exemptions (e.g., 80C). |
| Tax Exemption Proof Submission | Employee's year-end documentary proof; used in the final payroll true-up. |
| Employee Other Income | Employee-declared outside income that raises annual tax liability. |
| Additional Salary | Any ad-hoc pay/deduction injected into a specific payroll month (bonus, arrears, gratuity, encashment, overtime). |
| Is Recurring (Additional Salary) | Repeat the amount monthly between two dates. |
| Retention Bonus / Employee Incentive | Thin wrappers that generate an Additional Salary. |
| Flexible Benefit | A tax-exempt allowance restructured as an annual pool the employee is paid via salary pro-rata or claims. |
| Benefit Application | Employee's election of how the annual benefit pool is split across components. |
| Benefit Claim | Employee's lump-sum withdrawal of accrued benefit amount into next salary. |
| Employee Benefit Ledger | Balance tracker of benefit accruals vs payouts. |
| Accrual Component | Earn-now-pay-later salary line (e.g., loyalty bonus) tracked until paid via Additional Salary. |
| Employer Contribution | Company-paid statutory/retirement contribution (e.g., employer PF) — CTC, not employee cash. |
| Statistical Component | Information-only value usable inside formulas. |
| Arrears | Backdated salary revision: diffs old vs new structure for past months and pays the difference. |
| Payroll Correction | Reversal of wrongly applied LWP days; recalculates affected slips. |
| Overtime Slip | Approved extra-hours payment computed from attendance, delivered via Additional Salary. |
| Overtime Type | Rules for overtime rate/multipliers/caps tied to a shift. |
| Validate Attendance (Payroll Entry) | Force slips to reflect attendance-based payment days. |
| Deduct Tax For Unclaimed Employee Benefits | Flag to tax flexible-benefit amounts not claimed yet. |
| Deduct Tax For Unsubmitted Tax Exemption Proof | Flag to tax declared-but-unproven exemptions before year-end. |
| Leave Encashment | Convert unused leave balance to money via Additional Salary at a per-day rate. |
| Leave Policy / Policy Assignment | Auto-allocation rules assigned to employees. |
| Leave Application | Employee time-off request with balance, approver, half-day. |
| Compensatory Leave Request | Exchange worked-holiday attendance for extra leave balance. |
| Attendance Request | Employee's correction claim for worked-but-not-punched days (On Duty / WFH). |
| Employee Checkin | One raw punch (IN/OUT) with optional geolocation. |
| Auto Attendance | Background job converting punch groups into submitted attendance. |
| Shift Type / Shift Assignment / Shift Schedule | Shift definition / who works it / recurring pattern. |
| Shift Location | Geofence (coordinates + radius) restricting check-ins. |
| Timesheet (Salary Slip based on Timesheet) | Hour-based pay: structure stores an hourly rate; slips pay submitted hours. |
| Expense Claim | Employee reimbursement request, approved and paid via Payment Entry — explicitly not via salary. |
| Employee Advance | Cash advanced to employee; recovered by return payment or offset in a claim. |
| Loan (Repay from Salary) | Loan with EMI schedule; EMI appears as slip deduction. |
| Gratuity / Gratuity Rule | Exit payout computed from service slabs; paid via Additional Salary or Payment Entry. |
| Full & Final Statement | Exit settlement checklist pulling payables/receivables/assets, closed by one Journal Entry. |
| Payroll Settings / HR Settings | Global toggles for payroll math, slip display, payslip email/encryption, attendance & leave behaviour. |
| Salary Register | The classic monthly payroll report (net pay + components per employee). |
| Bank Remittance Report | Per-payroll-entry bank transaction listing. |
| Make Bank Entry | Button producing the lump-sum salary payment Journal Entry. |
| Employee Benefit Application (Mandatory) flag | Setting forcing employees to elect benefit split before payroll. |
| India Payroll app | Separate app adding EPF/ESI/PT/LWF/TDS-24Q/Form 16 + registers on top of Frappe HR v16. |
| PWA (mobile app) | Frappe HR's installable web app at `<site>/hrms`: attendance, leave, claims, advances, payslips. |

---

## 4. Fenzit payroll V1 verdicts

Context recap for judgment: India SMB, field service (technicians + office staff), ~150 users, RN mobile app already does attendance punch + leave apply + payslip display; web console for owner/admin payroll; monthly payroll engine exists with LOP handling, payslips, PF bits, statutory state rules; NestJS + Supabase (no GL/accounting module implied); small admin team.

**YES** = build in V1. **LATER** = documented need, defer past V1. **NO** = skip unless strategy changes. "Judgment" marks where the verdict (not the facts) is my call.

| # | Feature | What Frappe docs say (abridged) | Verdict | Rationale (Fenzit context) |
|---|---|---|---|---|
| 1 | Employee master with payroll fields (bank AC/IFSC, salary mode, PAN, DoJ/relieving, cost center) | Central record; payroll tab feeds slips and bank entries (https://docs.frappe.io/hr/employee) | **YES** | Every payslip needs bank/PAN/DoJ data; PF filing needs PAN/UAN-grade fields. Judgment. |
| 2 | Salary Component + formula/condition engine | Building blocks with flags (tax-applicable, prorate-on-LOP, exempt) (https://docs.frappe.io/hr/salary-component) | **YES** (subset of flags) | Need Basic/HRA/special-allowance/PT/PF/TDS lines with proration; skip exotic flags (statistical, accrual, flexible) in V1. Judgment on subset. |
| 3 | Salary Structure template | Frequency + earnings/deductions rows (https://docs.frappe.io/hr/salary-structure) | **YES** | One or two standard SMB structures (e.g., Field Staff, Office Staff) keep setup sane for 150 users. Judgment. |
| 4 | Salary Structure Assignment (dated, per employee, base amount) | Per-employee link + amounts + slab choice (https://docs.frappe.io/hr/salary-structure-assignment) | **YES** | Revisions with From-Date are mandatory for raises; tax slab choice per employee needed for India TDS. Judgment. |
| 5 | Bulk structure assignment tool | Filter by grade/department/designation → bulk assign (https://docs.frappe.io/hr/salary-structure-assignment) | **YES** | Onboarding ~150 users at once; owners won't assign one-by-one. Judgment. |
| 6 | Monthly bulk payroll run (Payroll Entry equivalent) | Filters → get employees → create slips → bulk submit (https://docs.frappe.io/hr/payroll-entry) | **YES** | Fenzit already has a run engine; keep bulk-create + bulk-submit pattern + duplicate protection. Judgment. |
| 7 | Payment-days engine driven by attendance/leave (LOP) | Leave or Attendance mode; unmarked-as; holiday treatment; half-day fraction (https://docs.frappe.io/hr/working-days-calculation-in-the-salary-slip) | **YES** | Field-service punches must convert to pay; Fenzit's LOP handling must match the "Consider Unmarked Attendance As" semantic (default Present) — a subtle but critical default. Judgment. |
| 8 | Salary Slip with component-wise YTD/MTD + tax breakup + payment-day breakdown | (https://docs.frappe.io/hr/salary-slip; tax breakup v15 rel note) | **YES** | Employees dispute payslips; YTD + tax breakup reduces owner queries; mobile display already planned. Judgment. |
| 9 | Payslip PDF + email delivery | Auto email on submit; bulk list email; template/sender (https://docs.frappe.io/hr/payroll-settings) | **YES** | Office staff without the app still need the slip; email is cheap; Fenzit already shows slips in mobile. Judgment. |
| 10 | Encrypted payslip emails (password policy) | Encrypted PDF with policy template (https://docs.frappe.io/hr/payroll-settings) | **LATER** | Nice privacy touch; India SMB V1 rarely needs it. Judgment. |
| 11 | Auto TDS via tax slabs ("Variable Based On Taxable Salary") | Annual projection ÷ cycles, slab conditions, cess (https://docs.frappe.io/hr/income-tax-slab, /setting-up-income-tax-deduction) | **YES** | India payroll without slab-based TDS is incomplete even for SMBs; slab engine is well-scoped. Judgment. |
| 12 | Professional Tax component support (state slabs, month-conditional formulas) | Month-based formula example (`getdate(start_date).month`) in docs; India Payroll app does state engine (https://docs.frappe.io/hr/salary-component; https://frappe.io/hr/india-payroll) | **YES** | Fenzit already has statutory state rules; PT is the highest-frequency small deduction. Judgment. |
| 13 | PF/EPF computation (employee 12%, ceiling, employer split) | Core: only component typing; full engine in India Payroll app (https://github.com/frappe/india-payroll) | **YES** (basic) / **LATER** (ECR export) | Fenzit has "PF-related bits"; V1 needs correct deduction math; EPFO ECR file export can wait. Judgment. |
| 14 | ESI | Wage-ceiling check on full monthly gross (https://github.com/frappe/india-payroll) | **LATER** | Only applies below ₹21k gross; still common for field staff — early V1.x, not launch. Judgment. |
| 15 | LWF (state-wise) | 14 states, varied frequency (https://github.com/frappe/india-payroll) | **LATER** | Long-tail states; add on demand. Judgment. |
| 16 | Tax exemption declarations + proof submission workflow | Employee declarations → year-end proof → final-payroll true-up (https://docs.frappe.io/hr/employee-tax-exemption-declaration, /employee-tax-exemption-proof-submission) | **LATER** | Most Indian SMBs run regime-based or simple TDS in V1; the declaration/proof loop is a big UX investment (categories, proofs, true-up). Judgment. |
| 17 | HRA exemption (metro/non-metro min-of-three) | Built into declarations + Company HRA settings (https://docs.frappe.io/hr/employee-tax-exemption-declaration) | **LATER** | Depends on #16. Judgment. |
| 18 | Old vs new regime comparator + regime lock-in | India Payroll app feature (https://frappe.io/hr/india-payroll) | **LATER** | Post-V1 differentiator; needs declarations anyway. Judgment. |
| 19 | Surcharge with marginal relief | India Payroll app (https://github.com/frappe/india-payroll) | **LATER** | Affects a tiny minority of 150-user SMBs. Judgment. |
| 20 | TDS 24Q e-filing + Form 16 | Via Sandbox API (https://github.com/frappe/india-payroll) | **NO** for V1 / **LATER** | Owner can file via CA; heavy integration. Judgment. |
| 21 | Statutory registers (EPF ECR, ESIC, PT, LWF, bank mandate) | Filing-ready exports (https://github.com/frappe/india-payroll) | **LATER** | EPF ECR is the first one to add after V1 (ties to #13). Judgment. |
| 22 | Additional Salary (bonus/arrears/one-off pay or deduction, recurring option) | Payroll-date injection into slips (https://docs.frappe.io/hr/additional-salary) | **YES** | Single mechanism covers Diwali bonus, one-time deductions, mid-month fixes — must-have for real payroll. Judgment. |
| 23 | Backdated structure revision handling (Arrears doctype) | Diffs past months → Additional Salary (https://docs.frappe.io/hr/arrears) | **YES** (mechanism) / **LATER** (dedicated UI) | Pay revisions effective mid-year are routine; V1 can implement via additional-salary math; the self-serve arrears screen can come later. Judgment. |
| 24 | LWP reversal / payroll correction | Pick month, reverse days, recalc (https://docs.frappe.io/hr/payroll-correction) | **LATER** | Owners can cancel/amend a slip in V1; the guided tool is polish. Judgment. |
| 25 | Retention Bonus / Employee Incentive wrappers | Generate Additional Salary (https://docs.frappe.io/hr/retention-bonus, /employee-incentive) | **LATER** | Pure sugar over #22; skip as separate doctypes. Judgment. |
| 26 | Flexible benefits pool (benefit application/claim/ledger, 3 payout modes) | Complex benefit restructuring (https://docs.frappe.io/hr/employee-flexible-benefits) | **NO** for V1 / **LATER** | Indian SMB field-service CTCs rarely structure flexible pools; high complexity (ledger, claims, tax interplay). Judgment. |
| 27 | Reimbursements (expense claims) | Approve → pay via Payment Entry; explicitly *not* via salary to avoid making it taxable (https://docs.frappe.io/hr/expense-claim) | **YES** (claims + approval) / **NO** (pay-through-salary) | Field techs need fuel/tool reimbursement; follow Frappe: pay separately, keep out of salary for tax cleanliness. Judgment. |
| 28 | Employee advances with claim-offset and return | Advance → payment → offset in claim or return (https://docs.frappe.io/hr/employee-advance) | **LATER** | Useful for field service (travel advances) but V1 can run on expense claims alone; note Frappe itself doesn't recover from salary. Judgment. |
| 29 | Salary recovery of advances/loans | Loans: "Repay from Salary" slip line (https://docs.frappe.io/hr/loan) | **LATER** | Deduction-from-salary for advances is a common SMB ask even though Frappe lacks it for advances — good future differentiator. Judgment. |
| 30 | Employee loans (EMI schedule) | Moved to Lending app in v15 (https://docs.frappe.io/hr/loan; v15 rel notes) | **NO** | Out of scope for SMB payroll V1. Judgment. |
| 31 | Attendance check-ins (mobile punch → checkin record) | Employee Checkin with geolocation, radius rejection (https://docs.frappe.io/hr/employee-checkin) | **YES** | Fenzit already punches; geofencing is core to field-service credibility. Judgment. |
| 32 | Auto attendance (punch → attendance record with hours, late/early flags) | Hourly job, thresholds, grace, absent buffer (https://docs.frappe.io/hr/auto-attendance) | **YES** | Without auto-conversion, owners manually mark 150 people. Judgment. |
| 33 | Attendance Request (missed-punch fix) | Employee-submitted correction, HR submits (https://docs.frappe.io/hr/attendance-request) | **YES** | Field techs will miss punches constantly; self-service correction is the #1 support-reducer. Judgment. |
| 34 | Leave types + policy + auto allocation | Policies, allocation, block lists (https://docs.frappe.io/hr/leaves) | **YES** (simple subset) | CL/SL/EL + comp-off covers SMB; earned-leave schedules and block lists later. Judgment. |
| 35 | Leave → payroll coupling (LWP, cannot-apply-after-salary-processed guard) | Leave-calculation rules; "cannot submit if salary processed" (https://docs.frappe.io/hr/leave-calculation-in-salary-slip, /leave-application) | **YES** | LWP correctness is the core of the run; the payroll-processed guard prevents retro disputes. Judgment. |
| 36 | Half-day leave + configurable half-day fraction | Fraction setting (https://docs.frappe.io/hr/payroll-settings) | **YES** | Field staff half-days are common; default 0.5. Judgment. |
| 37 | Compensatory off | Worked-holiday → comp balance (https://docs.frappe.io/hr/compensatory-leave-request) | **LATER** | Field service does work holidays, but V1 can pay OT or adjust manually. Judgment. |
| 38 | Leave encashment (in-run) | Per-day rate → Additional Salary (https://docs.frappe.io/hr/how-to-encash-unused-leaves-using-salary-slips) | **LATER** | Year-end event; not in monthly loop. Judgment. |
| 39 | Shift management (types, assignments, schedules, roster) | Full shift suite (https://docs.frappe.io/hr/shift-management) | **LATER** | Field service is geofence-first, shift-second; a default shift + geofence covers V1. Judgment. |
| 40 | Overtime (slips, multipliers from attendance) | Overtime Type + Slip → Additional Salary (https://docs.frappe.io/hr/overtime) | **LATER** (lean-early) | Strong candidate for first post-V1 feature for field staff; docs show it's self-contained (type + slip + additional salary). Judgment. |
| 41 | Timesheet-based salary | Hour-rate structures, timesheet hours → pay (https://docs.frappe.io/hr/create-payroll-entry-with-timesheets) | **NO** | Fenzit pays salaried staff; job costing ≠ payroll V1. Judgment. |
| 42 | Gratuity (rules + payment) | Slab fractions, pay via salary or payment entry (https://docs.frappe.io/hr/gratuity) | **LATER** | Statutory on exit (5+ years service); exits are rare pre-launch. Judgment. |
| 43 | Full & Final settlement | Pull payables/receivables, assets, JE closure (https://docs.frappe.io/hr/full-and-final-statement) | **LATER** | Needed once attrition starts; not for launch with pre-launch headcount. Judgment. |
| 44 | Payslip display in mobile app | PWA views + PDF download (https://github.com/frappe/hrms/releases/tag/v16.0.0; clone views) | **YES** | Already Fenzit's plan; Frappe validates it as table stakes. Judgment. |
| 45 | Mobile check-in + geolocation | PWA check-in, geolocation, radius (https://docs.frappe.io/hr/employee-checkin, /mobile-app-installation) | **YES** | Already Fenzit's plan. Judgment. |
| 46 | Push notifications on approvals | PWA push (v15) | **LATER** | Nice-to-have; polling/notification list is enough at 150 users. Judgment. |
| 47 | Bank details change request with proof (v16.60) | Employee Profile flow (https://github.com/frappe/hrms/releases/tag/v16.60.0) | **LATER** | Good ESS addition after V1; V1 can take bank edits on web console. Judgment. |
| 48 | Hierarchy-based visibility (managers see team docs) | Reports-To → User Permissions (https://docs.frappe.io/hr/user-permission-based-on-hierarchy) | **LATER** | Owner + small admin team in V1; matters when supervisors approve claims. Judgment. |
| 49 | Payroll accounting integration (JEs, cost centers, payable accounts) | Accrual JE + bank JE + per-component accounts (https://docs.frappe.io/hr/payroll-entry) | **NO** for V1 (export-oriented) | Fenzit has no GL module in the brief; produce a payroll summary export for the accountant instead of JEs. Judgment. |
| 50 | Salary Register report | Net pay + components per employee per month (https://docs.frappe.io/hr/human-resources-reports) | **YES** | The owner's monthly audit sheet; trivially derivable from run data. Judgment. |
| 51 | Bank remittance / payment advice | Bank Remittance report (https://docs.frappe.io/hr/human-resources-reports) | **YES** (simple list) | Paying 150 people needs a bank-ready list even without JE integration. Judgment. |
| 52 | Income tax computation/deductions reports | Core hrms reports (clone `hrms/payroll/report/`) | **LATER** | Useful at year-end; V1 shows per-slip tax breakup instead. Judgment. |
| 53 | Monthly Attendance Sheet report | Grouped attendance view (https://docs.frappe.io/hr/human-resources-reports) | **YES** | Owners close attendance before payroll; mirrors Frappe's documented flow. Judgment. |
| 54 | Opening balances (taxable earnings/deducted till date on migration) | Assignment opening balances, only pre-slip (https://docs.frappe.io/hr/payroll-settings) | **LATER** | Matters for mid-year customer onboarding, not launch. Judgment. |
| 55 | Multicurrency payroll/claims/advances | v16 multicurrency claims/advances (v16 rel notes) | **NO** | India-only. Judgment. |
| 56 | Per-employee accounting entries option | Payroll Settings flag (https://docs.frappe.io/hr/payroll-settings) | **NO** | Tied to #49. Judgment. |
| 57 | CTC break-up (offer/assignment level) | Assignment CTC computation + report (https://docs.frappe.io/hr/salary-component) | **LATER** | Helpful for offers; not payroll-run critical. Judgment. |
| 58 | Recruitment / performance / appraisal / fleet / training modules | Documented hubs (https://docs.frappe.io/hr/leaves etc.; https://frappe.io/hr) | **NO** | Different product pillars; out of payroll V1 scope. Judgment. |
| 59 | Biometric device integration | Device logs via Attendance Device ID (https://docs.frappe.io/hr/employee-checkin) | **LATER** | Fenzit is mobile-first; some SMB offices will want biometrics later. Judgment. |
| 60 | Employee Overview tab (pay/attendance snapshot) | v16.60 (https://github.com/frappe/hrms/releases/tag/v16.60.0) | **LATER** | Nice ESS/admin dashboard; post-V1. Judgment. |

**Headline verdicts (the short list):**
- **V1 must-haves (Frappe-validated):** employee payroll fields; component/structure/assignment (dated, bulk); monthly bulk run with duplicate protection; attendance/leave-driven payment days with explicit unmarked-attendance semantics; half-day handling; slab-based TDS + PT; payslip with YTD + tax breakup; payslip email; payslip in mobile; Additional Salary for ad-hoc pay; arrears math; expense claims paid outside salary; salary register + bank list reports; auto attendance + attendance-request corrections; simple leave with LWP coupling.
- **Deliberate Frappe patterns Fenzit should copy:** expense reimbursement is *never* paid through salary (tax cleanliness); bulk-submit produces the accounting event, per-slip submit does not; one lump-sum bank entry; Additional Salary as the single off-cycle vehicle; "cannot apply leave for a salary-processed period" guard.
- **Deliberate gaps in Frappe Fenzit can beat:** no salary recovery of advances (only loan EMIs); pay-via-salary absent for expense claims; India statutory depth requires a second app install (india-payroll), i.e., not zero-config.

---

## 5. Dead-ends, gaps, and unverified items

1. **HTTP 500 pages (old ERPNext-era wiki docs):** `https://docs.frappe.io/hr/income-tax-calculation-in-erpnext`, `/hr/configuring-earned-leave`, `/hr/salary-structure-and-payroll` returned 500 on every retry this session. Earned-leave detail is therefore corroborated only by the Leaves hub + v16 release notes (Earned Leave Schedule, PR #3509). The generic income-tax *computation* narrative was covered instead by `/hr/setting-up-income-tax-deduction` and `/hr/income-tax-slab`.
2. **Docs nav/sidebar not machine-readable:** docs.frappe.io/hr renders no sitemap at `/hr/sitemap.xml` (404); the full page list was recovered from `https://docs.frappe.io/sitemap.xml` (which mixes old ERPNext wiki pages with current Frappe HR pages — old pages like `/hr/how-to-process-payroll-in-erpnext` were ignored as superseded).
3. **Pre-v14 India statutory history unverified:** current hrms `hrms/regional/india/` contains only custom fields, HRA utils, and a gratuity rule seed (verified in clone). Whether earlier versions shipped dedicated PF/ESI/PT doctypes was not verified this session — do not cite such a claim.
4. **india_compliance ≠ payroll:** the app now lives at `resilient-tech/india-compliance` (the old `frappe/india_compliance` URL 404s) and is GST/e-invoice focused per its repo page; it is **not** the India payroll engine. The payroll engine is the new `frappe/india-payroll` app (created 2026-04-09, v16.x).
5. **Mobile app functional docs are thin:** the docs page (`/hr/mobile-app-installation`) covers installation only; ESS feature scope was corroborated from release notes + the PWA source views in the clone.
6. **Payroll Settings page vs code drift:** docs don't yet document the `mandatory_benefit_application` and `create_overtime_slip` flags (found in clone JSON + referenced in the flexible-benefits and overtime doc pages respectively); treat the docs page as slightly behind v16 code.
7. **Docs staleness:** most fetched pages carry "last updated 2026-02-04"; several v16 features (arrears, overtime, payroll correction, benefit redesign) postdate the marketing pages and are documented on individual pages only.
8. **Loan docs staleness:** `/hr/loan` still documents in-app loans while v15 moved loans to the Frappe Lending app (release note PR #616) — treat Loan docs as legacy.
9. **Not fetched (out of payroll scope):** recruitment/performance/fleet/training/interview pages beyond hub descriptions; UAE regional docs; `/hr/push-notification`; `/hr/shift-assignment` and `/hr/shift-request` standalone pages (covered by the shift-management summary).
