# GLM next slice — contract and money data

Astra-approved. Read AGENTS.md, docs/HANDOFF.md, design/implementation-plan.md (task 08), design/menu-contracts.html for data shape inspiration first. Work only /Volumes/HARD/projects/printshop-sim. git pull --ff-only (main at 70b8155, deployed). Model pinned glm-5.3-flash via zai coding plan (GLM_BASE_URL set by parent). Stop on quota/auth, no fallback. Never touch automated-newsletter or pitchforge/pitch-therapy.

Exclusive files: new scripts/Contract.gd, new scripts/Ledger.gd, tests/contract_test.gd, docs/worker-contract.md, generated UID files. You may NOT touch Main.gd, PrintSim.gd, JobBoard.gd, or any existing test — this slice is pure data + logic, integration comes later.

Implement now, not a plan.

1. Contract.gd — class_name Contract, extends Resource. Fields: id: String, client: String, model_name: String, payout_cents: int, material_cost_cents: int, difficulty: int (1-5), risk_flags: Array[String] (subset: "overhangs","bed adhesion","stability"), layers: int, deadline_days: int. Enum State {OFFERED, ACCEPTED, PREPARING, PRINTING, INSPECTION, PACKED, DELIVERED, FAILED} with is_terminal() and static legal_transitions(from) -> Array[State] (documented table; FAILED reachable from PREPARING/PRINTING/INSPECTION; DELIVERED only from PACKED).

2. Ledger.gd — class_name Ledger, extends RefCounted. Fields: balance_cents: int (start 0), transactions: Array[Dictionary] ({id:int seq, reason:String, delta_cents:int, balance_after:int}). Methods: balance() -> int, can_afford(cents) -> bool, charge(cents, reason) -> bool (false + no mutation if insufficient or negative), credit(cents, reason) -> bool (rejects negative), has_paid(contract_id) -> bool, pay_once(contract_id, cents, reason) -> bool (exactly-once per contract id), transaction_count() -> int, snapshot()/restore(dict) for future saves. No floats anywhere; assert non-negative balance invariant in every mutator.

3. Fixture data + factory in Contract.gd: static make_fixture_jobs() -> Array[Contract] with at least 4 varied jobs (values inspired by design/menu-contracts.html but integer cents: e.g. 6400, 8750...). Deterministic, no RNG.

Behavioral RED/GREEN tests (tests/contract_test.gd) — pure SceneTree test, no Main scene: contract construction/validation (difficulty bounds, risk flag subset, payout > 0); full legal state path OFFERED→...→DELIVERED and each illegal jump rejected (write a transition-table probe covering ALL from→to pairs); FAILED reachable exactly from {PREPARING, PRINTING, INSPECTION}; ledger: insufficient charge rejected without mutation; negative credit rejected; exactly-once pay_once (second call false, single credit entry); balance reconciliation after mixed operations equals sum of deltas; balance never negative across all operations; snapshot/restore round-trip preserves balance and pay_once history. Bounded subprocess run (timeout=60), scan SCRIPT ERROR/Parse Error. Record real RED then GREEN.

Do not integrate with gameplay yet. No git/export/browser/README changes — parent owns those. First inspection immediately, minimal prose, code early. Checkpoint docs/worker-contract.md (files, commands, outcomes, NOT-RUN list) before budget expiry.
