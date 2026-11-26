extends Node
## Scripted playthroughs: the game is played through the normal input paths (virtual joystick
## vector, enter / fire / handbrake actions) by a small autopilot, with captions on screen.
## Record one with Godot's Movie Maker (needs a display; see README "Playthroughs"):
##   godot --path . --write-movie out.avi --fixed-fps 30 -- --play=joyride|phone_job|hit_job|five_stars
## Headless dry run (prints the event log, much faster):
##   godot --headless --fixed-fps 60 --path . -- --play=joyride
var m
var c
var cap: Label
var log_t := 0.0
var events := []

func run(main_, name: String) -> void:
	m = main_
	c = m.crime
	m.add_child(self)
	var layer := CanvasLayer.new(); layer.layer = 20
	add_child(layer)
	cap = Label.new()
	cap.add_theme_font_size_override("font_size", 26)
	cap.add_theme_color_override("font_color", Color(1, 1, 1))
	cap.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	cap.add_theme_constant_override("outline_size", 8)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layer.add_child(cap)
	Game.message.connect(func(t, _c): _ev("msg " + t))
	Game.wanted_changed.connect(func(w): _ev("wanted %d" % w))
	Game.ped_killed.connect(func(p, bp): _ev("killed %s%s" % [p.role, " (by player)" if bp else ""]))
	_go.call_deferred(name)

var _last_car_hp := 100.0
var _last_hp := 100.0
func _physics_process(dt: float) -> void:
	if m == null: return
	log_t += dt
	var car: Car = m.player_car
	if car:
		if _last_car_hp - car.health > 15.0: _ev("car hit -%.0f hp=%.0f v=%.1f" % [_last_car_hp - car.health, car.health, car.speed()])
		_last_car_hp = car.health
	else: _last_car_hp = 100.0
	if _last_hp - m.player.health > 0.5: _ev("player hurt -%.0f hp=%.0f" % [_last_hp - m.player.health, m.player.health])
	_last_hp = m.player.health
	for k in get_tree().get_nodes_in_group("cars"):
		if k.has_meta("swat") and not k.has_meta("seen_by_play"):
			k.set_meta("seen_by_play", true); _ev("SWAT van arrives")
	if log_t > 2.0:
		log_t = 0.0
		var p: Vector3 = m.player_target().global_position
		var cop_d := INF
		for k in get_tree().get_nodes_in_group("cars"):
			if c.is_cop_car(k): cop_d = minf(cop_d, k.global_position.distance_to(p))
		_ev("status pos=(%.0f,%.0f) %s w=%d hp=%.0f cop=%.0fm seen=%s" % [p.x, p.z, ("car hp=%.0f v=%.0f" % [car.health, car.speed()]) if car else "on foot", Game.wanted, m.player.health, cop_d, Game.cop_sees])

func _process(_dt: float) -> void:
	if cap:
		var vs := get_viewport().get_visible_rect().size
		cap.size = Vector2(vs.x - 40, 40)
		cap.position = Vector2(20, vs.y - 160)

func _ev(s: String) -> void:
	var line := "[%6.1f] %s" % [Game.clock, s]
	events.append(line)
	print("PLAY ", line)

func say(text: String) -> void:
	cap.text = text
	_ev("caption " + text)

func _wait(s: float) -> void:
	await get_tree().create_timer(s, true, true).timeout

func _tick() -> void:
	await get_tree().physics_frame

func tap(action: String) -> void:
	Input.action_press(action)
	await _tick(); await _tick()
	Input.action_release(action)
	await _tick()

func stick(v: Vector2) -> void:
	Game.touch_vec = v.limit_length(1.0)

func idle() -> void:
	Game.touch_vec = Vector2.ZERO
	Game.touch_handbrake = false
	Input.action_release("fire")

