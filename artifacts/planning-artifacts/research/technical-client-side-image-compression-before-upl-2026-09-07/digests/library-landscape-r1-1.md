# Digest — dimension 1: library landscape & maturity (round 1, researcher 2)
Accessed 2026-09-07. All registry data fetched live from npmjs.org registry + npm downloads API.

## 1. Version / freshness / adoption
| Package | Latest | Published | dl/mo | Verdict |
|---|---|---|---|---|
| @bam.tech/react-native-image-resizer | 3.0.11 | 2024-11-25 | 404,648 | STALE ~9.5–21 mo, nothing since |
| react-native-compressor | 2.0.3 | 2026-07-25 | 834,734 | Current (~6 wk; 3 releases in 6 wk) |
| expo-image-manipulator | 57.0.16 | 2026-09-04 | 7,618,458 | Very current (3 days) |
| react-native-image-crop-picker | 0.51.1 | 2025-10-21 | 840,583 | Stale ~10.5 mo; repo health poor (557 open issues, 99 open PRs) |
| react-native-nitro-image | 0.15.2 | 2026-08-20 | 473,125 | Current; pre-1.0 |

Legacy: react-native-image-resizer@1.4.5 (2021) deprecated → renamed @bam.tech; @react-native-community/image-resizer does not exist (dead).

## 2. New Architecture / RN 0.86
- compressor: README "New Architecture (Turbo Module) Supported", RN >= 0.60, autolinking both platforms. BUT npm 2.0.3 peerDeps react-native-nitro-modules >=0.35.0 → v2.0.x is Nitro-based (repo has nitrogen/, nitro.json). RN 0.86-specific statement: not found (medium). {npm registry + repo README; high/medium; version-compat}
- @bam.tech resizer: New Arch since 3.0.0 (TurboModule + retrocompat). ph:// camera-roll URIs broken under New Arch (maintainers point to image-picker). iOS EXIF orientation unhandled. {repo README; high; version-compat}
- image-crop-picker: New Arch from >= 0.50.0 only. No RN 0.80+ statement. {README; high; version-compat}
- nitro-image: hard-requires New Architecture; saveToTemporaryFileAsync('jpg', 90) / toEncodedImageData('jpg', 50) = exactly the pre-upload flow; but pre-1.0, 20 open issues / 24 open PRs. {README; high; version-compat}
- expo-image-manipulator: peer expo:*, dep expo-image-loader; bare-CLI requirement UNVERIFIED (docs.expo.dev 404'd; unverified belief). {npm metadata; low; version-compat}

## 3. Native footprint / Expo coupling
- compressor: ~50 KB APK claim self-reported (vs ~9 MB FFmpeg); no FFmpeg bundled; bare CLI primary path; v2.x adds nitro-modules runtime dependency (not Expo-dependent). {README; high; version-compat}
- nitro-image: requires nitro-modules + pod 'SDWebImage' modular headers. Not Expo-dependent; adds dependency chain. {README; high; version-compat}

## 4. Consolidation / consensus
- 2026 new entrants unproven: react-native-image-compression-kit (Jun 2026, target-size maxBytes, HEIC/HEIF/AVIF input, 0.2.x), spiral-image (Nitro, ~0 stars), expo-image-and-video-compressor (Expo module). Low confidence, snippets only.
- Aggregator consensus (medium, matched primary numbers): compressor for all-in-one media+upload; @bam.tech for focused resize. Both flagged New-Arch ready.

## Claims of note
1. compressor 2.0.3 pub 2026-07-25, 834,734 dl/mo, peer nitro-modules >=0.35.0 {npm registry; high; version-compat}
2. compressor New Arch + RN>=0.60 + ~50KB vs ~9MB FFmpeg, bare-CLI primary {README; high; version-compat}
3. @bam.tech 3.0.11 pub 2024-11-25, 404,648 dl/mo, stale {npm; high; version-compat}
4. @bam.tech New Arch since 3.0.0; iOS EXIF unhandled; ph:// broken under New Arch {README; high; version-compat}
5. image-crop-picker 0.51.1 stale, New Arch >=0.50, 557 open issues {npm+README; high; version-compat}
6. nitro-image 0.15.2 pub 2026-08-20, 473,125 dl/mo, hard New Arch, resize+JPEG save/encode for upload, pre-1.0 {npm+README; high; version-compat}
7. expo-image-manipulator 57.0.16 pub 2026-09-04, 7.6M dl/mo, Expo-coupled {npm; high; version-compat}
8. bare-CLI expo-image-manipulator needs expo-modules-core natively — UNVERIFIED {npm metadata; low; version-compat}
9. legacy resizer deprecated/renamed; @react-native-community/image-resizer nonexistent {npm deprecation; high; ecosystem}
10. consensus compressor + @bam.tech; 2026 entrants early {aggregation; medium; landscape}

## Not found
- RN 0.86 explicit support statements anywhere (only permissive peer ranges).
- Download trend direction (point values only).
- GitHub commit/pushed_at (api.github.com blocked) — recency inferred from npm publish dates.
- expo docs installation page (404 twice).
- Whether compressor's nitro-modules >=0.35 works cleanly with RN 0.86's bundled nitro version.

## Round-2 leads
1. CONTRADICTION: compressor README says TurboModule supported vs npm 2.0.x Nitro peer dep — is v1.x TurboModule and v2.0.x a Nitro rewrite? Which path is stable? Read releases/changelog directly.
2. compressor issues for RN 0.86 / New Arch regressions.
3. expo-image-manipulator bare-CLI via expo/expo monorepo README (docs unreachable).
4. @bam.tech maintenance health: active fork or handover?
5. compressor's "50 KB" vs nitro-image's SDWebImage/Coil footprint — self-reported, unverified.
