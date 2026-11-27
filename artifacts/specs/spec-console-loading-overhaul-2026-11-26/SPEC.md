---
id: SPEC-console-loading-overhaul-2026-11-26
companions:
  - loading-cases.md
  - ../../planning-artifacts/loader-overhaul-2026-11-26/FENZIT-LOADER-BRIEF.md
sources: []
---

> **Canonical contract.** This SPEC and the files in `companions:` are the complete, preservation-validated contract for what to build, test, and validate. The companion `loading-cases.md` carries the binding case matrix, thresholds, surface map, and loudness gaps; `FENZIT-LOADER-BRIEF.md` carries the adopted animated-logo contract.

# SPEC — Console loading overhaul: shimmer skeletons, full-page Pour loader, loud in-flight feedback

## Why

The web console's only load signal is a 3px top progress bar that is too quiet to register: entire page categories (Leave, Holidays, Attendance, Payroll, job detail, company overview) keep stale content frozen behind it, several mutations give no feedback beyond a 13px button spinner, dialogs can be dismissed mid-send, and the longest operation (payroll run) completes silently. The owner mandated a loud loading system on 2026-11-26: shimmer on the components being loaded, a full-page Fenzit-logo loader with a light blur background, and unambiguous feedback whenever an API request is in flight — for a small admin console where every user is an owner/operator.

## Capabilities

- **CAP-1 — Full-page branded boot loader.** When the console boots or auth resolves (`/admin*` HydrateFallback + layout `adminLoader`), the user sees the full-page FenzitLoader (hero variant, per the Pour brief) centered on a light blurred pane instead of plain text.
  intent: make the first impression a branded, obviously-working moment instead of a text line.
  success: a hard load of any `/admin/*` URL shows the animated Pour logo until the layout resolves; reduced-motion shows the static filled mark with pulse; browser-verified.
- **CAP-2 — Navigation skeletons.** While a route loader runs after navigation, the target page shows a layout-matching skeleton in the content region while the persistent shell stays interactive.
  intent: navigating never leaves the user on a frozen or blank page; the shell never unmounts or grays out.
  success: navigating to every console page shows a content-region skeleton for loads that persist past the 300ms delay; shell and nav remain interactive throughout.
- **CAP-3 — Region skeletons and stale-while-revalidate.** In-page reloads (tabs, month changes, filter refetches) show skeletons scoped to the affected region; refreshes of already-visible data keep the old data with a subtle updating cue.
  intent: the currently-displayed content never pretends to vanish when only part of the page reloads.
  success: Leave/Holidays/Attendance/Payroll tab and month changes show region shimmer; employees/customers/jobs paging keeps stale rows + "— Updating…"; verified in browser.
- **CAP-4 — Skeleton primitives.** The console has shared skeleton primitives (block/row/card/list archetypes, derived from the existing `TableSkeleton` recipe and `--color-shimmer-sheen` token) that match the real content's dimensions.
  intent: every covered page composes its skeleton from one system so shimmer feels native, not bolted on.
  success: all CAP-2/CAP-3 surfaces use the primitives; no layout shift when data arrives (CLS ≤ 0.1 locally verified); reduced-motion renders static sunken blocks.
- **CAP-5 — Loud mutations.** Every mutation shows an unambiguous in-flight state (pending button + `aria-busy`, dialogs locked while their fetcher is submitting) and completion/failure feedback that survives the operation via a hand-rolled toast layer (no new dependencies).
  intent: no API request completes or fails without the user knowing.
  success: invite and add-customer dialogs cannot be dismissed mid-send; completing a card-scoped mutation produces a toast or persistent status; errors announce via `role="alert"` and never auto-dismiss.
- **CAP-6 — Long-op escalation.** Operations longer than ~3s (payroll run, PDF report, CSV exports, bulk import) show progress that is determinate where countable, survive navigation, and signal completion without manual Refresh.
  intent: the longest, highest-stakes ops are never the quietest.
  success: page-walking CSV exports report "N downloaded"; the PDF download step shows a busy state; payroll-run completion is covered by CAP-9.
- **CAP-7 — Motion and accessibility contract.** All loading motion obeys the binding thresholds and a11y rules in `loading-cases.md` (300ms delay / 500ms min-display / ~3s ceiling / CLS ≤ 0.1; reduced-motion fallbacks; one `role="status"` per cluster; decorative layers `aria-hidden`).
  intent: loud does not mean noisy or exclusionary.
  success: every new loader/skeleton honors the thresholds and reduced-motion fallbacks; a reduced-motion pass over all covered surfaces shows meaningful static states.
