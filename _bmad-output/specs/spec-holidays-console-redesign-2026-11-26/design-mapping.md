# Design mapping — Stitch project 1904834121279645727

Screens (downloaded to /tmp/holiday-design during planning: main/modal/schedule/flyout .png + .html):

## Screen 1 — "Fenzit Holidays & Calendar Management" (main page)
- Breadcrumb Workspace / Settings / Holidays & Time-off; header "Hello, {name}" + subtitle listing offices; primary button "+ Add Holiday" (top right).
- Year switcher pills: prev year / current ("Current") / next year.
- Left card: month calendar (`< Today >` nav), holiday cells = blue dot + short name chip; legend "● Holiday (Office Closed)"; IST footnote. Cell click → holiday modal (owner-specified interaction).
- Right rail: gradient "UPCOMING HOLIDAY · IN N DAYS" banner; "Upcoming in {year} · N Holidays" list (date box, name, weekday, "N Employees have off", office chips, Edit/Remove) + "See Full List →" (→ schedule page); "Archive Reference — Past Holidays This Year" chips.
- Bottom-left: "TOTAL PAID HOLIDAYS · {year} — N Days Off" stat; "LONG WEEKEND BREAKS — Friday or Monday Off" card listing long weekends (name, date, "3 Days Off" chip) + tip line.

## Screen 2 — "Add Holiday Modal Dialog"
- Title "Add New Holiday"; subtitle "Set up holiday date and select which office it applies to".
- Fields: Holiday Name* (max 80, e.g. hint "e.g. Diwali, Eid, Republic Day"); Holiday Classification = single static selected card "Official Company Holiday — Standard fully paid leave"; Holiday Date & Timing* (date input + weekday/"Full Day Off" readout + helper); "Which Offices Does This Apply To?*" chips (All Offices globe chip = scope all; per-office chips multi-select, N offices selected counter).
- NO email checkbox (owner: omitted). Footer: Cancel / Save Holiday.
- Edit mode = same modal pre-filled (calendar date with holiday, Edit buttons, Edit Details in flyout).

## Screen 3 — "Full Annual Holiday Schedule" (route /admin/company/holidays/schedule)
- Breadcrumb … > {year} Annual Holiday Calendar; title "{year} Official Holiday Calendar"; buttons Print, Export Calendar, + Add Holiday.
- Stats: Total Holidays (N days scheduled, all offices closed), Offices (N branches covered), Long Weekend Breaks (N extended breaks).
- Filter bar: office dropdown ("All offices…") + month chips All/Jan…Dec.
- Table grouped by month: month header (badge, "N statutory holidays", "N Days Off" chip); rows = name + description, observed date & day (date-box), duration & impact tag (3-Day Long Weekend / 1 Day Mid-Week / Weekend Observation), applicable offices, headcount ("N staff"), edit pencil. Row click → inspector sidebar.
- Footer "Showing N official holidays for calendar year {year}"; Branch Office Coverage card (per-office bars: office name, days, staff) + compliance note.

## Screen 4 — "Calendar Date Inspector Flyout" (right sidebar over dimmed page)
- Top row: "● Official Holiday" + "Edit Date" (pencil) + close X.
- Long date "Sunday, 08 November 2026"; chip holiday name; "Day off for all staff" (or "for N offices").
- Card: holiday name + description + "Paid holiday for all branches/offices".
- "Team Attendance & Leave": "N out of M employees are on leave" progress bar + "K team members on urgent duty / standby" (real: approved leave on that date vs tracked staff).
- "Offices closed on this day": per-office chips with staff counts (real: assignments covering the date); unassigned staff = "Work from Home staff" chip.
- "Next upcoming holiday" row (date box, name, weekday) → opens that date's inspector.
- Footer: "Delete Holiday" (destructive) + "Edit Holiday Details".

## Token / copy mapping rules
- Colours → existing console tokens (`src/styles/tokens.css`); blue accent ≈ existing primary; holiday status colours already exist (`--color-status-holiday-*`).
- Fonts/spacing → console defaults; icons → existing glyph set (no Material icon font).
- Demo numbers (94/48/86 employees), emoji (🪔), "+2 vs last year", "Floating Allowance Pool" are mock-only — replaced by real data or dropped.
- All copy Indian English, "Employee" terminology per CLAUDE.md.
