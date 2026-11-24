"""Turns a scanned Poly Haven plant (CC0) into a game-ready model.

    blender -b -P tools/blender_tree.py -- <in.gltf> <out.glb> <target_tris> <height_m>

Joins the parts, reduces the triangle count, stands it on the ground at the
origin, scales it to the given height and exports a .glb with its textures.
"""
import bpy, sys
from mathutils import Vector

src, dst, target, height = sys.argv[sys.argv.index("--") + 1:][:4]
target = int(target); height = float(height)
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
for o in bpy.context.scene.objects:
    o.select_set(o in meshes)
bpy.context.view_layer.objects.active = meshes[0]
if len(meshes) > 1:
    bpy.ops.object.join()
ob = bpy.context.view_layer.objects.active
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
tris = sum(len(p.vertices) - 2 for p in ob.data.polygons)
print("[tree] source tris", tris, "materials", [m.name for m in ob.data.materials])
if tris > target:
    m = ob.modifiers.new("dec", "DECIMATE")
    m.ratio = target / tris
    bpy.ops.object.modifier_apply(modifier="dec")
vs = [v.co for v in ob.data.vertices]
zmin = min(v.z for v in vs); zmax = max(v.z for v in vs)
cx = sum(v.x for v in vs) / len(vs); cy = sum(v.y for v in vs) / len(vs)
k = height / (zmax - zmin)
for v in ob.data.vertices:
    v.co = Vector(((v.co.x - cx) * k, (v.co.y - cy) * k, (v.co.z - zmin) * k))
for p in ob.data.polygons:
    p.use_smooth = True
ob.name = "Plant"
print("[tree] out tris", sum(len(p.vertices) - 2 for p in ob.data.polygons))
bpy.ops.export_scene.gltf(filepath=dst, export_format="GLB", use_selection=True, export_image_format="JPEG", export_jpeg_quality=85)
