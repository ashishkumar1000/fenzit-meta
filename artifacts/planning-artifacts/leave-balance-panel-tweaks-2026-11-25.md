# Leave balance panel — three tweaks (2026-11-25)

Owner-reported confusion: on `/admin/company/leave?tab=requests`, Ajay Sinha (Wallah Book)
shows Earned "12 total allowance" while Types shows Earned = 0 days/year and disabled Sick
still accruing. Root cause established (DB + code + audit log): the panel shows
`credits + accrued + carryForward` (computed on read), the 12 is a manual credit, and the
accrual math ignores the `enabled` flag. Three approved tweaks:

## Tweak 1 — a disabled leave type stops accruing (BE, fenzit-be)

**Layer choice: BE.** The derivation contract is computed-on-read and shared by the admin
panel, the employee app balances screen, the apply-time sufficiency check and the payslip
snapshot — the invariant "a disabled type accrues nothing" must hold for every consumer,
so it belongs in the shared math, not in any one renderer.

- `src/attendance/leave-balance.math.ts` — `walkCarryForward`: each walked FY's
  `accruedFull = !type.enabled ? 0 : (isMonthly ? accruedMonthly(...) : accruedAnnual(...))`.
- `src/attendance/leave-balance.math.ts` — `deriveTypeBalance`: same gate on the
  current-FY `accrued`.
- `src/attendance/leave-balance.service.ts` — `assertBalanceForApply` inline current-FY
  accrual: same gate (defensive consistency; both callers already refuse disabled types
  before reaching it — POST at `leave.service.ts:249`, preview at
  `leave-read.service.ts:276-284` — so the inline gate is dead code on both paths and
  can never disagree).
- Header contract comments updated in both files: "a disabled type accrues nothing in
  every FY — retroactive, the same way a rate edit re-derives the past".
- Semantics decision recorded: "stop accrual" is implemented FULLY RETROACTIVE (zero in
  every walked FY, which also collapses carry-forward chains built from prior-FY
  accrual). Freeze-at-disable-date was considered and rejected: no persisted disable
  timestamp exists (only `updated_at`, which any edit bumps), and current-config-is-truth
  already re-derives the past on a rate edit.
- Ripple check (reviewer-verified): the gate also changes `unusedByFy` (prior-FY raw
  balances) that `assertBalanceForApply` reads for prior-FY segments — unreachable in
  production because both callers refuse disabled types; enabled types change nowhere.
  Payslip capture reads enabled-only types (`leave-balance.service.ts:285`) and surfaces
  stored snapshots — unaffected. The mobile app's `LeaveBalancesCard` already greys
  `!enabled` rows with a "Not available" badge and prints the derived numbers verbatim —
  no app change needed.
- Known spec flip (test phase, not now): `leave-balance.math.spec.ts:363-374` "a type
  disabled or without a mode still derives (the caller filters)" asserts
  `derived.accrued === 5` for `enabled: false` — premise reversed by this change; the
  spec gets rewritten, not patched around. The service spec's disabled row asserts only
  shape (`service.spec.ts:194-232`) and stays green.

No DB change. No response-shape change (numbers only). Payslip capture unaffected (it
reads enabled-only types). Unaffected surfaces keep their semantics: credits, consumed
and remaining still render for disabled types; disabling then re-enabling re-derives the
"lost" months from the rate (current-config-is-truth philosophy, already documented).

Known visible ripple (accepted, owner-informed): Ajay's Sick panel flips from
11 total / 9 remaining to **8 total / 6 remaining** (credit 8 + accrued 0 − used 2) once
this ships; same for every other disabled-type balance.

## Tweak 2 — show where the total comes from (FE, fenzit-web)

**Layer choice: FE.** The API already returns `credits / accrued / carryForward`
separately; only the web panel collapses them into one "total allowance" figure.

- `src/features/admin/components/LeaveRequestsTab.tsx` — `BalanceBlock`: under the
  legend, a muted breakdown line listing each part whose value ≠ 0, joined with " · ":
  credits → "N credited" (numeric sign as-is; credits can net offsetting corrections, so
  the neutral "credited" replaces the looser "opening balance"), accrued → "N accrued",
  carryForward → "N carried forward".
  (Within the full block at least one part is non-zero; the `gross <= 0` early return
  handles the all-zero case per tweak 3's branch below.)
- `LeaveRequestsTab.module.css` — one new muted `.allowBreakdown` line, reusing
  `--color-text-muted` / `--font-size-xs` idioms.

## Tweak 3 — disabled rows read as off (FE, fenzit-web)

**Layer choice: FE.** Display concern only; the BE row must keep flowing (a disabled
type's consumed days stay visible, and a request for a now-disabled type still needs its
balance context).

- `BalanceBlock`: when `!balance.enabled`, add a "Turned Off" chip in the heading
  (same pill shape as `.allowTag`, muted variant class) and fade the block
  (`.allowOff` on the section). Subject-first ordering unchanged — a request spent on a
  disabled type still leads with its own greyed row.
- `gross <= 0` early-return branch (plan-review P2 fix): the early return must not
  swallow the off-state. When `!balance.enabled && gross <= 0`, render the muted line
  "No balance recorded for {name}." with the "Turned Off" pill appended, and — when
  `balance.consumed > 0` — " · N days used this year" so spent days stay visible even
  with no allowance left. Enabled zero-gross rows keep the plain line unchanged.
- Chip copy reuses the Types-tab house term "Turned Off" (LeaveTypesTab.tsx:127), never
  a new synonym (the employee app's own surface says "Not available" — admin console
  anchors to the Types tab; no unification attempt).
- Test-phase caveat: `AdminLeavePage.test.tsx`'s fixture Sick *balance row* says
  `enabled: true` while its type is disabled — the existing "No balance recorded for
  Sick Leave." assertions (lines 428/466/472/623) keep passing today; if the fixture is
  corrected to `enabled: false`, those assertions move to the pill-carrying variant.

## Order of work and gates

1. BE edits → run existing `leave-balance.math.spec.ts` + `leave-balance.service.spec.ts`
   (bunx jest) to see which specs the semantic change flips; report, do not rewrite specs
   yet.
2. FE edits.
3. **Owner gate**: localhost preview (local fenzit-be + Vite 5173 against prod Supabase;
   owner logs in with their phone OTP) — owner confirms before anything else.
4. After owner yes: update/add tests (BE math + service specs for the enabled gate; FE
   panel tests for the breakdown line + Turned Off chip — grep page tests for every old
   string first), then `/bmad-code-review`, triage, then ask to commit (BE first, FE
   second).
