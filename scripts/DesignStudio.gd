extends CanvasLayer

class_name DesignStudio

signal close_requested
signal test_print_requested(design: Dictionary)

const SAVE_PATH := "user://printshop_blueprint.json"
const INK := Color("#202B2B")
const PAPER := Color("#EEE5D3")
const MUTED := Color("#C2CCBA")
const MINT := Color("#A8C8AC")
const CLAY := Color("#DA623A")
const FILAMENTS := {"Clay": "#DA623A", "Sage": "#738771", "Honey": "#C3A076"}
const SHAPES := ["Desk planter", "Cable ring", "Storage block"]

var _design := defaults()
var _preview_root: Node3D
var _preview_mesh: MeshInstance3D
var _preview_view: SubViewport
var _info: Label
var _metric: Label
var _value_labels: Dictionary = {}
var _sliders: Dictionary = {}
var _material: OptionButton
var _buttons: Dictionary = {}

static func defaults() -> Dictionary:
	return {"name": "Desk planter", "shape": "cylinder", "width_mm": 54.0,
		"depth_mm": 54.0, "height_mm": 72.0, "layer_mm": 0.2,
		"wall_mm": 1.2, "infill_pct": 18.0, "material": "PLA", "filament": "Clay"}

static func normalize(source: Dictionary) -> Dictionary:
	var out := defaults()
	if source.get("name", "") in SHAPES:
		out["name"] = str(source["name"])
		out["shape"] = _shape_for_name(out["name"])
	for key in ["width_mm", "depth_mm"]:
		if source.get(key) is int or source.get(key) is float:
			out[key] = clampf(float(source[key]), 24.0, 140.0)
	if source.get("height_mm") is int or source.get("height_mm") is float:
		out.height_mm = clampf(float(source.height_mm), 20.0, 160.0)
	if source.get("layer_mm") is int or source.get("layer_mm") is float:
		out.layer_mm = clampf(float(source.layer_mm), 0.12, 0.32)
	if source.get("wall_mm") is int or source.get("wall_mm") is float:
		out.wall_mm = clampf(float(source.wall_mm), 0.8, 3.2)
	if source.get("infill_pct") is int or source.get("infill_pct") is float:
		out.infill_pct = clampf(float(source.infill_pct), 5.0, 40.0)
	if source.get("material") in ["PLA", "PETG"]:
		out.material = str(source.material)
	if source.get("filament") in FILAMENTS:
		out.filament = str(source.filament)
	return out

static func _shape_for_name(n: String) -> String:
	match n:
		"Cable ring": return "ring"
		"Storage block": return "box"
	return "cylinder"

static func estimate_grams(source: Dictionary) -> int:
	var d := normalize(source)
	var wall: float = float(d.wall_mm)
	var inner_w: float = maxf(float(d.width_mm) - wall * 2.0, 0.0)
	var inner_d: float = maxf(float(d.depth_mm) - wall * 2.0, 0.0)
	var shell_mm3 := (float(d.width_mm) * float(d.depth_mm) - inner_w * inner_d) * float(d.height_mm)
	var inner_mm3 := inner_w * inner_d * float(d.height_mm)
	var body_mm3 := shell_mm3 + inner_mm3 * float(d.infill_pct) / 100.0
	if d.shape == "cylinder":
		body_mm3 *= 0.72
	elif d.shape == "ring":
		body_mm3 *= 0.29
	return maxi(1, roundi(body_mm3 * 0.00124))

static func estimate_seconds(source: Dictionary) -> int:
	var d := normalize(source)
	var layers := ceilf(float(d.height_mm) / float(d.layer_mm))
	return maxi(1, roundi(layers * 0.1 + float(estimate_grams(d)) * 0.035))

