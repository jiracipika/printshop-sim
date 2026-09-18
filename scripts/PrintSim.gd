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
	state = State.RUNNING
	print_started.emit()

func estimated_print_time_s() -> float:
	# simulated print seconds = ticks needed x sim-seconds per tick
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
	elapsed_sim_time_s += delta * SIM_TIME_SCALE
	_tick_accum += delta
	while _tick_accum >= 1.0 / TICK_HZ:
		_tick_accum -= 1.0 / TICK_HZ
		_step_tick()

func _step_tick() -> void:
	if _failed:
		state = State.DONE_FAIL
		print_finished.emit(false)
		return
	layers_done += 1
	if failure_seeded and layers_done == int(layers_total / 2):  # seeded mid-print failure
		_failed = true
	if layers_done >= layers_total:
		state = State.DONE_OK
		print_finished.emit(true)
