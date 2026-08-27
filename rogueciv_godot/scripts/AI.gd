class_name AI
extends RefCounted

## The rivals. Static, because the AI holds no state of its own — everything
## it needs lives on the Player it is thinking for.


static func take_turn(g: GameRules, p: Player) -> void:
	if not p.alive:
		return
	g.world.recompute_vision(p)
	if not p.is_barbarian:
		_diplomacy(g, p)
	for c in p.cities.duplicate():
		if c.queue.is_empty():
			pick_build(g, c)
	_spend_gold(g, p)

	# civilians first, then siege, ranged, and finally the melee that will
	# walk into whatever the others have softened
	var order := p.units.duplicate()
	order.sort_custom(func(a, b): return _order_weight(a) < _order_weight(b))
	for u in order:
		if not u.dead:
			_run_unit(g, p, u)


static func _order_weight(u: Unit) -> int:
	match u.cls():
		"settler": return 0
		"siege": return 1
		"ranged": return 2
		_: return 3


# =========================================================================
#  Diplomacy
# =========================================================================
static func _diplomacy(g: GameRules, p: Player) -> void:
	for o in g.players:
		if o == p or o.is_barbarian or not o.alive:
			continue
		_drift_attitude(g, p, o)
		var rel := p.relation(o.id)
		if not rel["met"]:
			continue
		var mine := g.empire_power(p)
		var theirs := g.empire_power(o)
		if not rel["war"] and int(rel["truce"]) < g.turn:
			var agenda: String = p.leader.get("agenda", "")
			var wants: bool = float(rel["attitude"]) < -28.0 and mine > theirs * 1.02 and g.turn > 10
			var opportunist: bool = float(rel["attitude"]) < -10.0 and mine > theirs * 1.7 and g.turn > 14
			var greedy: bool = (agenda == "conqueror" or agenda == "raider") \
				and mine > theirs * 1.25 and g.turn > 16
			if (wants or opportunist or greedy) and g.rng.chance(0.26 * g.diff()["aggression"]):
				g.declare_war(p, o)
		elif rel["war"]:
			var losing := mine < theirs * 0.62
			if (losing or g.rng.chance(0.10)) and g.rng.chance(0.4):
				if o == g.me:
					if g.rng.chance(0.5):
						g.pending_peace_offer = p
				else:
					g.make_peace(p, o)
		# the tributary's favourite pastime
		if o == g.me and not rel["war"] and p.leader.get("agenda", "") == "tributary" \
				and g.turn - int(rel["last_tribute"]) > 16 and mine > theirs * 1.15 \
				and g.me.mod("no_tribute") <= 0.0 and g.rng.chance(0.45):
			rel["last_tribute"] = g.turn
			g.pending_tribute_demand = p


static func _drift_attitude(g: GameRules, a: Player, b: Player) -> void:
	var rel := a.relation(b.id)
	if not rel["met"]:
		return
	var agenda: String = a.leader.get("agenda", "")
	var mine := g.empire_power(a)
	var theirs := g.empire_power(b)
	var ratio := float(theirs) / maxf(1.0, float(mine))
	var target := -8.0                      ## nobody starts out trusting anybody

	match agenda:
		"conqueror": target -= 24.0 + (1.4 - minf(1.4, ratio)) * 30.0
		"raider":    target -= 15.0 + (16.0 if b.gold > a.gold else 0.0)
		"builder":   target -= 5.0 + b.wonders.size() * 12.0
		"scholar":   target += (a.bt_done - b.bt_done) * 3.5 - 5.0
		"peaceful":  target += 30.0 - b.kills * 2.0
		"tributary": target += int(rel["paid"]) * 12.0 - int(rel["refused"]) * 20.0 - 5.0

	# a close neighbour is a temptation, a weak close neighbour doubly so
	var min_dist := 99
	for c in a.cities:
		for c2 in b.cities:
			min_dist = mini(min_dist, Hex.distance(c.coord, c2.coord))
	if min_dist < 9:
		target -= (9 - min_dist) * 4.0 * (1.5 if ratio < 1.0 else 0.7)

	target += a.mod("diplo")
	if rel["denounced"]:
		target -= 25.0
	if rel["war"]:
		target -= 25.0
	target = clampf(target, -100.0, 100.0)

	var att := float(rel["attitude"])
	var step := minf(2.5, absf(target - att) * 0.25)
	att += signf(target - att) * step
	rel["attitude"] = clampf(att, -100.0, 100.0)


