---
title: 'The owner sees and edits the reporting tree on web — a Reports-to column, the member record editor, and a manager on the invite'
type: 'feature'
created: '2026-11-27'
status: 'done'
commit: 'c1ab204'
route: 'full'
route_source: 'auto'
review: 'REVISE — adversarial review 2026-11-27; 3 HIGH, 8 MEDIUM, 9 LOW triaged and folded'
review_source: 'subagent adversarial review'
lenses_ran: ['adversarial']
review_loop_iteration: 1
baseline_commit: '465e5d2'
baseline_revision: '465e5d2'
context:
  - 'artifacts/specs/spec-company-hierarchy/SPEC.md'
  - 'artifacts/specs/spec-company-hierarchy/approval-routing.md'
  - 'artifacts/implementation-artifacts/epic-24-context.md'
  - 'artifacts/implementation-artifacts/spec-24-1-backend-hierarchy-data-model-and-manager-assignment.md'
  - 'artifacts/implementation-artifacts/plan-24-5c-mobile-manager-surfaces.md'
  - 'artifacts/planning-artifacts/ux-designs/ux-fenzit-2026-11-27-manager-team/EXPERIENCE.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** The backend has carried the reporting tree since 24-1..24-4 — `memberships.manager_id`, the member payload's `managerId` / `managerName` / `chain` / `headcount` / `directReports`, `PATCH /members/:userId/manager`, and the optional `managerId` on invite. The owner console still shows a flat team: no Reports-to column, no way to see the upward chain or who a person's subtree is, no way to assign or clear a reporting manager, and no manager on the invite. Story 24-6 (CAP-6) is unbuilt in `fenzit-web`.

**Approach:** `MembersTable` gains a read-only **Reports to** column (the chain with the top admin marked `(Owner)`, plus the headcount below) resolved from the full roster the loader reads. The **employee profile** (the member record) becomes the one place the owner edits it: a "Reports to" block in the header with the chain, headcount and role, a **Change** control that opens a picker dialog (active members, self + subtree excluded, search, the D13 viewer note), and an explicit re-parent confirmation before the save when the member has direct reports. The **invite dialog** gains the same optional picker and posts `managerId` only when chosen. Owner-only; managers still land on their existing web surfaces and web approvals stay out of scope.

</frozen-after-approval>

## Boundaries & Constraints

**Always:**
- `fenzit-web` only. No BE/DB change: `PATCH /members/:userId/manager` takes `{ managerId: string | null }`, invite takes the optional `managerId`, and both `GET /members` and `GET /members/page` already carry the hierarchy. If a need proves impossible with the shipped contract, stop and report.
- Read the roster with `GET /members` in the existing owner loaders (settled independently, non-fatal) — the same read the console overview uses. No new client cache, no TanStack Query, no fetch in `useEffect`. Server data stays in loader data; only the dialog's open/selection/search is `useState`.
- The owner gate is `requireConsoleRole(request, ["owner"])` in every loader/action touched — the console is owner-only and a manager must not see this surface.
- Copy is the story/spec vocabulary verbatim: **"Reports to"**, **"Reporting manager"**, **"(Owner)"**, **"Not set"**, "Admins sit at the top of the team.", "3 people report to them", the D13 viewer note. Never L1/L2/L3, never "Technician".
- Refusals are mapped by `error_code` through `messageForError` (the standards rule, never the developer `message`). The four manager codes get their own entries in `src/utils/errorMessages.ts`, so the invite and the profile dialog can both show a sentence a user can read.
- The table cell is read-only. The profile header is the only editor. Admins say "Admins sit at the top of the team." and carry no Change control; the headcount line still renders for everyone (EXPERIENCE Surface 5).
- The picker excludes the member themselves and everyone below them (their subtree) — using the server-provided `chain` (no client tree walk), because the server would answer `HIERARCHY_CYCLE`. Clearing is a valid choice ("No reporting manager").
- The current manager is always representable: when they are no longer active (deactivation leaves `manager_id` in place), the dialog shows them as the selected, non-selectable row ("No longer active") so Save cannot silently clear the pointer.
- Re-parent confirmation: when the member has `directReports > 0` and the pick changes, Save first shows what changes ("X's 3 direct reports will now report to you."); nothing posts until Confirm. Clearing says "X will have no reporting manager, so their team's requests go to the company admins."
- Refusals (`MEMBER_IS_ADMIN`, `HIERARCHY_CYCLE`, `HIERARCHY_DEPTH`, `MANAGER_NOT_ACTIVE`, `RESOURCE_NOT_FOUND`) keep the dialog open with the mapped plain-English sentence and the previously shown value untouched.
- Every new surface has loading, error and empty states. CSS Modules only, tokens only (`--space-*`, `--color-*`, `--radius-*`), no raw hex, no `any`, files under ~300 lines.
- The candidate list is its own bounded scroll box (a `max-height` token) with the footer actions outside it, so a 200-person roster can never push Save/Confirm below the fold (the 24-5c device finding).
- Responsive at 360 / 390 / 768 / 1280 px with no **page-level** horizontal scroll. The employees table keeps its existing in-card `overflow-x` scroll (the column joins it); the dialog fits phone widths.

