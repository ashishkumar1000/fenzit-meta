---
id: UX-app-roadblocks
status: draft
updated: 2026-11-09
companions: []
sources: []
---

# UX: App roadblocks (force update, subscription expired)

Two roadblocks in fenzit-app, shown as **modals**: a card over the dimmed app. Both are bare: text and one primary action. No navigation, no data, no tabs, no dismiss.

Design tokens come from `workspace/core/frontend/fenzit-app/src/theme` (`colors`, `spacing`, `typography`). No raw hex in code.

## Presentation (modal, decided 2026-11-09)

- **Scrim:** the app stays visible behind a dark overlay. Use an overlay token from the theme. If none exists, add one to the fenzit-app theme first, then sync it. No raw colour in the screen.
- **Card:** centred, max width 360px, full width minus `s6` (24px) on each side. Background `surfaceCard`, radius and soft shadow from the design system.
- **No dismiss:** no close button. Taps on the scrim do nothing. Touches do not reach the app behind the card.
- **Android back:** force update exits the app. Subscription expired does nothing.
- **Log out removed (owner decision, 2026-11-09):** the subscription card has no action. An owner can leave only by closing the app. Open risk: see the Open questions below.
- **Motion:** scrim fades in over 150ms. Card fades and rises 8px over 200ms. With reduce-motion on, both appear at once.
- **Focus:** moves to the card title when the modal opens. Screen readers are told the content behind is hidden (modal on iOS, modal on Android).
- **Scrolling:** the card scrolls inside itself if the text is taller than the screen. The title and button stay in view.

## Shared rules

- **Layout:** one centred card, max width about 360px, padding `s6` (24px). Vertical gap `s4` (16px) between blocks.
- **Background:** card `surfaceCard`, scrim over the app. Text: `textStrong` for titles, `textBody` for messages, `textMuted` for meta lines.
- **Primary button:** `primary` fill, `onPrimary` text. Pressed: `primaryActive`. Disabled: `textDisabled` text on `surfaceSunken`.
- **Secondary button:** text-only, `textLink` colour, minimum touch target 48px.
- **Theme:** the same token names in light and dark. No screen-specific colours.
- **Width:** works at about 400px phone width. Long text wraps; nothing scrolls sideways.
- **Plain English** on every line. No emoji. Indian English.
- **Disabled controls say why** in visible text next to the control.

---

## Screen 1: Force update

**Shown when:** installed app version is below the server minimum for this platform.

### Layout (top to bottom)

1. **Title:** "Update required" (`typography.heading`, `textStrong`, centred).
2. **Message:** the server-supplied text (`typography.body`, `textBody`, centred). Falls back to "Please update the Fenzit app to continue." when the server sends nothing or an empty string.
3. **Version line:** "Installed version: v1.2.3" (`typography.bodySm`, `textMuted`).
4. **Primary button:** "Update app".
5. **Status line** (only when the button is disabled or an error occurs): one line under the button, `textMuted` for "why" text, `danger` for errors.

### Button behaviour

| State | Button | Text under button |
| --- | --- | --- |
| Normal | Enabled | none |
| Store link missing from config | Disabled | "Update link is not set yet. Please try again later." |
| Store app did not open | Enabled | "Could not open the Play Store. Open it yourself and search for Fenzit." (Android) / "Could not open the App Store. Open it yourself and search for Fenzit." (iOS) |

- Android opens the Play Store listing. iOS opens the App Store listing. The URL comes from config, one per platform.
- The button never shows a spinner. Opening the store is instant.

### Long message

- Message wraps fully. No truncation.
- Above about 600 characters, the message area scrolls inside the column. The title and button stay visible.
- Ops should keep messages short. The design does not enforce a hard cap.

### What the user can do

- Tap "Update app" to open the store.
- Nothing else. No dismiss, no back gesture (Android back exits the app), no navigation.

### Accessibility

- Button: `accessibilityLabel="Update app"`, `accessibilityRole="button"`. When disabled, `accessibilityHint` reads the same text as the "why" line.
- Title: `accessibilityRole="header"`.
- Version line: read as one string: "Installed version v1.2.3".
- Focus moves to the title when the screen appears.

---

## Screen 2: Subscription expired

**Shown when:** the company's subscription validity date has passed, and the signed-in user is the company owner. Technicians (Employees) never see this screen; they keep full use of the app.

### Layout (top to bottom)

1. **Title:** "Subscription expired" (`typography.heading`, `textStrong`, centred).
2. **Message:** one line, sets the scene. See copy below.
3. **Expiry line:** "Expired on 8 Nov 2026" (`typography.body`, `textBody`). The date is shown in IST.
4. **Reason line:** says this is the company's account (copy below). `textMuted`.
5. **Support line:** "For help, contact Fenzit support at hello@fenzit.com or +91 92792 30451." Both values come from config (`support_email`, `support_phone`) and are plain text. No tel or mailto link.
6. **Action:** "Log out" (primary button style, `primary` fill, `onPrimary` text). It is the only action.

Log out is the only action, so it uses the primary button style.

### Copy: owner view

- **Title:** Subscription expired
- **Message:** "Your Fenzit subscription has ended. You cannot add or change data until it is renewed."
- **Expiry line:** Expired on 8 Nov 2026
- **Reason line:** "This is your company account."
- **Support:** "For help, contact Fenzit support at hello@fenzit.com or +91 92792 30451." (from config)
- **Button:** Log out

### What the user can do

- Read the message and the expiry date.
- Log out. Nothing else.
- Contact support by reading the email or phone number and typing it into their own mail or phone app. The app does not open mail or dialler.

### Date format

- Format: "8 Nov 2026" (day, short month, year), IST.
- If the server sends no date, drop the expiry line. Do not show "Expired on unknown".

### Accessibility

- Log out: `accessibilityLabel="Log out"`, `accessibilityRole="button"`.
- Title: `accessibilityRole="header"`.
- Expiry line and reason line read in order.
- Focus moves to the title when the screen appears.

---

## Open questions for the owner

3. **Log out and local data:** does log out clear locally cached jobs and photos on the device? If unsent offline work exists, should the screen warn about it? Current draft: no warning. Logout behaviour is open: see SPEC.md Open Questions.
5. **Expired copy wording:** "cannot add or change data" is the draft. Confirm that matches the API behaviour in CAP-2 (writes blocked, reads still allowed).
