---
name: Fenzo — Attendance & Leave
description: Behavioral contract (IA, states, interactions, flows) for the optional Attendance & Leave module — owner setup/oversight and technician check-in/leave. Companion to DESIGN.md, which owns visual identity.
type: feature
status: final
updated: 2026-09-25
product: fenzo-app (owner + technician) · fenzit-be
sources:
  - artifacts/planning-artifacts/prds/prd-Fenzo-attendance-2026-09-25/prd.md
  - artifacts/planning-artifacts/prds/prd-Fenzo-attendance-2026-09-25/addendum.md
  - workspace/core/frontend/fenzo-app/src/theme/DESIGN_SYSTEM.md
  - workspace/core/frontend/fenzo-app/src/navigation/TabBar.tsx (existing 3-tab technician bar)
  - workspace/core/frontend/fenzo-app/src/features/more/MoreScreen.tsx (existing tile/row pattern)
  - workspace/core/frontend/fenzo-app/src/features/notifications (existing shared inbox — Owner-only today; FR-27 requires generalising it to be role-aware, tracked as real build work in addendum §C1/§C2, not a given)
---

# EXPERIENCE.md — Fenzo Attendance & Leave

## Foundation

- **Form factor:** mobile only — React Native, iOS + Android, phone portrait. No tablet/web surface (matches the rest of Fenzit).
- **UI system:** Fenzit Design System. Visual identity reference: [DESIGN.md](DESIGN.md) — this file owns behaviour only.
- **Roles:** Owner (setup, oversight, approvals, corrections) and Employee — an existing `technician`-role user with attendance enabled (glossary: **Tracked employee**). No new role.
- **Day logic:** all "today"/date-boundary logic is computed server-side in the tenant timezone (default `Asia/Kolkata`) — the app only ever displays server-provided local dates/times, 12-hour format. This is a deliberate departure from the job flow's client-side IST util (NFR-5); attendance never does its own timezone maths.
- **Module boundary (NFR-12):** its own entry points, screens, navigation stack and notification event types. Off (or never enabled) leaves the job/field flow exactly as it is today. The only shared surfaces are the design system, the location-permission helper, and the notifications inbox.

## Information Architecture

```
Owner
 ├─ MoreScreen
 │   └─ "Attendance" tile          (before setup → opens wizard; after → Attendance Home)
 ├─ Home
 │   └─ "Attendance today" card    (after setup only — mirrors the Today & needs attention card)
 └─ Attendance Home (Owner)
     ├─ Dashboard (Today)                          FR-24  → mockups/key-owner-dashboard.html
     │   ├─ KPI tiles (Tracked / Checked in / Not checked in / Late / On leave)
     │   ├─ Flags: Checkout missing, Fake location attempt
     │   └─ Office filter
     ├─ Monthly view                               FR-25
     │   ├─ Employee list (month summary per row)  → mockups/key-monthly-employee-list.html
     │   └─ Employee month calendar → Day detail → Correction sheet   FR-21  → mockups/key-month-calendar.html
     ├─ Leave
     │   ├─ Pending queue → Leave detail (Approve / Reject)           FR-13
     │   ├─ All leave history
     │   └─ Apply on behalf                                          FR-16
     ├─ Setup / Settings
     │   ├─ Setup wizard (first run)                                  FR-1  → mockups/key-setup-wizard.html
     │   │   Offices → Timings & hours → Weekly off → Holidays → Employees
     │   ├─ Offices (list → add/edit → map picker)                    FR-5  → mockups/key-office-map-picker.html
     │   ├─ Employees (enable/disable, office assignment, start date, reassignment)  FR-2, FR-6
     │   ├─ Weekly off (tenant default + per-employee override, effective-dated)  FR-18, FR-19  → mockups/key-weekly-off-holidays.html
     │   └─ Holidays (add/edit/remove, overlap warning)               FR-20  → mockups/key-weekly-off-holidays.html
     └─ (shared) Notifications bell — existing screen, unchanged position

Employee (Tracked)
 ├─ Tab bar gains a 4th tab: "Attendance"    (shown for upcoming / active / history_only; hidden for `none`)
 └─ Attendance tab
     ├─ Onboarding (first entry only)         FR-4  — summary also reachable later via a "My Office" row under Today
     ├─ Upcoming-state screen                 FR-3 ("Attendance starts on {date}")
     ├─ Today (active state)                  FR-7, FR-8 — check-in/out  → mockups/key-checkin.html
     ├─ My calendar (own month view, read-only in history_only state)   FR-26
     ├─ My leave (apply, history)             FR-12, FR-17  → mockups/key-leave-apply.html
     └─ (shared) Notifications bell — same tab-bar bell as today, now also carries attendance/leave events
```

