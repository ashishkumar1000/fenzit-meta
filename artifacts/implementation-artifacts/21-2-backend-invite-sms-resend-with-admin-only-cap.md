---
title: 'Story 21-2: Backend resend invite SMS — company admin only, 5 per phone per rolling hour'
type: 'feature'
epic: 'epic-21'
repo: 'fenzit-be'
status: 'ready-for-dev'
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
| New endpoint | `src/auth/auth.controller.ts` (or a new `invite-sms.controller.ts` if the file nears 300 lines) |
| Service | new `src/auth/invite-sms.service.ts`, reusing the 21-1 send path |
| Permission | `@Can(...)` for company admin only — confirm the permission key in `src/common/permissions/permissions.ts` (the invite uses `member.invite`; Resend needs a permission that only `company_admin` holds, or an explicit role check) |
| Counters and audit | `invite_sms_counter`, `invite_sms_audit` from 21-1 |
| Error codes | `src/common/enums/error-code.enum.ts` |
| Membership lookup | existing membership resolver in `src/common/auth/membership-resolver.ts` |

## Contract

**Endpoint:** `POST /auth/invite/:membershipUserId/resend-sms`
(Path uses the invited membership's user ID, the same ID the invite response returns as `invite_id`.)

**Body:** none.

**Responses**
- `201` — `{ "sms_status": "sent" | "failed" | "not_configured" }`
- `403` — `NOT_COMPANY_ADMIN` (caller is not a company admin in this company)
- `404` — `INVITE_NOT_FOUND` (no invited membership with that ID in the caller's company)
- `409` — `INVITE_NOT_PENDING` (membership is no longer `invited`; for example, the person already signed in)
- `429` — `INVITE_SMS_LIMIT_REACHED` (5 counted sends to this phone in the last 60 minutes)

Error bodies follow the existing `{ error_code, message }` shape. `message` is plain English. The app branches on `error_code` only.

## Rules

1. **Admin only.** Only a `company_admin` membership in the caller's company can call this. The check is on the server. Owners are company admins (confirm the owner's stored role in dev notes; this is an open item in the spec).
2. **Same company.** An invited membership in another company returns `404`, not `403`, so the endpoint does not reveal that the person exists elsewhere.
3. **Status must be `invited`.** Any other status returns `409`.
4. **Cap.** Count `invite_sms_counter` rows for this phone hash with `created_at > now() - 60 minutes`. If the count is 5 or more, write an audit row with `outcome: refused_cap` and return `429`. Send nothing.
5. **Send.** Under the cap: same send path and same name, company and role rules as 21-1. The counter row is written only when a send actually happens.
6. **Placeholder.** While `T-INVITE` is the placeholder, return `sms_status: not_configured`. No counter row, no provider call.
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

## Tests (write after the owner confirms the behaviour)

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

## Done when

- The owner has confirmed the behaviour on a local or staging run.
- The tests above are written and pass.
- `/bmad-code-review` has run and its findings are triaged.
- The owner has agreed to the commit. The commit lands in `fenzit-be` only. Nothing is pushed without consent.
