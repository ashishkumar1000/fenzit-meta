# Digest — dimension 3: backend logging & propagation (round 1)

## 1. Middleware pattern (read header, fallback generate, echo back)

- {claim: Standard manual Express pattern: read `req.headers['x-request-id']`, fall back to `crypto.randomUUID()`, assign to `req.id`, echo back via `res.set('X-Request-Id', requestId)`, register as first middleware before routes/CORS/body-parsing. Tutorial-level consensus, not one authoritative doc., source: npm express-request-id + multiple tutorials, publisher: npm/dev.to/GeeksforGeeks, accessed=2026-09-21, confidence: medium, class: practice}
- {claim: `express-request-id` package (~30K weekly downloads, not recently updated) sets `req.id` and echoes `X-Request-Id`; supports custom header and generator function., source: https://www.npmjs.com/package/express-request-id, publisher: npm, accessed=2026-09-21, confidence: medium, class: standard}
- {claim: Fastify has this built in: `requestIdHeader` (default `false`) names an incoming header to honor, e.g. `requestIdHeader: 'x-request-id'`; `genReqId` is fallback generator, called only when the header is absent; log label defaults to `reqId` (configurable via `requestIdLogLabel`). Fastify warns honoring the header lets any caller set reqId to any value with no validation., source: https://fastify.dev/docs/latest/Reference/Server/, publisher: Fastify, pub_date: current docs, accessed=2026-09-21, confidence: high, class: standard}
- Contradiction: 2019 Fastify issue #1584 reported `genReqId` wrongly taking precedence over the header; fixed so the header now wins. {source: https://github.com/fastify/fastify/issues/1584, pub_date: 2019-04, confidence: medium}

## 2. Attaching the ID to every log line

- {claim: Node official docs present AsyncLocalStorage (ALS) as the built-in way to propagate per-request data across async operations, with a canonical HTTP-server example storing a per-request id; ALS Stable since v16.4.0, preferred over hand-rolling async_hooks., source: https://nodejs.org/api/async_context.html, publisher: Node.js, accessed=2026-09-21, confidence: high, class: standard}
- {claim: Pino's recommended integration is the `mixin` option — a function reading the ALS store that merges `reqId` into every log line — with `mixinMergeStrategy` to let store values win; pino deliberately chose mixin over automatic ALS integration (pino issue #1097)., source: https://github.com/pinojs/pino/blob/main/docs/asynchronous-storage.md (via search), publisher: pinojs, accessed=2026-09-21, confidence: medium, class: standard} — direct fetch timed out; pattern quoted consistently across search results.
- {claim: `pino-http` supports `genReqId` and, combined with ALS, gives every log line the request id without plumbing `req.log` through helpers., source: https://dev.to/jeanp413/nodejs-asynchronous-local-storage-example-with-pino-http-1bcb, publisher: dev.to, accessed=2026-09-21, confidence: medium, class: practice}
- cls-hooked: no 2024–2026 source recommends it as current; ALS is the successor everywhere. Treated as legacy (absence of evidence).

## 3. Propagation to downstream calls and background jobs

- {claim: Canonical axios pattern on the *server* for outbound calls: request interceptor that reads the ALS store and sets `x-correlation-id` on each outbound call; setting the header on a shared axios singleton's defaults is a documented anti-pattern — under concurrency one user's ID leaks into another user's request (axios maintainer flagged in discussion #5955)., source: https://github.com/axios/axios/discussions/5955, publisher: GitHub/axios, accessed=2026-09-21, confidence: medium, class: practice}
- {claim: ALS context does not survive a job-queue boundary; fixes: `AsyncLocalStorage.snapshot()` at enqueue time, or carry correlationId in the job payload and have the worker re-run `als.run()`. Cron/interval jobs mint their own ID., source: https://dev.to/tarun_koshti_122/asynclocalstorage-in-nodejs-stop-passing-requestid-to-every-function-2lcd + https://nerdleveltech.com/nodejs-correlation-id-asynclocalstorage-tutorial, publisher: dev.to/nerdleveltech, pub_date: 2026 (per titles), accessed=2026-09-21, confidence: medium, class: practice}
- {claim: EventEmitter listeners run with the context active at emit time, not registration time — use `AsyncResource.bind()`; Node docs warn `enterWith()` leaks context beyond its boundary, prefer `run()`., source: https://nodejs.org/api/async_context.html (primary for enterWith/prefer-run), publisher: Node.js, accessed=2026-09-21, confidence: high, class: standard}

## 4. Structured logging conventions

- {claim: Datadog correlates logs↔traces via `dd.trace_id`/`dd.span_id` JSON fields (nested `dd` object), auto-injected for pino/bunyan/winston when JSON-formatted; custom field names need a Trace ID Remapper pipeline rule; traces and logs sampled independently so a log can carry a trace ID for a non-retained trace., source: https://docs.datadoghq.com/tracing/other_telemetry/connect_logs_and_traces/nodejs.md, publisher: Datadog, accessed=2026-09-21, confidence: high, class: standard}
- {claim: W3C Trace Context v1 (Rec 2021) defines `traceparent` with 16-byte trace-id as the portable distributed correlation ID; spec mandates no PII in these headers, prefers random over timestamp/IP-derived IDs, says ignore malformed/all-zero headers. Level 2 still Candidate Recommendation (2023–2024 drafts)., source: https://www.w3.org/TR/trace-context/ + https://www.w3.org/TR/trace-context-2/, publisher: W3C, accessed=2026-09-21, confidence: high, class: standard}

## 5. Is manual middleware redundant under OTel?

- {claim: With `@opentelemetry/sdk-node` + auto-instrumentations, `traceparent` is automatically extracted from inbound HTTP requests and injected into outbound ones (http/express/undici/axios instrumentation) — no manual propagation code needed., source: https://opentelemetry.io/docs/languages/js/propagation/ + https://github.com/open-telemetry/opentelemetry-js/tree/main/packages/opentelemetry-sdk-trace-node, publisher: OpenTelemetry, accessed=2026-09-21, confidence: high, class: standard} — implication: manual header middleware is NOT redundant for app-level correlation (search by client-supplied ID in plain stdout logs), but IS redundant for trace propagation if OTel is enabled; the two systems need bridging (OTel trace-id ↔ correlationId field).

## Not found / gaps

- No authoritative doc prescribing one canonical JSON field name (`requestId` vs `correlationId` vs `trace_id`) — only Datadog's reserved `dd.trace_id` is normative. Fastify uses `reqId`.
- New Relic and Grafana/Loki header-extraction conventions not read (budget).
- Pino's async-storage doc could not be fetched directly (404 on blob URL, timeout on raw URL) — mixin pattern rests on search-result quotations.
- No Render-specific stdout guidance surfaced.