**Never:**
- No manager web-approval surface, no widening of `consoleRole`/`sectionsFor`, no new sidebar entry, no manager console.
- No manager on the Job settings dialog (the owner chose the profile page as the editor); the deviation from CAP-6's "member settings dialog" wording is recorded below.
- No new design-system component or new dependency; compose `TextInput`, `Button`, `SectionCard`, `Spinner`, `Avatar`, and the existing dialog idioms.
- No silent drops: a malformed `managerId` on the invite is a visible validation error, and an unselected manager is simply absent from the body.
- No test file until the owner confirms the behaviour (house test-timing rule).

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|---|---|---|---|
| Table column, member with manager | `managerName`, `chain [Priya, Arjun]`, Arjun admin | "Priya → Arjun (Owner)"; below it "3 people report to them" when `headcount > 0` | roster read failed → plain chain names, no `(Owner)`, no crash |
| Table column, unassigned member | `managerId null`, `headcount 0` | "Not set" | — |
| Table column, admin row | role `company_admin`, `headcount 3` | "Admins sit at the top of the team."; headcount line still shown | — |
| Table column, invited / deactivated | any non-admin | chain shown; the profile editor still works | — |
| Profile header, member | chain + headcount | "Reports to Priya → Arjun (Owner)", "3 people report to them", a **Change** control | roster failed → chain still shown, Change disabled with the reason |
| Profile header, admin | role `company_admin` | "Admins sit at the top of the team."; headcount line; no Change | — |
| Profile header, own record (admin) | `selfUserId` | no Change | — |
| Picker, candidates | editing Priya | active members minus Priya and her subtree; search by name / EMP code / phone; role word under the name | roster failed → inline error + Retry |
| Picker, current manager inactive | `managerId` points at a deactivated member | that row is shown first, selected, non-selectable, "No longer active" | Save keeps the pointer unless the owner picks another |
| Picker, viewer candidate | chosen role `viewer` | neutral D13 note before Save | not an error colour |
| Re-parent confirmation | Priya has 3 direct reports, pick changes | "Priya's 3 direct reports will now report to you." (or "... to Sanjay."); Confirm posts | Back returns to the list, nothing posted |
| Clearing with reports | pick "No reporting manager" | "Priya will have no reporting manager, so their team's requests go to the company admins." before Confirm | — |
| No-op save | picked id equals the stored id | Save is allowed, the server writes nothing, dialog closes, "Reporting manager updated." | — |
| Save refusal | `MEMBER_IS_ADMIN` / `HIERARCHY_CYCLE` / `HIERARCHY_DEPTH` / `MANAGER_NOT_ACTIVE` | mapped sentence, dialog open, previous value untouched | — |
| Save success | — | dialog closes, header chain/headcount refresh, toast "Reporting manager updated." | — |
| Invite with manager, unset | picker untouched | POST body has no `managerId` | invite still succeeds |
| Invite with manager, chosen | member chosen | POST carries `managerId` | refusal in the dialog's error slot, dialog open |
| Invite with malformed id | non-UUID `managerId` value | validation error, nothing sent | "Please choose a reporting manager from the list." |
| Invite, roster failed | directory slice failed | manager row disabled with "Reports to can't be set right now." | invite without a manager still works |
| Manager signed in | role `employee` | route guard sends them to the existing member surfaces; no console | 403 → login/redirect as today |

