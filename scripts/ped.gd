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
# ---- v4 roles ----
var role := "civ"        # civ | gang | cop | swat
var gang := -1
var hp := 20.0
var stun_t := 0.0
var flee_t := 0.0
var mugged := false
var shoot_cd := 0.0
var leave_t := 0.0       # cops walking off after the heat is gone
var mission_target := false
const ROLE_HP := {"civ": 20.0, "gang": 40.0, "cop": 50.0, "swat": 95.0}

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

func setup(b: Vector2i, role_ := "civ", gang_ := -1) -> void:
	add_to_group("peds")
	role = role_; gang = gang_
	hp = ROLE_HP.get(role, 20.0)
	block = b
	var r := Game.rng
	var shirt: Color = SHIRTS[r.randi() % SHIRTS.size()]
	var pants: Color = [Color(0.2, 0.25, 0.45), Color(0.15, 0.15, 0.15), Color(0.45, 0.35, 0.25)][r.randi() % 3]
	var hair: Color = HAIR[r.randi() % HAIR.size()]
	match role:
		"gang": shirt = Game.GANGS[gang]["col"]; pants = Color(0.08, 0.08, 0.1)
		"cop": shirt = Color(0.12, 0.2, 0.55); pants = Color(0.06, 0.08, 0.2); hair = Color(0.05, 0.07, 0.2)
		"swat": shirt = Color(0.1, 0.1, 0.12); pants = Color(0.08, 0.08, 0.09); hair = Color(0.02, 0.02, 0.02)
	var v := make_visual(self, shirt, SKIN[r.randi() % SKIN.size()], hair, pants)
	body = v[0]; arm_l = v[1]; arm_r = v[2]
	if role == "swat":
		body.scale *= 1.12
	if role == "cop" or role == "swat" or role == "gang":
		add_to_group("armed")
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
	if stun_t > 0.0:
		stun_t -= dt
		if stun_t <= 0.0:
			body.rotation = Vector3.ZERO; body.position.y = 0.0
			flee_t = 7.0
		return
	shoot_cd -= dt
	if role == "cop" or role == "swat":
		_ai_cop(dt); return
	if role == "gang" and _ai_gang(dt): return
	if flee_t > 0.0:
		flee_t -= dt
		var m = Game.main
		if m:
			var away: Vector3 = global_position - m.player_target().global_position
			away.y = 0
			_walk_dir(away.normalized(), 4.6, dt)
			if flee_t <= 0.0:
				block = Game.block_of(global_position)
				target = _corner_pos(block, corner)
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

## Walk in a direction, sliding round buildings (layer 1) with a short look-ahead ray.
func _walk_dir(dir: Vector3, speed: float, dt: float) -> void:
	if dir.length() < 0.01: return
	var space := get_world_3d().direct_space_state
	var best := dir
	for a in [0.0, 0.8, -0.8, 1.57, -1.57, 2.4, -2.4]:
		var d := dir.rotated(Vector3.UP, a)
		var q := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 0.8, 0), global_position + Vector3(0, 0.8, 0) + d * 1.4, 1)
		if space.intersect_ray(q).is_empty():
			best = d; break
	global_position += best * speed * dt
	global_position.y = 0.15
	rotation.y = lerp_angle(rotation.y, Game.yaw_of(best), 10.0 * dt)
	t += dt
	var sw := sin(t * speed * 3.0) * 0.7
	arm_l.rotation.x = sw; arm_r.rotation.x = -sw

func _los(a: Vector3, b: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(a + Vector3(0, 1.2, 0), b + Vector3(0, 1.2, 0), 1)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()

func _aim(to: Vector3, dt: float) -> void:
	rotation.y = lerp_angle(rotation.y, Game.yaw_of(to), 12.0 * dt)
	arm_r.rotation.x = -1.5   # gun arm up

## Police on foot: chase and arrest; shoot from 3 stars (SWAT always).
func _ai_cop(dt: float) -> void:
	var m = Game.main
	if m == null: return
	var tgt: Node3D = m.player_target()
	var to: Vector3 = tgt.global_position - global_position
	to.y = 0
	var dist := to.length()
	if Game.wanted == 0 or m.player.dying:
		leave_t += dt
		_walk_dir(-to.normalized(), 2.5, dt)
		return
	leave_t = 0.0
	var armed := role == "swat" or Game.wanted >= 3
	var sees := dist < 26.0 and _los(global_position, tgt.global_position)
	if armed and sees and dist > 2.2:
		_aim(to, dt)
		if dist > 9.0: _walk_dir(to.normalized(), 2.2, dt)
		if shoot_cd <= 0.0:
			shoot_cd = 0.55 if role == "swat" else 0.9
			npc_shoot(tgt, 9.0 if role == "swat" else 6.0)
	else:
		_walk_dir(to.normalized(), 5.4 if role == "cop" else 4.6, dt)

## Gang members: walk their turf; shoot at you on sight when you're hated (respect <= -25).
func _ai_gang(dt: float) -> bool:
	var m = Game.main
	if m == null or m.player.dying: return false
	if Game.respect[gang] > -25: return false
	var tgt: Node3D = m.player_target()
	var to: Vector3 = tgt.global_position - global_position
	to.y = 0
	if to.length() > 17.0 or not _los(global_position, tgt.global_position): return false
	_aim(to, dt)
	if shoot_cd <= 0.0:
		shoot_cd = 1.1
		npc_shoot(tgt, 5.0)
	return true

func npc_shoot(tgt: Node3D, dmg: float) -> void:
	var m = Game.main
	var f := Vector3(-sin(rotation.y), 0, -cos(rotation.y))
	var o := global_position + f * 0.7 + Vector3(0, 1.3, 0)
	var aim: Vector3 = tgt.global_position + Vector3(0, 1.0, 0)
	var hit := Game.rng.randf() < 0.55
	var end := aim if hit else aim + Vector3(Game.rng.randf_range(-2.5, 2.5), 0, Game.rng.randf_range(-2.5, 2.5))
	m.weapons._tracer(o, end, Color(1.0, 0.6, 0.3) if role != "gang" else Game.GANGS[gang]["col"])
	m.play_at("pistol", o, -8.0)
	Game.npc_fired.emit()
	if hit:
		if m.player_car: m.player_car.take_damage(dmg * 0.6)
		else: m.player.hurt(dmg)

## Bullet / punch damage; dies at 0 hp.
func hit(dmg: float, dir: Vector3, by_player := false) -> void:
	if not alive: return
	hp -= dmg
	if hp <= 0.0:
		kill(dir * 6.0, by_player)
	elif role == "civ":
		flee_t = 8.0

## Knocked down for a few seconds (mugging), then runs away.
func stun(s: float) -> void:
	stun_t = s
	body.rotation = Vector3(PI / 2, 0, 0)
	body.position.y = 0.25

func kill(v: Vector3, by_player := false) -> void:
	if not alive: return
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
	remove_from_group("armed")
	Game.ped_killed.emit(self, by_player)
