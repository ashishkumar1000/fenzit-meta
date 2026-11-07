---
title: 'Web Android launch: remove early access, add Google Play download CTAs'
type: 'feature'
created: '2026-11-07'
status: 'in-progress'
route: 'full'
baseline_revision: 'ba1c31b6da559c57da8c615a6bc3e9cb56fd78ff'
review_loop_iteration: 0
context:
  [
    '{project-root}/workspace/core/frontend/fenzit-web/CLAUDE.md',
    '{project-root}/artifacts/planning-artifacts/ux-designs/ux-fenzit-2026-11-07/DESIGN.md',
    '{project-root}/artifacts/planning-artifacts/ux-designs/ux-fenzit-2026-11-07/EXPERIENCE.md',
  ]
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** The Fenzit Android app is live on Google Play, but fenzit-web still markets a
pre-launch product: an early-access email form on the home page, "join the waitlist"
copy on every inner page, and "Launching 2026" in the home meta tags. There is not one
link to the store listing.

**Approach:** Remove every early-access surface and string from fenzit-web, and point
download demand at the one confirmed listing — `https://play.google.com/store/apps/details?id=com.fenzit`
— through a shared badge component and one config URL, designed per the UX delta spines
(DESIGN.md / EXPERIENCE.md in `artifacts/planning-artifacts/ux-designs/ux-fenzit-2026-11-07/`).
Android only: no iOS mention anywhere.

## Boundaries & Constraints

**Always:** Use design tokens and existing components (`LinkButton`, `SectionHeading`,
`Container`, `Header`, `Footer`). One source of truth for the store URL in
`src/config/`, used by badge, footer and FAQ. Play links are external
(`target="_blank"`, `rel="noopener noreferrer"`). Keep meta descriptions 25–160
characters. Indian English in copy. No new pages — `PUBLIC_PAGES`, routes, sitemap and
speculation rules are unchanged.

**Ask First:** Any copy promising something beyond "90 days free" and "live on Google
Play". Any change to the fenzit-be `/api/v1/early-access` endpoint or its stored data
(backend cleanup is a separate, later change).

**Never:** iOS, iPhone, App Store or "coming soon to iOS" wording anywhere. Any
early-access/waitlist wording, form, bell/zap badge, or the notify form. Recolouring or
CSS-rebuilding the Google Play badge. New token values (no edits to `src/theme/`).
Committing or pushing before `/bmad-code-review` and user consent.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Tap any download CTA | Any page, any viewport | Play Store listing opens in a new tab | N/A (native tab) |
| Screen reader on badge | Badge focused | Accessible name "Get Fenzit on Google Play (opens the Play Store)" | N/A |
| 360px viewport | Home or any inner page | Badge and buttons wrap; no horizontal scroll | N/A |
| Keyboard user | Tab through hero/panel/footer | Badge is one visible focus stop per instance | N/A |
| Home meta tags | Crawl or share preview | Descriptions say live on Google Play, no "Launching 2026", 25–160 chars | N/A |
| Early-access remnants | Grep the repo | No "early access"/waitlist copy, no notify form, no dead imports | Build fails on dead imports |

</frozen-after-approval>

## Code Map

