extends Node3D
## Weapons: pistol + SMG, pickups, hitscan shooting on foot and as forward drive-by.

const DEFS := {
	"pistol": {"rate": 0.32, "dmg": 26.0, "spread": 1.5, "range": 45.0, "pickup": 30, "color": Color(1.0, 0.85, 0.2), "snd": "pistol"},
	"smg":    {"rate": 0.085, "dmg": 11.0, "spread": 5.0, "range": 38.0, "pickup": 120, "color": Color(0.3, 0.7, 1.0), "snd": "smg"},
}
var ammo := {}           # weapon -> rounds
var current := ""
var cd := 0.0
var pickups: Array = []  # [node, weapon, respawn_t]
var m
var wanted_cd := 0.0
var auto_fire := false   # used by screenshot scripts
signal fired

func setup(main_) -> void:
	m = main_
	var r := RandomNumberGenerator.new(); r.seed = 99
	for i in 14:
		var b := Vector2i(r.randi() % Game.NB, r.randi() % Game.NB)
		var c := r.randi() % 4
		var pos: Vector3 = Ped._corner_pos(b, c)
		add_pickup(pos, "pistol" if i % 2 == 0 else "smg")

func add_pickup(pos: Vector3, w: String) -> Node3D:
	var n := Node3D.new()
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new(); bm.size = Vector3(1.1, 0.5, 1.1)
	mi.mesh = bm
	mi.material_override = Tex.mat_col(DEFS[w]["color"], true)
	n.add_child(mi)
	var inner := MeshInstance3D.new()
	var im := BoxMesh.new(); im.size = Vector3(0.75, 0.2, 0.25) if w == "pistol" else Vector3(1.0, 0.2, 0.3)
	inner.mesh = im
	inner.material_override = Tex.mat_col(Color(0.08, 0.08, 0.1))
	inner.position = Vector3(0, 0.32, 0)
	n.add_child(inner)
	add_child(n)
	n.global_position = pos + Vector3(0, 0.6, 0)
	pickups.append([n, w, 0.0])
	return n

func has_any() -> bool:
	return current != "" and ammo.get(current, 0) > 0

func cycle() -> void:
	var owned := []
	for w in ["pistol", "smg"]:
		if ammo.get(w, 0) > 0: owned.append(w)
	if owned.is_empty(): current = ""; return
	var i := owned.find(current)
	current = owned[(i + 1) % owned.size()]

func _physics_process(dt: float) -> void:
	cd -= dt
	wanted_cd -= dt
	var t := Time.get_ticks_msec() / 1000.0
	var who: Node3D = m.player_target()
	for p in pickups:
		var n: Node3D = p[0]
		if p[2] > 0.0:
			p[2] -= dt
			if p[2] <= 0.0: n.visible = true
			continue
		n.rotation.y = t * 2.0
		n.position.y = 0.6 + sin(t * 3.0) * 0.15
		if who.global_position.distance_to(n.global_position) < 2.4 and not m.player.dying:
			var w: String = p[1]
			ammo[w] = ammo.get(w, 0) + DEFS[w]["pickup"]
			if current == "" or ammo.get(current, 0) <= 0 or w == "smg": current = w
			n.visible = false
			p[2] = 30.0
			Game.message.emit(w.to_upper() + "!", DEFS[w]["color"])
			m.play_at("pickup", n.global_position, -2.0)
	if Input.is_action_just_pressed("weapon_next"): cycle()
	var firing := Input.is_action_pressed("fire") or auto_fire
	if firing and cd <= 0.0 and has_any() and not m.player.dying:
		shoot()

func muzzle() -> Array:
	if m.player_car:
		var c: Car = m.player_car
		return [c.global_position + c.forward() * 3.0 + Vector3(0, 1.0, 0), c.forward()]
	var p: Node3D = m.player
	var f := Vector3(-sin(p.rotation.y), 0, -cos(p.rotation.y))
	return [p.global_position + f * 0.8 + Vector3(0, 1.1, 0), f]

