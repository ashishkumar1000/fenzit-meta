---
title: Fenzit app — manager team experience (Epic 24 story 24-5)
type: experience-delta
status: approved
created: 2026-11-27
updated: 2026-11-27
applies_to: "workspace/core/frontend/fenzit-app (technician shell + owner shell) over fenzit-be 24-5a/24-5b"
sources:
  - artifacts/specs/spec-company-hierarchy/SPEC.md (CAP-5, D13, D14)
  - artifacts/specs/spec-company-hierarchy/approval-routing.md
  - artifacts/implementation-artifacts/spec-24-5a-backend-manager-signals.md
  - artifacts/implementation-artifacts/plan-24-5b-backend-manager-team-surfaces.md
  - workspace/core/frontend/fenzit-app/PRODUCT.md + src/theme/DESIGN_SYSTEM.md
---

# EXPERIENCE.md — the manager's team

## Foundation

Epic 24 gives a company a reporting tree. The backend already answers the
three questions a manager's phone needs: **whom do I manage**
(`GET /users/me → team`), **what is waiting** (`GET /attendance/leave?status=pending`,
`GET /jobs?scope=all&status=pending_approval&teamOnly=true`), and **may I decide
this row** (`decision: { canDecide, reason }` on every leave and job row, computed
by the same walk the decide POST runs).

This delta designs the app surfaces on top of those reads. It does not invent
new product facts: every row, count and action maps to a shipped field.

### Who is a "manager"

A manager is anyone with `team.headcount > 0` — not a role. Three cases:

| Person | Shell | Team block on `/users/me` | Team surface |
|---|---|---|---|
| Employee with reports | technician app | `headcount ≥ 1`, `members[]` | **Your team** (full: Leave, Jobs, People) |
| Viewer with reports (D13) | owner shell | `headcount ≥ 1`, `members[]` | **Your team** (Leave, Jobs; no apply-on-behalf — they lack `leave.create_on_behalf`) |
| Company admin | owner shell | always empty | **none** — the owner console already is the whole-company surface |
| Anyone with `headcount = 0` | either | empty | **none, and no disabled states to explain** (CAP-5) |

The gate is `team.headcount > 0`. A person with only indirect reports still has
a team: routing climbs to the nearest eligible manager, and the subtree reads
include the people below them.

---

## Voice and copy

- Plain Indian English, sentence case, no exclamation marks.
- **"Your team"**, **"Reports to"**, **"Reporting manager"**. Never L1/L2/L3,
  never "Technician" — the person is an **employee**.
- The app never says "approver set", "walk", "subtree", "routing" or "resolved".
- A disabled control always carries its reason in the row itself; never a
  mystery grey button.
- Names truncate at 24 characters with "…" in titles, 30 in body lines; the
  dates or job number always survive truncation (they are load-bearing).

---

## Surface 1 — Your team (new screen, pushed)

Registered in **both** stacks (`RootStack`, `TechnicianRootStack`) so an
employee manager and a viewer manager reach the same screen.

### Entry points

| Where | Row | Shows when |
|---|---|---|
| Technician **Profile** tab | "Your team" action row, group above Payslips, `Users` glyph | `team.headcount > 0` |
| Owner **Account** tab (viewer manager) | "Your team" row beside the Notifications tile | `team.headcount > 0` |
| Notification tap | leave/job approval + reassignment cards land on the relevant segment | card kind (below) |

No Home banner and no numeric tab badge in this story: the profile mirror's
`pendingLeaveRequests` is owner-only, and a manager's count would need an
extra aggregate the queue does not serve. The **notification bell is the live
signal**; the Profile row is the stable door.

### Anatomy

```
← Your team
  {headcount} people in your team · You report to {managerName}
  [ Leave ] [ Jobs ] [ People ]            ← SegmentedControl
  ...segment content...
```

- Header: `ScreenHeader title="Your team"`.
- Subtitle line (one line, muted): `"4 people in your team"`; append
  `" · You report to Priya"` when `team.managerName` is set. If the manager has
  no manager themselves, omit the clause — never print "Reports to —".
- Segments are a `SegmentedControl` (view switching, per the design system).
  Each segment label carries the count of **actionable** rows once loaded
  (`"Leave, 2"`) only in its accessibility label, not visibly — the segment
  is a section name, not a counter.

