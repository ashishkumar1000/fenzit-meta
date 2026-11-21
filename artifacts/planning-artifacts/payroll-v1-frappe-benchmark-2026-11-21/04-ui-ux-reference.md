# Frappe HR — Payroll UI/UX Reference (for Fenzit web + mobile)

**Research pass:** direct browser + image review, 2026-11-21 (overnight run).
**Evidence:** 22 official product screenshots downloaded from frappe.io feature pages into `ui-shots/` (same folder as this file), plus source-level reading of the ESS frontend in the hrms clone (`workspace/external/frappe-hrms/frontend/`, HEAD `ea4158c4`).

> **Honesty note on evidence quality:** Frappe publishes **no public demo site with credentials** (verified 2026-11-21: frappe.io/hr only offers a Frappe Cloud trial signup; no demo login is published). So this pass is based on **official product screenshots from frappe.io** (marketing pages, mostly updated through 2024–2026) and on **reading the actual Vue ESS frontend code** in the repo — not on driving a live instance. A third-party interactive demo exists (mith.tech/demos/frappe-hr) but was not verified by this run. Screenshots are the real product UI, but some may lag the newest version (except the India Payroll set, which is dated 2026-07).

---

## 1. How Frappe's UI is organised (two distinct surfaces)

| Surface | Tech | Who | What it contains |
|---|---|---|---|
| **Desk (admin)** | Frappe Framework "desk" — metadata-driven forms + query reports | HR/Payroll admin | Everything: setup, runs, reports, approvals |
| **ESS frontend (employee)** | Dedicated Vue/frappe-ui SPA (`frontend/` in hrms repo) + native mobile shells | Employee | Home, Leaves, Expenses (claims + advances), Salary (payslips), Notifications, Profile |

Fenzit maps cleanly onto this split: our **web console = desk**, our **fenzit-app = ESS**. The important structural takeaway: **employees never see payroll configuration — only payslips and their own submissions** (verified in `frontend/src/views/` — only attendance, leave, employee_advance, expense_claim, salary_slip, notifications, profile, home; no structure/component/tax screens).

---

## 2. Admin desk UX — payroll screens (with screenshot refs)

### 2.1 Salary Structure editor — `ui-shots/payroll-salary-structure.webp`
- Standard form with **tabs: Details / Earnings & Deductions / Account**.
- Two stacked child tables: **Earnings** and **Deductions**, each row exposing the full calculation contract as inline columns: Component, Abbr, Amount, **Depends on Payment Days** (checkbox), **Is Tax Applicable**, **Amount based on formula**, **Formula** (e.g. `base * 0.4`, `B / 2`).
- The formula/condition editor is a small code box with **autocomplete over bound variables** — the completion list literally teaches the user the evaluation context: `gender` (Employee field), `getaddr`, Salary Structure Assignment fields, Employee fields, Salary Slip fields (`target_working_hours`…). Condition example shown: `gender == "Female"`; formula `base * 0.4`.
- Month-conditional logic is expressed **in the formula itself**, e.g. Professional Tax: `300 if getdate(start_date).month ...` — no separate state-slab engine needed for simple cases.
- Top-right **Create menu** on a structure: *Single Assignment, Bulk Assignments, Income Tax Slab* — the next step of the flow is one click away.

**Fenzit relevance:** our StructureEditor already has components + formulas, but Frappe's per-row *flag columns* (payment-days dependency, taxability) are the cleanest mental model for admins. Their formula-editor autocomplete (showing exactly which variables exist) is the single best UX idea here.

### 2.2 Payslip preview — `ui-shots/payroll-preview-slips.webp`
- A print-format preview card: employee id/name/company | start/end dates, **Working Days / Payment Days**, earnings table, deductions table, **Gross Pay / Total Deduction / Net Pay**.
- Preview is shown *as part of the run flow* ("Preview slips" before processing) — i.e. the admin sees a rendered payslip **before** committing.

**Fenzit relevance:** we have no pre-run payslip preview. "Preview before commit" is a cheap, high-trust feature for our run flow.

