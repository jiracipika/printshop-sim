extends SceneTree

## v0.58.0 -- "The front counter": CounterStation island at (-1.9, 0, 2.55)
## with collision, the _near_counter radius (1.35 m horizontal), the
## empty-handed E branch (bell + quiet prompt, placed BEFORE the crate
## branch -- hazard 10), and the deterministic ring seam. Behavioral, on the
## REAL Main scene (pattern of room_boot_test.gd / grab_test.gd).
## Run: godot --headless --path . -s tests/counter_test.gd

const TOTAL := 22

var checks := 0
var failures := 0


func _ok(cond: bool, label: String) -> void:
	checks += 1
	if cond:
		print("ok %d: %s" % [checks, label])
	else:
		failures += 1
		printerr("FAIL %d: %s" % [checks, label])


func _init() -> void:
	root.ready.connect(_run)


## Feed one E press through Main's real input handler (grab_test pattern).
func _feed_key(main, keycode: Key) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode
	ev.pressed = true
	main._unhandled_input(ev)


## Detach every sfx player's stream, so any bell assignment afterwards can
## only come from a fresh sfx.play("bell").
func _quiet_bell(main) -> void:
	for p in main.sfx._players:
		p.stream = null


## True once a player holds the bell stream (Sfx caches it per process, so
## play("bell") assigns the same object this helper builds).
func _bell_heard(main) -> bool:
	var sfx_script = load("res://scripts/Sfx.gd")
	var bell: AudioStreamWAV = sfx_script.stream("bell")
	for p in main.sfx._players:
		if p.stream == bell:
			return true
	return false


