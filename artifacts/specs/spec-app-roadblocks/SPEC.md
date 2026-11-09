---
id: SPEC-app-roadblocks
companions:
  - ux-roadblocks.md
sources: []
---

> **Canonical contract.** This SPEC and the files in `companions:` are the complete contract for what to build, test, and validate. Derived from `.memlog.md` (entries 1–51).

# App Roadblocks: Force Update and Subscription Expired

## Why

Two cases stop a user from using the app safely. (1) Old app builds keep calling APIs that have changed, so Fenzit must force an update per platform (Android and iOS) without a new release. (2) Company accounts run out of their 90-day validity, and nothing stops them from carrying on. Fenzit platform staff set the force-update rules from the admin config page. The app shows a full-screen roadblock for each case.

## Capabilities

- **CAP-1 — Subscription expired roadblock (app).** When the company's validity date has passed, the app shows a full-screen roadblock to company owners only. Log out is the only action. Technicians are not blocked.
  - success: an owner of an expired company sees the roadblock on next launch or foreground. An owner of an active company does not. A technician of an expired company sees no roadblock and keeps full use of the app.
- **CAP-2 — Server enforces expiry on owner writes (backend).** Non-GET requests from an owner in an expired company return HTTP 402 with `error_code: SUBSCRIPTION_EXPIRED`. Reads are open. Technicians and platform admins are not blocked.
  - success: an owner's POST, PATCH or DELETE on an expired company returns 402 `SUBSCRIPTION_EXPIRED`. A technician's write on the same company succeeds. An owner's GET succeeds.
- **CAP-3 — New company gets 90 days (backend).** The validity date belongs to the company (`tenants.validity_until`), not to an owner.
  - success: a new company's `validity_until` is exactly 90 days after its creation.
- **CAP-4 — Existing companies backfilled (DB migration).** Companies that exist at migration get migration time + 90 days.
  - success: no existing company is expired on migration day.
- **CAP-5 — Manual extension (backend).** A platform admin sets a company's `validity_until` through a backend endpoint.
  - success: after an extension, the owner's app drops the roadblock on next foreground, and owner writes succeed again, with no app update.
- **CAP-6 — Force update per platform (app and config).** Android and iOS each have their own minimum version, message and store link.
  - success: Android minimum set to 1.5.0 with iOS at 1.2.0 blocks an Android 1.4.0 install and leaves an iOS 1.4.0 install alone.
- **CAP-7 — Roadblock config is server-driven (backend and app).** Both roadblocks read from `app_config`, served by `GET /config/app`.
  - success: a changed value shows on the next launch or foreground, with no app release.
- **CAP-8 — Super admin edits force-update rules (fenzit-web admin).** Only platform admins (`users.platform_admin = true`, the super admin) can open the Config page or write config. Other users get a forbidden page. The page sets per-platform minimum version, store link and message, plus the support contact.
  - success: a super admin saves each platform's values. Any other user sees the forbidden page, and the write endpoint returns 403 for them. Store links must be Play Store or App Store links.

## Constraints

- **Backend ships first.** Changes are additive: new `/users/me` field, new error code, new config keys. Then fenzit-web (admin page), then fenzit-app (roadblock screens). Each repo gets its own commit.
- **Old app binaries ignore unknown fields** and must not break when new config keys appear.
- **Expiry belongs to the company.** One source of truth: `tenants.validity_until`. Owners and technicians read the same date.
- **The backend is the enforcement point.** The app roadblock is UX only. The client is never trusted.
- **Owner-only enforcement.** The 402 guard applies to owner-role writes only. Technicians are fully functional.
- **Fail safe.** If config or `/users/me` cannot be read, the subscription roadblock is not shown. Force update keeps its shipped default (1.0.0) until the server answers.
- **Roadblock screens are bare:** no data, no navigation except log out (subscription) or the store link (force update).
- **Config writes go through the backend** with the admin client, and only super admins may call them. The browser never talks to the database directly.
- **Employee wording.** User-facing copy says "Employee", not "Technician" (see CLAUDE.md Terminology). Internal names stay unchanged.

## Non-goals

- Payment, billing or renewal flow.
- An admin UI for subscription expiry. Extension is a backend endpoint only.
- An admin UI for the whole config store. Only force-update fields, support contact and store links are editable here.
- Grace or hold states after expiry. Expired means `now >= validity_until`.
- Per-user or per-company targeting of force update.
- Server-driven UI.
- Device-clock hardening.
- A reminder banner before expiry.

## Success signal

An owner whose 90 days end opens the app, sees the subscription roadblock, and every write is refused with 402. A technician in the same company keeps working. A platform admin sets a new Android minimum on the config page, and an old Android build shows the force-update screen on its next foreground while iOS builds are untouched.

## Assumptions

- `validity_until` is stored as UTC `timestamptz`. Comparison is by instant. Dates are shown in IST.
- The iOS store URL is a placeholder (`https://apps.apple.com/app/id0000000000`) until the owner supplies the real listing.
- Both platforms ship. iOS force update is switched on once its store URL is real.

## Open Questions

- **Logout and local cache.** The owner said logout does not clear local cache. The existing `useLogOut` already calls `runAllResets()`. Keep the existing behaviour or skip the reset for the roadblock logout? (memlog entry 51)
- **Real iOS store URL.** Owner to supply it.
- **Companies with more than one owner.** The rule is per company, so this is settled by design. Confirm no per-owner date is wanted later.
