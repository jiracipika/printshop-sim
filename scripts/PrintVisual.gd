extends Node3D

class_name PrintVisual

## Fixed-pool deposition preview. Each thin section follows the selected
## blueprint profile; the shader adds fine, restrained extrusion ridges.

const N_BOXES := 48
const DEFAULT_DESIGN := {
	"name": "Storage block", "shape": "box", "width_mm": 82.0,
	"depth_mm": 70.0, "height_mm": 56.0, "layer_mm": 0.2,
	"wall_mm": 1.6, "infill_pct": 18.0, "material": "PLA", "filament": "Clay"
}
const FILAMENTS := {"Clay": Color("#DA623A"), "Sage": Color("#738771"), "Honey": Color("#C3A076")}
const RIDGE_SHADER := """
shader_type spatial;
uniform vec4 filament_tint : source_color = vec4(0.85, 0.34, 0.19, 1.0);
uniform float polymer_roughness = 0.72;
uniform float layer_pitch = 0.0002;
varying float print_height;
void vertex() {
	print_height = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}
void fragment() {
	float wave = 0.5 + 0.5 * cos(print_height / max(layer_pitch, 0.00012) * 6.2831853);
	float ridge = smoothstep(0.78, 1.0, wave);
	ALBEDO = filament_tint.rgb * (0.95 + ridge * 0.05);
	ROUGHNESS = clamp(polymer_roughness + ridge * 0.035, 0.0, 1.0);
}
"""

enum FailMode { NONE, TILTED, GRAY }

var state_ok := true
var _slices: Array[MeshInstance3D] = []
var _current_progress := 0.0
var _fail_mode: int = FailMode.NONE
var _design: Dictionary = {}
var _design_key := ""
var _material: ShaderMaterial

func _ready() -> void:
	visible = false
	_material = ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = RIDGE_SHADER
	_material.shader = shader
	for i in range(N_BOXES):
		var slice := MeshInstance3D.new()
		slice.name = "DepositionLayer%02d" % i
		slice.material_override = _material
		slice.visible = false
		add_child(slice)
		_slices.append(slice)
	set_design(DEFAULT_DESIGN)

func set_design(source: Dictionary) -> void:
	var d := DesignStudio.normalize(source if not source.is_empty() else DEFAULT_DESIGN)
	var key := JSON.stringify(d)
	if key == _design_key:
		return
	_design = d
	_design_key = key
	var filament: Color = FILAMENTS.get(str(d.filament), FILAMENTS.Clay)
	_material.set_shader_parameter("filament_tint", filament)
	_material.set_shader_parameter("polymer_roughness", 0.34 if d.material == "PETG" else 0.72)
	_material.set_shader_parameter("layer_pitch", float(d.layer_mm) / 1000.0)
	var w := float(d.width_mm) / 1000.0
	var dep := float(d.depth_mm) / 1000.0
	var height := float(d.height_mm) / 1000.0
	var step_h := height / float(N_BOXES)
	for i in range(N_BOXES):
		_slices[i].mesh = _make_layer_mesh(d, w, dep, height, i, step_h)
		_slices[i].position.y = step_h * (float(i) + 0.5)
		_slices[i].visible = false

func _make_layer_mesh(d: Dictionary, width: float, depth: float, height: float,
		index: int, step_h: float) -> Mesh:
	if d.shape == "cylinder":
		var outer_x := width * 0.5
		var outer_z := depth * 0.5
		var wall := float(d.wall_mm) / 1000.0
		var inner_x := maxf(outer_x - wall, outer_x * 0.35)
		var inner_z := maxf(outer_z - wall, outer_z * 0.35)
		# Solid first two layers give the planter a printable base; the rest are
		# open annular walls so the live silhouette matches the finished vessel.
		if index < 2:
			var base := CylinderMesh.new()
			base.top_radius = minf(outer_x, outer_z)
			base.bottom_radius = minf(outer_x, outer_z)
			base.height = step_h
			base.radial_segments = 32
			return base
		return _annulus_mesh(outer_x, outer_z, inner_x, inner_z, step_h, 32)
	if d.shape == "ring":
		var outer := minf(width, depth) * 0.5
		var inner := maxf(outer - height * 0.5, outer * 0.12)
		var tube := (outer - inner) * 0.5
		var major := (outer + inner) * 0.5
		var center_y := height * 0.5
		var dy := (float(index) + 0.5) * step_h - center_y
		if tube <= 0.0001 or absf(dy) >= tube:
			return null
		var radial := sqrt(maxf(tube * tube - dy * dy, 0.0))
		if radial <= 0.0001:
			return null
		var outer_r := major + radial
		var inner_r := maxf(major - radial, 0.0001)
		return _annulus_mesh(outer_r, outer_r, inner_r, inner_r, step_h, 48)
	var block := BoxMesh.new()
	block.size = Vector3(width, step_h, depth)
	return block

func _annulus_mesh(outer_x: float, outer_z: float, inner_x: float, inner_z: float,
		thickness: float, segments: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var y0 := -thickness * 0.5
	var y1 := thickness * 0.5
	for i in range(segments):
		var a0 := TAU * float(i) / float(segments)
		var a1 := TAU * float(i + 1) / float(segments)
		var o0 := Vector3(cos(a0) * outer_x, 0, sin(a0) * outer_z)
		var o1 := Vector3(cos(a1) * outer_x, 0, sin(a1) * outer_z)
		var i0 := Vector3(cos(a0) * inner_x, 0, sin(a0) * inner_z)
		var i1 := Vector3(cos(a1) * inner_x, 0, sin(a1) * inner_z)
		_append_quad(st, o0 + Vector3.UP * y0, o0 + Vector3.UP * y1,
			o1 + Vector3.UP * y1, o1 + Vector3.UP * y0)
		_append_quad(st, i1 + Vector3.UP * y0, i1 + Vector3.UP * y1,
			i0 + Vector3.UP * y1, i0 + Vector3.UP * y0)
		_append_quad(st, o0 + Vector3.UP * y1, i0 + Vector3.UP * y1,
			i1 + Vector3.UP * y1, o1 + Vector3.UP * y1)
		_append_quad(st, o1 + Vector3.UP * y0, i1 + Vector3.UP * y0,
			i0 + Vector3.UP * y0, o0 + Vector3.UP * y0)
	st.generate_normals()
	return st.commit()

func _append_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)
	st.add_vertex(a)
	st.add_vertex(c)
	st.add_vertex(d)

func set_progress(p: float, _model_name: String = "", design: Dictionary = {}) -> void:
	if not design.is_empty():
		set_design(design)
	p = clampf(p, 0.0, 1.0)
	_current_progress = p
	var shown := int(round(p * N_BOXES))
	for i in range(N_BOXES):
		_slices[i].visible = i < shown
	var should_show := p > 0.001
	if visible != should_show:
		visible = should_show

func reset() -> void:
	state_ok = true
	_fail_mode = FailMode.NONE
	rotation = Vector3.ZERO
	set_progress(0.0)
	_material.set_shader_parameter("filament_tint", FILAMENTS.get(str(_design.filament), FILAMENTS.Clay))

func get_progress() -> float:
	return _current_progress

func mark_failed() -> void:
	state_ok = false
	_fail_mode = FailMode.GRAY
	_material.set_shader_parameter("filament_tint", Color(0.55, 0.55, 0.55))

func is_failed() -> bool:
	return state_ok == false

func get_fail_mode() -> int:
	return _fail_mode

func slice_count_visible() -> int:
	var n := 0
	for slice in _slices:
		if slice.visible:
			n += 1
	return n
