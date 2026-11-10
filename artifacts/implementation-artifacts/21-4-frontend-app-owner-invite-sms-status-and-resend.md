---
title: 'Story 21-4: fenzit-app owner invite — "SMS not sent" status and admin-only Resend'
type: 'feature'
epic: 'epic-21'
repo: 'fenzit-app'
status: 'ready-for-dev'
spec: 'artifacts/specs/spec-invite-sms-download-link/SPEC.md'
stories_source: 'artifacts/specs/spec-invite-sms-download-link/stories.yaml'
deploy_order: 'last — after 21-1, 21-2 and 21-3 are deployed'
spec_checkpoint: true
---

## Intent

After an owner invites someone, the owner must see whether the SMS went out. If it failed or was not sent, a company admin can press Resend. When the 5-per-hour cap is reached, the owner sees a clear message and no misleading button.

## Code touchpoints (verified 2026-11-10)

| What | Where |
|---|---|
| Invite API call | `src/services/resources/technicians.ts` — `POST /auth/invite` (the comment around line 39 says the endpoint "sends the SMS invite"; that is wrong until 21-1 ships, and this story corrects it) |
| Invite types | `src/features/technicians/types.ts` — payload (around line 48) and response (around line 59). Add `sms_status` to the response type. |
| Invite hook | `src/features/technicians/useTechnicians.ts` — the `add` action |
| Caller | `src/features/newJob/NewJobScreen.tsx` (around line 133) — New Job reacts to the invite outcome |
| Invite sheet | the inline "add technician" sheet from story 11-3 (see `sprint-status.yaml` entry 11-3). Confirm the exact file in dev. |
| Error mapping | find the repo's existing error-code to message map (search for the mapper used by other screens, for example `messageForError`). Add the new codes there. |
| Role check | the current user's role comes from the existing auth state (`features/auth/types.ts`). Confirm the field name in dev. |
| Design tokens | `src/theme/` (design system); use tokens only |

## Contract (from 21-1 and 21-2)

**Invite response** (`POST /auth/invite`, 201): adds `sms_status: "sent" | "failed" | "not_configured"`.

**Resend** (`POST /auth/invite/:membershipUserId/resend-sms`):
- `201` `{ sms_status }`
- `403` `NOT_COMPANY_ADMIN`
- `404` `INVITE_NOT_FOUND`
- `409` `INVITE_NOT_PENDING`
- `429` `INVITE_SMS_LIMIT_REACHED`

The app branches on `error_code` only, never on `message`.

## Behaviour

**Status line after an invite** (driven by `sms_status`):

| `sms_status` | Owner sees |
|---|---|
| `sent` | Nothing extra. |
| `failed` | "SMS not sent. Tap Resend to try again." |
| `not_configured` | "SMS sending is not switched on yet." (only while the backend is in placeholder mode) |

**Resend button:**
- Shown only to a company admin. Employees and viewers never see it. (The server still enforces this; the app check is only a convenience.)
- Shown when `sms_status` is `failed`, and also from the invited person's row later, so a missed SMS can be resent without re-inviting. (Confirm the row location with the owner in dev.)
- While the call is in flight: spinner in the button, button disabled, label still readable.
- On success: status becomes `sent`; the line disappears.
- On `429 INVITE_SMS_LIMIT_REACHED`: "This person has already received 5 invite SMS in the last hour. Try again later." The button is disabled, with that reason beside it.
- On `403`: the button is not shown (should not happen; if it does, show "Only a company admin can resend this SMS.").
- On `404` or `409`: "This invite can no longer be resent." (Use the plain-English text in the mapper.)
- On a network error or timeout: "Could not send the SMS. Check your connection and try again." Keep the button enabled.
- Unknown code: "Could not send the SMS. Try again."

## Acceptance criteria

1. **Status line** appears for `failed` and `not_configured`, and not for `sent`.
2. **Resend** is shown only to company admins (checked against the current user's role).
3. **Loading state** on the Resend button, disabled while in flight, with a readable label.
4. **Cap message** on `429`, with the button disabled and the reason shown in plain English.
5. **Error mapping** uses the repo's existing mapper. No screen shows `error.message` or a raw code.
6. **Success** updates the status and hides the message.
7. **Copy** is plain English, sentence case. Role words: "Employee", "Admin", "Viewer". Never "Technician".
8. **No company-name warning.** The company name is trimmed silently in the SMS (CAP-5). The invite form is unchanged.
9. **No full phone number** on screen. Use the name, or the masked number if the screen already shows one.
10. **Accessibility.** Resend has the button role and a clear label. The status line is announced to screen readers when it appears. Tap targets meet the minimum size used by the design system.
11. **Responsive.** Works at 360, 390, 768 and 1280 px.
12. **Correct the stale comment.** Update the comment in `technicians.ts` so it describes the real behaviour: the endpoint returns `sms_status`.

## Out of scope

- Any change to the invite form fields.
- A company-name length warning.
- Attendance, leave or onboarding screens.
- The privacy policy.

## Constraints

- Follow the `fenzit-app` standards: design-system tokens only, atomic components, tiered state (server data from the service layer, UI state local), explicit loading, error and empty states.
- Every request has a timeout.
- The resend call uses the existing authenticated client. No secret or service key in the app.
- Read the repo's `CLAUDE.md` and its standards file before writing code.
- Run the app tests with `bun run test`, not bare `bun test` (RN Flow types break under bare `bun test`).

## Tests (write after the owner confirms the behaviour)

Name the intended tests now:

- Status matrix: `sent` (no line), `failed` (line + button), `not_configured` (line, no button), and an unknown value (no line).
- Role gating: company admin sees Resend; employee and viewer do not.
- Cap: `429` shows the cap message and the button is disabled.
- Error mapping: known codes, an unknown code, and a missing error body.
- Loading: disabled during the call; re-enabled after a failure.
- Network timeout: the message appears; the button is enabled again.
- Masking: no full phone number is rendered.
- Accessibility: correct role and label; the status line is a live region.

## Device check

Once the owner confirms the behaviour, run a device pass on the Pixel 6 (uiautomator2, per the platform notes): invite as admin, see `failed` status, resend, see `429` after the cap. Record the result in the dev notes.

## Done when

- The owner has confirmed the behaviour on the Pixel 6.
- The tests above are written and pass, and `bun run test` is clean.
- `/bmad-code-review` has run and its findings are triaged.
- The owner has agreed to the commit. The commit lands in `fenzit-app` only. Nothing is pushed without consent.
