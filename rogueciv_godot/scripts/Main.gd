extends Node2D

## Wires the world, the camera and the interface together, and owns input.

const HEX := 46.0
const ZOOM_MIN := 0.42
const ZOOM_MAX := 2.10

var camera: Camera2D
var map: Node2D
var ui: CanvasLayer

var _dragging := false
var _drag_from := Vector2.ZERO
var _drag_cam := Vector2.ZERO
var _drag_moved := false

# --- dev harness: --shot <file> --seed N --turns N --leader id --auto ------
var _shot_path := ""
var _shot_frames := 0
var _shot_after := 22
var _run_tests := false
var _unit_sheet := false
var _glyph_sheet := false
var _modal := ""
var _select := ""
var _boot_only := false
var _fight := false
var _sim_games := 0
var _in_menu := false
var _menu_drift := 0.0


func _ready() -> void:
	camera = Camera2D.new()
	camera.zoom = Vector2(0.95, 0.95)
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 12.0
	add_child(camera)
	camera.make_current()

	map = preload("res://scripts/MapView.gd").new()
	map.camera = camera
	add_child(map)

	ui = preload("res://scripts/Ui.gd").new()
	ui.map = map
	ui.main = self
	add_child(ui)
	ui.mini.camera = camera
	ui.mini.jumped.connect(func(c: Vector2i):
		centre_on(c)
		map.queue_redraw())

	Game.run_ended.connect(_on_run_ended)
	map.selection_changed.connect(func(): ui.refresh())

	_parse_args()
	if _shot_path == "":
		_open_menu()
	set_process(true)


func _parse_args() -> void:
	var args := OS.get_cmdline_user_args()
	var seed_value := 12345
	var leader := "nefertiti"
	var turns := 0
	var diff := 1
	var auto := false
	var i := 0
	while i < args.size():
		match args[i]:
			"--shot":
				i += 1
				_shot_path = args[i]
			"--seed":
				i += 1
				seed_value = int(args[i])
			"--leader":
				i += 1
				leader = args[i]
			"--turns":
				i += 1
				turns = int(args[i])
			"--diff":
				i += 1
				diff = int(args[i])
			"--frames":
				i += 1
				_shot_after = int(args[i])
			"--auto":
				auto = true
			"--zoom":
				i += 1
				camera.zoom = Vector2(float(args[i]), float(args[i]))
			"--test":
				_run_tests = true
			"--units":
				_unit_sheet = true
			"--glyphs":
				_glyph_sheet = true
			"--modal":
				i += 1
				_modal = args[i]
			"--select":
				i += 1
				_select = args[i]
			"--boot":
				_boot_only = true
			"--fight":
				_fight = true
			"--sim":
				i += 1
				_sim_games = int(args[i])
			"--mute":
				Snd.enabled = false
		i += 1
	# Screenshots and tests open a real window: never make a noise in one.
	# This sets the flag directly rather than going through toggle(), so a dev
	# run never writes "muted" into the player's own settings.
	if _shot_path != "" or _run_tests or _glyph_sheet or _unit_sheet:
		Snd.enabled = false
		Save.use_dev_slot()
		print("sound: muted for this dev run; saving to the dev slot")
	if _sim_games > 0:
		Snd.enabled = false
		Save.use_dev_slot()
		_run_sim(_sim_games, seed_value, diff)
		get_tree().quit(0)
		return
	if _run_tests:
		var failures := Tests.run(Game, self)
		get_tree().quit(1 if failures > 0 else 0)
		return
	if _shot_path == "":
		return
	if _boot_only:
		_open_menu(seed_value)      # exactly what a player sees on launch
		return
	Game.new_run(seed_value, leader, diff)
	if turns > 0:
		var was_human := Game.me.is_human
		if auto:
			Game.me.is_human = false
		for t in turns:
			if Game.over:
				break
			Game.run_turn()
		Game.me.is_human = was_human
		Game.pending_drafts = 0
	if _glyph_sheet:
		map.sheet_mode = true
		camera.position = Vector2(475, 360)
		camera.zoom = Vector2(0.95, 0.95)
		ui.root.visible = false
		map.queue_redraw()
		return
	if _unit_sheet:
		_lay_out_every_unit()
	map.floaters.clear()
	ui.begin_run_ui()
	if Game.me.capital != null:
		camera.position = Hex.to_world(Game.me.capital.coord, HEX)
	camera.position_smoothing_enabled = false
	ui.refresh()
	map.queue_redraw()
	match _select:
		"unit":
			for u in Game.me.units:
				if not u.is_civilian() and Game.reachable(u).size() > 0:
					map.select_unit(u)
					camera.position = Hex.to_world(u.coord, HEX)
					break
		"settler":
			for u in Game.me.units:
				if u.is_civilian():
					map.select_unit(u)
					camera.position = Hex.to_world(u.coord, HEX)
					break
		"city":
			if not Game.me.cities.is_empty():
				map.select_city(Game.me.cities[0])
				camera.position = Hex.to_world(Game.me.cities[0].coord, HEX)
	match _modal:
		"start": ui.show_start_screen()
		"draft": ui.show_draft()
		"build": ui.show_build_menu(Game.me.cities[0])
		"nations": ui.show_nations()
		"cities": ui.show_cities()
		"edicts": ui.show_edicts()
		"help": ui.show_help()
		"pause": ui.show_pause()
		"event":
			for ev in EventData.LIST:
				if ev["id"] == "refugees":
					Game.pending_event = ev
			ui.show_event()
		"over": Game.end_run(true, "beacon")
		"promotion":
			var u := Game.me.units[0]
			for v in Game.me.units:
				if not v.is_civilian():
					u = v
					break
			u.rank = 2
			Game.pending_promotions.append(u)
			ui.show_promotion()


