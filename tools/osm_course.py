"""Build a course from the REAL road: OpenStreetMap geometry + public DEM.

  python3 tools/osm_course.py haruna

Uses tools/osm/<route>.json (lat/lon path of the road, from OSM) and
Terrarium elevation tiles (AWS open data) for the mountain around it.
Writes tracks/<id>.json + tracks/<id>_terrain.bin like trace_course.py.
"""
import json, math, os, sys, io, urllib.request
import numpy as np
from PIL import Image
from scipy.spatial import cKDTree
from scipy.ndimage import gaussian_filter, map_coordinates

HERE = os.path.dirname(os.path.abspath(__file__))
STEP = 2.0
RAIL = 3.7 + 0.55 + 0.45
Z = 14

COURSES = {
    "haruna": {
        "osm": "osm/route33.json",
        "features": "osm/haruna_full.json",
        # metres along the OSM chain: downhill from the pass by Lake Haruna to Ikaho
        "from_s": 10330.0, "to_s": 2650.0,
        "lake": {"lat": (36.468, 36.482), "lon": (138.862, 138.885), "level_from_dem": True},
        "towns": [  # name, lat, lon, radius m, lights
            ("Ikaho", 36.4977, 138.9190, 600, 900),
            ("Shibukawa", 36.4893, 139.0003, 2200, 4200),
            ("Maebashi", 36.3911, 139.0608, 4500, 7000),
            ("Takasaki", 36.3219, 139.0033, 4000, 5000),
        ],
    },
}

_tiles = {}


def tile(tx, ty):
    if (tx, ty) not in _tiles:
        cache = os.path.join(HERE, "osm", f"dem_{Z}_{tx}_{ty}.npy")
        if os.path.exists(cache):
            _tiles[(tx, ty)] = np.load(cache)
        else:
            u = f"https://elevation-tiles-prod.s3.amazonaws.com/terrarium/{Z}/{tx}/{ty}.png"
            im = np.asarray(Image.open(io.BytesIO(urllib.request.urlopen(u, timeout=60).read())).convert("RGB")).astype(np.float64)
            a = im[:, :, 0] * 256 + im[:, :, 1] + im[:, :, 2] / 256 - 32768
            np.save(cache, a)
            _tiles[(tx, ty)] = a
    return _tiles[(tx, ty)]


def latlon_to_tile(lat, lon):
    n = 2 ** Z
    x = (lon + 180) / 360 * n
    y = (1 - math.log(math.tan(math.radians(lat)) + 1 / math.cos(math.radians(lat))) / math.pi) / 2 * n
    return x, y


def dem(lat, lon):
    x, y = latlon_to_tile(lat, lon)
    tx, ty = int(x), int(y)
    px, py = (x - tx) * 256 - 0.5, (y - ty) * 256 - 0.5
    # bilinear across tile borders
    i0, j0 = math.floor(py), math.floor(px)
    a, b = py - i0, px - j0
    def at(i, j):
        ttx, tty = tx, ty
        if j < 0: ttx -= 1; j += 256
        if j > 255: ttx += 1; j -= 256
        if i < 0: tty -= 1; i += 256
        if i > 255: tty += 1; i -= 256
        return tile(ttx, tty)[i, j]
    return (at(i0, j0) * (1 - a) * (1 - b) + at(i0, j0 + 1) * (1 - a) * b +
            at(i0 + 1, j0) * a * (1 - b) + at(i0 + 1, j0 + 1) * a * b)


def resample(poly, step):
    out = [poly[0]]
    acc = 0.0
    for a, b in zip(poly, poly[1:]):
        seg = math.dist(a, b)
        while acc + seg >= step:
            t = (step - acc) / seg
            a = (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)
            out.append(a)
            seg = math.dist(a, b)
            acc = 0.0
        acc += seg
    return out


def catmull(pts, per_seg=6):
    out = []
    n = len(pts)
    for i in range(n - 1):
        p0 = pts[max(i - 1, 0)]; p1 = pts[i]; p2 = pts[i + 1]; p3 = pts[min(i + 2, n - 1)]
        for k in range(per_seg):
            t = k / per_seg; t2 = t * t; t3 = t2 * t
            out.append(tuple(0.5 * ((2 * p1[j]) + (-p0[j] + p2[j]) * t + (2 * p0[j] - 5 * p1[j] + 4 * p2[j] - p3[j]) * t2 +
                                    (-p0[j] + 3 * p1[j] - 3 * p2[j] + p3[j]) * t3) for j in range(2)))
    out.append(pts[-1])
    return out


