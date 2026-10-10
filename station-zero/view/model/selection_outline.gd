extends RefCounted
## The outline of a selected colonist, built at runtime from the alpha of its own sprite (no new art). Same idea as the
## building outline in view/world/selection_draw.gd.


## A ring mask the size of `alpha`: opaque pixels within `outline_px` of the sprite's opaque area, outside it. White,
## alpha 1 on the ring and 0 elsewhere; the caller tints it.
static func ring(alpha: Image, outline_px: int) -> Image:
	var src := alpha.duplicate() as Image
	if src.is_compressed():
		src.decompress()
	src.convert(Image.FORMAT_RGBA8)
	var w := src.get_width()
	var h := src.get_height()
	var out := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var r := maxi(1, outline_px)
	for y in h:
		for x in w:
			if src.get_pixel(x, y).a > 0.0:
				continue
			var hit := false
			for dy in range(-r, r + 1):
				if hit:
					break
				for dx in range(-r, r + 1):
					if dx * dx + dy * dy > r * r:
						continue
					var sx := x + dx
					var sy := y + dy
					if sx >= 0 and sy >= 0 and sx < w and sy < h and src.get_pixel(sx, sy).a > 0.0:
						hit = true
						break
			if hit:
				out.set_pixel(x, y, Color(1, 1, 1, 1))
	return out
