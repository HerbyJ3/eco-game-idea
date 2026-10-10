extends "res://tests/minds_lib.gd"
## Task 6b, step 3 (tests first, red): the rule voice, the text filter, the source scans and the panel doors. Spec
## docs/specs/ai-minds.md revision 5, section 14 tests 17 (rule voice coverage), 18 (filter table), 19 (source scan of sim/),
## 20 (repository scan), 22 (BeingPanel with minds on and off, view source scan).
##
## The filter is the driver's (`res://minds/filter.gd`); spec 5.9: static `Filter.check(text: String, allowed_names: Array) ->
## Dictionary` with a bool `ok` and, when not ok, a non-empty String `reason`; it reads its limits from data/minds.json and its
## word lists from data/minds_text.json itself. A bare bool is no longer accepted.

const SITUATIONS := ["grief", "lapse", "friend", "close", "birth_parent", "season_turn", "hard", "pledge", "heavy_other", "low",
		"light", "bright", "with_friend", "alone_even", "day_even", "night_even", "even_spring", "even_summer", "even_autumn",
		"even_winter"]
## Revision 5 (5.7): the four seasonal even situations, one per entry of calendar.json `seasons`, in that order.
const SEASONAL := ["even_spring", "even_summer", "even_autumn", "even_winter"]
const NAMED := ["grief", "lapse", "friend", "close", "with_friend", "heavy_other"]
const ALLOWED_PLACEHOLDERS := ["self", "other", "place", "season"]
const CHART_TERMS := ["deimos", "phobos", "chart", "horoscope", "zodiac", "birth sign"]
const PLAYER_TERMS := ["player", "god", "watcher", "hello", "hi there", "greetings", "welcome", "dear"]
## Phrases that would promise an action; that vocabulary lives only in intent.* (spec 5.7).
const PROMISE_PATTERNS := ["i'll", "i will", "going to", "go and", "head to", "heading", "on my way", "let's", "gonna", "off to", "i shall"]


func _voice_api(t) -> bool:
	var missing: Array[String] = []
	for f in ["data/minds.json", "data/minds_text.json", "sim/minds_voice.gd"]:
		if not FileAccess.file_exists("res://" + f):
			missing.append(f)
	var sit: Variant = _mt().get("rule", {}).get("situations", null)
	if not (sit is Dictionary):
		missing.append("minds_text.json rule.situations")
	if not (_mt().get("filter", {}).get("template_forbidden_words", null) is Array):
		missing.append("minds_text.json filter.template_forbidden_words")
	if FileAccess.file_exists("res://sim/minds_voice.gd") and not _has_static(load("res://sim/minds_voice.gd"), "line"):
		missing.append("MindsVoice.line()")
	t.check(missing.is_empty(), "missing API: " + ", ".join(PackedStringArray(missing)))
	return missing.is_empty()


func _values(x: Variant) -> Array:
	var out: Array = []
	if x is Dictionary:
		for k in x:
			out.append_array(_values(x[k]))
	elif x is Array:
		for v in x:
			out.append_array(_values(v))
	elif x != null:
		out.append(str(x))
	return out


func _longest(x: Variant) -> String:
	var best := ""
	for v in _values(x):
		if str(v).length() > best.length():
			best = str(v)
	return best


func _words(s: String) -> PackedStringArray:
	var re := RegEx.create_from_string("[A-Za-z']+")
	var out := PackedStringArray()
	for m in re.search_all(s):
		out.append(m.get_string())
	return out


# ---------------------------------------------------------------- 17. rule voice coverage

func test_t17a_every_situation_has_enough_templates(t) -> void:
	if not _voice_api(t):
		return
	var sit: Dictionary = _mt().rule.situations
	var vmin: int = int(_md().rule.variants_min)
	var vplain: int = int(_md().rule.variants_min_plain)
	for name in SITUATIONS:
		t.check(sit.has(name), "situation `%s` exists" % name)
		if not sit.has(name):
			continue
		var need: int = vplain if name in ["day_even", "night_even"] else vmin
		t.check((sit[name] as Array).size() >= need, "`%s` has at least %d templates (%d)" % [name, need, (sit[name] as Array).size()])
	if sit.has("season_turn"):
		t.eq((sit.season_turn as Array).size(), 4, "season_turn has one line per season (4)")
	# Revision 5 decision 6: the four seasonal situations have fixed names, one per entry of calendar.json `seasons`.
	t.eq(SimData.calendar().seasons.size(), SEASONAL.size(), "calendar.json has four seasons, one even_<season> situation each")
	for name in SEASONAL:
		t.check(sit.has(name) and (sit[name] as Array).size() >= vmin, "`%s` exists with at least rule.variants_min (%d) lines" % [name, vmin])


