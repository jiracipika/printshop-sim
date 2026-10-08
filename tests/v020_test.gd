extends SceneTree

## v0.20.0 — "Hardening & release polish": quality presets (Low/Standard/
## High), draw-call audit, portrait HUD validation, touch target sizes, and
## a full delivery loop at Low quality. Run:
## timeout 180 godot --headless --path . -s tests/v020_test.gd

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
	await _test_presets_and_hardening()
	BrowserSave.clear()
	print("---")
	print("checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _test_presets_and_hardening() -> void:
	var packed: PackedScene = load("res://scenes/Main.tscn")
	var main = packed.instantiate()
	root.add_child(main)
	await physics_frame
	await physics_frame

	# --- presets drive shadows + glow, checkbox stays in sync ----------------
	_ok(str(main.settings.quality_preset) == "Standard"
		and main._sun.shadow_enabled and main._env.glow_enabled,
		"default preset is Standard")
	main.apply_setting("quality_preset", "Low", false)
	_ok(not main._sun.shadow_enabled and not main._env.glow_enabled
		and main.settings.shadows == false,
		"Low kills shadows and glow, checkbox syncs off")
	# Season overlays follow the quality gate (force humid first).
	main.season = Events._season_by_id("humid")
	main._apply_quality()
	_ok(not main._rain.visible, "Low hides the rain overlay")
	main.apply_setting("quality_preset", "Standard", false)
	_ok(main._sun.shadow_enabled and main._env.glow_enabled
		and absf(main._env.glow_intensity - 0.5) < 0.01 and main._rain.visible,
		"Standard restores shadows, glow 0.5, overlays")
	main.apply_setting("quality_preset", "High", false)
	_ok(main._sun.shadow_enabled and absf(main._env.glow_intensity - 0.8) < 0.01,
		"High boosts glow to 0.8")
	# The checkbox path maps back into the preset ladder.
	main.apply_setting("shadows", false, false)
	_ok(str(main.settings.quality_preset) == "Low", "unchecking shadows picks Low")
	main.apply_setting("shadows", true, false)
	_ok(str(main.settings.quality_preset) == "Standard", "checking shadows picks Standard")

	# Settings panel reflects the preset; validator accepts it in saves.
	main.main_menu.show_settings(main.settings)
	var opt: OptionButton = main.main_menu._settings_panel \
		.get_node("Sheet/SheetScroll/SheetBox/QualityRow/QualityOption")
	_ok(opt.selected == 1, "settings dropdown shows the current preset")
	main.apply_setting("quality_preset", "High", false)
	main._save_game()
	var saved: Dictionary = load("res://scripts/BrowserSave.gd").load_payload()
	_ok(str(saved.get("settings", {}).get("quality_preset", "")) == "High",
		"preset persists in the save payload")

	# --- draw-call audit -------------------------------------------------------
	var total := 0
	var visible := 0
	var stack := [main]
	while stack.size() > 0:
		var n = stack.pop_back()
		if n is MeshInstance3D:
			total += 1
			if n.visible and n.is_visible_in_tree():
				visible += 1
		for c in n.get_children():
			stack.append(c)
	_ok(visible <= 180, "visible mesh budget holds (%d/180)" % visible)
	_ok(total <= 400, "total mesh budget holds (%d/400)" % total)

	# --- touch targets stay >= 48 px at phone size -----------------------------
	var touch = load("res://scripts/TouchControls.gd").new()
	var layout: Dictionary = touch.layout_rects(Vector2(390, 844), 0.0, 0.0, 0.0, 0.0)
	var interact: Rect2 = layout["interact"]
	var pause: Rect2 = layout["pause"]
	_ok(interact.size.x >= 48.0 and interact.size.y >= 48.0
		and pause.size.x >= 48.0 and pause.size.y >= 48.0,
		"touch hit regions stay >= 48 px at 390x844 (%.0fx%.0f, %.0fx%.0f)" % [
			interact.size.x, interact.size.y, pause.size.x, pause.size.y])
	touch.free()

	# --- portrait HUD: card wraps inside 390 px, back to compact on wide ------
	main._update_hud()
	var card: PanelContainer = main._status.get_parent()
	root.size = Vector2i(390, 844)
	main._apply_hud_layout()
	await physics_frame
	await physics_frame
	var card_right: float = card.position.x + card.size.x
	_ok(main._status.autowrap_mode == TextServer.AUTOWRAP_WORD_SMART,
		"narrow viewport wraps the status label")
	_ok(card.position.x >= 0.0 and card_right <= 391.0,
		"status card stays inside 390 px (%.0f..%.0f)" % [card.position.x, card_right])
	var prompt: Label = main._prompt
	_ok(prompt.position.x >= 0.0 and prompt.position.x + prompt.size.x <= 391.0,
		"prompt line stays inside 390 px")
	root.size = Vector2i(1280, 720)
	main._apply_hud_layout()
	await physics_frame
	_ok(main._status.autowrap_mode == TextServer.AUTOWRAP_OFF
		and card.anchor_right == 0.0 and card.position.x == 10.0,
		"wide viewport restores the compact top-left card")

	# --- full delivery loop at Low quality -------------------------------------
	BrowserSave.clear()
	var main2 = packed.instantiate()
	root.add_child(main2)
	await physics_frame
	await physics_frame
	main2.apply_setting("quality_preset", "Low", false)
	main2.paused = false
	main2.captured = true
	main2._machine(0)["filament_g"] = 50000
	main2.job_board._queue.clear()
	var job: Contract = load("res://scripts/JobBoard.gd")._contract_from({
		"id": "G-LOW", "client": "Low Quality Co.", "model_name": "Budget part",
		"payout_cents": 5000, "material_cost_cents": 300, "difficulty": 1,
		"risk_flags": [], "layers": 40, "deadline_days": 6, "rush": false,
		"competing": false, "offered_day": 1, "color": "", "parts_total": 1,
	})
	main2.job_board._queue.append(job)
	main2._player.global_position = Vector3(-1.8, 0.3, -1.0)
	main2._try_interact()
	_ok(main2._machine(0).get("contract") != null, "Low: job accepted")
	var sim: PrintSim = main2._machine(0).get("sim")
	main2._machine(0)["orient"] = 0
	main2._machine(0)["orient_pending"] = true
	main2._prep_on(0)
	sim._failure_tick = -1
	sim.failure_seeded = false
	while sim.is_running():
		sim.tick(1.0)
	main2._try_interact()  # collect
	main2._player.global_position = Vector3(2.0, 0.3, 0.9)
	main2._try_interact()  # pack + deliver
	_ok(main2._machine(0).get("contract") == null and main2.ledger.balance() > 2500,
		"Low: full loop delivers and pays")
	_ok(not main2._env.glow_enabled and not main2._sun.shadow_enabled,
		"Low quality held through the whole loop")
	main2.queue_free()
	await physics_frame
	main.queue_free()
	await physics_frame