## Code Map

**Wire types + calls**
- `src/features/admin/companyApi.ts` — `MemberChainLink`; `MemberRow` gains `managerId`, `managerName`, `chain`, `headcount`, `directReports`; `setManager(token, userId, managerId | null): Promise<MemberRow>` (`PATCH /members/:userId/manager`); `inviteMember` input gains optional `managerId` and forwards it only when present.
- `src/features/admin/employeeProfileApi.ts` — `EmployeeProfile` gains the same five hierarchy fields.
- `src/utils/errorMessages.ts` — `MEMBER_IS_ADMIN`, `MANAGER_NOT_ACTIVE`, `HIERARCHY_CYCLE`, `HIERARCHY_DEPTH` entries (plain English, owner/team vocabulary). `RESOURCE_NOT_FOUND` already maps.

**Pure model (new)**
- `src/features/admin/memberHierarchy.ts` — `roleMap(members)`, `chainLine(chain, roles)` (append `(Owner)` for an admin, `null` when empty), `reportsToValue(member)`, `headcountLine(n)` (null at 0, singular at 1), `managerCandidates(members, memberId)` (active, not self, not a candidate whose server `chain` contains the member), `viewerManagerNote(role)`, `roleWord(role)` (reuses `ROLE_WORDS`), `reparentNotice(...)` (assign / clear variants), `sameManager(a, b)` (id comparison), `inactiveCurrentManager(member, candidates)`.

**Employees page**
- `src/features/admin/adminBrowseLoaders.ts` — `EmployeesData.ok` gains `directory: Slice<MemberRow[]>`; the loader fetches `fetchMembers` alongside the page and countries (settled, non-fatal); the `invite` intent reads `managerId` (UUID-shaped; a malformed value is a visible validation error) and passes it through.
- `src/features/admin/components/MembersTable.tsx` (+ `.module.css`) — the new **Reports to** column after Role; the chain + headcount cell; admins read the top-of-team line.
- `src/features/admin/components/AddEmployeeDialog.tsx` (+ `.module.css`) — an optional "Reports to" row (value "Not set"), hint "Optional. You can change this later.", the shared picker inline, a hidden `managerId` posted only when chosen, and the disabled-with-reason state when the roster failed.
- `src/pages/AdminEmployeesPage.tsx` — pass `directory` into `MembersTable` and `AddEmployeeControl`.

**Shared picker (new)**
- `src/features/admin/components/ManagerPicker.tsx` (+ `.module.css`) — search field, "No reporting manager" option, bounded radio list (EMP code + role word), selected mark, the inactive-current-manager row, the D13 note, the empty search line, and the roster error + Retry slot. Used by the invite dialog and the profile dialog.

