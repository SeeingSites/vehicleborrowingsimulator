extends Node3D
## Game root: builds the city, spawns player/traffic/peds/police, runs the chase camera.

const CAR_COLORS := [Color(0.85, 0.12, 0.10), Color(0.10, 0.35, 0.85), Color(0.95, 0.75, 0.10), Color(0.15, 0.6, 0.25),
	Color(0.9, 0.9, 0.9), Color(0.15, 0.15, 0.18), Color(0.55, 0.15, 0.6), Color(0.95, 0.45, 0.1), Color(0.3, 0.75, 0.85)]

var city: City
var player: Player
var player_car: Car = null
var cam: Camera3D
var cam_h := 30.0
var hud
var touch
var skids: MultiMeshInstance3D
var skid_i := 0
var n_traffic := 34
var n_peds := 90
var shake := 0.0
var weapons
var crime
var fps_t := 0.0
var engine_snd: AudioStreamPlayer
var skid_snd: AudioStreamPlayer
var horn_snd: AudioStreamPlayer

func _ready() -> void:
	Game.main = self
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.35, 0.5, 0.35)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.78, 0.9)
	e.ambient_light_energy = 0.42
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = 0.92
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-58, -35, 0)
	sun.light_energy = 0.95
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.shadow_enabled = true
	sun.shadow_opacity = 0.75
	sun.directional_shadow_max_distance = 140.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	add_child(sun)
	n_traffic = Game.traffic_cars
	city = City.new()
	add_child(city)
	city.build(42)
	_setup_skids()
	cam = Camera3D.new()
	cam.fov = 50.0
	cam.far = 300.0
	cam.rotation_degrees = Vector3(-90, 0, 0)
	add_child(cam)
	cam.make_current()
	get_viewport().size_changed.connect(_on_resize)
	_on_resize()
	player = Player.new()
	add_child(player)
	player.global_position = Vector3(3 * Game.P + 6.25, 0.2, 3 * Game.P + 12.0)
	for s in city.parked_spots:
		var c := spawn_car(s[0], s[1], CAR_COLORS[Game.rng.randi() % CAR_COLORS.size()])
		c.ctrl = Car.Ctrl.NONE
	for i in n_traffic: spawn_traffic_random()
	for i in n_peds: spawn_ped(Vector2i(Game.rng.randi() % Game.NB, Game.rng.randi() % Game.NB))
	weapons = load("res://scripts/weapons.gd").new()
	add_child(weapons)
	weapons.setup(self)
	crime = load("res://scripts/crime.gd").new()
	add_child(crime)
	crime.setup(self)
	hud = load("res://scripts/hud.gd").new()
	add_child(hud)
	touch = load("res://scripts/touch.gd").new()
	hud.add_child(touch)
	hud.touch_ui = touch
	Game.wanted_changed.connect(_on_wanted)
	engine_snd = _loop_player("engine", -10.0)
	skid_snd = _loop_player("skid", -12.0)
	horn_snd = _loop_player("horn", -6.0)
	if Game.sim_seconds > 0.0:
		load("res://scripts/sim.gd").new().run(self)
	if Game.test:
		# watchdog: a script error in the checks must fail the run, not hang it
		get_tree().create_timer(600.0, true, false, true).timeout.connect(func():
			print("TESTS timed out"); get_tree().quit(2))
		var tests = load("res://scripts/tests.gd")
		if tests == null or not tests.can_instantiate():
			print("TESTS could not load scripts/tests.gd"); get_tree().quit(2)
		else:
			tests.new().run(self)
	if Game.shot != "":
		load("res://scripts/shots.gd").new().run(self, Game.shot)

const TRAFFIC_MIX := ["sedan", "sedan", "sedan", "taxi", "taxi", "sports", "hatchback", "suv", "van", "truck"]

func random_type() -> String:
	return TRAFFIC_MIX[Game.rng.randi() % TRAFFIC_MIX.size()]

func spawn_car(pos: Vector3, yaw: float, col: Color, police := false, type := "") -> Car:
	var c := Car.new()
	c.setup(col, police, type if type != "" else random_type())
	add_child(c)
	c.global_position = Vector3(pos.x, 0, pos.z)
	c.rotation.y = yaw
	return c

func spawn_traffic_at(node: Vector2i, dir: Vector2i, t: float) -> Car:
	var a := Game.node_pos(node); var b := Game.node_pos(node + dir)
	var pos := a.lerp(b, t) + Game.right_of(dir) * Game.LANE
	var c := spawn_car(pos, Game.yaw_of(Vector3(dir.x, 0, dir.y)), CAR_COLORS[Game.rng.randi() % CAR_COLORS.size()])
	c.start_traffic(node, dir)
	c.velocity = c.forward() * 8.0
	return c

