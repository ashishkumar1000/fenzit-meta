# Technician flow QA — 2026-10-02 (evening, device + API)

> **FIXES + REGRESSION TESTS SHIPPED same night (22:00–22:45 IST)** — see "Fixes applied" and
> "Regression tests" at the bottom. BE fix is LIVE in production (migration applied + verified
> end-to-end). FE fixes are committed/pushed (fenzo-app 7461494 + 9714712) but need a release APK
> rebuild to reach the installed phone build.

Session: owner assigns job → technician (Ravi, +91 8285052048, "Business" tenant) logs in on the
Pixel 6 (release build `fenzit-release-arm64-1.0.0-2026-10-02.apk`, contains `5f0a3ca`) → walks the
6-step workflow. Both user-reported bugs **CONFIRMED**, plus one new bug found live.

## What was tested

| Job | Purpose | Result |
|---|---|---|
| JB-2026-0006/0007 (QA A/B) | API-level repro + control | A stuck at photos step (now 4 photos); B control: auto-advance fired |
| JB-2026-0008 (QA C) | Device happy path | Walked all 6 steps on device → **completed** |
| JB-2026-0004 "Test work" | User's own live session | **User hit the dead-end for real** (5/5 photos, stuck); unblocked via API |
| JB-2026-0009 (QA D) | Fix verification | Consumed by the live BE-fix verification (see Fixes applied) |

## BUG 1 — CONFIRMED: an early photo permanently dead-ends the Photos Uploaded step

**Repro (matches the field report exactly, and the user independently reproduced it on JB-2026-0004
while I was testing):**

1. Technician uploads a photo from the Photos card at ANY step before `in_progress`
   (the Photos card is available from the moment the job opens — by design).
2. Later the job reaches `photos_uploaded` (label "Photos Uploaded"). The action bar renders the
   **non-tappable pill "Upload a photo to continue"** (`workflowActionBarModel.ts:51` —
   `advancesOn === 'photo_confirm'` → `photoHint`; the stepper row is display-only too).
