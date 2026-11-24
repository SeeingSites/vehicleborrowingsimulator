class_name Kit
## Loads Kenney CC0 models (assets/kenney) and measures their bounds.

static var _scenes := {}
static var _aabbs := {}

const BUILDINGS := ["building-a", "building-b", "building-c", "building-d", "building-e", "building-f", "building-g",
	"building-h", "building-i", "building-j", "building-k", "building-l", "building-m", "building-n",
	"building-skyscraper-a", "building-skyscraper-b", "building-skyscraper-c", "building-skyscraper-d", "building-skyscraper-e"]

static func scene(path: String) -> PackedScene:
	if not _scenes.has(path):
		_scenes[path] = load(path)
	return _scenes[path]

static func instance(path: String) -> Node3D:
	return scene(path).instantiate()

## Local-space AABB of all meshes in the model (cached per path).
static func aabb(path: String) -> AABB:
	if _aabbs.has(path): return _aabbs[path]
	var n := instance(path)
	var box := AABB()
	var first := true
	var stack: Array = [[n, Transform3D()]]
	while not stack.is_empty():
		var it = stack.pop_back()
		var node: Node = it[0]
		var xf: Transform3D = it[1]
		if node is Node3D and node != n:
			xf = xf * (node as Node3D).transform
		if node is MeshInstance3D and (node as MeshInstance3D).mesh:
			var b: AABB = xf * (node as MeshInstance3D).mesh.get_aabb()
			box = b if first else box.merge(b)
			first = false
		for c in node.get_children():
			stack.append([c, xf])
	n.free()
	_aabbs[path] = box
	return box

static func building_path(name: String) -> String:
	return "res://assets/kenney/city/%s.glb" % name

static func car_path(name: String) -> String:
	return "res://assets/kenney/cars/%s.glb" % name
