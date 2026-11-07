---
title: Fenzit web — Android launch CTA treatment
type: design-delta
status: final
created: 2026-11-07
updated: 2026-11-07
ui_system: fenzit-web design system (tokens.css generated from fenzit-app src/theme; components in src/components/ui)
inherits: "{fenzit-web design system} — this file specifies only the delta for the download CTA surfaces"
applies_to: "workspace/core/frontend/fenzit-web"
---

# DESIGN.md — Android launch CTA treatment

## Brand & Style

Fenzit's web voice and look are already fixed by the existing design system: Inter,
near-white pages, white cards with hairline borders, blue `{color.primary}` as the single
action colour. This change adds no brand new look — it re-expresses the existing style
around one new fact: the Fenzit Android app is on Google Play **today**, so every
"join the waitlist" affordance becomes a "get the app" affordance.

The one new visual object is the **Google Play badge** (the official "Get it on Google
Play" mark). It is the only place Google's brand appears; everything else stays Fenzit.

## Colors

No new colours. All surfaces keep the existing tokens:

- Panel surface: `{color.surface.card}` on `{color.surface.page}`, hairline `{color.border.subtle}`.
- Action/attention colour stays `{color.primary}` (blue) for links and focus rings.
- The badge keeps its own official chrome (black card, white border, Play logo in its
  brand colours) and never gets recoloured or restyled.

## Typography

Existing scale only: `{typography.heading}` for the section title, `{typography.body}`
for the lead, `{typography.small}` for the supporting line under the badge. Sentence case
everywhere. No caps, no exclamation marks, no "Download NOW" energy — the badge itself is
the loud element; the copy stays quiet and factual.

## Layout & Spacing

**GetApp section** (replaces EarlyAccess on the home page, same slot after CallBack):

- Same section rhythm as EarlyAccess: `{space.6}` vertical padding, content in a
  `{radius.large}` card panel with `{shadow.small}`, matching the old panel so the page
  does not jump stylistically.
- Desktop (≥768px): two columns — copy + badge left, phone art right; `4rem` column gap.
- Mobile (<768px): single column, copy, badge, then art; badge takes the full row width
  up to its natural width, never overflows 320px content.
- The badge sits on its own row with `{space.4}` above (after the supporting line) and
  `{space.2}` below (before the "or book a demo" fallback link). Minimum tap height 48px;
  minimum clear space around the badge equal to half its height, per Google's badge rules.

## Elevation & Depth

Reuse `{shadow.small}` on the panel. The badge is a flat image inside the panel — no
extra shadow, no hover scale. Hover/press feedback is the standard `LinkButton` opacity
shift applied to the badge's anchor wrapper (0.9 opacity on hover, full on press).

## Shapes

Badge corners are rounded with `{radius.medium}` — the same token as the buttons — so the
badge matches the site's control shape. This is an owner decision (2026-11-07) that
overrides the original don't-round rule: the asset's transparent margin is trimmed once,
and the rounding is applied in CSS; the official artwork itself is not recoloured or
rebuilt. Everything else keeps `{radius.large}` panels and `{radius.medium}` chips
exactly as today.

## Components

**StoreBadge (new, one place: `src/components/ui/StoreBadge`)**

- Renders the official "Get it on Google Play" badge image as an external `<a>` to
  `{config.playStoreUrl}` with `target="_blank"` and `rel="noopener noreferrer"`.
- Accessible name on the anchor: "Get Fenzit on Google Play (opens the Play Store)".
- Two sizes: `height 56px` (hero, download panel) and `height 48px` (footer). Width scales
  by the asset's intrinsic ratio (~2.72:1).
- Props: `size?: "md" | "sm"`, everything else fixed — the URL comes from config so the
  badge, footer and FAQ can never disagree.

**GetApp section (replaces EarlyAccess)**

- `SectionHeading` title "Get the Fenzit app"; lead "Live on Google Play for Android
  phones. Every team gets 90 days free."
- `StoreBadge` size `md`.
- One quiet fallback link under the badge: "Prefer a walkthrough? Book a demo" →
  `/book-demo` (existing page).
- Perk dots (existing pattern): "Built for owners and employees." / "Phone-number
  sign-in — no usernames." / "Every team gets 90 days free." — all facts true today.
- Right column art: reuse the existing phone-panel art pattern (`HeroPreview`'s panel
  style, one attendance panel) so the section matches the hero without new illustration.
  `[ASSUMPTION] If reuse is not cheap, the panel ships copy+badge only — never new artwork.`

**Header strip**

- Same strip; text becomes "The Fenzit Android app is live on Google Play." with the
  strip link "Get the app" → `#get-app` on the current page (falls back to home anchor
  from inner pages, same pattern as existing `/#how-it-works` links). The phone tel link
  stays.

**Footer**

- Solution card for the attendance app: note changes from "iOS & Android mobile" to
  "Android app on Google Play".
- A `StoreBadge` size `sm` joins the contact row (next to LinkedIn/contact bar), so every
  page footer carries the store link.

## Do's and Don'ts

**Do**

- Use the official badge asset as-is, one shared component, one config URL.
- Keep exactly one download CTA per view; supporting links stay secondary style.
- Say "Android" where a platform is named — and only there.

**Don't**

- Don't mention iOS, an iPhone build, "coming to iOS", or an App Store badge — iOS is not
  live and must not appear on the site.
- Don't keep any early-access/waitlist wording, iconography (bell/zap badge), or the
  notify form anywhere.
- Don't recolour or rebuild the Play badge in CSS; shape comes from the `{radius.medium}`
  clip only, per the owner's 2026-11-07 decision.
- Don't add raw hex, spacing, or radii — tokens only.
