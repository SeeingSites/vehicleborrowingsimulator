extends Node
## Headless checks for the v4 crime systems:
##   godot --headless --fixed-fps 60 --path . -- --test
var m
var c
var passed := 0
var failed := 0

func run(main_) -> void:
	m = main_
	c = m.crime
	m.add_child(self)
	_go.call_deferred()

func _wait(s: float) -> void:
	await get_tree().create_timer(s, true, true).timeout

func ok(name: String, cond: bool, info := "") -> void:
	if cond: passed += 1; print("PASS ", name)
	else: failed += 1; print("FAIL ", name, "  ", info)

func _quiet(pos: Vector3, r := 14.0) -> void:
	for p in get_tree().get_nodes_in_group("peds"):
		if p.global_position.distance_to(pos) < r: p.queue_free()
	for p in c.foot_cops(): p.queue_free()
	for k in get_tree().get_nodes_in_group("cars"):
		# burning cars / wrecks left by earlier checks can explode and kill whoever the next check uses
		if k.ctrl == Car.Ctrl.POLICE or k.has_meta("roadblock") or k.dead or k.burn_t >= 0.0: k.queue_free()

func _reset() -> void:
	# let a WASTED / BUSTED sequence from the previous check finish, or its pending respawn
	# would teleport the player in the middle of the next check
	for k in 60:
		if not m.player.dying and not c.busy: break
		await _wait(0.1)
	if m.player_car: m.toggle_car()
	m.player.dying = false; m.player.busy = false; m.player.health = 100.0; m.player.visible = true
	Game.set_wanted(0); Game.cop_sees = false
	c.mission = {}; c.frenzy = {}; c.breaking = {}
	await _wait(0.1)

## Somewhere on a road away from other facilities.
func _spot(i: int) -> Vector3:
	return Vector3(Game.P * (1 + i % 6) + 12.0, 0.2, Game.P * (1 + i / 6) + Game.LANE)

