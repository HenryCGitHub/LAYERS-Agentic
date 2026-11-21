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
  parseFeatureSpecJs,
  computeFeaturePassedJs,
  isFeatureLockedBaselineJs,
  renderServerGodotEpicContextJs,
  renderServerGodotFeatureContextJs,
  computeActiveGodotEpicPayload,
  resolveTargetEpicDocIdJs,
  applyGodotEpicMutationJs,
  buildGodotSyncProjectSectionsJs,
  normalizeAgentBundle,
  buildGodotAgentPrompts,
  GODOT_READONLY_TOOL_NAMES,
  sanitizeToolHistoryJs,
  buildGodotMultiTurnPrompt,
  normalizeAgentStepResponse,
} = _testHelpers;

assert(GODOT_UPDATE_VALID_ACTIONS.has("build_epic"));
assert(GODOT_UPDATE_VALID_ACTIONS.has("fix_epic"));
assert(GODOT_UPDATE_VALID_ACTIONS.has("build_feature"));
assert(GODOT_UPDATE_VALID_ACTIONS.has("fix_feature"));
assert(GODOT_UPDATE_VALID_ACTIONS.has("toggle_check"));
assert(GODOT_UPDATE_VALID_ACTIONS.has("pass_epic"));
assert(GODOT_UPDATE_VALID_ACTIONS.has("reopen_epic"));
assert(GODOT_UPDATE_VALID_ACTIONS.has("pass_feature"));
assert(GODOT_UPDATE_VALID_ACTIONS.has("reopen_feature"));
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

const cleanedUnits3d = sanitizeGodotLineJs("Dash 1850 cm/s across 550 cm arena", "dim3d");
assert(cleanedUnits3d.includes("18.5 m/s") && cleanedUnits3d.includes("5.5 m"), cleanedUnits3d);
const cleanedUnits2d = sanitizeGodotLineJs("Move 320 cm/s in 64 cm hall", "dim2d");
assert(cleanedUnits2d.includes("320 px/s") && cleanedUnits2d.includes("64 px"), cleanedUnits2d);

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
  scriptUpdates: [{ resPath: "scripts/player.gd", content: "+ extends CharacterBody3D\n+func _ready(): pass" }],
  sceneOps: [{ op: "ensure_node", scenePath: "scenes/arena_3d.tscn", parentPath: ".", nodeName: "Player", nodeType: "CharacterBody3D" }],
  inputOps: [{ action: "claw_dash", keys: ["SPACE"], overwrite: true }],
}, "build_epic", { dimension: "dim3d" });
assert.strictEqual(bundle.scriptUpdates[0].resPath, "res://scripts/player.gd");
assert(bundle.scriptUpdates[0].content.startsWith("extends CharacterBody3D"));
assert(bundle.scriptUpdates[0].content.includes("func _ready(): pass"), bundle.scriptUpdates[0].content);
assert.strictEqual(bundle.arenaScenePath, "res://scenes/arena_3d.tscn");
assert.strictEqual(bundle.sceneOps[0].scenePath, "res://scenes/arena_3d.tscn");
assert.strictEqual(resolveTargetEpicDocIdJs({ docsById, projectId: "proj_1" }), "epic_2");

const customFixMut = applyGodotEpicMutationJs({
  epicDoc: docsById.get("epic_1"),
  action: "log_fix",
  body: { fixId: "fix_custom_1", fixText: "[FIX] Move ACharacter 400 cm/s in PIE" },
  dimension: "dim2d",
});
const customFix = customFixMut.epicSpec.fixes.find((f) => f.id === "fix_custom_1");
assert(customFix, "Expected custom fixId preserved");
assert.strictEqual(customFix.text, "Move CharacterBody2D 400 px/s in Playtest");

const blank2dDocs = new Map();
blank2dDocs.set("proj_2d", {
  id: "proj_2d",
  tier: "PROJECT",
  title: "Emberkeep",
  childrenIds: ["rel_2d"],
  sections: {
    concept_blueprint_json: JSON.stringify({
      gameTitle: "Emberkeep",
      dimension: "dim2d",
      pitch: "Torch Survival — 2D pixel dungeon.",
      coreLoop: ["Move", "Dodge"],
    }),
  },
});
blank2dDocs.set("rel_2d", {
  id: "rel_2d",
  tier: "RELEASE",
  parentId: "proj_2d",
  title: "v0.1",
  sections: { release_version: "v0.1" },
  childrenIds: ["ep_2d"],
});
blank2dDocs.set("ep_2d", {
  id: "ep_2d",
  tier: "EPIC",
  parentId: "rel_2d",
  title: "Runner Movement",
  isCompleted: false,
  sections: {
    code: "E01",
    epic_spec_json: JSON.stringify({ code: "E01", title: "Runner Movement", goal: "Move in 2D." }),
  },
});
const payload2dBlank = computeActiveGodotEpicPayload({
  docsById: blank2dDocs,
  projectId: "proj_2d",
});
assert.strictEqual(payload2dBlank.arenaScenePath, "res://scenes/arena_2d.tscn");

