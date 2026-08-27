class_name GameRules
extends Node

## The rules. Autoloaded as `Game`.
## The interface never reaches past the signals and the public helpers here.

signal state_changed
signal log_added(text: String, kind: String)
signal banner(title: String, subtitle: String)
signal draft_ready
signal promotion_ready(unit: Unit)
signal run_ended(won: bool, how: String)
signal revealed(flag: String)
signal combat_happened(at: Vector2i, damage: int)
signal attack_made(from: Vector2i, to: Vector2i, ranged: bool)

# =========================================================================
#  State
# =========================================================================
var world: World
var players: Array[Player] = []
var me: Player = null
var rng: Rng

var seed_value: int = 0
var leader_id: String = ""
var turn: int = 1
var difficulty: int = 1
var over: bool = false
var end_how: String = ""
var end_won: bool = false
var busy: bool = false

var wonders_built: Dictionary = {}   ## wonder id -> owner id + 1 (never 0: player 0 is falsy)
var next_id: int = 1
var pending_drafts: int = 0
var pending_promotions: Array = []
var pending_event: Dictionary = {}
var events_seen: Array[String] = []
var next_event_turn: int = 0
var chronicle: Array = []
var captures: int = 0

## Progressive disclosure: the interface only shows what has come up.
var unlocked: Dictionary = {}
var hints_done: Dictionary = {}


func diff() -> Dictionary:
	return EdictData.DIFFICULTIES[difficulty]


func unlock(flag: String) -> void:
	if unlocked.has(flag):
		return
	unlocked[flag] = true
	revealed.emit(flag)


func is_unlocked(flag: String) -> bool:
	return unlocked.has(flag)


func log_line(text: String, kind: String = "") -> void:
	chronicle.append({"turn": turn, "text": text, "kind": kind})
	if chronicle.size() > 240:
		chronicle.pop_front()
	log_added.emit(text, kind)


# =========================================================================
#  Starting a run
# =========================================================================
func new_run(a_seed: int, a_leader_id: String, a_difficulty: int) -> void:
	seed_value = a_seed
	leader_id = a_leader_id
	difficulty = a_difficulty
	rng = Rng.new(a_seed ^ 0x5f3a71)
	turn = 1
	over = false
	end_how = ""
	end_won = false
	busy = false
	next_id = 1
	pending_drafts = 0
	pending_promotions.clear()
	pending_event = {}
	events_seen.clear()
	wonders_built.clear()
	chronicle.clear()
	unlocked.clear()
	hints_done.clear()
	captures = 0
	players.clear()

	world = World.new()
	world.generate(a_seed, Data.MAP_RADIUS)

	# you, then rivals drawn from the leaders you were not offered
	me = _make_player(0, a_leader_id, true)
	players.append(me)
	var rest: Array = []
	for L in EdictData.LEADERS:
		if L["id"] != a_leader_id:
			rest.append(L)
	rng.shuffle(rest)
	for i in Data.NUM_RIVALS:
		players.append(_make_player(i + 1, rest[i]["id"], false))
	players.append(_make_barbarians(players.size()))

	var spots := _pick_starts(Data.NUM_RIVALS + 1)
	var civs: Array = []
	for p in players:
		if not p.is_barbarian:
			civs.append(p)
	for i in civs.size():
		var p: Player = civs[i]
		var t: Tile = spots[i]
		var c := found_city(p, t, true)
		_grant_starting_unit(p, t, "warrior", false)
		_grant_starting_unit(p, t, "scout", false)
		_grant_starting_unit(p, t, "settler", true)
		p.gold = 40
		world.recompute_vision(p)

	_seed_camps()
	world.recompute_territory(players)
	for p in players:
		world.recompute_vision(p)
	for p in players:
		for c in p.cities:
			assign_tiles(c)

	# scheduled last: drawing from this generator earlier would shift where
	# every civilisation starts
	next_event_turn = 8 + rng.below(5)

	unlock("city")
	log_line("The %s people settle at %s." % [me.adjective, me.capital.name], "big")
	state_changed.emit()


func _grant_starting_unit(p: Player, t: Tile, base: String, civilian: bool) -> void:
	var spot := free_spot_for(p, t, civilian)
	if spot != null:
		spawn_unit(p, real_unit(p, base), spot.coord)


func _make_player(id: int, leader_id: String, human: bool) -> Player:
	var L: Dictionary = {}
	for entry in EdictData.LEADERS:
		if entry["id"] == leader_id:
			L = entry
			break
	var p := Player.new()
	p.id = id
	p.is_human = human
	p.leader = L
	p.name = L["civ"]
	p.adjective = L["adj"]
	p.colour = Pal.CIV_COLOURS[L["colour"]]
	p.add_mods(L["m"])
	return p


func _make_barbarians(id: int) -> Player:
	var p := Player.new()
	p.id = id
	p.is_barbarian = true
	p.name = "Raiders"
	p.adjective = "Raider"
	p.colour = Pal.BARBARIAN
	p.leader = {"name": "Raiders", "civ": "Raiders", "agenda": "barbarian",
				"agenda_desc": "", "cities": []}
	return p


func rivals() -> Array:
	var out: Array = []
	for p in players:
		if not p.is_barbarian and p != me:
			out.append(p)
	return out


func living_rivals() -> Array:
	var out: Array = []
	for p in rivals():
		if p.alive:
			out.append(p)
	return out


func barbarians() -> Player:
	return players[players.size() - 1]


func _pick_starts(n: int) -> Array:
	var scored: Array = []
	for t in world.list:
		if t.is_water() or t.is_impassable() or t.terrain == "snow":
			continue
		scored.append({"t": t, "s": site_score(null, t) + Hex.hash2(t.coord.x, t.coord.y) * 6.0})
	scored.sort_custom(func(a, b): return a["s"] > b["s"])

	var out: Array = []
	var min_d := maxi(5, int(round(world.radius * 0.85)))
	for relax in 6:
		out.clear()
		var need := min_d - relax
		for entry in scored:
			if out.size() >= n:
				break
			var t: Tile = entry["t"]
			var ok := true
			for o in out:
				if Hex.distance(o.coord, t.coord) < need:
					ok = false
					break
			if ok:
				out.append(t)
		if out.size() >= n:
			break
	while out.size() < n:
		for entry in scored:
			if not out.has(entry["t"]):
				out.append(entry["t"])
				break
	out.resize(n)
	rng.shuffle(out)
	return out


func _seed_camps() -> void:
	var land: Array = []
	for t in world.list:
		if not t.is_water() and not t.is_impassable() and t.city == null and t.owner_id < 0:
			land.append(t)
	rng.shuffle(land)
	var want := int(round(world.list.size() * 0.016 * diff()["barb"])) + 2
	var n := 0
	for t in land:
		if n >= want:
			break
		var too_close := false
		for p in players:
			for c in p.cities:
				if Hex.distance(c.coord, t.coord) < 5:
					too_close = true
					break
		if too_close:
			continue
		var crowded := false
		for o in world.in_range(t.coord, 3):
			if o.camp:
				crowded = true
				break
		if crowded:
			continue
		t.camp = true
		n += 1


# =========================================================================
#  Cities
# =========================================================================
func found_city(p: Player, t: Tile, is_capital: bool) -> City:
	var c := City.new()
	c.id = next_id
	next_id += 1
	c.owner_id = p.id
	c.coord = t.coord
	c.name = p.next_city_name()
	c.pop = 1 + (1 if is_capital else int(p.mod("pop_start")))
	c.is_capital = is_capital
	c.founded = turn
	if is_capital:
		p.capital = c
	t.city = c
	t.ruin = false
	t.camp = false
	p.cities.append(c)
	refresh_city(c)
	c.hp = c.max_hp
	world.recompute_territory(players)
	if p == me:
		Snd.play("found")
		unlock("city")
	return c


func refresh_city(c: City) -> void:
	var p := player(c.owner_id)
	var f := {"food": 0, "prod": 0, "gold": 0, "sci": 0, "hp": 0, "def": 0,
			  "unit_pct": 0.0, "prod_pct": 0.0, "xp": 0, "water": 0, "radius": 0, "max_pop": 0}
	for s in c.structures:
		var d: Dictionary = Data.STRUCTURE.get(s, Data.WONDER.get(s, {}))
		if not d.has("f"):
			continue
		for k in d["f"]:
			f[k] = f.get(k, 0) + d["f"][k]
	c.effects = f
	c.max_hp = int(round(100 + c.pop * 4 + int(f["hp"]) + p.mod("city_hp")))
	c.hp = mini(c.hp, c.max_hp)