- Owner entry points exist from day one (before setup, the tile opens the wizard instead of a dashboard) — matches FR-3 ("Owner always sees the entry point").
- The technician tab only appears once `attendanceAccess !== 'none'`; an employee who has never been enabled sees no 4th tab and no attendance UI anywhere, per FR-3.
- The bell/badge in the tab bar is visible to **every** technician regardless of attendance access (FR-27) — it is not part of the conditional Attendance tab; it is the existing, always-present notifications entry point.
- **Naming collision to avoid:** the existing technician tab bar already has a tab labelled "Today" (today's scheduled jobs — unchanged by this module) and a tab labelled "History" (job history — unchanged). The new Attendance tab has its own internal "Today" screen (check-in/out) and "My calendar" screen. These are four different surfaces that happen to share two names. To keep a builder from merging or confusing them: the job tabs keep their exact current labels and icons; the Attendance tab's internal screens are never exposed as sibling tab-bar items, and the Attendance tab's own screen header always says "Attendance," never bare "Today," so the app bar text disambiguates even when the tab icon alone might not.

## Voice and Tone

Calm, factual, sentence case, no emoji — the app's established voice (same posture as the other two UX passes in this app). Attendance is a trust-sensitive surface (it decides who's marked absent), so copy is exact and never vague. Copy below is quoted directly from the PRD where the PRD specifies exact wording — this module doesn't rephrase it.

| Surface | Copy |
|---|---|
| Too far to check in | "You are {distance} m from {office} office. Move within {radius} m to check in." |
| Low GPS accuracy | "Location not accurate enough, try again in the open." |
| Fake GPS detected | "Turn off fake location apps to check in." |
| Rate limited | (clear message per FR-7; exact copy at build time) — "Too many attempts. Try again in 10 minutes." [ASSUMPTION] |
| Check-in on a leave day | "You're on leave today. Checking in will cancel today's leave. Continue?" |
| Check-in on a holiday/weekly off | "It's a holiday. Check in anyway?" |
| Missed-checkout reminder | "You haven't checked out" |
| Missed-checkin reminder (FR-23) | "You haven't checked in" |
| Owner daily not-checked-in summary (per Office, FR-23) | "{n} employees haven't checked in at {office}" |
| Owner daily pending-leave summary (FR-23) | "{n} leave requests waiting for your approval" [ASSUMPTION exact count phrasing] |
| Precise location off (Android "Approximate" / iOS "Precise off") | "Turn on precise location to check in" — distinct from the permission-denied state below, per addendum §C2 |
| Location permission denied / never granted | "Attendance needs your location to check in and out. You can still view your records and apply for leave without it." with a "Turn on location" action that deep-links to OS Settings when the OS won't re-prompt in-app |
| Holiday added over an employee's approved leave (Owner-side warning, before confirming) | "This date overlaps {employee}'s approved leave. It will no longer count as leave for them." |
| Holiday added over approved leave (Employee notification, FR-22) | "{date} is now a holiday — it no longer counts against your leave" |
| Holiday removed inside a leave range (Employee notification, FR-20/FR-22) | "{date} is Leave again — the holiday covering it was removed" |
| Leave dates already off | "These days are already off" |
| Leave overlaps an existing request (FR-12) | "You already have a leave request covering one of these dates" |
| Leave past-date limit exceeded (FR-12, 7-day limit) | "You can only apply for leave up to 7 days in the past" |
| Leave requested before start date (FR-12, upcoming employee) | "You can only apply for leave from {startDate} onward" |
| Leave date already has a check-in (FR-12) | "You already checked in on {date}, so it can't be requested as leave" |
| Employee cancels leave (confirmation, FR-15) | "Cancel this leave request?" with the same split-outcome wording as Revoke when part of it has already started |
| Upcoming access state | "Attendance starts on {date}" |
| Leave rejected with no reason | Employee sees "Rejected" with no reason line (reason is optional on reject) |
| Leave revoked | "Revoked ({dates}): {reason}" |
| Empty notifications (untracked technician) | "No notifications yet" (existing EmptyState copy, unchanged) |

