part of 'workbench_provider.dart';

/// Direct inline manual CRUD operations for Stage 2 Epics (`§01-§04`) and
/// Feature Slices (`§01-§05`) with Undo snapshots and UnrealSpecGuard sanitization.
extension WorkbenchSpecEditMixin on WorkbenchProvider {
  void _captureEpicUndoBeforeEdit(
    String epicId, {
    String? featureId,
    required String summary,
  }) {
    final doc = documents[epicId];
    if (doc == null || doc.tier != TierType.epic) return;
    final idx = activeReleaseEpicDocs.indexWhere((d) => d.id == epicId);
    final snapshot = EpicSpec.fromDocument(doc, indexHint: idx >= 0 ? idx : 0);
    _pushStage2UndoSnapshot(
      epicDocId: epicId,
      featureId: featureId,
      snapshot: snapshot,
      summary: summary,
    );
    _lastStage2RefineSummary = summary;
  }

  /// Updates an Epic's `§01` Goal, In Scope, and Done When fields cleanly.
  void updateEpicScope(
    String epicId, {
    String? title,
    String? goal,
    List<String>? inScope,
    List<String>? doneWhen,
  }) {
    final mode = unrealArchitectureMode;
    _captureEpicUndoBeforeEdit(epicId, summary: 'Edited Epic domain scope');
    _updateAndPersistEpic(epicId, (spec) {
      if (title != null && title.trim().isNotEmpty) {
        spec.title = UnrealSpecGuard.sanitizeLine(title, mode: mode);
      }
      if (goal != null) {
        spec.goal = UnrealSpecGuard.sanitizeLine(goal, mode: mode);
      }
      if (inScope != null) {
        spec.inScope = _cleanSpecList(inScope, mode);
      }
      if (doneWhen != null) {
        spec.doneWhen = _cleanSpecList(doneWhen, mode);
      }
    });
  }

  /// Appends a sanitized `No ...` exclusion rule to an Epic's `§04` Out-of-Scope cuts.
  void addEpicOutOfScopeCut(String epicId, String rawCut) {
    final cleanCut = UnrealSpecGuard.sanitizeExclusion(
      rawCut,
      mode: unrealArchitectureMode,
    );
    if (cleanCut.isEmpty) return;
    _captureEpicUndoBeforeEdit(epicId, summary: 'Added Epic cut: $cleanCut');
    _updateAndPersistEpic(epicId, (spec) {
      if (!spec.outOfScope.any(
        (c) => c.trim().toLowerCase() == cleanCut.toLowerCase(),
      )) {
        spec.outOfScope.add(cleanCut);
      }
    });
  }

  /// Removes an out-of-scope cut at [index] from an Epic's `§04` list.
  void removeEpicOutOfScopeCut(String epicId, int index) {
    _captureEpicUndoBeforeEdit(epicId, summary: 'Removed Epic scope cut');
    _updateAndPersistEpic(epicId, (spec) {
      if (index >= 0 && index < spec.outOfScope.length) {
        spec.outOfScope.removeAt(index);
      }
    });
  }

  /// Updates an unlocked Feature slice's `§01` Goal, In Scope, Done When, or Delta note.
  void updateFeatureScope(
    String epicId,
    String featureId, {
    String? title,
    String? goal,
    List<String>? inScope,
    List<String>? doneWhen,
    String? releaseDelta,
  }) {
    final mode = unrealArchitectureMode;
    _updateAndPersistFeature(epicId, featureId, (spec, feat, _) {
      _pushStage2UndoSnapshot(
        epicDocId: epicId,
        featureId: feat.id,
        snapshot: spec.deepCopy(),
        summary: 'Edited ${feat.code} scope',
      );
      _lastStage2RefineSummary = 'Edited ${feat.code} scope';
      if (title != null && title.trim().isNotEmpty) {
        feat.title = UnrealSpecGuard.sanitizeLine(title, mode: mode);
      }
      if (goal != null) {
        feat.goal = UnrealSpecGuard.sanitizeLine(goal, mode: mode);
      }
      if (inScope != null) {
        feat.inScope = _cleanSpecList(inScope, mode);
      }
      if (doneWhen != null) {
        feat.doneWhen = _cleanSpecList(doneWhen, mode);
      }
      if (releaseDelta != null) {
        feat.releaseDelta = UnrealSpecGuard.sanitizeLine(
          releaseDelta,
          mode: mode,
        );
      }
    });
  }

  /// Inserts or updates an Enhanced Input (`IA_*`) binding row in Feature `§02`.
  void upsertFeatureControl(
    String epicId,
    String featureId, {
    int? index,
    required String action,
    required String trigger,
    required String rule,
  }) {
    final mode = unrealArchitectureMode;
    final cleanAction = UnrealSpecGuard.sanitizeInputActionName(action);
    final cleanTrigger = UnrealSpecGuard.sanitizeLine(trigger, mode: mode);
    final cleanRule = UnrealSpecGuard.sanitizeLine(rule, mode: mode);
    if (cleanRule.isEmpty && cleanTrigger.isEmpty) return;

    final binding = EpicControlBinding(
      action: cleanAction,
      trigger: cleanTrigger.isEmpty ? 'Triggered' : cleanTrigger,
      rule: cleanRule,
    );
    _updateAndPersistFeature(epicId, featureId, (spec, feat, _) {
      _pushStage2UndoSnapshot(
        epicDocId: epicId,
        featureId: feat.id,
        snapshot: spec.deepCopy(),
        summary: 'Updated ${feat.code} input $cleanAction',
      );
      _lastStage2RefineSummary = 'Updated ${feat.code} input $cleanAction';
      if (index != null && index >= 0 && index < feat.controls.length) {
        feat.controls[index] = binding;
      } else {
        feat.controls.add(binding);
      }
    });
  }