func test_t17b_template_content_rules_on_the_raw_text(t) -> void:
	if not _voice_api(t):
		return
	var sit: Dictionary = _mt().rule.situations
	var signs: Array[String] = []
	for s in SimData.signs():
		signs.append(str(s.name).to_lower())
	var brace := RegEx.create_from_string("\\{([^}]*)\\}")
	var caps := RegEx.create_from_string("\\b[A-Z]{%d,}\\b" % int(_md().filter.caps_min_len))
	var promise_leads: Array[String] = []
	for kind in _mt().get("intent", {}):
		for tpl in _mt().intent[kind]:
			var lead := str(tpl).split("{")[0].strip_edges().to_lower()
			if lead.length() >= 8:
				promise_leads.append(lead)
	var n := 0
	for name in sit:
		for raw in sit[name]:
			var tpl := str(raw)
			n += 1
			var tag := "%s: %s" % [name, tpl]
			for m in brace.search_all(tpl):
				t.check(m.get_string(1) in ALLOWED_PLACEHOLDERS, "%s: placeholder {%s} is allowed" % [tag, m.get_string(1)])
			var digit := RegEx.create_from_string("\\d").search(tpl)
			t.check(digit == null, "%s: no digit in the raw template" % tag)
			t.check(not tpl.contains("!"), "%s: no exclamation mark" % tag)
			t.check(caps.search(brace.sub(tpl, "", true)) == null, "%s: no all-capital word" % tag)
			var ascii := true
			for i in tpl.length():
				var c := tpl.unicode_at(i)
				ascii = ascii and c >= 32 and c <= 126
			t.check(ascii, "%s: plain printable ASCII" % tag)
			var low := tpl.to_lower()
			for s in signs:
				t.check(not low.contains(s), "%s: no sign name `%s`" % [tag, s])
			for term in CHART_TERMS:
				t.check(not low.contains(term), "%s: no chart term `%s`" % [tag, term])
			var ws := _words(low)
			# Revision 5 decision 7: whole-word, case-insensitive loop over the data list (replaces the vague trait-word rule).
			for fw in _mt().filter.template_forbidden_words:
				t.check(not (str(fw).to_lower() in ws), "%s: not the forbidden word `%s`" % [tag, fw])
			for term in PLAYER_TERMS:
				if " " in term:
					t.check(not low.contains(term), "%s: no player term `%s`" % [tag, term])
				else:
					t.check(not (term in ws), "%s: no player term `%s`" % [tag, term])
			for p in PROMISE_PATTERNS:
				t.check(not low.contains(p), "%s: promises no action (`%s`)" % [tag, p])
			for lead in promise_leads:
				t.check(not low.contains(lead), "%s: does not use the intent vocabulary `%s`" % [tag, lead])
			var rendered := tpl
			for ph in ALLOWED_PLACEHOLDERS:
				var src: Variant = _mt().get("words", {}).get("place" if ph == "place" else ("season" if ph == "season" else ph), null)
				var fill := "Zzzzzz-99"
				if ph == "place" or ph == "season":
					fill = _longest(src) if src != null else "northern summer"
				rendered = rendered.replace("{%s}" % ph, fill)
			t.check(rendered.length() <= int(_md().say.max_chars), "%s: rendered at most say.max_chars (%d)" % [tag, rendered.length()])
			if name in NAMED:
				t.check(tpl.contains("{other}"), "%s: a named-person situation uses {other}" % tag)
	t.check(n >= 40, "at least 40 templates were examined (%d); the writing budget is about 60" % n)


func test_t17c_rendered_lines_for_generated_facts(t) -> void:
	if not _voice_api(t) or not _api(t):
		return
	var voice = load("res://sim/minds_voice.gd")
	var count := 0
	var bad: Array[String] = []
	var seed_i := 1
	while count < 200 and seed_i < 40:
		var w = SimWorld.new(seed_i, {"minds_mode": "rules"})
		for b in w.beings:
			var f: Dictionary = w.minds.facts_for(w, b)
			var line: String = voice.line(f)
			var again: String = voice.line(f)
			count += 1
			if line != again:
				bad.append("impure: " + line)
			if line == "" or line.contains("{") or line.contains("}") or line.length() > int(_md().say.max_chars):
				bad.append("shape: " + line)
		seed_i += 1
	t.check(count >= 200, "200 facts were rendered (%d)" % count)
	t.check(bad.is_empty(), "every line is non-empty, brace-free, within say.max_chars and pure; first problem: %s" % (bad[0] if not bad.is_empty() else ""))
	_end(t)


