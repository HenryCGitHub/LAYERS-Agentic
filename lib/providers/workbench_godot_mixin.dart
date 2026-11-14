part of 'workbench_provider.dart';

/// Snapshot of the single Epic currently active in the native Godot 4 LAYERS Dock.
class ActiveGodotEpicSnapshot {
  final String releaseVersion;
  final String? activeEpicId;
  final String activeEpicCode;
  final String activeEpicTitle;
  final String activeEpicGoal;
  final int epicPosition;
  final int totalEpics;
  final int completedFeaturesInActiveEpic;
  final int totalFeaturesInActiveEpic;
  final bool allEpicsCompleted;

  const ActiveGodotEpicSnapshot({
    required this.releaseVersion,
    required this.activeEpicId,
    required this.activeEpicCode,
    required this.activeEpicTitle,
    required this.activeEpicGoal,
    required this.epicPosition,
    required this.totalEpics,
    required this.completedFeaturesInActiveEpic,
    required this.totalFeaturesInActiveEpic,
    required this.allEpicsCompleted,
  });
}

/// Godot 4 Contract and cumulative Cloud-saved `TierType.codeFile` scripts + patch applier.
extension WorkbenchGodotMixin on WorkbenchProvider {
  /// Resolves the single active Epic shown inside the Godot 4 Dock (`E01` -> `E02` -> ...),
  /// matching `/godotLink/epic` Cloud Sync progression rules.
  ActiveGodotEpicSnapshot computeActiveGodotEpicSnapshot() {
    final activeVer = activeReleaseVersionTag;
    final beats = activeReleaseBeats;
    if (beats.isEmpty) {
      return ActiveGodotEpicSnapshot(
        releaseVersion: activeVer,
        activeEpicId: null,
        activeEpicCode: '',
        activeEpicTitle: '',
        activeEpicGoal: '',
        epicPosition: 0,
        totalEpics: 0,
        completedFeaturesInActiveEpic: 0,
        totalFeaturesInActiveEpic: 0,
        allEpicsCompleted: false,
      );
    }

    bool isFeatureFinishedForGodot(TierDocument feat) {
      if (!isFeatureActiveInRelease(feat, activeVer)) return true;
      final states = FeatureStateNode.getStatesForDocument(feat);
      if (states.isEmpty) return feat.isCompleted;
      FeatureStateNode? cp;
      final matching = states.where((s) => s.releaseVersion == activeVer).toList();
      if (matching.isNotEmpty) {
        cp = matching.last;
      } else {
        for (final s in states) {
          if (!s.isCompleted || !s.isPlaytestPassed) {
            cp = s;
            break;
          }
        }
        cp ??= states.last;
      }
      final steps = cp.flatSteps;
      return steps.isNotEmpty &&
          steps.every((s) => s.completed) &&
          cp.isPlaytestPassed;
    }

    final releaseHasActiveFeats = beats.any(
      (b) => featuresForBeat(b.id).any(
        (f) => isFeatureActiveInRelease(f, activeVer),
      ),
    );

    final candidates = <({
      TierDocument beat,
      int originalIndex,
      int doneCount,
      int totalCount,
    })>[];

    for (int i = 0; i < beats.length; i++) {
      final beat = beats[i];
      final allFeats = featuresForBeat(beat.id);
      final scopedFeats = releaseHasActiveFeats
          ? allFeats.where((f) => isFeatureActiveInRelease(f, activeVer)).toList()
          : allFeats;
      if (releaseHasActiveFeats && allFeats.isNotEmpty && scopedFeats.isEmpty) {
        continue;
      }
      final doneCount = scopedFeats.where(isFeatureFinishedForGodot).length;
      candidates.add((
        beat: beat,
        originalIndex: i,
        doneCount: doneCount,
        totalCount: scopedFeats.length,
      ));
    }

    if (candidates.isEmpty) {
      return ActiveGodotEpicSnapshot(
        releaseVersion: activeVer,
        activeEpicId: null,
        activeEpicCode: '',
        activeEpicTitle: '',
        activeEpicGoal: '',
        epicPosition: 0,
        totalEpics: 0,
        completedFeaturesInActiveEpic: 0,
        totalFeaturesInActiveEpic: 0,
        allEpicsCompleted: false,
      );
    }

    for (int idx = 0; idx < candidates.length; idx++) {
      final c = candidates[idx];
      if (c.totalCount == 0 || c.doneCount < c.totalCount) {
        final code = 'E${(c.originalIndex + 1).toString().padLeft(2, '0')}';
        return ActiveGodotEpicSnapshot(
          releaseVersion: activeVer,
          activeEpicId: c.beat.id,
          activeEpicCode: code,
          activeEpicTitle: c.beat.title,
          activeEpicGoal: SectionTextUtils.resolveGoal(c.beat.sections),
          epicPosition: idx + 1,
          totalEpics: candidates.length,
          completedFeaturesInActiveEpic: c.doneCount,
          totalFeaturesInActiveEpic: c.totalCount,
          allEpicsCompleted: false,
        );
      }
    }

    final last = candidates.last;
    return ActiveGodotEpicSnapshot(
      releaseVersion: activeVer,
      activeEpicId: null,
      activeEpicCode: 'E${(last.originalIndex + 1).toString().padLeft(2, '0')}',
      activeEpicTitle: last.beat.title,
      activeEpicGoal: SectionTextUtils.resolveGoal(last.beat.sections),
      epicPosition: candidates.length,
      totalEpics: candidates.length,
      completedFeaturesInActiveEpic: last.doneCount,
      totalFeaturesInActiveEpic: last.totalCount,
      allEpicsCompleted: true,
    );
  }

