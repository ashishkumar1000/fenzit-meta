---
title: 'technical research: Google Places API (New) integration for address autocomplete, cost-optimized'
type: 'technical'
topic: 'Google Places API (New) integration for address autocomplete, cost-optimized'
decision: 'Design the FE/BE contract for an address autosuggest feature backed by Google Places API, minimizing per-request billing'
source: 'native run (WebFetch against official Google Maps Platform docs, this session)'
status: complete
preset: 'standard'
validation: 'normal'
created: '2026-09-05'
updated: '2026-09-05'
claims_verified: 8
claims_disputed: 1
claims_total: 9
---

# technical research: Google Places API (New) integration for address autocomplete, cost-optimized

**Decision this research serves:** Design the FE/BE contract for an address autosuggest feature backed by Google Places API, minimizing per-request billing.

## Executive summary

The sample contract in the requirement (Text Search — `places:searchText`) is the wrong Google Places API for a type-ahead address picker. The correct pair is **Autocomplete (New)** (`places:autocomplete`) for the keystroke-driven suggestion list, followed by **Place Details (New)** (`places/{placeId}`) once the user picks one, to get lat/long and address details — the Autocomplete guide itself directs callers to Place Details "to get more information about any of the returned place predictions" [1][2]. Cost is controlled by two levers used together: a **session token** shared across every Autocomplete keystroke and the terminating Place Details call, which the Autocomplete (New) guide confirms bills the whole search as one cheaper session instead of N separate requests [3][4]; and an **Essentials-tier field mask** (`id,formattedAddress,location,addressComponents,postalAddress`) on Place Details — Google's own billing page states verbatim "you are then billed at the highest SKU applicable to your request," so adding `displayName` would silently upgrade the entire call to Pro-tier pricing; the display label should instead come free from Autocomplete's own `structuredFormat.mainText` [5][6]. One design correction from the mid-verification pass: pin code should be read from `postalAddress.postalCode` directly rather than parsed out of `addressComponents`, which is more reliable [7]. Biggest caveat: the exact per-session dollar figures and the current Maps Platform free-tier credit were not re-verified live this round — treat pricing as directionally correct, confirm exact numbers in the Cloud Console before finance sign-off.

## Integration & interoperability (consolidated with landscape and implementation-reality signals)

**Wrong API, right API.** Places API (New) exposes three relevant endpoints [1]: Text Search (`places:searchText`) resolves a complete natural-language query ("Spicy Vegetarian Food in Sydney") to a ranked list of places — this is what the requirement's sample curl uses, and it is not built for incremental, partial-input address typing. Autocomplete (New) (`places:autocomplete`) is purpose-built for that: it accepts partial `input` text and returns a ranked list of predictions as the user types. Place Details (New) (`places/{placeId}`) resolves one specific place, by ID, to its full record.

**The two-call pattern.** Autocomplete's response gives `suggestions[].placePrediction.placeId` and display text (`text`, `structuredFormat.mainText`/`secondaryText`) — no coordinates, no structured address [2]:

```json
POST https://places.googleapis.com/v1/places:autocomplete
{"input": "123 main", "sessionToken": "3519edfe-..."}

→ {"suggestions":[{"placePrediction":{
     "placeId":"ChIJ...","text":{"text":"123 Main St, ..."},
     "structuredFormat":{"mainText":{"text":"123 Main St"},"secondaryText":{"text":"..."}}
}}]}
```

Selecting a suggestion triggers Place Details, same session token, minimal field mask:

```
GET https://places.googleapis.com/v1/places/{placeId}?sessionToken=3519edfe-...
X-Goog-FieldMask: id,formattedAddress,location,addressComponents,postalAddress

→ {"id":"ChIJ...","formattedAddress":"123 Main St, City, ST 12345, IN",
   "location":{"latitude":37.422,"longitude":-122.084},
   "postalAddress":{"postalCode":"12345","regionCode":"IN","locality":"City", ...},
   "addressComponents":[{"longText":"City","shortText":"City","types":["locality"]},
                         {"longText":"Area","shortText":"Area","types":["sublocality_level_1"]}, ...]}
```

