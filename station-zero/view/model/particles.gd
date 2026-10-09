extends RefCounted
## The particle pool and its emitters (spec sprite-view.md 5.6, 5.4 flicker). View only.
##
## One pool, capped at particles.cap (new ones are dropped, never evicted). Emission is deterministic by accumulator:
## each source adds rate x dt, emits floor of it and keeps the rest, so over T seconds it emits floor(rate x T) +-1
## whatever the frame rate. The RNG only draws a particle's position, velocity and life, one generator per source,
## seeded from the source's kind and key (plus a salt), never from the sim.
##
## Source dictionaries (all carry key and kind):
##   weld_hand, dig: feet: Vector2, face: int (+1/-1), scale: float, ice: bool (dig only)
##   weld_seam: rect: Rect2 (sprite rect), f: float (wall reveal), crew: int
##   flicker: rect: Rect2 (footprint)

var art: Dictionary
## Particles refused because the pool was full.
var dropped := 0
var _salt: int
var _pool: Array[Dictionary] = []
var _acc: Dictionary = {}
var _emitted: Dictionary = {}
var _kind_total: Dictionary = {}
var _rngs: Dictionary = {}


func _init(art_in: Dictionary, seed_salt: int = 0) -> void:
	art = art_in
	_salt = seed_salt


## Live particles.
func count() -> int:
	return _pool.size()


## Particles a source has emitted (accepted plus dropped).
func emitted(key: String) -> int:
	return int(_emitted.get(key, 0))


func emitted_kind(kind: String) -> int:
	return int(_kind_total.get(kind, 0))


## Copies of the live particles: {kind, x, y, vx, vy, life (remaining), max_life, radius, ice}
## (radius and ice are used by dig dust only).
func snapshot() -> Array:
	var out: Array = []
	for p in _pool:
		out.append(p.duplicate())
	return out


func _rng_for(s: Dictionary) -> RandomNumberGenerator:
	var key: String = s.key
	if not _rngs.has(key):
		var r := RandomNumberGenerator.new()
		r.seed = ("%s|%s" % [s.kind, key]).hash() + _salt
		_rngs[key] = r
	return _rngs[key]


static func _span(r: RandomNumberGenerator, bounds: Array) -> float:
	return r.randf_range(float(bounds[0]), float(bounds[1]))


## Emission rate in particles per real second for a source (0 when it should not emit).
func _rate(s: Dictionary) -> float:
	var p: Dictionary = art.particles
	match s.kind:
		"weld_hand":
			return float(p.weld_hand.rate_per_s)
		"dig":
			return float(p.dig.rate_per_s)
		"flicker":
			return float(art.offline.flicker_per_s)
		"weld_seam":
			var f := float(s.f)
			if f > 0.0 and f < 1.0:
				var crew := minf(float(s.crew), float(p.weld_seam.max_crew))
				return float(p.weld_seam.rate_per_s_per_crew) * crew
	return 0.0


## One refresh: ages and moves the live particles, then emits for the sources present. dt is the real frame time,
## clamped to door.max_dt_s. A particle emitted by this call is not aged by it.
func update(dt_real: float, sources: Array) -> void:
	var dt := minf(dt_real, float(art.door.max_dt_s))
	_advance(dt)
	var present := {}
	for s in sources:
		var key: String = s.key
		present[key] = true
		var rate := _rate(s)
		if rate <= 0.0:
			continue
		var acc := float(_acc.get(key, 0.0)) + rate * dt
		var n := int(floor(acc))
		_acc[key] = acc - n
		_emitted[key] = emitted(key) + n
		_kind_total[s.kind] = emitted_kind(s.kind) + n
		for i in n:
			if _pool.size() >= int(art.particles.cap):
				dropped += 1
			else:
				_pool.append(_spawn(s))
	_forget_absent(present)


func _advance(dt: float) -> void:
	if _pool.is_empty():
		return
	var gravity := float(art.particles.gravity_px_s2)
	var damp := pow(float(art.particles.dig.damp_per_60hz_frame), 60.0 * dt)
	var grow := float(art.particles.dig.grow_px_s) * dt
	var keep: Array[Dictionary] = []
	for p in _pool:
		p.life -= dt
		if p.life <= 0.0:
			continue
		match p.kind:
			"weld_hand", "weld_seam":
				p.vy += gravity * dt
			"dig":
				p.vx *= damp
				p.vy *= damp
				p.radius += grow
		p.x += p.vx * dt
		p.y += p.vy * dt
		keep.append(p)
	_pool = keep


## Accumulators and generators of sources that stopped are dropped (counts stay), so the dictionaries stay small.
func _forget_absent(present: Dictionary) -> void:
	if _acc.size() > present.size():
		for key in _acc.keys():
			if not present.has(key):
				_acc.erase(key)
	if _rngs.size() > present.size():
		for key in _rngs.keys():
			if not present.has(key):
				_rngs.erase(key)


func _spawn(s: Dictionary) -> Dictionary:
	var r := _rng_for(s)
	var pa: Dictionary = art.particles
	var p := {"kind": s.kind, "x": 0.0, "y": 0.0, "vx": 0.0, "vy": 0.0, "life": 0.0, "max_life": 0.0,
			"radius": 0.0, "ice": bool(s.get("ice", false))}
	match s.kind:
		"weld_hand":
			var w: Dictionary = pa.weld_hand
			var face := float(s.face)
			var feet: Vector2 = s.feet
			p.x = feet.x + float(w.offset_px[0]) * face * float(s.scale)
			p.y = feet.y + float(w.offset_px[1]) * float(s.scale)
			p.vx = _span(r, w.vx) + face * _span(r, w.vx_facing)
			p.vy = _span(r, w.vy)
			p.max_life = _span(r, w.life_s)
		"weld_seam":
			var w: Dictionary = pa.weld_seam
			var rect: Rect2 = s.rect
			p.x = r.randf_range(rect.position.x, rect.end.x)
			p.y = rect.position.y + rect.size.y * (1.0 - float(s.f))
			p.vx = _span(r, w.vx)
			p.vy = _span(r, w.vy)
			p.max_life = _span(r, w.life_s)
		"dig":
			var d: Dictionary = pa.dig
			var face := float(s.face)
			var feet: Vector2 = s.feet
			p.x = feet.x + float(d.offset_px[0]) * face
			p.y = feet.y + float(d.offset_px[1])
			p.vx = _span(r, d.vx) + face * float(d.vx_facing)
			p.vy = _span(r, d.vy)
			p.max_life = _span(r, d.life_s)
			p.radius = _span(r, d.radius_px)
		"flicker":
			var o: Dictionary = art.offline
			var rect: Rect2 = s.rect
			var inset := float(o.flicker_x_inset_px)
			p.x = r.randf_range(rect.position.x + inset, rect.end.x - inset)
			p.y = r.randf_range(rect.position.y, rect.position.y + rect.size.y * float(o.flicker_y_frac))
			p.max_life = float(o.flicker_life_s)
	p.life = p.max_life
	return p
