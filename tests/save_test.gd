extends SceneTree

## Task 12 (save portion) — versioned save payload + browser persistence adapter.
## Run: timeout 60 godot --headless --path . -s tests/save_test.gd
## RED before scripts/SaveSystem.gd + scripts/BrowserSave.gd; GREEN after.
## Never touches Main.gd or gameplay symbols (integration is a parent follow-up).

var checks := 0
var failures := 0

const TEST_PATH := "user://printshop_save_test_v1.json"


func _ok(cond: bool, label: String) -> void:
	checks += 1
	if cond:
		print("ok %d: %s" % [checks, label])
	else:
		failures += 1
		printerr("FAIL %d: %s" % [checks, label])


func _sample_ledger_snapshot() -> Dictionary:
	return {
		"balance_cents": 3250,
		"transactions": [
			{"id": 1, "reason": "opening funds", "delta_cents": 2500, "balance_after": 2500},
			{"id": 2, "reason": "material C-014", "delta_cents": -840, "balance_after": 1660},
			{"id": 3, "reason": "payout C-014", "delta_cents": 6400, "balance_after": 8060},
			{"id": 4, "reason": "material C-015", "delta_cents": -4810, "balance_after": 3250},
		],
		"paid_contract_ids": ["C-014"],
		"next_seq": 4,
	}


func _sample_active_contract() -> Dictionary:
	return {
		"id": "C-015",
		"client": "Ellis / Repair cafe",
		"model_name": "Keep the cables tidy",
		"payout_cents": 4200,
		"material_cost_cents": 610,
		"difficulty": 1,
		"risk_flags": [],
		"layers": 120,
		"deadline_days": 3,
		"state": 2,
	}


func _sample_payload() -> Dictionary:
	return SaveSystem.build_payload(
		_sample_ledger_snapshot(), _sample_active_contract(), 3250, ["C-014"])


func _is_dict_equal(a: Dictionary, b: Dictionary) -> bool:
	return str(a) == str(b) or (a.hash() == b.hash())


func _init() -> void:
	_run()


func _finish(code: int) -> void:
	print("---")
	print("checks=%d failures=%d" % [checks, failures])
	quit(code)


func _run() -> void:
	_test_build_payload()
	_test_validate_accepts()
	_test_validate_rejects()
	_test_validate_fuzz_never_throws()
	_test_browser_save()
	_finish(1 if failures > 0 else 0)


# --- 1. build_payload shape ---
func _test_build_payload() -> void:
	var p := _sample_payload()
	_ok(p is Dictionary, "build_payload returns a Dictionary")
	_ok(int(p.get("version", -1)) == SaveSystem.VERSION,
		"payload version matches SaveSystem.VERSION")
	_ok(int(p.get("balance_cents", -1)) == 3250, "payload carries balance_cents")
	_ok(p.get("ledger", {}) is Dictionary
		and int(p["ledger"].get("balance_cents", -1)) == 3250,
		"payload embeds ledger snapshot")
	_ok(p.get("active_contract", null) is Dictionary
		and str(p["active_contract"].get("id", "")) == "C-015",
		"payload embeds active contract")
	_ok(p.get("paid_ids", []) is Array
		and p["paid_ids"] == ["C-014"], "payload carries paid_ids")
	_ok(p.get("saved_at_unix", -1) is int and int(p["saved_at_unix"]) > 0,
		"payload stamps saved_at_unix")
	# Empty active contract is legal.
	var p2 := SaveSystem.build_payload(_sample_ledger_snapshot(), {}, 3250, ["C-014"])
	_ok(p2 is Dictionary and (p2["active_contract"] as Dictionary).is_empty(),
		"build_payload allows empty active_contract")
	# Snapshot independence: mutating the payload must not touch the source.
	var snap := _sample_ledger_snapshot()
	var p3 := SaveSystem.build_payload(snap, {}, 100, [])
	p3["ledger"]["balance_cents"] = 999
	_ok(int(snap["balance_cents"]) == 3250 and int(p3["ledger"]["balance_cents"]) == 999,
		"build_payload deep-copies ledger snapshot")


# --- 2. validate accepts well-formed payloads (normalized copy) ---
func _test_validate_accepts() -> void:
	var p := _sample_payload()
	var v := SaveSystem.validate(p)
	_ok(not v.is_empty(), "validate accepts a well-formed payload")
	_ok(_is_dict_equal(v, p), "validate round-trips canonical fields unchanged")
	var v2 := SaveSystem.validate(SaveSystem.build_payload(_sample_ledger_snapshot(), {}, 0, []))
	_ok(not v2.is_empty(), "validate accepts zero balance and empty paid_ids")