# ------------------------------------------------------------------ on foot
func walk_to(p: Vector3, timeout := 20.0, r := 1.2) -> bool:
	var t := 0.0
	var chk := 0.0; var last: Vector3 = m.player.global_position
	var side := 0.0; var side_dir := 1.0
	while t < timeout:
		if m.player.dying or m.player_car: idle(); return false
		var to: Vector3 = p - m.player.global_position; to.y = 0
		if to.length() < r: idle(); return true
		var v := Vector2(to.x, to.z).normalized()
		if side > 0.0:   # blocked (parked car, booth...): step sideways for a moment
			side -= get_physics_process_delta_time()
			v = Vector2(-v.y, v.x) * side_dir
		stick(v)
		await _tick(); t += get_physics_process_delta_time()
		chk += get_physics_process_delta_time()
		if chk > 0.5:
			if m.player.global_position.distance_to(last) < 0.6 and side <= 0.0:
				side = 0.6; side_dir = -side_dir
			chk = 0.0; last = m.player.global_position
	idle()
	return false

## Face `target` and hold fire for `secs` (re-aims every tick by nudging the stick).
func shoot_at(target: Node3D, secs: float) -> void:
	Input.action_press("fire")
	var t := 0.0
	while t < secs and is_instance_valid(target) and not m.player.dying:
		if "alive" in target and not target.alive: break
		if not c.los(m.player.global_position, target.global_position): break
		var to: Vector3 = target.global_position - m.player.global_position; to.y = 0
		stick(Vector2(to.x, to.z).normalized() * (0.25 if to.length() > 6.0 else 0.12))
		await _tick(); t += get_physics_process_delta_time()
	idle()

# ------------------------------------------------------------------ driving
## Road-grid route from the car to `p`: off-road points (parking lots, pads) are reached through
## the middle of the block from the nearest north-south road.
func route_to(from: Vector3, p: Vector3) -> Array:
	var P := Game.P
	var pts := []
	var a := _road_point(from)
	var b := _road_point(p)
	if a.distance_to(from) > 1.0: pts.append(a)
	var na := _seg_node(a, b)
	var nb := _seg_node(b, a)
	var cur := na
	pts.append(Game.node_pos(cur))
	while cur.x != nb.x:
		cur.x += signi(nb.x - cur.x); pts.append(Game.node_pos(cur))
	while cur.y != nb.y:
		cur.y += signi(nb.y - cur.y); pts.append(Game.node_pos(cur))
	pts.append(b)
	if b.distance_to(p) > 1.0: pts.append(p)
	# keep right: shift each point by the lane offset of the leg arriving at it
	var out := []
	var prev := from
	for q in pts:
		var d: Vector3 = q - prev; d.y = 0
		var off := Vector3.ZERO
		if d.length() > 0.5: off = Vector3(-d.z, 0, d.x).normalized() * 2.2
		out.append(q + off if q != p else q)
		prev = q
	return out

func _on_road(p: Vector3) -> bool:
	var P := Game.P
	return absf(p.x - roundf(p.x / P) * P) < Game.ROAD_HALF or absf(p.z - roundf(p.z / P) * P) < Game.ROAD_HALF

func _road_point(p: Vector3) -> Vector3:
	if _on_road(p): return Vector3(p.x, 0, p.z)
	return Vector3(roundf(p.x / Game.P) * Game.P, 0, p.z)

## Of the two junctions at the ends of the road segment `p` is on, the one nearer `toward`.
func _seg_node(p: Vector3, toward: Vector3) -> Vector2i:
	var P := Game.P
	var ax := absf(p.x - roundf(p.x / P) * P) < Game.ROAD_HALF
	var cands := []
	if ax:   # on a north-south road
		var x := roundi(p.x / P)
		cands = [Vector2i(x, floori(p.z / P)), Vector2i(x, ceili(p.z / P))]
	else:
		var z := roundi(p.z / P)
		cands = [Vector2i(floori(p.x / P), z), Vector2i(ceili(p.x / P), z)]
	var best: Vector2i = cands[0]
	for n in cands:
		n.x = clampi(n.x, 0, Game.NB); n.y = clampi(n.y, 0, Game.NB)
		if Game.node_pos(n).distance_to(toward) < Game.node_pos(best).distance_to(toward): best = n
	return best

var bail_hp := -INF   # drive_path gives up when the car gets this damaged
var brake_peds := true
var urgent := false   # fleeing: don't queue behind traffic, go round it straight away

