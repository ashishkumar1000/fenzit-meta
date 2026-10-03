# BE-originated user-visible copy — full inventory (2026-10-03)

> Evidence file for the UX copy review. Produced by a read-only source exploration of
> `workspace/core/backend/fenzit-be`. All strings exactly as the BE emits them; paths relative
> to the backend root.

Response envelope (all errors): `{ error_code, message, ...extra }` via `src/common/filters/global-exception.filter.ts:18,47-48` (fallback message: `An unexpected error occurred`). ValidationPipe returns 422 with class-validator messages; `whitelist: true`, custom options in `src/common/validation-pipe-options.ts`.

## 1. API error / validation messages

### Auth — login/OTP (`POST /auth/otp/send`, `POST /auth/otp/verify`) + invite/setup
| String | Location | Trigger |
|---|---|---|
| `Too many OTP requests. Maximum ${OTP_RATE_LIMIT_MAX} requests allowed per ${OTP_RATE_LIMIT_WINDOW / 60} minutes.` | src/auth/auth.service.ts:81 | OTP resend too often |
| `OTP session not found or expired` | src/auth/auth.service.ts:158 | verify with stale session |
| `OTP session is locked due to too many failed attempts` | src/auth/auth.service.ts:165 | 5 wrong OTPs |
| `Invalid OTP code` | src/auth/auth.service.ts:192 | wrong OTP |
| `OTP code must be exactly 6 digits` | src/auth/dto/verify-otp.dto.ts:15 | malformed OTP |
| `countryCode must be a valid dial code (e.g. +91)` | src/auth/dto/send-otp.dto.ts:8 (also invite-technician.dto.ts:17, jobs/dto/new-customer.dto.ts:25, customers/dto/create-customer.dto.ts:18) | login/invite/customer forms |
| `phoneNumber must be 6–15 digits` | src/auth/dto/send-otp.dto.ts:17 (also invite-technician.dto.ts:26, new-customer.dto.ts:34, create-customer.dto.ts:27) | same |
| `Company setup required before inviting technicians` | src/auth/auth.service.ts:277 | owner invites before setup |
| `Phone number is already an active member of this tenant` | src/auth/auth.service.ts:296 | duplicate invite |
| `One or more skill IDs are invalid` | src/auth/auth.service.ts:321 | invite with bad skill |
| `This phone number is already registered in this tenant` | src/auth/auth.service.ts:343 | race on invite |
| `Invalid country code` | src/auth/auth.service.ts:349 | invite FK failure |
| `Failed to set up company` / `Failed to query user` / `Failed to create user` / `Failed to create invite` | src/auth/auth.service.ts:396, 475, 502, 353 | setup/invite failures — **"Failed to create user" was displayed live on the device 2026-10-03 (see report §Findings F2)** |
| `name must not be empty or whitespace`, `name must be at most 100 characters`, `companyName must not be empty or whitespace`, `stateCode must be a 2-letter uppercase code (e.g. KA, MH)`, `Invalid GSTIN format` | src/auth/dto/setup-company.dto.ts:20,21,26,36,47 | company setup form |
| `At least one skill ID is required` / `At most 20 skill IDs are allowed` / `Skill IDs must be unique` / `Each skill ID must be a valid UUID` | src/auth/dto/invite-technician.dto.ts:42-45 | invite form |

### Guards / common
| String | Location | Trigger |
|---|---|---|
| `Missing or malformed Authorization header` | src/common/guards/jwt-auth.guard.ts:58 | session expired/invalid token shape |
| `Invalid or expired token` | src/common/guards/jwt-auth.guard.ts:74 | expired login |
| `Token is not valid for API access` | src/common/guards/jwt-auth.guard.ts:83 | wrong token audience |
| `Insufficient permissions` | src/common/guards/roles.guard.ts:33 | technician hitting owner route |
| `X-Idempotency-Key must be a UUID v4` | src/common/interceptors/idempotency.interceptor.ts:62 | punch/leave POST with bad header |
| `X-Idempotency-Key header is required and must be a UUID v4` | src/attendance/leave.controller.ts:181, me-leave.controller.ts:172, me-attendance.controller.ts:177 | same |
| `This confirmation key was already used` | src/attendance/check-in-out.rejections.ts:105, check-in-out.replay.ts:89, leave.model.ts:174 | retry replay (409) |
| `Invalid cursor` | src/common/utils/cursor.util.ts:69 | paginated list with bad cursor |

