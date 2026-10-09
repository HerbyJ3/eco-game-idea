extends RefCounted
## Buildings: shadows (L5), the y-sorted entity layer (L6: pad, exterior, door leaves, offline dim, construction) and the
## additive lights (L9: accents, windows, door strip and glow, offline flicker). Everything is read from the view model:
## the fit rect, door openness, light alphas, the construction draw list. Nothing is animated here.

const WorldCtx = preload("res://view/world/world_ctx.gd")
const BeingDraw = preload("res://view/world/being_draw.gd")

const Construction = preload("res://view/model/construction.gd")
const Doors = preload("res://view/model/doors.gd")
const ZSort = preload("res://view/model/zsort.gd")

var _pad_style: StyleBoxFlat
var _pad_key := ""


# ------------------------------------------------------------------ geometry

## The roof cut of a finished building (spec 9.2): the zoom cut or the peek cut, but only while its interior is loaded,
## so a building with nothing to show under the roof keeps its roof.
static func roof_cut(x: WorldCtx, b: Buildings.Building) -> float:
	if not b.finished() or x.vm.interior(b.id) == null:
		return 0.0
	return x.vm.selection.cut(b.id, x.vm.camera.zoom)


func _visible(x: WorldCtx, b: Buildings.Building) -> bool:
	return x.visible(x.vm.footprint_rect(b).grow(float(x.art.light.shadow.dx_scale_px)))


## The y-sorted entity records of the buildings (ZSort.sorted input).
static func entities(x: WorldCtx) -> Array:
	var out: Array = []
	for b in x.world.buildings.list:
		var foot: Rect2 = x.vm.footprint_rect(b)
		out.append({"type": "building", "id": b.id, "base_y": foot.end.y, "state": "", "built": b.built, "rect": foot,
				"pos": foot.get_center()})
	return out


## Door rect in world px: the manifest's normalised rect on the fit rect.
static func door_world(x: WorldCtx, kind: String, ext: Rect2) -> Rect2:
	var r: Rect2 = x.lib.door_rect(kind)
	return Rect2(ext.position + r.position * ext.size, r.size * ext.size)


## A glow copy of a sprite rect grown by `expand` px each side horizontally and by the same factor vertically, so the
## copy stays the sprite's own shape (never stretched).
static func halo_rect(ext: Rect2, expand: float) -> Rect2:
	var k := (ext.size.x + expand * 2.0) / ext.size.x
	var size := ext.size * k
	return Rect2(ext.get_center() - size * 0.5, size)


# ------------------------------------------------------------------ L5 shadows

func draw_shadows(c: Object, x: WorldCtx) -> void:
	var sh: Dictionary = x.art.light.shadow
	var alpha := float(sh.alpha) * x.daylight * float(sh.building_alpha_scale)
	if alpha <= 0.0:
		return
	var off := Vector2(x.shadow.x, x.shadow.y * float(sh.building_dy_scale))
	for b in _by_kind(x, x.detail):
		var ext: Rect2 = x.vm.sprite_rect(b)
		x.blit(c, "building.%s.mask.shadow" % b.kind, Rect2(ext.position + off, ext.size), alpha)


## The finished, visible buildings. Far zoom (sorted true) groups them by kind so same-texture draws are consecutive and
## the canvas batches them; near zoom keeps the list order.
func _by_kind(x: WorldCtx, keep_order: bool) -> Array:
	var out: Array = []
	for b in x.world.buildings.list:
		if b.finished() and _visible(x, b):
			out.append(b)
	if not keep_order:
		out.sort_custom(func(a: Buildings.Building, b: Buildings.Building) -> bool:
			return a.kind < b.kind or (a.kind == b.kind and a.id < b.id))
	return out


# ------------------------------------------------------------------ L6 entities

func draw_entities(c: Object, x: WorldCtx, beings: BeingDraw = null) -> void:
	var list := entities(x)
	if beings != null:
		list.append_array(BeingDraw.entities(x))
	for e in ZSort.sorted(list):
		if e.type == "being":
			beings.draw_outside(c, x, e.g)
			continue
		var b := x.world.buildings.get_building(int(e.id))
		if b != null and _visible(x, b):
			_draw_building(c, x, b, beings)


