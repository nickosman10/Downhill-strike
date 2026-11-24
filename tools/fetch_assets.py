"""Downloads the CC0 scanned materials and sky the game uses from Poly Haven.

    python3 tools/fetch_assets.py

Everything here is CC0 (public domain): https://polyhaven.com/license
"""
import json, os, urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "pbr")
os.makedirs(OUT, exist_ok=True)
UA = {"User-Agent": "asset-fetch/1.0"}

# game name -> Poly Haven id
MATERIALS = {
    "asphalt": "asphalt_04",
    "masonry": "japanese_stone_wall",
    "concrete": "concrete_wall_008",
    "rock": "rock_face_03",
    "forest": "forest_floor",
    "grass": "leafy_grass",
    "bark": "japanese_cedar_bark",
    "roof": "grey_roof_tiles_02",
    "plaster": "grey_plaster_02",
    "metal": "metal_plate",
}
SKY = "rogland_clear_night"
RES = "2k"


def get(url):
    return urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=120).read()


def files(asset):
    return json.loads(get("https://api.polyhaven.com/files/" + asset))


for name, pid in MATERIALS.items():
    f = files(pid)
    for kind, key in (("diff", "Diffuse"), ("nor", "nor_gl"), ("rough", "Rough"), ("ao", "AO")):
        dst = os.path.join(OUT, f"{name}_{kind}.jpg")
        if os.path.exists(dst) or key not in f:
            continue
        url = f[key][RES]["jpg"]["url"]
        open(dst, "wb").write(get(url))
        print("got", os.path.basename(dst), os.path.getsize(dst) // 1024, "KB")

dst = os.path.join(OUT, "night_sky.hdr")
if not os.path.exists(dst):
    f = files(SKY)
    open(dst, "wb").write(get(f["hdri"]["4k"]["hdr"]["url"]))
    print("got night_sky.hdr", os.path.getsize(dst) // 1024, "KB")
