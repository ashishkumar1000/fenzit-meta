# Creative Brief — "The Pour": Fenzit Logo Loader

> Adopted companion of `artifacts/specs/spec-console-loading-overhaul-2026-11-26/SPEC.md`.
> Provenance: produced 2026-11-26 by the BMAD UX agent (Sally) from the owner's raw idea —
> "filling animation on the Fenzit logo, initially black and white, color filling from
> bottom to top with bubble-type filling, like filling water into a bottle" — after reading
> the actual logo PNGs and researching the liquid-fill cliché baseline. Implementation
> (FenzitMark + FenzitLoader + /logo-preview) is in flight by the BMAD dev agent (Amelia),
> uncommitted, gated on owner preview.

**Deliverable:** `FenzitLoader` React component + hand-authored SVG, pure CSS keyframes, for `fenzit-web`.

## 1. Concept narrative

Someone watching this should feel that the product itself is being *poured into existence* — the logo arrives as an empty white ghost of itself, and every millisecond of waiting visibly fills it with life until the real, full-color Fenzit mark stands complete. It is one bottle, one pour, held — then the pour begins again, patiently, for as long as the data needs. Nothing bounces, nothing fizzes; the motion has the calm of water level rising in glass.

## 2. The mark (from the actual PNGs)

The logo (read from `src/assets/brand/logo-3x.png` / `public/logo.png`, both 360×360) is an **italic lowercase "f" built from two overlapping calligraphic ribbon strokes**, leaning right:

- **Upper ribbon (deep royal blue, ≈`#1D3FAE` → `#2A63E8`):** starts as a sharp diagonal ribbon point at mid-left, sweeps up and over in a broad hook to the upper-right, ending in a rounded, slightly tapered terminal that curls back down-left. This is the f's ascender.
- **Lower ribbon (cyan → teal, ≈`#3EC8F0` right → `#12A38F` lower-left):** a longer S-swoosh — sharp point at upper-left just below the upper ribbon's tail, sweeping right across the middle (reads as the f's crossbar), then curving down and around into a broad rounded descender terminal at lower-left.
- **Weave:** the lower ribbon passes *over* the upper ribbon's stem at the crossing, with a subtle darker seam — the two strokes read as woven, not merged. The whole mark carries a soft drop shadow down-right.
- **White variant** (`fenzit-app/assets/bootsplash/logo.png`): identical geometry, flat white fill — this is the "empty glass" state and matches the native boot splash F, so the web loader and the app splash already share a shape language.

**SVG rebuild rules:** trace the two ribbon paths from `logo-3x.png` (each ribbon is one closed path; the weave is achieved by draw order + a soft shadow at the seam, not by splitting paths). Gradients sampled from the PNG. One shared `<clipPath>` of both paths defines the silhouette. Preserve the soft drop shadow as `filter: drop-shadow(0 2px 6px rgba(22, 49, 140, 0.18))` on the mark group. The silhouette must overlay the boot splash white F within visual tolerance.

## 3. Animation mechanics (pure CSS, no JS animation, no framer-motion)

SVG layers, all inside one `<svg>`:

1. **Ghost layer (always present):** both ribbon paths filled white, `stroke: #D7DCE3`, `stroke-width: 1`, `vector-effect: non-scaling-stroke` — a faint keyline so the empty mark reads on the light `#F9FAFB` backdrop. This is the "black and white" start state (white mark, ink wordmark below).
2. **Color layer:** both ribbons with their real gradients, wrapped in `<g class="loader-liquid" clip-path="url(#fz-mark)">`. The rising fill is a single `translateY` on this group: `100%` (fully below the clip → invisible) → `0%` (fully revealed). The clip does all masking; nothing leaks.
3. **Meniscus:** a thin (3–4 user-unit) white band at 55% opacity pinned to the top edge of the color group, bobbing ±1px on its own 1.8s ease-in-out alternate loop, `scaleX` 1 → 1.02. This is the trembling waterline — deliberately not an animated wave path.
4. **Bubbles:** 5 circles (r 2–4, hero) as children of the `.loader-liquid` group, so they are clipped by the mark **and** bounded by the liquid level automatically. Each rises locally `translateY(0 → -Npx)` with fade in/out over 1.2s linear, staggered via negative `animation-delay` (−0.15s, −0.45s, −0.7s, −1.0s, −1.3s) and per-bubble `cx` set as CSS custom properties. Deterministic, not random. Bubble spawn points live in the mark's lower basin.
5. **Reset:** at cycle end the color layer crossfades to 0 (`opacity`, 400ms) while its `translateY` resets — the white ghost is always beneath, so the mark never disappears or blinks. No "drain" animation.

