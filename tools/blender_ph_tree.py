"""Game-weight trees from Poly Haven's scanned tree packages (CC0).

    blender -b <package.blend> -P tools/blender_ph_tree.py -- fir <out_dir>
    blender -b <package.blend> -P tools/blender_ph_tree.py -- broadleaf <out_dir>

fir:        exports the package's own artist-made game LODs of whole trees.
broadleaf:  assembles a tree from the package's real trunk/branch skeleton and
            its leaf-cluster cards, placed at the tips of the real fine branches.
Meshes are exported without images; the game assigns materials by name from
textures prepared by tools/ph_tree_textures.py.
"""
import bpy, sys, math, random
from mathutils import Vector, Matrix

mode, out = sys.argv[sys.argv.index("--") + 1:][:2]


def mat_images():
    for m in bpy.data.materials:
        if m.use_nodes:
            imgs = [(n.label or n.name, n.image.filepath) for n in m.node_tree.nodes if n.type == "TEX_IMAGE" and n.image]
            print("[tree] material", m.name, imgs)


def export(objs, name):
    for o in bpy.context.scene.objects:
        o.select_set(False)
    for o in objs:
        o.hide_set(False)
        o.hide_viewport = False
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.export_scene.gltf(filepath=f"{out}/{name}.glb", export_format="GLB", use_selection=True,
                              export_image_format="NONE", export_apply=True, export_tangents=True)
    print("[tree] exported", name, sum(len(p.vertices) - 2 for o in objs for p in o.data.polygons), "tris")


def link_all():
    # objects live in excluded collections: link them into the scene root so they can be exported
    root = bpy.context.scene.collection
    for o in bpy.data.objects:
        if o.name not in root.objects:
            try:
                root.objects.link(o)
            except RuntimeError:
                pass


def thin_cards(obj, mat_name, keep, grow, seed=7):
    """Lighter copy of a tree: drops a share of its twig cards and enlarges the rest."""
    import bmesh
    rnd = random.Random(seed)
    ob = obj.copy()
    ob.data = obj.data.copy()
    bpy.context.scene.collection.objects.link(ob)
    slot = [i for i, sl in enumerate(ob.material_slots) if sl.material and sl.material.name == mat_name][0]
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    faces = [f for f in bm.faces if f.material_index == slot]
    seen = set()
    drop = []
    for f in faces:
        if f.index in seen:
            continue
        stack = [f]
        seen.add(f.index)
        isl = []
        while stack:
            g = stack.pop()
            isl.append(g)
            for e in g.edges:
                for h in e.link_faces:
                    if h.index not in seen and h.material_index == slot:
                        seen.add(h.index)
                        stack.append(h)
        if rnd.random() > keep:
            drop += isl
        else:
            vs = {v for g in isl for v in g.verts}
            c = sum((v.co for v in vs), Vector()) / len(vs)
            for v in vs:
                v.co = c + (v.co - c) * grow
    bmesh.ops.delete(bm, geom=drop, context="FACES")
    bm.to_mesh(ob.data)
    bm.free()
    return ob


def tube(path, radii, sides, verts, faces, uvs):
    """Tapered round limb along a path, with bark UVs running up it."""
    base = len(verts)
    run = 0.0
    for i, p in enumerate(path):
        d = (path[min(i + 1, len(path) - 1)] - path[max(i - 1, 0)]).normalized()
        ref = Vector((1, 0, 0)) if abs(d.x) < 0.9 else Vector((0, 1, 0))
        u = d.cross(ref).normalized()
        w = d.cross(u)
        if i:
            run += (p - path[i - 1]).length
        for j in range(sides + 1):
            a = 2 * math.pi * j / sides
            verts.append(p + (u * math.cos(a) + w * math.sin(a)) * radii[i])
            uvs.append((j / sides, run * 0.5))
    for i in range(len(path) - 1):
        for j in range(sides):
            a = base + i * (sides + 1) + j
            faces.append((a, a + 1, a + sides + 2, a + sides + 1))


def decimated(obj, ratio, keep_mat=None, drop_mats=()):
    """Applies a decimation. keep_mat: leave faces of that material (leaf cards) alone.
    drop_mats: delete faces of those materials outright."""
    import bmesh
    if drop_mats:
        bm = bmesh.new()
        bm.from_mesh(obj.data)
        idx = [i for i, sl in enumerate(obj.material_slots) if sl.material and sl.material.name in drop_mats]
        bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.material_index in idx], context="FACES")
        bm.to_mesh(obj.data)
        bm.free()
    for o in bpy.context.scene.objects:
        o.select_set(False)
    m = obj.modifiers.new("dec", "DECIMATE")
    m.ratio = ratio
    if keep_mat:
        slot = [i for i, sl in enumerate(obj.material_slots) if sl.material and sl.material.name == keep_mat][0]
        vg = obj.vertex_groups.new(name="woody")
        leafy = {v for poly in obj.data.polygons if poly.material_index == slot for v in poly.vertices}
        vg.add([v.index for v in obj.data.vertices if v.index not in leafy], 1.0, "REPLACE")
        m.vertex_group = "woody"
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.convert(target="MESH")
    return obj