func drive_to(p: Vector3, timeout := 40.0, top := 26.0) -> bool:
	var pts := route_to(m.player_car.global_position, p) if m.player_car else []
	var t0 := Game.clock
	var ok: bool = await drive_path(pts, timeout, top)
	_ev("drive to (%.0f,%.0f) %s in %.1fs" % [p.x, p.z, "arrived" if ok else "gave up", Game.clock - t0])
	return ok

func drive_path(pts: Array, timeout := 40.0, top := 26.0) -> bool:
	var t := 0.0
	var i := 0
	var stuck := 0.0
	var rev := 0.0
	var blocked := 0.0
	var overtake := 0.0
	var prog_t := 0.0; var prog_d := INF
	while t < timeout and i < pts.size():
		var car: Car = m.player_car
		if car == null or car.dead or m.player.dying or car.health < bail_hp: idle(); return false
		var wp: Vector3 = pts[i]
		var last := i == pts.size() - 1
		var to := wp - car.global_position; to.y = 0
		var dist := to.length()
		var spd := car.speed()
		if dist < (3.0 if last else 5.5 + spd * 0.25):
			i += 1; continue
		var diff := wrapf(Game.yaw_of(to) - car.rotation.y, -PI, PI)
		var want := top if absf(diff) < 0.25 else ((17.0 if urgent else 13.0) if absf(diff) < 0.8 else (9.0 if urgent else 7.0))
		# brake in time for the turn at the next junction: v^2 = v_turn^2 + 2 * decel * distance
		if not last and i + 1 < pts.size():
			var nxt: Vector3 = pts[i + 1] - wp
			if absf(wrapf(Game.yaw_of(nxt) - Game.yaw_of(to), -PI, PI)) > 0.6:
				var v_turn := 12.0 if urgent else 10.0
				want = minf(want, sqrt(v_turn * v_turn + 2.0 * 18.0 * maxf(dist - 6.0, 0.0)))
		if last: want = minf(want, dist * 0.7 + 1.5)
		var fs := car.velocity.dot(car.forward())
		# traffic ahead: brake behind it, and after a moment pull out and overtake on the left
		var gap := _gap_ahead(car)
		if gap < INF:
			want = minf(want, maxf(0.0, (gap - 4.0) * 0.8) if not urgent else maxf(8.0, (gap - 4.0) * 1.2))
			blocked += get_physics_process_delta_time()
			if blocked > (0.25 if urgent else 1.2) and overtake <= 0.0: overtake = 2.2
		else:
			blocked = 0.0
		var steer_to := wp
		if overtake > 0.0:
			overtake -= get_physics_process_delta_time()
			steer_to = car.global_position + car.forward() * 10.0 - car.global_transform.basis.x * 4.5
			want = maxf(want, 9.0)
			diff = wrapf(Game.yaw_of(steer_to - car.global_position) - car.rotation.y, -PI, PI)
		var y := -1.0 if fs < want else (1.0 if fs > want + 1.5 else 0.0)
		var x := clampf(-diff * 2.2, -1.0, 1.0)
		if rev > 0.0:
			rev -= get_physics_process_delta_time()
			x = -x; y = 1.0
		elif y < 0.0 and spd < 1.0:
			stuck += get_physics_process_delta_time()
			if stuck > 1.0: stuck = 0.0; rev = 0.9
		else:
			stuck = 0.0
		# grinding against something at walking pace: no progress towards the waypoint
		prog_t += get_physics_process_delta_time()
		if prog_t > 2.0:
			if prog_d - dist < 2.0 and rev <= 0.0 and gap == INF: rev = 1.0
			prog_t = 0.0; prog_d = dist
		stick(Vector2(x, y))
		await _tick(); t += get_physics_process_delta_time()
	# stop
	var k := 0.0
	while m.player_car and m.player_car.speed() > 0.8 and k < 3.0:
		stick(Vector2(0, 1.0 if m.player_car.velocity.dot(m.player_car.forward()) > 0.0 else -1.0))
		await _tick(); k += get_physics_process_delta_time()
	idle()
	return i >= pts.size()

