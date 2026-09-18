# DLT SMS Template Registration — Ops Handoff

**Date:** 2026-09-18 · **Owner:** Ashish Kumar · **Source doc:** `artifacts/planning-artifacts/prd-otp-sms-msg91-2026-09-18.md` (§10)

One-pager for registering all Fenzit SMS templates on the Jio DLT portal and
wiring them into MSG91. Follow the steps in order — each needs the previous
approved.

---

## Account & portal facts

| Field | Value |
|---|---|
| Portal | https://trueconnect.jio.com/#/ (Jio Trueconnect) |
| Login | hello@fenzit.com |
| Entity (PE) ID | `1201178928684294441` |
| Header / sender ID to register | `FENZIT` |
| Category (all templates) | **Service Implicit**, type SMS |
| ⚠️ Payment deadline | ₹5,000 + GST annual subscription on Trueconnect — **pay by 17/10/2026** or registration lapses |

## Step order

1. **Pay** the ₹5,000 + GST subscription on Trueconnect (deadline above).
2. **Register header** `FENZIT` — 6 alphabetic chars, free, 1–3 business days.
3. **Register templates T1–T5 below** — submit all five **in one batch**
   (24–72h each). Paste content **exactly** — spelling, spacing, punctuation.
4. **PE–TM link** — in Trueconnect (Campaign → My Telemarketer), link the
   entity to **MSG91's telemarketer** so Jio routes accept MSG91 traffic.
5. **MSG91 panel mapping** — map Entity ID → sender ID (SMS → Sender ID → edit);
   create each template (SMS → Templates → Create) with its **DLT template ID**
   + exact approved content + `FENZIT` sender.
6. **Test DLT** in the MSG91 panel against one number per template.
7. **Record each approved DLT template ID** back into this sheet and send it to
   the dev team (they need the IDs + auth key configured server-side).

## Rules that cause rejection (apply to every template)

- Variables only as `{#var#}` — never `{{var}}` or `%s`. Max **3** variables per
  template, non-consecutive.
- Each variable value ≤ **30 characters** at send time (dev backend enforces).
- **Brand name must appear in the content** — that's the `- Fenzit Technology`
  footer; never remove it.
- Fixed URLs only from our own domain (`fenzit.com`) — public URL shorteners are
  banned.
- **Approved templates cannot be edited.** A wording change = register a new
  template. Finalise copy before submitting.

## Templates — launch set (submit together)

### T1 — OTP login (all users)

```
{#var#} is your Fenzit verification code. Valid for 5 minutes. Do not share it with anyone. - Fenzit Technology
```
Var 1 = 6-digit OTP.

### T2 — Technician invited (account created)

```
Hi {#var#}, you have been added as a technician on Fenzit by {#var#}. Download the app at fenzit.com/app and log in with this number to activate your account. - Fenzit Technology
```
Var 1 = technician first name · Var 2 = company name — can exceed 30 chars; the backend truncates at send time (don't extend this variable beyond 30 when composing).
⚠️ `fenzit.com/app` must resolve to the app-store link **before** submitting.

### T3 — Job assigned to technician

```
New job {#var#} for {#var#} service is scheduled for {#var#}. Open the Fenzit app for details. - Fenzit Technology
```
Var 1 = job number (e.g. `JB-2026-0042`) · Var 2 = service name · Var 3 = schedule (e.g. `12 Oct, 10:00 AM`).
(Reworded 2026-09-18: fixed text between every variable pair — the earlier
"New job {#var#} ({#var#})" had consecutive variables, a DLT rejection cause.)

### T4 — Job status update (owner; one template for started / completed / cancelled)

```
Job {#var#} update: status {#var#}, technician {#var#}. Check the Fenzit app for the latest status. - Fenzit Technology
```
Var 1 = job number · Var 2 = status label (`started` / `completed` / `cancelled`) · Var 3 = technician name.
(Reworded 2026-09-18: fixed text between every variable pair — the earlier
"Update for job {#var#}: {#var#}" had consecutive variables.)

### T5 — Job cancelled (technician)

```
Job {#var#} scheduled for {#var#} has been cancelled. No action is needed. - Fenzit Technology
```
Var 1 = job number · Var 2 = original schedule date-time.

### Later (do NOT register yet)

T6 reschedule · T7 reassignment · T8 customer "technician on the way" — flows
still being built; see PRD §10.2. No payment/invoice templates — that feature
doesn't exist.

## Approved template IDs (fill in after approval)

Record the **exact template string that succeeded in MSG91's Test DLT** per
template (column 3) — that value is what the dev team puts in
`MSG91_OTP_TEMPLATE_ID` (DLT ID and MSG91 panel ID can differ).

| Template | DLT Template ID | Value that worked in Test DLT | Approved on | MSG91 status |
|---|---|---|---|---|
| T1 OTP | | | | |
| T2 Technician invite | | | | |
| T3 Job assigned | | | | |
| T4 Job status | | | | |
| T5 Job cancelled | | | | |

## If a template is rejected

Check: variable syntax, category (must be Service Implicit), brand name present,
>3 variables, or wording mismatch. Fix and re-register as a **new** template.
Help: Jio.ISOMCCSupport@ril.com · support@msg91.com