def limit_radius(pts, rmin):
    """Round off corners tighter than rmin by local smoothing (keeps the shape)."""
    P = np.array(pts)
    for it in range(400):
        h = np.arctan2(np.diff(P[:, 1]), np.diff(P[:, 0]))
        dh = (np.diff(h) + np.pi) % (2 * np.pi) - np.pi
        k = np.zeros(len(P))
        k[1:-1] = np.abs(dh) / STEP
        k = np.convolve(k, np.ones(3) / 3, mode="same")
        hot = np.where(k > 1.0 / rmin)[0]
        if len(hot) == 0:
            break
        mask = np.zeros(len(P), bool)
        for i in hot:
            mask[max(i - 3, 2):min(i + 4, len(P) - 2)] = True
        Q = P.copy()
        Q[mask] = (P[np.roll(np.arange(len(P)), 2)][mask] + P[np.roll(np.arange(len(P)), 1)][mask] * 2 + P[mask] * 2 +
                   P[np.roll(np.arange(len(P)), -1)][mask] * 2 + P[np.roll(np.arange(len(P)), -2)][mask]) / 8
        P = Q
        if it % 20 == 19:
            P = np.array(resample([tuple(p) for p in P], STEP))
    print(f"radius limit: {it + 1} passes")
    return [tuple(p) for p in resample([tuple(p) for p in P], STEP)]


def main(cid):
    c = COURSES[cid]
    src = json.load(open(os.path.join(HERE, c["osm"])))
    ll = src["path"]
    # cumulative distance along the OSM chain
    s = [0.0]
    for a, b in zip(ll, ll[1:]):
        s.append(s[-1] + math.hypot((b[0] - a[0]) * 111320, (b[1] - a[1]) * 111320 * math.cos(math.radians(a[0]))))
    lo, hi = sorted((c["from_s"], c["to_s"]))
    idx = [i for i in range(len(ll)) if lo <= s[i] <= hi]
    if c["from_s"] > c["to_s"]:
        idx = idx[::-1]
    sel = [ll[i] for i in idx]
    lat0, lon0 = sel[0]
    kx = 111320 * math.cos(math.radians(lat0))
    ky = 111320.0

    def to_local(lat, lon):
        return ((lon - lon0) * kx, -(lat - lat0) * ky)   # x east, z south

    def to_ll(x, z):
        return (lat0 - z / ky, lon0 + x / kx)

    xy = [to_local(*p) for p in sel]
    pts = resample(catmull(xy), STEP)
    for _ in range(4):
        pts = [pts[0]] + [((a[0] + 2 * b[0] + q[0]) / 4, (a[1] + 2 * b[1] + q[1]) / 4) for a, b, q in zip(pts, pts[1:], pts[2:])] + [pts[-1]]
    pts = resample(pts, STEP)
    pts = limit_radius(pts, 9.0)
    # real heights along the road; roads are smoother than the 10 m DEM and
    # the course is downhill only, so smooth and make it non-increasing
    ys = np.array([dem(*to_ll(x, z)) for x, z in pts])
    ys = gaussian_filter(ys, 12)
    for i in range(1, len(ys)):
        ys[i] = min(ys[i], ys[i - 1] - 0.0005 * STEP)
    ys = gaussian_filter(ys, 4)
    for i in range(1, len(ys)):
        ys[i] = min(ys[i], ys[i - 1])
    top = ys[0]
    # lead-in / tail, flat-ish
    (x0, z0), (x1, z1) = pts[0], pts[1]
    h0 = math.atan2(z1 - z0, x1 - x0)
    lead = [(x0 - math.cos(h0) * STEP * k, z0 - math.sin(h0) * STEP * k) for k in range(15, 0, -1)]
    (xa, za), (xb, zb) = pts[-2], pts[-1]
    h1 = math.atan2(zb - za, xb - xa)
    tail = [(xb + math.cos(h1) * STEP * k, zb + math.sin(h1) * STEP * k) for k in range(1, 21)]
    allp = lead + pts + tail
    ally = [ys[0] + 0.02 * STEP * (15 - k) for k in range(15)] + list(ys) + [ys[-1] - 0.02 * STEP * (k + 1) for k in range(20)]
    xyz = [(x, y - top, z) for (x, z), y in zip(allp, ally)]
    # stats
    hd = [math.atan2(b[2] - a[2], b[0] - a[0]) for a, b in zip(xyz, xyz[1:])]
    k = []
    for i in range(1, len(hd)):
        d = (hd[i] - hd[i - 1] + math.pi) % (2 * math.pi) - math.pi
        k.append(d / STEP)
    hp = 0; i = 0; win = 40
    while i < len(k) - win:
        if abs(sum(k[i:i + win]) * STEP) > math.radians(140):
            hp += 1; i += win
        else:
            i += 1
    tight = min(1 / max(abs(v), 1e-6) for v in gaussian_filter(np.array(k), 1.0))
    print(f"{cid}: {len(xyz) * STEP:.0f} m, drop {xyz[0][1] - xyz[-1][1]:.0f} m, top {top:.0f} m asl, hairpins {hp}, tightest R {tight:.1f} m")
    XZ = np.array([[p[0], p[2]] for p in xyz])
    tr = cKDTree(XZ)
    pairs = tr.query_pairs(2 * RAIL + 1.0)
    bad = sum(1 for a, b in pairs if abs(a - b) > 40 and abs(xyz[a][1] - xyz[b][1]) < 6.0)
    print(f"overlap pairs {bad}")
    terrain, trees, lake = build_terrain(cid, xyz, top, to_ll, to_local, c)
    far = build_far_terrain(cid, xyz, top, to_ll)
    feats, rails = export_features(c, xyz, to_local, terrain)
    towns = []
    for name, la, lo_, rad, cnt in c["towns"]:
        x, z = to_local(la, lo_)
        towns.append({"name": name, "x": round(x, 1), "z": round(z, 1), "y": round(dem(la, lo_) - top, 1), "r": rad, "n": cnt})
    out = {"id": cid, "step": STEP, "points": [[round(v, 3) for v in p] for p in xyz], "hairpins": hp,
           "terrain": terrain, "far_terrain": far, "features": feats, "rails": rails, "trees": trees, "lake": lake, "towns": towns,
           "geo": {"lat0": lat0, "lon0": lon0, "top_asl": round(float(top), 1), "source": "OpenStreetMap Route 33 + Terrarium DEM"}}
    json.dump(out, open(os.path.join(HERE, "..", "tracks", cid + ".json"), "w"), separators=(",", ":"))


