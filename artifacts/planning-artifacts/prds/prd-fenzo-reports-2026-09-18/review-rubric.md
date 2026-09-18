# PRD Quality Review — Report Module — Owner PDF Reports (2026-09-18)

Reviewed against `.claude/skills/bmad-prd/assets/prd-validation-checklist.md`. Stakes: solo developer, pre-launch, cross-repo technical capability spec (fenzit-be module + one owner screen in fenzo-app), feeding BMAD architecture and story creation. Calibrated accordingly — rigor light is acceptable, the substance bar is not.

## Overall verdict

This is a strong PRD for its stakes. The engineering decisions are stated as decisions with their costs named (pdfmake over Puppeteer because of the 512 MB free tier, polling worker over a queue because no broker exists, `scheduled_start` filtering with the alternative rejected in an inline assumption), the FRs are concrete to the level of status codes, field lists, TTLs and caps, and the extensibility thesis is validated by a dedicated success metric. What is at risk is a narrow band of operational detail: the PRD's only real hole is unbounded report volume inside the *allowed* date range — NFR-2 defines performance for ≤ 1,000 jobs but nothing defines behavior beyond that — plus a handful of underspecified implementation parameters ("short interval", "(and/or list)") that story creation will trip over.

## Decision-readiness — strong

The PRD's decisions are stated as decisions, and the big ones carry their trade-offs. The engine choice is the clearest case: §5.3/FR-6 commits to pdfmake "behind a `PdfRenderer` port", and addendum §1 gives the honest cost table — pdfmake's "no CSS" limitation is named, not hidden, and the Chromium OOM math on the free tier is the reason. The queue-vs-table decision in addendum §2 is likewise reasoned ("no existing job system in fenzit-be; free tier can't run one") rather than presented as free. The data-modeling call — filtering on `scheduled_start` versus activity events — is acknowledged as an assumption with the alternative explicitly rejected as "heavier and ambiguous" (§4), which is exactly the shape the rubric wants: a decision with its rejected alternative visible.

Open Questions are genuinely open: the single `[OPEN]` in §10 (attachments/photos inline in future reports) has no answer smuggled next to it. The resolved logo question is even marked with its resolution date, showing the open-items list is being maintained, not decorated.

One tension goes unflagged: NFR-2 promises "< 10 s on the free-tier instance" while addendum §1 states the free tier runs at 0.1 CPU and pdfmake costs 30–50 MB during render. These are probably compatible, but the PRD never acknowledges that the 10 s budget sits on the weakest CPU it will ever run on — the kind of spot where a `[NOTE FOR PM]` or a measured target would earn its place.

### Findings

- **low** Free-tier CPU vs generation-speed claim (NFR-2, addendum §1) — "< 10 s … on the free-tier instance" sits against a documented 0.1 CPU and is never flagged as a tension or backed by a measurement. *Fix:* mark it as a verify-in-test item or soften to "in the low tens of seconds on the free tier, measured."

## Substance over theater — strong

Nothing here is furniture. The Users table (§2) has three rows and every one drives a requirement: Technician → "No access. Reports are owner-only" → FR-9's "technician role gets 403"; Future/platform → NFR-5 and NFR-6. The Vision (§1) is unswappable — "summary numbers up top, a per-technician breakdown below" and "registering a new definition, not a new project" are specific to this product. The NFRs are product-shaped thresholds, not boilerplate: 512 MB free-tier ceiling, ~50 MB render memory, 92-day range cap, 3 in-flight per tenant, 10-minute presign TTL. Even the claimed architecture is honestly de-novelized — addendum §2 opens by admitting the registry/strategy/pipeline pattern is "standard across report engines", so no innovation theater. The one paragraph that could be accused of theater is the §4 layout description, but it is load-bearing: it is the de facto acceptance spec for the first report's content.

### Findings

(none)

## Strategic coherence — adequate

There is a thesis and it is unusual for a PRD of this size: the first report is a vehicle for a *pluggable engine*, and the PRD never loses sight of it. Scope kind is platform — §0 ("pluggable report engine", "structurally independent") — and the scope logic matches: FR-T1/T2 (brand kit + per-type template), FR-5 (registry), NFR-5 (extraction seam), NFR-6 (extensibility contract) all exist to serve the thesis, and §8's growth path shows the thesis paying out in four concrete directions. Success Metric 3 — "a second report type is added with **zero** changes under `src/reports/engine/`" — validates the thesis directly rather than measuring activity.

