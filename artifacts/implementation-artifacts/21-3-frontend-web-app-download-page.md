---
title: 'Story 21-3: fenzit-web download page at /app/download — Android to Play, iPhone coming-soon placeholder'
type: 'feature'
epic: 'epic-21'
repo: 'fenzit-web'
status: 'in-progress'
spec: 'artifacts/specs/spec-invite-sms-download-link/SPEC.md'
stories_source: 'artifacts/specs/spec-invite-sms-download-link/stories.yaml'
deploy_order: 'after 21-1 and 21-2 are deployed; before 21-4 and before sending is switched on'
spec_checkpoint: false
---

## Intent

The invite SMS links to `https://fenzit.com/app/download`. The page sends an Android phone to the Google Play listing. iPhone users see a plain "coming soon" message until iOS launches. Desktop visitors see both. Nobody should land on a 404 or a broken store link.

## Code touchpoints (verified 2026-11-10)

| What | Where |
|---|---|
| Store links (one place) | `src/config/appStores.ts` — `PLAY_STORE_URL` exists; the file says iOS constant is added only when iOS ships |
| Public page registry | `src/app/pageMeta.ts` — `PUBLIC_PAGES` (array starting around line 234) |
| Speculation rules | `index.html` — `href_matches` entries (existing examples: `/pricing`, `/book-demo`) |
| Crawler list | `public/llms.txt` — hand-written; descriptions must match the page copy |
| Routes | `src/app/router.tsx` |
| Feature folder | `src/features/downloadApp/` (new), or the pattern the repo uses for a marketing page under `src/pages/` |
| Existing legal pages | `src/pages/LegalPage.tsx` (reference for a simple static page) |
| Standards | `docs/repos/fenzit-web/standards.md` §5 (responsive), CSS Modules rule, design tokens in `src/styles/tokens.css` |

## Behaviour

**Route:** `/app/download` (no query parameters, no token).

**Platform detection:** read `navigator.userAgent` once, on the client. Classify as `android`, `ios` (iPhone or iPad, including iPadOS desktop-mode Safari), or `other`. A missing or empty user agent is `other`. Detection is presentation only; it must not be used for security or access.

| Platform | What the page shows |
|---|---|
| `android` | Primary button "Get it on Google Play" → `PLAY_STORE_URL`. Short line: "Install the Fenzit app, then log in with your phone number." |
| `ios` | Heading "The iPhone app is coming soon". Line: "Ask your employer for the link again when it is ready." No store button. |
| `other` | Both: the Play button, and the iPhone coming-soon block. No iPhone store button. |

**iOS switch:** a constant `APP_STORE_URL: string | null = null` in `appStores.ts`. When it is `null`, the `ios` block shows the coming-soon copy. When it is set, the `ios` block shows an App Store button. Launching iOS is then a one-value change, no page rewrite.

**Static first paint:** the page renders the `other` layout on the server and on the first client render, then switches to the detected layout after mount. This avoids a blank page and avoids a hydration mismatch. Use a `useState` default and set it in a client-only effect, not a data fetch. (Note: the lint rule forbids `useEffect` in `features/` and `pages/` for fetching. A platform read is not a fetch, but confirm with the lint rule in dev; if it fires, move detection into a hook under `src/hooks/`.)

## Acceptance criteria

1. **Route and registry.** `/app/download` renders. It has a `PUBLIC_PAGES` entry (title, description of 25 to 160 characters), a route, a speculation `href_matches` entry, and a `llms.txt` line. The build fails if any of these is missing.
2. **Android** shows the Play button with the exact URL `https://play.google.com/store/apps/details?id=com.fenzit`.
3. **iPhone** shows the coming-soon copy, and no link to `apps.apple.com` while `APP_STORE_URL` is `null`.
4. **Desktop and unknown** show both blocks, with no iPhone store link.
5. **iOS switch** works: a `null` URL shows the placeholder; a set URL shows the App Store button.
6. **Copy** is plain English, sentence case, uses "Employee" where a role is named, never "Technician".
7. **No network needed.** The page renders with no API call.
8. **Responsive.** No horizontal scroll at 360, 390, 768 and 1280 px. `100dvh` for full-height layouts. Tap targets only; no hover-only controls. Respect safe-area insets. Inputs (none here) use 16 px.
9. **Styling.** Each component has a paired CSS Module. Only tokens: no raw hex, spacing or radius values. Icons from `lucide-react` only (for example, a store or phone icon, if used).
10. **Privacy copy untouched.** This story does not change `legalCopy.ts`. The policy change is already committed (`21d7683`) and ships with the SMS feature.

## Out of scope

- Any App Store link while iOS is not live.
- Deep links, Universal Links, App Links, and any token in the URL.
- Analytics events on this page.
- The privacy policy text.
- An in-page QR code (not asked for).

## Tasks

1. Add `APP_STORE_URL: string | null = null` to `appStores.ts`, with the comment that it is set only when iOS ships.
2. Add the platform detection helper (pure function: user agent string → `android | ios | other`). Unit-test it.
3. Build the page with three layouts driven by the platform value.
4. Add the route, the `PUBLIC_PAGES` entry, the speculation rule and the `llms.txt` line.
5. Add the paired CSS Module and check it with `bun run check:styles`.
6. Run the design-system check (`bun run check:design-system`) to confirm no new raw values.

