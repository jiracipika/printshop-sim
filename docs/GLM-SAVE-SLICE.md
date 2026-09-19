# GLM next slice — save system with versioned corruption fallback

Astra-approved. Read AGENTS.md, docs/HANDOFF.md, scripts/Ledger.gd (snapshot/restore), scripts/Contract.gd, scripts/JobBoard.gd, scripts/Main.gd first. Work only /Volumes/HARD/projects/printshop-sim. git pull --ff-only (main at edb922b). Model pinned glm-5.3-flash via zai coding plan (GLM_BASE_URL set by parent). Stop on quota/auth, no fallback. Never touch automated-newsletter or pitchforge/pitch-therapy.

PARALLEL WORKER WARNING: other workers are editing PrintSim.gd, Main.gd (prep + packing integration), PrepSystem.gd, PackingStation.gd, QualityCheck.gd and their tests. To avoid collisions you own ONLY:
- new scripts/SaveSystem.gd (pure logic, class_name SaveSystem extends RefCounted)
- new scripts/BrowserSave.gd (persistence adapter; user:// works headless and in web export via Godot's filesystem abstraction — do NOT touch JS/localStorage directly)
- tests/save_test.gd
- docs/worker-save.md
- generated UID files
You must NOT edit Main.gd or any gameplay file — integration is a parent follow-up. No reference to PrepSystem/PackingStation symbols.

Scope (design/implementation-plan.md task 12 save portion):
1. SaveSystem.gd — versioned save payload builder/validator:
   - const VERSION := 1
   - static build_payload(ledger_snapshot: Dictionary, active_contract: Dictionary, balance_cents: int, paid_ids: Array) -> Dictionary: {"version": VERSION, "balance_cents": int, "ledger": ledger_snapshot, "active_contract": active_contract (may be {}), "paid_ids": paid_ids, "saved_at_unix": int(Time.get_unix_time_from_system())}
   - static validate(payload: Variant) -> Dictionary: returns {} if invalid (wrong version type, negative balance, non-dict ledger, non-array paid_ids, malformed transactions) else a normalized copy. Defensive: never throws on garbage input (fuzz-tested with strings/arrays/nested junk).
2. BrowserSave.gd — adapter around Godot FileAccess at user://printshop_save_v1.json:
   - save_payload(payload: Dictionary) -> bool (atomic-ish: write .tmp then rename)
   - load_payload() -> Dictionary ({} on missing/corrupt; JSON.parse via JSON.parse_string; validates through SaveSystem.validate)
   - clear() -> bool
   - exists() -> bool
   - static corrupt_file_for_test() -> void (writes junk bytes; used by tests to prove fallback; test-only but harmless in prod)
3. Main integration NOT in this slice. But design payload fields so Main can later do: on _ready load -> restore ledger from payload.ledger via Ledger restore, rebuild paid set, restore balance.
4. Tests (tests/save_test.gd): build/validate round-trip; validate rejects: version 0, version 99 treated as invalid, negative balance, ledger missing balance_after fields, paid_ids not array, non-dict input, random nested garbage (loop several adversarial shapes); BrowserSave: save->exists->load round-trip equality of canonical fields; corrupt file -> load returns {} without throwing; clear -> exists false; save twice -> second overwrites; tmp file never left behind (no .tmp residual). Use unique user:// test filenames if needed via an injectable path parameter (static var save_path for test override, default constant). Bounded subprocess runs (timeout=60), scan SCRIPT ERROR/Parse Error. Real RED then GREEN.

No export/browser/git/README — parent owns. First inspection immediately, minimal prose, code early. Checkpoint docs/worker-save.md before budget expiry.