## Spawns a traffic car on a random lane segment that is clear of other cars and at least
## `min_d` from `avoid` (used to keep respawns out of the player's view). Returns null if no slot.
func spawn_traffic_random(avoid := Vector3.ZERO, min_d := 0.0) -> Car:
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for k in 64:
		var n := Vector2i(Game.rng.randi_range(0, Game.NB), Game.rng.randi_range(0, Game.NB))
		var d: Vector2i = dirs[Game.rng.randi() % 4]
		if not Game.in_grid(n + d): continue
		var t := Game.rng.randf_range(0.3, 0.7)
		var pos := Game.node_pos(n).lerp(Game.node_pos(n + d), t) + Game.right_of(d) * Game.LANE
		if min_d > 0.0 and pos.distance_to(avoid) < min_d: continue
		if _car_near(pos, 7.0): continue
		return spawn_traffic_at(n, d, t)
	return null

func _car_near(pos: Vector3, r: float) -> bool:
	for c in get_tree().get_nodes_in_group("cars"):
		if c.global_position.distance_to(pos) < r: return true
	return false

func spawn_ped(b: Vector2i, role := "civ", gang := -1) -> Ped:
	var p := Ped.new()
	add_child(p)
	p.setup(b, role, gang)
	return p

func spawn_police_near(pos: Vector3, min_d := 45.0, max_d := 80.0) -> Car:
	var best := Vector2i(-1, -1)
	for k in 40:
		var n := Vector2i(Game.rng.randi_range(0, Game.NB), Game.rng.randi_range(0, Game.NB))
		var d := Game.node_pos(n).distance_to(pos)
		if d > min_d and d < max_d:
			best = n; break
	if best.x < 0: return null
	var c := spawn_car(Game.node_pos(best) + Vector3(Game.LANE, 0, 0), 0.0, Color.WHITE, true)
	c.start_police()
	return c

func player_target() -> Node3D:
	return player_car if player_car else player

func _on_wanted(level: int) -> void:
	if level == 0:
		for c in get_tree().get_nodes_in_group("cars"):
			if c.ctrl == Car.Ctrl.POLICE:
				var n := Vector2i(clampi(roundi(c.global_position.x / Game.P), 0, Game.NB - 1), clampi(roundi(c.global_position.z / Game.P), 0, Game.NB))
				c.start_traffic(n, Vector2i(1, 0))

func _setup_skids() -> void:
	skids = MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var q := BoxMesh.new(); q.size = Vector3(2.0, 0.01, 0.7)
	mm.mesh = q
	mm.instance_count = 600
	mm.visible_instance_count = 0
	skids.multimesh = mm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.05, 0.05, 0.05, 0.55)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	skids.material_override = m
	add_child(skids)

func add_skid(pos: Vector3, yaw: float) -> void:
	var mm := skids.multimesh
	var y := 0.02 if (pos.x - roundf(pos.x / Game.P) * Game.P) ** 2 < 30.0 or (pos.z - roundf(pos.z / Game.P) * Game.P) ** 2 < 30.0 else 0.22
	mm.set_instance_transform(skid_i, Transform3D(Basis(Vector3.UP, yaw), Vector3(pos.x, y, pos.z) + Basis(Vector3.UP, yaw) * Vector3(0, 0, 1.3)))
	skid_i = (skid_i + 1) % mm.instance_count
	mm.visible_instance_count = maxi(mm.visible_instance_count, skid_i)

func _loop_player(name: String, db: float) -> AudioStreamPlayer:
	var a := AudioStreamPlayer.new()
	a.stream = Sfx.get_stream(name)
	a.volume_db = db
	add_child(a)
	return a

func play_at(name: String, pos: Vector3, db := 0.0) -> void:
	if Game.sim_seconds > 0.0: return
	if cam and cam.global_position.distance_to(pos) > 160.0: return
	var a := AudioStreamPlayer3D.new()
	a.stream = Sfx.get_stream(name)
	a.unit_size = 40.0
	a.max_distance = 180.0
	a.volume_db = db
	add_child(a)
	a.global_position = pos
	a.play()
	a.finished.connect(a.queue_free)

