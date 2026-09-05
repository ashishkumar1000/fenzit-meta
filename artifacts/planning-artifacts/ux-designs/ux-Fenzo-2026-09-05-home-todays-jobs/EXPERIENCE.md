---
name: Fenzo Home — Today & needs attention section
description: Behavioral contract (IA, states, interactions, data) for the redesigned Today's jobs section on the Fenzo owner Home screen.
type: feature
status: final
updated: 2026-09-05
product: fenzo-app (owner Home screen) · fenzit-be (/users/me)
---

# EXPERIENCE.md — Fenzo owner Home · Today & needs attention

## Foundation

- **Form factor:** mobile only — React Native (0.86) owner app, portrait.
- **UI system:** Fenzit Design System (`src/theme/DESIGN_SYSTEM.md`) +
  `ui-design-spec.md` §0/§1. Visual identity reference: [DESIGN.md](DESIGN.md) —
  this file owns behaviour only.
- **Persona:** Kamlesh, the owner (Multi Business Partner) — morning dispatch,
  between site visits, end-of-day review.
- **Day logic:** all day windows are IST (the app's established convention —
  backend day-buckets are exclusive IST; frontend formatting uses IST).

## Information Architecture

Home (owner, established account) gains one redesigned section between
QuickActions and the bottom tab bar:

```
Home
 ├─ HomeHeader (greeting + KPI tiles — unchanged)
 ├─ QuickActions (unchanged)
 └─ Today & needs attention            ← THIS SECTION
     ├─ OverdueStrip       (conditional: overdue > 0)
     ├─ TodayJobCard[]     (jobs scheduled today, sorted by scheduledStart)
     └─ Empty state        (conditional: none of the above)
```

- Section replaces the current static "Nothing scheduled today" card.
- The KPI tiles above stay the count surface for Upcoming/Completed/Cancelled;
  this section never duplicates their content.
- First-run accounts (no technician or no jobs) keep their existing
  simplified Home branch untouched.

## Voice and Tone

Calm, factual, sentence case, no emoji — the app's established voice. The
section never scolds ("you missed…"), it orients ("2 jobs need attention").

| Surface | Copy |
|---|---|
| Section header | Today & needs attention |
| Overdue strip label | Overdue |
| Empty title | Nothing scheduled today |
| Empty body | You're all clear. Overdue or upcoming work shows in the tiles above. |
| Empty CTA | Create a job |

## Component Patterns

### OverdueStrip

- **Visible** only when `jobCounts.overdue > 0`. Hidden (not disabled) otherwise.
- One press target: navigates to Jobs tab, Overdue scope (same one-shot
  `scope` param pattern the KPI tiles use).
- Renders a count, never names — the strip stays one row at any count.

### TodayJobCard

- Rendered per job scheduled today (status `scheduled` or `in_progress`;
  completed/cancelled jobs drop out of today's view).
- Sorted by `scheduledStart` ascending; jobs without an end time sort before
  timed jobs in the same slot.
- **Press → Owner Job Detail** (existing route). Single action per card.
- **Footer** always renders avatar + technician name — `technician_id` is NOT
  NULL in the schema, so unassigned jobs cannot exist and there is no
  "Assign technician" affordance (decision recorded in the memlog, 2026-09-05).
  Reassignment stays in Job Detail → edit sheet, as today.
- **In-progress**: the status badge communicates it; no extra progress bar
  inside the card (workflow detail belongs to the detail screen).

### Empty state

- Shown when no today jobs AND `overdue === 0` (strip hidden, nothing to list).
- CTA "Create a job" only when the tenant has ≥ 1 technician (matches the
  first-run rule: no technician → can't assign); otherwise body copy only.

## State Patterns

| State | Behaviour |
|---|---|
| Loading (first load) | Existing full-screen spinner — unchanged |
| Refresh over data | No spinner flicker; section updates in place (existing profile store semantics) |
| Refresh failed | Existing dismissible `InlineError` banner; stale section stays usable |
| Empty today, overdue 0 | Empty-state card |
| Empty today, overdue > 0 | OverdueStrip alone — the section never fully disappears |
| Section error only (jobs fetch failed but profile loaded) | Banner + last-known cards; no skeleton inventing rows |

## Interaction Primitives

- Card press: scale 0.97 (existing Card `interactive`).
- Strip press: same interactive Card treatment, 44px min height.
- Press feedback never blocks navigation; navigation is immediate.

## Accessibility Floor

- OverdueStrip announced as "Overdue, 2 jobs. Button." — count + role, not
  "AlertCircle image".
- Job cards keep existing JobCard accessibility; footer "Assign technician"
  is a labelled button, not a styled Text.
- Colour is never the only signal: overdue uses icon + count + label; urgent
  uses a text badge.
- All press targets ≥ 44px; text meets the DS contrast pairs already verified
  (ui-design-spec §2 record).

## Key Flows

**Morning dispatch (Kamlesh, 8:40 AM, before the first site visit).**
1. Opens Fenzo → Home. Greeting, tiles show Today 3 · Overdue 2.
2. Under the tiles: amber OverdueStrip "Overdue — 2 · View". Taps it →
   Jobs tab opens pre-set to Overdue; sees the two jobs, calls one customer,
   reassigns the other to tomorrow.
3. Back on Home, the strip is gone (count refreshed). Three today cards below
   show who goes where: name, time window, technician avatar. One card's
   technician swapped overnight — Kamlesh taps the card → Job Detail → edit
   sheet reassigns to Ramesh → back on Home the footer shows Ramesh's avatar.
   *Climax: the day is fully dispatched in under a minute, without leaving Home.*

**Between jobs (Kamlesh, 2:15 PM, in the field).**
1. Pulls to refresh. A today card flips to "In Progress" — Ramesh started.
2. Taps the card → Job Detail for live workflow progress. Returns; Home shows
   the fresher badge. No list re-fetch churn.

## Data Contract (BE change — fenzit-be `/users/me`)

The section renders from the profile payload. Required deltas:

1. **Day-scoped jobs.** `GET /users/me` gains `jobsScope=today` (query param,
   default `all` = current behaviour, backwards compatible). `today` returns
   the existing `jobs` page filtered to the exclusive IST day window — the same
   mechanics `GET /jobs?scope=today` already implements (Story 3-7), reusing
   `listJobs`'s day-window + cursor logic rather than a parallel implementation.
2. **Enriched rows.** Profile job rows embed the same summaries the job-detail
   embed uses (fenzit-be 3-3 `toDetailResponse`):
   - `technician: { id, name, countryCode, phoneNumber, skills } | null`
   - `customer: { id, name, countryCode, phoneNumber, address, city }`
   This removes the frontend's id→name joins for the Home section (roster /
   customers stores stay the source of truth elsewhere).
3. **Deliberately NOT sent:** activity/attachment counts. Nothing on the
   section displays them; adding wire fields nothing renders is payload for
   payload's sake. If a future design shows them, they join this embed then.

Ordering (cross-repo rule): `fenzit-be` ships the additive change first
(1 + 2 are additive; nothing existing changes shape), then `fenzo-app` consumes.

## Open Questions

- None blocking. (Strip count chip styling — pill w/ soft bg — is a
  [ASSUMPTION] the dev may simplify to plain text "2 overdue" if the chip
  reads heavy at 14px.)