### Attendance — check-in/out punch flow (`POST /attendance/me/check-in`, `/check-out`)
All from `outcomeMessage()` in src/attendance/check-in-out.model.ts:88-117 — the highest-traffic user-facing copy:
- `You are ${distanceM} m from ${officeName}. Move within ${radiusM} m.` (too_far; also emits `distanceM`/`radiusM` body fields, line 169-172)
- `Location not accurate enough, try again in the open` (low_accuracy)
- `Turn off fake location apps to check in` / `...to check out` (mocked)
- `Your location seems outdated. Refresh GPS and try again` (stale_fix)
- `Too many attempts. Try again in ${n} min` (rate_limited; emits `retryAfterSeconds`)
- `Attendance is not active for you yet` (not_tracked — also src/attendance/day-status.read.ts:229, leave-validation.ts:99,110)
- `You have already checked in today` / `You have already checked out today`
- `Check in before checking out`
- `You have leave today. Confirm to cancel it and check in`
- `Check-in could not be recorded` (fallback, line 115)

### Attendance — day statuses / monthly grid
- `Dates must be in YYYY-MM-DD format` (src/attendance/day-status.read.ts:61, monthly.ts:64, leave-validation.ts:36)
- `The end date cannot be before the start date` (day-status.read.ts:66, monthly.ts:68, leave-validation.ts:42)
- `A day-status range covers at most ${DAY_STATUSES_MAX_SPAN_DAYS} days` (day-status.read.ts:73)
- `A monthly range covers at most ${MONTHLY_MAX_SPAN_DAYS} days` (monthly.ts:72)
- `Employee not found in your company` (day-status.read.ts:238, leave.model.ts:164)

### Attendance — leave
- `Half-day leave applies to a single date only` (leave-validation.ts:56)
- `Leave can cover at most ${LEAVE_MAX_SPAN_DAYS} days at a time` (leave-validation.ts:50)
- `These days are already off` (leave-validation.ts:141)
- `You already have a leave request covering one of these dates` (leave-validation.ts:157, leave-transition.ts:119)
- `You can only apply for leave from ${floor} onward` (leave-validation.ts:117)
- `You can only apply for leave up to ${N} days in the past` (leave-validation.ts:124)
- `You already checked in on ${date}, so it can't be requested as leave` (leave-validation.ts:131)
- `You have a correction on ${date}. It cannot be requested as leave` (leave-validation.ts:150)
- `Leave request not found` / `Leave state transition is not allowed` (leave.model.ts:153, 185)
- `This request is no longer pending` (approve/reject race, leave.service.ts:123,142)
- `No future dates left to revoke` / `No future dates left to cancel` (leave.service.ts:161, 468)
- `startDate must be a YYYY-MM-DD date` / `endDate must be a YYYY-MM-DD date` / `reason is required` / `reason is required to revoke` / `employeeId must be a UUID v4` (src/attendance/dto/leave.dto.ts:38,48,68,75,98,138,146)

