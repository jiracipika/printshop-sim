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
##     "reputation": float 0..5 (optional),
##     "stats": Dictionary of non-negative int counters (optional),
##     "filament": Array[int] grams per machine (optional),
##     "spool_colors": Array[String] per machine (optional),
##     "guide_done"/"guide_flags": onboarding progress (optional),
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
	if not _reputation_valid(p):
		return {}
	if not _stats_valid(p):
		return {}
	if not _filament_valid(p):
		return {}
	if not _spool_colors_valid(p):
		return {}
	if not _guide_valid(p):
		return {}
	if not _crate_next_valid(p):
		return {}
	if not _board_valid(p):
		return {}
	if not _log_valid(p):
		return {}
	if not _achv_toasted_valid(p):
		return {}
	if not _stations_heard_valid(p):
		return {}
	if not _recent_grades_valid(p):
		return {}
	if not _daily_earned_valid(p):
		return {}
	if not _client_orders_valid(p):
		return {}
	if not _client_grades_valid(p):
		return {}
	if not _media_a_valid(p):
		return {}
	if not _walkins_served_valid(p):
		return {}
	if not _wear_valid(p):
		return {}
	if not _cleans_valid(p):
		return {}
	if not _day_earned_valid(p):
		return {}
	if not _daily_delivered_valid(p):
		return {}
	if not _day_delivered_valid(p):
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
	if s.has("shadows") and not (s["shadows"] is bool):
		return false
	if s.has("music_volume") and not (_is_int(s["music_volume"]) \
			or s["music_volume"] is float):
		return false
	if s.has("music_volume") and (float(s["music_volume"]) < 0.0 or float(s["music_volume"]) > 1.0):
		return false
	if s.has("music_enabled") and not (s["music_enabled"] is bool):
		return false
	if s.has("quality_preset") and not (s["quality_preset"] is String):
		return false
	if s.has("quality_preset") and not (s["quality_preset"] in ["Low", "Standard", "High"]):
		return false
	if s.has("haptics") and not (s["haptics"] is bool):
		return false
	if s.has("radio_station"):
		var t2 := typeof(s["radio_station"])
		if t2 != TYPE_INT and t2 != TYPE_FLOAT:
			return false
		var rs := float(s["radio_station"])
		# Station dial: 0..3 since v0.55.0 added the fourth station (Jazz).
		if rs != floorf(rs) or rs < 0.0 or rs > 3.0:
			return false
	if s.has("haptics_strength"):
		var t3 := typeof(s["haptics_strength"])
		if t3 != TYPE_INT and t3 != TYPE_FLOAT:
			return false
		var hs := float(s["haptics_strength"])
		if hs != floorf(hs) or hs < 0.0 or hs > 100.0:
			return false
	if s.has("calm_mode") and not (s["calm_mode"] is bool):
		return false
	return true


## Optional "daily_earned" key (v0.30.0): absent = fine; present must be an
## array of at most 7 non-negative whole ints.
static func _daily_earned_valid(p: Dictionary) -> bool:
	if not p.has("daily_earned"):
		return true
	if typeof(p["daily_earned"]) != TYPE_ARRAY:
		return false
	if p["daily_earned"].size() > 7:
		return false
	for v in p["daily_earned"]:
		var t := typeof(v)
		if t != TYPE_INT and t != TYPE_FLOAT:
			return false
		var f := float(v)
		if f != floorf(f) or f < 0.0:
			return false
	return true


## Optional "day_earned_today" key (v0.30.0): absent = fine; present must be
## a non-negative whole int.
static func _day_earned_valid(p: Dictionary) -> bool:
	if not p.has("day_earned_today"):
		return true
	var t := typeof(p["day_earned_today"])
	if t != TYPE_INT and t != TYPE_FLOAT:
		return false
	var f := float(p["day_earned_today"])
	return f == floorf(f) and f >= 0.0


## Optional "media_a_deliveries" key (v0.43.0): absent = fine; present
## must be a non-negative whole int.
static func _media_a_valid(p: Dictionary) -> bool:
	if not p.has("media_a_deliveries"):
		return true
	var t := typeof(p["media_a_deliveries"])
	if t != TYPE_INT and t != TYPE_FLOAT:
		return false
	var f := float(p["media_a_deliveries"])
	return f == floorf(f) and f >= 0.0


## Optional "walkins_served" key (v0.59.0): absent = fine; present must be
## a non-negative whole int. (media_a_deliveries pattern.)
static func _walkins_served_valid(p: Dictionary) -> bool:
	if not p.has("walkins_served"):
		return true
	var t := typeof(p["walkins_served"])
	if t != TYPE_INT and t != TYPE_FLOAT:
		return false
	var f := float(p["walkins_served"])
	return f == floorf(f) and f >= 0.0


## Optional "wear" key (v0.45.0): array of per-machine wear percents 0..100.
static func _wear_valid(p: Dictionary) -> bool:
	if not p.has("wear"):
		return true
	if typeof(p["wear"]) != TYPE_ARRAY:
		return false
	for w in p["wear"]:
		var t := typeof(w)
		if t != TYPE_INT and t != TYPE_FLOAT:
			return false
		var f := float(w)
		if f != floorf(f) or f < 0.0 or f > 100.0:
			return false
	return true


