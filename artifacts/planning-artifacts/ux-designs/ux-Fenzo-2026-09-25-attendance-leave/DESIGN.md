---
name: Fenzo — Attendance & Leave
description: Visual design contract for the optional Attendance & Leave module (owner + technician), covering setup wizard, check-in/out, leave, calendars and corrections. Inherits the Fenzit Design System (fenzo-app/src/theme, src/components/ui) verbatim — introduces one generalisation (new Day-status tone keys on the existing status palette) and reuses every existing visual component; no new colours, no new component shells.
type: feature
status: final
updated: 2026-09-25
product: fenzo-app (owner + technician)

colors:
  # Inherits Fenzit tokens verbatim — src/theme/colors.ts. No new hues.
  # [ASSUMPTION] Day-status tones are the 5 existing status families,
  # reused by meaning (not job semantics) and disambiguated within a
  # family by icon + label — never colour alone (PRD FR-25).
  status.worked: "{colors.status.done}"       # green — Present, Worked on holiday
  status.partial: "{colors.status.scheduled}" # amber — Half day, Checkout missing, Late/Early flags
  status.blocked: "{colors.status.cancelled}" # red — Absent, Fake location flag
  status.planned: "{colors.status.progress}"  # blue — Leave, Half-day leave, In progress (today)
  status.neutral: "{colors.status.neutral}"   # gray — Weekly off, Holiday, Not tracked, Not checked in yet
  map.circleStroke: "{colors.primary}"        # office map pin + geofence circle stroke
  map.circleFill: "{colors.primarySoft}"      # geofence circle fill — colour token is real (colors.primarySoft); the ~20%-opacity overlay treatment on a map is the new part, not the colour itself
  danger.action: "{colors.danger}"            # revoke, reject-with-reason, fake-GPS block message
  surface.page: "{colors.surfacePage}"
  surface.card: "{colors.surfaceCard}"
  text.strong: "{colors.textStrong}"
  text.muted: "{colors.textMuted}"

typography:
  screen.title: "{typography.title}"
  section.header: "{typography.heading}"
  body: "{typography.body}"
  bodySm: "{typography.bodySm}"
  label: "{typography.label}"
  caption: "{typography.caption}"
  checkin.time: "{typography.display} @ {fontSize.3xl}"  # [ASSUMPTION] big legible check-in/out timestamp — 3xl (36) overrides display's own default fontSize (48)

rounded:
  card: "{radius.lg}"
  sheet: "{radius.xl}"
  pill: "{radius.pill}"
  calendar.cell: "{radius.sm}"

spacing:
  screen.padding: "{spacing.s4}"
  section.gap: "{spacing.s3}"
  card.gap: "{spacing.s3}"
  touch.target: "{touch.min}"
  cta.height: "{touch.large}"   # 56 — the Check in/out button, one deliberately larger target

components:
  status.badge: "existing Badge — new status keys added to colors.status (see Colors), no component change"
  flag.tag: "existing Badge, size=sm, tone=soft — Late / Early checkout / Fake location"
  checkin.button: "NEW CheckInOutButton — full-width primary CTA, touch.large height"
  office.map: "NEW full-screen map route — react-native-maps, draggable pin + geofence circle"
  month.calendar: "NEW MonthCalendar grid — 7-col day cells with status dot + tap-through to day detail"
  leave.form: "existing DateTimeFields + SegmentedControl + Input, composed in a new screen"
  wizard: "existing AuthFlow step pattern + StepIndicator, server-resumed"
  enrolment.rows: "existing Switch + TechnicianPicker row style"
  skeleton: "generalisation of existing ReportSkeleton into a shared components/ui Skeleton — real build work per addendum §B2, not something already generic today"
  weekly.off.settings: "existing 7-day picker pattern + effective-date field, composed in a new screen"
  holidays.settings: "existing list/add pattern + Input, composed in a new screen"
---

# DESIGN.md — Fenzo Attendance & Leave

## Brand & Style