### Attendance — offices / holidays / enrolments / weekly offs / setup / corrections
- `Invalid office id` (offices.controller.ts:50); `Invalid holiday id` (holidays.controller.ts:57); `Invalid employee id` (enrolments.controller.ts:46, weekly-offs.controller.ts:50)
- `Nothing to update` (offices.service.ts:191); `Office not found` (offices.service.ts:219, 379, 424); `Office has tracked employees assigned` (offices.service.ts:271); `Rules must be sent as a complete set: startTime, endTime, lateCutoffMinutes, fullDayHours, halfDayHours` (offices.service.ts:185); `Office rule values violate the allowed ranges` (offices.service.ts:439)
- `Company setup required before using attendance` (attendance-rpc.helpers.ts:45,65; offices.service.ts:400,418; enrolments.service.ts:362; attendance.service.ts:214)
- `Holiday not found` / `A holiday on this date already exists` (holidays.service.ts:199, 214, 222); `A holiday date cannot be changed — remove the holiday and add it on the new date` (holidays.controller.ts:76)
- `Employee not found` (enrolments.service.ts:405, weekly-offs.service.ts:227); `The employee has no enrolment covering the effective date` (enrolments.service.ts:225); `The enrolment would leave an enrolled date without its office assignment` (enrolments.service.ts:384); `` `${name} is archived. Pick a live office.` `` (enrolments.service.ts:414)
- `At least one working day must remain` (weekly-offs.service.ts:208, 237)
- Setup: `Attendance setup has already been completed` / `Attendance setup has not been started` / `Failed to start attendance setup` / `Failed to save attendance setup step` / `Failed to complete attendance setup` / `Failed to read attendance settings` / `Failed to read attendance setup progress` (attendance.service.ts:69,109,116,83,132,199,233,252,165,138,158,191)
- Corrections: `note contains invalid control characters` / `note must be between 1 and 500 characters after trimming` / `Corrections cannot target a future date` / `Attendance is not tracked for this date` / `Provide exactly one of status or check-in/check-out times` / `checkoutAt is not allowed without checkinAt` (corrections.service.ts:150,156,164,172,185,195); DTO: `checkinAt must be an ISO-8601 instant`, `checkoutAt must be an ISO-8601 instant`, `note is required`, `employeeId must be a UUID v4` (dto/correction.dto.ts:45,53,62,68,78)

### Jobs (create/update/list/workflow/photos)
- Create: `Company setup required before creating jobs` (jobs.service.ts:243); `Provide exactly one of customerId or newCustomer` (254); `scheduledEnd must not be before scheduledStart` (269, 474, 544); `Customer not found` (306); `Technician not found` (331, 503); `Unknown or inactive skillId` (360); `Referenced customer or technician not found` (391); `Failed to create job` (397,407); `serviceLocation must not be empty or whitespace` (dto/create-job.dto.ts:40); `name must not be empty or whitespace` (dto/new-customer.dto.ts:18)
- Update: `Company setup required before updating jobs` (427); `Cancellation cannot be combined with field edits` (447); `No updatable fields provided` (458); `Job is not modifiable in its current status` (532; also workflow.service.ts:123,248)
- Get/list: `Company setup required before listing jobs` (588); `Company setup required before viewing jobs` (727); `Job not found` (753; also attachments.service.ts:107,234; workflow.service.ts:102,144,266); `Forbidden` (762; also attachments.service.ts:114,241; workflow.service.ts:111)
- Workflow: `Company setup required before advancing jobs` (workflow.service.ts:75); `Invalid workflow step transition` (178) — also forwards `currentStep` field
- Photos: `Company setup required` (attachments.service.ts:82,200); `Maximum of 5 photos already uploaded` (142,281); `File size exceeds the maximum of ${N} bytes` (209); `Upload not found` (262,302); `Upload session expired — request a new presigned URL` (272); `Failed to request upload` / `Failed to confirm upload` (101,132,181,228,287)

### Customers
`Company setup required before managing customers` (customers.service.ts:199,260,351,519); `` `Invalid customer coordinates (latitude=${latitude}, longitude=${longitude})` `` (187); `Unknown country code` (232,331); `Customer not found` (550); `Failed to resolve customer` (283,322); `Failed to create customer` (238,337); `Failed to fetch customer` (537); `Failed to list customers` (389,485); `Failed to count customers` (449); `Failed to fetch customer job history` (607); DTO: `name must not be empty or whitespace`, `pincode must be a valid 6-digit Indian PIN code` (common/dto/structured-address.dto.ts:53)

### Users / skills / misc
`Failed to fetch profile` (users.service.ts x8), `Failed to update profile` (418), `Failed to list skills` (skills.service.ts:57); `placeId must be 10-255 url-safe characters (A-Z, a-z, 0-9, _, -)` (places/dto/place-id-params.dto.ts:28)

