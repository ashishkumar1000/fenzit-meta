# Earned-leave accrual — research digest (2026-11-18)

Three parallel research agents commissioned by the owner when the leave-accrual feature
entered epic 23 as story 23-13. Question: what does an SME Indian payroll product need for
per-tenant earned-leave programs (some tenants 2 leaves/month, some 1, some none), without
enterprise HRMS complexity?

## Agent 1 — Frappe HRMS (github.com/frappe/hrms)

- **Model**: Leave Type (single config doc: `is_lwp`, `is_carry_forward`, `allow_negative`,
  `include_holiday`, `max_leaves_allowed`, earned-leave block with frequency + rounding +
  allocate-on-day) → Leave Policy (rows of type + annual allocation) → Leave Period
  (company-scoped dates) → Leave Policy Assignment (employee, based on period / joining date /
  manual) → Leave Allocation → **Leave Ledger Entry** (event-sourced: every credit and every
  approved day is a dated ledger row; balance is always computed from the ledger, never stored).
- **Earned leaves**: allocated 0 up front; a daily scheduler credits the due amount per a
  precomputed `earned_leave_schedule`, pro-rates the joining month, rounds per type, caps at
  the annual quota. Failure emails to HR.
- **Over-balance**: `allow_negative` → warning + proceed; unset → `InsufficientLeaveBalanceError`.
  No auto-LWP conversion.
- **Per-company customisation**: Leave Type + Policy are GLOBAL (no company field); Period,
  assignments, allocations are company-scoped. Two companies can run different programs but
  share the type catalogue. (Our `leave_types` is already per-tenant — we get the
  differentiation one layer earlier.)
- **Payslip**: no leave detail beyond payment-days proration; LWP deducted via
  `payment_days -= lwp` (a parallel proration engine — clashes with our attendance-based LOP).

## Agent 2 — SME market scan (Zoho People, Keka, greytHR, RazorpayX, Gusto)

- **Common denominator**: configurable leave types with paid→LOP fallback; monthly or annual
  accrual with a credit-date choice; explicit negative-balance decision (block or allow-with-
  cap, never silent); excess leave converting to salary-deducted LOP; carry-forward with a cap;
  year-end processing (carry forward / encash / forfeit); encashment (thin in RazorpayX).
- **Enterprise-tier (small customers never touch)**: accrual rules by location/department/
  grade; probation-specific rates; expired-carry-forward quarantine types; grade-wise
  encashment caps; 50+ policy parameters.

## Agent 3 — our codebase hook points (fenzit-be / fenzit-app / fenzit-web)

- `leave_types` (migration 20261117110000): per-tenant, `paid boolean` is the only
  paid/unpaid resolution; NULL leave_type_id reads as paid (23-2).
- Apply flow: `leave.service.ts` `applyTransact` L180–460 — `attendance_lock_employee(tx)`
  L203 **already serialises per-employee writes**, so a balance check counting
  pending + approved is race-safe; validation lands after `validateApplyFacts` (L294–303).
- Freeing paths (revoke, cancel, check-in auto-cancel, disable sweep) all go through
  `leave-transition.ts`; because availed is DERIVED from `leave_request_days`, every freeing
  path restores balance with zero extra code.
- Payroll read: `payroll-run-engine.service.ts` L896–912 — approved days of `t.paid = false`
  → LOP. No balance read anywhere. Excess-to-LOP auto-conversion would need a per-day
  paid/unpaid resolution column; deferred in 23-13.
- Payslip: snapshot columns + `payslip.template.ts` — balance section slots after
  `sectionTitle('Total attendance')` (L319–329); must be captured at run time like
  `days_worked` (frozen snapshots for locked months).
- App: `src/features/attendance/leave/` — balance card sits at the top of
  `LeaveApplyScreen.tsx`/`LeaveApplyFields.tsx`; **no leaveTypeId plumbing exists in the app**
  (the 23-2 read-side defer) — BE 13's leave-types read endpoint is the prerequisite (story 14).
- Web: no leave config surface exists; pre-launch, accrual rates are set via the 23-2 admin
  API; UI rides a future web story.

## The cut (what 23-13 builds vs defers)

**Builds**: accrual rate on the per-tenant leave type (NULL = today); derived balance
(opening credits + accrued-as-of with join-month proration − pending+approved); apply-time
block (plain-English 422 LEAVE_INSUFFICIENT_BALANCE) or per-type allow-over-balance;
leave-types read for the app + balances endpoints (employee self, owner per-employee);
payslip leave-balance section captured at run time.

**Defers (each with the reason)**:
- *Excess-to-LOP auto-conversion* — needs a per-day resolution in the payroll read; the
  block/allow pair covers SME reality, and re-typing an approved leave already works.
- *Year-end carry-forward routine* — `leave_balance_credits` table is in the migration as the
  hook; manual opening credits via the admin API cover pre-launch.
- *Encashment* — off-cycle payout (23-9) already moves money outside the run.
- *Scheduler-based accrual* (Frappe's earned_leave_schedule + daily job + failure emails) —
  derived-on-read produces identical balances with zero background state.
- *Web config UI* — future web story; the 23-2 admin CRUD is usable pre-launch.
- *Negative-balance caps, credit-date choice, max-continuous-days, partial-paid fractions,
  block lists, optional/compensatory leaves, approver trees* — enterprise-tier per the market
  scan.

## Owner decisions (2026-11-18, applied to story 23-13)

1. **Two accrual modes per type** — monthly with a decimal rate (earned 2/month, sick
   0.5/month; half-day leave consumes 0.5) or an annual fixed grant (bereavement 5 or 6 or
   2 days, credited in full for the FY from day one, no pro-rating).
2. **All leave types are optional per tenant** — a company creates only the types it gives
   (already true from 23-2; no work).
3. **Carry-forward is owner-set per type and moves INTO scope** — only monthly-accrual
   types may carry forward; an annual fixed grant like bereavement never does. Derived on
   read from the prior FY's unused balance — no year-end routine, no scheduler.
4. **Starter set seeded automatically** for every company with no leave types:
   Earned Leave 1/month (carry-forward ON), Sick Leave 0.5/month (off), Bereavement annual
   fixed 0 days (blocks applications until the owner sets the number), Comp-Off no accrual
   paid (any time, any number, owner approves). Comp-off auto-crediting for worked
   off-days (with a use-by window) noted as a possible future story — not commissioned.
5. **Catalog revised to FIXED four types** (same day, supersedes the free-form starter
   set): every tenant sees exactly Earned / Sick / Bereavement / Comp-Off; they cannot be
   added or deleted; the owner edits VALUES only (accrual rate/days, carry-forward,
   over-balance, paid, enabled flag — a company without a type disables it instead). The
   accrual mode is inherent to each type (monthly/monthly/annual/none). The 23-2
   create/delete CRUD narrows to value PATCH + enable/disable; names not editable in v1.
