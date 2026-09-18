# Web build pipeline (tools/build_web.py / tools/build_web.sh)

Status after review-fix pass. Owner: build-infrastructure worker.

## What the pipeline does

1. Compute source state: full HEAD SHA, truthful dirty status. `web/build/`,
   `.baseline_logs/`, `.vercel/` and `*.log` are excluded from dirtiness.
   `vercel.json` is SOURCE configuration and counts as dirty.
2. Temporarily stamp `scripts/Version.gd` with HEAD SHA (+`-dirty`). The
   original bytes are always restored in a `finally`, on success and failure.
3. Validate the output path, then clear stale generated output INSIDE the
   stamp context, immediately before the engine runs:
   `index.html`, `index.js`, `index.wasm`, `index.pck`, `build-info.json`.
   Deletion is constrained to those known names inside `web/build/` only —
   unknown files in that directory (e.g. a README) are never deleted.
   The output directory is created fresh, so a clean checkout works.
4. Run `godot --headless --export-release Web web/build/index.html` with a
   finite timeout (`ENGINE_TIMEOUT_SECONDS = 900`) and captured combined
   output. A non-zero exit code OR a `SCRIPT ERROR` / `Parse Error` marker in
   the output fails the build, even at exit code 0.
5. Validate all four required outputs exist and are nonempty.
6. Write `web/build/build-info.json` (full source SHA, truthful pre-stamp
   dirty status). Because it is cleared in step 3, a failed build leaves NO
   build-info.json — stale metadata can never claim a fresh build succeeded.

## Output path policy

`--output` is restricted to the documented default `web/build/index.html`.
Custom targets would require matching file basenames and build-info handling
to stay consistent; until that is implemented, any other path is rejected
with `unsupported --output` before the engine runs. This also guarantees the
deletion pass can never target source files or arbitrary user paths.

## Testing (no real export here)

`tests/test_build_web.py` covers all of the above with a fake engine
(21 tests, mocked `subprocess`). Real exports are run by the parent worker
via `tools/build_web.sh`; this task's fixes were verified WITHOUT a real
export (mobile worker edits source concurrently).

## NOT RUN

- Real Godot web export (intentionally deferred — see above).
- Vercel deployment.

## Checkpoint (review-fix pass)

Fixed in tools/build_web.py:
- build() now creates web/build/ on fresh checkout (clear_generated_outputs
  mkdir -p before the engine runs).
- Stale required outputs + build-info.json are deleted (names constrained to
  REQUIRED_OUTPUTS + build-info, inside web/build/ only) before export, so a
  failed or zero-output export can no longer be masked, and no stale
  build-info.json survives failure.
- default_engine_runner: finite timeout (900s), capture_output, text.
- Exit-0 exports containing "SCRIPT ERROR" or "Parse Error" fail the build.
- vercel.json removed from non-source exclusions; counts as dirty.
- Custom --output restricted to documented web/build/index.html; other paths
  rejected before the engine runs (never delete source/arbitrary targets).
- Version.gd restore already guaranteed by finally; regression-tested.

Tests: tests/test_build_web.py 21/21 OK (python3 -m unittest discover -s
tests -p 'test_*.py'), includes new regression classes: TestStaleOutputAnd-
Clearing (fresh dir success, stale-mask failures, build-info invalidation,
unknown files untouched), TestEngineFailureMarkers (rc0 + SCRIPT ERROR /
Parse Error), TestDefaultRunnerContract (capture + finite timeout),
TestOutputRestriction (custom/source targets rejected, documented accepted).
No real export run (mobile worker edits source); no git ops; no deployment.
