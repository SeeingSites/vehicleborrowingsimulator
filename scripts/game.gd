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
signal ped_killed(ped, by_player)
signal respect_changed
signal npc_fired

# ---- crime economy (v4) ----
var mult := 1                 # cash multiplier: +1 per mission / kill frenzy, reset when busted or wasted
const MULT_MAX := 5
var respect := [0, 0, 0]      # per gang, -100..100
var cop_sees := false         # set every frame by crime.gd; wanted decays only while false
const EVADE := 12.0           # seconds unseen to lose one star
const GANGS := [
	{"name": "NEON SERPENTS", "short": "SERPENTS", "col": Color(0.25, 0.95, 0.45), "rival": 1},
	{"name": "IRON SAINTS",   "short": "SAINTS",   "col": Color(0.95, 0.22, 0.22), "rival": 2},
	{"name": "RUST KINGS",    "short": "KINGS",    "col": Color(1.0, 0.58, 0.12), "rival": 0},
]

var cash := 0
var wanted := 0
var wanted_timer := 0.0

# Touch input written by the on-screen controls.
var touch_vec := Vector2.ZERO
var touch_handbrake := false
var force_touch_ui := false

var shot := ""
var test := false
var sim_seconds := 0.0      # --sim=N : headless traffic simulation, prints jam metrics
var traffic_cars := 34
var car_contacts := 0      # car-vs-car impacts > 3 m/s (sim metric)
var signals := true         # --no-signals : disable traffic lights / right-of-way (v1 behaviour)
var sig_time := 0.0
const SIG_CYCLE := 16.0
enum Light { GREEN, YELLOW, RED }
var rng := RandomNumberGenerator.new()

var main: Node = null

func _ready() -> void:
	rng.seed = 1337
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			shot = a.substr(7)
		elif a == "--test":
			test = true
		elif a == "--touch":
			force_touch_ui = true
		elif a.begins_with("--sim="):
			sim_seconds = float(a.substr(6))
		elif a.begins_with("--cars="):
			traffic_cars = int(a.substr(7))
		elif a.begins_with("--seed="):
			rng.seed = int(a.substr(7))
		elif a == "--no-signals":
			signals = false
	if OS.has_feature("web"):
		# ?shot=v4_steal etc. runs a scripted scenario in the browser (used for phone-emulation checks)
		var qs := str(JavaScriptBridge.eval("window.location.search", true))
		for kv in qs.trim_prefix("?").split("&"):
			if kv.begins_with("shot="): shot = kv.substr(5)
	_add_action("move_up", [KEY_W, KEY_UP])
	_add_action("move_down", [KEY_S, KEY_DOWN])
	_add_action("move_left", [KEY_A, KEY_LEFT])
	_add_action("move_right", [KEY_D, KEY_RIGHT])
	_add_action("enter_exit", [KEY_E, KEY_ENTER])
	_add_action("handbrake", [KEY_SPACE])
	_add_action("horn", [KEY_H])
	_add_action("fire", [KEY_CTRL, KEY_F])
	_add_action("weapon_next", [KEY_Q, KEY_TAB])
	var mb := InputEventMouseButton.new(); mb.button_index = MOUSE_BUTTON_LEFT
	InputMap.action_add_event("fire", mb)

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

## Crime payout through the multiplier; returns the amount paid.
func reward(base: int, label := "", col := Color(1, 0.9, 0.2)) -> int:
	var n := base * mult
	add_cash(n)
	message.emit(("+$%d" % n) + ("  " + label if label != "" else ""), col)
	return n

func add_respect(g: int, d: int) -> void:
	if g < 0 or g > 2: return
	respect[g] = clampi(respect[g] + d, -100, 100)
	respect_changed.emit()

## Turf: west = Serpents, east = Saints, south-middle = Kings, north-middle neutral.
static func gang_at_block(b: Vector2i) -> int:
	if b.x <= 2: return 0
	if b.x >= 5: return 1
	if b.y >= 4: return 2
	return -1

static func block_of(p: Vector3) -> Vector2i:
	return Vector2i(clampi(int(floor(p.x / P)), 0, NB - 1), clampi(int(floor(p.z / P)), 0, NB - 1))

func add_wanted(n: int) -> void:
	set_wanted(wanted + n)

func set_wanted(n: int) -> void:
	wanted = clampi(n, 0, 6)
	wanted_timer = 0.0
	wanted_changed.emit(wanted)

func _process(delta: float) -> void:
	if wanted > 0:
		if cop_sees:
			wanted_timer = 0.0
		else:
			wanted_timer += delta
			if wanted_timer > EVADE:
				set_wanted(wanted - 1)
				if wanted == 0: message.emit("LOST THEM", Color(0.6, 1.0, 0.6))

func _physics_process(delta: float) -> void:
	sig_time += delta

func signalled(n: Vector2i) -> bool:
	var corner := (n.x == 0 or n.x == NB) and (n.y == 0 or n.y == NB)
	return signals and not corner

func sig_group(n: Vector2i) -> int:
	return (n.x + n.y) % 2

## Light state for traffic moving along `axis_ns` (true = along Z) at intersection n.
func light_for(n: Vector2i, axis_ns: bool) -> int:
	return light_group(sig_group(n), axis_ns)

func light_group(g: int, axis_ns: bool) -> int:
	var half := SIG_CYCLE * 0.5
	var t := fmod(sig_time + g * half, SIG_CYCLE)
	if not axis_ns:
		t = fmod(t + half, SIG_CYCLE)
	if t < half - 3.5: return Light.GREEN
	if t < half - 1.5: return Light.YELLOW
	return Light.RED

func node_pos(n: Vector2i) -> Vector3:
	return Vector3(n.x * P, 0.0, n.y * P)

func in_grid(n: Vector2i) -> bool:
	return n.x >= 0 and n.y >= 0 and n.x <= NB and n.y <= NB

static func right_of(d: Vector2i) -> Vector3:
	return Vector3(-d.y, 0.0, d.x)

static func yaw_of(v: Vector3) -> float:
	return atan2(-v.x, -v.z)