func _draw_building(c: Object, x: WorldCtx, b: Buildings.Building, beings: BeingDraw) -> void:
	var ext: Rect2 = x.vm.sprite_rect(b)
	var foot: Rect2 = x.vm.footprint_rect(b)
	if b.finished():
		if x.detail:
			_draw_pad(c, x, foot)
		var cut := roof_cut(x, b)
		x.blit(c, "building.%s.base" % b.kind, ext, 1.0 - cut)
		if cut > 0.0:
			x.blit(c, "building.%s.interior" % b.kind, x.vm.interior_rect(b.id), cut)
			if beings != null:
				beings.draw_interior(c, x, b.id, cut)
		if x.detail:
			_draw_door(c, x, b, ext, 1.0 - cut)
		var lights: Dictionary = x.vm.building(b.id).lights(x.hour, x.real_time, cut)
		if lights.dim > 0.0:
			x.blit(c, "building.%s.mask.shadow" % b.kind, ext, lights.dim)
	else:
		_draw_site(c, x, b, ext, foot)


func _draw_pad(c: Object, x: WorldCtx, foot: Rect2) -> void:
	var fit: Dictionary = x.art.fit
	var key := "%s|%s|%s" % [fit.pad_color, str(fit.pad_alpha), str(fit.pad_corner_px)]
	if _pad_key != key:
		_pad_key = key
		_pad_style = StyleBoxFlat.new()
		_pad_style.bg_color = x.col(fit.pad_color, float(fit.pad_alpha))
		_pad_style.set_corner_radius_all(int(fit.pad_corner_px))
	c.draw_style_box(_pad_style, foot)


func _draw_door(c: Object, x: WorldCtx, b: Buildings.Building, ext: Rect2, alpha: float) -> void:
	var door := door_world(x, b.kind, ext)
	var open: float = x.vm.building(b.id).door_open
	var mode: String = x.lib.door_mode(b.kind)
	var id := "building.%s.door" % b.kind
	var offs: Dictionary = Doors.leaf_offsets(open, mode, door.size, x.art)
	var clip := Rect2(door.position + (offs.clip as Rect2).position, (offs.clip as Rect2).size)
	if mode == "rollup":
		x.blit_clip(c, id, Rect2(door.position + (offs.panel as Vector2), door.size), clip, alpha)
		return
	var half := Vector2(door.size.x * 0.5, door.size.y)
	var tex := x.tex(id)
	if tex == null:
		return
	var tex_size := tex.get_size()
	var left := Rect2(door.position + (offs.left as Vector2), half)
	var right := Rect2(door.position + Vector2(half.x, 0.0) + (offs.right as Vector2), half)
	_leaf_half(c, x, tex, tex_size, id, left, clip, false, alpha)
	_leaf_half(c, x, tex, tex_size, id, right, clip, true, alpha)


## One half of a split door leaf: the left or right half of the leaf image, drawn into dest and clipped to the door rect.
func _leaf_half(c: Object, x: WorldCtx, tex: Texture2D, tex_size: Vector2, id: String, dest: Rect2, clip: Rect2,
		right_half: bool, alpha: float) -> void:
	var inter := dest.intersection(clip)
	if inter.size.x <= 0.0 or inter.size.y <= 0.0:
		return
	var k := Vector2(tex_size.x * 0.5 / dest.size.x, tex_size.y / dest.size.y)
	var origin := Vector2(tex_size.x * 0.5 if right_half else 0.0, 0.0)
	var src := Rect2(origin + (inter.position - dest.position) * k, inter.size * k)
	if alpha <= 0.0:
		return
	c.draw_texture_rect_region(tex, inter, src, Color(1, 1, 1, alpha))
	if x.record:
		x.log.append({"id": id, "rect": inter, "tex_size": tex_size, "src": src, "alpha": alpha})


# ------------------------------------------------------------------ construction

