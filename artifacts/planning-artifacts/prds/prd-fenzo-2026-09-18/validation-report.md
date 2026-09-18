# Validation Report — Real OTP Delivery via MSG91 SMS (DLT)

- **PRD:** `artifacts/planning-artifacts/prd-otp-sms-msg91-2026-09-18.md`
- **Rubric:** `.claude/skills/bmad-prd/assets/prd-validation-checklist.md`
- **Run at:** 2026-09-18
- **Grade:** Fair

## Overall verdict

Strong, unusually well-grounded PRD: every brownfield claim checked is accurate (all §2 file/line references verified against the working tree), decisions are logged with dates in the frontmatter, the Non-Goals section does real work with reasons, and §11's architecture section constrains actual code rather than decorating. All seven rubric dimensions judge **strong**. Risks concentrate in three places: FR-BE5's dev/prod `otp`-field gate is stated two conflicting ways (security-adjacent), the T2–T5 notification-sender backend work implied by §10 is never explicitly de-scoped or owned, and the §7 "≥ 98% signup success rate" metric has no instrumentation anywhere in the FRs.

The adversarial reviewer materially shifts the picture without dropping any dimension: six findings rank high by impact — Math.random() OTP generation, FR-BE5's unimplementable gate, the production-plaintext-OTP rollout window, the multi-variable port gap, the T3/T4 DLT wording, and T2–T5's unowned backend work. Rubric and adversarial findings overlap on four items (FR-BE5 gate, port/T2–T5 scope, the 98% metric, multi-variable support) — overlap is signal: these are the PRD's real seams.

## Dimension verdicts

- Decision-readiness — strong
- Substance over theater — strong
- Strategic coherence — strong
- Done-ness clarity — strong
- Scope honesty — strong
- Downstream usability — strong
- Shape fit — strong

## Findings by severity

### Critical (0)

None.

### High (6) — all adversarial; pre-implementation must-resolves

