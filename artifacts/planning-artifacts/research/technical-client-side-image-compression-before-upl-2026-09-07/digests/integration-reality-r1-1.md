# Digest — dimension 3: integration reality (round 1, researcher 3)
Accessed 2026-09-07. 7 searches, ~8 distinct source clusters.

## F1 (decision-critical): @bam.tech/react-native-image-resizer stale + RN 0.84+ pod break
- Latest release v3.0.11, Nov 25 2024 — no releases ~21 months. New-Arch supported since 3.0.0 (TurboModule + old-arch fallback, RN >= 0.61), BUT podspec declares RCT-Folly/React-Codegen, conflicting with RN 0.84.x prebuilt core (RCT_USE_PREBUILT_RNCORE); pod install fails. Issue #437 (Mar 2026, 9 thumbs) unmerged; workarounds: patch-package skipping RCT-Folly, install_modules_dependencies(s), or RCT_USE_PREBUILT_RNCORE='0'. {github issue #437 + npm listing; confidence: high; class: version-compat}
- New Arch RN 0.83+: NSException in iOS async completionBlock escapes to TurboModule, convertNSExceptionToJSError from wrong thread → EXC_BAD_ACCESS crash. Fix PR #439 closed wontfix by stale bot, never merged. {github PR #439; confidence: high; class: implementation-reality}

## F2: OOM on huge photos — longest-running weakness, "recurring, partially patched, no systemic fix"
- Android OOM in ImageResizer.loadBitmap since 2017 (issue #97, fixed #103); iOS "Terminated due to memory issue" since 2020 (issue #143, PR #205); #283 (2021 graceful-OOM) closed wontfix — the suggested OOM error code never landed. Fragmentation (not free RAM) is the cause; at least one team moved resizing to the server. Currency verdict: stale because deprioritized, not fixed. {github issues #97/#143/#283; confidence: high; class: implementation-reality}

## F3: react-native-compressor — actively maintained; crash record current-version mostly fixed; HEIC photo input NOT documented
- ImageCompressor.swift crash from paths not starting file:// fixed v1.8.14 (PR #227), recurred, further fix PR #334. iPhone 16 Pro HEVC video bug fixed v1.10.1+ (PR #321, itself caused build errors for some). 4K HEVC audio-only MP4 fixed (issue #400). Open NSRangeException on audio-only (issue #363, Aug 2025). Severity mostly in the VIDEO path. {github issues #221/#313/#363/#400; confidence: high; class: implementation-reality}
- npm docs list only JPEG/PNG for image quality — HEIC not documented as supported input; pre-conversion needed (react-native-simple-heic2jpg, or Nitro-based react-native-simple-image-compressor which claims HEIC/HEIF direct, or react-native-image-compression-kit). {npm react-native-compressor, github Drzaln/react-native-simple-heic2jpg; confidence: medium; class: version-compat}

## F4 (decision-critical): image-picker's own options already downscale — EXIF the catch
- quality (0–1) defaults 0.8 on both platforms, applies only with a compression option set (e.g. JPEG on iOS); 1 disables iOS compression. maxWidth/maxHeight are aspect-preserving BOUNDS, not exact targets. Picker alone can produce a compliant JPEG with zero extra native modules. {image-picker options docs + SO 40274875; confidence: high; class: pattern}
- Catch: iOS resize path (UIImageJPEGRepresentation) destroys ALL EXIF; issue #2235 reports strip-even-when-no-resize regression (confirmed iOS 18.3+). Android 10+ downscaled images lose or keep STALE EXIF (stale width/height + wrong orientation flag) → 90/180° rotation bugs and Glide IllegalStateException crashes. {github #2235/#1413/#920 + medium sprocket-fy; confidence: high; class: implementation-reality}
- Implication: if EXIF (GPS/timestamp) need not survive, picker-only is viable and dependency-free; if deterministic max-edge sizing or EXIF preservation matters, a dedicated resizer wins.

## F5: Bun + native autolinking — works; friction is the isolated linker, not libraries
- Bun isolated mode (default in workspaces) breaks Metro transitive resolution and hoisting-assuming podspecs (pod install rb_sysopen). Fix: linker = "hoisted" in bunfig.toml + reinstall. Bun skips postinstall by default → trustedDependencies entries needed for native-CLI packages. No image-library-specific Bun incompatibility found anywhere. {oven-sh bun#25870, RN firebase#8956, expo docs; confidence: high; class: version-compat}

## F6: Presigned-URL guidance prescribes client-side processing by pattern
- Supabase presigned uploads carry no compression; guidance: client-side resize+quality before upload, allowedMimeTypes on bucket (signed URL = anyone holding it can PUT), verify content server-side (content-type client-controlled). EXIF stripped during compression → rotation; fix = re-attach EXIF or preserve orientation. {supabase docs via search summary; confidence: medium; class: pattern}
- Amplify: no built-in resize (open FR since Feb 2023); AWS suggests client-side or Lambda trigger. Amplify uploads of manipulator output can arrive corrupted in S3 unless fetch(uri)→blob. {amplify-js#10930, SO 49341597; confidence: high; class: pattern}

## F7: Nitro/JSI fast but immature
- react-native-nitro-image 10–80x faster, 100% Swift/Kotlin, but: load() only http(s):// (local file paths unsupported, issues #1/#21), crashes on large files (#16), iOS build failures (#17), quality regressions at blur 0. Nitro HybridObject memory leaks (partial fix 0.27), high API churn. react-native-simple-image-compressor (Nitro) claims HEIC input + EXIF + OOM-safe downsampling but no production track record. {nitro-image issues + margelo/nitro discussion 627; confidence: medium; class: implementation-reality}
- Tradeoff: bamlab = boring/proven but frozen + pod issue; Nitro = fast/HEIC-capable but early-stage, local-file blocker disqualifying until verified fixed.

## Not found
1. Quantified production crash rates (percent-of-sessions) for either library.
2. Android Photo Picker interplay with a resizer as a distinct thread.
3. Bun + image-resizer podspec specifically (only generic isolated-mode failures).
4. compressor's image-path HEIC handling as an actual user report (npm docs listing only).

## Round-2 leads (contradictions first)
1. NitroImage local-file support contradiction: issues #1/#21 say http-only vs sample's loadFromFileAsync — possibly two different libraries conflated. Resolve before ranking Nitro.
2. Was PR #439 (TurboModule NSException) merged after all? Repo had activity through 2026.
3. Issue #437 workaround status on RN 0.86 specifically (search covered 0.84.x only).
4. image-picker #2235 — was the always-strip-EXIF regression fixed in a later picker release?
5. Supabase Storage docs fetched directly for presigned-upload + allowedMimeTypes flow.
