# GLM 3.0 slice 2 — walk-in customers (v0.59.0)

Model must be glm-5.3-flash via the zai coding plan; no fallback, no auth retry —
on routing failure stop and write the blocker into the worker doc. Work on main,
no commits/push/deploy before parent review. Slice 1 (the counter, v0.58.0) is
already integrated — build on it.

Read FIRST: AGENTS.md, design/overhaul-3.0.md (binding spec: walk-in flow,
geometry, hazards, DoD), docs/HANDOFF.md (top two sections + the v0.41/v0.43
persistence precedents), then source: scripts/CounterStation.gd (slice 1),
scripts/Contract.gd (generate, State, parts fields), scripts/JobBoard.gd
(generation path — do NOT touch), scripts/Main.gd: _try_interact,
_try_pack_held (3552-3681) and _finalize_payout, _update_hud, _physics_process
(_tick_cleaning pattern), _on_day_changed, _load_save/_build_save_payload,
scripts/SaveSystem.gd (validator + restore patterns, media_a_deliveries
precedent), scripts/WindowLife.gd (set_motion deterministic-seam pattern),
scripts/Clock.gd + scripts/DayCycle.gd (day fraction source), tests/spool_test.gd
+ tests/v038_test.gd (E-press test discipline), tests/counter_test.gd.

BOT-SAFETY INVARIANT (the single most important rule): unless the player serves
a walk-in at the counter, walk-ins must be observationally inert — no money, no
rep, no log entries (arrival, leave or expiry NEVER log — v015/v035 pin log
counts), no board changes, no milestones. sim_playtest/sim_lategame never
approach the counter, so their curves must stay byte-identical to the slice-1
reference. If any harness number moves, you have broken this rule — find out
why before writing the worker doc.

New files you own: scripts/CounterService.gd, scripts/CustomerActor.gd,
tests/walkin_test.gd, docs/worker-walkin.md. Allowed edits: scripts/Main.gd
(additive wiring listed below), scripts/Contract.gd (ONE additive var
`var walk_in := false` plus nothing else), scripts/SaveSystem.gd (two new
absence-tolerant validators, media_a_deliveries pattern), scripts/Version.gd
(0.59.0). Nothing else; on any other need, record and stop.

CounterService.gd (RefCounted, pure logic — PrintSim style, no nodes):
- Arrivals: due(day, frac, waiting_now) -> int arrival index (0 or 1) or -1.
  Arrival i is due when frac crosses t_i = 0.25 + 0.22*i + 0.03*(hash(
  "walkin-t-%d-%d" % [day, i]) % 4), gated on hash("walkin-%d-%d" % [day, i])
  % 10 < 6, only for frac in [0.15, 0.80], skipped entirely while
  waiting_now. Max 2 arrival slots/day, max 1 waiting customer at a time.
- Patience: 0.55 of a shop day from ACCEPT; constants + deadline math as pure
  functions (patience_deadline_frac(day, frac) etc.).
- State dict: {day, index, client, contract, accepted, deadline_frac,
  machine_idx}. Teardown helpers that Main calls (no signals needed — keep it
  PollSim-tickable from _physics_process like the machines).
- Client names: reuse Contract's existing first-name pools via a deterministic
  draw hash("walkin-name-%d-%d" % [day, index]).

CustomerActor.gd (Node3D, no physics body, never collides): builds a low-poly
person standing at (-1.9, 0, 2.75) facing the room: capsule torso (palette
color drawn deterministically from hash("walkin-outfit-<day>-<i>")), sphere
head, subtle idle bob via _advance(t) ONLY — gated by set_motion(false)
(WindowLife pattern: calm_mode freezes the actor exactly where it stands).
add_child on arrival, queue_free on despawn — never pre-built, never visible at
boot (v020 budget audit counts boot meshes).

Main.gd wiring, additive and in this shape:
1. var _counter_service: CounterService, var _customer: CustomerActor (current
   waiting actor), build in _ready after the counter; day-frac source = the
   same clock DayCycle already drives (read DayCycle.gd — do not invent a
   second clock).
2. Tick in _physics_process beside _tick_cleaning: arrivals (only when
   not paused and the day-frac window is open), patience countdown, expiry
   teardown. Expiry: despawn actor; if a machine holds the walk-in contract,
   run the existing overnight-cancel teardown path (read _on_day_changed's
   cancel branch — reuse the same calls, do not duplicate); stats/lost_walkins
   += 1 (see 6); NO rep change, NO log entry.
