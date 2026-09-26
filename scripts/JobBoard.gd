extends Node

## Task 09 — contract job board. Serves Contract objects (task 08 fixtures).
## Deterministic: fixture list refills in rotated order when drained.

var _queue: Array[Contract] = []
var _fixture_cycle := 0

func _ready() -> void:
	_fill_to_capacity()

func _refill() -> void:
	# Append ONE next fixture job (rotated deterministic order). Duplicated:
	# the shared fixture Resources must never be mutated — a checked-out
	# contract's state would otherwise be clobbered by a later refill.
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
	var capacity := Contract.make_fixture_jobs().size()
	if _queue.is_empty():
		_fill_to_capacity()
	var c: Contract = _queue.pop_front()
	_fill_to_capacity()
	return c

func _fill_to_capacity() -> void:
	# Top the queue back up to at most fixture capacity so the board count
	# is invariant (existing suites rely on this) and the loop never drains;
	# refill order cycles deterministically through the fixture set.
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

## HUD summaries: {id, client, model_name, payout_cents, difficulty, risk_flags}.
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
		})
	return out
