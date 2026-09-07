---
title: 'Technical research: client-side image compression before upload in React Native'
type: 'technical'
topic: 'Client-side image compression/resize before upload in React Native'
decision: 'Pick the client-side resize/compress approach for fenzo-app photo upload (RN 0.86 CLI, bun, new arch, not Expo); gallery photos upload uncompressed up to 10 MB, target ~2048px max dimension before presign'
source: 'live web research (npm registry, GitHub repos/issues, library docs, vendor benchmarks)'
status: complete
preset: 'standard'
validation: 'normal'
created: '2026-09-07'
updated: '2026-09-07'
verified_claims: 5
unverified_claims: 1
---

# Technical research: client-side image compression before upload in React Native

**Decision this research serves:** Pick the client-side resize/compress approach for fenzo-app photo upload (RN 0.86 CLI, bun, new arch, not Expo). Gallery photos currently upload uncompressed (up to 10 MB) direct to R2 via presigned URL; target ~2048px max dimension before presign. User constraint: server-side processing is cost-negative because bytes would pass through the server instead of going direct via presigned PUT.

## Executive summary

**Do not add a new library. Use `react-native-image-picker`'s built-in downscale options — `maxWidth`/`maxHeight: 2048` + `quality: 0.8` — on both the camera and gallery paths, and gate the change on an on-device HEIC smoke test.** Fallback if the smoke test fails: `react-native-compressor` v2.0.3.

The three findings that drive this:

1. **The original plan's library is out.** `@bam.tech/react-native-image-resizer` — the library the deferred-story note named — has shipped nothing since Nov 2024 and its iOS podspec breaks `pod install` on RN 0.84+ (open issue #437), with an unmerged wontfix New-Arch crash fix. Two researchers corroborated independently. [2][6]
2. **A zero-dependency path already exists in the app.** The picker's `quality` (default 0.8) and aspect-preserving `maxWidth`/`maxHeight` bounds downscale on both platforms, and the maintainer-documented intent is that setting them converts output to JPEG (v8.1.0 explicitly added HEIF→JPEG support). For an image-only, 5-photos-per-job use case this avoids every native-module risk the research surfaced. [5][21][22]
3. **Resolution is the size lever.** A 4032×3024 iPhone photo (3.93 MB) lands at ~361 KB at 1600px q82; compressing without resizing at q80 only reaches ~3–4 MB. 2048px @ q80 interpolates to ~500 KB–1 MB (estimate, not measured) — a ~10–20x cut on the worst 10 MB case. [16][17]

