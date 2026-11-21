const crypto = require("crypto");
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
const DEFAULT_WEB_STUDIO_URL = "https://henrycgithub.github.io/LAYERS-Agentic/";
const DEFAULT_SYNC_BASE_URL =
  "https://us-central1-layers-b8a16.cloudfunctions.net/geminiProxy";


const {
  resolveVersionTag,
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
} = require("./godot_spec_context");
const {
  hashLinkToken,
  extractBearerLinkToken,
  GODOT_UPDATE_VALID_ACTIONS,
  computeActiveGodotEpicPayload,
  resolveTargetEpicDocIdJs,
  applyGodotEpicMutationJs,
  buildGodotSyncProjectSectionsJs,
} = require("./godot_link_sync");
const {
  normalizeAgentBundle,
  buildGodotAgentPrompts,
  GODOT_READONLY_TOOL_NAMES,
  sanitizeToolHistoryJs,
  buildGodotMultiTurnPrompt,
  normalizeAgentStepResponse,
  runGodotEpicAgentWithGemini,
  runGodotMultiTurnStepWithGemini,
} = require("./godot_agent_runner");

const {
  isAdminEmail,
  parseJsonBody,
  createAuthAccessControl,
} = require("./auth_access_control");
const {
  verifyGodotLinkToken,
  getAccessStatusFromDb,
  verifyCallerToken,
  handleInviteAdminRoutes,
} = createAuthAccessControl({
  getAuth,
  getFirestore,
  FieldValue,
  gmailAppPasswordSecret: GMAIL_APP_PASSWORD,
  defaultWebStudioUrl: DEFAULT_WEB_STUDIO_URL,
  extractBearerLinkToken,
  hashLinkToken,
});

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
    if (await handleInviteAdminRoutes(req, res, cleanPath)) {
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
