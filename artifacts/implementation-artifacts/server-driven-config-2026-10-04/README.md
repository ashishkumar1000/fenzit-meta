# Server-driven config — implementation record (2026-10-04)

Feature: BE config API + FE defaults-then-override + client metadata headers + CF edge caching.
Spec contract: `artifacts/specs/spec-server-driven-config/` (CAP-1..6). This file records what shipped and how it was proven.

## Shipped

| Piece | Commit | Notes |
| --- | --- | --- |
| BE config API | fenzit-be `7761184` | `app_config` table (RLS on, no policies), `@Public` GET `/api/v1/config/app` (ETag + Cache-Control), in-memory cache invalidated by Supabase Realtime + 60s TTL fallback, access log gains app/platform/OS/model |
| BE review patches | fenzit-be `2677849` | P2: `updated_at` trigger (configVersion change-detector now works for plain SQL edits); P3: publication alter idempotent |
| FE remote config | fenzo-app `1edbbde` | remoteConfig service (defaults → MMKV last-known-good → throttled overlay), X-App-* headers via device-info 15.0.2, server-driven clamped timeout, forced-update gate + maintenance banner (theme tokens) |
| FE review patches | fenzo-app `f956724` | fail-open device-info accessors (boot can't be bricked by a native-module gap — caught live), failed fetch no longer holds the retry throttle, App suites pin fetch |
| CF edge cache | worker (CF account) | Cache API, bare-URL key, Authorization stripped, 60s TTL, `x-cache` header; dormant until endpoint existed, now live |

## How it was proven (strict pass)

- **BE**: 98 suites / 1,532 unit tests green; e2e 414 passed with **exactly the 26 documented pre-existing** date-fixture failures (zero new); local probe (payload, ETag, 3ms cached read); prod probe (200, `x-cache` HIT); DB edit → public URL in ~1s (≤60s worst case in a just-cached colo — demonstrated on the phone).
- **FE**: 237 suites / 2,993 tests green (post-patch), tsc clean; new suites cover merge semantics, unknown-key/type tolerance, fail-open, throttle-retry, gate/banner render, version compare.
- **Device (Pixel 6, shots in `shots/`)**: d1 clean boot as Ayush → d2/d3 DB-inserted banner appears on cold start (worst-case edge staleness hit first, then live) → d4 raised `min_supported_version` flips the app to the full-screen forced-update gate (banner correctly hidden) → d5 clean recovery after reset → d6 final patched APK installed (phone runs `f956724`).
- **Production left safe**: `maintenance_banner=''`, `min_supported_version='1.0.0'` (trigger verified live via fresh `updated_at`).

## Incidents / lessons

1. **First APK crashed at boot** (`RNDeviceInfo is null`): the Gradle **configuration cache** replayed the pre-install autolinking manifest, silently excluding the new native module. Fix: purge `android/build/generated/autolinking` + `android/.gradle/configuration-cache`, build with `--no-configuration-cache`. Hardening: all device-info access now goes through safe accessors that degrade to `package.json` fallbacks.
2. **BMAD review verdict FIX-FIRST** — triaged per the standing rule: 2×P2 verified real and patched (both prod/device-verified), 2×P3 patched, 1×P3 (in-flight cache-miss dedup) deferred as documented.

## Deferred (recorded in spec)

In-flight cache-miss dedup; CF purge API for instant propagation; per-platform targeting (edge cache key must grow targeting attributes when it lands).
