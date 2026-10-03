# Leave list N+1 — owner Leave screen never loaded (fixed + shipped 2026-10-04)

## Incident (reported 2026-10-03, owner: "when i click on leave -> all data is not loading")

The owner Leave screen (All tab) always died with "Couldn't load leave requests. Check
your connection and try again." after ~15s of skeletons. Reproduced live on the Pixel 6
(screenshots `leave-check-00/01.png` in session tmp).

## Root cause (fully evidenced)

- `GET /attendance/leave?limit=20` answered **HTTP 200 in 16.4–17.5s** on prod; the FE
  cancels at `API_TIMEOUT = 15000` (fenzo-app `src/config/index.ts`) → the error card.
- BE `LeaveReadService.listTransact` awaited `readSpanFacts` **per row** — 3 SQL round
  trips × 20 rows, strictly sequential (one tx connection cannot pipeline), ~0.85s/row
  on the Render↔Supabase pooler ≈ 17s.
- The SQL itself is innocent: `EXPLAIN ANALYZE` = **1.2ms** (23 requests / 75 day rows).
  Pure round-trip latency, zero index work needed.
- Pending tab was fast only because it had **0 rows** (empty page → no loop).
- The same shared `listTransact` serves `GET /attendance/me/leave` (technician history).

## Fix — BE `a11564c` (fenzo-be main, pushed 2026-10-03 late, deployed 2026-10-04)

Placement per the fix-placement rule: **BE owns it** (FE timeout raise = masking; DB = nothing to fix).

- `leave.repository.ts`: new `readPageSpanFacts` — the whole page's weekly-off overrides
  (employee `any($1::uuid[])`), tenant defaults and holidays in **3 statements** over the
  page's union date range; facts computed in JS with the SAME pickers (superset rows are
  harmless — validity is checked per date). `readSpanFacts` keeps its signature for the
  single-span preview/apply paths; its computation is now shared via `computeSpanFacts`
  (one implementation, no drift).
- `leave-read.service.ts` `listTransact`: per-row loop → one batched call (3 RTs/page).
- FE unchanged. DB unchanged.

## Verification (the user's bar: "test it rigorous… check all parties using this API")

- RED→GREEN: 5 new repository specs (statement contracts + scripted behavior incl.
  override-replaces-default, holiday-wins, cross-employee isolation, same-employee merge,
  empty page). Full BE suite **95/95 suites, 1,512 tests** (+5), typecheck clean.
- Default e2e: the real-DB leave journey suite stays at its pre-existing **26 failures**
  (needs real credentials; red at HEAD before the change) — nothing else regressed.
- Real-PG17 statement proofs via Supabase MCP with the literal page params: 0.09–0.13ms.
- **Byte-equivalence on prod data**: the deployed All-tab response vs the saved
  pre-fix baseline — same 20 rows, same order, ZERO field diffs (incl. `workingDays`,
  the exact field the batch recomputes).
- All API consumers probed live: owner All 17.5s→**~2.8–4.1s**, Pending 2.2s, page-2
  cursor 2.8s (3 rows, no overlap, hasMore=false), technician `me/leave` 3.6s (0 rows),
  technician apply preview `ok:true workingDays:2` 3.6s.
- Device (Pixel 6, Ayush owner): All tab loads + renders, Pending tab empty state
  ("No pending requests / You're all caught up."), tab switching, scroll load-more all
  verified on screenshots.

Remaining ~2–3s is the same per-request pooler floor every endpoint on this deployment
pays (5 RTs × ~230ms + HTTP overhead) — 5× headroom under the 15s timeout. Going lower
would need a single-round-trip SQL function (against the house AD-3 no-new-SQL-functions
amendment) — not taken.
