extends SceneTree

## v0.56.0 — "Milestones IV": Four figures (earn $1,000 lifetime), Rolodex
## (serve 25 different clients) and Spotless (run 25 cleaning cycles) — three
## more derived achievements, no new save keys. Run:
## godot --headless --path . -s tests/v056_test.gd

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

	# A fresh shop has earned none of the new three.
	_ok(not _done(main, "Four figures"), "Four figures starts undone")
	_ok(not _done(main, "Rolodex"), "Rolodex starts undone")
	_ok(not _done(main, "Spotless"), "Spotless starts undone")

	# Four figures: the lifetime earned counter, in cents.
	main.stats["earned_cents"] = 99999
	_ok(not _done(main, "Four figures"), "$999.99 is not four figures")
	main.stats["earned_cents"] = 100000
	_ok(_done(main, "Four figures"), "$1,000.00 lifetime is four figures")

	# Rolodex: distinct clients served, one above Ten spot's bar.
	main.stats["earned_cents"] = 0
	for i in range(24):
		main.client_orders["Client %d" % i] = 1
	_ok(not _done(main, "Rolodex"), "24 clients is not a rolodex")
	main.client_orders["Twenty-fifth Client"] = 2
	_ok(_done(main, "Rolodex"), "25 clients is a rolodex")

	# Spotless: the completed-clean counter, one above Meticulous's bar.
	main.client_orders.clear()
	main.cleans = 24
	_ok(not _done(main, "Spotless"), "24 cleans is not spotless")
	main.cleans = 25
	_ok(_done(main, "Spotless"), "25 cleans is spotless")

	# The stats listing renders the earned one with a check and the rest
	# with their hint. Explicit state: Four figures done, Spotless undone.
	main.stats["earned_cents"] = 100000
	main.cleans = 24
	main._on_menu_stats()
	await physics_frame
	var body: Label = main.main_menu._stats_panel.get_node("Sheet/SheetBox/Body")
	_ok(body.text.contains("✓  Four figures"), "the panel checks off Four figures")
	_ok(body.text.contains("Spotless — run 25 cleaning cycles"),
		"undone milestones keep their hint line")
	_ok(body.text.contains("Rolodex — serve 25 different clients"),
		"Rolodex keeps its hint line too")
	_ok(body.text.contains("Ten spot"), "the v0.52 milestones still render")

	# Boot adoption: milestones already true at load are adopted silently,
	# never re-toasted after a reload.
	main.stats["earned_cents"] = 100000
	main._save_game()
	main.queue_free()
	await physics_frame
	var main2 = packed.instantiate()
	root.add_child(main2)
	await physics_frame
	_ok(main2._achv_toasted.has("Four figures"),
		"a reload adopts Four figures into the toasted set")
	_ok(not main2._achv_toasted.has("Spotless"),
		"Spotless (undone in the save) stays unadopted")
	_ok(_done(main2, "Four figures"), "the restored boot re-derives Four figures")

	main2.queue_free()
	await physics_frame
	BrowserSave.clear()
	print("---")
	print("checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)
