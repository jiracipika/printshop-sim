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

## Test-only: simulate a web export (hides Quit exactly like the real gate).
var simulate_web := false:
	set(value):
		simulate_web = value
		_apply_quit_visibility()

var _root: Control
var _contracts_panel: Control
var _open := false
var _contracts_open := false

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
	_contracts_panel.visible = false
	_contracts_open = false
	is_open()

func close_menu() -> void:
	visible = false
	_contracts_panel.visible = false
	_contracts_open = false
	is_open()

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

	var settings := _make_button("Settings — coming soon", "Settings")
	settings.disabled = true
	buttons.add_child(settings)

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
	sub.text = "  read-only — accept at the printer"
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
		child.queue_free()
	for s in summaries:
		list.add_child(_make_card(s))
	_contracts_panel.visible = true
	_contracts_open = true
	is_open()

func _make_card(s: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	card.set_meta("contract_summary", true)
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
	for flag in s.get("risk_flags", []):
		var tag := Label.new()
		tag.text = "  [%s]" % flag
		tag.add_theme_color_override("font_color", COLOR_TERRA)
		tag.add_theme_font_size_override("font_size", 12)
		meta.add_child(tag)
	return card
