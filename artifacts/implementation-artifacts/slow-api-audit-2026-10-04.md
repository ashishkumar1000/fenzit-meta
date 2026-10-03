# Slow-API audit — full production timing matrix (2026-10-04, evening)

Follow-up to `product-perf-sweep-2026-10-04.md`: that sweep identified the
RTT tax as the root; this pass **timed every read endpoint on production**
(owner + technician personas, via CF and direct-to-Render), root-caused each
slow one in code, swept the data for latent bugs, and did a device pass.
Two actions shipped tonight: the leave-list batch fix (BE `a11564c`,
already live) and **API_TIMEOUT 15s → 30s (fenzo-app `ddbc1b6`)**.

## Method

- Probe: OTP flow (master OTP) → Bearer token → 2 warm samples per endpoint,
  `curl -w '%{http_code} %{time_total} %{size_download}'`, sequential.
  Script pattern in the session memory; not checked in (holds no secrets,
  but is throwaway).
- Personas: Ayush (owner, "Business" tenant — 103 technicians, 4 offices)
  and Ravi (technician, same tenant).
- Same requests re-sent **direct to `fenzit-be.onrender.com`** to separate
  the Cloudflare-worker hop from Render time.
- Render free tier was warm throughout (first `health` hit 0.61s — no cold
  start penalised the numbers).

## Timing matrix (warm, seconds; body bytes)

| Endpoint (owner via CF) | t1 | t2 | bytes | Direct-Render |
|---|---|---|---|---|
| `users/me` (boot call) | 2.29 | 2.05 | 42,530 | 1.78–1.93 |
| `attendance/dashboard` (Today) | 6.72 | 6.43 | 2,261 | 6.84–7.70 |
| `attendance/monthly?from=09-01&to=09-30` | 6.33 | 5.82 | 30,611 | 5.54–5.58 |
| `attendance/day-statuses?…30d` | 5.20 | 5.10 | 14,885 | — |
| `attendance/leave` (All page, post-fix) | 2.86 | 3.05 | 9,127 | 2.38–2.39 |
| `attendance/corrections?employeeId=…` | 2.34 | 2.33 | 1,897 | — |
| `attendance/me/summary` | 2.34 | 2.40 | 396 | — |
| `attendance/me/corrections` | 2.44 | 2.24 | 45 | — |
| `attendance/offices` | 2.21 | 1.87 | 1,402 | — |
| `attendance/enrolments` | 2.13 | 1.28 | 37,161 | — |
| `attendance/holidays` | 1.57 | 1.52 | 163 | — |
| `attendance/weekly-off-overrides` | 1.41 | 1.28 | 152 | — |
| `attendance/weekly-offs` | 1.62 | 1.25 | 204 | — |
| `attendance/me/leave` | 1.92 | 1.82 | 45 | — |
| `customers` | 1.22 | 1.20 | 1,446 | — |
| `skills` | 1.09 | 1.02 | 4,308 | — |
| `attendance/setup` | 0.94 | 0.81 | 111 | — |
| `notifications/unread-count` | 0.96 | 0.95 | 18 | — |
| `reports` (list) | 0.98 | 0.87 | 2,483 | — |
| `jobs?scope=history` | 0.99 | 0.94 | 8,856 | — |
| `jobs` (today) | 0.99 | 0.98 | 45 | — |
| `notifications` | 0.83 | 0.83 | 6,831 | — |
| `health` | 0.61 | 0.74 | — | — |

Technician: `me/day-statuses` (19d) 5.20–5.38s · `me/monthly` (30d)
**6.12–6.25s for a 291-byte payload** · others ≈ owner column.

## The floor model (all numbers fit it)

- Base floor ≈ **0.6–1.0s**: CF worker hop + Render auth + ~1 query.
- **Each additional serialised SQL round trip ≈ +0.24s** (Render sits in
  GCP us-west1 *Oregon*; Supabase in Mumbai ≈ 12,000 km). `Promise.all`
  waves do **not** parallelise — node-postgres serialises every query on
  the transaction's single connection.
- **CF worker adds ~0.3–0.5s** per request (consistent CF-vs-direct delta).
- Worked examples: dashboard ≈ 0.7 + ~24 RT ≈ 6.5s ✓ · day-statuses ≈
  0.7 + ~18 RT ≈ 5.1s ✓ · me/monthly ≈ 0.7 + ~19 RT ≈ 6.2s (291 B!) ✓ ·
  leave-list post-fix ≈ 0.7 + ~9 RT ≈ 2.9s ✓.