func city_max_pop(c: City) -> int:
	var p := player(c.owner_id)
	if int(c.effects.get("max_pop", 0)) > 0 or p.mod("max_pop") > 0.0:
		return 99
	return 8


func assign_tiles(c: City) -> void:
	var p := player(c.owner_id)
	var rad := world.city_radius(c, p)
	var centre := world.at(c.coord)
	var coastal := world.is_coastal(c.coord)
	var cand: Array = []
	for t in world.in_range(c.coord, rad):
		if t == centre or t.owner_id != c.owner_id:
			continue
		if t.worked_by != -1 and t.worked_by != c.id:
			continue
		if t.is_impassable():
			continue
		if t.is_water() and int(c.effects.get("water", 0)) == 0 and not coastal:
			continue
		cand.append(t)

	var w: Array
	match c.focus:
		"growth": w = [4.2, 1.3, 0.8]
		"work":   w = [1.5, 4.0, 0.8]
		"trade":  w = [1.6, 1.3, 3.4]
		_:        w = [2.4, 2.2, 1.1]

	var scored: Array = []
	for t in cand:
		var y := world.tile_yield(t, p)
		var s: float = y.x * w[0] + y.y * w[1] + y.z * w[2]
		if t.is_water():
			s += 1.2 if int(c.effects.get("water", 0)) > 0 else -1.0
		if t.resource != "":
			s += 0.7
		scored.append({"t": t, "s": s})
	scored.sort_custom(func(a, b): return a["s"] > b["s"])

	for t in world.list:
		if t.worked_by == c.id:
			t.worked_by = -1
	c.worked.clear()
	var n := mini(c.pop, scored.size())
	for i in n:
		var t: Tile = scored[i]["t"]
		t.worked_by = c.id
		c.worked.append(t)


## Returns food, production, gold, progress for one turn.
func city_yield(c: City) -> Vector4i:
	var p := player(c.owner_id)
	var centre := world.at(c.coord)
	var cy := world.tile_yield(centre, p)
	var f := maxi(2, cy.x)
	var pr := maxi(1, cy.y)
	var g := cy.z
	var water_bonus := int(c.effects.get("water", 0))
	for t in c.worked:
		var y := world.tile_yield(t, p)
		f += y.x
		pr += y.y
		g += y.z
		if t.is_water() and water_bonus > 0:
			f += water_bonus
			g += water_bonus

	f += int(c.effects.get("food", 0)) + int(p.mod("p_food"))
	pr += int(c.effects.get("prod", 0)) + int(p.mod("p_prod"))
	g += int(c.effects.get("gold", 0)) + int(p.mod("p_gold"))
	f -= c.pop * 2

	pr = int(round(pr * (1.0 + float(c.effects.get("prod_pct", 0.0)) + p.mod("pct_prod"))))
	g = int(round(g * (1.0 + p.mod("pct_gold"))))

	var s := 1.5 + c.pop * 0.7 + float(c.effects.get("sci", 0)) + p.mod("p_sci") \
		+ p.mod("sci_per_pop") * c.pop
	if c.is_capital:
		s += p.mod("cap_sci")
	var sci_mult := 1.0 + p.mod("pct_sci")
	if c.is_capital:
		sci_mult += p.mod("cap_sci_pct")
	s *= sci_mult

	return Vector4i(f, maxi(1, pr), g, int(round(s)))


func city_defence(c: City) -> float:
	var p := player(c.owner_id)
	var s := 12.0 + p.age * 9.0 + float(c.effects.get("def", 0)) + p.mod("city_str")
	var t := world.at(c.coord)
	var garrison = t.military() if t != null else null
	if garrison != null:
		s += unit_strength(garrison, {}) * 0.45
	# A breached wall must actually be breached, or an assault can never finish.
	var frac := 0.0
	if c.max_hp > 0:
		frac = maxf(0.0, float(c.hp) / float(c.max_hp))
	return s * (0.45 + 0.55 * frac)


## What an attacker actually faces on a tile.
func defence_at(t: Tile, attacker: Unit) -> float:
	var city_here = t.city if (t.city != null and t.city.owner_id != attacker.owner_id) else null
	var garrison = t.military()
	if garrison != null and garrison.owner_id != attacker.owner_id:
		var d := unit_strength(garrison, {"defending": true, "tile": t, "foe": attacker})
		if city_here != null:
			d = maxf(d, city_defence(city_here) * 0.85)
		return d
	if city_here != null:
		return city_defence(city_here)
	return 1.0


# =========================================================================
#  Costs and build options
# =========================================================================
func player(id: int) -> Player:
	for p in players:
		if p.id == id:
			return p
	return null


func real_unit(p: Player, base: String) -> String:
	var uq: String = p.leader.get("unique", "")
	if uq != "" and Data.UNIT[uq].get("replaces", "") == base:
		return uq
	return base


func unit_cost(p: Player, id: String) -> int:
	var d: Dictionary = Data.UNIT[id]
	var c: float = d["cost"]
	if d["cls"] == "settler":
		c = 44.0 + 22.0 * maxi(0, p.cities.size() - 1)
		c *= 1.0 + p.mod("settler_pct")
	else:
		c *= 1.0 + p.mod("unit_pct")
	return maxi(10, int(round(c)))


func structure_cost(p: Player, id: String) -> int:
	return maxi(10, int(round(Data.STRUCTURE[id]["cost"] * (1.0 + p.mod("struct_pct")))))


func wonder_cost(p: Player, id: String) -> int:
	var mult := 1.0 + p.mod("wonder_pct")
	if id == "beacon":
		mult += p.mod("beacon_pct")
	return maxi(20, int(round(Data.WONDER[id]["cost"] * mult)))


func item_cost(p: Player, item: Dictionary) -> int:
	if item.is_empty():
		return 0
	match item["kind"]:
		"unit": return unit_cost(p, item["id"])
		"structure": return structure_cost(p, item["id"])
		_: return wonder_cost(p, item["id"])


func has_resource(p: Player, res: String) -> bool:
	if res == "":
		return true
	if p.mod("free_" + res) > 0.0:
		return true
	for t in world.list:
		if t.resource == res and t.owner_id == p.id and world.resource_visible(t, p):
			return true
	return false


func wonder_taken(id: String) -> bool:
	return wonders_built.has(id)


func wonder_owner(id: String) -> int:
	return int(wonders_built.get(id, 0)) - 1


func set_wonder_owner(id: String, pid: int) -> void:
	wonders_built[id] = pid + 1


func unit_available(p: Player, id: String) -> bool:
	var d: Dictionary = Data.UNIT[id]
	if d.has("replaces"):
		return false                      ## uniques arrive by substitution
	if d["age"] > p.age:
		return false
	var real := real_unit(p, id)
	var rd: Dictionary = Data.UNIT[real]
	if rd.has("req") and not has_resource(p, rd["req"]):
		return false
	var line: Array = Data.LINES.get(d["cls"], [])
	var i := line.find(id)
	if i >= 0:
		for j in range(i + 1, line.size()):
			var nx = line[j]
			if nx == null or nx == id:
				continue
			var nr := real_unit(p, nx)
			if Data.UNIT[nx]["age"] <= p.age and (not Data.UNIT[nr].has("req") or has_resource(p, Data.UNIT[nr]["req"])):
				return false
	return true


func build_options(c: City) -> Array:
	var p := player(c.owner_id)
	var out: Array = []
	var full := army_size(p) >= army_cap(p)
	for id in Data.UNIT:
		if not unit_available(p, id):
			continue
		if id == "settler":
			if p.cities.size() >= p.city_cap():
				continue
			if c.pop < 2 and p.mod("settler_no_pop") <= 0.0:
				continue
		elif full:
			continue
		out.append({"kind": "unit", "id": real_unit(p, id)})
	for id in Data.STRUCTURE:
		var d2: Dictionary = Data.STRUCTURE[id]
		if d2["age"] > p.age or c.has(id):
			continue
		if d2.get("coastal", false) and not world.is_coastal(c.coord):
			continue
		out.append({"kind": "structure", "id": id})
	for id in Data.WONDER:
		var d: Dictionary = Data.WONDER[id]
		if d["age"] > p.age or wonder_taken(id) or c.has(id):
			continue
		if d.get("coastal", false) and not world.is_coastal(c.coord):
			continue
		if d.has("req") and not has_resource(p, d["req"]):
			continue
		var raced := false
		for o in p.cities:
			if o != c and not o.queue.is_empty() and o.queue["kind"] == "wonder" and o.queue["id"] == id:
				raced = true
		if raced:
			continue
		out.append({"kind": "wonder", "id": id})
	return out


