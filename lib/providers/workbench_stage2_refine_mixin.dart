part of 'workbench_provider.dart';

/// Scoped Stage 2 Gemini 4 Hydrogen (`LOW` thinking) Refine + Undo support
/// for individual Epics (`§01-§04`) and Feature Slices (`§01-§05`).
extension WorkbenchStage2RefineMixin on WorkbenchProvider {
  void dismissStage2RefineError() {
    if (_stage2RefineError == null) return;
    _stage2RefineError = null;
    notifyListeners();
  }

  void _pushStage2UndoSnapshot({
    required String epicDocId,
    String? featureId,
    required EpicSpec snapshot,
    required String summary,
  }) {
    _syncStage2UndoProjectScope();
    _stage2UndoProjectId = _activeProjectId;
    _stage2UndoReleaseId = _activeReleaseId;
    _stage2UndoStack.add(
      _Stage2UndoEntry(
        epicDocId: epicDocId,
        featureId: featureId,
        snapshotJson: jsonEncode(snapshot.toJson()),
        summary: summary,
      ),
    );
    if (_stage2UndoStack.length > 15) {
      _stage2UndoStack.removeAt(0);
    }
  }

  static bool _ownersDiffer(
    List<EpicSceneOwnership> a,
    List<EpicSceneOwnership> b,
  ) {
    if (a.length != b.length) return true;
    for (int i = 0; i < a.length; i++) {
      if (a[i].path != b[i].path || a[i].role != b[i].role) return true;
    }
    return false;
  }

  /// Refines a Stage 2 Epic Domain Sheet via `Stage2RefineAgent` and saves with Undo history.
  Future<EpicSpec?> applyStage2EpicRefine(
    String epicId,
    String instruction,
  ) async {
    final clean = instruction.trim();
    final doc = documents[epicId];
    if (clean.isEmpty || doc == null || doc.tier != TierType.epic) return null;

    final startProjectId = _activeProjectId;
    final startReleaseId = _activeReleaseId;
    final idx = activeReleaseEpicDocs.indexWhere((d) => d.id == epicId);
    final beforeEpic = EpicSpec.fromDocument(doc, indexHint: idx >= 0 ? idx : 0);

    _isRefiningStage2 = true;
    _stage2RefineError = null;
    _agentProgressStep = 'Hydrogen refining ${beforeEpic.code} domain...';
    notifyListeners();

    try {
      final outcome = await Stage2RefineAgent.refineEpicSpec(
        rootSpec: _conceptDraft,
        epic: beforeEpic,
        instruction: clean,
        apiKey: _apiKey,
        mode: unrealArchitectureMode,
        preferredModel: _conversationModel,
        thinkingLevel: GeminiAgentClient.defaultFastThinkingLevel,
      );
      if (_isDisposed ||
          _activeProjectId != startProjectId ||
          _activeReleaseId != startReleaseId ||
          !documents.containsKey(epicId)) {
        return null;
      }

      if (outcome.epic == null) {
        _stage2RefineError = outcome.errorMessage ??
            'Could not refine ${beforeEpic.code}. Retry when ready.';
        return null;
      }

      final latestDoc = documents[epicId]!;
      if (latestDoc.tier != TierType.epic) return null;
      final latestIdx = activeReleaseEpicDocs.indexWhere((d) => d.id == epicId);
      final latestEpic = EpicSpec.fromDocument(
        latestDoc,
        indexHint: latestIdx >= 0 ? latestIdx : 0,
      );
      final patched = outcome.epic!;
      final merged = latestEpic.deepCopy();
      if (patched.title != beforeEpic.title) {
        merged.title = patched.title;
      }
      if (patched.goal != beforeEpic.goal) {
        merged.goal = patched.goal;
      }
      if (!listEquals(patched.inScope, beforeEpic.inScope)) {
        merged.inScope = List<String>.from(patched.inScope);
      }
      if (!listEquals(patched.doneWhen, beforeEpic.doneWhen)) {
        merged.doneWhen = List<String>.from(patched.doneWhen);
      }
      if (_ownersDiffer(patched.sceneOwnership, beforeEpic.sceneOwnership)) {
        merged.sceneOwnership = [
          for (final o in patched.sceneOwnership) o.copyWith(),
        ];
      }
      if (!listEquals(patched.stateFlow, beforeEpic.stateFlow)) {
        merged.stateFlow = List<String>.from(patched.stateFlow);
      }
      if (!listEquals(patched.interruptRules, beforeEpic.interruptRules)) {
        merged.interruptRules = List<String>.from(patched.interruptRules);
      }
      if (!listEquals(patched.outOfScope, beforeEpic.outOfScope)) {
        merged.outOfScope = List<String>.from(patched.outOfScope);
      }

      _pushStage2UndoSnapshot(
        epicDocId: epicId,
        featureId: null,
        snapshot: latestEpic,
        summary: outcome.summary,
      );
      final updatedDoc = merged.applyToDocument(latestDoc);
      documents[epicId] = updatedDoc;
      _lastStage2RefineSummary = outcome.summary;
      _lastStage2ChangedSections = outcome.changedSections;
      _persistDocument(updatedDoc);
      return EpicSpec.fromDocument(
        updatedDoc,
        indexHint: latestIdx >= 0 ? latestIdx : 0,
      );
    } catch (e) {
      if (!_isDisposed &&
          _activeProjectId == startProjectId &&
          _activeReleaseId == startReleaseId) {
        _stage2RefineError = 'Stage 2 refine error: $e';
      }
      return null;
    } finally {
      _isRefiningStage2 = false;
      _agentProgressStep = null;
      notifyListeners();
    }
  }