static func create_mesh(source: Dictionary) -> Mesh:
	var d := normalize(source)
	var w := float(d.width_mm) / 1000.0
	var dep := float(d.depth_mm) / 1000.0
	var h := float(d.height_mm) / 1000.0
	match d.shape:
		"cylinder":
			return _hollow_cylinder(d)
		"ring":
			var ring := TorusMesh.new()
			ring.outer_radius = minf(w, dep) * 0.5
			ring.inner_radius = maxf(ring.outer_radius - h * 0.5, ring.outer_radius * 0.12)
			ring.rings = 32
			ring.ring_segments = 12
			return ring
	var block := BoxMesh.new()
	block.size = Vector3(w, h, dep)
	return block

static func _hollow_cylinder(d: Dictionary) -> ArrayMesh:
	var radius_x: float = float(d.width_mm) / 2000.0
	var radius_z: float = float(d.depth_mm) / 2000.0
	var height: float = float(d.height_mm) / 1000.0
	var wall: float = float(d.wall_mm) / 1000.0
	var inner_x := maxf(radius_x - wall, radius_x * 0.45)
	var inner_z := maxf(radius_z - wall, radius_z * 0.45)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segments := 32
	for i in range(segments):
		var a0 := TAU * float(i) / float(segments)
		var a1 := TAU * float(i + 1) / float(segments)
		var ob0 := Vector3(cos(a0) * radius_x, -height * 0.5, sin(a0) * radius_z)
		var ob1 := Vector3(cos(a1) * radius_x, -height * 0.5, sin(a1) * radius_z)
		var ot0 := Vector3(cos(a0) * radius_x, height * 0.5, sin(a0) * radius_z)
		var ot1 := Vector3(cos(a1) * radius_x, height * 0.5, sin(a1) * radius_z)
		var ib0 := Vector3(cos(a0) * inner_x, -height * 0.5, sin(a0) * inner_z)
		var ib1 := Vector3(cos(a1) * inner_x, -height * 0.5, sin(a1) * inner_z)
		var it0 := Vector3(cos(a0) * inner_x, height * 0.5, sin(a0) * inner_z)
		var it1 := Vector3(cos(a1) * inner_x, height * 0.5, sin(a1) * inner_z)
		_append_quad(st, ob0, ot0, ot1, ob1) # exterior wall
		_append_quad(st, ib1, it1, it0, ib0) # interior wall
		_append_quad(st, ot0, it0, it1, ot1) # open top rim
		_append_quad(st, ob1, ib1, ib0, ob0) # closed base rim
		st.add_vertex(Vector3(0, -height * 0.5, 0))
		st.add_vertex(ib0)
		st.add_vertex(ib1)
	st.generate_normals()
	return st.commit()

static func _append_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)
	st.add_vertex(a)
	st.add_vertex(c)
	st.add_vertex(d)

func _ready() -> void:
	layer = 30
	visible = false
	_build()

func _process(delta: float) -> void:
	if visible and _preview_mesh != null:
		_preview_mesh.rotate_y(delta * 0.28)

func open() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file != null:
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		file.close()
		if parsed is Dictionary:
			_design = normalize(parsed)
	_apply_values()
	visible = true
	_refresh_preview()
	_info.text = "A print-ready starting point. Change a size, then test it on a printer."

func close() -> void:
	visible = false

func current_design() -> Dictionary:
	return normalize(_design)

func show_feedback(message: String) -> void:
	_info.text = message