## Optional "cleans" key (v0.45.0): non-negative whole count.
static func _cleans_valid(p: Dictionary) -> bool:
	if not p.has("cleans"):
		return true
	var t := typeof(p["cleans"])
	if t != TYPE_INT and t != TYPE_FLOAT:
		return false
	var f := float(p["cleans"])
	return f == floorf(f) and f >= 0.0


## Optional "daily_delivered" key (v0.47.0): weekly window of per-day order
## counts — same shape rules as daily_earned.
static func _daily_delivered_valid(p: Dictionary) -> bool:
	if not p.has("daily_delivered"):
		return true
	if typeof(p["daily_delivered"]) != TYPE_ARRAY:
		return false
	if p["daily_delivered"].size() > 7:
		return false
	for v in p["daily_delivered"]:
		var t := typeof(v)
		if t != TYPE_INT and t != TYPE_FLOAT:
			return false
		var f := float(v)
		if f != floorf(f) or f < 0.0:
			return false
	return true


## Optional "day_delivered_today" key (v0.47.0): non-negative whole count.
static func _day_delivered_valid(p: Dictionary) -> bool:
	if not p.has("day_delivered_today"):
		return true
	var t := typeof(p["day_delivered_today"])
	if t != TYPE_INT and t != TYPE_FLOAT:
		return false
	var f := float(p["day_delivered_today"])
	return f == floorf(f) and f >= 0.0


## Optional "client_last_grade" key (v0.38.0): absent = fine; present must
## be a dictionary of non-empty names -> grade letters (no F: failed parts
## were never delivered).
static func _client_grades_valid(p: Dictionary) -> bool:
	if not p.has("client_last_grade"):
		return true
	if typeof(p["client_last_grade"]) != TYPE_DICTIONARY:
		return false
	if p["client_last_grade"].size() > 40:
		return false
	for k in p["client_last_grade"]:
		if not (k is String) or (k as String).is_empty():
			return false
		if not (str(p["client_last_grade"][k]) in ["A", "B", "C", "D"]):
			return false
	return true


## Optional "client_orders" key (v0.31.0): absent = fine; present must be a
## dictionary of non-empty client names -> whole-int counts 1..999.
static func _client_orders_valid(p: Dictionary) -> bool:
	if not p.has("client_orders"):
		return true
	if typeof(p["client_orders"]) != TYPE_DICTIONARY:
		return false
	if p["client_orders"].size() > 40:
		return false
	for k in p["client_orders"]:
		if not (k is String) or (k as String).is_empty():
			return false
		var t := typeof(p["client_orders"][k])
		if t != TYPE_INT and t != TYPE_FLOAT:
			return false
		var f := float(p["client_orders"][k])
		if f != floorf(f) or f < 1.0 or f > 999.0:
			return false
	return true


## Optional "recent_grades" key (v0.23.0): absent = fine; present must be an
## array of at most 5 grade letters.
static func _recent_grades_valid(p: Dictionary) -> bool:
	if not p.has("recent_grades"):
		return true
	if typeof(p["recent_grades"]) != TYPE_ARRAY:
		return false
	if p["recent_grades"].size() > 5:
		return false
	for v in p["recent_grades"]:
		if not (v is String) or not (v in ["A", "B", "C", "D", "F"]):
			return false
	return true


## Optional "stations_heard" key (v0.22.0): absent = fine; present must be
## an array of station indexes 0..3 (at most 4 since v0.55.0 added the
## fourth station, duplicates tolerated-read).
static func _stations_heard_valid(p: Dictionary) -> bool:
	if not p.has("stations_heard"):
		return true
	if typeof(p["stations_heard"]) != TYPE_ARRAY:
		return false
	if p["stations_heard"].size() > 4:
		return false
	for v in p["stations_heard"]:
		var t := typeof(v)
		if t != TYPE_INT and t != TYPE_FLOAT:
			return false
		var f := float(v)
		if f != floorf(f) or f < 0.0 or f > 3.0:
			return false
	return true


## Optional "achv_toasted" key (v0.21.0): absent = fine; present must be an
## array of up to 40 milestone name strings.
static func _achv_toasted_valid(p: Dictionary) -> bool:
	if not p.has("achv_toasted"):
		return true
	if typeof(p["achv_toasted"]) != TYPE_ARRAY:
		return false
	if p["achv_toasted"].size() > 40:
		return false
	for v in p["achv_toasted"]:
		if not (v is String):
			return false
	return true


## Optional "day" key: absent = fine; present must be an int >= 1.
static func _day_valid(p: Dictionary) -> bool:
	if not p.has("day"):
		return true
	return _is_int(p["day"]) and int(p["day"]) >= 1


## Optional "reputation" key: numeric in [0, 5].
static func _reputation_valid(p: Dictionary) -> bool:
	if not p.has("reputation"):
		return true
	var t := typeof(p["reputation"])
	if t != TYPE_FLOAT and t != TYPE_INT:
		return false
	return float(p["reputation"]) >= 0.0 and float(p["reputation"]) <= 5.0


