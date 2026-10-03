# UX Copy & Design-Clarity Review — Fenzit app (2026-10-03)

**Reviewer:** Sally (BMAD UX Designer persona, bmad-agent-ux-designer).
**Question asked:** *Can a non-technical business owner, and a technician who reads weak English, use every screen without getting confused?*
**Method:** internet research → review criteria → full text inventory (45 app screens, ~750 strings + ~175 backend strings, 2 PDFs) → live device walkthrough on the Pixel 6 as the owner (Ayush) and attempted technician (Ravi) pass → findings triaged BMAD-style (normalized, deduped, source-verified, severity owned). No fixes applied.

**Evidence:** this folder — `criteria.md`, `screen-inventory-FE.md`, `screen-inventory-BE.md`, `shots/00–37.png` (37 device screenshots).

**Build under review:** production APK FE `c742a0b` on the Pixel 6, against live production BE.

---

## Verdict

The app is **fundamentally sound** for both personas: screens have one clear primary action, empty states explain themselves, and the best lines ("Who's in and who's not", "You're all caught up", "Changes take effect from tomorrow", "No technician is tagged with this skill — showing everyone") are already plain-English exemplars.

But a **fresh user's first 60 seconds are the weakest part**, and jargon clusters in exactly the two places non-technical users live: the **login flow** and the **attendance/punch area**. Two front-door defects were caught live on the device today; they matter more than every wording nit combined.

**Tally:** 1 blocker (login), 8 P1 (confusing enough to cause wrong action or dead-end), 12 P2 (will confuse or slow a weak-English reader), ~10 P3 (polish/consistency).

---

## Findings — triaged

Severity: **P0** blocks the persona from using the app · **P1** confusion likely causes a wrong action/dead-end · **P2** confusion/distrust for a weak-English reader · **P3** polish & consistency.
Verification: 📱 = reproduced on device today (screenshot ref) · 📄 = verified in source (file:line in inventories) · 🕐 = device-verified in a previous session (memory).

### P0 — Login is broken for the technician persona