func buy_cost(c: City) -> int:
	var p := player(c.owner_id)
	if c.queue.is_empty():
		return 0
	var remaining := maxi(0, item_cost(p, c.queue) - c.prod)
	return maxi(8, int(round(remaining * 3.4 * (1.0 + p.mod("buy_pct")))))


func complete_item(c: City, item: Dictionary) -> bool:
	var p := player(c.owner_id)
	var t := world.at(c.coord)
	match item["kind"]:
		"unit":
			var civilian: bool = Data.UNIT[item["id"]]["cls"] == "settler"
			if not civilian and army_size(p) >= army_cap(p):
				return false
			var spot := free_spot_for(p, t, civilian)
			if spot == null:
				return false
			var u := spawn_unit(p, item["id"], spot.coord)
			u.xp = int(c.effects.get("xp", 0)) + int(p.mod("xp_start"))
			_apply_rank(u, false)
			if civilian and p.mod("settler_no_pop") <= 0.0:
				c.pop = maxi(1, c.pop - 1)
				c.food = 0
				refresh_city(c)
			if p == me:
				log_line("%s trains a %s." % [c.name, Data.UNIT[item["id"]]["name"]])
		"structure":
			c.structures.append(item["id"])
			refresh_city(c)
			if p == me:
				Snd.play("build")
				log_line("%s completes the %s." % [c.name, Data.STRUCTURE[item["id"]]["name"]], "good")
		_:
			var w: Dictionary = Data.WONDER[item["id"]]
			if wonder_taken(item["id"]):
				if p == me:
					log_line("Another nation completes %s before you." % w["name"], "war")
				c.queue = {}
				return false
			c.structures.append(item["id"])
			set_wonder_owner(item["id"], p.id)
			if not p.wonders.has(item["id"]):
				p.wonders.append(item["id"])
			if w.has("emp"):
				p.add_mods(w["emp"])
			refresh_city(c)
			log_line("%s completes %s." % [p.name, w["name"]], "big")
			if p == me:
				Snd.play("wonder")
				banner.emit(str(w["name"]), "raised in " + c.name)
			elif me != null and me.seen.has(c.coord):
				banner.emit(str(w["name"]), "raised by " + p.name)
			if w.has("once"):
				_wonder_hook(p, w["once"])
			if w.get("victory", false):
				end_run(p == me, "beacon")
				return true
	return true


func _wonder_hook(p: Player, id: String) -> void:
	match id:
		"free_bt":
			p.sci += Data.bt_cost(p.bt_done)
		"rank_all":
			for u in p.units:
				u.xp = maxi(u.xp, Data.RANK_XP[1] + 1)
				_apply_rank(u, p == me)
		"peace":
			for o in players:
				if o == p or o.is_barbarian:
					continue
				o.relation(p.id)["war"] = false
				o.relation(p.id)["attitude"] += 35.0
				p.relation(o.id)["war"] = false


# =========================================================================
#  Units
# =========================================================================
func spawn_unit(p: Player, type: String, c: Vector2i) -> Unit:
	var u := Unit.new()
	u.id = next_id
	next_id += 1
	u.owner_id = p.id
	u.type = type
	u.coord = c
	u.hp = Data.HP_MAX
	var t := world.at(c)
	t.units.append(u)
	p.units.append(u)
	u.mv = unit_moves(u)
	return u


func kill_unit(u: Unit, silent: bool = false) -> void:
	var t := world.at(u.coord)
	if t != null:
		t.units.erase(u)
	var p := player(u.owner_id)
	p.units.erase(u)
	u.dead = true
	if not silent and p == me:
		log_line("Your %s is destroyed." % Data.UNIT[u.type]["name"], "war")


func unit_moves(u: Unit) -> int:
	var p := player(u.owner_id)
	var d: Dictionary = Data.UNIT[u.type]
	var mv: float = d["mv"] + p.mod("mv_all") + u.promo_value("mv")
	if d["cls"] == "mounted":
		mv += p.mod("mv_mounted")
	if d["cls"] == "settler":
		mv += p.mod("mv_settler")
	return maxi(1, int(mv))


## ctx keys: attacking, defending, ranged, vs_city, tile, foe
func unit_strength(u: Unit, ctx: Dictionary) -> float:
	var p := player(u.owner_id)
	var d: Dictionary = Data.UNIT[u.type]
	var ranged: bool = ctx.get("ranged", false)
	var s: float = float(d.get("rs", 0)) if ranged else float(d["str"])
	if u.embarked and not ranged:
		s = maxf(8.0, s * 0.45)
	s += u.rank * 6.0
	s += p.mod("s_all")
	match d["cls"]:
		"melee": s += p.mod("s_melee")
		"ranged": s += p.mod("s_ranged")
		"mounted": s += p.mod("s_mounted")
		"siege": s += p.mod("s_siege")
	if d.get("gunpowder", false):
		s += p.mod("s_gp")
	if ranged:
		s += u.promo_value("rs")
	if ctx.get("attacking", false):
		s += u.promo_value("atk")
	if ctx.get("defending", false):
		s += u.promo_value("def")

	var mult := 1.0
	if ctx.get("attacking", false):
		mult += p.mod("pct_atk") + p.mod("pct_war")
	if ctx.get("defending", false):
		mult += p.mod("pct_war")
	if ctx.get("vs_city", false):
		mult += float(d.get("vs_city", 0.0)) + p.mod("pct_vs_city") + u.promo_value("vs_city")

	var tile = ctx.get("tile", null)
	if tile != null:
		if u.has_promo("rough") and tile.is_rough():
			mult += u.promo_value("rough")
		if ctx.get("defending", false):
			if tile.owner_id == p.id:
				mult += p.mod("pct_home")
			mult += tile.defence_bonus()
			if u.fortified > 0:
				mult += 0.30
			if tile.city != null:
				mult += 0.20
	var foe = ctx.get("foe", null)
	if ctx.get("defending", false) and foe != null and d.get("vs_mounted", false):
		if Data.UNIT[foe.type]["cls"] == "mounted":
			mult += 1.0
	return maxf(1.0, s * mult)


func unit_range(u: Unit) -> int:
	var p := player(u.owner_id)
	var d: Dictionary = Data.UNIT[u.type]
	if not d.has("rng"):
		return 0
	var r: int = int(d["rng"]) + int(u.promo_value("rng"))
	if d["cls"] == "siege":
		r += int(p.mod("rng_siege"))
	else:
		r += int(p.mod("rng_ranged"))
	return r


func can_embark(p: Player) -> bool:
	if p.mod("embark") > 0.0:
		return true
	if p.mod("early_embark") > 0.0 and p.age >= 1:
		return true
	return p.age >= 4


func can_enter(u: Unit, t: Tile) -> bool:
	if t == null or t.is_impassable():
		return false
	var p := player(u.owner_id)
	if t.is_water():
		if not can_embark(p):
			return false
		if t.city != null:
			return false
	return true


## "own" if a friendly unit of the same layer is there, "foe" if hostile.
func blocked_by(u: Unit, t: Tile) -> String:
	var civilian := u.is_civilian()
	for o in t.units:
		var o_civ: bool = Data.UNIT[o.type]["cls"] == "settler"
		if o.owner_id == u.owner_id:
			if o_civ == civilian:
				return "own"
		else:
			return "foe"
	if t.city != null and t.city.owner_id != u.owner_id:
		return "foe"
	return ""


