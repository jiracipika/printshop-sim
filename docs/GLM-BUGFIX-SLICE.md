# GLM slice — bug-fix batch (v0.61.x, parent-verified)

You are the implementation worker. Parent session plans and verifies; you
implement and run the test suite. Read `AGENTS.md` and `docs/HANDOFF.md`
(hazards catalog is BINDING) before touching anything.

Baseline: commit 1894b03, all suites green. Version stays 0.61.0 — the
parent bumps/exports/deploys.

## File ownership (non-overlapping, hard boundary)

- `scripts/Main.gd` — targeted fixes only, additive where possible
- `scripts/ShopFront.gd`, `scripts/CustomerActor.gd` — dedup item only
- NEW `scripts/MeshKit.gd` — shared mesh helpers (item 3)
- NEW `tests/bugfix_test.gd` — your suite
- NEW `docs/worker-bugfix.md` — your report
- NOTHING else. Never `.github/workflows`, Version.gd, SaveSystem.gd, or
  the pinning suites (packing_test, v018_test, v037_test, v034_test).

## The three bugs (root causes verified by parent — re-verify in code)

### 1. Packing-table stack visual wiped by unrelated deliveries

`packing_station.set_stack_count(0)` is called blind in several paths:

- `_settle_held_delivery` tail (search `packing_station.set_stack_count(0)`
  after `ledger.pay_once` — ~line 3960)
- walk-in patience-expiry teardown (~3192), walk-in accept/deliver paths
  (~3271, ~3876), machine-clear sites (~4227, ~4337)

Bug: a board multi-part order mid-completion shows `parts_packed` copies
stacked on the packing table (partial-pack path sets the count at ~3907).
Delivering/accepting/expiring an UNRELATED walk-in or single-part job
zeroes the stack visual while the multi-part order still has packed
copies — visual and bookkeeping disagree until the next partial pack.

Fix: add `func _refresh_stack_visual()` that recomputes the count from
live state — the max `parts_packed` over machines whose contract is a
multi-part board order in a mid-completion state (copies packed but not
all delivered; a contract being carried/packed counts). Replace the blind
`set_stack_count(0)` calls with either `set_stack_count(0)` (when the
path truly ends the only stacked order — e.g. final copy of THE multi-part
completes, machine sim reset) or `_refresh_stack_visual()` (when the
touched contract is unrelated to whatever is stacked). Think per call
site; document your decision for each in worker-bugfix.md.

Constraints: `packing_test` (58 checks) and `v018_test` (55) pin the
multi-part flow and must stay green UNMODIFIED — if your semantics break
them, your semantics are wrong, not the tests. `walkin_test` must stay
green unmodified. Add bugfix_test coverage: stack survives an unrelated
counter delivery mid-multi-part; stack resets when the multi-part itself
completes/fails.

### 2. Event prompts never age out

`_set_prompt(t)` writes `_prompt.text` and nothing ever clears it — every
event prompt ("Print FAILED…", "Part 2/3 packed…", refusals) persists on
screen indefinitely until replaced. There is no per-frame interaction
prompt (verified: `_physics_process` has none; `_update_hud` does not
touch `_prompt`).

Fix: timestamp event prompts and fade them out. Add `_prompt_t: float`;
in `_physics_process`, count down and clear `_prompt.text` (only the
prompt label, never the HUD lines) after ~6 s. `_set_prompt` resets the
timer. The boot capture prompt (`_boot_prompt`, set directly on
`_prompt.text` at ~299/615) must NOT age — keep direct writes
timer-exempt (or set the timer only inside `_set_prompt`).

Constraint: suites assert prompt text right after driving actions (fast);
a 6 s wall window is expected safe, but if any suite fails from aging,
re-check timing before suspecting the suite — and report which suite and
why. Coverage: prompt set → simulated 6+ s of `_physics_process` deltas →
text empty; fresh `_set_prompt` restarts the window.

### 3. Dedup `_offset_arrays`/`_box_mesh`

`ShopFront.gd` and `CustomerActor.gd` carry duplicated private mesh
helpers (identical logic, parent-confirmed). Move them to NEW
`scripts/MeshKit.gd` as `static func`s (class_name MeshKit is fine —
tests never name Main/MainMenu as compile-time classes, a leaf util class
is allowed; verify no parse-order hazard by running the ladder). Update
both call sites. Draw-call and mesh-node counts must be UNCHANGED
(v020_test budgets hold; do not add or remove visible nodes).

## Bounded free sweep (report-first)

While in the files, grep for obvious adjacent defects (typed-array literal
assignment, `Array[String].extend` misuse, un-awaited coroutines,
`get_node` in per-frame loops, timers never freed). FIX only trivially
safe ones inside your owned files; LIST everything else in
worker-bugfix.md as findings with file:line — do not expand scope.

## Definition of done

- [ ] `bash tools/ladder.sh` full green, sequential, no other godot
      running (hazards 1/9). New suite green 3 consecutive runs.
- [ ] `~/tools/venv/bin/python -m pytest tests/test_build_web.py -q` green
- [ ] sim_playtest + sim_lategame curves byte-identical to the 1894b03
      reference (these fixes are NOT allowed to touch bot-observable
      state: money, rep, stats, board, log counts — hazard 17)
- [ ] worker-bugfix.md: per-call-site stack decision table, prompt-aging
      notes, sweep findings, exact ladder output line
- [ ] No commits — parent integrates.
