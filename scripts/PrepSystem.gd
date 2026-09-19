class_name PrepSystem
extends RefCounted

## Task 09 slice — orientation and support preparation heuristics.
## Engine-free pure logic: no scene tree, no RNG state, no side effects.
## Deterministic heuristics (documented so tests can pin exact numbers):
##
##   upright:    support 0.0  (+0.35 if "overhangs" flag); adhesion 0.15;
##               stability 0.10; material = layers * 6; time = layers * 2.4
##   tilted:     support 0.55 (+0.2 if "overhangs"); adhesion 0.15;
##               stability 0.35; material = (layers*6)*1.4; time = (layers*2.4)*1.25
##   flat_side:  support 0.45; adhesion 0.55 (+0.15 if "bed adhesion");
##               stability 0.30; material = (layers*6)*1.2; time = (layers*2.4)*1.1
##               INVALID (reason "not printable flat") if "stability" flag present.
##
## risk_level thresholds on max(support, adhesion, stability):
##   < 0.4 -> "low", < 0.6 -> "medium", otherwise "high".


static func orientations() -> Array[String]:
	return ["upright", "tilted", "flat_side"]


static func evaluate(contract: Contract, orientation: String) -> Dictionary:
	var layers := contract.layers
	var has_overhangs: bool = "overhangs" in contract.risk_flags
	var has_bed_adhesion: bool = "bed adhesion" in contract.risk_flags
	var has_stability: bool = "stability" in contract.risk_flags

	var base_material := float(layers) * 6.0
	var base_time := float(layers) * 2.4

	match orientation:
		"upright":
			return {
				"valid": true,
				"reason": "",
				"support_need": 0.35 if has_overhangs else 0.0,
				"adhesion_risk": 0.15,
				"stability_risk": 0.10,
				"estimated_material_g": int(base_material),
				"estimated_time_s": base_time,
			}
		"tilted":
			return {
				"valid": true,
				"reason": "",
				"support_need": 0.75 if has_overhangs else 0.55,
				"adhesion_risk": 0.15,
				"stability_risk": 0.35,
				"estimated_material_g": int(base_material * 1.4),
				"estimated_time_s": base_time * 1.25,
			}
		"flat_side":
			if has_stability:
				return {
					"valid": false,
					"reason": "not printable flat",
					"support_need": 0.45,
					"adhesion_risk": 0.70 if has_bed_adhesion else 0.55,
					"stability_risk": 0.30,
					"estimated_material_g": int(base_material * 1.2),
					"estimated_time_s": base_time * 1.1,
				}
			return {
				"valid": true,
				"reason": "",
				"support_need": 0.45,
				"adhesion_risk": 0.70 if has_bed_adhesion else 0.55,
				"stability_risk": 0.30,
				"estimated_material_g": int(base_material * 1.2),
				"estimated_time_s": base_time * 1.1,
			}
	# Unknown orientation: fail closed with a reason.
	return {"valid": false, "reason": "unknown orientation", "support_need": 0.0,
		"adhesion_risk": 0.0, "stability_risk": 0.0,
		"estimated_material_g": 0, "estimated_time_s": 0.0}


static func risk_level(evaluation: Dictionary) -> String:
	var worst: float = maxf(
		maxf(float(evaluation.get("support_need", 0.0)),
			float(evaluation.get("adhesion_risk", 0.0))),
		float(evaluation.get("stability_risk", 0.0)))
	if worst < 0.4:
		return "low"
	if worst < 0.6:
		return "medium"
	return "high"
