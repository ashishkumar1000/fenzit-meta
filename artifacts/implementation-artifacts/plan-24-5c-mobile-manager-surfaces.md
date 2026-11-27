---
title: 'The manager works their branch from the phone — Your team queues, team directory, apply-on-behalf, and Reports-to editing'
type: 'feature'
created: '2026-11-27'
status: 'done'
route: 'full'
route_source: 'auto'
review: 'REVISE — adversarial review 2026-11-27; 15 findings triaged and folded'
review_source: 'subagent adversarial review'
lenses_ran: ['adversarial']
review_loop_iteration: 1
baseline_commit: 'bad705e'
baseline_revision: 'bad705e'
context:
  - 'artifacts/specs/spec-company-hierarchy/SPEC.md'
  - 'artifacts/specs/spec-company-hierarchy/approval-routing.md'
  - 'artifacts/implementation-artifacts/epic-24-context.md'
  - 'artifacts/implementation-artifacts/spec-24-5a-backend-manager-signals.md'
  - 'artifacts/implementation-artifacts/plan-24-5b-backend-manager-team-surfaces.md'
  - 'artifacts/planning-artifacts/ux-designs/ux-fenzit-2026-11-27-manager-team/EXPERIENCE.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** The backend now answers everything a manager's phone needs — `team.members` on `/users/me`, a team-only job queue, subtree leave balances, per-row `decision { canDecide, reason }`, and notifications routed to the resolved approver — but the app still shows a manager the employee experience: no team surface, no way to decide a report's leave or job, no way to apply for a report, and no way for an owner to set "Reports to" at all. Story 24-5's CAP-5 is unbuilt in `fenzit-app`.

**Approach:** One new "Your team" screen (Leave / Jobs / People segments) reachable from the Profile tab when `team.headcount > 0` and from the existing notification taps; a manager variant of the leave detail (balances + "also off" glance) and of the technician job detail (decision bar); the shipped apply-on-behalf flow re-pointed at `team.members` for managers; real notification cards and taps for the manager events; and the owner-side Reports-to picker on the invite sheet and the member settings sheet with the chain/headcount record.

</frozen-after-approval>

## Boundaries & Constraints

**Always:**
- Reuse the shipped reads and writes — no new endpoint, no new queue contract. Queue data comes from `GET /attendance/leave?status=pending` (subtree) and `GET /jobs?scope=all&status=pending_approval&teamOnly=true`; decision truth is the row's `decision` field, never a client-side role guess. The write paths are the shipped approve/reject/revoke and `POST /jobs/:id/approval`.
- A person with `team.headcount === 0` sees **no new UI anywhere** — no row, no badge, no empty state. Admins get `team` empty and keep the owner console.
- The "Your team" gesture is display-only: every decision is re-checked by the server. A demoted manager loses the surface on the next `/users/me` read; rows already on screen whose `decision.canDecide` is false never render action buttons.
- Copy is the EXPERIENCE.md table verbatim: "Your team", "Reports to", "Reporting manager", "Someone closer to {name} decides this.", "No approver is set up…", "Also off on these days: …"; never L1/L2/L3, never "Technician".
- Every queue has explicit loading (skeletons), error (`InlineError` + Retry), empty and partial-page states; a failed refresh keeps the loaded rows.
- The owner's own leave request never appears in their team queue (the server scope is self + subtree; the queue filters the caller's row out).

**Never:**
- No BE/DB change in this story. If an app need proves impossible with the shipped contract, stop and report rather than widening scope silently.
- No Home banner, no tab badge (owner decision 2026-11-27: the bell is the live signal; the Profile row is the stable door).
- No apply-on-behalf for a viewer (they lack `leave.create_on_behalf`) — the People segment hides the action for them, no disabled button.
- No apply-on-behalf for jobs, no manager job creation, no web changes, no org chart.
- No new design-system component; compose the shipped `Card`, `Button`, `Badge`, `SegmentedControl`, `Sheet`, `InlineError`, `EmptyState`, `Skeleton` and the existing leave/job cards.
- No test file until the device pass confirms behaviour (house test-timing rule).

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|---|---|---|---|
| Manager boots | `/users/me` `team.headcount 3`, `members[]` | Profile shows "Your team"; screen header "3 people in your team" | `team` absent (old BE) → no row, no crash |
| Leave queue | subtree pending, one row is the caller's own | own row filtered out; report rows with Approve/Decline | page error → rows stay + inline retry |
| Read-only row | `decision.canDecide=false, reason='higher_manager'` | quiet line "Someone closer to {name} decides this."; no buttons; row tap still opens detail | — |
| Unresolved row | `reason='unresolved'` | "No approver is set up for this request. Ask your admin." | — |
| Job queue | `teamOnly=true`, empty subtree | empty state, never company rows | 404 out-of-branch id never sent |
| Approve race | row decided elsewhere | 409 → shipped "already handled" notice + first-page refetch | — |
| Teammates-off | approved leave overlapping the request, 0/1/3/5 names | "Nobody else…" / 1–3 names / "and N more" | fetch failure → "Couldn't check who else is off." |
| Apply on behalf (manager) | picker from `team.members`, active only | born-approved, success lands on Your team · Leave; copy names where it went | non-tracked target → server message verbatim |
| Apply on behalf (viewer) | People segment | no action, no disabled control | — |
| Job detail decision | pending + canDecide | Decline (reason sheet) + Approve bar | 409 → already handled |
| Owner record | member with chain `[Priya, Arjun]`, headcount 3 | "Reports to Priya", chain line, "3 people report to them" | read failure → sheet error + retry |
| Manager assignment | picker candidates | self + own subtree excluded; viewer choice shows D13 note | server refusal verbatim, sheet stays open |
| Invite with manager | optional `managerId` | POST body carries it only when chosen | refusal in the sheet's error slot |
| Notification revision | `leave.approver_added` / `_removed` | cards with exact copy; removed job card not tappable | drifted payload → minimal honest card |
| Old build, new row | unknown event type | generic inert card (registry fallback) | — |

