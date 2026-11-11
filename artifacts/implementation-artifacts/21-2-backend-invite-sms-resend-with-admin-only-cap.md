---
title: 'Story 21-2: Backend resend invite SMS — company admin only, 5 per phone per rolling hour'
type: 'feature'
epic: 'epic-21'
repo: 'fenzit-be'
status: 'in-progress'
spec: 'artifacts/specs/spec-invite-sms-download-link/SPEC.md'
stories_source: 'artifacts/specs/spec-invite-sms-download-link/stories.yaml'
deploy_order: 'first (additive) — after 21-1, before 21-4'
spec_checkpoint: false
---

## Intent

When an invite SMS did not arrive or failed, a company admin must be able to send it again. The same phone number must not receive more than 5 invite SMS in any rolling one-hour window, counting every invite and re-invite.

## Code touchpoints

| What | Where |
|---|---|
| New endpoint | `src/auth/invite-sms.controller.ts` (kept apart from `auth.controller.ts`, as built) |
| Service | `src/auth/invite-sms/invite-sms.service.ts` (the send and cap, shared with the invite path), and `src/auth/invite-sms/invite-sms-resend.service.ts` (who may resend, and the 403/404/409/429 answers) |
| Permission | `@AnyMember()` on the route, with the company-admin check in the service against `invite_sms.resend` in `src/common/permissions/permissions.ts`. Not `@Can`, so non-admins get `NOT_COMPANY_ADMIN`, not a generic FORBIDDEN (see Dev notes) |
| Idempotency | optional `X-Idempotency-Key` through the existing `IdempotencyInterceptor` (added 2026-11-11, review decision 2) |
| Counters and audit | `invite_sms_counter`, `invite_sms_audit` from 21-1 |
| Error codes | `src/common/enums/error-code.enum.ts` |
| Membership lookup | existing membership resolver in `src/common/auth/membership-resolver.ts` |

## Contract