func _build() -> void:
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(INK, 0.96)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	var sheet := PanelContainer.new()
	sheet.name = "DesignSheet"
	sheet.set_anchors_preset(Control.PRESET_FULL_RECT)
	sheet.offset_left = 42.0
	sheet.offset_top = 32.0
	sheet.offset_right = -42.0
	sheet.offset_bottom = -32.0
	sheet.add_theme_stylebox_override("panel", _panel_style())
	add_child(sheet)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 24)
	sheet.add_child(columns)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.15
	left.add_theme_constant_override("separation", 10)
	columns.add_child(left)
	var title := _label("FORM LAB  /  DESIGN COMPUTER", 24, MINT)
	left.add_child(title)
	left.add_child(_label("Choose a template. Shape the size. See the estimate before you print.", 14, MUTED))
	_preview_view = SubViewport.new()
	_preview_view.name = "ModelPreview"
	_preview_view.size = Vector2i(640, 420)
	_preview_view.transparent_bg = false
	_preview_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_preview_view.world_3d = World3D.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#273631")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#C2CCBA")
	env.ambient_light_energy = 0.8
	_preview_view.world_3d.environment = env
	_preview_root = Node3D.new()
	_preview_view.add_child(_preview_root)
	var camera := Camera3D.new()
	camera.position = Vector3(0.2, 0.16, 0.34)
	camera.rotation = Vector3(-0.39, 0.53, 0.0)
	camera.fov = 38.0
	_preview_root.add_child(camera)
	camera.current = true
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-48, -28, 0)
	light.light_energy = 1.2
	_preview_root.add_child(light)
	var fill := OmniLight3D.new()
	fill.position = Vector3(-0.2, 0.12, 0.18)
	fill.light_energy = 0.35
	fill.omni_range = 1.5
	_preview_root.add_child(fill)
	_preview_mesh = MeshInstance3D.new()
	_preview_root.add_child(_preview_mesh)
	var viewport_box := SubViewportContainer.new()
	viewport_box.name = "Preview"
	viewport_box.custom_minimum_size = Vector2(440, 330)
	viewport_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	viewport_box.stretch = true
	viewport_box.add_child(_preview_view)
	left.add_child(viewport_box)
	left.add_child(_label("PLA is easy to print. PETG is tougher and more heat resistant.", 13, MUTED))

	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 400
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 9)
	columns.add_child(right)
	right.add_child(_label("START WITH A SHAPE", 14, MINT))
	var templates := HBoxContainer.new()
	for name in SHAPES:
		var button := _button(name)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_select_template.bind(name))
		templates.add_child(button)
		_buttons[name] = button
	right.add_child(templates)
	for spec in [["width_mm", "Width", 24.0, 140.0, 2.0], ["depth_mm", "Depth", 24.0, 140.0, 2.0],
		["height_mm", "Height", 20.0, 160.0, 2.0], ["wall_mm", "Wall thickness", 0.8, 3.2, 0.2],
		["layer_mm", "Layer height", 0.12, 0.32, 0.02],
		["infill_pct", "Infill", 5.0, 40.0, 1.0]]:
		_add_slider(right, str(spec[0]), str(spec[1]), float(spec[2]), float(spec[3]), float(spec[4]))
	right.add_child(_label("FILAMENT", 13, MINT))
	_material = OptionButton.new()
	_material.add_item("PLA · forgiving and low-cost", 0)
	_material.add_item("PETG · stronger and more heat resistant", 1)
	_material.item_selected.connect(func(index: int) -> void:
		_design.material = "PETG" if index == 1 else "PLA"
		_refresh_estimate())
	right.add_child(_material)
	right.add_child(_label("COLOR", 13, MINT))
	var colors := HBoxContainer.new()
	for name in FILAMENTS:
		var b := _button(name)
		b.pressed.connect(_select_filament.bind(name))
		colors.add_child(b)
	right.add_child(colors)
	_metric = _label("", 17, PAPER)
	right.add_child(_metric)
	right.add_child(_label("Shells make the walls. Infill supports the inside. Smaller layers add detail but take longer.", 13, MUTED))
	_info = _label("", 14, PAPER)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_info)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(spacer)
	var actions := HBoxContainer.new()
	var close_button := _button("Back to shop")
	close_button.pressed.connect(func() -> void: close_requested.emit())
	actions.add_child(close_button)
	var print_button := _button("Test print")
	print_button.add_theme_color_override("font_color", INK)
	print_button.add_theme_color_override("font_hover_color", INK)
	print_button.add_theme_stylebox_override("normal", _accent_style())
	print_button.add_theme_stylebox_override("hover", _accent_style())
	print_button.pressed.connect(_save_and_print)
	actions.add_child(print_button)
	right.add_child(actions)