## Code Map

**Services (types + one write + one filter)**
- `src/services/resources/users.ts` — `TeamMember`, `TeamSummary` and optional `team` on `MyProfile`; `DecisionView` may live here or in a shared `types`.
- `src/services/resources/jobs.ts` — `decision?: DecisionView` on `ApiJob`; `teamOnly?: boolean` on `ListJobsQuery` (wire `teamOnly=true`).
- `src/services/resources/attendanceLeave.ts` — `decision?: DecisionView` on `LeaveRequestRow`.
- `src/services/resources/members.ts` — hierarchy fields on `CompanyMember`, `setManager(userId, managerId | null)`.
- `src/services/resources/technicians.ts` + `src/features/technicians/types.ts` — `managerId?: string` on `InviteTechnicianRequest` / `NewTechnicianInput`, forwarded by `invite()`.

**New feature `src/features/team/`**
- `teamModel.ts` — pure: `hasTeam(profile)`, `withoutOwnRows(rows, myId)`, `decisionNote(decision, firstName)`, `teammatesOffLine(names)`, `activeDirectory(members)`, `teamHeadcountLine(n)`, `managerCandidates(members, memberId)` (exclude self + subtree), `chainLine(member)`, `viewerManagerNote(role)`.
- `useTeamLeaveQueue.ts` — page 1 + load-more of `status=pending` (PAGE_SIZE 20), own-row filter, refetch, `removeDecided(id)`; approve/reject/revoke writes return the updated row.
- `useTeamJobQueue.ts` — same shape over `jobsService.list({ scope: 'all', status: ['pending_approval'], teamOnly: true })`; decide via `jobService.decidePending`.
- `useTeammatesOff.ts` — for a span, `GET /attendance/leave?status=approved&from&to`, exclude requester + self, cap names.
- `YourTeamScreen.tsx` — header + `SegmentedControl` (Leave · Jobs · People), route param `{ segment? }` consumed once.
- `components/TeamLeavePane.tsx` — cards (shipped `LeaveRequestCard` with a `readOnlyNote`), inline approve, detail sheet host.
- `components/TeamJobsPane.tsx` — cards (new thin `TeamJobApprovalCard` over `ApiJob` + resolved names), inline approve, reject sheet, tap → `TechJobDetail`.
- `components/TeamPeoplePane.tsx` — directory rows, "Apply for leave" (employees only), row preselect.
- `index.ts`.

**Manager leave detail**
- `src/features/attendance/leave/LeaveRequestCard.tsx` — optional `readOnlyNote` (suppresses the action row on a pending row).
- `src/features/attendance/leave/LeaveDetailSheet.tsx` — optional `teammatesOffSlot` under the date strip; manager mode reuses the shipped approve/reject/revoke actions.
- `src/features/attendance/leave/useDetailBalances.ts` — already manager-readable; no change beyond using it in the team pane.

**Apply on behalf**
- `src/features/attendance/leave/useApplyOnBehalf.ts` — picker source branches admin → enrolments, employee → `team.members` (active); success landing branches owner → `OwnerLeave`, employee → `YourTeam { segment: 'leave' }`.
- `src/features/attendance/leave/ApplyOnBehalfScreen.tsx` — copy/target only.
- `src/features/attendance/leave/EmployeePickerSheet.tsx` — caption already degrades (code-only); confirm no office/phone assumption.

**Job detail**
- `src/features/technicianApp/TechJobDetailScreen.tsx` — decision bar (pending + `decision.canDecide`), read-only note otherwise, `RejectJobSheet`, 409 reconciliation.

**Owner Reports-to**
- `src/features/technicians/useMemberDirectory.ts` — one `GET /members` read shared by both pickers (fresh on open).
- `src/features/technicians/memberHierarchyModel.ts` — candidates, chain text, headcount copy, viewer note, refusal copy passthrough.
- `src/features/technicians/components/ManagerPickerSheet.tsx` — searchable active-member list; excludes self/subtree; D13 note.
- `src/features/technicians/components/AddTechnicianSheet.tsx` — optional "Reports to" row; `onSubmit` input carries `managerId`.
- `src/features/technicians/components/JobSettingsSheet.tsx` — "Reporting manager" section (Reports to / chain / headcount) above the job switches.
- `src/features/technicians/TechniciansScreen.tsx` — wire the invite submit's `managerId` (store/add path unchanged in shape).

