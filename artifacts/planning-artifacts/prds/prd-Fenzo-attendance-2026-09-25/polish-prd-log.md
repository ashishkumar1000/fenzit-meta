# Polish log: prd.md (2026-09-25)

No business rule, number, default, threshold, time, state, scope item or ID was changed. Frontmatter kept (status: draft). All four "(decided by Claude on delegation)" markers and §10 Confirmed Defaults kept.

## Pass 1: Structure (bmad-editorial-review-structure), 12 changes

1. Removed the "*Working title — confirm.*" line under the title.
2. §0: split the long paragraph into a short intro plus 5 bullets (Source, Terms, Numbering, Defaults, Technical notes). Replaced "FR-1 … FR-N" with "FR-1 … FR-28" and noted that FR-27 is under §4.9 and FR-28 under §4.11.
3. FR-5: simplified the validation sentence to what is enforced: both hours values > 0, Half-day hours < Full-day hours, no check against the Office's working hours.
4. Moved the "today's Cancel uses the same Start-time cut-off" line from FR-14 to FR-15, where the Cancel rules live (it still points to FR-14; the delegation marker stays on FR-14).
5. FR-23: the no-push bullet repeated FR-22, so it is now shorter and points to FR-22.
6. §7.1: joined the separate "Office pin set on a map" line into the Offices line.
7. §7.1: removed the separate "Technician notification inbox (FR-27)" line, because the notifications line already lists FR-27. The notifications line now names the inbox.
8. FR-22 table: moved the fake-location row up so the three Holiday rows sit together.
9. §9: fixed the clash with §10 ("listed in §10 for confirmation" changed to "confirmed in §10").
10. Glossary drift: UJ-1 "The other 7 technicians" changed to "Employees"; UJ-1 edge case changed to "Tracked employee" / "Office"; §2.2 changed to "The Owner is not a Tracked employee."
11. Glossary drift: lowercase "employee"/"owner"/"office" changed to Employee / Owner / Office / Tracked employee / Removed employee in FR-7, FR-19 heading, FR-25, FR-28, NFR-1, NFR-3, NFR-4, §3 Weekly off, §4.2, §7.1, §7.2 and UJ-2. "technician" kept where it means the system role (§3 Employee / Removed employee, FR-2, FR-27, FR-28, §4.11, NFR-1, §7.2). Vision and JTBD text (before the Glossary) left in plain words.
12. UJ-5: leave statuses capitalised to match FR-17 (Pending / Approved / Rejected / Revoked / Cancelled).

## Pass 2: Prose (bmad-editorial-review-prose), 17 changes

1. "Realizes" changed to "Realises" (Indian English spelling, 11 places).
2. "optimize" changed to "optimise" (§8 counter-metrics).
3. FR-12: "500 chars" changed to "500 characters".
4. §7.1: "incl." changed to "including".
5. FR-7: rewrote the rejected-attempt sentence to read cleanly ("is still recorded, with Employee, time, coordinates, reason and Office").
6. §3 Owner: "Configures … Not itself attendance-tracked." changed to "Sets up … The Owner is not attendance-tracked."
7. SM-C2: "capped to FR-23" changed to "limited to those in FR-23".
8. NFR-1: "looked at" changed to "reviewed".
9. JTBD: "leave requests" changed to "Leave requests".
10. UJ-2: split the persona sentence; "Andheri office" changed to "Andheri Office".
11. UJ-2: "weekly offs" changed to "Weekly offs".
12. UJ-2: "office pin" / "check-in" changed to "Office pin" / "Check-in".
13. UJ-2: "end time" changed to "End time".
14. UJ-2: "a reminder" changed to "a Reminder".
15. UJ-3: "in-app notification" changed to "in-app Notification".
16. UJ-3: word order fixed ("had cancelled the leave on Wednesday instead").
17. FR-1 / FR-24: "completed" changed to "finished"; "Tracked employees count" changed to "number of Tracked employees".

## Rejected / not applied
- Did not rename or reorder any FR/NFR/UJ/SM. FR-27 stays under §4.9.
- Kept the testable FR bullets that repeat rules in other FRs (for example FR-13 "Leave pending" and FR-10 step 9) so each FR can be tested on its own.
- Left UI strings as they are (for example "Corrected by owner", "You are 600 m from Andheri office").
