"""Generates the game's surface textures (all procedural, all original).

    python3 tools/make_textures.py

Writes tileable PNGs to assets/textures/.
"""
import os
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "textures")
os.makedirs(OUT, exist_ok=True)
rng = np.random.default_rng(7)


def tile_noise(n, scale, octaves=4, seed=0):
    """Tileable value noise in 0..1 built from wrapped low-res grids."""
    r = np.random.default_rng(seed)
    out = np.zeros((n, n))
    amp, total = 1.0, 0.0
    for o in range(octaves):
        cells = max(2, int(scale * 2 ** o))
        g = r.random((cells, cells))
        img = Image.fromarray((g * 255).astype(np.uint8))
        # wrap by tiling 3x3, resizing, cropping the middle: seamless edges
        big = Image.new("L", (cells * 3, cells * 3))
        for i in range(3):
            for j in range(3):
                big.paste(img, (i * cells, j * cells))
        big = big.resize((n * 3, n * 3), Image.BICUBIC)
        layer = np.asarray(big.crop((n, n, 2 * n, 2 * n)), dtype=float) / 255.0
        out += layer * amp
        total += amp
        amp *= 0.5
    return out / total


def save(name, arr, mode=None):
    arr = np.clip(arr, 0, 255).astype(np.uint8)
    Image.fromarray(arr, mode).save(os.path.join(OUT, name))
    print("wrote", name, arr.shape)


def normal_from_height(h, strength):
    dx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * strength
    dy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * strength
    nz = np.ones_like(h)
    l = np.sqrt(dx * dx + dy * dy + nz * nz)
    return np.stack([(-dx / l) * 0.5 + 0.5, (dy / l) * 0.5 + 0.5, nz / l * 0.5 + 0.5], -1) * 255


# ------------------------------------------------------------------ asphalt
def concrete():
    n = 512
    v = tile_noise(n, 6, 5, 21) * 0.5 + tile_noise(n, 80, 2, 22) * 0.3
    stains = tile_noise(n, 3, 3, 23)
    lum = 0.55 + (v - 0.4) * 0.25 - np.clip(stains - 0.55, 0, 1) * 0.5
    # vertical rain streaks
    streak = tile_noise(n, 30, 2, 24)
    streak = np.repeat(streak[:1, :], n, 0) * np.linspace(0.6, 1.0, n)[:, None]
    lum -= np.clip(streak - 0.55, 0, 1) * 0.35
    # form-work seams
    lum[::128, :] -= 0.18
    lum[:, ::256] -= 0.15
    col = np.stack([lum, lum * 0.99, lum * 0.96], -1) * 255
    save("concrete.png", col)