### Review Findings (2026-11-11, commits cbafd6c and 1ea2e7f in fenzit-web)

Four review layers ran (blind hunter, edge-case hunter, verification gap, acceptance audit against this story). Triaged below. Admin landing (1ea2e7f) is out of this story's scope; its findings are listed here because they came from the same review.

**Decision needed**
- [x] [Review][Decision] D1: Android auto-redirect to the Play intent link. `DownloadAppPage.tsx:18` calls `useRedirectTo(PLAY_STORE_APP_LINK)` for Android. The Behaviour table asks for a button only, and Out of scope excludes app links. Options: (1) keep the auto-redirect; (2) drop it and show the Play button only. **Decided: removed the redirect and the hook; the Play button is the only Android action.**
- [x] [Review][Decision] D2: Desktop instruction. The old page told desktop visitors to open the link on a phone. The new desktop view has no such line. Options: (1) add "Open this link on your phone" back; (2) keep as is. **Decided: desktop lead now says to open the link on a phone.**

**Patch**
- [x] [Review][Patch] P1 (medium): `AdminHome` returns `null` while the loader is loading or failed, so the landing is blank with no loading or error text. CLAUDE.md requires both states. [`AdminPage.tsx` AdminHome, `data === undefined || data.status === "failed"`]
- [x] [Review][Patch] P2 (medium): Internal jargon in user copy: "Destructive work stays in the owner's super CLI". Rewrite in plain English. [`AdminPage.tsx:278`]
- [x] [Review][Patch] P3 (low): The download page heading is hardcoded in three places. Read it from `DOWNLOAD_APP_PAGE.title`. [`DownloadAppPage.tsx` lines 25, 50, 53]
- [x] [Review][Patch] P4 (low): `UserChip` shows a blank first line for a whitespace-only name. Trim before the check. [`AdminPage.tsx` UserChip]
- [x] [Review][Patch] P5 (low): `SectionIndex` renders an empty description line when a section has no blurb. Hide the line when empty. [`AdminPage.tsx` SectionIndex]
- [x] [Review][Patch] P6 (low): `LEDE.member` is unreachable (members redirect before the index). Remove it. [`AdminPage.tsx` LEDE]
- [x] [Review][Patch] P7 (low): Duplicate helpers in the download page (`AppStoreBlock` only wraps `AppStoreButton`; the iPhone copy repeats). Merge them. [`DownloadAppPage.tsx`]
- [x] [Review][Patch] P8 (low): The index row hover and arrow transition has no `prefers-reduced-motion` guard. [`AdminPage.module.css` `.indexRow`, `.indexGo`]

**Defer** (pre-existing or waiting on owner confirmation)
- [x] [Review][Defer] Tests for the download page branches, index row hrefs, blurb coverage, chip name, and sidebar landing state. Deferred until the owner confirms the pages (test timing rule). Deferred, pre-existing.
- [x] [Review][Defer] Layout at 360 to 1280 px, `100dvh`, safe-area insets, and gutter bleed on phones. Needs a device check (AC 8). Deferred, pre-existing.
- [x] [Review][Defer] Commit 1ea2e7f bundled a `ForceUpdateFields.module.css` change, and its message names only the glyph change. Not rewritten without consent. Deferred, pre-existing.
- [x] [Review][Defer] Sidebar highlights the first section on the landing with no test. Visual choice to confirm. Deferred, pre-existing.

**Dismissed (4):** the two guards' treatment of `/app/download` agrees today; the Android-only meta description is required by the metadata guard; the Play button shows briefly before detection is the spec's first-paint rule. Separate doc fix, not a code finding: the spec's touchpoints table says `src/app/router.tsx`, but the route is in `src/app/routes.tsx`.

## Constraints

- Follow `fenzit-web/CLAUDE.md` and `docs/repos/fenzit-web/standards.md`: exact pins, no `^`/`~`, no `useEffect` fetching, no TanStack Query, feature-first layout, files under about 300 lines, no barrel `index.ts`.
- No new dependency is expected. If one is needed, add it to the standard's stack table first and wait two weeks for the package to age.
- Bun only. Use `bun run test`, not bare `bun test`.

## Tests (write after the owner confirms the page)

Name the intended tests now:

- Detection: Android Chrome, iPhone Safari, iPad (desktop-mode Safari reports Mac), desktop Chrome, an empty user agent, a mixed-case user agent, and a user agent that contains both "Android" and "iPhone" (define the winner in the test).
- iOS switch: `null` shows the placeholder; a set URL shows the App Store button.
- The Play URL is exactly `https://play.google.com/store/apps/details?id=com.fenzit`.
- No `apps.apple.com` link while the iOS URL is `null`.
- `PUBLIC_PAGES` entry exists; description is 25 to 160 characters.
- The page renders with no network request.

## Done when

- The owner has checked the page on an Android phone, an iPhone and a desktop browser, at 360, 390, 768 and 1280 px.
- The tests above are written and pass.
- `/bmad-code-review` has run and its findings are triaged.
- The owner has agreed to the commit and to the push. Push deploys to fenzit.com, so it needs explicit consent, and it is held until the SMS feature ships.
