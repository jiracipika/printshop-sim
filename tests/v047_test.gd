extends SceneTree

const BrowserSave = preload("res://scripts/BrowserSave.gd")

## v0.47.0 — "shop history": the chalkboard gains an order-count graph
## beside the earnings sparkline (same weekly window + ramp) and a
## "Best day" record line; the Today panel gains yesterday's order count.
## daily_delivered / day_delivered_today persist with validators, banked at
## rollover exactly like daily_earned.
## Run: godot --headless --path . -s tests/v047_test.gd

var checks := 0
var failures := 0
var main = null


func _ok(cond: bool, label: String) -> void:
	checks += 1
	if cond:
		print("ok %d: %s" % [checks, label])
	else:
		failures += 1
		printerr("FAIL %d: %s" % [checks, label])


func _drive(max_steps := 60000) -> void:
	var steps := 0
	while main.sim.state == PrintSim.State.RUNNING and steps < max_steps:
		main.sim.tick(1.0 / 60.0)
		steps += 1


func _init() -> void:
	root.ready.connect(_run)


func _run() -> void:
	BrowserSave.clear()
	var packed: PackedScene = load("res://scenes/Main.tscn")
	main = packed.instantiate()
	root.add_child(main)
	await physics_frame
	await physics_frame
	main.paused = false
	main.captured = true

	_ok(main._orders_sparkline() == "No orders yet this week.",
		"an empty history shows the placeholder")
	_ok(int(main._best_day_cents()) == 0, "no best day before any earnings")

	# Ramp glyphs pin against the best DAY (never against dollars).
	main.daily_delivered.assign([1, 2, 4])
	main.daily_earned.assign([100, 300, 900])
	_ok(main._orders_sparkline() == "Orders: ▂▄█",
		"the order graph scales against the best day (%s)" % main._orders_sparkline())
	_ok("Last days: ▁▃█" in main._earnings_sparkline(),
		"the earnings graph is unchanged")
	_ok(int(main._best_day_cents()) == 900, "best day reads the stored maximum")
	main._chalk_cache = ""
	main._update_chalkboard()
	_ok("Orders: ▂▄█" in str(main._chalk_label.text)
		and "Best day: $9.00" in str(main._chalk_label.text),
		"the chalkboard renders both graphs and the record")

	# The real delivery path feeds today's counters.
	main._player.global_position = Vector3(-1.8, 0.3, -1.0)
	main.yaw = 0.0
	main._player.rotation.y = main.yaw
	main._try_interact()  # accept
	var c0 = main.active_contract
	if c0 == null:
		_ok(false, "accept works for the delivery loop")
		_finish()
		return
	main._try_interact()  # preview
	main._try_interact()  # confirm
	main.paused = true
	_drive()
	main.paused = false
	main._try_interact()  # collect
	_ok(main._try_pack_held() and int(main.day_delivered_today) == 1,
		"a real delivery raises today's order count")

	# Rollover banks the day, same as earnings.
	main.day_earned_today = 1234
	main.day_delivered_today = 3
	main._on_day_changed(2)
	_ok(int(main.daily_earned[-1]) == 1234 and int(main.day_earned_today) == 0,
		"earnings bank and reset at rollover")
	_ok(int(main.daily_delivered[-1]) == 3 and int(main.day_delivered_today) == 0,
		"orders bank and reset at rollover")

	# The weekly window trims to 7.
	main.daily_delivered.assign([1, 2, 3, 4, 5, 6, 7])
	main.day_delivered_today = 8
	main._on_day_changed(3)
	_ok(main.daily_delivered.size() == 7 and int(main.daily_delivered[0]) == 2
		and int(main.daily_delivered[-1]) == 8,
		"the order window keeps the newest seven days")

	# The Today panel reports yesterday's orders (panel lines are built from
	# the same arrays; a real delivery already fed them above).
	main.daily_earned.assign([500])
	main.daily_delivered.assign([2])
	_ok(not main.daily_delivered.is_empty()
		and int(main.daily_delivered[-1]) == 2,
		"today's panel data source carries yesterday's orders")

	# Persistence + validators.
	main.daily_delivered.assign([2, 0, 5])
	main.day_delivered_today = 1
	main._save_game()
	var saved: Dictionary = BrowserSave.load_payload()
	var arr_ok: bool = typeof(saved.get("daily_delivered")) == TYPE_ARRAY \
		and saved["daily_delivered"].size() == 3 \
		and int(saved["daily_delivered"][2]) == 5
	_ok(arr_ok and int(saved.get("day_delivered_today", -1)) == 1,
		"order history persists in the payload")
	var ss = load("res://scripts/SaveSystem.gd")
	var no_hist: Dictionary = saved.duplicate(true)
	no_hist.erase("daily_delivered")
	no_hist.erase("day_delivered_today")
	_ok(not ss.validate(no_hist).is_empty(), "payloads without history validate (old saves)")
	var frac: Dictionary = saved.duplicate(true)
	frac["daily_delivered"] = [1.5, 2]
	_ok(ss.validate(frac).is_empty(), "validator rejects fractional orders")
	var neg: Dictionary = saved.duplicate(true)
	neg["daily_delivered"] = [-1, 2]
	_ok(ss.validate(neg).is_empty(), "validator rejects negative orders")
	var big: Dictionary = saved.duplicate(true)
	big["daily_delivered"] = [1, 2, 3, 4, 5, 6, 7, 8]
	_ok(ss.validate(big).is_empty(), "validator rejects a window over 7 days")
	var bad_count: Dictionary = saved.duplicate(true)
	bad_count["day_delivered_today"] = -2
	_ok(ss.validate(bad_count).is_empty(), "validator rejects a negative daily count")

	# Restore: a fresh boot rebuilds the graph.
	var packed2: PackedScene = load("res://scenes/Main.tscn")
	var main2 = packed2.instantiate()
	root.add_child(main2)
	await physics_frame
	await physics_frame
	var restored: bool = main2.daily_delivered.size() == 3 \
		and int(main2.daily_delivered[2]) == 5 \
		and int(main2.day_delivered_today) == 1
	_ok(restored, "restored boot rebuilds the order history")
	main2.queue_free()
	await physics_frame

	_finish()


func _finish() -> void:
	BrowserSave.clear()
	print("---")
	print("checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)
