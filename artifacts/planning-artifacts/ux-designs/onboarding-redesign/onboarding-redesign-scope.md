# Onboarding Redesign — Scope & Definition

Status: proposed, updated 2026-10-24 after product decisions · Evidence: [stitch-designs-analysis.md](stitch-designs-analysis.md) · [role-selection-flow-analysis.md](role-selection-flow-analysis.md) · Product facts: [designer-input-brief.md](designer-input-brief.md)

Decided by the product owner: keep our theme and logo (BrandMark) · remove everything Fenzit doesn't have · include the staff/owner selection with a slightly different flow per role (analysis in the role-selection doc).

## Goal

Turn the current role-blind, partly-overselling 3-slide tour into a **role-aware, verified-claims-only onboarding** that ends by pointing each user at their real first win — using **only** our existing design system. No new features are invented; anything the Stitch designs showed that isn't in Fenzit is explicitly out (see §6).

## Design principles (contract for every screen)

1. **Our DS only** — tokens from `src/theme/`, lucide icons, existing `Button`/`OnboardingSlide` patterns. The Kinetic Field theme (orange/slate/emerald, Plus Jakarta Sans, Material Symbols) is rejected.
2. **Verified claims only** — the safe list in brief §D.13 (live job-status updates, photo + signature proof, works offline, exact-address navigation, attendance & leave, branded PDF reports) plus structural truths (OTP-only, 6-step workflow). Nothing about GPS tracking, payments/invoicing, trials, SMS alerts, or customer-facing surfaces.
3. **Role-aware, after the role is known** — role comes from the phone identity post-OTP; no self-selected role picker before login.
4. **Prompts fire from context, never from a tour** — the primer explains; the actual OS permission requests stay attached to the first feature use (camera → first photo step, location → first check-in / first navigate).
5. **End at activation, not at an empty app** — the owner's path must name the first win: invite an employee → add a customer → create a job.

## Target flow

```
App first launch
└─ Welcome hero (BrandMark logo, one verified line)        [W]
   └─ "How will you use Fenzit?" intent picker             [R] (owner / staff / skip = neutral)
      └─ Phone → OTP                                       (exists, unchanged)
         └─ intent × verified role (routeAfterVerify):
            ├─ Owner intent
            │  ├─ new person → Company setup (exists; businessTypes chips already there)
            │  ├─ owner tour (3 slides, verified)          [O1]
            │  ├─ Permissions primer (owner rows)          [P]
            │  └─ Home + activation checklist              [A] (invite → customer → first job)
            ├─ Staff intent
            │  ├─ invited employee → employee tour (2–3)   [E1]
            │  ├─ Permissions primer (staff rows)          [P]
            │  └─ Today tab (existing empty state)
            ├─ Staff intent + unknown number → "not on a team yet" help screen (no company creation)
            └─ intent/truth mismatch → one-line correction, then the phone's real experience
"How a job works" per role (static)                       [F] — merged into tour slides unless D2 approves a demo
```

## Work items

| # | Item | What it is | Repo |
|---|---|---|---|
| S1 | Rewrite tour copy, remove fiction | Replace `src/features/onboarding/data.ts` SLIDES: drop "live map" and "arrival times" oversells; new verified owner + employee slide sets keyed by role | fenzit-app |
| S2 | Intent picker + role-aware delivery | Add the "How will you use Fenzit?" intent step [R] to `AuthFlow`; extend `routeAfterVerify(user, intent)` with the reconciliation matrix (role-selection doc §Reconciliation); new small help screen for staff-intent + unknown number. **Frontend-only — no BE change** (verify-otp already returns role/tenant/`formerMember`; `setupCompany` already 409s) | fenzit-app |
| S3 | Permissions primer screen [P] | New screen, orientation only (no prompt firing): role-specific rows (location = check-in & job-step validation, camera = photo proof); notifications row hidden until push ships (D4); Enable-all/Decide-later wording | fenzit-app |
| S4 | "How a job works" story [F] | Static per-role diagram in our DS: employee = real 6-step workflow with proof; owner = assign → live status updates → proof & reports | fenzit-app |
| S5 | Owner activation checklist [A] | Home "get started" card: invite employee → add customer → create job; dismiss on completion (closes brief §3 weakness "tour ends where work begins") | fenzit-app |

Ponytail note: S1–S3 are the core; S4 can merge into S1's slides; S5 is separable. Nothing here adds a dependency, a new theme, or any backend change. (Former S6 "trade chips" is dropped — company setup already collects `businessTypes`, so the Stitch idea already exists in our product.)

## Decisions

| # | Decision | Status |
|---|---|---|
| D1 | Pre-login stage | **Decided** — keep a single welcome hero + the intent picker [R]; no extra pre-login swipes |
| D2 | Demo/sample data for new companies ("aha simulator")? | **Open** — recommend no for v1; static flow story only. Demo data is a real backend product, not an onboarding garnish |
| D3 | Capture company trade at setup (chips)? | **Closed — already exists.** Company setup collects `businessTypes` (required multi-select); the Stitch chips map to it |
| D4 | Include notifications in the permissions primer? | **Open** — recommend hidden until push notifications actually ship |
| D5 | Commerce copy (free trial, paid plans) | **Decided** — none anywhere (product owner confirmed: remove what we don't have) |

## Explicitly out of scope (rejected from the Stitch set)

Live GPS/tracking surfaces · invoicing/UPI/GST/payments · free-trial & card copy · employee job-acceptance model · SMS job alerts · language switch/hindi UI · Kinetic Field theme · the Stitch picker *as an identity selector* (our picker is intent-only; the phone decides the role — see role-selection doc) · customer-facing verification claims · interactive simulator (until D2).

## Success measures (pre-launch targets, brief §G.24)

Tour completion rate ≥ 80% · ≥ 60% of new owners invite ≥1 employee in first session · time-to-first-created-job median < 10 min after signup. Instrumentation of these funnel steps is part of S1/S2.

## Next step

Only D2 (demo data) and D4 (notifications row) remain open; both have safe defaults (no demo, hide row) and don't block the core. Run `/bmad-spec` (fenzit-app only — no backend change anywhere in this scope) to turn S1–S5 into stories. Implementation follows the BMAD order spec → plan → build → review, tests only after user confirmation, `/bmad-code-review` before any commit.
