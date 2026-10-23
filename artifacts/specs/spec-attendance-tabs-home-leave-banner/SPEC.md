---
id: SPEC-attendance-tabs-home-leave-banner
companions:
  - ui-map.md
sources:
  - ../../specs/spec-owner-footer-attendance-nav/SPEC.md
---

> **Canonical contract.** This SPEC and the files in `companions:` are the complete, preservation-validated contract for what to build, test, and validate. Source documents listed in frontmatter are for traceability — consult them only if you need narrative rationale or prose color this contract intentionally omits.

# Attendance page as three tabs; Home leave-review banner

## Why

**A pain to solve.** The Attendance tab page (shipped today as three tiles opening pushed screens) makes the owner's daily ritual — "who's in, who's not, who's on leave" — a two-tap drill on every visit, and pending leave decisions surface only as a thin pointer row on Home. The owner wants the three attendance reads one switch away on the page itself (mockup: a segmented Today | Monthly | Leave control, Today active), a visible badge when leave decisions are waiting, and a proper Home banner — "N leave requests / Action pending approval" with a Review button — that says action is pending and lands on the Leave tab in one tap.

## Capabilities

- **CAP-1 — Tabbed attendance page**
  - **intent:** The Attendance tab page renders Today, Monthly, and Leave as three switchable tabs in a segmented control, Today active on entry, replacing the three tiles.
  - **success:** The page opens with Today selected and the Today dashboard beneath; tapping Monthly or Leave swaps the content in place with no navigation push; no tiles render; the page can be opened with Leave pre-selected (the Review target); the three leaf screens still open unchanged when pushed from Home's pulse card and every other existing entry.

- **CAP-3 — Leave tab pending badge**
  - **intent:** The Leave tab carries a badge showing how many leave requests are pending.
  - **success:** The badge equals the mirror's `pendingLeaveRequests` when > 0, is absent at 0, and disappears with the Leave tab itself for viewers; the count refreshes on focus per the attendance focus-refetch contract.

- **CAP-4 — Home leave-review banner**
  - **intent:** Home shows an "N leave requests / Action pending approval" banner with a Review action while requests are pending, replacing the shipped LeaveReviewStrip visual; Review lands on the Attendance tab with Leave pre-selected.
  - **success:** Admin + attendance-enabled + N > 0 renders the banner with the mirror count; Review switches to the Attendance tab showing the Leave tab; N = 0, a non-admin, or an absent mirror renders nothing.

*(CAP-2 — "settings while setup is incomplete" — was retired by the owner mid-run on 2026-10-23: the shipped setup-banner behaviour stands; the ID is never reused.)*

## Constraints

- **App-only:** no fenzit-be change — the count already rides the owner `/users/me` mirror (`attendance.pendingLeaveRequests`, story 20-1); no new endpoint, request, or migration.
- **Dual-hosting:** `AttendanceDashboard`, `AttendanceMonthly`, `OwnerLeave` remain pushed root-stack screens while also embedding as tab panes; headers, back behaviour, and SafeArea must hold in both hosts (see [ui-map.md](ui-map.md)).
- **Setup banner stands:** the shipped incomplete-setup behaviour — the "Finish setting up attendance" banner above the tabs, one light `GET /attendance/setup` per focus, latest-wins, owner-only, silent on failure — carries over unchanged; it now sits above the tabbed content instead of the tiles.
- **Viewer visibility:** `canWrite` continues to gate the Leave tab, badge, and banner; viewers get exactly Today + Monthly.
- **Mockup fidelity:** segmented pill control with calendar glyphs and the count badge on Leave; banner in the leave-hue family with an explicit Review button — the LeaveReviewStrip pointer-row anatomy (20-1 AC 12) is visually superseded inside this story.
- **Standing rules:** design-system tokens only, ~300-line file limit, explicit loading/empty states, attendance focus-refetch contract.

## Non-goals

- No backend, API, or deep-link change.
- No redesign of the Today dashboard, Monthly grid, or Leave list content — they render as-is inside the tabs.
- No change to the setup-incomplete state: the banner behaviour ships as-is today and stays (owner withdrew the "just show settings" direction, 2026-10-23).
- No change to the Account → Attendance setup-only hub, its wizard focus gate, the four-item footer, or Customers access (spec-owner-footer-attendance-nav stands except where superseded — see [ui-map.md](ui-map.md)).
- No technician-side change.
- No Home restructure beyond the banner: the pulse card and plain Attendance tile keep their CAP-6 targets.

## Success signal

An owner with two pending leave requests sees "2 leave requests / Action pending approval" on Home, taps Review, and lands on the Attendance tab's Leave tab — badge showing the same 2 — and decides them without a navigation push; the badge clears as decisions land; an owner who never finished setup still sees the Finish-setting-up banner above the tabs; a viewer still gets exactly Today and Monthly.