**Navigation + entries**
- `src/navigation/types.ts` — `YourTeam: { segment?: 'leave' | 'jobs' | 'people' } | undefined` on both stacks; `ApplyOnBehalf` on the technician stack.
- `src/navigation/RootNavigator.tsx` + `src/navigation/TechnicianRootNavigator.tsx` — register `YourTeam` (both) and `ApplyOnBehalf` (technician).
- `src/features/technicianApp/ProfileScreen.tsx` — "Your team" row (gated `team.headcount > 0`).
- `src/features/more/MoreScreen.tsx` — "Your team" row for the owner shell (viewer-manager only; admins have `team` empty).

**Notifications**
- `src/features/notifications/leaveNotificationModel.ts` — employee-side classification of `leave.applied` / `leave.pending_reminder` (tap `team-pending`); new `leave.approver_added` / `leave.approver_removed` copy + tap.
- `src/features/notifications/jobApprovalNotificationModel.ts` — `job.approver_added` / `job.approver_removed` copy; removed card not tappable.
- `src/features/notifications/notificationEventRegistry.ts` — classify the new events; widen `leave.applied` / `pending_reminder` to employee recipients.
- `src/features/notifications/notificationTapModel.ts` — `YourTeam` target, `team-pending` leave tap, push-side mapping for the four new events; job-removed no-op.
- `src/features/notifications/NotificationsScreen.tsx` — handlers for the new card kinds; read-marking unchanged.
- `src/features/notifications/reportNotificationModel.ts` — the card union/merge gains the new kinds (or the leave/job models keep their own kinds and the union type widens).

## Tasks & Acceptance

1. **Types + wire** — add `team`, `decision`, `teamOnly`, member hierarchy, `setManager`, invite `managerId`. Acceptance: unit typecheck; a fixture profile with `team` parses and an absent `team` fails hidden.
2. **`teamModel` + `YourTeamScreen` skeleton** — gate, header, segments, route param, Profile/More rows. Acceptance: headcount 0 renders no row; headcount 3 renders the row; the screen opens on the requested segment.
3. **Leave queue** — hook + pane + card read-only note + detail sheet host (balances + teammates-off). Acceptance: own row filtered; canDecide row approves inline; higher-manager row shows the reason and no buttons; 409 reconciles.
4. **Jobs queue** — hook + card + inline approve/reject + tap to `TechJobDetail`. Acceptance: empty team answers empty; decided row leaves the list; reject sends the optional reason.
5. **Apply on behalf** — manager picker source, dual registration, success landing/copy. Acceptance: an employee manager files for an active report and lands on Your team · Leave; viewer sees no action; admin path unchanged.
6. **Job detail decision bar** — pending + canDecide; read-only reason; reject sheet. Acceptance: creator's own pending job shows no bar; manager's report job shows the bar; 409 says already handled.
7. **Notifications** — widened classification + four new cards + taps (job-removed inert). Acceptance: each event type lands where the table says; unknown stays generic.
8. **Owner Reports-to** — directory hook, picker, invite row, settings section, chain/headcount, viewer note, refusals verbatim. Acceptance: assigning/clearing works; self/subtree excluded; refusal keeps the sheet open.
9. **Docs** — sprint-status lines (`24-5-mobile-manager-surfaces` split into the two shipped slices), EXPERIENCE.md status → approved; no release-notes file until a release is declared.

## Test Plan (written after the device pass, per the house rule)

- `teamModel.test.ts` — gate, own-row filter, decision copy (all three reasons, null name), teammates-off (0/1/3/5), candidates (self + subtree excluded), chain text, viewer note, headcount copy.
- `useTeamLeaveQueue.test.tsx` / `useTeamJobQueue.test.tsx` — page 1, load-more, error keeps rows, write removes the row, 409 path.
- `YourTeamScreen.test.tsx` — segment switching, route param consumption, loading/empty/error, read-only row, approve call ordering, viewer hides apply.
- `LeaveRequestCard.test.tsx` — read-only note suppresses actions; action row unchanged without it.
- `TechJobDetailScreen.test.tsx` — bar only with `canDecide`; read-only reason; reject reason payload.
- `notificationEventRegistry.test.ts` / `leaveNotificationModel.test.ts` / `jobApprovalNotificationModel.test.ts` / `notificationTapModel.test.ts` — widened classification, four new payloads (drifted too), tap table incl. job-removed no-op, push parity.
- `JobSettingsSheet.test.tsx` / `AddTechnicianSheet.test.tsx` / `memberHierarchyModel.test.ts` — reports-to display, save/clear, refusal stays open, candidate exclusion, viewer note, invite body omission when unset.
- `useApplyOnBehalf` tests — manager source from `team.members`, admin source unchanged, success landing per role.

## Design Notes

