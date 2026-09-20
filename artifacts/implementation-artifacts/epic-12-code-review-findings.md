# BMAD Code Review — Epic 12 Stories (12-1 through 12-6)

**Date:** 2026-09-21  
**Reviewed:** Stories 12-1 through 12-6 (Epic 12: Reports)  
**Status:** ✅ Committed; ⚠️ Blockers identified before implementation  
**Total findings:** 35 (BE: 15, FE: 20)

---

## Priority Classification

- 🔴 **BLOCKER** — Will halt implementation; must resolve before dev starts
- 🟠 **MAJOR GAP** — Design choice unresolved; developers will guess
- 🟡 **CLARITY** — Missing detail; can be resolved with cross-reference or clarification

---

## Story 12-1: Backend — report_requests schema + claim RPC

### 🔴 BLOCKER: Story title and ACs describe RPC that no longer exists

**Location:** Story title + AC 3–6  
**Issue:** Developers will read AC 3 and implement a SECURITY DEFINER RPC that was dropped in implementation (migration 51). The deviation blockquote contradicts the acceptance criteria.  
**Resolution:** Retitle to "report_requests schema + guarded UPDATE claim" and rewrite AC 3–6 to describe the guarded UPDATE instead of the RPC. Keep dev notes pointing to migration 51 header comment.

### 🟡 CLARITY: RPC guard pattern references external file

**Location:** AC 4  
**Issue:** Critical claim semantics (PT SQLSTATE codes, lease recovery contract) documented only in migration 51 header comment, not inline.  
**Resolution:** Add inline summary of claim eligibility predicate in AC 2 or Task 1 dev notes; keep migration reference as secondary.

---

## Story 12-2: Backend — report module skeleton & request API

### 🔴 BLOCKER: Empty technician_ids validation code choice unresolved

**Location:** AC 2, Task 2  
**Issue:** "if zero, return 400 `report_too_many_technicians` or a dedicated code?" — which one?  
**Resolution:** Choose one error code and update AC 2 and Task 2 to be explicit. Suggest: use single code `invalid_technician_selection`.

### 🔴 BLOCKER: Env vars REPORT_LEASE_SECONDS assigned to wrong story

**Location:** AC 7, Task 7  
**Issue:** These are worker-only config (polling interval, lease duration, concurrency cap), but AC 7 and Task 7 say to add them in 12-2. They belong in 12-3 (the worker story).  
**Resolution:** Move REPORT_LEASE_SECONDS and REPORT_WORKER_CONCURRENCY additions to story 12-3, Task 7. Update AC 7 to exclude them.

### 🟠 MAJOR GAP: Transient vs persistent R2 presign failure criteria undefined

**Location:** AC 4  
**Issue:** "transient presign failure → 500 `report_presign_failed`; persistent R2 object loss → 410 Gone" — no logic for detecting persistent loss. No mention of retry or timeout thresholds.  
**Resolution:** Define detection strategy: e.g., "persistent = S3 HeadObject returns 404 after 3 retries with exponential backoff; transient = network timeout or S3 5xx after N retries."

### 🟠 MAJOR GAP: In-flight cap mechanism unresolved

**Location:** Task 3, Dev Notes  
**Issue:** Two paths offered (RPC or trigger), but task assumes RPC. Implementation used BEFORE INSERT trigger. Developers need to know which path to take.  
**Resolution:** State explicitly: "Use a BEFORE INSERT trigger (migration 51 pattern) to guard the in-flight count. Do not implement RPC."

### 🟡 CLARITY: StorageService presign method name not specified

**Location:** Task 4  
**Issue:** "mint a fresh presigned URL via `StorageService`" — what's the method name? `presign()`? `presignRead(key, ttl)`?  
**Resolution:** Add method signature: `presignUrl(key: string, ttlSeconds: number): Promise<string>`.

---

## Story 12-3: Backend — generation engine & worker

### 🟠 MAJOR GAP: Notification recipient edge case not handled

