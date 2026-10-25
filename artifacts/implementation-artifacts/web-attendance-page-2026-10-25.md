# Story: fenzit-web attendance page — 2026-10-25

Direct user request: build the dedicated attendance page we scoped in the SEO story
(`web-seo-fundamentals-2026-10-25.md`) — "use hand drawn svg, use bmad". The page exists to rank
for attendance/leave searches ("attendance software for field staff") where the home page, which
must pitch three products at once, only half-answers.

## Spec

- **Route**: `/attendance`, prerendered like `/` and `/features` with its own head
  (title/description/canonical/og/twitter from `pageMeta.ts`), sitemap entry, noindex-free.
- **Target searches**: attendance software for field staff/teams, employee check-in app with GPS,
  leave management for small business India.
- **Copy**: house voice — plain English, sentence case, honest. Every claim traced to a shipped
  feature (FeaturesPage GROUPS; geofence check-in; live daily dashboard; monthly report;
  corrections with a record; leave apply/approve/revoke/on-behalf). The offline answer stays
  "not yet" — no overclaiming.
- **Sections**: back link → hero (h1 + lead + hand-drawn art) → the problem (register lives at
  the office, WhatsApp leave messages, month-end reconstruction) → how it works (4 steps with
  lucide icons) → leave in the same place → FAQ (native details, 5 honest answers) → CTA back to
  the home early-access form + link to /features.
- **Art**: one hand-drawn SVG scene in the established single-ink style (NotFoundArt model:
  primary blue lines, tint cut-outs, feTurbulence+feDisplacementMap sketch wobble, tokens only):
  office with location pin inside a dashed geofence, a phone with a large check-in button, a
  small leave calendar. Icons in steps come from lucide-react (house rule: icons are never
  hand-drawn).
- **Internal links (the point of the page)**: home Features section gets a contextual
  "attendance and leave" link beside the /features link; the footer lists both pages; the page
  links back to `/` and `/features`.
- **Speculation rules**: the template gains an /attendance hover-prerender entry, and the
  prerender guard extends to require BOTH public routes present (same protection as round 2).

## Out of scope

More use-case pages (each needs its own evidence first), header-nav changes (hash links are
home-section anchors), new dependencies, Analytics.

## Intended tests (after user confirms, per test-timing rule)

- `router.test.tsx` renders `/attendance` and asserts the h1 and `document.title`.
- prerender/entry-server checks: attendance head carries its own canonical
  `https://fenzit.com/attendance`; sitemap lists three pages.
- Footer renders the two page links; home Features section links `/attendance`.

## Status

Confirmed by the user on the local preview, tested (router covers every route's heading + title;
footer's seven links; header anchors qualified; prerender head builders in scripts/lib/page-head
with their own tests — 404 tests green), reviewed via /bmad-code-review (4+4 findings — missing
.step class, dead header anchors, hand-written output paths, untested route/prerender/footer
wiring — all fixed in this change, nothing deferred), COMMITTED: fenzit-web 8494780, deployed.