## A world of its own turns quietly behind the menu. It is thrown away the
## moment a leader is chosen.
func _open_menu(fixed_seed := -1) -> void:
	var seed_value := fixed_seed
	if seed_value < 0:
		seed_value = int(Time.get_unix_time_from_system() * 977.0) % 1000000007
	var pool := EdictData.LEADERS
	Game.new_run(seed_value, str(pool[seed_value % pool.size()]["id"]), 1)
	for t in Game.world.list:
		Game.me.seen[t.coord] = true
		Game.me.vis[t.coord] = true
	_in_menu = true
	_menu_drift = 0.0
	camera.position_smoothing_enabled = false
	camera.zoom = Vector2(1.15, 1.15)
	map.clear_selection()
	map.queue_redraw()
	ui.enter_menu_mode()
	ui.show_start_screen()


func resume_run() -> void:
	_in_menu = false
	if not Save.read(Game):
		ui.show_start_screen()
		return
	ui.begin_run_ui()
	camera.position_smoothing_enabled = false
	if Game.me.capital != null:
		camera.position = Hex.to_world(Game.me.capital.coord, HEX)
	camera.zoom = Vector2(0.95, 0.95)
	await get_tree().process_frame
	camera.position_smoothing_enabled = true
	map.clear_selection()
	ui.refresh()
	map.queue_redraw()
	await get_tree().create_timer(0.3).timeout
	map.next_idle_unit(false)


func start_run(seed_value: int, leader: String, difficulty: int) -> void:
	_in_menu = false
	Game.new_run(seed_value, leader, difficulty)
	ui.begin_run_ui()
	camera.position_smoothing_enabled = false
	camera.position = Hex.to_world(Game.me.capital.coord, HEX)
	camera.zoom = Vector2(0.95, 0.95)
	await get_tree().process_frame
	camera.position_smoothing_enabled = true
	map.clear_selection()
	ui.refresh()
	map.queue_redraw()
	await get_tree().create_timer(0.35).timeout
	map.next_idle_unit(false)


func _process(_delta: float) -> void:
	if _shot_path != "":
		_shot_frames += 1
		if _fight and _shot_frames == maxi(2, _shot_after - 9):
			_stage_a_fight()
		if _shot_frames == _shot_after:
			var img := get_viewport().get_texture().get_image()
			img.save_png(_shot_path)
			print("SHOT-SAVED ", _shot_path)
			get_tree().quit()
		return
	if _in_menu:
		_menu_drift += _delta * 0.06
		var r := Game.world.radius * HEX * 0.20 if Game.world != null else 120.0
		camera.position = Vector2(cos(_menu_drift) * r, sin(_menu_drift * 0.8) * r * 0.55)
		map.queue_redraw()
		return
	var pan := Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		pan.y -= 1
	if Input.is_key_pressed(KEY_S) and map.selected_unit == null:
		pan.y += 1
	if Input.is_key_pressed(KEY_DOWN):
		pan.y += 1
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		pan.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		pan.x += 1
	if pan != Vector2.ZERO:
		camera.position += pan.normalized() * (900.0 * _delta) / camera.zoom.x
		_clamp_camera()


