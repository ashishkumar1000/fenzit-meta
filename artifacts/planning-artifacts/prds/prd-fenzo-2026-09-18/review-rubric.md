# PRD Quality Review — PRD: Real OTP Delivery via MSG91 SMS (DLT)

**Doc:** `artifacts/planning-artifacts/prd-otp-sms-msg91-2026-09-18.md` (status: drafted)
**Compared against:** ops one-pager `ops-dlt-sms-template-registration-2026-09-18.md` and `fenzit-be/project-context.md`.
**Brownfield verification:** §2's file/line claims were spot-checked against the working tree — `auth.service.ts` (rate limit at :67-82, `const isValid = true` with the "Phase 2" comment at ~:139-140, `otp` in the `sendOtp` return and `this.logger.log(`OTP for ${e164}: ${otp}`)`, `useClass: MockOtpDeliveryProvider` at `auth.module.ts:19-22`), `error-code.enum.ts` (`INVALID_OTP`/`OTP_EXPIRED`/`OTP_SESSION_LOCKED` present, no `OTP_SEND_FAILED`), `.env.example` (no OTP/SMS section — as claimed), `places-provider.ts`/`mock-places.provider.ts` (the DI-swap convention FR-BE1 mirrors exists), and the FE files (`SendOtpResponse.otp?` with its "will be removed before production" docstring, `sendOtpErrorMessage` at AuthFlow.tsx:34-43, `devOtp` state ~:70-76/:94). Every reference I checked resolves accurately.

## Overall verdict

This is a strong, unusually well-grounded PRD: every brownfield claim I checked is accurate, decisions are logged with dates in the frontmatter, the Non-Goals section does real work with reasons, and §11's architecture section constrains actual code rather than decorating. The risks are concentrated in three places: FR-BE5's dev/prod `otp`-field gate is stated two conflicting ways (security-adjacent), the T2–T5 notification-sender backend work implied by §10 is never explicitly de-scoped or owned, and the §7 "≥ 98% signup success rate" metric has no instrumentation anywhere in the FRs to make it measurable.

## Decision-readiness — strong

Decisions are stated as decisions, not buried. The frontmatter carries five dated, confirmed decisions (including the user-corrected "ports named per CHANNEL" rule); §5 rejects the MSG91-managed OTP engine with the actual reason ("discarding our session store/lockout would be a net regression"); FR-BE4 names what was given up ("The rate-limit counter already having incremented is accepted (prevents bypassing the limit via a failing provider)") — a real trade-off, not a smoothed one. §9's italic note honestly concedes that flipping verification "does invalidate the 'any code works' convenience." Pushback would find its objection already in the text.

The gaps are two. First, FR-BE5 is stated in two incompatible ways (see finding below) — this is the one decision that looks decided but isn't. Second, there is no consolidated Open Questions section; genuinely open items exist but live scattered inline: T8's "decide consent/opt-out handling before registering" (§10.2), T2's "Confirm the link works before registering" for `fenzit.com/app` (§10.1), and T6's "no activity-log event exists today" (§10.2). None is rhetorical; they're just easy to lose.

### Findings
- **medium** FR-BE5's gate is stated two conflicting ways (§4.1 FR-BE5 vs §9 step 1) — FR-BE5 says the `otp` field appears "only when the active provider is the mock (dev/test)" and "In production the field is absent," but §9 step 1 lands fenzit-be in production with `SMS_DELIVERY_PROVIDER=mock` and tells testers to use "the mock's logged/response OTP." If the gate is *active provider* and prod temporarily runs mock, plaintext OTP flows in production API responses; if the gate is *NODE_ENV*, production testers lose the response OTP §9 promised them. These cannot both hold. *Fix:* gate on NODE_ENV alone (prod never sees the field regardless of provider) and reword §9's tester note to "mock logs only" in prod.
- **low** Open items are scattered, not consolidated (§10.1 T2 note, §10.2 T8, §10.2 T6) — three pre-registration/pre-build conditions live as inline italic notes across two sections. *Fix:* a short "Open items before/after rollout" list (or an Open Questions section) collecting them.

## Substance over theater — strong

