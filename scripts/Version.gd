extends Node

# Autoload: build/version identification so we always know what's deployed.

const VERSION := "0.63.0"
const GIT_SHA := ""  # populated by tools/build_web.sh for an exported build

func label() -> String:
	if GIT_SHA.is_empty():
		return "Alpha %s" % VERSION
	return "Alpha %s Git: %s" % [VERSION, GIT_SHA]