def export_features(c, xyz, to_local, terrain):
    """Real roadside features from OpenStreetMap, in course coordinates, plus
    per-sample guardrail flags: mapped guard rails, and the valley (fill) side
    wherever the real ground falls away (that's where Japanese roads put them)."""
    d = json.load(open(os.path.join(HERE, c["features"])))
    N, W, PN = d["nodes"], d["ways"], d["pnodes"]
    P = np.array(xyz)
    XZ = P[:, [0, 2]]
    tree = cKDTree(XZ)
    n = len(P)
    hd = np.arctan2(np.gradient(P[:, 2]), np.gradient(P[:, 0]))
    D = np.c_[np.cos(hd), np.sin(hd)]
    R = np.c_[-D[:, 1], D[:, 0]]     # right of travel in (x, z)
    def loc(nid):
        la, lo = N[nid]
        return to_local(la, lo)
    def side_of(q):
        dd, i = tree.query(q)
        v = np.array(q) - XZ[i]
        return dd, i, (1 if v @ R[i] > 0 else -1)
    rail = np.zeros((2, n), dtype=np.int8)   # [left, right]
    feats = {"buildings": [], "parking": [], "points": [], "bridges": []}
    for w in W.values():
        t = w["tags"]
        pts = [loc(x) for x in w["nodes"] if x in N]
        if len(pts) < 2:
            continue
        near = min(tree.query(p)[0] for p in pts)
        if t.get("barrier") == "guard_rail" and near < 15:
            for a, b in zip(pts, pts[1:]):
                for f in np.linspace(0, 1, 10):
                    q = (a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f)
                    dd, i, sd = side_of(q)
                    if dd < 15:
                        rail[0 if sd < 0 else 1, max(i - 2, 0):i + 3] = 1
        elif "building" in t and near < 450:
            h = float(t.get("height", "0").split()[0] or 0) if t.get("height", "").replace(".", "").split(" ")[0].isdigit() else 0.0
            lv = int(t.get("building:levels", "0")) if t.get("building:levels", "").isdigit() else 0
            feats["buildings"].append({"poly": [[round(x, 1), round(z, 1)] for x, z in pts],
                                       "h": h if h > 0 else (lv * 3.2 if lv else 6.5), "kind": t["building"]})
        elif t.get("amenity") == "parking" and near < 120:
            feats["parking"].append([[round(x, 1), round(z, 1)] for x, z in pts])
        elif t.get("bridge") and t.get("ref") == "33":
            ss = sorted(tree.query(p)[1] for p in pts)
            feats["bridges"].append([int(ss[0]), int(ss[-1])])
    for nid, t in PN.items():
        if nid not in N:
            continue
        q = loc(nid)
        dd, i, sd = side_of(q)
        if dd > 60:
            continue
        kind = t.get("highway") or t.get("amenity") or t.get("tourism") or t.get("barrier")
        if kind in ("bus_stop", "toilets", "viewpoint", "parking", "street_lamp", "crossing"):
            feats["points"].append({"kind": kind, "x": round(q[0], 1), "z": round(q[1], 1), "i": int(i), "side": sd,
                                    "name": t.get("name", "")})
    # valley side guardrails from the real ground
    nx, nz, cell = terrain["nx"], terrain["nz"], terrain["cell"]
    ox, oz = terrain["origin"]
    hgrid = np.fromfile(os.path.join(HERE, "..", "tracks", terrain["file"]), dtype="<f4").reshape(nz, nx)
    def ground(x, z):
        j = int(np.clip((x - ox) / cell, 0, nx - 1)); i = int(np.clip((z - oz) / cell, 0, nz - 1))
        return hgrid[i, j]
    for k in range(n):
        for si, sd in ((0, -1), (1, 1)):
            q = XZ[k] + R[k] * sd * (RAIL + 9.0)
            drop = P[k, 1] - ground(*q)
            if drop > 2.5:
                rail[si, k] = 1
    # close small gaps, drop tiny bits
    for si in range(2):
        r = rail[si]
        for k in range(1, n - 6):
            if r[k - 1] and not r[k] and r[k:k + 6].any():
                r[k] = 1
    feats["counts"] = {kk: len(v) for kk, v in feats.items() if isinstance(v, list)}
    print("features", feats["counts"], "rail cover L/R %", round(rail[0].mean() * 100), round(rail[1].mean() * 100))
    rails = ["".join(str(int(v)) for v in rail[0]), "".join(str(int(v)) for v in rail[1])]
    return feats, rails


