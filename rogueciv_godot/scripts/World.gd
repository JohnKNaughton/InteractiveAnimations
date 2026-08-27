class_name World
extends RefCounted

## The map: generation, lookup, territory and sight.

var radius: int = Data.MAP_RADIUS
var tiles: Dictionary = {}       ## Vector2i -> Tile
var list: Array[Tile] = []       ## every Tile, in creation order
var rng: Rng


func at(c: Vector2i) -> Tile:
	return tiles.get(c, null)


func has(c: Vector2i) -> bool:
	return tiles.has(c)


func neighbours(c: Vector2i) -> Array[Tile]:
	var out: Array[Tile] = []
	for d in Hex.DIRS:
		var t: Tile = tiles.get(c + d, null)
		if t != null:
			out.append(t)
	return out


func neighbour(c: Vector2i, d: int) -> Tile:
	return tiles.get(c + Hex.DIRS[d], null)


func in_range(c: Vector2i, n: int) -> Array[Tile]:
	var out: Array[Tile] = []
	for coord in Hex.in_range(c, n):
		var t: Tile = tiles.get(coord, null)
		if t != null:
			out.append(t)
	return out


# =========================================================================
#  Value noise
# =========================================================================
class ValueNoise:
	var tab := PackedFloat32Array()
	const N := 256

	func _init(r: Rng) -> void:
		tab.resize(N * N)
		for i in N * N:
			tab[i] = r.nextf()

	func _at(x: int, y: int) -> float:
		return tab[(posmod(y, N)) * N + posmod(x, N)]

	func _n2(x: float, y: float) -> float:
		var xi := int(floor(x))
		var yi := int(floor(y))
		var xf := x - xi
		var yf := y - yi
		var u := xf * xf * (3.0 - 2.0 * xf)
		var v := yf * yf * (3.0 - 2.0 * yf)
		var a := _at(xi, yi)
		var b := _at(xi + 1, yi)
		var c := _at(xi, yi + 1)
		var d := _at(xi + 1, yi + 1)
		var top := a + (b - a) * u
		var bot := c + (d - c) * u
		return top + (bot - top) * v

	func fbm(x: float, y: float, octaves := 4) -> float:
		var s := 0.0
		var amp := 1.0
		var f := 1.0
		var total := 0.0
		for i in octaves:
			s += _n2(x * f, y * f) * amp
			total += amp
			amp *= 0.5
			f *= 2.05
		return s / total


