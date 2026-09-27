extends SceneTree

## v0.10.0 — art pass: detailed textures, baseboards, pegboard, cables,
## packing props, printer LCD. Run:
##   timeout 90 godot --headless --path . -s tests/art_pass_test.gd

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
	_test_textures()
	await _test_scene()
	_finish(1 if failures > 0 else 0)


func _test_textures() -> void:
	# Detailed variants are 512 and cached separately.
	var floor512: ImageTexture = ShopArt.floor_tiles(Color("#AD5F3D"), 4, 512)
	var img: Image = floor512.get_image()
	_ok(img.get_width() == 512 and img.get_height() == 512, "floor detail texture is 512x512")
	var wall512: ImageTexture = ShopArt.plaster(Color("#738771"), 512)
	_ok(wall512.get_image().get_width() == 512, "wall detail texture is 512x512")
	var wood512: ImageTexture = ShopArt.wood(Color("#C3A076"), 5, 512)
	_ok(wood512.get_image().get_width() == 512, "wood detail texture is 512x512")
	_ok(ShopArt.wood(Color("#C3A076"), 5, 512) == wood512, "detail variants are cached")
	_ok(ShopArt.pegboard(Color("#8A7A5E")) != null, "pegboard texture builds")
	_ok(ShopArt.bed_grid(Color("#C3A076")) != null, "bed grid texture builds")
	_ok(ShopArt.calendar() != null, "calendar texture builds")


func _test_scene() -> void:
	var packed: PackedScene = load("res://scenes/Main.tscn")
	var main = packed.instantiate()
	root.add_child(main)
	await physics_frame
	await physics_frame

	var props: Array = main.get_tree().get_nodes_in_group("props")
	_ok(props.size() >= 30, "prop population grew with the art pass (got %d)" % props.size())

	# Baseboards: four dark strips near the wall feet.
	var baseboards := 0
	for p in props:
		if p is MeshInstance3D and p.mesh is BoxMesh \
				and absf((p.mesh as BoxMesh).size.y - 0.12) < 0.001 \
				and (p.position.y - 0.06) < 0.001:
			baseboards += 1
	_ok(baseboards >= 4, "baseboard strips present (%d)" % baseboards)

	# Pegboard + tools + calendar on the walls.
	var found_peg := false
	var found_cal := false
	var tools := 0
	for p in props:
		if p is MeshInstance3D and p.mesh is QuadMesh and p.position.z < -2.7:
			var mat: StandardMaterial3D = p.material_override
			if mat != null and mat.albedo_texture == ShopArt.pegboard(Color("#8A7A5E")):
				found_peg = true
			elif mat != null and mat.albedo_texture == ShopArt.calendar():
				found_cal = true
		if p is MeshInstance3D and p.mesh is BoxMesh and p.material_override != null \
				and (p.material_override as StandardMaterial3D).metallic > 0.3 \
				and p.position.z < -2.7 and p.position.y > 1.8:
			tools += 1
	_ok(found_peg, "pegboard hangs on the back wall")
	_ok(found_cal, "calendar hangs on the wall")
	_ok(tools >= 3, "tools hang on the pegboard (%d)" % tools)

	# Cables + power strip: dark low boxes on the floor.
	var cables := 0
	for p in props:
		if p is MeshInstance3D and p.mesh is BoxMesh and p.position.y <= 0.03 \
				and (p.position.z < -1.0):
			cables += 1
	_ok(cables >= 1, "floor cables present")

	# Printer: bed grid + LCD text updates with state.
	var p1: Node3D = main._printers[0]
	_ok(p1.get("set_status") != null, "printer exposes set_status")
	p1.set_status("L10/40 25%")
	_ok(p1._screen_label.text == "L10/40 25%", "LCD text updates")

	# Drive a real print and confirm the LCD mirrors progress.
	ledger_setup(main)
	main.paused = false
	main.captured = true
	main.touch_controls.force_enabled = true
	main.touch_controls.set_motion_enabled(true)
	main._machine(0)["filament_g"] = 5000
	main._player.global_position = Vector3(-1.8, 0.3, -1.0)
	main._try_interact()
	for i in range(3):
		main._machine(0)["orient"] = (int(main._machine(0)["orient"]) + 1) % 3
		main._machine(0)["orient_pending"] = true
	main._prep_on(0)
	var s0: PrintSim = main._machine(0).get("sim")
	s0.layers_done = maxi(s0.layers_total / 4, 1)
	main._update_print_visuals(0.016)
	var lcd: String = p1._screen_label.text
	_ok("%" in lcd, "LCD shows live progress (%s)" % lcd)
	main.queue_free()
	await physics_frame
	BrowserSave.clear()

func ledger_setup(main) -> void:
	main.ledger.credit(30000, "test funds")


func _finish(code: int) -> void:
	print("---")
	print("checks=%d failures=%d" % [checks, failures])
	quit(code)