func _update_audio() -> void:
	var c := player_car
	if c and not c.dead:
		if not engine_snd.playing: engine_snd.play()
		var k := clampf(c.speed() / c.max_speed, 0.0, 1.0)
		engine_snd.pitch_scale = 0.7 + k * 1.9 + absf(c.throttle) * 0.15
		engine_snd.volume_db = -14.0 + k * 6.0 + absf(c.throttle) * 3.0
		var sk := c.drifting and c.speed() > 7.0
		if sk and not skid_snd.playing: skid_snd.play()
		elif not sk and skid_snd.playing: skid_snd.stop()
		var hn := Input.is_action_pressed("horn")
		if hn and not horn_snd.playing: horn_snd.play()
		elif not hn and horn_snd.playing: horn_snd.stop()
	else:
		for a in [engine_snd, skid_snd, horn_snd]:
			if a.playing: a.stop()

## Fireball, flash, debris, scorch mark, sound and blast damage.
func explosion(pos: Vector3, src: Node, blame := false) -> void:
	play_at("explosion", pos, 6.0)
	shake = 0.6
	var root := Node3D.new()
	add_child(root)
	root.global_position = pos
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.7, 0.3); light.omni_range = 22.0; light.light_energy = 10.0
	light.position = Vector3(0, 4, 0)
	root.add_child(light)
	var balls := []
	for spec in [[Color(1.0, 0.95, 0.6), 0.7], [Color(1.0, 0.55, 0.1), 1.0], [Color(0.6, 0.15, 0.05), 1.3]]:
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new(); sm.radius = 1.0; sm.height = 2.0
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(spec[0], 0.8)
		mi.mesh = sm; mi.material_override = m
		mi.position = Vector3(0, 1.5, 0)
		mi.scale = Vector3.ONE * 0.5
		root.add_child(mi)
		balls.append([mi, m, spec[1]])
	var debris := CPUParticles3D.new()
	var dm := BoxMesh.new(); dm.size = Vector3(0.35, 0.35, 0.35)
	dm.material = Tex.mat_col(Color(0.12, 0.1, 0.08))
	debris.mesh = dm; debris.amount = 40; debris.lifetime = 1.4; debris.one_shot = true; debris.explosiveness = 1.0
	debris.direction = Vector3(0, 1, 0); debris.spread = 80.0
	debris.initial_velocity_min = 8.0; debris.initial_velocity_max = 18.0
	debris.position = Vector3(0, 1, 0)
	root.add_child(debris)
	debris.emitting = true
	var flames := CPUParticles3D.new()
	var fm := SphereMesh.new(); fm.radius = 0.8; fm.height = 1.6; fm.radial_segments = 8; fm.rings = 4
	var fmat := StandardMaterial3D.new()
	fmat.vertex_color_use_as_albedo = true
	fmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.material = fmat
	flames.mesh = fm; flames.amount = 70; flames.lifetime = 1.1; flames.one_shot = true; flames.explosiveness = 0.95
	flames.direction = Vector3(0, 1, 0); flames.spread = 90.0
	flames.initial_velocity_min = 3.0; flames.initial_velocity_max = 11.0
	flames.damping_min = 6.0; flames.damping_max = 9.0
	flames.gravity = Vector3(0, 2.0, 0)
	flames.scale_amount_min = 0.8; flames.scale_amount_max = 2.2
	var fc := Curve.new(); fc.add_point(Vector2(0, 0.6)); fc.add_point(Vector2(0.4, 1.0)); fc.add_point(Vector2(1, 1.4))
	flames.scale_amount_curve = fc
	var fg := Gradient.new()
	fg.set_color(0, Color(1.0, 0.95, 0.55, 1.0)); fg.set_color(1, Color(0.15, 0.12, 0.1, 0.0))
	fg.add_point(0.3, Color(1.0, 0.55, 0.1, 0.95)); fg.add_point(0.6, Color(0.5, 0.15, 0.05, 0.7))
	flames.color_ramp = fg
	flames.position = Vector3(0, 1.2, 0)
	flames.local_coords = false
	root.add_child(flames)
	flames.emitting = true
	var scorch := MeshInstance3D.new()
	var cm := CylinderMesh.new(); cm.top_radius = 4.0; cm.bottom_radius = 4.0; cm.height = 0.02
	var sm2 := StandardMaterial3D.new(); sm2.albedo_color = Color(0.05, 0.04, 0.03, 0.7)
	sm2.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	scorch.mesh = cm; scorch.material_override = sm2
	add_child(scorch)
	scorch.global_position = Vector3(pos.x, 0.03, pos.z)
	var tw := create_tween().set_parallel(true)
	for b in balls:
		tw.tween_property(b[0], "scale", Vector3.ONE * 3.2 * b[2], 0.45).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
		tw.tween_property(b[1], "albedo_color:a", 0.0, 0.9).set_delay(0.25)
	tw.tween_property(light, "light_energy", 0.0, 0.9)
	tw.chain().tween_callback(root.queue_free).set_delay(1.8)
	# blast damage
	for c in get_tree().get_nodes_in_group("cars"):
		if c == src or c.dead: continue
		var d: float = c.global_position.distance_to(pos)
		if d < 10.0:
			if blame: c.blame_t = Game.clock   # chain reactions stay the player's doing
			c.take_damage(95.0 * (1.0 - d / 10.0))
			c.velocity += (c.global_position - pos).normalized() * 12.0 * (1.0 - d / 10.0)
	for p in get_tree().get_nodes_in_group("peds"):
		var d: float = p.global_position.distance_to(pos)
		if d < 7.0 and p.alive: p.kill((p.global_position - pos).normalized(), blame)
	if src == player_car or (player.visible and player.global_position.distance_to(pos) < 6.5):
		wasted()

