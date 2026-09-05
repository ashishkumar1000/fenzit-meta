---
name: 'Rubric Walk — Address Autosuggest Architecture Spine'
type: review
reviews: '../ARCHITECTURE-SPINE.md'
created: '2026-09-05'
---

# Rubric Walk-Through — Address Autosuggest for Add Customer

Reviewed against: `ARCHITECTURE-SPINE.md`, `fenzit-be/docs/architecture.md`,
`fenzit-be/project-context.md`, the companion research artifact
(`research/technical-google-places-api-address-autocomplete-c-2026-09-05/research.md`),
and direct inspection of both repos' current source (`fenzit-be/src/**`,
`fenzo-app/src/**`).

## Verdict

The backend half of this spine is solid and well-grounded in the existing
codebase; the frontend half has one significant gap (the FE→BE contract that
actually persists a picked address is never specified) and one significant
brownfield contradiction (AD-8 invents a navigation pattern the codebase
doesn't use, where an existing, simpler pattern already solves this exact
problem). Recommend revising AD-7/AD-8 and the AD-1 rule text before this
spine is used as a build substrate.

---

## 1. Does it fix the real divergence points for the level below?

**Mostly, with one major miss.**

The spine nails the divergence points on the Places-proxy side: which Google
endpoints to call (AD-2), who owns the session token (AD-3), the exact
request/response shape of the two new routes (AD-4), which request params are
server-fixed (AD-5), and where cost control lives (AD-6). These are exactly
the decisions two independent builders (FE dev building `AddressPickerScreen`,
BE dev building `PlacesController`) would otherwise guess differently on, and
the spine resolves all of them with concrete, checkable rules.

**Miss:** the spine never specifies the contract between "user picked an
address" and "customer gets created with that data." AD-7 adds six new
nullable `customers` columns (`area`, `formatted_address`, `pincode`,
`latitude`, `longitude`, `place_id`). AD-8 describes how the resolved address
gets back to `AddCustomerSheet`'s local state via a callback. But **nothing
defines the amended `CreateCustomerDto` / `POST /customers` request shape** —
field names (camelCase vs. the DB's snake_case), which of the six new columns
`AddCustomerSheet` actually sends, whether `latitude`/`longitude` go over the
wire as numbers or strings, or whether the manual-entry `area` field (which
today doesn't exist as its own request field at all — see finding below)
becomes a first-class optional DTO field or keeps being folded into
`address`. AD-4 defines the *Places proxy* contract in exact wire-format
detail; the *customer-creation* contract — the thing that actually turns a
picked address into persisted data — gets none of that rigor. This is
precisely the seam where an FE dev and a BE dev, building independently off
this spine, will guess differently and diverge. This should be its own AD
(or an explicit extension of AD-7) with the same level of precision as AD-4.

Everything else this altitude should own (auth on the new routes, error
shape, schema additivity, provider abstraction) is covered.

## 2. Is every AD's Rule enforceable and does it prevent its stated divergence?

Checked each AD's Rule against actual enforceability (lint/code-review
checkable, not just aspirational prose):

| AD | Enforceable? | Notes |
|---|---|---|
| AD-1 | Yes, but see finding below — the rule's premise about *how* `CacheModule` is consumed doesn't match the codebase. |
| AD-2 | Yes — abstract class + DI token, directly mirrors `OtpDeliveryProvider`/`MockOtpDeliveryProvider` (verified in `src/auth/otp-delivery.provider.ts`, `mock-otp-delivery.provider.ts`). |
| AD-3 | Yes — `sessionToken` as a required, validated DTO field is a standard, checkable constraint. |
| AD-4 | Yes — exact route shapes, `@Roles(Role.OWNER)` matches verified precedent in `customers.controller.ts`. |
| AD-5 | Yes — field mask and region code are literal constants, not derived from request input; trivially reviewable. Spot-checked against live Google docs today (see §4) — accurate. |
| AD-6 | Yes, mechanism is enforceable. Minor gap: rate-limit key `places:rate:{tenantId}` doesn't account for `RequestUser.tenantId` being typed `string \| null` (confirmed in `src/common/interfaces/request-user.interface.ts`) — a not-yet-onboarded owner would collapse into a `places:rate:null` bucket shared across all such owners. Likely moot in practice (an owner without a tenant probably can't reach customer creation either) but not ruled out explicitly. |
| AD-7 | Schema part is enforceable (migration diff review). But see the contract gap in §1 — the DTO/API-shape half of this AD is missing, so the schema alone doesn't fully prevent the stated divergence (BE/FE could still disagree on what actually flows into the new columns). |
| AD-8 | Enforceable as written, but built on a pattern with no codebase precedent — see §5, this is the most significant finding in this review. |
| AD-9 | Yes — status codes and error shapes are concrete and match `GlobalExceptionFilter`'s actual mechanics (verified: it reads `error_code`/`message` off a thrown `HttpException`'s response body). |
| AD-10 | Yes — `getOrThrow` on a Joi-required key is the exact, verified existing convention (`storage.service.ts`, `supabase-client.factory.ts`, `webhooks.service.ts`, `jwt-auth.guard.ts` all do this). |

