---
id: SPEC-play-privacy-compliance
companions: []
sources: []
---

> **Canonical contract.** This SPEC is the complete, preservation-validated contract for what to build, test, and validate. Consult the `.memlog.md` for the chronological decision record it was distilled from.

# Play Store privacy compliance: in-app legal links, deletion entry, policy hardening

## Why

**Mandate to meet.** Google Play's User Data policy (support.google.com/googleplay/android-developer/answer/10144311) blocks the store submission until (a) the privacy policy is reachable **within the app**, and (b) account deletion is reachable **in-app and on a web resource**. The published policy page already passes Play's URL and content checks (verified live 2026-11-03); the gaps are app-side — the login screen's "Terms of Service"/"Privacy Policy" are dead text, the Account & settings screen has no policy or deletion entry — plus two disclosure gaps in the published policy (camera use, children). Google's account-deletion guidance (answer/13327111) explicitly sanctions "a link within your app that takes users to your app account deletion web resource", so no native deletion flow is required.

## Capabilities

- **CAP-1 — In-app legal links.**
  - **intent:** A person can open Fenzit's privacy policy and terms from inside the app — tappable "Terms of Service"/"Privacy Policy" text on the login screen (the consent point) and rows on the Account & settings screen.
  - **success:** Tapping either phrase on the login screen, or either row on Account & settings, opens `https://fenzit.com/privacy-policy` / `https://fenzit.com/terms` in the device browser.
- **CAP-2 — In-app deletion entry (revised by owner, 2026-11-03: request + review).**
  - **intent:** A signed-in person can start account deletion from inside the app: a dialog informs them they are about to delete the account, states the consequences for their role (owner: whole company's data; employee/technician: personal details, name removed from records), and consent files the same reviewed deletion request the web flow creates — the JWT replaces the OTP proof, so no code is asked in-app. On success the app logs out automatically.
  - **success:** Tapping "Delete account" on Account & settings shows the role-specific dialog; consent calls an authenticated backend endpoint that inserts into `account_deletion_requests` for the token's user (idempotent when a request is already open); the app then clears the token, resets all stores and returns to the login screen. A failed call shows a retryable error and does **not** log out. `https://fenzit.com/delete-account` remains the Play Console web resource.
- **CAP-3 — Policy content hardening.**
  - **intent:** The published privacy policy discloses what Play cross-checks but it currently omits.
  - **success:** `https://fenzit.com/privacy-policy` states the camera is used only for job photos and customer signatures, carries a children statement (a workplace tool, not directed at children; under-13 data deleted on request), and names the self-serve deletion page; the last-updated date reflects the change.

## Constraints

- Play User Data policy is the contract: policy reachable within the app; deletion reachable in-app — the reviewed-request path is Google's accepted form ("a path to request account deletion"); legal web pages open in the device browser, no in-app WebView.
- Cross-repo ordering: the authenticated deletion endpoint is additive — fenzit-be merges/deploys **first**, then fenzit-app switches onto it.
- Never gate an https open on `Linking.canOpenURL` (iOS `LSApplicationQueriesSchemes` limit, Android 11+ package visibility — `openUrl` in `src/utils/linking.ts` already avoids it); a failed open must not crash the screen — silent guard, same philosophy as `openTel`.
- Deletion-consent must be an explicit affirmative action on a dialog that names the consequences **before** the request is filed; a failed request never logs the user out (that would look like the deletion succeeded).
- Tappable text uses `accessibilityRole="link"` (RN docs pattern); legal copy follows the existing `legalCopy.ts` plain-English style — only statements the product honours today — with the date bumped via the single `LEGAL_UPDATED` constant.
- Backend: never log phone numbers or other personal data; the endpoint answers the same whether or not a request is already open (unique-violation tolerated, like the public flow).

## Non-goals

- No immediate/impatient deletion: the app files the request; the admin console review remains the only executor (no one-tap company wipe).
- No OTP inside the app — the login token is the identity proof (the public web endpoint keeps its OTP flow unchanged).
- No Play Console Data safety form work (manual Console entry, not code).
- No change to the location prominent-disclosure/permission flow (already compliant: intro disclosure + primer screen precede the runtime prompt).
- No new legal claims (M&A clauses, GDPR citations) the owner has not stated.

## Success signal

A Play reviewer installing the app can reach the privacy policy and terms from both the login screen and Account & settings, start deletion from Account & settings and finish it on the web page, and read the camera sentence, children statement and deletion pointer on the published policy.

## Assumptions

- `https://fenzit.com/privacy-policy`, `/terms` and `/delete-account` are the canonical public URLs (verified live 2026-11-03).
- The app's MoreScreen ("Account & settings") is the settings page the owner means.
- The test-timing rule applies: no new tests until the owner confirms the behaviour on device; existing suites must stay green.

## Code Review

### 2026-11-03

**Code review complete.** 0 `decision-needed`, 6 `patch`, 2 `defer`, 7 rejected. Lenses: blind-hunter, verification-gap, intent-alignment (findings above); edge-case-hunter returned empty (recorded as failed layer — its deep boundary trace held and corroborated the other lenses' verifications).

- [x] [Review][Patch] BE: `requestForSignedIn` untested — add `account-deletion.service.spec.ts` (insert carries the JWT's userId; 23505 answers the received message; any other error throws the friendly 500) [workspace/core/backend/fenzit-be/src/account-deletion/account-deletion.service.ts:84]
- [x] [Review][Patch] BE: insert/idempotency block duplicated between `request()` and `requestForSignedIn` — extract one private filing helper so the two paths cannot drift [workspace/core/backend/fenzit-be/src/account-deletion/account-deletion.service.ts:60]
- [x] [Review][Patch] Policy omits the in-app deletion path the app now offers — extend the rights-section sentence [workspace/core/frontend/fenzit-web/src/pages/legalCopy.ts:85]
- [x] [Review][Patch] Login-screen consent links have no visual affordance (weight-only) — underline `termsEm`, the standard legal-link pattern [workspace/core/frontend/fenzit-app/src/features/auth/screens/PhoneScreen.tsx:363]
- [x] [Review][Patch] `openWebPage` comment still lists "account deletion" though no caller opens the web deletion page [workspace/core/frontend/fenzit-app/src/utils/linking.ts:115]
- [x] [Review][Patch] `src/utils/linking.ts` is missing its trailing newline [workspace/core/frontend/fenzit-app/src/utils/linking.ts:130]
- [x] [Review][Defer] App delete-flow/link tests (dialog success signs out, failure keeps dialog with retry line, admin-profile copy; PhoneScreen phrases and More legal rows open the config URLs; `openWebPage` cases in linking.test.ts) [workspace/core/frontend/fenzit-app/src/features/more/MoreScreen.test.tsx] — deferred: test-timing rule (SPEC assumption) — write after the owner confirms the flow on device
- [x] [Review][Defer] Admin queue cannot tell an in-app request from a web one (both flows insert identical rows, no `source` column) [workspace/core/backend/fenzit-be/src/account-deletion/account-deletion.service.ts:85] — deferred: needs a schema migration plus admin-console UI scope

**Rejected**

- false — app/web copy divergence: the web page makes the same promise the app does ("Records we must keep for audit stay, with names removed", DeleteAccountPage.tsx:12).
- false — 401 shown as connection error: the apiClient clears the token and fires the global unauthorized logout on any 401 while a token is present (apiClient.ts:225-235), so the retry line never persists for an expired session.
- false — success leaves the dialog hanging: `clearAuthToken()` is a synchronous MMKV remove (`(): void`), and `runAllResets`/`navigation.reset` are synchronous — the modal unmounts in the same tick, with no reachable failure path.
- false — hard-deleted user's live JWT would 500 on the FK: the guard resolves membership from the database per request and 401s unknown users before the controller runs (jwt-auth.guard.ts:99-107).
- low — platform_admin sees member copy in the dialog: staff do not use the field app in everyday use, and the fix adds a third copy branch.
- low — rights-section URL renders as plain text: linkifying adds parsing complexity; Play's requirement is that the policy names the resource, and the reader is already on fenzit.com.
- low — URL constants manually synced to web routes: a cross-repo test would couple two separately deployed repos; the config comment documents the contract, and device test + Play review catch drift.

### 2026-11-03 — post-review find (device test, employee role)

- [x] [Review][Patch] Employee Profile tab (`features/technicianApp/ProfileScreen.tsx`) had no privacy/terms rows and no Delete account entry — the review and this spec assumed MoreScreen was the only settings surface, but employees use a separate TechnicianTabs Profile screen. Found on-device while testing the employee dialog; fixed by mirroring the More tab rows through the same `openWebPage` + `DeleteAccountConfirm` (the employee role gets the personal-data consequences copy). Verified on the Pixel 6: rows render, dialog shows the member copy, Cancel holds the session, the privacy row opens the live page. Shipped as fenzit-app cc1c8e9.

### 2026-11-03 — deferred items implemented (owner-approved)

- [x] [Review][Defer→Patch] App delete-flow/link tests written after the owner's on-device confirmation (test-timing rule satisfied): MoreScreen delete-flow + copy-switch + legal-row tests, PhoneScreen consent-phrase taps, `openWebPage` cases, new ProfileScreen tests (fenzit-app 394a4b3; 305 suites / 3947 tests).
- [x] [Review][Defer→Patch] Deletion-source tracking: `source` column (web|app, default web), BE filing paths record it, admin queue displays it. Migration applied 2026-11-03 before the BE deploy (fenzit-be 39c72b1, fenzit-web ba1c31b).

### 2026-11-04 — Play Console steps completed (owner account: Fenzit LLC, fenzit1000@gmail.com)

- App entry created: Fenzit / com.fenzit / App / Free (package was already registered to the account).
- App content, all declarations filed: privacy policy URL (fenzit.com/privacy-policy), sign-in details (reviewer credentials: owner phone + reusable master OTP 1039, full access), ads (none), content rating (IARC: Everyone / PEGI 3 / USK All ages), target audience (18+), data safety (submitted: name, phone, precise location, photos, UGC collected; nothing shared; deletion URL fenzit.com/delete-account; partial-deletion link → privacy policy), government apps (no), financial features (none), health (none), advertising ID (none).
- Store settings: category Business; contact hello@fenzit.com / +91 92792 30451 / fenzit.com.
- Store listing text saved as draft: "Fenzit", short + full descriptions (artifacts/play-listing/listing-copy.md).
- Listing assets: 512 icon + 1024×500 feature graphic built from the launcher foreground art (artifacts/play-listing/graphics/); 8 device screenshots 1080×1920 (screenshots/final/) captured on the Pixel 6 against seeded demo data.
- Demo tenant on production: "Sparkle Facility Services" (owner +91 9810012345, master OTP), 5-person team, 8 jobs across statuses (two completed with photo, one in progress), 6 customers, office geofence + enrolments, 3 check-ins, one pending + one approved leave. Seed scripts: artifacts/play-listing/seed-demo*.ts.
- Promo video skipped for now (owner decision): build_video.py is ready in artifacts/play-listing/video/; Play takes a YouTube URL, addable any time.
- Listing assets uploaded and saved (2026-11-04, "Your changes have been saved"): App icon ×1, feature graphic ×1, 8 phone screenshots in Main store listing. App content overview shows "You're all caught up" — 10/10 declarations actioned.
- Remaining: (1) build a signed release AAB and upload to a testing track (app is still Draft, no bundle yet); (2) optional YouTube promo URL (build_video.py ready); (3) rotate the master OTP before public review — 1039 is written into the reviewer credentials in the Console; (4) MSG91 recharge (owner handling); (5) Send for review in Publishing overview once the AAB is live.
- Ops flag: MSG91 SMS balance exhausted (seen on the owner's phone) — real OTP delivery is down until topped up; master OTP testing unaffected.

### 2026-11-04 — Release uploaded, app sent for review (owner ruling: direct production release, no testing)

- Release AAB: `fenzit-1.2.0.aab` downloaded from GitHub Releases v1.2.0 (owner tip; CI-built, release-keystore signed — SHA-1 verified against the local `fenzit-release.keystore` before upload). Local gradle build cancelled as redundant.
- Console blockers found at preview and fixed: countries/regions (178 targeted incl. rest of world), store listing AI-asset declaration (answered "Don't label assets" — assets are real screenshots + PIL-drawn graphics), health declaration re-flag cleared itself on rescan, and a NEW Foreground Service declaration triggered by `react-native-nitro-geolocation` merging `FOREGROUND_SERVICE`/`FOREGROUND_SERVICE_LOCATION` into the manifest.
- FGS fix (fenzit-app 497de7b): the app only uses one-shot location (`getCurrentPosition`/`watchPosition` foregrounded) — the library's background service is never started — so the four unused permissions are stripped via `tools:node="remove"` instead of declaring (the FGS-location declaration route can demand a demo video). Merged manifest verified clean via `strings` on the AAB; RECEIVE_BOOT_COMPLETED survives (another library) but triggers no declaration.
- Version code 10200 is burnt forever in Play (first Console upload, superseded by the FGS rebuild) → bumped to **1.2.1 / 10201** via `bun run sync:version` (per the repo's store policy: every Console upload is a SemVer bump).
- Upload path: Console file inputs accept chunked base64 injection (page-side `DataTransfer` + change event); ~120 × 800 KB evaluate calls per 68 MB AAB (1.8 MB+ chunks break the browser broker; the release-notes editor needs `<en-US>` XML tags, NOT `[en-US]`).
- Runtime regression check on the Pixel 6 (owner ask): metroDebug with the stripped manifest — owner session intact, employee login (Arjun, master OTP), punch prescreen streams GPS, Check in captured a fresh fix and gated correctly ("You are 1727.4 km from Sparkle Hub… within 150 m") — geofence verdict, not a breakage. No SecurityException in logcat.
- **Submitted: 11 changes sent for review from Publishing overview** (production release 10201 full rollout, countries, listing, app content). Managed publishing is OFF → everything publishes automatically once Google approves (reviews typically ≤ 7 days).
- Left over: maps API key still unrestricted (restrict to Android + com.fenzit + release SHA-1 01:0B:F4:BF:3F:07:DF:5E:2D:36:46:9E:55:92:36:0F:D4:8F:CC:A3 before launch); MSG91 recharge; YouTube promo URL optional; consider rotating master OTP 1039 now that review is in flight.

### 2026-11-04 — iOS release pipeline wired (owner ruling: this Mac never builds iPhone — CI only)

- This machine has no full Xcode (CommandLineTools only) — per the owner, iOS builds happen on GitHub Actions macOS runners, never locally.
- `ios-release.yml` (fenzit-app f58282e, pushed) mirrors android-release.yml: `release`-branch trigger + workflow_dispatch, tests (TZ Asia/Kolkata), verify:version, verify:store, bun install. Runner macos-15 (Xcode 16, RN 0.87).
- Signing/upload pattern (researched, modern): App Store Connect **API key** drives everything — `xcodebuild -allowProvisioningUpdates -authenticationKeyPath/ID/IssuerID` creates the App Store distribution profile at build time (no cert .p12 / profile secrets, no match), and `fastlane pilot upload --api_key_path` (API-key auth is Apple's supported CI path post-altool) pushes to TestFlight with `--skip_waiting_for_build_processing` (processing queue is 10–30 min — runner must not wait). IPA also attached to the v<version> GitHub Release for audit parity.
- Secrets required (owner-side): FENZIT_ASC_KEY_ID, FENZIT_ASC_ISSUER_ID, FENZIT_ASC_KEY_P8 (.p8 content, Admin/App Manager role key), FENZIT_APPLE_TEAM_ID. DEVELOPMENT_TEAM is passed as a command-line override (none checked into the pbxproj).
- Info.plist GOOGLE_MAPS_API_KEY is committed inline (same key as Android keystore.properties) — CI needs no extra injection.
- Prerequisite before the upload succeeds: the App Store Connect **app record for com.fenzit** must exist (signing auto-creates the profile, but pilot upload needs the record). TestFlight-first matches the repo's store policy ("RCs are the next patch sent to TestFlight first").

### 2026-11-04 — Apple Developer enrollment started (hello@fenzit.com)

- Apple Account created: Ashish Kumar / hello@fenzit.com / India / DOB on file; verification phone = Pixel 6 (+91 97173 31820) so SMS codes are readable from the device via adb. Password and CAPTCHA done by the owner directly in the browser.
- Web enrollment flow (developer.apple.com/programs/enroll) accepted the Developer Agreement but now dead-ends: new enrollments MUST go through the **Apple Developer app** on iPhone/iPad/Mac (web alternative = "contact us" support route). Next step is manual on the Mac: App Store → sign in with the new Apple ID → install the free Apple Developer app → Account tab → enroll as Organization (Fenzit LLC, owner has a D-U-N-S number), then the $99 purchase (owner's card). Apple verifies the D-U-N-S + entity before membership activates (days, occasionally weeks).
- Blocked-on-membership chain: Developer Program approval → ASC API key creation → FENZIT_ASC_* secrets + FENZIT_APPLE_TEAM_ID → com.fenzit app record → re-run ios-release workflow. iOS CI is otherwise fully wired.
