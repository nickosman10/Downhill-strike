"""Builds a high-detail car model in Blender and exports it as a .glb the game loads.

    blender -b -P tools/blender_car.py -- ae86 [--render out.png]

Coordinates while building: x right, y forward (front of the car is +y), z up,
origin on the ground at the middle of the car's length. The glTF exporter turns
this into Godot's convention (front = -Z, up = +Y).

Body: a dense loft of cross-sections (from the measured side profile of each
car) run through a subdivision surface, with real wheel arches cut out by
boolean, glass inset behind black window frames, and separate modelled parts:
bumpers, arch lips, lamps, grille, mirrors, plates, wipers, door shut lines,
handles and the livery. Wheels are lathed tyres with rounded sidewalls and
rims with real spokes.

Named nodes the game looks for:
  Body                        everything static
  Wheel_FL / FR / RL / RR     origin at the hub, axle along X
  Popup_L / Popup_R           origin on the hinge (pop-up lamps only)
Material names: Paint, Lower, Glass, Trim, Chrome, Lens, Tail, Amber,
  Reverse, Plate, Tire, Rim, RimLip, Well, Decal, Interior
"""
import bpy
import bmesh
import math
import sys
import os
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from car_specs import SPECS  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
JP_FONT = "/usr/share/fonts/opentype/ipafont-gothic/ipag.ttf"


# ------------------------------------------------------------------ helpers

def lerp(a, b, t):
    return a + (b - a) * t


def clamp(x, a, b):
    return max(a, min(b, x))


def smooth(t):
    t = clamp(t, 0.0, 1.0)
    return t * t * (3 - 2 * t)


def mat(name, color, rough=0.5, metal=0.0, emit=None, emit_strength=0.0):
    m = bpy.data.materials.get(name)
    if m:
        return m
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*color, 1.0)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    if emit:
        b.inputs["Emission Color"].default_value = (*emit, 1.0)
        b.inputs["Emission Strength"].default_value = emit_strength
    m.diffuse_color = (*color, 1.0)
    return m


def new_obj(name, bm_or_mesh, mats=()):
    if isinstance(bm_or_mesh, bmesh.types.BMesh):
        me = bpy.data.meshes.new(name)
        bm_or_mesh.to_mesh(me)
        bm_or_mesh.free()
    else:
        me = bm_or_mesh
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    for m in mats:
        me.materials.append(m)
    return ob


def apply_mods(ob):
    dg = bpy.context.evaluated_depsgraph_get()
    ev = ob.evaluated_get(dg)
    me = bpy.data.meshes.new_from_object(ev)
    old = ob.data
    ob.modifiers.clear()
    ob.data = me
    bpy.data.meshes.remove(old)


def shade(ob, angle=38.0):
    """Smooth shading with sharp edges above `angle` (exported as split normals)."""
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    for f in bm.faces:
        f.smooth = True
    lim = math.radians(angle)
    for e in bm.edges:
        if len(e.link_faces) == 2:
            if e.calc_face_angle(0.0) > lim or e.link_faces[0].material_index != e.link_faces[1].material_index:
                e.smooth = False
        else:
            e.smooth = False
    bm.to_mesh(ob.data)
    bm.free()


def subdivide(ob, levels=1):
    m = ob.modifiers.new("sub", "SUBSURF")
    m.levels = levels
    m.render_levels = levels
    m.quality = 3
    apply_mods(ob)


def bevel(ob, width=0.006, segs=2, angle=40.0):
    m = ob.modifiers.new("bev", "BEVEL")
    m.width = width
    m.segments = segs
    m.limit_method = "ANGLE"
    m.angle_limit = math.radians(angle)
    m.harden_normals = False
    apply_mods(ob)


def box_bm(bm, center, size, mat_index=0, rot=None):
    """Axis-aligned (optionally rotated) box into an existing bmesh."""
    res = bmesh.ops.create_cube(bm, size=1.0)
    vs = res["verts"]
    M = Matrix.Diagonal((*size, 1.0))
    if rot is not None:
        M = rot.to_4x4() @ M
    M = Matrix.Translation(center) @ M
    bmesh.ops.transform(bm, matrix=M, verts=vs)
    for f in {f for v in vs for f in v.link_faces}:
        f.material_index = mat_index
    return vs


def sweep(bm, path, profile, up=Vector((0, 0, 1)), closed_path=False, cap=True, mat_index=0, normals=None):
    """Sweep a 2D profile [(u, v)] along a 3D path. u runs along `side` (path x up), v along the frame's up."""
    rings = []
    n = len(path)
    for i, p in enumerate(path):
        a = path[(i - 1) % n] if (closed_path or i > 0) else p
        b = path[(i + 1) % n] if (closed_path or i < n - 1) else p
        t = (Vector(b) - Vector(a)).normalized()
        u = (normals[i] if normals else up)
        side = t.cross(u).normalized()
        upv = side.cross(t).normalized()
        ring = [bm.verts.new(Vector(p) + side * pu + upv * pv) for pu, pv in profile]
        rings.append(ring)
    m = len(profile)
    segs = n if closed_path else n - 1
    for i in range(segs):
        r0, r1 = rings[i], rings[(i + 1) % n]
        for j in range(m):
            f = bm.faces.new((r0[j], r0[(j + 1) % m], r1[(j + 1) % m], r1[j]))
            f.material_index = mat_index
    if cap and not closed_path:
        f = bm.faces.new(list(reversed(rings[0])))
        f.material_index = mat_index
        f = bm.faces.new(rings[-1])
        f.material_index = mat_index
    return rings


def lathe(bm, profile, segs, mat_of=None, axis_x=True):
    """Revolve [(r, x)] around the X axis. mat_of(i) gives the material of profile segment i."""
    rings = []
    for k in range(segs):
        a = math.tau * k / segs
        ca, sa = math.cos(a), math.sin(a)
        rings.append([bm.verts.new((x, r * ca, r * sa)) for r, x in profile])
    for k in range(segs):
        r0, r1 = rings[k], rings[(k + 1) % segs]
        for j in range(len(profile) - 1):
            if profile[j][0] < 1e-5 and profile[j + 1][0] < 1e-5:
                continue
            vs = [r0[j], r1[j], r1[j + 1], r0[j + 1]]
            if profile[j][0] < 1e-5:
                vs = [r0[j], r1[j + 1], r0[j + 1]]
            elif profile[j + 1][0] < 1e-5:
                vs = [r0[j], r1[j], r1[j + 1]]
            try:
                f = bm.faces.new(vs)
            except ValueError:
                continue
            f.material_index = mat_of(j) if mat_of else 0
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    return rings


def flip_outward(bm):
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)


# ------------------------------------------------------------------ the car