func _clamp_camera() -> void:
	var lim := Game.world.radius * HEX * 2.0 if Game.world != null else 2000.0
	camera.position.x = clampf(camera.position.x, -lim, lim)
	camera.position.y = clampf(camera.position.y, -lim * 0.9, lim * 0.9)


func centre_on(c: Vector2i) -> void:
	camera.position = Hex.to_world(c, HEX)
	_clamp_camera()


func _zoom_at(factor: float, screen_point: Vector2) -> void:
	var before := _screen_to_world(screen_point)
	camera.zoom = Vector2(clampf(camera.zoom.x * factor, ZOOM_MIN, ZOOM_MAX),
						  clampf(camera.zoom.y * factor, ZOOM_MIN, ZOOM_MAX))
	var after := _screen_to_world(screen_point)
	camera.position += before - after
	_clamp_camera()
	map.queue_redraw()


func _screen_to_world(p: Vector2) -> Vector2:
	return camera.global_position + (p - get_viewport_rect().size * 0.5) / camera.zoom


# =========================================================================
#  Input
# =========================================================================
func _unhandled_input(event: InputEvent) -> void:
	if Game.world == null:
		return
	# Escape has to reach a modal, so it is handled before the modal guard
	if event is InputEventKey and event.pressed and not event.echo 			and (event as InputEventKey).keycode == KEY_ESCAPE and ui.modal_open():
		ui.escape_modal()
		return
	if ui.modal_open():
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					_zoom_at(1.12, mb.position)
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					_zoom_at(1.0 / 1.12, mb.position)
			MOUSE_BUTTON_LEFT:
				if mb.pressed:
					_dragging = true
					_drag_moved = false
					_drag_from = mb.position
					_drag_cam = camera.position
				else:
					_dragging = false
					if not _drag_moved:
						_click(mb.position)
			MOUSE_BUTTON_RIGHT:
				if mb.pressed:
					map.clear_selection()
					ui.refresh()

	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _dragging:
			if mm.position.distance_to(_drag_from) > 6.0:
				_drag_moved = true
			if _drag_moved:
				camera.position = _drag_cam - (mm.position - _drag_from) / camera.zoom
				_clamp_camera()
				map.queue_redraw()
			return
		_update_hover(mm.position)

	elif event is InputEventKey and event.pressed and not event.echo:
		_key(event as InputEventKey)


func _update_hover(screen_point: Vector2) -> void:
	var c := Hex.from_world(_screen_to_world(screen_point), HEX)
	if c == map.hover:
		return
	map.hover = c
	map.path_preview.clear()
	var u: Unit = map.selected_unit
	if u != null and not u.dead and u.mv > 0 and Game.world.has(c) \
			and Game.me.seen.has(c) and not map.targets.has(Game.world.at(c)):
		var p := Game.path_to(u, c)
		if not p.is_empty():
			map.path_preview = p.slice(0, mini(24, p.size()))
	ui.set_hover(c)
	map.queue_redraw()


