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
def asphalt():
    n = 1024
    base = tile_noise(n, 3, 5, 1)
    fine = tile_noise(n, 64, 2, 2)
    # aggregate: scattered light and dark stones of a few pixels
    agg = np.zeros((n, n))
    for count, val, rmax in ((26000, 0.55, 2), (18000, -0.45, 2), (2500, 0.8, 3)):
        ys = rng.integers(0, n, count)
        xs = rng.integers(0, n, count)
        rs = rng.integers(1, rmax + 1, count)
        for y, x, r in zip(ys, xs, rs):
            agg[max(0, y - r):y + r, max(0, x - r):x + r] += val * rng.random()
    agg = np.clip(agg, -0.6, 0.9)
    h = base * 0.4 + fine * 0.35 + agg * 0.2
    # cracks and tar seams (dark, slightly raised sealant lines)
    crack = Image.new("L", (n, n), 0)
    d = ImageDraw.Draw(crack)
    for _ in range(14):
        x, y = rng.integers(0, n, 2)
        pts = [(int(x), int(y))]
        ang = rng.random() * np.pi * 2
        for _ in range(rng.integers(8, 30)):
            ang += rng.normal(0, 0.5)
            x = (x + np.cos(ang) * 14) % n
            y = (y + np.sin(ang) * 14) % n
            pts.append((int(x), int(y)))
        for a, b in zip(pts, pts[1:]):
            if abs(a[0] - b[0]) < 40 and abs(a[1] - b[1]) < 40:
                d.line([a, b], fill=255, width=int(rng.integers(2, 5)))
    crack = np.asarray(crack.filter(ImageFilter.GaussianBlur(1.2)), dtype=float) / 255.0
    # patched repair squares
    patch = np.zeros((n, n))
    for _ in range(3):
        x, y = rng.integers(0, n - 220, 2)
        w, hgt = rng.integers(120, 220, 2)
        patch[y:y + hgt, x:x + w] = 1.0
    patch = np.asarray(Image.fromarray((patch * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(3)), dtype=float) / 255.0
    lum = 0.30 + (h - 0.4) * 0.26 - crack * 0.14 - patch * 0.04
    col = np.stack([lum * 1.0, lum * 1.0, lum * 1.04], -1) * 255
    save("asphalt_albedo.png", col)
    save("asphalt_normal.png", normal_from_height(h - crack * 0.4, 6.0))
    # roughness: polished wheel tracks are a bit smoother; tar seams glossy
    rough = 0.82 - crack * 0.35 - patch * 0.05 + (fine - 0.5) * 0.1
    save("asphalt_rough.png", rough * 255, "L")


# ------------------------------------------------------------------ ground / rock detail
def ground():
    n = 512
    a = tile_noise(n, 8, 5, 11)
    b = tile_noise(n, 40, 3, 12)
    blades = np.zeros((n, n))
    for _ in range(9000):
        x, y = rng.integers(0, n, 2)
        l = rng.integers(3, 9)
        blades[max(0, y - l):y, x] += rng.random()
    v = np.clip(a * 0.55 + b * 0.3 + np.clip(blades, 0, 1) * 0.25, 0, 1)
    col = np.stack([0.20 + v * 0.18, 0.28 + v * 0.30, 0.12 + v * 0.10], -1) * 255
    save("ground_detail.png", col)
    r = tile_noise(n, 6, 6, 13)
    strata = 0.5 + 0.5 * np.sin(np.linspace(0, 18 * np.pi, n))[:, None] * (0.4 + 0.6 * tile_noise(n, 4, 2, 14))
    v = np.clip(r * 0.6 + strata * 0.25 + tile_noise(n, 60, 2, 15) * 0.25, 0, 1)
    col = np.stack([0.33 + v * 0.3, 0.32 + v * 0.29, 0.30 + v * 0.27], -1) * 255
    save("rock_detail.png", col)


# ------------------------------------------------------------------ concrete
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


def roof():
    n = 256
    v = tile_noise(n, 8, 3, 41)
    rows = (np.arange(n)[:, None] % 32) / 32.0
    lum = 0.22 + v * 0.06 - (rows < 0.12) * 0.07 + (rows > 0.85) * 0.03
    cols = (np.arange(n)[None, :] % 32) < 2
    lum = lum - cols * 0.04
    col = np.stack([lum * 0.85, lum * 0.92, lum * 1.05], -1) * 255     # blue-grey kawara tiles
    save("roof_tiles.png", col)


# ------------------------------------------------------------------ foliage cards
def leaves():
    """Broadleaf canopy card: clusters of leaves, alpha-cut, lighter on top."""
    n = 512
    img = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cx, cy = n / 2, n / 2
    for _ in range(2600):
        # leaves fill a rough ellipse, denser in the middle
        a = rng.random() * np.pi * 2
        r = np.sqrt(rng.random()) * 0.47 * n
        x = cx + np.cos(a) * r
        y = cy + np.sin(a) * r * 0.85
        if rng.random() < (r / (0.47 * n)) ** 3 * 0.6:
            continue
        top = 1.0 - (y / n)
        g = 0.35 + top * 0.45 + rng.random() * 0.2
        col = (int(40 * g + 10), int(110 * g + 20), int(45 * g + 10), 255)
        s = rng.integers(5, 12)
        ang = rng.random() * np.pi
        dx, dy = np.cos(ang) * s, np.sin(ang) * s * 0.5
        d.polygon([(x - dx, y - dy), (x - dy * 0.6, y + dx * 0.6), (x + dx, y + dy), (x + dy * 0.6, y - dx * 0.6)], fill=col)
    # a few branches showing through
    for _ in range(6):
        a = rng.random() * np.pi * 2
        d.line([(cx, n * 0.95), (cx + np.cos(a) * n * 0.3, cy + np.sin(a) * n * 0.25)], fill=(45, 32, 22, 255), width=4)
    img.save(os.path.join(OUT, "leaves.png"))
    print("wrote leaves.png")


def cedar():
    """Japanese cedar (sugi) card: narrow layered cone of needle sprays."""
    w, h = 256, 512
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rectangle([w // 2 - 5, int(h * 0.7), w // 2 + 5, h], fill=(60, 40, 28, 255))
    for k in range(34):
        t = k / 33.0
        y = h * 0.04 + t * h * 0.78
        half = (0.06 + t * 0.4) * w
        for _ in range(int(40 + t * 60)):
            x = w / 2 + (rng.random() * 2 - 1) * half
            yy = y + rng.random() * 18 - 4
            g = 0.45 + (1 - t) * 0.3 + rng.random() * 0.2
            col = (int(28 * g + 8), int(80 * g + 18), int(48 * g + 12), 255)
            d.line([(x, yy), (x + (rng.random() - 0.5) * 10, yy + 6)], fill=col, width=3)
    img.save(os.path.join(OUT, "cedar.png"))
    print("wrote cedar.png")


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


if __name__ == "__main__":
    asphalt()
    ground()
    concrete()
    facade()
    roof()
    leaves()
    cedar()
    canopy()
