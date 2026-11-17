#!/usr/bin/env python3
"""Headless test for LAYERS Godot 4 Cloud Function helpers (`functions/index.js`)."""

from __future__ import annotations

import os
import subprocess
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))

NODE_TEST = r"""
const assert = require("assert");
const path = require("path");
const { _testHelpers } = require(path.resolve(process.argv[1], "functions", "index.js"));

const {
  hashLinkToken,
  GODOT_UPDATE_VALID_ACTIONS,
  resolveDimensionMetaJs,
  sanitizeGodotLineJs,
  sanitizeGodotTuningKeyJs,
  normalizeGodotUnitJs,
  inferGodotPropertyTypeJs,
  sanitizeGodotLiveContextJs,
  parseRootSpecJs,
  parseEpicSpecJs,
  renderServerGodotEpicContextJs,
  computeActiveGodotEpicPayload,
  resolveTargetEpicDocIdJs,
  applyGodotEpicMutationJs,
  normalizeAgentBundle,
} = _testHelpers;

assert(GODOT_UPDATE_VALID_ACTIONS.has("build_epic"));
assert(GODOT_UPDATE_VALID_ACTIONS.has("fix_epic"));
assert(GODOT_UPDATE_VALID_ACTIONS.has("toggle_check"));
assert(GODOT_UPDATE_VALID_ACTIONS.has("pass_epic"));
assert(GODOT_UPDATE_VALID_ACTIONS.has("reopen_epic"));
assert.strictEqual(hashLinkToken("lyr_abc").length, 64);

assert.strictEqual(resolveDimensionMetaJs("dim2d").speedUnit, "px/s");
assert.strictEqual(resolveDimensionMetaJs("dim3d").speedUnit, "m/s");
assert.strictEqual(sanitizeGodotTuningKeyJs("bAllowAirDash"), "allow_air_dash");
assert.strictEqual(sanitizeGodotTuningKeyJs("MaxWalkSpeed"), "max_walk_speed");
assert.strictEqual(normalizeGodotUnitJs("move_speed", "cm/s", "dim3d"), "m/s");
assert.strictEqual(normalizeGodotUnitJs("move_speed", "cm/s", "dim2d"), "px/s");
assert.strictEqual(inferGodotPropertyTypeJs("3", "count"), "int");
assert.strictEqual(inferGodotPropertyTypeJs("true", ""), "bool");
assert.strictEqual(inferGodotPropertyTypeJs("6.4", "m/s"), "float");

const cleaned = sanitizeGodotLineJs("Attach BP_CrabPlayer and ACharacter with PIE check", "dim3d");
assert(!cleaned.includes("ACharacter") && cleaned.includes("CharacterBody3D"), cleaned);
assert(!cleaned.includes("PIE") && cleaned.includes("Playtest"), cleaned);

const docsById = new Map();
docsById.set("proj_1", {
  id: "proj_1",
  tier: "PROJECT",
  title: "Shellbreaker",
  childrenIds: ["rel_v01", "rel_v02"],
  sections: {
    active_release_id: "rel_v02",
    concept_blueprint_json: JSON.stringify({
      gameTitle: "Shellbreaker",
      dimension: "dim3d",
      pitch: "Arcade Claw Brawler — Top-down 3D crab arena.",
      coreLoop: ["Move", "Dash", "Break Armor"],
      pillars: ["Every dash commits"],
      tradeOffs: [{ prefer: "Snappy arcade", avoid: "Slow drift" }],
      outOfScope: ["No main menu"],
    }),
  },
});

docsById.set("rel_v01", {
  id: "rel_v01",
  tier: "RELEASE",
  parentId: "proj_1",
  title: "v0.1 · Prototype",
  sections: { release_version: "v0.1" },
  childrenIds: ["epic_1"],
});

docsById.set("epic_1", {
  id: "epic_1",
  tier: "EPIC",
  parentId: "rel_v01",
  title: "Mech Movement",
  isCompleted: true,
  sections: {
    code: "E01",
    release_version: "v0.1",
    lifecycle: "stable",
    epic_spec_json: JSON.stringify({
      code: "E01",
      title: "Mech Movement",
      goal: "Walk and claw dash cleanly in 3D.",
      links: ["res://scenes/arena_3d.tscn", "res://scripts/player.gd"],
      controls: [{ action: "claw_dash", trigger: "Just Pressed (Space)", rule: "Dash forward 5.5 m" }],
      tuning: [{ key: "move_speed", value: "6.4", unit: "m/s" }],
      levelStaging: "res://scenes/arena_3d.tscn",
      checks: [{ id: "chk_1", text: "Press Space -> Mech dashes 5.5 m", passed: true }],
    }),
  },
});

docsById.set("rel_v02", {
  id: "rel_v02",
  tier: "RELEASE",
  parentId: "proj_1",
  title: "v0.2 · Combat",
  sections: { release_version: "v0.2" },
  childrenIds: ["epic_2"],
});

docsById.set("epic_2", {
  id: "epic_2",
  tier: "EPIC",
  parentId: "rel_v02",
  title: "Mech Movement",
  isCompleted: false,
  sections: {
    code: "E01",
    lineage_key: "e01",
    release_version: "v0.2",
    lifecycle: "upgrading",
    epic_spec_json: JSON.stringify({
      code: "E01",
      lineageKey: "e01",
      releaseVersion: "v0.2",
      lifecycle: "upgrading",
      goal: "Walk and claw dash with v0.2 chain stun.",
      baselineSummary: ["v0.1 Walk + Dash verified"],
      upgradeDeltas: ["Chain second dash on armor break"],
      tuning: [{ key: "move_speed", value: "6.4", unit: "m/s" }],
      levelStaging: "res://scenes/arena_3d.tscn",
      checks: [
        { id: "chk_base", text: "Press Space -> Mech dashes 5.5 m", passed: true },
        { id: "chk_v02_delta_1", text: "Verify v0.2 delta: Break armor -> Chain dash unlocks", passed: false },
      ],
    }),
  },
});

const liveCtx = sanitizeGodotLiveContextJs({
  project_name: "Shellbreaker",
  main_scene: "res://scenes/arena_3d.tscn",
  input_actions: ["claw_dash", "move_left"],
  scene_files: ["res://scenes/arena_3d.tscn"],
  script_files: ["res://scripts/player.gd"],
});

const payload = computeActiveGodotEpicPayload({
  docsById,
  projectId: "proj_1",
  liveGodotContext: liveCtx,
});
assert.strictEqual(payload.ok, true);
assert.strictEqual(payload.dimension, "dim3d");
assert.strictEqual(payload.arenaScenePath, "res://scenes/arena_3d.tscn");
assert(payload.godotContextMarkdown.includes("# ROOT_GODOT_CONTEXT · Shellbreaker"));
assert(payload.godotContextMarkdown.includes("+Chain second dash on armor break"));

const logged = applyGodotEpicMutationJs({
  epicDoc: docsById.get("epic_2"),
  action: "log_fix",
  body: { fixText: "Dash hits wall twice" },
  dimension: "dim3d",
});
assert.strictEqual(logged.epicSpec.fixes.filter((f) => !f.resolved).length, 1);

const passed = applyGodotEpicMutationJs({
  epicDoc: { id: "epic_2", sections: logged.sections },
  action: "pass_epic",
  body: {},
  dimension: "dim3d",
});
assert.strictEqual(passed.isCompleted, true);

const reopened = applyGodotEpicMutationJs({
  epicDoc: { id: "epic_2", sections: passed.sections, isCompleted: true },
  action: "reopen_epic",
  body: {},
  dimension: "dim3d",
});
assert.strictEqual(reopened.isCompleted, false);
assert.strictEqual(reopened.epicSpec.checks[0].passed, true, "v0.1 baseline check preserved");
assert.strictEqual(reopened.epicSpec.checks[1].passed, false, "v0.2 delta check unchecked");

const bundle = normalizeAgentBundle({
  summary: "Built E01",
  scriptUpdates: [{ resPath: "scripts/player.gd", content: "+ extends CharacterBody3D\nfunc _ready(): pass" }],
  sceneOps: [{ op: "ensure_node", scenePath: "scenes/arena_3d.tscn", parentPath: ".", nodeName: "Player", nodeType: "CharacterBody3D" }],
  inputOps: [{ action: "claw_dash", keys: ["SPACE"], overwrite: true }],
}, "build_epic", { dimension: "dim3d" });
assert.strictEqual(bundle.scriptUpdates[0].resPath, "res://scripts/player.gd");
assert(bundle.scriptUpdates[0].content.startsWith("extends CharacterBody3D"));
assert.strictEqual(bundle.sceneOps[0].scenePath, "res://scenes/arena_3d.tscn");
assert.strictEqual(resolveTargetEpicDocIdJs({ docsById, projectId: "proj_1" }), "epic_2");

console.log("GODOT_CLOUD_TEST_OK");
"""


def main() -> int:
  proc = subprocess.run(
      ["node", "-e", NODE_TEST, ROOT],
      cwd=ROOT,
      capture_output=True,
      text=True,
  )
  if proc.stdout:
    print(proc.stdout.strip())
  if proc.stderr:
    print(proc.stderr.strip(), file=sys.stderr)
  return proc.returncode


if __name__ == "__main__":
  sys.exit(main())