func test_t17d_a_being_never_gets_the_same_line_twice_in_a_row(t) -> void:
	if not _api(t):
		return
	var c := _cast("rules", 2, false)
	var w = c.w
	var last := ""
	var repeats := 0
	var lines := 0
	var seen_n: int = 0
	var guard := 0
	while lines < 14 and guard < 400000:
		_mini(w)
		guard += 1
		if int(c.s.mind_slot_n) != seen_n:
			seen_n = int(c.s.mind_slot_n)
			var txt := str(w.minds.says.get(int(c.s.id), {}).get("text", ""))
			if txt != "":
				lines += 1
				if txt == last:
					repeats += 1
				last = txt
	t.check(lines >= 14, "fourteen consecutive slots produced lines (%d)" % lines)
	t.eq(repeats, 0, "no two consecutive lines of one being are the same (last-said guard)")
	_end(t)


# ---------------------------------------------------------------- 18. the filter table

func _filter_script() -> Variant:
	return _script("res://minds/filter.gd")


## Filter.check returns {ok: bool, reason: String when not ok} (5.9). Returns null for a result that breaks that shape.
func _res(f: Variant, text: String, allowed: Array) -> Variant:
	var r: Variant = f.check(text, allowed)
	if not (r is Dictionary) or not (r.get("ok", null) is bool):
		return null
	return r


func _ok(f: Variant, text: String, allowed: Array) -> bool:
	var r: Variant = _res(f, text, allowed)
	return r != null and bool(r.ok)


func test_t18_filter_table(t) -> void:
	var f: Variant = _filter_script()
	t.check(f != null and _has_static(f, "check"), "missing API: minds/filter.gd with a static check(text, allowed_names)")
	if f == null or not _has_static(f, "check") or not FileAccess.file_exists("res://data/minds.json"):
		return
	var maxc: int = int(_md().say.max_chars)
	var caps: int = int(_md().filter.caps_min_len)
	var dax := ["Dax-8"]
	var cases := [
		["Feeling steady today.", [], true, "plain good remark"],
		["A quiet evening in here.", [], true, "quiet good remark"],
		["Dax-8 has been kind to me.", dax, true, "an allowed Name-N (digits inside it pass)"],
		["Tired, but Dax-8 and Vana-3 make it easier.", ["Dax-8", "Vana-3"], true, "two allowed names"],
		["It is a slow week.", [], true, "good remark"],
		["x".repeat(maxc), [], true, "exactly say.max_chars long"],
		["x".repeat(maxc + 1), [], false, "one over say.max_chars"],
		["", [], false, "empty"],
		["   ", dax, false, "blank"],
		["Fine\nthen.", [], false, "newline"],
		["Fine\tthen.", [], false, "tab (control character)"],
		["Fine" + char(7) + " then.", [], false, "bell (control character)"],
		["Feeling fine " + char(0x1F600), [], false, "emoji"],
		["Caf" + char(0xE9) + " nights are quiet.", [], false, "a character outside plain printable ASCII"],
		["<b>Fine</b> today.", [], false, "angle brackets"],
		["{self} is fine.", [], false, "braces"],
		["[ok] fine today.", [], false, "square brackets"],
		["`fine` today.", [], false, "backtick"],
		["*fine* today.", [], false, "asterisk"],
		["Fine today!", [], false, "exclamation mark"],
		["I am " + "T".repeat(caps) + " today.", [], false, "an all-capital word of filter.caps_min_len letters"],
		["I am " + "T".repeat(caps - 1) + " today.", [], true, "an all-capital word one letter shorter passes"],
		["The Drift is strong tonight.", [], false, "a sign name"],
		["Deimos is bright tonight.", [], false, "Deimos"],
		["Phobos rises early.", [], false, "Phobos"],
		["My chart says so.", [], false, "chart"],
		["The horoscope was kind.", [], false, "horoscope"],
		["The zodiac turns.", [], false, "zodiac"],
		["My birth sign is quiet.", [], false, "birth sign"],
		["Hello there, friend.", [], false, "a greeting (hello)"],
		["Greetings from the hab.", [], false, "a greeting (greetings)"],
		["hi there, all.", [], false, "a greeting (hi there)"],
		["Dear all, it is cold.", [], false, "a player-address term (dear)"],
		["Welcome to the colony.", [], false, "a player-address term (welcome)"],
		["The player will see.", [], false, "a player-address term (player)"],
		["The watcher is near.", [], false, "a player-address term (watcher)"],
		["God help us.", [], false, "a player-address term (god)"],
		["I counted 3 lights tonight.", [], false, "a stray digit"],
		["Dax-88 is kind.", dax, false, "a digit glued to an allowed name"],
		["Zed-40 looks tired.", dax, false, "a disallowed Name-N"],
		["Dax-8 is here.", [], false, "a Name-N when the allowed set is empty"],
		["A good evening.", [], true, "`good` is not the word god"],
	]
	t.check(cases.size() >= 30, "at least 30 cases (%d)" % cases.size())
	for c in cases:
		var r: Variant = _res(f, str(c[0]), c[1])
		t.check(r != null, "filter returns a Dictionary with a bool ok: %s" % str(c[3]))
		if r == null:
			continue
		t.eq(bool(r.ok), bool(c[2]), "filter: %s" % str(c[3]))
		if not bool(c[2]):
			t.check(r.get("reason", null) is String and str(r.reason) != "", "filter: a rejection carries a reason (%s)" % str(c[3]))


