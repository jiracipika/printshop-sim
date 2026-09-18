extends SceneTree

## Headless smoke test: main scene boots, sim runs a full job.
## Run: godot --headless -s tests/smoke.gd (from project root)

func _init() -> void:
	# Wait until the root is ready before touching the scene tree.
	root.ready.connect(_run)

func _run() -> void:
	var failures := 0
	var checks := 0

	# Load main scene
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

	# Groups wired
	var sim: Node = root.get_tree().get_first_node_in_group("print_sim")
	var board: Node = root.get_tree().get_first_node_in_group("job_board")
	checks += 1
	if sim == null or board == null:
		printerr("FAIL: print_sim/job_board groups missing")
		_finish(1)
		return
	print("check %d: sim+board groups OK" % checks)

	# Printers exist
	var printers := root.get_tree().get_nodes_in_group("printers")
	checks += 1
	if printers.size() != 2:
		printerr("FAIL: expected 2 printers, got %d" % printers.size())
		failures += 1
	else:
		print("check %d: 2 printers OK" % checks)

	# Job queue
	checks += 1
	if not board.has_available() or board.get_available_count() < 1:
		printerr("FAIL: job board empty at boot")
		failures += 1
	else:
		print("check %d: job board stocked (%d jobs)" % [checks, board.get_available_count()])

	# Drive a full print job with manual ticks
	var job: Dictionary = board.take_next()
	sim.start_job(job.id, job.model, job.layers)
	checks += 1
	if not sim.is_running():
		printerr("FAIL: sim not RUNNING after start_job")
		failures += 1
	else:
		print("check %d: job %s started (%s, %d layers)" % [checks, job.id, job.model, job.layers])

	var steps := 0
	while sim.is_running() and steps < 10000:
		sim.tick(1.0 / 60.0)
		steps += 1
	checks += 1
	if sim.state != PrintSim.State.DONE_OK:
		printerr("FAIL: sim ended in state %s after %d ticks" % [sim.get_state_name(), steps])
		failures += 1
	else:
		print("check %d: print completed OK in %d ticks" % [checks, steps])

	checks += 1
	if sim.material_used_g() <= 0:
		printerr("FAIL: no material consumed")
		failures += 1
	else:
		print("check %d: material consumed %d g" % [checks, sim.material_used_g()])

	checks += 1
	var refilled: bool = board.has_available()
	if not refilled:
		printerr("FAIL: job board did not refill after take")
		failures += 1
	else:
		print("check %d: job board refilled" % checks)

	print("%d checks — %s" % [checks, "ALL PASS" if failures == 0 else "FAILURES: %d" % failures])
	_finish(0 if failures == 0 else 1)

func _finish(code: int) -> void:
	quit(code)