**Location:** AC 5, Task 6  
**Issue:** "insert into `notifications` via admin client ... only to `requested_by`" — no fallback if user is deleted, null, or doesn't exist.  
**Resolution:** Add AC clarification: "If `requested_by` user is deleted before notification insert, log a warning and skip the notification (history polling is the fallback per PRD §5.3)."

### 🟡 CLARITY: Definition contract field names conflict across stories

**Location:** AC 7 vs 12-5 implementation blockquote  
**Issue:** AC 7 says use canonical names `fetcher` and `templateBuilder`, but 12-5 implementation refers to `fetchData` and `buildDocument`.  
**Resolution:** Confirm canonical names in 12-3 Task 3 and all definitions use `fetcher` + `templateBuilder` (not `fetchData`/`buildDocument`).

---

## Story 12-4: Backend — PDF renderer & brand kit

### 🟡 CLARITY: Font weight notation uses CSS, not TTF filenames

**Location:** AC 1  
**Issue:** "Inter TTFs (Regular 400 / SemiBold 600 / Bold 700)" — developers may misinterpret "400" as a filename.  
**Resolution:** Clarify: "Inter font files: Inter-Regular.ttf, Inter-SemiBold.ttf, Inter-Bold.ttf (weights 400, 600, 700)."

### 🟡 CLARITY: Font file system path not specified

**Location:** Task 2  
**Issue:** "fs-read once, cached at module load" — from which directory?  
**Resolution:** Add: "Load fonts from `src/reports/templates/brand-kit/assets/fonts/*.ttf`."

### 🟡 CLARITY: pdfmake version chosen but not in spec

**Location:** Dev Notes (Version section)  
**Issue:** Implementation blockquote says "pdfmake 0.3.11", but spec offers two versions without choosing. Developers must guess.  
**Resolution:** State explicitly in Task 1 or Dev Notes: "Use pdfmake 0.3.x; verify ESM/CJS compatibility with Bun runtime before finalizing."

---

## Story 12-5: Backend — Technician job activity report

### 🔴 BLOCKER: AC 1 claims "zero engine changes" but adds maxJobs parameter

**Location:** AC 1 vs implementation blockquote  
**Issue:** AC 1: "Definition completed, zero engine changes." Implementation blockquote: "`ReportFetchContext` gained `maxJobs`." Adding a context parameter is an engine change.  
**Resolution:** Update AC 1: "Minimal engine change: `ReportFetchContext` gains `maxJobs` parameter (passed from `REPORT_MAX_JOBS` config); definitions remain DI-free."

### 🟠 MAJOR GAP: Pagination strategy for three separate queries undefined

**Location:** AC 2, Dev Notes  
**Issue:** Story mentions "paged jobs query" + "chunked technician-name reads" + "chunked attachment-count reads" — unclear how pagination works across three queries. Do they share a cursor or paginate independently?  
**Resolution:** Clarify in Task 1 dev notes: "Jobs query paginated by PostgREST (default 1000 rows); technician names and attachment counts fetched in separate chunked queries (no pagination — chunk by technician_id, not by offset)."

### 🟡 CLARITY: On-time metric calculation ambiguous with null scheduled_end

**Location:** AC 4, Task 2  
**Issue:** "jobs with null `scheduled_end` excluded from the denominator" — does this also exclude them from the numerator? Can a job be on-time with null `scheduled_end`?  
**Resolution:** Clarify: "On-time = `completed_at <= scheduled_end`. Jobs with null `scheduled_end` excluded entirely from on-time calc (excluded from both numerator and denominator). A job is counted as 'completed' only if `scheduled_end` is not null."

---

## Story 12-6: Frontend — Owner reports screen

### 🔴 BLOCKER: Validation error messaging placement/timing/styling undefined