# =========================================================================
#  Generation
# =========================================================================
func generate(seed_value: int, map_radius: int = Data.MAP_RADIUS) -> void:
	radius = map_radius
	rng = Rng.new(seed_value)
	tiles.clear()
	list.clear()

	var n_elev := ValueNoise.new(rng)
	var n_moist := ValueNoise.new(rng)
	var n_temp := ValueNoise.new(rng)
	var n_feat := ValueNoise.new(rng)

	# --- 1. the shape of the land -----------------------------------------
	for coord in Hex.in_range(Vector2i.ZERO, radius):
		var p := Hex.to_world(coord, 1.0)
		var dist := p.length() / (radius * 1.732)
		var h := n_elev.fbm(p.x * 0.30 + 7.0, p.y * 0.30 + 13.0, 5)
		# two broad lobes stop the landmass being one dull blob
		h += 0.16 * cos(p.x * 0.28) * sin(p.y * 0.22)
		var rim := maxf(0.0, (dist - 0.62) / 0.38)
		h -= rim * rim * 1.25
		h -= 0.06

		var t := Tile.new()
		t.coord = coord
		t.pos = p
		t.height = h
		tiles[coord] = t
		list.append(t)

	# --- 2. sea level and elevation, cut at percentiles so every seed works -
	var land_fraction := 0.50 + rng.nextf() * 0.09
	var heights: Array[float] = []
	for t in list:
		heights.append(t.height)
	heights.sort()
	var sea_level: float = heights[int(heights.size() * (1.0 - land_fraction))]
	var land_h: Array[float] = []
	for h2 in heights:
		if h2 > sea_level:
			land_h.append(h2)
	var hill_level: float = land_h[int(land_h.size() * 0.52)]
	var mtn_level: float = land_h[int(land_h.size() * 0.88)]

	for t in list:
		if t.height > sea_level:
			t.terrain = "grass"
			if t.height > mtn_level:
				t.elev = "mtn"
			elif t.height > hill_level:
				t.elev = "hill"

	# thin mountain clumps so they read as ranges, not plateaus
	for t in list:
		if t.elev != "mtn":
			continue
		var m := 0
		for nb in neighbours(t.coord):
			if nb.elev == "mtn":
				m += 1
		if m >= 4 and rng.chance(0.55):
			t.elev = "hill"

	# --- 3. coast, then landlocked water becomes lakes ---------------------
	for t in list:
		if t.terrain != "ocean":
			continue
		for nb in neighbours(t.coord):
			if nb.terrain != "ocean":
				t.terrain = "coast"
				break
	_label_continents()
	var water_size := {}
	for t in list:
		if t.is_water():
			water_size[t.continent] = int(water_size.get(t.continent, 0)) + 1
	for t in list:
		if t.is_water() and int(water_size.get(t.continent, 0)) <= 6:
			t.terrain = "lake"

	# --- 4. climate --------------------------------------------------------
	var temps := {}
	var moists := {}
	for t in list:
		if t.is_water():
			continue
		var lat := absf(float(t.coord.y)) / float(radius)
		var temp := 1.0 - lat * 1.28 + (n_temp.fbm(t.pos.x * 0.34 + 41.0, t.pos.y * 0.34 + 3.0, 3) - 0.5) * 0.42
		if t.elev == "hill":
			temp -= 0.06
		if t.elev == "mtn":
			temp -= 0.16
		var moist := n_moist.fbm(t.pos.x * 0.26 + 91.0, t.pos.y * 0.26 + 57.0, 4)
		temps[t.coord] = temp
		moists[t.coord] = moist
		if temp < 0.14:
			t.terrain = "snow"
		elif temp < 0.30:
			t.terrain = "tundra"
		elif moist < 0.36 and temp > 0.44:
			t.terrain = "desert"
		elif moist > 0.55:
			t.terrain = "grass"
		else:
			t.terrain = "plains"
	for t in list:
		if t.terrain == "ocean" and absf(float(t.coord.y)) / float(radius) > 0.93 and rng.chance(0.7):
			t.feature = "ice"

	# --- 5. rivers, walked downhill to the sea -----------------------------
	var sources: Array = []
	for t in list:
		if not t.is_water() and t.height > sea_level + 0.16 and t.terrain != "desert":
			sources.append(t)
	rng.shuffle(sources)
	var want := maxi(5, int(round(radius * 1.3)))
	var made := 0
	for s in sources:
		if made >= want:
			break
		if s.has_river():
			continue
		var path: Array = [s]
		var cur: Tile = s
		var ok := false
		for step in radius * 2:
			var best: Tile = null
			var best_score := 1e9
			for d in 6:
				var nb := neighbour(cur.coord, d)
				if nb == null or path.has(nb):
					continue
				var score: float = nb.height - (5.0 if nb.is_water() else 0.0) \
					+ Hex.hash2(nb.coord.x, nb.coord.y) * 0.05
				if score < best_score:
					best_score = score
					best = nb
			if best == null:
				break
			if best.is_water():
				ok = path.size() >= 2
				break
			if best.height > cur.height + 0.02:
				break
			path.append(best)
			cur = best
			if best.has_river():
				ok = path.size() >= 2
				break
		if not ok:
			continue
		for i in range(path.size() - 1):
			var a: Tile = path[i]
			var b: Tile = path[i + 1]
			var delta := b.coord - a.coord
			var d_index := Hex.DIRS.find(delta)
			if d_index < 0:
				continue
			if not a.rivers.has(d_index):
				a.rivers.append(d_index)
			var back := (d_index + 3) % 6
			if not b.rivers.has(back):
				b.rivers.append(back)
		made += 1

	for t in list:
		if t.terrain == "desert" and t.elev == "flat" and t.has_river():
			t.feature = "flood"

	# --- 6. features -------------------------------------------------------
	for t in list:
		if t.is_water() or t.elev == "mtn" or t.feature != "":
			continue
		var fv := n_feat.fbm(t.pos.x * 0.42 + 13.0, t.pos.y * 0.42 + 77.0, 3)
		var temp: float = temps.get(t.coord, 0.5)
		var moist: float = moists.get(t.coord, 0.5)
		if temp > 0.72 and moist > 0.62 and fv > 0.42:
			t.feature = "jungle"
		elif moist > 0.46 and temp > 0.20 and temp < 0.86 and fv > 0.46:
			t.feature = "forest"
		elif t.elev == "flat" and moist > 0.70 and fv < 0.26 and _touches_water(t):
			t.feature = "marsh"
		elif t.terrain == "desert" and rng.chance(0.045):
			t.feature = "oasis"

	_label_continents()
	_place_resources()

	# --- 7. ruins, the small kindnesses of an empty map --------------------
	var land: Array = []
	for t in list:
		if not t.is_water() and not t.is_impassable():
			land.append(t)
	rng.shuffle(land)
	var n_ruins := int(round(land.size() * 0.055))
	for i in mini(n_ruins, land.size()):
		land[i].ruin = true


