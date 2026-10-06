extends SceneTree

## v0.46.0 — "power bill": every unlocked printer draws $1/day, charged at
## the morning rollover right after rent. No debt plumbing: a shop that
## cannot pay runs dark (nothing charged, nothing owed). A rent holiday
## does not cover power. Scales with the farm: 1 machine $1, all 4 $4.
## Run: godot --headless --path . -s tests/v046_test.gd

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


func _init() -> void:
	root.ready.connect(_run)


func _power_txs(day: int) -> Array:
	var out: Array = []
	for t in main.ledger.transactions:
		if t["reason"] == "power day %d" % day:
			out.append(t)
	return out


func _has_rent_tx(day: int) -> bool:
	for t in main.ledger.transactions:
		if t["reason"] == "rent day %d" % day:
			return true
	return false


func _run() -> void:
	BrowserSave.clear()
	var packed: PackedScene = load("res://scenes/Main.tscn")
	main = packed.instantiate()
	root.add_child(main)
	await physics_frame
	await physics_frame

	# Boot: day 1 never bills (rollover-only, like rent).
	_ok(_power_txs(1).is_empty(), "day 1 charges no power")

	# A one-printer shop is billed $1.00, rent charges alongside.
	main._on_day_changed(2)
	var t2 := _power_txs(2)
	_ok(t2.size() == 1 and int(t2[0]["delta_cents"]) == -100,
		"a one-printer shop is billed $1.00 at rollover")
	_ok(_has_rent_tx(2), "rent still charges alongside power")

	# The farm scales the bill: unlock through the real upgrade path.
	main.ledger.credit(30000, "test funds")
	main._on_menu_upgrade_buy("pro_machine")  # printer 2
	main._on_menu_upgrade_buy("farm_kit_a")  # printer 3
	main._on_menu_upgrade_buy("farm_kit_b")  # printer 4
	_ok(main._unlocked_machine_count() == 4, "three purchases unlock the full farm")
	main._on_day_changed(3)
	var t3 := _power_txs(3)
	_ok(t3.size() == 1 and int(t3[0]["delta_cents"]) == -400,
		"a four-printer farm is billed $4.00 at rollover")

	# A rent holiday skips rent but not power (week-agnostic: find a day).
	var holiday := -1
	for d in range(2, 61):
		if bool(load("res://scripts/Events.gd").for_day(d).rent_free):
			holiday = d
			break
	_ok(holiday > 0, "a rent holiday exists within 60 days")
	main.day_cycle.day = holiday
	main._on_day_changed(holiday)
	_ok(_power_txs(holiday).size() == 1, "power bills on a rent holiday too")
	_ok(not _has_rent_tx(holiday), "the holiday skips rent")

	# Broke: nothing charged, nothing owed for power; rent still goes to debt.
	main.ledger.charge(main.ledger.balance(), "test drain")
	var debt_before: int = int(main.rent_debt_cents)
	main.day_cycle.day = holiday + 1
	main._on_day_changed(holiday + 1)
	_ok(_power_txs(holiday + 1).is_empty(), "a broke shop is not billed (runs dark)")
	_ok(int(main.rent_debt_cents) > debt_before,
		"rent debt still accrues for the unpaid morning")

	# The morning log records the bill for the Today panel recap.
	var saw_power := false
	for e in main.workshop_log.entries():
		if str(e.get("kind")) == "power":
			saw_power = true
	_ok(saw_power, "the workshop log carries a power entry")

	BrowserSave.clear()
	print("---")
	print("checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)