## Optional "filament" key: array of non-negative gram counts per machine.
static func _filament_valid(p: Dictionary) -> bool:
	if not p.has("filament"):
		return true
	if typeof(p["filament"]) != TYPE_ARRAY:
		return false
	for g in p["filament"]:
		if not _is_int(g) or int(g) < 0:
			return false
	return true


## Optional "crate_next" key: non-negative int crate-rotation counter.
static func _crate_next_valid(p: Dictionary) -> bool:
	if not p.has("crate_next"):
		return true
	return _is_int(p["crate_next"]) and int(p["crate_next"]) >= 0


## Optional guide keys: "guide_done" bool, "guide_flags" dict of bools.
static func _guide_valid(p: Dictionary) -> bool:
	if p.has("guide_done") and not (p["guide_done"] is bool):
		return false
	if p.has("guide_flags"):
		if typeof(p["guide_flags"]) != TYPE_DICTIONARY:
			return false
		for v in p["guide_flags"].values():
			if not (v is bool):
				return false
	return true


## Optional "spool_colors" key: array of known color names (or "").
static func _spool_colors_valid(p: Dictionary) -> bool:
	if not p.has("spool_colors"):
		return true
	if typeof(p["spool_colors"]) != TYPE_ARRAY:
		return false
	for c in p["spool_colors"]:
		if not (c is String):
			return false
	return true


## Optional "board" key (v0.14.0): job-board persistence —
## {day: int>=1, cycle: int>=0, jobs: Array[job-dict]}. Job dicts carry the
## Contract fields (see JobBoard.snapshot_payload); each must type-check and
## satisfy Contract.is_valid's ranges or the whole payload is rejected.
static func _board_valid(p: Dictionary) -> bool:
	if not p.has("board"):
		return true
	var b: Dictionary = p["board"]
	if typeof(b) != TYPE_DICTIONARY:
		return false
	if not b.has_all(["day", "cycle", "jobs"]):
		return false
	if not _is_int(b["day"]) or int(b["day"]) < 1:
		return false
	if not _is_int(b["cycle"]) or int(b["cycle"]) < 0:
		return false
	if typeof(b["jobs"]) != TYPE_ARRAY:
		return false
	for j in b["jobs"]:
		if typeof(j) != TYPE_DICTIONARY:
			return false
		var job: Dictionary = j
		for key in ["id", "client", "model_name", "payout_cents", "material_cost_cents",
				"difficulty", "risk_flags", "layers", "deadline_days", "rush",
				"competing", "offered_day", "color"]:
			if not job.has(key):
				return false
		for key in ["id", "client", "model_name", "color"]:
			if not (job[key] is String):
				return false
		for key in ["id", "client", "model_name"]:
			if (job[key] as String).is_empty():
				return false
		for key in ["payout_cents", "material_cost_cents", "layers", "deadline_days", "offered_day"]:
			if not _is_int(job[key]) or int(job[key]) < 0:
				return false
		if not _is_int(job["difficulty"]) or int(job["difficulty"]) < 1 or int(job["difficulty"]) > 5:
			return false
		if int(job["payout_cents"]) <= 0 or int(job["layers"]) <= 0:
			return false
		if int(job["offered_day"]) < 1:
			return false
		if not (job["rush"] is bool) or not (job["competing"] is bool):
			return false
		if (job["color"] as String) != "" and not ((job["color"] as String) in Contract.VALID_COLORS):
			return false
		if typeof(job["risk_flags"]) != TYPE_ARRAY:
			return false
		for f in job["risk_flags"]:
			if not (f is String) or not (f as String in Contract.VALID_RISK_FLAGS):
				return false
	return true


## Optional "log" key (v0.15.0): workshop-log ring buffer — Array of
## {seq, day, kind, text} entries. Types/ranges must check; more than CAP
## (30) entries is tolerated (restore keeps the newest CAP).
static func _log_valid(p: Dictionary) -> bool:
	if not p.has("log"):
		return true
	if typeof(p["log"]) != TYPE_ARRAY:
		return false
	for e in p["log"]:
		if typeof(e) != TYPE_DICTIONARY:
			return false
		var d: Dictionary = e
		if not d.has_all(["seq", "day", "kind", "text"]):
			return false
		if not _is_int(d["seq"]):
			return false
		if not _is_int(d["day"]) or int(d["day"]) < 1:
			return false
		if not (d["kind"] is String) or (d["kind"] as String).is_empty():
			return false
		if not (d["text"] is String):
			return false
	return true


## Optional "stats" key: dict of known non-negative int counters.
const STAT_KEYS: Array[String] = ["delivered", "late", "scrapped", "cancelled", "earned_cents", "missed", "lost_walkins"]

static func _stats_valid(p: Dictionary) -> bool:
	if not p.has("stats"):
		return true
	if typeof(p["stats"]) != TYPE_DICTIONARY:
		return false
	var st: Dictionary = p["stats"]
	for key in STAT_KEYS:
		if not st.has(key):
			continue
		if not _is_int(st[key]) or int(st[key]) < 0:
			return false
	return true


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