// 4-tier Project -> Release -> Epic -> Feature payload & 2-way Feature mutations
const docs4t = new Map();
docs4t.set("proj_4t", {
  id: "proj_4t",
  tier: "PROJECT",
  title: "Shellbreaker 4T",
  childrenIds: ["rel_4t_v01", "rel_4t_v02"],
  sections: {
    active_release_id: "rel_4t_v02",
    concept_blueprint_json: JSON.stringify({
      gameTitle: "Shellbreaker 4T",
      dimension: "dim3d",
      pitch: "Arcade Claw Brawler — Top-down 3D crab arena.",
      coreLoop: ["Move", "Dash", "Break Armor"],
      pillars: ["Every dash commits"],
      tradeOffs: [{ prefer: "Snappy arcade", avoid: "Slow drift" }],
      outOfScope: ["No main menu"],
    }),
  },
});
docs4t.set("rel_4t_v01", {
  id: "rel_4t_v01",
  tier: "RELEASE",
  parentId: "proj_4t",
  title: "v0.1 · Prototype",
  sections: { release_version: "v0.1" },
  childrenIds: [],
});
docs4t.set("rel_4t_v02", {
  id: "rel_4t_v02",
  tier: "RELEASE",
  parentId: "proj_4t",
  title: "v0.2 · Chain Dash",
  sections: { release_version: "v0.2" },
  childrenIds: ["ep_4t_e01"],
});
docs4t.set("ep_4t_e01", {
  id: "ep_4t_e01",
  tier: "EPIC",
  parentId: "rel_4t_v02",
  title: "Player Movement",
  isCompleted: false,
  sections: {
    code: "E01",
    lineage_key: "e01",
    release_version: "v0.2",
    lifecycle: "upgrading",
    epic_spec_json: JSON.stringify({
      code: "E01",
      lineageKey: "e01",
      title: "Player Movement",
      releaseVersion: "v0.2",
      lifecycle: "upgrading",
      goal: "Own locomotion, dash commitments, and follow camera rig.",
      sceneOwnership: [
        { path: "res://scenes/player_mech.tscn", role: "Player rig" },
        { path: "res://scenes/arena_proto.tscn", role: "Arena room" },
      ],
      stateFlow: ["Idle", "Walk", "ClawDash"],
      interruptRules: ["ClawDash locks walk for 0.18 s"],
      outOfScope: ["No wall jump"],
      features: [
        {
          id: "f01",
          code: "F01",
          title: "8-Way Walk",
          introducedIn: "v0.1",
          status: "passed",
          releaseDelta: "",
          goal: "Smooth 8-way arena walk.",
          controls: [{ action: "move_left", trigger: "Hold A", rule: "Strafe left" }],
          tuning: [{ key: "move_speed", value: "6.4", unit: "m/s" }],
          checks: [{ id: "f01_c1", text: "Hold A -> Moves left", passed: true }],
        },
        {
          id: "f02",
          code: "F02",
          title: "Armored Claw Dash",
          introducedIn: "v0.1",
          status: "active",
          releaseDelta: "+ Refund dash on armor break",
          goal: "Forward 4 m claw dash.",
          controls: [{ action: "claw_dash", trigger: "Space", rule: "Dash 4 m" }],
          tuning: [{ key: "dash_distance", value: "4.0", unit: "m" }],
          checks: [{ id: "f02_c1", text: "Tap Space -> Dashes 4 m", passed: true }],
          releaseDeltaChecks: [{ id: "f02_dc1", text: "Break armor -> Dash resets", passed: false }],
        },
        {
          id: "f03",
          code: "F03",
          title: "Chain Dash Refund",
          introducedIn: "v0.2",
          status: "queued",
          goal: "Chain second dash inside 0.35 s window.",
          tuning: [{ key: "chain_window", value: "0.35", unit: "s" }],
          checks: [{ id: "f03_c1", text: "Chain dash triggers in 0.35 s", passed: false }],
        },
      ],
    }),
  },
});

