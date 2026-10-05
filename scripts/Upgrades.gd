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
	{
		"id": "pro_machine",
		"name": "Pro machine (printer 2)",
		"desc": "Unlock printer 2 — jobs run there print 25% faster",
		"cost_cents": 6000,
		"machine_speed_multiplier": 1.25,
		"machine_index": 1,
	},
	{
		"id": "farm_kit_a",
		"name": "Print farm kit A (printer 3)",
		"desc": "Opens the back room — third printer, ships empty",
		"cost_cents": 8000,
		"machine_index": 2,
	},
	{
		"id": "farm_kit_b",
		"name": "Print farm kit B (printer 4)",
		"desc": "Fourth printer for the back room, ships empty",
		"cost_cents": 12000,
		"machine_index": 3,
	},
	{
		"id": "grand_showcase",
		"name": "Grand showcase",
		"desc": "Display shelf fits 5 models — payouts up to +10%",
		"cost_cents": 15000,
	},
	{
		"id": "pei_plate",
		"name": "Textured PEI plate",
		"desc": "Grips anything — flat-side printing works on tippy parts",
		"cost_cents": 3500,
	},
	{
		"id": "filament_dryer",
		"name": "Filament dryer",
		"desc": "Bone-dry spools — adhesion risk -0.10 more",
		"cost_cents": 4500,
	},
	{
		"id": "enclosure",
		"name": "Print enclosure",
		"desc": "Still air, steady warmth — stability risk -0.25 more",
		"cost_cents": 12000,
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


## Speed bonus for jobs run on the unlocked pro machine (1.0 otherwise).
func machine_speed_multiplier() -> float:
	if is_owned("pro_machine"):
		return float(entry("pro_machine").machine_speed_multiplier)
	return 1.0


## Printer 2 stays locked until the pro machine is purchased.
func pro_machine_unlocked() -> bool:
	return is_owned("pro_machine")


## Per-machine unlock gate (v0.13): machines 0-1 ship with the shop
## (machine 1 still needs the pro machine), 2-3 open with the farm kits.
func machine_unlocked(idx: int) -> bool:
	match idx:
		0:
			return true
		1:
			return is_owned("pro_machine")
		2:
			return is_owned("farm_kit_a")
		3:
			return is_owned("farm_kit_b")
	return false


## Delta applied to PrintSim.failure_threshold (0.0 when none owned).
func failure_threshold_delta() -> float:
	var d := 0.0
	if is_owned("premium_nozzle"):
		d += float(entry("premium_nozzle").failure_threshold_delta)
	return d


## Risk modifiers written into the prep evaluation before it reaches the sim.
## Stacking upgrades sum; Main clamps the final risks to [0, 1].
func risk_modifiers() -> Dictionary:
	var adhesion := 0.0
	var stability := 0.0
	if is_owned("heated_bed"):
		adhesion -= 0.15
	if is_owned("filament_dryer"):
		adhesion -= 0.10
	if is_owned("stiff_frame"):
		stability -= 0.15
	if is_owned("enclosure"):
		stability -= 0.25
	return {"adhesion_risk": adhesion, "stability_risk": stability}


## The PEI plate unlocks flat-side printing for stability-flagged parts.
func pei_plate_unlocks_flat() -> bool:
	return is_owned("pei_plate")
