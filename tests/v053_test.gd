extends SceneTree

## v0.53.0 — "Top clients": the Stats panel ranks the three most loyal
## clients by completed orders. Run:
## godot --headless --path . -s tests/v053_test.gd

var checks := 0
var failures := 0


func _ok(cond: bool, label: String) -> void:
	checks += 1
	if cond:
		print("ok %d: %s" % [checks, label])
	else:
		failures += 1
		printerr("FAIL %d: %s" % [checks, label])


func _stats_text(main) -> String:
	main._on_menu_stats()
	return str(main.main_menu._stats_panel.get_node("Sheet/SheetBox/Body").text)


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

	# A fresh shop has no client history: no block at all.
	var text := _stats_text(main)
	_ok(not text.contains("CLIENTS"), "no client block before the first order")
	_ok(text.contains("Regulars: 0"), "the regulars line still renders")

	# Two clients: both listed under the distinct count.
	main.client_orders["Kiki's Cafe"] = 4
	main.client_orders["Dot's Diner"] = 2
	text = _stats_text(main)
	_ok(text.contains("CLIENTS (2 distinct)"), "the header counts distinct clients")
	_ok(text.contains("1. Kiki's Cafe x4"), "the top client leads with a count")
	_ok(text.contains("2. Dot's Diner x2"), "the second client follows")

	# Ranking: count desc, ties alphabetical, capped at three.
	main.client_orders["Alpha Press"] = 1
	main.client_orders["Gamma Gym"] = 3
	main.client_orders["Delta Deli"] = 5
	main.client_orders["Beta Bakery"] = 5
	text = _stats_text(main)
	var i_beta := text.find("1. Beta Bakery x5")
	var i_delta := text.find("2. Delta Deli x5")
	var i_kiki := text.find("3. Kiki's Cafe x4")
	_ok(i_beta >= 0 and i_delta >= 0 and i_kiki >= 0,
		"the top three rank by orders with a name tie-break")
	_ok(i_beta < i_delta and i_delta < i_kiki, "the ranked order is stable")
	_ok(not text.contains("Gamma Gym"), "clients past third place stay off the list")
	_ok(text.contains("CLIENTS (6 distinct)"),
		"the header counts every distinct client, not just the podium")

	# Ten clients: the podium still caps at three lines.
	main.client_orders["Sixth"] = 1
	main.client_orders["Seventh"] = 1
	main.client_orders["Eighth"] = 1
	main.client_orders["Ninth"] = 1
	main.client_orders["Tenth"] = 1
	text = _stats_text(main)
	_ok(text.contains("CLIENTS (11 distinct)"), "eleven distinct clients counted")
	_ok(text.count("1. ") + text.count("2. ") + text.count("3. ") >= 3
		and not text.contains("4. "), "the list never grows past three")

	# The block survives a save/reload (client_orders is the same persisted
	# dictionary the regulars system uses).
	main._save_game()
	main.queue_free()
	await physics_frame
	var main2 = packed.instantiate()
	root.add_child(main2)
	await physics_frame
	text = _stats_text(main2)
	_ok(text.contains("1. Beta Bakery x5"),
		"a reloaded shop keeps its client ranking")
	_ok(text.contains("CLIENTS (11 distinct)"),
		"the distinct count survives the reload")

	main2.queue_free()
	await physics_frame
	BrowserSave.clear()
	print("---")
	print("checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)
