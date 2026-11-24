class_name Car
extends CharacterBody3D
## Arcade top-down car. One physics model, driven by the player, traffic AI or police AI.

enum Ctrl { NONE, PLAYER, TRAFFIC, POLICE }

var ctrl := Ctrl.NONE
var is_police := false
var body_color := Color.RED

# tuning
var max_speed := 32.0
var accel := 15.0
var brake_force := 30.0
var reverse_max := 9.0
var turn_rate := 2.7
var grip := 9.0
var drift_grip := 1.2

# per-frame inputs
var throttle := 0.0
var steer := 0.0
var hb := false
var drifting := false

# traffic AI state
var ai_node := Vector2i.ZERO     # intersection we are heading to
var ai_dir := Vector2i(1, 0)
var ai_target := Vector3.ZERO
var ai_phase := 0                # 0 = heading to exit of segment, 1 = heading to entry of next
var ai_speed := 11.0
var stuck_t := 0.0
var reverse_t := 0.0
var wait_t := 0.0
var ignore_t := 0.0
# police
var pol_wp := Vector2i(-1, -1)
var siren_t := 0.0
var siren_a: MeshInstance3D
var siren_b: MeshInstance3D
var skid_t := 0.0
var siren_light: OmniLight3D

func setup(col: Color, police := false) -> void:
	body_color = col
	is_police = police
	collision_layer = 2
	collision_mask = 1 | 2
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	add_to_group("cars")
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new(); sh.size = Vector3(2.0, 1.2, 4.3)
	cs.shape = sh; cs.position = Vector3(0, 0.7, 0)
	add_child(cs)
	var bodym := Tex.mat_col(col)
	var glass := Tex.mat_col(Color(0.10, 0.13, 0.18))
	var dark := Tex.mat_col(Color(0.06, 0.06, 0.06))
	if police:
		bodym = Tex.mat_col(Color(0.95, 0.95, 0.97))
	_part(Vector3(0, 0.55, 0), Vector3(2.0, 0.6, 4.3), bodym)
	if police:
		_part(Vector3(0, 0.87, 1.2), Vector3(2.02, 0.05, 1.4), Tex.mat_col(Color(0.08, 0.10, 0.30)))
		_part(Vector3(0, 0.87, -1.5), Vector3(2.02, 0.05, 1.1), Tex.mat_col(Color(0.08, 0.10, 0.30)))
	_part(Vector3(0, 1.08, 0.25), Vector3(1.7, 0.5, 2.2), glass)
	_part(Vector3(0, 1.35, 0.35), Vector3(1.6, 0.06, 1.5), bodym)
	for sx in [-1.0, 1.0]:
		for sz in [-1.35, 1.35]:
			_part(Vector3(sx * 0.98, 0.35, sz), Vector3(0.3, 0.6, 0.85), dark)
		_part(Vector3(sx * 0.65, 0.6, -2.16), Vector3(0.45, 0.2, 0.06), Tex.mat_col(Color(1.0, 0.95, 0.7), true))
		_part(Vector3(sx * 0.70, 0.6, 2.16), Vector3(0.4, 0.2, 0.06), Tex.mat_col(Color(0.9, 0.1, 0.1), true))
	if police:
		siren_a = _part(Vector3(-0.42, 1.5, 0.35), Vector3(0.8, 0.28, 0.5), Tex.mat_col(Color(1, 0.1, 0.1), true))
		siren_b = _part(Vector3(0.42, 1.5, 0.35), Vector3(0.8, 0.28, 0.5), Tex.mat_col(Color(0.15, 0.35, 1), true))
		siren_light = OmniLight3D.new()
		siren_light.omni_range = 7.0
		siren_light.light_energy = 3.0
		siren_light.position = Vector3(0, 2.5, 0.3)
		add_child(siren_light)

