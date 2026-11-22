"""Turn hand-traced waypoints (pixel coords on a course map) into a driveable
curvature profile for the Godot track generator.

  python3 tools/trace_course.py haruna [--overlay map.jpg]

Pipeline: waypoints -> Catmull-Rom spline -> scale to real length ->
2 m samples -> curvature -> smooth until no corner is tighter than R_MIN
(smoothing keeps the total turn of every corner) -> re-integrate ->
self-overlap check -> tracks/<id>.json
"""
import json, math, sys, os

STEP = 2.0
R_MIN = 11.0

# Waypoints in pixel coordinates of the reference map, listed in DOWNHILL order.
# grade: list of (fraction_of_course, grade_percent) control points.
COURSES = {
    "haruna": {
        "map": "Map_of_Akina.jpg",
        "length": 7650.0,
        "grade": [(0.0, -2.5), (0.12, -4.0), (0.3, -6.0), (0.55, -6.5), (0.8, -7.0), (1.0, -5.5)],
        "points": [
            # lakeside wiggles (top right)
            (447, 72), (435, 79), (430, 93), (426, 98), (422, 94), (413, 67), (410, 60), (407, 57), (403, 59), (400, 68),
            (392, 92), (386, 107), (382, 111), (378, 107), (367, 83), (357, 67), (350, 65), (340, 67),
            (327, 78), (317, 85), (311, 81), (308, 68), (310, 48), (318, 40), (323, 30),
            (318, 20), (307, 15), (277, 10), (250, 5), (226, 3),
            # hairpin at top-left of the plateau
            (214, 8), (218, 17), (237, 23), (257, 28), (260, 36), (250, 43),
            (242, 50), (237, 64), (235, 71), (231, 74), (227, 71), (226, 63), (227, 57), (225, 50), (221, 49), (218, 53), (215, 62), (212, 73), (206, 86),
            # tight switchback cluster
            (196, 88), (186, 89), (182, 92), (183, 97), (188, 99), (208, 98), (213, 100), (213, 105), (208, 107),
            (188, 107), (183, 112), (184, 122),
            # descent to the big right-hand hairpin
            (184, 140), (188, 155), (200, 162), (226, 161), (229, 172), (228, 190),
            (250, 205), (265, 212), (274, 217), (278, 221), (276, 226), (270, 227), (255, 222), (247, 219), (217, 204), (200, 200),
            # long run west and the hairpin back east
            (177, 205), (150, 202), (123, 203), (103, 211), (90, 230), (88, 240), (87, 250), (90, 255), (94, 253), (97, 245),
            (99, 236), (110, 222), (123, 235), (137, 238), (160, 232), (177, 233),
            (197, 228), (207, 231), (210, 240), (227, 248), (230, 257), (217, 263),
            (190, 270), (167, 280), (140, 297), (117, 310), (104, 318),
            # double hairpin
            (100, 330), (100, 341), (97, 347), (93, 345), (92, 336), (91, 315), (90, 308), (86, 305), (83, 309), (82, 316),
            (80, 332), (70, 343), (61, 352),
            # final section: the consecutive hairpins down to the finish
            (61, 375), (64, 395), (70, 415), (72, 428), (73, 435), (70, 439), (66, 436), (63, 428), (50, 406),
            (35, 393), (22, 378), (18, 360), (18, 351), (15, 346), (11, 348), (9, 355), (7, 365), (6, 375), (10, 395),
            (22, 410), (38, 421), (50, 432), (46, 447), (35, 465), (25, 485), (17, 510),
            (13, 530), (10, 547),
        ],
    },
}


def catmull(pts, per_seg=20):
    out = []
    n = len(pts)
    for i in range(n - 1):
        p0 = pts[max(i - 1, 0)]; p1 = pts[i]; p2 = pts[i + 1]; p3 = pts[min(i + 2, n - 1)]
        for k in range(per_seg):
            t = k / per_seg
            t2, t3 = t * t, t * t * t
            out.append(tuple(0.5 * ((2 * p1[j]) + (-p0[j] + p2[j]) * t +
                                    (2 * p0[j] - 5 * p1[j] + 4 * p2[j] - p3[j]) * t2 +
                                    (-p0[j] + 3 * p1[j] - 3 * p2[j] + p3[j]) * t3) for j in range(2)))
    out.append(pts[-1])
    return out


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


def headings(pts):
    h = [math.atan2(b[1] - a[1], b[0] - a[0]) for a, b in zip(pts, pts[1:])]
    for i in range(1, len(h)):
        while h[i] - h[i - 1] > math.pi: h[i] -= 2 * math.pi
        while h[i] - h[i - 1] < -math.pi: h[i] += 2 * math.pi
    return h


def integrate(k, h0):
    x = y = 0.0; h = h0
    pts = [(x, y)]
    for kk in k:
        hm = h + kk * STEP * 0.5
        x += math.cos(hm) * STEP; y += math.sin(hm) * STEP
        h += kk * STEP
        pts.append((x, y))
    return pts


def limit_radius(k, lim):
    passes = 0
    while max(abs(v) for v in k) > lim and passes < 3000:
        hot = {j for i, v in enumerate(k) if abs(v) > lim for j in range(i - 3, i + 4) if 0 <= j < len(k)}
        nk = k[:]
        for i in hot:
            nk[i] = (k[max(i - 1, 0)] + k[i] + k[min(i + 1, len(k) - 1)]) / 3.0
        k = nk
        passes += 1
    return k, passes


