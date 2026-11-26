extends Node3D
## v4 crime loop (GTA2-style):
##  * car theft: break into parked cars (alarm), pull drivers out; stars if a cop or a bystander sees it
##  * escalating police: cop cars -> cops on foot -> armed cops (3*) -> roadblocks (4*) -> SWAT vans (5-6*)
##  * evasion: stars only decay while no cop can see you; respray shop clears heat for cash
##  * busted (police station, weapons confiscated, fine) vs wasted (hospital bill, keep weapons)
##  * payphone missions per gang, gated by respect; three gangs with turf and rivalries
##  * cash multiplier, mugging, car crusher, weapon shop (Ammu-Nation style), kill frenzy

const COP_CARS := [0, 1, 2, 3, 4, 4, 4]
const SWAT_VANS := [0, 0, 0, 0, 0, 1, 2]
const CAR_VALUE := {"sedan": 400, "sports": 1200, "hatchback": 500, "taxi": 450, "suv": 800, "van": 600, "truck": 900, "police": 1500}
const SHOP := [["pistol", 150, 30], ["smg", 400, 120], ["shotgun", 600, 16]]
const RESPRAY_COST := 500
const REPAIR_COST := 150
const TINTS := [Color(0.8, 0.1, 0.1), Color(0.1, 0.3, 0.85), Color(0.1, 0.55, 0.2), Color(0.95, 0.75, 0.1), Color(0.5, 0.15, 0.6), Color(0.15, 0.15, 0.18), Color(0.92, 0.92, 0.92)]
const MISSIONS := [
	[{"kind": "steal", "car": "sports", "time": 150.0, "pay": 1500, "title": "HOT WHEELS"},
	 {"kind": "hit", "time": 120.0, "pay": 2500, "title": "SAINTS' DAY"}],
	[{"kind": "hit", "time": 120.0, "pay": 1500, "title": "SNAKE HUNT"},
	 {"kind": "run", "n": 5, "time": 80.0, "pay": 2500, "title": "SPEED RUN"}],
	[{"kind": "run", "n": 4, "time": 70.0, "pay": 1200, "title": "BURN RUBBER"},
	 {"kind": "steal", "car": "police", "time": 180.0, "pay": 3000, "title": "COP SHOP"}],
]
const UNLOCK_RESPECT := 20
const HATE_RESPECT := -25

var m
var respray_pos := Vector3.ZERO
var crusher_pos := Vector3.ZERO
var drop_pos := Vector3.ZERO
var hospital_pos := Vector3.ZERO
var police_pos := Vector3.ZERO
var shop_pads := []            # [pos, weapon, price, rounds]
var phones := []               # [pos, gang, node, light]
var skull: Node3D
var skull_cd := 0.0
var frenzy := {}               # {t, need, got}
var mission := {}              # active mission
var mission_done := [0, 0, 0]
var beacon: MeshInstance3D
var checkpoint: Node3D
var breaking := {}             # {car, t}
var bust_t := 0.0
var police_cd := 0.0
var rb_cd := 0.0
var see_t := 0.0
var pad_lock := ""             # facility we're standing on (fires once per visit)
var crush_t := 0.0
var turf := -2
var zone_msg := ""
var zone_t := 0.0
var busy := false
var last_event := ""           # for tests
var no_bust := false           # tests / screenshots

func setup(main_) -> void:
	m = main_
	Game.ped_killed.connect(_on_killed)
	_place_facilities()
	for g in 3:
		for k in 6: spawn_gang(g, true)

# ---------------------------------------------------------------- facilities
func _sidewalk_mid(b: Vector2i, side: int) -> Vector3:
	var lo := Game.ROAD_HALF + Game.WALK * 0.5
	var cx := (b.x + 0.5) * Game.P; var cz := (b.y + 0.5) * Game.P
	var h := Game.P * 0.5 - lo
	match side:
		0: return Vector3(cx, 0.2, cz - h)   # north
		1: return Vector3(cx + h, 0.2, cz)   # east
		2: return Vector3(cx, 0.2, cz + h)   # south
		_: return Vector3(cx - h, 0.2, cz)   # west

