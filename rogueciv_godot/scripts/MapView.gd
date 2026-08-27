extends Node2D

## Draws the world, and owns what the player currently has selected.
## The look: flat hexes with a hairline of paper between them, features drawn
## as small marks in a darker tint of their own tile, and unexplored ground
## left as bare paper so the map appears as it is walked.

signal selection_changed
signal wants_city_panel(city)

const HEX := 46.0
const INSET := 0.955

var selected_unit: Unit = null
var selected_city: City = null
var reach: Dictionary = {}
var targets: Array = []
var sites: Array = []
var path_preview: Array = []
var hover: Vector2i = Vector2i(9999, 9999)

var floaters: Array = []          ## {pos, text, colour, born}
var rings: Array = []             ## brief impact rings
var camera: Camera2D
var sheet_mode := false


func _ready() -> void:
	Game.state_changed.connect(func(): queue_redraw())
	Game.combat_happened.connect(_on_combat)
	Game.attack_made.connect(_on_attack)
	set_process(true)


func _process(delta: float) -> void:
	var live := false
	# units glide to their new tile rather than snapping
	for p in Game.players:
		for u in p.units:
			var want := Hex.to_world(u.coord, HEX)
			if not u.draw_init:
				u.draw_pos = want
				u.draw_init = true
			elif u.draw_pos.distance_to(want) > 0.5:
				u.draw_pos = u.draw_pos.lerp(want, clampf(delta * 11.0, 0.0, 1.0))
				live = true
			else:
				u.draw_pos = want
	var now := Time.get_ticks_msec() / 1000.0
	if not floaters.is_empty():
		floaters = floaters.filter(func(f): return now - float(f["born"]) < 1.15)
		live = true
	if not rings.is_empty():
		rings = rings.filter(func(r): return now - float(r["born"]) < 0.45)
		live = true
	for p2 in Game.players:
		for u2 in p2.units:
			if now - u2.lunge_at < LUNGE_TIME:
				live = true
	if live or selected_unit != null:
		queue_redraw()


const LUNGE_TIME := 0.34

## A blow should look like one: the attacker leans in and comes back.
func _on_attack(from: Vector2i, to: Vector2i, ranged: bool) -> void:
	if Game.me == null or not Game.me.vis.has(from):
		return
	var t := Game.world.at(from)
	if t == null:
		return
	var u := t.military()
	if u == null:
		return
	u.lunge_dir = (Hex.to_world(to, HEX) - Hex.to_world(from, HEX)).normalized() 		* (0.30 if not ranged else 0.12)
	u.lunge_at = Time.get_ticks_msec() / 1000.0
	rings.append({"pos": Hex.to_world(to, HEX), "born": u.lunge_at})
	while rings.size() > 5:
		rings.pop_front()
	queue_redraw()


func _lunge_offset(u: Unit) -> Vector2:
	var age := Time.get_ticks_msec() / 1000.0 - u.lunge_at
	if age < 0.0 or age > LUNGE_TIME:
		return Vector2.ZERO
	# out fast, back slow
	var f := age / LUNGE_TIME
	return u.lunge_dir * HEX * sin(f * PI) * (1.0 - f * 0.35)


func _on_combat(at: Vector2i, damage: int) -> void:
	# a rival's turn can resolve a dozen fights at once; only report the ones
	# in sight, and never let them pile into a screen full of numbers
	if Game.me == null or not Game.me.vis.has(at):
		return
	floaters.append({
		"pos": Hex.to_world(at, HEX), "text": "-" + str(damage),
		"colour": Pal.BAD, "born": Time.get_ticks_msec() / 1000.0})
	while floaters.size() > 6:
		floaters.pop_front()
	queue_redraw()


func float_text(at: Vector2i, text: String, colour: Color) -> void:
	floaters.append({"pos": Hex.to_world(at, HEX), "text": text,
		"colour": colour, "born": Time.get_ticks_msec() / 1000.0})
	queue_redraw()


# =========================================================================
#  Selection
# =========================================================================
func select_unit(u: Unit) -> void:
	if u != selected_unit:
		Snd.play("select")
	selected_unit = u
	selected_city = null
	path_preview.clear()
	_recompute_selection()
	selection_changed.emit()
	queue_redraw()


func select_city(c: City) -> void:
	selected_city = c
	selected_unit = null
	reach.clear()
	targets.clear()
	sites.clear()
	path_preview.clear()
	selection_changed.emit()
	queue_redraw()


func clear_selection() -> void:
	selected_unit = null
	selected_city = null
	reach.clear()
	targets.clear()
	sites.clear()
	path_preview.clear()
	selection_changed.emit()
	queue_redraw()


func _recompute_selection() -> void:
	reach.clear()
	targets.clear()
	sites.clear()
	var u := selected_unit
	if u == null or u.dead or u.owner_id != Game.me.id:
		return
	if u.mv > 0:
		reach = Game.reachable(u)
	if u.is_civilian():
		if Game.me.cities.size() < Game.me.city_cap():
			for t in Game.world.in_range(u.coord, 7):
				if Game.me.seen.has(t.coord) and Game.can_found_here(Game.me, t):
					sites.append(t)
		return
	if u.mv <= 0:
		return
	var r := Game.unit_range(u)
	var scan: Array = Game.world.in_range(u.coord, r) if r > 0 else Game.world.neighbours(u.coord)
	for t in scan:
		var d := Hex.distance(u.coord, t.coord)
		if d == 0:
			continue
		if r == 0 and d > 1:
			continue
		if not Game.me.vis.has(t.coord):
			continue
		var foe = t.military()
		if foe == null:
			foe = t.civilian()
		if foe != null and Game.at_war(Game.me, Game.player(foe.owner_id)):
			targets.append(t)
		elif t.city != null and t.city.owner_id != Game.me.id \
				and Game.at_war(Game.me, Game.player(t.city.owner_id)):
			if r > 0 or u.cls() != "ranged":
				targets.append(t)


func refresh() -> void:
	_recompute_selection()
	queue_redraw()


# =========================================================================
#  Orders
# =========================================================================
func order_to(u: Unit, t: Tile) -> void:
	if targets.has(t):
		var r := Game.unit_range(u)
		var d := Hex.distance(u.coord, t.coord)
		if r > 0 and d > 1:
			Game.ranged_attack(u, t)
		elif d == 1:
			Game.melee_attack(u, t)
		if not u.dead and u.mv <= 0:
			u.done = true
		_after_order(u)
		return
	if u.coord == t.coord:
		return
	var path := Game.path_to(u, t.coord)
	if path.is_empty():
		Snd.play("deny")
		float_text(u.coord, "no route", Pal.BAD)
		return
	_walk(u, path)
	if u.coord != t.coord:
		u.goto = t.coord
		u.has_goto = true
		u.done = true
	else:
		u.has_goto = false
	_after_order(u)


func _walk(u: Unit, path: Array) -> void:
	for step in path:
		if u.mv <= 0:
			break
		var t := Game.world.at(step)
		if t == null or Game.blocked_by(u, t) != "":
			break
		if not Game.step_unit(u, t):
			break


func _after_order(u: Unit) -> void:
	Game.world.recompute_vision(Game.me)
	_recompute_selection()
	Game.state_changed.emit()
	queue_redraw()
	if u.dead or u.mv <= 0 or u.has_goto:
		u.done = true


func resume_orders(p: Player) -> void:
	for u in p.units.duplicate():
		if u.dead or not u.has_goto:
			continue
		var target := Game.world.at(u.goto)
		if target == null or u.coord == u.goto:
			u.has_goto = false
			continue
		var path := Game.path_to(u, u.goto)
		if path.is_empty():
			u.has_goto = false
			continue
		for step in path:
			if u.mv <= 0:
				break
			var t := Game.world.at(step)
			if t == null or Game.blocked_by(u, t) != "":
				u.has_goto = false
				break
			if not Game.step_unit(u, t):
				u.has_goto = false
				break
			# stop the moment anything hostile is in reach
			var spotted := false
			for nb in Game.world.neighbours(u.coord):
				var f = nb.military()
				if f != null and Game.at_war(p, Game.player(f.owner_id)):
					spotted = true
					break
			if spotted:
				u.has_goto = false
				break
		if u.coord == u.goto:
			u.has_goto = false
		if u.has_goto:
			u.done = true


