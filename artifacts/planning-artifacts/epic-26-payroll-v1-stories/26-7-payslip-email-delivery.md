# 26-7 — Payslip email delivery

| | |
|---|---|
| Status | ready-for-dev (card created 2026-11-21; **revised after review** — transport decision pinned) |
| Size | M (~3–4 days — includes a minimal outbound-email transport) |
| Layer | BE (fenzit-be) |
| Depends on | none hard (26-1/26-6 make the content richer; ships fine without) |
| Contract | 05 §6 WI-G · 03 §10.D, §7.4 · 02 §3.5, §8.12 |

## Gap (evidence)

**No payslip delivery** — the notifications module has zero payroll hooks (03 §7.4);
employees must open the app to discover a payslip exists. Office staff without the
app never learn one came. Frappe auto-emails on slip submit with templates and bulk
send (02 §3.5) — table stakes we lack.

## Review correction (2026-11-21) — there is NO email transport today

The `src/notifications/` module is an **in-app inbox only** (CRUD over the
`notifications` table: list / unread-count / mark-read — zero send code). OTP delivery
is MSG91 **SMS inside auth** (`SMS_DELIVERY_PROVIDER: mock | msg91`); the only outbound
**email** in the BE is Supabase auth magic-link mail, which is not reusable for
arbitrary payroll mail. The original card's "existing notifications infrastructure /
handles bursts for OTP" premise was wrong. V1 therefore ships a **minimal
provider-agnostic outbound-email service** (SMTP creds via env; interface swappable),
one fixed template, no per-tenant templates. The MSG91/DLT caveat applies to SMS only —
this card does not use SMS.

## Scope

1. Tenant setting `payslip_email: off | on_completion` (**default off**) on the
   payroll config surface.
2. Trigger at ONE layer — **run completion** (post-commit, fire-and-forget; a send
   failure is logged, never fails the run or the lock). Lock-time is the alternative
   if the owner prefers "only final numbers leave the building" — decide + pin once.
3. Email content: member name, period, gross/net + **PDF attachment** rendered via the
   existing payslip worker path. **No presigned links in email V1**: the shipped
   presign TTL is 600 s with fresh-presign-on-read (payroll-payslips.service.ts:498-530)
   — an emailed link dies in 10 minutes and staff without the app have no re-issue
   path. An attachment avoids the link-TTL problem entirely; deep-link re-issue
   returns when an employee-facing web surface exists (post-V1).
4. Dedupe + re-run semantics (pinned): dedupe key `(run_id, member_id)`. Re-runs are
   new run rows, so a re-run MAY re-send — **a re-run re-sends only when the member's
   payslip snapshot (line set + net) differs from the prior run's; an identical
   re-run sends nothing** (comparison pinned by test).
5. Missing email → skip reason appended to the run summary in a **post-commit
   summary UPDATE** (no audit row — delivery metadata, not a payroll mutation; the
   runs-tab re-poll picks it up). Never an error (Frappe: msgprint-only,
   salary_slip.py:2417-2418).
6. No PHI in logs: member id + run id only, never amounts.

## Out of scope

Encrypted PDFs + password policy (LATER, agent 1 row 10), WhatsApp/SMS delivery
(DLT registration per-template — separate work), custom email templates per tenant,
employee email-preference management, bounce/complaint handling beyond logging.

## Technical approach

- New `email` module: transport interface + SMTP implementation (env-configured), a
  render function for the fixed template, and a fire-and-forget dispatcher used by the
  payroll completion hook. Mocked transport in tests.
- Snapshot comparison for re-runs: hash the member's payslip line set + net; compare
  against the prior run's hash for the same month (stored alongside the run summary or
  derived from the prior payslip rows).
- Attachment: reuse the payslip report render (deterministic per-request key) and
  attach the bytes; do not mint a presigned URL for the email.

## Acceptance criteria

1. Exactly one email per member per run execution; a re-run with a changed snapshot
   re-sends; an identical re-run sends nothing (both pinned by tests).
2. Off by default; enabling is a payroll.config audit-written change.
3. Members without email → run-summary skip via the post-commit update; the run
   completes; the console shows the skip.
4. No amounts/PHI in any log line (test asserts scrubbing).
5. Email send failure never fails the run, the lock, or the summary (logged only).
6. Journey legs: completion-triggered send, changed-snapshot re-send, unchanged
   re-run suppressed, missing-email skip.

## Test anchors

- Single-layer invariant (02 §8.12) — the test that would have caught Frappe's
  double-send.
- Missing-email non-error (`salary_slip.py:2417-2418` semantics); template rendering
  with slip context (`:2385-2389`).

## References

Frappe: email_salary_slip (salary_slip.py:2379-2418) — template rendering w/ slip
context, attach_print, enqueue, missing-email msgprint; `generate_password_for_pdf`
(:2691-2694, LATER for us); Payroll Settings `email_salary_slip_to_employee`
default-on (we ship off — deliberate).

## Risks / gotchas

- SMTP creds management on Render (env secrets); bounce handling = log-only in V1.
- Sending from a no-reply address: the template must say so and point to the owner/
  HR channel for queries.
- Do not reuse OTP sender identity/templates (DLT registration is per-template; SMS
  is a different pipeline anyway).
- If the owner picks lock-time instead of completion, the lock confirmation flow must
  not block on email dispatch (async + status in summary).
