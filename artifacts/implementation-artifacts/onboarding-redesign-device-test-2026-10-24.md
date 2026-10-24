# Onboarding/Login Redesign — Physical Device Test Round

Date: 2026-10-24 · Device: Pixel 6 (`1C301FDF6002ZB`), Android, debug build v1.0.0 (installed 20:13, Metro serving the working tree) · Backend: production `https://api.fenzit.com` · Master OTP `1039` (pre-release gate, user-confirmed) · DB: Supabase `pnlvreaijzslfymlnoti` (Fenzit-Be, production).

Feature under test: the onboarding/login redesign (scope: `artifacts/planning-artifacts/ux-designs/onboarding-redesign/onboarding-redesign-scope.md`; code-reviewed same day, 4 lenses, 1 deferred item). Frontend-only. Uncommitted in `fenzit-app` at test time.

## Test data

| Role | Number | Started as |
|---|---|---|
| Owner O | 9999940001 | unused (verified in DB pre-round) |
| Employee E | 9999940002 | unused |
| Stranger U | 9999940003 | unused (staff intent, no company) |
| Fresh F | 9999940004 | unused (decide-later round) |
| Throwaway T | 9999940005 | unused (lockout/expiry negatives) |

`pm clear com.fenzitapp` between rounds simulates a fresh install (clears the MMKV onboarding keys).

## Test cases

### Happy path
- **H1** Fresh install → new Welcome hero (brand glyph, one verified line, Get started). Old 3-slide tour gone.
- **H2** Intent picker "What do you do?": two radio cards (STAFF "I am an Employee" / OWNER "I run the business"); Continue disabled until a pick; back arrow returns to the welcome hero.
- **H3** Owner intent → Phone (owner number) → OTP screen (4-digit copy) → master OTP 1039 → brand-new person routes to **Company setup**.
- **H4** Company setup: business name + owner name + ≥1 business type + city/state → submit → owner app; **FirstRunFlow opens on HowItWorksScreen** ("How every job runs": check-in / steps / proof cards).
- **H5** Continue → **PermissionsPrimerScreen** (owner copy; location + camera rows showing LIVE OS state) → Continue fires the OS permission prompts one after another → accept → reward screen "You're all set" (~1.6 s) → Home.
- **H6** Fresh-owner Home renders sensibly (empty state, bell, quick actions).
- **H7** Owner invites employee E from the UI (Technicians invite flow).
- **H8** Employee E first login (staff intent) lands in the **employee** app: FirstRunFlow goes **straight to the primer** (owner tour skipped), then Today tab.
- **H9** Staff intent + uninvited number U → **NotOnTeamScreen** ("Not on a team yet", warning strip, the number to hand over, share).
- **H10** Mismatch corrections (role-aware, never a dead end):
  - **H10a** owner intent on employee E's number → one-line notice "…registered as a field employee — here's the employee app", lands on the **primer** (no owner tour).
  - **H10b** staff intent on a number that runs a company → notice "This number runs a company on Fenzit — here's the owner app", lands on the **owner tour**.

### Corner cases
- **C1** "Decide later" (skip intent) → fresh number F routes to Company setup (documented deferred behavior: intent null ≡ owner). No crash; the stray-company trade-off is a recorded review deferral, not a bug to fail here.
- **C2** NotOnTeamScreen "Set up new company" escape → Company setup; completing it makes U an owner; **H10b** notice then appears because the install's intent stayed `staff`.
- **C3** NotOnTeamScreen "Use another number" → back to Phone screen.
- **C4** NotOnTeamScreen **Share** → Android share sheet opens with the number text; cancel returns safely.
- **C5** Primer permission rows: before = Allow pills; after OS grant = green checks. Deny-once keeps the pill; permanently-denied Allow opens the app's Settings page.
- **C6** Kill + relaunch mid-first-run: flow reappears (firstRunDone not yet set), from the role's first step.
- **C7** Completed install: logout → login screen greets **"Welcome back"** (returningUser), and the welcome/intent stage does **not** re-show.
- **C8** Completed install: kill + relaunch → straight into the app; FirstRunFlow never repeats.
- **C9** Shared-device intent leak (known deferred issue): staff-intent install → a real login completes first run → logout → brand-new owner number logs in → **expected (documented): routes to NotOnTeamScreen** (wrong-but-recoverable via the escape). Record, don't fail — needs product decision per deferred-work.md.

### Negative
- **N1** Wrong OTP (0000) → "Wrong code. Try again.", boxes clear, stays on OTP screen.
- **N2** Short phone number (5 digits) → Continue blocked client-side (PHONE_LENGTH).
- **N3** OTP expiry (5-min TTL): request on T, wait out the TTL, enter 1039 → expiry error path ("That code has expired. Please ask for a new one.").
- **N4** OTP lockout: 5 wrong codes on T → OTP_SESSION_LOCKED → back to Phone with "Too many wrong codes. Please ask for a new one."
- **N5** Company setup validation: empty submit → "Enter your name."; name but no business type → "Select at least one business type."
- **N6** setupCompany 409 (invited person insists on creating a company) → NO_COMPANY_MESSAGE copy — only reachable if an invited-but-not-signed-in number lands on NotOnTeamScreen; decide after Round C.
- **N7** OTP send rate limit (5/10 min per number) → "Too many attempts…" — record only if naturally observed; do not burn main numbers.

## Results

_Filled in as the round executes — see the final section for the verdict._
