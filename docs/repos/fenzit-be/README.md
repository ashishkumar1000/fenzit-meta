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
