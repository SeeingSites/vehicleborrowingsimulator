extends CanvasLayer
## Esc / P pauses the game (runs while the tree is paused).
var lbl: Label
var dim: ColorRect

func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	dim = ColorRect.new(); dim.color = Color(0, 0, 0, 0.5); dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	lbl = Label.new()
	lbl.text = "PAUSED\nEsc / P / tap to resume"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 56)
	lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	lbl.add_theme_constant_override("outline_size", 12)
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(lbl)
	newb = Label.new()
	newb.text = "NEW GAME (N / Select)"
	newb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	newb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	newb.add_theme_font_size_override("font_size", 32)
	newb.add_theme_color_override("font_color", Color(1, 0.5, 0.4))
	newb.add_theme_color_override("font_outline_color", Color.BLACK)
	newb.add_theme_constant_override("outline_size", 10)
	add_child(newb)
	visible = false

var newb: Label

func _process(_dt: float) -> void:
	if not visible: return
	var vs := get_viewport().get_visible_rect().size
	newb.size = Vector2(360, 70)
	newb.position = Vector2(vs.x * 0.5 - 180, vs.y * 0.5 + 110)

## Touch / click while paused: NEW GAME button or resume.
func _input(ev: InputEvent) -> void:
	if not visible: return
	var at = null
	if ev is InputEventScreenTouch and ev.pressed: at = ev.position
	elif ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT: at = ev.position
	if at == null: return
	get_viewport().set_input_as_handled()
	if Rect2(newb.position, newb.size).has_point(at): new_game()
	else: toggle()

## Wipe the save and restart the city.
func new_game(reload := true) -> void:
	if Game.main and Game.main.save and Game.main.save.enabled: Game.main.save.reset()
	Game.cash = 0; Game.mult = 1; Game.respect = [0, 0, 0]
	Game.set_wanted(0)
	Engine.time_scale = 1.0
	get_tree().paused = false
	visible = false
	if reload: get_tree().reload_current_scene()

func _unhandled_input(ev: InputEvent) -> void:
	if ev.is_action_pressed("pause") and not ev.is_echo():
		toggle()
		get_viewport().set_input_as_handled()
	elif visible and ((ev is InputEventKey and ev.pressed and ev.physical_keycode == KEY_N) or (ev is InputEventJoypadButton and ev.pressed and ev.button_index == JOY_BUTTON_BACK)):
		new_game()
		get_viewport().set_input_as_handled()

func toggle() -> void:
	var p := not get_tree().paused
	get_tree().paused = p
	visible = p
	if p and Game.main and Game.main.save and Game.main.save.enabled: Game.main.save.save_game()
