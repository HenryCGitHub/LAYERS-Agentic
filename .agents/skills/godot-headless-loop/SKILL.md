---
name: godot-headless-loop
description: Use when reproducing, debugging, or verifying Godot 4 plugin behavior, scene ops, GDScript diagnostics, or external Godot project issues via fast headless SceneTree probes.
---

# Headless Godot 4 Verification Loop

Run real Godot `4.7.2-stable` headlessly before editing or reporting a Godot fix so every change has a deterministic pass/fail signal.

## Loop Procedure

1. **Locate Godot**:
   - `/Users/henry/Godot/Editors/4.7.2-stable/Godot.app/Contents/MacOS/Godot` (or `$GODOT_BIN`).
2. **Write a Repro Probe First**:
   - Keep external user game files (`/Users/henry/Godot/Projects/<Project>/{project.godot,scenes,scripts}`) **strictly read-only**.
   - Place temporary repro scripts in `<appDataDir>/brain/<conversation-id>/scratch/repro_*.gd` (`extends SceneTree`) using an isolated temp project or read-only snapshot.
   - Always free instantiated nodes before calling `quit(0)` / `quit(1)` so exit leak checks stay clean.
3. **Iterate Until Exit 0**:
   - Run `"$GODOT_EXEC" --headless --path <project_dir> --script <probe.gd>`.
   - Fix `godot_plugin/addons/layers/*.gd` or `functions/index.js` until the probe exits `0`.
4. **Promote Permanent Checks**:
   - Add regression assertions to [scripts/godot_plugin_smoke.gd](../../scripts/godot_plugin_smoke.gd) and run `./scripts/verify_loop.sh --fix-zip`.