const payload4t = computeActiveGodotEpicPayload({
  docsById: docs4t,
  projectId: "proj_4t",
  liveGodotContext: liveCtx,
});
assert.strictEqual(payload4t.ok, true);
assert(payload4t.activeFeature, "Expected activeFeature resolved");
assert.strictEqual(payload4t.activeFeature.id, "f02");
assert.strictEqual(payload4t.arenaScenePath, "res://scenes/arena_proto.tscn");
assert.strictEqual(payload4t.activeEpicFeatures.length, 3);
assert.strictEqual(payload4t.activeEpicFeatures[0].isLockedBaseline, true);
assert.strictEqual(payload4t.activeEpicFeatures[1].isLockedBaseline, false);
assert.strictEqual(payload4t.activeEpicFeatures[2].introducedIn, "v0.2");
assert.strictEqual(payload4t.siblingFeaturesSummary.length, 2);
const f01Sib = payload4t.siblingFeaturesSummary.find((s) => s.id === "f01");
assert(f01Sib, "Expected f01 in siblingFeaturesSummary");
assert(f01Sib.tuningKeys.includes("move_speed"));
assert(f01Sib.inputActions.includes("move_left"));
assert(!payload4t.siblingFeaturesSummary.some((s) => s.id === "f02"));
assert(payload4t.activeFeatureContextMarkdown.includes("# ACTIVE FEATURE SPEC · F02"));
assert(payload4t.activeFeatureContextMarkdown.includes("Parent Epic Architecture"));
assert(payload4t.activeFeatureContextMarkdown.includes("res://scenes/player_mech.tscn"));
assert(payload4t.activeFeatureContextMarkdown.includes("Preserve Passing Sibling Features"));
assert(payload4t.activeFeatureContextMarkdown.includes("move_speed"));

const payload4tPrefF03 = computeActiveGodotEpicPayload({
  docsById: docs4t,
  projectId: "proj_4t",
  preferredFeatureId: "f03",
});
assert.strictEqual(payload4tPrefF03.activeFeature.id, "f03");

// Locked [v0.1] baseline guard on f01 in v0.2
for (const [act, bodyArg] of [
  ["update_tuning", { featureId: "f01", key: "move_speed", value: "12.0" }],
  ["toggle_check", { featureId: "f01", checkId: "f01_c1", passed: false }],
  ["log_fix", { featureId: "f01", fixText: "Should block on locked baseline" }],
  ["reopen_feature", { featureId: "f01" }],
]) {
  assert.throws(
    () =>
      applyGodotEpicMutationJs({
        epicDoc: docs4t.get("ep_4t_e01"),
        action: act,
        body: bodyArg,
        dimension: "dim3d",
      }),
    (err) => err && err.statusCode === 409,
    `Expected 409 on locked baseline action ${act}`
  );
}

// 2-way Feature mutations on f02 & f03
const tunedF02 = applyGodotEpicMutationJs({
  epicDoc: docs4t.get("ep_4t_e01"),
  action: "update_tuning",
  body: { featureId: "f02", key: "dash_distance", value: "5.5", unit: "m" },
  dimension: "dim3d",
});
assert.strictEqual(tunedF02.epicSpec.features[1].tuning[0].value, "5.5");
assert.strictEqual(tunedF02.epicSpec.features[0].tuning[0].value, "6.4");

const loggedF02 = applyGodotEpicMutationJs({
  epicDoc: { id: "ep_4t_e01", sections: tunedF02.sections },
  action: "log_fix",
  body: { featureId: "f02", fixId: "fx_4t_1", fixText: "Dash clips pillar corner" },
  dimension: "dim3d",
});
assert.strictEqual(loggedF02.epicSpec.features[1].fixes.filter((f) => !f.resolved).length, 1);

const resolvedF02 = applyGodotEpicMutationJs({
  epicDoc: { id: "ep_4t_e01", sections: loggedF02.sections },
  action: "resolve_fix",
  body: { featureId: "f02", fixId: "fx_4t_1", resolved: true },
  dimension: "dim3d",
});
assert.strictEqual(resolvedF02.epicSpec.features[1].fixes.filter((f) => !f.resolved).length, 0);

