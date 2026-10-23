# UI map — Attendance tabs & Home leave banner

Load-bearing structure, visibility, and supersession detail for the implementing agent. Route names in `code` style; file paths relative to `workspace/core/frontend/fenzit-app/src`.

## Attendance tab page — before (shipped, commit 3fc7593)

```
AttendanceTabHomeScreen (features/attendance/home/AttendanceTabHomeScreen.tsx)
├── Title-only header "Attendance"
├── [owner + setupIncomplete] banner tile "Finish setting up attendance" → AttendanceSetupWizard
└── "EVERY DAY" eyebrow + three Tiles (push screens):
    ├── Today   → AttendanceDashboard   (root stack)
    ├── Monthly → AttendanceMonthly    (root stack)
    └── Leave   → OwnerLeave           (root stack, canWrite only)
```

Gate: one light `GET /attendance/setup` per focus, latest-wins, owner-only; a failed/403 GET silently renders the page without the banner.

## Attendance tab page — after (this spec)

```
AttendanceTabHomeScreen
├── Title-only header "Attendance"
├── [owner + setupIncomplete] banner "Finish setting up attendance" → AttendanceSetupWizard (UNCHANGED)
└── Segmented control (mockup: pill style, calendar glyphs)
    ├── 📅 Today    ← AttendanceDashboard pane   (ACTIVE by default)
    ├── 📅 Monthly  ← AttendanceMonthly pane
    └── 📅 Leave ⓶ ← OwnerLeave pane            (canWrite only; badge = pendingLeaveRequests)
```

- The banner (shipped CAP-3 behaviour) stays exactly as is — it now sits above the segmented control instead of the tiles. The owner withdrew the "just show settings instead" direction on 2026-10-23.
- The page must support being opened with Leave pre-selected: Home's Review lands here (nav param on the `Attendance` tab route or equivalent — plan-level).
- No "EVERY DAY" eyebrow (the tabs are the content, not a tile list).

## Home — leave entry

```
HomeScreen → TodaysJobsSection
└── [admin + attendanceEnabled + N>0] leave banner (CAP-4, mockup):
    "N leave requests" / "Action pending approval"  +  [ Review ]
    Review → Attendance tab, Leave pre-selected
    (replaces the shipped LeaveReviewStrip pointer-row anatomy:
    "Leave requests to review [N] >" — features/home/components/LeaveReviewStrip.tsx)
```

Count source (unchanged): `profile.attendance.pendingLeaveRequests` off the owner `/users/me` mirror — fail-hidden when absent; no second request.

## Visibility matrix

| Surface | Owner, setup done | Owner, setup incomplete | Viewer (canWrite=false) |
|---|---|---|---|
| Attendance tabs | Today + Monthly + Leave(badge) | same (banner above tabs) | Today + Monthly only |
| Setup banner | absent | present | never |
| Setup GET per focus | yes | yes | skipped |
| Home leave banner | N>0 | N>0 (same) | never |

## Dual-hosting (constraint)

`AttendanceDashboard`, `AttendanceMonthly`, `OwnerLeave` stay pushed root-stack screens — Home's pulse card → AttendanceDashboard, and any other existing entries → OwnerLeave — while ALSO embedding as tab panes. Headers, back behaviour, and SafeArea must hold in both hosts. `OwnerLeaveScreen` currently ships its own `ScreenHeader` with back + "Apply on behalf" CTA + internal `Pending | All` SegmentedControl; how the header degrades inside a tab pane is plan-level.

## Supersession map (spec-owner-footer-attendance-nav)

- CAP-2 (three tiles) → replaced by CAP-1 here (tabs).
- Non-goal "no embedded attendance content on the tab page" → reversed by CAP-1.
- CAP-3 (setup banner, "never auto-redirects") → STANDS — owner re-affirmed it on 2026-10-23 (withdrew the settings-instead-of-tabs direction).
- CAP-1 (four-item footer), CAP-4 (Customers via Account), CAP-5 (setup-only hub + gate), CAP-6 (Home pulse card → AttendanceDashboard, plain tile → Attendance tab) → stand unchanged.
