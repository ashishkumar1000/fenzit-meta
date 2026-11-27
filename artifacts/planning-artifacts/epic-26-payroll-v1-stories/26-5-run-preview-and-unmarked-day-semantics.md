# 26-5 — Run preview (dry-run) + unmarked-day semantics + attendance gate

| | |
|---|---|
| Status | ready-for-dev (card created 2026-11-21) |
| Size | M (~3–4 days) |
| Layer | BE (fenzit-be) + web (fenzit-web) |
| Depends on | after 26-2/26-3/26-4 for richer warnings (preview itself can start earlier) |
| Contract | 05 §6 WI-E · 03 §2.1–2.4, §10.C · 02 §3, §2.2, §8.3 |

## Gap (evidence)

**Enqueue computes AND commits payslips in one step** — the owner sees numbers only
after money exists (03 §10.C/D). There is no unmarked-day surface: Frappe makes it a
first-class setting (`consider_unmarked_attendance_as`, default **Present**,
salary_slip.py:626) and an explicit run gate (`validate_attendance`), field-service
reality is missed punches are constant. Frappe's gate has a verified bug — it ignores
its own unmarked-as setting and counts holidays full-weight, so it can block runs
whose slips would compute fine (gotcha 02-§8.3, payroll_entry.py:1331/:1366): copy the
intent, not the bug.

## Scope

1. **Preview API** — `POST /payroll/runs/preview` (payroll.config): reuses the engine
   compute pipeline with commit disabled. Returns per-employee computed lines, totals,
   skip reasons, warnings, and aggregate employer cost (incl. 26-4 split). Read-only:
   no payslip rows, no lock interaction, no advisory-key writes; audit-tagged
   `preview` (or no audit — decide + pin) so dry runs never pollute the trail.
2. **Web preview step** — the run card gains Preview → per-employee table + warnings +
   totals → Commit (the enqueue button). Frappe's desk flow is built entirely on
   review-before-submit (Payroll Entry draft: Get Employees → Create Slips → review →
   Submit; ui-shots/doc-payroll-entry-*.png).
3. **Unmarked-day semantics** — verify `run-lop.ts` current behaviour first; make
   `unmarked_days_as: present | absent` an explicit tenant setting (default
   **present** — pay silent days, Frappe's default), surfaced as a preview warning
   with counts when non-zero.
4. **Optional gate** — tenant setting: warn-only (default) or block enqueue when
   unmarked days > threshold for any employee; the gate must respect the
   unmarked-as setting and half-day-holiday fractions (no Frappe bug).

## Out of scope

Full draft/approve state machine on the run (LATER — single-operator admin; preview
covers the safety need), hold/release per payslip (LATER), editing computed lines from
the preview (overrides already exist via run_overrides).

## Technical approach

- The engine's compute is already a pure pipeline over (month, config, day-status);
  preview = run the compute to the response shape without the write tx. No advisory
  locks, no unique-slip checks.
- Determinism is the contract: same inputs → preview totals == subsequent run totals
  (pinned by test, journey leg compares preview JSON vs run summary).
- Warnings taxonomy: unmarked-days count per employee, missing PT rule (26-3),
  missing structure, PF exclusion, missing bank details (feeds 26-6's warning block).
- Web: preview results render from the same summary shape the run page already uses
  (no bespoke components); the Commit button stays behind the preview step.

## Pinned decisions (added by review triage 2026-11-21)

1. **Preview audit**: preview writes NO audit rows (it mutates nothing; audit-tagged
   previews would pollute the append-only trail with noise).
2. **Gate threshold**: default 3 unmarked days per employee to trigger the
   block-enqueue gate; tenant-configurable setting. Default gate mode = warn-only.
3. **Preview validation scope**: preview validates month format + first-payroll-month
   bound + future-month rejection only (fail fast on garbage input); cut-off and lock
   checks stay at Commit — preview must preview, not gate-policy.
4. **Absent-mode × checkout_missing**: `unmarked_days_as: absent` flips only genuinely
   unmarked days (no day-status row / no attendance facts); `checkout_missing`
   (tracked check-in, no checkout — currently paid-pending-correction,
   run-lop.ts:71-74) stays paid-pending-correction in absent-mode. Pin with a test so
   absent-mode cannot silently start docking tracked days.

## Acceptance criteria

1. Preview totals == subsequent run totals for identical inputs (determinism test).
2. Preview writes nothing: no payslip rows, no lock change, no staged-line flips; a
   preview followed by a real run produces identical results to a run alone.
3. `unmarked_days_as` setting exists (default present), drives LOP math, and appears
   in month-status/config surfaces; absent-mode passes the 02 §7.6 (8) matrix
   (test_salary_slip.py:188/252 semantics: half-days + unmarked subtract payment days).
4. Warnings render in web with plain-English copy; zero-warning previews show a
   clean "nothing to fix" state.
5. Gate (if enabled) blocks enqueue with a 422 listing the offending employees;
   disabled default never blocks.

## Test anchors

- 02 §7.6 (8) unmarked-as-absent/present matrix (`:188/:252`); (1) mid-joinee clip
  (`:1227`) keeps holding in preview mode.
- Frappe gate bug must NOT reproduce: unmarked-as-respected + half-day-holiday
  fractions in any gate math (02 §8.3).

## References

Frappe: Payroll Entry two-step flow (02 §3); `consider_unmarked_attendance_as`
(02 §2.2, default Present at :626); `for_preview` short-circuit precedent
(salary_slip.py:567-570); gate + bug (payroll_entry.py:1302-1342, §8.3).

## Risks / gotchas

- Engine is a whole-run transaction — the preview path must not construct the write tx
  at all (no savepoints leaking), or preview latency/locks degrade the run.
- Preview on a large tenant = full compute; fine at 200-employee mock scale, but
  response shape should stream/paginate per-employee lines.
- Changing unmarked-day defaults changes money — ship default present (current
  behaviour if verification confirms) and let owners opt into absent; any change to
  the default is an owner decision, not an agent one.
