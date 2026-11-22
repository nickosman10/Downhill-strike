"""Find the real road a course map shows.

  python3 tools/find_route.py <id> <lat0> <lat1> <lon0> <lon1> <wiki_map.jpg> [min_km max_km]

1. downloads OpenStreetMap data for the box (cached in tools/osm/<id>_full.json)
2. chains every named/numbered road into its longest path
3. slides windows of several lengths along each road, fits them (north up,
   uniform scale) onto the black line of the course map, and scores the fit
   with a two-way chamfer distance
4. writes tools/osm/<id>_route.json (lat/lon path of the best window, ordered
   downhill later by osm_course.py) and an overlay image for checking
"""
import json, math, os, sys, time, collections, heapq, urllib.request
import xml.etree.ElementTree as ET
import numpy as np
from PIL import Image, ImageDraw
from scipy.ndimage import distance_transform_edt

HERE = os.path.dirname(os.path.abspath(__file__))
UA = {"User-Agent": "DownhillStrike-trace/1.0"}


def fetch(cid, la0, la1, lo0, lo1, step=0.02):
    path = os.path.join(HERE, "osm", f"{cid}_full.json")
    if os.path.exists(path):
        return json.load(open(path))
    nodes, ways, pnodes = {}, {}, {}
    la = la0
    while la < la1 - 1e-9:
        lo = lo0
        while lo < lo1 - 1e-9:
            url = f"https://api.openstreetmap.org/api/0.6/map?bbox={lo:.4f},{la:.4f},{min(lo + step, lo1):.4f},{min(la + step, la1):.4f}"
            data = None
            for attempt in range(4):
                try:
                    data = urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=120).read()
                    break
                except Exception as e:
                    print("retry", str(e)[:60]); time.sleep(5)
            if data:
                root = ET.fromstring(data)
                for n in root.findall("node"):
                    nodes[n.get("id")] = (float(n.get("lat")), float(n.get("lon")))
                    tags = {t.get("k"): t.get("v") for t in n.findall("tag")}
                    if tags:
                        pnodes[n.get("id")] = tags
                for w in root.findall("way"):
                    tags = {t.get("k"): t.get("v") for t in w.findall("tag")}
                    if tags:
                        ways[w.get("id")] = {"tags": tags, "nodes": [nd.get("ref") for nd in w.findall("nd")]}
            lo += step
            time.sleep(1)
        la += step
    d = {"nodes": nodes, "ways": ways, "pnodes": pnodes}
    json.dump(d, open(path, "w"))
    return d


def chains(d):
    N, W = d["nodes"], d["ways"]
    groups = collections.defaultdict(list)
    for w in W.values():
        t = w["tags"]
        if t.get("highway") not in ("motorway", "trunk", "primary", "secondary", "tertiary", "unclassified", "residential"):
            continue
        key = t.get("ref") or t.get("name")
        if key:
            groups[key].append(w)
    out = []
    for key, ws in groups.items():
        adj = collections.defaultdict(set)
        for w in ws:
            ns = [n for n in w["nodes"] if n in N]
            for a, b in zip(ns, ns[1:]):
                adj[a].add(b); adj[b].add(a)
        if len(adj) < 20:
            continue
        def dist(a, b):
            (la1, lo1), (la2, lo2) = N[a], N[b]
            return math.hypot((la2 - la1) * 111320, (lo2 - lo1) * 111320 * math.cos(math.radians(la1)))
        def dijk(s):
            D = {s: 0.0}; P = {s: None}; pq = [(0.0, s)]
            while pq:
                dd, u = heapq.heappop(pq)
                if dd > D[u]:
                    continue
                for v in adj[u]:
                    nd = dd + dist(u, v)
                    if nd < D.get(v, 1e18):
                        D[v] = nd; P[v] = u; heapq.heappush(pq, (nd, v))
            return D, P
        ends = [n for n in adj if len(adj[n]) == 1] or list(adj)[:1]
        best = (0.0, None)
        for e in ends[:40]:
            D, P = dijk(e)
            far = max(D, key=D.get)
            if D[far] > best[0]:
                path = [far]
                while P[path[-1]] is not None:
                    path.append(P[path[-1]])
                best = (D[far], path)
        if best[0] > 1500:
            pts = [N[n] for n in best[1]]
            out.append((key, best[0], pts))
    return out


def wiki_line(img_path):
    im = np.asarray(Image.open(img_path).convert("L")).astype(np.float32)
    line = im < 110
    ys, xs = np.nonzero(line)
    return line, (xs.min(), xs.max(), ys.min(), ys.max())


def resample_ll(pts, step):
    xy = np.array([(p[1] * 111320 * math.cos(math.radians(pts[0][0])), -p[0] * 111320) for p in pts])
    seg = np.hypot(*np.diff(xy, axis=0).T)
    s = np.r_[0, np.cumsum(seg)]
    ss = np.arange(0, s[-1], step)
    return np.c_[np.interp(ss, s, xy[:, 0]), np.interp(ss, s, xy[:, 1])], ss, s


def match(cands, img_path, min_km, max_km, angles=(0,)):
    line, (x0, x1, y0, y1) = wiki_line(img_path)
    dt = distance_transform_edt(~line)
    lys, lxs = np.nonzero(line)
    pick = np.random.default_rng(0).choice(len(lxs), min(3000, len(lxs)), replace=False)
    lp = np.c_[lxs[pick], lys[pick]].astype(np.float64)
    bw, bh = x1 - x0, y1 - y0
    best = (1e18, None)
    for key, L, pts in cands:
      xy0, ss, _ = resample_ll(pts, 20.0)
      for ang in angles:
        ca, sa = math.cos(math.radians(ang)), math.sin(math.radians(ang))
        xy = xy0 @ np.array([[ca, -sa], [sa, ca]])
        for length in np.arange(min_km * 1000, min(max_km * 1000, ss[-1]) + 1, 250.0):
            n = int(length / 20.0)
            for a in range(0, len(xy) - n, 5):
                seg = xy[a:a + n]
                mn, mx = seg.min(0), seg.max(0)
                sw, sh = mx - mn
                if sw < 1 or sh < 1:
                    continue
                aspect = abs(math.log((sw / sh) / (bw / bh)))
                if aspect > 0.35:
                    continue
                sc = min(bw / sw, bh / sh)
                q = (seg - mn) * sc + [x0 + (bw - sw * sc) / 2, y0 + (bh - sh * sc) / 2]
                qi = np.clip(np.round(q).astype(int), 0, [dt.shape[1] - 1, dt.shape[0] - 1])
                d1 = dt[qi[:, 1], qi[:, 0]].mean()
                # line -> segment (coarse): nearest of 200 segment points
                sub = q[:: max(1, len(q) // 200)]
                d2 = np.sqrt(((lp[:, None, :] - sub[None, :, :]) ** 2).sum(-1)).min(1).mean()
                score = d1 + d2 + aspect * 20
                if score < best[0]:
                    best = (score, (key, length, a, n, sc, ang))
    return best


def main():
    cid = sys.argv[1]
    la0, la1, lo0, lo1 = map(float, sys.argv[2:6])
    img = sys.argv[6]
    nums = [a for a in sys.argv[7:] if not a.startswith("--")]
    min_km = float(nums[0]) if len(nums) > 0 else 3.0
    max_km = float(nums[1]) if len(nums) > 1 else 9.0
    d = fetch(cid, la0, la1, lo0, lo1)
    cands = chains(d)
    print("candidate roads:", [(k, round(L)) for k, L, _ in sorted(cands, key=lambda c: -c[1])][:15])
    angles = tuple(range(0, 360, 15)) if "--rotate" in sys.argv else (0,)
    score, (key, length, a, n, sc, ang) = match(cands, img, min_km, max_km, angles)
    pts = dict((k, p) for k, _, p in cands)[key]
    xy, ss, s = resample_ll(pts, 20.0)
    s_from, s_to = ss[a], ss[a] + length
    sel = [p for p, si in zip(pts, s) if s_from - 1 <= si <= s_to + 1]
    print(f"best: road {key}, {length:.0f} m from {s_from:.0f} m, map rotated {ang} deg, score {score:.1f}")
    ca, sa = math.cos(math.radians(ang)), math.sin(math.radians(ang))
    xy = xy @ np.array([[ca, -sa], [sa, ca]])
    json.dump({"road": key, "path": sel}, open(os.path.join(HERE, "osm", f"{cid}_route.json"), "w"), ensure_ascii=False)
    # overlay for a visual check
    line, (x0, x1, y0, y1) = wiki_line(img)
    seg = xy[a:a + n]
    mn, mx = seg.min(0), seg.max(0)
    sw, sh = mx - mn
    q = (seg - mn) * sc + [x0 + ((x1 - x0) - sw * sc) / 2, y0 + ((y1 - y0) - sh * sc) / 2]
    ov = Image.open(img).convert("RGB")
    dr = ImageDraw.Draw(ov)
    dr.line([tuple(p) for p in q], fill=(255, 0, 0), width=3)
    ov.save(os.path.join(HERE, "osm", f"{cid}_match.png"))


if __name__ == "__main__":
    main()
