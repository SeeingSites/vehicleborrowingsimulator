class_name City
extends Node3D
## Procedural GTA2-style city: grid of roads, raised sidewalks, building blocks with
## textured facades and roof clutter, parks and parking lots.

var P := Game.P
var parked_spots: Array = []   # [Vector3 pos, float yaw]
var block_kind := {}           # Vector2i -> "park" | "parking" | "buildings"
var r := RandomNumberGenerator.new()
var facade_mats := []
var roof_mats := []
var mm_white: PackedVector3Array
var dash_xf: Array[Transform3D] = []
var stripe_xf: Array[Transform3D] = []
# lamp_mats[group][axis_ns 0/1][light 0..2]
var lamp_mats := []
const LAMP_COLS := [Color(0.05, 0.95, 0.2), Color(1.0, 0.75, 0.0), Color(1.0, 0.0, 0.0)]

func build(seed_: int) -> void:
	r.seed = seed_
	for i in 6: facade_mats.append(Tex.mat_tex(Tex.facade(i), 6.0))
	for i in 5: roof_mats.append(Tex.mat_tex(Tex.roof(i), 8.0))
	var size := Game.NB * P
	# outer ground (grass/dirt) and road asphalt
	_box(Vector3(size * 0.5, -0.06, size * 0.5), Vector3(size + 200, 0.1, size + 200), Tex.mat_tex(Tex.grass(), 6.0, Color(0.8, 0.85, 0.7)), false)
	_box(Vector3(size * 0.5, -0.01, size * 0.5), Vector3(size + Game.ROAD_HALF * 2, 0.02, size + Game.ROAD_HALF * 2), Tex.mat_tex(Tex.asphalt(), 8.0), false)
	var walk_mat := Tex.mat_tex(Tex.sidewalk(), 4.0, Color(0.86, 0.84, 0.82))
	var curb := Tex.mat_col(Color(0.55, 0.53, 0.50))
	for bi in Game.NB:
		for bj in Game.NB:
			var c := Vector3((bi + 0.5) * P, 0.0, (bj + 0.5) * P)
			var bw := P - Game.ROAD_HALF * 2
			_box(c + Vector3(0, 0.1, 0), Vector3(bw, 0.2, bw), walk_mat, false)
			for sd in [-1, 1]:
				_box(c + Vector3(sd * (bw * 0.5 - 0.15), 0.11, 0), Vector3(0.3, 0.22, bw), curb, false)
				_box(c + Vector3(0, 0.11, sd * (bw * 0.5 - 0.15)), Vector3(bw, 0.22, 0.3), curb, false)
			var lot := bw - Game.WALK * 2
			var roll := r.randf()
			if roll < 0.12:
				_park(c, lot); block_kind[Vector2i(bi, bj)] = "park"
			elif roll < 0.22:
				_parking(c, lot); block_kind[Vector2i(bi, bj)] = "parking"
			else:
				_buildings(c, lot); block_kind[Vector2i(bi, bj)] = "buildings"
	_markings()
	if Game.signals: _signals()

func _box(pos: Vector3, size: Vector3, mat: Material, collide: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	add_child(mi)
	if collide:
		var sb := StaticBody3D.new()
		sb.collision_layer = 1
		sb.collision_mask = 0
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		sb.position = pos
		sb.add_child(cs)
		add_child(sb)
	return mi

func _buildings(c: Vector3, lot: float) -> void:
	var split := r.randi_range(1, 3)
	var cells := []
	if split == 1:
		cells.append([c, Vector2(lot, lot)])
	elif split == 2:
		var a := r.randf_range(0.35, 0.65) * lot
		if r.randf() < 0.5:
			cells.append([c + Vector3(-lot * 0.5 + a * 0.5, 0, 0), Vector2(a, lot)])
			cells.append([c + Vector3(a * 0.5, 0, 0), Vector2(lot - a, lot)])
		else:
			cells.append([c + Vector3(0, 0, -lot * 0.5 + a * 0.5), Vector2(lot, a)])
			cells.append([c + Vector3(0, 0, a * 0.5), Vector2(lot, lot - a)])
	else:
		var h := lot * 0.5
		for dx in [-1, 1]:
			for dz in [-1, 1]:
				cells.append([c + Vector3(dx * h * 0.5, 0, dz * h * 0.5), Vector2(h, h)])
	for cell in cells:
		var cc: Vector3 = cell[0]
		var sz: Vector2 = cell[1] - Vector2(0.4, 0.4)
		_kenney_building(cc, sz, c)

## Place a Kenney City Kit (CC0) building in a lot cell, facing the street, scaled to fit.
func _kenney_building(cc: Vector3, sz: Vector2, block_c: Vector3) -> void:
	var tall := r.randf() < 0.2
	var pool := Kit.BUILDINGS.slice(14) if tall else Kit.BUILDINGS.slice(0, 14)
	var name: String = pool[r.randi() % pool.size()]
	var path := Kit.building_path(name)
	var bb := Kit.aabb(path)
	# face the nearest street: direction from block centre to cell centre (or a random side)
	var off := cc - block_c
	var face := Vector3(signf(off.x), 0, 0) if absf(off.x) > absf(off.z) else Vector3(0, 0, signf(off.z))
	if off.length() < 0.5:
		face = [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)][r.randi() % 4]
	var yaw := atan2(face.x, face.z)
	var quarter := absf(face.x) > 0.5
	var w := bb.size.z if quarter else bb.size.x
	var d := bb.size.x if quarter else bb.size.z
	var s := minf(sz.x / w, sz.y / d)
	var hs := s * r.randf_range(1.0, 1.2)
	var height := bb.size.y * hs
	if height > 20.0: hs *= 20.0 / height
	var inst := Kit.instance(path)
	inst.scale = Vector3(s, hs, s)
	inst.rotation.y = yaw
	add_child(inst)
	var centre := Basis(Vector3.UP, yaw) * (bb.get_center() * Vector3(s, 0, s))
	inst.position = Vector3(cc.x - centre.x, 0.2, cc.z - centre.z)
	var foot := Vector3(w * s, bb.size.y * hs, d * s)
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	sb.collision_mask = 0
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = foot * Vector3(0.92, 1.0, 0.92)
	cs.shape = sh
	sb.position = Vector3(cc.x, 0.2 + foot.y * 0.5, cc.z)
	sb.add_child(cs)
	add_child(sb)

