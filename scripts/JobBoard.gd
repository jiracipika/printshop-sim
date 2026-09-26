extends Node

## Task 09 — contract job board. Serves Contract objects.
## Two modes:
##   fixture mode (default): the fixed 8-job pool rotates deterministically.
##   generation mode (v0.4.0, `generation_enabled = true`): procedurally
##     generated contracts, deterministic per shop day; `rotate_day(day)`
##     deals a fresh board each morning. Main enables this for the live shop;
##     suites that build a JobBoard directly keep fixture behavior.

var _queue: Array[Contract] = []
var _fixture_cycle := 0
var generation_enabled := false
var _gen_day := 1

func _ready() -> void:
	_fill_to_capacity()

## Point the board at a new shop day: clears the queue and refills from that
## day's deterministic generation. No-op in fixture mode.
func rotate_day(day: int) -> void:
	if not generation_enabled:
		return
	_gen_day = maxi(day, 1)
	_queue.clear()
	_fixture_cycle = 0
	_fill_to_capacity()

func _refill() -> void:
	# Append ONE next job (rotated deterministic order). In fixture mode the
	# shared fixture Resources must never be mutated — a checked-out
	# contract's state would otherwise be clobbered by a later refill —
	# so they are duplicated. Generated contracts are fresh objects already.
	if generation_enabled:
		var g: Contract = Contract.generate(_gen_day, _fixture_cycle)
		g.state = Contract.State.OFFERED
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

func take_next() -> Contract:
	if _queue.is_empty():
		_fill_to_capacity()
	var c: Contract = _queue.pop_front()
	_fill_to_capacity()
	return c

func _fill_to_capacity() -> void:
	# Top the queue back up to board capacity (fixture pool size) so the count
	# is invariant (existing suites rely on this) and the loop never drains;
	# refill order cycles deterministically.
	var capacity := Contract.make_fixture_jobs().size()
	while _queue.size() < capacity:
		_refill()

## Return an unstarted job to the front (acceptance was refused, e.g. funds).
func put_back(c: Contract) -> void:
	_queue.push_front(c)

## Move an already-queued contract to the front in place (no take/refill).
func rotate_to_front(c: Contract) -> bool:
	var idx := _queue.find(c)
	if idx < 0:
		return false
	_queue.remove_at(idx)
	_queue.push_front(c)
	return true

## HUD summaries: {id, client, model_name, payout_cents, difficulty, risk_flags, rush}.
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
		})
	return out