class Car:
    def __init__(self, cid):
        self.id = cid
        self.s = SPECS[cid]
        s = self.s
        self.L = s["L"]
        self.rows = s["rows"]          # [d, bottom, crease, belt, top, half width, roof half width]
        self.M = {
            "Paint": mat("Paint", s["paint"], 0.25, 0.1),
            "Lower": mat("Lower", s["lower"], 0.35, 0.1),
            "Glass": mat("Glass", (0.03, 0.04, 0.06), 0.05, 0.4),
            "Trim": mat("Trim", (0.02, 0.02, 0.022), 0.55),
            "Chrome": mat("Chrome", (0.85, 0.85, 0.87), 0.12, 1.0),
            "Lens": mat("Lens", (0.9, 0.92, 0.95), 0.05, 0.2, (1.0, 0.97, 0.88), 3.0),
            "Tail": mat("Tail", (0.55, 0.02, 0.02), 0.15, 0.0, (1.0, 0.05, 0.03), 1.0),
            "Amber": mat("Amber", (0.95, 0.45, 0.05), 0.15, 0.0, (1.0, 0.45, 0.0), 0.4),
            "Reverse": mat("Reverse", (0.62, 0.64, 0.66), 0.05, 0.6),
            "Plate": mat("Plate", (0.93, 0.93, 0.88), 0.5),
            "Tire": mat("Tire", (0.035, 0.035, 0.037), 0.85),
            "Rim": mat("Rim", s.get("rim", (0.55, 0.56, 0.58)), 0.3, 0.8),
            "RimLip": mat("RimLip", (0.8, 0.8, 0.82), 0.15, 1.0),
            "Well": mat("Well", (0.012, 0.012, 0.014), 0.9),
            "Decal": mat("Decal", s.get("decal", (0.03, 0.03, 0.03)), 0.4),
            "Interior": mat("Interior", (0.04, 0.04, 0.045), 0.8),
        }
        self.parts = []      # objects merged into Body
        self.bumpers = []
        self.fo = s["fo"]
        self.wb = s["wb"]
        self.tire_r = s["tire"]
        self.wheel_d = [self.fo, self.fo + self.wb]

    # car space: d metres from the front bumper -> blender y
    def Y(self, d):
        return self.L * 0.5 - d

    def st(self, d):
        rows = self.rows
        out = list(rows[-1][1:])
        if d <= rows[0][0]:
            out = list(rows[0][1:])
        else:
            for i in range(1, len(rows)):
                if d <= rows[i][0]:
                    a, b = rows[i - 1], rows[i]
                    t = (d - a[0]) / max(b[0] - a[0], 1e-6)
                    out = [lerp(a[k], b[k], t) for k in range(1, len(a))]
                    break
        # fenders always clear the wheel arch: the shoulder rises over each wheel
        R = self.tire_r + self.s.get("arch_gap", 0.055)
        need = self.tire_r + R + 0.06
        for dw in self.wheel_d:
            f = smooth(1.0 - abs(d - dw) / (R + 0.35))
            if f > 0 and out[2] < need:
                rise = (need - out[2]) * f
                out[2] += rise
                out[1] = min(out[1] + rise * 0.6, out[2] - 0.05)
                if out[3] < out[2] + 0.004:
                    out[3] = max(out[3], out[2] - 0.035)   # hood centre may sit below the fender tops
        return out

    # ---------------------------------------------------------- body shell
    def ring(self, d):
        """Right half cross-section, bottom centre -> top centre, as (x, z)."""
        bot, crease, belt, top, w, rw = self.st(d)
        s = self.s
        gh = smooth((top - belt - 0.04) / 0.3)   # 0 over the hood/deck, 1 at the cabin
        sill = s.get("sill_in", 0.05)
        pts = [
            (0.0, bot),
            (w * 0.55, bot),
            (w - sill, bot + 0.005),
            (w - sill * 0.35, bot + 0.05),
            (w - 0.01, lerp(bot, crease, 0.5)),
            (w, crease),                                   # side character line
            (w - 0.006, lerp(crease, belt, 0.5)),
            (w - 0.022, belt - 0.025),
            (w - 0.045, belt + 0.002),                     # shoulder
        ]
        # greenhouse (blends to a crowned hood/deck where there is no cabin)
        hood = [(w - 0.11, lerp(belt, top, 0.55) + 0.004), (w * 0.62, top - 0.006), (w * 0.3, top)]
        tum = s.get("tumble", 0.55)
        cab = [(lerp(w - 0.06, rw, tum), lerp(belt, top, 0.55)), (rw, top - 0.045), (rw - 0.14, top - 0.004)]
        for (hx, hz), (cx, cz) in zip(hood, cab):
            pts.append((lerp(hx, cx, gh), lerp(hz, cz, gh)))
        pts.append((rw * 0.35 * gh + w * 0.1 * (1 - gh), top + 0.002))
        pts.append((0.0, top + 0.003))
        return pts

    def build_shell(self):
        s = self.s
        bm = bmesh.new()
        # dense stations, with extra ones near the ends for a crisp nose and tail
        ds = []
        d = 0.0
        while d < self.L:
            ds.append(d)
            step = 0.025 if (d < 0.12 or d > self.L - 0.12) else 0.07
            d += step
        ds.append(self.L)
        # pull the very ends in so the subdivided nose/tail round off like pressed steel
        rings = []
        for i, d in enumerate(ds):
            r = self.ring(d)
            ins = 0.0
            if d < 0.06:
                ins = (0.06 - d) / 0.06
            elif d > self.L - 0.06:
                ins = (d - (self.L - 0.06)) / 0.06
            ins = ins * ins * s.get("end_round", 0.06)
            row = []
            nh = len(r)
            for j, (x, z) in enumerate(r):
                xx = max(x - ins, 0.0) if x > 0 else 0.0
                zz = z
                if j == nh - 1 or j == nh - 2:
                    zz = z - ins * 0.6
                row.append((xx, zz))
            rings.append(row)
        nh = len(rings[0])
        verts = []
        for i, d in enumerate(ds):
            y = self.Y(d)
            r = rings[i]
            full = []
            # left side reversed (excluding centre points), then right
            left = [bm.verts.new((-x, y, z)) for x, z in r[1:-1]]
            bc = bm.verts.new((0.0, y, r[0][1]))
            tc = bm.verts.new((0.0, y, r[-1][1]))
            right = [bm.verts.new((x, y, z)) for x, z in r[1:-1]]
            full = [bc] + right + [tc] + list(reversed(left))
            verts.append(full)
        m = len(verts[0])
        for i in range(len(verts) - 1):
            a, b = verts[i], verts[i + 1]
            for j in range(m):
                bm.faces.new((a[j], a[(j + 1) % m], b[(j + 1) % m], b[j]))
        # caps: ladder of quads between left and right halves
        for ring_v, flip in ((verts[0], False), (verts[-1], True)):
            half = nh - 1   # index of top centre in full ring
            for j in range(half - 1):
                r0 = ring_v[j]
                r1 = ring_v[j + 1]
                l1 = ring_v[(m - j - 1) % m]
                l0 = ring_v[(m - j) % m]
                quad = [r0, r1, l1, l0] if j > 0 else [r0, r1, l1]
                if flip:
                    quad = list(reversed(quad))
                try:
                    bm.faces.new(quad)
                except ValueError:
                    pass
            last = [ring_v[half - 1], ring_v[half], ring_v[half + 1]]
            if flip:
                last = list(reversed(last))
            try:
                bm.faces.new(last)
            except ValueError:
                pass
        bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
        flip_outward(bm)
        ob = new_obj("Shell", bm, [self.M["Paint"]])
        subdivide(ob, 2)
        self.shell = ob
        return ob

    # ---------------------------------------------------------- paint regions
    # ---------------------------------------------------------- clean region cuts
    def _plane_dz(self, p1, p2, inside):
        """Plane through two side-view points (d, z), running across the car."""
        a = Vector((0, self.Y(p1[0]), p1[1]))
        b = Vector((0, self.Y(p2[0]), p2[1]))
        no = (b - a).cross(Vector((1, 0, 0))).normalized()
        ins = Vector((0, self.Y(inside[0]), inside[1]))
        if (ins - a).dot(no) < 0:
            no = -no
        return (a, no)

    def _plane_dx(self, p1, p2, inside):
        """Plane through two plan-view points (d, x), running vertically."""
        a = Vector((p1[1], self.Y(p1[0]), 0))
        b = Vector((p2[1], self.Y(p2[0]), 0))
        no = (b - a).cross(Vector((0, 0, 1))).normalized()
        ins = Vector((inside[1], self.Y(inside[0]), 0))
        if (ins - a).dot(no) < 0:
            no = -no
        return (a, no)

    def _plane_x(self, x, above):
        return (Vector((x, 0, 0)), Vector((1 if above else -1, 0, 0)))

    def regions(self):
        """Convex regions (lists of half-spaces) for the glass and pillars, in priority order."""
        s = self.s
        g0, g1 = s["glass"]
        r0, r1 = s["roof"]
        sd0, sd1 = s["side"]
        bp = s.get("b", (9, 9))
        belt = lambda d: self.st(d)[2]
        top = lambda d: self.st(d)[3]
        rw = lambda d: self.st(d)[5]
        out = []
        if s.get("roofless"):
            cp = s.get("cockpit", (r0, r1))
            out.append(("Interior", [self._plane_z(belt(cp[0]) + 0.02, True),
                                     self._plane_dz((cp[0], 0), (cp[0], 2), (cp[0] + 1, 0)),
                                     self._plane_dz((cp[1], 0), (cp[1], 2), (cp[1] - 1, 0))]))
        # windscreen
        fr = s.get("frame", 0.075)
        dm = (g0 + r0) / 2
        ws = [self._plane_z(belt(g0) + 0.045, True),
              self._plane_dz((r0 - 0.035, 0), (r0 - 0.035, 2), (dm, 0))]
        for sx in (-1, 1):
            ws.append(self._plane_dx((g0, sx * (rw(g0) - fr - 0.03)), (r0, sx * (rw(r0) - fr)), (dm, 0)))
        out.append(("Glass", ws))
        # rear glass (hatch / backlight)
        if g1 > r1 + 0.1:
            dm2 = (r1 + g1) / 2
            rg = [self._plane_z(top(g1) + 0.03, True),
                  self._plane_dz((r1 + 0.04, 0), (r1 + 0.04, 2), (dm2, 0))]
            for sx in (-1, 1):
                rg.append(self._plane_dx((r1, sx * (rw(r1) - fr)), (g1, sx * (rw(g1) - fr - 0.04)), (dm2, 0)))
            out.append(("Glass", rg))
        # side windows (per side) and the black B pillar
        if sd1 > sd0:
            zt = top((r0 + r1) / 2) - s.get("side_top", 0.065)
            a_off = s.get("a_off", 0.085)
            slant = s.get("side_slant", 0.0)
            h = zt - belt(sd1)
            dmid = (sd0 + sd1) / 2
            zin = (belt(dmid) + zt) / 2
            for sx in (-1, 1):
                sw = [self._plane_x(sx * 0.3, sx > 0),
                      self._plane_dz((sd1, 0), (sd1, 2), (dmid, zin)),
                      self._plane_dz((sd0, belt(sd0) + 0.035), (sd1, belt(sd1) + 0.035), (dmid, zin)),
                      self._plane_z(zt, False),
                      # A pillar runs parallel to the windscreen
                      self._plane_dz((g0 + a_off, belt(g0)), (r0 + a_off, top(r0)), (dmid, zin)),
                      # C pillar: the quarter window's rear edge runs parallel to the hatch glass,
                      # leaving an even strip of body colour between them
                      (self._plane_dz((r1 - s["c_off"], top(r1)), (g1 - s["c_off"], top(g1)), (dmid, zin))
                       if s.get("c_off") else
                       self._plane_dz((sd1, belt(sd1)), (sd1 - slant * h, zt), (dmid, zin)))]
                if bp[0] < 8:
                    out.append(("Trim", sw + [self._plane_dz((bp[0], 0), (bp[0], 2), (bp[1], 0)),
                                              self._plane_dz((bp[1], 0), (bp[1], 2), (bp[0], 0))]))
                out.append(("Glass", sw))
        return out

    def _plane_z(self, z, above):
        return (Vector((0, 0, z)), Vector((0, 0, 1 if above else -1)))

    @staticmethod
    def _inside(c, planes):
        return all((c - co).dot(no) > 0 for co, no in planes)

    def cut(self, bm, planes):
        for co, no in planes:
            geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
            bmesh.ops.bisect_plane(bm, geom=geom, dist=1e-5, plane_co=co, plane_no=no)

    def assign_regions(self):
        s = self.s
        ob = self.shell
        names = ["Paint", "Lower", "Glass", "Trim", "Well", "Interior"]
        me = ob.data
        me.materials.clear()
        for n in names:
            me.materials.append(self.M[n])
        idx = {n: i for i, n in enumerate(names)}
        bm = bmesh.new()
        bm.from_mesh(me)
        regs = self.regions()
        panda = s.get("panda", 0.0)
        # cut the surface exactly along every border first, so colour edges are clean lines
        planes = [p for _, pl in regs for p in pl]
        if panda > 0:
            planes.append(self._plane_z(panda, True))
        self.cut(bm, planes)
        glass_faces = []
        for f in bm.faces:
            c = f.calc_center_median()
            region = "Lower" if (panda > 0.0 and c.z < panda) else "Paint"
            for name, pl in regs:
                if self._inside(c, pl):
                    region = name
                    break
            f.material_index = idx[region]
            if region == "Glass":
                glass_faces.append(f)
        # window frames: inset the glass behind a black rubber surround
        res = bmesh.ops.inset_region(bm, faces=glass_faces, thickness=0.016, depth=-0.005, use_even_offset=True)
        for f in res["faces"]:
            f.material_index = idx["Trim"]
        bm.to_mesh(me)
        bm.free()

    # ---------------------------------------------------------- wheel arches
    def cut_arches(self):
        s = self.s
        R = self.tire_r + s.get("arch_gap", 0.055)
        cutters = []
        for i, d in enumerate(self.wheel_d):
            bm = bmesh.new()
            bmesh.ops.create_cone(bm, cap_ends=True, segments=64, radius1=R, radius2=R, depth=0.7)
            bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.pi / 2, 3, "Y"))
            tr = s["track"][i] * 0.5
            for sx in (-1, 1):
                b2 = bm.copy()
                bmesh.ops.translate(b2, verts=b2.verts, vec=(sx * (tr + 0.33), self.Y(d), self.tire_r))
                ob = new_obj("cut", b2, [self.M["Well"]])
                cutters.append(ob)
            bm.free()
        for c in cutters:
            m = self.shell.modifiers.new("arch", "BOOLEAN")
            m.operation = "DIFFERENCE"
            m.solver = "EXACT"
            m.object = c
            m.material_mode = "TRANSFER"
            apply_mods(self.shell)
        for c in cutters:
            bpy.data.objects.remove(c)
        # arch lips: a rolled lip just proud of the body around each opening
        bm = bmesh.new()
        for i, d in enumerate(self.wheel_d):
            tr = s["track"][i] * 0.5
            for sx in (-1, 1):
                path = []
                nrm = []
                a0, a1 = math.radians(-8), math.radians(188)
                for k in range(33):
                    a = lerp(a0, a1, k / 32)
                    y = self.Y(d) + math.cos(a) * (R + 0.006)
                    z = self.tire_r + math.sin(a) * (R + 0.006)
                    dd = self.L * 0.5 - y
                    bot, crease, belt, top, w, rw = self.st(dd)
                    if z < bot + 0.01:
                        continue
                    x = self.surface_x(dd, z)
                    path.append(Vector((sx * (x + 0.004), y, z)))
                    nrm.append(Vector((sx, 0, 0)))
                if len(path) > 2:
                    flare = s.get("flare", 0.012)
                    prof = [(-0.012, -0.01), (0.012, -0.012), (0.03, flare * 0.4), (0.0, flare), (-0.02, 0.004)]
                    if sx < 0:
                        prof = [(-u, v) for u, v in reversed(prof)]
                    sweep(bm, path, prof, normals=nrm, mat_index=0)
        lip_mat = s.get("lip_mat", "Paint")
        lip = new_obj("ArchLips", bm, [self.M[lip_mat]])
        flip_outward_obj(lip)
        if s.get("panda", 0) > 0.0 and lip_mat == "Paint":
            self.paint_by_height(lip)
        shade(lip, 50)
        self.parts.append(lip)

    def surface_x(self, d, z):
        """Half-width of the shell at height z (from the section polygon)."""
        r = self.ring(d)
        best = 0.0
        for (x0, z0), (x1, z1) in zip(r, r[1:]):
            if min(z0, z1) <= z <= max(z0, z1) and abs(z1 - z0) > 1e-6:
                t = (z - z0) / (z1 - z0)
                best = max(best, lerp(x0, x1, t))
        return best

    def paint_by_height(self, ob):
        """Two-tone (panda) objects: faces below the split line get the lower colour."""
        me = ob.data
        bm = bmesh.new()
        bm.from_mesh(me)
        self.cut(bm, [self._plane_z(self.s.get("panda", 0.0), True)])
        bm.to_mesh(me)
        bm.free()
        names = [m.name for m in me.materials]
        for n in ("Paint", "Lower"):
            if n not in names:
                me.materials.append(self.M[n])
                names.append(n)
        ip, il = names.index("Paint"), names.index("Lower")
        split = self.s.get("panda", 0.0)
        for p in me.polygons:
            if p.material_index in (ip, il):
                p.material_index = il if p.center.z < split else ip

    # ---------------------------------------------------------- projection helpers
    def bvh(self, extra=()):
        bm = bmesh.new()
        for ob in [self.shell, *extra]:
            me = ob.data.copy()
            me.transform(ob.matrix_world)
            bm.from_mesh(me)
            bpy.data.meshes.remove(me)
        t = BVHTree.FromBMesh(bm)
        bm.free()
        return t

    def project(self, tree, origin, direction):
        hit = tree.ray_cast(Vector(origin), Vector(direction).normalized(), 5.0)
        return hit[0], hit[1]

    def decal(self, name, tree, verts_uv, faces, origin_fn, direction, mat_name, offset=0.004, thickness=0.0):
        """Project a flat 2D mesh onto the shell along `direction`."""
        bm = bmesh.new()
        vs = []
        dirn = Vector(direction).normalized()
        last_t = None
        hits = []
        for uv in verts_uv:
            o = Vector(origin_fn(uv))
            p, n = self.project(tree, o, direction)
            if p is not None:
                last_t = (p - o).dot(dirn)
            hits.append((o, p, n))
        ts = [(p - o).dot(dirn) for o, p, n in hits if p is not None]
        t_avg = sum(ts) / len(ts) if ts else 1.0
        for o, p, n in hits:
            if p is None:
                # missed the edge of a rounded panel: snap to the nearest surface point
                q, n2, _, _ = tree.find_nearest(o + dirn * t_avg)
                p, n = q, n2
            vs.append(bm.verts.new(p + n * offset))
        for f in faces:
            try:
                bm.faces.new([vs[i] for i in f])
            except ValueError:
                pass
        if thickness > 0:
            res = bmesh.ops.extrude_face_region(bm, geom=bm.faces[:])
            nv = [e for e in res["geom"] if isinstance(e, bmesh.types.BMVert)]
            bmesh.ops.translate(bm, verts=nv, vec=-Vector(direction).normalized() * thickness)
        flip_outward(bm)
        ob = new_obj(name, bm, [self.M[mat_name]])
        return ob

    def panel(self, tree, name, side, d0, d1, z0, z1, mat_name, offset=0.003, nu=10, nv=4, thickness=0.0, round_r=0.0):
        """A shaped plate on a side (+1/-1 x), front ('F') or back ('B') face of the shell."""
        verts, faces = [], []
        for j in range(nv + 1):
            for i in range(nu + 1):
                verts.append((lerp(d0, d1, i / nu), lerp(z0, z1, j / nv)))
        for j in range(nv):
            for i in range(nu):
                a = j * (nu + 1) + i
                faces.append((a, a + 1, a + nu + 2, a + nu + 1))
        if side in (1, -1):
            fn = lambda uv: (side * 2.0, self.Y(uv[0]), uv[1])
            dirv = (-side, 0, 0)
        elif side == "F":
            fn = lambda uv: (uv[0], self.L, uv[1])
            dirv = (0, -1, 0)
        else:
            fn = lambda uv: (uv[0], -self.L, uv[1])
            dirv = (0, 1, 0)
        ob = self.decal(name, tree, verts, faces, fn, dirv, mat_name, offset, thickness)
        if round_r > 0:
            bevel(ob, round_r, 2, 30)
        shade(ob, 45)
        self.parts.append(ob)
        return ob

    def text_decal(self, tree, text, side, d_center, z, size, mat_name="Decal", font=JP_FONT):
        cu = bpy.data.curves.new("txt", "FONT")
        cu.body = text
        cu.font = bpy.data.fonts.load(font, check_existing=True)
        cu.size = size
        cu.align_x = "CENTER"
        cu.align_y = "CENTER"
        cu.resolution_u = 4
        tob = bpy.data.objects.new("txt", cu)
        bpy.context.scene.collection.objects.link(tob)
        dg = bpy.context.evaluated_depsgraph_get()
        me = bpy.data.meshes.new_from_object(tob.evaluated_get(dg))
        bpy.data.objects.remove(tob)
        bm = bmesh.new()
        bm.from_mesh(me)
        bmesh.ops.triangulate(bm, faces=bm.faces[:])
        uv = [(v.co.x, v.co.y) for v in bm.verts]
        faces = [[v.index for v in f.verts] for f in bm.faces]
        bm.free()
        bpy.data.meshes.remove(me)
        # text reads left-to-right from outside the car on either side
        if side > 0:
            fn = lambda p: (2.0, self.Y(d_center) + p[0], z + p[1])
        else:
            fn = lambda p: (-2.0, self.Y(d_center) - p[0], z + p[1])
        ob = self.decal("Livery", tree, uv, faces, fn, (-side, 0, 0), mat_name, 0.0035)
        self.parts.append(ob)
        return ob

    # ---------------------------------------------------------- details
    def build_details(self):
        s = self.s
        tree = self.bvh()
        L = self.L
        f0 = self.st(0.0)
        b0 = self.st(L)
        # ---- bumpers: wrap-around bars following the plan outline
        for key, d_face, sgn in (("bumper_f", 0.0, 1), ("bumper_r", L, -1)):
            bz = s.get(key)
            if not bz:
                continue
            z0, z1, wrap, proud, mname = bz
            path, nrm = [], []
            ns = 40
            for k in range(ns + 1):
                u = lerp(-1.0, 1.0, k / ns)
                ang = u * math.pi * 0.5
                # front face then wrap around the corner and back along the side
                if abs(u) < 0.7:
                    x = u / 0.7 * (self.surface_x(d_face + sgn * 0.05, (z0 + z1) / 2) - 0.12)
                    origin = (x, sgn * L, (z0 + z1) / 2)
                    hit, hn = self.project(tree, origin, (0, -sgn, 0))
                    y = hit.y if hit else self.Y(d_face)
                    path.append(Vector((x, y + sgn * proud, (z0 + z1) / 2)))
                    nrm.append(Vector((0, 0, 1)))
                else:
                    t = (abs(u) - 0.7) / 0.3
                    sx = 1 if u > 0 else -1
                    dd = d_face + sgn * t * wrap if sgn > 0 else d_face - t * wrap
                    xx = self.surface_x(dd, (z0 + z1) / 2) + proud * 0.6
                    # round the corner
                    w_corner = self.surface_x(d_face + sgn * 0.05, (z0 + z1) / 2) - 0.12
                    ang = t * math.pi * 0.5
                    cx = w_corner + math.sin(ang) * (xx - w_corner)
                    yy = lerp(path[-1].y if path and abs(u) - 0.7 < 0.01 else self.Y(d_face) + sgn * proud,
                              self.Y(dd), 1 - math.cos(ang)) if False else None
                    hit, hn = self.project(tree, (sx * 2.0, self.Y(dd), (z0 + z1) / 2), (-sx, 0, 0))
                    yb = self.Y(d_face) + sgn * proud
                    y = lerp(yb, self.Y(dd), 1 - math.cos(ang))
                    path.append(Vector((sx * cx, y, (z0 + z1) / 2)))
                    nrm.append(Vector((0, 0, 1)))
            h = (z1 - z0) / 2
            # black urethane bumpers stand out; body-colour ones sit nearly flush
            bul = 0.04 if mname != "Paint" else 0.014
            prof = [(-0.03, -h), (bul * 0.75, -h + 0.01), (bul, 0), (bul * 0.75, h - 0.01), (-0.03, h)]
            if sgn < 0:
                prof = [(-u, v) for u, v in reversed(prof)]
            bm = bmesh.new()
            sweep(bm, path, prof, normals=nrm)
            ob = new_obj(key, bm, [self.M[mname]])
            flip_outward_obj(ob)
            subdivide(ob, 1)
            shade(ob, 50)
            self.parts.append(ob)
            self.bumpers.append(ob)
        tree = self.bvh(self.bumpers)

        # ---- front: grille, turn signals, fixed lamps
        for item in s.get("front", []):
            self.front_item(tree, item)
        for item in s.get("rear", []):
            self.front_item(tree, item)
        # ---- side: door shut lines, handles, mirrors, side markers
        for sx in (-1, 1):
            for (d0, d1, z0, z1) in s.get("shut_lines", []):
                # thin dark grooves
                if abs(d1 - d0) < 0.02:
                    self.panel(tree, "shut", sx, d0 - 0.003, d0 + 0.003, z0, z1, "Trim", 0.0015, 1, 8)
                else:
                    self.panel(tree, "shut", sx, d0, d1, z0 - 0.003, z0 + 0.003, "Trim", 0.0015, 8, 1)
            hd = s.get("handle")
            if hd:
                self.panel(tree, "handle", sx, hd[0], hd[0] + 0.16, hd[1], hd[1] + 0.035, "Trim", 0.006, 4, 1, 0.012, 0.004)
            sm = s.get("side_marker")
            if sm:
                self.panel(tree, "marker", sx, sm[0], sm[0] + 0.07, sm[1], sm[1] + 0.03, "Amber", 0.004, 2, 1, 0.006)
            for st in s.get("stripes", []):
                d0, d1, z0, z1, mname = st
                self.panel(tree, "stripe", sx, d0, d1, z0, z1, mname, 0.0025, 40, 1)
            self.mirror(tree, sx)
            lv = s.get("livery")
            if lv:
                for (txt, d, z, size) in lv:
                    self.text_decal(tree, txt, sx, d, z, size)
        # ---- plates
        pf = s.get("plate_f")
        if pf:
            self.plate(tree, pf, "F")
        pr = s.get("plate_r")
        if pr:
            self.plate(tree, pr, "B")
        # ---- wipers, antenna, exhaust, wing
        self.wipers(tree)
        self.antenna(tree)
        self.hoops(tree)
        self.wing(tree)
        self.exhaust()
        self.interior()

    def front_item(self, tree, item):
        kind, face = item[0], item[1]
        x0, x1, z0, z1, mname = item[2:7]
        opts = item[7] if len(item) > 7 else {}
        if kind == "disc":
            # round lamp: centre (x0, z0), radius x1
            for sx in ((1, -1) if opts.get("mirror", True) else (1,)):
                cx, r = sx * x0, x1
                for rr, m, prd, th in ((r + 0.012, "Trim", 0.003, 0.006), (r, mname, 0.008, 0.01)):
                    n = 20
                    verts = [(cx, z0)] + [(cx + rr * math.cos(math.tau * k / n), z0 + rr * math.sin(math.tau * k / n)) for k in range(n)]
                    faces = [(0, 1 + k, 1 + (k + 1) % n) for k in range(n)]
                    if face == "F":
                        fn = lambda uv: (uv[0], self.L, uv[1])
                        dirv = (0, -1, 0)
                    else:
                        fn = lambda uv: (uv[0], -self.L, uv[1])
                        dirv = (0, 1, 0)
                    ob = self.decal("disc", tree, verts, faces, fn, dirv, m, prd, th)
                    shade(ob, 50)
                    self.parts.append(ob)
            return
        mirror = opts.get("mirror", True)
        for sx in ((1, -1) if mirror else (1,)):
            xa, xb = (x0, x1) if sx > 0 else (-x1, -x0)
            if kind == "lamp":
                ob = self.panel(tree, "lamp", face, xa, xb, z0, z1, mname, opts.get("proud", 0.004), 10, 4,
                                opts.get("thick", 0.012), opts.get("round", 0.006))
            elif kind == "slats":
                n = opts.get("n", 3)
                for k in range(n):
                    za = lerp(z0, z1, k / n)
                    zb = za + (z1 - z0) / n * 0.45
                    self.panel(tree, "slat", face, xa, xb, za, zb, mname, opts.get("proud", 0.006), 10, 1, 0.01, 0.003)
            elif kind == "headlamp":
                # black housing slightly larger than the lens, lens standing proud in it
                self.panel(tree, "hlh", face, xa - 0.012, xb + 0.012, z0 - 0.012, z1 + 0.012, "Trim", 0.003, 10, 4, 0.006, 0.004)
                self.panel(tree, "hl", face, xa, xb, z0, z1, mname, 0.008, 10, 4, 0.01, 0.005)
            elif kind == "panel":
                self.panel(tree, "pnl", face, xa, xb, z0, z1, mname, opts.get("proud", 0.003), 10, 3,
                           opts.get("thick", 0.0), opts.get("round", 0.0))

    def plate(self, tree, p, face):
        x, z = p
        self.panel(tree, "plate", face, -0.165, 0.165, z - 0.08 if face == "B" else z - 0.055,
                   z + 0.08 if face == "B" else z + 0.055, "Plate", 0.012, 4, 2, 0.008, 0.004)
        txt = self.s.get("plate_text", "13-24")
        h = 0.11 if face == "B" else 0.075
        # plate characters, readable from behind / in front
        cu = bpy.data.curves.new("ptxt", "FONT")
        cu.body = txt
        cu.font = bpy.data.fonts.load(JP_FONT, check_existing=True)
        cu.size = h * 0.55
        cu.align_x = "CENTER"
        cu.align_y = "CENTER"
        tob = bpy.data.objects.new("ptxt", cu)
        bpy.context.scene.collection.objects.link(tob)
        dg = bpy.context.evaluated_depsgraph_get()
        me = bpy.data.meshes.new_from_object(tob.evaluated_get(dg))
        bpy.data.objects.remove(tob)
        bm = bmesh.new()
        bm.from_mesh(me)
        bmesh.ops.triangulate(bm, faces=bm.faces[:])
        uv = [(v.co.x, v.co.y) for v in bm.verts]
        faces = [[v.index for v in f.verts] for f in bm.faces]
        bm.free()
        bpy.data.meshes.remove(me)
        if face == "F":
            fn = lambda q: (-q[0], self.L, z - h * 0.12 + q[1])
            dirv = (0, -1, 0)
        else:
            fn = lambda q: (q[0], -self.L, z - h * 0.12 + q[1])
            dirv = (0, 1, 0)
        ob = self.decal("plate_txt", tree, uv, faces, fn, dirv, "Interior", 0.0215)
        # hold the text just in front of the plate
        self.parts.append(ob)

    def mirror(self, tree, sx):
        """Door mirror: black sail plate set into the window corner, head on a short arm."""
        s = self.s
        m = s.get("mirror")
        if not m:
            return
        d, z = m
        belt = self.st(d)[2]
        # sail: triangle filling the front lower corner of the side window
        tri = [(d - 0.05, belt + 0.015), (d + 0.10, belt + 0.015), (d - 0.05 + min(s.get("a_run", 0.12), 0.08), belt + 0.11)]
        fn = lambda uv: (sx * 2.0, self.Y(uv[0]), uv[1])
        sail = self.decal("sail", tree, tri, [(0, 1, 2)], fn, (-sx, 0, 0), "Trim", 0.002, 0.014)
        shade(sail, 40)
        self.parts.append(sail)
        # head: rounded wedge mounted straight onto the sail plate (no visible arm)
        hit, n = self.project(tree, (sx * 2.0, self.Y(d + 0.02), belt + 0.06), (-sx, 0, 0))
        x0 = abs(hit.x) + 0.012 if hit else self.surface_x(d, belt) - 0.02
        hw, hd, hh = s.get("mirror_size", (0.13, 0.085, 0.115))
        bm = bmesh.new()
        # inner face buried 1.5 cm into the sail, outer end slightly narrower (wedge)
        xi, xo = x0 - 0.015, x0 + hw
        yc = self.Y(d + 0.03)
        zc = z
        quad = []
        for xx, sc in ((xi, 1.0), (xo, 0.82)):
            for dy, dz in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
                quad.append(bm.verts.new((sx * xx, yc + dy * hd * 0.5 * sc + (0.012 if xx == xo else 0), zc + dz * hh * 0.5 * sc)))
        idx = [(0, 1, 2, 3), (7, 6, 5, 4), (0, 4, 5, 1), (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 4, 0)]
        for q in idx:
            bm.faces.new([quad[i] for i in q])
        flip_outward(bm)
        ob = new_obj("mirror", bm, [self.M[s.get("mirror_mat", "Trim")]])
        bevel(ob, 0.022, 4, 25)
        shade(ob, 55)
        self.parts.append(ob)
        bm = bmesh.new()
        box_bm(bm, Vector((sx * (x0 + hw * 0.5), yc - hd * 0.5 + 0.004, zc)), (hw - 0.04, 0.004, hh - 0.04), 0)
        self.parts.append(new_obj("mirror_glass", bm, [self.M["Chrome"]]))

    def antenna(self, tree):
        s = self.s
        an = s.get("antenna")
        if not an:
            return
        d, sx = an
        belt = self.st(d)[2]
        hit, n = self.project(tree, (sx * 2.0, self.Y(d), belt + 0.005), (-sx, 0, 0))
        if hit is None:
            return
        bm = bmesh.new()
        base = hit + Vector((sx * 0.004, 0, 0))
        top = base + Vector((sx * 0.02, -0.18, 0.72))
        c = bmesh.ops.create_cone(bm, cap_ends=True, segments=8, radius1=0.016, radius2=0.012, depth=0.03)
        bmesh.ops.translate(bm, verts=c["verts"], vec=base + Vector((0, 0, 0.01)))
        sweep(bm, [base, top], [(0.0025 * math.cos(a), 0.0025 * math.sin(a)) for a in [k * math.tau / 6 for k in range(6)]],
              normals=[Vector((1, 0, 0))] * 2)
        ob = new_obj("antenna", bm, [self.M["Chrome"]])
        self.parts.append(ob)

    def wipers(self, tree):
        """Wiper arms pivot on the cowl; blades rest on the glass along its lower edge,
        every point projected onto the curved windscreen so nothing floats."""
        s = self.s
        g0 = s["glass"][0]
        bm = bmesh.new()
        for x0, length in s.get("wipers", ((-0.5, 0.46), (0.06, 0.46))):
            # blade: 12 points along the glass, 6 mm above it
            pts, nrm = [], []
            for k in range(12):
                x = x0 + 0.03 + length * k / 11
                hit, n = self.project(tree, (x, self.Y(g0 + 0.085 + 0.02 * k / 11), 3.0), (0, 0, -1))
                if hit is None:
                    continue
                pts.append(hit + n * 0.007)
                nrm.append(n)
            if len(pts) > 2:
                sweep(bm, pts, [(-0.008, -0.005), (0.008, -0.005), (0.006, 0.006), (-0.006, 0.006)], normals=nrm)
            # arm: from the pivot on the cowl to the middle of the blade, resting just on top of it
            hp, hn = self.project(tree, (x0, self.Y(g0 - 0.03), 3.0), (0, 0, -1))
            if hp is None or len(pts) < 6:
                continue
            mid = pts[6] + nrm[6] * 0.009
            arm = [hp + hn * 0.012]
            for k in range(1, 6):
                t = k / 5
                q = arm[0].lerp(mid, t)
                h2, n2 = self.project(tree, (q.x, q.y, 3.0), (0, 0, -1))
                if h2 is not None:
                    q = h2 + n2 * (0.016 - 0.007 * t)
                arm.append(q)
            sweep(bm, arm, [(-0.006, -0.004), (0.006, -0.004), (0.006, 0.004), (-0.006, 0.004)], normals=[Vector((0, 0, 1))] * len(arm))
            # pivot cap sits on the cowl
            c = bmesh.ops.create_cone(bm, cap_ends=True, segments=12, radius1=0.018, radius2=0.014, depth=0.02)
            bmesh.ops.translate(bm, verts=c["verts"], vec=hp + hn * 0.006)
        ob = new_obj("wipers", bm, [self.M["Trim"]])
        flip_outward_obj(ob)
        shade(ob, 50)
        self.parts.append(ob)

    def wing(self, tree):
        """Spoilers sit on the panel: every point of the base is projected onto the body."""
        s = self.s
        wg = s.get("wing")
        if not wg:
            return
        kind = wg[0]
        bm = bmesh.new()
        d = wg[1] if len(wg) > 1 and wg[1] else s["roof"][1] + 0.02
        bot, crease, belt, top, w, rw = self.st(d)
        span = (rw - 0.16) if kind == "roof" else (w - 0.09)
        surf = []
        for k in range(13):
            x = lerp(-span, span, k / 12)
            hit, n = self.project(tree, (x, self.Y(d), 3.0), (0, 0, -1))
            if hit is not None:
                surf.append(hit)
        # drop points that landed off the panel (pillars, glass edges)
        zs = sorted(p.z for p in surf)
        med = zs[len(zs) // 2]
        surf = [p for p in surf if abs(p.z - med) < 0.05]
        if kind in ("lip", "roof", "duck"):
            hgt = wg[2] if len(wg) > 2 else 0.04
            chord = wg[3] if len(wg) > 3 else 0.12
            nrm = [Vector((0, 0, 1))] * len(surf)
            # wedge profile rising from the surface, trailing edge at the back
            prof = [(chord * 0.25, -0.012), (chord * 0.3, 0.008), (0.0, hgt), (-chord * 0.7, hgt * 0.75),
                    (-chord * 0.75, hgt * 0.3), (-chord * 0.6, -0.012)]
            sweep(bm, surf, prof, normals=nrm)
        elif kind == "big":
            hgt, chord = wg[2], wg[3]
            zt = max(p.z for p in surf) + hgt
            path = [Vector((p.x, p.y, zt)) for p in surf]
            prof = [(chord * 0.5, -0.01), (chord * 0.52, 0.004), (chord * 0.4, 0.018), (-chord * 0.2, 0.024),
                    (-chord * 0.5, 0.016 + chord * 0.12), (-chord * 0.5, chord * 0.1), (0.0, -0.008)]
            sweep(bm, path, prof)
            for sx in (-1, 1):
                xx = sx * span * 0.68
                hit, n = self.project(tree, (xx, self.Y(d), 3.0), (0, 0, -1))
                zb = hit.z - 0.01 if hit else zt - hgt
                box_bm(bm, Vector((xx, self.Y(d), (zt + zb) / 2)), (0.03, chord * 0.5, zt - zb), 0)
                # endplates
                box_bm(bm, Vector((sx * (span + 0.004), self.Y(d), zt + 0.02)), (0.008, chord * 1.05, 0.1), 0)
        ob = new_obj("wing", bm, [self.M[wg[4] if len(wg) > 4 else "Paint"]])
        flip_outward_obj(ob)
        shade(ob, 45)
        self.parts.append(ob)

    def hoops(self, tree):
        """Roll hoops behind the seats (roadsters)."""
        h = self.s.get("hoops")
        if not h:
            return
        d, height = h
        belt = self.st(d)[2]
        bm = bmesh.new()
        for sx in (-1, 1):
            cx = sx * 0.36
            path = []
            for k in range(13):
                a = math.pi * k / 12
                path.append(Vector((cx + 0.2 * math.cos(a), self.Y(d), belt - 0.02 + (height) * math.sin(a))))
            sweep(bm, path, [(0.022 * math.cos(t), 0.022 * math.sin(t)) for t in [k * math.tau / 8 for k in range(8)]],
                  normals=[Vector((0, 1, 0))] * len(path))
        ob = new_obj("hoops", bm, [self.M["Chrome"]])
        flip_outward_obj(ob)
        shade(ob, 60)
        self.parts.append(ob)

    def exhaust(self):
        s = self.s
        ex = s.get("exhaust", (0.45, 0.3, 0.035))
        x, z, r = ex
        bm = bmesh.new()
        prof = [(r, -0.12), (r, 0.03), (r - 0.006, 0.03), (r - 0.006, -0.1), (0.0, -0.1)]
        lathe(bm, [(pr, px) for pr, px in prof], 16)
        bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(-math.pi / 2, 3, "Z"))
        bmesh.ops.translate(bm, verts=bm.verts, vec=(x, self.Y(self.L) - 0.02, z))
        ob = new_obj("exhaust", bm, [self.M["Chrome"]])
        flip_outward_obj(ob)
        shade(ob, 60)
        self.parts.append(ob)

    def interior(self):
        """Dark cabin shapes so the glass reads as a window with seats behind it."""
        s = self.s
        r0, r1 = s["roof"]
        bm = bmesh.new()
        dmid = (r0 + r1) * 0.5
        bot, crease, belt, top, w, rw = self.st(dmid)
        for sx in (-1, 1):
            # seat backs and headrests
            # kept well under the roof skin (headroom ~10 cm) so nothing pokes through
            box_bm(bm, Vector((sx * 0.36, self.Y(dmid + 0.05), belt + 0.02)), (0.42, 0.1, 0.38), 0)
            box_bm(bm, Vector((sx * 0.36, self.Y(dmid + 0.04), belt + 0.26)), (0.22, 0.09, 0.12), 0)
        # steering wheel (right-hand drive)
        g0 = s["glass"][0]
        sw = bmesh.ops.create_cone(bm, cap_ends=False, segments=20, radius1=0.19, radius2=0.19, depth=0.03)
        bmesh.ops.rotate(bm, verts=sw["verts"], cent=(0, 0, 0), matrix=Matrix.Rotation(math.radians(70), 3, "X"))
        bmesh.ops.translate(bm, verts=sw["verts"], vec=(0.36, self.Y(g0 + 0.55), belt + 0.08))
        # dash
        box_bm(bm, Vector((0, self.Y(g0 + 0.25), belt - 0.03)), (2 * w - 0.25, 0.4, 0.14), 0)
        ob = new_obj("interior", bm, [self.M["Interior"]])
        self.parts.append(ob)

    def underside(self):
        # dark floor so the ground never shows through the arches
        s = self.s
        bm = bmesh.new()
        bot = self.st(self.L * 0.5)[0]
        box_bm(bm, Vector((0, 0, bot + 0.02)), (2 * self.st(self.L * 0.5)[4] - 0.2, self.L - 0.5, 0.03), 0)
        for i, d in enumerate(self.wheel_d):
            # inner wheel-well liners
            tr = s["track"][i] * 0.5
            for sx in (-1, 1):
                box_bm(bm, Vector((sx * (tr - 0.2), self.Y(d), self.tire_r + 0.05)), (0.02, 0.75, 0.6), 0)
        ob = new_obj("floor", bm, [self.M["Well"]])
        self.parts.append(ob)

    # ---------------------------------------------------------- pop-ups
    def popups(self, tree):
        """Pop-up lamps hinged at the rear edge of the lid, exported OPEN.
        Open: the lid tips up at the front and a black wedge housing carries a
        framed lens on its vertical front face. The game rotates each unit down
        about its hinge by the angle stored in the child node name
        ("lens_<tenths of a degree>") until the lid lies flush in the hood."""
        s = self.s
        pu = s.get("popup")
        if not pu:
            return []
        d0, d1, x0, x1 = pu["d0"], pu["d1"], pu["x0"], pu["x1"]
        beta = math.radians(pu.get("tilt", 24.0))      # lid angle above horizontal when open
        out = []
        nu, nv = 10, 8
        faces = [(j * (nu + 1) + i, j * (nu + 1) + i + 1, (j + 1) * (nu + 1) + i + 1, (j + 1) * (nu + 1) + i)
                 for j in range(nv) for i in range(nu)]
        down = lambda uv: (uv[0], self.Y(uv[1]), 3.0)
        for sx, name in ((1, "Popup_R"), (-1, "Popup_L")):
            xa, xb = (x0, x1) if sx > 0 else (-x1, -x0)
            cx = (xa + xb) / 2
            hH, _ = self.project(tree, (cx, self.Y(d1), 3.0), (0, 0, -1))
            hF, _ = self.project(tree, (cx, self.Y(d0), 3.0), (0, 0, -1))
            H = Vector((0, hH.y, hH.z))                       # hinge line (x varies)
            alpha = math.atan2(hH.z - hF.z, hF.y - hH.y)       # hood slope, front lower
            theta = alpha + beta                               # open angle from flush
            R = Matrix.Translation(H) @ Matrix.Rotation(theta, 4, "X") @ Matrix.Translation(-H)
            # lid: the hood corner panel itself, 12 mm thick, swung open about the hinge
            grid = [(lerp(xa, xb, i / nu), lerp(d0, d1, j / nv)) for j in range(nv + 1) for i in range(nu + 1)]
            lid = self.decal(name, tree, grid, faces, down, (0, 0, -1), "Paint", 0.0015, 0.012)
            bevel(lid, 0.003, 1, 30)
            lid.data.transform(R)
            # open-state geometry in the side plane (y, z)
            ln = hF.y - hH.y
            fy = H.y + ln * math.cos(beta)                     # lid front edge
            fz = H.z + ln * math.sin(beta)
            fz_bot = hF.z - 0.03                               # front face reaches just under the hood
            inset = 0.012
            bm = bmesh.new()
            prof = [(H.y - 0.005, H.z - 0.012), (fy - 0.004, fz - 0.004), (fy - 0.004, fz_bot), (H.y + 0.02, H.z - 0.05)]
            ring = []
            for xx in (xa + inset, xb - inset):
                ring.append([bm.verts.new((xx, py, pz)) for py, pz in prof])
            bm.faces.new(ring[0])
            bm.faces.new(list(reversed(ring[1])))
            for k in range(4):
                bm.faces.new((ring[0][k], ring[1][k], ring[1][(k + 1) % 4], ring[0][(k + 1) % 4]))
            flip_outward(bm)
            hous = new_obj("housing", bm, [self.M["Trim"]])
            bevel(hous, 0.005, 2, 30)
            # framed lens on the vertical front face, in the part that shows above the hood
            vis_lo, vis_hi = hF.z + 0.012, fz - 0.016
            lz = (vis_lo + vis_hi) / 2
            lw = abs(xb - xa) - 2 * inset - pu.get("frame", 0.05)
            lh = min(vis_hi - vis_lo - 0.02, lw * pu.get("aspect", 0.86))
            yf = fy - 0.004
            bm = bmesh.new()
            fw = 0.012
            for (bx, bz, sw, shh) in ((cx, lz + lh / 2 + fw / 2, lw + 2 * fw, fw), (cx, lz - lh / 2 - fw / 2, lw + 2 * fw, fw),
                                      (cx - lw / 2 - fw / 2, lz, fw, lh), (cx + lw / 2 + fw / 2, lz, fw, lh)):
                box_bm(bm, Vector((bx, yf + 0.006, bz)), (sw, 0.014, shh), 0)
            bez = new_obj("bezel", bm, [self.M["Trim"]])
            bevel(bez, 0.003, 1, 30)
            bm = bmesh.new()
            box_bm(bm, Vector((cx, yf + 0.002, lz)), (lw, 0.016, lh), 0)
            lens = new_obj("lens", bm, [self.M["Lens"]])
            bevel(lens, 0.004, 2, 30)
            bm = bmesh.new()
            for k in (-1, 1):
                box_bm(bm, Vector((cx, yf + 0.0105, lz + k * lh * 0.2)), (lw * 0.85, 0.002, 0.004), 0)
            ribs = new_obj("ribs", bm, [self.M["Chrome"]])
            join_into(lid, [hous, bez, lens, ribs])
            # origin on the hinge
            org = Vector((cx, H.y, H.z))
            lid.data.transform(Matrix.Translation(-org))
            lid.location = org
            shade(lid, 40)
            # marker child: lens position + closing angle
            emp = bpy.data.objects.new("lens_%d" % round(math.degrees(theta) * 10), None)
            bpy.context.scene.collection.objects.link(emp)
            emp.parent = lid
            emp.location = Vector((cx, yf + 0.01, lz)) - org
            out.append(lid)
            out.append(emp)
            # shut line around the lid opening (stays on the body)
            e = 0.004
            for (ua, ub, va, vb) in ((xa - e, xb + e, d0 - e, d0), (xa - e, xb + e, d1, d1 + e),
                                     (xa - e, xa, d0, d1), (xb, xb + e, d0, d1)):
                g = [(lerp(ua, ub, i / 6), lerp(va, vb, j / 1)) for j in range(2) for i in range(7)]
                f = [(i, i + 1, i + 8, i + 7) for i in range(6)]
                self.parts.append(self.decal("shut", tree, g, f, down, (0, 0, -1), "Trim", 0.0008))
        return out

    # ---------------------------------------------------------- wheels
    def wheel(self, name, i, sx):
        s = self.s
        R = self.tire_r
        rim_r = s.get("rim_in", 13) * 0.0254 * 0.5
        wdt = s.get("tire_w", 0.185)
        hw = wdt * 0.5
        bm = bmesh.new()
        # tyre section: tread, shoulders, bulging sidewall into the bead (x = across the tyre)
        prof = []
        prof.append((rim_r + 0.006, -hw + 0.01))
        for k in range(7):
            a = k / 6
            prof.append((lerp(rim_r + 0.012, R - 0.03, a), -hw - 0.012 * math.sin(a * math.pi)))
        for k in range(5):
            a = math.pi * 0.5 * (1 - k / 4)
            prof.append((R - 0.03 + 0.03 * math.cos(a) , -hw + 0.03 - 0.03 * math.sin(a)))
        for k in range(1, 9):
            prof.append((R + 0.002 * (1 - abs(k / 4.5 - 1)), lerp(-hw + 0.03, hw - 0.03, k / 9)))
        for k in range(5):
            a = math.pi * 0.5 * k / 4
            prof.append((R - 0.03 + 0.03 * math.cos(a), hw - 0.03 + 0.03 * math.sin(a)))
        for k in range(1, 7):
            a = k / 6
            prof.append((lerp(R - 0.03, rim_r + 0.012, a), hw + 0.012 * math.sin((1 - a) * math.pi)))
        prof.append((rim_r + 0.006, hw - 0.01))
        lathe(bm, prof, 48, lambda j: 0)
        tire = new_obj(name, bm, [self.M["Tire"]])
        flip_outward_obj(tire)
        # tread grooves as dark bands
        bm = bmesh.new()
        for gx in (-hw * 0.45, 0.0, hw * 0.45):
            lathe(bm, [(R + 0.0015, gx - 0.006), (R + 0.0015, gx + 0.006)], 48)
        gro = new_obj("groove", bm, [self.M["Well"]])
        # rim: barrel, polished lip, spoke face
        style = s.get("rim_style", ("spokes", 8))
        bm = bmesh.new()
        face_x = hw - 0.025 - s.get("dish", 0.02)
        lip_x = hw - 0.012
        barrel = [(rim_r - 0.005, -hw + 0.02), (rim_r - 0.005, face_x - 0.01), (rim_r - 0.01, face_x - 0.005)]
        lathe(bm, barrel, 40)
        rim_parts = new_obj("barrel", bm, [self.M["Rim"]])
        bm = bmesh.new()
        lip = [(rim_r - 0.012, face_x - 0.004), (rim_r - 0.004, lip_x - 0.004), (rim_r + 0.012, lip_x), (rim_r + 0.014, lip_x - 0.008), (rim_r + 0.006, lip_x - 0.016)]
        lathe(bm, lip, 48)
        lipo = new_obj("lip", bm, [self.M["RimLip"]])
        bm = bmesh.new()
        kind = style[0]
        n = style[1]
        hub_r = 0.065
        inner = rim_r - 0.014
        if kind == "spokes" or kind == "mesh":
            for k in range(n):
                a = math.tau * k / n
                for sub in ((0.0,) if kind == "spokes" else (-0.12, 0.12)):
                    aa = a + sub
                    dirv = Vector((0, math.cos(aa), math.sin(aa)))
                    perp = Vector((0, -math.sin(aa), math.cos(aa)))
                    r_in, r_out = hub_r - 0.005, inner
                    w_in, w_out = s.get("spoke_w", (0.026, 0.018))
                    if kind == "mesh":
                        w_in, w_out = 0.01, 0.008
                    pts = []
                    for rr, ww, xx in ((r_in, w_in, face_x + 0.012), (r_out, w_out, face_x - 0.004)):
                        for side in (-1, 1):
                            for dx in (0.0, -0.018):
                                pts.append(Vector((xx + dx, 0, 0)) + dirv * rr + perp * side * ww * 0.5)
                    vs = [bm.verts.new(p) for p in pts]
                    # vs: [in-l-front, in-l-back, in-r-front, in-r-back, out-l-front, out-l-back, out-r-front, out-r-back]
                    quads = [(0, 2, 6, 4), (1, 5, 7, 3), (0, 4, 5, 1), (2, 3, 7, 6), (4, 6, 7, 5), (0, 1, 3, 2)]
                    for q in quads:
                        bm.faces.new([vs[j] for j in q])
        elif kind == "dish":
            # flat dish face with n round holes suggested by dark circles (steelies / turbine)
            disk = [(0.0, face_x + 0.006), (inner, face_x - 0.004)]
            lathe(bm, disk, 40)
        elif kind == "fivespoke":
            for k in range(5):
                a = math.tau * k / 5
                dirv = Vector((0, math.cos(a), math.sin(a)))
                perp = Vector((0, -math.sin(a), math.cos(a)))
                pts = []
                for rr, ww, xx in ((hub_r - 0.005, 0.05, face_x + 0.014), (inner, 0.075, face_x - 0.004)):
                    for side in (-1, 1):
                        for dx in (0.0, -0.02):
                            pts.append(Vector((xx + dx, 0, 0)) + dirv * rr + perp * side * ww * 0.5)
                vs = [bm.verts.new(p) for p in pts]
                for q in [(0, 2, 6, 4), (1, 5, 7, 3), (0, 4, 5, 1), (2, 3, 7, 6), (4, 6, 7, 5), (0, 1, 3, 2)]:
                    bm.faces.new([vs[j] for j in q])
        # hub with lug nuts and centre cap
        hub = [(0.0, face_x + 0.03), (0.035, face_x + 0.028), (hub_r, face_x + 0.016), (hub_r, face_x - 0.01)]
        lathe(bm, hub, 24)
        flip_outward(bm)
        spokes = new_obj("spokes", bm, [self.M["Rim"]])
        bm = bmesh.new()
        nl = s.get("lugs", 4)
        for k in range(nl):
            a = math.tau * k / nl + 0.3
            c = bmesh.ops.create_cone(bm, cap_ends=True, segments=6, radius1=0.009, radius2=0.009, depth=0.016)
            bmesh.ops.rotate(bm, verts=c["verts"], cent=(0, 0, 0), matrix=Matrix.Rotation(math.pi / 2, 3, "Y"))
            bmesh.ops.translate(bm, verts=c["verts"], vec=(face_x + 0.022, math.cos(a) * 0.05, math.sin(a) * 0.05))
        # brake disc and caliper behind the spokes
        disc = bmesh.ops.create_cone(bm, cap_ends=True, segments=32, radius1=rim_r - 0.035, radius2=rim_r - 0.035, depth=0.02)
        bmesh.ops.rotate(bm, verts=disc["verts"], cent=(0, 0, 0), matrix=Matrix.Rotation(math.pi / 2, 3, "Y"))
        bmesh.ops.translate(bm, verts=disc["verts"], vec=(-0.02, 0, 0))
        lugs = new_obj("lugs", bm, [self.M["Chrome"]])
        join_into(tire, [gro, rim_parts, lipo, spokes, lugs])
        shade(tire, 35)
        # mirror the wheel for the left side so the face points outward
        if sx < 0:
            tire.data.transform(Matrix.Scale(-1, 4, (1, 0, 0)))
            tire.data.flip_normals()
        d = self.wheel_d[i]
        tire.location = (sx * s["track"][i] * 0.5, self.Y(d), R)
        tire.name = name
        return tire

    # ---------------------------------------------------------- assemble
    def build(self):
        self.build_shell()
        self.assign_regions()
        self.cut_arches()
        shade(self.shell, 34)
        self.build_details()
        tree = self.bvh()
        pops = self.popups(tree)
        body = self.shell
        join_into(body, self.parts)
        body.name = "Body"
        wheels = [self.wheel("Wheel_FL", 0, -1), self.wheel("Wheel_FR", 0, 1),
                  self.wheel("Wheel_RL", 1, -1), self.wheel("Wheel_RR", 1, 1)]
        return body, wheels, pops


