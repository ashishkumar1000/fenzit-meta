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

## Code Review

### 2026-11-25

**Code review complete.** 0 decision-needed, 9 patch (applied), 3 defer, 4 rejected.
Lenses: blind-hunter + verification-gap + intent-alignment reported; edge-case-hunter
returned an empty result → failed layer (round not fully covered by all four).
Verification-gap found no verification gap; it also ran both full suites clean
(BE 192 suites / 3531 passed, web 1289 passed / 0 fail) before this round's patches.

Patches (applied under the owner's "yes proceed"; suites re-run green after):
- [x] [Review][Patch] FE fixture: casual off row carries accrued 4 — a shape the disabled gate forbids [AdminLeavePage.test.tsx:519]
- [x] [Review][Patch] Panel day counts never singularize ("1 days used/remaining") — three sites [LeaveRequestsTab.tsx:532/557/570]
- [x] [Review][Patch] Service spec pins consumed 0 while claiming "consumed stays visible" [leave-balance.service.spec.ts:234]
- [x] [Review][Patch] No composition test: disabled × prior-FY through deriveTypeBalance [leave-balance.math.spec.ts]
- [x] [Review][Patch] Disabled gate ternary copy-pasted 3× → extracted accruedFor [leave-balance.math.ts, leave-balance.service.ts]
- [x] [Review][Patch] Comment anchors cite rotting line numbers → name LEAVE_TYPE_DISABLED [leave-balance.service.ts:234]
- [x] [Review][Patch] Disabled-rule rationale restated ~5× → inlines trimmed to pointers
- [x] [Review][Patch] .allowTagOff re-declares the whole .allowTag pill → composes: allowTag [LeaveRequestsTab.module.css:551]

Defer:
- [x] [Review][Defer] Mode-null/'none' accrual fall-through unpinned in the math specs [leave-balance.math.spec.ts] — deferred: pre-existing (the old case's title over-claimed; it only ever tested enabled:false); caller filtering (readBalancesFor excludes mode-none and remnants) guards the fall-through by design.
- [x] [Review][Defer] Over-consumed block clamps remaining to 0 — the overdraw stays silent (used caps at gross) [LeaveRequestsTab.tsx:526/541-542] — deferred: pre-existing display contract; surfacing negative remaining is an owner design decision.
- [x] [Review][Defer] .allowOff fade class binding never asserted [LeaveRequestsTab.tsx:553] — deferred: the bun test stub resolves CSS-module keys to undefined (className renders "undefined undefined" in tests), so RTL class asserts are impossible in this suite; the "Turned Off" chip remains the verified semantic signal.

Rejected appendix:
- [Review][False] Defense-gate test name implies refusal — false: the name says "accrues nothing" and the comment says callers refuse first; both refusals are tested (leave.service.spec.ts:419, leave-read.service.spec.ts:891).
- [Review][False] Caller-refusal property untested — false: both caller refusals have named 23-13 tests (same cites).
- [Review][Reject-low] Prior-FY × disabled through assertBalanceForApply untested — the path is unreachable by construction (both callers refuse disabled types first); a test would pin dead behavior; the walk itself is tested directly.
- [Review][Reject] Collapsed off-line does not fade like off blocks — the collapsed treatment (chip + used-days, no fade) was specced in this plan's P2 amendment and owner-previewed live before "yes proceed"; changing it edits the approved plan.

Post-patch suite state: leave-balance math+service 58/58, leave.service + leave-read
70/70, AdminLeavePage 37/37, check:styles + biome clean, tsc clean on touched files.
