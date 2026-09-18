---
title: "PRD: Real OTP Delivery via MSG91 SMS (DLT) — replacing the mock OTP flow"
status: final
created: 2026-09-18
updated: 2026-09-18
scope: cross-repo (fenzit-be primary, fenzo-app minor)
owner: Ashish Kumar
decisions:
  - Backend keeps OTP generation + verification; MSG91 is delivery-only (confirmed 2026-09-18)
  - Mock provider + `otp` response field stay for dev/test; stripped in production (confirmed 2026-09-18)
  - SMS only this phase; WhatsApp OTP (Interakt/Wati) deferred to a future phase (confirmed 2026-09-18)
  - Pluggable provider architecture locked in §11 — new providers = one adapter file + one registry entry, never a rewrite (confirmed 2026-09-18)
  - Ports are named and shaped per CHANNEL, not per message type: `OtpDeliveryProvider` renamed to `SmsDeliveryProvider` with a generic `send(to, templateId, variables)` signature — OTP is one message type above it, notifications reuse the same port (confirmed 2026-09-18)
  - PRD validated 2026-09-18 (BMAD rubric + adversarial review, grade Fair, all dimensions strong); 6 high findings applied as fixes — env-gated dev OTP field (EXPOSE_DEV_OTP, never provider-gated), crypto.randomInt generation, T3/T4 rewording for DLT's non-consecutive rule, T2–T5 senders explicitly out of scope, multi-variable endpoint mapping pinned as future adapter work
---

# PRD: Real OTP Delivery via MSG91 SMS (DLT)

## 0. Document Purpose

This PRD defines the work needed to replace Fenzit's dummy OTP flow with real SMS
OTP delivery, using **MSG91** as the SMS gateway and the **Jio Trueconnect DLT**
registration (entity approved 2026-09-17, entity ID `1201178928684294441`) as the
regulatory pipeline. It covers both repos: `fenzit-be` (primary) and `fenzo-app`
(minor cleanup).

The current flow is explicitly marked "Critical before any production
deployment" in the central deferred-work log (`artifacts/implementation-artifacts/deferred-work.md`, W1):
**the verify endpoint accepts any 6-digit code** and the **send endpoint returns
the plaintext OTP in the HTTP response**. This PRD closes both.

## 1. Vision

A new user enters their Indian mobile number in the app and receives a real 6-digit
OTP over SMS within seconds, delivered through a TRAI-compliant DLT-approved
route. Verification is done by our own backend against the already-hashed session
code. The existing API contract, session store, rate limiting, and lockout
behaviour are preserved — only the delivery leg changes. Development continues to
work without spending real SMS money (mock provider in dev/test).

## 2. Current State (Gap Analysis)

### Wired and working

| Piece | Location | Status |
|---|---|---|
| OTP generation + bcrypt hash | `fenzit-be/src/auth/auth.service.ts:84-85` | 6-digit random, bcrypt cost 10 |
| OTP session store (in-memory, 5-min TTL) | `fenzit-be/src/auth/in-memory-otp-session.store.ts` | Keys `otp:session:{id}`, rate key `otp:rate:{e164}` |
| Rate limiting (5 sends / 10 min per number, 429 + Retry-After) | `auth.service.ts:67-82` | Working |
| Attempt lockout (5 wrong attempts → locked) | `auth.service.ts:143-147` | **Dead code** — never exercised (see gap) |
| `SmsDeliveryProvider` abstraction (today named `OtpDeliveryProvider` — renamed in this PRD, see §11) | `fenzit-be/src/auth/otp-delivery.provider.ts` | DI seam ready for a real provider |
| `MockSmsDeliveryProvider` (today `MockOtpDeliveryProvider`) | `fenzit-be/src/auth/mock-otp-delivery.provider.ts` | Logs the code; wired in `auth.module.ts:19-22` |
| Custom JWT issuance (Supabase-compatible claims) | `auth.service.ts:182-186` | Working, no `exp` (separate concern, out of scope) |
| FE auth flow (phone → otp → profile) | `fenzo-app/src/features/auth/AuthFlow.tsx` | Contract-driven, error-code handling in place |
| FE OTP screen (6-digit input, 45s resend) | `fenzo-app/src/features/auth/screens/OtpScreen.tsx` | Working, plus a `__DEV__` banner fed by the response OTP |

### Missing / broken (the gaps this PRD closes)

1. **Verification is a stub** — `auth.service.ts:139-140`: `const isValid = true;`
   with a "Phase 2" comment. Any 6-digit code logs the user in. This is W1 in
   `deferred-work.md`.
2. **Plaintext OTP in the API response** — `sendOtp` returns `otp` in the body
   (`auth.service.ts:108`) and logs it (`auth.service.ts:99`). The FE consumes it
   for the dev banner (`AuthFlow.tsx:71-76,94`; `OtpScreen.tsx:104-108`;
   typed in `authApi.ts:29-41`).
