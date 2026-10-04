extends SceneTree

var checks := 0
var failures := 0
const LIB_PATH := "user://test_studio_library.json"

func _init() -> void:
	root.ready.connect(_run)

func _ok(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + label)
	else:
		print("ok: " + label)

func _run() -> void:
	DirAccess.remove_absolute(LIB_PATH)
	var library := BlueprintLibrary.new(LIB_PATH)
	var design := DesignStudio.defaults()
	_ok(library.save("Desk gift", design), "save a named blueprint")
	design.width_mm = 100.0
	_ok(library.entries()[0].design.width_mm == 54.0, "stored design is a snapshot")
	_ok(library.save("DESK GIFT", design) and library.entries().size() == 1, "same name updates one slot")
	var restored := BlueprintLibrary.new(LIB_PATH)
	_ok(restored.read() and restored.entries()[0].design.width_mm == 100.0, "reload preserves design")
	for i in range(11):
		_ok(restored.save("Design %d" % i, design), "fill library slot %d" % i)
	_ok(not restored.save("Overflow", design), "capacity does not discard a saved design")
	_ok(restored.remove(0) and restored.entries().size() == 11, "delete frees one slot")
	var file := FileAccess.open(LIB_PATH, FileAccess.WRITE)
	file.store_string("{broken")
	file.close()
	_ok(not restored.read() and restored.entries().size() == 11, "corrupt data preserves in-memory library")
	var blocked := BlueprintLibrary.new("user://missing_folder/blueprints.json")
	_ok(not blocked.save("Cannot write", design) and blocked.entries().is_empty(), "failed write rolls back")
	DirAccess.remove_absolute(LIB_PATH)
	var studio := DesignStudio.new()
	root.add_child(studio)
	await process_frame
	studio._select_profile("Detail")
	_ok(studio.current_design().layer_mm == 0.12 and studio.current_design().width_mm == 54.0, "profile applies without changing size")
	studio._turn_preview(PI / 6.0)
	_ok(not studio._auto_rotate and not studio._spin_button.button_pressed, "manual turn stops automatic rotation")
	var status: Array[String] = ["P1 · Ready · 120g loaded"]
	studio.set_printer_status(status)
	_ok(studio._printer_status.text.contains("120g"), "computer displays loaded printer filament")
	_ok(DesignStudio.design_guidance({"height_mm": 160.0, "width_mm": 24.0, "depth_mm": 24.0}).contains("Tall"), "tall designs receive guidance")
	var sim := PrintSim.new()
	sim.failure_threshold = 0.0
	sim.speed_multiplier = 2.0
	sim.start_job("ETA", "test", 100)
	_ok(is_equal_approx(sim.remaining_real_time_s(), 5.0), "ETA includes printer speed")
	sim.tick(0.025)
	_ok(is_equal_approx(sim.remaining_real_time_s(), 4.975), "ETA includes partial tick")
	sim.tick(10.0)
	_ok(sim.remaining_real_time_s() == 0.0, "completed job has zero ETA")
	sim.free()
	studio.queue_free()
	await process_frame
	print("%d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
