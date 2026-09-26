class_name SaveSystem
extends RefCounted

## Task 12 (save portion) — versioned save payload builder/validator.
## Pure logic, no file I/O (see BrowserSave.gd) and no gameplay symbols;
## Main integration is a parent follow-up.
##
## Payload shape (VERSION 1):
##   {
##     "version": 1,
##     "balance_cents": int,
##     "ledger": Ledger.snapshot() shape — validated down to transaction level,
##     "active_contract": Dictionary (may be {}),
##     "paid_ids": Array[String] (redundant mirror of ledger.paid_contract_ids),
##     "saved_at_unix": int,
##     "upgrades": Array[String] (optional — owned upgrade ids),
##     "settings": Dictionary (optional — {mouse_sens_scale, sfx_volume, invert_y}),
##     "day": int >= 1 (optional — shop day counter),
##   }
##
## Optional keys are additive: payloads without them stay valid (older saves
## keep loading), and validate() rejects them only when malformed (wrong
## types, negative/zero scale, out-of-range volume, non-string ids).
##
## validate() returns a normalized deep copy of the payload, or {} if anything
## is malformed. It never throws on garbage input (fuzz-tested).

const VERSION := 1


## Build a v1 payload. Deep-copies inputs so later mutation of the caller's
## dictionaries cannot corrupt the payload. `extras` may carry "upgrades"
## (Array[String]) and "settings" (Dictionary); unknown extra keys are kept
## verbatim and must still pass validate().
static func build_payload(
		ledger_snapshot: Dictionary, active_contract: Dictionary,
		balance_cents: int, paid_ids: Array, extras: Dictionary = {}) -> Dictionary:
	var paid: Array = []
	for id in paid_ids:
		paid.append(str(id))
	var payload := {
		"version": VERSION,
		"balance_cents": int(balance_cents),
		"ledger": ledger_snapshot.duplicate(true),
		"active_contract": active_contract.duplicate(true),
		"paid_ids": paid,
		"saved_at_unix": int(Time.get_unix_time_from_system()),
	}
	for key in extras:
		payload[key] = extras[key].duplicate(true) if extras[key] is Array \
			or extras[key] is Dictionary else extras[key]
	return payload


## Defensive validation. Returns {} for ANY malformed input (wrong version
## type/value, negative balance, non-dict ledger, malformed transactions,
## non-array paid_ids, non-dict payload itself, arbitrary junk); otherwise a
## normalized deep copy. Never throws.
##
## JSON tolerance: JSON.parse_string yields floats for every number. Whole
## floats are coerced to int (and normalized into the output) so a payload
## read from disk validates; fractional or non-numeric values are rejected.
static func validate(payload: Variant) -> Dictionary:
	if not (payload is Dictionary):
		return {}
	var p: Dictionary = payload
	if not _is_int(p.get("version")) or int(p["version"]) != VERSION:
		return {}
	if not _is_int(p.get("balance_cents")) or int(p["balance_cents"]) < 0:
		return {}
	if typeof(p.get("ledger")) != TYPE_DICTIONARY:
		return {}
	if typeof(p.get("active_contract")) != TYPE_DICTIONARY:
		return {}
	if typeof(p.get("paid_ids")) != TYPE_ARRAY:
		return {}
	if not _ledger_valid(p["ledger"]):
		return {}
	for id in p["paid_ids"]:
		if not (id is String) or id.is_empty():
			return {}
	if not _upgrades_valid(p):
		return {}
	if not _settings_valid(p):
		return {}
	if not _day_valid(p):
		return {}

	var out: Dictionary = p.duplicate(true)
	out["version"] = int(p["version"])
	out["balance_cents"] = int(p["balance_cents"])
	var led: Dictionary = out["ledger"]
	led["balance_cents"] = int(p["ledger"]["balance_cents"])
	led["next_seq"] = int(p["ledger"]["next_seq"])
	var txs: Array = led["transactions"]
	for i in txs.size():
		var tx: Dictionary = txs[i]
		tx["id"] = int(tx["id"])
		tx["delta_cents"] = int(tx["delta_cents"])
		tx["balance_after"] = int(tx["balance_after"])
	return out


## Optional "upgrades" key: absent = fine; present must be Array[String] of
## non-empty ids.
static func _upgrades_valid(p: Dictionary) -> bool:
	if not p.has("upgrades"):
		return true
	if typeof(p["upgrades"]) != TYPE_ARRAY:
		return false
	for id in p["upgrades"]:
		if not (id is String) or id.is_empty():
			return false
	return true


## Optional "settings" key: absent = fine; present must be a Dictionary whose
## known keys type-check (positive float scale, float volume in [0,1], bool
## invert). Unknown keys are tolerated and preserved.
static func _settings_valid(p: Dictionary) -> bool:
	if not p.has("settings"):
		return true
	if typeof(p["settings"]) != TYPE_DICTIONARY:
		return false
	var s: Dictionary = p["settings"]
	if s.has("mouse_sens_scale") and not (_is_int(s["mouse_sens_scale"]) \
			or s["mouse_sens_scale"] is float):
		return false
	if s.has("mouse_sens_scale") and float(s["mouse_sens_scale"]) <= 0.0:
		return false
	if s.has("sfx_volume") and not (_is_int(s["sfx_volume"]) or s["sfx_volume"] is float):
		return false
	if s.has("sfx_volume") and (float(s["sfx_volume"]) < 0.0 or float(s["sfx_volume"]) > 1.0):
		return false
	if s.has("invert_y") and not (s["invert_y"] is bool):
		return false
	return true


## Optional "day" key: absent = fine; present must be an int >= 1.
static func _day_valid(p: Dictionary) -> bool:
	if not p.has("day"):
		return true
	return _is_int(p["day"]) and int(p["day"]) >= 1


## True for TYPE_INT or a float with an exactly integral value.
static func _is_int(v: Variant) -> bool:
	if typeof(v) == TYPE_INT:
		return true
	if typeof(v) == TYPE_FLOAT:
		var f: float = v
		return is_equal_approx(f, floorf(f)) and is_finite(f)
	return false


## Ledger snapshot shape check, aligned with Ledger.snapshot()/restore()
## (scripts/Ledger.gd): all four keys, non-negative balance, transactions
## form a coherent chain whose replay equals the balance, paid ids are
## non-empty strings.
static func _ledger_valid(led: Dictionary) -> bool:
	if not led.has_all(["balance_cents", "transactions", "paid_contract_ids", "next_seq"]):
		return false
	if not _is_int(led["balance_cents"]) or int(led["balance_cents"]) < 0:
		return false
	if typeof(led["transactions"]) != TYPE_ARRAY:
		return false
	if typeof(led["paid_contract_ids"]) != TYPE_ARRAY:
		return false
	if not _is_int(led["next_seq"]):
		return false
	var running := 0
	for t in led["transactions"]:
		if typeof(t) != TYPE_DICTIONARY:
			return false
		var tx: Dictionary = t
		if not tx.has_all(["id", "reason", "delta_cents", "balance_after"]):
			return false
		if not _is_int(tx["id"]) or not _is_int(tx["delta_cents"]) \
				or not _is_int(tx["balance_after"]):
			return false
		running += int(tx["delta_cents"])
	if running != int(led["balance_cents"]):
		return false
	for k in led["paid_contract_ids"]:
		if not (k is String) or k.is_empty():
			return false
	return true
