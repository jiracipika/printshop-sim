extends SceneTree

## Contract + Ledger unit tests (task 08). Pure data/logic, no Main scene.
## Run: timeout 60 godot --headless -s tests/contract_test.gd
## Exits 0 on all checks passing, 1 on any failure.

const Contract := preload("res://scripts/Contract.gd")
const Ledger := preload("res://scripts/Ledger.gd")
const JobBoard := preload("res://scripts/JobBoard.gd")

var checks := 0
var failures := 0


func check(cond: bool, label: String) -> void:
	checks += 1
	if cond:
		print("ok %d: %s" % [checks, label])
	else:
		failures += 1
		printerr("FAIL %d: %s" % [checks, label])


func _init() -> void:
	root.ready.connect(_run)


func _run() -> void:
	_test_contract_validation()
	_test_state_path()
	_test_transition_table_probe()
	_test_failed_reachability()
	_test_fixtures()
	_test_expanded_fixtures_and_rush()
	_test_jobboard_rush_summaries()
	_test_ledger_basics()
	_test_ledger_exactly_once()
	_test_ledger_reconciliation_and_invariant()
	_test_snapshot_restore()
	print("---")
	print("checks=%d failures=%d" % [checks, failures])
	_finish(1 if failures > 0 else 0)


func _test_contract_validation() -> void:
	var c := Contract.new()
	c.id = "C-001"
	c.client = "Test Client"
	c.model_name = "Test Model"
	c.payout_cents = 6400
	c.material_cost_cents = 840
	c.difficulty = 1
	c.risk_flags = ["bed adhesion"]
	c.layers = 210
	c.deadline_days = 3
	check(c.is_valid(), "valid contract passes is_valid()")
	check(c.state == Contract.State.OFFERED, "new contract starts OFFERED")
	check(not c.is_terminal(), "OFFERED is not terminal")

	c.difficulty = 0
	check(not c.is_valid(), "difficulty 0 rejected")
	c.difficulty = 6
	check(not c.is_valid(), "difficulty 6 rejected")
	c.difficulty = 5
	check(c.is_valid(), "difficulty 5 accepted")
	c.difficulty = 1

	c.payout_cents = 0
	check(not c.is_valid(), "payout 0 rejected")
	c.payout_cents = -1
	check(not c.is_valid(), "negative payout rejected")
	c.payout_cents = 6400

	c.risk_flags = ["overhangs"]
	check(c.is_valid(), "known risk flag accepted")
	c.risk_flags = ["wingdings"]
	check(not c.is_valid(), "unknown risk flag rejected")
	c.risk_flags = ["overhangs", "bed adhesion", "stability"]
	check(c.is_valid(), "all three known flags accepted")
	c.risk_flags = []
	check(c.is_valid(), "empty risk flags accepted")
	c.risk_flags = []

	c.material_cost_cents = -5
	check(not c.is_valid(), "negative material cost rejected")
	c.material_cost_cents = 0
	check(c.is_valid(), "zero material cost accepted")
	c.material_cost_cents = 840

	c.layers = 0
	check(not c.is_valid(), "zero layers rejected")
	c.layers = 210
	c.deadline_days = -1
	check(not c.is_valid(), "negative deadline rejected")
	c.deadline_days = 3


func _test_state_path() -> void:
	var c := Contract.new()
	c.id = "C-PATH"
	var path := [
		Contract.State.OFFERED,
		Contract.State.ACCEPTED,
		Contract.State.PREPARING,
		Contract.State.PRINTING,
		Contract.State.INSPECTION,
		Contract.State.PACKED,
		Contract.State.DELIVERED,
	]
	for i in range(path.size() - 1):
		check(Contract.can_transition(path[i], path[i + 1]),
			"legal step %s -> %s" % [Contract.state_name(path[i]), Contract.state_name(path[i + 1])])
		c.state = path[i + 1]
	check(c.is_terminal(), "DELIVERED is terminal")
	check(Contract.legal_transitions(Contract.State.DELIVERED).is_empty(),
		"DELIVERED has no outgoing transitions")


