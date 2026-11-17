# Digest — linkage (dim 3), round 1, researcher 2
Accessed: 2026-11-16. 12 web calls; bare-act fetch attempts failed (devgan.in 503, cleartax 410) — regulatory claims rest on search summaries, confidence marked accordingly.

## A. LOP divisor — competing conventions (the core ambiguity)

1. Divide by actual calendar days in month (28/29/30/31) — presented as one of three standard divisor choices with worked example. — attendmitra.com/resources/payroll/how-to-calculate-salary-per-day-and-lop. [medium-high · convention-practice]
2. Divide by fixed 30 ("gross method") — same source; courts reportedly note this over-deducts (ignores paid weekly offs). [medium · convention-practice]
3. Divide by 26 (6-day week + 1 paid weekly off) — standard basis for minimum-wage compliance: monthly min wage = daily rate × 26; hourly = daily ÷ 8. — calcguru.in/minimum-wage-compliance-calculator; corroborated by india-briefing.com "Guide to Minimum Wage India" (pub 2026-06-26): monthly minimum wages "derived from revised daily wages × 26 days." [medium-high · regulatory(min-wage)/convention(LOP)]
4. Divide by 21 or 22 for 5-day-week companies. [low-medium · convention-practice]
5. Divide by actual worked days — attested (and criticized) company practice; the unpaid day itself shrinks the divisor, inflating the deduction. — Reddit r/LegalAdviceIndia, ~Oct 2024. [low (anecdote) · convention-practice]
6. SAP India standard payroll: monthly pay on working days excluding Sundays (26-day basis for 6-day weeks). — SAP Community, pub 2008-10-20. [medium (old, ERP-specific) · convention-practice]
7. No single statute mandates a universal LOP divisor. The statutory 26 appears in: minimum-wage computation; gratuity (PoG Act 1972 §4: monthly wage ÷ 26 × 15); Factories Act earned-leave encashment practice. LOP for salaried staff otherwise sits in contract/company policy. [medium · regulatory]

## B–C. Proration & rounding

8. Products prorate by configurable daily-wage basis (calendar vs working days), not one fixed rule — greytHR "Prorate employee's salary on LOP days" setting; Keka daily-wage basis + configurable LOP-day rounding. [medium · convention-practice]
9. LOP-day rounding is a config (nearest half-day/full day); Keka half-day = 0.5 or round to 1. Rounding ORDER (per-day wage before multiply vs final amount to rupee) not explicit in any source. [medium · convention-practice]

## D. Overtime

10. Factories Act 1948 §59: beyond 9 hrs/day (§54) or 48 hrs/week (§51) paid at TWICE ordinary rate (basic + allowances, excl. bonus); §59(3) rest-day OT also 2×, hourly = (2 × daily rate) ÷ shift hours. [medium · regulatory]
11. Code on Wages 2019 §14: OT at least twice normal rate (basic + DA + retaining allowance); §14(2) under-time still paid for full normal period. [medium · regulatory]
12. Code on Wages status: enacted Aug 2019, NOT yet fully in force as of late-2025 reporting; legacy laws continue; Mar 2025 "final stages", Nov 2025 model rules cleared, phased rollout expected 2025–26 (Business Standard/CNBC-TV18/Moneylife via search). Product action: build on legacy-law rules, treat Codes as pending re-baseline. [medium · regulatory]
13. SMB-product OT config surface (multipliers, comp-off) not found — gap.

## E. Leave types, accrual, encashment

14. Statutory EL, Factories Act §79: 240+ days worked → 1 day per 20 worked (adults); carry-over with ~30-day accumulation cap unless state notifies otherwise. [medium · regulatory]
15. Shops & Establishments employees: state S&E Acts vary — commonly 1 per 15 or per 22 days worked. [medium · regulatory]
16. Encashment formula (Factories Act practice): unavailed EL × (last monthly wages ÷ 26). The "15 days" figure belongs to gratuity, NOT leave encashment. [medium · regulatory/quantitative]
17. During-service encashment is policy (Karnataka permits advance encashment); taxable. Exit encashment: govt up to 300 days (CCS Rules; 300-day proviso struck down by SC Jan 2024); private-sector exit encashment exempt u/s 10(10AA) up to 10 months' average salary, ₹25 lakh cap (Budget 2023). [medium · regulatory/quantitative]
18. Comp-off statutory cousin: Factories Act §53 compensatory holidays within same/next two months (max 2/week); §52 weekly-holiday substitution so no one works >10 consecutive days. Product-level comp-off policies not found. [medium · regulatory; product convention NOT FOUND]

## F. Weekly offs & holidays

19. Weekly holiday is paid — statutory right, Factories Act §52; §53 compensatory mechanism replaces a lost weekly off. [medium · regulatory]
20. "Week off forfeiture" rejected by case law — Automotive Industries Ltd v. Workmen (SC 1959): absence on a preceding working day does not forfeit the Sunday; forfeiture of weekly holiday for unauthorized absence held illegal (narrow standing-orders exception). [medium (case citations unverified) · regulatory]
21. Implication: LOP deduction should count only working days absent, not the weekly off inside the absence span — normative basis for the ÷26 camp. [synthesis of 2/3/19/20 · convention-practice]

## G. Deductions, half-days, late arrival

22. Payment of Wages Act 1936 §7: itemized wage slip required; permissible deductions include fines §7(2)(a) and absence from duty §7(2)(b); total deductions capped at 50% per wage period §7(3) — cap does NOT apply to absence-from-duty, damage/loss from employee default, certain advance recovery. Design takeaway: attendance-driven LOP sits outside the 50% cap; discretionary late/fine deductions sit inside it. [medium · regulatory]
23. Half-day → 0.5 LOP mapping (Keka); greytHR unpaid-break handling; configurable. Late-arrival and minimum-hours mechanics: articles exist but snippets didn't capture exact mechanics. [medium for 0.5 mapping; low late/min-hours · convention-practice]
24. How the (unenforced) Code on Wages rewrites §7 cap: nothing found.

## LEADS
- ÷26 vs ÷30 vs calendar-days is a genuine product decision — mainstream products make it a setting, not a constant. Recommendation shape: per-company divisor setting (calendar | fixed-30 | fixed-26 | working-days), default fixed-26 for a 6-day field workforce (convention choice, not legal mandate).
- Anomaly to guard: never use actual-worked-days as divisor (unpaid day shrinks divisor, inflates deduction). Decouple "days present" from "days in month".
- Unverified case law: Surendra Kumar Verma v. CGIT (1980) 26-divisor holding; Automotive Industries (1959) — verify against judgment texts before citing to stakeholders.
- §7(3) 75% carve-out (co-operative-society deductions) — verify against bare act before relying on the cap.
- Comp-off-instead-of-OT-pay and product OT config — chase vendor help centres (support.greythr.com, Keka help).
- Monitor Ministry of Labour gazette for Code on Wages commencement — when notified, §14 OT rule and deduction-cap rewrite become the baseline.

## NOT FOUND
- Verbatim statute text (all bare-act fetches failed). First follow-up: indiacode.nic.in / labour.gov.in PDFs for Factories Act §§52/59/79, PWA §7.
- Exact rounding defaults of named products (per-day vs per-month rounding order).
- Minimum-hours-per-shift and late-arrival deduction mechanics in specific products.
- Comp-off policy conventions (expiry, hours→days) in SMB field-force products.
- Definitive Code on Wages commencement date — latest evidence Nov 2025 "model rules cleared".