3. **No real delivery provider** — only the mock exists. No MSG91 code, no env
   vars (`fenzit-be/.env.example` has no OTP/SMS section).
4. **No DLT-side artifacts yet** — entity registration is approved, but the
   header (sender ID), content template, PE–TM linking, and MSG91 panel mapping
   are all pending (operational, not code — see §8).

## 3. Target User Journeys

### 3.1 New owner signup (production)

1. Enters 10-digit mobile number → app calls `POST /auth/otp/send`
   (`{ countryCode: "+91", phoneNumber }`).
2. Backend rate-limits (existing 5/10 min), generates the 6-digit code,
   bcrypt-hashes it into a 5-minute session, and calls the new
   `Msg91SmsDeliveryProvider`, which POSTs to MSG91's v5 OTP endpoint with the
   DLT template ID and the OTP value.
3. User receives SMS from the approved sender ID (e.g. `FENZIT`):
   "123456 is your Fenzit verification code. …" typically within seconds.
4. Enters the code → `POST /auth/otp/verify` → `bcrypt.compare()` against the
   session hash → wrong code increments attempts (5 → session locked);
   right code issues the JWT (flow unchanged from here).
5. Expired/locked session → same `OTP_EXPIRED` / `OTP_SESSION_LOCKED` recovery
   as today (back to step 1).

### 3.2 Returning user / invited technician — unchanged

Technician first-login auto-activation, owner tenant routing, company setup —
no changes.

### 3.3 Developer (dev/test)

`NODE_ENV=development|test` → `MockSmsDeliveryProvider` stays wired; with
`EXPOSE_DEV_OTP=true` (FR-BE5) the `otp` field remains in the `sendOtp`
response and the `__DEV__` banner keeps
working. Zero real SMS spend in dev.

## 4. Functional Requirements

### 4.1 Backend — delivery provider (fenzit-be)

- **FR-BE0**: Rename the existing port to a **channel name** (ports are
  per-channel, not per-message type — §11): `OtpDeliveryProvider` →
  `SmsDeliveryProvider` in `fenzit-be/src/auth/sms-delivery.provider.ts`
  (file renamed from `otp-delivery.provider.ts`; `MockOtpDeliveryProvider` →
  `MockSmsDeliveryProvider` in `mock-sms-delivery.provider.ts`; no compat shims
  — pre-launch). Its signature generalises from `send(phone, otp)` to the
  channel's message model — every DLT SMS is an approved template + variables:
  ```ts
  export abstract class SmsDeliveryProvider {
    /** Send a DLT-approved template message. `variables` fills the
     *  template's `{#var#}` slots in order (DLT caps at 3). */
    abstract send(to: string, templateId: string, variables: string[]): Promise<void>;
  }
  ```
  OTP login becomes one caller of this port — `send(phone, T1_TEMPLATE_ID, [otp])`.
- **FR-BE1**: New `Msg91SmsDeliveryProvider extends SmsDeliveryProvider` in
  `fenzit-be/src/auth/`, mirroring the existing `PlacesProvider`/
  `MockPlacesProvider` DI-swap convention. Its `send(to, templateId, variables)`
  POSTs to `https://control.msg91.com/api/v5/otp` with:
  - query: `template_id` (DLT-approved template mapped in the MSG91 panel),
    `mobile` (number with country code, no `+`, e.g. `919876543210`),
    `otp` (`variables[0]` — our backend-generated code), `otp_expiry`
    (5, matching `OTP_TTL_SECONDS`);
  - header: `authkey` (account auth key — **header, not query param**;
    MSG91's verify endpoint rejects query-param auth keys, and header
    transport keeps the secret out of URLs/logs);
  - timeout via `AbortSignal.timeout(4000)` (same as `GooglePlacesProvider`);
  - success predicate: HTTP 2xx with body `{"type": "success"}` — any
    `{type: "error"}` body or non-2xx counts as failure (FR-BE4);
  - the value configured as `MSG91_OTP_TEMPLATE_ID` is **exactly the string
    MSG91's send call accepts** — captured during §8 step 5's "Test DLT" run,
    not assumed from the Trueconnect approval (DLT ID vs MSG91 panel ID can
    differ; see §10.4);
  - **endpoint scope**: the v5 `/otp` endpoint carries a single `otp` param, so
    this FR serves T1 (single variable). Multi-variable templates (T2–T5) go
    through MSG91's transactional/flow SMS endpoint when their sender work is
    built — a second method inside this adapter (§11 AD-2: vendor detail,
    invisible to the port; the port itself is unchanged). That endpoint's
    mapping is designed in the T2–T5 sender story, not here.
- **FR-BE2**: Provider selection at composition root (`auth.module.ts`) via the
  config-driven registry factory defined in §11 (AD-3) — not `useClass`:
  `NODE_ENV=test` → `MockSmsDeliveryProvider` (never burns real SMS in CI);
  otherwise `SMS_DELIVERY_PROVIDER=mock|msg91` decides (default `msg91` in
  production, `mock` in development until keys are configured). Same
  env-driven selection pattern as `PlacesProvider`.
