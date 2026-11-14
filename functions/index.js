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

function extractResPath(raw) {
  const match = String(raw || "").match(/res:\/\/[A-Za-z0-9_./-]+/);
  return match ? match[0] : "";
}

function resolveVersionTag(relDoc) {
  const v = String(relDoc?.sections?.version || "").trim();
  if (v) return v.startsWith("v") ? v : `v${v}`;
  const m = String(relDoc?.title || "").match(/v?(\d+\.\d+(?:\.\d+)?)/i);
  return m ? `v${m[1]}` : "v0.1";
}

function parseFeatureStates(featDoc) {
  const raw = String(featDoc?.sections?.states || "").trim();
  if (!raw) return [];
  try {
    const parsed = JSON.parse(raw);
    return Array.isArray(parsed) ? parsed : [];
  } catch (_) {
    return [];
  }
}

function collectLeafChecklistItems(items, out = []) {
  if (!Array.isArray(items)) return out;
  for (const item of items) {
    if (!item || typeof item !== "object") continue;
    const children = Array.isArray(item.children) ? item.children : [];
    if (children.length === 0) {
      out.push(item);
    } else {
      collectLeafChecklistItems(children, out);
    }
  }
  return out;
}

function countLeafChecklist(item) {
  const children = Array.isArray(item?.children) ? item.children : [];
  if (children.length === 0) {
    return { total: 1, done: item?.completed ? 1 : 0 };
  }
  let total = 0;
  let done = 0;
  for (const c of children) {
    const counts = countLeafChecklist(c);
    total += counts.total;
    done += counts.done;
  }
  return { total, done };
}

function isCheckpointStepsDone(cp) {
  const leaves = collectLeafChecklistItems(cp?.checklist || []);
  return leaves.length > 0 && leaves.every((s) => Boolean(s.completed));
}

function selectActiveCheckpoint(states, activeVer) {
  if (!Array.isArray(states) || states.length === 0) return null;
  const matching = states.filter(
    (s) => String(s?.parameters?.releaseVersion || "v0.1").trim() === activeVer
  );
  if (matching.length > 0) {
    return matching[matching.length - 1];
  }
  const firstIncomplete = states.find(
    (s) =>
      !isCheckpointStepsDone(s) ||
      String(s?.parameters?.playtestPassed || "") !== "true"
  );
  return firstIncomplete || states[states.length - 1];
}

const STEP_ROLE_ALIASES = {
  editor_setup: "editor_setup",
  scene: "editor_setup",
  scene_setup: "editor_setup",
  node_setup: "editor_setup",
  initial_setup: "editor_setup",
  inspector_setup: "inspector_setup",
  inspector: "inspector_setup",
  input_setup: "inspector_setup",
  properties: "inspector_setup",
  script_logic: "script_logic",
  code: "script_logic",
  gdscript: "script_logic",
  input_handling: "script_logic",
  physics: "script_logic",
  logic: "script_logic",
  wire_and_verify: "wire_and_verify",
  wire: "wire_and_verify",
  wiring_and_feel: "wire_and_verify",
  signal_wiring: "wire_and_verify",
  verify: "wire_and_verify",
  fix: "fix",
  playtest_fix: "fix",
  bugfix: "fix",
  bug: "fix",
};

const ASSET_STOP_WORDS = new Set([
  "create", "build", "implement", "implementation", "playtest", "add", "wire",
  "hook", "up", "setup", "set", "bind", "apply", "enforce", "verify", "test",
  "the", "and", "for", "with", "in", "on", "to", "of", "a", "an", "core",
  "state", "player", "interaction", "mechanics", "controls", "logic", "pass",
  "stage", "checkpoint", "checkpoints", "milestone", "phase", "step", "task",
  "version", "system", "systems", "controller", "controllers", "mechanic",
  "manager", "managers", "module", "handler", "service", "feature", "structure",
]);

function normalizeStepRoleJs(rawRole) {
  const sr = String(rawRole || "").trim().toLowerCase();
  return STEP_ROLE_ALIASES[sr] || "";
}

