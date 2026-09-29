class_name WorkshopLog
extends RefCounted

## v0.15.0 — the workshop log: a capped ring buffer of shop events so the
## player can answer "what happened overnight?" and "why did that print fail?".
## Pure logic (like Ledger): no nodes, no I/O. Main appends at the real event
## sites (delivered/failed/expired/rent/upgrade/prototype/cancel); the Log
## menu panel renders it; the save payload persists it.
##
## Entry shape: { "seq": int (append order), "day": int (shop day >= 1),
##                "kind": String (free-form tag, e.g. "delivered"),
##                "text": String (one line) } — oldest first, newest last.

const CAP := 30

var _entries: Array[Dictionary] = []
var _seq := 0

func count() -> int:
	return _entries.size()

## Chronological copy (oldest first). Safe to mutate.
func entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in _entries:
		out.append(e.duplicate(true))
	return out

## The newest n entries, oldest-first within the slice.
func latest(n: int) -> Array[Dictionary]:
	var all := entries()
	return all.slice(maxi(0, all.size() - n)) if n > 0 else []

## Append one event; drops the oldest past CAP. Returns the stored entry.
func append(kind: String, text: String, day: int) -> Dictionary:
	_seq += 1
	var e := {
		"seq": _seq,
		"day": maxi(int(day), 1),
		"kind": kind if not kind.is_empty() else "event",
		"text": str(text),
	}
	_entries.append(e)
	while _entries.size() > CAP:
		_entries.pop_front()
	return e

func clear() -> void:
	_entries.clear()

## Snapshot for the save payload (plain arrays/dicts).
func snapshot() -> Array:
	var out: Array = []
	for e in _entries:
		out.append(e.duplicate(true))
	return out

## Restore from snapshot data. Whole-float coercion for JSON round-trips.
## Accepts at most CAP entries — a longer history keeps only its NEWEST CAP.
## Returns false WITHOUT mutating on any malformed input.
func restore(data: Variant) -> bool:
	if not (data is Array):
		return false
	var parsed: Array[Dictionary] = []
	for e in data:
		if not (e is Dictionary):
			return false
		var d: Dictionary = e
		if not d.has_all(["seq", "day", "kind", "text"]):
			return false
		for key in ["seq", "day"]:
			if not _whole_int(d[key]):
				return false
		if not (d["kind"] is String) or (d["kind"] as String).is_empty():
			return false
		if not (d["text"] is String):
			return false
		if int(d["day"]) < 1:
			return false
		parsed.append({
			"seq": int(d["seq"]),
			"day": int(d["day"]),
			"kind": d["kind"],
			"text": d["text"],
		})
	_entries.clear()
	var first := maxi(0, parsed.size() - CAP)
	for i in range(first, parsed.size()):
		_entries.append(parsed[i])
	_seq = 0
	for e in _entries:
		_seq = maxi(_seq, e["seq"])
	return true

static func _whole_int(v: Variant) -> bool:
	if typeof(v) == TYPE_INT:
		return true
	if typeof(v) == TYPE_FLOAT:
		var f: float = v
		return is_equal_approx(f, floorf(f)) and is_finite(f)
	return false
