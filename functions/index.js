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
  const v = String(
    relDoc?.sections?.versionTag || relDoc?.sections?.version || ""
  ).trim();
  if (v) return /^v/i.test(v) ? `v${v.slice(1)}` : `v${v}`;
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

function selectActiveCheckpoint(states, activeVer) {
  if (!Array.isArray(states) || states.length === 0) return null;
  const matching = states.filter(
    (s) => String(s?.parameters?.releaseVersion || "v0.1").trim() === activeVer
  );
  if (matching.length > 0) {
    return matching[matching.length - 1];
  }
  const firstIncomplete = states.find(
    (s) => String(s?.parameters?.playtestPassed || "") !== "true"
  );
  return firstIncomplete || states[states.length - 1];
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

function guardStorageKeyJs(index, rawGuardText) {
  const cleaned = String(rawGuardText || "").trim();
  return cleaned || `#${index}`;
}

function parseSignedOffGuardsSetJs(cp) {
  const raw = cp?.parameters?.signedOffGuards;
  if (!raw) return new Set();
  try {
    const parsed = Array.isArray(raw) ? raw : JSON.parse(String(raw));
    if (!Array.isArray(parsed)) return new Set();
    return new Set(parsed.map((x) => String(x || "").trim()).filter(Boolean));
  } catch (_) {
    return new Set();
  }
}

function cleanGuardDisplayTextJs(rawGuard) {
  return String(rawGuard || "")
    .trim()
    .replace(/^\[(?:STATE|PLAYTEST)\s+GUARD\]\s*:?\s*/i, "")
    .trim();
}

function isFixChecklistItemJs(item) {
  if (!item || typeof item !== "object") return false;
  const lang = String(item.codeLanguage || "").trim().toLowerCase();
  const txt = String(item.text || "").trim().toUpperCase();
  return lang === "fix" || txt.startsWith("[FIX]");
}

function collectOpenPlaytestIssuesJs(cp) {
  const out = [];
  let seq = 0;
  const walk = (items) => {
    if (!Array.isArray(items)) return;
    for (const item of items) {
      if (!item || typeof item !== "object") continue;
      if (isFixChecklistItemJs(item) && !item.completed) {
        const cleanText = String(item.text || "")
          .trim()
          .replace(/^\[FIX\]\s*/i, "")
          .trim();
        if (cleanText) {
          const itemId = String(item.id || "").trim() || `fix_idx_${seq}`;
          out.push({ id: itemId, text: cleanText });
        }
      }
      seq += 1;
      if (Array.isArray(item.children) && item.children.length > 0) {
        walk(item.children);
      }
    }
  };
  walk(cp?.checklist || []);
  return out;
}

function parseStructuredScopeFieldsJs(rawText) {
  const lines = String(rawText || "").replace(/\r\n/g, "\n").split("\n");
  let section = "goal";
  const goalLines = [];
  const inScopeLines = [];
  const doneWhenLines = [];

  for (const rawLine of lines) {
    const trimmed = rawLine.trim();
    if (!trimmed) continue;

    const goalMatch = trimmed.match(/^goal\s*:\s*(.*)$/i);
    if (goalMatch) {
      section = "goal";
      const rest = String(goalMatch[1] || "").trim();
      if (rest) goalLines.push(rest);
      continue;
    }

    const inScopeMatch = trimmed.match(/^in\s+scope(?:\s*\([^)]*\))?\s*:\s*(.*)$/i);
    if (inScopeMatch) {
      section = "in_scope";
      const rest = String(inScopeMatch[1] || "")
        .replace(/^[-*•]\s*/, "")
        .trim();
      if (rest) inScopeLines.push(rest);
      continue;
    }

    const outOfScopeMatch = trimmed.match(
      /^(?:out\s+of\s+scope|exclusions)(?:\s*\([^)]*\))?\s*:\s*(.*)$/i
    );
    if (outOfScopeMatch) {
      section = "out_of_scope";
      continue;
    }

    const doneMatch = trimmed.match(/^(?:done\s+when|playtest\s+gate|end\s+goal)\s*:\s*(.*)$/i);
    if (doneMatch) {
      section = "done_when";
      const rest = String(doneMatch[1] || "").trim();
      if (rest) doneWhenLines.push(rest);
      continue;
    }

    if (section === "goal") {
      if (/^[-*•]\s+/.test(trimmed) && goalLines.length > 0) {
        section = "in_scope";
        const bullet = trimmed.replace(/^[-*•]\s*/, "").trim();
        if (bullet) inScopeLines.push(bullet);
      } else {
        goalLines.push(trimmed);
      }
    } else if (section === "in_scope") {
      const bullet = trimmed.replace(/^[-*•]\s*/, "").trim();
      if (bullet) inScopeLines.push(bullet);
    } else if (section === "out_of_scope") {
      continue;
    } else {
      const donePart = trimmed.replace(/^[-*•]\s*/, "").trim();
      if (donePart) doneWhenLines.push(donePart);
    }
  }

  return {
    goal: goalLines.join(" ").trim(),
    inScope: inScopeLines,
    doneWhen: doneWhenLines
      .join(" ")
      .replace(/\s*->\s*/g, " → ")
      .trim(),
  };
}

