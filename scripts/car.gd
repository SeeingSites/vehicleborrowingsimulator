class_name Car
extends CharacterBody3D
## Arcade top-down car. One physics model, driven by the player, traffic AI or police AI.
## Has health: darkens and smokes when damaged, catches fire, explodes and leaves a wreck.

enum Ctrl { NONE, PLAYER, TRAFFIC, POLICE }

signal exploded(car)

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

# damage
var health := 100.0
var dead := false
var burn_t := -1.0
var hit_cd := 0.0
var body_mat: StandardMaterial3D
var roof_mat: StandardMaterial3D
var glass_mi: MeshInstance3D
var smoke: CPUParticles3D
var fire: CPUParticles3D
var fire_light: OmniLight3D
var siren_snd: AudioStreamPlayer3D

# traffic AI state
var ai_node := Vector2i.ZERO     # intersection we are heading to
var ai_dir := Vector2i(1, 0)
var ai_target := Vector3.ZERO
var ai_phase := 0                # 0 = heading to the stop line, 1 = crossing to entry of next segment
var ai_speed := 11.0
var pending := Vector2i.ZERO
var has_pending := false
var held_t := 0.0
var still_t := 0.0               # continuous time nearly stationary (jam metric)
var crossings := 0
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

## Car types: Kenney Car Kit (CC0) model + handling.
## [model, target length m, max_speed, accel, turn_rate, grip, drift_grip, mass]
const TYPES := {
	"sedan":     ["sedan",            4.4, 32.0, 15.0, 2.7, 9.0, 1.2, 1.0],
	"sports":    ["sedan-sports",     4.3, 42.0, 22.0, 3.0, 10.5, 1.5, 0.9],
	"hatchback": ["hatchback-sports", 4.0, 35.0, 18.0, 3.4, 8.0, 1.0, 0.8],
	"taxi":      ["taxi",             4.6, 33.0, 15.0, 2.8, 9.0, 1.2, 1.0],
	"suv":       ["suv",              4.8, 30.0, 13.0, 2.4, 8.0, 1.4, 1.4],
	"van":       ["van",              5.0, 26.0, 10.0, 2.1, 6.5, 1.5, 1.8],
	"truck":     ["delivery",         6.2, 22.0, 7.0, 1.7, 6.0, 1.8, 2.8],
	"police":    ["police",           4.8, 34.0, 17.0, 2.9, 9.5, 1.3, 1.2],
}
var car_type := "sedan"
var mass := 1.0
var dmg_overlay: StandardMaterial3D
var model: Node3D
var roof_h := 1.5

func setup(col: Color, police := false, type := "") -> void:
	body_color = col
	is_police = police
	car_type = "police" if police else (type if TYPES.has(type) else "sedan")
	var t: Array = TYPES[car_type]
	max_speed = t[2]; accel = t[3]; turn_rate = t[4]; grip = t[5]; drift_grip = t[6]; mass = t[7]
	collision_layer = 2
	collision_mask = 1 | 2
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	add_to_group("cars")
	var path := Kit.car_path(t[0])
	var bb := Kit.aabb(path)
	var sc: float = t[1] / bb.size.z
	model = Kit.instance(path)
	model.scale = Vector3.ONE * sc
	model.rotation.y = PI   # Kenney cars face +Z, ours face -Z
	model.position = Vector3(-bb.get_center().x * sc, 0.0, bb.get_center().z * sc)
	add_child(model)
	roof_h = bb.end.y * sc
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new(); sh.size = Vector3(bb.size.x * sc * 0.92, minf(roof_h, 2.2), t[1] * 0.96)
	cs.shape = sh; cs.position = Vector3(0, 0.1 + sh.size.y * 0.5, 0)
	add_child(cs)
	# damage tint: a translucent dark overlay over every surface of the model
	dmg_overlay = StandardMaterial3D.new()
	dmg_overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dmg_overlay.albedo_color = Color(0.08, 0.06, 0.05, 0.0)
	dmg_overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_apply_overlay(model)
	body_mat = StandardMaterial3D.new()  # kept for API compatibility
	if police:
		siren_a = _part(Vector3(-0.42, roof_h + 0.12, 0.2), Vector3(0.8, 0.24, 0.45), Tex.mat_col(Color(1, 0.1, 0.1), true))
		siren_b = _part(Vector3(0.42, roof_h + 0.12, 0.2), Vector3(0.8, 0.24, 0.45), Tex.mat_col(Color(0.15, 0.35, 1), true))
		siren_light = OmniLight3D.new()
		siren_light.omni_range = 7.0
		siren_light.light_energy = 3.0
		siren_light.position = Vector3(0, roof_h + 1.2, 0.3)
		add_child(siren_light)
		siren_snd = AudioStreamPlayer3D.new()
		siren_snd.stream = Sfx.get_stream("siren")
		siren_snd.unit_size = 35.0
		siren_snd.max_distance = 140.0
		siren_snd.volume_db = -8.0
		add_child(siren_snd)

