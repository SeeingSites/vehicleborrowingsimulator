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
	get_tree().quit()