## 3. Could anything in Deferred let independently-built units diverge incompatibly?

No item in Deferred looks unsafe to defer:

- UX affordance for opening the picker — pure implementation detail, doesn't affect FE/BE contract.
- Numeric rate-limit threshold — AD-9 already fixes the *contract* (`429 RATE_LIMITED`) regardless of the number, so FE can build against it without knowing the value.
- Multi-address-per-customer schema — explicitly out of scope per product decision, columns are correctly modeled as single-address now.
- Extracting the rate-limiter/cache into `common/` — deferring extraction (not behavior) carries no interop risk; the duplicated shape is still consistent.
- Refreshing stored place data via `place_id` — a future enhancement, absence doesn't break anything today.
- CI/deployment wiring for `GOOGLE_PLACES_API_KEY` — legitimately deferred; confirmed via repo scan that fenzit-be has **no Dockerfile and no CI config at all** yet (AR-18 is already a whole-app gap, not something this feature introduces or worsens).

One thing that arguably *should* be in Deferred (or promoted to a Rule) but
is currently just a code comment in the Structural Seed: the FE-side
debounce/minimum-query-length discipline. The research artifact treats this
as a **primary, coequal cost control** alongside session tokens (~300ms
debounce, 3-char minimum, explicitly called out in its Recommendations §5).
The spine's Capability→Architecture Map lists "Cost control" as governed
only by AD-6 (the BE-side limiter). The FE-side lever is mentioned only in
passing in the Structural Seed's file comment (`useAddressAutosuggest.ts #
debounce + session-token lifecycle`) — never stated as a Rule, never listed
in Deferred with an explicit "the number is TBD but the mechanism is fixed"
treatment the way AD-6's threshold gets. Two independently-built units could
each assume the other enforces a minimum input length, and ship with none,
which directly undermines the cost story this whole feature's research was
built around.

## 4. Is named tech verified-current?

Spot-checked live today (not just trusting the doc or the research
artifact's citations) via direct fetch against Google's current docs:

- **Place Details (New) SKU tiers** — confirmed `displayName` is Pro-tier
  (not Essentials), and `addressComponents`, `formattedAddress`, `location`,
  `postalAddress` are Essentials-tier. Matches AD-5's field mask exactly.
- **Autocomplete (New) session token billing statement** — confirmed live
  doc text: "Autocomplete (New) uses session tokens to group the query and
  selection phases of a user autocomplete search into a discrete session for
  billing purposes." Matches AD-3/AD-6's design rationale verbatim.
- **Bun 1.3.13, NestJS v11** — confirmed against `package.json`
  (`"packageManager": "bun@1.3.13"`) and `project-context.md`. Accurate.
- Google's own billing page's "highest applicable SKU" framing wasn't
  re-confirmed verbatim in this pass (the fetch tool's summary didn't surface
  the exact sentence), but the underlying tier classification it depends on
  was independently confirmed, so the practical conclusion (never add
  `displayName`) stands regardless.

No named tech claim in this spine reads as stale or incorrect.

## 5. Does it ratify or contradict existing brownfield conventions?

**This is where the spine's most serious issue lives: AD-8.**

The spine treats AD-8 (route-param callback: `navigation.navigate('AddressPicker', { onSelect })`)
as a **novel pattern needing runtime verification** — it's flagged
`[ASSUMPTION — not yet runtime-verified against this app's actual
native-stack config]`. That flag is good practice, but it understates the
actual problem: this codebase already has an established, working pattern
for exactly this class of interaction — "pick something from a list, return
the selection to a form" — and it is *not* navigation-based at all.

Verified precedent: `TechnicianPicker` (`src/components/TechnicianPicker`)
is rendered **inline**, in the same component tree as its caller, and takes
`onSelect` as a **direct prop**:
```tsx
// NewJobScreen.tsx:406
<TechnicianPicker
  technicians={technicianOptions}
  selectedId={draft.technicianId}
  onSelect={id => patch({ technicianId: id })}