### 2.3 Off-cycle / one-time pay (Additional Salary) — `ui-shots/payroll-off-cycle.webp`
- Form: Employee, Company, **Is Recurring** checkbox, **Payroll Date** with helper text ("the date on which this Salary Component with Amount will contribute for Earnings/Deduction in Salary Slip"), Salary section: Salary Component (e.g. Performance Bonus), Component Type (Earning), Currency, Amount.
- Two expert checkboxes: **Deduct Full Tax on Selected Payroll Date** and **Overwrite Salary Structure Amount**.
- An **Earnings overlay** shows the resulting slip after adding the bonus (Basic 40k, HRA 20k, SA 40k, Performance Bonus 1L).

**Fenzit relevance:** our off-cycle lines exist (API) but have no UI (verified in current-state audit). This screen is the reference for building that UI: amount + payroll-date + two tax/overwrite flags, with live impact preview.

### 2.4 Salary Slip form — `ui-shots/tax-breakup.webp`
- Tabs: **Details / Payment Days / Earnings & Deductions / Net Pay Info / Income Tax Breakup / Bank Details / Leaves**.
- **Income Tax Breakup** tab exposes the entire projection model as read-only fields: CTC, Total Earnings, Non Taxable Earnings, Income from Other Sources, Standard Tax Exemption Amount, Tax Exemption Declaration, Deductions before tax calculation, Annual Taxable Amount, **Income Tax Deducted Till Date, Current Month Income Tax, Future Income Tax, Total Income Tax**.

**Fenzit relevance:** our payslip is a snapshot PDF. Frappe's slip is a full document with an auditable tax projection embedded. At minimum, a "current/future tax" pair on the slip answers the most common employee question ("why was TDS so high?").

### 2.5 India Payroll module (new, 2026-07) — `ui-shots/india-payroll-1..5`
- A dedicated **module** in the sidebar (visible in the module launcher: Expenses, HR Setup, Leaves, Payroll, Performance, Recruitment, Shift & Attendance, Tax & Benefits, Tenure, **India Payroll**).
- Module home: **Tax Regime Selector**, **Reports** group → *Bank Mandate Report, Employee Provident Fund Register, ESIC Register, LWF Register*, and **Settings**.
- **EPF Register** (`india-payroll-5.png`): query-report table, per-employee columns: Universal Account No. (UAN), Name as per UAN, Gross Wages, **PF Wages, Pension Scheme Wages (EPS), Deposit Linked Insurance (EDLI), Employee PF, Voluntary PF (VPF), Employer Pension, Employer PF** + footer totals + **Download ECR Text File** button.
- **ESIC Register** (`india-payroll-3.png`): filters Company/Year/Month/Contribution Period/Coverage Status; columns Gross Wages, Employee Contribution, Employer Contribution, Total; **Coverage Status badges (Covered / PwD / Exempt)**; **Export for ESIC Portal**.
- **LWF Register** (`india-payroll-2.png`): filters Company/Year/Month/Work State/Deduction Status; columns Work State, **LWF Frequency (Monthly / Half-Yearly / Annual)**, Employee LWF, Employer LWF, Total; **status badges: Deducted / Non-Deduction Month / Exempted / No LWF State**; **Export for LWF Remittance**.

**Fenzit relevance:** this is the exact shape of what our audit flagged as absent (PF EPS/EDLI split, ECR, ESI, PT, LWF). Note the pattern Frappe chose: **statutory work surfaces as per-month registers with per-employee status badges + one-click portal export**, not as hidden deduction lines. If we add statutory breadth later, this is the UX template. Note also these live in a **separate module** — statutory breadth does not clutter the core payroll screens.

### 2.6 Tax declarations — `ui-shots/tax-declaration.webp`
- Employee Tax Exemption Declaration: child table of **Exemption Sub Category → Category (80C/80CCC, 80D…) → Maximum Exempted Amount (caps pre-filled: 1.5L, 75k) → Declared Amount**.
- Dedicated **HRA Exemption** section: Monthly House Rent, **Rented in Metro City** checkbox, HRA as per Salary Structure, computed Monthly/Annual HRA Exemption.
- Sub-category picker with caps (Medical Expenditure 80DDB 75k, NSC, Tax saving FD, ULIP, Home Loan Principal).
- Matching **Proof Submission** doctype follows the same categories (docs agent verifying).

