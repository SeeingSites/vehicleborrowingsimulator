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

func _enter_btn() -> Vector2: return Vector2(size.x - 170, size.y - 270)
func _drift_btn() -> Vector2: return Vector2(size.x - 290, size.y - 110)
func _horn_btn() -> Vector2: return Vector2(size.x - 340, size.y - 300)
var horn_id := -1
var fire_id := -1
func _fire_btn() -> Vector2: return Vector2(size.x - 110, size.y - 110)
func _wpn_btn() -> Vector2: return Vector2(size.x - 60, size.y - 360)

func _input(ev: InputEvent) -> void:
	if not visible: return
	if ev is InputEventScreenTouch:
		if ev.pressed:
			if ev.position.x < size.x * 0.45 and stick_id < 0:
				stick_id = ev.index
				stick_origin = Vector2(ev.position.x, ev.position.y - size.y)
				stick_pos = Vector2.ZERO
			elif ev.position.distance_to(_enter_btn()) < 75:
				_tap("enter_exit")
			elif ev.position.distance_to(_fire_btn()) < 70:
				fire_id = ev.index
				Input.action_press("fire")
			elif ev.position.distance_to(_wpn_btn()) < 42:
				_tap("weapon_next")
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
			if ev.index == fire_id:
				fire_id = -1; Input.action_release("fire")
			if ev.index == horn_id:
				horn_id = -1; Input.action_release("horn")
			if ev.index == hb_id:
				hb_id = -1; Game.touch_handbrake = false
		queue_redraw()
	elif ev is InputEventScreenDrag and ev.index == stick_id:
		stick_pos = (ev.position - _base()).limit_length(RADIUS)
		Game.touch_vec = stick_pos / RADIUS
		queue_redraw()

## Press an action for one full physics tick. Both actions are read with is_action_just_pressed()
## in _physics_process; releasing on the same frame (as a deferred call did) drops the tap on
## displays faster than the 60 Hz physics rate, where many frames run no physics step at all.
func _tap(action: String) -> void:
	Input.action_press(action)
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release(action)

func _draw() -> void:
	var b := _base()
	draw_circle(b, RADIUS, Color(1, 1, 1, 0.12))
	draw_arc(b, RADIUS, 0, TAU, 48, Color(1, 1, 1, 0.5), 3.0)
	draw_circle(b + stick_pos, 48, Color(1, 1, 1, 0.45))
	var font := ThemeDB.fallback_font
	for pair in [[_enter_btn(), _enter_label(), Color(0.2, 0.8, 0.3, 0.45), 70.0], [_drift_btn(), "DRIFT", Color(0.9, 0.4, 0.2, 0.45), 70.0], [_horn_btn(), "HORN", Color(0.3, 0.5, 0.95, 0.45), 45.0], [_fire_btn(), "FIRE", Color(0.95, 0.15, 0.15, 0.5), 70.0], [_wpn_btn(), "WPN", Color(0.9, 0.8, 0.2, 0.45), 40.0]]:
		draw_circle(pair[0], pair[3], pair[2])
		draw_arc(pair[0], pair[3], 0, TAU, 48, Color(1, 1, 1, 0.6), 3.0)
		var fs := 20 if pair[3] < 60 else (24 if String(pair[1]).length() <= 5 else 21)
		draw_string(font, pair[0] + Vector2(-55, 8), pair[1], HORIZONTAL_ALIGNMENT_CENTER, 110, fs, Color.WHITE)

func _enter_label() -> String:
	var m = Game.main
	if m and m.crime: return m.crime.context_label()
	return "ENTER"

var _last_label := ""
func _process(_dt: float) -> void:
	if not visible: return
	var lab := _enter_label()
	if lab != _last_label:
		_last_label = lab
		queue_redraw()
	var vs := get_viewport_rect().size
	if size != vs:
		position = Vector2.ZERO
		size = vs
		queue_redraw()
