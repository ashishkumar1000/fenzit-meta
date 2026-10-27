# Spec: Web admin — user inspect (dossier) + account flags (staff-only)



Status: active — rewritten 2026-10-26. This replaces the earlier purge-centred version (parked the same day): destructive remove/purge stays **super-CLI-only** (`fenzit-be/scripts/super.tsx`, owner tooling). The web admin gets the two read/flag sections only.
Repos: `fenzit-be` (backend first), `fenzit-web` (website)
Date: 2026-10-26
Depends on: `roles-and-access-spec.md` (roles, memberships, permissions, audit log); visual + data DNA from the super-CLI whois v3 dossier (`artifacts/specs/spec-whois-v3-dossier/`).

## Goal

`/admin` becomes the role-aware Fenzit console. A **fenzit staff member** (the `platform_admin` flag) gets two working sections: **Inspect** — type a phone number, an exact match resolves any user, and the page lays out everything the system knows about that person (the same dossier the super CLI prints: identity, companies and memberships, jobs, attendance with check-in attempts, leave, skills, invites both ways, notifications, audit trail, activity and reports — as counts plus recent rows, with coloured status badges) — and **Account** — promote/demote `platform_admin` and disable/enable the account for the found person, each behind a confirm that states the consequence. A **company owner** (`company_admin`) gets a Company section built from existing company-scoped endpoints: today's team pulse, the roster, leave requests and the company's audit trail. An **employee** (and viewer) gets a Me section with only their own data: profile, today's attendance facts and their leave history.

## Decisions made (product owner, 2026-10-26)

1. **No database changes.** No migrations, no new RPCs, no schema edits, no RLS changes. Everything is API code over existing tables. Writes are plain guarded UPDATEs from app code (the `project-context.md` rule-6 pattern), never new DB functions.
2. **Reuse existing APIs wherever they exist.** Already reused unchanged: `GET /users/me` (session + `platformAdmin` gating), `POST /api/v1/admin/users/:userId/disable` and `…/enable` (existing, `user.disable`). Exactly two new endpoints (below); nothing else is added.
3. **The dossier endpoint is read-only** service-role SELECTs — one response with true totals per dataset plus capped recent lists (the CLI's counts + recent shape). A missing table or column degrades that section to absent, never fails the request (the CLI's `soft()` rule).
4. **No destructive actions on the web.** Remove/purge/company-wipe are super-CLI only. The web's most powerful write is a flag flip, and every flag flip is confirmed in the UI and auto-audited by the existing platform-audit interceptor (staff POST on a `:userId` route → `platform.write` row, tenant NULL).
5. **Staff rails mirror the CLI.** A staff target can be demoted but never disabled from the new UI (disable is hidden for platform admins, demote shown). The new flag endpoint refuses the caller changing their own account (409 `PLATFORM_ADMIN_SELF`) — a staff actor cannot lock themselves out. The existing disable/enable endpoints are not modified in this story.
6. **Flamboyant within the house system.** The CLI's ANSI gradients and gold palette do not transfer: web tokens are generated from `fenzit-app` and raw hex/gradients are forbidden in `fenzit-web`. The CLI DNA ports as *information architecture*: stat tiles, dense capped tables, a fixed status-colour vocabulary (`--color-status-{done,progress,scheduled,cancelled,neutral}-*`), section cards, never colour-alone (badge always carries the word).
7. **Three-persona visibility (product owner, 2026-10-26).** Staff sees anything; an owner sees his company's data; an employee sees only his own data. The owner and employee sections reuse **existing endpoints only** — `GET /attendance/dashboard`, `GET /members`, `GET /attendance/leave`, `GET /audit-log` for the owner (all already granted to `company_admin`); `GET /users/me`, `GET /attendance/me/summary`, `GET /attendance/me/leave`, `GET /jobs` for the employee (own-scope permissions). No backend change is needed for these two personas. The staff dossier and flag endpoints stay `user.manage`-gated.
8. **Bespoke SVG artwork, no icon library** (product owner override of the web repo's lucide rule for this story): every glyph and the empty-state art are original, hand-written SVGs — 24×24 grid, stroke 1.5, round caps/joins, `currentColor` — plus one larger console illustration. No third-party icon imports in the new code.
9. **Motion is quiet and escapable**: entrance stagger on tiles/cards (`animation-delay: calc(var(--i) * 60ms)` fade+rise), a pulsing dot on live statuses, shimmer on loading rows — all inside `@media (prefers-reduced-motion: no-preference)` so reduced-motion users get instant, static rendering.
10. **Console width**: the console reuses the existing wide `Container` (1120px cap) instead of re-applying the public-app 480px content cap — the cap lives in the old page CSS, not the token, so no token or new width is introduced.

## Backend (`fenzit-be`) — ships first

- **New permission `user.manage`** (code-only): added to the `Permission` union, granted only to `Role.PLATFORM_ADMIN`, listed in `PLATFORM_WIDE_PERMISSIONS` (no company membership or `X-Company-Id` needed). `user.disable` and every existing permission stay exactly as they are.
- **`GET /api/v1/admin/users/lookup?phone=…`** (`user.manage`): normalises the input (accepts `+91…`, `91…`, 10-digit; strips spaces/dashes; anything else → 422). Exact match on `(country_code, phone_number)`; no match → 404 `RESOURCE_NOT_FOUND`. Response (camelCase): the person (id, name, phone, email, `platformAdmin`, `disabled`, createdAt, lastSignInAt — auth facts soft-degraded to null), per-dataset **totals**, and **capped recent lists** (8) for: memberships with company summary (name, GSTIN present, UPI present, founder marker), jobs (as technician or in their companies) with workflow step, attendance records with check-in attempts forensics, leave requests, skills, invites sent/received, authored moderations, notifications, audit trail (as actor and as target), activity events, reports. Live query against the DB as it is today; sections whose tables change shape later degrade, not fail.
- **`POST /api/v1/admin/users/:userId/platform-admin`** (`user.manage`): body `{ value: boolean }`. Guarded UPDATE `users SET platform_admin = $value WHERE id = $userId AND platform_admin <> $value` — idempotent success, 404 when the id does not exist, 409 `PLATFORM_ADMIN_SELF` when the target is the caller. Returns `{ userId, platformAdmin }`. No RPC; audit comes from the interceptor.
- Swagger operation summaries, `error_code` envelope, JWT + permission guards apply as everywhere else.

## Web (`fenzit-web`) — ships after the backend deploys

- **`/admin` is a layout route with per-role child sections** (react-router children, each lazy-loaded with its own loader): layout carries the header (greeting, role badge, log out) and the section tabs a role actually has; unknown section for a role redirects home.
  - **staff (`platformAdmin`)** — `Inspect` and `Account`.
  - **owner (`company_admin`)** — `Company`: today's pulse tiles (tracked / checked in / not checked in / short day / late / on leave + unresolved flags), the roster (name, phone, employee code, role, status), leave requests, and the company's audit trail.
  - **employee / viewer** — `Me`: profile card, today's attendance facts (office, timings, weekly offs, today's record), leave history, own jobs.
