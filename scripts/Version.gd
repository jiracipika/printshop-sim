extends Node

# Autoload: build/version identification so we always know what's deployed.

const VERSION := "0.39.0"
const GIT_SHA := "9d42ef7"  # stamped by tools/build_web.sh at export time

func label() -> String:
	if GIT_SHA.is_empty():
		return "Alpha %s" % VERSION
	return "Alpha %s Git: %s" % [VERSION, GIT_SHA]
