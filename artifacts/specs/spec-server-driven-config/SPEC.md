---
id: SPEC-server-driven-config
companions:
  - research-patterns.md
  - client-metadata-headers.md
  - edge-caching.md
sources: []
---

> **Canonical contract.** This SPEC and the files in `companions:` are the complete, preservation-validated contract for what to build, test, and validate.

# Server-Driven App Configuration

## Why

**A pain to solve, plus an opportunity.** Every behavior change in fenzit-app today ships as a binary: the installed base (sideloaded APKs on owner/technician phones) only picks up fixes, tuning, and feature toggles when someone rebuilds, re-signs, and reinstalls — proven painful by the API_TIMEOUT 15s→30s change (2026-10-04), which is coded but unreachable on devices until the next APK. Meanwhile the backend cannot see *which* client is asking (version, platform, OS) on any request, so it can neither triage field issues nor vary behavior per client. A server-driven config — FE boots on shipped defaults and overrides them from a fetched payload, with the client sending app/device metadata headers — removes the binary round-trip for safe changes and gives the server the client attributes it needs.

## Capabilities

- **CAP-1 — Runtime config pickup**
  - **intent:** The app picks up operational and feature configuration from the backend at runtime, so behavior changes ship without an app release.
  - **success:** Changing a value in `app_config` is reflected in an installed app on its next launch or foreground, with no app update.
- **CAP-2 — Defaults-first boot, never blocked**
  - **intent:** The app boots instantly on shipped defaults and overlays the best-known server config, so config never delays or breaks startup.
  - **success:** A fresh install in airplane mode is fully functional on defaults; after one successful fetch, a kill + offline relaunch runs with the persisted server values, not defaults.
- **CAP-3 — Client metadata on every request**
  - **intent:** Every API request carries app/platform metadata headers so the server can log, triage, and target by client attributes.
  - **success:** Any fenzit-be request log line identifies app version, platform, and OS version; config resolution can branch on these attributes.
- **CAP-4 — Minimum-supported-version gate**
  - **intent:** The server can flag an unsupported app version (minimum supported version + update copy) so field clients update before breaking API changes.
  - **success:** Setting a min version above an installed app's version in `app_config` triggers the in-app update UX on that device without shipping anything.
- **CAP-5 — Attribute targeting of values**
  - **intent:** Config values can resolve differently per client platform and app version (targeting via the metadata headers).
  - **success:** The same endpoint returns platform-appropriate values when clients with different platforms or app versions ask.
- **CAP-6 — Edge-cached delivery**
  - **intent:** Config reads are served from the Cloudflare edge, so a config fetch costs an edge lookup instead of a Render + cross-region-DB round trip.
  - **success:** Two back-to-back GETs of `/api/v1/config/app` within the TTL — the second returns `x-cache: HIT` with Render never contacted (Render sees only the first); TTL expiry re-fetches from origin.

## Constraints

- No secrets or PII in the config payload; no persistent device identifiers in headers (Play policy + privacy).
- API base URL bootstrap stays compile-time — config cannot relocate the server the config itself is fetched from.
- Fail-open: the config fetch uses a short dedicated timeout and never blocks boot; any failure keeps last-known-good or defaults.
- Forward compatibility: clients ignore unknown config keys; the server only adds keys and never repurposes existing ones (sideloaded old clients must keep working).
- bun only; headers are implemented at the single FE choke point (apiClient request interceptor); config serving is owned by a new BE config module.
- Every shipped default equals today's current behavior — a key used as a kill switch must fail safe to current behavior when config is unavailable.
- The config endpoint stays parameterless while the payload is identical for everyone; when attribute targeting (CAP-5) lands, the edge cache key must grow the targeting attributes with it, or clients get cross-partition values.
- Staleness bound: an owner config edit reaches all clients within the edge TTL (60s); instant purge is deferred until a key needs faster propagation.

## Non-goals

- No server-driven UI — the payload carries values/flags only, never layout or component trees.
- No A/B experiments, percentage rollouts, or per-user/per-tenant targeting in v1.
- No realtime push of config changes (WebSocket/streaming) — pull on app start and foreground only.
- No admin UI in v1 — config is edited via SQL / Supabase dashboard.

## Success signal

An owner edits one value in the `app_config` table and, without shipping any binary, an installed app picks up the new behavior on its next launch or foreground — while a fresh install with no network still runs fully on shipped defaults, and every request the app ever made identifies its app version/platform/OS in the server logs.

## Assumptions

- MMKV (already a dependency) persists last-known-good config; no new native dependency ships in v1 (hence the device-model header is deferred).
- App version source of truth is `package.json` (`sync:version` keeps native files in sync); the JS bundle reads it at build time via JSON import or a generated constant.

## Open Questions

- Confirm the v1 key set: `min_supported_version` (with update copy), `api_timeout_ms`, feature flags (which ones?), maintenance banner — anything else?
- Should the config endpoint be public pre-login (assumed yes) or JWT-required?
- Is the device-model header worth adding `react-native-device-info` now, or stay dependency-free in v1?

## Design anchors (non-prescriptive)

Implementation HOW lives with downstream skills; the load-bearing shape agreed during distillation: `GET /api/v1/config/app` is `@Public()` (pre-login), backed by a Supabase `app_config` (key/value jsonb) table served through a short in-memory BE cache. Edge caching of the endpoint is **already deployed** in the CF worker (Cache API, bare-URL key, 60s worker-owned TTL — mechanism and gotchas in [edge-caching.md](edge-caching.md)), so the BE endpoint only needs to exist and return 200. Header catalog and value sources: [client-metadata-headers.md](client-metadata-headers.md). Pattern research and the SDUI rejection: [research-patterns.md](research-patterns.md).
