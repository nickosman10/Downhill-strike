"""Bakes a full-detail scanned plant (Poly Haven, CC0) into cut-out images.

    blender -b -P tools/blender_bake_tree.py -- <in.gltf> <out_prefix> [object_index]

Renders the plant from two sides with a transparent background and soft,
even light, so the game can light it itself. Prints the plant's width/height.
"""
import bpy, sys, math
from mathutils import Vector

args = sys.argv[sys.argv.index("--") + 1:]
src, prefix = args[0], args[1]
pick = int(args[2]) if len(args) > 2 else -1
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
scn = bpy.context.scene
meshes = [o for o in scn.objects if o.type == "MESH"]
print("[bake] objects", [(o.name, len(o.data.polygons)) for o in meshes][:12])
if pick >= 0:
    # keep one plant from a set: objects whose centre is near the picked one's
    c = meshes[pick].matrix_world.translation
    for o in meshes:
        if (o.matrix_world.translation - c).length > 0.05:
            o.hide_render = True
    meshes = [o for o in meshes if not o.hide_render]
pts = [o.matrix_world @ Vector(b) for o in meshes for b in o.bound_box]
mn = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
mx = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
h = mx.z - mn.z
w = max(mx.x - mn.x, mx.y - mn.y)
cen = (mn + mx) / 2
print("[bake] size w %.2f h %.2f" % (w, h))
scn.render.engine = "CYCLES"
scn.cycles.samples = 24
scn.cycles.device = "CPU"
scn.render.film_transparent = True
scn.render.resolution_x = 1024
scn.render.resolution_y = 1024
scn.render.image_settings.file_format = "PNG"
scn.render.image_settings.color_mode = "RGBA"
scn.view_settings.view_transform = "Standard"
world = bpy.data.worlds.new("w")
world.use_nodes = True
world.node_tree.nodes["Background"].inputs[0].default_value = (1, 1, 1, 1)
world.node_tree.nodes["Background"].inputs[1].default_value = 1.6
scn.world = world
cam_d = bpy.data.cameras.new("c")
cam_d.type = "ORTHO"
cam_d.ortho_scale = max(w, h) * 1.02
cam = bpy.data.objects.new("c", cam_d)
scn.collection.objects.link(cam)
scn.camera = cam
for k, ang in enumerate((0.0, math.pi / 2)):
    d = Vector((math.sin(ang), -math.cos(ang), 0))
    cam.location = cen + d * 50
    cam.rotation_euler = (cen - cam.location).to_track_quat("-Z", "Y").to_euler()
    scn.render.filepath = "%s_%d.png" % (prefix, k)
    bpy.ops.render.render(write_still=True)
print("[bake] done")
