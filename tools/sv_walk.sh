#!/bin/bash
# Street View reference walk along a built course (reference only, git-ignored).
#   tools/sv_walk.sh <course_id> [spacing_m]
cd "$(dirname "$0")/.."
ID=$1; SP=${2:-250}
OUT=reference/real_$ID/walk; mkdir -p "$OUT"
python3 - "$ID" "$SP" "$OUT" <<'PY'
import json, math, sys
cid, sp, out = sys.argv[1], float(sys.argv[2]), sys.argv[3]
d = json.load(open(f"tracks/{cid}.json"))
lat0, lon0 = d["geo"]["lat0"], d["geo"]["lon0"]
kx = 111320 * math.cos(math.radians(lat0))
P = d["points"]
s = [0.0]
for a, b in zip(P, P[1:]): s.append(s[-1] + math.hypot(b[0] - a[0], b[2] - a[2]))
lines = []
t = 30.0; k = 0
while t < s[-1] - 40:
    i = min(range(len(s)), key=lambda q: abs(s[q] - t))
    j = min(i + 3, len(P) - 1)
    x, z = P[i][0], P[i][2]
    hdg = (math.degrees(math.atan2(P[j][0] - x, -(P[j][2] - z))) + 360) % 360
    lines.append(f"{k:02d} {int(t)} {lat0 - z / 111320:.7f} {lon0 + x / kx:.7f} {hdg:.0f}")
    t += sp; k += 1
open(f"{out}/points.txt", "w").write("\n".join(lines) + "\n")
print(len(lines), "stops")
PY
while read k s la lo h; do
  [ -f "$OUT/sv_${k}_s${s}.png" ] && continue
  timeout 90 xvfb-run -a -s "-screen 0 1280x720x24" node tools/sv_capture.js "$la" "$lo" "$h" "$PWD/$OUT/sv_${k}_s${s}.png" > /dev/null 2>&1
  echo "done $k"
done < "$OUT/points.txt"
echo ALLDONE
