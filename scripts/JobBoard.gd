extends Node

## Simple job queue: endless generated jobs so the loop is always playable.

var _jobs: Array[Dictionary] = []
var _next_id := 1

const MODELS := [
	{"name": "Benchy Bracket", "layers": 40},
	{"name": "Gear Cover", "layers": 65},
	{"name": "Phone Stand", "layers": 30},
	{"name": "Cable Clip", "layers": 18},
	{"name": "Hex Organizer", "layers": 55},
]

func _ready() -> void:
	for i in 3:
		_push_job()

func _push_job() -> void:
	var m: Dictionary = MODELS[randi() % MODELS.size()]
	_jobs.append({
		"id": "JOB-%03d" % _next_id,
		"model": m.name,
		"layers": m.layers,
	})
	_next_id += 1

func has_available() -> bool:
	return not _jobs.is_empty()

func get_available_count() -> int:
	return _jobs.size()

func take_next() -> Dictionary:
	var job: Dictionary = _jobs.pop_front()
	_push_job()
	return job