func _test_transition_table_probe() -> void:
	# Exhaustive from->to probe: legal only when documented table allows it.
	var states: Array = Contract.State.values()
	for from_s in states:
		var legal: Array = Contract.legal_transitions(from_s)
		# No duplicates in legal_transitions.
		var seen := {}
		for s in legal:
			seen[s] = true
		check(seen.size() == legal.size(), "legal_transitions(%s) has no duplicates" % Contract.state_name(from_s))
		# Every documented legal transition is reachable.
		for to_s in legal:
			check(Contract.can_transition(from_s, to_s),
				"table allows %s -> %s" % [Contract.state_name(from_s), Contract.state_name(to_s)])
		# Every undocumented transition is rejected.
		for to_s in states:
			var documented: bool = to_s in legal
			var allowed: bool = Contract.can_transition(from_s, to_s)
			check(documented == allowed,
				"%s -> %s probed consistently (%s)" % [
					Contract.state_name(from_s), Contract.state_name(to_s),
					"legal" if documented else "rejected"])


func _test_failed_reachability() -> void:
	var expected_from := {
		Contract.State.PREPARING: true,
		Contract.State.PRINTING: true,
		Contract.State.INSPECTION: true,
	}
	var states: Array = Contract.State.values()
	for from_s in states:
		var to_failed: bool = Contract.can_transition(from_s, Contract.State.FAILED)
		check(to_failed == expected_from.get(from_s, false),
			"FAILED reachable from %s: %s" % [Contract.state_name(from_s), str(to_failed)])
	check(Contract.is_terminal_state(Contract.State.FAILED), "FAILED is terminal")
	var c := Contract.new()
	c.id = "C-FAIL"
	c.state = Contract.State.FAILED
	check(c.is_terminal(), "is_terminal() true on FAILED contract")


func _test_fixtures() -> void:
	var jobs: Array = Contract.make_fixture_jobs()
	check(jobs.size() >= 4, "at least 4 fixture jobs")
	var ids := {}
	for j in jobs:
		check(j is Contract, "fixture is a Contract")
		check(j.is_valid(), "fixture %s is valid" % j.id)
		check(not ids.has(j.id), "fixture id %s unique" % j.id)
		ids[j.id] = true
	# Deterministic: two calls produce identical values.
	var again: Array = Contract.make_fixture_jobs()
	check(again.size() == jobs.size(), "fixture factory deterministic in size")
	var same := true
	for i in range(jobs.size()):
		if jobs[i].id != again[i].id or jobs[i].payout_cents != again[i].payout_cents \
				or jobs[i].difficulty != again[i].difficulty or jobs[i].layers != again[i].layers:
			same = false
	check(same, "fixture factory deterministic in values")


func _test_expanded_fixtures_and_rush() -> void:
	var jobs: Array = Contract.make_fixture_jobs()
	check(jobs.size() == 8, "expanded fixture pool has 8 jobs (got %d)" % jobs.size())
	# Original four fixtures stay first, in order, with exact payout values.
	var original_payouts := {"C-014": 6400, "C-015": 4200, "C-016": 11600, "C-017": 8750}
	var i := 0
	for want_id in original_payouts.keys():
		var j: Contract = jobs[i]
		check(j.id == want_id, "fixture %d is %s (got %s)" % [i, want_id, j.id])
		check(j.payout_cents == original_payouts[want_id],
			"fixture %s payout unchanged (%d)" % [want_id, j.payout_cents])
		check(not j.rush, "original fixture %s is not rush" % want_id)
		i += 1
	# Full-pool invariants.
	var ids := {}
	var rush_count := 0
	for j in jobs:
		check(j.is_valid(), "expanded fixture %s is_valid()" % j.id)
		check(not ids.has(j.id), "expanded fixture id %s unique" % j.id)
		ids[j.id] = true
		check(j.payout_cents >= 3000 and j.payout_cents <= 15000,
			"fixture %s payout in 3000-15000" % j.id)
		check(j.layers >= 60 and j.layers <= 500, "fixture %s layers in 60-500" % j.id)
		check(j.deadline_days >= 1 and j.deadline_days <= 6,
			"fixture %s deadline in 1-6" % j.id)
		check(j.difficulty >= 1 and j.difficulty <= 5, "fixture %s difficulty in 1-5" % j.id)
		if j.rush:
			rush_count += 1
			check(j.deadline_days <= 2, "rush fixture %s has deadline <= 2" % j.id)
	check(rush_count >= 2, "at least 2 rush fixtures exist (got %d)" % rush_count)
	# Rush fixtures pay clearly above the non-rush norm for their difficulty.
	var norm := {1: 4200, 2: 6400, 3: 8750, 4: 11600, 5: 11600}
	for j in jobs:
		if j.rush:
			var ratio: float = float(j.payout_cents) / float(norm[j.difficulty])
			check(ratio >= 1.3 and ratio <= 1.6,
				"rush fixture %s payout is 1.3-1.6x norm (%.2f)" % [j.id, ratio])


