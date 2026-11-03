#!/usr/bin/env python3
"""Builds the Play promo video (1920x1080, ~24s) from the screenshot set:
title card (feature graphic) -> Ken Burns over each app screenshot ->
end card. Output: video/fenzit-promo.mp4 (silent — listings play it muted)."""
import glob
import subprocess
import os
from PIL import Image, ImageDraw, ImageFont, ImageFilter

BASE = "/Users/admin/workspace/fenzit-meta/artifacts/play-listing"
VID = f"{BASE}/video"
os.makedirs(VID, exist_ok=True)
W, H = 1920, 1080
FPS = 30

def load_font(size):
    for path in glob.glob("/System/Library/Fonts/SFNS.ttf") + glob.glob("/System/Library/Fonts/Helvetica.ttc"):
        try:
            return ImageFont.truetype(path, size, index=1 if path.endswith(".ttc") else 0)
        except Exception:
            continue
    return ImageFont.load_default()

# ---------- title card: the feature graphic + phone ----------
fg = Image.open(f"{BASE}/graphics/feature-graphic-1024x500.png")
title = Image.new("RGB", (W, H), (22, 53, 118))
td = ImageDraw.Draw(title)
td.rounded_rectangle((0, 0, W, 500), radius=0, fill=None)
title.paste(fg, ((W - 1024) // 2, 0))
tag = load_font(40)
sub = "Run your field team from one simple app."
tw = td.textlength(sub, font=tag)
td.text(((W - tw) // 2, 560), sub, font=tag, fill=(219, 230, 253))
brand = load_font(30)
b = "fenzit.com"
bw = td.textlength(b, font=brand)
td.text(((W - bw) // 2, H - 90), b, font=brand, fill=(140, 170, 235))
title.save(f"{VID}/card-title.png")

# ---------- end card ----------
end = Image.new("RGB", (W, H), (22, 53, 118))
ed = ImageDraw.Draw(end)
ic = Image.open(f"{BASE}/graphics/icon-512.png").resize((260, 260), Image.LANCZOS)
# round the icon corners like a store icon
mask = Image.new("L", (260, 260), 0)
md = ImageDraw.Draw(mask)
md.rounded_rectangle((0, 0, 260, 260), radius=58, fill=255)
end.paste(ic, ((W - 260) // 2, 210), mask)
big = load_font(96)
n = "Fenzit"
nw = ed.textlength(n, font=big)
ed.text(((W - nw) // 2, 540), n, font=big, fill=(255, 255, 255))
line = load_font(38)
s = "Jobs, attendance and leave for field teams"
sw = ed.textlength(s, font=line)
ed.text(((W - sw) // 2, 680), s, font=line, fill=(219, 230, 253))
site = load_font(34)
w2 = ed.textlength("Get started at fenzit.com", font=site)
ed.text(((W - w2) // 2, H - 130), "Get started at fenzit.com", font=site, fill=(140, 170, 235))
end.save(f"{VID}/card-end.png")

# ---------- Ken Burns clips from the screenshots ----------
shots = sorted(glob.glob(f"{BASE}/screenshots/final/*.png"))
print("screenshots:", [os.path.basename(p) for p in shots])
clips = []
SEG = 3.4
card_t = 2.6
# title card (slight zoom in)
subprocess.run(
    ["ffmpeg", "-y", "-loglevel", "error", "-loop", "1", "-t", str(card_t), "-i", f"{VID}/card-title.png",
     "-vf", f"scale=2400:-2,zoompan=z='min(1.0+0.06*on/{card_t*FPS},1.06)':d={int(card_t*FPS)}:x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)',fps={FPS},scale={W}:{H}",
     "-c:v", "libx264", "-pix_fmt", "yuv420p", f"{VID}/c-title.mp4"], check=True)
clips.append(f"{VID}/c-title.mp4")

for i, shot in enumerate(shots[:8]):
    zoom_in = i % 2 == 0
    frames = int(SEG * FPS)
    zexpr = f"min(1.0+0.10*on/{frames},1.10)" if zoom_in else f"max(1.10-0.10*on/{frames},1.0)"
    yexpr = "ih/2-(ih/zoom/2)" if i % 3 == 0 else "ih/2-(ih/zoom/2)+((ih/zoom)*0.02)*sin(on/20)"
    out = f"{VID}/c{i}.mp4"
    subprocess.run(
        ["ffmpeg", "-y", "-loglevel", "error", "-loop", "1", "-t", str(SEG), "-i", shot,
         "-vf", f"scale=2160:-2:flags=lanczos,zoompan=z='{zexpr}':d={frames}:x='iw/2-(iw/zoom/2)':y='{yexpr}',"
                f"scale={W}:{H}:force_original_aspect_ratio=increase,crop={W}:{H},fps={FPS}",
         "-c:v", "libx264", "-pix_fmt", "yuv420p", out], check=True)
    clips.append(out)

subprocess.run(
    ["ffmpeg", "-y", "-loglevel", "error", "-loop", "1", "-t", "3.2", "-i", f"{VID}/card-end.png",
     "-vf", f"scale=2400:-2,zoompan=z='max(1.08-0.08*on/{int(3.2*FPS)},1.0)':d={int(3.2*FPS)}:x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)',fps={FPS},scale={W}:{H}",
     "-c:v", "libx264", "-pix_fmt", "yuv420p", f"{VID}/c-end.mp4"], check=True)
clips.append(f"{VID}/c-end.mp4")

# ---------- concat ----------
with open(f"{VID}/clips.txt", "w") as fh:
    for c in clips:
        fh.write(f"file '{c}'\n")
subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "concat", "-safe", "0",
                "-i", f"{VID}/clips.txt", "-c:v", "libx264", "-pix_fmt", "yuv420p",
                "-movflags", "+faststart", f"{VID}/fenzit-promo.mp4"], check=True)
for c in clips:
    os.remove(c)
print("done ->", f"{VID}/fenzit-promo.mp4")
