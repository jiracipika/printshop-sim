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
signal reset_requested
signal reset_disarmed
signal settings_changed(key: String, value)

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
var _settings_applying := false
var _open := false
var _contracts_open := false
var _upgrades_open := false
var _settings_open := false
var _howto_open := false
var _stats_open := false
var _log_open := false

const COLOR_STEEL := Color("#202B2B")
const COLOR_PAPER := Color("#EEE5D3")
const COLOR_MUTED := Color("#C2CCBA")
const COLOR_HONEY := Color("#C3A076")
const COLOR_TERRA := Color("#DA623A")
const COLOR_MINT := Color("#A8C8AC")

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
	for panel in [_contracts_panel, _upgrades_panel, _settings_panel, _howto_panel, _stats_panel, _log_panel]:
		if panel != null:
			panel.visible = false
	_contracts_open = false
	_upgrades_open = false
	_settings_open = false
	_howto_open = false
	_stats_open = false
	_log_open = false
	is_open()

func close_menu() -> void:
	visible = false
	for panel in [_contracts_panel, _upgrades_panel, _settings_panel, _howto_panel, _stats_panel, _log_panel]:
		if panel != null:
			panel.visible = false
	_contracts_open = false
	_upgrades_open = false
	_settings_open = false
	_howto_open = false
	_stats_open = false
	_log_open = false
	is_open()

## True while any subpanel is showing — Esc should step back to the main
## panel rather than close the menu.
func subpanel_open() -> bool:
	return visible and (_contracts_open or _upgrades_open or _settings_open \
		or _howto_open or _stats_open or _log_open)

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
	dim.color = Color(COLOR_STEEL, 0.92)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(dim)

	var layout := VBoxContainer.new()
	layout.name = "Layout"
	layout.set_anchors_preset(Control.PRESET_FULL_RECT)
	layout.offset_left = 56.0
	layout.offset_top = 48.0
	layout.offset_right = -400.0
	layout.offset_bottom = -48.0
	layout.add_theme_constant_override("separation", 12)
	_root.add_child(layout)

	var tag := Label.new()
	tag.name = "Tag"
	tag.text = "PRINT SHOP SIM / MAIN MENU"
	tag.add_theme_color_override("font_color", COLOR_MINT)
	tag.add_theme_font_size_override("font_size", 12)
	layout.add_child(tag)

	var title := Label.new()
	title.name = "Title"
	title.text = "PRINT SHOP SIM"
	title.add_theme_color_override("font_color", COLOR_PAPER)
	title.add_theme_font_size_override("font_size", 64)
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

	var buttons := VBoxContainer.new()
	buttons.name = "Buttons"
	buttons.add_theme_constant_override("separation", 10)
	buttons.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	layout.add_child(buttons)

	var play := _make_button("Play", "Play")
	play.add_theme_color_override("font_color", COLOR_STEEL)
	var play_sb := StyleBoxFlat.new()
	play_sb.bg_color = COLOR_TERRA
	play_sb.content_margin_left = 22.0
	play_sb.content_margin_right = 22.0
	play_sb.content_margin_top = 14.0
	play_sb.content_margin_bottom = 14.0
	play.add_theme_stylebox_override("normal", play_sb)
	play.add_theme_stylebox_override("hover", play_sb)
	play.add_theme_stylebox_override("pressed", play_sb)
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

	var quit := _make_button("Quit", "Quit")
	quit.pressed.connect(func() -> void: get_tree().quit())
	buttons.add_child(quit)
	_apply_quit_visibility()

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
	b.custom_minimum_size = Vector2(240, 44)
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
	sb.bg_color = Color("#2B3934")
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

	var head := HBoxContainer.new()
	sv.add_child(head)
	var h1 := Label.new()
	h1.text = "CONTRACT BOARD"
	h1.add_theme_color_override("font_color", COLOR_PAPER)
	h1.add_theme_font_size_override("font_size", 28)
	head.add_child(h1)
	var sub := Label.new()
	sub.text = "  first come, first served — Reserve pins a job for your next printer accept"
	sub.add_theme_color_override("font_color", COLOR_MINT)
	sub.add_theme_font_size_override("font_size", 12)
	head.add_child(sub)

	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sv.add_child(scroll)

	var list := VBoxContainer.new()
	list.name = "List"
	list.add_theme_constant_override("separation", 10)
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

	var sv := VBoxContainer.new()
	sv.name = "SheetBox"
	sv.add_theme_constant_override("separation", 14)
	sheet.add_child(sv)

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

	var reset := Button.new()
	reset.name = "ResetButton"
	reset.text = "Reset shop (new game)"
	reset.add_theme_color_override("font_color", COLOR_TERRA)
	reset.add_theme_font_size_override("font_size", 15)
	reset.pressed.connect(func() -> void: reset_requested.emit())
	sv.add_child(reset)

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
		_:
			return "sfx_volume"

