# Story: fenzit-web use-case pages (field-tracking cluster) — 2026-10-25

Direct user request, same day as the attendance page: field tracking is the USP — build five
use-case pages for it, with multiple agents, under BMAD. Five copy-strategist agents drafted the
page briefs in parallel, each grounded in a strict shipped-features manifest so nothing overclaims
("live tracking" = live job status + location at the steps + distance from site; no live maps, no
route planning, no offline — every page says so where relevant).

## The five pages

| Route | Use case |
|---|---|
| `/field-job-tracking` | USP pillar: live field job tracking for any field team |
| `/ac-service-software` | AC and appliance service businesses |
| `/plumber-software` | Plumbing teams of 2–20 |
| `/delivery-tracking` | Local delivery teams with photo + signature proof |
| `/collection-agent-tracking` | Collection/field-visit teams with proof of visit |

Plus `/attendance` from its own story — the site goes from 2 public pages to 8.

## Structure (shared template)

`src/features/use-case/components/UseCasePage.tsx` renders the shared structure (hero with art,
problem, how-it-works steps, FAQ, early-access CTA + sibling links); each page is a content
module in `src/features/use-case/content/` (pure data, component references only — no JSX, so
the CSS-modules checker's scope stays honest). Art: five distinct hand-drawn scenes in
`src/features/use-case/art/UseCaseArt.tsx`, single-ink house style with the sketch-wobble filter.

## Wiring

- `pageMeta.ts`: five new meta entries (unique titles/descriptions, sentence case).
- `routes.tsx`: five routes pairing `UseCasePage` with its content.
- `prerender.ts`: five entries in the page table — sitemap is now 8 URLs; the ld+json and
  speculation-rules guards check every public route automatically.
- `index.html`: speculationrules hover-prerender entries for all seven non-home public routes.
- Links: footer lists all seven public pages; the home Features section links attendance, field
  tracking and the feature list; every use-case page links its siblings (hub = the pillar page).

## Intended tests (after user confirms, per test-timing rule)

- `router.test.tsx`: each new route renders its h1 and document title.
- Footer renders all seven page links; home Features section links the new pages.
- Prerender checks: all eight heads carry their own canonical; sitemap lists eight URLs.

## Status

Confirmed by the user on the local preview, tested (router covers every route's heading + title;
footer's seven links; header anchors qualified; prerender head builders in scripts/lib/page-head
with their own tests — 404 tests green), reviewed via /bmad-code-review (4+4 findings — missing
.step class, dead header anchors, hand-written output paths, untested route/prerender/footer
wiring — all fixed in this change, nothing deferred), COMMITTED: fenzit-web 8494780, deployed.