const checkedF02 = applyGodotEpicMutationJs({
  epicDoc: { id: "ep_4t_e01", sections: resolvedF02.sections },
  action: "toggle_check",
  body: { featureId: "f02", checkId: "f02_dc1", passed: true },
  dimension: "dim3d",
});
assert.strictEqual(checkedF02.epicSpec.features[1].releaseDeltaChecks[0].passed, true);

const passedF02 = applyGodotEpicMutationJs({
  epicDoc: { id: "ep_4t_e01", sections: checkedF02.sections },
  action: "pass_feature",
  body: { featureId: "f02" },
  dimension: "dim3d",
});
assert.strictEqual(passedF02.epicSpec.features[1].status, "passed");
assert.strictEqual(passedF02.isCompleted, false, "Epic stays incomplete while f03 is queued");

const passedF03 = applyGodotEpicMutationJs({
  epicDoc: { id: "ep_4t_e01", sections: passedF02.sections },
  action: "pass_feature",
  body: { featureId: "f03" },
  dimension: "dim3d",
});
assert.strictEqual(passedF03.epicSpec.features[2].status, "passed");
assert.strictEqual(passedF03.isCompleted, true, "All features passed rolls Epic up to completed");
assert.strictEqual(passedF03.epicSpec.lifecycle, "stable");

const reopenedF02 = applyGodotEpicMutationJs({
  epicDoc: { id: "ep_4t_e01", sections: passedF03.sections, isCompleted: true },
  action: "reopen_feature",
  body: { featureId: "f02" },
  dimension: "dim3d",
});
assert.strictEqual(reopenedF02.epicSpec.features[1].status, "active");
assert.strictEqual(reopenedF02.epicSpec.features[1].checks[0].passed, true);
assert.strictEqual(reopenedF02.epicSpec.features[1].releaseDeltaChecks[0].passed, false);
assert.strictEqual(reopenedF02.isCompleted, false);
assert.strictEqual(reopenedF02.epicSpec.lifecycle, "upgrading");

// Targeted .gd patches, exact tab preservation & additive inputOps protection
const patchedBundle = normalizeAgentBundle({
  summary: "Added Armored Claw Dash",
  scriptUpdates: [
    {
      resPath: "scripts/player.gd",
      patches: [
        {
          find: "\tmove_and_slide()",
          replace: "\tif Input.is_action_just_pressed('claw_dash'):\n\t\t_start_dash()\n\tmove_and_slide()",
        },
      ],
    },
    {
      resPath: "res://scripts/hud.gd",
      patches: [{ search: "var a := 1", replacement: "var a: int = 2" }],
    },
    {
      resPath: "scripts/dash_trail.gd",
      content: "extends Node3D\n@export var fade_s: float = 0.22\n",
    },
  ],
  inputOps: [
    { action: "claw_dash", keys: ["SPACE"], overwrite: true },
    { action: "move_left", remove: true },
  ],
}, "build_feature", {
  dimension: "dim3d",
  featureId: "f02",
  featureCode: "F02",
  preserveExports: ["move_speed"],
  preserveInputActions: ["move_left"],
});
assert.strictEqual(patchedBundle.mode, "build_feature");
assert.strictEqual(patchedBundle.featureId, "f02");
assert.strictEqual(patchedBundle.featureCode, "F02");
assert.deepStrictEqual(patchedBundle.preserveExports, ["move_speed"]);
assert.strictEqual(patchedBundle.scriptUpdates.length, 3);
assert.strictEqual(patchedBundle.scriptUpdates[0].resPath, "res://scripts/player.gd");
assert.strictEqual(patchedBundle.scriptUpdates[0].patches.length, 1);
assert.strictEqual(patchedBundle.scriptUpdates[0].patches[0].find, "\tmove_and_slide()");
assert.strictEqual(patchedBundle.scriptUpdates[0].content, "");
assert.strictEqual(patchedBundle.scriptUpdates[1].patches[0].find, "var a := 1");
assert.strictEqual(patchedBundle.scriptUpdates[1].patches[0].replace, "var a: int = 2");
assert.strictEqual(patchedBundle.inputOps.length, 1);
assert.strictEqual(patchedBundle.inputOps[0].action, "claw_dash");

// fix_feature still blocks removing protected sibling InputMap actions while allowing stale cleanup
const fixBundle = normalizeAgentBundle({
  summary: "Fixed stale action",
  inputOps: [
    { action: "move_left", remove: true },
    { action: "stale_bad_action", remove: true },
  ],
}, "fix_feature", {
  dimension: "dim3d",
  featureId: "f02",
  featureCode: "F02",
  preserveInputActions: ["move_left"],
});
assert.strictEqual(fixBundle.inputOps.length, 1);
assert.strictEqual(fixBundle.inputOps[0].action, "stale_bad_action");
assert.strictEqual(fixBundle.inputOps[0].remove, true);

