class_name FinishingStation
extends Node3D

## Finishing station — a vapor-smoothing bench. A carried part can be bumped
## one letter grade before packing (B -> A, C -> B, D -> C). F-grade parts are
## refused outright (not salvageable); A and ungraded ("") parts pass through
## with nothing to improve. One use per part is tracked by the CALLER (Main):
## the station itself is stateless across parts, like PackingStation.
## Built from primitives in the shop palette (honey plywood bench with dark
## steel legs, a steel basin on top, an emissive strip that reads "working").
## Joins the "stations" group with meta "station_kind" = "finishing" so Main
## can discover it without a direct reference.

signal finished(old_grade: String, new_grade: String)

## Result of the most recent try_finish() call:
##   { finished: bool, old_grade: String, grade: String, reason: String }
var last_result: Dictionary = {}

## One-letter bump table: anything not here is passed / refused, never bumped.
const BUMP := {"B": "A", "C": "B", "D": "C"}

## "Working" feedback: emissive strip along the basin + a small spill light.
var _strip: MeshInstance3D
var _strip_light: OmniLight3D
var _active := false


func _ready() -> void:
	add_to_group("stations")
	set_meta("station_kind", "finishing")
	_build_visuals()
	_build_collision()


func _build_visuals() -> void:
	var honey := StandardMaterial3D.new()
	honey.albedo_color = Color.WHITE
	honey.albedo_texture = ShopArt.wood(Color("#C3A076"))
	honey.roughness = 0.7
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color.WHITE
	steel.albedo_texture = ShopArt.metal(Color("#202B2B"))
	steel.roughness = 0.5
	var terracotta := StandardMaterial3D.new()
	terracotta.albedo_color = Color("#DA623A")
	terracotta.roughness = 0.6

	# Bench top: honey plywood, 1.0 x 0.9 m, top surface at 0.8 m.
	var top := MeshInstance3D.new()
	var top_box := BoxMesh.new()
	top_box.size = Vector3(1.0, 0.1, 0.9)
	top.mesh = top_box
	top.material_override = honey
	top.position = Vector3(0, 0.75, 0)
	add_child(top)

	# Terracotta fascia stripe under the top (matches the packing table).
	var fascia := MeshInstance3D.new()
	var fascia_box := BoxMesh.new()
	fascia_box.size = Vector3(1.0, 0.12, 0.94)
	fascia.mesh = fascia_box
	fascia.material_override = terracotta
	fascia.position = Vector3(0, 0.64, 0)
	add_child(fascia)

	# Four dark steel legs.
	for sx in [-0.4, 0.4]:
		for sz in [-0.35, 0.35]:
			var leg := MeshInstance3D.new()
			var leg_box := BoxMesh.new()
			leg_box.size = Vector3(0.1, 0.7, 0.1)
			leg.mesh = leg_box
			leg.material_override = steel
			leg.position = Vector3(sx, 0.35, sz)
			add_child(leg)

	# Small steel basin on the tabletop: the vapor chamber.
	var basin := MeshInstance3D.new()
	var basin_box := BoxMesh.new()
	basin_box.size = Vector3(0.42, 0.09, 0.3)
	basin.mesh = basin_box
	basin.material_override = steel
	basin.position = Vector3(-0.18, 0.85, 0.0)
	add_child(basin)

	# "Working" strip: an emissive slat on the basin's front lip, hidden until
	# set_active(true). The spill light rides along so the bench glows softly.
	var strip_mat := StandardMaterial3D.new()
	strip_mat.albedo_color = Color("#FFC98A")
	strip_mat.emission_enabled = true
	strip_mat.emission = Color("#FFC98A")
	strip_mat.emission_energy_multiplier = 1.6
	_strip = MeshInstance3D.new()
	_strip.name = "VaporStrip"
	var strip_box := BoxMesh.new()
	strip_box.size = Vector3(0.36, 0.02, 0.02)
	_strip.mesh = strip_box
	_strip.material_override = strip_mat
	_strip.position = Vector3(-0.18, 0.9, 0.16)
	_strip.visible = false
	add_child(_strip)
	_strip_light = OmniLight3D.new()
	_strip_light.omni_range = 1.2
	_strip_light.light_color = Color("#FFC98A")
	_strip_light.light_energy = 0.6
	_strip_light.position = Vector3(-0.18, 1.05, 0.1)
	_strip_light.visible = false
	add_child(_strip_light)

	# Sign so the station reads as "the place to finish a part".
	var sign := Label3D.new()
	sign.text = "FINISHING"
	sign.font_size = 48
	sign.pixel_size = 0.0022
	sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sign.modulate = Color("#EEE5D3")
	sign.outline_modulate = Color("#202B2B")
	sign.outline_size = 5
	sign.position = Vector3(0, 1.4, 0)
	add_child(sign)


func _build_collision() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var shape := CollisionShape3D.new()
	var col := BoxShape3D.new()
	col.size = Vector3(1.0, 0.8, 0.94)
	shape.shape = col
	body.add_child(shape)
	body.position = Vector3(0, 0.4, 0)
	add_child(body)


## Try to vapor-smooth one part carried at `grade`:
##   - "B" -> "A", "C" -> "B", "D" -> "C" (finished == true, signal fired),
##   - "A" or "" -> finished == true, grade unchanged (nothing to improve),
##   - "F" -> finished == false, grade "F" (refused — not salvageable),
##   - anything else fails closed: finished == false, grade "F".
## Returns the same dictionary stored in last_result. Emits `finished`
## exactly once, and only when the grade actually changed. The one-use-per-
## part bookkeeping stays with the caller; this node keeps no part state.
func try_finish(grade: String) -> Dictionary:
	if BUMP.has(grade):
		var new_grade: String = BUMP[grade]
		last_result = {
			"finished": true, "old_grade": grade, "grade": new_grade,
			"reason": "vapor-smoothed %s -> %s" % [grade, new_grade],
		}
		finished.emit(grade, new_grade)
		return last_result
	if grade == "A" or grade == "":
		last_result = {
			"finished": true, "old_grade": grade, "grade": grade,
			"reason": "nothing to improve",
		}
		return last_result
	if grade == "F":
		last_result = {
			"finished": false, "old_grade": grade, "grade": "F",
			"reason": "grade F is not salvageable",
		}
		return last_result
	last_result = {
		"finished": false, "old_grade": grade, "grade": "F",
		"reason": "unknown grade '%s' — refused" % grade,
	}
	return last_result


## Bench "working" feedback: show/hide the emissive strip + spill light.
func set_active(on: bool) -> void:
	_active = on
	if _strip != null:
		_strip.visible = on
	if _strip_light != null:
		_strip_light.visible = on


func is_active() -> bool:
	return _active
