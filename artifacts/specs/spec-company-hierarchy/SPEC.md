---
id: SPEC-company-hierarchy
companions: [approval-routing.md]
sources: []
---

> **Canonical contract.** This SPEC, the files in `companions:`, `stories.yaml` and `.decision-log.md` are the complete contract for what to build, test, and validate. Decisions taken during planning and review are recorded in `.decision-log.md`.

# Company reporting hierarchy with manager approvals

## Why

Today every company is flat: the owner sees and approves everything, and each employee sees only their own work. As a company grows, a supervisor must be able to see and act on their own people's requests — leave and jobs — without being given owner powers and without seeing other branches. The industry baseline (Zoho People, Keka, greytHR, BambooHR, Connecteam, Deputy) is one "reporting manager" pointer per person that drives both visibility and approval, with the owner as fallback and override. This SPEC adds that tree. The Phase-1 architecture named a future "supervisor" role for exactly this need.

## Terms

- **Reporting manager** (UI copy: "Reports to") is the member a person reports to. Stored as `memberships.manager_id`, pointing at the manager's **user** (composite with tenant). Any active member may **serve as** someone's reporting manager — including an admin, whose direct reports form L2 — but an admin cannot be **assigned** a reporting manager themself (D13).
- **Admin (owner)** is an active `company_admin` membership. Admins sit at the top of the tree: they **cannot be assigned a reporting manager**, and an admin's own request is decided by the admin themself (D11). When several admins are active, they together form the **fallback set** (D12). Admins other than someone's direct manager keep their existing powers but are not in the routing chain.
- **Reporting tree** is the per-company structure rooted at the admins. Levels (L1, L2, L3…) are depth in the tree — admins are L1, their direct reports are L2, and so on. Levels are **derived, never stored, and never shown in UI**.
- **Subtree** of a manager is the manager plus everyone below them, direct and indirect.
- **Resolved approver** is computed at action time from the requester's current position in the tree (algorithm in `approval-routing.md`). It is never stored on the request.
- **Fallback set** is all active admins. It becomes the resolved approver set when the walk must step **up from** an unassigned member — the requester unassigned at the walk's start, or an excluded (requester/actor) unassigned member on an on-behalf walk. An active unassigned member reached as an eligible candidate is instead the **single resolved approver**. No single admin is picked arbitrarily; today's behaviour is preserved until real managers are assigned (D12).
- **Unassigned manager** is `manager_id = null`. Routing treats an unassigned member as reporting to the fallback set; behaviour is identical to today until managers are assigned.
- **Manager** is a **capability derived from the tree** (you hold it if anyone reports to you), not a new role value. A member with no reports has no manager powers. Subtree rights are **additive** to the member's role rights (D13).

## Capabilities

- **CAP-1**
  - **intent:** The owner can set or change each non-admin member's reporting manager — at invite time or later — on web and mobile. The database enforces what DDL can: the composite foreign key (same company) and a not-self CHECK. The app transaction enforces the rest and refuses: a target who is not an active same-company member, an **admin** (admins are the top of the tree), an assignment that would create a cycle, and anything beyond the depth cap of 20 — the cycle check and the write run in one transaction with the affected member rows locked for update in a consistent order, so two concurrent reassignments cannot each pass their check and jointly create a loop. Any active member may serve as the reporting manager; only a non-admin can be assigned one (D13); the UI warns when assigning a viewer. When a member is removed, their whole subtree re-parents to the removed member's manager; if the removed member was unassigned, their reports become unassigned too (the fallback set covers routing). A removal that would leave the company with no active admin is refused. Audit: one row per changed membership — including every re-parented member — with the acting admin as actor.
  - **success:** The assignment saves and shows on the member's record as a full upward chain ("Reports to Priya → Arjun (Owner)") plus the headcount below them. An invalid assignment — including assigning a manager to an admin — is refused with a plain-English reason. A removal re-parents the subtree, nothing is left pointing at the removed member, and each re-parented member has its own audit row.
