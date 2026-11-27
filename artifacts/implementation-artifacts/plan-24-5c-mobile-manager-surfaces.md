---
title: 'The manager works their branch from the phone — Your team queues, team directory, apply-on-behalf, and Reports-to editing'
type: 'feature'
created: '2026-11-27'
status: 'in-progress'
route: 'full'
route_source: 'auto'
review: ''
review_source: ''
lenses_ran: []
review_loop_iteration: 0
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

## Verification

**Commands:** `bun run typecheck`, `bun run lint` (changed files), `bun run test` (after the device pass).
**Device (Pixel 6):** manager `8202260000` in tenant 24-4 Probe — Your team shows the report, a seeded pending leave and pending job approve/reject end to end, apply-on-behalf lands with the manager above, and a report's job detail decides; owner `7700000002` in PayrollQA Works — invite with Reports-to, change/clear on the member sheet, chain + headcount, viewer note.
**Live API:**
- `GET /users/me` team block (already verified in 24-5b).
- The seeded fixtures are removed after the pass; no production tenant is mutated.