func _touches_water(t: Tile) -> bool:
	for nb in neighbours(t.coord):
		if nb.is_water():
			return true
	return false


func _label_continents() -> void:
	for t in list:
		t.continent = 0
	var id := 0
	for t in list:
		if t.continent != 0:
			continue
		id += 1
		var water := t.is_water()
		var stack: Array = [t]
		t.continent = id
		while not stack.is_empty():
			var c: Tile = stack.pop_back()
			for nb in neighbours(c.coord):
				if nb.continent != 0 or nb.is_water() != water:
					continue
				nb.continent = id
				stack.append(nb)


func _place_resources() -> void:
	var cand: Array = []
	for t in list:
		if not t.is_impassable() and t.feature != "ice":
			cand.append(t)
	rng.shuffle(cand)

	var n := list.size()
	var quota := {}
	var placed := {}
	for k in Data.RESOURCE:
		var kind: String = Data.RESOURCE[k]["kind"]
		# kept deliberately sparse: a resource on every fifth tile reads as
		# confetti rather than as somewhere worth settling
		if kind == "s":
			quota[k] = int(round(n * 0.022))
		elif kind == "l":
			quota[k] = int(round(n * 0.010))
		else:
			quota[k] = int(round(n * 0.019))
		placed[k] = 0

	for t in cand:
		if t.resource != "":
			continue
		if not rng.chance(0.45):
			continue
		var options: Array[String] = []
		for k in Data.RESOURCE:
			if int(placed[k]) >= int(quota[k]):
				continue
			if not _resource_fits(t, k):
				continue
			var crowded := false
			for o in in_range(t.coord, 2):
				if o.resource == k:
					crowded = true
					break
			if crowded:
				continue
			options.append(k)
		if options.is_empty():
			continue
		var chosen: String = options[rng.below(options.size())]
		t.resource = chosen
		placed[chosen] = int(placed[chosen]) + 1

	# guarantee every strategic resource exists somewhere reachable
	for k in ["horses", "iron", "niter", "oil", "uranium"]:
		if int(placed[k]) > 0:
			continue
		for t in cand:
			if t.resource == "" and _resource_fits(t, k):
				t.resource = k
				placed[k] = 1
				break


func _resource_fits(t: Tile, key: String) -> bool:
	var r: Dictionary = Data.RESOURCE[key]
	if r.has("needs_feature"):
		return t.feature == r["needs_feature"] and (r["on"] as Array).has(t.terrain)
	if r.get("flat", false) and t.elev != "flat":
		return false
	if r.get("hill", false) and t.elev != "hill":
		return false
	if t.feature == "forest" or t.feature == "jungle":
		return false
	if key == "fish":
		return t.terrain == "coast"
	if t.is_water():
		return key == "oil" and t.terrain == "coast"
	return (r["on"] as Array).has(t.terrain)


