# Polish log — addendum.md (2026-09-25)

Scope: `addendum.md` only. `prd.md` was not edited. No technical decision, name, path, library, number or recommendation was changed.

## Pass 1 — Structure (bmad-editorial-review-structure): 18 changes
1. Added a "How to read this" note in the intro: §C is the latest; overlapping §A/§B rows point to §C.
2. A0: split the long bold sentence; pointed the SQL distance to §C1 Distance.
3. A2: the library/key detail (react-native-maps, Apple/Google, SHA-1) now points to §C2 Maps. "Architecture to confirm" is kept.
4. A3: pointed to §C2 Location capture contract.
5. A4: kept the (recipient, type, date) unique key; pointed to §C1 Notifications `dedupe_key`; noted that §B1 plans every 5 min.
6. A5, A8, A9, A11: made the §C1 pointers name the exact bullet.
7. A6: condensed the Generalise note and pointed to §C1 Notifications, §C1 Realtime for technicians and §C2.
8. B1: merged the orphan "Tables also needed" row into the main Tables cell.
9. B1: the `notifications` column change points to §C1 Notifications.
10. B1: the realtime-token item now shows the **Blocked** status (§C1).
11. B1: the RPC list gets "holiday change" added (see contradiction 2).
12. B1: the `tenants.timezone` DDL is replaced by a pointer to §C1; the "util" becomes SQL logic (see contradiction 1).
13. B1: the `IdempotencyInterceptor` entry notes that the key is required (§C1).
14. B1: the report-RPC pattern detail is replaced by a pointer to §C1 RPC template.
15. B2: the location hook, notifications, pickers, wizard, month calendar and offline entries point to their §C2 bullets.
16. B2: the office pin picker's Apple/Google detail is replaced by a pointer to §C2 Maps.
17. B2: the `istDate` generalisation is replaced by the §C2 rule (see contradiction 3).
18. B1 Scheduler choice: the dash is split into two sentences.

## Pass 2 — Prose (bmad-editorial-review-prose): 9 changes
1. A6: "Generalise for technician access…" → "Generalise so technicians can use…".
2. C1 RPC template: made the subject explicit ("it takes tenant/actor from the caller…").
3. C1 Idempotency: added the missing subjects ("the result is stored only after the response, and the key is not scoped to the user").
4. C1 Effective-dated rules: "→ needs" → ", so they need".
5. C2 Location capture: "a timeout, returns" → "a timeout, and it returns".
6. C2 Location capture: "(guide to enable precise)" → "(guide the user to turn on precise location)".
7. C2 Enrolment state: removed the stacked brackets ("(not a boolean), plus `attendanceStartDate`").
8. C2 Reuse list corrections: "or extend" → "or extend `TechnicianPicker`".
9. C1 Timezone: "TS util and SQL" → "TypeScript util with SQL".

## Contradictions resolved in favour of §C
1. **B1 "timezone-aware day-range util"** vs §C1 "today computed in SQL only; don't mix a TS util and SQL" → B1 now says "timezone-aware day-range logic in SQL". The existing IST util is still left alone for jobs.
2. **B1 RPC list left out "holiday change"**, which §C1 Stored-procedure count includes → added to B1.
3. **B2 "`istDate` → timezone-parameterised date math"** vs §C2 "show server-provided local dates/times (no client timezone maths)" → B2 now says `istDate` stays as-is for jobs, and attendance uses server-provided dates/times.

Not a contradiction, kept as is: A4 says "per-minute or per-5-minute" (feasibility) and B1 says "every 5 min" (plan). Both are kept, and A4 now points to B1.

## Reference check
FR-1, FR-5, FR-7 (fake GPS; rate limit of 5 in 10 min → 10 min wait), FR-10, FR-27, NFR-10 and NFR-12 were checked against prd.md and are accurate. None were changed.
