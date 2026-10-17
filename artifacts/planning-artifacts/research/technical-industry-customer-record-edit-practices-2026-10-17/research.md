---
title: 'Technical research: Industry practices for editing customer records (CRM/field-service)'
type: 'technical'
topic: 'Industry practices for editing customer records (CRM/field-service) vs Fenzit SPEC-edit-customer'
decision: 'Do our five SPEC-edit-customer choices (live-join display semantics, phone immutability, no audit trail, no delete/archive, silent-strip PATCH) match industry norms — match, deliberate divergence, or reconsider?'
source: 'native run (WebSearch/WebFetch fan-out, 2 rounds, 5 researchers, 1 verifier)'
status: complete
preset: 'standard'
validation: 'normal'
created: '2026-10-17'
updated: '2026-10-17'
claims: 'verified=12 unverified=3 overturned=0 disputed=0'
---

# Technical research: Industry practices for editing customer records (CRM/field-service)

**Decision this research serves:** Do our five SPEC-edit-customer choices (live-join display semantics, phone immutability, no audit trail, no delete/archive, silent-strip PATCH) match industry norms — match, deliberate divergence, or reconsider?

## Executive summary

**The evidence says: no SPEC-edit-customer choice contradicts observed industry practice — three match leading defaults outright, and two are deliberate divergences from those defaults.** The divergences differ in weight: phone immutability is a benign simplification with a one-field escape hatch, while the absent audit trail is the one place the industry's leading default (HubSpot's) is clearly ahead of the spec and worth a planned follow-up. Three findings drive the answer:

1. **Transaction-time freezing exists where identity must be frozen, and only there.** Stripe's Invoice copies name/email/phone/address from the Customer and freezes them at finalization while keeping the live ID reference [1]; QuickBooks behaves the same way — existing invoices are snapshots, and customer edits reach only future invoices [5][6][21]. Our job already freezes the operationally-critical datum (`service_location`) at creation and keeps the job record immutable, while contact fields follow the customer (SPEC-edit-customer, `brownfield.md`) — the same ID-live/copy-frozen split Stripe draws, mapped to field service.
2. **Phone is never the identity in the platforms we compared.** Stripe's Customer object has exactly one unique attribute, `id`; email and phone are ordinary editable attributes [3]. Salesforce Contact phones are ordinary updateable fields [19]; even WhatsApp, where the number is the channel identity, pairs it with a platform-generated ID and treats identity changes as re-verification events [9]. Our phone-immutability decision is therefore a policy simplification of an editable-with-duplicate-check norm — defensible for v1, with a named revisit trigger.
3. **Edit history is table stakes at the leaders.** HubSpot records per-property history for every record, available on all products and plans [13]; Salesforce offers field history tracking as a manual per-object opt-in with a ~20-field default limit [14][17]. Our "no audit trail" non-goal is the one choice below a leading default — and the cheap fix (a who/when/old→new history table) needs no change to `customers` itself.

Biggest caveat: the field-service-native platforms (Jobber, ServiceTitan, Housecall Pro) do not publicly document how a completed job treats the customer's contact fields — two independent researchers found docs silence [8][22] — so the closest analogies are payments/invoicing, not field service. One Salesforce figure set (20-field limit, 18-month retention) is snippet-level and unverified (rate-limited verifier) [14][15].

## Dimension sections

### D1 — Historical transactions vs live customer data: what gets snapshotted

Payment/invoicing platforms freeze identity-bearing fields onto the transaction at a defined moment, and only those. On a Stripe Invoice, `customer_name`, `customer_email`, `customer_phone`, `customer_address`, `customer_shipping`, `customer_tax_exempt`, and `customer_tax_ids` each "will equal `customer.[X]`" only until the invoice is finalized — after finalization the copy no longer updates — while the invoice *also* carries `customer`, a live expandable ID reference to the Customer [1]. QuickBooks Online invoices carry their own bill/ship address fields alongside a required `CustomerRef`, and editing a customer's address affects only future transactions: each existing invoice must be edited individually to show the new address [5][6][21]. The freeze point is explicit and business-meaningful (Stripe: finalization; QBO: invoice creation with overridable copies).