# =========================================================================
#  Yields
# =========================================================================
## A strategic resource stays hidden until the player's age reveals it.
func resource_visible(t: Tile, p: Player) -> bool:
	if t.resource == "":
		return false
	var r: Dictionary = Data.RESOURCE[t.resource]
	if r["kind"] != "s":
		return true
	if p == null:
		return true
	if t.resource == "uranium" and p.mod("uranium_all") > 0.0:
		return true
	return p.age >= int(r.get("age", 0))


func tile_yield(t: Tile, p: Player) -> Vector3i:
	var base: Vector3i = Data.TERRAIN[t.terrain]["y"]
	var el: Vector3i = Data.ELEV[t.elev]["y"]
	var ft: Vector3i = Vector3i.ZERO
	if t.feature != "":
		ft = Data.FEATURE[t.feature]["y"]
	var f := base.x + el.x + ft.x
	var pr := base.y + el.y + ft.y
	var g := base.z + el.z + ft.z

	if t.resource != "" and resource_visible(t, p):
		var r: Dictionary = Data.RESOURCE[t.resource]
		var ry: Vector3i = r["y"]
		f += ry.x
		pr += ry.y
		g += ry.z
		if p != null and r["kind"] == "b":
			f += int(p.mod("t_food_res"))

	if t.has_river():
		g += 1
	f += t.improve

	if p != null:
		if t.has_river() or t.feature == "flood":
			f += int(p.mod("t_food_river"))
		if t.elev == "hill":
			f += int(p.mod("t_food_hill"))
		if t.feature == "forest" or t.feature == "jungle":
			f += int(p.mod("t_food_wood"))
		if t.is_water():
			g += int(p.mod("t_gold_water"))
			pr += int(p.mod("t_prod_water"))

	return Vector3i(maxi(0, f), maxi(0, pr), maxi(0, g))


func is_fresh_water(t: Tile) -> bool:
	if t.has_river():
		return true
	for nb in neighbours(t.coord):
		if nb.terrain == "lake":
			return true
	return false


func is_coastal(c: Vector2i) -> bool:
	for nb in neighbours(c):
		if nb.terrain == "coast" or nb.terrain == "ocean":
			return true
	return false


# =========================================================================
#  Territory and sight
# =========================================================================
func recompute_territory(players: Array[Player]) -> void:
	for t in list:
		t.owner_id = -1
		t.claim = 9999
	for p in players:
		if p == null or p.is_barbarian:
			continue
		for c in p.cities:
			var rad := city_radius(c, p)
			for t in in_range(c.coord, rad):
				var d := Hex.distance(t.coord, c.coord)
				if d < t.claim:
					t.claim = d
					t.owner_id = p.id


func city_radius(c: City, p: Player) -> int:
	var rad := 3 if c.pop >= 8 else 2
	rad += int(p.mod("city_radius")) + int(c.effects.get("radius", 0))
	return mini(4, rad)


func see_from(p: Player, t: Tile, sight: int, elevated: bool) -> void:
	p.vis[t.coord] = true
	p.seen[t.coord] = true
	var high := elevated or t.elev == "hill" or t.elev == "mtn"
	for o in in_range(t.coord, sight):
		var d := Hex.distance(t.coord, o.coord)
		if d <= 1:
			p.vis[o.coord] = true
			p.seen[o.coord] = true
			continue
		var blocked := false
		if not high:
			var ln := Hex.line(t.coord, o.coord)
			for i in range(1, ln.size() - 1):
				var mid: Tile = tiles.get(ln[i], null)
				if mid != null and mid.blocks_sight():
					blocked = true
					break
		if not blocked:
			p.vis[o.coord] = true
			p.seen[o.coord] = true


func recompute_vision(p: Player) -> void:
	if p.is_barbarian:
		return
	p.vis = {}
	for c in p.cities:
		var t := at(c.coord)
		if t != null:
			see_from(p, t, 3, true)
	for u in p.units:
		var t2 := at(u.coord)
		if t2 == null:
			continue
		var s: int = int(Data.UNIT[u.type].get("sight", 2)) + int(p.mod("sight_all"))
		see_from(p, t2, s, false)
	if p.mod("reveal_all") > 0.0:
		for t3 in list:
			p.seen[t3.coord] = true
