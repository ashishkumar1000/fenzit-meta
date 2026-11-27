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

A colourful restyle of the Edit Profile popup was generated in the Epic 24 project (`129662491942565583`, Field Utility System) and is saved under `artifacts/implementation-artifacts/design-24-6/` (Job / Personal / Statutory IDs / Bank states). Sections are grounded in the real 15 employment fields and real-shaped values; no invented capability. The owner asked Sally to review it before implementation; the review and the shipped version are below.

### Design implementation (2026-11-27, after Sally's review)

Sally's critique (dual-agent: independent design read + code/token evidence) scored the mockups **15/40** and rejected the four-hue rail. The full report is saved beside the mockups as `design-review-2026-11-27.md`; the measured reasons: only two of the four active fills are tokens, there is no violet family in either repo, the green Bank tab collides with the product's "done" meaning, white on `#06956F` is 3.79:1 and the idle amber is 3.07:1. `DESIGN_SYSTEM.md` already says a chip's active state is a soft tint, never a solid fill.

The owner chose **one accent with a soft-tint active tab** (the P0 fix) and the full **P0+P1+P2** set. The four groups, the tinted panel and the pinned footer survived; the rainbow did not.

**What shipped**

- `EmploymentForm.tsx` — the four sections as a real tablist (`role=tab`, `aria-selected`, `aria-controls`, roving tabindex, Left/Right/Home/End, one panel labelled by the active tab). A section with unsaved edits carries its count; the footer carries the total.
- The form opens on the section the clicked link points at: the Master Record banner opens the section of its first missing field, and each "+ Add" opens its own field's section.
- Save is disabled until a field differs, with the reason in the footer; the footer states the destructive half of the tri-state ("Emptying a field clears it"); Cancel and Esc ask before dropping edits, and a backdrop click is held while edits are pending (the pinned Cancel opens the prompt); the footer actions are 44px.
- Header trimmed to the title and the person's name. No avatar, designation, department or status pill: the host already shows them, status is not editable here, and the two editable fields would go stale while typing.
- `dialogRail` in the shared chrome stops the box scrolling as a whole; the shell's grid keeps the header, rail and footer fixed and scrolls only the body. A modifier, not a change to `.dialog`, because twenty other dialogs still rely on that scroll.
- One accent: active tab `primary-soft` + `primary` border + `primary` label; inactive tabs `surface-sunken`. Icons carry the section identity (Briefcase, UserRound, IdCard, Landmark); the counts are tinted chips, not solid primary.
- At 360px the rail wraps to two rows, the fields go one column, the footer note takes its own line and the actions stay 44px. Verified in a 360×820 iframe against the live QA tenant; the dialog's own `scrollWidth` equals its `clientWidth`.

**Employment contract (build-time)**

The owner's rule: the FE should be a dumb layer. The field list and constraints now come from the BE DTO, not a second local list.

- fenzit-be `src/members/dto/update-employment.dto.ts` carries `maxLength`, `pattern` and `format: date` in the Swagger metadata, next to the validators (the limits live in one `MAX` object so they cannot disagree).
- `bun run contract:employment` (fenzit-be, `scripts/export-employment-schema.ts`) builds a minimal Nest app — no DB, no server — and writes `contracts/employment.schema.json`.
- The snapshot is copied to `fenzit-web/contracts/` and `bun run sync:employment-contract` generates `src/features/admin/employmentContract.generated.ts`. The form's max lengths and date controls read the generated rules; the four sections, labels and hints stay FE presentation. `bun run build` runs `check:employment-contract`, so a stale generated file fails the build.
- A test pins that every generated field appears in exactly one section; a compile-time assertion pins the generated field union to `EmploymentView`.

**Verification:** web 1442 tests / 122 files, tsc, eslint, prettier, styles and the full build green; BE 3747 tests / 198 suites and typecheck green. Live visual pass on the QA tenant at 1256px and 360px: all four sections, the dirty count, the discard prompt, the disabled Save with its reason, and the 44px footer.

