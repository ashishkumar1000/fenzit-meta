# Plan — 23-12 Mobile payslip self-service + 23-14 Mobile leave balances (fenzit-app)

Combined build (owner direction 2026-11-19: "complete the coding part of both the stories 23-12 and 23-14 at once"). One repo, one device pass covering both. Both are frontend-only — zero BE changes (the BE legs shipped in 23-8/23-13 are live on prod). Execution order within the plan: resources → models → hooks → components → screens → navigation wiring. Tests after device confirmation (test-timing rule).

## Wire contracts (verified from fenzit-be source, not docs)

### 23-12 payslips (permission `payroll.own` = EMPLOYEE role only — no admin legs in the app)

| Call | Shape |
|---|---|
| `GET /api/v1/payroll/payslips/me` | `PayslipView[]` — locked months only, newest first, empty array when nothing locked. Each row carries `pdf: {status: none\|queued\|running\|ready\|failed, url?}` (fresh presign per read, TTL 600s) |
| `GET /api/v1/payroll/payslips/me/:month` | single `PayslipView` — full detail incl. `slipNumber`, `month`, `payableDays/lopDays/paidDays/daysWorked`, `grossEarnings`, `earningLines[{name,amount}]`, `deductionLines[{source,amount}]`, `netWages`, `totalDeductions`, `leaveBalances[{code,name,accrued,availed,carryForward,remaining}]`, `warnings[]`, `pdf` |
| `POST /api/v1/payroll/payslips/me/:month/pdf` | 201 `{id, status: queued|generating|ready|failed, createdAt}`; in-flight dedupe (newest matching request queued/generating → returned as-is); failed never blocks re-request; 429 `REPORT_IN_FLIGHT_LIMIT` "Too many reports in progress — wait for one to finish (max 3)" |

- PDF URL: **no stored URL anywhere** — `url` present only when `pdf.status === 'ready'` and presigning succeeded; a presign failure leaves url absent, never fails the row. Expiry remedy = re-fetch the detail GET (url regenerated on every read).
- Branched 404 `RESOURCE_NOT_FOUND` copies (render `err.message` verbatim): "Payroll for ${month} hasn't been run for your company yet" / "Your ${month} payslip isn't available yet — it will appear once payroll locks the month" / "There is no payslip for you in ${month}".

### 23-14 leave balances

| Call | Shape |
|---|---|
| `GET /api/v1/attendance/me/leave/balances` (`leave.own`) | one row per accrual-bearing type, **disabled included** (their consumed still counts); Comp-Off (`mode none`) never appears. `{typeId, code, name, accrualMode: monthly\|annual, accrualDays, paid, enabled, credits, accrued, carryForward, consumed, remaining}` — derived as of today, current April–March FY |
| `GET /api/v1/attendance/me/leave/types` (`leave.own`) | enabled-only `LeaveTypeView[]` `{id, code, name, accrualMode: monthly\|annual\|none, accrualDays, carryForward, allowOverBalance, paid, enabled, configurable}`; Comp-Off included with `accrualMode:'none'` |
| `GET /api/v1/attendance/leave/:employeeId/balances` (`leave.read_all`, COMPANY_ADMIN) | same balance shape, for the owner surfaces; unknown/foreign id → 404 "The employee is not in this company" |
| apply body | `leaveTypeId?: string \| null` added to both self and on-behalf apply (absent/null = untyped → reads as paid, no balance check) |

- Insufficient balance surfaces ONLY at submit (BE preview deliberately does not check balance): 422 `LEAVE_INSUFFICIENT_BALANCE`, message verbatim e.g. "Not enough Earned Leave balance — you have 3.5 days left and this request needs 4 days". The apply path already renders server `err.message` verbatim via `messageForSubmitError` → no FE code→copy table needed; just never intercept it.
- Unknown type 404 "The leave type is not in this company"; disabled-at-submit 422 `LEAVE_TYPE_DISABLED` "This leave type is no longer available to apply for" — both verbatim via the same path.

## Story 23-12 — Payslip self-service

**Entry point (technician side).** Profile tab (`src/features/technicianApp/ProfileScreen.tsx`): a new `Card padding="none"` group with one `ProfileActionRow` "Payslips" (lucide `Receipt`, `textMuted`), placed directly below `MyJobsSummaryCard` and above the legal rows — money documents sit with the personal record, not the legal block. Navigates to a new full-screen route.

**Navigation.** `TechnicianRootNavigator.tsx` gains `MyPayslips` (no params) and `MyPayslipDetail` (`{month: string}`), both `headerShown: false`, registered as siblings of AttendanceIntro/LeaveApply; param list entries in `src/navigation/types.ts`. Detail is a SCREEN not a Sheet — the Form-V detail (summary + earning/deduction lines + leave balances) is long-form content; the repo's sheet idiom is for bounded actions.