# ---------------------------------------------------------------- 19. source scan of sim/

func _gd_files(dir: String) -> Array[String]:
	var out: Array[String] = []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		out.append_array(_gd_files(dir.path_join(d)))
	return out


func test_t19_sim_has_no_network_key_or_provider_names(t) -> void:
	t.check(FileAccess.file_exists("res://sim/minds.gd"), "missing API: sim/minds.gd (the scan must include it)")
	t.check(FileAccess.file_exists("res://sim/minds_voice.gd"), "missing API: sim/minds_voice.gd (the scan must include it)")
	var tokens := ["HTTPRequest", "HTTPClient", "StreamPeer", "PacketPeer", "OS.get_environment", "https://", "http://", "Authorization",
			"api_key", "user://"]
	var names := ["anthropic", "openai", "claude", "gpt-", "gemini", "sonnet", "haiku", "opus", "mistral", "llama"]
	var allowed_minds := ["res://sim/minds.gd", "res://sim/minds_voice.gd", "res://sim/sim_data.gd", "res://sim/world.gd", "res://sim/being.gd"]
	var files := _gd_files("res://sim")
	t.check(files.size() >= 15, "sim/ scripts were found (%d)" % files.size())
	for f in files:
		var src := FileAccess.get_file_as_string(f)
		var low := src.to_lower()
		for tok in tokens:
			t.check(not src.contains(tok), "%s does not mention %s" % [f, tok])
		for n in names:
			t.check(not low.contains(n), "%s does not name a provider or model (%s)" % [f, n])
		if not (f in allowed_minds):
			t.check(not low.contains("minds"), "%s does not mention minds (only minds.gd, minds_voice.gd, sim_data.gd, world.gd, being.gd may)" % f)


# ---------------------------------------------------------------- 20. repository scan

func _text_files(dir: String, out: Array[String]) -> void:
	for f in DirAccess.get_files_at(dir):
		var ext := f.get_extension().to_lower()
		if ext in ["gd", "json", "md", "cfg", "txt", "tscn", "example", "sh", "py", "tres", "jsonl", "yml", "yaml", "toml", "env", "ini"]:
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		if d in [".godot", "assets", ".git", "node_modules"]:
			continue
		_text_files(dir.path_join(d), out)


