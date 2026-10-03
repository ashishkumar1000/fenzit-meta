# UX Copy & Design Clarity Review — Criteria (2026-10-03)

Reviewer: Sally (BMAD UX Designer) · Personas: (1) business OWNER, non-technical; (2) field TECHNICIAN, weak English reader.

Sources: [plainlanguage.gov](https://www.plainlanguage.gov) (understandable on first read), [NN/g error-message guidance](https://www.nngroup.com) (plain problem + fix + no blame, no codes), [CSCW low-literate smartphone UI guidelines](https://programs.sigchi.org), [inclusive UX tips — JetSoftPro](https://jetsoftpro.com), [Kompassify microcopy](https://kompassify.com), [Uxcel mobile accessibility](https://uxcel.com).

## The checklist (what every screen is judged against)

**Language**
- L1. Understandable on FIRST read by the persona; everyday words; no jargon, acronyms, idioms (geofence, GPS, sync, punch, payload, presigned URL, idempotency, enrolment, regularized…).
- L2. Short sentences; one idea per sentence; front-load the meaning.
- L3. Error messages: say WHAT happened in plain words + WHAT to do next; never blame; never show codes, field names, formats (UUID v4, ISO-8601, YYYY-MM-DD, bytes).
- L4. Buttons verb-driven and specific ("Add customer", not "Submit"); same action = same label everywhere.
- L5. ONE word per concept across the whole app (Fenzit/Fenzo, skills/job types, punch/check-in, technician/employee/team member, Sep/Sept, In Progress casing).
- L6. Numbers/dates/units friendly and unambiguous (metres with context, no raw bytes, consistent date formats, no 24h-only times for consumers).
- L7. Outcome over mechanic ("no more paperwork", not "verified via GPS fix age < 30s").
- L8. Reading level suited to weak-English readers (CEFR ≈ A2–B1); avoid British-legal register ("Effective from", "enrolment").

**Design clarity**
- D1. One obvious primary action per screen; clear visual hierarchy.
- D2. Icons never alone for meaning — pair with labels (low-literacy users).
- D3. Empty states explain what this screen is for + what to do next.
- D4. Confirmations state the consequence before the irreversible action.
- D5. Status words/colors consistent across screens (status vocabulary audit).
- D6. Trust/privacy: the app explains WHY it needs location (technicians' fear: being tracked all day).
- D7. Fresh-user path: from login, is the next step always obvious?

## Scope
- All 45 FE screens (inventory: `screen-inventory-FE.md`), BE-originated text users see (~175 API errors, 2 PDF reports, notification payloads — `screen-inventory-BE.md`), verified on-device (Pixel 6, production build) as owner and technician.
