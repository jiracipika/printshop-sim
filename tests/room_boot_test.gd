extends SceneTree

## Headless room boot gate (task 01).
## Run: godot --headless --path . -s tests/room_boot_test.gd
## RED before Main.gd/Main.tscn edits; GREEN after room build.

func _init() -> void:
	root.ready.connect(_run)

func _run() -> void:
	var failures := 0
	var checks := 0

	# 1. Scene loads and instantiates.
	var packed: PackedScene = load("res://scenes/Main.tscn")
	checks += 1
	if packed == null:
		printerr("FAIL: Main.tscn failed to load")
		_finish(1)
		return
	var main = packed.instantiate()
	checks += 1
	if main == null:
		printerr("FAIL: Main.tscn failed to instantiate")
		_finish(1)
		return
	root.add_child(main)
	print("check 1-2: Main.tscn loads and instantiates OK")

	# 2. Player exists, spawned above the floor surface (y > 0).
	var player: Node = root.get_tree().get_first_node_in_group("player")
	checks += 1
	if player == null or not (player is CharacterBody3D):
		printerr("FAIL: player CharacterBody3D missing")
		failures += 1
	else:
		print("check %d: player CharacterBody3D OK at y=%.2f" % [checks, player.global_position.y])

	checks += 1
	if player == null or player.global_position.y <= 0.0:
		printerr("FAIL: player spawn not above floor (y<=0)")
		failures += 1
	else:
		print("check %d: player spawn above floor OK" % checks)

	# 3. Floor collision body exists on layer 1 (world).
	checks += 1
	var floor_body := _find_body(main, Vector3(0, -0.1, 0), 1)
	if floor_body == null:
		printerr("FAIL: floor StaticBody3D collision missing")
		failures += 1
	else:
		print("check %d: floor StaticBody3D OK" % checks)

	# 4. At least 4 wall collision bodies surround the room.
	var wall_bodies: Array = _collect_walls(main)
	checks += 1
	if wall_bodies.size() < 4:
		printerr("FAIL: expected >=4 wall collision bodies, got %d" % wall_bodies.size())
		failures += 1
	else:
		print("check %d: wall collision bodies OK (%d)" % [checks, wall_bodies.size()])

	# 5. Workbench exists (group "bench", with StaticBody3D collision).
	checks += 1
	var bench: Node = root.get_tree().get_first_node_in_group("bench")
	if bench == null:
		printerr("FAIL: workbench missing")
		failures += 1
	else:
		var bench_body := _find_descendant(bench, "StaticBody3D")
		if bench_body == null:
			printerr("FAIL: bench has no StaticBody3D")
			failures += 1
		else:
			print("check %d: workbench with collision OK" % checks)

	# 6. At least one printer exists with collision.
	checks += 1
	var printers := root.get_tree().get_nodes_in_group("printers")
	var printer_ok := false
	for p in printers:
		if _find_descendant(p, "StaticBody3D") != null:
			printer_ok = true
			break
	if not printer_ok:
		printerr("FAIL: no printer with StaticBody3D collision")
		failures += 1
	else:
		print("check %d: printer with collision OK (%d printers)" % [checks, printers.size()])

	# 7. Palette materials match the sage/honey/dark-steel spec.
	checks += 1
	var ok_palette := true
	var world = main.get("world")
	if world == null or not (world is Dictionary) or world.is_empty():
		ok_palette = false
	else:
		for pair in [["sage", Color("#738771")], ["honey", Color("#C3A076")], ["steel", Color("#202B2B")], ["terracotta", Color("#DA623A")]]:
			var mat: StandardMaterial3D = world.get(pair[0])
			if mat == null or not mat is StandardMaterial3D or mat.albedo_color != pair[1]:
				ok_palette = false
				printerr("FAIL: palette material '%s' missing or wrong color" % pair[0])
	if ok_palette:
		print("check %d: palette materials sage/honey/steel/terracotta OK" % checks)

	print("%d checks — %s" % [checks, "ALL PASS" if failures == 0 else "FAILURES: %d" % failures])
	_finish(0 if failures == 0 else 1)

func _collect_walls(main: Node) -> Array:
	var walls: Array = []
	for body in _all_bodies(main):
		if body.has_meta("wall"):
			walls.append(body)
	return walls

func _all_bodies(main: Node) -> Array:
	var found: Array = []
	var stack: Array = [main]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is StaticBody3D:
			found.append(n)
		stack.append_array(n.get_children())
	return found

func _find_body(main: Node, pos: Vector3, layer: int) -> StaticBody3D:
	for b in _all_bodies(main):
		if b is StaticBody3D and b.collision_layer & layer and b.global_position.distance_to(pos) < 0.3:
			return b
	return null

func _find_descendant(node: Node, klass: String) -> Node:
	var stack: Array = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n.get_class() == klass:
			return n
		stack.append_array(n.get_children())
	return null

func _finish(code: int) -> void:
	quit(code)