- **FR-BE3**: New env vars in the Joi schema (`app.module.ts`) + `.env.example`
  + `render.yaml`: `MSG91_AUTH_KEY`, `MSG91_OTP_TEMPLATE_ID`,
  `SMS_DELIVERY_PROVIDER`, `EXPOSE_DEV_OTP` (FR-BE5). Auth key and template ID
  are server-side only and must never reach the mobile client. Joi validates
  cross-field: when `SMS_DELIVERY_PROVIDER=msg91`, `MSG91_AUTH_KEY` (non-empty)
  and `MSG91_OTP_TEMPLATE_ID` are required — the app refuses to boot
  otherwise, so a bad config flip is a boot error, not a runtime login outage.
- **FR-BE4**: Delivery failure handling — if the MSG91 call throws or returns a
  non-success response, the endpoint fails with `502 OTP_SEND_FAILED` (new
  error code in `error-code.enum.ts`). The rate-limit counter already having
  incremented is accepted (prevents bypassing the limit via a failing
  provider). Session deletion is failure-specific: when the failure is
  determined **before** the request could have been dispatched (connection
  error, non-success body), the just-created session is deleted; on **timeout**
  (`AbortSignal` fired) the session is **kept** — MSG91 may have already
  dispatched and the SMS can still arrive — and the outcome is logged for
  diagnosis (semantics pinned by FR-T4).
- **FR-BE5**: The `sendOtp` response includes `otp` **only when the
  environment allows it — never based on which provider is active** (a
  provider-identity check inside the service is banned by §11's anti-pattern
  list). The gate is a config flag: `EXPOSE_DEV_OTP=true` set only in
  dev/test compose and CI; absent (default false) in staging/production.
  Production never sees the field regardless of provider — including §9's
  step-1→step-3 window when production deliberately runs the mock (internal
  testers use the mock's log line in that window). The service-level plaintext
  log (`auth.service.ts:99`) is **deleted, not gated** — the mock provider's
  own log already covers dev.

### 4.2 Backend — real verification (fenzit-be)

- **FR-BE6**: Replace the stub at `auth.service.ts:139-140` with
  `await bcrypt.compare(otpCode, session.otpHash)` — activating the existing
  attempt-increment and lockout logic, **with two corrections to the existing
  code**: (a) the OTP is generated with `crypto.randomInt(100000, 1000000)`
  instead of `Math.random()` (`auth.service.ts:84`) — real verification
  deserves a CSPRNG, not a predictable generator; (b) on a failed attempt the
  session is re-stored with its **remaining** TTL, not the full
  `OTP_TTL_SECONDS` (the current code resets the 5-minute clock on every wrong
  attempt — a session could live ~25 minutes and outlive its advertised
  `expires_at`). This closes deferred work W1.
- **FR-BE7**: No API contract changes: `POST /auth/otp/send` still returns
  `{ otp_session_id, expires_at }` (plus `otp` in dev per FR-BE5);
  `POST /auth/otp/verify` contract unchanged. `docs/api-contracts.md` updated in
  the same change (remove the "verify accepts any 6-digit code" Phase-1 note).
- **FR-BE8**: Delivery-outcome logging (structured, no PII beyond the E.164
  already logged today): provider name, outcome (`ok | timeout | error`),
  duration, and MSG91 response type — sufficient to compute §7's metrics by
  log query. Plus one weekly manual check of the MSG91 wallet balance during
  the launch window (pay-as-you-go spend is otherwise invisible until it
  runs out).

### 4.3 Frontend (fenzo-app)

- **FR-FE1**: Remove the `otp?: string` field from `SendOtpResponse`
  (`src/services/resources/authApi.ts:29-41`).
- **FR-FE2**: Remove the `devOtp` state and plumbing from `AuthFlow.tsx`
  (`:71-76, 94, 155, 256`) and the DEV OTP banner from `OtpScreen.tsx`
  (`:104-108`).
- **FR-FE3**: Handle the new `OTP_SEND_FAILED` error code in
  `sendOtpErrorMessage` (`AuthFlow.tsx:34-43`) with retry copy, e.g. "Couldn't
  send the code. Please try again." Also handle `RATE_LIMIT_EXCEEDED` on the
  OTP screen with a countdown derived from the backend's `Retry-After` (already
  returned), resend disabled for that window — with real delivery,
  resend-until-arrival at the screen's 45 s cadence reaches the 5/10-min cap
  in ~3–4 minutes, so 429 is a normal user path, not an edge case.
- **FR-FE4**: No changes to screens' design, navigation, or the verify/retry
  UX — the contract is stable.

### 4.4 Tests

