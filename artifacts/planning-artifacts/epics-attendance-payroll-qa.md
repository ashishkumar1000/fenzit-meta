# Epic 25 — Attendance + Payroll QA (web admin, mobile, BE, DB)

Owner-commissioned full-product QA epic (2026-11-20): test the attendance and payroll
flows end to end across all four layers — fenzit-web admin panel, fenzit-app mobile,
fenzit-be API, and the Supabase database — using a purpose-built 200-employee mock
company with deliberately mixed data.

## Mission

1. **Inventory** — recon every attendance + payroll feature that actually ships today
   (BE endpoints + rules, web UI surfaces, mobile surfaces, DB tables/triggers/views)
   and record what is supported vs not.
2. **Mock world** — seed a dedicated mock tenant ("PayrollQA Works", 200 employees)
   with mixed states: full days, half days, LOP-absent, leave (per type), weekly-off
   patterns, holidays, joiners/leavers mid-month, punched-but-missing-checkout, no
   enrolment, no salary structure, and so on.
3. **Test cases** — ≥40 happy path, ≥40 corner cases, ≥40 end-to-end, ≥40 negative,
   written with internet research on industry-standard HRMS coverage, each tagged with
   the layer(s) it exercises (web / mobile / BE / DB).
4. **Execution** — one test case at a time, result documented (PASS/FAIL/BLOCKED +
   evidence). Documentation only — no fixes during the execution wave.
5. **Fix waves** — failed cases triaged and fixed in batches; every fix first states
   FE vs BE vs DB placement (root cause + long-term contract) per the standing rule;
   verify no regression planted while fixing (run the touched suites + re-run the
   affected cases).

## Explicit out of scope

- New features (e.g. shift scheduling, overtime, ESI/PT, payslip email) — test what
  ships; gaps are documented, not built here.
- Repairing the pre-existing e2e baseline reds unrelated to attendance/payroll.

## Stories

- 25-1 — Feature inventory (recon fleet + synthesized capability matrix). DONE 2026-11-20.
- 25-2 — Mock tenant seeding (PayrollQA Works, 200 employees, mixed attendance/leave/payroll data).
- 25-3 — Test-case authoring (4 × ≥40 cases, layered tags, industry research fed in).
- 25-4 — Execution wave: run every case one-by-one, document results in the results ledger.
- 25-5 — Triage + batch fixes of failed cases (placement analysis first, BMAD review before commits).

## Working rules (from CLAUDE.md, binding here)

- No commit without consent; BMAD code review before any commit.
- Execution wave documents only — fixes wait for the wave to finish.
- Fixes state the owning layer before implementing; never weaken an assertion to match
  buggy behaviour.
- bun only; Supabase MCP for DB work; master OTP 1039 for scripted logins.