### Reports API (`/reports`)
- `Company setup required before requesting reports` / `...before viewing reports` (reports.service.ts:69,236,314)
- `` `Too many reports in progress — wait for one to finish (max ${N})` `` (113,171)
- `Only a failed report can be retried` (146,189)
- `Report not found` (336); `Report file is no longer available` (352); `Failed to generate the report download link` (359)
- `` `A report can be scoped to at most ${N} technicians` `` (383); `technicianIds must all be valid technician ids` (394); `technicianIds must all be technicians of your company` (419); `technicianIds must all be employees enrolled in attendance` (attendance.definition.ts:149)
- `` `A report can be scoped to at most ${50} offices` `` (attendance.definition.ts:69); `officeIds must all be valid office ids` (76); `officeIds must all be offices of your company` (127); `officeIds is not a valid filter for this report` (technician-job-activity.definition.ts:31)
- Dates: `start_date and end_date must be real calendar dates` / `start_date cannot be after end_date` / `` `Date range cannot exceed ${N} days` `` / `end_date cannot be in the future` (report-params.util.ts:46,72,79,86)
- `` `Unknown report type '${type}'` `` (report-registry.ts:44)
- Size: `Report range contains too many jobs` (technician-job-activity.data.ts:96); `Report range contains too many employee-days` (attendance.data.ts:148)
- `Attendance is not enabled for your company` (attendance.definition.ts:107); `Failed to verify the attendance module` (101); `Failed to verify the selected offices` (122); `Failed to verify the selected employees` (143)

### Places (address autocomplete — used when typing customer address)
- `` `Too many ${label} requests. Maximum ${max} requests allowed per ${windowSeconds} seconds.` `` (label = `autosuggest`|`resolve`|`reverse`, places.service.ts:238)
- `Unable to fetch address suggestions right now` (67,81); `Unable to resolve the selected address right now` (92); `Unable to read the pinned address right now` (157)

### Internal/admin-only (brief)
Webhooks: `Unauthorized` (webhooks.service.ts:41), `Failed to process storage event` (109). Health/telemetry endpoints have no user copy.

**Note — class-validator default messages**: most punch/job DTO fields have NO custom message (src/attendance/dto/check-in-out.dto.ts:25-79, jobs/dto/advance-workflow.dto.ts:16-49, update-office.dto.ts, etc.), so 422s surface raw defaults like `latitude must not be greater than 90`, `accuracyM must be a number conforming to the specified constraints`, `provider must be shorter than or equal to 40 characters` — field-name jargon a user can trigger from the punch screen.

## 2. OTP / SMS

- **No SMS text template exists in this repo.** `OtpDeliveryProvider` is abstract (src/auth/otp-delivery.provider.ts); the only bound implementation is `MockOtpDeliveryProvider` (auth.module.ts:19-22) which logs `[MOCK OTP] Phone: ${phone}, Code: ${otp} (Valid for 5 minutes)` (mock-otp-delivery.provider.ts:10) — server log only, never user-visible. The DLT template (e.g. OTP_V1) must be configured at the SMS gateway, not here. Real send path would be a second provider implementation not in this codebase.
- Dev-only: response echoes `otp` when `OTP_DEV_ECHO=true` (auth.service.ts:123-124) — "pre-DLT dev convenience" per auth.controller.ts:41.
- Login error wording a user sees: the 5 auth strings in section 1 above.

## 3. Notifications

The `notifications` table stores NO title/body — only `event_type` + self-sufficient camelCase payload; the FE composes all display text (supabase/migrations/20260909000002_notifications_table.sql:4-6). BE-originated visible content = event types + payload values:

**Job workflow events** (owner): `event_type` = step key (`on_my_way`, `arrived`, `in_progress`, `photos_uploaded`, `signature_captured`, `completed`); payload `{ job_number, step, technician_name }` with fallback string **`A technician`** (supabase/migrations/20260909000003_rpc_notify_owner_on_advance.sql:71-80; same in 20260913000002:102-113).

