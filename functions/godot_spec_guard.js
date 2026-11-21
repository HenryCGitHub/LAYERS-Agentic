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
    .map((line) => {
      if (line.startsWith("+ ")) return line.slice(2);
      if (line === "+") return "";
      if (line.startsWith("+") && !line.startsWith("++")) return line.slice(1);
      return line;
    })
    .join("\n")
    .trim();
}

function formatCleanNumJs(v) {
  if (Math.abs(v - Math.round(v)) < 0.001) return String(Math.round(v));
  return v.toFixed(2).replace(/\.?0+$/, "");
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
    .replace(/^(?:[-*]\s+|\u2022\s*)+/, "")
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
    [/\b[A-Za-z0-9_]+\.uproject\b/gi, "project.godot"],
    [/\.uproject\b/gi, "project.godot"],
    [/\.prefab\b/gi, ".tscn"],
    [/\bPrefabs\b/gi, "PackedScenes"],
    [/\bPrefab\b/gi, "PackedScene"],
    [/\bCSG2D\b/gi, "Polygon2D"],
    ...(is2d
      ? [
          [/\bCharacterBody3D\b/g, "CharacterBody2D"],
          [/\bArea3D\b/g, "Area2D"],
          [/\bNode3D\b/g, "Node2D"],
          [/\bMarker3D\b/g, "Marker2D"],
          [/\bCollisionShape3D\b/g, "CollisionShape2D"],
          [/\bRayCast3D\b/g, "RayCast2D"],
          [/\bGPUParticles3D\b/g, "GPUParticles2D"],
          [/\bCPUParticles3D\b/g, "CPUParticles2D"],
          [/\bSpringArm3D\b/g, "Camera2D"],
          [/\bCamera3D\b/g, "Camera2D"],
          [
            /\b(?:CSGBox3D|CSGCylinder3D|CSGShape3D|MeshInstance3D)\b/g,
            "Polygon2D",
          ],
          [/\bStandardMaterial3D\b/g, "CanvasItemMaterial"],
        ]
      : [
          [/\bCharacterBody2D\b/g, "CharacterBody3D"],
          [/\bArea2D\b/g, "Area3D"],
          [/\bNode2D\b/g, "Node3D"],
          [/\bMarker2D\b/g, "Marker3D"],
          [/\bCollisionShape2D\b/g, "CollisionShape3D"],
          [/\bRayCast2D\b/g, "RayCast3D"],
          [/\bGPUParticles2D\b/g, "GPUParticles3D"],
          [/\bCPUParticles2D\b/g, "CPUParticles3D"],
          [/\bCamera2D\b/g, "Camera3D"],
        ]),
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
  out = out.replace(
    /\bL_([A-Za-z0-9_]+)(?:\.[Uu][Mm][Aa][Pp]|\.[Uu][Aa][Ss][Ss][Ee][Tt]|\.[Tt][Ss][Cc][Nn])?\b/g,
    (_, grp) => `${toSnakeCaseTokenJs(grp || "arena")}.tscn`
  );
  out = out.replace(/\b([A-Za-z_][A-Za-z0-9_]*)\.(?:cpp|hpp)\b/gi, (_, grp) =>
    `${toSnakeCaseTokenJs(grp || "script")}.gd`
  );
  out = out.replace(/\b(\d+(?:\.\d+)?)\s*(?:cm|uu)\/s\b/gi, (_, numStr) => {
    const rawNum = Number(numStr) || 0;
    return is2d
      ? `${formatCleanNumJs(rawNum)} px/s`
      : `${formatCleanNumJs(rawNum / 100)} m/s`;
  });
  out = out.replace(/\b(\d+(?:\.\d+)?)\s*(?:cm|uu)\b/gi, (_, numStr) => {
    const rawNum = Number(numStr) || 0;
    return is2d
      ? `${formatCleanNumJs(rawNum)} px`
      : `${formatCleanNumJs(rawNum / 100)} m`;
  });
  out = out.replace(/\buu\b/gi, is2d ? "px" : "m");

  const pxPerMeter = 40;
  if (is2d) {
    out = out.replace(
      /(\d+(?:\.\d+)?)\s*x\s*(\d+(?:\.\d+)?)\s*m(?=$|[\s.,;:)!?])/gi,
      (_, aStr, bStr) =>
        `${formatCleanNumJs((Number(aStr) || 0) * pxPerMeter)}x${formatCleanNumJs((Number(bStr) || 0) * pxPerMeter)} px`
    );
    out = out.replace(/\b(\d+(?:\.\d+)?)\s*m\/s\b/gi, (_, numStr) =>
      `${formatCleanNumJs((Number(numStr) || 0) * pxPerMeter)} px/s`
    );
    out = out.replace(
      /(?<=^|[\s(~])(\d+(?:\.\d+)?)\s*m(?=$|[\s.,;:)!?])/gi,
      (_, numStr) => `${formatCleanNumJs((Number(numStr) || 0) * pxPerMeter)} px`
    );
  } else {
    out = out.replace(
      /(\d+(?:\.\d+)?)\s*x\s*(\d+(?:\.\d+)?)\s*px(?=$|[\s.,;:)!?])/gi,
      (_, aStr, bStr) =>
        `${formatCleanNumJs((Number(aStr) || 0) / pxPerMeter)}x${formatCleanNumJs((Number(bStr) || 0) / pxPerMeter)} m`
    );
    out = out.replace(/\b(\d+(?:\.\d+)?)\s*px\/s\b/gi, (_, numStr) =>
      `${formatCleanNumJs((Number(numStr) || 0) / pxPerMeter)} m/s`
    );
    out = out.replace(
      /(?<=^|[\s(~])(\d+(?:\.\d+)?)\s*px(?=$|[\s.,;:)!?])/gi,
      (_, numStr) => `${formatCleanNumJs((Number(numStr) || 0) / pxPerMeter)} m`
    );
  }

  const phraseMap = [
    ["end-to-end loop", "core loop"],
    ["end-to-end", "full"],
    ["unified pipeline", "pipeline"],
  ];
  for (const [fromPhrase, toPhrase] of phraseMap) {
    out = out.replace(
      new RegExp(`\\b${fromPhrase.replace(/[-/\\^$*+?.()|[\]{}]/g, "\\$&")}\\b`, "gi"),
      (matched) =>
        matched &&
        matched[0] === matched[0].toUpperCase() &&
        matched[0] !== matched[0].toLowerCase()
          ? `${toPhrase[0].toUpperCase()}${toPhrase.slice(1)}`
          : toPhrase
    );
  }

  out = out.replace(
    /(?<![/._A-Za-z0-9])staging(?![/._A-Za-z0-9])/gi,
    (matched) =>
      matched &&
      matched[0] === matched[0].toUpperCase() &&
      matched[0] !== matched[0].toLowerCase()
        ? "Layout"
        : "layout"
  );

  const jargonMap = [
    ["leveraging", "using"],
    ["leveraged", "used"],
    ["leverages", "uses"],
    ["leverage", "use"],
    ["validating", "checking"],
    ["validates", "checks"],
    ["validated", "checked"],
    ["validate", "check"],
    ["verified", "checked"],
    ["delivering", "producing"],
    ["delivered", "produced"],
    ["delivers", "produces"],
    ["deliver", "produce"],
    ["husbandry", "breeding"],
    ["homesteads", "bases"],
    ["homestead", "base"],
    ["expeditions", "runs"],
    ["expedition", "run"],
    ["ordinances", "weapons"],
    ["ordinance", "weaponry"],
  ];
  for (const [fromWord, toLower] of jargonMap) {
    out = out.replace(new RegExp(`\\b${fromWord}\\b`, "gi"), (matched) => {
      if (
        matched &&
        matched[0] === matched[0].toUpperCase() &&
        matched[0] !== matched[0].toLowerCase()
      ) {
        return `${toLower[0].toUpperCase()}${toLower.slice(1)}`;
      }
      return toLower;
    });
  }
  for (const filler of ["unified", "seamlessly", "synergistic", "synergy"]) {
    out = out.replace(new RegExp(`\\b${filler}\\b`, "gi"), "");
  }
  return out
    .replace(/\s{2,}/g, " ")
    .replace(/\s+(?:and|or)\s*([.,;:])/gi, "$1")
    .replace(/\s+([.,;:])/g, "$1")
    .trim();
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

function scaleGodotTuningValueJs(rawValue, rawUnit, dimension = "dim3d") {
  const cleanVal = String(rawValue ?? "0").trim() || "0";
  const unit = String(rawUnit || "").trim().toLowerCase();
  const parsed = Number(cleanVal);
  if (!Number.isFinite(parsed)) return cleanVal;
  const is2d = resolveDimensionMetaJs(dimension).id === "dim2d";
  const pxPerMeter = 40;
  if (!is2d) {
    if (unit === "cm" || unit === "cm/s" || unit === "uu" || unit === "uu/s") {
      return formatCleanNumJs(parsed / 100);
    }
    if (
      unit === "px" ||
      unit === "pixel" ||
      unit === "pixels" ||
      unit === "px/s" ||
      unit === "pixels/s"
    ) {
      return formatCleanNumJs(parsed / pxPerMeter);
    }
  } else {
    if (
      unit === "m" ||
      unit === "meter" ||
      unit === "meters" ||
      unit === "mps" ||
      unit === "m/s"
    ) {
      return formatCleanNumJs(parsed * pxPerMeter);
    }
  }
  return cleanVal;
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

module.exports = {
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
};