// buildGodotAgentPrompts builds 4-tier compact prompt & thinkingLevel
const buildPromptRes = buildGodotAgentPrompts({
  mode: "build_feature",
  rootSpec: payload4t.rootSpec,
  epicSpec: payload4t.activeEpic,
  featureSpec: payload4t.activeFeature,
  siblingFeaturesSummary: payload4t.siblingFeaturesSummary,
  godotContextMarkdown: payload4t.activeFeatureContextMarkdown,
  liveScripts: {
    "res://scripts/player.gd": "extends CharacterBody3D\n@export var move_speed: float = 6.4\n",
  },
  arenaScenePath: payload4t.arenaScenePath,
  epicScenePath: "res://scenes/player_mech.tscn",
});
assert.strictEqual(buildPromptRes.thinkingLevel, "LOW");
assert(buildPromptRes.systemInstruction.includes("patches"), buildPromptRes.systemInstruction);
assert(buildPromptRes.systemInstruction.includes("find") && buildPromptRes.systemInstruction.includes("replace"));
assert(buildPromptRes.systemInstruction.includes("passedSiblings") || buildPromptRes.systemInstruction.includes("sibling"));
assert(buildPromptRes.preserveExports.includes("move_speed"));
assert(!buildPromptRes.preserveExports.includes("chain_window"));
assert(buildPromptRes.preserveInputActions.includes("move_left"));
assert(buildPromptRes.userPrompt.includes("F02"));
assert(buildPromptRes.userPrompt.includes("Armored Claw Dash"));
assert(buildPromptRes.userPrompt.includes("move_speed"));
const parsedContextInPrompt = JSON.parse(
  buildPromptRes.userPrompt.split("PROJECT & FEATURE CONTEXT JSON:\n\n")[1]
);
assert(parsedContextInPrompt.epicArchitecture, "Expected compact epicArchitecture object");
assert(!("features" in parsedContextInPrompt.epicArchitecture), "Should not duplicate features array");

const fixPromptRes = buildGodotAgentPrompts({
  mode: "fix_feature",
  rootSpec: payload4t.rootSpec,
  epicSpec: payload4t.activeEpic,
  featureSpec: payload4t.activeFeature,
  siblingFeaturesSummary: payload4t.siblingFeaturesSummary,
  godotContextMarkdown: payload4t.activeFeatureContextMarkdown,
  errorText: "SCRIPT ERROR: Nil base",
});
assert.strictEqual(fixPromptRes.thinkingLevel, "MEDIUM");

// Multi-turn v1 Cloud tool-calling protocol helpers (Round 2/5)
assert(GODOT_READONLY_TOOL_NAMES instanceof Set);
assert.strictEqual(GODOT_READONLY_TOOL_NAMES.size, 6);
for (const toolName of [
  "list_project_files",
  "grep_project_text",
  "read_script_slice",
  "inspect_scene_tree",
  "read_autoloads_and_layers",
  "inspect_tres_resource",
]) {
  assert(GODOT_READONLY_TOOL_NAMES.has(toolName), `Missing read-only tool ${toolName}`);
}
assert(!GODOT_READONLY_TOOL_NAMES.has("delete_file"));

const sanitizedHistory = sanitizeToolHistoryJs([
  { turn: 1, tool: "delete_file", args: { path: "res://scripts/player.gd" }, result: { ok: true } },
  {
    turn: 1,
    tool: "read_script_slice",
    args: { path: "res://scripts/player.gd", startLine: 1, endLine: 20 },
    result: "x".repeat(15050),
  },
]);
assert.strictEqual(sanitizedHistory.length, 1);
assert.strictEqual(sanitizedHistory[0].tool, "read_script_slice");
assert.strictEqual(typeof sanitizedHistory[0].result, "string");
assert(sanitizedHistory[0].result.length <= 12000, "Expected oversized tool result truncated <= 12000 chars");