func free_spot_for(p: Player, t: Tile, civilian: bool) -> Tile:
	var fits := func(x: Tile) -> bool:
		if x == null or x.is_impassable() or x.is_water():
			return false
		if x.city != null and x.city.owner_id != p.id:
			return false
		for o in x.units:
			if o.owner_id != p.id:
				return false
			if (Data.UNIT[o.type]["cls"] == "settler") == civilian:
				return false
		return true
	# prefer somewhere with room to walk out of: a unit spawned onto a dead
	# end can sit there unable to move for the whole run
	var roomy := func(x: Tile) -> bool:
		if not fits.call(x):
			return false
		for n in world.neighbours(x.coord):
			if not n.is_water() and not n.is_impassable() and n.units.is_empty():
				return true
		return false
	if roomy.call(t):
		return t
	for nb in world.neighbours(t.coord):
		if roomy.call(nb):
			return nb
	for nb2 in world.in_range(t.coord, 2):
		if roomy.call(nb2):
			return nb2
	# nothing roomy anywhere: take whatever is legal
	if fits.call(t):
		return t
	for nb3 in world.neighbours(t.coord):
		if fits.call(nb3):
			return nb3
	for nb4 in world.in_range(t.coord, 2):
		if fits.call(nb4):
			return nb4
	return null


func move_cost_for(u: Unit, t: Tile) -> int:
	if Data.UNIT[u.type].get("ignore_terrain", false) or u.has_promo("ignore_terrain"):
		return 1
	return t.move_cost()


# =========================================================================
#  Ranks and promotions — the second draft in the game
# =========================================================================
func _apply_rank(u: Unit, offer: bool) -> bool:
	var nr := 0
	if u.xp >= Data.RANK_XP[2]:
		nr = 3
	elif u.xp >= Data.RANK_XP[1]:
		nr = 2
	elif u.xp >= Data.RANK_XP[0]:
		nr = 1
	if nr <= u.rank:
		return false
	u.rank = nr
	u.hp = mini(Data.HP_MAX, u.hp + 25)
	var p := player(u.owner_id)
	if p.is_human:
		if offer:
			pending_promotions.append(u)
			unlock("promotion")
		else:
			_auto_promote(u)
	else:
		_auto_promote(u)
	return true


func promotion_choices(u: Unit) -> Array:
	var cls := u.cls()
	var pool: Array[String] = []
	for id in Data.PROMOTION:
		if u.promos.has(id):
			continue
		if not (Data.PROMOTION[id]["for"] as Array).has(cls):
			continue
		pool.append(id)
	rng.shuffle(pool)
	var out: Array = []
	for i in mini(2, pool.size()):
		out.append(pool[i])
	return out


func take_promotion(u: Unit, id: String) -> void:
	if id == "" or u.promos.has(id):
		return
	u.promos.append(id)
	u.mv = mini(unit_moves(u), u.mv + int(Data.PROMOTION[id]["m"].get("mv", 0)))
	if player(u.owner_id) == me:
		Snd.play("promote")
		log_line("%s becomes %s." % [Data.UNIT[u.type]["name"], Data.PROMOTION[id]["name"]], "good")


func _auto_promote(u: Unit) -> void:
	var choices := promotion_choices(u)
	if not choices.is_empty():
		u.promos.append(choices[0])


# =========================================================================
#  Movement
# =========================================================================
func zoc_tiles(p: Player) -> Dictionary:
	var z := {}
	for o in players:
		if o == p or not at_war(p, o):
			continue
		for u in o.units:
			if u.is_civilian():
				continue
			for nb in world.neighbours(u.coord):
				z[nb.coord] = true
	return z


## Dijkstra. `limit` caps movement for this turn; -1 means unlimited.
## `goal` is reached even when something hostile stands on it: you walk up
## to a city and then attack it. Without this no army could ever march.
func move_field(u: Unit, limit: int, goal: Vector2i, use_goal: bool) -> Dictionary:
	var p := player(u.owner_id)
	var start := u.coord
	var dist := {start: 0}
	var from := {}
	var zoc: Dictionary = {} if p.mod("ignore_zoc") > 0.0 else zoc_tiles(p)
	var border := int(p.mod("mv_border"))
	var frontier: Array = [start]

	while not frontier.is_empty():
		frontier.sort_custom(func(a, b): return int(dist.get(a, 99999)) < int(dist.get(b, 99999)))
		var cur: Vector2i = frontier.pop_front()
		var cd: int = dist[cur]
		if limit >= 0 and cd >= limit:
			continue
		if use_goal and cur == goal:
			continue
		var cur_tile := world.at(cur)
		for nb in world.neighbours(cur):
			var is_goal: bool = use_goal and nb.coord == goal
			if not is_goal:
				if not can_enter(u, nb):
					continue
				if blocked_by(u, nb) != "":
					continue
			var c := move_cost_for(u, nb)
			if nb.is_water() or cur_tile.is_water():
				c = 1
			if border > 0 and nb.owner_id == p.id and cur_tile.owner_id == p.id:
				c = maxi(1, c - border)
			var nd := cd + c
			if zoc.has(cur) and zoc.has(nb.coord):
				nd = limit if limit >= 0 else cd + c + 3
			if limit >= 0:
				nd = mini(nd, limit)
			if not dist.has(nb.coord) or nd < int(dist[nb.coord]):
				dist[nb.coord] = nd
				from[nb.coord] = cur
				frontier.append(nb.coord)
	return {"dist": dist, "from": from}


func reachable(u: Unit) -> Dictionary:
	if u.mv <= 0:
		return {}
	var f := move_field(u, u.mv, Vector2i.ZERO, false)
	var d: Dictionary = f["dist"]
	d.erase(u.coord)
	return d


func path_to(u: Unit, goal: Vector2i) -> Array:
	var f := move_field(u, -1, goal, true)
	var dist: Dictionary = f["dist"]
	var from: Dictionary = f["from"]
	if not dist.has(goal):
		return []
	var path: Array = []
	var k := goal
	while k != u.coord:
		path.push_front(k)
		if not from.has(k):
			return []
		k = from[k]
	return path


func step_unit(u: Unit, t: Tile) -> bool:
	if not can_enter(u, t) or blocked_by(u, t) != "":
		return false
	if u.mv <= 0:
		return false
	var p := player(u.owner_id)
	var cur := world.at(u.coord)
	var c := move_cost_for(u, t)
	if t.is_water() or cur.is_water():
		c = 1
	var border := int(p.mod("mv_border"))
	if border > 0 and t.owner_id == p.id and cur.owner_id == p.id:
		c = maxi(1, c - border)
	c = mini(c, maxi(1, u.mv))

	cur.units.erase(u)
	u.coord = t.coord
	t.units.append(u)
	u.mv -= c
	u.fortified = 0
	u.embarked = t.is_water()
	u.moved_this_turn = true

	if p.mod("ignore_zoc") <= 0.0:
		var zoc := zoc_tiles(p)
		if zoc.has(cur.coord) and zoc.has(t.coord):
			u.mv = 0
	if p == me:
		Snd.play("move")
	if t.ruin and not p.is_barbarian:
		_pop_ruin(p, t, u)
	if t.camp and not p.is_barbarian:
		t.camp = false
		p.gold += 40
		if p == me:
			log_line("You clear a raider camp. +40 gold.", "good")
	return true


func _pop_ruin(p: Player, t: Tile, u: Unit) -> void:
	t.ruin = false
	var roll := rng.below(100)
	if roll < 26:
		var g := rng.irange(30, 70)
		p.gold += g
		if p == me:
			log_line("Ruins yield %d gold." % g, "good")
	elif roll < 50:
		var s := int(Data.bt_cost(p.bt_done) * 0.34)
		p.sci += s
		if p == me:
			log_line("Ruins yield old knowledge. +%d progress." % s, "good")
	elif roll < 66:
		u.xp += 30
		_apply_rank(u, p.is_human)
		if p == me:
			log_line("Your %s learns from the ruins." % Data.UNIT[u.type]["name"], "good")
	elif roll < 80:
		world.see_from(p, t, 6, true)
		if p == me:
			log_line("A map fragment reveals the land around.", "good")
	elif roll < 92:
		var spot := free_spot_for(p, t, false)
		if spot != null:
			var nu := spawn_unit(p, real_unit(p, "warrior"), spot.coord)
			if p == me:
				log_line("Wanderers join you: a %s." % Data.UNIT[nu.type]["name"], "good")
		else:
			p.gold += 40
	else:
		var spot2 := free_spot_for(p, t, true)
		if spot2 != null and p.cities.size() < p.city_cap():
			spawn_unit(p, "settler", spot2.coord)
			if p == me:
				log_line("A lost people ask to follow you. A Settler joins!", "good")
		else:
			p.sci += int(Data.bt_cost(p.bt_done) * 0.3)


# =========================================================================
#  Combat
# =========================================================================
func combat_odds(attack: float, defend: float) -> int:
	return int(round(100.0 / (1.0 + exp(-0.05 * (attack - defend)))))


