# Role-Selected Onboarding — "Staff vs Owner, slightly different flow" Analysis

Status: analysis complete, 2026-10-24 · Companion to [onboarding-redesign-scope.md](onboarding-redesign-scope.md) · Evidence: `fenzit-app/src/features/auth/` (AuthFlow, routeAfterVerify, roles.ts), backend auth contract.

## The one design fact everything hangs on

**In Fenzit the phone number decides the role; the picker only declares intent.** A number is already attached to a company and a role (owner created it, or an admin invited it), and `verify-otp` returns that truth — `role`, `tenantId`, `formerMember`, `platformAdmin` — which `routeAfterVerify` (`AuthFlow.tsx:61`) branches on today. So the Stitch "How will you use Fenzit?" screen cannot be an identity selector; it is an **intent selector**: it personalises what we show and what we promise, while the OTP response stays the source of truth. When intent and truth disagree, the app follows the phone and says so in one friendly line — it never blocks, never creates a second experience.

## Where the picker sits

```
Welcome hero (our logo via BrandMark, one verified line)     [W]
  └─ "How will you use Fenzit?" intent picker                [R]  ← Stitch stage 2, rebuilt in our DS
       ├─ "I run a business"            (owner intent)
       ├─ "I work in the field"         (staff intent)
       └─ Skip = neutral (exactly today's behaviour)
  └─ Phone → OTP                                             (exists, unchanged)
       └─ intent × verified truth → one of the outcomes below
```

Selection cards reuse the Stitch radio-card pattern in our tokens (selected ring `colors.borderFocus`, check disc `colors.primary`, lucide icons, ROLE-style labels "Owner/Admin" and "Employee"). Skip stays available: neutral users get today's routing with the neutral tour.

## The two flows (the "little difference")

Common trunk: welcome → intent → phone → OTP. The flows diverge **after** OTP, and only in four places: which tour slides, which primer rows, whether company setup appears, and what "first win" the ending points at.

| Step | Owner intent | Staff intent |
|---|---|---|
| Tour slides | Assign jobs → live status updates + proof → reports & attendance (3) | Today's jobs → 6-step job with photo/signature → works offline (2–3) |
| Company setup | Appears for a brand-new person (existing ProfileScreen — `businessTypes` chips already there) | Never appears |
| Permissions primer [P] | Rows framed for managing a team: location (attendance & job-site validation), camera (photo proof) | Rows framed for personal use: location (check-in & navigation), camera (photo proof) |
| Landing | Home + activation checklist: invite employee → add customer → create job [A] | Today tab (existing empty state), "your assigned jobs appear here" |

## Reconciliation matrix — intent × what verify-otp says

Every cell must land somewhere useful; none may dead-end. This is the QA contract for the flow.

| You selected | Verify says | What happens |
|---|---|---|
| Owner | New person (no company, no role) | Company setup → owner tour → primer → Home + checklist (today's path + tour) |
| Owner | `company_admin` or `viewer` of a company | Short owner tour → Home ("Welcome back") |
| Owner | `employee` of a company | One-line correction: "This number is on **\<Company\>**'s team as a field employee." → employee tour → Today. Their real experience wins |
| Staff | Invited/active `employee` | Employee tour → primer → Today — the happy path |
| Staff | `company_admin` of a company | One-line correction: "This number runs **\<Company\>**." → owner tour → Home |
| Staff | New person (unknown number) | **No company creation.** Help screen: "You're not on a team yet — ask your admin to invite +91XXXXXXXXXX", with an escape link "I run my own business → set up a company" |
| Either | `formerMember` (removed) | Existing NoAccessScreen, unchanged |
| Either | `platform_admin` | Existing plain message, unchanged |
| Skipped | anything | Exactly today's routing (`routeAfterVerify` as written) with the neutral tour |

## Why the picker earns its place (not just personalisation)

Today an employee who installs the app **before** the owner invites them is treated as a brand-new person: `routeAfterVerify` sends them to company setup, and one tap later they own a stray company. Their real invite then hits the "phone already in a company" refusal. The staff intent closes this trap for the most common real-world install order (owner shares the app, employees install first). That is a functional win, not a cosmetic one, and the reason to keep the picker even though the phone already decides the role.

## Cost and repo impact

- **Frontend-only.** The verify response already carries role/tenant/`formerMember`; `setupCompany` already refuses with 409 when the number belongs to a company. `AuthFlow` gains the intent step and `routeAfterVerify(user, intent)` gains the matrix above; one small new screen (the staff-and-unknown help screen) reusing the NoAccess pattern.
- **No backend change, no schema change.** fenzit-be is untouched by this feature.
- Logo: use the existing `BrandMark` (`assets/branding/logo.png`, blue "F") — replaces every Stitch placeholder "img" box and the "FIELD OS" badge.

## Copy rules per role

Same verified-claims list as the scope doc (§Design principles), phrased per audience: owner copy speaks about the team ("see job status update live", "proof on every job"); staff copy speaks about the day ("your jobs today", "six taps, works offline"). Never show an owner row to a staff member or vice versa; the primer's notifications row stays hidden until push ships (scope D4).
