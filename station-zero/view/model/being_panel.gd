class_name BeingPanel
extends RefCounted
## The being inspect panel as a pure function of the world (docs/specs/emotions.md 7.1, revision 4). Text only: no number, no
## bar, no icon. Reads the four whitelisted mood members of a Being (band, why, base, half-life), the world clock,
## relationships.friends_of(id) and the texts and thresholds of data/mood.json. Draws nothing, takes no random number and
## writes nothing; the caller builds the view from the returned strings.

const BAND_EVEN := 2
## Band index (0 heavy .. 4 bright) to the key of text.band; the even band has no sentence.
const BAND_KEYS: Array[String] = ["heavy", "low", "", "light", "bright"]


## One element per template group, in this order: who; spirits (the band sentence with the why appended after one space,
## omitted when the band is even); nature (only when no why sentence is shown); company.
## `band_override` (0 to 4) shows that band instead of the stored one: the caller holds the shown band for hold_s (PanelHold).
static func lines(world: SimWorld, id: int, band_override: int = -1) -> Array:
	var out: Array = []
	var b: Being = _find(world, id)
	if b == null:
		return out
	var cfg: Dictionary = SimData.moods()
	var tx: Dictionary = cfg.text
	var friends: Array = world.relationships.friends_of(id)
	out.append(_fill(str(tx.panel.who), b.name, "").replace("{description}", str(b.persona.description)))
	var why_text := ""
	var band: int = b.mood_band if band_override < 0 else band_override
	if band != BAND_EVEN:
		var sentence := _fill(str(tx.band[BAND_KEYS[band]]), b.name, "")
		why_text = _why_sentence(world, b, band, friends, cfg)
		out.append(sentence if why_text == "" else sentence + " " + why_text)
	if why_text == "":
		var nature := _nature(b, cfg)
		if nature != "":
			out.append(nature)
	out.append(_company(world, b, friends, tx.panel))
	return out


## The numbers of the selection and panel rules (data/mood.json selection), for the view helpers that take a cfg.
static func selection_cfg() -> Dictionary:
	return SimData.moods().selection


## True while the being is in the world.
static func alive(world: SimWorld, id: int) -> bool:
	return _find(world, id) != null


## The band the sim holds for the being now, or -1 when it is gone.
static func wanted_band(world: SimWorld, id: int) -> int:
	var b: Being = _find(world, id)
	return -1 if b == null else b.mood_band


## "{name} has died." for a being no longer in the world (the name from the death record), or "" when none is recorded.
static func died_line(world: SimWorld, id: int) -> String:
	for d: Dictionary in world.stats.deaths_list:
		if int(d.being_id) == id:
			return _fill(str(SimData.moods().text.panel.died), str(d.name), "")
	return ""


static func _fill(template: String, name: String, other: String) -> String:
	return template.replace("{name}", name).replace("{other}", other)


static func _find(world: SimWorld, id: int) -> Being:
	for b in world.beings:
		if b.id == id:
			return b
	return null


static func _holds(friends: Array, other_id: int) -> bool:
	for f in friends:
		if int(f.id) == other_id:
			return true
	return false


## The why sentence, or "" when none shows: the stored sign must equal the sign of the deviation (the band side, the band
## not being even), a friend or close why needs the pair still held, a company why never shows.
static func _why_sentence(world: SimWorld, b: Being, band: int, friends: Array, cfg: Dictionary) -> String:
	var why: Variant = b.mood_why
	if why == null:
		return ""
	var side := -1 if band < BAND_EVEN else 1
	if int(why.sign) != side:
		return ""
	var key := str(why.key)
	var wt: Dictionary = cfg.text.why
	var other := str(why.name)
	var fresh: bool = float(world.t) - float(why.t) < float(cfg.why.fresh_sols) * float(world.clock.sol_h)
	var template := ""
	match key:
		"grief":
			template = wt.grief_new if fresh else wt.grief_still
		"friend":
			if not _holds(friends, int(why.id)):
				return ""
			template = wt.friend if fresh else wt.friend_old
		"close":
			if not _holds(friends, int(why.id)):
				return ""
			template = wt.close if fresh else wt.close_old
		"lapse", "lapse_close":
			template = wt.lapse
		"birth", "birth_parent":
			template = wt.birth
		"hard_sol":
			template = wt.hard
		"pledge":
			template = wt.pledge
		_:
			return ""
	return _fill(template, b.name, other)


## At most one nature sentence, the first match of the ordered list (spec 7.1 line 4).
static func _nature(b: Being, cfg: Dictionary) -> String:
	var nt: Dictionary = cfg.nature
	var tx: Dictionary = cfg.text.nature
	if b.mood_base <= float(nt.base_lo):
		return _fill(str(tx.heavy), b.name, "")
	if b.mood_base >= float(nt.base_hi):
		return _fill(str(tx.bright), b.name, "")
	if b.mood_halflife >= float(nt.slow_halflife):
		return _fill(str(tx.slow), b.name, "")
	if b.mood_halflife <= float(nt.quick_halflife):
		return _fill(str(tx.quick), b.name, "")
	return ""


## K1 when the being holds no friends pair; else the close friend (or the friend) the relationships module picks (strongest tie, lowest id on a tie).
static func _company(world: SimWorld, b: Being, friends: Array, tx: Dictionary) -> String:
	if friends.is_empty():
		return _fill(str(tx.k1), b.name, "")
	var top: Dictionary = world.relationships.top_friend_of(b.id)
	var other: Being = _find(world, int(top.id))
	var oname := other.name if other != null else ""
	return _fill(str(tx.close if bool(top.close) else tx.friend), b.name, oname)