func idle_units() -> Array:
	var out: Array = []
	for u in Game.me.units:
		if u.dead or u.done or u.asleep or u.mv <= 0:
			continue
		if u.is_civilian() and u.has_goto:
			continue
		out.append(u)
	return out


func next_idle_unit(auto: bool) -> bool:
	if auto:
		resume_orders(Game.me)
	var list := idle_units()
	if list.is_empty():
		if auto:
			clear_selection()
		else:
			selected_unit = null
			selection_changed.emit()
			queue_redraw()
		return false
	var i := list.find(selected_unit)
	var u: Unit = list[(i + 1) % list.size()]
	select_unit(u)
	return true


# =========================================================================
#  Drawing - pop art
#
#  Flat colour, a heavy black keyline around every tile, and Ben-Day dots
#  standing in for shading. Nothing here uses a gradient or a soft shadow:
#  depth comes from line weight and dot density, the way it does in print.
#  Detail drops away in two steps as the camera pulls back.
# =========================================================================
var _lod := 2                     ## 2 full, 1 medium, 0 far

## A lattice of dot positions inside a unit hex, each carrying how far it sits
## from the light. Built once and scaled per tile: recomputing it per tile is
## the difference between a screen of dots and a slideshow.
var _dots: Array = []


func tile_colour(t: Tile) -> Color:
	var c: Color = Pal.TERRAIN_COLOUR[t.terrain]
	if t.elev == "hill":
		c = Pal.shade(c, -0.10)
	elif t.elev == "mtn":
		c = c.lerp(Pal.MOUNTAIN, 0.45)
	match t.feature:
		"forest": c = c.lerp(Pal.FOREST, 0.62)
		"jungle": c = c.lerp(Pal.JUNGLE, 0.70)
		"marsh":  c = c.lerp(Pal.MARSH, 0.58)
		"ice":    c = Pal.ICE
		"flood":  c = c.lerp(Pal.GRASS, 0.45)
	# a whisper of variation so a field of one terrain is not a flat slab
	var j := (Hex.hash2(t.coord.x, t.coord.y) - 0.5) * 0.075
	return Pal.shade(c, j)


## One flat plate of colour. No gradient - that is the whole point.
func _ground(centre: Vector2, size: float, col: Color, _dim: bool) -> void:
	_fill(Hex.polygon(centre, size), col)


func _build_dots() -> void:
	_dots.clear()
	var hex := Hex.polygon(Vector2.ZERO, 1.0)
	var step := 0.32
	var row := 0
	var y := -1.0
	while y <= 1.0:
		var x := -1.0 + (step * 0.5 if row % 2 == 1 else 0.0)
		while x <= 1.0:
			var p := Vector2(x, y)
			if Geometry2D.is_point_in_polygon(p, hex):
				var sh := 0.0
				if p.length() > 0.02:
					sh = p.normalized().dot(-Pal.LIGHT)
				_dots.append({"off": p, "shade": sh})
			x += step
		y += step * 0.9
		row += 1


## Ben-Day dots. Density is how much of the tile the screen covers, growing
## from the lit edge toward the dark one, so a hex still reads as a solid with
## a light on it without a single soft pixel.
func _benday(centre: Vector2, size: float, col: Color, density: float,
		dim := false, tint := Color(0, 0, 0, 0)) -> void:
	if _dots.is_empty():
		_build_dots()
	var dot := Pal.dot_over(col) if tint.a <= 0.0 else tint
	dot.a = 0.30 if dim else 0.72
	var cut := 1.0 - density * 2.0
	var r := size * 0.075
	for d in _dots:
		if float(d["shade"]) < cut:
			continue
		draw_circle(centre + Vector2(d["off"]) * size * 0.90, r, dot)


## The keyline: every tile is outlined in black, like a cel.
func _keyline(centre: Vector2, size: float, width: float, col := Pal.INK) -> void:
	draw_polyline(_closed(Hex.polygon(centre, size)), col, width, true)


func _draw() -> void:
	if sheet_mode:
		_draw_glyph_sheet()
		return
	if Game.world == null or Game.me == null:
		return
	var me := Game.me
	var view := _visible_rect()
	var zoom := camera.zoom.x if camera != null else 1.0
	_lod = 2 if zoom > 0.72 else (1 if zoom > 0.46 else 0)

	# --- the sea beyond the world ----------------------------------------
	draw_rect(view, Pal.VOID)

	var drawn: Array[Tile] = []
	var unknown: Array[Tile] = []
	for t in Game.world.list:
		t.screen = Hex.to_world(t.coord, HEX)
		if not view.has_point(t.screen):
			continue
		if me.seen.has(t.coord):
			drawn.append(t)
		else:
			unknown.append(t)

	# --- country nobody has walked ---------------------------------------
	for t in unknown:
		# flat, not graded: a gradient this dark only shows as banding
		var shade_jitter := (Hex.hash2(t.coord.x, t.coord.y) - 0.5) * 0.05
		_fill(Hex.polygon(t.screen, HEX * 1.004), Pal.shade(Pal.UNKNOWN, shade_jitter))
	if _lod > 0:
		for t in unknown:
			draw_polyline(_closed(Hex.polygon(t.screen, HEX * 0.995)),
				Pal.with_alpha(Pal.UNKNOWN_EDGE, 0.55), 1.0, true)

	# --- ground -----------------------------------------------------------
	for t in drawn:
		var dim := not me.vis.has(t.coord)
		var col := tile_colour(t)
		if dim:
			col = Pal.remembered(col)
		_ground(t.screen, HEX * 1.002, col, dim)

	# --- shallows: a band of light water against every shore --------------
	if _lod > 0:
		for t in drawn:
			if not t.is_water() or t.terrain == "lake":
				continue
			var dim2 := not me.vis.has(t.coord)
			for d in 6:
				var nb := Game.world.neighbour(t.coord, d)
				if nb == null or nb.is_water():
					continue
				var e := Hex.edge(d, HEX * 0.90)
				var shallow := Pal.COAST_HI if not dim2 else Pal.remembered(Pal.COAST_HI)
				draw_line(t.screen + e[0], t.screen + e[1],
					Pal.with_alpha(shallow, 0.55), HEX * 0.20, true)
				var e2 := Hex.edge(d, HEX * 0.99)
				draw_line(t.screen + e2[0], t.screen + e2[1],
					Pal.with_alpha(Pal.SHORE, 0.75 if not dim2 else 0.30), HEX * 0.075, true)

	# --- the screen of dots -----------------------------------------------
	if _lod == 2:
		for t in drawn:
			var dim_d := not me.vis.has(t.coord)
			var c2 := tile_colour(t)
			if dim_d:
				c2 = Pal.remembered(c2)
			if t.is_water():
				# an ocean of dots is the oldest trick in the style
				_benday(t.screen, HEX, c2, 0.62, dim_d, Pal.PAPER_HI)
			else:
				_benday(t.screen, HEX, c2, 0.40, dim_d)

	# --- the keyline ------------------------------------------------------
	if _lod > 0:
		var kw: float = HEX * (0.040 if _lod == 2 else 0.026)
		for t in drawn:
			var ink := Pal.INK if me.vis.has(t.coord) else Pal.with_alpha(Pal.INK, 0.5)
			_keyline(t.screen, HEX * 0.995, kw, ink)

	# --- rivers -----------------------------------------------------------
	for t in drawn:
		if t.rivers.is_empty():
			continue
		var dim3 := not me.vis.has(t.coord)
		var deep := Pal.RIVER_DEEP if not dim3 else Pal.remembered(Pal.RIVER_DEEP)
		var bright := Pal.RIVER if not dim3 else Pal.remembered(Pal.RIVER)
		var mouths: Array[Vector2] = []
		for d in t.rivers:
			mouths.append(t.screen + Hex.to_world(Hex.DIRS[d], HEX) * 0.5)
		var runs: Array = []
		if mouths.size() == 1:
			runs.append(_curve(mouths[0], t.screen.lerp(mouths[0], 0.35), t.screen))
		else:
			for i in mouths.size():
				for j in range(i + 1, mouths.size()):
					runs.append(_curve(mouths[i], t.screen, mouths[j]))
		for r in runs:
			draw_polyline(r, deep, HEX * 0.125, true)
			draw_polyline(r, bright, HEX * 0.075, true)

	# --- what grows on it -------------------------------------------------
	if _lod > 0:
		for t in drawn:
			_draw_feature(t, not me.vis.has(t.coord))

	# --- resources --------------------------------------------------------
	if _lod == 2:
		for t in drawn:
			if t.resource != "" and Game.world.resource_visible(t, me):
				_draw_resource(t, not me.vis.has(t.coord))

	# --- territory --------------------------------------------------------
	_draw_borders(drawn)
	_draw_overlays(drawn)

	# --- cities and units -------------------------------------------------
	for t in drawn:
		if t.city != null:
			_draw_city(t.city, t.screen, not me.vis.has(t.coord))
	for t in drawn:
		if not me.vis.has(t.coord):
			continue
		var stacked: bool = t.units.size() > 1
		for u in t.units:
			_draw_unit(u, stacked)

	# --- the moment of impact ---------------------------------------------
	var ring_now := Time.get_ticks_msec() / 1000.0
	for r in rings:
		var age: float = (ring_now - float(r["born"])) / 0.45
		if age < 0.0 or age > 1.0:
			continue
		draw_arc(r["pos"], HEX * (0.16 + age * 0.52), 0, TAU, 26,
			Pal.with_alpha(Pal.BAD, (1.0 - age) * 0.75), HEX * 0.06 * (1.0 - age * 0.6), true)

	# --- floating numbers -------------------------------------------------
	var now := Time.get_ticks_msec() / 1000.0
	for f in floaters:
		var age2 := (now - float(f["born"])) / 1.15
		var pos: Vector2 = f["pos"] + Vector2(0, -HEX * 0.78 - age2 * HEX * 0.55)
		var col3: Color = f["colour"]
		col3.a = clampf(1.0 - age2 * age2, 0.0, 1.0)
		_text_centred(str(f["text"]), pos, 22, col3, true)