No personas at all, which is correct for a technical capability spec. The Vision (§1) is not swappable — it names the preserved contract, the session store, and "Development continues to work without spending real SMS money." Success Metrics are product-specific ("Zero real SMS spend in dev/CI runs," "~5 s of request on Indian numbers"), not scalable/secure/reliable boilerplate. §11 is earned: it constrains FR-BE0/BE1/BE2 concretely, names anti-patterns as a review checklist, and explicitly declines to build failover ("Not built in this phase — YAGNI for a single Render instance") while noting what the port boundary preserves. That is the opposite of theater.

Two mild deductions. §12/§11's justification cites five external sources (Hashigo, FireflyFramework, MessagingGateway, InterviewLoop, a Medium post) to defend a standard hexagonal pattern the team already agreed to — the citations pad rather than decide, and AD-1 through AD-6 stand fine without them. And FR-BE1's concrete spec does not actually deliver what §11/AD-5 promises for multi-variable templates (finding below).

### Findings
- **medium** FR-BE1's adapter spec only works for single-variable templates, but §11 claims the port serves T2–T5 (§11 AD-5: "every SMS message type: T1 OTP today, T2–T5 notifications later") — FR-BE1 pins the v5 OTP endpoint mapping to `otp` (`variables[0]`), a single-code param; T2–T5 are 2–3-variable templates. AD-2 waves this off as "vendor detail … inside the adapter," but that leaves the mapping for the very templates the architecture is being shaped for unspecified — the port's `variables: string[]` model and FR-BE1's concrete HTTP contract don't yet connect. *Fix:* one sentence in FR-BE1 or AD-2 stating which MSG91 endpoint/param mapping carries multi-variable templates (or explicitly: T2–T5 send goes through the transactional endpoint, an adapter-internal branch).
- **low** §11's external-citation weight is disproportionate (§12: five references to obscure repos for a pattern the user already mandated). *Fix:* optional — trim to the two best; zero substance lost.

## Strategic coherence — strong

