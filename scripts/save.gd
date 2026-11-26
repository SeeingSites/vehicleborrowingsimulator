extends Node
## Progress save (cash, multiplier, respect, missions done, ammo) in user://save.cfg — IndexedDB on the
## web build. Saves every 15 s, after missions and on quit; disabled in test / sim / shot / play runs.
const PATH := "user://save.cfg"
var m
var t := 0.0
var enabled := true

func setup(main_, enable := true) -> void:
	m = main_
	enabled = enable
	if enabled: load_game()

func _physics_process(dt: float) -> void:
	if not enabled: return
	t += dt
	if t > 15.0:
		t = 0.0
		save_game()

func _notification(what: int) -> void:
	# a browser tab never sends the close request: also save when it's hidden / loses focus
	if enabled and what in [NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED]:
		save_game()

func save_game(path := PATH) -> void:
	var cf := ConfigFile.new()
	cf.set_value("game", "cash", Game.cash)
	cf.set_value("game", "mult", Game.mult)
	cf.set_value("game", "respect", Game.respect)
	cf.set_value("game", "mission_done", m.crime.mission_done)
	cf.set_value("game", "ammo", m.weapons.ammo)
	cf.set_value("game", "weapon", m.weapons.current)
	cf.save(path)

func load_game(path := PATH) -> bool:
	var cf := ConfigFile.new()
	if cf.load(path) != OK: return false
	Game.cash = int(cf.get_value("game", "cash", 0))
	Game.cash_changed.emit(Game.cash)
	Game.mult = clampi(int(cf.get_value("game", "mult", 1)), 1, Game.MULT_MAX)
	var r: Array = cf.get_value("game", "respect", [0, 0, 0])
	if r.size() == 3: Game.respect = [clampi(r[0], -100, 100), clampi(r[1], -100, 100), clampi(r[2], -100, 100)]
	var md: Array = cf.get_value("game", "mission_done", [0, 0, 0])
	if md.size() == 3: m.crime.mission_done = md.duplicate()
	m.weapons.ammo = (cf.get_value("game", "ammo", {}) as Dictionary).duplicate()
	m.weapons.current = str(cf.get_value("game", "weapon", ""))
	if m.hud: m.hud.shown_cash = float(Game.cash)
	Game.respect_changed.emit()
	return true

func reset(path := PATH) -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
