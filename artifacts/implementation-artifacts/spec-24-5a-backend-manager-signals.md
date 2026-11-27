---
title: 'Manager signals on the BE contract — team on /users/me, decision on every row'
type: 'feature'
status: 'done'
created: '2026-11-27'
baseline_commit: 'df3add6'
context:
  - 'artifacts/specs/spec-company-hierarchy/SPEC.md'
  - 'artifacts/specs/spec-company-hierarchy/approval-routing.md'
  - 'artifacts/implementation-artifacts/epic-24-context.md'
---

# Manager signals: the two questions 24-5 could not ask

## Why this exists

Story 24-5 (mobile manager surfaces) needs two answers from the server before it
can render anything, and stories 24-1…24-4 did not expose either one.

1. **"Do I have a team?"** A manager is an `employee` or `viewer` membership —
   manager is never a role value (D13). `GET /users/me` carried no hierarchy, and
   `GET /members` is `@Can('member.read')`, which employees and viewers do not
   hold. CAP-5 says "someone with no reports sees no new UI", so the client needs
   a server-endorsed gate; inferring it from a 403 on the team queue is neither
   reliable nor a contract.
2. **"Can I decide this row?"** The leave list and the jobs list carried no
   approver information. A higher manager can read lower-branch rows (24-2), and
   CAP-5 requires those to be read-only with a plain-English reason. Without a
   per-row answer the app would have to re-implement the resolved-approver walk
   in the client — exactly the client-side authorisation the spec forbids.

Both are read-only additions. No endpoint was added, no permission changed, no
migration was needed, and the decide paths are untouched.

## The contract

### `GET /users/me` — `team`

Every profile with a company carries:

```json
"team": {
  "managerId": "uuid|null",
  "managerName": "string|null",
  "chain": [{ "userId": "uuid", "name": "string" }],
  "directReports": 1,
  "headcount": 2
}
```

- `chain` is nearest-first ("Reports to Priya → Arjun"), the same shape
  `GET /members` returns.
- `headcount` counts everyone strictly below the caller; `directReports` the
  immediate count. Both exclude removed memberships and disabled accounts.
- No company → the empty block (`null`/`[]`/`0`), never a missing key.
- Read with `readMemberHierarchy` — the same helper the admin member pages use,
  so the two can never drift. Two indexed reads seeded at one id; a tree read
  failure degrades to the empty block rather than failing the boot call.
- `GET /users/me/access` is deliberately unchanged: it stays the no-extra-query
  foreground ping.

### Leave and job reads — `decision`

`GET /attendance/leave` (both the team list and the employee's own list) and
`GET /jobs`, plus `GET /jobs/:id`, carry on every row:

```json
"decision": { "canDecide": true, "reason": null }
"decision": { "canDecide": false, "reason": "higher_manager" }
```

`reason` is one of:

| code | meaning |
|---|---|
| `not_pending` | already decided (or not yet submittable) |
| `higher_manager` | pending, but the caller is not in the resolved approver set |
| `unresolved` | pending, but no approver resolves (ownerless company or a corrupt tree) |

- Computed with `decisionFor` over `resolveApproversWithTree` — the same walk the
  decide POST runs, on the requester's branch (leave: `employee_id` with the
  filer as actor, so an on-behalf filing routes up from the subject; jobs:
  `created_by`).
- The admin override is honoured: for jobs it is read from the live tree inside
  the read transaction (matching 24-4's stale-token protection), so a demoted or
  disabled admin shows `false`.
- One tree read per page, one walk per distinct (employee, actor) pair — a page
  with no pending row loads nothing.
- Leave rows present it on list reads (there is no plain `GET /attendance/leave/:id`;
  the detail sheet renders the list row). Job writes keep returning the bare
  response; the app re-reads.

## Verification

**Unit — 2,237 passing, 107 suites** (`src/users src/attendance src/jobs src/members
src/common src/push src/auth src/job-reports`). New pins:

- `decisionFor` — approver, fallback, higher manager, not-pending, unresolved,
  admin override on an unresolved set.
- Leave list — resolved approver `true`; manager above `false/higher_manager`;
  on-behalf filing routes from the subject (filer refused, the manager above
  allowed); decided row `not_pending` with no tree read; corrupt loop
  `unresolved` for a manager while an admin still overrides; one walk per
  (employee, filer) pair.
- Job list/detail — resolved approver `true`; higher manager
  `false/higher_manager`; live-tree admin override (and a disabled admin losing
  it); null creator `unresolved`; tree-read failure degrades to `unresolved`;
  one walk per creator; a page with no pending row queries nothing; the detail
  carries the same answer.
- Profile — the team block maps the walk (chain, headcount, directReports); a
  tree read failure still answers the profile with an empty block; no company
  means an empty block and no query.

**Live HTTP against the `.env` project (`pnlvreaijzslfymlnoti`), real OTP
sessions: 24/24 checks.**

- Three-level branch Employee → Manager → Outsider built with the real
  `PATCH /members/:id/manager`: the employee's profile shows the two-step chain;
  Outsider's shows `headcount 2 / directReports 1`; the employee's own is `0/0`;
  a viewer gets the block too.
- Leave: resolved approver `canDecide: true`; Outsider (above) `false` +
  `higher_manager`; admin override `true`; the POST still decides; the decided
  row reads `not_pending`.
- Jobs: employee submission lands `pending_approval`; Manager `true`, Outsider
  `false/higher_manager`, admin `true`, the detail identical; the POST approves.
- Tree and job settings restored at the end of the probe.

Typecheck clean; lint clean on the new code (the remaining findings are the
pre-existing `any`-logger pattern in `jobs.service.ts` / `users.service.ts`).

## Deliberately not done

- No new endpoint (`GET /members/me/team` was the alternative) and nothing on
  `GET /users/me/access` — one authoritative copy, on the call the app already
  boots from.
- The approval-queue endpoint needed nothing: it is already filtered to rows the
  caller may decide.
- `stories.yaml` / `SPEC.md` are unchanged; this is the BE contract story 24-5
  consumes, recorded here and in `sprint-status.yaml` as `24-5a`.
