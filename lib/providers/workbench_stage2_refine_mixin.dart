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

  /// Refines a Stage 2 Epic Domain Sheet via `Stage2RefineAgent` and saves with Undo history.
  Future<EpicSpec?> applyStage2EpicRefine(
    String epicId,
    String instruction,
  ) async {
    final clean = instruction.trim();
    final doc = documents[epicId];
    if (clean.isEmpty || doc == null || doc.tier != TierType.epic) return null;

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
      if (_isDisposed) return null;

      if (outcome.epic == null) {
        _stage2RefineError = outcome.errorMessage ??
            'Could not refine ${beforeEpic.code}. Retry when ready.';
        return null;
      }

      _pushStage2UndoSnapshot(
        epicDocId: epicId,
        featureId: null,
        snapshot: beforeEpic,
        summary: outcome.summary,
      );
      final updatedDoc = outcome.epic!.applyToDocument(doc);
      documents[epicId] = updatedDoc;
      _lastStage2RefineSummary = outcome.summary;
      _lastStage2ChangedSections = outcome.changedSections;
      _persistDocument(updatedDoc);
      return EpicSpec.fromDocument(updatedDoc, indexHint: idx >= 0 ? idx : 0);
    } catch (e) {
      _stage2RefineError = 'Stage 2 refine error: $e';
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
        mode: unrealArchitectureMode,
        preferredModel: _conversationModel,
        thinkingLevel: GeminiAgentClient.defaultFastThinkingLevel,
      );
      if (_isDisposed) return null;

      if (outcome.feature == null) {
        _stage2RefineError = outcome.errorMessage ??
            'Could not refine ${targetFeat.code}. Retry when ready.';
        return null;
      }

      _pushStage2UndoSnapshot(
        epicDocId: epicId,
        featureId: targetFeat.id,
        snapshot: beforeEpic,
        summary: outcome.summary,
      );

      final updatedEpic = beforeEpic.deepCopy();
      updatedEpic.features[featIdx] = outcome.feature!;
      _syncEpicLifecycleFromFeatures(updatedEpic, relVer);

      final updatedDoc = updatedEpic.applyToDocument(doc);
      documents[epicId] = updatedDoc;
      _lastStage2RefineSummary = outcome.summary;
      _lastStage2ChangedSections = outcome.changedSections;
      _persistDocument(updatedDoc);
      return outcome.feature!;
    } catch (e) {
      _stage2RefineError = 'Stage 2 refine error: $e';
      return null;
    } finally {
      _isRefiningStage2 = false;
      _agentProgressStep = null;
      notifyListeners();
    }
  }

  /// Reverts the most recent Stage 2 AI or inline refine snapshot in the active project.
  bool undoStage2Edit() {
    _syncStage2UndoProjectScope();
    if (_stage2UndoStack.isEmpty) return false;
    final entry = _stage2UndoStack.removeLast();
    final doc = documents[entry.epicDocId];
    if (doc == null) return false;

    final restoredEpic = EpicSpec.fromJson(
      jsonDecode(entry.snapshotJson) as Map<String, dynamic>,
    );
    final restoredDoc = restoredEpic.applyToDocument(doc);
    documents[entry.epicDocId] = restoredDoc;
    _lastStage2RefineSummary = 'Reverted: ${entry.summary}';
    _stage2RefineError = null;
    _lastStage2ChangedSections = const <String>{};
    _persistDocument(restoredDoc);
    notifyListeners();
    return true;
  }
}
