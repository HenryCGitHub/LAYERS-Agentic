const DEFAULT_WEB_STUDIO_URL = "https://henrycgithub.github.io/LAYERS-Agentic/";

const specGuard = require("./godot_spec_guard");
const {
  resolveVersionTag,
  parseJsonObjectSafe,
  normalizeStringArrayJs,
  formatTradeOffJs,
  resolveCoreFeelJs,
  resolveDimensionMetaJs,
  toSnakeCaseTokenJs,
  normalizeResPathJs,
  stripDiffLinePrefixes,
  formatCleanNumJs,
  extractResPathsListJs,
  sanitizeGodotLineJs,
  sanitizeGodotTuningKeyJs,
  scaleGodotTuningValueJs,
  normalizeGodotUnitJs,
  inferGodotPropertyTypeJs,
  sanitizeGodotLiveContextJs,
} = specGuard;

function parseRootSpecJs(projectDoc) {
  const parsed =
    parseJsonObjectSafe(projectDoc?.sections?.concept_blueprint_json) || {};
  const dimMeta = resolveDimensionMetaJs(
    parsed.dimension ||
      projectDoc?.sections?.dimension ||
      parsed.targetEngine ||
      projectDoc?.sections?.engine ||
      "dim3d"
  );
  const rawTitle = String(
    parsed.gameTitle || projectDoc?.title || "UNTITLED GODOT PROJECT"
  ).trim();
  const normalizedTitle = rawTitle || "UNTITLED GODOT PROJECT";
  const coreFeel = resolveCoreFeelJs(parsed.feelChoiceId);
  const defaultCamera =
    dimMeta.id === "dim2d"
      ? "Camera2D zoom Vector2(2.0, 2.0), position_smoothing_enabled = true, speed 7.0"
      : "SpringArm3D 14.5 m @ -52 deg pitch, 55 deg FOV, Camera3D look-ahead smoothing 9.0";
  const defaultScale =
    dimMeta.id === "dim2d"
      ? "CharacterBody2D CollisionShape2D 32x32 px · base walk speed 240 px/s · tile 32x32 px"
      : "CharacterBody3D CapsuleShape3D radius 0.42 m · height 1.84 m · base walk speed 6.2 m/s";

  return {
    gameTitle: normalizedTitle,
    normalizedTitle,
    dimension: dimMeta.id,
    pitch: String(parsed.pitch || projectDoc?.sections?.goal || "").trim(),
    coreLoop: normalizeStringArrayJs(parsed.coreLoop),
    cameraContract: String(parsed.cameraContract || defaultCamera).trim(),
    characterScale: String(parsed.characterScale || defaultScale).trim(),
    inputContract: String(
      parsed.inputContract ||
        "InputMap (move_left/move_right/move_up/move_down, primary_action, secondary_action, ui_cancel)"
    ).trim(),
    assetPolicy: String(
      parsed.assetPolicy ||
        (dimMeta.id === "dim2d"
          ? "Prototype ColorRect/Polygon2D/Line2D geometry + Resource (.tres) config + typed GDScript 2.0"
          : "Prototype CSGBox3D/CSGCylinder3D greybox geometry + StandardMaterial3D + Resource (.tres) + typed GDScript 2.0")
    ).trim(),
    feelChoiceId: coreFeel.id,
    coreFeelLabel: coreFeel.label,
    pillars: normalizeStringArrayJs(parsed.pillars),
    tradeOffs: Array.isArray(parsed.tradeOffs)
      ? parsed.tradeOffs.map(formatTradeOffJs).filter(Boolean)
      : [],
    outOfScope: normalizeStringArrayJs(parsed.outOfScope),
    releaseDoneWhen: String(parsed.releaseDoneWhen || "").trim(),
  };
}

function parseVersionTupleJs(rawVer) {
  const clean = String(rawVer || "").trim().toLowerCase().replace(/^v/, "");
  if (!clean) return [0, 0];
  return clean.split(".").map((p) => Number.parseInt(p, 10) || 0);
}

function compareReleaseVersionsJs(a, b, releaseOrder = []) {
  const va = String(a || "").trim().toLowerCase();
  const vb = String(b || "").trim().toLowerCase();
  if (va === vb) return 0;
  if (Array.isArray(releaseOrder) && releaseOrder.length > 0) {
    const normOrder = releaseOrder.map((r) => String(r || "").trim().toLowerCase());
    const ia = normOrder.indexOf(va);
    const ib = normOrder.indexOf(vb);
    if (ia >= 0 && ib >= 0) return ia - ib;
  }
  const pa = parseVersionTupleJs(va);
  const pb = parseVersionTupleJs(vb);
  const maxLen = Math.max(pa.length, pb.length);
  for (let i = 0; i < maxLen; i += 1) {
    const da = i < pa.length ? pa[i] : 0;
    const db = i < pb.length ? pb[i] : 0;
    if (da !== db) return da - db;
  }
  return va.localeCompare(vb);
}

function isFeatureLockedBaselineJs(feature, targetReleaseVersion, releaseOrder = []) {
  const target = String(targetReleaseVersion || "").trim();
  if (!target || !feature) return false;
  return (
    compareReleaseVersionsJs(feature.introducedIn || "v0.1", target, releaseOrder) < 0 &&
    !String(feature.releaseDelta || "").trim()
  );
}

