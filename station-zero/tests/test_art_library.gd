extends RefCounted
## ArtLibrary against the real generated manifest. Loads each distinct file once (cached), so it is fast.


func test_every_entry_with_a_file_loads_at_manifest_size(t) -> void:
	var lib := ArtLibrary.new()
	t.check(lib.load_manifest(), "manifest loads: " + lib.last_error)
	var ids := lib.ids()
	t.check(ids.size() >= 80, "manifest has entries (%d)" % ids.size())
	var loaded := 0
	for id in ids:
		if not lib.has_art(id):
			continue
		var tex := lib.texture(id)
		t.check(tex != null, "%s loads: %s" % [id, lib.last_error])
		if tex == null:
			continue
		loaded += 1
		t.eq(Vector2i(tex.get_width(), tex.get_height()), lib.size(id), id + " size")
		t.check(lib.texture(id) == tex, id + " is cached")
	t.check(loaded >= 60, "many textures loaded (%d)" % loaded)


func test_mipmaps_on_buildings_interiors_atlases(t) -> void:
	var lib := ArtLibrary.new()
	for id in ["building.habitat.base", "building.habitat.interior", "character.eva"]:
		var tex := lib.texture(id) as ImageTexture
		t.check(tex != null and tex.get_image().has_mipmaps(), id + " has mipmaps")


func test_placeholders_resolve(t) -> void:
	var lib := ArtLibrary.new()
	lib.load_manifest()
	var subst := 0
	for id in lib.ids():
		if not lib.is_placeholder(id):
			continue
		subst += 1
		if lib.has_art(id):
			t.check(lib.texture(id) != null, id + " placeholder file resolves")
			t.check(String(lib.entry(id)["file"]).begins_with("placeholder/"), id + " points at placeholder/")
		else:
			# Optional art (decals, sleeping poses) without a file: no texture, no error, view goes procedural.
			t.check(lib.texture(id) == null and lib.last_error == "", id + " null file gives null, no error")
	t.check(subst > 0, "manifest has placeholder entries")
	# Every kind has an exterior and an interior in the manifest, real or placeholder.
	for kind in ["reactor", "habitat", "workshop", "green_room", "archive", "comms"]:
		for part in ["base", "door", "interior", "interior_outline", "mask.accent"]:
			t.check(lib.has_art("building.%s.%s" % [kind, part]), "%s %s has art" % [kind, part])


func test_missing_id_fails_clearly(t) -> void:
	var lib := ArtLibrary.new()
	lib.silent = true
	t.check(lib.texture("building.nope.base") == null, "unknown id gives null")
	t.check(lib.last_error.contains("unknown art id 'building.nope.base'"), "error names the id: " + lib.last_error)
	t.check(not lib.has_entry("building.nope.base") and not lib.has_art("building.nope.base"), "unknown id has no entry")
	t.eq(lib.size("building.nope.base"), Vector2i.ZERO, "unknown size")
	var bad := ArtLibrary.new()
	bad.silent = true
	t.check(not bad.load_manifest("res://assets/processed/no_such.json"), "missing manifest fails")
	t.check(bad.last_error.contains("not found"), "manifest error is clear: " + bad.last_error)


func test_door_pivot_and_frame_tables(t) -> void:
	var lib := ArtLibrary.new()
	var d := lib.door_rect("habitat")
	t.check(d.size.x > 0.0 and d.size.y > 0.0 and d.end.x <= 1.0 and d.end.y <= 1.0, "habitat door rect normalized")
	t.check(lib.door_mode("habitat") in ["split", "rollup"], "door mode")
	t.eq(lib.pivot("building.habitat.base").y, 1.0, "pivot y is the bottom edge")
	t.near(lib.pivot("building.habitat.base").x, d.get_center().x, 0.001, "pivot x is door centre")
	var fr := lib.frame_rect("eva", "walk_side_0")
	t.check(fr.size == Vector2(128, 128), "frame rect is one cell")
	t.check(lib.frame_rect("eva", "no_such_frame") == Rect2(), "unknown frame is empty")
	var anchor: Variant = lib.lamp_anchor("eva", "walk_side_0")
	t.check(anchor is Vector2 and (anchor as Vector2).y < 40.0, "eva lamp anchor in the upper part of the cell")
	t.check(lib.lamp_anchor("jumpsuit", "idle_front") == null, "jumpsuit has no lamp anchor")
