---
title: 'Frontend — Bell icon, notifications page, deep link to job'
type: 'feature'
created: '2026-09-09'
status: 'ready-for-dev'
review_loop_iteration: 0
context: []
baseline_commit: 'efb3d35daf15b429b5e25cb4c3e3bf83e5d573fe'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** Story 3.3 gives the owner *live* updates, but only as a transient banner while the app is foregrounded. There is no history: events that fired while the app was closed or backgrounded are invisible, and there's no place to see past technician activity. fenzit-be's `GET /notifications`, `GET /notifications/unread-count`, and `POST /notifications/mark-read`/`mark-all-read` (Stories 3.1/3.2, deploy first) have no consumer yet.

**Approach:** Owner-only surface, entirely new `src/features/notifications/` feature folder:

1. **Bell icon** (`Bell` from `lucide-react-native`, already the icon set) with an unread-count badge, placed in the Jobs screen's existing custom header row (`JobsScreen.tsx:249` `<View style={styles.header}>` — the owner's primary surface, where the "+ New job" action already lives). The Home screen's existing decorative bell (`src/components/HomeHeader.tsx:102-107`, a `Pressable` with an empty `onPress` and a hardcoded `notificationDot`) is wired to the same screen + real unread count so the app doesn't ship a dead affordance.
2. **Notifications screen** — new full-screen route `Notifications` in `RootNavigator` (sibling of `JobDetail`, covers the tab bar, same header pattern as other full-screen routes): newest-first cursor-paginated list, pull-to-refresh, unread rows visually distinguished, "Mark all read" action.
3. **Deep link** — tapping a row marks it read (optimistic) and navigates via the existing route: `navigation.navigate('JobDetail', { jobId })` (exact precedent: `JobsScreen.tsx:231`, `HomeScreen.tsx:62`).

Data flows through the standard pattern: new `src/services/resources/notifications.ts` API module → hand-rolled store + `useSyncExternalStore` (mirroring `useJobs.ts`) → hook consumed by the screen. Story 3.3's live hook later feeds this store's unread badge on each broadcast (small integration point, listed below).

## Boundaries & Constraints