**Attendance/leave events** (registry: src/attendance/notification-events.ts:14-52 with payload contracts at :82-212):
- `attendance.holiday_added` / `attendance.holiday_removed` → `{holidayName, holidayDate}` (written in migration 20260927000002:273-275, 382-384)
- `attendance.fake_location` → `{employeeName, month, attemptCount}` (check-in-out.repository.ts:214-227) — owner alerted on 3rd fake-GPS punch in month
- `leave.applied` → `{employeeName, startDate, endDate, workingDays}`; `leave.applied_on_behalf`; `leave.approved`; `leave.rejected` (adds `reason`); `leave.owner_revoked` (`revokedDates`, `reason`); `leave.employee_cancelled`; `leave.cancelled_by_disable`; `leave.checkin_auto_cancel` (writers: src/attendance/leave-transition.ts:256+)
- `attendance.reminder_checkin` → `{workDate}`; `attendance.reminder_checkout` → `{workDate, checkinAt}`; `attendance.reminder_not_checked_in` → `{officeName, notCheckedInCount, workDate}`; `leave.pending_reminder` → `{pendingCount}` (written by DB cron: migration 20260929000004_attendance_run_reminders.sql:331, 356-358, 388-391, 142)
- `report_ready` / `report_failed` → `{reportId, reportType, reportLabel, status, errorCode}` where `reportLabel` = "Attendance Report" or "Technician Job Report" (src/reports/engine/report-notifications.ts:29-44)

## 4. PDF report text

### Common chrome (src/reports/templates/brand-kit/page-header.ts)
- Header: tenant company name + address, report title, range line `` `${startDate} → ${endDate} (IST)` `` — raw ISO dates, e.g. `2026-09-27 → 2026-09-27 (IST)` (page-header.ts:81)
- Footer: `` `Created ${YYYY-MM-DD HH:mm} IST · ${confidentiality}` `` + `` `Fenzit · ${page} / ${pageCount}` `` (page-header.ts:149,155); confidentiality default `Private — contains customer details` (:123)

### Technician Job Report (FE menu: "Job & attendance reports (PDF)")
- Label/registry id: `Technician Job Report` / `technician_job_activity` (registry/technician-job-activity.definition.ts:13,23)
- Scope subtitle: `All technicians` or `` `${n} technician${s} selected · ${n} job${s} in this period` `` (template:180-191)
- Section titles: `Overall`, `Needs attention`, per-technician names (198,203,225)
- Metric cards (template:96-149): `Total jobs`; `Completed` + caption `` `${pct}% finish rate` ``; `Open`; `Cancelled` + caption `` `${pct}% drop rate` ``; `Finished on time %` + caption `No completed jobs yet`; `Urgent jobs done`; `Customers`; `Photos & signatures`
- Job table headers (brand-kit/job-table.ts:39-46, uppercased at render): `Job`, `Customer`, `Skill`, `Status`, `Planned time`, `Finish time`, `Proofs`; empty cell `—`
- Status labels (template:70-75): `Scheduled`, `In progress`, `Completed`, `Cancelled`
- "Needs attention" flags (registry/technician-job-activity.flags.ts — deliberately plain English per :7-9):
  - `Urgent job not done` → `This is an urgent job. Its planned time has passed and it is not done yet.`
  - `Not done on time` → `Work has started, but the planned time has passed.` / `The planned time has passed, but the job has not started.`
  - `No proof of work` → `The job shows as done, but no photo or signature was saved as proof.`
  - `Cancelled` → `This job was cancelled. Please check if the customer needs help.`
  - Row title `` `${kind} · ${jobNumber}` ``; detail suffix `` `— ${technicianName}` ``; fallback `Unknown technician` (:43)
- Empty state: `No jobs for these dates` (block and per-technician row, template:195,230)

