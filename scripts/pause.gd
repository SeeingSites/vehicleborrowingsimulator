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
	lbl.text = "PAUSED\nEsc / P to resume"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 56)
	lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	lbl.add_theme_constant_override("outline_size", 12)
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(lbl)
	visible = false

func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo and (ev.physical_keycode == KEY_ESCAPE or ev.physical_keycode == KEY_P):
		toggle()
		get_viewport().set_input_as_handled()

func toggle() -> void:
	var p := not get_tree().paused
	get_tree().paused = p
	visible = p
	if p and Game.main and Game.main.save and Game.main.save.enabled: Game.main.save.save_game()
