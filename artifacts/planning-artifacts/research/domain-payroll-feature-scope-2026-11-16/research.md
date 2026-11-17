---
title: 'domain research: payroll feature scope'
type: 'domain'
topic: 'payroll feature scope'
decision: 'Scope Fenzit payroll/salary-processing feature set (India, field workforce, attendance already tracked) to feed a good-to-have-features brainstorm'
source: 'web fan-out'
status: complete
preset: 'standard'
validation: 'normal'
created: '2026-11-16'
updated: '2026-11-16'
verified: 3
unverified: 2
overturned: 1
claims_note: '8 ledger claim refs; F10 disputed→overturned and PWA7 unverified→verified reconciled last-status-wins. Superseded ledger lines excluded from counts.'
---

# domain research: payroll feature scope

**Decision this research serves:** Scope Fenzit's payroll/salary-processing feature set — Indian market, field workforce, attendance already tracked — feeding a brainstorm on good-to-have features before any spec. **Scope constraint (user direction):** keep it simple — implement only good-to-have features, no enterprise HRMS complexity.

## Executive summary

The evidence says: build the **minimum correct-and-legal monthly payroll loop** — attendance cut-off → leave/LOP application → payslip with statutory fields → admin-defined deductions — and treat everything else as a small, opt-in feature list. Two findings drive this:

1. **The table-stakes in Indian SMB payroll are almost all *filing* machinery, not calculation** [16][17][19][20][21][22]. Calculation is simple arithmetic on a salary structure; the hard, complex part competitors lead with is statutory filing artefacts (PF ECR, ESI challans, eTDS 24Q, Form 16). Fenzit's simple-first direction means we do **calculation + payslip** and let admin enter deduction amounts (TDS etc.) — deferring the filing engines, which is where the complexity lives.
2. **The attendance→payroll seam has one genuine product decision — the LOP divisor — and the market answers it with a setting, not a constant** [5][6][8]. Five conventions coexist and no statute mandates one for salaried staff; make it a per-company config (default fixed-26 for a 6-day field workforce), and the LOP problem is solved without any engine.

**Biggest caveat:** the labour codes were notified 21 Nov 2025 but their rules rollout runs through 2026 [26]; payroll specs must distinguish "in force" from "rules operational", and statutory rates/ceilings should be data (config), never hard-coded [2][3][4].

## Dimension 1 — payroll language & mental models (glossary)

- **Salary structure builds bottom-up:** basic (typically 40–50% of CTC; fully taxable; base for PF, gratuity, HRA) → HRA (conventionally 40% of basic non-metro, 50% in Delhi/Mumbai/Kolkata/Chennai) → fixed allowances (conveyance, medical) → LTA → **special allowance as the fully taxable balancing figure, structured last**; perquisites and variable pay sit alongside [10].
- **CTC > gross > net.** Gross = earnings before deductions (excludes employer PF, perquisites). Net = gross − (EPF + TDS + PT + other deductions). CTC = full annual package including employer PF; whether gratuity accrual sits inside CTC varies by practitioner [1].
- **Statutory payslip fields** (PWA 1936 mandates issuing wage slips — s.17(3) claimed, unverifiable verbatim this run): employer identity; employee name/ID/designation; PAN; bank account; EPF/ESI numbers; date of joining; earnings breakdown; deductions itemised; slip number; salary period; payment date; paid days/days worked; gross and net pay [11].
- **Schema vocabulary anchors:** pay period = the salary month; CTC is annual, gross/net computed per pay period; monthly earnings bases must be computed against statutory caps (PF ₹15,000 wage ceiling [2], ESI ₹21,000 gross [2]); tax-regime election is a per-FY employee declaration [12].

## Dimension 2 — statutory rules of the game (India)

Verified current where the round-2 pass reached it; all rates must be config data.