## Distance to the nearest car or ped in our path (INF if clear).
func _gap_ahead(car: Car) -> float:
	var fwd := car.forward(); var rt := car.global_transform.basis.x
	var look := 8.0 + car.speed() * 0.9
	var best := INF
	var peds: Array = m.near_peds(car.global_position, look + 3.0) if brake_peds else []
	for o in m.near_cars(car.global_position, look + 3.0) + peds:
		if o == car or ("alive" in o and not o.alive): continue
		var d: Vector3 = o.global_position - car.global_position
		var a := d.dot(fwd)
		if a > 1.0 and a < look and absf(d.dot(rt)) < 2.3: best = minf(best, a)
	return best

func nearest_car(pred: Callable, r := 60.0) -> Car:
	var best: Car = null; var bd := r
	for k in get_tree().get_nodes_in_group("cars"):
		if k.dead or not pred.call(k): continue
		var d: float = k.global_position.distance_to(m.player.global_position)
		if d < bd: bd = d; best = k
	return best

## Walk to a free side of `car` (driver, passenger, front, back) so E picks this car, then press E.
func get_in(car: Car, timeout := 12.0) -> bool:
	var b := car.global_transform.basis
	var best = null; var bd := INF
	for off in [-b.x * 2.3, b.x * 2.3, -b.z * 3.3, b.z * 3.3]:
		var q: Vector3 = car.global_position + off
		var free := true
		for o in get_tree().get_nodes_in_group("cars"):
			if o != car and o.global_position.distance_to(q) < 2.6: free = false
		var d: float = q.distance_to(m.player.global_position)
		if free and d < bd: bd = d; best = q
	await walk_to(best if best != null else car.global_position, timeout, 0.8 if best != null else 3.0)
	await tap("enter_exit")
	var t := 0.0
	while t < 3.0 and m.player_car != car:
		await _tick(); t += get_physics_process_delta_time()
	return m.player_car == car

func get_out() -> void:
	if m.player_car: await tap("enter_exit")

func finish(ok: bool) -> void:
	idle()
	await _wait(2.5)
	print("PLAYRESULT ", JSON.stringify({"ok": ok, "cash": Game.cash, "wanted": Game.wanted, "mult": Game.mult,
		"respect": Game.respect, "last_event": c.last_event, "t": snappedf(Game.clock, 0.1)}))
	get_tree().quit(0 if ok else 1)

# ------------------------------------------------------------------ scenarios
func _go(name: String) -> void:
	await _wait(0.5)
	match name:
		"joyride": await joyride()
		"phone_job": await phone_job()
		"hit_job": await hit_job()
		"five_stars": await five_stars()
		_:
			print("unknown playthrough ", name); get_tree().quit(2)