func _draw_site(c: Object, x: WorldCtx, b: Buildings.Building, ext: Rect2, foot: Rect2) -> void:
	var cfg: Dictionary = x.art.construction
	var ph := Construction.phases(b.built, x.art)
	var pad := float(cfg.clip_pad_px)
	for item in Construction.draw_list(b.built, ext, x.art):
		match item.layer:
			"stakes":
				_draw_stakes(c, x, foot, cfg.survey)
			"ghost":
				var s: Dictionary = cfg.survey
				x.blit(c, "building.%s.mask.ghost" % b.kind, ext,
						float(s.ghost_alpha) + float(s.ghost_amp) * sin(x.real_time * float(s.ghost_rate_rad_s)))
			"slab":
				_draw_slab(c, x, ext, float(ph.p), cfg.slab)
			"gray":
				x.blit_clip(c, "building.%s.mask.gray" % b.kind, ext, _clip_below(ext, float(item.clip_top), pad))
			"paint":
				x.blit_clip(c, "building.%s.base" % b.kind, ext, _clip_below(ext, float(item.clip_top), pad))
			"scaffold":
				_draw_scaffold(c, x, ext, float(ph.sa), cfg.scaffold)


## Everything of the sprite rect at or below clip_top, widened by the clip pad on the sides and the bottom (proto L1360).
static func _clip_below(ext: Rect2, clip_top: float, pad: float) -> Rect2:
	return Rect2(ext.position.x - pad, clip_top, ext.size.x + pad * 2.0, ext.end.y - clip_top + pad)


func _draw_stakes(c: Object, x: WorldCtx, foot: Rect2, cfg: Dictionary) -> void:
	var size := Vector2(float(cfg.stake_w_px), float(cfg.stake_h_px))
	var color: Color = x.col(cfg.stake_color)
	var lift := size.y
	for p in [Vector2(foot.position.x, foot.position.y), Vector2(foot.end.x - size.x, foot.position.y),
			Vector2(foot.position.x, foot.end.y - lift), Vector2(foot.end.x - size.x, foot.end.y - lift)]:
		c.draw_rect(Rect2(p, size), color)


func _draw_slab(c: Object, x: WorldCtx, ext: Rect2, p: float, cfg: Dictionary) -> void:
	var inset := float(cfg.inset_px)
	var top := ext.position.y + ext.size.y * float(cfg.top_frac)
	var rect := Rect2(ext.position.x + inset, top, ext.size.x - inset * 2.0, ext.size.y * float(cfg.bottom_frac))
	var a := minf(1.0, p / float(cfg.fade_p))
	c.draw_rect(rect, x.col(cfg.color, a))
	var line: Color = x.col(cfg.line_color, a)
	var yy := top
	while yy < ext.end.y:
		c.draw_rect(Rect2(rect.position.x, yy, rect.size.x, float(cfg.line_h_px)).intersection(rect), line)
		yy += float(cfg.line_spacing_px)


func _draw_scaffold(c: Object, x: WorldCtx, ext: Rect2, sa: float, cfg: Dictionary) -> void:
	var color: Color = x.col(cfg.color, float(cfg.alpha) * sa)
	var diag: Color = x.col(cfg.color, float(cfg.diag_alpha) * sa)
	var w := float(cfg.line_w_px)
	var inset := float(cfg.edge_inset_px)
	var top := ext.position.y + ext.size.y * float(cfg.top_frac)
	var bottom := ext.end.y - float(cfg.bottom_inset_px)
	var x0 := ext.position.x + inset
	var x1 := ext.end.x - inset
	var cols := maxi(int(cfg.min_cols), roundi((ext.size.x - inset * 2.0) / float(cfg.col_spacing_px)))
	var step := (ext.size.x - inset * 2.0) / float(cols)
	var xx := x0
	while xx <= x1 + w:
		c.draw_line(Vector2(xx, top), Vector2(xx, bottom), color, w)
		xx += step
	var yy := top
	while yy <= bottom:
		c.draw_line(Vector2(x0, yy), Vector2(x1, yy), color, w)
		yy += float(cfg.row_spacing_px)
	var run := float(cfg.diag_run_px)
	xx = x0
	while xx < ext.end.x - inset - run:
		c.draw_line(Vector2(xx, bottom), Vector2(xx + run, top), diag, w)
		xx += float(cfg.diag_spacing_px)


