class_name Ped
extends Node3D
## Pedestrian that walks around sidewalk rings and crosses streets at corners.

var alive := true
var block := Vector2i.ZERO
var corner := 0          # index 0..3 of the corner we are walking towards
var cw := 1
var spd := 1.6
var target := Vector3.ZERO
var crossing := false
var dead_t := 0.0
var t := 0.0
var arm_l: Node3D
var arm_r: Node3D
var body: Node3D
var is_player := false

const SHIRTS := [Color(0.85, 0.2, 0.2), Color(0.2, 0.45, 0.85), Color(0.2, 0.7, 0.3), Color(0.9, 0.8, 0.2),
	Color(0.6, 0.3, 0.7), Color(0.95, 0.55, 0.15), Color(0.9, 0.9, 0.9), Color(0.25, 0.25, 0.3)]
const SKIN := [Color(0.95, 0.78, 0.62), Color(0.75, 0.55, 0.40), Color(0.45, 0.30, 0.20), Color(0.88, 0.68, 0.5)]
const HAIR := [Color(0.1, 0.07, 0.05), Color(0.35, 0.2, 0.1), Color(0.8, 0.65, 0.3), Color(0.15, 0.15, 0.15)]

static func make_visual(parent: Node3D, shirt: Color, skin: Color, hair: Color, pants: Color) -> Array:
	var root := Node3D.new()
	parent.add_child(root)
	var mk := func(p: Vector3, s: Vector3, c: Color) -> MeshInstance3D:
		var mi := MeshInstance3D.new(); var bm := BoxMesh.new(); bm.size = s
		mi.mesh = bm; mi.material_override = Tex.mat_col(c); mi.position = p
		root.add_child(mi); return mi
	mk.call(Vector3(0, 0.45, 0), Vector3(0.5, 0.9, 0.32), pants)
	mk.call(Vector3(0, 1.15, 0), Vector3(0.7, 0.6, 0.38), shirt)
	var al: MeshInstance3D = mk.call(Vector3(-0.45, 1.05, 0), Vector3(0.18, 0.65, 0.2), shirt)
	var ar: MeshInstance3D = mk.call(Vector3(0.45, 1.05, 0), Vector3(0.18, 0.65, 0.2), shirt)
	var head := MeshInstance3D.new(); var sm := SphereMesh.new(); sm.radius = 0.24; sm.height = 0.48
	head.mesh = sm; head.material_override = Tex.mat_col(skin); head.position = Vector3(0, 1.62, 0)
	root.add_child(head)
	mk.call(Vector3(0, 1.80, 0.04), Vector3(0.36, 0.1, 0.34), hair)
	root.scale = Vector3.ONE * 1.25
	return [root, al, ar]

func setup(b: Vector2i) -> void:
	add_to_group("peds")
	block = b
	var r := Game.rng
	var v := make_visual(self, SHIRTS[r.randi() % SHIRTS.size()], SKIN[r.randi() % SKIN.size()], HAIR[r.randi() % HAIR.size()],
		[Color(0.2, 0.25, 0.45), Color(0.15, 0.15, 0.15), Color(0.45, 0.35, 0.25)][r.randi() % 3])
	body = v[0]; arm_l = v[1]; arm_r = v[2]
	spd = r.randf_range(1.3, 2.1)
	cw = 1 if r.randf() < 0.5 else -1
	corner = r.randi() % 4
	# start at random point along the edge leading to `corner`
	var prev := _corner_pos(block, (corner - cw + 4) % 4)
	global_position = prev.lerp(_corner_pos(block, corner), r.randf())
	target = _corner_pos(block, corner)

static func _corner_pos(b: Vector2i, c: int) -> Vector3:
	var lo := Game.ROAD_HALF + Game.WALK * 0.5
	var x0 := b.x * Game.P + lo; var x1 := (b.x + 1) * Game.P - lo
	var z0 := b.y * Game.P + lo; var z1 := (b.y + 1) * Game.P - lo
	match c:
		0: return Vector3(x0, 0.2, z0)
		1: return Vector3(x1, 0.2, z0)
		2: return Vector3(x1, 0.2, z1)
		_: return Vector3(x0, 0.2, z1)

func _physics_process(dt: float) -> void:
	if not alive:
		dead_t += dt
		return
	t += dt
	var to := target - global_position; to.y = 0
	if to.length() < 0.3:
		_next_target()
		to = target - global_position; to.y = 0
	var step := to.normalized() * spd * dt
	global_position += step
	global_position.y = 0.2 if not crossing else 0.0
	rotation.y = lerp_angle(rotation.y, Game.yaw_of(to), 10.0 * dt)
	var sw := sin(t * spd * 5.0) * 0.6
	arm_l.rotation.x = sw; arm_r.rotation.x = -sw
	body.position.y = absf(sin(t * spd * 5.0)) * 0.05

func _next_target() -> void:
	if crossing:
		crossing = false
	elif Game.rng.randf() < 0.3:
		# cross the street to a neighbouring block, keeping the same world corner position
		var opts := []
		var c := corner
		var hx := -1 if (c == 0 or c == 3) else 1
		var hz := -1 if (c == 0 or c == 1) else 1
		for nb in [Vector2i(block.x + hx, block.y), Vector2i(block.x, block.y + hz)]:
			if nb.x >= 0 and nb.y >= 0 and nb.x < Game.NB and nb.y < Game.NB: opts.append(nb)
		if not opts.is_empty():
			var nb: Vector2i = opts[Game.rng.randi() % opts.size()]
			var nc := c
			if nb.x != block.x: nc = [1, 0, 3, 2][c]
			else: nc = [3, 2, 1, 0][c]
			block = nb; corner = nc
			target = _corner_pos(block, corner)
			crossing = true
			return
	if Game.rng.randf() < 0.1: cw = -cw
	corner = (corner + cw + 4) % 4
	target = _corner_pos(block, corner)

func kill(v: Vector3) -> void:
	alive = false
	remove_from_group("peds")
	add_to_group("dead_peds")
	global_position += v.normalized() * 1.5
	global_position.y = 0.22
	body.rotation = Vector3(PI / 2, 0, 0)
	body.position.y = 0.25
	var splat := MeshInstance3D.new()
	var cm := CylinderMesh.new(); cm.top_radius = 1.1; cm.bottom_radius = 1.1; cm.height = 0.02
	splat.mesh = cm; splat.material_override = Tex.mat_col(Color(0.55, 0.02, 0.02))
	splat.position = Vector3(0, 0.03, 0)
	splat.scale = Vector3(1.0, 1.0, 0.7)
	add_child(splat)
