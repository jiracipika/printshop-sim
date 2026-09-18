class_name Grabbable
extends RigidBody3D

## One interactable interface for grabbable props (task 03).
## Main.gd stores/restores physics state through the helpers below so a
## held prop cannot push or launch the player, and placement restores the
## body exactly as it was found.

var held := false
var _saved := false
var _saved_gravity_scale := 1.0
var _saved_freeze_mode := RigidBody3D.FREEZE_MODE_STATIC
var _saved_collision_layer := 0
var _saved_collision_mask := 0

func _ready() -> void:
	add_to_group("grabbables")
	collision_layer |= 4  # layer 3 "grabbable"

func can_grab() -> bool:
	return not held

func on_grabbed() -> void:
	held = true
	# Explicitly store original physics state before disabling simulation.
	_saved_gravity_scale = gravity_scale
	_saved_freeze_mode = freeze_mode
	_saved_collision_layer = collision_layer
	_saved_collision_mask = collision_mask
	_saved = true
	freeze = true
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	gravity_scale = 0.0
	# Mask 0 AND layer 0 while held: the frozen body sits inside the player
	# capsule at the hold marker — keeping any world bit would let the
	# player's mask collide with it and shove the player every frame.
	collision_mask = 0
	collision_layer = 0
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO

func on_released() -> void:
	held = false
	# Restore exactly what on_grabbed saved; without a save (never grabbed
	# or already released) the live values stand — a release must never
	# overwrite the body's real configured state with stale defaults.
	if not _saved:
		return
	_saved = false
	freeze = false
	freeze_mode = _saved_freeze_mode
	gravity_scale = _saved_gravity_scale
	collision_layer = _saved_collision_layer
	collision_mask = _saved_collision_mask
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