## Component Patterns

Visual specs for every component named below live in DESIGN.md → Components. This section covers only behaviour.

### CheckInOutButton
- Exactly one enabled action at a time: "Check in" before today's check-in exists, "Check out" after (and before checkout), nothing (replaced by a summary) after checkout. Never both visible.
- **Pre-flight check (before any GPS fix is requested):** the button press first checks today's already-known Day status, not location.
  - Full-day Approved or Pending leave today → show "You're on leave today. Checking in will cancel today's leave. Continue?" On confirm, proceed to the GPS/submit step below; the server auto-cancels that date's leave (FR-9) and notifies the Owner. On dismiss, no request is sent at all.
  - Half-day leave today → **no dialog** — FR-9's explicit exception; proceed straight to the GPS/submit step, since checking in on the working half never cancels anything.
  - Weekly off or Holiday today (no leave involved) → show "It's a holiday. Check in anyway?" On confirm, proceed to GPS/submit (the day becomes Worked on holiday if it succeeds); on dismiss, no request is sent.
  - Otherwise (normal working day) → proceed straight to the GPS/submit step, no dialog.
- **GPS/submit step:** request a **fresh** high-accuracy GPS fix (never a cached one, per addendum §C2 location-capture contract) → submit with an idempotency key → server decides. The button is disabled and shows a spinner for the whole round-trip, including the GPS fix itself; it never optimistically shows "Checked in" before the server confirms (NFR-2: server authority — the UI must not get ahead of it).
- **States, distinct from each other (not folded into one "Blocked" state):**
  - *Too far / low accuracy / fake GPS* — returns to Ready with the exact PRD-specified message shown below the button. Retry is immediate.
  - *Rate limited* (5 rejections in 10 min, FR-7) — returns to Ready but the button itself is disabled with a visible countdown ("Try again in 9:42") for the remainder of the 10-minute window, not just a message the employee could ignore by mashing the button again.
  - *GPS fix timeout* (NFR-8) — its own message ("Couldn't get your location. Move to an open area and try again."), distinct from low-accuracy, since no fix was obtained at all versus a fix that was obtained but rejected.
  - *Precise location off* (Android "Approximate" / iOS "Precise off", addendum §C2) — its own state, "Turn on precise location to check in" — not folded into "permission not granted," since the permission is technically granted here.
  - *Location permission never granted / denied* — the button shows "Turn on location to check in"; tapping it opens the permission flow, not a rejected attempt (FR-4 — records/leave still browsable without this permission). If the OS won't re-prompt in-app (already denied once), the same state's action deep-links to OS Settings instead of firing a doomed in-app prompt.

### Office map picker
- Three entry paths to the same map screen (current location / address search / drag pin), per FR-5. Whichever path is used, the **final pin position on the map** is what's saved — a search result is a starting point for the pin, never the saved value itself.
- The radius circle redraws live as the radius value changes; there is no separate "preview" step.
- Map-unavailable fallback: current-location and address-search still work; the map area shows a plain message instead of freezing or erroring silently.

