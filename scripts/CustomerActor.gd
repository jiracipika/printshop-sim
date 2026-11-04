class_name CustomerActor
extends Node3D

## A walk-in customer (v0.59.0) — a scripted low-poly person waiting behind
## the counter (wall side), torso above the 1.0 m counter top. Pure visual:
## no physics body, never collides with the player or furniture, and NEVER
## exists at boot (Main add_child()s one on arrival and queue_free()s it on
## despawn — the v020 budget audit counts boot meshes, so a waiting customer
## must cost nothing while nobody waits).
##
## Deterministic seam (WindowLife pattern, hazard 13): the only animation is
## the idle bob inside _advance(t), gated by set_motion() — calm mode freezes
## the actor exactly where it stands. No Tween, no AnimationPlayer, no RNG.
## Outfit color is a palette draw pinned by hash("walkin-outfit-<day>-<i>").
##
## Outfit variety (v0.60.0): the torso palette widens to six warm-maker
## colors and each walk-in may wear a flat cap OR a scarf, chosen AND colored
## by deterministic hash draws. The accessory is built as extra SURFACES on
## the existing Head/Torso meshes (cap = crown + brim surfaces on the head,
## scarf = one band surface on the torso) rather than child MeshInstance3D
## nodes — same look, same draw calls per accessory, zero extra audit nodes,
## so slice 2's "a fresh customer is two meshes" pin and the v020 budget both
## hold. Nothing rises above the head top (crown surface stays under it), and
## the accessories ride the meshes they decorate, so the bob carries them.

## Where a waiting customer stands: behind the counter, facing the room
## (the room lies toward -z from here). Main sets .position; never baked.
const WAIT_POS := Vector3(-1.9, 0, 2.75)

## Shop-palette outfits (v0.60.0: six warm-maker colors — sage / honey /
## terracotta / steel / honey-dark / mint).
const OUTFITS: Array[Color] = [
	Color("#738771"), Color("#C3A076"), Color("#AD5F3D"),
	Color("#4A5A5A"), Color("#B98A5F"), Color("#A8C8AC"),
]

## Accessory accent palette (design tokens) for the cap/scarf color draw.
const ACCENTS: Array[Color] = [
	Color("#DA623B"), Color("#202B2B"), Color("#C3A076"), Color("#EEE5D3"),
]

## Accessory kinds drawn per (day, index): none / flat cap / scarf.
const ACC_NONE := 0
const ACC_CAP := 1
const ACC_SCARF := 2

const TORSO_Y := 1.32
const HEAD_Y := 1.76
const BOB_AMPLITUDE := 0.012
const BOB_SPEED := 2.2

## Calm mode (v0.51.0): when Main turns this off, _advance stops stepping —
## the customer holds exactly where they stand until it returns.
var motion_enabled := true
var _bob_t := 0.0
var _torso: MeshInstance3D
var _head: MeshInstance3D


func _ready() -> void:
	_build()


## Deterministic outfit draw for the (day, slot) walk-in.
static func outfit_color(day: int, index: int) -> Color:
	return OUTFITS[absi(hash("walkin-outfit-%d-%d" % [day, index])) % OUTFITS.size()]


## Deterministic accessory kind for the (day, slot) walk-in: none, flat cap
## or scarf (roughly one third each).
static func accessory_kind(day: int, index: int) -> int:
	return absi(hash("walkin-acc-%d-%d" % [day, index])) % 3


## Deterministic accessory color for the (day, slot) walk-in.
static func accessory_color(day: int, index: int) -> Color:
	return ACCENTS[absi(hash("walkin-acc-c-%d-%d" % [day, index])) % ACCENTS.size()]


## Calm mode (v0.51.0): Main pushes the persisted "calm_mode" setting here.
func set_motion(on: bool) -> void:
	motion_enabled = on


func _process(delta: float) -> void:
	_advance(delta)