3. _try_interact branches, in order:
   a. HELD walk-in part (its machine contract has walk_in) and _near_counter():
      deliver at the counter via the extracted settle path (see 4) — insert
      AFTER the finishing/shelf branches, BEFORE the packing-table branch.
   b. HELD walk-in part and near the packing table instead: prompt
      "<client> is waiting at the counter — hand it over there"; return
      (the packing table must never pay out a walk-in).
   c. Empty-handed at the counter, before the crate branch (slice-1 order):
      no walk-in → keep slice-1 bell behavior; walk-in waiting, not accepted →
      two-press arm (press 1 shows the slip: client, model, color, counter
      price ~base x1.1, patience seconds; press 2 within 8 s accepts; disarm on
      leaving radius or timeout — the shop-code import arm pattern); accepted →
      prompt names the machine and remaining patience. Accepting assigns the
      FIRST idle, unlocked, contract-free machine via the same machine-setup
      calls _accept_on uses (read it; walk-ins never enter JobBoard queues);
      no free machine → "No free printer for a counter order" and the slip
      stays armed.
4. Grading/payout extraction (the one careful refactor): extract the FINAL
   settle tail of _try_pack_held (grade snapshot -> finishing bump -> color
   cap -> payout chain -> machine teardown -> part despawn -> stats/delivered
   bookkeeping) into func _settle_held_delivery(m: Dictionary, late: bool,
   via_counter: bool) -> bool. _try_pack_held calls it with via_counter=false
   and must remain behavior-identical for board contracts — packing_test (58
   checks), v018_test (55), v034_station_test, v037_test, economy_test pin it;
   do not reorganize statements, move them. The counter path differs ONLY by:
   the counter premium and the stats/walkin bookkeeping. Multi-part partial
   packing stays inside _try_pack_held (walk-ins are single-part by
   construction).
5. _finalize_payout gains one trailing optional param `counter := false`;
   when true multiply by 1.10 immediately AFTER the event multiplier and
   BEFORE the late factor (chain becomes grade -> loyalty -> rep -> season ->
   event -> counter x1.10 -> late -> same-day tip -> shelf). All existing
   callers/tests pass by default — no call-site changes anywhere else.
   Round with the same int cents discipline the function already uses.
6. Persistence: two new keys mirroring the media_a_deliveries precedent
  exactly (read how it validates/restores): walkins_served and
   stats.lost_walkins (or the stats-dict pattern the repo actually uses for
   delivered/late — follow the code you find, not this brief's guess).
   Both absence-tolerant for old saves. Waiting walk-ins are NOT persisted;
   reload despawns (document in the worker doc).
7. HUD: when a walk-in waits, one status line in _update_hud:
   "Counter: <client> — <model> (<patience>s)" appended after the existing
   contract lines; nothing when nobody waits (bots render the HUD too — this
   line is the only new HUD text and only appears with a live walk-in; confirm
   sim_playtest never sees it by the bot-safety invariant: it does not assert
   HUD text).
8. On serve (counter delivery): walkins_served += 1, rep +0.2 through the
   existing delivery branch (media-day bonus composes), client memory
   (client_orders/client_last_grade) updates exactly like a board delivery,
   one log entry "counter" kind is ALLOWED here (player action; bots never
   serve — confirm by running both harnesses).

tests/walkin_test.gd (checks-format, house discipline: load()-only references,
paused/captured before E presses, explicit yaw/pitch after teleports, settle
frames, release-before-poll; typed arrays via .assign()): arrival gating
determinism (same day -> same schedule; different days differ; night window
refuses; second slot skipped while one waits), patience math, two-press arm/
disarm (leaving radius, timeout), accept assigns the first idle unlocked
machine and reserves it (second accept attempt while one walks-in pending on
the same machine is refused — one walk-in at a time globally), no-free-printer
refusal, pack-table refusal prompt for a held walk-in part, counter delivery
pays base x1.1 through the documented chain (pin exact cents on a controlled
contract), finishing bump + color cap still apply at the counter, rep/client
memory update, expiry cancels the machine contract with zero rep change and
zero log noise, stats/walkins persistence round-trip + old-save absence
tolerance, calm mode freezes the actor (set_motion(false) + _advance no-op),
no boot-time customer nodes (budget), counter branch does not steal crate buys.
Target 30-40 checks.

Verification: new suite 3 consecutive green runs; bash tools/ladder.sh FULL
(failed=0); ~/tools/venv/bin/python -m pytest tests/test_build_web.py -q; both
harnesses (sim_playtest then sim_lategame, sequential, never concurrent):
printed curves byte-identical to the slice-1 reference recorded in
docs/worker-counter.md — paste both numbers in your worker doc. Version.gd
0.59.0. docs/worker-walkin.md (baseline, exact changes incl. the extraction
diff shape, commands + results, harness curves, NOT-RUN list, blockers).
Stop — parent session reviews, integrates, commits.

Machine baseline (2026-10-30, this box, commit 1186ca3): full ladder 72/72 green incl. smoke; sim_playtest 17 deliveries / $1,749.64 day-8 (8/8 checks); sim_lategame 64 deliveries / $4,918.89 day-14 (16/16 checks). These two curves are the BYTE-IDENTICAL targets for slices 1-3 (slice 4 re-measures). GODOT is at $HOME/tools/godot; pytest is $HOME/tools/venv/bin/python -m pytest. Repo root: the directory containing this docs/ file.