func _visible_rect() -> Rect2:
	if camera == null:
		return Rect2(Vector2(-9999, -9999), Vector2(19998, 19998))
	var size := get_viewport_rect().size / camera.zoom
	var pad := HEX * 2.0
	return Rect2(camera.global_position - size * 0.5 - Vector2(pad, pad),
				 size + Vector2(pad, pad) * 2.0)


func _dimmed(c: Color, dim: bool) -> Color:
	return Pal.remembered(c) if dim else c


# --- one raised thing: lit face, shaded face, and a shadow on the ground ---
## A hill, printed: one flat plate, a black keyline, and a wedge of dots on
## the side away from the light.
func _mound(at: Vector2, w: float, h: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 13:
		var ang := PI + PI * (float(i) / 12.0)
		pts.append(at + Vector2(cos(ang) * w, sin(ang) * h))
	_fill(pts, col)
	var dark := PackedVector2Array()
	for i in 7:
		var ang2 := PI + PI * (float(i) / 12.0)
		dark.append(at + Vector2(cos(ang2) * w, sin(ang2) * h))
	dark.append(at)
	_fill(dark, Pal.dot_over(col))
	draw_polyline(_closed(pts), Pal.INK, maxf(1.0, w * 0.15), true)


func _tree(at: Vector2, size: float, dark: Color, light: Color, conifer: bool) -> void:
	var ink := maxf(1.0, size * 0.24)
	if conifer:
		var body := PackedVector2Array([
			at + Vector2(-size * 0.78, size * 0.72),
			at + Vector2(0.0, -size * 1.42),
			at + Vector2(size * 0.78, size * 0.72)])
		_fill(body, dark)
		_fill(PackedVector2Array([
			at + Vector2(-size * 0.78, size * 0.72),
			at + Vector2(0.0, -size * 1.42),
			at + Vector2(-size * 0.06, size * 0.72)]), light)
		draw_polyline(_closed(body), Pal.INK, ink, true)
	else:
		draw_circle(at, size * 0.86, dark)
		draw_circle(at + Pal.LIGHT * size * 0.30, size * 0.50, light)
		draw_arc(at, size * 0.86, 0, TAU, 20, Pal.INK, ink, true)


func _draw_feature(t: Tile, dim: bool) -> void:
	var h := Hex.hash2(t.coord.x, t.coord.y)

	if t.elev == "mtn":
		var rock := _dimmed(Color("#8a8074"), dim)
		var snowy := t.terrain == "snow" or t.terrain == "tundra"
		# back range first, then the main peak in front of it
		var peaks := [[-0.34, 0.16, 0.62], [0.34, 0.19, 0.72], [0.00, 0.26, 1.0]]
		for spec in peaks:
			var bx: float = t.screen.x + float(spec[0]) * HEX
			var by: float = t.screen.y + float(spec[1]) * HEX
			var hh: float = HEX * 0.80 * float(spec[2])
			var hw: float = HEX * 0.44 * float(spec[2])
			var apex := Vector2(bx, by - hh)
			# a soft shadow pooled at the foot, away from the light
			draw_circle(Vector2(bx - Pal.LIGHT.x * hw * 0.8, by + hh * 0.04), hw * 0.85,
				Pal.with_alpha(Color(0.06, 0.09, 0.13), 0.20))
			# the shaded face, then the lit face over it
			_fill(PackedVector2Array([
				Vector2(bx - hw, by), apex, Vector2(bx + hw, by)]),
				Pal.shaded(rock, 0.42))
			_fill(PackedVector2Array([
				Vector2(bx - hw, by), apex, Vector2(bx - hw * 0.06, by)]),
				Pal.lit(rock, 0.34))
			# a crease down the ridge sells the fold
			draw_line(apex, Vector2(bx - hw * 0.06, by),
				Pal.with_alpha(Pal.shaded(rock, 0.55), 0.5), HEX * 0.012, true)
			var cap := hh * (0.42 if snowy else 0.28)
			var cw := hw * cap / hh
			var snow_col := _dimmed(Color("#f6fafc"), dim)
			_fill(PackedVector2Array([
				apex, apex + Vector2(cw * 1.05, cap * 1.05), apex + Vector2(cw * 0.15, cap * 0.72),
				apex + Vector2(-cw * 0.35, cap * 1.1), apex + Vector2(-cw * 1.05, cap * 0.95)]),
				snow_col)
			_fill(PackedVector2Array([
				apex, apex + Vector2(-cw * 0.35, cap * 1.1), apex + Vector2(-cw * 1.05, cap * 0.95)]),
				Pal.shaded(snow_col, 0.14))
		return

	if t.elev == "hill":
		var ground := _dimmed(tile_colour(t), dim)
		for i in 2:
			_mound(t.screen + Vector2((-0.21 + i * 0.42) * HEX, 0.12 * HEX),
				HEX * 0.27, HEX * 0.19, Pal.shade(ground, 0.24))

	match t.feature:
		"forest", "jungle":
			var jungle := t.feature == "jungle"
			var dark := _dimmed(Pal.JUNGLE if jungle else Pal.FOREST, dim)
			var light := _dimmed(Pal.JUNGLE_HI if jungle else Pal.FOREST_HI, dim)
			var n := 6 if _lod == 2 else 3
			var spots: Array[Vector2] = []
			for i in n:
				var a := (h + i * 0.37) * TAU
				var d := (0.14 + fmod(h * 7.3 + i * 0.41, 1.0) * 0.44) * HEX
				spots.append(t.screen + Vector2(cos(a) * d, sin(a) * d * 0.78))
			spots.sort_custom(func(x, y): return x.y < y.y)
			for i in spots.size():
				var sz := HEX * (0.155 + fmod(h * 3.1 + i * 0.27, 1.0) * 0.05)
				_tree(spots[i], sz, dark, light, not jungle)
		"marsh":
			var reed := _dimmed(Pal.shade(Pal.MARSH, -0.25), dim)
			for i in 4:
				var a2 := (h + i * 0.51) * TAU
				var d2 := fmod(h * 5.1 + i * 0.3, 1.0) * 0.42 * HEX
				var p2 := t.screen + Vector2(cos(a2) * d2, sin(a2) * d2 * 0.8)
				draw_line(p2 + Vector2(-HEX * 0.10, 0), p2 + Vector2(HEX * 0.10, 0),
					reed, HEX * 0.04, true)
				draw_line(p2 + Vector2(0, HEX * 0.05), p2 + Vector2(HEX * 0.02, -HEX * 0.09),
					reed, HEX * 0.03, true)
		"oasis":
			draw_circle(t.screen + Vector2(0, HEX * 0.04), HEX * 0.21,
				_dimmed(Pal.shade(Pal.LAKE, -0.2), dim))
			draw_circle(t.screen, HEX * 0.18, _dimmed(Pal.LAKE, dim))
			for i in 2:
				_tree(t.screen + Vector2((i - 0.5) * HEX * 0.34, -HEX * 0.16),
					HEX * 0.13, _dimmed(Pal.FOREST, dim), _dimmed(Pal.FOREST_HI, dim), false)
		"ice":
			for i in 3:
				var a3 := (h + i * 0.44) * TAU
				var d3 := fmod(h * 3.7 + i * 0.6, 1.0) * 0.42 * HEX
				_fill(Hex.polygon(t.screen + Vector2(cos(a3) * d3, sin(a3) * d3 * 0.8),
					HEX * 0.14), _dimmed(Color("#f2f8fb"), dim))
		_:
			if t.is_water():
				# two lines of swell, brighter on the lit side
				var swell := _dimmed(Pal.COAST_HI if t.terrain != "ocean" else Pal.shade(Pal.OCEAN, 0.22), dim)
				for i in 2:
					var yy := t.screen.y + (-0.16 + i * 0.30) * HEX + (h - 0.5) * HEX * 0.12
					var w := HEX * (0.28 - i * 0.05)
					draw_polyline(_curve(
						Vector2(t.screen.x - w, yy),
						Vector2(t.screen.x, yy - HEX * 0.09),
						Vector2(t.screen.x + w, yy)),
						Pal.with_alpha(swell, 0.42), HEX * 0.035, true)
			elif t.terrain == "desert":
				var dune := _dimmed(Pal.shade(Pal.DESERT, -0.22), dim)
				for i in 2:
					var cy := t.screen.y + (-0.04 + i * 0.24) * HEX
					var w2 := HEX * (0.25 - i * 0.05)
					draw_polyline(_curve(
						Vector2(t.screen.x - w2, cy),
						Vector2(t.screen.x, cy - HEX * 0.12),
						Vector2(t.screen.x + w2, cy)),
						Pal.with_alpha(dune, 0.40), HEX * 0.035, true)
			elif t.terrain == "snow" or t.terrain == "tundra":
				for i in 4:
					var a4 := (h + i * 0.39) * TAU
					var d4 := fmod(h * 3.7 + i * 0.6, 1.0) * 0.46 * HEX
					draw_circle(t.screen + Vector2(cos(a4) * d4, sin(a4) * d4 * 0.8),
						HEX * 0.026, _dimmed(Color("#ffffff"), dim))
			elif _lod == 2 and (t.terrain == "grass" or t.terrain == "plains"):
				var tuft := _dimmed(Pal.shade(tile_colour(t), -0.26), dim)
				for i in 5:
					var a5 := (h + i * 0.43) * TAU
					var d5 := fmod(h * 6.1 + i * 0.37, 1.0) * 0.48 * HEX
					var p5 := t.screen + Vector2(cos(a5) * d5, sin(a5) * d5 * 0.8)
					draw_line(p5 + Vector2(0, HEX * 0.030), p5 + Vector2(-HEX * 0.018, -HEX * 0.028),
						Pal.with_alpha(tuft, 0.5), HEX * 0.017, true)
					draw_line(p5 + Vector2(0, HEX * 0.030), p5 + Vector2(HEX * 0.020, -HEX * 0.024),
						Pal.with_alpha(tuft, 0.5), HEX * 0.017, true)


func _draw_resource(t: Tile, dim: bool) -> void:
	var r: Dictionary = Data.RESOURCE[t.resource]
	var pos := t.screen + Vector2(-HEX * 0.44, HEX * 0.40)
	var ring: Color = Pal.ACCENT
	match r["kind"]:
		"s": ring = Color("#a05fc0")
		"l": ring = Color("#d9a72c")
		_: ring = Color("#57923f")
	ring = _dimmed(ring, dim)
	draw_circle(pos + Vector2(0, HEX * 0.02), HEX * 0.155, Pal.with_alpha(Color.BLACK, 0.22))
	draw_circle(pos, HEX * 0.145, _dimmed(Pal.PANEL, dim))
	draw_arc(pos, HEX * 0.145, 0, TAU, 22, ring, HEX * 0.042, true)
	match r["kind"]:
		"s":
			_fill(PackedVector2Array([
				pos + Vector2(0, -HEX * 0.075), pos + Vector2(HEX * 0.068, HEX * 0.045),
				pos + Vector2(-HEX * 0.068, HEX * 0.045)]), ring)
		"l":
			_fill(PackedVector2Array([
				pos + Vector2(0, -HEX * 0.082), pos + Vector2(HEX * 0.072, 0),
				pos + Vector2(0, HEX * 0.082), pos + Vector2(-HEX * 0.072, 0)]), ring)
		_:
			draw_circle(pos, HEX * 0.058, ring)


func _draw_borders(drawn: Array) -> void:
	var me := Game.me
	for t in drawn:
		if t.owner_id < 0:
			continue
		var p := Game.player(t.owner_id)
		if p == null:
			continue
		var dim := not me.vis.has(t.coord)
		var col := p.colour if not dim else Pal.remembered(p.colour)
		draw_polygon(Hex.polygon(t.screen, HEX * 1.002),
			PackedColorArray([Pal.with_alpha(col, 0.13), Pal.with_alpha(col, 0.13),
				Pal.with_alpha(col, 0.13), Pal.with_alpha(col, 0.13),
				Pal.with_alpha(col, 0.13), Pal.with_alpha(col, 0.13)]))
		for d in 6:
			var nb := Game.world.neighbour(t.coord, d)
			if nb != null and nb.owner_id == t.owner_id:
				continue
			var e := Hex.edge(d, HEX * 0.955)
			# a dark seat under the ribbon so it reads on any ground
			draw_line(t.screen + e[0], t.screen + e[1],
				Pal.with_alpha(Color(0.06, 0.08, 0.11), 0.34), HEX * 0.10, true)
			draw_line(t.screen + e[0], t.screen + e[1], col, HEX * 0.062, true)
			draw_line(t.screen + e[0], t.screen + e[1],
				Pal.with_alpha(Pal.lit(col, 0.5), 0.55), HEX * 0.022, true)


func _draw_overlays(drawn: Array) -> void:
	var u := selected_unit

	if selected_city != null and u == null:
		for t in selected_city.worked:
			draw_arc(t.screen, HEX * 0.30, 0, TAU, 24, Pal.with_alpha(Pal.ACCENT, 0.85), HEX * 0.05, true)

	if u == null or u.dead:
		if hover.x != 9999 and Game.world.has(hover) and Game.me.seen.has(hover):
			var ht := Game.world.at(hover)
			draw_polyline(_closed(Hex.polygon(ht.screen, HEX * 0.99)),
				Pal.with_alpha(Color.WHITE, 0.22), 2.0, true)
		return

	for k in reach:
		var t2 := Game.world.at(k)
		if t2 == null:
			continue
		draw_polygon(Hex.polygon(t2.screen, HEX * 0.93),
			PackedColorArray([Pal.with_alpha(Color.WHITE, 0.10), Pal.with_alpha(Color.WHITE, 0.10),
				Pal.with_alpha(Color.WHITE, 0.10), Pal.with_alpha(Color.WHITE, 0.10),
				Pal.with_alpha(Color.WHITE, 0.10), Pal.with_alpha(Color.WHITE, 0.10)]))

	var pulse := 0.80 + sin(Time.get_ticks_msec() / 460.0) * 0.035
	for t3 in sites:
		draw_polyline(_closed(Hex.polygon(t3.screen, HEX * pulse)),
			Pal.with_alpha(Pal.GOOD, 0.95), HEX * 0.045, true)

	for t4 in targets:
		draw_polygon(Hex.polygon(t4.screen, HEX * 0.93),
			PackedColorArray([Pal.with_alpha(Pal.BAD, 0.20), Pal.with_alpha(Pal.BAD, 0.20),
				Pal.with_alpha(Pal.BAD, 0.20), Pal.with_alpha(Pal.BAD, 0.20),
				Pal.with_alpha(Pal.BAD, 0.20), Pal.with_alpha(Pal.BAD, 0.20)]))
		draw_polyline(_closed(Hex.polygon(t4.screen, HEX * 0.95)), Pal.BAD, HEX * 0.055, true)

	if not path_preview.is_empty():
		var pts := PackedVector2Array([Hex.to_world(u.coord, HEX)])
		for k2 in path_preview:
			pts.append(Hex.to_world(k2, HEX))
		draw_polyline(pts, Pal.with_alpha(Color(0.06, 0.08, 0.11), 0.35), HEX * 0.075, true)
		draw_polyline(pts, Pal.with_alpha(Color.WHITE, 0.75), HEX * 0.040, true)
		draw_circle(pts[pts.size() - 1], HEX * 0.10, Pal.with_alpha(Color.WHITE, 0.85))

	var here := Hex.to_world(u.coord, HEX)
	var ring := 0.985 + sin(Time.get_ticks_msec() / 330.0) * 0.03
	draw_polyline(_closed(Hex.polygon(here, HEX * ring)),
		Pal.with_alpha(Color(0.06, 0.08, 0.11), 0.4), HEX * 0.085, true)
	draw_polyline(_closed(Hex.polygon(here, HEX * ring)), Pal.ACCENT, HEX * 0.055, true)


## A quadratic bend from a to c, bowing through b.
func _curve(a: Vector2, b: Vector2, c: Vector2, steps := 8) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in steps + 1:
		var t := float(i) / float(steps)
		pts.append(a.lerp(b, t).lerp(b.lerp(c, t), t))
	return pts


func _closed(p: PackedVector2Array) -> PackedVector2Array:
	var out := p.duplicate()
	out.append(p[0])
	return out


# =========================================================================
#  Cities
# =========================================================================
func _draw_city(c: City, pos: Vector2, dim: bool) -> void:
	var p := Game.player(c.owner_id)
	var col := p.colour if not dim else Pal.remembered(p.colour)
	var walled := c.has("walls") or c.has("fortress")
	var grand := false
	for s in c.structures:
		if Data.WONDER.has(s):
			grand = true
			break
	var stone := _dimmed(Color("#ddd0b4"), dim)
	var roof := _dimmed(Color("#b8563a"), dim)

	# it stands on the ground it stands on: just a contact shadow
	draw_circle(pos + Vector2(0, HEX * 0.20), HEX * 0.30,
		Pal.with_alpha(Color(0.05, 0.07, 0.10), 0.26))

	if walled:
		draw_arc(pos + Vector2(0, HEX * 0.05), HEX * 0.43, 0, TAU, 40,
			Pal.shaded(stone, 0.40), HEX * 0.10, true)
		draw_arc(pos + Vector2(0, HEX * 0.05), HEX * 0.43, PI * 0.92, TAU * 1.03, 22,
			Pal.lit(stone, 0.32), HEX * 0.055, true)
		if _lod == 2:
			for i in 12:
				var a := TAU * (float(i) / 12.0)
				var at := pos + Vector2(0, HEX * 0.05) + Vector2(cos(a), sin(a)) * HEX * 0.43
				_fill(Hex.polygon(at, HEX * 0.040),
					Pal.lit(stone, 0.20) if sin(a) < 0.0 else Pal.shaded(stone, 0.25))

	# the keep, in the nation's colour, with its banner
	var kw := HEX * 0.215
	var kh := HEX * 0.46
	var ky := pos.y + HEX * 0.08
	draw_circle(Vector2(pos.x + kw * 0.6, ky + HEX * 0.02), kw * 0.85, Pal.with_alpha(Color.BLACK, 0.18))
	_fill(PackedVector2Array([
		Vector2(pos.x - kw, ky - kh), Vector2(pos.x, ky - kh),
		Vector2(pos.x, ky), Vector2(pos.x - kw, ky)]), Pal.lit(col, 0.22))
	_fill(PackedVector2Array([
		Vector2(pos.x, ky - kh), Vector2(pos.x + kw, ky - kh),
		Vector2(pos.x + kw, ky), Vector2(pos.x, ky)]), Pal.shaded(col, 0.28))
	_fill(PackedVector2Array([
		Vector2(pos.x - kw * 1.22, ky - kh), Vector2(pos.x, ky - kh - HEX * 0.17),
		Vector2(pos.x + kw * 1.22, ky - kh)]), Pal.shaded(col, 0.12))
	if _lod == 2:
		draw_line(Vector2(pos.x, ky - kh - HEX * 0.17), Vector2(pos.x, ky - kh - HEX * 0.40),
			_dimmed(Color("#efe7d6"), dim), HEX * 0.020, true)
		_fill(PackedVector2Array([
			Vector2(pos.x, ky - kh - HEX * 0.40), Vector2(pos.x + HEX * 0.17, ky - kh - HEX * 0.335),
			Vector2(pos.x, ky - kh - HEX * 0.27)]), Pal.lit(col, 0.15))

	# buildings, back to front so they overlap correctly
	var n := clampi(3 + int(c.pop / 2.4), 3, 6)
	var h0 := Hex.hash2(c.coord.x, c.coord.y)
	var houses: Array = []
	for i in n:
		var a2 := (float(i) / n) * TAU + h0 * TAU
		var d := HEX * (0.20 + float(i % 2) * 0.13)
		houses.append(Vector2(pos.x + cos(a2) * d, pos.y + absf(sin(a2)) * d * 0.42 + HEX * 0.10))
	houses.sort_custom(func(x, y): return x.y < y.y)
	for i in houses.size():
		var b: Vector2 = houses[i]
		var w := HEX * 0.255
		var ht := HEX * (0.26 + fmod(h0 * 4.3 + i * 0.31, 1.0) * 0.12)
		draw_circle(b + Vector2(w * 0.45, HEX * 0.02), w * 0.70, Pal.with_alpha(Color.BLACK, 0.20))
		_fill(PackedVector2Array([
			b + Vector2(-w * 0.5, -ht), b + Vector2(0, -ht), b + Vector2(0, 0), b + Vector2(-w * 0.5, 0)]),
			Pal.lit(stone, 0.20))
		_fill(PackedVector2Array([
			b + Vector2(0, -ht), b + Vector2(w * 0.5, -ht), b + Vector2(w * 0.5, 0), b + Vector2(0, 0)]),
			Pal.shaded(stone, 0.22))
		_fill(PackedVector2Array([
			b + Vector2(-w * 0.78, -ht), b + Vector2(0, -ht - HEX * 0.145),
			b + Vector2(w * 0.78, -ht)]), roof)
		_fill(PackedVector2Array([
			b + Vector2(-w * 0.78, -ht), b + Vector2(0, -ht - HEX * 0.145),
			b + Vector2(0, -ht)]), Pal.lit(roof, 0.26))

	if grand and _lod == 2:
		var dome := pos + Vector2(-HEX * 0.29, ky - pos.y - HEX * 0.09)
		draw_circle(dome, HEX * 0.10, _dimmed(Pal.ACCENT_DEEP, dim))
		draw_circle(dome + Pal.LIGHT * HEX * 0.03, HEX * 0.065, _dimmed(Pal.ACCENT, dim))

	# population, on its own disc
	var pop_at := pos + Vector2(-HEX * 0.34, -HEX * 0.30)
	draw_circle(pop_at + Vector2(0, HEX * 0.02), HEX * 0.165, Pal.with_alpha(Color.BLACK, 0.25))
	draw_circle(pop_at, HEX * 0.155, col)
	draw_arc(pop_at, HEX * 0.155, PI, TAU, 18, Pal.with_alpha(Pal.lit(col, 0.55), 0.9), HEX * 0.03, true)
	_text_centred(str(c.pop), pop_at + Vector2(0, 1), 15, Color.WHITE, false)

	if c.is_capital:
		var star := pos + Vector2(HEX * 0.30, -HEX * 0.32)
		_fill(PackedVector2Array([
			star + Vector2(0, -HEX * 0.11), star + Vector2(HEX * 0.033, -HEX * 0.033),
			star + Vector2(HEX * 0.11, 0), star + Vector2(HEX * 0.033, HEX * 0.033),
			star + Vector2(0, HEX * 0.11), star + Vector2(-HEX * 0.033, HEX * 0.033),
			star + Vector2(-HEX * 0.11, 0), star + Vector2(-HEX * 0.033, -HEX * 0.033)]),
			_dimmed(Pal.ACCENT, dim))

	if c.hp < c.max_hp:
		var frac := float(c.hp) / float(c.max_hp)
		var bar_w := HEX * 0.62
		var y := pos.y + HEX * 0.44
		draw_line(Vector2(pos.x - bar_w * 0.5, y), Vector2(pos.x + bar_w * 0.5, y),
			Pal.with_alpha(Color.BLACK, 0.45), HEX * 0.085, true)
		draw_line(Vector2(pos.x - bar_w * 0.5, y),
			Vector2(pos.x - bar_w * 0.5 + bar_w * frac, y),
			Pal.GOOD if frac > 0.5 else (Pal.WARN if frac > 0.25 else Pal.BAD), HEX * 0.065, true)

	if camera != null and camera.zoom.x > 0.62:
		var label := c.name
		var font := Pal.bold()
		var size := 15
		var tw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		var box := Rect2(pos.x - tw * 0.5 - 8.0, pos.y + HEX * 0.54, tw + 16.0, 22.0)
		draw_rect(Rect2(box.position + Vector2(0, 2), box.size), Pal.with_alpha(Color.BLACK, 0.25))
		draw_rect(box, _dimmed(Pal.PANEL, dim))
		draw_rect(Rect2(box.position, Vector2(box.size.x, 2.5)), col)
		_text_centred(label, Vector2(pos.x, box.position.y + 15.0), size,
			_dimmed(Pal.INK, dim), false)


# =========================================================================
#  Units
# =========================================================================
func _draw_unit(u: Unit, stacked: bool) -> void:
	var p := Game.player(u.owner_id)
	var t := Game.world.at(u.coord)
	var pos := (u.draw_pos if u.draw_init else Hex.to_world(u.coord, HEX)) + _lunge_offset(u)
	var civilian := u.is_civilian()

	var in_city := t != null and t.city != null
	if in_city:
		# tucked against the town rather than standing beside it, so the
		# settlement stays the thing you read first
		pos += Vector2(HEX * 0.40, HEX * 0.24) if not civilian else Vector2(-HEX * 0.42, HEX * 0.22)
	elif stacked:
		pos += Vector2(-HEX * 0.20, HEX * 0.16) if civilian else Vector2(HEX * 0.16, -HEX * 0.03)

	var r := HEX * (0.255 if civilian else 0.305)
	if in_city:
		r *= 0.56
	var spent := p == Game.me and (u.done or u.mv <= 0)
	var col := p.colour
	if spent:
		col = Pal.desaturate(col, 0.45).lerp(Color("#6a7280"), 0.30)

	# a printed token: one flat plate, a screen of dots away from the light,
	# and a keyline heavy enough to hold it off a loud tile
	if civilian:
		_rounded_rect(Rect2(pos.x - r, pos.y - r * 0.88, r * 2.0, r * 1.76), r * 0.30, col)
		_stroke_rounded_rect(Rect2(pos.x - r, pos.y - r * 0.88, r * 2.0, r * 1.76),
			r * 0.30, Pal.INK, r * 0.19)
	else:
		draw_circle(pos, r, col)
		_benday_disc(pos, r, col)
		draw_arc(pos, r, 0, TAU, 32, Pal.INK, r * 0.19, true)

	if u.embarked:
		draw_arc(pos, r * 1.14, 0, TAU, 28, Pal.with_alpha(Pal.COAST_HI, 0.9), r * 0.09, true)
	if p == Game.me and not spent:
		draw_arc(pos, r * 1.24, 0, TAU, 30, Pal.with_alpha(Pal.ACCENT, 0.85), r * 0.085, true)

	var glyph_name: String = Data.UNIT[u.type].get("glyph", "sword")
	if u.embarked:
		glyph_name = "boat"
	_draw_glyph(glyph_name, pos + Vector2(0, r * 0.075), r / 12.4, Pal.INK)
	_draw_glyph(glyph_name, pos, r / 13.0, Pal.PAPER_HI)

	if u.rank > 0:
		for i in u.rank:
			var at := pos + Vector2((i - (u.rank - 1) * 0.5) * r * 0.42, r * 1.02)
			draw_circle(at + Vector2(0, r * 0.04), r * 0.13, Pal.with_alpha(Color.BLACK, 0.3))
			draw_circle(at, r * 0.115, Pal.ACCENT)
	if u.fortified > 0:
		draw_arc(pos, r * 1.44, -2.30, -0.84, 14, Pal.with_alpha(Pal.ACCENT, 0.85), r * 0.10, true)

	if u.hp < Data.HP_MAX:
		var frac := float(u.hp) / float(Data.HP_MAX)
		var bw := r * 1.85
		var y := pos.y - r - r * 0.46
		draw_line(Vector2(pos.x - bw * 0.5, y), Vector2(pos.x + bw * 0.5, y),
			Pal.with_alpha(Color.BLACK, 0.55), r * 0.24, true)
		draw_line(Vector2(pos.x - bw * 0.5, y), Vector2(pos.x - bw * 0.5 + bw * frac, y),
			Pal.GOOD if frac > 0.55 else (Pal.WARN if frac > 0.28 else Pal.BAD), r * 0.18, true)


## The dot screen again, clipped to a disc, for tokens and city walls.
func _benday_disc(centre: Vector2, radius: float, col: Color, density := 0.44) -> void:
	if _dots.is_empty():
		_build_dots()
	var dot := Pal.dot_over(col)
	var cut := 1.0 - density * 2.0
	var dr := radius * 0.105
	for d in _dots:
		var off: Vector2 = d["off"]
		if off.length() > 0.86 or float(d["shade"]) < cut:
			continue
		draw_circle(centre + off * radius * 0.94, dr, dot)


func _stroke_rounded_rect(rect: Rect2, radius: float, col: Color, width: float) -> void:
	var pts := PackedVector2Array()
	var corners := [
		[Vector2(rect.position.x + radius, rect.position.y + radius), PI, PI * 1.5],
		[Vector2(rect.end.x - radius, rect.position.y + radius), PI * 1.5, TAU],
		[Vector2(rect.end.x - radius, rect.end.y - radius), 0.0, PI * 0.5],
		[Vector2(rect.position.x + radius, rect.end.y - radius), PI * 0.5, PI],
	]
	for c in corners:
		var centre: Vector2 = c[0]
		for i in 5:
			var a: float = lerpf(c[1], c[2], float(i) / 4.0)
			pts.append(centre + Vector2(cos(a), sin(a)) * radius)
	draw_polyline(_closed(pts), col, width, true)


func _rounded_rect(rect: Rect2, radius: float, col: Color) -> void:
	var pts := PackedVector2Array()
	var corners := [
		[Vector2(rect.position.x + radius, rect.position.y + radius), PI, PI * 1.5],
		[Vector2(rect.end.x - radius, rect.position.y + radius), PI * 1.5, TAU],
		[Vector2(rect.end.x - radius, rect.end.y - radius), 0.0, PI * 0.5],
		[Vector2(rect.position.x + radius, rect.end.y - radius), PI * 0.5, PI],
	]
	for c in corners:
		var centre: Vector2 = c[0]
		var a0: float = c[1]
		var a1: float = c[2]
		for i in 7:
			var a := lerpf(a0, a1, float(i) / 6.0)
			pts.append(centre + Vector2(cos(a), sin(a)) * radius)
	_fill(pts, col)


# =========================================================================
#  Unit glyphs — filled silhouettes, because at token size nothing else reads
#  Drawn in a box of roughly -12..12 and scaled to the token.
# =========================================================================
func _draw_glyph(name: String, at: Vector2, scale: float, col: Color) -> void:
	draw_set_transform(at, 0.0, Vector2(scale, scale))
	var dark := Pal.with_alpha(Pal.INK, 0.55)
	match name:
		"sword":
			_poly([[0,-11],[2.6,-5],[1.9,3],[-1.9,3],[-2.6,-5]], col)
			_bar(-5.5, 3.4, 5.5, 3.4, 2.4, col)
			_bar(0, 3.4, 0, 8, 2.2, col)
			draw_circle(Vector2(0, 9), 1.7, col)
		"gladius", "axe":
			if name == "gladius":
				_poly([[0,-8.5],[3.6,-4],[2.6,3],[-2.6,3],[-3.6,-4]], col)
				_bar(-5, 3.4, 5, 3.4, 2.6, col)
				_bar(0, 3.4, 0, 7.5, 2.4, col)
			else:
				_bar(-1.6, -9.5, -1.6, 10, 2.4, col)                  # haft
				# a crescent: outer sweep out, inner sweep back to the haft
				var blade := PackedVector2Array()
				for i in 11:
					var a := lerpf(-1.15, 1.15, float(i) / 10.0)
					blade.append(Vector2(-3.0, -4.4) + Vector2(cos(a), sin(a)) * 10.5)
				for i in 9:
					var a2 := lerpf(1.0, -1.0, float(i) / 8.0)
					blade.append(Vector2(-2.2, -4.4) + Vector2(cos(a2), sin(a2)) * 4.4)
				_fill(blade, col)
		"spear":
			_bar(0, -4, 0, 10, 2.0, col)
			_poly([[0,-10.5],[3.2,-4.5],[0,-2.8],[-3.2,-4.5]], col)
		"sling":
			_bar(0, 2, 0, 9, 2.4, col)
			_bar(0, 2, -5, -4, 2.4, col)
			_bar(0, 2, 5, -4, 2.4, col)
			draw_circle(Vector2(0, -3.2), 2.4, col)
		"bow":
			var limb := PackedVector2Array()
			for i in 15:
				var a := lerpf(PI - 1.12, PI + 1.12, float(i) / 14.0)
				limb.append(Vector2(3.4, 0.0) + Vector2(cos(a), sin(a)) * 9.2)
			draw_polyline(limb, col, 2.7, true)
			_bar(-0.6, -8.3, -0.6, 8.3, 1.4, col)                     # string
			_bar(-2.5, 0, 7.5, 0, 2.0, col)                           # shaft
			_poly([[10.5,0],[6.5,-2.8],[6.5,2.8]], col)               # head
		"xbow":
			_poly([[-11,-6.6],[-1.5,-4.6],[-1.5,-2.2],[-11,-3.6]], col)   # left limb
			_poly([[11,-6.6],[1.5,-4.6],[1.5,-2.2],[11,-3.6]], col)       # right limb
			_bar(-10.5, -6.2, 10.5, -6.2, 1.3, col)                       # string
			_poly([[-1.8,-5.6],[1.8,-5.6],[1.8,6.5],[-1.8,8.6]], col)     # stock
			_poly([[-5.4,4.2],[1.8,4.2],[1.8,6.8],[-5.4,6.8]], col)       # grip
		"horse", "knight", "chariot":
			# built from simple convex parts: one concave outline collapses
			# into a blob at token size
			_poly([[-7,-1],[5,-2],[6,3],[-7,3]], col)                 # body
			_poly([[3,-2],[7,-9],[9.5,-8],[5.5,-1]], col)             # neck
			_poly([[6,-11],[11.5,-9.5],[10.5,-6],[5.5,-7]], col)      # head
			_poly([[6.6,-11],[7.4,-13.6],[9.2,-10.6]], col)           # ear
			_poly([[-10,-4],[-6.5,-1.5],[-6.5,2.5],[-9.5,2]], col)    # tail
			for lx in [-6.4, -3.9, 0.6, 3.1]:
				_poly([[lx,2],[lx+2,2],[lx+2,9],[lx,9]], col)         # legs
			draw_circle(Vector2(9.0, -8.3), 1.0, dark)                # eye
			if name == "knight":
				_poly([[5.6,-10.8],[4.0,-14.6],[8.2,-13.2],[9.4,-10.2]], col)  # crest
			elif name == "chariot":
				draw_arc(Vector2(-4, 6), 3.6, 0, TAU, 18, col, 1.8, true)
		"elephant":
			_poly([[-4,-4],[7,-5],[9,3],[-4,4]], col)                 # body
			_poly([[-9.5,-3],[-3.5,-5],[-2.5,3],[-9.5,3]], col)       # head
			_poly([[-9.5,0.5],[-7.2,0.5],[-7.8,4.5],[-6.6,8.5],[-9.2,9],[-10.6,4.5]], col)
			_poly([[-8.6,3.4],[-12,6.6],[-10.2,7.2]], col)            # tusk
			for lx in [-3.4, 0.6, 4.4]:
				_poly([[lx,3],[lx+2.4,3],[lx+2.4,9],[lx,9]], col)     # legs
			draw_circle(Vector2(-4.6, -0.6), 3.4, dark)               # ear
			draw_circle(Vector2(-8.4, -1.6), 1.0, dark)               # eye
		"catapult":
			_bar(-8, 7, 8, 7, 2.0, col)
			draw_circle(Vector2(-4.5, 7.5), 2.9, col)
			draw_circle(Vector2(4.5, 7.5), 2.9, col)
			draw_circle(Vector2(-4.5, 7.5), 1.1, dark)
			draw_circle(Vector2(4.5, 7.5), 1.1, dark)
			_bar(-6, 6, 4, -7, 2.6, col)
			draw_circle(Vector2(5.5, -8.5), 3.0, col)
		"bombard", "arty":
			_poly([[-9,3],[-2,3],[9,-5],[7.5,-8],[-4,-1],[-9,-1]], col)
			_bar(-7, 3, -7, 7, 2.2, col)
			draw_circle(Vector2(-5, 7.5), 3.2, col)
			draw_circle(Vector2(-5, 7.5), 1.2, dark)
			_bar(-8, 4, 4, 9, 2.0, col)
		"rocket":
			_poly([[0,-11],[3.4,-3],[3.4,5],[-3.4,5],[-3.4,-3]], col)
			_poly([[3.4,4],[8,9.5],[3.4,9.5]], col)
			_poly([[-3.4,4],[-8,9.5],[-3.4,9.5]], col)
			draw_circle(Vector2(0, -3.5), 1.7, dark)
		"musket", "rifle":
			_poly([[6,-10],[8.5,-8.6],[-2,6],[-4.5,4.5]], col)
			_poly([[-3,4],[-1,5.5],[-5.5,10.5],[-8.5,9]], col)
			_bar(-1, 1, 2, 3, 1.8, col)
		"infantry":
			_poly([[-5.2,-5.4],[-4.0,-9.6],[4.0,-9.6],[5.2,-5.4]], col)   # helmet
			_poly([[-7.2,-5.4],[7.2,-5.4],[6.6,-3.4],[-6.6,-3.4]], col)   # brim
			_poly([[-4.6,-2.2],[4.6,-2.2],[3.6,4],[-3.6,4]], col)         # chest
			_poly([[-4.2,4],[-1.0,4],[-1.0,9.6],[-4.2,9.6]], col)         # legs
			_poly([[1.0,4],[4.2,4],[4.2,9.6],[1.0,9.6]], col)
			_bar(9.0, -9.0, 3.2, 6.0, 2.4, col)                           # slung rifle
		"tank":
			_poly([[-9,2],[9,2],[9,7.5],[-9,7.5]], col)
			for i in 5:
				draw_circle(Vector2(-7 + i * 3.5, 5), 1.1, dark)
			_poly([[-6,-4.5],[3.5,-4.5],[4.5,1],[-7,1]], col)
			_poly([[3.5,-4],[11,-4],[11,-1.8],[3.5,-1.8]], col)
		"settler":
			var hood := PackedVector2Array()
			for i in 15:
				var a := PI + PI * (float(i) / 14.0)
				hood.append(Vector2(cos(a) * 7.6, 2.0 + sin(a) * 7.0))
			_fill(hood, col)
			_poly([[-8.6,1.6],[8.6,1.6],[7.6,5.2],[-7.6,5.2]], col)   # wagon bed
			draw_circle(Vector2(-4.8, 7.0), 2.8, col)
			draw_circle(Vector2(4.8, 7.0), 2.8, col)
			draw_circle(Vector2(-4.8, 7.0), 1.1, dark)
			draw_circle(Vector2(4.8, 7.0), 1.1, dark)
		"scout":
			draw_set_transform(at, -0.6, Vector2(scale, scale))
			_poly([[-9,-2.6],[1,-2.0],[1,2.0],[-9,2.6]], col)
			_poly([[1,-3.4],[9,-4.6],[9,4.6],[1,3.4]], col)
			draw_set_transform(at, 0.0, Vector2(scale, scale))
		"eagle":
			_poly([[-2.4,-5],[2.4,-5],[2.0,6],[0,9.5],[-2.0,6]], col)  # body
			_poly([[-2.4,-4.6],[-12.5,-3],[-11,2],[-2.4,3.4]], col)
			_poly([[2.4,-4.6],[12.5,-3],[11,2],[2.4,3.4]], col)
			draw_circle(Vector2(0, -6.4), 2.6, col)                    # head
			_poly([[0,-8.4],[4,-7.2],[0,-5.6]], col)                   # beak
		"boat":
			_poly([[-9,1],[9,1],[6,7],[-6,7]], col)
			_bar(0, 1, 0, -9, 1.9, col)
			_poly([[0.9,-9.5],[7.5,-4],[0.9,-2.5]], col)
		_:
			draw_circle(Vector2.ZERO, 5.5, col)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _poly(points: Array, col: Color) -> void:
	var pts := PackedVector2Array()
	for p in points:
		pts.append(Vector2(p[0], p[1]))
	_fill(pts, col)


## draw_colored_polygon fans triangles from the first vertex, which is only
## correct for convex shapes — a horse's head came out as a blob. Triangulate.
func _fill(pts: PackedVector2Array, col: Color) -> void:
	if pts.size() < 3:
		return
	var idx := Geometry2D.triangulate_polygon(pts)
	if idx.is_empty():
		draw_colored_polygon(pts, col)
		return
	var i := 0
	while i + 2 < idx.size():
		draw_colored_polygon(PackedVector2Array([
			pts[idx[i]], pts[idx[i + 1]], pts[idx[i + 2]]]), col)
		i += 3


func _bar(x0: float, y0: float, x1: float, y1: float, w: float, col: Color) -> void:
	draw_line(Vector2(x0, y0), Vector2(x1, y1), col, w, true)


func _text_centred(text: String, at: Vector2, size: int, col: Color, shadow: bool) -> void:
	var font := Pal.bold()
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var pos := at - Vector2(w * 0.5, -size * 0.36)
	if shadow:
		# a dark seat under the glyphs, so numbers read over bright ground too
		for off in [Vector2(0, 2), Vector2(1.5, 0), Vector2(-1.5, 0)]:
			draw_string(font, pos + off, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size,
				Color(0.05, 0.07, 0.10, col.a * 0.75))
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


## Dev only: every glyph, large, through exactly the code the map uses.
func _draw_glyph_sheet() -> void:
	var names: Array[String] = []
	var labels: Array[String] = []
	var seen := {}
	for key in Data.UNIT:
		var gname: String = Data.UNIT[key].get("glyph", "sword")
		if seen.has(gname):
			continue
		seen[gname] = true
		names.append(gname)
		labels.append(Data.UNIT[key]["name"])
	names.append("boat")
	labels.append("at sea")

	var cols := 6
	var cell := Vector2(190, 190)
	var pal: Array[Color] = [Pal.CIV_COLOURS["crimson"], Pal.CIV_COLOURS["indigo"],
		Pal.CIV_COLOURS["teal"], Pal.CIV_COLOURS["amber"], Pal.CIV_COLOURS["plum"],
		Pal.CIV_COLOURS["olive"]]
	for i in names.size():
		var at := Vector2((i % cols) * cell.x, int(i / float(cols)) * cell.y)
		var col: Color = pal[i % pal.size()]
		var r := 52.0
		draw_circle(at + Vector2(0, r * 0.55), r * 0.92, Pal.with_alpha(Color.BLACK, 0.30))
		draw_circle(at, r, Pal.shaded(col, 0.26))
		draw_circle(at + Pal.LIGHT * r * 0.20, r * 0.82, col)
		draw_circle(at + Pal.LIGHT * r * 0.34, r * 0.52, Pal.lit(col, 0.16))
		draw_arc(at, r, 0, TAU, 36, Pal.with_alpha(Color(0.07, 0.09, 0.12), 0.75), r * 0.13, true)
		draw_arc(at, r * 0.99, PI * 0.85, TAU * 0.98, 22,
			Pal.with_alpha(Pal.lit(col, 0.65), 0.85), r * 0.09, true)
		_draw_glyph(names[i], at, r / 13.0, Pal.PANEL)
		_text_centred(labels[i], at + Vector2(0, r + 24.0), 17, Color("#e8eef4"), false)
		_text_centred(names[i], at + Vector2(0, r + 44.0), 13, Color("#8fa0b2"), false)