**Deviations:** the mockup's header close X is dropped — the footer Cancel is pinned and always in view, and a second close path would need its own dirty guard. The statutory section was later renamed "Govt IDs" by the owner (see the follow-up). "Senior Technician" is real QA data, not sample copy; the phrase is also a pre-existing BE fixture value, so it is not a terminology breach.

**Follow-up: floating labels, review fixes and the Govt IDs rename (2026-11-27)**

Sally's second review (29/40) rejected the first floating-label pass: the patch painted a grey tab inside every white field, the focus ring was cut above the label, the label competed with the value, and the joining-date payroll consequence had been removed with the hints. The owner chose to keep the outlined style and fix it rather than revert.

- `TextInput` keeps the floating variant opt-in (15 uses, all in this form; the other call sites stay stacked). The label is still a real `<label htmlFor>`.
- The patch is two surfaces in one box: the panel colour above the border and the input fill below it, with a 1px opaque band over the border itself. The grey tab inside the field is gone; the border is cut cleanly.
- Label: 12px, medium, muted (`#4B5563`, 6.87:1 on the sunken panel), left edge aligned with the field's text. The panel gains one spacing step of top padding for the overhang.
- Focus: the ring runs on the border (`outline-offset: 0`) so it reads as one perimeter interrupted at the notch, not a second ring passing behind the label. An invalid field that also has focus keeps the red ring instead of red-border-plus-blue-ring, and its floating label turns red. The inline error and footer reason use the same sentence, and the disabled Save's `aria-describedby` points at the footer reason.
- Consequences: clearing a joining date that had a value shows "This employee will be left out of salary runs." under the field. The "Unique in the company" line was deliberately not restored (owner call), so a duplicate employee code still surfaces only as the BE's refusal after Save.
- "Statutory IDs" is renamed "Govt IDs" in the tab rail and every section-aware link; the internal key stays `statutory`.
- The variant is documented as a local exception in the component CSS and the form's CSS contract note, not in the generated design-system guide (that lives in `fenzit-app`).
- Verification: web 1444 tests / 122 files, tsc, eslint, prettier and styles green. Live pass on the QA tenant at desktop and 360px: the default Job section fits without body scroll; clearing the joining date adds its one-line warning and the body scrolls; the error, focus and disabled-Save states were checked in the browser.

**Follow-up: Impeccable audit of the employee profile page (2026-11-27)**

Sally ran the Impeccable **audit** playbook over the profile shell, header, five tabs and entry points (Edit Profile internals excluded — audited separately). Verdict: fail on content integrity, pass on system coherence; **14/20** (A11y 3, Performance 4, Theming 4, Responsive 1, Integrity 2), with **1 P0, 3 P1, 7 P2, 4 P3**. The owner approved the full recommendation set; every finding is fixed below.

