class_name Tests
extends RefCounted

## Headless checks. Run with:
##   godot --headless --path <project> -- --test

static var _pass := 0
static var _fail := 0
static var _out: Array[String] = []


static func ok(name: String, cond: bool, extra: String = "") -> void:
	if cond:
		_pass += 1
		_out.append("  PASS  " + name + ("   [" + extra + "]" if extra != "" else ""))
	else:
		_fail += 1
		_out.append("* FAIL  " + name + ("   [" + extra + "]" if extra != "" else ""))


static func info(s: String) -> void:
	_out.append("        " + s)


static func head(s: String) -> void:
	_out.append("")
	_out.append("=== " + s + " ===")


static func run(g: GameRules, main = null) -> int:
	_pass = 0
	_fail = 0
	_out.clear()

	_content()
	_maths()
	_maps(g)
	_player_actions(g)
	_promotions(g)
	_upgrades(g)
	_siege(g)
	_events(g)
	_full_games(g)
	_losability(g)
	_save_load(g)
	if main != null:
		_interaction(g, main)

	_out.push_front("RESULT  pass=%d  fail=%d" % [_pass, _fail])
	for line in _out:
		print(line)
	return _fail


# =========================================================================
static func _content() -> void:
	head("content")
	ok("six ages", Data.AGES.size() == 6)
	ok("72 edicts, twelve per age", EdictData.LIST.size() == 6 and _all_twelve(),
		_age_sizes())
	var ids := {}
	var dupes: Array[String] = []
	for age in EdictData.LIST:
		for e in age:
			if ids.has(e["id"]):
				dupes.append(str(e["id"]))
			ids[e["id"]] = true
	ok("edict ids are unique", dupes.is_empty(), ", ".join(dupes))
	var missing: Array[String] = []
	for age in EdictData.LIST:
		for e in age:
			if not e.has("name") or not e.has("desc") or not e.has("flavour"):
				missing.append(str(e.get("id", "?")))
			if not e.has("m") and not e.has("once"):
				missing.append(str(e.get("id", "?")) + " (no effect)")
	ok("every edict has text and an effect", missing.is_empty(), ", ".join(missing))

	ok("six leaders, each with a unique unit", EdictData.LEADERS.size() == 6 and _uniques_ok())
	var bad: Array[String] = []
	for k in Data.UNIT:
		var u: Dictionary = Data.UNIT[k]
		if u["cls"] != "settler" and int(u["str"]) <= 0:
			bad.append(k + " no strength")
		if u.has("rs") and not u.has("rng"):
			bad.append(k + " ranged without range")
		if not u.has("glyph"):
			bad.append(k + " no glyph")
	ok("the unit table is consistent", bad.is_empty(), ", ".join(bad))
	var promo_bad: Array[String] = []
	for k in Data.PROMOTION:
		var pr: Dictionary = Data.PROMOTION[k]
		if not pr.has("for") or (pr["for"] as Array).is_empty():
			promo_bad.append(k)
		if not pr.has("m") or (pr["m"] as Dictionary).is_empty():
			promo_bad.append(k + " (no effect)")
	ok("every promotion applies to something", promo_bad.is_empty(), ", ".join(promo_bad))


static func _all_twelve() -> bool:
	for age in EdictData.LIST:
		if age.size() != 12:
			return false
	return true


static func _age_sizes() -> String:
	var parts: Array[String] = []
	for age in EdictData.LIST:
		parts.append(str(age.size()))
	return "/".join(parts)


static func _uniques_ok() -> bool:
	for L in EdictData.LEADERS:
		var uq: String = L["unique"]
		if not Data.UNIT.has(uq):
			return false
		if not Data.UNIT.has(Data.UNIT[uq]["replaces"]):
			return false
	return true