  /// Generates, fetches, or rotates a per-project Cloud Link Token (`lyr_...`) for the Godot 4 Dock.
  Future<({String? token, String? error})> fetchOrCreateGodotLinkToken({
    bool rotate = false,
  }) async {
    final pid = _activeProjectId;
    if (pid == null || pid.trim().isEmpty) {
      return (token: null, error: 'Create or select a project first.');
    }
    if (!rotate) {
      final cached = _cachedGodotLinkTokensByProjectId[pid];
      if (cached != null && cached.trim().isNotEmpty) {
        return (token: cached, error: null);
      }
    }

    try {
      final resp = await GeminiAgentClient.postAuthenticatedProxyAction(
        routePath: '/godotLink/token',
        payload: <String, dynamic>{
          'projectId': pid,
          'rotate': rotate,
        },
      );
      final token = resp.body['linkToken']?.toString().trim() ?? '';
      if (resp.statusCode == 200 && token.isNotEmpty) {
        _cachedGodotLinkTokensByProjectId[pid] = token;
        notifyListeners();
        return (token: token, error: null);
      }
      final errObj = resp.body['error'];
      final serverMsg =
          (errObj is Map ? errObj['message'] : null)?.toString().trim();
      return (
        token: null,
        error: (serverMsg != null && serverMsg.isNotEmpty)
            ? serverMsg
            : 'Sign in with Google to generate a live Godot Cloud Link Token.',
      );
    } catch (e) {
      return (
        token: null,
        error: 'Unable to fetch Godot Cloud Link Token: $e',
      );
    }
  }
  /// Escalates to `MEDIUM` (unless already `HIGH`) strictly for `.gd` script synthesis/patching and `[FIX]` diagnoses.
  String get effectiveGodotCodeThinkingLevel =>
      _thinkingLevel.trim().toUpperCase() == 'HIGH' ? 'HIGH' : 'MEDIUM';

  bool get _is3dGodotProject =>
      _activeEngineLabel.toLowerCase().contains('3d') ||
      (_activeEngineHint ?? '').toLowerCase().contains('3d');

  GodotProjectContract get activeGodotContract {
    final proj = activeProject;
    if (proj == null) return GodotProjectContract.starter(is3D: _is3dGodotProject);
    return GodotProjectContract.fromProjectSections(
      proj.sections,
      is3DHint: _is3dGodotProject,
    );
  }

  void updateGodotContract(GodotProjectContract contract) {
    final proj = activeProject;
    if (proj == null) return;
    proj.sections[GodotProjectContract.sectionKey] = contract.toJsonString();
    _persistDocument(proj);
    notifyListeners();
  }

  /// All cumulative `TierType.codeFile` artifacts belonging to the active project, sorted `.gd` first.
  List<GodotVirtualFile> get activeProjectGodotFiles {
    final pid = _activeProjectId;
    if (pid == null) return const [];
    final files = documents.values
        .where((d) => d.tier == TierType.codeFile && d.parentId == pid)
        .map(GodotVirtualFile.fromTierDocument)
        .where((vf) => vf.resPath.isNotEmpty)
        .toList();
    files.sort((a, b) {
      int weight(String p) => p.endsWith('.gd') ? 0 : (p.endsWith('.tres') ? 1 : 2);
      final wCmp = weight(a.resPath).compareTo(weight(b.resPath));
      if (wCmp != 0) return wCmp;
      return a.resPath.compareTo(b.resPath);
    });
    return files;
  }

  GodotVirtualFile? godotFileForResPath(String resPath) {
    final pid = _activeProjectId;
    if (pid == null) return null;
    final norm = GodotVirtualFile.normalizeResPath(resPath);
    if (norm.isEmpty) return null;
    for (final doc in documents.values) {
      if (doc.tier == TierType.codeFile && doc.parentId == pid) {
        final vf = GodotVirtualFile.fromTierDocument(doc);
        if (vf.resPath == norm) return vf;
      }
    }
    return null;
  }

