class_name Persona
extends RefCounted
## Chart -> six traits -> role and a visible two-word description.
## The chart itself is hidden; only these effects are ever shown.

var dims: Array
var signs: Array
var element: Dictionary
var modality: Dictionary
var modality_scale: float
var boost_dims: Dictionary
var placement_table: Dictionary
var trait_offset: float
var trait_scale: float
var roles: Dictionary
var role_order: Array
var role_weights: Dictionary
var adjectives: Dictionary
var never_paired: Array


func _init(cfg: Dictionary = {}, signs_in: Array = []) -> void:
	if cfg.is_empty():
		cfg = SimData.persona()
	if signs_in.is_empty():
		signs_in = SimData.signs()
	signs = signs_in
	dims = cfg.dims
	element = cfg.element
	modality = cfg.modality
	modality_scale = cfg.modality_scale
	boost_dims = cfg.boost_dims
	placement_table = cfg.placements
	trait_offset = cfg.trait_offset
	trait_scale = cfg.trait_scale
	roles = cfg.roles
	role_order = cfg.role_order
	role_weights = cfg.role_weights
	adjectives = cfg.adjectives
	never_paired = cfg.never_paired


## [{sign, weight, inner, outer, drive, curiosity}] for a chart.
func placements(chart: Dictionary) -> Array:
	var out: Array = []
	for p: Dictionary in placement_table[chart.world]:
		var entry := p.duplicate()
		entry["sign"] = int(chart[p.key])
		out.append(entry)
	return out


## Weighted sums before the offset/scale/clamp step.
func raw_traits(chart: Dictionary) -> Dictionary:
	var sum := {}
	for d: String in dims:
		sum[d] = 0.0
	for pl: Dictionary in placements(chart):
		var sg: Dictionary = signs[pl.sign]
		var e: Dictionary = element[sg.element]
		var m: Dictionary = modality[sg.modality]
		for d: String in dims:
			var v: float = float(e.get(d, 0.0)) + float(m.get(d, 0.0)) * modality_scale
			for boost: String in boost_dims:
				if d in boost_dims[boost]:
					v *= float(pl[boost])
			sum[d] += float(pl.weight) * v
	return sum


func traits_from_raw(raw: Dictionary) -> Dictionary:
	var p := {}
	for d: String in dims:
		p[d] = clampf((float(raw[d]) + trait_offset) / trait_scale, 0.0, 1.0)
	return p


func traits(chart: Dictionary) -> Dictionary:
	return traits_from_raw(raw_traits(chart))


## Weighted argmax; ties go to the earlier dimension in role_order.
func role_dim(p: Dictionary) -> String:
	var best: String = role_order[0]
	for d: String in role_order:
		if float(p[d]) * float(role_weights[d]) > float(p[best]) * float(role_weights[best]):
			best = d
	return best


func role_of(p: Dictionary) -> String:
	return roles[role_dim(p)]


func _paired_ok(a: String, b: String) -> bool:
	for pair: Array in never_paired:
		if (a == pair[0] and b == pair[1]) or (a == pair[1] and b == pair[0]):
			return false
	return true


## Top two traits as "X and Y". Stable: equal values keep dims order.
func describe(p: Dictionary) -> String:
	var order: Array = []
	for d: String in dims:
		var i := 0
		while i < order.size() and float(p[order[i]]) >= float(p[d]):
			i += 1
		order.insert(i, d)
	var first: String = order[0]
	var second := ""
	for d: String in order:
		if d != first and _paired_ok(first, d):
			second = d
			break
	return "%s and %s" % [adjectives[first], adjectives[second]]


## Everything the rest of the game may know about a being's personality.
func persona_from(chart: Dictionary) -> Dictionary:
	var p := traits(chart)
	return {"traits": p, "role": role_of(p), "description": describe(p)}