def dem_grid(lat, lon):
    n = 2 ** Z
    tx = (lon + 180) / 360 * n
    ty = (1 - np.log(np.tan(np.radians(lat)) + 1 / np.cos(np.radians(lat))) / np.pi) / 2 * n
    tx0, tx1 = int(tx.min()) - 1, int(tx.max()) + 1
    ty0, ty1 = int(ty.min()) - 1, int(ty.max()) + 1
    mosaic = np.zeros(((ty1 - ty0 + 1) * 256, (tx1 - tx0 + 1) * 256))
    for a in range(ty0, ty1 + 1):
        for b in range(tx0, tx1 + 1):
            mosaic[(a - ty0) * 256:(a - ty0 + 1) * 256, (b - tx0) * 256:(b - tx0 + 1) * 256] = tile(b, a)
    return map_coordinates(mosaic, [(ty - ty0) * 256 - 0.5, (tx - tx0) * 256 - 0.5], order=1)


def build_far_terrain(cid, xyz, top, to_ll, half=8000.0, cell=40.0):
    """Real mountains and valleys all around, coarse, for the horizon."""
    P = np.array(xyz)
    cx, cz = P[:, 0].mean(), P[:, 2].mean()
    nx = nz = int(2 * half / cell) + 1
    gx, gz = np.meshgrid(cx - half + np.arange(nx) * cell, cz - half + np.arange(nz) * cell)
    lat0, lon0 = to_ll(0, 0)
    kx = 111320 * math.cos(math.radians(lat0))
    h = dem_grid(lat0 - gz / 111320.0, lon0 + gx / kx) - top - 3.0
    fname = f"{cid}_far.bin"
    h.astype("<f4").tofile(os.path.join(HERE, "..", "tracks", fname))
    print(f"far terrain {nx}x{nz} @ {cell} m")
    return {"file": fname, "origin": [float(cx - half), float(cz - half)], "cell": cell, "nx": nx, "nz": nz}


