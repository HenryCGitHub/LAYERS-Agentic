const {
  resolveDimensionMetaJs,
  normalizeResPathJs,
  stripDiffLinePrefixes,
  sanitizeGodotTuningKeyJs,
} = require("./godot_spec_context");

const VALID_SCENE_OPS = new Set([
  "ensure_node",
  "set_property",
  "reparent_node",
  "attach_script",
  "detach_script",
  "connect_signal",
  "instance_scene",
  "remove_node",
  "add_to_group",
]);

function normalizeAgentBundle(rawObj, mode, opts = {}) {
  const obj = rawObj && typeof rawObj === "object" ? rawObj : {};
  const effectiveMode = String(obj.mode || mode || "build_epic").trim();
  const rawUpdates = Array.isArray(obj.scriptUpdates) ? obj.scriptUpdates : [];
  const scriptUpdates = [];
  for (const u of rawUpdates) {
    if (!u || typeof u !== "object") continue;
    const resPath = normalizeResPathJs(u.resPath || u.res_path || "");
    const content = stripDiffLinePrefixes(u.content || "");
    const rawPatches = Array.isArray(u.patches) ? u.patches : [];
    const patches = [];
    for (const p of rawPatches) {
      if (!p || typeof p !== "object") continue;
      const rawFind = p.find ?? p.search ?? p.old;
      const rawReplace = p.replace ?? p.replacement ?? p.new;
      if (typeof rawFind !== "string" || rawFind.length === 0) continue;
      if (typeof rawReplace !== "string") continue;
      patches.push({
        find: rawFind.replace(/\r\n/g, "\n"),
        replace: rawReplace.replace(/\r\n/g, "\n"),
      });
    }
    if (!resPath || (!content && patches.length === 0)) continue;
    const entry = {
      resPath,
      attachTo: String(u.attachTo || u.attach_to || "").trim(),
      scenePath: normalizeResPathJs(u.scenePath || u.scene_path || ""),
      language: String(u.language || "gdscript").trim().toLowerCase(),
      content,
    };
    if (patches.length > 0) {
      entry.patches = patches;
    }
    scriptUpdates.push(entry);
  }

  const rawOps = Array.isArray(obj.sceneOps) ? obj.sceneOps : [];
  const sceneOps = [];
  for (const opObj of rawOps) {
    if (!opObj || typeof opObj !== "object") continue;
    const op = String(opObj.op || opObj.type || "").trim().toLowerCase();
    if (!VALID_SCENE_OPS.has(op)) continue;
    sceneOps.push({
      op,
      scenePath: normalizeResPathJs(opObj.scenePath || opObj.scene_path || ""),
      nodePath: String(opObj.nodePath || opObj.node_path || "").trim(),
      parentPath: String(opObj.parentPath || opObj.parent_path || "").trim(),
      newParentPath: String(
        opObj.newParentPath || opObj.new_parent_path || ""
      ).trim(),
      nodeName: String(opObj.nodeName || opObj.node_name || "").trim(),
      nodeType: String(opObj.nodeType || opObj.node_type || "").trim(),
      subResourceClass: String(
        opObj.subResourceClass || opObj.sub_resource_class || ""
      ).trim(),
      subResourceProps:
        opObj.subResourceProps && typeof opObj.subResourceProps === "object"
          ? opObj.subResourceProps
          : {},
      properties:
        opObj.properties && typeof opObj.properties === "object"
          ? opObj.properties
          : {},
      groups: Array.isArray(opObj.groups)
        ? opObj.groups.map((g) => String(g || "").trim()).filter(Boolean)
        : [],
      scriptPath: normalizeResPathJs(opObj.scriptPath || opObj.script_path || ""),
      sourcePath: String(opObj.sourcePath || opObj.source_path || "").trim(),
      signalName: String(opObj.signalName || opObj.signal_name || "").trim(),
      targetPath: String(opObj.targetPath || opObj.target_path || "").trim(),
      methodName: String(opObj.methodName || opObj.method_name || "").trim(),
      instancePath: normalizeResPathJs(
        opObj.instancePath || opObj.instance_path || ""
      ),
    });
  }

  const protectedActions = new Set(
    (Array.isArray(opts.preserveInputActions) ? opts.preserveInputActions : [])
      .map((a) => String(a || "").trim().toLowerCase())
      .filter(Boolean)
  );

  const rawInputs = Array.isArray(obj.inputOps)
    ? obj.inputOps
    : Array.isArray(obj.input_ops)
      ? obj.input_ops
      : [];
  const inputOps = [];
  for (const inp of rawInputs) {
    if (!inp || typeof inp !== "object") continue;
    const action = String(inp.action || inp.name || "").trim();
    const rawKeys = Array.isArray(inp.keys)
      ? inp.keys
      : inp.key
        ? [inp.key]
        : [];
    const keys = rawKeys.map((k) => String(k || "").trim()).filter(Boolean);
    const remove =
      Boolean(inp.remove) ||
      String(inp.op || inp.type || "").trim().toLowerCase() === "remove_action";
    const overwrite = Boolean(inp.overwrite);
    if (!action) continue;
    if (
      remove &&
      (effectiveMode === "build_feature" || protectedActions.has(action.toLowerCase()))
    ) {
      continue;
    }
    const normInput = { action, keys };
    if (remove) normInput.remove = true;
    if (overwrite) normInput.overwrite = true;
    inputOps.push(normInput);
  }

  const defaultDimScene =
    opts.dimension === "dim2d"
      ? "res://scenes/arena_2d.tscn"
      : "res://scenes/arena_3d.tscn";
  const arenaScenePath = normalizeResPathJs(
    obj.arenaScenePath || obj.arena_scene_path || opts.arenaScenePath || defaultDimScene
  );
  const featureScenePath = normalizeResPathJs(
    obj.epicScenePath ||
      obj.epic_scene_path ||
      obj.featureScenePath ||
      obj.feature_scene_path ||
      opts.epicScenePath ||
      arenaScenePath ||
      defaultDimScene
  );
  const preserveExports = Array.from(
    new Set(
      (Array.isArray(opts.preserveExports) ? opts.preserveExports : [])
        .map((k) => sanitizeGodotTuningKeyJs(k, ""))
        .filter(Boolean)
    )
  );

  return {
    mode: effectiveMode,
    summary: String(obj.summary || "").trim(),
    diagnosis: String(obj.diagnosis || "").trim(),
    dimension: opts.dimension || "dim3d",
    featureId: String(obj.featureId || opts.featureId || "").trim(),
    featureCode: String(obj.featureCode || opts.featureCode || "").trim(),
    preserveExports,
    arenaScenePath,
    featureScenePath,
    epicScenePath: featureScenePath,
    scriptUpdates,
    sceneOps,
    inputOps,
  };
}

