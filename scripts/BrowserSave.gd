class_name BrowserSave
extends RefCounted

## Task 12 (save portion) — persistence adapter for the save system.
## All I/O goes through Godot's FileAccess at user://, which works headless
## and in web export via Godot's filesystem abstraction (no JS/localStorage).
##
## save_payload: atomic-ish write (tmp file + rename).
## load_payload: {} on missing/corrupt/invalid — never throws.
## save_path is a static var so tests can point at an isolated user:// file.

const DEFAULT_PATH := "user://printshop_save_v1.json"

static var save_path: String = DEFAULT_PATH


static func _tmp_path() -> String:
	return save_path + ".tmp"


func _ready() -> void:
	pass  # RefCounted: no lifecycle; keeps static-only class explicit.


static func exists() -> bool:
	return FileAccess.file_exists(save_path)


## Atomic-ish: write payload JSON to a .tmp file, then rename over the real
## path so a crash mid-write cannot leave a half-written save.
static func save_payload(payload: Dictionary) -> bool:
	var text := JSON.stringify(payload)
	var f := FileAccess.open(_tmp_path(), FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	f.flush()
	f.close()
	var err := DirAccess.rename_absolute(_tmp_path(), save_path)
	if err != OK:
		# Best effort: do not leave the tmp file behind on rename failure.
		DirAccess.remove_absolute(_tmp_path())
		return false
	return true


## Reads and validates through SaveSystem.validate. Returns {} when the file
## is missing, unreadable, unparseable, or fails validation.
static func load_payload() -> Dictionary:
	if not FileAccess.file_exists(save_path):
		return {}
	var f := FileAccess.open(save_path, FileAccess.READ)
	if f == null:
		return {}
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null:
		return {}
	return SaveSystem.validate(parsed)


static func clear() -> bool:
	if not FileAccess.file_exists(save_path):
		return true
	return DirAccess.remove_absolute(save_path) == OK


## Test-only helper: fills the save file with junk bytes so tests can prove
## the corruption fallback. Harmless in production but not called by gameplay.
static func corrupt_file_for_test() -> void:
	var junk := PackedByteArray()
	for i in 64:
		junk.append((i * 37 + 11) % 256)
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f != null:
		f.store_buffer(junk)
		f.flush()
		f.close()
