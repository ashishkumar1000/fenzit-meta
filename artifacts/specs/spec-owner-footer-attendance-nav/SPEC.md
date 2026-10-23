---
id: SPEC-owner-footer-attendance-nav
companions:
  - nav-map.md
sources:
  - ../../planning-artifacts/epics-attendance-leave.md
---

> **Canonical contract.** This SPEC and the files in `companions:` are the complete, preservation-validated contract for what to build, test, and validate. Source documents listed in frontmatter are for traceability — consult them only if you need narrative rationale or prose color this contract intentionally omits.

# Owner footer restructure — Attendance tab replaces Customers

## Why

**A pain to solve + an opportunity.** Attendance is the owner's daily ritual — who's in, who's on leave, who's late — yet it currently sits three taps deep (Account → Attendance → tile). Customers, by contrast, is consulted occasionally and already has a second entry point on the Account tab. Promoting Attendance to a first-class footer tab puts the daily answer one tap away, and the freed slot restructures the footer to Home, Jobs, Attendance, Account — while every attendance setup and management surface keeps its existing home.

## Capabilities

- **CAP-1 — Four-item footer**
  - **intent:** The owner's bottom tab bar shows exactly Home, Jobs, Attendance, Account, in that order; Customers is no longer an owner tab.
  - **success:** The tab bar renders four items; tapping Attendance shows the attendance page; MainTabs registers no Customers tab and the app renders no orphaned or empty tab state anywhere.

- **CAP-2 — Attendance tab page**
  - **intent:** The Attendance tab opens a page with three tiles — Today, Monthly, Leave — opening the existing AttendanceDashboard, AttendanceMonthly, and OwnerLeave screens.
  - **success:** Tiles navigate to the existing screens unchanged; the Leave tile is hidden for view-only users, who see Today and Monthly only — visibility identical to the old hub.

- **CAP-3 — Setup banner, not a redirect**
  - **intent:** When the owner's attendance setup is incomplete, the tab page shows a prominent "finish setting up attendance" banner that opens the setup wizard — the page itself never auto-redirects.
  - **success:** An incomplete-setup owner sees the page with the banner; the banner opens AttendanceSetupWizard; it disappears once `setupCompletedAt` is set; view-only users never see it; a failed setup fetch never redirects, blocks the page, or shows the banner.

- **CAP-4 — Customers stays reachable**
  - **intent:** The Account tab's Customers row opens the Customers list as a stacked screen on the root stack.
  - **success:** Account → Customers opens the full list; tapping a customer opens detail as today; the new-job customer picker and every other customer flow behave exactly as before.

- **CAP-5 — Setup-only attendance hub**
  - **intent:** Account → Attendance keeps the wizard focus-gate and shows only the setup surfaces — Offices, Team attendance, Weekly off, Holidays — with no section eyebrow (owner decision 2026-10-23: every tile there IS setup); Today/Monthly/Leave no longer appear there.
  - **success:** The row stays visible to every role and opens the four setup tiles (owner); on first entry with incomplete setup the existing gate still replaces into the wizard; a view-only user sees the existing view-only notice with no tiles; no Today/Monthly/Leave tiles and no "Set up"/"Every day" eyebrow renders on the hub.

- **CAP-6 — Home screen attendance entries**
  - **intent:** The Home today-pulse card opens the Today dashboard and the plain Attendance tile opens the Attendance tab page; neither lands on the setup-only hub.
  - **success:** Pulse-card tap → AttendanceDashboard; plain-tile tap → the Attendance tab; the plain tile's subtitle no longer promises setup surfaces; Home's tests pin the new targets.

## Constraints

- **Nav-level change only:** reuse the existing screens and routes (AttendanceDashboard, AttendanceMonthly, OwnerLeave, AttendanceSetupWizard, offices/enrolments/weekly-off/holidays, CustomersScreen); no screen rewrites, no backend or fenzit-web changes.
- **Shared TabBar:** the tab bar also serves TechnicianTabs and keys icons by route name; the owner Attendance tab must not disturb technician rendering (the `Attendance → CalendarCheck` mapping already exists).
- **Route keys:** `More` keeps its internal key with the "Account" label (existing convention); the new tab key is `Attendance` in `MainTabParamList`; a stacked `Customers` route joins `RootStackParamList` and every `navigate('Customers')` reference is updated to land on it.
- **Hub gate intact:** the focus gate (GET `/attendance/setup` → replace into the wizard while `setupCompletedAt` is null, owner-only, never on fetch failure) keeps working unchanged from the Account row.
- **Viewer visibility preserved:** `canWrite` continues to gate the Leave tile and all setup surfaces on both the new tab page and the hub.

## Non-goals

- No change to the technician app — TechnicianTabs already carries its own conditional Attendance tab.
- No redesign of the Dashboard, Monthly, or Leave screens; they open exactly as today.
- No change to Notifications, Reports, Technicians rows, or the account card on the Account tab.
- No embedded attendance content on the tab page (tiles only — decided 2026-10-23).
- No backend, deep-link scheme, or fenzit-web changes.

## Success signal

An owner opens the app, sees Home / Jobs / Attendance / Account, and reaches "who's in, who's not" in one tap instead of three. An owner who never finished attendance setup taps Attendance, sees the page with a setup banner, and completes the wizard from there. A view-only user gets Today and Monthly from the tab with no Leave or setup surfaces. Customers remain two taps away via Account, and a technician's footer is pixel-identical to before.

## Decisions of record (2026-10-23)

Tiles over embedded sections · setup banner over wizard redirect · Customers via Account row · setup-only hub with gate kept · hub row visible to every role (view-only users see only the view-only notice).