- **Own row in the team leave queue** — the BE scope is self + subtree; the queue filters the caller's own `employeeId` out client-side (one row at most, so pagination stays honest). A BE `teamOnly` for leave is not needed for this story; if a later surface needs strict-below paging, it is an additive filter there.
- **Job-removed card is inert** — a re-parent can move the job out of the reader's branch; a tap would 404. The inbox still carries the fact.
- **No numeric badge** — a true count needs an aggregate the queue does not serve (G7 in the 24-5b plan). The bell is the live signal.
- **Owner edits use `GET /members`** — the profile roster has no role/manager; the picker needs role words and the subtree set for candidate exclusion. Both sheets fetch it on open; no shared cache means no stale tree.
- **The owner's member sheet stays the same route** — `JobSettingsSheet` grows a Reporting manager section; no second "member detail" screen.
- **Ledger scan** — `deferred-work.md` "Manager-queue triage gaps" (age chip, description line) is not inherited by this queue: the new job card is designed for decisions (employee, customer, scheduled slot, job number), not for the owner's triage anatomy; the owner's `ApprovalQueueCard` is untouched.

## Design references (Stitch, 2026-11-27)

Sally's UX delta is the source of truth; the Stitch project is the visual
companion (“Fenzit — Manager Team Experience (Epic 24)”,
`projects/129662491942565583`, design system “Field Utility System”
`assets/de896120dd7a4af3bf9f06c265c22d8e`). Seven completed screens:

| Screen | Stitch id |
|---|---|
| Your team — Leave queue | `screens/15839b0ed80b4f22af17a8f6e4d7d6f1` |
| Your team — Jobs queue | `screens/d2e0e7e685664eb38cfaaa34bec93493` |
| Your team — People directory | `screens/1af3f3dd79ef48bb9e7a4820420d47c0` |
| Leave request detail (sheet) | `screens/bf6836574a1d401caad5c367d143a323` |
| Member settings — Reporting manager | `screens/2ac5e10e18f545b291bee5c8f38d9580` |
| Add employee — Reports to | `screens/8fa79c1234064fd19c9a93cec48388ad` |
| Reports to picker stage | `screens/8e8205d6d99d459b98c2eef68c456c6c` |

## Plan-review triage (2026-11-27)

Verdict was **REVISE**. All fifteen findings were accepted; the four HIGH
ones changed the build:

1. **Admin gate (HIGH)** — `hasTeam` now excludes `company_admin` /
   `platform_admin` as well as requiring `headcount > 0`. The server computes
   an admin's hierarchy, so the old gate would have shown the owner a second,
   narrower team surface (tenant-wide Leave, subtree Jobs, empty People).
2. **Viewer job routing (HIGH)** — the team job tap routes by role: employee →
   `TechJobDetail`, viewer → the owner `JobDetail`. The owner detail's
   decision bar is now gated on the row's `decision.canDecide` (falling back
   to `canWrite`), and a pending row somebody closer owns shows the quiet
   reason instead of buttons.