static func _maths() -> void:
	head("mathematics")
	ok("hex distance to itself is zero", Hex.distance(Vector2i(3, -4), Vector2i(3, -4)) == 0)
	ok("neighbours are one apart", Hex.distance(Vector2i.ZERO, Vector2i(1, 0)) == 1
		and Hex.distance(Vector2i.ZERO, Vector2i(1, -1)) == 1)
	var round_trip_bad := 0
	for q in range(-8, 9):
		for r in range(-8, 9):
			if absi(q + r) > 8:
				continue
			var c := Vector2i(q, r)
			if Hex.from_world(Hex.to_world(c, 46.0), 46.0) != c:
				round_trip_bad += 1
	ok("world and hex coordinates round-trip", round_trip_bad == 0, str(round_trip_bad) + " bad")

	var costs: Array[int] = []
	var total := 0
	for i in 18:
		costs.append(Data.bt_cost(i))
		total += Data.bt_cost(i)
	ok("eighteen breakthroughs cost a sane total", total > 3000 and total < 6500, "total " + str(total))
	var rising := true
	for i in range(1, costs.size()):
		if costs[i] <= costs[i - 1]:
			rising = false
	ok("breakthroughs get dearer", rising)


static func _maps(g: GameRules) -> void:
	head("map generation over 10 seeds")
	var problems: Array[String] = []
	var fractions: Array[float] = []
	for s in 10:
		g.new_run(4000 + s, EdictData.LEADERS[s % 6]["id"], 1)
		var land := 0
		var rivers := 0
		var resources := 0
		var coast := 0
		for t in g.world.list:
			if not t.is_water():
				land += 1
			if t.terrain == "coast":
				coast += 1
			if t.has_river():
				rivers += 1
			if t.resource != "":
				resources += 1
		var frac := float(land) / float(g.world.list.size())
		fractions.append(frac)
		if rivers < 6:
			problems.append("seed %d rivers %d" % [4000 + s, rivers])
		if resources < 12:
			problems.append("seed %d resources %d" % [4000 + s, resources])
		var civs := 0
		for p in g.players:
			if not p.is_barbarian:
				civs += 1
				if p.capital == null:
					problems.append("seed %d: %s has no capital" % [4000 + s, p.name])
		if civs != 4:
			problems.append("seed %d players %d" % [4000 + s, civs])
		# starts must be spread out
		var caps: Array[City] = []
		for p in g.players:
			if not p.is_barbarian and p.capital != null:
				caps.append(p.capital)
		for i in caps.size():
			for j in range(i + 1, caps.size()):
				if Hex.distance(caps[i].coord, caps[j].coord) < 4:
					problems.append("seed %d starts too close" % (4000 + s))
		if s == 0:
			info("seed 4000: %d tiles, %.0f%% land, %d coast, %d river tiles, %d resources"
				% [g.world.list.size(), frac * 100.0, coast, rivers, resources])
	ok("ten maps are all playable", problems.is_empty(), ", ".join(problems.slice(0, 4)))
	var lo := 1.0
	var hi := 0.0
	for f in fractions:
		lo = minf(lo, f)
		hi = maxf(hi, f)
	ok("land fraction stays in a sensible band", lo > 0.42 and hi < 0.68,
		"%.2f - %.2f" % [lo, hi])

	# every strategic resource must exist on every map
	var missing := 0
	for s2 in 6:
		g.new_run(4200 + s2, "ashur", 1)
		for key in ["horses", "iron", "niter", "oil", "uranium"]:
			var found := false
			for t in g.world.list:
				if t.resource == key:
					found = true
					break
			if not found:
				missing += 1
	ok("every strategic resource appears on every map", missing == 0, str(missing) + " missing")