/>
```
Same pattern again in `EditJobSheet.tsx:310`. No screen push, no route
params, no callback crossing a navigation boundary.

Further, every existing route param in `RootStackParamList`
(`navigation/types.ts`) is **plain serializable data** — `JobDetail: {
jobId: string }`, `CustomerDetail: { customerId: string }`. None carries a
function. AD-8 would be the first route param in the app to carry a
callback — a pattern React Navigation itself discourages (params should be
serializable) and one this codebase has never needed because its existing
"pick and return" idiom doesn't need navigation at all.

This matters more here than it would elsewhere because **the caller,
`AddCustomerSheet`, isn't a screen** — it's a `TrueSheet` bottom sheet
rendered inline inside `CustomersScreen` (confirmed in
`AddCustomerSheet.tsx` and `Sheet.tsx`). Pushing a brand-new full-screen
navigation route on top of the stack, to eventually pop back and mutate a
sheet's local `useState`, is a materially more fragile design than the
codebase's own established alternative: render `AddressPickerScreen`'s
content (list + search input) as an inline component *inside* the sheet,
exactly like `TechnicianPicker`, with a direct `onSelect` prop. That sidesteps
the entire "does native-stack keep the screen mounted" question the current
AD-8 assumption is worried about, because there would be no screen push at
all.

Recommendation: rewrite AD-8 to use the inline-component + direct-callback
pattern (matching `TechnicianPicker`), unless there's a UX reason (e.g., a
full-screen search experience is wanted for the address picker specifically)
that the product/UX side has already decided and this spine hasn't recorded.
If that UX decision genuinely requires a full-screen picker, then AD-8
should at least drop the callback-in-route-params approach (unprecedented
and against React Navigation's own serializability guidance) in favor of a
result returned through `navigation.goBack()` + a data param read via
`route.params` on refocus, or a screen-level state store scoped to this one
flow — not a function riding in the param list.

**A related, smaller ratify/contradict issue: AD-7's stated rationale is
factually wrong about current behavior.** AD-7 says the migration prevents
"losing the `area` field fenzo-app already submits but fenzit-be never
persists." In fact, fenzo-app does **not** currently submit a separate
`area` field — per `CustomersScreen.tsx`'s own code comment: *"The endpoint
has no `area` field, so Area is merged into the address line as
'\<address\>, \<area\>' — either part alone is sent on its own."* The FE
already works around the missing column via string concatenation; nothing
is currently being silently dropped by the BE. This inaccuracy connects
directly to the §1 contract gap: because the spine mischaracterizes the
starting state, it undersells the actual required change — adding `area` as
its own optional `CreateCustomerDto` field *and* removing the FE's
concatenation workaround, which nothing in the spine currently mandates.

**AD-1 has a smaller version of the same issue.** The Rule says "PlacesModule
imports only `CacheModule`," implying `CacheModule` is a shared module that
feature modules import (paralleling how `CustomersModule`/`AuthModule`
import `SupabaseModule`). Verified in `app.module.ts`: `CacheModule.register({
isGlobal: true, ttl: 300 })` — it's registered globally at the root, so
`CACHE_MANAGER` is injectable everywhere without any feature module
importing it. Confirmed: `AuthModule` uses `CACHE_MANAGER` (via
`InMemoryOtpSessionStore`) and does **not** import `CacheModule` at all. So
the existing, actual convention is "don't import it — it's already global,"
and AD-1's rule doesn't ratify that; it invents an import that isn't how the
codebase does this today. Harmless if followed (a redundant import of a
global module is a no-op in Nest), but it's a documentation inaccuracy sitting
inside an otherwise-enforceable rule, and worth fixing so PlacesModule's
module file matches AuthModule's actual precedent rather than a assumption
about it.

Everything else ratifies rather than contradicts: AD-2's abstract-provider
DI-swap is a faithful mirror of `OtpDeliveryProvider`; AD-4's role guard
usage matches `CustomersController` exactly; AD-9's error shape matches
`GlobalExceptionFilter`'s actual mechanics; AD-10's `getOrThrow` matches
every other required-secret consumer in the codebase.

## 6. Is every dimension this altitude owns decided, deferred, or an open question?

Walked the full set: paradigm/module boundaries (AD-1, decided), external
API surface (AD-2, decided), cost/session model (AD-3/AD-5/AD-6, decided
with one number correctly left open), API contract for the new endpoints
(AD-4, decided), schema (AD-7, decided but incomplete per §1), FE↔BE data
return (AD-8, decided but see §5), error handling (AD-9, decided), secrets
(AD-10, decided).

**Operational/environmental envelope** — checked specifically per the
instructions, since this spans FE+BE and could plausibly need its own
treatment. Confirmed via direct repo inspection that fenzit-be has **zero**
deployment/CI infrastructure today (no Dockerfile, no `.github/workflows`,
no DO App Platform config — AR-18 in `docs/architecture.md` is already
marked ❌ "Not in repo" for the *entire* application, pre-dating this
feature). Given that, the spine's choice to fold `GOOGLE_PLACES_API_KEY`'s
CI/deployment wiring into that pre-existing, already-tracked gap (rather than
inventing environment-specific handling this feature doesn't need yet) is
the right call, not a silent omission — this dimension is genuinely
"deferred with reason," not "left silent."

**Not fully owned:** the FE→BE customer-creation contract (§1) and the
FE-side cost-control discipline (§3's debounce/min-length note) are the two
places where a dimension this altitude should own is under-specified rather
than explicitly decided/deferred/open.

---

## Findings, ranked by severity

1. **(High) Missing FE→BE contract for the amended `CreateCustomerDto`.**
   AD-7 adds six new nullable columns; nothing specifies the request shape
   that actually populates them from `AddressPickerScreen`'s resolved output.
   This is the single most important seam in the whole feature and it's the
   one place the spine doesn't apply AD-4's level of contract rigor.

2. **(High) AD-8 contradicts an existing, simpler brownfield pattern.**
   `TechnicianPicker` (used in `NewJobScreen.tsx`, `EditJobSheet.tsx`) already
   solves "pick from a list, return to a form" via an inline component +
   direct `onSelect` prop — no navigation, no route params. AD-8 introduces
   an unprecedented navigation-based pattern (a function riding in route
   params — no existing route in `RootStackParamList` carries anything but
   plain data) to solve the same problem, for a caller (`AddCustomerSheet`)
   that is itself a bottom sheet, not a screen. The doc's own `[ASSUMPTION]`
   flag undersells this — it's not just an unverified runtime detail, it's a
   pattern choice that contradicts a working precedent.

3. **(Medium) AD-7's stated rationale is factually wrong.** fenzo-app does
   not currently submit a dropped `area` field — it concatenates `area` into
   `address` client-side today (confirmed in `CustomersScreen.tsx`'s own
   comment) precisely because the field doesn't exist. This mischaracterization
   is directly linked to finding #1.

4. **(Medium) FE-side cost control (debounce + minimum query length) is
   under-specified relative to its importance.** The research names it a
   coequal primary cost lever; the spine reduces it to a file comment in the
   Structural Seed rather than a Rule or a Deferred item with an explicit
   number-vs-mechanism split (as AD-6 gets for its rate limit).

5. **(Low) AD-1's rule doesn't match how `CacheModule` is actually consumed**
   (it's global via `isGlobal: true`; `AuthModule` doesn't import it despite
   using `CACHE_MANAGER`). Harmless if followed, but the stated convention is
   inaccurate.

6. **(Low) AD-6's rate-limit key doesn't address `tenantId: string | null`**,
   and the new `AddressPicker` route isn't added to `RootStackParamList` in
   the Structural Seed — both minor, implementation-level gaps adjacent to
   the larger findings above.
