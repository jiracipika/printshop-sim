# GLM 3.0 slice 4 — shop rank career (v0.61.0)

Model must be glm-5.3-flash via the zai coding plan; no fallback, no auth retry —
on routing failure stop and write the blocker into the worker doc. Work on main,
no commits/push/deploy before parent review. Slices 1-3 (counter, walk-ins,
atmosphere — v0.58.0-v0.60.0) are integrated. This slice DELIBERATELY shifts
payouts; the byte-identical rule is replaced by re-measure + floors.

Read FIRST: AGENTS.md, design/overhaul-3.0.md (shop rank spec + hazards),
docs/HANDOFF.md top sections, then source: scripts/Main.gd: _finalize_payout
(full chain — you append at the END), _achievements()/_check_milestone_toasts/
Stats panel builder (search "_top_client_lines" and the STATS block),
_update_chalkboard, announced_tier lifecycle (the announcement high-water
pattern to copy), _load_save/_build_save_payload, scripts/SaveSystem.gd
(validators + the tier_announced precedent), scripts/Events.gd
(tier_for_rep thresholds), tests/v052_test.gd + tests/v057_test.gd
(milestone-suite pattern), tests/sim_playtest.gd + tests/sim_lategame.gd
(what the bots assert — the floors).

Spec (binding, from design/overhaul-3.0.md):
- Five DERIVED levels (never persist the level itself — compute like the tier
  system): L1 "Sprout" (default), L2 "Staple" (lifetime delivered >= 15 AND
  reputation high-water >= 3.0), L3 "Known" (40 + 3.5), L4 "Fixture"
  (80 + 4.0), L5 "Institution" (150 + 4.5).
- High-water rep WITHOUT a new persisted rep mark: effective_hwm = max(
  reputation, Events tier threshold for the persisted announced_tier). Read
  Events.tier_for_rep/tier tables and announced_tier's semantics first and
  state in the worker doc exactly how you derived it; if it cannot be derived
  soundly, fall back to persisting one new key rep_high_water (float 0..5,
  absence-tolerant, updated on every rep change) and say so in the doc.
- Level-up announcement: once per level ever — persist announced_rank (int
  1..5, absence-tolerant, adopt-current-silently at boot like tier_announced):
  gold toast "Shop rank: <name>", one "rank" workshop-log entry, chalkboard
  header gains "RANK: <name>".
- Payout: +2% x (level - 1) appended at the very END of _finalize_payout,
  AFTER the shelf bonus, before the final int-cents return. Document the
  extended chain in a comment at the function.
- Three new milestones appended to _achievements(): "Counter regular"
  (walkins_served >= 10), "Face of the street" (rank >= 3), "Institution"
  (rank >= 5) — derived from existing/slice-2 persisted counters; hints,
  toasts, boot adoption and the Stats listing ride the existing machinery.
- Stats panel: one RANK block (current level name, next threshold, bonus %)
  after the BOARD TIER block, same style.
- Thresholds are lifetime-delivered + high-water on purpose (monotonic —
  remember the v0.57 design trap note about balance-held milestones).

New files you own: tests/rank_test.gd, docs/worker-rank.md. Allowed edits:
scripts/Main.gd (payout tail, rank helpers, chalkboard line, Stats block,
milestones, announcement + persistence plumbing), scripts/SaveSystem.gd
(announced_rank validator [+ rep_high_water only if the fallback]),
scripts/Version.gd (0.61.0). Nothing else; record-and-stop otherwise.

tests/rank_test.gd (checks-format, house discipline): level table boundaries
(14/15, 39/40, 79/80, 149/150 delivered; exact 3.0/3.5/4.0/4.5 high-water
counts as the higher level — mirror tier_for_rep's boundary rule), derivation
or fallback soundness, payout math through the documented chain (pin exact
cents at each level on a controlled contract: L1 base, L3 = base x 1.04
composed after every other factor), announcement once-per-level (re-crossing
silent, boot adopt, persistence round-trip + old-save absence), chalkboard
line, Stats block content, three milestones at their edges (9/10 served,
rank 2/3, rank 4/5), counter premium x1.10 composes with the rank bonus in
the right order (walk-in + rank pinned exactly). Target 26-34 checks.

Verification: new suite 3 consecutive green; bash tools/ladder.sh FULL
failed=0 — economy/day/payout-pinning suites MUST stay green unmodified (if
one pins a total that the rank bonus shifts, the shop in that suite sits at
L1 by construction — fresh shops are L1; if any suite still shifts, you
applied the bonus to a path it should not touch: investigate, do not retune
the suite); ~/tools/venv/bin/python -m pytest tests/test_build_web.py -q;
both harnesses sequential — curves WILL move (+2%/level); record the new
reference numbers in docs/worker-rank.md and assert the floors pass:
sim_playtest >= 8 deliveries / >= $500 / rep >= 2.0; sim_lategame >= 60
deliveries / >= $3000 / rep >= 2.0. Paste the new curves. Version.gd 0.61.0.
docs/worker-rank.md. Stop — parent session reviews, integrates, commits.
