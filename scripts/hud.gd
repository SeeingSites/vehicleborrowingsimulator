extends CanvasLayer
## GTA2-style HUD: cash (top right), wanted stars (top centre), speed, messages.

var cash_l: Label
var stars: Control
var speed_l: Label
var msg_l: Label
var hint_l: Label
var touch_ui: Control
var bars: Control
var panel: Control
var minimap: Control
var gauge: Control
var weapon_l: Label
var wasted_rect: ColorRect
var wasted_l: Label
var msg_t := 0.0
var mult_l: Label
var obj_l: Label
var zone_l: Label
var evade_l: Label
var respect: Control
var shown_cash := 0.0

func _ready() -> void:
	layer = 10
	cash_l = _label(44, Color(1.0, 0.86, 0.15))
	cash_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cash_l.size = Vector2(400, 60)
	stars = StarBar.new()
	add_child(stars)
	speed_l = _label(34, Color(0.6, 1.0, 0.6))
	speed_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	speed_l.size = Vector2(320, 50)
	msg_l = _label(64, Color(1, 1, 1))
	msg_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg_l.size = Vector2(800, 90)
	hint_l = _label(16, Color(0.9, 0.9, 0.9))
	hint_l.text = "WASD move · E steal/enter/exit car, answer phones · SPACE handbrake · H horn · CTRL/F/click fire or punch · Q weapon · Esc pause · M mute"
	Game.message.connect(_on_msg)
	panel = Panel2.new()
	add_child(panel)
	move_child(panel, 0)
	bars = Bars.new()
	add_child(bars)
	minimap = Minimap.new()
	add_child(minimap)
	gauge = Gauge.new()
	add_child(gauge)
	weapon_l = _label(22, Color(1, 1, 1))
	weapon_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	weapon_l.size = Vector2(300, 30)
	wasted_rect = ColorRect.new()
	wasted_rect.color = Color(0.55, 0.0, 0.0, 0.35)
	wasted_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wasted_rect.visible = false
	add_child(wasted_rect)
	wasted_l = _label(120, Color(0.95, 0.1, 0.1))
	wasted_l.text = "WASTED"
	wasted_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wasted_l.size = Vector2(900, 160)
	wasted_l.add_theme_constant_override("outline_size", 24)
	wasted_l.visible = false
	mult_l = _label(30, Color(1.0, 0.6, 0.15))
	mult_l.size = Vector2(80, 40)
	obj_l = _label(24, Color(1.0, 0.95, 0.5))
	obj_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	obj_l.size = Vector2(700, 70)
	zone_l = _label(22, Color(0.9, 0.95, 1.0))
	zone_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	zone_l.size = Vector2(700, 34)
	evade_l = _label(16, Color(0.7, 1.0, 0.7))
	evade_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	evade_l.size = Vector2(300, 24)
	respect = Respect.new()
	add_child(respect)

func show_wasted(on: bool) -> void:
	show_overlay(on, "WASTED", Color(0.95, 0.1, 0.1))

func show_overlay(on: bool, text := "", col := Color.WHITE) -> void:
	wasted_rect.visible = on
	wasted_l.visible = on
	if on:
		wasted_l.text = text
		wasted_l.add_theme_color_override("font_color", col)
		wasted_rect.color = Color(col.r * 0.5, col.g * 0.5, col.b * 0.5, 0.35)

