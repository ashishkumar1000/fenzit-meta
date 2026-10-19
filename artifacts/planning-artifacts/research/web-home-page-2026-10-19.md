# fenzit-web home page: content plan

Date: 2026-10-19. Status: decided by the product owner's delegation ("take your own decision"). Not built. Not committed.

Scope: `workspace/core/frontend/fenzit-web` home page (`HomePage.tsx`), which currently shows the "Coming soon" hero.

## 1. Decisions taken

| # | Question | Decision | Why |
|---|---|---|---|
| 1 | Primary button | **"Join early access"** (email, existing `NotifyForm`). Secondary: "See what it does" (scrolls to features). Add "Get the app" only when store links exist. | Web sign-up is not built, and store listings are not confirmed. A button that leads nowhere costs more than a waitlist. |
| 2 | Audience first | **Business owners**, then technicians. | Owners buy and set up the product. Technicians are the users who must be onboarded by an owner. |
| 3 | Pricing on page | **No prices.** Say "Free to start" only if the owner confirms that. | No pricing exists in the code, and inventing it is a claim we cannot back. |
| 4 | Language | **English only** now. Write plain English, short sentences, so Hindi can follow later. | Matches the app's current copy. |
| 5 | Name | **Fenzit.** | Used in fenzit-web, fenzit-app and the current sprint notes. "Fenzo" appears only in older docs and should be renamed there separately. |

## 2. Features we can state (checked in `fenzit-app` source)

Owner:
- Create a job from a skill, a customer and one or more technicians.
- Job list and job detail with live status and maps navigation to the customer.
- Customers with address search and a map pin.
- Invite technicians and see their skills.
- Live notifications with deep links to the job.
- PDF job and attendance reports.
- Optional attendance module: office geofences, working hours, weekly offs, holidays, enrolment, a live daily dashboard, a monthly report per person, day corrections with a record, and leave (apply, approve, revoke, apply on someone's behalf).

Technician:
- Today's jobs and step-by-step workflow.
- Location captured at steps that require it.
- Photos and the customer's signature.
- Check in and check out, own monthly attendance, leave requests, history.

Platform:
- Phone and OTP sign-in.
- Live updates.

## 3. Features we must NOT claim

- **Offline use.** The offline queue is a placeholder; sync (Epic 8) is deferred. Competitors offer it, so this is a gap to state honestly in the FAQ.
- **Invoicing and payments.** Not built. The only mention is an optional GSTIN field.
- **Customer portal, accounting sync, trip distance reports.** Not built.

## 4. Section order

Keep to nine sections. Each one answers one question.

1. **Header:** logo, "Log in" (text link), no nav menu on phones.
2. **Hero:** headline "Run your field team in real time." Sub-line: assign jobs, see each step move from scheduled to done. One primary button, one secondary link. A flat screenshot of the job list, not a photo.
3. **For owners:** three short points (assign, track, report).
4. **For technicians:** three short points (today's jobs, step proof, check in and out).
5. **Features, four blocks:** Jobs and live status · Proof of work · Customers and addresses · Reports and attendance. One line each, no icon grid.
6. **How it works:** three numbered steps, create a job, assign by skill, track to done.
7. **Trust:** phone sign-in. Each company's data is kept separate. Location is taken only at steps that need it. Say only what the back end enforces.
8. **FAQ, four questions:** Who is it for? Does it work offline? (Not yet.) Do technicians need to install an app? (Yes, the mobile app.) How do I get access? (Join early access.)
9. **Final call and footer:** repeat the early-access form, then links to privacy, terms and contact.

Full feature list goes on a separate `/features` page, so the home page stays short without losing detail.

## 5. Design rules (from `fenzit-app` DESIGN_SYSTEM.md, copied to fenzit-web)

- Inter only. Body 16px minimum.
- Flat backgrounds. No gradients, no photo hero, no decorative loops.
- Colours from tokens only: blue for primary and "in progress", green for done, amber for scheduled, red for cancelled.
- Status words exactly: Done, In Progress, Scheduled, Cancelled.
- Phone first. 16px gutter below 768px, content max 480px.
- Check at 360, 390, 768 and 1280px. No horizontal scroll.
- Touch targets 44px minimum. Visible focus ring. Respect reduced motion.
- No emoji. Sentence case. Buttons name the action.

## 6. Open items

- Store links: needed before "Get the app" can appear.
- Free-to-start: confirm before it is stated.
- Name in older docs: rename "Fenzo" separately.
- Research depth: the homepage evidence is thin. A full deep-recon run would strengthen it, but needs approval for its plan checkpoint.
- Design pass: the BMAD UX step (Sally) should review the layout before build.

## 7. Sources

- [LaunchList, waitlist page examples](https://getlaunchlist.com/blog/waitlist-landing-page-examples-that-convert): one headline, one action, no invented social proof.
- [Flighted, SaaS landing page practices](https://www.flighted.co/blog/10-saas-landing-page-best-practices-that-actually-convert-in-2026): show real product UI.
- [Zoho FSM help, mobile app](https://help.zoho.com/portal/kb/articles/fsm-mobile-app): competitor offline and GPS features, used only to identify gaps.

## 8. Next steps

1. Build the home page in `fenzit-web` once you approve this plan.
2. Commit in `fenzit-web` only after your consent and the BMAD code review.

## 9. Copy update: jobs, attendance and leave (2026-10-19)

The home page said "field management" only. The copy now says the app can be used for field jobs, for attendance and leave, or for both.

Verified in source:
- Attendance is a per-company module. It is on only when the owner enables it and finishes setup (`attendance_access_state`, migration 20261001000001). It does not depend on jobs.
- Jobs, Customers and Reports are always visible for owners (`MainTabs.tsx`). The app has no switch that hides jobs. So "attendance only" works in the data, but the owner still sees the Jobs tab. A product decision is open: hide Jobs when attendance is the only module.
- Leave (apply, approve, revoke, apply on someone's behalf) lives inside the attendance module.

Market check (one standard web search, vendor sources, promotional): field-service vendors pitch attendance and leave as part of the same field platform. Their pitch is check-in verification and leave routed to managers. Their productivity figures have no published method, so the site makes no such claim.

Copy changed in fenzit-web (uncommitted): hero, audience, features (attendance block replaces "reports and attendance"), "How a job works", trust, FAQ (new question: can I use only attendance and leave), and the page title, meta description, Open Graph and JSON-LD text.

Open: confirm the headline "Run your jobs, attendance and leave in one place" and the FAQ answer on attendance-only.