- **CAP-2**
  - **intent:** A manager sees, in addition to their own data, the leave requests and jobs of everyone in their subtree — lists, details, and attachments (the subtree check precedes signing or serving any attachment). Subtree rights are additive to the member's role rights (D13). Nobody sees above or across their own branch: not another manager's team, not their manager's other branches. Admins see the whole company. A member without reports — employee, viewer or admin — sees exactly what they see today (a viewer **assigned** as a manager is the deliberate D13 exception).
  - **success:** A manager's list and detail reads return their subtree's requests; a request from another branch returns not found (no existence leak). A member without reports gets an unchanged response. Attachment reads outside the subtree are refused the same way. The scoping lives in the backend; the client submits intent only.
- **CAP-3**
  - **intent:** Approval follows the tree. The resolved approver of a leave request or a pending job is computed by the walk in `approval-routing.md` at the moment of action; when the walk falls back, the resolved approver set is all active admins (D12). An admin's own submission stays pending in their own queue and is decided by the admin themself (D11). A manager filing a **leave** request on behalf of a team member creates a normal request routed up — the actor never decides their own filing (D14; on-behalf applies to leave in this epic). Any active admin can approve or reject any request in the company (override). Subtree visibility is not decision right: a manager may decide only requests whose resolved approver set contains them; a higher manager sees lower-branch requests read-only, actions disabled with a plain-English reason. Nothing is ever auto-approved. Approve, reject and revoke stay atomic and idempotent: exactly one decision wins a race, the other gets a conflict. The walk and the decision write happen in one transaction under the same advisory locks, so a concurrent reassignment cannot split them.
  - **success:** A manager approves and rejects the requests routed to them from their subtree, from their own queue. A manager requesting their own leave finds it routed to their manager, or to the fallback set. The admin's own submission is decided by the admin (D11). After a mid-flight reassignment, the pending request appears in the new manager's queue and disappears from the old one's — responsibility is recomputed at action time, nothing migrates.
- **CAP-4**
  - **intent:** Notifications follow the routing. A submission event (leave applied, job submitted) notifies the resolved approver set — one specific approver when the walk resolves one, all active admins when it falls back (D12). The actor never receives a notification for their own filing: with D14 a manager's on-behalf filing routes up, and an owner's self-filed request notifies no one. Decision notifications go to the requester as today. Tree-change transactions that affect pending requests emit, **per affected pending request, to the set difference**: "now awaiting your approval" only to members newly in the resolved set, and "no longer yours to approve" only to members that left it (skipping members no longer active). Admin activation/deactivation counts as a tree change for fallback-routed requests. Admins outside the resolved set are no longer notified of individual submissions; they keep full list visibility and approval powers.
  - **success:** Each recipient in the resolved set gets exactly one push and one inbox entry per submission — and an active admin **outside** the resolved set receives no submission push and no inbox entry, for leave and jobs alike (this negative assertion is the acceptance evidence for D7). A reassignment emits the notices per affected request: newly-resolved members get "now awaiting your approval", members that left the set get "no longer yours to approve". The requester's decision notifications are unchanged from today.
- **CAP-5**
  - **intent:** In fenzit-app, a manager gets a "Your team" experience: a pending leave queue and a pending-jobs queue for their subtree, with approve/reject available only where the member is in the resolved approver set (higher managers see lower-branch requests read-only, the action disabled with a plain-English reason); apply-on-behalf for their subtree members' **leave**, with the filing routed up per D14; a "Reports to" picker at invite time and on the member's settings sheet; and the upward chain and headcount shown on the member's record. Someone with no reports sees no new UI.
  - **success:** A manager works their queues end to end in the app, and can apply on behalf of a team member (the filing then awaits the nearest eligible manager above the subject). On a leave detail the manager can see who else on the team is already off on those days. A member without reports has no team section, no disabled states to explain. Copy is plain business English ("Your team", "Reports to", "Reporting manager").