### Segment: Leave — "Waiting for your approval"

`GET /attendance/leave?status=pending`, paged 20 at a time. Rows are the
subtree's pending requests, **minus the manager's own** (their own request
routes up; it belongs in their personal history, not their team queue).

Each row reuses the shipped `LeaveRequestCard` anatomy — avatar + status
glyph, name, EMP code, status chip, date strip, working-days chip, leave type,
reason — with a **manager footer**:

| Row state | Footer |
|---|---|
| `decision.canDecide = true` | **Decline** (secondary) · **Approve** (primary, inline) |
| `decision.reason = 'higher_manager'` | Quiet line: **"Someone closer to {firstName} decides this."** No buttons. |
| `decision.reason = 'unresolved'` | Quiet line: **"No approver is set up for this request. Ask your admin."** No buttons. |
| `decision.reason = 'not_pending'` | Never in this list (server filter is pending). |

- Row tap → the shipped `LeaveDetailSheet` (manager variant): approve, decline
  with an optional reason, revoke an approved request, and the employee's
  balances (`GET /attendance/leave/:employeeId/balances`, now manager-readable).
- Approve is the one inline write (single tap, state-guarded); decline opens
  the sheet's reason stage. A 409 shows the shipped "already handled" notice
  and refetches the first page.
- Empty: icon `CheckCircle2`, title **"Nothing waiting for you"**, description
  **"Leave requests from your team will show up here."**
- Loading: 3 skeleton cards. Error: `InlineError` + Retry. Pull to refresh.
- Load more on scroll end; a page failure keeps the loaded rows and shows an
  inline retry, never wipes the list.

### Segment: Jobs — "Waiting for your approval"

`GET /jobs?scope=all&status=pending_approval&teamOnly=true`, paged as the
existing jobs store does. Each row:

- Job number (lead), status chip **Pending approval**, **From {employee name}**,
  then customer name · scheduled date/time, and the service location.
- Footer, same decision matrix as Leave:
  - `canDecide` → **Decline** (opens the shipped `RejectJobSheet`, optional
    reason) · **Approve** (inline).
  - `higher_manager` → **"Someone closer to {firstName} decides this."**
  - `unresolved` → **"No approver is set up for this job. Ask your admin."**
- Row tap → `TechJobDetail` for that job (a manager may open their subtree's
  job; the decision bar also lives there, Surface 4).
- Empty: **"Nothing waiting for you"** / **"Jobs your team submits for approval
  will show up here."**
- Loading, error, refresh, load-more: same rules as Leave.

### Segment: People — "Your team"

The actionable subtree directory from `team.members[]`, name-sorted.

- Row: avatar, name, EMP code, status chip (`Active` / `Invited` /
  `Deactivated` — plain words, `Badge` vocabulary, no colour invention).
- Top action (employees only): **"Apply for leave"** (secondary, full width) →
  the existing `EmployeePickerSheet` fed by `team.members`, then the existing
  `ApplyOnBehalfScreen`.
- Row tap (employees only, active rows) → the same flow with that person
  preselected. Invited/deactivated rows are inert and say why in their caption
  ("Not joined yet" / "No longer active"). Viewers see no apply action at all
  (they lack the right); the list stays read-only.
- Empty (headcount > 0 but no listable rows): **"No one in your team can be
  listed right now."** No retry theatre — the queues above still work.
- The screen never shows a person's leave balances or phone here; this is a
  directory, not an HR record.

---

## Surface 2 — leave detail, manager variant

The shipped `LeaveDetailSheet` gains a manager mode used from Surface 1 and
from approval notifications.

- Header identity: employee avatar, name, EMP code, status chip.
- Balance strip for the **employee** (compact `LeaveBalancesCard`), fetched
  through the now-manager-readable balances route. Failure degrades to the
  existing quiet "couldn't load balances" line.
- **"Also off"** glance, under the date strip:
  - Fetched from `GET /attendance/leave?status=approved&from=<start>&to=<end>`
    (the same subtree read), excluding the requester and the viewer.
  - 1–3 names: **"Also off on these days: Priya, Arjun"**.
  - More than 3: **"Also off on these days: Priya, Arjun and 2 more"**.
  - None: **"Nobody else in your team is off on these days."**
  - Failure: **"Couldn't check who else is off."** — never the "nobody" line.
  - Loading: the line is absent until the answer lands (no spinner in a
    secondary strip).
