---
title: 'Story 21-1: Backend invite SMS — role word, fitted names, trimmed company name, placeholder template, audit and counting records'
type: 'feature'
epic: 'epic-21'
repo: 'fenzit-be'
status: 'in-progress'
baseline_commit: '73bf45e64971e4b63c7a31b0d5dd611307c15a66'
spec: 'artifacts/specs/spec-invite-sms-download-link/SPEC.md'
stories_source: 'artifacts/specs/spec-invite-sms-download-link/stories.yaml'
deploy_order: 'first (additive) — deploys before 21-2, 21-3 and 21-4'
spec_checkpoint: true
---

## Intent

When an owner, company admin or viewer invites a person, one SMS must go to that person's phone with a download link. Today `POST /auth/invite` saves the invite and sends nothing. This story adds the SMS step after `invite_member` succeeds. A failed SMS never rolls back the invite.

## Code touchpoints (verified 2026-11-10)

| What | Where |
|---|---|
| Invite endpoint | `src/auth/auth.controller.ts` — `@Post('invite')`, guarded by `@Can('member.invite')` |
| Invite service | `src/auth/auth.service.ts` — `inviteMember()`, calls RPC `invite_member`, maps errors with `memberRpcException` |
| Invite DTO | `src/auth/dto/invite-member.dto.ts` — `countryCode`, `phoneNumber`, `name`, `role`, `skillIds` |
| SMS port (frozen) | `src/auth/sms-delivery.provider.ts` — `send(to, templateId, variables)`; failures are `SmsDeliveryError` with `outcome: 'timeout' \| 'error'` |
| SMS adapter (MSG91) | `src/auth/msg91-sms-delivery.provider.ts` — FLOW endpoint, variables mapped **by name** |
| Mock adapter (tests) | `src/auth/mock-sms-delivery.provider.ts` |
| Template ID constants | `src/common/constants/sms-templates.ts` — add `T-INVITE` here, placeholder value |
| Error codes | `src/common/enums/error-code.enum.ts` |
| Roles | `src/common/enums/role.enum.ts` — `company_admin`, `employee`, `viewer` on a membership |
| Migrations | `supabase/migrations/` (latest: `20261109000001_…`); new files use the next timestamp |
| Provider wiring | `src/auth/auth.module.ts` |

## Contract

**Request:** unchanged `POST /auth/invite` body.

**Response (201), additive field:**
```json
{ "invite_id": "uuid", "employee_code": "…", "sms_status": "sent | failed | not_configured" }
```
- `sent` — the provider accepted the message.
- `failed` — the provider returned an error or timed out. The invite is kept.
- `not_configured` — the template ID is still the placeholder; no provider call was made.

The existing fields stay. Clients that ignore `sms_status` keep working (additive change, deploy first).

## Template and variables (decision 2026-11-10, MSG91 by-name mapping)

Message text, as registered:
`Hi {name}, you are added to {company} as {role}. Get the app at fenzit.com/app/download and log in with this number. - Fenzit Technology`

Variable names are **`name`, `company`, `role`**. The DLT portal form uses `##name##`, `##company##`, `##role##`. The ops submission must use these exact names, or MSG91 will not map them. The placeholder in code is `T-INVITE` with value `PENDING_DLT_APPROVAL`; while it is that value, sending is off.

## Data model

Two new tables, both with RLS deny-by-default and service-role writes only (the backend is the only writer).

1. **`invite_sms_audit`** — one row per attempt. Columns: `id`, `membership_user_id` (FK to the invited membership), `tenant_id`, `phone_masked` (`+91 ******3210`), `outcome` (`sent | failed | refused_cap | not_configured`), `created_at`. **No full number, no hash.** Retention: delete rows older than 12 months.
2. **`invite_sms_counter`** — one row per counted send. Columns: `id`, `phone_hash` (keyed hash, see below), `created_at`. Retention: delete rows older than 24 hours. Index on `(phone_hash, created_at)`.

Keyed hash: HMAC-SHA256 of the E.164 number, key from backend secret `INVITE_SMS_HASH_KEY`. Never in code, never in logs.

Retention job: a scheduled cleanup (or a documented manual SQL step until the scheduler exists). The choice goes in the dev notes.

## Name and company-name rules (pure functions, unit-tested)

- `fitFirstName(name)`: trim → first whitespace-separated word → Devanagari letters converted with a small custom table → if any non-ASCII letter remains, return `there` → cut to 12 characters. Empty result → `there`.
- `fitCompanyName(name)`: trim → cut to 20 characters. Stored name is never changed.
- `roleWord(role)`: `employee → Employee`, `company_admin → Admin`, `viewer → Viewer`. Any other value throws (validation already rejects it earlier).

