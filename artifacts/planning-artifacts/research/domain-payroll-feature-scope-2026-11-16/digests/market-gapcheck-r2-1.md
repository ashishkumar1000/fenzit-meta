# Digest — market gap-check of spec-payroll v1 list (round 3), researcher 2
Accessed: 2026-11-16. 12 web calls, 6 sources. Directly fetched: Zoho Payroll India pricing page, RazorpayX Payroll product page, RazorpayX salary-slip article. Others search-derived (medium confidence, product-doc URLs not opened).

## FINDINGS

1. Statutory auto-computation exists even in the FREE tier of simple products — manual admin entry is not a market pattern. Zoho Payroll India's ₹0 Free plan (≤10 employees) includes compliance for Income Tax/EPF/ESI/statewise PT/LWF + "Automatic TDS worksheet"; RazorpayX markets PF/ESIC/TDS/PT fully automated, no manual-entry mode. — Zoho pricing page, razorpay.com/payroll. [HIGH · product-feature] → MISSING: admin-entered TDS/PF is the v1 list's biggest gap; minimal slab-based tax calculator + 12%-of-basic PF rule reaches free-tier parity.
2. Employer (not employee) is legally liable for TDS/PF/PT correctness; hand-entered statutory amounts carry real employer liability the product should surface. Sec 192 "assessee in default" (interest 1%/mo, 1.5%/mo if deducted-not-deposited; penalty u/s 271C; 40(a) disallowance); PF default s.14B damages up to 100% + 12% p.a.; PT employer-deducted, state PTRC registration. [MEDIUM (search-derived legal summary, regulatory pages not opened) · regulatory] → MISSING: admin UX guardrails — computed default the admin can override + acknowledgment/warning on override, framed on employer liability.
3. Attendance regularization for missed punches before cut-off is standard in every attendance-integrated product. Keka help: regularization for missed IN/OUT punches, incl. on weekly-offs/holidays; "lost punch does not automatically regularize"; factoHR feeds regularized data directly into payroll. [MEDIUM · product-feature] → MISSING: v1 has half-day LOP + cut-off but no missed-punch correction path before cut-off.
4. Paid public holidays and weekly offs are configured lists the run treats as paid days, separate from leave. Keka "Managing Holiday lists"/"Managing Weekly Off" config tied to payroll; factoHR computes pay from attendance+leave+week-off data. [MEDIUM · product-feature] → MISSING: v1 has no named treatment of public holidays as paid non-LOP days inside the run.
5. LOP reversal is a named core feature — Zoho Free tier explicitly includes "LOP and LOP Reversal". [HIGH · product-feature] → MISSING: LOP deducted forward has no reversal path (unpaid leave later regularized / leave credited retroactively) — correction twin of the LOP deduction.
6. Salary revision is effective-dated with arrears even at free tier — not an overwrite. Zoho Free: "Salary Revision and Arrears"; RazorpayX: automated arrears/revisions past/future/mid-month. [HIGH · product-feature] → MISSING (subtle): v1 never says how revisions land in history; minimal correct = effective-dated revision + arrears, not overwrite.
7. Payslip contents: earnings/deductions/net core verified (RazorpayX article: Basic/HRA/conveyance/medical/DA/special earnings; PT/EPF/TDS deductions; net; no statutory format exists); identity numbers (UAN/PAN/ESI) and YTD widely cited standard-practice (search-derived, not verified on opened pages); leave balance recommended-not-universal. [HIGH for RazorpayX scope; MEDIUM for identity/YTD · convention-practice] → MISSING: v1 "statutory fields" should explicitly include employee identifiers (UAN/PAN/ESI) and YTD totals.
8. Off-cycle runs, audit trail, employee payslip access, lock — v1 list matches market basics. Zoho Professional adds bonus & off-cycle runs, Standard adds audit trail, Free includes self-service portal; RazorpayX regular & off-cycle payroll; Zoho record-locking is Premium-only. [HIGH · product-feature] → CORRECT as planned (lock ahead of Zoho basic tiers; audit at Zoho Standard).
9. Formula-based salary components are an ADVANCED-tier feature in simple products. Zoho gates "Advanced salary components — scheduled, formula-based" behind Professional (₹3,000/mo); Free ships only pre-defined components. [HIGH · product-feature] → UNNECESSARY-COMPLEXITY candidate: v1 could launch flat components + one implicit HRA pattern, defer the general formula engine; circular-formula rejection only needed if formulas ship.

## LEADS
- greytHR/Keka statutory computation help docs named by search, not opened — next fetches for finding 1's table-stakes claim.
- ClearTax salary-slip/TDS pages 410 at old paths; re-find current URLs to upgrade findings 1/2/7 to HIGH.
- Saral PayPack official feature page (search-derived only so far).

## NOT FOUND
- Q4 leave types vs single count for LOP: no direct evidence either way; payslip hints (earned/casual/sick balances) suggest products model types; v1 single-count model UNVALIDATED.
- No product found where employer manually enters statutory amounts (consistent with finding 1; absence-of-evidence).
- No legal mandate for payslip format or leave balance on payslip (PWA payslip requirement itself search-derived).

## TOP 5 GAPS (ranked)
1. Minimal statutory computation (PF 12% of basic, state PT slabs, slab TDS) replacing pure manual entry — manual entry has no market analogue, concentrates employer liability in typing.
2. Attendance regularization / missed-punch correction before cut-off — attendance-driven LOP has no error-recovery path without it.
3. Public-holiday + weekly-off paid-day handling inside the run (configured lists, separate from leave).
4. Effective-dated salary revision + arrears instead of silent overwrite.
5. LOP reversal — correction twin of LOP deduction; Zoho Free-tier feature.
Runner-up: payslip identity fields (UAN/PAN/ESI) + YTD totals — cheap, conventional.