- **P0 — mobile Attendance clipped.** The shell's `.main` is now `grid-template-columns: minmax(0, 1fr)` with `min-width: 0`, and the attendance `.stack` carries `min-width: 0`. The table scrolls inside its card instead of widening the page. Measured at 360/390/768: `documentElement.scrollWidth === innerWidth`; the only internal scroller is the table wrapper (647px in a 294/324/736px card).
- **P1 — "Joined" was the account-creation date.** The header now reads **"Added 20 Nov 2026"** (`member.createdAt`, honest), and the master record gained **Joining Date** and **Designation** rows from the employment record — no extra fetch, so the "each tab fetches only its own section" contract holds. Read-only dates in the grid (DOB, joining date) render through `fmtDay`.
- **P1 — header clipped at 360.** `.pageHead` is one column by default and two from 560px; actions stack under the identity on phones (measured actions right edge 344px in a 344px box at 360).
- **P1 — no skip link.** The console shell gains a focus-visible **"Skip to content"** link targeting `#console-content`; the shell `<main>` is focusable (`tabIndex={-1}`).
- **P2 — duplicate title entry / invisible designation.** "+ Add Job Title" is removed; **Edit Profile** is the single editor entry, and Designation now shows in the master grid with an honest `+ Add` when empty.
- **P2 — Salary dead end.** **Manage salary** renders in both the empty and filled structure states (secondary in the filled one), deep-linked to this employee.
- **P2 — late promise without a grade.** Attendance rows now flag **"Late N min"** next to the check-in when it crosses the `startTime + lateCutoffMinutes` threshold of **the rule that covered that day** (revision-aware, warning-toned text, not colour alone), so the Work Timings card's promise is applied by the history. The card's meta is also reworded to "The rules this employee's attendance is measured against." — it no longer promises a full-day/half-day grade the table does not show.
- **P2 — four date formats / tab naming.** Read-only dates use one format; the first tab is renamed **"Profile"** (it holds PAN/PF/UAN/bank), while the card stays "Employee Details".
- **P2 — touch targets.** Tabs, month links, master `+ Add` and the reporting "Change" control are ≥44px (`var(--touch-min)`); `Button` gained an optional `className` for the local hit-area rule.
- **P2 — phone nav strip.** The sidebar nav wraps on phones instead of hiding later links in a horizontal scroll (reset to `nowrap` at ≥960px).
- **P3 — polish.** Jobs chips use **"In Progress" / "Done"**; each tab has a visually hidden H2 so the outline is H1 → H2 → H3; the browser title is `"<name> · <tab> · Fenzit"` via a new `useDocumentTitle` hook with cleanup; the Table empty state is no longer italic; annual leave reads "N days added every year."; month chevrons are `aria-hidden`.
- **P3 — table semantics.** `DataTable`'s first cell is a `<th scope="row">` (rebased on `.td`), so each row is named by its own key.
- **Verification:** web 1448 tests / 122 files, tsc, eslint, prettier, styles green. Live QA tenant at 768/400/390/360 (same-origin fixed-width frames): page `scrollWidth === innerWidth` on every tab checked; header stacks below 560 with actions inside the gutter; nav wraps with no horizontal overflow; tabs and month links 44px; skip link present; title reads "Vijay Menon · Attendance · Fenzit"; the 09:40 check-in against 09:00 + 15 shows "Late 25 min".

**Follow-up: console chrome, Help & Support, and the second Impeccable audit (2026-11-27)**

The owner asked for the two Stitch sidebar states and a Help page, then for the audit's second round to be applied. What shipped:

- **Two rail states.** The shell remembers 280px expanded or 72px collapsed under `fenzit.console.sidebar`; the labels stay in the accessibility tree (clipped, with `title`), and the `pageRail` class reclaims the width on every console page. Below 960px the rail is untouched — the phone bar is the same 69px whichever state was saved.
- **Phone nav behind one labelled Menu control.** The ten-section strip no longer wraps over every page: a 44px `aria-expanded` toggle opens a stacked panel (cluster captions, 46px rows, the user chip and Log Out inside). Escape closes it from anywhere in the shell and returns focus to the toggle; any navigation — including a query-only tab or month change — closes it, keyed on `location.key`, because closing in the anchor's click handler detached it before the browser followed the link.
- **Settings while the screen does not exist.** The row is a `role="link"` with `aria-disabled`, a visible "Coming soon" note (hidden in the icon rail), and `tabIndex={0}` so keyboard users can reach the reason they are being refused.
- **Help & Support page** (`/admin/help`, all three roles, grouped under Preferences): two contact cards, six FAQs in the product's own vocabulary, and a closing block that says what to include rather than repeating the contact cards. The topic count derives from the list; the salary question points at **Manage salary** (the Salary tab is read-only); the contact cards carry a visually hidden H2 so heading navigation reaches the page's primary action.
- **Profile tab follows the crop.** Four groups of tiles with icon labels and coloured caption dots, statutory values at 14px/600 against 12px labels, a copy control on each of the five identifiers (with a selection-copy fallback), and **Copy identifiers** in the card header — one toast that replaces the previous one rather than stacking.
- **Collapsed active state.** The rolled-up rail marks the current section with the expanded rail's tinted 40×40 square instead of the design's corner dot, which collided with the leave badge; the leave count keeps its numeral on the icon corner. A deliberate deviation from the Stitch screen.
- **Salary card.** Manage salary sits in the card header in both the empty and filled states; clearing a joining date warns only when there was one; the load-failure lines say to reload instead of pointing at a menu that does not exist; the date density rule follows the pointer, not just the viewport.
- **Verification:** web 1469 tests / 123 files, tsc, eslint (0 errors), prettier, CSS-module pairing and the full build green. Live QA tenant at 360/390/768/959/960/1280: 69px phone bar, no horizontal scroll, the rail threshold at 960, the Settings note in both states, 44px copy controls on touch, and one toast per copy.

