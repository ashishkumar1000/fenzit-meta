# Epic 24 Context: Company reporting hierarchy with manager approvals

<!-- Compiled from planning artifacts. Edit freely. Regenerate with compile-epic-context if planning docs change. -->
<!-- Source gap: this epic has no epics-*.md in artifacts/planning-artifacts. Compiled from artifacts/specs/spec-company-hierarchy/ (SPEC.md, approval-routing.md, stories.yaml, .decision-log.md) plus sprint-status.yaml. -->

## Goal

Give each company a reporting tree so a supervisor can see and approve their own people's leave and jobs without owner powers or visibility into other branches. Today every company is flat: the owner sees and approves everything, and an employee sees only their own work. The tree is one "Reports to" pointer per member, rooted at the admins, driving visibility, approval routing and notifications. The industry baseline (Zoho, Keka, greytHR, BambooHR, Deputy) uses exactly this shape, with the owner as fallback and override.

## Stories

- Story 24-1: Hierarchy data model and manager assignment (BE)
- Story 24-2: Subtree scoping and the permission scope dimension (BE)
- Story 24-3: Leave approval routing and notifications (BE)
- Story 24-4: Job approval without RPC (BE)
- Story 24-5: Manager surfaces in fenzit-app
- Story 24-6: Web manager column and editing (fenzit-web)
- Story 24-7: Retire the decide_pending_job RPC (BE, gated)

## Requirements & Constraints

- An owner can set/change any non-admin member's "Reports to" at invite or later, on web and mobile; an admin can never be assigned a manager. Any active member may serve as a manager; subtree rights are additive to role rights.
- Invalid assignments are refused with plain English: inactive target, admin target, cycle, or depth beyond 20. Cycle check and write run in one transaction with affected member rows locked in a consistent order, so concurrent reassignments cannot jointly create a loop.
- Removing a member re-parents their whole subtree to that member's manager (unassigned when the removed member was unassigned), with one audit row per changed membership; a removal that would leave no active admin is refused.
- Managers see the leave requests and jobs of their whole subtree — lists, details, attachments — and nothing above or across their branch; other branches answer not found, never 403. Members without reports see exactly what they see today.
- Approval follows the tree: the resolved approver is computed at action time (never stored), with all active admins as the fallback set when the walk steps up from an unassigned member, and any active admin as override. A member never decides their own filing; an admin's own request is self-decided, never auto-approved.
- Notifications follow routing: submissions and admin-named reminders go to the resolved approver set, not all admins; tree changes emit per-pending-request set-difference notices ("now awaiting your approval" / "no longer yours to approve").
- Copy: "Reports to", "Reporting manager", "Your team". Never L1/L2/L3 in UI; "Employee", never "Technician". Existing API field names are not renamed; `manager_id` is new.
- Deploy order: fenzit-be first (additive), then fenzit-app and fenzit-web in either order.

## Technical Decisions

- Zero stored procedures in this epic: no new DB function and no call to an existing RPC on hierarchy paths. The migration is DDL only; advisory locks are inline (`pg_advisory_xact_lock`); audit rows are direct inserts reproducing `write_audit_row`'s column contract once.
- `memberships.manager_id` is a composite FK to `users(id, tenant_id)`, with a not-self CHECK and an index on `(tenant_id, manager_id)`. DDL enforces only what it can; active-membership, admin-target, cycle and depth checks live in the transaction.
- Manager is a tree-derived capability, never a role value. The permission guard gains a role × subtree scope dimension; `permissions.ts` stays the single source of what each role holds. Guard and service derive subtree scope from the same recursive-CTE helper so they cannot drift.
- Reads run with the service-role client, so subtree scoping is the NestJS service layer's job (memberships is service-only under deny-all RLS).
- The resolved approver walk: admins first (self-decide, no notification), then climb from the requester's manager skipping inactive/removed/requester/actor, fallback set when stepping up from an unassigned member, depth-capped with a visited set, refusal when unresolvable. Walk and decision write share one transaction and the existing AD-5 advisory locks.
- Job decisions move from the `decide_pending_job` PL/pgSQL function to a NestJS transaction with the same endpoint contract and the same PT400/PT403/PT404/PT409 semantics; the RPC is retired in a later, gated migration only after both frontends are released.
- Submission audit events snapshot the resolved approver set at submission time; routing itself stays derived at action time.
- Every write keeps one audit row per changed membership; existing conventions hold: composite FKs, cross-company ids = not found, PT-style SQLSTATE errors, `memberships_one_live_per_user` untouched.

## UX & Interaction Patterns

- App managers get a "Your team" surface: pending leave and pending-jobs queues, approve/reject only where they are in the resolved set; higher managers see lower-branch requests read-only with a plain-English reason. Apply-on-behalf for subtree leave, routed up. Upward chain ("Reports to Priya → Arjun (Owner)") and subtree headcount on the member record.
- Someone with no reports sees no new UI and no disabled states to explain.
- Web owner surface: Reports-to column on the members table, field in member settings and invite dialogs, explicit re-parenting confirmation ("Priya's 3 direct reports will now report to you"), viewer-assignment warning. Web manager approvals are out of scope.

## Cross-Story Dependencies

- Backend stories 24-1 → 24-2 → 24-3/24-4 must ship before both frontends (delivery order rule).
- 24-5 and 24-6 both depend on the member payload from 24-1 and the routing semantics from 24-3/24-4.
- 24-7 is gated on story 24-4 being live in both frontend releases; separate migration, separate change.
- The epic revises the epic-22 contract on record: job visibility includes the subtree manager, and the resolved approver — not "the owner" — decides. `job-approval-states.md` is superseded by this epic's diagram.
