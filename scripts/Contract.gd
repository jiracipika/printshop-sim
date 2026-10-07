class_name Contract
extends Resource

## Task 08 — one typed contract resource for the contract loop (design/implementation-plan.md).
## Pure data + validation + state machine. No gameplay integration in this slice.
##
## Rush contracts: rush=true marks a premium job with a short deadline. Data-level
## only — fixture rush jobs carry deadline_days <= 2 and a payout roughly 1.3-1.6x
## the non-rush norm for their difficulty; Main applies any gameplay effects.
##
## Board pressure (v0.14.0): rush and competing jobs leave the job board at the
## next morning rollover — first come, first served. competing=true means
## another buyer is circling the same part ("2 waiting" on the card); rush is
## the deadline-pressure flavor. offered_day records the shop day the job was
## dealt so the board can expire it exactly one morning later. Data-level only;
## JobBoard/Main apply the expiry and the reputation cost.
##
## State transition table (documented; FAILED reachable exactly from PREPARING / PRINTING /
## INSPECTION; DELIVERED only from PACKED):
##
##     OFFERED    -> ACCEPTED
##     ACCEPTED   -> PREPARING
##     PREPARING  -> PRINTING, FAILED
##     PRINTING   -> INSPECTION, FAILED
##     INSPECTION -> PACKED, FAILED, PREPARING (multi-part reprint, v0.18.0)
##     PACKED     -> DELIVERED
##     DELIVERED  -> (terminal)
##     FAILED     -> (terminal)

enum State {
	OFFERED,
	ACCEPTED,
	PREPARING,
	PRINTING,
	INSPECTION,
	PACKED,
	DELIVERED,
	FAILED,
}

const VALID_RISK_FLAGS: Array[String] = ["overhangs", "bed adhesion", "stability"]
const VALID_COLORS: Array[String] = ["Clay", "Sage", "Honey"]

@export var id: String = ""
@export var client: String = ""
@export var model_name: String = ""
@export var payout_cents: int = 0
@export var material_cost_cents: int = 0
@export_range(1, 5) var difficulty: int = 1
@export var risk_flags: Array[String] = []
@export var layers: int = 0
@export var deadline_days: int = 0
@export var rush: bool = false
## Another buyer is waiting: this offer leaves the board overnight (v0.14.0).
@export var competing: bool = false
## Shop day this contract was dealt onto the board (expiry anchor).
@export var offered_day: int = 1
## Filament color the client expects ("" = any). A mismatch caps the delivery
## grade at B — the part still ships, just for less money.
@export var color: String = ""
## Multi-part orders (v0.18.0): generated contracts can ask for 2-3 copies.
## payout_cents and material_cost_cents stay PER COPY; the whole order pays
## out once, when the last copy is packed. Fixture jobs stay single-part.
@export var parts_total: int = 1
## Customer voice (v0.30.0): a short handwritten request on the order
## card. Flavor only — never affects grading or payouts. "" = no note.
@export var note: String = ""
## Featured order (v0.42.0): one job per day is the board's featured pick
## and pays +15%. Deterministic per (day, slot) — derived, not stored.
@export var featured: bool = false


## Which slot of the day's board is the featured pick (v0.42.0): one per
## day, hash-pinned. Slots 0..7 match the board's dealt order.
static func featured_slot_for_day(day: int) -> int:
	return absi(hash("printshop-featured-%d" % maxi(day, 1))) % 8
## Copies packed so far (packed parts stack on the packing table).
@export var parts_packed: int = 0
## Per-copy delivery grades recorded at pack time, in pack order. The order
## grade aggregates from these at final completion (aggregate_grades).
@export var copy_grades: Array[String] = []
@export var state: State = State.OFFERED

static var _RISK_FLAG_SET: Dictionary = {
	"overhangs": true,
	"bed adhesion": true,
	"stability": true,
}


func is_terminal() -> bool:
	return state == State.DELIVERED or state == State.FAILED


## Board-pressure expiry (v0.14.0): rush/competing offers leave the board
## overnight. `today` is the day being rolled into; a job dealt today (or a
## carried-over calm job) never expires against its own offer day.
func has_expired_for(today: int) -> bool:
	return (rush or competing) and offered_day < today


