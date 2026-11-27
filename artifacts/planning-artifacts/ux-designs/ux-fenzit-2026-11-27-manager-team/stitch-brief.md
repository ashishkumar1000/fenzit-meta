# Stitch brief — Fenzit app: the manager's team (Epic 24 story 24-5)

Grounding rule: every number, name, status and control below exists in the
real `fenzit-be` contract (24-5a / 24-5b) and the app's design system. Do not
add capabilities that are not listed. Do not invent fields, charts, GPS,
org-chart diagrams, "L1/L2" labels, or the word "Technician".

## Product

Fenzit is attendance + job management for small Indian field-workforce
businesses. This is the **Android mobile app** (React Native), used by field
employees (copy: "Employee") and by a manager who is still an employee with a
reporting team. The owner runs the company from the same app.

A reporting tree now exists: each member has one "Reports to". A manager sees
the people below them, decides their leave and pending jobs when they are the
resolved approver, and can apply for leave on a report's behalf. Someone with
no reports sees no team UI at all.

## Visual language (must follow exactly)

- Font: Inter. Sentence case. Plain Indian English. No exclamation marks.
- Primary blue `#1A56DB`; success green `#06956F`; pending/warning amber
  `#D97706`; danger red `#C92A2A`; page background `#F9FAFB`; card `#FFFFFF`;
  text `#111827`; muted `#6B7280`; hairline border `#E5E7EB`.
- Cards: 14px radius, 1px `#E5E7EB` border + soft cool-gray shadow, 16px
  padding, ~10px gaps, single column.
- Buttons: 10px radius, 48px tall; primary = solid blue with white label;
  secondary = white with a hairline border and dark label. Touch targets
  ≥44px. Chips are pills, never capsules of solid primary.
- Status vocabulary is fixed: **Done / In Progress / Scheduled / Cancelled**
  for jobs; leave status chips read **Needs review / Approved / Rejected /
  Revoked / Cancelled**. Pending approval jobs show **Pending approval**.
- Bottom tab bar (only on tab screens): Today · Jobs · Attendance · Profile
  with simple line icons. Pushed screens use a plain app bar with a back
  chevron and a title, no tab bar.
- No gradients, no photographic heroes, no textures, no dark mode.

## Screens to design (all mobile, portrait)

### 1. Your team — Leave segment

App bar: back chevron, title **Your team**.
Below the bar, one muted line: **3 people in your team · You report to
Vikram Rao**.
Segmented control with three equal segments: **Leave · Jobs · People**
(Leave active; sunken gray track, white raised active segment, blue label).

Content (single column of cards):

Card A — actionable pending leave:
- Avatar circle (initials "RK"), name **Ravi Kumar**, caption **EMP-018**.
- Right-aligned amber chip **Needs review**.
- Date row with a small calendar icon: **14 – 18 Sep 2026**, a small neutral
  chip **5 working days**.
- Type tag **Casual Leave**; reason in quotes: **"Family function in Jaipur"**.
- Footer: secondary **Decline** + primary **Approve** (equal width).

Card B — actionable pending leave:
- Avatar "NS", **Neha Singh**, **EMP-027**, amber chip **Needs review**.
- Date row **22 Sep 2026**, chip **1 working day**.
- Type tag **Sick Leave**; reason **"Fever, doctor advised rest"**.
- Footer: **Decline** + **Approve**.

Card C — read-only row (a higher manager sees a lower branch):
- Avatar "AM", **Arjun Mehta**, **EMP-021**, amber chip **Needs review**.
- Date row **25 – 26 Sep 2026**, chip **2 working days**.
- Type tag **Earned Leave**, no reason shown (leave it empty honestly).
- No buttons. A quiet one-line note with a small info glyph:
  **Someone closer to Arjun decides this.**

Empty state is not shown on this screen, but design it on a second artboard
if space allows: a green check glyph, **Nothing waiting for you**,
**Leave requests from your team will show up here.**

### 2. Your team — Jobs segment

Same app bar, same header line, Jobs active in the segmented control.

Card A:
- Top line: **JB-2026-0042** (semibold) + amber chip **Pending approval**.
- **From Ravi Kumar**
- **For Sunrise Apartments** (customer)
- Meta line with a clock glyph: **Wed 12 Nov 2026, 10:30 AM** · **AC
  servicing**
