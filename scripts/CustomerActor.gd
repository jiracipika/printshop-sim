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

## Where a waiting customer stands: behind the counter, facing the room
## (the room lies toward -z from here). Main sets .position; never baked.
const WAIT_POS := Vector3(-1.9, 0, 2.75)

## Shop-palette outfits (sage / honey / terracotta / steel / clay).
const OUTFITS: Array[Color] = [
	Color("#738771"), Color("#C3A076"), Color("#AD5F3D"),
	Color("#4A5A5A"), Color("#B98A5F"),
]

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


## Two primitives: a capsule torso (outfit color) and a sphere head. Built
## facing -z, i.e. out into the room from behind the counter.
func _build() -> void:
	var outfit := StandardMaterial3D.new()
	outfit.albedo_color = outfit_color_for_instance()
	outfit.roughness = 0.7
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color("#D9B08C")
	skin.roughness = 0.8

	_torso = MeshInstance3D.new()
	_torso.name = "Torso"
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.16
	capsule.height = 0.62
	_torso.mesh = capsule
	_torso.material_override = outfit
	_torso.position = Vector3(0, TORSO_Y, 0)
	add_child(_torso)

	_head = MeshInstance3D.new()
	_head.name = "Head"
	var sphere := SphereMesh.new()
	sphere.radius = 0.105
	sphere.height = 0.21
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
