# Navigation map — before / after

Load-bearing route-level detail for the implementing agent. Routes in `code` style are React Navigation route names; file paths are relative to `workspace/core/frontend/fenzit-app/src`.

## Before

```
MainTabs (owner footer)                    RootNavigator (root stack, excerpts)
├── Home        → screens/HomeScreen       ├── AttendanceHome          (features/attendance/home)
├── Jobs        → features/jobs            │     gate: focus → GET /attendance/setup
├── Customers   → features/customers       │     incomplete+owner ⇒ replace AttendanceSetupWizard
└── More        → features/more            ├── AttendanceSetupWizard
    ("Account" label, TabBar icon: More)   ├── AttendanceDashboard / AttendanceMonthly
                                            ├── OwnerLeave / AttendanceOffices / …
```

Account tab rows of record: **Customers row** → `navigate('Customers')` (tab switch), **Attendance row** → `navigate('AttendanceHome')` (root-stack push).

Attendance hub (`AttendanceHomeScreen.tsx`) sections after the restructure: the four setup tiles (Offices, Team attendance, Weekly off, Holidays) with NO section eyebrow (owner removed the "Set up" header on 2026-10-23 — every tile there is setup); the "Every day" tiles moved to the tab page.

## After

```
MainTabs (owner footer)                    RootNavigator (root stack, excerpts)
├── Home        → screens/HomeScreen       ├── Customers              ← NEW stacked route (features/customers list)
├── Jobs        → features/jobs            ├── AttendanceHome          (setup-only hub; gate unchanged)
├── Attendance  → NEW tab screen           ├── AttendanceSetupWizard
│   "Every day": Today → AttendanceDashboard├── AttendanceDashboard / AttendanceMonthly
│   (owner-only) Leave → OwnerLeave        ├── OwnerLeave / AttendanceOffices / …
└── More        → features/more
    ("Account" label; unchanged key)
```

- New tab screen (new file under `features/attendance/home/`, e.g. `AttendanceTabScreen.tsx`): renders the three tiles moved off the hub + the CAP-3 setup banner; no back header (tab roots have no back), no "justEnabled" flash (that belongs to the hub/wizard return path).
- `TabBar` `ICONS` already maps `Attendance → CalendarCheck`; owner and technician tabs share it unchanged.
- Account tab: Customers row and Attendance row both keep their labels/positions; only their navigation targets change (`Customers` now resolves to the root-stack route once the tab route is gone).
- View-only users: tab page shows Today + Monthly (no banner, no Leave); the hub row stays visible and opens a page with just the view-only notice (no tiles) — decided 2026-10-23.
- Home screen (CAP-6, decided 2026-10-23): `TodayPulseCard` tap → `AttendanceDashboard` (root stack); the plain "Attendance" tile tap → the new Attendance tab; its subtitle stops promising offices/team.
- The owner tab screen is named `AttendanceTabHomeScreen.tsx` — the basename `AttendanceTabScreen.tsx` is taken by the technician's tab screen (`features/attendance/me/`).