**Location:** AC 2  
**Issue:** AC 2 lists validation rules but doesn't specify where/how errors appear (inline under field? alert banner? floating label?), when they run (onChange? onBlur? submit?), or exact error text per violation.  
**Resolution:** Add AC detail: "Validation errors appear inline under the field (red border + error text below) on submit attempt or onChange after first blur. Error text: '[Field name] is required' / 'Start date cannot be after end date' / 'Range exceeds 92 days' / 'End date cannot be in the future.'"

### 🟠 MAJOR GAP: MultiSelect technician field UX severely underspecified

**Location:** Scope (request form)  
**Issue:** "technician MultiSelect (empty = all)" missing: search/filter, sort order, selected count display, maximum count, "how does user know empty = all?"  
**Resolution:** Add AC detail: "MultiSelect field: searchable, sorted alphabetically, shows '[N] technicians selected' (or 'All technicians' if empty), no hard limit, placeholder text 'Select technicians (leave empty for all).'"

### 🟠 MAJOR GAP: Pagination UI pattern not defined

**Location:** Scope (history list)  
**Issue:** API returns `nextCursor` and `hasMore`, but spec doesn't say: infinite scroll vs "Load more" button? Scroll position recovery? Initial load count?  
**Resolution:** Add AC detail: "History list uses 'Load more' button (not infinite scroll). Initial load: 20 items. Load button appears when `hasMore=true`. Scroll position recovers on back navigation (FlatList `viewabilityConfig` with `minIndexForVisible=0`)."

### 🟠 MAJOR GAP: Refresh mechanics and failure handling missing

**Location:** Scope (refresh strategy)  
**Issue:** "5s list-polling while any row is queued/generating + Supabase Realtime" — no mention of: poll failure retry, exponential backoff, stop-on-repeated-failure, manual refresh button, visual "polling active" indicator.  
**Resolution:** Add AC detail: "Poll fails: log and retry after 5s (no exponential backoff v1). Manual refresh button (pull-to-refresh iOS) available. Stop polling if Realtime connects. Show subtle "syncing..." indicator in header."

### 🟠 MAJOR GAP: Form submission success feedback missing

**Location:** AC 3 (Submit interaction)  
**Issue:** AC 3 covers idempotency and duplicate handling, but doesn't specify: form reset after success, success toast, button disabled state, loading spinner.  
**Resolution:** Add AC detail: "After successful submission: Generate button shows spinner for 1s, form resets, success toast 'Report queued — you'll be notified when ready' appears for 2s, dismiss on tap."

### 🟠 MAJOR GAP: PDF open failure and presigned URL expiry not addressed

**Location:** AC 6 (Ready row tap)  
**Issue:** "tap opens GET /reports/:id presigned URL via Linking.openURL" — no error path for: presign failure, URL expiry, Linking.openURL failure.  
**Resolution:** Add AC detail: "Fetch presigned URL; if network fails or URL fetch times out after 10s, show error banner 'Failed to open PDF — try again.' If Linking.openURL fails (app not available), show 'No PDF reader installed.'"

### 🟡 CLARITY: Empty/error state designs not specified

**Location:** AC 7 (design system states)  
**Issue:** "no blank screen" mentioned, but no design spec for: empty state message/icon, error banner styling, offline boundary appearance, design system component tokens.  
**Resolution:** Add AC detail: "Empty state: 'No reports yet. Create your first report to get started' + illustration from design system `EmptyState` component. Error banner: `ErrorBanner` component (red bg, dismissible). Offline: 'No connection — using cached data' with `OfflineBanner` component."

### 🟡 CLARITY: Realtime subscription lifecycle not defined

**Location:** Scope (refresh via Supabase Realtime)  
**Issue:** Mentions listening to `'report_ready'`/`'report_failed'` notifications but doesn't specify: channel name/pattern, unmount cleanup, connection drop fallback, unsubscribe logic.  
**Resolution:** Add AC detail: "Subscribe to `auth.tenantId + ':reports'` channel on mount; unsubscribe on unmount. If Realtime disconnects, fall back to 5s polling. Reconnect automatically when connection restored."