**Fenzit relevance:** old-regime support needs exactly this declaration+proof pair. V1 verdict depends on whether our customers are all new-regime (audit says our TDS is new-regime-only).

---

## 3. Employee ESS / mobile UX (reference for fenzit-app)

Screenshots: `mobile-salary.webp`, `mobile-request-panel.webp`, plus `mobile-leaves-holidays.webp`, `mobile-expenses-advances.webp`, `mobile-notifications.webp`, `mobile-employee-profile.webp`.

### 3.1 Salary tab — the payslip experience
- **List screen:** hero card **"Year To Date ₹2,71,096"** with an **FY selector** (Apr 2023 – Mar 2024 dropdown), then month rows: icon, "Nov 2023", sub-line "Gross Pay ₹75,400 ·", right-aligned **net ₹71,725**, chevron. Bottom tab bar: **Home / Leaves / Expenses / Salary**.
- **Detail screen:** segmented tabs **Details / Earnings & Deductions / Net Pay Info**; group headers with right-aligned totals (Earnings ₹75,400; Deductions ₹3,675); line items only (Basic, HRA, SA, PF, Income Tax); **Totals** section with Gross Pay and **Gross Year To Date**; full-width sticky **Download PDF** button pinned at the bottom.
- YTD data comes from the **last salary slip's `year_to_date` field** (verified in `frontend/src/views/salary_slip/Dashboard.vue`); PDF via `hrms.api._download_pdf` (`Detail.vue:136`).

### 3.2 Home / approvals UX
- Quick actions: **Claim an Expense / Request an Advance / View Salary Slips**.
- **My Requests vs Team Requests** segmented control — the same list screen serves employee and manager.
- Request rows: type icon, title, date+duration, **status chip (Open/Draft)**, requester avatar.
- Detail opens as a **bottom sheet** with explicit **Reject (red) / Approve (green)** footer buttons; leave application sheet offers Reject / Review / Approve / Dismiss.
- Payroll-related approvals surfaced on mobile: expense claims, advances, leaves — *not* payroll runs (those are desk-only).

### 3.3 Pattern ideas worth stealing for Sally (fenzit-app)
1. **YTD hero card with FY selector** on our Payslips screen — one glance answers "how much have I earned this FY", and FY is the natural grouping for Indian users (Apr–Mar). We already store per-month slips; YTD = sum.
2. **Month rows with gross + net both visible** (we currently show net only — verify in PayslipsScreen) — gross-vs-net on the row preempts "why is this less?" questions.
3. **Grouped totals in detail** (Earnings header carries its own total, same for Deductions) — cheap to render, big readability win over a flat list.
4. **Sticky Download PDF** as the single primary action.
5. **Status chips + My/Team toggle** — when we add manager approvals on mobile, this is the proven shape.
6. **Never expose config on mobile** — Frappe keeps all payroll config on desk; employee surface is read-only money statements + their own requests. Matches our current split; keep it as a rule.

---

## 4. What Frappe's UI does that our console does NOT (UI-specific gaps, verified against our current-state audit)

| # | Frappe UI affordance | Fenzit today | Value |
|---|---|---|---|
| 1 | Pre-run **payslip preview** before processing | Absent | Trust + error catch before commit |
| 2 | **Formula editor with variable autocomplete** | Formula AST editor exists; no bound-variable autocomplete | Cuts admin mistakes; teaches the contract |
| 3 | Per-component flag columns in structure grid (taxable, payment-days) | Present in API; UI shows editable fields (verify exact rendering) | Cleaner mental model |
| 4 | **Income Tax Breakup** on the slip (till-date / current / future) | Absent (TDS line only) | Answers the #1 employee question |
| 5 | **Statutory registers + portal exports** (EPF/ESIC/LWF) | Absent | Compliance surface for later phases |
| 6 | **Bulk Salary Structure Assignment** UI | Absent | Needed before onboarding scales |
| 7 | Admin **payslip viewer** on web | Absent (API-only, audit finding) | Cheap to add; owners ask for it constantly |
| 8 | Off-cycle **Additional Salary UI with impact preview** | Absent (API-only) | Needed for bonuses/arrears common case |

