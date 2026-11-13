# Reports dashboard catalogue

Companion to `SPEC.md` (CAP-8, CAP-9). Lists the insight each dashboard must show. On the web admin console, the dashboard is the landing view after login: the owner gets the owner dashboard, and an employee gets the employee dashboard. Every number is computed from job and employee records for the chosen date range; none is stored as a counter.

Filters on both dashboards: date range (today, 7 days, 30 days, this month, last month, custom), and for the owner: employee, job type or source.

## Owner (company-wide, web)

**Headline counts** (the four required, first row)
- Jobs created by employees
- Employee-created jobs approved by owner
- Employee-created jobs auto-approved (approval off)
- Jobs created by owner

**Approval queue** (filters: employee, age of submission; these combine)
- Pending jobs with submitter, submitted time, age, and any owner edits made so far

**Approval pipeline**
- Pending now, and pending older than 24 hours
- Rejected, with and without reason
- Approval rate = approved / (approved + rejected), for jobs that needed approval
- Average and median time from submission to decision
- Oldest pending job

**Per-employee breakdown** (table, sortable)
- Created, approved, auto-approved, rejected, pending
- Share of company's employee-created jobs
- Employees with permission on but no jobs created in the range

**Trends** (line or bar by day or week)
- Jobs created per day, split by creator type (owner, employee-auto, employee-approved)
- Approval decisions per day

**Mix**
- Share of jobs created by owner vs employees
- Share of employee jobs that needed approval vs auto-approved

## Employee (own numbers, web and mobile summary)

- Jobs I created: total, approved, auto-approved, rejected, pending
- My approval rate and average wait for a decision
- My jobs that are assigned now and that are completed in the range
- Rejection reasons I received, with the most recent first
- My full rejected-job history, all time (no expiry)

## Data notes

- Counts use the approval state from `job-approval-states.md`. Owner-created jobs count only toward the owner's total.
- Time-to-decision needs a submission timestamp and a decision timestamp on each pending job. These are new fields and need a backend migration.
- Per-employee breakdown and trend data are company-scoped server queries; clients do not aggregate raw job lists.
- Reports use the same definitions on web and mobile. Mobile shows a summary for the owner (headline counts and pending) and for the employee (own numbers); the full owner dashboard with breakdowns and trends is web only.
