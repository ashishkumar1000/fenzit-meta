# Digest — round 2: candidate-path follow-up (picker built-ins vs compressor)
Accessed 2026-09-07. 9 tool calls; several primary pages unreachable (403/404/truncated) — aggregation-based claims flagged.

## PATH A — react-native-image-picker built-ins
- Picker latest release 8.2.1, published 2025-05-04 (web-fix only) — nothing shipped since May 2025; any open bug is not getting fixed soon. {GitHub releases API, primary read; high; version-compat}
- v8.0.0 (2025-02-01): HEIC→JPEG conversion automatic on Android when assetRepresentationMode != "current". v8.1.0 (2025-02-16): HEIF→JPEG support (issue #2264, PR #2357) — closest evidence the iOS-side HEIF→JPEG path was addressed. {releases API, primary; high; version-compat}
- Maintainer position (issues #1560/#1535, 2022 era, aggregation): "if maxWidth, maxHeight, or quality are set, images are converted to JPEG" — documented intent is a re-encoded JPEG, not a resized HEIC. {aggregation; medium; pattern}
- Historical iOS regression #1882: with default selectionLimit 0 (PHPicker) + maxWidth/maxHeight/quality, returned file could still end .heic (UIImage invalid → fallback to original path) → "unsupported media type" upload failures; workaround selectionLimit 1 (UIImagePickerController converts natively, loses multi-select) or a post-resize step. Current open/closed state of #1882 UNVERIFIED. {aggregation; medium; implementation-reality}
- Issue #2235 in the picker repo is NOT the EXIF report (it is an unmerged podspec PR from Nov 2023) — the EXIF-stripped-on-iOS-18.3 claim from round 1 has a wrong issue number; the real issue and fix status UNFOUND within budget. {primary read of #2235; high; implementation-reality}
- Picker Android EXIF-orientation correctness when resizing: NO EVIDENCE found either way. maxWidth/maxHeight "silently ignored" at current versions: not searched (budget).

## PATH B — react-native-compressor
- v2.0.0 (2026-06-12, PR #401) migrated the native module to Nitro (react-native-nitro-modules; one Nitrogen spec replacing four). Breaking: requires New Architecture, RN >= 0.75, iOS 13.4+, Android SDK 24, progress events become callbacks, no NativeModules.Compressor, clean native rebuild required. {releases + PR #401, aggregation; medium-high; version-compat}
- 2.0.x fixes are mostly VIDEO (#400/#403 export-fails-not-audio-only, #408 release-build/Expo, #416 QTI AVC encoder); 2.0.1 fixed a nitro import error. NO image-module-specific fix in 2.0.x notes. Image fixes all date to v1.x: EXIF stripped on compress #220 (fixed 1.8.15); iOS manual quality ignored (identical output sizes 0.1–1) #287 (fixed 1.8.25, "re-reported as recurring"); unwanted 90° rotation on Android 12+/14 #280 (fixed 1.15.0); inconsistent Android results on Samsung devices #308 OPEN. {releases + issues, aggregation; medium; implementation-reality}
- Peer deps of 2.0.3 (npm registry primary read): react-native-nitro-modules >= 0.35.0, react-native "*"; requires New Architecture. No RN 0.85/0.86 report found; whether RN 0.86's bundled nitro satisfies the floor is UNVERIFIED. A Nitro 0.35.9-on-RN-0.83 build failure (NitroPromiseAdapter not abstract) was resolved via PR #407; issue #404 explains nitro-modules is intentionally a shared peer dep. {registry primary + issues aggregation; high/medium; version-compat}
- HEIC input for compressor's IMAGE module: undocumented (README lists only output: 'jpg' | 'png'); no dedicated issue surfaced; closest is a video HEVC bug #313. Treat as unknown. {aggregation; medium; pattern}

## Open items (round-2 close-out)
1. Picker 8.2.1 + iOS PHPicker HEIC→JPEG (#1882 current state) — unverified; 8.1.0 suggests a fix landed.
2. The real iOS-EXIF-stripping issue number + fix status — unknown.
3. Picker Android EXIF orientation when resizing — unknown.
4. Picker maxWidth/maxHeight "ignored" at current versions — not searched.
5. Compressor + RN 0.86 / nitro-modules floor — untested.
6. Compressor image-module HEIC input — undocumented.
