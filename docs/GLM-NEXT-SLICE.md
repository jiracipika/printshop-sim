# GLM next slice — workshop baseline

Astra authorizes implementation now; design-plan statements saying all work needs future authorization describe the earlier design-only task, not a current blocker. Use main, not a feature branch; no worker commits/push/deploy before parent review.

Read AGENTS.md, docs/HANDOFF.md, design/language.md and design/implementation-plan.md. Work only /Volumes/HARD/projects/printshop-sim. Never touch automated-newsletter or pitchforge/pitch-therapy. Model must be glm-5.3-flash via zai coding plan; no fallback or auth/quota retry.

First run read-only inventory: git status/remotes, engine version, actual source/test files. Preserve existing untracked work. No remote exists at last check; do not blindly pull an absent remote. Execute existing tests and bounded import/runtime checks to establish baseline (subprocess timeouts and SCRIPT ERROR/Parse Error scanning mandatory).

Scope: task 00 and minimum room/boot gate task 01 only. Allowed edits: scripts/Main.gd, scenes/Main.tscn, tests/ room or boot tests, docs/worker-workshop-baseline.md, and automatically generated UID files. If a failure requires any other production file, record it and stop for review. At most 300 source lines changed; do not rewrite architecture. Existing project is incomplete; discover before editing.

Required RED then GREEN: a behavioral boot/room smoke test asserting main scene initializes, floor/wall collision bodies and bench/printer exist, player spawn is above floor. Build missing minimum elements if absent, match sage/honey plywood/dark steel/terracotta visual spec. Preserve existing features. Run Godot headless import with quit and bounded runtime tests. Actual rendered inspection may remain pending: do not claim headless proves visuals or browser gameplay.

Write docs/worker-workshop-baseline.md containing initial baseline, exact changes, commands/results, outstanding blockers, next task and explicit NOT RUN browser/deployment status. Checkpoint before budget expires. No global config, credentials, git mutation, deployment, additional workers or unrelated edits. Do the first inspection immediately; minimal prose.
