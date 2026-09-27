extends SceneTree

## Integration gate for the design-computer prototype loop.
## Run: godot --headless --path . --script tests/design_computer_test.gd

var failures := 0
var checks := 0

func _init() -> void:
	root.ready.connect(_run)

func _ok(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("check %d: %s OK" % [checks, label])
	else:
		printerr("FAIL: %s" % label)
		failures += 1

func _run() -> void:
	var default_design := DesignStudio.defaults()
	var small := DesignStudio.normalize({"width_mm": -500.0, "height_mm": 500.0,
		"name": "unknown", "material": "mystery"})
	_ok(small.width_mm == 24.0 and small.height_mm == 160.0,
		"designer clamps invalid dimensions to the printable range")
	_ok(small.name == default_design.name and small.material == "PLA",
		"invalid template and material return to beginner-safe defaults")
	_ok(DesignStudio.estimate_grams({"width_mm": 100.0}) > DesignStudio.estimate_grams(default_design),
		"larger models estimate more filament")
	_ok(DesignStudio.estimate_seconds({"layer_mm": 0.12}) > DesignStudio.estimate_seconds(default_design),
		"finer layers estimate longer print time")
	var planter_mesh := DesignStudio.create_mesh(default_design) as ArrayMesh
	_ok(planter_mesh != null and planter_mesh.get_surface_count() == 1,
		"planter template creates a hollow, wall-thickness-based model")
	_ok(DesignStudio.create_mesh({"name": "Cable ring"}) is TorusMesh,
		"cable-ring template creates a ring model")
	_ok(DesignStudio.create_mesh({"name": "Storage block"}) is BoxMesh,
		"storage template creates a box model")

	var packed: PackedScene = load("res://scenes/Main.tscn")
	_ok(packed != null, "main scene loads")
	if packed == null:
		quit(1)
		return
	var main = packed.instantiate()
	root.add_child(main)
	await process_frame
	var target := main.get_node_or_null("DesignComputer/DesignComputerTarget")
	_ok(target is StaticBody3D and target.has_meta("design_computer"),
		"computer is a real world-space interaction target")
	main._open_design_studio()
	_ok(main.design_studio.visible and main.paused,
		"using the computer opens the designer and pauses shop time")
	main._route_escape()
	_ok(not main.design_studio.visible and main.main_menu.visible,
		"Escape returns from the designer to the shop menu")

	main._open_design_studio()
	var design := {"name": "Storage block", "shape": "box", "width_mm": 60.0,
		"depth_mm": 50.0, "height_mm": 40.0, "layer_mm": 0.2,
		"wall_mm": 1.6, "infill_pct": 22.0, "material": "PETG", "filament": "Sage"}
	var balance_before: int = main.ledger.balance()
	main.design_studio._design = design.duplicate(true)
	main.design_studio._save_and_print() # exercise the real button path + signal
	var machine: Dictionary = main._machine(0)
	var sim: PrintSim = machine.sim
	_ok(sim.is_running() and str(sim.job_id).begins_with("PROTO-"),
		"test print starts through the normal printer simulation")
	_ok(machine.prototype.name == "Storage block" and main.main_menu.visible,
		"chosen blueprint is assigned to the printer and the shop pauses safely")
	_ok(main.ledger.balance() < balance_before,
		"prototype filament is charged before printing")
	_ok(main.design_studio.visible == false,
		"successful send closes the designer")
	_ok(FileAccess.file_exists(DesignStudio.SAVE_PATH),
		"test print stores the blueprint for the next visit")
	for i in range(sim.layers_total + 2):
		sim.tick(1.0 / PrintSim.TICK_HZ + 0.001)
	_ok(sim.state == PrintSim.State.DONE_OK,
		"prototype print completes without a surprise risk roll")
	_ok(main._collect_on(0), "completed prototype can be collected from the printer")
	_ok(main.held is Grabbable and main.held.has_meta("prototype"),
		"collected item is a physical grabbable prototype")
	_ok(sim.state == PrintSim.State.IDLE and machine.prototype.is_empty(),
		"collection resets the printer for the next design")

	print("%d checks — %s" % [checks, "ALL PASS" if failures == 0 else "FAILURES: %d" % failures])
	quit(0 if failures == 0 else 1)
