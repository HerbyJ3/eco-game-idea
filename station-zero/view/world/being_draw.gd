extends RefCounted
## Colonists (spec sprite-view.md 4.4, 6, 7): outside beings in the y-sorted entity layer, beings in a tunnel in the
## transit layer, beings in an open interior above the interior art, and the helmet lamp glow in the additive layer.
## Every position, frame, mirror, scale and lamp level comes from the view model (vm.being); this only puts them on a
## canvas.

const WorldCtx = preload("res://view/world/world_ctx.gd")

## How far beyond a being's feet its sprite can reach, for culling (world px).
const CULL_MARGIN_PX := 24.0


# ------------------------------------------------------------------ records

## The y-sorted entity records of the beings drawn outside (ZSort.sorted input), each with its Being under "g".
static func entities(x: WorldCtx) -> Array:
	var out: Array = []
	for g in x.world.beings:
		var rec: Variant = x.vm.being(g.id)
		if rec != null and rec.visible and rec.space == "outside":
			out.append({"type": "being", "id": g.id, "base_y": rec.pos.y, "state": g.state, "built": 1.0, "rect": Rect2(),
					"pos": rec.pos, "g": g})
	return out


static func _near(x: WorldCtx, p: Vector2) -> bool:
	return x.visible(Rect2(p - Vector2(CULL_MARGIN_PX, CULL_MARGIN_PX), Vector2(CULL_MARGIN_PX, CULL_MARGIN_PX) * 2.0))


# ------------------------------------------------------------------ geometry of one sprite

## Where and how a being's pose is drawn: {id (manifest texture), sheet, src, dest (relative to the pivot), feet (draw
## origin, bob and sleeper offset applied), rot, mirror, scale (sprite scale), sc (size relative to an Earth-born)}.
## Empty when the pose has no frame.
static func sprite_params(x: WorldCtx, id: int, rec: Dictionary) -> Dictionary:
	var art: Dictionary = x.art
	var pose: Dictionary = rec.pose
	if pose.is_empty():
		return {}
	var tex_id: String = pose.sheet
	var s: float = float(rec.height_px) / float(art.pipeline.character_height_in_cell_px)
	var sc: float = float(rec.height_px) / float(art.colonist.height_px)
	var src: Rect2
	var dest: Rect2
	var sheet_name := ""
	if tex_id.begins_with("character.sleeping."):
		var size := Vector2(x.lib.size(tex_id))
		var pivot := Vector2(float(art.optional.sleeping.pivot_px[0]), float(art.optional.sleeping.pivot_px[1]))
		src = Rect2(Vector2.ZERO, size)
		dest = Rect2(-pivot * s, size * s)
	else:
		sheet_name = tex_id.split(".")[1]
		src = x.lib.frame_rect(sheet_name, pose.frame)
		if src.size == Vector2.ZERO:
			return {}
		var sheet: Dictionary = x.lib.sheet(sheet_name)
		var pivot := Vector2(float(sheet.pivot_px[0]), float(sheet.pivot_px[1]))
		dest = Rect2(-pivot * s, Vector2(float(sheet.cell_px), float(sheet.cell_px)) * s)
	var feet: Vector2 = rec.pos
	var rot := deg_to_rad(float(pose.rotate_deg))
	if is_zero_approx(rot):
		var bob := float(art.walk.bob_walk_px) * absf(cos(float(rec.phase))) if rec.moving \
				else float(art.walk.bob_idle_px) * sin(x.real_time * float(art.walk.bob_idle_rate_rad_s) + float(id))
		feet.y -= bob
	else:
		# The fallback sleeper: lying down. The pivot is at the feet, so the feet move half a body length from the slot to
		# put the body on it, then the spec's nudge (x scales with the size, y does not).
		feet -= Vector2(0.0, -float(rec.height_px) * 0.5).rotated(rot)
		feet += Vector2(float(art.colonist.sleeper_offset_px[0]) * sc, float(art.colonist.sleeper_offset_px[1]))
	return {"id": tex_id, "sheet": sheet_name, "src": src, "dest": dest, "feet": feet, "rot": rot,
			"mirror": bool(pose.mirror), "scale": s, "sc": sc}


func _shadow(c: Object, x: WorldCtx, rec: Dictionary, sc: float) -> void:
	var sh: Dictionary = x.art.colonist.shadow
	var a := float(sh.alpha) * x.daylight
	if a > 0.0:
		x.ellipse(c, rec.pos + Vector2(0.0, float(sh.dy_px)), float(sh.rx_px) * sc, float(sh.ry_px) * sc, x.col(sh.color, a))


