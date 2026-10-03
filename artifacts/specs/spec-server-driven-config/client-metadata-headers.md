# Companion: client metadata headers (CAP-3, CAP-5)

Every `apiClient` request carries these, added by one request interceptor next to the existing `X-Correlation-ID` / `X-Session-ID` one. BE logs them per request (correlation logger) and may read them for config resolution. Absence is always acceptable.

## Catalog

| Header | Value | FE source (no new native dep) | BE use |
| --- | --- | --- | --- |
| `X-App-Version` | semver, e.g. `1.0.0` | `package.json` `version` read at build time (JSON import or generated constant; `scripts/sync-version.js` already keeps native `versionName` in sync from this same source) | log/triage, min-version gate, per-version targeting |
| `X-App-Build` | integer versionCode | native build number from the same sync script's formula — only if cheaply reachable in JS; optional in v1 | distinguishing rebuilds of one semver |
| `X-Platform` | `ios` \| `android` | `Platform.OS` (core RN) | platform targeting (CAP-5) |
| `X-OS-Version` | OS version string | `Platform.Version` (core RN) | triage (OS-specific defects) |
| `X-Device-Model` | e.g. `Pixel 6` | **not available without a new native dep** — deferred (open question) | nice-to-have triage only |

## Rules

- Additive only: BE never rejects a request for missing/unknown metadata headers.
- No persistent device identifiers, ever (privacy + Play policy).
- Values are informational, not auth inputs — they may *target* config but never *grant* anything.
- The metadata interceptor sits beside (not inside) the correlation interceptor; neither reads the other's headers, so registration order stays non-load-bearing, matching the existing apiClient design comment.
