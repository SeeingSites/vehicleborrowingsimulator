class_name Sfx
## Procedurally synthesised sound effects (16-bit mono AudioStreamWAV), no audio assets needed.

const RATE := 22050
static var _cache := {}

static func _wav(samples: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = samples.size()
	return w

static func get_stream(name: String) -> AudioStreamWAV:
	if _cache.has(name): return _cache[name]
	var s: AudioStreamWAV
	match name:
		"engine": s = _make_engine()
		"skid": s = _make_skid()
		"siren": s = _make_siren()
		"horn": s = _make_horn()
		"thud": s = _make_thud()
		"splat": s = _make_splat()
		"pistol": s = _wav(_burst(0.22, 0.6, 22.0, 140.0, 0.6, 21), false)
		"smg": s = _wav(_burst(0.12, 0.7, 35.0, 180.0, 0.4, 22), false)
		"pickup": s = _make_pickup()
		"shotgun": s = _wav(_burst(0.45, 0.35, 9.0, 90.0, 0.9, 23), false)
		"punch": s = _wav(_burst(0.12, 0.1, 30.0, 110.0, 0.9, 24), false)
		"alarm": s = _make_tones([[950.0, 0.18], [700.0, 0.18]], 5, true, 0.35)
		"ring": s = _make_tones([[1200.0, 0.05], [900.0, 0.05]], 8, false, 0.3)
		"cash": s = _make_tones([[1318.0, 0.07], [1760.0, 0.16]], 1, false, 0.4)
		"spray": s = _wav(_burst(1.2, 0.9, 1.5, 0.0, 0.0, 25), false)
		"crush": s = _wav(_burst(1.0, 0.05, 3.0, 55.0, 1.0, 26), false)
		_: s = _make_explosion()
	_cache[name] = s
	return s

## Engine: 55 Hz rumble with harmonics and firing pulses; loop is an exact number of periods.
static func _make_engine() -> AudioStreamWAV:
	var period := 400   # 22050 / 400 = 55.125 Hz
	var n := period * 10
	var out := PackedFloat32Array(); out.resize(n)
	for i in n:
		var ph := TAU * float(i % period) / period
		var v := sin(ph) * 0.5 + sin(2 * ph) * 0.3 + sin(3 * ph + 0.5) * 0.2 + sin(4 * ph) * 0.12
		var pulse := 0.6 + 0.4 * pow(0.5 + 0.5 * sin(2 * ph), 4.0)
		out[i] = v * pulse * 0.55
	return _wav(out, true)

static func _make_skid() -> AudioStreamWAV:
	var n := RATE
	var out := PackedFloat32Array(); out.resize(n)
	var r := RandomNumberGenerator.new(); r.seed = 7
	var lp := 0.0; var prev := 0.0
	for i in n:
		var w := r.randf_range(-1, 1)
		lp += (w - lp) * 0.35
		var hp := lp - prev; prev = lp
		var tone := sin(TAU * 900.0 * i / RATE) * 0.35 + sin(TAU * 1350.0 * i / RATE) * 0.15
		var wob := 0.75 + 0.25 * sin(TAU * 6.0 * i / RATE)
		out[i] = (hp * 1.2 + tone * wob) * 0.5
	return _wav(out, true)

static func _make_siren() -> AudioStreamWAV:
	var n := RATE
	var out := PackedFloat32Array(); out.resize(n)
	var ph := 0.0
	for i in n:
		var f := 660.0 if i < n / 2 else 880.0
		ph += TAU * f / RATE
		var v := sin(ph) + 0.3 * sin(3 * ph)
		out[i] = v * 0.4
	return _wav(out, true)

static func _make_horn() -> AudioStreamWAV:
	var n := RATE / 5
	var out := PackedFloat32Array(); out.resize(n)
	for i in n:
		var a := signf(sin(TAU * 400.0 * i / RATE)) * 0.5 + signf(sin(TAU * 500.0 * i / RATE)) * 0.5
		out[i] = a * 0.3
	return _wav(out, true)

static func _burst(len_s: float, lp_k: float, decay: float, low_f: float, low_amt: float, seed_: int) -> PackedFloat32Array:
	var n := int(RATE * len_s)
	var out := PackedFloat32Array(); out.resize(n)
	var r := RandomNumberGenerator.new(); r.seed = seed_
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		lp += (r.randf_range(-1, 1) - lp) * lp_k
		var env := exp(-t * decay) * minf(1.0, t * 400.0)
		var low := sin(TAU * low_f * t * (1.0 - t * 0.3)) * low_amt
		out[i] = (lp * 2.0 + low) * env
	return out

static func _make_thud() -> AudioStreamWAV:
	return _wav(_burst(0.35, 0.08, 14.0, 70.0, 0.8, 11), false)

static func _make_splat() -> AudioStreamWAV:
	var o := _burst(0.4, 0.25, 9.0, 160.0, 0.5, 12)
	return _wav(o, false)

static func _make_explosion() -> AudioStreamWAV:
	var o := _burst(2.2, 0.04, 2.2, 40.0, 0.9, 13)
	for i in o.size(): o[i] = clampf(o[i] * 1.6, -1.0, 1.0)
	return _wav(o, false)

static func _make_pickup() -> AudioStreamWAV:
	var n := int(RATE * 0.25)
	var out := PackedFloat32Array(); out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var f := 660.0 if t < 0.08 else (880.0 if t < 0.16 else 1320.0)
		out[i] = sin(TAU * f * t) * 0.4 * exp(-t * 6.0)
	return _wav(out, false)

## Sequence of square-ish tones repeated `reps` times (alarm, phone ring, cash chime).
static func _make_tones(seq: Array, reps: int, square: bool, amp: float) -> AudioStreamWAV:
	var out := PackedFloat32Array()
	for r in reps:
		for st in seq:
			var n := int(RATE * float(st[1]))
			for i in n:
				var t := float(i) / RATE
				var v := sin(TAU * float(st[0]) * t)
				if square: v = signf(v) * 0.6
				out.append(v * amp * minf(1.0, (n - i) / 200.0) * minf(1.0, i / 100.0))
	return _wav(out, false)
