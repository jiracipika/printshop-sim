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
const META_PATH := "user://printshop_meta.json"
const SLOT_COUNT := 3

static var save_path: String = DEFAULT_PATH


## Save slots (v0.41.0): three shops live side by side; the META file
## remembers which slot is active (last played). save_path keeps working
## for tests — switching slots only moves the real save file.
static func slot_path(slot: int) -> String:
	if slot < 1 or slot > SLOT_COUNT:
		return DEFAULT_PATH
	return "user://printshop_save_slot%d.json" % slot


static func switch_slot(slot: int) -> void:
	if slot >= 1 and slot <= SLOT_COUNT:
		save_path = slot_path(slot)


static func active_slot() -> int:
	if save_path == DEFAULT_PATH:
		return 1
	for i in range(1, SLOT_COUNT + 1):
		if save_path == slot_path(i):
			return i
	return 1


## META file: tiny free-form record outside the slots themselves.
static func save_meta(meta: Dictionary) -> bool:
	var f := FileAccess.open(META_PATH, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(meta))
	f.flush()
	f.close()
	return true


static func load_meta() -> Dictionary:
	if not FileAccess.file_exists(META_PATH):
		return {}
	var f := FileAccess.open(META_PATH, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		return parsed
	return {}


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
	# Pre-boot clears (save_path still DEFAULT) mean "fresh environment":
	# remove every slot file too, so a stale slot doesn't leak into the
	# next boot. In slot mode (save_path = slot file) only that file is
	# removed — production reset must never wipe the other shops.
	if save_path == DEFAULT_PATH:
		for i in range(1, SLOT_COUNT + 1):
			var sp := slot_path(i)
			if FileAccess.file_exists(sp):
				DirAccess.remove_absolute(sp)
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