| Item | Key rules | Source |
|---|---|---|
| EPF | 20+ employees; 12% + 12% of basic+DA; ₹15,000/mo wage ceiling (unchanged since 2014); employer 12% splits 8.33% EPS / 3.67% EPF; ECR monthly, due by 15th | [2][12] |
| ESI | 10+ employees; covers gross ≤ ₹21,000/mo (₹25,000 PwD); employer 3.25% / employee 0.75% | [2][12] |
| Professional tax | State-level; ~21 states levy; cap ₹2,500/employee/year; slab-based | [3] |
| LWF | 16 states; ₹3–₹240 range; Haryana 0.2% of wages; Karnataka revised 2025 (₹50/₹100 annual) | [4] |
| TDS on salary | Employer deposits by 7th of following month; quarterly **Form 24Q**; **Form 16** issued after FY close; regime election per FY, new regime default | [12][25] |
| Gratuity | After 5 years' continuous service; (last drawn salary × 15 × years) ÷ 26; payable within 30 days | [2] |
| OT | Factories Act §59: 2× ordinary rate beyond 9 hrs/day or 48 hrs/week (round-2 confirmed) | [13] |
| Deduction cap | PWA 1936 §7(3): 50% of wages per period (75% band for <₹200/month earners); absence-from-duty is an authorised deduction (§7(2)(b)) | [13][PWA7] |
| Earned leave | Factories Act §79: 1 day per 20 worked (240+ days in year); S&E Acts vary (1/15 or 1/22) | [13][14] |
| Labour codes | All four codes notified by Gazette **21 Nov 2025**; Code on Wages draft model rules Dec 2025, finalisation targeted end-Jan 2026; state rules in varying stages through 2026 — build on legacy-law rules, treat codes as pending re-baseline | [26] |

**REFUTED:** the round-1 vendor claim that Form 24Q/Form 16 were renamed "Form 138"/"Form 130" under "Income-tax Rules, 2026" — no credible source exists; forms remain 24Q/26Q/27Q/27D and Form 16/16A as of Nov 2026 [25].

## Dimension 3 — attendance → payroll linkage

