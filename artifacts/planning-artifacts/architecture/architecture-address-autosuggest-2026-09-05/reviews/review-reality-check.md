---
title: 'Reality-check review — Address Autosuggest architecture spine'
type: review
lens: 'reality-check (web-researched vs. asserted-from-training-data)'
target: 'artifacts/planning-artifacts/architecture/architecture-address-autosuggest-2026-09-05/ARCHITECTURE-SPINE.md'
created: '2026-09-05'
status: complete
---

# Reality-Check Review — Address Autosuggest Architecture Spine

## Verdict

Every load-bearing technology/version claim in the spine checks out against live sources or the actual repo — no invented API, no dead/wrong version — with one imprecision inherited from the companion research (the `id` field's SKU label) that should be corrected in the record, and one pre-existing "not yet runtime-verified" assumption (AD-8) that the spine itself already flags honestly.

## Item-by-item findings

### 1. Google Places API (New) — endpoints and Essentials tier

**Autocomplete (New):** Confirmed live via `https://developers.google.com/maps/documentation/places/web-service/place-autocomplete`. Real endpoint: `POST https://places.googleapis.com/v1/places:autocomplete`, JSON body with `input`, optional `sessionToken`, `includedRegionCodes`, etc. Note: it's **POST**, not GET — the spine's Stack table (line 132) just names the path `places:autocomplete` without a verb, which is fine, but AD-4's own BE contract (`GET /places/autosuggest`) is fenzit-be's own proxy design, not a mirror of Google's verb — no inconsistency, just worth knowing BE and Google verbs differ by design.

**Place Details (New):** Confirmed live via `https://developers.google.com/maps/documentation/places/web-service/place-details`. Real endpoint: `GET https://places.googleapis.com/v1/places/{placeId}`. Matches spine exactly.

**Essentials tier field mask — one imprecision found:** The current Google docs split what the spine calls "Essentials tier" into **two separate SKUs**:
- **Essentials SKU** (paid, $5/1,000 after free cap): `addressComponents`, `addressDescriptor`, `adrFormatAddress`, `formattedAddress`, `location`, `plusCode`, `postalAddress`, `shortFormattedAddress`, `types`, `viewport`.
- **Essentials IDs Only SKU** (billed at $0, unlimited free): `attributions`, `consumerAlert`, **`id`**, `movedPlace`, `movedPlaceId`, `name`, `photos`.

So `id` in the spine's mask (`id,formattedAddress,location,addressComponents,postalAddress`, AD-5) is **not** actually part of the "Essentials" SKU — it's a distinct, separately-billed-but-free SKU. Net effect on cost is nil (both are cheap/free relative to Pro), so AD-5's no-`displayName` rule is still the right call and nothing is broken. But calling the whole mask "Essentials tier" is imprecise; it should read "Essentials + Essentials IDs Only (free)". This imprecision was already present in the companion research (`research.md` line 58 lists Essentials tier membership *without* `id`, then line 71's recommendation calls the full mask including `id` "all Essentials tier" — an internal inconsistency in the research that carried forward unchanged into the spine). Confirmed `displayName` is genuinely Pro-tier (correctly excluded).

**Session pricing mechanic** (not explicitly asked for, but underlies AD-3/AD-6): confirmed live via `.../session-pricing` — Essentials-tier Place Details bills the first 12 Autocomplete requests individually before the session discount applies; Pro/Enterprise-tier Place Details makes all Autocomplete requests in the session free. This matches the research's claim [4] and is correctly reflected in the spine's trade-off framing.

