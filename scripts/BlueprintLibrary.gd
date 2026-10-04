class_name BlueprintLibrary
extends RefCounted

const SAVE_PATH := "user://printshop_blueprints.json"
const CAP := 12
var path: String
var _entries: Array[Dictionary] = []

func _init(save_path := SAVE_PATH) -> void:
	path = save_path

func entries() -> Array[Dictionary]:
	return _entries.duplicate(true)

func read() -> bool:
	if not FileAccess.file_exists(path):
		return true
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var data: Variant = JSON.parse_string(file.get_as_text())
	if not data is Dictionary or data.get("version") != 1 or not data.get("entries") is Array:
		return false
	var parsed: Array[Dictionary] = []
	for entry in data.entries:
		if not entry is Dictionary or not entry.get("title") is String or not entry.get("design") is Dictionary:
			return false
		if str(entry.title).strip_edges().is_empty():
			return false
		if parsed.size() >= CAP:
			break
		parsed.append({"title": str(entry.title).left(32), "design": entry.design.duplicate(true)})
	_entries = parsed
	return true

func save(title: String, design: Dictionary) -> bool:
	title = title.strip_edges().replace("\n", " ").left(32)
	if title.is_empty() or design.is_empty():
		return false
	var previous := entries()
	var index := -1
	for i in _entries.size():
		if title.nocasecmp_to(str(_entries[i].title)) == 0:
			index = i
	var entry := {"title": title, "design": design.duplicate(true)}
	if index >= 0:
		_entries[index] = entry
	elif _entries.size() < CAP:
		_entries.append(entry)
	else:
		return false
	if not _write():
		_entries = previous
		return false
	return true

func remove(index: int) -> bool:
	if index < 0 or index >= _entries.size():
		return false
	var previous := entries()
	_entries.remove_at(index)
	if not _write():
		_entries = previous
		return false
	return true

func _write() -> bool:
	var temp_path := path + ".tmp"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify({"version": 1, "entries": _entries}))
	var error := file.get_error()
	file.close()
	if error != OK:
		return false
	return DirAccess.rename_absolute(temp_path, path) == OK