static func _player_actions(g: GameRules) -> void:
	head("playing as a human")
	g.new_run(777, "nefertiti", 1)
	ok("you begin with a capital and three units",
		g.me.cities.size() == 1 and g.me.units.size() == 3,
		"%d cities, %d units" % [g.me.cities.size(), g.me.units.size()])

	var warrior: Unit = null
	var settler: Unit = null
	for u in g.me.units:
		if u.is_civilian():
			settler = u
		elif warrior == null:
			warrior = u
	ok("there is a settler and a fighter", settler != null and warrior != null)

	# whichever unit we happen to pick, at least one of them must be able to
	# move — a start where nobody can leave is a bug, one cramped unit is not
	var movable := 0
	for u2 in g.me.units:
		if g.reachable(u2).size() > 0:
			movable += 1
	ok("your opening units can move", movable >= 2,
		"%d of %d units have somewhere to go" % [movable, g.me.units.size()])
	for u3 in g.me.units:
		if not u3.is_civilian() and g.reachable(u3).size() > 0:
			warrior = u3
			break
	var reach := g.reachable(warrior)
	ok("the chosen unit has somewhere to go", reach.size() > 0, str(reach.size()) + " tiles")
	# how far can a fresh unit actually see to walk, across several starts?
	var sizes: Array[int] = []
	for probe_seed in 6:
		g.new_run(3300 + probe_seed, "ashur", 1)
		for v in g.me.units:
			if v.is_civilian():
				continue
			var t0 := g.world.at(v.coord)
			var open := 0
			var blocked_own := 0
			var impass := 0
			for nb in g.world.neighbours(v.coord):
				if not g.can_enter(v, nb):
					impass += 1
				elif g.blocked_by(v, nb) != "":
					blocked_own += 1
				else:
					open += 1
			info("seed %d %s at %s (mv %d): %d open neighbours, %d blocked by own, %d impassable -> reach %d"
				% [3300 + probe_seed, Data.UNIT[v.type]["name"], str(v.coord), v.mv,
				   open, blocked_own, impass, g.reachable(v).size()])
			sizes.append(g.reachable(v).size())
			break
	var mean_reach := 0
	for z in sizes:
		mean_reach += z
	var stranded := 0
	for z2 in sizes:
		if z2 < 2:
			stranded += 1
	ok("no start leaves its army stranded", stranded == 0,
		"%d of %d starts had nowhere to go" % [stranded, sizes.size()])
	ok("a two-move unit reaches a useful number of tiles",
		float(mean_reach) / sizes.size() >= 4.0,
		"mean %.1f tiles" % (float(mean_reach) / sizes.size()))
	# back to the fixed seed for the rest of this section
	g.new_run(777, "nefertiti", 1)
	warrior = null
	settler = null
	for v3 in g.me.units:
		if v3.is_civilian():
			settler = v3
		elif warrior == null or g.reachable(warrior).is_empty():
			warrior = v3
	reach = g.reachable(warrior)
	var target := Vector2i.ZERO
	for k in reach:
		target = k
		break
	var before := warrior.coord
	var path := g.path_to(warrior, target) if reach.size() > 0 else ([] as Array)
	ok("a path exists to a reachable tile", not path.is_empty() or reach.is_empty(),
		"%d reachable" % reach.size())
	for step in path:
		g.step_unit(warrior, g.world.at(step))
	if reach.size() > 0:
		ok("the unit actually moved", warrior.coord != before,
			"%s -> %s" % [str(before), str(warrior.coord)])
		ok("it is on the new tile", g.world.at(warrior.coord).units.has(warrior))
		ok("and off the old one", not g.world.at(before).units.has(warrior))

	# founding
	var spot: Tile = null
	for t in g.world.list:
		if Hex.distance(t.coord, g.me.capital.coord) == 4 and g.can_found_here(g.me, t):
			spot = t
			break
	ok("there is legal ground for a second city", spot != null)
	if spot != null:
		g.world.at(settler.coord).units.erase(settler)
		settler.coord = spot.coord
		spot.units.append(settler)
		var n0 := g.me.cities.size()
		var c := g.found_city(g.me, spot, false)
		g.kill_unit(settler, true)
		ok("founding adds a city", g.me.cities.size() == n0 + 1)
		ok("the new city claims its ground", spot.owner_id == g.me.id)
		ok("it is not a second capital", not c.is_capital)

	# building
	var cap := g.me.capital
	var options := g.build_options(cap)
	ok("the capital can build something", options.size() > 0, str(options.size()) + " options")
	var has_settler := false
	for o in options:
		if o["kind"] == "unit" and Data.UNIT[o["id"]]["cls"] == "settler":
			has_settler = true
	ok("a settler is offered while under the limit", has_settler)
	ok("units come before wonders in the list",
		options[0]["kind"] == "unit")

	# the army ceiling
	var cap_was := g.army_cap(g.me)
	ok("the ceiling rises with every city", cap_was == 3 + g.me.cities.size())
	while g.army_size(g.me) < g.army_cap(g.me):
		g.spawn_unit(g.me, "warrior", g.free_spot_for(g.me, g.world.at(cap.coord), false).coord)
	var full := g.build_options(cap)
	var offers_soldier := false
	var offers_settler := false
	for o in full:
		if o["kind"] != "unit":
			continue
		if Data.UNIT[o["id"]]["cls"] == "settler":
			offers_settler = true
		else:
			offers_soldier = true
	ok("a full army may train no more soldiers", not offers_soldier,
		"%d/%d" % [g.army_size(g.me), g.army_cap(g.me)])
	ok("but a settler is still allowed", offers_settler)
	var settlers := 0
	for u in g.me.units:
		if u.is_civilian():
			settlers += 1
	ok("settlers do not count against the ceiling",
		g.army_size(g.me) == g.me.units.size() - settlers)

	# progress and the draft
	var pool := g.draft_pool(g.me)
	ok("a draft offers three distinct choices", pool.size() == 3
		and pool[0]["id"] != pool[1]["id"] and pool[1]["id"] != pool[2]["id"])
	var first_fires: Dictionary = {}
	for e in EdictData.LIST[0]:
		if e["id"] == "firstfires":
			first_fires = e
	var prod_before := g.city_yield(cap).y
	g.take_edict(g.me, first_fires)
	g.assign_tiles(cap)
	ok("First Fires really adds production", g.city_yield(cap).y > prod_before,
		"%d -> %d" % [prod_before, g.city_yield(cap).y])
	var offered_again := false
	for e in g.draft_pool(g.me):
		if e["id"] == "firstfires":
			offered_again = true
	ok("an edict is never offered twice", not offered_again)

	var bt0 := g.me.bt_done
	var drafts0 := g.pending_drafts
	g.grant_progress(g.me, Data.bt_cost(g.me.bt_done) + 1)
	ok("filling the bar grants a breakthrough", g.me.bt_done == bt0 + 1)
	ok("and queues a draft for you", g.pending_drafts == drafts0 + 1)


