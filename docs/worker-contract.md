# Worker checkpoint — contract and money data (task 08)

Worker: GLM 5.3 Flash via Z.AI coding plan. Astra integrated and reviewed.

Files: scripts/Contract.gd, scripts/Ledger.gd (+ .uid), tests/contract_test.gd (+ .uid), docs/GLM-CONTRACT-SLICE.md, this file.

## What was built
- Contract: Resource with id/client/model/payout_cents/material_cost_cents/difficulty(1-5)/risk_flags(subset of overhangs|bed adhesion|stability)/layers/deadline_days; State enum OFFERED→ACCEPTED→PREPARING→PRINTING→INSPECTION→PACKED→DELIVERED plus FAILED; legal_transitions() table; make_fixture_jobs() deterministic 4-job fixture set.
- Ledger: integer-cents only; charge/credit with rejection-without-mutation; pay_once exactly-once per contract id and funds-gated; transactions with seq/reason/delta/balance_after; non-negative invariant asserted in mutators; snapshot()/restore() with defensive copies and validation.

## Verification
- tests/contract_test.gd: 171 checks ALL PASS (Astra-verified rerun). Covers full legal path, ALL from→to transition pairs probed, FAILED reachability, insufficient/negative rejections, exactly-once, reconciliation, snapshot round-trips, malformed snapshot rejection.
- Astra review fixes after worker handoff: pay_once was not funds-gated (worker flagged; fixed, funds-gated per test contract), one wrong identifier (_balance_cents → balance_cents) that broke compilation of depended scripts.
- Full regression ladder green: contract 171, printer_visual 28, grab 26, touch 47, input_pause 21, room 9, smoke 9.

## NOT RUN / deferred
- No gameplay integration (Main/PrintSim/JobBoard untouched by design) — wiring is the next slice.
- No export, browser, git, deploy — parent-owned.

Integration notes for the next slice: JobBoard.gd currently serves raw Dictionaries (id/model/layers) to Main._try_interact; replace with Contract objects and drive accept/prep/print/inspect/pack/deliver transitions from gameplay events, charging material_cost_cents at print start and pay_once(payout) at delivery. Ledger snapshot/restore is the save-system seam.
