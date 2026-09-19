# GLM worker checkpoint — save system slice (task 12, save portion)

Model: glm-5.3-flash via zai coding plan. Branch main @ edb922b (pull --ff-only clean).
Status: COMPLETE and GREEN, awaiting Astra review. No integration into Main.gd (parent owns).

## Files owned and created
- scripts/SaveSystem.gd — versioned payload builder/validator (pure logic, RefCounted)
- scripts/BrowserSave.gd — FileAccess persistence adapter at user:// (atomic tmp+rename)
- tests/save_test.gd — 44 checks, all passing
- docs/worker-save.md — this file
- Generated UIDs: scripts/SaveSystem.gd.uid, scripts/BrowserSave.gd.uid, tests/save_test.gd.uid

No gameplay files touched. No PrepSystem/PackingStation symbol references.

## Design
- SaveSystem.VERSION := 1. build_payload() deep-copies inputs, stamps saved_at_unix.
- validate() returns {} on ANY malformed input (never throws; fuzz-tested with 7
  adversarial shapes + non-dict types). Returns a normalized deep copy otherwise:
  all int-ish fields coerced to int, chain replay checked against ledger balance.
- JSON round-trip yields floats: validate accepts whole floats and normalizes them
  to int; fractional/non-numeric values are rejected. This makes load-from-disk work
  while still rejecting corrupt numerics.
- Ledger validation mirrors Ledger.snapshot()/restore() shape (all 4 keys,
  non-negative balance, transaction delta chain must replay to balance, paid ids
  are non-empty strings). Ledger.restore() remains the final gate for Main.

## BrowserSave API
- static save_path (test-injectable; default user://printshop_save_v1.json)
- save_payload(): JSON to .tmp then DirAccess.rename_absolute; removes tmp on rename failure
- load_payload(): {} on missing/unreadable/unparseable/invalid (routes through validate)
- clear(), exists(), corrupt_file_for_test() (test-only junk-byte writer)
- user:// only — no JS/localStorage touched; works headless and in web export

## Parent integration path (follow-up, not in this slice)
On Main._ready: `var p := BrowserSave.load_payload()`; if non-empty:
ledger.restore(p.ledger); rebuild paid set from p.paid_ids or ledger.paid_contract_ids;
balance := p.balance_cents (ledger.balance() already equals it post-restore).
active_contract (if {}) means no contract to restore; non-empty is a Contract-shaped
Dictionary for the parent to rebuild/decide.

## Verification evidence (real runs, Godot 4.7.1 headless)
- RED first: SaveSystem/BrowserSave undeclared parse errors before implementation.
- GREEN: `godot --headless --path . -s tests/save_test.gd` → checks=44 failures=0
  (build shape, round-trip equality, version 0/99/non-numeric rejection, negative
  balance, non-dict ledger, transaction missing balance_after, chain-mismatch
  rejection, paid_ids type/content rejection, 7-shape fuzz, save→exists→load
  canonical equality, overwrite, corrupt→{} fallback, clear→exists false,
  no .tmp residual, path override isolation).

## Notes / caveats
- validate() canonical-equality test uses Dictionary hash() comparison.
- Godot global class registration required one `--import` scan before the -s test
  saw SaveSystem/BrowserSave class names (first run after file creation only).
- No git commit/push/export/README — parent owns per instructions.
