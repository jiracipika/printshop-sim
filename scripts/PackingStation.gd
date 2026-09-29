class_name PackingStation
extends Node3D

## Task 11 (station layer) — physical packing station.
## Built from primitives in the shop palette (honey plywood table with dark
## steel legs and a terracotta fascia stripe, cardboard-tone box on top).
## Joins the "stations" group with meta "station_kind" = "packing" so Main
## can discover it without a direct reference.
##
## Station layer only: try_pack() grades and computes the payout but does
## NOT mutate the contract (INSPECTION -> PACKED stays with Main), does NOT
## touch the ledger, and emits `packed` exactly once per successful pack.

signal packed(contract_id: String, grade: String, payout_cents: int)

## Result of the most recent try_pack() call:
##   { id: String, grade: String, payout_cents: int, packed: bool, reason: String }
var last_result: Dictionary = {}

## Packed-part stack pieces (v0.18.0), hidden until a copy is packed.
var _stack: Array[MeshInstance3D] = []


## Show `count` packed copies on the table (0..3; clamped).
func set_stack_count(count: int) -> void:
	for i in range(_stack.size()):
		_stack[i].visible = i < clampi(count, 0, _stack.size())


func stack_count() -> int:
	var n := 0
	for piece in _stack:
		if piece.visible:
			n += 1
	return n


func _ready() -> void:
	add_to_group("stations")
	set_meta("station_kind", "packing")
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
	var cardboard := StandardMaterial3D.new()
	cardboard.albedo_color = Color.WHITE
	cardboard.albedo_texture = ShopArt.cardboard(Color("#B08D57"))
	cardboard.roughness = 0.85

	# Table top: honey plywood, 1.2 x 0.9 m, top surface at 0.9 m.
	var top := MeshInstance3D.new()
	var top_box := BoxMesh.new()
	top_box.size = Vector3(1.2, 0.1, 0.9)
	top.mesh = top_box
	top.material_override = honey
	top.position = Vector3(0, 0.85, 0)
	add_child(top)

	# Terracotta fascia stripe under the top.
	var fascia := MeshInstance3D.new()
	var fascia_box := BoxMesh.new()
	fascia_box.size = Vector3(1.2, 0.12, 0.94)
	fascia.mesh = fascia_box
	fascia.material_override = terracotta
	fascia.position = Vector3(0, 0.74, 0)
	add_child(fascia)

	# Four dark steel legs.
	for sx in [-0.5, 0.5]:
		for sz in [-0.35, 0.35]:
			var leg := MeshInstance3D.new()
			var leg_box := BoxMesh.new()
			leg_box.size = Vector3(0.1, 0.8, 0.1)
			leg.mesh = leg_box
			leg.material_override = steel
			leg.position = Vector3(sx, 0.4, sz)
			add_child(leg)

	# Cardboard-tone box on the tabletop.
	var box := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(0.3, 0.3, 0.3)
	box.mesh = box_mesh
	box.material_override = cardboard
	box.position = Vector3(0.25, 1.05, 0.1)
	add_child(box)

	# Sign so the station reads as "the place to deliver".
	var sign := Label3D.new()
	sign.text = "PACKING"
	sign.font_size = 48
	sign.pixel_size = 0.0022
	sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sign.modulate = Color("#EEE5D3")
	sign.outline_modulate = Color("#202B2B")
	sign.outline_size = 5
	sign.position = Vector3(0, 1.45, 0)
	add_child(sign)

	# Packed-part stack (v0.18.0): up to 3 terracotta copies pile up next to
	# the shipping box while a multi-part order is mid-completion.
	var stack_mat := StandardMaterial3D.new()
	stack_mat.albedo_color = Color("#DA623A")
	stack_mat.roughness = 0.55
	for i in range(3):
		var piece := MeshInstance3D.new()
		var pb := BoxMesh.new()
		pb.size = Vector3(0.12, 0.1, 0.12)
		piece.mesh = pb
		piece.material_override = stack_mat
		piece.position = Vector3(-0.15 + 0.14 * i, 0.95, -0.25)
		piece.visible = false
		add_child(piece)
		_stack.append(piece)


func _build_collision() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var shape := CollisionShape3D.new()
	var col := BoxShape3D.new()
	col.size = Vector3(1.2, 1.0, 0.94)
	shape.shape = col
	body.add_child(shape)
	body.position = Vector3(0, 0.5, 0)
	add_child(body)


## Validate + grade + price one pack attempt. Pure station-layer logic:
##   - contract must be in INSPECTION state (anything else is rejected
##     with a reason and no signal),
##   - grade comes from QualityCheck using the sim snapshot
##     {"final_layer": int, "total_layers": int, "risks": Dictionary},
##   - payout = roundi(contract.payout_cents * multiplier(grade)),
##   - "F" or invalid input -> packed == false, payout 0.
## Returns the same dictionary stored in last_result. Emits `packed`
## exactly once, and only when packed == true. Never mutates `contract`.
func try_pack(contract: Contract, sim_snapshot: Dictionary) -> Dictionary:
	if contract == null:
		last_result = {
			"id": "", "grade": "", "payout_cents": 0,
			"packed": false, "reason": "no contract",
		}
		return last_result

	if contract.state != Contract.State.INSPECTION:
		last_result = {
			"id": contract.id, "grade": "", "payout_cents": 0,
			"packed": false,
			"reason": "contract not at inspection (state: %s)" % Contract.state_name(contract.state),
		}
		return last_result

	var final_layer: int = int(sim_snapshot.get("final_layer", 0))
	var total_layers: int = int(sim_snapshot.get("total_layers", 0))
	var risks: Dictionary = sim_snapshot.get("risks", {}) if sim_snapshot.get("risks", {}) is Dictionary else {}
	var grade_str := QualityCheck.grade(contract, final_layer, total_layers, risks)
	var multiplier := QualityCheck.quality_multiplier(grade_str)
	var payout := roundi(contract.payout_cents * multiplier)

	if grade_str == "F":
		last_result = {
			"id": contract.id, "grade": grade_str, "payout_cents": 0,
			"packed": false, "reason": "failed inspection (grade F)",
		}
		return last_result

	last_result = {
		"id": contract.id, "grade": grade_str, "payout_cents": payout,
		"packed": true, "reason": "packed at grade %s" % grade_str,
	}
	packed.emit(contract.id, grade_str, payout)
	return last_result
