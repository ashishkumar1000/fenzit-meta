# Edge-case QA round — human-readable IDs (2026-10-16, 50 cases)

Method: 50 self-designed edge cases across DB trigger semantics, security/RLS, live API contracts, server-rendered PDFs, invite lifecycle, and device UI. Executed on prod (`pnlvreaijzslfymlnoti` + Render BE + Pixel 6) with isolated throwaway-tenant probes and full cleanup. Verdicts logged per case in `edge-case-matrix.md`.

## Tally: 48 PASS · 2 pre-existing findings · 1 REAL BUG (found → fixed → verified)

### The real bug (E44) — FIXED & SHIPPED

`lpad(v_seq::text, 3, '0')` **truncates** inputs longer than the pad width: `lpad('1000',3,'0') = '100'`. At tenant scale ≥1000 employees, the 1000th insert minted `EMP-100` (already taken) and would hard-fail on the unique index. Latent (largest tenant: 104) but genuine.
**Fix**: `20261016000001_fix_employee_code_lpad_overflow.sql` → `GREATEST(3, length(...))`. Applied via MCP; re-proved **through the trigger** (counter bumped to 999 → `EMP-1000`, next → `EMP-1001/1002` under parallel sessions).

### Findings (pre-existing, not this feature's regressions)

- **F1 — codes aren't searchable.** `filterTechnicians` (new-job flow) matches name/phone; the shared `components/TechnicianPicker.tsx` (edit-job sheet) matches **name only** — searching `EMP-002` yields "No technician matches that name." (graceful, live-verified). Enhancement: extend both filters to `employeeCode`.
- **F2 — picker inconsistency**: edit-job sheet is name-only while new-job screen is name+phone — pre-existing, now more visible since codes are displayed everywhere else. (Also: the two pickers don't show EMP codes on their tiles — fine per spec, noted as polish.)

### Notable verifications (highlights)

- **Concurrency**: two simultaneous invites through the live API got distinct sequential codes (`EMP-105/106/107`); two parallel SQL sessions post-fix got `EMP-1001/1002`. No deadlock (counter row-lock is first lock acquired).
- **Never-reuse**: deleted users' codes never re-minted (post-delete insert continued at `EMP-004`/`EMP-108`); a support-SQL clear stays NULL (write-once guard) and a later update re-allocates the NEXT number.
- **Owner lifecycle**: NULL-tenant signup stub → code allocated exactly at tenant attach (EMP-001), mirroring `setup_tenant_for_owner`.
- **Security**: anon sees zero sequences/codes (RLS no-policy), RPC not callable (404), function EXECUTE revoked, exactly one trigger on users. Codes are tenant-visible only — same exposure class as name+phone (accepted by spec).
- **Contracts**: PATCH `/users/me` ignores `employeeCode` (whitelist); technician me/leave + leave previews carry NO code (owner-list-read only, `employeeName` precedent); sync + notification payloads untouched.
- **PDFs**: attendance (`NAME · EMP-NNN` inline ×2 tables + 102 two-line register rows) and job-activity (`Ravi · EMP-104` section title, flags name-only) verified by downloading the real R2 PDFs and extracting text (pypdf).
- **Docs/ordering**: duplicate explicit code → 23505 with the named constraint; NULLs-distinct holds; lpad-1000 regression covered.

### Ops gotchas learned (recorded for future sessions)

- **Render "live" ≠ serving**: after a deploy goes live, traffic can still hit the previous process for minutes — a report generated 6 min after "live" rendered with OLD code; minutes later the SAME deploy rendered correctly. Always re-test after a settle window (or redeploy-probe twice).
- jest must run under node (not `bun run test`); same-statement CTE DELETE can't see CTE INSERT rows; MCP probe trick = `RAISE EXCEPTION` inside DO-block for atomic rollback probes.

### State changes left behind (all intentional)

- BE `a860dae` (lpad fix migration, in repo + applied) and `1ac2f20` (force-deploy chore) pushed; Render redeployed & verified.
- ~8 report rows (ready) from PDF testing sit in the owner's Reports screen — real data, harmless.
- Business tenant counter burned to 108 (invites 105–107 deleted as cleanup; documented gap semantics).
- Phone still logged in as Ayush (owner).
