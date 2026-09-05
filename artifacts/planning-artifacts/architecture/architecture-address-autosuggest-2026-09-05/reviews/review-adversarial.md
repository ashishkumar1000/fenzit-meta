# Adversarial Review — Address Autosuggest Architecture Spine

**Target:** `ARCHITECTURE-SPINE.md` (Address Autosuggest for Add Customer, 2026-09-05)
**Method:** For each AD, construct two engineers who each read only the spine (not each other's code), obey every stated Rule to the letter, and make the most locally-reasonable call wherever the Rule is silent or presented as shorthand. Where they'd diverge, that's a hole. Findings below are grounded against the actual `fenzit-be` and `fenzo-app` codebases (file/line evidence noted where applicable), not just the spine text in isolation.

**Verdict:** Not ready to build from as-is. The spine is well-organized and most invariants are genuinely load-bearing, but it under-specifies exactly the surfaces where two independent engineers naturally diverge: the precise wire shape crossing FE↔BE (nullability semantics, casing, and the raw-vs-normalized return type of the provider abstraction), the exact payload crossing the FE-internal callback, and two silently-shared-vs-silently-absent stateful behaviors (rate-limit key scope, in-flight-request cancellation). None of these are exotic edge cases — most fire on the very first "no locality returned" or "user backgrounds mid-flow" case in manual testing.

---

## Ranked Findings

| # | Severity | Finding |
|---|----------|---------|
| 1 | **Critical** | AD-4's `latitude`/`longitude: number` (non-nullable) is not actually guaranteed by Google's Place Details API for every place that can be resolved from Autocomplete, and the spine defines no error path for the case where it's absent. |
| 2 | **Critical** | AD-2 never fixes whether `PlacesProvider.resolve()`/`autosuggest()` return Google's raw shape or the AD-4-normalized shape — and the one existing DI-swap precedent in the codebase (`OtpDeliveryProvider.send(): Promise<void>`) gives zero guidance either way, so `GooglePlacesProvider` and `MockPlacesProvider` can be built to genuinely different contracts and both look "correct" in isolation. |
| 3 | **High** | AD-4/AD-5 don't pin down null-vs-omitted-vs-empty-string for `city`/`area`/`pincode` when Google returns no matching address component at all — a real, common case (rural addresses, some administrative-only results). |
| 4 | **High** | AD-8's callback-via-route-params pattern has **zero precedent** in this codebase (confirmed by repo search) and cuts against the codebase's actual, consistent convention for cross-screen data return (serializable param + read-on-focus, as used by `JobsScreen`'s `scope` param) — plus React Navigation's own documented aversion to non-serializable route params. The exact payload shape of `resolvedAddress` crossing that callback is also nowhere typed, and `AddCustomerSheet`'s current state (three flat `useState<string>` fields, no lat/lng/placeId fields at all) has no defined mapping from the resolve response. |
| 5 | **High** | AD-6's rate-limiter key `places:rate:{tenantId}` carries no endpoint discriminator, so it's ambiguous whether `autosuggest` (fired on every debounced keystroke) and `resolve` (fired once per selection) share one budget or two — and the one existing precedent (OTP's `otp:rate:${key}`) doesn't resolve this because it has only ever had one call site. |
| 6 | **Medium** | In-flight `resolve()` cancellation on unmount/backgrounding is unspecified, despite an established `AbortController` + `signal` convention already used for exactly this race elsewhere in the app (`CustomerDetailScreen`, `JobDetailScreen`). One engineer will follow house style and cancel; another will lean on AD-8's "stays mounted" assumption and not bother — producing different behavior when a resolved callback fires after the user has moved on. |
| 7 | **Medium** | AD-9's 429 body is only ever shown as shorthand (`429 RATE_LIMITED`), never as a literal JSON example the way the 502 case is (`502 { error_code: 'PLACES_UPSTREAM_ERROR' }`) — an engineer working from the spine alone (not the wider codebase) could reasonably build a different, non-conforming shape. |
| 8 | **Medium** | AD-8 defines only the success path (`onSelect` then `goBack()`); the failure path — what happens on the picker screen when `resolve()` 502s or 429s after a tap — is undefined, and two equally rule-compliant implementations (silent auto-`goBack` to manual entry vs. inline retry) produce different UX and different code. |
| 9 | **Low** | AD-7 pins DB column names (snake_case) but never states the new `CreateCustomerDto` field names/casing. The codebase's real convention (camelCase DTO, hand-mapped to snake_case columns in the service layer, confirmed in `customers.service.ts`) strongly implies camelCase — but the spine doesn't say so, so this is convention-by-osmosis, not a stated invariant. |
| 10 | **Low (systemic, not a single hole)** | Nothing in the spine requires a shared/generated type contract between the two repos. FE resource files in this codebase are hand-typed per endpoint with **no** runtime validation or shared schema (confirmed: no zod/io-ts, no key-casing transform, `customers.ts` comment literally says "matches a real response"). Every ambiguity above (#1, #3, #4, #9) will not be caught by any tool — it surfaces only as a runtime mismatch or crash discovered in manual testing. |

*(Checked and found NOT to be a hole: AD-1's "imports only `CacheModule`" reads as if it might conflict with AD-10's `ConfigService` dependency in `GooglePlacesProvider` — but `ConfigModule` is registered globally in `app.module.ts` with `isGlobal: true`, confirmed by grep showing no existing feature module imports it to use `ConfigService`. No fix needed, just worth noting AD-1's wording is slightly imprecise about what "imports only" is scoping.)*

---

## Scenario 1 — Lat/long "always present": Engineer A trusts the type, Engineer B doesn't (Critical)

**Rule as written (AD-4):** `latitude: number, longitude: number` — no `| null`, unlike `city`/`area`/`pincode`.

**Reality check:** The field mask requested (AD-5) is `id,formattedAddress,location,addressComponents,postalAddress`. Requesting a field does not guarantee Google populates it for every resolvable `placeId` — Google's Place Details documentation itself notes `location` can be absent for certain place types (e.g., some administrative-area-only results, plus-code-only entries). Autocomplete filtered toward addresses makes this rare, not impossible — and the spine gives no filter on Autocomplete restricting results to only geocodable address types.

- **Engineer A** (backend) writes `GooglePlacesProvider.resolve()` trusting the type contract literally: `latitude: place.location.latitude`. If `location` is ever absent for a given placeId, this throws a `TypeError` reading a property of `undefined` — an unhandled 500, not the clean 502 `PLACES_UPSTREAM_ERROR` AD-9 promises for "provider failure."
- **Engineer B** (also backend, different day) is more defensive: uses optional chaining, `place.location?.latitude`, which NestJS's default JSON serializer will simply **drop the key** for (an `undefined` value in a plain object is omitted, not serialized as `null`). The FE, trusting the `number` contract from AD-4 (no `| null` needed, no defensive check written), destructures `latitude` as `undefined`, then either crashes doing math on it or silently persists garbage into `customers.latitude` (nullable per AD-7, so no DB constraint catches it).

Both engineers followed AD-4 and AD-5 to the letter. Neither produced the same failure mode, and neither actually delivers on the "never null" promise the type makes.

**Fix:** Add an AD (or amend AD-9) explicitly stating: if Place Details response for a resolved `placeId` lacks `location`, treat it identically to provider failure — throw the same `502 PLACES_UPSTREAM_ERROR` GlobalExceptionFilter shape, never let a partial object reach the controller's serializer.

---

## Scenario 2 — `PlacesProvider`'s return shape is a free variable (Critical)

**Rule as written (AD-2):** "An abstract `PlacesProvider` class ... with two methods — `autosuggest(input, sessionToken)` and `resolve(placeId, sessionToken)`." No return type is given for either method. AD-5 describes *where in Google's raw response* the mapped fields come from (`postalAddress.postalCode`, `addressComponents` typed `locality`/`sublocality_level_1`) — but never says *which layer performs that mapping*.

**Precedent check (confirmed via repo read):** The one existing DI-swappable provider in this codebase, `OtpDeliveryProvider`, has the signature `abstract send(phone: string, otp: string): Promise<void>` — a fire-and-forget side effect with no return value at all. This establishes precedent for "keep the abstract interface minimal," but gives **zero guidance** on what a provider that returns data should return.

- **Engineer A** builds `GooglePlacesProvider.resolve()` to return Google's raw Place object (full `addressComponents` array, `location: {latitude, longitude}`, `postalAddress`), and puts the AD-5 mapping logic (locality→city, sublocality_level_1→area, postalAddress.postalCode→pincode) inside `PlacesController` or a separate mapper service that calls the provider.
- **Engineer B** builds `resolve()` to return the AD-4-normalized flat shape directly (`{placeId, formattedAddress, city, area, pincode, latitude, longitude}`), doing the AD-5 mapping *inside* `GooglePlacesProvider` itself, with the controller doing a pure passthrough.

Both are legitimate readings of "an abstract `PlacesProvider` class... backed by `GooglePlacesProvider`." The practical damage: `MockPlacesProvider`, built by whichever engineer gets to it first (or a third engineer working from tests only), fabricates test fixtures matching *one* of these two shapes. If it's built against the wrong assumption relative to the real controller wiring, tests pass green while the real integration is broken — the exact kind of hole a mock/interface abstraction is supposed to prevent, but doesn't here because the interface's return type was never specified.

**Fix:** Add to AD-2 (or split into AD-2b): explicit TypeScript signatures for both methods, e.g. `resolve(placeId: string, sessionToken: string): Promise<ResolvedPlace>` with `ResolvedPlace` defined as exactly the AD-4 response shape (minus HTTP wrapper) — i.e., the provider does the AD-5 mapping, the controller is a pure passthrough. State explicitly that `MockPlacesProvider` must satisfy this same normalized shape.

---

## Scenario 3 — "No locality returned": null, empty string, or omitted? (High)

**Rule as written:** `city: string | null` etc. (AD-4). AD-5: "city/area from `addressComponents` entries typed `locality` / `sublocality_level_1`." No statement of what happens when no entry of that type exists in the array — which happens routinely (many rural/administrative Google results have no `locality`-typed component at all, only `administrative_area_level_2/3`).

- **Engineer A** treats "no matching component" as `city: null` — clean, matches the declared type.
- **Engineer B**, writing the mapping function generically (`components.find(c => c.types.includes('locality'))?.longText`), gets `undefined` from the `find`, and either lets it flow through as `undefined` (dropped key, same JSON-omission problem as Scenario 1) or coerces it with `?? ''` to an empty string, reasoning "the FE form field is a plain text input that starts as `''`, so `null` would require an extra guard downstream that `''` doesn't."

Both are defensible. But downstream, `AddCustomerSheet`'s `city` state (confirmed: a plain `useState<string>`, not nullable) needs *some* value from whichever shape arrives — an engineer building the FE mapping independently, seeing `city: string | null` in the contract, will write `setCity(resolved.city ?? '')`, which happens to paper over both choices at that boundary. But the DB write path (AD-7, nullable `city`... wait, `city` is the *existing*, unchanged column) still receives whatever `AddCustomerSheet` submits, so if the BE ever emits `''` instead of `null`, a "no city" result becomes indistinguishable from "user explicitly typed nothing," corrupting any future query/filter that distinguishes "no data" from "empty."

**Fix:** State explicitly in AD-4/AD-5: "If no matching address component exists, the field is `null` — never an empty string, never an omitted key." Add a one-line contract test asserting this on the mapper.

---

## Scenario 4 — AD-8's callback pattern has no home in this codebase (High)

**Confirmed via repo search:** There is no existing case in `fenzo-app` of a function passed through `route.params`. The two real precedents are (a) a plain serializable value passed via `navigation.navigate(..., { scope })` and read via `route.params?.scope` on focus, then cleared with `setParams({ scope: undefined })` (`JobsScreen.tsx`), or (b) an in-screen prop callback for a picker rendered inline in the same component tree, never pushed as a separate route (`TechnicianPicker` in `EditJobSheet.tsx`/`NewJobScreen.tsx`). AD-8 proposes a third pattern that resembles neither, and it's also a well-known rough edge in React Navigation itself (non-serializable route params generate dev warnings and break state persistence/devtools/deep-linking, none of which the spine addresses).

- **Engineer A** follows AD-8 literally: `AddCustomerSheet` calls `navigation.navigate('AddressPicker', { onSelect: (addr) => { setCity(...); ... } })`.
- **Engineer B**, aware the codebase's `RootStackParamList` only ever carries serializable values (confirmed: IDs and enums only) and wary of the non-serializable-params warning, instead follows the codebase's own established convention: `AddressPickerScreen` calls `navigation.navigate('AddCustomer', { pickedAddress: resolved })` and `AddCustomerSheet` reads it via a focus effect, mirroring `JobsScreen`.

Both engineers can point to "I followed the codebase's conventions" — one obeying the letter of AD-8, the other obeying the stronger, unstated precedent AD-8 contradicts. These two implementations are structurally incompatible (different navigation route names, different param shapes, different screen that owns the "clear it" responsibility).

Compounding this: even *within* AD-8's literal interpretation, the exact shape of the object passed to `onSelect` is never typed. `AddCustomerSheet`'s confirmed current state is three flat strings (`city`, `area`, `address`) with **no** `latitude`/`longitude`/`placeId`/`formattedAddress` state fields declared anywhere yet. Does `onSelect` receive the raw AD-4 resolve response verbatim (requiring `AddCustomerSheet` to add four new state variables not mentioned in the spine's structural seed) or some FE-side-transformed subset? Two engineers building the picker side and the sheet side independently will not agree on this without it being pinned down.

**Fix:** Either (a) explicitly override the "serializable params only" convention in AD-8, with reasoning for why this one screen is the exception, and give the literal TypeScript type of the object crossing the callback (matching AD-4's resolve response 1:1, or stating the transform); or (b) drop the callback pattern in favor of the codebase's existing `setParams`-and-read-on-focus convention, consistent with `JobsScreen`. Also: explicitly list the new `AddCustomerSheet` state fields (`latitude`, `longitude`, `placeId`, `formattedAddress`) in the structural seed.

---

## Scenario 5 — Rate limiter: one shared budget or two? (High)

**Rule as written (AD-6):** key `places:rate:{tenantId}` — no route/purpose segment. Contrast with the caching rule two sentences later, which *does* explicitly differentiate: "keyed on normalized query text + region for `autosuggest`, and on `placeId` for `resolve`."

**Precedent check (confirmed):** the OTP counter (`otp:rate:${key}`) has exactly one call site (`auth.service.ts`, keyed by phone number) — it has never had to answer "do two different call sites share a counter," so it sets no precedent either way.

- **Engineer A** implements literally: one `RateLimiterService.check(tenantId)` call, invoked identically from both the `autosuggest` and `resolve` controller methods, incrementing the same `places:rate:{tenantId}` counter. Given `autosuggest` fires on every debounced keystroke while typing an address (many calls per address entered) and `resolve` fires once per selection, a single shared budget means heavy autosuggest usage can exhaust the counter before the user ever reaches `resolve` — the exact opposite of what AD-6's own reasoning ("cost control... premature abstraction across two unrelated domains") is trying to protect, since resolve (Place Details) is the pricier of the two Google calls.
- **Engineer B**, reasoning about the volume mismatch, appends an endpoint segment: `places:rate:{tenantId}:autosuggest` / `places:rate:{tenantId}:resolve` — two independent budgets — believing this is obviously what was intended, since the *caching* rule right next to it does exactly this kind of per-endpoint keying.

Both are literal-compliant-or-better-judgment readings of an ambiguous key. They produce different rate-limiting behavior under load, which is exactly the kind of "clashing shared state" the task is looking for (same tenant, different effective quota depending on which engineer wrote it).

**Fix:** State explicitly whether `autosuggest` and `resolve` share one counter or have independent ones, and if independent, give the exact key template.

---

## Scenario 6 — In-flight `resolve()` after the user has moved on (Medium)

**Confirmed precedent:** `CustomerDetailScreen.tsx`, `JobDetailScreen.tsx`, and `TechJobDetailScreen.tsx` all use a `latestControllerRef`-held `AbortController` passed as `signal` into the resource call, specifically to guard against a stale response landing after the user has navigated elsewhere. The resource layer (`customers.ts`, `jobs.ts`, `users.ts`) already supports an optional `signal` param for this reason.

AD-8's bracketed assumption only addresses whether the screen stays *mounted* — it says nothing about whether the in-flight `/places/resolve` fetch triggered by tapping a suggestion should be cancelled if the user backgrounds the app, hits the hardware back button, or otherwise leaves the picker before the request resolves.

- **Engineer A**, following house style, wires an `AbortController` into `useAddressAutosuggest.ts`'s resolve call and aborts it on unmount/navigation-away, matching `CustomerDetailScreen`.
- **Engineer B** takes AD-8's "stays mounted, callback stays valid" language at face value and does nothing special — no cancellation, no unmount guard. If the request eventually resolves after the user has already closed `AddCustomerSheet` (e.g., swiped away, or the flow was abandoned), `onSelect` still fires against a component that may have already been dismissed/unmounted by the parent screen (the sheet's `visible` prop, not the screen, controls its lifecycle — a case AD-8 never reasons about since it only talks about `navigation`-level mounting, not the sheet's own `visible`/`onClose` state).

**Fix:** State explicitly whether cancellation is required, and if so, that it follows the existing `AbortController`+`signal` convention already used elsewhere in the app.

---

## Scenario 7 — 429 body: shorthand vs. literal (Medium)

AD-9 shows the 502 case as a literal JSON body (`502 { error_code: 'PLACES_UPSTREAM_ERROR' }`) but the 429 case only as shorthand (`429 RATE_LIMITED`) in both AD-6 and AD-9. The Consistency Conventions table does state a global error shape (`{ statusCode, error_code, message }` per AR-14), and a repo check confirms `GlobalExceptionFilter` will indeed always emit that three-field shape as long as the throwing code follows the codebase's own idiom (`throw new HttpException({ error_code, message }, 429)`, as used throughout `customers.service.ts`). But nothing in the spine text itself tells an engineer working from the spine alone that "429 RATE_LIMITED" expands to that idiom rather than, say, a bare `429` with a `Retry-After` header and no body, or a plain-text body — both plausible alternate REST conventions for rate limiting, and neither contradicted by the spine's literal wording.

**Fix:** Spell out the 429 body in full JSON in AD-9, matching the 502 example's format, for consistency and to close the reliance on tribal codebase knowledge.

---

## Scenario 8 — Picker-side failure path is undefined (Medium)

AD-8 only describes the success path. AD-9 guarantees the *shape* of a resolve failure (502/429) but not what the **picker screen** does with it. Two equally rule-compliant behaviors:

- **Engineer A**: on `resolve()` failure, silently call `navigation.goBack()` without invoking `onSelect` — the user lands back on `AddCustomerSheet` with nothing filled in, expected to fall back to manual entry (consistent with AD-9's "manual entry is the standing fallback").
- **Engineer B**: on `resolve()` failure, keep the picker open, show an inline error/toast, let the user retry or tap a different suggestion.

Both satisfy every written Rule; they are simply different products, and neither is wrong per the spine as written.

**Fix:** Add one sentence to AD-8 or AD-9 describing the picker's on-failure UI behavior.

---

## Scenario 9 — `CreateCustomerDto` new field casing (Low)

AD-7 specifies exact snake_case DB column names (`area`, `formatted_address`, `pincode`, `latitude`, `longitude`, `place_id`) but never states the corresponding `CreateCustomerDto` field names. The codebase's actual convention (confirmed: `CreateCustomerDto` uses camelCase — `countryCode`, `phoneNumber` — hand-mapped to snake_case columns inside `customers.service.ts`'s raw Supabase `.insert()` call, e.g. `country_code: dto.countryCode`) strongly implies the new fields should be `formattedAddress`, `pincode`, `latitude`, `longitude`, `placeId`. But since the spine only ever states the *DB* names, an engineer who doesn't cross-reference `customers.service.ts` could just as easily copy the DB names verbatim into the DTO (`formatted_address`, `place_id`), producing a payload the FE (which will naturally send camelCase, matching AD-4's response casing) fails class-validator on with unrecognized-field or missing-required-field errors.

**Fix:** State the DTO field names explicitly in AD-7, confirming camelCase to match the codebase convention and AD-4's response casing.

---

## Overall Recommendation

Tighten AD-2 (explicit return types + who does AD-5's mapping), AD-4/AD-5 (null-vs-omitted contract, lat/long failure path), AD-6 (rate-limiter key scope), AD-7 (DTO field casing), and AD-8 (exact callback payload type, failure path, cancellation semantics, and either a justification for departing from the codebase's serializable-params convention or a switch to that convention). None of these require new architectural decisions from scratch — each is a one-to-three-sentence tightening of an AD that already exists, informed directly by conventions already present and confirmed in both `fenzit-be` and `fenzo-app`.
