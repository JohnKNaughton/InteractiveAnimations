class_name Save
extends RefCounted

## Saving and resuming a run.
##
## The map is not stored: it is regenerated from the seed, which is
## deterministic, and only the things play has changed since (improvements,
## cleared ruins and camps) are written down. Everything else is the empires.

## Not a const: a dev run redirects this so testing can never overwrite the
## save belonging to whoever is actually playing.
static var PATH := "user://autosave.json"
const VERSION := 1


static func use_dev_slot() -> void:
	PATH = "user://dev_autosave.json"


static func is_dev() -> bool:
	return PATH != "user://autosave.json"


static func exists() -> bool:
	return FileAccess.file_exists(PATH)


static func clear() -> void:
	if exists():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


static func describe() -> String:
	## A one-line summary for the "continue" button, without loading the run.
	if not exists():
		return ""
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return ""
	var raw = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(raw) != TYPE_DICTIONARY or not raw.has("summary"):
		return ""
	return str(raw["summary"])


# =========================================================================
#  Writing
# =========================================================================
static func write(g: GameRules) -> bool:
	if g.world == null or g.me == null or g.over:
		return false
	var d := {
		"version": VERSION,
		"seed": g.seed_value,
		"difficulty": g.difficulty,
		"turn": g.turn,
		"next_id": g.next_id,
		"rng": g.rng.state(),
		"wonders_built": g.wonders_built.duplicate(),
		"unlocked": g.unlocked.duplicate(),
		"hints_done": g.hints_done.duplicate(),
		"captures": g.captures,
		"pending_drafts": g.pending_drafts,
		"events_seen": g.events_seen,
		"next_event_turn": g.next_event_turn,
		"pending_event": str(g.pending_event.get("id", "")),
		"chronicle": g.chronicle.slice(maxi(0, g.chronicle.size() - 60)),
		"tiles": _tile_changes(g),
		"players": _players(g),
		"summary": "%s · %s Age · turn %d of %d" % [
			g.me.name, Data.AGES[g.me.age]["name"], g.turn, Data.MAX_TURNS],
	}
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(d))
	f.close()
	return true


## Only what play has changed: the terrain itself comes back from the seed.
static func _tile_changes(g: GameRules) -> Array:
	var out: Array = []
	for t in g.world.list:
		out.append([t.coord.x, t.coord.y, t.improve, t.worked_turns,
			1 if t.ruin else 0, 1 if t.camp else 0])
	return out


static func _players(g: GameRules) -> Array:
	var out: Array = []
	for p in g.players:
		var dip: Array = []
		for other_id in p.dip:
			var r: Dictionary = p.dip[other_id]
			dip.append({
				"id": int(other_id), "met": r["met"], "war": r["war"],
				"attitude": float(r["attitude"]), "truce": int(r["truce"]),
				"last_tribute": int(r["last_tribute"]), "paid": int(r["paid"]),
				"refused": int(r["refused"]), "denounced": r["denounced"]})
		var seen: Array = []
		for c in p.seen:
			seen.append([c.x, c.y])
		var cities: Array = []
		for c in p.cities:
			cities.append({
				"id": c.id, "q": c.coord.x, "r": c.coord.y, "name": c.name,
				"pop": c.pop, "food": c.food, "prod": c.prod, "hp": c.hp,
				"structures": c.structures.duplicate(), "queue": c.queue.duplicate(),
				"focus": c.focus, "capital": c.is_capital, "founded": c.founded,
				"just_taken": c.just_taken})
		var units: Array = []
		for u in p.units:
			units.append({
				"id": u.id, "type": u.type, "q": u.coord.x, "r": u.coord.y,
				"hp": u.hp, "mv": u.mv, "xp": u.xp, "rank": u.rank,
				"promos": u.promos.duplicate(), "fortified": u.fortified,
				"asleep": u.asleep, "done": u.done, "embarked": u.embarked,
				"goto": [u.goto.x, u.goto.y] if u.has_goto else []})
		out.append({
			"id": p.id, "leader": p.leader.get("id", ""), "human": p.is_human,
			"barbarian": p.is_barbarian, "alive": p.alive,
			"gold": p.gold, "sci": p.sci, "bt_done": p.bt_done, "age": p.age,
			"edicts": p.edicts.duplicate(), "wonders": p.wonders.duplicate(),
			"m": p.m.duplicate(), "kills": p.kills,
			"captured_capitals": p.captured_capitals, "name_index": p.name_index,
			"lost_all_on": p.lost_all_on, "beacon": p.beacon_announced,
			"dip": dip, "seen": seen, "cities": cities, "units": units})
	return out


