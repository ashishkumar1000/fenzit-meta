# fenzit-web — Standards and Process

Status: **draft v1, 2026-10-19.** Written from the current code in `fenzit-app` and `fenzit-be`, the live fenzit.com page, and the official docs listed at the end. Anything marked **Decide** needs your answer before it becomes a rule.

Short agent rules live in `workspace/core/frontend/fenzit-web/CLAUDE.md` and point here. Keep this file as the full reference.

---

## 1. Purpose and scope

`fenzit-web` is the browser app served at https://fenzit.com on Cloudflare Workers. It calls `fenzit-be` over HTTPS. It does not own data, auth rules, or business logic. Those stay in `fenzit-be`.

The mobile app (`fenzit-app`) is React Native and has its own design system. The web app must match its brand and vocabulary, not its code.

---

## 2. Stack and pinned versions

Versions are exact pins (no `^`). A new dependency must be at least two weeks old on the registry when first added. Check with `bun pm view <pkg> version` and the package's release page before pinning.

| Concern | Choice | Pinned in repo today | Notes |
|---|---|---|---|
| Runtime / package manager | Bun | `bun@1.3.14` (`packageManager`, CI) | Bun only. `preinstall` blocks npm, yarn, pnpm. |
| UI library | React | 19.3.0 | Matches `fenzit-app` line (19.x). |
| Routing | React Router, **library mode** | 8.4.0 | `createBrowserRouter` in `src/app/router.tsx`. Not framework mode (see §3). |
| Build | Vite | 8.3.2 | Plain Vite build. |
| React Vite plugin | `@vitejs/plugin-react` | 6.1.1 | |
| Language | TypeScript | `tsc` 7.0.2 (latest stable) | Build and typecheck use TS 7. Lint tools use TS 6.0.3. See §2a. The app and BE stay on 5.x (§12). |
| Hosting / deploy | Cloudflare Workers with static assets | wrangler 4.147.0 | `wrangler.jsonc`, SPA fallback. |
| Server data | React Router loaders and actions | built into react-router 8.4.0 | No TanStack Query (the user does not want it). Data loads in route loaders (§6). Local UI state uses `useState` or `useReducer`. |
| Styles | CSS Modules | built into Vite | Strict. Every component has a paired `.module.css` (§5). |
| Country flags | `country-flag-icons` | 1.6.20 (published 2026-07-01, MIT) | React SVG components from `country-flag-icons/react/3x2`, no global CSS. Adds about 60 KB gzip because all 272 flags are imported. Shown beside the country-code select on the early-access form. |
| Git hooks | husky | 9.1.7 (published 2024-11-18, MIT) | `.husky/pre-commit` runs lint, format, style, design-system, typecheck and tests, the same checks as CI. Installed by the `prepare` script. |
| Forms (next) | React Hook Form + zod | not yet added (RHF 7.90.0, zod 4.6.7) | **Decide** before the first form. |
| Lint | ESLint 10 flat config + typescript-eslint 8.71.0 + react-hooks 7.1.1 + react-refresh 0.5.7 | eslint 10.12.0, @eslint/js 10.0.1, globals 17.13.0 | Type-free rules only (§2a). Import direction enforced by `no-restricted-imports` (§4). |
| Format | Prettier | 3.9.9 | `.prettierrc.json`: double quotes, trailing commas, printWidth 100. Verbatim ports are ignored (§4). |
| Tests | `bun test` (Bun's built-in runner) + happy-dom + React Testing Library | happy-dom 20.14.5, @happy-dom/global-registrator 20.14.5, @testing-library/react 16.3.3, @testing-library/dom 10.4.2, @testing-library/jest-dom 7.0.1, @types/bun 1.4.2 | Config in `bunfig.toml` (two preload files in `src/testing/`). `bun run test` runs `bun test`. With no test files it fails, so an empty suite cannot pass the CI gate. |

### 2a. TypeScript 7 and the lint tools

typescript-eslint 8.71.x declares `typescript <6.1.0`, and it refuses to load when it sees TypeScript 7 (it checks for major version 7). Microsoft's guidance for this is to run the lint tools on the TypeScript 6 API side by side. We do that with two packages:

- `typescript` = `6.0.3`. The lint tools load this name, so typescript-eslint works.
- `@typescript/native` = `npm:typescript@7.0.2`. This gives the `tsc` binary used by `typecheck` and `build`.

Checked 2026-10-19:
- `@typescript/typescript6` does not work as a compatibility shim. Its entry file requires `@typescript/old`, which requires itself, so it exports nothing. Use the regular `typescript@6.0.3`.
- No typescript-eslint release in the registry supports TypeScript 7 yet. The tracking issue is typescript-eslint#10940 (support for TS 7.1 and later).

Because lint runs without type information, the ESLint config uses the untyped `recommended` sets only. When typescript-eslint supports TS 7, switch the `typescript` alias back to TS 7, add the typed rules, and remove the `@typescript/native` alias.

**Rule:** do not add a library that is not in this table without writing it into this table first, with a one-line reason.

**Libraries we avoid** (and why):
- **TanStack Query, Redux, MobX, or any global store** for server data. Server data loads in React Router loaders (§6). Use plain React state for UI state only.
- **Axios.** `fenzit-app` uses it, but the web app has one thin `fetch` wrapper and does not need an interceptor stack. Keep `fetch`.
- **Moment.js.** Use native `Intl` and `Date`. The BE uses IST for "today", so format dates in `Asia/Kolkata` explicitly.
- **Next.js, Remix, or React Router framework mode.** Not needed. See §3.
- **Cloudflare Vite plugin for the SPA.** Cloudflare's docs say SPA mode and prerendering are not supported with it (see §3).
- **Any CSS-in-JS runtime, and global stylesheets for components.** Styles are CSS Modules with tokens (§5).
- **Any `jsonwebtoken`, `jose`, or Supabase service key in the browser.** The BE rules say JWT handling stays in `fenzit-be`. The web app holds only the user's own token, and only for its own session.

---

## 3. Why this architecture

- **Prerendered pages, not a runtime server.** The site is mostly signed-in app screens behind a login, so only the public marketing pages (`/`, `/features`) need to be crawlable. `bun run build` prerenders both to static HTML and rewrites each page's head for its own URL (title, description, canonical, Open Graph, Twitter — `scripts/prerender.ts` + `src/app/pageMeta.ts`). `/login`, `/admin` and the 404 shell ship `noindex`; the build also writes `dist/sitemap.xml`. Workers static assets serve the files, `html_handling: "drop-trailing-slash"` keeps the no-slash form canonical, and `not_found_handling: "404-page"` returns a real 404 for unknown paths.
- **React Router library mode.** Cloudflare's React Router guide says: for an SPA, "start with the React template and use React Router as a library." Framework mode adds a server runtime we do not need.
- **Plain Vite, no Cloudflare Vite plugin.** Cloudflare says SPA mode is not supported with its Vite plugin. We use `vite build` into `dist/`, and `wrangler.jsonc` points at it.
- **Direct API calls to `fenzit-be`.** The browser calls `VITE_API_BASE_URL` directly. This needs CORS on the BE (§12). The alternative is a same-origin proxy through the fenzit.com Worker. **Decide** (§12).

---

## 4. Folder layout

Feature-first, with a shared layer. Industry guides agree on this shape for a React SPA: one folder per feature holding its own components, hooks, and API calls, plus shared code that every feature may use. Sources are in §13. We add a folder when it gets its first real file, not before.

```
src/
  main.tsx              entry: StrictMode, RouterProvider, global stylesheet
  app/
    router.tsx          route table, plus each route's loader and action (§6). No UI.
  pages/                route screens, <Name>Page.tsx + <Name>Page.module.css. They compose features.
  features/
    landing/
      components/       landing-page sections: Header, Hero, Footer, NotifyForm, ... each with its .module.css
    <feature>/          one folder per feature: components/ (each with a .module.css), hooks/, api.ts, types.ts
  components/
    ui/                 shared design-system primitives (PulseDot, Button, Input). Each with its .module.css.
  hooks/                shared hooks (useThing.ts). A hook moves here when a second feature needs it.
  services/
    api.ts              shared HTTP client: apiFetch, ApiError (status, errorCode). Feature API calls live in the feature folder.
  config/
    env.ts              typed reads and checks of VITE_ values
  utils/                pure helpers (dates, formatting, validation). No React, no fetch.
  types/                shared types, one file per domain
  testing/
    happydom.ts         preload 1: DOM for bun test
    testing-library.ts  preload 2: jest-dom matchers and cleanup
    bun-test.d.ts       types for the jest-dom matchers used in tests
  styles/
    global.css          the only global stylesheet: design tokens (:root), reset, page background
public/                 static files served as-is (robots.txt)
scripts/
  check-css-modules.ts  CSS Modules check (bun run check:styles)
  check-design-system.ts  design-system hash and tokens check (bun run check:design-system)
  sync-design-system.ts   copies the design system from fenzit-app (bun run sync:design-system)
  build-tokens.ts         writes src/styles/tokens.css (bun run tokens)
  design-system-files.ts  the list of copied design-system files
  lib/                    the logic behind each script, with tests beside it
```

**Dependency rules** (the first is enforced by ESLint; the rest by review):
- Shared code (`components/`, `hooks/`, `services/`, `config/`, `utils/`, `types/`) never imports from `features/`, `pages/`, or `app/`. The lint rule was tested with a deliberate violation on 2026-10-19 and it fails.
- A feature never imports another feature. Code moves out of a feature into shared only when a second feature needs it.
- `pages/` imports features and shared code. `app/` imports pages and providers. Only `main.tsx` imports `app/`.
- No barrel `index.ts` re-exports. Import the file directly, so stack traces and "find usages" stay accurate.
- Nesting stays at three levels under `src/` (for example `features/landing/components/`). Go deeper only with a reason.
- Tests sit next to the file they cover (`Name.test.tsx`). Shared test helpers live in `testing/`.

**Formatting exceptions:** `index.html` and `wrangler.jsonc` are verbatim copies of the live page and the deploy config. Prettier ignores them (`.prettierignore`), so their diffs against the live site stay readable. The landing stylesheet was split into CSS Modules, so it is no longer a verbatim copy and Prettier formats it.

Naming:
- Components and component files: `PascalCase.tsx`, one component per file, named export.
- Hooks: `useThing.ts`.
- Pure functions: `camelCase.ts`. The scripts in `scripts/` use kebab-case (`check-css-modules.ts`), as their own names show. The scripts' logic lives in `scripts/lib/`, which follows the camelCase rule.
- Types: `PascalCase` type names, no `I` prefix. Use `type` for unions and object shapes.
- Constants: `UPPER_SNAKE_CASE` only for real fixed values (for example `API_TIMEOUT_MS`).
- Imports: relative paths, like the rest of the repo today. Path aliases are not used yet. If we adopt them, add them to `tsconfig` and Vitest together and change every file in one commit.

File size: keep each file under about 300 lines (same rule as `fenzit-app`). Split by component when a file grows past that.

---

## 5. UI and design system

- **Brand source:** `fenzit-app/src/theme/DESIGN_SYSTEM.md` is the rule book for the Fenzit look. The web app follows it. Colors, spacing, radius, and type come from tokens, not from hard-coded values in components.
- **Design system: one source, copied to both apps** (set by the user, 2026-10-19). The web app copies the app's design system from `fenzit-app/src/theme/` (colours, spacing, radius, shadow, type, motion, and `DESIGN_SYSTEM.md`) into `src/theme/`. The copies are byte-identical.
  - Sync from the app: `bun run sync:design-system` (run on your machine, where both repos sit side by side). It copies the files and writes `src/theme/design-system.lock.json` with a SHA-256 of each file. Then run `bun run tokens`, and commit.
  - `bun run tokens` generates `src/styles/tokens.css` (CSS custom properties, such as `--color-primary`, `--space-4`, `--radius-md`, `--shadow-md`, `--font-size-base`). Never edit `tokens.css` by hand.
  - `bun run check:design-system` runs in CI. It fails when a copied file no longer matches its hash, or when `tokens.css` is stale. CI cannot see the app repo, so the hashes are the drift check.
  - The copied files are excluded from Prettier and from the type check (`colors.test.ts` uses Bun's globals). Do not edit them here. Change the design system in `fenzit-app`, then sync.
  - Components use token names, never raw hex. `global.css` keeps a short alias block for the sample landing page's old names. Remove that block with the sample page.
  - The app's design rules (flat backgrounds, no decorative loops, pill radius for badges, the fixed status vocabulary) apply here as well. The sample landing page does not follow them yet, and the user has said it will be replaced.
- **CSS Modules, strictly** (set by the user, 2026-10-19):
  - Every component file has a paired `<Name>.module.css` in the same folder. The component imports it as `import styles from "./Name.module.css";` and applies classes as `className={styles.name}`.
  - `scripts/check-css-modules.ts` (`bun run check:styles`) fails when a component has no paired file or does not import it this way. The import line must match exactly, but leading indentation and trailing spaces are allowed. Block comments are ignored, so an import inside a comment does not count. CI runs it.
  - ESLint rejects a string `className="…"`. Combine classes with a template string: `` className={`${styles.a} ${styles.b}`} ``.
  - `global.css` holds only tokens, the reset, and the page background. It must not style a component. No element selectors (`h1`, `button`, `header`) in component modules. Give the element a class instead, so the style stays scoped.
  - Inline `style={{…}}` props are not used for layout, colour, or type. Put them in the module.
  - Reduced motion: each module sets its own entrance content to visible, because the global safety net stops the animation and would otherwise leave content invisible.
- **Components:** build primitives in `components/ui/`. A screen composes primitives. A new screen must not invent a new button or badge.
- **Icons: the same library as the mobile app** (set by the user, 2026-10-19). Use `lucide-react` on the web, which is Lucide's official web package. `fenzit-app` uses `lucide-react-native` from the same project. Pin `lucide-react` to the same version as the app (1.48.0 now), and change both together. Import each icon by name, for example `import { CircleCheck } from "lucide-react";`, and pass the CSS Module class as `className`. Do not draw an icon by hand in SVG. Raw SVG is fine for graphics that are not icons (a logo mark, an illustration, a chart), wherever the design needs it.
- **Status vocabulary:** job and task state uses the same fixed words as the app: Done, In Progress, Scheduled, Cancelled (plus neutral). No synonyms.
- **Copy:** sentence case. Plain English. Write from the user's point of view, not the system's. A disabled control says why it is disabled. Errors say what went wrong and what to do next. Button text names the action ("Save changes", not "Submit"). No emoji in product UI. Follow the same copy rules as the app's plain-English feedback.
- **Visual direction for new screens (from the frontend-design guidance):** pick a point of view that fits Fenzit's subject (field-service operations, Indian SMB owners and technicians) and do not default to the generic look. Avoid the common tells: a cream background with serif display type, a near-black background with one neon accent, cards in identical rounded boxes with the same grey shadow, gradient washes, ALL-CAPS eyebrow labels, a middle-dot meta line (`A · B · C`), and a `→` on every link. One element can be bold. Everything around it stays quiet.
- **Sample landing page (decided 2026-10-19):** it is a placeholder. These standards apply to the new web app, not to it. It will be deleted, so it is not restyled to meet them.
- **Responsive, on every screen** (set by the user, 2026-10-19). Everything we build works in a desktop browser and in mobile web (Chrome on Android, Safari on iOS). A screen that only works at one width is not done.
  - Design mobile first. Start from a phone, then add layout for wider screens with `min-width` media queries.
  - Breakpoints come from the design system's layout tokens: `--layout-gutter-mobile` (16 px) below 768 px, `--layout-gutter-desktop` (24 px) from 768 px, and `--layout-content-max` (480 px) for phone-width content. Use `--layout-content-max` for the main column on phones. Wider screens may use a wider column, with a stated reason. Use `--space-*` for spacing.
  - Test widths: 360 px (small Android), 390 px (iPhone), 768 px (tablet), and 1280 px (desktop). Each screen has no horizontal page scroll at any of them.
  - Mobile web: include `<meta name="viewport" content="width=device-width, initial-scale=1">` (already in `index.html`). Inputs use at least 16 px text, so iOS Safari does not zoom in on focus. Use `100dvh` (or `min-height`) for full-height layouts, not `100vh`, because mobile browser toolbars change the visible height.
  - Touch and hover: every action works by tap. Never put a control behind a hover-only state. Touch targets are at least 44 px (48 px for inputs).
  - Safe areas: keep fixed headers and bottom bars clear of the notch and the home indicator with `env(safe-area-inset-*)`.
  - Check each screen at all four widths, in both a desktop browser and a phone-sized browser, before it is marked done. Note the check in the story.
- **Touch and focus:** touch targets at least 44 px (the app uses 44 px touch targets and 48 px inputs). Visible focus ring on every interactive element. Never remove `outline` without a replacement.
- **Motion:** one deliberate page-load or reveal at most. Respect `prefers-reduced-motion`. Motion that answers a user action (open, expand, confirm) is fine.
- **Accessibility target:** WCAG 2.2 AA. Every input has a label. Icon-only buttons have an `aria-label`. Use semantic elements (`header`, `main`, `nav`, `button`) before adding ARIA. Color is never the only signal. Contrast is at least 4.5:1 for body text.
- **Type safety** (set by the user, 2026-10-19): components, props, hooks, and API calls are explicitly typed. No `any`. `typescript-eslint` recommended rules reject `any` as an error. Prefer `unknown` and narrow it.
- **Specificity:** keep it low. Class selectors only. Do not use `!important` in component modules. The one exception is the global reduced-motion guard in `global.css`.

---

## 6. Data, API, and errors

**Contract source:** the BE's real contract. Read these before writing a client:
- Prefix: every route is under `/api/v1/…`.
- Error body: `{ error_code, message, …extra }`. Branch on `error_code`, never on the `message` text. The BE sets `retryAfterSeconds` on some 429s, and that goes into a `Retry-After` header.
- Error codes: the list in `fenzit-be/src/common/enums/error-code.enum.ts`. Web code maps each code it handles to plain-English copy in one place (`src/lib/errorMessages.ts`, to be created). An unknown code falls back to a generic message.
- Request headers the BE reads: `X-Correlation-Id` and `X-Session-Id` (story 13.2 on the app side), and `X-Idempotency-Key` on every mutating call that the BE dedupes. Send the correlation and session IDs on every request. Generate an idempotency key once per user action and reuse it on retry.

**Client rules:**
- One `apiFetch` (in `src/services/api.ts`) builds the URL from `VITE_API_BASE_URL`, adds headers, enforces a 15 s timeout with `AbortController`, parses the error body, and throws `ApiError`. Done: timeout, network failure (status 0), `errorCode` from the body, and a clear error for a non-JSON response. Each call sends an `X-Correlation-Id` (new per call) and an `X-Session-Id` (one per page load). Both are set unless the caller sets its own. Done too: a caller's own `Headers` or tuple headers are kept, and the caller's cancel signal is honoured. Not yet: `X-Idempotency-Key`. Set it per user action on writes, with the first write screen.
- Typed API calls: every call has an explicit return type. `apiFetch<T>` takes `T` from the caller, and the caller owns that type.
- **Empty responses (decided 2026-10-19):** a `204 No Content` answer returns `undefined`, so the caller types the call as `apiFetch<void>`. An empty `200` breaks the JSON contract, so it throws an `ApiError`.
- **Server data, without TanStack Query** (set by the user, 2026-10-19):
  - Load data in a route `loader` in `src/app/router.tsx`, and read it in the page with `useLoaderData<typeof loader>()`. React Router runs the loader before the page renders, so no effect is needed.
  - Send changes with a route `action`, and submit them with `useFetcher` or `<Form>`. A pending state comes from `fetcher.state`.
  - Loaders and actions live in the feature folder (`features/<name>/loaders.ts`), and the route wires them up.
  - **Never fetch in `useEffect`.** ESLint rejects `useEffect` in `features/` and `pages/`. A justified exception needs an `eslint-disable` line with the reason next to it.
  - Local UI state (open or closed, form inputs, selected tab) stays in `useState` or `useReducer`. It is never copied from server data into state.
- Mutations: show a pending state while the action runs, and disable the submit button during it.
- **Error copy:** `src/utils/errorMessages.ts` maps each `error_code` to plain English. Screens show `messageForError(error)`, never `error.message`. That text is written for developers. A status 0 (no response) shows the connection message. Unknown codes get the generic message, and 5xx get the server message.
- **Offline (done):** `useOnlineStatus` (a hook on `useSyncExternalStore`, not an effect) drives `OfflineBanner`. `RootLayout` shows the banner above every route.
- Retries: none by default. A failed load shows its error with a retry button, which calls the loader again through `revalidate`. Retry is a user action, not an automatic loop.
- Every screen that loads data has three explicit states: loading (a skeleton, not a spinner over blank space), error (plain message and retry), and empty (what to do next). The screen never freezes or goes blank on a network error.
- Offline: the banner (above) shows while the browser is offline. Do not queue writes in the browser.

**Auth and storage (Decide):**
- The web app never holds a Supabase service key. Only the BE's signed user token reaches the browser.
- Options for the token: (a) keep it in memory and refresh on reload, (b) store it in `localStorage`, (c) an httpOnly cookie set by a Worker route. Option (c) is safest, and it requires a same-origin setup (§12). Pick one before the first signed-in screen.

**Environment variables:**
- `VITE_*` values are public. They end up in the JavaScript bundle. Put only public values there (for example `VITE_API_BASE_URL`). Never a secret, token, or key.
- Read them only in `src/config/env.ts`. `getApiBaseUrl()` throws a clear error when `VITE_API_BASE_URL` is missing or is not an http(s) URL. It throws at the first API call, not at page load, so a missing value does not blank the landing page. The deploy workflow sets `VITE_API_BASE_URL` to `https://api.fenzit.com` for the build.

---

## 7. Testing

Order of work is fixed by the project rules: **implement → user confirms it works → write tests → BMAD review → commit.** Never write tests before the feature is confirmed.

When writing tests, think as a QA engineer. Cover:
- Boundaries: empty, zero, one, many. Min and max lengths. Email with no `@`, a space, or a trailing dot.
- Malformed and hostile input (script tags, very long strings, unicode).
- Failure paths: 401, 403, 404, 422, 429, 500, network error, timeout, and offline. Each one shows the right UI.
- Ordering and races: double submit, slow response arriving after a newer one.
- Permissions: a technician sees no owner-only controls. Tenant data never leaks across accounts.
- Never weaken an assertion to match the code. If a test and the code disagree, fix the code. Change the test only when the test is wrong about the requirement, and say so.

Tools (§2): `bun test` for unit and component tests, with React Testing Library for component behaviour. Playwright for a small set of end-to-end journeys (sign-in, landing sign-up) later.

Known limits, checked 2026-10-19:
- jest-dom's own types do not merge into `bun:test` (jest-dom issues #674 and #744). The matchers a test uses are declared by hand in `src/testing/bun-test.d.ts`. The runtime has the full set.
- Bun's runner is faster and needs no extra config package. Bun's module mocking and coverage are weaker than Vitest's. If a test needs `vi.mock`-style mocking at scale, revisit the runner choice then.

Commands:
- `bun run test` runs `bun test`, Bun's own runner. Bun is the test runner for this repo, so do not add Vitest or Jest.
- `bun run typecheck` must pass before a commit.
- `bun run check:styles` must pass. It checks the CSS Modules pairing.

---

## 8. Quality gates

Before any commit:
1. `bun run build` passes (typecheck + Vite build).
2. `bun run lint` passes. It includes the import-direction, no-string-className, and no-`useEffect` rules.
3. `bun run test` passes. `bun run check:styles` and `bun run format:check` pass too.
4. Check the page at 360 px and 1280 px wide. Check keyboard focus and reduced motion.
5. `/bmad-code-review` has run on the change (not `/code-review`). Findings are triaged, not just listed.
6. The user has said the feature works and has consented to the commit.

Performance budget (initial, **Decide** the numbers): landing page JS under 150 KB gzipped. Routes after the landing page load with `lazy` in React Router. Images have explicit `width` and `height`.

---

## 9. Process (how work moves)

1. **Plan in BMAD**, from the `fenzit-meta` repo, not from `fenzit-web`. Stories go in `artifacts/implementation-artifacts/`. `sprint-status.yaml` is the single source of truth.
2. **Before writing code:** state the layer that owns the change (web, BE, or DB) and why, in one line. If a change needs the BE first, it ships first (§10).
3. **Implement** on `main`. No branches.
4. **User confirms** the feature works (on the deployed preview or local `bun run dev`).
5. **Write tests** (§7).
6. **BMAD code review** (`/bmad-code-review`). Triage findings.
7. **Ask for commit consent.** Commit in `fenzit-web`, never in `fenzit-meta` for web code. Docs for the web app commit in `fenzit-meta` under `docs/repos/fenzit-web/`.
8. **Push = production deploy.** Every push to `main` deploys to fenzit.com through `.github/workflows/deploy.yml`. Treat a push as an outward action: confirm first, same as a commit.
9. Check the deploy badge in the README. A red badge means production did not update. Fix it before the next push.
10. **Compact** the context between stories (`/compact`).

---

## 10. Cross-repo order

- Additive BE change (a new header allowed, a new endpoint, CORS for a new origin): **merge and deploy `fenzit-be` first**, then `fenzit-web`.
- Breaking BE change (renamed or removed field, changed response shape): three steps. (1) BE adds the new shape alongside the old. (2) Web switches to the new shape. (3) BE removes the old shape in a separate change.
- Say which repo ships first in every hand-off.

---

## 11. Security

- No secrets in the repo, the bundle, or logs. `.env`, `.env.local`, `.dev.vars` are gitignored.
- Never log tokens, OTPs, phone numbers, or full error bodies from the BE. Log the `error_code` and the correlation ID.
- Escape user-provided text. Do not use `dangerouslySetInnerHTML`. If it becomes unavoidable, sanitise first and get review.
- External links that open a new tab use `rel="noopener noreferrer"`.
- Add a Content-Security-Policy header through the Worker when the first signed-in screen ships. **Decide** the policy. Google Fonts and the inline JSON-LD in `index.html` must be allowed explicitly.
- Dependencies: pin exact versions, commit `bun.lock`, and use `bun install --frozen-lockfile` in CI (already set).

---

## 12. Open gaps and decisions

Status as of 2026-10-19. Items 1, 2 (accepted), 3, 4, and 5 are done.

1. **Done: CORS on `fenzit-be`.** `fenzit-be` commit `94c7a69`, live on api.fenzit.com. Allowed origins come from `CORS_ALLOWED_ORIGINS`, which defaults to `https://fenzit.com`. Local web dev needs `http://localhost:5173` added in the BE's `.env`. The same-origin proxy through the fenzit.com Worker stays as an option. Revisit it only if cookies are chosen for item 6.
2. **Accepted: TypeScript split.** Web uses `tsc` 7.0.2 (latest stable, as requested). App and BE stay on 5.x. Shared types are not shared across repos yet, so this matters only once a types package exists. Lint tools run on TypeScript 6.0.3 (§2a).
3. **Done: lint, format, and CI gate.** ESLint, Prettier, and the import-boundary rule are installed. The deploy workflow runs lint, format check, and tests before deploying.
4. **Done: test setup.** Bun's test runner, happy-dom, and React Testing Library are configured. The first `NotifyForm` tests (12 cases) pass, and a deliberate break of the email rule fails 9 of them. Feature tests follow the process in §7.
5. **Done: folder layout.** `src/lib/api.ts` moved to `src/services/api.ts`. Landing components moved to `src/features/landing/components/`. The router moved to `src/app/`.
6. **Open: auth token storage.** Pick option (a), (b), or (c) from §6 before the first signed-in screen.
7. **Open: performance budget numbers** (§8). Current bundle: 325.8 KB raw, 103.5 KB gzip, after removing TanStack Query.
8. **Done: `og-image.png` shipped** (2026-10-25). A 1200×630 card generated from the brand glyph, with `public/logo.png` as the stable favicon and JSON-LD logo, per-route heads, noindex shells, robots.txt + sitemap (story: `artifacts/implementation-artifacts/web-seo-fundamentals-2026-10-25.md`). Infra side done the same day: `www.fenzit.com` is a proxied CNAME with a 301 zone redirect rule to the apex (path + query preserved). Google verification TXT records already exist on the zone; still user-side: confirm the sitemap is submitted in Search Console, and Bing (import from GSC).
9. **Open: `workers.dev` is disabled** for `fenzit-web` (Wrangler warning). Decide whether to re-enable it for staging.
10. **Done: `src/services/api.ts`.** The 15 s timeout, network-failure mapping, `errorCode`, correlation and session IDs, and the empty-response rule are in place, with tests. `X-Idempotency-Key` is still open, for the first write screen (§6).
11. **Done: TanStack Query removed**, at the user's request on 2026-10-19. Server data loads through React Router loaders (§6).
12. **Done: CSS Modules, strictly.** Each component has a paired `.module.css`, and the check runs in CI. The only global stylesheet is `src/styles/global.css` (§5).
13. **Done: tests for the CI scripts, the router, the sync, and the token generator.** The check, sync, and generator logic lives in `scripts/lib/` with tests. The generator rejects a theme it cannot turn into valid CSS, such as duplicate names, NaN, or a bad spacing key. Font sizes are emitted in rem, so a user's text-size setting still applies. The sync stores a label in the lock, never the machine path, and copies nothing when a source is missing or is a folder. The router test runs the real route table, including the offline banner on every route.
14. **Open: design-system contrast failure.** `textMuted` on `surfaceSunken` measures 4.39:1, below the 4.5:1 body-text minimum (§5). The test in `src/testing/contrast.test.ts` fails on purpose. Fix the token in `fenzit-app`, then re-sync. The web repo does not edit copied tokens. Until then the deploy workflow's test step blocks every push to `main`.

---

## 13. Sources

- Cloudflare: React Router on Workers (SPA mode is not supported with the Vite plugin; use React Router as a library). https://developers.cloudflare.com/workers/framework-guides/web-apps/react-router/
- Cloudflare: Static Assets, `not_found_handling: "single-page-application"`. https://developers.cloudflare.com/workers/static-assets
- Repo sources: `fenzit-app/CLAUDE.md`, `fenzit-app/src/theme/DESIGN_SYSTEM.md`, `fenzit-be/project-context.md`, `fenzit-be/src/common/filters/global-exception.filter.ts`, `fenzit-be/src/common/enums/error-code.enum.ts`, `fenzit-be/src/main.ts`.
- Folder structure (feature-first with a shared layer, one-way imports, promote on reuse):
  - Robin Wieruch, React Folder Structure Best Practices [2026]: https://www.robinwieruch.de/react-folder-structure/
  - Bulletproof React, feature-based architecture reference: https://github.com/alan2207/bulletproof-react
  - React docs, file structure FAQ (legacy site, still the official guidance on structure): https://legacy.reactjs.org/docs/faq-structure.html
  - Feature-based React 19 template (example layout): https://github.com/naserrasoulii/feature-based-react
- TypeScript 7 and lint tooling: Microsoft, "Announcing TypeScript 7.0", section "Running side-by-side with TypeScript 6.0": https://devblogs.microsoft.com/typescript/announcing-typescript-7-0/ . typescript-eslint support tracking issue: https://github.com/typescript-eslint/typescript-eslint/issues/10940
- Bun test with DOM and React Testing Library: Bun docs, "Write browser DOM tests with Bun and happy-dom": https://bun.com/guides/test/happy-dom and "Using Testing Library with Bun": https://bun.com/guides/test/testing-library . jest-dom type issues on Bun: https://github.com/testing-library/jest-dom/issues/674 and https://github.com/testing-library/jest-dom/issues/744
- Community guidance (checked, not treated as authority): TanStack Query server-state and fetch-wrapper patterns; strict TypeScript and flat ESLint setup for React 19 with Vite.
- Design guidance: Anthropic `frontend-design` plugin, `SKILL.md` (installed in the plugin cache).
