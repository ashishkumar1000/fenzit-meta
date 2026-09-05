---
name: Fenzo Home — Today & needs attention section
description: Visual design contract for the redesigned Today's jobs section on the Fenzo owner Home screen.
type: feature
status: final
updated: 2026-09-05
product: fenzo-app (owner Home screen)

colors:
  # Inherits Fenzit tokens verbatim — src/theme/index.ts. Listed here are the
  # tokens this section touches; nothing new is invented.
  section.background: "{colors.surfacePage}"        # #F9FAFB screen bg
  card.background: "{colors.surfaceCard}"           # #FFFFFF
  card.border: "{colors.borderSubtle}"              # #E5E7EB 1px
  text.strong: "{colors.textStrong}"                # #111827
  text.muted: "{colors.textMuted}"                  # #6B7280
  status.badges: "{colors.status.<key>}"            # done|progress|scheduled|cancelled|neutral (fg/bg/solid/border)
  urgent.badge: "{colors.status.cancelled}"         # soft tone — red communicates urgency, no new colour
  overdue.accent: "{colors.status.scheduled.fg}"    # amber — pending/attention vocabulary, calm not alarm
  primary.action: "{colors.primary}"                # reserved for the one primary action

typography:
  section.header: "{typography.title} @ fontSize 20"   # matches existing Home section titles
  card.title: "{typography.heading}"                   # 18 semibold — customer name
  meta.row: "{typography.bodySm}" + "{colors.textMuted}"  # 14, icon 15px inline pattern
  strip.label: "{typography.labelStrong}"              # 14 semibold — overdue strip label
  strip.count: "{typography.bodyStrong}"               # 16 semibold — overdue count
  empty.title: "{typography.heading} @ fontSize 16"
  empty.body: "{typography.bodySm}" + "{colors.textMuted}"

rounded:
  card: "{radius.lg}"        # 14
  strip: "{radius.lg}"       # 14 — same card language
  avatar: "{radius.pill}"
  badges: "{radius.pill}"

spacing:
  screen.padding: "{spacing.s4}"      # 16
  section.gap: "{spacing.s3}"         # 12 between header / strip / cards
  card.padding: "{spacing.s4}"        # Card padding="md"
  card.internal.gap: "{spacing.s2}"
  cards.gap: "{spacing.s3}"           # 12 between stacked job cards
  touch.target: "{touch.min}"         # 44

components:
  job.card: "existing JobCard — no visual change, see components section"
  overdue.strip: "NEW OverdueStrip — one compact card, single row"
  empty.state: "existing Card + icon badge pattern (current noJobsCard anatomy)"
---

# DESIGN.md — Fenzo owner Home · Today & needs attention

## Brand & Style

Inherits the Fenzit Design System wholesale — see
`fenzo-app/src/theme/DESIGN_SYSTEM.md` and
`fenzo-app/_bmad-output/planning-artifacts/ui-design-spec.md` §0 (authoritative
token cheat-sheet). This document is a **section delta**: it covers only the
"Today & needs attention" section of the owner Home screen. Flat backgrounds,
no emoji, sentence case, lucide icons at stroke 2, meta-row pattern as
established in JobCard.

Spines win on conflict with any mock or wireframe.

## Colors

No new colours. The section reuses the status palette and one borrowed accent:

- **Overdue strip** uses `colors.status.scheduled.fg` (amber) for its accent —
  the same calm "needs attention" vocabulary the pending-state uses, never
  alarm red. Red stays reserved for the Urgent badge (borrowed
  `cancelled` palette, soft tone) and the danger button.
- **Job cards** carry status badges exactly as JobCard does today.

## Typography

As in frontmatter. One rule: the section header uses the established
Home section title style (`typography.title` @ 20) so it reads as a peer of
"Today's jobs" today — no new header treatment.

## Layout & Spacing

```
┌ section ─────────────────────────────────────┐
│  Today & needs attention        (title @20)  │
│  ┌ OverdueStrip ───────────────────────────┐ │   only when overdue > 0
│  │ ⚠ 2 overdue                    View  ›  │ │   one row, 44px tall
│  └─────────────────────────────────────────┘ │
│  ┌ JobCard ────────────────────────────────┐ │
│  │ …existing JobCard anatomy…              │ │
│  └─────────────────────────────────────────┘ │
│  ┌ JobCard ────────────────────────────────┐ │
│  └─────────────────────────────────────────┘ │
└──────────────────────────────────────────────┘
```

- Gap `spacing.s3` (12) between header, strip, and cards; `spacing.s3` between
  stacked cards (matches Jobs list rhythm).
- The section lives inside the existing Home `ScrollView`, below QuickActions.

## Elevation & Depth

Inherits: Card = `surfaceCard` bg, 1px `borderSubtle`, `shadow.sm`. Nothing new.

## Shapes

Inherits: cards `radius.lg` (14), avatars/badges pill. Nothing new.

## Components

> Visual reference: [mockups/key-home-todays-jobs.html](mockups/key-home-todays-jobs.html)
> — canonical state, unassigned variant, and empty state in one file.
> Spines win on conflict.

### OverdueStrip (NEW)

One compact `Card padding="md"`, single row, height ≥ 44px (touch.min):

| Element | Spec |
|---|---|
| Leading icon | `AlertCircle` 18px, `colors.status.scheduled.fg` |
| Label | `labelStrong`, `textStrong`: "Overdue" |
| Count chip | `bodyStrong`, `colors.status.scheduled.fg` — e.g. "2" (soft bg `status.scheduled.bg`, pill, optional) |
| Trailing affordance | `ChevronRight` 18 `textMuted`; whole row pressable |

The whole strip is one press target → Jobs tab, Overdue scope. It never
renders overdue job rows inline — it is a pointer, not a list.

### TodayJobCard

The **existing `JobCard` unchanged** (§1 of ui-design-spec) with two footer
variants for the dispatch/action-hub behaviour:

| Variant | Footer |
|---|---|
| All cards | Avatar + technician name (BE-enriched, falls back to roster) — as today. Every job has a technician (`technician_id` is NOT NULL), so there is no unassigned variant: the decision to drop "Assign technician" is recorded in the memlog (2026-09-05). |

Header/meta/anatomy, urgent badge, status badge: byte-identical to JobCard.

### Empty state (no jobs today, no overdue)

Existing `noJobsCard` anatomy kept: icon badge (Calendar 24, primarySoft bg,
56px), title "Nothing scheduled today", and — enriched — a one-line body and a
secondary CTA:

- Body: "You're all clear. Overdue or upcoming work shows in the tiles above."
- CTA: secondary Button "Create a job" (size md) — only when technicians
  exist; the first-run screen keeps its own onboarding copy.

## Do's and Don'ts

- **Do** keep the strip a single pointer row — it must never grow into a list.
- **Do** use the amber `scheduled.fg` for overdue attention; **don't** reach
  for red (reserved for Urgent / danger).
- **Don't** add a third badge to a job card header (Urgent + status is the max).
- **Don't** hard-code any colour/spacing — tokens and DS components only.
- **Do** keep every press target ≥ 44px.
- **Don't** render customer/technician names from ids on-device when the
  enriched payload carries them (see EXPERIENCE.md → Data Contract).