func damage_roll(a: float, d: float) -> int:
	var raw := 30.0 * exp(0.036 * (a - d)) * (0.88 + rng.nextf() * 0.24)
	return clampi(int(round(raw)), 2, 95)


func at_war(a: Player, b: Player) -> bool:
	if a == b:
		return false
	if a.is_barbarian or b.is_barbarian:
		return true
	return a.relation(b.id)["war"]


func melee_attack(u: Unit, t: Tile) -> bool:
	var p := player(u.owner_id)
	if t.city != null and t.city.owner_id != u.owner_id:
		return attack_city(u, t.city, t)
	var foe = t.military()
	if foe == null:
		foe = t.civilian()
	if foe == null:
		return false
	var d_player := player(foe.owner_id)
	if not at_war(p, d_player):
		return false

	# an undefended civilian is simply taken
	if Data.UNIT[foe.type]["cls"] == "settler" and t.military() == null:
		kill_unit(foe, true)
		if d_player == me:
			log_line("Your %s is captured by %s!" % [Data.UNIT[foe.type]["name"], p.name], "war")
		elif p == me:
			log_line("You capture a %s." % Data.UNIT[foe.type]["name"], "good")
		u.mv = maxi(0, u.mv - 1)
		step_unit(u, t)
		return true

	var here := world.at(u.coord)
	var a := unit_strength(u, {"attacking": true, "foe": foe, "tile": here})
	var d := unit_strength(foe, {"defending": true, "tile": t, "foe": u})
	var dd := damage_roll(a, d)
	var da := damage_roll(d, a)
	foe.hp -= dd
	u.hp -= da
	attack_made.emit(u.coord, t.coord, false)
	_combat_fx(t.coord, dd)
	u.mv = 0
	u.fortified = 0
	u.fought_this_turn = true
	u.xp += 6
	foe.xp += 5
	unlock("combat")

	if foe.hp <= 0 and u.hp <= 0:
		if rng.chance(0.5):
			u.hp = 1
		else:
			foe.hp = 1
	if foe.hp <= 0:
		_on_kill(p, d_player, foe, u)
		kill_unit(foe)
		if t.military() == null and t.city == null:
			var civ2 = t.civilian()
			if civ2 != null and civ2.owner_id != u.owner_id:
				kill_unit(civ2, true)
			if u.has_promo("move_after") or p.mod("move_after") > 0.0:
				u.mv = 1
			step_unit(u, t)
	elif u.hp <= 0:
		kill_unit(u)
		foe.xp += 4
		_apply_rank(foe, d_player.is_human)
		d_player.kills += 1
	_apply_rank(u, p.is_human)
	if not foe.dead:
		_apply_rank(foe, d_player.is_human)
	return true


func ranged_attack(u: Unit, t: Tile) -> bool:
	var p := player(u.owner_id)
	var foe = t.military()
	if foe == null:
		foe = t.civilian()
	var city_here = t.city if (t.city != null and t.city.owner_id != u.owner_id) else null
	if foe == null and city_here == null:
		return false
	var d_player := player(city_here.owner_id) if city_here != null else player(foe.owner_id)
	if not at_war(p, d_player):
		return false
	var here := world.at(u.coord)
	attack_made.emit(u.coord, t.coord, true)
	var a := unit_strength(u, {"attacking": true, "ranged": true,
		"vs_city": city_here != null and foe == null, "foe": foe, "tile": here})
	if foe != null:
		var d := unit_strength(foe, {"defending": true, "tile": t, "foe": u})
		var dd := damage_roll(a, d)
		foe.hp -= dd
		_combat_fx(t.coord, dd)
		u.xp += 5
		foe.xp += 3
		if foe.hp <= 0:
			_on_kill(p, d_player, foe, u)
			kill_unit(foe)
		else:
			_apply_rank(foe, d_player.is_human)
	else:
		var dc := int(round(damage_roll(a, city_defence(city_here)) * 1.15))
		city_here.hp = maxi(0, city_here.hp - dc)
		_combat_fx(t.coord, dc)
		u.xp += 4
	u.mv = 0
	u.fortified = 0
	u.fought_this_turn = true
	unlock("combat")
	_apply_rank(u, p.is_human)
	return true


func attack_city(u: Unit, c: City, t: Tile) -> bool:
	var p := player(u.owner_id)
	var d_player := player(c.owner_id)
	if not at_war(p, d_player):
		return false
	var garrison = t.military()
	if garrison != null:
		return _attack_garrison(u, garrison, t, c)
	var cls := u.cls()
	if c.hp > 0:
		var here := world.at(u.coord)
		var a := unit_strength(u, {"attacking": true, "vs_city": true, "tile": here})
		var d := city_defence(c)
		var dd := damage_roll(a, d)
		var da := int(round(damage_roll(d, a) * 0.75))
		c.hp = maxi(0, c.hp - dd)
		u.hp -= da
		attack_made.emit(u.coord, t.coord, false)
		_combat_fx(t.coord, dd)
		u.mv = 0
		u.fought_this_turn = true
		u.xp += 6
		_apply_rank(u, p.is_human)
		if u.hp <= 0:
			kill_unit(u)
			return true
		if c.hp <= 0 and cls != "ranged" and cls != "siege":
			capture_city(p, c, u)
		return true
	if cls == "ranged" or cls == "siege":
		return false
	capture_city(p, c, u)
	return true


func _attack_garrison(u: Unit, foe: Unit, t: Tile, c: City) -> bool:
	var p := player(u.owner_id)
	var d_player := player(foe.owner_id)
	var here := world.at(u.coord)
	var a := unit_strength(u, {"attacking": true, "foe": foe, "vs_city": true, "tile": here})
	var d := defence_at(t, u)
	var dd := damage_roll(a, d)
	var da := damage_roll(d, a)
	foe.hp -= dd
	u.hp -= da
	c.hp = maxi(0, c.hp - int(round(dd * 0.5)))
	attack_made.emit(u.coord, t.coord, false)
	_combat_fx(t.coord, dd)
	u.mv = 0
	u.fought_this_turn = true
	u.xp += 6
	foe.xp += 5
	if foe.hp <= 0:
		_on_kill(p, d_player, foe, u)
		kill_unit(foe)
	if u.hp <= 0:
		kill_unit(u)
		d_player.kills += 1
	if not u.dead:
		_apply_rank(u, p.is_human)
	if not foe.dead:
		_apply_rank(foe, d_player.is_human)
	return true


func _on_kill(p: Player, d_player: Player, foe: Unit, killer: Unit) -> void:
	p.kills += 1
	p.gold += int(p.mod("kill_gold"))
	p.sci += int(p.mod("kill_sci"))
	if killer != null:
		killer.xp += 14
		var heal := p.mod("heal_win") + killer.promo_value("heal_kill")
		if heal > 0.0:
			killer.hp = mini(Data.HP_MAX, killer.hp + int(heal))
		_apply_rank(killer, p.is_human)
	if p == me or d_player == me:
		Snd.play("kill")
	if d_player == me:
		log_line("Your %s falls to %s." % [Data.UNIT[foe.type]["name"], p.name], "war")
	elif p == me:
		log_line("You destroy a %s %s." % [d_player.name, Data.UNIT[foe.type]["name"]], "good")


