class_name Tex
## Procedurally generated textures and materials (no external assets).

static var _cache := {}

static func _noise_img(w: int, base: Color, amount: float, seed_: int) -> Image:
	var img := Image.create(w, w, false, Image.FORMAT_RGBA8)
	var r := RandomNumberGenerator.new()
	r.seed = seed_
	for y in w:
		for x in w:
			var n := r.randf_range(-amount, amount)
			img.set_pixel(x, y, Color(base.r + n, base.g + n, base.b + n))
	return img

static func _finish(img: Image) -> ImageTexture:
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

static func asphalt() -> ImageTexture:
	if _cache.has("asphalt"): return _cache["asphalt"]
	var img := _noise_img(128, Color(0.24, 0.24, 0.26), 0.035, 1)
	var r := RandomNumberGenerator.new(); r.seed = 2
	for i in 120:
		var x := r.randi_range(0, 127); var y := r.randi_range(0, 127)
		img.set_pixel(x, y, Color(0.16, 0.16, 0.17))
	var t := _finish(img); _cache["asphalt"] = t; return t

static func sidewalk() -> ImageTexture:
	if _cache.has("sidewalk"): return _cache["sidewalk"]
	var img := _noise_img(128, Color(0.68, 0.64, 0.58), 0.03, 3)
	for y in 128:
		for x in 128:
			if x % 32 == 0 or y % 32 == 0:
				img.set_pixel(x, y, Color(0.48, 0.45, 0.41))
	var t := _finish(img); _cache["sidewalk"] = t; return t

static func grass() -> ImageTexture:
	if _cache.has("grass"): return _cache["grass"]
	var img := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	var r := RandomNumberGenerator.new(); r.seed = 4
	for y in 128:
		for x in 128:
			var n := r.randf_range(-0.05, 0.05)
			img.set_pixel(x, y, Color(0.22 + n, 0.48 + n * 1.5, 0.16 + n))
	var t := _finish(img); _cache["grass"] = t; return t

static func facade(variant: int) -> ImageTexture:
	var key := "facade%d" % variant
	if _cache.has(key): return _cache[key]
	var palettes := [
		[Color(0.72, 0.42, 0.30), Color(0.15, 0.22, 0.35)], # brick red, blue glass
		[Color(0.82, 0.76, 0.60), Color(0.12, 0.18, 0.28)], # sandstone
		[Color(0.45, 0.55, 0.62), Color(0.10, 0.25, 0.32)], # steel blue
		[Color(0.60, 0.60, 0.58), Color(0.14, 0.16, 0.22)], # concrete
		[Color(0.55, 0.35, 0.45), Color(0.12, 0.12, 0.22)], # plum
		[Color(0.85, 0.65, 0.30), Color(0.18, 0.20, 0.30)], # ochre
	]
	var pal = palettes[variant % palettes.size()]
	var img := _noise_img(128, pal[0], 0.03, 10 + variant)
	var r := RandomNumberGenerator.new(); r.seed = 20 + variant
	for wy in 2:
		for wx in 2:
			var lit := r.randf() < 0.3
			var glass: Color = pal[1]
			if lit: glass = Color(0.95, 0.85, 0.45)
			var x0 := wx * 64 + 12; var y0 := wy * 64 + 14
			for y in range(y0 - 2, y0 + 38):
				for x in range(x0 - 2, x0 + 42):
					img.set_pixel(x, y, pal[0].darkened(0.35))
			for y in range(y0, y0 + 36):
				for x in range(x0, x0 + 40):
					var g := glass.lightened(0.25 * float(y0 + 36 - y) / 36.0 * (1.0 if not lit else 0.3))
					if x - x0 == 19 or x - x0 == 20: g = pal[0].darkened(0.35)
					img.set_pixel(x, y, g)
		# floor band
		for x in 128:
			for y in range(wy * 64 + 58, wy * 64 + 62):
				img.set_pixel(x, y, pal[0].darkened(0.2))
	var t := _finish(img); _cache[key] = t; return t

static func roof(variant: int) -> ImageTexture:
	var key := "roof%d" % variant
	if _cache.has(key): return _cache[key]
	var cols := [Color(0.42, 0.42, 0.44), Color(0.55, 0.47, 0.36), Color(0.40, 0.30, 0.28), Color(0.36, 0.42, 0.38), Color(0.30, 0.32, 0.38)]
	var base: Color = cols[variant % cols.size()]
	var img := _noise_img(128, base, 0.05, 30 + variant)
	# tar-paper seams
	for y in 128:
		for x in 128:
			if y % 43 == 0 or (x % 64 == 0 and y % 86 < 43):
				img.set_pixel(x, y, base.darkened(0.25))
	var t := _finish(img); _cache[key] = t; return t

static func mat_tex(t: Texture2D, world_scale: float, tint := Color.WHITE) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = t
	m.albedo_color = tint
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE / world_scale
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	m.roughness = 0.95
	return m

static func mat_col(c: Color, emissive := false) -> StandardMaterial3D:
	var key := "col_%s_%s" % [c.to_html(), emissive]
	if _cache.has(key): return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.6
	if emissive:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = 1.5
	_cache[key] = m
	return m