func _apply_overlay(n: Node) -> void:
	if n is MeshInstance3D: (n as MeshInstance3D).material_overlay = dmg_overlay
	for c in n.get_children(): _apply_overlay(c)

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

func stop_dist() -> float:
	return Game.ROAD_HALF + (5.0 if Game.signals else 3.0)

func start_traffic(from_node: Vector2i, dir: Vector2i) -> void:
	if dead: return
	ctrl = Ctrl.TRAFFIC
	ai_dir = dir
	ai_node = from_node + dir
	ai_phase = 0
	has_pending = false
	ai_target = _exit_point()
	ai_speed = Game.rng.randf_range(9.0, 13.0)
	if siren_snd: siren_snd.stop()

func start_police() -> void:
	ctrl = Ctrl.POLICE
	pol_wp = Vector2i(-1, -1)
	max_speed = 34.0
	accel = 17.0
	if siren_snd and not siren_snd.playing: siren_snd.play()

func _exit_point() -> Vector3:
	var d3 := Vector3(ai_dir.x, 0, ai_dir.y)
	return Game.node_pos(ai_node) - d3 * stop_dist() + Game.right_of(ai_dir) * Game.LANE

func _physics_process(dt: float) -> void:
	if dead:
		throttle = 0.0; steer = 0.0; hb = true
	else:
		match ctrl:
			Ctrl.PLAYER: _input_player()
			Ctrl.TRAFFIC: _ai_traffic(dt)
			Ctrl.POLICE: _ai_police(dt)
			_:
				throttle = 0.0; steer = 0.0; hb = true
	_drive(dt)
	still_t = still_t + dt if speed() < 0.5 else 0.0
	hit_cd = maxf(hit_cd - dt, 0.0)
	if burn_t >= 0.0 and not dead:
		burn_t -= dt
		if fire_light: fire_light.light_energy = 2.0 + randf() * 1.5
		if burn_t < 0.0:
			explode()
	if is_police:
		siren_t += dt
		var on := fmod(siren_t, 0.5) < 0.25
		var active := ctrl == Ctrl.POLICE and not dead
		siren_a.visible = on or not active
		siren_b.visible = not on or not active
		siren_light.visible = active
		siren_light.light_color = Color(1, 0.15, 0.1) if on else Color(0.2, 0.4, 1)
		if not active and siren_snd.playing: siren_snd.stop()

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
	var acc := accel * (0.55 if health < 30.0 else 1.0)
	if throttle > 0.05:
		if fs < -0.5: fs += brake_force * throttle * dt
		else: fs += acc * throttle * dt * (1.0 - 0.5 * fs / max_speed)
	elif throttle < -0.05:
		if fs > 0.5: fs -= brake_force * -throttle * dt
		else: fs -= acc * 0.6 * -throttle * dt
	else:
		fs = move_toward(fs, 0.0, 3.0 * dt)
	if hb:
		fs = move_toward(fs, 0.0, 7.0 * dt)
	fs = clampf(fs, -reverse_max, max_speed)
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
	var impact := 0.0
	var other: Object = null
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var into := -before.dot(col.get_normal())
		var o := col.get_collider()
		if o is Car:
			into = (before - o.velocity).dot(-col.get_normal())
		if into > impact:
			impact = into; other = o
	if get_slide_collision_count() > 0:
		velocity *= 0.92
		if before.length() > 12.0 and ctrl == Ctrl.PLAYER:
			velocity *= 0.6
	if impact > 3.0 and other is Car and hit_cd <= 0.0 and get_instance_id() < other.get_instance_id():
		Game.car_contacts += 1
	if impact > 7.0 and hit_cd <= 0.0:
		hit_cd = 0.4
		var dmg := (impact - 7.0) * 5.0
		# one crash can wreck a car but never makes it explode outright
		take_damage(minf(dmg / mass, 60.0))
		if other is Car: other.take_damage(minf(dmg * 0.8 * mass / other.mass, 60.0))
		if Game.main: Game.main.play_at("thud", global_position, clampf(-14.0 + impact, -14.0, 4.0))
	global_position.y = 0.0
	rotation.x = 0.0; rotation.z = 0.0
	if drifting and speed() > 8.0:
		skid_t += dt
		if skid_t > 0.05:
			skid_t = 0.0
			if Game.main: Game.main.add_skid(global_position, rotation.y)
	_hit_peds()