### 🟡 CLARITY: Date picker and date range UX constraints unclear

**Location:** Scope (IST date pickers)  
**Issue:** "≤ 92 days inclusive" is ambiguous (92 or 93 calendar days?). Missing: day-count display, same start/end date allowed, future date disable UX, keyboard nav.  
**Resolution:** Add AC detail: "Date range: inclusive both ends, max 92 calendar days. Show '45 days selected' below field. Same-date reports allowed (1-day range = 1 calendar day). Future dates disabled (grayed out in picker). Keyboard: arrow keys navigate days; Enter confirms."

### 🟡 CLARITY: Retry button visibility and state missing from main AC

**Location:** AC 1–7, cross-ref to 12-7  
**Issue:** Retry button only mentioned in follow-up story 12-7 ("compact secondary Retry button"), not in main 12-6 ACs. AC 4 assumes basic red chip only.  
**Resolution:** Add to 12-6 AC 4: "Failed rows show red chip with status text. [Follow-up 12-7 adds Retry button beside failed row—not in 12-6 scope.]" Or move Retry detail into 12-6 if it's in scope.

### 🟡 CLARITY: Error code to friendly copy mapping not specified

**Location:** AC 4 (failed rows show friendly copy)  
**Issue:** "`errorCode` to friendly copy" mapping undefined. Which codes exist? Where does mapping live? Fallback for unknown codes? i18n?  
**Resolution:** Add AC detail or reference story file: "Error code mapping (fenzit-be spec, imported from BE contracts): `report_generation_failed` → 'Report generation failed. Try again.' / `report_too_large` → 'Too many jobs in range. Narrow the date range.' / default → 'Error (code: XXX).'"

### 🟡 CLARITY: Loading skeleton and skeleton row count not defined

**Location:** AC 7 (skeleton loading)  
**Issue:** "skeleton loading" mentioned but: row count, animated shimmer or static, height match not specified.  
**Resolution:** Add AC detail: "Show 3 skeleton rows on initial load, animated shimmer (0.8s ease-in-out repeat), matching final row height (80px per row). Replace with real data on fetch."

### 🟡 CLARITY: Idempotency key generation not detailed

**Location:** Scope (fresh `x-idempotency-key` per submit)  
**Issue:** "Never reuse key" — but format, generation location, validity window, retry semantics undefined.  
**Resolution:** Add AC detail: "Generate UUID v4 on each submit. Use as `x-idempotency-key` header. Valid for 1 hour (backend tracks). Retry same request with same key if network fails (correct idempotency)."

### 🟡 CLARITY: Form field focus and keyboard management missing

**Location:** Scope (request form design)  
**Issue:** No keyboard handling spec for: keyboard dismiss after submit, focus order, a11y labels, tab order/touch target sizes.  
**Resolution:** Add AC detail: "Focus order: start date → end date → technician → Generate. Keyboard dismiss: hide after Generate tap. A11y: label all fields ('Start date', 'End date', 'Select technicians'). Touch targets: min 48pt."

### 🟡 CLARITY: List scrolling and state preservation not addressed

**Location:** Scope (history list behavior)  
**Issue:** If user scrolls down and new report arrives via Realtime, does scroll position maintain or jump? Scroll recovery on back nav?  
**Resolution:** Add AC detail: "New items via Realtime: prepend to list, maintain scroll position (don't jump to top). Back nav from details screen: restore scroll position (FlatList state preservation)."

### 🟡 CLARITY: Concurrent submission guard not specified

**Location:** AC 3 (idempotency + in-flight limit)  
**Issue:** AC covers 429 error from in-flight limit, but doesn't say: should Generate button disable after first tap? How is 429 shown to user?  
**Resolution:** Add AC detail: "Generate button disabled while submit in flight (prevents double-tap). If 429 returned, show error banner: 'You have a report generating. Wait for it to finish before creating another.' Auto-retry after 2s or dismiss manually."

### 🟡 CLARITY: Technician selector initialization unclear