func is_valid() -> bool:
	if id.is_empty() or client.is_empty() or model_name.is_empty():
		return false
	if payout_cents <= 0:
		return false
	if material_cost_cents < 0:
		return false
	if difficulty < 1 or difficulty > 5:
		return false
	if layers <= 0:
		return false
	if deadline_days < 0:
		return false
	if parts_total < 1 or parts_total > 3:
		return false
	if parts_packed < 0 or parts_packed > parts_total:
		return false
	for flag in risk_flags:
		if not _RISK_FLAG_SET.has(flag):
			return false
	if color != "" and not (color in VALID_COLORS):
		return false
	return true


## --- multi-part orders (v0.18.0) ----------------------------------------------

func is_multi_part() -> bool:
	return parts_total > 1


## True while more copies still need printing and packing.
func needs_parts() -> bool:
	return parts_packed < parts_total


## The whole order's payout: the per-copy payout times the copy count.
func order_payout_cents() -> int:
	return payout_cents * parts_total


## Order grade from the per-copy grades. Two F copies fail the whole order;
## a single F caps the order at C; otherwise the average grades floor to a
## letter (A=4 .. D=1, averages round down — conservative by design).
static func aggregate_grades(grades: Array[String]) -> String:
	var f_count := 0
	var sum := 0.0
	const VALUES := {"A": 4.0, "B": 3.0, "C": 2.0, "D": 1.0}
	for g in grades:
		if g == "F":
			f_count += 1
		else:
			sum += float(VALUES.get(g, 1.0))
	if f_count >= 2:
		return "F"
	if f_count == 1:
		return "C"
	if grades.is_empty():
		return "D"
	var avg := sum / float(grades.size())
	if avg >= 3.5:
		return "A"
	if avg >= 2.5:
		return "B"
	if avg >= 1.5:
		return "C"
	return "D"


## Legal successor states for `from`, in table order. No duplicates.
static func legal_transitions(from: State) -> Array[State]:
	var table := {
		State.OFFERED: [State.ACCEPTED],
		State.ACCEPTED: [State.PREPARING],
		State.PREPARING: [State.PRINTING, State.FAILED],
		State.PRINTING: [State.INSPECTION, State.FAILED],
		# INSPECTION -> PREPARING: multi-part orders re-enter prep to print
		# their next copy (v0.18.0). Single-part flow never uses it.
		State.INSPECTION: [State.PACKED, State.FAILED, State.PREPARING],
		State.PACKED: [State.DELIVERED],
		State.DELIVERED: [],
		State.FAILED: [],
	}
	var out: Array[State] = []
	out.assign(table.get(from, []))
	return out


static func can_transition(from: State, to: State) -> bool:
	return to in legal_transitions(from)


static func is_terminal_state(s: State) -> bool:
	return s == State.DELIVERED or s == State.FAILED


static func state_name(s: State) -> String:
	return State.keys()[s]