func _place_facilities() -> void:
	var lots := []
	var parks := []
	var ctr := Vector2(Game.NB * 0.5, Game.NB * 0.5)
	for b in m.city.block_kind:
		if m.city.block_kind[b] == "parking": lots.append(b)
		elif m.city.block_kind[b] == "park": parks.append(b)
	var by_ctr := func(a, b): return Vector2(a).distance_to(ctr) < Vector2(b).distance_to(ctr)
	lots.sort_custom(by_ctr); parks.sort_custom(by_ctr)
	var open_blocks: Array = lots + parks
	while open_blocks.size() < 3: open_blocks.append(Vector2i(open_blocks.size(), 0))
	var bc := func(b: Vector2i) -> Vector3: return Vector3((b.x + 0.5) * Game.P, 0.22, (b.y + 0.5) * Game.P)
	respray_pos = bc.call(open_blocks[0])
	crusher_pos = bc.call(open_blocks[1])
	drop_pos = bc.call(open_blocks[2])
	_garage(respray_pos, Color(0.25, 0.6, 1.0), "PAY 'N' SPRAY")
	_garage(crusher_pos, Color(0.95, 0.8, 0.1), "CAR CRUSHER")
	_pad(drop_pos, Color(1.0, 0.85, 0.2), 4.0, "DROP-OFF", 0.0)
	print("CRIME facilities respray=", open_blocks[0], " crusher=", open_blocks[1], " drop=", open_blocks[2])
	# weapon shop: three pads on the north sidewalk of a neutral block
	var shop_b := Vector2i(3, 3)
	var sp := _sidewalk_mid(shop_b, 2)
	for i in SHOP.size():
		var p := sp + Vector3((i - 1) * 4.6, 0, 0)
		var w: String = SHOP[i][0]
		_pad(p, m.weapons.DEFS[w]["color"], 1.2, "", 0.0)
		_sign(p, "%s\n$%d" % [w.to_upper(), SHOP[i][1]], m.weapons.DEFS[w]["color"], 2.4).font_size = 40
		shop_pads.append([p, w, SHOP[i][1], SHOP[i][2]])
	_sign(sp + Vector3(0, 0, -1.6), "AMMU", Color(1, 0.3, 0.2), 6.5)
	# gang payphones
	var phone_blocks := [Vector2i(1, 3), Vector2i(6, 4), Vector2i(4, 6)]
	for g in 3:
		var p := _sidewalk_mid(phone_blocks[g], 1 if g == 0 else 3)
		phones.append([p, g] + _phone_booth(p, g))
	hospital_pos = _sidewalk_mid(Vector2i(1, 6), 0)
	police_pos = _sidewalk_mid(Vector2i(6, 1), 2)
	_pad(hospital_pos, Color(1, 1, 1), 1.6, "", 0.0)
	_sign(hospital_pos + Vector3(0, 0, 0.5), "+ HOSPITAL", Color(1, 0.25, 0.25), 5.0)
	_pad(police_pos, Color(0.3, 0.45, 1.0), 1.6, "", 0.0)
	_sign(police_pos, "POLICE", Color(0.4, 0.6, 1.0), 5.0)
	# kill frenzy skull
	skull = _skull(_sidewalk_mid(Vector2i(3, 2), 2) + Vector3(-6, 0, 0))

