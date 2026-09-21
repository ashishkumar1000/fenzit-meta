# Digest — dimension 1+2: standards & header conventions (round 1)

## Findings

- {claim: `X-Request-ID` and `X-Correlation-ID` are the de facto non-standard headers for request correlation; Microsoft's REST API Guidelines define the most-cited spec: `X-Correlation-ID` (end-to-end transaction, "required for all API calls", propagated unmodified, service generates one if caller omits) vs `X-Request-ID` (per-request, recommended GUID), with `X-Correlation-Status: invalid-correlation-id` returned on bad input., source: https://github.com/microsoft/api-guidelines via search summary, publisher: Microsoft, pub_date: current (living doc), accessed=2026-09-21, confidence: medium, class: practice}
- {claim: Heroku router generates a UUID-style request ID and passes it to the app as `X-Request-ID`; clients may supply their own (20–200 chars, ASCII letters/digits/+/=/-; invalid values are replaced), for router↔dyno log correlation., source: https://devcenter.heroku.com/articles/http-request-id, publisher: Heroku, pub_date: current doc, accessed=2026-09-21, confidence: high, class: practice}
- {claim: Rails has built-in `X-Request-ID` support (generates a UUID per request if client doesn't supply one; `config.log_tags = [:request_id]`), widely mirrored in Node (express-request-id), Django, Java, PHP., source: Heroku Dev Center (above) + search summary, publisher: Heroku/framework docs, accessed=2026-09-21, confidence: medium, class: practice}
- {claim: Platform-native variants: AWS `X-Amzn-Trace-Id` (X-Ray, format `Root=1-{8hex-timestamp}-{24hex-id};Parent=...;Sampled=...`, injected by ALB/API Gateway); Vercel `x-vercel-id` (region-encoded, `iad1::node-timestamp-hash`, also a loop guard); Envoy `x-request-id` used natively for tracing/logging plus `x-client-trace-id`., source: https://docs.aws.amazon.com/elasticloadbalancing/latest/application/load-balancer-request-tracing.html, https://vercel.com/docs/headers/request-headers, publisher: AWS / Vercel, accessed=2026-09-21, confidence: high, class: practice}
- {claim: W3C Trace Context Recommendation published 23 Nov 2021. Format: `traceparent: {version}-{trace-id}-{parent-id}-{trace-flags}`, all lowercase hex: version `00`, trace-id 32 hex (16 bytes, not all-zero), parent-id 16 hex, trace-flags 2 hex (only `sampled` bit defined in v00). Example: `00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01`. Unparseable header → ignored, trace restarted., source: https://www.w3.org/TR/trace-context/, publisher: W3C, pub_date: 2021-11-23, accessed=2026-09-21, confidence: high, class: standard}
- {claim: The spec explicitly permits non-tracing participation: minimum compliance is MUST-propagate even without collecting trace data, and pass-through "may also be implemented in a service which currently does not collect distributed tracing information" — a Node backend can accept/forward `traceparent` without a full tracing stack., source: https://www.w3.org/TR/trace-context/, publisher: W3C, accessed=2026-09-21, confidence: high, class: standard}
- {claim: No dedicated IETF RFC or draft defines a request-id/correlation-id HTTP header. Closest IETF HTTPAPI artifact is the (expired Oct 2025) Idempotency-Key draft; RFC 8941 is Structured Field Values (unrelated)., source: https://datatracker.ietf.org/doc/draft-ietf-httpapi-idempotency-key-header/ and https://datatracker.ietf.org/group/httpapi/documents/, publisher: IETF, accessed=2026-09-21, confidence: high, class: standard}
- {claim: RFC 6648 (BCP 178, June 2012) says new parameters "SHOULD NOT prefix with 'X-'" but makes no migration recommendation — `X-Request-Id` is deprecated-by-style, not deprecated-in-fact; bare names (`Request-Id`, `Correlation-ID`) are the RFC-clean spellings., source: https://www.rfc-editor.org/rfc/rfc6648, publisher: IETF, pub_date: 2012-06, accessed=2026-09-21, confidence: high, class: standard}
- {claim: Microsoft's own spec (`x-ms-request-id`) requires every response to carry a unique, non-deterministic request ID logged as a searchable field for support; Azure Monitor documents legacy support for `Request-Id`/`X-Request-Id` alongside W3C `traceparent`., source: https://microsoft.github.io/openspecs/Open_API_Working_Group/httprequestids/1-introduction, https://learn.microsoft.com/en-us/azure/azure-monitor/app/telemetry-correlation, publisher: Microsoft, accessed=2026-09-21, confidence: high, class: standard}
- {claim: OpenTelemetry's default propagator is W3C TraceContext (`traceparent`+`tracestate`); practitioner consensus is to run both: trace ID for latency/debugging (traces retained ~7–30 days), a separate business/correlation ID for support workflows and retention beyond trace storage, joined by injecting trace-id into log lines; business context can ride in W3C `baggage` (RFC 9552)., source: https://github.com/open-telemetry/opentelemetry.io/blob/main/content/en/docs/concepts/context-propagation/index.md, https://last9.io/blog/correlation-id-vs-trace-id/, https://codelit.io/blog/distributed-tracing-context-propagation, publisher: OpenTelemetry docs + practitioner blogs, accessed=2026-09-21, confidence: medium, class: practice}

## Contradictions

- Last9/Mytheon say prefer W3C Trace Context over house headers; Codelit says keep a separate business correlation ID and reuse the trace ID only for log linking. Not a true contradiction — they split "debug correlation" (trace-id) from "business/support correlation" (separate ID); the mobile-app support-key use case is the latter.

## Leads worth chasing

- `traceparent` IANA registration entry verification.
- W3C Trace Context Level 2 draft (256-bit IDs).
- Microsoft's `X-Correlation-Status` response-header echo pattern.

## Could not find

- Any official RFC or IETF draft standardizing `Request-Id`/`Correlation-ID` as a header — confirmed absent.
- No evidence of any vendor declaring `X-Request-Id` deprecated-in-fact; Heroku, Rails, Envoy, ASP.NET all still ship it.

## Practical read

A client-supplied `X-Request-ID`/`X-Correlation-ID` (UUID) echoed back in the response is the established, low-risk convention for app-to-support correlation; `traceparent` is the standards-track option that doubles as future OTel enablement; the two are complementary, not competing.