func _part(p: Vector3, s: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new(); bm.size = s
	mi.mesh = bm; mi.material_override = m; mi.position = p
	add_child(mi)
	return mi

func speed() -> float:
	return velocity.length()

func forward() -> Vector3:
	return -global_transform.basis.z

func start_traffic(from_node: Vector2i, dir: Vector2i) -> void:
	ctrl = Ctrl.TRAFFIC
	ai_dir = dir
	ai_node = from_node + dir
	ai_phase = 0
	ai_target = _exit_point()
	ai_speed = Game.rng.randf_range(9.0, 13.0)

func start_police() -> void:
	ctrl = Ctrl.POLICE
	pol_wp = Vector2i(-1, -1)
	max_speed = 34.0
	accel = 17.0

func _exit_point() -> Vector3:
	var d3 := Vector3(ai_dir.x, 0, ai_dir.y)
	return Game.node_pos(ai_node) - d3 * (Game.ROAD_HALF + 3.0) + Game.right_of(ai_dir) * Game.LANE

func _physics_process(dt: float) -> void:
	match ctrl:
		Ctrl.PLAYER: _input_player()
		Ctrl.TRAFFIC: _ai_traffic(dt)
		Ctrl.POLICE: _ai_police(dt)
		_:
			throttle = 0.0; steer = 0.0; hb = true
	_drive(dt)
	if is_police:
		siren_t += dt
		var on := fmod(siren_t, 0.5) < 0.25
		siren_a.visible = on or ctrl != Ctrl.POLICE
		siren_b.visible = not on or ctrl != Ctrl.POLICE
		siren_light.visible = ctrl == Ctrl.POLICE
		siren_light.light_color = Color(1, 0.15, 0.1) if on else Color(0.2, 0.4, 1)

func _input_player() -> void:
	var v := Game.move_vector()
	throttle = -v.y
	steer = -v.x
	hb = Game.handbrake()

func _drive(dt: float) -> void:
	var fwd := forward()
	var rt := global_transform.basis.x
	var fs := velocity.dot(fwd)
	var ls := velocity.dot(rt)
	if throttle > 0.05:
		if fs < -0.5: fs += brake_force * throttle * dt
		else: fs += accel * throttle * dt * (1.0 - 0.5 * fs / max_speed)
	elif throttle < -0.05:
		if fs > 0.5: fs -= brake_force * -throttle * dt
		else: fs -= accel * 0.6 * -throttle * dt
	else:
		fs = move_toward(fs, 0.0, 3.0 * dt)
	if hb:
		fs = move_toward(fs, 0.0, 7.0 * dt)
	fs = clampf(fs, -reverse_max, max_speed)
	# speed-dependent steering (no turning when stopped)
	var sf := clampf(absf(fs) / 7.0, 0.0, 1.0) * signf(fs)
	var hi := clampf(absf(fs) / max_speed, 0.0, 1.0)
	var yaw := steer * turn_rate * sf * (1.0 - 0.35 * hi) * (1.5 if hb else 1.0)
	var g := (drift_grip if hb else grip * (1.0 - 0.55 * hi * absf(steer)))
	ls = lerpf(ls, 0.0, 1.0 - exp(-g * dt))
	drifting = absf(ls) > 3.0
	velocity = fwd * fs + rt * ls
	velocity.y = 0.0
	rotation.y += yaw * dt
	var before := velocity
	move_and_slide()
	if get_slide_collision_count() > 0:
		velocity *= 0.92
		if before.length() > 12.0 and ctrl == Ctrl.PLAYER:
			velocity *= 0.6
	global_position.y = 0.0
	rotation.x = 0.0; rotation.z = 0.0
	if drifting and speed() > 8.0:
		skid_t += dt
		if skid_t > 0.05:
			skid_t = 0.0
			if Game.main: Game.main.add_skid(global_position, rotation.y)
	_hit_peds()

func _hit_peds() -> void:
	if speed() < 4.0: return
	var pos := global_position
	for p in get_tree().get_nodes_in_group("peds"):
		if not p.alive: continue
		var d: Vector3 = p.global_position - pos
		d.y = 0
		var f := absf(d.dot(forward())); var l := absf(d.dot(global_transform.basis.x))
		if f < 2.5 and l < 1.3:
			p.kill(velocity)
			if ctrl == Ctrl.PLAYER:
				Game.add_cash(10)
				Game.add_wanted(1)
				Game.message.emit("+$10", Color(1, 0.9, 0.2))

# ---------- traffic AI ----------
func _obstacle_ahead() -> bool:
	if ignore_t > 0.0: return false
	var fwd := forward(); var rt := global_transform.basis.x
	var look := 6.0 + speed() * 0.5
	for c in get_tree().get_nodes_in_group("cars"):
		if c == self: continue
		var d: Vector3 = c.global_position - global_position
		var a := d.dot(fwd)
		if a > 0.5 and a < look and absf(d.dot(rt)) < 2.4: return true
	for p in get_tree().get_nodes_in_group("peds"):
		if not p.alive: continue
		var d: Vector3 = p.global_position - global_position
		var a := d.dot(fwd)
		if a > 0.5 and a < look * 0.8 and absf(d.dot(rt)) < 1.8: return true
	var pl = Game.main.player if Game.main else null
	if pl and pl.visible:
		var d: Vector3 = pl.global_position - global_position
		var a := d.dot(fwd)
		if a > 0.5 and a < look * 0.8 and absf(d.dot(rt)) < 1.8: return true
	return false

func _steer_to(p: Vector3) -> float:
	var to := p - global_position; to.y = 0
	var diff := wrapf(Game.yaw_of(to) - rotation.y, -PI, PI)
	steer = clampf(diff * 2.5, -1.0, 1.0)
	return diff

func _ai_traffic(dt: float) -> void:
	hb = false
	ignore_t = maxf(ignore_t - dt, 0.0)
	var to := ai_target - global_position; to.y = 0
	if to.length() < 3.0:
		if ai_phase == 0:
			var opts := []
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if d == -ai_dir: continue
				if Game.in_grid(ai_node + d): opts.append(d)
			if opts.is_empty(): opts.append(-ai_dir)
			# prefer going straight a bit
			var nd: Vector2i = ai_dir if (opts.has(ai_dir) and Game.rng.randf() < 0.5) else opts[Game.rng.randi() % opts.size()]
			ai_dir = nd
			ai_target = Game.node_pos(ai_node) + Vector3(nd.x, 0, nd.y) * (Game.ROAD_HALF + 2.0) + Game.right_of(nd) * Game.LANE
			ai_phase = 1
		else:
			ai_node = ai_node + ai_dir
			ai_target = _exit_point()
			ai_phase = 0
	var diff := _steer_to(ai_target)
	var want := ai_speed * (0.55 if absf(diff) > 0.35 or ai_phase == 1 else 1.0)
	if _obstacle_ahead():
		throttle = -1.0 if speed() > 1.0 else 0.0
		wait_t += dt
		if wait_t > 4.0:
			ignore_t = 1.5; wait_t = 0.0
		return
	wait_t = 0.0
	var fs := velocity.dot(forward())
	throttle = clampf((want - fs) * 0.4, -1.0, 1.0)
	_unstick(dt)

func _unstick(dt: float) -> void:
	if reverse_t > 0.0:
		reverse_t -= dt
		throttle = -1.0
		steer = -steer
		return
	if throttle > 0.3 and speed() < 1.0:
		stuck_t += dt
		if stuck_t > 1.2:
			stuck_t = 0.0
			reverse_t = 1.0
	else:
		stuck_t = 0.0

# ---------- police AI ----------
func _ai_police(dt: float) -> void:
	var pl = Game.main.player_target()
	if pl == null:
		throttle = 0.0; return
	var ppos: Vector3 = pl.global_position
	var dist := global_position.distance_to(ppos)
	var target := ppos
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 1, 0), ppos + Vector3(0, 1, 0), 1)
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		# route along the road grid
		var here := Vector2i(roundi(global_position.x / Game.P), roundi(global_position.z / Game.P))
		if pol_wp.x < 0 or global_position.distance_to(Game.node_pos(pol_wp)) < 6.0:
			var base := pol_wp if pol_wp.x >= 0 else here
			var best := base; var bd := INF
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n: Vector2i = base + d
				if not Game.in_grid(n): continue
				var dd := Game.node_pos(n).distance_to(ppos)
				if dd < bd: bd = dd; best = n
			pol_wp = best
		target = Game.node_pos(pol_wp)
	else:
		pol_wp = Vector2i(-1, -1)
	var diff := _steer_to(target)
	hb = absf(diff) > 1.1 and speed() > 12.0
	var on_foot: bool = pl == Game.main.player
	if on_foot and dist < 9.0:
		throttle = -1.0 if speed() > 2.0 else 0.0
	else:
		throttle = 1.0 if absf(diff) < 1.3 else 0.5
	_unstick(dt)
