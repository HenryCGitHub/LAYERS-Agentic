const crypto = require("crypto");
const nodemailer = require("nodemailer");
const { onRequest } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const { initializeApp } = require("firebase-admin/app");
const { getAuth } = require("firebase-admin/auth");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");

initializeApp();

const GEMINI_API_KEY = defineSecret("GEMINI_API_KEY");
const GMAIL_APP_PASSWORD = defineSecret("GMAIL_APP_PASSWORD");

// Hard model lock: strictly allow Gemini Flash models only (never Argon / Pro / Imagen / Veo).
const ALLOWED_MODELS = new Set([
  "gemini-4-hydrogen",
  "gemini-3.8-flash",
  "gemini-flash-latest",
]);

const MAX_BODY_BYTES = 512 * 1024; // 512 KB payload cap
const ACCESS_CACHE_TTL_MS = 15 * 1000;
const accessCache = new Map();
const DEFAULT_WEB_STUDIO_URL = "https://henrycgithub.github.io/LAYERS-Agentic/";
const DEFAULT_SYNC_BASE_URL =
  "https://us-central1-layers-b8a16.cloudfunctions.net/geminiProxy";

function hashLinkToken(rawToken) {
  return crypto
    .createHash("sha256")
    .update(String(rawToken || "").trim())
    .digest("hex");
}

function extractBearerLinkToken(req) {
  const authHeader = String(req.headers.authorization || "");
  if (authHeader.startsWith("Bearer ")) {
    const candidate = authHeader.slice("Bearer ".length).trim();
    if (candidate.startsWith("lyr_") && candidate.length >= 20) {
      return candidate;
    }
  }
  const headerToken = String(req.headers["x-layers-link-token"] || "").trim();
  if (headerToken.startsWith("lyr_") && headerToken.length >= 20) {
    return headerToken;
  }
  return "";
}

async function verifyGodotLinkToken(req) {
  const rawToken = extractBearerLinkToken(req);
  if (!rawToken) {
    return {
      errorStatus: 401,
      errorMessage: "Missing or invalid Godot Project Link Token (lyr_...).",
    };
  }
  const tokenHash = hashLinkToken(rawToken);
  const snap = await getFirestore()
    .collection("godot_links")
    .where("tokenHash", "==", tokenHash)
    .limit(1)
    .get();
  if (snap.empty) {
    return {
      errorStatus: 401,
      errorMessage: "Invalid or expired Godot Project Link Token.",
    };
  }
  const linkDoc = snap.docs[0];
  const data = linkDoc.data() || {};
  if (data.revoked === true || !data.uid || !data.projectId) {
    return {
      errorStatus: 401,
      errorMessage: "This Godot Project Link Token has been revoked.",
    };
  }
  const email = String(data.email || "").trim().toLowerCase();
  if (!email) {
    return {
      errorStatus: 403,
      errorMessage: "Linked account email is missing.",
    };
  }
  if (!isAdminEmail(email)) {
    const status = await getAccessStatusFromDb(email);
    if (status !== "approved") {
      return {
        errorStatus: 403,
        errorMessage: `Invite approval required for ${email}.`,
      };
    }
  }
  return {
    uid: String(data.uid),
    email,
    projectId: String(data.projectId),
    webStudioUrl: String(data.webStudioUrl || DEFAULT_WEB_STUDIO_URL),
    linkRef: linkDoc.ref,
  };
}

function resolveVersionTag(relDoc) {
  const v = String(
    relDoc?.sections?.release_version ||
      relDoc?.sections?.versionTag ||
      relDoc?.sections?.version ||
      ""
  ).trim();
  if (v) return /^v/i.test(v) ? `v${v.slice(1)}` : `v${v}`;
  const m = String(relDoc?.title || "").match(/v?(\d+\.\d+(?:\.\d+)?)/i);
  return m ? `v${m[1]}` : "v0.1";
}

function parseJsonObjectSafe(raw) {
  if (!raw) return null;
  if (typeof raw === "object" && !Array.isArray(raw)) return raw;
  try {
    const parsed = JSON.parse(String(raw));
    return parsed && typeof parsed === "object" && !Array.isArray(parsed)
      ? parsed
      : null;
  } catch (_) {
    return null;
  }
}

function normalizeStringArrayJs(raw) {
  if (!Array.isArray(raw)) return [];
  return raw.map((x) => String(x || "").trim()).filter(Boolean);
}

function formatTradeOffJs(raw) {
  if (raw && typeof raw === "object") {
    const prefer = String(raw.prefer || "Direct arcade response").trim();
    const avoid = String(raw.avoid || "Slow physical inertia").trim();
    return `${prefer} OVER ${avoid}`;
  }
  return String(raw || "").trim();
}

function resolveCoreFeelJs(raw) {
  const clean = String(raw || "").trim().toLowerCase();
  if (clean === "heavy") return { id: "heavy", label: "Heavy Deliberate" };
  if (clean === "physics") return { id: "physics", label: "Physics Momentum" };
  return { id: "snappy", label: "Snappy Arcade" };
}

function resolveDimensionMetaJs(rawDim) {
  const lower = String(rawDim || "").trim().toLowerCase();
  const is2d = lower === "dim2d" || lower === "2d" || lower.includes("2d");
  if (is2d) {
    return {
      id: "dim2d",
      shortLabel: "Godot 4 · 2D",
      pillLabel: "2D (px, px/s)",
      architectureContract:
        "Godot 4 2D (.tscn + GDScript .gd) — CharacterBody2D / Node2D + @export Inspector tuning (px, px/s)",
      codePolicyContract:
        "PURE GODOT 4 GDSCRIPT (.gd + .tscn) — Use typed GDScript 2.0, @export snake_case tuning vars, CharacterBody2D/Area2D/Camera2D, and project.godot InputMap.",
      tuningColumnLabel: "@export GDScript Var",
      inputContractLabel: "InputMap Actions (project.godot)",
      distanceUnit: "px",
      speedUnit: "px/s",
    };
  }
  return {
    id: "dim3d",
    shortLabel: "Godot 4 · 3D",
    pillLabel: "3D (m, m/s)",
    architectureContract:
      "Godot 4 3D (.tscn + GDScript .gd) — CharacterBody3D / Node3D + @export Inspector tuning (1 unit = 1 m)",
    codePolicyContract:
      "PURE GODOT 4 GDSCRIPT (.gd + .tscn) — Use typed GDScript 2.0, @export snake_case tuning vars, CharacterBody3D/Area3D/SpringArm3D/Camera3D, and project.godot InputMap.",
    tuningColumnLabel: "@export GDScript Var",
    inputContractLabel: "InputMap Actions (project.godot)",
    distanceUnit: "m",
    speedUnit: "m/s",
  };
}

function toSnakeCaseTokenJs(raw) {
  const spaced = String(raw || "")
    .replace(/([A-Z]+)([A-Z][a-z])/g, "$1_$2")
    .replace(/([a-z0-9])([A-Z])/g, "$1_$2")
    .replace(/([a-zA-Z])(\d)/g, "$1_$2");
  const tokens = spaced
    .split(/[^A-Za-z0-9]+/)
    .map((t) => t.trim().toLowerCase())
    .filter(Boolean);
  return tokens.length === 0 ? "item" : tokens.join("_");
}

function normalizeResPathJs(rawPath) {
  let clean = String(rawPath || "").trim().replace(/\\/g, "/");
  if (!clean) return "";
  if (clean.startsWith("res://")) {
    clean = clean.slice("res://".length);
  }
  clean = clean.replace(/^\/+/, "").replace(/\/{2,}/g, "/");
  return clean ? `res://${clean}` : "";
}

function stripDiffLinePrefixes(rawCode) {
  return String(rawCode || "")
    .split(/\r?\n/)
    .map((line) => (line.startsWith("+ ") ? line.slice(2) : line))
    .join("\n")
    .trim();
}

function extractResPathsListJs(rawText, extFilter = "") {
  const matches = String(rawText || "").match(/res:\/\/[A-Za-z0-9_./-]+/g) || [];
  const out = [];
  const seen = new Set();
  for (const m of matches) {
    const norm = normalizeResPathJs(m);
    if (!norm) continue;
    if (extFilter && !norm.toLowerCase().endsWith(extFilter)) continue;
    if (!seen.has(norm)) {
      seen.add(norm);
      out.push(norm);
    }
  }
  return out;
}