const mtBaseArgs = {
  mode: "build_feature",
  rootSpec: payload4t.rootSpec,
  epicSpec: payload4t.activeEpic,
  featureSpec: payload4t.activeFeature,
  siblingFeaturesSummary: payload4t.siblingFeaturesSummary,
  godotContextMarkdown: payload4t.activeFeatureContextMarkdown,
  maxTurns: 6,
  projectManifest: {
    sceneFiles: ["res://scenes/arena_proto.tscn"],
    scriptFiles: ["res://scripts/player.gd"],
    autoloads: { GameBus: "res://autoload/game_bus.gd" },
    layerNames: { "3d_physics/layer_1": "World" },
  },
  arenaScenePath: payload4t.arenaScenePath,
  epicScenePath: "res://scenes/player_mech.tscn",
};

const mtPromptT1 = buildGodotMultiTurnPrompt({
  ...mtBaseArgs,
  turnIndex: 1,
});
assert.strictEqual(mtPromptT1.thinkingLevel, "LOW");
assert.strictEqual(mtPromptT1.forceFinal, false);
assert.strictEqual(mtPromptT1.turnIndex, 1);
assert.strictEqual(mtPromptT1.maxTurns, 6);
for (const toolName of GODOT_READONLY_TOOL_NAMES) {
  assert(mtPromptT1.systemInstruction.includes(toolName), `Expected ${toolName} in systemInstruction`);
}
assert(mtPromptT1.systemInstruction.includes("tool_calls"));
assert(mtPromptT1.systemInstruction.includes("final_bundle"));
assert(mtPromptT1.systemInstruction.includes("4"));
assert(mtPromptT1.systemInstruction.includes("patches"));
assert(mtPromptT1.preserveExports.includes("move_speed"));
assert(mtPromptT1.preserveInputActions.includes("move_left"));
assert(Array.isArray(mtPromptT1.contents), "Expected contents[] on multi-turn prompt");
assert.strictEqual(mtPromptT1.contents.length, 1);
assert.strictEqual(mtPromptT1.contents[0].role, "user");
const mtT1Text = mtPromptT1.contents[0].parts[0].text;
assert(mtT1Text.includes("GameBus"));
assert(mtT1Text.includes("3d_physics/layer_1"));
assert(mtT1Text.includes('"maxTurns":6'));
assert(!mtT1Text.includes("# ACTIVE FEATURE SPEC"), "Expected no duplicated godotContextMarkdown when featureSpec present");

const t1ReadEntry = {
  turn: 1,
  tool: "read_script_slice",
  args: { path: "res://scripts/player.gd", startLine: 1, endLine: 20 },
  result: { ok: true, content: "extends CharacterBody3D\n@export var move_speed: float = 6.4" },
};
const t2InspectEntry = {
  turn: 2,
  tool: "inspect_scene_tree",
  args: { path: "res://scenes/arena_proto.tscn" },
  result: { ok: true, nodes: [{ path: ".", name: "ArenaProto", class: "Node3D" }] },
};

const mtPromptT2 = buildGodotMultiTurnPrompt({
  ...mtBaseArgs,
  turnIndex: 2,
  toolHistory: [t1ReadEntry],
});
assert.strictEqual(mtPromptT2.systemInstruction, mtPromptT1.systemInstruction, "systemInstruction must stay byte-identical Turn 1 -> 2");
assert.deepStrictEqual(mtPromptT2.contents.map((c) => c.role), ["user", "model", "user"]);
assert.strictEqual(
  mtPromptT2.contents[0].parts[0].text,
  mtPromptT1.contents[0].parts[0].text,
  "Turn-1 user prefix must stay byte-identical across Turn 2"
);

const mtPromptT3 = buildGodotMultiTurnPrompt({
  ...mtBaseArgs,
  turnIndex: 3,
  toolHistory: [t1ReadEntry, t2InspectEntry],
});
assert.strictEqual(mtPromptT3.systemInstruction, mtPromptT1.systemInstruction, "systemInstruction must stay byte-identical Turn 1 -> 3");
assert.deepStrictEqual(
  mtPromptT3.contents.map((c) => c.role),
  ["user", "model", "user", "model", "user"]
);
for (let i = 0; i < 3; i += 1) {
  assert.deepStrictEqual(
    mtPromptT3.contents[i],
    mtPromptT2.contents[i],
    `Expected prefix contents[${i}] to match byte-for-byte between Turn 2 and Turn 3`
  );
}