func _go() -> void:
	await _wait(0.5)
	var P := Game.P
	# 1. steal a parked car, nobody looking
	await _reset()
	var pos := _spot(0)
	_quiet(pos, 30.0)
	var car: Car = m.spawn_car(pos, 0.0, Color.WHITE, false, "sedan")
	m.player.global_position = pos + Vector3(2.5, 0, 0)
	Game.cash = 1000
	m.toggle_car()
	car.remove_meta("alarm")   # the 50% alarm may summon a witness: keep this check deterministic
	ok("break-in starts (player frozen)", not c.breaking.is_empty() and m.player.busy)
	await _wait(1.5)
	ok("steal parked car unseen: in car, no stars, +$25", m.player_car == car and Game.wanted == 0 and Game.cash == 1025, "wanted=%d cash=%d" % [Game.wanted, Game.cash])
	# 2. steal with a bystander right there
	await _reset()
	pos = _spot(1)
	_quiet(pos, 30.0)
	car = m.spawn_car(pos, 0.0, Color.WHITE, false, "taxi")
	m.player.global_position = pos + Vector3(2.5, 0, 0)
	var wit: Ped = m.spawn_ped(Game.block_of(pos)); wit.set_physics_process(false); wit.global_position = pos + Vector3(4, 0.2, 2)
	m.toggle_car()
	await _wait(1.5)
	ok("steal parked car witnessed: +1 star", m.player_car == car and Game.wanted == 1, "wanted=%d ev=%s" % [Game.wanted, c.last_event])
	# 3. carjack a traffic car in front of a cop
	await _reset()
	pos = _spot(2)
	_quiet(pos, 40.0)
	car = m.spawn_car(pos, Game.yaw_of(Vector3(1, 0, 0)), Color.WHITE, false, "sedan")
	car.start_traffic(Vector2i(int(pos.x / P), int(round(pos.z / P))), Vector2i(1, 0))
	car.set_physics_process(false)
	var cop: Ped = c.spawn_cop(pos + Vector3(-12, 0, 0)); cop.set_physics_process(false)
	m.player.global_position = pos + Vector3(0, 0, 2.5)
	var peds_before := get_tree().get_nodes_in_group("peds").size()
	m.toggle_car()
	car.set_physics_process(true)
	ok("carjack: instant, driver pulled out, cop saw it (+1 star)", m.player_car == car and Game.wanted == 1 and get_tree().get_nodes_in_group("peds").size() == peds_before + 1, "wanted=%d" % Game.wanted)
	# 4. police escalation
	await _reset()
	_quiet(m.player.global_position, 0.0)
	m.player.global_position = Vector3(4 * P + 6.25, 0.2, 4 * P + 12.0)
	Game.set_wanted(2)
	c.no_bust = true
	await _wait(8.0)
	var cars := 0; var vans := 0
	for k in get_tree().get_nodes_in_group("cars"):
		if k.ctrl == Car.Ctrl.POLICE and not k.dead:
			if k.has_meta("swat"): vans += 1
			else: cars += 1
	ok("2 stars: 2 cop cars, no SWAT", cars == 2 and vans == 0, "cars=%d vans=%d" % [cars, vans])
	m.player.global_position = Vector3(4 * P + 6.25, 0.2, 4 * P + 12.0)
	Game.set_wanted(5)
	m.player.health = 1000.0
	m.god = true
	# cop cars crash and burn at 5 stars, so track the peak counts over the window
	var seen_van := false
	var max_cars := 0; var max_vans := 0; var max_foot := 0
	for k in 40:
		await _wait(0.5)
		cars = 0; vans = 0
		for v in get_tree().get_nodes_in_group("cars"):
			if v.ctrl == Car.Ctrl.POLICE and not v.dead:
				if v.has_meta("swat"): vans += 1; seen_van = true
				else: cars += 1
		max_cars = maxi(max_cars, cars); max_vans = maxi(max_vans, vans)
		max_foot = maxi(max_foot, c.foot_cops().size())
	ok("5 stars: up to 4 cop cars (>=3 at once) + a SWAT van (max 1)", max_cars >= 3 and max_cars <= 4 and max_vans <= 1 and seen_van, "max cars=%d vans=%d" % [max_cars, max_vans])
	ok("cops get out on foot when they reach you", max_foot > 0, "max foot cops=%d" % max_foot)
	c.no_bust = false
	m.god = false
	# roadblock
	await _reset()
	_quiet(Vector3.ZERO, 0.0)
	await _wait(0.1)
	c.place_roadblock(Vector2i(4, 4), Vector2i(1, 0))
	var rb := 0
	for k in get_tree().get_nodes_in_group("cars"):
		if k.has_meta("roadblock"): rb += 1
	ok("roadblock: 2 parked police cars + cops", rb == 2 and c.foot_cops().size() == 2, "rb=%d cops=%d" % [rb, c.foot_cops().size()])
	# 5. armed cops shoot at 3 stars
	await _reset()
	_quiet(Vector3.ZERO, 0.0)
	pos = Vector3(4 * P + 6.25, 0.2, 4 * P + 10.0)
	m.player.global_position = pos
	_quiet(pos, 30.0)
	Game.set_wanted(3)
	c.police_cd = 99.0
	var sh: Ped = c.spawn_cop(pos + Vector3(0, 0, 12.0))
	m.player.health = 100.0
	m.god = true   # a stray hit must not end the run in WASTED
	for k in 16:   # 55% hit chance per shot: poll instead of a fixed 3 s window
		await _wait(0.5)
		if m.player.health < 100.0: break
	m.god = false
	ok("3 stars: cops on foot shoot you", sh != null and m.player.health < 100.0, "hp=%.0f" % m.player.health)
	# 6. evasion
	await _reset()
	_quiet(Vector3.ZERO, 0.0)
	Game.set_wanted(1)
	c.police_cd = 99.0
	await _wait(6.0)
	ok("evading: still wanted after 6 s", Game.wanted == 1)
	await _wait(7.5)
	ok("evading: star lost after 12 s unseen", Game.wanted == 0, "wanted=%d" % Game.wanted)
	Game.set_wanted(1)
	c.police_cd = 99.0
	for k in get_tree().get_nodes_in_group("cars"):
		if k.global_position.distance_to(m.player.global_position) < 40.0: k.queue_free()   # nothing to run the watcher over
	var watcher: Ped = c.spawn_cop(m.player.global_position + Vector3(0, 0, 8.0)); watcher.set_physics_process(false)
	await _wait(14.0)
	ok("seen by a cop: star does not decay", Game.wanted == 1 and Game.cop_sees, "wanted=%d sees=%s" % [Game.wanted, Game.cop_sees])
	watcher.queue_free()
	c.police_cd = 0.0
	# 7. respray
	await _reset()
	_quiet(c.respray_pos, 40.0)
	car = m.spawn_car(c.respray_pos + Vector3(0, 0, 12), 0.0, Color.WHITE, false, "suv")
	car.take_damage(50.0)
	m.enter_car(car, true)
	Game.set_wanted(3); Game.cash = 1000
	c.police_cd = 99.0
	_quiet(c.respray_pos, 60.0)
	await _wait(0.4)
	car.global_position = c.respray_pos; car.velocity = Vector3.ZERO
	await _wait(0.5)
	ok("Pay 'n' Spray: -$500, wanted cleared, car repaired", Game.wanted == 0 and Game.cash == 500 and car.health == 100.0, "w=%d cash=%d hp=%.0f ev=%s" % [Game.wanted, Game.cash, car.health, c.last_event])
	car.global_position = c.respray_pos + Vector3(0, 0, 12)
	await _wait(0.3)
	Game.set_wanted(2); c.police_cd = 99.0
	var spy: Ped = c.spawn_cop(c.respray_pos + Vector3(6, 0, 0)); spy.set_physics_process(false)
	await _wait(0.4)
	car.global_position = c.respray_pos
	await _wait(0.5)
	ok("Pay 'n' Spray refuses while a cop is watching", Game.wanted == 2 and c.last_event == "respray_seen", "w=%d ev=%s" % [Game.wanted, c.last_event])
	spy.queue_free()
	c.police_cd = 0.0
	# 8. crusher
	await _reset()
	Game.mult = 1; Game.cash = 0
	car = m.spawn_car(c.crusher_pos + Vector3(0, 0, 12), 0.0, Color.WHITE, false, "sports")
	m.enter_car(car, true)
	Game.cash = 0
	car.global_position = c.crusher_pos; car.velocity = Vector3.ZERO
	await _wait(2.0)
	ok("crusher: sports car -> $1200, player on foot", Game.cash == 1200 and m.player_car == null, "cash=%d ev=%s" % [Game.cash, c.last_event])
	# 9. shop
	await _reset()
	Game.cash = 700
	m.weapons.clear()
	m.player.global_position = c.shop_pads[2][0]
	await _wait(0.3)
	ok("Ammu shop: shotgun for $600", m.weapons.ammo.get("shotgun", 0) == 16 and Game.cash == 100, "cash=%d" % Game.cash)
	m.player.global_position = c.shop_pads[1][0]
	await _wait(0.3)
	ok("Ammu shop: can't afford SMG", m.weapons.ammo.get("smg", 0) == 0 and c.last_event == "shop_broke")
	# 10. mugging
	await _reset()
	pos = _spot(3) + Vector3(0, 0, 4.0)
	_quiet(pos, 30.0)
	m.weapons.clear()
	m.player.global_position = pos
	m.player.rotation.y = 0.0
	var vic: Ped = m.spawn_ped(Game.block_of(pos)); vic.set_physics_process(false); vic.global_position = pos + Vector3(0, 0, -1.2)
	Game.cash = 0
	m.weapons.punch()
	ok("mugging: punch knocks a ped down and takes cash", vic.mugged and vic.stun_t > 0.0 and Game.cash > 0, "cash=%d" % Game.cash)
	# 11. gang kills change respect
	await _reset()
	Game.respect = [0, 0, 0]
	var gm: Ped = c.spawn_gang(1, true)
	gm.hit(999.0, Vector3.FORWARD, true)
	ok("kill a SAINT: Saints -15, their rivals (Serpents) +5", Game.respect[1] == -15 and Game.respect[0] == 5, str(Game.respect))
	# 12. hostile gang shoots
	await _reset()
	Game.respect[2] = -50
	pos = Vector3(4 * P + 6.25, 0.2, 5 * P + 12.0)
	_quiet(pos, 30.0)
	m.player.global_position = pos
	var g2: Ped = m.spawn_ped(Game.block_of(pos), "gang", 2); g2.global_position = pos + Vector3(0, 0, 8)
	await _wait(6.0)
	ok("hated gang (respect <= -25) opens fire", m.player.health < 100.0, "hp=%.0f" % m.player.health)
	Game.respect = [0, 0, 0]
	# 13. payphone missions
	await _reset()
	Game.mult = 1
	m.player.global_position = c.phones[0][0] + Vector3(1, 0, 0)
	m.toggle_car()
	ok("payphone: Serpents give HOT WHEELS (steal a sports car)", not c.mission.is_empty() and c.mission["kind"] == "steal")
	var tc: Car = c.mission["target"]
	m.enter_car(tc, true)
	tc.global_position = c.drop_pos; tc.velocity = Vector3.ZERO
	await _wait(0.5)
	ok("steal mission: delivered -> passed, +25 respect, x2 multiplier", c.mission.is_empty() and Game.respect[0] == 25 and Game.mult == 2, "resp=%s mult=%d ev=%s" % [str(Game.respect), Game.mult, c.last_event])
	await _reset()
	Game.respect[0] = 10
	m.player.global_position = c.phones[0][0] + Vector3(1, 0, 0)
	m.toggle_car()
	ok("respect gate: below 20 -> repeat job, not the big one", c.mission.get("idx", -1) == 0)
	c.mission = {}
	Game.respect[0] = 30
	m.toggle_car()
	ok("respect gate: 20+ -> SAINTS' DAY hit unlocked", c.mission.get("idx", -1) == 1 and c.mission["kind"] == "hit")
	var tgt: Ped = c.mission["target"]
	tgt.hit(999.0, Vector3.FORWARD, true)
	await _wait(0.2)
	ok("hit mission: target killed -> passed", c.mission.is_empty() and c.last_event == "mission_pass_0", c.last_event)
	await _reset()
	Game.respect[1] = -40
	m.player.global_position = c.phones[1][0] + Vector3(-1, 0, 0)
	m.toggle_car()
	ok("hated gang hangs up the phone", c.mission.is_empty() and c.last_event == "phone_refused")
	Game.respect[2] = 0
	m.player.global_position = c.phones[2][0] + Vector3(-1, 0, 0)
	m.toggle_car()
	ok("Kings give a timed checkpoint run", c.mission.get("kind", "") == "run")
	car = m.spawn_car(m.player.global_position + Vector3(-4, 0, 0), 0.0, Color.WHITE, false, "sports")
	m.enter_car(car, true)
	for k in c.mission["cps"].size():
		car.global_position = c.mission["cps"][k]; car.velocity = Vector3.ZERO
		await _wait(0.2)
	ok("timed run: all checkpoints -> passed", c.mission.is_empty() and c.last_event == "mission_pass_2", c.last_event)
	# 14. kill frenzy
	await _reset()
	m.player.global_position = c.skull.global_position
	c.skull_cd = 0.0
	await _wait(0.2)
	ok("kill frenzy starts at the skull", not c.frenzy.is_empty() and m.weapons.ammo.get("smg", 0) >= 150)
	var cash0 := Game.cash
	var mult0 := Game.mult
	var vics := 0
	for p in get_tree().get_nodes_in_group("peds"):
		if p.role == "civ" and p.alive and vics < 12:
			p.hit(999.0, Vector3.FORWARD, true); vics += 1
	ok("kill frenzy: 12 kills -> passed, bonus and multiplier+1", c.frenzy.is_empty() and c.last_event == "frenzy_pass" and Game.mult == mini(mult0 + 1, 5) and Game.cash >= cash0 + 2000 * mult0, "ev=%s" % c.last_event)
	# 15. busted vs wasted
	await _reset()
	Game.cash = 3000; Game.mult = 3
	m.weapons.give("pistol", 30)
	Game.set_wanted(2)
	c.busted()
	await _wait(3.5)
	ok("BUSTED: fine 10% (min $100), weapons taken, x1, at police station", Game.cash == 2700 and m.weapons.ammo.is_empty() and Game.mult == 1 and Game.wanted == 0 and m.player.global_position.distance_to(c.police_pos) < 1.0, "cash=%d" % Game.cash)
	await _reset()
	Game.cash = 3000; Game.mult = 3
	m.weapons.give("smg", 50)
	m.wasted()
	await _wait(4.5)
	ok("WASTED: $250 hospital bill, weapons kept, x1, at hospital", Game.cash == 2750 and m.weapons.ammo.get("smg", 0) == 50 and Game.mult == 1 and m.player.global_position.distance_to(c.hospital_pos) < 1.0, "cash=%d" % Game.cash)
	# 16. arrest on foot by a cop
	await _reset()
	_quiet(Vector3.ZERO, 0.0)
	m.weapons.clear()
	Game.cash = 500
	pos = Vector3(4 * P + 6.25, 0.2, 4 * P + 10.0)
	m.player.global_position = pos
	Game.set_wanted(1); c.police_cd = 99.0
	c.spawn_cop(pos + Vector3(0, 0, 6.0))
	await _wait(5.0)
	ok("1 star: a cop on foot runs you down and arrests you", c.last_event == "busted", c.last_event)
	await _regressions()
	print("TESTS passed=%d failed=%d" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)

