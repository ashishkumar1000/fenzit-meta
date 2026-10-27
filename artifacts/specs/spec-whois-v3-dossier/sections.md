# sections.md — whois v3 section catalog

Per-section source, columns, and the 2026-10-27 DB-research verdicts. Column
widths are tuned for an 80-column terminal (≤74 content columns incl.
gutters). Status colors follow the schema CHECK domains via `statusColor`:
green = active/approved/ready/completed, amber = invited/pending/queued/
generating/in_progress, red = removed/rejected/cancelled/revoked/failed/absent.

| # | Section | Source (join/filter) | Columns |
|---|---------|----------------------|---------|
| 1 | Identity header | `users` by phone; logins via `auth.identities`⨝`auth.users` by phone | name+badges, phone, joined, id-prefix, logins, membership strip, gradient rule |
| 2 | Glance strip | counts | jobs, attendance attempts, leave, offices, notifications, audit |
| 3 | Company line | `tenants` by membership | founded-by marker, people/customers/jobs/attendance counts, address, timezone, GSTIN ✓, UPI ✓ |
| 4 | Memberships | `memberships`⨝`tenants` (+invited_by name) | company◆, role, status, code, invited by, joined |
| 5 | Jobs (as technician) | `jobs`⨝`customers` (+photos count, current_step, completed_at) | number (! = urgent), status, step, scheduled, customer, photos |
| 6 | Offices | `attendance_office_assignments`⨝`attendance_offices` | office, address, radius, valid daterange |
| 7 | Attendance records | `attendance_records` by employee, recent 5 | work date, in, out, hours (derived; OPEN), distance, mocked flags |
| 8 | Attendance attempts | `attendance_attempts` by employee, recent 5 | kind, outcome (colored), provider, distance, mocked, when |
| 9 | Authored moderations | `attendance_corrections`/`_day_overrides` where actor/created_by = person | date, employee, note (+overrides-authored count) |
| 10 | Leave | `leave_requests` + `_request_days` + `_events` | span, part, state chips, reason; events feed cause/actor/dates/when |
| 11 | Skills | `user_skills`⨝`skills` | names, dim-separated |
| 12 | Invites | `memberships` where invited_by = person (sent), and invited-by (received) | name, phone, company, role, status |
| 13 | Activity | `activity_logs` by actor or job, recent 5 | event, job, when |
| 14 | Audit | `audit_log` actor-or-target, recent 5 | action, actor/target, when |
| 15 | Notifications | `notifications` by user, recent 5 | event, payload summary, pushed/read, when |
| 16 | Reports | `report_requests` by person, recent 5 | type, status, when |

## Rejected by research (and why)

- `attendance_onboarding` — one timestamp; folded into enrolments count.
- `attendance_setup_progress`, `holidays`, `attendance_settings`,
  `attendance_office_rules`, `attendance_weekly_off_defaults` — tenant-level
  config, not person facts.
- `early_access_signups`, `app_config`, `country_codes` — no user link / global KV.
- `customers` — no users FK; belongs to a job drill-down (non-goal).
- `idempotency_log`, `job_sequences`, `employee_sequences`,
  `attachment_uploads` — plumbing.
- Workflow template step labels — future work (current_step key shown raw).