const mtPromptT6 = buildGodotMultiTurnPrompt({
  mode: "fix_feature",
  rootSpec: payload4t.rootSpec,
  epicSpec: payload4t.activeEpic,
  featureSpec: payload4t.activeFeature,
  siblingFeaturesSummary: payload4t.siblingFeaturesSummary,
  godotContextMarkdown: payload4t.activeFeatureContextMarkdown,
  turnIndex: 6,
  maxTurns: 6,
  toolHistory: sanitizedHistory,
  errorText: "SCRIPT ERROR: Parse Error at line 14",
});
assert.strictEqual(mtPromptT6.thinkingLevel, "MEDIUM");
assert.strictEqual(mtPromptT6.forceFinal, true);
assert(Array.isArray(mtPromptT6.contents) && mtPromptT6.contents.length === 3);
assert.strictEqual(mtPromptT6.contents[0].role, "user");
assert.strictEqual(mtPromptT6.contents[1].role, "model");
assert.strictEqual(mtPromptT6.contents[2].role, "user");
assert(mtPromptT6.contents[0].parts[0].text.includes("Parse Error at line 14"));
assert(mtPromptT6.contents[1].parts[0].text.includes("read_script_slice"));
assert(
  mtPromptT6.contents[2].parts[0].text.toLowerCase().includes("disabled") &&
    mtPromptT6.contents[2].parts[0].text.includes("final_bundle"),
  "Expected Turn 6 trailing user turn to disable tool_calls and require final_bundle"
);

// (a) tool_calls step: strips disallowed tool, normalizes name/arguments aliases, caps at 4
const rawStepCandidates = {
  type: "tool_calls",
  thought: "Inspect scripts and scene tree first.",
  toolCalls: [
    { tool: "delete_file", args: { path: "res://scripts/player.gd" } },
    { tool: "list_project_files", args: { dir: "res://" } },
    { tool: "grep_project_text", args: { query: "dash" } },
    { name: "inspect_scene_tree", arguments: { path: "res://scenes/arena_proto.tscn" } },
    { tool: "read_script_slice", args: { path: "res://scripts/player.gd", startLine: 1, endLine: 40 } },
    { tool: "read_autoloads_and_layers", args: {} },
  ],
};
const stepToolCalls = normalizeAgentStepResponse(rawStepCandidates, "build_feature", {
  dimension: "dim3d",
  forceFinal: false,
});
assert.strictEqual(stepToolCalls.type, "tool_calls");
assert.strictEqual(stepToolCalls.toolCalls.length, 4);
assert(!stepToolCalls.toolCalls.some((c) => c.tool === "delete_file"));
assert.strictEqual(stepToolCalls.toolCalls[2].tool, "inspect_scene_tree");
assert.deepStrictEqual(stepToolCalls.toolCalls[2].args, { path: "res://scenes/arena_proto.tscn" });

// (b) Same tool_calls payload under forceFinal=true coerces to final_bundle
const stepForcedFinal = normalizeAgentStepResponse(rawStepCandidates, "build_feature", {
  dimension: "dim3d",
  forceFinal: true,
});
assert.strictEqual(stepForcedFinal.type, "final_bundle");
assert(stepForcedFinal.bundle && Array.isArray(stepForcedFinal.bundle.scriptUpdates));

// (c) final_bundle step preserves patches & sibling input protections
const stepFinalBundle = normalizeAgentStepResponse({
  type: "final_bundle",
  thought: "Apply dash patch and action.",
  bundle: {
    summary: "Implemented F02 dash",
    scriptUpdates: [
      {
        resPath: "scripts/player.gd",
        patches: [{ find: "\tmove_and_slide()", replace: "\t_dash()\n\tmove_and_slide()" }],
      },
    ],
    inputOps: [
      { action: "claw_dash", keys: ["SPACE"], overwrite: true },
      { action: "move_left", remove: true },
    ],
  },
}, "build_feature", {
  dimension: "dim3d",
  featureId: "f02",
  featureCode: "F02",
  preserveExports: ["move_speed"],
  preserveInputActions: ["move_left"],
  forceFinal: false,
});
assert.strictEqual(stepFinalBundle.type, "final_bundle");
assert.strictEqual(stepFinalBundle.bundle.scriptUpdates[0].resPath, "res://scripts/player.gd");
assert.strictEqual(stepFinalBundle.bundle.scriptUpdates[0].patches.length, 1);
assert.strictEqual(stepFinalBundle.bundle.inputOps.length, 1);
assert.strictEqual(stepFinalBundle.bundle.inputOps[0].action, "claw_dash");
assert.deepStrictEqual(stepFinalBundle.bundle.preserveExports, ["move_speed"]);