def build_terrain(cid, xyz, top, to_ll, to_local, c, cell=5.0, margin=260.0):
    P = np.array(xyz)
    xz = P[:, [0, 2]]
    mn = xz.min(0) - margin
    mx = xz.max(0) + margin
    nx = int((mx[0] - mn[0]) / cell) + 1
    nz = int((mx[1] - mn[1]) / cell) + 1
    gx, gz = np.meshgrid(mn[0] + np.arange(nx) * cell, mn[1] + np.arange(nz) * cell)
    # real ground heights
    lat = (to_ll(0, 0)[0]) - gz / 111320.0
    lon0 = to_ll(0, 0)[1]
    kx = 111320 * math.cos(math.radians(to_ll(0, 0)[0]))
    lon = lon0 + gx / kx
    # vectorised DEM sampling via tile mosaic
    n = 2 ** Z
    tx = (lon + 180) / 360 * n
    ty = (1 - np.log(np.tan(np.radians(lat)) + 1 / np.cos(np.radians(lat))) / np.pi) / 2 * n
    tx0, tx1 = int(tx.min()) - 1, int(tx.max()) + 1
    ty0, ty1 = int(ty.min()) - 1, int(ty.max()) + 1
    mosaic = np.zeros(((ty1 - ty0 + 1) * 256, (tx1 - tx0 + 1) * 256))
    for a in range(ty0, ty1 + 1):
        for b in range(tx0, tx1 + 1):
            mosaic[(a - ty0) * 256:(a - ty0 + 1) * 256, (b - tx0) * 256:(b - tx0 + 1) * 256] = tile(b, a)
    real = map_coordinates(mosaic, [(ty - ty0) * 256 - 0.5, (tx - tx0) * 256 - 0.5], order=1) - top
    real = gaussian_filter(real, 0.8)
    q = np.stack([gx.ravel(), gz.ravel()], 1)
    tree = cKDTree(xz)
    d, idx = tree.query(q)
    hr = P[idx, 1]
    natural = real.ravel()
    # cut into the hillside steeply (walls / rock-fall protection go there),
    # fill the valley side with a gentler embankment
    width = np.where(natural > hr + 0.5, 6.0, 18.0)
    t = np.clip((d - (RAIL + 1.0)) / width, 0.0, 1.0)
    t = t * t * (3 - 2 * t)
    h = ((hr - 0.6) * (1 - t) + natural * t).reshape(nz, nx)
    dd = d.reshape(nz, nx)
    h[dd < RAIL + 1.0] = (hr - 0.6).reshape(nz, nx)[dd < RAIL + 1.0]
    fname = f"{cid}_terrain.bin"
    h.astype("<f4").tofile(os.path.join(HERE, "..", "tracks", fname))
    # lake surface
    lake = None
    if c.get("lake"):
        L = c["lake"]
        (la0, la1), (lo0, lo1) = L["lat"], L["lon"]
        x0, z1 = to_local(la0, lo0)
        x1, z0 = to_local(la1, lo1)
        level = min(dem(la, lo) for la in np.linspace(la0 + 0.003, la1 - 0.003, 4) for lo in np.linspace(lo0 + 0.004, lo1 - 0.004, 4))
        lake = {"x0": round(x0, 1), "x1": round(x1, 1), "z0": round(z0, 1), "z1": round(z1, 1), "y": round(level - top + 0.3, 2)}
    # trees: forest on gentle slopes, keep downhill views open
    rng = np.random.default_rng(abs(hash(cid)) % 2 ** 32)
    trees = []
    cand = rng.uniform(0, 1, (int(nx * nz * 0.5), 2)) * [mx[0] - mn[0], mx[1] - mn[1]] + mn
    dc, ic = tree.query(cand)
    for (x, z), ddd, ni in zip(cand, dc, ic):
        if ddd < RAIL + 3.0 or ddd > 200.0:
            continue
        if rng.uniform() > (1.0 if ddd < 70 else 0.35):
            continue
        fx = (x - mn[0]) / cell; fz = (z - mn[1]) / cell
        i0, j0 = int(fz), int(fx)
        if i0 >= nz - 1 or j0 >= nx - 1:
            continue
        a, b = fz - i0, fx - j0
        y = (h[i0, j0] * (1 - a) * (1 - b) + h[i0, j0 + 1] * (1 - a) * b + h[i0 + 1, j0] * a * (1 - b) + h[i0 + 1, j0 + 1] * a * b)
        if lake and lake["x0"] < x < lake["x1"] and lake["z0"] < z < lake["z1"] and y < lake["y"] + 1.0:
            continue
        slope = abs(h[i0, j0 + 1] - h[i0, j0]) / cell + abs(h[i0 + 1, j0] - h[i0, j0]) / cell
        if slope > 1.4:
            continue
        sc = float(rng.uniform(0.75, 1.35))
        road_y = P[ni, 1]
        if y < road_y - 1.0 and y + 13.0 * sc > road_y - 1.5 and ddd < 120.0 and rng.uniform() > 0.12:
            continue
        trees += [round(float(x), 1), round(float(y), 2), round(float(z), 1), round(sc, 2)]
    print(f"terrain {nx}x{nz}, {len(trees) // 4} trees, lake {lake}")
    return {"file": fname, "origin": [float(mn[0]), float(mn[1])], "cell": cell, "nx": nx, "nz": nz}, trees, lake


if __name__ == "__main__":
    main(sys.argv[1])
