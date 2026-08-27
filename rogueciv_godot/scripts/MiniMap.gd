class_name MiniMap
extends Control

## A quiet plan of the world: terrain where you have been, colour where a
## nation holds ground, and a frame showing what is on screen. Click to go.

signal jumped(coord: Vector2i)

var camera: Camera2D
var hex_size := 46.0

var _scale := 1.0
var _origin := Vector2.ZERO


func _ready() -> void:
	clip_contents = true          # the view frame can be larger than the world
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	set_process(true)


func _process(_d: float) -> void:
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		_jump_to((event as InputEventMouseButton).position)
	elif event is InputEventMouseMotion \
			and (event as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT:
		_jump_to((event as InputEventMouseMotion).position)


func _jump_to(at: Vector2) -> void:
	if Game.world == null or _scale <= 0.0:
		return
	var world_point := (at - _origin) / _scale
	jumped.emit(Hex.from_world(world_point, hex_size))


func _draw() -> void:
	if Game.world == null or Game.me == null:
		return
	var me := Game.me
	var span := (Game.world.radius + 1.0) * hex_size
	var box := size - Vector2(10, 10)
	_scale = minf(box.x / (span * Hex.SQ3 * 2.0), box.y / (span * 1.5 * 2.0))
	_origin = size * 0.5

	# one small hexagon per tile, only where you have been
	var r := hex_size * _scale * 0.70
	for t in Game.world.list:
		if not me.seen.has(t.coord):
			continue
		var p := _origin + t.pos * hex_size * _scale
		var col: Color
		if t.owner_id >= 0 and Game.player(t.owner_id) != null:
			col = Game.player(t.owner_id).colour
		elif t.is_water():
			col = Pal.OCEAN if t.terrain == "ocean" else Pal.COAST
		elif t.elev == "mtn":
			col = Pal.MOUNTAIN
		else:
			col = Pal.TERRAIN_COLOUR[t.terrain]
		if not me.vis.has(t.coord):
			col = Pal.desaturate(col, 0.30).lerp(Pal.PANEL, 0.30)
		draw_circle(p, r, col)

	# every city you know of
	for p2 in Game.players:
		if p2.is_barbarian:
			continue
		for c in p2.cities:
			if not me.seen.has(c.coord):
				continue
			var at := _origin + Hex.to_world(c.coord, hex_size) * _scale
			draw_circle(at, maxf(2.2, r * 1.5), Pal.PANEL)
			draw_circle(at, maxf(1.4, r * 1.0), p2.colour)

	# what is on screen
	if camera != null:
		var view := get_viewport_rect().size / camera.zoom * _scale
		var centre := _origin + camera.global_position * _scale
		var frame := Rect2(centre - view * 0.5, view)
		draw_rect(frame, Pal.with_alpha(Pal.INK, 0.55), false, 1.5)