# ------------------------------------------------------------------ L4 transit, L6 outside, interiors

## Beings in a tunnel (spec 6, L4): jumpsuit, y-sorted, drawn under the buildings.
func draw_transit(c: Object, x: WorldCtx) -> void:
	var list: Array = []
	for g in x.world.beings:
		var rec: Variant = x.vm.being(g.id)
		if rec != null and rec.visible and rec.space == "transit" and _near(x, rec.pos):
			list.append([rec.pos.y, g.id, rec])
	list.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	for e in list:
		_draw_sprite(c, x, int(e[1]), e[2], 1.0)


## One outside being: shadow, then sprite (called in y-sort order by the entity pass).
func draw_outside(c: Object, x: WorldCtx, g: Being) -> void:
	var rec: Variant = x.vm.being(g.id)
	if rec == null or not rec.visible or not _near(x, rec.pos):
		return
	var p := sprite_params(x, g.id, rec)
	if p.is_empty():
		return
	_shadow(c, x, rec, p.sc)
	_draw_params(c, x, p, 1.0)


## The beings of an open interior, sorted by their interior y, at the roof cut as alpha (spec 6, 7.3).
func draw_interior(c: Object, x: WorldCtx, building_id: int, cut: float) -> void:
	var model = x.vm.interior(building_id)
	if model == null or cut <= 0.0:
		return
	var list: Array = []
	for id in model.drawn_ids():
		var rec: Variant = x.vm.being(id)
		if rec != null and rec.inside:
			list.append([rec.pos.y, id, rec])
	list.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	for e in list:
		_draw_sprite(c, x, int(e[1]), e[2], cut)


func _draw_sprite(c: Object, x: WorldCtx, id: int, rec: Dictionary, alpha: float) -> void:
	var p := sprite_params(x, id, rec)
	if not p.is_empty():
		_draw_params(c, x, p, alpha)


func _draw_params(c: Object, x: WorldCtx, p: Dictionary, alpha: float) -> void:
	x.sprite(c, p.id, p.dest, p.src, p.feet, p.rot, p.mirror, alpha)


# ------------------------------------------------------------------ L9 helmet lamps

## Facing as the ground pool's direction (unit vector, y down).
static func _facing_vec(rec: Dictionary) -> Vector2:
	match String(rec.facing.dir):
		"front":
			return Vector2.DOWN
		"back":
			return Vector2.UP
	return Vector2.LEFT if rec.facing.mirror else Vector2.RIGHT


## {anchor, pool, level, sc}: where the lamp of an outside being glows, or {} when it is off or has no anchor.
static func lamp_params(x: WorldCtx, id: int, rec: Dictionary) -> Dictionary:
	if float(rec.lamp_level) <= 0.0 or not rec.visible or rec.space != "outside":
		return {}
	var p := sprite_params(x, id, rec)
	if p.is_empty() or p.sheet == "jumpsuit":
		return {}
	var a: Variant = x.lib.lamp_anchor(p.sheet, rec.pose.frame)
	if a == null:
		return {}
	var sheet: Dictionary = x.lib.sheet(p.sheet)
	var local: Vector2 = ((a as Vector2) - Vector2(float(sheet.pivot_px[0]), float(sheet.pivot_px[1]))) * float(p.scale)
	if p.mirror:
		local.x = -local.x
	var lamp: Dictionary = x.art.lamp
	return {"anchor": (p.feet as Vector2) + local, "level": float(rec.lamp_level), "sc": float(p.sc),
			"pool": (rec.pos as Vector2) + _facing_vec(rec) * float(lamp.ground_offset_px) * float(p.sc)}


func draw_lamps(c: Object, x: WorldCtx) -> void:
	var lamp: Dictionary = x.art.lamp
	for g in x.world.beings:
		var rec: Variant = x.vm.being(g.id)
		if rec == null or float(rec.lamp_level) <= 0.0 or not _near(x, rec.pos):
			continue
		var l := lamp_params(x, g.id, rec)
		if l.is_empty():
			continue
		var k: float = l.level
		var sc: float = l.sc
		x.glow_ellipse(c, l.pool, float(lamp.ground_r_px) * sc, float(lamp.ground_r_px) * sc * 0.5,
				x.col(lamp.outer_color, float(lamp.ground_alpha) * k))
		x.glow_disc(c, l.anchor, float(lamp.outer_r_px) * sc, x.col(lamp.outer_color, float(lamp.outer_alpha) * k))
		x.glow_disc(c, l.anchor, float(lamp.core_r_px) * sc, x.col(lamp.core_color, float(lamp.core_alpha) * k))