function dedupeScopeBulletsJs(items, maxItems = 6, releaseVersion = "") {
  if (!Array.isArray(items)) return [];
  const cleaned = [];
  for (const raw of items) {
    let clean = String(raw || "")
      .replace(/^[-*•]\s*/, "")
      .trim();
    if (!clean) continue;
    if (clean.startsWith("+")) {
      clean = `+${clean.replace(/^\+\s*/, "").trim()}`;
    }
    if (clean && clean !== "+") {
      cleaned.push(clean);
    }
  }
  if (cleaned.length === 0) return [];
  const ver = String(releaseVersion || "").trim().toLowerCase();
  const allowDeltaFilter = Boolean(ver) && ver !== "v0.1" && ver !== "0.1";
  const plusOnly = cleaned.filter((s) => s.startsWith("+"));
  const source =
    allowDeltaFilter && plusOnly.length > 0 ? plusOnly : cleaned;

  const out = [];
  const keyToIdx = new Map();
  for (const clean of source) {
    const normKey = clean.replace(/^\+\s*/, "").trim().toLowerCase();
    if (!normKey) continue;
    if (keyToIdx.has(normKey)) {
      const existingIdx = keyToIdx.get(normKey);
      if (clean.startsWith("+") && !out[existingIdx].startsWith("+")) {
        out[existingIdx] = clean;
      }
      continue;
    }
    if (out.length >= maxItems) continue;
    keyToIdx.set(normKey, out.length);
    out.push(clean);
  }
  return out;
}

function parseBulletLinesJs(rawText, maxItems = 6) {
  return String(rawText || "")
    .replace(/\r\n/g, "\n")
    .split("\n")
    .map((l) => l.replace(/^[-*•]\s*/, "").trim())
    .filter((l) => Boolean(l) && !l.startsWith("#"))
    .slice(0, maxItems);
}

function cleanCheckpointDoneWhenJs(rawText) {
  const stripped = String(rawText || "")
    .trim()
    .replace(/^(?:playtest|done\s+when)\s*:\s*/i, "")
    .replace(/\s*->\s*/g, " → ")
    .trim();
  if (!stripped) return "";
  if (stripped.startsWith("+")) return "";
  if (
    /^(?:Verify stage deliverables and checklist criteria|Press F6 and verify\b)/i.test(
      stripped
    )
  ) {
    return "";
  }
  return stripped;
}

function markChecklistItemCompletedByIdJs(items, targetId) {
  const cleanTarget = String(targetId || "").trim();
  if (!cleanTarget || !Array.isArray(items)) return false;
  let seq = 0;
  let matched = false;
  const walk = (list) => {
    for (const item of list) {
      if (!item || typeof item !== "object") continue;
      const itemId = String(item.id || "").trim() || `fix_idx_${seq}`;
      const cleanText = String(item.text || "")
        .trim()
        .replace(/^\[FIX\]\s*/i, "")
        .trim();
      if (itemId === cleanTarget || cleanText === cleanTarget) {
        item.completed = true;
        matched = true;
      }
      seq += 1;
      if (Array.isArray(item.children) && item.children.length > 0) {
        walk(item.children);
      }
    }
  };
  walk(items);
  return matched;
}