- Actions: Approve / Decline (reason optional) when `canDecide`; Revoke on an
  approved row; the read-only reason line otherwise. No "Cancel" (that is the
  employee's own action).

---

## Surface 3 — apply on behalf (manager)

Reuses `ApplyOnBehalfScreen` and `useApplyOnBehalf` unchanged in shape.

- Picker source branches on the caller: an **admin** keeps the enrolment
  roster (tracked employees, office + phone captions); a **manager** uses
  `team.members` filtered to `status === 'active'`, caption `EMP-005`.
- The form keeps its live preview (`/attendance/leave/on-behalf/preview`), the
  server message verbatim, and the idempotency key.
- Submit label stays **"Approve"** — the born-approved semantic (D10) — with
  the helper line **"This leave is recorded as approved."**
- Success: announce **"Leave applied for {name}"** and land back on **Your
  team → Leave** for a manager (the owner keeps landing on the Leave Requests
  pane). The request is now pending with **the nearest eligible manager above
  the subject** — which is not the actor, so it may not appear in the actor's
  own queue. That is expected; the success copy says where it went:
  **"Leave applied for {name}. It's waiting for approval."**

---

## Surface 4 — job detail, manager decision bar

`TechJobDetailScreen` gains a decision bar for a pending job the caller can
decide (the detail payload carries `decision`).

- `status === 'pending_approval' && decision.canDecide` → pinned footer:
  **Decline** (opens `RejectJobSheet`) · **Approve** (primary, in-flight
  spinner).
- `pending_approval && !canDecide` → a quiet note where the footer would be:
  `higher_manager` → **"Someone closer to {employee} decides this job."**;
  `unresolved` → **"No approver is set up for this job. Ask your admin."**
- Decision success refreshes the detail in place and announces
  **"Job approved"** / **"Job declined"**; a 409 says it was already handled.
- The creator's existing view of their own pending job is unchanged (they see
  "Pending approval" and no decision bar).

---

## Surface 5 — member record: Reports to (owner app)

The roster row still opens `JobSettingsSheet`; the sheet grows a **Reporting
manager** section above the job switches.

- Row: label **"Reports to"**, value the manager's name or **"Not set"**,
  chevron → manager picker.
- Under it, the chain as one muted line:
  **"Priya → Arjun (Owner)"** (nearest first). When the member is an admin:
  **"Admins sit at the top of the team."**
- Headcount line: **"3 people report to them"** / **"1 person reports to
  them"** / omitted at 0. (This is the member's own subtree, not the company.)
- Picker: a `Sheet` listing active members by name + EMP code + role word,
  with search. Excludes the member themselves and everyone below them (their
  subtree — the server would refuse the cycle; the UI must not offer it).
- **D13 viewer note**: when the chosen manager holds the viewer role, the
  sheet shows an inline note before saving: **"Viewers can't normally see
  leave or job requests. As a reporting manager, they will see their team's
  and can decide them."** Not an error, not a warning colour — a neutral
  `InlineNotice`.
- Save → `PATCH /members/:userId/manager`. Refusals render the server's
  plain-English message verbatim (`MEMBER_IS_ADMIN`, `HIERARCHY_CYCLE`,
  `HIERARCHY_DEPTH`, `MANAGER_NOT_ACTIVE`) in `InlineError`; the sheet stays
  open with the previous value.
- Clearing ("No reporting manager") is a valid choice and routes the member's
  filings to the admin fallback; the row says **"Not set"** afterwards.
- Disabled for a non-admin while saving; the sheet is admin-only (a viewer
  never sees the editor).

---

## Surface 6 — invite sheet: optional Reports to (owner app)

`AddTechnicianSheet` gains one optional row below the skills field:

- Label **"Reports to"**, value **"Not set"** by default, opens the same
  manager picker (active members, search).
- Copy under the row: **"Optional. You can change this later."**
- The invite POST carries `managerId` only when chosen. A refused assignment
  surfaces in the sheet's existing inline error slot (server message
  verbatim) and the sheet stays open — no silent drop.

---

## Surface 7 — notification cards and taps

New manager recipients get real cards, not the generic fallback. Copy is
FE-composed from payload data; a drifted payload degrades to the minimal
honest card.

