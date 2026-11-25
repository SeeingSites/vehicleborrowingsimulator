extends Node
## Scripted gameplay scenarios used to capture screenshots headlessly:
##   godot --path . -- --shot=onfoot|driving|traffic|police
var m

func run(main_, name: String) -> void:
	m = main_
	m.add_child(self)
	_go.call_deferred(name)

func _wait(s: float) -> void:
	await get_tree().create_timer(s, true, true).timeout

func _capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	if OS.has_feature("web"):
		print("SHOT_READY ", name)
		get_tree().paused = false
		await get_tree().create_timer(3.0).timeout
		return
	var img: Image = get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path("res://screenshots/%s.png" % name)
	img.save_png(path)
	print("SAVED ", path, " ", img.get_size())

func _clear_lane(z: float, x0: float, x1: float) -> void:
	for c in get_tree().get_nodes_in_group("cars"):
		if c != m.player_car and absf(c.global_position.z - z) < 4.0 and c.global_position.x > x0 and c.global_position.x < x1:
			c.queue_free()

func _go(name: String) -> void:
	var P := Game.P
	await _wait(0.3)
	m.hud.shown_cash = 1240.0
	match name:
		"onfoot":
			Game.cash = 1240
			for b in [Vector2i(4, 2), Vector2i(5, 2), Vector2i(4, 3), Vector2i(5, 3)]:
				for i in 4: m.spawn_ped(b)
			# a few locals on the same street
			for k in 6:
				var blk := Vector2i(4, 3) if k % 2 == 0 else Vector2i(5, 3)
				var pd = m.spawn_ped(blk)
				var cn := (1 if k % 4 < 2 else 2) if blk.x == 4 else (0 if k % 4 < 2 else 3)
				pd.corner = cn
				pd.target = Ped._corner_pos(blk, cn)
				pd.global_position = Vector3(pd.target.x, 0.2, 4 * P - 22.0 + k * 3.0)
			m.player.global_position = Vector3(5 * P - 6.25, 0.2, 4 * P - 8.0)
			m.cam.global_position = Vector3(0, 0, 0)
			Input.action_press("move_up")
			await _wait(0.8)
			Input.action_press("move_right", 0.5)
			await _wait(0.25)
			Input.action_release("move_right")
			await _wait(0.2)
			Input.action_release("move_up")
			await _wait(0.3)
			await _capture("01_on_foot")
		"driving":
			Game.cash = 1240
			var z := 4 * P + Game.LANE
			_clear_lane(z, 0.0, 8 * P)
			var car = m.spawn_car(Vector3(0.6 * P, 0, z), Game.yaw_of(Vector3(1, 0, 0)), Color(0.9, 0.1, 0.1))
			m.enter_car(car)
			m.cam.global_position = Vector3(0, 0, 0)
			Input.action_press("move_up")
			await _wait(2.6)
			Input.action_press("move_left", 0.6)
			Input.action_press("handbrake")
			await _wait(0.22)
			Input.action_release("handbrake")
			Input.action_press("move_right", 0.6)
			Input.action_release("move_left")
			await _wait(0.25)
			await _capture("02_driving_fast")
		"traffic":
			Game.cash = 1240
			var n := Vector2i(4, 4)
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				m.spawn_traffic_at(n - d, d, 0.45)
				m.spawn_traffic_at(n - d, d, 0.7)
				m.spawn_traffic_at(n, d, 0.35)
			for b in [Vector2i(3, 3), Vector2i(4, 3), Vector2i(3, 4), Vector2i(4, 4)]:
				for i in 5: m.spawn_ped(b)
			m.player.global_position = Vector3(4 * P + 6.25, 0.2, 4 * P + 9.0)
			m.cam.global_position = Vector3(0, 0, 0)
			await _wait(2.5)
			await _capture("03_traffic_peds")
		"police":
			Game.cash = 1230
			var z := 4 * P + Game.LANE
			_clear_lane(z, 0.0, 8 * P)
			var car = m.spawn_car(Vector3(2.0 * P, 0, z), Game.yaw_of(Vector3(1, 0, 0)), Color(0.95, 0.75, 0.1))
			m.enter_car(car)
			m.cam.global_position = Vector3(0, 0, 0)
			Game.set_wanted(2)
			var c1 = m.spawn_car(Vector3(2.0 * P - 16.0, 0, z), Game.yaw_of(Vector3(1, 0, 0)), Color.WHITE, true)
			c1.start_police()
			c1.velocity = c1.forward() * 10.0
			var c2 = m.spawn_car(Vector3(2.0 * P - 28.0, 0, z - 5.0), Game.yaw_of(Vector3(1, 0, 0)), Color.WHITE, true)
			c2.start_police()
			c2.velocity = c2.forward() * 10.0
			# a pedestrian wanders into the road...
			var p = m.spawn_ped(Vector2i(2, 3))
			p.set_physics_process(false)
			p.global_position = Vector3(2.0 * P + 26.0, 0.0, z)
			Input.action_press("move_up")
			await _wait(2.3)
			await _capture("04_police_chase")
		"signals":
			Game.cash = 1240
			Game.sig_time = 0.2
			var n := Vector2i(4, 4)
			for t in [0.15, 0.35, 0.55]:
				m.spawn_traffic_at(Vector2i(3, 4), Vector2i(1, 0), t)
				m.spawn_traffic_at(Vector2i(5, 4), Vector2i(-1, 0), t)
			m.spawn_traffic_at(Vector2i(4, 3), Vector2i(0, 1), 0.4)
			m.spawn_traffic_at(Vector2i(4, 5), Vector2i(0, -1), 0.55)
			for b in [Vector2i(3, 3), Vector2i(4, 3), Vector2i(3, 4), Vector2i(4, 4)]:
				for i in 4: m.spawn_ped(b)
			m.player.global_position = Vector3(4 * P + 6.6, 0.2, 4 * P + 6.6)
			m.cam.global_position = Vector3(0, 0, 0)
			await _wait(3.8)
			await _capture("v2/01_traffic_lights")
		"damage":
			Game.cash = 1240
			var z := 4 * P + Game.LANE
			_clear_lane(z, 0.0, 8 * P)
			var car = m.spawn_car(Vector3(2.0 * P, 0, z), Game.yaw_of(Vector3(1, 0, 0)), Color(0.1, 0.35, 0.85))
			m.enter_car(car)
			car.take_damage(64.0)
			var wreck = m.spawn_car(Vector3(2.0 * P + 17.0, 0, z - 1.0), Game.yaw_of(Vector3(1, 0.0, 0.4)), Color(0.15, 0.6, 0.25))
			wreck.take_damage(87.0)
			wreck.burn_t = 60.0
			m.cam.global_position = Vector3(0, 0, 0)
			Input.action_press("move_up", 0.45)
			await _wait(1.2)
			Input.action_release("move_up")
			await _wait(1.0)
			await _capture("v2/02_damaged_smoking")
		"explosion":
			Game.cash = 1240
			var z := 4 * P + Game.LANE
			_clear_lane(z, 0.0, 8 * P)
			m.player.global_position = Vector3(2.0 * P + 1.0, 0.2, 4 * P + 6.5)
			var c1 = m.spawn_car(Vector3(2.0 * P + 14.0, 0, z), Game.yaw_of(Vector3(1, 0, 0)), Color(0.9, 0.1, 0.1))
			var c2 = m.spawn_car(Vector3(2.0 * P + 20.5, 0, z - 4.5), Game.yaw_of(Vector3(-1, 0, 0)), Color(0.95, 0.75, 0.1))
			c1.take_damage(88.0)
			c1.burn_t = 1.0
			m.cam.global_position = Vector3(0, 0, 0)
			await c1.exploded
			await _wait(0.12)
			await _capture("v2/03_explosion")
		"wasted":
			Game.cash = 1240
			Game.set_wanted(2)
			var z := 4 * P + Game.LANE
			_clear_lane(z, 0.0, 8 * P)
			var car = m.spawn_car(Vector3(2.0 * P, 0, z), Game.yaw_of(Vector3(1, 0, 0)), Color(0.55, 0.15, 0.6))
			m.enter_car(car)
			car.take_damage(88.0)
			car.burn_t = 1.2
			m.cam.global_position = Vector3(0, 0, 0)
			await car.exploded
			await _wait(0.45)
			await _capture("v2/04_wasted")
		"shooting":
			Game.cash = 1240
			var wp = m.weapons
			wp.ammo["smg"] = 120; wp.ammo["pistol"] = 30; wp.current = "smg"
			var x := 4 * P - Game.LANE
			var tgt = m.spawn_car(Vector3(x, 0, 4 * P + 13.0), 0.0, Color.WHITE, false, "taxi")
			for k in 3:
				var pd = m.spawn_ped(Vector2i(3, 4))
				pd.set_physics_process(false)
				pd.global_position = Vector3(4 * P - 6.6, 0.2, 4 * P + 8.0 + k * 2.2)
			m.player.global_position = Vector3(4 * P + 6.4, 0.2, 4 * P + 12.0)
			m.player.rotation.y = PI / 2
			m.cam.global_position = Vector3(0, 0, 0)
			await _wait(0.6)
			wp.auto_fire = true
			await _wait(0.5)
			await wp.fired
			await _capture("v3/01_shooting_smg")
			wp.auto_fire = false
		"driveby":
			Game.cash = 1240
			var wp = m.weapons
			wp.ammo["pistol"] = 30; wp.current = "pistol"
			var z := 4 * P + Game.LANE
			_clear_lane(z, 0.0, 8 * P)
			var car = m.spawn_car(Vector3(2.0 * P, 0, z), Game.yaw_of(Vector3(1, 0, 0)), Color.WHITE, false, "sports")
			m.enter_car(car)
			Game.set_wanted(1)
			var cop = m.spawn_car(Vector3(2.0 * P + 22.0, 0, z), Game.yaw_of(Vector3(1, 0, 0)), Color.WHITE, true)
			cop.start_police()
			cop.take_damage(40.0)
			m.cam.global_position = Vector3(0, 0, 0)
			Input.action_press("move_up", 0.5)
			await _wait(0.9)
			wp.auto_fire = true
			await _wait(0.6)
			await wp.fired
			await _capture("v3/02_driveby_minimap")
			wp.auto_fire = false
		"cars":
			Game.cash = 1240
			var z := 4 * P + Game.LANE
			_clear_lane(z, 0.0, 8 * P)
			_clear_lane(z - 2 * Game.LANE, 0.0, 8 * P)
			var types := ["sedan", "sports", "hatchback", "taxi", "suv", "van", "truck", "police"]
			var x0 := 3.5 * P - 3.5 * 5.6
			for i in types.size():
				var c = m.spawn_car(Vector3(x0 + i * 5.6, 0, 4 * P - 1.0), 0.0, Color.WHITE, types[i] == "police", types[i])
				var lbl := Label3D.new()
				lbl.text = types[i].to_upper()
				lbl.font_size = 52
				lbl.outline_size = 24
				lbl.pixel_size = 0.012
				lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
				lbl.no_depth_test = true
				lbl.position = Vector3(0, 3.0, 4.0)
				c.add_child(lbl)
			m.player.global_position = Vector3(3.5 * P, 0.2, 4 * P + 2.5)
			m.cam.global_position = Vector3(0, 0, 0)
			await _wait(0.8)
			await _capture("v3/03_car_types")
		_:
			if name.begins_with("v4_"): await _v4(name.substr(3))
	if not OS.has_feature("web"): get_tree().quit()

