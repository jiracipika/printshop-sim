class_name Ledger
extends RefCounted

## Task 08 — integer-cents money ledger. No floats anywhere.
## transactions entries: { "id": int seq, "reason": String, "delta_cents": int,
##                         "balance_after": int }
## Invariant: balance_cents >= 0 at all times; asserted in every mutator.
## snapshot()/restore() exist for a future save system (task 12).

var balance_cents: int = 0
var transactions: Array[Dictionary] = []

var _seq: int = 0
var _paid_contract_ids: Dictionary = {}


func balance() -> int:
	return balance_cents


func can_afford(cents: int) -> bool:
	return cents >= 0 and balance_cents >= cents


## Charge cents (delta <= 0). Rejects negative input and insufficient funds
## without mutating. A plain charge is not tied to a contract payout.
func charge(cents: int, reason: String) -> bool:
	if cents < 0 or not can_afford(cents):
		return false
	_apply(-cents, reason)
	return true


## Add cents (delta >= 0). Rejects negative input without mutating.
func credit(cents: int, reason: String) -> bool:
	if cents < 0:
		return false
	_apply(cents, reason)
	return true


func has_paid(contract_id: String) -> bool:
	return _paid_contract_ids.has(contract_id)


## Exactly-once payout per contract id. A payout is INCOME, not a payment,
## so it is never funds-gated (the business can receive more than it holds).
## A failed pay_once never mutates.
func pay_once(contract_id: String, cents: int, reason: String) -> bool:
	if contract_id.is_empty() or cents < 0 or _paid_contract_ids.has(contract_id):
		return false
	_apply(cents, reason)
	_paid_contract_ids[contract_id] = true
	return true


func transaction_count() -> int:
	return transactions.size()


## Deep defensive copy for a future save system.
func snapshot() -> Dictionary:
	var txs: Array = []
	for t in transactions:
		txs.append(t.duplicate(true))
	var paid: Array = []
	for k in _paid_contract_ids.keys():
		paid.append(k)
	return {
		"balance_cents": balance_cents,
		"transactions": txs,
		"paid_contract_ids": paid,
		"next_seq": _seq,
	}


## Restore from snapshot(). Rejects malformed input without mutating.
func restore(dict: Dictionary) -> bool:
	if not dict.has_all(["balance_cents", "transactions", "paid_contract_ids", "next_seq"]):
		return false
	var bal: int = dict["balance_cents"]
	if bal < 0:
		return false
	var txs: Array = dict["transactions"]
	var paid: Array = dict["paid_contract_ids"]
	# Validate shapes first; only then mutate.
	var parsed: Array[Dictionary] = []
	var running: int = 0
	for t in txs:
		if t is Dictionary and t.has_all(["id", "reason", "delta_cents", "balance_after"]):
			running += int(t["delta_cents"])
			parsed.append(t)
		else:
			return false
	if running != bal:
		return false
	var paid_set: Dictionary = {}
	for k in paid:
		if not (k is String) or k.is_empty():
			return false
		paid_set[k] = true
	balance_cents = bal
	transactions.clear()
	for t in parsed:
		transactions.append(t)
	_paid_contract_ids = paid_set
	_seq = int(dict["next_seq"])
	return true


## Single mutation path. Keeps the balance_after chain and the non-negative
## invariant in one place.
func _apply(delta_cents: int, reason: String) -> void:
	balance_cents += delta_cents
	assert(balance_cents >= 0, "Ledger invariant violated: negative balance")
	_seq += 1
	transactions.append({
		"id": _seq,
		"reason": reason,
		"delta_cents": delta_cents,
		"balance_after": balance_cents,
	})
