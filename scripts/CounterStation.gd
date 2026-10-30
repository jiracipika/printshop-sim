class_name CounterStation
extends Node3D

## Service counter (v0.58.0) -- the shop's front-of-house island against the
## front wall: honey-plywood top on a sage fascia with dark-steel legs, a
## brass desk bell and a paper slip pad on top, and a small "COUNTER" sign.
## Furniture only this slice: walk-in customers arrive in v0.59.0 and will
## wait behind the counter (wall side). Built from primitives in the shop
## palette (pattern of FinishingStation.gd) -- no external assets, at most
## 10 visible meshes so the v020 draw-call budget holds. Joins the
## "stations" group with meta "station_kind" = "counter".
## Main sets .position (COUNTER_POS); this node never bakes its own spot.

## Fixed home of the counter island (front wall; spans x -2.6..-1.2 and
## z 2.225..2.875 -- clear of the spool crate's 1.6 m interact corner and
## of grab_test's placement corridor along x~0).
const COUNTER_POS := Vector3(-1.9, 0, 2.55)

## Counter top slab: 1.4 x 0.08 x 0.65, centered at y 1.0.
const TOP_CENTER_Y := 1.0
## Top surface height -- what the bell and slip pad sit on.
const TOP_Y := 1.04

## Desk bell base offset on the counter top (local space).
const BELL_OFFSET := Vector3(-0.45, 1.04, 0.0)
## Slip pad offset on the counter top (local space).
const PAD_OFFSET := Vector3(0.4, 1.04, 0.05)

## Ring animation length in seconds; ring_frame() walks 0..1 over it.
const RING_DURATION := 0.35

## The squashable brass dome (base cylinder stays put).
var _bell_dome: MeshInstance3D
## Deterministic ring seam: -1 = never rung, 0..1 while the squash plays.
## Advanced ONLY by tick() -- no _process of its own -- so tests can freeze
## it and the sim stays deterministic.
var _ring_t := -1.0


func _ready() -> void:
	add_to_group("stations")
	set_meta("station_kind", "counter")
	_build_visuals()
	_build_collision()


## World-space position of the desk bell (where a customer's hand would land).
func bell_pos() -> Vector3:
	return to_global(BELL_OFFSET)


## Arm the bell squash: the frame timer restarts at 0 and walks to 1 as
## tick() is called. Nothing animates until something ticks.
func ring() -> void:
	_ring_t = 0.0
	_apply_squash()


## Advance the ring timer by `delta` seconds. No-op before the first ring()
## ("ticked only when rung"); clamps at frame 1 when the squash is done.
func tick(delta: float) -> void:
	if _ring_t < 0.0:
		return
	_ring_t = minf(_ring_t + delta / RING_DURATION, 1.0)
	_apply_squash()


## Deterministic 0..1 ring animation frame (0 while never rung).
func ring_frame() -> float:
	return clampf(_ring_t, 0.0, 1.0)


## Squash the dome along the ring frame: a half-sine dip, back to rest at
## frame 0 and frame 1.
func _apply_squash() -> void:
	if _bell_dome == null:
		return
	var s := 0.0
	if _ring_t >= 0.0:
		s = sin(PI * _ring_t)
	_bell_dome.scale = Vector3(1.0 + 0.25 * s, 1.0 - 0.4 * s, 1.0 + 0.25 * s)


