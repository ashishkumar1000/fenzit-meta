# Adversarial Review — Report Module PRD (2026-09-18)

Reviewer: adversarial general review (pre-architecture).
Inputs: `prd.md`, `addendum.md`.
Verdict up front: **conditional go.** The isolation story (FR-9, RLS, tenant-scoped presign) and the pluggability story (FR-5/FR-6, NFR-6) are genuinely well thought through, and I could not break tenant isolation through the documented API surface. But the PRD has a **critical liveness hole in the state machine** (a crashed worker permanently strands requests and, via the in-flight cap, permanently locks a tenant out of reports), one **Supabase-specific security landmine** around the claim RPC, and a cluster of **data-correctness and contract ambiguities** that will produce different implementations depending on which developer guesses what. Fix the two criticals and the highs before this drives epics.

---

## Critical

### C1 — A worker crash after claim strands the request forever — and the in-flight cap then locks the tenant out permanently
- **PRD section:** FR-4, FR-7, NFR-3
- **What's wrong:** FR-7's claim RPC prevents *double-run* ("a crashed worker never double-runs a request") — but the PRD never says what happens to a row left in `generating` when the worker dies after claiming. There is no lease/lock timeout, no stale-claim reaper, no max-attempt counter, no requeue path. `failed` is described as terminal, `ready` is terminal — `generating` with no live worker is a fourth, undocumented terminal state. And the most likely crash source is not exotic: **every backend deploy kills the in-process worker mid-render** (Render restarts on deploy). This will happen routinely, not once a year.
- **Why it matters:** NFR-3 counts `queued + generating` toward the per-tenant cap of 3. Three deploys at the wrong moment (or one deploy plus two crashes) and the tenant has 3 zombie `generating` rows → **every future report request is rejected forever** with no user-visible remedy. The owner sees "Generating…" chips that never resolve and a "cap reached" error on retry. For a solo dev pre-launch this is the single most likely production incident this module produces — and FR-13 has no copy or recovery flow for it either.
- **Fix:** Specify recovery explicitly in FR-7: (a) stamp `claimed_at` (or `locked_until`) at claim time; the poll loop re-claims rows whose lease has expired (`generating` AND `locked_until < now()`), with an `attempt_count` and a max-attempts → `failed` transition; or (b) a startup sweep that requeues all `generating` rows on boot (safe for an in-process worker, since `generating` can only be owned by this process's predecessor). Also decide: does the idempotency replay of a requeued request still hold? State it. Add the zombie-recovery case to NFR-7's integration tests — as written, the test plan only covers happy transitions and isolation.

### C2 — The claim RPC is a Supabase-exposed, RLS-bypassing mutation endpoint unless privileges are revoked
- **PRD section:** FR-7, FR-9, NFR-4
- **What's wrong:** FR-7 puts the `queued → generating` transition in a Postgres RPC with the repo's `PT<status>` SQLSTATE convention — i.e., a Supabase RPC, callable over PostgREST. "Deny-by-default RLS" does not protect here: a `SECURITY DEFINER` RPC (which a claim transition must be, to update rows the caller can't select) **bypasses RLS by design**, and Supabase grants `EXECUTE` on functions to `anon`/`authenticated` by default. Any authenticated user of *any* tenant can call it unless you `REVOKE EXECUTE`. And "tenant-scoped" is ambiguous in a dangerous way: scoped by a `tenant_id` *parameter* (client-supplied, spoofable — pass another tenant's id and claim their rows) vs scoped by the JWT inside the function. The PRD doesn't say which.
- **Why it matters:** This is a genuine isolation hole on the exact requirement the product owner called hard. Even short of data theft, an unrevoked claim RPC lets any authenticated user flip arbitrary tenants' report rows to `generating` (DoS on the report queue, and a vector for the C1 zombie state). The existing `confirm_attachment` precedent may already handle this correctly — but the PRD must *say* the new RPC inherits that discipline, because a story writer reading only the PRD will create the function and move on.
- **Fix:** FR-7 must state: the claim RPC runs as `SECURITY DEFINER`, resolves tenant identity from the JWT (not parameters) or is called exclusively with the service-role key, and `EXECUTE` is revoked from `anon`/`authenticated` if it is service-role-only. Add "RPC privilege audit" to the isolation integration test in NFR-7 (call the RPC as an owner JWT → expect refusal/no-op).

---

## High

### H1 — Unbounded report size: the caps limit the *request*, not the *document*
- **PRD section:** FR-1, §4, NFR-1, NFR-2
- **What's wrong:** The PRD caps the date range (92 days) and concurrency, but nothing caps rows or sections. The worst case is fully legal: 92-day range, empty `technician_ids` = *all* technicians (FR-1), each with a per-technician section containing a full job table. A busy tenant with, say, 80 technicians × 200 jobs in range = 16,000 table rows in **one in-memory pdfmake document**. NFR-2's "< 10 s for ≤ 1,000 jobs" is a benchmark, not an enforced limit — nothing rejects or truncates above it. NFR-1's 50 MB budget was derived from pdfmake's *renderer* footprint, not from a 16,000-row doc-definition plus the fetched job/customer/attachment dataset held simultaneously.
- **Why it matters:** This is the memory-kill scenario NFR-1 was written to prevent, reachable through the normal UI with no abuse at all. It also silently violates NFR-2 (a multi-minute render on 0.1 CPU blocks the concurrency-1 worker for every tenant — see L7). And §9's "PDF within 60 s" metric dies with it.
- **Fix:** Pick and state a document cap: max `technician_ids` per request (e.g. 25) and max jobs per report (enforced at fetch time — e.g. hard stop with a distinct `error_code` like `REPORT_TOO_LARGE`, or per-technician truncation with a visible "showing first N jobs" note). Either is fine; the PRD must pick one. Also state whether "≤ 1,000 jobs" in NFR-2 is a guarantee or a test fixture.

### H2 — On-time % and the summary card are undefined at exactly the edges that matter
- **PRD section:** §4
- **What's wrong:** "On-time = `completed_at` ≤ `scheduled_end`" defines the comparison but not the metric:
  - **Denominator:** on-time % of *completed* jobs only, or of all jobs in range? An owner reading "72% on-time" will assume completed-only; a naive implementation divides by all assigned jobs. Both are defensible; they produce different numbers.
  - **Null `completed_at`:** jobs with `completed_at` set to null (open/cancelled) — excluded from the numerator, yes, but are cancelled jobs in the denominator? And is a job that has `completed_at` but a null `scheduled_end` (data gap) on-time, never on-time, or excluded?
  - **Division by zero:** zero completed jobs in range → "NaN%" / "0%" / "—"? This *will* be hit: a new tenant's first week.
  - **Zero-job technicians:** owner explicitly selects technician X who has no jobs in range — does X get a section with an empty table and zeroed card, or is X silently omitted from a report the owner explicitly asked to include them in? Both behaviors will be reported as a bug by someone.
  - **Summary totals:** "photos + signatures captured" and "distinct customers served" — across all statuses including cancelled, or completed only? "Urgent jobs completed" — what marks a job urgent (a flag? a priority enum?)? The PRD uses the word without defining the source field.
- **Why it matters:** These are the headline numbers of the report. Two correct-looking implementations differ by 20+ points on on-time %, and the discrepancy surfaces months later as "the report is wrong" with no spec to arbitrate. This is exactly the ambiguity class the PRD is otherwise good about ([ASSUMPTION] tags).
- **Fix:** One paragraph in §4: define the on-time denominator, null-handling for `completed_at`/`scheduled_end`, the zero-completed / zero-job renderings, which status set feeds each summary total, and the source field for "urgent". Tag it [ASSUMPTION] if undecided — but decide the *shape* now.

### H3 — The in-flight cap is check-then-insert: two concurrent POSTs beat it
- **PRD section:** FR-1, NFR-3
- **What's wrong:** NFR-3 says further requests are "rejected with a clear error code" when 3 are in flight — but doesn't say *where* the count is enforced. If the service counts then inserts (the natural reading), two simultaneous POSTs (double-tap on flaky network, two owners of the same tenant) both see 2 in flight and both insert → 4, and repeated races can exceed the cap arbitrarily. The repo's own backend guidelines demand concurrency safety via atomic operations; this FR as written doesn't have one.
- **Why it matters:** Weak on its own, but it compounds with C1 (zombies count toward the cap) and with H1 (each extra request is a big render competing for the 1-slot worker). It's also the kind of thing that fails silently — the cap just occasionally doesn't hold, and nobody notices until a Render OOM.
- **Fix:** State the enforcement point: a partial unique index on `(tenant_id) where status in ('queued','generating')` can't express "max 3", so the atomic option is a `create_report_request` RPC/transaction that counts and inserts under one statement, or an advisory-lock around count+insert. One sentence in FR-1 suffices.

---

## Medium

### M1 — Polling contract is "and/or", the list payload omits `error_code`, and tapping a Failed item is undefined
- **PRD section:** FR-2, FR-3, FR-11, FR-13
- **What's wrong:** Three related contract gaps between FE and BE:
  1. FR-11 says the FE "polls `GET /reports/:id` **(and/or list)**" — that's not a spec, it's a coin flip. Polling N individual status endpoints for up to 3 in-flight items vs polling one list endpoint are different loads and different store shapes; the story writer will pick one arbitrarily. No interval is given either ("short interval" — 3 s? 15 s? On a free-tier 0.1-CPU box this matters).
  2. FR-3's history fields (`id, type, range, status, createdAt, completedAt`) omit `error_code`. FR-13 maps per-item error copy "from `ApiError` codes" — but a failed report is a 200 with `status: failed`, not an `ApiError`. The FE cannot render *why* a list item failed without it. Either add `error_code` to FR-3, or spec that the FE fetches `GET /reports/:id` on tap.
  3. FR-12 defines tap behavior only for Ready items. Tapping a Failed item (the most likely thing a confused owner does) is unspecified — open detail? show error copy? nothing?
- **Why it matters:** These are exactly the FE-assumes-BE-doesn't-promise seams that turn into mid-story API churn.
- **Fix:** Pick one polling strategy and a concrete interval in FR-11; add `error_code` (and ideally `params`/technician count) to FR-3's payload; one sentence in FR-12 for failed-item tap behavior.

### M2 — Idempotency replay of a *failed* request returns a stale success forever, and FE key generation is unspecified
- **PRD section:** FR-1, FR-13, addendum §3
- **What's wrong:** FR-1 honours `x-idempotency-key` and the addendum says the interceptor replays the stored create-response for 24 h. Replay of a *failed* request therefore returns the original `201 { status: queued }` — a stale lie — and, worse, the owner **cannot retry through the same key**: any retry with the same key keeps replaying the dead request, and the FE has no specified behavior for generating keys (per screen-load? per tap? regenerated after failure?). If the FE reuses a key across a user-initiated retry, the user is hard-stuck for 24 h.
- **Why it matters:** The PRD treats idempotency purely as duplicate protection and never defines its interaction with the failure path it carefully builds elsewhere.
- **Fix:** State in FR-1: idempotency keys are scoped to first-request-wins (replay returns current row status rather than the frozen 201, if the interceptor supports it — decide), and FR-13 states the FE generates a fresh key per submit attempt (user-visible retry = new key = new request), which also matches the NFR-3 cap story.

### M3 — Terminal-status ordering: upload → mark ready → notify is a three-step dance with no failure assignment
- **PRD section:** FR-4, FR-8
- **What's wrong:** FR-4 and FR-8 each describe their step but never their *composition*: Is the notification insert in the same transaction as the `ready` stamp? If the notifications insert fails (trigger error, transient DB hiccup) after the PDF is uploaded and the row stamped ready — does the pipeline mark the request `failed` (a lie: the PDF exists and is downloadable), retry the insert, or swallow the error? Conversely, the PRD never addresses the mirror case: R2 upload succeeds, the DB update fails → row stuck `generating` (C1) with an orphaned object in R2. The out-of-scope retention line covers *lifecycle policy*, not *failed-pipeline debris* — those are different problems and the PRD shouldn't hide the second behind the first.
- **Why it matters:** Without an ordering rule, the implementation will either produce linkless "ready" rows (explicitly forbidden by FR-4's own last sentence) or flip ready reports to failed, and the owner-visible symptom (notification says failed, history says ready — or vice versa) is confusing.
- **Fix:** One paragraph in FR-4/FR-8: R2 upload strictly before the ready stamp; ready stamp and notification insert in one transaction (or notify-as-outbox, which NFR-5 already gestures at); notification failure after commit is logged-and-dropped (history polling is the fallback UX — say so). For DB-update-after-upload failure, note that the retry (via lease recovery, C1) re-uploads to the same deterministic key `{tenantId}/reports/{requestId}.pdf`, so the orphan self-heals on retry — that property is worth writing down, it's currently implicit.

### M4 — The empty-report case has no contract
- **PRD section:** §4, FR-1, FR-2
- **What's wrong:** A range with zero matching jobs (new tenant, or a filter so narrow nothing matches) is fully legal per FR-1. Does it produce a `ready` PDF of zeros and empty tables, or a `failed` with an error code like `NO_DATA`? The FE has an `EmptyState` for "no reports yet" but nothing for "report generated and it's empty". Also unhandled: the tenant has zero technicians at all.
- **Why it matters:** Whoever implements this picks one silently, and the owner's first experience with the feature (week one, little data) is exactly this case.
- **Fix:** Pick: zero-job selection → `ready` with an explicit "no jobs in this period" page in the PDF (my recommendation — the request succeeded), and say so in §4.

---

## Low

### L1 — Date semantics are under-specified: inclusive end, 92-day counting, and which clock defines "future"
- **PRD section:** FR-1, §4
- **What's wrong:** Is `end_date` inclusive (owner expectation: report *through* the 30th)? Is "max range 92 days" counted inclusively (a "3-month" Jan-1→Mar-31 request is 90 days inclusive — legal — but Feb-1→May-3 is 92 inclusive / 91 exclusive)? And "not in the future" — measured against the server clock (Render runs UTC) or IST? A UTC server rejects a *today* IST range for part of the day, which is a maddening, timezone-shaped bug for an India-only product.
- **Fix:** One line each: end_date inclusive; day-count inclusive; "future" evaluated in IST via the existing `utils/istDate` convention.

### L2 — "Logo if supplied" — supplied from where?
- **PRD section:** §4, FR-T1
- **What's wrong:** The branded header includes "tenant company name and address; logo if supplied" but no FR says which table/field the tenant logo and address come from, or whether one exists today. If the field doesn't exist, the first template story stalls on a schema question the PRD was supposed to settle.
- **Fix:** Name the source (e.g. `tenants.name`, `tenants.address`, `tenants.logo_url`) or state that v1 renders name-only with the styled text band fallback.

### L3 — Notification recipient: *which* owner?
- **PRD section:** FR-8, FR-3
- **What's wrong:** FR-8 says "owner as recipient", but FR-3 makes history tenant-scoped — meaning every owner of the tenant sees every report, including ones they didn't request. So does the notification go to `requested_by` only, or all owners? Both are defensible; silent divergence between the bell and the history list is the confusion.
- **Fix:** Say "requested_by user" (recommended) or "all owner-role users of the tenant".

### L4 — Presign failure at GET-time has no defined shape
- **PRD section:** FR-2, FR-12
- **What's wrong:** `file?` implies optional, but the only stated reason for its absence is non-ready status. If the row is `ready` and the R2 presign call transiently fails, is the endpoint a 500 (mapped to `InlineError` + Retry — losing the row), or a 200 with `file` absent (which the FE could read as "not ready after all")? One line fixes it.
- **Fix:** Transient presign failure → 5xx with a distinct `error_code`; FE retry already exists per FR-13.

### L5 — Single global worker, unspecified poll interval: one tenant's render is every tenant's latency
- **PRD section:** FR-4, NFR-1, NFR-3
- **What's wrong:** Concurrency 1 is a sensible free-tier default (and the cap is config-driven, so this is mild), but combined with an unspecified poll interval and H1's unbounded documents, one tenant's 92-day all-technician report silently delays everyone else's 5-second report past §9's 60 s metric. Pre-launch this is acceptable — but the PRD should own it as a known consequence, not leave it to be discovered.
- **Fix:** One sentence: poll interval default (e.g. 5 s) and a note that head-of-line blocking across tenants is accepted at v1 scale, revisit at NFR-2 violations.

### L6 — Addendum section numbering is scrambled (§6 appears before §5, §5 is Sources)
- **PRD section:** addendum.md
- **What's wrong:** Headings run 1, 2, 3, 4, 6, 5 — "Brand assets & theme tokens" is §6 but sits before "Sources" (§5), and the PRD references "addendum §6" for the logo, which a reader scanning for §6 after §4 will misfind. Trivial, but downstream agents cite these section numbers.
- **Fix:** Renumber to sequential order.

---

## What I checked and am *not* flagging (deliberate scope cuts or already addressed)

- **Presigned URL expiry vs FE staleness** — FR-2 mints fresh per GET, FR-12 re-fetches on tap, FR-8 keeps URLs out of notification payloads. Closed.
- **History list cross-tenant leakage / params smuggling another tenant's technician_ids** — FR-1 validates technician ownership, FR-9 double-scopes reads, list is tenant-scoped. Closed (pending C2's RPC caveat).
- **Duplicate generation on double-submit** — claim RPC + idempotency replay cover the double-run case; my C1 is the *complement* (crash after claim), not a re-claim of it.
- **PDF retention/lifecycle** — explicit out-of-scope, legitimate.
- **Push notifications** — explicit out-of-scope; polling + Realtime fallback is specified on both sides of the contract.
- **Engine coupling for new report types** — FR-5/NFR-6 are concrete (data access via Supabase client, no imports from domain modules); the "duplicate schema knowledge" cost of that independence is a fair trade the PRD consciously made.
- **GET /reports/:id while generating** — `file?` optional covers it; only the presign-failure-on-ready corner (L4) is open.
- **Secret leakage in logs** — FR-4 explicitly requires tenant/request context without secrets.

## Verdict

**Conditional go.** Fix C1 and C2 before architecture (both are one paragraph each in FR-4/FR-7); settle H1–H3 with one decision each before story writing; M1–M4 are one-liners that will save a story-cycle each if written into the PRD now. The pluggable-engine and isolation core is sound — the risk lives entirely in the failure paths and the numeric definitions.