---

### 2.7 Payroll Entry (the run screen) — `ui-shots/doc-payroll-entry-payroll-entry.png`, `-get-employees.png`
- A **Draft document**, not a fire-and-forget button: Posting Date, Currency + Exchange Rate, Payroll Frequency, Company, **Payroll Payable Account** (accounting linkage on the run itself), employee filters (**Branch / Designation / Department** + count), an **Employee Details** preview table.
- Two-step flow: **Get Employees** (preview the population) → **Create Salary Slips**. Plus follow-on actions from the same doc: **Make Bank Entry** (journal) and **Make Accrual Entry** (`doc-payroll-entry-payroll-make-accrual-entry.png`, `-bank-entry.png`).

**Fenzit relevance:** our RunsPanel has a single "Run payroll" button that commits payslips immediately (verified in the current-state audit §5). Frappe's run is a *draftable, previewable, reversible-until-submitted document* with the employee population visible before commit. Even without a full draft stage, a "Get Employees" preview step is a cheap trust win.

### 2.8 Payroll Settings — `ui-shots/doc-payroll-settings-*.png`
- **Working Days and Hours:** Calculate Payroll Working Days Based On (**Attendance**), **Consider Unmarked Attendance As (Present/Absent)**, **Include holidays in Total no. of Working Days** (explicit trade-off helper text: "this will reduce the value of Salary Per Day"), **Consider Marked Attendance on Holidays** ("by default, holidays are considered as paid"), Max working hours against Timesheet, **Fraction of Daily Salary for Half Day (0.50)**.
- **Salary Slip:** Disable Rounded Total, **Show Leave Balances in Salary Slip**.

**Fenzit relevance:** our equivalents are hard-coded policy choices (e.g. no-attendance days are paid+flagged, halves = 0.5). Frappe exposes them as documented settings. Where we differ, it's worth a conscious product decision per policy rather than silence.

### 2.9 What Frappe's "mobile app" is — verified
- **A PWA, not a native app:** "Frappe HR ships with a mobile frontend (progressive web app) v15 onwards" (docs.frappe.io/hr/mobile-app-installation) — installed by opening `<site>/hrms` and Add-to-Home-Screen; the Vue SPA in the hrms clone IS that frontend.
- Marketing claims (frappe.io/hr/mobile-app): geolocation check-in/out, approver Request Panel, leave balances + holidays, expenses & advances "just like wallet balances", salary slips with YTD, notifications (push via Frappe Cloud), profile.
- **Fenzit takeaway:** our native RN app is structurally stronger (offline, camera, native push); we take *patterns* (YTD hero, group totals, approval sheets) — not architecture — from Frappe's ESS.

---

## 5. Source list

- frappe.io/hr (product page; feature grid = Recruitment, Employee Lifecycle, Shifts & Attendance, Leave Management, Expense Management, Performance Management, Payroll, Payroll Tax & Reports, Mobile App)
- frappe.io/hr/payroll · /hr/payroll-tax-and-reports · /hr/mobile-app · /hr/india-payroll (screenshot sources, downloaded to `ui-shots/`)
- hrms clone HEAD `ea4158c4f8ec84b4c76db028f0898294817cdf06`: `frontend/src/views/` (ESS SPA surface), `frontend/src/views/salary_slip/Dashboard.vue`, `Detail.vue`
- Docs site referenced by the product: docs.frappe.io/hr (text inventory in `01-frappe-docs-feature-inventory.md`)
- No public demo credentials exist (checked 2026-11-21); third-party demo mith.tech/demos/frappe-hr exists but unverified by this run.
