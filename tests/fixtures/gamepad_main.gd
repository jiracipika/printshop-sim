extends "res://scripts/Main.gd"

## Only platform device discovery is substituted; callbacks remain real.
var test_pad_connected := false

func _has_gamepad() -> bool:
	return test_pad_connected