## Code Review

### 2026-11-27 (second review — console chrome, Help, profile tiles)

**Code review complete.** 0 `decision-needed`, 21 `patch` (13 code, 8 tests; all applied), 1 `defer`, 30 rejected. Four thorough lenses (blind-hunter, edge-case-hunter, verification-gap, intent-alignment) over the uncommitted web set (45 files, +2831/−308, HEAD→worktree).

- [x] [Review][Patch] The phone menu closes on any navigation, query-only changes included — the effect keyed on `location.pathname`, so a tab or month link left the panel open over the page it opened [src/pages/AdminPage.tsx]
- [x] [Review][Patch] Escape closes the phone menu from anywhere in the shell — the handler sat on `<aside>`, so focus in the content region could not close it [src/pages/AdminPage.tsx]
- [x] [Review][Patch] The disabled Settings row is reachable by keyboard — `role="link"` on a span is not focusable without `tabIndex`, so the "Coming soon" reason was unreachable [src/pages/AdminPage.tsx]
- [x] [Review][Patch] The salary FAQ points at Manage salary — the answer told the reader to add components on the read-only Salary tab [src/pages/AdminHelpPage.tsx]
- [x] [Review][Patch] The contact cards carry a heading — heading navigation skipped the page's primary action [src/pages/AdminHelpPage.tsx + .module.css]
- [x] [Review][Patch] The topic count pluralises ("1 topic") [src/pages/AdminHelpPage.tsx]
- [x] [Review][Patch] A copy is announced once — the tile's `aria-label` flipped to "<field> copied" while the toast said the same, so screen readers heard it twice; the tile keeps its name and the toast speaks [src/features/admin/components/employee/MasterRecordPanel.tsx]
- [x] [Review][Patch] "Copy identifiers" names what the control copies — "Copy all details" copied only the five identifiers, and the toast said "Employee details copied." [MasterRecordPanel.tsx]
- [x] [Review][Patch] The selection-copy fallback removes its temporary field when `execCommand` throws — the cleanup was not in a `finally` [MasterRecordPanel.tsx]
- [x] [Review][Patch] A punch taken at another office is not graded with the assigned office's late rule — only that office's revisions are in hand, so a transferred employee's older punches would have borrowed a rule that never applied [src/features/admin/components/employee/ProfileAttendancePanel.tsx]
- [x] [Review][Patch] A line with no usable amount no longer reads "— per month" [ProfilePayrollPanel.tsx]
- [x] [Review][Patch] The salary card's date density follows the pointer, like every other dense control — it densified on viewport width alone [ProfilePayrollPanel.module.css]
- [x] [Review][Patch] `/admin/help` joins the client-only title map [src/app/pageMeta.ts]
- [x] [Review][Patch] Tuple of tests for the gaps the lenses proved: the `/admin/help` route inside the shell (one h1, no greeting); every catalogue field rendering in the grouped grid; a null joining date staying quiet; the rail mounting from remembered storage; the menu closing on a navigation; no total from a partially uncomputable structure; the selection-copy success path; the document title restored on leaving the record [src/pages/AdminPage.test.tsx, AdminEmployeeProfilePage.test.tsx, AdminEmployeesPage.employment.test.tsx]
- [x] [Review][Defer] The client's "Late N min" duplicates the backend's late math (`ProfileAttendancePanel.tsx` `lateBy` vs `computeLateMinutes`) — deferred: the punch wire carries no `lateMinutes`, so removing the copy needs a BE wire change; both sides use the tenant-local clock and the rule covering the day today. Owner: next time the punches payload or the day-status engine is touched, send `lateMinutes`/`isLate` and delete the FE copy.

**Rejected (30):**