- **FR-T1**: `auth.service.spec.ts` extended: correct OTP verifies; wrong OTP
  increments attempts and locks at 5 (`OTP_SESSION_LOCKED`); expired session →
  `OTP_EXPIRED`.
- **FR-T2**: New provider tests: `Msg91SmsDeliveryProvider` builds the expected
  request (URL, template id, mobile format, authkey header) and maps MSG91
  error responses to provider failures (mocked fetch — no real HTTP, no real
  SMS in CI).
- **FR-T3**: Existing integration specs keep passing with the mock provider
  (provider selection per FR-BE2 makes this automatic under `NODE_ENV=test`).
- **FR-T4**: Failure-path semantics pinned: provider failure before dispatch
  deletes the session (FR-BE4); provider timeout keeps it; a failed attempt
  does not extend the session past its advertised `expires_at` (FR-BE6);
  `OTP_TTL_SECONDS` stays 300 — its value is coupled to T1's approved
  "Valid for 5 minutes" wording (§10.1), so the test fails loudly if anyone
  changes the constant without re-registering T1.

## 5. Non-Goals

- **WhatsApp OTP** (Interakt/Wati BSP, from the original architecture's Phase 2
  plan) — deferred; the `SmsDeliveryProvider` seam already leaves room for it
  (§11 AD-5).
- **MSG91-managed OTP engine** (their send/verify/reqId flow) — rejected in
  favour of backend verification (confirmed 2026-09-18); discarding our session
  store/lockout would be a net regression.
- **JWT expiry / refresh tokens** — separate deferred item; the never-expiring
  login JWT predates and survives this PRD.
- **Redis-backed OTP session store** — only needed for multi-instance
  deployment; single Render instance today. The `OtpSessionStore` interface
  already isolates this swap.
- **Consent templates, promotional SMS, non-OTP templates** — not needed for
  login.
- **OTP autofill / SMS-retriever native integration** — the `OtpInput` UX stays
  manual; can be a follow-up.
- **International numbers beyond `+91`** — the DTO allows 6–15 digits and the
  MSG91 call is country-agnostic, but India-only is the tested, DLT-registered
  reality this phase.
- **T2–T5 sender implementation** (technician-invite SMS, job-event sends, the
  `notifications`-subscriber SMS worker) — out of scope for this PRD. The
  templates ride along with the §8 batch registration (per-template approval,
  no batch coupling), and approved template IDs are stored (§10.4) until the
  future notifications story builds the senders (§10.1's "Backend:" lines are
  design notes for that story, not commitments of this PRD).

## 6. Dependencies & Assumptions

- **MSG91 account** — created (wallet top-up needed; pay-as-you-go, ~₹0.20–0.25
  per OTP SMS + 18% GST).
- **DLT entity** — approved on Jio Trueconnect (entity ID
  `1201178928684294441`); **₹5,000 + GST annual subscription must be paid on
  trueconnect.jio.com by 17/10/2026** or registration lapses.
- **DLT header + template** — to be registered (§8); code work can proceed and
  be tested against the mock while these pend, but **production rollout of the
  msg91 provider is blocked until the template is approved** (no template ID to
  send with).
- **Assumption**: single backend instance (in-memory session store sufficient).
  Two accepted risks ride with it: (a) every process restart/deploy invalidates
  all in-flight OTP sessions and resets rate windows — a user who received a
  code just before a deploy gets `OTP_EXPIRED` for a just-received code;
  acceptable at launch traffic, revisit if deploys × signups make it visible
  (deploy at low-traffic times meanwhile); (b) the store's rate-limit increment
  is non-atomic (its own code comment says so) — worst case ~2× the 5/10-min
  cap under a concurrent burst; accepted while SMS spend is small, and
  per-key serialization in the in-memory store is a one-method fix if it
  ever matters.
- **Pre-launch context**: no real users yet (per project memory) — no
  backward-compatibility shims needed; the dev-only response field can simply
  disappear in production.

## 7. Success Metrics

- Wrong/absent OTP can no longer log anyone in (`bcrypt.compare` enforced) —
  verified by tests and by manual prod check.
- No plaintext OTP in any production API response or log line — asserted at
  the §9 step-3 flip by checking the live response carries no `otp` key.
- OTP SMS delivered within ~5 s of request on Indian numbers (MSG91's direct
  carrier routes typically 1–2 s) — computed from FR-BE8's structured delivery
  logs.
- End-to-end signup (send → verify → JWT) success rate ≥ 98% of attempts that
  respect the rate limit — computed from FR-BE8's structured logs (send
  outcomes + verify outcomes per session).
- Counter-metrics: OTP send failure rate (watch > 2%); verify abandonment
  after successful delivery (signals UX friction); SMS spend per signup (from
  the weekly wallet check).
- Zero real SMS spend in dev/CI runs.

## 8. Operational Prerequisites (DLT checklist — outside the repos)

Ordered; each needs the previous approved:

1. **Pay the DLT subscription** (₹5,000 + GST) on
   [trueconnect.jio.com](https://trueconnect.jio.com/#/) — deadline
   **17/10/2026**.
2. **Header (sender ID) registration** — 6 alphabetic characters, e.g.
   `FENZIT` (transactional/Service Implicit headers are alphabetic). Free,
   approval 1–3 business days.
3. **Content template registration** — category **Service Implicit**, SMS type,
   associated with the header. TRAI/DLT constraints: only `{#var#}` variables,
   max 3 non-consecutive variables (ideally 1; ≤30 chars each) — fixed text
   between every variable pair — and the **brand name must appear in the
   content** or the template is rejected. Proposed content:

   ```
   {#var#} is your Fenzit verification code. Valid for 5 minutes. Do not share
   it with anyone. - Fenzit Technology
   ```

   (Single variable; brand name from the registered entity name. Approval
   24–72 h. Templates cannot be edited after approval — register a new one if
   the wording changes.)
4. **PE–TM linking** — in Trueconnect (Campaign → My Telemarketer), link the
   entity to **MSG91's telemarketer** so Jio's DLT accepts MSG91-routed traffic.
5. **MSG91 panel mapping** — map the DLT **entity ID** to the sender ID
   (SMS → Sender ID → edit), then create the template in MSG91 (SMS →
   Templates → Create) pasting the **DLT template ID** and exact approved
   content; use MSG91's "Test DLT" against one number before rollout. The
   string that succeeds in the Test DLT run is what goes into
   `MSG91_OTP_TEMPLATE_ID` (record it — DLT ID and MSG91 panel ID can
   differ).
6. **Configure** `MSG91_AUTH_KEY` + `MSG91_OTP_TEMPLATE_ID` in Render and flip
   `SMS_DELIVERY_PROVIDER=msg91`.

Registration on one operator's DLT portal is valid across all Indian networks —
Jio registration covers Airtel/Vi/BSNL deliveries.

The OTP template (step 3) is template **T1** of the full registration sheet in
§10 — the ops team should register T1–T5 (the launch set) together in one
batch once the header from step 2 is approved. Registration is ops work and
does not imply backend work: **T2–T5 sender implementation is out of scope for
this PRD** (§5) — approved template IDs are stored (§10.4) until the future
notifications story builds the senders.

## 9. Deployment Order (cross-repo)

`fenzo-app` and `fenzit-be` deploy independently; this PRD's change is
**additive-first**:

1. **fenzit-be first**: provider + real verification + env schema lands with
   `SMS_DELIVERY_PROVIDER=mock` (or unset → mock in dev); no FE breakage — the
   verify flip doesn't break the existing app because real codes are already
   being entered end-to-end.
   *Note*: flipping verification on **breaks nothing but does invalidate the
   "any code works" convenience** — with `EXPOSE_DEV_OTP` unset in production
   (FR-BE5), internal testers in the production window use the mock's **log
   line** (the response `otp` field exists in dev/test only). At the step-3
   config flip, assert the live response carries no `otp` key (§7).
2. **fenzo-app second**: remove the dev OTP plumbing + add
   `OTP_SEND_FAILED` handling (safe to merge any time after step 1, and
   `__DEV__`-gated today so even merging first is harmless in release builds —
   but the stated order is BE → FE).
3. **Config flip last** (§8 step 6) — enables real SMS in production; no code
   deploy.

## 10. Notification SMS Templates — DLT Registration Sheet (ops handoff)

> Hand this section to the ops team registering templates on Jio Trueconnect,
> or hand the standalone one-pager:
> `artifacts/planning-artifacts/ops-dlt-sms-template-registration-2026-09-18.md`
> (same content, formatted for ops — includes the approved-template-ID table to
> fill in).
> All templates below are **Service Implicit / SMS** on the registered entity —
> no consent templates needed (all go to our own logged-in users; the customer
> templates are second-wave and get their own consent review).
> Rules baked into every template: `{#var#}` variables only, max 3 (ideally 1),
> **non-consecutive** — fixed text between every variable pair —, ≤30
> characters per variable value, brand name in content.
> **Templates cannot be edited after approval** — wording below is final-candidate;
> confirm before submitting. Content must be pasted exactly (spelling, spacing,
> punctuation) into both Trueconnect and the MSG91 template panel, and the DLT
> template ID must then be recorded back into this sheet.

**Registration context** (same for every template below):

| Field | Value |
|---|---|
| Portal | https://trueconnect.jio.com/#/ (Jio Trueconnect) |
| Entity (PE) ID | `1201178928684294441` |
| Header / sender ID | `FENZIT` (register first if not yet approved) |
| Category | Service Implicit (SMS type) |
| Template registration fee | None (header + templates are free) |
| Approval time | 24–72h per template |

### 10.1 Launch set — register together in one batch

**T1 — OTP login** (all users; already covered in §8)

```
{#var#} is your Fenzit verification code. Valid for 5 minutes. Do not share it with anyone. - Fenzit Technology
```

| Var | Filled with | Max length note |
|---|---|---|
| 1 | 6-digit OTP | 6 chars — safe |

- Backend: `Msg91SmsDeliveryProvider` sends this via MSG91 v5 `/otp` (`otp` param).
- Blocker before registration: none (flow exists).
- ⚠️ `OTP_TTL_SECONDS` is coupled to this wording ("Valid for 5 minutes") —
  changing the TTL constant requires re-registering T1 as a new template.
  Treat the constant as frozen (FR-T4 pins it with a test).

**T2 — Technician invited / account created** (recipient: technician's phone)

```
Hi {#var#}, you have been added as a technician on Fenzit by {#var#}. Download the app at fenzit.com/app and log in with this number to activate your account. - Fenzit Technology
```

| Var | Filled with | Max length note |
|---|---|---|
| 1 | Technician first name | short — safe |
| 2 | Company name (`tenants.company_name`) | **can exceed 30 chars — backend must truncate; ops: do not extend this variable beyond 30** |

- Backend: new — sent by `inviteTechnician` after the users row commits.
- Depends on: `fenzit.com/app` resolving to the app-store link (own domain, no
  public URL shortener — shorteners get DLT-rejected). Confirm the link works
  before registering; the URL is fixed template text.

**T3 — Job assigned to technician** (fires on `create_job_with_log` commit)

```
New job {#var#} for {#var#} service is scheduled for {#var#}. Open the Fenzit app for details. - Fenzit Technology
```

| Var | Filled with | Max length note |
|---|---|---|
| 1 | Job number (`JB-2026-0042` format) | 13 chars — safe |
| 2 | Service / skill name (`skills.name`) | keep ≤30 (catalog names are short) |
| 3 | Schedule date-time (formatted IST) | keep ≤30 — backend formats, e.g. `12 Oct, 10:00 AM` |

> Reworded 2026-09-18: the earlier "New job {#var#} ({#var#})" put two
> variables back-to-back (separated only by punctuation), which violates DLT's
> non-consecutive-variable rule and would likely be rejected. Fixed text now
> sits between every variable pair.

**T4 — Job status update, generic** (owner; one template covers started /
completed / cancelled / future step labels — mirrors the existing
`notifications` payload `{job_number, step, technician_name}`)

```
Job {#var#} update: status {#var#}, technician {#var#}. Check the Fenzit app for the latest status. - Fenzit Technology
```

| Var | Filled with | Max length note |
|---|---|---|
| 1 | Job number | 13 chars — safe |
| 2 | Status label (e.g. `started`, `completed`, `cancelled`) | short — safe |
| 3 | Technician name | **can exceed 30 — backend truncates** |

> Reworded 2026-09-18: the earlier "Update for job {#var#}: {#var#}" put two
> variables back-to-back (violating DLT's non-consecutive rule); fixed text
> now sits between every variable pair.

- Backend: SMS worker subscribes to `notifications` inserts (the table is
  already the designed Phase-2 outbox) rather than new calls inside services.
- Known gap: the Cloudflare Worker attachment path skips owner notifications
  (deferred-work L169) — same gap applies to SMS if mirrored.

**T5 — Job cancelled — technician** (fires on `update_job_with_log p_cancel`)

```
Job {#var#} scheduled for {#var#} has been cancelled. No action is needed. - Fenzit Technology
```

| Var | Filled with | Max length note |
|---|---|---|
| 1 | Job number | 13 chars — safe |
| 2 | Original schedule date-time | keep ≤30 — backend formats |

### 10.2 Second wave — register later, when flows justify spend

- **T6 — Reschedule (technician)**: `Job {#var#} has been rescheduled to {#var#}. Open the Fenzit app for details. - Fenzit Technology`
  *Needs backend work first: no activity-log event exists today for a pure
  schedule change.*
- **T7 — Reassignment (old + new technician)**: `Job {#var#} has been reassigned. Check the Fenzit app for your latest jobs. - Fenzit Technology`
- **T8 — Customer "technician on the way"** (customers have no app login; phone
  is already on the job): `Your technician {#var#} is on the way for your {#var#} service. - Fenzit Technology`
  *New SMS surface — decide consent/opt-out handling before registering.*

### 10.3 Deliberately not registered

- Payment / invoice / amount SMS — no payment features exist; `tenants.upi_vpa`
  is stored-only. Do not register placeholders for flows that don't exist.
- OTP-adjacent "welcome" SMS — the OTP message itself covers signup; extra SMS
  is spend without signal.

### 10.4 After approval (ops checklist)

1. Record each approved DLT template ID next to its template above.
2. In the MSG91 panel (SMS → Templates → Create): paste the DLT template ID +
   exact approved content, select the `FENZIT` sender.
3. Use MSG91's **Test DLT** against one number per template before rollout —
   and record **the exact template string that succeeded** in the test; that
   value is what goes into `MSG91_OTP_TEMPLATE_ID` (DLT ID and MSG91 panel ID
   can differ; FR-BE1).
4. Rejection? Fix per the common causes (variable syntax, category mismatch,
   missing brand name, >3 variables, **consecutive variables**) and
   re-register as a **new** template — approved templates can't be edited.

### 10.5 Open items (consolidated)

- **T2**: confirm `fenzit.com/app` resolves to the app-store link **before**
  submitting — the URL is fixed template text (§10.1).
- **T6**: no activity-log event exists today for a pure schedule change —
  backend work needed before this template is useful.
- **T8**: decide consent/opt-out handling before registering (customers are a
  new SMS surface, not logged-in users).
- **T2–T5 backend senders**: out of scope for this PRD (§5) — future
  notifications story; store approved IDs until it starts.

## 11. Extensibility Architecture — Pluggable Provider Adapters

**Goal (user requirement, 2026-09-18):** adding a provider tomorrow (Twilio,
Gupshup, Wati/Interakt WhatsApp, anything else) must be *write one adapter +
register it* — never a rewrite. MSG91 is the first adapter, not a dependency.

**Pattern: Ports & Adapters (hexagonal), with per-channel ports and a
config-driven provider registry.** This is the established industry shape for
multi-provider messaging systems — FireflyFramework.Notifications
(`ISmsProvider`/`IEmailProvider` ports, vendor adapters in separate packages)
and the unified MessagingGateway (`ProviderRegistry` + provider bundles, zero
core changes to add a provider) are the two reference implementations (§12).

### Architecture decisions

**Naming rule (user correction, 2026-09-18): ports are named and shaped per
CHANNEL, never per message type.** OTP, technician invite, job updates are
*message types* — any of them can travel over any *channel* (SMS, WhatsApp,
email). A channel port therefore gets the channel's name and the channel's
generic message model (for DLT SMS: template + variables), and every message
type is just a caller above it. `OtpDeliveryProvider` was the wrong name for
this — it becomes `SmsDeliveryProvider`.

- **AD-1 — The port is narrow and never changes.** `SmsDeliveryProvider`
  (`send(to, templateId, variables): Promise<void>`) is the *SMS channel* port.
  The signature is the channel's message model — DLT SMS is always an approved
  template + `{#var#}` values — so any message type (T1 OTP, T2 invite, T3 job
  assigned …) calls the same port with its own template ID and variables.
  Business code depends only on this abstract class — it must never import a
  vendor SDK, vendor type, or vendor response shape. The port signature is
  frozen; adapters vary. (If a message type needs more than the template model
  one day, that is a new port — not a change to this one.)
- **AD-2 — One adapter per provider, one file each.**
  `mock-sms-delivery.provider.ts`, `msg91-sms-delivery.provider.ts`, and
  future `twilio-sms-delivery.provider.ts` etc. all extend the same abstract
  class and live flat in `src/auth/` (split into a folder only if the count
  grows past ~4). An adapter's whole job: translate the port call into vendor
  HTTP calls and normalize errors — nothing else. (How a given provider
  handles message kinds internally — e.g. MSG91's OTP endpoint vs its
  transactional SMS endpoint — is vendor detail and belongs inside the
  adapter, invisible to the port.)
- **AD-3 — Selection is config-driven, resolved once at the composition root.**
  `auth.module.ts` switches from `useClass` to a `useFactory` (injected
  `ConfigService`) that reads `SMS_DELIVERY_PROVIDER` and returns the adapter
  from a registry map:
  ```ts
  // auth.module.ts (sketch)
  const SMS_PROVIDER_REGISTRY: Record<string, Type<SmsDeliveryProvider>> = {
    mock: MockSmsDeliveryProvider,
    msg91: Msg91SmsDeliveryProvider,
    // twilio: TwilioSmsDeliveryProvider,   // ← tomorrow: 1 line
  };
  {
    provide: SmsDeliveryProvider,
    useFactory: (config: ConfigService) => {
      // FR-BE2: test env → mock; unset → msg91 in production, mock in dev.
      const key =
        config.get('NODE_ENV') === 'test'
          ? 'mock'
          : (config.get('SMS_DELIVERY_PROVIDER') ??
            (config.get('NODE_ENV') === 'production' ? 'msg91' : 'mock'));
      const Adapter = SMS_PROVIDER_REGISTRY[key];
      if (!Adapter) throw new Error(`Unknown SMS_DELIVERY_PROVIDER: ${key}`);
      return new Adapter();
    },
    inject: [ConfigService],
  }
  ```
  Adding a provider = write the adapter file + one registry entry + one env
  var. **Zero changes** to `auth.service.ts`, controller, DTOs, or core tests.
- **AD-4 — Failures normalize at the port boundary.** Adapters throw a
  provider-agnostic delivery failure (mapped from vendor errors, e.g. MSG91's
  `{type: "error"}` responses); `FR-BE4` handles it once, in the service.
  Vendor error shapes never cross the port. (The interface stays
  `Promise<void>` for now — a `DeliveryResult`/`providerMessageId` return is
  the natural extension if/when audit trails need it, and is additive.)
- **AD-5 — Channel ≠ provider; one port per channel.** No god-interface trying
  to cover SMS + WhatsApp + email (the FireflyFramework/LLD convention: narrow
  per-channel ports). Each channel port serves ALL its message types — there is
  no separate "notification" port:
  - `SmsDeliveryProvider` (this phase) — every SMS message type: T1 OTP today,
    T2–T5 notifications later, each with its own DLT template ID;
  - `WhatsAppSender` (future) — WhatsApp message types, adapter against MSG91's
    WhatsApp API or a BSP (Wati/Interakt);
  - `EmailSender` (future, same recipe) — `send(to, subject, body)`;
  - channel *routing* (which channel serves which message type, e.g. "OTP →
    SMS, job updates → WhatsApp then SMS") is a policy that lives ABOVE the
    ports — never inside an adapter.
- **AD-6 — Failover/retry wraps the port, never lives inside adapters**
  (per-provider circuit breaker, retry with backoff, fallback chain
  `SMS_DELIVERY_PROVIDERS=primary,fallback`). The registry (AD-3) is
  deliberately shaped to accept an ordered list later. **Not built in this
  phase** — YAGNI for a single Render instance — but the port boundary is what
  makes it a wrapper-class addition rather than surgery.

### Anti-patterns (review checklist)

- ❌ `if (provider === 'msg91')` anywhere outside the composition root
- ❌ Vendor SDK/client imported in `auth.service.ts` or any service
- ❌ Vendor response types in DTOs or error codes leaking to the frontend
- ❌ Channel logic (WhatsApp vs SMS vs email choice) inside a provider adapter
- ❌ Ports named after a message type (`OtpDeliveryProvider`) instead of a channel
- ❌ Changing a port's public shape when adding a provider

### Adding Twilio tomorrow (the whole diff)

1. `twilio-sms-delivery.provider.ts` (adapter, ~60 lines)
2. one registry entry in `auth.module.ts`
3. `TWILIO_*` env vars in the Joi schema
Nothing else — that is the contract this section locks in.

## 12. Research References

- MSG91 OTP API suite (send / verify / retry / analytics):
  [docs.msg91.com/otp](https://docs.msg91.com/otp); step-by-step OTP
  configuration (sender ID + OTP template prerequisites):
  [msg91.com/help](https://msg91.com/help/sendotp/step-by-step-process-to-configure-otp).
- v5 endpoint specifics: `POST /api/v5/otp` with `template_id`/`mobile`/`otp`;
  authkey as **header** on verify; retry via `/api/v5/otp/retry` — per
  [docs.msg91.com/otp](https://docs.msg91.com/otp) and community-documented
  curl examples of `control.msg91.com/api/v5/otp/verify`.
- DLT process and PE–TM chain: [msg91.com/help/dlt-process](https://msg91.com/help/dlt-process);
  mapping entity ID → sender ID and template ID in the MSG91 panel:
  [map entity ID](https://msg91.com/help/dlt-registration-in-india/map-your-dlt-entity-pe-id-with-dlt-approved-header-sender-id),
  [create template](https://msg91.com/help/template/how-to-create-flow-id-to-send-sms-via-api).
- Jio Trueconnect portal specifics (fees, timelines, header/template rules):
  [SpringEdge Jio DLT guide](https://www.springedge.com/dlt-jio),
  [Zoho Trueconnect walkthrough](https://help.zoho.com/portal/en/kb/campaigns/user-guide/sms-campaigns/articles/zcv2-dlt-registration-on-jio-trueconnect).
- Template variable/brand-name rules (`{#var#}`, ≤3 variables, brand name
  mandatory): [Exotel DLT guide](https://developer.exotel.com/docs/sms-support/dlt-guide),
  [DLT template approval tips](https://startmessaging.com/blog/dlt-template-approval-guide).
- Pricing (₹5,000 + GST DLT annual; ~₹0.20–0.25/OTP SMS + 18% GST, wallet
  prepay): [msg91.com/in/pricing/otp](https://msg91.com/in/pricing/otp).
- Pluggable-provider architecture (§11): ports & adapters / hexagonal for
  messaging — FireflyFramework.Notifications (per-channel ports, vendor
  adapters in opt-in packages, vendor SDKs never in domain code):
  [FireflyFramework.Notifications README](https://github.com/fireflyframework/fireflyframework-dotnet/blob/main/src/FireflyFramework.Notifications/README.md);
  MessagingGateway hexagonal reference (`ProviderRegistry`, zero-core-change
  provider addition):
  [ARCHITECTURE.md](https://github.com/vgpastor/MessagingGateway/blob/main/ARCHITECTURE.md).