### Attendance Report
- Label/registry id: `Attendance Report` / `attendance_report` (registry/attendance.definition.ts:36,58)
- Scope subtitle (template:277-285): `All offices` / `` `${n} office${s}` `` · `All employees` / `` `${n} employee${s}` `` · `` `${n} tracked` ``
- Section titles (template): `Overall` (313), `Offices` (343), `Employees — attendance` (347), `Employees — discipline & hours` (349), `Needs attention` (354), `Weekly trend` (402), `Leave summary` (427), `Rejected punches` (452)
- Overall cards (template:74-159): `Employees in scope`; `Expected working days`; `Attendance rate` + caption `Worked days ÷ expected days`; `Total worked hours` + caption `` `${x} h/day avg` ``; `Late arrivals` + caption `` `${n} min late in total` ``; `Absent days`; `Leave days`; `Missed check-outs` + caption `Hours under-counted on these days`; `Half days`; `Extra days worked` + caption `On weekly offs / holidays`; `Corrections applied`; `Fake-location attempts` + caption `` `${n} unacknowledged day flag${s}` ``
- Office table headers: `Office`, `Employees`, `Days worked`, `Absent`, `Leave`, `Late`, `Attendance`, `Worked hrs` (template:319-326)
- Employee attendance headers: `Employee`, `Office(s)`, `Joined` (cell `` `from ${d MMM}` ``), `Days worked`, `Full`, `Half`, `Absent`, `Leave`, `Off`, `Holiday`, `Extra` (template:196-206)
- Discipline headers: `Employee`, `Late days`, `Late minutes`, `Early outs`, `Missed check-outs`, `Worked hours`, `Avg hrs/day`, `Attendance`, `Corrections`, `Fake GPS` (template:212-221)
- Weekly trend headers: `Week`, `Attendance`, `Days worked`, `Absent`, `Late`, `Leave` (template:386-391). **Week label** (registry/attendance.data.ts:141-143, 297): `` `${d MMM} – ${d MMM}` `` e.g. `1 Sep – 7 Sep`; a 1-day/partial week renders just the short date — **`27 Sep`** style (`shortDate` = `` `${day} ${Mon}` ``, attendance.data.ts:135-137). Only shown when range spans >1 week (template:383).
- Day register: columns `` `${day}\n${Mon}` `` ; single-character codes (registry/attendance.metrics.ts:155-168): P, H, A, L, Hl, W, O, ★, M, `·`. Legend (template:257-260): `P present · H half day · A absent · L leave · Hl half-day leave · W worked on holiday · O weekly off · ★ holiday · M checkout missing · · not tracked / not yet`
- Needs attention items (registry/attendance.metrics.ts:228-301):
  - `Fake-location attempt` — `` `${n} day${s} with unacknowledged fake-location punches — ${30 Sep, 01 Oct}` ``
  - `Missing check-out` — `` `${n} day${s} never checked out — ${dates}` ``
  - `Absent streak` — `` `${n} consecutive days absent — ${1 Sep} to ${5 Sep}` ``
  - `Repeatedly late` — `` `Late on ${n} days — ${dates}` ``
  - `Attendance corrected` — `` `${n} day${s} corrected by the owner — ${dates}` ``
  - Overflow: `` `+${n} more — narrow the filters` `` (template:370)
- Leave summary headers: `Employee`, `Approved (days)`, `Pending (days)`, `Half-day leaves` (template:413-416)
- Rejected punches headers: `Employee`, `Too far`, `Low accuracy`, `Fake location`, `Rate-limited`, `Other` (template:434-438); footnote `Attempts shown here never became attendance records.` (template:479)
- Empty state: `No attendance data for these dates` (template:297); footer confidentiality `Private — contains employee details` (template:307,471)

## 5. Enum / status labels reaching the UI

- **Job status** raw keys: `scheduled`, `in_progress`, `completed`, `cancelled` (src/jobs/enums/job-status.enum.ts); priority `normal`/`urgent` (job-priority.enum.ts). Display mapping lives in the PDF (`Scheduled`/`In progress`/`Completed`/`Cancelled`) and presumably FE.
- **Workflow step labels** served from seed template: `On My Way`, `Arrived`, `In Progress`, `Photos Uploaded`, `Signature Captured`, `Completed` (supabase/migrations/20260911000002_workflow_templates_skill_tagged_jobs.sql:58-63); notification event_type = step keys (`on_my_way`...).
- **Day-status keys** (API returns these; FE renders them): `not_tracked`, `not_checked_in_yet`, `in_progress`, `weekly_off`, `holiday`, `worked_on_holiday`, `leave`, `half_day_leave`, `present`, `half_day`, `absent`, `checkout_missing` (src/common/day-status/keys.ts:12-23). PDF register maps them to P/H/A/L/Hl/W/O/★/M/· (metrics.ts:155-168).
- **Report statuses**: `queued`, `generating`, `ready`, `failed` (src/reports/enums/report-status.enum.ts) — visible in report history/notification payloads.
- **Report type ids + labels**: `technician_job_activity` → `Technician Job Report`; `attendance_report` → `Attendance Report` — these labels reach the user via the `report_ready`/`report_failed` notification payload (`reportLabel`).
- Job number format `JB-YYYY-NNNN` (migration 20260911000002:161); check-in/out responses return `isLate`, `earlyCheckout`, `lateMinutes`, `workedMinutes`, `dayContext{isWeeklyOff, isHoliday, holidayName, isWorkingDay}` (check-in-out.model.ts:22-41).

