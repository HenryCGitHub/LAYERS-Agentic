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

function computeActiveGodotEpicPayload({
  docsById,
  projectId,
  webStudioUrl = DEFAULT_WEB_STUDIO_URL,
  liveGodotContext = null,
  preferredEpicId = "",
  preferredFeatureId = "",
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
      activeFeature: null,
      activeEpicFeatures: [],
      siblingFeaturesSummary: [],
      activeFeatureContextMarkdown: "",
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
      activeFeature: null,
      activeEpicFeatures: [],
      siblingFeaturesSummary: [],
      activeFeatureContextMarkdown: "",
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
      activeFeature: null,
      activeEpicFeatures: [],
      siblingFeaturesSummary: [],
      activeFeatureContextMarkdown: "",
      releaseEpicsSummary: [],
      godotContextMarkdown: "",
    };
  }

  const releaseOrder = releases.map((r) => resolveVersionTag(r));
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
  const visibleFeaturesRaw = getVisibleFeaturesForReleaseJs(
    activeEpic,
    releaseVersion,
    releaseOrder
  );
  const annotatedFeatures = visibleFeaturesRaw.map((f) => {
    const effChecks = getEffectiveChecksForReleaseJs(f, releaseVersion);
    const isLocked = isFeatureLockedBaselineJs(f, releaseVersion, releaseOrder);
    const isPassedForRel = isLocked || computeFeaturePassedJs(f);
    return {
      ...f,
      isLockedBaseline: isLocked,
      isPassedForRelease: isPassedForRel,
      effectiveChecks: effChecks,
      passedChecksCount: effChecks.filter((c) => Boolean(c?.passed)).length,
      totalChecksCount: effChecks.length,
    };
  });

  const prefFeatId = String(preferredFeatureId || "").trim();
  const selectedFeatId = String(projSections.selected_feature_id || "").trim();
  let activeFeature = null;
  if (prefFeatId) {
    const lowerPref = prefFeatId.toLowerCase();
    activeFeature =
      annotatedFeatures.find(
        (f) => f.id === prefFeatId || f.code.toLowerCase() === lowerPref
      ) || null;
  }
  if (!activeFeature && selectedFeatId) {
    const selFeat = annotatedFeatures.find((f) => f.id === selectedFeatId);
    if (selFeat && !selFeat.isPassedForRelease) {
      activeFeature = selFeat;
    }
  }
  if (!activeFeature) {
    activeFeature = annotatedFeatures.find((f) => !f.isPassedForRelease) || null;
  }
  if (!activeFeature && selectedFeatId) {
    activeFeature = annotatedFeatures.find((f) => f.id === selectedFeatId) || null;
  }
  if (!activeFeature && annotatedFeatures.length > 0) {
    activeFeature = annotatedFeatures[annotatedFeatures.length - 1];
  }

  const activeEpicFeatures = annotatedFeatures.map((f) => ({
    id: f.id,
    code: f.code,
    title: f.title,
    introducedIn: f.introducedIn,
    sliceTime: f.sliceTime,
    status: f.status,
    isLockedBaseline: Boolean(f.isLockedBaseline),
    isPassed: Boolean(f.isPassedForRelease),
    openFixesCount: Number(f.openFixesCount || 0),
    passedChecksCount: Number(f.passedChecksCount || 0),
    totalChecks: Number(f.totalChecksCount || 0),
  }));

  const siblingFeaturesSummary = annotatedFeatures
    .filter((f) => !activeFeature || f.id !== activeFeature.id)
    .map((f) => ({
      id: f.id,
      code: f.code,
      title: f.title,
      introducedIn: f.introducedIn,
      status: f.status,
      isLockedBaseline: Boolean(f.isLockedBaseline),
      isPassed: Boolean(f.isPassedForRelease),
      tuningKeys: (f.tuning || []).map((t) => t.key).filter(Boolean),
      inputActions: (f.controls || []).map((c) => c.action).filter(Boolean),
      checksSummary: (f.effectiveChecks || [])
        .slice(0, 4)
        .map((c) => c.text)
        .filter(Boolean),
    }));

  const baseUrl = String(webStudioUrl || DEFAULT_WEB_STUDIO_URL).replace(/\/+$/, "");
  const epicStudioUrl = `${baseUrl}/?project=${encodeURIComponent(
    projectDoc.id
  )}&epic=${encodeURIComponent(activeEpic.id)}${
    activeFeature ? `&feature=${encodeURIComponent(activeFeature.id)}` : ""
  }`;

  const godotContextMarkdown = renderServerGodotEpicContextJs({
    rootSpec,
    epicSpec: activeEpic,
    releaseEpics: parsedEpics,
    liveGodotContext: liveCtx,
  });

  const activeFeatureContextMarkdown = activeFeature
    ? renderServerGodotFeatureContextJs({
        rootSpec,
        epicSpec: activeEpic,
        featureSpec: activeFeature,
        releaseVersion,
        siblingFeaturesSummary,
        liveGodotContext: liveCtx,
      })
    : "";

  const stagingTscns = extractResPathsListJs(activeEpic.levelStaging, ".tscn");
  const ownershipTscns = (Array.isArray(activeEpic.sceneOwnership)
    ? activeEpic.sceneOwnership
    : []
  )
    .map((o) => normalizeResPathJs(o?.path || ""))
    .filter((p) => p && p.toLowerCase().endsWith(".tscn"));
  const ownershipPreferredArena =
    ownershipTscns.find((p) => /(?:arena|proto|level|room|world|main)/i.test(p)) ||
    ownershipTscns[0] ||
    "";
  const linkTscns = extractResPathsListJs((activeEpic.links || []).join(" "), ".tscn");
  const liveMainScene = normalizeResPathJs(liveCtx?.main_scene || "");
  const liveScenes = Array.isArray(liveCtx?.scene_files)
    ? liveCtx.scene_files.map((s) => normalizeResPathJs(s)).filter(Boolean)
    : [];
  const defaultArenaScene =
    rootSpec.dimension === "dim2d"
      ? "res://scenes/arena_2d.tscn"
      : "res://scenes/arena_3d.tscn";
  const arenaScenePath =
    stagingTscns[0] ||
    ownershipPreferredArena ||
    liveMainScene ||
    linkTscns[0] ||
    liveScenes[0] ||
    defaultArenaScene;

  const releaseEpicsSummary = parsedEpics.map((ep) => {
    const epVis = getVisibleFeaturesForReleaseJs(ep, releaseVersion, releaseOrder);
    return {
      id: ep.id,
      code: ep.code,
      title: ep.title,
      isPassed: Boolean(ep.isPassed),
      openFixesCount:
        Number(ep.openFixesCount || 0) +
        epVis.reduce((acc, f) => acc + Number(f.openFixesCount || 0), 0),
      passedChecksCount: Number(ep.passedChecksCount || 0),
      totalChecks: Array.isArray(ep.checks) ? ep.checks.length : 0,
      featuresCount: epVis.length,
      passedFeaturesCount: epVis.filter((f) =>
        isFeaturePassedForReleaseJs(f, releaseVersion, releaseOrder)
      ).length,
      totalOpenFeatureFixes: epVis.reduce(
        (acc, f) => acc + Number(f.openFixesCount || 0),
        0
      ),
    };
  });

  for (const ep of parsedEpics) {
    delete ep._synthesizedLegacyFeatures;
  }

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
    activeFeature,
    activeEpicFeatures,
    siblingFeaturesSummary,
    activeFeatureContextMarkdown,
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
  "pass_feature",
  "reopen_feature",
  "sync_project",
  "build_epic",
  "fix_epic",
  "build_feature",
  "fix_feature",
]);