func _test_jobboard_rush_summaries() -> void:
	var board = JobBoard.new()
	root.add_child(board)  # triggers _ready -> fill to capacity
	var fixtures: Array = Contract.make_fixture_jobs()
	check(board.get_available_count() == fixtures.size(),
		"job board fills to expanded capacity (%d)" % fixtures.size())
	var rush_by_id := {}
	for f in fixtures:
		rush_by_id[f.id] = f.rush
	var summaries: Array[Dictionary] = board.available_summaries()
	check(summaries.size() == fixtures.size(), "summaries cover the whole board")
	var rush_summaries := 0
	var non_rush_summaries := 0
	var values_match := true
	for s in summaries:
		if not s.has("rush"):
			values_match = false
			break
		if rush_by_id.get(s["id"], null) != s["rush"]:
			values_match = false
		if s["rush"]:
			rush_summaries += 1
		else:
			non_rush_summaries += 1
	check(values_match, "every summary carries 'rush' matching its contract")
	check(rush_summaries >= 1, "at least one rush summary present (got %d)" % rush_summaries)
	check(non_rush_summaries >= 1, "at least one non-rush summary present (got %d)" % non_rush_summaries)
	# Rotation still works with the bigger pool: take everything, then check the
	# next refill starts back at the first fixture.
	var first_id: String = fixtures[0].id
	var drained_ok := true
	for k in range(fixtures.size()):
		var c: Contract = board.take_next()
		if c.id != fixtures[k].id:
			drained_ok = false
	check(drained_ok, "board rotates through all fixtures in order")
	var after: Contract = board.take_next()
	check(after.id == first_id, "refill wraps around to the first fixture")
	board.free()


func _test_ledger_basics() -> void:
	var l := Ledger.new()
	check(l.balance() == 0, "ledger starts at 0")
	check(l.can_afford(0), "can_afford(0) at balance 0")
	check(not l.can_afford(1), "cannot afford 1 at balance 0")
	check(not l.charge(100, "too soon"), "charge with insufficient funds rejected")
	check(l.balance() == 0, "rejected charge did not mutate")
	check(l.transaction_count() == 0, "rejected charge added no transaction")
	check(not l.charge(-1, "negative"), "negative charge rejected")
	check(not l.credit(-1, "negative"), "negative credit rejected")
	check(l.credit(2500, "opening deposit"), "credit accepted")
	check(l.balance() == 2500, "balance after credit")
	check(l.charge(840, "material C-014"), "charge accepted")
	check(l.balance() == 1660, "balance after charge")
	var last: Dictionary = l.transactions[l.transaction_count() - 1]
	check(last["delta_cents"] == -840 and last["balance_after"] == 1660,
		"charge transaction records delta and balance_after")
	check(l.has_paid("C-014") == false, "plain charge is not a contract payout")


