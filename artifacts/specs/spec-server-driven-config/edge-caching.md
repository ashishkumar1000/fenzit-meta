# Companion: edge caching of the config endpoint (CAP-6)

**Deployed 2026-10-03** in the `fenzit-api-proxy` Cloudflare worker (production, dormant until the backend ships the endpoint). The worker has no local git repo — it lives in the CF account and is deployed via the API; the pre-cache version is preserved at `/tmp/fenzit-worker/orig-worker.js` (and derivable from CF's script history).

## Mechanism

`GET /api/v1/config/app` is served through the **Cache API** (`caches.default`) inside the worker:

1. Cache key = the bare URL (`origin + path`); query string excluded.
2. On hit → response returned from the colo's cache, `x-cache: HIT`.
3. On miss → fetch Render (Authorization header stripped), return with `x-cache: MISS`; if status 200, store into the cache with `Cache-Control: public, max-age=60` (worker-owned TTL, `CONFIG_EDGE_TTL_SECONDS`) via `ctx.waitUntil(cache.put(...))`.

Everything else (all methods, all other paths) is byte-for-byte the original passthrough.

## Gotchas baked into the design (from CF docs, 2026-10)

- **Authorization bypass**: Cloudflare's cache automatically bypasses responses to `Authorization`-bearing requests. The app attaches its bearer token to *every* request via the apiClient interceptor — so the cached path strips the header (the endpoint is `@Public()`; nothing needs it). Without this, the cache would simply never fill.
- **Cache API is per-colo**: entries don't replicate across data centers. Fine — users cluster by region (India → Mumbai/Chennai colo), and a cold colo just pays one origin fetch.
- **No request collapsing**: a burst of cold misses invokes the worker once per request; each may hit Render. Harmless for a ~1KB payload; Workers Caching (below) collapses if we ever care.
- **`put()` respects `Cache-Control`, `ETag`, `Expires`, `Last-Modified`; responses with `Set-Cookie` are never cached** — the BE must not send Set-Cookie on the config route (Nest won't by default).
- **`match()` evaluates `If-None-Match` against the stored ETag** — if the BE later adds its ETag, edge-side 304s come free.
- Only **200s** are cached; BE 404/500s pass through uncached, so a broken endpoint never gets pinned at the edge.
- The CF zone's default cache rules do **not** apply to worker responses — the worker's headers are the whole configuration surface.

## Tuning knobs

- **TTL**: `CONFIG_EDGE_TTL_SECONDS = 60` — one constant in the worker. An owner config edit propagates to all clients within ≤60s. Lower it if a key (e.g. `min_supported_version`) ever needs faster propagation; raise it to cut origin fetches further.
- **Instant purge** (deferred): CF API `DELETE /zones/:id/purge_cache` or Cache-Tag purge from the BE on config write, if 60s staleness ever becomes a problem.
- **Workers Caching** (newer CF feature, `wrangler [cache]`): skips the worker entirely on hits and adds request collapsing + tiered caching. Requires a redeploy config change; revisit if config traffic grows.

## Verification

```bash
curl -sD - -o /dev/null https://api.fenzit.com/api/v1/config/app | grep -i x-cache
# MISS (cold) → HIT (within 60s) → MISS again after TTL expiry
```

Post-deploy smoke (2026-10-03T20:45Z): health via CF 200 @ 0.63s; config/app origin-404 passthrough with `x-cache: MISS`; POST `auth/otp/send` body round-trip 200 with fresh `otp_session_id` — no behavioral change to existing traffic.
