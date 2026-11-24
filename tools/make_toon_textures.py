"""Painted versions of the surface scans for the cartoon look: broad flat
patches of colour with soft brush edges instead of photographic grain.

    python3 tools/make_toon_textures.py
"""
import os
from PIL import Image, ImageFilter, ImageEnhance, ImageChops

SRC, OUT = "assets/pbr", "assets/toon"
os.makedirs(OUT, exist_ok=True)
#           colours  saturation  keep joints (darken along the scan's creases)
SPEC = {"asphalt": (5, 0.7, False), "concrete": (6, 0.8, True), "masonry": (8, 0.9, True), "grass": (7, 1.25, False),
        "bark": (6, 1.1, True), "metal": (4, 0.6, False), "roof": (6, 1.1, True), "rock": (8, 0.9, True), "forest": (7, 1.1, False)}
for name, (colours, sat, joints) in SPEC.items():
    path = "%s/%s_diff.jpg" % (SRC, name)
    if not os.path.exists(path):
        continue
    im = Image.open(path).convert("RGB").resize((512, 512), Image.LANCZOS)
    flat = im
    for _ in range(3):
        flat = flat.filter(ImageFilter.MedianFilter(9))
    flat = flat.quantize(colours, dither=Image.Dither.NONE).convert("RGB").filter(ImageFilter.GaussianBlur(0.7))
    flat = ImageEnhance.Color(flat).enhance(sat)
    if joints:
        ao_path = "%s/%s_ao.jpg" % (SRC, name)
        src = Image.open(ao_path).convert("L").resize((512, 512), Image.LANCZOS) if os.path.exists(ao_path) else im.convert("L")
        dark = src.filter(ImageFilter.MedianFilter(5)).point(lambda v: 255 if v > 105 else 70).filter(ImageFilter.GaussianBlur(0.8))
        flat = ImageChops.multiply(flat, Image.merge("RGB", (dark, dark, dark)))
    flat.save("%s/%s.png" % (OUT, name))
    print("painted", name)
