extends SceneTree

## v0.57.0 — "Milestones V": Ten K (earn $10,000 lifetime), Scrap heap
## (scrap 15 misprints), Better late than never (deliver 10 late orders)
## and Hard knocks (have 10 orders fail on quality) — four more derived
## achievements, no new save keys. Run:
## godot --headless --path . -s tests/v057_test.gd

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
	_ok(not _done(main, "Ten K"), "Ten K starts undone")
	_ok(not _done(main, "Scrap heap"), "Scrap heap starts undone")
	_ok(not _done(main, "Better late than never"), "Better late starts undone")
	_ok(not _done(main, "Hard knocks"), "Hard knocks starts undone")

	# Ten K: the lifetime earned counter, in cents, one tier above Four figures.
	main.stats["earned_cents"] = 999999
	_ok(not _done(main, "Ten K"), "$9,999.99 is not ten K")
	main.stats["earned_cents"] = 1000000
	_ok(_done(main, "Ten K"), "$10,000.00 lifetime is ten K")

	# Scrap heap: the lifetime scrapped-print counter, one above the
	# single scrap a failed order accrues.
	main.stats["earned_cents"] = 0
	main.stats["scrapped"] = 14
	_ok(not _done(main, "Scrap heap"), "14 scrapped misprints is not the heap")
	main.stats["scrapped"] = 15
	_ok(_done(main, "Scrap heap"), "15 scrapped misprints is the heap")

	# Better late than never: the lifetime late-delivery counter.
	main.stats["scrapped"] = 0
	main.stats["late"] = 9
	_ok(not _done(main, "Better late than never"), "9 late orders is not the badge")
	main.stats["late"] = 10
	_ok(_done(main, "Better late than never"), "10 late orders is the badge")

	# Hard knocks: the lifetime quality-failure counter (second F kills
	# an order and counts here).
	main.stats["late"] = 0
	main.stats["cancelled"] = 9
	_ok(not _done(main, "Hard knocks"), "9 quality failures is not the badge")
	main.stats["cancelled"] = 10
	_ok(_done(main, "Hard knocks"), "10 quality failures is the badge")

	# The stats listing renders the earned one with a check and the rest
	# with their hint. Explicit state: Ten K done, Scrap heap undone.
	main.stats["earned_cents"] = 1000000
	main.stats["cancelled"] = 0
	main._on_menu_stats()
	await physics_frame
	var body: Label = main.main_menu._stats_panel.get_node("Sheet/SheetBox/Body")
	_ok(body.text.contains("✓  Ten K"), "the panel checks off Ten K")
	_ok(body.text.contains("Scrap heap — scrap 15 misprints"),
		"undone milestones keep their hint line")
	_ok(body.text.contains("Better late than never — deliver 10 late orders"),
		"Better late keeps its hint line too")
	_ok(body.text.contains("Hard knocks — have 10 orders fail on quality"),
		"Hard knocks keeps its hint line too")
	_ok(body.text.contains("Spotless"), "the v0.56 milestones still render")

	# Boot adoption: milestones already true at load are adopted silently,
	# never re-toasted after a reload.
	main.stats["earned_cents"] = 1000000
	main.stats["scrapped"] = 15
	main._save_game()
	main.queue_free()
	await physics_frame
	var main2 = packed.instantiate()
	root.add_child(main2)
	await physics_frame
	_ok(main2._achv_toasted.has("Ten K"),
		"a reload adopts Ten K into the toasted set")
	_ok(main2._achv_toasted.has("Scrap heap"),
		"a reload adopts Scrap heap into the toasted set")
	_ok(not main2._achv_toasted.has("Hard knocks"),
		"Hard knocks (undone in the save) stays unadopted")
	_ok(_done(main2, "Ten K"), "the restored boot re-derives Ten K")
	_ok(_done(main2, "Scrap heap"), "the restored boot re-derives Scrap heap")

	main2.queue_free()
	await physics_frame
	BrowserSave.clear()
	print("---")
	print("checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)
