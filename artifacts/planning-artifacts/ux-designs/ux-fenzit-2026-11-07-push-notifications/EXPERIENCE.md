---
title: Fenzit app — push notification experience (FCM, Crashlytics, Analytics)
type: experience-delta
status: approved
created: 2026-11-07
updated: 2026-11-07
applies_to: "workspace/core/frontend/fenzit-app + workspace/core/backend/fenzit-be push copy (src/push/push-copy.ts)"
sources:
  - artifacts/specs/spec-firebase-integration/SPEC.md
  - artifacts/implementation-artifacts/plan-firebase-integration.md
  - artifacts/planning-artifacts/ux-designs/onboarding-redesign/onboarding-redesign-scope.md (D4, lifted)
---

# EXPERIENCE.md — push notification experience

## Foundation

React Native app (`com.fenzit`), three roles: Admin, Employee/technician, Viewer. The notification row in `notifications` stays the single source of truth; a push is just its voice outside the app. Pushes are plain `notification` title/body + `data {type, id}` — no images, no action buttons, no in-app preference toggles (the OS permission and Android channels are the only gates). In-app surfaces (bell badge, inbox, owner job banner, deep links) are already shipped and unchanged by this delta except where named below.

## Voice and tone

Plain Indian English, sentence case, no exclamation marks, no greetings. The push mirrors the in-app card's words for the same event so the shade and the bell never disagree.

| Rule | Spec |
|---|---|
| Person | "You" for events about the recipient ("You haven't checked in yet today."); third person for events about others ("Priya Sharma applied for leave."); "Their" as the neutral possessive |
| Joiners | " · " between peer facts; " — " before reasons/details |
| Truncation caps | Name 24 chars in titles, 30 in bodies; reason 40; customer/office/holiday/report label 30; truncate with "…". Load-bearing facts (dates, job numbers, decisions) always lead the body — Android's collapsed shade shows roughly one line of text, so nothing critical may sit past ~50 chars |
| Dates | Leave "14–18 Sep 2026"; scheduled slot IST "12 Nov, 10:30 AM"; holiday "Wed, 12 Nov, 2026" — the same formats the cards already use |
| Unknown/drifted payload | Degrade per field to an honest shorter notification; never a broken string, never "undefined" |

## Push copy — every event type

`push-copy.ts` is the implementation; the deltas it still needs are listed after the table.

**Jobs**

| Event | Recipient | Title | Body |
|---|---|---|---|
| `job.assigned` | Assigned technician | `New job assigned` | `{job_number} · {customer_name} · {scheduled_start IST}` — each part dropped when absent |
| Workflow step (event_type = step key, template-driven) | Active admins (not the actor) | `{technician_name} · {job_number}` | Humanized step key: `on_my_way` → "On my way", `completed` → "Completed" |

*Template-driven pattern:* any step key — present or future — gets `{technician} · {job}` over the humanized key, zero per-push DB reads (the exact template label would cost a join per push; the humanized key already reads fine). Field missing → title falls back to "Job status updated". A reassignment still says "New job assigned": it IS new to that technician.

**Reports** (owner/viewer)

| Event | Title | Body |
|---|---|---|
| `report_ready` | `Report ready` | `{reportLabel} is ready to view.` / "Your report is ready to view." |
| `report_failed` | `Report failed` | "Report generation failed. Try again." / "Too many jobs in range. Narrow the date range." (per errorCode, mirroring the card) |

**Attendance**

| Event | Recipient | Title | Body |
|---|---|---|---|
| `attendance.holiday_added` / `_removed` | Tracked employees | `Holiday added` / `Holiday removed` | `{holidayName} — {Wed, 12 Nov, 2026}` |
| `attendance.fake_location` | Owner | `Fake location alert` | `{employeeName} — attempt {N} this month` |
| `attendance.reminder_checkin` | Tracked employee | `Check-in reminder` | "You haven't checked in yet today." |
| `attendance.reminder_checkout` | Tracked employee | `Check-out reminder` | "You haven't checked out yet today." |
| `attendance.reminder_not_checked_in` | Owner | `Not checked in` | "{N} haven't checked in at {officeName}." |

**Leave**

| Event | Recipient | Title | Body |
|---|---|---|---|
| `leave.applied` | Owner | `{employeeName} applied for leave` | `{dates} · {n} working days` |
| `leave.employee_cancelled` | Owner | `{employeeName} cancelled leave` | exact `cancelledDates[]` |
| `leave.checkin_auto_cancel` | Owner | `{employeeName} checked in on leave` | "Their leave on {date} was cancelled." |
| `leave.pending_reminder` | Owner | `Pending leave` | "{N} leave request(s) waiting for approval." |
| `leave.applied_on_behalf` | Employee | `Leave applied for you` | `{dates} · {n} working days` |
| `leave.approved` | Employee | `Leave approved` | `{dates} · {n} working days` |
| `leave.rejected` | Employee | `Leave rejected` | `{dates} — "{reason}"` (reason omitted when null) |
| `leave.owner_revoked` | Employee | `Leave revoked` | `{revokedDates[]} no longer count(s) as leave — {reason}` |
| `leave.cancelled_by_disable` | Employee | `Leave cancelled` | exact `cancelledDates[]` |

