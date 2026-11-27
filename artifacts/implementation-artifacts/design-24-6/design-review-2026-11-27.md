---
target: Edit Profile section-rail mockups (design-24-6)
total_score: 15
max_score: 40
na_heuristics: 
p0_count: 1
p1_count: 2
target_identity: "file:/Users/admin/workspace/fenzit-meta/workspace/core/frontend/fenzit-web/src/features/admin/components/payroll/EmploymentDialog.tsx"
target_fingerprint: "sha256:2be4b784c24892deccefa720dc2f1013fa5e3a65f48c0c9c34445ae8ee35cece"
target_path: /Users/admin/workspace/fenzit-meta/workspace/core/frontend/fenzit-web/src/features/admin/components/payroll/EmploymentDialog.tsx
timestamp: 2026-11-27T11-14-25Z
slug: n-components-payroll-employmentdialog-tsx-c174ae32
---
# Design critique — Edit Profile section-rail mockups (story 24-6)

Method: dual-agent (A: independent design read · B: code/token evidence).
Target: `artifacts/implementation-artifacts/design-24-6/employment-dialog-{colorful,personal,statutory,bank}.png`, replacing `src/features/admin/components/payroll/EmploymentDialog.tsx`.

## Design Health Score

| # | Heuristic | Score | Key Issue |
|---|-----------|-------|-----------|
| 1 | Visibility of System Status | 2 | Active chip shows location; no dirty state, no per-tab completeness, no pending-change count. |
| 2 | Match System / Real World | 2 | Labels and hints are good; groups follow the schema, not the owner's paperwork; "Joined" on the page vs "Joining date" in the form. |
| 3 | User Control and Freedom | 1 | Cancel/Esc silently discard edits across up to four panels; no unsaved-changes guard, no undo. |
| 4 | Consistency and Standards | 1 | Solid fills reserve status meaning; a second tab idiom sits below the page's underline tabs; three idle palettes and two chip heights across four frames. |
| 5 | Error Prevention | 1 | The destructive half of the tri-state (empty a field clears it) is hidden behind tabs; the joining-date consequence hint is gone; no discard confirmation. |
| 6 | Recognition Rather Than Recall | 1 | 11 of 15 fields sit behind a chip the owner must remember. |
| 7 | Flexibility and Efficiency | 2 | Faster for one field, slower for a new hire; no keyboard path, no save-and-next. |
| 8 | Aesthetic and Minimalist Design | 2 | Calmer field panel, undermined by four hues plus avatar, subtitle, status pill and tinted panel before the first label. |
| 9 | Error Recovery | 1 | No error state drawn; the shipped code-cleared guard and reason are not shown. |
| 10 | Help and Documentation | 2 | Strong inline hints for PAN/UAN/PF/IFSC; nothing explains the save contract or what each tab holds. |
| **Total** | | **15/40** | **Poor (37.5%) — significant redesign before build.** |

## Design Specificity Verdict

**Category-interchangeable.** The field copy is authored for this product; the rail is stock pastel tab pills drawn in Tailwind swatches. Measured fills: `#1A56DB` (token), `#7C3AED` (no violet anywhere in either repo), `#954F00` (nearest token `#92490A`, foreground-only), `#06956F` (token). The pale tints (`#EBEFFF`, `#FFE8D8`, `#BDFBE2`, `#F1F3FF`) are all non-token. In this product colour is status — blue in progress, green done, amber scheduled, red cancelled — and the mockup paints navigation in those meanings, including a green Bank tab. `DESIGN_SYSTEM.md` says chip active state is a soft tint, never a solid primary fill, and reserves solid primary for primary actions.

**Deterministic scan:** detector ran on `EmploymentDialog.tsx`: 0 findings, regex-level only; element-level rules (contrast, tiny text) did not run. No browser overlay: the target is four PNG frames, not a running page.

## Overall Impression

The grouping is the right idea. The colour system is the wrong one, and it is the part that cannot ship: two of its four active fills are the product's status colours, one does not exist, and one fails AA. The screen also spends its first ~146 CSS px reprinting a person the owner just clicked, then hides 11 of 15 fields behind guesses.

## What's Working

