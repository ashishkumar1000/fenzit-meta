---
id: SPEC-invite-sms-download-link
companions: []
sources: []
---

> **Canonical contract.** This SPEC is the complete contract for what to build, test and validate. The `.memlog.md` in this folder is the decision record it was distilled from.

# Invite SMS with download link

## Why

When an owner or admin invites someone, the invited person has no way to get the app. Today the invite is saved, but no SMS goes out. This spec adds an automatic SMS with one link, `https://fenzit.com/app/download`, which sends Android users to Google Play and shows iPhone users a coming-soon message until iOS launches. The invited person then logs in with their own phone number and OTP, and the app finds the invite by that number.

## Capabilities

- **CAP-1 — Automatic invite SMS.**
  - **intent:** When someone is invited, one SMS goes to their phone with their first name, the company name, their role word and the download link.
  - **success:** Creating an invite as an owner, company admin or viewer sends one SMS to the invited number. The text matches the approved template, with the role word Employee, Admin or Viewer. The invite is saved even if the SMS fails.
- **CAP-2 — Resend with a rate cap.**
  - **intent:** A company admin can send the invite SMS again when it was not received or failed. The cap stops one phone number from receiving too many SMS.
  - **success:** Only a company admin sees and can use the Resend action. Each phone number can receive at most 5 invite SMS within any rolling one-hour window. A re-invite of the same phone counts against the same 5. A further attempt is refused with a clear message, and no SMS is sent.
- **CAP-3 — Download page routing.**
  - **intent:** The person taps the link and lands on the right store for their phone.
  - **success:** On Android, the page sends the person to the Google Play listing for `com.fenzit`. On iPhone, it shows "The iPhone app is coming soon" and no store button. On a desktop, it shows the Play button and the iPhone coming-soon line.
- **CAP-4 — Greeting name fits one SMS.**
  - **intent:** The first name in the SMS is short, plain English, and never pushes the message past one SMS.
  - **success:** The greeting name is the first word only, cut to at most 12 characters. Devanagari letters (Hindi, Marathi) are converted to English letters using a small custom table in fenzit-be. Any other non-English script, or an empty result, becomes "there".
- **CAP-5 — Company name fits one SMS.**
  - **intent:** The company name in the SMS never pushes the message past one SMS.
  - **success:** A company name longer than 20 characters is trimmed to 20 characters in the SMS. The invite form shows no warning.
- **CAP-6 — Audit trail of invite SMS.**
  - **intent:** Each invite SMS is recorded so the rate cap can be enforced and the owner team can check what was sent.
  - **success:** Every send attempt is logged in the audit record with a masked phone number (for example +91 ******3210), time and outcome (sent, failed, or refused by the cap). The audit record never holds the full number or the hash. The cap counts from a keyed hash of the full number, held only in a separate counting row that is deleted 24 hours after it is created. Masked numbers are never used for counting, because two different numbers could share a masked form.

## Constraints

- **SMS template is locked after DLT approval.** One template covers all roles:
  `Hi {var1}, you are added to {var2} as {var3}. Get the app at fenzit.com/app/download and log in with this number. - Fenzit Technology`
  Var1 is the employee's first name (max 12 characters after CAP-4). Var2 is the company name (max 20 characters after CAP-5). Var3 is the role word: `Employee`, `Admin` or `Viewer`. The role word is never `Technician`. The template has 3 variables, the DLT maximum.
- **Role word mapping.** employee → Employee; company_admin → Admin; viewer → Viewer.
- **Template ID is a placeholder until approval.** The backend holds a clearly marked placeholder constant for the DLT template ID. SMS sending stays switched off until the real approved ID is set.
- **One SMS only.** The rendered message must fit in 160 characters. Worst case with the longest variables is about 155 characters, which fits. Any non-English letter in the message would switch the message to a 70-character limit, so the name rule must output English letters only.
- **The invite is never rolled back by SMS failure.** The owner sees "SMS not sent" and a company admin can tap Resend.
- **The name rule lives in fenzit-be.** Clients never build SMS text.
- **Copy never uses "Technician".** Applies to the SMS, the role word and the download page.
- **Cross-repo order.** fenzit-be ships first (additive: a new SMS step, a new Resend endpoint and the audit log). The fenzit-web download page is deployed before the SMS feature is switched on, so the link never leads to a 404. The fenzit-app owner screen ships last.
- **No new login steps.** The SMS carries no token. The invite is matched by phone number at OTP login, which already happens.
- **Phone numbers are masked in logs.** Application logs and the audit view show only the masked form. The full number is never logged. The keyed hash used for counting is stored, not the raw number, and the hash key lives in backend secrets, not in code. Retention, both counted from when the record is created: audit records (masked number, time, outcome) are deleted after 12 months; counting rows (keyed hash, time) are deleted after 24 hours. The privacy policy and the Play Data safety form state these periods.

## Non-goals

- No invite token or one-tap "already invited" link.
- No iOS store link while iOS is not live. The placeholder is a config-driven page section.
- No WhatsApp or email invite.
- No change to the OTP login flow.
- No automatic reminders. Resend is manual.
- No external transliteration library. Only the Devanagari table is built.

## Success signal

A new employee invited from the owner app receives one SMS on their phone that names the right role. Tapping the link on an Android phone opens the Play listing. Tapping it on an iPhone shows the coming-soon message. A name longer than 12 characters, or a name in Hindi, still produces one SMS. A company name longer than 20 characters still produces one SMS. The sixth invite SMS to the same phone inside one hour is refused, including after a re-invite. A viewer or employee cannot see or use Resend.

## Assumptions

- The Play Store listing `com.fenzit` is live and valid (`fenzit-web/src/config/appStores.ts`).
- `fenzit.com` is served by fenzit-web, which already hosts `/privacy-policy` and `/terms`.
- The owner role is a company admin for the purpose of Resend and for the role word `Admin`. Confirm this in the build, since the membership role enum is the source of truth.
- The MSG91 SMS provider and the `SmsDeliveryProvider` port already exist and are used for OTP.

## Open questions

- **DLT template approval.** The single template with a role variable needs one DLT approval. Submitted by the owner; approval pending (as of 2026-11-11). The placeholder stays and SMS sending stays off until the approved ID is set.
- **Owner role mapping. Resolved 2026-11-11 (owner confirmed).** The company owner is stored as `company_admin`, so the role word is `Admin` and Resend is available to the owner. Super admin is Fenzit staff, stored as `users.platform_admin = true` (checked in DB 2026-11-11 for hello@fenzit.com, which has no membership row) and is not a company membership role; it is never an invitable role and never gets the role word.
- **Cap decisions (2026-11-11, owner).** (1) A provider timeout counts toward the 5-per-hour cap, because the SMS may have been delivered. (2) A capped invite returns `sms_status: refused_cap`, a new value alongside `sent`, `failed` and `not_configured`, so the owner app can explain the limit. (3) The cap covers every invite, re-invite and resend for a phone. (4) A slot is reserved before the send, so parallel sends cannot pass the cap; a crash between reserve and send keeps the slot until the 24-hour cleanup.
- **SMS text decisions (2026-11-11, owner).** (5) A company name in Devanagari is transliterated with the same table as names; any other non-English company name becomes "your company". (6) A person name with any character outside plain English letters (after Devanagari conversion) falls back to "there".
