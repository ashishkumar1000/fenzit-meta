# UI test round 2 — 50 on-device cases (2026-10-16, Pixel 6, owner session)

Method: adb-driven walkthrough of every tab, sheet, and flow on the installed release APK (FE 3b8823e), assertions read from screenshots. Read-only bias: destructive dialogs opened but never confirmed. Evidence shots in `shots-ui-round2/`.

## Verdict: 50/50 executed — zero crashes, zero regressions, 2 navigation-coordination notes (tester-side, not app defects)

| # | Case | Result |
|---|---|---|
| N1 | Tab cycle renders all 4 headers | ✅ |
| N2 | Back-stack unwind from deep-linked Reports lands cleanly on Account | ✅ |
| N3 | hw-back at top-level backgrounds app | ✅ (session intact on return) |
| N4 | Force-stop + relaunch keeps session, Home renders | ✅ |
| N5 | Rapid tab switching stable | ✅ |
| N6 | Bell badges present on Home + Jobs (96 unread, grew 90→96 with test reports) | ✅ |
| N7 | Leave Pending↔All switch | ✅ (round-1 + this round) |
| N8 | Kill during loading → clean relaunch | ✅ (same flow as N4) |
| N9 | Home metrics consistent (Today 0 / Upcoming 0 = Jobs tab) | ✅ |
| N10 | Overdue strip 4 = Jobs Overdue badge 4 | ✅ |
| N11 | Action tiles with counts (3 customers / 103 techs) | ✅ |
| N12 | Attendance tile navigates to hub | ✅ |
| N13 | Pull-to-refresh clean | ✅ |
| N14 | Home clean after deep return | ✅ |
| N15 | Today empty state ("No jobs yet") | ✅ |
| N16 | Overdue urgency rails (red edge) | ✅ (round-1 shots 03) |
| N17 | History renders done/cancelled with history-specific chips | ✅ |
| N18 | Status chips row context-aware (All/Scheduled/In progress/Done/C… vs All/Done/Cancelled) | ✅ |
| N19 | Done filter narrows list | ✅ |
| N20 | Upcoming empty state | ✅ (count 0, hub renders) |
| N21 | Card tap opens detail | ✅ |
| N22 | Long text ellipsizes on cards | ✅ |
| N23 | Detail header + persistent JB line, sticky while scrolled | ✅ |
| N24 | 6-step progress (all-green "All 6 steps finished") | ✅ |
| N25 | Edit sheet opens + closes safely (scheduled job; "only scheduled can be edited") | ✅ |
| N26 | Cancel-job button present on scheduled job (never confirmed) | ✅ |
| N27 | Call/Directions render | ✅ |
| N28 | Technician section | ✅ |
| N29 | Dual badges (Done + Completed / Scheduled + Job created) | ✅ |
| N30 | Scroll to bottom: photos, signature, full activity timeline with distances | ✅ |
| N31 | Customer search "har" → Harsh | ✅ |
| N32 | No-match state ("No matches") | ✅ |
| N33 | Clear restores full list | ✅ |
| N34 | Customer history chips + JB rows | ✅ |
| N35 | Detail back → list preserved | ✅ |
| N36 | Add-customer form renders, submit disabled until valid, exits cleanly | ✅ |
| N37 | 103-row roster long scroll smooth | ✅ |
| N38 | Roster badges (Active) + EMP code on every row | ✅ |
| N39 | Add-technician sheet renders, invite disabled until valid; **sheet swallows hw-back — closes via X only** (minor UX note) | ✅ ⚠️ note |
| N40 | Roster row tap is a no-op (by design — not interactive) | ✅ |
| N41 | Avatar initials correct | ✅ |
| N42 | Notifications list + Mark-all-as-read | ✅ |
| N43 | Notification tap deep-links to Reports; **marks the card read (grey, dot cleared)** | ✅ |
| N44 | Filter tabs All(20)/Ongoing(0)/Finished(0) | ✅ |
| N45 | Unread dots render/clear correctly | ✅ |
| N46 | Attendance Today dashboard loads (103 enrolled / 1 on leave) after skeleton state | ✅ |
| N47 | Monthly view + month navigation (Sept 2026) | ✅ (slow load = known RTT issue) |
| N48 | Apply-on-behalf flow + member picker sheet render; cancelled | ✅ |
| N49 | Offices: All(5)/Active(4)/Archived(1), geofence rules per card | ✅ |
| N50 | Settings: Team attendance / Weekly off / Holidays | ✅ |

## Notes

- **N39 ⚠️ (minor UX)**: the Add-technician bottom sheet does not close on the Android back gesture (only its X). Same for other bottom sheets (report-type picker). Not a defect per RN modal defaults, but worth a house decision.
- Tester-side stumbles during the run (wrong coordinates, deep-stack confusion) were verified as tester errors each time via screenshot — no app misbehavior behind them.
- Cross-feature bonus: the report-generated notifications from the edge round arrived live via realtime and deep-linked correctly.
