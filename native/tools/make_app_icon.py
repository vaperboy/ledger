#!/usr/bin/env python3
"""Draws the placeholder app icon set (Ivory Ledger style: dark ground, champagne serif L).
Run: python3 native/tools/make_app_icon.py   (needs Pillow). Writes AppIcon.png (1024 master), every iPhone/iPad size and Contents.json."""
import json, os
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
SET = os.path.join(HERE, "..", "App", "Ledger", "Assets.xcassets", "AppIcon.appiconset")
GROUND, GOLD = (15, 16, 17), (230, 207, 154)
FONTS = ["/usr/share/fonts/truetype/liberation/LiberationSerif-Bold.ttf", "/usr/share/fonts/truetype/dejavu/DejaVuSerif-Bold.ttf"]
S = 1024
img = Image.new("RGB", (S, S), GROUND)
d = ImageDraw.Draw(img)
font = ImageFont.truetype(next(f for f in FONTS if os.path.exists(f)), 700)
box = d.textbbox((0, 0), "L", font=font)
d.text(((S - (box[2] - box[0])) / 2 - box[0], (S - (box[3] - box[1])) / 2 - box[1] - 10), "L", font=font, fill=GOLD)
d.rectangle([312, 800, 712, 808], fill=GOLD)  # ledger rule under the L
img.save(os.path.join(SET, "AppIcon.png"))

# (idiom, point size, scale)
specs = [("iphone", 20, 2), ("iphone", 20, 3), ("iphone", 29, 2), ("iphone", 29, 3), ("iphone", 40, 2), ("iphone", 40, 3), ("iphone", 60, 2), ("iphone", 60, 3),
         ("ipad", 20, 1), ("ipad", 20, 2), ("ipad", 29, 1), ("ipad", 29, 2), ("ipad", 40, 1), ("ipad", 40, 2), ("ipad", 76, 1), ("ipad", 76, 2), ("ipad", 83.5, 2)]
images = [{"idiom": "universal", "platform": "ios", "size": "1024x1024", "filename": "AppIcon.png"}]
for idiom, pt, sc in specs:
    px = int(round(pt * sc))
    name = f"icon-{idiom}-{pt:g}@{sc}x.png"
    img.resize((px, px), Image.LANCZOS).save(os.path.join(SET, name))
    images.append({"idiom": idiom, "size": f"{pt:g}x{pt:g}", "scale": f"{sc}x", "filename": name})
img.save(os.path.join(SET, "icon-marketing-1024.png"))
images.append({"idiom": "ios-marketing", "size": "1024x1024", "scale": "1x", "filename": "icon-marketing-1024.png"})
with open(os.path.join(SET, "Contents.json"), "w") as f:
    json.dump({"images": images, "info": {"author": "xcode", "version": 1}}, f, indent=2)
