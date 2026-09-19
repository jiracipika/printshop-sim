extends Node3D

class_name Printer

## Desktop FDM printer built from primitives (task 04 visual upgrade).
## Replaces the old 1.2 m cube shell. Origin stays near the BED CENTER so
## Main._nearest_printer() measures distance from the bed, not the frame top.
## Contracts kept: "printers" group, printer_index meta, StaticBody3D (layer 1).

const FRAME_COLOR := Color("#202B2B")     # dark steel
const ACCENT_COLOR := Color("#DA623A")    # terracotta
const BED_COLOR := Color("#C3A076")       # honey ply

const FOOTPRINT := 0.5
const HEIGHT := 0.6
const BED_THICK := 0.04
const NOZZLE_BLOCK := Vector3(0.09, 0.07, 0.09)

var nozzle: Node3D      # small block; Main oscillates its X during RUNNING
var gantry: Node3D
var bed: MeshInstance3D
var _nozzle_mat: StandardMaterial3D

func _ready() -> void:
	add_to_group("printers")
	_build()

## Printer visuals; caller sets printer_index meta if needed.
func _build() -> void:
	# Base: dark steel slab the whole printer sits on.
	var base := _box(Vector3(FOOTPRINT, 0.06, FOOTPRINT), FRAME_COLOR)
	base.position = Vector3(0, 0.03, 0)
	base.name = "Base"
	add_child(base)

	# Build plate: honey plywood, flat and visible from above.
	bed = _box(Vector3(FOOTPRINT * 0.92, BED_THICK, FOOTPRINT * 0.92), BED_COLOR)
	bed.position = Vector3(0, 0.06 + BED_THICK / 2.0, 0)
	bed.name = "Bed"
	add_child(bed)

	# Two vertical Z rails at the back.
	for sx in [-0.18, 0.18]:
		var rail := _box(Vector3(0.05, HEIGHT, 0.05), FRAME_COLOR)
		rail.position = Vector3(sx, HEIGHT / 2.0, -0.20)
		rail.name = "ZRail"
		add_child(rail)

	# Terracotta cross-brace between the rails for a hint of accent.
	var brace := _box(Vector3(0.41, 0.04, 0.04), ACCENT_COLOR)
	brace.position = Vector3(0, HEIGHT - 0.06, -0.20)
	brace.name = "AccentBrace"
	add_child(brace)

	# X gantry spanning the rails; nozzle block hangs from it.
	gantry = Node3D.new()
	gantry.name = "Gantry"
	add_child(gantry)

	var beam := _box(Vector3(0.41, 0.05, 0.05), FRAME_COLOR)
	beam.position = Vector3(0, 0.38, 0.0)
	beam.name = "GantryBeam"
	gantry.add_child(beam)

	var carriage := _box(Vector3(0.1, 0.1, 0.06), ACCENT_COLOR)
	carriage.position = Vector3(0, 0.38, 0.0)
	carriage.name = "Carriage"
	gantry.add_child(carriage)

	# Nozzle assembly: carriage + steel nozzle block pointing at the bed.
	nozzle = Node3D.new()
	nozzle.name = "Nozzle"
	gantry.add_child(nozzle)

	_nozzle_mat = StandardMaterial3D.new()
	_nozzle_mat.albedo_color = Color(0.85, 0.85, 0.9)
	_nozzle_mat.roughness = 0.3
	var block := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = NOZZLE_BLOCK
	block.mesh = bm
	block.material_override = _nozzle_mat
	block.position = Vector3(0, -0.05, 0)
	block.name = "NozzleBlock"
	nozzle.add_child(block)

	var tip := _box(Vector3(0.02, 0.03, 0.02), FRAME_COLOR)
	tip.position = Vector3(0, -0.095, 0)
	tip.name = "NozzleTip"
	nozzle.add_child(tip)

	# Collision: single static box roughly matching footprint + height so
	# player collision and grab-ray occlusion still work (layer 1).
	var body := StaticBody3D.new()
	body.name = "PrinterBody"
	body.collision_layer = 1
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(FOOTPRINT, HEIGHT, FOOTPRINT)
	col.shape = shape
	col.position = Vector3(0, HEIGHT / 2.0, 0)
	body.add_child(col)
	add_child(body)

func _box(size: Vector3, color: Color) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	m.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.6
	m.material_override = mat
	return m

## Drive the nozzle block X position; "life" while RUNNING. t = any clock.
func set_nozzle_scan(t: float) -> void:
	if nozzle == null:
		return
	nozzle.position.x = sin(t * 1.7) * 0.14

## Distinct failed-print look: nozzle block grays out (print spoilage cue).
func set_failed(failed: bool) -> void:
	if _nozzle_mat == null:
		return
	_nozzle_mat.albedo_color = Color(0.45, 0.45, 0.45) if failed else Color(0.85, 0.85, 0.9)
