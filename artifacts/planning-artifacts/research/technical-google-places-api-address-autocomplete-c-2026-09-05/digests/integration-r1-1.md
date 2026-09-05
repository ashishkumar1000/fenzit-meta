# Digest — Integration & interoperability, round 1

**Assistant task:** Verify the correct Google Places API (New) endpoint for a type-ahead address picker, the session-token billing mechanism, field-mask SKU tiers, and cost-reduction best practices. Retrieved live via WebFetch against official Google Maps Platform docs this session.

## Claims

- claim: Autocomplete (New) (`places:autocomplete`) is the endpoint designed for type-ahead ("as user types") predictions; Text Search (New) (`places:searchText`) is designed for complete search phrases (e.g. "restaurants near me"), not incremental address entry.
  source: https://developers.google.com/maps/documentation/places/web-service/op-overview
  publisher: Google Maps Platform (official docs) — accessed: 2026-09-05 — confidence: high — class: landscape/integration-pattern

- claim: Autocomplete (New) responses return `suggestions[].placePrediction.placeId` and prediction text (`text`, `structuredFormat.mainText`/`secondaryText`) but do not include geographic coordinates or full address components; a second call to Place Details (New) (`places/{placeId}`) is required to obtain `location` (lat/long) and `addressComponents`.
  source: https://developers.google.com/maps/documentation/places/web-service/op-overview
  publisher: Google Maps Platform (official docs) — accessed: 2026-09-05 — confidence: high — class: integration-pattern

- claim: A session token (client-generated UUID) attached to every Autocomplete keystroke request and to the terminating Place Details call groups that sequence into one billable "session," which is cheaper than per-request billing.
  source: https://developers.google.com/maps/documentation/places/web-service/session-tokens
  publisher: Google Maps Platform (official docs) — accessed: 2026-09-05 — confidence: high — class: pricing-mechanism

- claim: If the Place Details call in a session requests any Pro-tier or Enterprise-tier field, all Autocomplete requests in that session become free; if Place Details only requests Essentials-tier fields, Autocomplete requests are billed individually before the session discount applies.
  source: https://developers.google.com/maps/documentation/places/web-service/session-pricing
  publisher: Google Maps Platform (official docs) — accessed: 2026-09-05 — confidence: high — class: pricing-mechanism (needs recheck ≤1mo per pack freshness bar — pricing pages change)

- claim: Place Details (New) fields are billed at the highest SKU tier touched by the field mask. Essentials tier includes `addressComponents`, `formattedAddress`, `location`, `postalAddress`, `plusCode`, `viewport`, `types`. Pro tier includes `displayName`, `businessStatus`, `primaryType`, and timezone-related fields. Enterprise/Enterprise+Atmosphere covers phone, rating, hours, reviews.
  source: https://developers.google.com/maps/documentation/places/web-service/place-details
  publisher: Google Maps Platform (official docs) — accessed: 2026-09-05 — confidence: high — class: pricing-mechanism (needs recheck ≤1mo — SKU tables are versioned and have changed before)

- claim: A field mask of `id,formattedAddress,location,addressComponents` stays entirely in the Essentials tier (cheapest); adding `displayName` (as originally proposed) bumps the whole Place Details call to Pro-tier pricing. Autocomplete's own `structuredFormat.mainText` can substitute as a display label without paying for `displayName`.
  source: https://developers.google.com/maps/documentation/places/web-service/place-details
  publisher: Google Maps Platform (official docs) — accessed: 2026-09-05 — confidence: high — class: implementation-reality

- claim: Postal/pin code is not a flat field on Place Details responses — it must be extracted by filtering the `addressComponents` array for the entry whose `types` array contains `"postal_code"`, reading `longText`/`shortText`.
  source: https://developers.google.com/maps/documentation/places/web-service/place-details (addressComponents schema)
  publisher: Google Maps Platform (official docs) — accessed: 2026-09-05 — confidence: high — class: integration-pattern

- claim: Google's API key security guidance recommends never sharing one key across a client-side JS SDK and a server-side REST integration — server keys should carry IP-address restrictions, client keys HTTP-referrer restrictions.
  source: https://developers.google.com/maps/api-security-best-practices
  publisher: Google Maps Platform (official docs) — accessed: 2026-09-05 — confidence: high — class: security-practice

- claim: `includedRegionCodes`/`locationBias`/`locationRestriction` on Autocomplete (New) narrows predictions to a target country/area, reducing noisy/irrelevant results (and by extension wasted billable calls).
  source: https://developers.google.com/maps/documentation/places/web-service/op-overview
  publisher: Google Maps Platform (official docs) — accessed: 2026-09-05 — confidence: medium — class: implementation-reality (general best practice, not a hard Google-stated cost figure)

- claim: A ~300ms debounce and a minimum-character threshold (commonly 3 characters) before firing the first Autocomplete request are standard industry practice for typeahead search to cut request volume, independent of any specific Google-stated number.
  source: general implementation-reality synthesis (industry convention), not tied to one Google doc page
  publisher: n/a — confidence: medium — class: implementation-reality

## Leads not chased further (out of scope for this focused query)
- Exact current Maps Platform monthly free-tier credit amount ($200/mo cited from training-era knowledge, not re-verified against a live pricing page this round — should be reconfirmed before finance sign-off, flagged as open question).
- Per-method QPS default quotas — not itemized; general statement that they're configurable in Cloud Console and comfortably high for low-volume internal use.

## What was looked for and not found
- No official Google guidance found (or needed) specifying an exact debounce/min-character number — these are cited as industry convention, not vendor spec.