# ------------------------------------------------------------------ building facade
def facade():
    """2 storeys x 2 bays of siding with aluminium-frame windows. Alpha = lit window."""
    n = 512
    img = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    sid = tile_noise(n, 10, 3, 31)
    base = np.zeros((n, n, 4))
    lum = 0.78 + (sid - 0.5) * 0.08
    lum = lum - (np.arange(n)[:, None] % 16 < 1) * 0.06          # siding boards
    base[..., 0] = lum * 0.96
    base[..., 1] = lum * 0.93
    base[..., 2] = lum * 0.86
    base[..., 3] = 0
    arr = (base * 255).astype(np.uint8)
    img = Image.fromarray(arr, "RGBA")
    d = ImageDraw.Draw(img)
    lit_choices = [True, False, True, False]
    k = 0
    for row in (0, 1):
        for col in (0, 1):
            x0 = col * 256 + 54
            y0 = row * 256 + 70
            w, h = 148, 110
            lit = lit_choices[k]
            k += 1
            d.rectangle([x0 - 6, y0 - 6, x0 + w + 6, y0 + h + 6], fill=(150, 150, 152, 0))       # frame
            glass = (255, 196, 120, 255) if lit else (30, 38, 50, 0)
            d.rectangle([x0, y0, x0 + w, y0 + h], fill=glass)
            d.line([x0 + w // 2, y0, x0 + w // 2, y0 + h], fill=(120, 120, 124, 0), width=5)  # sliding sash
            if lit:
                # shoji / curtain pattern inside the lit window
                for gx in range(x0 + 10, x0 + w, 24):
                    d.line([gx, y0, gx, y0 + h], fill=(220, 150, 80, 255), width=2)
            d.rectangle([x0 - 10, y0 + h + 6, x0 + w + 10, y0 + h + 14], fill=(110, 110, 112, 0))  # sill
    # floor band between storeys
    d.rectangle([0, 248, n, 262], fill=(140, 136, 128, 0))
    img.save(os.path.join(OUT, "facade.png"))
    print("wrote facade.png")


def canopy():
    """Forest canopy seen from a distance: packed tree crowns, lit from the
    upper left, dark gaps between them. Greyscale, tileable."""
    n = 512
    img = np.full((n, n), 0.18)
    yy, xx = np.mgrid[0:n, 0:n]
    for _ in range(900):
        cx, cy = rng.integers(0, n, 2)
        r = rng.integers(9, 22)
        for ox in (-n, 0, n):
            for oy in (-n, 0, n):
                x0, y0 = cx + ox, cy + oy
                if x0 + r < 0 or x0 - r > n or y0 + r < 0 or y0 - r > n:
                    continue
                sl = (slice(max(0, y0 - r), min(n, y0 + r)), slice(max(0, x0 - r), min(n, x0 + r)))
                dx = (xx[sl] - x0) / r
                dy = (yy[sl] - y0) / r
                d = dx * dx + dy * dy
                inside = d < 1.0
                shade = 0.55 + 0.45 * np.clip(-(dx + dy) * 0.7 + 0.3, -1, 1) - d * 0.25
                top = np.where(inside, shade, -1)
                img[sl] = np.maximum(img[sl], top)
    img = np.clip(img, 0, 1) * (0.8 + 0.2 * tile_noise(n, 30, 2, 51))
    save("canopy.png", img * 255, "L")


def _font(size):
    from PIL import ImageFont
    return ImageFont.truetype(JP, size)


def bus_stop_sign():
    """Round bus-stop plate: white face, blue ring, a simple bus pictogram and
    the words "bus stop". Original design; transparent outside the disc."""
    n = 256
    img = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.ellipse([4, 4, n - 5, n - 5], fill=(30, 70, 160, 255))
    d.ellipse([18, 18, n - 19, n - 19], fill=(245, 245, 240, 255))
    # bus: body, windows, wheels
    d.rounded_rectangle([60, 70, 196, 140], radius=12, fill=(30, 70, 160, 255))
    for k in range(4):
        x = 72 + k * 30
        d.rectangle([x, 80, x + 22, 102], fill=(245, 245, 240, 255))
    d.ellipse([78, 128, 102, 152], fill=(20, 20, 25, 255))
    d.ellipse([154, 128, 178, 152], fill=(20, 20, 25, 255))
    f = _font(40)
    d.text((n / 2, 186), "バス停", fill=(30, 70, 160, 255), font=f, anchor="mm")
    img.save(os.path.join(OUT, "bus_stop_sign.png"))
    print("wrote bus_stop_sign.png")


def shelter_panel():
    """Back panel of a mountain bus shelter: a timetable board on the left and
    a faded local poster on the right. Original design."""
    w, h = 512, 384
    img = Image.new("RGB", (w, h), (196, 198, 194))
    d = ImageDraw.Draw(img)
    # timetable board
    d.rectangle([20, 24, 232, 360], fill=(250, 250, 246), outline=(60, 60, 70), width=4)
    d.rectangle([20, 24, 232, 70], fill=(30, 70, 160))
    d.text((126, 47), "時刻表", fill=(255, 255, 255), font=_font(30), anchor="mm")
    f = _font(18)
    times = ["6", "7", "8", "9", "11", "13", "15", "17", "18", "20"]
    for k, hr in enumerate(times):
        y = 84 + k * 27
        d.text((34, y), hr, fill=(30, 30, 40), font=f)
        mins = ["05", "32"] if k % 3 else ["15"]
        d.text((84, y), "  ".join(mins), fill=(40, 40, 50), font=f)
        d.line([28, y + 24, 224, y + 24], fill=(200, 200, 205), width=1)
    # poster: hot-spring town at dusk (original)
    d.rectangle([260, 24, 492, 360], fill=(242, 236, 222), outline=(90, 80, 70), width=3)
    for y in range(40, 230):
        t = (y - 40) / 190
        col = (int(250 - 60 * t), int(170 - 40 * t), int(110 + 30 * t))
        d.line([272, y, 480, y], fill=col)
    d.polygon([(272, 230), (330, 150), (380, 200), (430, 130), (480, 210), (480, 230)], fill=(70, 60, 90))
    for k in range(3):
        x = 300 + k * 50
        d.arc([x, 170, x + 30, 210], 200, 340, fill=(255, 255, 255), width=3)    # steam
    d.text((376, 270), "温泉の町", fill=(120, 40, 30), font=_font(36), anchor="mm")
    d.text((376, 318), "山を下りて ひと休み", fill=(80, 60, 50), font=_font(18), anchor="mm")
    # weathering
    arr = np.asarray(img, dtype=float)
    arr *= (0.88 + 0.12 * tile_noise(512, 8, 3, 71)[:h, :w, None])
    save("shelter_panel.png", arr)


def chevron():
    """Corner arrow board: yellow face, black border, two black arrows
    pointing right (mirrored in game for left-hand corners)."""
    w, h = 160, 200
    img = Image.new("RGB", (w, h), (250, 205, 20))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, w - 1, h - 1], outline=(15, 15, 15), width=10)
    for x0 in (30, 78):
        d.polygon([(x0, 40), (x0 + 24, 40), (x0 + 58, 100), (x0 + 24, 160), (x0, 160), (x0 + 34, 100)], fill=(15, 15, 15))
    img.save(os.path.join(OUT, "chevron.png"))
    print("wrote chevron.png")


if __name__ == "__main__":
    concrete()
    facade()
    canopy()
    bus_stop_sign()
    shelter_panel()
    chevron()