- **LOP divisor is a product decision, not a solved legal question.** Five conventions coexist: actual calendar days [5]; fixed-30 (over-deducts — ignores paid weekly offs) [5]; **fixed-26** (6-day week + paid weekly off — the minimum-wage basis [6][7], SAP India's standard basis [8], the gratuity and encashment divisor); 21–22 for 5-day weeks (weakly sourced, low-medium confidence); actual-worked-days (bad — the unpaid day shrinks the divisor and inflates the deduction) [9]. Mainstream products expose it as a **setting** (greytHR, Keka: configurable daily-wage basis + LOP-day rounding) [15].
- **Week-offs stay paid.** The weekly holiday is a paid statutory right (Factories Act §52), and case law rejects forfeiting it for absence on a preceding working day — the specific case citations (*Automotive Industries*, 1959 line) are unverified this run; treat the principle as practitioner consensus, not settled citation [14]. So an LOP deduction should count only working days absent, not the week-off inside the absence span.
- **Attendance-driven LOP is an authorised "absence from duty" deduction (PWA §7(2)(b), round-2 confirmed), and is *believed* to sit outside the 50% cap — the cap-exclusion clause itself was unverifiable this run**; verify against the bare act before relying on it in compliance copy [13].
- **Half-days map to 0.5 LOP** (configurable rounding, e.g. round to full day) [15]. Rounding *order* (per-day wage before multiply vs final amount) is unspecified in sources — a design decision to make explicitly.
- **Overtime:** statutory floor 2× ordinary rate [13]; SMB-product OT configuration (multipliers, comp-off-instead-of-pay) was not evidenced this run — a gap.
- **Leave encashment:** exit encashment = unavailed EL days × (last monthly wages ÷ 26); private-sector exit encashment is tax-exempt up to 10 months' average salary, ₹25 lakh cap [14]. During-service encashment is a policy matter, taxable.
- **Comp-off:** statutory cousins are Factories Act §52/§53 (compensatory holidays for a lost weekly off); product-level comp-off policies not evidenced this run.

## Dimension 4 — competitive feature teardown (Indian SMB payroll)

Read from product pages: Zoho [16], RazorpayX [17][18], greytHR [19], factoHR [20], Keka [21], Saral PayPack [22]; SoftwareSuggest-level for Pocket HRMS/HROne/Darwinbox [23].

**Table-stakes (nearly all products):** one-click + off-cycle runs; configurable formula-driven salary structure; PF/ESI/PT/TDS/LWF compliance with filing artefacts; payslip generation + app/portal delivery; digitally signed Form 16; bonuses/incentives with scheduling; arrears; salary revision with trail; employee self-service (payslip download, IT declarations, reimbursement claims); **attendance→payroll sync** — the pattern is punch → attendance lock → automatic LOP/OT inside the pay run.

**Differentiators (only some):** native bank payouts/bank-advice files; WhatsApp delivery/query channel; contractor payments with TDS; maker-checker/locking/audit governance; run-fix without re-running the cycle (Keka); earned-wage-access partnerships (RazorpayX); AI anomaly detection and assistants (advertised as of access date — Zoho Zia, Keka AI, greytHR NAVOS).

**Enterprise/tier-gated:** multi-entity/multi-country payroll; tier-gated advanced modules (RazorpayX Elite/Enterprise); Darwinbox-class HCM suites.

**Pricing:** the third-party table puts the entry SMB tier at ≈ ₹20–50/employee/month [23] (low-medium confidence); RazorpayX's live flat pricing (₹3,499/mo for ≤20 employees ≈ ₹175/employee/month) sits above that range — treat the ₹20–50 figure as directional only [18].

## Dimension 5 — cadence, delivery, integrations

- **Standard cadence:** attendance cut-off ~20th–25th → payroll run 26th–30th (LOP, arrears, deductions applied) → pay credited 1st–7th of the next month; a payroll **lock** freezes components for the period [24]. Payment of Wages Act §5 (before 7th/10th of following month) is the legal outer bound — unverifiable verbatim this run, do not cite without a bare-act check [PWA5].
- **Payslip delivery:** app/portal download, email, print; WhatsApp emerging (Zoho, RazorpayX only) [16][17]. **Payslip immutability/versioning is not addressed by any product page** — an open design question.
- **Integrations:** bulk bank-transfer advice is table-stakes at SMB; TDS 24Q e-filing appears at greytHR/factoHR tier; accounting sync (Tally/Zoho Books) unverified on the pages read.

## Cross-dimension insights

- **Complexity lives in filing, not calculation.** The competitive table-stakes list is dominated by statutory filing artefacts [16]-[22], while the calculation core (structure × attendance × deductions) is simple arithmetic governed by one config decision (divisor). This directly validates the user's simple-first constraint: a lean Fenzit payroll = calculation + payslip + admin-entered deductions, with the filing engines deferred.
- **Attendance-first is the wedge, and Fenzit already owns that half.** Attendance-only products (Saral "Punch to Payslip" [22]) compete on exactly the integration Fenzit has already built; the market treats attendance→payroll sync as table-stakes, so Fenzit starting from attendance is not a handicap — it is the entry position.
- **The regulatory environment is mid-rewrite** [26]: every rate/ceiling finding lands during a labour-code transition. That argues for storing statutory values as editable config with effective dates, not literals in code.

## Contrary evidence

- The strongest counter to "simple first": statutory filing artefacts (PF ECR, ESI challans, 24Q eTDS, Form 16) are table-stakes in every competitor, so a payroll without them is below the market floor [19][20]. Counterweight: they are the highest-complexity, highest-maintenance surface, they can be admin-served manually at Fenzit's scale, and the user has explicitly scoped them out for now.
- A flat "50% deduction cap" reading was corrected in round 2 — a 75% band exists for <₹200/month earners [13]; the cap interacts with the Code on Wages in ways not yet evidenced.

## Recommendations

1. **Must-do (legal minimum loop):** monthly payroll run from attendance + leave (LOP applied), configurable LOP divisor setting (default fixed-26), half-day 0.5 LOP, statutory-field payslip generation, admin-defined deduction heads with amounts (TDS entered by admin, not computed), payslip delivery in-app + PDF. Basis: dims 1–3 (high confidence), validated by the market treating this as the floor.
2. **Good-to-have candidates (pick a few):** off-cycle run for bonus/arrears payouts; payroll lock + simple audit trail; leave encashment at exit; comp-off; leave-accrual configuration (monthly accrual). Basis: dims 3–4; each is small and does not require a filing engine.
3. **Defer (record in the ledger):** statutory filing engines (PF ECR/ESI challans/24Q eTDS/Form 16 generation), bank-advice integration, WhatsApp channel, loans & advances with EMI, F&F settlement workflow, maker-checker governance, AI layer, contractor payments, multi-entity. Basis: differentiator/enterprise tiers + complexity concentration insight.
4. **Schema constraints for the SPEC:** statutory rates, ceilings, PT/LWF state tables, and the LOP divisor are configuration with effective dates — never literals; earnings bases computed against caps (PF ₹15k, ESI ₹21k); payslip fields per the statutory list in dim 1; decouple "days present" from "days in month" (never use worked-days as divisor).
5. **Compliance posture for v1:** admin-served filing — payslip carries the statutory fields; TDS/PF/ESI amounts are admin inputs; the product does not file. Re-check statutory rates before launch (see staleness map).

## Open questions

- **Verbatim statute checks still owed** (government sites bot-blocked this run): PWA §5 pay-date rule, PWA §17(3) wage-slip provision, EPF 20-employee threshold from the Act text, the exact §7(3) cap clause. Route: iLawKhoj section-wise PDFs or indiacode "Act Only" web view. The product design does not hinge on these (admin-served filing), but cite carefully in any user-facing compliance copy.
- **Code on Wages operational impact:** model rules finalisation status as of mid/late-2026 — what §14 OT rules and any deduction-cap rewrite change for SMB payroll. Route: Ministry of Labour gazette watch (a Deepen pass).
- **Product OT/comp-off configuration conventions** in SMB field-force tools (vendor help centres not chased). Needed only if OT pays-out goes in v1.
- **Payslip immutability/versioning semantics** — no market convention found; decide by design (recommend: a payslip row, once locked, is never edited — a correction is a new payslip version).
- **Zoho's current published pricing** (page 404'd) and primary feature pages for Pocket HRMS/HROne — only needed if a formal competitor matrix is ever written.

