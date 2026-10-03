# Research: industry patterns for server-driven app config (2026-10-04)

Owner asked what pattern people follow and what the best way is. Findings below; links are the sources.

## The pattern the owner described has a name

"FE initializes with defaults, overrides when the response arrives" is exactly the **remote config** pattern, canonically [Firebase Remote Config](https://levelup.gitconnected.com): set **in-app defaults** → **fetch** from the server → **activate** atomically → cache last-known-good locally → refetch on a minimum interval. [Practitioner guides](https://resources.tarmac.io) all stress: defaults so the app works offline/pre-fetch, and activation as a separate atomic step so a partial fetch never half-applies. Feature-flag platforms (LaunchDarkly, Statsig) use the same shape: mobile SDKs [bootstrap from local storage](https://github.com/launchdarkly/react-native-client-sdk) so evaluations work before/without the first network connection, then refresh by polling or streaming.

## What we adopt vs reject

| Pattern | Verdict | Why |
| --- | --- | --- |
| Defaults-in-binary + fetch + activate + last-known-good cache | **Adopt** | Industry standard; exactly the owner's ask; fail-open by construction |
| Pull on app start + foreground with a min-interval TTL | **Adopt** | Firebase/LD default behavior; no push infrastructure needed |
| Server-driven UI (Shopify Shop, Yelp, DoorDash send layout/component JSON) | **Reject for v1** | [SDUI architectures](https://shopify.engineering) are a full rendering contract — heavy on both ends, big regression surface. Fenzit needs values and flags, not layouts ([2026 SDUI overview](https://www.weweb.io)) |
| Feature-flag SDK / hosted vendor (LaunchDarkly, Firebase) | **Reject as a dependency** | The BE already owns auth/tenancy; a Supabase table + one endpoint is ~a day of work and no vendor coupling. Keep the *pattern*, skip the *product* |
| Per-user/context targeting with percentage rollouts and A/B | **Defer** | Valuable at scale; v1 needs only platform/app-version branching ([LD context attributes](https://www.vantageos.tech) show where this goes later) |
| Streaming/push config updates | **Defer** | Pull-on-start/foreground covers every key we have; streaming adds a socket for near-zero benefit at this cadence |

## Endpoint design best practice

- One small versioned JSON document per app (`GET /api/v1/config/app`), flat typed key-values + a `config_version`; clients **ignore unknown keys** so the server can add keys without breaking old binaries ([schema-versioning guidance](https://www.digia.tech)).
- `ETag` + `If-None-Match` → 304, and short-lived `Cache-Control` so a CDN/edge (our CF worker) serves repeats — a config read should be the cheapest request in the app, not one more Oregon↔Mumbai round trip on boot.
- Fetch with a **short dedicated timeout** and treat every failure as "keep what you had" — config is an optimization, never a boot dependency.
- Never put secrets in the payload: the client is untrusted and the endpoint is typically pre-login/public.
- Kill-switch flags must default to **current shipped behavior** when the server is unreachable — a flag that fails "off" is a remote outage waiting to happen.

## Client metadata headers

Mobile APIs commonly carry app version / platform / OS version / device model as custom request headers for analytics, forced-upgrade, and targeting ([pattern survey](https://www.alibabacloud.com); header-versioning write-ups: [DZone](https://dzone.com), [Pluralsight](https://www.pluralsight.com)). Conventions worth honoring:

- `X-`-prefixed names are ubiquitous in the wild but deprecated for *new* registry names per RFC 6648 — `X-App-Version` remains the de-facto standard and is what our own `X-Correlation-ID` / `X-Session-ID` already use, so we stay consistent.
- Values must be compact and machine-parsable (semver for versions, fixed enums for platform).
- **No persistent device identifiers** (IMEI/ODIN/advertising ID) in headers — privacy policy and Play Store policy risk for zero operational gain at our scale.
- Servers must tolerate their absence: older binaries, curl probes, and internal calls send no metadata headers and must never be rejected.

Full proposed catalog with FE value sources: [client-metadata-headers.md](client-metadata-headers.md).