def tris(me, slot=None):
    return sum(len(p.vertices) - 2 for p in me.polygons if slot is None or p.material_index == slot)


def lighter(obj, twig_budget, bough_budget, trunk_budget):
    """A lighter fir: thinned twig cards, the longest boughs only, a decimated trunk."""
    import bmesh
    twig = "fir_tree_01_twig"
    slots = {sl.material.name: i for i, sl in enumerate(obj.material_slots) if sl.material}
    keep = twig_budget / tris(obj.data, slots[twig])
    ob = thin_cards(obj, twig, keep, (1.0 / keep) ** 0.42)
    # trunk on its own object so it can be decimated cleanly
    trunk_slot = [i for n, i in slots.items() if "trunk" in n][0]
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    drop = [f for f in bm.faces if f.material_index == slots.get("fir_tree_01_dead_branches", -1)]
    # boughs: keep the longest connected pieces within the budget
    bark = [f for f in bm.faces if f.material_index == slots["fir_tree_01_bark"]]
    seen = set()
    islands = []
    for f in bark:
        if f.index in seen:
            continue
        stack = [f]
        seen.add(f.index)
        isl = []
        while stack:
            g = stack.pop()
            isl.append(g)
            for e in g.edges:
                for h in e.link_faces:
                    if h.index not in seen and h.material_index == f.material_index:
                        seen.add(h.index)
                        stack.append(h)
        cos = [v.co for g in isl for v in g.verts]
        size = (Vector((max(c.x for c in cos), max(c.y for c in cos), max(c.z for c in cos)))
                - Vector((min(c.x for c in cos), min(c.y for c in cos), min(c.z for c in cos)))).length
        islands.append((size, isl))
    islands.sort(key=lambda t: -t[0])
    used = 0
    for size, isl in islands:
        n = sum(len(g.verts) - 2 for g in isl)
        if used + n > bough_budget:
            drop += isl
        else:
            used += n
    trunk_faces = [f for f in bm.faces if f.material_index == trunk_slot]
    bmesh.ops.delete(bm, geom=drop + trunk_faces, context="FACES")
    bm.to_mesh(ob.data)
    bm.free()
    t = obj.copy()
    t.data = obj.data.copy()
    bpy.context.scene.collection.objects.link(t)
    bm = bmesh.new()
    bm.from_mesh(t.data)
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.material_index != trunk_slot], context="FACES")
    bm.to_mesh(t.data)
    bm.free()
    decimated(t, trunk_budget / max(1, tris(t.data)))
    for o in bpy.context.scene.objects:
        o.select_set(False)
    ob.select_set(True)
    t.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.join()
    print("[tree] lighter: boughs", used, "total", tris(ob.data))
    return ob


mat_images()
link_all()
if mode == "fir":
    for src, name in (("fir_tree_01_c_LOD2", "fir_c"), ("fir_tree_01_b_LOD2", "fir_b"), ("fir_tree_01_a_LOD2", "fir_a")):
        o = bpy.data.objects[src]
        o.location = (0, 0, 0)
        export([o], name)
        # lighter versions of the same tree for the middle and far-middle distance:
        # fewer, larger twig cards, only the main boughs, and a simpler trunk
        export([lighter(o, 5500, 2000, 400)], name + "_m")
        export([lighter(o, 1100, 0, 90)], name + "_l")
