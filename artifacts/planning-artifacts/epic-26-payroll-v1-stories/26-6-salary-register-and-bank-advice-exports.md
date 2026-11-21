# 26-6 — Salary register + bank advice exports (+ FY YTD columns)

| | |
|---|---|
| Status | ready-for-dev (card created 2026-11-21) |
| Size | M (~3–4 days) |
| Layer | BE (fenzit-be) + web (fenzit-web) |
| Depends on | 26-2 (type grouping); leans on 26-5's determinism test; 26-4 for employer-PF columns |
| Contract | 05 §6 WI-F · 03 §10.F · 02 §5, §8.15 |

## Gap (evidence)

**No exports at all** — no salary register, no bank advice/transfer file, no
accounting or statutory exports; the reports registry holds only payslip + attendance
+ job activity (03 §10.F). The owner's monthly operational loop (register → bank →
hand slips to employees) is uncovered; the run computes correctly and then stops.

## Scope

1. **Salary Register** (reports-registry entry, XLSX/CSV): month × employee grid —
   component columns grouped by 26-2 `type`, gross, each deduction, net, payable
   days, LOP days, employer PF (26-4 split), FY YTD earnings + FY YTD TDS columns.
2. **Bank Advice** (CSV + printable summary): employee, bank a/c, IFSC, rounded net,
   run reference; one row per non-skipped employee with bank details.
3. Both flow through the existing `report_requests` → R2 presign pipeline (queue,
   ready stamp, per-request keys — the payslip PDF pattern, 03 §2.10).
4. Web: exports section on the payroll surface (month picker, queued/ready states,
   download) — reuses report_requests states; payroll.config-gated.
5. Missing-bank-details employees appear in a warnings block on the advice, not as
   silent omissions.

## Out of scope

Accounting/journal export (V1.x, simple 2-line-per-component form when a CA asks),
statutory registers/ECR (deferred), per-employee payslip regeneration (exists since
23-8), bank API integrations (NEFT/IMPS push) — CSV out only. Note: Frappe's own
`mode_of_payment` slip field is a dead literal confirming bank files are not engine
core (02 App.B) — CSV is the right V1 shape.

## Technical approach

- Report types follow the shipped pattern: pure shape `validateParams`, worker-path
  tenant-scoped fetch, upload before ready stamp, deterministic per-request key
  (23-8 contract).
- **Totals integrity rule** (borrow #11): compute per-employee net from unrounded
  lines, round once per employee — the register's net column sum must equal the run
  summary net **exactly** (rounding-remainder never drifts across 150 rows).
- YTD columns: SUM of run lines across the FY per employee (26-1's openings included);
  the two-number discipline (borrow #1) makes FY sums trivial — full-cycle vs prorated
  amounts stay distinct.
- Large tenants: fetch batches per employee in the worker (the leave-list N+1 lesson:
  batch, don't page per row — a11564c incident).
- Register column layout is derived from the components present that month (not a
  fixed 40-column template) so tenants with 6 components get 6 columns.

## Acceptance criteria

1. Register net column-sum == run summary net exactly (pinned test, incl. a
   rounding-sensitive fixture case).
2. Bank advice rows == non-skipped employees with bank details; missing-details
   employees listed in the warnings block with plain-English copy.
3. Tenant isolation proven (cross-tenant probe test, the 23-9 pattern).
4. Export == grid semantics: register row per employee matches the payslip snapshot
   for the same month (spot-pinned legs).
5. Large-tenant path queued via report_requests (no synchronous megaresponse);
   PT429→429 pattern preserved.
6. payroll.config-gated on all routes; employee /me unaffected.

## Test anchors

- Rounding-remainder rule (02 §8.15, payroll_entry.py:722-736 analog).
- Determinism leg reuses 26-5's preview/run comparison harness.

## References

Frappe: `salary_register` + `bank_remittance` reports (02 §5 report inventory);
02 §7.2 row 3 (register + net table instead of JEs for a SaaS without GL).

## Risks / gotchas

- YTD columns for leavers/mid-year joiners: openings (26-1) must flow into FY sums or
  the register contradicts the payslip.
- XLSX vs CSV: CSV first if effort-constrained (bank advice needs CSV anyway); XLSX
  niceties (frozen header row) are polish.
- Component-column dynamism must be stable month-over-month for the same config —
  pin column order by component id, not name.