function stripDiffLinePrefixes(rawCode) {
  return String(rawCode || "")
    .split(/\r?\n/)
    .map((line) => (line.startsWith("+ ") ? line.slice(2) : line))
    .join("\n")
    .trim();
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

function fnv1aHash6Js(text) {
  let h = 0x811c9dc5;
  const s = String(text || "");
  for (let i = 0; i < s.length; i++) {
    h ^= s.charCodeAt(i);
    h = Math.imul(h, 0x01000193) >>> 0;
  }
  return h.toString(16).padStart(8, "0").slice(0, 6);
}

function stableCodeFileDocIdJs(projectId, resPath) {
  const norm = normalizeResPathJs(resPath) || "res://scripts/script.gd";
  const pathWithoutScheme = norm.replace(/^res:\/\//, "");
  const slug =
    pathWithoutScheme
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, "_")
      .replace(/^_+|_+$/g, "")
      .slice(0, 48) || "script";
  return `${projectId}_code_${slug}_${fnv1aHash6Js(norm)}`;
}

function extractBareGdScriptPathJs(raw, existingCodeFiles = null) {
  const text = String(raw || "");
  if (!text) return "";
  const explicit = extractResPathsListJs(text, ".gd");
  if (explicit.length > 0) return explicit[0];
  const re =
    /(?:^|[\s>`"'(,])([A-Za-z0-9_.-]+(?:\/[A-Za-z0-9_.-]+)*\.gd)(?=$|[\s<`"'),:;])/g;
  let match;
  while ((match = re.exec(text)) !== null) {
    const rel = String(match[1] || "").trim().replace(/^\/+/, "");
    if (!rel || !rel.endsWith(".gd")) continue;
    const baseName = rel.split("/").pop().toLowerCase();
    const candidate = normalizeResPathJs(
      rel.includes("/") ? `res://${rel}` : `res://scripts/${rel}`
    );
    if (existingCodeFiles && typeof existingCodeFiles === "object") {
      if (
        candidate &&
        Object.prototype.hasOwnProperty.call(existingCodeFiles, candidate)
      ) {
        return candidate;
      }
      for (const key of Object.keys(existingCodeFiles)) {
        const normKey = normalizeResPathJs(key);
        if (
          normKey.toLowerCase() === candidate.toLowerCase() ||
          normKey.toLowerCase().endsWith(`/${baseName}`)
        ) {
          return normKey;
        }
      }
    }
    return candidate;
  }
  return "";
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

function collectFeatureScriptPathsJs(feat, steps, existingCodeFiles = null) {
  const ordered = [];
  const seen = new Set();
  const explicitSet = new Set();
  const addPath = (p, isExplicit) => {
    const norm = normalizeResPathJs(p);
    if (!norm || !norm.endsWith(".gd")) return;
    if (isExplicit) explicitSet.add(norm);
    if (!seen.has(norm)) {
      seen.add(norm);
      ordered.push(norm);
    }
  };
  const addFrom = (txt, isExplicit = true) => {
    for (const p of extractResPathsListJs(txt, ".gd")) {
      addPath(p, isExplicit);
    }
    const bare = extractBareGdScriptPathJs(txt, existingCodeFiles);
    if (bare) addPath(bare, isExplicit);
  };
  addFrom(feat?.sections?.primary_asset || "", true);
  addFrom(feat?.sections?.assets || "", true);
  addFrom(feat?.sections?.goal || "", true);
  for (const s of Array.isArray(steps) ? steps : []) {
    addFrom(s?.codeSnippet || s?.rawCopyCode || "", true);
    addFrom(s?.locationLabel || "", true);
    addFrom(s?.instruction || "", true);
    addFrom(s?.area1Hierarchy || "", true);
    addFrom(s?.area2Inspector || "", true);
    addFrom(s?.stepPath || s?.resPath || "", false);
  }
  if (
    existingCodeFiles &&
    typeof existingCodeFiles === "object" &&
    ordered.length > 1
  ) {
    const snake = toSnakeCaseAssetJs(feat?.title || "gameplay_feature");
    const derivedFallback = normalizeResPathJs(`res://scripts/${snake}.gd`);
    const filtered = ordered.filter(
      (p) =>
        p !== derivedFallback ||
        explicitSet.has(p) ||
        Object.prototype.hasOwnProperty.call(existingCodeFiles, p)
    );
    if (filtered.length > 0) return filtered;
  }
  return ordered;
}

function collectProjectCodeFilesJs(docsById) {
  const out = {};
  const latestTsByPath = {};
  if (!docsById || typeof docsById.values !== "function") return out;
  for (const d of docsById.values()) {
    if (!d || String(d.tier || "").toUpperCase() !== "CODEFILE") continue;
    const resPath = normalizeResPathJs(d?.sections?.res_path || "");
    if (!resPath) continue;
    const ts =
      Number(
        d?.sections?.updated_at_ms || d?.updatedAtMs || d?.updated_at_ms || 0
      ) || 0;
    if (
      !Object.prototype.hasOwnProperty.call(out, resPath) ||
      ts >= (latestTsByPath[resPath] || 0)
    ) {
      out[resPath] = String(d?.sections?.content || "");
      latestTsByPath[resPath] = ts;
    }
  }
  return out;
}

function detectArenaScenePathJs(docsById, candidateEpics, activeIdx) {
  const allTscns = [];
  const seen = new Set();
  const pushTscn = (raw) => {
    for (const p of extractResPathsListJs(raw, ".tscn")) {
      if (!seen.has(p)) {
        seen.add(p);
        allTscns.push(p);
      }
    }
  };
  if (Array.isArray(candidateEpics)) {
    for (const ep of candidateEpics) {
      for (const f of ep?.features || []) {
        pushTscn(f?.primaryAsset || "");
        for (const s of f?.steps || []) {
          pushTscn(s?.stepPath || s?.resPath || "");
          pushTscn(s?.area1Hierarchy || "");
          pushTscn(s?.instruction || "");
        }
      }
    }
  }
  if (docsById && typeof docsById.values === "function") {
    for (const d of docsById.values()) {
      pushTscn(d?.sections?.primary_asset || "");
      pushTscn(d?.sections?.assets || "");
    }
  }
  const preferredKeywords = ["arena", "main", "world", "level", "island", "stage", "game"];
  for (const kw of preferredKeywords) {
    const match = allTscns.find((p) => p.toLowerCase().includes(kw));
    if (match) return match;
  }
  if (
    Array.isArray(candidateEpics) &&
    activeIdx >= 0 &&
    candidateEpics[activeIdx]?.features?.length
  ) {
    for (const f of candidateEpics[activeIdx].features) {
      if (String(f?.primaryAsset || "").endsWith(".tscn")) {
        return f.primaryAsset;
      }
    }
  }
  return allTscns[0] || "";
}

function findCodeFileDocByResPathJs(docsById, resPath) {
  const norm = normalizeResPathJs(resPath);
  if (!norm || !docsById) return null;
  for (const d of docsById.values()) {
    if (!d || String(d.tier || "").toUpperCase() !== "CODEFILE") continue;
    if (normalizeResPathJs(d?.sections?.res_path || "") === norm) {
      return d;
    }
  }
  return null;
}

const VALID_SCENE_OPS = new Set([
  "ensure_node",
  "set_property",
  "attach_script",
  "detach_script",
  "connect_signal",
  "instance_scene",
  "remove_node",
  "add_to_group",
]);

function normalizeAgentBundle(rawObj, mode) {
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
    const normalized = {
      op,
      scenePath: normalizeResPathJs(opObj.scenePath || opObj.scene_path || ""),
      nodePath: String(opObj.nodePath || opObj.node_path || "").trim(),
      parentPath: String(opObj.parentPath || opObj.parent_path || "").trim(),
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
    };
    sceneOps.push(normalized);
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
    if (!action) continue;
    inputOps.push({ action, keys });
  }
  return {
    mode: String(obj.mode || mode || "direct_agent").trim(),
    summary: String(obj.summary || "").trim(),
    diagnosis: String(obj.diagnosis || "").trim(),
    scriptUpdates,
    sceneOps,
    inputOps,
  };
}

async function callGeminiFlashJson({ apiKey, systemInstruction, userPrompt }) {
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
        maxOutputTokens: 8192,
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
                thinkingConfig: { thinkingLevel: "LOW" },
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

async function runGodotAgentWithGemini({
  apiKey,
  mode,
  projectTitle,
  projectDoc,
  feature,
  featDoc,
  codeFiles,
  liveScripts,
  sceneSnapshot,
  prompt,
  errorText,
  arenaScenePath,
  featureScenePath,
}) {
  const mergedScripts = { ...(codeFiles || {}) };
  if (liveScripts && typeof liveScripts === "object") {
    for (const [k, v] of Object.entries(liveScripts)) {
      const norm = normalizeResPathJs(k);
      if (norm && typeof v === "string") mergedScripts[norm] = v;
    }
  }

  const featureStepsSummary = (feature?.steps || []).map((s, idx) => ({
    index: idx + 1,
    role: s.role || s.stepRole || "",
    title: s.title || "",
    stepPath: s.stepPath || s.resPath || "",
    locationLabel: s.locationLabel || "",
    instruction: s.instruction || "",
    area1Hierarchy: s.area1Hierarchy || "",
    area2Inspector: s.area2Inspector || "",
    codeSnippet: String(s.codeSnippet || s.rawCopyCode || "").slice(0, 2400),
    verifyResult: s.verifyResult || "",
  }));

  const systemInstruction = [
    "You are LAYERS Godot Agent Co-Builder targeting Godot 4.7.2.stable.",
    "Return strictly valid JSON with keys: mode, summary, diagnosis, scriptUpdates, sceneOps, inputOps.",
    "STRICT ENGINE & OUTPUT RULES:",
    "1. NEVER emit push_warning(...) placeholders or stub comments. Emit real runnable GDScript and real sceneOps.",
    "2. scriptUpdates: array of { resPath, attachTo, scenePath, language: 'gdscript', content }. Always output COMPLETE, cohesive, compile-clean Godot 4 .gd files (no '+ ' diff prefixes, no 'const X := [...]' untyped const arrays, no speculative preload() on missing files; prefer '@export var foo_scene: PackedScene' + set_property sceneOp).",
    "3. sceneOps: array of structured scene mutations. Supported op values:",
    "   - ensure_node: { op:'ensure_node', scenePath, parentPath, nodeName, nodeType, subResourceClass, subResourceProps, properties, groups }",
    "   - set_property: { op:'set_property', scenePath, nodePath, properties }",
    "   - attach_script: { op:'attach_script', scenePath, nodePath, scriptPath }",
    "   - detach_script: { op:'detach_script', scenePath, nodePath }",
    "   - connect_signal: { op:'connect_signal', scenePath, sourcePath, signalName, targetPath, methodName }",
    "   - instance_scene: { op:'instance_scene', scenePath, parentPath, nodeName, instancePath, properties, groups }",
    "   - remove_node: { op:'remove_node', scenePath, nodePath }",
    "   - add_to_group: { op:'add_to_group', scenePath, nodePath, groups }",
    "4. ClassDB SAFETY: NEVER attach a script whose 'extends <Class>' is incompatible with the target node's Godot class (e.g. NEVER attach a CharacterBody3D script to a Node3D arena root — emit detach_script if live snapshot shows a mismatch!).",
    "5. SIGNAL & ARITY SAFETY: Connect signals ONLY to a node whose attached script defines methodName (typically targetPath: '.' for a sub-scene root, or the child instance name in the arena scene). NEVER connect a Timer signal to itself. Match signal & callback parameter counts across scripts: if a signal emits payload arguments (e.g. 'signal totem_selected(totem_id: String)') and a connected method needs 0 arguments (e.g. 'spawn_next_wave'), give the method an optional default parameter ('func spawn_next_wave(_arg: Variant = null) -> void:').",
    "6. FEEL TUNING: Expose key gameplay tuning numbers cleanly with '@export var ...' at the top of scripts (speeds, ranges, cooldowns, counts) so the native dock renders SpinBoxes automatically.",
    "7. MATERIALS & SHAPES: When creating meshes or colliders, specify explicit subResourceClass + subResourceProps (e.g. radius, height, size) and properties (monitoring, wait_time, one_shot, autostart, albedo_color, emission).",
    "8. SCENE TREE & _ready() SAFETY: Never call 'get_parent().add_child(...)' synchronously inside '_ready()' (Godot throws 'Parent node is busy setting up children'). Use 'add_child.call_deferred(node)' or add spawned instances to a child container / post-ready method. Always call 'add_child(inst)' BEFORE setting 'inst.global_position' or 'inst.global_transform'.",
    "9. CLEAN ENTITY LIFECYCLE: Enemies, projectiles, and temporary wave spawns MUST clean up cleanly with 'queue_free()' on death or expiry so wave spawner 'tree_exited' / child checks advance reliably.",
    "10. CAMERA & CURSOR ACCESSIBILITY: Whenever capturing the mouse ('Input.mouse_mode = Input.MOUSE_MODE_CAPTURED'), ALWAYS wire an 'ESC' ('ui_cancel') release/capture toggle in '_unhandled_input'.",
    "11. GROUNDED SPAWNS & INPUT BINDINGS: Spawn characters cleanly on the playable floor (never floating meters above Y=0 unless flying) and ensure every input action in 'inputOps' has a real Key or Mouse Button binding (never empty events).",
    "12. INPUT OPS: Whenever GDScript uses custom Input actions (Input.is_action_*, Input.get_vector, Input.get_axis, event.is_action_*), declare them in inputOps: [{ action: 'action_name', keys: ['SHIFT'] }] using standard tokens ('W','A','S','D','SPACE','SHIFT','CTRL','E','Q','F','R','TAB','LMB','RMB','MMB').",
    "13. UI OVERLAYS, PAUSE & BOUND SIGNALS: UI panels/HUDs/menus/draft overlays in 3D games MUST use a 'CanvasLayer' or 'Control' scene root (NEVER parent Control/Container nodes directly under a 'Node3D', because Node3D.visible=false does NOT hide CanvasItem children). When pausing gameplay ('get_tree().paused = true') for clickable UI, ALWAYS set 'process_mode = Node.PROCESS_MODE_ALWAYS' AND 'Input.mouse_mode = Input.MOUSE_MODE_VISIBLE' on open (restoring 'MOUSE_MODE_CAPTURED' on close if 3D mouselook is active). NEVER emit 0-arg 'connect_signal' sceneOps for callbacks requiring bound arguments (connect '.bind(...)' in '_ready()' instead). Attach reusable sub-scene scripts directly to the sub-scene root (scenePath: 'res://scenes/foo.tscn', attachTo: '.'), populate '@export var ...: NodePath' properties on arena instances (with a 'get_tree().get_first_node_in_group(\"player\")' fallback in '_ready()'), and use 'ProgressBar' inside explicit layout containers ('MarginContainer'/'VBoxContainer'/'HBoxContainer' with 'custom_minimum_size') rather than textureless 'TextureProgressBar' or controls stacked at (0, 0).",
  ].join("\n");

  const projSections = projectDoc?.sections || {};
  const contextPayload = {
    mode,
    projectTitle: String(projectTitle || "LAYERS Project"),
    gameSpec: String(projSections.game_spec || projSections.gameSpec || "").slice(0, 800),
    techSpec: String(projSections.tech_spec || projSections.techSpec || projSections.tech_stack || "").slice(0, 800),
    godotContract: String(projSections.godot_contract || "").slice(0, 1400),
    arenaScenePath: String(arenaScenePath || ""),
    featureScenePath: String(featureScenePath || feature?.primaryAsset || ""),
    feature: {
      id: feature?.id || featDoc?.id || "",
      title: feature?.title || featDoc?.title || "Feature",
      primaryAsset: feature?.primaryAsset || "",
      doneWhen: feature?.doneWhen || "",
      goal: String(featDoc?.sections?.goal || ""),
      scriptPaths: feature?.scriptPaths || [],
      steps: featureStepsSummary,
    },
    userPrompt: String(prompt || "").trim(),
    errorText: String(errorText || "").trim(),
    liveScripts: mergedScripts,
    liveSceneSnapshot: sceneSnapshot || {},
  };

  const userPrompt = [
    mode === "build_feature"
      ? "TASK: Synthesize the complete, playable GDScript files and exact sceneOps needed to build this Feature cleanly into the Godot project so it compiles and playtests immediately."
      : mode === "diagnose_fix"
      ? "TASK: Diagnose the Godot runtime/editor/scene problem from the error text, live scripts, and live scene snapshot, then return real scriptUpdates and/or sceneOps that completely fix it."
      : "TASK: Apply the developer's requested gameplay tweak or bug fix cleanly across both live scripts (scriptUpdates) and Godot scenes (sceneOps).",
    "PROJECT CONTEXT JSON:",
    JSON.stringify(contextPayload),
  ].join("\n\n");

  const aiResp = await callGeminiFlashJson({
    apiKey,
    systemInstruction,
    userPrompt,
  });
  if (!aiResp.ok) {
    return { ok: false, error: aiResp.error || "Gemini agent request failed." };
  }
  const bundle = normalizeAgentBundle(aiResp.data, mode);
  if (!bundle.summary) {
    bundle.summary =
      mode === "build_feature"
        ? `Built ${feature?.title || "feature"} script(s) & scene ops.`
        : "Applied scene and script updates.";
  }
  return { ok: true, model: aiResp.model, bundle };
}

function markFeatureScaffoldStepsCompletedJs(states, checkpointId) {
  let changed = false;
  const markItems = (items) => {
    if (!Array.isArray(items)) return items;
    return items.map((item) => {
      if (!item || typeof item !== "object") return item;
      const children = Array.isArray(item.children) ? item.children : [];
      if (children.length > 0) {
        const nextChildren = markItems(children);
        const nextItem = { ...item, children: nextChildren };
        const counts = countLeafChecklist(nextItem);
        const allChildDone = counts.total > 0 && counts.done === counts.total;
        if (Boolean(item.completed) !== allChildDone) {
          changed = true;
        }
        return { ...nextItem, completed: allChildDone };
      }
      const notes = decodeThreeAreaNotesJs(item.specNotes || "");
      const isFix = notes.stepRole === "fix" || String(item.title || "").startsWith("[FIX]");
      if (!isFix && !item.completed) {
        changed = true;
        return { ...item, completed: true };
      }
      return item;
    });
  };
  const updatedStates = (Array.isArray(states) ? states : []).map((st) => {
    if (!st || typeof st !== "object") return st;
    if (checkpointId && String(st.id || "") !== checkpointId) return st;
    return { ...st, checklist: markItems(st.checklist || []) };
  });
  return { updatedStates, changed };
}

function preparePendingCodeWritesJs({
  docsById,
  docsCol,
  projectId,
  scriptUpdates,
}) {
  const dedupedUpdates = new Map();
  for (const u of scriptUpdates || []) {
    if (u && u.resPath) dedupedUpdates.set(u.resPath, u);
  }
  const pendingCodeWrites = [];
  for (const u of dedupedUpdates.values()) {
    const existing = findCodeFileDocByResPathJs(docsById, u.resPath);
    const docId = existing
      ? existing.id
      : stableCodeFileDocIdJs(projectId, u.resPath);
    pendingCodeWrites.push({
      docId,
      ref: docsCol.doc(docId),
      update: u,
    });
  }
  return pendingCodeWrites;
}

function applyCodeFileWritesInTxJs({
  tx,
  projRef,
  projSnap,
  docsById,
  projectId,
  pendingCodeWrites,
  codeSnaps,
  activeVer = "",
  featureId = "",
  nowMs = Date.now(),
}) {
  const addedCodeIds = [];
  for (let i = 0; i < pendingCodeWrites.length; i++) {
    const w = pendingCodeWrites[i];
    const existingSnap = codeSnaps[i];
    const existingData = existingSnap.exists ? existingSnap.data() || {} : {};
    let featureIds = [];
    try {
      const parsedIds = JSON.parse(existingData?.sections?.feature_ids || "[]");
      if (Array.isArray(parsedIds)) featureIds = parsedIds.map(String);
    } catch (_) {}
    if (featureId && !featureIds.includes(featureId)) featureIds.push(featureId);

    const fileName = w.update.resPath.split("/").pop() || "script.gd";
    const resolvedVer =
      activeVer || String(existingData?.sections?.release_version || "");
    const codeDoc = {
      id: w.docId,
      title: fileName,
      tier: "CODEFILE",
      parentId: projectId,
      childrenIds: [],
      sections: {
        ...(existingData.sections || {}),
        res_path: w.update.resPath,
        content: w.update.content,
        language: w.update.language || "gdscript",
        release_version: resolvedVer,
        feature_ids: JSON.stringify(featureIds),
        updated_at_ms: String(nowMs),
      },
      subtasks: Array.isArray(existingData.subtasks) ? existingData.subtasks : [],
      phase: String(existingData.phase || ""),
      isInbox: false,
      isIcebox: false,
      isCompleted: false,
    };
    tx.set(w.ref, codeDoc, { merge: true });
    docsById.set(w.docId, codeDoc);
    if (!existingSnap.exists) {
      addedCodeIds.push(w.docId);
    }
  }

  if (projSnap.exists) {
    const projData = projSnap.data() || {};
    const childrenIds = Array.isArray(projData.childrenIds)
      ? [...projData.childrenIds]
      : [];
    let projChanged = false;
    for (const cid of addedCodeIds) {
      if (!childrenIds.includes(cid)) {
        childrenIds.push(cid);
        projChanged = true;
      }
    }
    const nextProjSections = {
      ...(projData.sections || {}),
      last_godot_sync_ms: String(Date.now()),
    };
    const projUpdate = { sections: nextProjSections };
    if (projChanged) projUpdate.childrenIds = childrenIds;
    tx.update(projRef, projUpdate);
    docsById.set(projectId, {
      id: projectId,
      ...projData,
      sections: nextProjSections,
      ...(projChanged ? { childrenIds } : {}),
    });
  }
}

async function handleSyncLiveScriptsRoute({ linkAuth, body, res }) {
  const rawScripts = body?.scripts ?? body?.liveScripts;
  if (!rawScripts || typeof rawScripts !== "object" || Array.isArray(rawScripts)) {
    res.status(400).json({ error: { code: 400, message: "Missing scripts map." } });
    return;
  }

  const normalizedUpdates = [];
  for (const [rawPath, rawContent] of Object.entries(rawScripts)) {
    if (normalizedUpdates.length >= 40) break;
    const resPath = normalizeResPathJs(String(rawPath || ""));
    if (!resPath.startsWith("res://") || !resPath.endsWith(".gd")) continue;
    const content = typeof rawContent === "string" ? rawContent : "";
    if (!content.trim()) continue;
    normalizedUpdates.push({
      resPath,
      content: content.slice(0, 65536),
      language: "gdscript",
    });
  }

  const db = getFirestore();
  const docsCol = db
    .collection("users")
    .doc(linkAuth.uid)
    .collection("documents");
  const docsSnap = await docsCol.get();
  const docsById = new Map();
  for (const d of docsSnap.docs) {
    docsById.set(d.id, { id: d.id, ...d.data() });
  }

  const projDoc = docsById.get(linkAuth.projectId);
  const activeVer = String(projDoc?.sections?.active_release_version || "");
  const pendingCodeWrites = preparePendingCodeWritesJs({
    docsById,
    docsCol,
    projectId: linkAuth.projectId,
    scriptUpdates: normalizedUpdates,
  });

  const projRef = docsCol.doc(linkAuth.projectId);
  const nowMs = Date.now();
  await db.runTransaction(async (tx) => {
    const [projSnap, ...codeSnaps] = await Promise.all([
      tx.get(projRef),
      ...pendingCodeWrites.map((w) => tx.get(w.ref)),
    ]);
    applyCodeFileWritesInTxJs({
      tx,
      projRef,
      projSnap,
      docsById,
      projectId: linkAuth.projectId,
      pendingCodeWrites,
      codeSnaps,
      activeVer,
      nowMs,
    });
  });

  linkAuth.linkRef.set({ lastSyncAt: nowMs }, { merge: true }).catch(() => {});
  res.status(200).json({
    ok: true,
    syncedCount: pendingCodeWrites.length,
    syncedAtMs: nowMs,
  });
}

async function handleGodotAgentActionRoute({ req, res, linkAuth, body }) {
  const action = String(body.action || "").trim();
  const featureId = String(body.featureId || "").trim();
  const checkpointId = String(body.checkpointId || "").trim();

  if (!featureId) {
    res.status(400).json({
      error: { code: 400, message: "Missing featureId." },
    });
    return;
  }

  const db = getFirestore();
  const docsCol = db.collection("users").doc(linkAuth.uid).collection("documents");
  const docsSnap = await docsCol.get();
  const docsById = new Map();
  for (const snap of docsSnap.docs) {
    docsById.set(snap.id, { id: snap.id, ...snap.data() });
  }

  const featDoc = docsById.get(featureId);
  const projectDoc = docsById.get(linkAuth.projectId);
  if (!featDoc || !projectDoc) {
    res.status(404).json({
      error: { code: 404, message: "Linked project or feature not found." },
    });
    return;
  }

  const basePayload = computeActiveEpicPayload({
    docsById,
    projectId: linkAuth.projectId,
    webStudioUrl: linkAuth.webStudioUrl,
  });
  const activeVer = String(basePayload.releaseVersion || "v0.1");

  let featureObj = null;
  for (const f of basePayload?.activeEpic?.features || []) {
    if (String(f.id) === featureId) {
      featureObj = f;
      break;
    }
  }
  if (!featureObj) {
    featureObj = {
      id: featureId,
      title: String(featDoc.title || "Feature"),
      primaryAsset: extractResPath(featDoc?.sections?.primary_asset || ""),
      doneWhen: "",
      steps: [],
      scriptPaths: [],
    };
  }

  if (action === "complete_feature_steps") {
    const featRef = docsCol.doc(featureId);
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(featRef);
      if (!snap.exists) return;
      const d = snap.data() || {};
      const parsedStates = parseFeatureStates({ sections: d.sections });
      const { updatedStates, changed } = markFeatureScaffoldStepsCompletedJs(
        parsedStates,
        checkpointId || String(featureObj.checkpointId || "")
      );
      if (!changed) return;
      const nextSections = {
        ...(d.sections || {}),
        states: JSON.stringify(updatedStates),
      };
      const nextSubtasks = rebuildDocSubtasksFromStates(updatedStates);
      tx.update(featRef, { sections: nextSections, subtasks: nextSubtasks });
      docsById.set(featureId, {
        id: featureId,
        ...d,
        sections: nextSections,
        subtasks: nextSubtasks,
      });
    });
    const nextPayload = computeActiveEpicPayload({
      docsById,
      projectId: linkAuth.projectId,
      webStudioUrl: linkAuth.webStudioUrl,
    });
    res.status(200).json(nextPayload);
    return;
  }

  const apiKey = String(GEMINI_API_KEY.value() || "").trim();
  if (!apiKey) {
    res.status(500).json({
      error: { code: 500, message: "Server Gemini API key is not configured." },
    });
    return;
  }

  const agentResp = await runGodotAgentWithGemini({
    apiKey,
    mode: action,
    projectTitle: projectDoc.title,
    projectDoc,
    feature: featureObj,
    featDoc,
    codeFiles: basePayload.codeFiles,
    liveScripts: body.liveScripts,
    sceneSnapshot: body.sceneSnapshot,
    prompt: body.prompt,
    errorText: body.errorText,
    arenaScenePath: body.arenaScenePath || basePayload.arenaScenePath,
    featureScenePath: body.featureScenePath || featureObj.primaryAsset,
  });

  if (!agentResp.ok) {
    res.status(502).json({
      error: {
        code: 502,
        message: agentResp.error || "Gemini agent request failed.",
      },
    });
    return;
  }

  const bundle = agentResp.bundle;
  const nowMs = Date.now();
  const pendingCodeWrites = preparePendingCodeWritesJs({
    docsById,
    docsCol,
    projectId: linkAuth.projectId,
    scriptUpdates: bundle.scriptUpdates,
  });

  const projRef = docsCol.doc(linkAuth.projectId);
  const featRef = docsCol.doc(featureId);

  await db.runTransaction(async (tx) => {
    // 1. All reads before any writes (Firestore transaction requirement).
    const [projSnap, featSnap, ...codeSnaps] = await Promise.all([
      tx.get(projRef),
      tx.get(featRef),
      ...pendingCodeWrites.map((w) => tx.get(w.ref)),
    ]);

    applyCodeFileWritesInTxJs({
      tx,
      projRef,
      projSnap,
      docsById,
      projectId: linkAuth.projectId,
      pendingCodeWrites,
      codeSnaps,
      activeVer,
      featureId,
      nowMs,
    });


    if (action === "build_feature" && featSnap.exists) {
      const fData = featSnap.data() || {};
      const parsedStates = parseFeatureStates({ sections: fData.sections });
      const { updatedStates, changed } = markFeatureScaffoldStepsCompletedJs(
        parsedStates,
        checkpointId || String(featureObj.checkpointId || "")
      );
      const fallbackPrimary = String(featureObj?.primaryAsset || "").trim();
      const hasPrimary = Boolean(
        String(fData?.sections?.primary_asset || "").trim()
      );
      if (changed || (!hasPrimary && fallbackPrimary)) {
        const nextSections = {
          ...(fData.sections || {}),
          states: JSON.stringify(updatedStates),
          ...(!hasPrimary && fallbackPrimary
            ? { primary_asset: fallbackPrimary }
            : {}),
        };
        const nextSubtasks = rebuildDocSubtasksFromStates(updatedStates);
        tx.update(featRef, { sections: nextSections, subtasks: nextSubtasks });
        docsById.set(featureId, {
          id: featureId,
          ...fData,
          sections: nextSections,
          subtasks: nextSubtasks,
        });
      }
    }
  });

  const finalPayload = computeActiveEpicPayload({
    docsById,
    projectId: linkAuth.projectId,
    webStudioUrl: linkAuth.webStudioUrl,
  });
  res.status(200).json({
    ...finalPayload,
    agentBundle: bundle,
    model: agentResp.model,
  });
}


function decodeThreeAreaNotesJs(rawSpecNotes) {
  const empty = {
    instruction: "",
    area1Hierarchy: "",
    area2Inspector: "",
    verifyMode: "",
    stepRole: "",
    diagnosis: "",
    scriptPatch: null,
    shortTitle: "",
  };
  const raw = String(rawSpecNotes || "");
  if (!raw.trim()) return empty;

  if (raw.trim().startsWith("{")) {
    try {
      const notes = JSON.parse(raw);
      if (notes && typeof notes === "object") {
        const sr = normalizeStepRoleJs(notes.stepRole);
        const vm = String(notes.verifyMode || "").trim().toLowerCase();
        return {
          instruction: String(notes.instruction || "").trim(),
          area1Hierarchy: String(notes.area1Hierarchy || "").trim(),
          area2Inspector: String(notes.area2Inspector || "").trim(),
          verifyMode: vm === "editor" || vm === "playtest" ? vm : "",
          stepRole: sr,
          diagnosis: String(notes.diagnosis || "").trim(),
          scriptPatch:
            notes.scriptPatch && typeof notes.scriptPatch === "object"
              ? notes.scriptPatch
              : null,
          shortTitle: String(notes.shortTitle || "").trim(),
        };
      }
    } catch (_) {}
  }

  let working = raw;
  let scriptPatch = null;
  let diagnosis = "";
  let stepRole = "";
  let verifyMode = "";
  let area2Inspector = "";
  let area1Hierarchy = "";

  const patchIdx = working.indexOf("\n[[SCRIPT_PATCH]]\n");
  if (patchIdx >= 0) {
    const patchRaw = working.slice(patchIdx + "\n[[SCRIPT_PATCH]]\n".length).trim();
    working = working.slice(0, patchIdx);
    if (patchRaw) {
      try {
        const parsedPatch = JSON.parse(patchRaw);
        if (parsedPatch && typeof parsedPatch === "object") {
          const replaceBlock = stripDiffLinePrefixes(parsedPatch.replaceBlock || "");
          if (replaceBlock) {
            scriptPatch = {
              resPath: extractResPath(parsedPatch.resPath || "") || String(parsedPatch.resPath || "").trim(),
              targetBlock: String(parsedPatch.targetBlock || ""),
              replaceBlock,
            };
          }
        }
      } catch (_) {}
    }
  }

  const diagIdx = working.indexOf("\n[[DIAGNOSIS]]\n");
  if (diagIdx >= 0) {
    diagnosis = working.slice(diagIdx + "\n[[DIAGNOSIS]]\n".length).trim();
    working = working.slice(0, diagIdx);
  }

  const srIdx = working.indexOf("\n[[STEP_ROLE]]\n");
  if (srIdx >= 0) {
    stepRole = normalizeStepRoleJs(
      working.slice(srIdx + "\n[[STEP_ROLE]]\n".length)
    );
    working = working.slice(0, srIdx);
  }

  const vmIdx = working.indexOf("\n[[VERIFY_MODE]]\n");
  if (vmIdx >= 0) {
    const vm = working
      .slice(vmIdx + "\n[[VERIFY_MODE]]\n".length)
      .trim()
      .toLowerCase();
    verifyMode = vm === "editor" || vm === "playtest" ? vm : "";
    working = working.slice(0, vmIdx);
  }

  const a2Idx = working.indexOf("\n[[AREA2]]\n");
  if (a2Idx >= 0) {
    area2Inspector = working.slice(a2Idx + "\n[[AREA2]]\n".length).trim();
    working = working.slice(0, a2Idx);
  }

  const a1Idx = working.indexOf("\n[[AREA1]]\n");
  if (a1Idx >= 0) {
    area1Hierarchy = working.slice(a1Idx + "\n[[AREA1]]\n".length).trim();
    working = working.slice(0, a1Idx);
  }

  return {
    instruction: working.trim(),
    area1Hierarchy,
    area2Inspector,
    verifyMode,
    stepRole,
    diagnosis,
    scriptPatch,
    shortTitle: "",
  };
}

function encodeThreeAreaNotesJs({
  instruction,
  area1Hierarchy = "",
  area2Inspector = "",
  verifyMode = "",
  stepRole = "",
  diagnosis = "",
  scriptPatch = null,
}) {
  let out = String(instruction || "").trim();
  const a1 = String(area1Hierarchy || "").trim();
  const a2 = String(area2Inspector || "").trim();
  const vm = String(verifyMode || "").trim().toLowerCase();
  const sr = normalizeStepRoleJs(stepRole);
  const diag = String(diagnosis || "").trim();

  if (a1) out += `\n[[AREA1]]\n${a1}`;
  if (a2) out += `\n[[AREA2]]\n${a2}`;
  if (vm === "editor" || vm === "playtest") {
    out += `\n[[VERIFY_MODE]]\n${vm}`;
  }
  if (sr) out += `\n[[STEP_ROLE]]\n${sr}`;
  if (diag) out += `\n[[DIAGNOSIS]]\n${diag}`;
  if (scriptPatch && typeof scriptPatch === "object" && scriptPatch.replaceBlock) {
    out += `\n[[SCRIPT_PATCH]]\n${JSON.stringify({
      resPath: String(scriptPatch.resPath || "").trim(),
      targetBlock: String(scriptPatch.targetBlock || ""),
      replaceBlock: stripDiffLinePrefixes(scriptPatch.replaceBlock),
    })}`;
  }
  return out;
}

function resolveStepShortTitle(subtask, decoded) {
  const noteObj = decoded || decodeThreeAreaNotesJs(subtask?.specNotes);
  let raw = noteObj.shortTitle || String(subtask?.text || "Step");
  raw = raw.replace(/^\s*STEP\s+\d+(?:\.\d+)?\s*(?:[·:\-—]\s*)?/i, "");
  raw = raw.replace(/\s*\([\d.]+\s*[hm]\)\s*$/i, "").trim();
  return raw || "Step";
}

function resolveStepRoleBadge(subtask, decoded, cleanTitle) {
  const noteObj = decoded || decodeThreeAreaNotesJs(subtask?.specNotes);
  const titleStr = String(cleanTitle || subtask?.text || "");
  const upperTitle = titleStr.toUpperCase();
  const sr = noteObj.stepRole || "";

  if (upperTitle.includes("[FIX]") || sr === "fix") {
    return "FIX";
  }
  if (sr === "inspector_setup") {
    return "INSP";
  }
  if (sr === "script_logic") {
    return "CODE";
  }

  const hasHierarchy = Boolean(noteObj.area1Hierarchy);
  const code = String(subtask?.codeSnippet || "").trim();
  const hasInspector =
    Boolean(noteObj.area2Inspector) ||
    (code.includes("|") && code.includes("---"));
  const lowerPath = String(subtask?.codeLanguage || "").toLowerCase();
  const lowerInstr = String(noteObj.instruction || "").toLowerCase();
  const lowerTitle = titleStr.toLowerCase();

  if (sr === "editor_setup") {
    if (
      !hasHierarchy &&
      (hasInspector ||
        lowerPath.includes("inspector") ||
        lowerPath.includes("input map") ||
        lowerTitle.includes("input map") ||
        lowerTitle.includes("collision layer") ||
        lowerTitle.includes("export"))
    ) {
      return "INSP";
    }
    return "SCENE";
  }

  const looksLikeCode = /\bfunc\s|\bextends\s|@export\b|@onready\b|\bvar\s/.test(code);
  const looksLikeSignalOrRun =
    lowerPath.includes("node dock") ||
    lowerPath.includes("signal") ||
    (lowerInstr.includes("connect") && lowerInstr.includes("signal")) ||
    /timeout\(\)|pressed\(\)|body_entered|-->|──►|─►/.test(code) ||
    /\bf6\b|\bf5\b|run scene/.test(lowerInstr);

  if (sr === "wire_and_verify") {
    return !looksLikeCode || looksLikeSignalOrRun ? "WIRE" : "CODE";
  }

  const target = String(subtask?.codeTargetFile || "").trim().toLowerCase();
  if (target === "scene_setup") return "SCENE";
  if (target === "inspector_setup") return "INSP";
  if (target === "signal_wire") return "WIRE";

  if (
    /^wire\b|\bsignal\b|\bconnect\b.*\b(trigger|signal)\b/i.test(titleStr) ||
    (looksLikeSignalOrRun && !looksLikeCode)
  ) {
    return "WIRE";
  }
  if (
    (hasHierarchy ||
      lowerPath.includes("scene dock") ||
      /\.tscn\b|\bchild node\b|\bcreate\b.*\bscene\b|^add\b.*\b(node|nodes|area|collider|colliders|marker|markers|spawner|timer|camera|mesh|light)\b/i.test(
        titleStr
      )) &&
    !/\bscript\b/i.test(titleStr) &&
    !looksLikeCode
  ) {
    return "SCENE";
  }
  if (
    ((hasInspector && !hasHierarchy) ||
      /\binput\s*map\b|\bcollision\b|\blayer\b|\bbounds\b|\binspector\b/i.test(
        titleStr
      )) &&
    !/\bscript\b/i.test(titleStr) &&
    !looksLikeCode
  ) {
    return "INSP";
  }
  return "CODE";
}

function toSnakeCaseAssetJs(rawTitle) {
  const words = String(rawTitle || "")
    .toLowerCase()
    .replace(/[^a-z0-9\s_]+/g, " ")
    .split(/\s+/)
    .filter((w) => w && !ASSET_STOP_WORDS.has(w));
  if (words.length > 0) {
    return words.slice(0, 3).join("_");
  }
  const rawWords = String(rawTitle || "")
    .toLowerCase()
    .replace(/[^a-z0-9\s_]+/g, " ")
    .split(/\s+/)
    .filter(Boolean);
  return rawWords.length > 0 ? rawWords.slice(0, 3).join("_") : "gameplay_feature";
}

function flattenCheckpointSteps(cp, featDoc, existingCodeFiles = null) {
  if (!cp) return [];
  const leaves = collectLeafChecklistItems(cp.checklist || []);
  const snake = toSnakeCaseAssetJs(featDoc?.title || cp?.name || "gameplay_feature");
  const primaryRaw =
    featDoc?.sections?.primary_asset ||
    cp?.parameters?.primarySharedScriptOrScene ||
    "";
  const primaryRes =
    extractResPath(primaryRaw) ||
    extractBareGdScriptPathJs(primaryRaw, existingCodeFiles);
  let fallbackScene = primaryRes.endsWith(".tscn") || primaryRes.endsWith(".scn") ? primaryRes : "";
  let fallbackScript = primaryRes.endsWith(".gd") ? primaryRes : "";

  for (const st of leaves) {
    const cand =
      extractResPath(st.codeLanguage || "") ||
      extractBareGdScriptPathJs(st.codeLanguage || "", existingCodeFiles) ||
      extractResPath(st.specNotes || "") ||
      extractBareGdScriptPathJs(st.specNotes || "", existingCodeFiles);
    if (!fallbackScene && (cand.endsWith(".tscn") || cand.endsWith(".scn"))) {
      fallbackScene = cand;
    }
    if (!fallbackScript && cand.endsWith(".gd")) {
      fallbackScript = cand;
    }
  }
  if (!fallbackScript && featDoc?.sections?.assets) {
    const assetScript =
      extractResPath(featDoc.sections.assets) ||
      extractBareGdScriptPathJs(featDoc.sections.assets, existingCodeFiles);
    if (assetScript && assetScript.endsWith(".gd")) {
      fallbackScript = assetScript;
    }
  }
  if (!fallbackScene) fallbackScene = `res://scenes/${snake}.tscn`;
  if (!fallbackScript && fallbackScene) {
    const sceneStem = fallbackScene
      .split("/")
      .pop()
      .replace(/\.(tscn|scn)$/i, "");
    const stemCandidate = normalizeResPathJs(`res://scripts/${sceneStem}.gd`);
    if (existingCodeFiles && typeof existingCodeFiles === "object") {
      if (Object.prototype.hasOwnProperty.call(existingCodeFiles, stemCandidate)) {
        fallbackScript = stemCandidate;
      } else {
        for (const key of Object.keys(existingCodeFiles)) {
          const normKey = normalizeResPathJs(key);
          if (normKey.toLowerCase().endsWith(`/${sceneStem.toLowerCase()}.gd`)) {
            fallbackScript = normKey;
            break;
          }
        }
      }
    }
  }
  if (!fallbackScript) fallbackScript = `res://scripts/${snake}.gd`;

  const cpVerifyFallback = String(
    cp?.parameters?.playtestGoal ||
      cp?.feedback ||
      "Verify in Godot with 0 console errors."
  ).trim();

  return leaves.map((st, idx) => {
    const decoded = decodeThreeAreaNotesJs(st.specNotes);
    const title = resolveStepShortTitle(st, decoded);
    const role = resolveStepRoleBadge(st, decoded, title);
    const explicitPath =
      extractResPath(st.codeLanguage || "") ||
      extractBareGdScriptPathJs(st.codeLanguage || "", existingCodeFiles) ||
      extractResPath(decoded.instruction || "") ||
      extractBareGdScriptPathJs(decoded.instruction || "", existingCodeFiles) ||
      extractBareGdScriptPathJs(st.specNotes || "", existingCodeFiles);
    const stepPath =
      explicitPath ||
      (role === "SCENE" || role === "INSP" || role === "WIRE"
        ? fallbackScene
        : fallbackScript);

    return {
      id: String(st.id || `step_${idx}`),
      index: idx + 1,
      role,
      title,
      locationLabel: String(st.codeLanguage || "").trim(),
      stepPath,
      instruction:
        decoded.instruction || `Complete "${title}" in ${stepPath}.`,
      area1Hierarchy: decoded.area1Hierarchy || "",
      area2Inspector: decoded.area2Inspector || "",
      codeSnippet: String(st.codeSnippet || "").trim(),
      verifyResult: String(st.verification || "").trim() || cpVerifyFallback,
      verifyMode:
        decoded.verifyMode ||
        (role === "SCENE" || role === "INSP" ? "editor" : "playtest"),
      diagnosis: decoded.diagnosis || "",
      scriptPatch: decoded.scriptPatch || null,
      completed: Boolean(st.completed),
    };
  });
}

function isFeatureActiveInReleaseJs(featDoc, activeVer, totalReleasesCount) {
  const lc = String(featDoc?.sections?.lifecycle || "");
  if (lc === "superseded") return false;
  const featActiveVer = String(
    featDoc?.sections?.activeReleaseVersion || ""
  ).trim();
  if (
    lc === "stable" &&
    (featActiveVer === activeVer || (!featActiveVer && totalReleasesCount <= 1))
  ) {
    return false;
  }
  const states = parseFeatureStates(featDoc);
  if (
    states.length > 0 &&
    states.some(
      (s) =>
        String(s?.parameters?.releaseVersion || "v0.1").trim() === activeVer
    )
  ) {
    return true;
  }
  return lc !== "stable";
}

function rebuildDocSubtasksFromStates(states) {
  return (Array.isArray(states) ? states : []).map((s) => {
    let total = 0;
    let done = 0;
    for (const item of Array.isArray(s.checklist) ? s.checklist : []) {
      const counts = countLeafChecklist(item);
      total += counts.total;
      done += counts.done;
    }
    const meta = {};
    meta.trigger = String(s.trigger || "");
    if (s.guard) meta.guard = s.guard;
    if (s.feedback) meta.feedback = s.feedback;
    if (s.parameters && Object.keys(s.parameters).length > 0) {
      meta.parameters = s.parameters;
    }
    if (Array.isArray(s.coveredScope) && s.coveredScope.length > 0) {
      meta.coveredScope = s.coveredScope;
    }
    if (Array.isArray(s.tuningParams) && s.tuningParams.length > 0) {
      meta.tuningParams = s.tuningParams;
    }
    if (Array.isArray(s.edgeCases) && s.edgeCases.length > 0) {
      meta.edgeCases = s.edgeCases;
    }
    return {
      id: String(s.id || ""),
      text: String(s.name || "Checkpoint"),
      completed: total > 0 && done === total,
      children: Array.isArray(s.checklist) ? s.checklist : [],
      isExpanded: true,
      specNotes: JSON.stringify(meta),
    };
  });
}

function updateLeafStepCompletion(items, stepId, completed) {
  let matched = false;
  if (!Array.isArray(items)) return false;
  for (const item of items) {
    if (!item || typeof item !== "object") continue;
    const children = Array.isArray(item.children) ? item.children : [];
    if (String(item.id || "") === stepId) {
      item.completed = completed;
      if (children.length > 0) {
        for (const c of children) {
          c.completed = completed;
        }
      }
      matched = true;
    } else if (children.length > 0) {
      if (updateLeafStepCompletion(children, stepId, completed)) {
        const counts = countLeafChecklist(item);
        item.completed = counts.total > 0 && counts.done === counts.total;
        matched = true;
      }
    }
  }
  return matched;
}

function setAllChecklistItemsCompleted(items, completed) {
  if (!Array.isArray(items)) return;
  for (const item of items) {
    if (!item || typeof item !== "object") continue;
    item.completed = completed;
    if (Array.isArray(item.children) && item.children.length > 0) {
      setAllChecklistItemsCompleted(item.children, completed);
    }
  }
}

function computeActiveEpicPayload({ docsById, projectId, webStudioUrl }) {
  let projectDoc = docsById.get(projectId) || null;
  if (!projectDoc) {
    for (const d of docsById.values()) {
      if (String(d?.tier || "").toUpperCase() === "PROJECT") {
        projectDoc = d;
        break;
      }
    }
  }
  if (!projectDoc) {
    return {
      ok: true,
      projectId,
      projectTitle: "LAYERS Project",
      releaseVersion: "v0.1",
      releaseTitle: "",
      epicPosition: 0,
      totalEpics: 0,
      allEpicsCompleted: false,
      webStudioUrl,
      activeEpic: null,
    };
  }

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

  const savedActiveRelId = String(
    projectDoc?.sections?.active_release_id || ""
  ).trim();
  const hasBuiltEpics = (rel) =>
    Array.isArray(rel?.childrenIds) &&
    rel.childrenIds.some((id) => {
      const ep = docsById.get(id);
      return ep && String(ep.tier || "").toUpperCase() === "EPIC";
    });
  const savedRel = releases.find((r) => r.id === savedActiveRelId) || null;
  let activeRel = savedRel && hasBuiltEpics(savedRel) ? savedRel : null;
  if (!activeRel) {
    for (let i = releases.length - 1; i >= 0; i -= 1) {
      if (hasBuiltEpics(releases[i])) {
        activeRel = releases[i];
        break;
      }
    }
  }
  if (!activeRel) {
    activeRel =
      savedRel ||
      (releases.length > 0 ? releases[releases.length - 1] : null);
  }

  if (!activeRel) {
    return {
      ok: true,
      projectId: projectDoc.id,
      projectTitle: String(projectDoc.title || "LAYERS Project"),
      releaseVersion: "v0.1",
      releaseTitle: "",
      epicPosition: 0,
      totalEpics: 0,
      allEpicsCompleted: false,
      webStudioUrl,
      activeEpic: null,
    };
  }

  const activeVer = resolveVersionTag(activeRel);
  const epics = (Array.isArray(activeRel.childrenIds) ? activeRel.childrenIds : [])
    .map((id) => docsById.get(id))
    .filter((d) => d && String(d.tier || "").toUpperCase() === "EPIC");

  let releaseHasActiveFeats = false;
  const rawFeaturesByEpic = new Map();
  for (const epic of epics) {
    const feats = (Array.isArray(epic.childrenIds) ? epic.childrenIds : [])
      .map((id) => docsById.get(id))
      .filter((d) => d && String(d.tier || "").toUpperCase() === "FEATURE");
    rawFeaturesByEpic.set(epic.id, feats);
    if (
      feats.some((f) => isFeatureActiveInReleaseJs(f, activeVer, releases.length))
    ) {
      releaseHasActiveFeats = true;
    }
  }

  const codeFiles = collectProjectCodeFilesJs(docsById);
  const candidateEpics = [];
  for (let i = 0; i < epics.length; i++) {
    const epic = epics[i];
    const allFeats = rawFeaturesByEpic.get(epic.id) || [];
    const scopedFeats = releaseHasActiveFeats
      ? allFeats.filter((f) =>
          isFeatureActiveInReleaseJs(f, activeVer, releases.length)
        )
      : allFeats;
    if (releaseHasActiveFeats && allFeats.length > 0 && scopedFeats.length === 0) {
      continue;
    }

    const mappedFeatures = scopedFeats.map((feat) => {
      const states = parseFeatureStates(feat);
      const cp = selectActiveCheckpoint(states, activeVer);
      const steps = flattenCheckpointSteps(cp, feat, codeFiles);
      const isPlaytestPassed =
        String(cp?.parameters?.playtestPassed || "") === "true";
      const allStepsDone =
        steps.length === 0 || steps.every((s) => Boolean(s.completed));
      const doneWhen = String(
        cp?.parameters?.playtestGoal ||
          cp?.feedback ||
          feat?.sections?.done_when ||
          feat?.sections?.doneWhen ||
          feat?.sections?.playtest_criteria ||
          `Press F6 and verify ${feat.title || "this feature"} works with 0 console errors.`
      ).trim();
      return {
        id: String(feat.id),
        title: String(feat.title || "Feature"),
        primaryAsset: extractResPath(feat?.sections?.primary_asset || ""),
        scriptPaths: collectFeatureScriptPathsJs(feat, steps, codeFiles),
        doneWhen,
        checkpointId: String(cp?.id || ""),
        isPlaytestPassed,
        isCompleted: allStepsDone && isPlaytestPassed,
        steps,
      };
    });

    const goal = String(
      epic?.sections?.goal ||
        epic?.sections?.objective ||
        epic?.sections?.summary ||
        ""
    ).trim();

    candidateEpics.push({
      id: String(epic.id),
      code: `E${String(i + 1).padStart(2, "0")}`,
      title: String(epic.title || "Epic"),
      goal,
      features: mappedFeatures,
    });
  }

  let activeIdx = candidateEpics.findIndex(
    (e) => e.features.length > 0 && e.features.some((f) => !f.isCompleted)
  );
  if (activeIdx === -1 && candidateEpics.length > 0) {
    const hasAnyPopulated = candidateEpics.some((e) => e.features.length > 0);
    if (!hasAnyPopulated) {
      activeIdx = 0;
    }
  }
  const arenaScenePath = detectArenaScenePathJs(
    docsById,
    candidateEpics,
    activeIdx >= 0 ? activeIdx : 0
  );

  if (candidateEpics.length > 0 && activeIdx === -1) {
    return {
      ok: true,
      projectId: projectDoc.id,
      projectTitle: String(projectDoc.title || "LAYERS Project"),
      releaseVersion: activeVer,
      releaseTitle: String(activeRel.title || activeVer),
      epicPosition: candidateEpics.length,
      totalEpics: candidateEpics.length,
      allEpicsCompleted: true,
      webStudioUrl,
      codeFiles,
      arenaScenePath,
      activeEpic: null,
    };
  }

  return {
    ok: true,
    projectId: projectDoc.id,
    projectTitle: String(projectDoc.title || "LAYERS Project"),
    releaseVersion: activeVer,
    releaseTitle: String(activeRel.title || activeVer),
    epicPosition: activeIdx >= 0 ? activeIdx + 1 : 0,
    totalEpics: candidateEpics.length,
    allEpicsCompleted: false,
    webStudioUrl,
    codeFiles,
    arenaScenePath,
    activeEpic: activeIdx >= 0 ? candidateEpics[activeIdx] : null,
  };
}

function extractJsonObjectFromGeminiBody(parsedBody) {
  try {
    const parts = parsedBody?.candidates?.[0]?.content?.parts;
    if (!Array.isArray(parts)) return null;
    for (let i = parts.length - 1; i >= 0; i--) {
      const p = parts[i];
      if (!p || p.thought === true || typeof p.text !== "string") continue;
      let text = p.text.trim();
      if (!text) continue;
      text = text
        .replace(/^```(?:json)?\s*/i, "")
        .replace(/\s*```$/i, "")
        .trim();
      const firstBrace = text.indexOf("{");
      const lastBrace = text.lastIndexOf("}");
      if (firstBrace >= 0 && lastBrace > firstBrace) {
        return JSON.parse(text.slice(firstBrace, lastBrace + 1));
      }
    }
  } catch (_) {}
  return null;
}

async function diagnoseGodotIssueWithGemini({
  secretKey,
  featTitle,
  doneWhen,
  stepsSummary,
  defaultScriptPath,
  issue,
  sceneSnapshot,
  scriptsSnapshot,
}) {
  const safePath = extractResPath(defaultScriptPath) || "res://scripts/fix_target.gd";
  const deterministicFallback = {
    fixTitle: issue.length > 52 ? `${issue.slice(0, 49)}...` : issue,
    diagnosis: `AI diagnosis unavailable offline; inspect ${safePath} and the active Scene Tree nodes around "${issue}".`,
    stepPath: safePath,
    instruction: `Open ${safePath}, add a safe null/state guard for "${issue}", and re-run F6.`,
    area2Inspector: "",
    codeSnippet: `# Root-cause guard for: ${issue}\npush_warning("[LAYERS FIX] Add guard for: ${issue.replace(/"/g, "'")}")`,
    scriptPatch: null,
    verifyResult: `Press F6 -> "${issue}" no longer occurs and Output shows 0 console errors.`,
  };

  if (!secretKey) return deterministicFallback;

  const prompt = [
    "You are the Godot 4 Root-Cause Debugger for LAYERS-Agentic.",
    "Diagnose the user's reported runtime/editor issue using their LIVE Godot 4 Scene Tree and actual .gd script files on disk, and return ONE surgical [FIX] step as strict JSON.",
    "",
    `Feature: ${featTitle}`,
    `Expected Outcome (Done When): ${doneWhen}`,
    stepsSummary ? `Existing Steps: ${stepsSummary}` : "",
    `Primary Script Hint: ${safePath}`,
    `Reported Issue: "${issue}"`,
    "",
    "LIVE GODOT SCENE TREE SNAPSHOT:",
    sceneSnapshot ? sceneSnapshot : "(No open scene root in Godot editor.)",
    "",
    "LIVE .GD SCRIPTS ON DISK:",
    scriptsSnapshot ? scriptsSnapshot : "(No .gd files attached/captured yet.)",
    "",
    "Return strictly one JSON object with these exact keys:",
    "{",
    '  "fixTitle": "3-6 word plain title without [FIX] prefix",',
    '  "diagnosis": "1-2 clear sentences naming the exact bug in the live scene tree or .gd script",',
    '  "stepPath": "res://scripts/...gd (or res://scenes/...tscn)",',
    '  "instruction": "1-2 direct imperative sentences describing the fix",',
    '  "area2Inspector": "Optional Inspector/InputMap bindings (or empty string)",',
    '  "codeSnippet": "Clean valid Godot 4 GDScript code for the fix (use tab indentation, NO + diff markers)",',
    '  "scriptPatch": {',
    '    "resPath": "res://scripts/...gd",',
    '    "targetBlock": "exact verbatim substring from LIVE .GD SCRIPTS ON DISK to replace, or empty string if creating a new script",',
    '    "replaceBlock": "exact replacement GDScript code (tab-indented, valid Godot 4 syntax, NO + diff markers)"',
    "  },",
    '  "verifyResult": "Player action -> observable fixed result with 0 errors in F6"',
    "}",
  ]
    .filter(Boolean)
    .join("\n");

  const modelsToTry = [
    {
      model: "gemini-4-hydrogen",
      generationConfig: {
        responseMimeType: "application/json",
        thinkingConfig: { thinkingLevel: "LOW" },
      },
    },
    {
      model: "gemini-flash-latest",
      generationConfig: {
        responseMimeType: "application/json",
      },
    },
  ];

  for (const cfg of modelsToTry) {
    try {
      const upstreamRes = await fetch(
        `https://generativelanguage.googleapis.com/v1beta/models/${cfg.model}:generateContent`,
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "x-goog-api-key": secretKey,
          },
          body: JSON.stringify({
            contents: [{ parts: [{ text: prompt }] }],
            generationConfig: cfg.generationConfig,
          }),
        }
      );
      if (!upstreamRes.ok) continue;
      const bodyJson = await upstreamRes.json();
      const parsed = extractJsonObjectFromGeminiBody(bodyJson);
      if (!parsed || typeof parsed !== "object") continue;

      const fixTitle =
        String(parsed.fixTitle || "")
          .replace(/^\[FIX\]\s*/i, "")
          .trim() || deterministicFallback.fixTitle;
      const diagnosis =
        String(parsed.diagnosis || "").trim() ||
        deterministicFallback.diagnosis;
      const resolvedPath =
        extractResPath(parsed.stepPath || "") ||
        extractResPath(parsed?.scriptPatch?.resPath || "") ||
        safePath;
      const instruction =
        String(parsed.instruction || "").trim() ||
        deterministicFallback.instruction;
      const area2Inspector = String(parsed.area2Inspector || "").trim();
      const rawSnippet = stripDiffLinePrefixes(parsed.codeSnippet || "");
      let scriptPatch = null;
      if (parsed.scriptPatch && typeof parsed.scriptPatch === "object") {
        const patchPath =
          extractResPath(parsed.scriptPatch.resPath || "") ||
          (resolvedPath.endsWith(".gd") ? resolvedPath : safePath);
        const targetBlock = String(parsed.scriptPatch.targetBlock || "");
        const replaceBlock = stripDiffLinePrefixes(
          parsed.scriptPatch.replaceBlock || ""
        );
        if (patchPath.endsWith(".gd") && replaceBlock) {
          scriptPatch = {
            resPath: patchPath,
            targetBlock,
            replaceBlock,
          };
        }
      }
      const codeSnippet =
        rawSnippet ||
        (scriptPatch ? scriptPatch.replaceBlock : "") ||
        deterministicFallback.codeSnippet;
      const verifyResult =
        String(parsed.verifyResult || "").trim() ||
        deterministicFallback.verifyResult;

      return {
        fixTitle,
        diagnosis,
        stepPath: resolvedPath,
        instruction,
        area2Inspector,
        codeSnippet,
        scriptPatch,
        verifyResult,
      };
    } catch (_) {
      // Fall over to next flash model cleanly
    }
  }

  return deterministicFallback;
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
    // Route 3C: GET /godotLink/epic (Godot 4 Dock: strictly 1 active Epic + steps only)
    // -------------------------------------------------------------------------
    if (cleanPath === "/godotLink/epic") {
      if (req.method !== "GET") {
        res.status(405).json({ error: { code: 405, message: "Expected GET." } });
        return;
      }
      const linkAuth = await verifyGodotLinkToken(req);
      if (linkAuth.errorStatus) {
        res.status(linkAuth.errorStatus).json({
          error: { code: linkAuth.errorStatus, message: linkAuth.errorMessage },
        });
        return;
      }

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
      linkAuth.linkRef.set({ lastSyncAt: Date.now() }, { merge: true }).catch(() => {});
      db.collection("users")
        .doc(linkAuth.uid)
        .collection("documents")
        .doc(linkAuth.projectId)
        .set(
          { sections: { last_godot_sync_ms: String(Date.now()) } },
          { merge: true }
        )
        .catch(() => {});

      const payload = computeActiveEpicPayload({
        docsById,
        projectId: linkAuth.projectId,
        webStudioUrl: linkAuth.webStudioUrl,
      });
      res.status(200).json(payload);
      return;
    }

    // -------------------------------------------------------------------------
    // Route 3D: POST /godotLink/update (Godot 4 Dock: toggle_step / pass_gate / set_playtest / diagnose_fix)
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
      const featureId = String(body.featureId || "").trim();
      const checkpointId = String(body.checkpointId || "").trim();
      const action = String(body.action || "").trim();
      const stepId = String(body.stepId || "").trim();

      if (
        action === "build_feature" ||
        action === "direct_agent" ||
        action === "diagnose_fix" ||
        action === "complete_feature_steps"
      ) {
        await handleGodotAgentActionRoute({ req, res, linkAuth, body });
        return;
      }

      if (action === "sync_scripts") {
        await handleSyncLiveScriptsRoute({ linkAuth, body, res });
        return;
      }

      if (
        !featureId ||
        (action !== "toggle_step" &&
          action !== "pass_gate" &&
          action !== "set_playtest")
      ) {
        res.status(400).json({
          error: {
            code: 400,
            message:
              "Expected featureId and action ('toggle_step', 'pass_gate', or 'set_playtest').",
          },
        });
        return;
      }
      if (action === "toggle_step" && !stepId) {
        res.status(400).json({
          error: { code: 400, message: "Missing stepId for toggle_step." },
        });
        return;
      }

      const db = getFirestore();
      const featRef = db
        .collection("users")
        .doc(linkAuth.uid)
        .collection("documents")
        .doc(featureId);

      try {
        await db.runTransaction(async (tx) => {
          const snap = await tx.get(featRef);
          if (!snap.exists) {
            const notFound = new Error("Feature document not found.");
            notFound.statusCode = 404;
            throw notFound;
          }
          const featData = snap.data() || {};
          const sections =
            featData.sections && typeof featData.sections === "object"
              ? { ...featData.sections }
              : {};
          const states = parseFeatureStates({ sections });
          if (states.length === 0) {
            const badStates = new Error("Feature has no checkpoints.");
            badStates.statusCode = 400;
            throw badStates;
          }
          let cp = checkpointId
            ? states.find((s) => String(s?.id || "") === checkpointId)
            : null;
          if (!cp) cp = states[states.length - 1];

          cp.parameters =
            cp.parameters && typeof cp.parameters === "object"
              ? { ...cp.parameters }
              : {};

          if (action === "toggle_step") {
            const nextCompleted = Boolean(body.completed);
            const matched = updateLeafStepCompletion(
              cp.checklist,
              stepId,
              nextCompleted
            );
            if (!matched) {
              const missingStep = new Error(`Step "${stepId}" not found.`);
              missingStep.statusCode = 404;
              throw missingStep;
            }
            if (!nextCompleted) {
              cp.parameters.playtestPassed = "false";
            }
          } else {
            const nextPassed = action === "pass_gate" ? true : Boolean(body.passed);
            cp.parameters.playtestPassed = nextPassed ? "true" : "false";
            if (nextPassed) {
              setAllChecklistItemsCompleted(cp.checklist, true);
            }
          }

          sections.states = JSON.stringify(states);
          const nextSubtasks = rebuildDocSubtasksFromStates(states);
          tx.update(featRef, {
            sections,
            subtasks: nextSubtasks,
            updatedAt: FieldValue.serverTimestamp(),
          });
        });
      } catch (err) {
        const code = err?.statusCode || 500;
        res.status(code).json({
          error: { code, message: String(err?.message || err) },
        });
        return;
      }

      const docsSnap = await db
        .collection("users")
        .doc(linkAuth.uid)
        .collection("documents")
        .get();
      const docsById = new Map();
      for (const d of docsSnap.docs) {
        docsById.set(d.id, { id: d.id, ...(d.data() || {}) });
      }
      linkAuth.linkRef.set({ lastSyncAt: Date.now() }, { merge: true }).catch(() => {});
      db.collection("users")
        .doc(linkAuth.uid)
        .collection("documents")
        .doc(linkAuth.projectId)
        .set(
          { sections: { last_godot_sync_ms: String(Date.now()) } },
          { merge: true }
        )
        .catch(() => {});

      const payload = computeActiveEpicPayload({
        docsById,
        projectId: linkAuth.projectId,
        webStudioUrl: linkAuth.webStudioUrl,
      });
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
      res.status(502).json({
        error: {
          code: 502,
          message: `Upstream Gemini request failed: ${err.message || err}`,
        },
      });
    }
  }
);