## Source appendix

| # | Claim/finding supported | Publisher | Pub date | Accessed | Confidence |
|---|---|---|---|---|---|
| [1] | CTC/gross/net definitions | [Zoho Payroll Academy](https://www.zoho.com/in/payroll/academy/payroll-administration/ctc-vs-gross-vs-net-salary.html) | 2025-02-18 | 2026-11-16 | high |
| [2] | EPF/ESI rates+ceilings, gratuity formula, compliance calendar | [Keka compliance checklist](https://www.keka.com/indian-payroll-compliance-checklist) | 2025-08-25 (upd 2026-09-08) | 2026-11-16 | high (rates) |
| [3] | PT states, ₹2,500 cap, slabs | [greytHR wiki](https://www.greythr.com/wiki/acts/professional-tax-india/) | © 2026 | 2026-11-16 | high (cap), medium (list) |
| [4] | LWF 16 states, rates, Karnataka 2025 revision | [SalaryBox](https://salarybox.in/lwf-rates-india) | verified 2026-07 | 2026-11-16 | high |
| [5] | LOP divisor conventions (calendar/30) | [AttendMitra](https://www.attendmitra.com/resources/payroll/how-to-calculate-salary-per-day-and-lop) | n.d. | 2026-11-16 | medium-high |
| [6] | 26-day minimum-wage basis | [CalcGuru](https://calcguru.in/minimum-wage-compliance-calculator) | n.d. | 2026-11-16 | medium-high |
| [7] | Monthly min wage = daily × 26 | [India Briefing](https://www.india-briefing.com/news/guide-minimum-wage-india-19406.html) | 2026-06-26 | 2026-11-16 | medium-high |
| [8] | SAP India 26-day basis | [SAP Community](https://community.sap.com/t5/enterprise-resource-planning-q-a/payroll-calculation-for-26-days/qaq-p/4644362) | 2008-10-20 | 2026-11-16 | medium (old) |
| [9] | Worked-days divisor anti-pattern | [Reddit r/LegalAdviceIndia](https://www.reddit.com/r/LegalAdviceIndia/comments/1g8e6fk/per_day_salary_calculation) | ~2024-10 | 2026-11-16 | low (anecdote) |
| [10] | Salary-structure build order | Aggregated summaries (ClearTax/Keka/Razorpay guides) | 2026 | 2026-11-16 | medium |
| [11] | Payslip statutory fields, PWA s.17(3) claim | Aggregated summaries (ClearTax/Razorpay/Saral/greytHR) | 2026 | 2026-11-16 | medium (s.17(3) unverified) |
| [12] | EPF/ESI/TDS mechanics, regime election | Aggregated summaries (EPFO-linked ClearTax, Tax2Win) | 2026 | 2026-11-16 | high (mechanics) |
| [13] | Factories Act §59/§79, PWA §7 text, OT 2× | WebSearch summaries of bare-act text | 2026 | 2026-11-16 | moderate (round-2) |
| [14] | §52/§53 week-offs, §79 EL, encashment 10(10AA)/₹25L | WebSearch summaries | 2026 | 2026-11-16 | medium |
| [15] | Proration/rounding settings (greytHR, Keka) | WebSearch summaries of product settings | 2026 | 2026-11-16 | medium |
| [16] | Zoho payroll feature set | [Zoho Payroll](https://www.zoho.com/payroll/) | n.d. (live page) | 2026-11-16 | high |
| [17] | RazorpayX feature set | [RazorpayX Payroll](https://razorpay.com/payroll/) | n.d. (live page) | 2026-11-16 | high |
| [18] | RazorpayX pricing ₹3,499/₹6,499 tiers | [RazorpayX pricing](https://razorpay.com/payroll/pricing/) | n.d. (live page) | 2026-11-16 | high |
| [19] | greytHR feature set (ECR, eTDS, Form 16) | [greytHR](https://www.greythr.com/payroll-software/) | n.d. (live page) | 2026-11-16 | high |
| [20] | factoHR feature set (off-cycle, arrears, 15+ formats) | [factoHR](https://www.factohr.com/payroll-software) | n.d. (live page) | 2026-11-16 | high |
| [21] | Keka feature set (maker-checker, run-fix) | [Keka](https://www.keka.com/payroll-software) | n.d. (live page) | 2026-11-16 | high |
| [22] | Saral PayPack attendance-first payroll | [Saral PayPack](https://www.saralpaypack.com/) | n.d. (live page) | 2026-11-16 | high |
| [23] | SoftwareSuggest comparisons, entry pricing ₹20–50 PEPM | [SoftwareSuggest](https://www.softwaresuggest.com/) (search-level) | 2026 | 2026-11-16 | low-medium |
| [24] | Cadence: cut-off → run → pay date; payroll lock | Payroll-calendar guides (Zoho docs, RazorpayX blog, Saral, greytHR — search-level) | 2026 | 2026-11-16 | medium |
| [25] | Form renaming refuted; current form names | Live web search verification pass | 2026-11 | 2026-11-16 | moderate-high |
| [26] | Labour codes notified 21 Nov 2025; rollout through 2026 | News search verification pass (Ministry of Labour announcements) | 2025-11→2026 | 2026-11-16 | moderate |

## Staleness map

Computed via `recon_kit.py staleness` (windows: regulatory 1 mo · pricing 6 mo · product-feature 18 mo · convention 36 mo · glossary 36 mo):

| Ref | Class | Pub | Re-check | Status |
|---|---|---|---|---|
| L12 (labour codes rollout) | regulatory | 2025-11 | **2025-12 — already due** | moving target; re-check model-rules finalisation before spec-lock |
| F4/F5 (EPF/ESI rates) | regulatory | 2026-09 | 2026-10 | re-check before launch |
| F6 (PT) | regulatory | 2026 | 2026-02 | re-check per-state slabs |
| F7 (LWF) | regulatory | 2026-07 | 2026-08 | re-check per-state gazettes |
| F8 (gratuity) | regulatory | 2026-09 | 2026-10 | re-check |
| F9 (TDS) | regulatory | 2026 | 2026-02 | re-check (FY 2026-27 rules) |
| F10 (form renaming) | regulatory | 2026-09 | — | OVERTURNED — closed |
| FA59-79, PWA7, L14-17 | regulatory | 2026-11 | 2026-12 | fresh |

Earliest re-check: the labour-code rollout line (already due). Every re-check is a Deepen pass on this run folder.
