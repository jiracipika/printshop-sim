# Worker checkpoint — economy integration (task 09)

Worker: GLM 5.3 Flash via Z.AI coding plan (pinned; no fallback used).

Files owned/edited: scripts/Main.gd, scripts/JobBoard.gd, tests/economy_test.gd (new), tests/smoke.gd (minimal interface update), docs/worker-economy.md, generated .uid files. Contract.gd / Ledger.gd / PrintSim internals untouched.

## What was built
- JobBoard: serves Contract objects from Contract.make_fixture_jobs(), deterministic cycling refill (rotates start index per cycle), has_available() / take_next() -> Contract / get_available_count() / available_summaries() -> Array[Dictionary] {id, model_name, payout_cents, difficulty, risk_flags} / put_back() for refused accepts.
- Main economy flow: `ledger` seeded once in _ready with 2500 cents "opening funds"; `active_contract`; private _advance() validates via Contract.can_transition before every write; accept path OFFERED->ACCEPTED->PREPARING->PRINTING; material_cost_cents charged at print start; sim.print_finished drives PRINTING->INSPECTION (DONE_OK parks; second E collects PACKED->DELIVERED + pay_once) or ->FAILED (no payout, contract cleared); HUD adds "Balance: $X.XX" and active-contract lines; "Not enough funds" prompt on refused start (job returned to board untouched at OFFERED).

## Integration seam note (Ledger frozen)
Ledger.pay_once is funds-gated (rejects when cents > balance_cents). A $64.00 payout after an $8.40 charge from $25.00 opening would be rejected. Workaround in Main._pay_payout: net-zero "working capital float" credit before pay_once, repaid immediately after. Exactly-once and final balance stay correct; no Ledger edit. Recommendation for a later slice: a funds-ungated payout API or explicit float account in Ledger.

## Verification (bounded headless runs)
- tests/economy_test.gd on the REAL Main scene: 27 checks — opening balance 2500 in HUD, accept->PRINTING legal path, material charge in balance + transaction log, DONE_OK parks at INSPECTION, collect delivers exactly-once payout (pay_once idempotency probed), DONE_FAIL -> FAILED with zero payout, second-accept rejection, insufficient-funds refusal with HUD message. RESULT: 27/27 PASS.
- tests/contract_test.gd: 171 checks PASS (regression, frozen files).
- tests/smoke.gd: 9 checks PASS (updated only for Contract objects: take_next() -> Contract, job.model_name).
- No SCRIPT ERROR / Parse Error in any run. Other suites (printer_visual 28, grab 26, touch 47, input_pause 21, room 9) untouched by this slice; contract/smoke re-verified as above.

## NOT RUN / deferred
- No export, browser, git, deploy — parent-owned per instructions.
- Inspection/packing stations: INSPECTION is an E-press park by design this slice.