function sanitizeGodotLineJs(raw, dimension = "dim3d") {
  let out = String(raw || "")
    .trim()
    .replace(/^[-*•]+\s+/, "")
    .trim();
  if (!out) return "";
  const is2d = resolveDimensionMetaJs(dimension).id === "dim2d";
  const bodyClass = is2d ? "CharacterBody2D" : "CharacterBody3D";
  const nodeClass = is2d ? "Node2D" : "Node3D";
  const areaClass = is2d ? "Area2D" : "Area3D";
  const camClass = is2d ? "Camera2D" : "Camera3D";
  const particlesClass = is2d ? "GPUParticles2D" : "GPUParticles3D";
  const springCam = is2d ? "Camera2D" : "SpringArm3D";

  const replacements = [
    [/\bUnreal Engine\b/gi, "Godot 4"],
    [/\bUnreal\b/gi, "Godot 4"],
    [/\bACharacter\b/gi, bodyClass],
    [/\bAPawn\b/gi, bodyClass],
    [/\bAActor\b/gi, nodeClass],
    [/\bGameObjects\b/gi, `${nodeClass}s`],
    [/\bGameObject\b/gi, nodeClass],
    [/\bMonoBehaviour\b/gi, "GDScript Node"],
    [/\bUBoxComponent\b/gi, areaClass],
    [/\bUSpringArmComponent\b/gi, springCam],
    [/\bSpringArm\b/gi, springCam],
    [/\bUCameraComponent\b/gi, camClass],
    [/\bUInputAction\b/gi, "InputMap Action"],
    [/\bEnhanced Input\b/gi, "InputMap"],
    [/\bIMC_[A-Za-z0-9_]+\b/g, "InputMap"],
    [/\bNiagara\b/gi, particlesClass],
    [/\bUMG\b/g, "Control HUD"],
    [/\bPlayerStart\b/gi, "SpawnPoint"],
    [/\bOutput Log\b/gi, "Godot Debugger"],
    [/\bPIE\b/g, "Playtest"],
    [/\bSerializeField\b/gi, "@export"],
    [/\bUCLASS\s*(?:\([^)]*\))?/gi, "PackedScene"],
    [/\bUPROPERTY\s*(?:\([^)]*\))?/gi, "@export"],
    [/\bUFUNCTION\s*(?:\([^)]*\))?/gi, "GDScript Signal"],
    [/\bBlueprint Class\b/gi, "PackedScene"],
    [/\bBlueprints\b/gi, "Scenes/Scripts"],
    [/\bBlueprint\b/gi, "Scene/Script"],
    [/\bPrimaryDataAsset\b/gi, "Resource (.tres)"],
    [/\bUDataAsset\b/gi, "Resource (.tres)"],
    [/\.uasset\b/gi, ".tscn"],
    [/\.uproject\b/gi, "project.godot"],
    [/\.prefab\b/gi, ".tscn"],
    [/\bPrefabs\b/gi, "PackedScenes"],
    [/\bPrefab\b/gi, "PackedScene"],
  ];
  for (const [re, target] of replacements) {
    out = out.replace(re, target);
  }
  out = out.replace(/\bIA_([A-Za-z0-9_]+)\b/g, (_, grp) =>
    toSnakeCaseTokenJs(grp || "action")
  );
  out = out.replace(/\b(?:BP|BPI|WBP|DA)_([A-Za-z0-9_]+)\b/g, (_, grp) =>
    toSnakeCaseTokenJs(grp || "entity")
  );
  out = out.replace(/\bL_([A-Za-z0-9_]+)\b/g, (_, grp) =>
    `${toSnakeCaseTokenJs(grp || "arena")}.tscn`
  );
  out = out.replace(/\b([A-Za-z_][A-Za-z0-9_]*)\.(?:cpp|hpp)\b/gi, (_, grp) =>
    `${toSnakeCaseTokenJs(grp || "script")}.gd`
  );
  return out.replace(/\s{2,}/g, " ").trim();
}

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
          ? "Prototype ColorRect/Polygon2D/CSG2D geometry + Resource (.tres) config + typed GDScript 2.0"
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

function computeEpicPassedJs(spec) {
  if (!spec) return false;
  const checks = Array.isArray(spec.checks) ? spec.checks : [];
  const fixes = Array.isArray(spec.fixes) ? spec.fixes : [];
  const openFixes = fixes.filter((f) => !f?.resolved);
  if (openFixes.length > 0) return false;
  if (String(spec.lifecycle || "").toLowerCase() !== "stable") return false;
  return checks.length === 0 || checks.every((c) => Boolean(c?.passed));
}

function sanitizeGodotTuningKeyJs(rawKey, fallback = "tuning_param") {
  let clean = String(rawKey || "")
    .trim()
    .replace(/^@export\s+var\s+/i, "")
    .replace(/[^A-Za-z0-9_]+/g, "_");
  const boolMatch = clean.match(/^b([A-Z][A-Za-z0-9_]*)$/);
  if (boolMatch) {
    clean = boolMatch[1];
  }
  if (!clean) return fallback;
  const snake = toSnakeCaseTokenJs(clean);
  if (!snake) return fallback;
  return /^[0-9]/.test(snake) ? `param_${snake}` : snake;
}

function normalizeGodotUnitJs(key, rawUnit, dimension = "dim3d") {
  const unit = String(rawUnit || "").trim().toLowerCase();
  const dimMeta = resolveDimensionMetaJs(dimension);
  const speedUnit = dimMeta.speedUnit;
  const distUnit = dimMeta.distanceUnit;
  if (unit) {
    if (
      unit === "cm/s" ||
      unit === "uu/s" ||
      unit === "mps" ||
      unit === "m/s" ||
      unit === "px/s" ||
      unit === "pixels/s"
    ) {
      return speedUnit;
    }
    if (
      unit === "cm" ||
      unit === "uu" ||
      unit === "m" ||
      unit === "meter" ||
      unit === "meters" ||
      unit === "px" ||
      unit === "pixel" ||
      unit === "pixels"
    ) {
      return distUnit;
    }
    if (unit === "degrees" || unit === "degree" || unit === "deg") return "deg";
    if (unit === "sec" || unit === "secs" || unit === "seconds" || unit === "s") {
      return "s";
    }
    if (unit === "pct" || unit === "percent" || unit === "%") return "%";
    if (unit === "boolean" || unit === "bool") return "bool";
    return unit;
  }

  const lowerKey = sanitizeGodotTuningKeyJs(key, "").toLowerCase();
  if (
    lowerKey.includes("speed") ||
    lowerKey.includes("velocity") ||
    lowerKey.includes("accel") ||
    lowerKey.includes("decel")
  ) {
    return speedUnit;
  }
  if (
    lowerKey.includes("distance") ||
    lowerKey.includes("range") ||
    lowerKey.includes("radius") ||
    lowerKey.includes("height") ||
    lowerKey.includes("width") ||
    lowerKey.includes("length") ||
    lowerKey.includes("offset") ||
    lowerKey.includes("reach")
  ) {
    return distUnit;
  }
  if (
    lowerKey.includes("cooldown") ||
    lowerKey.includes("duration") ||
    lowerKey.includes("time") ||
    lowerKey.includes("delay") ||
    lowerKey.includes("interval") ||
    lowerKey.includes("window")
  ) {
    return "s";
  }
  if (
    lowerKey.includes("angle") ||
    lowerKey.includes("pitch") ||
    lowerKey.includes("yaw") ||
    lowerKey.includes("fov") ||
    lowerKey.includes("arc")
  ) {
    return "deg";
  }
  if (
    lowerKey.includes("hp") ||
    lowerKey.includes("health") ||
    lowerKey.includes("damage") ||
    lowerKey.includes("armor") ||
    lowerKey.includes("shield")
  ) {
    return "hp";
  }
  if (
    lowerKey.includes("count") ||
    lowerKey.includes("waves") ||
    lowerKey.includes("charges") ||
    lowerKey.includes("ammo") ||
    lowerKey.includes("max_enemies")
  ) {
    return "count";
  }
  if (
    lowerKey.includes("mult") ||
    lowerKey.includes("scale") ||
    lowerKey.includes("zoom")
  ) {
    return "x";
  }
  return "";
}

function inferGodotPropertyTypeJs(value, unit) {
  const cleanVal = String(value || "").trim().toLowerCase();
  const cleanUnit = String(unit || "").trim().toLowerCase();
  if (
    cleanUnit === "bool" ||
    cleanUnit === "boolean" ||
    cleanVal === "true" ||
    cleanVal === "false"
  ) {
    return "bool";
  }
  if (cleanUnit === "count" && /^-?\d+$/.test(cleanVal)) {
    return "int";
  }
  return "float";
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
            value: String(t.value ?? "0").trim() || "0",
            unit: normalizeGodotUnitJs(cleanKey, t.unit, dimension),
          };
        })
    : [];

  const spec = {
    id: String(epicDoc?.id || parsed.id || `epic_${indexHint + 1}`),
    code,
    lineageKey,
    title: String(epicDoc?.title || parsed.title || "Untitled System").trim(),
    releaseVersion,
    lifecycle,
    coreLoopBeat: String(parsed.coreLoopBeat || "").trim(),
    goal: String(parsed.goal || sec.goal || "").trim(),
    links: normalizeStringArrayJs(parsed.links || parsed.plugsInto),
    outOfScope: normalizeStringArrayJs(parsed.outOfScope),
    controls,
    states: normalizeStringArrayJs(parsed.states),
    interrupts: normalizeStringArrayJs(parsed.interrupts),
    tuning,
    feedback: normalizeStringArrayJs(parsed.feedback),
    levelStaging: String(parsed.levelStaging || "").trim(),
    checks,
    fixes,
    baselineSummary: normalizeStringArrayJs(parsed.baselineSummary),
    upgradeDeltas: normalizeStringArrayJs(parsed.upgradeDeltas),
    copilotUpgrades: Array.isArray(parsed.copilotUpgrades)
      ? parsed.copilotUpgrades
      : [],
    chosen: Boolean(parsed.chosen),
  };

  spec.openFixes = spec.fixes.filter((f) => !f.resolved);
  spec.openFixesCount = spec.openFixes.length;
  spec.passedChecksCount = spec.checks.filter((c) => c.passed).length;
  spec.isPassed = computeEpicPassedJs(spec);
  return spec;
}

