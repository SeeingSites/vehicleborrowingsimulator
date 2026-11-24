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
var bust_t := 0.0
var police_cd := 0.0

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
	player = Player.new()
	add_child(player)
	player.global_position = Vector3(3 * Game.P + 6.25, 0.2, 3 * Game.P + 12.0)
	for s in city.parked_spots:
		var c := spawn_car(s[0], s[1], CAR_COLORS[Game.rng.randi() % CAR_COLORS.size()])
		c.ctrl = Car.Ctrl.NONE
	for i in n_traffic: spawn_traffic_random()
	for i in n_peds: spawn_ped(Vector2i(Game.rng.randi() % Game.NB, Game.rng.randi() % Game.NB))
	hud = load("res://scripts/hud.gd").new()
	add_child(hud)
	touch = load("res://scripts/touch.gd").new()
	hud.add_child(touch)
	Game.wanted_changed.connect(_on_wanted)
	if Game.shot != "":
		load("res://scripts/shots.gd").new().run(self, Game.shot)

func spawn_car(pos: Vector3, yaw: float, col: Color, police := false) -> Car:
	var c := Car.new()
	c.setup(col, police)
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

func spawn_traffic_random() -> Car:
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	while true:
		var n := Vector2i(Game.rng.randi_range(0, Game.NB), Game.rng.randi_range(0, Game.NB))
		var d: Vector2i = dirs[Game.rng.randi() % 4]
		if Game.in_grid(n + d):
			return spawn_traffic_at(n, d, Game.rng.randf_range(0.3, 0.7))
	return null

func spawn_ped(b: Vector2i) -> Ped:
	var p := Ped.new()
	add_child(p)
	p.setup(b)
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

func _physics_process(dt: float) -> void:
	if Input.is_action_just_pressed("enter_exit"):
		toggle_car()
	_police_logic(dt)
	_recycle()

func toggle_car() -> void:
	if player_car:
		var c := player_car
		c.ctrl = Car.Ctrl.NONE
		player_car = null
		player.global_position = c.global_position - c.global_transform.basis.x * 2.0 + Vector3(0, 0.2, 0)
		player.visible = true
		player.collision_layer = 4
		player.collision_mask = 1 | 2
		return
	var best: Car = null; var bd := 4.5
	for c in get_tree().get_nodes_in_group("cars"):
		var d: float = c.global_position.distance_to(player.global_position)
		if d < bd: bd = d; best = c
	if best == null: return
	enter_car(best)

func enter_car(c: Car) -> void:
	if c.ctrl == Car.Ctrl.TRAFFIC or c.ctrl == Car.Ctrl.POLICE:
		# carjack: throw the driver out
		var p := spawn_ped(Vector2i(clampi(int(c.global_position.x / Game.P), 0, Game.NB - 1), clampi(int(c.global_position.z / Game.P), 0, Game.NB - 1)))
		p.global_position = c.global_position + c.global_transform.basis.x * 2.2 + Vector3(0, 0.2, 0)
		if c.is_police: Game.add_wanted(2)
	c.ctrl = Car.Ctrl.PLAYER
	player_car = c
	player.visible = false
	player.collision_layer = 0
	player.collision_mask = 0

func _police_logic(dt: float) -> void:
	var cops := []
	for c in get_tree().get_nodes_in_group("cars"):
		if c.ctrl == Car.Ctrl.POLICE: cops.append(c)
	police_cd -= dt
	if Game.wanted > 0 and cops.size() < mini(Game.wanted, 4) and police_cd <= 0.0:
		police_cd = 3.0
		spawn_police_near(player_target().global_position)
	# busted: police car next to you while you're on foot or stopped
	var near := false
	for c in cops:
		var d: float = c.global_position.distance_to(player_target().global_position)
		var slow: bool = player_car == null or player_car.speed() < 2.0
		if d < (5.0 if player_car == null else 5.5) and slow: near = true
	bust_t = bust_t + dt if near else 0.0
	if bust_t > 1.0 and Game.wanted > 0:
		bust_t = 0.0
		Game.message.emit("BUSTED!", Color(0.4, 0.6, 1.0))
		Game.add_cash(-mini(Game.cash, 100))
		Game.set_wanted(0)
		if player_car: toggle_car()

func _recycle() -> void:
	for p in get_tree().get_nodes_in_group("dead_peds"):
		if p.dead_t > 20.0:
			p.queue_free()
			spawn_ped(Vector2i(Game.rng.randi() % Game.NB, Game.rng.randi() % Game.NB))

func _process(dt: float) -> void:
	var tgt := player_target()
	var vel: Vector3 = player_car.velocity if player_car else Vector3.ZERO
	var spd := vel.length()
	var want_h := lerpf(34.0, 66.0, clampf(spd / 30.0, 0.0, 1.0))
	cam_h = lerpf(cam_h, want_h, 1.0 - exp(-1.8 * dt))
	var look := tgt.global_position + vel * 0.45
	var want := Vector3(look.x, cam_h, look.z)
	cam.global_position = cam.global_position.lerp(want, 1.0 - exp(-6.0 * dt)) if cam.global_position.y > 1.0 else want
	cam.global_position.y = cam_h
