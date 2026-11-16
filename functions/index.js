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

async function verifyUnrealLinkToken(req) {
  const rawToken = extractBearerLinkToken(req);
  if (!rawToken) {
    return {
      errorStatus: 401,
      errorMessage: "Missing or invalid Unreal Project Link Token (lyr_...).",
    };
  }
  const tokenHash = hashLinkToken(rawToken);
  const snap = await getFirestore()
    .collection("unreal_links")
    .where("tokenHash", "==", tokenHash)
    .limit(1)
    .get();
  if (snap.empty) {
    return {
      errorStatus: 401,
      errorMessage: "Invalid or expired Unreal Project Link Token.",
    };
  }
  const linkDoc = snap.docs[0];
  const data = linkDoc.data() || {};
  if (data.revoked === true || !data.uid || !data.projectId) {
    return {
      errorStatus: 401,
      errorMessage: "This Unreal Project Link Token has been revoked.",
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

function parseRootSpecJs(projectDoc) {
  const parsed =
    parseJsonObjectSafe(projectDoc?.sections?.concept_blueprint_json) || {};
  const rawEngine = String(
    parsed.targetEngine || projectDoc?.sections?.engine || "ue5Mcp"
  )
    .trim()
    .toLowerCase();
  const isUe6 = rawEngine === "ue6verse" || rawEngine.includes("verse") || rawEngine.includes("ue6");
  const targetEngine = isUe6 ? "ue6Verse" : "ue5Mcp";
  const rawTitle = String(
    parsed.gameTitle || projectDoc?.title || "UNTITLED UNREAL PROJECT"
  ).trim();
  const normalizedTitle = rawTitle || "UNTITLED UNREAL PROJECT";
  const coreFeel = resolveCoreFeelJs(parsed.feelChoiceId);

  return {
    gameTitle: normalizedTitle,
    normalizedTitle,
    targetEngine,
    pitch: String(parsed.pitch || projectDoc?.sections?.goal || "").trim(),
    coreLoop: normalizeStringArrayJs(parsed.coreLoop),
    cameraContract: String(
      parsed.cameraContract ||
        "SpringArm 1450 cm @ -52 deg pitch, 55 deg FOV, CameraLag 9.0"
    ).trim(),
    characterScale: String(
      parsed.characterScale ||
        "ACharacter CapsuleRadius 42 cm · HalfHeight 92 cm · MaxWalkSpeed 620 cm/s"
    ).trim(),
    inputContract: String(
      parsed.inputContract ||
        "Enhanced Input (IMC_Core + IA_Move / IA_Aim / IA_Primary / IA_Secondary)"
    ).trim(),
    assetPolicy: String(
      parsed.assetPolicy ||
        "Prototype Greybox Primitives (Engine/BasicShapes) + Debug Materials; UDataAsset for tuning"
    ).trim(),
    feelChoiceId: coreFeel.id,
    coreFeelLabel: coreFeel.label,
    pillars: normalizeStringArrayJs(parsed.pillars),
    tradeOffs: Array.isArray(parsed.tradeOffs)
      ? parsed.tradeOffs.map(formatTradeOffJs).filter(Boolean)
      : [],
    outOfScope: normalizeStringArrayJs(parsed.outOfScope),
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

function sanitizeTuningKeyJs(rawKey, fallback = "TuningVar") {
  const trimmed = String(rawKey || "").trim();
  if (!trimmed) return fallback;
  if (/^[A-Za-z][A-Za-z0-9]*$/.test(trimmed)) {
    if (
      trimmed.length >= 2 &&
      trimmed[0] === "b" &&
      trimmed[1] === trimmed[1].toUpperCase() &&
      trimmed[1] !== trimmed[1].toLowerCase()
    ) {
      return trimmed;
    }
    return trimmed[0].toUpperCase() + trimmed.slice(1);
  }
  const tokens = trimmed.split(/[^A-Za-z0-9]+/).filter(Boolean);
  if (tokens.length === 0) return fallback;
  const joined = tokens.map((t) => t[0].toUpperCase() + t.slice(1)).join("");
  if (/^[0-9]/.test(joined)) return `Param${joined}`;
  return joined;
}

function normalizeTuningUnitJs(key, rawUnit) {
  const cleanUnit = String(rawUnit || "").trim();
  const lowerUnit = cleanUnit.toLowerCase();
  const lowerKey = String(key || "").toLowerCase();
  if (
    lowerUnit === "px" ||
    lowerUnit === "pixels" ||
    lowerUnit === "pixel" ||
    lowerUnit === "uu"
  ) {
    return "cm";
  }
  if (lowerUnit.startsWith("px/")) return `cm/${cleanUnit.slice(3)}`;
  if (lowerUnit.startsWith("pixels/")) return `cm/${cleanUnit.slice(7)}`;
  if (
    lowerUnit === "sec" ||
    lowerUnit === "secs" ||
    lowerUnit === "second" ||
    lowerUnit === "seconds"
  ) {
    return "s";
  }
  if (lowerUnit === "deg" || lowerUnit === "degree" || lowerUnit === "degrees") {
    return "deg";
  }
  if (
    lowerUnit === "pct" ||
    lowerUnit === "percent" ||
    lowerUnit === "percentage"
  ) {
    return "%";
  }
  if (cleanUnit) return cleanUnit;
  if (
    lowerKey.includes("speed") ||
    lowerKey.includes("velocity") ||
    lowerKey.includes("impulse") ||
    lowerKey.includes("accel") ||
    lowerKey.includes("decel")
  ) {
    return "cm/s";
  }
  if (
    lowerKey.includes("distance") ||
    lowerKey.includes("radius") ||
    lowerKey.includes("height") ||
    lowerKey.includes("range") ||
    lowerKey.includes("offset") ||
    lowerKey.includes("width") ||
    lowerKey.includes("length") ||
    lowerKey.includes("springarm") ||
    lowerKey.includes("boomarm")
  ) {
    return "cm";
  }
  if (
    lowerKey.includes("angle") ||
    lowerKey.includes("fov") ||
    lowerKey.includes("pitch") ||
    lowerKey.includes("yaw") ||
    lowerKey.includes("roll") ||
    lowerKey.includes("spread") ||
    lowerKey.includes("deg")
  ) {
    return "deg";
  }
  if (
    lowerKey.includes("time") ||
    lowerKey.includes("duration") ||
    lowerKey.includes("cooldown") ||
    lowerKey.includes("delay") ||
    lowerKey.includes("window")
  ) {
    return "s";
  }
  if (
    lowerKey.includes("chance") ||
    lowerKey.includes("percent") ||
    lowerKey.includes("pct")
  ) {
    return "%";
  }
  if (lowerKey.includes("rate")) {
    return "%/s";
  }
  if (
    lowerKey.includes("mult") ||
    lowerKey.includes("scale") ||
    lowerKey.includes("factor")
  ) {
    return "x";
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
  return "count";
}

function inferTuningPropertyTypeJs(value, unit, isUe6Verse = false) {
  const cleanVal = String(value || "").trim().toLowerCase();
  const cleanUnit = String(unit || "").trim().toLowerCase();
  if (
    cleanUnit === "bool" ||
    cleanUnit === "boolean" ||
    cleanVal === "true" ||
    cleanVal === "false"
  ) {
    return isUe6Verse ? "logic" : "bool";
  }
  if (cleanUnit === "count" && /^-?\d+$/.test(cleanVal)) {
    return isUe6Verse ? "int" : "int32";
  }
  return "float";
}

function parseEpicSpecJs(epicDoc, indexHint = 0) {
  const sec =
    epicDoc?.sections && typeof epicDoc.sections === "object"
      ? epicDoc.sections
      : {};
  const parsed = parseJsonObjectSafe(sec.epic_spec_json) || {};
  const fallbackCode = `E${String(indexHint + 1).padStart(2, "0")}`;
  const code =
    String(sec.code || parsed.code || fallbackCode).trim() ||
    fallbackCode;
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
          action: String(c.action || "IA_Action").trim(),
          trigger: String(c.trigger || "Pressed (Tap)").trim(),
          rule: String(c.rule || "").trim(),
        }))
    : [];

  const tuning = Array.isArray(parsed.tuning)
    ? parsed.tuning
        .filter((t) => t && typeof t === "object")
        .map((t) => {
          const cleanKey = sanitizeTuningKeyJs(t.key, "TuningVar");
          return {
            key: cleanKey,
            value: String(t.value ?? "0").trim() || "0",
            unit: normalizeTuningUnitJs(cleanKey, t.unit),
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

function sanitizeUprojectContextJs(raw) {
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
    current_level: cleanStr(raw.current_level),
    game_mode: cleanStr(raw.game_mode),
    default_pawn: cleanStr(raw.default_pawn),
    input_assets: cleanArr(raw.input_assets, 16),
    blueprint_assets: cleanArr(raw.blueprint_assets, 16),
    data_assets: cleanArr(raw.data_assets, 12),
    widget_assets: cleanArr(raw.widget_assets, 12),
    level_assets: cleanArr(raw.level_assets, 10),
    verse_files: cleanArr(raw.verse_files, 12),
    recent_errors: cleanArr(raw.recent_errors, 8),
  };
}

function renderServerUnrealMcpPayloadJs({
  rootSpec,
  epicSpec,
  uprojectContext,
}) {
  const isUe6 = rootSpec?.targetEngine === "ue6Verse";
  const archContract = isUe6
    ? "Verse Components + Scene Graph Entities (@editable exposed fields)"
    : "Blueprint Actors/Components + PrimaryDataAsset (EditAnywhere tuning)";
  const inputContractLabel = isUe6
    ? "Enhanced Input → Verse InputAction"
    : "Enhanced Input (UInputAction + IMC_Core)";
  const tuningColLabel = isUe6
    ? "@editable Verse Field"
    : "DataAsset / Details Var";

  const lines = [];
  lines.push(`# ROOT_MCP_CONTEXT · ${rootSpec.normalizedTitle}`);
  lines.push(`Target Architecture: ${archContract}`);
  lines.push("");
  lines.push("## §01 Concept & 30s Core Loop");
  lines.push(`- Vision: ${rootSpec.pitch}`);
  if (Array.isArray(rootSpec.coreLoop) && rootSpec.coreLoop.length > 0) {
    lines.push(`- Loop: ${rootSpec.coreLoop.join(" -> ")}`);
  }
  lines.push("");
  lines.push("## §02 Global Unreal Contracts (1 UU = 1 cm)");
  lines.push(`- Camera & Boom: ${rootSpec.cameraContract}`);
  lines.push(`- Player Scale: ${rootSpec.characterScale}`);
  lines.push(`- Input Contract: ${rootSpec.inputContract}`);
  lines.push(`- Asset Policy: ${rootSpec.assetPolicy}`);
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

  if (uprojectContext && typeof uprojectContext === "object" && Object.keys(uprojectContext).length > 0) {
    lines.push("");
    lines.push("## Live Unreal Project Snapshot (.uproject via LayersBridge)");
    const projName = String(uprojectContext.project_name || "").trim();
    const level = String(uprojectContext.current_level || "").trim();
    const gameMode = String(uprojectContext.game_mode || "").trim();
    const pawn = String(uprojectContext.default_pawn || "").trim();
    if (projName) lines.push(`- Project: ${projName}`);
    if (level) lines.push(`- Open Level: ${level}`);
    if (gameMode) lines.push(`- GameMode: ${gameMode}`);
    if (pawn) lines.push(`- DefaultPawnClass: ${pawn}`);
    const pushSnapshotList = (label, rawList, cap) => {
      if (!Array.isArray(rawList) || rawList.length === 0) return;
      const clean = rawList
        .map((item) => String(item ?? "").trim())
        .filter(Boolean)
        .slice(0, cap);
      if (clean.length === 0) return;
      lines.push(`- ${label}: ${clean.join(", ")}`);
    };
    pushSnapshotList("Existing Enhanced Input Assets", uprojectContext.input_assets, 12);
    pushSnapshotList("Existing Blueprints", uprojectContext.blueprint_assets, 12);
    pushSnapshotList("Existing DataAssets & Tables", uprojectContext.data_assets, 8);
    pushSnapshotList("Existing UMG Widgets", uprojectContext.widget_assets, 8);
    pushSnapshotList("Existing Levels", uprojectContext.level_assets, 6);
    pushSnapshotList("Existing Verse Files", uprojectContext.verse_files, 8);
    if (Array.isArray(uprojectContext.recent_errors) && uprojectContext.recent_errors.length > 0) {
      lines.push("- Recent Editor/PIE Log Warnings:");
      for (const err of uprojectContext.recent_errors.slice(0, 4)) {
        lines.push(`  - ${err}`);
      }
    }
  }

  const openFixes = Array.isArray(epicSpec.openFixes)
    ? epicSpec.openFixes
    : (epicSpec.fixes || []).filter((f) => !f.resolved);

  lines.push("");
  lines.push("---");
  lines.push("");
  lines.push(
    `# ACTIVE EPIC SPEC · ${epicSpec.code} · ${epicSpec.title} (${epicSpec.releaseVersion})`
  );
  if (openFixes.length > 0) {
    lines.push(
      `Execution Mode: FOCUSED PIE REVISION PASS (${openFixes.length} OPEN [FIX]) — surgical edits only; keep passing checks intact`
    );
  } else {
    lines.push("Execution Mode: FULL-EPIC AUTONOMOUS BUILD & SELF-CHECK");
  }
  lines.push("");
  lines.push("## §01 System Intent & Actor Links");
  if (epicSpec.coreLoopBeat) {
    lines.push(`- Core Loop Beat: ${epicSpec.coreLoopBeat}`);
  }
  lines.push(`- Goal: ${epicSpec.goal}`);
  if (epicSpec.links.length > 0) {
    lines.push(`- Links: ${epicSpec.links.join(" · ")}`);
  }
  if (epicSpec.outOfScope.length > 0) {
    lines.push(`- Out of Scope: ${epicSpec.outOfScope.join("; ")}`);
  }
  if (
    Array.isArray(epicSpec.baselineSummary) &&
    epicSpec.baselineSummary.length > 0 &&
    (epicSpec.releaseVersion !== "v0.1" || epicSpec.upgradeDeltas.length > 0)
  ) {
    lines.push(`- Locked Baseline: ${epicSpec.baselineSummary.join(" · ")}`);
  }

  if (epicSpec.upgradeDeltas.length > 0) {
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
  lines.push(`## §02 Controls (${inputContractLabel})`);
  if (epicSpec.controls.length === 0) {
    lines.push("- None (passive/system-driven Epic)");
  } else {
    for (const c of epicSpec.controls) {
      lines.push(`- ${c.action} | ${c.trigger} | ${c.rule}`);
    }
  }

  lines.push("");
  lines.push("## §03 State Flow & Interrupt Rules");
  if (epicSpec.states.length === 0 && epicSpec.interrupts.length === 0) {
    lines.push("- Stateless / event-driven Epic");
  } else {
    for (const s of epicSpec.states) {
      lines.push(`- State: ${s}`);
    }
    for (const rule of epicSpec.interrupts) {
      lines.push(`- Interrupt: ${rule}`);
    }
  }

  lines.push("");
  lines.push(`## §04 Spatial & Exposed Tuning (${tuningColLabel})`);
  if (epicSpec.tuning.length === 0) {
    lines.push("- None");
  } else {
    for (const t of epicSpec.tuning) {
      const unitSuffix = t.unit ? ` ${t.unit}` : "";
      const propType = inferTuningPropertyTypeJs(t.value, t.unit, isUe6);
      lines.push(`- ${t.key}: ${t.value}${unitSuffix} [${propType}]`);
    }
  }

  lines.push("");
  lines.push("## §05 Viewport, UMG & Audio Cues");
  if (epicSpec.feedback.length === 0) {
    lines.push("- Minimal greybox debug visuals");
  } else {
    for (const f of epicSpec.feedback) {
      lines.push(`- ${f}`);
    }
  }

  lines.push("");
  lines.push("## §06 Test Level Staging & PIE Acceptance Gate");
  if (epicSpec.levelStaging) {
    lines.push(`- Test Level: ${epicSpec.levelStaging}`);
  }
  epicSpec.checks.forEach((chk, i) => {
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
    lines.push(`### FOCUSED PIE REVISION PASS (${openFixes.length} OPEN [FIX])`);
    lines.push(
      "Targeted edits only to resolve every open [FIX] item above; keep already-passing checks intact, compile/save modified Blueprint/Verse assets, and report via layers_resolve_pie_fix(fix_id) + layers_toggle_pie_check(check_id, passed=true). Do NOT call layers_pass_active_epic (reserved for human PIE sign-off)."
    );
  } else {
    lines.push("");
    lines.push("### FULL-EPIC AUTONOMOUS BUILD & SELF-CHECK");
    lines.push(
      "Implement §01-§06 in one Unreal MCP pass matching ROOT_MCP_CONTEXT contracts, expose every §04 tuning variable, then run PIE self-check against every §06 Check and call layers_toggle_pie_check(check_id, passed=true). Do NOT call layers_pass_active_epic (reserved for human PIE sign-off)."
    );
  }

  return lines.join("\n").trimRight();
}

function computeActiveUnrealEpicPayload({
  docsById,
  projectId,
  webStudioUrl = DEFAULT_WEB_STUDIO_URL,
  uprojectContext = null,
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
      mcpPayloadMarkdown: "",
    };
  }

  const rootSpec = parseRootSpecJs(projectDoc);
  const projSections =
    projectDoc.sections && typeof projectDoc.sections === "object"
      ? projectDoc.sections
      : {};
  const liveCtx =
    uprojectContext && typeof uprojectContext === "object"
      ? uprojectContext
      : parseJsonObjectSafe(projSections.unreal_live_context_json);

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
      targetEngine: rootSpec.targetEngine,
      releaseVersion: "v0.1",
      releaseTitle: "",
      epicPosition: 0,
      totalEpics: 0,
      allEpicsCompleted: false,
      webStudioUrl,
      activeEpic: null,
      mcpPayloadMarkdown: renderServerUnrealMcpPayloadJs({
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
        uprojectContext: liveCtx,
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

  const parsedEpics = epicDocs.map((d, idx) => parseEpicSpecJs(d, idx));
  if (parsedEpics.length === 0) {
    return {
      ok: true,
      projectId: projectDoc.id,
      projectTitle: rootSpec.normalizedTitle,
      targetEngine: rootSpec.targetEngine,
      releaseVersion,
      releaseTitle: String(activeRel.title || releaseVersion),
      epicPosition: 0,
      totalEpics: 0,
      allEpicsCompleted: false,
      webStudioUrl,
      activeEpic: null,
      mcpPayloadMarkdown: "",
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

  const mcpPayloadMarkdown = renderServerUnrealMcpPayloadJs({
    rootSpec,
    epicSpec: activeEpic,
    uprojectContext: liveCtx,
  });

  return {
    ok: true,
    projectId: projectDoc.id,
    projectTitle: rootSpec.normalizedTitle,
    targetEngine: rootSpec.targetEngine,
    releaseVersion,
    releaseTitle: String(activeRel.title || releaseVersion),
    epicPosition: activeIdx + 1,
    totalEpics: parsedEpics.length,
    allEpicsCompleted,
    webStudioUrl: epicStudioUrl,
    activeEpic,
    mcpPayloadMarkdown,
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
    const payload = computeActiveUnrealEpicPayload({
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
    const parsed = parseEpicSpecJs(doc, i);
    if (
      parsed.code.toLowerCase() === lowerReq ||
      parsed.lineageKey.toLowerCase() === lowerReq
    ) {
      return String(doc.id);
    }
  }

  return reqId;
}

const UNREAL_UPDATE_VALID_ACTIONS = new Set([
  "toggle_check",
  "update_tuning",
  "set_tuning",
  "log_fix",
  "resolve_fix",
  "pass_epic",
  "reopen_epic",
  "sync_uproject",
]);

function applyUnrealEpicMutationJs({
  epicDoc,
  action,
  body = {},
  nowMs = Date.now(),
}) {
  const sec =
    epicDoc?.sections && typeof epicDoc.sections === "object"
      ? { ...epicDoc.sections }
      : {};
  const spec = parseEpicSpecJs(epicDoc);
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
        `Matching PIE check not found for "${checkId || checkIdx}".`
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
    const cleanKey = sanitizeTuningKeyJs(body.key, "");
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
      existing.unit = normalizeTuningUnitJs(existing.key, rawUnit || existing.unit);
    } else {
      spec.tuning.push({
        key: cleanKey,
        value: rawVal,
        unit: normalizeTuningUnitJs(cleanKey, rawUnit),
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
    const err = new Error(`Unsupported Unreal Epic action: ${action}`);
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
  sec.last_unreal_sync_ms = String(nowMs);

  const subtasks = spec.checks.map((c) => ({
    id: c.id,
    text: c.text,
    completed: Boolean(c.passed),
  }));

  return { sections: sec, isCompleted, subtasks, epicSpec: spec };
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
    // Route 3B: POST /unrealLink/token (Google Sign-In auth: generate/reuse/rotate lyr_... token)
    // -------------------------------------------------------------------------
    if (cleanPath === "/unrealLink/token") {
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
      const linkRef = db.collection("unreal_links").doc(linkDocId);
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
    // Route 3C: GET / POST /unrealLink/epic (LayersBridge: ROOT_MCP_CONTEXT + 1 active Epic Spec)
    // -------------------------------------------------------------------------
    if (cleanPath === "/unrealLink/epic") {
      if (req.method !== "GET" && req.method !== "POST") {
        res.status(405).json({ error: { code: 405, message: "Expected GET or POST." } });
        return;
      }
      const linkAuth = await verifyUnrealLinkToken(req);
      if (linkAuth.errorStatus) {
        res.status(linkAuth.errorStatus).json({
          error: { code: linkAuth.errorStatus, message: linkAuth.errorMessage },
        });
        return;
      }

      const body = req.method === "POST" ? parseJsonBody(req) : {};
      const uprojectContext = sanitizeUprojectContextJs(body.uprojectContext);

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

      const payload = computeActiveUnrealEpicPayload({
        docsById,
        projectId: linkAuth.projectId,
        webStudioUrl: linkAuth.webStudioUrl,
        uprojectContext,
      });
      if (!payload.ok) {
        res.status(404).json({
          error: { code: 404, message: payload.error || "Project not found." },
        });
        return;
      }

      const nowMs = String(Date.now());
      const nextProjSections = {
        last_unreal_sync_ms: nowMs,
      };
      if (uprojectContext) {
        nextProjSections.unreal_live_context_json = JSON.stringify(uprojectContext);
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

      res.status(200).json(payload);
      return;
    }

    // -------------------------------------------------------------------------
    // Route 3D: POST /unrealLink/update (LayersBridge: toggle_check / log_fix / resolve_fix / pass_epic / reopen_epic / sync_uproject)
    // -------------------------------------------------------------------------
    if (cleanPath === "/unrealLink/update") {
      if (req.method !== "POST") {
        res.status(405).json({ error: { code: 405, message: "Expected POST." } });
        return;
      }
      const linkAuth = await verifyUnrealLinkToken(req);
      if (linkAuth.errorStatus) {
        res.status(linkAuth.errorStatus).json({
          error: { code: linkAuth.errorStatus, message: linkAuth.errorMessage },
        });
        return;
      }

      const body = parseJsonBody(req);
      const action = String(body.action || "").trim();
      if (!UNREAL_UPDATE_VALID_ACTIONS.has(action)) {
        res.status(400).json({
          error: {
            code: 400,
            message:
              "Expected valid action (toggle_check, update_tuning, log_fix, resolve_fix, pass_epic, reopen_epic, or sync_uproject).",
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

      const uprojectContext = sanitizeUprojectContextJs(body.uprojectContext);

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
      if (action !== "sync_uproject") {
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
      let updatedEpicDoc = null;
      if (action !== "sync_uproject") {
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
            const mutated = applyUnrealEpicMutationJs({
              epicDoc: { id: snap.id, ...epicData },
              action,
              body,
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
        existingSec.last_unreal_sync_ms = String(nowMs);
        if (uprojectContext) {
          existingSec.unreal_live_context_json = JSON.stringify(uprojectContext);
        }
        if (action === "pass_epic") {
          existingSec.selected_epic_id = "";
        } else if (targetEpicId) {
          existingSec.selected_epic_id = targetEpicId;
        }
        inMemProj.sections = existingSec;
      }

      const isInPlaceMutation = action !== "pass_epic" && action !== "sync_uproject";
      const payload = computeActiveUnrealEpicPayload({
        docsById,
        projectId: linkAuth.projectId,
        webStudioUrl: linkAuth.webStudioUrl,
        uprojectContext,
        preferredEpicId: isInPlaceMutation ? targetEpicId : "",
      });
      if (!payload.ok) {
        res.status(404).json({
          error: { code: 404, message: payload.error || "Project not found." },
        });
        return;
      }

      const nextProjSec = {
        last_unreal_sync_ms: String(nowMs),
      };
      if (uprojectContext) {
        nextProjSec.unreal_live_context_json = JSON.stringify(uprojectContext);
      }
      if (payload.activeEpic?.id) {
        nextProjSec.selected_epic_id = payload.activeEpic.id;
      }

      linkAuth.linkRef.set({ lastSyncAt: nowMs }, { merge: true }).catch(() => {});
      docsCol
        .doc(linkAuth.projectId)
        .set({ sections: nextProjSec }, { merge: true })
        .catch(() => {});

      res.status(200).json(payload);
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
  UNREAL_UPDATE_VALID_ACTIONS,
  sanitizeTuningKeyJs,
  normalizeTuningUnitJs,
  inferTuningPropertyTypeJs,
  sanitizeUprojectContextJs,
  parseRootSpecJs,
  parseEpicSpecJs,
  renderServerUnrealMcpPayloadJs,
  computeActiveUnrealEpicPayload,
  resolveTargetEpicDocIdJs,
  applyUnrealEpicMutationJs,
};
