extends Node

## Task 09 — contract job board. Serves Contract objects.
## Two modes:
##   fixture mode (default): the fixed 8-job pool rotates deterministically.
##   generation mode (v0.4.0, `generation_enabled = true`): procedurally
##     generated contracts, deterministic per shop day; `rotate_day(day)`
##     deals fresh work each morning. Main enables this for the live shop;
##     suites that build a JobBoard directly keep fixture behavior.
##
## Board pressure (v0.14.0): the board is first come, first served. Calm jobs
## CARRY OVER across mornings instead of being wiped; rush/competing offers
## expire overnight (Contract.has_expired_for) and are replaced by fresh
## deals. rotate_day returns the expired contracts so Main can charge the
## reputation cost. The full queue state persists via snapshot_payload()/
## restore_payload() so a save/reload mid-day reproduces the exact board.

var _queue: Array[Contract] = []
var _fixture_cycle := 0
## Enabling generation mid-flight (suites do this after _ready) drops any
## fixture-mode offers — they are not generated-board deals and would
## otherwise clog the queue past every rollover.
var generation_enabled := false:
	set(value):
		if generation_enabled == value:
			return
		generation_enabled = value
		if value:
			_queue.clear()
			_fixture_cycle = 0
var _gen_day := 1
var _capacity := 0  # cached fixture-pool size (set on first fill)
## Reputation-tier deal terms (v0.19.0): generated refills cap at this
## difficulty and scale rush payouts. Defaults reproduce the uncapped board.
var _deal_cap := 5
var _deal_rush_mult := 1.0


## Fresh morning deal (v0.19.0, boot path): clear and deal a full board at
## the given tier terms. Resets the deal cycle so a re-deal reproduces the
## day's canonical slots (0..7), not a continuation.
func deal_day(day: int, max_difficulty := 5, rush_mult := 1.0) -> void:
	if not generation_enabled:
		return
	_queue.clear()
	_fixture_cycle = 0
	_gen_day = maxi(day, 1)
	_deal_cap = clampi(max_difficulty, 1, 5)
	_deal_rush_mult = maxf(rush_mult, 1.0)
	_fill_to_capacity()

func _ready() -> void:
	_fill_to_capacity()

## Morning rollover. Expire overnight offers (rush/competing dealt before
## `day`), keep everything else, then top back up with fresh deals stamped
## for the new day. `apply_expiry = false` deals a fresh board without
## penalties (save-load path). `max_difficulty`/`rush_mult` (v0.19.0) update
## the reputation-tier deal terms when >= 0/-1; refills use them from here
## on. Returns the expired contracts, oldest first.
func rotate_day(day: int, apply_expiry := true, max_difficulty := -1, rush_mult := -1.0) -> Array:
	if not generation_enabled:
		return []
	var expired: Array = []
	if apply_expiry:
		for c in _queue:
			if c.has_expired_for(maxi(day, 1)):
				expired.append(c)
	for c in expired:
		_queue.erase(c)
	if max_difficulty > 0:
		_deal_cap = clampi(max_difficulty, 1, 5)
	if rush_mult > 0.0:
		_deal_rush_mult = maxf(rush_mult, 1.0)
	_gen_day = maxi(day, 1)
	_fill_to_capacity()
	return expired

func _refill() -> void:
	# Append ONE next job (rotated deterministic order). In fixture mode the
	# shared fixture Resources must never be mutated — a checked-out
	# contract's state would otherwise be clobbered by a later refill —
	# so they are duplicated. Generated contracts are fresh objects already.
	if generation_enabled:
		var g: Contract = Contract.generate(_gen_day, _fixture_cycle, _deal_cap)
		g.state = Contract.State.OFFERED
		# Tier rush premium (v0.19.0): scaled at deal time so pinned
		# Contract.generate values stay untouched.
		if g.rush and _deal_rush_mult > 1.0:
			g.payout_cents = mini(roundi(float(g.payout_cents) * _deal_rush_mult), 9500)
		_queue.append(g)
		_fixture_cycle += 1
		return
	var fixtures: Array = Contract.make_fixture_jobs()
	var idx := _fixture_cycle % fixtures.size()
	var c: Contract = fixtures[idx].duplicate()
	c.state = Contract.State.OFFERED
	_queue.append(c)
	_fixture_cycle += 1

func has_available() -> bool:
	return not _queue.is_empty()

func get_available_count() -> int:
	return _queue.size()

## How many queued jobs would expire rolling into `day` (HUD "expire tonight").
func expiring_count(day: int) -> int:
	var n := 0
	for c in _queue:
		if c.has_expired_for(maxi(day, 1)):
			n += 1
	return n

func take_next() -> Contract:
	if _queue.is_empty():
		_fill_to_capacity()
	var c: Contract = _queue.pop_front()
	_fill_to_capacity()
	return c

func _fill_to_capacity() -> void:
	# Top the queue back up to board capacity (fixture pool size) so the count
	# is invariant (existing suites rely on this) and the loop never drains;
	# refill order cycles deterministically. Capacity is cached: building the
	# fixture list on every refill was pure waste.
	if _capacity == 0:
		_capacity = Contract.make_fixture_jobs().size()
	while _queue.size() < _capacity:
		_refill()

## Return an unstarted job to the front (acceptance was refused, e.g. funds).
func put_back(c: Contract) -> void:
	_queue.push_front(c)

## Move an already-queued contract to the front in place (no take/refill).
## This is "Reserve" from the contracts menu: the next printer accept takes it.
func rotate_to_front(c: Contract) -> bool:
	var idx := _queue.find(c)
	if idx < 0:
		return false
	if idx > 0:
		_queue.remove_at(idx)
		_queue.push_front(c)
	return true