## Deterministic heartbeat: steps the exact math _process runs, so tests can
## drive the bob instantly and prove calm mode freezes it. The gate lives
## here so _process inherits it (WindowLife pattern).
func _advance(seconds: float) -> void:
	if not motion_enabled:
		return
	_bob_t += seconds
	var s := sin(_bob_t * BOB_SPEED)
	if _torso != null:
		_torso.position.y = TORSO_Y + BOB_AMPLITUDE * s
	if _head != null:
		_head.position.y = HEAD_Y + BOB_AMPLITUDE * s


## Two mesh nodes (torso + head); when spawned for a walk-in (meta stamped by
## Main) the torso/head become multi-surface ArrayMeshes carrying the hashed
## accessory. Built facing -z, i.e. out into the room from behind the
## counter.
func _build() -> void:
	var outfit := StandardMaterial3D.new()
	outfit.albedo_color = outfit_color_for_instance()
	outfit.roughness = 0.7
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color("#D9B08C")
	skin.roughness = 0.8

	var day := int(get_meta("walkin_day", -1))
	var index := int(get_meta("walkin_index", -1))
	var kind := accessory_kind(day, index) if has_meta("walkin_day") else ACC_NONE
	var accent := StandardMaterial3D.new()
	accent.albedo_color = accessory_color(day, index) if has_meta("walkin_day") \
		else OUTFITS[0]
	accent.roughness = 0.7

	var capsule := CapsuleMesh.new()
	capsule.radius = 0.16
	capsule.height = 0.62
	_torso = MeshInstance3D.new()
	_torso.name = "Torso"
	if kind == ACC_SCARF:
		# Capsule plus one scarf band surface wrapped at the neck (torso
		# local: the capsule top sits at +0.31, the neck just above it).
		var tm := ArrayMesh.new()
		tm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,
			MeshKit.offset_arrays(capsule, Vector3.ZERO))
		tm.surface_set_material(0, outfit)
		tm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,
			MeshKit.offset_arrays(MeshKit.box_mesh(Vector3(0.30, 0.06, 0.30)),
				Vector3(0, 0.335, 0)))
		tm.surface_set_material(1, accent)
		_torso.mesh = tm
	else:
		_torso.mesh = capsule
		_torso.material_override = outfit
	_torso.position = Vector3(0, TORSO_Y, 0)
	add_child(_torso)

	var sphere := SphereMesh.new()
	sphere.radius = 0.105
	sphere.height = 0.21
	_head = MeshInstance3D.new()
	_head.name = "Head"
	if kind == ACC_CAP:
		# Sphere plus flat-cap crown and brim surfaces. The crown stays UNDER
		# the sphere top (+0.105 local): crown top = +0.075 + 0.025 = 0.100.
		var hm := ArrayMesh.new()
		hm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,
			MeshKit.offset_arrays(sphere, Vector3.ZERO))
		hm.surface_set_material(0, skin)
		hm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,
			MeshKit.offset_arrays(MeshKit.box_mesh(Vector3(0.26, 0.05, 0.26)),
				Vector3(0, 0.075, 0)))
		hm.surface_set_material(1, accent)
		hm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,
			MeshKit.offset_arrays(MeshKit.box_mesh(Vector3(0.24, 0.015, 0.09)),
				Vector3(0, 0.055, -0.15)))
		hm.surface_set_material(2, accent)
		_head.mesh = hm
	else:
		_head.mesh = sphere
		_head.material_override = skin
	_head.position = Vector3(0, HEAD_Y, 0)
	add_child(_head)


## The outfit color: the deterministic (day, slot) draw when this actor was
## spawned for a walk-in (Main stamps meta), else the first palette entry.
func outfit_color_for_instance() -> Color:
	if has_meta("walkin_day"):
		return outfit_color(int(get_meta("walkin_day")), int(get_meta("walkin_index")))
	return OUTFITS[0]


## Offset/box primitives come from the shared MeshKit (v0.61.x bugfix dedup —
## the per-file copies ShopFront and CustomerActor carried are gone).
