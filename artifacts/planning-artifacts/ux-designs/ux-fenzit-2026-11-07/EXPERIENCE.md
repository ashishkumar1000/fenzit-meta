---
title: Fenzit web — Android launch experience delta
type: experience-delta
status: final
created: 2026-11-07
updated: 2026-11-07
ui_system: fenzit-web design system
design_reference: "{./DESIGN.md} — visual identity; this file owns behaviour, IA, copy and states"
applies_to: "workspace/core/frontend/fenzit-web"
---

# EXPERIENCE.md — Android launch experience delta

## Foundation

Marketing site, multi-page (prerendered React Router), consumed on phones (majority,
360–430px), desktops (owner researching during the evening) and AI/answer engines
(llms.txt + meta descriptions). The UI system is the existing fenzit-web design system;
`DESIGN.md` in this folder is the visual identity reference for the delta. This file
specifies only what changes for the Android launch.

## Information Architecture

**Removed surface:** the early-access section (`#early-access`) and its notify form —
gone from the home page, along with the `/api/v1/early-access` call from the web client.

**Added surface:** `#get-app` — "Get the Fenzit app" panel on the home page, same slot
in the section order (after CallBack, before Footer). Home page order becomes: Hero →
Clients → Audience → Features → HowItWorks → Trust → Faq → CallBack → **GetApp**.

**No pages added or removed.** Sitemap, `PUBLIC_PAGES`, routes, speculation rules and
prerender list are unchanged. `llms.txt` gains one line under Company pointing at the
Play Store listing.

## Voice and Tone

The site speaks as a live product now. Three shifts:

| Old register (pre-launch) | New register (live) |
|---|---|
| "Join early access" | "Get the app on Google Play" |
| "We will email you as access opens." | (gone — nothing to wait for) |
| "Launching 2026." | "Live on Google Play for Android." |

Sentence case, plain English, no urgency theatrics. The trial promise stays exactly as
it is ("Every team gets 90 days free.").

## Component Patterns

**Download CTA (the one pattern to rule them all).** Every download affordance is the
`StoreBadge` from `{DESIGN.md.Components}` or a `LinkButton` labelled "Get the app on
Google Play" — never a plain text link, never a bell/waitlist metaphor. It always opens
`{config.playStoreUrl}` in a new tab. Exactly one download CTA per view:

| Surface | Treatment |
|---|---|
| Header strip (all pages) | Text link "Get the app" → `#get-app` (cheap, no badge in the strip) |
| Home hero | Primary: `StoreBadge` md. Secondary buttons unchanged (call back, demo, features) |
| Home `#get-app` panel | `StoreBadge` md + "Book a demo" fallback link |
| Home FAQ | Answers link to the Play listing in prose |
| Use-case pages (all 21) | Hero CTA + bottom CTA become `LinkButton` external "Get the app on Google Play" |
| Attendance page | Same as use-case pages (hero + bottom CTA) |
| Footer (all pages) | `StoreBadge` sm in the contact row |
| Meta tags | "Live on Google Play for Android." — no store link in meta copy |

**External-link rule.** Every Play Store link is `target="_blank"`,
`rel="noopener noreferrer"`, with "(opens in a new tab)" conveyed by the accessible name
suffix " (opens the Play Store)". No interstitial, no confirmation.

## State Patterns

There are no loading, error or empty states to design — the download CTA is a plain
external link; nothing posts anywhere. The only form left on the home page is call-back,
whose states are unchanged and already designed (inline field errors, role=status
confirmation).

Failure fallback: if Play Store is unreachable, that is Google's surface, not ours —
the page still offers "Book a demo" and the phone number as alternate paths. No JS
detects the store's availability.

## Interaction Primitives

- Anchor `#get-app` works from every page via the `/#get-app` qualified form (same
  pattern as `/#how-it-works` today); `scroll-margin-top` keeps it clear of the sticky
  header.
- Badge tap targets ≥48px tall on touch; the whole badge is the target, not the image's
  inner text.
- Focus rings: default token focus ring on the badge's anchor wrapper — visible on
  keyboard tab-through in both sizes.

## Accessibility Floor

- Badge anchor carries a full accessible name ("Get Fenzit on Google Play (opens the
  Play Store)") because the badge image's text is not real text to a screen reader;
  `alt=""` on the image itself (decorative once the anchor is named).
- Colour contrast of new copy follows existing body/heading tokens (AA by construction).
- No information is conveyed by colour or the badge alone: each download CTA is reachable
  and named in text contexts (FAQ answers, strip link) too.
- Keyboard: badge is one tab stop; fallback "Book a demo" link follows in DOM order.

## Key Flows

**Flow 1 — Ravi repairs ACs, finds us from search (phone).**
Ravi searches "ac service software" on his Redmi between jobs, lands on
`/ac-service-software`. The hero says what it does; below the fold the bottom CTA says
"Get the app on Google Play" — he taps, the Play Store opens, ratings visible, he
installs before his next call. *Climax beat: he is trying Fenzit 90 seconds after the
search, with no form and no waiting-for-an-email step in between.*

**Flow 2 — Priya researches on her laptop (desktop).**
Priya, who runs a cleaning company, lands on the home page from a WhatsApp link a friend
sent. The strip says the Android app is live. She scrolls, reads the FAQ, and reaches the
`#get-app` panel: badge on the left, the app's attendance screen on the right. She
scans/taps nothing yet — instead she taps "Book a demo", because she wants to see it with
her own data first. *Climax beat: the page gives her both doors — self-serve download or
human demo — without making her choose between them.*

**Flow 3 — Sampath adds his seven technicians (phone, referred by an owner).**
Sampath already heard about Fenzit from another owner. He arrives straight to the Play
listing from a shared link, then googles "fenzit" to check the company is real. The site
answers with the live-on-Google-Play strip, the FAQ ("Do employees need to install an
app?" — "Yes. Everyone installs the Fenzit Android app from Google Play and signs in
with their phone number."), and the footer badge on the page he lands on. *Climax beat:
the site corroborates the app he is about to install instead of asking him to join a
list.*

## Responsive & Platform

- 360px: hero badge scales to content width without pushing the secondary buttons into
  horizontal scroll (actions wrap; badge keeps intrinsic width, capped by `max-width:
  100%`). `#get-app` panel single column. Footer badge wraps under the contact bar.
- 390/768/1280px: two-column panel from 768px up; badge never smaller than 48px tall.
- Mobile web: no hover-dependent affordance anywhere in the delta; tap-only.
- No native surface is touched; this is the marketing site only. The `smartbanner`-style
  overlays are out of scope.

## Invented section — Search & AI surface

Meta descriptions and `llms.txt` must state the launch fact because answer engines quote
them: home description, og and twitter copy drop "Launching 2026." for "Live on Google
Play for Android."; `llms.txt` gains "Android app: download from Google Play —
{config.playStoreUrl}". Descriptions stay within 25–160 characters.
