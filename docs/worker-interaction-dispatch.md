# Interaction repair — implementation checkpoint

2026-11-17. User explicitly authorized the current coding model to override
the old GLM routing rule, and requested GPT-6.1 Terra/GPT-6 Luna evaluation only.
GPT-6.1 Terra reviewed this patch and found no blocking issue.

Changes: route held E/A/touch actions through the existing station dispatch;
retain empty-handed ray-grab priority; block inactive input; remove global
dropped-part preemption; align walk-in, showcase and finishing carry prompts.

New public-input regression suite: `tests/interaction_dispatch_test.gd`,
30 checks passed on installed Godot 4.6.3. Existing grab, input_pause,
parallel, spool, v037, and walkin suites also passed. An initial ordinary-floor
placement fixture overlapped occupied geometry; its position was corrected.
No production behavior was relaxed to make that fixture pass.

The documented release engine is 4.7.1; this machine has 4.6.3. Full ladder,
bot comparison and export/browser acceptance remain for integration. The
available live browser previously reported missing WebGL2. No deployment
or current-release acceptance is claimed. Next bounded slice: preparation
selection separate from confirmation (R / gamepad X / touch Rotate).