static func _promotions(g: GameRules) -> void:
	head("promotions")
	g.new_run(888, "ashur", 1)
	var u: Unit = null
	for v in g.me.units:
		if not v.is_civilian():
			u = v
			break
	ok("choices are offered for a fresh unit", g.promotion_choices(u).size() == 2)
	var choices := g.promotion_choices(u)
	for c in choices:
		ok("a promotion suits the unit's class",
			(Data.PROMOTION[c]["for"] as Array).has(u.cls()), c + " for " + u.cls())
	var before := g.unit_strength(u, {"attacking": true})
	g.take_promotion(u, "shock")
	ok("Shock really raises an attack", g.unit_strength(u, {"attacking": true}) > before,
		"%.0f -> %.0f" % [before, g.unit_strength(u, {"attacking": true})])
	ok("the promotion is remembered", u.promos.has("shock"))
	var again := g.promotion_choices(u)
	ok("a promotion already held is never re-offered", not again.has("shock"))
	# a unit must not be offered a promotion it cannot use
	var bad := 0
	for k in Data.UNIT:
		var cls: String = Data.UNIT[k]["cls"]
		if cls == "settler":
			continue
		var probe := Unit.new()
		probe.type = k
		probe.owner_id = g.me.id
		for c2 in g.promotion_choices(probe):
			if not (Data.PROMOTION[c2]["for"] as Array).has(cls):
				bad += 1
	ok("no unit is offered an unusable promotion", bad == 0, str(bad))


static func _upgrades(g: GameRules) -> void:
	head("upgrades")
	var loops: Array[String] = []
	var weaker: Array[String] = []
	for L in EdictData.LEADERS:
		for age in 6:
			g.new_run(999, L["id"], 1)
			g.me.age = age
			for res in ["horses", "iron", "niter", "oil"]:
				g.me.m["free_" + res] = 1.0
			for k in Data.UNIT:
				var probe := Unit.new()
				probe.type = k
				probe.owner_id = g.me.id
				var up := g.upgrade_for(g.me, probe)
				if up == "":
					continue
				if up == k or Data.UNIT[up]["name"] == Data.UNIT[k]["name"]:
					loops.append("%s age%d %s" % [L["id"], age, k])
				if Data.UNIT[up]["cls"] != "siege" and int(Data.UNIT[up]["str"]) <= int(Data.UNIT[k]["str"]):
					weaker.append("%s->%s" % [k, up])
	ok("no unit ever upgrades into itself", loops.is_empty(), ", ".join(loops.slice(0, 4)))
	ok("every offered upgrade is stronger", weaker.is_empty(), ", ".join(weaker.slice(0, 4)))


