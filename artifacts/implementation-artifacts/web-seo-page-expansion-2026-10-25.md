# Story: fenzit-web SEO page expansion — 15 more use-case pages

- **Date:** 2026-10-25
- **Status:** Done — user confirmed on local preview; committed as fenzit-web `f8a2b9c`, pushed to main (deploys to fenzit.com).
- **Request:** "similarly add 15 more pages... each page will be done by a separate agent" (continuing the use-case page pattern; user wants search coverage for every trade/keyword near the product).

## What shipped

Fifteen pages, each built by its own agent (content module + hand-drawn single-ink SVG scene
with a unique turbulence filter id), on the shared `UseCasePage` template:

- **Trades (10):** `/cleaning-services-software`, `/pest-control-software`,
  `/electrician-software`, `/appliance-repair-software`, `/water-purifier-service-software`,
  `/cctv-installation-software`, `/solar-installation-software`, `/it-amc-software`,
  `/facility-management-software`, `/salon-at-home-software`.
- **Product keywords (5):** `/employee-attendance-app`, `/geofencing-attendance`,
  `/leave-management-software`, `/technician-tracking-software`,
  `/service-business-software` (umbrella).

Copy stays inside the shipped-features manifest (jobs with skill/customer/pin, assignment,
live status, location at steps, photos + signature, PDF reports, GPS-verified attendance,
leave requests/approvals); missing capabilities are answered "Not yet" (no live maps, route
optimisation, offline, inventory, invoicing, customer portal, recurring jobs, biometrics,
leave-balance deductions).

Structural change: `src/features/use-case/content/registry.ts` now lists all 20 use-case
content objects. Routes are generated from it; `siblingsFor()` derives each page's four
"Fenzit also helps" links from it (rotated, so each page leads with a different set), and
`UseCaseContent` swapped the hand-written `siblings` array for a `shortLabel`. `pageMeta.ts`
gained the 15 `PageMeta` constants plus `PUBLIC_PAGES`, which `scripts/prerender.ts` walks
for prerender + sitemap. Footer nav lists all 22 public pages; speculationrules cover all of
them (build-guarded). The site is 23 public pages; sitemap has 23 URLs.

Three agents hit the provider usage limit mid-run and were relaunched after the reset; two
partially written sets were verified complete rather than rewritten.

## Verification

tsc clean; eslint clean; check:styles 54 files; check:design-system pass; 446 tests pass
(registry-driven title+heading checks for all 20 use-case pages, footer=PUBLIC_PAGES,
sibling-link rendering per page, registry consistency suite); full build prerenders 23 pages;
wrangler preview on :8799 returned 200 with correct single title/h1/canonical on sampled new
pages.

## Code Review

BMAD code review (thorough; no-plan mode), 2026-10-25, before commit. Layers:
edge-case-hunter, verification-gap. Diff 58 files, +3565/−98 (reviewed unchunked — the bulk
is 15 same-shape page pairs, and the interesting risks were cross-file).

| # | Finding (source) | Verdict | Disposition |
|---|---|---|---|
| 1 | `PUBLIC_PAGES` and `ALL_USE_CASE_CONTENT` can drift apart; dropping a meta passes every check while the footer links a 404 shell and the sitemap loses the URL (edge-case-hunter + verification-gap) | high | **Patched** — `registry.test.ts` asserts registry paths equal PUBLIC_PAGES' use-case subset, in order, and no duplicate paths. |
| 2 | Footer nav is a third hand-kept list, pinned by a hand-copied test literal; a forgotten footer link passes everything (edge-case-hunter + verification-gap) | medium | **Patched** — footer test now expects `PUBLIC_PAGES.map(p => p.path)`; the literal is gone. |
| 3 | Sibling cross-links on all 20 pages have no test; a self-link or copy-pasted label would ship in static HTML (verification-gap) | medium | **Patched** — router test asserts, per page: four sibling links, distinct hrefs, none self, each label equals the target's `shortLabel`. |
| 4 | Router test derives heading expectations from the same object the route renders, so copy-pasted copy across agent files ships green (edge-case-hunter deletion + verification-gap) | medium | **Patched** — registry test asserts headings, leads, short labels, titles and descriptions pairwise distinct; exact h1/title match per page remains registry-driven. |
| 5 | `prerender.ts` derives output files from `PUBLIC_PAGES` unguarded; a slash-less or duplicate path would miswrite dist or overwrite home (edge-case-hunter) | low | **Patched** — prerender throws on duplicate paths and on PUBLIC_PAGES entries without a leading slash or equal to "/". First version wrongly also rejected the home page's own "/" entry; caught by the build and narrowed to PUBLIC_PAGES. |
| 6 | Registry/UseCasePage comments claim a new page is "linked from every other page"; the rotation caps at four (verification-gap, other) | low | **Patched** — both comments reworded to the rotation reality. |

Rejected: none. Deferred: none (user's standing instruction: fix findings immediately).

All patches applied, then the full gate re-run green (the pre-commit hook runs eslint,
prettier, check:styles, check:design-system, tsc and the full test suite).