# ---------- damage ----------
func take_damage(d: float) -> void:
	if dead or d <= 0.0: return
	health -= d
	var k := clampf((100.0 - health) / 100.0, 0.0, 1.0)
	dmg_overlay.albedo_color.a = k * 0.6
	if health < 45.0: _ensure_smoke()
	if health < 15.0 and burn_t < 0.0:
		ignite(Game.rng.randf_range(3.0, 4.5))
	if health < -40.0:
		explode()

## Respray: full repair, fire out, new paint tint.
func respray(tint: Color) -> void:
	if dead: return
	health = 100.0
	burn_t = -1.0
	dmg_overlay.albedo_color.a = 0.0
	if smoke: smoke.queue_free(); smoke = null
	if fire: fire.queue_free(); fire = null
	if fire_light: fire_light.queue_free(); fire_light = null
	_tint(model, tint)

func _tint(n: Node, tint: Color) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var base := mi.mesh.surface_get_material(i)
			if base is StandardMaterial3D:
				var mat := (base as StandardMaterial3D).duplicate() as StandardMaterial3D
				mat.albedo_color = tint
				mi.set_surface_override_material(i, mat)
	for ch in n.get_children(): _tint(ch, tint)

func _ensure_smoke() -> void:
	if smoke: return
	smoke = _particles(Color(0.3, 0.3, 0.3, 0.75), Color(0.55, 0.55, 0.55, 0.0), 28, 1.8, 0.45, 2.4, false)
	smoke.position = Vector3(0, 1.0, -1.4)
	add_child(smoke)

func ignite(t: float) -> void:
	if dead: return
	_ensure_smoke()
	burn_t = t
	if fire: return
	fire = _particles(Color(1.0, 0.9, 0.3, 1.0), Color(0.9, 0.2, 0.0, 0.0), 60, 0.7, 0.7, 1.9, true)
	fire.position = Vector3(0, 1.0, -1.2)
	add_child(fire)
	fire_light = OmniLight3D.new()
	fire_light.light_color = Color(1.0, 0.55, 0.15)
	fire_light.omni_range = 8.0
	fire_light.position = Vector3(0, 2.5, -1.2)
	add_child(fire_light)

func _particles(c0: Color, c1: Color, amount: int, life: float, s0: float, s1: float, glow: bool) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	var m := SphereMesh.new(); m.radius = 0.5; m.height = 1.0; m.radial_segments = 8; m.rings = 4
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if glow else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	m.material = mat
	p.mesh = m
	p.amount = amount
	p.lifetime = life
	p.direction = Vector3(0, 1, 0)
	p.spread = 25.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 3.0
	p.gravity = Vector3(0.6, 1.2, 0.3)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.4
	var cr := Curve.new(); cr.add_point(Vector2(0, s0)); cr.add_point(Vector2(1, s1))
	p.scale_amount_curve = cr
	p.scale_amount_max = 1.0
	var gr := Gradient.new(); gr.set_color(0, c0); gr.set_color(1, c1)
	p.color_ramp = gr
	p.local_coords = false
	return p

