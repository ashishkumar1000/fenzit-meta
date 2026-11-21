# 26-7 — Payslip email delivery

| | |
|---|---|
| Status | ready-for-dev (card created 2026-11-21) |
| Size | S–M (~2–3 days) |
| Layer | BE (fenzit-be) |
| Depends on | none hard (26-1/26-6 make the content richer; ships fine without) |
| Contract | 05 §6 WI-G · 03 §10.D, §7.4 · 02 §3.5, §8.12 |

## Gap (evidence)

**No payslip delivery** — the notifications module has zero payroll hooks (03 §7.4);
employees must open the app to discover a payslip exists. Office staff without the
app never learn one came. Frappe auto-emails on slip submit with templates and bulk
send (02 §3.5) — table stakes we lack.

## Scope

1. Tenant setting `payslip_email: off | on_completion` (**default off**) on the
   payroll config surface.
2. Trigger: at the chosen single layer — recommend **run completion** (never per-slip
   AND per-run; Frappe's `via_payroll_entry` flag exists precisely because this
   doubles, gotcha 02-§8.12). Lock-time is the alternative if the owner prefers
   "only final numbers leave the building" — decide + pin once.
3. Email content: member name, period, gross/net + presigned PDF link (no attachment
   in V1 — link matches the R2 presign pattern; attachment is polish).
4. Missing email → skip reason in the run summary ("no email on file for X"), never
   an error (Frappe: msgprint-only, salary_slip.py:2417-2418).
5. No PHI in logs: log member id + run id, never amounts.

## Out of scope

Encrypted PDFs + password policy (LATER, agent 1 row 10), WhatsApp/SMS delivery
(MSG91 exists for OTP but payroll templates would need DLT registration — separate
work), custom email templates per tenant (single fixed template V1), employee
email-preference management.

## Technical approach

- Fire-and-forget via the existing notifications infrastructure; dedupe key
  `(run_id, member_id)` — a re-run regenerates the PDF (new presign) and may re-send
  the corrected slip; **pin the chosen re-run semantics in a test**: recommend
  re-send on re-run with the corrected numbers (an owner correcting a run wants the
  fix to reach people), but suppress if the run summary is unchanged.
- Rate-limit friendly: batch the queue (150 emails is fine; the notifications module
  already handles bursts for OTP).
- Sender/subject fixed for V1; body plain-English with the period and amounts.

## Acceptance criteria

1. Exactly one email per member per run, even on re-run (dedupe pinned by test).
2. Off by default; enabling is a payroll.config audit-written change.
3. Members without email → run-summary skip reason; the run still completes.
4. No amounts/PHI in any log line (test asserts log scrubbing).
5. Journey legs: completion-triggered send, re-run re-send, missing-email skip.

## Test anchors

- Single-layer invariant (02 §8.12) — the test that would have caught Frappe's
  double-send.
- Missing-email non-error (`salary_slip.py:2417-2418` semantics).

## References

Frappe: email_salary_slip (salary_slip.py:2379-2418) — template rendering w/ slip
context, bulk list email, password policy (`generate_password_for_pdf`, :2691-2694,
LATER for us); Payroll Settings `email_salary_slip_to_employee` default-on (we ship
off — deliberate).

## Risks / gotchas

- Email *delivery* reputation: payslip links are sensitive — presign expiry should be
  short (hours, not days) since the app re-issues on demand.
- Don't reuse OTP sender identity/templates (DLT registration is per-template).
- If the owner picks lock-time instead of completion, the lock confirmation flow must
  not block on email dispatch (async + status in summary).