func _run() -> void:
	print("%d checks defined" % TOTAL)
	BrowserSave.clear()
	var counter_script = load("res://scripts/CounterStation.gd")
	var packed: PackedScene = load("res://scenes/Main.tscn")
	var main = packed.instantiate()
	root.add_child(main)
	for i in range(6):
		await physics_frame
	main.paused = false
	main.captured = true  # desktop pointer-lock intent active (hazard 5)

	# Park the boot spool far from every spot this test presses E at, so
	# grab-first can never steal a press (grab range ~2.2 m).
	var boot_spool = main.get_node_or_null("Spool")
	if boot_spool != null:
		boot_spool.freeze = true
		boot_spool.global_position = Vector3(2.6, 0.14, -2.4)

	# --- 1. the station exists, placed by Main at COUNTER_POS ----------------
	var counter = main._counter
	_ok(counter != null and counter is Node3D,
		"counter node exists in the booted room")
	_ok(counter != null and counter.position.distance_to(counter_script.COUNTER_POS) < 0.001,
		"counter sits at COUNTER_POS (set by Main, not baked)")
	if counter == null:
		printerr("FATAL: no counter node; aborting")
		print("checks=%d failures=%d" % [checks, failures])
		quit(1)
		return

	# --- 2. collision body covers the counter volume -------------------------
	var body: StaticBody3D = null
	var stack: Array = [counter]
	while not stack.is_empty():
		var n = stack.pop_back()
		if n is StaticBody3D:
			body = n
			break
		stack.append_array(n.get_children())
	var aabb_ok := false
	var clear_of_corridor := false
	if body != null:
		var shape_node: CollisionShape3D = null
		for c in body.get_children():
			if c is CollisionShape3D:
				shape_node = c
				break
		if shape_node != null and shape_node.shape is BoxShape3D:
			var box: BoxShape3D = shape_node.shape
			var center: Vector3 = shape_node.global_position
			var half: Vector3 = box.size / 2.0
			var mn: Vector3 = center - half
			var mx: Vector3 = center + half
			# The island volume: x -2.6..-1.2, y 0..1.04, z 2.225..2.875.
			var vol_mn := Vector3(-2.6, 0.0, 2.225)
			var vol_mx := Vector3(-1.2, 1.04, 2.875)
			aabb_ok = (body.collision_layer & 1) != 0 \
				and mn.x < vol_mx.x and mx.x > vol_mn.x \
				and mn.y < vol_mx.y and mx.y > vol_mn.y \
				and mn.z < vol_mx.z and mx.z > vol_mn.z \
				and (mx - mn).length() < Vector3(1.4, 1.04, 0.65).length() + 0.02 \
				and center.distance_to(Vector3(-1.9, 0.52, 2.55)) < 0.02
			# grab_test's placement corridor runs along x~0 (kept to |x|<0.5).
			clear_of_corridor = mx.x < -0.5
	_ok(aabb_ok,
		"counter has a world-layer StaticBody3D whose box matches the island volume")
	_ok(clear_of_corridor, "counter collision stays clear of the grab corridor (x~0)")

	# --- 3. _near_counter radius: true at 1.2 m, false at 1.6 m --------------
	main._player.global_position = Vector3(-1.9, 0.3, 1.35)  # 1.2 m off center
	main.yaw = 0.0
	main._player.rotation.y = main.yaw
	main.pitch = 0.0
	main._camera.rotation.x = main.pitch
	await physics_frame
	await physics_frame
	_ok(main._near_counter(), "_near_counter true at 1.2 m from the counter center")
	main._player.global_position = Vector3(-1.9, 0.3, 0.95)  # 1.6 m off center
	await physics_frame
	await physics_frame
	_ok(not main._near_counter(), "_near_counter false at 1.6 m from the counter center")

	# --- 4. empty-handed E at the counter: bell + quiet prompt, nothing else -
	main._player.global_position = Vector3(-1.9, 0.3, 1.35)  # inside the radius
	await physics_frame
	await physics_frame
	var balance0: int = main.ledger.balance()
	var queue0: int = main.job_board._queue.size()
	var contracts0 := 0
	for m in main.machines:
		if m.get("contract") != null:
			contracts0 += 1
	_quiet_bell(main)
	_feed_key(main, KEY_E)
	_ok(str(main._prompt.text) == "The counter is quiet — nobody waiting yet",
		"E at the counter shows the quiet-counter prompt")
	_ok(_bell_heard(main), "E at the counter plays the bell")
	_ok(main.ledger.balance() == balance0, "the counter ring changes no money")
	var contracts1 := 0
	for m in main.machines:
		if m.get("contract") != null:
			contracts1 += 1
	_ok(main.held == null and main.job_board._queue.size() == queue0 \
			and contracts1 == contracts0 and int(main.stats.delivered) == 0,
		"the ring buys no spool, accepts no board job, starts no machine")

	# --- 5. paused gate: E while paused is inert ------------------------------
	main.paused = true
	main._set_prompt("PAUSED-SENTINEL")
	_quiet_bell(main)
	_feed_key(main, KEY_E)
	_ok(str(main._prompt.text) == "PAUSED-SENTINEL" and not _bell_heard(main),
		"no counter prompt and no bell while paused")
	main.paused = false

	# --- 6. the crate still buys: the counter branch must not steal it -------
	main._player.global_position = Vector3(-3.0, 0.3, 1.4)  # sim bot's crate spot
	main.yaw = 0.0
	main._player.rotation.y = main.yaw
	main.pitch = 0.0
	main._camera.rotation.x = main.pitch
	await physics_frame
	await physics_frame
	_ok(not main._near_counter(),
		"the crate spot sits outside the counter radius (1.59 m)")
	var balance2: int = main.ledger.balance()
	_feed_key(main, KEY_E)
	_ok(main.held != null and main._is_held_spool(),
		"E at the crate still buys a spool")
	_ok(main.ledger.balance() < balance2, "buying the spool still costs money")

	# Set the bought spool down on grab_test's proven-clear floor spot so the
	# next section is truly empty-handed (setup, unasserted).
	main._player.global_position = Vector3(0, 0.3, 0.3)
	main.pitch = -0.8
	main._camera.rotation.x = main.pitch
	await physics_frame
	await physics_frame
	main._try_place()

	# --- 7. far from the counter, behavior is unchanged ----------------------
	main._player.global_position = Vector3(0, 0.3, -2.3)  # back wall, far side
	main.yaw = 0.0
	main._player.rotation.y = main.yaw
	main.pitch = 0.0
	main._camera.rotation.x = main.pitch
	await physics_frame
	await physics_frame
	_quiet_bell(main)
	_feed_key(main, KEY_E)
	_ok(not main._near_counter()
		and str(main._prompt.text) != "The counter is quiet — nobody waiting yet",
		"far from the counter the radius is false and E never shows the quiet prompt")
	_ok(not _bell_heard(main), "far E never rings the bell")

	# --- 8. the ring seam: advances only after a ring, frozen without ticks --
	var station = counter_script.new()
	root.add_child(station)
	var fresh: float = station.ring_frame()
	station.tick(0.5)
	_ok(fresh == 0.0 and station.ring_frame() == 0.0,
		"a fresh counter's ring frame is 0 and tick() before a ring is a no-op")
	station.ring()
	var armed: float = station.ring_frame()
	station.tick(counter_script.RING_DURATION / 2.0)
	var mid: float = station.ring_frame()
	_ok(armed == 0.0 and mid > 0.4 and mid < 0.6,
		"ring() arms the frame at 0; half a duration lands near 0.5 (%.2f)" % mid)
	var frozen: float = station.ring_frame()
	await physics_frame
	await physics_frame
	_ok(station.ring_frame() == frozen,
		"the ring frame stays frozen across frames without ticks")
	station.tick(counter_script.RING_DURATION)
	var done: float = station.ring_frame()
	station.tick(counter_script.RING_DURATION)
	_ok(done == 1.0 and station.ring_frame() == 1.0,
		"a full duration completes the ring and the frame clamps at 1")
	_ok(station.bell_pos().distance_to(station.position + Vector3(-0.45, 1.04, 0.0)) < 0.001,
		"bell_pos() is the bell offset in world space")
	station.queue_free()
	_ok(main._counter.bell_pos().distance_to(Vector3(-2.35, 1.04, 2.55)) < 0.001,
		"booted counter's bell world pos is COUNTER_POS + bell offset")

	BrowserSave.clear()
	print("---")
	print("checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)
