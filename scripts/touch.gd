extends Control
## Virtual joystick (left half of the screen) + ENTER and DRIFT buttons (right side).

var stick_id := -1
var stick_origin := Vector2(170, -170)   # relative to bottom-left
var stick_pos := Vector2.ZERO
var hb_id := -1
const RADIUS := 110.0

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = DisplayServer.is_touchscreen_available() or Game.force_touch_ui or OS.has_feature("web_android") or OS.has_feature("web_ios")

func _base() -> Vector2:
	return Vector2(stick_origin.x, size.y + stick_origin.y)

func _enter_btn() -> Vector2: return Vector2(size.x - 150, size.y - 260)
func _drift_btn() -> Vector2: return Vector2(size.x - 260, size.y - 130)
func _horn_btn() -> Vector2: return Vector2(size.x - 330, size.y - 290)
var horn_id := -1

func _input(ev: InputEvent) -> void:
	if not visible: return
	if ev is InputEventScreenTouch:
		if ev.pressed:
			if ev.position.x < size.x * 0.45 and stick_id < 0:
				stick_id = ev.index
				stick_origin = Vector2(ev.position.x, ev.position.y - size.y)
				stick_pos = Vector2.ZERO
			elif ev.position.distance_to(_enter_btn()) < 75:
				var a := InputEventAction.new(); a.action = "enter_exit"; a.pressed = true
				Input.parse_input_event(a)
				var b := InputEventAction.new(); b.action = "enter_exit"; b.pressed = false
				Input.parse_input_event.call_deferred(b)
			elif ev.position.distance_to(_horn_btn()) < 50:
				horn_id = ev.index
				Input.action_press("horn")
			elif ev.position.distance_to(_drift_btn()) < 75:
				hb_id = ev.index
				Game.touch_handbrake = true
		else:
			if ev.index == stick_id:
				stick_id = -1; stick_pos = Vector2.ZERO; Game.touch_vec = Vector2.ZERO
				stick_origin = Vector2(170, -170)
			if ev.index == horn_id:
				horn_id = -1; Input.action_release("horn")
			if ev.index == hb_id:
				hb_id = -1; Game.touch_handbrake = false
		queue_redraw()
	elif ev is InputEventScreenDrag and ev.index == stick_id:
		stick_pos = (ev.position - _base()).limit_length(RADIUS)
		Game.touch_vec = stick_pos / RADIUS
		queue_redraw()

func _draw() -> void:
	var b := _base()
	draw_circle(b, RADIUS, Color(1, 1, 1, 0.12))
	draw_arc(b, RADIUS, 0, TAU, 48, Color(1, 1, 1, 0.5), 3.0)
	draw_circle(b + stick_pos, 48, Color(1, 1, 1, 0.45))
	var font := ThemeDB.fallback_font
	for pair in [[_enter_btn(), "ENTER", Color(0.2, 0.8, 0.3, 0.45), 70.0], [_drift_btn(), "DRIFT", Color(0.9, 0.4, 0.2, 0.45), 70.0], [_horn_btn(), "HORN", Color(0.3, 0.5, 0.95, 0.45), 45.0]]:
		draw_circle(pair[0], pair[3], pair[2])
		draw_arc(pair[0], pair[3], 0, TAU, 48, Color(1, 1, 1, 0.6), 3.0)
		draw_string(font, pair[0] + Vector2(-38, 8), pair[1], HORIZONTAL_ALIGNMENT_CENTER, 76, 20 if pair[3] < 60 else 24, Color.WHITE)

func _process(_dt: float) -> void:
	if not visible: return
	var vs := get_viewport_rect().size
	if size != vs:
		position = Vector2.ZERO
		size = vs
		queue_redraw()