**Always:**
- Follow the established feature-folder shape: `NotificationsScreen.tsx`, `useNotifications.ts` (store + hook), components, `index.ts` barrel; every screen uses design-system tokens/components (`EmptyState`, `InlineError`, segmented patterns from `JobsScreen`), absolute imports (`@components`, `@theme`, …), ≥44px touch targets, sentence-case copy, no emoji.
- Bell badge count comes from `GET /notifications/unread-count`, refreshed on Jobs-screen **and Home-screen** focus (`useFocusEffect` — the store's TTL throttle convention; both bells share it, so the Home dot never goes stale while the Jobs badge is fresh) and after any mark-read mutation.
- Optimistic mark-read on tap: update the store before the POST resolves, roll back on failure (the established optimistic pattern); "Mark all read" requires an explicit confirm-free tap and **always POSTs** — the endpoint is idempotent, so a stale `unreadCount === 0` (missed live event) must not silently no-op while unread rows are on screen.
- Route param and navigation types: `Notifications: undefined` added to `RootStackParamList` (`src/navigation/types.ts`) and `RootNavigator.tsx`; row tap uses the **existing** `JobDetail: { jobId: string }` route — no param shape changes.
- Row content from the notification's persisted `payload` (`job_number`, `step`, `technician_name`) + `createdAt` relative time — the same denormalized fields the banner uses; no extra per-row fetches.

**Ask First:** None — every pattern (custom header icon, full-screen route, cursor list, optimistic mutation, deep link to JobDetail) has a direct in-repo precedent.

**Never:**
- Never mount the bell or the screen for technicians — bells live only on owner surfaces (`JobsScreen` header + the existing Home `HomeHeader` bell, both wired in this story); the technician app (`src/features/technicianApp/` — `TodayScreen.tsx`, `HistoryScreen.tsx`, `ProfileScreen.tsx`, mounted via `src/navigation/TechnicianTabs.tsx`/`TechnicianRootNavigator.tsx`) must not change, and there is no `Notifications` route in `TechnicianRootStackParamList` (types.ts lines 71-76); the `Notifications` route is reachable only from owner surfaces.
- Do not implement push notifications, background delivery, or deep-link handling for closed-app launches (Phase 2; cold-start navigation from a push is a different mechanism).
- Do not poll `unread-count` on a timer — focus + live-event refresh only (the socket already handles "while open"; polling would defeat the architecture).
- Do not re-implement list state in a new pattern — hand-rolled store + `useSyncExternalStore` like `useJobs`, not react-query/redux.
- Do not change Story 3.3's banner behavior — it stays; the bell/page is additive history, not a replacement.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Bell with unread | `unreadCount > 0` | Badge shows count (99+ cap above 99); zero renders no badge | N/A |
| Empty history | Fresh owner, no notifications | `EmptyState` with "No notifications yet" copy + CTA back to jobs | N/A |
| List failure | Network error, nothing loaded | `InlineError` + Retry, mirroring JobsScreen's error states | N/A |
| Pagination | Scroll end, more pages | Fetch `before = nextBefore` cursor; `null` cursor stops pagination | N/A |
| Row tap | Unread notification for job X | Optimistic mark-read, badge decrements, navigate `JobDetail { jobId }` | Roll back badge on POST failure; still navigates (navigation is the user's intent; read-state is cosmetic) |
| Row tap, read notification | `readAt` already set | No mark-read POST; straight to `JobDetail { jobId }` | N/A |
| Orphaned job | Notification's job deleted/unreachable | `JobDetail` shows its existing not-found error state — no special casing here | Existing JobDetail error path |
| Mark all read | Any unread rows | All rows render read, badge → 0, idempotent repeat is a no-op POST (0 marked) | Failure rolls back optimistic state |
| Live event mid-view | Story 3.3 hook receives broadcast while Notifications screen open | Unread badge refetches; list may show stale rows until focus/pull-to-refresh (accepted — this story adds no socket of its own; Story 3.3's existing subscription drives the refresh) | N/A |
| Technician session | Any attempt to reach bell/screen | Bell not rendered (owner-only header); route unreachable from tech navigator | N/A |

</frozen-after-approval>

## Code Map

- `src/services/resources/notifications.ts` -- NEW: typed API module in the `jobs.ts` style — module-level `async function`s with explicit request/response types + failure docs, exported as one `export const notificationService = { list, unreadCount, markRead, markAllRead }`; `list(query: { cursor?: string; limit?: number }): Promise<Paginated<ApiNotification>>` hits `GET /notifications` (Story 3.2's `{ data, nextCursor }` envelope — the existing FE `Paginated<T>` type), `unreadCount(): Promise<{ unreadCount: number }>`, `markRead(ids: string[]): Promise<{ markedCount: number }>`, `markAllRead(): Promise<{ markedCount: number }>`; re-export from `src/services/index.ts` (via `resources/index.ts`)
- `src/features/notifications/useNotifications.ts` -- NEW: hand-rolled store + `useSyncExternalStore` (mirror `src/features/jobs/useJobs.ts`): items, `nextCursor`, `unreadCount`, focus-TTL'd loads, optimistic `markRead`/`markAllRead` — rollback on a **definitive** failure (non-2xx); on a timeout/unknown outcome, refetch `unreadCount` (and the list) from the server instead of guessing, so a POST that succeeded server-side doesn't leave the badge wrong
- `src/features/notifications/NotificationsScreen.tsx` -- NEW: header (SafeAreaView edges `['top']` + ghost `IconButton` with `ChevronLeft` — exact pattern at `src/features/customerDetail/CustomerDetailScreen.tsx:265-277`), `FlatList` rows, `EmptyState`/`InlineError` states, pull-to-refresh, "Mark all read" header action
- `src/features/notifications/components/NotificationRow.tsx` -- NEW: step + job number + technician name + relative time; unread visual distinction (token-driven, e.g. unread dot / `Badge`); if `payload` is missing keys (degraded row), render the generic copy "Job status updated" instead of blank/undefined fields — same fallback philosophy as the Story 3.3 banner
- `src/features/notifications/index.ts` -- NEW: barrel
- `src/utils/relativeTime.ts` -- NEW: extract a relative-time helper here (verified 2026-09-09: `src/features/jobs/format.ts` has only `statusToBadge`, `serviceTypeToIcon`, `serviceTypeLabel`, `formatTimeLabel` — **no** relative-time helper exists anywhere), re-export from `src/utils/index.ts`
- `src/features/jobs/JobsScreen.tsx:249` -- UPDATE: `Bell` icon (+ unread badge) in the existing header row (line 249 `<View style={styles.header}>` holds the title + the "New job" pill `Button` at 251-258), wired to `navigation.navigate('Notifications')` — JobsScreen's `CompositeScreenProps` (lines 126-129) already lets it push root-stack routes
- `src/components/HomeHeader.tsx:102-107` -- UPDATE (small but required): the Home screen already renders a **dead decorative bell** — a `Pressable` with `onPress={() => {}}` and a hardcoded `notificationDot`. Wire it to the same destination (`navigate('Notifications')`) and drive the dot from the real `unreadCount` — leaving a tappable bell that does nothing beside a live one is worse than the status quo. Owner-side only (verified 2026-09-09: `HomeHeader` is imported only by `src/screens/HomeScreen.tsx`; the technician app renders its own screens via `TechnicianTabs`, so this surface can never appear for a technician); do not touch the technician app
- `src/navigation/RootNavigator.tsx` + `src/navigation/types.ts` -- UPDATE: `Notifications: undefined` full-screen route in `RootStackParamList` (lines 36-59; add after `JobDetail: { jobId: string }` at line 48) + `<Stack.Screen name="Notifications" component={NotificationsScreen} options={{ headerShown: false }} />` (all 7 existing registrations use `headerShown: false`, e.g. JobDetail at RootNavigator.tsx:37-41)
- `src/features/notifications/useOwnerNotifications.ts` -- REFERENCE (Story 3.3, no change here): the live hook that will additionally call the store's unread-count refresh per broadcast — that one-line integration lands in this story if 3.3 is already merged
- Reference: `src/features/jobs/JobsScreen.tsx:231`, `src/screens/HomeScreen.tsx:60-65` -- the exact `navigate('JobDetail', { jobId })` deep-link precedent
- Reference: `src/services/resources/jobs.ts` -- API-module conventions (module-level typed async fns + one exported service object, e.g. `list` at lines 296-306 passing `cursor`/`limit` query params; `advanceWorkflow` at 357-365; long `/** */` doc listing documented failures)

## Tasks & Acceptance

**Execution:**
- [ ] `src/services/resources/notifications.ts` API module (4 calls, types matching Story 3.2's `{ data, nextCursor }` shapes exactly)
- [ ] `useNotifications.ts` store + hook (cursor pagination, TTL focus refresh, optimistic mark-read with rollback, unreadCount)
- [ ] `src/utils/relativeTime.ts` helper + barrel re-export (none exists today — verified)
- [ ] `NotificationsScreen.tsx` + `NotificationRow.tsx` + barrel — all states from the I/O matrix
- [ ] Navigation: `Notifications` route in `types.ts` + `RootNavigator.tsx`
- [ ] JobsScreen header: bell + badge → navigate
- [ ] `HomeHeader.tsx`: wire the existing dead bell to `navigate('Notifications')` + real unread dot
- [ ] Story 3.3 integration: live broadcast also refreshes `unreadCount`
- [ ] Unit tests: store logic (pagination cursor walk, optimistic mark-read rollback, TTL) with the API module mocked (the `__tests__/useJobs.test.ts` pattern: `jest.mock('../src/services', ...)` + `react-test-renderer` probe); row/banner-free pure models where extractable

**Acceptance Criteria:**
- Given the owner's Jobs screen, the bell shows the live unread count and opens the Notifications screen on tap
- Given the Notifications screen, rows render newest-first with step, job number, technician name, and relative time; unread rows are visually distinct; older pages load on scroll; pull-to-refresh works
- Given a row tap, the notification becomes read (optimistically, with badge update) and the app navigates to that job's `JobDetail`
- Given "Mark all read", all rows clear their unread state and the bell badge resets
- Given a technician session, no bell renders and the route is unreachable
- Given failure modes (list error, mark-read failure, orphaned job), the behaviors match the I/O matrix exactly

## Design Notes

- **Why Jobs-screen header is the primary bell (and Home's is just a cleanup):** Jobs is where the owner already watches technician activity, the header row exists with an action precedent ("+ New job"), and the banner + list both redirect to JobDetail — one mental model. Home's bell already renders (decorative, dead onPress, hardcoded dot at `HomeHeader.tsx:102-107`) — this story wires it to the same screen and the real unread count rather than leaving a tappable control that does nothing; it adds no second badge surface beyond that.
- **Why optimistic mark-read:** the read state is cosmetic (a dot), the POST is idempotent, and navigation must feel instant — optimistic with rollback is strictly better UX here than await-then-navigate.
- **Why no timer polling:** unread-count freshness is covered by (a) screen focus TTL, (b) the Story 3.3 socket while the app is open. A timer would add the exact background-cost pattern the foreground-only socket design exists to avoid.
- **Payload over joins:** rows render entirely from the persisted `payload` — the same denormalization decision as Story 3.2's read path; if a row needs a field it doesn't have, the fix is in the Story 3.1 INSERT, never a read-time fetch.
- **Phase 2 push reuses this story verbatim:** a push notification's tap action is "cold-start the app and deep-link" — this story's `navigate('JobDetail', { jobId })` from a payload field is exactly that handler; and the push's foreground arrival path is Story 3.3's `handleJobStatusEvent` refreshing this store's unread count. Nothing here should assume "the user is already in the app" beyond what the deep link already handles.
- **Previous-work intelligence (from Epic 1/2 dev records + code re-verified 2026-09-09):**
  - **`useJobs.ts` is the store template:** module-level store (`subscribers` Set line 59, `state` line 60, `setState` line 80, `subscribe`/`getSnapshot` lines 85-94, `useSyncExternalStore` line 267, shared `inFlight` de-dup lines 68-71), `loadJobs(scope, filter, opts: { force? })` at lines 126-130 with a **hardcoded `15_000` TTL literal at line 137** (`FOCUS_REFRESH_TTL_MS` exists in `src/constants/index.ts:14` but is unused by useJobs — use the constant in the new store, don't copy the literal), `refresh` force-bypassing the TTL at line 281, `upsertJob` (249, prepend-only for today-scope) / `clearJobs` (258) mutators, `registerReset(clearJobs)` at line 264 — copy the shape, don't invent a new store pattern. Register the new store's reset the same way.
  - **Focus refresh precedent:** `JobsScreen` uses `useFocusEffect` (lines 161-173) for its throttled refetch — the bell's unread-count refresh on focus uses the same hook, not a `useEffect` on mount.
  - **Optimistic mutation precedent:** `src/features/technicianApp/useWorkflowAdvance.ts` mints an idempotency key once per action (`keyRef.current ??= generateIdempotencyKey()`, line 89) via `X-Idempotency-Key`, retries offline failures with the same key, and merges the response into local stores; optimistic mark-read with rollback follows the same spirit (update store → POST → roll back on failure). Mark-read is idempotent on the BE (Story 3.2), so no idempotency key is needed here.
  - **Relative time:** verified 2026-09-09 — `src/features/jobs/format.ts` has NO relative-time helper (only `statusToBadge`, `serviceTypeToIcon`, `serviceTypeLabel`, `formatTimeLabel`). Extract `src/utils/relativeTime.ts` (barrel-exported), never a per-screen copy (the four-copies `isAbort.ts` consolidation is the cautionary precedent). `jest.setup.js` pins `process.env.TZ = 'Asia/Kolkata'` — write the helper timezone-agnostic.
  - **Touch targets:** bell is an icon-only button — theme `touch.min` token + `hitSlop={8}`, per the consolidated ≥44px convention; `IconButton` (`src/components/ui/IconButton.tsx`, variants solid/soft/ghost, sizes sm 36 / md 44 / lg 52, `label` required) is the base component.
  - **Screen-header pattern:** back buttons on full-screen routes copy `src/features/customerDetail/CustomerDetailScreen.tsx:265-277` (SafeAreaView `edges={['top']}` + `IconButton variant="ghost"` with `ChevronLeft` `size={22}` `color={colors.textStrong}`); the Notifications screen header follows it. Design-system components available in `src/components/ui/`: `Avatar, Badge, Button, Card, EmptyState, IconButton, InlineError, Input, MultiSelect, SegmentedControl, Select, Sheet, Switch` (all from the barrel `src/components/ui/index.ts`).
  - **Tests via `bun run test`** (never bare `bun test`); `jest.config.js` already sets `watchman: false` — no extra flag. Tests use `react-test-renderer` probe components (`@testing-library/react-native` NOT installed) and mock the services barrel (the `__tests__/useJobs.test.ts` pattern at repo-root `__tests__/`). Unit-test the store with `notificationService` mocked.
  - **Absolute imports** (`@components`, `@services`, `@theme`, …) are mandatory in all new files (fenzo-app CLAUDE.md; tsconfig `paths` already mapped — some legacy files use relative imports; do not copy that).
- Cross-repo ordering: after Stories 3.1/3.2 (fenzit-be, deployed first). Can merge together with Story 3.3 — both fenzo-app, both consume deployed BE.

## Verification

**Commands:**
- `bun run test` -- expected: store tests pass (jest via the script, never bare `bun test`)
- `bun run lint` -- expected: clean on new files
- Manual: owner app → bell tap → list loads → tap unread row → JobDetail opens, badge decremented; airplane-mode → open list → InlineError + Retry; technician app → no bell

## Suggested Review Order

1. `useNotifications.ts` — store correctness: cursor walk, optimistic rollback, TTL, no stale badge.
2. `notifications.ts` API module — types mirror Story 3.2 responses exactly.
3. Navigation diff — route registered, param type, owner-only reachability.
4. `JobsScreen` header diff — smallest possible change to a complex screen.
5. Screen + row — design-system compliance (tokens, touch targets, states).
6. Tests + Story 3.3 integration line.