# 02 — Frappe HRMS Payroll Engine Internals (code-level reverse engineering)

**Benchmark target**: `frappe/hrms` @ `ea4158c4f8ec84b4c76db028f0898294817cdf06` (HEAD 2026-11-20), local read-only clone at `/Users/admin/workspace/fenzit-meta/workspace/external/frappe-hrms`.
**Purpose**: implementation reference for Fenzit payroll V1 (NestJS + Supabase Postgres, ~150 users, India SMB field-service).
**Method**: every claim below was verified by reading the Python source in this clone. Citations are `path:line` relative to the repo root. Frappe-framework functions that live outside this repo (e.g. `safe_eval` internals, `rounded()`, doc framework) are described at the level verifiable from call sites, and flagged as such.
**Note on versions**: the SSA-based formula pre-evaluation (`SalaryStructureAssignment.get_evaluated_components`) and the `Employee Benefit Ledger` / `Payroll Correction` / `Arrear` doctypes are recent additions in this HEAD; older Frappe releases (v14/v15) evaluate formulas directly in `salary_slip.py`. The engine semantics are the same; only the split of code differs.

---

## 1. Data model — every doctype in the payroll domain

All doctypes live under `hrms/payroll/doctype/<name>/` unless noted. "Feeds payroll" = the doc eventually becomes an `Additional Salary` row or a query input to the slip.

### 1.1 Core calculation chain

