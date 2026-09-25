---
title: Attendance & Leave
status: final
created: 2026-09-25
updated: 2026-09-25
---

# PRD: Attendance & Leave

## 0. Document Purpose

This PRD defines the optional Attendance & Leave module for Fenzo (fenzo-app mobile + fenzit-be backend). It is written for the product owner and for the downstream UX, architecture and epic/story workflows.

- **Source:** a structured discussion on 2026-09-25. Every decision is logged in `.memlog.md` next to this file. The business rules were then revised with the user after backend, frontend, database, adversarial and rubric reviews (`review-*.md` next to this file).
- **Terms:** words defined in §3 Glossary are used exactly as defined everywhere else.
- **Numbering:** features are grouped in §4 with globally numbered FRs (FR-1 … FR-28). FR-27 sits under §4.9 Notifications and FR-28 under §4.11.
- **Defaults:** values Claude proposed and the user approved on 2026-09-25 are listed in §10. Rules the user delegated to Claude are marked *(decided by Claude on delegation)*.
- **Technical notes** (data model hints, scheduler, push outbox) live in `addendum.md`, not here.

## 1. Vision

Many Fenzo owners run a small business with a mix of field technicians and office staff. Today they track office attendance and leave on paper, WhatsApp or memory. Attendance & Leave gives them a simple, trustworthy way to do this inside the app they already use for jobs.

An owner switches the module on, sets up their office(s), and picks which employees need to mark attendance. Those employees check in and check out from the app, and they can only do it while physically at their office. They apply for leave from the app too, and the owner approves it in a tap. Weekly offs and festival holidays are set once and apply automatically, so nobody applies for leave on a day that is already off.

At the end of the month, the owner sees one consolidated view: for every employee, how many days they worked, when they were late, the leave they took and the holidays they had. Each employee sees the same data for themselves. There's no more arguing over who came in on which day.

## 2. Target User

### 2.1 Jobs To Be Done

- **Owner (functional):** Know every day who has come to the office and who hasn't, without calling around.
- **Owner (functional):** Handle Leave requests quickly, with a record of what was approved, rejected or revoked, and why.
- **Owner (functional):** Get an accurate month-end count of days worked per employee (decimal, half days included).
- **Owner (control):** Decide which employees need attendance tracking. Field-only technicians should not be bothered.
- **Owner (trust):** Be confident that a check-in means the employee was really at the office.
- **Employee (functional):** Mark attendance in a few seconds, and see their own attendance, leave, weekly offs and holidays.
- **Employee (emotional):** Have a fair, visible record, so late flags, leave status and revoke reasons are clear and not disputed.

### 2.2 Non-Users (v1)

- **Field-only technicians** whose owner has not enabled attendance for them. They see no attendance UI at all.
- **Owners marking their own attendance.** The Owner is not a Tracked employee.
- **Payroll / HR staff.** There's no salary calculation, payslip or statutory compliance in v1.

### 2.3 Key User Journeys

- **UJ-1. Rakesh sets up attendance for the office team.**
  - **Persona + context:** Rakesh owns a pest-control business with two offices (Andheri, Thane). He has 12 technicians, and 5 of them are office staff whose attendance he wants to track.
  - **Entry state:** Signed-in owner, on the home screen. Attendance is not enabled yet.
  - **Path:** He opens the Attendance entry point and starts the setup wizard. (1) He adds the "Andheri" office, drops a pin using his current location and sets the radius to 100 m, then adds "Thane" the same way. (2) For each office he sets start time 10:00 AM, end time 6:00 PM, late cut-off 15 min, full day ≥ 8 h and half day ≥ 4 h. (3) He changes the weekly off from Sunday to Sunday + Saturday. (4) He skips holidays for now. (5) He selects 3 employees for Andheri and 2 for Thane.
  - **Climax:** The wizard finishes. The dashboard shows "5 employees tracked · 0 checked in today".
  - **Resolution:** Attendance is live for those 5 from today. The other 7 Employees see no change.
  - **Edge case:** Rakesh tries to enable an employee without picking an office, and the wizard blocks it: every Tracked employee needs one Office.