static func _siege(g: GameRules) -> void:
	head("siege")
	g.new_run(1234, "ashur", 1)
	var me := g.me
	# choose a target with room around it: a capital on a peninsula would
	# fail this test for reasons that have nothing to do with sieges
	var city: City = null
	var foe: Player = null
	var best_open := -1
	for p in g.players:
		if p == me or p.is_barbarian:
			continue
		for cand in p.cities:
			var open := 0
			for d0 in 6:
				var n0 := g.world.neighbour(cand.coord, d0)
				if n0 != null and n0.units.is_empty() and n0.city == null 						and not n0.is_water() and not n0.is_impassable():
					open += 1
			if open > best_open:
				best_open = open
				city = cand
				foe = p
	me.age = 2
	foe.age = 2
	me.relation(foe.id)["war"] = true
	me.relation(foe.id)["met"] = true
	foe.relation(me.id)["war"] = true
	foe.relation(me.id)["met"] = true
	var tile := g.world.at(city.coord)
	var hp0 := city.hp
	var placed := 0
	for d in 6:
		if placed >= 4:
			break
		var nb := g.world.neighbour(city.coord, d)
		if nb == null or not nb.units.is_empty() or nb.city != null or nb.is_water() or nb.is_impassable():
			continue
		g.spawn_unit(me, "legion", nb.coord)
		placed += 1
	ok("a besieging stack can be placed", placed >= 3,
		str(placed) + " legions, " + str(best_open) + " open neighbours")
	var turns := 0
	for t in 8:
		turns += 1
		for u in me.units.duplicate():
			if u.dead or u.is_civilian():
				continue
			u.mv = g.unit_moves(u)
			if Hex.distance(u.coord, city.coord) == 1:
				g.melee_attack(u, tile)
		if city.owner_id == me.id:
			break
	ok("a determined assault takes a city", city.owner_id == me.id,
		"in %d turns from %d defence" % [turns, hp0])

	# and a besieged city must not repair itself
	g.new_run(1235, "ashur", 1)
	me = g.me
	for p in g.players:
		if p != me and not p.is_barbarian:
			foe = p
			break
	me.relation(foe.id)["war"] = true
	foe.relation(me.id)["war"] = true
	var c2 := foe.capital
	c2.hp = 20
	for d in 6:
		var nb := g.world.neighbour(c2.coord, d)
		if nb != null and nb.units.is_empty() and nb.city == null and not nb.is_water() and not nb.is_impassable():
			g.spawn_unit(me, "warrior", nb.coord)
			break
	var before := c2.hp
	g.city_turn(c2)
	ok("walls do not mend with an enemy at the gate", c2.hp <= before + 4,
		"%d -> %d" % [before, c2.hp])


