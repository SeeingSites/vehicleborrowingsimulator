extends CanvasLayer
## GTA2-style HUD: cash (top right), wanted stars (top centre), speed, messages.

var cash_l: Label
var stars: Control
var speed_l: Label
var msg_l: Label
var hint_l: Label
var msg_t := 0.0
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
	hint_l = _label(18, Color(0.9, 0.9, 0.9))
	hint_l.text = "WASD/arrows move  ·  E enter/exit car  ·  SPACE handbrake"
	Game.message.connect(_on_msg)

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
	stars.position = Vector2(vs.x * 0.5, 44)
	stars.queue_redraw()
	hint_l.position = Vector2(16, vs.y - 40)
	var car = Game.main.player_car if Game.main else null
	if car:
		speed_l.text = "%d km/h" % int(car.speed() * 3.6)
	else:
		speed_l.text = ""
	msg_t -= dt
	msg_l.visible = msg_t > 0.0
	hint_l.visible = Time.get_ticks_msec() < 12000 and not Game.force_touch_ui

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