func capture_city(p: Player, c: City, u: Unit) -> void:
	var d_player := player(c.owner_id)
	var t := world.at(c.coord)
	var was_capital := c.is_capital
	d_player.cities.erase(c)
	c.owner_id = p.id
	c.pop = maxi(1, int(c.pop * 0.6))
	c.is_capital = false
	c.just_taken = 3
	c.queue = {}
	c.prod = 0
	c.food = 0
	if p.mod("keep_structs") <= 0.0:
		var kept: Array[String] = []
		for s in c.structures:
			if Data.WONDER.has(s):
				kept.append(s)
		c.structures = kept
	# wonders change hands exactly once; recapturing must not stack their effects
	for s in c.structures:
		if not Data.WONDER.has(s) or wonder_owner(s) == p.id:
			continue
		var prev := player(wonder_owner(s))
		if prev == null:
			prev = d_player
		set_wonder_owner(s, p.id)
		var w: Dictionary = Data.WONDER[s]
		if w.has("emp"):
			p.add_mods(w["emp"])
			if prev != null and prev != p:
				prev.subtract_mods(w["emp"])
		if prev != null:
			prev.wonders.erase(s)
		d_player.wonders.erase(s)
		if not p.wonders.has(s):
			p.wonders.append(s)
	p.cities.append(c)
	captures += 1
	refresh_city(c)
	c.hp = int(c.max_hp * 0.4)
	if u != null:
		u.mv = 0
		step_unit(u, t)
	world.recompute_territory(players)
	if p == me:
		Snd.play("capture")
	elif d_player == me:
		Snd.play("lost")
	log_line("%s captures %s!" % [p.name, c.name], "war")
	if d_player == me:
		banner.emit("%s is lost" % c.name,
			"taken by %s" % p.name if not was_capital else "your capital has fallen")
	elif p == me:
		banner.emit("%s is yours" % c.name, "taken from %s" % d_player.name)
	if was_capital:
		p.captured_capitals += 1
		if not d_player.cities.is_empty():
			d_player.cities[0].is_capital = true
			d_player.capital = d_player.cities[0]
	if d_player.cities.is_empty():
		_eliminate(d_player)
	check_end()


func _eliminate(d_player: Player) -> void:
	d_player.alive = false
	for u in d_player.units.duplicate():
		kill_unit(u, true)
	if not d_player.is_barbarian:
		log_line("%s is no more." % d_player.name, "big")


func _combat_fx(c: Vector2i, damage: int) -> void:
	combat_happened.emit(c, damage)
	if me != null and me.vis.has(c):
		Snd.play("hit")


# =========================================================================
#  Progress, ages and the draft
# =========================================================================
func grant_progress(p: Player, amount: int) -> void:
	p.sci += amount
	var guard := 0
	while p.sci >= Data.bt_cost(p.bt_done) \
			and p.bt_done < Data.BT_PER_AGE * Data.AGES.size() and guard < 8:
		guard += 1
		p.sci -= Data.bt_cost(p.bt_done)
		p.bt_done += 1
		var new_age := mini(Data.LAST_AGE, int(p.bt_done / Data.BT_PER_AGE))
		var aged := new_age > p.age
		p.age = new_age
		if p.is_human:
			pending_drafts += 1
			unlock("edicts")
			if aged:
				Snd.play("age")
				banner.emit("The %s Age" % Data.AGES[p.age]["name"], Data.AGES[p.age]["sub"])
			else:
				Snd.play("draft")
		else:
			_ai_draft(p)
			if aged:
				log_line("%s enters the %s Age." % [p.name, Data.AGES[p.age]["name"]])


func draft_pool(p: Player) -> Array:
	var taken := {}
	for e in p.edicts:
		taken[e] = true
	var pool: Array = []
	var a := p.age
	while a >= 0 and pool.size() < 3:
		for e in EdictData.LIST[a]:
			if not taken.has(e["id"]):
				pool.append(e)
		a -= 1
	if pool.is_empty():
		return []
	rng.shuffle(pool)
	return pool.slice(0, mini(3, pool.size()))


func take_edict(p: Player, e: Dictionary) -> void:
	p.edicts.append(e["id"])
	if e.has("m"):
		p.add_mods(e["m"])
	if e.has("once"):
		_edict_hook(p, e["once"])
	if p == me:
		Snd.play("edict")
		log_line("Edict adopted: %s." % e["name"], "big")
	world.recompute_territory(players)
	world.recompute_vision(p)


func _edict_hook(p: Player, id: String) -> void:
	match id:
		"reveal":
			p.m["reveal_all"] = 1.0
			for t in world.list:
				p.seen[t.coord] = true
		"uranium":
			p.m["uranium_all"] = 1.0
		"spy":
			for o in players:
				if o == p:
					continue
				for c in o.cities:
					var t := world.at(c.coord)
					if t != null:
						world.see_from(p, t, 1, true)
		"endwars":
			for o in players:
				if o == p or o.is_barbarian:
					continue
				p.relation(o.id)["war"] = false
				o.relation(p.id)["war"] = false
				o.relation(p.id)["truce"] = turn + 15
			log_line("Every war ends at once.", "big")


func _ai_draft(p: Player) -> void:
	var options := draft_pool(p)
	if options.is_empty():
		return
	var best: Dictionary = options[0]
	var best_score := -1e9
	var agenda: String = p.leader.get("agenda", "")
	for e in options:
		var s := rng.nextf() * 8.0
		var m: Dictionary = e.get("m", {})
		for k in m:
			var v := float(m[k])
			if k.begins_with("s_") or k.begins_with("pct_atk") or k == "pct_war" \
					or k == "pct_vs_city" or k == "city_str" or k == "city_hp":
				s += v * (2.4 if agenda == "conqueror" or agenda == "raider" else 1.3)
			elif k == "pct_sci" or k == "p_sci" or k == "cap_sci" or k == "sci_per_pop":
				s += v * (26.0 if agenda == "scholar" else 16.0)
			elif k == "pct_gold" or k == "p_gold" or k == "buy_pct":
				s += absf(v) * (22.0 if agenda == "tributary" else 14.0)
			elif k == "pct_prod" or k == "p_prod" or k == "unit_pct" or k == "struct_pct":
				s += absf(v) * 20.0
			elif k == "p_food" or k.begins_with("t_food"):
				s += v * (20.0 if agenda == "builder" else 15.0)
			elif k == "city_cap":
				s += v * 30.0
			elif k == "diplo":
				s += v * (1.4 if agenda == "peaceful" else 0.5)
			else:
				s += absf(v) * 6.0
		if s > best_score:
			best_score = s
			best = e
	take_edict(p, best)


# =========================================================================
#  Diplomacy
# =========================================================================
func meet(a: Player, b: Player) -> void:
	var ra := a.relation(b.id)
	var rb := b.relation(a.id)
	if ra["met"]:
		return
	ra["met"] = true
	rb["met"] = true
	ra["attitude"] = a.mod("diplo") + (10.0 if a.leader.get("agenda", "") == "peaceful" else 0.0)
	rb["attitude"] = b.mod("diplo") + (10.0 if b.leader.get("agenda", "") == "peaceful" else 0.0)
	if a == me or b == me:
		var o: Player = b if a == me else a
		unlock("diplomacy")
		log_line("You meet %s, who leads %s." % [o.leader["name"], o.name], "big")
		banner.emit("You meet " + o.leader["name"], "of " + o.name)


func check_meetings() -> void:
	for a in players:
		if a.is_barbarian or not a.alive:
			continue
		for b in players:
			if b == a or b.is_barbarian or not b.alive:
				continue
			if a.relation(b.id)["met"]:
				continue
			var close := false
			var a_spots: Array = []
			for u in a.units:
				a_spots.append(u.coord)
			for c in a.cities:
				a_spots.append(c.coord)
			var b_spots: Array = []
			for u in b.units:
				b_spots.append(u.coord)
			for c in b.cities:
				b_spots.append(c.coord)
			for x in a_spots:
				for y in b_spots:
					if Hex.distance(x, y) <= 4:
						close = true
						break
				if close:
					break
			if close:
				meet(a, b)


func declare_war(a: Player, b: Player) -> void:
	var ra := a.relation(b.id)
	var rb := b.relation(a.id)
	if ra["war"]:
		return
	ra["war"] = true
	rb["war"] = true
	ra["attitude"] -= 30.0
	rb["attitude"] -= 45.0
	for o in players:
		if o == a or o == b or o.is_barbarian:
			continue
		var r: Dictionary = o.relation(a.id)
		r["attitude"] -= 14.0 if o.leader.get("agenda", "") == "peaceful" else 6.0
	if a == me or b == me:
		Snd.play("war")
	if b == me:
		log_line("%s declares war on you!" % a.name, "war")
		banner.emit(a.name + " declares war", "the " + str(a.leader["name"]) + " host is marching")
	elif a == me:
		log_line("You declare war on %s." % b.name, "war")
	else:
		log_line("%s declares war on %s." % [a.name, b.name], "war")


func make_peace(a: Player, b: Player) -> void:
	var ra := a.relation(b.id)
	var rb := b.relation(a.id)
	ra["war"] = false
	rb["war"] = false
	ra["truce"] = turn + 12
	rb["truce"] = turn + 12
	ra["attitude"] += 12.0
	rb["attitude"] += 12.0
	if a == me or b == me:
		log_line("Peace between %s and %s." % [a.name, b.name], "good")