# --- 3. validate rejects malformed payloads ---
func _test_validate_rejects() -> void:
	var p := _sample_payload()

	var bad := p.duplicate(true); bad["version"] = 0
	_ok(SaveSystem.validate(bad).is_empty(), "validate rejects version 0")

	bad = p.duplicate(true); bad["version"] = 99
	_ok(SaveSystem.validate(bad).is_empty(), "validate rejects version 99")

	bad = p.duplicate(true); bad["version"] = "1"
	_ok(SaveSystem.validate(bad).is_empty(), "validate rejects non-numeric version")

	bad = p.duplicate(true); bad["balance_cents"] = -1
	_ok(SaveSystem.validate(bad).is_empty(), "validate rejects negative balance")

	bad = p.duplicate(true); bad["ledger"] = "not a dict"
	_ok(SaveSystem.validate(bad).is_empty(), "validate rejects non-dict ledger")

	bad = p.duplicate(true)
	(bad["ledger"]["transactions"][1] as Dictionary).erase("balance_after")
	_ok(SaveSystem.validate(bad).is_empty(),
		"validate rejects ledger transaction missing balance_after")

	bad = p.duplicate(true); bad["paid_ids"] = "C-014"
	_ok(SaveSystem.validate(bad).is_empty(), "validate rejects non-array paid_ids")

	bad = p.duplicate(true); bad["paid_ids"] = [42]
	_ok(SaveSystem.validate(bad).is_empty(), "validate rejects non-string paid id")

	bad = p.duplicate(true); bad["paid_ids"] = [""]
	_ok(SaveSystem.validate(bad).is_empty(), "validate rejects empty-string paid id")

	bad = p.duplicate(true)
	(bad["ledger"]["transactions"][2] as Dictionary)["delta_cents"] = 999
	_ok(SaveSystem.validate(bad).is_empty(),
		"validate rejects transaction chain that disagrees with ledger balance")

	for junk in [null, 42, "string", [], [1, 2, 3], true]:
		_ok(SaveSystem.validate(junk).is_empty(),
			"validate rejects non-dict payload of type %s" % type_string(typeof(junk)))

	bad = p.duplicate(true); bad.erase("ledger")
	_ok(SaveSystem.validate(bad).is_empty(), "validate rejects missing ledger")

	bad = p.duplicate(true); bad["active_contract"] = 7
	_ok(SaveSystem.validate(bad).is_empty(), "validate rejects non-dict active_contract")


# --- 4. fuzz: validate never throws on adversarial garbage ---
func _test_validate_fuzz_never_throws() -> void:
	var shapes: Array = [
		{"version": 1.0, "balance_cents": 100.0, "ledger": {}, "active_contract": {},
			"paid_ids": [], "saved_at_unix": 1.0},
		{"version": 1, "ledger": {"balance_cents": 1, "transactions": [[]],
			"paid_contract_ids": [], "next_seq": 0}, "paid_ids": []},
		{"version": 1, "balance_cents": 5, "ledger": {"transactions": [
			{"id": "x", "reason": {}, "delta_cents": null, "balance_after": true}],
			"balance_cents": 0}, "paid_ids": []},
		{"version": {"nested": [1, 2, {"deep": SaveSystem}]}},
		{"version": 1, "balance_cents": true, "ledger": [], "paid_ids": [[]]},
		[[[[{"version": 1}]]]],
		{"version": 1, "balance_cents": 0, "ledger": {"balance_cents": 0,
			"transactions": [], "paid_contract_ids": "", "next_seq": null},
			"active_contract": [], "paid_ids": {"a": 1}, "saved_at_unix": "now"},
	]
	var threw := false
	for s in shapes:
		var v: Dictionary = SaveSystem.validate(s)  # must not script-error
		if not (v is Dictionary):
			threw = true
	_ok(not threw, "validate survives %d adversarial shapes without throwing" % shapes.size())


# --- 5. BrowserSave adapter round-trips, corruption fallback, cleanup ---
func _test_browser_save() -> void:
	BrowserSave.save_path = TEST_PATH
	BrowserSave.clear()
	_ok(not BrowserSave.exists(), "clear -> exists() false on fresh path")

	var payload := _sample_payload()
	_ok(BrowserSave.save_payload(payload), "save_payload returns true")
	_ok(BrowserSave.exists(), "exists() true after save")

	var loaded := BrowserSave.load_payload()
	_ok(not loaded.is_empty(), "load_payload reads back a payload")
	_ok(int(loaded.get("version", -1)) == SaveSystem.VERSION
		and int(loaded.get("balance_cents", -1)) == 3250
		and loaded.get("paid_ids", []) == ["C-014"]
		and str((loaded.get("active_contract", {}) as Dictionary).get("id", "")) == "C-015",
		"loaded canonical fields match saved payload")
	var led: Dictionary = loaded.get("ledger", {})
	_ok(int(led.get("balance_cents", -1)) == 3250
		and (led.get("transactions", []) as Array).size() == 4,
		"loaded ledger snapshot matches saved ledger")

	# Second save overwrites.
	var p2 := SaveSystem.build_payload(_sample_ledger_snapshot(), {}, 7777, ["C-014", "C-015"])
	_ok(BrowserSave.save_payload(p2), "second save_payload returns true")
	var loaded2 := BrowserSave.load_payload()
	_ok(int(loaded2.get("balance_cents", -1)) == 7777
		and (loaded2.get("paid_ids", []) as Array).size() == 2,
		"second save overwrites first")

	# Corrupt file -> {} without throwing.
	BrowserSave.corrupt_file_for_test()
	var corrupt := BrowserSave.load_payload()
	_ok(corrupt.is_empty(), "corrupt file -> load_payload returns empty dict")
	_ok(BrowserSave.exists(), "corrupt file still exists (not silently deleted)")

	# Missing file -> {}.
	BrowserSave.clear()
	_ok(BrowserSave.load_payload().is_empty(), "missing file -> load_payload returns empty dict")

	# No .tmp residual at any point.
	_ok(not FileAccess.file_exists(TEST_PATH + ".tmp"), "no .tmp residual after operations")

	# Path override isolation: default path untouched.
	_ok(BrowserSave.save_path == TEST_PATH, "save_path override holds for test isolation")
