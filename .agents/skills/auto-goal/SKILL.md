---
name: auto-goal
description: Automated continuous Goal discovery and execution loop for LAYERS-Agentic. Activate whenever the user types /auto-goal or explicitly launches the autonomous Auto-Goal loop.
---

# Auto-Goal (`/auto-goal`) — Continuous Autonomous Loop

Run this loop continuously from repo telemetry until canceled or explicitly stopped (`stop`, `pause`, `exit auto goal`).

## Phase 1 — Signal Discovery & Ranking
1. Collect live repository signals from the workspace root:
   ```bash
   PYTHONDONTWRITEBYTECODE=1 python3 .agents/skills/auto-goal/scripts/discover_signals.py
   ```
   Pass any optional user focus phrase after the script (e.g. `... unreal` or `... stage 2`).
2. Read `1–3` candidate files surfaced by `focusMatches`, `godotLeakageHits`, `untestedModules`, `monolithHotspots`, `unrealSmoke`, or `todoMarkers`.
3. Rank concrete improvements by `(User Impact × Reliability Gain) / Blast Radius`.

## Phase 2 — Auto-Lock #1 Goal Contract (Optional Auto-Grill Only on Real UX Fork)
1. Pick the single `#1` safest high-impact goal yourself — **never** ask the user to choose among backlog items in `/auto-goal` mode.
2. Lock the 3-part Goal Contract:
   - **Goal**: One plain-English sentence naming what changes and why.
   - **In Scope**: Concise bulleted list of files, systems, and specs.
   - **Done When**: Concrete causal/test conditions.
3. Only invoke `auto-grill` (`ask_question`) if implementing the `#1` goal introduces a genuine product, UX, or scope fork. Otherwise skip `ask_question` and move straight into execution.

## Phase 3 — Closed Verification Loop (`Red → Verify → Commit`)
1. If in Plan Mode, call `exit_plan_mode` with the concrete file + test plan.
2. Add or refine a failing unit/widget test (`test/`) or Python smoke probe (`scripts/unreal_plugin_smoke.py` / `scripts/workflow_hook_smoke.py`) first.
3. Implement the smallest clean fix, run `./scripts/verify_loop.sh` (`--fix-zip` if `unreal_plugin/` changed) until exit `0`, and commit cleanly to `main` (without leaving `__pycache__` or `.pyc` files).

## Phase 4 — Perpetual Next-Round Handoff
1. Immediately call `enter_plan_mode` with `reason` prefixed by `[round-complete]` and a 2-line summary of the shipped commit so Round `N+1` automatically discovers and starts the next goal.
2. Stop immediately whenever the user cancels an optional `ask_question` or writes `stop`, `pause`, `done`, or `stop auto goal`.