func _snap() -> void:
	m.cam.global_position = Vector3(0, 0, 0)

func _isolate(pos: Vector3, r: float) -> void:
	for p in get_tree().get_nodes_in_group("peds"):
		if p.global_position.distance_to(pos) < r: p.queue_free()
	for k in get_tree().get_nodes_in_group("cars"):
		if k.global_position.distance_to(pos) < r and k != m.player_car: k.queue_free()

func _stand(p: Ped) -> Ped:
	p.set_physics_process(false)
	return p

func _v4(name: String) -> void:
	var P := Game.P
	var cr = m.crime
	cr.no_bust = true
	Game.cash = 1240
	m.hud.shown_cash = 1240.0
	match name:
		"steal":
			Game.force_touch_ui = true
			m.touch.visible = true
			var car: Car = null
			for k in get_tree().get_nodes_in_group("cars"):
				if k.ctrl == Car.Ctrl.NONE and k.global_position.distance_to(cr.drop_pos) < 14.0: car = k; break
			m.player.global_position = car.global_position + car.global_transform.basis.x * 2.0 + Vector3(0, 0.2, 0)
			m.player.rotation.y = car.rotation.y + PI / 2
			_snap()
			await _wait(0.6)
			cr.start_break_in(car)
			await _wait(0.35)
			await _capture("v4/01_steal_breakin_touch")
		"carjack":
			var z := 4 * P + Game.LANE
			_isolate(Vector3(3.5 * P, 0, z), 30.0)
			var car: Car = m.spawn_car(Vector3(3.5 * P, 0, z), Game.yaw_of(Vector3(1, 0, 0)), Color.WHITE, false, "taxi")
			car.ctrl = Car.Ctrl.TRAFFIC
			car.set_physics_process(false)
			var cop: Ped = _stand(m.spawn_ped(Vector2i(3, 4), "cop"))
			cop.global_position = Vector3(3.5 * P - 9.0, 0.15, z + 4.5)
			cop.rotation.y = Game.yaw_of(Vector3(1, 0, -0.4))
			m.player.global_position = Vector3(3.5 * P, 0.2, z + 2.2)
			_snap()
			await _wait(0.5)
			m.enter_car(car, true)
			car.set_physics_process(true)
			await _wait(0.4)
			await _capture("v4/02_carjack_seen_by_cop")
		"footcops":
			m.god = true
			var pos := Vector3(4 * P + 6.25, 0.2, 4 * P + 12.0)
			_isolate(pos, 25.0)
			m.player.global_position = pos
			Game.set_wanted(3)
			cr.police_cd = 99.0
			for k in 3:
				var cp: Ped = cr.spawn_cop(pos + Vector3(-6.0 + k * 6.0, 0, -11.0 + absf(k - 1) * 2.0))
			var cc: Car = m.spawn_car(pos + Vector3(-12.6, 0, -6), PI / 2, Color.WHITE, true)
			cc.ctrl = Car.Ctrl.POLICE; cc.set_meta("deployed", true); cc.set_physics_process(false)
			_snap()
			await _wait(0.8)
			await Game.npc_fired
			await _capture("v4/03_armed_cops_on_foot_3stars")
		"roadblock":
			m.god = true
			var z := 4 * P + Game.LANE
			_clear_lane(z, 0.0, 8 * P)
			var car = m.spawn_car(Vector3(1.6 * P, 0, z), Game.yaw_of(Vector3(1, 0, 0)), Color.WHITE, false, "sports")
			m.enter_car(car, true)
			Game.set_wanted(4)
			cr.police_cd = 99.0; cr.rb_cd = 99.0
			cr.place_roadblock(Vector2i(3, 4), Vector2i(-1, 0))
			_snap()
			Input.action_press("move_up", 0.55)
			await _wait(1.3)
			await _capture("v4/04_roadblock_4stars")
			Input.action_release("move_up")
		"swat":
			m.god = true
			var pos := Vector3(4 * P + 6.25, 0.2, 4 * P + 4.0)
			_isolate(pos, 28.0)
			m.player.global_position = pos
			Game.set_wanted(5)
			cr.police_cd = 99.0
			var van: Car = m.spawn_car(Vector3(4 * P - Game.LANE, 0, 4 * P - 6.0), 0.3, Color.WHITE, false, "van")
			van.set_meta("swat", true); van.respray(Color(0.25, 0.28, 0.4)); van.ctrl = Car.Ctrl.POLICE
			van.set_meta("deployed", true); van.set_physics_process(false)
			for k in 4:
				cr.spawn_cop(van.global_position + Vector3(-2.6 + (k % 2) * 5.2, 0, 0.5 + (k / 2) * 2.5), "swat")
			_snap()
			await _wait(0.9)
			await Game.npc_fired
			await _capture("v4/05_swat_team_5stars")
		"respray":
			var car = m.spawn_car(cr.respray_pos + Vector3(0, 0, 14), 0.0, Color.WHITE, false, "hatchback")
			m.enter_car(car, true)
			car.take_damage(70.0)
			Game.set_wanted(3)
			cr.police_cd = 99.0
			_snap()
			await _wait(0.4)
			car.global_position = cr.respray_pos + Vector3(0, 0, 1.5); car.velocity = Vector3.ZERO
			await _wait(0.5)
			await _capture("v4/06_pay_n_spray")
		"busted":
			var pos := Vector3(4 * P + 6.25, 0.2, 4 * P + 12.0)
			_isolate(pos, 20.0)
			m.player.global_position = pos
			Game.set_wanted(2)
			m.weapons.give("pistol", 30)
			cr.police_cd = 99.0
			var cc: Car = m.spawn_car(pos + Vector3(-3.7, 0, 0), 0.0, Color.WHITE, true)
			cc.start_police(); cc.set_physics_process(false)
			_stand(cr.spawn_cop(pos + Vector3(0, 0, -1.6)))
			_snap()
			await _wait(0.5)
			cr.no_bust = false
			cr.busted()
			await _wait(0.7)
			await _capture("v4/07_busted")
		"hospital":
			Game.cash = 1240
			m.weapons.give("smg", 80)
			m.wasted()
			await _wait(2.1)
			await _capture("v4/08_wasted_hospital_respawn")
		"phone":
			m.player.global_position = cr.phones[0][0] + Vector3(1.2, 0, 0.6)
			m.player.rotation.y = PI / 2
			_snap()
			await _wait(0.6)
			m.toggle_car()
			await _wait(0.5)
			await _capture("v4/09_payphone_mission")
		"gangs":
			m.god = true
			Game.respect = [35, -60, 10]
			Game.respect_changed.emit()
			var pos := Vector3(6 * P - 6.25, 0.2, 3 * P + 14.0)
			_isolate(pos, 25.0)
			m.player.global_position = pos
			m.player.rotation.y = PI / 2
			for k in 3:
				var g: Ped = m.spawn_ped(Vector2i(6, 3), "gang", 1)
				g.global_position = pos + Vector3(9.0 + k * 1.5, 0, -6.0 + k * 5.0)
			_snap()
			await _wait(1.0)
			cr.turf = -2
			await Game.npc_fired
			await _capture("v4/10_gang_turf_hostile_saints")
		"crusher":
			var car = m.spawn_car(cr.crusher_pos + Vector3(0, 0, 14), 0.0, Color.WHITE, false, "sports")
			m.enter_car(car, true)
			_snap()
			await _wait(0.3)
			car.global_position = cr.crusher_pos; car.velocity = Vector3.ZERO
			await _wait(1.75)
			await _capture("v4/11_car_crusher")
		"shop":
			Game.cash = 1240
			m.player.global_position = cr.shop_pads[0][0] + Vector3(0, 0, 3.0)
			_snap()
			await _wait(0.4)
			m.player.global_position = cr.shop_pads[1][0]
			await _wait(0.35)
			await _capture("v4/12_ammu_weapon_shop")
		"frenzy":
			var sk: Vector3 = cr.skull.global_position
			m.player.global_position = sk + Vector3(0, -0.7, 0)
			m.player.rotation.y = PI / 2   # face -X
			for k in 7:
				var pd: Ped = _stand(m.spawn_ped(Game.block_of(sk)))
				pd.global_position = sk + Vector3(-5.0 - k * 1.6, -0.7, -0.4 + (k % 3) * 0.4)
			_snap()
			await _wait(0.4)
			m.weapons.auto_fire = true
			await _wait(1.3)
			await m.weapons.fired
			await _capture("v4/13_kill_frenzy")
			m.weapons.auto_fire = false
		"mug":
			Game.mult = 2
			var pos := Vector3(3 * P + 4.5, 0.2, 4 * P - 6.25)
			_isolate(pos, 14.0)
			m.player.global_position = pos
			m.player.rotation.y = PI / 2
			var v: Ped = _stand(m.spawn_ped(Vector2i(3, 4)))
			v.global_position = pos + Vector3(-1.2, 0, 0)
			for k in 3:
				var o: Ped = m.spawn_ped(Vector2i(3, 4))
				o.global_position = pos + Vector3(-1.5 + k * 1.2, 0, -5.0 - k * 1.5)
			_snap()
			await _wait(0.5)
			m.weapons.punch()
			await _wait(0.45)
			await _capture("v4/14_mugging_multiplier")