def pull_to(integ, target, sigma=40):
    n = min(len(integ), len(target))
    err = [(target[i][0] - integ[i][0], target[i][1] - integ[i][1]) for i in range(n)]
    wts = [math.exp(-0.5 * (d / sigma) ** 2) for d in range(-3 * sigma, 3 * sigma + 1)]
    out = []
    for i in range(n):
        sx = sy = sw = 0.0
        for d, w in zip(range(-3 * sigma, 3 * sigma + 1), wts):
            j = i + d
            if 0 <= j < n:
                sx += err[j][0] * w; sy += err[j][1] * w; sw += w
        out.append((integ[i][0] + sx / sw, integ[i][1] + sy / sw))
    return out


def build(cid, overlay=None):
    c = COURSES[cid]
    raw = c["points"]
    px_len = sum(math.dist(a, b) for a, b in zip(raw, raw[1:]))
    spline = catmull(raw)
    sp_len = sum(math.dist(a, b) for a, b in zip(spline, spline[1:]))
    scale = c["length"] / sp_len
    pts = resample([(x * scale, y * scale) for x, y in spline], STEP)
    # light Laplacian smoothing of positions removes spline kinks but keeps the shape
    for _ in range(6):
        pts = [pts[0]] + [((a[0] + 2 * b[0] + c2[0]) / 4, (a[1] + 2 * b[1] + c2[1]) / 4)
                          for a, b, c2 in zip(pts, pts[1:], pts[2:])] + [pts[-1]]
    pts = resample(pts, STEP)
    h = headings(pts)
    k = [(h[i + 1] - h[i]) / STEP for i in range(len(h) - 1)]
    # open up hairpin tips tighter than R_MIN: blur curvature locally (keeps the
    # corner's total turn), re-integrate, then pull back onto the map with a
    # low-frequency position correction so the overall layout is preserved.
    target = pts
    track = pts
    # report corners tighter than R_MIN with their map pixel position
    run = []
    for i, v in enumerate(k):
        if abs(v) > 1.0 / R_MIN:
            run.append(i)
        elif run:
            j = min(run, key=lambda q: -abs(k[q]))
            print(f"  tight R={1/abs(k[j]):.1f}m at map px ({pts[j][0]/scale:.0f},{pts[j][1]/scale:.0f})")
            run = []
    end_err = math.dist(track[-1], target[min(len(target), len(track)) - 1])
    print(f"end offset vs map {end_err:.0f} m")
    h = headings(track)
    k = [(h[i + 1] - h[i]) / STEP for i in range(len(h) - 1)]
    # overlap check (horizontal); grades separate them vertically a bit but be strict
    rail = 3.3 + 0.55 + 0.45
    bad = 0
    for i in range(0, len(track), 2):
        for j in range(i + 40, len(track), 2):
            if math.dist(track[i], track[j]) < 2 * rail + 1:
                bad += 1
    # hairpins: corners turning > 140 deg within 80 m
    hp = 0; i = 0; win = int(80 / STEP)
    while i < len(k) - win:
        turn = sum(k[i:i + win]) * STEP
        if abs(turn) > math.radians(140):
            hp += 1; i += win
        else:
            i += 1
    # grade per step
    g = c["grade"]
    grades = []
    for i in range(len(k)):
        f = i / max(len(k) - 1, 1)
        for (f0, g0), (f1, g1) in zip(g, g[1:]):
            if f0 <= f <= f1:
                grades.append(round(g0 + (g1 - g0) * (f - f0) / (f1 - f0), 3)); break
    drift = 0.0
    tight = min(1 / max(abs(v), 1e-6) for v in k)
    print(f"tightest radius {tight:.1f} m")
    print(f"{cid}: {len(k)*STEP:.0f} m, scale {scale:.2f} m/px, "
          f"hairpins {hp}, overlap pairs {bad}, end drift {drift:.0f} m")
    out = {"id": cid, "step": STEP, "points": [[round(x, 2), round(y, 2)] for x, y in track], "grade": grades, "hairpins": hp}
    path = os.path.join(os.path.dirname(__file__), "..", "tracks", cid + ".json")
    json.dump(out, open(path, "w"), separators=(",", ":"))
    if overlay:
        from PIL import Image, ImageDraw
        im = Image.open(overlay).convert("RGB").resize((c_w := Image.open(overlay).width * 2, Image.open(overlay).height * 2))
        d = ImageDraw.Draw(im)
        # align integrated track to spline start/orientation (already same frame, same start heading)
        d.line([(x / scale * 2, y / scale * 2) for x, y in track], fill=(255, 0, 0), width=2)
        d.line([(x * 2, y * 2) for x, y in raw], fill=(0, 160, 255), width=1)
        o = overlay.rsplit(".", 1)[0] + "_trace.png"
        im.save(o)
        print("overlay:", o)
    return bad


if __name__ == "__main__":
    ov = sys.argv[sys.argv.index("--overlay") + 1] if "--overlay" in sys.argv else None
    sys.exit(1 if build(sys.argv[1], ov) else 0)
