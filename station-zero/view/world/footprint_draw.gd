extends RefCounted
## Layer L2 (spec 5.7): the footprints the sim keeps, as one small quad per print from a single baked print texture
## (ellipse plus heel), rotated by the print's heading and faded by the model's alpha. Every quad shares one texture, so
## the whole layer is one batch. The visible set and the alpha come from view/model/footprints.gd.

const WorldCtx = preload("res://view/world/world_ctx.gd")
const Footprints = preload("res://view/model/footprints.gd")

## Texels per world px of the baked print (a drawing detail: higher is crisper at zoom 6).
const BAKE_TEXELS_PER_PX := 24

var _tex: ImageTexture
var _key := ""
## Quads drawn by the last pass, for tests and the performance report.
var drawn := 0


## The baked print: ellipse (rx, ry) in the footprint colour, the heel rect over it at heel_alpha_scale, centred. Pixels
## are white-alpha-modulated by the per-vertex colour at draw time, so one texture serves every alpha.
static func bake(art: Dictionary) -> Image:
	var fp: Dictionary = art.footprint
	var rx := float(fp.rx_px)
	var ry := float(fp.ry_px)
	var k := float(BAKE_TEXELS_PER_PX)
	var w := int(ceil(rx * 2.0 * k))
	var h := int(ceil(ry * 2.0 * k))
	var body := Color.html(String(fp.color))
	var heel_c := Color.html(String(fp.heel_color))
	var heel: Array = fp.heel_rect_px
	var heel_a := float(fp.heel_alpha_scale)
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for j in h:
		for i in w:
			var px := (float(i) + 0.5) / k - rx
			var py := (float(j) + 0.5) / k - ry
			var in_body := (px * px) / (rx * rx) + (py * py) / (ry * ry) <= 1.0
			var in_heel := px >= float(heel[0]) and px <= float(heel[0]) + float(heel[2]) \
					and py >= float(heel[1]) and py <= float(heel[1]) + float(heel[3])
			if in_body and in_heel:
				var c := body.lerp(heel_c, heel_a)
				c.a = 1.0
				img.set_pixel(i, j, c)
			elif in_body:
				img.set_pixel(i, j, body)
			elif in_heel:
				var c2 := heel_c
				c2.a = heel_a
				img.set_pixel(i, j, c2)
	return img


func _texture(art: Dictionary) -> ImageTexture:
	var key := JSON.stringify(art.footprint)
	if _tex == null or key != _key:
		_key = key
		_tex = ImageTexture.create_from_image(bake(art))
	return _tex


func draw(c: Object, x: WorldCtx) -> void:
	var tex := _texture(x.art)
	var rx := float(x.art.footprint.rx_px)
	var ry := float(x.art.footprint.ry_px)
	var uv := PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	var corners: Array[Vector2] = [Vector2(-rx, -ry), Vector2(rx, -ry), Vector2(rx, ry), Vector2(-rx, ry)]
	drawn = 0
	for f in Footprints.drawn(x.world, x.view_rect.grow(maxf(rx, ry)), x.art):
		var rot := Transform2D(float(f.heading), Vector2(f.x, f.y))
		var pts := PackedVector2Array()
		for q in corners:
			pts.append(rot * q)
		var col := Color(1, 1, 1, float(f.alpha))
		c.draw_primitive(pts, PackedColorArray([col, col, col, col]), uv, tex)
		drawn += 1