function sanitizeGodotLiveContextJs(raw) {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
    return null;
  }
  const cleanStr = (val, maxLen = 160) =>
    String(val ?? "").trim().slice(0, maxLen);
  const cleanArr = (val, maxItems) =>
    Array.isArray(val)
      ? val
          .map((item) => cleanStr(item, 240))
          .filter(Boolean)
          .slice(0, maxItems)
      : [];

  return {
    project_name: cleanStr(raw.project_name),
    main_scene: cleanStr(raw.main_scene),
    input_actions: cleanArr(raw.input_actions, 16),
    scene_files: cleanArr(raw.scene_files, 12),
    script_files: cleanArr(raw.script_files, 14),
    resource_files: cleanArr(raw.resource_files, 8),
    recent_errors: cleanArr(raw.recent_errors, 8),
  };
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
          for (const link of (Array.isArray(sib.links) ? sib.links : []).slice(0, 2)) {
            addContract(link);
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

function computeActiveGodotEpicPayload({
  docsById,
  projectId,
  webStudioUrl = DEFAULT_WEB_STUDIO_URL,
  liveGodotContext = null,
  preferredEpicId = "",
}) {
  const projectDoc = projectId ? docsById.get(projectId) || null : null;
  if (!projectDoc) {
    return {
      ok: false,
      projectId,
      error: "Project not found in Cloud Vault.",
      allEpicsCompleted: false,
      totalEpics: 0,
      epicPosition: 0,
      webStudioUrl,
      activeEpic: null,
      releaseEpicsSummary: [],
      godotContextMarkdown: "",
    };
  }

  const rootSpec = parseRootSpecJs(projectDoc);
  const projSections =
    projectDoc.sections && typeof projectDoc.sections === "object"
      ? projectDoc.sections
      : {};
  const liveCtx =
    liveGodotContext && typeof liveGodotContext === "object"
      ? liveGodotContext
      : parseJsonObjectSafe(projSections.godot_live_context_json);

  let releases = (Array.isArray(projectDoc.childrenIds) ? projectDoc.childrenIds : [])
    .map((id) => docsById.get(id))
    .filter((d) => d && String(d.tier || "").toUpperCase() === "RELEASE");
  if (releases.length === 0) {
    for (const d of docsById.values()) {
      if (
        String(d?.tier || "").toUpperCase() === "RELEASE" &&
        d?.parentId === projectDoc.id
      ) {
        releases.push(d);
      }
    }
  }

  const prefId = String(preferredEpicId || "").trim();
  const prefDoc = prefId ? docsById.get(prefId) : null;
  const savedRelId = String(projSections.active_release_id || "").trim();
  const activeRel =
    (prefDoc?.parentId && releases.find((r) => r.id === prefDoc.parentId)) ||
    releases.find((r) => r.id === savedRelId) ||
    (releases.length > 0 ? releases[releases.length - 1] : null);

  if (!activeRel) {
    return {
      ok: true,
      projectId: projectDoc.id,
      projectTitle: rootSpec.normalizedTitle,
      dimension: rootSpec.dimension,
      releaseVersion: "v0.1",
      releaseTitle: "",
      epicPosition: 0,
      totalEpics: 0,
      allEpicsCompleted: false,
      webStudioUrl,
      activeEpic: null,
      releaseEpicsSummary: [],
      godotContextMarkdown: renderServerGodotEpicContextJs({
        rootSpec,
        epicSpec: {
          id: "none",
          code: "E00",
          title: "No Active Release",
          releaseVersion: "v0.1",
          goal: rootSpec.pitch,
          links: [],
          outOfScope: [],
          upgradeDeltas: [],
          controls: [],
          states: [],
          interrupts: [],
          tuning: [],
          feedback: [],
          levelStaging: "",
          checks: [],
          fixes: [],
          openFixes: [],
        },
        liveGodotContext: liveCtx,
      }).split("\n---\n")[0],
    };
  }

  const releaseVersion = resolveVersionTag(activeRel);
  let epicDocs = (Array.isArray(activeRel.childrenIds) ? activeRel.childrenIds : [])
    .map((id) => docsById.get(id))
    .filter((d) => d && String(d.tier || "").toUpperCase() === "EPIC");
  if (epicDocs.length === 0) {
    for (const d of docsById.values()) {
      if (
        String(d?.tier || "").toUpperCase() === "EPIC" &&
        d?.parentId === activeRel.id
      ) {
        epicDocs.push(d);
      }
    }
  }

  const parsedEpics = epicDocs.map((d, idx) =>
    parseEpicSpecJs(d, idx, rootSpec.dimension)
  );
  if (parsedEpics.length === 0) {
    return {
      ok: true,
      projectId: projectDoc.id,
      projectTitle: rootSpec.normalizedTitle,
      dimension: rootSpec.dimension,
      releaseVersion,
      releaseTitle: String(activeRel.title || releaseVersion),
      epicPosition: 0,
      totalEpics: 0,
      allEpicsCompleted: false,
      webStudioUrl,
      activeEpic: null,
      releaseEpicsSummary: [],
      godotContextMarkdown: "",
    };
  }

  const selectedId = String(projSections.selected_epic_id || "").trim();
  const selIdx = selectedId
    ? parsedEpics.findIndex((e) => e.id === selectedId)
    : -1;
  const prefIdx = prefId
    ? parsedEpics.findIndex((e) => e.id === prefId)
    : -1;
  const firstUnsignedIdx = parsedEpics.findIndex((e) => !e.isPassed);
  const allEpicsCompleted = parsedEpics.length > 0 && firstUnsignedIdx === -1;

  let activeIdx = -1;
  if (prefIdx >= 0) {
    activeIdx = prefIdx;
  } else if (selIdx >= 0 && !parsedEpics[selIdx].isPassed) {
    activeIdx = selIdx;
  } else if (firstUnsignedIdx >= 0) {
    activeIdx = firstUnsignedIdx;
  } else if (selIdx >= 0) {
    activeIdx = selIdx;
  } else {
    activeIdx = parsedEpics.length - 1;
  }

  const activeEpic = parsedEpics[activeIdx];
  const baseUrl = String(webStudioUrl || DEFAULT_WEB_STUDIO_URL).replace(/\/+$/, "");
  const epicStudioUrl = `${baseUrl}/?project=${encodeURIComponent(
    projectDoc.id
  )}&epic=${encodeURIComponent(activeEpic.id)}`;

  const godotContextMarkdown = renderServerGodotEpicContextJs({
    rootSpec,
    epicSpec: activeEpic,
    releaseEpics: parsedEpics,
    liveGodotContext: liveCtx,
  });

  const stagingTscns = extractResPathsListJs(activeEpic.levelStaging, ".tscn");
  const linkTscns = extractResPathsListJs((activeEpic.links || []).join(" "), ".tscn");
  const liveMainScene = normalizeResPathJs(liveCtx?.main_scene || "");
  const liveScenes = Array.isArray(liveCtx?.scene_files)
    ? liveCtx.scene_files.map((s) => normalizeResPathJs(s)).filter(Boolean)
    : [];
  const arenaScenePath =
    stagingTscns[0] || liveMainScene || linkTscns[0] || liveScenes[0] || "";

  const releaseEpicsSummary = parsedEpics.map((ep) => ({
    id: ep.id,
    code: ep.code,
    title: ep.title,
    isPassed: Boolean(ep.isPassed),
    openFixesCount: Number(ep.openFixesCount || 0),
    passedChecksCount: Number(ep.passedChecksCount || 0),
    totalChecks: Array.isArray(ep.checks) ? ep.checks.length : 0,
  }));

  return {
    ok: true,
    projectId: projectDoc.id,
    projectTitle: rootSpec.normalizedTitle,
    dimension: rootSpec.dimension,
    releaseVersion,
    releaseTitle: String(activeRel.title || releaseVersion),
    epicPosition: activeIdx + 1,
    totalEpics: parsedEpics.length,
    allEpicsCompleted,
    webStudioUrl: epicStudioUrl,
    arenaScenePath,
    activeEpic,
    releaseEpicsSummary,
    godotContextMarkdown,
    rootSpec,
    releaseEpics: parsedEpics,
  };
}

function resolveTargetEpicDocIdJs({
  docsById,
  projectId,
  requestedEpicId = "",
  webStudioUrl = DEFAULT_WEB_STUDIO_URL,
  action = "",
}) {
  const reqId = String(requestedEpicId || "").trim();
  if (!reqId) {
    const payload = computeActiveGodotEpicPayload({
      docsById,
      projectId,
      webStudioUrl,
    });
    return String(payload.activeEpic?.id || "").trim();
  }

  const directDoc = docsById.get(reqId);
  if (directDoc && String(directDoc.tier || "").toUpperCase() === "EPIC") {
    return reqId;
  }

  const lowerReq = reqId.toLowerCase();
  const projectDoc = docsById.get(projectId);
  const rootSpec = parseRootSpecJs(projectDoc);
  const savedRelId = String(projectDoc?.sections?.active_release_id || "").trim();

  const epicDocs = [];
  for (const d of docsById.values()) {
    if (d && String(d.tier || "").toUpperCase() === "EPIC") {
      epicDocs.push(d);
    }
  }

  const ordered = savedRelId
    ? [
        ...epicDocs.filter((d) => d.parentId === savedRelId),
        ...epicDocs.filter((d) => d.parentId !== savedRelId),
      ]
    : epicDocs;

  for (let i = 0; i < ordered.length; i += 1) {
    const doc = ordered[i];
    const parsed = parseEpicSpecJs(doc, i, rootSpec.dimension);
    if (
      parsed.code.toLowerCase() === lowerReq ||
      parsed.lineageKey.toLowerCase() === lowerReq
    ) {
      return String(doc.id);
    }
  }

  return reqId;
}

const GODOT_UPDATE_VALID_ACTIONS = new Set([
  "toggle_check",
  "update_tuning",
  "set_tuning",
  "log_fix",
  "resolve_fix",
  "pass_epic",
  "reopen_epic",
  "sync_project",
  "build_epic",
  "fix_epic",
]);

function applyGodotEpicMutationJs({
  epicDoc,
  action,
  body = {},
  dimension = "dim3d",
  nowMs = Date.now(),
}) {
  const sec =
    epicDoc?.sections && typeof epicDoc.sections === "object"
      ? { ...epicDoc.sections }
      : {};
  const spec = parseEpicSpecJs(epicDoc, 0, dimension);
  delete spec.openFixes;
  delete spec.openFixesCount;
  delete spec.passedChecksCount;
  delete spec.isPassed;

  if (action === "toggle_check") {
    const checkId = String(body.checkId || "").trim();
    const checkIdx =
      body.checkIndex !== undefined &&
      body.checkIndex !== null &&
      String(body.checkIndex).trim() !== "" &&
      Number.isInteger(Number(body.checkIndex))
        ? Number(body.checkIndex)
        : -1;
    const oneBasedIdx = /^\d+$/.test(checkId) ? Number(checkId) - 1 : -1;
    const lowerCheckId = checkId.toLowerCase();

    let matchedIdx = -1;
    for (let i = 0; i < spec.checks.length; i += 1) {
      if ((checkId && spec.checks[i].id === checkId) || i === checkIdx) {
        matchedIdx = i;
        break;
      }
    }
    if (matchedIdx < 0 && oneBasedIdx >= 0 && oneBasedIdx < spec.checks.length) {
      matchedIdx = oneBasedIdx;
    }
    if (matchedIdx < 0 && lowerCheckId) {
      matchedIdx = spec.checks.findIndex((c) =>
        c.text.toLowerCase().includes(lowerCheckId)
      );
    }
    if (matchedIdx < 0) {
      const err = new Error(
        `Matching Playtest check not found for "${checkId || checkIdx}".`
      );
      err.statusCode = 404;
      throw err;
    }
    spec.checks[matchedIdx].passed =
      typeof body.passed === "boolean"
        ? body.passed
        : !spec.checks[matchedIdx].passed;
    const anyUnchecked = spec.checks.some((c) => !c.passed);
    if (spec.lifecycle === "queued") {
      spec.lifecycle = "active";
    } else if (spec.lifecycle === "stable" && anyUnchecked) {
      spec.lifecycle =
        Array.isArray(spec.upgradeDeltas) && spec.upgradeDeltas.length > 0
          ? "upgrading"
          : "active";
    }
  } else if (action === "update_tuning" || action === "set_tuning") {
    const cleanKey = sanitizeGodotTuningKeyJs(body.key, "");
    const rawVal =
      body.value === undefined || body.value === null
        ? ""
        : String(body.value).trim();
    if (!cleanKey || !rawVal) {
      const err = new Error(
        "Expected non-empty key and value for update_tuning."
      );
      err.statusCode = 400;
      throw err;
    }
    const rawUnit = String(body.unit || "").trim();
    const existing = spec.tuning.find(
      (t) => t.key.toLowerCase() === cleanKey.toLowerCase()
    );
    if (existing) {
      existing.value = rawVal;
      existing.unit = normalizeGodotUnitJs(
        existing.key,
        rawUnit || existing.unit,
        dimension
      );
    } else {
      spec.tuning.push({
        key: cleanKey,
        value: rawVal,
        unit: normalizeGodotUnitJs(cleanKey, rawUnit, dimension),
      });
    }
    if (spec.lifecycle === "queued") {
      spec.lifecycle = "active";
    }
  } else if (action === "log_fix") {
    const cleanText = String(body.fixText || "")
      .trim()
      .replace(/^\[FIX\]\s*/i, "")
      .trim();
    if (!cleanText) {
      const err = new Error("Expected non-empty fixText for log_fix.");
      err.statusCode = 400;
      throw err;
    }
    const newId =
      String(body.fixId || "").trim() ||
      `fix_${nowMs}_${Math.random().toString(36).slice(2, 6)}`;
    spec.fixes.push({
      id: newId,
      text: cleanText,
      resolved: false,
      createdAtMs: Number(nowMs) || Date.now(),
    });
    if (spec.lifecycle === "stable" || spec.lifecycle === "queued") {
      spec.lifecycle =
        Array.isArray(spec.upgradeDeltas) && spec.upgradeDeltas.length > 0
          ? "upgrading"
          : "active";
    }
  } else if (action === "resolve_fix") {
    const targetId = String(body.fixId || "").trim();
    const nextResolved = body.resolved !== false;
    let matched = false;
    if (targetId === "latest") {
      for (let i = spec.fixes.length - 1; i >= 0; i -= 1) {
        if (!spec.fixes[i].resolved) {
          spec.fixes[i].resolved = nextResolved;
          matched = true;
          break;
        }
      }
    } else if (targetId) {
      const lowerTarget = targetId.toLowerCase();
      for (const f of spec.fixes) {
        if (f.id === targetId || String(f.text || "").toLowerCase() === lowerTarget) {
          f.resolved = nextResolved;
          matched = true;
        }
      }
      if (!matched && /^\d+$/.test(targetId)) {
        const oneBased = Number(targetId) - 1;
        const unresolved = spec.fixes.filter((f) => !f.resolved);
        if (oneBased >= 0 && oneBased < unresolved.length) {
          unresolved[oneBased].resolved = nextResolved;
          matched = true;
        }
      }
      if (!matched) {
        for (const f of spec.fixes) {
          if (!f.resolved && String(f.text || "").toLowerCase().includes(lowerTarget)) {
            f.resolved = nextResolved;
            matched = true;
            break;
          }
        }
      }
    }
    if (!matched && !targetId) {
      for (let i = spec.fixes.length - 1; i >= 0; i -= 1) {
        if (!spec.fixes[i].resolved) {
          spec.fixes[i].resolved = nextResolved;
          break;
        }
      }
    }
  } else if (action === "pass_epic") {
    for (const f of spec.fixes) f.resolved = true;
    for (const c of spec.checks) c.passed = true;
    spec.lifecycle = "stable";
  } else if (action === "reopen_epic") {
    if (Array.isArray(spec.upgradeDeltas) && spec.upgradeDeltas.length > 0) {
      spec.lifecycle = "upgrading";
      const verLower = String(spec.releaseVersion || "").trim().toLowerCase();
      const deltaChecks = spec.checks.filter((c) => {
        const t = String(c.text || "").trim().toLowerCase();
        return (
          String(c.id || "").includes("_delta_") ||
          (verLower
            ? t.startsWith(`verify ${verLower} delta`)
            : t.includes("delta:"))
        );
      });
      if (deltaChecks.length > 0) {
        for (const c of deltaChecks) c.passed = false;
      } else {
        for (const c of spec.checks) c.passed = false;
      }
    } else {
      spec.lifecycle = "active";
      for (const c of spec.checks) c.passed = false;
    }
  } else {
    const err = new Error(`Unsupported Godot Epic action: ${action}`);
    err.statusCode = 400;
    throw err;
  }

  const isCompleted = computeEpicPassedJs(spec);
  sec.code = spec.code;
  sec.lineage_key = spec.lineageKey;
  sec.release_version = spec.releaseVersion;
  sec.lifecycle = spec.lifecycle;
  sec.goal = spec.goal;
  sec.epic_spec_json = JSON.stringify(spec);
  sec.updated_at_ms = String(nowMs);
  sec.last_godot_sync_ms = String(nowMs);

  const subtasks = spec.checks.map((c) => ({
    id: c.id,
    text: c.text,
    completed: Boolean(c.passed),
  }));

  return { sections: sec, isCompleted, subtasks, epicSpec: spec };
}

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
  const rawUpdates = Array.isArray(obj.scriptUpdates) ? obj.scriptUpdates : [];
  const scriptUpdates = [];
  for (const u of rawUpdates) {
    if (!u || typeof u !== "object") continue;
    const resPath = normalizeResPathJs(u.resPath || u.res_path || "");
    const content = stripDiffLinePrefixes(u.content || "");
    if (!resPath || !content) continue;
    scriptUpdates.push({
      resPath,
      attachTo: String(u.attachTo || u.attach_to || "").trim(),
      scenePath: normalizeResPathJs(u.scenePath || u.scene_path || ""),
      language: String(u.language || "gdscript").trim().toLowerCase(),
      content,
    });
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
    const normInput = { action, keys };
    if (remove) normInput.remove = true;
    if (overwrite) normInput.overwrite = true;
    inputOps.push(normInput);
  }

  const arenaScenePath = normalizeResPathJs(
    obj.arenaScenePath || obj.arena_scene_path || opts.arenaScenePath || ""
  );
  const featureScenePath = normalizeResPathJs(
    obj.epicScenePath ||
      obj.epic_scene_path ||
      obj.featureScenePath ||
      obj.feature_scene_path ||
      opts.epicScenePath ||
      arenaScenePath ||
      ""
  );

  return {
    mode: String(obj.mode || mode || "build_epic").trim(),
    summary: String(obj.summary || "").trim(),
    diagnosis: String(obj.diagnosis || "").trim(),
    dimension: opts.dimension || "dim3d",
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
  thinkingLevel = "LOW",
  maxOutputTokens = 16384,
}) {
  const models = ["gemini-4-hydrogen", "gemini-flash-latest"];
  let lastError = "Gemini request failed.";
  for (const modelId of models) {
    const endpoint = `https://generativelanguage.googleapis.com/v1beta/models/${modelId}:generateContent?key=${encodeURIComponent(
      apiKey
    )}`;
    const basePayload = {
      systemInstruction: { parts: [{ text: systemInstruction }] },
      contents: [{ role: "user", parts: [{ text: userPrompt }] }],
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

async function runGodotEpicAgentWithGemini({
  apiKey,
  mode,
  rootSpec,
  epicSpec,
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
  const mergedScripts = {};
  if (liveScripts && typeof liveScripts === "object") {
    for (const [k, v] of Object.entries(liveScripts)) {
      const norm = normalizeResPathJs(k);
      if (norm && typeof v === "string") mergedScripts[norm] = v;
    }
  }

  const dimRules =
    dimMeta.id === "dim2d"
      ? "DIMENSION CONTRACT (Godot 4 · 2D): Use CharacterBody2D / Node2D / Area2D / Camera2D / Sprite2D or ColorRect/Polygon2D in pixel space (px, px/s)."
      : "DIMENSION CONTRACT (Godot 4 · 3D): Use CharacterBody3D / Node3D / Area3D / SpringArm3D / Camera3D / CSGBox3D / CSGCylinder3D / MeshInstance3D in meters (1 unit = 1 m). Ground at Y=0.";

  const systemInstruction = [
    "You are LAYERS Godot 4 Epic Co-Builder targeting Godot 4.7.2.stable.",
    dimRules,
    "Return strictly valid JSON with keys: mode, summary, diagnosis, arenaScenePath, epicScenePath, scriptUpdates, sceneOps, inputOps.",
    "STRICT ENGINE & GODOT 4.7 OUTPUT RULES:",
    "1. NEVER emit push_warning(...) placeholders or stub comments. Emit real, playable typed GDScript 2.0 and real sceneOps.",
    "2. GODOT 4.7 STRICT TYPING: NEVER write ':=' when assigning from a Variant dictionary/array/JSON getter (e.g. dict.get(...), JSON.parse_string(...), arr[0]). Always annotate explicit types ('var x: String = ...', 'var f: float = ...', 'var parsed: Variant = ...') and typed Array constructors.",
    "3. scriptUpdates: array of { resPath, attachTo, scenePath, language: 'gdscript', content }. Expose EVERY §04 tuning variable with exact snake_case '@export var ...' at the top of the relevant script with defaults matching §04.",
    "4. sceneOps: array of structured scene mutations: ensure_node, set_property, reparent_node, attach_script, detach_script, connect_signal, instance_scene, remove_node, add_to_group.",
    "5. ClassDB SAFETY: NEVER attach a script whose 'extends <Class>' is incompatible with the target node class.",
    "6. SIGNAL & ARITY SAFETY: Connect signals ONLY to nodes defining methodName with matching parameter count (use optional '_arg: Variant = null' if emitting args).",
    "7. MATERIALS & SHAPES: Specify explicit subResourceClass + subResourceProps (BoxShape3D/CapsuleShape3D/SphereShape3D or RectangleShape2D/CircleShape2D, BoxMesh/CapsuleMesh, StandardMaterial3D albedo_color).",
    "8. SCENE TREE & _ready() SAFETY: Use add_child(inst) BEFORE setting inst.global_position; use call_deferred when adding siblings inside _ready(). Clean up projectiles/enemies with queue_free().",
    "9. INPUT OPS: Declare every §02 InputMap action in inputOps: [{ action: 'snake_case', keys: ['SHIFT'], overwrite: true }] using W/A/S/D/SPACE/SHIFT/CTRL/E/Q/F/R/TAB/LMB/RMB/MMB. Emit { action: 'bad_action', remove: true } to prune stale conflicts.",
    "10. MOUSE & PAUSE SAFETY: If capturing mouse in 3D, wire ESC ('ui_cancel') toggle in _unhandled_input. Put HUD Controls inside CanvasLayer.",
    "11. 3D FACING & INSTANT HIT WINDOWS: Align VisualRig forward direction (+basis.z for atan2(dir.x, dir.z), -basis.z for look_at), parent hitbox pivots under VisualRig, and check get_overlapping_bodies() with a hit_targets guard on swing open.",
    "12. OBSERVABLE PLAYTEST FEEDBACK: Trigger albedo/modulate flashes, knockback, camera punch, cooldown HUD bar, and clear Test Scene greybox props matching §05 & §06.",
  ].join("\n");

  const contextPayload = {
    mode,
    dimension: dimMeta.id,
    projectTitle: rootSpec?.normalizedTitle || "LAYERS Project",
    arenaScenePath: String(arenaScenePath || ""),
    epicScenePath: String(epicScenePath || ""),
    godotContextMarkdown: String(godotContextMarkdown || "").slice(0, 14000),
    epicSpec: epicSpec || {},
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

  const userPrompt = [
    mode === "build_epic"
      ? `TASK: Synthesize the complete cohesive Godot 4 (${dimMeta.shortLabel}) Epic §01-§06 (scenes .tscn, scripts .gd, InputMap actions, tuning @exports, greybox test staging) so the developer can press Play immediately.`
      : "TASK: Diagnose and repair the compile error(s), runtime error(s), or open [FIX] item(s) across affected Godot scripts, scenes, and InputMap while preserving passing playtest gates.",
    "PROJECT & EPIC CONTEXT JSON:",
    JSON.stringify(contextPayload),
  ].join("\n\n");

  const aiResp = await callGeminiFlashJson({
    apiKey,
    systemInstruction,
    userPrompt,
    thinkingLevel: mode === "fix_epic" ? "MEDIUM" : "LOW",
    maxOutputTokens: 16384,
  });
  if (!aiResp.ok) {
    return { ok: false, error: aiResp.error || "Gemini Epic agent request failed." };
  }
  const bundle = normalizeAgentBundle(aiResp.data, mode, {
    dimension: dimMeta.id,
    arenaScenePath: arenaScenePath || "",
    epicScenePath: epicScenePath || "",
  });
  if (!bundle.summary) {
    bundle.summary =
      mode === "build_epic"
        ? `Built ${epicSpec?.code || "Epic"} · ${epicSpec?.title || "System"} (${bundle.scriptUpdates.length} scripts, ${bundle.sceneOps.length} scene ops).`
        : `Applied ${epicSpec?.code || "Epic"} fix (${bundle.scriptUpdates.length} scripts, ${bundle.sceneOps.length} scene ops).`;
  }
  return { ok: true, model: aiResp.model, bundle };
}

function parseAdminEmails() {
  return new Set(
    String(process.env.ADMIN_EMAILS || "henryyoungchoi@gmail.com")
      .split(",")
      .map((s) => s.trim().toLowerCase())
      .filter(Boolean)
  );
}

function isAdminEmail(email) {
  return parseAdminEmails().has(String(email || "").trim().toLowerCase());
}

function isValidEmail(email) {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) && email.length <= 254;
}

function setCachedStatus(email, status) {
  accessCache.set(email, {
    status,
    expiresAt: Date.now() + ACCESS_CACHE_TTL_MS,
  });
}

function clearCachedStatus(email) {
  accessCache.delete(email);
}

async function getAccessStatusFromDb(email) {
  const cached = accessCache.get(email);
  if (cached && cached.expiresAt > Date.now()) {
    return cached.status;
  }
  const snap = await getFirestore().collection("ai_access").doc(email).get();
  const status = snap.exists ? String(snap.data()?.status || "uninvited") : "uninvited";
  setCachedStatus(email, status);
  return status;
}

async function verifyCallerToken(req) {
  const authHeader = String(req.headers.authorization || "");
  if (!authHeader.startsWith("Bearer ")) {
    return { errorStatus: 401, errorMessage: "Missing Firebase Authorization Bearer token." };
  }
  const idToken = authHeader.slice("Bearer ".length).trim();
  if (!idToken) {
    return { errorStatus: 401, errorMessage: "Empty Bearer token." };
  }
  try {
    // checkRevoked = true ensures revoked users lose token access immediately
    const decoded = await getAuth().verifyIdToken(idToken, true);
    const email = String(decoded.email || "").trim().toLowerCase();
    if (!email || decoded.email_verified === false) {
      return { errorStatus: 403, errorMessage: "A verified Google account email is required." };
    }
    return {
      uid: decoded.uid,
      email,
      displayName: String(decoded.name || "").trim(),
    };
  } catch (_err) {
    return { errorStatus: 401, errorMessage: "Invalid, expired, or revoked Google Sign-In token." };
  }
}

function parseJsonBody(req) {
  if (req.body && typeof req.body === "object") return req.body;
  if (typeof req.body === "string" && req.body.trim()) {
    try {
      return JSON.parse(req.body);
    } catch (_) {
      return {};
    }
  }
  if (req.rawBody) {
    try {
      return JSON.parse(req.rawBody.toString("utf8"));
    } catch (_) {
      return {};
    }
  }
  return {};
}

async function sendInviteEmailIfConfigured({ toEmail, inviteUrl, invitedBy }) {
  const rawPass = String(GMAIL_APP_PASSWORD.value() || "").replace(/\s+/g, "");
  if (!rawPass) {
    return { emailSent: false, reason: "smtp_not_configured" };
  }
  const fromEmail = String(
    process.env.SMTP_FROM_EMAIL || invitedBy || "henryyoungchoi@gmail.com"
  ).trim();

  const transporter = nodemailer.createTransport({
    host: "smtp.gmail.com",
    port: 465,
    secure: true,
    auth: {
      user: fromEmail,
      pass: rawPass,
    },
  });

  const html = `
    <div style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; max-width: 520px; margin: 24px auto; padding: 28px; background: #12151B; color: #F3F4F6; border: 1px solid #262C36; border-radius: 10px;">
      <div style="font-family: monospace; font-size: 11px; letter-spacing: 1px; color: #10B981; font-weight: 700; margin-bottom: 10px;">LAYERS-AGENTIC STUDIO</div>
      <h2 style="margin: 0 0 12px 0; font-size: 20px; color: #FFFFFF;">You've been invited to LAYERS-Agentic</h2>
      <p style="margin: 0 0 20px 0; font-size: 14px; line-height: 1.55; color: #9CA3AF;">
        <strong>${invitedBy}</strong> invited <strong>${toEmail}</strong> to collaborate and build with Gemini 4 Hydrogen in LAYERS-Agentic.
      </p>
      <a href="${inviteUrl}" style="display: inline-block; padding: 11px 20px; background: #10B981; color: #06281E; text-decoration: none; font-weight: 700; font-size: 14px; border-radius: 6px;">
        Accept Invite &amp; Sign in with Google &rarr;
      </a>
      <p style="margin: 22px 0 0 0; font-size: 12px; line-height: 1.5; color: #6B7280;">
        Sign in using <strong>${toEmail}</strong> when prompted. If the button doesn't open, copy and paste this link:<br/>
        <span style="color: #9CA3AF; word-break: break-all;">${inviteUrl}</span>
      </p>
    </div>
  `;

  try {
    await transporter.sendMail({
      from: `"LAYERS-Agentic" <${fromEmail}>`,
      to: toEmail,
      subject: "You're invited to LAYERS-Agentic",
      text: `${invitedBy} invited you (${toEmail}) to LAYERS-Agentic.\n\nAccept your invite and sign in with Google:\n${inviteUrl}\n`,
      html,
    });
    return { emailSent: true };
  } catch (err) {
    return {
      emailSent: false,
      reason: String(err && err.message ? err.message : err),
    };
  }
}

exports.geminiProxy = onRequest(
  {
    region: "us-central1",
    cors: [
      "https://henrycgithub.github.io",
      /^http:\/\/localhost(:\d+)?$/,
      /^http:\/\/127\.0\.0\.1(:\d+)?$/,
    ],
    invoker: "public",
    timeoutSeconds: 120,
    memory: "256MiB",
    secrets: [GEMINI_API_KEY, GMAIL_APP_PASSWORD],
  },
  async (req, res) => {
    const cleanPath = (req.path || "/").replace(/\/+$/, "") || "/";

    // -------------------------------------------------------------------------
    // Route 1: POST /sendInvite (Admin-only)
    // -------------------------------------------------------------------------
    if (cleanPath === "/sendInvite") {
      if (req.method !== "POST") {
        res.status(405).json({ error: { code: 405, message: "Expected POST." } });
        return;
      }
      const caller = await verifyCallerToken(req);
      if (caller.errorStatus) {
        res.status(caller.errorStatus).json({
          error: { code: caller.errorStatus, message: caller.errorMessage },
        });
        return;
      }
      if (!isAdminEmail(caller.email)) {
        res.status(403).json({
          error: { code: 403, message: "Only workspace admins can send invites." },
        });
        return;
      }

      const body = parseJsonBody(req);
      const targetEmail = String(body.email || "").trim().toLowerCase();
      if (!isValidEmail(targetEmail)) {
        res.status(400).json({
          error: { code: 400, message: "Please enter a valid email address." },
        });
        return;
      }
      if (isAdminEmail(targetEmail)) {
        res.status(400).json({
          error: { code: 400, message: "Admin owner already has full access." },
        });
        return;
      }

      const inviteToken = crypto.randomBytes(24).toString("hex");
      const baseAppUrl = String(
        process.env.APP_PUBLIC_URL || "https://henrycgithub.github.io/LAYERS-Agentic/"
      ).replace(/\/+$/, "");
      const inviteUrl = `${baseAppUrl}/?invite=${inviteToken}&invited_email=${encodeURIComponent(
        targetEmail
      )}`;
      const nowMs = Date.now();

      const docRef = getFirestore().collection("ai_access").doc(targetEmail);
      const existing = await docRef.get();
      const prevStatus = existing.exists ? existing.data()?.status : null;
      const keepApproved = prevStatus === "approved" && body.resetStatus !== true;

      await docRef.set(
        {
          email: targetEmail,
          status: keepApproved ? "approved" : "invited",
          inviteToken,
          inviteUrl,
          invitedBy: caller.email,
          invitedAt: nowMs,
          updatedAt: nowMs,
        },
        { merge: true }
      );
      clearCachedStatus(targetEmail);

      const mailResult = await sendInviteEmailIfConfigured({
        toEmail: targetEmail,
        inviteUrl,
        invitedBy: caller.email,
      });

      res.status(200).json({
        ok: true,
        email: targetEmail,
        status: keepApproved ? "approved" : "invited",
        emailSent: mailResult.emailSent,
        emailNotice: mailResult.reason || null,
        inviteUrl,
      });
      return;
    }

    // -------------------------------------------------------------------------
    // Route 2: POST /acceptInvite (Verifies or activates invited Google login)
    // -------------------------------------------------------------------------
    if (cleanPath === "/acceptInvite") {
      if (req.method !== "POST") {
        res.status(405).json({ error: { code: 405, message: "Expected POST." } });
        return;
      }
      const caller = await verifyCallerToken(req);
      if (caller.errorStatus) {
        res.status(caller.errorStatus).json({
          error: { code: caller.errorStatus, message: caller.errorMessage },
        });
        return;
      }

      if (isAdminEmail(caller.email)) {
        res.status(200).json({
          ok: true,
          email: caller.email,
          status: "approved",
          isAdmin: true,
        });
        return;
      }

      const body = parseJsonBody(req);
      const expectedEmail = String(body.invitedEmail || "").trim().toLowerCase();
      const db = getFirestore();
      const callerRef = db.collection("ai_access").doc(caller.email);
      const callerSnap = await callerRef.get();
      const callerStatus = callerSnap.exists
        ? String(callerSnap.data()?.status || "uninvited")
        : "uninvited";

      // Guard: clicked an invite link sent to Email A while signed into Google Account B
      if (expectedEmail && expectedEmail !== caller.email) {
        if (callerStatus !== "approved" && callerStatus !== "invited") {
          await getAuth().deleteUser(caller.uid).catch(() => {});
        }
        res.status(409).json({
          ok: false,
          code: "email_mismatch",
          expectedEmail,
          signedInEmail: caller.email,
          error: {
            code: 409,
            message: `This invite was sent to ${expectedEmail}, but you signed in as ${caller.email}. Please sign in with ${expectedEmail}.`,
          },
        });
        return;
      }

      const nowMs = Date.now();
      if (callerStatus === "approved") {
        await callerRef.set(
          {
            uid: caller.uid,
            displayName: caller.displayName || callerSnap.data()?.displayName || "",
            lastLoginAt: nowMs,
            updatedAt: nowMs,
          },
          { merge: true }
        );
        setCachedStatus(caller.email, "approved");
        res.status(200).json({
          ok: true,
          email: caller.email,
          status: "approved",
          newlyAccepted: false,
        });
        return;
      }

      if (callerStatus === "invited") {
        await callerRef.set(
          {
            status: "approved",
            uid: caller.uid,
            displayName: caller.displayName || "",
            inviteToken: null,
            acceptedAt: nowMs,
            lastLoginAt: nowMs,
            updatedAt: nowMs,
          },
          { merge: true }
        );
        setCachedStatus(caller.email, "approved");
        res.status(200).json({
          ok: true,
          email: caller.email,
          status: "approved",
          newlyAccepted: true,
        });
        return;
      }

      // Uninvited or revoked Google account: purge from Firebase Auth Users to keep list clean
      await getAuth().deleteUser(caller.uid).catch(() => {});
      clearCachedStatus(caller.email);
      res.status(403).json({
        ok: false,
        code: callerStatus === "revoked" ? "revoked" : "uninvited",
        status: callerStatus,
        error: {
          code: 403,
          message:
            callerStatus === "revoked"
              ? `Access for ${caller.email} has been revoked by the workspace admin.`
              : `Invite required — ${caller.email} has not been invited to this workspace yet.`,
        },
      });
      return;
    }

    // -------------------------------------------------------------------------
    // Route 3: POST /revokeInvite (Admin-only: cancels pending invite or revokes active user)
    // -------------------------------------------------------------------------
    if (cleanPath === "/revokeInvite") {
      if (req.method !== "POST") {
        res.status(405).json({ error: { code: 405, message: "Expected POST." } });
        return;
      }
      const caller = await verifyCallerToken(req);
      if (caller.errorStatus) {
        res.status(caller.errorStatus).json({
          error: { code: caller.errorStatus, message: caller.errorMessage },
        });
        return;
      }
      if (!isAdminEmail(caller.email)) {
        res.status(403).json({
          error: { code: 403, message: "Only workspace admins can revoke access." },
        });
        return;
      }

      const body = parseJsonBody(req);
      const targetEmail = String(body.email || "").trim().toLowerCase();
      if (!isValidEmail(targetEmail) || isAdminEmail(targetEmail)) {
        res.status(400).json({
          error: { code: 400, message: "Invalid target email." },
        });
        return;
      }

      const nowMs = Date.now();
      const docRef = getFirestore().collection("ai_access").doc(targetEmail);
      await docRef.set(
        {
          email: targetEmail,
          status: "revoked",
          inviteToken: null,
          revokedBy: caller.email,
          revokedAt: nowMs,
          updatedAt: nowMs,
        },
        { merge: true }
      );
      clearCachedStatus(targetEmail);

      try {
        const userRecord = await getAuth().getUserByEmail(targetEmail);
        await getAuth().revokeRefreshTokens(userRecord.uid).catch(() => {});
        await getAuth().deleteUser(userRecord.uid).catch(() => {});
      } catch (_) {
        // User had not signed into Firebase Auth yet
      }

      res.status(200).json({
        ok: true,
        email: targetEmail,
        status: "revoked",
      });
      return;
    }

    // -------------------------------------------------------------------------
    // Route 3B: POST /godotLink/token (Google Sign-In auth: generate/reuse/rotate lyr_... token)
    // -------------------------------------------------------------------------
    if (cleanPath === "/godotLink/token") {
      if (req.method !== "POST") {
        res.status(405).json({ error: { code: 405, message: "Expected POST." } });
        return;
      }
      const caller = await verifyCallerToken(req);
      if (caller.errorStatus) {
        res.status(caller.errorStatus).json({
          error: { code: caller.errorStatus, message: caller.errorMessage },
        });
        return;
      }
      if (!isAdminEmail(caller.email)) {
        const accessStatus = await getAccessStatusFromDb(caller.email);
        if (accessStatus !== "approved") {
          res.status(403).json({
            error: {
              code: 403,
              accessStatus,
              message: `Invite approval required for ${caller.email}.`,
            },
          });
          return;
        }
      }

      const body = parseJsonBody(req);
      const projectId = String(body.projectId || "").trim();
      const rotate = body.rotate === true;
      const webStudioUrl = String(body.webStudioUrl || DEFAULT_WEB_STUDIO_URL).trim();
      if (!projectId) {
        res.status(400).json({
          error: { code: 400, message: "Missing projectId." },
        });
        return;
      }

      const db = getFirestore();
      const linkDocId = `${projectId}_${caller.uid}`;
      const linkRef = db.collection("godot_links").doc(linkDocId);
      const existingSnap = await linkRef.get();
      const existingData = existingSnap.exists ? existingSnap.data() || {} : null;

      if (
        existingData &&
        !rotate &&
        existingData.linkToken &&
        existingData.revoked !== true
      ) {
        const existingToken = String(existingData.linkToken);
        const tokenHint = `${existingToken.slice(0, 8)}…${existingToken.slice(-4)}`;
        res.status(200).json({
          ok: true,
          projectId,
          linkToken: existingToken,
          tokenHint,
          syncBaseUrl: DEFAULT_SYNC_BASE_URL,
        });
        return;
      }

      const newToken = `lyr_${crypto.randomBytes(24).toString("hex")}`;
      const tokenHash = hashLinkToken(newToken);
      const tokenHint = `${newToken.slice(0, 8)}…${newToken.slice(-4)}`;
      await linkRef.set(
        {
          uid: caller.uid,
          email: caller.email,
          projectId,
          linkToken: newToken,
          tokenHash,
          tokenHint,
          webStudioUrl: webStudioUrl || DEFAULT_WEB_STUDIO_URL,
          revoked: false,
          updatedAt: Date.now(),
        },
        { merge: true }
      );

      res.status(200).json({
        ok: true,
        projectId,
        linkToken: newToken,
        tokenHint,
        syncBaseUrl: DEFAULT_SYNC_BASE_URL,
      });
      return;
    }

    // -------------------------------------------------------------------------
    // Route 3C: GET / POST /godotLink/epic (Godot Dock: ROOT_GODOT_CONTEXT + 1 active Epic Spec)
    // -------------------------------------------------------------------------
    if (cleanPath === "/godotLink/epic") {
      if (req.method !== "GET" && req.method !== "POST") {
        res.status(405).json({ error: { code: 405, message: "Expected GET or POST." } });
        return;
      }
      const linkAuth = await verifyGodotLinkToken(req);
      if (linkAuth.errorStatus) {
        res.status(linkAuth.errorStatus).json({
          error: { code: linkAuth.errorStatus, message: linkAuth.errorMessage },
        });
        return;
      }

      const body = req.method === "POST" ? parseJsonBody(req) : {};
      const liveGodotContext = sanitizeGodotLiveContextJs(
        body.godotContext || body.liveGodotContext
      );
      const preferredEpicId = String(body.epicId || "").trim();

      const db = getFirestore();
      const docsSnap = await db
        .collection("users")
        .doc(linkAuth.uid)
        .collection("documents")
        .get();
      const docsById = new Map();
      for (const d of docsSnap.docs) {
        docsById.set(d.id, { id: d.id, ...(d.data() || {}) });
      }

      const payload = computeActiveGodotEpicPayload({
        docsById,
        projectId: linkAuth.projectId,
        webStudioUrl: linkAuth.webStudioUrl,
        liveGodotContext,
        preferredEpicId,
      });
      if (!payload.ok) {
        res.status(404).json({
          error: { code: 404, message: payload.error || "Project not found." },
        });
        return;
      }

      const nowMs = String(Date.now());
      const nextProjSections = {
        last_godot_sync_ms: nowMs,
      };
      if (liveGodotContext) {
        nextProjSections.godot_live_context_json = JSON.stringify(liveGodotContext);
      }
      if (payload.activeEpic?.id) {
        nextProjSections.selected_epic_id = payload.activeEpic.id;
      }

      linkAuth.linkRef.set({ lastSyncAt: Date.now() }, { merge: true }).catch(() => {});
      db.collection("users")
        .doc(linkAuth.uid)
        .collection("documents")
        .doc(linkAuth.projectId)
        .set({ sections: nextProjSections }, { merge: true })
        .catch(() => {});

      const { rootSpec: _rs, releaseEpics: _re, ...clientPayload } = payload;
      res.status(200).json(clientPayload);
      return;
    }

    // -------------------------------------------------------------------------
    // Route 3D: POST /godotLink/update (Godot Dock: toggle_check / update_tuning / log_fix / resolve_fix / pass_epic / reopen_epic / sync_project / build_epic / fix_epic)
    // -------------------------------------------------------------------------
    if (cleanPath === "/godotLink/update") {
      if (req.method !== "POST") {
        res.status(405).json({ error: { code: 405, message: "Expected POST." } });
        return;
      }
      const linkAuth = await verifyGodotLinkToken(req);
      if (linkAuth.errorStatus) {
        res.status(linkAuth.errorStatus).json({
          error: { code: linkAuth.errorStatus, message: linkAuth.errorMessage },
        });
        return;
      }

      const body = parseJsonBody(req);
      const action = String(body.action || "").trim();
      if (!GODOT_UPDATE_VALID_ACTIONS.has(action)) {
        res.status(400).json({
          error: {
            code: 400,
            message:
              "Expected valid action (toggle_check, update_tuning, log_fix, resolve_fix, pass_epic, reopen_epic, sync_project, build_epic, or fix_epic).",
          },
        });
        return;
      }
      if (action === "log_fix" && !String(body.fixText || "").trim()) {
        res.status(400).json({
          error: { code: 400, message: "Expected non-empty fixText for log_fix." },
        });
        return;
      }

      const liveGodotContext = sanitizeGodotLiveContextJs(
        body.godotContext || body.liveGodotContext
      );

      const db = getFirestore();
      const docsCol = db
        .collection("users")
        .doc(linkAuth.uid)
        .collection("documents");

      const docsSnap = await docsCol.get();
      const docsById = new Map();
      for (const d of docsSnap.docs) {
        docsById.set(d.id, { id: d.id, ...(d.data() || {}) });
      }

      let targetEpicId = String(body.epicId || "").trim();
      if (action !== "sync_project") {
        targetEpicId = resolveTargetEpicDocIdJs({
          docsById,
          projectId: linkAuth.projectId,
          requestedEpicId: targetEpicId,
          webStudioUrl: linkAuth.webStudioUrl,
          action,
        });
        if (!targetEpicId) {
          res.status(404).json({
            error: { code: 404, message: "No active Epic found to update." },
          });
          return;
        }
      }

      const nowMs = Date.now();

      // 1-Click In-Dock Cloud Gemini AI Builder (build_epic / fix_epic)
      if (action === "build_epic" || action === "fix_epic") {
        const apiKey = String(GEMINI_API_KEY.value() || "").trim();
        if (!apiKey) {
          res.status(500).json({
            error: { code: 500, message: "Server GEMINI_API_KEY secret is not configured." },
          });
          return;
        }
        const payload = computeActiveGodotEpicPayload({
          docsById,
          projectId: linkAuth.projectId,
          webStudioUrl: linkAuth.webStudioUrl,
          liveGodotContext,
          preferredEpicId: targetEpicId,
        });
        if (!payload.ok || !payload.activeEpic) {
          res.status(404).json({
            error: { code: 404, message: payload.error || "Active Epic not found." },
          });
          return;
        }

        const agentResp = await runGodotEpicAgentWithGemini({
          apiKey,
          mode: action,
          rootSpec: payload.rootSpec,
          epicSpec: payload.activeEpic,
          godotContextMarkdown: payload.godotContextMarkdown,
          liveScripts: body.liveScripts,
          sceneSnapshot: body.sceneSnapshot,
          inputMapSnapshot: body.inputMapSnapshot,
          projectDiagnostics: body.projectDiagnostics,
          liveGodotContext,
          prompt: body.prompt,
          errorText: body.errorText,
          arenaScenePath: body.arenaScenePath || payload.arenaScenePath,
          epicScenePath: body.epicScenePath || payload.arenaScenePath,
        });

        if (!agentResp.ok) {
          res.status(502).json({
            error: {
              code: 502,
              message: agentResp.error || "Gemini Epic agent request failed.",
            },
          });
          return;
        }

        const nextProjSec = {
          last_godot_sync_ms: String(nowMs),
          selected_epic_id: payload.activeEpic.id,
        };
        if (liveGodotContext) {
          nextProjSec.godot_live_context_json = JSON.stringify(liveGodotContext);
        }
        linkAuth.linkRef.set({ lastSyncAt: nowMs }, { merge: true }).catch(() => {});
        docsCol
          .doc(linkAuth.projectId)
          .set({ sections: nextProjSec }, { merge: true })
          .catch(() => {});

        const { rootSpec: _rs, releaseEpics: _re, ...clientPayload } = payload;
        res.status(200).json({
          ...clientPayload,
          mode: action,
          model: agentResp.model,
          agentBundle: agentResp.bundle,
        });
        return;
      }

      const rootSpecForDim = parseRootSpecJs(docsById.get(linkAuth.projectId));
      let updatedEpicDoc = null;
      if (action !== "sync_project") {
        const epicRef = docsCol.doc(targetEpicId);
        try {
          await db.runTransaction(async (tx) => {
            const snap = await tx.get(epicRef);
            if (!snap.exists) {
              const notFound = new Error("Epic document not found.");
              notFound.statusCode = 404;
              throw notFound;
            }
            const epicData = snap.data() || {};
            const mutated = applyGodotEpicMutationJs({
              epicDoc: { id: snap.id, ...epicData },
              action,
              body,
              dimension: rootSpecForDim.dimension,
              nowMs,
            });
            tx.update(epicRef, {
              sections: mutated.sections,
              subtasks: mutated.subtasks,
              isCompleted: mutated.isCompleted,
              updatedAt: FieldValue.serverTimestamp(),
            });
            updatedEpicDoc = {
              id: snap.id,
              ...epicData,
              sections: mutated.sections,
              subtasks: mutated.subtasks,
              isCompleted: mutated.isCompleted,
            };
          });
        } catch (err) {
          const code = err?.statusCode || 500;
          res.status(code).json({
            error: { code, message: String(err?.message || err) },
          });
          return;
        }
      }

      if (targetEpicId && updatedEpicDoc) {
        docsById.set(targetEpicId, updatedEpicDoc);
      }
      const inMemProj = docsById.get(linkAuth.projectId);
      if (inMemProj) {
        const existingSec =
          inMemProj.sections && typeof inMemProj.sections === "object"
            ? { ...inMemProj.sections }
            : {};
        existingSec.last_godot_sync_ms = String(nowMs);
        if (liveGodotContext) {
          existingSec.godot_live_context_json = JSON.stringify(liveGodotContext);
        }
        if (action === "pass_epic") {
          existingSec.selected_epic_id = "";
        } else if (targetEpicId) {
          existingSec.selected_epic_id = targetEpicId;
        }
        inMemProj.sections = existingSec;
      }

      const isInPlaceMutation = action !== "pass_epic" && action !== "sync_project";
      const payload = computeActiveGodotEpicPayload({
        docsById,
        projectId: linkAuth.projectId,
        webStudioUrl: linkAuth.webStudioUrl,
        liveGodotContext,
        preferredEpicId: isInPlaceMutation ? targetEpicId : "",
      });
      if (!payload.ok) {
        res.status(404).json({
          error: { code: 404, message: payload.error || "Project not found." },
        });
        return;
      }

      const nextProjSec = {
        last_godot_sync_ms: String(nowMs),
      };
      if (liveGodotContext) {
        nextProjSec.godot_live_context_json = JSON.stringify(liveGodotContext);
      }
      if (payload.activeEpic?.id) {
        nextProjSec.selected_epic_id = payload.activeEpic.id;
      }

      linkAuth.linkRef.set({ lastSyncAt: nowMs }, { merge: true }).catch(() => {});
      docsCol
        .doc(linkAuth.projectId)
        .set({ sections: nextProjSec }, { merge: true })
        .catch(() => {});

      const { rootSpec: _rs, releaseEpics: _re, ...clientPayload } = payload;
      res.status(200).json(clientPayload);
      return;
    }

    // -------------------------------------------------------------------------
    // Route 4: Gemini Flash Proxy (/v1beta/models/<model>:generateContent)
    // -------------------------------------------------------------------------
    const routeMatch = cleanPath.match(
      /^\/v1beta\/models\/([a-zA-Z0-9._-]+)(:generateContent)?$/
    );

    if (!routeMatch) {
      res.status(404).json({
        error: { code: 404, message: "Unsupported proxy route." },
      });
      return;
    }

    const modelName = routeMatch[1];
    const isGenerateContent = Boolean(routeMatch[2]);

    if (!ALLOWED_MODELS.has(modelName)) {
      res.status(403).json({
        error: {
          code: 403,
          message: `Model "${modelName}" is blocked by LAYERS Flash-only policy.`,
        },
      });
      return;
    }

    if (isGenerateContent && req.method !== "POST") {
      res.status(405).json({
        error: { code: 405, message: "Method Not Allowed. Expected POST." },
      });
      return;
    }

    const rawBytes = req.rawBody ? req.rawBody.length : 0;
    if (rawBytes > MAX_BODY_BYTES) {
      res.status(413).json({
        error: {
          code: 413,
          message: "Request payload exceeds 512 KB limit.",
        },
      });
      return;
    }

    const caller = await verifyCallerToken(req);
    if (caller.errorStatus) {
      res.status(caller.errorStatus).json({
        error: { code: caller.errorStatus, message: caller.errorMessage },
      });
      return;
    }

    if (!isAdminEmail(caller.email)) {
      const accessStatus = await getAccessStatusFromDb(caller.email);
      if (accessStatus !== "approved") {
        res.status(403).json({
          error: {
            code: 403,
            accessStatus,
            message: `Invite approval required for ${caller.email}.`,
          },
        });
        return;
      }
    }

    const secretKey = String(GEMINI_API_KEY.value() || "").trim();
    if (!secretKey) {
      res.status(500).json({
        error: {
          code: 500,
          message: "Server GEMINI_API_KEY secret is not configured.",
        },
      });
      return;
    }

    const upstreamUrl = isGenerateContent
      ? `https://generativelanguage.googleapis.com/v1beta/models/${modelName}:generateContent`
      : `https://generativelanguage.googleapis.com/v1beta/models/${modelName}`;

    const forwardBody = isGenerateContent
      ? req.rawBody
        ? req.rawBody.toString("utf8")
        : typeof req.body === "string"
          ? req.body
          : JSON.stringify(req.body ?? {})
      : undefined;

    if (forwardBody && Buffer.byteLength(forwardBody, "utf8") > MAX_BODY_BYTES) {
      res.status(413).json({
        error: {
          code: 413,
          message: "Request payload exceeds 512 KB limit.",
        },
      });
      return;
    }

    try {
      const upstreamRes = await fetch(upstreamUrl, {
        method: isGenerateContent ? "POST" : "GET",
        headers: {
          "Content-Type": "application/json",
          "x-goog-api-key": secretKey,
        },
        body: forwardBody,
      });

      const responseText = await upstreamRes.text();
      res
        .status(upstreamRes.status)
        .type("application/json")
        .send(responseText);
    } catch (err) {
      res
        .status(502)
        .json({
          error: {
            code: 502,
            message: `Upstream Gemini request failed: ${err.message || err}`,
          },
        });
    }
  }
);

exports._testHelpers = {
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
};
