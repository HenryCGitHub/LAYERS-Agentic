const crypto = require("crypto");
const {
  DEFAULT_WEB_STUDIO_URL,
  resolveVersionTag,
  parseJsonObjectSafe,
  normalizeResPathJs,
  extractResPathsListJs,
  sanitizeGodotLineJs,
  parseRootSpecJs,
  isFeatureLockedBaselineJs,
  getEffectiveChecksForReleaseJs,
  computeFeaturePassedJs,
  isFeaturePassedForReleaseJs,
  getVisibleFeaturesForReleaseJs,
  computeEpicPassedJs,
  sanitizeGodotTuningKeyJs,
  normalizeGodotUnitJs,
  parseEpicSpecJs,
  renderServerGodotEpicContextJs,
  renderServerGodotFeatureContextJs,
} = require("./godot_spec_context");

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

module.exports = {
  hashLinkToken,
  extractBearerLinkToken,
  GODOT_UPDATE_VALID_ACTIONS,
  computeActiveGodotEpicPayload,
  resolveTargetEpicDocIdJs,
  syncEpicLifecycleFromFeaturesJs,
  applyGodotEpicMutationJs,
  buildGodotSyncProjectSectionsJs,
};