func shoot() -> void:
	var d: Dictionary = DEFS[current]
	cd = d["rate"]
	ammo[current] -= 1
	var mz := muzzle()
	var origin: Vector3 = mz[0]
	var dir: Vector3 = (mz[1] as Vector3).rotated(Vector3.UP, deg_to_rad(randf_range(-d["spread"], d["spread"])))
	var rng: float = d["range"]
	var end := origin + dir * rng
	var q := PhysicsRayQueryParameters3D.create(origin, end, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		end = hit.position; rng = origin.distance_to(end)
	# nearest target along the ray (peds have no colliders; cars use their footprint)
	var best = null; var bt := rng
	for p in get_tree().get_nodes_in_group("peds"):
		var tt := _ray_hit(origin, dir, p.global_position, 0.8, bt)
		if tt >= 0.0: best = p; bt = tt
	for c in get_tree().get_nodes_in_group("cars"):
		if c == m.player_car: continue
		var tt := _ray_hit(origin, dir, c.global_position, 1.7, bt)
		if tt >= 0.0: best = c; bt = tt
	end = origin + dir * bt
	if best is Ped:
		best.kill(dir * 6.0)
		m.play_at("splat", best.global_position, -2.0)
		Game.add_cash(10)
		_crime(1)
	elif best is Car:
		var c: Car = best
		c.take_damage(d["dmg"])
		c.velocity += dir * 0.4
		if c.ctrl == Car.Ctrl.TRAFFIC and c.speed() < 6.0:
			c.ignore_t = 0.5
		_crime(2 if c.is_police else 1)
		_spark(end, Color(1.0, 0.8, 0.3))
	else:
		_spark(end, Color(0.9, 0.9, 0.8))
	_tracer(origin, end, d["color"])
	m.play_at(d["snd"], origin, -3.0)
	fired.emit()

## Shooting peds/cars adds a star (at most one per 2.5 s); shooting police always does.
func _crime(stars: int) -> void:
	if stars > 1:
		Game.add_wanted(1)
		return
	if wanted_cd > 0.0: return
	wanted_cd = 2.5
	Game.add_wanted(1)

func _ray_hit(o: Vector3, d: Vector3, p: Vector3, radius: float, max_t: float) -> float:
	var rel := Vector3(p.x - o.x, 0, p.z - o.z)
	var t := rel.dot(d)
	if t < 0.0 or t > max_t: return -1.0
	if (rel - d * t).length() > radius: return -1.0
	return t

func _tracer(a: Vector3, b: Vector3, col: Color) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new(); bm.size = Vector3(0.28, 0.28, a.distance_to(b))
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = col.lightened(0.4)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = mat
	add_child(mi)
	mi.global_position = (a + b) * 0.5
	mi.look_at(b, Vector3.UP)
	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.8, 0.4); flash.omni_range = 7.0; flash.light_energy = 6.0
	var mf := MeshInstance3D.new(); var ms := SphereMesh.new(); ms.radius = 0.45; ms.height = 0.9; mf.mesh = ms
	var mm := StandardMaterial3D.new(); mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; mm.albedo_color = Color(1, 0.9, 0.5)
	mf.material_override = mm; flash.add_child(mf)
	add_child(flash)
	flash.global_position = a
	var tw := create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.2)
	tw.parallel().tween_property(flash, "light_energy", 0.0, 0.06)
	tw.tween_callback(mi.queue_free)
	tw.tween_callback(flash.queue_free)

func _spark(p: Vector3, col: Color) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new(); sm.radius = 0.35; sm.height = 0.7
	mi.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = col
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = mat
	add_child(mi)
	mi.global_position = p
	var tw := create_tween()
	tw.tween_property(mi, "scale", Vector3.ONE * 2.2, 0.15)
	tw.parallel().tween_property(mat, "albedo_color:a", 0.0, 0.15)
	tw.tween_callback(mi.queue_free)