Field-service platforms are publicly silent on the analogous question: no retrieved Housecall Pro, Jobber, or ServiceTitan documentation states whether a completed job keeps the customer's address/phone as of the visit versus rendering the live record [8][22]. The closest analogies are therefore payments/invoicing, and nothing there contradicts our split.

**Verdict vs our spec: match for what matters, with a known middle path.** Our spec freezes the visit-critical data (`service_location`) at job creation and renders contact fields live (SPEC-edit-customer constraints; `brownfield.md`) — the same split Stripe makes (live ID reference plus a frozen copy of what the document needs). If a future requirement demands "address as of the visit" on past jobs, freeze-at-completion is additive (copy contact fields onto jobs from that change forward), so deferring it is low-regret.

### D2 — Phone editability and identity keys

Across every platform checked, the customer record's identity is a surrogate ID, never the phone. Stripe's Customer object describes exactly one unique attribute — `id` — while `email` and `phone` are plain nullable attributes with no uniqueness or identity language [3]. Salesforce's Contact identity is the system-assigned read-only Id; its phone fields (Phone, HomePhone, MobilePhone) are ordinary updateable fields, max 40 characters [19]. HubSpot is the outlier in the other direction: *email* acts as a unique identifier (with `idProperty=email` lookups in the API) — but it is still an editable attribute, not a frozen key [18]. WhatsApp Business Platform — the one system where a phone number genuinely is channel identity — still pairs the business's number with a platform-generated ID distinct from `display_phone_number`, supports migrating numbers between accounts, and treats a *customer* identity change (a number change is one trigger; the docs attribute the hash mismatch to "changed their identity" generally) as a re-verification event: a stale identity hash means non-delivery with error 137000, and Meta's guidance is to "assume the customer's phone number can no longer be trusted" [9]. Shopify demonstrates what a *checked* unique phone looks like when it is one: value-level validation rejecting a duplicate with `{"errors":{"phone":["has already been taken"]}}` [11].

**Verdict vs our spec: deliberate, defensible divergence.** Our phone-immutability decision (edit form read-only, phone absent from the update DTO) is stricter than the norm — every compared platform lets you edit the phone and resolves collisions with a duplicate check, not an immutability rule. The spec's own collision answer (create-time 409 on a unique per-tenant phone, the same mechanism Shopify shows [11]) is exactly the industry mechanism; only the edit path is closed. Revisit trigger: an owner needs to correct a customer's changed number. At that point, enabling phone edits is a one-field DTO change — which is what makes deferring it now low-regret.

### D3 — Audit trails / field history on customer edits

The leaders disagree on default, not on existence. HubSpot records property history for every record — "Changed to" value, date/time, and change source — available on all products and plans, with restore of previous values for UI/import/workflow changes [13]. Salesforce offers field history tracking as a **manual per-object opt-in** with a default limit of ~20 tracked fields per object and roughly 18 months of production retention (longer requires paid Field Audit Trail) [14][15][16][17]. Stripe's public Customer object reference documents no field-level history [3].

**Verdict vs our spec: the one clear divergence.** Our non-goal ("no audit trail or change-history UI") is stricter than HubSpot's default and roughly aligned with Stripe's silence. Nothing in the industry evidence says audit is *required* for a pre-launch single-tenant app — but the range of defaults (HubSpot ships it to everyone [13]; Salesforce makes it a first-class per-object setting [17]) says edit history is expected furniture in this category, and our spec's own ingredients (`updated_at` trigger convention, service-role write path — SPEC-edit-customer `brownfield.md`) make a minimal who/when/old→new history table a small follow-up slice. Recommended: keep it out of the current build, add it as a named backlog item rather than a silent gap.

### D4 — Delete vs soft-delete/archive

Platforms that offer removal overwhelmingly make it soft. Xero archives contacts — they "still show in reports and on any transactions created for them," and new transactions are blocked until restore [7]. Housecall Pro deletes are reversible — "If you delete a customer by mistake, you can restore their profile later" [8]. Stripe is the hard-delete outlier but preserves retrievability: "deleted customers can still be retrieved through the API in order to be able to track their history," with past invoices/charges intact and only future operations blocked [2].

