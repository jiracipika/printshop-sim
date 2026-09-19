extends Node3D

class_name PrintVisual

## Growing print-deposition visual, web-safe (task 04).
## ONE PrintVisual per printer. A fixed pool of N_BOXES box MeshInstance3D
## slices is created up front; set_progress() sizes/stacks only as many as
## the current progress needs. No per-layer node growth, no MultiMesh need.
## Total mesh instances: N_BOXES (=32), each BoxMesh (12 tris).

const N_BOXES := 32
const SLICE_H := 0.012
const PRINT_W := 0.16     # printed object footprint
const PRINT_D := 0.16

enum FailMode { NONE, TILTED, GRAY }

var state_ok := true      # false once marked failed; used by tests
var _slices: Array[MeshInstance3D] = []
var _mats: Array[StandardMaterial3D] = []
var _current_progress := 0.0
var _fail_mode: int = FailMode.NONE

func _ready() -> void:
	visible = false
	var alt := false
	for i in range(N_BOXES):
		var m := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(PRINT_W, SLICE_H, PRINT_D)
		m.mesh = bm
		var mat := StandardMaterial3D.new()
		# Two alternating filament tints (terracotta / honey) suggest layers.
		mat.albedo_color = Color("#DA623A") if alt else Color("#C3A076").lightened(0.15)
		mat.roughness = 0.65
		m.material_override = mat
		m.position = Vector3(0, SLICE_H / 2.0 + i * SLICE_H, 0)
		m.visible = false
		add_child(m)
		_slices.append(m)
		_mats.append(mat)
		alt = not alt

func set_progress(p: float, model_name: String = "") -> void:
	p = clampf(p, 0.0, 1.0)
	_current_progress = p
	var shown := int(round(p * N_BOXES))
	for i in range(N_BOXES):
		var s := _slices[i]
		if i < shown:
			s.visible = true
			# Slight footprint taper so the stack reads as an object.
			var taper := 1.0 - 0.15 * float(i) / float(N_BOXES)
			s.scale = Vector3(taper, 1.0, taper)
		else:
			s.visible = false
	var should_show := p > 0.001
	if visible != should_show:
		visible = should_show

func reset() -> void:
	state_ok = true
	_fail_mode = FailMode.NONE
	rotation = Vector3.ZERO
	for m in _mats:
		m.albedo_color = Color("#DA623A") if _mats.find(m) % 2 == 0 else Color("#C3A076").lightened(0.15)
	set_progress(0.0, "")

func get_progress() -> float:
	return _current_progress

## DONE_FAIL look: gray out every slice (distinct from DONE_OK colors).
func mark_failed() -> void:
	state_ok = false
	_fail_mode = FailMode.GRAY
	for m in _mats:
		m.albedo_color = Color(0.55, 0.55, 0.55)

func is_failed() -> bool:
	return state_ok == false

func get_fail_mode() -> int:
	return _fail_mode

func slice_count_visible() -> int:
	var n := 0
	for s in _slices:
		if s.visible:
			n += 1
	return n