## Deterministic fixture jobs (task 08, expanded). Values inspired by
## design/menu-contracts.html, converted to integer cents. No RNG; the same
## list every call. C-014..C-017 keep their original order and values (existing
## suites depend on the rotation order); C-018..C-021 widen the pool with more
## varied clients/models and two rush jobs (rush = deadline_days <= 2 plus a
## payout roughly 1.3-1.6x the non-rush norm for the same difficulty).
static func make_fixture_jobs() -> Array:
	var jobs: Array = []

	var planter := new()
	planter.id = "C-014"
	planter.client = "Mara / Corner Plant Co."
	planter.model_name = "A home for the cuttings"
	planter.payout_cents = 6400       # mockup $64.00
	planter.material_cost_cents = 840 # mockup est. material $8.40
	planter.difficulty = 2
	planter.risk_flags = ["bed adhesion"]
	planter.color = "Clay"
	planter.layers = 210
	planter.deadline_days = 2
	planter.note = "The cuttings are ready — don't keep them waiting."
	jobs.append(planter)

	var clips := new()
	clips.id = "C-015"
	clips.client = "Ellis / Repair cafe"
	clips.model_name = "Keep the cables tidy"
	clips.payout_cents = 4200         # mockup $42.00
	clips.material_cost_cents = 610
	clips.difficulty = 1
	clips.risk_flags = []
	clips.color = "Sage"
	clips.layers = 120
	clips.deadline_days = 3
	jobs.append(clips)

	var brackets := new()
	brackets.id = "C-016"
	brackets.client = "Northside / Parts desk"
	brackets.model_name = "Built for the heat"
	brackets.payout_cents = 11600     # mockup $116.00
	brackets.material_cost_cents = 2350
	brackets.difficulty = 4
	brackets.risk_flags = ["overhangs", "stability"]
	brackets.color = "Honey"
	brackets.layers = 480
	brackets.deadline_days = 5
	jobs.append(brackets)

	var hook := new()
	hook.id = "C-017"
	hook.client = "Priya / Community kitchen"
	hook.model_name = "Heavy wall hook"
	hook.payout_cents = 8750
	hook.material_cost_cents = 1220
	hook.difficulty = 3
	hook.risk_flags = ["overhangs"]
	hook.color = "Clay"
	hook.layers = 310
	hook.deadline_days = 4
	jobs.append(hook)

	var gauge := new()
	gauge.id = "C-018"
	gauge.client = "Theo / Farmers market"
	gauge.model_name = "Event signage clip set"
	gauge.payout_cents = 9000        # rush premium (~1.4x the diff-2 norm of 6400)
	gauge.material_cost_cents = 700
	gauge.difficulty = 2
	gauge.risk_flags = ["overhangs"]
	gauge.color = "Sage"
	gauge.layers = 150
	gauge.deadline_days = 2
	gauge.rush = true
	jobs.append(gauge)

	var bike := new()
	bike.id = "C-019"
	bike.client = "Odalys / Bike co-op"
	bike.model_name = "Derailleur alignment gauge"
	bike.payout_cents = 11000        # standard rate for diff 4, generous deadline
	bike.material_cost_cents = 2600
	bike.difficulty = 4
	bike.risk_flags = ["stability"]
	bike.color = "Honey"
	bike.layers = 440
	bike.deadline_days = 6
	bike.note = "Track day on the 14th — we're counting on it."
	jobs.append(bike)

	var ramen := new()
	ramen.id = "C-020"
	ramen.client = "Bram / Late Night Ramen"
	ramen.model_name = "Countdown order stand"
	ramen.payout_cents = 12400       # rush premium (~1.4x the diff-3 norm of 8750)
	ramen.material_cost_cents = 1400
	ramen.difficulty = 3
	ramen.risk_flags = ["bed adhesion", "stability"]
	ramen.color = "Clay"
	ramen.layers = 220
	ramen.deadline_days = 1
	ramen.rush = true
	jobs.append(ramen)

	var library := new()
	library.id = "C-021"
	library.client = "June / Ridgeview library"
	library.model_name = "Story-hour puppet joints"
	library.payout_cents = 3900      # standard rate for diff 1, no rush premium
	library.material_cost_cents = 520
	library.difficulty = 1
	library.risk_flags = []
	library.color = "Sage"
	library.layers = 90
	library.deadline_days = 4
	jobs.append(library)

	return jobs

## --- procedural generation (v0.4.0) -----------------------------------------
##
## The live shop serves generated contracts instead of the fixed fixture pool.
## Generation is fully deterministic: the same (day, slot) always produces the
## same contract, so a save/reload shows the same board and tests can pin
## exact values. Bounds chosen for playability: materials stay affordable
## (<= $24, so a fresh $25 shop can always confirm the first job), payouts
## stay in $30-$150, rush work keeps its <= 2-day deadline and ~1.4x premium.

const GEN_FIRSTS: Array[String] = [
	"Mara", "Ellis", "Priya", "Theo", "Odalys", "Bram", "June", "Sam",
	"Ines", "Viktor", "Noor", "Felix", "Ada", "Marcus", "Lena", "Kofi",
]
const GEN_ORGS: Array[String] = [
	"Corner Plant Co.", "Repair cafe", "Parts desk", "Community kitchen",
	"Farmers market", "Bike co-op", "Late Night Ramen", "Ridgeview library",
	"Makerspace", "Bakery Nord", "Print & Pixel", "School of Craft",
	"Harbor Clinic", "Venue Vinyl", "City ferries", "Escape room Nord",
]
const GEN_MODELS: Array[String] = [
	"Desk organizer set", "Cable comb set", "Plant propagation stand",
	"Camera hot-shoe cover", "Kitchen tape holder", "Loom shuttle repair",
	"Speaker grille frame", "Board game insert", "Greenhouse drip nozzle",
	"Backpack buckle pair", "Meter bezel replica", "Tool wall cradles",
	"Stereo knob set", "Fold-flat tablet stand", "Button repair discs",
	"Aquarium tube clip", "Sheet music page clamps", "Espresso tamper collar",
	"Helmet chin-bar clip", "Wind chime core",
]
const GEN_BASE_PAYOUT: Array[int] = [4200, 6400, 8750, 9800, 9000]

