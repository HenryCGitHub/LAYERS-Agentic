part of 'workbench_provider.dart';

/// Godot 4 Contract, cumulative Cloud-saved `TierType.codeFile` scripts, patch applier, and safe Folder Sync.
extension WorkbenchGodotMixin on WorkbenchProvider {
  bool get isCloudSaveReady =>
      _isCloudSynced || (isUserLoggedIn && isSessionApprovedForAi);

  bool get isGodotFolderSyncSupported => _godotSync.isSupported;
  String get godotFolderSyncUnsupportedReason => _godotSync.unsupportedReason;
  bool get isGodotFolderLinked => _godotSync.isLinked;
  String get linkedGodotFolderLabel => _godotSync.linkedFolderLabel;

  Map<String, String> get diskPulledGodotFiles =>
      Map.unmodifiable(_diskPulledFilesByResPath);

  List<String> patchWarningsForResPath(String resPath) =>
      List.unmodifiable(
        _lastPatchWarningsByResPath[GodotVirtualFile.normalizeResPath(resPath)] ??
            const [],
      );

  List<GdScriptPatchHunk> unmatchedPatchHunksForResPath(String resPath) =>
      List.unmodifiable(
        _unmatchedHunksByResPath[GodotVirtualFile.normalizeResPath(resPath)] ??
            const [],
      );

  bool isDocPendingCloudWrite(String docId) =>
      _pendingCloudWriteDocIds.contains(docId);

  bool canUndoDiskWrite(String resPath) =>
      _godotSync.canUndo(GodotVirtualFile.normalizeResPath(resPath));

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
    String? lastDiskHash,
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
      lastDiskHash: (lastDiskHash ?? existing?.lastDiskHash ?? '').trim(),
    );

    final doc = vf.toTierDocument();
    documents[doc.id] = doc;
    _persistDocument(doc);
    if (!silent) {
      notifyListeners();
    }
    return vf;
  }

  /// Applies surgical `{targetBlock, replaceBlock}` hunks onto the stored (or disk-pulled) `.gd` file.
  GdScriptPatchResult applyScriptPatchesToVirtualFile({
    required String resPath,
    required List<GdScriptPatchHunk> hunks,
    String? featureId,
    String? releaseVersion,
    bool silent = false,
  }) {
    final normPath = GodotVirtualFile.normalizeResPath(resPath);
    final existing = godotFileForResPath(normPath);
    final diskBaseline = _diskPulledFilesByResPath[normPath] ?? '';
    final baseContent =
        (existing != null && existing.content.trim().isNotEmpty)
            ? existing.content
            : diskBaseline;

    final result = GodotGdscriptGuard.applyPatchHunks(
      existingContent: baseContent,
      hunks: hunks,
    );

    if (result.warnings.isNotEmpty) {
      _lastPatchWarningsByResPath[normPath] = result.warnings;
    } else {
      _lastPatchWarningsByResPath.remove(normPath);
    }
    if (result.unmatchedHunks.isNotEmpty) {
      _unmatchedHunksByResPath[normPath] = result.unmatchedHunks;
    } else {
      _unmatchedHunksByResPath.remove(normPath);
    }

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

  /// Links a local Godot 4 project folder, performs read-only pull of `project.godot` + `.gd`/`.tres` files,
  /// and seeds missing Cloud virtual files without overwriting existing Cloud edits.
  Future<GodotFolderSnapshot> linkGodotProjectFolder({
    String? directoryPath,
  }) async {
    final snapshot =
        await _godotSync.linkAndPullFolder(directoryPath: directoryPath);
    if (snapshot.ok) {
      _ingestDiskSnapshot(snapshot);
    } else {
      notifyListeners();
    }
    return snapshot;
  }

  Future<GodotFolderSnapshot> refreshLinkedGodotFolder() async {
    final snapshot = await _godotSync.refreshLinkedFolder();
    if (snapshot.ok) {
      _ingestDiskSnapshot(snapshot);
    } else {
      notifyListeners();
    }
    return snapshot;
  }

  void _ingestDiskSnapshot(GodotFolderSnapshot snapshot) {
    _diskPulledFilesByResPath
      ..clear()
      ..addAll(snapshot.filesByResPath);

    if (snapshot.projectGodotText != null &&
        snapshot.projectGodotText!.trim().isNotEmpty) {
      final updatedContract = activeGodotContract.mergeFromProjectGodotIni(
        snapshot.projectGodotText!,
      );
      updateGodotContract(updatedContract);
    }

    // Seed disk-discovered files into Cloud `TierType.codeFile` only when missing or previously identical,
    // so Cloud edits never get silently clobbered by a read-only pull.
    for (final entry in snapshot.filesByResPath.entries) {
      final normPath = GodotVirtualFile.normalizeResPath(entry.key);
      final diskHash = GodotVirtualFile.computeContentHash(entry.value);
      final existing = godotFileForResPath(normPath);
      if (existing == null || existing.content.trim().isEmpty) {
        upsertGodotVirtualFile(
          resPath: normPath,
          content: entry.value,
          lastDiskHash: diskHash,
          silent: true,
        );
      } else if (existing.contentHash == diskHash && existing.lastDiskHash != diskHash) {
        upsertGodotVirtualFile(
          resPath: normPath,
          content: existing.content,
          lastDiskHash: diskHash,
          silent: true,
        );
      }
    }
    notifyListeners();
  }

  /// Computes a Red/Green unified diff comparing current disk contents against the Cloud virtual file.
  List<GodotDiffLine> previewDiskDiffForResPath(String resPath) {
    final norm = GodotVirtualFile.normalizeResPath(resPath);
    final diskText = _diskPulledFilesByResPath[norm] ?? '';
    final cloudText = godotFileForResPath(norm)?.content ?? '';
    return GodotVirtualFile.computeUnifiedDiff(diskText, cloudText);
  }

  /// Writes a diff-reviewed `.gd` or `.tres` file to disk with an automatic Undo snapshot.
  Future<GodotWriteResult> applyVirtualFileToDisk(String resPath) async {
    final norm = GodotVirtualFile.normalizeResPath(resPath);
    final vf = godotFileForResPath(norm);
    if (vf == null) {
      return GodotWriteResult(
        success: false,
        resPath: norm,
        message: 'No stored file found for $norm.',
      );
    }
    final res = await _godotSync.writeAllowedFile(
      resPath: norm,
      content: vf.content,
    );
    if (res.success) {
      _diskPulledFilesByResPath[norm] = vf.content;
      upsertGodotVirtualFile(
        resPath: norm,
        content: vf.content,
        lastDiskHash: vf.contentHash,
      );
    }
    notifyListeners();
    return res;
  }

  /// Restores the prior on-disk version saved before the most recent `applyVirtualFileToDisk`.
  Future<GodotWriteResult> undoLastDiskWrite(String resPath) async {
    final norm = GodotVirtualFile.normalizeResPath(resPath);
    final res = await _godotSync.undoLastWrite(norm);
    if (res.success) {
      final restored = await _godotSync.readDiskFile(norm);
      if (restored != null) {
        _diskPulledFilesByResPath[norm] = restored;
      } else {
        _diskPulledFilesByResPath.remove(norm);
      }
    }
    notifyListeners();
    return res;
  }

  void unlinkGodotProjectFolder() {
    _godotSync.unlink();
    _diskPulledFilesByResPath.clear();
    notifyListeners();
  }

  /// Builds a concise prompt context containing the Godot Project Contract and current stored/disk `.gd` code
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
      final currentCode = _diskPulledFilesByResPath[norm] ??
          godotFileForResPath(norm)?.content ??
          '';
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
