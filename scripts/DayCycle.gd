extends Node

class_name DayCycle

## v0.2.0 — the shop day. Advances a time-of-day fraction and counts whole
## days; emits day_changed once per wrap so Main can charge rent, age
## deadlines and apply daylight. Pure clock logic: no ledger, no visuals.

signal day_changed(new_day: int)

const DEFAULT_DAY_LENGTH_S := 90.0

## Whole-day counter, starting at 1 (the shop opens on day 1).
var day: int = 1
## Fraction of the current day in [0, 1). 0 = dawn, 0.5 = dusk onset.
var t: float = 0.0
var day_length_s: float = DEFAULT_DAY_LENGTH_S
var _accum := 0.0

func _init(length_s: float = DEFAULT_DAY_LENGTH_S) -> void:
	day_length_s = maxf(length_s, 1.0)

func tick(delta: float) -> void:
	_accum += delta
	while _accum >= day_length_s:
		_accum -= day_length_s
		day += 1
		day_changed.emit(day)
	t = clampf(_accum / day_length_s, 0.0, 0.9999)

## Restore clock state from a save payload (validated by caller).
func restore(saved_day: int, saved_t: float) -> void:
	day = maxi(saved_day, 1)
	t = clampf(saved_t, 0.0, 0.9999)
	_accum = t * day_length_s

func snapshot() -> Dictionary:
	return {"day": day, "t": t}