# ------------------------------------------------------------------ L9 lights

func draw_lights(c: Object, x: WorldCtx) -> void:
	if not x.detail:
		_draw_lights_far(c, x)
		return
	var l: Dictionary = x.art.light
	for b in x.world.buildings.list:
		if not b.finished() or not _visible(x, b):
			continue
		var anim = x.vm.building(b.id)
		if anim == null:
			continue
		var ext: Rect2 = x.vm.sprite_rect(b)
		var foot: Rect2 = x.vm.footprint_rect(b)
		var cut := roof_cut(x, b)
		var lights: Dictionary = anim.lights(x.hour, x.real_time, cut)
		if lights.accent > 0.0:
			x.blit(c, "building.%s.mask.accent" % b.kind, ext, lights.accent)
			x.blit(c, "building.%s.mask.accent" % b.kind, halo_rect(ext, float(l.accent.halo_expand_px)),
					lights.accent * float(l.accent.halo_alpha))
		if lights.windows > 0.0:
			x.blit(c, "building.%s.mask.windows" % b.kind, ext, lights.windows)
			x.blit(c, "building.%s.mask.windows" % b.kind, halo_rect(ext, float(l.windows.halo_expand_px)),
					lights.windows * float(l.windows.halo_alpha / l.windows.alpha))
		if lights.strip > 0.0:
			var s: Dictionary = l.ground_strip
			var strip_color: Color = x.col(s.color, lights.strip)
			c.draw_rect(Rect2(foot.position.x, foot.end.y, foot.size.x, float(s.h_px)), strip_color)
			var out := float(s.outer_expand_px)
			c.draw_rect(Rect2(foot.position.x - out, foot.end.y + float(s.h_px), foot.size.x + out * 2.0, float(s.h_px)),
					x.col(s.color, lights.strip * float(s.alpha_outer / s.alpha)))
		if lights.door_glow > 0.0:
			var door := door_world(x, b.kind, ext)
			var d: Dictionary = x.art.door
			x.glow_disc(c, Vector2(door.get_center().x, door.end.y), door.size.x * float(d.glow_radius_frac) * 2.0,
					x.col(d.glow_color, lights.door_glow))
		if b.kind == "comms" and x.lib.is_placeholder("building.comms.base"):
			_draw_beacon(c, x, ext)


## Far zoom (spec 13 lod.detail_min_zoom): one light pass per mask texture, no halo copies, ground strips or door glow.
## The layer is additive, so order does not matter and the masks are drawn grouped by kind to batch.
func _draw_lights_far(c: Object, x: WorldCtx) -> void:
	var list: Array = []
	for b in _by_kind(x, false):
		var anim = x.vm.building(b.id)
		if anim != null:
			list.append([b, anim.lights(x.hour, x.real_time, roof_cut(x, b))])
	for mask in ["accent", "windows"]:
		for e in list:
			var b: Buildings.Building = e[0]
			var a: float = e[1][mask]
			if a > 0.0:
				x.blit(c, "building.%s.mask.%s" % [b.kind, mask], x.vm.sprite_rect(b), a)
	for e in list:
		var b: Buildings.Building = e[0]
		if b.kind == "comms" and x.lib.is_placeholder("building.comms.base"):
			_draw_beacon(c, x, x.vm.sprite_rect(b))


## The comms placeholder's blinking red beacon (proto L1591).
func _draw_beacon(c: Object, x: WorldCtx, ext: Rect2) -> void:
	var cfg: Dictionary = x.art.pipeline.placeholder.comms.beacon
	if sin(x.real_time * float(cfg.rate_rad_s)) <= float(cfg.threshold):
		return
	var at := ext.position + Vector2(float(cfg.pos_frac[0]), float(cfg.pos_frac[1])) * ext.size
	c.draw_circle(at, float(cfg.radius_px), x.col(cfg.color, float(cfg.alpha)))
