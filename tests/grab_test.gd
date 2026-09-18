extends SceneTree

## Headless grab/place gate (task 03). Behavioral, on the REAL Main scene.
## Run: godot --headless --path . -s tests/grab_test.gd
## RED before Grabbable.gd + Main.gd grabbing edits; GREEN after.

var failures := 0
var checks := 0

func _init() -> void:
	root.ready.connect(_run)

func _ok(cond: bool, label: String) -> void:
	checks += 1
	if cond:
		print("check %d: %s OK" % [checks, label])
	else:
		printerr("FAIL: %s" % label)
		failures += 1

func _spool(main) -> Grabbable:
	return main.get_node_or_null("Spool") as Grabbable

## Stand the player at `offset` from the spool and aim the camera exactly at
## it (computed pitch from real camera/spool positions). Yaw is recomputed
## from the actual player->spool direction so repeated cycles stay aligned
## even after the spool is placed at slightly different floor spots.
func _face_spool(main, offset: Vector3) -> void:
	var s := _spool(main)
	main._player.global_position = s.global_position + offset
	await physics_frame
	var to_spool: Vector3 = s.global_position - main._player.global_position
	main.yaw = atan2(-to_spool.x, -to_spool.z)
	main._player.rotation.y = main.yaw
	await physics_frame
	var cam_pos: Vector3 = main._camera.global_position
	var delta: Vector3 = s.global_position - cam_pos
	main.pitch = atan2(delta.y, Vector2(delta.x, delta.z).length())
	main._camera.rotation.x = main.pitch
	await physics_frame

func _feed_key(main, keycode: Key) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode
	ev.pressed = true
	main._unhandled_input(ev)

func _reset_spool(main) -> void:
	var s := _spool(main)
	if s.get_parent() != main:
		s.get_parent().remove_child(s)
		main.add_child(s)
	s.freeze = true
	s.global_position = Vector3(0.2, 0.14, 0.2)
	s.on_released()
	s.freeze = false