## Regression checks for bugs found in review.
func _regressions() -> void:
	var P := Game.P
	# a lieutenant left over from a failed hit job must not pass the next hit job
	await _reset()
	Game.respect = [30, 0, 0]
	c.mission_done[0] = 1
	m.player.global_position = c.phones[0][0] + Vector3(1, 0, 0)
	m.toggle_car()
	var old: Ped = c.mission.get("target")
	c._mission_fail("TEST")
	ok("failed hit job: old target is no longer a mission target", old != null and not old.mission_target)
	m.toggle_car()
	var new_t: Ped = c.mission.get("target")
	old.hit(999.0, Vector3.FORWARD, true)
	await _wait(0.1)
	ok("killing the old lieutenant doesn't pass the new hit job", not c.mission.is_empty() and new_t != old, c.last_event)
	c._mission_clear()
	Game.respect = [0, 0, 0]
	# delivered mission car can't be re-entered while it sinks
	await _reset()
	m.player.global_position = c.phones[0][0] + Vector3(1, 0, 0)
	c.mission_done[0] = 0
	m.toggle_car()
	var tc: Car = c.mission["target"]
	m.enter_car(tc, true)
	tc.global_position = c.drop_pos; tc.velocity = Vector3.ZERO
	await _wait(0.3)
	ok("delivered car leaves the 'cars' group", c.mission.is_empty() and m.player_car == null and not tc.is_in_group("cars"))
	m.player.global_position = tc.global_position + Vector3(1.5, 0, 0)
	m.toggle_car()
	ok("delivered car can't be re-entered", m.player_car != tc and c.breaking.get("car") != tc)
	if m.player_car: m.toggle_car()
	c.breaking = {}; m.player.busy = false
	await _wait(1.8)
	# exiting a car parked against a building puts you on the open side
	await _reset()
	var wall_x := -1.0
	var space: PhysicsDirectSpaceState3D = m.get_world_3d().direct_space_state
	var probe := Vector3(3 * P + Game.ROAD_HALF + Game.WALK + 1.0, 1.0, 3 * P + P * 0.5)
	var hit: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(probe - Vector3(3, 0, 0), probe + Vector3(12, 0, 0), 1))
	if not hit.is_empty(): wall_x = hit.position.x
	if wall_x > 0.0:
		var car: Car = m.spawn_car(Vector3(wall_x - 1.4, 0, probe.z), 0.0, Color.WHITE, false, "sedan")   # facing -Z, driver side (-X) open
		car.rotation.y = PI   # facing +Z: driver side (-basis.x) is +X, i.e. the wall
		await _wait(0.05)
		m.enter_car(car, true)
		m.toggle_car()
		ok("exit: player not placed inside the building", m.player.global_position.x < wall_x, "x=%.1f wall=%.1f" % [m.player.global_position.x, wall_x])
		car.queue_free()
	else:
		ok("exit: found a building wall to test against", false)
	# shooting a wreck is not a crime
	await _reset()
	var pos := _spot(4)
	_quiet(pos, 30.0)
	await _wait(0.1)
	m.player.global_position = pos
	m.player.rotation.y = 0.0
	var wreck: Car = m.spawn_car(pos + Vector3(0, 0, -6), 0.0, Color.WHITE, false, "sedan")
	wreck.dead = true
	wreck.add_to_group("wrecks")
	m.weapons.wanted_cd = 0.0
	m.weapons._pellet(pos + Vector3(0, 1.1, -0.8), Vector3(0, 0, -1), {"dmg": 10.0, "spread": 0.0, "range": 20.0, "color": Color.WHITE})
	ok("shooting a wreck adds no wanted level", Game.wanted == 0, "w=%d" % Game.wanted)
	wreck.queue_free()
	# Pay 'n' Spray works once the watching cop loses sight, without leaving the pad
	await _reset()
	_quiet(c.respray_pos, 60.0)
	var car2: Car = m.spawn_car(c.respray_pos + Vector3(0, 0, 12), 0.0, Color.WHITE, false, "sedan")
	m.enter_car(car2, true)
	Game.set_wanted(2); Game.cash = 1000; c.police_cd = 99.0
	var spy: Ped = c.spawn_cop(c.respray_pos + Vector3(6, 0, 0)); spy.set_physics_process(false)
	await _wait(0.4)
	car2.global_position = c.respray_pos; car2.velocity = Vector3.ZERO
	await _wait(0.5)
	var refused: bool = c.last_event == "respray_seen"
	spy.queue_free()
	await _wait(0.8)
	ok("Pay 'n' Spray: refused while seen, then sprays once the cop is gone", refused and Game.wanted == 0 and c.last_event == "respray", "ev=%s w=%d" % [c.last_event, Game.wanted])
	c.police_cd = 0.0
	m.toggle_car()
	# traffic respawns never land on top of another car
	var bad := 0
	for k in 20:
		var tc2: Car = m.spawn_traffic_random(m.player.global_position, 45.0)
		if tc2 == null: continue
		for o in get_tree().get_nodes_in_group("cars"):
			if o != tc2 and o.global_position.distance_to(tc2.global_position) < 7.0: bad += 1
		if tc2.global_position.distance_to(m.player.global_position) < 45.0: bad += 1
	ok("traffic respawn: clear lane, away from the player", bad == 0, "bad=%d" % bad)
	await _design_fixes()

