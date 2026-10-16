# Edge-case matrix — human-readable-ids (50 cases, 2026-10-16) — RESULTS

Legend: ✅ pass · ❌ FAIL · ⚠️ finding (works but noteworthy) · ⏭️ n/a-skip. Findings triaged at the end. Full narrative in edge-case-report.md. Final tally: 48 PASS · 2 pre-existing findings (F1/F2) · 1 real bug (E44) found+fixed+verified.

## A. Device UI (read-only) — 8
1. Roster search by NAME still works (regression) — search "Arya"
2. Roster search by PHONE DIGITS still works (regression) — "8985056986"
3. Roster search by EMP CODE — behavior recorded (expected: no match today)
4. Roster code line truncation: long name + code ellipsizes, no wrap/clipping
5. Leave row tap → detail sheet renders (code in row list only, sheet unchanged)
6. Notifications list: cards render jobNumber (existing feature intact)
7. Customer detail → job history rows still show jobNumber (regression)
8. Leave "Pending" empty state unchanged (no stray code text)

## B. Security / RLS / PostgREST (anon key) — 7
9. anon GET employee_sequences → zero rows (RLS no-policy denies)
10. anon GET users?employee_code → only tenant-less rows visible, all codes NULL — no codes leak
11. anon RPC set_employee_code → not callable (404 / not in cache)
12. authenticated-with-no-tenant JWT path: tenant-less users never expose codes (covered by 10 shape)
13. employee_sequences has NO grant to anon/authenticated (catalog check)
14. set_employee_code EXECUTE revoked from public/anon/authenticated (catalog check)
15. trigger is the ONLY trigger on users (no surprise interactions, catalog check)

## C. Live API DTO contracts (owner + technician JWTs) — 12
16. owner GET /users/me → employeeCode = "EMP-001"
17. owner /users/me technicians[] → EVERY entry has employeeCode matching ^EMP-\d{3,}$ (or null)
18. profile jobs embed technician objects do NOT carry employeeCode (out-of-scope shape stable)
19. owner leave list rows carry employeeCode beside employeeName
20. technician /users/me → employeeCode present ("EMP-002" for Ashish/Thriftnest)
21. technician me/leave list → NO employeeCode (me-scope stays without it)
22. leave write/preview responses → NO employeeCode (spec: owner-list-read only)
23. PATCH /users/me {name:"Ayush"} (no-op write) → 200, employeeCode unchanged
24. PATCH /users/me with employeeCode in body → field ignored (whitelist), code unchanged
25. GET /sync (POST) jobs payload → zero employee_code keys (jobs-only surface)
26. notifications GET → payload keeps { job_number, step, technician_name } — no code, unchanged shape
27. roster code uniqueness across the 103-technician response — all distinct

## D. Report PDFs (server-rendered, downloaded + text-extracted) — 5
28. attendance PDF (Business, 1 Oct range) contains "NAME · EMP-…" inline labels
29. attendance PDF day register contains two-line "NAME\nEMP-…"
30. attendance PDF: employees with no code (none in Business today) → name-only fallback (logic asserted via 28/29 absence of placeholders)
31. job-activity PDF section titles contain "NAME · EMP-…"
32. job-activity PDF flag rows still name-only (recorded decision)

## E. DB trigger edges (throwaway tenant, cleaned up) — 12
33. INSERT with tenant_id NULL → employee_code stays NULL (re-verify)
34. INSERT tenant-less then UPDATE to attach tenant → code allocated ON the UPDATE
35. INSERT with explicit employee_code (tenant-scoped) → preserved, counter NOT consumed
36. explicit code colliding with an existing code → 23505 raised, constraint named users_tenant_employee_code_unique
37. counter monotonic: DELETE a user, INSERT new → next code, old code NOT reused
38. UPDATE moving user to a different tenant → code unchanged (write-once), no counter churn
39. UPDATE clearing employee_code (support SQL) → stays NULL while OLD had code (write-once guard) — behavior documented
40. subsequent UPDATE after a clear (OLD NULL) → re-allocates NEXT number (never the cleared one)
41. CONCURRENT inserts same tenant (pg bench via 8 parallel do-blocks) → all distinct sequential codes, no deadlock
42. CONCURRENT inserts across 2 tenants → counters independent
43. two NULL-tenant rows → unique index treats NULLs distinct (no violation)
44. lpad growth: 'EMP-' || lpad('1000',3,'0') = 'EMP-1000' (past-999 format stable)

## F. Invite lifecycle (live NestJS path, cleaned up) — 6
45. single invite (loadtest number) → 201, DB row has next EMP code, counter advanced
46. CONCURRENT invites (2 parallel HTTP) → both 201, distinct codes, no 500s
47. roster/profile reflects new invites with codes on next /users/me
48. duplicate-phone invite (same tenant) → rejected with phone-duplicate error, no user row
49. delete invited test users → codes remain burned; next insert continues past max (never-reuse, live)
50. invite SMS send accepted by MSG91 (response shape) — delivery leg unaffected by trigger

Total: 50. Extra probes beyond 50 allowed if something smells.
