# Review — Tech Currency / Reality Check

- **Target:** `ARCHITECTURE-SPINE.md` (Attendance & Leave, 2026-09-25)
- **Lens:** every committed decision is web-researched or checked against the repos, not taken from memory. Current versions, the named tech still exists and fits.
- **Date of check:** 2026-09-25
- **Evidence used:** npm registry (live `curl`), GitHub releases/issues, Supabase docs, PostgreSQL docs, Apple docs/forums, plus the installed `node_modules`, `bun.lock`, `Podfile`, `gradle.properties` and `supabase/migrations` in both repos.

## Verdict

The stack is mostly current and fits: every named library exists, the maps/netinfo versions are the latest ones, and the Supabase features are the ones already used in production. But one committed SQL rule (AD-7's CHECK against `pg_timezone_names`) cannot be built as written. The Stack table also lists floors, not what actually ships. And three client-side assumptions (geolocation options, iOS mock detection, react-native-maps on RN 0.87) need small spec corrections before stories are cut.

## Findings (by severity)

### F1 — HIGH — AD-7: "CHECK against `pg_timezone_names`" cannot be built

- Postgres rejects subqueries in CHECK (`cannot use subquery in check constraint`). The docs also say a CHECK must not reference data other than the row being checked, and must be immutable. `pg_timezone_names` is a view over the OS/tzdata files, and tzdata changes between Postgres minor versions. So even an `IMMUTABLE` wrapper function is a false promise. The docs warn this can make a dump/restore fail.
- Another common trick is CHECK (`now() AT TIME ZONE tz IS NOT NULL`) inside an IMMUTABLE wrapper. It has the same problem, and it is also too loose: `AT TIME ZONE` accepts POSIX strings like `'+05:30'` or `'UTC+5'`, where the sign is inverted. That is exactly the offset bug AD-7 is meant to prevent.
- **Fix:** replace the CHECK with a `BEFORE INSERT OR UPDATE OF timezone` trigger on `tenants`: `IF NOT EXISTS (SELECT 1 FROM pg_timezone_names WHERE name = NEW.timezone) THEN RAISE ... USING ERRCODE = 'PT422'`. Optionally also allow only region names (`name LIKE '%/%' OR name = 'UTC'`) so `Factory`, `posixrules` and `EST5EDT` are rejected. Mirror the check as a DTO allowlist. The spine should say "validated by trigger", not "CHECK".
- Source: https://www.postgresql.org/docs/current/ddl-constraints.html (CHECK section: "does not support CHECK constraints that reference table data other than the new or updated row"; "assumes that CHECK constraints' conditions are immutable").

### F2 — HIGH — AD-20: nitro-geolocation option names are stale, iOS "mocked" is weaker than implied, and the default timeout is 10 minutes

Checked in `fenzo-app/node_modules/react-native-nitro-geolocation@1.4.3`:

- `mocked` and `provider` exist on the modern `GeolocationResponse` (`src/types.ts`).
  - Android: `Location.isMock` on API 31+, else `isFromMockProvider` (`LocationMetadata.kt`). **Confirmed.**
  - iOS: `sourceInformation?.isSimulatedBySoftware` when iOS ≥ 15, else `nil` (`CLLocation+GeolocationMetadata.swift`). **Confirmed.** The RN 0.87 floor is iOS 15.1, so the API is always there.
  - iOS `provider` is hard-coded to `"unknown"`.
- `sourceInformation` can be `nil`, so `mocked` can be `undefined`, not `false`. Apple sets `isSimulatedBySoftware` only for Core Location's own simulation (Xcode GPX). Third-party spoofing tools are **not** flagged (Apple forum thread 803179). `isProducedByAccessory` (external GPS dongles) is not exposed by the library.
- "High accuracy": `enableHighAccuracy` is `@deprecated since v1.2` in 1.4.3 and **removed from the modern API in 2.0.0**. The latest is 2.0.2, published 2026-09-13; 1.4.3 is now one major behind. Use `accuracy: { android: 'high', ios: 'best' }` (or `'bestForNavigation'`).
- `maximumAge` is supported and its default is already `0`. `timeout` defaults to **600000 ms (10 min)**, so the spine's "and a timeout" must name a value. The job helper uses 15000.
- **Fix:** in AD-20:
  - name the options (`accuracy` presets, `maximumAge: 0`, `timeout: 15000`);
  - send `mocked: boolean | null` (null = unknown) and `provider` as reported (`"unknown"` on iOS);
  - have the server treat `null` as "not detected", never as proof of a real fix;
  - add one line to the spine or PRD: "mock detection is best-effort; iOS catches only Xcode simulation, Android only mock-location apps";
  - build on the 2.x API names now (string error discriminants, `accuracy`), so the later 1.4 → 2.0 upgrade does not touch attendance. Or pin 1.4.3 on purpose and record why.
- Sources: https://github.com/jingjing2222/react-native-nitro-geolocation/releases (2.0.0 breaking changes), https://www.npmjs.com/package/react-native-nitro-geolocation (latest 2.0.2), https://developer.apple.com/documentation/corelocation/cllocationsourceinformation/issimulatedbysoftware, https://developer.apple.com/forums/thread/803179

### F3 — MEDIUM — react-native-maps 1.29.8: right version, fits Fabric, not tested upstream on RN 0.87. The "spike first" note is correct but needs concrete exit criteria

- 1.29.8 is `latest` (published 2026-09-20). The `beta` tag is 2.0.0-beta.15 (do not use).
- The README compatibility table says new architecture (Fabric) is supported from **1.26.1+ with RN ≥ 0.81.1**.
- Peer range is `react-native >= 0.76`, but the library's own devDependency is `react-native ^0.83.10`, so RN 0.87 is not in its own CI.
- There is field evidence on RN 0.87.1 + Fabric: issue #5987 reports a real app on maps 1.29.0 / RN 0.87.1 (Android, Google). So it builds and runs.
- The podspec platform is iOS 15.1, which matches the Podfile. Android pulls `play-services-location 21.3.0`, the same version as nitro-geolocation, so there is no clash.
- `MapCircle` has a Fabric codegen spec (`src/specs/NativeComponentCircle.ts`). `Marker` has `draggable` and `onDragEnd`.
- Open issues that matter for the office pin picker:
  - #5987 — Android Fabric crash (`ReactViewGroup cannot be cast to MapMarker`) when markers with **custom child views** mount and unmount. Fix PR #5989 is not merged.
  - #6002 — iOS Apple Maps on Fabric: Marker `onPress` `position` is always `{0,0}`. Coordinates are OK, and `MapView.onPress` / `onDragEnd` are not affected.
  - #5994 — Android: drag starts only after a long press.
  - #6007 — Android: taps delayed by the double-tap timeout.
  - #5929 (fixed in 1.29.7) — the iOS polygon path was not rebuilt. Circle `center`/`radius` updates were not confirmed either way.
- **Fix:** in the Stack row and the FR-5 story, define the spike's pass criteria:
  - a default-pin `Marker` (no custom child view, because of #5987) that is draggable, and whose `onDragEnd` updates the pin;
  - a `Circle` whose `radius` and `center` re-render live as the slider moves, on both iOS Apple Maps and Android Google;
  - `MapView.onPress` to move the pin.
  - The UX copy should say "press and hold to drag" (#5994), or the picker should use tap-to-place as the main interaction.
  - Name the fallback if Circle does not update: re-key the Circle on change.
- Sources: https://github.com/react-native-maps/react-native-maps (README compatibility table), https://github.com/react-native-maps/react-native-maps/releases, https://github.com/react-native-maps/react-native-maps/issues/5987, https://github.com/react-native-maps/react-native-maps/issues/6002, https://github.com/react-native-maps/react-native-maps/issues/5994, https://github.com/react-native-maps/react-native-maps/issues/5929

### F4 — MEDIUM — Stack table versions are floors, not what ships. The backend lockfile is gitignored

- `fenzit-be/.gitignore:35` ignores `bun.lock`, and the Dockerfile says "no bun.lock in the repo — deps resolve fresh at build time". So Render installs whatever `^` resolves to on build day.
- What is installed today (local `node_modules` / `bun.lock`) compared with the spine:

| Package | Spine | package.json | Resolved today | npm latest |
| --- | --- | --- | --- | --- |
| Bun | 1.4.0 | `bun@1.4.0`, image `oven/bun:1.4.0` | 1.4.0 | 1.4.2 |
| @nestjs/core | 11.x | ^11.0.1 | 11.2.5 | **12.1.0** (12.0.0 published 2026-08-27) |
| @nestjs/platform-fastify | 11.1.27 | ^11.1.27 | 11.2.5 | 12.1.0 |
| fastify | 5.8.5 | ^5.8.5 | 5.12.5 (platform-fastify nests its own 5.11.3) | 5.12.5 |
| @supabase/supabase-js (be) | 2.108.2 | ^2.108.2 | **2.116.0** | 2.117.1 |
| @supabase/supabase-js (app) | 2.116.0 | ^2.116.0 | 2.116.0 | 2.117.1 |
| Jest (be / app) | 30 | ^30 / **^29.6.3** | 30.5.2 / 29.x | 30.5.2 |
| React Native / React | 0.87.1 / 19.2.3 | same | same | 0.87.1 |
| netinfo | 12.0.1 | — (new) | — | 12.0.1 |
| react-native-maps | 1.29.8 | — (new) | — | 1.29.8 |
| nitro-geolocation | 1.4.3 | ^1.4.3 | 1.4.3 | **2.0.2** |

- Side note (existing, not caused by the spine): `@nestjs/platform-fastify@11.2.5` declares the peer `@fastify/static ^10.1.2`, but the repo has `^9.1.3`.
- **Fix:**
  - Relabel the Stack column "Version (floor, `^` range)" and put the resolved versions next to them.
  - Say NestJS stays on 11.x on purpose: 12 is out, and attendance must not ride a major upgrade.
  - Say the "Jest 30" convention is backend only (fenzo-app is on Jest 29).
  - Separately, raise committing `bun.lock` in fenzit-be as a deferred-work item. The CLAUDE.md rule says "each repo keeps its own bun.lock", and today it is not tracked.
- Sources: live `https://registry.npmjs.org/<pkg>/latest`, `fenzit-be/package.json`, `fenzit-be/bun.lock`, `fenzit-be/Dockerfile`, `fenzo-app/package.json`.

### F5 — MEDIUM — AD-14 pg_cron: every 5 min is fine, but `cron.job_run_details` is never pruned, and AD-13/AD-18 depend on the legacy Supabase keys and JWT secret, which are being retired

- pg_cron on Supabase supports down to every second (`'[1-59] seconds'` syntax). Supabase recommends ≤ 8 concurrent jobs and ≤ 10 minutes per run. So 5 minutes is fine, and after this job the project has 3 jobs.
- `cron.job_run_details` is **not cleaned automatically**. A 5-minute job adds 288 rows a day. No existing migration prunes it (grep of `supabase/migrations`).
- pg_cron runs in GMT unless `cron.timezone` is set. That is fine here, because AD-14 evaluates the tenant timezone inside the function. State this so nobody "fixes" the schedule to IST.
- Supabase docs: "deprecating the `anon` and `service_role` keys by the end of 2026". The legacy HS256 JWT secret is "no longer recommended".
  - fenzit-be uses `SUPABASE_SERVICE_ROLE_KEY` for `createAdmin()` (AD-3) and `SUPABASE_JWT_SECRET` to mint realtime tokens (`auth.service.ts`, which AD-18 extends to technicians).
  - The new `sb_secret_*` keys still map to the `service_role` Postgres role, so AD-3's grant/revoke design survives.
  - The custom HS256 realtime token does **not** survive if the legacy secret is revoked.
- **Fix:**
  - Add to AD-14: "the reminders migration also schedules a daily `DELETE FROM cron.job_run_details WHERE end_time < now() - interval '7 days'`" (or leave this to the Deferred NFR-9 decision, but name it).
  - Add a Deferred item: "move `createAdmin` to `sb_secret_*` and move realtime-token minting to asymmetric JWT signing keys before the legacy secret is revoked (end of 2026)". Mark AD-18 as depending on it.
- Sources: https://supabase.com/docs/guides/cron, https://github.com/citusdata/pg_cron, https://supabase.com/docs/guides/api/api-keys, https://supabase.com/docs/guides/auth/signing-keys

### F6 — LOW — @react-native-community/netinfo 12.0.1: current, new-arch ready, not confirmed on RN 0.87

- 12.0.1 is `latest` (2026-02-14, no release since). New-architecture (TurboModule) support has been there since 11.5.0. 12.0.0 raised the floor to iOS 14 / RN 0.76 (it moved to `NEHotspotNetwork`, and 12.0.1 links NetworkExtension). The peer range is `react-native >= 0.59`. No RN 0.86/0.87 issue was found, and no statement of support for it either.
- By default `isInternetReachable` pings a Google endpoint. On office Wi-Fi with captive portals or blocked hosts, that can wrongly report "offline" and block check-in.
- **Fix:** gate check-in/out on `isConnected === false` only. Set `NetInfo.configure({ reachabilityUrl: <API>/api/v1/health })` if reachability is used. Still treat a request timeout as the real offline signal. Add a one-line smoke test on RN 0.87 in the maps spike build.
- Sources: https://github.com/react-native-netinfo/react-native-netinfo/releases, https://www.npmjs.com/package/@react-native-community/netinfo

### F7 — LOW — Postgres items: confirmed, with small wording fixes

- **Postgres version:** new Supabase projects run Postgres 17, and PG14 support ended on 2026-07-01. The fenzit-be repo has no `supabase/config.toml`, so the project's major version is not recorded. Every feature below works on PG15 and PG17. Record the result of `SELECT version()` in the first migration story.
- **btree_gist:** listed as a supported Supabase extension. It supports `uuid WITH =`, so `EXCLUDE USING gist (employee_id WITH =, valid WITH &&)` is valid. Enable it with the repo's pattern: `CREATE EXTENSION IF NOT EXISTS btree_gist WITH SCHEMA extensions`. Because `extensions` is not on the function `search_path = public`, the operator class must be resolvable at DDL time. Either create the constraint in a migration whose session search_path includes `extensions` (the Supabase default does), or write `gist_uuid_ops` with its schema. A test in the integration spec should prove an overlapping insert fails.
- **`pg_advisory_xact_lock(hashtextextended(text, 0))`:** `hashtextextended` (PG11+) returns `bigint`, which matches the one-argument lock. It is an internal function, not documented in the manual, but it is stable within a running cluster, and that is all a transaction-scoped lock needs. The lock is transaction-scoped, so it is safe with PostgREST RPCs and the Supavisor transaction pooler. No change needed. Add "xact-scoped only, never session locks (pooler)" to AD-5.
- **Partial unique index + `ON CONFLICT DO NOTHING` (AD-13):** a bare `ON CONFLICT DO NOTHING` works. If a conflict target is written, it must repeat the index predicate (`ON CONFLICT (dedupe_key) WHERE dedupe_key IS NOT NULL`).
- Sources: https://supabase.com/docs/guides/database/extensions, https://www.postgresql.org/docs/current/btree-gist.html, https://www.postgresql.org/docs/current/functions-admin.html, https://supabase.com/changelog/45827-deprecation-notice-support-for-postgres-14-ending-on-1st-july-2026

### F8 — OK — Supabase Realtime `broadcast_changes` + private channels is current

- The Supabase Broadcast docs still document `realtime.broadcast_changes()` for trigger-driven changes (`realtime.send()` is for arbitrary payloads). Private channels need `config: { private: true }` plus RLS on `realtime.messages`. Public and private must match.
- This is exactly what production already uses (`20260909000002_notifications_table.sql` trigger + `notifications_topic_recipient_only` policy; `fenzo-app/src/services/supabaseRealtime.ts` with `private: true`). The existing policy is keyed on `sub` for `user:%:notifications`, so it already covers technician topics once AD-18 opens the token. No new realtime tech is being introduced.
- Source: https://supabase.com/docs/guides/realtime/broadcast

## Confirmed without change

- iOS min 15.1 (Podfile) meets react-native-maps (15.1), netinfo 12 (14) and `isSimulatedBySoftware` (15).
- `newArchEnabled=true` and Hermes in `android/gradle.properties`; minSdk 24 and compile/target 36 are above what all three native libraries need.
- Apple Maps (MapKit) needs no API key. Google Maps Android needs a key restricted to SHA-1, as the spine says.
- Bun 1.4.0 matches `packageManager` and the Docker base image. Note that fenzo-app declares `bun@1.3.13`, so the Stack row should say "(be)".
