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
		"power_hiccup", "rent_holiday", "quiet", "surplus_stock",
		"quiet", "steady_hands", "media_day", "quiet", "backorders",
		"quiet"]
	var pick: String = pool[absi(hash("printshop-event-%d" % d)) % pool.size()]
	return _by_id(pick).duplicate(true)


static func _by_id(id: String) -> Dictionary:
	match id:
		"media_day":
			return {"id": id,
				"name": "Media day — A-grade deliveries in the paper (+0.3 rep)",
				"spool_price_cents": 1200,
				"payout_mult": 1.0,
				"failure_delta": 0.0,
				"rent_free": false,
				"extra_jobs": 0}
		"backorders":
			return {"id": id,
				"name": "Backorders — a bigger board today (+2 jobs)",
				"spool_price_cents": 1200,
				"payout_mult": 1.0,
				"failure_delta": 0.0,
				"rent_free": false,
				"extra_jobs": 2}
		"steady_hands":
			return {"id": id,
				"name": "Steady hands — prints behave today (risk -0.10)",
				"spool_price_cents": 1200,
				"payout_mult": 1.0,
				"failure_delta": -0.10,
				"rent_free": false,
    "extra_jobs": 0}
		"surplus_stock":
			return {"id": id,
				"name": "Surplus stock — spools $6 today",
				"spool_price_cents": 600,
				"payout_mult": 1.0,
				"failure_delta": 0.0,
				"rent_free": false,
    "extra_jobs": 0}
		"filament_sale":
			return {"id": id,
				"name": "Filament sale — spools $8 today",
				"spool_price_cents": 800,
				"payout_mult": 1.0,
				"failure_delta": 0.0,
				"rent_free": false,
    "extra_jobs": 0}
		"rush_week":
			return {"id": id,
				"name": "Rush week — payouts +25% today",
				"spool_price_cents": 1200,
				"payout_mult": 1.25,
				"failure_delta": 0.0,
				"rent_free": false,
    "extra_jobs": 0}
		"power_hiccup":
			return {"id": id,
				"name": "Power hiccups — prints riskier today",
				"spool_price_cents": 1200,
				"payout_mult": 1.0,
				"failure_delta": 0.10,
				"rent_free": false,
    "extra_jobs": 0}
		"rent_holiday":
			return {"id": id,
				"name": "Rent holiday — landlord is away",
				"spool_price_cents": 1200,
				"payout_mult": 1.0,
				"failure_delta": 0.0,
				"rent_free": true,
    "extra_jobs": 0}
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


## Tomorrow-forecast hints (v0.35.0) — one strategy line per event id.
const FORECAST_HINT := {
	"quiet": "A calm day. Good for long prints.",
	"filament_sale": "Spools are $8 — stock up.",
	"rush_week": "Payouts +25% — chase the board.",
	"power_hiccup": "Prints riskier today — calm orientations.",
	"rent_holiday": "No rent! Take the big jobs.",
	"surplus_stock": "Spools only $6 — cheapest of the month.",
	"steady_hands": "Prints behave — a great day for hard jobs.",
	"media_day": "Ship A-grades — the paper is watching.",
	"backorders": "More orders on the board — pick the best.",
}


static func forecast_hint(day: int) -> String:
	return FORECAST_HINT.get(_by_id(for_day(day).id).id, "A calm day.")


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


## --- reputation tiers (v0.19.0) ----------------------------------------------
##
## The board reacts to standing: below 3.0 stars only easy jobs appear, and
## every threshold up widens the pool and sweetens rush premiums. Pure data —
## JobBoard/Main apply the terms when they deal the morning board.

const TIER_NAMES: Array[String] = [
	"", "Unknown shop", "Local regular", "Trusted studio", "Top of the market",
]
## Reputation where each tier-up lands (index i = tier i+1 -> i+2).
const TIER_THRESHOLDS: Array[float] = [3.0, 3.5, 4.25]


## Tier 1..4 for a reputation in 0..5. Exactly 3.0/3.5/4.25 already counts as
## the higher tier.
static func tier_for_rep(rep: float) -> int:
	var r := clampf(rep, 0.0, 5.0)
	var tier := 1
	for i in range(TIER_THRESHOLDS.size()):
		if r >= TIER_THRESHOLDS[i]:
			tier = i + 2
	return tier


## Generated jobs cap at this difficulty for the tier (1->2, 2->3, 3->4, 4->5).
static func tier_max_difficulty(tier: int) -> int:
	return clampi(tier + 1, 2, 5)


## Rush premium multiplier on the board: +10% per tier above the first.
static func tier_rush_mult(tier: int) -> float:
	return 1.0 + 0.1 * float(clampi(tier, 1, 4) - 1)