func military_power(p: Player) -> int:
	var s := 0.0
	for u in p.units:
		if u.is_civilian():
			continue
		s += (float(Data.UNIT[u.type]["str"]) + u.rank * 6.0) * (float(u.hp) / Data.HP_MAX)
	return int(round(s))


func empire_power(p: Player) -> int:
	return military_power(p) + p.cities.size() * 22 + p.age * 18


func attitude_word(a: float) -> String:
	if a >= 55.0: return "Devoted"
	if a >= 25.0: return "Friendly"
	if a >= -10.0: return "Neutral"
	if a >= -40.0: return "Wary"
	if a >= -70.0: return "Hostile"
	return "Furious"


# =========================================================================
#  The turn
# =========================================================================
## What an army costs to keep standing.
##
## Soldiers past the allowance cost a gold a turn each. Settlers are not
## soldiers and are not counted.  See army_cap() for the hard limit.
func upkeep_of(p: Player) -> int:
	var over := maxi(0, army_size(p) - army_free(p))
	return maxi(0, int(round(over * (1.0 + p.mod("upkeep_pct")))))


## Soldiers the empire keeps for nothing.
func army_free(p: Player) -> int:
	return 2 + p.cities.size() * (1 + int(p.mod("upkeep_free")))


## The most soldiers an empire may field.
##
## One unit to a tile makes a large army a chore to move rather than a
## pleasure to command, so there is a ceiling on it, and the way to raise the
## ceiling is to hold more ground. It keeps the turn short and it makes taking
## a city worth something beyond the city.
func army_cap(p: Player) -> int:
	return 3 + p.cities.size() + int(p.mod("army_cap"))


func army_size(p: Player) -> int:
	var n := 0
	for u in p.units:
		if not u.is_civilian():
			n += 1
	return n


func empire_rates(p: Player) -> Dictionary:
	var gold := 0
	var sci := 0
	for c in p.cities:
		var y := city_yield(c)
		gold += y.z
		sci += y.w
	gold -= upkeep_of(p)
	return {"gold": gold, "sci": sci}


func city_turn(c: City) -> Vector2i:
	var p := player(c.owner_id)
	assign_tiles(c)
	var y := city_yield(c)
	var bonus: float = 1.0 if p.is_human else diff()["ai"]

	# tiles improve simply by being worked: this is why there are no workers
	var cap := 3 if p.age >= 4 else (2 if p.age >= 2 else 1)
	for t in c.worked:
		t.worked_turns += 1
		var lvl := 0
		if t.worked_turns >= 52: lvl = 3
		elif t.worked_turns >= 26: lvl = 2
		elif t.worked_turns >= 9: lvl = 1
		t.improve = mini(cap, lvl)

	c.food += y.x
	if c.food < 0:
		if c.pop > 1:
			c.pop -= 1
			c.food = int(Data.food_needed(c.pop) * 0.5)
			refresh_city(c)
			if p == me:
				log_line("%s starves and shrinks." % c.name, "war")
		else:
			c.food = 0
	elif c.food >= Data.food_needed(c.pop) and c.pop < city_max_pop(c):
		c.food -= Data.food_needed(c.pop)
		c.pop += 1
		refresh_city(c)

	if c.just_taken > 0:
		c.just_taken -= 1
	else:
		c.prod += int(round(y.y * bonus))
		if c.queue.is_empty() and not p.is_human:
			_ai.pick_build(self, c)
		if not c.queue.is_empty():
			var need := item_cost(p, c.queue)
			if c.prod >= need:
				var item := c.queue
				if complete_item(c, item):
					c.prod -= need
					c.queue = {}
					if not p.is_human:
						_ai.pick_build(self, c)

	# walls knit back together, but not with an enemy at the gate
	var besieged := false
	for nb in world.neighbours(c.coord):
		for u in nb.units:
			if not u.is_civilian() and at_war(p, player(u.owner_id)):
				besieged = true
				break
		if besieged:
			break
	if c.hp < c.max_hp and not besieged:
		c.hp = mini(c.max_hp, c.hp + int(round(c.max_hp * 0.07)) + 2)
	return Vector2i(y.z, y.w)


func player_end_turn(p: Player) -> void:
	if not p.alive:
		return
	var gold := 0
	var sci := 0
	for c in p.cities.duplicate():
		var gs := city_turn(c)
		gold += gs.x
		sci += gs.y
	var bonus: float = 1.0 if p.is_human else diff()["ai"]
	gold -= upkeep_of(p)
	p.gold += int(round(gold * bonus))
	if p.gold < 0:
		p.gold = 0
		var weakest = null
		for u in p.units:
			if u.is_civilian():
				continue
			if weakest == null or Data.UNIT[u.type]["str"] < Data.UNIT[weakest.type]["str"]:
				weakest = u
		if weakest != null:
			if p == me:
				log_line("The treasury is empty — a %s disbands." % Data.UNIT[weakest.type]["name"], "war")
			kill_unit(weakest, true)
	grant_progress(p, int(round(sci * bonus)))

	for u in p.units:
		var t := world.at(u.coord)
		if not u.moved_this_turn and not u.fought_this_turn and u.hp < Data.HP_MAX:
			var h := 7
			if t != null and t.owner_id == p.id:
				h = 13
			if t != null and t.city != null and t.city.owner_id == p.id:
				h = 24
			if u.fortified > 0:
				h += 4
			if u.embarked:
				h = 0
			u.hp = mini(Data.HP_MAX, u.hp + h)
		u.mv = unit_moves(u)
		u.done = false
		u.moved_this_turn = false
		u.fought_this_turn = false
		if u.fortified > 0:
			u.fortified = mini(3, u.fortified + 1)
	world.recompute_territory(players)
	world.recompute_vision(p)


func run_turn() -> void:
	for p in players:
		if not p.is_human and not p.is_barbarian and p.alive:
			_ai.take_turn(self, p)
	_ai.barbarian_turn(self)
	check_meetings()
	for p in players:
		if p.alive:
			player_end_turn(p)
	turn += 1
	_prune_dead()
	_maybe_event()
	autosave()
	if turn > Data.MAX_TURNS and not over:
		var mine := score_of(me)
		var best := 0
		for p in rivals():
			best = maxi(best, score_of(p))
		end_run(mine >= best, "time")
	check_end()


# =========================================================================
#  Events — a choice every dozen turns, between the Edicts
# =========================================================================
func _maybe_event() -> void:
	if over or me == null or not me.is_human:
		return
	if turn < next_event_turn or not pending_event.is_empty():
		return
	var pool: Array = []
	for e in EventData.LIST:
		if not events_seen.has(e["id"]):
			pool.append(e)
	if pool.is_empty():
		next_event_turn = Data.MAX_TURNS + 1
		return
	pending_event = pool[rng.below(pool.size())]
	events_seen.append(str(pending_event["id"]))
	next_event_turn = turn + 10 + rng.below(5)
	unlock("events")


func take_event_option(p: Player, option: Dictionary) -> void:
	if option.has("gold"):
		p.gold = maxi(0, p.gold + int(option["gold"]))
	if option.has("gold_per_city"):
		p.gold += int(option["gold_per_city"]) * maxi(1, p.cities.size())
	if option.has("progress"):
		grant_progress(p, Data.bt_cost(p.bt_done) * int(option["progress"]))
	if option.has("m"):
		p.add_mods(option["m"])
	if option.has("pop_capital") and p.capital != null:
		p.capital.pop = maxi(1, p.capital.pop + int(option["pop_capital"]))
		refresh_city(p.capital)
	if option.has("pop_all"):
		for c in p.cities:
			c.pop = maxi(1, c.pop + int(option["pop_all"]))
			refresh_city(c)
	if option.has("xp_all"):
		for u in p.units:
			if u.is_civilian():
				continue
			u.xp += int(option["xp_all"])
			_apply_rank(u, p.is_human)
	if option.has("heal_all"):
		for u in p.units:
			u.hp = Data.HP_MAX
	if option.has("diplo_all"):
		for o in players:
			if o == p or o.is_barbarian:
				continue
			var rel := o.relation(p.id)
			rel["attitude"] = clampf(float(rel["attitude"]) + float(option["diplo_all"]), -100.0, 100.0)
	if option.has("reveal") and p.capital != null:
		var t := world.at(p.capital.coord)
		if t != null:
			world.see_from(p, t, int(option["reveal"]) + 3, true)
	if option.has("unit"):
		_gift_unit(p, str(option["unit"]), int(option.get("unit_xp", 0)))
	if option.has("unit2"):
		_gift_unit(p, str(option["unit2"]), int(option.get("unit_xp", 0)))
	world.recompute_territory(players)
	world.recompute_vision(p)
	pending_event = {}
	state_changed.emit()