func _test_ledger_exactly_once() -> void:
	var l := Ledger.new()
	l.credit(5000, "opening deposit")
	var n_before := l.transaction_count()
	# A payout is income: never funds-gated, so it succeeds even beyond the till.
	check(l.pay_once("C-014", 6400, "payout"), "pay_once succeeds regardless of till")
	check(l.transaction_count() == n_before + 1, "payout added exactly one transaction")
	var bal := l.balance()
	check(not l.pay_once("C-014", 6400, "payout"), "second pay_once rejected")
	check(l.balance() == bal, "duplicate pay_once did not change balance")
	var payout_entries := 0
	for t in l.transactions:
		if t["reason"] == "payout" and t["delta_cents"] == 6400:
			payout_entries += 1
	check(payout_entries == 1, "exactly one payout credit entry")
	check(l.has_paid("C-014"), "has_paid true after payout")
	check(not l.has_paid("C-999"), "has_paid false for other contract")
	check(not l.pay_once("", 100, "payout"), "empty contract id rejected")
	check(not l.pay_once("C-015", -5, "payout"), "negative pay_once rejected")


func _test_ledger_reconciliation_and_invariant() -> void:
	var l := Ledger.new()
	var sum_deltas := 0
	l.credit(10000, "deposit")
	l.charge(840, "material C-014")
	l.charge(510, "material C-015")
	l.credit(6400, "payout")
	l.charge(1620, "material C-017")
	l.credit(4200, "payout 2")
	# Attempted illegal ops interleaved; none may mutate.
	l.charge(999999, "too big")
	l.credit(-1, "bad")
	check(l.charge(l.balance() + 1, "overdraw attempt") == false, "overdraw beyond exact balance rejected")
	for t in l.transactions:
		sum_deltas += t["delta_cents"]
	check(l.balance() == sum_deltas, "balance equals sum of deltas (%d)" % sum_deltas)
	check(l.balance() >= 0, "balance never negative")
	# balance_after chain must be internally consistent.
	var running := 0
	var chain_ok := true
	for t in l.transactions:
		running += t["delta_cents"]
		if t["balance_after"] != running:
			chain_ok = false
	check(chain_ok, "balance_after chain consistent with deltas")


func _test_snapshot_restore() -> void:
	var l := Ledger.new()
	l.credit(10000, "deposit")
	l.charge(840, "material C-014")
	l.pay_once("C-014", 6400, "payout")
	var snap: Dictionary = l.snapshot()
	check(snap["balance_cents"] == l.balance(), "snapshot preserves balance")
	check(snap["transactions"].size() == l.transaction_count(), "snapshot preserves transactions")

	# Mutate after snapshot, then restore.
	l.credit(99999, "post-snapshot deposit")
	l.pay_once("C-015", 1, "payout")
	var l2 := Ledger.new()
	check(l2.restore(snap), "restore accepts a valid snapshot")
	check(l2.balance() == snap["balance_cents"], "restored balance matches snapshot")
	check(l2.transaction_count() == snap["transactions"].size(), "restored transaction count matches")
	check(l2.has_paid("C-014"), "restored pay_once history keeps C-014 paid")
	check(not l2.has_paid("C-015"), "post-snapshot payout not present after restore")
	check(not l2.pay_once("C-014", 6400, "payout"), "exactly-once enforced after restore")

	# Invalid snapshots rejected without mutation.
	var before: int = l2.balance()
	var bad := {"balance_cents": -1, "transactions": [], "paid_contract_ids": []}
	check(not l2.restore(bad), "negative-balance snapshot rejected")
	check(l2.balance() == before, "rejected restore did not mutate")
	bad = {"balance_cents": 5, "transactions": [{"garbage": true}], "paid_contract_ids": []}
	check(not l2.restore(bad), "malformed-transaction snapshot rejected")
	check(l2.balance() == before, "second rejected restore did not mutate")
	# Snapshot is a copy: mutating it must not affect the ledger.
	snap["transactions"].clear()
	snap["balance_cents"] = 12345
	check(l.balance() != 12345 and l.transaction_count() > 0, "snapshot is a defensive copy")


func _finish(code: int) -> void:
	if failures > 0:
		printerr("contract_test: %d/%d checks FAILED" % [failures, checks])
	elif checks == 0:
		printerr("contract_test: no checks ran")
		code = 1
	else:
		print("contract_test: all %d checks passed" % checks)
	quit(code)
