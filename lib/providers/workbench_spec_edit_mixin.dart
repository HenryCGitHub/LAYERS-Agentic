part of 'workbench_provider.dart';

/// Direct inline manual CRUD operations for Stage 2 Epics (`§01-§04`) and
/// Feature Slices (`§01-§05`) with Undo snapshots and UnrealSpecGuard sanitization.
extension WorkbenchSpecEditMixin on WorkbenchProvider {
  List<String> _cleanSpecList(List<String> raw, UnrealArchitectureMode mode) =>
      raw
          .map((s) => UnrealSpecGuard.sanitizeLine(s, mode: mode).trim())
          .where((s) => s.isNotEmpty)
          .toList();

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

  /// Inserts or updates a shared UE5 Blueprint/level/class owner in Epic `§02`.
  void upsertEpicOwnership(
    String epicId, {
    int? index,
    required String path,
    String role = '',
  }) {
    final mode = unrealArchitectureMode;
    final cleanPath = UnrealSpecGuard.sanitizeLine(path, mode: mode).trim();
    if (cleanPath.isEmpty) return;
    final cleanRole = UnrealSpecGuard.sanitizeLine(role, mode: mode).trim();
    final isUpdate = index != null && index >= 0;
    _updateAndPersistEpic(epicId, (spec) {
      final hasTarget = isUpdate && index < spec.sceneOwnership.length;
      final summary = hasTarget ? 'Updated Epic owner' : 'Added Epic owner';
      _pushStage2UndoSnapshot(
        epicDocId: epicId,
        featureId: null,
        snapshot: spec.deepCopy(),
        summary: summary,
      );
      _lastStage2RefineSummary = summary;
      final entry = EpicSceneOwnership(path: cleanPath, role: cleanRole);
      if (hasTarget) {
        spec.sceneOwnership[index] = entry;
      } else {
        spec.sceneOwnership.add(entry);
      }
    });
  }

  /// Removes a shared UE5 asset/class owner at [index] from Epic `§02`.
  void removeEpicOwnership(String epicId, int index) {
    _updateAndPersistEpic(epicId, (spec) {
      if (index < 0 || index >= spec.sceneOwnership.length) return;
      _pushStage2UndoSnapshot(
        epicDocId: epicId,
        featureId: null,
        snapshot: spec.deepCopy(),
        summary: 'Removed Epic owner',
      );
      _lastStage2RefineSummary = 'Removed Epic owner';
      spec.sceneOwnership.removeAt(index);
    });
  }

  /// Updates an Epic's `§03` shared state flow and interrupt rules cleanly.
  void updateEpicStateRules(
    String epicId, {
    List<String>? stateFlow,
    List<String>? interruptRules,
  }) {
    final mode = unrealArchitectureMode;
    _updateAndPersistEpic(epicId, (spec) {
      final nextStates =
          stateFlow != null ? _cleanSpecList(stateFlow, mode) : null;
      final nextRules =
          interruptRules != null ? _cleanSpecList(interruptRules, mode) : null;
      if (nextStates == null && nextRules == null) return;
      _pushStage2UndoSnapshot(
        epicDocId: epicId,
        featureId: null,
        snapshot: spec.deepCopy(),
        summary: 'Edited Epic state rules',
      );
      _lastStage2RefineSummary = 'Edited Epic state rules';
      if (nextStates != null) spec.stateFlow = nextStates;
      if (nextRules != null) spec.interruptRules = nextRules;
    });
  }

  /// Appends a sanitized `No ...` exclusion rule to an Epic's `§04` Out-of-Scope cuts.
  void addEpicOutOfScopeCut(String epicId, String rawCut) {
    final cleanCut = UnrealSpecGuard.sanitizeExclusion(
      rawCut,
      mode: unrealArchitectureMode,
    );
    if (cleanCut.isEmpty) return;
    _updateAndPersistEpic(epicId, (spec) {
      if (spec.outOfScope.any(
        (c) => c.trim().toLowerCase() == cleanCut.toLowerCase(),
      )) {
        return;
      }
      _pushStage2UndoSnapshot(
        epicDocId: epicId,
        featureId: null,
        snapshot: spec.deepCopy(),
        summary: 'Added Epic cut: $cleanCut',
      );
      _lastStage2RefineSummary = 'Added Epic cut: $cleanCut';
      spec.outOfScope.add(cleanCut);
    });
  }

