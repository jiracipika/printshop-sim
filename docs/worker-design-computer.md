# Worker report — design computer prototype

## Result

Added a usable in-world design computer on the workbench. The player can open a beginner-friendly editor, select Desk planter / Cable ring / Storage block, adjust printable dimensions, wall thickness, layer height, infill, material, and filament color, and see a 3D preview with filament, time, and cost estimates. Test Print saves the blueprint, charges its material cost, starts a low-risk prototype on an available unlocked printer, and makes the completed model a physical grabbable that can be placed in the shop. Opening the editor pauses shop time; Escape and Back to shop return to the shop menu.

## Files changed

- `scripts/Main.gd`: computer prop and ray target, editor lifecycle/input, prototype print and collect path, HUD status.
- `scripts/DesignStudio.gd`: editor UI, blueprint validation/persistence, preview geometry, estimates.
- `tests/design_computer_test.gd`: designer rules and end-to-end prototype flow (20 checks).
- `docs/HANDOFF.md`: active state, verification evidence, next iteration.
- `docs/worker-design-computer.md`: this report.

## Verification run

- Godot `4.7.1.stable.official.a13da4feb` import: exit 0. Existing `export_presets.cfg` warning: `Couldn't find the given section "preset.1" and key "exclude_filter"`.
- All Godot scripts in `tests/*_test.gd tests/smoke.gd`: exit 0; 20 suites, 879 checks total, 0 failures, including the new 20-check integration suite.
- `python3 -m pytest tests/test_build_web.py -q`: exit 0; 21 passed.
- No browser capture or Web export was run. The interactive display/browser tooling and the matching export templates were not available in this workspace.

## Next

Iterate on print visuals so the live deposition follows the designed silhouette and shows subtle, fine extrusion lines. Then capture and inspect the in-game editor and printing states in an interactive browser before any release work.
