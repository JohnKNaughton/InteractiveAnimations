extends CanvasLayer

## The interface. Two rules run through all of it:
##  - nothing appears until it is relevant (see Game.unlocked)
##  - at any moment there is exactly one obvious next thing to click

var map: Node2D
var main: Node2D

var root: Control
var top: PanelContainer
var top_row: HBoxContainer
var civ_label: Label
var gold_box: HBoxContainer
var gold_label: Label
var gold_rate: Label
var army_label: Label
var army_box: HBoxContainer
var age_box: VBoxContainer
var age_label: Label
var age_bar: ProgressBar
var age_sub: Label
var buttons_box: HBoxContainer
var btn_nations: Button
var btn_cities: Button
var btn_edicts: Button
var turn_label: Label
var turn_sub: Label
var primary: Button

var hint_panel: PanelContainer
var hint_label: Label

var sel_panel: PanelContainer
var sel_body: VBoxContainer

var strip: HBoxContainer
var chron_box: VBoxContainer

var veil: ColorRect
var modal: PanelContainer
var modal_body: VBoxContainer
var _modal_id := ""

var mini: MiniMap
var mini_panel: PanelContainer
var tip_panel: PanelContainer
var _menu_mode := false
var tip_label: RichTextLabel


# =========================================================================
#  Small toolkit
# =========================================================================
## Every panel is a comic panel: flat fill, heavy black keyline, corners that
## are barely rounded, and no shadow at all. A blurred drop shadow is the one
## thing that would give the whole style away, so there isn't one anywhere.
func _sb(bg: Color, border: Color, radius := 12, width := 3) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(width)
	s.set_corner_radius_all(mini(radius, 4))
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	s.shadow_size = 0
	return s


func _panel(radius := 12) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _sb(Pal.PANEL, Pal.PANEL_EDGE, radius))
	return p


func _label(text: String, size := 14, col := Pal.INK, bold := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", Pal.bold() if bold else Pal.ui())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l


## An autowrapping label that actually reserves the height it needs.
func _wrap_label(text: String, size: int, col: Color, width: int, bold := false) -> Label:
	var l := _label(text, size, col, bold)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var font := Pal.bold() if bold else Pal.ui()
	var h := font.get_multiline_string_size(
		text, HORIZONTAL_ALIGNMENT_LEFT, float(width), size).y
	l.custom_minimum_size = Vector2(width, ceilf(h))
	return l


## Comic lettering: a poster face, set in capitals, with a hard offset shadow.
## Godot's label shadow has no blur, which is exactly what this style wants.
func _title(text: String, size := 26, hero := false) -> Label:
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_font_override("font", Pal.display())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Pal.PAPER if hero else Pal.INK)
	l.add_theme_color_override("font_shadow_color", Pal.RED if hero else Pal.with_alpha(Pal.RED, 0.85))
	l.add_theme_constant_override("shadow_offset_x", 5 if hero else 3)
	l.add_theme_constant_override("shadow_offset_y", 5 if hero else 3)
	if hero:
		l.add_theme_color_override("font_outline_color", Pal.INK)
		l.add_theme_constant_override("outline_size", 10)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


func _button(text: String, on_press: Callable, kind := "plain") -> Button:
	var b := Button.new()
	b.text = text.to_upper()
	b.add_theme_font_override("font", Pal.bold())
	b.add_theme_font_size_override("font_size", 13)
	b.focus_mode = Control.FOCUS_NONE
	var bg := Pal.PANEL
	var fg := Pal.INK
	var edge := Pal.PANEL_EDGE
	match kind:
		"primary":
			bg = Pal.ACCENT
			fg = Pal.PAPER
			edge = Pal.INK
		"danger":
			bg = Pal.PANEL
			fg = Pal.BAD
			edge = Pal.BAD
		"quiet":
			bg = Pal.with_alpha(Pal.INK, 0.0)
			fg = Pal.INK_SOFT
			edge = Pal.with_alpha(Pal.INK, 0.0)
	var normal := _sb(bg, edge, 9)
	if kind == "quiet":
		normal.set_border_width_all(0)
	normal.content_margin_left = 13
	normal.content_margin_right = 13
	normal.content_margin_top = 7
	normal.content_margin_bottom = 7
	normal.shadow_size = 0
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Pal.shade(bg, -0.06) if kind == "primary" else Pal.with_alpha(Pal.ACCENT, 0.14)
	if kind != "primary":
		hover.border_color = Pal.ACCENT
	var pressed := hover.duplicate() as StyleBoxFlat
	pressed.bg_color = Pal.shade(hover.bg_color, -0.08)
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Pal.with_alpha(Pal.INK, 0.04)
	disabled.border_color = Pal.with_alpha(Pal.INK, 0.08)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("disabled", disabled)
	b.add_theme_stylebox_override("focus", normal)
	b.add_theme_color_override("font_color", fg)
	b.add_theme_color_override("font_hover_color", fg if kind == "primary" else Pal.ACCENT)
	b.add_theme_color_override("font_pressed_color", fg)
	b.add_theme_color_override("font_disabled_color", Pal.INK_FAINT)
	if on_press.is_valid():
		b.pressed.connect(on_press)
	return b


func _spacer(w := 0, h := 0) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, h)
	if w == 0:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c


func _rule() -> Control:
	var r := ColorRect.new()
	r.color = Pal.INK
	r.custom_minimum_size = Vector2(0, 3)
	return r


func _row(kids: Array, sep := 8) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	for k in kids:
		h.add_child(k)
	return h


func _col(kids: Array, sep := 6) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	for k in kids:
		v.add_child(k)
	return v


func _dot(col: Color, size := 12) -> Control:
	var c := ColorRect.new()
	c.color = col
	c.custom_minimum_size = Vector2(size, size)
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return c


func _kv(key: String, value: String, value_col := Pal.INK) -> HBoxContainer:
	var h := _row([_label(key, 13, Pal.INK_SOFT), _spacer(), _label(value, 13, value_col, true)])
	return h


func _bar(fraction: float, col: Color, width := 160, height := 6) -> Control:
	var back := ColorRect.new()
	back.color = Pal.with_alpha(Pal.INK, 0.10)
	back.custom_minimum_size = Vector2(width, height)
	var fill := ColorRect.new()
	fill.color = col
	# anchored to the left edge, so offset_right is the fill's width, not an
	# inset from the right: getting this backwards drew every bar empty
	fill.anchor_left = 0.0
	fill.anchor_right = 0.0
	fill.anchor_top = 0.0
	fill.anchor_bottom = 0.0
	fill.offset_left = 0
	fill.offset_top = 0
	fill.offset_right = width * clampf(fraction, 0.0, 1.0)
	fill.offset_bottom = height
	back.add_child(fill)
	return back


# =========================================================================
#  Building the frame
# =========================================================================
func _ready() -> void:
	layer = 10
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_build_top()
	_build_hint()
	_build_selection()
	_build_strip()
	_build_chronicle()
	_build_minimap()
	_build_tip()
	_build_modal()

	Game.state_changed.connect(refresh)
	Game.log_added.connect(func(_t, _k): _refresh_chronicle())
	Game.revealed.connect(func(_f): refresh())
	Game.banner.connect(_show_banner)
	_set_run_ui_visible(false)


## A soft darkening at the corners. Cheap, and it stops the map feeling like
## a spreadsheet that happens to be coloured in.
## Pop art has no soft focus, so there is no vignette. What there is instead
## is a hard black offset behind anything that floats: `_hard_shadow`.
func _hard_shadow(sb: StyleBoxFlat, dist: float) -> StyleBoxFlat:
	sb.shadow_color = Pal.INK
	sb.shadow_size = 2          # 2px, not 0: Godot will not draw a 0-size shadow
	sb.shadow_offset = Vector2(dist, dist)
	return sb


func _build_top() -> void:
	top = _panel(14)
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 14
	top.offset_right = -14
	top.offset_top = 12
	top.offset_bottom = 68
	root.add_child(top)

	top_row = HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 18)
	top.add_child(top_row)

	var civ_dot := _dot(Pal.ACCENT, 14)
	civ_dot.name = "civdot"
	civ_label = _label("—", 16, Pal.INK, true)
	var leader_label := _label("", 12, Pal.INK_SOFT)
	leader_label.name = "leader"
	top_row.add_child(_row([civ_dot, _col([civ_label, leader_label], 0)], 9))

	gold_label = _label("0", 16, Pal.INK, true)
	gold_rate = _label("+0", 12, Pal.INK_SOFT)
	gold_box = _row([_dot(Pal.GOLD, 9), gold_label, gold_rate], 6)
	gold_box.alignment = BoxContainer.ALIGNMENT_CENTER
	top_row.add_child(gold_box)

	# the army ceiling has to be visible, or reaching it just looks like a bug
	army_label = _label("0/0", 16, Pal.INK, true)
	army_box = _row([_dot(Pal.BAD, 9), army_label], 6)
	army_box.alignment = BoxContainer.ALIGNMENT_CENTER
	army_box.tooltip_text = "Soldiers, and the most you may field. " 		+ "Every city you hold raises the limit."
	army_box.mouse_filter = Control.MOUSE_FILTER_STOP
	top_row.add_child(army_box)

	age_label = _label("Dawn", 15, Pal.INK, true)
	age_sub = _label("", 11, Pal.INK_SOFT)
	age_bar = ProgressBar.new()
	age_bar.custom_minimum_size = Vector2(190, 7)
	age_bar.show_percentage = false
	age_bar.max_value = 1.0
	var bg := StyleBoxFlat.new()
	bg.bg_color = Pal.with_alpha(Pal.INK, 0.10)
	bg.set_corner_radius_all(4)
	var fg := StyleBoxFlat.new()
	fg.bg_color = Pal.SCI
	fg.set_corner_radius_all(4)
	age_bar.add_theme_stylebox_override("background", bg)
	age_bar.add_theme_stylebox_override("fill", fg)
	age_box = _col([_row([age_label, age_sub], 8), age_bar], 3)
	top_row.add_child(age_box)

	top_row.add_child(_spacer())

	buttons_box = HBoxContainer.new()
	buttons_box.add_theme_constant_override("separation", 6)
	btn_nations = _button("Nations", show_nations)
	btn_cities = _button("Cities", show_cities)
	btn_edicts = _button("Edicts", show_edicts)
	buttons_box.add_child(btn_nations)
	buttons_box.add_child(btn_cities)
	buttons_box.add_child(btn_edicts)
	buttons_box.add_child(_button("?", show_help, "quiet"))
	top_row.add_child(buttons_box)

	turn_label = _label("1", 16, Pal.INK, true)
	turn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	turn_sub = _label("of 100", 11, Pal.INK_SOFT)
	turn_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top_row.add_child(_col([turn_label, turn_sub], 0))

	primary = _button("End Turn", _on_primary, "primary")
	primary.custom_minimum_size = Vector2(150, 38)
	top_row.add_child(primary)


func _build_hint() -> void:
	hint_panel = _panel(10)
	hint_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	hint_panel.offset_top = 82
	hint_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hint_panel.grow_vertical = Control.GROW_DIRECTION_END
	hint_label = _label("", 14, Pal.INK)
	var close := _button("Got it", _dismiss_hint, "quiet")
	hint_panel.add_child(_row([_dot(Pal.ACCENT, 8), hint_label, _spacer(10), close], 10))
	hint_panel.visible = false
	root.add_child(hint_panel)


func _dismiss_hint() -> void:
	var h := Game.current_hint()
	if not h.is_empty():
		Game.dismiss_hint(h["id"])
	refresh()


func _build_selection() -> void:
	sel_panel = _panel(14)
	sel_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	sel_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	sel_panel.grow_horizontal = Control.GROW_DIRECTION_END
	sel_panel.offset_left = 14
	sel_panel.offset_bottom = -14
	sel_panel.custom_minimum_size = Vector2(272, 0)
	sel_body = VBoxContainer.new()
	sel_body.add_theme_constant_override("separation", 7)
	sel_panel.add_child(sel_body)
	sel_panel.visible = false
	root.add_child(sel_panel)


func _build_strip() -> void:
	var holder := PanelContainer.new()
	holder.name = "striphold"
	holder.add_theme_stylebox_override("panel", _sb(Pal.PANEL, Pal.PANEL_EDGE, 12))
	holder.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	holder.offset_bottom = -14
	holder.grow_horizontal = Control.GROW_DIRECTION_BOTH
	holder.grow_vertical = Control.GROW_DIRECTION_BEGIN
	strip = HBoxContainer.new()
	strip.add_theme_constant_override("separation", 6)
	holder.add_child(strip)
	holder.visible = false
	root.add_child(holder)


func _build_chronicle() -> void:
	var holder := _clickable(12, Pal.ACCENT, show_chronicle)
	holder.name = "chronhold"
	var sb := _sb(Pal.with_alpha(Pal.PANEL, 0.96), Pal.with_alpha(Pal.PANEL_EDGE, 0.9), 12)
	sb.content_margin_top = 9
	sb.content_margin_bottom = 9
	_hard_shadow(sb, 6.0)
	holder.add_theme_stylebox_override("panel", sb)
	holder.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	holder.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	holder.grow_vertical = Control.GROW_DIRECTION_BEGIN
	holder.offset_right = -14
	holder.offset_bottom = -14
	holder.custom_minimum_size = Vector2(300, 0)
	holder.tooltip_text = "The whole chronicle"
	chron_box = VBoxContainer.new()
	chron_box.add_theme_constant_override("separation", 3)
	chron_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(chron_box)
	root.add_child(holder)


func show_chronicle() -> void:
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 2)
	var last_turn := -1
	for e in Game.chronicle:
		if int(e["turn"]) != last_turn:
			last_turn = int(e["turn"])
			inner.add_child(_spacer(0, 5))
			inner.add_child(_label("TURN %d" % last_turn, 10, Pal.INK_FAINT, true))
		var col := Pal.INK
		match str(e["kind"]):
			"war": col = Pal.BAD
			"good": col = Pal.GOOD
			"big": col = Pal.ACCENT
		inner.add_child(_wrap_label(str(e["text"]), 13, col, 520, str(e["kind"]) == "big"))
	if Game.chronicle.is_empty():
		inner.add_child(_label("Nothing has happened yet.", 13, Pal.INK_SOFT))
	open_modal("chronicle", "The Chronicle", "Everything that has happened in this run.",
		[_scroll(inner)], [_button("Close", close_modal, "quiet")])


func _build_minimap() -> void:
	mini_panel = _panel(12)
	var sb := _sb(Pal.PANEL, Pal.PANEL_EDGE, 12)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	mini_panel.add_theme_stylebox_override("panel", sb)
	mini_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	mini_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	mini_panel.grow_vertical = Control.GROW_DIRECTION_END
	mini_panel.offset_right = -14
	mini_panel.offset_top = 80
	mini = MiniMap.new()
	mini.custom_minimum_size = Vector2(196, 132)
	mini_panel.add_child(mini)
	mini_panel.visible = false
	root.add_child(mini_panel)


func _build_tip() -> void:
	tip_panel = _panel(10)
	tip_panel.custom_minimum_size = Vector2(210, 0)
	tip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip_label = RichTextLabel.new()
	tip_label.bbcode_enabled = true
	tip_label.fit_content = true
	tip_label.custom_minimum_size = Vector2(196, 0)
	tip_label.add_theme_font_override("normal_font", Pal.ui())
	tip_label.add_theme_font_override("bold_font", Pal.bold())
	tip_label.add_theme_font_size_override("normal_font_size", 13)
	tip_label.add_theme_font_size_override("bold_font_size", 13)
	tip_label.add_theme_color_override("default_color", Pal.INK)
	tip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip_panel.add_child(tip_label)
	tip_panel.visible = false
	root.add_child(tip_panel)


func _build_modal() -> void:
	veil = ColorRect.new()
	veil.color = Color(0.09, 0.07, 0.13, 0.42)
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	veil.visible = false
	root.add_child(veil)

	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	veil.add_child(centre)

	modal = _panel(16)
	var sb := _sb(Pal.PANEL, Pal.PANEL_EDGE, 16)
	sb.content_margin_left = 26
	sb.content_margin_right = 26
	sb.content_margin_top = 22
	sb.content_margin_bottom = 20
	sb.set_border_width_all(5)
	_hard_shadow(sb, 11.0)
	modal.add_theme_stylebox_override("panel", sb)
	modal_body = VBoxContainer.new()
	modal_body.add_theme_constant_override("separation", 10)
	modal.add_child(modal_body)
	centre.add_child(modal)


# =========================================================================
#  Visibility of the whole run interface
# =========================================================================
## The title screen runs a real world behind it. Everything that belongs to
## a run — the strip, the chronicle, toasts — must stay out of the way.
func enter_menu_mode() -> void:
	_menu_mode = true
	_set_run_ui_visible(false)
	for n in get_tree().get_nodes_in_group("rc_note"):
		n.queue_free()
	for n in get_tree().get_nodes_in_group("rc_banner"):
		n.queue_free()
	tip_panel.visible = false


func _set_run_ui_visible(v: bool) -> void:
	top.visible = v
	mini_panel.visible = v
	root.get_node("striphold").visible = v and Game.me != null and not Game.me.cities.is_empty()
	root.get_node("chronhold").visible = v
	if not v:
		sel_panel.visible = false
		hint_panel.visible = false


func begin_run_ui() -> void:
	_menu_mode = false
	_set_run_ui_visible(true)
	refresh()
	_refresh_chronicle()


func modal_open() -> bool:
	return veil.visible


## Escape closes anything that is not a decision the run is waiting on.
func escape_modal() -> void:
	if _modal_id in ["draft", "promotion", "start", "over", "tribute", "peace"]:
		return
	close_modal()


# =========================================================================
#  Refresh
# =========================================================================
func refresh() -> void:
	if Game.me == null or _menu_mode:
		return
	var p := Game.me
	root.get_node("striphold").visible = not p.cities.is_empty()

	(top_row.get_child(0).get_child(0) as ColorRect).color = p.colour
	civ_label.text = p.name
	(top_row.get_child(0).get_child(1).get_child(1) as Label).text = \
		str(p.leader.get("name", "")) + " · " + str(p.leader.get("trait", ""))

	var rates := Game.empire_rates(p)
	var army := Game.army_size(p)
	var cap := Game.army_cap(p)
	army_label.text = "%d/%d" % [army, cap]
	army_label.add_theme_color_override("font_color",
		Pal.BAD if army >= cap else Pal.INK)
	(army_box.get_child(0) as Control).modulate = 		Color.WHITE if army >= cap else Color(1, 1, 1, 0.45)

	gold_label.text = str(p.gold)
	gold_rate.text = ("+" if int(rates["gold"]) >= 0 else "") + str(rates["gold"])
	gold_rate.add_theme_color_override("font_color",
		Pal.GOOD if int(rates["gold"]) > 0 else (Pal.BAD if int(rates["gold"]) < 0 else Pal.INK_SOFT))

	# the age track only exists once there has been something to research
	age_box.visible = Game.is_unlocked("edicts") or p.sci > 0
	var need := Data.bt_cost(p.bt_done)
	age_bar.value = clampf(float(p.sci) / float(need), 0.0, 1.0)
	age_label.text = Data.AGES[p.age]["name"]
	if p.bt_done >= Data.BT_PER_AGE * Data.AGES.size():
		age_sub.text = "every edict taken"
	else:
		age_sub.text = "%d edicts · +%d" % [p.edicts.size(), int(rates["sci"])]

	btn_nations.visible = Game.is_unlocked("diplomacy")
	btn_cities.visible = p.cities.size() > 1
	btn_edicts.visible = not p.edicts.is_empty()

	turn_label.text = str(Game.turn)
	turn_sub.text = "of %d" % Data.MAX_TURNS

	var idle: int = map.idle_units().size() if map != null else 0
	if Game.pending_drafts > 0:
		primary.text = "Choose an Edict"
	elif not Game.pending_event.is_empty():
		primary.text = "Decide"
	elif not Game.pending_promotions.is_empty():
		primary.text = "Promote"
	elif idle > 0:
		primary.text = "Next Unit (%d)" % idle
	else:
		primary.text = "End Turn"

	_refresh_hint()
	_refresh_selection()
	_refresh_strip()


func _refresh_hint() -> void:
	var h := Game.current_hint()
	if h.is_empty() or modal_open():
		hint_panel.visible = false
		return
	hint_label.text = str(h["text"])
	hint_panel.visible = true


func _on_primary() -> void:
	if Game.pending_drafts > 0:
		show_draft()
		return
	if not Game.pending_event.is_empty():
		show_event()
		return
	if not Game.pending_promotions.is_empty():
		show_promotion()
		return
	if map.idle_units().is_empty():
		end_turn()
	else:
		map.next_idle_unit(false)
		refresh()


func end_turn() -> void:
	if Game.over or Game.busy:
		return
	Game.busy = true
	Snd.play("turn")
	Game.run_turn()
	Game.busy = false
	if not Game.over:
		map.next_idle_unit(true)
		_check_pending()
	refresh()
	map.queue_redraw()


func _check_pending() -> void:
	if Game.pending_tribute_demand != null:
		var who := Game.pending_tribute_demand
		Game.pending_tribute_demand = null
		show_tribute_demand(who)
		return
	if Game.pending_peace_offer != null:
		var who2 := Game.pending_peace_offer
		Game.pending_peace_offer = null
		show_peace_offer(who2)
		return
	if Game.pending_drafts > 0:
		show_draft()
		return
	if not Game.pending_event.is_empty():
		show_event()
		return
	if not Game.pending_promotions.is_empty():
		show_promotion()


func _show_banner(title: String, subtitle: String) -> void:
	if _menu_mode:
		return
	if modal_open():
		return                      # never drop a banner on top of a choice
	var b := _panel(12)
	var sb := _sb(Pal.PANEL, Pal.ACCENT, 12, 2)
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14
	sb.content_margin_left = 30
	sb.content_margin_right = 30
	b.add_theme_stylebox_override("panel", sb)
	var t := _title(title, 24)
	var s := _label(subtitle, 13, Pal.INK_SOFT)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.add_child(_col([t, s], 2))
	b.set_anchors_preset(Control.PRESET_CENTER_TOP)
	b.offset_top = 150
	b.grow_horizontal = Control.GROW_DIRECTION_BOTH
	b.grow_vertical = Control.GROW_DIRECTION_END
	b.modulate.a = 0.0
	b.add_to_group("rc_banner")
	root.add_child(b)
	var tw := create_tween()
	tw.tween_property(b, "modulate:a", 1.0, 0.25)
	tw.tween_interval(2.1)
	tw.tween_property(b, "modulate:a", 0.0, 0.45)
	tw.tween_callback(b.queue_free)


## A brief line in the middle of the screen: used for sound, and nothing that
## the chronicle should be recording.
func flash_note(text: String) -> void:
	if _menu_mode:
		return
	for n in get_tree().get_nodes_in_group("rc_note"):
		n.queue_free()
	var p := _panel(10)
	var sb := _sb(Pal.PANEL, Pal.PANEL_EDGE, 10)
	sb.content_margin_left = 20
	sb.content_margin_right = 20
	p.add_theme_stylebox_override("panel", sb)
	p.add_child(_label(text, 14, Pal.INK, true))
	p.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BEGIN
	p.offset_bottom = -104
	p.add_to_group("rc_note")
	root.add_child(p)
	var tw := create_tween()
	tw.tween_property(p, "modulate:a", 1.0, 0.10)
	tw.tween_interval(1.0)
	tw.tween_property(p, "modulate:a", 0.0, 0.35)
	tw.tween_callback(p.queue_free)


func set_hover(c: Vector2i) -> void:
	if Game.world == null or not Game.world.has(c) or not Game.me.seen.has(c) or modal_open():
		tip_panel.visible = false
		return
	tip_label.text = _tile_tip(Game.world.at(c))
	tip_panel.visible = true
	await get_tree().process_frame
	var mp := root.get_global_mouse_position()
	var size := tip_panel.size
	var vp := root.size
	tip_panel.position = Vector2(
		clampf(mp.x + 18.0, 8.0, vp.x - size.x - 8.0),
		clampf(mp.y + 18.0, 80.0, vp.y - size.y - 8.0))


# =========================================================================
#  The one panel that changes: whatever is selected
# =========================================================================
func _clear(node: Node) -> void:
	for c in node.get_children():
		c.queue_free()
		node.remove_child(c)


func _refresh_selection() -> void:
	_clear(sel_body)
	var u: Unit = map.selected_unit
	var c: City = map.selected_city
	if u != null and not u.dead:
		_fill_unit_panel(u)
		sel_panel.visible = true
	elif c != null and Game.me.cities.has(c):
		_fill_city_panel(c)
		sel_panel.visible = true
	else:
		sel_panel.visible = false


func _fill_unit_panel(u: Unit) -> void:
	var d: Dictionary = Data.UNIT[u.type]
	var t := Game.world.at(u.coord)
	sel_body.add_child(_label(u.title(), 17, Pal.INK, true))
	sel_body.add_child(_label(("At sea · " if u.embarked else "") + t.display_name(), 12, Pal.INK_SOFT))
	sel_body.add_child(_bar(float(u.hp) / Data.HP_MAX,
		Pal.GOOD if u.hp > 55 else (Pal.WARN if u.hp > 28 else Pal.BAD), 244, 7))

	if not u.is_civilian():
		sel_body.add_child(_kv("Strength", str(int(round(Game.unit_strength(u, {})))) ))
		if Game.unit_range(u) > 0:
			sel_body.add_child(_kv("Ranged",
				"%d  ·  range %d" % [int(round(Game.unit_strength(u, {"ranged": true}))), Game.unit_range(u)]))
	sel_body.add_child(_kv("Movement", "%d / %d" % [u.mv, Game.unit_moves(u)]))
	if not u.is_civilian():
		var nxt := "—"
		if u.rank < 3:
			nxt = "%d / %d" % [u.xp, Data.RANK_XP[u.rank]]
		sel_body.add_child(_kv("Experience", nxt))
	if not u.promos.is_empty():
		var names: Array[String] = []
		for pr in u.promos:
			names.append(Data.PROMOTION[pr]["name"])
		sel_body.add_child(_rule())
		sel_body.add_child(_label(", ".join(names), 12, Pal.ACCENT, true))
	if d.has("desc"):
		sel_body.add_child(_wrap_label(str(d["desc"]), 12, Pal.INK_SOFT, 244))

	sel_body.add_child(_spacer(0, 2))
	var acts := HBoxContainer.new()
	acts.add_theme_constant_override("separation", 5)
	var acts2 := HBoxContainer.new()
	acts2.add_theme_constant_override("separation", 5)

	if u.is_civilian():
		var can := Game.can_found_here(Game.me, t)
		var b := _button("Found City", func(): _do_found(u), "primary")
		b.disabled = not can
		if not can:
			b.tooltip_text = "Too close to another city, or unsuitable ground."
		acts.add_child(b)
	else:
		acts.add_child(_button("Fortify" if u.fortified == 0 else "Fortified", func():
			u.fortified = maxi(1, u.fortified)
			u.done = true
			map.next_idle_unit(false)
			refresh()))
	var up := Game.upgrade_for(Game.me, u)
	if up != "":
		var cost := Game.upgrade_cost(Game.me, u, up)
		var ub := _button("→ %s  %dg" % [Data.UNIT[up]["name"], cost], func(): _do_upgrade(u, up))
		ub.disabled = Game.me.gold < cost
		acts.add_child(ub)
	acts2.add_child(_button("Sleep", func():
		u.asleep = true
		u.done = true
		map.next_idle_unit(false)
		refresh(), "quiet"))
	acts2.add_child(_button("Skip", func():
		u.done = true
		map.next_idle_unit(false)
		refresh(), "quiet"))
	acts2.add_child(_button("Disband", func(): _confirm_disband(u), "danger"))
	sel_body.add_child(acts)
	sel_body.add_child(acts2)


func _confirm_disband(u: Unit) -> void:
	open_modal("confirm", "Disband this %s?" % Data.UNIT[u.type]["name"],
		"It will be gone for good.", [],
		[_button("Disband", func():
			Game.kill_unit(u, true)
			map.clear_selection()
			close_modal()
			map.queue_redraw(), "danger"),
		 _button("Keep it", close_modal, "primary")])


func _do_found(u: Unit) -> void:
	var t := Game.world.at(u.coord)
	if not Game.can_found_here(Game.me, t):
		return
	var c := Game.found_city(Game.me, t, Game.me.cities.is_empty())
	Game.kill_unit(u, true)
	Game.log_line("You found %s." % c.name, "big")
	Game.dismiss_hint("settle")
	Game.world.recompute_vision(Game.me)
	map.select_city(c)
	refresh()
	map.queue_redraw()


func _do_upgrade(u: Unit, to: String) -> void:
	var cost := Game.upgrade_cost(Game.me, u, to)
	if Game.me.gold < cost:
		return
	Game.me.gold -= cost
	u.type = to
	u.hp = mini(Data.HP_MAX, u.hp + 20)
	u.mv = 0
	u.done = true
	Snd.play("build")
	Game.log_line("A unit becomes a %s." % Data.UNIT[to]["name"], "good")
	refresh()
	map.queue_redraw()


func _fill_city_panel(c: City) -> void:
	var y := Game.city_yield(c)
	sel_body.add_child(_label(("★ " if c.is_capital else "") + c.name, 17, Pal.INK, true))
	sel_body.add_child(_label("Size %d · %s" % [c.pop,
		"coastal" if Game.world.is_coastal(c.coord) else "inland"], 12, Pal.INK_SOFT))

	var grow := "—"
	if y.x > 0:
		grow = "grows in %d" % maxi(1, int(ceil(float(Data.food_needed(c.pop) - c.food) / float(y.x))))
	elif y.x < 0:
		grow = "starving"
	sel_body.add_child(_kv("Food", "%s%d   %s" % ["+" if y.x >= 0 else "", y.x, grow],
		Pal.BAD if y.x < 0 else Pal.FOOD))
	sel_body.add_child(_kv("Production", str(y.y), Pal.PROD))
	sel_body.add_child(_kv("Gold", "+" + str(y.z), Pal.GOLD))
	sel_body.add_child(_kv("Progress", "+" + str(y.w), Pal.SCI))
	sel_body.add_child(_rule())

	if c.queue.is_empty():
		sel_body.add_child(_label("Nothing being built", 13, Pal.WARN, true))
	else:
		var need := Game.item_cost(Game.me, c.queue)
		var turns := maxi(1, int(ceil(float(need - c.prod) / float(maxi(1, y.y)))))
		sel_body.add_child(_row([
			_label(c.queue_name(), 14, Pal.INK, true), _spacer(),
			_label("%d turns" % turns, 12, Pal.INK_SOFT)]))
		sel_body.add_child(_bar(float(c.prod) / float(maxi(1, need)), Pal.PROD, 244, 6))
	if c.hp < c.max_hp:
		sel_body.add_child(_kv("Defences", "%d / %d" % [c.hp, c.max_hp], Pal.BAD))

	sel_body.add_child(_spacer(0, 2))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	row.add_child(_button("Choose Build", func(): show_build_menu(c), "primary"))
	if not c.queue.is_empty():
		var cost := Game.buy_cost(c)
		var bb := _button("Buy  %dg" % cost, func():
			if Game.me.gold >= cost:
				Game.me.gold -= cost
				c.prod = Game.item_cost(Game.me, c.queue)
				Snd.play("build")
				refresh())
		bb.disabled = Game.me.gold < cost
		row.add_child(bb)
	sel_body.add_child(row)

	var focus_row := HBoxContainer.new()
	focus_row.add_theme_constant_override("separation", 4)
	for pair in [["balanced", "Balanced"], ["growth", "Food"], ["work", "Work"], ["trade", "Trade"]]:
		var key: String = pair[0]
		var b := _button(pair[1], func():
			c.focus = key
			Game.assign_tiles(c)
			refresh()
			map.queue_redraw(), "primary" if c.focus == key else "quiet")
		focus_row.add_child(b)
	sel_body.add_child(focus_row)


func _refresh_strip() -> void:
	_clear(strip)
	# a wide empire would otherwise push the strip into the chronicle
	var tile_w := 132 if Game.me.cities.size() <= 5 else 104
	for c in Game.me.cities:
		var y := Game.city_yield(c)
		var sub := "idle"
		if not c.queue.is_empty():
			var need := Game.item_cost(Game.me, c.queue)
			sub = "%s · %dt" % [c.queue_name(),
				maxi(1, int(ceil(float(need - c.prod) / float(maxi(1, y.y)))))]
		var p := _clickable(9, Pal.ACCENT, func():
			map.select_city(c)
			main.centre_on(c.coord)
			refresh(), map.selected_city == c)
		var sb := p.get_theme_stylebox("panel") as StyleBoxFlat
		sb.content_margin_top = 7
		sb.content_margin_bottom = 7
		sb.content_margin_left = 11
		sb.content_margin_right = 11
		sb.shadow_size = 0
		p.custom_minimum_size = Vector2(tile_w, 0)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 1)
		var name_label := _label(("★ " if c.is_capital else "") + c.name, 13, Pal.INK, true)
		# clip rather than wrap, but it must still claim the row's slack or a
		# zero-minimum clipped label collapses to nothing
		name_label.clip_text = true
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_child(_row([name_label, _label(str(c.pop), 12, Pal.INK_SOFT)], 6))
		var sub_label := _label(sub, 11, Pal.WARN if c.queue.is_empty() else Pal.INK_SOFT)
		sub_label.clip_text = true
		v.add_child(sub_label)
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for kid in v.get_children():
			(kid as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_child(v)
		strip.add_child(p)


func _refresh_chronicle() -> void:
	_clear(chron_box)
	var holder := root.get_node("chronhold") as Control
	holder.visible = not Game.chronicle.is_empty() and Game.me != null
	var start := maxi(0, Game.chronicle.size() - 5)
	var shown := Game.chronicle.size() - start
	for i in range(start, Game.chronicle.size()):
		var e: Dictionary = Game.chronicle[i]
		var col := Pal.INK_SOFT
		match str(e["kind"]):
			"war": col = Pal.BAD
			"good": col = Pal.GOOD
			"big": col = Pal.ACCENT
		var l := _label(str(e["text"]), 12, col, str(e["kind"]) == "big")
		l.clip_text = true
		l.custom_minimum_size = Vector2(276, 0)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# the oldest line is faintest, so the eye lands on what just happened
		l.modulate.a = lerpf(0.42, 1.0, float(i - start + 1) / float(maxi(1, shown)))
		chron_box.add_child(l)


func _tile_tip(t: Tile) -> String:
	var me := Game.me
	var s := "[b]%s[/b]\n" % t.display_name()
	var y := Game.world.tile_yield(t, me)
	var bits: Array[String] = []
	if y.x > 0: bits.append("%d food" % y.x)
	if y.y > 0: bits.append("%d prod" % y.y)
	if y.z > 0: bits.append("%d gold" % y.z)
	s += ("  ·  ".join(bits) if not bits.is_empty() else "no yield")
	if t.defence_bonus() > 0.0:
		s += "  ·  +%d%% defence" % int(t.defence_bonus() * 100)
	if t.resource != "" and Game.world.resource_visible(t, me):
		s += "\n[b]%s[/b]" % Data.RESOURCE[t.resource]["name"]
	elif t.resource != "" and Data.RESOURCE[t.resource]["kind"] == "s":
		s += "\nSomething here your age cannot yet use."
	if t.ruin:
		s += "\nAncient ruins — send a unit"
	if t.camp:
		s += "\nA raider camp"
	if t.city != null:
		var p := Game.player(t.city.owner_id)
		s += "\n\n[b]%s[/b]\n%s · size %d · defence %d/%d" % [
			t.city.name, p.name, t.city.pop, t.city.hp, t.city.max_hp]
	if me.vis.has(t.coord):
		for u in t.units:
			var p2 := Game.player(u.owner_id)
			s += "\n\n[b]%s[/b]\n%s · %d hp" % [u.title(), p2.name, u.hp]
			var sel: Unit = map.selected_unit
			if sel != null and sel.owner_id == me.id and Game.at_war(me, p2) and not u.is_civilian():
				var r := Game.unit_range(sel)
				var dist := Hex.distance(sel.coord, t.coord)
				var ranged := r > 0 and dist <= r and dist > 1
				var atk := Game.unit_strength(sel, {"attacking": true, "ranged": ranged,
					"foe": u, "tile": Game.world.at(sel.coord), "vs_city": t.city != null})
				var odds := Game.combat_odds(atk, Game.defence_at(t, sel))
				s += "\nYour odds: [b]%d%%[/b]" % odds
	return s


# =========================================================================
#  Modals
# =========================================================================
func open_modal(id: String, title: String, subtitle: String,
		body: Array, footer: Array, dismissable := true) -> void:
	_modal_id = id
	_clear(modal_body)
	if title != "":
		modal_body.add_child(_title(title, 44 if id == "start" else 26, id == "start"))
	if subtitle != "":
		var s := _wrap_label(subtitle, 13, Pal.INK_SOFT, 560)
		s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		modal_body.add_child(s)
	modal_body.add_child(_spacer(0, 6))
	for b in body:
		modal_body.add_child(b)
	if not footer.is_empty():
		modal_body.add_child(_spacer(0, 6))
		var f := HBoxContainer.new()
		f.add_theme_constant_override("separation", 8)
		f.alignment = BoxContainer.ALIGNMENT_CENTER
		for b2 in footer:
			f.add_child(b2)
		modal_body.add_child(f)
	# a banner still fading in from the turn that just resolved must not
	# land on top of the choice being asked for
	for b in get_tree().get_nodes_in_group("rc_banner"):
		b.queue_free()
	# before a run there is no map to dim, so the wash goes almost to nothing
	veil.color = Color(0.09, 0.07, 0.13, 0.30 if id == "start" else 0.42)
	modal.modulate.a = 0.0
	modal.scale = Vector2(0.98, 0.98)
	veil.visible = true
	hint_panel.visible = false
	tip_panel.visible = false
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(modal, "modulate:a", 1.0, 0.14)
	tw.tween_property(modal, "scale", Vector2.ONE, 0.14).set_trans(Tween.TRANS_QUAD)


func close_modal() -> void:
	veil.visible = false
	_modal_id = ""
	refresh()
	if map != null:
		map.queue_redraw()


func _scroll(inner: Control, max_h := 460) -> ScrollContainer:
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(0, mini(max_h, 460))
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.add_child(inner)
	return sc


## A panel that behaves like a button. A Button does not size itself to its
## children, so cards built out of Buttons collapsed and overlapped whatever
## came after them.
func _clickable(radius: int, accent: Color, on_click: Callable,
		selected := false) -> PanelContainer:
	var p := PanelContainer.new()
	var normal := _sb(Pal.with_alpha(accent, 0.07) if selected else Pal.PANEL,
		accent if selected else Pal.PANEL_EDGE, radius)
	normal.content_margin_left = 16
	normal.content_margin_right = 16
	normal.content_margin_top = 14
	normal.content_margin_bottom = 14
	_hard_shadow(normal, 5.0)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.border_color = accent
	hover.set_border_width_all(2)
	hover.bg_color = Pal.with_alpha(accent, 0.08)
	_hard_shadow(hover, 8.0)
	p.add_theme_stylebox_override("panel", normal)
	if on_click.is_valid():
		p.mouse_filter = Control.MOUSE_FILTER_STOP
		p.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		p.mouse_entered.connect(func(): p.add_theme_stylebox_override("panel", hover))
		p.mouse_exited.connect(func(): p.add_theme_stylebox_override("panel", normal))
		p.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton and ev.pressed \
					and ev.button_index == MOUSE_BUTTON_LEFT:
				on_click.call())
	else:
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


## A pickable card: the shape used by every choice in the game.
## Cards carry a red stamp above the name: kickers are cover lines, not
## footnotes, so they are set in the accent rather than in grey.
func _card(title: String, kicker: String, body: String, flavour: String,
		on_pick: Callable, accent := Pal.ACCENT, width := 236) -> Control:
	var p := _clickable(13, accent, on_pick)
	p.custom_minimum_size = Vector2(width, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 5)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var line := ColorRect.new()
	line.color = accent
	line.custom_minimum_size = Vector2(30, 3)
	v.add_child(line)
	v.add_child(_spacer(0, 3))
	if kicker != "":
		v.add_child(_label(kicker.to_upper(), 11, Pal.ACCENT_DEEP, true))
	var wrap := width - 34
	v.add_child(_wrap_label(title, 17, Pal.INK, wrap, true))
	v.add_child(_wrap_label(body, 13, Pal.INK, wrap))
	if flavour != "":
		v.add_child(_spacer(0, 4))
		v.add_child(_wrap_label(flavour, 12, Pal.INK_FAINT, wrap))
	for kid in v.get_children():
		(kid as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(v)
	return p


func _list_row(title: String, sub: String, right_top: String, right_bottom: String,
		on_pick: Callable, selected := false, width := 560) -> Control:
	var p := _clickable(9, Pal.ACCENT, on_pick, selected)
	var sb := p.get_theme_stylebox("panel") as StyleBoxFlat
	sb.content_margin_top = 9
	sb.content_margin_bottom = 9
	sb.shadow_size = 0
	p.custom_minimum_size = Vector2(width, 0)

	var left := _col([
		_wrap_label(title, 14, Pal.INK, width - 190, true),
		_wrap_label(sub, 12, Pal.INK_SOFT, width - 190)], 1)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var right := _col([
		_label(right_top, 14, Pal.INK, true),
		_label(right_bottom, 11, Pal.INK_SOFT)], 1)
	(right.get_child(0) as Label).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	(right.get_child(1) as Label).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var h := _row([left, right], 12)
	for node in [h, left, right]:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for kid in left.get_children() + right.get_children():
		(kid as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(h)
	return p


# -------------------------------------------------------------- start ----
func show_start_screen() -> void:
	var seed_value := int(Time.get_unix_time_from_system() * 1000.0) % 1000000007
	var r := Rng.new(seed_value)
	var pool: Array = EdictData.LEADERS.duplicate()
	r.shuffle(pool)
	var offered := pool.slice(0, 3)
	var chosen_diff := [1]

	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 14)
	cards.alignment = BoxContainer.ALIGNMENT_CENTER
	for L in offered:
		var col: Color = Pal.CIV_COLOURS[L["colour"]]
		var uq: Dictionary = Data.UNIT[L["unique"]]
		cards.add_child(_card(
			str(L["name"]), str(L["civ"]),
			str(L["trait"]) + " — " + str(L["trait_desc"]),
			str(uq["name"]) + ": " + str(uq.get("desc", "")),
			func(): _begin(seed_value, str(L["id"]), chosen_diff[0]), col, 244))

	var diff_row := HBoxContainer.new()
	diff_row.add_theme_constant_override("separation", 6)
	diff_row.alignment = BoxContainer.ALIGNMENT_CENTER
	var diff_desc := _label(EdictData.DIFFICULTIES[1]["desc"], 12, Pal.INK_SOFT)
	diff_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var rebuild := func():
		for i in diff_row.get_child_count():
			var btn := diff_row.get_child(i) as Button
			var is_sel: bool = i == chosen_diff[0]
			btn.add_theme_color_override("font_color", Color.WHITE if is_sel else Pal.INK)
			var sb := _sb(Pal.ACCENT if is_sel else Pal.PANEL, Pal.ACCENT if is_sel else Pal.PANEL_EDGE, 9)
			sb.content_margin_top = 7
			sb.content_margin_bottom = 7
			sb.shadow_size = 0
			btn.add_theme_stylebox_override("normal", sb)
			btn.add_theme_stylebox_override("hover", sb)
			btn.add_theme_stylebox_override("pressed", sb)
		diff_desc.text = str(EdictData.DIFFICULTIES[chosen_diff[0]]["desc"])
	for i in EdictData.DIFFICULTIES.size():
		var idx := i
		var b := _button(str(EdictData.DIFFICULTIES[i]["name"]), func():
			chosen_diff[0] = idx
			rebuild.call())
		diff_row.add_child(b)
	rebuild.call()

	var top_row := VBoxContainer.new()
	top_row.add_theme_constant_override("separation", 6)
	if Save.exists():
		var resume := _button("Continue  ·  " + Save.describe(), func():
			close_modal()
			main.resume_run(), "primary")
		resume.custom_minimum_size = Vector2(420, 42)
		top_row.add_child(_centre(resume))
		top_row.add_child(_centre(_label("or begin again", 12, Pal.INK_FAINT)))
		top_row.add_child(_spacer(0, 4))

	var best := _best_score()
	open_modal("start", "RogueCiv",
		"A whole civilisation in one sitting: 100 turns, 6 Ages, 18 Edicts — and only one of every three offered to you."
		+ ("\nBest run so far: %d" % best if best > 0 else ""),
		[top_row, cards, _spacer(0, 10),
		 _centre(_label("CHOOSE A WORLD", 10, Pal.INK_FAINT, true)),
		 diff_row, diff_desc],
		[_button("How to play", show_help, "quiet")], false)


func _centre(c: Control) -> Control:
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_child(c)
	return h


func _begin(seed_value: int, leader: String, difficulty: int) -> void:
	close_modal()
	main.start_run(seed_value, leader, difficulty)


func _best_score() -> int:
	var cfg := ConfigFile.new()
	if cfg.load("user://rogueciv.cfg") != OK:
		return 0
	return int(cfg.get_value("run", "best", 0))


func _save_best(score: int) -> void:
	if Save.is_dev():
		return                      # a test run must not enter the record book
	var cfg := ConfigFile.new()
	cfg.load("user://rogueciv.cfg")
	if score > int(cfg.get_value("run", "best", 0)):
		cfg.set_value("run", "best", score)
		cfg.save("user://rogueciv.cfg")


# -------------------------------------------------------------- pause ----
func show_pause() -> void:
	if Game.me == null or Game.over:
		return
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 7)
	var wide := func(b: Button) -> Button:
		b.custom_minimum_size = Vector2(300, 40)
		return b
	rows.add_child(wide.call(_button("Resume", close_modal, "primary")))
	rows.add_child(wide.call(_button("Restart this run", func():
		close_modal()
		main.start_run(Game.seed_value, Game.leader_id, Game.difficulty))))
	rows.add_child(wide.call(_button("New run", func():
		close_modal()
		show_start_screen())))
	rows.add_child(wide.call(_button("How to play", show_help)))
	rows.add_child(wide.call(_button("Save and quit", func():
		Game.autosave()
		get_tree().quit(), "danger")))
	var note := _label("Your run is saved after every turn, so you can close the "
		+ "window at any time and pick it up again.", 12, Pal.INK_SOFT)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	open_modal("pause", "Paused",
		"%s · %s Age · turn %d of %d" % [Game.me.name,
			Data.AGES[Game.me.age]["name"], Game.turn, Data.MAX_TURNS],
		[_centre(rows), _spacer(0, 4), _centre(_wrap_label(note.text, 12, Pal.INK_SOFT, 360))],
		[])


# -------------------------------------------------------------- draft ----
func show_draft() -> void:
	var options := Game.draft_pool(Game.me)
	if options.is_empty():
		Game.pending_drafts = 0
		return
	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 14)
	cards.alignment = BoxContainer.ALIGNMENT_CENTER
	for e in options:
		cards.add_child(_card(str(e["name"]), Data.AGES[Game.me.age]["name"] + " edict",
			str(e["desc"]), str(e["flavour"]),
			func():
				Game.take_edict(Game.me, e)
				Game.pending_drafts -= 1
				close_modal()
				await get_tree().create_timer(0.12).timeout
				_check_pending()))
	open_modal("draft", "A Breakthrough",
		"Choose one. The other two are gone for the rest of this run.\n%s Age · edict %d of 18"
			% [Data.AGES[Game.me.age]["name"], Game.me.edicts.size() + 1],
		[cards], [], false)


# -------------------------------------------------------------- event ----
func show_event() -> void:
	var e := Game.pending_event
	if e.is_empty():
		return
	Snd.play("draft")
	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 13)
	cards.alignment = BoxContainer.ALIGNMENT_CENTER
	for opt in e["options"]:
		var o: Dictionary = opt
		cards.add_child(_card(str(o["label"]), "", str(o["desc"]), "",
			func():
				Game.take_event_option(Game.me, o)
				Game.log_line("%s — %s" % [e["title"], o["label"]], "big")
				close_modal()
				await get_tree().create_timer(0.12).timeout
				_check_pending(), Pal.TEAL, 224))
	open_modal("event", str(e["title"]), str(e["text"]), [cards], [], false)


# ---------------------------------------------------------- promotion ----
func show_promotion() -> void:
	while not Game.pending_promotions.is_empty():
		var u: Unit = Game.pending_promotions[0]
		if u == null or u.dead:
			Game.pending_promotions.pop_front()
			continue
		var choices := Game.promotion_choices(u)
		if choices.is_empty():
			Game.pending_promotions.pop_front()
			continue
		var cards := HBoxContainer.new()
		cards.add_theme_constant_override("separation", 14)
		cards.alignment = BoxContainer.ALIGNMENT_CENTER
		for id in choices:
			var pr: Dictionary = Data.PROMOTION[id]
			cards.add_child(_card(str(pr["name"]), "promotion", str(pr["desc"]), "",
				func():
					Game.take_promotion(u, id)
					Game.pending_promotions.erase(u)
					close_modal()
					await get_tree().create_timer(0.12).timeout
					_check_pending(), Pal.TEAL, 214))
		open_modal("promotion", u.rank_name() + " " + str(Data.UNIT[u.type]["name"]),
			"It has survived enough to learn something. This choice stays with the unit.",
			[cards], [], false)
		return
	refresh()


# ---------------------------------------------------------- build menu ----
func show_build_menu(c: City) -> void:
	var options := Game.build_options(c)
	var y := Game.city_yield(c)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 3)

	var groups := {"wonder": [], "structure": [], "unit": []}
	for o in options:
		groups[o["kind"]].append(o)
	if Game.army_size(Game.me) >= Game.army_cap(Game.me):
		inner.add_child(_spacer(0, 6))
		var warn := _wrap_label(
			"Your army is at its limit of %d. Found or take another city to raise it."
				% Game.army_cap(Game.me), 13, Pal.ACCENT_DEEP, 560)
		inner.add_child(warn)
	var titles := {"wonder": "Wonders", "structure": "Structures", "unit": "Units"}
	for kind in ["unit", "structure", "wonder"]:
		if groups[kind].is_empty():
			continue
		inner.add_child(_spacer(0, 6))
		inner.add_child(_label(str(titles[kind]).to_upper(), 10, Pal.INK_FAINT, true))
		for o in groups[kind]:
			var cost := Game.item_cost(Game.me, o)
			var turns := maxi(1, int(ceil(float(cost) / float(maxi(1, y.y)))))
			var nm := ""
			var sub := ""
			match kind:
				"unit":
					var d: Dictionary = Data.UNIT[o["id"]]
					nm = str(d["name"])
					if d.has("replaces"):
						nm += "  ·  unique"
					sub = str(d.get("desc", ""))
					if sub == "":
						sub = "Strength %d" % int(d["str"])
						if d.has("rs"):
							sub += " · ranged %d (range %d)" % [int(d["rs"]), int(d["rng"])]
						sub += " · %d movement" % int(d["mv"])
					if d.has("req"):
						sub += " · needs " + str(Data.RESOURCE[d["req"]]["name"])
				"structure":
					nm = str(Data.STRUCTURE[o["id"]]["name"])
					sub = str(Data.STRUCTURE[o["id"]]["desc"])
				_:
					nm = str(Data.WONDER[o["id"]]["name"]) + "  ·  wonder"
					sub = str(Data.WONDER[o["id"]]["desc"])
			var selected: bool = not c.queue.is_empty() and c.queue["kind"] == o["kind"] and c.queue["id"] == o["id"]
			inner.add_child(_list_row(nm, sub, str(cost), "%d turns" % turns,
				func():
					if not c.queue.is_empty() and (c.queue["kind"] != o["kind"] or c.queue["id"] != o["id"]):
						c.prod = int(c.prod * 0.7)
					c.queue = {"kind": o["kind"], "id": o["id"]}
					Game.dismiss_hint("build")
					close_modal(), selected))
	if options.is_empty():
		inner.add_child(_label("Nothing to build here.", 13, Pal.INK_SOFT))

	var cap_note := ""
	if Game.me.cities.size() >= Game.me.city_cap():
		cap_note = "  ·  city limit reached (%d)" % Game.me.city_cap()
	else:
		cap_note = "  ·  %d of %d cities" % [Game.me.cities.size(), Game.me.city_cap()]
	open_modal("build", c.name,
		"Size %d  ·  %d production a turn  ·  %d gold%s" % [c.pop, y.y, Game.me.gold, cap_note],
		[_scroll(inner)], [_button("Close", close_modal, "quiet")])


# ------------------------------------------------------------- nations ----
func show_nations() -> void:
	var me := Game.me
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 10)
	var met := 0
	for o in Game.rivals():
		var rel := me.relation(o.id)
		if not rel["met"]:
			continue
		met += 1
		var theirs: Dictionary = o.relation(me.id)
		var att := float(theirs["attitude"])
		var card := _panel(11)
		var sb := _sb(Pal.PANEL, Pal.PANEL_EDGE, 11)
		sb.shadow_size = 0
		card.add_theme_stylebox_override("panel", sb)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 6)

		var status := "at peace"
		var status_col := Pal.GOOD
		if not o.alive:
			status = "destroyed"
			status_col = Pal.INK_FAINT
		elif rel["war"]:
			status = "AT WAR"
			status_col = Pal.BAD
		v.add_child(_row([_dot(o.colour, 12),
			_label(str(o.leader["name"]), 16, Pal.INK, true),
			_label("of " + o.name, 12, Pal.INK_SOFT),
			_spacer(), _label(status, 12, status_col, true)], 8))
		v.add_child(_wrap_label(str(o.leader.get("agenda_desc", "")), 12, Pal.INK_SOFT, 520))

		var power := Game.empire_power(o)
		var mine := Game.empire_power(me)
		var rel_text := "a match for you"
		if power > mine * 1.3:
			rel_text = "stronger than you"
		elif power < mine * 0.75:
			rel_text = "weaker than you"
		v.add_child(_row([
			_label(Game.attitude_word(att), 12,
				Pal.GOOD if att >= 25 else (Pal.BAD if att <= -40 else Pal.INK_SOFT), true),
			_bar((att + 100.0) / 200.0,
				Pal.GOOD if att >= 25 else (Pal.BAD if att <= -40 else Pal.INK_FAINT), 220, 6),
			_spacer(), _label(rel_text, 12, Pal.INK_SOFT)], 10))
		v.add_child(_label("%d cities · %s Age · %d edicts" %
			[o.cities.size(), Data.AGES[o.age]["name"], o.edicts.size()], 12, Pal.INK_FAINT))

		var acts := HBoxContainer.new()
		acts.add_theme_constant_override("separation", 6)
		if o.alive:
			if rel["war"]:
				acts.add_child(_button("Sue for Peace", func(): _sue_for_peace(o)))
			else:
				var g1 := _button("Gift 60g", func(): _gift(o, 60))
				g1.disabled = me.gold < 60
				var g2 := _button("Gift 200g", func(): _gift(o, 200))
				g2.disabled = me.gold < 200
				acts.add_child(g1)
				acts.add_child(g2)
				acts.add_child(_button("Demand Tribute", func(): _demand(o)))
				acts.add_child(_button("Declare War", func():
					Game.declare_war(me, o)
					show_nations()
					map.queue_redraw(), "danger"))
		v.add_child(acts)
		card.add_child(v)
		inner.add_child(card)

	if met == 0:
		inner.add_child(_label("You have met no one yet. Send a scout over the hills.",
			13, Pal.INK_SOFT))
	open_modal("nations", "The Nations",
		"Rivals remember what you do. Their agendas decide what they make of it.",
		[_scroll(inner)], [_button("Close", close_modal, "quiet")])


func _gift(o: Player, amount: int) -> void:
	if Game.me.gold < amount:
		return
	Game.me.gold -= amount
	var rel := o.relation(Game.me.id)
	rel["attitude"] = minf(100.0, float(rel["attitude"]) + amount / 5.0)
	Game.log_line("You send %d gold to %s." % [amount, o.name], "good")
	show_nations()


func _sue_for_peace(o: Player) -> void:
	var rel := o.relation(Game.me.id)
	var mine := Game.empire_power(Game.me)
	var theirs := Game.empire_power(o)
	var willing := (float(rel["attitude"]) > -55.0 and (mine > theirs * 0.85 or Game.rng.chance(0.5))) \
		or theirs < mine * 0.6
	if willing:
		Game.make_peace(Game.me, o)
		_show_banner("Peace with " + o.name, "the guns fall silent")
	else:
		Game.log_line("%s refuses peace." % str(o.leader["name"]), "war")
		rel["attitude"] -= 4.0
	show_nations()
	map.queue_redraw()


func _demand(o: Player) -> void:
	var rel := o.relation(Game.me.id)
	var mine := Game.empire_power(Game.me)
	var theirs := Game.empire_power(o)
	var scared := mine > theirs * 1.25 or float(rel["attitude"]) > 45.0
	if scared and o.gold >= 40:
		var amount := mini(o.gold, 40 + int(o.gold * 0.35))
		o.gold -= amount
		Game.me.gold += amount
		rel["attitude"] -= 0.0 if Game.me.mod("tribute_up") > 0.0 else 16.0
		rel["paid"] = int(rel["paid"]) + 1
		Game.log_line("%s pays %d gold in tribute." % [o.name, amount], "good")
	else:
		rel["attitude"] -= 4.0 if Game.me.mod("tribute_up") > 0.0 else 22.0
		rel["refused"] = int(rel["refused"]) + 1
		Game.log_line("%s refuses, and remembers it." % str(o.leader["name"]), "war")
		if float(rel["attitude"]) < -60.0 and Game.rng.chance(0.35):
			Game.declare_war(o, Game.me)
	show_nations()


func show_tribute_demand(p: Player) -> void:
	var amount := mini(Game.me.gold, 40 + Game.turn * 2)
	if amount < 20:
		return
	open_modal("tribute", str(p.leader["name"]) + " Demands Tribute",
		"A delegation of %s waits in your court. They ask for %d gold, and are not asking politely."
			% [p.name, amount],
		[_centre(_label("Refusing costs you nothing today.", 13, Pal.INK_SOFT))],
		[_button("Pay %d gold" % amount, func():
			Game.me.gold -= amount
			p.gold += amount
			var rel := p.relation(Game.me.id)
			rel["attitude"] = float(rel["attitude"]) + 24.0
			Game.log_line("You pay %d gold to %s." % [amount, p.name])
			close_modal(), "primary"),
		 _button("Refuse", func():
			var rel2 := p.relation(Game.me.id)
			rel2["attitude"] = float(rel2["attitude"]) - 28.0
			Game.log_line("You refuse %s." % str(p.leader["name"]), "war")
			if float(rel2["attitude"]) < -45.0 and Game.rng.chance(0.5):
				Game.declare_war(p, Game.me)
			close_modal(), "danger")], false)


func show_peace_offer(p: Player) -> void:
	open_modal("peace", str(p.leader["name"]) + " Sues for Peace",
		"%s has had enough of this war." % p.name,
		[_centre(_label("Accepting ends the war and sets a truce of twelve turns.", 13, Pal.INK_SOFT))],
		[_button("Accept peace", func():
			Game.make_peace(Game.me, p)
			close_modal(), "primary"),
		 _button("Fight on", func():
			var rel := p.relation(Game.me.id)
			rel["attitude"] = float(rel["attitude"]) - 10.0
			close_modal(), "danger")], false)


# -------------------------------------------------------------- cities ----
func show_cities() -> void:
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 3)
	for c in Game.me.cities:
		var y := Game.city_yield(c)
		var sub := "%s%d food · %d prod · +%d gold · +%d progress" % [
			"+" if y.x >= 0 else "", y.x, y.y, y.z, y.w]
		var right := "idle"
		var right2 := ""
		if not c.queue.is_empty():
			right = c.queue_name()
			right2 = "%d turns" % maxi(1, int(ceil(
				float(Game.item_cost(Game.me, c.queue) - c.prod) / float(maxi(1, y.y)))))
		inner.add_child(_list_row(("★ " if c.is_capital else "") + c.name + "   size " + str(c.pop),
			sub, right, right2, func():
				close_modal()
				map.select_city(c)
				main.centre_on(c.coord)
				refresh()))
	open_modal("cities", "Your Cities",
		"%d of %d · the limit rises only through Edicts" % [Game.me.cities.size(), Game.me.city_cap()],
		[_scroll(inner)], [_button("Close", close_modal, "quiet")])


# -------------------------------------------------------------- edicts ----
func show_edicts() -> void:
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 3)
	for age in range(Game.me.age + 1):
		var mine: Array = []
		for e in EdictData.LIST[age]:
			if Game.me.edicts.has(e["id"]):
				mine.append(e)
		if mine.is_empty():
			continue
		inner.add_child(_spacer(0, 6))
		inner.add_child(_label(str(Data.AGES[age]["name"]).to_upper() + " AGE", 10, Pal.INK_FAINT, true))
		for e in mine:
			inner.add_child(_list_row(str(e["name"]), str(e["desc"]), "", "", Callable()))
	if not Game.me.wonders.is_empty():
		inner.add_child(_spacer(0, 6))
		inner.add_child(_label("WONDERS", 10, Pal.INK_FAINT, true))
		for w in Game.me.wonders:
			inner.add_child(_list_row(str(Data.WONDER[w]["name"]), str(Data.WONDER[w]["desc"]),
				"", "", Callable()))
	if Game.me.edicts.is_empty():
		inner.add_child(_label("No edicts yet. Progress brings the first.", 13, Pal.INK_SOFT))
	open_modal("edicts", "Your Edicts",
		"%d of 18 taken · %s Age" % [Game.me.edicts.size(), Data.AGES[Game.me.age]["name"]],
		[_scroll(inner)], [_button("Close", close_modal, "quiet")])


# ---------------------------------------------------------------- help ----
func show_help() -> void:
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 9)
	var sections := [
		["The shape of a run",
		 "One hundred turns, six Ages, eighteen Edicts. Progress fills the bar at the top; each time it fills you draft one Edict from three, and the two you refuse are gone for the run. Three Breakthroughs advance the Age."],
		["How you win",
		 "Build The Beacon in the Atomic Age, take every rival capital, or hold half the cities in the world. If turn 100 arrives, the highest score wins."],
		["How you lose",
		 "Lose every city. It can happen by turn twenty-five if you leave your capital open."],
		["Deliberately absent",
		 "No worker units and no tile micromanagement: land improves as your cities work it, and each city picks its own tiles from a focus you set with one click. Your city limit is small and rises only through Edicts, so sprawling gains you nothing."],
		["Fighting",
		 "One military unit per tile, and a civilian may share it. Your army has a ceiling of three soldiers plus one for every city you hold, shown beside your treasury — the way to a bigger army is more ground. Ranged units strike without reply. Siege breaks walls and little else. A city must be beaten to zero defence and then entered by a melee unit. Units that survive earn promotions you choose."],
		["Controls",
		 "Click a unit then a tile to move · Space for the next unit · Enter to end the turn · F fortify · S sleep · C capital · drag or WASD to pan · wheel to zoom · Esc for the menu · M mute · [ and ] for volume"],
	]
	for s in sections:
		inner.add_child(_label(str(s[0]).to_upper(), 10, Pal.ACCENT, true))
		inner.add_child(_wrap_label(str(s[1]), 13, Pal.INK, 560))
	var was_start := _modal_id == "start"
	open_modal("help", "RogueCiv", "A civilisation, start to finish, in one sitting.",
		[_scroll(inner, 420)],
		[_button("Back" if was_start else "Play", func():
			if was_start:
				show_start_screen()
			else:
				close_modal(), "primary")])


# ----------------------------------------------------------- game over ----
func show_game_over(won: bool, how: String) -> void:
	var me := Game.me
	var titles := {
		"beacon": ["The Beacon Burns", "Your Beacon lights the sky, and will be seen long after the last of you is gone."],
		"conquest": ["The World is Yours", "No rival capital still flies its own flag."],
		"dominion": ["Half the World", "More cities answer to you than to everyone else together. The rest is a formality."],
		"time": ["The Reckoning", "A hundred turns have passed. History renders its verdict."],
		"wiped": ["Your People Are Scattered", "The last of your cities has fallen. Nothing remains but the name."],
	}
	var t: Array = titles.get(how, ["The Run Ends", ""])
	_save_best(me.score)

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 4)
	var big := _title(str(me.score), 58)
	big.add_theme_color_override("font_color", Pal.ACCENT)
	big.add_theme_color_override("font_shadow_color", Pal.INK)
	big.add_theme_color_override("font_outline_color", Pal.INK)
	big.add_theme_constant_override("outline_size", 8)
	inner.add_child(big)
	var cap := _label("FINAL SCORE", 10, Pal.INK_FAINT, true)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inner.add_child(cap)
	inner.add_child(_spacer(0, 8))

	var pop := 0
	for c in me.cities:
		pop += c.pop
	for row in [
		["Cities held", me.cities.size(), me.cities.size() * 38],
		["Population", pop, pop * 7],
		["Edicts adopted", "%d / 18" % me.edicts.size(), me.edicts.size() * 26],
		["Wonders raised", me.wonders.size(), me.wonders.size() * 65],
		["Age reached", Data.AGES[me.age]["name"], me.age * 90],
		["Units destroyed", me.kills, me.kills * 6],
		["Capitals taken", me.captured_capitals, me.captured_capitals * 170],
	]:
		inner.add_child(_row([
			_label("%s  (%s)" % [row[0], str(row[1])], 13, Pal.INK_SOFT),
			_spacer(), _label(str(row[2]), 13, Pal.INK, true)]))

	inner.add_child(_spacer(0, 8))
	inner.add_child(_label("FINAL STANDING", 10, Pal.INK_FAINT, true))
	var standing: Array = []
	for p in Game.players:
		if not p.is_barbarian:
			standing.append({"p": p, "s": Game.score_of(p)})
	standing.sort_custom(func(a, b): return a["s"] > b["s"])
	for entry in standing:
		var p: Player = entry["p"]
		inner.add_child(_row([_dot(p.colour, 10),
			_label(str(p.leader["name"]) + " of " + p.name, 13,
				Pal.ACCENT if p == me else Pal.INK, p == me),
			_label("" if p.alive else "destroyed", 11, Pal.INK_FAINT),
			_spacer(), _label(str(entry["s"]), 13, Pal.INK, true)], 8))
	inner.add_child(_spacer(0, 6))
	var foot := _label("seed %d · %s · %d turns" % [Game.seed_value,
		str(EdictData.DIFFICULTIES[Game.difficulty]["name"]), Game.turn], 11, Pal.INK_FAINT)
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inner.add_child(foot)

	open_modal("over", ("🏆 " if won else "") + str(t[0]), str(t[1]),
		[inner], [_button("New Run", func():
			close_modal()
			show_start_screen(), "primary")], false)
