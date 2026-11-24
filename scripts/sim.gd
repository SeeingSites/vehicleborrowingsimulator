extends Node
## Headless traffic simulation for the jam metric:
##   godot --headless --fixed-fps 60 --path . -- --sim=300 [--no-signals]
var m
const WARMUP := 30.0
const JAM_T := 20.0   # 'gridlocked' = stationary 20 s+; 'jammed' = stationary 5 s+ and not queued at a red light

func run(main_) -> void:
	m = main_
	m.add_child(self)
	m.player.global_position = Vector3(-80, 0.2, -80)
	m.player.visible = false
	m.player.collision_layer = 0
	_go.call_deferred()

func _traffic() -> Array:
	var out := []
	for c in get_tree().get_nodes_in_group("cars"):
		if c.ctrl == Car.Ctrl.TRAFFIC and not c.dead: out.append(c)
	return out

func _go() -> void:
	var t := 0.0
	var samples := 0
	var jam_sum := 0.0
	var crawl_sum := 0.0
	var speed_sum := 0.0
	var start_cross := {}
	var ever_stuck := {}
	var peak := 0.0
	var dt := 1.0
	while t < Game.sim_seconds:
		await get_tree().create_timer(dt, true, true).timeout
		t += dt
		var cars := _traffic()
		if t < WARMUP:
			continue
		if start_cross.is_empty():
			for c in cars: start_cross[c.get_instance_id()] = c.crossings
		var jammed := 0
		var crawl := 0
		var sp := 0.0
		for c in cars:
			sp += c.speed()
			if c.still_t >= 5.0 and not c.red_queued():
				crawl += 1
			if c.still_t >= JAM_T:
				jammed += 1
				if OS.get_environment("SIMDEBUG") != "" and int(c.still_t) == int(JAM_T):
					print("STUCK phase=%d held=%.1f wait=%.1f node=%s dir=%s pend=%s pos=%s light=%d" % [c.ai_phase, c.held_t, c.wait_t, c.ai_node, c.ai_dir, c.pending, c.global_position, Game.light_for(c.ai_node, c.ai_dir.x == 0)])
				ever_stuck[c.get_instance_id()] = true
		var f := float(jammed) / maxf(1.0, cars.size())
		peak = maxf(peak, f)
		jam_sum += f
		crawl_sum += float(crawl) / maxf(1.0, cars.size())
		speed_sum += sp / maxf(1.0, cars.size())
		samples += 1
	var cross := 0; var n := 0
	for c in _traffic():
		var id: int = c.get_instance_id()
		if start_cross.has(id):
			cross += c.crossings - start_cross[id]; n += 1
	var minutes := (Game.sim_seconds - WARMUP) / 60.0
	var wrecks := get_tree().get_nodes_in_group("wrecks").size()
	var res := {
		"signals": Game.signals, "sim_seconds": Game.sim_seconds, "cars": m.n_traffic, "seed": Game.rng.seed,
		"jam_rate_pct": snappedf(100.0 * crawl_sum / samples, 0.01),
		"gridlock_pct": snappedf(100.0 * jam_sum / samples, 0.01),
		"peak_jam_pct": snappedf(100.0 * peak, 0.01),
		"cars_ever_stuck_20s": ever_stuck.size(),
		"mean_speed_kmh": snappedf(3.6 * speed_sum / samples, 0.1),
		"intersections_per_car_min": snappedf(float(cross) / maxf(1, n) / minutes, 0.01),
		"wrecks": wrecks,
		"car_contacts_per_min": snappedf(Game.car_contacts / (Game.sim_seconds / 60.0), 0.01),
	}
	print("SIMRESULT ", JSON.stringify(res))
	get_tree().quit()