// (d) Unwrapped bundle object coerces to final_bundle
const stepUnwrapped = normalizeAgentStepResponse({
  summary: "Unwrapped bundle recovery",
  scriptUpdates: [
    { resPath: "scripts/player.gd", patches: [{ find: "pass", replace: "return" }] },
  ],
}, "build_feature", { dimension: "dim3d", forceFinal: false });
assert.strictEqual(stepUnwrapped.type, "final_bundle");
assert.strictEqual(stepUnwrapped.bundle.scriptUpdates[0].resPath, "res://scripts/player.gd");

// (e) tool_calls containing ONLY disallowed tools never returns empty tool_calls
const stepOnlyDisallowed = normalizeAgentStepResponse({
  type: "tool_calls",
  toolCalls: [{ tool: "delete_file", args: {} }],
}, "build_feature", { dimension: "dim3d", forceFinal: false });
assert.strictEqual(stepOnlyDisallowed.type, "final_bundle");
assert(stepOnlyDisallowed.bundle && Array.isArray(stepOnlyDisallowed.bundle.scriptUpdates));

// (f) Read-only /godotLink/epic pull does not hijack Web Studio's selected_epic_id / selected_feature_id
const readOnlyPullSec = buildGodotSyncProjectSectionsJs({
  existingSections: { selected_epic_id: "epic_2", selected_feature_id: "" },
  payload: { activeEpic: { id: "epic_2" }, activeFeature: { id: "feat_dash" } },
  liveGodotContext: liveCtx,
  nowMs: 1234567890,
  explicitEpicId: "",
  explicitFeatureId: "",
  isReadOnlyPull: true,
});
assert.strictEqual(readOnlyPullSec.last_godot_sync_ms, "1234567890");
assert(typeof readOnlyPullSec.godot_live_context_json === "string");
assert.strictEqual(
  Object.prototype.hasOwnProperty.call(readOnlyPullSec, "selected_epic_id"),
  false
);
assert.strictEqual(
  Object.prototype.hasOwnProperty.call(readOnlyPullSec, "selected_feature_id"),
  false
);

// Explicit pull selection updates selected_epic_id & selected_feature_id
const explicitPullSec = buildGodotSyncProjectSectionsJs({
  existingSections: { selected_epic_id: "epic_1", selected_feature_id: "" },
  payload: { activeEpic: { id: "epic_2" }, activeFeature: { id: "feat_dash" } },
  liveGodotContext: liveCtx,
  nowMs: 1234567891,
  explicitEpicId: "epic_2",
  explicitFeatureId: "feat_dash",
  isReadOnlyPull: true,
});
assert.strictEqual(explicitPullSec.selected_epic_id, "epic_2");
assert.strictEqual(explicitPullSec.selected_feature_id, "feat_dash");

// sync_project without explicitFeatureId preserves Web Studio's Epic Domain Sheet (selected_feature_id: "")
const syncDomainSheetSec = buildGodotSyncProjectSectionsJs({
  existingSections: { selected_epic_id: "epic_2", selected_feature_id: "" },
  payload: { activeEpic: { id: "epic_2" }, activeFeature: { id: "feat_dash" } },
  nowMs: 1234567892,
  explicitFeatureId: "",
  action: "sync_project",
});
assert.strictEqual(syncDomainSheetSec.selected_epic_id, "epic_2");
assert.strictEqual(syncDomainSheetSec.selected_feature_id, "");

// pass_feature clears selected_feature_id when payload advances/clears, toggle_check selects active feature
const passFeatureSec = buildGodotSyncProjectSectionsJs({
  existingSections: { selected_epic_id: "epic_2", selected_feature_id: "feat_dash" },
  payload: { activeEpic: { id: "epic_2" }, activeFeature: null },
  nowMs: 1234567893,
  action: "pass_feature",
});
assert.strictEqual(passFeatureSec.selected_epic_id, "epic_2");
assert.strictEqual(passFeatureSec.selected_feature_id, "");

const toggleCheckSec = buildGodotSyncProjectSectionsJs({
  existingSections: { selected_epic_id: "epic_2", selected_feature_id: "" },
  payload: { activeEpic: { id: "epic_2" }, activeFeature: { id: "feat_dash" } },
  nowMs: 1234567894,
  action: "toggle_check",
});
assert.strictEqual(toggleCheckSec.selected_epic_id, "epic_2");
assert.strictEqual(toggleCheckSec.selected_feature_id, "feat_dash");

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