async function callGeminiFlashJson({
  apiKey,
  systemInstruction,
  userPrompt,
  contents = null,
  thinkingLevel = "LOW",
  maxOutputTokens = 16384,
}) {
  const models = ["gemini-4-hydrogen", "gemini-flash-latest"];
  const resolvedContents =
    Array.isArray(contents) && contents.length > 0
      ? contents
      : [{ role: "user", parts: [{ text: userPrompt }] }];
  let lastError = "Gemini request failed.";
  for (const modelId of models) {
    const endpoint = `https://generativelanguage.googleapis.com/v1beta/models/${modelId}:generateContent?key=${encodeURIComponent(
      apiKey
    )}`;
    const basePayload = {
      systemInstruction: { parts: [{ text: systemInstruction }] },
      contents: resolvedContents,
      generationConfig: {
        temperature: 0.2,
        maxOutputTokens,
        responseMimeType: "application/json",
      },
    };
    const payloads =
      modelId === "gemini-4-hydrogen"
        ? [
            {
              ...basePayload,
              generationConfig: {
                ...basePayload.generationConfig,
                thinkingConfig: { thinkingLevel },
              },
            },
            basePayload,
          ]
        : [basePayload];

    for (const payload of payloads) {
      try {
        const resp = await fetch(endpoint, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(payload),
        });
        if (!resp.ok) {
          const errTxt = await resp.text();
          lastError = `${modelId} HTTP ${resp.status}: ${errTxt.slice(0, 220)}`;
          if (resp.status === 400 && payload !== payloads[payloads.length - 1]) {
            continue;
          }
          break;
        }
        const jsonResp = await resp.json();
        const parts = jsonResp?.candidates?.[0]?.content?.parts || [];
        const rawText = parts
          .filter((p) => p && !p.thought && typeof p.text === "string")
          .map((p) => p.text)
          .join("\n")
          .trim();
        if (!rawText) {
          lastError = `${modelId} returned empty response.`;
          continue;
        }
        const cleanJson = rawText
          .replace(/^```json\s*/i, "")
          .replace(/^```\s*/i, "")
          .replace(/```\s*$/i, "")
          .trim();
        const parsed = JSON.parse(cleanJson);
        return { ok: true, model: modelId, data: parsed };
      } catch (err) {
        lastError = `${modelId}: ${String(err && err.message ? err.message : err)}`;
      }
    }
  }
  return { ok: false, error: lastError };
}

const GODOT_READONLY_TOOL_NAMES = new Set([
  "list_project_files",
  "grep_project_text",
  "read_script_slice",
  "inspect_scene_tree",
  "read_autoloads_and_layers",
  "inspect_tres_resource",
]);
const GODOT_MULTI_TURN_MAX_TURNS = 6;
const GODOT_MULTI_TURN_MAX_CALLS_PER_TURN = 4;

const GODOT_AGENT_CORE_RULES = [
  "1. NEVER emit push_warning(...) placeholders or stub comments. Emit real, playable typed GDScript 2.0 and real sceneOps.",
  "2. GODOT 4.7 STRICT TYPING: NEVER write ':=' when assigning from a Variant dictionary/array/JSON getter (e.g. dict.get(...), JSON.parse_string(...), arr[0]). Always annotate explicit types ('var x: String = ...', 'var f: float = ...', 'var parsed: Variant = ...') and typed Array constructors.",
  "3. TARGETED .gd PATCHES FOR EXISTING SCRIPTS: For ANY existing .gd file already present in liveScripts or read via read_script_slice, emit scriptUpdates entries with patches: [{ find, replace }] (exact contiguous blocks copied verbatim from liveScripts[resPath] or read_script_slice with exact leading tabs and 2-4 surrounding context lines) instead of rewriting the full file. Emit full content ONLY for brand-new .gd files absent from the project (or when errorText explicitly reports a PATCH MISMATCH requiring a full rewrite).",
  "4. @EXPORT TUNING VARS: Expose EVERY §03 tuning variable from the active Feature with exact snake_case '@export var ...' at the top of the relevant script with matching defaults.",
  "5. PRESERVE PASSING SIBLING FEATURES: Keep EVERY passed/baseline sibling Feature working; never delete or break existing @export vars in preserveExports, InputMap actions in preserveInputActions, existing scene nodes, or signal connections.",
  "6. sceneOps: array of structured scene mutations: ensure_node, set_property, reparent_node, attach_script, detach_script, connect_signal, instance_scene, remove_node, add_to_group.",
  "7. ClassDB SAFETY: NEVER attach a script whose 'extends <Class>' is incompatible with the target node class.",
  "8. SIGNAL & ARITY SAFETY: Connect signals ONLY to nodes defining methodName with matching parameter count (use optional '_arg: Variant = null' if emitting args).",
  "9. MATERIALS & SHAPES: Specify explicit subResourceClass + subResourceProps (BoxShape3D/CapsuleShape3D/SphereShape3D or RectangleShape2D/CircleShape2D, BoxMesh/CapsuleMesh, StandardMaterial3D albedo_color).",
  "10. SCENE TREE & _ready() SAFETY: Use add_child(inst) BEFORE setting inst.global_position; use call_deferred when adding siblings inside _ready(). Clean up projectiles/enemies with queue_free().",
  "11. ADDITIVE INPUT OPS: Declare each InputMap action in inputOps: [{ action: 'snake_case', keys: ['SHIFT'], overwrite: true }] using W/A/S/D/SPACE/SHIFT/CTRL/E/Q/F/R/TAB/LMB/RMB/MMB. Never remove protected sibling actions; on build_feature keep inputOps strictly additive.",
  "12. MOUSE & PAUSE SAFETY: If capturing mouse in 3D, wire ESC ('ui_cancel') toggle in _unhandled_input. Put HUD Controls inside CanvasLayer.",
  "13. 3D FACING & INSTANT HIT WINDOWS: Align VisualRig forward direction (+basis.z for atan2(dir.x, dir.z), -basis.z for look_at), parent hitbox pivots under VisualRig, and check get_overlapping_bodies() with a hit_targets guard on swing open.",
  "14. OBSERVABLE PLAYTEST FEEDBACK: Trigger albedo/modulate flashes, knockback, camera punch, cooldown HUD bar, and clear Test Scene greybox props matching §04 & §05.",
];

function computeGodotAgentScopeAndGuards({
  mode,
  rootSpec,
  epicSpec,
  featureSpec = null,
  siblingFeaturesSummary = [],
}) {
  const dimMeta = resolveDimensionMetaJs(rootSpec?.dimension);
  const isFixMode = mode === "fix_feature" || mode === "fix_epic";
  const isFeatureMode =
    Boolean(featureSpec) &&
    (mode === "build_feature" ||
      mode === "fix_feature" ||
      (mode !== "build_epic" && mode !== "fix_epic"));

  const siblings = Array.isArray(siblingFeaturesSummary)
    ? siblingFeaturesSummary
    : [];
  const passedSiblings = siblings.filter((s) =>
    Boolean(s?.isPassed || s?.isLockedBaseline)
  );
  const preserveExports = Array.from(
    new Set(
      passedSiblings
        .flatMap((s) => (Array.isArray(s.tuningKeys) ? s.tuningKeys : []))
        .map((k) => sanitizeGodotTuningKeyJs(k, ""))
        .filter(Boolean)
    )
  );
  const preserveInputActions = Array.from(
    new Set(
      passedSiblings
        .flatMap((s) => (Array.isArray(s.inputActions) ? s.inputActions : []))
        .map((a) => String(a || "").trim())
        .filter(Boolean)
    )
  );

  const dimRules =
    dimMeta.id === "dim2d"
      ? "DIMENSION CONTRACT (Godot 4 · 2D): Use CharacterBody2D / Node2D / Area2D / Camera2D / Sprite2D or ColorRect/Polygon2D in pixel space (px, px/s)."
      : "DIMENSION CONTRACT (Godot 4 · 3D): Use CharacterBody3D / Node3D / Area3D / SpringArm3D / Camera3D / CSGBox3D / CSGCylinder3D / MeshInstance3D in meters (1 unit = 1 m). Ground at Y=0.";

  const compactEpicArchitecture = featureSpec
    ? {
        id: epicSpec?.id || "",
        code: epicSpec?.code || "",
        title: epicSpec?.title || "",
        releaseVersion: epicSpec?.releaseVersion || "v0.1",
        goal: epicSpec?.goal || "",
        inScope: Array.isArray(epicSpec?.inScope) ? epicSpec.inScope : [],
        doneWhen: Array.isArray(epicSpec?.doneWhen) ? epicSpec.doneWhen : [],
        sceneOwnership: Array.isArray(epicSpec?.sceneOwnership)
          ? epicSpec.sceneOwnership
          : [],
        stateFlow: Array.isArray(epicSpec?.stateFlow)
          ? epicSpec.stateFlow
          : epicSpec?.states || [],
        interruptRules: Array.isArray(epicSpec?.interruptRules)
          ? epicSpec.interruptRules
          : epicSpec?.interrupts || [],
        outOfScope: Array.isArray(epicSpec?.outOfScope) ? epicSpec.outOfScope : [],
      }
    : null;

  let taskHeader;
  if (isFeatureMode) {
    const fLabel = `${featureSpec.code || "Feature"} · ${featureSpec.title || "Slice"}`;
    taskHeader = isFixMode
      ? `TASK: Diagnose and repair compile errors, runtime errors, or open [FIX] notes on ${fLabel} using targeted .gd patches while keeping passed sibling Features intact.`
      : `TASK: Build Feature slice ${fLabel} inside the parent Epic ${epicSpec?.code || ""} architecture (${dimMeta.shortLabel}) using targeted .gd patches on existing scripts, new .gd scripts where needed, additive inputOps, and sceneOps so Playtest works immediately.`;
  } else {
    taskHeader =
      mode === "build_epic"
        ? `TASK: Build the cohesive Godot 4 (${dimMeta.shortLabel}) Epic §01-§06 (scenes .tscn, scripts .gd, InputMap actions, tuning @exports, greybox test room props) so the developer can press Play immediately.`
        : "TASK: Diagnose and repair compile errors, runtime errors, or open [FIX] items across affected Godot scripts, scenes, and InputMap while preserving passing playtest gates.";
  }

  return {
    dimMeta,
    dimRules,
    isFixMode,
    isFeatureMode,
    siblings,
    preserveExports,
    preserveInputActions,
    compactEpicArchitecture,
    taskHeader,
  };
}

function buildGodotAgentPrompts({
  mode,
  rootSpec,
  epicSpec,
  featureSpec = null,
  siblingFeaturesSummary = [],
  godotContextMarkdown,
  liveScripts,
  sceneSnapshot,
  inputMapSnapshot,
  projectDiagnostics,
  liveGodotContext,
  prompt,
  errorText,
  arenaScenePath,
  epicScenePath,
}) {
  const mergedScripts = {};
  if (liveScripts && typeof liveScripts === "object") {
    for (const [k, v] of Object.entries(liveScripts)) {
      const norm = normalizeResPathJs(k);
      if (norm && typeof v === "string") mergedScripts[norm] = v;
    }
  }

  const scope = computeGodotAgentScopeAndGuards({
    mode,
    rootSpec,
    epicSpec,
    featureSpec,
    siblingFeaturesSummary,
  });

  const systemInstruction = [
    "You are LAYERS Godot 4 Feature Co-Builder targeting Godot 4.7.2.stable.",
    scope.dimRules,
    "Return strictly valid JSON with keys: mode, summary, diagnosis, arenaScenePath, epicScenePath, scriptUpdates, sceneOps, inputOps.",
    "STRICT ENGINE & GODOT 4.7 OUTPUT RULES:",
    ...GODOT_AGENT_CORE_RULES,
  ].join("\n");

  const contextPayload = {
    mode,
    dimension: scope.dimMeta.id,
    projectTitle: rootSpec?.normalizedTitle || "LAYERS Project",
    arenaScenePath: String(arenaScenePath || ""),
    epicScenePath: String(epicScenePath || ""),
    godotContextMarkdown: String(godotContextMarkdown || "").slice(0, 16000),
    ...(featureSpec
      ? {
          epicArchitecture: scope.compactEpicArchitecture,
          activeFeature: featureSpec,
          siblingFeaturesSummary: scope.siblings,
          preserveExports: scope.preserveExports,
          preserveInputActions: scope.preserveInputActions,
        }
      : {
          epicSpec: epicSpec || {},
        }),
    userPrompt: String(prompt || "").trim(),
    errorText: String(errorText || "").trim(),
    liveGodotContext: liveGodotContext || {},
    liveScripts: mergedScripts,
    liveSceneSnapshot: sceneSnapshot || {},
    liveInputMap:
      inputMapSnapshot && typeof inputMapSnapshot === "object"
        ? inputMapSnapshot
        : {},
    projectDiagnostics: Array.isArray(projectDiagnostics)
      ? projectDiagnostics
      : [],
  };

  const payloadLabel = scope.isFeatureMode
    ? "PROJECT & FEATURE CONTEXT JSON:"
    : "PROJECT & EPIC CONTEXT JSON:";

  const userPrompt = [scope.taskHeader, payloadLabel, JSON.stringify(contextPayload)].join(
    "\n\n"
  );

  return {
    systemInstruction,
    userPrompt,
    thinkingLevel: scope.isFixMode ? "MEDIUM" : "LOW",
    preserveExports: scope.preserveExports,
    preserveInputActions: scope.preserveInputActions,
    isFeatureMode: scope.isFeatureMode,
    isFixMode: scope.isFixMode,
  };
}

function sanitizeToolHistoryJs(toolHistory) {
  if (!Array.isArray(toolHistory)) return [];
  const filtered = [];
  for (const entry of toolHistory) {
    if (!entry || typeof entry !== "object") continue;
    const tool = String(entry.tool || entry.name || "").trim();
    if (!GODOT_READONLY_TOOL_NAMES.has(tool)) continue;
    const rawTurn = Number(entry.turn);
    const turn = Number.isFinite(rawTurn) && rawTurn > 0 ? Math.round(rawTurn) : 1;
    const rawArgs = entry.args !== undefined ? entry.args : entry.arguments;
    const args =
      rawArgs && typeof rawArgs === "object" && !Array.isArray(rawArgs)
        ? rawArgs
        : {};
    let result = entry.result;
    if (typeof result === "string") {
      if (result.length > 12000) {
        result = `${result.slice(0, 11985)}...[truncated]`;
      }
    } else if (result !== undefined && result !== null) {
      let serialized = "";
      try {
        serialized = JSON.stringify(result);
      } catch (_) {
        serialized = String(result);
      }
      if (serialized.length > 12000) {
        result = `${serialized.slice(0, 11985)}...[truncated]`;
      }
    } else {
      result = {};
    }
    filtered.push({ turn, tool, args, result });
  }
  const recent = filtered.slice(-24);
  const kept = [];
  let totalChars = 0;
  for (let i = recent.length - 1; i >= 0; i -= 1) {
    const item = recent[i];
    const len = JSON.stringify(item).length;
    if (kept.length > 0 && totalChars + len > 40000) break;
    kept.push(item);
    totalChars += len;
  }
  kept.reverse();
  return kept;
}

function buildGodotMultiTurnPrompt({
  mode,
  rootSpec,
  epicSpec,
  featureSpec = null,
  siblingFeaturesSummary = [],
  godotContextMarkdown = "",
  projectManifest = null,
  toolHistory = [],
  turnIndex = 1,
  maxTurns = GODOT_MULTI_TURN_MAX_TURNS,
  liveScripts = null,
  sceneSnapshot = null,
  inputMapSnapshot = null,
  projectDiagnostics = [],
  liveGodotContext = null,
  prompt = "",
  errorText = "",
  arenaScenePath = "",
  epicScenePath = "",
}) {
  const parsedMax = Number.parseInt(String(maxTurns ?? GODOT_MULTI_TURN_MAX_TURNS), 10);
  const clampedMaxTurns = Math.min(
    GODOT_MULTI_TURN_MAX_TURNS,
    Math.max(1, Number.isFinite(parsedMax) ? parsedMax : GODOT_MULTI_TURN_MAX_TURNS)
  );
  const parsedTurn = Number.parseInt(String(turnIndex ?? 1), 10);
  const clampedTurnIndex = Math.min(
    clampedMaxTurns,
    Math.max(1, Number.isFinite(parsedTurn) ? parsedTurn : 1)
  );
  const forceFinal = clampedTurnIndex >= clampedMaxTurns;

  const mergedScripts = {};
  if (liveScripts && typeof liveScripts === "object") {
    for (const [k, v] of Object.entries(liveScripts)) {
      const norm = normalizeResPathJs(k);
      if (norm && typeof v === "string") mergedScripts[norm] = v;
    }
  }

  const scope = computeGodotAgentScopeAndGuards({
    mode,
    rootSpec,
    epicSpec,
    featureSpec,
    siblingFeaturesSummary,
  });
  const sanitizedHistory = sanitizeToolHistoryJs(toolHistory);

  const responseProtocolBlock = [
    `MULTI-TURN PROTOCOL (up to ${clampedMaxTurns} turns): Either inspect the Godot 4 project with read-only tools OR emit your final edit bundle.`,
    `Option A — Request read-only project tools (max ${GODOT_MULTI_TURN_MAX_CALLS_PER_TURN} calls per turn; disabled on final turn ${clampedMaxTurns}/${clampedMaxTurns}):`,
    '  { "type": "tool_calls", "thought": "what you are checking next", "toolCalls": [{ "tool": "<tool_name>", "args": { ... } }] }',
    "Option B — Return final implementation/fix bundle when ready (required on final turn):",
    `  { "type": "final_bundle", "thought": "brief summary", "bundle": { "mode": "${mode}", "summary": "...", "diagnosis": "...", "arenaScenePath": "...", "epicScenePath": "...", "scriptUpdates": [...], "sceneOps": [...], "inputOps": [...] } }`,
  ].join("\n");

  const systemInstruction = [
    "You are LAYERS Godot 4 Feature Co-Builder targeting Godot 4.7.2.stable.",
    scope.dimRules,
    responseProtocolBlock,
    "AVAILABLE READ-ONLY PROJECT TOOLS:",
    '- list_project_files({ dir?: "res://", ext?: ".gd"|".tscn"|".tres", cap?: 80 })',
    '- grep_project_text({ query: "...", dir?: "res://", ext?: "", caseSensitive?: false, maxMatches?: 25 })',
    '- read_script_slice({ path: "res://...", startLine?: 1, endLine?: 120 })',
    '- inspect_scene_tree({ path: "res://...", limitNodes?: 140 })',
    "- read_autoloads_and_layers({})",
    '- inspect_tres_resource({ path: "res://..." })',
    "MULTI-TURN ENGINEERING RULES:",
    "- NEVER guess patches[].find blocks for an existing .gd file before inspecting it via read_script_slice (or seeing it in liveScripts).",
    "- Check inherited/instanced .tscn scenes, custom .tres resources, [autoload] singletons, and [layer_names] physics layers before mutating scenes or scripts.",
    "STRICT ENGINE & GODOT 4.7 OUTPUT RULES:",
    ...GODOT_AGENT_CORE_RULES,
  ].join("\n");

  const staticContextPayload = {
    mode,
    agentProtocol: "multi_turn_v1",
    maxTurns: clampedMaxTurns,
    dimension: scope.dimMeta.id,
    projectTitle: rootSpec?.normalizedTitle || "LAYERS Project",
    arenaScenePath: String(arenaScenePath || ""),
    epicScenePath: String(epicScenePath || ""),
    ...(featureSpec
      ? {
          epicArchitecture: scope.compactEpicArchitecture,
          activeFeature: featureSpec,
          siblingFeaturesSummary: scope.siblings,
          preserveExports: scope.preserveExports,
          preserveInputActions: scope.preserveInputActions,
        }
      : {
          godotContextMarkdown: String(godotContextMarkdown || "").slice(0, 16000),
          epicSpec: epicSpec || {},
        }),
    userPrompt: String(prompt || "").trim(),
    errorText: String(errorText || "").trim(),
    liveGodotContext: liveGodotContext || {},
    projectManifest:
      projectManifest && typeof projectManifest === "object" && !Array.isArray(projectManifest)
        ? projectManifest
        : {},
    ...(Object.keys(mergedScripts).length ? { liveScripts: mergedScripts } : {}),
    ...(sceneSnapshot && typeof sceneSnapshot === "object" && Object.keys(sceneSnapshot).length
      ? { liveSceneSnapshot: sceneSnapshot }
      : {}),
    ...(inputMapSnapshot &&
    typeof inputMapSnapshot === "object" &&
    Object.keys(inputMapSnapshot).length
      ? { liveInputMap: inputMapSnapshot }
      : {}),
    ...(Array.isArray(projectDiagnostics) && projectDiagnostics.length
      ? { projectDiagnostics }
      : {}),
  };

  const payloadLabel = scope.isFeatureMode
    ? "PROJECT & FEATURE CONTEXT JSON:"
    : "PROJECT & EPIC CONTEXT JSON:";

  const initialUserText = [
    scope.taskHeader,
    payloadLabel,
    JSON.stringify(staticContextPayload),
  ].join("\n\n");

  const contents = [{ role: "user", parts: [{ text: initialUserText }] }];
  const entriesByTurn = new Map();
  for (const entry of sanitizedHistory) {
    const t = entry.turn;
    if (!entriesByTurn.has(t)) entriesByTurn.set(t, []);
    entriesByTurn.get(t).push(entry);
  }
  const sortedTurnNums = Array.from(entriesByTurn.keys()).sort((a, b) => a - b);

  if (sortedTurnNums.length === 0 && forceFinal) {
    contents[0].parts[0].text += `\n\nFINAL TURN (${clampedTurnIndex}/${clampedMaxTurns}): Tool calls are disabled now. Return final_bundle immediately.`;
  } else {
    sortedTurnNums.forEach((turnNum, idx) => {
      const entries = entriesByTurn.get(turnNum);
      contents.push({
        role: "model",
        parts: [
          {
            text: JSON.stringify({
              type: "tool_calls",
              toolCalls: entries.map((e) => ({ tool: e.tool, args: e.args })),
            }),
          },
        ],
      });
      const isLastGroup = idx === sortedTurnNums.length - 1;
      const nextTurnNum = isLastGroup
        ? clampedTurnIndex
        : Math.min(clampedMaxTurns, turnNum + 1);
      const isFinalInstruction = isLastGroup && forceFinal;
      const header = isFinalInstruction
        ? `TOOL RESULTS (Turn ${turnNum}) — FINAL TURN ${clampedTurnIndex}/${clampedMaxTurns}: Tool calls are disabled now. Return final_bundle using the gathered evidence.`
        : `TOOL RESULTS (Turn ${turnNum}) — Turn ${nextTurnNum}/${clampedMaxTurns}: Request up to ${GODOT_MULTI_TURN_MAX_CALLS_PER_TURN} more read-only tools or return final_bundle.`;
      const body = JSON.stringify(
        entries.map((e) => ({ tool: e.tool, args: e.args, result: e.result }))
      );
      contents.push({
        role: "user",
        parts: [{ text: `${header}\n\n${body}` }],
      });
    });
  }

  const userPrompt = contents
    .map((c) => c.parts.map((p) => p.text).join("\n"))
    .join("\n\n");

  return {
    systemInstruction,
    contents,
    userPrompt,
    thinkingLevel: scope.isFixMode ? "MEDIUM" : "LOW",
    preserveExports: scope.preserveExports,
    preserveInputActions: scope.preserveInputActions,
    isFeatureMode: scope.isFeatureMode,
    isFixMode: scope.isFixMode,
    turnIndex: clampedTurnIndex,
    maxTurns: clampedMaxTurns,
    forceFinal,
  };
}

function normalizeAgentStepResponse(raw, mode, opts = {}) {
  let obj = raw;
  if (typeof obj === "string") {
    try {
      obj = JSON.parse(obj);
    } catch (_) {
      obj = {};
    }
  }
  if (!obj || typeof obj !== "object" || Array.isArray(obj)) obj = {};

  const forceFinal = Boolean(opts.forceFinal);
  const thought = String(obj.thought || obj.statusNote || "").trim().slice(0, 240);
  const rawToolCalls = Array.isArray(obj.toolCalls)
    ? obj.toolCalls
    : Array.isArray(obj.tool_calls)
      ? obj.tool_calls
      : [];

  const toolCalls = [];
  for (const tc of rawToolCalls) {
    if (!tc || typeof tc !== "object") continue;
    const tool = String(tc.tool || tc.name || "").trim();
    if (!GODOT_READONLY_TOOL_NAMES.has(tool)) continue;
    const rawArgs = tc.args !== undefined ? tc.args : tc.arguments;
    const args =
      rawArgs && typeof rawArgs === "object" && !Array.isArray(rawArgs)
        ? rawArgs
        : {};
    toolCalls.push({ tool, args });
    if (toolCalls.length >= GODOT_MULTI_TURN_MAX_CALLS_PER_TURN) break;
  }

  const rawType = String(obj.type || obj.stepType || "").trim().toLowerCase();
  const hasBundleData = Boolean(
    (obj.bundle && typeof obj.bundle === "object" && !Array.isArray(obj.bundle)) ||
      Array.isArray(obj.scriptUpdates) ||
      Array.isArray(obj.script_updates) ||
      Array.isArray(obj.sceneOps) ||
      Array.isArray(obj.scene_ops) ||
      Array.isArray(obj.inputOps) ||
      Array.isArray(obj.input_ops)
  );

  if (
    !forceFinal &&
    toolCalls.length > 0 &&
    (rawType === "tool_calls" || (rawType !== "final_bundle" && !hasBundleData))
  ) {
    return {
      type: "tool_calls",
      thought,
      toolCalls,
    };
  }

  const rawBundle =
    obj.bundle && typeof obj.bundle === "object" && !Array.isArray(obj.bundle)
      ? obj.bundle
      : obj;
  const bundle = normalizeAgentBundle(rawBundle, mode, opts);
  return {
    type: "final_bundle",
    thought,
    bundle,
  };
}

async function runGodotEpicAgentWithGemini({
  apiKey,
  mode,
  rootSpec,
  epicSpec,
  featureSpec = null,
  siblingFeaturesSummary = [],
  godotContextMarkdown,
  liveScripts,
  sceneSnapshot,
  inputMapSnapshot,
  projectDiagnostics,
  liveGodotContext,
  prompt,
  errorText,
  arenaScenePath,
  epicScenePath,
}) {
  const dimMeta = resolveDimensionMetaJs(rootSpec?.dimension);
  const built = buildGodotAgentPrompts({
    mode,
    rootSpec,
    epicSpec,
    featureSpec,
    siblingFeaturesSummary,
    godotContextMarkdown,
    liveScripts,
    sceneSnapshot,
    inputMapSnapshot,
    projectDiagnostics,
    liveGodotContext,
    prompt,
    errorText,
    arenaScenePath,
    epicScenePath,
  });

  const aiResp = await callGeminiFlashJson({
    apiKey,
    systemInstruction: built.systemInstruction,
    userPrompt: built.userPrompt,
    thinkingLevel: built.thinkingLevel,
    maxOutputTokens: 16384,
  });
  if (!aiResp.ok) {
    return { ok: false, error: aiResp.error || "Gemini Feature agent request failed." };
  }
  const bundle = normalizeAgentBundle(aiResp.data, mode, {
    dimension: dimMeta.id,
    arenaScenePath: arenaScenePath || "",
    epicScenePath: epicScenePath || "",
    featureId: featureSpec?.id || "",
    featureCode: featureSpec?.code || "",
    preserveExports: built.preserveExports,
    preserveInputActions: built.preserveInputActions,
  });
  if (!bundle.summary) {
    const targetCode = featureSpec?.code || epicSpec?.code || "Feature";
    const targetTitle = featureSpec?.title || epicSpec?.title || "Slice";
    bundle.summary = built.isFixMode
      ? `Applied ${targetCode} fix (${bundle.scriptUpdates.length} scripts, ${bundle.sceneOps.length} scene ops).`
      : `Built ${targetCode} · ${targetTitle} (${bundle.scriptUpdates.length} scripts, ${bundle.sceneOps.length} scene ops).`;
  }
  return { ok: true, model: aiResp.model, bundle };
}

async function runGodotMultiTurnStepWithGemini({
  apiKey,
  mode,
  rootSpec,
  epicSpec,
  featureSpec = null,
  siblingFeaturesSummary = [],
  godotContextMarkdown = "",
  projectManifest = null,
  toolHistory = [],
  turnIndex = 1,
  maxTurns = GODOT_MULTI_TURN_MAX_TURNS,
  liveScripts = null,
  sceneSnapshot = null,
  inputMapSnapshot = null,
  projectDiagnostics = [],
  liveGodotContext = null,
  prompt = "",
  errorText = "",
  arenaScenePath = "",
  epicScenePath = "",
}) {
  const dimMeta = resolveDimensionMetaJs(rootSpec?.dimension);
  const built = buildGodotMultiTurnPrompt({
    mode,
    rootSpec,
    epicSpec,
    featureSpec,
    siblingFeaturesSummary,
    godotContextMarkdown,
    projectManifest,
    toolHistory,
    turnIndex,
    maxTurns,
    liveScripts,
    sceneSnapshot,
    inputMapSnapshot,
    projectDiagnostics,
    liveGodotContext,
    prompt,
    errorText,
    arenaScenePath,
    epicScenePath,
  });

  const aiResp = await callGeminiFlashJson({
    apiKey,
    systemInstruction: built.systemInstruction,
    userPrompt: built.userPrompt,
    contents: built.contents,
    thinkingLevel: built.thinkingLevel,
    maxOutputTokens: 16384,
  });
  if (!aiResp.ok) {
    return {
      ok: false,
      error: aiResp.error || "Gemini Feature agent step request failed.",
    };
  }

  const agentStep = normalizeAgentStepResponse(aiResp.data, mode, {
    dimension: dimMeta.id,
    arenaScenePath: arenaScenePath || "",
    epicScenePath: epicScenePath || "",
    featureId: featureSpec?.id || "",
    featureCode: featureSpec?.code || "",
    preserveExports: built.preserveExports,
    preserveInputActions: built.preserveInputActions,
    forceFinal: built.forceFinal,
  });
  if (agentStep.type === "final_bundle" && !agentStep.bundle.summary) {
    const targetCode = featureSpec?.code || epicSpec?.code || "Feature";
    const targetTitle = featureSpec?.title || epicSpec?.title || "Slice";
    agentStep.bundle.summary = built.isFixMode
      ? `Applied ${targetCode} fix (${agentStep.bundle.scriptUpdates.length} scripts, ${agentStep.bundle.sceneOps.length} scene ops).`
      : `Built ${targetCode} · ${targetTitle} (${agentStep.bundle.scriptUpdates.length} scripts, ${agentStep.bundle.sceneOps.length} scene ops).`;
  }

  return {
    ok: true,
    model: aiResp.model,
    turnIndex: built.turnIndex,
    maxTurns: built.maxTurns,
    agentStep,
  };
}

module.exports = {
  VALID_SCENE_OPS,
  GODOT_READONLY_TOOL_NAMES,
  GODOT_MULTI_TURN_MAX_TURNS,
  GODOT_MULTI_TURN_MAX_CALLS_PER_TURN,
  GODOT_AGENT_CORE_RULES,
  normalizeAgentBundle,
  callGeminiFlashJson,
  computeGodotAgentScopeAndGuards,
  buildGodotAgentPrompts,
  sanitizeToolHistoryJs,
  buildGodotMultiTurnPrompt,
  normalizeAgentStepResponse,
  runGodotEpicAgentWithGemini,
  runGodotMultiTurnStepWithGemini,
};
