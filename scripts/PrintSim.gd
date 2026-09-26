extends Node

class_name PrintSim

signal print_started
signal print_finished(ok: bool)

enum State { IDLE, PREPARING, RUNNING, DONE_OK, DONE_FAIL }

const TICK_HZ := 10.0           # sim ticks per real second
const SIM_TIME_SCALE := 240.0   # simulated print seconds per real second
const LAYER_H := 0.02           # display layer height (visual + scores)
const MATERIAL_G_PER_LAYER := 6 # grams per display layer (stub, tune later)

var job_id := ""
var model_name := ""
var layers_total := 0
var layers_done := 0
var elapsed_sim_time_s := 0.0
var elapsed_real_time_s := 0.0
var _tick_accum := 0.0

# Per-job score accumulators (stub heuristics; replaced by analyzer later)
var support_need := 0.35
var adhesion_risk := 0.25
var stability_risk := 0.20
var failure_seeded := false
var _failed := false

## Task 09 seam: deterministic risk-driven failure. Main writes the evaluated
## prep risks into these fields BEFORE start_job; start_job rolls ONE outcome
## for the whole print (no per-tick RNG): a deterministic pseudo-random draw
## keyed on job_id only, normalized 0..1 — no global RNG state, so the same
## job_id + same risks always produce the same outcome across runs/instances.
## failure_chance = max(0, max(risks) - 0.4) * failure_threshold; a roll below
## that means the print fails mid-way (tick = _failure_roll * layers_total).
var failure_threshold: float = 0.55
var _failure_tick: int = -1

## Task 12 upgrade seam: multiplies sim time accumulation so owned extruder
## upgrades genuinely shorten prints. Layer counts, progress and the
## deterministic failure roll are unaffected (the roll is layer-keyed).
var speed_multiplier: float = 1.0

var state: State = State.IDLE

func get_state_name() -> String:
	match state:
		State.IDLE: return "IDLE"
		State.PREPARING: return "PREPARING"
		State.RUNNING: return "RUNNING"
		State.DONE_OK: return "DONE_OK"
		State.DONE_FAIL: return "DONE_FAIL"
	return "?"

func is_running() -> bool:
	return state == State.RUNNING

func start_job(id: String, model: String, layers: int) -> void:
	if state == State.RUNNING or state == State.PREPARING:
		return
	job_id = id
	model_name = model
	layers_total = layers
	layers_done = 0
	elapsed_sim_time_s = 0.0
	elapsed_real_time_s = 0.0
	_tick_accum = 0.0
	_failed = false
	_failure_tick = -1
	if not failure_seeded:
		_roll_failure_tick()
	state = State.RUNNING
	print_started.emit()

## One deterministic outcome roll per print (task 09). Hash is Godot's builtin
## String hash — stable for the same string across runs and platforms in a
## session; no RandomNumberGenerator / global RNG state involved.
func _roll_failure_tick() -> void:
	var worst: float = maxf(maxf(support_need, adhesion_risk), stability_risk)
	var chance: float = maxf(0.0, worst - 0.4) * failure_threshold
	if chance <= 0.0:
		_failure_tick = -1
		return
	var draw := float(absi(hash(job_id)) % 100000) / 100000.0
	if draw < chance:
		# Deterministic mid-print tick for the failure.
		_failure_tick = maxi(1, int(draw / chance * float(layers_total)))
	else:
		_failure_tick = -1

func estimated_print_time_s() -> float:
	# simulated print seconds = ticks needed x sim-seconds per tick
	# (speed_multiplier shortens the real-world wait, not the job's duration)
	return float(layers_total) * SIM_TIME_SCALE / TICK_HZ

func material_used_g() -> int:
	return int(layers_done * MATERIAL_G_PER_LAYER)

func progress() -> float:
	if layers_total <= 0:
		return 0.0
	return clampf(float(layers_done) / float(layers_total), 0.0, 1.0)

func support_score() -> float:
	return clampf(1.0 - support_need, 0.0, 1.0)

func bed_adhesion_score() -> float:
	return clampf(1.0 - adhesion_risk, 0.0, 1.0)

func stability_score() -> float:
	return clampf(1.0 - stability_risk, 0.0, 1.0)

func current_risks() -> Array[String]:
	var risks: Array[String] = []
	if support_need > 0.5:
		risks.append("overhangs")
	if adhesion_risk > 0.5:
		risks.append("bed adhesion")
	if stability_risk > 0.5:
		risks.append("stability")
	return risks

func tick(delta: float) -> void:
	if state != State.RUNNING:
		return
	elapsed_real_time_s += delta
	elapsed_sim_time_s += delta * SIM_TIME_SCALE * speed_multiplier
	_tick_accum += delta * speed_multiplier
	# Guard against reentrant completion: a large delta can cover several
	# ticks, but once the print finishes the remaining budget must not step
	# past layers_total or emit print_finished twice.
	while _tick_accum >= 1.0 / TICK_HZ and state == State.RUNNING:
		_tick_accum -= 1.0 / TICK_HZ
		_step_tick()


## Full reset back to IDLE (task 12: clearing a failed print off the bed).
## Does not emit signals — the printer/visual cleanup is the caller's job.
func reset() -> void:
	state = State.IDLE
	job_id = ""
	model_name = ""
	layers_total = 0
	layers_done = 0
	elapsed_sim_time_s = 0.0
	elapsed_real_time_s = 0.0
	_tick_accum = 0.0
	_failed = false
	_failure_tick = -1

func _step_tick() -> void:
	if _failed:
		state = State.DONE_FAIL
		print_finished.emit(false)
		return
	layers_done += 1
	if failure_seeded and layers_done == int(layers_total / 2):  # seeded mid-print failure
		_failed = true
	elif _failure_tick >= 0 and layers_done == _failure_tick:
		_failed = true  # risk-rolled deterministic failure (task 09 seam)
	if layers_done >= layers_total:
		state = State.DONE_OK
		print_finished.emit(true)