  /// Refines an unlocked Stage 2 Feature Slice Sheet via `Stage2RefineAgent` with Undo history.
  Future<FeatureSpec?> applyStage2FeatureRefine(
    String epicId,
    String featureId,
    String instruction,
  ) async {
    final clean = instruction.trim();
    final doc = documents[epicId];
    if (clean.isEmpty || doc == null || doc.tier != TierType.epic) return null;

    final startProjectId = _activeProjectId;
    final startReleaseId = _activeReleaseId;
    final idx = activeReleaseEpicDocs.indexWhere((d) => d.id == epicId);
    final beforeEpic = EpicSpec.fromDocument(doc, indexHint: idx >= 0 ? idx : 0);
    final relVer = _releaseVersionForEpicDoc(doc, beforeEpic);
    final featIdx = beforeEpic.features.indexWhere(
      (f) => f.id == featureId || f.code == featureId,
    );
    if (featIdx < 0) return null;

    final targetFeat = beforeEpic.features[featIdx];
    if (!_canEditFeature(targetFeat, releaseVersion: relVer)) {
      _stage2RefineError =
          '${targetFeat.code} is a locked ${targetFeat.introducedIn} baseline in $relVer. Open in ${targetFeat.introducedIn} or target a delta slice.';
      notifyListeners();
      return null;
    }

    _isRefiningStage2 = true;
    _stage2RefineError = null;
    _agentProgressStep = 'Hydrogen refining ${targetFeat.code} slice...';
    notifyListeners();

    try {
      final outcome = await Stage2RefineAgent.refineFeatureSpec(
        rootSpec: _conceptDraft,
        epic: beforeEpic,
        feature: targetFeat,
        instruction: clean,
        apiKey: _apiKey,
        releaseVersion: relVer,
        mode: unrealArchitectureMode,
        preferredModel: _conversationModel,
        thinkingLevel: GeminiAgentClient.defaultFastThinkingLevel,
      );
      if (_isDisposed ||
          _activeProjectId != startProjectId ||
          _activeReleaseId != startReleaseId ||
          !documents.containsKey(epicId)) {
        return null;
      }

      if (outcome.feature == null) {
        _stage2RefineError = outcome.errorMessage ??
            'Could not refine ${targetFeat.code}. Retry when ready.';
        return null;
      }

      final latestDoc = documents[epicId]!;
      if (latestDoc.tier != TierType.epic) return null;
      final latestIdx = activeReleaseEpicDocs.indexWhere((d) => d.id == epicId);
      final latestEpic = EpicSpec.fromDocument(
        latestDoc,
        indexHint: latestIdx >= 0 ? latestIdx : 0,
      );
      final latestRelVer = _releaseVersionForEpicDoc(latestDoc, latestEpic);
      final freshFeatIdx = latestEpic.features.indexWhere(
        (f) =>
            f.id == targetFeat.id || f.id == featureId || f.code == featureId,
      );
      if (freshFeatIdx < 0) return null;
      final freshFeat = latestEpic.features[freshFeatIdx];
      if (!_canEditFeature(freshFeat, releaseVersion: latestRelVer)) {
        _stage2RefineError =
            '${freshFeat.code} is a locked ${freshFeat.introducedIn} baseline in $latestRelVer. Open in ${freshFeat.introducedIn} or target a delta slice.';
        return null;
      }

      _pushStage2UndoSnapshot(
        epicDocId: epicId,
        featureId: freshFeat.id,
        snapshot: latestEpic,
        summary: outcome.summary,
      );

      final updatedEpic = latestEpic.deepCopy();
      final patchedFeat = outcome.feature!.deepCopy();
      patchedFeat.fixes = [for (final fx in freshFeat.fixes) fx.copyWith()];
      if (patchedFeat.status == FeatureStatus.passed &&
          (!patchedFeat.allEffectiveChecksPassedForRelease(latestRelVer) ||
              patchedFeat.openFixesCount > 0)) {
        patchedFeat.status = FeatureStatus.active;
      }
      updatedEpic.features[freshFeatIdx] = patchedFeat;
      _syncEpicLifecycleFromFeatures(updatedEpic, latestRelVer);

      final updatedDoc = updatedEpic.applyToDocument(latestDoc);
      documents[epicId] = updatedDoc;
      _lastStage2RefineSummary = outcome.summary;
      _lastStage2ChangedSections = outcome.changedSections;
      _persistDocument(updatedDoc);
      return patchedFeat;
    } catch (e) {
      if (!_isDisposed &&
          _activeProjectId == startProjectId &&
          _activeReleaseId == startReleaseId) {
        _stage2RefineError = 'Stage 2 refine error: $e';
      }
      return null;
    } finally {
      _isRefiningStage2 = false;
      _agentProgressStep = null;
      notifyListeners();
    }
  }

  /// Reverts the most recent Stage 2 AI or inline refine snapshot in the active release.
  bool undoStage2Edit() {
    _syncStage2UndoProjectScope();
    if (_stage2UndoStack.isEmpty) return false;
    final entry = _stage2UndoStack.removeLast();
    final doc = documents[entry.epicDocId];
    if (doc == null) {
      notifyListeners();
      return false;
    }

    final restoredEpic = EpicSpec.fromJson(
      jsonDecode(entry.snapshotJson) as Map<String, dynamic>,
    );
    final restoredDoc = restoredEpic.applyToDocument(doc);
    documents[entry.epicDocId] = restoredDoc;
    if (_selectedEpicId == entry.epicDocId &&
        _selectedFeatureId != null &&
        !restoredEpic.features.any((f) => f.id == _selectedFeatureId)) {
      _selectedFeatureId = null;
      _syncActiveProjectMetadata();
    }
    _lastStage2RefineSummary = 'Reverted: ${entry.summary}';
    _stage2RefineError = null;
    _lastStage2ChangedSections = const <String>{};
    _persistDocument(restoredDoc);
    notifyListeners();
    return true;
  }
}