**Endpoint:** `POST /auth/invite/:membershipUserId/resend-sms`
(Path uses the invited membership's user ID, the same ID the invite response returns as `invite_id`.)

**Body:** none.

**Responses**
- `201` — `{ "sms_status": "sent" | "failed" | "not_configured" }`. A repeat with the same `X-Idempotency-Key` replays the first answer and sends nothing. A malformed key is `422`.
- `403` — `NOT_COMPANY_ADMIN` (caller is not a company admin in this company)
- `404` — `INVITE_NOT_FOUND` (no invited membership with that ID in the caller's company)
- `409` — `INVITE_NOT_PENDING` (membership is no longer `invited`; for example, the person already signed in)
- `429` — `INVITE_SMS_LIMIT_REACHED` (5 counted sends to this phone in the last 60 minutes)

Error bodies follow the existing `{ error_code, message }` shape. `message` is plain English. The app branches on `error_code` only.

## Rules

1. **Admin only.** Only a `company_admin` membership in the caller's company can call this. The check is on the server. Owners are company admins (resolved 2026-11-11, see Dev notes).
2. **Same company.** An invited membership in another company returns `404`, not `403`, so the endpoint does not reveal that the person exists elsewhere.
3. **Status must be `invited`.** Any other status returns `409`.
4. **Cap.** Count `invite_sms_counter` rows for this phone hash with `created_at > now() - 60 minutes`. If the count is 5 or more, write an audit row with `outcome: refused_cap` and return `429`. Send nothing.
5. **Send.** Under the cap: same send path and same name, company and role rules as 21-1. The counter row is reserved before the send, and deleted again if the send fails. A timeout keeps it (see Dev notes, and the "Failed sends and the reservation" note).
6. **Placeholder.** While `T-INVITE` is the placeholder, return `sms_status: not_configured`. No counter row, no provider call. This check runs before the cap, so a capped phone gets `not_configured` (201), not a 429, while sending is off.
7. **Re-invite counts.** A re-invite of the same phone (handled by 21-1's `inviteMember`) also writes a counter row, so it counts toward the same 5.

## Race safety (required)

Two parallel resends at count 4 must not both succeed. Choose one approach and record it in the dev notes:
- **(a)** A single guarded transaction that locks a per-phone row (`SELECT … FOR UPDATE` on a small `invite_sms_phone_lock` row keyed by phone hash), counts, then inserts.
- **(b)** A Postgres function that does count-and-insert atomically.

Either way, the count and the insert happen inside the same transaction. A `SELECT count` followed by a separate `INSERT` is not acceptable.

## Tasks

1. Decide the permission approach (permission key vs explicit role check). Record it.
2. Add the endpoint, the service and the DTO-less route (no body).
3. Add the atomic count-and-insert (option a or b above).
4. Add the error codes to `error-code.enum.ts`.
5. Write one audit row per attempt (sent, failed, refused_cap, not_configured).
6. Add Swagger docs with the four error responses.

## Constraints

- Authorization and the cap check live in the service, not the controller.
- The cap count comes from the database, never from memory, so it holds across instances.
- No phone number in any response, log or error. Masked form only.
- Do not change the cap value (5) or the window (60 minutes) without a new decision.

## Out of scope

- The owner app's Resend button and messages (21-4).
- Any change to the invite SMS text or template (21-1).

## Tests (planned list; unit and HTTP tests were written early at the owner's request, real-database tests wait for the owner's confirmation)

Name the intended tests now:

- Permission matrix: company admin (allowed), owner (allowed, if owners are admins), employee, viewer, platform admin acting in another company.
- Cap boundary: sends 1 to 5 allowed, the 6th refused with `429`, and allowed again after the window passes (use a clock that can be moved).
- Re-invite counts: invite, then re-invite, then resend. All three count toward the same cap.
- Race: two parallel resends at count 4 — exactly one succeeds, and the total count is 5, not 6.
- Unknown membership, membership in another company, and a non-invited membership.
- Placeholder: `not_configured`, no provider call, no counter row.
- `failed` provider result: counter row not written, audit row written with `failed`. Failed sends do not count toward the cap (owner decision 2026-11-10).
- A failed send followed by a successful resend: exactly one counter row, so the cap is 1 of 5, not 2 of 5.
- Masking: no full number in the response, logs or audit row.

### Coverage status (checked 2026-11-11, fenzit-be f555b41)

Existing tests, all with mocked database and provider:
- `src/auth/invite-sms/invite-sms.service.spec.ts` (11 tests): timeout keeps the slot; rejection releases it; success keeps it; `refused_cap` sends nothing and audits without a delete; a cap-check DB error sends nothing; canonical number shares one slot; a different number gets its own key; a rejected audit write after a sent text still returns `sent`.
- `src/auth/auth.service.spec.ts`: invite returns `refused_cap` and `not_configured` (mocked service).

Written 2026-11-11 (unit level, mocked database). Run with `bun run test -- src/auth/invite-sms src/auth/auth.service.spec.ts`: 118 tests green, typecheck clean. Written before the owner's confirmation of the behaviour, at the owner's instruction "write test gaps".
- [x] Permission matrix: `invite-sms-resend.service.spec.ts`. Company admin (owners are company_admin memberships) allowed; employee, viewer, platform admin, no membership, and no company refused with 403 before any read.
- [x] Unknown, other-company and non-invited memberships: 404, 404 (identical body) and 409. Lookup failure and a missing user row give 500 with no send.
- [x] 429 on a refused cap, with no full number in the body. `failed` and `not_configured` pass through as 201 statuses.
- [x] Placeholder: `invite-sms.placeholder.spec.ts`. `not_configured`, no provider call, no cap row.
- [x] Failed then successful resend: `invite-sms.service.spec.ts`. Net cap slots = 1. A timeout then a retry = 2.
- [x] Masking: audit row, logs and 429 body contain no full number.
- [x] Cap value: the cap function is called with 5 and 60 minutes.
- [ ] Cap boundary end to end, including the 60-minute reset. Needs a real database and a movable clock. The unit tests cannot test the window.
- [ ] Re-invite counts: invite, re-invite and resend share one cap. The count lives in the database, so this needs the e2e suite.
- [ ] Race: two parallel resends at count 4 give exactly one success and five rows. Needs a real database.
- [x] Route wiring over HTTP (2026-11-11): `test/invite-sms-resend.e2e-spec.ts` (401, 403 employee and viewer, 400 bad ID, 404, 409, 201 `not_configured` with no phone number) and `test/invite-sms-resend-cap.e2e-spec.ts` (201 `sent`, 201 `failed`, 429 with nothing sent; template swapped in for the file). Run with `bun run test:e2e -- test/invite-sms-resend`: 10 green.
- [x] Invite e2e repaired (`test/invite.e2e-spec.ts`, 12 green; it was 9 red before this change, on HEAD). Causes, all in the test, not the app: (a) `SubscriptionExpiryGuard` (added in 8e277d1) reads `tenants` through the admin mock, which did not model it; the harness now answers that read (`test/helpers/open-subscription-admin.ts`). (b) AC1 now expects `sms_status: 'not_configured'`, the 21-1 contract. (c) AC3 expected 422 for an empty `skillIds`, but commit d9fa073 made an empty list valid, so the test now expects 201. (d) The OTP fixture phone `2222222222` breaks the Indian mobile rule `[6-9]`; it is now `9222222222`.
- [ ] Cap boundary end to end with a real database (the window reset). Still open.
- [ ] Re-invite counts against the database. Still open.
- [ ] Race against a real database. Still open.

## Done when

- The owner has confirmed the behaviour on a local or staging run.
- The tests above are written and pass.
- `/bmad-code-review` has run and its findings are triaged.
- The owner has agreed to the commit. The commit lands in `fenzit-be` only. Nothing is pushed without consent.

## Dev notes

- **Task 1, permission: `invite_sms.resend`, held by `company_admin` only, enforced in the service.** The route is `@AnyMember()` in `src/auth/invite-sms.controller.ts`. `InviteSmsResendService` refuses unless `permissionsFor(role)` has `invite_sms.resend` and the caller is not a platform admin. Why not `@Can`: the guard would answer employees and viewers with a generic FORBIDDEN, but the contract needs NOT_COMPANY_ADMIN for them. Why not `member.invite`: a platform admin holds it, so staff would pass as company admins. The new permission sits outside `ADMIN_PERMISSIONS`, so `platform_admin` does not get it. Owners are `company_admin` (spec open item resolved 2026-11-11), so they pass.
- **Task 3, race: option (b), a Postgres function.** `invite_sms_reserve_send` (migration `20261111000002_invite_sms_reserve_send.sql`) takes a per-phone advisory lock, counts the rolling window, and inserts one counter row in one transaction. Why a function: PostgREST cannot hold one transaction across two calls, and the lock has to be taken in SQL. This is the only new RPC. Plain English: the count and the insert must be one step, and no NestJS-only path can make them one step.
- **Failed sends and the reservation.** The slot is reserved before the send and deleted if the send fails. Holding a DB transaction open across the MSG91 call would keep a lock during an external timeout. Trade-offs: a slot counts while its send is in flight, and a crash between reserve and send leaves a slot that counts only until its 60-minute window passes. The 24-hour prune only removes old rows; it does not change the count.
- **Timeout (decided 2026-11-11).** A timeout counts toward the cap, because the SMS may have been delivered. Its slot is kept, and the audit row and response still say `failed`. Code done: fenzit-be `invite-sms.service.ts` keeps the slot on a timeout (commit f555b41).
- **Invite path is capped too.** Invite and re-invite share the 5-per-hour cap, as the intent and the success signal require. When the cap stops an invite SMS, `POST /auth/invite` returns `sms_status: refused_cap` (decided 2026-11-11; the invite is kept). The audit row says `refused_cap`, and Resend answers 429. Code done: `invite-sms.service.ts` returns `refused_cap` and `auth.service.ts` passes it through (commit de24d1f; f555b41 hardened it).
- **Order of checks:** role (403) → membership in the caller's company (404) → status (409) → cap (429) → send. A non-admin never learns whether a membership exists.
- **Audit:** one row per attempt. `refused_cap` was already in the 21-1 outcome check, so no change to that table.
- **Constants:** cap 5 and window 60 minutes in `src/auth/invite-sms/invite-sms-cap.constants.ts`, passed into the function. Unchanged.
- **Tests:** see the Coverage status section above (unit and HTTP tests written 2026-11-11; the real-database tests are still open). Covered by this change: the permission matrix, cap boundary, re-invite counting, the race, unknown or other-company membership, non-pending membership, placeholder, failed-send release, failed-then-success, and masking.

### Review Findings

Review run 2026-11-11 (bmad-code-review; layers: blind-hunter, edge-case-hunter, verification-gap, acceptance-auditor). Scope: uncommitted 21-2 test files in fenzit-be plus production commits de24d1f and f555b41. Reviewers' line numbers were checked against the source before triage.

**decision-needed**
- [x] [Review][Decision] Real-database tests for the cap: the window reset, re-invite counting and the parallel race are still unproven. Every test stubs `invite_sms_reserve_send`, so a broken SQL function (wrong count, missing lock, missing window) would pass the whole suite. Options: (a) write the real-DB integration tests now, against a test database; (b) write them after the owner confirms the behaviour, per the test-timing rule. — medium
- [x] [Review][Decision] Resend double-click: each click consumes a cap slot and sends another text. Options: (a) add an `Idempotency-Key` header on the resend POST, as the backend write rules call for; (b) accept it and leave the owner app to disable the button while sending. — medium
- [x] [Review][Decision] Unexpected provider error after dispatch releases the slot. Only a timeout keeps it. Options: (a) keep as is; (b) count every error that is not a clean rejection as used. — medium
- [x] [Review][Decision] Config fault shows as `failed`. A missing `INVITE_SMS_HASH_KEY` outside production makes every send read as `failed`, with only a generic log line. Options: (a) require the key in every environment except test at boot (app.module Joi rule); (b) log config faults at error level and keep the `failed` status. — medium
- [x] [Review][Decision] The 429 message reveals that other companies have texted this phone, and the cap is global across companies. The spec says "the same phone must not receive more than 5", so global is the literal reading. Options: (a) keep the global cap and use a neutral 429 message; (b) keep the message. — low
- [x] [Review][Decision] Commit shape. The diff mixes the 21-2 test files with repairs to the invite e2e suite (AC1 contract, AC3 empty list, OTP fixture phone). Options: (a) separate commit for the repairs; (b) one commit, with each repair named in the message. — low

**patch**
- [x] [Review][Patch] Story text is stale: Rule 5 says the counter row is written only when a send happens (it is reserved first, then released on failure); the contract omits `refused_cap` on `POST /auth/invite`; the timeout rule is missing; the code touchpoints name old paths and `@Can`; Rule 1 still says "confirm" the owner role; Dev notes say the expiry is the 24-hour prune (the count window is 60 minutes); the test-timing status contradicts itself. [artifacts/implementation-artifacts/21-2-backend-invite-sms-resend-with-admin-only-cap.md] — low
- [x] [Review][Patch] Spec does not state the order of checks when sending is off: the placeholder check runs before the cap, so a capped phone gets `not_configured`, not a 429. [story Dev notes] — low
- [x] [Review][Patch] Migration comments drift: `20261111000001_invite_sms_audit_and_counter.sql` says the counter holds one row per SMS actually sent; `20261111000002_invite_sms_reserve_send.sql` says a failed send deletes its row, and does not say a timeout keeps it. Comments only. [supabase/migrations/20261111000001_invite_sms_audit_and_counter.sql, supabase/migrations/20261111000002_invite_sms_reserve_send.sql] — low
- [x] [Review][Patch] Resend unit spec: add the case `platformAdmin: true` with a `company_admin` role. The guard checks the flag, and the test only covers the role. [src/auth/invite-sms/invite-sms-resend.service.spec.ts] — low
- [x] [Review][Patch] Cross-company test passes on any two nulls, so it would still pass if the tenant filter were removed. The separate scoping test covers the filter, but this one should assert the filter too. [src/auth/invite-sms/invite-sms-resend.service.spec.ts] — low
- [x] [Review][Patch] Failed-send HTTP test does not assert that the counter row was deleted. The unit test covers it. [test/invite-sms-resend-cap.e2e-spec.ts] — low
- [x] [Review][Patch] Placeholder tripwire: add a comment that this file must be updated or removed when the DLT template ID ships. [src/auth/invite-sms/invite-sms.placeholder.spec.ts] — low

**defer** (appended to deferred-work.md)
- [x] [Review][Defer] The invite HTTP request awaits the SMS provider, so each invite waits up to the provider timeout. [src/auth/auth.service.ts] — deferred, pre-existing design
- [x] [Review][Defer] The 429 has no Retry-After header, though the window is a rolling 60 minutes. [src/auth/invite-sms/invite-sms-resend.service.ts] — deferred, pre-existing design
- [x] [Review][Defer] The resend checks `invited` before sending and does not re-check, so a person who joins in between still gets the text. [src/auth/invite-sms/invite-sms-resend.service.ts] — deferred, pre-existing design
- [x] [Review][Defer] `logger.error('...', { error })` puts the object in the stack position. This pattern is used across the codebase. [src/auth/invite-sms/invite-sms.service.ts] — deferred, pre-existing pattern
- [x] [Review][Defer] The audit foreign key is ON DELETE RESTRICT, so a future hard delete of a texted membership will fail. Check removal flows before any hard delete. [supabase/migrations/20261111000001_invite_sms_audit_and_counter.sql] — deferred, pre-existing design

**dismissed (noise, false positive, or already decided)**: 10
- releaseCounter throwing: supabase-js returns errors rather than throwing, and a failed release is already logged.
- DB error in the cap check gives `failed`, not 500: deliberate and tested ("a database error in the cap check returns failed and sends nothing").
- Null users.phone_number: the users table has phone NOT NULL (20260619000001); not re-checked against the current schema.
- Unknown membership role: `memberships_role_check` constrains the value.
- RPC returns a non-string: the function returns a uuid or null.
- Missing member_user_id from invite_member: outside 21-2, and an RPC contract matter.
- Parallel sends causing a false 429: already documented in Dev notes ("a slot counts while its send is in flight").
- `@AnyMember()` with a service-side check: already documented in Dev notes.
- Pre-try code in sendInviteSms throwing: createAdmin and canonicalisation cannot realistically throw.
- Review base mismatch in the blind-hunter report: a process note, not a code defect.

**Resolutions (2026-11-11, owner asked for best decisions):**
- Decision 1 (real-DB cap tests): option (b). Still open. Written after the owner confirms the behaviour, against a test database. The Verification Gap finding stands until then.
- Decision 2 (resend double-click): option (a). Applied: optional `X-Idempotency-Key` through the existing `IdempotencyInterceptor`, with three e2e tests. Best effort: two clicks at the same instant can both get through, and the cap still holds. The owner app (21-4) should also disable the button while a send is in flight.
- Decision 3 (provider error after dispatch): option (a). Unchanged. Matches owner decision 2026-11-10 (failed sends do not count).
- Decision 4 (config fault): option (b). Applied: non-provider errors now log at error level, so a missing hash key stands out. Status stays `failed`. Requiring the key at boot is left for a later decision.
- Decision 5 (429 message): option (a). Applied: neutral wording that does not say whose invites used the limit. Cap stays global, as the spec says.
- Decision 6 (commit shape): still open. Asked at commit time.
- Patches: all six applied. Story text, placeholder order note, migration comments, platform-admin flag test, cross-company tenant-filter assertion, failed-send counter assertion, and go-live reminder on the placeholder test.