### MonthCalendar
- One cell per calendar date; only Working days for that employee carry a meaningful status glyph — non-tracked dates before the start date, or after disabling, render as the neutral "Not tracked" glyph, not blank (a blank cell would read as a bug, not a state).
- Tapping any cell — including a future date — opens Day Detail. Future dates simply show the day's known state (Weekly off, Holiday, or a Leave request already Approved/Pending) with no check-in data yet.
- Today's cell carries the `primary` outline treatment regardless of its status glyph.
- **Day Detail sheet fields (FR-25):** StatusBadge with label, Check-in/Check-out times, Worked hours, **distance from the office pin at check-in/check-out**, flags (Late/Early/fake-location), leave info if applicable, and — if the date carries more than one Attendance correction over time — an expandable "Correction history" row listing each one (who, when, old value, new value, note), not only the most recent (FR-21's audit-trail visibility requirement covers the full history, not just the latest edit).

### StatusBadge & Flag tag (behaviour)
- Neither is interactive on its own — tapping a StatusBadge or Flag tag never does anything; the tap target is always the containing row/cell, not the badge itself. This keeps the badge a read-only indicator, consistent everywhere it appears (calendar cells, Day Detail, monthly list rows, Dashboard flag strips).
- Screen-reader announcement is centralised here (see Accessibility Floor for the exact phrasing pattern) rather than repeated per screen, so a StatusBadge announces identically wherever it's rendered.

### Dashboard KPI tiles & Flags strip
- The KPI tiles (Tracked / Checked in / Not checked in / Late / On leave / Absent) are informational only — tapping a tile does nothing; they summarise, they don't filter. Employees whose start date hasn't arrived yet are excluded from every tile's count (an upcoming employee is neither "Tracked" nor "Not checked in" today — they simply don't exist yet from the dashboard's point of view, matching FR-2's "doesn't appear in the Owner's not-checked-in summaries" rule).
- The Flags strip rows (Checkout missing, Fake location attempt) **are** tappable — each row navigates to a filtered list of the affected employee-dates, which is the one piece of "todo" navigation on this screen, distinct from the read-only tiles above it.

### Setup wizard
- Five steps, forward-only navigation with a back option that doesn't lose entered data. Each step's data is persisted to the server as it's completed (FR-1) — closing the app mid-wizard and reopening resumes exactly where it left off, on any device.
- The wizard cannot be finished (final "Enable attendance" action stays disabled) until at least one Office exists and at least one Employee is both selected and assigned to an Office — enforced in the UI before the submit call is even attempted, matching the server-side rule 1:1 so there's never a submit-then-fail round trip for this specific case.
- "Skip for now" on Holidays is the only skippable step; every other step requires at least one entry to proceed.

### Enrolment rows (bulk enable/disable)
- Toggling a switch to "on" without an assigned Office does not silently fail — it opens the office-assignment picker inline for that row immediately, and the switch itself doesn't visually commit to "on" until an Office is chosen (prevents the exact edge case UJ-1 calls out: enabling an employee without an office). This is a hard rule for the mockup too — a screen showing the switch already "on" while an office is still unpicked is a mockup bug, not an alternate valid state.
- The start-date field defaults to today; picking a future date is one tap away (a small "Starts today" link that expands to a date picker), not a separate screen — this is the flow that answers "can the owner set up a new joiner before day one" (yes, per FR-2, resolved during PRD review).
- **Enabled today, after today's Start time (FR-2 edge case):** no special dialog or warning is shown — the row simply enables as normal. The only consequence, handled entirely server-side and reflected passively wherever data is shown, is that today renders as "Not tracked" everywhere (Dashboard tiles, calendar) unless the employee actually checks in today, in which case it's evaluated normally. Nothing in the UI needs to explain this to the Owner at enable-time; it just needs to not misrepresent today's state anywhere it's shown.

### Office reassignment (FR-6)
- Reached from an Employee's row in Settings → Employees: a "Change office" action opens the same office-picker used in Enrolment rows, plus an effective-date field (default today, or a future date — same date-field pattern as the start-date field above).
- If the Employee has already checked in today, the effective-date field is pre-filled to tomorrow and today's date option is disabled with an inline note: "Already checked in today — this takes effect from tomorrow" (FR-6).
- Past attendance records are never touched by a reassignment; only the calendar/monthly views for dates on or after the effective date show the new Office.