Where coherence is thin is in the metrics' rigor. All three SMs are binary validation checks (can open in 60 s / zero cross-tenant reads / zero engine changes), which is defensible pre-launch, but SM-1's "p95 well under that" is unmeasurable as written, and no counter-metric guards the extensibility bet. SM-3's "zero changes to the engine" is gameable — a definition file can absorb arbitrarily much complexity to keep the engine pristine — and a counter-constraint ("definitions stay under N lines / engine stays testable in isolation") would catch the failure mode where extensibility is preserved in letter and lost in substance.

### Findings

- **medium** SM-1 "p95 well under that" is unmeasurable (§9) — "well under" has no threshold, so the metric cannot fail. *Fix:* give a number (e.g. p95 ≤ 45 s) or drop the qualifier and keep 60 s as the bar.
- **low** No counter-metric for the extensibility bet (§9, NFR-6) — SM-3 can be satisfied by bloating definitions while the engine "changes zero lines". *Fix:* add a counter-constraint, e.g. "the second definition adds no shared state and no new cross-module imports."

## Done-ness clarity — adequate

This is the PRD's strongest surface at the FR level and its weakest at the parameter level. Most FRs are genuinely done-able: FR-1 specifies the route, role, validation rules (max range 92 days, start ≤ end, not in the future), the absent/empty-means-all semantics, the 201 shape, and idempotency behavior; FR-2 lists the exact response fields, the presign TTL and its config source, and the 404 cross-tenant behavior; FR-7 enumerates every column, the RLS posture, and the atomic claim with its `PT<status>` SQLSTATE convention. §4's layout list plus the on-time formula (`completed_at` ≤ `scheduled_end`) is a workable acceptance spec for the report content itself. The NFRs have bounds, not adjectives.

The gaps are all "the last parameter is missing" gaps. FR-11 polls "on a short interval" — no number, and the addendum notes polling is "new pattern (first in app)", meaning there is no existing convention to inherit, so the interval and its stop conditions are exactly what a story needs from the PRD. Worse, FR-11 says the feature "polls `GET /reports/:id` (and/or list)" — an "and/or" is a decision the PRD declined to make, on a mechanism it is introducing. And the biggest hole: NFR-2 scopes performance to "≤ 1,000 jobs", NFR-3 permits a 92-day range over all technicians, and nothing says what happens when those combine into several thousand jobs — no row cap, no truncation, no slow-path behavior, no error. An engineer implementing FR-4 has no defined "done" for the heavy case, and it is the realistic case for the feature's heaviest users.

### Findings

- **high** Report volume inside the allowed range is unbounded (§4, NFR-2, NFR-3) — NFR-2 defines "< 10 s" only for ≤ 1,000 jobs; NFR-3's 92-day all-technician request can exceed that with no defined behavior (cap, truncate, paginate the table, or fail with a code). With concurrency capped at 1 (NFR-1), one oversized request also blocks every other tenant's report. *Fix:* add a volume bound — e.g. a max-jobs guard in FR-1 with a dedicated error code, or an explicit "render the first N jobs per technician + count overflow" rule in §4.
- **medium** FR-11 polling is underspecified — "short interval" with no value, and "(and/or list)" leaves the polling mechanism undecided. This is a first-of-kind pattern in the app (addendum §4), so there is no convention to lean on. *Fix:* pin interval (e.g. 5 s, capped attempts) and pick one: poll the list endpoint while any item is non-terminal.
- **low** FR-3 pagination shape incomplete — keyset pagination and the envelope are named but page size and cursor semantics are not. *Fix:* one line ("page size 20, cursor = last created_at+id").
- **low** FR-4 error codes promised but not enumerated — "a stable `error_code`" and "add error codes to `error-code.enum.ts`" (addendum §3) leave the set open. *Fix:* enumerate the v1 set (e.g. range-too-long, in-flight-limit, render-failed, upload-failed) — the FR-13 mapping depends on it.
- **low** "photos + signatures captured" counting undefined (§4 summary card) — attachment counts come from `attachments`, but which attachment types count toward this figure is unspecified. *Fix:* state it (e.g. `type IN ('photo','signature')`).

## Scope honesty — strong

Scope is explicit at both ends. §3's Out-of-scope list is real work, not a formality: deferred items come with the reason or the unlock condition (charts "unlocked with the Puppeteer renderer swap, §8"; retention "policy added later"; push deferred in favor of "polling + the existing Realtime-backed in-app notification"). Assumptions are tagged inline where they are made (§4's `scheduled_start` filter) and indexed in §10, with the revisit condition attached ("revisit only if owners ask"). The one-PDF-vs-per-technician assumption even states the trigger for revisiting. Open-items density is low (4 assumptions, 1 open, 1 resolved) and appropriate for a low-stakes pre-launch PRD — nothing here reads as an unresolved blocker dressed as a note.

