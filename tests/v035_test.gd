extends SceneTree

## v0.35.0 — "The morning paper": Today panel with yesterday's recap,
## today's modifiers and tomorrow's forecast. Run:
## timeout 180 godot --headless --path . -s tests/v035_test.gd

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

	# The panel exists and the button row grew to 9 with Today between
	# Log and Quit.
	_ok(main.main_menu._today_panel != null, "Today panel built")
	main._on_menu_today()
	await physics_frame
	_ok(main.main_menu._today_panel.visible, "Today panel opens")
	var body: Label = main.main_menu._today_panel.get_node("Sheet/SheetBox/Scroll/List/Body")
	var text := body.text

	# Day 1: no yesterday, today's event, tomorrow's forecast.
	_ok(text.contains("the shop just opened"), "day 1 has no yesterday")
	_ok(text.contains("TODAY -- Day 1"), "today header present")
	_ok(text.contains(str(main.today_event.name)), "today's event named")
	var tomorrow := Events.for_day(2)
	_ok(text.contains("TOMORROW -- Day 2")
		and text.contains(str(tomorrow.name)),
		"tomorrow's event forecast")
	_ok(text.contains(Events.forecast_hint(2)), "forecast carries a hint")

	# Forecast correctness across a sweep: the panel always names
	# Events.for_day(day+1).
	var forecast_ok := true
	for day in range(2, 12):
		main.day_cycle.restore(day, 0.3)
		main._refresh_event()
		main._on_menu_today()
		await physics_frame
		var t: String = main.main_menu._today_panel.get_node(
			"Sheet/SheetBox/Scroll/List/Body").text
		if not t.contains(str(Events.for_day(day + 1).name)):
			forecast_ok = false
	_ok(forecast_ok, "forecast tracks Events.for_day(day+1) across days")

	# Week roll: the panel announces the incoming season.
	main.day_cycle.restore(7, 0.3)  # day 7 -> tomorrow is day 8 = week 2
	main._refresh_event()
	main._on_menu_today()
	await physics_frame
	var wk_text: String = main.main_menu._today_panel.get_node(
		"Sheet/SheetBox/Scroll/List/Body").text
	_ok(wk_text.contains("A new week begins")
		and wk_text.contains(str(Events.season_for_week(2).name)),
		"week roll announces the incoming season")

	# Yesterday's recap: banked earnings + log kinds. Advance to day 3 so
	# "yesterday" (day 2) is a real, loggable day.
	main.day_cycle.restore(3, 0.3)
	main._refresh_event()
	main.daily_earned.assign([3210])
	main.workshop_log.append("delivered", "test delivery", 2)
	main.workshop_log.append("expired", "test expiry", 2)
	main._on_menu_today()
	await physics_frame
	var recap: String = main.main_menu._today_panel.get_node(
		"Sheet/SheetBox/Scroll/List/Body").text
	_ok(recap.contains("$32.10 earned"), "yesterday's take shown")
	_ok(recap.contains("1 delivered") and recap.contains("1 expired"),
		"yesterday's log kinds counted")

	# Focus chain: Today sits between Log and Quit.
	var log_btn: Button = main.main_menu._root.find_child("Log", true, false)
	var today_btn: Button = main.main_menu._root.find_child("Today", true, false)
	var quit_btn: Button = main.main_menu._root.find_child("Quit", true, false)
	_ok(today_btn != null and log_btn != null and quit_btn != null
		and today_btn.focus_neighbor_right == quit_btn.get_path()
		and today_btn.focus_neighbor_left == log_btn.get_path(),
		"Today sits in the focus chain between Log and Quit")

	# Production shows only unlocked printers and protects an active print.
	_ok("Printer 1" in recap and "Printer 2" not in recap, "production lists unlocked printers")
	var machine: Dictionary = main._machine(0)
	machine["last_est_g"] = 90
	main._accept_on(0)
	var job: Contract = machine.contract
	main._on_menu_today()
	var release: Button = main.main_menu._today_panel.find_child("Release0", true, false)
	var balance: int = main.ledger.balance()
	var stock: int = machine.filament_g
	var rating: float = main.reputation
	_ok(release != null and job.model_name in body.text, "unstarted order offers release")
	release.pressed.emit()
	_ok(machine.contract == job and "Confirm" in release.text, "release requires confirmation")
	release.pressed.emit()
	_ok(machine.contract == null and main.ledger.balance() == balance and machine.filament_g == stock,
		"confirmed release frees the printer without consuming materials")
	_ok(is_equal_approx(main.reputation, rating - 0.1), "confirmed release records the disclosed reputation cost")

	main._accept_on(0)
	var printing_job: Contract = machine.contract
	var orientations := PrepSystem.orientations()
	for index in range(orientations.size()):
		var estimate: Dictionary = main._prep_eval(printing_job, orientations[index])
		if estimate.valid:
			machine.orient = index
			machine.filament_g = int(estimate.estimated_material_g)
			break
	main.ledger.credit(printing_job.material_cost_cents, "test setup")
	main._prep_on(0)
	main._prep_on(0)
	main._on_menu_today()
	var sim: PrintSim = machine.sim
	_ok(sim.state == PrintSim.State.RUNNING and not main._can_release_order(machine),
		"a running order cannot be released")

	main.queue_free()
	await physics_frame
	BrowserSave.clear()
	print("---")
	print("checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)