func _park(c: Vector3, lot: float) -> void:
	_box(c + Vector3(0, 0.22, 0), Vector3(lot, 0.05, lot), Tex.mat_tex(Tex.grass(), 6.0), false)
	# footpath cross
	_box(c + Vector3(0, 0.25, 0), Vector3(lot, 0.03, 1.6), Tex.mat_col(Color(0.70, 0.62, 0.48)), false)
	_box(c + Vector3(0, 0.25, 0), Vector3(1.6, 0.03, lot), Tex.mat_col(Color(0.70, 0.62, 0.48)), false)
	var leaf := [Tex.mat_col(Color(0.18, 0.42, 0.15)), Tex.mat_col(Color(0.25, 0.50, 0.18)), Tex.mat_col(Color(0.14, 0.35, 0.14))]
	for k in 9:
		var p := c + Vector3(r.randf_range(-0.42, 0.42) * lot, 0, r.randf_range(-0.42, 0.42) * lot)
		if abs(p.x - c.x) < 1.6 or abs(p.z - c.z) < 1.6: continue
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		var rad := r.randf_range(1.3, 2.2)
		sm.radius = rad; sm.height = rad * 1.6
		mi.mesh = sm
		mi.material_override = leaf[k % 3]
		mi.position = p + Vector3(0, 2.5, 0)
		add_child(mi)
	# fountain
	var f := MeshInstance3D.new()
	var cm := CylinderMesh.new(); cm.top_radius = 1.4; cm.bottom_radius = 1.5; cm.height = 0.5
	f.mesh = cm; f.material_override = Tex.mat_col(Color(0.3, 0.55, 0.85)); f.position = c + Vector3(0, 0.45, 0)
	add_child(f)

func _parking(c: Vector3, lot: float) -> void:
	_box(c + Vector3(0, 0.21, 0), Vector3(lot, 0.03, lot), Tex.mat_tex(Tex.asphalt(), 8.0, Color(1.05, 1.05, 1.1)), false)
	var white := Tex.mat_col(Color(0.92, 0.92, 0.88))
	for k in 5:
		var x := c.x - lot * 0.5 + 1.3 + k * 2.6
		_box(Vector3(x - 1.3, 0.24, c.z - lot * 0.5 + 2.5), Vector3(0.12, 0.02, 4.5), white, false)
		if r.randf() < 0.55:
			parked_spots.append([Vector3(x, 0.2, c.z - lot * 0.5 + 2.6), 0.0])
		_box(Vector3(x - 1.3, 0.24, c.z + lot * 0.5 - 2.5), Vector3(0.12, 0.02, 4.5), white, false)
		if r.randf() < 0.55:
			parked_spots.append([Vector3(x, 0.2, c.z + lot * 0.5 - 2.6), PI])

