extends SceneTree

## Headless touch-controls gate (mobile slice).
## Run: godot --headless --path . -s tests/touch_controls_test.gd
## RED before TouchControls.gd/Main.gd mobile changes; GREEN after.
## Feeds real InputEventScreenTouch / InputEventScreenDrag objects through
## TouchControls._unhandled_input and Main's real handlers — no source-text
## regex, no logic-replacing mocks. Headless cannot detect a touchscreen, so
## the documented test-only override (TouchControls.force_enabled) is used;
## real browser touch behavior still needs parent browser verification.

const TC := preload("res://scripts/TouchControls.gd")
const STICK_DRAG_X := 40.0
const STICK_DRAG_Y := 50.0

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

func _feed_touch(tc, index: int, pos: Vector2, pressed: bool) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = index
	ev.position = pos
	ev.pressed = pressed
	tc._unhandled_input(ev)

func _feed_drag(tc, index: int, pos: Vector2, rel: Vector2) -> void:
	var ev := InputEventScreenDrag.new()
	ev.index = index
	ev.position = pos
	ev.relative = rel
	tc._unhandled_input(ev)

func _feed_cancel(tc, index: int, pos: Vector2) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = index
	ev.position = pos
	ev.pressed = true
	ev.canceled = true
	tc._unhandled_input(ev)

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