## 6. Seeded data visible in UI lists

- **28 skill names + descriptions** shown in the skill picker (owner invite/job create) and the `Skill` column of the job PDF: `Pipe Leak Repair`, `Drain Cleaning & Unclog`, `Water Heater Service`, `Tap & Sanitary Fitting`, `AC Installation & Removal`, `Gas Charging & Leak Check`, `Duct & Coil Cleaning`, `AC General Service`, `Electrical Wiring & Repair`, `Switchboard & Socket Installation`, `Fan & Light Installation`, `Inverter & Stabilizer Setup`, `General Pest Control`, `Termite Treatment`, `Bed Bug & Mosquito Treatment`, `Deep Home Cleaning`, `Bathroom & Kitchen Cleaning`, `Sofa & Carpet Cleaning`, `Water Tank Cleaning`, `Furniture Repair & Assembly`, `Door & Lock Repair`, `Interior Painting`, `Waterproofing`, `Washing Machine Repair`, `Refrigerator Repair`, `Microwave & Chimney Repair`, `CCTV & Doorbell Installation`, `Handyman Visit` (supabase/migrations/20260920000001_expand_skill_catalog_28.sql:41-69). No seeded office names or demo tenants found.

## 7. Suspicious jargon (backend wording a non-technical user may hit)

| String | Trigger |
|---|---|
| `Upload session expired — request a new presigned URL` | photo confirm after delay — tells user a developer action |
| `X-Idempotency-Key must be a UUID v4` / `header is required and must be a UUID v4` / `This confirmation key was already used` | punch/leave POST retry glitch |
| `Rules must be sent as a complete set: startTime, endTime, lateCutoffMinutes, fullDayHours, halfDayHours` | owner edits office rules partially |
| `You are ${n} m from ${office}. Move within ${n} m.` | punch outside geofence (compact "m", meter math — otherwise good) |
| `Too many attempts. Try again in ${n} min` / `Rate-limited` (PDF column) / `Too many OTP requests. Maximum N requests...` | rate limiting |
| `Fake GPS` (PDF column header), `unacknowledged day flags`, `unacknowledged fake-location punches` | attendance PDF |
| `Rejected punches`, `Missed check-outs`, `Early outs` | attendance PDF headers ("punches" is jargon) |
| `not tracked / not yet`, `Attendance is not active for you yet`, `Attendance is not tracked for this date`, `${n} tracked` | punch / register legend / scope line |
| `Leave state transition is not allowed` | leave action race |
| `The enrolment would leave an enrolled date without its office assignment` / `The employee has no enrolment covering the effective date` | office-assignment edits |
| `checkinAt must be an ISO-8601 instant`, `note contains invalid control characters`, `Provide exactly one of status or check-in/check-out times`, `checkoutAt is not allowed without checkinAt` | correction form |
| `Dates must be in YYYY-MM-DD format`, `startDate must be a YYYY-MM-DD date` | any date-range screen |
| `latitude must not be greater than 90`-style class-validator defaults (`accuracyM`, `fixAgeMs`, `provider`) | punch payload rejected |
| `File size exceeds the maximum of ${N} bytes` | photo too large (bytes, not MB) |
| `Invalid customer coordinates (latitude=..., longitude=...)` | customer create |
| `placeId must be 10-255 url-safe characters (A-Z, a-z, 0-9, _, -)` | address picker |
| `Invalid GSTIN format`, `countryCode must be a valid dial code (e.g. +91)` | setup/forms |
| `Employees in scope`, `A report can be scoped to at most N technicians/offices`, `narrow the filters` | reports API + PDF |
| `Report range contains too many employee-days` / `too many jobs` | huge report request |
| `Worked days ÷ expected days`, `${x} h/day avg`, `${pct}% finish rate`, `${pct}% drop rate` | PDF captions (÷ symbol, rate jargon) |
| `(IST)` in range line, `Created ... IST` footer | every PDF page |
| `Insufficient permissions` / `Forbidden` | role-gated actions |
| Notification payloads use raw keys/ISO values (`workDate: 2026-09-27`, `attemptCount`) — FE must humanize | all notifications |