**Employee profile (the member record)**
- `src/features/admin/employeeProfileLoaders.ts` — one hoisted `settle(() => fetchMembers(...))` in the ok path (every ok variant gains `directory: Slice<MemberRow[]>`); action gains `intent === "manager"` (`userId` from the path, `managerId` from the form; `""` clears) returning `{ kind: "manager", … }`, refusal copy via `messageForError`.
- `src/features/admin/components/employee/ReportingBlock.tsx` (+ `.module.css`) — the header block: "Reports to" + chain, headcount line, admin line, **Change** control.
- `src/features/admin/components/employee/ManagerDialog.tsx` (+ `.module.css`) — the dialog host + stages: picker → re-parent confirmation → save; saved/error states, roster retry, dialog lock while saving, focus moves to the confirmation and returns to Change.
- `src/pages/AdminEmployeeProfilePage.tsx` — render `ReportingBlock` in the header, host `ManagerDialog`, widen the activate result handling to `kind === "activate"`.

**Test fixtures**
- `src/testing/employeesPageKit.tsx` — `row()` gains the hierarchy defaults (`managerId: null`, `managerName: null`, `chain: []`, `headcount: 0`, `directReports: 0`), with per-test overrides.
- `src/pages/AdminEmployeeProfilePage.test.tsx` — `memberProfile()` gains the same fields.

**Docs**
- `artifacts/implementation-artifacts/sprint-status.yaml` — `24-6-web-manager-column-and-editing` line.
- No release-notes file until a release is declared.

## Tasks & Acceptance

1. **Wire + model + fixtures** — types, `setManager`, invite `managerId`, directory slice in both loaders, error-code entries, `memberHierarchy.ts`, the two shared fixtures. Acceptance: `bun run typecheck` clean; a page without a directory still renders (settled slice); the pure model answers the matrix rows.
2. **Table column** — read-only Reports-to cell. Acceptance: chain with `(Owner)`, "Not set", top-of-team line, headcount line; no page-level horizontal scroll at 360 px (the table keeps its in-card scroll).
3. **Profile block + dialog** — header block and the picker/confirm/save flow. Acceptance: assigning, re-parent confirm, clearing, inactive current manager, refusal sentence, viewer note, roster retry, double-click cannot double-post.
4. **Invite field** — optional picker and wire. Acceptance: omitted when unset; sent when chosen; malformed id refused visibly; refusal surfaces in the dialog.
5. **Responsive + a11y pass** — 360/390/768/1280, keyboard order, fieldset/legend on the radio list, dialog accessible name, `role="alert"` refusals, focus to the confirmation and back to Change, reduced motion. Acceptance noted in this plan.
6. **Docs** — sprint status + this plan's verification.

## Test Plan (written after the owner confirms, per the house rule)

- `memberHierarchy.test.ts` — chain text with/without `(Owner)`, null/1/3 headcount, candidates (self, subtree via `chain`, inactive excluded), current-inactive detection, viewer note, re-parent copy (assign to you / to a name / clear), `sameManager`.
- `MembersTable.test.tsx` — the four cell shapes; the cell carries no button; admin headcount still renders.
- `ManagerDialog.test.tsx` — candidate list, search, viewer note, no-op save, re-parent confirm with 1 vs 3 reports, clear path, inactive current manager preserved, refusal keeps the dialog open with the mapped sentence and the old value, roster error + Retry, double-submit.
- `AddEmployeeDialog` test — the hidden `managerId` is absent when unset and present when chosen; malformed id is a visible error; refusal stays in the dialog.
- `employeeProfileLoaders.test.ts` / `adminBrowseLoaders.test.ts` — the manager intent (owner gate, `""` → null, mapped refusals), the invite payload's optional field and validation, the directory slice's failure being non-fatal.
- `companyApi.test.ts` — `setManager` wire (PATCH body `{ managerId }`, null on clear) and `inviteMember` omission.
- `AdminEmployeeProfilePage.test.tsx` — header chain/headcount, admin line, the dialog flow, focus moves, the refreshed header after save.
- `AdminEmployeesPage.test.tsx` — the column renders; invite with a manager; `check:styles` pairing for every new component.

## Design Notes

