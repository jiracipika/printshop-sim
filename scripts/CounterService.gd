class_name CounterService
extends RefCounted

## Walk-in customers (v0.59.0) — the pure counter-arrival/patience logic.
## PrintSim style: no nodes, no signals, no save I/O — every input that
## matters is a deterministic hash draw, so the same day always produces the
## same schedule and tests can pin exact times. Main owns the one service
## instance, ticks it from _physics_process (PollSim pattern, like the
## machine sims) and renders/destroys the CustomerActor around this state.
##
## Arrival model: at most 2 slots per day (index 0 and 1). Slot i is live on
## a day when hash("walkin-<day>-<i>") % 10 < 6, and is due at day fraction
## 0.25 + 0.22 * i + 0.03 * (hash jitter 0..3), inside the business window
## 0.15..0.80. A due slot is SKIPPED ENTIRELY while someone already waits
## (max 1 waiting customer at a time) — it is not deferred.
##
## Patience: 0.55 of a shop day, measured from the arrival (the deadline is
## fixed when the customer steps in; accepting the slip does not extend it —
## the slip's "waits ~Ns" is the same clock the HUD counts down). An expired
## walk-in despawns; if a machine still holds the walk-in contract Main
## cancels it through the overnight-cancel teardown calls. Expiry itself is
## observationally inert: no log, no rep, no money (BOT-SAFETY INVARIANT).
##
## Waiting walk-ins are NOT persisted: a reload spawns nobody (documented in
## docs/worker-walkin.md); only the lifetime counters persist.

## Business window (day fraction): arrivals only inside it.
const DAY_START_FRAC := 0.15
const DAY_END_FRAC := 0.80
## Arrival slots per day; at most one customer waiting at a time.
const SLOTS_PER_DAY := 2
## Per-(day, slot) arrival gate: slot live when hash % 10 < 6.
const GATE_DIVISOR := 10
const GATE_THRESHOLD := 6
## Slot i is due at BASE + STEP * i + JITTER * (hash jitter 0..3).
const ARRIVAL_BASE_FRAC := 0.25
const ARRIVAL_SLOT_STEP := 0.22
const ARRIVAL_JITTER := 0.03
## Patience: 0.55 of a shop day, deadline fixed at arrival.
const PATIENCE_DAYS := 0.55
## Two-press slip window (seconds of shop time) before the arm disarms.
const ARM_WINDOW_S := 8.0
## Walk-in contracts generate at board index 100+ so they can never collide
## with the board's dealt slots (0..7).
const BOARD_INDEX_BASE := 100


## Is arrival slot i live on `day`? Deterministic per (day, i).
static func slot_enabled(day: int, i: int) -> bool:
	return absi(hash("walkin-%d-%d" % [day, i])) % GATE_DIVISOR < GATE_THRESHOLD


## Day fraction arrival slot i is due at on `day`. Deterministic; always
## inside 0.25..0.53, i.e. inside the business window.
static func slot_time(day: int, i: int) -> float:
	return ARRIVAL_BASE_FRAC + ARRIVAL_SLOT_STEP * float(i) \
		+ ARRIVAL_JITTER * float(absi(hash("walkin-t-%d-%d" % [day, i])) % 4)


## Patience deadline as an absolute day+frac value for an arrival at `frac`.
## May exceed 1.0 — a customer who steps in late in the day leaves early
## the next day (Main's expiry check handles the wrap).
static func patience_deadline_frac(frac: float) -> float:
	return frac + PATIENCE_DAYS


## Absolute (day + frac) position of a walk-in state's deadline.
static func deadline_abs(state: Dictionary) -> float:
	var df := float(state.get("deadline_frac", 0.0))
	return float(int(state.get("day", 1))) + float(int(df)) + fmod(df, 1.0)


## Has the walk-in state's patience run out at (day, frac)?
static func is_expired(state: Dictionary, day: int, frac: float) -> bool:
	if state.is_empty():
		return false
	return float(day) + frac >= deadline_abs(state)