3. **Born-approved claim (HIGH)** — only an admin's on-behalf filing is born
   approved. A manager's is pending, routed above the subject. The screen's
   submit label/helper and the success announcement now branch by caller
   ("Approve" + "recorded as approved" vs "Apply leave" + "waiting for
   approval"), and the manager lands on Your team · Leave.
4. **Leave-type catalog (HIGH)** — an employee manager cannot read
   `GET /attendance/leave/types` (`leave.types` is admin-only). The hook now
   uses `GET /attendance/me/leave/types` for non-admins (same shape,
   enabled-only), so the form is typed and the balance check runs.
5. **Revoke (MEDIUM)** — dropped from the manager detail. The revoke preview
   route is admin-only and the team queue lists pending rows only, so no
   approved-row entry point exists. Deviation from EXPERIENCE Surface 2
   recorded here.
6. **Viewer notifications (MEDIUM)** — leave classification no longer keys on
   role: recipient sets are tree-derived, so a viewer manager now gets real
   cards and taps to Your team · Leave. Employee/viewer recipients of
   `leave.applied` / `pending_reminder` land on Your team; admins keep
   OwnerLeave.
7. **No role in `team.members` (MEDIUM)** — accepted limitation: a viewer
   report is listed but cannot take on-behalf leave. The refusal now reads
   “This person isn't set up for leave requests.” for a manager instead of
   the false “isn't in your team anymore”.
8. **Technician shell not manager-aware (MEDIUM)** — `TechJobDetail` hides
   the workflow bar, stepper advances and shared-store upserts unless the
   caller is the assignee/creator; the manager's decision bar is new there.
9. **Own rows (MEDIUM)** — the note now says a page may render fewer than 20;
   the “one row at most” invariant is removed.
10. **Nested sheets (MEDIUM)** — the manager picker is a STAGE inside the
    hosting sheet (the shipped LeaveDetailSheet morph precedent), shared by
    `JobSettingsSheet` and `AddTechnicianSheet`.
11. **Reporting-manager section (MEDIUM)** — renders above every role arm for
    any non-removed member, so a viewer can be assigned a manager.
12. **Invite refusals (MEDIUM)** — `inviteErrorMessage` passes the manager
    codes through verbatim and says the refusal cancelled the invite.
13. **Pending-invite row (LOW)** — verification must open a **server-backed**
    member’s sheet (after a profile refresh), not the `invite_` placeholder.
14. **`from`/`to` (LOW)** — added to `listOwnerLeave`’s params.
15. **`deactivated` (LOW)** — added to `CompanyMember.status`; the settings
    sheet shows a paused-account note instead of dead switches. A viewer has
    no row on the owner’s Technicians roster (employee-only), so CAP-1’s
    every-non-admin coverage is not reachable on mobile; recorded, not
    silently shipped.

## Verification

**Commands:** `npx tsc --noEmit`, `bun run lint` (changed files), `bun run test` (after the device pass).
**Device (Pixel 6, `1C301FDF6002ZB`, u2cli):**
- Employee manager `7700000074` (PayrollQA Works, 3 reports): Account → **Your team** row and
  "3 people in your team"; Leave queue lists both pending requests with name, dates, working
  days and reason; **Approve** and **Decline** both decide inline; the leave sheet shows the
  employee + EMP code, day part, dates, working days, status, the requester's balances
  ("Vijay's leave balances"), REASON, and "Nobody else in your team is off on these days.";
  a reject records `leave_events.cause='reject'`. Jobs queue shows the pending card
  (From/For/slot/skill/location), the tap opens `TechJobDetail` with
  "Approve it to schedule it like any other job." + Decline/Approve and no workflow bar;
  approving schedules it. People lists the 3 reports; apply-on-behalf for Rekha walks the
  manager branch (balances, type picker, dates, "1 working day", reason presets), lands on
  Your team · Leave as pending, and shows the read-only
  "Someone closer to Rekha decides this." note with no action buttons.
- Viewer manager `7700099001` (Meena, one report): Account shows **Your team**
  ("Leave & job requests from your team"), the screen reads "1 person in your team",
  the report's pending leave is listed with Decline/Approve, approving records Meena as the
  approver (`leave_events.cause='approve'`, actor = Meena), and People offers no
  apply-on-behalf for a viewer (D13).
- Owner `7700099000`: Account has **no** Your team; a member's sheet shows REPORTING
  MANAGER ("Reports to" / "Not set" / "No one above them in the team yet.") above the job
  switches; picking a manager and pressing **Save** persists it
  (`memberships.manager_id`) and the row re-reads "Reports to PQA Viewer Meena Iyer",
  with the D13 note shown before saving.
- **Device finding (fixed):** the picker's candidate list was a flat `View`, so with a
  200-person directory the rows ran past the sheet and Save sat ~200 rows below the fold —
  the pick could never be saved (the first symptom: "Save closes the sheet"). The list now
  scrolls inside a bounded box (`useWindowDimensions().height * 0.45`) with
  `keyboardShouldPersistTaps="handled"`, leaving Save/Back reachable at any team size; the
  save was then verified end to end (DB + UI).
- **Device finding (fixed):** `useTeammatesOff` listed an object literal in its dependency
  array, so the "Also off" line refetched forever and never rendered.
**Commands/DB checks:** `npx tsc --noEmit` clean; full `bun run test` green; manager
assignment via `PATCH /members/:memberId/manager`; the on-behalf preview returns `ok`;
`leave_events` confirm the requester/actor exclusion (the actor is never in
`resolved_approvers`).
**Live API:**
- `GET /users/me` team block (already verified in 24-5b).
- The seeded fixtures are removed after the pass; no production tenant is mutated.

## Code Review

### 2026-11-27

**Code review complete.** 2 `decision-needed` (both resolved to patch 2026-11-27), 23 `patch`, 3 `defer`, 22 rejected.
Lenses: blind-hunter, edge-case-hunter, verification-gap, intent-alignment.
The diff reviewed was `git diff bad705e` (44 files); six new test files written
after the patch was cut (1,323 lines) were reviewed separately and the
verification-gap lens checked the on-disk tree. Suites at review time: 353
suites / 4,629 tests green; `tsc --noEmit` clean.

**All 25 patch items applied 2026-11-27.** Six new pane/model test files were
added with the fixes (LeaveDetailSheet, TeamLeavePane, TeamJobsPane,
TeamPeoplePane, notificationTapModel, jobApprovalNotificationModel) plus
additions to the push matrix, the jobs service (`teamOnly` wire), the owner and
technician job-detail screens, and `useTechnicians` (invite `managerId`).
Post-patch verification: `npx tsc --noEmit` clean; targeted suites **40/40
suites, 552/552 tests**; full `bun run test` **359 suites / 4,672 tests green**.
Lint is at the pre-existing baseline (only `no-void` warnings in changed files;
the `JobDetailScreen`/`NotificationsScreen` unused-var errors predate this
story). The three defer entries live in `deferred-work.md`.

- [x] [Review][Patch] Segment labels carry no announced count — EXPERIENCE Surface 1 requires each segment's accessibility label to carry its actionable count ("Leave, 2") once loaded, invisibly; the screen's static `SEGMENTS` carries no counts and `SegmentedControl` only offers a visible `badge`. The counts live inside three separate pane-level hooks, so wiring them means either lifting count state to `YourTeamScreen` (pane prop/refactor) or adding an a11y-only option to the design-system control, or accepting the deviation as a follow-up. [src/features/team/YourTeamScreen.tsx:43]
- [x] [Review][Patch] A failed decline in the Jobs queue closes the sheet and hides both the reason and the error — `confirmReject` always calls `setRejecting(null)`, so a network/server failure discards the typed reason and leaves the message only in the list header behind the closed sheet; `RejectJobSheet` has no error slot. The fix is a product choice: show the error inside the sheet (new prop/slot), reuse the owner's `Alert.alert` posture, or keep the current close-and-show-on-list behavior. [src/features/team/components/TeamJobsPane.tsx:48-60]
- [x] [Review][Patch] `job.approver_removed` push still deep-links to a job that may have left the branch — the inbox card is deliberately inert (`tappable: false`) but `pushTapTargetForEvent` has no guard, so the event falls through `isNonJobEventType` (it starts with `job.`) into `tapTargetForJobCard`; the shade tap opens the job detail, the exact 404 the card exists to prevent. [src/features/notifications/notificationTapModel.ts:250]
- [x] [Review][Patch] The drifted-payload leave-card fallback lost its role split — the diff replaced `copy?.tap ?? (role === 'company_admin' ? 'owner-all' : 'attendance-guarded')` with an unconditional `'attendance-guarded'`, so an admin receiving a `leave.applied` row whose payload has no `employeeName` gets a card that navigates to the technician `TechnicianTabsAttendance`, a route the owner stack does not have. Restore the role-aware fallback. [src/features/notifications/leaveNotificationModel.ts:319-322]
- [x] [Review][Patch] Approver-set cards route an admin to a team surface admins never get — `LEAVE_APPROVER_EVENTS` and `team-pending` return `YourTeam` before any role check, so an admin approver (the owner is the top approver) lands on a screen whose `hasTeam` gate is false: it renders `null` and pops back. Site the approver events to `OwnerLeave`'s pending queue for admins, `YourTeam · Leave` for managers, on both the inbox and push paths. [src/features/notifications/notificationTapModel.ts:145-148,227-229]
- [x] [Review][Patch] A failed pull-to-refresh is silent and is announced as a success — both queues' `loadFirst` swallows the error and resolves, so `onRefresh`'s `.then` always announces "Leave requests updated"/"Job requests updated", and both panes render `queue.error` only when `items.length === 0`; with rows on screen an offline refresh keeps stale rows, shows no banner and tells the user (and screen readers) the list was updated. Return success from `loadFirst`, announce only on success, and render the error banner whenever `error != null`. [src/features/team/useTeamLeaveQueue.ts:96-104, src/features/team/components/TeamLeavePane.tsx:94-132]
- [x] [Review][Patch] `YourTeamScreen` turns a failed profile read into a permanent spinner — `profile == null` renders a bare `ActivityIndicator` and ignores `useMyProfile()`'s `error`, so a failed `/users/me` looks like eternal loading with no back affordance. Render an `InlineError` + Back (or Retry) when the load has failed. [src/features/team/YourTeamScreen.tsx:50,68-74]
- [x] [Review][Patch] The leave card's Decline opens the detail stage, not the reason stage — EXPERIENCE Surface 1 says decline "opens the sheet's reason stage"; `TeamLeavePane` wires `onDecline` to `openDetail(item)`, so the manager must find Decline again inside the sheet. Open `LeaveDetailSheet` at its reject stage (a small initial-stage prop, mirroring the shipped stage machine). [src/features/team/components/TeamLeavePane.tsx:154]
- [x] [Review][Patch] The technician detail's read-only posture stops at the workflow bar — a manager opening a report's job gets no Start/advance, but `onPhotosConfirmed` and `onRecaptureSignature` are passed unconditionally and the Photos card renders on non-terminal jobs, so the capture slot (and the signature Re-capture) is still offered on someone else's job. Gate both on the same ownership rule as the bar. [src/features/technicianApp/TechJobDetailScreen.tsx:404-420]
- [x] [Review][Patch] The People directory prints "Active" twice and drops the badge on every other status — an active row shows the status word in the caption (`note ?? chip.label`) and again as a badge, while invited/deactivated rows get no badge at all; `statusChip` also labels any unknown status "Deactivated". Show the badge for every status and reserve the caption for the explanatory note. [src/features/team/components/TeamPeoplePane.tsx:66-85]
- [x] [Review][Patch] The apply-on-behalf roster reloads on every profile object change — `loadRoster` depends on `[isAdmin, profile]` and re-runs from its effect, so any `/users/me` refresh flips the picker back to its loading state mid-use (and re-reads the admin enrolments). Depend on `isAdmin` plus `profile?.team?.members`. [src/features/attendance/leave/useApplyOnBehalf.ts:204-221]
- [x] [Review][Patch] `useApplyOnBehalf`'s header still documents the admin-only story — it promises success lands on `OwnerLeave`'s Requests/All and lists only `ATTENDANCE_NOT_TRACKED`/`ATTENDANCE_EMPLOYEE_NOT_FOUND`, never the manager branch, `listMyLeaveTypes` or `EMPLOYEE_NOT_SET_UP_MESSAGE`; the preview comment still calls the route owner-only. Update the docblocks to the shipped two-caller contract. [src/features/attendance/leave/useApplyOnBehalf.ts:1-28,418-426]
- [x] [Review][Patch] The Profile row announces "Your team, 1 people" — the a11y label hardcodes `${headcount} people` while `teamHeadcountLine` already pluralises the visible line. Use the same rule. [src/features/technicianApp/ProfileScreen.tsx:204]
- [x] [Review][Patch] The invite refusal's appended sentence can lose its full stop — `${err.message || …} No invite was sent.` yields "…manager is not active No invite was sent." when the server line has no terminator; `convertPartialFailureMessage` in `ownerLeaveModel.ts` already exists for exactly this. [src/features/technicians/components/AddTechnicianSheet.tsx:83-84]
- [x] [Review][Patch] A second Reports-to save in the same sheet session uses stale chains — `saveManager` patches only the saved row into `members`, so editing a member *below* the one just re-parented still offers candidates from the old tree and can earn a `HIERARCHY_CYCLE` 409. Bump the existing `fetchTick` after a successful save. [src/features/technicians/components/JobSettingsSheet.tsx:132-150]
- [x] [Review][Patch] The two job-detail screens re-implement the job read-only sentence inline and take the name from the assignee — `teamModel.jobDecisionNote` already owns the copy, including the "this person" fallback, and is tested; the screens' copies can diverge (and the note-only footer lacks the `SafeAreaView edges={['bottom']}` the buttoned footer has). Import the helper in both and add the inset. [src/features/jobDetail/JobDetailScreen.tsx:685-695, src/features/technicianApp/TechJobDetailScreen.tsx:457-467]
- [x] [Review][Patch] No test covers the leave-card tap split — `tapTargetForLeave` gained a required `role` and the `team-pending` case; nothing imports it. Add a role table (admin → `OwnerLeave`, employee/viewer → `YourTeam · Leave`, `team-pending` for every manager, `attendance-guarded` guard) plus an `openTapTarget` `YourTeam` navigate case. [src/features/notifications/notificationTapModel.ts:136-159]
- [x] [Review][Patch] The push matrix has no row for the new leave destinations — `notificationTapModel.push.test.ts` still covers only admin `leave.applied`/`pending_reminder` and employee `leave.approved`; the four new manager rows and both approver events are unasserted, so the push entry point can regress silently while the inbox works. [src/features/notifications/notificationTapModel.push.test.ts:133-170]
- [x] [Review][Patch] The two new job approver cards and the `tappable` flag have no test — there is no `jobApprovalNotificationModel.test.ts`; assert the seven titles, `tappable: false` only for `job.approver_removed`, and that both new types classify `'job-approval'`. [src/features/notifications/jobApprovalNotificationModel.ts:63,136]
- [x] [Review][Patch] `teamOnly` is never asserted at the wire — `jobService.list` forwards it (`jobs.ts:464`), but `__tests__/jobs-service.test.ts` has no case; the queue test stops at the mocked service. Add one axios-params case, so a viewer's company-wide read cannot leak the tenant's pending list unnoticed. [src/services/resources/jobs.ts:464]
- [x] [Review][Patch] The manager read-only posture in the technician detail is untested — no test seeds `useMyProfileSnapshot`, so `myId` is always `null` and `isOwnJob` always true; assert a non-assignee manager sees no workflow bar/advance and no shared-store upserts. [src/features/technicianApp/TechJobDetailScreen.tsx:324-329]
- [x] [Review][Patch] The viewer-manager decision bar on the owner job detail is untested — no fixture carries a `decision`, so the widened condition (`canWrite || decision.canDecide`) and the quiet-reason branch are unpinned; the only viewer case asserts the bar is absent on a fixture without a `decision`. [src/features/jobDetail/JobDetailScreen.tsx:656-700]
- [x] [Review][Patch] The invited employee's `managerId` is verified only up to the sheet's `onSubmit` — `useTechnicians.add` spreads it onto the invite call, and no test mentions `managerId`; assert the invite body carries it and that the key is absent when unset. [src/features/technicians/useTechnicians.ts:216-222]
- [x] [Review][Patch] `LeaveDetailSheet`'s read-only suppression has no test — the sheet replaces its whole action slot when `readOnlyNote != null` (and gates revoke on it), but only the card's sibling prop is tested; render the sheet with a note and assert the sentence shows and no Approve/Decline buttons exist. [src/features/attendance/leave/LeaveDetailSheet.tsx:250-270]
- [x] [Review][Patch] The three team panes have no tests — `YourTeamScreen.test.tsx` stubs them, so the Leave approve/decline wiring, the Jobs reject sheet, the read-only rows and the People directory/apply action are unverified. Cover the decision matrix and the disabled/absent actions per status. [src/features/team/components/TeamLeavePane.tsx, TeamJobsPane.tsx, TeamPeoplePane.tsx]
- [x] [Review][Defer] The manager apply-on-behalf copy contradicts EXPERIENCE Surface 3 — [src/features/attendance/leave/ApplyOnBehalfScreen.tsx:133-141] — deferred: the plan's triage #3 deliberately overturned the born-approved copy ("Approve"/"recorded as approved") for a manager; the fix is to update the UX document, not the code.
- [x] [Review][Defer] `deactivated` reads as an ordinary offline technician in the pickers — [src/features/technicians/useTechnicians.ts:135-145] — deferred: pre-existing `toTechnician` mapping (only the `CompanyMember` union widened here); revisit when the BE starts returning `deactivated` on the `/users/me` technician roster.
- [x] [Review][Defer] The two queue hooks and their panes are near-clones — [src/features/team/useTeamLeaveQueue.ts, useTeamJobQueue.ts] — deferred: a shared paged-queue/render hook would prevent the postures drifting (they already differ on reject-sheet error handling), but the refactor is larger than this story's scope.

**Rejected**

- `false` — LeaveDetailSheet offers buttons for a `canDecide: false` row with a null note: EXPERIENCE declares `not_pending` "never in this list" (the queue reads `status=pending`), so the gate's only reachable false case is a backend that predates `decision`, which the story does not support.
- `false` — `decisionNote`/`jobDecisionNote` return null for reasons other than `higher_manager`/`unresolved`, leaving a row inert with no explanation: `not_pending` cannot appear on a pending row; the model test pins the null as intended copy.
- `low` — the two job detail screens fall back to "Someone closer to …" for a non-`higher_manager` reason: unreachable while the bar only renders on `pending_approval`, and the server's reason set for that state has no third value.
- `false` — "Someone closer to themselves" on the submitter's own pending job: EXPERIENCE Surface 4's copy names `{employee}` (the creator), so the sentence is per the approved document.
- `low` — the inert `job.approver_removed` card still renders as a Pressable (`onPress` always passed) and marks read on tap: the model's comment intends the mark-read, and making it fully inert would remove the only way to clear its unread dot.
- `low` — no focus refresh on the team panes, so a job approved from the detail stays in the queue until pull-to-refresh: auto-refresh on focus is new behavior; EXPERIENCE specifies pull-to-refresh only.
- `low` — a second row's Approve tap while one write is in flight is swallowed with no feedback: requires a deliberate two-row double tap; the fix (disabling every row while busy) adds state the list does not have.
- `low` — a 409 on a row loaded from page 2+ refetches page 1 and drops the loaded pages: rare (a decision landing elsewhere while paging) and the reconcile refetch is the shipped owner behavior.
- `low` — `useTeammatesOff` reads one 50-row page and can under-report the "and N more" count: it cannot turn into "Nobody else is off" (that needs an empty page), and paging a glance strip costs more than the error it prevents.
- `false` — `ManagerPickerStage`'s search calls `member.employeeCode.toLowerCase()` on a nullable field: the stage receives `CompanyMember[]`, where `employeeCode` is a non-null `string`.
- `false` — the two job details name a different person than the queue card: a pending job's technician *is* the creator (CAP-2 creator-assigned), so both name the same person; the copy duplication is patched separately.
- `low` — a viewer-manager decision on `JobDetailScreen` upserts the shared jobs store and forces a profile reload: the stores are the owner-stack lists the viewer already reads company-wide, and the decision response is that job's truth.
- `low` — `isAdmin` is hand-rolled (`profile == null || role === 'company_admin'`) so a `platform_admin` takes the manager branch: a `platform_admin` never reaches this screen (the People action is hidden and `hasTeam` excludes them); only a hand-typed deep link would.
- `low` — a viewer who deep-links `ApplyOnBehalf` reads team routes their role lacks and submits untyped: no UI path reaches the screen for a viewer (the People action is hidden); the server still re-verdicts the write.
- `false` — the manager picker offers active members who cannot take on-behalf leave: the plan's triage #7 records this as an accepted limitation (no role/leave-tracking data in `team.members`), and the refusal copy was written for exactly that.
- `low` — `listOwnerLeave`'s `from`/`to` docblock still attributes the window to 27-1: a stale attribution in a comment, no behavior.
- `low` — `TeamMember.status` is `string` while `CompanyMember` uses a union, and `TeamChainLink` duplicates `MemberChainLink`: developer-only typing debt with no caller that diverges today.
- `low` — `isOwnJob` treats the creator as the assignee: the clause exists for creator-assigned pending jobs and removing it risks hiding the workflow from its rightful owner; the reachable bad case (a job reassigned away from its creator) is rare.
- `low` — `loadMembers` in `AddTechnicianSheet` has no unmount/cancelled guard: the sheet's fetch resolves into a still-mounted sheet in every reachable flow.
- `low` — `TeamJobApprovalCard`'s `showActions` gate is redundant with its host: it is a second safety rule, not a defect.
- `false` — `copyFor`'s `leave.pending_reminder` comment describes a split that "isn't there": the split happens in `tapTargetForLeave`, which the card's tap feeds, so the comment is accurate.
- `low` — the Approach's `headcount > 0` gate versus the notification classifier's role keying: the server only addresses manager events to managers, and the screen's `hasTeam` is the gate; the divergence is the plan's triage #6, not a defect.