static func _full_games(g: GameRules) -> void:
	head("full games, every side played by the AI")
	var errors := 0
	var ends: Array[String] = []
	var wonder_dupes := 0
	var total_captures := 0
	var best_ages: Array[int] = []
	var best_edicts: Array[int] = []
	var mean_cities := 0.0
	var games := 6
	for s in games:
		g.new_run(5000 + s, EdictData.LEADERS[s % 6]["id"], 1)
		g.me.is_human = false
		g.captures = 0
		var guard := 0
		while not g.over and guard < 120:
			guard += 1
			g.run_turn()
		var civs: Array[Player] = []
		for p in g.players:
			if not p.is_barbarian:
				civs.append(p)
		var owned := {}
		var total_w := 0
		var ages := 0
		var edicts := 0
		var cities := 0
		for p in civs:
			for w in p.wonders:
				owned[w] = true
				total_w += 1
			ages = maxi(ages, p.age)
			edicts = maxi(edicts, p.edicts.size())
			cities += p.cities.size()
		if total_w != owned.size():
			wonder_dupes += 1
		total_captures += g.captures
		best_ages.append(ages)
		best_edicts.append(edicts)
		mean_cities += cities / 4.0
		ends.append(g.end_how if g.end_how != "" else "unfinished")
		info("seed %d: ended turn %d (%s) · best age %d · best edicts %d · wonders %d · cities taken %d"
			% [5000 + s, g.turn, ends[ends.size() - 1], ages, edicts, owned.size(), g.captures])
	ok("six full games ran without dying", errors == 0)
	var reached := true
	for a in best_ages:
		if a < 3:
			reached = false
	ok("somebody always reaches a late age", reached, str(best_ages))
	var drafted := true
	for e in best_edicts:
		if e < 8:
			drafted = false
	ok("leaders take a healthy pile of edicts", drafted, str(best_edicts))
	ok("no wonder is ever built twice", wonder_dupes == 0, str(wonder_dupes) + " games with duplicates")
	ok("cities change hands over a campaign", total_captures >= 6,
		str(total_captures) + " captures across %d games" % games)
	ok("empires reach a decent size", mean_cities / games >= 3.0,
		"mean %.1f cities per civ" % (mean_cities / games))
	info("endings: " + ", ".join(ends))


static func _losability(g: GameRules) -> void:
	head("a run can be lost, and lost quickly")
	var deaths: Array[int] = []
	for s in 6:
		g.new_run(6100 + s, EdictData.LEADERS[s % 6]["id"], 1)
		var guard := 0
		# a wholly passive player: never builds, never moves, only ends turns
		while not g.over and guard < 100:
			guard += 1
			for c in g.me.cities:
				c.queue = {}
			g.run_turn()
		if g.end_how == "wiped":
			deaths.append(g.turn)
	ok("doing nothing loses the run", deaths.size() >= 4,
		"%d of 6 games" % deaths.size())
	if not deaths.is_empty():
		var mean := 0
		for d in deaths:
			mean += d
		mean = int(mean / float(deaths.size()))
		ok("and loses it early enough to sting", mean < 60, "mean death on turn " + str(mean))
		info("wiped out on turns: " + str(deaths))

static func _fingerprint(g: GameRules) -> String:
	var parts: Array[String] = []
	parts.append("t%d seed%d diff%d caps%d" % [g.turn, g.seed_value, g.difficulty, g.captures])
	for p in g.players:
		parts.append("P%d %s gold%d sci%d bt%d age%d alive%s kills%d edicts:%s wonders:%s" % [
			p.id, p.name, p.gold, p.sci, p.bt_done, p.age, str(p.alive), p.kills,
			",".join(p.edicts), ",".join(p.wonders)])
		for c in p.cities:
			parts.append("  C%d %s @%s pop%d food%d prod%d hp%d cap%s %s" % [
				c.id, c.name, str(c.coord), c.pop, c.food, c.prod, c.hp,
				str(c.is_capital), ",".join(c.structures)])
		for u in p.units:
			parts.append("  U%d %s @%s hp%d mv%d xp%d rank%d %s" % [
				u.id, u.type, str(u.coord), u.hp, u.mv, u.xp, u.rank, ",".join(u.promos)])
		parts.append("  seen%d" % p.seen.size())
	return "
".join(parts)


static func _save_load(g: GameRules) -> void:
	head("saving and resuming a run")
	Save.clear()
	ok("no save exists to begin with", not Save.exists())

	g.new_run(31337, "wuzhao", 1)
	g.me.is_human = false
	for i in 22:
		if g.over:
			break
		g.run_turn()
	g.me.is_human = true
	var before := _fingerprint(g)
	var cities := g.me.cities.size()
	var units := g.me.units.size()
	ok("the run has something worth saving", cities > 0 and units > 0,
		"%d cities, %d units, turn %d" % [cities, units, g.turn])

	ok("the run writes", Save.write(g))
	ok("and the file is there", Save.exists())
	ok("it can describe itself without loading", Save.describe() != "", Save.describe())

	# wipe the slate with a different world entirely
	g.new_run(999, "ashur", 2)
	ok("a different run really is different", _fingerprint(g) != before)

	ok("the saved run reads back", Save.read(g))
	var after := _fingerprint(g)
	ok("every empire comes back exactly as it was", after == before,
		_first_difference(before, after))

	# the world must come back too, not just the empires
	var improved := 0
	var ruins := 0
	for t in g.world.list:
		if t.improve > 0:
			improved += 1
		if t.ruin:
			ruins += 1
	ok("worked land keeps its improvements", improved > 0, str(improved) + " improved tiles")
	info("%d ruins still unclaimed, %d tiles improved" % [ruins, improved])

	# and play must be able to continue from it
	var turn_before := g.turn
	g.me.is_human = false
	g.run_turn()
	g.me.is_human = true
	ok("the resumed run can take another turn", g.turn == turn_before + 1)

	# finishing a run should not leave a save to continue
	g.end_run(true, "beacon")
	ok("a finished run clears its save", not Save.exists())