func explode() -> void:
	if dead: return
	dead = true
	health = 0.0
	burn_t = -1.0
	if ctrl == Ctrl.POLICE and siren_snd: siren_snd.stop()
	dmg_overlay.albedo_color = Color(0.05, 0.04, 0.03, 0.88)
	if fire: fire.emitting = false
	if fire_light: fire_light.queue_free(); fire_light = null
	_ensure_smoke()
	smoke.amount = 16
	add_to_group("wrecks")
	velocity += Vector3(randf_range(-2, 2), 0, randf_range(-2, 2))
	exploded.emit(self)
	if Game.main: Game.main.explosion(global_position, self)

func _hit_peds() -> void:
	if speed() < 4.0: return
	var pos := global_position
	var fwd := forward(); var rt := global_transform.basis.x
	for p in get_tree().get_nodes_in_group("peds"):
		if not p.alive: continue
		var d: Vector3 = p.global_position - pos
		d.y = 0
		if absf(d.dot(fwd)) < 2.5 and absf(d.dot(rt)) < 1.3:
			p.kill(velocity, ctrl == Ctrl.PLAYER)
			if Game.main: Game.main.play_at("splat", p.global_position, 0.0)
			if ctrl == Ctrl.PLAYER:
				Game.add_wanted(1)
	var pl = Game.main.player if Game.main else null
	# police only run you down deliberately from 4 stars; otherwise they brake to arrest
	if pl and pl.visible and not pl.dying and speed() > 6.0 and (ctrl != Ctrl.POLICE or Game.wanted >= 4):
		var d: Vector3 = pl.global_position - pos
		d.y = 0
		if absf(d.dot(fwd)) < 2.6 and absf(d.dot(rt)) < 1.4:
			pl.hurt(speed() * 3.0, velocity)

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

func _choose_dir() -> Vector2i:
	var opts := []
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if d == -ai_dir: continue
		if Game.in_grid(ai_node + d): opts.append(d)
	if opts.is_empty(): opts.append(-ai_dir)
	return ai_dir if (opts.has(ai_dir) and Game.rng.randf() < 0.5) else opts[Game.rng.randi() % opts.size()]

func _entry_point(nd: Vector2i) -> Vector3:
	return Game.node_pos(ai_node) + Vector3(nd.x, 0, nd.y) * (Game.ROAD_HALF + 2.0) + Game.right_of(nd) * Game.LANE

func _commit(nd: Vector2i) -> void:
	ai_dir = nd
	ai_target = _entry_point(nd)
	ai_phase = 1
	has_pending = false
	held_t = 0.0

## Right-of-way: may we enter the intersection now?
func _may_enter(nd: Vector2i) -> bool:
	if Game.signalled(ai_node):
		var st := Game.light_for(ai_node, ai_dir.x == 0)
		if st == Game.Light.RED: return false
		if st == Game.Light.YELLOW and speed() < 4.0: return false
	# don't block the box: the exit lane must have room
	var e0 := _entry_point(nd)
	var nd3 := Vector3(nd.x, 0, nd.y)
	for c in get_tree().get_nodes_in_group("cars"):
		if c == self: continue
		var rel: Vector3 = c.global_position - e0
		var a := rel.dot(nd3)
		if a > -2.0 and a < 6.5 and absf(rel.dot(Game.right_of(nd))) < 1.8 and c.speed() < 3.0: return false
	# left turns yield to oncoming traffic
	var left := Vector2i(ai_dir.y, -ai_dir.x)
	if nd == left:
		var npos := Game.node_pos(ai_node)
		for c in get_tree().get_nodes_in_group("cars"):
			if c == self or c.ctrl != Ctrl.TRAFFIC: continue
			# gap acceptance: after waiting a while, only yield to cars that are close
			var gap := 24.0 if held_t < 3.0 else 14.0
			if c.ai_node == ai_node and c.speed() > 1.0 and c.global_position.distance_to(npos) < gap:
				var cd: Vector2i = c.ai_dir
				if (c.ai_phase == 0 and cd == -ai_dir) or (c.ai_phase == 1 and cd == -ai_dir):
					return false
	return true