## Steal a parked car, plough a crowd (1 star, not 5), lose the cop, Pay 'n' Spray repaint.
func joyride() -> void:
	var P := Game.P
	Game.cash = 900
	# a parked car in a lot about two blocks from the respray
	var spot = null
	for s in m.city.parked_spots:
		var d: float = s[0].distance_to(c.respray_pos)
		if d > 70.0 and d < 120.0 and s[0].distance_to(c.drop_pos) > 30.0 and s[0].distance_to(c.crusher_pos) > 30.0:
			spot = s; break
	var car: Car = null
	for k in get_tree().get_nodes_in_group("cars"):
		if spot and k.global_position.distance_to(spot[0]) < 1.0: car = k
	if car and car.car_type != "sports":
		car.queue_free(); car = null
	if car == null:   # put a sports car in that bay (the getaway needs to outrun a cop car)
		var at: Vector3 = spot[0] if spot else Vector3(2 * P + 6.0, 0, 2 * P - 9.0)
		car = m.spawn_car(at, spot[1] if spot else 0.0, Color.WHITE, false, "sports"); car.ctrl = Car.Ctrl.NONE
	m.player.global_position = car.global_position + Vector3(7, 0.2, 4)
	m.cam.global_position = Vector3(m.player.global_position.x, m.cam_h, m.player.global_position.z)
	say("JOYRIDE — walk up to a parked car and break in (E)")
	await _wait(1.0)
	if not await get_in(car):
		await _wait(1.4)   # break-in takes 1.1 s
	if m.player_car != car:
		say("couldn't get the car"); await finish(false); return
	say("Got it. Out of the lot and onto the street")
	# head for a straight road away from the respray, with a crowd crossing it
	var crowd_road := Vector3(roundf(car.global_position.x / P) * P, 0, 0)
	var z0 := roundf(car.global_position.z / P) * P
	var start := Vector3(crowd_road.x + 2.5, 0, z0)
	await drive_to(start, 20.0, 18.0)
	var dirz := 1.0 if z0 < 4 * P else -1.0
	# a crowd crossing the street at the next block
	var cz := z0 + dirz * P * 0.62
	for k in 5:
		var pd: Ped = m.spawn_ped(Game.block_of(Vector3(crowd_road.x + 8, 0, cz)))
		pd.set_physics_process(false)
		pd.global_position = Vector3(crowd_road.x + 0.6 + k * 1.1, 0.0, cz + (k % 2) * 0.8)
	say("A crowd crossing the street... (fix: +1 star per 2.5 s, not +1 per body)")
	brake_peds = false
	await drive_path([Vector3(crowd_road.x + 2.5, 0, z0 + dirz * P)], 12.0, 24.0)
	brake_peds = true
	await _wait(0.3)
	say("Wanted: %d star(s). Straight for the Pay 'n' Spray" % Game.wanted)
	for attempt in 3:
		if m.player_car == null or m.player.dying: break
		say("Into the Pay 'n' Spray")
		await drive_to(c.respray_pos, 60.0, 30.0)
		var t := 0.0
		while t < 0.6 and Game.wanted > 0 and m.player_car:   # don't sit still with cops watching: they get out
			await _wait(0.2); t += 0.2
		if Game.wanted == 0 or m.player_car == null: break
		say("\"LOSE THE COPS FIRST\" — drive off, lose them, come back (fix: no need to re-trigger the pad)")
		await evade(30.0)
	say("Pay 'n' Spray: new body paint only — windows, lights and tyres keep their colours" if c.last_event == "respray" else "Result: " + c.last_event)
	await _wait(2.5)
	if m.player_car:
		await drive_path([m.player_car.global_position + m.player_car.forward() * 12.0], 6.0, 8.0)
	await finish(c.last_event == "respray" and Game.wanted == 0)

## Drive away from whichever cops can see us, junction to junction, until unseen for a while.
func evade(max_t: float, until_clear := false) -> void:
	var t := 0.0
	var unseen := 0.0
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	urgent = true
	while t < max_t and m.player_car and not m.player.dying and Game.wanted > 0:
		var here: Vector3 = m.player_car.global_position
		var n := Vector2i(clampi(roundi(here.x / Game.P), 0, Game.NB), clampi(roundi(here.z / Game.P), 0, Game.NB))
		# pick the neighbouring junction 2 blocks away that is furthest from all cop cars
		var best := n; var bs := -INF
		for d in dirs:
			var cand: Vector2i = n + d * 3
			cand = Vector2i(clampi(cand.x, 1, Game.NB - 1), clampi(cand.y, 1, Game.NB - 1))   # stay off the edge roads
			if cand == n: continue
			var score := 0.0
			var heading := (Game.node_pos(cand) - here).normalized()
			for k in get_tree().get_nodes_in_group("cars"):
				if not c.is_cop_car(k): continue
				score += minf(k.global_position.distance_to(Game.node_pos(cand)), 120.0)
				var to_cop: Vector3 = k.global_position - here
				if to_cop.length() < 60.0 and heading.dot(to_cop.normalized()) > 0.3: score -= 500.0   # never flee into them
			if score > bs: bs = score; best = cand
		var t0 := Game.clock
		await drive_to(Game.node_pos(best), 12.0, 38.0)
		t += Game.clock - t0
		unseen = 0.0 if Game.cop_sees else unseen + (Game.clock - t0)
		if unseen > 3.0 and not until_clear and _cop_dist() > 50.0: break
	urgent = false

