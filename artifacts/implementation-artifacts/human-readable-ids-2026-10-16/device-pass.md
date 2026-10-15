# Device pass — human-readable IDs (2026-10-16, ~02:15–02:25 IST)

**APK**: `fenzit-release-arm64-1.0.0-2026-10-16.apk` (FE 3b8823e, signed CN=Fenzit Technology, `adb install -r` in-place — Ashish's technician login survived; later switched to owner). Pixel 6 `1C301FDF6002ZB`.

**Backend**: BE 8e38d82 (Render auto-deploy) — live, `config/app` 200 in 1.6s. Login as Ayush (owner, Business) via SMS-OTP flow + master 1039: **delivery + verify worked end to end**.

## Results — every CAP verified live

| CAP | Surface | Evidence (shots/) | Result |
|---|---|---|---|
| CAP-1 | Owner job cards (Overdue) | `03-job-cards-jb-numbers.png` | ✅ `JB-2026-0001/0002/0006` persistent on the time meta row; long time range ellipsizes, number+badge stay visible (the review-1 `numberOfLines` fix, live) |
| CAP-1 | Owner job detail header | `04-job-detail-header-jb.png` | ✅ "Pratyush" primary + `JB-2026-0001` persistent secondary line |
| CAP-2/3 | Technicians roster | `05-roster-emp-codes.png` | ✅ `Arya — EMP-002 · 1234576890`, `Suresh — EMP-003`, loadtests EMP-023/102/099/068/084/076 — exact DB match |
| CAP-3 | Owner leave rows (All) | `06-leave-rows-emp-codes.png` | ✅ `Suresh · EMP-003`, `Loadtest H04 · EMP-099`, `H03 · EMP-102`, `H01 · EMP-069` — codes beside every name |
| compat | Old APK → new BE | (pre-install, `/tmp/d2-profile.png`) | ✅ old build loaded new `/users/me` (with `employeeCode`) cleanly |
| — | Owner home / login | `01-owner-login-ayush.png` | ✅ no crash, all tiles render |

Not device-verifiable cheaply: report PDFs (server-rendered; pinned by BE template specs). Nothing regressed anywhere we looked.

**State left on the phone**: logged in as Ayush (owner, Business tenant) — deliberate, so the owner sees the codes on first unlock.