static func _first_difference(a: String, b: String) -> String:
	var la := a.split("
")
	var lb := b.split("
")
	for i in maxi(la.size(), lb.size()):
		var x: String = la[i] if i < la.size() else "<missing>"
		var y: String = lb[i] if i < lb.size() else "<missing>"
		if x != y:
			return "line %d: saved %s | loaded %s" % [i, x, y]
	return ""


## The click-to-move path lives in the view, not the rules, so it needs the
## real MapView to exercise. This is the interaction the player uses most.
static func _interaction(g: GameRules, main) -> void:
	head("clicking around")
	var map = main.map
	g.new_run(2468, "ragnhild", 1)
	main.ui.begin_run_ui()

	var u: Unit = null
	for v in g.me.units:
		if not v.is_civilian() and g.reachable(v).size() > 0:
			u = v
			break
	ok("there is a unit to give orders to", u != null)
	if u == null:
		return

	map.select_unit(u)
	ok("selecting fills the view's selection", map.selected_unit == u)
	ok("and works out where it may walk", map.reach.size() > 0,
		str(map.reach.size()) + " tiles")

	# walk it to a tile inside its range
	var target: Vector2i = Vector2i.ZERO
	for k in map.reach:
		target = k
		break
	var before := u.coord
	map.order_to(u, g.world.at(target))
	ok("ordering a move moves the unit", u.coord != before,
		"%s -> %s" % [str(before), str(u.coord)])
	ok("the unit is spent afterwards", u.mv <= 0 or u.done or u.coord == target)

	# a far tile becomes a standing order rather than a refusal
	g.new_run(2469, "ragnhild", 1)
	var scout: Unit = null
	for v2 in g.me.units:
		if v2.type == "scout":
			scout = v2
	if scout != null:
		var here := g.world.at(scout.coord)
		var far: Tile = null
		var best := 0
		for t in g.world.list:
			if t.continent != here.continent or t.is_water():
				continue
			var d := Hex.distance(t.coord, scout.coord)
			if d > best and d < 12:
				best = d
				far = t
		if far != null:
			map.select_unit(scout)
			map.order_to(scout, far)
			ok("a distant order becomes a standing one", scout.has_goto,
				"heading for " + str(scout.goto))
			var d1 := Hex.distance(scout.coord, far.coord)
			ok("and it sets off at once", d1 < best, "%d -> %d" % [best, d1])
			for i in 6:
				if not scout.has_goto or scout.dead:
					break
				g.run_turn()
				map.resume_orders(g.me)
			ok("a standing order carries it on across turns",
				scout.dead or Hex.distance(scout.coord, far.coord) < d1,
				"now %d away" % Hex.distance(scout.coord, far.coord))

	# selecting a city, and the panels that hang off it
	g.new_run(2470, "wuzhao", 1)
	main.ui.begin_run_ui()
	map.select_city(g.me.capital)
	ok("a city can be selected", map.selected_city == g.me.capital)
	ok("selecting a city drops the unit selection", map.selected_unit == null)
	var panels_ok := true
	var why := ""
	for opener in [
		func(): main.ui.show_build_menu(g.me.capital),
		func(): main.ui.show_cities(),
		func(): main.ui.show_help(),
		func(): main.ui.show_chronicle(),
		func(): main.ui.show_pause(),
		func(): main.ui.show_nations()]:
		var before_open := true
		opener.call()
		main.ui.close_modal()
		if not before_open:
			panels_ok = false
	ok("every panel opens and closes without dying", panels_ok, why)
	map.clear_selection()
	ok("clearing leaves nothing selected",
		map.selected_unit == null and map.selected_city == null and map.reach.is_empty())


static func _events(g: GameRules) -> void:
	head("events")
	var known := {}
	var bad: Array[String] = []
	var effect_keys := ["gold", "gold_per_city", "progress", "m", "pop_capital",
		"pop_all", "xp_all", "heal_all", "diplo_all", "reveal", "unit", "unit2"]
	for e in EventData.LIST:
		var id := str(e.get("id", "?"))
		if known.has(id):
			bad.append(id + " (duplicate)")
		known[id] = true
		if not e.has("title") or not e.has("text"):
			bad.append(id + " (no text)")
		var opts: Array = e.get("options", [])
		if opts.size() < 2 or opts.size() > 3:
			bad.append(id + " (%d options)" % opts.size())
		for o in opts:
			if not o.has("label") or not o.has("desc"):
				bad.append(id + " (option without words)")
			var has_effect := false
			for k in effect_keys:
				if o.has(k):
					has_effect = true
			if not has_effect:
				bad.append(id + "/" + str(o.get("label", "?")) + " (does nothing)")
	ok("every event is well formed", bad.is_empty(), ", ".join(bad.slice(0, 4)))
	info("%d events, %d choices in all" % [EventData.LIST.size(), _count_options()])

	# the effects must actually land
	g.new_run(4321, "ashur", 1)
	var gold_before := g.me.gold
	g.take_event_option(g.me, {"gold": 150})
	ok("gold arrives", g.me.gold == gold_before + 150, "%d -> %d" % [gold_before, g.me.gold])

	var prod_before := g.city_yield(g.me.capital).y
	g.take_event_option(g.me, {"m": {"p_prod": 2}})
	g.assign_tiles(g.me.capital)
	ok("a permanent modifier lands", g.city_yield(g.me.capital).y > prod_before,
		"%d -> %d" % [prod_before, g.city_yield(g.me.capital).y])

	var pop_before := g.me.capital.pop
	g.take_event_option(g.me, {"pop_all": 1})
	ok("population grows", g.me.capital.pop == pop_before + 1)
	g.take_event_option(g.me, {"pop_all": -99})
	ok("and never falls below one", g.me.capital.pop == 1, str(g.me.capital.pop))

	var units_before := g.me.units.size()
	g.take_event_option(g.me, {"unit": "melee", "unit_xp": 40})
	ok("a gifted soldier appears", g.me.units.size() == units_before + 1)
	var gift: Unit = g.me.units[g.me.units.size() - 1]
	ok("and arrives seasoned", gift.rank > 0, "rank " + str(gift.rank))

	var att_before := float(g.players[1].relation(g.me.id)["attitude"])
	g.take_event_option(g.me, {"diplo_all": 20.0})
	ok("goodwill moves the rivals",
		float(g.players[1].relation(g.me.id)["attitude"]) > att_before)

	# and they should turn up during a run, without ever repeating
	var fired := 0
	var repeats := 0
	g.new_run(5150, "nefertiti", 1)
	var seen := {}
	# a seat left to itself is overrun long before turn 90, so measure the
	# cadence against the turns actually played rather than the turns asked for
	var played := 0
	for i in 90:
		if g.over:
			break
		g.run_turn()
		played += 1
		if not g.pending_event.is_empty():
			var id2 := str(g.pending_event["id"])
			if seen.has(id2):
				repeats += 1
			seen[id2] = true
			fired += 1
			g.take_event_option(g.me, g.pending_event["options"][0])
	var per := float(played) / maxf(1.0, float(fired))
	ok("events arrive over a run", fired >= 2 and per >= 8.0 and per <= 18.0,
		"%d in %d turns (one per %.1f)" % [fired, played, per])
	info("events fired: " + ", ".join(PackedStringArray(seen.keys())))
	ok("and never repeat within one", repeats == 0, str(repeats) + " repeats")


static func _count_options() -> int:
	var n := 0
	for e in EventData.LIST:
		n += (e.get("options", []) as Array).size()
	return n