def flip_outward_obj(ob):
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    flip_outward(bm)
    bm.to_mesh(ob.data)
    bm.free()


def join_into(target, others):
    others = [o for o in others if o is not None and o != target]
    if not others:
        return
    for o in bpy.context.scene.objects:
        o.select_set(False)
    for o in others:
        o.select_set(True)
    target.select_set(True)
    bpy.context.view_layer.objects.active = target
    with bpy.context.temp_override(active_object=target, selected_editable_objects=others + [target], object=target):
        bpy.ops.object.join()


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def render(path, cid, pops=()):
    """Cycles studio render, lights-on version: pop-ups raised, lamps lit."""
    scn = bpy.context.scene
    for name, strength in (("Lens", 30.0), ("Tail", 8.0), ("Amber", 3.0)):
        bsdf = bpy.data.materials[name].node_tree.nodes["Principled BSDF"]
        bsdf.inputs["Emission Strength"].default_value = strength
    # headlight beams
    for sx in (-1, 1):
        ld = bpy.data.lights.new("beam", "SPOT")
        ld.energy = 900
        ld.spot_size = math.radians(40)
        ld.color = (1.0, 0.95, 0.85)
        lo = bpy.data.objects.new("beam", ld)
        lo.location = (sx * 0.55, 2.2, 0.75)
        lo.rotation_euler = (math.radians(80), 0, 0)
        scn.collection.objects.link(lo)
    scn.render.engine = "CYCLES"
    scn.cycles.samples = 48
    scn.cycles.device = "CPU"
    scn.render.resolution_x = 1280
    scn.render.resolution_y = 720
    scn.render.film_transparent = False
    world = bpy.data.worlds.new("w")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.18, 0.05, 0.05, 1)
    world.node_tree.nodes["Background"].inputs[1].default_value = 0.35
    scn.world = world
    # floor
    bpy.ops.mesh.primitive_plane_add(size=40)
    fl = bpy.context.active_object
    fm = bpy.data.materials.new("floor")
    fm.use_nodes = True
    fm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.25, 0.06, 0.05, 1)
    fl.data.materials.append(fm)
    for loc, en in (((4, 5, 6), 900), ((-5, -3, 4), 450), ((0, -6, 3), 250)):
        ld = bpy.data.lights.new("l", "AREA")
        ld.energy = en
        ld.size = 4
        lo = bpy.data.objects.new("l", ld)
        lo.location = loc
        lo.rotation_euler = (Vector((0, 0, 0)) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
        scn.collection.objects.link(lo)
    views = [("front34", (3.6, 4.4, 1.5)), ("rear34", (-3.4, -4.6, 1.6)), ("side", (6.0, 0.0, 0.9)), ("front", (0.0, 6.5, 0.9))]
    want = os.environ.get("CAR_VIEWS")
    if want:
        views = [v for v in views if v[0] in want.split(",")]
    cam_d = bpy.data.cameras.new("c")
    cam_d.lens = 50
    cam = bpy.data.objects.new("cam", cam_d)
    scn.collection.objects.link(cam)
    scn.camera = cam
    base, ext = os.path.splitext(path)
    for vname, loc in views:
        cam.location = loc
        cam.rotation_euler = (Vector((0, 0, 0.55)) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
        scn.render.filepath = f"{base}_{vname}{ext}"
        bpy.ops.render.render(write_still=True)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else ["ae86"]
    cid = argv[0]
    reset_scene()
    car = Car(cid)
    body, wheels, pops = car.build()
    out_dir = os.path.join(ROOT, "cars")
    os.makedirs(out_dir, exist_ok=True)
    out = os.path.join(out_dir, cid + ".glb")
    for o in bpy.context.scene.objects:
        o.select_set(o in [body] + wheels + pops)
    bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=True, export_apply=True,
                              export_yup=True, export_materials="EXPORT", export_normals=True)
    tris = sum(len(p.vertices) - 2 for o in [body] + wheels + pops if o.data for p in o.data.polygons)
    print(f"[car] {cid}: exported {out} ({tris} tris)")
    if "--render" in argv:
        render(argv[argv.index("--render") + 1], cid, pops)


if __name__ == "__main__":
    main()
