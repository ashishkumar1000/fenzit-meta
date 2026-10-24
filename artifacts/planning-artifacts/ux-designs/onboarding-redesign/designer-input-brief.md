# Fenzit — Product & Feature Brief for Onboarding Redesign

Purpose: everything a designer needs to know about Fenzit before designing its onboarding, plus the checklist of inputs the product team must supply. Compiled from the codebase and product docs, 2026-10-24.

---

## 1. What Fenzit is

Fenzit is a **field-service management app for Indian service businesses** (e.g. AC/appliance repair, installation and maintenance companies). It replaces WhatsApp + paper + registers with one system: the owner assigns jobs, field employees execute them step-by-step with proof (photos, signature, location), and the owner watches everything live — plus attendance, leave, and reports.

It is **one mobile app (iOS + Android, React Native) with two experiences, chosen by role at login**:

| Experience | Who                                                             | What they do |
|---|-----------------------------------------------------------------|---|
| **Owner/Admin** | The business owner (role `company_admin`, today called `owner`) | Creates and assigns jobs, manages customers and employees, approves leave, runs attendance, reads reports |
| **Employee** | Field technician or Employee (role `employee`)                  | Sees today's assigned jobs, executes the 6-step workflow with photos and signature, marks own attendance, applies for leave |

Plus two more roles defined (not yet the focus): `viewer` (read-only) and `platform_admin` (Fenzit staff).

**Login is phone number + OTP only** — no email, no passwords, no social login. First login as an owner creates the company; employees join by being invited via phone number.

Status: **pre-launch** (no live users yet — good timing for an onboarding redesign).

---

## 2. Major features

### Core job loop (the heart of the product)
1. **Job creation (owner)** — pick/create a customer, choose service type and required skills, assign one or more technicians, set date/time window, priority, notes, job location.
2. **Jobs board (owner)** — today's jobs by default, status filters, infinite scroll, pull-to-refresh, and **live status updates** (the screen updates by itself when an employee advances a job; bell icon with unread badge + notification list that deep-links to the job).
3. **Job detail (owner)** — customer + employee profiles, current workflow step, full activity log timeline, attachments (photos + customer signature); edit, reassign, or cancel while the job is still `scheduled`.
4. **Home dashboard (owner)** — today's stats and a "needs attention" section.

### Customers
5. **Customer list + add** — with **Google Places address autocomplete** (India-restricted): pick a real address, exact coordinates are saved; manual free-text entry always remains as fallback.
6. **Customer detail** — profile plus full paginated job history.

### Employee app (field execution)
7. **Today & History** — own assigned jobs, grouped by status.
8. **Job detail (employee)** — customer name/phone/address with tap-to-call and **precise map navigation** (uses saved coordinates when available), owner's notes, and the workflow stepper as the main element.
9. **6-step workflow** — On my way → Arrived → In progress → Photos → Customer signature → Completed. Strict order, one tap per step.
10. **Photo proof** — up to 5 photos per job, camera or gallery.
11. **Signature proof** — customer signs on the phone.
12. **Offline-first** — the entire execution flow works without network; actions queue locally and replay exactly once on reconnect; offline banner, pending badges, "last synced" indicator.
13. **Location capture** — location validated at job sites and on attendance check-in.

### Attendance & leave (a large, separate module)
14. **Attendance setup wizard** — the owner configures timezone, offices, weekly offs, and holidays; attendance is gated until this is done.
15. **Offices with map-pin locations** — geofenced office locations.
16. **Check-in / check-out** with location validation; attendance dashboard, monthly views, per-employee month view.
17. **Leave management** — employees apply; owners approve/reject; owners can apply on an employee's behalf; leave history and pending queues; attendance corrections with an owner review sheet; weekly-offs and holiday calendars; short-day/absence tiles.

### Team & skills
18. **Employee management** — invite by phone number, assign skills.
19. **Skills catalog** — global catalog + company skills; jobs and workflow templates are tagged by skill so assignment matches capability.
20. **Workflow templates** — configurable per-service step templates (e.g. a step can require location capture).

### Reports
21. **Owner reports** — request a report (e.g. attendance report), it's generated in the background as a **branded PDF**, owner downloads from the Reports screen.

### Platform
22. **OTP auth + session handling** — expiry lands the user back on login gracefully; forced-update screen via remote config.
23. **Profile** — edit own display name; employees manage their skills.
24. **Web app (fenzit-web)** — web login and an owner/admin console is being built separately.
25. **Audit log** — platform-admin and role changes are logged.

---

## 3. What exists today as "onboarding" (and why it isn't great)

Current first-run sequence:

1. **3-slide benefit tour** (Assign → Track → Done) with Skip — shown identically to *every* user, *before* login, with no role awareness.
2. **Phone screen → OTP screen** (SMS OTP).
3. **Owner:** company setup form (business name etc.) → lands in an empty app (no customers, no employees, no jobs).
4. **Invited employee:** verifies phone → lands in their empty Today tab.
5. Separately, the **attendance setup wizard** gates the attendance module until configured.
6. Every screen has its own empty state.

Specific weaknesses found in the current tour copy (`src/features/onboarding/data.ts`):
- It is **role-blind** — an employee sees the owner-pitched tour.
- **Copy oversells**: "Track your team live on a map" (there is no live fleet map in the shipped scope — only live job-status updates) and "arrival times your customers can count on" (there is no customer-facing surface in v1). A designer working from this copy would design around features that don't exist.
- The tour **ends where the real work begins** — after it, a new owner faces an empty app and the actual setup (invite employees, add customers, attendance wizard) with no guided path.
- There is no activation goal: nothing tells the owner that "invite an employee + create a job" is the path to value.

---

## 4. Data the designer needs from the product team (checklist)

### A. Product fundamentals
1. One-sentence value proposition, and the top 3 pains it replaces, **in an Indian SMB owner's own words**.
2. Business model and launch plan: free beta? paid plans? self-serve signup vs. sales-assisted?
3. Target customer profile: trade(s) served, typical company size (2 techs? 50?), who installs the app first — the owner or their employees.
4. What competitors/alternatives users come from (WhatsApp + paper registers, other FSM apps) — the tour should speak to switching.

### B. Users, roles, terminology
5. Final role names and the words the UI will use — **the app is mid-rename (`owner`→`company_admin`, `technician`→`employee`)**; onboarding copy must use the chosen customer-facing terms.
6. Per-role definition of success ("aha moment"): e.g. owner has invited ≥1 employee and created a job; employee has advanced one step of a real job. These become the onboarding's goals.
7. Whether the two roles will ever share a device (affects "who are you?" flows).

### C. The real first-run facts (from the app/backend)
8. Exact auth rules: country codes supported, OTP length/expiry/resend rules, what happens when SMS is delayed or fails (this is India — OTP friction is the #1 drop-off risk).
9. Company setup: exact required vs. optional fields, what can be deferred, and the rule that a phone already in another company is refused.
10. Invite flow states an employee can land in (invited / active / removed / no company) and what each should see.
11. Screenshots or screen recordings of the **real** app for each role and each major screen (not mockups) — the designer must design against reality.
12. Empty-state inventory: what every major screen shows with zero data, so the onboarding and empty states can be designed as one system.

### D. Verified feature claims (content for any tour/slides)
13. A signed-off list of claims that are true in v1. Current slide copy is not a reliable source (see §3). Safe claims today: live job-status updates on the owner's phone; photo + signature proof; works offline; exact-address navigation; attendance & leave; branded PDF reports.
14. Features shipping at launch vs. later (e.g. push notifications are planned but not live; live map tracking is not in scope) — slides must only sell what's shippable.

### E. Setup & activation path
15. The **minimum path to value**: the shortest setup sequence before an owner gets real value (likely: invite employee → add customer → create job → employee completes it). Which steps are skippable/deferrable?
16. Attendance setup wizard details: what it asks, when it appears, whether it can be deferred — and whether onboarding should mention attendance at all at first run.
17. Decision needed: **demo/sample data** — can a new company opt into a pre-filled demo so screens aren't empty? (This changes onboarding design materially.)
18. Permission-prompt timing plan per role: location, camera/photo library, notifications — which screen each is requested from, so prompts don't fire blind during onboarding.

### F. Brand & content assets
19. Brand kit: logo files, exact palette (theme tokens exist in `src/theme`), illustration style (or confirm the designer creates illustrations), icon set (lucide), and any existing marketing copy/website.
20. Language decision: English-only, or Hinglish/regional support? Tone guidelines.
21. App store listings (name, screenshots, description) so onboarding matches the store promise.

### G. Constraints & success criteria
22. Platforms and devices: iOS + Android, low-end Android support, often-poor connectivity in the field — employee-facing onboarding must be fast and tolerant.
23. Constraints on flow: pre-login tour allowed? Can onboarding add steps between OTP and the app? Any store-review constraints?
24. Success metrics to design for: tour completion rate, % of owners who invite an employee in the first session, time-to-first-job, week-1 retention per role. Pre-launch = no funnel data yet, so state the targets.

---

*Compiled from: `artifacts/planning-artifacts/epics.md`, `docs/repos/fenzit-app/bmad-history/planning-artifacts/{epics,prd}.md`, `artifacts/implementation-artifacts/roles-and-access-spec.md`, and the `fenzit-app` source (`src/features/*`).*
