# Worker: external QA pass (2026-10-27)

Independent verification of the v0.57.0 tree on a fresh machine
(Ubuntu, Godot 4.7.stable.official.5b4e0cb0, no prior user:// state).
No code changes were needed; nothing was modified.

## Gates run (all green)

- `godot --headless --path . --import --quit` → exit 0 (one benign adb
  daemon notice; no import errors).
- Full serial ladder, 62 suites (all `tests/*_test.gd` + `smoke.gd`),
  mechanical gate rc!=0 OR "SCRIPT ERROR" OR 150s hang = fail:
  **0 red**. Per-suite logs kept at /tmp/psim_ladder/*.log (ephemeral).
- `smoke.gd` → 9 checks — ALL PASS (exit-time ObjectDB leak warnings are
  the usual SceneTree-script noise, present on every run).
- `sim_playtest.gd` → checks=8 failures=0; day-8 $1,665.79 · delivered 15
  — byte-identical to the HANDOFF's recorded replay curve. Run ALONE,
  then `sim_lategame.gd` → checks=16 failures=0; day-15 $6,026.39 ·
  delivered 74 — also byte-identical. No concurrency, per the documented
  BrowserSave race rule.
- Python: `python -m unittest discover -s tests` → 21 tests OK.
  `design/verify_pack.py` → exit 0 (reports no local chrome/chromium —
  expected on a headless box; not a failure).

## Fresh-eyes review

- `Main.gd` milestones V (Ten K / Scrap heap / Better late than never /
  Hard knocks): thresholds match hints; lifetime-earned rationale holds;
  scrapped-and-cancelled double-count is documented intent.
- `BrowserSave.gd`: atomic tmp+rename write, validated never-throw reads,
  slot hygiene on pre-boot clear — no defects found.
- No new save keys, no version drift: `web/build/build-info.json` still
  stamped 0.57.0/0435ee6.

## Blockers / notes

- Web export not re-run here: no Godot export templates on this machine
  (~1 GB download; the committed `web/build` is already stamped clean for
  0435ee6). Re-run `tools/build_web.sh` before the next deploy.
- The documented Vercel alias-stuck recurrence remains an ops concern,
  not a code bug.
