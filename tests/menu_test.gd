extends SceneTree

## Headless main-menu gate (menus slice).
## Run: godot --headless --path . -s tests/menu_test.gd
## RED before MainMenu.gd / Main.gd menu wiring; GREEN after.
## All input is fed as real InputEvent objects through Main._unhandled_input
## (same harness style as input_pause_test / touch_controls_test).

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

	# 1. Boot state: menu visible, gameplay prompt suppressed while open.
	var menu = main.main_menu
	_ok(menu != null, "Main exposes main_menu at boot")
	if menu == null:
		quit(1)
		return
	_ok(menu is CanvasLayer and menu.visible, "main menu visible at boot")
	_ok(menu.is_open(), "menu reports open")
	_ok(str(main._prompt.text).strip_edges() == "", "gameplay prompt suppressed while menu open")

	# 2. Title + version content.
	var title: Label = menu.get_node("Root/Layout/Title")
	_ok(title != null and title.text == "PRINT SHOP SIM", "title label reads PRINT SHOP SIM")
	var ver: Label = menu.get_node("Root/Version")
	_ok(ver != null and ver.text == root.get_node("/root/Version").label(),
		"version label matches Version.label()")

	# 3. Play hides the menu and restores the capture prompt flow.
	_feed_click(main, MOUSE_BUTTON_LEFT)  # must NOT capture while menu is open
	_ok(main.paused and not main.get_mouse_locked(), "click while menu open does not capture")
	var play: Button = menu.get_node("Root/Layout/Buttons/Play")
	_ok(play != null, "Play button exists")
	play.pressed.emit()
	_ok(not menu.visible and not menu.is_open(), "Play hides the menu")
	_ok(not str(main._prompt.text).is_empty(), "capture prompt shown after Play")
	_ok(main.paused, "still paused after Play until deliberate capture")

	# 4. Click now captures (existing flow restored).
	_feed_click(main, MOUSE_BUTTON_LEFT)
	_ok(main.get_mouse_locked() and not main.paused, "click captures after Play")

	# 5. Esc opens the menu; Esc in menu closes back to resume prompt.
	_feed_key(main, KEY_ESCAPE)
	_ok(menu.visible and menu.is_open(), "Esc opens menu while playing")
	_ok(main.paused, "opening menu pauses")
	_feed_key(main, KEY_ESCAPE)
	_ok(not menu.visible, "Esc in menu closes it")
	_ok(not str(main._prompt.text).is_empty(), "resume/capture prompt restored after close")

	# 6. Contracts panel: >=3 cards with payout strings, Back returns.
	_feed_key(main, KEY_ESCAPE)  # open menu
	var contracts_btn: Button = menu.get_node("Root/Layout/Buttons/Contracts")
	contracts_btn.pressed.emit()
	var cards: Array = menu.contract_cards()
	_ok(menu.contracts_visible(), "contracts panel shown")
	_ok(cards.size() >= 3, "contracts panel lists >=3 cards (got %d)" % cards.size())
	var payouts_ok := true
	for card in cards:
		var pt: Variant = card.get_meta("payout_text", null)
		if not (pt is String and str(pt).begins_with("$") and str(pt).contains(".")):
			payouts_ok = false
	_ok(payouts_ok, "every card carries a $X.XX payout string")
	_ok(menu.get_node("Root/ContractsPanel/Sheet/SheetBox/Back") != null, "Back button exists")
	menu.get_node("Root/ContractsPanel/Sheet/SheetBox/Back").pressed.emit()
	_ok(not menu.contracts_visible() and menu.is_open(), "Back returns to main menu panel")

	# 7. Version sha format on the label (Alpha <ver> Git: <sha>).
	var sha_re := RegEx.new()
	sha_re.compile("^Alpha [0-9.]+ Git: [0-9a-f]+$")
	# NOTE: autoloads are not registered in --script mode (known artifact),
	# so compare the menu label against Version's format logic via the same
	# regex only — the autoload identity is covered in the running game.
	_ok(sha_re.search(ver.text) != null,
		"version label matches 'Alpha x.y Git: sha'")

	# 8. Quit button hidden when web feature is simulated (menu has a test seam).
	menu.simulate_web = true
	var quit_btn: Button = menu.get_node("Root/Layout/Buttons/Quit")
	_ok(quit_btn != null and not quit_btn.visible, "Quit hidden (web feature simulated)")
	menu.simulate_web = false

	# 9. With the menu closed the UI ignores the mouse (no full-rect filter).
	menu.close_menu()
	_ok(not menu.visible and not menu.blocks_mouse_when_closed(),
		"menu ignores mouse when closed")

	print("%d checks — %s" % [checks, "ALL PASS" if failures == 0 else "FAILURES: %d" % failures])
	quit(0 if failures == 0 else 1)
