#!/usr/bin/env python3
"""Builds the Play Store icon (512x512) and feature graphic (1024x500) from
the app's own brand assets (the launcher's gradient F + design-system colors)."""
from PIL import Image, ImageDraw, ImageFont
import glob

APP = "/Users/admin/workspace/fenzit-meta/workspace/core/frontend/fenzit-app"
OUT = "/Users/admin/workspace/fenzit-meta/artifacts/play-listing/graphics"

# The F mark: the launcher foreground — transparent bg, gradient fill.
f = Image.open(f"{APP}/android/app/src/main/res/mipmap-xxxhdpi/ic_launcher_foreground.png").convert("RGBA")
bbox = f.getbbox()
f = f.crop(bbox)
print("F content:", f.size)

# --- Icon 512x512: white bg + F centered, like the launcher icon ---
icon = Image.new("RGB", (512, 512), (255, 255, 255))
target = 340
scale = target / f.height
f_icon = f.resize((round(f.width * scale), target), Image.LANCZOS)
icon.paste(f_icon, ((512 - f_icon.width) // 2, (512 - f_icon.height) // 2), f_icon)
icon.save(f"{OUT}/icon-512.png")
print("icon-512.png written")

# --- Feature graphic 1024x500 ---
g = Image.new("RGB", (1024, 500))
draw = ImageDraw.Draw(g)
for x in range(1024):
    t = x / 1023
    if t < 0.55:
        k = t / 0.55
        c = tuple(round(a + (b - a) * k) for a, b in zip((22, 53, 118), (26, 86, 219)))
    else:
        k = (t - 0.55) / 0.45
        c = tuple(round(a + (b - a) * k) for a, b in zip((26, 86, 219), (6, 149, 111)))
    draw.line([(x, 0), (x, 500)], fill=c)
base = g.convert("RGBA")

# Translucent accents go on their own layer so alpha survives flattening.
overlay = Image.new("RGBA", (1024, 500), (0, 0, 0, 0))
od = ImageDraw.Draw(overlay)
od.ellipse((820, -160, 1180, 200), fill=(255, 255, 255, 16))
od.ellipse((-140, 360, 220, 720), fill=(255, 255, 255, 16))
od.ellipse((690, 330, 760, 400), fill=(33, 212, 224, 45))
# F mark in a translucent rounded card, left side.
od.rounded_rectangle((72, 130, 312, 370), radius=48, fill=(255, 255, 255, 28), outline=(255, 255, 255, 80), width=2)
base = Image.alpha_composite(base, overlay)
f_pos = (82, 140)
f_size = 170
f_scale = f_size / f.height
f_fg = f.resize((round(f.width * f_scale), f_size), Image.LANCZOS)
base.alpha_composite(f_fg, (f_pos[0] + (240 - f_fg.width) // 2, f_pos[1] + (240 - f_size) // 2))
draw = ImageDraw.Draw(base)

def load_font(size):
    for path in glob.glob("/System/Library/Fonts/SFNS.ttf") + glob.glob("/System/Library/Fonts/Helvetica.ttc"):
        try:
            return ImageFont.truetype(path, size, index=1 if path.endswith(".ttc") else 0)
        except Exception:
            continue
    return ImageFont.load_default()

name_font = load_font(96)
tag_font = load_font(34)
chip_font = load_font(24)

draw.text((352, 150), "Fenzit", font=name_font, fill=(255, 255, 255))
draw.text((356, 268), "Jobs, attendance and leave for field teams", font=tag_font, fill=(219, 230, 253))

chips = ["Assign jobs", "Track attendance", "Approve leave"]
x = 356
chip_layer = Image.new("RGBA", (1024, 500), (0, 0, 0, 0))
cd = ImageDraw.Draw(chip_layer)
for label in chips:
    w = draw.textlength(label, font=chip_font)
    pad = 18
    box = (x, 340, x + w + pad * 2, 392)
    cd.rounded_rectangle(box, radius=26, fill=(255, 255, 255, 30), outline=(255, 255, 255, 90), width=2)
    cd.text((x + pad, 351), label, font=chip_font, fill=(255, 255, 255))
    x = box[2] + 16
base = Image.alpha_composite(base, chip_layer)

base.convert("RGB").save(f"{OUT}/feature-graphic-1024x500.png")
print("feature-graphic-1024x500.png written")
