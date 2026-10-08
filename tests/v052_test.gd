extends SceneTree

## v0.52.0 — "Milestones III": Fortnight, Century, Full week and Ten spot —
## four derived achievements, no new save keys. Run:
## godot --headless --path . -s tests/v052_test.gd

var checks := 0
var failures := 0


func _ok(cond: bool, label: String) -> void:
	checks += 1
	if cond:
		print("ok %d: %s" % [checks, label])
	else:
		failures += 1
		printerr("FAIL %d: %s" % [checks, label])


func _done(main, achievement_name: String) -> bool:
	for a in main._achievements():
		if str(a.name) == achievement_name:
			return bool(a.done)
	return false


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

	# A fresh shop has earned none of the new four.
	_ok(not _done(main, "Fortnight"), "Fortnight starts undone")
	_ok(not _done(main, "Century"), "Century starts undone")
	_ok(not _done(main, "Full week"), "Full week starts undone")
	_ok(not _done(main, "Ten spot"), "Ten spot starts undone")

	# Fortnight: strictly past day 14, like Week one's past day 7.
	main.day_cycle.restore(14, 0.0)
	_ok(not _done(main, "Fortnight"), "day 14 is not yet a fortnight")
	main.day_cycle.restore(15, 0.0)
	_ok(_done(main, "Fortnight"), "day 15 is a fortnight")

	# Century: the lifetime delivered counter.
	main.stats["delivered"] = 99
	_ok(not _done(main, "Century"), "99 deliveries is not a century")
	main.stats["delivered"] = 100
	_ok(_done(main, "Century"), "100 deliveries is a century")

	# Full week: the 7-day window, all days positive.
	main.stats["delivered"] = 0
	main.daily_delivered.assign([2, 1, 1, 1, 1, 1])
	_ok(not _done(main, "Full week"), "six good days is not a full week")
	main.daily_delivered.assign([2, 1, 1, 1, 1, 1, 0])
	_ok(not _done(main, "Full week"), "one quiet day breaks the week")
	main.daily_delivered.assign([2, 1, 1, 1, 1, 1, 1])
	_ok(_done(main, "Full week"), "seven shipping days is a full week")

	# Ten spot: distinct clients served.
	main.daily_delivered.assign([0, 0, 0, 0, 0, 0, 0])
	for i in range(9):
		main.client_orders["Client %d" % i] = 1
	_ok(not _done(main, "Ten spot"), "nine clients is not a ten spot")
	main.client_orders["Tenth Client"] = 2
	_ok(_done(main, "Ten spot"), "ten clients is a ten spot")

	# The stats listing renders the earned ones with a check and the rest
	# with their hint. Explicit state: Century done, Full week undone.
	main.stats["delivered"] = 100
	main._on_menu_stats()
	await physics_frame
	var body: Label = main.main_menu._stats_panel.get_node("Sheet/SheetBox/Body")
	_ok(body.text.contains("✓  Century"), "the panel checks off Century")
	_ok(body.text.contains("Full week — ship an order every day for a week"),
		"undone milestones keep their hint line")
	_ok(body.text.contains("CLIENTS (10 distinct)"),
		"the v0.53 block coexists in the same panel")

	# Boot adoption: milestones already true at load are adopted silently,
	# never re-toasted after a reload.
	main._save_game()
	main.queue_free()
	await physics_frame
	var main2 = packed.instantiate()
	root.add_child(main2)
	await physics_frame
	_ok(main2._achv_toasted.has("Century"),
		"a reload adopts Century into the toasted set")
	_ok(not main2._achv_toasted.has("Full week"),
		"Full week (undone in the save) stays unadopted")

	main2.queue_free()
	await physics_frame
	BrowserSave.clear()
	print("---")
	print("checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)
