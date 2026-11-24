class_name Player
extends CharacterBody3D
## The player on foot.

var walk_speed := 6.0
var arms: Array
var t := 0.0
var auto_move := Vector2.ZERO   # used by screenshot scripts

func _ready() -> void:
	collision_layer = 4
	collision_mask = 1 | 2
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	var cs := CollisionShape3D.new()
	var sh := CapsuleShape3D.new(); sh.radius = 0.45; sh.height = 1.8
	cs.shape = sh; cs.position = Vector3(0, 0.9, 0)
	add_child(cs)
	arms = Ped.make_visual(self, Color(1.0, 0.85, 0.1), Color(0.95, 0.78, 0.62), Color(0.15, 0.1, 0.05), Color(0.1, 0.1, 0.12))
	# green "player" marker ring like GTA2's arrow
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new(); tm.inner_radius = 0.9; tm.outer_radius = 1.05
	ring.mesh = tm; ring.material_override = Tex.mat_col(Color(0.2, 1.0, 0.3), true)
	ring.position = Vector3(0, 0.25, 0)
	add_child(ring)

func _physics_process(dt: float) -> void:
	if not visible: return
	var v := Game.move_vector() + auto_move
	v = v.limit_length(1.0)
	velocity = Vector3(v.x, 0, v.y) * walk_speed
	move_and_slide()
	global_position.y = 0.2
	if v.length() > 0.1:
		t += dt
		rotation.y = lerp_angle(rotation.y, Game.yaw_of(Vector3(v.x, 0, v.y)), 12.0 * dt)
		var sw := sin(t * 10.0) * 0.7
		arms[1].rotation.x = sw; arms[2].rotation.x = -sw
