# Digest — foundations (dims 1+2), round 1, researcher 1
Accessed: 2026-11-16. 12 web calls, 4 sources read fully, 6 aggregated search summaries.

## Dimension 1 — payroll language & mental models

F1. Standard Indian salary structure builds bottom-up: basic (typically 40–50% of CTC, fully taxable, base for PF/gratuity/HRA) → HRA (conventionally 40% of basic non-metro, 50% in Delhi/Mumbai/Kolkata/Chennai) → fixed allowances (conveyance, medical) → LTA (tax-exempt domestic travel) → special allowance as the fully taxable balancing figure, structured last; perquisites (car, meal coupons, ESOPs) and variable pay/bonus alongside. [medium · glossary] — single aggregated source (ClearTax/Keka/Razorpay guides), no page read.

F2. Gross salary = earnings before deductions (excludes employer PF and perquisites). Net (in-hand) = gross − (EPF + income tax + PT + gratuity) per worked formula. CTC = full annual package, CTC > gross > net; CTC includes employer PF (₹48,000 in a ₹7,00,000 example); page FAQ says CTC generally also includes gratuity but worked example doesn't — practitioner practice varies. — https://www.zoho.com/in/payroll/academy/payroll-administration/ctc-vs-gross-vs-net-salary.html, Zoho Payroll Academy, 2025-02-18. [high · glossary]

F3. Statutory-compliant payslip fields: employer identity; employee name/ID/designation; PAN; bank account; EPF/ESI numbers; date of joining; earnings breakdown (basic/HRA/DA/conveyance/medical/special/LTA/OT); deductions (EPF, PT, TDS, ESI, loans); slip number; salary period and payment date; paid days/days worked; gross and net pay. Legal basis claimed: Payment of Wages Act 1936 s.17(3), fines ₹1,500–₹7,500 for failure; Act's wage coverage limited (~₹21,000/mo threshold); no single dedicated payslip law for all sectors. [medium · regulatory + glossary] — single aggregated source; verify s.17(3) and fine quantum against Act text.

## Dimension 2 — statutory rules (India)

F4 (regulatory). EPF: applies at 20+ employees; employee + employer each 12% of basic + DA; ₹15,000/mo statutory wage ceiling (unchanged since Sept 2014); employer 12% splits 8.33% EPS / 3.67% EPF; EDLI 0.5% + admin 0.65%; deposits due by 15th of following month via monthly ECR. — Keka compliance checklist (pub 2025-08-25, upd 2026-09-08) + aggregated summary. [high on rates/ceiling (two sources); 0.5%/0.65% split single-source · regulatory + quantitative]

F5 (regulatory). ESI: 10+ employees (even 1 in hazardous units); covers ≤₹21,000/mo gross (₹25,000 for PwD); employer 3.25% / employee 0.75% (total 4%) on gross; half-yearly returns. — Keka page + aggregated summary. [high · regulatory + quantitative]

F6 (regulatory). Professional tax: state-level, employer deducts/remits; 21 states/UTs have PT Act (AP, Assam, Bihar, Chhattisgarh, Gujarat, J&K, Jharkhand, Karnataka, Kerala, MP, Maharashtra, Manipur, Mizoram, Nagaland, Odisha, Punjab, TN, Telangana, Tripura, WB + page self-contradicts on Arunachal); no PT in Delhi, Goa, Haryana, Rajasthan, UP, Uttarakhand, HP and others; statutory cap ₹2,500/employee/year; slab-based; total PT deductible under Income Tax Act. — greytHR wiki (no date, © 2026); cap corroborated by Simpliance result. [high on cap/mechanism; medium on exact list · regulatory]

F7 (regulatory). LWF: 16 states/UTs (AP, Chandigarh, Chhattisgarh, Delhi, Goa, Gujarat, Haryana, Karnataka, Kerala, MP, Maharashtra, Odisha, Punjab, TN, Telangana, WB); contributions ₹3 (Delhi employee) to ₹240 total (Goa), monthly/half-yearly/annual; Haryana only wage-percentage state (0.2%, max ₹35 emp / ₹70 er, monthly); Kerala varies by establishment; Karnataka revised 2025 to ₹50 emp / ₹100 er annual. — https://salarybox.in/lwf-rates-india (verified July 2026); Karnataka revision corroborated by LinkedIn 2025. [high on list/shape · regulatory + quantitative; verify per-state gazette before schema-lock]