# =========================================================================
#  What a city builds
# =========================================================================
static func pick_build(g: GameRules, c: City) -> void:
	var p := g.player(c.owner_id)
	var options := g.build_options(c)
	if options.is_empty():
		c.queue = {}
		return
	var threat := g.threat_at(p, c.coord)
	var t := g.world.at(c.coord)
	var garrison = t.military() if t != null else null
	var at_war_any := false
	for o in g.players:
		if o != p and not o.is_barbarian and g.at_war(p, o):
			at_war_any = true
			break
	var settlers_out := 0
	var army := 0
	for u in p.units:
		if u.is_civilian():
			settlers_out += 1
		else:
			army += 1
	var want_army := 2.0 + p.cities.size() * (2.8 if at_war_any else 1.1) \
		+ (3.0 if p.leader.get("agenda", "") == "conqueror" else 0.0)
	var aggression: float = g.diff()["aggression"]

	var best: Dictionary = {}
	var best_score := -1e9
	for o in options:
		var s := g.rng.nextf() * 10.0
		match o["kind"]:
			"unit":
				var d: Dictionary = Data.UNIT[o["id"]]
				if d["cls"] == "settler":
					var room := p.city_cap() - p.cities.size()
					s += -70.0 if settlers_out >= mini(2, room) else 84.0 - p.cities.size() * 5.0
					if threat > 28.0:
						s -= 45.0
					if c.pop < 3:
						s -= 18.0
				else:
					s += 26.0 + (0.0 if garrison != null else 34.0) + minf(50.0, threat * 1.5)
					s += 34.0 * aggression if army < want_army else -22.0
					if at_war_any:
						s += 18.0 * aggression
					s += float(d["str"]) * 0.28
					if d["cls"] == "ranged":
						s += 6.0
					if d["cls"] == "siege" and at_war_any:
						s += 16.0
					if d["cls"] == "recon" and p.units.size() > 3:
						s -= 40.0
				s -= g.unit_cost(p, o["id"]) * 0.055
			"structure":
				var sd: Dictionary = Data.STRUCTURE[o["id"]]
				var f: Dictionary = sd["f"]
				s += 40.0
				s += float(f.get("food", 0)) * 7.0 + (12.0 if c.pop < 5 else 0.0)
				s += float(f.get("sci", 0)) * 6.0 + (14.0 if p.leader.get("agenda", "") == "scholar" else 0.0)
				s += float(f.get("gold", 0)) * 5.0
				s += float(f.get("prod_pct", 0.0)) * 70.0
				s += float(f.get("hp", 0)) * 0.22 + threat * 0.8
				if f.has("unit_pct"):
					s += 14.0 * aggression
				s -= g.structure_cost(p, o["id"]) * 0.075
				if threat > 30.0:
					s -= 20.0
			_:
				var wd: Dictionary = Data.WONDER[o["id"]]
				s += 44.0 + (46.0 if p.leader.get("agenda", "") == "builder" else 0.0)
				if wd.get("victory", false):
					s += 260.0
				s -= g.wonder_cost(p, o["id"]) * 0.055
				if threat > 25.0:
					s -= 40.0
		if s > best_score:
			best_score = s
			best = o
	c.queue = {"kind": best["kind"], "id": best["id"]} if not best.is_empty() else {}

	if not c.queue.is_empty() and c.queue["id"] == "beacon" and not p.beacon_announced:
		p.beacon_announced = true
		g.log_line("%s begins work on The Beacon." % p.name, "big")
		g.banner.emit(p.name + " begins The Beacon", "finish yours first, or stop theirs")