func _build_visuals() -> void:
	var honey := StandardMaterial3D.new()
	honey.albedo_color = Color.WHITE
	honey.albedo_texture = ShopArt.wood(Color("#C3A076"))
	honey.roughness = 0.7
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color.WHITE
	steel.albedo_texture = ShopArt.metal(Color("#202B2B"))
	steel.roughness = 0.5
	var sage := StandardMaterial3D.new()
	sage.albedo_color = Color("#738771")
	sage.roughness = 0.6
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color("#B5A642")
	brass.metallic = 0.6
	brass.roughness = 0.35
	var paper := StandardMaterial3D.new()
	paper.albedo_color = Color("#F2EDE0")
	paper.roughness = 0.9

	# Counter top: honey plywood 1.4 x 0.08 x 0.65, centered at y 1.0.
	var top := MeshInstance3D.new()
	var top_box := BoxMesh.new()
	top_box.size = Vector3(1.4, 0.08, 0.65)
	top.mesh = top_box
	top.material_override = honey
	top.position = Vector3(0, TOP_CENTER_Y, 0)
	add_child(top)

	# Sage fascia panel under the front edge (room side, -z), floor to top.
	var fascia := MeshInstance3D.new()
	var fascia_box := BoxMesh.new()
	fascia_box.size = Vector3(1.4, 0.92, 0.05)
	fascia.mesh = fascia_box
	fascia.material_override = sage
	fascia.position = Vector3(0, 0.5, -0.3)
	add_child(fascia)

	# Two dark-steel legs at the ends.
	for sx in [-0.6, 0.6]:
		var leg := MeshInstance3D.new()
		var leg_box := BoxMesh.new()
		leg_box.size = Vector3(0.08, 0.96, 0.08)
		leg.mesh = leg_box
		leg.material_override = steel
		leg.position = Vector3(sx, 0.48, 0.0)
		add_child(leg)

	# Brass desk bell: flat base cylinder + squashable dome sphere at
	# BELL_OFFSET. The dome is the only part ring()/tick() move.
	var bell_base := MeshInstance3D.new()
	var bell_cyl := CylinderMesh.new()
	bell_cyl.height = 0.02
	bell_cyl.bottom_radius = 0.055
	bell_cyl.top_radius = 0.05
	bell_base.mesh = bell_cyl
	bell_base.material_override = brass
	bell_base.position = BELL_OFFSET + Vector3(0, 0.01, 0)
	add_child(bell_base)
	_bell_dome = MeshInstance3D.new()
	var dome := SphereMesh.new()
	dome.radius = 0.042
	dome.height = 0.084
	_bell_dome.mesh = dome
	_bell_dome.material_override = brass
	_bell_dome.position = BELL_OFFSET + Vector3(0, 0.062, 0)
	add_child(_bell_dome)

	# Paper slip pad: thin white box with 3 loose sheets stacked on top,
	# each a quad nudged a hair so the stack reads as paper, not a slab.
	var pad := MeshInstance3D.new()
	var pad_box := BoxMesh.new()
	pad_box.size = Vector3(0.34, 0.016, 0.44)
	pad.mesh = pad_box
	pad.material_override = paper
	pad.position = PAD_OFFSET + Vector3(0, 0.008, 0)
	add_child(pad)
	for i in range(3):
		var sheet := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(0.28, 0.38)
		sheet.mesh = quad
		var sheet_mat := StandardMaterial3D.new()
		sheet_mat.albedo_color = Color("#FAF7EE") if i % 2 == 0 else Color("#EFEAD9")
		sheet_mat.roughness = 0.9
		sheet.material_override = sheet_mat
		sheet.rotation = Vector3(-PI / 2.0, 0.05 * float(i - 1), 0.0)
		sheet.position = PAD_OFFSET \
			+ Vector3(0.004 * float(i - 1), 0.018 + 0.0012 * float(i), 0.0)
		add_child(sheet)

	# Sign so the spot reads as "the counter", same style as the finishing
	# bench sign; billboarded so it faces the room from any angle.
	var sign := Label3D.new()
	sign.text = "COUNTER"
	sign.font_size = 48
	sign.pixel_size = 0.0022
	sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sign.modulate = Color("#EEE5D3")
	sign.outline_modulate = Color("#202B2B")
	sign.outline_size = 5
	sign.position = Vector3(0, 1.5, 0)
	add_child(sign)


## Solid volume of the whole island (top surface included) so the player
## cannot walk through it; sits on the world layer like the other furniture.
func _build_collision() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var shape := CollisionShape3D.new()
	var col := BoxShape3D.new()
	col.size = Vector3(1.4, TOP_Y, 0.65)
	shape.shape = col
	body.add_child(shape)
	body.position = Vector3(0, TOP_Y / 2.0, 0)
	add_child(body)