function getEffectiveChecksForReleaseJs(feature, releaseVersion) {
  const rel = String(releaseVersion || "v0.1").trim() || "v0.1";
  const checks = Array.isArray(feature?.checks) ? feature.checks : [];
  const deltaChecks = Array.isArray(feature?.releaseDeltaChecks)
    ? feature.releaseDeltaChecks
    : [];
  if (rel !== "v0.1" && deltaChecks.length > 0) {
    return [...checks, ...deltaChecks];
  }
  return checks;
}

function computeFeaturePassedJs(feature) {
  if (!feature) return false;
  if (String(feature.status || "").trim().toLowerCase() !== "passed") {
    return false;
  }
  const fixes = Array.isArray(feature.fixes) ? feature.fixes : [];
  return fixes.every((f) => Boolean(f?.resolved));
}

function isFeaturePassedForReleaseJs(feature, releaseVersion, releaseOrder = []) {
  return (
    isFeatureLockedBaselineJs(feature, releaseVersion, releaseOrder) ||
    computeFeaturePassedJs(feature)
  );
}

function getVisibleFeaturesForReleaseJs(epicSpec, releaseVersion, releaseOrder = []) {
  const features = Array.isArray(epicSpec?.features) ? epicSpec.features : [];
  const target = String(releaseVersion || epicSpec?.releaseVersion || "v0.1").trim() || "v0.1";
  return features.filter(
    (f) => compareReleaseVersionsJs(f.introducedIn || "v0.1", target, releaseOrder) <= 0
  );
}

function extractLegacySceneOwnershipJs(links = [], levelStaging = "") {
  const seen = new Set();
  const out = [];
  const resRx = /res:\/\/[^\s,)\];"]+/g;
  const scan = (src, fallbackRole) => {
    const trimmed = String(src || "").trim();
    if (!trimmed) return;
    const matches = trimmed.match(resRx) || [];
    for (const rawPath of matches) {
      const p = normalizeResPathJs(rawPath);
      if (!p || seen.has(p)) continue;
      seen.add(p);
      let role = fallbackRole;
      const split = trimmed.split(/\s+[—-]\s+/);
      if (split.length > 1 && split[0].includes(rawPath)) {
        role = split.slice(1).join(" - ").trim() || fallbackRole;
      }
      out.push({ path: p, role });
    }
  };
  for (const link of links) scan(link, "Shared scene or script");
  scan(levelStaging, "Playtest room scene");
  return out;
}

function parseFeatureSpecJs(raw, indexHint = 0, dimension = "dim3d", fallbackRelease = "v0.1") {
  const obj = raw && typeof raw === "object" ? raw : {};
  const fallbackCode = `F${String(indexHint + 1).padStart(2, "0")}`;
  const code = String(obj.code || fallbackCode).trim() || fallbackCode;
  const statusRaw = String(obj.status || "queued").trim().toLowerCase();
  let status = "queued";
  if (statusRaw === "passed" || statusRaw === "stable" || statusRaw === "done") {
    status = "passed";
  } else if (statusRaw === "active" || statusRaw === "in_progress" || statusRaw === "inprogress") {
    status = "active";
  }

  const parseCheckList = (rawArr, idPrefix) =>
    Array.isArray(rawArr)
      ? rawArr
          .map((item, idx) => {
            if (item && typeof item === "object") {
              return {
                id: String(item.id || `${idPrefix}_${idx + 1}`),
                text: String(item.text || "").trim(),
                passed: Boolean(item.passed ?? item.completed),
              };
            }
            const txt = String(item || "").trim();
            return txt ? { id: `${idPrefix}_${idx + 1}`, text: txt, passed: false } : null;
          })
          .filter((c) => c && c.text)
      : [];

  const controls = Array.isArray(obj.controls)
    ? obj.controls
        .filter((c) => c && typeof c === "object")
        .map((c) => ({
          action: String(c.action || "primary_action").trim(),
          trigger: String(c.trigger || "Just Pressed (Space)").trim(),
          rule: String(c.rule || "").trim(),
        }))
    : [];

  const tuning = Array.isArray(obj.tuning)
    ? obj.tuning
        .filter((t) => t && typeof t === "object")
        .map((t) => {
          const cleanKey = sanitizeGodotTuningKeyJs(t.key, "tuning_param");
          return {
            key: cleanKey,
            value: scaleGodotTuningValueJs(t.value ?? "0", t.unit, dimension),
            unit: normalizeGodotUnitJs(cleanKey, t.unit, dimension),
          };
        })
    : [];

  const rawFixes = Array.isArray(obj.fixes) ? obj.fixes : [];
  const fixes = rawFixes
    .map((item, idx) => {
      if (item && typeof item === "object") {
        return {
          id: String(item.id || `ffix_${idx + 1}`),
          text: String(item.text || "").trim(),
          resolved: Boolean(item.resolved),
          createdAtMs: Number(item.createdAtMs || 0) || 0,
        };
      }
      const txt = String(item || "").trim();
      return txt ? { id: `ffix_${idx + 1}`, text: txt, resolved: false, createdAtMs: 0 } : null;
    })
    .filter((f) => f && f.text);

  const checks = parseCheckList(obj.checks, "fchk");
  const releaseDeltaChecks = parseCheckList(
    obj.releaseDeltaChecks || obj.v02Checks,
    "fdchk"
  );

  const feat = {
    id: String(obj.id || `feat_${indexHint + 1}`).trim() || `feat_${indexHint + 1}`,
    code,
    title: String(obj.title || "Untitled Feature").trim(),
    introducedIn: String(obj.introducedIn || fallbackRelease || "v0.1").trim() || "v0.1",
    sliceTime: String(obj.sliceTime || "45 min").trim() || "45 min",
    status,
    goal: String(obj.goal || "").trim(),
    inScope: normalizeStringArrayJs(obj.inScope),
    doneWhen: normalizeStringArrayJs(obj.doneWhen),
    releaseDelta: String(obj.releaseDelta || obj.v02Delta || "").trim(),
    controls,
    tuning,
    cues: normalizeStringArrayJs(obj.cues || obj.feedback),
    checks,
    releaseDeltaChecks,
    fixes,
  };
  feat.openFixes = feat.fixes.filter((f) => !f.resolved);
  feat.openFixesCount = feat.openFixes.length;
  feat.passedChecksCount = feat.checks.filter((c) => c.passed).length;
  feat.isPassed = computeFeaturePassedJs(feat);
  return feat;
}