F8 (regulatory). Gratuity: payable after 5 years' continuous service; (last drawn salary × 15 × years) ÷ 26; Keka places it under Code on Social Security 2020 ss.53/56 (post-21-Nov-2025 labour codes), payable within 30 days of falling due. [high on formula; medium on code sections · regulatory + quantitative]

F9 (regulatory). TDS on salary: employer deposits by 7th of following month; quarterly Form 24Q; Form 16 (Part A from TRACES, Part B break-up) after FY close. Regime election: collect employee's old-vs-new regime choice at start of each FY; no declaration → new regime default (post-Budget 2023); HRA/LTA/80C/80D only in old regime; standard deduction ₹75,000 new regime (FY 2024-25 onward). — aggregated summary (ClearTax/Tax2Win) + Keka for deposit timing. [high · regulatory]

F10 (regulatory — CONTRADICTION, single source). Keka (upd 2026-09-08, post-21-Nov-2025 labour codes) claims income-tax forms renamed: Form 24Q → "Form 138", Form 16 → "Form 130", quarterly due dates 31 Jul / 31 Oct / 31 Jan / 31 May, 7-year retention under "Income-tax Rules, 2026"; contemporaneous practitioner articles (F9) still use 24Q/Form 16. Also asserts Code on Social Security penalties: unremitted deducted contributions → 1–3 yrs imprisonment + ₹1,00,000; other defaults 2–6 months + ₹50,000; repeat up to 2 yrs + ₹2,00,000; ESI late payment 12% p.a. interest. [low–medium · regulatory] — highest-risk claim in digest; see leads.

F11. Minimum wages: appears on the checklist only as ongoing obligation to track central + state revisions; no rates given. [low (absence) · regulatory]

F12. Schema vocabulary anchors: pay period = salary month shown as "salary period (month/year)" on payslip; monthly CTC vs annual package — CTC annual, gross/net per pay period; per-month earnings bases must be computed against statutory caps (PF ₹15k, ESI ₹21k); regime election is a per-FY employee declaration stored by employer. [high · glossary]

## LEADS
- Resolve F10 contradiction first: does the 21-Nov-2025 labour-code effect date + form renumbering (24Q→138, 16→130, "Income-tax Rules, 2026") hold? Verify at incometax.gov.in / TRACES / CoSS enforcement notifications. If true, every TDS form reference in the product changes; if not, Keka is speculative.
- EPF ceiling ₹15,000: agreed unchanged, but lapsed Amendment Bill (CPI indexation) + unconfirmed ₹21k/₹25k rumours — don't hard-code the ceiling in a schema.
- EPF trigger discrepancy: Keka says 20+ employees; aggregated summary notes 10% optional rate for certain <20-employee entities — pin exact threshold from EPF Act text.
- PT state list: greytHR page self-contradicts on Arunachal; per-state slabs, special months (Maharashtra February levy), registration deadlines not retrieved — greytHR per-state pages are the follow-up.
- FnF settlement: not covered by any source; likely carries its own statutory timeline (gratuity 30 days is the only adjacent sourced fact).
- Penalty figures are statutory text via secondary sources only; no enforcement data found.

## NOT FOUND
- Definitions from a read source for: reversal (negative pay component after overpayment), FnF settlement mechanics, arrear treatment — only pay-period concept sourced.
- Minimum wage rates (central floor or state schedules).
- Primary-statute confirmation of PWA s.17(3), PT ₹2,500 cap provision, EPF/ESI notifications on epfindia.gov.in / esic.gov.in (official sites unreachable within budget) — all regulatory figures rest on two strong practitioner pages + aggregated summaries.
- Payslip layout conventions beyond field lists (no single law governs format for all sectors; only field-level requirements found).
