# fenzo-app (frontend)

- Remote: https://github.com/ashishkumar1000/fenzo-app.git
- Local path: `workspace/core/frontend/fenzo-app`
- Role: frontend
- Default branch: main

Durable notes about this repo (architecture, conventions, how it talks to `fenzit-be`) go here. Repo-local operational docs (setup, scripts, etc.) stay inside the repo itself.

## Interface Contract (what this repo depends on from `fenzit-be`)

Keep this current whenever a cross-repo change lands — this is what lets an agent catch "this backend change breaks the frontend" *before* making the change, not after.

- Backend base URL / API version consumed:
- Endpoints called (path, method, request/response shape or link to OpenAPI spec):
- Shared types/DTOs (hand-copied? generated from an OpenAPI/schema? codegen command if any):
- Auth mechanism expected from the backend:
- Env vars this repo needs pointed at `fenzit-be`:
