extends CanvasLayer

class_name MainMenu

## Menus slice — full-screen main menu over the live 3D scene.
## Palette per design/language.md: steel #202B2B ground, honey #C3A076 accent
## underline, terracotta #DA623A primary action / risk tags, paper #EEE5D3 text.
##
## Boot flow: menu visible; gameplay prompt suppressed by Main while open.
## Esc routing lives in Main._unhandled_input (open <-> close).
## Accepting contracts still happens at the printer — this panel is read-only.
##
## Web test seam: `simulate_web` hides the Quit button the same way the
## OS.has_feature("web") gate does, without needing a real web export.

signal play_pressed
signal contracts_pressed
signal reserve_pressed(job_id: String)
signal upgrades_pressed
signal upgrade_buy_pressed(id: String)
signal settings_pressed
signal stats_pressed
signal log_pressed
signal release_order_pressed(idx: int)
signal today_pressed
signal reset_requested
signal slot_switch_requested(slot: int)
signal reset_disarmed
signal settings_changed(key: String, value)
signal export_code_requested
signal import_code_requested(code: String)

## Test-only: simulate a web export (hides Quit exactly like the real gate).
var simulate_web := false:
	set(value):
		simulate_web = value
		_apply_quit_visibility()

var _root: Control
var _contracts_panel: Control
var _upgrades_panel: Control
var _settings_panel: Control
var _howto_panel: Control
var _stats_panel: Control
var _log_panel: Control
var _today_panel: Control
var _settings_applying := false
## Couch menus (v0.28.0): the Play button, focused whenever the menu opens.
var _play_button: Button
var _focus_sfx: AudioStreamPlayer
var _open := false
var _contracts_open := false
var _upgrades_open := false
var _settings_open := false
var _howto_open := false
var _stats_open := false
var _log_open := false
var _today_open := false

const COLOR_STEEL := Color("#11201F")
const COLOR_PAPER := Color("#EEE5D3")
const COLOR_MUTED := Color("#C2CCBA")
const COLOR_HONEY := Color("#C3A076")
const COLOR_TERRA := Color("#F5B766")
const COLOR_MINT := Color("#A6D7CA")

func _ready() -> void:
	layer = 20
	_build()
	is_open()

func is_open() -> bool:
	_open = visible
	return _open

func open_menu() -> void:
	visible = true
	disarm_reset_button()
	if _play_button != null:
		_play_button.grab_focus()
	for panel in [_contracts_panel, _upgrades_panel, _settings_panel, _howto_panel, _stats_panel, _log_panel, _today_panel]:
		if panel != null:
			panel.visible = false
	_contracts_open = false
	_upgrades_open = false
	_settings_open = false
	_howto_open = false
	_stats_open = false
	_log_open = false
	_today_open = false
	is_open()

func close_menu() -> void:
	visible = false
	var focused := get_viewport().gui_get_focus_owner()
	if focused != null:
		focused.release_focus()
	for panel in [_contracts_panel, _upgrades_panel, _settings_panel, _howto_panel, _stats_panel, _log_panel, _today_panel]:
		if panel != null:
			panel.visible = false
	_contracts_open = false
	_upgrades_open = false
	_settings_open = false
	_howto_open = false
	_stats_open = false
	_log_open = false
	_today_open = false
	is_open()

## True while any subpanel is showing — Esc should step back to the main
## panel rather than close the menu.
func subpanel_open() -> bool:
	return visible and (_contracts_open or _upgrades_open or _settings_open \
		or _howto_open or _stats_open or _log_open or _today_open)

func production_visible() -> bool:
	return visible and _today_open and _today_panel.visible

func contracts_visible() -> bool:
	return visible and _contracts_open

func contract_cards() -> Array:
	var out: Array = []
	if _contracts_panel == null:
		return out
	var list: VBoxContainer = _contracts_panel.get_node_or_null("Sheet/SheetBox/Scroll/List")
	if list == null:
		return out
	for child in list.get_children():
		if child.has_meta("contract_summary"):
			out.append(child)
	return out

func blocks_mouse_when_closed() -> bool:
	# While hidden the layer never receives input at all; report that the
	# closed menu does not block gameplay clicks.
	return visible and _root != null and _root.mouse_filter != Control.MOUSE_FILTER_IGNORE

func _build() -> void:
	# Full-rect dark steel ground over the live 3D scene (~0.92 alpha).
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(COLOR_STEEL, 0.88)
	var backdrop := Shader.new()
	backdrop.code = """
shader_type canvas_item;
void fragment() {
	float shade = smoothstep(0.15, 0.85, UV.x);
	COLOR = vec4(mix(vec3(0.045, 0.09, 0.085), vec3(0.09, 0.17, 0.15), shade),
		mix(0.99, 0.20, shade));
}"""
	var backdrop_material := ShaderMaterial.new()
	backdrop_material.shader = backdrop
	dim.material = backdrop_material
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(dim)

	var layout := VBoxContainer.new()
	layout.name = "Layout"
	layout.set_anchors_preset(Control.PRESET_FULL_RECT)
	layout.offset_left = 24.0
	layout.offset_top = 24.0
	layout.offset_right = -24.0
	layout.offset_bottom = -38.0
	layout.add_theme_constant_override("separation", 12)
	_root.add_child(layout)

	var tag := Label.new()
	tag.name = "Tag"
	tag.text = "3D PRINTING WORKSHOP"
	tag.add_theme_color_override("font_color", COLOR_MINT)
	tag.add_theme_font_size_override("font_size", 12)
	layout.add_child(tag)

	var title := Label.new()
	title.name = "Title"
	title.text = "PRINT SHOP SIM"
	title.add_theme_color_override("font_color", COLOR_PAPER)
	title.add_theme_font_size_override("font_size", 52)
	layout.add_child(title)

	var underline := ColorRect.new()
	underline.name = "Underline"
	underline.color = COLOR_HONEY
	underline.custom_minimum_size = Vector2(220, 5)
	underline.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	layout.add_child(underline)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(spacer)

	var buttons := GridContainer.new()
	buttons.columns = 2
	buttons.name = "Buttons"
	buttons.add_theme_constant_override("h_separation", 8)
	buttons.add_theme_constant_override("v_separation", 8)
	buttons.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	layout.add_child(buttons)

	var play := _make_button("Play", "Play")
	_play_button = play
	play.add_theme_color_override("font_color", COLOR_STEEL)
	var play_sb := StyleBoxFlat.new()
	play_sb.bg_color = COLOR_TERRA
	play_sb.set_corner_radius_all(8)
	play_sb.content_margin_left = 22.0
	play_sb.content_margin_right = 22.0
	play_sb.content_margin_top = 14.0
	play_sb.content_margin_bottom = 14.0
	play.add_theme_stylebox_override("normal", play_sb)
	var play_hover := play_sb.duplicate() as StyleBoxFlat
	play_hover.bg_color = COLOR_TERRA.lightened(0.18)
	play.add_theme_stylebox_override("hover", play_hover)
	var play_pressed_style := play_sb.duplicate() as StyleBoxFlat
	play_pressed_style.bg_color = COLOR_TERRA.darkened(0.14)
	play.add_theme_stylebox_override("pressed", play_pressed_style)
	for state in ["hover", "pressed", "focus"]:
		play.add_theme_color_override("font_%s_color" % state, COLOR_STEEL)
	play.pressed.connect(func() -> void: play_pressed.emit())
	buttons.add_child(play)

	var contracts := _make_button("Contracts", "Contracts")
	contracts.pressed.connect(func() -> void: contracts_pressed.emit())
	buttons.add_child(contracts)

	var upgrades := _make_button("Upgrades", "Upgrades")
	upgrades.pressed.connect(func() -> void: upgrades_pressed.emit())
	buttons.add_child(upgrades)

	var settings := _make_button("Settings", "Settings")
	settings.pressed.connect(func() -> void: settings_pressed.emit())
	buttons.add_child(settings)

	var howto := _make_button("How to play", "HowTo")
	howto.pressed.connect(func() -> void: _show_panel(_howto_panel))
	buttons.add_child(howto)

	var stats_btn := _make_button("Stats", "Stats")
	stats_btn.pressed.connect(func() -> void: stats_pressed.emit())
	buttons.add_child(stats_btn)

	var log_btn := _make_button("Log", "Log")
	log_btn.pressed.connect(func() -> void: log_pressed.emit())
	buttons.add_child(log_btn)

	var today_btn := _make_button("Production", "Today")
	today_btn.pressed.connect(func() -> void: today_pressed.emit())
	buttons.add_child(today_btn)

	var quit := _make_button("Quit", "Quit")
	quit.pressed.connect(func() -> void: get_tree().quit())
	buttons.add_child(quit)
	_apply_quit_visibility()
	# Couch menus (v0.28.0): explicit focus chain — automatic neighbor
	# discovery proved unreliable here, so the row is wired by hand
	# (left/right along the row, with a wrap from Quit back to Play).
	var row: Array[Button] = [play, contracts, upgrades, settings, howto,
		stats_btn, log_btn, today_btn, quit]
	for i in range(row.size()):
		row[i].focus_neighbor_left = row[(i - 1 + row.size()) % row.size()].get_path()
		row[i].focus_neighbor_right = row[(i + 1) % row.size()].get_path()
		row[i].focus_neighbor_top = row[posmod(i - 2, row.size())].get_path()
		row[i].focus_neighbor_bottom = row[(i + 2) % row.size()].get_path()

	# Couch menus (v0.36.0): a soft tick whenever menu focus moves.
	_focus_sfx = AudioStreamPlayer.new()
	_focus_sfx.stream = Sfx.stream("click")
	_focus_sfx.volume_db = -18.0
	add_child(_focus_sfx)
	for b in row:
		b.focus_entered.connect(func() -> void: _focus_sfx.play())

	var version := Label.new()
	version.name = "Version"
	version.text = Version.label()
	version.add_theme_color_override("font_color", COLOR_MUTED)
	version.add_theme_font_size_override("font_size", 12)
	version.anchor_top = 1.0
	version.anchor_bottom = 1.0
	version.offset_left = 16.0
	version.offset_top = -28.0
	version.offset_right = 420.0
	version.offset_bottom = -10.0
	_root.add_child(version)

	_build_contracts_panel()
	_build_upgrades_panel()
	_build_settings_panel()
	_build_howto_panel()
	_build_stats_panel()
	_build_log_panel()
	_build_today_panel()
	var resize := func() -> void:
		var compact := get_viewport().get_visible_rect().size.x < 620.0
		var inset := 16.0 if compact else 56.0
		layout.offset_left = inset
		layout.offset_right = -inset
		title.add_theme_font_size_override("font_size", 32 if compact else 64)
		for panel in [_contracts_panel, _upgrades_panel, _settings_panel, _howto_panel,
				_stats_panel, _log_panel, _today_panel]:
			var sheet: PanelContainer = panel.get_node("Sheet")
			sheet.offset_left = inset
			sheet.offset_right = -inset
			sheet.offset_top = 16.0 if compact else 36.0
			sheet.offset_bottom = -16.0 if compact else -36.0
	get_viewport().size_changed.connect(resize)
	resize.call()

func _apply_quit_visibility() -> void:
	if _root == null:
		return
	var quit: Button = _root.get_node("Layout/Buttons/Quit")
	# Web exports never show Quit (no window to close).
	quit.visible = not simulate_web and not OS.has_feature("web")

func _make_button(label: String, btn_name: String) -> Button:
	var b := Button.new()
	b.name = btn_name
	b.text = label
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_color_override("font_color", COLOR_PAPER)
	b.add_theme_font_size_override("font_size", 17)
	b.custom_minimum_size = Vector2(132, 46)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("#263D39")
	normal.border_color = Color("#66857D")
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(8)
	normal.content_margin_left = 12
	normal.content_margin_right = 12
	b.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color("#36564F")
	b.add_theme_stylebox_override("hover", hover)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color("#192F2B")
	b.add_theme_stylebox_override("pressed", pressed)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return b

func _build_contracts_panel() -> void:
	_contracts_panel = Control.new()
	_contracts_panel.name = "ContractsPanel"
	_contracts_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_contracts_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_contracts_panel.visible = false
	_root.add_child(_contracts_panel)

	var dim := ColorRect.new()
	dim.color = Color(COLOR_STEEL, 0.92)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_contracts_panel.add_child(dim)

	var sheet := PanelContainer.new()
	sheet.name = "Sheet"
	sheet.set_anchors_preset(Control.PRESET_FULL_RECT)
	sheet.offset_left = 64.0
	sheet.offset_top = 48.0
	sheet.offset_right = -64.0
	sheet.offset_bottom = -48.0
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#1C302D")
	sb.set_corner_radius_all(12)
	sb.border_color = COLOR_MINT
	sb.set_border_width_all(1)
	sb.content_margin_left = 24.0
	sb.content_margin_right = 24.0
	sb.content_margin_top = 20.0
	sb.content_margin_bottom = 20.0
	sheet.add_theme_stylebox_override("panel", sb)
	_contracts_panel.add_child(sheet)

	var sv := VBoxContainer.new()
	sv.name = "SheetBox"
	sheet.add_child(sv)

	var head := VBoxContainer.new()
	sv.add_child(head)
	var h1 := Label.new()
	h1.text = "CONTRACT BOARD"
	h1.add_theme_color_override("font_color", COLOR_PAPER)
	h1.add_theme_font_size_override("font_size", 28)
	head.add_child(h1)
	var sub := Label.new()
	sub.text = "Reserve a job to accept it at a printer."
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.add_theme_color_override("font_color", COLOR_MINT)
	sub.add_theme_font_size_override("font_size", 12)
	head.add_child(sub)

	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sv.add_child(scroll)

	var list := VBoxContainer.new()
	list.name = "List"
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 10)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.add_child(list)

	var back := Button.new()
	back.name = "Back"
	back.text = "Back"
	back.custom_minimum_size = Vector2(140, 44)
	back.add_theme_color_override("font_color", COLOR_PAPER)
	back.add_theme_font_size_override("font_size", 17)
	back.pressed.connect(func() -> void:
		_contracts_panel.visible = false
		_contracts_open = false
		is_open())
	sv.add_child(back)

func show_contracts(summaries: Array[Dictionary]) -> void:
	var list: VBoxContainer = _contracts_panel.get_node("Sheet/SheetBox/Scroll/List")
	for child in list.get_children():
		list.remove_child(child)
		child.free()
	for s in summaries:
		list.add_child(_make_card(s))
	_show_panel(_contracts_panel)
	_contracts_open = true
	is_open()

## --- upgrades panel (task 12) ------------------------------------------------

	_focus_first_button_for("show_contracts")
func _build_upgrades_panel() -> void:
	_upgrades_panel = Control.new()
	_upgrades_panel.name = "UpgradesPanel"
	_upgrades_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_upgrades_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_upgrades_panel.visible = false
	_root.add_child(_upgrades_panel)

	var dim := ColorRect.new()
	dim.color = Color(COLOR_STEEL, 0.92)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_upgrades_panel.add_child(dim)

	var sheet := PanelContainer.new()
	sheet.name = "Sheet"
	sheet.set_anchors_preset(Control.PRESET_FULL_RECT)
	sheet.offset_left = 64.0
	sheet.offset_top = 48.0
	sheet.offset_right = -64.0
	sheet.offset_bottom = -48.0
	sheet.add_theme_stylebox_override("panel", _sheet_style())
	_upgrades_panel.add_child(sheet)

	var sv := VBoxContainer.new()
	sv.name = "SheetBox"
	sheet.add_child(sv)

	var head := HBoxContainer.new()
	head.name = "Head"
	sv.add_child(head)
	var h1 := Label.new()
	h1.name = "Title"
	h1.text = "UPGRADES"
	h1.add_theme_color_override("font_color", COLOR_PAPER)
	h1.add_theme_font_size_override("font_size", 28)
	head.add_child(h1)
	var balance := Label.new()
	balance.name = "Balance"
	balance.text = ""
	balance.add_theme_color_override("font_color", COLOR_MINT)
	balance.add_theme_font_size_override("font_size", 16)
	head.add_child(balance)

	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sv.add_child(scroll)

	var list := VBoxContainer.new()
	list.name = "List"
	list.add_theme_constant_override("separation", 10)
	scroll.add_child(list)

	sv.add_child(_make_back_button(func() -> void:
		_upgrades_panel.visible = false
		_upgrades_open = false
		is_open()))

## cards: [{id, name, desc, cost_cents, owned, affordable}]
func show_upgrades(cards: Array[Dictionary], balance_line := "") -> void:
	var list: VBoxContainer = _upgrades_panel.get_node("Sheet/SheetBox/Scroll/List")
	for child in list.get_children():
		list.remove_child(child)
		child.free()
	for c in cards:
		list.add_child(_make_upgrade_card(c))
	if balance_line != "":
		set_upgrade_balance(balance_line)
	_show_panel(_upgrades_panel)
	_upgrades_open = true
	is_open()
	_focus_first_button_for("show_upgrades")

var _balance_line := ""

## Main sets the header balance line before/alongside show_upgrades.
func set_upgrade_balance(line: String) -> void:
	_balance_line = line
	var bal: Label = _upgrades_panel.find_child("Balance", true, false) if _upgrades_panel != null else null
	if bal != null:
		bal.text = line

## Test/UI seam: the live card nodes in the upgrades list.
func upgrade_cards_ui() -> Array:
	var out: Array = []
	if _upgrades_panel == null:
		return out
	var list: VBoxContainer = _upgrades_panel.get_node("Sheet/SheetBox/Scroll/List")
	for child in list.get_children():
		out.append(child)
	return out

func _make_upgrade_card(c: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	card.set_meta("upgrade_id", str(c.get("id", "")))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#364137")
	sb.border_color = Color("#627265")
	sb.set_border_width_all(1)
	sb.content_margin_left = 16.0
	sb.content_margin_right = 16.0
	sb.content_margin_top = 12.0
	sb.content_margin_bottom = 12.0
	card.add_theme_stylebox_override("panel", sb)

	var row := HBoxContainer.new()
	card.add_child(row)

	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(v)
	var who := Label.new()
	who.text = str(c.get("name", ""))
	who.add_theme_color_override("font_color", COLOR_PAPER)
	who.add_theme_font_size_override("font_size", 18)
	v.add_child(who)
	var desc := Label.new()
	desc.text = str(c.get("desc", ""))
	desc.add_theme_color_override("font_color", COLOR_MUTED)
	desc.add_theme_font_size_override("font_size", 13)
	v.add_child(desc)

	var cost_cents := int(c.get("cost_cents", 0))
	var owned := bool(c.get("owned", false))
	var affordable := bool(c.get("affordable", false))
	card.set_meta("owned", owned)
	var btn := Button.new()
	btn.name = "Buy"
	btn.custom_minimum_size = Vector2(150, 44)
	btn.add_theme_font_size_override("font_size", 16)
	if owned:
		btn.text = "Installed"
		btn.disabled = true
	else:
		btn.text = "Buy $%d.%02d" % [cost_cents / 100, cost_cents % 100]
		btn.disabled = not affordable
		btn.pressed.connect(func() -> void: upgrade_buy_pressed.emit(str(c.get("id", ""))))
	if owned:
		btn.add_theme_color_override("font_color", COLOR_MINT)
	elif affordable:
		btn.add_theme_color_override("font_color", COLOR_HONEY)
	else:
		btn.add_theme_color_override("font_color", COLOR_MUTED)
	row.add_child(btn)
	return card

## --- settings panel (task 12) -------------------------------------------------

func _build_settings_panel() -> void:
	_settings_panel = Control.new()
	_settings_panel.name = "SettingsPanel"
	_settings_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_settings_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_settings_panel.visible = false
	_root.add_child(_settings_panel)

	var dim := ColorRect.new()
	dim.color = Color(COLOR_STEEL, 0.92)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_settings_panel.add_child(dim)

	var sheet := PanelContainer.new()
	sheet.name = "Sheet"
	sheet.set_anchors_preset(Control.PRESET_FULL_RECT)
	sheet.offset_left = 300.0
	sheet.offset_top = 110.0
	sheet.offset_right = -300.0
	sheet.offset_bottom = -260.0
	sheet.add_theme_stylebox_override("panel", _sheet_style())
	_settings_panel.add_child(sheet)

	# Scrollable sheet (v0.50.0): the settings list outgrew the panel — the
	# rows scroll now, so short windows can always reach the back button.
	var scroll := ScrollContainer.new()
	scroll.name = "SheetScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sheet.add_child(scroll)

	var sv := VBoxContainer.new()
	sv.name = "SheetBox"
	sv.add_theme_constant_override("separation", 14)
	sv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(sv)

	var h1 := Label.new()
	h1.text = "SETTINGS"
	h1.add_theme_color_override("font_color", COLOR_PAPER)
	h1.add_theme_font_size_override("font_size", 28)
	sv.add_child(h1)

	sv.add_child(_labeled_slider("Mouse look speed", "SensSlider", 0.3, 2.5, 0.05))
	sv.add_child(_labeled_slider("Sound volume", "VolSlider", 0.0, 1.0, 0.05))
	sv.add_child(_labeled_slider("Music volume", "MusicSlider", 0.0, 1.0, 0.05))

	var music := CheckBox.new()
	music.name = "MusicCheck"
	music.text = "Shop radio (lo-fi loop)"
	music.add_theme_color_override("font_color", COLOR_PAPER)
	music.add_theme_font_size_override("font_size", 16)
	music.toggled.connect(func(on: bool) -> void:
		if not _settings_applying:
			settings_changed.emit("music_enabled", on))
	sv.add_child(music)

	var invert := CheckBox.new()
	invert.name = "InvertCheck"
	invert.text = "Invert look Y"
	invert.add_theme_color_override("font_color", COLOR_PAPER)
	invert.add_theme_font_size_override("font_size", 16)
	invert.toggled.connect(func(on: bool) -> void:
		if not _settings_applying:
			settings_changed.emit("invert_y", on))
	sv.add_child(invert)

	var shadows := CheckBox.new()
	shadows.name = "ShadowsCheck"
	shadows.text = "Directional shadows (uncheck on slow devices)"
	shadows.add_theme_color_override("font_color", COLOR_PAPER)
	shadows.add_theme_font_size_override("font_size", 16)
	shadows.toggled.connect(func(on: bool) -> void:
		if not _settings_applying:
			settings_changed.emit("shadows", on))
	sv.add_child(shadows)

	# Quality preset (v0.20.0): one dropdown driving shadows + glow; the
	# shadows checkbox above stays in sync (checked = Standard, off = Low).
	var haptics := CheckBox.new()
	haptics.name = "HapticsCheck"
	haptics.text = "Gamepad rumble (haptics)"
	haptics.add_theme_color_override("font_color", COLOR_PAPER)
	haptics.add_theme_font_size_override("font_size", 16)
	haptics.toggled.connect(func(on: bool) -> void:
		if not _settings_applying:
			settings_changed.emit("haptics", on))
	sv.add_child(haptics)

	# Rumble strength (v0.48.0): scales both rumble magnitudes; 0 mutes.
	sv.add_child(_labeled_slider("Rumble strength", "RumbleSlider", 0.0, 100.0, 10.0))

	# Calm mode (v0.51.0): freezes ambient motion (rain, snow, clouds and the
	# window's birds/van) for motion-sensitive players.
	var calm := CheckBox.new()
	calm.name = "CalmCheck"
	calm.text = "Calm mode (freeze rain, snow & window motion)"
	calm.add_theme_color_override("font_color", COLOR_PAPER)
	calm.add_theme_font_size_override("font_size", 16)
	calm.toggled.connect(func(on: bool) -> void:
		if not _settings_applying:
			settings_changed.emit("calm_mode", on))
	sv.add_child(calm)

	var quality_row := HBoxContainer.new()
	quality_row.name = "QualityRow"
	var quality_label := Label.new()
	quality_label.text = "Quality preset"
	quality_label.add_theme_color_override("font_color", COLOR_PAPER)
	quality_label.add_theme_font_size_override("font_size", 16)
	quality_row.add_child(quality_label)
	var quality_opt := OptionButton.new()
	quality_opt.name = "QualityOption"
	for preset in ["Low", "Standard", "High"]:
		quality_opt.add_item(preset)
	quality_opt.add_theme_font_size_override("font_size", 15)
	quality_opt.item_selected.connect(func(idx: int) -> void:
		if not _settings_applying:
			settings_changed.emit("quality_preset", ["Low", "Standard", "High"][idx]))
	quality_row.add_child(quality_opt)
	sv.add_child(quality_row)

	var slot_row := HBoxContainer.new()
	slot_row.name = "SlotRow"
	var slot_label := Label.new()
	slot_label.text = "Save slot"
	slot_label.add_theme_color_override("font_color", COLOR_PAPER)
	slot_label.add_theme_font_size_override("font_size", 16)
	slot_row.add_child(slot_label)
	var slot_opt := OptionButton.new()
	slot_opt.name = "SlotOption"
	for n in ["Shop 1", "Shop 2", "Shop 3"]:
		slot_opt.add_item(n)
	slot_opt.add_theme_font_size_override("font_size", 15)
	slot_opt.item_selected.connect(func(idx: int) -> void:
		if not _settings_applying:
			slot_switch_requested.emit(idx + 1))
	slot_row.add_child(slot_opt)
	sv.add_child(slot_row)

	var reset := Button.new()
	reset.name = "ResetButton"
	reset.text = "Reset shop (new game)"
	reset.add_theme_color_override("font_color", COLOR_TERRA)
	reset.add_theme_font_size_override("font_size", 15)
	reset.pressed.connect(func() -> void: reset_requested.emit())
	sv.add_child(reset)

	# Shop codes (v0.50.0): export fills the field with the save as a
	# portable code; import applies a pasted code over the ACTIVE slot
	# (two-press confirm, like reset).
	var code_label := Label.new()
	code_label.name = "CodeLabel"
	code_label.text = "Shop code — copy this shop to another slot or device"
	code_label.add_theme_color_override("font_color", COLOR_PAPER)
	code_label.add_theme_font_size_override("font_size", 14)
	sv.add_child(code_label)

	var code_field := TextEdit.new()
	code_field.name = "CodeField"
	code_field.placeholder_text = "Export fills this — or paste a code to import"
	code_field.custom_minimum_size = Vector2(0, 84)
	code_field.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	code_field.add_theme_font_size_override("font_size", 12)
	code_field.add_theme_color_override("font_color", COLOR_PAPER)
	sv.add_child(code_field)

	var code_row := HBoxContainer.new()
	code_row.name = "CodeRow"
	code_row.add_theme_constant_override("separation", 16)
	var code_export := Button.new()
	code_export.name = "ExportCodeButton"
	code_export.text = "Export save code"
	code_export.add_theme_font_size_override("font_size", 15)
	code_export.pressed.connect(func() -> void: export_code_requested.emit())
	code_row.add_child(code_export)
	var code_import := Button.new()
	code_import.name = "ImportCodeButton"
	code_import.text = "Import code below"
	code_import.add_theme_color_override("font_color", COLOR_TERRA)
	code_import.add_theme_font_size_override("font_size", 15)
	code_import.pressed.connect(func() -> void:
		import_code_requested.emit(code_field.text))
	code_row.add_child(code_import)
	sv.add_child(code_row)

	sv.add_child(_make_back_button(func() -> void:
		_settings_panel.visible = false
		_settings_open = false
		is_open()))

func _labeled_slider(label_text: String, slider_name: String, min_v: float, max_v: float, step: float) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = slider_name + "Row"
	row.add_theme_constant_override("separation", 16)
	var l := Label.new()
	l.text = label_text
	l.custom_minimum_size = Vector2(190, 0)
	l.add_theme_color_override("font_color", COLOR_PAPER)
	l.add_theme_font_size_override("font_size", 16)
	row.add_child(l)
	var slider := HSlider.new()
	slider.name = slider_name
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = step
	slider.custom_minimum_size = Vector2(260, 32)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.value_changed.connect(func(v: float) -> void:
		if not _settings_applying:
			settings_changed.emit(slider_name_to_key(slider_name), v))
	row.add_child(slider)
	return row

static func slider_name_to_key(slider_name: String) -> String:
	match slider_name:
		"SensSlider":
			return "mouse_sens_scale"
		"MusicSlider":
			return "music_volume"
		"RumbleSlider":
			return "haptics_strength"
		_:
			return "sfx_volume"

## Second-press confirm state for the reset button.
func arm_reset_button() -> void:
	var reset: Button = _settings_panel.get_node("Sheet/SheetScroll/SheetBox/ResetButton")
	reset.text = "Really reset? Press again"

## Leaving settings (or any re-show) cancels the armed reset — and the
## armed import with it, so a half-confirmed code never lands later.
func disarm_reset_button() -> void:
	var reset: Button = _settings_panel.get_node_or_null("Sheet/SheetScroll/SheetBox/ResetButton")
	if reset != null:
		reset.text = "Reset shop (new game)"
	disarm_import_button()
	reset_disarmed.emit()

## Second-press confirm state for the import button (v0.50.0).
func arm_import_button() -> void:
	var btn: Button = _settings_panel.get_node("Sheet/SheetScroll/SheetBox/CodeRow/ImportCodeButton")
	btn.text = "Really import? Press again"

func disarm_import_button() -> void:
	var btn: Button = _settings_panel.get_node_or_null("Sheet/SheetScroll/SheetBox/CodeRow/ImportCodeButton")
	if btn != null:
		btn.text = "Import code below"

## Fill the code field from Main (v0.50.0 export path).
func set_shop_code(code: String) -> void:
	(_settings_panel.get_node("Sheet/SheetScroll/SheetBox/CodeField") as TextEdit).text = code

## Push current settings into the sliders without re-emitting signals.
func show_settings(current: Dictionary) -> void:
	_settings_applying = true
	var sens: HSlider = _settings_panel.get_node("Sheet/SheetScroll/SheetBox/SensSliderRow/SensSlider")
	var vol: HSlider = _settings_panel.get_node("Sheet/SheetScroll/SheetBox/VolSliderRow/VolSlider")
	var music_vol: HSlider = _settings_panel.get_node("Sheet/SheetScroll/SheetBox/MusicSliderRow/MusicSlider")
	var invert: CheckBox = _settings_panel.get_node("Sheet/SheetScroll/SheetBox/InvertCheck")
	var shadows: CheckBox = _settings_panel.get_node("Sheet/SheetScroll/SheetBox/ShadowsCheck")
	var music: CheckBox = _settings_panel.get_node("Sheet/SheetScroll/SheetBox/MusicCheck")
	sens.set_value_no_signal(float(current.get("mouse_sens_scale", 1.0)))
	vol.set_value_no_signal(float(current.get("sfx_volume", 0.8)))
	music_vol.set_value_no_signal(float(current.get("music_volume", 0.35)))
	invert.set_pressed_no_signal(bool(current.get("invert_y", false)))
	shadows.set_pressed_no_signal(bool(current.get("shadows", true)))
	music.set_pressed_no_signal(bool(current.get("music_enabled", true)))
	(_settings_panel.get_node("Sheet/SheetScroll/SheetBox/HapticsCheck") as CheckBox) \
		.set_pressed_no_signal(bool(current.get("haptics", true)))
	(_settings_panel.get_node("Sheet/SheetScroll/SheetBox/RumbleSliderRow/RumbleSlider") as HSlider) \
		.set_value_no_signal(float(current.get("haptics_strength", 100)))
	(_settings_panel.get_node("Sheet/SheetScroll/SheetBox/CalmCheck") as CheckBox) \
		.set_pressed_no_signal(bool(current.get("calm_mode", false)))
	(_settings_panel.get_node("Sheet/SheetScroll/SheetBox/SlotRow/SlotOption") as OptionButton) \
		.selected = clampi(int(current.get("active_slot", 1)), 1, 3) - 1
	var preset: String = str(current.get("quality_preset", "Standard"))
	var qidx := ["Low", "Standard", "High"].find(preset)
	(_settings_panel.get_node("Sheet/SheetScroll/SheetBox/QualityRow/QualityOption") as OptionButton) \
		.selected = qidx if qidx >= 0 else 1
	_settings_applying = false
	_show_panel(_settings_panel)
	_settings_open = true
	is_open()

## --- how-to-play panel (v0.4.0) -------------------------------------------------

	_chain_settings_focus()
	_focus_first_button_for("show_settings")
func _build_howto_panel() -> void:
	_howto_panel = Control.new()
	_howto_panel.name = "HowToPanel"
	_howto_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_howto_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_howto_panel.visible = false
	_root.add_child(_howto_panel)

	var dim := ColorRect.new()
	dim.color = Color(COLOR_STEEL, 0.92)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_howto_panel.add_child(dim)

	var sheet := PanelContainer.new()
	sheet.name = "Sheet"
	sheet.set_anchors_preset(Control.PRESET_FULL_RECT)
	sheet.offset_left = 140.0
	sheet.offset_top = 60.0
	sheet.offset_right = -140.0
	sheet.offset_bottom = -80.0
	sheet.add_theme_stylebox_override("panel", _sheet_style())
	_howto_panel.add_child(sheet)

	var sv := VBoxContainer.new()
	sv.name = "SheetBox"
	sv.add_theme_constant_override("separation", 10)
	sheet.add_child(sv)

	var h1 := Label.new()
	h1.name = "Title"
	h1.text = "HOW TO PLAY"
	h1.add_theme_color_override("font_color", COLOR_PAPER)
	h1.add_theme_font_size_override("font_size", 28)
	sv.add_child(h1)

	var body := Label.new()
	body.name = "Body"
	body.text = "\nTHE LOOP\n" \
		+ "1.  Walk to a printer and press E to accept a job from the board.\n" \
		+ "2.  E previews upright (supports, material, risk). R rotates the preview; E confirms and prints.\n" \
		+ "3.  Risky orientations can fail mid-print — clear the bed with E and try a calmer angle.\n" \
		+ "4.  When the print finishes, E collects the part.\n" \
		+ "5.  Board jobs go to PACKING; walk-in orders go back to the customer at the COUNTER. E delivers.\n" \
		+ "×2/×3 orders: the payout is per copy — pack each part, then E at the printer prints the next.\n" \
		+ "\nINPUTS\n" \
		+ "Mouse + keyboard: WASD move, mouse look, E interact, R rotate preview, Esc menu, F2 photo.\n" \
		+ "Touch: left stick move, right side look, Interact confirms, Rotate changes orientation, Pause.\n" \
		+ "Gamepad: stick/d-pad move, right stick look, A interact/confirm, X rotate preview, START menu, Y photo.\n" \
		+ "\nWATCH THE CLOCK\n" \
		+ "Days pass (~90 s each). Rent is due every morning — unpaid rent becomes debt.\n" \
		+ "Deliver late and the client pays half. Two days too late, the job is cancelled.\n" \
		+ "RUSH jobs pay a premium if you can make a 1-2 day deadline.\n" \
		+ "First come, first served: RUSH and [2 waiting] jobs leave the board overnight —\n" \
		+ "each one you miss costs reputation. Reserve from the Contracts menu to pin a job.\n" \
		+ "\nTHE SHOP\n" \
		+ "Printer 2 stays locked until you buy the Pro machine upgrade (menu > Upgrades).\n" \
		+ "Both printers can run separate jobs at once. Upgrades cut risks and speed up prints.\n" \
		+ "E also grabs and drops spools. Esc opens this menu; F3 is the dev panel (debug builds)."
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_color_override("font_color", COLOR_PAPER)
	body.add_theme_font_size_override("font_size", 16)
	sv.add_child(body)

	var controls := Label.new()
	controls.name = "Controls"
	controls.text = "Desktop: WASD move · mouse look · E interact · R rotate · Esc menu        Touch: stick move · drag look · Interact · Rotate · Pause"
	controls.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	controls.add_theme_color_override("font_color", COLOR_MINT)
	controls.add_theme_font_size_override("font_size", 13)
	sv.add_child(controls)

	sv.add_child(_make_back_button(func() -> void:
		_howto_panel.visible = false
		_howto_open = false
		is_open()))

## --- stats panel (v0.5.0) --------------------------------------------------------

func _build_stats_panel() -> void:
	_stats_panel = Control.new()
	_stats_panel.name = "StatsPanel"
	_stats_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_stats_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_stats_panel.visible = false
	_root.add_child(_stats_panel)

	var dim := ColorRect.new()
	dim.color = Color(COLOR_STEEL, 0.92)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_stats_panel.add_child(dim)

	var sheet := PanelContainer.new()
	sheet.name = "Sheet"
	sheet.set_anchors_preset(Control.PRESET_FULL_RECT)
	sheet.offset_left = 260.0
	sheet.offset_top = 130.0
	sheet.offset_right = -260.0
	sheet.offset_bottom = -300.0
	sheet.add_theme_stylebox_override("panel", _sheet_style())
	_stats_panel.add_child(sheet)

	var sv := VBoxContainer.new()
	sv.name = "SheetBox"
	sv.add_theme_constant_override("separation", 12)
	sheet.add_child(sv)

	var h1 := Label.new()
	h1.name = "Title"
	h1.text = "SHOP STATS"
	h1.add_theme_color_override("font_color", COLOR_PAPER)
	h1.add_theme_font_size_override("font_size", 28)
	sv.add_child(h1)

	var body := Label.new()
	body.name = "Body"
	body.text = ""
	body.add_theme_color_override("font_color", COLOR_PAPER)
	body.add_theme_font_size_override("font_size", 17)
	sv.add_child(body)

	sv.add_child(_make_back_button(func() -> void:
		_stats_panel.visible = false
		_stats_open = false
		is_open()))

## lines: preformatted stat strings from Main.
func show_today(lines: Array[String], releasable: Array[Dictionary] = []) -> void:
	var list := _today_panel.get_node("Sheet/SheetBox/Scroll/List")
	var scroll: ScrollContainer = list.get_parent()
	scroll.focus_mode = Control.FOCUS_NONE
	var body: Label = list.get_node("Body")
	body.text = "\n".join(lines)
	for child in list.get_children():
		if child != body:
			list.remove_child(child)
			child.queue_free()
	for order in releasable:
		var idx := int(order.idx)
		var button := _make_button("Release P%d · %s" % [idx + 1, order.model], "Release%d" % idx)
		button.pressed.connect(func() -> void:
			if button.has_meta("armed"):
				release_order_pressed.emit(idx)
			else:
				button.set_meta("armed", true)
				button.text = "Confirm release (−0.1 rep)")
		list.add_child(button)
	_show_panel(_today_panel)
	is_open()
	_focus_first_button(_today_panel)

func show_stats(lines: Array[String]) -> void:
	var body: Label = _stats_panel.get_node("Sheet/SheetBox/Body")
	body.text = "\n".join(lines)
	_show_panel(_stats_panel)
	_stats_open = true
	is_open()

## --- log panel (v0.15.0) ---------------------------------------------------------

func _build_today_panel() -> void:
	_today_panel = Control.new()
	_today_panel.name = "TodayPanel"
	_today_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_today_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_today_panel.visible = false
	_root.add_child(_today_panel)

	var dim := ColorRect.new()
	dim.color = Color(COLOR_STEEL, 0.92)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_today_panel.add_child(dim)

	var sheet := PanelContainer.new()
	sheet.name = "Sheet"
	sheet.set_anchors_preset(Control.PRESET_FULL_RECT)
	sheet.offset_left = 260.0
	sheet.offset_top = 130.0
	sheet.offset_right = -260.0
	sheet.offset_bottom = -300.0
	sheet.add_theme_stylebox_override("panel", _sheet_style())
	_today_panel.add_child(sheet)

	var sv := VBoxContainer.new()
	sv.name = "SheetBox"
	sv.add_theme_constant_override("separation", 12)
	sheet.add_child(sv)

	var h1 := Label.new()
	h1.name = "Title"
	h1.text = "PRODUCTION"
	h1.add_theme_color_override("font_color", COLOR_PAPER)
	h1.add_theme_font_size_override("font_size", 28)
	sv.add_child(h1)

	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	sv.add_child(scroll)
	var list := VBoxContainer.new()
	list.name = "List"
	list.add_theme_constant_override("separation", 8)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	var body := Label.new()
	body.name = "Body"
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_color_override("font_color", COLOR_PAPER)
	body.add_theme_font_size_override("font_size", 17)
	list.add_child(body)

	var back := _make_back_button(func() -> void: open_menu())
	sv.add_child(back)

## lines: preformatted stat strings from Main.


func _build_log_panel() -> void:
	_log_panel = Control.new()
	_log_panel.name = "LogPanel"
	_log_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_log_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_log_panel.visible = false
	_root.add_child(_log_panel)

	var dim := ColorRect.new()
	dim.color = Color(COLOR_STEEL, 0.92)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_log_panel.add_child(dim)

	var sheet := PanelContainer.new()
	sheet.name = "Sheet"
	sheet.set_anchors_preset(Control.PRESET_FULL_RECT)
	sheet.offset_left = 110.0
	sheet.offset_top = 48.0
	sheet.offset_right = -110.0
	sheet.offset_bottom = -48.0
	sheet.add_theme_stylebox_override("panel", _sheet_style())
	_log_panel.add_child(sheet)

	var sv := VBoxContainer.new()
	sv.name = "SheetBox"
	sv.add_theme_constant_override("separation", 12)
	sheet.add_child(sv)

	var h1 := Label.new()
	h1.name = "Title"
	h1.text = "WORKSHOP LOG"
	h1.add_theme_color_override("font_color", COLOR_PAPER)
	h1.add_theme_font_size_override("font_size", 28)
	sv.add_child(h1)

	var sub := Label.new()
	sub.name = "Sub"
	sub.text = "the last 30 things that happened around the shop"
	sub.add_theme_color_override("font_color", COLOR_MINT)
	sub.add_theme_font_size_override("font_size", 12)
	sv.add_child(sub)

	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sv.add_child(scroll)

	var list := VBoxContainer.new()
	list.name = "List"
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)

	sv.add_child(_make_back_button(func() -> void:
		_log_panel.visible = false
		_log_open = false
		is_open()))

## lines: preformatted log lines from Main, oldest first.
func show_log(lines: Array[String]) -> void:
	var list: VBoxContainer = _log_panel.get_node("Sheet/SheetBox/Scroll/List")
	for child in list.get_children():
		list.remove_child(child)
		child.free()
	for i in lines.size():
		var line := lines[lines.size() - 1 - i]  # newest at the top of the page
		var l := Label.new()
		l.text = line
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		# Failures and misses read hotter than deliveries and purchases.
		var hot := "[failed]" in line or "[expired]" in line or "[cancel]" in line
		l.add_theme_color_override("font_color", COLOR_TERRA if hot else COLOR_PAPER)
		l.add_theme_font_size_override("font_size", 15)
		list.add_child(l)
	_show_panel(_log_panel)
	_log_open = true
	is_open()

## --- shared panel helpers ------------------------------------------------------

func _sheet_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#1C302D")
	sb.set_corner_radius_all(12)
	sb.border_color = COLOR_MINT
	sb.set_border_width_all(1)
	sb.content_margin_left = 24.0
	sb.content_margin_right = 24.0
	sb.content_margin_top = 20.0
	sb.content_margin_bottom = 20.0
	return sb

func _make_back_button(on_pressed: Callable) -> Button:
	var back := Button.new()
	back.name = "Back"
	back.text = "Back"
	back.custom_minimum_size = Vector2(140, 44)
	back.add_theme_color_override("font_color", COLOR_PAPER)
	back.add_theme_font_size_override("font_size", 17)
	back.pressed.connect(on_pressed)
	return back

## Couch menus (v0.28.0): explicit vertical focus chain for the settings
## panel (slider rows, checkboxes, quality option, reset, back).
func _chain_settings_focus() -> void:
	var order: Array[String] = [
		"Sheet/SheetScroll/SheetBox/SensSliderRow/SensSlider",
		"Sheet/SheetScroll/SheetBox/VolSliderRow/VolSlider",
		"Sheet/SheetScroll/SheetBox/MusicSliderRow/MusicSlider",
		"Sheet/SheetScroll/SheetBox/MusicCheck",
		"Sheet/SheetScroll/SheetBox/InvertCheck",
		"Sheet/SheetScroll/SheetBox/ShadowsCheck",
		"Sheet/SheetScroll/SheetBox/HapticsCheck",
		"Sheet/SheetScroll/SheetBox/RumbleSliderRow/RumbleSlider",
		"Sheet/SheetScroll/SheetBox/CalmCheck",
		"Sheet/SheetScroll/SheetBox/QualityRow/QualityOption",
		"Sheet/SheetScroll/SheetBox/SlotRow/SlotOption",
		"Sheet/SheetScroll/SheetBox/ResetButton",
		"Sheet/SheetScroll/SheetBox/CodeField",
		"Sheet/SheetScroll/SheetBox/CodeRow/ExportCodeButton",
		"Sheet/SheetScroll/SheetBox/CodeRow/ImportCodeButton",
		"Sheet/SheetScroll/SheetBox/Back",
	]
	var nodes: Array[Control] = []
	for path in order:
		var n: Control = _settings_panel.get_node_or_null(path) as Control
		if n == null or n.focus_mode == Control.FOCUS_NONE:
			continue
		nodes.append(n)
	for i in range(nodes.size()):
		nodes[i].focus_neighbor_bottom = nodes[(i + 1) % nodes.size()].get_path()
		nodes[i].focus_neighbor_top = nodes[(i - 1 + nodes.size()) % nodes.size()].get_path()
		nodes[i].focus_neighbor_left = NodePath("")
		nodes[i].focus_neighbor_right = NodePath("")

func _focus_first_button_for(fn_name: String) -> void:
	match fn_name:
		"show_contracts":
			_focus_first_button(_contracts_panel)
		"show_upgrades":
			_focus_first_button(_upgrades_panel)
		"show_settings":
			_focus_first_button(_settings_panel)

## Couch menus (v0.28.0): put focus on the panel's first interactive Button
## so the gamepad can navigate immediately. No-op when nothing is focusable.
func _focus_first_button(panel: Control) -> void:
	if panel == null or not panel.visible:
		return
	# Depth-first: tree order is creation order, so the panel's first
	# interactive control wins over shallower late additions.
	var stack: Array[Node] = [panel]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		if n is Control and (n as Control).focus_mode != Control.FOCUS_NONE \
				and n != panel:
			(n as Control).grab_focus()
			return
		for i in range(n.get_child_count() - 1, -1, -1):
			stack.append(n.get_child(i))

func _show_panel(panel: Control) -> void:
	disarm_reset_button()
	for p in [_contracts_panel, _upgrades_panel, _settings_panel, _howto_panel, _stats_panel, _log_panel, _today_panel]:
		if p != null:
			p.visible = p == panel
	_today_open = panel == _today_panel
	_contracts_open = panel == _contracts_panel
	_upgrades_open = panel == _upgrades_panel
	_settings_open = panel == _settings_panel
	_howto_open = panel == _howto_panel
	_stats_open = panel == _stats_panel
	_log_open = panel == _log_panel

func _make_card(s: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	card.set_meta("contract_summary", true)
	card.set_meta("job_id", str(s.get("id", "")))
	card.set_meta("reserved", bool(s.get("reserved", false)))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#364137")
	sb.border_color = Color("#627265")
	sb.set_border_width_all(1)
	sb.content_margin_left = 16.0
	sb.content_margin_right = 16.0
	sb.content_margin_top = 12.0
	sb.content_margin_bottom = 12.0
	card.add_theme_stylebox_override("panel", sb)

	var v := VBoxContainer.new()
	card.add_child(v)

	var row := HBoxContainer.new()
	v.add_child(row)
	var who := Label.new()
	who.text = "%s — %s" % [s.get("client", ""), s.get("model_name", "")]
	who.add_theme_color_override("font_color", COLOR_PAPER)
	who.add_theme_font_size_override("font_size", 18)
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	who.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(who)
	var payout := Label.new()
	var cents := int(s.get("payout_cents", 0))
	payout.name = "Payout"
	payout.text = "$%d.%02d" % [cents / 100, absi(cents) % 100]
	payout.add_theme_color_override("font_color", COLOR_MINT)
	payout.add_theme_font_size_override("font_size", 22)
	row.add_child(payout)
	card.set_meta("payout_text", payout.text)

	# Reserve (v0.14.0): pin this job to the front of the queue; the next
	# printer accept takes it. Reserved cards show the state instead.
	var reserved := bool(s.get("reserved", false))
	var btn := Button.new()
	btn.name = "Reserve"
	btn.custom_minimum_size = Vector2(128, 36)
	btn.add_theme_font_size_override("font_size", 14)
	btn.focus_mode = Control.FOCUS_ALL
	if reserved:
		btn.text = "Reserved ✓"
		btn.disabled = true
		btn.add_theme_color_override("font_color", COLOR_MINT)
	else:
		btn.text = "Reserve"
		btn.add_theme_color_override("font_color", COLOR_HONEY)
		btn.pressed.connect(func() -> void: reserve_pressed.emit(str(s.get("id", ""))))
	row.add_child(btn)

	var terms := Label.new()
	var cost := int(s.get("material_cost_cents", 0))
	terms.text = "Materials $%d.%02d per part" % [cost / 100, cost % 100]
	terms.add_theme_color_override("font_color", COLOR_MUTED)
	v.add_child(terms)

	var meta := HFlowContainer.new()
	v.add_child(meta)
	var dots := Label.new()
	var diff := int(s.get("difficulty", 1))
	var dots_text := ""
	for i in range(5):
		dots_text += "●" if i < diff else "○"
	dots.text = dots_text
	dots.add_theme_color_override("font_color", COLOR_HONEY)
	dots.add_theme_font_size_override("font_size", 14)
	meta.add_child(dots)
	if bool(s.get("rush", false)):
		var rush_tag := Label.new()
		rush_tag.name = "RushTag"
		rush_tag.text = "  [RUSH]"
		rush_tag.add_theme_color_override("font_color", COLOR_TERRA)
		rush_tag.add_theme_font_size_override("font_size", 12)
		meta.add_child(rush_tag)
	if bool(s.get("competing", false)):
		var comp_tag := Label.new()
		comp_tag.name = "CompetingTag"
		comp_tag.text = "  [2 waiting]"
		comp_tag.add_theme_color_override("font_color", COLOR_TERRA)
		comp_tag.add_theme_font_size_override("font_size", 12)
		meta.add_child(comp_tag)
	# Featured pick (v0.42.0): the board's daily highlight.
	if bool(s.get("featured", false)):
		var feat := Label.new()
		feat.name = "FeaturedTag"
		feat.text = "  [FEATURED +15%]"
		feat.add_theme_color_override("font_color", COLOR_MINT)
		feat.add_theme_font_size_override("font_size", 12)
		meta.add_child(feat)
	# Customer voice (v0.30.0): the client's handwritten note, if any.
	var note_text := str(s.get("note", ""))
	if note_text != "":
		var note := Label.new()
		note.name = "NoteTag"
		note.text = "\u201C%s\u201D" % note_text
		note.add_theme_color_override("font_color", COLOR_MUTED)
		note.add_theme_font_size_override("font_size", 13)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.custom_minimum_size = Vector2(0, 0)
		v.add_child(note)
	# Multi-part orders (v0.18.0): the payout shown is per copy.
	if int(s.get("parts_total", 1)) > 1:
		var parts_tag := Label.new()
		parts_tag.name = "PartsTag"
		parts_tag.text = "  [×%d parts]" % int(s.get("parts_total", 1))
		parts_tag.add_theme_color_override("font_color", COLOR_HONEY)
		parts_tag.add_theme_font_size_override("font_size", 12)
		meta.add_child(parts_tag)
	var color_tag := Label.new()
	color_tag.name = "ColorTag"
	var wanted := str(s.get("color", ""))
	color_tag.text = "  [%s]" % wanted if wanted != "" else ""
	color_tag.add_theme_color_override("font_color", COLOR_MINT)
	color_tag.add_theme_font_size_override("font_size", 12)
	meta.add_child(color_tag)
	var due := Label.new()
	due.name = "DueTag"
	due.text = "  · %dd" % int(s.get("deadline_days", 0))
	due.add_theme_color_override("font_color", COLOR_MUTED)
	due.add_theme_font_size_override("font_size", 12)
	meta.add_child(due)
	for flag in s.get("risk_flags", []):
		var tag := Label.new()
		tag.text = "  [%s]" % flag
		tag.add_theme_color_override("font_color", COLOR_TERRA)
		tag.add_theme_font_size_override("font_size", 12)
		meta.add_child(tag)
	return card