Check: the rendered message must fit in 160 characters with the longest variables (12, 20, 8). Add a unit test that asserts this.

## Tasks

1. Add `INVITE_SMS_HASH_KEY` to the config schema (required in production, fail fast at boot if missing).
2. Add migration: `invite_sms_audit` and `invite_sms_counter` with RLS deny-by-default.
3. Add `fitFirstName`, `fitCompanyName`, `roleWord` as pure functions with unit tests (test timing: after owner confirms).
4. Add `T-INVITE` to `sms-templates.ts` with the placeholder value and the approved-copy comment.
5. In `inviteMember()`, after the RPC succeeds: decide the outcome (`not_configured` / send), call `SmsDeliveryProvider.send` with `{ name, company, role }`, write the audit row, write the counter row only on an actual send, and return `sms_status`.
6. Catch `SmsDeliveryError`: keep the invite, set `sms_status: failed`, write the audit row with `outcome: failed`. Never let the SMS error bubble up as a 500.
7. Add the Swagger examples for the new response field.
8. Document the retention job in the spec's dev notes.

## Error codes (stable strings)

- No new error code on the invite path. SMS failure is a field, not an error.
- `INVITE_SMS_LIMIT_REACHED` is story 21-2's code, not this one.

## Constraints

- The SMS text is built in the backend only. Clients never build it.
- Use the existing `SmsDeliveryProvider` port. Do not add a second provider.
- No phone number in any log, error body or response. Logs use the masked form.
- The company name is trimmed for the SMS only. The invite screen and the stored name are unchanged.
- The word `Technician` never appears in a message, response, error text or log line. The owner app's `technicians.ts` comment about the invite SMS is corrected in 21-4, not here.

## Out of scope

- The Resend endpoint and the 5-per-hour cap (21-2).
- Any app or web change (21-3, 21-4).
- Switching sending on. That happens only after the approved template ID is supplied.

## Tests (write after the owner confirms the behaviour)

Name the intended tests now:

- Name rule: a Devanagari name, a 12-character name, a 13-character name, an empty name, leading spaces, a Latin-plus-Devanagari mix, an emoji, and a single letter.
- Company name: exactly 20 characters, 21 characters, and multibyte characters.
- Role word: all three roles, and a rejected value.
- Message length: the longest case stays within 160 characters.
- SMS failure: the invite is kept, `sms_status` is `failed`, one audit row with `outcome: failed`, no counter row.
- Placeholder: `sms_status` is `not_configured`, no provider call, no counter row.
- Success: one audit row with `outcome: sent`, one counter row, the hash is not the phone number.
- Masking: the audit row and the logs never contain the full number.
- Tenant isolation: the SMS names only the inviting company.

## Done when

- The owner has confirmed the behaviour on a local or staging run.
- The tests above are written and pass.
- `/bmad-code-review` has run and its findings are triaged.
- The owner has agreed to the commit. The commit lands in `fenzit-be` only. Nothing is pushed without consent.

## Dev notes

- **Migration:** `workspace/core/backend/fenzit-be/supabase/migrations/20261111000001_invite_sms_audit_and_counter.sql`. Not applied to the remote database yet.
- **Code:** `src/auth/invite-sms/` (name and company rules, Devanagari table, `InviteSmsService`). Hook in `AuthService.inviteMember()`. Template placeholder `T-INVITE` in `src/common/constants/sms-templates.ts`. Config `INVITE_SMS_HASH_KEY` in `src/app.module.ts` (required in production, 32 characters minimum).
- **Retention (chosen):** pg_cron jobs in the migration, the same way as the device-tokens and notifications cleanups. `invite-sms-audit-prune` deletes audit rows older than 12 months, daily at 03:50 UTC. `invite-sms-counter-prune` deletes counter rows older than 24 hours, hourly at :20.
- **Name rule choices:** a converted Devanagari name is capitalised. Any non-ASCII character after conversion (letters, emoji, symbols) gives "there", so the SMS never leaves plain characters. Hyphens and apostrophes pass through.
- **Company name:** trimmed and cut to 20 characters by code point. A non-English company name is not handled by this story and would make the SMS a 70-character message. Owner decision needed.
- **Tests to write after confirmation:** the list in the Tests section above. Existing `auth.service.spec.ts` needs `InviteSmsService` added to its providers.
- **Deploy:** `fenzit-be` ships first. Set `INVITE_SMS_HASH_KEY` in production before deploy, or the app will not boot.