static func _spend_gold(g: GameRules, p: Player) -> void:
	if p.is_barbarian or p.gold < 260 or not g.rng.chance(0.5):
		return
	if p.cities.is_empty():
		return
	var c: City = p.cities[g.rng.below(p.cities.size())]
	if c.queue.is_empty():
		return
	var cost := g.buy_cost(c)
	if cost <= p.gold * 0.7:
		p.gold -= cost
		c.prod = g.item_cost(p, c.queue)


# =========================================================================
#  Units
# =========================================================================
static func _run_unit(g: GameRules, p: Player, u: Unit) -> void:
	var d: Dictionary = Data.UNIT[u.type]

	if d["cls"] == "settler":
		_run_settler(g, p, u)
		return

	# the wounded go home
	if u.hp < 38 and not u.embarked:
		var home := _nearest_own_city(p, u)
		if home != null and Hex.distance(u.coord, home.coord) > 0:
			_move_along(g, u, home.coord)
			return
		u.fortified = 1
		return

	# ranged and siege shoot first
	if g.unit_range(u) > 0:
		var targets := _ranged_targets(g, p, u)
		if not targets.is_empty():
			targets.sort_custom(func(a, b):
				var av := 200 if a["city"] else 0
				var bv := 200 if b["city"] else 0
				return av > bv)
			g.ranged_attack(u, targets[0]["tile"])
			return

	var adjacent := _adjacent_targets(g, p, u)
	if not adjacent.is_empty() and d["cls"] != "siege":
		var best: Dictionary = {}
		var best_odds := -1
		var best_is_city := false
		for a in adjacent:
			var odds := 0
			if a["city"] != null:
				odds = g.combat_odds(
					g.unit_strength(u, {"attacking": true, "vs_city": true, "tile": g.world.at(u.coord)}),
					g.defence_at(a["tile"], u))
				odds += 25 if a["city"].hp < a["city"].max_hp * 0.35 else 8
				if p.has_objective and a["tile"].coord == p.objective:
					odds += 20
			else:
				odds = g.combat_odds(
					g.unit_strength(u, {"attacking": true, "foe": a["foe"], "tile": g.world.at(u.coord)}),
					g.unit_strength(a["foe"], {"defending": true, "tile": a["tile"], "foe": u}))
			if a["foe"] != null and a["foe"].is_civilian():
				odds = 200
			if odds > best_odds:
				best_odds = odds
				best = a
				best_is_city = a["city"] != null
		# an even field fight only trades away the army meant to take a city
		var bar := 32 if p.is_barbarian else (42 if best_is_city else 56)
		if best_odds >= bar:
			g.melee_attack(u, best["tile"])
			return

	var goal := _goal_for(g, p, u)
	if goal.x != 9999:
		_move_along(g, u, goal)
	else:
		u.fortified = mini(3, u.fortified + 1)

	# one more look now that it has moved
	if u.dead or u.fought_this_turn or u.mv <= 0:
		return
	var again := _adjacent_targets(g, p, u)
	if not again.is_empty() and d["cls"] != "siege":
		var a2: Dictionary = again[0]
		var odds2 := 0
		if a2["city"] != null:
			odds2 = g.combat_odds(
				g.unit_strength(u, {"attacking": true, "vs_city": true}),
				g.defence_at(a2["tile"], u)) + 12
		else:
			odds2 = g.combat_odds(
				g.unit_strength(u, {"attacking": true, "foe": a2["foe"]}),
				g.unit_strength(a2["foe"], {"defending": true, "tile": a2["tile"], "foe": u}))
		if odds2 >= (45 if a2["city"] != null else 58):
			g.melee_attack(u, a2["tile"])
	elif g.unit_range(u) > 0:
		var late := _ranged_targets(g, p, u)
		if not late.is_empty():
			g.ranged_attack(u, late[0]["tile"])