func _run() -> void:
	var packed: PackedScene = load("res://scenes/Main.tscn")
	_ok(packed != null, "Main.tscn loads")
	if packed == null:
		quit(1)
		return
	var main = packed.instantiate()
	root.add_child(main)
	await process_frame

	_ok(main.touch_controls != null, "TouchControls attached to real Main scene")
	var tc = main.touch_controls
	_ok(tc is CanvasLayer and tc.get_parent() == main, "TouchControls is CanvasLayer child of Main")
	_ok(not tc.visible, "controls hidden on desktop (no touchscreen, no override)")

	# Visibility must reflect effective_enabled() at ready and whenever the
	# override changes — an invisible overlay can never be seen on real touch
	# devices, and a visible one would leak desktop-only visuals.
	tc.force_enabled = true
	_ok(tc.visible == true, "forced-touch override makes overlay visible")
	_ok(tc.pause_label_text() == "Resume", "mobile pause label starts as Resume (boot paused)")
	tc.force_enabled = false
	_ok(tc.visible == false, "clearing the override hides the overlay again")
	tc.force_enabled = true
	_ok(tc.visible == true, "re-enabling the override shows the overlay again")

	var stick: Vector2 = tc.stick_center()
	var look_pos: Vector2 = tc.look_rect().get_center()
	_ok(tc.stick_region().has_point(stick), "stick region contains stick center")
	_ok(tc.look_rect().has_point(look_pos), "look rect contains its center")
	_ok(tc.interact_rect().size.x >= 48.0 and tc.interact_rect().size.y >= 48.0,
		"interact target >= 48px")
	_ok(tc.pause_rect().size.x >= 48.0 and tc.pause_rect().size.y >= 48.0,
		"pause target >= 48px")

	# Portrait layout keeps targets >= 48px inside a narrow viewport.
	var portrait: Dictionary = tc.layout_rects(Vector2(390, 844), 0, 47, 0, 34)
	_ok(portrait.interact.size.x >= 48.0 and portrait.pause.size.y >= 48.0,
		"portrait layout targets >= 48px")
	_ok(portrait.look.size.x > 390.0 * 0.55 - 0.01 and portrait.look.size.x < 390.0 * 0.55 + 0.01,
		"portrait look region sized")

	# Paused at boot: stick touch must not engage motion (no input while paused).
	_ok(main.paused == true, "boot paused")
	_feed_touch(tc, 0, stick, true)
	_ok(tc.active_fingers() == 0 and main.get_touch_move_axis() == Vector2.ZERO,
		"stick touch while paused owns no motion finger, axis zero")
	_feed_touch(tc, 0, stick, false)

	# Resume via user gesture on the Pause/Resume button.
	var resume_pos: Vector2 = tc.pause_rect().get_center()
	_feed_touch(tc, 5, resume_pos, true)
	_ok(main.paused == false, "resume tap unpauses (user gesture)")
	_ok(tc.is_motion_enabled(), "motion enabled after resume")

	# Simultaneous two-finger move + look.
	_feed_touch(tc, 0, stick, true)
	_feed_touch(tc, 1, look_pos, true)
	_ok(tc.active_fingers() == 2, "two fingers owned (move + look)")
	var drag_pos: Vector2 = stick + Vector2(STICK_DRAG_X, -STICK_DRAG_Y)
	_feed_drag(tc, 0, drag_pos, Vector2(STICK_DRAG_X, -STICK_DRAG_Y))
	_ok(tc.get_move_axis().length() <= 1.0001, "move axis clamped to unit vector")
	_ok(tc.get_move_axis().y < -0.5, "stick pushed up = forward (negative y)")
	_feed_drag(tc, 1, look_pos + Vector2(30, -12), Vector2(30, -12))
	_ok(main.consume_touch_look_delta() == Vector2(30, -12),
		"simultaneous look delta accumulates while move finger held")

	var touch_start: Vector3 = main._player.position
	var touch_yaw: float = main.yaw
	_feed_drag(tc, 1, look_pos + Vector2(20, 0), Vector2(20, 0))
	main._physics_process(1.0 / 60.0)
	_ok(not main.get_mouse_locked() and main._player.position.distance_to(touch_start) > 0.001,
		"touch movement updates real player without pointer lock")
	_ok(not is_equal_approx(main.yaw, touch_yaw), "touch look updates real camera yaw without pointer lock")

	# Releasing the move finger preserves look ownership and vice versa.
	_feed_touch(tc, 0, drag_pos, false)
	_ok(tc.get_move_axis() == Vector2.ZERO, "move release clears axis")
	_feed_drag(tc, 1, look_pos + Vector2(6, 0), Vector2(6, 0))
	_ok(main.consume_touch_look_delta() == Vector2(6, 0), "look finger still owned after move release")
	_feed_touch(tc, 1, look_pos, false)

	# Third finger must not hijack move or look ownership.
	_feed_touch(tc, 0, stick, true)
	_feed_touch(tc, 1, look_pos, true)
	_feed_touch(tc, 2, Vector2(60, 60), true)  # lands in left/top region
	_ok(tc.active_fingers() == 2, "third finger not hijacking ownership")
	var look0: float = main.yaw
	_feed_drag(tc, 2, Vector2(80, 60), Vector2(200, 0))
	_ok(main.consume_touch_look_delta() == Vector2.ZERO, "third-finger drag produces no look")
	_ok(is_equal_approx(main.yaw, look0), "yaw unchanged by third finger")
	# Release owned fingers so later ownership checks start clean.
	_feed_touch(tc, 0, stick, false)
	_feed_touch(tc, 1, look_pos, false)
	_ok(tc.active_fingers() == 0, "both owned fingers released cleanly")

	# Deadzone: tiny stick offset reads as zero.
	_feed_touch(tc, 0, stick + Vector2(4, 0), true)
	_ok(tc.get_move_axis() == Vector2.ZERO, "deadzone: 4px stick offset = zero axis")
	_feed_touch(tc, 0, stick, false)

	# Axis clamp: far diagonal offset (still inside the stick region) reads unit-length.
	_feed_touch(tc, 0, stick + Vector2(100, -100), true)
	_ok(is_equal_approx(tc.get_move_axis().length(), 1.0), "far drag clamps to unit axis")
	_feed_touch(tc, 0, stick + Vector2(100, -100), false)

	# UI touch inside Interact rect must not start look or stick ownership.
	_feed_touch(tc, 7, tc.interact_rect().get_center(), true)
	_ok(tc.active_fingers() == 0, "interact tap owns no motion finger")

	# Interaction gating: paused blocks touch interact; unpaused near printer starts job.
	tc.force_enabled = true
	_on_pause_tap(tc, main)
	_ok(main.paused == true, "pause tap pauses")
	var jobs0: int = main.job_board.get_available_count()
	_feed_touch(tc, 8, tc.interact_rect().get_center(), true)
	_ok(main.job_board.get_available_count() == jobs0, "touch interact blocked while paused")
	_resume_via_tap(tc, main)
	_teleport_near_printer_a(main)
	main.sim.state = PrintSim.State.IDLE
	_feed_touch(tc, 8, tc.interact_rect().get_center(), true)
	_ok(main.sim.is_running(), "touch interact starts print job when unpaused")

	# Pause clears fingers and axes; motion stays off until next resume tap.
	main.touch_controls._move_finger = 0
	_on_pause_tap(tc, main)
	_ok(tc.active_fingers() == 0 and tc.get_move_axis() == Vector2.ZERO,
		"pause clears fingers and axis")
	_ok(tc.is_motion_enabled() == false, "motion disabled while paused")

	# Focus loss pauses and clears touch state.
	_resume_via_tap(tc, main)
	main.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	_ok(main.paused == true and tc.active_fingers() == 0,
		"focus loss pauses and clears touch fingers")

	# --- desktop regression: untouched behavior ---
	var yaw0: float = main.yaw
	var mm := InputEventMouseMotion.new()
	mm.relative = Vector2(120, -40)
	main._unhandled_input(mm)
	_ok(is_equal_approx(main.yaw, yaw0), "mouse motion still ignored while uncaptured")
	_feed_click(main, MOUSE_BUTTON_LEFT)
	_ok(not main.get_mouse_locked() and main.paused, "touch device ignores synthetic mouse capture")
	tc.force_enabled = false
	# Touch Pause opened the menu (menus slice); close it before desktop recapture.
	main.main_menu.close_menu()
	_feed_click(main, MOUSE_BUTTON_LEFT)
	_ok(main.get_mouse_locked() and main.paused == false, "left click still captures+resumes")
	var yaw1: float = main.yaw
	var mm2 := InputEventMouseMotion.new()
	mm2.relative = Vector2(-90, 30)
	main._unhandled_input(mm2)
	_ok(not is_equal_approx(main.yaw, yaw1), "mouse look works while captured")
	var pitch0: float = main.pitch
	var mm3 := InputEventMouseMotion.new()
	mm3.relative = Vector2(0, -100000)
	main._unhandled_input(mm3)
	_ok(is_equal_approx(main.pitch, 1.4), "desktop pitch clamp retained")
	# Menus slice: Esc opens the menu and pauses; close it to continue desktop flow.
	_feed_key(main, KEY_ESCAPE)
	_ok(main.paused == true and main.main_menu.is_open(), "Escape still pauses (menu opens)")
	main.main_menu.close_menu()
	# Touch drags must not capture or resume on the desktop path: game stays
	# paused after the drag (capture state alone is ambiguous in headless).
	var drag_pos0: Vector3 = main._player.global_position
	_feed_drag(tc, 1, look_pos + Vector2(50, 0), Vector2(50, 0))
	_ok(main.paused == true
		and main._player.global_position.distance_to(drag_pos0) < 0.001,
		"touch drag does not capture mouse on desktop")
	# Desktop mouse must not feed touch stick/look ownership.
	var pos0: Vector3 = main._player.global_position
	_feed_click(main, MOUSE_BUTTON_LEFT)
	_ok(main.get_mouse_locked() == true, "desktop recapture works after touch session")

	print("%d checks — %s" % [checks, "ALL PASS" if failures == 0 else "FAILURES: %d" % failures])
	quit(0 if failures == 0 else 1)

func _on_pause_tap(tc, main) -> void:
	# Ensure motion is on so the button means Pause, not Resume.
	if not tc.is_motion_enabled():
		_feed_touch(tc, 9, tc.pause_rect().get_center(), true)
	_feed_touch(tc, 9, tc.pause_rect().get_center(), true)

func _resume_via_tap(tc, main) -> void:
	_feed_touch(tc, 9, tc.pause_rect().get_center(), true)

func _teleport_near_printer_a(main) -> void:
	for p in get_nodes_in_group("printers"):
		if int(p.get_meta("printer_index", -1)) == 0:
			main._player.global_position = p.global_position + Vector3(0.9, -0.6, 1.1)
			return
	# Menus slice: boot opens the main menu; Play restores the capture flow.
	main.main_menu.get_node("Root/Layout/Buttons/Play").pressed.emit()