## True while legitimately queued for a red/yellow light (excluded from the jam metric).
func red_queued() -> bool:
	if not Game.signals or ctrl != Ctrl.TRAFFIC or ai_phase != 0: return false
	if not Game.signalled(ai_node): return false
	if Game.light_for(ai_node, ai_dir.x == 0) == Game.Light.GREEN and held_t < 0.5: return false
	var along := (Game.node_pos(ai_node) - global_position).dot(Vector3(ai_dir.x, 0, ai_dir.y))
	return along < Game.P

func _ai_traffic(dt: float) -> void:
	hb = false
	ignore_t = maxf(ignore_t - dt, 0.0)
	if not Game.signals:
		_ai_traffic_v1(dt)
		return
	if ai_phase == 0:
		var d3 := Vector3(ai_dir.x, 0, ai_dir.y)
		var along := (Game.node_pos(ai_node) - global_position).dot(d3)
		var to_line := along - stop_dist()
		var v := speed()
		if to_line <= 0.6:
			if not has_pending:
				pending = _choose_dir(); has_pending = true
			if _may_enter(pending) or held_t > 25.0:
				_commit(pending)
			else:
				held_t += dt
				_steer_to(Game.node_pos(ai_node) + Game.right_of(ai_dir) * Game.LANE)
				throttle = -1.0 if v > 0.3 else 0.0
				return
		elif Game.signalled(ai_node):
			var st := Game.light_for(ai_node, ai_dir.x == 0)
			var must_stop := st == Game.Light.RED or (st == Game.Light.YELLOW and to_line > v * v / 40.0 + 0.5)
			if must_stop and to_line < v * v / 24.0 + 4.0:
				_steer_to(ai_target)
				throttle = -1.0 if v > 0.3 else 0.0
				return
	else:
		var to := ai_target - global_position; to.y = 0
		if to.length() < 3.0:
			ai_node = ai_node + ai_dir
			ai_target = _exit_point()
			ai_phase = 0
			crossings += 1
	var diff := _steer_to(ai_target)
	var want := ai_speed * (0.55 if absf(diff) > 0.35 or ai_phase == 1 else 1.0)
	if ai_phase == 0 and Game.signalled(ai_node) and Game.light_for(ai_node, ai_dir.x == 0) != Game.Light.GREEN:
		var along2 := (Game.node_pos(ai_node) - global_position).dot(Vector3(ai_dir.x, 0, ai_dir.y)) - stop_dist()
		want = minf(want, maxf(4.0, along2 * 0.9))
	if _obstacle_ahead():
		throttle = -1.0 if speed() > 1.0 else 0.0
		wait_t += dt
		if wait_t > 14.0:
			ignore_t = 1.0; wait_t = 0.0
		return
	wait_t = 0.0
	var fs := velocity.dot(forward())
	throttle = clampf((want - fs) * 0.4, -1.0, 1.0)
	_unstick(dt)

## Original (v1) behaviour, no lights or right-of-way: kept for the before/after jam metric.
func _ai_traffic_v1(dt: float) -> void:
	var to := ai_target - global_position; to.y = 0
	if to.length() < 3.0:
		if ai_phase == 0:
			_commit(_choose_dir())
		else:
			ai_node = ai_node + ai_dir
			ai_target = _exit_point()
			ai_phase = 0
			crossings += 1
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
	if on_foot and dist < (14.0 if Game.wanted < 4 else 6.0):
		throttle = -1.0 if speed() > 2.0 else 0.0
	else:
		throttle = 1.0 if absf(diff) < 1.3 else 0.5
	_unstick(dt)