function computeEpicPassedJs(spec) {
  if (!spec) return false;
  const fixes = Array.isArray(spec.fixes) ? spec.fixes : [];
  if (fixes.some((f) => !f?.resolved)) return false;
  const features = Array.isArray(spec.features) ? spec.features : [];
  if (features.some((ft) => Array.isArray(ft?.fixes) && ft.fixes.some((fx) => !fx?.resolved))) {
    return false;
  }
  const checks = Array.isArray(spec.checks) ? spec.checks : [];
  if (String(spec.lifecycle || "").toLowerCase() === "stable") {
    return checks.length === 0 || checks.every((c) => Boolean(c?.passed));
  }
  if (features.length > 0) {
    return features.every((ft) => computeFeaturePassedJs(ft));
  }
  return false;
}

function parseEpicSpecJs(epicDoc, indexHint = 0, dimension = "dim3d") {
  const sec =
    epicDoc?.sections && typeof epicDoc.sections === "object"
      ? epicDoc.sections
      : {};
  const parsed = parseJsonObjectSafe(sec.epic_spec_json) || {};
  const fallbackCode = `E${String(indexHint + 1).padStart(2, "0")}`;
  const code =
    String(sec.code || parsed.code || fallbackCode).trim() || fallbackCode;
  const lineageKey = String(
    sec.lineage_key || parsed.lineageKey || code.toLowerCase()
  ).trim();
  const releaseVersion = String(
    sec.release_version || parsed.releaseVersion || "v0.1"
  ).trim();
  const lifecycle = String(
    sec.lifecycle || parsed.lifecycle || (epicDoc?.isCompleted ? "stable" : "queued")
  ).trim();

  const rawChecks =
    Array.isArray(parsed.checks) && parsed.checks.length > 0
      ? parsed.checks
      : Array.isArray(epicDoc?.subtasks)
        ? epicDoc.subtasks
        : [];
  const checks = rawChecks
    .map((item, idx) => {
      if (item && typeof item === "object") {
        return {
          id: String(item.id || `chk_${idx + 1}`),
          text: String(item.text || "").trim(),
          passed: Boolean(item.passed ?? item.completed),
        };
      }
      const txt = String(item || "").trim();
      return txt ? { id: `chk_${idx + 1}`, text: txt, passed: false } : null;
    })
    .filter((c) => c && c.text);

  const rawFixes = Array.isArray(parsed.fixes) ? parsed.fixes : [];
  const fixes = rawFixes
    .map((item, idx) => {
      if (item && typeof item === "object") {
        return {
          id: String(item.id || `fix_${idx + 1}`),
          text: String(item.text || "").trim(),
          resolved: Boolean(item.resolved),
          createdAtMs: Number(item.createdAtMs || 0) || 0,
        };
      }
      const txt = String(item || "").trim();
      return txt
        ? { id: `fix_${idx + 1}`, text: txt, resolved: false, createdAtMs: 0 }
        : null;
    })
    .filter((f) => f && f.text);

  const controls = Array.isArray(parsed.controls)
    ? parsed.controls
        .filter((c) => c && typeof c === "object")
        .map((c) => ({
          action: String(c.action || "primary_action").trim(),
          trigger: String(c.trigger || "Just Pressed (Space)").trim(),
          rule: String(c.rule || "").trim(),
        }))
    : [];

  const tuning = Array.isArray(parsed.tuning)
    ? parsed.tuning
        .filter((t) => t && typeof t === "object")
        .map((t) => {
          const cleanKey = sanitizeGodotTuningKeyJs(t.key, "tuning_param");
          return {
            key: cleanKey,
            value: scaleGodotTuningValueJs(t.value ?? "0", t.unit, dimension),
            unit: normalizeGodotUnitJs(cleanKey, t.unit, dimension),
          };
        })
    : [];

  const links = normalizeStringArrayJs(parsed.links || parsed.plugsInto);
  const levelStaging = String(parsed.levelStaging || "").trim();
  const rawOwnership = Array.isArray(parsed.sceneOwnership) ? parsed.sceneOwnership : [];
  const sceneOwnership =
    rawOwnership.length > 0
      ? rawOwnership
          .map((item) => {
            if (item && typeof item === "object") {
              const p = normalizeResPathJs(item.path || "");
              return p ? { path: p, role: String(item.role || "").trim() } : null;
            }
            const rawStr = String(item || "").trim();
            if (!rawStr) return null;
            const split = rawStr.split(/\s+[—-]\s+/);
            const p = normalizeResPathJs(split[0]);
            return p
              ? {
                  path: p,
                  role: split.length > 1 ? split.slice(1).join(" - ").trim() : "",
                }
              : null;
          })
          .filter(Boolean)
      : extractLegacySceneOwnershipJs(links, levelStaging);

  const states = normalizeStringArrayJs(parsed.states);
  const interrupts = normalizeStringArrayJs(parsed.interrupts);
  const stateFlow = normalizeStringArrayJs(parsed.stateFlow || parsed.states);
  const interruptRules = normalizeStringArrayJs(parsed.interruptRules || parsed.interrupts);
  const inScope = normalizeStringArrayJs(parsed.inScope);
  const doneWhen = normalizeStringArrayJs(parsed.doneWhen);
  const feedback = normalizeStringArrayJs(parsed.feedback);
  const goalText = String(parsed.goal || sec.goal || "").trim();
  const epicTitle = String(epicDoc?.title || parsed.title || "Untitled System").trim();
  const epicId = String(epicDoc?.id || parsed.id || `epic_${indexHint + 1}`);
  const upgradeDeltas = normalizeStringArrayJs(parsed.upgradeDeltas);

  let synthesizedLegacyFeatures = false;
  let features = [];
  if (Array.isArray(parsed.features)) {
    features = parsed.features
      .filter((f) => f && typeof f === "object")
      .map((f, idx) =>
        parseFeatureSpecJs(f, idx, dimension, releaseVersion || "v0.1")
      );
  } else if (
    controls.length > 0 ||
    tuning.length > 0 ||
    checks.length > 0 ||
    fixes.length > 0 ||
    feedback.length > 0
  ) {
    synthesizedLegacyFeatures = true;
    const hasOpenFixes = fixes.some((f) => !f.resolved);
    let migratedStatus = "queued";
    if (lifecycle === "stable" && !hasOpenFixes) {
      migratedStatus = "passed";
    } else if (lifecycle === "active" || hasOpenFixes || checks.some((c) => c.passed)) {
      migratedStatus = "active";
    }
    const f01 = {
      id: `${epicId}_f01`,
      code: "F01",
      title: epicTitle,
      introducedIn: releaseVersion || "v0.1",
      sliceTime: "60 min",
      status: migratedStatus,
      goal: goalText,
      inScope: [...inScope],
      doneWhen: [...doneWhen],
      releaseDelta: upgradeDeltas.join(" ; "),
      controls: controls.map((c) => ({ ...c })),
      tuning: tuning.map((t) => ({ ...t })),
      cues: [...feedback],
      checks: checks.map((c) => ({ ...c })),
      releaseDeltaChecks: [],
      fixes: fixes.map((f) => ({ ...f })),
    };
    f01.openFixes = f01.fixes.filter((f) => !f.resolved);
    f01.openFixesCount = f01.openFixes.length;
    f01.passedChecksCount = f01.checks.filter((c) => c.passed).length;
    f01.isPassed = computeFeaturePassedJs(f01);
    features = [f01];
  }

  const spec = {
    id: epicId,
    code,
    lineageKey,
    title: epicTitle,
    releaseVersion,
    lifecycle,
    coreLoopBeat: String(parsed.coreLoopBeat || "").trim(),
    goal: goalText,
    inScope,
    doneWhen,
    sceneOwnership,
    links,
    outOfScope: normalizeStringArrayJs(parsed.outOfScope),
    controls,
    states,
    interrupts,
    stateFlow,
    interruptRules,
    tuning,
    feedback,
    levelStaging,
    checks,
    fixes,
    features,
    baselineSummary: normalizeStringArrayJs(parsed.baselineSummary),
    upgradeDeltas,
    copilotUpgrades: Array.isArray(parsed.copilotUpgrades)
      ? parsed.copilotUpgrades
      : [],
    chosen: Boolean(parsed.chosen),
  };
  if (synthesizedLegacyFeatures) {
    spec._synthesizedLegacyFeatures = true;
  }

  spec.openFixes = spec.fixes.filter((f) => !f.resolved);
  spec.openFixesCount = spec.openFixes.length;
  spec.passedChecksCount = spec.checks.filter((c) => c.passed).length;
  spec.isPassed = computeEpicPassedJs(spec);
  return spec;
}