**Location:** Scope (request form)  
**Issue:** "empty MultiSelect = all" — is field pre-populated with all technicians or truly empty? How does user reset to "all"?  
**Resolution:** Add AC detail: "MultiSelect starts empty (no pre-population). User selects specific technicians or leaves empty to mean 'all.' No 'Select all' checkbox needed."

### 🟡 CLARITY: Presigned URL caching and lifetime undefined

**Location:** AC 6 (fresh presigned URL, never cached)  
**Issue:** "never cached" stated, but lifetime, fetch timeout, and expiry handling undefined.  
**Resolution:** Add AC detail: "Presigned URLs valid for 1 hour (backend TTL). Fetch on tap only (no caching). If fetch takes >10s, timeout and show error. Warn if URL older than 50 min: 'PDF link may have expired — try again.'"

### 🟡 CLARITY: Notification integration with Reports screen unclear

**Location:** Follow-up note (dedicated report notification cards)  
**Issue:** "tapping navigates to Reports route" — but does nav scroll list to report? Which state? Does notification dismiss?  
**Resolution:** Add AC detail or follow-up story note: "Notification tap navigates to Reports screen and scrolls to the report row (via `useScrollToIndex` if available). Notification dismissed on navigation."

### 🔴 BLOCKER: No accessibility testing requirements

**Location:** General story  
**Issue:** AC 7 references "design system" (which may include a11y), but no explicit AC for: color contrast (status chips), ARIA labels (MultiSelect, status chips), screen-reader testing for dynamic list updates, keyboard-only nav testing.  
**Resolution:** Add to AC 7 (or new AC 8): "Accessibility: status chips meet WCAG AA contrast (4.5:1 text); MultiSelect labeled for screen readers; list reads 'X jobs' on Realtime update; all interactive elements keyboard-accessible."

---

## Summary by Story

| Story | Blockers | Major Gaps | Clarity | Total |
|-------|----------|-----------|---------|-------|
| 12-1  | 1        | 0         | 1       | 2     |
| 12-2  | 2        | 2         | 1       | 5     |
| 12-3  | 0        | 1         | 1       | 2     |
| 12-4  | 0        | 0         | 3       | 3     |
| 12-5  | 1        | 1         | 1       | 3     |
| 12-6  | 2        | 6         | 12      | 20    |
| **Total** | **6** | **10** | **19** | **35** |

---

## Recommended Action Plan

### Before Implementation Starts (Blocker Resolution)
- [ ] Retitle 12-1 and rewrite AC 3–6 to describe guarded UPDATE instead of RPC
- [ ] Resolve empty technician_ids validation code choice (12-2 AC 2)
- [ ] Move REPORT_LEASE_SECONDS env var to 12-3 (12-2 AC 7)
- [ ] Define R2 presign failure detection logic (12-2 AC 4)
- [ ] Clarify whether 12-5 AC 1 includes the `maxJobs` context change
- [ ] Define validation error UX (placement/timing/text) for 12-6 AC 2

### Early in Implementation (Major Gap Clarification)
- [ ] Confirm in-flight cap mechanism is BEFORE INSERT trigger, not RPC (12-2)
- [ ] Resolve definition contract field names: `fetcher`/`templateBuilder` (12-3 AC 7, 12-5)
- [ ] Define pagination strategy for jobs + technician names + attachment counts (12-5 AC 2)
- [ ] Specify MultiSelect UX (search, sort, count, placeholder) (12-6)
- [ ] Specify pagination pattern for history list (infinite scroll vs "Load more") (12-6)

### Implementation Details (Can be Resolved During Dev)
- [ ] 18 clarity items (see table above)
- [ ] Cross-reference with design system for component tokens, accessibility defaults
- [ ] Verify PRD alignment for any design choices not in story ACs

---

**Status:** Ready for handoff to implementation team. Blockers should be resolved before dev start; major gaps can be addressed in story refinement or first sprint planning.