## Second-press confirm state for the reset button.
func arm_reset_button() -> void:
	var reset: Button = _settings_panel.get_node("Sheet/SheetBox/ResetButton")
	reset.text = "Really reset? Press again"

## Leaving settings (or any re-show) cancels the armed reset.
func disarm_reset_button() -> void:
	var reset: Button = _settings_panel.get_node_or_null("Sheet/SheetBox/ResetButton")
	if reset != null:
		reset.text = "Reset shop (new game)"
	reset_disarmed.emit()

## Push current settings into the sliders without re-emitting signals.
func show_settings(current: Dictionary) -> void:
	_settings_applying = true
	var sens: HSlider = _settings_panel.get_node("Sheet/SheetBox/SensSliderRow/SensSlider")
	var vol: HSlider = _settings_panel.get_node("Sheet/SheetBox/VolSliderRow/VolSlider")
	var music_vol: HSlider = _settings_panel.get_node("Sheet/SheetBox/MusicSliderRow/MusicSlider")
	var invert: CheckBox = _settings_panel.get_node("Sheet/SheetBox/InvertCheck")
	var shadows: CheckBox = _settings_panel.get_node("Sheet/SheetBox/ShadowsCheck")
	var music: CheckBox = _settings_panel.get_node("Sheet/SheetBox/MusicCheck")
	sens.set_value_no_signal(float(current.get("mouse_sens_scale", 1.0)))
	vol.set_value_no_signal(float(current.get("sfx_volume", 0.8)))
	music_vol.set_value_no_signal(float(current.get("music_volume", 0.35)))
	invert.set_pressed_no_signal(bool(current.get("invert_y", false)))
	shadows.set_pressed_no_signal(bool(current.get("shadows", true)))
	music.set_pressed_no_signal(bool(current.get("music_enabled", true)))
	_settings_applying = false
	_show_panel(_settings_panel)
	_settings_open = true
	is_open()

## --- how-to-play panel (v0.4.0) -------------------------------------------------

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
		+ "2.  E previews an orientation (supports, material, risk). E again confirms and starts the print.\n" \
		+ "3.  Risky orientations can fail mid-print — clear the bed with E and try a calmer angle.\n" \
		+ "4.  When the print finishes, E collects the part.\n" \
		+ "5.  Carry it to the PACKING table and press E to deliver. Grade A pays best; F pays nothing.\n" \
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
	controls.text = "Desktop: WASD move · mouse look · E interact · Esc menu        Touch: stick move · drag look · Interact · Pause"
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
func show_stats(lines: Array[String]) -> void:
	var body: Label = _stats_panel.get_node("Sheet/SheetBox/Body")
	body.text = "\n".join(lines)
	_show_panel(_stats_panel)
	_stats_open = true
	is_open()

## --- log panel (v0.15.0) ---------------------------------------------------------

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
	sb.bg_color = Color("#2B3934")
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

func _show_panel(panel: Control) -> void:
	disarm_reset_button()
	for p in [_contracts_panel, _upgrades_panel, _settings_panel, _howto_panel, _stats_panel, _log_panel]:
		if p != null:
			p.visible = p == panel
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

	var meta := HBoxContainer.new()
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