## Id of the job currently at the front of the queue ("" when empty).
func front_id() -> String:
	return _queue[0].id if not _queue.is_empty() else ""

## HUD summaries: {id, client, model_name, payout_cents, difficulty, risk_flags,
## rush, deadline_days, color, competing}.
func available_summaries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for c in _queue:
		out.append({
			"id": c.id,
			"client": c.client,
			"model_name": c.model_name,
			"payout_cents": c.payout_cents,
			"difficulty": c.difficulty,
			"risk_flags": c.risk_flags,
			"rush": c.rush,
			"deadline_days": c.deadline_days,
			"color": c.color,
			"competing": c.competing,
			"parts_total": c.parts_total,
		})
	return out

## --- persistence (v0.14.0) ----------------------------------------------------
##
## The queue is NOT re-derivable from (day, slot) once jobs have been taken or
## have rolled over, so the board serializes itself for the save payload.
## Plain dictionaries of Contract fields; restore rebuilds OFFERED contracts.

func snapshot_payload() -> Dictionary:
	var jobs: Array = []
	for c in _queue:
		jobs.append({
			"id": c.id,
			"client": c.client,
			"model_name": c.model_name,
			"payout_cents": c.payout_cents,
			"material_cost_cents": c.material_cost_cents,
			"difficulty": c.difficulty,
			"risk_flags": c.risk_flags.duplicate(),
			"layers": c.layers,
			"deadline_days": c.deadline_days,
			"rush": c.rush,
			"competing": c.competing,
			"offered_day": c.offered_day,
			"color": c.color,
			"parts_total": c.parts_total,
		})
	return {"day": _gen_day, "cycle": _fixture_cycle, "jobs": jobs}

## Rebuild the board from snapshot_payload() data. Whole-float coercion for
## JSON round-trips. Returns false WITHOUT touching the board on any
## malformed input; unknown ids in the cycle counter are tolerated (the
## generator is total over (day, slot)).
func restore_payload(data: Variant) -> bool:
	if not (data is Dictionary):
		return false
	var d: Dictionary = data
	if not d.has_all(["day", "cycle", "jobs"]):
		return false
	if not _whole_int(d["day"]) or int(d["day"]) < 1:
		return false
	if not _whole_int(d["cycle"]) or int(d["cycle"]) < 0:
		return false
	if typeof(d["jobs"]) != TYPE_ARRAY:
		return false
	var parsed: Array[Contract] = []
	for j in d["jobs"]:
		var c := _contract_from(j)
		if c == null:
			return false
		parsed.append(c)
	_queue.clear()
	for c in parsed:
		_queue.append(c)
	_gen_day = int(d["day"])
	_fixture_cycle = int(d["cycle"])
	_fill_to_capacity()
	return true

## Strict-ish shape check for one serialized job; null = reject.
static func _contract_from(j: Variant) -> Contract:
	if not (j is Dictionary):
		return null
	var d: Dictionary = j
	for key in ["id", "client", "model_name", "payout_cents", "material_cost_cents",
			"difficulty", "risk_flags", "layers", "deadline_days", "rush",
			"competing", "offered_day", "color"]:
		if not d.has(key):
			return null
	for key in ["id", "client", "model_name"]:
		if not (d[key] is String) or (d[key] as String).is_empty():
			return null
	for key in ["payout_cents", "material_cost_cents", "layers", "deadline_days", "offered_day"]:
		if not _whole_int(d[key]) or int(d[key]) < 0:
			return null
	if not _whole_int(d["difficulty"]) or int(d["difficulty"]) < 1 or int(d["difficulty"]) > 5:
		return null
	if int(d["payout_cents"]) <= 0 or int(d["layers"]) <= 0:
		return null
	if not (d["rush"] is bool) or not (d["competing"] is bool):
		return null
	if int(d["offered_day"]) < 1:
		return null
	if not (d["color"] is String) or ((d["color"] as String) != "" \
			and not ((d["color"] as String) in Contract.VALID_COLORS)):
		return null
	if typeof(d["risk_flags"]) != TYPE_ARRAY:
		return null
	# parts_total arrived with v0.18.0 — older saves omit it and restore as
	# single-part. When present it must be a whole int in 1..3.
	var parts := 1
	if d.has("parts_total"):
		if not _whole_int(d["parts_total"]):
			return null
		parts = int(d["parts_total"])
		if parts < 1 or parts > 3:
			return null
	var flags: Array[String] = []
	for f in d["risk_flags"]:
		if not (f is String) or not (f as String in Contract.VALID_RISK_FLAGS):
			return null
		flags.append(f)
	var c := Contract.new()
	c.id = d["id"]
	c.client = d["client"]
	c.model_name = d["model_name"]
	c.payout_cents = int(d["payout_cents"])
	c.material_cost_cents = int(d["material_cost_cents"])
	c.difficulty = int(d["difficulty"])
	c.risk_flags = flags
	c.layers = int(d["layers"])
	c.deadline_days = int(d["deadline_days"])
	c.rush = d["rush"]
	c.competing = d["competing"]
	c.offered_day = int(d["offered_day"])
	c.color = d["color"]
	c.parts_total = parts
	c.state = Contract.State.OFFERED
	return c

static func _whole_int(v: Variant) -> bool:
	if typeof(v) == TYPE_INT:
		return true
	if typeof(v) == TYPE_FLOAT:
		var f: float = v
		return is_equal_approx(f, floorf(f)) and is_finite(f)
	return false