func _add_slider(parent: VBoxContainer, key: String, title: String, min_v: float, max_v: float, step: float) -> void:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	var heading := HBoxContainer.new()
	var name := _label(title, 13, PAPER)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(name)
	var value := _label("", 13, MINT)
	heading.add_child(value)
	row.add_child(heading)
	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = step
	slider.value = float(_design[key])
	slider.value_changed.connect(func(v: float) -> void:
		_design[key] = v
		_update_value(key)
		_refresh_preview())
	row.add_child(slider)
	parent.add_child(row)
	_sliders[key] = slider
	_value_labels[key] = value
	_update_value(key)

func _apply_values() -> void:
	if _sliders.is_empty():
		return
	for key in _sliders:
		_sliders[key].set_value_no_signal(float(_design[key]))
		_update_value(key)
	_material.select(1 if _design.material == "PETG" else 0)
	_refresh_estimate()

func _update_value(key: String) -> void:
	if not _value_labels.has(key):
		return
	var suffix := " mm"
	if key == "infill_pct": suffix = "%"
	_value_labels[key].text = ("%.2f" % float(_design[key])) + suffix
	if key == "layer_mm":
		_value_labels[key].text = ("%.2f" % float(_design[key])) + suffix

func _select_template(name: String) -> void:
	_design.name = name
	_design.shape = _shape_for_name(name)
	match name:
		"Cable ring":
			_design.width_mm = 46.0
			_design.depth_mm = 46.0
			_design.height_mm = 12.0
		"Storage block":
			_design.width_mm = 88.0
			_design.depth_mm = 62.0
			_design.height_mm = 42.0
		_:
			_design.width_mm = 54.0
			_design.depth_mm = 54.0
			_design.height_mm = 72.0
	_apply_values()
	_refresh_preview()

func _select_filament(name: String) -> void:
	_design.filament = name
	_refresh_preview()

func _refresh_preview() -> void:
	if _preview_mesh == null:
		return
	_design = normalize(_design)
	_preview_mesh.mesh = create_mesh(_design)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(FILAMENTS[_design.filament])
	mat.roughness = 0.48 if _design.material == "PETG" else 0.72
	mat.metallic = 0.0
	_preview_mesh.material_override = mat
	var w := maxf(float(_design.width_mm), float(_design.depth_mm)) / 1000.0
	var h := float(_design.height_mm) / 1000.0
	var scale_factor := 0.19 / maxf(maxf(w, h), 0.02)
	_preview_mesh.scale = Vector3.ONE * scale_factor
	_preview_mesh.rotation = Vector3(deg_to_rad(-10), _preview_mesh.rotation.y, 0)
	_refresh_estimate()

func _refresh_estimate() -> void:
	if _metric == null:
		return
	var grams := estimate_grams(_design)
	var seconds := estimate_seconds(_design)
	var price := 4 if _design.material == "PLA" else 6
	_metric.text = "~%dg filament  ·  %d:%02d  ·  est. $%.2f" % [grams,
		seconds / 60, seconds % 60, float(grams * price) / 100.0]
	for name in _buttons:
		var selected := str(name) == str(_design.name)
		_buttons[name].modulate = Color("#DA623A") if selected else Color.WHITE

func _save_and_print() -> void:
	_design = normalize(_design)
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		show_feedback("Couldn't save the blueprint. Check available storage, then try again.")
		return
	file.store_string(JSON.stringify(_design))
	file.close()
	test_print_requested.emit(current_design())

func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label

func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 42)
	b.add_theme_color_override("font_color", PAPER)
	b.add_theme_font_size_override("font_size", 14)
	return b

func _panel_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color("#2B3934")
	s.border_color = MINT
	s.set_border_width_all(1)
	s.content_margin_left = 22
	s.content_margin_right = 22
	s.content_margin_top = 18
	s.content_margin_bottom = 18
	return s

func _accent_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = CLAY
	s.set_corner_radius_all(3)
	return s