var god := false   # tests only
func wasted() -> void:
	if player.dying or god: return
	player.dying = true
	player.health = 0.0
	if player_car:
		var c := player_car
		c.ctrl = Car.Ctrl.NONE
		player.global_position = c.global_position
		player_car = null
	else:
		player.rotation.x = PI / 2   # knocked flat
	Engine.time_scale = 0.4
	hud.show_wasted(true)
	await get_tree().create_timer(4.0, true, false, true).timeout
	Engine.time_scale = 1.0
	hud.show_wasted(false)
	Game.set_wanted(0)
	respawn_at(crime.hospital_pos)
	crime.after_wasted()

func respawn_at(pos: Vector3) -> void:
	player.rotation = Vector3.ZERO
	player.global_position = Vector3(pos.x, 0.2, pos.z)
	player.visible = true
	player.collision_layer = 4
	player.collision_mask = 1 | 2
	player.health = 100.0
	player.dying = false
	player.busy = false
	cam.global_position = Vector3(pos.x, cam_h, pos.z)

# ---- spatial grid: cars/peds bucketed by cell, rebuilt once per physics tick (main runs before
# its children), so the AI's neighbour checks don't scan every car and ped for every car. ----
const CELL := 16.0
var _grid_cars := {}
var _grid_peds := {}

func _rebuild_grid() -> void:
	_grid_cars.clear(); _grid_peds.clear()
	for c in get_tree().get_nodes_in_group("cars"): _bucket(_grid_cars, c)
	for p in get_tree().get_nodes_in_group("peds"): _bucket(_grid_peds, p)

func _bucket(g: Dictionary, n: Node3D) -> void:
	var k := Vector2i(floori(n.global_position.x / CELL), floori(n.global_position.z / CELL))
	if g.has(k): g[k].append(n)
	else: g[k] = [n]

func _query(g: Dictionary, p: Vector3, r: float) -> Array:
	var out := []
	var x0 := floori((p.x - r) / CELL); var x1 := floori((p.x + r) / CELL)
	var z0 := floori((p.z - r) / CELL); var z1 := floori((p.z + r) / CELL)
	for x in range(x0, x1 + 1):
		for z in range(z0, z1 + 1):
			var b = g.get(Vector2i(x, z))
			if b != null:
				for n in b:
					if is_instance_valid(n): out.append(n)
	return out

## Cars / peds in the grid cells overlapping a circle of radius r (callers do the exact test).
func near_cars(p: Vector3, r: float) -> Array: return _query(_grid_cars, p, r)
func near_peds(p: Vector3, r: float) -> Array: return _query(_grid_peds, p, r)

func _physics_process(dt: float) -> void:
	_rebuild_grid()
	if Input.is_action_just_pressed("enter_exit") and not player.dying:
		toggle_car()
	if city.lamp_mats.size() > 0: city.update_lamps()
	if player_car: player.global_position = player_car.global_position + Vector3(0, 0.2, 0)
	_update_audio()
	_recycle()

func toggle_car() -> void:
	if not crime.breaking.is_empty(): return
	if crime.interact(): return
	if player_car:
		var c := player_car
		c.ctrl = Car.Ctrl.NONE
		player_car = null
		player.global_position = _exit_spot(c)
		player.visible = true
		player.collision_layer = 4
		player.collision_mask = 1 | 2
		return
	var best: Car = null; var bd := 4.5
	for c in get_tree().get_nodes_in_group("cars"):
		if c.dead: continue
		var d: float = c.global_position.distance_to(player.global_position)
		if d < bd: bd = d; best = c
	if best == null: return
	enter_car(best)