function renderServerGodotEpicContextJs({
  rootSpec,
  epicSpec,
  releaseEpics = null,
  liveGodotContext = null,
  includeRootContext = true,
  includeExecutionFooter = true,
}) {
  const dimMeta = resolveDimensionMetaJs(rootSpec?.dimension);
  const openFixes = Array.isArray(epicSpec.openFixes)
    ? epicSpec.openFixes
    : (epicSpec.fixes || []).filter((f) => !f.resolved);

  const lines = [];

  if (includeRootContext) {
    lines.push(`# ROOT_GODOT_CONTEXT · ${rootSpec.normalizedTitle}`);
    lines.push(`Target Architecture: ${dimMeta.architectureContract}`);
    lines.push(`Code Policy: ${dimMeta.codePolicyContract}`);
    lines.push("");
    lines.push("## §01 Concept & 30s Core Loop");
    lines.push(`- Vision: ${String(rootSpec.pitch || "").trim()}`);
    if (Array.isArray(rootSpec.coreLoop) && rootSpec.coreLoop.length > 0) {
      lines.push(`- Loop: ${rootSpec.coreLoop.join(" -> ")}`);
    }
    if (rootSpec.releaseDoneWhen && String(rootSpec.releaseDoneWhen).trim()) {
      lines.push(`- Release Gate: ${String(rootSpec.releaseDoneWhen).trim()}`);
    }
    lines.push("");
    lines.push(`## §02 Global Godot 4 Contracts (${dimMeta.pillLabel})`);
    lines.push(`- Camera Rig: ${String(rootSpec.cameraContract || "").trim()}`);
    lines.push(`- Player Scale: ${String(rootSpec.characterScale || "").trim()}`);
    lines.push(`- Input Contract: ${String(rootSpec.inputContract || "").trim()}`);
    lines.push(`- Asset Policy: ${String(rootSpec.assetPolicy || "").trim()}`);
    lines.push("");
    lines.push("## §03 Pillars & Conflict Trade-Offs");
    lines.push(`- Core Feel: ${rootSpec.coreFeelLabel || "Snappy Arcade"}`);
    for (const pillar of rootSpec.pillars || []) {
      lines.push(`- Pillar: ${pillar}`);
    }
    for (const tradeOff of rootSpec.tradeOffs || []) {
      lines.push(`- Trade-Off: ${tradeOff}`);
    }
    if (Array.isArray(rootSpec.outOfScope) && rootSpec.outOfScope.length > 0) {
      lines.push("");
      lines.push("## §04 Hard Scope Cuts (Do Not Build)");
      for (const cut of rootSpec.outOfScope) {
        lines.push(`- ${cut}`);
      }
    }

    if (
      liveGodotContext &&
      typeof liveGodotContext === "object" &&
      Object.keys(liveGodotContext).length > 0
    ) {
      const snapshotLines = [];
      const projName = String(liveGodotContext.project_name || "").trim();
      const mainScene = String(liveGodotContext.main_scene || "").trim();
      if (projName) snapshotLines.push(`- Project: ${projName}`);
      if (mainScene) snapshotLines.push(`- Main Scene: ${mainScene}`);
      const pushSnapshotList = (label, rawList, cap) => {
        if (!Array.isArray(rawList) || rawList.length === 0) return;
        const clean = rawList
          .map((item) => String(item ?? "").trim())
          .filter(Boolean)
          .slice(0, cap);
        if (clean.length === 0) return;
        snapshotLines.push(`- ${label}: ${clean.join(", ")}`);
      };
      pushSnapshotList("Existing InputMap Actions", liveGodotContext.input_actions, 16);
      pushSnapshotList("Existing Scenes (.tscn)", liveGodotContext.scene_files, 12);
      pushSnapshotList("Existing Scripts (.gd)", liveGodotContext.script_files, 14);
      pushSnapshotList("Existing Resources (.tres)", liveGodotContext.resource_files, 8);
      if (
        Array.isArray(liveGodotContext.recent_errors) &&
        liveGodotContext.recent_errors.length > 0
      ) {
        const cleanErrors = liveGodotContext.recent_errors
          .map((err) => String(err ?? "").trim())
          .filter(Boolean)
          .slice(0, 4);
        if (cleanErrors.length > 0) {
          snapshotLines.push("- Recent Editor/Debugger Errors:");
          for (const err of cleanErrors) {
            snapshotLines.push(`  - ${err}`);
          }
        }
      }
      if (snapshotLines.length > 0) {
        lines.push("");
        lines.push("## Live Godot Project Snapshot (project.godot via Dock)");
        lines.push(...snapshotLines);
      }
    }

    if (Array.isArray(releaseEpics) && releaseEpics.length >= 2) {
      const passedCount = releaseEpics.filter((sib) =>
        typeof sib?.isPassed === "boolean"
          ? sib.isPassed
          : computeEpicPassedJs(sib)
      ).length;
      lines.push("");
      lines.push(
        `## Release Epic Roadmap (${epicSpec.releaseVersion} · ${passedCount}/${releaseEpics.length} Passed)`
      );
      for (const sib of releaseEpics) {
        const isCurrent =
          (epicSpec.id && sib.id === epicSpec.id) ||
          (!epicSpec.id && sib.code === epicSpec.code);
        const sibPassed =
          typeof sib?.isPassed === "boolean"
            ? sib.isPassed
            : computeEpicPassedJs(sib);
        if (isCurrent) {
          lines.push(
            `- [ACTIVE →] ${sib.code} · ${sib.title} — build in this pass`
          );
        } else if (sibPassed) {
          const seenContracts = new Set();
          const contracts = [];
          const addContract = (raw) => {
            const clean = String(raw || "").trim();
            if (!clean || contracts.length >= 3) return;
            const key = clean.toLowerCase();
            if (!seenContracts.has(key)) {
              seenContracts.add(key);
              contracts.push(clean);
            }
          };
          for (const own of (Array.isArray(sib.sceneOwnership) ? sib.sceneOwnership : []).slice(0, 2)) {
            addContract(own?.path);
          }
          for (const link of (Array.isArray(sib.links) ? sib.links : []).slice(0, 2)) {
            addContract(link);
          }
          for (const feat of Array.isArray(sib.features) ? sib.features : []) {
            for (const ctrl of (Array.isArray(feat?.controls) ? feat.controls : []).slice(0, 1)) {
              addContract(ctrl?.action);
            }
          }
          for (const ctrl of (Array.isArray(sib.controls) ? sib.controls : []).slice(0, 2)) {
            addContract(ctrl?.action);
          }
          if (contracts.length > 0) {
            lines.push(
              `- [BUILT ✓] ${sib.code} · ${sib.title} — preserve & reuse (${contracts.join(", ")})`
            );
          } else {
            lines.push(
              `- [BUILT ✓] ${sib.code} · ${sib.title} — preserve & reuse existing scenes/scripts`
            );
          }
        } else {
          lines.push(
            `- [QUEUED — DEFER] ${sib.code} · ${sib.title} — do not build yet; stub signals only if needed`
          );
        }
      }
    }

    lines.push("");
    lines.push("---");
    lines.push("");
  }

  lines.push(
    `# ACTIVE EPIC SPEC · ${epicSpec.code} · ${epicSpec.title} (${epicSpec.releaseVersion})`
  );
  if (openFixes.length > 0) {
    lines.push(
      `Execution Mode: FOCUSED PLAYTEST REVISION PASS (${openFixes.length} OPEN [FIX]) — surgical edits only; keep passing checks intact`
    );
  } else if (includeExecutionFooter) {
    lines.push("Execution Mode: FULL-EPIC AUTONOMOUS BUILD & SELF-CHECK");
  }
  lines.push("");
  lines.push("## §01 System Intent & Scene Links");
  if (epicSpec.coreLoopBeat && String(epicSpec.coreLoopBeat).trim()) {
    lines.push(`- Core Loop Beat: ${String(epicSpec.coreLoopBeat).trim()}`);
  }
  lines.push(`- Goal: ${String(epicSpec.goal || "").trim()}`);
  if (Array.isArray(epicSpec.links) && epicSpec.links.length > 0) {
    lines.push(`- Links: ${epicSpec.links.join(" · ")}`);
  }
  if (Array.isArray(epicSpec.outOfScope) && epicSpec.outOfScope.length > 0) {
    lines.push(`- Out of Scope: ${epicSpec.outOfScope.join("; ")}`);
  }
  if (
    Array.isArray(epicSpec.baselineSummary) &&
    epicSpec.baselineSummary.length > 0 &&
    (epicSpec.releaseVersion !== "v0.1" ||
      (Array.isArray(epicSpec.upgradeDeltas) && epicSpec.upgradeDeltas.length > 0))
  ) {
    lines.push(`- Locked Baseline: ${epicSpec.baselineSummary.join(" · ")}`);
  }

  if (Array.isArray(epicSpec.upgradeDeltas) && epicSpec.upgradeDeltas.length > 0) {
    lines.push("");
    lines.push(
      `## ${epicSpec.releaseVersion} Upgrade Deltas (atop locked v0.1 baseline)`
    );
    for (const delta of epicSpec.upgradeDeltas) {
      const cleanDelta = String(delta || "").trim().replace(/^\+\s*/, "");
      if (cleanDelta) lines.push(`- +${cleanDelta}`);
    }
  }

  lines.push("");
  lines.push(`## §02 Controls (${dimMeta.inputContractLabel})`);
  if (!Array.isArray(epicSpec.controls) || epicSpec.controls.length === 0) {
    lines.push("- None (passive/system-driven Epic)");
  } else {
    for (const c of epicSpec.controls) {
      lines.push(`- ${c.action} | ${c.trigger} | ${c.rule}`);
    }
  }

  lines.push("");
  lines.push("## §03 State Flow & Interrupt Rules");
  if (
    (!Array.isArray(epicSpec.states) || epicSpec.states.length === 0) &&
    (!Array.isArray(epicSpec.interrupts) || epicSpec.interrupts.length === 0)
  ) {
    lines.push("- Stateless / signal-driven Epic");
  } else {
    for (const s of epicSpec.states || []) {
      lines.push(`- State: ${s}`);
    }
    for (const rule of epicSpec.interrupts || []) {
      lines.push(`- Interrupt: ${rule}`);
    }
  }

  lines.push("");
  lines.push(`## §04 Spatial & Exposed Tuning (${dimMeta.tuningColumnLabel})`);
  if (!Array.isArray(epicSpec.tuning) || epicSpec.tuning.length === 0) {
    lines.push("- None");
  } else {
    for (const t of epicSpec.tuning) {
      const trimmedUnit = String(t.unit || "").trim();
      const unitSuffix = trimmedUnit ? ` ${trimmedUnit}` : "";
      const propType = inferGodotPropertyTypeJs(t.value, trimmedUnit);
      lines.push(`- ${t.key}: ${t.value}${unitSuffix} [${propType}]`);
    }
  }

  lines.push("");
  lines.push("## §05 Viewport, UI & Audio Cues");
  if (!Array.isArray(epicSpec.feedback) || epicSpec.feedback.length === 0) {
    lines.push("- Minimal greybox debug visuals");
  } else {
    for (const f of epicSpec.feedback) {
      lines.push(`- ${f}`);
    }
  }

  lines.push("");
  lines.push("## §06 Test Scene Staging & Playtest Acceptance Gate");
  if (epicSpec.levelStaging && String(epicSpec.levelStaging).trim()) {
    lines.push(`- Test Scene: ${String(epicSpec.levelStaging).trim()}`);
  }
  (epicSpec.checks || []).forEach((chk, i) => {
    const tag = chk.passed ? "[PASSED]" : "[VERIFY]";
    lines.push(`  ${tag} Check ${i + 1}: ${chk.text}`);
  });

  if (openFixes.length > 0) {
    lines.push("");
    lines.push("## Open Playtest Revisions ([FIX])");
    for (const fx of openFixes) {
      const fxId = String(fx.id || "").trim();
      const idTag = fxId ? ` (id: ${fxId})` : "";
      lines.push(`- [FIX] ${fx.text}${idTag}`);
    }
    lines.push("");
    lines.push(
      `### FOCUSED PLAYTEST REVISION PASS (${openFixes.length} OPEN [FIX])`
    );
    lines.push(
      `Targeted edits only to resolve every open [FIX] item above; keep already-passing checks intact, emit compile-clean Godot 4 .gd/.tscn/${dimMeta.shortLabel} updates, and leave final pass sign-off to human playtest.`
    );
  } else if (includeExecutionFooter) {
    lines.push("");
    lines.push("### FULL-EPIC AUTONOMOUS BUILD & SELF-CHECK");
    lines.push(
      `Synthesize §01-§06 cleanly into Godot 4 (${dimMeta.shortLabel}: .gd scripts + .tscn sceneOps + project.godot inputOps) matching ROOT_GODOT_CONTEXT contracts, expose every §04 @export variable in snake_case, and ensure zero GDScript compile errors.`
    );
  }

  return lines.join("\n").trimRight();
}