static func _run_settler(g: GameRules, p: Player, u: Unit) -> void:
	if p.cities.size() >= p.city_cap():
		u.done = true
		return
	var here := g.world.at(u.coord)
	var need_site := not u.has_site
	if u.has_site:
		var st := g.world.at(u.site_target)
		if st == null or st.city != null or (st.owner_id >= 0 and st.owner_id != p.id) \
				or Hex.distance(u.coord, u.site_target) > 16:
			need_site = true
	if need_site:
		var found := g.best_site_near(p, u.coord, 13)
		if found != null:
			u.site_target = found.coord
			u.has_site = true
		else:
			u.has_site = false

	if not u.has_site:
		if g.can_found_here(p, here):
			g.found_city(p, here, false)
			g.kill_unit(u, true)
		return
	if u.coord == u.site_target and g.can_found_here(p, here):
		g.found_city(p, here, false)
		g.kill_unit(u, true)
		return
	_move_along(g, u, u.site_target)
	var now := g.world.at(u.coord)
	if u.coord == u.site_target and g.can_found_here(p, now):
		g.found_city(p, now, false)
		g.kill_unit(u, true)


static func _nearest_own_city(p: Player, u: Unit) -> City:
	var best: City = null
	var bd := 9999
	for c in p.cities:
		var d := Hex.distance(u.coord, c.coord)
		if d < bd:
			bd = d
			best = c
	return best


static func _adjacent_targets(g: GameRules, p: Player, u: Unit) -> Array:
	var out: Array = []
	for nb in g.world.neighbours(u.coord):
		var foe = nb.military()
		if foe == null:
			foe = nb.civilian()
		if foe != null and g.at_war(p, g.player(foe.owner_id)):
			out.append({"tile": nb, "foe": foe, "city": null})
		elif nb.city != null and nb.city.owner_id != u.owner_id \
				and g.at_war(p, g.player(nb.city.owner_id)):
			out.append({"tile": nb, "foe": null, "city": nb.city})
	return out


static func _ranged_targets(g: GameRules, p: Player, u: Unit) -> Array:
	var rng_r := g.unit_range(u)
	var out: Array = []
	if rng_r <= 0:
		return out
	for nb in g.world.in_range(u.coord, rng_r):
		var d := Hex.distance(u.coord, nb.coord)
		if d < 1:
			continue
		var foe = nb.military()
		if foe == null:
			foe = nb.civilian()
		if foe != null and g.at_war(p, g.player(foe.owner_id)):
			out.append({"tile": nb, "foe": foe, "city": null})
		elif nb.city != null and nb.city.owner_id != u.owner_id \
				and g.at_war(p, g.player(nb.city.owner_id)) and nb.city.hp > 0:
			out.append({"tile": nb, "foe": null, "city": nb.city})
	return out


## The whole army works one objective at a time: units choosing their own
## nearest target scattered the host and no city ever fell.
static func _choose_objective(g: GameRules, p: Player, foes: Array) -> void:
	p.objective_turn = g.turn
	var best = null
	var best_score := -1e9
	for o in foes:
		for c in o.cities:
			var s := (1.0 - float(c.hp) / maxf(1.0, float(c.max_hp))) * 70.0
			s -= g.city_defence(c) * 0.7
			var dist := 40
			for mc in p.cities:
				dist = mini(dist, Hex.distance(mc.coord, c.coord))
			s -= dist * 3.2
			if c.is_capital:
				s += 22.0
			if o.cities.size() == 1:
				s += 30.0                      ## finish a wounded rival off
			if s > best_score:
				best_score = s
				best = c
	if best != null:
		p.objective = best.coord
		p.has_objective = true
	else:
		p.has_objective = false

	# pin the closest healthy unit to each city so home is never naked
	var army: Array = []
	for v in p.units:
		if not v.is_civilian():
			army.append(v)
			v.garrison_of = null
	var taken := {}
	for c in p.cities:
		var pick = null
		var pd := 9999
		for v in army:
			if taken.has(v) or v.hp < 55:
				continue
			var d := Hex.distance(v.coord, c.coord)
			if d < pd:
				pd = d
				pick = v
		if pick != null and army.size() > p.cities.size():
			pick.garrison_of = c
			taken[pick] = true