**[adversarial #1]** OTP still generated with `Math.random()` — the PRD makes verification a real security boundary but never upgrades the RNG (`auth.service.ts:84`; V8 xorshift128+ is predictable from a few observed outputs).
Fix: FR switching generation to `crypto.randomInt(100000, 1000000)`, or a documented deliberate deferral.

**[adversarial #2]** FR-BE5's mock-only `otp` field has no implementable mechanism that doesn't violate §11's own anti-pattern list (a provider-identity check inside the service is the banned pattern; NODE_ENV gating contradicts FR-BE5's provider-based wording).
Fix: gate on an explicit environment/config signal (e.g. `EXPOSE_DEV_OTP`, default false); mock keeps its own logging; delete the service-level OTP log line.

**[adversarial #3]** §9 step 1 schedules plaintext OTP in *production* API responses — prod runs the mock between deploy step 1 and the config flip (a days-long window spanning DLT approval), contradicting the §7 metric.
Fix: gate on environment (production never sees the field) + an acceptance check at the step-3 flip asserting no `otp` key in the response.

**[adversarial #4]** The port `send(to, templateId, variables)` can't deliver T3/T4 — FR-BE1 forwards only `variables[0]` to MSG91 v5 `/otp`'s single `otp` param, and nothing in the port call tells the adapter which endpoint to use; the transactional path has no FR at all.
Fix: pin the multi-variable mapping now (second adapter method / flow endpoint) or scope T2–T5 sending explicitly out.

**[adversarial #5]** T3 and T4 violate the DLT non-consecutive-variable rule the PRD itself states — "New job {#var#} ({#var#})" and "Update for job {#var#}: {#var#}" are adjacent variables separated only by punctuation; likely rejections that would burn the batch registration.
Fix: rewrite with real fixed text between every variable pair; re-check ≤30-char budgets; mirror into the ops one-pager before submission.

**[adversarial #6]** T2–T5 are handed to ops as a launch set, but no FR covers their backend sending — T4 presumes an undesigned "SMS worker subscribes to notifications inserts"; approved (non-editable) template copy depends on backend formatting choices that don't exist yet.
Fix: explicit scope sentence (ops may register now; backend wiring is a separate future story; store IDs until then) or cut T2–T5 from the batch.

### Medium (14)

**[rubric / = adversarial #2+#3]** FR-BE5's gate stated two conflicting ways (§4.1 vs §9 step 1) — fix: NODE_ENV-only gate; reword §9's tester note.
**[rubric / = adversarial #4+#14]** T2–T5 backend sender work never de-scoped or owned (§10.1) — fix: one explicit out-of-scope sentence.
**[rubric / = adversarial #15]** §7 "≥ 98%" metric unmeasurable — no instrumentation in any FR — fix: specify minimal measurement or restate.
**[rubric / = adversarial #4]** FR-BE1's single-`otp`-param mapping uncovered for T2–T5's 2–3-variable templates despite §11's claim — fix: name the endpoint mapping or the adapter-internal branch.
**[adversarial #6]** Registry sketch's `getOrThrow` contradicts "unset → mock in dev" — fix: resolve default by environment; validate key against registry.
**[adversarial #7]** No cross-field Joi validation — msg91 without auth key boots fine then 502s every login — fix: conditional Joi rule; refuse to boot.
**[adversarial #8]** FR-BE4 delete-on-failure races the 4s timeout — SMS may still arrive after the session is deleted; correct code then rejected as expired — fix: keep session on timeout; pin semantics with a test.
**[adversarial #9]** FR-BE6 "exactly as written" re-sets full TTL on each failed attempt (session lives ~25 min vs advertised 5; `expires_at` diverges) — fix: re-store with remaining TTL; test asserting expiry truthfulness.
**[adversarial #10]** Non-atomic rate-limit increment now caps real SMS spend (code's own caveat never carried into the PRD) — fix: per-key serialization or accept with a stated bound.
**[adversarial #11]** Restarts/deploy/spin-down wipe in-flight sessions on a single instance — "just-received code says expired" clusters around deploys — fix: accepted-risk paragraph in §6 + deploy-timing note.
**[adversarial #12]** `templateId` never pinned as DLT ID vs MSG91-panel ID — fix: `MSG91_OTP_TEMPLATE_ID` = the string that succeeded in Test DLT; add column to the ops table.
**[adversarial #13]** T1 hardcodes "Valid for 5 minutes" coupled to `OTP_TTL_SECONDS` in a non-editable template — fix: guard note + test pinning the constant.
**[adversarial #16]** FE 45s resend vs 5/10-min 429 ceiling becomes a normal user path; FR-FE3 doesn't cover `RATE_LIMIT_EXCEEDED` — fix: Retry-After countdown on the OTP screen.

### Low (6) — all rubric

- Open items scattered inline, not consolidated (§10.1 T2 note, §10.2 T6/T8) — add an Open items list.
- §12's five external citations disproportionate — trim to the two best.
- No counter-metrics (§7) — add send-failure rate, verify abandonment, or SMS spend per signup.
- FR-BE4's success shape never pinned (`type: "success"` vs HTTP-status) — one line in FR-BE1 or FR-T2.
- (mechanical) pricing drift ₹0.20–0.25 vs ₹0.19–0.25 (§6 vs §12).
- (mechanical) "max 2–3" vs "max 3 (ideally 1)" phrasing inconsistency (§8 vs §10).

## Mechanical notes

- Pricing drift: §6 "~₹0.20–0.25" vs §12 "~₹0.19–0.25" — pick one.
- Variable-count phrasing: §8 "max 2–3 non-consecutive" vs §10 "max 3 (ideally 1)".
- One inline assumption (single backend instance) without `[ASSUMPTION]` tags or index.
- Naming continuity handled well: rename flagged in §2, recorded as frontmatter decision 5, codified in §11 anti-patterns; `OtpSessionStore` matches the actual interface name; env vars and IDs consistent throughout.
- T1 wording consistent across §8, §10.1, ops one-pager; all five T1–T5 template strings character-identical with the ops sheet.

## Reviewer files

- `review-rubric.md`
- `review-adversarial-general.md`