func _label(sz: int, col: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	l.add_theme_constant_override("outline_size", maxi(6, sz / 5))
	add_child(l)
	return l

func _on_msg(text: String, col: Color) -> void:
	msg_l.text = text
	msg_l.add_theme_color_override("font_color", col)
	msg_t = 2.0

func _process(dt: float) -> void:
	shown_cash = move_toward(shown_cash, Game.cash, maxf(60.0 * dt, absf(Game.cash - shown_cash) * 4.0 * dt))
	cash_l.text = "$%08d" % int(round(shown_cash))
	var vs := get_viewport().get_visible_rect().size
	cash_l.position = Vector2(vs.x - 420, 12)
	speed_l.position = Vector2(vs.x - 340, vs.y - 70)
	msg_l.position = Vector2(vs.x * 0.5 - 400, vs.y * 0.5 - 170)
	stars.position = Vector2(vs.x * 0.5, 44) if vs.x >= 1000 else Vector2(vs.x * 0.5, 284)
	stars.queue_redraw()
	bars.position = Vector2(vs.x - 236, 74)
	bars.queue_redraw()
	panel.position = Vector2(vs.x - 300, 6)
	panel.queue_redraw()
	minimap.position = Vector2(14, 14)
	minimap.queue_redraw()
	gauge.position = Vector2(14, 246)
	gauge.queue_redraw()
	weapon_l.position = Vector2(vs.x - 316, 124)
	var wp = Game.main.weapons if Game.main else null
	if wp and wp.current != "":
		weapon_l.text = "%s  %d" % [wp.current.to_upper(), wp.ammo.get(wp.current, 0)]
		weapon_l.add_theme_color_override("font_color", wp.DEFS[wp.current]["color"])
	else:
		weapon_l.text = "FISTS  —"
		weapon_l.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	wasted_rect.size = vs
	wasted_l.position = Vector2(vs.x * 0.5 - 450, vs.y * 0.5 - 90)
	hint_l.position = Vector2(vs.x * 0.5 - 420, vs.y - 34)
	var cr = Game.main.crime if Game.main else null
	mult_l.visible = Game.mult > 1
	mult_l.text = "x%d" % Game.mult
	mult_l.position = Vector2(vs.x - 380 if vs.x >= 1000 else vs.x - 400, 18)
	var star_y: float = stars.position.y
	obj_l.text = cr.objective_text() if cr else ""
	obj_l.position = Vector2(vs.x * 0.5 - 350, star_y + 58)
	evade_l.position = Vector2(vs.x * 0.5 - 150, star_y + 26)
	evade_l.visible = Game.wanted > 0
	evade_l.text = "SEEN" if Game.cop_sees else "EVADING  %d" % ceili(Game.EVADE - Game.wanted_timer)
	evade_l.add_theme_color_override("font_color", Color(1, 0.4, 0.35) if Game.cop_sees else Color(0.7, 1.0, 0.7))
	zone_l.visible = cr != null and cr.zone_t > 0.0
	if zone_l.visible: zone_l.text = cr.zone_msg
	zone_l.position = Vector2(vs.x * 0.5 - 350, vs.y - (300 if touch_ui != null and touch_ui.visible and vs.x < 1000 else 96))
	respect.position = Vector2(vs.x - 290, 160)
	respect.queue_redraw()
	var car = Game.main.player_car if Game.main else null
	speed_l.text = ""
	msg_t -= dt
	msg_l.visible = msg_t > 0.0
	hint_l.visible = Time.get_ticks_msec() < 12000 and not Game.force_touch_ui and not (touch_ui != null and touch_ui.visible)

class StarBar extends Control:
	func _draw() -> void:
		var n: int = Game.wanted
		var flash := fmod(Time.get_ticks_msec() / 1000.0, 0.6) < 0.2
		for i in 6:
			var c := Vector2((i - 2.5) * 52.0, 0)
			var pts := PackedVector2Array()
			for k in 10:
				var rad := 22.0 if k % 2 == 0 else 9.5
				var a := -PI / 2 + k * PI / 5
				pts.append(c + Vector2(cos(a), sin(a)) * rad)
			var fill := Color(1, 0.85, 0.15) if i < n else Color(0, 0, 0, 0.25)
			if i < n and flash: fill = Color(1, 0.35, 0.3)
			var outline := pts.duplicate(); outline.append(pts[0])
			draw_colored_polygon(pts, fill)
			draw_polyline(outline, Color(0, 0, 0, 0.9) if i < n else Color(1, 1, 1, 0.25), 3.0)

class Bars extends Control:
	func _draw() -> void:
		var m = Game.main
		if m == null: return
		_bar(Vector2(0, 0), m.player.health / 100.0, Color(0.95, 0.2, 0.25), "HP")
		if m.player_car:
			_bar(Vector2(0, 26), maxf(m.player_car.health, 0.0) / 100.0, Color(0.3, 0.8, 1.0), "CAR")
	func _bar(p: Vector2, f: float, c: Color, label: String) -> void:
		draw_rect(Rect2(p + Vector2(44, 0), Vector2(176, 18)), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(p + Vector2(46, 2), Vector2(172 * clampf(f, 0, 1), 14)), c)
		draw_string(ThemeDB.fallback_font, p + Vector2(0, 15), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)

class Panel2 extends Control:
	func _draw() -> void:
		var h := 236.0
		draw_rect(Rect2(Vector2.ZERO, Vector2(294, h)), Color(0, 0, 0, 0.38))
		draw_rect(Rect2(Vector2.ZERO, Vector2(294, h)), Color(1, 1, 1, 0.15), false, 2.0)

## Speedometer gauge with needle, digital readout and car type.
class Gauge extends Control:
	func _draw() -> void:
		var m = Game.main
		if m == null or m.player_car == null: return
		var c = m.player_car
		var kmh: float = c.speed() * 3.6
		var w := 210.0
		var ctr := Vector2(w * 0.5, 92)
		draw_rect(Rect2(Vector2.ZERO, Vector2(w, 120)), Color(0, 0, 0, 0.4))
		draw_arc(ctr, 72, PI, TAU, 40, Color(1, 1, 1, 0.25), 10.0)
		var frac := clampf(kmh / 160.0, 0.0, 1.0)
		var col := Color(0.4, 1.0, 0.4).lerp(Color(1.0, 0.3, 0.2), frac)
		if frac > 0.0: draw_arc(ctr, 72, PI, PI + PI * frac, 40, col, 10.0)
		for k in 9:
			var a := PI + PI * k / 8.0
			draw_line(ctr + Vector2(cos(a), sin(a)) * 60, ctr + Vector2(cos(a), sin(a)) * 66, Color(1, 1, 1, 0.7), 2.0)
		var na := PI + PI * frac
		draw_line(ctr, ctr + Vector2(cos(na), sin(na)) * 64, Color(1, 0.9, 0.3), 3.0)
		draw_circle(ctr, 5, Color(1, 0.9, 0.3))
		var f := ThemeDB.fallback_font
		draw_string_outline(f, Vector2(0, 88), "%d" % int(kmh), HORIZONTAL_ALIGNMENT_CENTER, w, 34, 6, Color.BLACK)
		draw_string(f, Vector2(0, 88), "%d" % int(kmh), HORIZONTAL_ALIGNMENT_CENTER, w, 34, col)
		draw_string(f, Vector2(0, 112), "km/h  ·  " + String(c.car_type).to_upper(), HORIZONTAL_ALIGNMENT_CENTER, w, 15, Color(0.85, 0.85, 0.85))

## Rotating mini-map (player-up): streets, player arrow, police, traffic, pickups.
class Minimap extends Control:
	const SZ := 220.0
	func _ready() -> void:
		clip_contents = true
		size = Vector2(SZ, SZ)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var m = Game.main
		if m == null: return
		var tgt: Node3D = m.player_target()
		var yaw: float = tgt.rotation.y
		var spd: float = m.player_car.speed() if m.player_car else 0.0
		var scale := lerpf(1.5, 0.9, clampf(spd / 30.0, 0.0, 1.0))   # px per metre
		var ctr := Vector2(SZ, SZ) * 0.5
		var cy := cos(yaw); var sy := sin(yaw)
		var tp: Vector3 = tgt.global_position
		var to_map := func(p: Vector3) -> Vector2:
			var x := p.x - tp.x; var z := p.z - tp.z
			return ctr + Vector2(x * cy - z * sy, x * sy + z * cy) * scale
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.16, 0.22, 0.16, 0.85))
		var span := Game.NB * Game.P
		var road_w := Game.ROAD_HALF * 2.0 * scale
		for k in Game.NB + 1:
			var a := k * Game.P
			draw_line(to_map.call(Vector3(a, 0, 0)), to_map.call(Vector3(a, 0, span)), Color(0.42, 0.42, 0.45), road_w)
			draw_line(to_map.call(Vector3(0, 0, a)), to_map.call(Vector3(span, 0, a)), Color(0.42, 0.42, 0.45), road_w)
		for k in Game.NB + 1:
			var a := k * Game.P
			draw_line(to_map.call(Vector3(a, 0, 0)), to_map.call(Vector3(a, 0, span)), Color(0.85, 0.75, 0.3, 0.6), 1.0)
			draw_line(to_map.call(Vector3(0, 0, a)), to_map.call(Vector3(span, 0, a)), Color(0.85, 0.75, 0.3, 0.6), 1.0)
		# gang turf tint
		for bx in Game.NB:
			for by in Game.NB:
				var g := Game.gang_at_block(Vector2i(bx, by))
				if g < 0: continue
				var x0 := bx * Game.P + Game.ROAD_HALF; var x1 := (bx + 1) * Game.P - Game.ROAD_HALF
				var z0 := by * Game.P + Game.ROAD_HALF; var z1 := (by + 1) * Game.P - Game.ROAD_HALF
				var poly := PackedVector2Array([to_map.call(Vector3(x0, 0, z0)), to_map.call(Vector3(x1, 0, z0)), to_map.call(Vector3(x1, 0, z1)), to_map.call(Vector3(x0, 0, z1))])
				draw_colored_polygon(poly, Color(Game.GANGS[g]["col"], 0.28))
		var flash := fmod(Time.get_ticks_msec() / 1000.0, 0.5) < 0.25
		for p in m.get_tree().get_nodes_in_group("armed"):
			if not p.alive: continue
			var q: Vector2 = to_map.call(p.global_position)
			if q.x < 0 or q.y < 0 or q.x > SZ or q.y > SZ: continue
			var pc: Color = Game.GANGS[p.gang]["col"] if p.role == "gang" else Color(0.3, 0.5, 1.0)
			draw_circle(q, 3.0, pc)
		for c in m.get_tree().get_nodes_in_group("cars"):
			if c == m.player_car: continue
			var p: Vector2 = to_map.call(c.global_position)
			if p.x < -10 or p.y < -10 or p.x > SZ + 10 or p.y > SZ + 10: continue
			if c.ctrl == Car.Ctrl.POLICE and not c.dead:
				draw_circle(p, 6.0, Color(1, 0.15, 0.1) if flash else Color(0.2, 0.4, 1.0))
				draw_arc(p, 6.0, 0, TAU, 16, Color.WHITE, 1.5)
			elif not c.dead:
				draw_circle(p, 2.2, Color(0.9, 0.9, 0.9, 0.7))
		if m.weapons:
			for pk in m.weapons.pickups:
				if pk[2] > 0.0: continue
				var p: Vector2 = to_map.call(pk[0].global_position)
				var col: Color = m.weapons.DEFS[pk[1]]["color"]
				draw_rect(Rect2(p - Vector2(4, 4), Vector2(8, 8)), col)
				draw_rect(Rect2(p - Vector2(4, 4), Vector2(8, 8)), Color.BLACK, false, 1.0)
		if m.crime:
			var f := ThemeDB.fallback_font
			for b in m.crime.blips():
				var q: Vector2 = to_map.call(b[0])
				var inside := q.x > 8 and q.y > 8 and q.x < SZ - 8 and q.y < SZ - 8
				if not inside:
					if not b[3]: continue
					q = ctr + (q - ctr).normalized() * (SZ * 0.5 - 12)
					q = q.clamp(Vector2(10, 10), Vector2(SZ - 10, SZ - 10))
				var big: bool = b[3]
				var r := 9.0 if big else 7.5
				if big and flash: r = 11.0
				draw_circle(q, r, Color(0, 0, 0, 0.75))
				draw_arc(q, r, 0, TAU, 16, b[1], 2.0)
				draw_string(f, q + Vector2(-5, 5), b[2], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, b[1])
		# player arrow (always pointing up)
		var pts := PackedVector2Array([ctr + Vector2(0, -11), ctr + Vector2(8, 8), ctr + Vector2(0, 4), ctr + Vector2(-8, 8)])
		draw_colored_polygon(pts, Color(0.2, 1.0, 0.35))
		pts.append(pts[0])
		draw_polyline(pts, Color.BLACK, 2.0)
		# north marker on the rim
		var north := Vector2(sy, -cy)   # world -Z mapped
		var npos := ctr + north * (SZ * 0.5 - 14)
		draw_circle(npos, 10, Color(0, 0, 0, 0.6))
		draw_string(ThemeDB.fallback_font, npos + Vector2(-6, 6), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
		draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.6), false, 3.0)