## Checks for the design-level fixes (second review pass).
func _design_fixes() -> void:
	var P := Game.P
	# running over a crowd: +1 star, not +1 per body
	await _reset()
	var pos := _spot(5)
	_quiet(pos, 40.0)
	for k in get_tree().get_nodes_in_group("cars"):
		if k.global_position.distance_to(pos + Vector3(10, 0, 0)) < 14.0: k.queue_free()   # clear the run-up
	await _wait(0.1)
	var car: Car = m.spawn_car(pos, Game.yaw_of(Vector3(1, 0, 0)), Color.WHITE, false, "sports")
	m.enter_car(car, true)
	Game.set_wanted(0)
	for k in 5:
		var v: Ped = m.spawn_ped(Game.block_of(pos)); v.set_physics_process(false)
		v.global_position = pos + Vector3(4.0 + k * 1.2, 0.2, 0)
	car.velocity = car.forward() * 20.0
	await _wait(0.6)
	var killed := 0
	for v in get_tree().get_nodes_in_group("dead_peds"):
		if v.global_position.distance_to(pos) < 25.0: killed += 1
	ok("running over a crowd: one star, not one per body", killed >= 3 and Game.wanted == 1, "killed=%d wanted=%d" % [killed, Game.wanted])
	m.toggle_car()
	# hit job: someone else killing the target fails it
	await _reset()
	Game.respect = [30, 0, 0]
	c.mission_done[0] = 1
	m.player.global_position = c.phones[0][0] + Vector3(1, 0, 0)
	m.toggle_car()
	var tgt: Ped = c.mission.get("target")
	tgt.kill(Vector3.FORWARD, false)
	ok("hit job: target killed by someone else -> failed", tgt != null and c.mission.is_empty() and c.last_event == "mission_fail", c.last_event)
	Game.respect = [0, 0, 0]
	# explosion credit: a car the player shot blows up and kills a ped -> player's kill
	await _reset()
	pos = _spot(6)
	_quiet(pos, 30.0)
	await _wait(0.1)
	var bomb: Car = m.spawn_car(pos, 0.0, Color.WHITE, false, "sedan")
	var by := Ped.new(); m.add_child(by); by.setup(Game.block_of(pos)); by.set_physics_process(false)
	by.global_position = pos + Vector3(3, 0.2, 0)
	var credit := [false]
	var cb := func(p, bp): if p == by: credit[0] = bp
	Game.ped_killed.connect(cb)
	bomb.blame_t = Game.clock
	bomb.explode()
	Game.ped_killed.disconnect(cb)
	ok("explosion of a car the player shot: kills count as the player's", not by.alive and credit[0])
	# abandoned stolen cars are cleaned up out of sight
	await _reset()
	var ab: Car = m.spawn_car(_spot(7), 0.0, Color.WHITE, false, "sedan")
	ab.set_meta("owned", true)
	ab.set_meta("idle", 59.95)
	m.player.global_position = ab.global_position + Vector3(0, 0, 120.0)
	m.cam.global_position = Vector3(m.player.global_position.x, m.cam_h, m.player.global_position.z)
	await _wait(0.3)
	ok("abandoned stolen car removed after a minute out of sight", not is_instance_valid(ab) or ab.is_queued_for_deletion())
	# respray repaints the body only (wheels keep their material)
	var rc: Car = m.spawn_car(_spot(8), 0.0, Color.WHITE, false, "taxi")
	rc.respray(Color(0.1, 0.3, 0.85))
	var body := rc.model.get_node("body") as MeshInstance3D
	var wheel := rc.model.get_node("wheel-front-left") as MeshInstance3D
	var bmat := body.get_surface_override_material(0) as StandardMaterial3D
	var ok_paint: bool = bmat != null and bmat.albedo_texture != body.mesh.surface_get_material(0).albedo_texture and bmat.albedo_color == Color.WHITE
	ok("respray: body gets a repainted palette, wheels untouched", ok_paint and wheel.get_surface_override_material(0) == null)
	rc.queue_free()
	# one crash is counted once for both cars
	await _reset()
	pos = _spot(9) + Vector3(0, 0, 0)
	_quiet(pos, 30.0)
	await _wait(0.1)
	var a: Car = m.spawn_car(pos, Game.yaw_of(Vector3(1, 0, 0)), Color.WHITE, false, "sedan")
	var b: Car = m.spawn_car(pos + Vector3(7, 0, 0), Game.yaw_of(Vector3(-1, 0, 0)), Color.WHITE, false, "sedan")
	a.velocity = Vector3(14, 0, 0); b.velocity = Vector3(-14, 0, 0)
	a.ctrl = Car.Ctrl.PLAYER   # full throttle-free coast; PLAYER so input is read (none pressed)
	await _wait(0.5)
	a.ctrl = Car.Ctrl.NONE
	var lost_a := 100.0 - a.health; var lost_b := 100.0 - b.health
	ok("head-on crash damages each car once", lost_a > 0.0 and lost_b > 0.0 and lost_a <= 60.0 and lost_b <= 60.0, "a=%.0f b=%.0f" % [lost_a, lost_b])
	a.queue_free(); b.queue_free()
	# police spawn on a clear lane, out of sight when possible
	await _reset()
	var hidden := 0; var clash := 0
	for k in 10:
		var sp: Vector3 = m.police_spawn_point(m.player.global_position)
		if sp == Vector3.INF: continue
		if not c.los(sp, m.player.global_position): hidden += 1
		if m._car_near(sp, 6.0): clash += 1
	ok("police spawn: clear lane, out of the player's sight", clash == 0 and hidden >= 8, "hidden=%d clash=%d" % [hidden, clash])
	# pedestrians sometimes jump clear of a speeding car
	await _reset()
	pos = _spot(10)
	_quiet(pos, 40.0)
	await _wait(0.1)
	var dodged := 0
	for k in 10:
		var walker: Ped = m.spawn_ped(Game.block_of(pos)); walker.global_position = pos + Vector3(14.0, 0.2, k * 0.0)
		var runner: Car = m.spawn_car(pos, Game.yaw_of(Vector3(1, 0, 0)), Color.WHITE, false, "sports")
		runner.ctrl = Car.Ctrl.NONE
		runner.velocity = Vector3(18, 0, 0)
		await _wait(1.2)
		if walker.alive: dodged += 1
		walker.queue_free(); runner.queue_free()
		await _wait(0.05)
	ok("pedestrians dodge speeding cars some of the time", dodged >= 2 and dodged <= 9, "dodged=%d/10" % dodged)
	# progress save round-trip
	var sp_path := "user://test_save.cfg"
	Game.cash = 4321; Game.mult = 3; Game.respect = [10, -20, 30]; c.mission_done = [1, 0, 2]
	m.weapons.ammo = {"smg": 77}; m.weapons.current = "smg"
	m.save.save_game(sp_path)
	Game.cash = 0; Game.mult = 1; Game.respect = [0, 0, 0]; c.mission_done = [0, 0, 0]; m.weapons.clear()
	var loaded: bool = m.save.load_game(sp_path)
	ok("save/load keeps cash, multiplier, respect, missions and ammo", loaded and Game.cash == 4321 and Game.mult == 3 and Game.respect == [10, -20, 30] and c.mission_done == [1, 0, 2] and m.weapons.ammo.get("smg", 0) == 77 and m.weapons.current == "smg")
	m.save.reset(sp_path)
	Game.respect = [0, 0, 0]; c.mission_done = [0, 0, 0]; Game.mult = 1
	# losing the cops: police cars rejoin traffic on their own road
	await _reset()
	var pc: Car = m.spawn_car(Vector3(3 * P + Game.LANE, 0, 4 * P + 12.0), Game.yaw_of(Vector3(0, 0, 1)), Color.WHITE, true)
	pc.start_police()
	Game.set_wanted(1)
	Game.set_wanted(0)
	ok("cleared wanted: cop car heads for the junction ahead on its road", pc.ctrl == Car.Ctrl.TRAFFIC and pc.ai_dir == Vector2i(0, 1) and pc.ai_node == Vector2i(3, 5), "dir=%s node=%s" % [pc.ai_dir, pc.ai_node])
	pc.queue_free()
