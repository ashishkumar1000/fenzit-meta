---
id: SPEC-employee-created-jobs
companions: [job-approval-states.md, reports-dashboard.md]
sources: []
---

> **Canonical contract.** This SPEC and the files in `companions:` are the complete, preservation-validated contract for what to build, test, and validate.

# Employee-created jobs with owner approval

## Why

Today only the owner creates jobs and assigns them to employees. Employees who visit customers often know the work before the owner does, and the owner has to re-enter it. Owners want employees to log their own jobs, but keep control: each employee gets two owner-set switches, one for permission to create jobs and one for whether the owner must approve those jobs first. Owners also need to see how jobs are created and approved, so the reports must show who creates work and how much goes through approval.

## Terms

- **Job** is the existing record (the app's "task"). Employee-created jobs use the same record and the same fields.
- **Creator** is the user who created the job. For owner-created jobs the creator is the owner.
- **Employee** is the membership role `employee` (`memberships.role`). It is the user-facing word too. The old `technician` value is retired.

## Capabilities

- **CAP-1**
  - **intent:** The owner can set, for each employee, whether the employee may create their own jobs, and whether those jobs need owner approval. Both settings are per employee and are changed on web and mobile.
  - **success:** Toggles save and show the current value on the employee's record. A change applies to the next job the employee creates and does not change jobs already pending.
- **CAP-2**
  - **intent:** An employee with permission to create jobs can create a job for an existing customer, or create a new customer and a job in one flow, on web and mobile.
  - **success:** The job record stores the employee as creator. An employee without permission cannot create a job. The screen hides the action and the API refuses with a plain-English reason.
- **CAP-3**
  - **intent:** If the employee's approval setting is off, the new job is assigned to the employee at once and appears on their dashboard.
  - **success:** The job is assigned, visible to the creator and the owner, and counted as auto-approved in reports. No owner notification is sent.
- **CAP-4**
  - **intent:** If the employee's approval setting is on, the new job is saved as pending owner approval. It is not counted as assigned and does not appear as active work. The employee sees it on their dashboard under Pending owner approval, and the owner gets a push notification and an inbox entry.
  - **success:** A pending job is absent from the employee's assigned-work list and from the technician's schedule. The owner's approval queue lists it. The owner receives exactly one push and one inbox entry per submission.
- **CAP-5**
  - **intent:** On web and mobile, the owner can edit any field the creator could set on a pending job, then approve it, or deny it with or without a reason. Approval assigns the job to the creator. Denial (reject) leaves it unassigned and marks it Rejected. Owner edits are recorded in an audit trail with who changed what and when.
  - **success:** Approve moves the job to assigned and the creator sees it on the dashboard with the owner's edits applied. Reject shows Rejected, with the reason if one was given. An owner edit to a job that is no longer pending is refused. A second decision on the same job returns a conflict and sends no second notification. The audit trail lists each edit with the changed fields.
- **CAP-6**
  - **intent:** The creator gets a push notification and an inbox entry when the owner approves, rejects, or edits their pending job. The creator can see every owner edit on the job: each changed field with its before and after value, who changed it, and when. Both the owner and the employee can open an inbox list showing their notifications, and mark them read.
  - **success:** Each approve or reject produces one push and one inbox entry for the creator. Each owner edit save produces one push and one inbox entry, and one edit save never produces more than one. The job shows the edit history to the creator while pending and after decision. Inbox items show unread state and open the job.
- **CAP-7**
  - **intent:** Visibility: an employee-created job is visible only to its creator and to the owner. Other employees of the same company do not see it. No user outside the company sees it. The creator can see their own rejected jobs in their history with no expiry.
  - **success:** Another employee's list and detail request for the job returns not found. A user from another company gets the same response. A rejected job stays in the creator's history after any length of time.
- **CAP-8**
  - **intent:** Owner and employee each get a reports dashboard on the web admin console. It is the landing view a user sees after logging in. The owner sees company-wide numbers, including how many jobs employees created, how many were approved, how many were auto-approved, and how many the owner created. The employee sees their own numbers.
  - **success:** After login, each user lands on their dashboard. The four headline counts match a direct count of job records for the same period and scope. The owner dashboard shows a per-employee breakdown; the employee dashboard does not show other employees. Catalogue in `reports-dashboard.md`.
- **CAP-9**
  - **intent:** Employee and owner dashboards on mobile show the pending, assigned and rejected counts for their own scope, with a link to each list.
  - **success:** Counts on mobile match the web dashboard for the same user and date.
- **CAP-10**
  - **intent:** On web and mobile, the owner's approval queue can be filtered by employee and by age of submission (for example, older than 24 hours).
  - **success:** Filtering by one employee shows only that employee's pending jobs. An age filter shows only jobs submitted before the cut-off. Filters combine.

## Constraints

- The backend owns approval rules, state transitions, visibility and notification triggers. Clients display and submit intent only; they never decide approval or visibility.
- Approve and reject are atomic and idempotent per job. Exactly one decision wins a race; the other receives a conflict.
- Every read and write is scoped to the job's company. Cross-company access is denied, not filtered silently.
- Pending jobs are excluded from assigned-work lists, schedules, and any count labelled assigned or active.
- User-facing copy says Employee. The membership role is `employee`. Existing API field names are not renamed.
- Owner means the `company_admin` membership role. The platform super admin flag grants no owner job actions.
- Deploy order: `fenzit-be` first (additive: new states, fields, endpoints, notification types, and reports endpoints). Then `fenzit-app` and `fenzit-web`, which may ship in either order. Old clients must not break on the new states.
- Owners and employees use the same web sign-in. The membership role decides the landing view: `company_admin` gets the owner dashboard, `employee` gets the employee dashboard. An employee session shows only that employee's dashboard, jobs and history (CAP-7, CAP-8).
- Settings changes apply to new jobs only.
- Reports are computed from the job records, not from a separate counter that can drift.

## Non-goals

- Employees assigning jobs to other employees.
- Employees editing a job after submission. Only the owner edits a pending job.
- Multi-step or multi-approver approval chains.
- Changes to the existing owner-created job flow, except tagging the creator.
- Payments, invoicing, or pricing on employee-created jobs.
- Email notifications.
- Exporting reports to PDF or Excel. The dashboard is on screen only in this epic.

## Success signal

An employee with approval on creates a job for a new customer on mobile. The owner gets a push and an inbox entry, and the job sits in the owner's queue and not in the employee's active work. The owner approves it. The employee gets a push and an inbox entry, and the job appears in their assigned work. The owner's report shows the job under employee-created and approved, and the employee's report shows the same job.

## Assumptions

- Owner-created jobs are tagged creator = owner for reporting; no approval step applies to them.
- Settings changes apply to new jobs only; jobs already pending keep their state.
- Owner edits to a pending job are audited. Each owner edit save notifies the creator (push and inbox), and the creator sees the edit history on the job.

## Open Questions

None.