  /// Removes an out-of-scope cut at [index] from an Epic's `§04` list.
  void removeEpicOutOfScopeCut(String epicId, int index) {
    _updateAndPersistEpic(epicId, (spec) {
      if (index < 0 || index >= spec.outOfScope.length) return;
      _pushStage2UndoSnapshot(
        epicDocId: epicId,
        featureId: null,
        snapshot: spec.deepCopy(),
        summary: 'Removed Epic scope cut',
      );
      _lastStage2RefineSummary = 'Removed Epic scope cut';
      spec.outOfScope.removeAt(index);
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
    _updateAndPersistFeature(epicId, featureId, (spec, feat, relVer) {
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
        final cleanDelta = UnrealSpecGuard.sanitizeLine(
          releaseDelta,
          mode: mode,
        ).trim();
        if (relVer.trim() == feat.introducedIn.trim() ||
            cleanDelta.isNotEmpty) {
          feat.releaseDelta = cleanDelta;
        }
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

  /// Updates an exposed tuning variable value in Feature `§03`.
  void updateFeatureTuningParam(
    String epicId,
    String featureId,
    int paramIndex,
    String newValue,
  ) {
    final cleanVal = newValue.trim();
    _updateAndPersistFeature(
      epicId,
      featureId,
      (spec, feat, _) {
        if (paramIndex < 0 || paramIndex >= feat.tuning.length) return;
        final param = feat.tuning[paramIndex];
        if (param.value == cleanVal) return;
        _pushStage2UndoSnapshot(
          epicDocId: epicId,
          featureId: feat.id,
          snapshot: spec.deepCopy(),
          summary: 'Updated ${param.key} = $cleanVal',
        );
        _lastStage2RefineSummary = 'Updated ${param.key} = $cleanVal';
        param.value = cleanVal;
        for (final parentParam in spec.tuning) {
          if (parentParam.key.trim().toLowerCase() ==
              param.key.trim().toLowerCase()) {
            parentParam.value = cleanVal;
          }
        }
      },
      debounce: true,
    );
  }

  /// Adds or updates an exposed tuning variable in Feature `§03` with UE5 units.
  void addFeatureTuningParam(
    String epicId,
    String featureId, {
    required String key,
    required String value,
    required String unit,
  }) {
    final cleanKey = UnrealSpecGuard.sanitizeTuningKey(key, fallback: '');
    if (cleanKey.isEmpty) return;
    _updateAndPersistFeature(epicId, featureId, (spec, feat, _) {
      _pushStage2UndoSnapshot(
        epicDocId: epicId,
        featureId: feat.id,
        snapshot: spec.deepCopy(),
        summary: 'Updated tuning var $cleanKey',
      );
      _lastStage2RefineSummary = 'Updated tuning var $cleanKey';
      final nextVal = UnrealSpecGuard.scaleTuningValue(
        value.trim().isEmpty ? '0' : value.trim(),
        unit,
      );
      final nextUnit = UnrealSpecGuard.normalizeUnrealUnit(cleanKey, unit);
      final existingIdx = feat.tuning.indexWhere(
        (t) => t.key.trim().toLowerCase() == cleanKey.toLowerCase(),
      );
      if (existingIdx >= 0) {
        final existing = feat.tuning[existingIdx];
        existing.value = nextVal;
        existing.unit = unit.trim().isEmpty ? existing.unit : nextUnit;
      } else {
        feat.tuning.add(
          EpicTuningParam(
            key: cleanKey,
            value: nextVal,
            unit: nextUnit,
          ),
        );
      }
      for (final parentParam in spec.tuning) {
        if (parentParam.key.trim().toLowerCase() == cleanKey.toLowerCase()) {
          parentParam.value = nextVal;
          parentParam.unit = nextUnit;
        }
      }
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
      final isDeltaSlice = relVer.trim() != feat.introducedIn.trim() &&
          feat.releaseDelta.trim().isNotEmpty;
      final hasBase = !isDeltaSlice && feat.checks.any((c) => c.id == checkId);
      final hasDelta = feat.releaseDeltaChecks.any((c) => c.id == checkId);
      if (!hasBase && !hasDelta) return;
      _pushStage2UndoSnapshot(
        epicDocId: epicId,
        featureId: feat.id,
        snapshot: spec.deepCopy(),
        summary: 'Removed PIE check from ${feat.code}',
      );
      _lastStage2RefineSummary = 'Removed PIE check from ${feat.code}';
      if (!isDeltaSlice) {
        feat.checks.removeWhere((c) => c.id == checkId);
      }
      feat.releaseDeltaChecks.removeWhere((c) => c.id == checkId);
      _syncEpicLifecycleFromFeatures(spec, relVer);
    });
  }

  /// Navigates directly to the Stage 1 Project Brief document (`PROJECT_SPEC.md`).
  void selectProjectBrief() {
    _showingPlanNextRelease = false;
    _showingReleaseSpec = false;
    setStage(WorkbenchStage.projectPitch);
  }

  /// Navigates directly to the plain Release Spec page for [releaseId] (or active release).
  void selectReleaseSpec([String? releaseId]) {
    final targetId = releaseId ?? _activeReleaseId;
    if (targetId != null &&
        documents[targetId]?.tier == TierType.release &&
        targetId != _activeReleaseId) {
      _activeReleaseId = targetId;
    }
    if (activeRelease == null) return;
    _showingPlanNextRelease = false;
    _showingReleaseSpec = true;
    _currentStage = WorkbenchStage.releaseWorkbench;
    _syncActiveProjectMetadata();
    _syncStage2UndoProjectScope();
    notifyListeners();
  }

  /// Inline-edits Release Spec `title`, `goal`, or `doneWhen` with Undo history & local GDD sync.
  void updateReleaseSpec(
    String releaseId, {
    String? title,
    String? goal,
    String? doneWhen,
  }) {
    final rel = documents[releaseId];
    if (rel == null || rel.tier != TierType.release) return;
    final mode = unrealArchitectureMode;
    final ver = releaseVersionTagFor(rel);

    final nextTitle = title != null && title.trim().isNotEmpty
        ? UnrealSpecGuard.sanitizeLine(title, mode: mode)
        : rel.title;
    final nextGoal = goal != null
        ? UnrealSpecGuard.sanitizeLine(goal, mode: mode)
        : (rel.sections['goal'] ?? '');
    final nextDone = doneWhen != null
        ? UnrealSpecGuard.sanitizeLine(doneWhen, mode: mode)
        : (rel.sections['doneWhen'] ?? '');

    if (nextTitle == rel.title &&
        nextGoal == (rel.sections['goal'] ?? '') &&
        nextDone == (rel.sections['doneWhen'] ?? '')) {
      return;
    }

    _pushStage2ReleaseUndoSnapshot(
      releaseDoc: rel,
      summary: 'Edited $ver release spec',
    );
    _lastStage2RefineSummary = 'Edited $ver release spec';

    rel.title = nextTitle;
    rel.sections['goal'] = nextGoal;
    rel.sections['doneWhen'] = nextDone;
    if (ver == 'v0.1' && _conceptDraft != null) {
      _conceptDraft!.releaseDoneWhen = nextDone;
      _ensureActiveProjectDocument(_conceptDraft!);
    }
    _persistDocument(rel);
    notifyListeners();
  }

  /// Adds a new permanent Domain Epic (plus one starter Feature slice) to the active release.
  EpicSpec? addEpicToActiveRelease({
    required String title,
    String? goal,
  }) {
    final rel = activeRelease;
    final cleanTitle = UnrealSpecGuard.sanitizeLine(
      title,
      mode: unrealArchitectureMode,
    );
    if (rel == null || cleanTitle.isEmpty) return null;

    final existingEpics = activeReleaseEpics;
    int maxEpicNum = existingEpics.length;
    final epCodeRx = RegExp(r'^E(\d+)$', caseSensitive: false);
    for (final ep in existingEpics) {
      final m = epCodeRx.firstMatch(ep.code.trim());
      final parsed = m != null ? int.tryParse(m.group(1) ?? '') ?? 0 : 0;
      if (parsed > maxEpicNum) maxEpicNum = parsed;
    }
    final nextEpCode = EpicSpec.formatCode(maxEpicNum + 1);

    int maxFeatNum = 0;
    final featCodeRx = RegExp(r'^F(\d+)$', caseSensitive: false);
    for (final projRel in projectReleases) {
      for (final epDoc in epicDocsForRelease(projRel.id)) {
        for (final f in EpicSpec.fromDocument(epDoc).features) {
          final m = featCodeRx.firstMatch(f.code.trim());
          final parsed = m != null ? int.tryParse(m.group(1) ?? '') ?? 0 : 0;
          if (parsed > maxFeatNum) maxFeatNum = parsed;
        }
      }
    }
    final nextFeatCode = FeatureSpec.formatCode(maxFeatNum + 1);
    final relVer = releaseVersionTagFor(rel);
    final mode = unrealArchitectureMode;
    final cleanGoal = UnrealSpecGuard.sanitizeLine(
      (goal != null && goal.trim().isNotEmpty)
          ? goal
          : 'Handle $cleanTitle actors and shared domain state in PIE.',
      mode: mode,
    );
    final slug = cleanTitle
        .replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '')
        .trim();
    final bpOwner = '/Game/Blueprints/BP_${slug.isEmpty ? nextEpCode : slug}';
    final epDocId = '${rel.id}_epic_${DateTime.now().microsecondsSinceEpoch}';
    final featId = '${epDocId}_${nextFeatCode.toLowerCase()}';

    final rawEpic = EpicSpec(
      id: epDocId,
      lineageKey: nextEpCode.toLowerCase(),
      code: nextEpCode,
      releaseVersion: relVer,
      lifecycle: EpicLifecycle.active,
      title: cleanTitle,
      coreLoopBeat: cleanTitle,
      goal: cleanGoal,
      inScope: [cleanTitle],
      doneWhen: ['$cleanTitle responds cleanly in PIE with zero errors'],
      sceneOwnership: [
        EpicSceneOwnership(path: bpOwner, role: '$cleanTitle domain owner'),
      ],
      stateFlow: ['Idle', 'Active', 'Reset'],
      interruptRules: [
        'Pressing IA_QuickReset restores $cleanTitle state cleanly.',
      ],
      outOfScope: ['No unrelated UI menus in $nextEpCode'],
      features: [
        FeatureSpec(
          id: featId,
          code: nextFeatCode,
          title: '$cleanTitle Core',
          introducedIn: relVer,
          sliceTime: '45 min',
          status: FeatureStatus.active,
          goal: 'Implement $cleanTitle core loop cleanly in UE5 PIE.',
          inScope: ['$cleanTitle core action'],
          doneWhen: ['Trigger $cleanTitle -> Observable response runs in PIE'],
          controls: [
            EpicControlBinding(
              action: 'IA_PrimaryAction',
              trigger: 'Started (LMB / Space)',
              rule: 'Triggers $cleanTitle cleanly',
            ),
          ],
          tuning: [
            EpicTuningParam(
              key: 'PrimaryMagnitude',
              value: '300',
              unit: 'cm',
            ),
          ],
          cues: ['Visual feedback pulse + crisp activation audio cue'],
          checks: [
            EpicPieCheck(
              id: '${featId}_c1',
              text: 'Trigger $cleanTitle in PIE -> Expected response appears clearly',
            ),
          ],
        ),
      ],
    );
    final cleanEpic = UnrealSpecGuard.sanitizeEpicSpec(rawEpic, mode: mode);
    final epDoc = cleanEpic.toTierDocument(
      docId: epDocId,
      parentReleaseId: rel.id,
    );
    documents[epDocId] = epDoc;
    rel.childrenIds = [...rel.childrenIds, epDocId];
    rel.estimatedDuration = '${rel.childrenIds.length} Epics';
    _persistDocument(epDoc);
    _persistDocument(rel);
    notifyListeners();
    return cleanEpic;
  }

  /// Creates a quick slice directly from the left outline footer and marks it for title auto-focus.
  FeatureSpec? quickAddSliceToActiveRelease({String? epicId}) {
    final targetEpicId = epicId ??
        _selectedEpicId ??
        (activeReleaseEpicDocs.isNotEmpty
            ? activeReleaseEpicDocs.first.id
            : null);
    if (targetEpicId == null) return null;
    final created = addFeatureSlice(
      targetEpicId,
      title: 'New Playable Slice',
      goal: 'Build and test this playable slice cleanly in UE5 PIE.',
      selectCreated: true,
    );
    if (created == null) return null;
    _showingReleaseSpec = false;
    _showingPlanNextRelease = false;
    _currentStage = WorkbenchStage.releaseWorkbench;
    _autoFocusFeatureId = created.id;
    _syncActiveProjectMetadata();
    notifyListeners();
    return created;
  }
}