function renderServerGodotFeatureContextJs({
  rootSpec,
  epicSpec,
  featureSpec,
  releaseVersion = "v0.1",
  siblingFeaturesSummary = [],
  liveGodotContext = null,
}) {
  const dimMeta = resolveDimensionMetaJs(rootSpec?.dimension);
  const ver =
    String(releaseVersion || featureSpec?.introducedIn || epicSpec?.releaseVersion || "v0.1").trim() ||
    "v0.1";
  const openFixes = Array.isArray(featureSpec?.openFixes)
    ? featureSpec.openFixes
    : (featureSpec?.fixes || []).filter((f) => !f?.resolved);
  const effChecks = getEffectiveChecksForReleaseJs(featureSpec, ver);

  const rootHeader = renderServerGodotEpicContextJs({
    rootSpec,
    epicSpec,
    liveGodotContext,
    includeRootContext: true,
    includeExecutionFooter: false,
  }).split("\n---\n")[0];

  const lines = [rootHeader.trimRight(), "", "---", ""];

  lines.push(`## 2. Parent Epic Architecture (${epicSpec.code} · ${epicSpec.title})`);
  lines.push(`- Domain Goal: ${String(epicSpec.goal || "").trim()}`);
  if (Array.isArray(epicSpec.inScope) && epicSpec.inScope.length > 0) {
    lines.push("- Domain In Scope:");
    for (const s of epicSpec.inScope) lines.push(`  - ${s}`);
  }
  if (Array.isArray(epicSpec.doneWhen) && epicSpec.doneWhen.length > 0) {
    lines.push("- Domain Done When:");
    for (const d of epicSpec.doneWhen) lines.push(`  - ${d}`);
  }
  const ownership = Array.isArray(epicSpec.sceneOwnership) ? epicSpec.sceneOwnership : [];
  if (ownership.length > 0) {
    lines.push("- Shared Scene & Script Ownership:");
    for (const own of ownership) {
      const roleSuffix = own.role ? ` — ${own.role}` : "";
      lines.push(`  - ${own.path}${roleSuffix}`);
    }
  }
  const sFlow = Array.isArray(epicSpec.stateFlow) && epicSpec.stateFlow.length > 0
    ? epicSpec.stateFlow
    : epicSpec.states || [];
  const iRules = Array.isArray(epicSpec.interruptRules) && epicSpec.interruptRules.length > 0
    ? epicSpec.interruptRules
    : epicSpec.interrupts || [];
  if (sFlow.length > 0) {
    lines.push(`- State Flow: ${sFlow.join(" -> ")}`);
  }
  for (const r of iRules) {
    lines.push(`- Interrupt Rule: ${r}`);
  }
  if (Array.isArray(epicSpec.outOfScope) && epicSpec.outOfScope.length > 0) {
    lines.push(`- Domain Out of Scope: ${epicSpec.outOfScope.join("; ")}`);
  }

  lines.push("");
  lines.push("---");
  lines.push("");
  lines.push(
    `# ACTIVE FEATURE SPEC · ${featureSpec.code} · ${featureSpec.title} (${ver} · ${featureSpec.sliceTime || "45 min"})`
  );
  lines.push(`Dimension Contract: ${dimMeta.pillLabel} (${dimMeta.shortLabel})`);
  if (openFixes.length > 0) {
    lines.push(
      `Execution Mode: FOCUSED [FIX] PASS (${openFixes.length} OPEN [FIX]) — surgical edits only; keep passing sibling checks intact`
    );
  } else {
    lines.push("Execution Mode: FULL FEATURE BUILD");
  }

  if (ver !== "v0.1" && String(featureSpec.releaseDelta || "").trim()) {
    const cleanDelta = String(featureSpec.releaseDelta).trim().replace(/^\+\s*/, "");
    lines.push("");
    lines.push(`## ${ver} Upgrade Delta`);
    lines.push(`- +${cleanDelta}`);
  }

  lines.push("");
  lines.push("## §01 Feature Scope");
  lines.push(`- Goal: ${String(featureSpec.goal || "").trim()}`);
  if (Array.isArray(featureSpec.inScope) && featureSpec.inScope.length > 0) {
    lines.push("- In Scope:");
    for (const item of featureSpec.inScope) lines.push(`  - ${item}`);
  }
  if (Array.isArray(featureSpec.doneWhen) && featureSpec.doneWhen.length > 0) {
    lines.push("- Done When:");
    for (const item of featureSpec.doneWhen) lines.push(`  - ${item}`);
  }

  lines.push("");
  lines.push(`## §02 Input Actions (${dimMeta.inputContractLabel})`);
  if (!Array.isArray(featureSpec.controls) || featureSpec.controls.length === 0) {
    lines.push("- None (signal/system-driven slice)");
  } else {
    lines.push("| InputMap Action | Binding | Trigger Rule |");
    lines.push("| --- | --- | --- |");
    for (const c of featureSpec.controls) {
      lines.push(`| ${c.action} | ${c.trigger} | ${c.rule} |`);
    }
  }

  lines.push("");
  lines.push(`## §03 Exposed Tuning (${dimMeta.tuningColumnLabel})`);
  if (!Array.isArray(featureSpec.tuning) || featureSpec.tuning.length === 0) {
    lines.push("- None");
  } else {
    lines.push("```gdscript");
    for (const t of featureSpec.tuning) {
      const propType = inferGodotPropertyTypeJs(t.value, t.unit);
      const unitComment = String(t.unit || "").trim() ? ` # ${String(t.unit).trim()}` : "";
      lines.push(`@export var ${t.key}: ${propType} = ${t.value}${unitComment}`);
    }
    lines.push("```");
  }

  lines.push("");
  lines.push("## §04 Viewport, UI & Audio Cues");
  if (!Array.isArray(featureSpec.cues) || featureSpec.cues.length === 0) {
    lines.push("- Minimal greybox debug visuals");
  } else {
    for (const cue of featureSpec.cues) lines.push(`- ${cue}`);
  }

  lines.push("");
  lines.push("## §05 Playtest Gate");
  if (effChecks.length === 0) {
    lines.push("- [ ] Confirm observable player response inside Godot Playtest");
  } else {
    for (const chk of effChecks) {
      lines.push(`- [${chk.passed ? "x" : " "}] ${chk.text}`);
    }
  }

  if (openFixes.length > 0) {
    lines.push("");
    lines.push("## Open Playtest Revisions ([FIX])");
    for (const fx of openFixes) {
      const fxId = String(fx.id || "").trim();
      lines.push(`- [FIX] ${fx.text}${fxId ? ` (id: ${fxId})` : ""}`);
    }
  }

  if (Array.isArray(siblingFeaturesSummary) && siblingFeaturesSummary.length > 0) {
    lines.push("");
    lines.push("## Preserve Passing Sibling Features");
    for (const sib of siblingFeaturesSummary) {
      const statusTag = sib.isLockedBaseline
        ? "BASELINE LOCKED ✓"
        : sib.isPassed
          ? "PASSED ✓"
          : String(sib.status || "queued").toUpperCase();
      const parts = [];
      if (Array.isArray(sib.tuningKeys) && sib.tuningKeys.length > 0) {
        parts.push(`@export: ${sib.tuningKeys.join(", ")}`);
      }
      if (Array.isArray(sib.inputActions) && sib.inputActions.length > 0) {
        parts.push(`InputMap: ${sib.inputActions.join(", ")}`);
      }
      if (Array.isArray(sib.checksSummary) && sib.checksSummary.length > 0) {
        parts.push(`Checks: ${sib.checksSummary.join("; ")}`);
      }
      lines.push(
        `- [${statusTag}] ${sib.code} · ${sib.title}${parts.length > 0 ? ` — ${parts.join(" | ")}` : ""}`
      );
    }
  }

  return lines.join("\n").trimRight();
}


module.exports = {
  DEFAULT_WEB_STUDIO_URL,
  ...specGuard,
  parseRootSpecJs,
  parseVersionTupleJs,
  compareReleaseVersionsJs,
  isFeatureLockedBaselineJs,
  getEffectiveChecksForReleaseJs,
  computeFeaturePassedJs,
  isFeaturePassedForReleaseJs,
  getVisibleFeaturesForReleaseJs,
  extractLegacySceneOwnershipJs,
  parseFeatureSpecJs,
  computeEpicPassedJs,
  parseEpicSpecJs,
  renderServerGodotEpicContextJs,
  renderServerGodotFeatureContextJs,
};