## Handwritten client notes (v0.30.0) — flavor only. Expanded v0.49.0.
const GEN_NOTES: Array[String] = [
	"Make it sturdy — it gets dropped.",
	"Needed for a market stall this weekend.",
	"My old one finally snapped in half.",
	"The dog ate the last one. Long story.",
	"Color matters more than you'd think.",
	"It's a gift — no logos, please.",
	"Our last supplier ghosted us.",
	"Second order this month — you're reliable.",
	"Boss's orders. Don't ask.",
	"If it rattles, we send it back.",
	"The kids will destroy this. Fair warning.",
	"Lighter is better — it travels.",
	"It rides in a toolbag. Expect bumps.",
	"Sun-facing window shelf, so no warping, please.",
	"We photograph everything — make it photogenic.",
	"Needs to survive a toddler's birthday party.",
	"Replacing the one the movers crushed.",
	"Keep it cheap-looking. It's a stage prop.",
	"Grandpa's workshop replica — dimensions matter.",
	"We re-order these every season if they hold up.",
]


## Deterministic contract for shop `day`, board slot `index`. Same inputs ->
## same contract, forever. `day >= 1` also bumps difficulty odds slightly so
## later days lean toward meatier work. `max_difficulty` (v0.19.0) caps the
## difficulty roll for reputation tiers; the default keeps every pre-v0.19
## pinned (day, slot) value identical.
static func generate(day: int, index: int, max_difficulty := 5) -> Contract:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("printshop-gen-%d-%d" % [maxi(day, 1), index])

	var c := new()
	c.id = "G-%d-%02d" % [maxi(day, 1), index]
	c.client = "%s / %s" % [
		GEN_FIRSTS[rng.randi_range(0, GEN_FIRSTS.size() - 1)],
		GEN_ORGS[rng.randi_range(0, GEN_ORGS.size() - 1)]]
	c.model_name = GEN_MODELS[rng.randi_range(0, GEN_MODELS.size() - 1)]

	var day_bonus: int = clampi((maxi(day, 1) - 1) / 3, 0, 2)
	c.difficulty = clampi(rng.randi_range(1, 5) + (1 if rng.randf() < 0.15 * day_bonus else 0),
		1, clampi(max_difficulty, 1, 5))
	c.layers = rng.randi_range(60, 400)

	# Risk flags scale with difficulty (~15% per step above 1, per flag).
	var flag_odds := 0.15 * float(c.difficulty - 1)
	for flag in VALID_RISK_FLAGS:
		if rng.randf() < flag_odds:
			c.risk_flags.append(flag)

	# Materials: layers * rate, hard-capped at 2400 cents (always affordable
	# against the $25 opening balance).
	c.material_cost_cents = mini(c.layers * rng.randi_range(3, 6), 2400)

	# Clients have opinions about color (deterministic per slot).
	c.color = VALID_COLORS[rng.randi_range(0, VALID_COLORS.size() - 1)]

	# Rush: a quarter of the board; short deadline, ~1.4x premium.
	c.rush = rng.randf() < 0.25
	if c.rush:
		c.deadline_days = rng.randi_range(1, 2)
		c.payout_cents = mini((GEN_BASE_PAYOUT[c.difficulty - 1] + c.layers * 2) * 12 / 10, 9500)
	else:
		c.deadline_days = clampi(c.difficulty + rng.randi_range(-1, 1), 2, 6)
		c.payout_cents = mini(GEN_BASE_PAYOUT[c.difficulty - 1] + c.layers * 2, 9500)
	c.payout_cents = maxi(c.payout_cents, 3000)

	# Board pressure (v0.14.0): competing buyers circle ~30% of jobs. This draw
	# sits AFTER every value above so existing (day, slot) contracts keep their
	# pinned client/model/payout — only the new flag consumes fresh rng state.
	c.competing = rng.randf() < 0.3
	c.offered_day = maxi(day, 1)
	# Multi-part orders (v0.18.0): ~1 in 4 generated jobs asks for 2-3 copies
	# of the model. Last draw in the chain — pinned (day, slot) values above
	# never move. payout_cents stays per copy; the order pays parts_total x.
	if rng.randf() < 0.25:
		c.parts_total = 3 if rng.randf() < 0.4 else 2
	# Customer voice (v0.30.0): some clients add a handwritten note. This is
	# the new last draw — everything pinned above keeps its value.
	if rng.randf() < 0.45:
		c.note = GEN_NOTES[rng.randi_range(0, GEN_NOTES.size() - 1)]
	# Featured pick (v0.42.0): derived AFTER all rng draws — one slot per
	# day (hash-pinned), never fixtures. Stamped by the board at deal time.
	return c