**Fallbacks.** Unknown type → title = humanized event type (`payroll.synced` → "Payroll synced"), empty body; tap opens the app without navigating (already planned). Unknown `leave.*` → "Leave updated" title-only. `job.assigned` with a drifted payload → still titled "New job assigned", body degrades per field — the event name must survive even when the data doesn't.

**push-copy.ts deltas:** (1) fire the `job.assigned` branch on the event type alone — today it falls through to generic when `job_number` is missing; (2) extend `PushCopy` with `channel` and `visibility` per the two tables below; (3) apply the truncation caps; (4) leave/attendance/report copy is already correct as drafted.

## Lock-screen privacy

Android `visibility` per message (FCM `android.visibility`, works alongside plain `notification`). PUBLIC = full content on any lock screen; PRIVATE = content hidden when the user chose "hide sensitive content" (Android auto-redacts to app-name-only — no custom redacted copy needed). SECRET never: every event matters to its recipient.

| Visibility | Events | Why |
|---|---|---|
| PUBLIC | `job.assigned`, workflow steps, holiday events, all reminders, `leave.pending_reminder` | Facts the recipient needs at a glance; no personal revelations (customer names appear only on the technician's own phone) |
| PRIVATE | All other `leave.*` (reasons, personal dates), `attendance.fake_location`, both report events | Rejection reasons, fake-location accusations and report labels are personal/sensitive; on a shared family phone they shouldn't surface unlocked |

## Android channels

In-app toggles are a non-goal, so channels are the user's only noise control — four channels, created natively at `MainApplication.onCreate`:

| Channel (id) | Settings name | Settings description | Importance |
|---|---|---|---|
| `fenzit_jobs` | Jobs | Job assignments and job progress updates | HIGH — heads-up + sound |
| `fenzit_attendance` | Attendance & leave | Check-in reminders, leave decisions and holiday updates | HIGH — the check-in reminder protects the day's attendance |
| `fenzit_reports` | Reports | When a report you requested is ready or failed | DEFAULT — sound, no heads-up |
| `fenzit_default` | Updates | General updates from Fenzit | DEFAULT — fallback for unknown types |

Event → channel: `job.assigned` + workflow steps → Jobs; all `attendance.*` + `leave.*` → Attendance & leave; both report events → Reports; anything else → no channel on the message (FCM uses the `firebase.json` default = `fenzit_default`/"Updates"). Owners get several report events a day in busy seasons — that is exactly what DEFAULT keeps out of the face. Users who find leave heads-ups noisy can demote the channel in OS settings; we don't build that.

## Asking for permission (Android 13+; iOS later)

Never at app launch. Two surfaces, matching the plan's frozen boundary.

**New installs — the permissions primer row (built; blessed as-is).** Third row, after Location and Camera (least critical last; asked last in the Continue sequence).

| Part | Spec |
|---|---|
| Title | "Notifications" |
| Badge | "RECOMMENDED" (brand blue — the only RECOMMENDED row) |
| Body — employee | "Nudges about your jobs, attendance and leave — even when the app is closed. Turn them off anytime." |
| Body — admin/viewer | "Job assignments, leave requests and report updates — even when the app is closed. Turn them off anytime." |

Live state per row: green check when granted, Allow pill when not; "don't ask again" routes to app Settings; denial never blocks Continue.

**Existing installs.** The inbox card alone may never be seen — the inbox is visit-driven, and push is what removes the need to visit. Primary recommendation (Open Question 1): one-time dismissible "Turn on notifications?" card on the user's home surface (Jobs/Home for admin, Today for technician) after their first post-update login — post-login is in-context per the boundary's own logic, never at boot. Interim as-built: the inbox card below, which sits directly above the very events the user just came to read — the strongest natural moment.

**Denied / never-ask / Settings hand-off.** Plain denial → surfaces stay exactly as-is, copy unchanged, no guilt copy, no re-prompt within the session (the inbox card re-appears next focus — acceptable). Android never-ask → the Allow tap routes straight to app Settings; on return, the focus probe collapses the card. iOS (when it ships): no never-ask signal — a denied Allow tap must also open Settings (mirror the primer's camera behaviour); same two surfaces, still never at launch.

## App-open (foreground) experience

Foreground pushes never post a system notification; `onMessage` refreshes the same stores the Realtime seam refreshes. Realtime and FCM deliver the same row, so **visible foreground surfaces fire on the Realtime path only** — FCM `onMessage` stays silent — and nothing can ever double.

| Role | In-app foreground surface | Bell |
|---|---|---|
| Admin | Existing job-status banner (4s) for job steps — unchanged; report/leave events refresh silently | Count badge on Jobs header updates |
| Employee/technician | `job.assigned` shows the same banner pattern: "New job assigned · JOB-1042 · Sharma Electronics", 4s, via the shared seam (Open Question 2); Today's job list force-refreshes; other events refresh silently | Count badge on Today header updates — no animation, no auto-open |

Rationale: the spec's success signal is a technician learning of an assignment; a foreground technician currently gets zero feedback while an owner gets a banner. Same components, one new payload branch.

## The two new inbox pieces (using existing tokens/components)

**"New job assigned" card** (built; blessed). One card per row, under the All filter only (Active/Completed are job-status buckets, like report cards). Title "New job assigned" (`JOB_ASSIGNED_TITLE`); message "JOB-1042 · Sharma Electronics · 12 Nov, 10:30 AM" — present parts only, both payload naming conventions read. Default bell glyph (no custom icon). Tap → TechJobDetail through the shared tap helper; marks read alongside. Leaves the inbox by normal aging (30-day prune).

**"Notifications are off" card** (`PushPermissionCard`, built; blessed). Sits above the filter bar at the top of NotificationsScreen, `primarySoft` card, bell glyph. Copy: title "Notifications are off"; body "Turn them on to hear about job assignments, leave decisions and reports — even when the app is closed."; primary "Allow" ("Please wait…" while asking); ghost "Open settings". Disappears the moment notifications are on (re-probed on every focus — returning from Settings collapses it). The probe asks whether notifications are actually enabled, on every Android version — older Android has no permission prompt but users can still switch notifications off — so on those phones, and after "don't ask again", Allow opens the app's Settings. While it shows, the list stays fully usable — the card never blocks.

## Accessibility floor

Every new tappable carries an accessible name ("Allow Notifications", card titles read in full); the primer's Allow pill already labels "Allow {row}". Banner text mirrors the composed one-liner as its screen-reader text. No information by colour alone: granted/denied primer states differ by control (check vs Allow pill), not tint.

## Key flows

**Flow 1 — Ravi, technician, phone in pocket.** Sampath assigns JOB-1042 at 9:14; Ravi's Redmi buzzes: "New job assigned / JOB-1042 · Sharma Electronics · 12 Nov, 10:30 AM". Tap → TechJobDetail. *Climax: Ravi accepts the job without ever opening the app first.* If his permission is off, the same event still lights the bell; opening the inbox puts the "Notifications are off" card directly over this missed event.

**Flow 2 — Priya, owner, at the office.** Her technician completes a step; her phone flashes "Arjun · JOB-221 / Completed" (heads-up, Jobs channel) and her app's banner says the same words seconds later when she opens it. A report she asked for lands sound-only in the shade — "Technician Job Report is ready to view." — never interrupting a customer conversation.

## Open questions (each with my recommendation)

> **Resolved 2026-11-07.** The user delegated these ("take best decisions"); all five recommendations below are adopted as written. Two adjustments were made while approving: the Jobs channel description is role-neutral (technicians read it too), and the notifications-off probe checks real notification state on every Android version.

1. **Existing-install ask moment.** Add the one-time post-login home-surface card (needs a one-line boundary amendment beyond "primer + notifications screen")? — **Recommend yes:** once per install, dismissible ("Not now"), suppressed after any denial or dismissal; shown only after the first post-update login, never at boot. Without it, the card's audience is self-selected inbox visitors — the users push would help most never see it.
2. **Employee foreground banner for `job.assigned`.** Mirror the owner's StatusBanner (4s, Realtime path only)? — **Recommend yes** for symmetry and the spec's own success signal; FCM `onMessage` stays silent so nothing doubles. Fallback if scope must stay frozen: silent refresh only (assignment still lands in bell + Today).
3. **Four channels vs one "Updates".** — **Recommend the four above**: channels are the only noise control in a no-in-app-toggles world; rollback to the single "Updates" channel is deleting one mapping table, nothing else.
4. **Template-label resolution for job-step push bodies** (join the workflow template in the sweep so the body reads "Quality Check" exactly)? — **Recommend not now:** humanized keys read fine, and the join costs a per-push read; revisit only if owners report confusing bodies.
5. **iOS permission timing when iOS ships.** — **Recommend same two surfaces** (primer row, inbox card), Settings hand-off on denial (no never-ask signal on iOS), never at first launch.