func _click(screen_point: Vector2) -> void:
	if Game.over:
		return
	var c := Hex.from_world(_screen_to_world(screen_point), HEX)
	if not Game.world.has(c) or not Game.me.seen.has(c):
		return
	var t := Game.world.at(c)
	var u: Unit = map.selected_unit

	if u != null and not u.dead and u.owner_id == Game.me.id:
		var own = null
		for o in t.units:
			if o.owner_id == Game.me.id and o != u:
				own = o
				break
		if own != null and not map.targets.has(t) and t.coord != u.coord:
			map.select_unit(own)
			ui.refresh()
			return
		if t.coord == u.coord and t.city != null and t.city.owner_id == Game.me.id:
			map.select_city(t.city)
			ui.refresh()
			return
		map.order_to(u, t)
		ui.refresh()
		if not u.dead and (u.mv <= 0 or u.has_goto):
			await get_tree().create_timer(0.22).timeout
			if map.selected_unit == u:
				map.next_idle_unit(false)
				ui.refresh()
		return

	var mine: Array = []
	for o in t.units:
		if o.owner_id == Game.me.id:
			mine.append(o)
	if not mine.is_empty():
		var i := mine.find(map.selected_unit)
		map.select_unit(mine[(i + 1) % mine.size()])
		ui.refresh()
		return
	if t.city != null and t.city.owner_id == Game.me.id:
		map.select_city(t.city)
		ui.refresh()
		return
	map.clear_selection()
	ui.refresh()


func _key(k: InputEventKey) -> void:
	match k.keycode:
		KEY_ESCAPE:
			if map.selected_unit != null or map.selected_city != null:
				map.clear_selection()
				ui.refresh()
			else:
				ui.show_pause()
		KEY_SPACE:
			map.next_idle_unit(false)
			ui.refresh()
		KEY_ENTER, KEY_KP_ENTER:
			if map.idle_units().is_empty():
				ui.end_turn()
			else:
				map.next_idle_unit(false)
				ui.refresh()
		KEY_F:
			var u: Unit = map.selected_unit
			if u != null and not u.is_civilian():
				u.fortified = maxi(1, u.fortified)
				u.done = true
				map.next_idle_unit(false)
				ui.refresh()
		KEY_S:
			var u2: Unit = map.selected_unit
			if u2 != null:
				u2.asleep = true
				u2.done = true
				map.next_idle_unit(false)
				ui.refresh()
		KEY_C:
			var c = Game.me.capital
			if c == null and not Game.me.cities.is_empty():
				c = Game.me.cities[0]
			if c != null:
				centre_on(c.coord)
				map.select_city(c)
				ui.refresh()
		KEY_EQUAL, KEY_PLUS, KEY_KP_ADD:
			_zoom_at(1.15, get_viewport_rect().size * 0.5)
		KEY_MINUS, KEY_KP_SUBTRACT:
			_zoom_at(1.0 / 1.15, get_viewport_rect().size * 0.5)
		KEY_M:
			var on := Snd.toggle()
			ui.flash_note("Sound " + ("on" if on else "muted"))
		KEY_BRACKETLEFT:
			ui.flash_note("Volume %d%%" % int(Snd.nudge_volume(-0.12) * 100.0))
		KEY_BRACKETRIGHT:
			ui.flash_note("Volume %d%%" % int(Snd.nudge_volume(0.12) * 100.0))


func _on_run_ended(won: bool, how: String) -> void:
	ui.show_game_over(won, how)


## Dev only: stand one of every unit around the capital so the tokens can
## be looked at side by side at real map scale.
func _lay_out_every_unit() -> void:
	var me := Game.me
	for t in Game.world.list:
		for u in t.units.duplicate():
			Game.kill_unit(u, true)
	var cap := me.capital
	var spots: Array[Tile] = []
	for rad in range(1, 5):
		for t2 in Game.world.in_range(cap.coord, rad):
			if Hex.distance(t2.coord, cap.coord) != rad:
				continue
			if t2.city != null or t2.is_water() or t2.is_impassable():
				continue
			spots.append(t2)
	var civs: Array[Player] = []
	for p in Game.players:
		if not p.is_barbarian:
			civs.append(p)
	var i := 0
	for key in Data.UNIT:
		if i >= spots.size():
			break
		var u2 := Game.spawn_unit(civs[i % civs.size()], key, spots[i].coord)
		u2.rank = i % 4
		if i % 3 == 0:
			u2.hp = 58
		i += 1
	for t3 in Game.world.list:
		me.seen[t3.coord] = true
		me.vis[t3.coord] = true