static func _goal_for(g: GameRules, p: Player, u: Unit) -> Vector2i:
	var none := Vector2i(9999, 9999)
	var d: Dictionary = Data.UNIT[u.type]

	if p.is_barbarian:
		var best := none
		var bd := 9999
		for o in g.players:
			if o == p or not o.alive:
				continue
			for c in o.cities:
				var dd := Hex.distance(u.coord, c.coord)
				if dd < bd and dd < 11:
					bd = dd
					best = c.coord
			for v in o.units:
				var dv := Hex.distance(u.coord, v.coord)
				if dv < bd - 3 and dv < 7:
					bd = dv + 3
					best = v.coord
		if best.x != 9999:
			return best
		var wander: Array = []
		for t in g.world.list:
			if not t.is_water() and not t.is_impassable():
				wander.append(t)
		if wander.is_empty():
			return none
		return wander[g.rng.below(wander.size())].coord

	# scouts explore
	if d["cls"] == "recon" and p.units.size() > 1:
		var target := none
		var bd2 := 9999
		for t in g.world.list:
			if p.seen.has(t.coord) or t.is_water() or t.is_impassable():
				continue
			var dd2 := Hex.distance(u.coord, t.coord)
			if dd2 < bd2:
				bd2 = dd2
				target = t.coord
		if target.x != 9999:
			return target

	var foes: Array = []
	for o in g.players:
		if o != p and o.alive and g.at_war(p, o) and (not o.cities.is_empty() or not o.units.is_empty()):
			foes.append(o)
	if not foes.is_empty():
		if p.objective_turn != g.turn:
			_choose_objective(g, p, foes)
		if u.garrison_of != null:
			if Hex.distance(u.coord, u.garrison_of.coord) > 0:
				return u.garrison_of.coord
			return none
		if p.has_objective:
			if d["cls"] == "siege" and Hex.distance(u.coord, p.objective) <= g.unit_range(u):
				return none
			return p.objective
		var nearest := none
		var bd3 := 9999
		for o in foes:
			for v in o.units:
				var dv2 := Hex.distance(u.coord, v.coord)
				if dv2 < bd3:
					bd3 = dv2
					nearest = v.coord
		return nearest

	# at peace: hold whichever city looks softest
	var weakest = null
	var ws := 1e9
	for c in p.cities:
		var garrisons := 0
		for v in p.units:
			if v != u and not v.is_civilian() and Hex.distance(v.coord, c.coord) <= 1:
				garrisons += 1
		var s := garrisons * 10.0 - g.threat_at(p, c.coord) * 0.4 + Hex.distance(u.coord, c.coord) * 0.6
		if s < ws:
			ws = s
			weakest = c
	if weakest != null and Hex.distance(u.coord, weakest.coord) > 1:
		return weakest.coord
	return none


static func _move_along(g: GameRules, u: Unit, goal: Vector2i) -> void:
	if goal.x == 9999 or u.coord == goal:
		return
	var path := g.path_to(u, goal)
	if path.is_empty():
		return
	for step in path:
		if u.mv <= 0:
			break
		var t := g.world.at(step)
		if t == null or g.blocked_by(u, t) != "":
			break
		if not g.step_unit(u, t):
			break


# =========================================================================
#  Raiders
# =========================================================================
static func barbarian_turn(g: GameRules) -> void:
	var b := g.barbarians()
	# the opening is deliberately quiet: nothing hunts you for the first turns
	if g.turn < 8:
		return
	var camps: Array = []
	for t in g.world.list:
		if t.camp:
			camps.append(t)
	var cap := int(round((3.0 + g.turn * 0.12) * g.diff()["barb"]))
	if b.units.size() < cap and not camps.is_empty() and g.rng.chance(0.55 * g.diff()["barb"]):
		var t: Tile = camps[g.rng.below(camps.size())]
		var spot = g.free_spot_for(b, t, false)
		if spot != null:
			var tier := 0
			for p in g.players:
				if not p.is_barbarian:
					tier = maxi(tier, p.age)
			tier = clampi(tier - 1, 0, Data.LAST_AGE)
			var pool: Array[String] = []
			for k in ["warrior", "spearman", "archer", "legion", "crossbow", "musket", "rifle", "infantry"]:
				if Data.UNIT[k]["age"] <= tier and not Data.UNIT[k].has("req"):
					pool.append(k)
			var type: String = pool[pool.size() - 1] if not pool.is_empty() else "warrior"
			var u := g.spawn_unit(b, type, spot.coord)
			u.xp = 10 * tier
	take_turn(g, b)
