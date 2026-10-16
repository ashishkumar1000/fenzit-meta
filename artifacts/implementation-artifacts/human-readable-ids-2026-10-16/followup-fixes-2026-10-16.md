# Human-readable IDs — review follow-up fixes (2026-10-16)

Closes the three findings left open by the Round-1 edge matrix and Round-2 UI
matrix ([edge-case-report.md](./edge-case-report.md),
[ui-round2-report.md](./ui-round2-report.md)). Two fixed and device-proven;
the third (sheets swallow Android back) closed as **not reproducible** on the
current build after a systematic on-device investigation — details in §3.

Shipped in fenzo-app **210156a** (release APK rebuilt, signed
CN=Fenzit Technology, `adb install -r` onto the Pixel 6 — login preserved).
Full FE suite **3,009/3,009 across 240 suites**, `tsc --noEmit` clean.

## 1. F1 — employee codes are now searchable (all three surfaces)

One definition of search: `filterTechnicians`
(`src/features/technicians/format.ts`) gained employee-code matching on the
digits of the query — `104`, `EMP-104`, `emp104` all reduce to `104`. A
digits-free query (`emp`) deliberately never matches codes: it would match
every technician at once. The shared Edit-job-sheet picker
(`src/components/TechnicianPicker.tsx`) dropped its private name-only filter
and now runs the same shared function, so the New Job picker, the
Select-technicians screen and the Edit-job sheet can never drift apart again.

Device-proven on prod data (103-technician Business tenant):

| Surface | Query | Result |
| --- | --- | --- |
| New Job picker | `002` | Arya (EMP-002) by code + Loadtests matching phone digits — `shots-followup/dp-5-002result.png` |
| New Job picker | `076` | Loadtest H07 (EMP-076) — pure code match, `076` is in no phone — `dp-6-076.png` |
| Browse all | `emp-099` (lowercase) | Loadtest H04 (EMP-099) by code + Y49 by phone digits — `dp-9-emp099.png` |
| Edit-job sheet | `EMP-068` | Loadtest H05 row — the previously name-only picker — `dp-10-editsheet.png` |
| Edit-job sheet | `EMP-002` | Arya, still-ticked selection preserved — `dp-11-arya.png` |

## 2. F2 — codes visible on every picker surface

- New Job picker tiles + shared sheet-picker tiles: `EMP-xxx` caption under
  the name (`dp-3-tech.png`).
- Shared sheet-picker rows: one meta line `EMP-002 · AC Installation & Removal`
  (code and skills joined; no dangling separator when either is absent).
- Browse-all rows: `EMP-002 · +91 1234576890` — mirrors the Technicians-screen
  rows (`dp-8-browse.png`).
- No-match copy is search-generic ("No technician matches **that search**").

## 3. F3 — "sheets swallow Android back": CLOSED, not reproducible

Round 2 (N39) recorded that the Add-technician sheet ignores the hardware
back gesture. Systematic investigation on the SAME release APK could not
reproduce it — back behaves correctly in every posture:

| # | Scenario | Result |
| --- | --- | --- |
| 1 | Sheet auto-opened (`autoOpenAdd`) → back | Sheet closes, screen stays (bk-5) |
| 2 | Manually opened (Add button) → back | Closes (dp-14, new APK) |
| 3 | Keyboard up in Name field → back | Keyboard dismisses only — correct (bk-9) |
| 4 | → back again | Sheet closes (bk-10) |
| 5 | Report-type picker sheet → back | Closes (bk-11/12) |
| 6 | Open + back immediately (present race) | Net state correct (bk-13) |
| 7 | Edit-job sheet → back | Closes, no accidental save (dp-12) |

Most likely origin of the Round-2 note: it was taken with the keyboard up
(N39 also tested "invite disabled until valid", which requires typing) — the
first back dismisses only the keyboard, which reads as "swallowed" if you
stop there. Scenario #3+#4 above is exactly that sequence, working.

Code-level cross-check (TrueSheet 3.11.12 + RN 0.87 Fabric + react-native-screens
4.28): TrueSheet subscribes a JS `BackHandler` while presented and dismisses
natively through it; `Sheet.tsx` additionally wires `onBackPress={() => true}`
while `dismissible={false}` so a guarded parent's back press can't pop the
hosting screen. The chain is intact — no change shipped. A redundant
app-level `BackHandler` was considered and rejected: it would race
TrueSheet's own dismiss path for zero observed benefit.

## 4. Tests

- New: `src/features/technicians/__tests__/format.test.ts` (7 — spelling
  equivalence, digits-free non-match, no cross-match, code-less rows).
- New: `src/components/TechnicianPicker.test.tsx` (3 — captions, `code ·
  skills` join, generic no-match copy, code search from the consumer side).
- Extended: newJob picker suite (+code caption/search case),
  SelectTechnicians suite (+meta-line assertion), root
  `__tests__/technician-picker.test.tsx` (copy update).

## 5. Deliberately out of scope

- A search field on the Technicians screen itself (it has none today) — new
  UI feature, owner's call; the pickers were the documented gap.
- Slow Attendance loads (Render Oregon ↔ Supabase Mumbai RTT) — fix remains
  the Render Singapore migration, owner-executed.