func _run() -> void:
	var packed: PackedScene = load("res://scenes/Main.tscn")
	_ok(packed != null, "Main.tscn loads")
	if packed == null:
		quit(1)
		return
	var main = packed.instantiate()
	root.add_child(main)
	await physics_frame
	await physics_frame

	var s := _spool(main)
	_ok(s != null, "spool prop exists in room")
	if s == null:
		quit(1)
		return
	_ok(s is RigidBody3D and s.is_in_group("grabbables"), "spool is rigid body in grabbables group")

	# Boot state is paused (click-to-play). E must be inert while paused;
	# then unpause for the interaction sections below.
	_feed_key(main, KEY_E)
	_ok(main.held == null, "E blocked while paused (no grab)")
	main.paused = false
	main.captured = true  # desktop pointer-lock intent active

	# --- 1. Out of range: not grabbable ---
	await _face_spool(main, Vector3(0, 0, 3.0))
	_feed_key(main, KEY_E)
	_ok(main.held == null, "out-of-range spool not grabbed (beyond 2.2 m)")

	# --- 2. Occluded: spool on bench top inside printer A's collision box ---
	s.freeze = true
	s.global_position = Vector3(-1.8, 1.09, -2.0)
	main._player.global_position = Vector3(-1.8, 0.3, -0.6)
	main.yaw = 0.0
	main._player.rotation.y = main.yaw
	await physics_frame
	var cam_pos: Vector3 = main._camera.global_position
	var delta: Vector3 = s.global_position - cam_pos
	main.pitch = atan2(delta.y, Vector2(delta.x, delta.z).length())
	main._camera.rotation.x = main.pitch
	await physics_frame
	var r: Dictionary = main._grab_raycast()
	var blocker = r.get("collider")
	_ok(r.get("grabbable") == null and blocker != null and blocker is StaticBody3D,
		"occluded spool: ray hits occluder, not the grabbable")
	_feed_key(main, KEY_E)
	_ok(main.held == null, "occluded spool not grabbed by E")

	# --- 3. In range, clear line: grab works ---
	_reset_spool(main)
	await _face_spool(main, Vector3(0, 0, 1.0))
	_feed_key(main, KEY_E)
	_ok(main.held == s, "in-range spool grabbed by E")
	if main.held == s:
		_ok(s.freeze and s.collision_mask == 0 and s.gravity_scale == 0.0,
			"held state disables physics/collision, original stored")
		_ok(s.get_parent() == main._camera.get_node("HoldMarker"),
			"held spool attached at hold marker")
	else:
		_ok(false, "held state disables physics/collision, original stored")
		_ok(false, "held spool attached at hold marker")

	# --- 4. Second grab rejected while holding ---
	var grab_again: bool = main._try_grab()
	_ok(not grab_again and main.held == s, "second grab rejected while holding")

	# --- 5. E while holding places (context-dependent) ---
	var placed: bool = main._try_place()
	_ok(placed and main.held == null and s.get_parent() == main,
		"E while holding places the spool")

	# --- 6. Held object cannot launch player: step real physics ---
	await _face_spool(main, Vector3(0, 0, 1.0))
	_feed_key(main, KEY_E)
	_ok(main.held == s, "regrabbed for launch test")
	main._player.velocity = Vector3.ZERO
	var p0: Vector3 = main._player.global_position
	for i in range(30):
		await physics_frame
	_ok(main.held == s and main._player.velocity.length() < 1.0
		and main._player.global_position.distance_to(p0) < 0.1,
		"held spool does not push or launch player over 30 physics frames")

	# --- 7. Wall-overlapping placement rejected, still held, HUD explains ---
	# Stand ~0.6 m from the back wall (inner face z=-2.9), looking ahead:
	# the hold marker drop ray lands within a spool radius of the wall.
	s.freeze = false
	main._player.global_position = Vector3(0, 0.3, -2.3)
	main.yaw = 0.0
	main.pitch = 0.0
	main._camera.rotation.x = main.pitch
	await physics_frame
	await physics_frame
	var place_ok: bool = main._try_place()
	_ok(not place_ok and main.held == s, "wall-overlapping placement rejected, still held")
	_ok("No room here" in str(main._prompt.text), "HUD shows No room here on invalid placement")

	# --- 8. Valid floor placement restores physics state ---
	main._player.global_position = Vector3(0, 0.3, 0.3)
	main.yaw = 0.0
	main.pitch = -0.8
	main._camera.rotation.x = main.pitch
	await physics_frame
	# Free-state values (captured after _reset_spool at section 3, before the
	# first grab): layer 5 (world+grabbable), mask 1. Held state zeroes both,
	# so the restore must bring back exactly these.
	place_ok = main._try_place()
	_ok(place_ok and main.held == null, "valid floor placement succeeds and empties hands")
	_ok(not s.freeze and s.collision_mask == 1 and s.gravity_scale != 0.0,
		"placement restores physics body state exactly")
	_ok(s.collision_layer == 5 and (s.collision_layer & 4) != 0,
		"collision layer preserved through cycle")
	for i in range(10):
		await physics_frame
	_ok(s.global_position.y > -0.5, "placed spool rests on surface")

	# --- 9. 30 grab/place cycles: node + collision counts stable ---
	var node_count0: int = _count_nodes(main)
	var bodies0: int = _count_collision_bodies(main)
	var cycles_ok := true
	var cycle_fail := ""
	for i in range(30):
		_reset_spool(main)
		await _face_spool(main, Vector3(0, 0, 1.0))
		if not main._try_grab():
			cycles_ok = false
			cycle_fail = "grab failed at cycle %d" % i
			break
		if not main._try_place():
			cycles_ok = false
			cycle_fail = "place failed at cycle %d" % i
			break
	_ok(cycles_ok, "30 full grab/place cycles all succeeded (%s)" % cycle_fail)
	await physics_frame
	_ok(_count_nodes(main) == node_count0, "no orphan nodes after 30 cycles")
	_ok(_count_collision_bodies(main) == bodies0, "collision body count stable after 30 cycles")
	_ok(main.held == null, "hands empty after cycles")

	# --- 10. Touch Interact path grabs too (same logic path) ---
	var tc = main.touch_controls
	tc.force_enabled = true
	main.paused = false
	tc.set_motion_enabled(true)
	_reset_spool(main)
	await _face_spool(main, Vector3(0, 0, 1.0))
	main._on_touch_interact()
	_ok(main.held == s, "touch Interact grabs through the same logic path")
	main._on_touch_interact()
	_ok(main.held == null, "touch Interact places through the same logic path")
	tc.force_enabled = false

	print("%d checks — %s" % [checks, "ALL PASS" if failures == 0 else "FAILURES: %d" % failures])
	quit(0 if failures == 0 else 1)

func _count_nodes(main: Node) -> int:
	var n := 0
	var stack: Array = [main]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		n += 1
		stack.append_array(cur.get_children())
	return n

func _count_collision_bodies(main: Node) -> int:
	var n := 0
	var stack: Array = [main]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur is CollisionObject3D:
			n += 1
		stack.append_array(cur.get_children())
	return n
