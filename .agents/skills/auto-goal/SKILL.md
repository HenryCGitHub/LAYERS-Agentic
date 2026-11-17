---
name: auto-goal
description: Bounded hands-off autonomous improvement sweep (default 3 rounds, or [N] rounds) for LAYERS-Agentic. Targets bugs, Stage 1/2/Godot 4 Dock parity gaps, and test coverage without inventing speculative UI.
---

# Auto-Goal (`/auto-goal [N] [focus]`) — Bounded Hands-Off Sweep

Run a bounded autonomous sweep (`default N = 3` loops when omitted, or `1..50` when specified e.g. `/auto-goal 5 godot`, `auto goal 2`) without interactive interruptions (`ask_question` is skipped). Stop automatically after Round `N/N` (or early on `stop` / `pause` / `"finish ... and pause"`).

## Phase 1 — Signal Discovery & Autonomous Selection (`discovering`)
1. Collect live repository signals from the workspace root:
   ```bash
   PYTHONDONTWRITEBYTECODE=1 python3 .agents/skills/auto-goal/scripts/discover_signals.py
   ```
   Pass any optional user focus phrase after the script (e.g. `... godot` or `... stage 2`).
2. Read `1–3` candidate files surfaced by `focusMatches`, `unrealLeakageHits`, `untestedModules`, `monolithHotspots`, `godotCloudTest`, or `todoMarkers`.
3. Select the **`#1` highest-confidence non-speculative target** ranked by `(Reliability Gain × Parity Impact) / Blast Radius`.
   - **Strictly In Bounds**: Bug fixes, Stage 1 → Stage 2 → Godot 4 Dock (`addons/layers`) / Cloud Functions parity, validation/guardrails, and missing unit/widget/headless tests.
   - **Never Speculative UI**: Never invent unrequested UI panels, cosmetic redesigns, or new workflow toggles during hands-off `/auto-goal`.
4. Output a single `[Round k/N Goal]` banner line + lock the 3-part Goal Contract:
   - **Goal**: One plain-English sentence naming what changes and why.
   - **In Scope**: Concise bulleted list of files, systems, and specs.
   - **Done When**: Concrete causal/test conditions.

## Phase 2 — Closed Verification Loop (`Red → Verify → Commit`)
1. Call `exit_plan_mode` with the concrete file + test plan.
2. Add or refine a failing unit/widget test (`test/`) or Godot/Cloud test script (`scripts/godot_plugin_test.gd` / `scripts/godot_cloud_test.py` / `scripts/workflow_hook_test.py`) first.
3. Implement the smallest clean fix, run `./scripts/verify_loop.sh` (`--fix-zip` if `godot_plugin/` changed) until exit `0`, and commit cleanly to `main` (without leaving `__pycache__` or `.pyc` files).

## Phase 3 — Bounded Next-Round Handoff & Completion Summary
1. Call `enter_plan_mode` with `reason` prefixed by `[round-complete]` and a concise 1-line summary of the shipped commit.
2. When `Round k < N` (and not paused), the hook advances automatically to `Round k+1/N` (`discovering`).
3. When `Round k == N` (or `"finish ... and pause"` was sent), the loop stops automatically and injects `[Auto-Goal Complete — N/N Rounds Shipped]` so you output a crisp numbered `1..N` shipped-rounds changelog and stop cleanly.
