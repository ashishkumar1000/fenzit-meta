# Statutory verification — SPEC-payroll

Load-bearing legal citations, each verified by a dedicated internet deep-check in this spec's research run (accessed 2026-11-16/17). Companion of `SPEC.md`; the fixture's arithmetic depends on these. On legal matters, this file and the statutory digest supersede the research report.

## Wage slip — Form V, rule 52

- Code on Wages s.50(3) mandates wage slips; the operative form is **Form V, rule 52, Code on Wages (Central) Rules, 2026** (notified in the Gazette 8 May 2026), read verbatim from the Gazette during the deep-check. 12 fields incl. father's/mother's/spouse name, UAN, bank account number. Electronic issuance permitted; issued **on or before payment of wages**.
- The round-3 statutory digest's Q2 recorded the operative slip form as NOT FOUND (its "Form II" lead was wrong — Form II is a claims application). **Superseded by this verification** — CAP-7's field set traces to this section, which is why the companion set now includes it.
- Finalised state rules adopt the identical model form → the product ships the central template + a per-state "rules notified?" switch (acceptance: CAP-7).

## PF wage ceiling

- **₹25,000, effective 17 September 2026** — notification **S.O. 5109(E)** dated 17.09.2026; EPFO's own FAQ "Revision of EPFO Statutory Wage Ceiling" (table: effective 17 Sep 2026, revised ₹25,000, earlier ₹15,000, ~51 lakh additional employees); Cabinet approval 16.09.2026; KPMG flash alert 2026-249 (28.09.2026); PIB 31.10.2026. Applies to EPF, EPS and EDLI.
- One contrary secondary source (₹15,000 unchanged since 2014) was overturned by the tie-break reading of EPFO's FAQ PDF. **The config carries both values, effective-dated** (fixture §Effective dating; a 2026-09 run resolves ₹15,000).

## Excluded employee / new joiner above the ceiling

- Judicial line: SC *Pioneer India Entertainment* (2019) → Kerala HC *Sivasankaran* (2018/19) — post-first-coverage joiners above the ceiling cannot claim exclusion; **enrollment is the default**. EPFO's exclusion reading is administrative flux (Feb 2025 circular withdrawn Apr 2025; Jul 2025 draft unnotified). Product default: **enroll**; exclusion = admin configuration with an EPFO-flux warning; anyone ever an EPF member is covered at any wage (CAP-6, fixture variant E/H).
- The earlier "*P.F. Commissioner v. E. Sivasankaran* 2025" citation was a miscitation (an excluded-**establishment** case) and is deleted.

## PF contribution basis

- EPF Act **s.2(b)(ii)** (basic + DA + retaining allowance) and **s.6** — contribution on the basic wages **payable for the period** → the fixture's **earned basic** basis (window-prorated, LOP-reduced).
- Mid-month pro-rata with the ceiling applied to the period wage: EPFO circular **N-12/17/08/P&R/Part/110241 (08.08.2018)**; substance corroborated by practitioner worked examples (tax2win: 15,000 × 8/30 for a 22nd-of-month joiner). The earlier "HRM-4(2)17/2014/SS-III/1584 dated 27.01.2017" citation could not be located in any indexed source and is dropped (the 27.01.2017 order's exact number — /125 vs /1584 — is an Open Question).
- *ESIC v. M.M. Suri* is an ESI ruling and is **not** cited as PF authority.

## TDS — FY 2026-27

- Runs under the **Income-tax Act, 2025** (effective April 2026). New-regime slabs unchanged by Budget 2026: 0–4L nil · 4–8L 5% · 8–12L 10% · 12–16L 15% · 16–20L 20% · 20–24L 25% · >24L 30% (Bajaj table read this run; PIB Budget-2026 summary lists no direct-tax slab change). Standard deduction **₹75,000** unchanged.
- Rebate is **s.157** (renumbered 87A): resident-only, ₹60,000 = 100% of tax on income up to ₹12L, marginal relief above ₹12L. 4% health & education cess. New regime is the default without an employee declaration.
- Employer method (practitioner standard, CalcGuru Jul 2026): estimate **annual salary income**, apply slabs, **spread over the remaining FY months**, re-estimate and re-spread on revision. Open: the bare s.192/201 statutory wording and any small-employer exemption (SPEC Open Questions).

## Product-policy decisions (not statutory)

- **Month-start resolution** of effective-dated config (vs day-level) is product policy for determinism, not a statutory rule.
- Divisor conventions (26/30/calendar) are policy — no retrieved statute imposes one for LOP of salaried staff.
- The 50% cap base including off-cycle earnings (employer shares and recovery lines outside) is the product's reading of CoW s.18; verify the enacted rule text before legal freeze.