1. **The chunking is right.** 5/4/3/3 matches the real groups, fits a phone, and accounts for all 15 fields with nothing invented.
2. **The hints are the best copy in the artifact.** "A UAN means PF always applies to this employee." teaches the domain in place.
3. **The borderless tinted panel is calmer than four bordered fieldsets**, and the save note belongs at the point of action.

## Priority Issues

**[P0] The rainbow collides with status meaning and cannot be built from tokens.** Green Bank implies "verified" in the screen that pays people; brown reads as error; violet does not exist. `CustomersTable.module.css` already references undefined `--color-status-violet-*` — proof the hue was never real. White on `#06956F` is 3.79:1 (fails AA); idle amber `#D97706` on `#FFFBEB` is 3.07:1. Fix: one accent, soft-tint active state, icons carry identity; if colour is mandatory, add a real violet family to the design system in fenzit-app, sync tokens, and use the darker green.

**[P1] Four tabs hide 11 of 15 fields and break completeness.** "Complete Employee Details" opens Job while the missing PAN sits two tabs away; hidden fields also hide the destructive clear and unsaved edits. Fix: open on the first missing field, mark each tab ("1 to add", "2 edits"), show the pending count in the footer, guard close-with-edits, disable Save with a stated reason when nothing changed.

**[P1] The rail fails at 360px and at touch/contrast.** Four labels plus icons need ~575px of 328px; chips are 28–36px against a 44px minimum; labels are 12–13px. No 360px frame exists. Fix: 44px targets, 14px labels, AA contrast, and a wrap/scroll spec proven at 360.

**[P2] The header duplicates the host and adds a dead control.** Avatar, name, code, designation, department and Active status are all restated; status is not editable here; designation/department go stale while typing; the code appears three times; the title is ~28px against a shipped 16px. Fix: title "Employment details" plus the code (or name · code); drop avatar, subtitle and status pill.

**[P2] The footer states the safe half, and the sample data breaks product rules.** "Only changed fields are saved" omits "empty a field to clear it" and the joining-date consequence hint. "Senior Technician" breaches the workspace terminology rule in the most screenshot-able string; the PF sample contradicts its own hint; the family names are nonsensical. Fix: "Empty a field to clear it. Only changed fields are saved.", neutral sample designation, coherent sample data.

## Persona Red Flags

**Alex (power user):** the one-screen audit is gone; a new hire is 3–4 tab switches; the dialog height jumps per tab and Save moves under the pointer; no keyboard path or Enter-to-save.

**Sam (accessibility):** no tablist semantics (four unrelated buttons unless built as one); in the Statutory frame idle Job and Personal are the same colour, so colour carries nothing; 3.79:1 and 3.07:1 labels; 28px targets; no focus movement into the new panel; no focus/hover/disabled states drawn.

**Meena (owner, 44, electronics repair shop, 7 staff):** "Statutory IDs" is the least plain phrase on the screen; her paperwork order is PAN → bank → family, not Job → Personal → Statutory; the pastel rail reads as the Employees page's status filters; the green Active pill inside a form looks breakable; she will clear "Spouse's name" meaning "unmarried" and lose the value silently.

## Minor Observations

- Four frames are four slightly different dialogs: avatar 44/48px, Save 40/44px, three idle-chip treatments, two chip heights, footer tinted in two and white in two, panel tint two values.
- Missing states: dirty, disabled Save, focus, hover, error, loading, not-found.
- Inputs 44px vs the 48px comfort token.
- `.dialogTitle` uses undefined `--font-size-md` — pre-existing; the title currently inherits 16px.
- Restructuring the dialog shell touches a stylesheet imported by 21 dialogs and a shell duplicated in two hosts; a modifier class is required, not a change to `.dialog`.
- `AdminEmployeesPage.employment.test.tsx` queries PAN and Leaving date without switching tabs; it will fail unless updated with the tabs.

## Questions to Consider

1. If the four hues carry no meaning, why are they there — and if they do, what does a green Bank tab tell an owner about an employee he is about to pay?
2. What would this look like if it opened on the first empty field instead of the Job tab?
3. When Meena empties "Father's name" because she does not know it, which pixel told her the value would be erased?