function collectFeatureGdScriptPathsJs(feat, cp) {
  const ordered = [];
  const seen = new Set();
  const addFromText = (raw) => {
    for (const p of extractResPathsListJs(raw, ".gd")) {
      if (!seen.has(p)) {
        seen.add(p);
        ordered.push(p);
      }
    }
  };
  addFromText(feat?.sections?.primary_asset || "");
  addFromText(feat?.sections?.scripts || "");
  addFromText(feat?.sections?.assets || "");
  addFromText(feat?.sections?.in_scope || "");
  addFromText(feat?.sections?.engine_areas || "");
  const walkChecklist = (items) => {
    if (!Array.isArray(items)) return;
    for (const item of items) {
      if (!item || typeof item !== "object") continue;
      addFromText(item.codeLanguage || "");
      addFromText(item.text || "");
      if (Array.isArray(item.children) && item.children.length > 0) {
        walkChecklist(item.children);
      }
    }
  };
  walkChecklist(cp?.checklist || []);
  return ordered.slice(0, 12);
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
  if (states.length > 0) {
    return states.some(
      (s) =>
        String(s?.parameters?.releaseVersion || "v0.1").trim() === activeVer
    );
  }
  return lc !== "stable";
}

function rebuildDocSubtasksFromStates(states) {
  return (Array.isArray(states) ? states : []).map((s) => {
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
      completed: String(s?.parameters?.playtestPassed || "") === "true",
      children: Array.isArray(s.checklist) ? s.checklist : [],
      isExpanded: true,
      specNotes: JSON.stringify(meta),
    };
  });
}