func test_t20_repository_has_no_key_shaped_strings_and_ignores_user_files(t) -> void:
	var pats: Array[RegEx] = []
	for p in ["(?<![A-Za-z0-9])sk-[A-Za-z0-9_-]{20,}", "AIza[0-9A-Za-z_-]{30,}", "(?i)bearer\\s+[A-Za-z0-9._-]{20,}", "ghp_[A-Za-z0-9]{30,}", "xox[bp]-[A-Za-z0-9-]{10,}"]:
		pats.append(RegEx.create_from_string(p))
	var files: Array[String] = []
	_text_files("res://", files)
	t.check(files.size() > 100, "text files were found (%d)" % files.size())
	var hits: Array[String] = []
	for f in files:
		var src := FileAccess.get_file_as_string(f)
		for re in pats:
			if re.search(src) != null:
				hits.append(f)
	t.check(hits.is_empty(), "no key-shaped string in the repository; first: %s" % (hits[0] if not hits.is_empty() else ""))
	var ignore := FileAccess.get_file_as_string("res://.gitignore")
	var root_ignore := FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://").path_join("../.gitignore"))
	var both := ignore + "\n" + root_ignore
	t.check(both.contains("*.jsonl"), ".gitignore covers *.jsonl ledgers")
	t.check(both.contains("tests/fixtures"), ".gitignore names tests/fixtures/ as the one place ledgers may be committed")
	t.check(both.contains("minds.cfg") and both.contains("minds_meter.json"), ".gitignore covers the user files minds.cfg and minds_meter.json")
	t.check(FileAccess.file_exists("res://docs/minds-config.example"), "docs/minds-config.example exists (the documented example, no secret)")


# ---------------------------------------------------------------- 22. BeingPanel and the view scan

func test_t22a_panel_lines_are_byte_equal_with_minds_on_and_off(t) -> void:
	if not _api(t):
		return
	var panel = load("res://view/model/being_panel.gd")
	var worlds := []
	for mode in ["off", "llm"]:
		var c := _cast(mode, 4)
		_why(c.s, "friend", c.w.t, c.f1.id, "Dax-8")
		worlds.append(c)
	_mini(worlds[0].w, 900)
	_mini(worlds[1].w, 900)
	var d = _decide(worlds[1].w, worlds[1].s, "stay", "Quiet evening.")
	var a: Array = []
	var b: Array = []
	for who in ["s", "f1", "f2", "x"]:
		a.append(panel.lines(worlds[0].w, worlds[0][who].id))
		b.append(panel.lines(worlds[1].w, worlds[1][who].id))
	t.eq(JSON.stringify(a), JSON.stringify(b), "BeingPanel.lines is byte-equal with minds on (a bias and a line live) and off")
	_end(t)


func test_t22b_voice_and_intent_doors(t) -> void:
	if not _api(t):
		return
	var panel = load("res://view/model/being_panel.gd")
	t.check(_has_static(panel, "voice") and _has_static(panel, "intent"), "BeingPanel has voice() and intent()")
	if not (_has_static(panel, "voice") and _has_static(panel, "intent")):
		_end(t)
		return
	var c := _cast("llm", 4)
	var w = c.w
	t.eq(panel.voice(w, int(c.s.id)), "", "voice() is empty before any line exists")
	t.eq(panel.intent(w, int(c.s.id)), "", "intent() is empty with no bias")
	_decide(w, c.s, "visit:%d" % c.f1.id, "Quiet evening.")
	var v: String = panel.voice(w, int(c.s.id))
	t.check(v != "" and v.length() <= int(_md().say.total_max_chars), "voice() returns the current line, at most say.total_max_chars")
	var clause: String = panel.intent(w, int(c.s.id))
	var expect := str(_mt().intent_clause.visit).replace("{other}", "Dax-8")
	t.eq(clause, expect, "intent() returns the visit clause naming the friend")
	var stripped := RegEx.create_from_string("[A-Za-z]+-\\d+").sub(clause, "", true)
	t.check(RegEx.create_from_string("\\d").search(stripped) == null, "the clause carries no number outside a name")
	for word in ["model", "ai ", "llm", "claude", "assistant", "provider"]:
		t.check(not clause.to_lower().contains(word), "the clause never names a model (`%s`)" % word)
	_end(t)


func test_t22c_view_source_reads_only_the_bias_door(t) -> void:
	var files := _gd_files("res://view")
	t.check(files.size() >= 10, "view scripts were found (%d)" % files.size())
	var forbidden := ["ledger", "inbox", "outbox", "mind_bias", "provider", "pending_open", "last_visit_t"]
	var door := 0
	var mentions := RegEx.create_from_string("(?i)minds\\.(\\w+)")
	for f in files:
		var src := FileAccess.get_file_as_string(f)
		var low := src.to_lower()
		for w in forbidden:
			t.check(not low.contains(w), "%s does not mention %s" % [f, w])
		for m in mentions.search_all(src):
			var member := m.get_string(1)
			t.check(member in ["bias_view", "says"], "%s reads minds.%s (only the bias_view door and the line text are allowed)" % [f, member])
			if member == "bias_view":
				door += 1
	t.check(door >= 1, "BeingPanel reads the bias through the minds.bias_view door (found %d use)" % door)