**Resources.** New `src/services/resources/payrollPayslips.ts` (reports.ts pattern): `listMyPayslips()`, `getMyPayslip(month)`, `requestMyPayslipPdf(month)` (no body; idempotency header not required by BE but fresh `X-Idempotency-Key` sent for consistency with the house write idiom), types `PayslipView`, `PayslipPdf`, `PayslipPdfRequestView` hand-written to the wire. Exports `payslipsService`.

**List screen (`features/payslips/PayslipsScreen.tsx`).**
- `useMyPayslips` hook: focus-load with the 15s TTL throttle (FOCUS_REFRESH_TTL_MS) + pull-to-refresh force path.
- Rows (component `PayslipRow`): month long-form ("October 2026"), `netWages` as the primary figure (₹, en-IN grouping), caption "Slip {slipNumber}" + paid/LOP days caption, right side `pdf.status` → Badge: ready→"Ready", queued/running→"Making PDF", failed→"PDF failed", none→no badge. Tap → detail.
- States: `Skeleton` rows on first load; `EmptyState` "No payslips yet — yours will appear here after payroll runs" (never mention locks — the BE copy owns lock wording); `InlineError` + Retry on load failure; NETWORK_ERROR/TIMEOUT → FE offline copy ("Couldn't load payslips — you're offline. Check your connection and try again.").

**Detail screen (`features/payslips/PayslipDetailScreen.tsx`).**
- Fetches `getMyPayslip(month)` on mount + on focus (fresh presign each visit).
- Layout: hero card (month, slip number, net pay hero figure, paid/LOP days), Earnings section (`earningLines` rows + gross), Deductions section (`deductionLines` rows + total), Leave balances section (from `leaveBalances`: per type "N days left" + caption "N accrued · N used · N carried forward" — carried-forward line only when >0; omitted when the array is empty, mirroring the BE), warnings rendered as `InlineNotice` when present. NOTE: this section consumes the payslip-snapshot shape (`availed`), NOT the live `LeaveBalancesCard` (which consumes `consumed`) — the two unions stay separate types so reuse cannot silently typecheck.
- **Deduction row labels** (`deductionLines[].source` is a machine token): `pf_employee` → "PF — employee share", `tds` → "TDS", `head:<name>` → the head name verbatim, `recovery:<YYYY-MM>` → "Recovery (Oct 2026)" (month long-form). Earnings `name` is already human.
- **PDF button** (primary, bottom-anchored) — THREE-state tap (review patch, web-10 precedent): `pdf.status` ready → fresh detail GET → `openUrl(url)` (no re-queue; the BE inserts a new request when the newest is ready, so blind POST would regress ready→queued and burn a regeneration + an in-flight slot); queued/running → resume polling from current state, button disabled; none/failed → POST `requestMyPayslipPdf(month)` → poll `getMyPayslip(month)` every 5s while queued/running, cap 12 polls (~60s) then stop with InlineNotice "Still generating — try again in a bit" (button re-enabled as resume). `ready` + `url` → `openUrl(url)` (system viewer, linking.ts rethrow idiom → InlineError retry). `ready` without `url` (presign hiccup) → auto re-fetch once, else InlineError. `failed` → InlineError "The PDF failed to generate. Try again." + button "Try again" (POST again — failed never blocks).
- Expiry handling: never cache the url; every download tap starts from a fresh detail GET, so a stale/600s-expired URL is impossible to reach from the UI.
- Detail reads (mount + focus + poll) use the repo's seq-latch latest-wins idiom (useLeaveApply.ts:120-155 pattern) so a late focus response can't clobber a fresher poll.
- 404s render `err.message` verbatim (the branched BE copy) with a back affordance.
- `formatRupee` util (new, `src/utils/formatRupee.ts`): hand-rolled Indian 2-2-3 grouping (1,23,456 — NOT the western grouping the house regex produces), decimals only when fractional, negative prefix "−". House rule: no `toLocaleString`/Intl dependency on Hermes (attendanceTodayModel.ts:460-467 precedent).

## Story 23-14 — Leave balances

**Resource additions** (`src/services/resources/attendanceLeave.ts`): `getMyLeaveBalances()`, `getMyLeaveTypes()`, `getEmployeeBalances(employeeId)` (owner); `leaveTypeId?: string | null` on `ApplyLeaveBody` + `ApplyOnBehalfBody`; `LeaveTypeView`/`LeaveBalanceView` types.