- **Why the profile page owns the edit** (owner decision 2026-11-27): the table stays scannable, and the edit sits on the record that already shows the person's identity, flags and statutory fields. The `Job settings` dialog stays job-only, so no dialog gains an unrelated section.
- **Recorded deviation from CAP-6 / story 6 / EXPERIENCE Surface 5** — the SSOT says "the member settings dialog", and the approved mobile UX puts the editor in `JobSettingsSheet`. The owner chose the web member record (profile page) instead. Nothing else in CAP-6 changes; mobile keeps its shipped sheet. This is deliberate, not a missed requirement, and should be read that way at the spec checkpoint.
- **Why the loader reads the roster** — `(Owner)` marking, the invite picker and the exclusion set all need role and chain data for people outside the current page. `GET /members` is the shipped read the console overview already uses; a settled slice keeps a failed read from blanking the table or the invite. **Cost, stated:** the read runs two recursive CTEs and one avatar presign per member. Measure it on the largest tenant during verification; if the employees page load regresses, move the picker's roster to the shipped on-open resource-route pattern (`company/employees/employment`) and keep the table's chain read-only without the `(Owner)` marker.
- **Client cannot guess the tree** — every save is re-checked by the server; the client only narrows the candidate list so the owner is not offered a guaranteed refusal. A demoted manager loses subtree rights on the next read, never from cached client state.
- **No `(Owner)` inference from position** — the chain carries `{ userId, name }` only; the role map comes from the roster, because a branch's top can be an unassigned non-admin.
- **Subtree exclusion is chain lookup, not a client walk** — a candidate whose server-computed `chain` contains the member is below them; no depth cap is needed because the server already caps and dedupes the chain.
- **Refusal copy is code-first** — the standards require `messageForError`; the four new entries are the one place the sentences live, so invite and dialog agree.
- **Scope acceptance (recorded):** console routes have no `errorElement`, so a failed *revalidation* after a save replaces the page with React Router's default panel. That is pre-existing for every console loader (including activate) and not introduced here; adding route boundaries is a console-wide change, so it is consciously accepted rather than patched in this story.
- **Ledger scan** — `deferred-work.md` has no entry owned by 24-6. "Web approval surfaces for managers" is explicitly out of this epic (D2); "manager-queue triage gaps" is app-side; both stay out.

## Plan-review triage (2026-11-27)

Verdict **REVISE** (3 HIGH, 8 MEDIUM, 9 LOW). All findings folded or consciously accepted:

1. **H1 invite refusal** — added the four `error_code` entries and made both intents use `messageForError` (standards rule; no `message` pass-through).
2. **H2 inactive current manager** — the dialog seeds from `managerId`, shows a non-selectable "No longer active" row, compares ids, so Save cannot silently clear.
3. **H3 unbounded list** — the candidate list gets its own bounded scroll box; footer actions stay outside it; 200-row case added to verification.
4. **M1 invented "Top of team"** — replaced with the approved "Admins sit at the top of the team." in both places.
5. **M2 clear-path copy** — rewritten to say what actually happens (requests go to the company admins).
6. **M3 SSOT deviation** — recorded explicitly in Design Notes.
7. **M4 impossible revalidation clause** — removed; the missing console `errorElement` is recorded as a conscious scope acceptance.
8. **M5 fixtures** — `employeesPageKit.tsx` and `AdminEmployeeProfilePage.test.tsx` added to the Code Map and task 1.
9. **M6 360 px** — restated as "no page-level scroll; the table keeps its in-card scroll" (today's behaviour).
10. **M7 role word duplication** — `roleWord` derives from the existing `ROLE_WORDS`.
11. **M8 roster cost** — cost stated with a measurement gate and a fallback.
12. **L1 "you"** — branch on `managerId === selfUserId`, not the name.
13. **L2 `RESOURCE_NOT_FOUND`** — covered by `messageForError`'s friendly line.
14. **L3 client walk** — exclusion is a server-chain lookup; no walk, no cap needed.
15. **L4 silent invite drop** — a malformed id is a visible validation error.
16. **L5 five fetch sites** — one hoisted settled read in the profile loader.
17. **L6 a11y assertions** — added to task 5 and the test plan.
18. **L7 persistence** — added to verification.
19. **L8 double submit** — added to the dialog tests.
20. **L9 admin headcount** — headcount renders for everyone; only the chain is replaced by the top-of-team line.

## Verification

**Commands:** `bun run typecheck`, `bun run lint`, `bun run test` (**1434 tests / 121 files green**), `bun run check:styles`, `bun run format:check`, `bun run build`; widths 360 / 390 / 768 / 1280.
**Owner confirmation:** delegated to the agent for this story (owner instruction 2026-11-27); the browser flow was walked and signed off on the live QA tenant.
**Persistence:** after a save, reload the profile (and read the member from a second surface) and confirm `managerId`/`chain` survived — the same check the 24-5c device pass made.
**Scale:** the picker's list is its own bounded scroll box; Save/Confirm stay reachable with a 202-member roster.

### Cross-surface verification (2026-11-27, web + Pixel 6 `1C301FDF6002ZB`)

The BE is shared, so each direction was driven and checked on the other surface (PayrollQA Works, both surfaces signed in as the owner):

| # | Driven on | Checked on | Result |
|---|---|---|---|
| 1 | Web: assign Rahul Bhat → owner | Phone: Rahul's Job settings sheet | "Reports to PQA Owner Ashok Rao", chain "PQA Owner Ashok Rao (Owner)", "1 person reports to them" |
| 2 | Phone: assign Deepak Yadav → Rahul | Web: Rahul's profile + member read | header "Deepak Yadav", `managerId` persisted; Deepak's subtree headcount 2 (Rahul + Kavita) |
| 3 | Web: assign Kavita → Rahul | Phone: Kavita's sheet | chain "Rahul Bhat → Deepak Yadav" |
| 4 | Web: picker for Deepak | — | Rahul (EMP-038) and Kavita (EMP-039) not offered (his subtree); owner offered |
| 5 | Phone: picker for Rahul | — | Kavita (his report) not offered |
| 6 | Web: deactivate Deepak, then open Rahul's picker | Phone: same picker, then Save | Web shows the selected "No longer active" row; phone's Save (no change) kept the pointer (no silent clear) |
| 7 | Web: admin profile | — | "Admins sit at the top of the team.", no Change control |
| 8 | Web: viewer token opens `/admin/company/employees` | — | redirected to `/login` — the console stays owner-only |

**Negative contract checks (live API, owner token, every call refused and no state changed):**

| Attempt | Result |
|---|---|
| Assign a manager to the owner | `409 MEMBER_IS_ADMIN` |
| Make a cycle (Rahul → Kavita) | `409 HIERARCHY_CYCLE` |
| Assign Rahul to himself | `422 VALIDATION_ERROR` ("A person cannot report to themselves") |
| Assign a non-member id | `404 RESOURCE_NOT_FOUND` |

Tenant restored after the pass (all seeded managers cleared).

### Browser checks

- Table: "Not set", the chain with `(Owner)`, the headcount line, the admin top-of-team line; read-only cell.
- Profile: chain + headcount + Change; admin line with no Change; roster-failure state with Try Again.
- Dialog: centered, scrolls, candidate list bounded, subtree excluded, DVM viewer note, re-parent confirmation with Back/Confirm, clear path, refusal keeps it open, saved line.
- 360/390/768/1280: no page-level horizontal scroll (the table keeps its in-card scroll; it now fits at 1280 after the width tweak). At 360 the dialog is 360 wide, fits vertically and scrolls internally.
- Invite: optional Reports to picker; the hidden `managerId` fills; Enter in the picker's search does not submit the invitation.

### Additional fixes found during verification (same story, same surface)

1. **Edit Profile dialog was unpositioned** (pre-existing): the page's own `.dialog` rules never carried the modal centering, and the global reset removed the UA's `margin: auto`, so the fifteen-field dialog sat at the top-left. The page now reuses the console's one dialog chrome (`JobSettingsDialog.module.css` + the payroll `wideDialog`), so it cannot drift again.
2. **Enter in the invite's manager search submitted the invite**: `TextInput` gained an optional `onKeyDown`, and the picker's search stops Enter.
3. **`Button` gained `autoFocus`** for the confirmation stage, so focus moves to Confirm and the native dialog returns it to Change on close.

### Code review (BMAD `bmad-code-review`, thorough, 2026-11-27)

Four lenses ran on the uncommitted `fenzit-web` diff (blind-hunter, edge-case-hunter, verification-gap, intent-alignment); 50 raw findings, all verified against the surrounding code before grading. Patched in this story:

| # | Finding | Fix |
|---|---|---|
| 1 | An unchanged Save against a deactivated manager posted anyway; the server runs `assertManagerAssignable` before its no-op return, so doing nothing answered `MANAGER_NOT_ACTIVE` | Save is disabled until the pick differs, with a reason; the stale manager row is a disabled radio (as its comment always claimed) |
| 2 | The Enter-in-search test could not fail: it never filled the form, so Send was disabled | The test fills the invite, asserts the list filtered, and asserts `preventDefault` ran |
| 3 | The invite action's malformed-`managerId` guard had no test, and a test comment claimed it did | New case in `employeesAction.test.ts`: visible sentence, no request |
| 4 | The invite dialog's picker retry was unreachable (`pickerOpen && !directoryFailed`), leaving `retryDirectory` dead | The picker mounts on failure and owns its "Try Again"; the row is enabled and gains `aria-controls`/`aria-describedby` |
| 5 | The profile loader dropped the roster promise on the not-found/throw paths, hiding a 401 redirect as an unhandled rejection | The slice is pre-consumed with `void …catch` |
| 6 | Back from the re-parent confirmation was untested (wiring it to submit would pass) | The confirm test backs out, asserts nothing posted, then confirms |
| 7 | The header refresh after a save was untested | The test closes the dialog and asserts the new `(Owner)` chain |
| 8 | `autoFocus` on Confirm was untested | Asserted via `document.activeElement` |
| 9 | `reparentNotice` accepted a missing `directReports` and wrote "undefined direct reports" | `Number.isFinite` guard, matching `headcountLine` |
| 10 | `chainLine` printed a null name ("null (Owner)") because `users.name` is nullable | Falls back to "Team member"; covered |
| 11 | The D13 viewer note was unasserted on the invite path | Asserted in the invite's chosen-manager test |

Rejected with reasons: save-success keeping the dialog open (the invite dialog's shipped saved-stage pattern; the I/O matrix's close+toast is not the frozen intent), the D13 sentence's phrasing (approved verbatim), "people report to them" vs "direct reports" (subtree vs immediate is the contract), the owner/admin nouns (both approved), and the duplicated UUID regex (three copies, no demonstrated divergence).

Deferred, recorded here: the block does not show the member's own role though the frozen intent names it; the table loses `(Owner)` marks silently when the roster read fails; the CSV export has no Reports-to column; and the roster read's cost is still unmeasured on the largest tenant. The first two are reworked by the 24-7 owner-default story (below), the export is a product call, and the cost is the plan's named fallback (on-open resource route) if the employees page load regresses.

### Design exploration (Stitch, 2026-11-27)

A colourful restyle of the Edit Profile popup was generated in the Epic 24 project (`129662491942565583`, Field Utility System) and is saved under `artifacts/implementation-artifacts/design-24-6/` (Job / Personal / Statutory IDs / Bank states). Sections are grounded in the real 15 employment fields and real-shaped values; no invented capability. This is an exploration for the owner's decision, not shipped code.

