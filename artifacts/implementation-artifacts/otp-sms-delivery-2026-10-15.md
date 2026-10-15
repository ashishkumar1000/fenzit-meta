# Epic 10 shipped end-to-end — OTP via MSG91 (DLT) — 2026-10-15

**State: DONE + DEPLOYED + DEVICE-PASSED.** Only ops steps remain (see [Remaining](#remaining)).
Commits: fenzit-be `64597a7` (pushed, Render autoDeploy **live + prod-verified**), fenzo-app
`76bc597` (pushed; release APK built + installed on the Pixel 6), meta this commit.

## What shipped

**Backend (64597a7)** — the delivery leg (PRD prd-otp-sms-msg91-2026-09-18) plus the day's
three user calls:

- `SmsDeliveryProvider` port — `send(to, templateId, variables: Record<string,string>)`,
  shaped per CHANNEL (template + named variables), adapters behind it; mock + MSG91 adapters;
  registry factory in `auth.module.ts` (`NODE_ENV=test` → mock always; explicit
  `SMS_DELIVERY_PROVIDER` wins; default msg91 in prod / mock in dev; msg91 without
  `MSG91_AUTH_KEY` refuses to boot). Joi mirrors it in `app.module`.
- **MSG91 = the v5 `/flow` endpoint, NOT `/otp`.** The gotcha of the week: `/otp` answers
  `type:success` but the message silently dies in DLT scrubbing for a `##number##` template
  (MSG91's "Failed SMS API" alert emails in the user's inbox are exactly these sends).
  Flow maps variables BY NAME — the user's own curl proved delivery. authkey rides the
  header; 4s timeout; success = 2xx AND body `type:success` (MSG91 answers 200 `type:error`
  on DLT rejections).
- **502 `OTP_SEND_FAILED` contract**: definitive failure deletes the just-created session,
  timeout KEEPS it (the SMS may still dispatch); the rate-limit counter stays incremented;
  one structured `otp_delivery` log line per attempt (crash path included, never the
  plaintext code); a failing session delete can't mask the 502.
- **User call 1 — OTP is 4 digits** (CSPRNG `randomInt(1000,10000)`), guessing bounded by
  the 5-attempt lockout + 5-min TTL + 5-sends/10-min cap.
- **User call 2 — master code re-keyed `816001` → `1039`** so it fits the 4-box input; the
  DTO's 6-digit arm was dropped (`^\d{4}$` only).
- **User call 3 — the dev echo is REMOVED outright.** The send response never carries the
  code on any environment; `OTP_DEV_ECHO` now gates ONLY the master code
  (`preReleaseMasterEnabled()`), dying at cutover.
- DLT template IDs are code constants (`SMS_TEMPLATES.OTP_LOGIN =
  '6abbb9d03a3773ee7209dd94'` — the MSG91 panel ID, ≠ DLT registry ID); only the authkey
  is env config. `render.yaml` pins `SMS_DELIVERY_PROVIDER=mock` for the pre-cutover
  window with the cutover checklist in comments.

**Frontend (76bc597)** — PRD FR-FE1/2/3 + the digit change: `OTP_LENGTH` 6→4 (four boxes,
auto-submit), `otp` field removed from `SendOtpResponse`, devOtp plumbing + DEV banner
removed, `OTP_SEND_FAILED` retry copy, and a rate-limited resend restarts the countdown
from the backend's `Retry-After` (`ApiError.retryAfterSeconds` → `rateLimitSeconds` prop —
with real SMS, 429 is a normal user path, not an edge case).

## Review round (BMAD, thorough)

4 lenses (blind-hunter, edge-case-hunter, verification-gap, intent-alignment) on the
uncommitted diff; step-03 triage per finding with at-citation verification:
**13 patches applied / 5 rejected with refutations / 0 deferred.** Full findings recorded in
the PRD's `## Code Review` section (prd-otp-sms-msg91-2026-09-18.md). Highest-value catches:
the docs said "v5 OTP endpoint" (the exact thing that fails DLT scrubbing), a body-read
timeout misclassified as a definitive failure, session-delete failures masking the 502, and
the mock provider's log line — the only delivery channel pre-cutover — being verified
nowhere (now pinned by its own spec).

## Deploy verification (production)

Render autoDeploy went live within the first poll:

- `POST /auth/otp/send` → 200 with **no `otp` key** (echo removal live; the old code under
  the still-set flag would have echoed).
- **Master `1039` verifies a real session** on prod (old deploy only knew 816001) —
  conclusive proof the new build is serving. Health ok.
- Probe side-effect: a tenant-less owner row `+919000000110` was created (same pattern as
  the H01 loadtest users; deletable on request).

## Device pass (Pixel 6, release APK `~/Desktop/fenzit-release-arm64-1.0.0-2026-10-15.apk`)

Shots in `otp-device-pass-2026-10-15/` (this dir): onboarding (post `pm clear`) → fresh
send → **OTP screen renders four boxes** → master `1039` auto-submitted at the 4th digit
and verified → logged in ("Good evening, Ashish", routed by the account's existing role) →
**session persists across force-stop + relaunch**. No crashes.

## Test tallies at ship

- fenzit-be: unit 101/101 suites, **1,556 green**; e2e 20 suites green + the 26 known
  real-DB baseline failures (untouched by this work); `tsc` clean; husky pre-push
  typecheck clean.
- fenzo-app: **237/237 suites, 2,996 green**; `tsc --noEmit` clean.

## Remaining

1. **Confirm the code-1295 test SMS arrived** (the local live send, ~20:32 IST). Real SMS
   arrival is the one leg no test can cover while Render runs the mock provider.
2. **Cutover** (Render dashboard, one pass): set `MSG91_AUTH_KEY`, flip
   `SMS_DELIVERY_PROVIDER=msg91`, unset `OTP_DEV_ECHO` — that last one kills the master
   `1039` gate. After the flip, real codes arrive over SMS; the mock log line and master
   shortcut are gone from prod.

## Gotchas worth keeping

- Gradle settings shells out to `npx` → nvm node must be on PATH; a daemon started with a
  bad PATH keeps failing (`./gradlew --stop` first); JAVA_HOME = Android Studio JBR.
- Husky pre-push runs `bun run typecheck` → needs `~/.bun/bin` on PATH in fresh shells.
- Pixel 6 lockscreen is swipe-only; screen sleeps mid-test — `svc power stayon usb` set
  (resets on reboot).
- BMAD's installed `render_skill.py` doesn't accept the skill's `--set workflow.review`
  flag; resolve the selection from the skill's own `customize.toml` (default = thorough)
  and follow the rendered steps directly.