  /// Extracts the `.gd` script `res://...` path from strings like `"res://scenes/player.tscn · res://scripts/player.gd"`.
  String? extractPrimaryScriptResPath(String? rawAssetString) {
    if (rawAssetString == null || rawAssetString.trim().isEmpty) return null;
    final match = RegExp(r'res://[^\s,|·;"]+\.gd\b').firstMatch(rawAssetString);
    return match != null ? GodotVirtualFile.normalizeResPath(match.group(0)!) : null;
  }

  /// Extracts the `.tscn` scene `res://...` path from a feature's `primary_asset` string.
  String? extractPrimarySceneResPath(String? rawAssetString) {
    if (rawAssetString == null || rawAssetString.trim().isEmpty) return null;
    final match = RegExp(r'res://[^\s,|·;"]+\.tscn\b').firstMatch(rawAssetString);
    return match != null ? GodotVirtualFile.normalizeResPath(match.group(0)!) : null;
  }

  /// Creates or updates a cumulative `TierType.codeFile` document in Cloud Firestore & LocalVault.
  GodotVirtualFile? upsertGodotVirtualFile({
    required String resPath,
    required String content,
    String? releaseVersion,
    Iterable<String> featureIds = const [],
    bool silent = false,
  }) {
    final proj = activeProject;
    if (proj == null) return null;
    final normPath = GodotVirtualFile.normalizeResPath(resPath);
    if (normPath.isEmpty) return null;

    final existing = godotFileForResPath(normPath);
    final mergedFeatureIds = <String>{
      ...?existing?.featureIds,
      ...featureIds.where((id) => id.trim().isNotEmpty),
    }.toList();

    final vf = GodotVirtualFile(
      id: existing?.id ?? GodotVirtualFile.stableDocId(proj.id, normPath),
      projectId: proj.id,
      resPath: normPath,
      content: content.replaceAll('\r\n', '\n'),
      language: GodotVirtualFile.inferLanguage(normPath),
      releaseVersion: (releaseVersion ?? '').trim().isNotEmpty
          ? releaseVersion!.trim()
          : (existing?.releaseVersion.isNotEmpty == true
              ? existing!.releaseVersion
              : activeReleaseVersionTag),
      featureIds: mergedFeatureIds,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    );

    final doc = vf.toTierDocument();
    documents[doc.id] = doc;
    _persistDocument(doc);
    if (!silent) {
      notifyListeners();
    }
    return vf;
  }

  /// Applies surgical `{targetBlock, replaceBlock}` hunks onto the stored `.gd` file.
  GdScriptPatchResult applyScriptPatchesToVirtualFile({
    required String resPath,
    required List<GdScriptPatchHunk> hunks,
    String? featureId,
    String? releaseVersion,
    bool silent = false,
  }) {
    final normPath = GodotVirtualFile.normalizeResPath(resPath);
    final existing = godotFileForResPath(normPath);
    final baseContent = existing?.content ?? '';

    final result = GodotGdscriptGuard.applyPatchHunks(
      existingContent: baseContent,
      hunks: hunks,
    );

    if (result.appliedCount > 0 ||
        (existing == null && result.updatedContent.trim().isNotEmpty)) {
      upsertGodotVirtualFile(
        resPath: normPath,
        content: result.updatedContent,
        releaseVersion: releaseVersion,
        featureIds: featureId != null ? [featureId] : const [],
        silent: silent,
      );
    } else if (!silent) {
      notifyListeners();
    }
    return result;
  }

  /// Syncs an edited tuning parameter or Inspector value directly into the stored `.gd` `@export var`.
  bool syncExportVarToVirtualFile({
    String? primaryAssetOrResPath,
    required String varName,
    required String formattedValue,
    String? featureId,
  }) {
    final scriptPath = extractPrimaryScriptResPath(primaryAssetOrResPath);
    if (scriptPath != null) {
      final vf = godotFileForResPath(scriptPath);
      if (vf != null) {
        final patched = GodotGdscriptGuard.updateExportVarValue(
          vf.content,
          varName,
          formattedValue,
        );
        if (patched != null && patched != vf.content) {
          upsertGodotVirtualFile(
            resPath: vf.resPath,
            content: patched,
            featureIds: featureId != null ? [featureId] : const [],
          );
          return true;
        }
      }
    }

    if (featureId != null) {
      for (final vf in activeProjectGodotFiles) {
        if (!vf.resPath.endsWith('.gd') || !vf.featureIds.contains(featureId)) {
          continue;
        }
        final patched = GodotGdscriptGuard.updateExportVarValue(
          vf.content,
          varName,
          formattedValue,
        );
        if (patched != null && patched != vf.content) {
          upsertGodotVirtualFile(
            resPath: vf.resPath,
            content: patched,
            featureIds: [featureId],
          );
          return true;
        }
      }
    }
    return false;
  }