## Dev only: set a real assault in motion so the lunge can be photographed.
func _stage_a_fight() -> void:
	var me := Game.me
	var foe: Player = null
	var target: City = null
	var best := -1
	for p in Game.players:
		if p == me or p.is_barbarian:
			continue
		for c in p.cities:
			var open := 0
			for d in 6:
				var n := Game.world.neighbour(c.coord, d)
				if n != null and n.units.is_empty() and n.city == null 						and not n.is_water() and not n.is_impassable():
					open += 1
			if open > best:
				best = open
				target = c
				foe = p
	if target == null:
		return
	me.relation(foe.id)["war"] = true
	me.relation(foe.id)["met"] = true
	foe.relation(me.id)["war"] = true
	foe.relation(me.id)["met"] = true
	var placed: Array[Unit] = []
	for d2 in 6:
		if placed.size() >= 3:
			break
		var n2 := Game.world.neighbour(target.coord, d2)
		if n2 == null or not n2.units.is_empty() or n2.city != null 				or n2.is_water() or n2.is_impassable():
			continue
		var u := Game.spawn_unit(me, Game.real_unit(me, "knight" if placed.is_empty() else "crossbow"), n2.coord)
		u.xp = 60
		Game._apply_rank(u, false)
		placed.append(u)
	for t in Game.world.list:
		if Hex.distance(t.coord, target.coord) <= 6:
			me.seen[t.coord] = true
			me.vis[t.coord] = true
	target.hp = int(target.max_hp * 0.5)
	centre_on(target.coord)
	if not placed.is_empty():
		map.select_unit(placed[0])
		Game.melee_attack(placed[0], Game.world.at(target.coord))
	ui.refresh()
	map.queue_redraw()


# =========================================================================
#  Balance harness:  --sim N [--diff D] [--seed S]
#
#  Plays N complete runs with every seat on the AI and prints what the shape
#  of a run actually is: how many units are on the board, how long games
#  last, and how they end. Numbers, not impressions.
# =========================================================================
func _run_sim(games: int, base_seed: int, diff: int) -> void:
	var marks := [20, 40, 60, 80, 100]
	var units := {}
	var cities := {}
	var moves := {}          ## units the human seat would have had to move
	for m in marks:
		units[m] = []
		cities[m] = []
		moves[m] = []
	var lengths: Array[int] = []
	var shares: Array[float] = []
	var endings := {}
	var pool := EdictData.LEADERS

	for g in games:
		var s := base_seed + g * 7919
		Game.new_run(s, str(pool[g % pool.size()]["id"]), diff)
		Game.me.is_human = false
		var turn := 0
		while not Game.over and turn < Data.MAX_TURNS:
			Game.run_turn()
			turn = Game.turn
			if turn in marks:
				var alive := 0
				var u := 0
				var c := 0
				for p in Game.players:
					if p.is_barbarian or not p.alive:
						continue
					alive += 1
					u += p.units.size()
					c += p.cities.size()
				if alive > 0:
					units[turn].append(float(u) / float(alive))
					cities[turn].append(float(c) / float(alive))
				moves[turn].append(float(Game.me.units.size()))
		var total := 0
		var top := 0
		for p in Game.players:
			if p.is_barbarian:
				continue
			total += p.cities.size()
			top = maxi(top, p.cities.size())
		if total > 0:
			shares.append(float(top) / float(total))
		lengths.append(turn)
		var how := str(Game.end_how) if Game.end_how != "" else "timeout"
		endings[how] = int(endings.get(how, 0)) + 1

	print("")
	print("=== %d runs, difficulty %d ===" % [games, diff])
	print("turn |  units/empire |  cities/empire |  your units")
	for m in marks:
		if units[m].is_empty():
			continue
		print("%4d |%14.1f |%15.1f |%12.1f  (n=%d)"
			% [m, _mean(units[m]), _mean(cities[m]), _mean(moves[m]), units[m].size()])
	var lf: Array[float] = []
	for l in lengths:
		lf.append(float(l))
	print("best city share at the end: mean %.0f%%  max %.0f%%"
		% [_mean(shares) * 100.0, shares.max() * 100.0])
	print("run length: mean %.1f  min %d  max %d" % [_mean(lf), lengths.min(), lengths.max()])
	var keys := endings.keys()
	keys.sort()
	for k in keys:
		print("  %-14s %d" % [k, endings[k]])


func _mean(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var t := 0.0
	for v in a:
		t += float(v)
	return t / float(a.size())