**Correction from verification:** the API reference for `AddressComponent` does not document `postal_code` as an enumerated `types[]` value (it's standard across the wider Places product family but not confirmed on this specific reference page) — the more reliable source is the dedicated `PostalAddress` object, which carries a direct `postalCode` field. Read pin code from `postalAddress.postalCode`; keep `addressComponents` in the mask for City/Area breakdown (`locality`, `sublocality_level_1`, etc., needed for the auto-fill decision below) [7].

**Session tokens (primary cost lever).** A session token is a client-generated UUID attached to every Autocomplete request during one user typing-session and to the terminating Place Details call. The Autocomplete (New) guide states this directly: "Autocomplete (New) uses session tokens to group the query and selection phases of a user autocomplete search into a discrete session for billing purposes" [3]. The discount depends on the Place Details field mask: per the session-pricing page, a session ending in an **Essentials-only** Place Details call bills the *first 12* Autocomplete requests individually — only request 13+ gets the free session SKU; a session ending in a **Pro/Enterprise** Place Details call makes **all** Autocomplete requests in that session free [4]. For a typical address search (well under 12 keystrokes-worth of debounced requests), this means Essentials-only mode realistically still bills every Autocomplete call — the session token mainly saves on the Place Details call itself in that case, not on Autocomplete. This is a real trade-off, not a rounding error, and worth flagging before locking the mask.

**Field mask as SKU lever (secondary cost lever).** Google's billing page states verbatim: "You are then billed at the highest SKU applicable to your request. That means if you select fields in both the Essentials and the Pro SKUs, you are billed based on the Pro SKU" [5]. Tier membership: Essentials = `addressComponents`, `formattedAddress`, `location`, `postalAddress`, `plusCode`, `viewport`, `types`; Pro = `displayName`, `businessStatus`, `primaryType`, timezone fields; Enterprise/Enterprise+Atmosphere = phone, rating, hours, reviews. The requirement's stated need (place name, address, pincode, lat/long) tempts a mask of `id,displayName,formattedAddress,location,addressComponents` — but `displayName` alone bumps the whole call to Pro tier. Dropping it and sourcing the label from Autocomplete's `structuredFormat.mainText` keeps Place Details on pure Essentials pricing [6] — at the cost of forgoing the "all Autocomplete calls free" session discount described above. Given a typical address search rarely produces 12+ debounced keystroke requests anyway, staying Essentials-only and accepting per-request Autocomplete billing is still the cheaper overall choice for this feature's expected volume — but it is a genuine trade-off, not a free win, and should be restated to whoever owns the Maps Platform budget.

**Other cost/quality levers, implementation reality:** region/country biasing via `includedRegionCodes`/`locationBias`/`locationRestriction` narrows predictions to the target market and cuts irrelevant/wasted calls [9] — directly applicable here since the product is India-scoped. Debounce (~300ms) and a minimum input length (commonly 3 characters) before firing the first request are standard industry practice to cut request volume; these are not Google-mandated numbers, just convention (medium confidence, not vendor-sourced).

**Security.** Google's own guidance is never to share one API key between a client-side JS SDK integration and a server-side REST integration — server keys should carry IP-address restrictions, client keys HTTP-referrer restrictions [8]. Since this feature proxies through the backend (to keep the key off the device entirely, matching Fenzit's existing pattern of no client-held secrets), an IP-restricted server key is the right shape; no client-side Maps JS key is needed unless a future feature calls Places directly from the app.

## Cross-dimension insight

The two cost levers are not independent choices, and the interaction runs the *opposite* direction from the first pass of this research: because a typical debounced address search generates well under the 12-request threshold at which the Essentials-tier session discount kicks in for Autocomplete, choosing the cheapest Place Details field mask (Essentials-only) does **not** buy free Autocomplete calls — that only happens on Pro/Enterprise Place Details requests. So the "cheapest field mask" and "cheapest overall session" are not automatically the same choice; for this feature's low per-search request count, Essentials-only still wins on total cost, but that's a volume-dependent conclusion, not a mask-independent one, and should be re-checked if usage patterns change (e.g. very slow typers generating many more Autocomplete calls per session).

## Recommendations

1. Replace the requirement's Text Search sample with Autocomplete (New) + Place Details (New), session-token-linked. **Feeds:** architecture spine (integration pattern), BE API contract for the autosuggest endpoint.
2. Field mask on Place Details: `id,formattedAddress,location,addressComponents,postalAddress` — all Essentials tier. Read place label from Autocomplete's own prediction text, postal code from `postalAddress.postalCode` (not parsed out of `addressComponents`), and City/Area from `addressComponents` entries typed `locality`/`sublocality_level_1`. **Feeds:** BE endpoint implementation, contract for the caller (FE) payload shape.
3. Generate one session-token UUID per FE typing-session (created when the address picker opens, discarded on close/select), forwarded on every autosuggest call and the final "resolve" call to the BE, which forwards it to Google. **Feeds:** FE address-picker screen design, BE proxy endpoint request shape.
4. Restrict search with a country/region bias to India at the BE proxy layer (not user-configurable) per confirmed product scope, using `includedRegionCodes`. **Feeds:** BE endpoint config.
5. Debounce ~300ms, minimum 3 characters client-side before calling the BE autosuggest endpoint — medium confidence (industry convention, not a Google spec), acceptable to adopt as a starting default and tune later. **Feeds:** FE address-picker screen.
6. Use an IP-restricted server-side Google API key stored server-side only (fenzit-be `.env`, matching its existing Joi-validated `ConfigService` pattern) — no client-side key needed. **Feeds:** BE config/secrets handling.