## Seconds of patience left for `state` at (day, frac), clamped at 0.
static func patience_left_s(state: Dictionary, day: int, frac: float,
		day_length_s: float) -> float:
	if state.is_empty():
		return 0.0
	var left := deadline_abs(state) - (float(day) + frac)
	return maxf(left, 0.0) * maxf(day_length_s, 0.0)


## The walk-in's client name: a first name from Contract's existing pool,
## drawn deterministically per (day, index).
static func client_name(day: int, index: int) -> String:
	return Contract.GEN_FIRSTS[absi(hash("walkin-name-%d-%d" % [day, index]))
		% Contract.GEN_FIRSTS.size()]


## The slip's contract: a generated board-slot contract at an index the
## board never uses, forced single-part with a never-binding deadline and
## tagged walk_in. Client name is the walk-in draw (a person, not an org).
static func make_contract(day: int, index: int, max_difficulty: int) -> Contract:
	var c := Contract.generate(day, BOARD_INDEX_BASE + index, max_difficulty)
	c.parts_total = 1
	c.deadline_days = 2
	c.walk_in = true
	c.client = client_name(day, index)
	return c


## --- instance state ------------------------------------------------------------

## The one waiting (or accepted-but-unserved) walk-in; {} when nobody waits.
## Shape: {day, index, client, contract, accepted, deadline_frac, machine_idx}.
var state := {}

## Crossing memory for due(): the tick's last (day, frac) and which slots
## were already handled (fired or skipped) on the current day.
var _tick_day := -1
var _tick_frac := -1.0
var _handled := {}


func waiting() -> bool:
	return not state.is_empty()


## Fill the state for a fresh arrival at day fraction `frac`. Main calls
## this from the arrival path (never at boot, never while paused).
func begin(day: int, index: int, contract: Contract, frac: float) -> void:
	state = {
		"day": day,
		"index": index,
		"client": contract.client,
		"contract": contract,
		"accepted": false,
		"deadline_frac": patience_deadline_frac(frac),
		"machine_idx": -1,
	}


## Clear the state (serve or expiry teardown); Main despawns the actor.
func clear() -> void:
	state = {}


## Which arrival slot (0 or 1) is due at this tick, or -1. Crossing
## semantics: slot i fires when `frac` crosses slot_time(day, i) since the
## previous tick. A due slot is skipped ENTIRELY (marked handled, never
## deferred) when someone already waits or the window is closed. A day
## change resets the crossing memory — slots never leak across days.
func due(day: int, frac: float, waiting_now: bool) -> int:
	if day != _tick_day:
		# First tick of a day (boot, reload, rollover): seed the crossing
		# memory without firing — a mid-day reload must not spawn the
		# morning's already-passed slot out of nowhere.
		_tick_day = day
		_tick_frac = frac
		_handled.clear()
		return -1
	var prev := _tick_frac
	_tick_frac = frac
	if waiting_now:
		# Someone waits: mark every crossed slot handled so a served-or-
		# expired customer's slots cannot pile up behind them mid-day.
		for i in range(SLOTS_PER_DAY):
			if not _handled.has(i) and prev < slot_time(day, i) \
					and slot_time(day, i) <= frac:
				_handled[i] = true
		return -1
	var window_open := frac >= DAY_START_FRAC and frac <= DAY_END_FRAC
	for i in range(SLOTS_PER_DAY):
		if _handled.has(i):
			continue
		if not slot_enabled(day, i):
			_handled[i] = true
			continue
		var t := slot_time(day, i)
		if t < DAY_START_FRAC or t > DAY_END_FRAC:
			_handled[i] = true
			continue
		if prev < t and t <= frac:
			_handled[i] = true
			if window_open:
				return i
			# Night/edge-of-window call: the slot is skipped entirely.
	return -1
