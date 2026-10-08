extends SceneTree

## v0.50.0 — "Shop codes": the save exports to a portable base64/JSON code
## and a pasted code imports over the active slot after validation. Run:
## godot --headless --path . -s tests/v050_test.gd

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
	var packed: PackedScene = load("res://scenes/Main.tscn")
	var main = packed.instantiate()
	root.add_child(main)
	for i in range(6):
		await physics_frame
	main.paused = false
	main.captured = true

	# A fresh shop exports a decodable code.
	var code: String = main.export_shop_code()
	_ok(code.length() > 0, "a fresh shop exports a non-empty code")
	var decoded: Variant = JSON.parse_string(Marshalls.base64_to_utf8(code))
	_ok(decoded is Dictionary and int(decoded.get("version", 0)) == 1,
		"the code decodes to a version-1 payload")
	_ok(int(decoded.get("day", 0)) == main.day_cycle.day,
		"the payload carries the shop's day")

	# parse_shop_code round-trips its own export.
	_ok(not main.parse_shop_code(code).is_empty(),
		"parse_shop_code accepts its own export")

	# Distinctive state rides the code end to end.
	main.reputation = 4.25
	main.stats["delivered"] = 9
	main.client_orders["Kiki's Cafe"] = 3
	main.apply_setting("haptics_strength", 40)
	main.settings["calm_mode"] = true
	var code2: String = main.export_shop_code()
	var p2: Dictionary = main.parse_shop_code(code2)
	_ok(not p2.is_empty(), "the mutated shop still exports a valid code")
	_ok(absf(float(p2.get("reputation", 0.0)) - 4.25) < 0.001,
		"the code carries reputation")
	_ok(int(p2.get("stats", {}).get("delivered", 0)) == 9,
		"the code carries lifetime stats")
	_ok(int(p2.get("client_orders", {}).get("Kiki's Cafe", 0)) == 3,
		"the code carries client memory")
	_ok(int(p2.get("settings", {}).get("haptics_strength", 0)) == 40,
		"the code carries settings")

	# Rejection paths: every malformed input lands in {}.
	_ok(main.parse_shop_code("").is_empty(), "an empty code is rejected")
	_ok(main.parse_shop_code("not base64!!!").is_empty(),
		"non-base64 text is rejected")
	_ok(main.parse_shop_code(Marshalls.utf8_to_base64("not json at all")).is_empty(),
		"base64 of non-JSON is rejected")
	_ok(main.parse_shop_code(Marshalls.utf8_to_base64("[]")).is_empty(),
		"a JSON array is rejected")
	_ok(main.parse_shop_code(Marshalls.utf8_to_base64(
		JSON.stringify({"hello": "world"}))).is_empty(),
		"a dict without a valid save shape is rejected")

	# A failed import never touches the save file.
	main._save_game()
	var before: Dictionary = BrowserSave.load_payload()
	var err: String = main.apply_shop_code("garbage")
	_ok(err != "", "applying a garbage code reports an error")
	_ok(BrowserSave.load_payload() == before,
		"a failed import leaves the save file untouched")

	# A valid import rewrites the active slot with the code's shop.
	err = main.apply_shop_code(code2)
	_ok(err == "", "applying a valid code succeeds")
	var imported: Dictionary = BrowserSave.load_payload()
	_ok(not imported.is_empty() and int(imported.get("stats", {}).get("delivered", 0)) == 9,
		"the imported file carries the code's shop")

	# The imported file boots into the imported shop (what the reload lands in).
	main.queue_free()
	await physics_frame
	var main2 = packed.instantiate()
	root.add_child(main2)
	await physics_frame
	_ok(absf(main2.reputation - 4.25) < 0.001,
		"an imported code boots with the code's reputation")
	_ok(int(main2.stats.get("delivered", 0)) == 9,
		"an imported code boots with the code's stats")
	_ok(int(main2.settings.get("haptics_strength", 0)) == 40,
		"an imported code boots with the code's settings")
	_ok(bool(main2.settings.get("calm_mode", false)),
		"an imported code boots with the code's calm mode")

	# Settings sheet: the code widgets exist and export fills the field.
	main2.main_menu.open_menu()
	main2.main_menu.show_settings(main2.settings)
	await physics_frame
	var field: TextEdit = main2.main_menu._settings_panel \
		.get_node("Sheet/SheetScroll/SheetBox/CodeField")
	var export_btn: Button = main2.main_menu._settings_panel \
		.get_node("Sheet/SheetScroll/SheetBox/CodeRow/ExportCodeButton")
	var import_btn: Button = main2.main_menu._settings_panel \
		.get_node("Sheet/SheetScroll/SheetBox/CodeRow/ImportCodeButton")
	_ok(field != null and export_btn != null and import_btn != null,
		"the code field and both buttons exist on the settings sheet")
	main2.main_menu.set_shop_code("handy test code")
	_ok(field.text == "handy test code", "set_shop_code fills the field")
	export_btn.pressed.emit()
	await physics_frame
	_ok(field.text == main2.export_shop_code(),
		"the export button fills the field with the current shop's code")

	# Import flow: first press validates and arms; a bad second press disarms
	# without touching anything; the shared disarm (panel switch) also resets.
	field.text = main2.export_shop_code()
	import_btn.pressed.emit()
	await physics_frame
	_ok(main2._import_armed, "a valid first press arms the import")
	_ok(import_btn.text.contains("again"), "the armed button asks for a confirm")
	var guard: Dictionary = BrowserSave.load_payload()
	field.text = "garbage"
	import_btn.pressed.emit()
	await physics_frame
	_ok(not main2._import_armed, "a garbage second press disarms")
	_ok(not import_btn.text.contains("again"), "the disarmed button resets its label")
	_ok(BrowserSave.load_payload() == guard,
		"the disarmed import never touched the save file")
	field.text = main2.export_shop_code()
	import_btn.pressed.emit()
	await physics_frame
	_ok(main2._import_armed, "the import arms again after a disarm")
	main2.main_menu._show_panel(main2.main_menu._stats_panel)
	await physics_frame
	_ok(not main2._import_armed, "switching panels cancels the armed import")
	_ok(not import_btn.text.contains("again"),
		"the panel switch reset the import button label")

	main2.queue_free()
	await physics_frame
	BrowserSave.clear()
	print("---")
	print("checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)
