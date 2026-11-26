extends Node
## Inspector: builds every course as the game does and reports anything that
## is where it should not be: ground over the road or under a wall face,
## trees and bushes in the road or off the ground, objects standing in the
## carriageway, buried in the hillside or hanging in the air.
## Run: godot --rendering-driver vulkan tests/placement_check.tscn [-- <course index>]

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var only := int(args[0]) if args.size() > 0 else -1
	var total := 0
	var courses := Courses.all()
	for ci in courses.size():
		if only >= 0 and ci != only:
			continue
		Mats.crowd = true
		var t := Track.new()
		add_child(t)
		t.build(courses[ci])
		await get_tree().process_frame
		var found := inspect(t)
		var n := 0
		for k in found:
			n += (found[k] as Array).size()
		total += n
		print("[check] %-18s %d problems" % [courses[ci].name, n])
		for k in found:
			var list: Array = found[k]
			if list.is_empty():
				continue
			print("[check]     %-34s %4d   e.g. %s" % [k, list.size(), "  ".join(list.slice(0, 4))])
		t.queue_free()
		await get_tree().process_frame
	print("[check] TOTAL ", total)
	get_tree().quit(1 if total > 0 else 0)


func _tag(n: GeometryInstance3D, mesh: Mesh) -> String:
	var m: Material = n.material_override if n.material_override else (mesh.surface_get_material(0) if mesh.get_surface_count() > 0 else null)
	if m is ShaderMaterial and m.shader:
		return m.shader.resource_path.get_file().get_basename()
	if m is StandardMaterial3D:
		return "#" + (m.albedo_color as Color).to_html(false) + ("/" + m.albedo_texture.resource_path.get_file().get_basename() if m.albedo_texture else "")
	return "?"


var _vert_cache := {}


## A thinned set of a mesh's points (enough to find how far it spreads).
func _verts(mesh: Mesh) -> PackedVector3Array:
	if not _vert_cache.has(mesh):
		var faces := mesh.get_faces()
		var pts := PackedVector3Array()
		for k in range(0, faces.size(), maxi(1, faces.size() / 400)):
			pts.append(faces[k])
		_vert_cache[mesh] = pts
	return _vert_cache[mesh]


