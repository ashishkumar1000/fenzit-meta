# Loading cases — pattern matrix

Spec-authored companion of SPEC.md. Holds the case classification (which situation gets which loading pattern), the binding timing thresholds, the surface-by-surface map of the console, and the loudness gaps for in-flight API feedback. Distilled 2026-11-26 from four research passes: (a) current loader/route-loader inventory, (b) async-operation census, (c) design-system audit, (d) UX-pattern research (NNG, Primer, Stripe, Geist, React Router pending-UI, WCAG).

## 1. Timing thresholds — bound every implementation

| Wait | Pattern |
|---|---|
| < 100ms | Nothing — feels instant |
| 100–300ms | No skeleton; the (demoted) line loader is the only cue |
| ≥ 300ms persistent | Skeleton shown after a 300ms delay (100ms for view transitions; 0 for known-slow ops); once shown, minimum display 500ms so it reads as a state, not a glitch |
| 1–3s | Indeterminate only (skeleton/spinner) |
| 3–10s | Determinate if progress is countable, else indeterminate + named copy ("Searching…" past ~1s) |
| > 10s | Determinate + estimate + a way to interrupt/cancel; completion must be announced; status survives navigation |
| Skeleton ceiling | ~3s — beyond it escalate; never a full-page skeleton |
| Layout stability | Skeletons occupy the final content's dimensions (CLS ≤ 0.1 target) |

## 2. Case → pattern

| Case | Pattern |
|---|---|
| Boot / auth resolve (`/admin*` HydrateFallback + layout `adminLoader`) | **FULL-PAGE FenzitLoader (hero)** on a light blurred pane; replaces the plain "Checking your access…" text |
| Route navigation (shell → content) | Persistent shell stays interactive; **content-region skeleton** matching the target page archetype; line loader demoted to secondary cue |
| In-page region reload (tab switch, month change, filter refetch) | **Region-scoped skeleton** (300ms delay); never the whole page |
| Refresh of already-visible data | **Stale-while-revalidate**: keep old rows + subtle updating cue ("— Updating…"), no skeleton |
| Button mutation (< ~2s) | Existing pending button (disabled + Spinner + label swap) + `aria-busy`; dialogs lock Cancel/overlay while pending |
| Mutation completion | Toast (`role="status"`, polite) or persistent inline status; errors via `role="alert"`, never auto-dismissed |
| Long op > 10s (payroll run, big exports) | Determinate/countable progress where possible + completion signal that survives navigation |

## 3. Surface map (today → target)

| Surface | Today | Target |
|---|---|---|
| Boot `/admin*` | Plain text "Checking your access…" (`AdminPage.tsx:42`) | Full-page Pour loader + light blur |
| Route nav, all `/admin/*` | 3px line only (`AdminPage.tsx:248`); nothing on own-header pages when idle | Content-region skeletons per archetype; line loader stays as secondary cue |
| Jobs list | `TableSkeleton` rows=6 (`AdminJobsPage.tsx:493`) | Keep; rebuild on new primitives |
| Employees / Customers | `TableSkeleton` + "— Updating…" | Keep; rebuild on new primitives |
| Leave (3 tabs) | Line only (`AdminLeavePage.tsx:28`) | Region skeleton on tab/page change |
| Holidays (calendar/schedule/upload) | Line only | Region skeletons |
| Attendance | Line only (`AdminAttendancePage.tsx:56`); filters client-side | Region skeleton on roster load |
| Payroll (tabs/months) | Line + panel button spinners | Region skeleton on tab/month switch; keep panel spinners |
| Company overview | Line only (`AdminCompanyPage.tsx:70`) | Dashboard-archetype skeleton |
| Job detail | Line only (`AdminJobDetailPage.tsx:90`) | Detail-archetype skeleton |
| Employee profile (tab/month) | Line only (`AdminEmployeeProfilePage.tsx:60`) | Region skeleton |
| Reports / Deletion requests / Inspect / Account / Config / Me | Line or quiet text | Region skeletons; deletion-requests failed state gains a retry |
| Login | Label swap only; lazy-chunk gap | Keep; cover the chunk gap only if trivial |
| Identity check (all `/admin/*` loaders) | Double `GET /users/me` per navigation (`adminLoader.ts:126,166` — layout check + every child `requireConsoleRole`) | One cached fetch per burst (30s TTL, `leaveSummaryCache` pattern); invalidated on login/logout/401 |
| Public pages | Pre-rendered, instant | None |

## 4. Loudness gaps (silent ops → target behavior)

1. **Payroll run completion** — manual Refresh only (`RunsPanel.tsx:227`); no signal survives navigation; and if the user navigates away during the trigger POST, the 202 result is lost until they return → CAP-9: module-level singleton poller on the existing run-status endpoint (FE layer; no BE change), toasts transitions, revalidates the payroll route when mounted.
2. **Dialogs dismissible mid-send** — `AddEmployeeDialog.tsx:141`, `AddCustomerDialog.tsx:160` keep Cancel enabled during the POST → lock dialog while pending.
3. **Leave/Holidays/Payroll region navigation** — no skeleton at all → region skeletons (CAP-3).
4. **PDF download step** — blob download has no busy state (`ReportExportCard.tsx:37`) → busy state on the download control.
5. **One-shot CSV exports** on big rosters read as a hung click (`AttendanceExport.tsx:14`) → keep spinner; determinate progress for page-walking exports (jobs already reports "N downloaded").
6. **Resend-invite SMS** — feedback dies when the row re-renders (`MembersTable.tsx:45`) → toast.
7. **Config / subscription saves** — status line scrolls away (`ConfigForm.tsx:78`, `SubscriptionSection.tsx:89`) → toast.
8. **Session expiry mid-form** — failure reads like a validation error → 401 failures announce via toast/alert with a re-login hint.

## 5. Accessibility rules

- One `role="status"` announcement per skeleton cluster; decorative shimmer layers `aria-hidden`.
- `aria-busy` on the busy region/control; buttons stay focusable (no `aria-disabled` on the trigger).
- Errors: `role="alert"`, focus moves to the error; errors never auto-dismiss.
- `prefers-reduced-motion`: shimmer stops (static sunken blocks remain visible), Pour loader → fully-filled mark + opacity pulse.
- Blur pane: mostly opaque; blur is decoration, never the legibility mechanism (WCAG 1.4.3).