**F0 · Technician cannot get in; the flow shows the owner's screen then raw developer errors.** 📱 (shots 29–37, DB-verified)
Sequence reproduced today: Ravi (8285052048) verifies his OTP → lands on "**Tell us about your business**" (the owner's company-setup form: Business name, GST number…) which is not his screen; it has **no back button** — pressing system back exits the app (shot 31→32). On later attempts every verify fails with the raw backend string "**Failed to create user**" (shots 35, 36) — a developer message with no "what to do next".
Root cause (DB-checked): `users` now has **3 rows for his phone** — the real active technician row, an `invited` row in a second tenant, and an `owner` row with `tenant_id NULL` created today — tripping the known `findOrCreateUser .single()` multi-tenant bug (memory: fix decided 2026-10-02, stood down). My login attempts likely added the third row.
**Why P0:** this is the front door for every technician (the weak-English persona). Nothing after login can be reviewed by them — or used by them — until this is fixed.
**Fix placement:** BE `findOrCreateUser` (per-tenant lookup, decided already) + **FE AuthFlow routing** (a verified technician must never be routed to step 3) + **BE message hygiene** (`Failed to create user` → "We couldn't sign you in. Please try again in a few minutes." with error_code preserved for support). Data cleanup of the 3 rows is the user's call (destructive; they handled it last time).
**Sub-item (FE copy):** the login heading says "**Set up your account**" even for returning users (shots 29/34) — a technician logging in reads a registration message. Say "Log in" / "Enter your mobile number". Also "Step 1 of 3" over-promises for technicians (2 steps) — hide the stepper for technicians or count real steps. And pick **one word for the code**: heading says "code", buttons say "OTP" — weak-English users don't know "OTP"; use "code" everywhere.

### P1 — Confusion likely to cause wrong action or a dead-end

**F1 · Punch screen speaks "punch/geofence/bounds" to the weakest readers.** 📄 (inventory §2.29) · 🕐 device-verified 2026-10-02.
`Tap to punch`, `READY TO PUNCH`, `PUNCH DISABLED`, `Outside Geofence`, `Out of Bounds for Check-out` + `LOCKED`, `Location verified via GPS`, `Shift Active • In Office… Ready to conclude your workday`.
Rewrites (keep "Check in / Check out" as the only verbs): `Tap to punch` → *Tap to check in*; `Outside Geofence` → *Too far from {office}*; `Out of Bounds for Check-out` → *Too far to check out*; `LOCKED` → *Move closer*; `Location verified via GPS` → *Location checked*; `…Ready to conclude your workday at {office}` → *You can check out after {end time}*. Also standardize the cheating wording here and everywhere to **"Fake location"** (drop "GPS spoofing", "unacknowledged").
**Placement:** FE `attendanceTodayModel.ts` + BE `check-in-out.model.ts outcomeMessage()` (server sends the distance rejections) — both must change together or the FE mapping table grows again.

**F2 · The owner's office card is a jargon + unit collision.** 📱 (shot 13, 14)
One card shows: `150 m geofence` (metres) · `09:00 – 16:00` · `15m cutoff` (**minutes**) · `7h full · 4h half` — three units, two of them abbreviated "m", plus raw coordinates `12.977° N, 77.738° E` as the location line. A non-technical owner cannot explain "15m cutoff" and cannot place the office from coordinates.
Rewrites: coordinates line → *Pinned near: Mana Placido Apartments, Whitefield* (the reverse-geocoded address **already exists** in the map picker, shot 15 — surface it); `150 m geofence` → *Check-in allowed within 150 m*; `15m cutoff` → *Late after 15 min*; `7h full · 4h half` → *Full day 7 hrs · Half day 4 hrs*.
**Placement:** FE `OfficesScreen`/`OfficeLocationCard`/`OfficeListRow`.

**F3 · "Tenant" leaks into owner UI.** 📱 (shot 17)
`Weekly off — "Tenant default & per-employee overrides"`, `Holidays — "Tenant-wide holiday list"`. "Tenant" is SaaS-internal language; owners will never say it.
Rewrite: *"For everyone — you can change it per employee"* / *"Holidays for your whole company"*.
**Placement:** FE `SettingsScreen` tile subtitles. Also sweep: `Team enrolment` → *Team attendance*, `Geofenced check-ins at their assigned office.` → *They check in near their office.* (shot 18), `Effective from` → *Starting*, `Regularized by Ayush` → *Fixed by Ayush* (shot 11).

**F4 · Attendance dashboard KPIs assume HR vocabulary.** 📱 (shot 04)
`Tracked 103`, `Short day`, `Live Sync / Auto`, and "All **offices**" with a "4 **Sites**" chip on the same row.
Rewrites: `Tracked` → *On attendance*; `Short day` → *Worked short* (with subtitle "left before full day"); `Live Sync` → *Updates automatically*; pick **one** of Offices/Sites (recommend Offices) across app + PDF.
**Placement:** FE `dashboardModel.ts`, `PresentCard.tsx`, `WorkspaceSelector`.

**F5 · Monthly rows double-count half days and color zero as good.** 📱 (shot 08)
Arya shows `0.5 worked · 1 half day · 1 absent` — an owner adds 0.5 + 1 and mistrusts the math (it's the same half-day counted twice, once in days, once in events). `0 worked` renders in **green** (reads "good").
Rewrite: show `Half day: 1 · Worked 0.5 days · Absent 1` once each with a micro-legend, and color `0 worked` neutral/grey (reserve green for present).
**Placement:** FE `monthlyModel.ts` chips + colors.

**F6 · Owner's employee-month calendar has unexplained icons and no legend.** 📱 (shots 09, 10)
Days show ⊖ / ⊗ / 🕐 icons; the screen does not scroll and there is **no legend on the owner drill-down** (the technician "My month" has one). A fresh owner can't decode ⊖ = not tracked.
Rewrite: render the existing `DayStatusLegend` under the owner calendar too.
**Placement:** FE `AttendanceEmployeeMonthScreen`.

**F7 · Job detail leads with the job code, and "WORKFLOW STATUS" ≠ "Progress".** 📱 (shots 24, 25)
Screen title is `JB-2026-0001` — meaningless to an owner; customer+skill are below the fold. The owner card says `WORKFLOW STATUS`; the technician's equivalent says `Progress` — same idea, two names. The technician card shows an unrelated skill chip ("AC Installation & Removal" on a pipe-leak job) with no label, which reads as a mistake.
Rewrites: title → *Pratyush · Pipe Leak Repair* (code as small subtitle); unify on **Progress**; label the chip `Technician's skills:`.
**Placement:** FE `JobDetailScreen` header, `WorkflowStatus.tsx`, `TechJobDetailContent`.

**F8 · Brand is "Fenzit" in most places and "Fenzo" on technician screens.** 📄 (inventory §2.32, §2.36)
The attendance intro says *"Fenzo checks your location…"* and the location rationale says *"Allow Fenzo…"* — while onboarding, invites and the PDF footer say **Fenzit**. On the technician's first attendance screen, the wrong brand breaks trust exactly where location permission is requested (their biggest fear: being tracked).
Rewrite: global replace Fenzo → Fenzit (intro copy + `geolocation.ts:42` dialog).
**Placement:** FE only.

### P2 — Confusing for a weak-English reader

**F9 · "Failed"-family BE messages surface raw.** 📄 (BE inventory §1) — mapped FE fallbacks exist, but unmapped paths show BE text verbatim (inventory FE §5). Worst offenders and rewrites:
| BE string today | User-safe wording |
|---|---|
| `Failed to create user` (seen live, F0) | *We couldn't sign you in. Please try again in a few minutes.* |
| `Upload session expired — request a new presigned URL` | *This photo took too long to upload. Please add it again.* |
| `File size exceeds the maximum of N bytes` | *That photo is too big. Please choose one under 10 MB.* |
| `X-Idempotency-Key must be a UUID v4` / `This confirmation key was already used` | *Something went wrong. Please try once more.* |
| `Rules must be sent as a complete set: startTime…` | *Please fill in all the timing fields.* |
| `Leave state transition is not allowed` / `This request is no longer pending` | *This request was already handled.* (matches existing FE copy) |
| `The enrolment would leave an enrolled date without its office assignment` | *Assign this person to an office first.* |
| class-validator defaults (`latitude must not be greater than 90`, `accuracyM …`) | never surface; FE should map 422s on punch to *Please try again outside with a clear view of the sky.* |
| `Invalid customer coordinates (latitude=…)` | *That address doesn't have a location. Please pick it from the map.* |
**Placement:** BE message strings + FE `messageForApiError`-style mappers ( defence-in-depth: FE transport layer should never print an unmapped 422/5xx field-name string ).

**F10 · Three words for one cheating concept + alarmist labels.** 📱 (shot 05) — `Fake location attempt` / `Fake location` / `GPS spoofing blocked` / PDF `Fake GPS`. Standardize on **Fake location**, sentence explained in plain words: *"Someone used a fake-location app on 2 days."* Keep `CRITICAL` (owners understand it) or use a red "Needs your attention".
**Placement:** FE `dashboardModel.ts`, BE PDF `attendance.metrics.ts`.

**F11 · Unit collision "Early · 120m" / "Late · 15m" (minutes) vs metres everywhere else.** 📱 (shot 11). Rewrite: *Checked out 2 hrs early* / *Late by 15 min*. Also unify duration formats: `5 hrs 3 min` (day sheet) vs `8 h 08 m` (punch card) → pick `5 hrs 3 min`.
**Placement:** FE `dayStatusVisual.ts`, `attendanceTodayModel.ts`.

**F12 · "Checkout missing" + missing-legend wording.** 📱 (shot 05) — `Checkout missing` reads like shopping; hyphenation inconsistent with `Check-out`. → *Check-out missing*. **Placement:** FE `dashboardModel.ts`, `attendanceDayStatus.ts` vocabulary.

**F13 · Mixed names for the same people.** 📄 — `technician` (jobs), `employee` (attendance), `team member` (leave screens), `worker` (onboarding slide 1), `your team`. Within one owner's day all four appear. Recommendation: keep **technician** for jobs and **employee** for attendance (both are established), but stop using `worker` (onboarding `data.ts`) and prefer `team member` only inside Leave screens where it's already consistent — or switch Leave to "employee" too. **Placement:** FE copy sweep.

**F14 · "skills" vs "job types".** 📄 — skills error says `Couldn't load the job types.` (skills.ts:47) while every screen says Skills. → *Couldn't load skills. Please try again.* **Placement:** FE.

**F15 · 8 date formats and 2 month abbreviations.** 📄 (inventory §4) — `Sept` (`formatLongDate`) vs `Sep` everywhere else; `12 Jun 25` vs `12 Aug 2026` vs `Monday, 14 September 2026`… Standardize consumer-visible dates on `30 Sep 2026` (full weekday where space allows); keep long forms only where they aid comprehension (flag sheets already good).
**Placement:** FE `utils/formatLongDate` + formatters.

**F16 · Notifications: filters mean jobs, not notifications; "ready" ×3.** 📱 (shot 26) — `All (18) / Active (0) / Completed (2)` read as read/unread. → *All / Ongoing jobs / Finished jobs*. `Report ready / Ready / …is ready to view.` says "ready" three times → title *Report ready to view*, drop the status banner for the ready state. `Mark all read` → `Mark all as read`. Also BE label `Attendance Report` (title case) vs FE `Attendance report` — align casing.
**Placement:** FE `NotificationFilterBar.tsx`, `reportNotificationModel.ts`; BE `report-notifications.ts` label.

**F17 · Times: `Direction` → `Directions`; lowercase `11:49 pm` vs `2:14 PM`.** 📱 (shots 24, 25) — unify AM/PM casing; rename the map button. **Placement:** FE `JobDetailScreen`, ActivityTimeline formatting.

**F18 · Hardcoded "Good morning, {name}" at all hours.** 📄 (HomeHeader.tsx:106, HomeScreen, TodayScreen) — at 8 PM the owner is greeted "Good morning". → time-of-day greeting or a neutral *"Hi {name}"*. **Placement:** FE.

**F19 · PDF wording for owners.** 📄 + 📱 (shot 33) — `Employees in scope` → *Employees included*; range `2026-09-27 → 2026-10-03 (IST)` → *27 Sep – 3 Oct 2026 (IST)*; `7582 min late in total` → *≈127 hours late in total*; `Rejected punches` → *Blocked check-in attempts*; `Fake GPS` → *Fake location*; `Worked days ÷ expected days` → *Worked days out of expected days*. (The "Needs attention" flags are already excellent plain English — keep.) **Placement:** BE PDF templates.

**F20 · Punch status math reads like a police report.** 📄 (BE `outcomeMessage`) — `You are 1,357 m from {office} branch. Move within {200 m} to punch.` → *You are about 1.3 km from {office}. Please go closer, then check in.* (round distances; drop "branch" unless in the office name; end with the action). **Placement:** BE (FE renders verbatim by design).

### P3 — Polish / consistency (batch as one sweep)

- Confirm/cancel button pairs vary per feature (`Keep job/Cancel job`, `Don't check in/Check in`, `Keep half day/Cancel and send new request`) — acceptable contextually; standardize the **cancel** wording to "Keep …" where possible. 📄
- `Dispatch tip:` (Jobs empty) — "dispatch" is fleet-speak → *Tip: tap Overdue to fix late jobs.* 📄
- Icon-only affordances: pencil (edit name), copy-phone icons, dashboard refresh — add labels or tooltips-for-all via a11y + first-use label. 📱 (shots 01, 04)
- `Synced an offline update`, `Waiting to sync`, `Tap to sync status`, `syncing...`, `Sync paused` — for owners "sync" is tolerable, for technicians prefer *Sending… / Saved on phone, will send*. 📄
- Office form: label/helper inverted on grace — label `Late cut-off (minutes after start)` + helper `Grace period`; friendlier as label *"Late after (minutes)"* + helper *"e.g. 15 means 9:15 still counts on time for a 9:00 start."* 📱 (shot 14)
- 24h time inputs (owner office form) vs AM/PM elsewhere — acceptable; if changed, use a wheel picker and drop the `Use 24-hour time…` error. 📱
- `Please ask the customer to sign below.` — good; consider adding Hindi one-liner later (see Deferred). 📄
- Onboarding "worker" (see F13) and slide copy is owner-oriented on a shared screen — fine post-login since technicians skip it? Verify; if technicians see it, trim slide 2 (map tracking) which may scare them before trust is built. 📄

### Data hygiene (owner-policy calls, not copy bugs)

- **Loadtest H01–H10 employees, "QA probe job A/B" jobs, duplicate Ravi rows** are visible in the production tenant's real screens (shots 06, 08, 23; DB query above). They make the owner's dashboard lie (291 absent days, 96 late arrivals in the PDF, shot 33). Clean-up is destructive → owner's call, listed not executed.
- Office pins "Hero wala"/"Jhaji's Home" at the user's desk — already a known owner decision (memory), unchanged.

### Deferred (needs owner decision, not in this review's scope)

1. **Hindi / Hinglish support** — the single biggest lever for weak-English technicians (punch screen + leave form first). No i18n layer exists today; would be a proper epic. Recommended next after P0/P1 fixes.
2. Renaming the Reports concept (`Technician job report`) — fine as-is once F16 casing is aligned.
3. Icon-only affordances full pass (needs design input).

---

## Screen-by-screen scorecard (device pass; ● good / ◐ minor / ○ needs work)

| Screen (persona) | Verdict | Headline |
|---|---|---|
| Splash / Onboarding | ● | Clear value story; "worker" naming (F13) |
| Login: phone | ○ | "Set up your account" wrong for login; OTP vs code; Step 1 of 3 (F0) |
| Login: OTP | ○ | Raw BE error shown; code/OTP mix (F0, F9) |
| Login: company setup | ○ | Shown to technicians — dead-end, no back (F0) |
| Home (owner) | ● | Clean hierarchy; greeting bug (F18) |
| Jobs tab (owner) | ● | Good segments/empty states; Overdue-vs-Today mismatch is mild |
| New job (owner) | ● | Excellent guided form; skill/customer/technician pickers clear |
| Job detail (owner) | ◐ | Code-first title, WORKFLOW STATUS naming, unrelated skill chip (F7) |
| Customers / Add customer | ● | Plain labels, good helper ("Shown to the technician on the job") |
| Account tab (owner) | ● | Clear tiles; icon-only pencil |
| Technicians + invite sheet | ● | Invite copy explains SMS; errors mapped |
| Notifications | ◐ | Filter labels, "ready ×3" (F16) |
| Reports (owner) | ● | Clear types/scope lines; syncing jargon minor |
| Attendance hub (owner) | ● | Best plain-language tiles in the app |
| Attendance Today (owner) | ◐ | Tracked/Short day/Live Sync/Sites (F4, F10) |
| Attendance Monthly (owner) | ◐ | Half-day double display; green zero (F5) |
| Employee month (owner) | ○ | No legend for icons (F6) |
| Offices list/form/map (owner) | ○ | Geofence + coordinates + 15m cutoff (F2) |
| Attendance settings (owner) | ◐ | "Tenant" leak (F3) |
| Team enrolment (owner) | ● | Great reassurance lines; "Geofenced" helper (F3) |
| Leave (owner) | ● | "You're all caught up" exemplary |
| Today + punch (technician) | ○ | punch/geofence/bounds vocabulary (F1) — source + prior device pass |
| History (technician) | ● | Simple |
| Attendance tab / My month (technician) | ● | Good; "Shift & location policy" is bureaucratic |
| Job detail + steps (technician) | ● | Clear progress; BE step labels fine |
| Signature / Location capture | ● | Good instructions; Fenzo brand (F8) |
| Leave apply (technician) | ● | Excellent guidance + presets |
| PDF reports | ◐ | Strong flags; scope/min/ISO wording (F19) |

---

## Recommended fix order (when you say go)

1. **F0** login (BE findOrCreateUser + FE routing + auth copy) — unblocks the technician persona entirely; needs a data-cleanup decision from you for Ravi's 3 rows.
2. **F1 + F20** punch vocabulary (FE model + BE outcomeMessage together).
3. **F2 + F3 + F4** owner attendance jargon cluster (offices card, tenant, KPIs) — one FE PR.
4. **F5–F7** monthly double-count, calendar legend, job-detail title.
5. **F8–F19** copy sweep (FE strings + BE message map + PDF labels) — mostly mechanical.
6. Deferred: Hindi support epic; data hygiene cleanups on your word.

All FE fixes are string/layout changes in `workspace/core/frontend/fenzo-app`; BE fixes touch `fenzit-be` message strings and PDF templates; no DB schema changes anywhere. Per house rules: nothing committed until you approve.

*Research bases: [plainlanguage.gov](https://www.plainlanguage.gov), NN/g error-message guidelines, [CSCW low-literate UI guidelines](https://programs.sigchi.org), [Kompassify microcopy](https://kompassify.com), [JetSoftPro inclusive design](https://jetsoftpro.com), [Uxcel mobile accessibility](https://uxcel.com).*

---

## FIX ROUND — 2026-10-03 (same day, owner approved "fix all")

**Shipped (commits):**
- **BE** `6c951e9` fix(auth): multi-row phone lookup — picks a real membership (active > invited, tenant-bound beats stub), 23505 race fallback; e2e mocks moved to the `.order()` chain. `efa7c69` copy(ux): punch rejections kind-aware with km formatting, photo limits in MB, presigned/idempotency/leave-transition/enrolment/coordinate errors user-safe, report limits + PDF labels plain (Employees included, Blocked check-ins, Fake location, `27 Sep – 3 Oct 2026 (IST)` ranges, minutes-as-hours), notification labels sentence case. **BE unit 1,507 green; e2e back to its pre-existing baseline (26 leave-journey failures reproduce identically at HEAD — environmental date bootstrap, needs `test:e2e:real`/a fix later — NOT from this round).**
- **FE** `8a00079` fix(auth): role-keyed routing (technician never reaches company setup; corrupt-data corner routes to app), login copy (Welcome to Fenzit / Send code / Resend code / New code in m:ss / step labels without "of 3"). `cc85c74` copy(ux): punch screen speaks check-in (no punch/geofence/bounds/LOCKED), offices card (Check-in within N m · Late after N min · hours in words · no raw coordinates), Tenant leaks gone (incl. Weekly off "For everyone" eyebrow), dashboard (On attendance / Short hours / Updates automatically / N offices), monthly no double-display + zero never green, owner month calendar legend added, job detail customer-first + Directions + PROGRESS + Skills label, notifications Ongoing/Finished + Mark all as read + Ready banner dropped, Fenzo→Fenzit (4 strings), greetingForNow() time-of-day, Sept→Sep, worker→technician, skills error, Dispatch tip. **FE unit 2,972 green; tsc clean.**
- **DB**: junk owner stub row for Ravi (tenant NULL, created by the bug) deleted after verifying no references; his genuine "Raj Electronics" invite kept.
- Both pushed to main; **production probe confirmed**: verify for 8285052048 returns `role: technician, tenantId 792b28ed` (Business) — login works server-side; punch validation now answers "Please try again with a clearer location."

**Deferred / noted:** raw 422 arrays repeat the same line per field (FE flattens — fine, could dedupe server-side later); store office address text (list currently derives from radius/timing only); icon-only affordances; Hindi support epic; Loadtest/QA test data cleanup (owner call); pre-existing leave-journey e2e env failures.

**Device verification:** release APK with `cc85c74` built + installed; Ravi login lands in the technician app directly (no company setup), punch card wording verified on device — see session memory for the pass details.
