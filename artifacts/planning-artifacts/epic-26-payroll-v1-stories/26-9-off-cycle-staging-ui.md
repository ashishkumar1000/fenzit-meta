# 26-9 — Off-cycle staging UI (console)

| | |
|---|---|
| Status | ready-for-dev (card created 2026-11-21) |
| Size | S–M (~2–3 days) |
| Layer | Web (fenzit-web) — BE ships since 23-9; a tiny BE preview-field is a **named follow-up** only if the client estimate proves dishonest |
| Depends on | none (clears the 23-11 ledgered debt) |
| Contract | 05 §6 WI-I · 03 §2.9, §5 · sprint-status 23-9 entry · 04 §screens (Additional Salary UI) |

## Gap (evidence)

The off-cycle API ships complete but the console list is **read-only** — owners can't
stage bonus/deduction lines from the UI (23-11 review defer, ledgered in
deferred-work.md against the memberships.id surface; 03 §2.9 documents the
staged→applied contract). This is the ledgered debt this story clears.

## Scope

1. Add-line sheet: employee picker, signed amount (+ earning / − recovery), tag
   (wage/bonus), note, applies-to-month; hits the shipped API
   (`POST /payroll/off-cycle-lines`, payroll.config, idempotent POST).
2. Validation copy maps the BE's contract exactly: zero amount / negative without
   acknowledgment (inline acknowledgment checkbox), future or below-bound month 422,
   locked month 409 — each as inline copy, never a toast dump.
3. Staged-lines list with source attribution + the shipped re-target action
   (membershipId editable while staged — the owner-decided wrong-employee remedy);
   applied lines immutable → 422 surfaces as "already applied".
4. Impact hint on the sheet: "applies to next run of <month>".
5. **Negative-line preview**: before committing a recovery line, show the 50%-cap
   effect (proportional clamp + recovery roll-forward) in plain English — the owner
   should see "₹X will recover now, ₹Y rolls to next months" before it exists.
6. Staged → run → applied trace visible in one screen (filter by state).

## Out of scope

New BE capabilities (recurring lines = 26-12), bulk CSV import of lines, editing
applied lines (never), per-line approvals (no draft/approve stage in V1).

## Technical approach

- The 23-11 read-only list becomes the state-aware screen; keep its URL-owns-state +
  intent-keyed action idioms.
- Cap preview: estimated client-side from the shipped run-summary recovery block
  (outstandingBefore/After + staged lines of the last run) — labelled an estimate in
  the copy. It must never present itself as the engine's number; if the estimate can't
  be derived honestly, the BE-truth preview field ships as a named follow-up story
  (not silently in this card).
- Copy tone matches the lock/run dialogs (plain-English permanence and consequence
  copy — 23-11 established the pattern).

## Acceptance criteria

1. Stage / edit (amount unchanged keeps acknowledgment) / re-target / delete staged
   lines all reachable; applied lines show immutable state cleanly.
2. Every BE 422/409 has matching inline copy (contract-pinned web tests — 23-11
   lesson: source-verify each code).
3. Negative-line flow shows the cap/roll-forward effect before commit, estimated from
   the shipped run-summary recovery block (client-side); if the estimate proves
   dishonest against engine behaviour, the BE-truth preview field ships as a **named
   follow-up story** — planning stays honest either way.
4. Staged→applied trace filterable in one view; orphaned staged lines (zero-employee
   months) visible with the re-target remedy.
5. Suite green; all static gates.

## Test anchors

- 23-9's journey semantics are the contract (staged-only edits, acknowledgment
  retention when amount unchanged, concurrent-retarget 409 OFFCYCLE_LINE_CHANGED).

## References

Frappe Additional Salary UI affordances (04 §screens: amount, Deduct Full Tax +
Overwrite flags + impact preview — we take the impact-preview pattern; overwrite flag
is LATER); 23-9/23-11 entries in sprint-status for the exact API contracts.

## Risks / gotchas

- The memberships.id surface that blocked 23-11 may have landed since — verify before
  assuming the original blocker still exists.
- The cap preview must never show a number the engine could disagree with — when in
  doubt, BE truth over client math.
- Do not let the sheet allow future months the BE will 422 anyway; disable them
  client-side with the reason.
