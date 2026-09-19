# GLM next slice — inspection and packaging stations

Astra-approved. Read AGENTS.md, docs/HANDOFF.md, docs/worker-economy.md, scripts/Main.gd, scripts/Contract.gd, scripts/PrepSystem.gd (if present from parallel worker — read-only; if absent, do not reference it), scripts/PrintSim.gd first. Work only /Volumes/HARD/projects/printshop-sim. git pull --ff-only (main at edb922b). Model pinned glm-5.3-flash via zai coding plan (GLM_BASE_URL set by parent). Stop on quota/auth, no fallback. Never touch automated-newsletter or pitchforge/pitch-therapy.

PARALLEL WORKER WARNING: another worker is editing scripts/PrintSim.gd, scripts/Main.gd (prep/orientation sections), scripts/PrepSystem.gd, tests/prep_test.gd. To avoid collisions you own ONLY:
- new scripts/PackingStation.gd (scene node script)
- new scripts/QualityCheck.gd (pure logic)
- tests/packing_test.gd
- docs/worker-packing.md
- generated UID files
You must NOT edit Main.gd, PrintSim.gd, PrepSystem.gd, JobBoard.gd, Contract.gd, Ledger.gd, Grabbable.gd, TouchControls.gd, Printer.gd, PrintVisual.gd, or any existing test. Design your scripts so Main integration is a small follow-up (parent does it): clean public API, no Main references.

Scope (from design/implementation-plan.md task 11, station layer only):
1. QualityCheck.gd — class_name QualityCheck, extends RefCounted. Pure logic:
   - static grade(contract: Contract, final_layer: int, total_layers: int, risks: Dictionary) -> String: returns "A" (final==total, max risk < 0.5), "B" (final==total, max risk < 0.7), "C" (final >= 0.9*total), "F" otherwise (incomplete print or wild risks). Deterministic, documented.
   - static quality_multiplier(grade: String) -> float: A=1.0, B=0.9, C=0.7, F=0.0.
2. PackingStation.gd — class_name PackingStation, extends Node3D. Physical station built from primitives matching design language (honey plywood table 1.2x0.9x0.9 with dark steel legs + terracotta fascia stripe, small cardboard-tone box on top ~0.3m, a StaticBody3D collision box, group "stations", meta station_kind = "packing"). Exposes:
   - signal packed(contract_id: String, grade: String, payout_cents: int)
   - var last_result: Dictionary = {}
   - func try_pack(contract: Contract, sim_snapshot: Dictionary) -> Dictionary: validates contract.state == INSPECTION, grades via QualityCheck using sim_snapshot ({"final_layer","total_layers","risks"}), computes payout = roundi(contract.payout_cents * multiplier), sets last_result {id, grade, payout_cents, packed: bool, reason}, emits packed only when packed true. Rejects wrong state with reason. No ledger access, no Main access.
3. Tests (tests/packing_test.gd): grade boundaries at exact thresholds (construct dicts hitting 0.5/0.7/0.9 precisely); multiplier table complete; try_pack on non-INSPECTION contract rejected with reason and no signal; A-grade full payout; B 90%; C 70%; F zero and packed false; packed signal emitted exactly once with right args; station has collision body + groups. Bounded subprocess runs (timeout=60), scan SCRIPT ERROR/Parse Error. Real RED then GREEN.

No export/browser/git/README — parent owns. First inspection immediately, minimal prose, code early. Checkpoint docs/worker-packing.md before budget expiry.
