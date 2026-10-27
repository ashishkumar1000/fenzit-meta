---
id: SPEC-whois-v3-dossier
companions:
  - sections.md
sources: []
---

# Whois v3 — data-complete dossier for the super CLI

## Why

Pain + opportunity. The owner uses `super whois` to inspect any person before
dangerous operations, but v2 shows only a slice of what the DB holds (verified
by a schema sweep agent against the 9717331820 fixture). This work makes the
dossier data-complete and visually structured so one screen answers "who is
this person, what do they touch, what have they done" without SQL.

## Capabilities

- **CAP-1**
  - **intent:** Context header — the k9s-style strip (name, kind badges,
    phone, joined, membership, colored rule) anchors every dossier so the
    operator always knows whose file is open.
  - **success:** Rendering any report shows the person's name, kind chip and
    membership on the first two lines, above all data sections.
- **CAP-2**
  - **intent:** Glance strip — btop-style stat tiles (jobs, attendance
    attempts, leave, offices, notifications, audit) give a one-line volume
    read before the detail tables.
  - **success:** The strip renders six labelled, colored tiles with en-IN
    values that match the section counts beneath.
- **CAP-3**
  - **intent:** Data completeness — every user-linked datum the schema holds
    is surfaced somewhere in the dossier (final section list in
    [sections.md](sections.md), per the 2026-10-27 DB research agents).
  - **success:** Re-running the research inventory finds no user-linked table
    whose data is absent from the dossier (rejected tables listed in
    sections.md).
- **CAP-4**
  - **intent:** Role-aware ordering — owner/staff dossiers lead with
    memberships, technician dossiers lead with jobs and attendance.
  - **success:** For an owner report the MEMBERSHIPS section renders before
    JOBS; for a technician report the reverse.
- **CAP-5**
  - **intent:** Grid discipline — tables keep aligned columns that fit an
    80-column terminal (fixed-width boxes, gutters, clipped cells).
  - **success:** A fabricated rich dossier renders with every row on one
    line and headers aligned over columns at 80 columns.
- **CAP-6**
  - **intent:** Semantic color + labels — status colors follow the schema
    CHECK domains and every colored marker also carries its text label.
  - **success:** active/approved/ready render green with their word,
    pending-class amber, removed/failed-class red, all with visible text.
- **CAP-7**
  - **intent:** Headless twin — `super whois <phone>` prints the same
    sections as aligned plain text.
  - **success:** Headless output contains a line per non-empty section title
    matching the interactive section set.
- **CAP-8**
  - **intent:** Honesty preserved — whois stays strictly read-only and the
    shell's key grammar (n / esc / ctrl+c) is unchanged.
  - **success:** No write statement is added by the whois path; existing
    shell tests and smokes stay green.

- **CAP-9**
  - **intent:** Invites graph — both directions of `memberships.invited_by`
    (name, phone, company, role, status), catching dangling invited rows.
  - **success:** For the fixture (who invited Suresh and Vidya) the section
    lists both with live status; a person nobody invited shows no
    invited-them line.
- **CAP-10**
  - **intent:** Leave timeline — per-day states plus the leave_events feed
    (cause, actor, reason, affected dates).
  - **success:** A request with an auto-cancel renders its day chip and the
    cancel event with actor name.
- **CAP-11**
  - **intent:** Attendance depth — attempt forensics (outcome, provider,
    distance, mocked), derived worked hours with open-day flag, and the
    moderations this person authored (corrections with note, override count).
  - **success:** A record with checkout renders computed hours; one without
    renders OPEN; failed attempts (too_far/rate_limited) render in red with
    their outcome word; authored corrections list their employee and note.
- **CAP-12**
  - **intent:** Job + notification depth — jobs carry current step, photo
    count; notifications carry a payload summary and pushed state; identity
    carries email; the company line carries GSTIN/UPI onboarding signals.
  - **success:** A job with photos shows the count; a leave.applied
    notification renders its employeeName/date summary; a tenant with GSTIN
    shows the signal.

## Constraints

- Ink 8 + @inkjs/ui v2 only; no new dependencies.
- whois stays strictly read-only; the Sally honesty contract and the shell
  key grammar (n / esc / ctrl+c) are untouched.
- Source files stay near the ~300-line house limit (the dossier lives in its
  own file).
- Tables must survive values longer than their column (clip, never wrap the
  grid).

## Non-goals

- No drill-down navigation inside the dossier (no sub-screens, no pagination).
- No live refresh; the dossier is a snapshot per lookup.
- No JSON/export output; the headless twin stays plain text.
- No workflow-template step labels (current_step shows the raw key; the
  template join is future work).

## Success signal

Running the whois of the fixture (9717331820) and of a fabricated rich
dossier renders every non-empty section from sections.md, aligned at 80
columns, with the fixture's real data (founder marker, invites Suresh+Vidya,
8 notifications with payload summaries, authored correction and override);
`bun run test:super` and the strict typecheck stay green; the DB research
inventory re-run finds no un-surfaced user-linked data.

## Assumptions

- Assumed the fixture's auth schema stays empty (purge/restore history), so
  the logins figure legitimately reads 0 and the section stays a KV value.
- Assumed Indian-number formatting (en-IN) everywhere numeric.

## Open Questions

- None blocking; workflow-template labels are logged as future work.
