# Spec: Website login (email or phone) and company admin page

Status: approved by the product owner (2026-10-21). UX pass: `web-login-and-owner-admin-ux.md`.
Repos: `fenzit-be` (backend first), `fenzit-web` (website)
Date: 2026-10-20
Depends on: `roles-and-access-spec.md` (roles, memberships, token and guard rules). This spec follows its decisions and does not repeat them.

## Goal

A visitor to fenzit.com can log in from a Log in button in the header. Login accepts either the phone number (existing OTP flow, unchanged) or an email address plus password. After login, a company admin or platform admin sees a dummy admin page. Anyone else who logs in sees a plain "no access" message.

## Decisions already made (from the conversation)

1. Email login uses a fixed password for now. The real email provider is chosen later. Phone OTP login stays as it is.
2. One email maps to one phone number, and the reverse. Email is unique across users.
3. Phone stays required. Email is an extra way to log in, so the change is additive.
4. An email is linked by a logged-in user from a profile step, not at sign-up.
5. The web app keeps the signed-in token in localStorage.
6. Only `company_admin` and `platform_admin` can open the admin page (roles spec, decision 18).
7. The Log in button sits next to "Join early access" in the header.
8. The fixed password is hardcoded in the backend source. The product has no users yet, so the risk is accepted by the product owner (2026-10-20). It must still follow the guardrails below. It is a development shortcut under roles spec decisions 9 and 30, and removing it is part of the go-live gate (roles spec, order of work step 9).

## How this follows the roles spec

- The login token carries identity only (user ID and the `typ: 'access'` marker). It has no role or company (roles spec, decisions 22 and 23). The website therefore never trusts a role from the token or from localStorage.
- After login, and every time the admin page loads, the website asks the backend who the user is with the existing `GET /users/me`. The roles work updates that endpoint to return the user, a `platformAdmin` flag, and the active membership (role and company) or none. The role shown to the page comes only from that response.
- A disabled person (roles spec, decision 35) gets the same generic 401 as a wrong password, at login and on every later request.
- A removed member's next request returns 403 `FORBIDDEN` (roles spec, invite and login rules). The website treats 401 and 403 from `GET /users/me` as signed out and returns to `/login`.
- A person with no active membership can sign in. The website shows the no-permission message, and company setup stays in the mobile app.

## Backend guardrails for the fixed password

- The value is a constant in the backend source code, the same way `PRE_RELEASE_MASTER_OTP` is. It is not read from an environment variable (product owner's call, 2026-10-20). It is never in any `VITE_*` value, and it is never returned or logged.
- The constant is marked "remove at go-live" in a code comment, and the real email provider replaces it later.
- The fixed password signs in the user who owns that email, with the role that user has. It does not create users or roles.
- Failed email-password attempts count against the same lockout rule as wrong OTP codes.
- The password is never logged, returned, or echoed in an error body.

## Backend (`fenzit-be`)

Ships first, because the web app depends on it. It ships in the same release as the roles work, so it uses the new token, guard and permission rules.

- **Migration (new file, not applied yet):** add `users.email text null` with a unique constraint, and a format check (lowercase, length 3–254, basic email shape). Existing rows keep `email = null`. The roles migration adds `users.disabled` (roles spec, decision 35). Enable nothing new in RLS.
- **`POST /auth/email/login`** (public): body `{ email, password }`. Returns the same shape as `otp/verify`: `token` and `user`. The token follows the roles spec (identity only, with the marker). Errors use `error_code`. An unknown email, a wrong password, and a disabled user all return the same generic 401, so the endpoint does not reveal which emails exist.
- **`POST /auth/email/link`** (any signed-in user, `@AnyMember()`, roles spec decision 10): body `{ email }`. Links the email to the signed-in user. Returns 409 `DUPLICATE_RESOURCE` when another user already has it. It works for a person with no membership yet.
- **`GET /users/me`** (exists today): updated by the roles work to return `email`, `platformAdmin` and the membership. No new endpoint is needed.
- Tests follow the repo's test rules after the feature is confirmed working, not before.

## Web (`fenzit-web`)

Ships after the backend is deployed.

- **Header:** a "Log in" link beside "Join early access" on desktop. On mobile it stays visible in the header bar. Links to `/login`.
- **`/login` page:** one form with two fields, "Phone or email" and "Password". Phone numbers follow the existing country-code rule; the page decides which login path to call. Empty and invalid states are handled. Errors use `messageForError`. Loading state and timeout come from `apiFetch`.
- **Token:** on success, store the token in localStorage under one key, with the user's display name for the header. Do not store the role. Wrap every read and write in try/catch. A missing or unreadable value means signed out.
- **`/admin` page:** requires a stored token. If there is none, redirect to `/login`. On load it calls `GET /users/me`. A 401 or 403 clears storage and redirects to `/login`. If the response shows neither the `company_admin` role nor `platformAdmin`, show "You do not have permission to open this page." Admins see a plain dummy page with a heading and a Log out button.
- **Log out:** clears localStorage and returns to `/`.
- **Design:** Sally reviews the login and admin screens against the design system before the build. Tokens only, no raw hex.
- **Routes** are added to `src/app/routes.tsx`. The new pages are client-only, so they are not pre-rendered.

## Out of scope

- The real email provider, and sending any email.
- Password reset, password change, and sign-up with email.
- Any change to the mobile app, except the role-name changes in the roles spec.
- Platform admin screens beyond the dummy admin page.
- Changing `sprint-status.yaml`. Whether this becomes a tracked epic is a separate decision.

## Open items to confirm during implementation

- None. `GET /users/me` exists (`src/users/users.controller.ts`), so no new endpoint is needed.

## Decisions from the review (2026-10-21)

- **Re-linking:** an account that already has an email cannot change it through `POST /auth/email/link` (409). Setting the same email again is a no-op (200). An admin changes an email by hand until a change flow exists.
- **Enumeration:** the 409 for an address that belongs to another account is limited. After 5 such answers in 10 minutes for one user, the endpoint answers 429. A user with many accounts can still probe, so per-IP limiting belongs at the edge before go-live.
- **Go-live gate, not built yet:** an email must be proven before it is linked (a code sent to that address). Email sending is out of scope until the email provider is chosen, so the link works without proof for now. Email login is dev-only until then.
- **Logout:** the web app clears its own sign-in only. The token stays valid until it expires on the server. A server-side revoke is a later decision.
- **Direct visits:** `/login` and `/admin` have their own static shell, so a direct visit answers 200 and the router draws the page.
- **Phone sign-in:** India only, 10-digit mobile numbers. Other countries are not supported on this page yet.

## Order of work

1. Spec approved (this file and the roles spec).
2. fenzit-be: the roles work first (roles spec, order of work steps 0 to 5), then the migration file, the two email endpoints and the guardrails. Local tests run. Migrations are applied to the remote database only after approval.
3. Sally: UX pass on the login and admin screens. Output saved next to this spec.
4. fenzit-web: header, login page, token storage, admin page, routes. Local build and typecheck run.
5. User confirms the flow works on the local build.
6. Tests written for both repos.
7. `/bmad-code-review` in each repo, then a commit only after consent. fenzit-be deploys first.