## Root causes (per endpoint)

1. **Dashboard / monthly / day-statuses / me-monthly (5–6.7s)** — the
   grid readers are *already batched* (13 statements in 3 waves in
   `grid-reader.ts`; dashboard adds flags + office registry). Their cost
   is pure RTT on a serialised connection. No N+1 exists. **Only the
   region move (or fewer statements) helps.**
2. **`users/me` (2.1s, 42.5 KB)** — two sequential REST reads (own row →
   tenant row), then a 6-call wave where `listTechnicians` embeds **the
   entire 103-technician roster in every boot response**. Payload grows
   linearly with headcount — a scaling defect, not just latency.
3. **`attendance/enrolments` (1.3–2.1s, 37 KB)** — unpaginated roster
   (one row per technician, `attendance_access_state` view). Same growth
   shape as users/me.
4. **leave-list (2.9s)** — this IS the post-fix floor (list + count +
   3-statement facts batch). Behavior verified byte-equivalent earlier;
   not worth further code work.
5. **corrections / me-summary / offices (1.9–2.4s)** — ~5–7 serialised
   reads each (existence checks, access row, today resolution). Small
   constant wins possible; region move dominates.
6. **Everything ≤1.1s** — at the floor; healthy.

## Prioritised findings & owner decisions

| # | Finding | Fix | Status / decision needed |
|---|---|---|---|
| 1 | RTT tax: Render Oregon ↔ Supabase Mumbai (~240ms/query) | Move Render service to **Singapore** (rename-cutover plan already delivered) | **Owner executing** — awaiting new service URL to verify before cutover |
| 2 | 15s FE timeout converted 6–9s reads into error cards | API_TIMEOUT 15→30s | **SHIPPED tonight** — fenzo-app `ddbc1b6` (235 suites / 2,972 tests green). Needs next APK rebuild to reach the phone |
| 3 | `users/me` embeds all 103 technicians → 42.5KB boot payload, grows with headcount | Page the roster or ship count + lazy fetch (BE+FE contract change) | **Owner decision** — do before headcount grows a few× |
| 4 | Grid readers: 13 statements serialised per read | Optional BE-only refactor: CTE-merge to 1–3 statements (cuts ~2.5–3s even in Oregon; parity-test heavy) | **Owner decision** — partly redundant after #1 (Singapore makes each RT ~70ms → dashboard ≈ 2.3s without any code change) |
| 5 | `attendance/enrolments` unpaginated (37KB at 103 techs) | Add cursor pagination (BE+FE) | **Owner decision** — same trigger as #3 |
| 6 | CF worker adds 0.3–0.5s/request | None (it fronts api.fenzit.com TLS; keep) | Informational |

## Bug sweep (same night) — nothing new

- `report_requests`: 0 stuck, 0 failed (12 rows in `ready` = terminal
  success state — first query's "in-flight" was my filter's bug, not the
  product's).
- Leave: the 1 pending request in the DB belongs to tenant "Raj
  Electronics", not Ayush's — Ayush's empty Pending tab is **correct**;
  tenant isolation verified end-to-end.
- `attendance_attempts`: 232 total, 2 unacknowledged mocked — healthy.
- jobs overdue (status column): 0. Home tile showed "Overdue 4" — that's
  the *scope* (past-due non-terminal jobs), not the status column; the
  Jobs list is the source of truth, no contradiction found on device.
- 527 unread notifications — loadtest/QA hygiene, already parked as an
  owner-policy call (with the H01–H10 data).

## Device pass (Pixel 6, prod APK c742a0b — still the 15s build)

- Home → Attendance hub: instant; plain-English copy everywhere.
- Leave Pending: correct empty state (see tenant-isolation note above).
- Leave All: list rendered within 4s — **the batched fix is live on
  device** with real rows (H01–H04, Suresh) and status chips.
- Today: fully loaded by 8s (103 on attendance; buckets sum: 0+103+0+0).
- Monthly: fully loaded by 8s (September 2026, per-employee summaries).
- Screenshots: `shots/d0…d10` in this folder.
- No crashes, no stuck spinners, no visual defects observed.
