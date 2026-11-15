---
name: auto-goal
description: Automated continuous Goal discovery and user-selected Goal loop for LAYERS-Agentic. Activate whenever the user types /auto-goal or explicitly launches the autonomous Auto-Goal loop.
---

# Auto-Goal (`/auto-goal`) — Continuous Goal-Picker Loop

Run this loop continuously from repo telemetry until canceled or explicitly stopped (`stop`, `pause`, `finish the last loop and pause`). On **every round**, present the user a concrete ranked Goal Choice menu before modifying code.

## Phase 1 — Signal Discovery & Ranking
1. Collect live repository signals from the workspace root:
   ```bash
   PYTHONDONTWRITEBYTECODE=1 python3 .agents/skills/auto-goal/scripts/discover_signals.py
   ```
   Pass any optional user focus phrase after the script (e.g. `... unreal` or `... stage 2`).
2. Read `1–3` candidate files surfaced by `focusMatches`, `godotLeakageHits`, `untestedModules`, `monolithHotspots`, `unrealSmoke`, or `todoMarkers`.
3. Rank the top `3–4` concrete improvements by `(User Impact × Reliability Gain) / Blast Radius`.

## Phase 2 — Interactive Goal Choice (`select_goal`)
1. Call `ask_question` with **1 Goal Choice question** presenting `3–4` concrete ranked goals (`(Recommended)` first, each stating in plain English what changes and its payoff).
2. **Never** call `exit_plan_mode` or edit code before the user picks a goal (`PreToolUse` blocks premature `exit_plan_mode`).
3. Once the user picks a goal, lock the 3-part Goal Contract directly (no extra UX-grill question step — use `/auto-gg` when you also want interactive UX grilling on the chosen goal):
   - **Goal**: One plain-English sentence naming what changes and why.
   - **In Scope**: Concise bulleted list of files, systems, and specs.
   - **Done When**: Concrete causal/test conditions.

## Phase 3 — Closed Verification Loop (`Red → Verify → Commit`)
1. Call `exit_plan_mode` with the concrete file + test plan.
2. Add or refine a failing unit/widget test (`test/`) or Python smoke probe (`scripts/unreal_plugin_smoke.py` / `scripts/workflow_hook_smoke.py`) first.
3. Implement the smallest clean fix, run `./scripts/verify_loop.sh` (`--fix-zip` if `unreal_plugin/` changed) until exit `0`, and commit cleanly to `main` (without leaving `__pycache__` or `.pyc` files).

## Phase 4 — Perpetual Next-Round Handoff
1. Call `enter_plan_mode` with `reason` prefixed by `[round-complete]` and a 2-line summary of the shipped commit so Round `N+1` automatically discovers and presents the next Goal Choice menu.
2. Pause cleanly whenever the user cancels `ask_question`, writes `stop` / `pause` / `done`, or asks `"finish ... and pause"` (completes the current round, then pauses without launching Round `N+1`).