- `false` — "Salary tab / Payroll tab" naming drift: user-visible copy is consistent ("Salary" is the tab, the section and the FAQ's word); "Payroll" is the sidebar group caption and the standalone page.
- `false` — `ruleOn` returning the last covering revision: `toOfficeDetailResponse` sorts by `validFrom` before mapping, the documented "last = current" contract.
- `false` — non-IST offsets misgrading: `toTenantOffsetIso` writes the tenant offset, so the clock digits are tenant-local; the rule's `startTime` is tenant-local too.
- `false` — overnight shifts misgrading: the office DTO requires end after start, same day, so no overnight rule exists.
- `false` — "Added" showing `createdAt` while `joinDate` is on the page: the prior audit's deliberate P1 fix, recorded above.
- `false` — clearing a code blocks Save but clearing a joining date only warns: the code is required by the BE, the date is optional.
- `false` — the two deleted EmploymentForm hints: the uniqueness line was dropped by owner call (recorded above); the payroll consequence now appears when the destructive edit is made.
- `false` — Log Out behind the Menu on phones: the panel contains the chip and Log Out by design; the closed bar deliberately carries no second log-out.
- `false` — copy-all omitting non-identifier fields: the control's set is the five identifiers by design; its name and toast now say so.
- `false` — three "active" signals: the avatar dot is conditional and decorative, the badge is the status, and the rail chip belongs to a different surface.
- `false` — "Excludes mandatory employer PF and gratuity": structure lines are earning components; employer PF/gratuity are outside them.
- `false` — annual figure rounding / `fmtMoney(String(number))`: the monthly total is 2dp-rounded before ×12 and the formatter rounds to 2dp, so no visible drift.
- `false` — empty-string `amount` counted as zero: the wire sends 2dp text or null; `""` is not a shape the API produces.
- `false` — the `DataTable empty` prop on Payslips: `empty` is required by the shared table contract; the branch above owns the message.
- `false` — `white-space: nowrap` on Button: the cited "Confirm Deactivation" is a plain `.confirmDanger` button outside `Button`, and no Button label in the repo overflows its container.
- `false` — `ReportingBlock` `flex-wrap: nowrap` clipping Change: `.facts` has `min-width: 0` and `.value` `overflow-wrap: anywhere`, so the name wraps and the control stays; no horizontal scroll at 360.
- `false` — floating label with a prefix: no call site combines `variant="floating"` with `prefix`.
- `false` — clipboard stubs not restored in tests: each copy test sets its own stub and no later test in the file copies.
- `false` — `useDocumentTitle` vs the layout `<title>`: the hook runs after render on purpose (the record's own name wins), and its restore path is now pinned.
- `low` — module-level `copyToastId` and the per-tile timer with no unmount cleanup: no user-visible effect; a cleanup effect is more machinery than the risk.
- `low` — Help CSS repeating the profile page's crumb/title styles: developer duplication only; extracting a shared crumb is a separate refactor.
- `low` — "/admin labels as Console for members": the console's index is theirs too; the crumb word matches the sidebar.
- `low` — blank names handled four ways: the contexts differ (h1, crumb, title, chip) and a whitespace-only name is not a reachable input.
- `low` — chips say "Done" while the row badge says "Completed": the chip wording was the prior audit's P3; the row badge carries the precise status.
- `low` — group captions ("Tax identifiers" holding PF/UAN): the owner's crop supplies those captions; renaming them is a design call.
- `low` — `ReportsValue` parsing " (Owner)" off the string: styling only; a copy change would drop the quiet mark, not data.
- `low` — `<details open={index === 0}>` mixed with the browser toggle: the prop never changes across re-renders, so a reader's collapse sticks; no default-open prop exists in React.
- `low` — the Help entry living in six maps: `sectionsFor` is pinned per role and `sectionGroupsFor` for the owner; a missing glyph or blurb falls back rather than breaks.
- `low` — the phone menu as a disclosure without scroll lock / click-outside: it closes on Escape, the toggle and any navigation; a modal treatment would misstate what it is.
- `low` — sales number under "Call us" and the one-working-day promise: the contact config carries one line and the copy comes from the approved screen; a support-line decision is the owner's.
