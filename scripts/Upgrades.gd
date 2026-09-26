class_name Upgrades
extends RefCounted

## Task 12 — printer upgrade catalog + ownership. Pure logic: the caller
## (Main) applies the effects to the sim and the ledger. Costs are integer
## cents. Purchases are exactly-once per id (a second buy() for an owned id
## is refused without side effects).

const CATALOG: Array[Dictionary] = [
	{
		"id": "heated_bed",
		"name": "Heated bed",
		"desc": "Grips the first layer — adhesion risk -0.15",
		"cost_cents": 2500,
	},
	{
		"id": "dual_gear",
		"name": "Dual-gear extruder",
		"desc": "Pushes filament faster — prints 30% quicker",
		"cost_cents": 4000,
		"speed_multiplier": 1.3,
	},
	{
		"id": "stiff_frame",
		"name": "Stiffened frame",
		"desc": "Steady motion — stability risk -0.15",
		"cost_cents": 6000,
	},
	{
		"id": "premium_nozzle",
		"name": "Premium nozzle",
		"desc": "Cleaner extrusion — failure threshold -0.12",
		"cost_cents": 9000,
		"failure_threshold_delta": -0.12,
	},
]

var _owned: Dictionary = {}  # id -> true


static func catalog() -> Array[Dictionary]:
	return CATALOG.duplicate(true)


static func entry(id: String) -> Dictionary:
	for e in CATALOG:
		if e.id == id:
			return e.duplicate(true)
	return {}


func is_owned(id: String) -> bool:
	return _owned.has(id)


## Exactly-once purchase. Returns false (no mutation) if already owned.
func buy(id: String) -> bool:
	if id.is_empty() or _owned.has(id) or entry(id).is_empty():
		return false
	_owned[id] = true
	return true


## Restore ownership from a save payload without charging (no effect
## application here — Main applies speed/threshold/risk modifiers itself).
func load_owned(ids: Array) -> int:
	var restored := 0
	for id in ids:
		if id is String and not id.is_empty() and not _owned.has(id) \
				and not entry(id).is_empty():
			_owned[id] = true
			restored += 1
	return restored


func owned_ids() -> Array[String]:
	var out: Array[String] = []
	for id in _owned.keys():
		out.append(id)
	out.sort()
	return out


func owned_count() -> int:
	return _owned.size()


## --- effect helpers (Main reads these; sim fields stay plain) --------------

## Speed multiplier from owned extruder upgrades (1.0 when none).
func speed_multiplier() -> float:
	var m := 1.0
	if is_owned("dual_gear"):
		m *= float(entry("dual_gear").speed_multiplier)
	return m


## Delta applied to PrintSim.failure_threshold (0.0 when none owned).
func failure_threshold_delta() -> float:
	var d := 0.0
	if is_owned("premium_nozzle"):
		d += float(entry("premium_nozzle").failure_threshold_delta)
	return d


## Risk modifiers written into the prep evaluation before it reaches the sim.
func risk_modifiers() -> Dictionary:
	return {
		"adhesion_risk": -0.15 if is_owned("heated_bed") else 0.0,
		"stability_risk": -0.15 if is_owned("stiff_frame") else 0.0,
	}
