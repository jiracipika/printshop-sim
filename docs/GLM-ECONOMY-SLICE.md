# GLM next slice — wire contracts and money into gameplay

Astra-approved. Read AGENTS.md, docs/worker-contract.md (integration notes), docs/HANDOFF.md, scripts/Contract.gd, scripts/Ledger.gd, scripts/Main.gd, scripts/JobBoard.gd, scripts/PrintSim.gd, tests/smoke.gd first. Work only /Volumes/HARD/projects/printshop-sim. git pull --ff-only (main at b77805f). Model pinned glm-5.3-flash via zai coding plan (GLM_BASE_URL set by parent). Stop on quota/auth, no fallback. Never touch automated-newsletter or pitchforge/pitch-therapy.

Exclusive files: scripts/Main.gd, scripts/JobBoard.gd, tests/economy_test.gd, docs/worker-economy.md, generated UID files. Do NOT touch Contract.gd, Ledger.gd (frozen, tested), Grabbable.gd, TouchControls.gd, Printer.gd, PrintVisual.gd, PrintSim.gd internals (you may READ PrintSim; if an integration seam is missing, note it and work around it in Main), or any existing test except smoke.gd which you MAY update minimally to the new JobBoard interface (behavior-preserving intent, keep 9-ish checks covering stocked/start/complete/refill).

Implement now, not a plan.

1. JobBoard.gd: serve Contract objects from Contract.make_fixture_jobs() (+refill when drained, cycling deterministically). Replace the raw Dictionary API; expose has_available(), take_next() -> Contract, get_available_count(), and available_summaries() -> Array[Dictionary] ({id, model_name, payout_cents, difficulty, risk_flags}) for HUD display.

2. Main.gd economy flow:
- var ledger := Ledger.new() and var active_contract: Contract = null.
- Accept (E at printer with no active contract, hands empty): take_next(); active_contract = job; require contract transition OFFERED→ACCEPTED→PREPARING→PRINTING via Contract's legal_transitions (use its API; if no transition helper method exists beyond legal_transitions(), implement small private _advance(state) in Main that validates).
- Charge material_cost_cents at print start (ledger.charge; if it fails — insufficient funds — refuse to start, HUD explains "Not enough funds"; starting balance should be seeded with an opening credit of e.g. 2500 cents "opening funds" once in _ready so the loop is playable).
- When sim reaches DONE_OK: transition PRINTING→INSPECTION (auto for now — inspection/packing stations come later; immediately →PACKED→DELIVERED is WRONG: for this slice, DONE_OK parks at INSPECTION and a second E press at the printer "collects" the print: PACKED then DELIVERED, ledger.pay_once(id, payout_cents) credited, HUD shows balance; active_contract cleared).
- DONE_FAIL: transition to FAILED via legal path, no payout, active_contract cleared, HUD explains failure.
- HUD: add a "$X.XX" balance line (format cents properly) and an active-contract line (model, state, payout). Keep existing lines working.

3. Behavioral RED/GREEN tests (tests/economy_test.gd) on the REAL Main scene: opening balance 2500 shows in HUD; accept at printer sets active_contract ACCEPTED→PREPARING→PRINTING transitions all legal (probe via active_contract.state); material charge reflected in balance and transaction log; DONE_OK parks at INSPECTION; E collect delivers exactly-once payout (balance up by payout, pay_once idempotent on repeated E); DONE_FAIL yields FAILED state and zero payout; cannot accept second contract while one active; insufficient-funds path (drain ledger via test hook — you may expose a test-only method or use ledger directly) refuses print start. Reuse smoke-style sim driving (tick sim directly or via _physics_process). Bounded subprocess runs (timeout=60), scan SCRIPT ERROR/Parse Error. Real RED then GREEN.

Keep all other suites green: printer_visual 28, grab 26, touch 47, input_pause 21, room 9, contract 171, smoke (updated). No export/browser/git — parent owns. First inspection immediately, minimal prose, code early. Checkpoint docs/worker-economy.md before budget expiry.
