# Stitch Onboarding Designs — Feature & Theme Analysis

Status: analysis complete, 2026-10-24 · Input: `~/Downloads/stitch_fenzit_mobile_onboarding_flow/` (4 stages × 2 role variants + `fenzit_kinetic_field/DESIGN.md`) · Ground truth: [designer-input-brief.md](designer-input-brief.md) and the `fenzit-app` source.

## Verdict in one paragraph

The Stitch set proposes a 3-step setup flow (role → permissions → "aha" demo) on a **new visual theme ("Fenzit Kinetic Field": slate + orange + emerald, Plus Jakarta Sans) that we are rejecting** — we keep our own design system (Fenzit Blue `#1A56DB`, our tokens, lucide icons). Conceptually the set contributes three genuinely good ideas: **role-aware onboarding** (the biggest gap in our current tour), a **contextual permissions primer**, and a **"how a job works" walkthrough**. But roughly **half the content sells features that do not exist in Fenzit** — live GPS tracking, instant invoicing/UPI/GST billing, free-trial/commerce copy, employee job acceptance, SMS job alerts, a language switch — and every one of those must be removed, exactly the failure mode the designer brief warned about (§3: current tour copy oversells). Detailed verdicts below; the actionable scope is in [onboarding-redesign-scope.md](onboarding-redesign-scope.md).

## 1. What was received

| Folder | Screen | Role variant |
|---|---|---|
| `1._value_hook_interactive_demo` | Pre-login welcome / hero | Owner-flavoured (has Sign In) |
| `1._value_hook_staff_attendance` | Same, owner-flavoured variant | — |
| `2._quick_role_personalization` | Step 1 of 3 — role picker + service chips | Two variants (Staff / Field Staff) |
| `3._contextual_permissions_primer` | Step 2 of 3 — permissions | Owner & staff variants |
| `4._aha_moment_interactive_job_simulator` | Step 3 of 3 — 3-tap job story + CTA | Owner & staff variants |

Each folder carries `code.html` (Tailwind + Material Symbols) and `screen.png`. The HTML is presentation-only except stage 4, which contains a scripted 6-step job simulator (steps, photo grid, signature box, owner-side "live sync" banner).

## 2. Theme verdict — REJECT, keep ours

The `fenzit_kinetic_field/DESIGN.md` defines a full but foreign identity: deep-slate primary `#0F172A`, Field Amber Orange `#EA580C` CTAs, Verified Emerald `#10B981`, Plus Jakarta Sans, Material Symbols icons, 8px radii, boundary-driven cards. Our product ships the Fenzit Design System: primary `#1A56DB`, success `#06956F`, scheduled `#D97706`, gray-50 page, gray-900 text, lucide icons (`src/theme/`). Mixing two identities in one app is worse than either alone, so:

- **No Stitch colour, font, or icon enters the app.** All redesign screens are rebuilt with our existing tokens (`colors.*`, `spacing.*`, `radius.*`, `typography.*`), lucide icons, and the existing `OnboardingSlide` medallion treatment where it fits.
- **Theme-neutral patterns worth adopting** (re-expressed in our DS): progress as "Step N of 3" + pill segments; full-pill feature chips; selected-state radio cards for choices; a dedicated permissions screen with *Enable all / Decide later*; sticky bottom CTA in the thumb zone; 44–48pt touch targets (we already require this).

## 3. Screen-by-screen analysis

### Stage 1 — Value hook / welcome
**What it shows:** brand pill "FENZIT FIELD OS", English/हिन्दी toggle, headline "Run your service team with zero chaos", feature chips (Live GPS / Photo Proof / Instant Invoicing — or Staff Attendance / Live GPS / Photo Proof), Get Started, Sign In link, trust footer "14-Day Free Trial • No Card Needed • Works Offline".

| Element | In our product? | Action |
|---|---|---|
| "Zero chaos" / replace-WhatsApp framing | — (positioning) | **Keep** — matches brief §1; best headline direction in the set |
| Photo Proof chip | ✅ | Keep |
| Staff Attendance chip | ✅ | Keep |
| Works Offline trust mark | ✅ | Keep — real differentiator, verified |
| **Live GPS chip** | ❌ no live map tracking, only live job-status updates | **Remove** |
| **Instant Invoicing chip** | ❌ no billing/payments module at all | **Remove** |
| English/हिन्दी switch | ❌ language decision open (brief §F.20) | **Remove** |
| 14-Day Free Trial / No Card Needed | ❌ business model undecided (brief §A.2) | **Remove** |
| Fenzit FIELD OS badge | ❌ not our brand | Remove |
| Separate "Sign In" path | ⚠️ Fenzit has one phone+OTP door; login *is* signup for owners | **Simplify** to a single CTA (+ optional "I already use Fenzit" copy line, same screen) |

### Stage 2 — Quick role personalisation ("How will you use Fenzit?")
**What it shows:** "Step 1 of 3", "Zero-Password Onboarding" chip, radio cards Business Owner (ADMIN) vs Staff/Field Staff (STAFF), optional service chips (AC Repair / Electrical / Plumbing / Appliances), dynamic CTA ("Continue to Manager Desk" / "Continue to Field App").

