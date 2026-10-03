# Product-wide performance sweep — round-trip tax + remaining slow surfaces (2026-10-04)

Follow-up to the leave-list N+1 fix (`a11564c`): "identify similar issues in the product."
Method: (1) static scan of the whole BE for await-in-loop / per-row query patterns
(for-loops with awaits, `Promise.all` over per-element work, while+await); (2) code audit
of every hit; (3) empirical timing of EVERY read endpoint the app calls, warm, on
production (owner + technician tokens).

## The root finding: per-query round-trip cost, not (only) N+1s

Every DB round trip on this deployment costs ~300–500ms (Render ↔ Supabase Mumbai
pooler path; region co-location unverified). The evidence is a clean linear model:

| Endpoint (warm, prod) | Queries/RTs | Measured |
|---|---|---|
| /jobs (1–2 queries) | ~3 RTs | 0.9s |
| /customers | few | 1.2s |
| /notifications/unread-count | 1 | 0.84s |
| leave list AFTER fix | ~9 RTs | 2.8–4.3s |
| /users/me | few | 2.0–3.2s |
| owner day-statuses (31–62d) | ~17 RTs | 5.3–5.5s |
| tech me/day-statuses | ~17 RTs | 5.2s |
| owner monthly | ~19 RTs | 7.1s |
| tech me/monthly | ~19 RTs | 6.2s |
| **owner dashboard** | ~19 RTs | **6.7–8.5s** |

The leave fix worked because it cut 63 RTs → 9. The remaining slow screens are fully
BATCHED already (dashboard.ts + grid-reader.ts audited: 13–15 queries in 3 parallel
waves, zero per-row loops) — they pay the RTT tax ~19 times. A code fix per screen
cannot beat the floor; the root is infra.

**Highest-leverage fix (owner decision): co-locate the Render service with Supabase
(ap-south-1/Mumbai)** — Render supports the region. At in-region RTT (~2–5ms) every
endpoint above drops to ~100–400ms with ZERO code change. Verify current region in the
Render dashboard (service → Settings → Region); memory says "Render starter".

## Similar-issue list (each verified, none speculative)

1. **Owner dashboard (Home, opens on every app launch): 6.7–8.5s.** Not an N+1 —
   `dashboard.ts` + `grid-reader.ts` are fully batched; ~19 sequential RTs inside one
   transaction (control RTs BEGIN/SET/COMMIT included). Same root as §root.
2. **Owner monthly table: 7.1s; Technician month calendar (me/monthly): 6.2s.** Same.
3. **Day statuses (owner per-employee 5.3s; technician 62-day 5.2s):** same.
4. **jobs.service.ts job detail: per-attachment R2 presign** (`Promise.all` over
   `getPresignedReadUrl` per row). Parallel HTTP (does overlap, unlike pg), bounded by
   attachments per job, degrades one url to null on failure — MINOR, no action now.
5. **report-worker.ts processOne loop:** sequential BY DESIGN (PDF memory; the
   1–2-concurrent render safeguard). No action.
6. **leave-transition.ts cancelLeaveOnDisable per-request loop:** admin-triggered,
   bounded to one employee's own requests, each iteration is a real write + notification.
   No action.
7. **Every trivial endpoint's 0.8–2.4s floor** — the same tax; fixed only by §root.

Static-scan cleanups: the classic per-row-await N+1 class has NO other instance in the
request paths (the leave list was the only one).

## Testing ladder notes (same run)

- Real-DB integration suites run locally now: credentials ARE in fenzit-be `.env`
  (leading-space lines — a line-start grep misses them; that's why they looked absent).
- Leave journey (26 probes): **26/26 PASS with the batched code** — the "26 pre-existing
  failures" were purely the missing-credentials default runner.
- Full integration dir: 8/11 suites pass; the 3 failing (check-in-out, day-statuses,
  reminders; 21 tests) fail IDENTICALLY at pre-fix `efa7c69` (proven via worktree) —
  date/time-sensitive test fixtures (anchor-collision guard throws on some calendar
  days; a midnight worked-minutes off-by-one), never reaching business logic.
