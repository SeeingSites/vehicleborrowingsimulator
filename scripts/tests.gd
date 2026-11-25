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
		if k.ctrl == Car.Ctrl.POLICE or k.has_meta("roadblock"): k.queue_free()

func _reset() -> void:
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
	var seen_van := false
	for k in 40:
		await _wait(0.5)
		for v in get_tree().get_nodes_in_group("cars"):
			if v.has_meta("swat") and v.ctrl == Car.Ctrl.POLICE: seen_van = true
	cars = 0; vans = 0
	for k in get_tree().get_nodes_in_group("cars"):
		if k.ctrl == Car.Ctrl.POLICE and not k.dead:
			if k.has_meta("swat"): vans += 1
			else: cars += 1
	ok("5 stars: up to 4 cop cars (>=3 alive) + a SWAT van (max 1)", cars >= 3 and cars <= 4 and vans <= 1 and seen_van, "cars=%d vans=%d" % [cars, vans])
	var swat := 0; var footcops := 0
	for p in c.foot_cops():
		if p.role == "swat": swat += 1
		else: footcops += 1
	ok("cops get out on foot when they reach you", footcops + swat > 0, "foot=%d swat=%d" % [footcops, swat])
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
	await _wait(3.0)
	ok("3 stars: cops on foot shoot you", m.player.health < 100.0, "hp=%.0f" % m.player.health)
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
	print("TESTS passed=%d failed=%d" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)
