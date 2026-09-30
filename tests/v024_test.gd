extends SceneTree

## v0.24.0 — "Studio & street pass": design catalog grows to six shapes and
## the left poster rotates its slogan per week. Run:
## timeout 180 godot --headless --path . -s tests/v024_test.gd

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


func _run() -> void:
	BrowserSave.clear()
	_test_catalog()
	await _test_poster()
	BrowserSave.clear()
	print("---")
	print("checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _test_catalog() -> void:
	_ok(DesignStudio.SHAPES.size() == 6, "catalog holds six shapes")
	var shape_of := {"Phone stand": "stand", "Plant marker": "stake", "Drawer knob": "dome"}
	for name in shape_of:
		var d := DesignStudio.normalize({"name": name})
		_ok(str(d.shape) == shape_of[name], "%s normalizes to '%s'" % [name, shape_of[name]])
	# Mesh classes: stand leans (prism), stake is paper-thin, dome is round.
	_ok(DesignStudio.create_mesh({"name": "Phone stand"}) is PrismMesh,
		"Phone stand builds a prism")
	_ok(DesignStudio.create_mesh({"name": "Drawer knob"}) is SphereMesh,
		"Drawer knob builds a sphere")
	var stake_mesh: Mesh = DesignStudio.create_mesh({"name": "Plant marker"})
	_ok(stake_mesh is BoxMesh and (stake_mesh as BoxMesh).size.z < 0.012,
		"Plant marker is a paper-thin stake")
	# Material order: the stake is the lightest of the three at equal size.
	var base := {"width_mm": 40.0, "depth_mm": 40.0, "height_mm": 40.0,
		"wall_mm": 1.2, "infill_pct": 18.0}
	var grams := {}
	for name in ["Phone stand", "Plant marker", "Drawer knob"]:
		var d := base.duplicate()
		d["name"] = name
		grams[name] = DesignStudio.estimate_grams(d)
	_ok(int(grams["Plant marker"]) < int(grams["Drawer knob"])
		and int(grams["Drawer knob"]) < int(grams["Phone stand"]),
		"gram estimates order stake < knob < stand")
	# Template buttons write their starter dims through the panel path.
	var studio: DesignStudio = load("res://scripts/DesignStudio.gd").new()
	studio._select_template("Phone stand")
	_ok(str(studio._design.name) == "Phone stand"
		and absf(float(studio._design.width_mm) - 70.0) < 0.01,
		"Phone stand template fills its starter dims")
	# Every template's dims must survive normalize (regression: Plant marker
	# shipped width 14, below the 24 mm floor, and renders/printing silently
	# clamped it; Cable ring later shipped height 12 below the 20 mm floor
	# the same way).
	var template_ok := true
	for name in DesignStudio.SHAPES:
		studio._select_template(name)
		var d := DesignStudio.normalize(studio._design)
		if absf(float(d.width_mm) - float(studio._design.width_mm)) > 0.01 \
				or absf(float(d.depth_mm) - float(studio._design.depth_mm)) > 0.01 \
				or absf(float(d.height_mm) - float(studio._design.height_mm)) > 0.01:
			template_ok = false
	_ok(template_ok, "every template's dims survive the normalize clamps")
	studio.free()
	# The prototype pipeline accepts a new design end to end.
	var packed: PackedScene = load("res://scenes/Main.tscn")
	var main = packed.instantiate()
	root.add_child(main)
	await physics_frame
	var part = main._make_prototype_part({"name": "Drawer knob", "filament": "Honey"})
	_ok(part != null and part.name.begins_with("Prototype_Drawer_knob"),
		"prototype part builds for a knob")
	part.queue_free()
	main.queue_free()
	await physics_frame


func _test_poster() -> void:
	var packed: PackedScene = load("res://scenes/Main.tscn")
	var main = packed.instantiate()
	root.add_child(main)
	await physics_frame
	await physics_frame

	var lines: Array = (load("res://scripts/Main.gd") as GDScript).POSTER_LINES
	_ok(main._poster_label != null and lines.has(str(main._poster_label.text)),
		"poster caption is one of the weekly slogans")
	# Determinism: the same week always picks the same line.
	var week1: String = str(main._poster_label.text)
	main._refresh_event()
	_ok(str(main._poster_label.text) == week1, "same week, same slogan")
	# A different week can flip it; whichever line shows is the pinned one.
	main.day_cycle.restore(8, 0.3)
	main._refresh_event()
	var week2: String = str(main._poster_label.text)
	_ok(lines.has(week2), "week 2 shows a slogan (%s)" % week2)
	var flips := false
	for w in range(1, 12):
		main.day_cycle.restore(w * 7, 0.3)
		main._refresh_event()
		if str(main._poster_label.text) != week1:
			flips = true
	_ok(flips, "the slogan actually rotates across weeks")
	main.queue_free()
	await physics_frame