**Verdict on item 1:** Structurally correct and genuinely web-verified (the research.md shows real WebFetch citations against live Google docs, and I independently re-confirmed the same URLs return the same facts today). One field-label imprecision (`id`'s actual SKU) to fix, no cost or behavior impact.

### 2. Bun 1.3.13

Confirmed against the **actual repo**, not just asserted:
- `workspace/core/backend/fenzit-be/project-context.md:34` — "Stack: NestJS v11 + Fastify v5 + Bun v1.3.13"
- `workspace/core/backend/fenzit-be/package.json` — `"packageManager": "bun@1.3.13"`, `"engines": { "bun": ">=1.3" }`
- Locally installed `bun --version` → `1.3.13`

This is a real, existing, current-ish Bun version — current latest per web search is 1.4.1 (Sept 2026), so 1.3.13 is one minor behind, not stale or invented. The spine correctly sources this from the existing project rather than asserting a version from training data.

### 3. `AbortSignal.timeout()` with Bun's native `fetch`

Confirmed real and current via Bun's own docs (`https://bun.com/docs/runtime/networking/fetch`): documented pattern is exactly `fetch(url, { signal: AbortSignal.timeout(1000) })`, no caveats noted on the current docs page. This has been supported since Bun v0.5.7 (2023). There was a real historical rough edge — GitHub issue #13302 ("`AbortSignal.timeout` and `fetch` not working when can't reach server," reported against Bun 1.1.24) and a related fix in PR #16859 (Jan 2025, "Make passing `signal: AbortSignal.timeout` to fetch implicitly set `timeout: false`", addressing a case where Bun's own internal default fetch timeout could race/override the AbortSignal). Both predate Bun 1.3.13 (Sept 2026) by well over a year, so the pinned version should already include these fixes. No caveat needed in the spine; AD-2's `AbortSignal.timeout(4000)` usage is sound.

### 4. Other named tech/version claims — spot-checked against the actual repo

All confirmed present exactly as described, not just plausible-sounding:
- NestJS v11 → `package.json`: `@nestjs/core@^11.0.1`, `@nestjs/common@^11.0.1`
- Fastify v5 → `package.json`: `fastify@^5.8.5`
- `@nestjs/cache-manager` (existing, in-memory) → `package.json`: `@nestjs/cache-manager@^3.1.3`, `cache-manager@^7.2.8`
- The DI-swap convention the spine claims `PlacesProvider`/`GooglePlacesProvider`/`MockPlacesProvider` mirrors → real files exist: `src/auth/otp-delivery.provider.ts`, `src/auth/mock-otp-delivery.provider.ts`, `src/auth/in-memory-otp-session.store.ts`
- `JwtAuthGuard` / `Roles` decorator / `RolesGuard` referenced in AD-4 and Inherited Invariants → real files exist: `src/common/guards/jwt-auth.guard.ts`, `src/common/decorators/roles.decorator.ts`, `src/common/guards/roles.guard.ts`

No fabricated file paths or invented conventions found among these.

### AD-8 — flagged by the spine itself, not by me

The spine already self-flags AD-8's React Navigation native-stack "callback survives across push" claim as `[ASSUMPTION — not yet runtime-verified]`. This is the correct honest posture for a claim that genuinely needs a runtime check rather than a doc check (React Navigation's mount/unmount behavior on push is configuration-dependent within the app, not something a web search settles). No further action needed beyond what the spine already commits to (verify at implementation time).

## Summary of required fixes

1. **AD-5 / Stack table:** Reword "Essentials tier" field mask description to note `id` comes from the separate (free) "Essentials IDs Only" SKU, not the "Essentials" SKU proper — cosmetic/precision fix only, no cost or design impact. Same correction should ideally flow back to the companion research.md (lines 58 vs. 71 currently contradict each other on whether `id` is Essentials).
2. No other technology, version, or endpoint claim in the spine needs correction — all were either genuinely web-verified (Google Places specifics, Bun/AbortSignal facts) or reality-checked against the existing fenzit-be repo (Bun version, NestJS/Fastify/cache-manager versions, DI-swap file conventions, guard/decorator names).

## Sources consulted this session

- https://developers.google.com/maps/documentation/places/web-service/place-details
- https://developers.google.com/maps/documentation/places/web-service/place-autocomplete
- https://developers.google.com/maps/documentation/places/web-service/session-pricing
- https://developers.google.com/maps/billing-and-pricing/pricing
- https://bun.com/docs/runtime/networking/fetch
- https://github.com/oven-sh/bun/issues/13302
- https://github.com/oven-sh/bun/pull/15623
- https://github.com/oven-sh/bun/pull/16859
- Local repo: `workspace/core/backend/fenzit-be/project-context.md`, `package.json`, `src/auth/*`, `src/common/guards/*`, `src/common/decorators/*`
- Companion research: `artifacts/planning-artifacts/research/technical-google-places-api-address-autocomplete-c-2026-09-05/research.md`
