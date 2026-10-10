extends RefCounted
## Layer L10 (spec 9.3): the selected building's outline. It is built at runtime from the alpha of the sprite that is
## showing (the exterior below the silhouette cut, the interior above it): the opaque area is grown by
## pipeline.masks.outline.radius_px (scaled to the texture's width) and the original area cut out, so the ring hugs the
## silhouette and is never a box. The ring is pulsed by the model and a wider halo copy is drawn under it. The prebuilt
## outline PNGs of the manifest are only a fallback when the sprite has no texture.

const WorldCtx = preload("res://view/world/world_ctx.gd")
const Selection = preload("res://view/model/selection.gd")
const BuildingDraw = preload("res://view/world/building_draw.gd")
const BeingDraw = preload("res://view/world/being_draw.gd")
const PanelText = preload("res://view/model/being_panel.gd")
const SelectionOutline = preload("res://view/model/selection_outline.gd")

## Built colonist rings by "texture id|frame rect": {tex: ImageTexture, pad: int (texels added on every side)}.
var _being_rings: Dictionary = {}
## Built rings by source texture id: {tex: ImageTexture, pad: int (texels added on every side)}.
var _rings: Dictionary = {}


## The ring image of an RGBA image: pixels within `radius` texels of the area where alpha >= alpha_min, outside it, in
## `color`, on a canvas grown by `radius` on every side.
static func build_ring(src: Image, radius: int, alpha_min: int, color: Color) -> Image:
	var img := src.duplicate() as Image
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	var ow := w + radius * 2
	var oh := h + radius * 2
	var data := img.get_data()
	var solid := PackedByteArray()
	solid.resize(w * h)
	for i in w * h:
		solid[i] = 1 if data[i * 4 + 3] >= alpha_min else 0
	var out := PackedByteArray()
	out.resize(ow * oh)
	var disk: Array[Vector2i] = []
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if dx * dx + dy * dy <= radius * radius:
				disk.append(Vector2i(dx, dy))
	for y in h:
		for x in w:
			if solid[y * w + x] == 0:
				continue
			# Only edge pixels can reach beyond the area.
			var edge := x == 0 or y == 0 or x == w - 1 or y == h - 1 or solid[y * w + x - 1] == 0 \
					or solid[y * w + x + 1] == 0 or solid[(y - 1) * w + x] == 0 or solid[(y + 1) * w + x] == 0
			if not edge:
				continue
			for d in disk:
				out[(y + radius + d.y) * ow + x + radius + d.x] = 1
	var ring := PackedByteArray()
	ring.resize(ow * oh * 4)
	for y in oh:
		for x in ow:
			if out[y * ow + x] == 0:
				continue
			var sx := x - radius
			var sy := y - radius
			if sx >= 0 and sy >= 0 and sx < w and sy < h and solid[sy * w + sx] == 1:
				continue
			var o := (y * ow + x) * 4
			ring[o] = int(color.r8)
			ring[o + 1] = int(color.g8)
			ring[o + 2] = int(color.b8)
			ring[o + 3] = 255
	return Image.create_from_data(ow, oh, false, Image.FORMAT_RGBA8, ring)


## {tex, pad} for a manifest texture id, built once. Empty when the id has no texture.
func ring_for(x: WorldCtx, id: String) -> Dictionary:
	if _rings.has(id):
		return _rings[id]
	var t := x.lib.texture(id)
	if t == null:
		return {}
	var o: Dictionary = x.art.pipeline.masks.outline
	var radius := maxi(1, roundi(float(o.radius_px) * t.get_width() / float(o.radius_ref_width_px)))
	var color := Color8(int(o.color[0]), int(o.color[1]), int(o.color[2]))
	var img := build_ring(t.get_image(), radius, int(o.alpha_min), color)
	_rings[id] = {"tex": ImageTexture.create_from_image(img), "pad": radius}
	return _rings[id]


func draw(c: Object, x: WorldCtx) -> void:
	_draw_being(c, x)
	var sel: int = x.vm.selection.selected
	if sel == 0:
		return
	var b := x.world.buildings.get_building(sel)
	if b == null or not x.visible(x.vm.footprint_rect(b).grow(float(x.art.selection.halo_expand_px))):
		return
	var cut := BuildingDraw.roof_cut(x, b)
	var interior: bool = Selection.outline_source(cut, x.art) == "interior"
	var id := "building.%s.interior" % b.kind if interior else "building.%s.base" % b.kind
	var rect: Rect2 = x.vm.interior_rect(b.id) if interior else x.vm.sprite_rect(b)
	var ring := ring_for(x, id)
	if ring.is_empty():
		_fallback(c, x, b, interior, rect)
		return
	var pad_px: float = float(ring.pad) * rect.size.x / float((ring.tex as Texture2D).get_width() - int(ring.pad) * 2)
	var outer := rect.grow(pad_px)
	var pulse := Selection.pulse(x.real_time, x.art)
	var halo := float(x.art.selection.halo_expand_px)
	x.blit_texture(c, "outline.halo." + id, ring.tex, BuildingDraw.halo_rect(outer, halo), pulse * float(x.art.selection.halo_alpha))
	x.blit_texture(c, "outline." + id, ring.tex, outer, pulse)


## No sprite texture to read: the manifest's outline mask at the same rect.
func _fallback(c: Object, x: WorldCtx, b: Buildings.Building, interior: bool, rect: Rect2) -> void:
	var mask := "building.%s.interior_outline" % b.kind if interior else "building.%s.mask.outline" % b.kind
	x.blit(c, mask, rect, Selection.pulse(x.real_time, x.art))


## The selected colonist's outline (docs/specs/emotions.md 7.1 rule 2): a ring built from the alpha of the sprite being drawn,
## selection.outline_px wide in world px, in selection.outline_color. Nothing while the colonist is not drawn.
func _draw_being(c: Object, x: WorldCtx) -> void:
	var id: int = x.vm.selection.selected_being
	if id == 0:
		return
	var rec: Variant = x.vm.being(id)
	if rec == null or not rec.visible:
		return
	var p := BeingDraw.sprite_params(x, id, rec)
	if p.is_empty():
		return
	var tex := x.lib.texture(p.id)
	if tex == null:
		return
	var sel: Dictionary = PanelText.selection_cfg()
	var scale_px: float = p.scale
	var radius := maxi(1, roundi(float(sel.outline_px) / scale_px))
	var key := "%s|%s|%d" % [p.id, str(p.src), radius]
	if not _being_rings.has(key):
		var region := tex.get_image().get_region(Rect2i(p.src))
		region.convert(Image.FORMAT_RGBA8)
		var padded := Image.create(region.get_width() + radius * 2, region.get_height() + radius * 2, false, Image.FORMAT_RGBA8)
		padded.blit_rect(region, Rect2i(Vector2i.ZERO, region.get_size()), Vector2i(radius, radius))
		_being_rings[key] = ImageTexture.create_from_image(SelectionOutline.ring(padded, radius))
	var oc: Array = sel.outline_color
	var colour := Color8(int(oc[0]), int(oc[1]), int(oc[2]))
	var grow := float(radius) * scale_px
	c.draw_set_transform(p.feet, p.rot, Vector2(-1.0 if p.mirror else 1.0, 1.0))
	c.draw_texture_rect(_being_rings[key], (p.dest as Rect2).grow(grow), false, colour)
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