There is a thesis and the PRD bets on it: close a security hole (W1, "any 6-digit code logs the user in") with minimal blast radius — "only the delivery leg changes" (§1), "No API contract changes" (FR-BE7). Prioritization follows from it: real verification and the provider first, FE cleanup second, config flip last (§9). MVP scope is problem-solving and the scope logic matches. Success Metrics validate the thesis (wrong OTP can't log in; no plaintext OTP in prod responses/logs), not activity. §10's T2–T5 notification templates widen the document beyond its title, but the PRD is honest about why they ride along (batch registration with the header, §8's "register T1–T5 together in one batch"), and they are registration-only, not code.

### Findings
- **low** No counter-metrics (§7) — the rubric expects them when SMs exist. The natural ones are right there: OTP send failure rate, verify abandonment after delivery, SMS spend per signup. *Fix:* add 1–2 counter-metrics.

## Done-ness clarity — strong

This is the dimension story creation will lean on, and it mostly holds. FRs are concrete to the line: FR-BE1 names the exact endpoint, query params, `authkey` "header, not query param," and `AbortSignal.timeout(4000)`; FR-BE4 names the status code, error code, and the session-deletion consequence; FR-T1–T3 spell out the test matrix (lockout at 5 → `OTP_SESSION_LOCKED`, expired → `OTP_EXPIRED`); FR-FE1–3 cite exact files and line ranges. An engineer could write acceptance criteria from these without asking questions — I verified the cited code locations exist as described.

Three soft spots: FR-BE5 (above), the MSG91 success criterion, and the 98% metric.

### Findings
- **medium** §7's "End-to-end signup (send → verify → JWT) success rate ≥ 98% of attempts that respect the rate limit" is not measurable under this plan — no FR adds instrumentation, logging aggregation, or an analytics hook, and the in-memory session store keeps no attempt history. As written the metric can never be checked. *Fix:* either specify the minimal measurement (e.g. structured logs + a query, or a counter on the session store) or restate the SM as something verifiable with the shipped tests and manual checks.
- **low** FR-BE4's trigger is "throws or returns a non-success response" but the success shape is never pinned — AD-4 mentions MSG91's `{type: "error"}` shape in passing, and FR-T2 covers error mapping, yet "what counts as success" (e.g. `type: "success"` vs an HTTP-status-only check) is left to the implementer. *Fix:* one line in FR-BE1 or FR-T2 defining the success predicate.

## Scope honesty — strong

§5's Non-Goals section does real work — seven items, each with a reason, including two rejections of tempting alternatives (MSG91's OTP engine, autofill/SMS-retriever) and one honest boundary statement ("India-only is the tested, DLT-registered reality this phase"). Dependencies are explicit and dated (the ₹5,000 DLT subscription lapsing on 17/10/2026; "production rollout of the msg91 provider is blocked until the template is approved"). Deferred items surface as callouts rather than silence (T4's known notification gap, T8's consent decision, §9's tester-convenience note). Open-items density is low, which is right for a green-light-to-build PRD with decisions confirmed.

The one real hole: the backend senders implied by the T2–T5 registration batch.

### Findings
- **medium** T2–T5 backend sender work is described with implementation sketches but never de-scoped or owned (§10.1) — §10.1 says "Backend: new — sent by `inviteTechnician` after the users row commits" (T2) and "SMS worker subscribes to `notifications` inserts" (T4), yet no FR covers any of it, §5's Non-Goals doesn't list it, and no deferred-work pointer exists. A reader cannot tell whether registering T2–T5 now implies building those senders this phase. *Fix:* one explicit sentence — "T2–T5 sender implementation is out of scope for this PRD; tracked as <where>."

## Downstream usability — strong

FR IDs are contiguous and unique (FR-BE0–BE7, FR-FE1–4, FR-T1–3); cross-references resolve (FR-BE2 ↔ §11 AD-3, FR-BE4 ↔ AD-4, §5 ↔ AD-5, §8 ↔ §10 T1, §10 ↔ the ops one-pager). UJs each have a protagonist (new owner, technician — explicitly "unchanged," developer). Sections read standalone: §10 carries its own registration-context table rather than "see §8." §10 and the ops one-pager are consistent where they overlap — entity ID, portal, `FENZIT` header, Service Implicit category, the 17/10/2026 deadline, the rejection rules, the "cannot be edited after approval" rule, and all five T1–T5 template strings are character-identical; the ops sheet adds only ops-only facts (login email, rejection support address). There is no Glossary section, but the noun set is small and each term is defined inline at first use ("Header (sender ID) — 6 alphabetic characters"), so nothing drifts enough to mislead story creation.

### Findings
- (none beyond the mechanical notes below)

## Shape fit — strong

Correct shape for what this is: a brownfield, cross-repo technical capability spec feeding BMAD story creation (chain-top, so downstream usability matters and is delivered). UJ density is light (§3.1–3.3), which is right — UJ-heavy formality would be overhead here, and §3.2's "Technician first-login auto-activation, owner tenant routing, company setup — no changes" is exactly the right kind of non-journey. New-vs-existing is distinguished throughout (§2's "Wired and working" table vs "the gaps this PRD closes"). The §10/§11 ride-alongs (notification templates, channel architecture) stretch the title's scope, but both are labeled for what they are and are justified by the batch-registration and per-channel-port decisions — shape-wise they read as deliberate annexes, not scope smuggling.

### Findings
- (none)

## Mechanical notes

- **Glossary drift (minor):** pricing is "~₹0.20–0.25 per OTP SMS" in §6 but "~₹0.19–0.25/OTP SMS" in §12 — pick one. §8 step 3 says "max 2–3 non-consecutive variables" while §10's rule block says "max 3 (ideally 1)"; same rule, two phrasings — ops readers get the ops sheet's version, fine, but align the PRD's own two statements.
- **No Assumptions Index:** §6 carries one inline bold "**Assumption**: single backend instance" and a "Pre-launch context" note, but the PRD doesn't use `[ASSUMPTION: …]` tags or index them. One assumption; low cost to fix if the house style demands it.
- **Naming continuity:** the old/new provider naming (`OtpDeliveryProvider` → `SmsDeliveryProvider`) is handled unusually well — §2 flags the rename inline, frontmatter decision 5 records it, and §11's anti-patterns list codifies it. `OtpSessionStore` (§5) matches the actual `otp-session-store.ts` interface name — verified. No ID gaps or unresolved cross-refs found.
- **T1 wording consistency:** §8 step 3, §10.1, and the ops one-pager all carry the identical T1 template string, including "Valid for 5 minutes," which matches the code's `OTP_TTL_SECONDS` 5-minute TTL — good.
- **Env-var continuity:** FR-BE3's three vars (`MSG91_AUTH_KEY`, `MSG91_OTP_TEMPLATE_ID`, `SMS_DELIVERY_PROVIDER`) are the same set §8 step 6 configures and §9 step 1 flips — consistent.