## A free unit of a line, the best of it the player could plausibly field.
func _gift_unit(p: Player, line_name: String, xp: int) -> void:
	if p.capital == null:
		return
	var line: Array = Data.LINES.get(line_name, [])
	var pick := ""
	for i in range(line.size() - 1, -1, -1):
		var key = line[i]
		if key == null or Data.UNIT[key]["age"] > p.age:
			continue
		var real := real_unit(p, key)
		if Data.UNIT[real].has("req") and not has_resource(p, Data.UNIT[real]["req"]):
			continue
		pick = real
		break
	if pick == "":
		pick = real_unit(p, "warrior")
	var t := world.at(p.capital.coord)
	var spot := free_spot_for(p, t, false)
	if spot == null:
		p.gold += 120
		return
	var u := spawn_unit(p, pick, spot.coord)
	u.xp = xp
	_apply_rank(u, false)
	log_line("A %s joins you." % Data.UNIT[pick]["name"], "good")


## Written after every turn so a run survives closing the window.
func autosave() -> void:
	if over or me == null or not me.is_human:
		return
	Save.write(self)


func _prune_dead() -> void:
	for p in players:
		if p.is_barbarian or not p.alive:
			continue
		if p.cities.is_empty() and p.units.is_empty():
			_eliminate(p)
		elif p.cities.is_empty() and p.lost_all_on >= 0 and turn - p.lost_all_on > 8:
			_eliminate(p)
		if p.cities.is_empty() and p.lost_all_on < 0:
			p.lost_all_on = turn


# =========================================================================
#  Ending
# =========================================================================
func score_of(p: Player) -> int:
	var s := 0
	s += p.cities.size() * 38
	for c in p.cities:
		s += c.pop * 7
	s += p.edicts.size() * 26
	s += p.wonders.size() * 65
	s += p.age * 90
	s += int(p.gold / 12.0)
	s += p.kills * 6
	s += p.captured_capitals * 170
	return s


func check_end() -> void:
	if over:
		return
	if me.cities.is_empty():
		end_run(false, "wiped")
		return
	if living_rivals().is_empty():
		end_run(true, "conquest")
		return
	# You do not have to hunt down every last village. Hold half the world and
	# the rest of it is only arguing about when to admit it.
	var total := 0
	for p in players:
		if not p.is_barbarian:
			total += p.cities.size()
	if total >= 6 and me.cities.size() * 2 >= total:
		end_run(true, "dominion")


func end_run(won: bool, how: String) -> void:
	if over:
		return
	over = true
	end_how = how
	end_won = won
	Save.clear()
	me.score = score_of(me)
	Snd.play("win" if won else "lost")
	run_ended.emit(won, how)


# =========================================================================
#  Coaching — one short line at a time, and only until it is done
# =========================================================================
func current_hint() -> Dictionary:
	if over or me == null:
		return {}
	var settler = null
	for u in me.units:
		if u.is_civilian():
			settler = u
			break

	if not hints_done.has("move") and turn <= 3:
		return {"id": "move", "text": "Click a unit, then a tile, to move it."}
	if settler != null and me.cities.size() < me.city_cap() and not hints_done.has("settle"):
		return {"id": "settle", "text": "Your Settler founds cities. Green rings show where one may stand."}
	if not me.cities.is_empty() and me.cities[0].queue.is_empty() and not hints_done.has("build"):
		return {"id": "build", "text": "Your city is idle. Click it and choose something to build."}
	if pending_drafts > 0:
		return {"id": "draft", "text": "A Breakthrough is waiting. Choose an Edict."}
	if is_unlocked("events") and not hints_done.has("events"):
		return {"id": "events",
			"text": "Things will happen to you between Edicts. Those choices are permanent too."}
	if is_unlocked("diplomacy") and not hints_done.has("diplo"):
		return {"id": "diplo", "text": "You have met a rival. Open Nations to see what they make of you."}
	if is_unlocked("combat") and not hints_done.has("fight"):
		return {"id": "fight", "text": "Red rings are targets. A city must be beaten to zero, then entered."}
	if turn >= 12 and me.units.size() <= 2 and not hints_done.has("army"):
		return {"id": "army", "text": "You have almost no army. An empty border invites a war."}
	return {}


func dismiss_hint(id: String) -> void:
	hints_done[id] = true


# =========================================================================
#  Where a city may stand, and how good it would be
# =========================================================================
func can_found_here(p: Player, t: Tile) -> bool:
	if t == null or t.is_water() or t.is_impassable():
		return false
	if t.city != null:
		return false
	if p.cities.size() >= p.city_cap():
		return false
	for o in players:
		for c in o.cities:
			if Hex.distance(t.coord, c.coord) < 3:
				return false
	if t.owner_id >= 0 and t.owner_id != p.id:
		return false
	return true


## A rough appraisal of a site. `p` may be null at map-generation time.
func site_score(p: Player, t: Tile) -> float:
	if t.is_water() or t.is_impassable() or t.city != null:
		return -1e9
	for o in players:
		for c in o.cities:
			if Hex.distance(t.coord, c.coord) < 3:
				return -1e9
	if p != null and t.owner_id >= 0 and t.owner_id != p.id:
		return -1e9

	var s := 0.0
	for n in world.in_range(t.coord, 2):
		var y := world.tile_yield(n, p)
		var d := Hex.distance(t.coord, n.coord)
		var w := 1.6 if d == 0 else (1.2 if d == 1 else 0.75)
		s += (y.x * 1.5 + y.y * 1.6 + y.z * 0.7) * w
		if n.resource != "" and world.resource_visible(n, p):
			s += 7.0 if Data.RESOURCE[n.resource]["kind"] == "s" else 4.0
	if world.is_fresh_water(t):
		s += 12.0
	if world.is_coastal(t.coord):
		s += 7.0
	if t.elev == "hill":
		s += 6.0
	if t.terrain == "snow" or t.terrain == "desert":
		s -= 8.0
	return s


func best_site_near(p: Player, from: Vector2i, max_dist: int) -> Tile:
	var best: Tile = null
	var best_score := -1e9
	for t in world.list:
		if not p.is_barbarian and not p.seen.has(t.coord):
			continue
		var d := Hex.distance(from, t.coord)
		if d > max_dist:
			continue
		var s := site_score(p, t)
		if s <= -1e8:
			continue
		s -= d * 2.2
		if s > best_score:
			best_score = s
			best = t
	return best


## Threat felt at a point, used by the AI to decide what a city builds.
func threat_at(p: Player, c: Vector2i) -> float:
	var th := 0.0
	for o in players:
		if o == p or not at_war(p, o):
			continue
		for u in o.units:
			var d := Hex.distance(c, u.coord)
			if d <= 6:
				th += (float(Data.UNIT[u.type]["str"]) + u.rank * 6.0) / (1.0 + d)
	return th


func upgrade_for(p: Player, u: Unit) -> String:
	var d: Dictionary = Data.UNIT[u.type]
	var base: String = d.get("replaces", u.type)
	var line: Array = Data.LINES.get(d["cls"], [])
	var i := line.find(base)
	if i < 0:
		return ""
	for j in range(line.size() - 1, i, -1):
		var nx = line[j]
		if nx == null or nx == base:
			continue
		var real := real_unit(p, nx)
		if real == u.type:
			continue
		if Data.UNIT[nx]["age"] <= p.age and (not Data.UNIT[real].has("req") or has_resource(p, Data.UNIT[real]["req"])):
			return real
	return ""


func upgrade_cost(p: Player, u: Unit, to: String) -> int:
	return maxi(20, int(round((unit_cost(p, to) - unit_cost(p, u.type)) * 1.4 + 20)))


# =========================================================================
#  Things a rival wants to say to you, handled by the interface next frame
# =========================================================================
## AI.gd is typed against GameRules, so naming it here at parse time would
## be circular. Load the script instead and dispatch dynamically.
var _ai: GDScript = null


func _ready() -> void:
	_ai = load("res://scripts/AI.gd")


var pending_tribute_demand: Player = null
var pending_peace_offer: Player = null
