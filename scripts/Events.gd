class_name Events
extends RefCounted

## v0.7.0 — daily shop events. Deterministic per shop day: the same day always
## has the same event, so saves and tests can pin exact outcomes. Day 1 is
## always quiet (the shop opens steady); from day 2 on, the day's hash picks
## from a weighted pool (two quiet entries in six -> ~1/3 quiet days).

const QUIET := {
	"id": "quiet",
	"name": "Quiet day — steady as she goes",
	"spool_price_cents": 1200,
	"payout_mult": 1.0,
	"failure_delta": 0.0,
	"rent_free": false,
}


## Event for a shop day (>= 1). Same inputs -> same event, forever.
static func for_day(day: int) -> Dictionary:
	var d := maxi(day, 1)
	if d == 1:
		return QUIET.duplicate(true)
	var pool := ["quiet", "filament_sale", "quiet", "rush_week",
		"power_hiccup", "rent_holiday"]
	var pick: String = pool[absi(hash("printshop-event-%d" % d)) % pool.size()]
	return _by_id(pick).duplicate(true)


static func _by_id(id: String) -> Dictionary:
	match id:
		"filament_sale":
			return {"id": id,
				"name": "Filament sale — spools $8 today",
				"spool_price_cents": 800,
				"payout_mult": 1.0,
				"failure_delta": 0.0,
				"rent_free": false}
		"rush_week":
			return {"id": id,
				"name": "Rush week — payouts +25% today",
				"spool_price_cents": 1200,
				"payout_mult": 1.25,
				"failure_delta": 0.0,
				"rent_free": false}
		"power_hiccup":
			return {"id": id,
				"name": "Power hiccups — prints riskier today",
				"spool_price_cents": 1200,
				"payout_mult": 1.0,
				"failure_delta": 0.10,
				"rent_free": false}
		"rent_holiday":
			return {"id": id,
				"name": "Rent holiday — landlord is away",
				"spool_price_cents": 1200,
				"payout_mult": 1.0,
				"failure_delta": 0.0,
				"rent_free": true}
	return QUIET.duplicate(true)


## Coverage check helper: does every event id appear within `days` days?
static func all_ids_seen_within(days: int) -> bool:
	var seen := {}
	for d in range(2, maxi(days, 2) + 1):
		seen[str(for_day(d).id)] = true
	for id in ["filament_sale", "rush_week", "power_hiccup", "rent_holiday"]:
		if not seen.has(id):
			return false
	return true