- `src/config/appStores.ts` (new) — `PLAY_STORE_URL` constant; the only place the listing URL appears
- `src/components/ui/StoreBadge.tsx` (new) + `.module.css` — official "Get it on Google Play" badge, `md` (56px) / `sm` (48px) sizes, external anchor
- `src/assets/brand/` — official badge PNG (fetched from Google's badge CDN; fallback if unreachable: inline SVG of the badge, decided at build)
- `src/features/landing/components/EarlyAccess.tsx` + `.module.css` — deleted; replaced by GetApp
- `src/features/landing/components/GetApp.tsx` (new) + `.module.css` — the `#get-app` panel per DESIGN.md
- `src/features/landing/components/NotifyForm.tsx` + `.module.css` + `.test.tsx` — deleted with the form
- `src/features/landing/earlyAccessAction.ts`, `earlyAccessApi.ts`, `homeAction.ts`, `homeAction.test.ts` — deleted; home route action becomes `callBackAction` directly
- `src/features/landing/components/ContactForms.tsx` — drop the hidden `intent` field and its comment (single home form now)
- `src/features/landing/components/Hero.tsx` + `.module.css` — primary CTA becomes the badge; secondary buttons unchanged
- `src/features/landing/components/Header.tsx` + `.test.tsx` — strip text "The Fenzit Android app is live on Google Play." + "Get the app" → `/#get-app`
- `src/features/landing/components/Faq.tsx` — "How do I get the app?" and install answers link to the listing
- `src/features/landing/components/Footer.tsx` + `.module.css` — card note "Android app on Google Play"; `StoreBadge` sm in the contact row
- `src/features/use-case/components/UseCasePage.tsx` — hero + bottom CTAs become "Get the app on Google Play" (external)
- `src/features/use-case/content/serviceBusiness.ts` — FAQ answer rewritten for the live app
- `src/pages/AttendancePage.tsx` — same CTA swap as UseCasePage
- `src/pages/HomePage.tsx` — EarlyAccess → GetApp in the section list
- `src/app/routes.tsx` — home `action` → `callBackAction`; comment updated
- `src/app/pageMeta.ts` — privacy-policy description drops "early access"
- `src/pages/legalCopy.ts` — privacy-policy copy drops the early-access purpose
- `index.html` — home description, og:description, twitter:description: drop "Launching 2026.", state the Play launch
- `public/llms.txt` — one Company-section line for the Play listing
- `artifacts/implementation-artifacts/deferred-work.md` — record: BE endpoint + stored sign-ups cleanup, QR code idea

## Tasks & Acceptance

**Execution:**
- [ ] `src/config/appStores.ts` — add `PLAY_STORE_URL` — one URL, no drift
- [ ] Badge asset — fetch official PNG into `src/assets/brand/`; if unreachable, inline SVG per DESIGN.md assumption — real badge, not a hand-drawn icon
- [ ] `StoreBadge.tsx` + `.module.css` — shared component, two sizes, named external anchor — every download CTA uses it
- [ ] `GetApp.tsx` + `.module.css` — replace EarlyAccess in `HomePage`; anchor `#get-app`; reuse panel tokens; phone art reuses existing hero panel pattern or is omitted — no new artwork
- [ ] Delete `EarlyAccess*`, `NotifyForm*`, `earlyAccessAction`, `earlyAccessApi`, `homeAction*` — no dead code or dead routes
- [ ] `routes.tsx` action swap + `ContactForms.tsx` intent removal — call-back still posts and validates as today
- [ ] `Hero`, `Header`, `Faq`, `Footer`, `UseCasePage`, `AttendancePage`, `serviceBusiness.ts` copy + CTA swaps per EXPERIENCE.md table
- [ ] `index.html`, `pageMeta.ts`, `legalCopy.ts`, `llms.txt` — launch copy, no iOS, lengths within 25–160
- [ ] Update `Header.test.tsx` for the new strip; delete form/action tests of removed code
- [ ] `artifacts/implementation-artifacts/deferred-work.md` — BE cleanup + QR entries

**Acceptance Criteria:**
- Given any public page, when it renders, then no element mentions early access, a waitlist, iOS or "Launching 2026", and at least one Play Store link exists on home, every use-case page, the attendance page and the footer
- Given the home page, when the visitor scrolls past CallBack, then the `#get-app` panel shows the badge, the 90-days-free line and a "Book a demo" fallback link
- Given the call-back form, when submitted with valid input, then it succeeds exactly as before (intent field gone, same backend request)
- Given 360px width, when any touched page renders, then there is no horizontal scroll
- Given `bun run typecheck && bun run lint && bun run build && bun run test`, then all pass

## Design Notes

UX contract is the delta pair in `artifacts/planning-artifacts/ux-designs/ux-fenzit-2026-11-07/`
(spines win on conflict with this file). The badge is Google's official asset, used
unmodified per their brand rules. The notify form's backend (`POST /api/v1/early-access`)
keeps working — the web simply stops calling it; data cleanup belongs to fenzit-be in a
later change, recorded in the deferred-work ledger.

## Verification

**Commands:**
- `bun run typecheck` — expected: no errors
- `bun run lint` — expected: no errors
- `bun run check:styles` — expected: every new component paired with its module
- `bun run build` — expected: prerender succeeds; home HTML carries the new meta copy
- `bun run test` — expected: green (remaining suites), removed suites gone
- `grep -rni "early access\|waitlist\|iOS\|Launching 2026" src index.html public/llms.txt` — expected: no hits

**Manual checks (if no CLI):**
- Playwright screenshots at 1280px and 360px: hero, `#get-app`, footer, one use-case page — for user review before push

## Plan Change Log

- 2026-11-07 (user request during review): round the Play badge to match the buttons — `--radius-md` clip on the badge image, focus ring radius aligned, asset's transparent margin trimmed once with Pillow (official artwork otherwise unmodified). Overrides the DESIGN.md "don't round" line, now amended in the spine.

## Code Review

### 2026-11-07 — `/bmad-code-review` (thorough: edge-case-hunter + verification-gap lenses over the full diff since `ba1c31b`)

**Code review complete.** 0 decision-needed, 3 patch, 3 defer, 1 rejected. All checks re-run green after the patches (typecheck, lint, check:styles, prerender build, 469 tests).

Findings (patch items were applied during this run — the user was away; each was a direct correction, re-verified):

- [x] [Review][Patch] LinkButton allowed `external` with `to`, silently ignored on the router branch [workspace/core/frontend/fenzit-web/src/components/ui/LinkButton.tsx] — applied: `external` is structurally excluded on the `to` variant, so a caller cannot ask for a new-tab internal link.
- [x] [Review][Patch] Attendance page FAQ still said "We will share how to get it when access opens", contradicting its own Google Play CTA (missed by the remnant grep — the string never says "early access") [workspace/core/frontend/fenzit-web/src/pages/AttendancePage.tsx:57] — applied: answer now names the Fenzit Android app on Google Play.
- [x] [Review][Patch] Stale comment named the deleted "Join early access" section as CallBack's padding dependency [workspace/core/frontend/fenzit-web/src/features/landing/components/CallBack.module.css:1] — applied: comment names "Get the app"; the spec's grep verification now passes as written.
- [x] [Review][Defer] No route-level test guards the home action binding (`action: callBackAction`) — deferred: repo test-timing rule (implement → user confirms → tests); recorded in deferred-work.md with the other post-confirmation tests.
- [x] [Review][Defer] The removal invariant (no early-access/waitlist/"Launching 2026"/iOS strings) has no automated check — deferred: same rule; recorded in deferred-work.md.
- [x] [Review][Defer] Stale cached home pages can still post the removed early-access form to "/" right after deploy; callBackAction records those as call_back leads — deferred: transient cache-purge window, rows are human-reviewable; recorded in deferred-work.md.

Rejected:

- `false` — StoreBadge fixed-height squash: no layout in the repo can hand the badge a container narrower than its rendered width (~145px) — wrapping flex rows and a single-column panel at the 360px minimum keep the badge at its natural size, so `max-width: 100%` never engages.

Noted, not a finding: two timing flakes in `router.test.tsx` home tests observed once in three full-suite runs (green twice after); folded into the deferred post-confirmation test work.
