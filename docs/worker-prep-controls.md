# Preparation controls and gamepad input

2026-11-17. Current-session implementation authorized by explicit user model
override; GPT-6.1 Terra independently reviewed the changes and ran both new
input suites: interaction_dispatch 30/30 and prep_controls 28/28, no script
errors or failed checks. The existing exit-time resource warning also occurs
in the unchanged economy suite; it is not counted as a release acceptance.

Behavior: E/A/Interact first previews the current orientation (upright on
accept) and then confirms. R/X/Rotate selects the next orientation without
charging, consuming stock or starting. Invalid confirmation retains selection.
Touch Rotate appears only at an eligible preparing printer, avoids the other
buttons, and never owns movement/look fingers. HUD instructions follow the
input route. The economy fixture explicitly rotates to preserve its original
tilted-risk/material expectations.

Movement, interactions and rotation now share the active-input gate, including
connected gamepad play without mouse capture. Pause remains authoritative.
The fixture in tests/fixtures/gamepad_main.gd substitutes device discovery only;
it does not establish physical controller/browser behavior. It is dynamically
loaded after root.ready because statically extending Main before autoloads
register causes the UI's Version reference to fail compilation.

Source work was kept in two conceptual repairs (selection/confirmation and
shared gamepad gating) with a separate small platform fixture to preserve
real callback coverage. Tests exceed the original approximate line budget
slightly to cover hidden-button, resource-refusal and gamepad-pause cases.

Parent focused suites economy, interaction_dispatch, prep_controls, v027,
touch_controls passed on Godot 4.6.3. Full integration evidence will be recorded
in HANDOFF. Pinned 4.7.1 engine/templates, export, and real browser/device
acceptance are unavailable here; no new deployment is claimed.