**Shared component** `features/attendance/leave/LeaveBalancesCard.tsx` (flat next to the leave folder's siblings — no components/ subfolder): props `{balances, loading, error, highlightTypeId?, compact?}`. Rows: name + big `remaining` figure + caption "N accrued · N used" (+ "N carried forward" when >0; halves shown as 0.5). **Remaining copy rules** (derived balance is not clamped and allow-over types can go negative): 0 → "0 days left"; negative → "Overdrawn by N days" (absolute value). Disabled types render muted with a "Not available" chip (their remaining is history, not usable). `Comp-Off` never appears (BE excludes; nothing FE-side). Loading → 2 `Skeleton` rows; error → InlineNotice "Couldn't load balances" (non-blocking — the form stays usable); empty → card omitted.

**Apply form** (`LeaveApplyFields.tsx` + `leaveApplyModel.ts` + `useLeaveApply.ts`):
- **Copy fix:** the existing day-part SegmentedControl is labelled `Type` — next to a real leave-type picker that is actively confusing. Renamed to **"Day part"** (plain-English rule); the reset note retitled to match: "Day part reset to Full day — half day applies to a single date only." (was "Leave type reset to Full day…" — with a real Leave type section on the form, the old string reads as the picker being reset). Tests pinning the old label/string updated in the same pass. Same rename applied to `LeaveDetailSheet`'s day-part key-value row ("Type" → "Day part") so the owner's review surface matches the form.
- New **"Leave type"** section ABOVE Day part: a chip/picker bound to `leaveTypeId` (null = no type). Options from `getMyLeaveTypes()` (enabled only — a disabled type structurally cannot reach the picker). Each option caption: monthly/annual types show "X days left" from the matching balance row (tap-through highlight on the balance card); **Comp-Off (`accrualMode 'none'`) shows NO balance — caption "Owner approves each request"**.
- Optional by design: null selection = untyped paid leave (the shipped BE semantic, and a tenant may disable types — "a company without a type disables it" — in which case the section collapses to a neutral "No leave types available" notice and the form behaves exactly as today). Caption under the picker when nothing selected: "No type — counted as paid leave". **DECISION FLAG for review:** optional-vs-required.
- Balance card: `LeaveBalancesCard` pinned at the top of the form (below the header, above Leave type), `highlightTypeId` wired to the picker selection.
- Submit: `buildApplyBody` gains `leaveTypeId` (omitted when null); insufficient-balance 422 falls through `messageForSubmitError` → InlineError verbatim (no new FE copy table). Fresh idempotency key per tap unchanged. After a successful typed apply, the balance card must not show stale numbers if the user returns — the form unmounts on success (goBack), and the owner's on-behalf form refetches balances on focus (below).
- **Apply-on-behalf (owner)**: same picker + `LeaveBalancesCard` fed by `getEmployeeBalances(pickedEmployeeId)` (refetch on employee change AND on focus — the owner can submit, land on OwnerLeave, and Android-back into the still-mounted form, so focus-refetch is the staleness guard; submit keeps its existing `navigate('OwnerLeave', {tab:'all'})` landing), `leaveTypeId` in the on-behalf body; owner applies on behalf consume the TARGET employee's balance (BE-side).

**Owner leave screens.** `LeaveDetailSheet.tsx` gains a compact "Balances" section (name + remaining rows via `compact` mode). The sheet's own contract ("the sheet never calls the API itself") is preserved: the HOST (`OwnerLeaveScreen`) fetches `getEmployeeBalances(request.employeeId)` when the sheet opens, keyed to the open request, and passes balances/loading/error down as props; non-blocking on error (404 for a since-removed employee → quiet InlineNotice). The pending-queue rows stay as-is (no per-row fetch).

## Non-goals
- No in-app payroll admin UI (CAP-7 scope: employee leg only).
- No PDF in-app viewer — system viewer via Linking (reports precedent).
- No change to BE preview semantics (no balance check there, by design).
- No payslip list filters/search (history is short — months).

## Device pass plan (Pixel 6, one pass covering both)
Debug APK → Metro live-JS → login (master OTP 1039). Prereq seeding via Supabase MCP on a test tenant: lock a month with a run + payslip for the test employee (or reuse existing rows), balances visible from the 23-13 catalog seed.
- 23-12: empty state (tenant without payroll) → seeded state (list → detail → download → poll → system viewer opens PDF) → failed/retry posture → 404 month copy → offline posture → presign-expiry refetch (wait out TTL is impractical; simulate by tapping download twice well apart).
- 23-14: balance card numbers vs DB (credits/accrued/CF/consumed/remaining math on a scratch check), picker shows only enabled types, Comp-Off no-balance caption, disabled type absent from picker but present (muted) on card, typed insufficient-balance submit → verbatim BE message, untyped submit still works, owner detail-sheet balances, apply-on-behalf consumes target balance.
- Test-timing rule: implement → user confirms on device → tests written after.

## Review checklist for the adversarial pass
1. Optional-vs-required leave type (flagged above).
2. Balance card showing disabled types muted vs hiding them.
3. "Day part" rename blast radius (tests, a11y labels).
4. Poll cap + back-button interplay (leave screen while polling → poll must die with the hook).
5. Payslip detail 404 copy — verbatim BE message may name a month the user can't act on; back affordance clarity.
6. List `pdf.url` never used on rows (only status) — no stale-URL path.
7. On-behalf balance fetch 404 (employee left company between pick and fetch) — non-blocking InlineNotice.
8. Amount formatting — ₹ en-IN, decimals only when fractional (money fields are numbers on the wire; no string parsing).