  /// Removes an Enhanced Input binding row at [index] from Feature `§02`.
  void removeFeatureControl(String epicId, String featureId, int index) {
    _updateAndPersistFeature(epicId, featureId, (spec, feat, _) {
      if (index < 0 || index >= feat.controls.length) return;
      _pushStage2UndoSnapshot(
        epicDocId: epicId,
        featureId: feat.id,
        snapshot: spec.deepCopy(),
        summary: 'Removed input from ${feat.code}',
      );
      _lastStage2RefineSummary = 'Removed input from ${feat.code}';
      feat.controls.removeAt(index);
    });
  }

  /// Removes an exposed tuning parameter at [index] from Feature `§03`.
  void removeFeatureTuningParam(String epicId, String featureId, int index) {
    _updateAndPersistFeature(epicId, featureId, (spec, feat, _) {
      if (index < 0 || index >= feat.tuning.length) return;
      _pushStage2UndoSnapshot(
        epicDocId: epicId,
        featureId: feat.id,
        snapshot: spec.deepCopy(),
        summary: 'Removed tuning var ${feat.tuning[index].key}',
      );
      _lastStage2RefineSummary = 'Removed tuning var ${feat.tuning[index].key}';
      feat.tuning.removeAt(index);
    });
  }

  /// Appends a viewport/audio/UI cue line to Feature `§04`.
  void addFeatureCue(String epicId, String featureId, String cueText) {
    final clean = UnrealSpecGuard.sanitizeLine(
      cueText,
      mode: unrealArchitectureMode,
    );
    if (clean.isEmpty) return;
    _updateAndPersistFeature(epicId, featureId, (spec, feat, _) {
      _pushStage2UndoSnapshot(
        epicDocId: epicId,
        featureId: feat.id,
        snapshot: spec.deepCopy(),
        summary: 'Added cue to ${feat.code}',
      );
      _lastStage2RefineSummary = 'Added cue to ${feat.code}';
      feat.cues.add(clean);
    });
  }

  /// Removes a viewport/audio/UI cue at [index] from Feature `§04`.
  void removeFeatureCue(String epicId, String featureId, int index) {
    _updateAndPersistFeature(epicId, featureId, (spec, feat, _) {
      if (index < 0 || index >= feat.cues.length) return;
      _pushStage2UndoSnapshot(
        epicDocId: epicId,
        featureId: feat.id,
        snapshot: spec.deepCopy(),
        summary: 'Removed cue from ${feat.code}',
      );
      _lastStage2RefineSummary = 'Removed cue from ${feat.code}';
      feat.cues.removeAt(index);
    });
  }

  /// Adds a PIE Playtest check to Feature `§05` (or to `releaseDeltaChecks` on upgraded v0.2+ slices).
  void addFeatureCheck(String epicId, String featureId, String checkText) {
    final clean = UnrealSpecGuard.sanitizeLine(
      checkText,
      mode: unrealArchitectureMode,
    );
    if (clean.isEmpty) return;
    _updateAndPersistFeature(epicId, featureId, (spec, feat, relVer) {
      _pushStage2UndoSnapshot(
        epicDocId: epicId,
        featureId: feat.id,
        snapshot: spec.deepCopy(),
        summary: 'Added PIE check to ${feat.code}',
      );
      _lastStage2RefineSummary = 'Added PIE check to ${feat.code}';
      final entry = EpicPieCheck(
        id: '${feat.id}_chk_${DateTime.now().microsecondsSinceEpoch}',
        text: clean,
      );
      if (relVer != 'v0.1' && feat.releaseDelta.trim().isNotEmpty) {
        feat.releaseDeltaChecks.add(entry);
      } else {
        feat.checks.add(entry);
      }
      if (feat.status == FeatureStatus.passed) {
        feat.status = FeatureStatus.active;
      }
      _syncEpicLifecycleFromFeatures(spec, relVer);
    });
  }

  /// Removes a PIE Playtest check by [checkId] from Feature `§05`.
  void removeFeatureCheck(String epicId, String featureId, String checkId) {
    _updateAndPersistFeature(epicId, featureId, (spec, feat, relVer) {
      final hasBase = feat.checks.any((c) => c.id == checkId);
      final hasDelta = feat.releaseDeltaChecks.any((c) => c.id == checkId);
      if (!hasBase && !hasDelta) return;
      _pushStage2UndoSnapshot(
        epicDocId: epicId,
        featureId: feat.id,
        snapshot: spec.deepCopy(),
        summary: 'Removed PIE check from ${feat.code}',
      );
      _lastStage2RefineSummary = 'Removed PIE check from ${feat.code}';
      feat.checks.removeWhere((c) => c.id == checkId);
      feat.releaseDeltaChecks.removeWhere((c) => c.id == checkId);
      _syncEpicLifecycleFromFeatures(spec, relVer);
    });
  }
}
