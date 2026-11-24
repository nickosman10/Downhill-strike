"""Prepares textures for the scanned trees (Poly Haven, CC0) from a tree package.

    python3 tools/ph_tree_textures.py <package>/textures assets/trees/ph

Leaf and twig atlases become RGBA PNGs (colour + cut-out); bark and trunk
sets become 1k JPEGs.
"""
import sys, os
from PIL import Image

src, out = sys.argv[1:3]
NAMES = {
    "fir_tree_01_bark": "fir_bark", "fir_tree_01_trunk_a": "fir_trunk_a", "fir_tree_01_trunk_b": "fir_trunk_b",
    "fir_tree_01_trunk_c": "fir_trunk_c", "fir_tree_01_twig": "fir_twig",
    "jacaranda_tree_trunk": "jac_trunk", "jacaranda_tree_branches": "jac_branches", "jacaranda_tree_leaves": "jac_leaves",
}
for long, short in NAMES.items():
    f = lambda kind: os.path.join(src, "%s_%s_2k.png" % (long, kind))
    if not os.path.exists(f("diff")):
        continue
    if os.path.exists(f("alpha")):
        rgb = Image.open(f("diff")).convert("RGB")
        a = Image.open(f("alpha")).convert("L")
        rgb.putalpha(a)
        rgb.save(os.path.join(out, short + ".png"))
        Image.open(f("nor_gl")).convert("RGB").save(os.path.join(out, short + "_nor.jpg"), quality=90)
    else:
        for kind, name in (("diff", "diff"), ("nor_gl", "nor"), ("rough", "rough")):
            Image.open(f(kind)).convert("RGB").resize((1024, 1024), Image.LANCZOS).save(os.path.join(out, "%s_%s.jpg" % (short, name)), quality=90)
    print("textures", short)