Inherits the Fenzit Design System wholesale — see `fenzo-app/src/theme/DESIGN_SYSTEM.md`. Same posture as the rest of the app: flat backgrounds, no emoji, no illustrations, sentence case, lucide icons at stroke 2. This is a **utility, trust-first surface** — an owner checking "who's in today" and an employee checking in both need the answer in one glance, not a designed moment. Numbers and times are given generous size and weight (they're the whole point of the screen); everything else stays quiet.

Spines win on conflict with any mock or wireframe.

## Colors

No new hues — the existing 5-tone status palette (`done` green / `progress` blue / `scheduled` amber / `cancelled` red / `neutral` gray) is reused for Day status, by **meaning**, not by borrowing job semantics:

- **Green (worked family):** Present, Worked on holiday — a day the person was there and it counted.
- **Amber (partial/attention family):** Half day, Checkout missing — matches the existing "needs attention, not alarm" convention (the Home overdue strip uses the same amber for the same reason). Also used for the **Late** and **Early checkout** flags.
- **Red (blocked family):** Absent, and the **Fake location attempt** flag — reserved for genuinely bad outcomes, exactly as the rest of the app reserves red for Urgent/danger.
- **Blue (planned family):** Leave, Half-day leave, and today's **In progress** state — these are the system correctly handling something, not a problem; blue already carries "in progress / on track" meaning in Badge today.
- **Gray (neutral family):** Weekly off, Holiday, Not tracked, Not checked in yet — non-events, nothing to react to.

Two or more Day statuses share a hue family on purpose (e.g. Present and Worked on holiday are both green). **Icon + label always disambiguate within a family** — this is the FR-25 accessibility rule ("never relies on colour alone") applied by construction, not as an afterthought.

The office geofence circle on the map uses `colors.primary` stroke with a soft fill — the one deliberately "branded" visual moment in the module (it's the trust anchor: "this is the boundary that decides whether your check-in works").

## Typography

As in frontmatter — no new type roles except one deliberate exception: the Check-in/Check-out screen shows the resulting time at `typography.display` size (36px) after a successful action, because that confirmation is the single most important thing on the screen for an employee glancing at their phone. Everywhere else, existing roles only.

## Layout & Spacing

```
┌ Owner: Attendance Dashboard (Today) ──────────┐
│  Attendance · Today            [Office: All ▾]│
│  ┌────────┐ ┌────────┐ ┌────────┐             │
│  │ 5       │ │ 3       │ │ 1      │  KPI tiles │
│  │ Tracked │ │ Checked │ │ Late   │  (existing │
│  └────────┘ └────────┘ └────────┘   tile card) │
│  ┌ Flags ──────────────────────────────────┐  │
│  │ ⚠ 2 Checkout missing            View ›  │  │  same OverdueStrip
│  └──────────────────────────────────────────┘  │  pattern as Home
│  Pending leave (2)                    View ›   │
└─────────────────────────────────────────────────┘

┌ Employee: Today ───────────────────────────────┐
│  Andheri Office · 10:00 AM – 6:00 PM            │
│                                                  │
│              ┌───────────────┐                  │
│              │   CHECK IN    │  ← cta.height 56  │
│              └───────────────┘                  │
│         You are 40 m from Andheri office        │  live hint, textMuted
└─────────────────────────────────────────────────┘
```

- Dashboard/list screens keep the established `screen.padding` (16) and `section.gap` (12) rhythm from Home and Jobs.
- The Check-in/out screen is the one screen that breaks from list density: it is mostly whitespace, one CTA, one line of context above and below. Nothing competes with the button.
- Month calendar cells: 7 equal columns, `calendar.cell` radius, minimum 40×40pt tap target (below `touch.min` in raw size but the whole cell — not just the number — is the tap target, matching the touch-target *area* rule even though the visual chip is smaller, same as small calendar patterns elsewhere use a tap-area larger than the visible glyph).

## Elevation & Depth

Inherits: cards = `surfaceCard` + 1px `borderSubtle` + `shadow.sm`. The map screen is the one full-bleed exception (no card chrome around the map itself; the pin/circle sit directly on it). The bottom control sheet on the map screen (search / current-location / confirm) uses `shadow.sheet`, matching every other bottom sheet.

## Shapes

Inherits: cards `radius.lg`, sheets `radius.xl`, pills `radius.pill`. Calendar day cells use `radius.sm` (6) — small chips, not full cards.

## Components

> Visual reference — every load-bearing surface is mocked: [key-checkin.html](mockups/key-checkin.html), [key-owner-dashboard.html](mockups/key-owner-dashboard.html), [key-month-calendar.html](mockups/key-month-calendar.html), [key-leave-apply.html](mockups/key-leave-apply.html), [key-setup-wizard.html](mockups/key-setup-wizard.html), [key-office-map-picker.html](mockups/key-office-map-picker.html), [key-weekly-off-holidays.html](mockups/key-weekly-off-holidays.html), [key-enrollment-toggles.html](mockups/key-enrollment-toggles.html), [key-onboarding-states.html](mockups/key-onboarding-states.html), [key-monthly-employee-list.html](mockups/key-monthly-employee-list.html). Spines win on conflict with any mock.

### StatusBadge (Day status) — extends existing `Badge`, no new component

`Badge` already renders from `colors.status[status]`; this module only adds new keys to that palette object (`leave`, `halfDayLeave`, `weeklyOff`, `holiday`, `workedHoliday`, `checkoutMissing`, `notTracked`, `inProgress`, `notCheckedIn`) mapped to the 5 existing hue families above. **Job code never passes these keys, so job rendering is byte-identical** — this is a generalisation, not a behaviour change, the same pattern the addendum already uses for `NotificationRow.jobId` (nullable) elsewhere in this module.

| Day status | Tone family | Icon | Label |
|---|---|---|---|
| Present | worked (green) | `CheckCircle2` | Present |
| Half day | partial (amber) | `Clock` | Half day |
| Absent | blocked (red) | `XCircle` | Absent |
| Leave | planned (blue) | `CalendarOff` | Leave |
| Half-day leave | planned (blue) | `CalendarClock` | Half-day leave |
| Weekly off | neutral (gray) | `Moon` | Weekly off |
| Holiday | neutral (gray) | `Flag` | Holiday |
| Worked on holiday | worked (green) | `Briefcase` | Worked on holiday |
| Checkout missing | partial (amber) | `AlertCircle` | Checkout missing |
| Not tracked | neutral (gray) | `MinusCircle` | Not tracked |
| Not checked in yet | neutral (gray) | `Circle` | Not checked in yet |
| In progress | planned (blue) | `Play` | In progress |

`tone="soft"` everywhere in this module (never `solid`) — matches the calm, non-alarming posture; solid stays reserved for wherever jobs already use it.

### Flag tag — existing `Badge`, `size="sm"`

Rendered inline, next to (never replacing) the StatusBadge:

| Flag | Tone | Icon | Example label |
|---|---|---|---|
| Late | partial (amber) | `AlertCircle` | Late · 22m |
| Early checkout | partial (amber) | `AlertCircle` | Early · 15m |
| Fake location attempt | blocked (red) | `ShieldAlert` | Fake location |
| Leave pending | neutral (gray) | `Clock` | Leave pending |
| Corrected by owner | neutral (gray) | `Pencil` | Corrected |

### CheckInOutButton (NEW)

> [key-checkin.html](mockups/key-checkin.html)

Full-width primary `Button`-shell at `cta.height` (56, one size step above the design system's largest default) — the one screen in the app that deliberately makes the primary action bigger than the standard control, because it is used one-handed, often while walking, and must be unmissable.

| State | Look |
|---|---|
| Ready to check in | Solid primary, label "Check in" |
| Ready to check out | Solid primary, label "Check out" |
| Pre-flight confirm (leave/holiday) | Native confirm dialog over the screen — button itself untouched underneath (see EXPERIENCE.md → CheckInOutButton) |
| Resolving (GPS fix + server round-trip) | Disabled, spinner replaces label |
| Blocked (too far / low accuracy / fake GPS) | Returns to Ready state; a below-button `InlineError`-style message explains why, per FR-7 wording exactly as specified in the PRD |
| GPS fix timeout | Returns to Ready state; its own below-button message, distinct copy from low-accuracy |
| Rate limited | Disabled (not Ready) with a live countdown label ("Try again in 9:42") replacing the normal "Check in" text, for the full 10-minute window |
| Precise location off | Label reads "Turn on precise location to check in"; tap opens the OS precise-location setting |
| Permission denied/never granted | Label reads "Turn on location to check in"; tap opens the permission flow, or OS Settings if already denied once |
| Done today | Replaced by the day's summary card (times + worked hours) — the button itself disappears, there's nothing left to press |

Below the button: a live, muted-text distance hint ("You are 40 m from Andheri office") reusing `utils/distanceUtils.ts`'s existing haversine — display-only, the server is the real gate (NFR-2).

### Office map picker (NEW — full-screen route)

> [key-office-map-picker.html](mockups/key-office-map-picker.html)

`react-native-maps` (Apple Maps iOS / Google Maps Android, per addendum §C2). Pin is draggable; a translucent circle (`colors.primary` stroke, soft fill) redraws live as the Radius stepper/slider changes. A bottom control sheet (shadow.sheet) holds: "Use my current location", the existing address-search entry (reuses the Address Autosuggest screen from the prior UX pass verbatim), and "Confirm location". No-map fallback per FR-5: the sheet's two location methods still work with a plain "Map unavailable" message replacing the map area — same `InlineError`/`EmptyState` vocabulary used elsewhere for a degraded surface.

### MonthCalendar (NEW)

> [key-month-calendar.html](mockups/key-month-calendar.html) — also shows the Day Detail sheet and Correction sheet overlay

A 7-column month grid, one screen: employee's own (self view) or an Owner viewing one employee. Each day cell: date number + one small icon-only status glyph (colour from the family table above) — no text label inside the cell (no room); tapping any cell opens the Day Detail sheet, which shows the full StatusBadge with its label, times, worked hours, **distance from the office pin**, flags and (if present) the correction note and correction history. Today is outlined with `colors.primary`, matching how the rest of the app marks "current".

**Icon distinctness is load-bearing, not decorative:** the StatusBadge table below assigns every status within a hue family a different icon on purpose — e.g. Half day (`Clock`) vs Checkout missing (`AlertCircle`) are both amber but must render as visibly different glyphs, never the same path with only a colour or ring difference. Any mock or build that renders two same-hue statuses with the same icon has a bug, full stop — this is exactly the FR-25 rule this whole colour scheme exists to satisfy.

### Employee list row (Monthly view, Owner)

> [key-monthly-employee-list.html](mockups/key-monthly-employee-list.html)

Reuses `TechnicianPicker`'s existing row-card style verbatim (per addendum §B2 reuse note) — avatar, name, and a row of small summary numbers (Days worked, Late, Leave, Absent) instead of skills. Tapping the row opens that employee's MonthCalendar.

### Leave apply form

> [key-leave-apply.html](mockups/key-leave-apply.html) — also shows the Owner's pending-leave detail sheet

Composed entirely from existing components — no new form component:
- `SegmentedControl`: Full day / First half / Second half (half-day options shown only for a single-date selection, per FR-12).
- `DateTimeFields` (existing feature component, per addendum reuse note): date range picker, shows the live "X working days" count as dates change (FR-12).
- `Input`: reason, max 500 chars, required.
- Primary `Button`: "Submit for approval" (Employee) or "Approve" (Owner, on-behalf — FR-16, applied immediately, no submit-for-approval copy).

### Pending leave queue row → detail sheet

List row (existing row-card style) shows employee name, dates, working-day count. Tap opens a `Sheet` with the full reason, an "Approve" primary button and a "Reject" secondary/danger button (reason optional on reject, via an inline `Input` that appears only after Reject is pressed and before it's confirmed — never a separate screen).

### Setup wizard

> [key-setup-wizard.html](mockups/key-setup-wizard.html)

Reuses the existing `AuthFlow` step pattern + `StepIndicator` (per addendum §B2) — same chrome as sign-up. Five steps per FR-1: Offices → Timings & hours → Weekly off → Holidays (skippable, shows a "Skip for now" secondary action) → Employees. Progress persists server-side; re-opening mid-setup resumes at the last incomplete step with no re-entry of earlier steps.

### Enrolment rows (bulk enable/disable)

> [key-enrollment-toggles.html](mockups/key-enrollment-toggles.html) — includes the future-start-date case (a new joiner set up before day one)

Existing `Switch` component per row (employee name + office assignment shown as secondary text), inside a `MultiSelect`-style scrollable list — toggling a row's switch is the enable/disable action; a per-row secondary tap opens the start-date picker (default today, or a future date) inline below that row, collapsing when set.

### Correction sheet

> see [key-month-calendar.html](mockups/key-month-calendar.html) Frame B

Existing `Sheet` + `SegmentedControl` (Present / Half day / Absent) + `Input` (note, required) + existing time-field components for adjusting Check-in/Check-out times directly. Primary button "Save correction" — disabled until the note is filled in (mirrors the existing required-field pattern elsewhere in the app). Day Detail (above) grows an expandable "Correction history" row when a date has more than one correction — same row-card style as everywhere else, just a disclosure toggle.

### Dashboard KPI tiles & Flags strip

> see [key-owner-dashboard.html](mockups/key-owner-dashboard.html)

KPI tiles: existing tile-card component (per Home's KPI tiles), non-interactive, arranged 3-per-row. Flags strip: the exact `OverdueStrip` pattern from Home's DESIGN.md, reused verbatim — one compact card, single row, ≥44px, amber for Checkout missing, red for Fake location attempt, chevron affordance, whole row pressable.

### Weekly off settings

> [key-weekly-off-holidays.html](mockups/key-weekly-off-holidays.html)

Tenant-default: 7 pill toggles (existing pill-button style) in a row + an effective-date field (existing date-field component). Per-employee overrides: `TechnicianPicker`-style rows, each opening a detail sheet with the same pills + effective-date + a "Remove override" secondary/danger action.

### Holidays settings

> [key-weekly-off-holidays.html](mockups/key-weekly-off-holidays.html)

List: date-badge + name row (existing row-card style), grouped Upcoming/Past. Add/edit: `Sheet` + date field + `Input` (name). An inline `InlineError`-style amber banner (not red — this is information, not a failure) appears above the confirm button when the chosen date overlaps an employee's approved leave, naming the affected employee(s).

### Revoke sheet / Cancel

> behavioral spec in EXPERIENCE.md → Component Patterns → Revoke sheet / Cancel; no dedicated mock — composed from existing `Sheet` + `Input` (reason, required only for Revoke) + a plain two-line "stays Approved / will be revoked" split summary using existing list-row typography, no new visual element.

### Office reassignment / Office archive

> behavioral spec in EXPERIENCE.md → Component Patterns → Office reassignment / Office archive; visually these are existing patterns already specified elsewhere — the office-picker + effective-date field from Enrolment rows, and the blocked-state `InlineError` banner pattern used everywhere else in this module.

## Do's and Don'ts

- **Do** keep every Day-status hue inside the 5 existing families — no sixth colour, ever, even though there are 12 statuses.
- **Do** pair every status/flag with an icon and a text label — colour is a reinforcement, never the only signal (FR-25). **Exception:** the Monthly Employee List's compact summary chips ("17.5 worked", "Late 3") are text + colour only, no icon — they're already unambiguous by their text content alone (a number and a word, not a status name that could be confused with a same-hue sibling), so this exception doesn't reopen the FR-25 risk the icon rule exists to close.
- **Don't** use `tone="solid"` Badges anywhere in this module — the calm/soft posture is deliberate; solid stays a job-status convention this module doesn't borrow.
- **Do** make the Check-in/Check-out button the single largest, most isolated element on its screen — resist adding shortcuts, banners or promos near it.
- **Don't** show the geofence circle anywhere except the Owner's Office setup/edit screen — an Employee never sees "how close they need to be" as a map; they see the plain-language distance message the PRD specifies (FR-7). Showing the boundary to the employee would invite gaming it, which the PRD's fake-GPS handling is explicitly guarding against.
- **Don't** add a photo/selfie affordance anywhere near check-in — explicitly out of scope (§7.2); don't let a future "looks nice" instinct sneak it back in.
- **Do** reuse `TechnicianPicker`'s row style, `DateTimeFields`, `AuthFlow`/`StepIndicator`, `Switch`, `Sheet`, `SegmentedControl`, `MultiSelect`, `Input`, `EmptyState`, `InlineError` and the Address Autosuggest screen verbatim wherever this module needs their shape — this module invents only what genuinely doesn't exist yet (map picker, month calendar, the big check-in button).