# =========================================================================
#  Reading
# =========================================================================
static func read(g: GameRules) -> bool:
	if not exists():
		return false
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return false
	var raw = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(raw) != TYPE_DICTIONARY or int(raw.get("version", 0)) != VERSION:
		return false
	var d: Dictionary = raw

	# rebuild the world from its seed, then start a fresh run to get the
	# players, and overwrite them from the file
	var human_leader := ""
	for entry in d["players"]:
		if bool(entry["human"]):
			human_leader = str(entry["leader"])
	if human_leader == "":
		return false
	g.new_run(int(d["seed"]), human_leader, int(d["difficulty"]))

	g.turn = int(d["turn"])
	g.next_id = int(d["next_id"])
	g.rng.set_state(int(d["rng"]))
	g.captures = int(d["captures"])
	g.pending_drafts = int(d["pending_drafts"])
	g.events_seen.assign(d.get("events_seen", []))
	g.next_event_turn = int(d.get("next_event_turn", g.turn + 10))
	g.pending_event = {}
	var waiting := str(d.get("pending_event", ""))
	if waiting != "":
		for ev in EventData.LIST:
			if ev["id"] == waiting:
				g.pending_event = ev
	g.wonders_built = (d["wonders_built"] as Dictionary).duplicate()
	g.unlocked = (d["unlocked"] as Dictionary).duplicate()
	g.hints_done = (d["hints_done"] as Dictionary).duplicate()
	g.chronicle = (d["chronicle"] as Array).duplicate()

	for row in d["tiles"]:
		var t := g.world.at(Vector2i(int(row[0]), int(row[1])))
		if t == null:
			continue
		t.improve = int(row[2])
		t.worked_turns = int(row[3])
		t.ruin = int(row[4]) == 1
		t.camp = int(row[5]) == 1

	# strip everything the fresh run created, then rebuild from the file
	for t in g.world.list:
		t.units.clear()
		t.city = null
		t.worked_by = -1
	for entry in d["players"]:
		var p := g.player(int(entry["id"]))
		if p == null:
			continue
		p.cities.clear()
		p.units.clear()
		p.capital = null
		_restore_player(g, p, entry)

	g.world.recompute_territory(g.players)
	for p2 in g.players:
		for c in p2.cities:
			g.assign_tiles(c)
		g.world.recompute_vision(p2)
	g.state_changed.emit()
	return true


static func _restore_player(g: GameRules, p: Player, e: Dictionary) -> void:
	p.alive = bool(e["alive"])
	p.gold = int(e["gold"])
	p.sci = int(e["sci"])
	p.bt_done = int(e["bt_done"])
	p.age = int(e["age"])
	p.edicts.assign(e["edicts"])
	p.wonders.assign(e["wonders"])
	p.kills = int(e["kills"])
	p.captured_capitals = int(e["captured_capitals"])
	p.name_index = int(e["name_index"])
	p.lost_all_on = int(e["lost_all_on"])
	p.beacon_announced = bool(e["beacon"])

	# the modifier bag is authoritative: it already has the leader trait and
	# every edict folded in, so it replaces rather than adds
	p.m.clear()
	for k in e["m"]:
		p.m[k] = float(e["m"][k])

	p.dip.clear()
	for r in e["dip"]:
		p.dip[int(r["id"])] = {
			"met": bool(r["met"]), "war": bool(r["war"]),
			"attitude": float(r["attitude"]), "truce": int(r["truce"]),
			"last_tribute": int(r["last_tribute"]), "paid": int(r["paid"]),
			"refused": int(r["refused"]), "denounced": bool(r["denounced"])}

	p.seen.clear()
	for c in e["seen"]:
		p.seen[Vector2i(int(c[0]), int(c[1]))] = true

	for cd in e["cities"]:
		var c := City.new()
		c.id = int(cd["id"])
		c.owner_id = p.id
		c.coord = Vector2i(int(cd["q"]), int(cd["r"]))
		c.name = str(cd["name"])
		c.pop = int(cd["pop"])
		c.food = int(cd["food"])
		c.prod = int(cd["prod"])
		c.structures.assign(cd["structures"])
		c.queue = (cd["queue"] as Dictionary).duplicate()
		c.focus = str(cd["focus"])
		c.is_capital = bool(cd["capital"])
		c.founded = int(cd["founded"])
		c.just_taken = int(cd["just_taken"])
		p.cities.append(c)
		var t := g.world.at(c.coord)
		if t != null:
			t.city = c
		g.refresh_city(c)
		c.hp = mini(int(cd["hp"]), c.max_hp)
		if c.is_capital:
			p.capital = c

	for ud in e["units"]:
		var u := Unit.new()
		u.id = int(ud["id"])
		u.owner_id = p.id
		u.type = str(ud["type"])
		u.coord = Vector2i(int(ud["q"]), int(ud["r"]))
		u.hp = int(ud["hp"])
		u.mv = int(ud["mv"])
		u.xp = int(ud["xp"])
		u.rank = int(ud["rank"])
		u.promos.assign(ud["promos"])
		u.fortified = int(ud["fortified"])
		u.asleep = bool(ud["asleep"])
		u.done = bool(ud["done"])
		u.embarked = bool(ud["embarked"])
		var gt: Array = ud["goto"]
		if gt.size() == 2:
			u.has_goto = true
			u.goto = Vector2i(int(gt[0]), int(gt[1]))
		p.units.append(u)
		var t2 := g.world.at(u.coord)
		if t2 != null:
			t2.units.append(u)