Overflow containment: `overflow: hidden` on the SVG root; all translations confined to ±100%.

## 4. Timing

Loop durations are hand-authored ambient-loop values, outside the 120/200/320 interaction tokens — same precedent as the Spinner (1.4s/2.2s/1.6s). Document them in the component header comment.

| Phase | Duration | Easing |
|---|---|---|
| Pour (level 0 → 100%) | 2000ms | `cubic-bezier(0.2, 0, 0, 1)` (house `easeStandard`) |
| Meniscus bob | 1800ms, infinite alternate | `ease-in-out` |
| Bubble rise (per bubble) | 1200ms, infinite, negative delays | linear rise, `ease-out` fade |
| Hold at 100% | 600ms | — |
| Reset crossfade | 400ms | `easeStandard` |
| Rest on white ghost | 400ms | — |
| **Full cycle** | **3400ms** | loops seamlessly, verified at 60s+ continuous run |

Wordmark behavior: hero shows "Fenzit" beneath the mark (weight 600, ink `#111827`), fading up 8px once on mount with `durationSlow` + `easeOut` — it **stays put across cycles**; it never re-animates per loop. First load and every repeat behave identically (a loader has no "second visit").

## 5. Variants + reduced-motion fallback

One component, `variant` prop:

- **Hero (full-page loader):** mark 96–120px + wordmark; 5 bubbles; centered over a backdrop of page content under `blur(8px)` + `rgba(249, 250, 251, 0.6)` scrim (blur applies to the page, never the mark — the mark stays crisp).
- **Inline (small surfaces):** mark 28–32px, no wordmark, 3 bubbles, identical cycle timing. Bubbles scale with the viewBox; delays via custom props.

**Reduced-motion (non-negotiable):** render the mark **fully filled** in full color (a static empty ghost would read as a rendering bug) + wordmark, with a single opacity pulse `1 → 0.6`, 1.6s ease-in-out infinite alternate — exactly the existing Spinner fallback pattern. Zero transform animation.

## 6. Cliché bans

- No flat single-blue fill — the fill must reveal the real two-ribbon gradient artwork; that is the entire point.
- No perfectly straight, static waterline — the bobbing meniscus band is mandatory.
- No soda-fizz: no random bubble positions/sizes, no bubbles outside the mark, no bubbles above the liquid level, more than 5.
- No animated wave/slosh path — surface motion capped at ±1px bob.
- No snap, blink, or drain reset — crossfade only; the mark never vanishes between cycles.
- No glow, bloom, or breathing halo on the mark (that is the mobile splash's move; web stays flat).
- No bounces, no overshoot, no non-house easing on the pour.
- No letter-by-letter or per-loop wordmark animation on web.

## 7. Acceptance criteria

1. Animation is pure CSS keyframes driven by CSS custom properties — no JS animation library, no `requestAnimationFrame`.
2. Fill level is a `translateY` on the color group inside a `<clipPath>` of the traced mark silhouette; the revealed artwork is the two-ribbon gradient set sampled from `logo-3x.png`.
3. Rebuilt silhouette overlays the fenzit-app boot splash white F within visual tolerance (side-by-side check).
4. Start state reads black-and-white: white keylined mark, ink "Fenzit" wordmark (hero), color layer at 0%.
5. Cycle runs 3400ms (2000 pour / 600 hold / 400 crossfade / 400 rest), loops seamlessly, and shows no broken frame when observed continuously for 60s+ or interrupted at 0.5s.
6. Bubbles: ≤5 hero / ≤3 inline, deterministically staggered, clipped strictly inside the mark and below the liquid surface — none escape the silhouette at any frame.
7. Under `prefers-reduced-motion: reduce`: static fully-colored mark + opacity pulse (1 → 0.6, 1.6s alternate); no transforms animate.
8. Both variants ship from one component; the backdrop blur never applies to the mark itself, and the mark remains crisp at 28px.
