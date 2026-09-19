class_name QualityCheck
extends RefCounted

## Task 11 (station layer) — pure inspection grading logic.
## No scene, no Main access, no ledger. Deterministic.
##
## Grading rules (documented contract):
##   - The grade looks at two independent gates: completeness and risk.
##   - Completeness: ratio = final_layer / total_layers.
##       complete      := final_layer == total_layers  (and total_layers > 0)
##       mostly_done   := final_layer >= 0.9 * total_layers (ceil-free float compare)
##   - Risk: max_risk = max value in `risks`. Any value outside [0, 1]
##     is "wild" data (sensor/analyzer garbage) and fails outright -> "F".
##   - Grade:
##       "A" : complete and max_risk < 0.5
##       "B" : complete and max_risk < 0.7
##       "C" : not complete but mostly_done and all risks in [0, 1]
##       "F" : anything else (incomplete beyond 0.9, wild risks,
##             or degenerate input such as total_layers <= 0)
##   - Boundary notes (exact-threshold behavior, tested in packing_test.gd):
##       max_risk == 0.5 -> NOT A (0.5 is excluded from A by strict <)
##       max_risk == 0.7 -> NOT B (excluded from B by strict <, falls to C if complete)
##       final == 0.9 * total exactly -> C (>= boundary is inclusive)


static func grade(_contract: Contract, final_layer: int, total_layers: int, risks: Dictionary) -> String:
	# Degenerate / impossible prints never pass inspection.
	if total_layers <= 0 or final_layer < 0 or final_layer > total_layers:
		return "F"

	# Wild risk values fail inspection outright.
	for key in risks:
		var v: float = float(risks[key])
		if v < 0.0 or v > 1.0:
			return "F"

	var complete := final_layer == total_layers
	var max_risk := 0.0
	for key in risks:
		max_risk = maxf(max_risk, float(risks[key]))

	if complete:
		if max_risk < 0.5:
			return "A"
		if max_risk < 0.7:
			return "B"
		return "C"

	# Incomplete but substantially done: C at best (risks are already sane).
	if float(final_layer) >= 0.9 * float(total_layers):
		return "C"
	return "F"


static func quality_multiplier(grade_str: String) -> float:
	match grade_str:
		"A":
			return 1.0
		"B":
			return 0.9
		"C":
			return 0.7
	return 0.0  # "F" and anything unknown pay nothing