**Verdict vs our spec: match (by omission).** Our spec has no delete at all (SPEC-edit-customer non-goal), and the schema already forbids it where it would matter (`jobs.customer_id ON DELETE RESTRICT`; `brownfield.md`) — there is no deletion path to get wrong. That posture can graduate to Xero/Housecall-style archive when there is a concrete need; no change now.

### D5 — PATCH semantics, unknown fields, concurrency

The standards backdrop is RFC 7386 JSON Merge Patch (unmentioned members untouched, `null` removes, non-object body replaces everything) [20] — but none of the three commercial APIs checked uses its media type. Stripe's update-customer is POST with explicit diff prose: "Any parameters not provided are left unchanged" [4]. Shopify's customer update is a PUT whose docs state no replace-vs-merge or unknown-field rule (and whose REST Admin API is designated legacy as of 2024-10) [11]. GitHub's docs define PATCH only as "updating properties of resources" with per-endpoint bodies [23]. On unrecognized keys specifically, no compared API documents any rule — reject or ignore.

On stale writes: GitHub states verbatim that "Conditional requests for unsafe methods, such as POST, PUT, PATCH, and DELETE are not supported unless otherwise noted" — conditional requests are a read/caching/rate-limit technique only [10]. Shopify documents no concurrency control on customer updates [11]; Stripe's update page documents no precondition either [4]. For offline-first clients, WatermelonDB documents the most fully-specified model: per-column client-wins ("in conflict, server version is taken except for any column that was changed locally"), explicitly content-based rather than time-based, push aborts with all changes reverted if a record changed server-side since `lastPulledAt`, and delta sync runs off server-side per-record timestamps (or version numbers) against the client's `lastPulledAt` [12].

**Verdict vs our spec: match on all three counts.** Silent-strip of non-DTO fields (the house NestJS `whitelist` config; `brownfield.md`) matches the documented lenient stance toward omitted parameters [4]; for unrecognized keys the compared APIs are silent, so strip-and-ignore contradicts nothing. Skipping optimistic concurrency matches every compared API — even GitHub disclaims write preconditions [10] — and our single-owner edit path makes conflicts near-impossible. The `updated_at`-keyed delta sync is the same shape WatermelonDB expects servers to offer (per-record timestamps) [12].

## Cross-dimension insights

- **The universal pattern is surrogate ID + mutable attributes.** Stripe (`id` vs email/phone) [3], WhatsApp (phone-number `id` vs `display_phone_number`) [9], Salesforce (read-only Id) [19], HubSpot (internal record ID, email as a *secondary* unique key) [18] all decouple a stable identifier from every display attribute. Our UUID primary key already does this (SPEC-edit-customer `brownfield.md`); the per-tenant unique phone index is a *dedupe constraint*, not an identity — which is what makes the D2 immutability decision a policy choice rather than a schema risk.
- **Freeze at business moments, not at write time.** The one verified snapshot mechanism (Stripe finalization [1]) freezes when the document becomes legally/operationally final, not when the row is created. Mapped to us: the analogous moment is job *completion*, and freezing there later is additive — which is why the D1 live-join decision is low-regret.
- **Defaults span the industry range, and audit is where the spec sits below the leading default.** HubSpot's no-setup-history end [13], Salesforce's opt-in middle [17], and Stripe's silence [3] bracket the whole range; our non-goal sits at the silent end. Combined with D5's finding that concurrency protection is *not* standard anywhere, the industry's actual "must-have" surface for a customer edit feature is: partial update, lenient unknown-field handling, no preconditions — and optionally, visible history.

## Recommendations

