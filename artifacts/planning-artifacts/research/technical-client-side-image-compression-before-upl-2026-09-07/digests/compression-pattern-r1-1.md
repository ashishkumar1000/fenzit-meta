# Digest — dimension 2: industry-standard compression pattern (round 1, researcher 1)
Accessed 2026-09-07. Publisher/pub dates as stated in the assistant's return.

## Q1. Max pixel dimension on upload
- No single industry cap; the cluster is 1200–2048px. Writeups use 2048px (upload pipelines), 1200px (card images), 1600px. Per-use-case choice, not a standard. {dev.to/mursalnasaj02, scalebloom.com, engineered.at; confidence: medium; class: pattern}
- WhatsApp ~1600px longest edge, JPEG q70–80, EXIF stripped; 3–5MB original → ~200–300KB. Full-res only via explicit "HD"/document send. Cap varies by version. {WhatsApp Help Center/Android Authority/WABetaInfo aggregated; confidence: medium; class: landscape}
- Cloudinary: upload originals, resize at DELIVERY with q_auto/f_auto; cap upload dimensions only when you know max display sizes. "2048 at upload" = storage/bandwidth control choice, not doctrine. {cloudinary.com documentation; confidence: high; class: pattern}
- AWS Amplify Storage: no client resize built in; team's own suggested workarounds = client resize or post-upload Lambda. No official AWS 2048 number found. {github.com/aws-amplify/amplify-js/issues/10930, /6081; confidence: high; class: landscape}
- Firebase Storage guidance: NOT FOUND this round.

## Q2. JPEG quality; stepping vs one-shot
- q0.8–0.82 recurring sweet spot; 0.95 roughly doubles size with no visible benefit after downscaling. {dev.to/multigrid; confidence: medium; class: pattern}
- Quality stepping is implemented (jpegoptim --size= bisection, JPEG-Click compressTarget), not proven superior as a default; size→quality not perfectly monotonic. Fixed one-shot q0.8 is the default; step only for a hard byte cap. {github.com/tjko/jpegoptim, github.com/vihanb/JPEG-Click; confidence: medium; class: pattern}
- NOT FOUND: measured head-to-head stepped vs one-shot with attempt counts.

## Q3. HEIC/HEIF and PNG
- iOS does not auto-transcode HEIC on upload; S3 does not transcode. Non-Safari browsers cannot display HEIC. Pattern: detect via ftyp/heic/mif1 magic bytes, transcode to JPEG client-side. {stackoverflow.com/questions/71820862, aws.s3.fm; confidence: high; class: pattern}
- HEIC→JPEG re-encode typically INCREASES size ~1.95x median (1.5–2.9x) even quality-matched; HEIC ~50% more efficient than JPEG. Transcode is for compat, never compression. {cleanor.app benchmark + paper, 2026; confidence: medium (vendor benchmark, single publisher); class: performance}
- PNG screenshots stay PNG (JPEG artifacts destroy text edges). {dev.to/multigrid; confidence: medium; class: pattern}

## Q4. EXIF orientation
- @bam.tech/react-native-image-resizer bakes rotation during resize, preserves EXIF via keepMeta but NOT the orientation tag (rotation already applied). README limitation: "Image EXIF orientation are correctly handled on Android only, but not yet on iOS" (issue #402); iOS rotation limited to 90° multiples; keepMeta JPEG-from-filesystem only, broken with ph:// URIs under new arch. {github.com/bamlab/react-native-image-resizer README + issue #402; confidence: high; class: pattern}

## Q5. Resulting sizes
- 4032×3024 iPhone 3.93MB → 1600×1200 JPEG q82, metadata stripped → ~361KB. Resize is the lever, not quality. {roundcut.app; confidence: medium; class: performance}
- 4032×3024 ~6MB → 1920×1440 only → ~1.8MB → q80 → ~350–480KB (WebP). q80 with NO resize on the original only reaches ~3–4MB. {pictuary.com; confidence: medium; class: performance}
- 2048×1536 @ q80: NOT directly measured; interpolation suggests ~500KB–1MB — estimate, not evidenced.

## Leads for round 2
1. Uber/Instagram/Airbnb/eBay upload-resolution engineering posts (nothing primary surfaced).
2. Firebase Storage official upload-resolution guidance — absent.
3. Stepped-vs-one-shot benchmark with attempt counts — absent.
4. iOS EXIF orientation fix status in current bamlab image-resizer (issue #402 date unknown).
5. Whether expo-image-manipulator / react-native-compressor transcode HEIC or only resize JPEG — unverified.
