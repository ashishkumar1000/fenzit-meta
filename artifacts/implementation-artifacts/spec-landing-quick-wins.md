---
title: 'Landing quick wins: phone, call back, demo, four pages, 3-month trial'
type: 'feature'
created: '2026-10-28'
status: 'draft'
review_loop_iteration: 0
context: ['{project-root}/workspace/core/frontend/fenzit-web/CLAUDE.md']
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** The landing site has no phone number, no call-back or demo option, no pricing or trial message, and too few public pages for buyers who compare us with competitors.

**Approach:** Add the phone number and tel links, a demo page, and four plain public pages (pricing, book a demo, data safety, partners) using the existing page template. State the 3-month free trial for everyone on the hero and early-access perks. No backend change: call-back uses a tel link, not a stored request.

## Boundaries & Constraints

**Always:** Use design tokens and existing components (`LinkButton`, `SectionHeading`, `Container`, `Header`, `Footer`). Plain English, no jargon. Every new page is registered in `PUBLIC_PAGES` so it is prerendered and in the sitemap. Phone shown as `+91 92792 30451`, linked as `tel:+919279230451`.

**Ask First:** Any page copy that makes a promise beyond the 3-month trial (price amounts, SLAs, partner terms). Any real call-back or demo request form (needs a fenzit-be endpoint first, deployed before fenzit-web).

**Never:** Stored call-back or demo requests. New images or illustrations. Pricing amounts. Changes to the early-access form or its endpoint. Committing or pushing before the user has reviewed.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Tap call back | Visitor on phone | Dialer opens with +919279230451 | N/A (native) |
| Visit /book-demo | Direct URL | Page renders, prerendered, in sitemap | Unknown paths still show 404 page |
| Narrow phone | 360px wide | Strip, hero buttons and footer wrap without sideways scroll | N/A |

</frozen-after-approval>

## Code Map

- `src/features/landing/components/Header.tsx` -- top strip, add phone tel link next to strip text
- `src/features/landing/components/Header.module.css` -- strip layout for the phone link
- `src/features/landing/components/Hero.tsx` -- add "Request a call back" (tel) and "Book a demo" (/book-demo) buttons
- `src/features/landing/components/EarlyAccess.tsx` -- PERKS: add the 3-month trial line
- `src/features/landing/components/Footer.tsx` -- phone tel link in the bar; add new pages to the list
- `src/app/pageMeta.ts` -- PageMeta entries for the four pages; add to `PUBLIC_PAGES`
- `src/app/routes.tsx` -- routes for the four pages (static element, like `/features`)
- `src/pages/FeaturesPage.tsx` + `.module.css` -- layout to copy for the new pages (Header, Container, SectionHeading, Footer)
- `scripts/prerender.ts` -- reads `PUBLIC_PAGES`, so new pages are prerendered with no change here
- `src/features/landing/components/Header.test.tsx` -- existing header tests (later step)

## Tasks & Acceptance

**Execution:**
- [ ] `src/app/pageMeta.ts` -- add PRICING_PAGE, BOOK_DEMO_PAGE, DATA_SAFETY_PAGE, PARTNERS_PAGE and list them in `PUBLIC_PAGES` -- one place for titles, descriptions and sitemap
- [ ] `src/pages/SimplePage.tsx` (new) + `.module.css` -- one shared template: title, lead, sections, one call-to-action row -- the four pages share it, so layout is written once
- [ ] `src/pages/PricingPage.tsx`, `BookDemoPage.tsx`, `DataSafetyPage.tsx`, `PartnersPage.tsx` (new) -- content only, using SimplePage
- [ ] `src/app/routes.tsx` -- add the four routes -- reachable and prerendered
- [ ] `src/features/landing/components/Header.tsx` + `.module.css` -- phone tel link in the strip -- phone on every page
- [ ] `src/features/landing/components/Hero.tsx` -- add "Request a call back" (tel) and "Book a demo" (/book-demo) -- two new entry points
- [ ] `src/features/landing/components/EarlyAccess.tsx` -- perk "Everyone gets a 3-month free trial when access opens." -- trial message
- [ ] `src/features/landing/components/Hero.tsx` -- sub line or note: "3 months free for every team." -- trial message on the first screen
- [ ] `src/features/landing/components/Footer.tsx` -- phone tel link in the bar; add the four pages to the page list -- phone and links on every page

**Acceptance Criteria:**
- Given any public page, when the header renders, then the strip shows a tel link to +919279230451
- Given the home page, when it renders, then "Request a call back" links to tel:+919279230451 and "Book a demo" links to /book-demo
- Given /pricing, /book-demo, /data-safety, /partners, when requested, then each renders with a title and is listed in sitemap.xml
- Given a 360px screen, when any new page loads, then there is no sideways scroll

## Design Notes

Call-back is a tel link because a stored request needs a fenzit-be endpoint, which must deploy before fenzit-web. The page copy names only facts in the app today (phone and one-time code sign-in, company data kept separate, location only at job steps and attendance check-ins).

## Verification

**Commands:**
- `bun run typecheck` -- expected: no errors
- `bun run lint` -- expected: no errors
- `bun run build` -- expected: four new pages prerendered, sitemap lists them

**Manual checks (if no CLI):**
- Playwright CLI scan at 1280px and 360px: strip, hero buttons, footer; screenshots for review before push