func _mat(col: Color, a := 1.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(col, a)
	if a < 1.0: mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return mat

func _sign(p: Vector3, text: String, col: Color, h: float) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = 64
	l.outline_size = 22
	l.modulate = col
	l.pixel_size = 0.014
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	add_child(l)
	l.global_position = p + Vector3(0, h, 0)
	return l

func _pad(p: Vector3, col: Color, r: float, text: String, h: float) -> Node3D:
	var n := Node3D.new()
	add_child(n)
	n.global_position = p
	var ring := MeshInstance3D.new()
	var cm := CylinderMesh.new(); cm.top_radius = r; cm.bottom_radius = r; cm.height = 0.04
	ring.mesh = cm; ring.material_override = _mat(col, 0.45)
	ring.position = Vector3(0, 0.05 + h, 0)
	n.add_child(ring)
	var edge := MeshInstance3D.new()
	var tm := TorusMesh.new(); tm.inner_radius = r - 0.18; tm.outer_radius = r
	edge.mesh = tm; edge.material_override = _mat(col)
	edge.position = Vector3(0, 0.08 + h, 0)
	n.add_child(edge)
	if text != "": _sign(p, text, col, 2.6)
	return n

func _garage(p: Vector3, col: Color, text: String) -> void:
	_pad(p, col, 4.0, "", 0.0)
	var frame := Tex.mat_col(Color(0.25, 0.25, 0.28))
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			var post := MeshInstance3D.new(); var bm := BoxMesh.new(); bm.size = Vector3(0.4, 4.0, 0.4)
			post.mesh = bm; post.material_override = frame
			add_child(post)
			post.global_position = p + Vector3(sx * 4.2, 2.0, sz * 4.2)
	for sz in [-1, 1]:
		var beam := MeshInstance3D.new(); var bb := BoxMesh.new(); bb.size = Vector3(8.8, 0.5, 0.5)
		beam.mesh = bb; beam.material_override = _mat(col)
		add_child(beam)
		beam.global_position = p + Vector3(0, 4.1, sz * 4.2)
	_sign(p, text, col, 6.0)

func _phone_booth(p: Vector3, g: int) -> Array:
	var col: Color = Game.GANGS[g]["col"]
	var booth := MeshInstance3D.new(); var bm := BoxMesh.new(); bm.size = Vector3(0.9, 2.4, 0.9)
	booth.mesh = bm; booth.material_override = Tex.mat_col(col.darkened(0.3))
	add_child(booth)
	booth.global_position = p + Vector3(0, 1.2, 0)
	var top := MeshInstance3D.new(); var tb := BoxMesh.new(); tb.size = Vector3(1.1, 0.3, 1.1)
	top.mesh = tb; top.material_override = _mat(col)
	booth.add_child(top); top.position = Vector3(0, 1.3, 0)
	var light := OmniLight3D.new(); light.light_color = col; light.omni_range = 6.0; light.light_energy = 0.0
	booth.add_child(light); light.position = Vector3(0, 2.0, 0)
	_sign(p, "☎ " + String(Game.GANGS[g]["short"]), col, 3.6).font_size = 48
	return [booth, light]

func _skull(p: Vector3) -> Node3D:
	var n := Node3D.new()
	add_child(n)
	n.global_position = p + Vector3(0, 0.9, 0)
	var head := MeshInstance3D.new(); var sm := SphereMesh.new(); sm.radius = 0.55; sm.height = 1.0
	head.mesh = sm; head.material_override = _mat(Color(0.95, 0.95, 0.9))
	n.add_child(head)
	for sx in [-1, 1]:
		var eye := MeshInstance3D.new(); var eb := BoxMesh.new(); eb.size = Vector3(0.22, 0.2, 0.22)
		eye.mesh = eb; eye.material_override = _mat(Color(0.8, 0.0, 0.0))
		n.add_child(eye); eye.position = Vector3(sx * 0.2, 0.5, -0.25)
	var l := Label3D.new(); l.text = "KILL FRENZY"; l.font_size = 40; l.outline_size = 16; l.modulate = Color(1, 0.2, 0.2)
	l.pixel_size = 0.014; l.billboard = BaseMaterial3D.BILLBOARD_ENABLED; l.no_depth_test = true; l.position = Vector3(0, 2.0, 0)
	n.add_child(l)
	return n

# ---------------------------------------------------------------- helpers
func los(a: Vector3, b: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(a + Vector3(0, 1.2, 0), b + Vector3(0, 1.2, 0), 1)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()

func is_cop_car(c) -> bool:
	return not c.dead and (c.ctrl == Car.Ctrl.POLICE or c.has_meta("roadblock"))

func foot_cops() -> Array:
	var out := []
	for p in get_tree().get_nodes_in_group("armed"):
		if p.alive and (p.role == "cop" or p.role == "swat") and not p.is_queued_for_deletion(): out.append(p)
	return out

## "COP" if police can see `pos`, "WITNESS" if a bystander is close, else "".
func witnessed(pos: Vector3, exclude = null) -> String:
	for c in get_tree().get_nodes_in_group("cars"):
		if is_cop_car(c) and c.global_position.distance_to(pos) < 35.0 and los(c.global_position, pos): return "COP"
	for p in foot_cops():
		if p.global_position.distance_to(pos) < 35.0 and los(p.global_position, pos): return "COP"
	for p in get_tree().get_nodes_in_group("peds"):
		if p != exclude and p.alive and p.role == "civ" and p.stun_t <= 0.0 and p.global_position.distance_to(pos) < 7.0: return "WITNESS"
	return ""

func spawn_gang(g: int, initial := false) -> Ped:
	var blocks := []
	for bx in Game.NB:
		for by in Game.NB:
			var b := Vector2i(bx, by)
			if Game.gang_at_block(b) != g: continue
			if not initial and Game.node_pos(b).distance_to(m.player_target().global_position) < 40.0: continue
			blocks.append(b)
	if blocks.is_empty(): return null
	return m.spawn_ped(blocks[Game.rng.randi() % blocks.size()], "gang", g)

func spawn_cop(pos: Vector3, role := "cop") -> Ped:
	if foot_cops().size() >= 14: return null
	var p: Ped = m.spawn_ped(Game.block_of(pos), role)
	p.global_position = Vector3(pos.x, 0.15, pos.z)
	return p

# ---------------------------------------------------------------- theft
func start_break_in(c: Car) -> void:
	breaking = {"car": c, "t": 1.1}
	m.player.busy = true
	Game.message.emit("BREAKING IN...", Color(1, 1, 1))
	if Game.rng.randf() < 0.5 or c.is_police:
		m.play_at("alarm", c.global_position, -2.0)
		c.set_meta("alarm", true)
		for p in get_tree().get_nodes_in_group("peds"):
			if p.role == "civ" and p.alive and p.global_position.distance_to(c.global_position) < 15.0: p.flee_t = 6.0

## Called by main.enter_car once the player is in a car that wasn't theirs.
func car_stolen(c: Car, how: String, driver = null) -> void:
	var w := witnessed(c.global_position, driver)
	if c.has_meta("alarm") and w == "": w = "WITNESS" if Game.rng.randf() < 0.5 else ""
	if c.is_police:
		Game.add_wanted(2)
		last_event = "steal_police"
		Game.reward(100, "STOLE A COP CAR", Color(0.5, 0.7, 1.0))
		return
	if w != "":
		Game.add_wanted(1)
		Game.message.emit("CAR THEFT — " + ("COPS SAW YOU" if w == "COP" else "WITNESSED"), Color(1, 0.5, 0.4))
	else:
		Game.reward(25, "CAR " + ("JACKED" if how == "jack" else "STOLEN"))
	last_event = "steal_" + how + ("_seen" if w != "" else "")

func mugged(p: Ped) -> void:
	var amt := Game.rng.randi_range(8, 40)
	Game.reward(amt, "MUGGED")
	m.play_at("cash", p.global_position, -4.0)
	var w := witnessed(p.global_position, p)
	if w == "COP": Game.add_wanted(1)
	for q in get_tree().get_nodes_in_group("peds"):
		if q != p and q.role == "civ" and q.alive and q.global_position.distance_to(p.global_position) < 12.0: q.flee_t = 5.0
	last_event = "mugged"

# ---------------------------------------------------------------- kills / gangs / frenzy
func _on_killed(p: Ped, by_player: bool) -> void:
	if not mission.is_empty() and mission["kind"] == "hit" and p == mission.get("target"):
		# the job is yours to do: traffic or a gang war getting him first doesn't count
		if by_player: _mission_pass()
		else: _mission_fail("SOMEONE ELSE GOT HIM")
	if not by_player: return
	if not frenzy.is_empty():
		frenzy["got"] += 1
		if frenzy["got"] >= frenzy["need"]:
			Game.reward(2000, "FRENZY PASSED!", Color(1, 0.3, 0.3))
			Game.mult = mini(Game.mult + 1, Game.MULT_MAX)
			frenzy = {}
			last_event = "frenzy_pass"
	match p.role:
		"civ": Game.reward(10)
		"gang":
			Game.reward(25, String(Game.GANGS[p.gang]["short"]) + " DOWN", Game.GANGS[p.gang]["col"])
			Game.add_respect(p.gang, -15)
			for h in 3:
				if Game.GANGS[h]["rival"] == p.gang: Game.add_respect(h, 5)
		"cop":
			Game.reward(50, "COP KILLER", Color(0.5, 0.7, 1.0))
			Game.add_wanted(1)
		"swat":
			Game.reward(100, "SWAT DOWN", Color(0.5, 0.7, 1.0))

# ---------------------------------------------------------------- missions
func interact() -> bool:
	if m.player_car or m.player.dying: return false
	for ph in phones:
		if m.player.global_position.distance_to(ph[0]) < 2.6:
			answer_phone(ph[1])
			return true
	return false

func near_phone() -> bool:
	if m.player_car: return false
	for ph in phones:
		if m.player.global_position.distance_to(ph[0]) < 2.6: return true
	return false

func answer_phone(g: int) -> void:
	var gname: String = Game.GANGS[g]["name"]
	if not mission.is_empty():
		Game.message.emit("FINISH YOUR JOB FIRST", Color(1, 1, 1)); return
	if Game.respect[g] <= HATE_RESPECT:
		Game.message.emit(gname + ": GET LOST!", Game.GANGS[g]["col"]); last_event = "phone_refused"; return
	var idx := 0
	if mission_done[g] >= 1:
		idx = 1 if Game.respect[g] >= UNLOCK_RESPECT else 0
		if idx == 0: zone("Earn %d respect with the %s to unlock their big job" % [UNLOCK_RESPECT, gname])
	start_mission(g, idx)

func start_mission(g: int, idx: int) -> void:
	var def: Dictionary = MISSIONS[g][idx].duplicate()
	mission = def
	mission["gang"] = g
	mission["idx"] = idx
	mission["left"] = def["time"]
	m.play_at("ring", m.player.global_position, -4.0)
	Game.message.emit(String(def["title"]), Game.GANGS[g]["col"])
	match def["kind"]:
		"steal":
			var car := _spawn_target_car(def["car"])
			mission["target"] = car
			_set_beacon(car)
		"hit":
			var rival: int = Game.GANGS[g]["rival"]
			var tgt: Ped = null
			for k in 10:
				tgt = spawn_gang(rival)
				if tgt and tgt.global_position.distance_to(m.player.global_position) > 45.0: break
			if tgt == null:
				_mission_clear(); return
			tgt.hp = 70.0
			tgt.mission_target = true
			tgt.set_physics_process(true)
			for k in 2:
				var guard: Ped = m.spawn_ped(tgt.block, "gang", rival)
				guard.global_position = tgt.global_position + Vector3(k * 2.0 - 1.0, 0, 1.5)
			mission["target"] = tgt
			_set_beacon(tgt)
		"run":
			mission["cps"] = _route(def["n"])
			mission["cp"] = 0
			_set_checkpoint(mission["cps"][0])
	last_event = "mission_start_%d_%d" % [g, idx]

func _spawn_target_car(type: String) -> Car:
	var best = null; var bd := 0.0
	for s in m.city.parked_spots:
		var d: float = s[0].distance_to(m.player_target().global_position)
		if d > 50.0 and d < 160.0 and (best == null or absf(d - 90.0) < absf(bd - 90.0)):
			best = s; bd = d
	var pos: Vector3 = best[0] if best else Vector3(2 * Game.P + Game.LANE, 0, 6 * Game.P)
	for c in get_tree().get_nodes_in_group("cars"):
		if c.global_position.distance_to(pos) < 2.5 and c != m.player_car: c.queue_free()
	var car: Car = m.spawn_car(pos, best[1] if best else 0.0, Color.WHITE, type == "police", type)
	car.ctrl = Car.Ctrl.NONE
	return car

func _route(n: int) -> Array:
	var out := []
	var cur := Vector2i(clampi(roundi(m.player_target().global_position.x / Game.P), 0, Game.NB), clampi(roundi(m.player_target().global_position.z / Game.P), 0, Game.NB))
	for i in n:
		var nxt := cur
		for k in 30:
			nxt = Vector2i(Game.rng.randi_range(0, Game.NB), Game.rng.randi_range(0, Game.NB))
			var dd: int = absi(nxt.x - cur.x) + absi(nxt.y - cur.y)
			if dd >= 2 and dd <= 4: break
		out.append(Game.node_pos(nxt))
		cur = nxt
	return out

func _set_beacon(target) -> void:
	if beacon == null:
		beacon = MeshInstance3D.new()
		var cm := CylinderMesh.new(); cm.top_radius = 1.3; cm.bottom_radius = 1.3; cm.height = 24.0
		beacon.mesh = cm; beacon.material_override = _mat(Color(1.0, 0.9, 0.2), 0.28)
		add_child(beacon)
	beacon.visible = true
	beacon.set_meta("target", target)

func _set_checkpoint(p: Vector3) -> void:
	if checkpoint == null:
		checkpoint = _pad(Vector3.ZERO, Color(1.0, 0.85, 0.1), 6.0, "", 0.0)
	checkpoint.visible = true
	checkpoint.global_position = p
	_set_beacon(p)

func mission_target_pos():
	if mission.is_empty(): return null
	match mission["kind"]:
		"steal":
			if m.player_car and m.player_car.car_type == mission["car"]: return drop_pos
			if is_instance_valid(mission["target"]): return mission["target"].global_position
			return drop_pos
		"hit":
			if is_instance_valid(mission["target"]): return mission["target"].global_position
		"run":
			return mission["cps"][mission["cp"]]
	return null

func _mission_tick(dt: float) -> void:
	if mission.is_empty(): return
	mission["left"] -= dt
	var tp = mission_target_pos()
	if beacon and tp != null: beacon.global_position = tp + Vector3(0, 12, 0)
	if mission["left"] <= 0.0:
		_mission_fail("OUT OF TIME"); return
	match mission["kind"]:
		"steal":
			var c: Car = m.player_car
			if c and c.car_type == mission["car"] and c.global_position.distance_to(drop_pos) < 4.5 and c.speed() < 4.0:
				m.toggle_car()
				c.ctrl = Car.Ctrl.NONE
				c.set_meta("owned", false)
				c.remove_from_group("cars")   # can't be re-entered (or shot / recycled) while it sinks
				var tw := create_tween(); tw.tween_property(c, "global_position:y", -3.0, 1.5); tw.tween_callback(c.queue_free)
				_mission_pass()
		"hit":
			var t = mission["target"]
			if not is_instance_valid(t): _mission_fail("TARGET LOST")
		"run":
			if m.player_car and m.player_target().global_position.distance_to(mission["cps"][mission["cp"]]) < 7.0:
				mission["cp"] += 1
				m.play_at("pickup", m.player_target().global_position, -2.0)
				if mission["cp"] >= mission["cps"].size():
					_mission_pass()
				else:
					Game.message.emit("CHECKPOINT %d/%d" % [mission["cp"], mission["cps"].size()], Color(1, 0.9, 0.2))
					_set_checkpoint(mission["cps"][mission["cp"]])

func _mission_pass() -> void:
	var g: int = mission["gang"]
	Game.reward(int(mission["pay"]), "MISSION PASSED!", Game.GANGS[g]["col"])
	m.play_at("cash", m.player_target().global_position, 0.0)
	Game.add_respect(g, 25)
	Game.add_respect(Game.GANGS[g]["rival"], -15)
	Game.mult = mini(Game.mult + 1, Game.MULT_MAX)
	mission_done[g] = maxi(mission_done[g], mission["idx"] + 1)
	last_event = "mission_pass_%d" % g
	_mission_clear()

func _mission_fail(why: String) -> void:
	if mission.is_empty(): return
	Game.message.emit("MISSION FAILED", Color(1, 0.3, 0.3))
	zone(why)
	Game.add_respect(mission["gang"], -5)
	last_event = "mission_fail"
	_mission_clear()

func _mission_clear() -> void:
	# a lieutenant from a failed hit job goes back to being an ordinary gang member
	var t = mission.get("target")
	if is_instance_valid(t) and t is Ped: t.mission_target = false
	mission = {}
	if beacon: beacon.visible = false
	if checkpoint: checkpoint.visible = false

func objective_text() -> String:
	var parts := []
	if not mission.is_empty():
		var s := ""
		match mission["kind"]:
			"steal":
				var have: bool = m.player_car != null and m.player_car.car_type == mission["car"]
				s = ("Deliver the %s to the DROP-OFF" if have else "Steal a %s (yellow beam)") % String(mission["car"]).to_upper()
			"hit": s = "Kill the %s lieutenant" % Game.GANGS[Game.GANGS[mission["gang"]]["rival"]]["short"]
			"run": s = "Checkpoint %d/%d in any car" % [mission["cp"] + 1, mission["cps"].size()]
		parts.append("%s  %d:%02d" % [s, int(mission["left"]) / 60, int(mission["left"]) % 60])
	if not frenzy.is_empty():
		parts.append("KILL FRENZY  %d/%d  %ds" % [frenzy["got"], frenzy["need"], int(frenzy["t"])])
	return "\n".join(parts)

func zone(text: String) -> void:
	zone_msg = text; zone_t = 3.5

# ---------------------------------------------------------------- busted / wasted
func busted() -> void:
	if busy or m.player.dying: return
	busy = true
	m.player.dying = true
	if m.player_car: m.toggle_car()
	m.hud.show_overlay(true, "BUSTED", Color(0.35, 0.55, 1.0))
	Engine.time_scale = 0.5
	_mission_fail("BUSTED")
	frenzy = {}
	await get_tree().create_timer(3.0, true, false, true).timeout
	Engine.time_scale = 1.0
	m.hud.show_overlay(false)
	var fine := mini(Game.cash, maxi(100, Game.cash / 10))
	Game.add_cash(-fine)
	m.weapons.clear()
	Game.mult = 1
	Game.set_wanted(0)
	_clear_cops()
	m.respawn_at(police_pos)
	Game.message.emit("FINE -$%d" % fine, Color(0.5, 0.7, 1.0))
	zone("Weapons confiscated  ·  multiplier reset")
	last_event = "busted"
	busy = false

## Called from main.wasted() after the WASTED screen.
func after_wasted() -> void:
	var bill := mini(Game.cash, 250)
	Game.add_cash(-bill)
	Game.mult = 1
	_mission_fail("WASTED")
	frenzy = {}
	_clear_cops()
	Game.message.emit("HOSPITAL -$%d" % bill, Color(1, 0.4, 0.4))
	zone("You keep your weapons  ·  multiplier reset")
	last_event = "wasted"

func _clear_cops() -> void:
	for p in foot_cops(): p.queue_free()

# ---------------------------------------------------------------- police
func _spawn_swat_van(pos: Vector3) -> Car:
	var c: Car = m.spawn_police_near(pos)
	if c == null: return null
	var at := c.global_position
	c.queue_free()
	var van: Car = m.spawn_car(at, 0.0, Color.WHITE, false, "van")
	van.set_meta("swat", true)
	van.respray(Color(0.25, 0.28, 0.4))
	van.start_police()
	van.max_speed = 30.0
	return van

func _police(dt: float) -> void:
	var tgt: Node3D = m.player_target()
	var tp := tgt.global_position
	var cars := []; var vans := []
	for c in get_tree().get_nodes_in_group("cars"):
		if c.ctrl == Car.Ctrl.POLICE and not c.dead:
			if c.has_meta("swat"): vans.append(c)
			else: cars.append(c)
	police_cd -= dt
	rb_cd -= dt
	var w := Game.wanted
	if w > 0 and police_cd <= 0.0 and not m.player.dying:
		# SWAT gets priority once at least one cop car is on you, so wrecked cop cars
		# being replaced can't starve the vans forever
		if vans.size() < SWAT_VANS[w] and (cars.size() > 0 or COP_CARS[w] == 0):
			police_cd = 4.0
			_spawn_swat_van(tp)
		elif cars.size() < COP_CARS[w]:
			police_cd = 3.0
			m.spawn_police_near(tp)
	# cops get out on foot when they catch up
	for c in cars + vans:
		if c.has_meta("deployed") or w == 0: continue
		var d: float = c.global_position.distance_to(tp)
		var on_foot: bool = m.player_car == null
		# in a car, cops only get out once you've (nearly) stopped: deploying beside a moving car
		# just got them run over, turning 1 star into 3 (run-over + cop killer) in one tick
		var stopped: bool = on_foot or m.player_car.speed() < 4.0
		if d < (14.0 if on_foot else 9.0) and c.speed() < 5.0 and stopped:
			c.set_meta("deployed", true)
			var swat: bool = c.has_meta("swat")
			var n := 4 if swat else (1 if w == 1 else 2)
			for k in n:
				spawn_cop(c.global_position + c.global_transform.basis.x * (2.2 if k % 2 == 0 else -2.2) + c.forward() * (k / 2) * 1.5, "swat" if swat else "cop")
	# roadblocks from 4 stars
	if w >= 4 and m.player_car and rb_cd <= 0.0 and m.player_car.speed() > 6.0:
		if roadblock_ahead(): rb_cd = 16.0
		else: rb_cd = 2.0
	# arrest
	var near := false
	var slow: bool = m.player_car == null or m.player_car.speed() < 2.0
	for c in cars:
		if c.global_position.distance_to(tp) < (5.0 if m.player_car == null else 5.5) and slow: near = true
	if m.player_car == null:
		for p in foot_cops():
			if p.global_position.distance_to(tp) < 1.8: near = true
	bust_t = bust_t + dt if near and w > 0 else 0.0
	if bust_t > 1.0 and not m.player.dying and not no_bust:
		bust_t = 0.0
		busted()
	# line of sight (evasion)
	see_t -= dt
	if see_t <= 0.0:
		see_t = 0.25
		var sees := false
		if w > 0:
			for c in get_tree().get_nodes_in_group("cars"):
				if is_cop_car(c) and c.global_position.distance_to(tp) < 45.0 and los(c.global_position, tp): sees = true; break
			if not sees:
				for p in foot_cops():
					if p.global_position.distance_to(tp) < 30.0 and los(p.global_position, tp): sees = true; break
		Game.cop_sees = sees
	# clean up cops once the heat is gone / far away
	for p in foot_cops():
		if (w == 0 and p.leave_t > 8.0) or p.global_position.distance_to(tp) > 110.0: p.queue_free()
	for c in get_tree().get_nodes_in_group("cars"):
		if c.has_meta("roadblock") and c != m.player_car and c.ctrl == Car.Ctrl.NONE:
			var age: float = c.get_meta("rb_age", 0.0) + dt
			c.set_meta("rb_age", age)
			if (age > 45.0 or w == 0) and c.global_position.distance_to(tp) > 60.0: c.queue_free()

## Two police cars parked across the road at the next junction ahead, with armed cops.
func roadblock_ahead() -> bool:
	var c: Car = m.player_car
	var ahead := c.global_position + c.forward() * 55.0
	var n := Vector2i(clampi(roundi(ahead.x / Game.P), 0, Game.NB), clampi(roundi(ahead.z / Game.P), 0, Game.NB))
	var np := Game.node_pos(n)
	var rel := c.global_position - np
	if rel.length() < 30.0: return false
	var d := Vector2i(signi(roundi(rel.x)), 0) if absf(rel.x) > absf(rel.z) else Vector2i(0, signi(roundi(rel.z)))
	if not Game.in_grid(n + d): return false
	place_roadblock(n, d)
	return true

func place_roadblock(n: Vector2i, d: Vector2i) -> void:
	var dir3 := Vector3(d.x, 0, d.y)
	var across := Vector3(-d.y, 0, d.x)
	var centre := Game.node_pos(n) + dir3 * 10.0
	for c in get_tree().get_nodes_in_group("cars"):
		if c != m.player_car and c.global_position.distance_to(centre) < 7.0: c.queue_free()
	for s in [-1, 1]:
		var p: Vector3 = centre + across * (s * 2.6)
		var cop: Car = m.spawn_car(p, Game.yaw_of(across * s) + 0.25 * s, Color.WHITE, true)
		cop.ctrl = Car.Ctrl.NONE
		cop.set_meta("roadblock", true)
		cop.set_meta("deployed", true)
		spawn_cop(p + dir3 * 2.8, "cop")
	m.play_at("siren", centre, -6.0)
	Game.message.emit("ROADBLOCK!", Color(0.5, 0.7, 1.0))
	last_event = "roadblock"

# ---------------------------------------------------------------- facilities tick
func _facilities(dt: float) -> void:
	var here := ""
	var c: Car = m.player_car
	var pp: Vector3 = m.player_target().global_position
	if c:
		if pp.distance_to(respray_pos) < 4.2: here = "respray"
		elif pp.distance_to(crusher_pos) < 4.2: here = "crusher"
	else:
		for s in shop_pads:
			if pp.distance_to(s[0]) < 1.4: here = "shop_" + s[1]
	if here != "crusher": crush_t = 0.0
	if here == "": pad_lock = ""; return
	if here == "crusher":
		if c.speed() < 2.5:
			crush_t += dt
			if crush_t > 1.2: crush(c)
		return
	if here == pad_lock: return
	if here == "respray":
		if c.speed() > 3.0: return
		if respray(c): pad_lock = here
	elif here.begins_with("shop_"):
		pad_lock = here
		for s in shop_pads:
			if "shop_" + s[1] == here: buy(s[1], s[2], s[3])

## Returns false only when it should retry while the car stays on the pad (a cop is watching).
func respray(c: Car) -> bool:
	if Game.wanted > 0 and Game.cop_sees:
		if last_event != "respray_seen":
			Game.message.emit("LOSE THE COPS FIRST", Color(0.5, 0.7, 1.0))
		last_event = "respray_seen"
		return false
	var cost := RESPRAY_COST if Game.wanted > 0 else REPAIR_COST
	if Game.wanted == 0 and c.health > 95.0:
		zone("Pay 'n' Spray: nothing to fix"); return true
	if Game.cash < cost:
		Game.message.emit("NEED $%d" % cost, Color(1, 0.4, 0.4)); last_event = "respray_broke"; return true
	Game.add_cash(-cost)
	c.respray(TINTS[Game.rng.randi() % TINTS.size()])
	var had := Game.wanted
	Game.set_wanted(0)
	m.play_at("spray", c.global_position, 0.0)
	Game.message.emit("RESPRAY -$%d" % cost, Color(0.4, 0.75, 1.0))
	zone("New paint, repaired" + ("  ·  WANTED LEVEL CLEARED" if had > 0 else ""))
	last_event = "respray"
	return true

func crush(c: Car) -> void:
	crush_t = 0.0
	var value := int(CAR_VALUE.get(c.car_type, 400) * clampf(c.health / 100.0, 0.25, 1.0))
	m.toggle_car()
	m.player.global_position = crusher_pos + Vector3(5.5, 0, 0)
	c.ctrl = Car.Ctrl.NONE
	c.remove_from_group("cars")
	m.play_at("crush", c.global_position, 2.0)
	var tw := create_tween()
	tw.tween_property(c, "scale", Vector3(1.15, 0.12, 1.15), 0.9).set_trans(Tween.TRANS_BOUNCE)
	tw.tween_interval(1.5)
	tw.tween_callback(c.queue_free)
	Game.reward(value, "CRUSHED " + String(c.car_type).to_upper())
	last_event = "crushed"

func buy(w: String, price: int, rounds: int) -> void:
	if Game.cash < price:
		Game.message.emit("NEED $%d" % price, Color(1, 0.4, 0.4)); last_event = "shop_broke"; return
	Game.add_cash(-price)
	m.weapons.give(w, rounds)
	m.play_at("cash", m.player.global_position, -2.0)
	Game.message.emit("%s +%d  -$%d" % [w.to_upper(), rounds, price], m.weapons.DEFS[w]["color"])
	last_event = "bought_" + w

# ---------------------------------------------------------------- main loop
func _physics_process(dt: float) -> void:
	if m == null: return
	if not breaking.is_empty():
		var c: Car = breaking["car"]
		breaking["t"] -= dt
		if not is_instance_valid(c) or c.dead or m.player.dying or c.global_position.distance_to(m.player.global_position) > 5.0:
			breaking = {}; m.player.busy = false
		elif breaking["t"] <= 0.0:
			breaking = {}; m.player.busy = false
			m.enter_car(c, true)
	_police(dt)
	_facilities(dt)
	_mission_tick(dt)
	# frenzy
	skull_cd -= dt
	if skull:
		skull.visible = skull_cd <= 0.0 and frenzy.is_empty()
		skull.rotation.y += dt * 2.0
		if skull.visible and m.player_car == null and m.player.global_position.distance_to(skull.global_position) < 2.2 and not m.player.dying:
			start_frenzy()
	if not frenzy.is_empty():
		frenzy["t"] -= dt
		if frenzy["t"] <= 0.0:
			Game.message.emit("FRENZY FAILED", Color(1, 0.3, 0.3))
			frenzy = {}
			last_event = "frenzy_fail"
	# gangs: keep 6 alive per turf
	if Engine.get_physics_frames() % 120 == 0:
		var counts := [0, 0, 0]
		for p in get_tree().get_nodes_in_group("armed"):
			if p.alive and p.role == "gang" and not p.mission_target: counts[p.gang] += 1
		for g in 3:
			if counts[g] < 6: spawn_gang(g)
	# phones ring when a job is on offer and you're near
	var tsec := Time.get_ticks_msec() / 1000.0
	for ph in phones:
		var ring: bool = mission.is_empty() and Game.respect[ph[1]] > HATE_RESPECT and m.player_target().global_position.distance_to(ph[0]) < 30.0
		ph[3].light_energy = (4.0 if fmod(tsec, 1.0) < 0.5 else 0.5) if ring else 0.0
	# turf banner
	var t := Game.gang_at_block(Game.block_of(m.player_target().global_position))
	if t != turf:
		turf = t
		if t >= 0 and Engine.get_physics_frames() > 30 and zone_t <= 0.5:
			var r: int = Game.respect[t]
			zone("%s TURF  ·  respect %d%s" % [Game.GANGS[t]["name"], r, "  ·  HOSTILE" if r <= HATE_RESPECT else ""])
	zone_t -= dt

func start_frenzy() -> void:
	frenzy = {"t": 40.0, "need": 12, "got": 0}
	skull_cd = 90.0
	m.weapons.give("smg", 150)
	m.play_at("ring", m.player.global_position, 0.0)
	Game.message.emit("KILL FRENZY!", Color(1, 0.2, 0.2))
	zone("Kill 12 people in 40 seconds  ·  SMG supplied")
	last_event = "frenzy_start"

## Label for the touch ENTER button.
func context_label() -> String:
	if m.player_car: return "EXIT"
	if near_phone(): return "PHONE"
	for c in get_tree().get_nodes_in_group("cars"):
		if c.dead: continue
		if c.global_position.distance_to(m.player.global_position) < 4.5:
			return "ENTER" if c.get_meta("owned", false) else "STEAL"
	return "ENTER"

## Minimap blips: [world pos, colour, letter, pin to edge]
func blips() -> Array:
	var out := [[respray_pos, Color(0.25, 0.6, 1.0), "R", false], [crusher_pos, Color(0.95, 0.8, 0.1), "C", false],
		[shop_pads[1][0], Color(1, 0.3, 0.2), "$", false], [hospital_pos, Color(1, 1, 1), "H", false], [police_pos, Color(0.4, 0.6, 1.0), "P", false]]
	for ph in phones: out.append([ph[0], Game.GANGS[ph[1]]["col"], "☎", false])
	if skull and skull.visible: out.append([skull.global_position, Color(1, 0.2, 0.2), "K", false])
	var tp = mission_target_pos()
	if tp != null: out.append([tp, Color(1, 0.9, 0.2), "!", true])
	return out