function applyGodotFeatureMutationJs({ sections, states, cp, action, body }) {
  cp.parameters =
    cp.parameters && typeof cp.parameters === "object"
      ? { ...cp.parameters }
      : {};

  if (action === "set_playtest") {
    const nextPassed = Boolean(body?.passed);
    if (nextPassed) {
      cp.parameters.playtestPassed = "true";
      setAllChecklistItemsCompleted(cp.checklist, true);
      const rawArr = Array.isArray(cp.edgeCases) ? cp.edgeCases : [];
      const signedOffSet = parseSignedOffGuardsSetJs(cp);
      for (let idx = 0; idx < rawArr.length; idx += 1) {
        const rawGuard = String(rawArr[idx] || "").trim();
        if (!rawGuard) continue;
        signedOffSet.add(guardStorageKeyJs(idx, rawGuard));
      }
      if (signedOffSet.size > 0) {
        cp.parameters.signedOffGuards = JSON.stringify(
          Array.from(signedOffSet)
        );
      }
    } else {
      delete cp.parameters.playtestPassed;
      if (String(sections?.lifecycle || "").trim() === "stable") {
        sections.lifecycle =
          Array.isArray(states) && states.length > 1 ? "upgrade" : "newFeature";
      }
    }
    return;
  }

  if (action === "toggle_guard") {
    const guardIdx = Number.isInteger(Number(body?.guardIndex))
      ? Number(body.guardIndex)
      : 0;
    const rawArr = Array.isArray(cp.edgeCases) ? cp.edgeCases : [];
    const rawFromArr =
      guardIdx >= 0 && guardIdx < rawArr.length
        ? String(rawArr[guardIdx] || "").trim()
        : "";
    const rawGuard = rawFromArr || String(body?.guardText || "").trim();
    const key = guardStorageKeyJs(guardIdx, rawGuard);
    const signedOffSet = parseSignedOffGuardsSetJs(cp);
    if (Boolean(body?.signedOff)) {
      signedOffSet.add(key);
    } else {
      signedOffSet.delete(key);
      signedOffSet.delete(`#${guardIdx}`);
      const bodyKey = String(body?.guardText || "").trim();
      if (bodyKey) signedOffSet.delete(bodyKey);
    }
    if (signedOffSet.size === 0) {
      delete cp.parameters.signedOffGuards;
    } else {
      cp.parameters.signedOffGuards = JSON.stringify(
        Array.from(signedOffSet)
      );
    }
    return;
  }

  if (action === "log_issue") {
    const rawText = String(body?.issueText || "").trim();
    const cleanIssue = rawText.replace(/^\[FIX\]\s*/i, "").trim();
    const fixText = cleanIssue ? `[FIX] ${cleanIssue}` : rawText;
    const gdPaths = extractResPathsListJs(rawText, ".gd");
    cp.checklist = Array.isArray(cp.checklist) ? [...cp.checklist] : [];
    cp.checklist.push({
      id: `fix_${Date.now()}_${Math.random().toString(36).slice(2, 6)}`,
      text: fixText,
      completed: false,
      children: [],
      isExpanded: true,
      codeTargetFile: "playtest_fix",
      codeLanguage: gdPaths[0] || "fix",
      verification: `Re-test: ${cleanIssue || rawText} is resolved with 0 console errors.`,
    });
    cp.edgeCases = Array.isArray(cp.edgeCases) ? [...cp.edgeCases] : [];
    if (cleanIssue) {
      const lowerIssue = cleanIssue.toLowerCase();
      if (
        !cp.edgeCases.some((g) =>
          String(g || "").toLowerCase().includes(lowerIssue)
        )
      ) {
        cp.edgeCases.push(`[PLAYTEST GUARD] ${cleanIssue}`);
      }
    }
    if (cp.edgeCases.length > 0 && sections && typeof sections === "object") {
      sections.edge_cases = cp.edgeCases.map((e) => `• ${e}`).join("\n");
    }
    delete cp.parameters.playtestPassed;
    if (String(sections?.lifecycle || "").trim() === "stable") {
      sections.lifecycle =
        Array.isArray(states) && states.length > 1 ? "upgrade" : "newFeature";
    }
    return;
  }

  if (action === "resolve_issue") {
    const targetId = String(body?.issueId || "").trim();
    cp.checklist = Array.isArray(cp.checklist) ? cp.checklist : [];
    markChecklistItemCompletedByIdJs(cp.checklist, targetId);
  }
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
      designPillars: [],
      tradeOffs: [],
      webStudioUrl,
      activeEpic: null,
    };
  }

  const designPillars = parseBulletLinesJs(
    projectDoc?.sections?.design_pillars ||
      projectDoc?.sections?.designPillars ||
      "",
    6
  );
  const tradeOffs = parseBulletLinesJs(
    projectDoc?.sections?.trade_offs ||
      projectDoc?.sections?.tradeOffs ||
      "",
    6
  );

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
      designPillars,
      tradeOffs,
      webStudioUrl,
      selectedFeatureId: "",
      webSelectedFeatureId: "",
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

  const candidateEpics = [];
  for (let i = 0; i < epics.length; i++) {
    const epic = epics[i];
    const feats = rawFeaturesByEpic.get(epic.id) || [];
    const scopedFeats = releaseHasActiveFeats
      ? feats.filter((f) =>
          isFeatureActiveInReleaseJs(f, activeVer, releases.length)
        )
      : feats;
    if (releaseHasActiveFeats && feats.length > 0 && scopedFeats.length === 0) {
      continue;
    }

    const mappedFeatures = scopedFeats.map((feat) => {
      const states = parseFeatureStates(feat);
      const cp = selectActiveCheckpoint(states, activeVer);
      const isPlaytestPassed =
        String(cp?.parameters?.playtestPassed || "") === "true";
      const parsedScope = parseStructuredScopeFieldsJs(feat?.sections?.scope || "");
      const parsedGoal = parseStructuredScopeFieldsJs(feat?.sections?.goal || "");
      const rawTriggerGoalFallback =
        cp?.trigger &&
        !/^(?:playtest|done\s+when)\s*:/i.test(String(cp.trigger).trim()) &&
        !String(cp.trigger).includes("->") &&
        !String(cp.trigger).includes("→")
          ? String(cp.trigger).trim()
          : "";
      const goal = String(
        parsedGoal.goal ||
          parsedScope.goal ||
          rawTriggerGoalFallback ||
          feat?.sections?.summary ||
          ""
      ).trim();
      const coveredScope =
        Array.isArray(cp?.coveredScope) && cp.coveredScope.length > 0
          ? dedupeScopeBulletsJs(cp.coveredScope, 6, activeVer)
          : String(feat?.sections?.in_scope || "").trim()
            ? dedupeScopeBulletsJs(
                String(feat.sections.in_scope).split("\n"),
                6,
                activeVer
              )
            : dedupeScopeBulletsJs(parsedScope.inScope, 6, activeVer);
      const tuningParams =
        Array.isArray(cp?.tuningParams) && cp.tuningParams.length > 0
          ? cp.tuningParams
              .map((x) => String(x || "").trim())
              .filter(Boolean)
              .slice(0, 8)
          : String(feat?.sections?.tuning || feat?.sections?.variables || "")
              .split("\n")
              .map((l) => l.replace(/^[-*•]\s*/, "").trim())
              .filter(Boolean)
              .slice(0, 8);
      const signedOffSet = parseSignedOffGuardsSetJs(cp);
      const rawEdgeCases = Array.isArray(cp?.edgeCases) ? cp.edgeCases : [];
      const edgeCases = rawEdgeCases
        .map((raw, idx) => {
          const rawText = String(raw || "").trim();
          if (!rawText) return null;
          const key = guardStorageKeyJs(idx, rawText);
          const signedOff =
            signedOffSet.has(key) || signedOffSet.has(`#${idx}`);
          return {
            index: idx,
            rawText,
            text: cleanGuardDisplayTextJs(rawText) || rawText,
            signedOff,
          };
        })
        .filter(Boolean);
      const signedOffCount = edgeCases.filter((g) => Boolean(g.signedOff)).length;
      const progress = isPlaytestPassed
        ? 100
        : edgeCases.length === 0
          ? 0
          : Math.round((signedOffCount / edgeCases.length) * 50);
      const openIssues = collectOpenPlaytestIssuesJs(cp);
      const doneWhen =
        cleanCheckpointDoneWhenJs(cp?.parameters?.playtestGoal) ||
        cleanCheckpointDoneWhenJs(cp?.trigger) ||
        cleanCheckpointDoneWhenJs(cp?.feedback) ||
        cleanCheckpointDoneWhenJs(
          feat?.sections?.done_when ||
            feat?.sections?.doneWhen ||
            feat?.sections?.playtest_criteria
        ) ||
        cleanCheckpointDoneWhenJs(parsedScope.doneWhen) ||
        cleanCheckpointDoneWhenJs(parsedGoal.doneWhen) ||
        `Press F6 and verify ${feat.title || "this feature"} works with 0 console errors.`;
      return {
        id: String(feat.id),
        title: String(feat.title || "Feature"),
        goal,
        primaryAsset: extractResPath(feat?.sections?.primary_asset || ""),
        scriptPaths: collectFeatureGdScriptPathsJs(feat, cp),
        coveredScope,
        tuningParams,
        edgeCases,
        openIssues,
        doneWhen,
        checkpointId: String(cp?.id || ""),
        isPlaytestPassed,
        isCompleted: isPlaytestPassed,
        progress,
      };
    });

    const parsedEpicScope = parseStructuredScopeFieldsJs(
      epic?.sections?.goal ||
        epic?.sections?.scope ||
        epic?.sections?.objective ||
        epic?.sections?.summary ||
        ""
    );
    const goal = String(
      parsedEpicScope.goal ||
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
      designPillars,
      tradeOffs,
      webStudioUrl,
      arenaScenePath,
      selectedFeatureId: "",
      webSelectedFeatureId: "",
      activeEpic: null,
    };
  }

  const projSections =
    projectDoc.sections && typeof projectDoc.sections === "object"
      ? projectDoc.sections
      : {};
  const rawWebSelId = String(projSections.selected_feature_id || "").trim();
  const webSelMs = Number(projSections.selected_feature_ms || 0) || 0;
  const rawGodotFeatId = String(
    projSections.last_godot_feature_id || ""
  ).trim();
  const godotFeatMs = Number(projSections.last_godot_feature_ms || 0) || 0;

  const activeEpic = activeIdx >= 0 ? candidateEpics[activeIdx] : null;
  let webSelectedFeatureId = "";
  let selectedFeatureId = "";
  if (
    activeEpic &&
    Array.isArray(activeEpic.features) &&
    activeEpic.features.length > 0
  ) {
    const featsInEpic = activeEpic.features;
    const webFeat = rawWebSelId
      ? featsInEpic.find((f) => f.id === rawWebSelId) || null
      : null;
    if (webFeat) {
      webSelectedFeatureId = webFeat.id;
    }
    const godotFeat = rawGodotFeatId
      ? featsInEpic.find((f) => f.id === rawGodotFeatId) || null
      : null;
    const webIncomplete = webFeat && !webFeat.isCompleted ? webFeat : null;
    const godotIncomplete =
      godotFeat && !godotFeat.isCompleted ? godotFeat : null;

    if (webIncomplete && webSelMs > godotFeatMs) {
      selectedFeatureId = webIncomplete.id;
    } else if (godotIncomplete) {
      selectedFeatureId = godotIncomplete.id;
    } else if (webIncomplete && !rawGodotFeatId && godotFeatMs === 0) {
      selectedFeatureId = webIncomplete.id;
    } else {
      const firstIncomplete =
        featsInEpic.find((f) => !f.isCompleted) || featsInEpic[0];
      selectedFeatureId = firstIncomplete ? firstIncomplete.id : "";
    }
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
    designPillars,
    tradeOffs,
    webStudioUrl,
    arenaScenePath,
    selectedFeatureId,
    webSelectedFeatureId,
    activeEpic,
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
      const payload = computeActiveEpicPayload({
        docsById,
        projectId: linkAuth.projectId,
        webStudioUrl: linkAuth.webStudioUrl,
      });
      const nowMs = String(Date.now());
      const projDoc = docsById.get(linkAuth.projectId);
      const projSec =
        projDoc?.sections && typeof projDoc.sections === "object"
          ? projDoc.sections
          : {};
      const webSelMs = Number(projSec.selected_feature_ms || 0) || 0;
      const godotFeatMs = Number(projSec.last_godot_feature_ms || 0) || 0;
      const existingGodotFeat = String(
        projSec.last_godot_feature_id || ""
      ).trim();
      const existingStillIncomplete = Boolean(
        existingGodotFeat &&
          Array.isArray(payload.activeEpic?.features) &&
          payload.activeEpic.features.some(
            (f) => f.id === existingGodotFeat && !f.isCompleted
          )
      );
      const nextProjSections = { last_godot_sync_ms: nowMs };
      if (
        payload.selectedFeatureId &&
        (!existingStillIncomplete || webSelMs > godotFeatMs)
      ) {
        nextProjSections.last_godot_feature_id = payload.selectedFeatureId;
        nextProjSections.last_godot_feature_ms = nowMs;
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
    // -------------------------------------------------------------------------
    // Route 3D: POST /godotLink/update (Godot 4 Dock: set_playtest / toggle_guard / log_issue / resolve_issue)
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
      const validActions = new Set([
        "set_playtest",
        "toggle_guard",
        "log_issue",
        "resolve_issue",
        "select_feature",
      ]);

      if (!featureId || !validActions.has(action)) {
        res.status(400).json({
          error: {
            code: 400,
            message:
              "Expected featureId and action (set_playtest, toggle_guard, log_issue, resolve_issue, or select_feature).",
          },
        });
        return;
      }

      if (action === "log_issue" && !String(body.issueText || "").trim()) {
        res.status(400).json({
          error: { code: 400, message: "Expected non-empty issueText for log_issue." },
        });
        return;
      }
      if (action === "resolve_issue" && !String(body.issueId || "").trim()) {
        res.status(400).json({
          error: { code: 400, message: "Expected issueId for resolve_issue." },
        });
        return;
      }

      const db = getFirestore();
      const featRef = db
        .collection("users")
        .doc(linkAuth.uid)
        .collection("documents")
        .doc(featureId);

      if (action !== "select_feature") {
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

            applyGodotFeatureMutationJs({
              sections,
              states,
              cp,
              action,
              body,
            });

            sections.states = JSON.stringify(states);
            sections.last_godot_sync_ms = String(Date.now());
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
      if (action === "select_feature" && !docsById.has(featureId)) {
        res.status(404).json({
          error: { code: 404, message: "Feature document not found." },
        });
        return;
      }
      const nowMs = String(Date.now());
      const passedJustNow = action === "set_playtest" && Boolean(body.passed);
      const inMemProj = docsById.get(linkAuth.projectId);
      if (inMemProj) {
        inMemProj.sections = {
          ...(inMemProj.sections && typeof inMemProj.sections === "object"
            ? inMemProj.sections
            : {}),
          last_godot_sync_ms: nowMs,
          last_godot_feature_id: passedJustNow ? "" : featureId,
          last_godot_feature_ms: nowMs,
        };
      }
      const payload = computeActiveEpicPayload({
        docsById,
        projectId: linkAuth.projectId,
        webStudioUrl: linkAuth.webStudioUrl,
      });
      const resolvedGodotFeatId = passedJustNow
        ? String(payload.selectedFeatureId || "")
        : featureId;
      linkAuth.linkRef.set({ lastSyncAt: Date.now() }, { merge: true }).catch(() => {});
      db.collection("users")
        .doc(linkAuth.uid)
        .collection("documents")
        .doc(linkAuth.projectId)
        .set(
          {
            sections: {
              last_godot_sync_ms: nowMs,
              last_godot_feature_id: resolvedGodotFeatId,
              last_godot_feature_ms: nowMs,
            },
          },
          { merge: true }
        )
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
  rebuildDocSubtasksFromStates,
  selectActiveCheckpoint,
  computeActiveEpicPayload,
  applyGodotFeatureMutationJs,
  parseStructuredScopeFieldsJs,
  dedupeScopeBulletsJs,
  cleanCheckpointDoneWhenJs,
};