- **CAP-6**
  - **intent:** In fenzit-web, the owner sees and edits each member's reporting manager — a column on the members table and the field in the member settings dialog — and the invite dialog gains the field. Editing shows what will change before it saves ("Priya's 3 direct reports will now report to you"); assigning a viewer carries the D13 warning; assigning a manager to an admin is refused. Web approval surfaces for managers are out of scope in this epic; web keeps owner-only approvals.
  - **success:** The owner assigns and reassigns reporting managers on web with an explicit confirmation of re-parenting effects. The invite flow accepts a manager. A manager signing in to web lands on their existing surfaces (no owner console).

## Constraints

- **Zero stored-procedure calls.** No new DB functions, and hierarchy code paths call no existing RPC — advisory locks are taken inline (`pg_advisory_xact_lock`), audit rows are direct inserts in the same transaction, and the migration is DDL only (columns, constraints, index). (`write_audit_row` is deliberately bypassed; reproduce its column contract faithfully once and copy that snippet.)
- Subtree scoping lives in the NestJS service layer over the pg pool. The permission guard gains a **scope dimension** (role × subtree); `permissions.ts` remains the single source of what each role holds. Manager is never a new role value. The guard's scope check and the service's subtree scoping derive from the **same helper** (story 2's recursive-CTE helper), so the two layers cannot drift.
- Existing conventions hold: composite FKs `(col, tenant_id) → users(id, tenant_id)`; cross-company ids answer not found, never 403; PT-style SQLSTATE errors with hints; one audit row per write; AD-5 advisory-lock keys; `memberships_one_live_per_user` untouched.
- The backend owns routing, visibility and notification triggers. Clients display and submit intent only.
- **Decision-26 exception, on the record:** subtree leave visibility for managers is a deliberate second exception to "non-admins read only their own leave" (roles-and-access spec). Managers see the leave reasons of their own people; no one else's.
- **Epic-22 contract revision, on the record:** job decisions move from the `decide_pending_job` RPC to a NestJS transaction with the same endpoint contract; the RPC is retired in a later, separate change once no live deployment depends on it (see stories). The revision also covers epic-22 CAP-7 (job visibility now includes the subtree manager) and the approver identity in CAP-4/CAP-5 (the resolved approver decides, not "the owner") — see D6.
- User-facing copy says "Reports to" / "Reporting manager" / "Your team"; never L1/L2/L3; "Employee" not "Technician"; existing API field names are not renamed (`manager_id` is new).
- Deploy order: `fenzit-be` first (additive; the D7 notification narrowing rides this deploy and needs no client change), then `fenzit-app` and `fenzit-web` in either order.

## Non-goals

- Delegation or substitute approvers when a manager is on leave.
- Escalation timers or auto-approval on timeout (remind-first only, as today).
- Comp-off flows riding the same approval rails.
- Multiple managers per person, departments/teams as structures, historical org charts, hierarchy-based attendance rules.
- Web approval surfaces for managers (app-only in this epic).
- Managers creating jobs for their people (future story; would also be RPC-free).
- Apply-on-behalf for **jobs** — it rides with that future story; in this epic on-behalf applies to leave only.
- Manager edits to pending jobs — in this epic, pending-job editing stays owner-only (epic-22 CAP-5), while the decision right follows the tree.
- Changes to attendance access states (the `attendance_access_state` view and AD-17 are untouched).
- Email notifications.

## Success signal

An owner sets Priya as the reporting manager of three employees. One of them requests leave; Priya gets exactly one notification, sees the request in her team queue with the dates and who else is already off, and approves it. The employee gets the decision notification. A manager of another branch sees nothing of it. Priya herself requests leave, and it routes to the owner. The owner then requests leave themself, and decides it from their own queue (D11). The audit log shows Priya as the actor of her decisions and the owner as the actor of the reassignments.

## Assumptions

- One live membership per user per company; `manager_id` points at a user, so identity survives membership edits.
- The migration leaves existing `manager_id` values null — every company behaves exactly as today until its owner assigns managers (the fallback set covers routing meanwhile, D12).
- `can_create_jobs` / `job_approval_required` semantics are unchanged.
- Levels (L1/L2…) may appear in planning docs and code comments, never in UI copy.

## Open Questions

None. Resolved decisions are recorded in `.decision-log.md`.