Two small silent omissions: there is no retry-a-failed-report or delete-from-history behavior anywhere (is regeneration just a fresh request? is history ever pruned?), and FR-12's reliance on a "system PDF viewer" existing on the test devices is an untagged assumption rather than an `[ASSUMPTION]` — pre-launch solo dev makes both cheap, but the second one is discoverable only at test time.

### Findings

- **low** Retry/delete behavior for failed or old reports never addressed (§3, §5.1) — presumably "generate a new request", but the PRD never says, and history growth is tied to the deferred retention policy. *Fix:* one line in §3 or §10: "no delete/retry in v1; regenerating = a new request."
- **low** System PDF viewer availability on Android is an untagged assumption (FR-12) — `Linking.openURL` on a presigned URL assumes a viewer app exists. *Fix:* tag as `[ASSUMPTION]` with the graceful-failure toast as the fallback, already specified.

## Downstream usability — adequate

This PRD will feed architecture and story creation, so this dimension is weighted, and it mostly earns the weight. Terms are defined at first use and used consistently — "definition", "brand kit", "template", "port", "registry" each get a defining sentence (FR-T1, FR-T2, FR-5, FR-6) and never drift afterward. FR IDs are unique and complete (FR-1..13 plus FR-T1/T2), § cross-references resolve (§8, addendum §6), and each FR carries enough context to be lifted alone into a story — FR-7 restates its SQLSTATE convention inline rather than pointing elsewhere. The addendum is explicitly framed as "downstream inputs for `bmad-architecture` / story writing" and its recon of existing patterns (§3, §4) is exactly what a story-writer needs.

Two deductions. There is no Glossary, and this spec leans on a genuinely novel vocabulary ("definition unit", "brand kit", "renderer port", "claim semantics") — first-use definitions mostly cover it, but a story pulled out of context loses the engine/definition boundary that the whole PRD bets on. And the addendum's own numbering is scrambled (sections run 1, 2, 3, 4, 6, 5 — "Sources" is §5 but appears after §6), which the PRD's "see addendum §6" reference navigates past, but which will confuse any tool or agent extracting addendum sections by number.

### Findings

- **low** No Glossary section (§ front matter) — the engine/definition/brand-kit/port vocabulary is the PRD's core contract and is only defined in prose. *Fix:* a 6–8 term glossary under §2 or §3.
- **low** Addendum section numbering out of order (addendum §§ run 1,2,3,4,6,5) — PRD cross-refs resolve, but section-by-section extraction breaks. *Fix:* renumber Sources as §7.

## Shape fit — strong

The shape matches the product. This is a technical capability spec with one owner-facing screen, and it is written as one: capability-first FRs for the backend, flow-first FRs for the screen, no UJ theater. The absence of a User Journey section is the right call — the single journey (request → generating → ready → open PDF) is fully told inside the Vision paragraph and FR-10..FR-13, and inventing a UJ section for a solo-operator flow would have been over-formalization. Brownfield obligations are met: every existing-code reference checked out as specific and plausible (`IdempotencyInterceptor` + 24 h replay, `PT<status>` RPC convention via `confirm_attachment`, `OwnerRealtimeBridge`, `MultiSelect`, `utils/istDate`, `PaginatedResponse` envelope), and the new-vs-existing line is kept clean (FR-4 explicitly notes the backend uploads itself, unlike the client-upload attachments flow). Chain-top obligations are also met — addendum §3/§4 exist precisely so architecture and stories can source-extract. No over- or under-formalization to flag.

### Findings

(none)

## Mechanical notes

- **Glossary drift:** minimal. "report definition" / "definition unit" (FR-5 vs §0) are used interchangeably once each; "template file" vs "report template" likewise. Harmless, but the glossary suggested under Downstream usability would settle them.
- **ID continuity:** FR-1..13 + FR-T1/T2 — unique, no gaps, no dangling references. The T-suffix numbering inserted between FR-3 and FR-4 is unusual but self-explanatory.
- **Assumptions Index roundtrip:** clean. Four `[ASSUMPTION]` tags in §10 plus the §4 inline one, which is duplicated in §10 (acceptable — one is the point-of-use, one the index). The resolved logo item is appropriately marked "resolved 2026-09-18" with its destination.
- **UJ protagonist naming:** n/a — no UJ section, correctly for this shape (see Shape fit).
- **Addendum structure:** section numbering scrambled (1,2,3,4,6,5); §6 "Brand assets" appearing before §5 "Sources" reads as an editing artifact. Low impact, easy fix.
- **Required sections for the stakes:** Vision, Users, Scope, FRs, NFRs, Growth Path, Success Metrics, Assumptions/Open Questions all present and populated. No Acceptance Criteria section, but FR-level testable consequences largely carry that role here (Done-ness findings list where they don't).