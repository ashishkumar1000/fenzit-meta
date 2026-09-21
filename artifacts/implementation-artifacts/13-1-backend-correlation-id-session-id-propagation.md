# Story 13.1: Backend — Correlation ID & Session ID propagation (fenzit-be)

Status: done (implemented + user-verified + BMAD review applied: 9 patches + 1 decision, tests 710/710, 2026-09-21; commit pending user consent)

## Story

As a developer/operator,
I want every inbound request to carry a client-supplied correlation ID and session ID on every backend log line,
so that a reported issue can be traced to the exact request and, when needed, to the whole app sitting that produced it.

## Acceptance Criteria

1. **Read + validate client headers.** An APP_INTERCEPTOR registered BEFORE `LoggingInterceptor` reads `x-correlation-id` and `x-session-id` from the request. A header is accepted only if it matches a UUID format (v4-style 36-char or case-insensitive hex-with-hyphens regex); anything else (missing, wrong type, over-length, injection payloads) is rejected and regenerated. **Never log or echo an unvalidated header value.**
2. **Server fallback.** Missing or invalid `x-correlation-id` → server mints `crypto.randomUUID()`. Missing `x-session-id` → the field is simply absent for that request (session is client-owned; the backend does NOT fabricate a session id). This mirrors Microsoft/Heroku/Rails behavior (service generates when caller omits).
3. **Echo back.** Every response carries `x-correlation-id` (always). `x-session-id` is echoed only when a valid one arrived.
4. **AsyncLocalStorage context.** The correlation context `{ correlationId, sessionId }` is stored in a Node `AsyncLocalStorage` so any code in the request's async chain can read it without parameter threading. The raw request object is ALSO stamped with the ids so the `GlobalExceptionFilter` (which has no ALS access in its current shape) can include them in error logs.
5. **Every log line carries the context.** An app-wide logger (subclass of Nest's `ConsoleLogger`, wired via `app.useLogger(...)` in `main.ts`) merges `{ correlationId, sessionId, userId, tenantId }` from the ALS store into every `Logger.log/warn/error/debug` output — including existing `new Logger(ClassName.name)` call sites, which must keep working WITHOUT edits. When ALS context is absent (e.g. worker, boot), lines log without those fields (no crash, no `undefined` noise).
6. **Access log unified.** `LoggingInterceptor`'s structured JSON line is amended: `request_id` (its own randomUUID) is REPLACED by the correlation context — fields `correlation_id`, `session_id`, `user_id`, `tenant_id`, `route`, `http_status`, `duration_ms`. The legacy `x-request-id` response header is dropped (pre-launch, no compat shims; no consumer of it exists).
7. **Worker correlation.** `ReportWorker`'s per-job processing runs inside `als.run({ correlationId: crypto.randomUUID() })` so worker logs carry a correlation id too (per-job fresh UUID; `reportRequestId` continues to identify the job domain-wise).
8. **Unit tests** mirror `logging.interceptor.spec.ts` patterns: context interceptor (accept/validate/fallback/echo), logger merge (with and without ALS context), LoggingInterceptor field changes. All existing tests stay green.
9. **Docs updated in the same change** (`docs/architecture.md` logging/cross-cutting section + README where it describes the middleware chain): header names, validation rule, echo behavior, log field names.

## Tasks / Subtasks

- [x] Task 1: Correlation context infrastructure (AC: 1, 2, 4)
  - [x] New `src/common/correlation/correlation.context.ts` — `AsyncLocalStorage<CorrelationContext>` holder + `getCorrelationContext()` reader (pure, no Nest deps; ~40 lines per small-modular rule)
  - [x] New `src/common/correlation/correlation.interceptor.ts` — APP_INTERCEPTOR: validate UUID regex, fallback `randomUUID()`, `als.run(...)` around `next.handle()`, stamp `request.correlationId`/`request.sessionId`, set echo response headers
  - [x] UUID validation helper (regex) co-located in the correlation folder; header constants (`CORRELATION_HEADER = 'x-correlation-id'`, `SESSION_HEADER = 'x-session-id'`) exported for FE parity
- [x] Task 2: App-wide logger merge (AC: 5)
  - [x] New `src/common/correlation/correlation-logger.ts` — extends Nest `ConsoleLogger`, overrides `log/warn/error/debug/verbose` to append the merged context object; no-op fields when ALS is empty
  - [x] `main.ts`: `app.useLogger(new CorrelationLogger())` (confirm with a quick test that Nest routes `new Logger(...)` instances through the app logger — this is the load-bearing assumption, verify FIRST before building on it)
- [x] Task 3: Integrate with existing interceptors/filter (AC: 6, 4)
  - [x] `LoggingInterceptor`: stop minting its own UUID; read context from ALS/request; emit `correlation_id`, `session_id`, `user_id`, `tenant_id`; drop `x-request-id` echo
  - [x] `GlobalExceptionFilter`: read `request.correlationId`/`sessionId` via `host.switchToHttp().getRequest()` and include in the unhandled-error log line
  - [x] `app.module.ts`: register `CorrelationInterceptor` as the FIRST APP_INTERCEPTOR (before `LoggingInterceptor`)
- [x] Task 4: Worker correlation (AC: 7)
  - [x] `src/reports/engine/report-worker.ts` (or pipeline service): wrap per-job processing in `als.run({ correlationId: randomUUID() })`
- [x] Task 5: Tests (AC: 8)
  - [x] `correlation.interceptor.spec.ts` — fake `ExecutionContext` per `logging.interceptor.spec.ts` pattern: valid header accepted+echoed, invalid header replaced, missing header generated, session echoed only when valid
  - [x] `correlation-logger.spec.ts` — merge with ALS context; no-context output stays clean
  - [x] Update `logging.interceptor.spec.ts` for renamed fields
- [x] Task 6: Docs (AC: 9)
  - [x] `docs/architecture.md` + README: correlation design, header contract, log field names

## Dev Notes

- **Framework reality: NestJS 11 on Fastify, NOT Express** (`src/main.ts` uses `FastifyAdapter({ logger: false })` — Fastify's own logger is off). There are NO Express `app.use()` middlewares; cross-cutting concerns are APP_FILTER/APP_GUARD/APP_INTERCEPTOR providers in `src/app.module.ts` (lines ~146–163, order: GlobalExceptionFilter → JwtAuthGuard → RolesGuard → LoggingInterceptor). The correlation interceptor goes FIRST in the APP_INTERCEPTOR list so `LoggingInterceptor` sees the context.
- **Existing request-ID behavior to replace, not preserve:** `src/common/interceptors/logging.interceptor.ts` (lines 24–26) already generates `randomUUID()` per request, stashes `request.requestId`, echoes `x-request-id`. Grep confirmed ZERO other consumers of `requestId`. Replace with the correlation context; do not keep both IDs (pre-launch, no compat shims per user memory).
- **Logging reality:** Nest built-in `Logger` from `@nestjs/common` everywhere (`private readonly logger = new Logger(ClassName.name)`); NO pino/winston/pino-http/morgan/axios in package.json. Do NOT introduce pino — the ConsoleLogger-subclass approach achieves the research's "mixin" outcome in Nest-native terms. The only structured logging today is `LoggingInterceptor.log()` which hand-`JSON.stringify`s one object; keep that shape (parseable one-line JSON), now with correlation fields.
- **Load-bearing assumption to verify first (Task 2):** that `app.useLogger(new CorrelationLogger())` redirects ALL `new Logger(Context)` instances to the subclass (Nest's Logger delegates to the app logger set by `useLogger`). If Nest 11 does NOT route instance loggers through the app logger, fall back to `Logger.overrideLogger()` (static) or a small `CorrelatedLogger` static wrapper — decide with evidence from a 5-minute spike, and record the finding in Dev Agent Record.
- **ALS gotchas from the research (apply, don't rediscover):** prefer `als.run()` over `enterWith()` (Node docs warn `enterWith` leaks context past its boundary — source: nodejs.org/api/async_context.html); EventEmitter listeners bind with `AsyncResource.bind()` if any appear; context does NOT cross the job-queue boundary — the worker mints its own (Task 4). There is no broker/queue library — the "queue" is the `report_requests` table polled by in-process `setInterval` (`src/reports/engine/report-worker.ts`), so `als.run()` per job is sufficient; no snapshot/serialization machinery needed.
- **Security (backend-first, never trust the client):** the UUID-regex validation is the log-injection defense (a header like `\n2026-... INFO fake` must be rejected, not logged/echoed). Also cap header length before regex (e.g. reject > 64 chars). `userId`/`tenantId` come from `request.user` attached by `JwtAuthGuard` (shape: `{ userId, tenantId, role, rawJwt }` in `src/common/interfaces/request-user.interface.ts`) — NEVER from a client header. Public routes (`@Public()`) will have no user — fields absent, fine.
- **Outbound propagation is OUT OF SCOPE for 13-1.** Outbound calls are per-provider global `fetch` (Google Places), AWS SDK (R2), and Supabase REST — no shared HTTP client exists to intercept, and none of these are ours to correlate (they're third parties). Do not add header forwarding to them. This story is inbound-only + logs.
- **Testing pattern to copy:** `src/common/interceptors/logging.interceptor.spec.ts` — fake plain-object ExecutionContext, instantiate directly (no DI), `jest.spyOn(interceptor['logger'], 'log')`, `JSON.parse` the logged string to assert fields. Unit tests co-located as `*.spec.ts` under `src/` (jest 30 + ts-jest, `rootDir: "src"`). E2E lives in `test/*.e2e-spec.ts` — not required for this story beyond existing suites staying green.
- **Test timing rule (user global):** do NOT write tests up front beyond what's needed to keep suites green; the dev agent implements, the user confirms behavior (e.g. via Render logs / local run), THEN tests. Structure Task 5 to run after user confirmation, same as epics 11–12 did.

### Project Structure Notes

- New files: `src/common/correlation/{correlation.context.ts, correlation.interceptor.ts, correlation-logger.ts}` + co-located specs — sibling to `src/common/interceptors/`, `src/common/filters/`, `src/common/guards/`. ~300-line file cap per repo convention.
- Modified: `src/app.module.ts` (interceptor registration), `src/main.ts` (useLogger), `src/common/interceptors/logging.interceptor.ts` (+spec), `src/common/filters/global-exception.filter.ts`, `src/reports/engine/report-worker.ts`, docs.
- No new dependencies. No DB change. No migration. No Supabase MCP work.

### References

- Research (design + evidence): `artifacts/planning-artifacts/research/technical-correlation-id-2026-09-21/research.md` — exec summary + §3 backend section; header contract per user decisions 2026-09-21 (`X-Correlation-ID` per request stable across retries + `X-Session-ID` per app sitting; session ID added to v1 scope by user on 2026-09-21)
- Architecture conventions: `artifacts/planning-artifacts/architecture/architecture-address-autosuggest-2026-09-05/ARCHITECTURE-SPINE.md` (modular monolith, no compat shims)
- Repo facts gathered by exploration 2026-09-21: `src/main.ts`, `src/app.module.ts` (lines 146–163), `src/common/interceptors/logging.interceptor.ts` (+spec), `src/common/filters/global-exception.filter.ts` (lines 66–69), `src/common/guards/jwt-auth.guard.ts` (line 94), `src/common/interfaces/request-user.interface.ts`, `src/reports/engine/report-worker.ts` (lines 59–85, 160–168), `package.json` (fastify ^5.8.5, @nestjs/* ^11, no pino)

### Review Findings

- [x] [Review][Decision] No echo on guard-rejected / 404 responses — responses that never reach interceptors (JwtAuthGuard reject, route not found) carry no `x-correlation-id` echo, while the design/AC3 says "every response". Fixing properly needs a Fastify `onSend`/`onError` hook outside the interceptor chain. — RESOLVED: accept the caveat (app mints the id, so it knows what it sent); architecture.md corrected to "every response that passes the interceptor chain".
- [x] [Review][Patch] Double correlation JSON on unhandled-exception log line (VERIFIED in test) — GlobalExceptionFilter's error branch actually runs INSIDE the ALS scope for request exceptions, so `CorrelationLogger.merge` appends a second `{correlation_id…}` blob on top of the filter's own suffix; the "runs outside the correlation ALS scope" comment is wrong [src/common/filters/global-exception.filter.ts:66-79] — FIXED: filter logs plain message and lets `CorrelationLogger.merge` append the ids; the stamped-request suffix is now only the no-ALS fallback; comment corrected.
- [x] [Review][Patch] Non-string log message degrades to `[object Object]` in merge() [src/common/correlation/correlation-logger.ts:60] — FIXED: plain-object messages get fields merged and re-stringified as one JSON line.
- [x] [Review][Patch] Worker job-failure logs escape the correlation scope — `claimAndProcess` throws unwind the ALS run before `tick()`'s catch logs [src/reports/engine/report-worker.ts:131-146] — FIXED: per-job catch moved inside the `runWithCorrelation` scope ("Report job failed:").
- [x] [Review][Patch] Worker correlation context seeds null tenant/user though the claimed row carries `tenant_id`/`requested_by` [src/reports/engine/report-worker.ts:131-146] — FIXED: store object seeded in place after the claim.
- [x] [Review][Patch] No test observes the unhandled-exception log suffix (filter logger never spied) [src/common/filters/global-exception.filter.spec.ts] — ADDED: 3 tests (stamped ids, no ids, correlation-only).
- [x] [Review][Patch] No test asserts the per-job correlation scope is active during `pipeline.run` [src/reports/engine/report-worker.spec.ts] — ADDED: 2 tests (scope active + seeded ids; scope stays active on job failure).
- [x] [Review][Patch] 8 new/changed files missing trailing newline [src/common/correlation/*, src/common/interceptors/*] — FIXED.
- [x] [Review][Patch] architecture.md wording: "every response carries x-correlation-id" vs guard/404 reality; "UUID v4" vs any-version regex [docs/architecture.md] — FIXED: echo caveat accepted and stated; any-version acceptance clarified.
- [x] [Review][Defer→Done] `app.useLogger` wiring has no end-to-end boot test [src/main.ts:36] — COMPLETED on user request: wiring test added (overrideLogger routes instance Loggers through CorrelationLogger, merge included) [correlation-logger.spec.ts]
- [x] [Review][Defer→Done] R2 410 mapping (`NotFound` → GoneException) has no test [src/reports/reports.service.ts:338-343] — COMPLETED on user request: 410 test added against the real SDK class [reports.service.spec.ts]
- [x] [Review][Defer→Done] Session-hygiene observability [src/common/correlation/correlation.interceptor.ts] — COMPLETED on user request: warn on present-but-invalid session header (raw value never logged) + 2 tests

## Dev Agent Record

### Agent Model Used

Claude (GLM, Claude Code session) — 2026-09-21

### Debug Log References

User-verified locally via `bun run start:dev` + curl against `http://localhost:3000/health` (2026-09-21):
- No headers → server-minted UUID echoed; log line `{"correlation_id":"0eee57e2-…","session_id":null,"user_id":null,"tenant_id":null,"route":"GET /health","http_status":200,"duration_ms":0}`
- Valid headers → both echoed verbatim (`x-correlation-id: 11111111-2222-4333-8444-555555555555`, `x-session-id: 9abcdef0-…`) and same values in the access log
- Injection attempt (`x-correlation-id: FAKE-LOG-LINE-INJECT`) → rejected, fresh server UUID echoed, raw value appears nowhere

### Completion Notes List

- **Load-bearing assumption VERIFIED (docs, then device):** Nest routes every `new Logger(Context)` instance through the app logger registered with `app.useLogger(...)` — confirmed via Context7 NestJS logger docs ("calls to `this.logger.log()` from `MyService` would result in calls to method `log` from `MyLogger` instance") and by the live log lines above going through `CorrelationLogger`'s merge. No `Logger.overrideLogger()` fallback needed.
- **ALS subscription-wrapping (implementation decision, differs from naive design):** `als.run(store, () => next.handle())` alone is insufficient — Nest subscribes to the interceptor chain AFTER `intercept()` returns, so the store must be active at SUBSCRIPTION time. Implemented as `new Observable((subscriber) => runWithCorrelation(store, () => next.handle().subscribe(subscriber)))`.
- **Execution order:** guards run BEFORE interceptors, so `request.user` is already attached when `CorrelationInterceptor` reads it (userId/tenantId in scope). If a guard rejects, no interceptors run → no ids echoed (same as the old `x-request-id` behavior). First-registered APP_INTERCEPTOR is outermost.
- **GlobalExceptionFilter has no ALS access in its scope** → ids are stamped on the raw request object by the interceptor and read there; non-HttpException error log gets a compact `{"correlation_id":…,"session_id":…}` suffix (only when a correlationId exists, i.e. a request that passed the interceptor).
- **Validation hardening beyond the story text:** header rejected if not a string, > 64 chars, or not UUID-shaped (8-4-4-4-12 hex, any version, case-insensitive — FE mints v4). Arrays/type-mismatches rejected by the `typeof` check. Unvalidated values are never logged or echoed.
- **Session never fabricated server-side:** invalid/missing session header → `session_id: null` in logs, no `x-session-id` echo (verified in the no-headers probe).
- **Worker:** `ReportWorker.processOne` renamed body to `claimAndProcess` and wraps it in `runWithCorrelation({ correlationId: randomUUID(), … })` — ALS does not cross the `setInterval` job boundary, so each job mints its own id.
- **Legacy retired:** `LoggingInterceptor` no longer mints `request_id` or echoes `x-request-id`; access-log fields are now `correlation_id, session_id, user_id, tenant_id, route, http_status, duration_ms`. `logging.interceptor.spec.ts` asserts the OLD `request_id` field — stale until Task 5.
- **Typecheck clean** (`bun run typecheck`). No new dependencies, no DB change.
- **Tests green 705/705 (2026-09-21, after user confirmation):** new `correlation.interceptor.spec.ts` (7) + `correlation-logger.spec.ts` (6) + rewritten `logging.interceptor.spec.ts` (3). Two incidental fixes landed in the same pass: (1) `global-exception.filter.spec.ts` mock host gained `getRequest()` (the filter now reads the stamped request); (2) `src/storage/storage.service.spec.ts` was failing **pre-existing on a clean tree** (verified via stash) — its AWS SDK mock lacked `HeadObjectCommand`/`client.send` and the service had a dead `instanceof NotFound` branch (both arms threw err; the check crashed under jest CJS interop) — dead branch removed from `storage.service.ts`, mock completed.
- **Docs updated in same change:** `docs/architecture.md` AR-15 rewritten (header contract, validation, echo, ALS + CorrelationLogger, access-log fields, worker correlation) + README `common/` tree line.
- **BMAD review (2026-09-21, 4 layers) — 12 findings after triage: 1 decision (accepted: no echo on guard-rejected/404 responses), 9 patches applied, 3 deferred** (recorded in `deferred-work.md`); 8 dismissed. Patches: (1) the review VERIFIED — with a throwaway ALS test — that GlobalExceptionFilter's error branch runs INSIDE the ALS scope, so the filter's own JSON suffix double-appended over `CorrelationLogger.merge`'s; filter now logs plain and merge appends (stamped-request suffix kept as no-ALS fallback); (2) plain-object log messages merge fields instead of degrading to `[object Object]`; (3) worker job-failure catch moved inside the correlation scope; (4) worker context seeded from the claimed row's `tenant_id`/`requested_by`; (5–6) 5 new tests covering the filter log line and the worker scope; (7) trailing newlines; (8) architecture.md echo caveat + any-version wording. Tests green **710/710**, typecheck clean.
- **Deferred items completed on user request (2026-09-21, pre-commit):** (1) `app.useLogger` delegation covered by a wiring test (`Logger.overrideLogger` routes instance Loggers through CorrelationLogger); (2) R2 `NotFound` → 410 mapping test added (real SDK class, StorageService mocked at the service boundary); (3) interceptor warns on present-but-invalid session header — raw value never logged. Tests green **714/714**, typecheck clean. No defers remain for this story.

### File List

Created (fenzit-be):
- `src/common/correlation/correlation.context.ts` — ALS store + `getCorrelationContext()` + `runWithCorrelation()`
- `src/common/correlation/correlation-headers.ts` — header name constants + `parseCorrelationHeader()` UUID/length validator
- `src/common/correlation/correlation.interceptor.ts` — `CorrelationInterceptor` (validate/mint/echo/ALS/req-stamp) + `CorrelatedRequest` interface
- `src/common/correlation/correlation-logger.ts` — `CorrelationLogger` (ConsoleLogger subclass) + `correlationLogFields()`

Modified (fenzit-be):
- `src/main.ts` — `app.useLogger(new CorrelationLogger())`
- `src/app.module.ts` — `CorrelationInterceptor` registered as FIRST APP_INTERCEPTOR
- `src/common/interceptors/logging.interceptor.ts` — rewrite: correlation context fields, `request_id`/`x-request-id` removed
- `src/common/filters/global-exception.filter.ts` — unhandled-exception log carries stamped ids
- `src/reports/engine/report-worker.ts` — per-job `runWithCorrelation` wrapper
- `docs/architecture.md`, `README.md`

Meta-repo (no commit yet, per no-commit-without-consent):
- `artifacts/implementation-artifacts/13-1-backend-correlation-id-session-id-propagation.md` (this file)
- `artifacts/implementation-artifacts/sprint-status.yaml` (13-1 → review)
- `artifacts/planning-artifacts/research/technical-correlation-id-2026-09-21/` (research)