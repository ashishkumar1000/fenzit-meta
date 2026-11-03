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
