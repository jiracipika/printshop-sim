extends SceneTree

## Headless debug-panel gate (menus slice).
## Run: godot --headless --path . -s tests/debug_panel_test.gd
## RED before DebugPanel.gd / Main.gd panel wiring; GREEN after.
## Actions are driven through the panel's real keyboard handler (feed F3 and
## the [1]-[6] keys); headless builds are debug builds, so DEBUG_PANEL is on.

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

func _feed_key(node, keycode: Key) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode
	ev.pressed = true
	node._unhandled_input(ev)

func _run() -> void:
	BrowserSave.save_path = "user://debug_panel_test_save.json"
	BrowserSave.clear()

	var packed: PackedScene = load("res://scenes/Main.tscn")
	_ok(packed != null, "Main.tscn loads")
	if packed == null:
		quit(1)
		return
	var main = packed.instantiate()
	root.add_child(main)
	await process_frame

	var panel = main.debug_panel
	_ok(panel != null, "Main exposes debug_panel")
	if panel == null:
		quit(1)
		return

	# 1. Hidden at boot even in a debug build; toggled by F3.
	_ok(panel.visible == false, "panel hidden at boot")
	_ok(panel.DEBUG_PANEL == true, "headless run is a debug build (DEBUG_PANEL on)")
	_feed_key(panel, KEY_F3)
	_ok(panel.visible == true, "F3 shows the panel")
	_feed_key(panel, KEY_F3)
	_ok(panel.visible == false, "F3 hides the panel")

	# Hidden panel must not swallow gameplay input: a captured mouse click
	# still reaches Main (gameplay is active here only if we capture first).
	_feed_key(main, KEY_ESCAPE)  # open menu
	main.main_menu.get_node("Root/Layout/Buttons/Play").pressed.emit()
	_feed_click_capture(main)
	_ok(main.get_mouse_locked(), "gameplay captured for input-pass-through check")

	# 2. Labels update after a real sim tick.
	main.sim.start_job("DBG-1", "Debug Cube", 12)
	main.sim.tick(1.0 / 10.0)
	_feed_key(panel, KEY_F3)  # show
	await process_frame  # let _process refresh labels before asserting
	_ok(str(panel.label_text("job")).contains("DBG-1"), "job label shows active job id")
	_ok(str(panel.label_text("job")).contains("RUNNING"), "job label shows state RUNNING")
	_ok(str(panel.label_text("balance")).contains("$"), "balance label rendered")
	_ok(str(panel.label_text("contract")).contains("contract:"),
		"contract state label rendered")
	_ok(str(panel.label_text("orientation")).contains("upright"),
		"orientation label shows orientation in use")
	_ok(str(panel.label_text("risk")).contains("support") and
		str(panel.label_text("risk")).contains("adhesion") and
		str(panel.label_text("risk")).contains("stability"),
		"risk label lists support/adhesion/stability")
	_ok(str(panel.label_text("material")).contains("g"), "material label shows grams")
	_ok(str(panel.label_text("esttime")).contains("s"), "est time label shows seconds")
	_ok(str(panel.label_text("save")).contains("save") or str(panel.label_text("save")).contains("Save"),
		"save status label rendered")
	# Source checkouts may have no export stamp; the builder injects a SHA.
	_ok(str(panel.label_text("version")) == "DEBUG — %s" % Version.label(),
		"version label shows the current source/export identity")
	_ok(panel.label_text("pack") != "", "last-pack label exists")

	# 3. Action [3] completes a running print.
	_ok(main.sim.is_running(), "print running before skip")
	_feed_key(panel, KEY_3)
	_ok(not main.sim.is_running()
		and main.sim.state in [PrintSim.State.DONE_OK, PrintSim.State.DONE_FAIL],
		"action [3] ticks sim to completion")

	# 4. Action [4] credits exactly 1000 cents per press.
	var b0: int = main.ledger.balance()
	_feed_key(panel, KEY_4)
	_ok(main.ledger.balance() == b0 + 1000, "action [4] credits exactly 1000 cents")
	_feed_key(panel, KEY_4)
	_ok(main.ledger.balance() == b0 + 2000, "second press credits once more (no dedup bug)")
	var log0: int = panel.action_log().size()
	_ok(log0 >= 3, "each action logged a line to the panel")

	# 5. Action [5] clears the save file (only if one exists).
	main._save_game()
	_ok(BrowserSave.exists(), "save file exists before clear")
	_feed_key(panel, KEY_5)
	_ok(BrowserSave.exists() == false, "action [5] cleared the save file")

	# 6. Action [2] seeds a failure, action [1] starts the highest-risk print.
	_feed_key(panel, KEY_2)
	_ok(main.sim.failure_seeded == true, "action [2] sets sim.failure_seeded")
	var jobs_before: int = main.job_board.get_available_count()
	_feed_key(panel, KEY_1)
	_ok(main.sim.is_running(), "action [1] starts a test print")
	_ok(main.active_contract != null, "action [1] drives the real accept path")
	_ok(jobs_before > 0, "job board was stocked before spawn")
	# panel skipped print time already at [1]? no — finish it cleanly for state
	_feed_key(panel, KEY_3)
	_ok(not main.sim.is_running(), "cleanup skip finishes spawned print")

	# 7. Panel never blocks gameplay input when hidden.
	_feed_key(panel, KEY_F3)  # hide
	_ok(panel.visible == false, "panel hidden before pass-through check")
	_feed_key(main, KEY_ESCAPE)
	_ok(main.main_menu.visible, "main still receives input while panel hidden")

	print("%d checks — %s" % [checks, "ALL PASS" if failures == 0 else "FAILURES: %d" % failures])
	quit(0 if failures == 0 else 1)

func _feed_click_capture(main) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	main._unhandled_input(ev)