### Office archive (FR-5)
- An "Archive" action on the Office detail screen. If any currently-Tracked employee is assigned to that Office (Removed employees don't count, per FR-28), the action is blocked with an inline message ("{n} employees are still assigned here — reassign them first") and a shortcut into the Employees list filtered to that Office, rather than a dead-end error.
- Once unblocked (zero non-removed employees assigned), Archive succeeds immediately with no further confirmation beyond the standard destructive-action pattern the app already uses elsewhere.

### Weekly off settings (FR-18, FR-19)
- Tenant-default screen: a 7-day picker (see Accessibility Floor for the label-disambiguation requirement) plus an effective-date field (default today, any future date) — mirroring the Office-timing-change pattern ("changes apply from the date you pick; past dates keep the old rule"). The screen blocks saving a selection that leaves zero working days in the week (FR-18).
- Per-employee override list: each override row has its own effective-date field on create, and an explicit "Remove override" action (not just an edit) that reverts that employee to the tenant default from a chosen effective date — the override doesn't just disappear, it ends on a date, consistent with every other effective-dated rule in this module.

### Holidays settings (FR-20)
- Add/edit screen: date + name, no recurrence, no preset list (out of scope). Before an Owner confirms adding or removing a holiday that falls inside any Tracked employee's Approved leave range, an inline warning appears naming the affected employee(s): "This date overlaps {employee}'s approved leave. It will no longer count as leave for them." (adding) or the equivalent removal-side notice. The Owner can still proceed — this is information, not a hard block — and the affected Employee(s) receive the FR-20/FR-22 notification the moment the change is saved.
- The upcoming/past split shown in the list (per the mockup) is purely a display grouping; there's no separate "past holidays" management action since past holidays can still be edited/removed per FR-20's "past dates can be added or removed" rule.

### Revoke sheet (Owner, FR-14)
- Reached from a Leave detail (Approved request) via a "Revoke" action. Requires a reason (blocks the confirm button until filled — same required-field pattern as Correction).
- **Before confirming**, the sheet shows exactly which dates will be revoked versus which stay Approved, computed from today's date (e.g. "Mon–Wed stay Approved (already started or past) · Thu–Fri will be revoked") — the split outcome (FR-14) is shown to the Owner at the moment of the decision, not only narrated to the Employee afterward.
- Today can be included in the revoked set only if the action is confirmed before the Office's Start time; once past Start time, today is locked into the "stays Approved" group and the sheet's copy reflects that automatically (no separate error — the date simply appears in the correct group).
- On confirm: the Employee receives the FR-22 notification with the same dates-and-reason wording already in the Voice and Tone table.

### Cancel (Employee, FR-15)
- Reached from a Leave-history row (Pending or Approved request) via a "Cancel" action.
- Pending, or Approved-and-not-started: a single confirm dialog ("Cancel this leave request?") — on confirm, the whole request is Cancelled, no reason required (matches FR-15; Cancel, unlike Revoke, needs no reason since it's the Employee's own request).
- Approved-and-in-progress: the same dialog additionally shows the split outcome, mirroring the Revoke sheet's presentation ("Mon–Wed stay Approved · Thu–Fri will be cancelled"), so the Employee sees the same clarity the Owner gets on Revoke.
- Today follows the same Start-time cut-off as Revoke (FR-15 references the FR-14 cut-off).
- On confirm: the Owner receives the FR-22 "Leave cancelled by Employee" notification.

### Leave apply form
- The working-day count recalculates live as dates change, before submission — the employee always sees "X working days" before committing, never after.
- Five rejection cases (FR-12), all handled the same way — surfaced inline on Submit, never by pre-disabling the button (the range might mix valid and invalid dates, so disabling early would be wrong more often than it's right):
  1. Every date already off → "These days are already off"
  2. Range overlaps a Pending/Approved request → "You already have a leave request covering one of these dates"
  3. A date is more than 7 days in the past → "You can only apply for leave up to 7 days in the past"
  4. A date is before the employee's own start date (upcoming employees) → "You can only apply for leave from {startDate} onward"
  5. A past date already has a Check-in → "You already checked in on {date}, so it can't be requested as leave"
- Half-day options (First half / Second half) only appear once exactly one date is selected; selecting a second date hides them and silently reverts to full-day (with a brief inline note, not a silent surprise).

### Pending leave queue → detail sheet
- Approve is a single tap with no confirmation (matches UJ-3's "in a tap" framing from the PRD vision). Reject requires the sheet to stay open long enough to optionally type a reason, but does not require typing one — "Reject" with an empty reason field is valid.
- Two owners cannot both act on the same request: if the request is no longer Pending by the time an action is confirmed (already handled elsewhere, e.g. two admin sessions), the sheet shows "This request was already handled" and closes — never a silent double-apply.

### Correction sheet
- "Save correction" stays disabled until the required note has at least one character — the same required-field pattern the rest of the app already uses for required text fields.
- Opens pre-filled with whatever data already exists for that date (times, if any) so the owner is editing, not re-entering from scratch.

## State Patterns

> Visual reference: [key-onboarding-states.html](mockups/key-onboarding-states.html) — onboarding intro (with the "Not now" path), `upcoming` state, `history_only` state, and the permission-denied state. Weekly off / Holidays settings screens: [key-weekly-off-holidays.html](mockups/key-weekly-off-holidays.html). Employee enrollment (including a future-start-date new joiner): [key-enrollment-toggles.html](mockups/key-enrollment-toggles.html).

| State | Behaviour |
|---|---|
| Attendance not yet enabled (Owner) | Tile/entry point opens the wizard directly, not an empty dashboard |
| `attendanceAccess: none` (Employee) | No 4th tab, no attendance UI anywhere. Notifications bell still visible (FR-27) |
| `attendanceAccess: upcoming` | 4th tab present; shows the "Attendance starts on {date}" screen with Office/timings/weekly-offs; onboarding (FR-4) can be completed early; no check-in control rendered at all (not disabled — absent) |
| `attendanceAccess: active` | Full Today / calendar / leave screens |
| Location permission denied/never granted (within `active`) | Today screen renders fully (Office info, summary) but CheckInOutButton shows "Turn on location to check in"; all other screens (calendar, leave) work normally per FR-4 |
| Location precise-off (Android Approximate / iOS Precise off, within `active`) | CheckInOutButton shows "Turn on precise location to check in" — a distinct state from permission-denied, since permission itself is granted |
| `attendanceAccess: history_only` | Calendar and leave history are read-only (past data only); no check-in control; a small persistent note explains why ("Attendance tracking ended on {date}") |
| Loading (any list/calendar) | Skeleton, never a blank flash (NFR-8). Reuses the existing `ReportSkeleton` shape generalised into a shared `Skeleton` — per addendum §B2, this generalisation is real, currently-unbuilt work, not something already sitting in `components/ui` today |
| Setup wizard: step save fails mid-flow (network drop while persisting a completed step) | The step's own screen shows an inline retry banner; the wizard does not advance and does not lose what was entered — the Owner retries from the same step, never re-enters earlier steps |
| Offline | Detected before a check-in attempt is even tried; check-in/out show a blocking offline message instead of attempting a doomed network call. Read-only screens (calendars, history) still work from last-loaded cache with an offline banner |
| Empty pending-leave queue | `EmptyState`: "No pending requests" |
| Empty monthly view (no tracked employees yet) | Shouldn't normally occur post-wizard, but if it does: `EmptyState` pointing back to Employees settings |

`attendanceAccess` is refetched on app foreground and whenever an attendance notification arrives (per addendum §C2), so the tab and its content never go stale or flicker between states.

## Interaction Primitives

- Check-in/out: one explicit tap, always server-confirmed before the UI reflects success — no optimistic update (see CheckInOutButton above).
- Approve/Reject/Revoke/Cancel: single tap for the terminal action; a reason field, where required, blocks the confirm button until filled (Revoke, Correction); where optional (Reject), it never blocks.
- Calendar cell tap → Day Detail sheet (not a full-screen push) — consistent with how the app already prefers a sheet for "more detail on one item" over a navigation push.
- Pull-to-refresh on Dashboard, Monthly employee list, and My calendar/leave history — standard native pattern, matching Jobs/Customers.

## Accessibility Floor

- Every Day status and flag pairs an icon with a text label — never colour alone (FR-25, enforced by construction in DESIGN.md's status-family table). Each of the 5 hue families holds 2–4 statuses; every icon within a family must be visually distinct at the actual rendered size (12px in the calendar cell) — not merely assigned a different name in the token table. Before build, render one throwaway calendar month containing at least one day from all 12 statuses at real size and confirm every same-hue pair is actually distinguishable at arm's length; do not rely on the token table alone as proof.
- Press targets: ≥ `touch.min` (44px) everywhere **except** the MonthCalendar's day cells, which are a stated exception — cells run as low as ~40px tap area on a 7-column grid on a 360dp-wide phone (a common budget-Android width in this app's core market). The exception is scoped to calendar cells only; every other control in this module (including the Weekly-off day-picker's pills, which are a similar small-grid control) meets the full 44px floor. The calendar's Day Detail sheet — reachable from any cell regardless of how imprecise the tap was, since the whole cell area is one tap target — is the accessible fallback that shows the full label, so no information is lost to the smaller target, only precision of the initial tap.
- Screen reader: a calendar cell announces date + status label together ("15 September, Present"), not the icon alone. The Dashboard's flag strip announces count + label ("2, Checkout missing. Button."), mirroring the existing OverdueStrip accessibility pattern.
- Dynamic type: status labels, flag tags and all form fields reflow rather than truncate to illegibility at the largest accessibility text size. The calendar cell's icon-only glyph does **not** scale with Dynamic Type (it's a fixed-size indicator inside a fixed-size grid cell) — the Day Detail sheet's full text label is the accessibility fallback for a user who has increased their text size, exactly as it is for the small-tap-target case above.
- **Permission-denied path (FR-4):** a denied (or OS-level "never ask again") user is never dead-ended. The onboarding/summary screen still renders in full — Office, timings, weekly-offs, leave history and the leave-apply action all work — with the CheckInOutButton replaced by its "Turn on location to check in" state (see CheckInOutButton). This state is explicit in the State Patterns table above, not just implied by the button's own states, because it changes what the *whole screen* looks like, not only the button.
- **Office map picker (FR-5):** the drag-to-fine-tune pin and the radius slider are the two genuinely spatial controls on this screen. Both get a non-visual equivalent: the radius slider is a standard accessible slider/stepper (announces the numeric value on every change, e.g. "Radius, 100 metres") rather than a bare custom-drawn knob, and the pin position exposes a text fallback (the resolved address/lat-long shown as a row beneath the map, editable via the existing address-search entry) so a screen-reader user can place and confirm an Office without needing to see or drag anything.
- **Weekly-off day picker:** the seven day pills are single letters visually (S M T W T F S) but each carries a full accessible label ("Sunday", "Monday", …) independent of the glyph, and announces its selected state ("Saturday, selected"). Two pills sharing a visible letter (the two S's, the two T's) must never share an accessible label.

## Key Flows

Mirrors the PRD's journeys (§2.3) verbatim — this module doesn't rename or re-scope them.

### UJ-1. Rakesh sets up attendance for the office team.
Rakesh (owner, pest control, two offices, 12 technicians, 5 office staff) opens the Attendance entry point and runs the setup wizard: adds Andheri and Thane (pin + 100 m radius each), sets 10:00 AM–6:00 PM / 15 min late cut-off / 8h-4h hours rules per office, changes the weekly off to Sat+Sun, skips holidays, and selects 3 + 2 employees across the two offices. The wizard blocks him once, when he tries to enable an employee with no office picked — he assigns one and continues. On finish, the dashboard shows "5 employees tracked · 0 checked in today." *Climax:* the dashboard reflects the new setup within the same session, with no separate "activate" step. The other 7 technicians see no change anywhere in the app.

### UJ-2. Priya checks in, late, and later checks out.
Priya, newly tracked at Andheri, opens the Attendance tab for the first time: onboarding shows a short intro, asks for location permission, and summarises her Office/timings/weekly-offs. At 10:22 AM she taps Check in; the app takes a fresh high-accuracy fix (40 m from the pin, well inside 100 m radius) and the check-in succeeds with a **Late** flag (22 min) — shown immediately as "Checked in 10:22 AM · Late by 22 min," and mirrored on the owner's dashboard in real time. *Climax:* at 6:22 PM (end time + 22 min, per FR-23) a reminder is waiting when she opens the app at 6:30 PM; she checks out and sees "8 h 08 m · Present." Earlier that morning, a check-in attempt from the bus stop (600 m away) was blocked with the exact distance-based message before she ever reached the office — she wasn't confused about why, because the message told her precisely how far and how close she needed to be.

### UJ-3. Arjun applies for leave, Rakesh approves, then revokes part of it.
Arjun applies for Mon–Fri leave with a reason; the app shows "5 working days" before he submits. Rakesh gets a notification, opens the Leave detail sheet, and approves in one tap. Midweek, Rakesh needs Arjun back and revokes the leave with a required reason ("Audit visit Thursday") — because Wed is already in progress, only Thu–Fri are revoked; Mon–Wed stay Approved. *Climax:* Arjun sees "Revoked (Thu–Fri): Audit visit Thursday" when he next opens the app, with no ambiguity about which days changed and why — the revoke sheet's "future dates only" behaviour (the split) is invisible plumbing to him; what he sees is exactly the two affected days and the reason. (Had Arjun instead cancelled the leave himself on Wednesday, the same split rule would apply from his side — only Thu–Fri would be cancelled, Mon–Wed stay Approved, and Rakesh would get a "Leave cancelled" notification instead of acting on a revoke.)

### UJ-4. Rakesh reviews the month.
On the 1st, Rakesh opens the Monthly view for last month: an employee list, each row showing the month's numbers. He taps Priya to open her calendar, sees a **Checkout missing** flag on the 14th, opens Day Detail, and corrects it to Present with a required note. *Climax:* the correction sheet's Save button only unlocks once he's typed the note — he can't accidentally save a correction with no explanation — and the moment he saves, both the calendar cell and the employee list row's totals update in place (Days worked 17.5 → 18.5), so he sees the effect of his own correction immediately rather than having to re-open the screen.

### UJ-5. Priya checks her own record.
Priya opens My Attendance and sees this month's calendar, her weekly offs, upcoming holidays, her leave requests with status, and a running "Days worked: 14.5 so far." Everything she sees here is read-only except the leave-apply action and (while active) the check-in/out control on Today — there is no way for her to edit a past day herself, by design (only the owner corrects; she can only see what happened and, if she disagrees, presumably raise it with Rakesh outside the app, exactly as the PRD's trust framing intends). *Climax:* she gets her answer — "am I doing okay this month?" — in the time it takes to open one screen, with no need to ask Rakesh or dig through a WhatsApp thread.

## Responsive & Platform

- iOS uses Apple Maps for the office picker, Android uses Google Maps (no shared map-styling concerns since each platform gets its native renderer, per addendum §C2) — same pin/circle behaviour on both.
- Fake-GPS detection differs by platform (Android: `isMock`; iOS 15+: `isSimulatedBySoftware`) but the **user-facing behaviour is identical** on both — same message, same rejection, same attempt log. The platform difference is invisible in this module's UX.
- No landscape layout — phone portrait only, matching the rest of the app.

## Open Questions

- **Exact rate-limit copy** ("Too many attempts, try again in 10 minutes" or similar) is a PRD-approved mechanism (FR-7) but the PRD doesn't fix the literal string — marked `[ASSUMPTION]` above; confirm exact copy at build time.
- **Calendar cell glyph at very small screen widths** (narrow older phones): whether the 7-column grid needs a horizontal-scroll fallback or simply shrinks cells further hasn't been tested against a real device matrix — flagging for implementation-time confirmation, not blocking.
- **Icon distinctness across the full 12-status set, at real size:** the reviewer pass caught and fixed one real collision (Half day vs Checkout missing, both amber) once a populated mockup was rendered. Only the green and amber families have actually been drawn together in a mock; the blue family (Leave, Half-day leave, In progress) and the 4-way gray family (Weekly off, Holiday, Not tracked, Not checked in yet) have not. Before build, render one throwaway calendar month covering all 12 statuses at once and eyeball every same-hue pair at arm's length — don't rely on the token table alone as proof, since that's exactly how the first collision slipped through.
- **KPI-tile tap behaviour beyond the Flags strip:** this pass decided the KPI tiles are informational-only (no tap action) and only the Flags strip rows navigate anywhere. If product feedback later wants a tile like "Late" to jump to a filtered list, that's a small additive change to the Dashboard KPI tiles Component Pattern, not a redesign.
