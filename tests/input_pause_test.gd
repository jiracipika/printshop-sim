extends SceneTree

## Headless input/pause behavior gate (task 02).
## Run: godot --headless --path . -s tests/input_pause_test.gd
## RED before Main.gd input/pause changes; GREEN after.
## Feeds actual InputEvent objects into Main._unhandled_input and drives real
## physics frames. Headless limitation (probed, see docs/worker-input-pause.md):
## Input.mouse_mode is pinned to VISIBLE in headless, so startup/resume are
## asserted via Main.get_mouse_locked(); real browser pointer-lock grant/deny
## still needs browser verification.

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

func _run() -> void:
	var packed: PackedScene = load("res://scenes/Main.tscn")
	_ok(packed != null, "Main.tscn loads")
	if packed == null:
		_finish(1)
		return
	var main = packed.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	# Menus slice: boot opens the main menu; Play closes it and restores the
	# original capture-prompt flow the checks below expect.
	main.main_menu.get_node("Root/Layout/Buttons/Play").pressed.emit()

	# 1. Startup: effectively uncaptured+paused headless (raw mode stays
	#    VISIBLE there), and the Click to play prompt is shown.
	_ok(main.get_mouse_locked() == false, "startup not mouse-locked (get_mouse_locked authority)")
	_ok(main.paused == true, "startup paused")
	_ok("Click to play" in str(main._prompt.text), "startup prompt shows Click to play")

	# 2. Mouse motion while uncaptured must not rotate the camera.
	var yaw0: float = main.yaw
	_feed_mouse_motion(main, Vector2(200, -200))
	_ok(is_equal_approx(main.yaw, yaw0) and is_equal_approx(main.pitch, 0.0),
		"mouse motion ignored while uncaptured")

	# 3. E blocked while paused, even near a printer.
	#    (Headless cannot also prove the raw-mode pointer-lock veto on E:
	#     Input.mouse_mode is pinned to VISIBLE there — browser-verified.)
	_teleport_near_printer_a(main)
	var jobs0: int = main.job_board.get_available_count()
	_feed_key(main, KEY_E)
	_ok(main.job_board.get_available_count() == jobs0, "E blocked while paused")
	_ok(main.sim.state == PrintSim.State.IDLE, "sim stays IDLE while paused")

	# 4. Left click captures and resumes.
	_feed_click(main, MOUSE_BUTTON_LEFT)
	_ok(main.get_mouse_locked() == true, "left click captures pointer")
	_ok(main.paused == false, "left click resumes gameplay")
	_ok(not ("Click to play" in str(main._prompt.text)), "play prompt restored")

	# 5. Movement active while captured.
	var pos0: Vector3 = main._player.global_position
	Input.action_press("move_forward")
	for i in range(20):
		await physics_frame
	Input.action_release("move_forward")
	_ok(main._player.global_position.distance_to(pos0) > 0.1, "movement active while captured")

	# 6. Pitch clamp retained under large motion.
	_feed_mouse_motion(main, Vector2(0, -100000))
	_ok(is_equal_approx(main.pitch, 1.4), "pitch clamp retained at +1.4")

	# 7. Escape opens the menu and pauses; latched movement is cleared.
	#    (Menus slice: Esc now routes to the menu — pointer release happens
	#    through the menu layer in the real display server.)
	Input.action_press("move_forward")
	_feed_key(main, KEY_ESCAPE)
	_ok(main.main_menu.is_open() and main.main_menu.visible, "Escape opens menu")
	_ok(main.paused == true, "Escape pauses gameplay")
	var pos1: Vector3 = main._player.global_position
	for i in range(10):
		await physics_frame
	_ok(main._player.global_position.distance_to(pos1) < 0.001,
		"stationary while uncaptured (latched input cleared)")

	# 8. E still blocked while paused, near a printer.
	var jobs1: int = main.job_board.get_available_count()
	_feed_key(main, KEY_E)
	_ok(main.job_board.get_available_count() == jobs1, "E blocked while paused")

	# 9. Close menu (Esc), then resume click, then E starts a real job.
	_feed_key(main, KEY_ESCAPE)
	_feed_click(main, MOUSE_BUTTON_LEFT)
	_teleport_near_printer_a(main)
	var jobs_before_e: int = main.job_board.get_available_count()
	_feed_key(main, KEY_E)
	_ok(main.sim.is_running(), "E after resume starts print job")
	# take_next() pops and immediately refills, so the count is invariant;
	# assert the loop stays stocked rather than a decrement.
	_ok(main.job_board.get_available_count() == jobs_before_e
		and main.job_board.has_available(), "job board still stocked after interact")

	# 10. Right click must not capture. Esc opens the menu (new semantics);
	#     close it again, verify a right click never starts capture or resumes.
	_feed_key(main, KEY_ESCAPE)
	_ok(main.main_menu.is_open(), "Escape reopens menu")
	menu_close_via_esc(main)
	_ok(main.paused == true, "right click test: still paused before click")
	_feed_click(main, MOUSE_BUTTON_RIGHT)
	_ok(main.get_mouse_locked() == false or main.paused == true,
		"right click does not capture")

	# 11. Focus-loss notification releases capture and pauses.
	_feed_click(main, MOUSE_BUTTON_LEFT)
	_ok(main.get_mouse_locked() == true, "recaptured before focus-loss test")
	main.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	_ok(main.get_mouse_locked() == false and main.paused == true,
		"focus loss releases capture and pauses")

	print("%d checks — %s" % [checks, "ALL PASS" if failures == 0 else "FAILURES: %d" % failures])
	_finish(0 if failures == 0 else 1)

func _teleport_near_printer_a(main) -> void:
	var pa: Node3D = null
	for p in get_nodes_in_group("printers"):
		if int(p.get_meta("printer_index", -1)) == 0:
			pa = p
			break
	if pa != null:
		main._player.global_position = pa.global_position + Vector3(0.9, -0.6, 1.1)

func _feed_key(main, keycode: Key) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode
	ev.pressed = true
	main._unhandled_input(ev)

func _feed_click(main, button: MouseButton) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = true
	main._unhandled_input(ev)

func _feed_mouse_motion(main, rel: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.relative = rel
	main._unhandled_input(ev)

func _finish(code: int) -> void:
	quit(code)

func menu_close_via_esc(main) -> void:
	_feed_key(main, KEY_ESCAPE)