- Footer: secondary **Decline** + primary **Approve**.

Card B:
- **JB-2026-0047**, **Pending approval**.
- **From Neha Singh**
- **For Green Leaf Cafe**
- **Thu 13 Nov 2026, 3:00 PM** · **Electrical repair**
- Footer: **Decline** + **Approve**.

Card C — read-only:
- **JB-2026-0051**, **Pending approval**.
- **From Arjun Mehta**
- **For Lakeview Villas**
- **Fri 14 Nov 2026, 9:00 AM** · **Plumbing**
- No buttons; quiet note: **Someone closer to Arjun decides this.**

### 3. Your team — People segment

Same app bar and header; People active.

A full-width secondary button at the top: **Apply for leave** (with a small
calendar-plus glyph).
Below, a directory list (rows, not cards, grouped in one white card with
hairline separators):
- Avatar "RK", **Ravi Kumar**, caption **EMP-018 · Active** (small green dot),
  trailing chevron.
- Avatar "AM", **Arjun Mehta**, **EMP-021 · Active**.
- Avatar "NS", **Neha Singh**, **EMP-027 · Active**.
- Avatar "KJ", **Karan Joshi**, **EMP-033 · Invited** (neutral chip, muted
  row, no chevron).
A helper line under the button: **Choose a person to apply for.**

### 4. Leave request detail (bottom sheet over a dimmed Your team screen)

A native bottom sheet, rounded top corners, drag handle, title **Leave
request**, close X.

- Identity row: Avatar "RK", **Ravi Kumar**, **EMP-018**, amber chip **Needs
  review**.
- Section: **Dates** — **14 – 18 Sep 2026**, **5 working days**, tag
  **Casual Leave**, split note absent.
- Reason block: **"Family function in Jaipur"**.
- **Balance** strip (compact): three small tiles — **Casual 8 of 12**,
  **Sick 5 of 6**, **Earned 10 of 15**, each with a thin progress bar in blue.
- A quiet secondary line with a people glyph: **Also off on these days:
  Neha Singh and 1 more.**
- Pinned footer: secondary **Decline** + primary **Approve**.

### 5. Member settings sheet — owner (bottom sheet over the roster)

Title **Priya Sharma**, subtitle **What this employee can do with jobs**
(sheet header), close X.

Section head **Reporting manager** (hairline + small caps label):
- Row: label **Reports to**, value **Vikram Rao**, chevron.
- Muted line under it: **Vikram Rao (Owner)** — the chain, nearest first.
- Muted line: **3 people report to them.**
- (If a viewer were chosen, a neutral notice would read: **Viewers can't
  normally see leave or job requests. As a reporting manager, they will see
  their team's and can decide them.** Design it as a soft gray info box.)

Section head **Jobs**:
- Switch row **Can create jobs** (on, blue).
- Helper **They can add new jobs from their app.**
- Switch row **Needs your approval** (off).
- Helper **Their new jobs wait for your approval before being assigned.**

### 6. Invite employee sheet — owner (bottom sheet)

Title **Add employee**, close X. Fields:
- **Name** — **Meera Nair** (filled).
- **Phone number** — **98765 43210** (filled, with a small contacts glyph).
- **Skills** — chips **AC repair** and **Electrical**, plus an **Add skill**
  ghost chip.
- Divider, then an optional row: **Reports to** — value **Not set**,
  chevron; helper **Optional. You can change this later.**
- Primary full-width button at the bottom: **Send invite**.

## Hard constraints

- No fabricated features: no live location map, no GPS tracking, no org
  chart tree, no reporting levels (L1/L2), no emergency contact, no salary or
  payslip data on these screens, no team attendance charts.
- No duplicate entry points or repeated data on one screen.
- Use exactly the copy above (sentence case); do not rename "Your team",
  "Reports to", "Needs review", "Approve", "Decline", "Apply for leave".
- Do not show a bottom tab bar on pushed screens or sheets.
- Do not use the word "Technician"; the person is an employee.
- Keep hierarchy calm: one accent per meaning, generous white space, no
  decorative loops or badges beyond the ones specified.