## Gang respect: three bars, centre = 0, left red (hated) / right gang colour (respected).
class Respect extends Control:
	func _draw() -> void:
		var f := ThemeDB.fallback_font
		for g in 3:
			var y := g * 23.0
			var r: int = Game.respect[g]
			var col: Color = Game.GANGS[g]["col"]
			draw_string(f, Vector2(0, y + 14), String(Game.GANGS[g]["short"]), HORIZONTAL_ALIGNMENT_LEFT, 90, 15, col)
			var x0 := 96.0; var w := 180.0
			draw_rect(Rect2(Vector2(x0, y + 2), Vector2(w, 14)), Color(0, 0, 0, 0.6))
			var mid := x0 + w * 0.5
			var len := w * 0.5 * absf(r) / 100.0
			if r >= 0: draw_rect(Rect2(Vector2(mid, y + 4), Vector2(len, 10)), col)
			else: draw_rect(Rect2(Vector2(mid - len, y + 4), Vector2(len, 10)), Color(0.9, 0.15, 0.15))
			draw_line(Vector2(mid, y), Vector2(mid, y + 18), Color(1, 1, 1, 0.7), 1.5)
			var ux := mid + w * 0.5 * 20.0 / 100.0
			draw_line(Vector2(ux, y + 2), Vector2(ux, y + 16), Color(1, 1, 0.4, 0.6), 1.0)