| Event | Recipient | Title | Message | Tap |
|---|---|---|---|---|
| `leave.applied` | admin **or manager** | `{name} applied for leave` | dates · working days | admin → Leave Requests (Needs review); manager → **Your team · Leave** |
| `leave.pending_reminder` | admin **or manager** | `Pending leave` | `{n} leave requests waiting for approval.` | same split |
| `leave.approver_added` | the added manager | `Now waiting for your approval` | `{name} · {dates}` | **Your team · Leave** |
| `leave.approver_removed` | the removed manager | `No longer yours to approve` | `{name} · {dates}` | **Your team · Leave** (the row is gone, or now read-only) |
| `job.submitted` | admin **or manager** | `New job waiting for approval` | job no · customer · employee | admin → Job detail; manager → **TechJobDetail** (decision bar, Surface 4) |
| `job.approver_added` | the added manager | `Now waiting for your approval` | job no · customer · employee | **TechJobDetail** |
| `job.approver_removed` | the removed manager | `No longer yours to approve` | job no · customer · employee | **not tappable** — the job may have left the reader's branch (a 404 is worse than no door) |

- The registry stays the one classifier; the leave model's role gate widens
  from "admin only" to "admin **or** employee recipient" for `leave.applied`
  and `leave.pending_reminder` (an employee only receives them as a manager).
- The two removal cards are informational: they sit in the inbox, mark read,
  and never open a surface that can fail.
- Push copy (`fenzit-be/src/push/push-copy.ts`) already carries these events;
  the app's push tap uses the same tap model, so a shade tap and a bell tap
  land in the same place.

---

## States matrix (every queue, every load)

| State | Leave / Jobs queue | People |
|---|---|---|
| First load | 3 skeleton cards | 3 skeleton rows |
| Empty | "Nothing waiting for you" + one-line promise | "No one in your team can be listed right now." (headcount > 0) |
| Error | `InlineError` + Retry | `InlineError` + Retry |
| Partial page failure | rows stay, inline Retry under the last row | — |
| Refresh | pull-to-refresh, announced result | pull-to-refresh |
| Offline | the last loaded rows stay; a retry line says "Check your connection." | same |

---

## Accessibility

- Every segment has a label and an announced count ("Leave, 2 waiting").
- Each request card's label reads the person, dates, working days, type and
  decision state; the read-only reason is part of the label, not only a colour.
- Approve/Decline are ≥44 px targets; the inline approve announces
  "Leave approved for {name}".
- The "Also off" line is plain text, not a colour cue.
- `SegmentedControl` keeps the design system's selection semantics; status
  chips keep the fixed `Badge` vocabulary (no new colours).
- The team row in Profile is a single actionable row with the label
  "Your team, {n} people".

---

## Explicitly out of scope

- No manager Home banner / tab badge (the bell is the signal; a count would
  need a new aggregate, tracked as G7).
- No apply-on-behalf for jobs (epic non-goal), no manager job creation.
- No org chart, no multiple managers, no delegation.
- No team attendance dashboard, no team reports.
- No client-side authorisation cache: every decision is rendered from the
  row's `decision` and re-checked by the server; a demoted manager loses the
  surface on the next profile read.

## Acceptance scenarios (CAP-5)

1. **Priya, an employee manager with three reports.** Her Profile shows
   "Your team". The Leave segment shows the pending request from Ravi with
   Approve/Decline; she approves; the row leaves every list and Ravi gets his
   decision notification. The Jobs segment shows a submitted job; she declines
   with a reason from the detail sheet. The People segment lists her three
   reports and "Apply for leave" files a request for one of them, which lands
   with her own manager — not with her.
2. **A higher manager, Arjun.** He opens the same screen: the same pending
   rows appear with **"Someone closer to Ravi decides this."** and no buttons.
   He can still read the detail, the balances and who else is off.
3. **An employee with no reports.** No "Your team" row anywhere; the app is
   byte-for-byte today's app.
4. **The owner.** The roster sheet shows Priya's "Reports to" chain and
   headcount; he sets a manager from the invite sheet and from the record; a
   viewer chosen as manager shows the D13 note.
5. **A tree change.** Priya is moved under another manager; the pending
   request's approver set changes; both managers get the right set-difference
   card; the removed manager's card opens the queue and shows the request
   read-only (or nothing, if it left her branch).
