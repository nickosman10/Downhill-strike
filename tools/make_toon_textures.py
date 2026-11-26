"""Makes the game's painted surface textures (assets/toon/*.png).

    python3 tools/make_toon_textures.py

Each one starts from a CC0 scanned material from Poly Haven
(https://polyhaven.com/license), fetched to a temporary folder, and is
reduced to broad flat patches of colour with soft brush edges.
"""
import io, json, os, tempfile, urllib.request
from PIL import Image, ImageFilter, ImageEnhance, ImageChops

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "toon")
UA = {"User-Agent": "asset-fetch/1.0"}
# name: (Poly Haven id, colours, saturation, keep joints: darken along the scan's creases)
SPEC = {
    "asphalt": ("asphalt_04", 5, 0.7, False),
    "concrete": ("concrete_wall_008", 6, 0.8, True),
    "masonry": ("japanese_stone_wall", 8, 0.9, True),
    "grass": ("leafy_grass", 7, 1.25, False),
    "roof": ("grey_roof_tiles_02", 6, 1.1, True),
}


def get(url):
    return urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=120).read()


def scan(pid, key, cache):
    """One 2k map of a Poly Haven material, as an image (None if it has no such map)."""
    path = os.path.join(cache, "%s_%s.jpg" % (pid, key))
    if not os.path.exists(path):
        files = json.loads(get("https://api.polyhaven.com/files/" + pid))
        if key not in files:
            return None
        open(path, "wb").write(get(files[key]["2k"]["jpg"]["url"]))
    return Image.open(path)


os.makedirs(OUT, exist_ok=True)
cache = os.path.join(tempfile.gettempdir(), "downhill_strike_scans")
os.makedirs(cache, exist_ok=True)
for name, (pid, colours, sat, joints) in SPEC.items():
    im = scan(pid, "Diffuse", cache).convert("RGB").resize((512, 512), Image.LANCZOS)
    flat = im
    for _ in range(3):
        flat = flat.filter(ImageFilter.MedianFilter(9))
    flat = flat.quantize(colours, dither=Image.Dither.NONE).convert("RGB").filter(ImageFilter.GaussianBlur(0.7))
    flat = ImageEnhance.Color(flat).enhance(sat)
    if joints:
        ao = scan(pid, "AO", cache)
        src = ao.convert("L").resize((512, 512), Image.LANCZOS) if ao else im.convert("L")
        dark = src.filter(ImageFilter.MedianFilter(5)).point(lambda v: 255 if v > 105 else 70).filter(ImageFilter.GaussianBlur(0.8))
        flat = ImageChops.multiply(flat, Image.merge("RGB", (dark, dark, dark)))
    flat.save(os.path.join(OUT, name + ".png"))
    print("painted", name)