## Where to put the player when leaving `c`: driver side, else passenger side, else front/back,
## whichever isn't blocked by a building or another car.
func _exit_spot(c: Car) -> Vector3:
	var b := c.global_transform.basis
	var from := c.global_position + Vector3(0, 1.0, 0)
	var space := get_world_3d().direct_space_state
	for off in [-b.x * 2.0, b.x * 2.0, -b.z * 4.0, b.z * 4.0]:
		var q := PhysicsRayQueryParameters3D.create(from, from + off + off.normalized() * 0.6, 1 | 2, [c.get_rid()])
		if space.intersect_ray(q).is_empty():
			return c.global_position + off + Vector3(0, 0.2, 0)
	return c.global_position - b.x * 2.0 + Vector3(0, 0.2, 0)

func enter_car(c: Car, forced := false) -> void:
	if c.dead: return
	var owned: bool = c.get_meta("owned", false)
	if c.ctrl == Car.Ctrl.TRAFFIC or c.ctrl == Car.Ctrl.POLICE:
		# carjack: pull the driver out (a cop driver gets out on foot and fights back)
		var cop: bool = c.is_police or c.has_meta("swat")
		var p := spawn_ped(Game.block_of(c.global_position), "cop" if cop else "civ")
		p.global_position = c.global_position + c.global_transform.basis.x * 2.2 + Vector3(0, 0.15, 0)
		if not cop:
			p.stun(1.2)
		c.set_meta("owned", true)
		if Game.shot == "" or forced: crime.car_stolen(c, "jack", p)
	elif not owned and not forced and Game.shot == "":
		crime.start_break_in(c)
		return
	elif not owned and forced:
		crime.car_stolen(c, "parked")
	c.set_meta("owned", true)
	c.ctrl = Car.Ctrl.PLAYER
	player_car = c
	player.visible = false
	player.collision_layer = 0
	player.collision_mask = 0

func _recycle() -> void:
	for w in get_tree().get_nodes_in_group("wrecks"):
		w.set_meta("age", w.get_meta("age", 0.0) + get_physics_process_delta_time())
		if w.get_meta("age") > 60.0 and w != player_car and w.global_position.distance_to(cam.global_position) > 70.0:
			w.queue_free()
	var live := 0
	var dt := get_physics_process_delta_time()
	var mission_car = crime.mission.get("target") if crime else null
	for c in get_tree().get_nodes_in_group("cars"):
		if c.ctrl == Car.Ctrl.TRAFFIC and not c.dead: live += 1
		# cars the player stole and left behind: remove after a minute out of sight
		elif c.ctrl == Car.Ctrl.NONE and not c.dead and c.get_meta("owned", false) and c != player_car and c != mission_car:
			var idle: float = c.get_meta("idle", 0.0)
			idle = idle + dt if c.global_position.distance_to(cam.global_position) > 90.0 else 0.0
			c.set_meta("idle", idle)
			if idle > 60.0: c.queue_free()
	if live < n_traffic and Game.shot == "":
		spawn_traffic_random(player_target().global_position, 45.0)
	for p in get_tree().get_nodes_in_group("dead_peds"):
		if p.dead_t > 20.0:
			p.queue_free()
			if p.role == "civ": spawn_ped(Vector2i(Game.rng.randi() % Game.NB, Game.rng.randi() % Game.NB))

func _process(dt: float) -> void:
	if OS.has_feature("web") or OS.get_environment("FPSLOG") != "":
		fps_t += dt
		if fps_t > 5.0:
			fps_t = 0.0
			print("FPS %d draws %d objs %d" % [Engine.get_frames_per_second(), Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)])
	var tgt := player_target()
	var vel: Vector3 = player_car.velocity if player_car else Vector3.ZERO
	var spd := vel.length()
	var want_h := lerpf(34.0, 66.0, clampf(spd / 30.0, 0.0, 1.0))
	cam_h = lerpf(cam_h, want_h, 1.0 - exp(-1.8 * dt))
	var look := tgt.global_position + vel * 0.45
	var want := Vector3(look.x, cam_h, look.z)
	cam.global_position = cam.global_position.lerp(want, 1.0 - exp(-6.0 * dt)) if cam.global_position.y > 1.0 else want
	cam.global_position.y = cam_h
	if shake > 0.0:
		shake -= dt
		cam.global_position += Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * shake * 1.5


# Portrait phones: keep the UI at a sane scale and widen the camera so the
# street view isn't a narrow slit.
func _on_resize() -> void:
	var ws := DisplayServer.window_get_size()
	var portrait := ws.y > ws.x
	get_window().content_scale_size = Vector2i(720, 1280) if portrait else Vector2i(1280, 720)
	cam.keep_aspect = Camera3D.KEEP_WIDTH if portrait else Camera3D.KEEP_HEIGHT
	cam.fov = 65.0 if portrait else 50.0
