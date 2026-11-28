# Design mapping — Stitch project 12976873967605867584

Screen (downloaded to /tmp/stitch-exec-dashboard during planning: screen_raw.png + screen_raw.html):

## Screen 1 — "Fenzit - Executive Dashboard with Employee Pulse Analytics" (route /admin/company)
- Breadcrumb Console › Overview; greeting "Hello, {name}" + Owner pill (STAR icon, not the old crown) + lede "Today's pulse, the job report and every list in your company — one page." (unchanged copy).
- Subscription banner (full-width, white, blue-tinted border, rounded-2xl): "Subscription" bold + pulsing emerald "Active" chip + blue "Enterprise Plan" chip · "Valid until {date} (India time)" · "Annual Billing • Auto-renews"; right side: "Full access to multi-org tracking & workflows" + primary blue "Manage Plan →" button.
- Two side-by-side chart cards (lg:grid-cols-2), each rounded-2xl white with hover shadow:
  1. **Attendance Trend** — subtitle "Distribution of team attendance"; controls row = date-range pill (calendar icon + "23 Oct – 21 Nov" + chevron, display-only) + segmented presets [7D | 30 Days | This Month]; 5-dot legend: Tracked (blue-500), Checked In (emerald-500), Not Checked (amber-400), Short Day (indigo-400), Late / Leave (rose-400); area chart (h-60, 5 gridlines, dashed tracked baseline, emerald area+line, amber under-line), 5 weekly x-labels ending "21 Nov (Today)"; footer "Download CSV".
  2. **Jobs & Approvals** — subtitle "Flow comparison"; same controls [7D | Last 30 Days | This Month]; 4-dot legend: Created by Empl. (blue-600), Approved by You (emerald-600), Auto-Approved (amber-500), Created by You (purple-600); cumulative rising lines (blue area under Created-by-employees), weekly x-labels "Week N (date)" + "Today (date)"; footer: "Overall Turnaround efficiency: {pct}" (emerald) + "Approval Rules →" link.
- **Employee Overview & Analytics** (full-width card) — subtitle "Active headcounts, invitations status, and job approvals needed"; same controls; 4-dot legend: Total Employees (blue-600), Active Employees (emerald-500), Pending Invites (amber-400), Needs Approval (purple-600); wide chart (dashed total baseline, emerald area for active, amber invites line, purple needs-approval line), weekly x-labels; footer: "Download CSV • Active workforce rate: {pct}" + "Manage Employees →".

## Removed from the old overview (owner instruction + mock)
- The six pulse tiles (Tracked/Checked in/Not checked in/Short day/Late/On leave), the flag line.
- The five link cards (Customers/Employees/Jobs/Holidays/Attendance).
- The job report's headline tiles as tiles, the Per-employee table, the "Can create jobs, none created yet" list, the approval-pipeline fact cards, the Leave card, the Subscription SectionCard (replaced by the banner).

## Token / copy mapping rules
- Colours: mock Tailwind palette → existing console tokens (`src/styles/tokens.css`); blue-600 ≈ `--color-primary`; emerald/amber/indigo/rose/purple series dots use the mock's literal hues (chart series identity, not console tokens).
- The sidebar in the mock is the existing console shell — out of scope (page content only).
- Mock placeholder numbers (Tracked (5), 100 employees, 92.4%) are replaced by real API data; the "(4.8 avg)" legend format is kept (avg per day for checked-in / not-checked, totals elsewhere).
- "Enterprise Plan / Annual Billing / Auto-renew / Manage Plan" come from new tenants columns via /users/me (see SPEC).
- Chart SVG structure (gridlines y=20/60/100/140, baseline y=170, viewBox 500×180 / 1000×180, dashed baselines, white-stroked end dots with `<title>` tooltips) is reproduced from the mock.