func _cop_dist() -> float:
	var d := INF
	for k in get_tree().get_nodes_in_group("cars"):
		if c.is_cop_car(k): d = minf(d, k.global_position.distance_to(m.player_target().global_position))
	return d

## Answer the Serpents' phone, carjack a ride, steal the sports car, deliver it.
func phone_job() -> void:
	var P := Game.P
	Game.cash = 300
	var ph: Array = c.phones[0]
	m.player.global_position = ph[0] + Vector3(5, 0, -6)
	m.cam.global_position = Vector3(m.player.global_position.x, m.cam_h, m.player.global_position.z)
	say("PHONE JOB — the Neon Serpents' payphone is ringing")
	await _wait(1.0)
	await walk_to(ph[0] + Vector3(0.8, 0, 0), 10.0, 1.0)
	await tap("enter_exit")
	await _wait(1.5)
	if c.mission.is_empty():
		say("no job?"); await finish(false); return
	say("HOT WHEELS: steal a sports car (yellow beam) and bring it to the DROP-OFF")
	# flag down a ride: carjack the first traffic car on this road
	var road_x: float = roundf(ph[0].x / P) * P
	var ride: Car = m.spawn_traffic_at(Vector2i(roundi(road_x / P), roundi(ph[0].z / P) - 1), Vector2i(0, 1), 0.3)
	var t := 0.0
	while t < 5.0 and ride.global_position.distance_to(m.player.global_position) > 9.0:
		await _wait(0.1); t += 0.1
	say("Carjack the next car that comes past")
	if not await get_in(ride, 6.0):
		ride = nearest_car(func(k): return k.ctrl == Car.Ctrl.TRAFFIC)
		if ride == null or not await get_in(ride, 10.0):
			await finish(false); return
	var target: Car = c.mission["target"]
	say("Driving to the sports car")
	var aisle: Vector3 = target.global_position - target.global_transform.basis.z * 6.0   # parked nose-in: the aisle is in front
	if _on_road(target.global_position): aisle = target.global_position + target.global_transform.basis.x * 4.0
	await drive_to(aisle, 60.0)
	if Game.wanted > 0:
		say("Can't get out with cops on my tail: lose them first (12 s unseen per star)")
		await evade(60.0, true)
		say("Clear. Back to the sports car")
		await drive_to(aisle, 60.0)
	await get_out()
	await _wait(0.4)
	say("Break into the sports car")
	if not await get_in(target, 12.0):
		await _wait(1.4)
	if m.player_car != target:
		await finish(false); return
	say("Now to the DROP-OFF before the timer runs out")
	await drive_to(c.drop_pos, 60.0, 34.0)
	if not c.mission.is_empty() and Game.wanted > 0 and m.player_car and m.player_car.global_position.distance_to(c.drop_pos) > 6.0:
		await evade(30.0)
		await drive_to(c.drop_pos, 60.0, 34.0)
	await _wait(1.0)
	await finish(c.last_event.begins_with("mission_pass"))