3. Technician uploads a photo. Confirm succeeds, but `confirm_attachment`'s auto-advance
   (`20260911000004_confirm_auto_advance_no_template_log.sql` §6) fired **only when
   `v_photo_count = 1`** (the job's first photo) **AND** `current_step` is exactly the
   photo step's predecessor (`in_progress`). The early upload already made count ≥ 1, so the gate
   was burnt forever. Every retry incremented the count; the step never advanced.
4. At the 5-photo cap the add tile disables — there was then **no action at all** that could move
   the job. Hard dead-end. (JB-2026-0004 reached exactly this state: photo #1 at 20:32:51 while the
   job was at On My Way; photos #2–#5 at 20:34–20:37 all ignored; stuck until manually advanced.)

**Escape hatch that existed but was unreachable from the app:** `POST /jobs/:id/workflow
{step:"photos_uploaded"}` returns 200 — the BE's step-order validation does not enforce
`requires_photo`, but the FE never offered that button. Used it to unstick JB-2026-0004 and A.

**Control:** with no early upload, the first photo confirmed at the step auto-advanced
(`step_photos_uploaded` logged) — verified via API (job B) and on device with a camera photo
(job C, 9:32 pm).

## BUG 2 — CONFIRMED: "Location not captured" seen by owner — three distinct mechanisms

Owner timeline renders `Location not captured — {reason}` whenever a step's
`metadata.locationCaptured === false` (`locationMetadata.ts:58`, `ActivityTimeline.tsx:118`).

- **2a — GPS failure silently advances with nulls.** `LocationCaptureScreen.tsx:63-85`: any
  capture failure (timeout after the 15 s strict + 25 s balanced attempts, permission denied,
  services off) falls into a catch that POSTs the advance with `latitude/longitude/accuracy:
  null`. BE (CAP-4 policy, `workflow.service.ts:196-220`) stores `locationCaptured: false,
  reason: "Location not provided"` and lets the step through. Reproduced via API: step advanced,
  metadata `{"locationCaptured": false, "reason": "Location not provided"}`. The field
  technician's report is this path (bad GPS / denied permission); the owner then sees the label.
  Indoors on the desk the capture worked when the attendance prescreen had warmed the location
  cache (14 m fix) and stalled ~30 s when the fix was 6 h stale.
- **2b — NEW: the signature step NEVER captures location.** `useSignatureSave.ts:94-98` called
  `advanceWorkflow(jobId, stepKey, key)` with **no coordinates at all** — no capture attempt
  existed on that screen. Every job's Signature Captured step was recorded
  `locationCaptured: false, "Location not provided"`. Observed on device 2026-10-02 21:33 (user
  signed live) — the technician's own History showed "Location not captured — Location not
  provided" under Signature Captured. FIXED (see Fixes applied 3).
- **2c — inconsistency (no failure label, but no location either):** the `photos_uploaded`
  auto-advance calls `advance_workflow_step` without location params (RPC defaults NULL), so the
  Photos step never carries location even when GPS is perfect. Renders as *no* location line
  (metadata NULL ≠ false). DEFERRED — product call.

## JB-2026-0005 postscript (user follow-up)

The user's second job (8:40–8:43 pm) had `locationCaptured: false` on EVERY device step — same
class, three causes: the three walking steps were run on the OLD debug build with the app's
location permission OFF at the time (silent null-advance, no prompt — steps ~20 s apart confirms
no capture was attempted); the signature step never captures by code (2b); the photos step never
carries location by RPC design (2c). The user's own 8:38 pm punch DID capture a fresh genuine fix
(fused, 5.7 s old) — the phone's GPS was fine; also one punch attempt that evening resolved to a
Delhi fix (28.64, 77.08 — a Play Services WiFi misfire while indoors in Bangalore), so indoor
fixes were flaky in general. All-time split across all jobs: 20 step-captures true / 17 false /
6 null — the job-flow capture is the most marginal capture path in the app; the release-build
happy-path walk captured on EVERY step from the same desk, so the failures are build/capture-
strategy, not device.

## Fixes applied (2026-10-02 ~22:00, per user: code fixes first, no tests/review; tests added after)

1. **BE — fenzit-be `3043493`** (migration `20261002220000_confirm_auto_advance_any_photo.sql`,
   applied to production via MCP): `confirm_attachment` §6 no longer requires the confirmed photo
   to be the job's FIRST — any photo confirm while `current_step` is the photo step's immediate
   predecessor advances it. Double-advance stays impossible (predecessor CAS + PT409 swallow
   unchanged). Verified against the previous function by whitespace/comment-insensitive diff
   (only the two intended logic lines changed) and by `pg_proc` probe of the LIVE function (old
   gate absent, cap/expiry/signature-conflict logic intact).
   **Live end-to-end verification (job D, JB-2026-0009):** early photo while at `on_my_way` →
   correctly no advance; photo #2 confirmed at `in_progress` → **auto-advanced**
   (`step_photos_uploaded` 22:10:05); photo #3 while at the step → no over-advance. The exact
   original dead-end sequence now completes.
2. **FE — fenzo-app `7461494`:** `actionBarAction` now takes `photoCount`; when the
   photo-confirm step is next and the job already has ≥1 photo, the bar renders a manual
   **Continue** button (routed through the standard location capture → advance) instead of the
   dead "Upload a photo to continue" pill. Rescues already-stuck jobs even without the BE fix and
   covers any future auto-advance miss. `TechJobDetailScreen` passes the photo count.
3. **FE — signature location:** `useSignatureSave` captures the technician's position
   (best-effort via `getCurrentPosition`, never blocks the save — CAP-4 parity) and sends it with
   the advance, ending the unconditional "Location not captured — Location not provided" on the
   signature step.

## Regression tests (added 22:15–22:30, the "skipped" ones from the prevention list)

- **BE real-DB probes** — fenzit-be `5971f1c`,
  `test/integration/photo-auto-advance.integration.spec.ts` (16-1 harness convention: gated on
  real credentials, skips under the jest.env.setup.ts stubs, throwaway tenant removed in
  afterAll; fixture lesson: tenants need `state_code`, owner user must precede the tenant row).
  Probe 1 replays the JB-2026-0004 dead-end in SQL: early photo while fresh → walk to
  `in_progress` → second photo confirm MUST advance to `photos_uploaded` + log
  `step_photos_uploaded` (fails under the old first-photo-only gate). Probe 2 pins the
  over-advance guard. **PASSES against production** (2/2); stub run skips cleanly; full BE
  default suite 90/90 suites, 1428 tests. (The mocked e2e specs cannot cover this — the gate
  lives inside the SQL function; an rpc mock would only test itself.)
- **FE unit tests** — fenzo-app `9714712`: three `actionBarAction` photoCount branches (photos at
  the photo step → Continue button; explicit 0 → pill; photos at a non-photo step ignored) and
  the signature best-effort behavior (GPS failure → advance with no coordinates, still pops).
  technicianApp suites: 171 tests green.

Existing-suite impact (found in the post-fix review, fixed): `SignatureScreen.test.tsx` needed a
`./geolocation` mock (re-seeded in `beforeEach` — `resetAllMocks` clears factory values) and its
exact-args assertion updated for the 4th location arg. Full FE suite green: **235 suites /
2951 tests passed**; `tsc --noEmit` clean.

## NOT fixed (deferred, product calls)

- Photos-step auto-advance carries no location (RPC calls `advance_workflow_step` without
  location params — metadata NULL, renders as no line).
- No visible "completed without location" cue for the technician.
- Job-flow capture order is still strict-first + one balanced fallback (the punch's
  balanced-first + foreground stream upgrade was scoped to attendance).

## Device session state (as found → as left)

- Release APK installed over uninstalled debug build; location (FINE+COARSE) and CAMERA granted
  via pm; login as Ravi via master OTP 816001 (auto-submit worked).
- Job C completed end-to-end on device (On My Way 9:27 → Arrived 9:28 → In Progress 9:29 →
  Photos 9:32 (camera) → Signature 9:33 (user) → Completed 9:36); steps showed "≈ 580 m away".
- JB-2026-0004 unblocked (manual advance at 21:39); user may continue it to completion in-app.
- QA residue in "Business" tenant: jobs A (0006, 4 photos) and B (0007, 1 photo) parked at
  `photos_uploaded`; job D (0009) at `photos_uploaded` with 3 photos after the live fix
  verification (user's own On My Way at 21:48 + probe steps) — continuable in-app; 0008
  completed. The installed release APK predates the FE fixes (button + signature location land
  with the next APK rebuild; the BE fix is already effective for it).
- Attendance state untouched (user's own check-in 8:38 pm, "late by 10h53m" banner as-found).