func _markings() -> void:
	var dash := BoxMesh.new(); dash.size = Vector3(0.22, 0.02, 2.2)
	var stripe := BoxMesh.new(); stripe.size = Vector3(0.55, 0.02, 2.0)
	var gap := Game.ROAD_HALF + 2.0
	for k in Game.NB + 1:
		for s in Game.NB:
			var a := s * P + gap
			var b := (s + 1) * P - gap
			var t := a + 1.0
			while t < b:
				# road along X at z = k*P (dashes rotated 90deg)
				dash_xf.append(Transform3D(Basis(Vector3.UP, PI / 2), Vector3(t, 0.01, k * P)))
				dash_xf.append(Transform3D(Basis(), Vector3(k * P, 0.01, t)))
				t += 4.5
	# zebra crossings at every intersection approach
	for i in Game.NB + 1:
		for j in Game.NB + 1:
			var n := Vector3(i * P, 0.01, j * P)
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if not Game.in_grid(Vector2i(i, j) + d): continue
				var dir := Vector3(d.x, 0, d.y)
				var rt := Game.right_of(d)
				var w := -Game.ROAD_HALF + 0.8
				while w < Game.ROAD_HALF - 0.5:
					var bas := Basis() if d.x == 0 else Basis(Vector3.UP, PI / 2)
					stripe_xf.append(Transform3D(bas, n + dir * (Game.ROAD_HALF + 0.9) + rt * w))
					w += 1.3
	_multimesh(dash, dash_xf, Tex.mat_col(Color(0.95, 0.85, 0.35)))
	_multimesh(stripe, stripe_xf, Tex.mat_col(Color(0.92, 0.92, 0.90)))

func _multimesh(mesh: Mesh, xfs: Array, mat: Material) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	add_child(mmi)

func _signals() -> void:
	var dark := Tex.mat_col(Color(0.16, 0.17, 0.18))
	var pole_xf: Array = []; var arm_xf: Array = []; var house_xf: Array = []; var bar_xf: Array = []
	var lamp_xf := []
	for g in 2:
		lamp_mats.append([])
		lamp_xf.append([])
		for a in 2:
			lamp_mats[g].append([]); lamp_xf[g].append([])
			for c in 3:
				var m := StandardMaterial3D.new()
				m.albedo_color = LAMP_COLS[c]
				m.emission_enabled = true
				m.emission = LAMP_COLS[c]
				m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				lamp_mats[g][a].append(m)
				lamp_xf[g][a].append([])
	var hw := Game.ROAD_HALF
	for i in Game.NB + 1:
		for j in Game.NB + 1:
			var n := Vector2i(i, j)
			if (i == 0 or i == Game.NB) and (j == 0 or j == Game.NB): continue
			var c := Game.node_pos(n)
			var g := Game.sig_group(n)
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if not Game.in_grid(n - d): continue
				var d3 := Vector3(d.x, 0, d.y)
				var rt := Game.right_of(d)
				var ns := 1 if d.x == 0 else 0
				var bas := Basis() if d.x == 0 else Basis(Vector3.UP, PI / 2)
				var pole := c - d3 * (hw + 1.2) + rt * (hw + 1.2)
				pole_xf.append(Transform3D(Basis(), pole + Vector3(0, 2.6, 0)))
				var head := c - d3 * (hw + 0.8) + rt * Game.LANE + Vector3(0, 5.0, 0)
				var mid := (pole + head) * 0.5
				arm_xf.append(Transform3D(bas, Vector3(mid.x, 5.1, mid.z)))
				house_xf.append(Transform3D(bas, head))
				for k in 3:
					lamp_xf[g][ns][k].append(Transform3D(bas, head + rt * ((1 - k) * 0.66) + Vector3(0, 0.22, 0)))
				bar_xf.append(Transform3D(bas, c - d3 * (hw + 2.4) + rt * Game.LANE + Vector3(0, 0.012, 0)))
	var pm := BoxMesh.new(); pm.size = Vector3(0.25, 5.2, 0.25)
	var am := BoxMesh.new(); am.size = Vector3(hw + 1.2 - Game.LANE, 0.15, 0.15)
	var hm := BoxMesh.new(); hm.size = Vector3(2.1, 0.4, 0.8)
	var lm := BoxMesh.new(); lm.size = Vector3(0.56, 0.1, 0.56)
	var bm := BoxMesh.new(); bm.size = Vector3(4.4, 0.02, 0.45)
	_multimesh(pm, pole_xf, dark)
	_multimesh(am, arm_xf, dark)
	_multimesh(hm, house_xf, dark)
	_multimesh(bm, bar_xf, Tex.mat_col(Color(0.95, 0.95, 0.93)))
	for g in 2:
		for a in 2:
			for k in 3:
				_multimesh(lm, lamp_xf[g][a][k], lamp_mats[g][a][k])

func update_lamps() -> void:
	for g in lamp_mats.size():
		for a in 2:
			var st := Game.light_group(g, a == 1)
			for k in 3:
				var m: StandardMaterial3D = lamp_mats[g][a][k]
				var on := st == k
				m.albedo_color = LAMP_COLS[k] if on else LAMP_COLS[k].darkened(0.85)
				m.emission_energy_multiplier = 0.0