function syncEpicLifecycleFromFeaturesJs(spec, releaseVersion, releaseOrder = []) {
  const visible = getVisibleFeaturesForReleaseJs(spec, releaseVersion, releaseOrder);
  if (visible.length === 0) return;
  const hasAnyOpenFixes =
    (spec.fixes || []).some((f) => !f?.resolved) ||
    visible.some((f) => (f.fixes || []).some((fx) => !fx?.resolved));
  const allFeaturesPassed = visible.every((f) =>
    isFeaturePassedForReleaseJs(f, releaseVersion, releaseOrder)
  );
  if (!hasAnyOpenFixes && allFeaturesPassed) {
    spec.lifecycle = "stable";
    for (const c of spec.checks || []) c.passed = true;
  } else if (spec.lifecycle === "stable" || spec.lifecycle === "queued") {
    const relTrimmed = String(releaseVersion || "v0.1").trim();
    const hasDelta =
      relTrimmed !== "v0.1" &&
      ((Array.isArray(spec.upgradeDeltas) && spec.upgradeDeltas.length > 0) ||
        visible.some((f) => String(f.releaseDelta || "").trim() !== ""));
    spec.lifecycle = hasDelta ? "upgrading" : "active";
  }
}

function applyGodotEpicMutationJs({
  epicDoc,
  action,
  body = {},
  dimension = "dim3d",
  nowMs = Date.now(),
  releaseOrder = [],
}) {
  const sec =
    epicDoc?.sections && typeof epicDoc.sections === "object"
      ? { ...epicDoc.sections }
      : {};
  const spec = parseEpicSpecJs(epicDoc, 0, dimension);
  const wasSynthesizedLegacy = Boolean(spec._synthesizedLegacyFeatures);
  delete spec._synthesizedLegacyFeatures;
  delete spec.openFixes;
  delete spec.openFixesCount;
  delete spec.passedChecksCount;
  delete spec.isPassed;

  const requestedFeatureId = String(body.featureId || "").trim();
  const isFeatureAction =
    action === "pass_feature" ||
    action === "reopen_feature" ||
    requestedFeatureId.length > 0;

  if (isFeatureAction) {
    const features = Array.isArray(spec.features) ? spec.features : [];
    const relVer = spec.releaseVersion || "v0.1";
    let targetFeat = null;
    if (requestedFeatureId) {
      const lowerReqF = requestedFeatureId.toLowerCase();
      targetFeat =
        features.find(
          (f) => f.id === requestedFeatureId || f.code.toLowerCase() === lowerReqF
        ) || null;
    } else if (action === "pass_feature") {
      targetFeat =
        features.find((f) => !isFeaturePassedForReleaseJs(f, relVer, releaseOrder)) ||
        features[0] ||
        null;
    } else if (action === "reopen_feature") {
      targetFeat = features[features.length - 1] || null;
    }
    if (!targetFeat) {
      const err = new Error(
        `Target Feature not found for "${requestedFeatureId || action}".`
      );
      err.statusCode = 404;
      throw err;
    }
    if (isFeatureLockedBaselineJs(targetFeat, relVer, releaseOrder)) {
      const err = new Error(
        `Feature ${targetFeat.code} is a locked ${targetFeat.introducedIn} baseline in ${relVer}.`
      );
      err.statusCode = 409;
      throw err;
    }

    if (action === "toggle_check") {
      const effList = getEffectiveChecksForReleaseJs(targetFeat, relVer);
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

      let matched = null;
      for (let i = 0; i < effList.length; i += 1) {
        if ((checkId && effList[i].id === checkId) || i === checkIdx) {
          matched = effList[i];
          break;
        }
      }
      if (!matched && oneBasedIdx >= 0 && oneBasedIdx < effList.length) {
        matched = effList[oneBasedIdx];
      }
      if (!matched && lowerCheckId) {
        matched = effList.find((c) => c.text.toLowerCase().includes(lowerCheckId)) || null;
      }
      if (!matched) {
        const err = new Error(
          `Matching Playtest check not found on ${targetFeat.code} for "${checkId || checkIdx}".`
        );
        err.statusCode = 404;
        throw err;
      }
      matched.passed = typeof body.passed === "boolean" ? body.passed : !matched.passed;
      const activeList = getEffectiveChecksForReleaseJs(targetFeat, relVer);
      const allEffPassed = activeList.every((c) => Boolean(c?.passed));
      if (targetFeat.status === "queued") {
        targetFeat.status = "active";
      } else if (targetFeat.status === "passed" && !allEffPassed) {
        targetFeat.status = "active";
      }
      syncEpicLifecycleFromFeaturesJs(spec, relVer, releaseOrder);
    } else if (action === "update_tuning" || action === "set_tuning") {
      const cleanKey = sanitizeGodotTuningKeyJs(body.key, "");
      const rawVal =
        body.value === undefined || body.value === null
          ? ""
          : String(body.value).trim();
      if (!cleanKey || !rawVal) {
        const err = new Error("Expected non-empty key and value for update_tuning.");
        err.statusCode = 400;
        throw err;
      }
      const rawUnit = String(body.unit || "").trim();
      const existing = targetFeat.tuning.find(
        (t) => t.key.toLowerCase() === cleanKey.toLowerCase()
      );
      const nextUnit = existing
        ? normalizeGodotUnitJs(existing.key, rawUnit || existing.unit, dimension)
        : normalizeGodotUnitJs(cleanKey, rawUnit, dimension);
      if (existing) {
        existing.value = rawVal;
        existing.unit = nextUnit;
      } else {
        targetFeat.tuning.push({ key: cleanKey, value: rawVal, unit: nextUnit });
      }
      for (const p of spec.tuning || []) {
        if (p.key.toLowerCase() === cleanKey.toLowerCase()) {
          p.value = rawVal;
          p.unit = nextUnit;
        }
      }
      if (targetFeat.status === "queued") {
        targetFeat.status = "active";
      }
      syncEpicLifecycleFromFeaturesJs(spec, relVer, releaseOrder);
    } else if (action === "log_fix") {
      const rawText = String(body.fixText || "")
        .trim()
        .replace(/^\[FIX\]\s*/i, "")
        .trim();
      const cleanText = sanitizeGodotLineJs(rawText, dimension);
      if (!cleanText) {
        const err = new Error("Expected non-empty fixText for log_fix.");
        err.statusCode = 400;
        throw err;
      }
      const newId =
        String(body.fixId || "").trim() ||
        `ffix_${nowMs}_${Math.random().toString(36).slice(2, 6)}`;
      targetFeat.fixes.push({
        id: newId,
        text: cleanText,
        resolved: false,
        createdAtMs: Number(nowMs) || Date.now(),
      });
      targetFeat.status = "active";
      syncEpicLifecycleFromFeaturesJs(spec, relVer, releaseOrder);
    } else if (action === "resolve_fix") {
      const targetId = String(body.fixId || "").trim();
      const nextResolved = body.resolved !== false;
      let matched = false;
      if (targetId === "latest") {
        for (let i = targetFeat.fixes.length - 1; i >= 0; i -= 1) {
          if (!targetFeat.fixes[i].resolved) {
            targetFeat.fixes[i].resolved = nextResolved;
            matched = true;
            break;
          }
        }
      } else if (targetId) {
        const lowerTarget = targetId.toLowerCase();
        for (const f of targetFeat.fixes) {
          if (f.id === targetId || String(f.text || "").toLowerCase() === lowerTarget) {
            f.resolved = nextResolved;
            matched = true;
          }
        }
        if (!matched && /^\d+$/.test(targetId)) {
          const oneBased = Number(targetId) - 1;
          const unresolved = targetFeat.fixes.filter((f) => !f.resolved);
          if (oneBased >= 0 && oneBased < unresolved.length) {
            unresolved[oneBased].resolved = nextResolved;
            matched = true;
          }
        }
        if (!matched) {
          for (const f of targetFeat.fixes) {
            if (!f.resolved && String(f.text || "").toLowerCase().includes(lowerTarget)) {
              f.resolved = nextResolved;
              matched = true;
              break;
            }
          }
        }
      }
      if (!matched && !targetId) {
        for (let i = targetFeat.fixes.length - 1; i >= 0; i -= 1) {
          if (!targetFeat.fixes[i].resolved) {
            targetFeat.fixes[i].resolved = nextResolved;
            break;
          }
        }
      }
      if (!nextResolved) {
        targetFeat.status = "active";
      }
      syncEpicLifecycleFromFeaturesJs(spec, relVer, releaseOrder);
    } else if (action === "pass_feature") {
      for (const f of targetFeat.fixes || []) f.resolved = true;
      for (const c of targetFeat.checks || []) c.passed = true;
      if (relVer !== "v0.1") {
        for (const c of targetFeat.releaseDeltaChecks || []) c.passed = true;
      }
      targetFeat.status = "passed";
      syncEpicLifecycleFromFeaturesJs(spec, relVer, releaseOrder);
    } else if (action === "reopen_feature") {
      targetFeat.status = "active";
      const hasDelta =
        relVer !== "v0.1" &&
        Boolean(String(targetFeat.releaseDelta || "").trim()) &&
        Array.isArray(targetFeat.releaseDeltaChecks) &&
        targetFeat.releaseDeltaChecks.length > 0;
      if (hasDelta) {
        for (const c of targetFeat.releaseDeltaChecks) c.passed = false;
      } else {
        for (const c of targetFeat.checks || []) c.passed = false;
      }
      if (spec.lifecycle === "stable" || spec.lifecycle === "queued") {
        const epicHasDelta =
          relVer !== "v0.1" &&
          ((Array.isArray(spec.upgradeDeltas) && spec.upgradeDeltas.length > 0) ||
            hasDelta ||
            features.some((f) => String(f.releaseDelta || "").trim() !== ""));
        spec.lifecycle = epicHasDelta ? "upgrading" : "active";
      }
    } else {
      const err = new Error(`Unsupported Godot Feature action: ${action}`);
      err.statusCode = 400;
      throw err;
    }

    for (const f of spec.features) {
      delete f.openFixes;
      delete f.openFixesCount;
      delete f.passedChecksCount;
      delete f.isPassed;
      delete f.isLockedBaseline;
      delete f.isPassedForRelease;
      delete f.effectiveChecks;
      delete f.totalChecksCount;
    }
  } else {
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
    const rawText = String(body.fixText || "")
      .trim()
      .replace(/^\[FIX\]\s*/i, "")
      .trim();
    const cleanText = sanitizeGodotLineJs(rawText, dimension);
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
    if (!wasSynthesizedLegacy && Array.isArray(spec.features)) {
      const relVer = spec.releaseVersion || "v0.1";
      for (const ft of spec.features) {
        if (isFeatureLockedBaselineJs(ft, relVer, releaseOrder)) continue;
        for (const f of ft.fixes || []) f.resolved = true;
        for (const c of ft.checks || []) c.passed = true;
        if (relVer !== "v0.1") {
          for (const c of ft.releaseDeltaChecks || []) c.passed = true;
        }
        ft.status = "passed";
      }
    }
  } else if (action === "reopen_epic") {
    const relVer = spec.releaseVersion || "v0.1";
    if (
      !wasSynthesizedLegacy &&
      Array.isArray(spec.features) &&
      spec.features.length > 0 &&
      (!Array.isArray(spec.upgradeDeltas) || spec.upgradeDeltas.length === 0) &&
      spec.features.every((ft) => isFeatureLockedBaselineJs(ft, relVer, releaseOrder))
    ) {
      const err = new Error(`Epic ${spec.code} is a locked ${relVer} baseline.`);
      err.statusCode = 409;
      throw err;
    }
    if (
      relVer !== "v0.1" &&
      Array.isArray(spec.upgradeDeltas) &&
      spec.upgradeDeltas.length > 0
    ) {
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
      if (!wasSynthesizedLegacy && Array.isArray(spec.features)) {
        const relVer = spec.releaseVersion || "v0.1";
        for (const ft of spec.features) {
          if (isFeatureLockedBaselineJs(ft, relVer, releaseOrder)) continue;
          ft.status = "active";
          if (Array.isArray(ft.releaseDeltaChecks) && ft.releaseDeltaChecks.length > 0) {
            for (const c of ft.releaseDeltaChecks) c.passed = false;
          } else {
            for (const c of ft.checks || []) c.passed = false;
          }
        }
      }
    } else {
      spec.lifecycle = "active";
      for (const c of spec.checks) c.passed = false;
      if (!wasSynthesizedLegacy && Array.isArray(spec.features)) {
        const relVer = spec.releaseVersion || "v0.1";
        for (const ft of spec.features) {
          if (isFeatureLockedBaselineJs(ft, relVer, releaseOrder)) continue;
          ft.status = "active";
          for (const c of ft.checks || []) c.passed = false;
        }
      }
    }
  } else {
    const err = new Error(`Unsupported Godot Epic action: ${action}`);
    err.statusCode = 400;
    throw err;
  }

  if (wasSynthesizedLegacy) {
    delete spec.features;
  } else if (Array.isArray(spec.features)) {
    for (const f of spec.features) {
      delete f.openFixes;
      delete f.openFixesCount;
      delete f.passedChecksCount;
      delete f.isPassed;
      delete f.isLockedBaseline;
      delete f.isPassedForRelease;
      delete f.effectiveChecks;
      delete f.totalChecksCount;
    }
  }
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

function buildGodotSyncProjectSectionsJs({
  existingSections = null,
  payload,
  liveGodotContext = null,
  nowMs,
  explicitEpicId = "",
  explicitFeatureId = "",
  isReadOnlyPull = false,
  action = "",
  epicCompletedOnPass = false,
}) {
  const nextProjSec = {
    last_godot_sync_ms: String(nowMs),
  };
  if (liveGodotContext) {
    nextProjSec.godot_live_context_json = JSON.stringify(liveGodotContext);
  }

  const activeEpicId = String(payload?.activeEpic?.id || "").trim();
  const activeFeatureId = String(payload?.activeFeature?.id || "").trim();

  if (isReadOnlyPull) {
    if (String(explicitEpicId || "").trim() && activeEpicId) {
      nextProjSec.selected_epic_id = activeEpicId;
    }
    if (String(explicitFeatureId || "").trim() && activeFeatureId) {
      nextProjSec.selected_feature_id = activeFeatureId;
    }
    return nextProjSec;
  }

  if (epicCompletedOnPass) {
    nextProjSec.selected_epic_id = activeEpicId;
    nextProjSec.selected_feature_id = activeFeatureId;
    return nextProjSec;
  }

  if (action === "pass_feature") {
    nextProjSec.selected_epic_id = activeEpicId;
    nextProjSec.selected_feature_id = activeFeatureId;
    return nextProjSec;
  }

  const cleanExplicitFeatureId = String(explicitFeatureId || "").trim();
  const hasBlankSelectedFeature =
    existingSections &&
    typeof existingSections === "object" &&
    Object.prototype.hasOwnProperty.call(existingSections, "selected_feature_id") &&
    String(existingSections.selected_feature_id || "").trim() === "";
  const existingEpicId = String(existingSections?.selected_epic_id || "").trim();
  if (
    action === "sync_project" &&
    !cleanExplicitFeatureId &&
    hasBlankSelectedFeature &&
    (!existingEpicId || existingEpicId === activeEpicId)
  ) {
    if (activeEpicId) {
      nextProjSec.selected_epic_id = activeEpicId;
    }
    nextProjSec.selected_feature_id = "";
    return nextProjSec;
  }

  if (activeEpicId) {
    nextProjSec.selected_epic_id = activeEpicId;
  }
  nextProjSec.selected_feature_id = activeFeatureId;
  return nextProjSec;
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
      const preferredFeatureId = String(body.featureId || "").trim();

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
        preferredFeatureId,
      });
      if (!payload.ok) {
        res.status(404).json({
          error: { code: 404, message: payload.error || "Project not found." },
        });
        return;
      }

      const nowMs = String(Date.now());
      const existingPullSections =
        docsById.get(linkAuth.projectId)?.sections &&
        typeof docsById.get(linkAuth.projectId)?.sections === "object"
          ? docsById.get(linkAuth.projectId).sections
          : null;
      const nextProjSections = buildGodotSyncProjectSectionsJs({
        existingSections: existingPullSections,
        payload,
        liveGodotContext,
        nowMs,
        explicitEpicId: preferredEpicId,
        explicitFeatureId: preferredFeatureId,
        isReadOnlyPull: true,
      });

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
    // Route 3D: POST /godotLink/update (Godot Dock: toggle_check / update_tuning / log_fix / resolve_fix / pass_feature / reopen_feature / pass_epic / reopen_epic / sync_project / build_feature / fix_feature / build_epic / fix_epic)
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
              "Expected valid action (toggle_check, update_tuning, log_fix, resolve_fix, pass_feature, reopen_feature, pass_epic, reopen_epic, sync_project, build_feature, fix_feature, build_epic, or fix_epic).",
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
      const requestedFeatureId = String(body.featureId || "").trim();

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
      const projDocForRel = docsById.get(linkAuth.projectId);
      const releaseOrder = (
        Array.isArray(projDocForRel?.childrenIds) ? projDocForRel.childrenIds : []
      )
        .map((id) => docsById.get(id))
        .filter((d) => d && String(d.tier || "").toUpperCase() === "RELEASE")
        .map((r) => resolveVersionTag(r));

      // 1-Click In-Dock Cloud Gemini AI Builder (build_feature / fix_feature / build_epic / fix_epic)
      if (
        action === "build_epic" ||
        action === "fix_epic" ||
        action === "build_feature" ||
        action === "fix_feature"
      ) {
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
          preferredFeatureId: requestedFeatureId,
        });
        if (!payload.ok || !payload.activeEpic) {
          res.status(404).json({
            error: { code: 404, message: payload.error || "Active Epic not found." },
          });
          return;
        }

        const requestedProtocol = String(body.agentProtocol || "").trim();
        if (requestedProtocol === "multi_turn_v1") {
          const stepResp = await runGodotMultiTurnStepWithGemini({
            apiKey,
            mode: action,
            rootSpec: payload.rootSpec,
            epicSpec: payload.activeEpic,
            featureSpec: payload.activeFeature || null,
            siblingFeaturesSummary: payload.siblingFeaturesSummary || [],
            godotContextMarkdown:
              payload.activeFeatureContextMarkdown || payload.godotContextMarkdown,
            projectManifest: body.projectManifest || null,
            toolHistory: body.toolHistory || [],
            turnIndex: body.turnIndex,
            maxTurns: body.maxTurns,
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
          if (!stepResp.ok) {
            res.status(502).json({
              error: {
                code: 502,
                message: stepResp.error || "Gemini Feature agent step failed.",
              },
            });
            return;
          }

          if (
            stepResp.turnIndex === 1 ||
            stepResp.agentStep?.type === "final_bundle"
          ) {
            const nextProjSec = {
              last_godot_sync_ms: String(nowMs),
              selected_epic_id: payload.activeEpic.id,
              selected_feature_id: payload.activeFeature?.id || "",
            };
            if (liveGodotContext) {
              nextProjSec.godot_live_context_json = JSON.stringify(liveGodotContext);
            }
            linkAuth.linkRef.set({ lastSyncAt: nowMs }, { merge: true }).catch(() => {});
            docsCol
              .doc(linkAuth.projectId)
              .set({ sections: nextProjSec }, { merge: true })
              .catch(() => {});
          }

          const { rootSpec: _rs, releaseEpics: _re, ...clientPayload } = payload;
          res.status(200).json({
            ...clientPayload,
            mode: action,
            agentProtocol: "multi_turn_v1",
            model: stepResp.model,
            turnIndex: stepResp.turnIndex,
            maxTurns: stepResp.maxTurns,
            agentStep: stepResp.agentStep,
            ...(stepResp.agentStep?.type === "final_bundle"
              ? { agentBundle: stepResp.agentStep.bundle }
              : {}),
          });
          return;
        }

        const agentResp = await runGodotEpicAgentWithGemini({
          apiKey,
          mode: action,
          rootSpec: payload.rootSpec,
          epicSpec: payload.activeEpic,
          featureSpec: payload.activeFeature || null,
          siblingFeaturesSummary: payload.siblingFeaturesSummary || [],
          godotContextMarkdown:
            payload.activeFeatureContextMarkdown || payload.godotContextMarkdown,
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
          selected_feature_id: payload.activeFeature?.id || "",
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
              releaseOrder,
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
      const epicCompletedOnPass =
        action === "pass_epic" ||
        (action === "pass_feature" && Boolean(updatedEpicDoc?.isCompleted));
      const inMemProj = docsById.get(linkAuth.projectId);
      const prevProjSec =
        inMemProj?.sections && typeof inMemProj.sections === "object"
          ? { ...inMemProj.sections }
          : null;
      if (inMemProj) {
        const existingSec =
          inMemProj.sections && typeof inMemProj.sections === "object"
            ? { ...inMemProj.sections }
            : {};
        existingSec.last_godot_sync_ms = String(nowMs);
        if (liveGodotContext) {
          existingSec.godot_live_context_json = JSON.stringify(liveGodotContext);
        }
        if (epicCompletedOnPass) {
          existingSec.selected_epic_id = "";
          existingSec.selected_feature_id = "";
        } else if (action === "pass_feature") {
          existingSec.selected_epic_id = targetEpicId;
          existingSec.selected_feature_id = "";
        } else if (targetEpicId) {
          existingSec.selected_epic_id = targetEpicId;
          if (requestedFeatureId) {
            existingSec.selected_feature_id = requestedFeatureId;
          }
        }
        inMemProj.sections = existingSec;
      }

      const stayOnEpic = !epicCompletedOnPass && action !== "sync_project";
      const stayOnFeature =
        action !== "pass_epic" && action !== "pass_feature" && action !== "sync_project";
      const payload = computeActiveGodotEpicPayload({
        docsById,
        projectId: linkAuth.projectId,
        webStudioUrl: linkAuth.webStudioUrl,
        liveGodotContext,
        preferredEpicId: stayOnEpic ? targetEpicId : "",
        preferredFeatureId: stayOnFeature ? requestedFeatureId : "",
      });
      if (!payload.ok) {
        res.status(404).json({
          error: { code: 404, message: payload.error || "Project not found." },
        });
        return;
      }

      const nextProjSec = buildGodotSyncProjectSectionsJs({
        existingSections: prevProjSec,
        payload,
        liveGodotContext,
        nowMs,
        explicitEpicId: targetEpicId,
        explicitFeatureId: requestedFeatureId,
        action,
        epicCompletedOnPass,
      });

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
  scaleGodotTuningValueJs,
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
};
