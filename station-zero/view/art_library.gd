class_name ArtLibrary
extends RefCounted
## View-side loader for assets/processed/manifest.json (spec sprite-view.md 3.9, 3.10).
## Decides only from the manifest, never by probing for raw files. Read-only, no sim access.
##
## Textures are built from the PNG bytes (PNG bytes + ImageTexture) with mipmaps
## generated here. That path does not depend on the editor import cache, which is gitignored and
## absent in a fresh clone, and it gives the mipmaps the spec requires (T-IMP) without a committed
## .import file. The CanvasItem that draws a texture still needs texture_filter =
## TEXTURE_FILTER_LINEAR_WITH_MIPMAPS (that is a node property, not a texture one).

const ROOT := "res://assets/processed/"
const MANIFEST := ROOT + "manifest.json"

## Message of the most recent failed lookup, "" after a success. Tests read it.
var last_error := ""
## Tests set this to keep expected failures out of the log.
var silent := false

var _entries: Dictionary = {}
var _textures: Dictionary = {}  # id -> Texture2D
var _sheets: Dictionary = {}    # sheet name -> parsed json
var _loaded := false


## Parses the manifest. Returns false (and sets last_error) when it is missing or malformed.
func load_manifest(path: String = MANIFEST) -> bool:
	_entries = {}
	_textures = {}
	_sheets = {}
	_loaded = false
	if not FileAccess.file_exists(path):
		return _fail("art manifest not found: %s" % path)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary) or not (parsed as Dictionary).get("entries") is Dictionary:
		return _fail("art manifest malformed: %s" % path)
	_entries = (parsed as Dictionary)["entries"]
	_loaded = true
	last_error = ""
	return true


func _ensure() -> void:
	if not _loaded:
		load_manifest()


func ids() -> Array[String]:
	_ensure()
	var out: Array[String] = []
	for k in _entries.keys():
		out.append(k)
	out.sort()
	return out


func has_entry(id: String) -> bool:
	_ensure()
	return _entries.has(id)


## Raw manifest entry (a copy), or {} for an unknown id.
func entry(id: String) -> Dictionary:
	_ensure()
	return (_entries[id] as Dictionary).duplicate(true) if _entries.has(id) else {}


## True when the id has a file the view can draw. False for an optional entry whose file is null
## (decals, sleeping poses without art): the view then uses its procedural fallback.
func has_art(id: String) -> bool:
	_ensure()
	return _entries.has(id) and _entries[id].get("file") != null


## True when the entry is a substitute (kind placeholder file, or no file at all).
func is_placeholder(id: String) -> bool:
	_ensure()
	return _entries.has(id) and bool(_entries[id].get("placeholder", false))


## Texture for a manifest id, cached. Follows the manifest exactly: a kind whose raw is missing
## already points at placeholder/... in its entry, so the file is loaded as given. An optional entry
## with file null returns null (use has_art first; the caller draws procedurally). An unknown id
## or an unreadable file also returns null, with last_error set and a push_error unless silent.
func texture(id: String) -> Texture2D:
	if _textures.has(id):
		return _textures[id]
	if not _loaded and not load_manifest():
		return null
	if not _entries.has(id):
		_fail("unknown art id '%s'" % id)
		return null
	var file: Variant = _entries[id].get("file")
	if file == null:
		last_error = ""
		return null
	# Bytes + load_png_from_buffer rather than Image.load_from_file: same pixels, but no
	# "will not work on export" warning for res:// paths, and it works wherever the PNG is packed.
	var img := Image.new()
	var bytes := FileAccess.get_file_as_bytes(ROOT + String(file))
	if bytes.is_empty() or img.load_png_from_buffer(bytes) != OK or img.is_empty():
		_fail("art file for '%s' failed to load: %s%s" % [id, ROOT, file])
		return null
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_textures[id] = tex
	last_error = ""
	return tex


## Size in pixels the manifest promises (w, h), (0, 0) for an unknown id or a null file.
func size(id: String) -> Vector2i:
	_ensure()
	if not _entries.has(id):
		return Vector2i.ZERO
	return Vector2i(int(_entries[id].get("w", 0)), int(_entries[id].get("h", 0)))


## Normalized door rect Rect2(x0, y0, x1 - x0, y1 - y0) of a building entry, or an empty Rect2.
func door_rect(kind: String) -> Rect2:
	_ensure()
	var r: Variant = _entries.get("building.%s.base" % kind, {}).get("door_rect")
	if not (r is Array) or (r as Array).size() != 4:
		return Rect2()
	return Rect2(r[0], r[1], r[2] - r[0], r[3] - r[1])


## "split" or "rollup" ("" when unknown).
func door_mode(kind: String) -> String:
	_ensure()
	return String(_entries.get("building.%s.base" % kind, {}).get("door_mode", ""))


## Normalized pivot of a building base or interior entry (x, y), default bottom centre.
func pivot(id: String) -> Vector2:
	_ensure()
	var p: Variant = _entries.get(id, {}).get("pivot")
	if p is Array and (p as Array).size() == 2:
		return Vector2(p[0], p[1])
	return Vector2(0.5, 1.0)


## Parsed characters/<sheet>.json ("jumpsuit", "eva", "construction"), cached. {} when missing.
## Keys: cell_px, pivot_px, scale, frames { name: { col, row, lamp_anchor_px } }.
func sheet(sheet_name: String) -> Dictionary:
	if _sheets.has(sheet_name):
		return _sheets[sheet_name]
	var path := "%scharacters/%s.json" % [ROOT, sheet_name]
	var data: Dictionary = {}
	if FileAccess.file_exists(path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary:
			data = parsed
	if data.is_empty():
		_fail("sheet table not found or malformed: %s" % path)
	_sheets[sheet_name] = data
	return data


## Frame table entry { col, row, lamp_anchor_px } of a sheet, or {}.
func frame(sheet_name: String, frame_name: String) -> Dictionary:
	return sheet(sheet_name).get("frames", {}).get(frame_name, {})


## Source rect of a frame inside its atlas, in atlas pixels. Empty Rect2 for an unknown frame.
func frame_rect(sheet_name: String, frame_name: String) -> Rect2:
	var f := frame(sheet_name, frame_name)
	if f.is_empty():
		return Rect2()
	var cell := float(sheet(sheet_name).get("cell_px", 0))
	return Rect2(float(f["col"]) * cell, float(f["row"]) * cell, cell, cell)


## Helmet lamp anchor in cell pixels, or null (jumpsuit frames, back-facing frames).
func lamp_anchor(sheet_name: String, frame_name: String) -> Variant:
	var a: Variant = frame(sheet_name, frame_name).get("lamp_anchor_px")
	if a is Array and (a as Array).size() == 2:
		return Vector2(a[0], a[1])
	return null


func _fail(msg: String) -> bool:
	last_error = msg
	if not silent:
		push_error(msg)
	return false
