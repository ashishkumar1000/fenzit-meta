# fenzit-be (backend)

- Remote: https://github.com/ashishkumar1000/fenzit-be.git
- Local path: `workspace/core/backend/fenzit-be`
- Role: backend
- Default branch: main

Durable notes about this repo (architecture, conventions, how `fenzo-app` depends on it) go here. Repo-local operational docs (setup, scripts, etc.) stay inside the repo itself.

## Interface Contract (what `fenzo-app` depends on from this repo)

Keep this current whenever a cross-repo change lands — this is what lets an agent catch "this backend change breaks the frontend" *before* making the change, not after.

- API surface exposed to `fenzo-app` (endpoints, or link to OpenAPI spec):
- Response shapes / DTOs that are load-bearing for the frontend (breaking these breaks `fenzo-app`):
- Auth mechanism issued to consumers:
- Breaking-change policy (versioned routes? deprecation window?):

## Build History (BMAD)

This repo was built solo with BMAD before `fenzo-meta` existed. On 2026-09-25 that history was moved out of the child repo into `bmad-history/` next to this README (a frozen record; internal links inside it still use the old `_bmad-output/` paths). All new BMAD work lives in meta's `artifacts/` — meta is the single source of truth.

As of 2026-08-30, all 4 defined epics are implemented and every story is `done` (per `sprint-status.yaml`) — there is no pending/unfinished story right now.

- Epic 1 — Project Foundation & Authentication (auth, tenant onboarding, technician invites)
- Epic 2 — Customer Management (create/search/detail)
- Epic 3 — Job Lifecycle (create/list/detail/edit/workflow steps/attachments)
- Epic 4 — Offline-First Mobile Sync (delta sync, idempotent replay, conflict resolution)

Source files (frozen, in `docs/repos/fenzit-be/bmad-history/`):
- `bmad-history/planning-artifacts/epics.md` — full epic/story breakdown, FRs and ARs
- `bmad-history/planning-artifacts/prds/` — PRD + addendum
- `bmad-history/planning-artifacts/architecture.md` — architecture doc
- `bmad-history/implementation-artifacts/sprint-status.yaml` — per-story status, source of truth for what's done
- `bmad-history/implementation-artifacts/deferred-work.md` — real known gaps from past code reviews (see below)

### Known deferred work (genuinely pending, from `deferred-work.md`)

The full list lives in `deferred-work.md` above; the ones worth knowing about before touching auth or security-sensitive paths:

- **OTP verification is not real** — `verifyOtp` has `isValid = true` hardcoded, any 6-digit code succeeds. Explicitly flagged "critical before any production deployment."
- **RLS gaps deferred by user until project is complete**: `setup_tenant_for_owner` RPC has no GRANT restriction (any authenticated user can call it); `tenants` table has SELECT-only RLS, no explicit INSERT/UPDATE/DELETE deny policies; `CustomersService.createCustomer()` uses the service-role client, bypassing RLS entirely (tenant isolation rests on the app layer only).
- **No CI database** — RLS isolation tests and a few DB-dependent integration assertions (job numbering race safety, atomic activity-log writes) are always skipped/mocked in CI; several stories flag this as the same underlying infra gap.
