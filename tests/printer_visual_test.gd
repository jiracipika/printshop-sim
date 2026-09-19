extends SceneTree

## Headless printer visual gate (task 04 visualization). Behavioral, on the
## REAL Main scene. Run: godot --headless --path . -s tests/printer_visual_test.gd
## RED before Printer.gd/PrintVisual.gd/Main.gd edits; GREEN after.

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

func _printer_by_index(main, idx: int) -> Node3D:
	for p in main.get_tree().get_nodes_in_group("printers"):
		if int(p.get_meta("printer_index", -1)) == idx:
			return p
	return null

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

	var printer: Node3D = _printer_by_index(main, 0)
	_ok(printer != null, "printer 0 exists in printers group")
	if printer == null:
		quit(1)
		return

	# --- named children: frame parts, bed, gantry, nozzle ---
	_ok(printer.get_node_or_null("Base") != null, "printer has Base frame part")
	_ok(printer.get_node_or_null("Bed") != null, "printer has Bed")
	_ok(printer.get_node_or_null("Gantry") != null, "printer has Gantry")
	_ok(printer.get_node_or_null("Gantry/Nozzle") != null, "printer has Nozzle")
	_ok(printer.get_node_or_null("Gantry/Nozzle/NozzleBlock") != null,
		"printer has NozzleBlock")
	_ok(printer.get_node_or_null("ZRail") != null, "printer has Z rail")

	# Bed is above printer origin, reachable distance.
	var bed: MeshInstance3D = printer.get_node("Bed")
	_ok(bed.global_position.y > printer.global_position.y,
		"bed sits above printer origin")

	# Collision body still present (player/occlusion contract).
	var body := printer.get_node_or_null("PrinterBody")
	_ok(body != null and body is StaticBody3D and body.collision_layer & 1,
		"printer StaticBody3D on layer 1 kept")

	# --- PrintVisual exists, hidden at IDLE ---
	var visual = printer.get_node_or_null("PrintVisual")
	_ok(visual != null, "PrintVisual node exists under printer")
	if visual == null:
		quit(1)
		return
	_ok(not visual.visible, "PrintVisual hidden at IDLE")
	_ok(visual.visible == false and visual.slice_count_visible() == 0,
		"PrintVisual shows zero slices at zero progress")

	# --- sim at 25%: visible, monotonic growth, progress matches ---
	var sim = main.sim
	sim.start_job("TEST-VIS", "Visual Test Model", 40)
	main._on_print_started()
	# tick to 10/40 layers = 25%
	for i in range(10):
		sim.tick(1.0 / sim.TICK_HZ + 0.001)
	_ok(sim.progress() >= 0.24 and sim.progress() <= 0.26,
		"sim near 25%% after 10 ticks (p=%.2f)" % sim.progress())
	main._update_print_visuals(0.016)
	_ok(visual.visible, "PrintVisual visible while RUNNING")
	_ok(absf(visual.get_progress() - sim.progress()) < 0.05,
		"visual progress matches sim at 25%%")
	var p25: float = visual.get_progress()

	# tick to 20/40 = 50%
	for i in range(10):
		sim.tick(1.0 / sim.TICK_HZ + 0.001)
	main._update_print_visuals(0.016)
	_ok(visual.get_progress() > p25, "visual growth monotonic 25%%->50%%")
	var p50: float = visual.get_progress()

	# tick to 40/40 = 100%, state DONE_OK
	for i in range(20):
		sim.tick(1.0 / sim.TICK_HZ + 0.001)
	_ok(sim.state == PrintSim.State.DONE_OK, "sim DONE_OK at full ticks")
	main._update_print_visuals(0.016)
	_ok(visual.get_progress() >= 0.99, "visual at 100%% in DONE_OK")
	var slices_full: int = visual.slice_count_visible()
	_ok(slices_full == visual.N_BOXES, "all %d slices shown at 100%% (got %d)" % [visual.N_BOXES, slices_full])
	_ok(not visual.is_failed(), "DONE_OK is not marked failed")

	# --- DONE_FAIL differs from DONE_OK ---
	sim.state = PrintSim.State.IDLE
	visual.reset()
	main._update_print_visuals(0.016)
	_ok(not visual.visible, "visual hidden again after reset to IDLE-like state")
	sim.start_job("TEST-FAIL", "Fail Test Model", 20)
	sim.failure_seeded = true
	main._on_print_started()
	for i in range(25):  # past halfway where failure seeds
		sim.tick(1.0 / sim.TICK_HZ + 0.001)
	_ok(sim.state == PrintSim.State.DONE_FAIL, "sim DONE_FAIL with seeded failure")
	main._update_print_visuals(0.016)
	_ok(visual.is_failed(), "DONE_FAIL marks visual failed (differs from DONE_OK)")
	_ok(visual.get_fail_mode() != visual.FailMode.NONE, "fail mode is a distinct flag")

	# --- node count under printer bounded after full print + 3 jobs ---
	visual.reset()
	sim.state = PrintSim.State.IDLE
	main._update_print_visuals(0.016)
	var base_count := _count_under(printer)
	for j in range(3):
		sim.start_job("TEST-J%d" % j, "Model %d" % j, 30)
		main._on_print_started()
		for i in range(30):
			sim.tick(1.0 / sim.TICK_HZ + 0.001)
		main._update_print_visuals(0.016)
		sim.state = PrintSim.State.IDLE
		main._update_print_visuals(0.016)
	var after_count := _count_under(printer)
	_ok(after_count <= 80, "node count under printer <= 80 after full print + 3 jobs (%d -> %d)"
		% [base_count, after_count])
	_ok(after_count == base_count, "no node growth across jobs (%d == %d)" % [base_count, after_count])

	# --- grab occlusion sanity: printer still blocks the ray (smaller now) ---
	_ok(printer.global_position.distance_to(main._player.global_position) > 0.0,
		"printer origin sane for nearest-printer distance")

	print("%d checks — %s" % [checks, "ALL PASS" if failures == 0 else "FAILURES: %d" % failures])
	quit(0 if failures == 0 else 1)

func _count_under(node: Node) -> int:
	var n := 0
	var stack: Array = [node]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		n += 1
		stack.append_array(cur.get_children())
	return n