## The big Serpents job (respect 20+): buy an SMG, take out the Saints lieutenant.
func hit_job() -> void:
	var P := Game.P
	Game.cash = 1600
	Game.respect = [25, -5, 0]
	c.mission_done[0] = 1
	say("HIT JOB — Serpents respect 25 after HOT WHEELS: their big job is unlocked")
	var ph: Array = c.phones[0]
	m.player.global_position = ph[0] + Vector3(3, 0, 3)
	m.cam.global_position = Vector3(m.player.global_position.x, m.cam_h, m.player.global_position.z)
	await _wait(1.0)
	await walk_to(ph[0] + Vector3(0.8, 0, 0), 8.0, 1.0)
	await tap("enter_exit")
	await _wait(1.2)
	if c.mission.get("kind", "") != "hit":
		await finish(false); return
	var tgt: Ped = c.mission["target"]
	say("SAINTS' DAY: kill the Iron Saints lieutenant. First, a gun.")
	var ride: Car = m.spawn_car(m.player.global_position + Vector3(-3.5, 0, 6), 0.0, Color.WHITE, false, "hatchback")
	ride.ctrl = Car.Ctrl.NONE; ride.set_meta("owned", true)
	await get_in(ride, 8.0)
	var smg_pad: Vector3 = c.shop_pads[1][0]
	await drive_to(smg_pad + Vector3(0, 0, 6.5), 50.0)   # the road just south of the pads
	await get_out()
	say("Ammu: walk onto the SMG pad ($400)")
	await walk_to(smg_pad, 8.0, 0.6)
	await _wait(0.8)
	await walk_to(smg_pad + Vector3(0, 0, 4.0), 4.0, 1.0)
	await get_in(ride, 8.0)
	say("Lieutenant + 2 bodyguards, east side. Follow the beam.")
	await drive_to(tgt.global_position, 70.0)
	await get_out()
	await _wait(0.3)
	say("Open fire (FIRE / Ctrl)")
	var t := 0.0
	while t < 25.0 and is_instance_valid(tgt) and tgt.alive and not m.player.dying:
		var d: float = tgt.global_position.distance_to(m.player.global_position)
		if d > 11.0 or not c.los(m.player.global_position, tgt.global_position):
			await walk_to(tgt.global_position, 1.5, 4.0)   # close in / round the corner
			t += 1.5
		else:
			await shoot_at(tgt, 0.6)
			t += 0.6
	if c.last_event == "mission_pass_0":
		say("MISSION PASSED — Serpents respect up, Saints furious, multiplier x%d" % Game.mult)
		await finish(true); return
	# mop up bodyguards shooting back
	for g in get_tree().get_nodes_in_group("armed"):
		if g.alive and g.role == "gang" and g.global_position.distance_to(m.player.global_position) < 16.0:
			await shoot_at(g, 1.5)
	await _wait(0.5)
	await finish(c.last_event == "mission_pass_0")

## Five stars in a fast car: cop cars, a roadblock, SWAT vans; then make a stand on foot.
func five_stars() -> void:
	var P := Game.P
	Game.cash = 2000
	m.weapons.give("smg", 400)
	var car: Car = m.spawn_car(Vector3(2 * P + Game.LANE, 0, 6 * P), 0.0, Color.WHITE, false, "sports")
	m.enter_car(car, true)
	m.cam.global_position = Vector3(car.global_position.x, m.cam_h, car.global_position.z)
	Game.set_wanted(4)
	bail_hp = 50.0
	say("FIVE STARS — 4 stars to start: cop cars and roadblocks")
	# laps round the middle of town
	var loop := [Vector2i(2, 2), Vector2i(6, 2), Vector2i(6, 6), Vector2i(2, 6)]
	var shot5 := false
	for lap in 2:
		for n in loop:
			if m.player.dying or m.player_car == null or m.player_car.health < bail_hp: break
			await drive_to(Game.node_pos(n), 25.0, 34.0)
			if not shot5 and Game.wanted < 5:
				shot5 = true
				Game.set_wanted(5)
				say("5 stars: SWAT vans join in")
	if m.player_car and not m.player.dying:
		var wreck: Car = m.player_car
		var hurt: bool = wreck.health < bail_hp
		await get_out()
		if hurt:
			say("Car's had it — bail out and get clear before it blows")
			var away: Vector3 = m.player.global_position - wreck.global_position; away.y = 0
			await walk_to(m.player.global_position + away.normalized() * 10.0, 2.5, 1.0)
		say("Out of the car with an SMG: last stand")
		var t := 0.0
		while t < 25.0 and not m.player.dying:
			var best = null; var bd := 22.0
			for p in c.foot_cops():
				var d: float = p.global_position.distance_to(m.player.global_position)
				if d < bd: bd = d; best = p
			if best: await shoot_at(best, 0.8)
			else: await _wait(0.5)
			t += 0.8
	var tt := 0.0
	while tt < 8.0 and m.player.dying:
		await _wait(0.5); tt += 0.5
	say("Result: " + c.last_event.to_upper())
	await finish(c.last_event in ["wasted", "busted"] or Game.wanted >= 4)
