# Story: fenzit-web navigation and copy round — scroll, brand-home, region-neutral

- **Date:** 2026-10-25
- **Status:** Done — user confirmed on local preview; committed as fenzit-web `5b4f181` and `406c267`, pushed to main (deploys to fenzit.com).
- **Requests:** three direct user asks after the 15-page expansion — (1) links left you scrolled at the bottom of the next page; (2) remove India-centric wording ("we are building this for everyone"); (3) the Fenzit logo should link home and the "Back to home" links should go.

## What shipped

1. **Scroll restoration** — `RootLayout` renders react-router's `<ScrollRestoration />`: every
   client-side navigation opens at the top, back/forward restores the reader's place. Tested
   for both halves (PUSH to top; POP restores the saved `scrollY`).
2. **Region-neutral copy** — one meta title ("for Indian teams" → "for small teams"), four
   meta descriptions, ten content leads rewritten; `areaServed: "IN"` removed from the
   Organization JSON-LD; support languages trimmed to `["en"]`. The sign-in flow keeps its
   honest +91-only message (real backend constraint, flagged to the user — global phone
   sign-in is a fenzit-be change if wanted).
3. **Logo-home navigation** — the header brand is a router `Link` to `/` on every page;
   "Back to home" removed from the use-case template, features and attendance pages with
   their CSS; the 404 keeps its "Go home" button (only way back from a wrong URL).

## Code Review

BMAD code review (thorough, no-plan), 2026-10-25, before commit. Layers: edge-case-hunter,
verification-gap. Diff 23 files, +70/−84.

| # | Finding (source) | Verdict | Disposition |
|---|---|---|---|
| 1 | Back/forward restoration now depends on ScrollRestoration (which sets `history.scrollRestoration = "manual"`, disabling native restoration), but only the PUSH half was tested — a POP regression would land every back click at the top, suite green (verification-gap) | medium | **Patched** — router test scrolls, navigates away, comes back via `router.navigate(-1)`, and asserts `scrollTo(0, 240)` restores the saved position. |
| 2 | Nothing would fail if India markers returned — the only title test is derived from the same meta objects, and `validateTemplateBlocks` never reads ld+json content (verification-gap) | medium | **Patched** — new `pageMeta.test.ts` asserts no `/india/i` in any PUBLIC_PAGES title/description and a region-neutral ld+json (no `areaServed`, `availableLanguage === ["en"]`); `registry.test.ts` asserts no region markers in any use-case copy. |
| 3 | Claim "length budgets enforced by registry tests" was false — distinctness only, use-case subset only, no length assertion anywhere (edge-case-hunter, claim) | low | **Patched** — `pageMeta.test.ts` enforces titles ≤ 60 chars, descriptions ≤ 200 chars, and distinctness across all 22 PUBLIC_PAGES (not just use-case pages). |
| 4 | The +91-only sign-in flow is the strongest remaining India signal a visitor meets (verification-gap, other) | — | **Noted, not this change** — pre-existing tested product constraint; already surfaced to the user as the fenzit-be scope for worldwide sign-in. |

Rejected: none. Deferred: #4 with the reason above.

## Verification

tsc clean; eslint clean; check:styles 54 files; check:design-system pass; 455 tests (was 449);
build prerenders 23 pages; served preview shows the logo anchor and zero "Back to home".
One mid-round correction: removing the `Link` import from AttendancePage broke its later
related-page links (tsc caught it) — import restored.