- **UJ-2. Priya checks in, late, and later checks out.**
  - **Persona + context:** Priya is an office coordinator at the Andheri Office. Attendance was enabled for them yesterday.
  - **Entry state:** First time opening the Attendance entry point.
  - **Path:** The employee onboarding shows a short intro and asks for location permission. It then shows the Andheri Office, 10:00 AM – 6:00 PM, and Weekly offs Sat + Sun. At 10:22 AM Priya taps Check in. The app gets their GPS location (accuracy 20 m, 40 m from the Office pin) and the Check-in succeeds with a **Late** flag (22 min).
  - **Climax:** The screen shows "Checked in 10:22 AM · Late by 22 min", and the Owner's dashboard shows the same.
  - **Resolution:** At 6:22 PM (End time + 22 min late) an in-app "You haven't checked out" reminder is created. Priya sees it when they open the app at 6:30 PM and checks out. The day shows 8 h 08 m, **Present**. (There's no push in v1, so a Reminder is seen only when the app is opened.)
  - **Edge case:** At 10:05 AM Priya tapped Check in from the bus stop, 600 m away. It was blocked with "You are 600 m from Andheri office. Move within 100 m to check in."

- **UJ-3. Arjun applies for leave, Rakesh approves, then revokes part of it.**
  - **Persona + context:** Arjun, office staff at Thane, needs Mon–Fri off for a family function.
  - **Path:** Arjun opens Leave → Apply, picks Mon–Fri full day and types a reason. The app shows "5 working days". Rakesh gets an in-app Notification, opens it and approves. Arjun is notified. On Wednesday of that week Rakesh needs Arjun back, so he revokes the leave with the reason "Audit visit Thursday".
  - **Climax:** Mon–Wed stay as **Leave**. Thu–Fri become normal working days. A notification is created for Arjun, and when Arjun next opens the app (the same evening) they see "Revoked (Thu–Fri): Audit visit Thursday". Rakesh also calls Arjun, since without push the app can't guarantee Arjun sees it in time.
  - **Resolution:** Arjun checks in on Thursday as normal.
  - **Edge case:** If Arjun had cancelled the leave on Wednesday instead, only Thu–Fri could be cancelled. Rakesh would get a "Leave cancelled" notification.

- **UJ-4. Rakesh reviews the month.**
  - **Path:** On the 1st, Rakesh opens Attendance → Monthly view for last month. He sees a list of Tracked employees with each person's month totals. For Priya, in a 30-day month with Sat + Sun off and one Holiday: 21 Working days = 17 Present + 1 Half day + 2 Leave + 1 Checkout missing, so Days worked = 17.5, plus Late 3, Weekly offs 8, Holidays 1, Worked on holiday 1 (a Saturday, full day), Absent 0. He taps Priya to open their calendar, sees the **Checkout missing** flag on the 14th and corrects it to Present with the note "Forgot to check out, confirmed with Priya". The audit trail records his change.
  - **Climax:** The summary updates: Days worked 18.5, Checkout missing 0.

- **UJ-5. Priya checks their own record.**
  - **Path:** Priya opens My Attendance and sees this month's calendar with a status for each day, their weekly offs, upcoming holidays, their Leave requests with status (Pending / Approved / Rejected / Revoked with reason / Cancelled), and "Days worked: 14.5 so far".

## 3. Glossary

- **Owner** — The existing `owner` role. Owns one tenant. Sets up and oversees attendance. The Owner is not attendance-tracked.
- **Employee** — An existing `technician`-role user in the owner's tenant. No new role is created; office staff are technicians in the system.
- **Tracked employee** — An Employee for whom the Owner has enabled attendance, from an effective date. Assigned to exactly one Office at any point in time.
- **Office** — A named work location of the tenant: pin (lat/long), Radius, Start time, End time, Late cut-off, Hours rules. A tenant has one or more Offices.
- **Radius** — Distance in metres from the Office pin inside which Check-in and Check-out are allowed.
- **Start time / End time** — The Office's working hours on a working day, in Tenant timezone.
- **Late cut-off** — Grace minutes after Start time. Default 15.
- **Midpoint** — The halfway time between an Office's Start time and End time (10:00 AM – 6:00 PM → 2:00 PM). It splits the day for Half-day leave.
- **Expected start** — Start time on a normal Working day. On a First-half leave day it is the Midpoint.
- **Expected end** — End time on a normal Working day. On a Second-half leave day it is the Midpoint.
- **Late** — A flag on a Check-in made after Expected start + Late cut-off. It records the minutes late.
- **Early checkout** — A flag on a Check-out made before Expected end.
- **Hours rules** — Office-level thresholds: Full-day hours and Half-day hours. They map worked hours to a Day status.
- **Check-in / Check-out** — One pair per Tracked employee per calendar day, each validated against the Office Radius.
- **Worked hours** — Check-out time minus Check-in time.
- **Day status** — The status of one Tracked employee for one date. Final statuses: Present, Half day, Absent, Leave, Half-day leave, Weekly off, Holiday, Worked on holiday, Checkout missing, Not tracked. Today-only (not final) statuses: Not checked in yet, In progress (checked in, not yet checked out).
- **Days worked** — A decimal sum over a period: Present = 1, Half day = 0.5, the worked half of a Half-day leave day = 0.5 (if earned), Checkout missing = 0 until corrected. Worked on holiday is counted separately.
- **Working day** — A date that is not a Weekly off and not a Holiday for that Tracked employee.
- **Weekly off** — Day(s) of the week that are non-working. Set as a tenant default (Sunday unless changed) with an optional per-Employee override. Effective-dated.
- **Holiday** — A fixed-date non-working day (for example a festival) set by the Owner. It applies to all Tracked employees.
- **Leave request** — A request for a date range (or one date), either full day or half day (First half / Second half), with a reason. It keeps its requested range; Weekly offs and Holidays only decide which dates in the range count as leave. Each date in the range has its own state: Pending, Approved, Rejected, Cancelled or Revoked, so a partial revoke or cancel changes only some dates.
- **Revoke** — An Owner action on an Approved Leave request for future dates. A reason is required.
- **Cancel** — An Employee action on a Pending or Approved Leave request for dates that have not started.
- **Attendance correction** — A manual change by the Owner to Check-in/Check-out times, or a direct Day status set to Present, Half day or Absent, with a required note, recorded in the audit trail. A correction always wins over automatic recalculation.
- **Removed employee** — A technician taken out of the tenant. No remove option exists today; §4.11 defines the rules for when it is built.
- **Reminder** — An in-app Notification created by a scheduled job at defined times.
- **Notification** — A row in the existing in-app notifications system (an inbox, not a permanent record; old rows are cleaned up after 30–90 days), delivered in real time to the recipient while the app is open.
- **Tenant timezone** — The tenant's IANA timezone (default `Asia/Kolkata`). It defines "today", midnight and all Office times. All Offices of a tenant share it.

## 4. Features

### 4.1 Attendance enablement & onboarding

**Description:** Attendance is off by default for every tenant. The Owner turns it on through a setup wizard. After setup the Owner can enable or disable attendance for any Employee at any time, individually or for all of them at once. Realises UJ-1, UJ-2.

#### FR-1: Owner enables the module through a setup wizard
The Owner can enable Attendance & Leave for their tenant through a guided wizard: (1) add Office(s), (2) set Start time, End time, Late cut-off and Hours rules per Office, (3) set the tenant default Weekly off, (4) add Holidays (optional, can skip), (5) select Employees and assign each to an Office. Realises UJ-1.

**Consequences (testable):**
- The wizard can't be finished without at least one Office and at least one Tracked employee.
- Every selected Employee must have an Office before the wizard finishes.
- The wizard progress is saved on the server after each step, so it survives closing the app or switching phones (resume at the last incomplete step).
- Until the wizard is completed, no Employee sees any attendance UI.

#### FR-2: Owner enables or disables attendance per Employee or for all
The Owner can enable attendance for all Employees or a selected subset, and can disable it for any Tracked employee.

**Consequences (testable):**
- When enabling, the Owner picks a **start date**: today (default) or any future date (for example a new joiner's first day, 1 Nov). Dates before it show as **Not tracked**, not Absent.
- An Employee can be enabled with a future start date before they have ever logged in (an invited technician). The Office and any Weekly off override can be set up in advance.
- Before the start date: no Reminders, no Absent marks, and the Employee doesn't appear in the Owner's not-checked-in summaries. From the start date, tracking begins automatically with no Owner action.
- The Owner can change or cancel a future start date any time before it arrives.
- If enabled after today's Start time, today is **Not tracked** unless the Employee checks in today (then it's evaluated as normal). Nobody is marked Absent on the day they are enabled.
- Disabling keeps all history, now read-only. Dates after disabling show as Not tracked.
- Re-enabling later starts a new tracked period. The gap shows as Not tracked.
- New Employees added to the tenant later are not tracked automatically.
- Only an Owner of the same tenant can change enablement (enforced server-side).

#### FR-3: Attendance entry points appear only when relevant
The Owner always sees the Attendance entry point (before setup it opens the setup wizard). An Employee sees it while they are a Tracked employee, or in history-only mode after being disabled.

**Consequences (testable):**
- An untracked Employee has no attendance screens, reminders or attendance notifications. The shared notification bell (FR-27) is still shown.
- An Employee who was tracked before can still view their own past records (read-only) after being disabled.
- The Employee's attendance access has four states: **none** (never tracked, no entry point), **upcoming** (start date in the future), **active** and **history only**.
- In the upcoming state, the Employee sees "Attendance starts on {date}" with their Office, timings and Weekly offs. They can finish onboarding (FR-4) early but can't check in yet. The app refreshes this state when it comes to the foreground and when an attendance Notification arrives, so the entry point never flickers or goes stale.

#### FR-4: Employee onboarding on first entry
On first entry, a Tracked employee sees a short intro, a request for location permission, and a summary screen showing their Office, Start/End time, Late cut-off and Weekly offs. Realises UJ-2.

**Consequences (testable):**
- If location permission is denied, the Employee can still view their records and apply for leave. Check-in/Check-out shows how to grant the permission.
- Onboarding shows once per Employee. The summary screen stays reachable later.

### 4.2 Offices & attendance rules

**Description:** An Office holds the location and the timing rules. All timing rules are Office-level only, with no per-Employee override. Realises UJ-1.

#### FR-5: Owner manages Offices
The Owner can create, edit and archive Offices. For each: name, pin (current location or picked on a map), Radius, Start time, End time, Late cut-off, Full-day hours, Half-day hours.

**Consequences (testable):**
- Pin selection offers three ways, all ending on the same map screen: (a) "Use my current location", (b) search an address (existing address search), (c) drag the pin on the map. The map shows the Radius as a circle around the pin, and the circle updates live as the Radius changes.
- The saved pin is the map pin's final position, not the search result's raw coordinates.
- Editing an existing Office opens the same map with the current pin and circle.
- If the map fails to load (no network or a map error), the Owner can still save using current location or address search, and sees a message that the map is unavailable.
- Radius range is 50–1000 m, default 100 m.
- Late cut-off default is 15 min, range 0–120 min.
- Defaults: Full-day hours 8, Half-day hours 4. Validation: both must be more than 0, and Half-day hours must be less than Full-day hours. They are not checked against the Office's working hours.
- End time must be after Start time on the same day (no overnight Offices).
- Changes to timing and Hours rules apply from **tomorrow**. Today and all past dates keep the rules that were active on that date (Office rules are stored with effective dates).
- An Office with Tracked employees assigned can't be archived until they are reassigned. Removed employees (§4.11) don't block archiving.
- The map uses Apple Maps on iOS and Google Maps on Android.

#### FR-6: Owner assigns each Tracked employee to one Office
The Owner can assign and reassign a Tracked employee's Office.

**Consequences (testable):**
- A Tracked employee has exactly one Office on any date.
- Reassignment is effective from the date it's made, or from a future date the Owner picks (for example "move to Thane from 1 Nov"). Past records keep the old Office.
- If the change is made after the Employee has checked in today, it applies from tomorrow.

### 4.3 Check-in & Check-out

**Description:** A Tracked employee marks one Check-in and one Check-out per day, only from inside their Office Radius, with a good GPS fix and a working network. The server, not the app, decides whether the location is valid. Realises UJ-2.

#### FR-7: Employee checks in
A Tracked employee can Check in once per day when inside their Office Radius.

**Consequences (testable):**
- The server computes the distance from the submitted coordinates to the Office pin. If distance > Radius, the request is rejected with the distance and the Radius, for example "You are 600 m from Andheri office. Move within 100 m."
- If GPS accuracy is worse than 100 m, it's rejected with a "Location not accurate enough, try again in the open" message.
- **Fake GPS (Android and iOS 15+):** if the device reports the location as mocked or simulated by software (a fake-GPS app or tool is active), the Check-in is rejected with "Turn off fake location apps to check in". The app sends the flag to the server, and the server makes the decision.
- The app uses a fresh, high-accuracy GPS reading for every attempt (never an old cached location), and needs precise location permission. If the Employee allowed only approximate location, the app explains how to turn on precise location.
- Every rejected attempt (distance, accuracy or fake location) is still recorded, with Employee, time, coordinates, reason and Office. The Owner sees a "Fake location attempt" flag on that Employee's day in the dashboard and monthly view.
- If an Employee has 3 or more fake-location attempts in a calendar month, the Owner also receives a Notification. It is sent once per Employee per month, on the 3rd attempt.
- **Rate limit:** after 5 rejected attempts within 10 minutes, the Employee must wait 10 minutes before trying again, with a clear message. This stops anyone from using the "you are X m away" message to hunt for a working fake location. *(Values decided by Claude on delegation.)*
- Offline → blocked in the app with a clear message. There's no queued or offline check-in.
- A second Check-in on the same day is rejected. Repeated taps are safe: the same request replayed does not create duplicates (idempotent). This is guaranteed by the database, not only by the app.
- Check-in is allowed on any day, including Weekly offs and Holidays (that day becomes **Worked on holiday**). On a Weekly off or Holiday the app first asks "It's a holiday. Check in anyway?"
- Check-in is allowed before Start time.
- A Check-in after Expected start + Late cut-off gets the **Late** flag with the minutes late. On a First-half leave day, Expected start is the Midpoint (for 10:00 AM – 6:00 PM, Late after 2:15 PM). There's no Late flag on a Weekly off or Holiday.
- Stored with the Check-in: server timestamp, lat/long, accuracy, distance and Office. The device clock is never trusted.

#### FR-8: Employee checks out
A Tracked employee who has checked in today can Check out once, when inside the same Office Radius.

**Consequences (testable):**
- Same location, accuracy, fake GPS, offline and idempotency rules as FR-7.
- Check-out before Expected end gets the **Early checkout** flag. On a Second-half leave day, Expected end is the Midpoint (for 10:00 AM – 6:00 PM, Early checkout before 2:00 PM).
- After Check-out, the app shows the Worked hours (for example "8 h 08 m").
- Check-out without a Check-in that day is rejected.

#### FR-9: Check-in on a leave day
If a Tracked employee checks in on a date with an Approved or Pending full-day Leave, the Check-in is allowed after the Employee confirms.

**Consequences (testable):**
- Before checking in, the app asks "You're on leave today. Checking in will cancel today's leave. Continue?"
- On confirm, that date's leave (Approved or Pending) is auto-cancelled and the Day status comes from attendance as normal.
- The Owner receives a Notification ("Arjun checked in during approved leave; leave for {date} cancelled").
- For a multi-day leave, only that date is removed. The rest stays Approved.
- On a Half-day leave date, Check-in is allowed as normal (the working half), with no auto-cancel.

**Out of Scope:** multiple check-in/out pairs per day (lunch breaks), night shifts crossing midnight, check-in at customer sites.

### 4.4 Day status & Days worked

**Description:** For each Tracked employee and each date, the system computes one Day status from Weekly offs, Holidays, Leave, attendance and Hours rules. Realises UJ-4, UJ-5.

#### FR-10: Day status rules
The system works out the Day status using this order (first match wins):

1. An Attendance correction set a status directly → that status (Present, Half day or Absent). **A correction always wins**, even when Holidays, Weekly offs or leave change later.
2. Not a tracked date (including the enable-day rule in FR-2) → **Not tracked**.
3. Weekly off or Holiday with a Check-in → **Worked on holiday**, graded with the same Hours rules: Worked hours ≥ Full-day hours → full day; ≥ Half-day hours → half day; below → shown with the hours but counted 0; no Check-out by midnight → counted 0 until corrected.
4. Weekly off → **Weekly off**. Holiday → **Holiday**. If both apply, Holiday is shown.
5. Approved full-day Leave (no Check-in) → **Leave**.
6. Approved Half-day leave → **Half-day leave**. The leave half counts 0.5 leave. The working half counts 0.5 worked if Worked hours ≥ Full-day hours ÷ 2, otherwise 0. No Check-out by midnight → the working half counts 0 until corrected, and the Checkout missing flag is shown.
7. Check-in and Check-out → Worked hours ≥ Full-day hours → **Present**. ≥ Half-day hours → **Half day**. Otherwise → **Absent** (the hours are still shown).
8. Check-in with no Check-out by midnight (Tenant timezone) → **Checkout missing**, counted **0** until the Owner corrects it.
9. Working day, date has passed, no Check-in and no Approved leave → **Absent**. This includes dates covered by a Pending leave: they show as Absent with a "Leave pending" marker until the Owner acts. If the Owner approves, they become **Leave**.
10. Today, no Check-in yet → **Not checked in yet**. Today, checked in but not checked out → **In progress**. Neither is final or counted until midnight.

**Consequences (testable):**
- Every Tracked employee-date has exactly one Day status.
- Late and Early checkout are flags on top of the status. They never change the status.
- A Leave request keeps its full requested range. Adding a Holiday (or a Weekly off change) inside the range stops that date counting as leave. Removing the Holiday makes that date **Leave** again.
- Adding or removing a Holiday, or making an Attendance correction, updates the affected dates immediately, including past dates (no month lock in v1). Past dates are always evaluated with the Office rules and Weekly offs that were active on that date.
- For any Tracked employee and month, the Day status counts add up to the number of tracked days in that month.

#### FR-11: Days worked calculation
The system calculates Days worked for any period as a decimal (Present 1, Half day 0.5, worked half of Half-day leave 0.5 if earned, Checkout missing 0 until corrected). Worked on holiday is counted and shown separately (full day 1, half day 0.5), not mixed into Days worked.

**Consequences (testable):**
- The totals shown to the Owner and to the Employee for the same period match exactly.

### 4.5 Leave management

**Description:** There's a single leave type with no quota. Leave can be full day or half day (First half / Second half), and a request can span multiple dates. Only Working days are counted. Realises UJ-3.

#### FR-12: Employee applies for leave
A Tracked employee can apply for leave: date range (or a single date), full day or half day (First/Second half for single-date half days), and a reason.

**Consequences (testable):**
- The app shows the number of Working days in the range (for example "Fri–Tue = 3 working days" with Sat–Sun off). Weekly offs and Holidays inside the range are excluded and don't count as leave.
- A request where every date is a Weekly off or Holiday is rejected ("These days are already off").
- Past dates are allowed up to 7 days back, but never before the Employee's start date. Past-date and future requests both need Owner approval.
- An upcoming Employee can apply for leave only for dates on or after their start date.
- A past date where the Employee has a Check-in can't be requested as leave.
- A request that overlaps a Pending or Approved leave of the same Employee is rejected.
- Half-day leave applies to a single date only.
- The reason is required, free text, max 500 characters.
- The Owner receives a Notification on submission.

#### FR-13: Owner approves or rejects leave
The Owner can Approve or Reject a Pending Leave request. A reason is optional on Reject.

**Consequences (testable):**
- The Employee receives a Notification with the outcome (and the reason, if given).
- Only Pending requests can be approved or rejected. Two simultaneous actions on the same request resolve to exactly one outcome (atomic state change).
- A Pending request never auto-expires, even after its dates have passed. It stays Pending until the Owner acts. Until approval, those dates count as **Absent** (with a "Leave pending" marker). On approval, they become **Leave** and the totals update.

#### FR-14: Owner revokes approved leave
The Owner can Revoke an Approved Leave request for dates that have not started yet, with a required reason.

**Consequences (testable):**
- Only future dates (after today) can be revoked. Today can also be revoked if the Owner acts before the Office Start time. After Start time, today's leave is treated as started and can't be revoked. *(Cut-off decided by Claude on delegation.)*
- For a leave already in progress, only the remaining future dates are revoked. The past or current part stays Approved (the request is split).
- Revoked dates become normal Working days.
- The Employee receives a Notification and sees the status **Revoked** with the reason and the revoked dates.

#### FR-15: Employee cancels leave
A Tracked employee can Cancel a Pending or Approved Leave request for dates that have not started.

**Consequences (testable):**
- Pending → Cancelled entirely, if no date has passed.
- Approved and not started → Cancelled entirely. Approved and in progress → only the remaining future dates are cancelled (split).
- Today can be cancelled only before the Office Start time (the same cut-off as FR-14).
- The Owner receives a Notification.

#### FR-16: Owner applies leave on behalf of an Employee
The Owner can create a Leave request for a Tracked employee. It is Approved immediately.

**Consequences (testable):**
- The same rules as FR-12 apply (Working days only, 7-day back-date limit, no overlap, no Check-in on those dates).
- The Employee receives a Notification.
- It can be revoked like any Approved leave (FR-14).

#### FR-17: Leave history and status visibility
The Employee sees all their Leave requests with status (Pending / Approved / Rejected / Cancelled / Revoked), dates, Working-day count and reasons. The Owner sees the same for all Employees, with a Pending queue.

### 4.6 Weekly offs

#### FR-18: Tenant default Weekly off
The Owner can set the tenant default Weekly off day(s). The default is Sunday. Any combination of weekdays is allowed (for example Friday + Saturday).

**Consequences (testable):**
- The change is effective from a date the Owner picks (default today). Dates before it are unchanged.
- At least one working day per week must remain.

#### FR-19: Per-Employee Weekly off override
The Owner can set a Weekly off override for one or more Tracked employees. The override wins over the tenant default.

**Consequences (testable):**
- Effective-dated, same as FR-18.
- The Owner can remove an override, and the Employee falls back to the tenant default from that date.
- Each Employee can see their current and upcoming Weekly offs.

### 4.7 Holidays

#### FR-20: Owner manages Holidays
The Owner can add, edit and remove Holidays (date + name). They apply to all Tracked employees.

**Consequences (testable):**
- Past dates can be added or removed. Affected Day statuses are recomputed (FR-10).
- Adding a Holiday on a date that is inside an Approved leave removes that date from the leave count. The Employee receives a Notification.
- Removing a Holiday that falls inside a Leave request's range makes that date **Leave** again (the leave keeps its requested range). The Employee receives a Notification.
- A Holiday on a date with an Attendance correction doesn't change that date (the correction wins).
- All Tracked employees are notified when a new future Holiday is added.
- Employees see the list of upcoming Holidays.

**Out of Scope:** preset national/festival holiday lists; Holidays for a subset of Employees.

### 4.8 Attendance corrections

#### FR-21: Owner corrects attendance
The Owner can correct a Tracked employee's attendance for any past or current date: set or change Check-in/Check-out times, or set the Day status directly to **Present**, **Half day** or **Absent** (for example Checkout missing → Present). A note is required. To mark leave, the Owner uses leave on behalf (FR-16). Holiday and Weekly off come only from settings.

**Consequences (testable):**
- Every correction is stored in an audit trail: who, when, old value, new value and the note. The audit trail is visible to the Owner. The Employee sees that the day was "Corrected by owner" along with the Owner's note.
- Corrected times skip the location check (they're marked as "manual").
- Corrections never delete the original Check-in/Check-out record.
- A correction works even on a date with no Check-in at all (for example an Absent day corrected to Present).
- A correction always wins over later automatic changes (Holidays, Weekly offs). The Owner can correct it again.
- Checkout missing days show as a flag on the Owner dashboard until they are corrected.

### 4.9 Notifications & reminders

**Description:** All notifications are in-app, using the existing notifications system with real-time delivery. Each event has a stable event type and a self-contained payload, so push notifications can be added later without redesign. Realises UJ-2, UJ-3.

#### FR-22: Attendance & leave notifications

| Event | Recipient |
|---|---|
| Leave applied | Owner |
| Leave approved / rejected | Employee |
| Leave revoked (with reason and dates) | Employee |
| Leave cancelled by Employee | Owner |
| Leave applied by Owner on behalf | Employee |
| Leave auto-cancelled due to Check-in | Owner |
| Repeated fake-location attempts (3rd in a month) | Owner |
| New Holiday added (future date) | All Tracked employees |
| Holiday added over approved leave | Employee |
| Holiday removed inside a leave range (date is Leave again) | Employee |

**Consequences (testable):**
- A Notification is created in the same atomic operation as the state change. No state change goes without its Notification, and no Notification is sent for a change that failed. The one exception is the fake-location alert: it is recorded together with the rejected attempt that triggered it.
- Tapping a Notification opens the related leave or day.
- In v1 (no push), a Notification is seen only when the recipient opens the app. The app shows new Notifications live while it is open.

#### FR-23: Reminders
The system creates in-app Reminders:

| Reminder | Recipient | When |
|---|---|---|
| "You haven't checked in" | Tracked employee | Expected start + Late cut-off, on a Working day, with no Check-in and no full-day leave (on a First-half leave day: Midpoint + Late cut-off) |
| "You haven't checked out" | Tracked employee | Expected end + actual minutes late (for example check-in 10:40 AM, late by 40 min → reminder at 6:40 PM; on a Second-half leave day, Midpoint + minutes late), if still not checked out |
| Daily not-checked-in summary | Owner | Once per Office per day at Start time + Late cut-off, for example "3 employees haven't checked in at Andheri" |
| Pending leave requests | Owner | Once a day at 10:00 AM (Tenant timezone), if there are any Pending requests |

**Consequences (testable):**
- Each Reminder is created at most once per recipient per day per type (per Office for the Owner summary). The database guarantees this, so a re-run job never creates duplicates.
- No Reminders for untracked Employees, or on Weekly offs or Holidays.
- A Reminder appears in the in-app notification list. Like every Notification in v1, it is seen only when the app is opened (FR-22).

#### FR-27: Technician notification inbox (reuses the Owner inbox)
Every technician gets an in-app notification inbox with an unread badge. It's the **same** notifications screen and backend the Owner uses today, made role-aware. It is not a second, separate inbox. The technician receives their attendance/leave Notifications and Reminders in real time.

**Consequences (testable):**
- One shared notifications screen and one backend (list, unread count, mark read, realtime) serve both Owner and technician. The only role differences are which events appear and where a tap leads.
- Notifications that aren't about a job (attendance, leave, reports) always appear in the list. The unread badge count always matches what the list shows.
- A leave or attendance event never shows a job banner or triggers a job refresh.
- A technician sees only their own Notifications (enforced server-side, including the realtime channel).
- Tapping an attendance/leave Notification opens the related leave request or day, never a job screen. Job notifications keep opening the job.
- The bell and badge are visible to **every** technician from day one, whether they are tracked or not. An untracked technician with no Notifications sees an empty state ("No notifications yet").
- Existing Owner job and report notifications look and behave exactly as before.

**Out of Scope:** new job-related notifications for technicians (for example "job assigned to you"). The shared inbox makes these easy to add later.

### 4.10 Views & summaries

#### FR-24: Owner dashboard (today)
The Owner sees today's snapshot: number of Tracked employees, In progress (checked in), Not checked in yet, Late, on leave, plus flags from past days until handled: Checkout missing and Fake location attempt. It can be filtered by Office. Realises UJ-1.

#### FR-25: Owner monthly consolidated view
The Owner's monthly view opens as a **list of Tracked employees**, each with their month summary: Days worked, Half days, Late count, Leave (days, with half days as 0.5), Weekly offs, Holidays, Worked on holiday, Absent, Checkout missing. Tapping an Employee opens their **month calendar** (Day status and Late/Early flags per date). It can be filtered by Office. Realises UJ-4.

**Consequences (testable):**
- Tapping a date in the calendar shows that day's detail: Check-in/Check-out times, Worked hours, distance, flags, leave and correction history.
- It supports any past month since the module was enabled.
- Loading, empty and error/offline states are all handled explicitly (skeleton while loading).
- Every Day status and flag has its own colour and label from the design system, and never relies on colour alone (accessibility).

#### FR-26: Employee self view
A Tracked employee sees their own monthly calendar (Day status per date, flags), today's Check-in/Check-out state, month summary (same fields as FR-25), Weekly offs, upcoming Holidays and leave history. Realises UJ-5.

**Consequences (testable):**
- The Employee can only ever see their own data (enforced server-side).

### 4.11 Removed employees (future-ready rules)

**Description:** There's no option to remove a technician today, and building one is out of scope. These rules apply once removal exists.

#### FR-28: Attendance rules when a technician is removed
When a technician is removed from the tenant, attendance handles it automatically.

**Consequences (testable):**
- Attendance is turned off from the removal date. Later dates show as Not tracked.
- All attendance and leave history is kept, and the Owner can still see it in the monthly view and summaries. Nothing is deleted.
- Pending leave and future Approved leave are cancelled automatically. No Notification goes to the removed technician.
- Reminders stop, and the technician no longer appears in Owner summaries for dates after removal.
- An Office whose only assigned Employees are Removed employees can be archived.

## 5. Cross-Cutting NFRs

- **NFR-1 Tenant isolation & least privilege.** Every attendance, leave, office, holiday and audit record belongs to one tenant. Row-level security is deny-by-default. An Employee reads only their own records, and an Owner reads only their own tenant's. No service-role key in the app. Every Employee, Office or leave ID sent by the app is checked on the server to belong to the caller's tenant (and to the caller, for an Employee). New attendance database functions can be called only by the backend, never directly with the app's public key. The same gap in existing job functions (public EXECUTE on the job RPCs, and the `users_update_own` policy with no column limit) is fixed in this initiative as a prerequisite story, merged before FR-27 gives technicians a realtime token and before the app's attendance release (architecture AD-18).
- **NFR-2 Server authority.** Location validation, timestamps, Late/Early flags, Day status and Days worked are computed on the server. The client is never trusted for time or for status.
- **NFR-3 Atomicity & idempotency.** Check-in, Check-out, every leave state change and its Notification each happen atomically. Check-in/Check-out and leave submission require an idempotency key, and database constraints are the final guard, so retries or double taps never create duplicates. Concurrent actions on the same Employee (for example check-in vs leave approve, or revoke vs cancel) are serialised, so they resolve to one consistent outcome.
- **NFR-4 Integrity constraints.** Database constraints enforce: one Check-in/Check-out pair per Tracked employee per date, one Office per Tracked employee per date, no overlapping effective-dated rules (enrolment, Office rules, Weekly offs), no overlapping leave dates for an Employee, valid radius/time ranges, and valid leave state transitions.
- **NFR-5 Timezone.** All dates and times are evaluated in the Tenant timezone (a stored field, default `Asia/Kolkata`). Timestamps are stored in UTC. Moving to non-IST tenants later needs no schema change. The timezone value is validated as a real IANA name. "Today" and date boundaries are worked out in one place, on the server, and the app displays the dates and times the server sends (12-hour format, for example 10:00 AM).
- **NFR-6 Auditability.** Attendance corrections and all leave transitions are recorded with actor, time and reason, and are never hard-deleted.
- **NFR-7 Performance.** Check-in/Check-out responds in ≤ 2 s p95 on a 4G network, excluding GPS fix time. The monthly view for up to 50 Tracked employees loads in ≤ 3 s p95.
- **NFR-8 Resilience (app).** Offline, timeout and GPS-failure states show clear messages with a retry option. The app detects offline state before a check-in attempt. The screen never freezes. Loading skeletons are shown for all lists and calendars.
- **NFR-9 Observability.** Rejected check-ins (distance, accuracy, fake location, rate limit), reminder job runs and failures are logged and exposed as metrics (existing telemetry). Logs never contain raw coordinates beyond what's needed for debugging.
- **NFR-10 Push-ready.** Every Notification has a stable event type and a self-contained payload, and uses the existing push-outbox marker. Adding push later needs no change to the attendance logic. Each event type carries a push priority, so push can be switched on in waves *(waves decided by Claude on delegation)*:
  - **Wave 1 (time-sensitive, action needed):** leave applied, leave cancelled, repeated fake-location attempts (Owner); leave approved, rejected or revoked, leave applied on behalf (Employee); "haven't checked in" and "haven't checked out" reminders (Employee).
  - **Wave 2 (informational):** daily not-checked-in summary and pending-leave reminder (Owner); leave auto-cancelled due to Check-in (Owner); Holiday added, and Holiday added over approved leave (Employee).
- **NFR-11 Privacy.** Location is captured only at the moment of Check-in/Check-out, never tracked in the background. The Employee is told this during onboarding.
- **NFR-12 Separate module from the field (jobs) flow.** Attendance & Leave is its own module in both repos, with its own entry point, screens, navigation stack, API routes, tables and notification event types. It does not reuse or change the job/workflow location-capture flow, job screens, job notifications or job reports. Turning it off (or never enabling it) leaves the field flow exactly as it is today. Shared building blocks (design system components, the location permission helper, the notifications list) may be reused as-is. The only allowed change to shared code is making it generic without changing its behaviour.

## 6. Non-Goals (Explicit)

- Not a payroll or HR system: no salary, payable days, payslips, PF/ESI or statutory reports.
- Not a location-tracking tool: no background location, route tracking or geofence alerts.
- Not linked to jobs: attendance doesn't gate job start and doesn't appear in job flows.
- Not for travel or site work: check-in happens only at the assigned Office.
- No new roles (manager, HR). Only Owner and Employee.

## 7. MVP Scope

### 7.1 In Scope
- Setup wizard, per-Employee or bulk enablement with a start date (today or future), Employee onboarding (FR-1 – FR-4).
- Multiple Offices with Radius, Start/End time, Late cut-off and Hours rules, and a pin set on a map (drag pin, Radius circle) or by current location or address search. One Office per Tracked employee (FR-5, FR-6).
- Check-in/Check-out with server-side radius, accuracy, fake-GPS (Android and iOS 15+) validation, rate limiting, Late and Early checkout flags (FR-7 – FR-9).
- Day status engine and decimal Days worked (FR-10, FR-11).
- Full leave lifecycle including half day, past-date leave, on-behalf leave, partial revoke/cancel (FR-12 – FR-17).
- Weekly offs (tenant + per-Employee, effective-dated) and Holidays (FR-18 – FR-20).
- Owner corrections with audit trail (FR-21).
- In-app notifications, scheduled Reminders and the technician notification inbox (FR-22, FR-23, FR-27).
- Owner dashboard, monthly Tracked employee list with per-Employee calendar, Employee self view (FR-24 – FR-26).
- Rules for Removed employees, ready for when removal is built (FR-28).
- Security prerequisite for FR-27: revoke public EXECUTE on the existing job RPCs and column-limit `users_update_own` (from `deferred-work.md`, 2026-09-25), shipped before the technician realtime token.

### 7.2 Out of Scope for MVP
- Push notifications. Deferred until push is built at the app level; the design is push-ready (NFR-10).
- Export (PDF/Excel) of the monthly view. Deferred; it could use the existing reports module.
- Leave types, leave quota and balances.
- Per-Employee shift timings, multiple shifts, night shifts, multiple check-in/out pairs per day.
- Late penalties (for example 3 lates = half day).
- Month lock / payroll close.
- Selfie or photo at check-in. Rooted/jailbroken device detection. Fake-GPS detection on iOS below 15 (the app's minimum is 15.1, so this affects no supported device).
- A "remove technician" feature (FR-28 only defines the attendance rules for it).
- Preset national/festival holiday list, and Holidays for a subset of Employees.
- Per-Office timezone.
- Owner self-attendance.
- Offline check-in.

## 8. Success Metrics

**Primary**
- **SM-1: Adoption.** % of active tenants that have ≥ 1 Tracked employee within 60 days of launch. Target: 30%. Validates FR-1, FR-2.
- **SM-2: Daily marking rate.** % of Tracked employee Working days with a Check-in (excluding leave). Target: ≥ 85% by month 2 (v1 has no push, so reminders only help when the app is opened). Validates FR-7, FR-23.

**Secondary**
- **SM-3: Leave turnaround.** Median time from leave applied to approved/rejected. Target: < 24 h. Validates FR-12, FR-13, FR-22.
- **SM-4: Checkout completeness.** % of checked-in days that end with a Check-out (not Checkout missing). Target: ≥ 90%. Validates FR-8, FR-23.
- **SM-5: Correction rate.** Attendance corrections per 100 Tracked employee-days. Watched as a data-quality signal; a falling trend is good. Validates FR-21.

**Counter-metrics (do not optimise)**
- **SM-C1: Check-in rejection rate** (distance, accuracy, fake location). Do not push SM-2 up by loosening the radius or accuracy rules. A high rejection rate should lead to UX fixes (better GPS guidance), not weaker validation. Counterbalances SM-2.
- **SM-C2: Reminder volume per user.** Don't drive SM-2/SM-4 with more reminders. Keep Reminders limited to those in FR-23. Counterbalances SM-2, SM-4.

## 9. Open Questions

None. All discussion questions are resolved, and all inferred defaults are confirmed in §10.

## 10. Confirmed Defaults

Defaults Claude proposed and the user approved (2026-09-25):

- FR-1: wizard progress is saved on the server and can be resumed.
- FR-2: new Employees are not auto-tracked.
- FR-3: previously tracked Employees keep read-only access to their history.
- FR-5: Late cut-off range 0–120 min; default Hours rules 8 h / 4 h; Office rule changes apply from tomorrow.
- FR-6: Office reassignment after today's Check-in applies from tomorrow.
- FR-7: fake-location Owner Notification on the 3rd attempt per calendar month; no Late flag on Weekly off / Holiday check-ins.
- FR-9: Check-in on a Half-day leave date doesn't cancel the leave.
- FR-10: Holiday is shown when a date is both Holiday and Weekly off.
- FR-11: Worked on holiday is counted separately from Days worked.
- FR-12: half-day leave is single-date only; reason required, max 500 chars.
- FR-18: at least one working day per week must remain.
- FR-23: Owner not-checked-in summary is per Office; pending-leave reminder once a day at 10:00 AM.
- NFR-7: performance targets.
- NFR-9: coordinates kept out of logs.
- SM-1: adoption target of 30%.

Decided by Claude on delegation: today's revoke/cancel cut-off at Start time (FR-14), push waves (NFR-10), check-in rate limit values (FR-7).