- **Inspect:** dial-code + number input (existing `DialCodeSelect` + `TextInput`), exact match; the dossier renders as section cards — identity header (name, flag/status badges, phone, email, joined, last sign-in), a stat-tile row of the totals, then one card per dataset with recent rows as token-coloured status tables/chips and an "and N more" line. Distinct loading, error (branch on `error_code`) and empty states, including the explicit "No person with this number".
- **Account:** same lookup; the found person's identity card carries the flag controls — Promote/Demote platform admin (new endpoint), Disable/Enable (existing endpoints). Each control opens an inline confirm naming the consequence. Self-actions are not offered (the loader's `id` powers the guard). After any action the dossier refetches from the loader; a 409 shows its `error_code` message.
- React-router discipline unchanged: section data comes from child-route loaders (`?phone=…` is the inspect/account state), flag writes go through the account route's action with `useFetcher` pending state, no `useEffect` fetching, no new dependencies.
- Pages stay under the ~300-line rule: dossier and section components are feature components under `src/features/admin/`, each with its paired `.module.css`.

## Out of scope

- Any remove/purge/company-wipe from the web (super-CLI only).
- Access-token minting (super-CLI only — a web button would be a standing secret-exfiltration surface).
- Name or partial-digit search; job-customer (`customers`) data; company admin tools; any mobile-app change; any DB migration.

## Intended tests (written after the product owner confirms the feature works)

- BE controller wiring spec: `lookup` + `platform-admin` require `user.manage`, platform-admin-only; service spec: phone normalisation boundaries (+91/91/10-digit/junk), 404, self-demote 409, guarded-UPDATE idempotency; soft-degrade unit.
- BE real-DB integration (member-functions style, review round 2026-10-26): the flag chain executed against a real database — unknown id → 404, differing value → row flipped, same value → zero rows + idempotent 200 from the re-read; and one probe asserting a successful flip leaves the interceptor's `platform.write` audit row with the right `target_user_id` (the audit is HTTP-layer only, unlike `set_user_disabled`'s in-DB audit).
- Web: role gating per child section (employee never reaches inspect/account; staff never sees Company), not-found/error/loading states, action → confirm → refetch flow, 409 surfacing; owner and employee loaders degrade per-section when one endpoint fails.

## Order of work

1. This spec approved by the product owner.
2. `fenzit-be`: permission + two endpoints; `bun run typecheck` green; read-only live probe on the sanctioned fixture (9717331820). Migrations: none.
3. `fenzit-be` deployed first (additive; nothing existing breaks).
4. `fenzit-web`: loader/action, sections, dossier components; `bun run typecheck` + `bun run build` green.
5. Product owner confirms the flow works (search → dossier → flags on a test account).
6. Tests written both repos (tester mindset), then `/bmad-code-review` in each repo.
7. Commit only with consent; `fenzit-be` deploys before `fenzit-web`.

## Round 2 (2026-10-27): sidebar console, owner browse pages, huge-data drill-downs

Decisions (product owner): (a) drop India-specific wording — the phone search is generic (full number with country code; the API keeps +91 as the default for bare 10-digit input); (b) the owner gets browse pages for the big datasets — customers, employees, jobs, holidays, attendance — all served by **existing endpoints** (`GET /customers` cursor-paginated, `GET /members`, `GET /jobs?scope=…` cursor-paginated, `GET /attendance/holidays`, `GET /attendance/monthly`); no new backend routes; (c) the section tabs move into a **left sidebar** on wide screens (top tabs remain on narrow screens); (d) cards gain colour and **original SVG background art, one agent per artwork**; (e) huge-data rule: overviews show summaries, "view all" moves to a drill-down page with cursor pagination ("Load more") — identified huge cases: customers and jobs (owner side, cursor endpoints exist), and, on the staff side for a future round, the dossier sections (audit/notifications/activity/jobs), which stay capped at 5–8 rows because the dossier endpoint has no cursors; (f) Sally pass on the dead space: sidebar + a denser two-column content grid on wide screens.

Intended tests follow the same rule as round 1 (written after the owner confirms the round works): generic phone parsing boundaries (+CC generic, bare 10-digit default, junk 400), drill-down loaders' per-section settle, Load-more cursor threading.