**Biggest caveat:** the picker has itself been frozen since May 2025 (8.2.1), and its iOS multi-select (PHPicker) path had a HEIC→JPEG regression (#1882: output still `.heic`) whose current fix status could not be verified — release notes suggest a fix landed in 8.1.0, but the issue state is unread. The smoke test resolves this; if it fails, the compressor fallback carries its own unverified edges (nitro-modules floor vs RN 0.86, undocumented HEIC image input, open Samsung-Android inconsistency). [21][22][23]

## Dimension 1 — Library landscape & maturity

### Maturity table

All registry data fetched live from the npm registry + npm downloads API on 2026-09-07 [1].

| Package | Latest | Published | dl/mo | Verdict |
|---|---|---|---|---|
| `@bam.tech/react-native-image-resizer` | 3.0.11 | 2024-11-25 | 404,648 | **Stale** — nothing since Nov 2024 |
| `react-native-compressor` | 2.0.3 | 2026-07-25 | 834,734 | Current (~6 weeks; 3 releases in 6 weeks) |
| `expo-image-manipulator` | 57.0.16 | 2026-09-04 | 7,618,458 | Very current (3 days), Expo-coupled |
| `react-native-image-crop-picker` | 0.51.1 | 2025-10-21 | 840,583 | Stale ~10.5 months; 557 open issues, 99 open PRs |
| `react-native-nitro-image` | 0.15.2 | 2026-08-20 | 473,125 | Current; **pre-1.0** |

The legacy `react-native-image-resizer` name (1.4.5, 2021) carries an explicit deprecation notice pointing at the @bam.tech scope; `@react-native-community/image-resizer` does not exist on npm [1].

### What this rules out

- **`@bam.tech/react-native-image-resizer` — out.** Frozen since Nov 2024, and its iOS podspec breaks `pod install` on RN 0.84+ (issue #437, Mar 2026, unmerged): it declares RCT-Folly/React-Codegen against RN's prebuilt core [2][6]. It also has an unmerged wontfix crash fix for New-Arch iOS (PR #439: an NSException escaping an async completionBlock becomes an EXC_BAD_ACCESS) and documents iOS EXIF-orientation handling as Android-only [2].
- **`react-native-image-crop-picker`** — stale and poor repo health; out [1].
- **`expo-image-manipulator`** — very current, but peer-depends on `expo`; bare-CLI usability was **not verifiable this run** (expo docs unreachable) — unverified, and moot given the alternatives [1].
- **`react-native-nitro-image`** — current, hard-New-Arch, and does exactly the pre-upload flow (`saveToTemporaryFileAsync('jpg', 90)` / `toEncodedImageData('jpg', 50)`), but pre-1.0 with a reported local-file-path limitation (open issue; possibly conflating two libraries) and Nitro memory-leak history — maturity risk [3][4].

### The live candidates

- **Picker built-ins (zero new dependencies)** — `quality` (default 0.8) and aspect-preserving `maxWidth`/`maxHeight` bounds downscale on both platforms (fit-within-bounds, not exact-edge targets) [5]. Round 2 added: maintainer statements across issues #1560/#1535 say that setting any of maxWidth/maxHeight/quality converts output to JPEG, and v8.1.0 (Feb 2025) explicitly added HEIF→JPEG support; the historical iOS PHPicker regression #1882 (resized output still `.heic` under `selectionLimit: 0`) may remain open — release notes suggest a fix, state unverified [21][22]. The picker has shipped nothing since 8.2.1 (May 2025) [21].
- **`react-native-compressor`** — the most-adopted actively-maintained media compressor; ~50 KB APK footprint (self-reported, vs ~9 MB FFmpeg), no FFmpeg bundled, bare-CLI primary install path [6]. Round 2 resolved the version split: **v2.0.0 (Jun 2026) is a Nitro rewrite** — requires New Architecture, RN ≥ 0.75, peer `react-native-nitro-modules >= 0.35.0`; the 2.0.x bug fixes are mostly **video**, while image-path fixes all date to v1.x (EXIF stripped on compress → 1.8.15; iOS quality-ignored → 1.8.25, re-reported as recurring; Android 90° rotation → 1.15.0; Samsung-Android inconsistency #308 still **open**) [23]. HEIC input for its **image** module is undocumented [23]. No RN 0.85/0.86 compatibility report exists; whether RN 0.86's bundled nitro satisfies the peer floor is unverified — a related Nitro-0.35.9-on-RN-0.83 build failure was fixed via PR #407, and issue #404 explains nitro-modules is intentionally a shared peer dep [23].

### Consensus check

An aggregator synthesis (medium confidence; its numbers matched the primary registry data) frames the consensus as compressor for all-in-one media+upload and @bam.tech for focused resize; 2026 new entrants (`react-native-image-compression-kit` — target-size `maxBytes` with HEIC/AVIF input; Nitro-based `spiral-image`) are early and unproven [1].

## Dimension 2 — The industry-standard pattern

### Max dimension

There is **no single industry cap — the cluster is 1200–2048px, chosen per use case** [7]: upload-pipeline writeups use 2048px, 1600px, and 1200px for different display needs. WhatsApp (the consumer default) lands at ~1600px longest edge, JPEG q70–80, EXIF stripped — a 3–5 MB original becomes ~200–300 KB, with full resolution available only as an explicit "HD"/document send [8]. Two counterweights to "resize at upload": Cloudinary's guidance pushes upload-originals-then-resize-at-delivery for CDN-managed pipelines, and AWS Amplify has no built-in resize at all — its team's own suggested workarounds for years-old feature requests are client-side resize or a post-upload Lambda [9][10]. Since our pipeline stores photos for job records (no dynamic display-size transforms today), capping at upload is the storage/bandwidth control the Cloudinary docs themselves reserve for this case [9].

### JPEG quality

**q0.8–0.82 is the recurring sweet spot**; 0.95 roughly doubles size with no visible benefit after downscaling [11]. **Fixed one-shot at ~0.8 is the default pattern; quality-stepping is an opt-in for a hard byte cap** — canonical implementations (jpegoptim's `--size=` bisection, JPEG-Click's exponential+binary search) exist, but no measured head-to-head against one-shot q0.8 was found, and jpegoptim notes size-to-quality is not perfectly monotonic, which is why bisection is used [12]. Our backend caps size only at confirm time (50 MB on a client-reported value), so there is no hard byte cap demanding stepping.

### HEIC and PNG

- **Transcode HEIC before upload for compat, never for compression**: iOS does not auto-transcode, S3/R2 does not transcode, and non-Safari browsers cannot display HEIC; detection should use `ftyp` magic bytes, not extension [13]. The known failure mode is "fake .jpg" files renamed from HEIC that upload fine and render broken [13].
- **The transcode tax is real**: HEIC→JPEG at quality-matched settings *increases* size ~1.95x median (range 1.5–2.9x) across a 96-encode benchmark — HEVC/HEIC is ~50% more efficient than JPEG, so transcoding is purely a browser/CDN compatibility cost [14] (vendor-run benchmark, single publisher — medium confidence).
- **PNG screenshots stay PNG** — JPEG artifacts destroy text/UI edges [11].

### EXIF / orientation

Resize/re-encode paths that strip EXIF without applying rotation produce 90°/180°-rotated photos — documented on the image-picker iOS path and Android 10+ downscale paths [5][15], and in compressor's own history (Android 90°-rotation bug #280, fixed 1.15.0) [23]. **If GPS/timestamp EXIF need not survive (it need not for our job photos), orientation-baked JPEG output is acceptable — orientation must be APPLIED, not preserved as a tag.** Whether the picker's Android resize path applies orientation correctly has no evidence either way [22] — part of the smoke test.

### Resulting sizes

Two measured data points agree that **resolution is the lever, quality is the trimmer**:
- 4032×3024 iPhone photo, 3.93 MB → 1600×1200 JPEG q82, metadata stripped → **~361 KB** [16].
- 4032×3024 ~6 MB → 1920×1440 resize only → ~1.8 MB → q80 → ~350–480 KB (WebP); compressing the *unresized* original at q80 only reaches ~3–4 MB [17].

No direct 2048×1536@q80 measurement was found; interpolating across the above suggests **~500 KB–1 MB** — an estimate, not an evidenced number.

## Dimension 3 — Integration reality

### Bun + native autolinking

Bun works with native autolinking; the one real friction source is its **isolated linker** (default in workspaces), which breaks hoisting-assuming podspecs (`pod install` fails with `rb_sysopen`) and Metro transitive resolution — fix: `linker = "hoisted"` in bunfig.toml. Bun also skips postinstall scripts by default, so native-CLI-dependent packages need `trustedDependencies` entries [18]. No image-manipulation-library-specific Bun incompatibility was found anywhere — the friction is generic, not library-specific.

### Presigned-URL guidance

Supabase/Amplify presigned-URL docs prescribe **client-side processing by pattern**: no built-in compression exists in either; the recommended flow is resize+quality before the PUT, with `allowedMimeTypes` on the bucket (a signed URL means anyone holding it can PUT) and content verification server-side, since the content-type header is client-controlled [19][20]. Neither prescribes a specific native library.

### Production reality of the native-resizer path

Crash reports for `react-native-compressor` are current-version and mostly fixed; most severity sits in the **video** path, not images [3][23]. The OOM record of the @bam.tech resizer (Android since 2017, iOS since 2020, a graceful-OOM request closed wontfix, fragmentation-not-free-RAM as the cause, at least one team moving resize to the server) is the cautionary tale for *any* native resizer: handle huge photos deliberately and fail gracefully [2].

## Cross-dimension insights

- **Every actively-maintained native option carries a non-image caveat** (compressor: video-first fixes + undocumented HEIC image input + nitro peer floor; nitro-image: pre-1.0; expo-image-manipulator: Expo-coupled). For an image-only, 5-photos-per-job need, that is exactly why the zero-dependency picker path wins — the riskiest component (the picker) is *already installed and already exercised in production by this app's camera path*.
- **The pattern dimension caps how much precision the picker's "fit within bounds" semantics can lose**: since resolution — not exact edge length — drives the size outcome, a 2048-bound instead of a guaranteed-2048-longest-edge loses almost nothing.
- **The HEIC picture is self-consistent but conditional**: the compat research says transcode (browser viewing), the transcode tax says it *grows* files ~2x, and the picker path may already transcode by intent — so the smoke test isn't just about upload success, it's about not shipping the "fake .jpg renders broken" failure mode. Note the safety net: our backend mime contract already accepts `image/heic`, so a picker that returns HEIC unchanged would still upload — the failure would be display-time, not upload-time.

## Recommendations

1. **Adopt the picker built-ins as the primary approach** — `quality: 0.8`, `maxWidth: 2048`, `maxHeight: 2048` on both `launchCamera` and `launchImageLibrary` in the photo-pick flow; keep the existing 10 MB client validation as a backstop. *Confidence: high for the documented behavior (picker options docs, high) + maintainer conversion statements (medium).* Downstream: this is a fenzo-app-only change; no BE change needed.
2. **Gate on an on-device HEIC/multi-select smoke test** — pick a real iPhone "High Efficiency" photo via gallery multi-select, verify the returned `uri`/`mime`/size, and check orientation on Android with a resized photo. This resolves the #1882 ambiguity and the Android-EXIF-orientation gap, both of which are cheap to test and expensive to get wrong (broken-orientation job photos). *Confidence: the test is mandatory precisely because these claims are medium/unverified.*
3. **Fallback to `react-native-compressor` v2.0.3 only if the smoke test fails** — test the nitro-modules floor against RN 0.86's bundled nitro and the image-module HEIC input before committing to it; both are unverified. *Confidence: medium — actively maintained and most-adopted, but image-path HEIC undocumented and Samsung inconsistency open.*
4. **Do not process server-side** — cost-negative per the decision frame (bytes would route through the server instead of the direct presigned PUT), and the presigned-URL ecosystem's own guidance prescribes client-side processing [19][20].
5. **Keep the pattern simple: one-shot q0.8, 2048px longest edge, no quality-stepping, no EXIF preservation** (orientation applied, metadata dropped). No hard byte cap exists in our presign flow to justify stepping. *Confidence: high for the pattern cluster; the 2048px size outcome (~500 KB–1 MB) is an interpolation, not a measurement.*

## Open questions

1. **Picker 8.2.1 + iOS PHPicker HEIC→JPEG regression (#1882) — current open/closed state.** To answer: read the issue state directly or, cheaper and authoritative, run the device smoke test (Rec 2).
2. **The real iOS EXIF-stripping issue in the picker** (round 1 cited #2235, which is actually an unrelated podspec PR) — the bug's issue number and fix status are unknown. To answer: targeted GitHub search within the picker repo for "EXIF stripped iOS 18".
3. **Picker Android EXIF-orientation correctness when resizing** — no evidence either way. To answer: device smoke test (Rec 2).
4. **Compressor + RN 0.86** — no report found; whether RN 0.86's bundled nitro satisfies `>= 0.35.0` is untested. To answer: `bun add` + clean native build test, only if the fallback is invoked.
5. **Compressor image-module HEIC input** — undocumented. To answer: a 10-line experiment, only if the fallback is invoked.
6. **What exactly 2048×1536 @ q80 lands at in KB** — interpolated (~500 KB–1 MB), not measured. To answer: the smoke test's size readout.

## Source appendix

|1 | package metadata, publish dates, download counts, deprecation notices for five candidates + legacy names | npm registry + npm downloads API (fetched live) | 2026-09-07 | 2026-09-07 | high
|2 | @bam.tech resizer staleness, RN 0.84+ pod break (#437), wontfix crash fix (PR #439), iOS EXIF Android-only, OOM history #97/#143/#283 | [github.com/bamlab/react-native-image-resizer](https://github.com/bamlab/react-native-image-resizer) | 2017–2026 | 2026-09-07 | high
|3 | compressor current-version fix record; severity in video path | [github.com/numandev1/react-native-compressor](https://github.com/numandev1/react-native-compressor) | 2023–2025 | 2026-09-07 | high
|4 | nitro-image local-file limitation, crashes, maturity risk | [github.com/mrousavy/react-native-nitro-image](https://github.com/mrousavy/react-native-nitro-image) | 2024–2026 | 2026-09-07 | medium
|5 | picker quality default 0.8; maxWidth/maxHeight as aspect-preserving bounds; EXIF stripping on resize paths | [react-native-image-picker options docs](https://niomenger.github.io/react-native-image-picker-website/docs/options) + [SO 40274875](https://stackoverflow.com/a/40274875) | current | 2026-09-07 | high
|6 | compressor New-Arch claim, ~50 KB vs ~9 MB FFmpeg, bare-CLI primary path | [react-native-compressor README](https://github.com/numandev1/react-native-compressor) | current | 2026-09-07 | high (50 KB self-reported)
|7 | max-dimension writeups: 2048px / 1600px / 1200px per use case | [DEV mursalnasaj02](https://dev.to/mursalnasaj02/efficient-client-side-image-preprocessing-for-ai-wrappers-3ebb), [Scalebloom](https://www.scalebloom.com/blog/client-side-image-optimization/), [Engineered.at](https://engineered.at/articles/building-a-fast-image-upload-pipeline-in-the-browser-with-javascript) | 2025–2026 (unverified dates) | 2026-09-07 | medium
|8 | WhatsApp ~1600px, q70–80, EXIF stripped, 3–5 MB → 200–300 KB | WhatsApp Help Center / Android Authority / WABetaInfo (aggregated) | unknown | 2026-09-07 | medium
|9 | resize-at-delivery vs at-upload doctrine | [Cloudinary docs](https://cloudinary.com/documentation/image_optimization) | current | 2026-09-07 | high
|10 | Amplify: no built-in resize; client-side or Lambda workarounds | [amplify-js #10930](https://github.com/aws-amplify/amplify-js/issues/10930), [#6081](https://github.com/aws-amplify/amplify-js/issues/6081) | 2023+ | 2026-09-07 | high
|11 | q0.8–0.82 sweet spot; 0.95 doubles size; PNG for screenshots | [DEV multigrid](https://dev.to/multigrid/sending-an-image-to-a-model-from-the-browser-8bd) | unknown | 2026-09-07 | medium
|12 | target-size bisection implementations; non-monotonicity caveat | [jpegoptim](https://github.com/tjko/jpegoptim), [JPEG-Click](https://github.com/vihanb/JPEG-Click) | current | 2026-09-07 | medium
|13 | HEIC not auto-transcoded (iOS/S3); magic-byte detection; fake-jpg failure mode | [SO 71820862](https://stackoverflow.com/questions/71820862/how-can-i-get-heic-image-format-working-in-s3), [aws.s3.fm](https://aws.s3.fm/free-heic-detection-and-conversion/) | 2022+ | 2026-09-07 | high
|14 | HEIC→JPEG grows size ~1.95x median (1.5–2.9x) | [cleanor.app benchmark](https://cleanor.app/blog/heic-to-jpg-conversion-file-size-tax-benchmark) | 2026 | 2026-09-07 | medium (vendor, single publisher)
|15 | picker iOS path destroys EXIF; Android stale-EXIF rotation bugs | [image-picker #2235/#1413/#920](https://github.com/react-native-image-picker/react-native-image-picker/issues/1413) + [Sprocket](https://medium.com/@sprocket-fy/fixing-image-orientation-and-orientation-related-crashes-431d1c9a9a1) | 2025-ish | 2026-09-07 | high (⚠ #2235 number disproven in round 2 — see Open Q2)
|16 | 3.93 MB → ~361 KB at 1600×1200 q82 | [roundcut.app](https://roundcut.app/blog/how-to-reduce-photo-file-size-on-iphone/) | unknown | 2026-09-07 | medium
|17 | 6 MB → ~1.8 MB (1920px) → ~350–480 KB (q80); no-resize q80 only 3–4 MB | [pictuary.com](https://pictuary.com/blog/how-to-reduce-image-file-size-before-uploading) | unknown | 2026-09-07 | medium
|18 | Bun isolated linker breaks pods; hoisted fix; trustedDependencies | [bun #25870](https://github.com/oven-sh/bun/issues/25870), [RN-firebase #8956](https://github.com/invertase/react-native-firebase/issues/8956), [Expo docs](https://docs.expo.dev/guides/using-bun/) | current | 2026-09-07 | high
|19 | presigned uploads carry no compression; client-side resize prescribed; allowedMimeTypes | [Supabase Storage docs](https://supabase.com/docs/guides/storage) | current | 2026-09-07 | medium (via search summary)
|20 | Amplify corrupted-unless-fetched upload report | [SO 49341597](https://stackoverflow.com/questions/49341597/react-native-image-upload-via-aws-amplify-using-storage-class) | 2018+ | 2026-09-07 | high
|21 | picker releases: 8.0.0 HEIC→JPEG on Android; 8.1.0 HEIF→JPEG; frozen at 8.2.1 (2025-05-04) | [picker releases API](https://api.github.com/repos/react-native-image-picker/react-native-image-picker/releases?per_page=5) | 2025-02→2025-05 | 2026-09-07 | high (primary read)
|22 | maintainer "options set ⇒ JPEG conversion"; #1882 iOS PHPicker HEIC regression; Android EXIF-when-resizing unknown | [picker issues #1560/#1535/#1882](https://github.com/react-native-image-picker/react-native-image-picker/issues/1882) | 2022–2024 | 2026-09-07 | medium (aggregation)
|23 | compressor v2.0.0 Nitro rewrite (New Arch, RN ≥ 0.75); image fixes all v1.x; #308 Samsung open; HEIC image input undocumented; nitro peer-dep design | [compressor releases](https://github.com/numandev1/react-native-compressor/releases), [PR #401](https://github.com/numandev1/react-native-compressor/pull/401), [issue #404](https://github.com/numandev1/react-native-compressor/issues/404) | 2024–2026 | 2026-09-07 | medium-high

## Staleness map

Freshness bars (technical pack): versions & compatibility ≤ 1 mo · ecosystem signals ≤ 6 mo · landscape ≤ 12 mo · patterns ≤ 2 yr.

| Claim class | Sources | Pub date | Re-check by |
|---|---|---|---|
| Picker version/freeze (8.2.1, May 2025) | 21 | 2025-05 | **Already past bar** — re-check now; low urgency: no version pins on our side to update, and a frozen dep is a *stable* dep |
| Compressor version (2.0.3, Jul 2026) + nitro peer floor | 1, 23 | 2026-07 | 2026-08 (only if the fallback is invoked) |
| HEIC transcode numbers (1.95x benchmark) | 14 | 2026 | 2027-01 (≤ 6 mo as ecosystem signal) |
| Pattern claims (2048px, q0.8, resize-is-the-lever) | 7, 8, 11, 16, 17 | 2025–2026 | 2027-09 (patterns ≤ 2 yr) |
| Landscape consensus | 1 | 2026-09 | 2027-09 (≤ 12 mo) |

**Earliest re-check: the picker version claim — already past its 1-month bar.** This matters little here because the recommendation *removes* a dependency rather than adding one, but a future story should confirm no picker release shipped since May 2025 before relying on HEIC conversion behavior.