| Element | In our product? | Action |
|---|---|---|
| "Zero-Password Onboarding" chip | ✅ OTP-only auth is real and is a genuine selling point | **Keep the claim**, reword to our voice ("No passwords — just your phone and an OTP") |
| Role picker **before login** | ❌ role is not self-selected — it follows from the phone number (owner = new company; employee = invited). A pre-OTP picker invents a branch our data model doesn't have and sets up wrong-path failures | **Remove as a step.** Role-awareness moves *after* OTP where the role is already known (see scope) |
| Service-category chips | ⚠️ no "company trade" field exists; nearest concept is the skills catalog. New data point + backend change | **Defer** — decision D3 in scope doc |
| Step progress pattern | — | Keep pattern |

### Stage 3 — Contextual permissions primer
**What it shows:** "Step 2 of 3 · Takes 20 sec", rows for GPS / Camera / Notifications with purpose copy, Enable All + Decide Later. Owner-variant rows: "Geofenced Staff Attendance (REQUIRED)", "Job Photo Proof (FIELD PROOF)", "Instant Job Alerts (REAL-TIME — SMS & notifications)". Reassurance line: "Active only during work hours. Zero personal tracking."

| Element | In our product? | Action |
|---|---|---|
| Pre-permission primer concept | ✅ directly answers brief §E.18 (prompt timing) — location and camera both need just-in-time priming | **Keep — the single best conceptual idea in the set** |
| Location row (attendance + job-site validation) | ✅ | Keep, honest copy |
| Camera row (photo proof) | ✅ | Keep |
| Notifications row | ❌ push is planned but **not live** (brief §D.14); in-app notification centre is owner-side | **Cut until push ships** — decision D4 |
| "Alerts via SMS" | ❌ no SMS job alerts | Remove |
| "Optimal driving routes / route guidance" | ❌ we deep-link to maps with saved coordinates; no routing engine | Reword to verified "exact-address navigation" |
| "Active only during work hours" | ⚠️ misleading — we capture location **at check-in and job steps**, not continuously | Reword: "Location is only captured when you check in or complete a job step — never in the background" |
| "Customers verify quality" | ❌ no customer-facing surface in v1 | Reword |
| Enable All / Decide Later | ✅ good honest pattern | Keep (prompts still fire from context, not from this screen) |

### Stage 4 — "Aha moment" job simulator
**What it shows:** "Everything in one place. No WhatsApp chaos." with a 3-step story (Accept Job → Upload Photo Proof → Get Paid Instantly), CTA "Start Your Free Trial", "Continue exploring demo". The HTML also scripts a richer 6-step interactive simulator (dispatch → photos → signature → closed, with an owner-side live-sync banner and WhatsApp/GST/payment notifications). Staff variant: Staff Marks Attendance → Accept Job & Route → Photo Proof & Signature; "No SMS chaos".

| Element | In our product? | Action |
|---|---|---|
| "See the whole job flow in one screen" | — | **Keep concept**, rebuilt around our real flow |
| Staff Marks Attendance | ✅ | Keep |
| Photo proof + customer signature | ✅ | Keep |
| Owner sees completion live | ✅ live **status** updates + bell | Keep (say "live status updates", never "live GPS") |
| **"1. Accept Job"** | ❌ jobs are **assigned** (push); employee flow starts at "On my way" | **Replace** with our 6-step vocabulary: On my way → Arrived → In progress → Photos → Signature → Completed |
| **"3. Get Paid Instantly — UPI QR, receipts & GST invoices"; "₹1,450 auto-credited to HDFC"; "GST invoice via WhatsApp"** | ❌ no payments/invoicing/WhatsApp integration whatsoever — the biggest fiction in the set | **Remove entirely** |
| Start Your Free Trial / No credit card / Cancel anytime | ❌ commerce undecided | Remove |
| "Takes 30 seconds per job • 0 training / Saves 45 mins per staff daily" | ⚠️ unverifiable claims | Remove |
| Interactive simulator + "Continue exploring demo" | ⚠️ demo/sample data is an open product decision (brief §E.17) | **Decision D2** — ship a static per-role flow diagram now; interactive demo only if D2 approves demo data |
| Role-split headline variants (No WhatsApp vs No SMS chaos) | — | Keep the *pattern* (role-aware content), with our verified copy |

## 4. Consolidated keep / adapt / drop

**Keep (concept, rebuilt in our DS):** role-aware onboarding content; permissions primer with Enable-all/Decide-later; "how a job works" flow story; zero-password claim; step progress + pill chips; thumb-zone CTA; offline trust mark; attendance/photo/signature/live-status/attendance proof points.

**Adapt (reword to verified behaviour):** location-privacy copy (point-in-time capture); navigation copy (exact-address deep-link, not routing); "notifications" only after push ships.

**Drop (not in product):** Live GPS tracking · Instant invoicing / UPI / GST / payments · Free-trial & commerce copy · Employee job acceptance · SMS job alerts · Language switch · Fenzit FIELD OS branding · the entire Kinetic Field theme · pre-login role picker · customer-facing verification claims · unverifiable time-savings stats.

## 5. Source of truth for replacement copy

Only claims from brief §D.13 may appear in tour/onboarding copy: live job-status updates on the owner's phone · photo + signature proof · works offline · exact-address navigation · attendance & leave · branded PDF reports. Plus the structural truths: OTP-only login, role chosen by phone identity, 6-step employee workflow, owner activation path = invite employee → add customer → create job.