## Open questions

- Exact current Maps Platform monthly free-tier credit and per-session/per-request dollar amounts were not re-verified live this round (training-era figures exist but are excluded here per this run's evidence rule) — reconfirm in Google Cloud Console pricing calculator before any finance/budget sign-off. Route: Refresh this run's pricing dimension, or check the Console directly.
- Default per-method QPS quotas for a low-volume internal app were not itemized (general statement only: configurable, comfortably high). Route: check Cloud Console quotas page if scale ever becomes a concern.
- Whether `postal_code` is actually a live `types[]` value on real Autocomplete/Place Details responses in India was not confirmed against a real API call this round (only against reference documentation, which doesn't enumerate it) — worth a quick manual test call before finalizing the BE parsing logic, though the design now primarily relies on `postalAddress.postalCode` instead, which sidesteps this.

## Source appendix

| # | Claim / finding it supports | Publisher | Pub. date | Accessed | Confidence |
|---|---|---|---|---|---|
| [1] | Autocomplete (New) is the type-ahead endpoint; Text Search is for complete phrases | [Google Maps Platform — Places API overview](https://developers.google.com/maps/documentation/places/web-service/op-overview) | n/d (live doc) | 2026-09-05 | High |
| [2] | Autocomplete guide directs callers to Place Details "to get more information about any of the returned place predictions" | [Google Maps Platform — Place Autocomplete (New)](https://developers.google.com/maps/documentation/places/web-service/place-autocomplete) | n/d (live doc) | 2026-09-05 | Medium-High (implies, doesn't state outright, that coordinates/full address are absent from Autocomplete) |
| [3] | "Autocomplete (New) uses session tokens to group the query and selection phases... into a discrete session for billing purposes" | [Google Maps Platform — Place Autocomplete (New)](https://developers.google.com/maps/documentation/places/web-service/place-autocomplete) | n/d (live doc) | 2026-09-05 | High |
| [4] | Essentials-only Place Details bills the first 12 Autocomplete requests individually; Pro/Enterprise Place Details makes all Autocomplete requests in the session free | [Google Maps Platform — Session pricing](https://developers.google.com/maps/documentation/places/web-service/session-pricing) | n/d (live doc) | 2026-09-05 | High |
| [5] | "You are then billed at the highest SKU applicable to your request" — cascading tier billing rule | [Google Maps Platform — Usage and billing](https://developers.google.com/maps/documentation/places/web-service/usage-and-billing) | n/d (live doc) | 2026-09-05 | High |
| [6] | Field-to-tier membership list (Essentials/Pro/Enterprise); `displayName` is Pro-tier | [Google Maps Platform — Place Details (New)](https://developers.google.com/maps/documentation/places/web-service/place-details) | n/d (live doc) | 2026-09-05 | High |
| [7] | `AddressComponent` reference doesn't enumerate `postal_code` as a types value; `PostalAddress.postalCode` is the documented, direct source | [Google Maps Platform — Places API reference](https://developers.google.com/maps/documentation/places/web-service/reference/rest/v1/places) | n/d (live doc) | 2026-09-05 | High (on what the reference does/doesn't say); Medium on whether `postal_code` type is truly absent in practice — see open questions |
| [8] | Server keys need IP restriction, client keys HTTP-referrer restriction, never shared | [Google Maps Platform — API security best practices](https://developers.google.com/maps/api-security-best-practices) | n/d (live doc) | 2026-09-05 | High |
| [9] | `includedRegionCodes`/`locationBias`/`locationRestriction` documented as Autocomplete (New) request parameters | [Google Maps Platform — Place Autocomplete (New)](https://developers.google.com/maps/documentation/places/web-service/place-autocomplete) | n/d (live doc) | 2026-09-05 | High |

_Correction note: the first draft of this research mis-cited claims [2], [3] and [9] to the general API-overview page and a legacy-scoped session-tokens page. A second-pass verification subagent re-fetched all 9 source URLs, caught the mismatches, and the citations above were corrected against the actual Autocomplete (New) guide and usage-and-billing page. Claim [7] was revised outright — see recommendation 2._

## Staleness map

Pricing-mechanism claims ([3][4][5]) are the fastest-aging class here — Google's SKU tables and session-pricing terms are versioned and have changed historically; recommended re-check window ≤ 1 month (per this pack's versions/compatibility freshness bar). Integration-pattern claims ([1][2][6][7]) and security-practice claims ([8]) are stable API-shape/practice facts, re-check window ≤ 2 years per the pack's patterns bar. Implementation-reality convention ([9], debounce/min-chars) doesn't age in the same sense — it's a design default, not a vendor fact.

**Earliest re-check due:** pricing-mechanism claims, within 1 month of 2026-09-05 (i.e. by 2026-10-05) — confirm current SKU tier assignments and session-pricing terms haven't changed before this ships to production billing.
