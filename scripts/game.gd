extends Node
## Global game state: cash, wanted level, input map, touch input, city constants.

const P := 28.0          # block pitch (distance between road centre lines)
const ROAD_HALF := 5.0   # half road width
const WALK := 2.5        # sidewalk width
const LANE := 2.5        # lane offset from road centre (right-hand traffic)
const NB := 8            # blocks per side -> road nodes 0..NB

signal wanted_changed(level)
signal cash_changed(amount)
signal message(text, color)

var cash := 0
var wanted := 0
var wanted_timer := 0.0
const WANTED_DECAY := 25.0

# Touch input written by the on-screen controls.
var touch_vec := Vector2.ZERO
var touch_handbrake := false
var force_touch_ui := false

var shot := ""
var rng := RandomNumberGenerator.new()

var main: Node = null

func _ready() -> void:
	rng.seed = 1337
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			shot = a.substr(7)
		elif a == "--touch":
			force_touch_ui = true
	_add_action("move_up", [KEY_W, KEY_UP])
	_add_action("move_down", [KEY_S, KEY_DOWN])
	_add_action("move_left", [KEY_A, KEY_LEFT])
	_add_action("move_right", [KEY_D, KEY_RIGHT])
	_add_action("enter_exit", [KEY_E, KEY_ENTER])
	_add_action("handbrake", [KEY_SPACE])

func _add_action(name: String, keys: Array) -> void:
	if not InputMap.has_action(name):
		InputMap.add_action(name, 0.2)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(name, ev)
	var map := {"move_up": [JOY_AXIS_LEFT_Y, -1.0], "move_down": [JOY_AXIS_LEFT_Y, 1.0],
		"move_left": [JOY_AXIS_LEFT_X, -1.0], "move_right": [JOY_AXIS_LEFT_X, 1.0]}
	if map.has(name):
		var j := InputEventJoypadMotion.new()
		j.axis = map[name][0]
		j.axis_value = map[name][1]
		InputMap.action_add_event(name, j)

## Combined keyboard / gamepad / virtual joystick vector (x right, y down).
func move_vector() -> Vector2:
	var v := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	v += touch_vec
	return v.limit_length(1.0)

func handbrake() -> bool:
	return Input.is_action_pressed("handbrake") or touch_handbrake

func add_cash(n: int) -> void:
	cash += n
	cash_changed.emit(cash)

func add_wanted(n: int) -> void:
	set_wanted(wanted + n)

func set_wanted(n: int) -> void:
	wanted = clampi(n, 0, 6)
	wanted_timer = 0.0
	wanted_changed.emit(wanted)

func _process(delta: float) -> void:
	if wanted > 0:
		wanted_timer += delta
		if wanted_timer > WANTED_DECAY:
			set_wanted(wanted - 1)

func node_pos(n: Vector2i) -> Vector3:
	return Vector3(n.x * P, 0.0, n.y * P)

func in_grid(n: Vector2i) -> bool:
	return n.x >= 0 and n.y >= 0 and n.x <= NB and n.y <= NB

static func right_of(d: Vector2i) -> Vector3:
	return Vector3(-d.y, 0.0, d.x)

static func yaw_of(v: Vector3) -> float:
	return atan2(-v.x, -v.z)
