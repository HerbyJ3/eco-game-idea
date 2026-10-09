extends RefCounted
## Draw layers and the y-sort of layer L6 (spec sprite-view.md 6).
## Entity: {type: "building"|"being", id, base_y, state, built, rect: Rect2 (building footprint), pos: Vector2 (being feet)}.


## "L4" for a being in a tunnel (drawn before buildings), "L6" for everything y-sorted.
static func layer(e: Dictionary) -> String:
	return "L4" if e.type == "being" and e.state == "transit" else "L6"


## Sort key (base_y, kind_order, id): building kind_order 0, being 1. A being inside a site's footprint takes the
## site's base_y, so with kind_order it draws above the site (builders work on it).
static func _key(e: Dictionary, sites: Array) -> Array:
	var y := float(e.base_y)
	if e.type == "being":
		for s in sites:
			if (s.rect as Rect2).has_point(e.pos):
				y = float(s.base_y)
				break
	return [y, 0 if e.type == "building" else 1, int(e.id)]


static func _before(a: Array, b: Array) -> bool:
	for i in a[0].size():
		if a[0][i] != b[0][i]:
			return a[0][i] < b[0][i]
	return false


## The L6 entities in draw order, back to front. Transit beings are not in the list.
static func sorted(entities: Array) -> Array:
	var l6: Array = []
	var sites: Array = []
	for e in entities:
		if layer(e) == "L6":
			l6.append(e)
			if e.type == "building" and float(e.built) < 1.0:
				sites.append(e)
	var keyed: Array = []
	for e in l6:
		keyed.append([_key(e, sites), e])
	keyed.sort_custom(_before)
	var out: Array = []
	for k in keyed:
		out.append(k[1])
	return out