1. **Keep the live-join display semantics (SPEC-edit-customer constraint).** Confidence: high — grounded in [1][5][21] (freeze-at-moment practice) and the additive-freeze low-regret analysis. No spec change.
2. **Keep phone immutability for v1, with the named revisit trigger** (owner needs to correct a changed number). Confidence: high that it diverges from the norm [3][9][19]; the divergence is a conscious simplification, and enabling edits later is a one-field DTO change. Spec non-goal already records it.
3. **Add minimal customer edit history as a named backlog item** (who/when/old→new per changed field). Confidence: medium — the industry-default evidence is strong [13], but pre-launch need is unproven; cost is a small follow-up slice using the repo's existing trigger convention. This amends the spec's "no audit trail" non-goal from "silent gap" to "planned follow-up" — a one-line spec update.
4. **No change on delete/archive** — current no-delete posture + FK restrict is within industry variance [2][7][8]; graduate to archive when a concrete need appears (e.g., duplicate or mistaken customers cluttering the owner's list).
5. **No change on PATCH semantics, concurrency, or sync** — spec constraints validated against [4][10][11][12][20].

## Open questions

- Do field-service-native platforms (Jobber, ServiceTitan) snapshot a job's customer contact fields at visit time? Public docs are silent [8][22]; settling it needs vendor support channels or a trial account, not more web search.
- What is PowerSync's default conflict resolution? Docs URL 404'd this run (new IA); unverified.
- Salesforce field-history figures (20-field limit, 18-month retention) remained snippet-level — verifier was rate-limited; treat as medium confidence until a direct primary read.
- Stripe's *global* unknown-parameter rule (errors/API overview pages) was not fetched; only the update-customer page's silence is evidenced.
- HubSpot phone-field editability was not directly evidenced (identity claim is email-based [18]).

## Source appendix

| # | Supports | Publisher | Pub date | Accessed | Confidence |
|---|---|---|---|---|---|
| [1] | D1 Stripe invoice freeze semantics | [Stripe API reference — Invoice object](https://docs.stripe.com/api/invoices/object) | n.d. | 2026-10-17 | high (verifier direct-read) |
| [2] | D4 Stripe hard-delete-keeps-history | [Stripe API reference — Delete customer](https://docs.stripe.com/api/customers/delete) | n.d. | 2026-10-17 | high |
| [3] | D2 Stripe id-only uniqueness; D3 Stripe audit silence | [Stripe API reference — Customer object](https://docs.stripe.com/api/customers/object) | n.d. | 2026-10-17 | high (verifier direct-read) |
| [4] | D5 Stripe partial-update semantics | [Stripe Docs — Update a customer](https://docs.stripe.com/api/customers/update) | n.d. | 2026-10-17 | high |
| [5] | D1 QBO non-retroactive address edits | [Intuit Community — invoice address change](https://quickbooks.intuit.com/community/reports-and-accounting-5/how-do-i-change-the-address-which-shows-on-my-invoices-69162) | 2020-12 | 2026-10-17 | medium (verifier direct-read) |
| [6] | D1 QBO email edits not propagating | [Intuit Community — emails not propagating to open invoices](https://quickbooks.intuit.com/community/reports-and-accounting-5/i-have-updated-multiple-customer-email-addresses-in-profiles-but-they-are-not-translating-over-to-open-invoices-how-do-i-get-the-email-address-into-existing-invoices-44480) | n.d. | 2026-10-17 | medium |
| [7] | D4 Xero archive semantics | [Xero Central — Archive or restore contacts](https://central.xero.com/0/article/Archive-or-restore-contacts) | n.d. | 2026-10-17 | medium (verbatim via search; third-party corroborated) |
| [8] | D4 Housecall Pro soft delete/restore; D1 field-service silence | [Housecall Pro Help Center](https://help.housecallpro.com/en/articles/2841512-delete-and-restore-customers) | 2026-07 | 2026-10-17 | high |
| [9] | D2 WhatsApp phone id + identity-change re-verification | [Meta Developer Docs — WhatsApp Phone Numbers](https://developers.facebook.com/docs/whatsapp/phone-numbers) | n.d. | 2026-10-17 | high |
| [10] | D5 GitHub no write preconditions | [GitHub Docs — REST best practices](https://docs.github.com/en/rest/using-the-rest-api/best-practices-for-using-the-rest-api) | n.d. | 2026-10-17 | high (verifier direct-read) |
| [11] | D5 Shopify PUT/LWW/legacy; D2 phone-uniqueness error | [Shopify — Admin REST customer resource](https://shopify.dev/docs/api/admin-rest/latest/resources/customer) | 2024-10 | 2026-10-17 | high |
| [12] | D5 WatermelonDB conflict + delta-sync model | [WatermelonDB — SyncImpl](https://watermelondb.dev/docs/Implementation/SyncImpl) | n.d. | 2026-10-17 | high (verifier direct-read) |
| [13] | D3 HubSpot property history all-plans | [HubSpot Knowledge Base — property history](https://knowledge.hubspot.com/records/view-record-property-history) | n.d. | 2026-10-17 | high (verifier direct-read) |
| [14] | D3 Salesforce 20-field limit, edition availability | [Salesforce Help — increase field history limit](https://help.salesforce.com/s/articleView?id=000386871&language=en_US&type=1) | 2026-04 | 2026-10-17 | medium (snippet-level, **unverified**) |
| [15] | D3 Salesforce retention / Field Audit Trail | [Salesforce Help — Field Audit Trail](https://help.salesforce.com/s/articleView?language=en_US&id=xcloud.field_audit_trail.htm&type=5) | n.d. | 2026-10-17 | medium (snippet-level, **unverified**) |
| [16] | D3 retention corroboration | [GRAX — Salesforce field history](https://www.grax.com/blog/protecting-your-data-legacy-unlimited-salesforce-field-history-tracking) | n.d. | 2026-10-17 | medium |
| [17] | D3 Salesforce opt-in setup path | [SalesforceBen — field history tracking](https://www.salesforceben.com/salesforce-field-history-tracking) | n.d. | 2026-10-17 | medium |
| [18] | D2 HubSpot email-as-identifier | [HubSpot Developers — Understanding the CRM](https://developers.hubspot.com/docs/api-reference/latest/crm/understanding-the-crm) | n.d. | 2026-10-17 | medium |
| [19] | D2 Salesforce Contact phone editability, Id identity | [Salesforce Developer Docs — Contact object](https://developer.salesforce.com/docs/atlas.en-us.object_reference.meta/object_reference/sforce_api_objects_contact.htm) | n.d. | 2026-10-17 | medium (snippet-level, **unverified**) |
| [20] | D5 merge-patch standards backdrop | [IETF RFC 7386](https://datatracker.ietf.org/doc/html/rfc7386) | 2014-04 | 2026-10-17 | high |
| [21] | D1 QBO corroboration | [Method — change address on QuickBooks invoice](https://www.method.me/blog/change-address-on-quickbooks-invoice) | n.d. | 2026-10-17 | low (secondary blog) |
| [22] | D1 field-service docs-silence (second researcher) | [ServiceTitan Help — History tab](https://help.servicetitan.com/docs/use-the-history-tab-in-servicetitan-mobile) | n.d. | 2026-10-17 | low (silence finding) |
| [23] | D5 GitHub PATCH definition | [GitHub Docs — Getting started with the REST API](https://docs.github.com/en/rest/using-the-rest-api/getting-started-with-the-rest-api) | n.d. | 2026-10-17 | high |

## Staleness map

Claims classed per the technical pack (patterns ≤ 24 mo; ecosystem/product facts ≤ 12 mo; legacy/designations ≤ 12 mo):

| Claim (ref) | Class | Basis | Re-check by |
|---|---|---|---|
| Shopify REST Admin API legacy designation [11] | ecosystem | 2024-10 designation | 2027-04 |
| Salesforce 20-field limit + 18-mo retention [14][15][16][17] | ecosystem (unverified) | snippet-level 2026-04 | 2026-10 (on first direct read) |
| HubSpot property-history all-plans availability [13] | product fact | current help page | 2027-10 |
| Housecall Pro restore flow [8] | product fact | help article 2026-07 | 2027-10 |
| Stripe/GitHub/WatermelonDB/RFC semantics [1][3][4][10][12][20] | doc-statement/pattern | current refs | 2028-10 |

Earliest re-check: 2026-10 (the unverified Salesforce figures — resolve on the next direct read; they gate nothing in the recommendations).

## Method note

Native headless run, standard preset: 2 rounds, 5 firewall-clean researchers (breadth-first), 1 fresh-context verifier. Of the 12 verified ledger claims, 7 were spot-checked by the verifier (independent source or verbatim direct-read; 1 of its 8 checks came back unverified — the Salesforce figures) and the other 5 rest on direct primary reads made during acquisition. Red-team off per config; digests in `digests/` (one per researcher per round); process log in `.memlog.md`. Comparison against SPEC-edit-customer was performed by the lead only — researchers saw no Fenzit context; Fenzit-internal facts in this report trace to SPEC-edit-customer and its `brownfield.md` companion.
