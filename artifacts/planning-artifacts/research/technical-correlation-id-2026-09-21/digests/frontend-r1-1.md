# Digest — dimension 4: frontend (React Native) implementation reality (round 1)

## Q1. Scope of the client-generated ID

- {claim: Use layered identifiers — a per-request ID (one HTTP call) plus a stable session ID (one sitting in the app) — rather than one ID for everything; a per-user ID alone is not a recommended substitute. Session ID is accepted-or-generated at the edge and carried unchanged, while request ID covers one call's fan-out., source: https://kristianeschenburg.netlify.app/post/request-correlation-middleware/, publisher: Kristian Eschenburg (engineering blog), pub_date: not shown, accessed=2026-09-21, confidence: medium, class: practice}
- {claim: OneUptime's guide shows clients sending both `X-Request-ID` (fresh per request) and `X-Client-Session`/`X-Session-ID` (stable per session), with request IDs composed as `${sessionId}-${timestamp}-${counter}` for sortability., source: https://oneuptime.com/blog/post/2026-01-30-request-trace-correlation/view, publisher: OneUptime blog, pub_date: 2026-01-30, accessed=2026-09-21, confidence: medium, class: practice}
- {claim: Retries are contested: one guide says reuse the original request ID across retry attempts + separate `X-Retry-Count` header; another says each retry gets a new request ID under the same correlation ID. Both agree: one logical operation stays one queryable unit, attempt-level detail kept separate., source: https://dev.to/sirmax/trace-any-api-request-across-your-stack-a-practical-guide-to-request-ids-29ck vs https://dev.to/couimet/correlation-id-vs-request-id-a-practical-guide-2l6o, publisher: DEV Community (two authors), accessed=2026-09-21, confidence: medium, class: practice}

## Q2. Generation on-device

- {claim: `expo-crypto`'s `Crypto.randomUUID()` returns a v4 UUID from cryptographically secure random values, supported on Android, iOS, tvOS and Web., source: https://docs.expo.dev/versions/unversioned/sdk/crypto, publisher: Expo official docs, pub_date: current, accessed=2026-09-21, confidence: high, class: standard}
- {claim: The npm `uuid` package throws `crypto.getRandomValues() not supported` in React Native unless a polyfill is installed; `react-native-get-random-values` fills `crypto.getRandomValues()` using native `SecRandomCopyBytes` (iOS) / `SecureRandom` (Android) and must be imported before `uuid` (import order critical)., source: https://github.com/LinusU/react-native-get-random-values and https://github.com/uuidjs/uuid#getrandomvalues-not-supported, publisher: LinusU / uuidjs GitHub, accessed=2026-09-21, confidence: medium, class: standard}
- {claim: `uuid@10.0.0` (June 2024) added `v7()` with `options.msecs/rng/seq` (seq handles same-millisecond uniqueness via counter bits, RFC 9562 Method 1); from `uuid@12` the package is ESM-only., source: https://github.com/uuidjs/uuid/compare/v9.0.1...v10.0.0, publisher: uuidjs GitHub, pub_date: 2024-06-07, accessed=2026-09-21, confidence: medium, class: version}
- {claim: UUIDv7 (RFC 9562, May 2024) has a 48-bit ms-timestamp prefix so values sort in creation order — better for log correlation — while v4 leaks nothing about timing; v7 also leaks creation time to millisecond precision. Within one millisecond, ordering not guaranteed unless counter bits used., source: https://blog.openreplay.com/uuid-v4-vs-v7/ and https://recatools.com/guides/uuid-v4-vs-v7-2026/, publisher: OpenReplay / recatools, pub_date: 2025-2026, accessed=2026-09-21, confidence: medium, class: standard}
- {claim: Node `crypto.randomUUIDv7()` exists only in Node 24.16+/26.1+, so RN cannot lean on the JS runtime's built-in for v7 — a library is needed on-device., source: https://www.devtidy.com/blog/uuid-v4-vs-v7/, publisher: DevTidy blog, accessed=2026-09-21, confidence: low, class: version}
- Persistence across relaunch: no guide states a per-request ID should persist across app relaunches (it should not, by scope). Persistence concerns in the sources apply only to device IDs.

## Q3. Implementation pattern

- {claim: Standard pattern is centralized injection — `axios.interceptors.request.use(config => { config.headers['X-Request-ID'] = uuidv4(); return config; })` — not `axios.defaults.headers` (shared, would stamp same value on every call). A fetch wrapper injecting the header is the equivalent for non-axios apps., source: https://axios-http.com/docs/interceptors + https://dev.to/shayy5/mastering-http-request-ids-in-javascript-59p1, publisher: Axios docs / DEV Community, accessed=2026-09-21, confidence: high (axios API), medium (guide), class: standard}
- {claim: No dedicated React Native correlation-ID library surfaced; every source implements it as an interceptor or fetch wrapper. RN-specific gotcha: header behaviour at the native layer (custom `user-agent` in `fetch()` on Android overrides WebView UA, facebook/react-native#27962), so plain custom headers like `X-Request-ID` are safer than headers the native stack manages., source: https://github.com/facebook/react-native/issues/27962, publisher: Meta react-native GitHub issue, accessed=2026-09-21, confidence: medium, class: practice}

## Q4. Complementary headers

- {claim: Mobile observability guides recommend the request also carry app version (`X-App-Version`), device ID (`X-Device-ID`), and a session ID alongside the trace/request ID — for release-by-release comparison, telemetry, user-journey correlation; sensitive values masked before leaving the device., source: https://community.dynatrace.com/ (APM for Mobile Apps) and Raygun/Embrace mobile observability guides, accessed=2026-09-21, confidence: low-medium, class: practice}
- {claim: Sentry's crash-correlation flow gives the user the *event ID* (returned by `captureException` / `lastEventId()`), not the issue ID; the event may have been dropped by sampling so the ID may match no stored event., source: https://www.sentry.help/en/articles/13965129-how-can-i-give-an-event-id-to-the-end-user, publisher: Sentry Help Center, accessed=2026-09-21, confidence: high, class: standard}

## Q5. Echoing the ID back

- {claim: Multiple guides recommend echoing IDs back in response headers so the user becomes a first-line debugger, and validating incoming IDs (length/charset) before echoing to prevent log injection., source: https://oneuptime.com/blog/post/2026-01-30-request-trace-correlation/view + https://dev.to/sirmax/trace-any-api-request-across-your-stack-a-practical-guide-to-request-ids-29ck, publisher: OneUptime / DEV Community, pub_date: 2026-01-30, accessed=2026-09-21, confidence: medium, class: practice}
- {claim: Documented "copy debug info" UX exists in crash reporting: show `Error ID: {eventId}`, support searches it (Sentry Explore `id:"<32-char event_id>"`), direct URL template links ticket to event., source: https://www.sentry.help/en/articles/13964363-why-isn-t-my-user-feedback-showing-up-in-sentry-every-time + https://github.com/getsentry/sentry/issues/108213, publisher: Sentry Help Center / getsentry GitHub, accessed=2026-09-21, confidence: medium, class: practice}

## Contradictions

- Retry semantics: Sir Max — reuse original request ID per retry + `X-Retry-Count`; Ouimet — new request ID per retry under the same correlation ID. Same underlying invariant: stable search key per logical operation, attempt detail separate. Naming-convention choice the fenzo design must pick explicitly (the team's "correlation key" wording leans correlation-ID-style: stable across retries).
- Smithy Rust RFC-0024 prefers server-generated UUID v4 for the server request ID and distrusts client-supplied IDs (duplicate/missing/malicious); .NET HttpCorrelationProtocol says caller-generated, callee generates only if absent. Different IDs, but flags: backend must not blindly trust/echo client IDs (log-injection validation).

## Leads worth chasing

- `traceparent` as standards-track alternative if the backend later adopts OTel.
- OTel mobile tracing (Raygun/Embrace) for client spans linked to backend spans.
- `uuid` `v7()` monotonicity in Hermes — unverified.

## Not found

- No engineering guide prescribing per-user scope for a request ID (per-user ID appears only as an implicit identity field, not a correlation key).
- No dedicated open-source RN correlation-ID library (pattern is always interceptor/wrapper).
- No documented "copy debug info" UX for backend request IDs specifically — only the Sentry event-ID pattern.
- Caveat: sources read via search-result summaries this round, not full-page fetches; non-official-doc claims capped at medium confidence.