else:
    random.seed(4)
    args = sys.argv[sys.argv.index("--") + 3:]
    N = int(args[0]) if len(args) > 0 else 200
    k = float(args[1]) if len(args) > 1 else 0.5
    name = args[2] if len(args) > 2 else "broadleaf_a"
    limb_ratio = float(args[3]) if len(args) > 3 else 0.07
    size = float(args[4]) if len(args) > 4 else 1.0
    card_ratio = float(args[5]) if len(args) > 5 else 1.0
    trunk = bpy.data.objects["jacaranda_tree_trunk_LOD1"]
    # fine branch network (geometry nodes scatter the leaves on it): the realised
    # mesh shows where the tree really carries leaves. It stands beside the trunk
    # in the file, so work in its own space, which lines up with the trunk.
    fine = bpy.data.objects["jacaranda_tree_geometry_nodes"]
    fine.hide_viewport = False
    fine.hide_set(False)
    dg = bpy.context.evaluated_depsgraph_get()
    fmesh = bpy.data.meshes.new_from_object(fine.evaluated_get(dg))
    step = max(1, len(fmesh.vertices) // 60000)
    pts = [fmesh.vertices[i].co.copy() for i in range(0, len(fmesh.vertices), step)]
    print("[tree] sample points", len(pts))
    top = max(p.z for p in pts)
    centre = Vector((sum(p.x for p in pts) / len(pts), sum(p.y for p in pts) / len(pts), top * 0.5))
    # mostly the outer shell of the crown, some inside so it is not hollow
    # nothing low: the crown must clear a road that passes under it
    cand = [p for p in pts if p.z > top * 0.46 and ((p - centre).length > top * 0.36 or random.random() < 0.25)]
    random.shuffle(cand)
    cand = cand[:5000]
    # farthest-point sampling for an even spread of clusters
    chosen = [cand[0]]
    dist = [(p - cand[0]).length for p in cand]
    while len(chosen) < N:
        i = max(range(len(cand)), key=lambda j: dist[j])
        chosen.append(cand[i])
        for j, p in enumerate(cand):
            d = (p - cand[i]).length
            if d < dist[j]:
                dist[j] = d
    clusters = [bpy.data.objects["jacaranda_tree_leaves_a_LOD1"], bpy.data.objects["jacaranda_tree_leaves_b_LOD1"]]
    made = []
    roots = []
    for p in chosen:
        src = random.choice(clusters)
        ob = src.copy()
        ob.data = src.data.copy()
        bpy.context.scene.collection.objects.link(ob)
        if card_ratio < 1.0:
            ob.modifiers.new("dec", "DECIMATE").ratio = card_ratio
        # the cluster grows along its +Y; aim that outward and a little up, with its flat side facing up
        outward = (p - centre).normalized()
        y = (outward + Vector((0, 0, random.uniform(0.0, 0.5)))).normalized()
        x = y.cross(Vector((0, 0, 1))).normalized()
        z = x.cross(y).normalized()
        rot = Matrix((x, y, z)).transposed().to_4x4() @ Matrix.Rotation(random.uniform(-0.6, 0.6), 4, "Y")
        sc = random.uniform(2.2, 3.2) * size
        root = p - y * 0.6 * sc * 0.3
        ob.matrix_world = Matrix.Translation(root) @ rot @ Matrix.Scale(sc, 4)
        made.append(ob)
        roots.append(root)
    # lighter trunk, and the real limbs that carry the crown
    t = trunk.copy()
    t.data = trunk.data.copy()
    bpy.context.scene.collection.objects.link(t)
    decimated(t, limb_ratio)
    # limbs carrying the crown: the scan's own fine branches are far too heavy,
    # so grow boughs from the real trunk's upper branches out to groups of leaf
    # clusters, and a twig from each bough to each cluster
    tv = [v.co.copy() for v in t.data.vertices]
    ttop = max(v.z for v in tv)
    anchors = [v for v in tv if v.z > ttop * 0.5]
    G = max(8, N // 7)
    seeds = [roots[0]]
    dd = [(r - roots[0]).length for r in roots]
    while len(seeds) < G:
        i = max(range(len(roots)), key=lambda j: dd[j])
        seeds.append(roots[i])
        for j, r in enumerate(roots):
            dd[j] = min(dd[j], (r - roots[i]).length)
    groups = [[] for _ in seeds]
    for r in roots:
        groups[min(range(G), key=lambda j: (r - seeds[j]).length)].append(r)
    verts, faces, uvs = [], [], []
    for grp in groups:
        if not grp:
            continue
        cen = sum(grp, Vector()) / len(grp)
        anc = min(anchors, key=lambda v: (v - cen).length + max(0.0, v.z - cen.z) * 2.0)
        node = anc.lerp(cen, 0.72)
        bend = (anc + node) / 2 + Vector((0, 0, (node - anc).length * 0.12))
        tube([anc, anc.lerp(bend, 0.66), bend.lerp(node, 0.5), node], [0.15, 0.12, 0.09, 0.06], 6, verts, faces, uvs)
        for r in grp:
            mid = (node + r) / 2 + Vector((0, 0, (r - node).length * 0.1))
            tube([node, mid, r] if card_ratio == 1.0 else [node, r], [0.055, 0.04, 0.018] if card_ratio == 1.0 else [0.055, 0.02], 4 if card_ratio == 1.0 else 3, verts, faces, uvs)
    lm = bpy.data.meshes.new("limbs")
    lm.from_pydata(verts, [], faces)
    uvl = lm.uv_layers.new(name="UVMap")
    for poly in lm.polygons:
        for li in poly.loop_indices:
            uvl.data[li].uv = uvs[lm.loops[li].vertex_index]
        poly.use_smooth = True
    lm.materials.append(bpy.data.materials["jacaranda_tree_branches"])
    limbs = bpy.data.objects.new("limbs", lm)
    bpy.context.scene.collection.objects.link(limbs)
    for o in bpy.context.scene.objects:
        o.select_set(False)
    for o in [t, limbs] + made:
        o.select_set(True)
    bpy.context.view_layer.objects.active = t
    bpy.ops.object.convert(target="MESH")
    bpy.ops.object.join()
    tree = bpy.context.view_layer.objects.active
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    # stand it on the origin at game size (the scanned tree is about 19 m tall)
    base = Vector((0.9, 0.5, 0.0))
    for v in tree.data.vertices:
        v.co = (v.co - base) * k
    export([tree], name)