func inspect(t: Track) -> Dictionary:
	var out := {"ground over road / under wall face": [], "step in the road surface": [], "plant in the road": [], "plant in a wall": [], "plant off the ground": [], "plant buried": [],
		"tree or bush over the rail line": [], "object in the carriageway": [], "object buried in the hillside": [], "object in the air": []}
	if not t.terrain_h.is_empty():
		for f in t.terrain_faults():
			out["ground over road / under wall face"].append("s=%d %s" % [int(f[0]), f[1]])
	# the road surface itself: no sudden steps
	for i in range(1, t.P.size() - 1):
		var dev := absf(t.P[i].y - (t.P[i - 1].y + t.P[i + 1].y) * 0.5)
		if dev > 0.12:
			out["step in the road surface"].append("s=%d %.2fm" % [int(t.S[i]), dev])
	var has_ground := not t.terrain_h.is_empty()
	# the foot of each small object: lowest point of anything standing within a few metres
	var lowest := {}
	var all := t.find_children("*", "GeometryInstance3D", true, false)
	for n in all:
		if n is MeshInstance3D and n.mesh and not _tag(n, n.mesh).begins_with("terrain"):
			var ab0: AABB = n.global_transform * n.mesh.get_aabb()
			if maxf(ab0.size.x, ab0.size.z) < 16.0:
				var key := Vector2i(floori(ab0.get_center().x / 2.5), floori(ab0.get_center().z / 2.5))
				lowest[key] = minf(float(lowest.get(key, 1.0e9)), ab0.position.y)
	for n in all:
		var g := n as GeometryInstance3D
		if g.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
			continue
		if g is MultiMeshInstance3D:
			var mm := (g as MultiMeshInstance3D).multimesh
			if mm == null or mm.mesh == null or g.visibility_range_begin > 1.0:
				continue          # (farther detail levels repeat the same places)
			var ab := mm.mesh.get_aabb()
			var tag := _tag(g, mm.mesh)
			var plant := tag.begins_with("foliage") or (ab.size.y > 0.25 and tag == "#80829a")
			if ab.size.y < 0.25:
				continue          # flat things on the road surface: studs, lids
			for k in mm.instance_count:
				var x := g.global_transform * mm.get_instance_transform(k)
				var o := x.origin
				var d := t.dist_to_road(o)
				var i := t.nearest_index(o)
				var where := "s=%d" % int(t.S[i])
				if d < t.hw + 0.2 and absf(o.y - t.P[i].y) < 4.0 and not t.in_tunnel(i):
					out["plant in the road" if plant else "object in the carriageway"].append(where + " " + tag)
				if plant:
					var w_side := 1 if (o - t.P[i]).dot(t.R[i]) > 0.0 else -1
					var w_reach := float(t.wall_reach.get(Vector2i(i, w_side), 0.0))
					if w_reach > 0.0 and d < t.rail + w_reach + 0.2 and absf(o.y - t.P[i].y) < 12.0:
						out["plant in a wall"].append(where + " " + tag)
				if plant and tag.begins_with("foliage"):
					# measured on the real leaves and branches, not a box round them
					var over := 0.0
					for v in _verts(mm.mesh):
						var w: Vector3 = x * v
						# against every leg of the road at or below this leaf
						over = maxf(over, t.rail - t.road_clearance(w, w.y - 16.0, w.y + 0.5))
					if over > 0.05:
						out["tree or bush over the rail line"].append("%s by %.1fm" % [where, over])
				if not plant or not has_ground:
					continue
				var ground := t.terrain_height(o.x, o.z)
				if o.y > ground + 0.6:
					out["plant off the ground"].append("%s %.1fm up" % [where, o.y - ground])
				elif o.y < ground - 1.6:
					out["plant buried"].append("%s %.1fm under" % [where, ground - o.y])
		elif g is MeshInstance3D and (g as MeshInstance3D).mesh:
			var mesh := (g as MeshInstance3D).mesh
			var tag := _tag(g, mesh)
			if tag.begins_with("terrain") or tag.begins_with("outline"):
				continue
			if n.get_parent() == t and tag.ends_with("/asphalt"):
				continue          # the road surface itself
			var wab: AABB = g.global_transform * mesh.get_aabb()
			var small := maxf(wab.size.x, wab.size.z) < 16.0
			# anything solid standing in the driving space
			var hits := 0
			var hit_where := ""
			var faces := mesh.get_faces()
			var stride := maxi(1, faces.size() / 60000)
			for vi in range(0, faces.size(), stride):
				var v: Vector3 = g.global_transform * faces[vi]
				if t.dist_to_road(v) > t.rail - 0.5:
					continue          # (the camera rides inside this strip as well as the cars)
				var i := t.nearest_index(v)
				var up := v.y - t.P[i].y
				# at a hairpin the other leg of the road may be the nearer one on the
				# map: measure against whichever leg this point actually lies on
				for j in range(maxi(i - 70, 0), mini(i + 71, t.P.size()), 2):
					if Vector2(t.P[j].x - v.x, t.P[j].z - v.z).length() < t.hw + 0.6 and absf(v.y - t.P[j].y) < absf(up):
						up = v.y - t.P[j].y
				# (signs, wires and the road above at a stacked hairpin pass overhead from 4.4 m up)
				if up > 0.3 and up < 4.0 and not t.in_tunnel(i) and t.S[i] > 30.0:
					hits += 1
					hit_where = "s=%d (%.1fm across, %.1fm up)" % [int(t.S[i]), (v - t.P[i]).dot(t.R[i]), up]
			if hits > 0:
				out["object in the carriageway"].append("%s %s (%d points)" % [hit_where, tag, hits])
			if small and has_ground and wab.size.y > 0.6:
				var c := wab.get_center()
				var i := t.nearest_index(c)
				var dc := t.dist_to_road(c)
				if dc > t.rail + 1.2 and dc < 60.0 and not t.in_tunnel(i) and not t.bridge_idx.has(i) and not tag.begins_with("building"):
					var ground := t.terrain_height(c.x, c.z)
					var key := Vector2i(floori(c.x / 2.5), floori(c.z / 2.5))
					var foot := 1.0e9
					for dz in range(-1, 2):
						for dx in range(-1, 2):
							foot = minf(foot, float(lowest.get(key + Vector2i(dx, dz), 1.0e9)))
					if ground > wab.position.y + wab.size.y * 0.6 and ground > wab.position.y + 1.3:
						out["object buried in the hillside"].append("s=%d %s %.1fm deep" % [int(t.S[i]), tag, ground - wab.position.y])
					elif foot > ground + 1.0 and wab.size.y < 12.0:
						out["object in the air"].append("s=%d %s %.1fm up" % [int(t.S[i]), tag, foot - ground])
	return out