- **CAP-8 — Single identity fetch per navigation burst.** The layout's auth check and every child loader's `requireConsoleRole` read one cached `/users/me` result (30s TTL, `leaveSummaryCache` pattern) instead of refetching per loader.
  intent: console navigation stops paying for duplicate identity fetches, which doubles the wait every loading state is covering.
  success: a console navigation burst issues one `GET /users/me` on the network where two or more fired before; login, logout, and any 401 invalidate the cache so role changes cannot go stale beyond the TTL; existing auth/role specs stay green.
- **CAP-9 — Payroll-run completion signal.** An in-flight payroll run is observed by a module-level poller on the existing run-status endpoint (no BE change) that survives navigation, toasts state transitions, and revalidates the payroll route when mounted.
  intent: the longest, highest-stakes operation announces its completion or failure without manual Refresh.
  success: starting a run and navigating away, the user still gets a completion/failure toast; returning to the payroll page shows the settled pill without pressing Refresh; a tab reload mid-run still surfaces the outcome on the next payroll visit; polls are modest-cadence with backoff aligned to the existing 15-minute "may have stopped" hint.

## Constraints

- CSS Modules strictly (paired `.module.css`, no string classes, no element selectors); no new dependencies; no JS animation libraries — the Pour loader is pure CSS keyframes.
- `src/theme/` and `src/styles/tokens.css` are generated from fenzit-app — never hand-edited; the implementation must need no new tokens (overlays follow the existing z-index-50 convention).
- `prefers-reduced-motion` is non-negotiable: every infinite animation ships a meaningful static fallback (existing Spinner precedent: opacity pulse instead of spin).
- Blur backdrop: mostly-opaque pane; blur is decoration, never the legibility mechanism (WCAG 1.4.3); blur never applies to the mark itself.
- The design-system "flat backgrounds / no decorative loops" exception applies to loading contexts only; the web mark gets no glow/bloom/halo (that is the mobile splash's move).
- Skeletons must occupy the final content's dimensions and never flash under the 300ms delay.
- The animated logo is the adopted Pour brief (`FENZIT-LOADER-BRIEF.md`): ghost white mark → gradient pour bottom-up inside a clipPath, bobbing meniscus, ≤5/≤3 deterministic bubbles, 3400ms seamless cycle, no cliché-banned moves.
- Identity cache never outlives the session: cleared on login/logout and any 401; role/tenant changes may lag at most the 30s TTL.
- Payroll-run observation stays on the existing run-status endpoint — no new BE endpoints, no realtime transport in this effort.

## Non-goals

- Mobile (fenzit-app) loading redesign — the app keeps its boot splash; the web loader is a sibling, not a port.
- Optimistic UI and undo-window machinery for irreversible ops (payroll postings, deletions).
- Rewriting the existing button pending pattern (disabled + Spinner + label swap) — it conforms; this effort adds `aria-busy`, dialog locks, and toasts around it.
- Route-level code-splitting or a global `errorElement` overhaul (the uncaught-error risk is noted but out of scope).
- Realtime transport (SSE/WebSocket/webpush) for run-status updates — the CAP-9 poller sits behind a seam so realtime can replace it later if the console ever justifies the infra.
- New tokens in the fenzit-app theme (unless a z-index/blur token proves necessary, which would go through the sync flow).

## Success signal

The owner opens the localhost preview: a hard load of `/admin` shows the Pour loader over a lightly blurred shell; navigating between Leave, Holidays, Payroll, and Jobs shows content-region shimmer instead of frozen pages; submitting an invite locks the dialog mid-send and lands a completion toast; starting a payroll run and navigating away still lands a completion toast. On the network, a console navigation burst issues a single `/users/me`. `bun test`, `check:styles`, and typecheck stay green; BMAD code review passes before any commit (owner rule).

## Assumptions

- Boot/auth (and shell re-initialization) are the only full-page loader moments; all in-app navigation uses content-region skeletons. The owner's "full page loader" reads as those moments, not every navigation — overridable at review.
- The 3px line loader is kept as a demoted secondary cue rather than deleted — overridable at review.
- The toast layer is hand-rolled and minimal: polite status announcements, assertive errors, small stack cap.