| Doctype | File | Purpose | Key behaviour-driving fields | Relationships |
|---|---|---|---|---|
| **Salary Component** | `salary_component.py` + `salary_component.json` | Master definition of one earning/deduction/employer-contribution; carries all evaluation flags | `type` (Earning/Deduction/Employer Contribution) (json `options`); `salary_component_abbr` (formula variable name, auto-generated + deduped at `salary_component.py:88-99`); `condition`, `formula`, `amount`, `amount_based_on_formula` (json `condition_and_formula` section); flags — see §3.4 for all 15; `payout_method` (3 accrual payout options, `salary_component.py:46-51`); `max_benefit_amount`; accounts table | 1—N `Salary Component Account`; referenced by `Salary Detail` rows in Structure/Slip; referenced by `Employee Benefit Detail/Application Detail`; `clear_cache` invalidates `salary_component_values` + `tax_components_by_company` caches (`salary_component.py:78-86`) |
| **Salary Component Account** | `salary_component_account/salary_component_account.json` | Per-company GL mapping of a component | `company`, `account` (expense side for earnings / liability side for deductions), `liability_account` (employer contributions only) | child table of Salary Component; consumed by `PayrollEntry.get_salary_component_account` (`payroll_entry.py:398-413`) and `get_employer_contribution_accounts` (`payroll_entry.py:792-815`) |
| **Salary Structure** | `salary_structure.py` | Reusable template of components for a company/currency/frequency | `payroll_frequency` (Monthly/Fortnightly/Bimonthly/Weekly/Daily, `salary_structure.py:46`); `is_active` (Yes/No); `currency`; `salary_slip_based_on_timesheet` + `salary_component` (the hourly wage component) + `hour_rate` (json fields); `leave_encashment_amount_per_day`; `max_benefits`; `employee_benefits` (default flexible-benefit split); three child tables `earnings`/`deductions`/`employer_contributions` of `Salary Detail` (json) | Company-scoped; assigned to employees via SSA. `make_salary_slip()` maps it to a slip (`salary_structure.py:360-431`). Validates: no `amount/formula` on `variable_based_on_taxable_salary` rows (`salary_structure.py:117-124`); a formula component may NOT also have `depends_on_payment_days` if it references another payment-day-dependent abbr (double-proration guard, `salary_structure.py:130-149`) |
| **Salary Detail** | `salary_detail/salary_detail.json` | Child row (in Structure AND in Slip) — one component instance | `salary_component`, `abbr`, copied flags (`statistical_component`, `is_tax_applicable`, `is_flexible_benefit`, `variable_based_on_taxable_salary`, `depends_on_payment_days`, `deduct_full_tax_on_selected_payroll_date`, `exempted_from_income_tax`, `do_not_include_in_total`, `do_not_include_in_accounts`, `accrual_component`, `is_recurring_additional_salary`); eval trio `condition`/`amount_based_on_formula`/`formula`; amounts `amount`, `default_amount` (full-cycle), `additional_amount` (from Additional Salary), `tax_on_flexible_benefit`, `tax_on_additional_salary`, `additional_salary` (link back), `year_to_date` | parent either Salary Structure (template) or Salary Slip (computed) |
| **Salary Structure Assignment (SSA)** | `salary_structure_assignment.py` | Per-employee binding of structure + base + tax slab, effective-dated | `employee`, `salary_structure`, `from_date`, `base` (the `BS` variable formulas see), `variable`, `currency`, `income_tax_slab` (mandatory if structure has a tax component, `salary_structure_assignment.py:145-167`), `payroll_payable_account`, `leave_encashment_amount_per_day` (overrides structure), `max_benefits`, `employee_benefits`, `payroll_cost_centers` (percentage split), **opening mid-year values** `taxable_earnings_till_date` + `tax_deducted_till_date` (warning if missing mid-period, `salary_structure_assignment.py:222-238`), computed `annual_gross_earning` + `ctc` (`calculate_ctc_and_gross`, `:279-312`) | N per employee over time; duplicate `from_date` per employee rejected (`:110-117`). New in this HEAD: holds the evaluated component rows used by slips (`get_evaluated_components`, `:240-259`) |
| **Salary Slip** | `salary_slip/salary_slip.py` (+ `salary_slip.json` via class types `:92-159`) | The computed monthly document | `employee`, `start_date`/`end_date`, `posting_date`, `payroll_frequency`, `salary_structure`, `total_working_days`, `payment_days`, `leave_without_pay`, `absent_days`, `unmarked_days`, `salary_slip_based_on_timesheet`, `total_working_hours`, `hour_rate`; totals `gross_pay`, `total_deduction`, `total_loan_repayment`, `net_pay`, `rounded_total`, `year_to_date`, `month_to_date`, `gross_year_to_date`; tax breakup fields `annual_taxable_amount`, `non_taxable_earnings`, `standard_tax_exemption_amount`, `tax_exemption_declaration`, `deductions_before_tax_calculation`, `income_from_other_sources`, `ctc`, `total_income_tax`, `current_month_income_tax`, `future_income_tax_deductions`, `income_tax_deducted_till_date`; `deduct_tax_for_unsubmitted_tax_exemption_proof`; tables `earnings`/`deductions`/`employer_contributions` (Salary Detail), `timesheets`, `leave_details`, `accrued_benefits`; `payroll_entry` link, `journal_entry` link, `salary_withholding`/`salary_withholding_cycle`, `status` (Draft/Submitted/Cancelled/**Withheld**, `:149`) | named `Sal Slip/{employee}/.#####` (`:166-172`); unique per employee+period enforced in `check_existing` (`:383-414`); DB index on (employee,start_date,end_date) at `:2851-2852` |
| **Payroll Entry** | `payroll_entry/payroll_entry.py` | Batch run: select employees → create slips → submit → JEs | `company`, `payroll_frequency`, `start_date`/`end_date`, `currency`, `exchange_rate`, `payroll_payable_account`, `cost_center`, `payment_account`, `branch/department/designation/grade` filters, `salary_slip_based_on_timesheet`, `validate_attendance`, `deduct_tax_for_unsubmitted_tax_exemption_proof`, employees child table (`Payroll Employee Detail` incl. `is_salary_withheld`, `payroll_employee_detail/payroll_employee_detail.json`), `overtime_step` (`:67`) | creates Salary Slips (`payroll_entry` link), accrual JE, employer-contribution JE, bank JE; status Draft/Submitted/Cancelled/Queued/Failed (`:77`) |
| **Payroll Period** | `payroll_period/payroll_period.py` | Annual accounting window for tax YTD math | `company`, `start_date`, `end_date`; overlap validated per company (`:39-67`) | queried by `get_payroll_period` (`:98-112`, redis-cached) and `get_period_factor` (`:115-153`) |
| **Income Tax Slab** | `income_tax_slab/income_tax_slab.py` | Slab table + surcharge/cess + relief thresholds | `currency` (forced to company currency `:42-44`), `effective_from`, `disabled`, `allow_tax_exemption`, `standard_tax_exemption_amount` (e.g. ₹50k std deduction), `tax_relief_limit` (zero-tax rebate threshold), child `slabs` (`TaxableSalarySlab`: `from_amount`, `to_amount` (0=open), `percent_deduction`, per-slab `condition` — `taxable_salary_slab.json`), child `other_taxes_and_charges` (`IncomeTaxSlabOtherCharges`: `percent`, `min_taxable_income`, `max_taxable_income`); India adds custom field `marginal_relief_limit` (`regional/india/setup.py` get_custom_fields Income Tax Slab) | linked from SSA |

### 1.2 Per-employee one-off inputs (all funnel through Additional Salary)

| Doctype | File | Purpose | Key fields | How it reaches payroll |
|---|---|---|---|---|
| **Additional Salary** | `additional_salary/additional_salary.py` | Universal vehicle for any extra earning/deduction in one or many cycles | `employee`, `salary_component`, `type`, `amount`, `payroll_date` (one-off) or `from_date`/`to_date` + `is_recurring` (`before_validate` enforces one or the other, `:43-49`), `overwrite_salary_structure_amount` (replace structure row vs add on top), `deduct_full_tax_on_selected_payroll_date`, `disabled`, `ref_doctype`/`ref_docname` dynamic link (Gratuity, Leave Encashment, Employee Advance, Employee Benefit Claim, Employee Referral, Payroll Correction, Arrear), negative amount rejected (`:66-67`) | picked up by `get_additional_salaries()` (`:331-397`): recurring match = `from_date<=end_date & to_date>=end_date`; one-off match = `payroll_date in [start,end]`; applied in `SalarySlip.add_additional_salary_components` (`salary_slip.py:1718-1774`) |
| **Retention Bonus** | `retention_bonus/retention_bonus.py` | Named bonus wrapper | `bonus_amount`, `bonus_payment_date` (future only, `:36-37`), `salary_component` | `on_submit` creates/updates an Additional Salary with `ref_doctype="Retention Bonus"` (`:39-61`) |
| **Employee Incentive** | `employee_incentive/employee_incentive.py` | Incentive wrapper (requires SSA to exist, `:28-35`) | `incentive_amount`, `payroll_date`, `salary_component` | `on_submit` creates Additional Salary (`:37-52`) |
| **Employee Other Income** | `employee_other_income/employee_other_income.py` | Taxable income from outside payroll (e.g. previous employer) | `amount`, `payroll_period`, `source` | summed directly into annual taxable base via `get_income_form_other_sources` (`salary_slip.py:2347-2360`) — NOT an Additional Salary |
| **Employee Benefit Claim** | `employee_benefit_claim/employee_benefit_claim.py` | Employee claims a flexible benefit (phone bill etc.) | `earning_component`, `claimed_amount`, `payroll_date` (future only `:44-49`), `max_amount_eligible` (computed) | claim limits via Employee Benefit Ledger `get_max_claim_eligible` (`employee_benefit_ledger.py:108-130`); one claim per component per month (`:61-98`); `on_submit` creates Additional Salary (`:100-114`) which the slip records as a Payout in the ledger (`salary_slip.py:1748-1774`) |
| **Employee Benefit Application** | `employee_benefit_application/employee_benefit_application.py` | Annual declaration of how a flexible part of CTC is split across benefits | `payroll_period`, `employee_benefits` detail rows (yearly `amount` per component) | becomes the benefits source instead of SSA rows when set — precedence logic in `get_benefits_details_parent` (`salary_slip.py:2612-2643`); `mandatory_benefit_application` setting (`:2617-2629`) |
| **Employee Benefit Ledger** | `employee_benefit_ledger/employee_benefit_ledger.py` | NEW accrual ledger per benefit component | `transaction_type` (Accrual/Payout), `amount`, `salary_component`, `payroll_period`, `salary_slip`, `reference_doctype`/`reference_document`, `yearly_benefit`, `flexible_benefit` | created on slip submit (`create_employee_benefit_ledger_entry`, `:45-97`); balances read back by slip (`_get_benefit_ledger_entries`, `salary_slip.py:1626-1643`) |
| **Gratuity** | `gratuity/gratuity.py` | Statutory gratuity on exit | `gratuity_rule`, `current_work_experience`, `amount`, `pay_via_salary_slip` + `payroll_date`/`salary_component`, else `expense_account`/`payable_account` GL path (`:81-133`) | amount from Gratuity Rule; `pay_via_salary_slip` creates Additional Salary (`:135-146`); slip submit flips status to Paid (`salary_slip.py:295-317`) |
| **Gratuity Rule** (+ `gratuity_rule_slab`, `gratuity_applicable_component`) | `gratuity_rule/gratuity_rule.py` | Formula: experience method, min years, slab fractions, applicable earning components | `work_experience_calculation_function` (Manual / Round off / Exact), `total_working_days_per_year`, `minimum_year_for_gratuity`, `calculate_gratuity_amount_based_on` (Current Slab / Sum of all previous slabs), slabs `from_year/to_year/fraction_of_applicable_earnings` | consumed by `Gratuity.calculate_work_experience_and_amount` (`gratuity.py:167-288`) |
| **Arrear** | `arrear/arrear.py` | NEW: recompute arrears from a chosen arrear_start_date within the period | `arrear_start_date`, `payroll_period`, `salary_structure`, breakup tables | creates Additional Salary rows with `ref_doctype="Arrear"` |
| **Payroll Correction** | `payroll_correction/payroll_correction.py` | NEW: reverse LWP days already deducted in a past slip | `salary_slip_reference`, `days_to_reverse`, `payroll_period`; breakup auto-filled from slip (`populate_breakup_table`, `:141-223`) | per-day amount = `default_amount / total_working_days * days_to_reverse` (`:217-218`); creates Additional Salary (`:230-247`) + accrual ledger entries (`:249-274`); the slip accepts a `lwp_days_corrected` correction in `get_working_days_details` (`salary_slip.py:646-648`, verified against corrections in `verify_lwp_days_corrected`, `salary_slip.py:2820-2848`) |
| **Salary Withholding** (+ `salary_withholding_cycle`) | `salary_withholding/salary_withholding.py` | Hold an employee's salary for N cycles (e.g. notice not served) | `from_date`, `number_of_withholding_cycles`, `payroll_frequency`; cycles auto-generated with `from_date/to_date/is_salary_released/journal_entry` (`set_withholding_cycles_and_to_date`, `:91-109`) | slip status becomes `Withheld` when a cycle matches (`salary_slip.py:257-263`, `get_salary_withholdings` `payroll_entry.py:1973-2003`); withheld slips excluded from normal bank entry but payable via `make_bank_entry(for_withheld_salaries=1)` (`payroll_entry.py:1092-1136`) |

### 1.3 Tax declaration chain

| Doctype | File | Purpose | Key fields / logic |
|---|---|---|---|
| **Employee Tax Exemption Category / Sub Category** | `employee_tax_exemption_category/`, `employee_tax_exemption_sub_category/` | Master data for exemption heads (e.g. 80C) | `max_amount` per category; sub-category has `is_active`, `exemption_category` |
| **Employee Tax Exemption Declaration** | `employee_tax_exemption_declaration/employee_tax_exemption_declaration.py` | Start-of-year declaration | `payroll_period`, `declarations` rows (`amount` per sub-category), computed `total_declared_amount` (`:54-57`), `total_exemption_amount` = Σ min(amount, sub-category max) capped by category max (`get_total_exemption_amount`, `hr/utils.py:278-302`) + HRA exemption (India) (`:64-81`); one per employee+period (`validate_duplicate_exemption_for_payroll_period`, `hr/utils.py:253-267`) |
| **Employee Tax Exemption Proof Submission** | `employee_tax_exemption_proof_submission/employee_tax_exemption_proof_submission.py` | End-of-year proof replacing declaration | `tax_exemption_proofs` rows, `exemption_amount` (`:59-62`), `house_rent_payment_amount` + rented dates (India fields); used instead of declaration when `deduct_tax_for_unsubmitted_tax_exemption_proof` is set (`salary_slip.py:2322-2341`) |
| **Income Tax Slab** (see above) | | | |

### 1.4 Leave / expense doctypes feeding payroll

| Doctype | File | Purpose | Payroll link |
|---|---|---|---|
| **Leave Application** | `hr/doctype/leave_application/leave_application.py` | Approved leave | read by `get_lwp_or_ppl_for_date_range` (`salary_slip.py:2732-2770`): only `docstatus=1, status="Approved"`, leave type `is_lwp`/`is_ppl`, and **`salary_slip` field empty** (a leave already attached to a slip is not double counted, `:2755`) |
| **Leave Type** | `hr/doctype/leave_type/` | `is_lwp`, `is_ppl`, `fraction_of_daily_salary_per_leave`, `include_holiday`, `allow_encashment`, `non_encashable_leaves`, `max_encashable_leaves`, `earning_component` (component used when encashing) | drives LWP math (`salary_slip.py:867-878`) and encashment (`leave_encashment.py:117-123`, `:192-194`) |
| **Attendance** | `hr/doctype/attendance/` | statuses Present/Absent/Half Day/On Leave + `half_day_status` | read when Payroll Settings `payroll_based_on == "Attendance"` (`salary_slip.py:593-600`) |
| **Leave Encashment** | `hr/doctype/leave_encashment/leave_encashment.py` | Cash out unused leaves | balance math `:168-185`; amount = days × `leave_encashment_amount_per_day` (SSA override → structure) `:212-237`; `pay_via_payment_entry` → direct GL (`:325-364`) else Additional Salary on `earning_component` of the Leave Type (`:187-201`) |
| **Expense Claim** | `hr/doctype/expense_claim/expense_claim.py` | Reimbursement | **no direct slip path in this version**: it is settled either via Payment Entry or as a payable row in Full & Final (`full_and_final_statement.py:242-248`, amounts via `get_account_and_amount` `:404-415`). Advances claimed offset `total_advance_amount` (`:598-655`) |
| **Employee Advance** | `hr/doctype/employee_advance/employee_advance.py` | Salary advance | `repay_unclaimed_amount_from_salary` (`employee_advance.json:180`) schedules return via Additional Salary (created from the form UI, `employee_advance.js:219-229`); the JE layer special-cases these rows: `get_advance_deductions` (`payroll_entry.py:481-502`) credits the **advance_account** instead of the deduction account, with `reference_type="Employee Advance"` (`add_advance_deduction_entry` `:504-520`) |
| **Full and Final Statement** | `hr/doctype/full_and_final_statement/full_and_final_statement.py` | Exit settlement | payables auto-listed: Gratuity, Expense Claim, Bonus, Leave Encashment + Withheld Salary Slips (`:242-248`, `:148-170`); receivables: Employee Advance (+ Loan if lending app) (`:250-254`); asset recovery cost (`:126-136`); one netting Journal Entry (`create_journal_entry`, `:293-365`) |
| **Overtime Slip** | `hr/doctype/overtime_slip/overtime_slip.py` | NEW: overtime pay from attendance hours | amount = `duration × hourly_rate × multiplier` (`:348-372`); hourly rate from overtime type (flat) or derived from salary slip components (`:306-337`); on submit creates Additional Salary (`:195-217`); triggered from Payroll Entry (`payroll_entry.py:1391-1482`, gated by Payroll Settings `create_overtime_slip`) |

### 1.5 Support doctypes

| Doctype | File | Note |
|---|---|---|
| **Bulk Salary Structure Assignment** | `bulk_salary_structure_assignment/` | Wizard that fans out SSAs by filters; reuses `create_salary_structure_assignment` |
| **Employee Cost Center** | `employee_cost_center/` | Child table on SSA: percentage split of cost centers (sum must be 100, `salary_structure_assignment.py:202-220`) |
| **Payroll Employee Detail** | `payroll_employee_detail/` | Child of Payroll Entry; adds `is_salary_withheld` flag (json) |
| **Payroll Correction Child / Salary Slip Leave / Salary Slip Loan / Salary Slip Timesheet** | | child tables described above |
| **Employee Tax Exemption Declaration Category / Proof Submission Detail** | | child tables of declaration/proof |

**Frontend (inventory only, per brief)**: the Vue `frontend/` is employee-facing (Ionic + frappe-ui). Routes: `/home`, dashboards for attendance/leaves/expense-claims/salary-slips (`frontend/src/router/index.js`), attendance request/checkin/shift lists (`frontend/src/router/attendance.js`), leave list/form (`router/leaves.js`), expense claim list/form/detail (`router/claims.js`), employee advance list/form/detail (`router/advances.js`), salary slip detail `frontend/src/views/salary_slip/Detail.vue` (`router/salary_slips.js`). No payroll-run UI in the frontend — admin payroll stays on the Frappe desk.

---

## 2. Salary Slip calculation pipeline

File: `hrms/payroll/doctype/salary_slip/salary_slip.py` (2877 lines). Helper context: `hrms/payroll/utils.py`.

### 2.1 Order of operations

`SalarySlip.validate()` (`salary_slip.py:218-255`) runs, in order:

1. `check_salary_withholding()` (`:257-263`) — sets status `Withheld` if an open Salary Withholding cycle covers [start_date,end_date].
2. `get_status()` (`:355-364`) — Cancelled / Withheld / Draft / Submitted from docstatus + withholding.
3. `validate_active_employee` (`hr/hr/utils.py:813-823`).
4. `validate_dates()` (`:366-378`) — start<end, slip period must intersect joining/relieving dates.
5. `check_existing()` (`:383-414`) — duplicate slip for same employee+start+end (docstatus != 2); timesheet slips instead check timesheet status "Payrolled".
6. `get_date_details()` (`:416-420`) — derive start/end from `payroll_frequency` via `get_start_end_dates` (`payroll_entry.py:1631-1661`): Monthly/Bimonthly = calendar month halves via Fiscal Year (`get_month_details`, `payroll_entry.py:1689-1714`); Weekly = +6 days; Fortnightly = +13; Daily = same day.
7. First load: `get_emp_and_working_day_details()` (`:422-452`) — clears component tables, resolves the structure (`check_sal_struct`, `:476-516`: latest SSA joined to active Salary Structure, optional frequency match, ordered by `from_date desc`, limit 1), pulls timesheet config, adds hourly wage row (`add_timesheet_earning_component`, `:518-524`: `wages_amount = hour_rate × total_working_hours`), then `make_salary_slip(structure, self)` copies the component rows, then loan demand processing.
   Subsequent validates (rows present): `get_working_days_details(lwp=self.leave_without_pay)` (`:232`).
8. `set_salary_structure_assignment()` (`:961-983`) — the effective SSA for `actual_start_date` (latest `from_date <= actual_start_date`, submitted); throws if none.
9. **`calculate_net_pay()`** (`:985-1028`) — see below.
10. `compute_year_to_date()` (`:2503-2525`), `compute_month_to_date()` (`:2527-2545`), `compute_component_wise_year_to_date()` (`:2547-2573`) — SUM over submitted slips in payroll period (or fiscal year fallback `:2575-2585`).
11. `add_leave_balances()` (`:2587-2606`) — only if Payroll Settings `show_leave_balances_in_salary_slip`.
12. Max-working-hours alert for timesheet slips (`:242-252`).

`calculate_net_pay()` (`:985-1028`) exact sequence:

```
if payroll_period: remaining_sub_periods = get_period_factor(...)[1]      # :993-1002
calculate_component_amounts("earnings")                                   # :1005
set_gross_pay_and_base_gross_pay()   # gross = Σ earnings with depends_on_payment_days re-proration # :986-990,1007
calculate_component_amounts("deductions")                                 # :1010
set_loan_repayment(self)             # lending-app loans (no-op otherwise) # :1012
apply_regional_deductions()          # @hrms.allow_regional no-op here     # :1017,1030-1033
calculate_component_amounts("employer_contributions")                     # :1021
apply_regional_employer_contributions()                                   # :1023,1035-1038
set_precision_for_component_amounts()                                     # :1025,1990-1993
set_net_pay()                                                             # :1026,1040-1055
compute_income_tax_breakup()         # unless skip_tax_breakup_computation # :1027-1028
```

`set_net_pay()` (`:1040-1055`):

```python
self.total_deduction = self.get_component_totals("deductions")            # :1041
self.net_pay = flt(self.gross_pay) - (flt(self.total_deduction)
              + flt(self.get("total_loan_repayment")))                    # :1045-1047
self.rounded_total = rounded(self.net_pay)                                # :1048
```

`rounded()` is a frappe-framework util (outside this repo; at call sites it rounds to the nearest integer using standard "round-half-away-from-zero" semantics). Rounding of the total can be disabled by Payroll Settings `disable_rounded_total` (`is_rounding_total_disabled`, `:380-381`; also hides the field via property setter, `payroll_settings.py:52-73`).

`get_component_totals()` (`:2362-2377`) skips rows with `do_not_include_in_total` and, when called with `depends_on_payment_days=1` for gross, re-derives each earning via `get_amount_based_on_payment_days`.

### 2.2 Payment days / LOP proration — exact formulas

Driver: `get_working_days_details()` (`:545-648`). Inputs read from Payroll Settings in one cached call (`:546-557`): `payroll_based_on` ("Leave"|"Attendance"), `include_holidays_in_total_working_days`, `consider_marked_attendance_on_holidays`, `daily_wages_fraction_for_half_day` (default 0.5, `:564`), `consider_unmarked_attendance_as` ("Present"|"Absent").

```python
working_days = date_diff(self.end_date, self.start_date) + 1              # :566
holidays = self.get_holidays_for_employee(...)                            # :572
half_day_holidays = [] if include_holidays_in_total_working_days \
    else self.get_half_day_holidays_for_employee(...)                     # :575-579
full_day_holidays = [d for d in holidays if d not in half_day_holidays]   # :580
if not include_holidays_in_total_working_days:
    working_days_list = [d for d in working_days_list if d not in full_day_holidays]
    working_days -= len(full_day_holidays) + HALF_DAY_HOLIDAY_FRACTION * len(half_day_holidays)   # :586
```
`HALF_DAY_HOLIDAY_FRACTION = 0.5` (`:75`). A holiday list day flagged "half day" contributes half a working day.

**Branch A — payroll_based_on == "Attendance"** → `calculate_lwp_ppl_and_absent_days_based_on_attendance()` (`:901-959`), which walks submitted Attendance rows of status Absent/Half Day/On Leave between `start_date` and `actual_end_date` (`:912-914`):

- rows "On Leave"/"Half Day" with a leave type that is neither LWP nor PPL are skipped (`:917-921`) — paid leave costs nothing.
- absent/on-leave rows on holidays are skipped unless `consider_marked_attendance_on_holidays` (`:925-931`).
- day fraction: `day_fraction = 0.5 if date in half_day_holidays else 1` (`:940`).
- Half Day with LWP/PPL leave: `equivalent_lwp = 1 - daily_wages_fraction_for_half_day`; for PPL multiplied by `(1 - fraction_of_daily_salary_per_leave)` (`:942-948`).
- On Leave (LWP): lwp += 1 × day_fraction; (PPL): lwp += `(1 - fraction)` × day_fraction (`:950-954`).
- Absent: `absent += day_fraction` (`:956-957`).

**Branch B — payroll_based_on == "Leave"** → `calculate_lwp_or_ppl_based_on_leave_application()` (`:823-865`) walks each calendar day of `working_days_list`:

```python
for d in working_days_list:
    if self.relieving_date and d > self.relieving_date: break             # :834
    leave = leaves.get(d)                                                 # :837
    if not leave: continue
    if not leave.include_holiday and getdate(d) in holidays: continue     # :842
    equivalent_lwp_count = (1 - daily_wages_fraction_for_half_day) if is_half_day_leave else 1   # :852
    if cint(leave.is_ppl):
        equivalent_lwp_count *= (1 - fraction_of_daily_salary_per_leave) or 1                     # :854-857
    if not leave.include_holiday and getdate(d) in half_day_holidays:
        equivalent_lwp_count *= HALF_DAY_HOLIDAY_FRACTION                 # :859-861
    lwp += equivalent_lwp_count                                           # :863
```
`leaves` comes from `get_lwp_or_ppl_for_date_range` (`:2732-2770`): approved, unattached LWP/PPL applications, expanded day-by-day into a dict. If the slip was saved with a manual `leave_without_pay` that disagrees with computed LWP, a msgprint warns (`:606-613`).

**Payment days** (`get_payment_days`, `:760-784`):

```python
payment_days = date_diff(self.actual_end_date, self.actual_start_date) + 1       # :774
if not include_holidays_in_total_working_days:
    payment_days -= len(holidays) - HALF_DAY_HOLIDAY_FRACTION * len(half_day_holidays)  # :782
```
`actual_start_date` = max(start_date, joining_date) and `actual_end_date` = min(end_date, relieving_date) (`:204-216`) — mid-joinee/mid-exit handled here. Employee joining after period → 0 (`:761-763`); relieved before period start requires status "Left" else throw (`:765-772`).

**Final combination** (`:615-648`):

```python
self.leave_without_pay = lwp
self.total_working_days = working_days
payment_days = self.get_payment_days(...)
if flt(payment_days) > flt(lwp):
    self.payment_days = flt(payment_days) - flt(lwp)                       # :621
    if payroll_based_on == "Attendance":
        self.payment_days -= flt(absent)                                   # :624
    if payroll_based_on == "Attendance" and consider_unmarked_attendance_as == "Absent":
        unmarked_days = self.get_unmarked_days(...)                        # :630-634
        self.absent_days += unmarked_days
        self.payment_days -= unmarked_days                                 # :636
    half_absent_days = self.get_half_absent_days(...)                      # :637-640  (Half Day rows whose half_day_status == "Absent", :670-686)
    self.absent_days += half_absent_days * daily_wages_fraction_for_half_day
    self.payment_days -= half_absent_days * daily_wages_fraction_for_half_day   # :641-642
else:
    self.payment_days = 0                                                  # :644
if lwp_days_corrected: self.payment_days += lwp_days_corrected             # :646-648 (Payroll Correction)
```

`get_unmarked_days` (`:650-668`): `total_working_days − days_outside_period (before DOJ / after relieving, :688-720) − marked_attendance_days (:733-758)`; holidays subtracted when included in working days. So "unmarked = absent" turns silent no-attendance days into LOP unless settings say "Present". Verbatim:

```python
def get_unmarked_days(self, include_holidays_in_total_working_days, holidays=None, half_day_holidays=None):
    unmarked_days = (
        self.total_working_days
        - self._get_days_outside_period(include_holidays_in_total_working_days, holidays, half_day_holidays)
        - self._get_marked_attendance_days(holidays, half_day_holidays)      # :657-663
    )
    if include_holidays_in_total_working_days and holidays:
        unmarked_days -= self._get_number_of_holidays(holidays)              # :665-666
    return unmarked_days
```

`_get_marked_attendance_days` (`:733-758`) counts submitted Attendance rows in the *actual* (DOJ/relieving-clipped) window, excluding holiday dates, and subtracts half for attendance marked on a half-day holiday. `_get_days_outside_period` (`:688-720`) counts days before DOJ / after relieving, counting half for half-day holidays when holidays are excluded from working days.

**Per-component proration** — `get_amount_based_on_payment_days()` (`:2268-2318`), applied to every slip row flagged `depends_on_payment_days`. Verbatim (four mutually exclusive branches plus rounding):

```python
def get_amount_based_on_payment_days(self, row):
    amount, additional_amount = row.amount, row.additional_amount
    timesheet_component = getattr(self, "_timesheet_component", None)

    if not row.additional_salary and not row.default_amount:                       # (1) pure additional-amount row: untouched
        amount, additional_amount = amount, additional_amount
    elif (                                                                          # (2) the proration branch
        self.salary_structure
        and cint(row.depends_on_payment_days)
        and cint(self.total_working_days)
        and not (row.additional_salary and row.default_amount)   # overwritten additional salary is final
        and (row.salary_component != timesheet_component
             or getdate(self.start_date) < self.joining_date
             or (self.relieving_date and getdate(self.end_date) > self.relieving_date))
    ):
        additional_amount = flt(
            (flt(row.additional_amount) * flt(self.payment_days) / cint(self.total_working_days)),
            row.precision("additional_amount"),
        )
        amount = (
            flt((flt(row.default_amount) * flt(self.payment_days) / cint(self.total_working_days)),
                row.precision("amount"))
            + additional_amount
        )
    elif (                                                                          # (3) zero payment days
        not self.payment_days
        and row.salary_component != timesheet_component
        and cint(row.depends_on_payment_days)
    ):
        amount, additional_amount = 0, 0
    elif (                                                                          # (4) no amount but additional amount set
        not row.amount and row.additional_amount
        and not (row.additional_salary and row.default_amount)
    ):
        amount = flt(row.additional_amount)

    # apply rounding
    if frappe.db.get_value("Salary Component", row.salary_component,
                           "round_to_the_nearest_integer", cache=True):
        amount, additional_amount = rounded(amount or 0), rounded(additional_amount or 0)

    return amount, additional_amount
```

Guards, restated against the real branches: rows sourced from an Additional Salary that **overwrites** a structure amount never re-prorate (`:2278-2280`, `:2308`); the timesheet wage component prorates only when the period straddles DOJ/relieving (`:2282-2285`, `:2301`); both `default_amount` **and** `additional_amount` are prorated together in branch (2); branch (3) zeroes the row only when `payment_days == 0` AND `total_working_days` didn't allow proration. Separately, Additional Salary rows referencing Arrear/Payroll Correction/Employee Benefit Claim/Employee Advance skip the payment-day adjustment entirely via `update_component_row` (`:1972-1977`) before this function is reached. The divisor is `total_working_days`, so `payment_days/total_working_days` is the paid fraction of the month.

Statistical components are also prorated for downstream reference without adding a row (`:1381-1391`).

*Illustrative arithmetic (derived from the quoted code, not a source example)*: 31-day month, 3 full-day holidays spread across it, DOJ on the 11th, 2 approved LWP days after joining. `total_working_days = 31 − 3 = 28` — note the denominator spans the **whole period** (`working_days = date_diff(self.end_date, self.start_date) + 1`, `:566`; the working-days list is likewise built from `self.start_date`, `:581`), while the numerator's holiday subtraction runs on the DOJ-clipped `actual_start_date` window only (`get_payment_days` fetches holidays for `[actual_start_date, actual_end_date]`, `:774-782`). So: `payment_days = 21 − 2 − 2 = 17`, and Basic (`default_amount = 28000`, `depends_on_payment_days`) = `28000 × 17 / 28 = 17000`. A dependent HRA row `0.5 × BS` evaluates to `8500` because it reads the *already prorated* `data["BS"]` (§2.3), never `28000 × 0.5 × 17/28` (which would double-prorate).

Two more verified details of this function:
- **Preview short-circuit** (`:567-570`): with `for_preview=1` both `total_working_days` and `payment_days` are set to the full period length and the method returns immediately. This flag comes only from `process_salary_structure(for_preview=…)` (`:2435-2440`) — the desk "preview slip from structure" flow; it is *not* the tax-breakup preview, which instead copies the doc and forces `payment_days = total_working_days` itself (§2.5 step 8, `:1215-1226`).
- **Unmarked default** (`:626`): `consider_unmarked_attendance_as = payroll_settings.consider_unmarked_attendance_as or "Present"` — when the setting is empty, unmarked days are silently treated as paid; only an explicit "Absent" subtracts them (`:628-636`).

### 2.3 Component evaluation mechanism

**Where evaluation lives now**: `SalaryStructureAssignment._evaluate_all_components()` (`salary_structure_assignment.py:314-345`) evaluates earnings → sets `data["gross_pay"]` = Σ payable earnings (`:329-333`) → deductions → employer contributions in one shared context, producing resolved rows carrying `default_amount` (full-cycle value) + all flags (`SALARY_COMPONENT_FLAGS`, `:23-37`). `_evaluate_component_table()` (`:438-502`) does the actual per-row eval: condition false → `condition_met=False, default_amount=0` (row still returned, because the condition may depend on period fields only the slip knows, `:438-445`); `amount_based_on_formula && formula` → `_safe_eval(formula)`; else fixed `amount`. Each satisfied abbr is written back into `data` so later rows can reference earlier ones (`:487-488`).

**Slip-side evaluation**: `SalarySlip.add_structure_components` (`salary_slip.py:1359-1444`) re-evaluates every structure row **against the slip's own period context** (`eval_condition_and_formula`, `:1471-1505`) to get the prorated `amount`, while `default_amount` stays the full-cycle value from the SSA. Two parallel dicts are maintained in `get_data_for_eval` (`:1446-1469`): `self.data` (prorated, feeds `amount`) and `self.default_data` (full-cycle, feeds `default_amount` and tax preview). The comment at `:1373-1377` is explicit: *proration cascades through dependent formulas* — e.g. `SA = BS * 0.5` inherits BS's proration automatically because `data[BS]` was already prorated.

**Expression language** — `hrms/payroll/utils.py`:

- `sanitize_expression` (`:23-45`): multiline → single line.
- `COMPONENT_EVAL_GLOBALS` (`:57-71`): `int, float, long(=int), round, rounded, date, getdate, get_first_day, get_last_day, ceil, floor, min, max`.
- `get_component_eval_context(employee, ssa)` (`:99-115`) binds, in order: (1) all component abbrs defaulting to 0 (`get_component_abbr_map`, `:77-86`, cached, invalidated on component save `salary_component.py:78-86`); (2) every numeric Salary Slip field defaulted to 0 (`get_salary_slip_field_defaults`, `:89-96`); (3) SSA fields (`base`, `variable`, …); (4) all Employee doc fields. The slip then overlays its own fields last, so slip values win over Employee fields on collision — except `ctc` which is dropped to keep the Employee/SSA value (`salary_slip.py:1452-1459`).
- `_safe_eval` (`:139-158`): **NOT** `frappe.safe_eval`. It normalizes unicode, runs `_check_attributes` (`:118-136`) — an AST walk that rejects `UNSAFE_ATTRIBUTES` (imported from `frappe.utils.safe_exec`, framework repo), any `__` attribute, `NamedExpr` (walrus) and `Lambda` nodes — then executes plain `eval(code, eval_globals, eval_locals)` with `__builtins__ = {}` plus the whitelisted globals. The docstring (`:140-147`) states it is a lighter denylist sandbox intended **only for admin-authored salary formulas**, not arbitrary user input. Enforcement test: `test_salary_slip.py:2700-2731` (walrus → SyntaxError; `.format` blocked; attribute access like `frappe.utils.os.path` → NameError).
- Tax-slab per-slab conditions use real `frappe.safe_eval` instead (`eval_tax_slab_condition`, `income_tax_slab.py:104-129`).

**Variable precedence in the formula context** (later wins; verified binding order):

| Priority | Source | Examples | Where bound |
|---|---|---|---|
| 1 (lowest) | Component abbrs | every `salary_component_abbr` → 0 | `payroll/utils.py:77-86` |
| 2 | Numeric Salary Slip field defaults | `gross_pay=0`, `payment_days=0`, `leave_without_pay=0`, … | `payroll/utils.py:89-96` |
| 3 | SSA fields | `base`, `variable`, `payroll_frequency`, … | `get_component_eval_context`, `payroll/utils.py:99-115` |
| 4 | Employee doc fields | `date_of_joining`, `department`, custom fields, … | same |
| 5 (highest) | Slip's own current values | recomputed `payment_days`, `total_working_days`, `leave_without_pay`, previously evaluated abbrs | `get_data_for_eval` overlay, `salary_slip.py:1446-1469` |

The one deliberate exception: the slip drops its own `ctc` from the overlay so formulas keep seeing the Employee/SSA `ctc` (`salary_slip.py:1452-1459`; pinned by `test_ctc_in_statistical_component_formula`, `test_salary_slip.py:2378`).

**Semantics of amount vs formula** — for a row: if `condition` evaluates falsey → component excluded (returns None, `:1474-1475`). If `amount_based_on_formula` and `formula` → `amount = flt(_safe_eval(formula), precision)`. Else static `amount`. After eval, `data[abbr] = amount` (`:1479-1480`) so subsequent components see it. Zero-amount inclusion is controlled by Salary Component `remove_if_zero_valued` (`salary_slip.py:1420-1444`, `:1926-1927`): rows with 0 are dropped unless the flag is off (or the component is a tax component — tax rows keep zero overwrites, `:1725-1738`).

**`depends_on_payment_days` on a formula row** is explicitly rejected when the formula references another payment-day-dependent abbr (double-proration guard): `salary_structure.py:130-149`.

### 2.4 All Salary Component flags (exact semantics)

Source: `salary_component/salary_component.json` field list + usage sites.

| Flag | Semantics (verified usage) |
|---|---|
| `type` | Earning / Deduction / Employer Contribution — selects parentfield (`COMPONENT_TYPE_TO_PARENTFIELD`, `payroll/utils.py:50-54`) |
| `salary_component_abbr` | Variable name bound into the formula context (`get_component_abbr_map`, `payroll/utils.py:77-86`) |
| `amount_based_on_formula` | Enables `formula` evaluation instead of static `amount`; warning if formula set without it (`salary_structure.py:74-89`) |
| `condition` | Python-expr gate; false → row skipped for this slip (`salary_slip.py:1474-1475`) |
| `formula` | Python-expr; may reference abbrs, `base`, `gross_pay`, `payment_days`, dates, Employee fields |
| `amount` | Static amount used when not formula-based |
| `depends_on_payment_days` | Row prorated by `payment_days / total_working_days` (`salary_slip.py:2268-2297`); zero payment days → zero (`:2299-2304`) |
| `statistical_component` | Value computed but never a slip row; still referenceable by other formulas; prorated in data maps only (`salary_slip.py:1381-1391`) |
| `do_not_include_in_total` | Shown on slip but excluded from gross/deduction/net totals (`get_component_totals`, `:2362-2377`); included in CTC (`salary_structure_assignment.py:297-312`) |
| `do_not_include_in_accounts` | Excluded from Journal Entries even if included in totals (JE filters `payroll_entry.py:437-440`, `:1160-1166`) |
| `remove_if_zero_valued` | Hide row when amount 0 (`:1420-1444`) |
| `is_tax_applicable` | Counts toward taxable earnings (`get_taxable_earnings`, `:2177-2228`) |
| `exempted_from_income_tax` | Deduction subtracted from taxable income without needing declaration/proof (json description; usage `:2205-2219`, `:1257-1286`) |
| `variable_based_on_taxable_salary` | Marks the TDS component; amount auto-computed from slabs; cannot also have amount/formula (`salary_structure.py:117-124`) |
| `deduct_full_tax_on_selected_payroll_date` | Additional Salary variant: tax the whole additional amount at this payroll date rather than spreading (`:2202-2203`, `:1956-1958`) |
| `is_flexible_benefit` | Flexible (claimable) benefit; interacts with `payout_method` |
| `max_benefit_amount` | Yearly cap validated against SSA/structure benefit rows (`salary_structure.py:485-523`) |
| `payout_method` | "" (pay as earned) / "Accrue and payout at end of payroll period" / "Accrue per cycle, pay only on claim" / "Allow claim for full benefit amount" (`salary_component.py:46-51`) |
| `accrual_component` | Accrue balance in Employee Benefit Ledger instead of paying (Earning-only, `salary_component.py:109-136`); slip posts accruals (`salary_slip.py:1393-1416`, `:1543-1581`) |
| `final_cycle_accrual_payout` | For claim-based accruals: pay out unclaimed balance in final cycle (`:1711-1714`) |
| `round_to_the_nearest_integer` | `rounded()` per row after proration (`:2312-2316`) and for benefit amounts (`:1619-1620`) |
| `arrear_component` | Component participates in Arrear / Payroll Correction recomputation (`payroll_correction.py:176-194`) |
| `is_income_tax_component` | Reporting only — inclusion in Income Tax Deductions report (json description; no engine effect found) |
| `disabled` | Component inactive |

Deduction ordering: deductions render in structure-row order; the **tax component is appended last** because `add_tax_components` runs after `add_structure_components` and `add_additional_salary_components` (`calculate_component_amounts`, `:1323-1341`), and it must see final gross + all other deductions (exempted deductions reduce taxable income).

### 2.5 Income tax computation

Pipeline (all in `salary_slip.py` unless noted):

1. **Tax component discovery** — `add_tax_components()` (`:1776-1817`): tax rows = evaluated deduction rows with `variable_based_on_taxable_salary` and no formula/amount; fallback: any manual deduction row flagged as tax (`:1786-1789`); last resort: company-scoped component master defaults (cached `TAX_COMPONENTS_BY_COMPANY`, `:1819-1863`).
2. **Slab resolution** — `get_income_tax_slabs()` (`:2074-2096`): slabs come from `SSA.income_tax_slab` (mandatory — throw if unset `:2077-2083`; disabled slab → throw; slab effective date must be ≤ payroll period start `:2089-2094`).
3. **Period bookkeeping** — `compute_taxable_earnings_for_year()` (`:1057-1094`):
   - `previous_taxable_earnings` = Σ `is_tax_applicable` earnings from submitted slips between period start and this slip's start (`get_salary_slip_details`, `:2118-2161`) + SSA opening `taxable_earnings_till_date` (`get_opening_for`, `:2113-2116`) − exempted deductions.
   - `current_structured_taxable_earnings` = this slip's taxable earnings **for actual payment days** (`get_taxable_earnings(..., based_on_payment_days=1)`, `:1112-1122`).
   - `future_structured_taxable_earnings` = full-cycle taxable earnings × `(round(remaining_sub_periods) − 1)` (`:1099-1101`) — future months assume full attendance, deliberately independent of this month's LOP (behaviour pinned by `test_salary_slip.py:2144`).
   - `current_additional_earnings` / `additional_income_with_full_tax`: from `get_taxable_earnings` (`:2177-2228`), where recurring Additional Salary future months are added via `get_future_recurring_additional_amount` (`:2257-2266`, month-count capped at payroll period end `:2247-2248`).
   - On the last cycle of the period, `deduct_tax_for_unsubmitted_tax_exemption_proof = 1` is forced (`:1068-1069`).
   - `total_taxable_earnings = prev + current_structured + future_structured + current_additional + other_incomes + unclaimed_benefits − total_exemption_amount` (`:1081-1089`); `total_taxable_earnings_without_full_tax_addl_components` subtracts addl income that will be taxed in full separately (`:1092-1094`).
4. **Exemption amount** — `get_total_exemption_amount()` (`:2320-2345`): if proof-deduction forced → use submitted Proof Submission `exemption_amount`, else Declaration `total_exemption_amount`; plus slab `standard_tax_exemption_amount`. Without `allow_tax_exemption` → only standard deduction.
5. **Slab walk** — `calculate_tax_by_tax_slab` (`income_tax_slab.py:47-68`):
   - zero tax if `annual_taxable_earning <= tax_relief_limit` (`:51-52`);
   - `calculate_base_tax_from_tax_slabs` (`:71-86`): for each slab (skipping slabs whose per-slab `condition` fails, `frappe.safe_eval`): final open slab (no `to_amount`): `(E − from + 1) × pct`; closed slab: `(E − from + 1) × pct` if `from ≤ E < to`, else `(to − from + 1) × pct`. Note the `+1` — a slab is inclusive of both endpoints. Verbatim:

   ```python
   def calculate_base_tax_from_tax_slabs(annual_taxable_earning, tax_slab, eval_globals, eval_locals):
       tax_amount = 0
       eval_locals.update({"annual_taxable_earning": annual_taxable_earning})

       for slab in tax_slab.slabs:
           cond = cstr(slab.condition).strip()
           if cond and not eval_tax_slab_condition(cond, eval_globals, eval_locals):
               continue
           if not slab.to_amount and annual_taxable_earning >= slab.from_amount:
               tax_amount += (annual_taxable_earning - slab.from_amount + 1) * slab.percent_deduction * 0.01
               continue
           if annual_taxable_earning >= slab.from_amount and annual_taxable_earning < slab.to_amount:
               tax_amount += (annual_taxable_earning - slab.from_amount + 1) * slab.percent_deduction * 0.01
           elif annual_taxable_earning >= slab.from_amount and annual_taxable_earning >= slab.to_amount:
               tax_amount += (slab.to_amount - slab.from_amount + 1) * slab.percent_deduction * 0.01
       return tax_amount
   ```

   (A consequence of the `+1`: the slabs must be configured so `to_amount` of slab n = `from_amount` of slab n+1 − 1; e.g. 0–400000, 400001–800000. A misconfigured slab table double-counts boundary rupees.)
   - marginal relief hook: `calculate_tax_with_marginal_relief` (`hr/hr/utils.py:755-759`, stub) → India override (`regional/india/utils.py:207-222`): if slab has `marginal_relief_limit` and income is between `tax_relief_limit` and it, tax = min(tax, income − relief_limit).
   - surcharge: `apply_surcharge_with_marginal_relief` (`income_tax_slab.py:132-136`) is an `@erpnext.allow_regional` stub in this repo — surcharge is implemented by the regional app (india_compliance), returning (tax, 0) here.
   - other charges (cess): `calculate_other_charges` (`:89-101`) — flat percent of tax, gated by income min/max range; returns `(tax, surcharge + other)`. The slip adds both to TDS (`calculate_variable_tax` uses the tuple `:2013-2018`). Order of operations in the caller: base tax → marginal relief → surcharge → cess, and cess is levied on the tax *after* surcharge was added inside the same function chain (`calculate_tax_by_tax_slab`, `:58-68`).
6. **Per-period tax spread** — `calculate_variable_tax()` (`:2006-2072`):
   ```
   previous_total_paid_taxes = Σ tax rows (variable_based_on_taxable_salary) of submitted slips this period + SSA tax_deducted_till_date   # :2007-2009, 2163-2175
   total_structured_tax_amount = calculate_tax_by_tax_slab(total_taxable_earnings_without_full_tax_addl_components, ...)   # :2012-2018
   payment_days_share = payment_days / total_working_days if tax row has depends_on_payment_days else 1                    # :2020-2032
   remaining_sub_periods = remaining_sub_periods − 1 + payment_days_share                                                  # :2034
   current_structured_tax_amount = (total_structured_tax_amount − previous_total_paid_taxes) / remaining_sub_periods       # :2038-2041
   full_tax_on_additional_earnings = calculate_tax_by_tax_slab(total_taxable_earnings) − total_structured_tax_amount       # :2046-2051
   current_tax_amount = max(0, current_structured_tax_amount + full_tax_on_additional_earnings)                            # :2053-2060
   current_tax_amount_for_payment_days = current_tax_amount × payment_days_share                                           # :2061
   ```
   The tax row actually written to the slip is `current_tax_amount_for_payment_days` (`:1811-1817`). Zero remaining sub-periods → 0 (`:2042-2043`, test `test_salary_slip.py:2190`).

**Where `remaining_sub_periods` comes from** — `get_period_factor` (`payroll_period.py:115-153`), verbatim. Note it clips the period to DOJ/relieving first, so a mid-year joinee's "remaining months" counts only their employed span:

```python
def get_period_factor(employee, start_date, end_date, payroll_frequency, payroll_period,
                      depends_on_payment_days=0, joining_date=None, relieving_date=None):
    period_start, period_end = payroll_period.start_date, payroll_period.end_date
    if not joining_date and not relieving_date:
        joining_date, relieving_date = frappe.get_cached_value(
            "Employee", employee, ["date_of_joining", "relieving_date"])
    if getdate(joining_date) > getdate(period_start):
        period_start = joining_date
    if relieving_date and getdate(relieving_date) < getdate(period_end):
        period_end = relieving_date

    if payroll_frequency == "Monthly" and not depends_on_payment_days:
        total_sub_periods = get_exact_month_diff(payroll_period.end_date, payroll_period.start_date)
        remaining_sub_periods = get_exact_month_diff(period_end, start_date)
    else:
        salary_days = date_diff(end_date, start_date) + 1
        days_in_payroll_period = date_diff(payroll_period.end_date, payroll_period.start_date) + 1
        total_sub_periods = flt(days_in_payroll_period) / flt(salary_days)
        remaining_days_in_payroll_period = date_diff(period_end, start_date) + 1
        remaining_sub_periods = flt(remaining_days_in_payroll_period) / flt(salary_days)

    return total_sub_periods, remaining_sub_periods
```

The slip calls it without `depends_on_payment_days` (`salary_slip.py:994-1002`), so for Monthly runs the branch is exact-month-diff; non-Monthly frequencies (and the `depends_on_payment_days` callers, e.g. the income-tax computation report) use day ratios. Supporting constant: `PERIODS_PER_YEAR = {Monthly: 12, Fortnightly: 26, Bimonthly: 24, Weekly: 52, Daily: 365}` (`salary_structure_assignment.py:39-45`) used for CTC annualization.
7. **TDS via Additional Salary** — `handle_additional_salary_tax_component()` (`:1865-1888`): if the tax row itself comes from an Additional Salary with `overwrite_salary_structure_amount`, the given amount replaces the whole computed tax for the cycle (`:2036-2037`); without overwrite the row is removed.
8. **Breakup docfields** — `compute_income_tax_breakup()` (`:1130-1178`) fills the display fields: `non_taxable_earnings` (Σ earnings with `is_tax_applicable=0` across prev/current/future periods, incl. a *recalculated preview slip* for future periods — `get_future_period_non_taxable_earnings` copies the doc, sets `payment_days = total_working_days`, re-runs `calculate_net_pay(skip_tax_breakup_computation=True)`, then scales by `ceil(remaining_sub_periods) − 1`, `:1215-1226`), `ctc` (`compute_ctc`, `:1180-1191`), `income_from_other_sources`, `standard_tax_exemption_amount`, `deductions_before_tax_calculation` (Σ `exempted_from_income_tax` deductions incl. future months via formula re-eval per sub-period `:1257-1286`), `tax_exemption_declaration`, `annual_taxable_amount` (`:1157-1162`; computed as `total_earnings − exemptions`, where `total_earnings = ctc + income_from_other_sources`, `:1144`), `income_tax_deducted_till_date` (`:1314-1321`), `future_income_tax_deductions`, `current_month_income_tax`, `total_income_tax`.

### 2.6 Rounding, currency, multi-currency

- Row rounding: per-component `round_to_the_nearest_integer` → `frappe.utils.rounded` (`:2312-2316`).
- Net rounding: `rounded_total = rounded(net_pay)` unless disabled (`:1048`, `:380-381`).
- Precision: every row amount forced to `Salary Detail.amount` precision (`set_precision_for_component_amounts`, `:1990-1993`); formula results use the structure row's precision (`salary_structure_assignment.py:457-461`, `salary_slip.py:1477-1478`).
- Currency: slip has `currency` + `exchange_rate`. Base (`company-currency`) columns are always derived: `base_X = flt(X × exchange_rate, precision)` (`:988-990`, `:1042-1050`). Salary Structure is filtered by currency when resolving for an employee (`check_sal_struct` doesn't filter, but Payroll Entry's `get_salary_structure` does, `payroll_entry.py:1485-1505`), and Income Tax Slab currency must equal SSA currency (`salary_structure_assignment.py:158-167`). Multi-currency salary structures are supported (`test_salary_slip.py:1369`, `test_payroll_entry.py:86`); JE handles mixed currencies by tracking per-account conversion and enabling `multi_currency` (`payroll_entry.py:829-841`, `:1049-1066`).

### 2.7 Slip status lifecycle

| Status | Set by | Meaning / downstream effects |
|---|---|---|
| Draft | initial | After validation; not yet accounting-relevant |
| Submitted | docstatus 1 | `on_submit` (`:276-293`): **throws if `net_pay < 0`** (`:277-278`); updates timesheet status; loan repayment entry (lending app); emails unless `frappe.flags.via_payroll_entry` or `in_patch` (`:285-290`); flips referenced Gratuity / Leave Encashment to "Paid" (`update_payment_status_for_gratuity_and_leave_encashment`, `:295-317`); writes Employee Benefit Ledger entries (`create_benefits_ledger_entry`, `:319-327`). The accrual JE + `journal_entry` write-back happen later at the Payroll Entry level |
| Withheld | `check_salary_withholding` (`:257-263`) | An open Salary Withholding cycle covers the period; excluded from normal bank entry; released via `make_bank_entry(for_withheld_salaries=1)` which flips the cycle row and then the slip to Submitted (`salary_withholding.py:168-228`) |
| Cancelled | docstatus 2 | `on_cancel` (`:329-336`): reverts Gratuity/Encashment to "Unpaid", deletes benefit ledger entries, cancels loan repayment entry; Payroll Entry cancellation also cancels the linked JE (`payroll_entry.py:209-232`) |

`get_status()` (`:355-364`) derives the displayed status from docstatus + withholding each validate. The "Paid via salary slip" linkage (`:295-317`) matches Additional Salary docs whose `payroll_date` falls in the slip window, `ref_doctype` is Gratuity / Leave Encashment, and whose link appears in the slip's `earnings` rows (`:311-314`) — unreferenced ones stay Unpaid.

---

## 3. Payroll Entry flow

File: `hrms/payroll/doctype/payroll_entry/payroll_entry.py` (2003 lines).

Key fields (from the doctype and validated behaviour):

| Field | Role |
|---|---|
| `company`, `payroll_frequency`, `start_date`, `end_date` | Scope of the run; dates must align to the frequency (`validate_dates`, `get_start_end_dates` round-trip, `:1631-1661`) |
| `currency`, `exchange_rate` | Filters structure selection by currency; passed into slips |
| `payroll_payable_account` | Liability account credited with net pay in the accrual JE; must be of type Payable (`validate_payroll_payable_account`, `:154-166`); also filters employee selection (SSA must match) |
| `cost_center` | Fallback cost center when employee/department has none |
| `payment_account` | Bank/cash account for the payment JE |
| `branch` / `department` / `designation` / `grade` | Optional employee filters (`set_filter_conditions`, `:1575-1584`) |
| `salary_slip_based_on_timesheet` | Selects timesheet structures |
| `validate_attendance` | Blocks submission when unmarked days exist (§3.2) |
| `deduct_tax_for_unsubmitted_tax_exemption_proof` | Copied into every slip it creates (`:337-341`) |
| `employees` (Payroll Employee Detail) | Resolved employee list, incl. `is_salary_withheld` flag |
| `salary_slips_created` / `salary_slips_submitted` | Progress counters set during background creation/submission |
| `status` | Draft / Submitted / Cancelled / Queued / Failed (`:77`) + `error_message` |
| `overtime_step` | Tracks the overtime-slip step when `create_overtime_slip` is on (`:67`) |

Note: the Payroll Entry doctype itself carries **no** `journal_entry` field — generated JEs are linked back on each Salary Slip (`ss.journal_entry`, query at `payroll_entry.py:364`; write-back `set_journal_entry_in_salary_slips`, `:1289-1295`). Cancellation finds them via `get_linked_salary_slips` (`:247-249`).

Whitelisted (desk button / endpoint) methods: `fill_employee_details` (`:269`), `create_salary_slips` (`:308`), `submit_salary_slips` (`:371`), `has_bank_entries` (`:1069`), `make_bank_entry` (`:1092`), `get_employees_with_unmarked_attendance` (`:1302`), `create_overtime_slips` (`:1391`), `submit_overtime_slips` (`:1430`), `get_start_end_dates` (`:1631`), `get_end_date` (`:1674`). The accrual and employer-contribution JEs are **not** whitelisted — they run server-side inside `submit_salary_slips_for_employees` right after slips are submitted (`:1864-1865`).

### 3.1 Employee selection

`fill_employee_details()` (`:269-299`) → `get_employee_list()` (`:1910-1947`):

1. `get_salary_structure()` (`:1485-1505`): submitted + active structures of the company filtered by `currency`, `salary_slip_based_on_timesheet`, and (for non-timesheet) `payroll_frequency`.
2. `get_filtered_employees()` (`:1508-1551`): Employee ⋈ SSA where `SSA.docstatus=1`, `Employee.status != "Inactive"`, `Employee.company = filters.company`, `(date_of_joining <= end_date OR null)`, `(relieving_date >= start_date OR null)`, `SSA.salary_structure IN sal_struct`, `SSA.payroll_payable_account = filters.payroll_payable_account`, `filters.end_date >= SSA.from_date`; plus optional `branch/department/designation/grade` filters (`set_filter_conditions`, `:1575-1584`) and user-permission match conditions (`set_match_conditions`, `:1587-1603`).
3. `remove_payrolled_employees()` (`:1615-1628`): employees with a **submitted** slip for exactly [start,end] are dropped from the table.
4. `update_employees_with_withheld_salaries()` (`:301-307`): flags `is_salary_withheld` from open Salary Withholding cycles.

### 3.2 Duplicate / overlap validation

- Before submit: `validate_existing_salary_slips()` (`:123-152`) throws if any of the entry's employees already has a slip (docstatus != 2) for [start,end].
- Slip-level: `check_existing` (`salary_slip.py:383-414`).
- During creation: `get_existing_salary_slips()` (`:1819-1834`) skips already-created employees inside the same entry (note: this one scopes by `payroll_entry`).
- `validate_payroll_payable_account()` (`:154-166`): account type must be "Payable".
- Attendance gate: `before_submit` → `get_employees_with_unmarked_attendance()` (`:1302-1342`): only when `validate_attendance` is checked; unmarked days = payroll window (clipped to DOJ/relieving, `:1380-1389`) − holidays − submitted attendance count; if > 0, submission is blocked (`:113-117`).

### 3.3 Salary slip creation and submission

- `on_submit` → `create_salary_slips()` (`:119-121`, `:308-348`): builds args (frequency, dates, currency, exchange_rate, `deduct_tax_for_unsubmitted_tax_exemption_proof`, `payroll_entry` link); queues a background job when > 30 employees (`:331-346`).
- `create_salary_slips_for_employees()` (`:1738-1791`): inserts one Salary Slip per employee (validate pipeline does the math), sets entry status Submitted + `salary_slips_created`; on failure rolls back, logs, and sets status "Failed" + `error_message` (`log_payroll_failure`, `:1717-1735`).
- `submit_salary_slips()` (`:371-391`) → `submit_salary_slips_for_employees()` (`:1837-1881`): per-slip savepoint (`:1843-1856`); negative net pay slips are skipped (`:1846-1848`); after submission: **`make_accrual_jv_entry(submitted)`** (`:1864-1865`), **email** (`email_salary_slip`, `:1866`, gated by Payroll Settings `email_salary_slip_to_employee`), sets `salary_slips_submitted`. `frappe.flags.via_payroll_entry` suppresses the slip-level email path (`salary_slip.py:285-290`).

### 3.4 Accounting side — which Journal Entries get created

**(a) Accrual JE** — `make_accrual_jv_entry()` (`:619-701`):
- Aggregates submitted slips' Salary Detail rows into `(component, cost_center) → amount` buckets (`get_salary_component_total`, `:445-479`), excluding rows with `do_not_include_in_total=1 AND do_not_include_in_accounts=1` (`:437-440`).
- Cost centers: per-employee percentage split from the SSA (`get_payroll_cost_centers_for_employee`, `:562-606`; fallback Employee.payroll_cost_center → Department → entry.cost_center).
- Entries: **debit** each earning component's `account` (from Salary Component Account, `:398-413`) with cost center; **credit** each deduction component's account; **credit** `payroll_payable_account` for the net payable (`set_payable_amount_against_payroll_payable_account`, `:908-963`).
- Employee Advances being recovered are rerouted: `get_advance_deductions` (`:481-502`) finds Additional Salary rows whose `ref_doctype == "Employee Advance"`, and instead of crediting the component account the JE credits `EmployeeAdvance.advance_account` with `party_type=Employee`, `reference_type="Employee Advance"`, `is_advance="Yes"` (`add_advance_deduction_entry` `:504-520`, `set_accounting_entries_for_advance_deductions` `:522-549`) — this is what "receives" the advance in the books.
- Optional employee-wise payable: Payroll Settings `process_payroll_accounting_entry_based_on_employee` books one payable credit line **per employee** (`:920-950`).
- JE submitted and linked back to every slip (`set_journal_entry_in_salary_slips`, `:1289-1295`).

**(b) Employer contribution JE** — `make_employer_contribution_jv_entry()` (`:703-790`): separate JE; per component debit `expense account` (cost-center split with rounding remainder on last cost center `:722-736`), credit `liability_account` (both required on Salary Component Account, `get_employer_contribution_accounts` `:792-815`), optionally employee-wise liability.

**(c) Bank/payment JE** — `make_bank_entry()` (`:1092-1136`, button on submitted entry): sums earnings − deductions − loan repayment over **non-withheld** slips (`get_salary_slip_details`, `:1138-1177`); credit `payment_account`, debit `payroll_payable_account` (employee-wise if enabled, `:1223-1258`); voucher type "Bank Entry" or "Cash Entry" by account type (`:1277-1287`). Withheld salaries have a separate run with `for_withheld_salaries=1` which links the JE into the Salary Withholding cycle (`link_bank_entry_in_salary_withholdings`, `salary_withholding.py:157-165`) and flips slip status Submitted (`update_salary_withholding_payment_status`, `:168-228`). Employees with zero net are skipped (test `test_payroll_entry.py:872`).

**(d) Cancellation** (`:168-246`): cancel + delete all slips, cancel linked JEs and payment ledger entries (>50 slips → queued action `:184-198`).

**Line-by-line summary of the three JEs** (all rows cost-center tagged unless employee-wise payable is on):

| JE | Line | Account | Amount | Notes |
|---|---|---|---|---|
| Accrual | Dr | Earning component's `account` (Salary Component Account) | Σ prorated amounts by (component, cost center) | expense recognition |
| Accrual | Cr | Deduction component's `account` | Σ amounts | the company's liability toward the deductee (PF dept, tax authority, lender) |
| Accrual | Cr | `payroll_payable_account` | net payable (Σ earnings − Σ deductions) | one line, or one per employee when `process_payroll_accounting_entry_based_on_employee` |
| Accrual | Cr | `EmployeeAdvance.advance_account` (party = Employee) | advance-recovery Additional Salary amounts | replaces the component's deduction-account credit; `reference_type="Employee Advance"`, `is_advance="Yes"` (`:522-549`) |
| Employer contribution | Dr | component's `account` (expense side) | Σ employer-contribution amounts | cost-center split; rounding remainder booked on last cost center (`:722-736`) |
| Employer contribution | Cr | component's `liability_account` | same | both accounts mandatory on Salary Component Account for employer-contribution type (`:792-815`) |
| Bank entry | Cr | `payment_account` | Σ net pay (non-withheld slips) | voucher "Bank Entry"/"Cash Entry" by account type (`:1277-1287`) |
| Bank entry | Dr | `payroll_payable_account` | same | employee-wise when enabled (`:1223-1258`); zero-net employees skipped |
| Withheld release | Cr | `payment_account` / Dr | payable | same JE shape, run with `for_withheld_salaries=1`; JE linked into the Salary Withholding cycle (`salary_withholding.py:157-165`) |

Loan repayments (lending app) reduce the bank-entry payable via `process_loan_repayments_for_bank_entry` (`:1180-1195`), which returns the loan-repayment totals from the slips' `loans` child rows.

### 3.5 Salary slip email + PDF password

`SalarySlip.email_salary_slip()` (`salary_slip.py:2379-2418`): recipient = `Employee.prefered_email` (cached value read, `:2380`); subject/body from Payroll Settings `email_template` rendered with the slip as context (`self.as_dict()`, `:2385-2389`); missing template → fixed subject + "Please see attachment". Attachment via `frappe.attach_print(..., password=password)` (`:2407`); emails are enqueued on the short queue outside tests (`:2413-2414`); missing email address is only a `msgprint`, never an error (`:2417-2418`). Password generated only when `encrypt_salary_slips_in_emails` is set:

```python
password = None
if payroll_settings.encrypt_salary_slips_in_emails:
    password = generate_password_for_pdf(payroll_settings.password_policy, self.employee)
    if not payroll_settings.email_template:
        message += "<br>" + _("Note: Your salary slip is password protected, "
            "the password to unlock the PDF is of the format {0}.").format(payroll_settings.password_policy)
```

(`:2391-2397` — the policy hint is appended only when no custom template exists, i.e. the template author is expected to mention it themselves.) The generator:

```python
def generate_password_for_pdf(policy_template, employee):
    employee = frappe.get_cached_doc("Employee", employee)
    values = {key: format_dates_in_system_format(value) for key, value in employee.as_dict().items()}
    return policy_template.format(**values)     # :2691-2694
```

— the policy string (e.g. `SAL-{first_name}-{date_of_birth.year}`) is `str.format` over every Employee field, with dates wrapped in `SystemFormattedDate` (`:2658-2688`) so `{date_of_birth:%d%m%Y}` renders in the system date format. Bulk email whitelisted at `:2855-2877`. Password policy is mandatory when both email+encrypt are on (`payroll_settings.py:47-50`).

### 3.6 Payroll Settings — every flag

Source: `payroll_settings/payroll_settings.json` + `.py`.

| Flag | Default | Semantics (verified call sites) |
|---|---|---|
| `payroll_based_on` | "Leave" | "Leave" → LOP from approved Leave Applications (`salary_slip.py:602`); "Attendance" → LOP/absent from Attendance records (`:593`) |
| `include_holidays_in_total_working_days` | 0 | Holidays count as working days (higher per-day rate) (`:583-586`, `:782`) |
| `consider_marked_attendance_on_holidays` | 0 | With holidays-included: attendance marked on holidays counts; absences on holidays deduct payment days (`:559-562`, tests `test_salary_slip.py:1089,1126,1179`) |
| `daily_wages_fraction_for_half_day` | 0.5 | Paid share of a half day; LWP share = 1 − fraction (`:564`, `:852`, `:943`) |
| `consider_unmarked_attendance_as` | None ("Present"/"Absent") | Attendance mode only; "Absent" subtracts unmarked days from payment days (`:626-636`) |
| `disable_rounded_total` | 0 | Hides/disables `rounded_total` on slips via property setter (`payroll_settings.py:56-73`) |
| `email_salary_slip_to_employee` | 1 | Auto-email on slip submit (`salary_slip.py:285-290`, `payroll_entry.py:1866`) |
| `encrypt_salary_slips_in_emails` | 0 | PDF password from policy (`:2392-2397`) |
| `password_policy` | None | e.g. `SAL-{first_name}-{date_of_birth.year}` (`:2393`, `:2691-2694`) |
| `email_template` / `sender` / `sender_email` / `sender_copy` | None | Email customization (`:2385-2389`, `:2402`) |
| `max_working_hours_against_timesheet` | None | Alert when timesheet slip hours exceed (`:242-252`) |
| `show_leave_balances_in_salary_slip` | 0 | Adds `leave_details` table (`:2587-2606`) |
| `process_payroll_accounting_entry_based_on_employee` | 0 | Employee-wise payable lines in accrual + bank JEs (`payroll_entry.py:621-624`, `:1096-1098`) |
| `mandatory_benefit_application` | 0 | Flexible benefits sourced only from Employee Benefit Application, not SSA (`salary_slip.py:2612-2643`) |
| `create_overtime_slip` | 0 | Enables overtime-slip step inside Payroll Entry (`payroll_entry.py:1475`) |

(There is no flag for "rounding precision" or "deduction ordering" — those are per-component.)

---

## 4. Integration inputs into payroll

Routing table for implementers — which Frappe mechanism answers which Fenzit need:

| Fenzit need | Frappe mechanism | Section |
|---|---|---|
| LOP from approved leave | Leave-mode day walk over LWP/PPL Leave Applications | §2.2 Branch B |
| LOP from field attendance | Attendance-mode walk + unmarked/half-absent handling | §2.2 Branch A |
| Bonus / one-time payment | Additional Salary (one-off payroll_date) | §4.3 |
| Arrears after a raise | Additional Salary overwrite, or the new Arrear doctype | §4.3, §1.2 |
| Refund of over-deducted LWP | Payroll Correction → Additional Salary | §1.2 |
| Advance recovery in EMIs | Additional Salary deduction + advance-account JE redirect | §4.4 |
| Leave encashment payout | Leave Encashment → Additional Salary or direct GL | §4.6 |
| Statutory gratuity | Gratuity + Gratuity Rule → Additional Salary or GL or F&F | §4.8 |
| Exit settlement | Full & Final Statement netting JE | §4.7 |
| Flexible allowances (phone/fuel) | Benefit Application / Claim / Ledger with 3 payout methods | §1.2, §2.4 |
| Overtime pay | Overtime Slip → Additional Salary | §4.9 |
| External income for tax | Employee Other Income (breakup only, no slip row) | §1.2 |
| Loans | lending app, fully external | §4.10 |
| Expense reimbursements | No salary-slip path; Payment Entry / F&F | §4.5 |

### 4.1 Attendance / leave days → slip

Covered in §2.2. Utility helpers: holiday resolution is cached per holiday-list+range (`get_holidays_for_employee`, `salary_slip.py:786-801`; shared helpers in `hrms/utils/holiday_list.py`); leave-type LWP/PPL map cached (`get_leave_type_map`, `:867-878`); leave-day expansion `get_lwp_or_ppl_for_date_range` (`:2732-2770`); Payroll Entry's own attendance completeness check (`payroll_entry.py:1302-1378`).

### 4.2 Timesheet-based salary

Structure flag `salary_slip_based_on_timesheet` + `salary_component` + `hour_rate` (`salary_structure.json`). Slip path: `get_emp_and_working_day_details` → `get_timesheet_config()` from SSA (`salary_structure_assignment.py:261-277`) → `set_time_sheet()` pulls submitted/billed timesheets in range (`salary_slip.py:454-474`) → `add_timesheet_earning_component` sets `wages_amount = hour_rate × total_working_hours` (`:518-524`) and skips the template row during structure evaluation to avoid double-adding (`:1365-1371`). Whitelisted entry `make_salary_slip_from_timesheet` (`:2773-2805`). When timesheet-based, day proration of the wage row is bypassed except mid-month DOJ/relieving (`:2282-2285`), and totals use `calculate_total_for_salary_slip_based_on_timesheet` (`:2484-2501`).

### 4.3 Additional Salary (arrears, one-time, recurring)

Selection: `get_additional_salaries()` (`additional_salary.py:331-397`) — recurring window or one-off payroll date, `disabled=0`, type match. Application: `add_additional_salary_components` (`salary_slip.py:1718-1774`):
- non-overwrite → row's `default_amount=0`, `additional_amount=<AS amount>` (`:1944-1955`);
- overwrite → replaces the structure row and computes `additional_amount = amount − structure default_amount` (`:1912-1923`, `:1944-1949`), and the merged amount is **not** re-prorated by payment days (`:2279-2281`);
- tax components via AS only work with overwrite (`validate_tax_component_overwrite`, `additional_salary.py:227-249`);
- zero-amount AS with `remove_if_zero_valued` is skipped unless it is a tax component or an overwrite (`salary_slip.py:1725-1738`);
- recurring AS is projected into future months for tax (`get_future_recurring_additional_amount`, `:2257-2266`) and excluded from future taxable earnings when it ends (`get_future_recurring_period`, `:2230-2255`).

### 4.4 Employee Advance recovery

Return is scheduled as a **deduction** Additional Salary with `ref_doctype="Employee Advance"` (created from the advance form, `employee_advance.js:219-229`); amount validated against `paid_amount − claimed_amount − already scheduled` (`validate_employee_advance_return`, `additional_salary.py:261-307`). Engine effects: proration skipped (`salary_slip.py:1972-1976` ref list includes "Employee Advance"); JE credit redirected to the advance account (§3.4a).

### 4.5 Expense Claim paid via salary

No direct Additional Salary path in this HEAD. Expense claims are reimbursed by Payment Entry, against advances (`expense_claim.py:598-655`), or as F&F payables (`full_and_final_statement.py:242-248`, `:404-415`). (Older versions had `pay_via_salary_slip`; only Gratuity/Leave Encashment have such flags today — grep confirms `pay_via_salary_slip` exists only in `gratuity.py`/`test_gratuity.py`.)

### 4.6 Leave Encashment

`LeaveEncashment` (`hr/doctype/leave_encashment/leave_encashment.py`): balance = allocation − carry-forwarded + taken (`set_leave_balance`, `:168-185`); encashable days limited by Leave Type `non_encashable_leaves` and `max_encashable_leaves` (`:125-153`); amount = days × per-day rate (SSA field wins over structure, `:212-237`); on submit either GL entries (`pay_via_payment_entry`) or Additional Salary using the Leave Type's `earning_component` (`:187-201`); payment status flips to Paid on slip submit (`salary_slip.py:295-317`) or F&F settlement (`leave_encashment.py:305-323`).

### 4.7 Full & Final settlement

`FullandFinalStatement` (`hr/doctype/full_and_final_statement/full_and_final_statement.py`): `get_outstanding_statements()` (`:106-119`) bootstraps: withheld salary slips as payables (`:148-170`), the fixed payable component list (Gratuity, Expense Claim, Bonus, Leave Encashment `:242-248`), outstanding Employee Advances as receivables (outstanding = paid − claimed − returned, refreshed on every load `:172-224`), asset recovery (`:121-136`). `create_journal_entry()` (`:293-365`) nets payables (debit) vs receivables (credit) with a balancing line referencing the statement; submission requires all rows settled and assets returned (`:57-104`). Status flips to Paid when the JE is submitted (`update_full_and_final_statement_status`, `:446-455`), which also marks linked Gratuity/Leave Encashment paid (`:367-380`). Amounts per reference resolved by `get_account_and_amount` (`:383-439`). **Who computes it**: this doctype itself aggregates; the individual amounts come from each source doc (Gratuity.amount, Encashment.encashment_amount, slip.net_pay for withheld, advance outstanding).

### 4.8 Gratuity / BFS

`Gratuity` (`payroll/doctype/gratuity/gratuity.py`): experience = (relieving − joining) days minus LWP/absent attendance depending on `payroll_based_on`, divided by `total_working_days_per_year`, rounded per rule (`get_work_experience`, `:178-194`); amount = Σ applicable components' `default_amount` from the **last salary slip** × experience × slab fraction, either "Current Slab" or "Sum of all previous slabs" (`get_gratuity_amount`, `:234-288`). Payment via salary slip (Additional Salary) or direct GL (`:81-146`). India default rule seeded at setup: 15/26 fraction, 5-year minimum (`regional/india/setup.py`, `create_gratuity_rule_for_india`). BFS (banking/flexi settlement) is not a thing in this repo; the flexible-benefit settlement is the Employee Benefit Ledger flow described in §3.4/§2.4.

### 4.9 Overtime (new)

`Overtime Slip` (`hr/doctype/overtime_slip/overtime_slip.py`): aggregates overtime hours from attendance per `Overtime Type`; hourly rate either fixed or `Σ component amounts / payment_days / standard_working_hours` from a preview slip (`_get_applicable_hourly_rate`, `:306-337`); amount = duration × rate × multiplier (`:348-372`); creates Additional Salary on submit (`:195-217`). Wired into Payroll Entry steps Create/Submit (`payroll_entry.py:83-90`, `:1391-1482`).

### 4.10 Loans (separate `lending` app, NOT in this repo)

`salary_slip_loan_utils.py` (`:13-181`): everything is decorated `@if_lending_app_installed`; slip pulls `Loan` rows with `repay_from_salary=1`, computes payable amounts, appends `loans` child rows, and `net_pay` subtracts `total_loan_repayment` (`salary_slip.py:1045-1047`). If lending is absent, all of this is a no-op.

---

## 5. India-specific vs generic

**In this repo (`hrms/regional/`)**:
- `regional/india/setup.py`: custom fields only — `component_type` select on Salary Component (Provident Fund / Additional Provident Fund / Provident Fund Loan / Professional Tax), Employee PAN/IFSC/PF account fields, Company basic/hra/arrear component links, HRA fields on Declaration/Proof, `marginal_relief_limit` on Income Tax Slab; custom roles for Income Tax Deductions report; seeds "Indian Standard Gratuity Rule" (15/26, min 5 years). **No PF/PT/LWF computation code** — the components are computed by ordinary formulas the admin writes (e.g. PF = 12% of Basic) or left to india_compliance.
- `regional/india/utils.py`: HRA exemption (min of actual HRA; rent − 10% basic; 50%/40% of basic for metro/non-metro, `:126-142`), annual/monthly HRA from salary assignments (`:11-76`, `:186-204`), house-rent date validation (`:160-183`), and **marginal relief** (`:207-222`).
- `regional/united_arab_emirates/setup.py`: seeds UAE gratuity rules only.
- Hook wiring: `hrms/hooks.py:316-321` maps the three `@erpnext.allow_regional` stubs in `hr/hr/utils.py:741-759` to the India implementations; `@hrms.allow_regional` hooks `apply_regional_deductions` / `apply_regional_employer_contributions` (`salary_slip.py:1030-1038`) and `apply_regional_ctc_components` (`salary_structure_assignment.py:347-354`) exist so a regional app can inject e.g. PF rows — but this repo ships **no implementation** for them.
- Default India component seed: `regional/india/data/salary_components.json` — 6 components (Basic, HRA, Arrear, Leave Encashment, Provident Fund, Professional Tax) with **no formulas** — amounts are admin-configured.
- Statutory reports in `hrms/payroll/report/`: `income_tax_computation`, `income_tax_deductions`, `salary_register`, `bank_remittance`, `salary_payments_via_ecs`, `salary_payments_based_on_payment_mode`, `employee_ctc_break_up`, `accrued_earnings_report` — generic, not PF/PT/LWF returns.

**NOT in this repo (owned elsewhere)**:
- The `erpnext.allow_regional` surcharge implementation (`income_tax_slab.py:132-136` returns 0) — income-tax surcharge and Indian TDS specifics beyond the above live in regional override apps.
- **india_compliance app** (`github.com/frappe/india_compliance`) owns GST, e-Invoice, e-Way Bill, TDS/TCS returns (24Q/26Q), and advanced Income-tax features. It is a separate app; nothing in this clone imports `india_compliance`. (Per repo boundary; not fetched — no payroll engine code overlaps it.)
- PF/ESI statutory **filing** and PT state schedules are not computed anywhere in this clone; PF is typically expressed as a Salary Structure formula on the "Provident Fund" component (deduction + employer contribution) and reported via the generic Salary Register / provided reports.
- Lending/loan repayment math lives in the separate `lending` app (`salary_slip_loan_utils.py:17-19` checks installation).

---

## 6. Tests as behavioural spec

Most valuable cases pinning engine behaviour (one line each). Paths relative to repo root.

### Salary slip core (`hrms/payroll/doctype/salary_slip/test_salary_slip.py`)
| Test | Line | Behaviour proven |
|---|---|---|
| `test_leave_details` | 62 | `show_leave_balances_in_salary_slip` populates the leave table |
| `test_employee_status_inactive` | 90 | slip blocked for inactive employee |
| `test_payment_days_based_on_attendance` | 119 | Attendance-mode payment days with absent/half days |
| `test_payment_days_considering_half_days_unmarked_as_absent` | 188 | half-days + unmarked-as-Absent subtract from payment_days |
| `test_payment_days_considering_half_days_unmarked_as_present` | 252 | same with unmarked-as-Present |
| `test_payment_days_for_mid_joinee_including_holidays` | 317 | DOJ clip of payment days, holidays included |
| `test_payment_days_for_mid_joinee_including_holidays_and_unmarked_days` | 384 | DOJ clip + unmarked days combined |
| `test_payment_days_for_mid_joinee_excluding_holidays` | 424 | DOJ clip with holidays excluded |
| `test_payment_days_based_on_leave_application` | 459 | Leave-mode LWP math incl. half days and PPL fraction |
| `test_partially_paid_leave_lwp_is_consistent_across_payroll_based_on` | 542 | PPL fraction identical in Leave vs Attendance mode |
| `test_payment_days_calculation_for_lwp_on_month_boundaries` | 570 | LWP spanning month boundaries |
| `test_component_condition_based_on_leave_without_pay` | 599 | `condition` can test `leave_without_pay > 0` (period-only vars) |
| `test_payment_days_in_salary_slip_based_on_timesheet` | 764 | timesheet slips still get DOJ/relieving proration |
| `test_component_amount_dependent_on_another_payment_days_based_component` | 808 | dependent formula (SA = BS × 0.5) prorates exactly once |
| `test_salary_slip_with_holidays_included` / `_excluded` | 855 / 877 | total_working_days ± holidays |
| `test_holidays_resolved_from_holiday_list_assigned_during_slip_period` | 900 | holiday list changes mid-period |
| `test_salary_slip_with_half_day_holiday` … `test_half_day_lwp_on_half_day_holiday` | 936-1088 | matrix of half-day-holiday × leave/absent interactions |
| `test_consider_marked_attendance_on_holidays*` | 1089, 1126, 1179 | attendance marked on holidays |
| `test_payment_days` | 1227 | DOJ/relieving-day formulas (payment_days = month_days − DOJ + 1; = relieving day) |
| `test_employee_salary_slip_read_permission` | 1291 | employee can read own slip only |
| `test_email_salary_slip` | 1305 | email path fires with settings on |
| `test_email_salary_slip_with_email_template` | 1319 | custom template rendering |
| `test_pdf_password_uses_system_date_format` | 1331 | password policy renders dates per system format |
| `test_payroll_frequency` | 1343 | start/end derivation per frequency |
| `test_multi_currency_salary_slip` | 1369 | non-company currency slip |
| `test_year_to_date_computation` / `test_component_wise_year_to_date_computation` | 1389 / 1433 | YTD sums |
| `test_tax_for_payroll_period` | 1483 | full-year simulation: 92,789 annual tax @ 2,36,000 slab; proof submission lowers to 71,989; 150k additional salary → 1,03,189 |
| `test_default_amount` | 1584 | `default_amount` vs prorated `amount` interplay |
| `test_tax_for_recurring_additional_salary` | 1614 | recurring AS projected across remaining months for TDS |
| `test_salary_slip_from_timesheet` | 1678 | wages from submitted timesheets |
| `test_do_not_show_statistical_component_in_slip` / `test_statistical_component_based_on_payment_days` | 1701 / 1715 | statistical components invisible but prorated in context |
| `test_salary_slip_generation_against_opening_entries_in_ssa` | 1756 | mid-year joinee: `taxable_earnings_till_date`/`tax_deducted_till_date` openings |
| `test_income_tax_breakup_fields` | 1857 | breakup docfield values |
| `test_income_tax_breakup_when_tax_added_via_additional_salary` | 1912 | overwritten tax component |
| `test_income_tax_unchanged_on_submit_with_exempted_additional_deduction` | 1970 | exempted deduction idempotency on submit |
| `test_consistent_future_earnings_irrespective_of_payment_days` | 2144 | future months ignore current LOP |
| `test_tax_period_for_mid_month_payroll_period` | 2166 | mid-month period factor |
| `test_variable_tax_with_zero_remaining_sub_periods` | 2190 | division-by-zero guard |
| `test_tax_in_joining_month_when_tax_depends_on_payment_days` / `…relieving_month…` | 2220 / 2252 | payment-days share of TDS in partial months |
| `test_lwp_calculation_based_on_relieving_date` | 2279 | LWP clipped at relieving date |
| `test_zero_value_component` | 2307 | remove_if_zero_valued |
| `test_component_default_amount_against_statistical_component` | 2342 | statistical components usable as default-amount source |
| `test_ctc_in_statistical_component_formula` | 2378 | `ctc` usable in formulas (and survives the overlay drop) |
| `test_variable_tax_component` | 2409 | TDS row creation |
| `test_opening_balances_excluded_from_tax_calculation` | 2468 | openings not double-taxed |
| `test_tax_payable_with_tax_relief_and_marginal_relief_limits` | 2523 | rebate + marginal relief |
| `test_status_on_discard` | 2569 | discard resets status |
| `test_salary_component_for_payment_days_zero` / `…additional_salary_zero` | 2576 / 2643 | zero payment days / zero-amount AS |
| `TestSalarySlipSafeEval.test_safe_eval_for_salary_slip` | 2701 | sandbox: walrus/Lambda blocked, unsafe attrs blocked, doc fields readable |
| `TestSalarySlipEmployerContributions.test_employer_contributions_populated_on_slip` | 3844 | employer contribution rows land in their own table |
| `…test_employer_contributions_excluded_from_totals` | 3855 | excluded from gross/deduction/net |
| `…test_employer_contribution_not_in_taxable_ctc` | 3871 | not part of taxable base |
| `…test_no_additional_salary_leaks_into_employer_contributions` | 3880 | Additional Salary never creates employer-contribution rows |
| `…test_employer_contributions_not_printed` | 3906 | hidden on the printed slip |
| `…test_employer_contributions_reset_on_reload` | 3917 | recomputed cleanly on structure change |

### Payroll entry (`hrms/payroll/doctype/payroll_entry/test_payroll_entry.py`)
| Test | Line | Behaviour |
|---|---|---|
| `test_payroll_entry` | 71 | happy path: select → create → submit → JE |
| `test_multi_currency_payroll_entry` | 86 | multi-currency JE |
| `test_payroll_entry_with_employee_cost_center` | 136 | cost centers resolved end-to-end |
| `test_employee_cost_center_breakup` | 182 | cost-center percentage splits in JE |
| `test_get_end_date` | 232 | frequency → end-date helper |
| `test_get_payroll_entries_for_jv_filters_docstatus` | 242 | JV filter query respects docstatus |
| `test_loan_with_settings_enabled` / `test_loan_with_settings_disabled` | 262 / 310 | lending-app loan rows appear/disappear with settings |
| `test_salary_slip_operation_queueing` | 341 | >30 employees → queued |
| `test_salary_slip_operation_failure` / `test_salary_slip_that_fails_to_submit_stays_draft` | 365 / 425 | failure path: status Failed; failed slip remains Draft |
| `test_payroll_entry_cancellation` / `…with_hr_manager` / `test_payroll_entry_status` / `…against_cancelled_journal_entry` | 461 / 498 / 533 / 553 | slips deleted, JEs cancelled, status transitions |
| `test_payroll_accrual_journal_entry_with_employee_tagging` / `…without_employee_tagging` | 591 / 624 | employee-wise payable lines vs single line |
| `test_advance_deduction_in_accrual_journal_entry` | 655 | advance recovery credits advance account |
| `test_employee_wise_bank_entry_with_cost_centers` | 719 | bank JE per employee |
| `test_validate_attendance` / `…with_holiday_list_assignment` | 785 / 824 | unmarked attendance blocks submission |
| `test_skip_bank_entry_for_employees_with_zero_amount` | 872 | zero-net employees skipped |
| `test_loan_repayment_from_salary` / `…with_employee_tagging` / `test_loan_repayment_value_date_for_future_payroll` | 902 / 909 / 975 | bank entry handles loan repayments; value-date rules |
| `test_component_exclusion_from_accounting_entries` | 1035 | `do_not_include_in_accounts` |
| `test_employer_contribution_journal_entry` / `…with_employee_tagging` / `…jv_balances_with_cost_center_split_rounding` | 1121 / 1189 / 1246 | separate employer JE + rounding split balancing |
| `test_employee_benefits_accruals_in_salary_slip` | 1299 | flexible-benefit accrual ledger flow inside payroll run |
| `test_status_on_discard` | 1447 | discard resets status |
| `test_set_match_conditions_maps_permission_doctype_to_employee_field` | 1465 | user-permission match conditions in employee query |

### Additional Salary (`hrms/payroll/doctype/additional_salary/test_additional_salary.py`)
| Test | Line | Behaviour |
|---|---|---|
| `test_recurring_additional_salary` | 20 | recurring window picked up across cycles |
| `test_disabled_recurring_additional_salary` | 44 | disabled rows ignored |
| `test_non_recurring_additional_salary` | 68 | one-off payroll-date match |
| `test_overwrite_salary_structure_amount` | 112 | overwrite semantics |
| `test_zero_overwrite_sets_structure_amount_to_zero` | 133 | zero overwrite zeroes the row |
| `test_zero_overwrite_removes_zero_valued_component` | 157 | zero overwrite + remove_if_zero_valued drops row |
| `test_zero_overwrite_of_tax_component_is_kept` | 179 | zero overwrite of TDS survives |
| `test_zero_overwrite_of_accrual_component_records_no_payout` | 203 | accrual component overwrite doesn't create payout |
| `test_overwrite_tax_component` | 231 | tax component only via overwrite |
| `test_validate_duplicate_or_overlapping_additional_salary` | 263 | recurring overlap blocked |

### Income Tax Slab (`hrms/payroll/doctype/income_tax_slab/test_income_tax_slab.py`)
| Test | Line | Behaviour |
|---|---|---|
| `test_other_charges_applied_as_flat_rate` | 40 | cess percent of tax |
| `test_other_charges_no_marginal_relief_at_threshold` | 48 | relief boundary |
| `test_other_charges_skipped_outside_income_range` | 70 | cess min/max income gating |
| `test_zero_tax_below_relief_limit` | 91 | rebate short-circuit |
| `test_tax_calculated_above_relief_limit` | 99 | slab walk above rebate |
| `test_cess_computed_on_base_tax` | 107 | cess on base tax |
| `test_surcharge_then_cess_reflected_in_salary_slip_tds` | 116 | surcharge + cess order |

### Salary Structure Assignment (`hrms/payroll/doctype/salary_structure_assignment/test_salary_structure_assignment.py`)
| Test | Line | Behaviour |
|---|---|---|
| `test_ctc_and_annual_gross_exclude_statistical_and_include_employer` | 38 | CTC composition |
| `test_regional_ctc_hook_reaches_ctc_but_not_gross` | 80 | regional hook injects CTC-only components |
| `test_ctc_reset_when_base_missing` | 121 | missing base → CTC cleared |
| `test_get_evaluated_components_does_not_mutate_cached_structure` | 134 | cache safety in batch runs |
| `test_get_evaluated_components_resolves_salary_slip_fields` | 146 | slip numeric fields seeded in full-cycle eval |
| `test_get_evaluated_components_resolves_uncovered_slip_fields` | 184 | unknown slip fields default safely |
| `test_get_evaluated_components_resolves_salary_slip_custom_field` | 228 | custom fields available in formulas |
| `test_get_evaluated_components_uses_declared_field_defaults` | 261 | declared defaults win |
| `test_get_evaluated_components_seeds_posting_date` | 294 | posting-date seeding |
| `test_do_not_include_in_total_earning_is_in_ctc_but_not_gross` | 326 | `do_not_include_in_total` flag semantics |
| `test_ctc_for_timesheet_structure_evaluates_base_driven_components` | 363 | timesheet structures still evaluate base-driven rows |
| `test_get_evaluated_components_excludes_timesheet_wage` | 402 | timesheet wage excluded from full-cycle eval |
| `test_assignment_dated_before_any_fiscal_year` | 440 | full-cycle date seeding fallback |
| `test_employee_currency_ignores_draft_and_cancelled_assignments` | 497 | only submitted SSAs resolve |

### Others
| Test | Line | Behaviour |
|---|---|---|
| `test_salary_withholding.py::test_set_withholding_cycles_and_to_date` | 46 | cycle generation |
| `…test_salary_withholding` / `…test_release_withheld_salaries` | 55 / 69 | withheld cycle → slip Withheld → bank entry release |
| `…test_status_on_discard` | 135 | discard resets status |
| `test_payroll_correction.py::test_payroll_correction` / `…with_zero_payment_days` | 20 / 109 | LWP-day reversal arrears |
| `test_leave_encashment.py::test_leave_balance_value_and_amount` | 63 | encashment amount math |
| `…test_non_encashable_leaves_setting` / `…test_max_encashable_leaves_setting` / `…test_max_encashable_leaves_and_non_encashable_leaves_setting` | 80 / 116 / 151 | Leave Type encashment caps |
| `…test_creation_of_leave_ledger_entry_on_submit` | 187 | leave ledger interaction |
| `…test_unused_leaves_after_leave_encashment_for_carry_forwarding_leave_type` / `…test_leave_expiry_after_leave_encashment_for_non_carry_forwarding_leave_type` | 206 / 234 | balance after encashment per leave type |
| `…test_status_of_leave_encashment_after_payment_via_salary_slip` | 305 | Paid status via slip |
| `…test_status_of_leave_encashment_after_payment_via_payment_entry_and_fnf` | 339 | Paid via payment entry / F&F |
| `…test_status_on_discard` | 410 | discard resets status |
| `…test_leave_encashment_based_on_salary_structure_assignment` | 417 | SSA-level per-day rate wins |
| `test_full_and_final_statement.py::test_check_bootstraped_data_asset_movement_and_jv_creation` / `…test_asset_cost` | 24 / 43 | bootstrap + asset recovery |
| `…test_journal_entry` / `…test_journal_entry_party_for_receivable_and_payable_accounts` | 54 / 69 | netting JE + party handling |
| `…test_employee_advance_settlement` / `…test_employee_advance_added_after_bootstrap` / `…test_employee_advance_row_refreshed_to_current_balance` / `…test_employee_advance_rows_follow_employee_change` | 78 / 109 / 132 / 181 | advance receivable refresh semantics |
| `…test_status_on_discard` | 203 | discard resets status |
| `test_gratuity.py::test_gratuity_based_on_current_slab_via_additional_salary` / `…all_previous_slabs_via_payment_entry` / `…consistent_irrespective_of_payment_days` / `test_settle_gratuity_via_fnf_statement` | 41 / 86 / 174 / 195 | gratuity math + payment modes |
| `…test_status_on_discard` | 243 | discard resets status |

---

## 7. Lean-reimplementation notes (Fenzit-specific judgment — NOT verified fact)

*Everything in §1-6 above is observed code behaviour; this section is opinion about what a 150-user, NestJS + Postgres reimplementation should keep or drop.*

### 7.1 Essential mechanisms to copy (semantics Fenzit likely lacks today)

1. **Two-number per row discipline** (`default_amount` = full-cycle, `amount` = prorated): Frappe's cleanest idea. Storing both makes the tax engine (which needs full-cycle values for future months) and the payslip display trivial. Cheap to implement, huge correctness payoff.
2. **Payment-days fraction as the single proration point**: one function computing `payment_days` and `total_working_days`, then `amount × payment_days / total_working_days` per `depends_on_payment_days` row — instead of Fenzit recomputing per-component LOP. Include the half-day-holiday fraction (0.5) and the DOJ/relieving clip (`actual_start/actual_end`) which are the two most-missed details.
3. **LOP from a single configurable source** (`payroll_based_on` Leave vs Attendance) plus `consider_unmarked_attendance_as`. Fenzit's field-service reality is attendance-heavy, so the Attendance branch is the one to copy: skip paid-leave types, treat Absent as LOP, respect half days, subtract unmarked days when configured.
4. **Annual tax as "slab walk over projected annual taxable income, spread back per period"** (`calculate_variable_tax`): tax = f(previous actual + current actual-for-payment-days + future full-cycle projection + recurring addl projections − exemptions) ÷ remaining sub-periods (with payment-days share), minus tax already deducted. This is what makes mid-year additions/raises self-correcting; simpler "per-month slab" engines drift badly.
5. **Opening balances on the assignment** (`taxable_earnings_till_date`, `tax_deducted_till_date`) for mid-year joinees — trivial fields, avoids an entire class of "joinee under-taxed" bugs.
6. **Tax breakup docfields** stored on the slip (annual taxable, exemptions, deducted-till-date, future, current-month): gives auditors and employees a defensible number without recomputation.
7. **The uniform "Additional Salary" input channel**: one table (employee, component, amount, date(s), recurring flag, overwrite flag, ref link) through which bonus/arrear/encashment/advance-recovery/benefit-claim/overtime all flow. In Postgres this is one `payroll_additional_amount` table with a `source_type`/`source_id`; the slip query is one WHERE clause.
8. **Flexible-benefit accrual ledger** (Accrual/Payout rows per component per period) if Fenzit ever does phone/fuel allowances — otherwise skip §2.4's benefit payout methods entirely.
9. **Idempotency & failure semantics of the run**: unique (employee, period) slip; per-slip savepoint during submission so one bad employee doesn't kill the run; run status Failed + error message retained; queue above ~30 employees. Directly transplantable to a NestJS job queue.
10. **Structure-row validation rules** worth porting as static checks: tax component must not have amount/formula; formula rows must not also be payment-day-dependent if they reference another payment-day component (double-proration); SSA required when structure has a tax component.

### 7.2 Over-engineered for Fenzit's scale (skip or simplify)

| Frappe mechanism | Why it's heavy | Lean equivalent |
|---|---|---|
| String formulas + `_safe_eval` sandbox (`payroll/utils.py:139-158`) | AST denylist sandbox, NameError UX, per-slip re-evaluation, cache invalidation on component save; formulas are admin-authored anyway | Evaluate components in TypeScript: a small set of typed expressions (percent-of, times-factor, slab) or a JSON "rule" per component; drop eval entirely. If expression power is needed, compile once at structure-save time, not per slip |
| SSA-side formula pre-evaluation + slip-side re-evaluation (two evaluation passes, `salary_structure_assignment.py:314-345` + `salary_slip.py:1359-1444`) | Exists to support CTC preview + cross-component refs; complex to reason about | One evaluation pass per slip with a deterministic ordering (earnings in row order → gross → deductions), exactly as §2.1 describes |
| Journal Entry generation (3 JE types, cost-center percentage splits, employee-wise payable, multi-currency, advance-account redirection — `payroll_entry.py:619-1295`) | Depends on full erpnext GL; ~40% of the file | For a SaaS without double-entry books: emit one summarized payroll register + per-employee net-pay table; integrate with the customer's accounting via a simple export. If books are needed later, generate two rows per component (expense Dr, liability Cr) in a `payroll_journal_line` table |
| Multi-currency payroll (`exchange_rate`, base_* columns, account-currency checks) | Fenzit is INR-only | Single currency; delete exchange-rate plumbing |
| `Employer Contribution` as a third parentfield with its own JE | Only needed to *display* CTC splits + accrue PF liability | Model employer PF as a `statistical` calculation on the employee (computed report), no slip table |
| Payroll frequency matrix (Daily/Weekly/Fortnightly/Bimonthly/Monthly + fiscal-year month math `payroll_entry.py:1631-1714`) | Fenzit is monthly | Hardcode monthly; keep `get_start_end_dates` = calendar month |
| Full flexible-benefit engine (3 payout methods, ledger, claims, mandatory-application setting) | Large surface (Benefit Application/Claim/Ledger + slip integration) | Defer; if needed later start with "claim-based, accrue per cycle" only |
| Withholding cycles + withheld bank-entry flow (`salary_withholding.py`) | Niche exit-hold scenario | Simple `status='withheld'` on the slip + manual release button |
| Lending-app loan integration | Separate app | If Fenzit does advances, the Employee-Advance-recovery pattern (§4.4) suffices |
| Payroll Correction + Arrear doctypes (new, overlapping) | Two parallel mechanisms for LWP reversal/arrears | One `payroll_lwp_reversal` concept; compute arrears as additional-amount rows |
| Holiday-list caching layer (`HOLIDAYS_BETWEEN_DATES`, `LEAVE_TYPE_MAP`, `TAX_COMPONENTS_BY_COMPANY` caches) | Redis-correctness burden for 150 users | Postgres can serve this read volume raw; add a memoized per-run load |

### 7.3 Minimal data model preserving the semantics (sketch)

```
salary_component(id, name, code, type: earning|deduction, flags: {
  depends_on_payment_days, statistical, do_not_include_in_total,
  is_tax_applicable, exempted_from_income_tax, variable_based_on_taxable_salary,
  round_to_int, remove_if_zero, accrual?}, rule_json)     -- rule replaces condition/formula strings

salary_structure(id, name, frequency='Monthly', currency='INR')
salary_structure_row(structure_id, component_id, idx, rule_json, amount, flags-copied)

salary_structure_assignment(id, employee_id, structure_id, from_date, base,
  income_tax_slab_id, taxable_earnings_till_date, tax_deducted_till_date,
  leave_encashment_amount_per_day)                        -- unique(employee_id, from_date)

additional_amount(id, employee_id, component_id, amount, payroll_date,
  from_date, to_date, is_recurring, overwrite, source_type, source_id, disabled)

payroll_period(id, company_id, start_date, end_date)
income_tax_slab(id, currency, effective_from, standard_exemption, tax_relief_limit,
  marginal_relief_limit, allow_exemption)
income_tax_slab_row(slab_id, from_amount, to_amount, percent, condition)
tax_exemption_declaration(employee_id, period_id, total_exemption_amount, status)

payroll_run(id, company_id, start_date, end_date, status: draft|queued|submitted|failed,
  payable_account?, error_message?)
payslip(id, run_id, employee_id, start_date, end_date, total_working_days,
  payment_days, leave_without_pay, absent_days, gross, deductions, net, rounded_net,
  status: draft|submitted|cancelled|withheld, tax_breakup_json, UNIQUE(employee_id, start_date, end_date))
payslip_line(payslip_id, component_id, default_amount, amount, additional_amount, ytd)
payroll_additional_ledger  -- optional, only if flexible benefits/arrears tracking is wanted
```

### 7.4 Minimal pipeline (per employee per month)

1. Resolve SSA effective at month start (latest `from_date <= start`).
2. `total_working_days` = calendar days − holidays (per holiday list) [− 0.5 per half-day holiday].
3. `payment_days` = clipped-window days − holidays (same rule) − LWP (leave app or attendance per setting) − absent − unmarked-as-absent (floor 0; if LWP ≥ window → 0).
4. Evaluate earning rows in order against `{base, abbrs→0, employee, slip: {payment_days, total_working_days, ...}}`; then `gross = Σ`; then deduction rows; then exempted deductions reduce taxable.
5. Prorate every flagged row: `default_amount × payment_days / total_working_days` (+ additional_amount rows per §4.3 semantics, overwrite wins, no re-proration of overwritten rows).
6. Tax: `prev_taxable (from submitted slips + openings)`, `current = taxable for payment_days`, `future = full-cycle taxable × (remaining months − 1)`, `+ recurring addl projection`, `− exemptions (+ standard deduction)`; slab walk (inclusive ends, relief limit, marginal relief, cess %); `month_tax = (annual_tax − paid_so_far) / (remaining + payment_days_share − 1) × payment_days_share`; floor 0; add `full_tax_on_additional` for full-tax-flagged extras.
7. `net = gross − deductions − (loan/advance rows)`; round; enforce net ≥ 0.
8. Persist YTD sums as columns maintained at submit time (avoid recomputation).

### 7.5 Complexity hotspots to avoid (and the simpler equivalent)

- **Sandboxed formula eval** → typed rules (§7.2 row 1). Biggest single de-risking.
- **JE generation + cost-center splits** → payroll register export (§7.2 row 3).
- **The remaining_sub_periods / get_period_factor dance** (`payroll_period.py:115-153`, month-diff with day rules) → for monthly-only, `remaining = months between month_end and period_end` computed with a simple month arithmetic helper; pin it with a table-driven test (copy `test_tax_for_payroll_period`, `test_salary_slip.py:1483`).
- **Holiday-list assignment chains** (Employee → Department → Company, ranges, half-day holidays) → one holiday table + employee mapping; still implement half-day holidays, they materially change LOP.
- **Benefit payout methods** → defer (§7.2 row 6).

### 7.6 Behaviours to copy verbatim into acceptance tests (from §6)

The eight highest-value: (1) mid-joinee payment days (`test_payment_days`, :1227); (2) half-day holiday × leave/absent matrix (:936-1088); (3) PPL fraction consistency (:542); (4) dependent-component single proration (:808); (5) future months ignore current LOP in tax (:2144); (6) full-year TDS self-correction with declarations/proofs/additional salary (:1483); (7) recurring additional salary tax projection (:1614); (8) unmarked-attendance-as-absent (:188/252).

---

## 8. Gotchas — subtle verified behaviours a reimplementation must decide on deliberately

| # | Gotcha | Consequence | Citation |
|---|---|---|---|
| 1 | Slab endpoints are **inclusive on both sides** (`+1` in the tax base). Slab tables must be authored as `0–400000`, `400001–800000`, `800001–…`; authoring `400000–800000` / `800000–…` double-counts the boundary rupee. | One-rupee-per-slab tax drift, worst for high earners crossing many slabs | `income_tax_slab.py:80-85` |
| 2 | `total_working_days` spans the **whole period** while `payment_days` subtracts holidays only in the DOJ/relieving-clipped window. | A mid-joinee gets a *higher* paid fraction if holidays fall in their non-employed days (numerator keeps more holidays than denominator removes) | `salary_slip.py:566-586` vs `:774-782` |
| 3 | The Payroll Entry attendance gate ignores `consider_unmarked_attendance_as`: it blocks submission whenever `payroll_days − holidays − attendance_count > 0`, even if the slip math would have paid those days. It also counts holidays at full weight (no half-day-holiday fraction), unlike slip math. | Run cannot be submitted despite slips that would compute correctly; the gate and the engine disagree | `payroll_entry.py:1331`, `:1366` |
| 4 | A manually-set non-zero `leave_without_pay` that disagrees with computed LWP is only a `msgprint` warning — the manual value **wins** (`if not lwp: lwp = actual_lwp`, so a manual 0 falls back to the computed value). | Silent under/over-deduction if upstream passes a wrong value | `salary_slip.py:606-615` |
| 5 | `payment_days` floors at 0 when LWP ≥ window (`else: self.payment_days = 0`), never negative; Payroll Correction can push it back up afterwards. | Full-month-absent employees get ₹0 earnings but still may owe deduction components that aren't payment-day-dependent | `salary_slip.py:620-648` |
| 6 | Additional Salary rows that **overwrite** structure amounts are exempt from payment-day proration. | A full overwrite pays the full amount even in an LOP month (intended for arrears/one-offs, surprising for "overwrite Basic") | `salary_slip.py:2279-2281` |
| 7 | Proration is skipped for Additional Salary rows referencing Employee Advance / Arrear / Payroll Correction / Employee Benefit Claim. | Recovery amounts and corrections are exact-amount, never pro-rated | `salary_slip.py:1972-1977` |
| 8 | The TDS row is **appended last** by design (`add_tax_components` runs after structure + additional components). | Any pipeline reordering that computes tax before exempted deductions exist will over-tax | `salary_slip.py:1323-1341` |
| 9 | Future-period tax preview re-runs a **copy of the slip** with `payment_days = total_working_days` and `skip_tax_breakup_computation=True` (results × `ceil(remaining_sub_periods) − 1`); the separate `for_preview` flag (structure preview) short-circuits working-days math to full days. | Preview recursion must be guarded or it recomputes the world; the copy must not persist | `salary_slip.py:1215-1226`, `:567-570`, `:2435-2440` |
| 10 | The slip context deliberately **drops its own `ctc`** so formulas see the Employee/SSA value. | Shadowing `ctc` in a slip context silently changes formula results | `salary_slip.py:1452-1459` |
| 11 | Email recipient is `Employee.prefered_email` (typo field name in the schema). | Misspelling breaks lookups in a reimplementation that copies field names | `salary_slip.py:2379-2418` |
| 12 | Email is sent at slip level **or** run level, never both: `frappe.flags.via_payroll_entry` suppresses the slip-level path. | Duplicated payslip emails if the flag isn't propagated through a job queue | `salary_slip.py:285-290`, `payroll_entry.py:1864-1866` |
| 13 | Negative net pay: slip `on_submit` throws (`:277-278`) but the run **skips** such slips first (`:1846-1848`) and continues; the slip stays Draft with no error surfaced to the run. | Run reports success while one employee silently got no payslip | `payroll_entry.py:1846-1848`, `salary_slip.py:277-278` |
| 14 | Duplicate-slip checks have two scopes: pre-submit validation matches any slip for [start,end] for the entry's employees (`:123-152`); inside the creation job, the skip-check scopes by `payroll_entry` (`:1819-1834`). | A manually-created slip blocks the run at submit time, but two runs on overlapping windows only collide on exact [start,end] | `payroll_entry.py:123-152`, `:1615-1628`, `:1819-1834` |
| 15 | Cost-center percentage splits carry a rounding remainder booked on the **last** cost center. | Independent rounding per split line drifts the JE by paise; copy the remainder-on-last-line trick | `payroll_entry.py:722-736` |
| 16 | Gratuity base uses the **last slip's `default_amount`** (full-cycle, un-prorated) — deliberately payment-day independent. | An employee in an LOP month still gets full-CTC gratuity basis (pinned by test) | `gratuity.py:234-288`, `test_gratuity.py:174` |
| 17 | In the payroll period's **last cycle**, `deduct_tax_for_unsubmitted_tax_exemption_proof` is forced on — the year-end declaration is ignored and only submitted proofs count. | Employees without proofs get a large final-month TDS spike; expected Indian behaviour, must be decided explicitly | `salary_slip.py:1068-1069` |
| 18 | Cess (`other_taxes_and_charges`) is applied to the tax amount **after** the (regional) surcharge hook mutated it, inside the same chain. | With a surcharge app installed, cess compounds on surcharge; without one, it's a flat % of base tax | `income_tax_slab.py:58-68`, `:89-101` |
| 19 | `tax_relief_limit` short-circuits to zero tax before slabs are walked (rebate), and marginal relief then caps tax at `income − marginal_relief_limit` for the band above. | Both must be implemented together or low-income taxpayers get an inverted cliff | `income_tax_slab.py:51-52`, `regional/india/utils.py:207-222` |
| 20 | Zero remaining sub-periods guards the tax spread (`remaining == 0 → tax 0`) — the last slip of the last period would divide by zero otherwise. | Classic division-by-zero on a 12th-slip edge | `salary_slip.py:2042-2043`, `test_salary_slip.py:2190` |
| 21 | `validate_attendance`'s unmarked-day count uses **submitted** attendance only (docstatus 1) and the *full* entry window in the SQL join, while the subtraction window is DOJ/relieving-clipped. | Draft attendance passes the gate but still causes LOP/absents in slip math | `payroll_entry.py:1331`, `:1364-1368` |
| 22 | Component `accrual_component` is Earning-only and must pair with a claim-compatible `payout_method` — validated, not enforced by schema. | Misconfigured flexible benefits throw only at save time | `salary_component.py:109-136` |
| 23 | Employer-contribution JEs require **both** an expense account and a liability account on Salary Component Account; the accrual JE ignores employer contributions entirely (separate JE). | Booking employer PF in the accrual JE is impossible without code changes — by design | `payroll_entry.py:792-815`, `:619-701` |
| 24 | F&F netting JE performs no debit/credit balance validation; correctness rests on the payables/receivables refresh logic. | A stale advance balance produces an unbalanced JE rather than an error | `full_and_final_statement.py:293-365` |

**Not verifiable from this clone** (framework or separate-app internals, described only from call sites): exact `frappe.safe_eval` semantics (used only for tax-slab conditions), `frappe.utils.rounded` rounding mode, `money_in_words`, the `lending` app's loan-demand computation, and everything inside `india_compliance` (§5).

---

## Appendix A — function quick reference (engine)

| Concern | Function | Location |
|---|---|---|
| Period dates | `get_start_end_dates`, `get_month_details` | `payroll_entry.py:1631-1661`, `:1689-1714` |
| Period factor | `get_period_factor` | `payroll_period.py:115-153` |
| Holiday resolution | `get_holidays_for_employee`, `get_half_day_holidays_for_employee` | `salary_slip.py:786-821` |
| LWP (leave mode) | `calculate_lwp_or_ppl_based_on_leave_application` | `salary_slip.py:823-865` |
| LWP (attendance mode) | `calculate_lwp_ppl_and_absent_days_based_on_attendance` | `salary_slip.py:901-959` |
| Payment days | `get_payment_days`, `get_unmarked_days`, `get_half_absent_days` | `salary_slip.py:760-784`, `:650-686` |
| Proration | `get_amount_based_on_payment_days` | `salary_slip.py:2268-2318` |
| Eval context | `get_component_eval_context`, `_safe_eval`, `_check_attributes` | `payroll/utils.py:99-158` |
| Structure eval | `get_evaluated_components`, `_evaluate_all_components`, `_evaluate_component_table` | `salary_structure_assignment.py:240-259`, `:314-345`, `:438-502` |
| Slip eval | `add_structure_components`, `eval_condition_and_formula`, `get_data_for_eval` | `salary_slip.py:1359-1444`, `:1471-1505`, `:1446-1469` |
| Additional salary | `get_additional_salaries`, `add_additional_salary_components` | `additional_salary.py:331-397`, `salary_slip.py:1718-1774` |
| Flexible benefits | `add_employee_benefits`, `get_current_period_employee_benefit_amounts`, `_get_final_period_benefit_payout`, `_get_claim_based_benefit_payout` | `salary_slip.py:1507-1716` |
| Tax base | `compute_taxable_earnings_for_year`, `compute_current_and_future_taxable_earnings`, `get_taxable_earnings` | `salary_slip.py:1057-1094`, `:1096-1128`, `:2177-2228` |
| Tax calc | `calculate_variable_based_on_taxable_salary`, `calculate_variable_tax`, `calculate_tax_by_tax_slab`, `calculate_base_tax_from_tax_slabs`, `calculate_other_charges` | `salary_slip.py:1995-2072`, `income_tax_slab.py:47-101` |
| Exemptions | `get_total_exemption_amount`, `compute_annual_deductions_before_tax_calculation` | `salary_slip.py:2320-2345`, `:1257-1286` |
| Breakup | `compute_income_tax_breakup`, `compute_ctc`, `compute_non_taxable_earnings` | `salary_slip.py:1130-1213` |
| Run | `create_salary_slips_for_employees`, `submit_salary_slips_for_employees` | `payroll_entry.py:1738-1791`, `:1837-1881` |
| JEs | `make_accrual_jv_entry`, `make_employer_contribution_jv_entry`, `make_bank_entry` | `payroll_entry.py:619-701`, `:703-790`, `:1092-1136` |
| Email | `email_salary_slip`, `generate_password_for_pdf` | `salary_slip.py:2379-2418`, `:2691-2694` |

## Appendix B — Salary Slip docfields (complete, from the type block at `salary_slip.py:92-160`)

| Group | Fields |
|---|---|
| Identity / scope | `employee`, `employee_name`, `company`, `branch`, `department`, `designation`, `posting_date`, `start_date`, `end_date`, `payroll_frequency` ("", Monthly, Fortnightly, Bimonthly, Weekly, Daily), `payroll_entry` (link), `journal_entry` (link), `salary_structure`, `salary_withholding` + `salary_withholding_cycle`, `status` (Draft/Submitted/Cancelled/Withheld), `current_payroll_period`, `amended_from`, `letter_head` |
| Attendance | `total_working_days`, `payment_days`, `leave_without_pay`, `absent_days`, `unmarked_days`, `total_working_hours`, `hour_rate` + `base_hour_rate`, `salary_slip_based_on_timesheet` |
| Totals | `gross_pay`, `total_deduction`, `total_earnings`, `net_pay`, `rounded_total`, `total_in_words`, `year_to_date`, `month_to_date`, `gross_year_to_date`, and the `base_` mirror of each (`base_gross_pay`, `base_net_pay`, `base_rounded_total`, `base_total_deduction`, `base_total_in_words`, `base_year_to_date`, `base_month_to_date`, `base_gross_year_to_date`) |
| Tables | `earnings`, `deductions`, `employer_contributions` (Salary Detail); `timesheets` (Salary Slip Timesheet); `leave_details` (Salary Slip Leave); `accrued_benefits` (Employee Benefit Detail) |
| Tax breakup | `annual_taxable_amount`, `non_taxable_earnings`, `standard_tax_exemption_amount`, `tax_exemption_declaration`, `deductions_before_tax_calculation`, `income_from_other_sources`, `ctc`, `total_income_tax`, `current_month_income_tax`, `future_income_tax_deductions`, `income_tax_deducted_till_date`, `deduct_tax_for_unsubmitted_tax_exemption_proof` |
| Bank / payout | `bank_name`, `bank_account_no`, `mode_of_payment` (literal `None` in this version — payout mode not wired), `currency`, `exchange_rate` |

Notes: `total_earnings` is **not** a totals-side sum — it belongs to the tax breakup: `total_earnings = ctc + income_from_other_sources` (`salary_slip.py:1144`) and `annual_taxable_amount = total_earnings − (standard exemption + declared exemptions + before-tax deductions)` (`:1157`). Gross/deduction/net come solely from `get_component_totals`, which skips `do_not_include_in_total` rows, with gross re-derived through the payment-day proration (`set_gross_pay_and_base_gross_pay`, `:986-990`; `get_component_totals`, `:2362-2377`). `mode_of_payment` being a dead literal confirms bank-file/payroll-mode integration is not part of the engine core (the `salary_payments_based_on_payment_mode` report reads Employee records directly); `unmarked_days` is a first-class slip field, so Fenzit's equivalent should surface it for debugging.

## Appendix C — flags copied from component to evaluated rows (`SALARY_COMPONENT_FLAGS`)

Exactly which flags the SSA evaluation copies onto each row handed to the slip (`salary_structure_assignment.py:21-37`) — i.e. the persistence set a reimplementation needs per payslip line:

```python
SALARY_COMPONENT_FLAGS = (
    "salary_component", "abbr", "amount_based_on_formula",
    "statistical_component", "accrual_component",
    "depends_on_payment_days", "do_not_include_in_total", "do_not_include_in_accounts",
    "is_tax_applicable", "is_flexible_benefit", "variable_based_on_taxable_salary",
    "exempted_from_income_tax", "deduct_full_tax_on_selected_payroll_date",
)
```

Flags NOT copied to evaluated rows and read from the component master instead: `remove_if_zero_valued`, `round_to_the_nearest_integer`, `arrear_component`, `is_income_tax_component`, `type`, `max_benefit_amount`, `payout_method`, `disabled`. The slip resolves them via cached master lookups (`SALARY_COMPONENT_VALUES` / `TAX_COMPONENTS_BY_COMPANY`, `salary_slip.py:69-72`), so a change to those flags invalidates the component cache (`salary_component.py:78-86`) while flag changes on copied fields only affect newly evaluated rows.

`amount`/`default_amount`/`additional_amount`/`condition`/`formula` are also carried per row (Salary Detail child schema, §1.1), but the eval engine always recomputes them per slip.

## Appendix D — evaluation walkthrough (illustrative)

Structure rows, all Monthly: `BS` = static 40000, `depends_on_payment_days`; `HRA` = formula `BS * 0.4`, `depends_on_payment_days`; `PT` (deduction) = static 200, condition `payment_days > 0`; `TDS` = `variable_based_on_taxable_salary`. SSA `base = 40000`. Month: 30 days, 1 holiday excluded, 2 LWP → `total_working_days = 29`, `payment_days = 27`.

1. SSA pre-evaluation (`_evaluate_all_components`, full-cycle context, `for_preview`-style full dates): BS → 40000 (data + default_data), HRA → 16000, PT → 200, TDS row reserved with no amount. `gross_pay` seeded = 56000 (BS+HRA).
2. Slip eval: context = `{abbrs→0, slip numerics→0, base:40000, employee fields, slip overlay: payment_days:27, total_working_days:29}`.
3. BS: `depends_on_payment_days` → `get_amount_based_on_payment_days`: `default_amount 40000 × 27/29 = 37241.38` → `amount`, `default_data[BS] = 40000`, `data[BS] = 37241.38`.
4. HRA: formula evaluates against `data[BS]` → `37241.38 × 0.4 = 14896.55`; full-cycle value `16000` kept in `default_data[HRA]`. Single proration — the dependent row never re-prorates.
5. PT: condition `payment_days > 0` true → amount 200 (static amounts are not prorated unless the component also carries `depends_on_payment_days`).
6. gross_pay = Σ earnings through `get_component_totals(earnings, depends_on_payment_days=1)` = 52137.93.
7. TDS: computed in `calculate_variable_tax` from the annual projection; its own row amount = the payment-days share of the spread (§2.5).
8. net = gross − deductions; `rounded_total = rounded(net)`.

Illustrative only — numbers follow mechanically from the quoted formulas (§2.2, §2.3, §2.5), not from a source test.

*End of report. ~references verified against clone HEAD ea4158c4.*