  /// Builds a concise prompt context containing the Godot Project Contract and current stored `.gd` code
  /// so Gemini can emit surgical `{targetBlock, replaceBlock}` hunks without guessing existing symbols.
  String buildPromptGodotContext({
    String? primaryAssetHint,
    String? fallbackScriptPath,
  }) {
    final buf = StringBuffer();
    final contractSummary = activeGodotContract.toPromptSummary();
    if (contractSummary.isNotEmpty) {
      buf.writeln('GODOT 4 PROJECT CONTRACT (use exact layer numbers, action names, autoloads, and groups):');
      buf.writeln(contractSummary);
    }

    final targetScript = extractPrimaryScriptResPath(primaryAssetHint) ??
        extractPrimaryScriptResPath(fallbackScriptPath);
    if (targetScript != null) {
      final norm = GodotVirtualFile.normalizeResPath(targetScript);
      final currentCode = godotFileForResPath(norm)?.content ?? '';
      if (currentCode.trim().isNotEmpty) {
        final lines = currentCode.split('\n');
        final clipped = lines.length > 140 ? lines.take(140).join('\n') : currentCode;
        buf.writeln('\nCURRENT CUMULATIVE SCRIPT ($norm — patch via `scriptPatches` with exact `targetBlock` -> `replaceBlock`):');
        buf.writeln('```gdscript\n$clipped\n```');
      } else {
        buf.writeln('\nNEW CUMULATIVE SCRIPT ($norm — initialize once via `scriptPatches` with `targetBlock: ""`).');
      }
    }
    return buf.toString().trim();
  }

  /// Applies structured `scriptPatches` returned by Gemini onto cumulative Cloud-saved `.gd` files.
  void applyAiScriptPatchesResponse(
    dynamic rawPatches, {
    String? fallbackResPath,
    String? featureId,
    String? releaseVersion,
  }) {
    if (rawPatches is! List || rawPatches.isEmpty) return;
    final grouped = <String, List<GdScriptPatchHunk>>{};
    for (final raw in rawPatches) {
      if (raw is! Map) continue;
      final map = Map<String, dynamic>.from(raw);
      final rawPath = (map['resPath'] ?? map['scriptPath'] ?? fallbackResPath ?? '')
          .toString()
          .trim();
      final resolved = extractPrimaryScriptResPath(rawPath) ??
          extractPrimaryScriptResPath(fallbackResPath) ??
          '';
      if (resolved.isEmpty) continue;
      grouped.putIfAbsent(resolved, () => <GdScriptPatchHunk>[]).add(
            GdScriptPatchHunk.fromJson(map),
          );
    }

    for (final entry in grouped.entries) {
      applyScriptPatchesToVirtualFile(
        resPath: entry.key,
        hunks: entry.value,
        featureId: featureId,
        releaseVersion: releaseVersion,
      );
    }
  }

  /// Fallback starter seed when AI step payloads omit `scriptPatches` for a new `.gd` asset.
  void seedCumulativeScriptFromStepsIfMissing({
    required String? primaryAssetString,
    required List<FeatureStateNode> states,
    required String featureId,
    required String releaseVersion,
  }) {
    final scriptPath = extractPrimaryScriptResPath(primaryAssetString);
    if (scriptPath == null) return;
    final existing = godotFileForResPath(scriptPath);
    if (existing != null && existing.content.trim().isNotEmpty) return;

    final hunks = <GdScriptPatchHunk>[];
    for (final node in states) {
      for (final entry in FeatureStateNode.iterStepEntries(node)) {
        final sub = entry.step;
        final snippet = (sub.codeSnippet ?? '').trim();
        if (snippet.isEmpty ||
            snippet.startsWith('|') ||
            snippet.contains('──►') ||
            snippet.contains('-->')) {
          continue;
        }
        final cleaned = snippet
            .split('\n')
            .map((l) => l.startsWith('+ ') ? l.substring(2) : (l.startsWith('+') && !l.startsWith('++') ? l.substring(1) : l))
            .join('\n')
            .trim();
        if (cleaned.isEmpty) continue;
        hunks.add(GdScriptPatchHunk(targetBlock: '', replaceBlock: cleaned));
      }
    }
    if (hunks.isNotEmpty) {
      applyScriptPatchesToVirtualFile(
        resPath: scriptPath,
        hunks: hunks,
        featureId: featureId,
        releaseVersion: releaseVersion,
      );
    }
  }
}
