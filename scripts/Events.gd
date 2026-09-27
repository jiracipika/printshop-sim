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

## --- seasons (v0.11.0) -------------------------------------------------------
##
## A slower rhythm under the daily events: the shop week (7 days) carries one
## season, deterministic per week number. Week 1 is always calm so fresh saves
## start gentle; humidity makes filament thirstier, cold snaps raise the rent,
## and a market boom lifts every payout.

const CALM_SEASON := {
	"id": "calm",
	"name": "",
	"adhesion_delta": 0.0,
	"extra_rent_cents": 0,
	"payout_mult": 1.0,
}


static func season_for_week(week: int) -> Dictionary:
	var w := maxi(week, 1)
	if w == 1:
		return CALM_SEASON.duplicate(true)
	var pool := ["calm", "humid", "calm", "cold_snap", "boom"]
	var pick: String = pool[absi(hash("printshop-season-%d" % w)) % pool.size()]
	return _season_by_id(pick).duplicate(true)


static func _season_by_id(id: String) -> Dictionary:
	match id:
		"humid":
			return {"id": id,
				"name": "Humid spell — filament thirstier (adhesion +0.05)",
				"adhesion_delta": 0.05,
				"extra_rent_cents": 0,
				"payout_mult": 1.0}
		"cold_snap":
			return {"id": id,
				"name": "Cold snap — heating costs up (rent +$1/day)",
				"adhesion_delta": 0.0,
				"extra_rent_cents": 100,
				"payout_mult": 1.0}
		"boom":
			return {"id": id,
				"name": "Market boom — payouts +10% this week",
				"adhesion_delta": 0.0,
				"extra_rent_cents": 0,
				"payout_mult": 1.10}
	return CALM_SEASON.duplicate(true)
