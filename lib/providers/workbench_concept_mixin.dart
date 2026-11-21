part of 'workbench_provider.dart';

/// Stage 1 actions: Spark Onboarding, Preset Packs, 3D | 2D Dimension toggle,
/// vague-spark clarification forks, scoped Co-Designer edits, Undo stack,
/// lean inline edits, and `Approve & Launch Godot Workbench`.
extension WorkbenchConceptMixin on WorkbenchProvider {
  void _pushStage1UndoSnapshot() {
    final draft = _conceptDraft;
    if (draft == null || !draft.hasSpec) return;
    _stage1UndoStack.add(draft.deepCopy());
    if (_stage1UndoStack.length > 12) {
      _stage1UndoStack.removeAt(0);
    }
  }

  bool undoStage1Edit() {
    if (_stage1UndoStack.isEmpty || _isAgentBusy) return false;
    final restored = _stage1UndoStack.removeLast();
    restored.lastCoDesignNote = 'Reverted last Stage 1 change.';
    _conceptDraft = restored;
    _lastStage1ChangedSections = const <String>{};
    _stage1InlineError = null;
    _offlineErrorMessage = null;
    _ensureActiveProjectDocument(restored);
    notifyListeners();
    return true;
  }

  void dismissStage1InlineError() {
    if (_stage1InlineError == null) return;
    _stage1InlineError = null;
    notifyListeners();
  }

  void previewDimensionFromSparkText(String rawText) {
    var changed = false;
    if (_pendingSparkClarification != null &&
        _pendingSparkClarification!.rawSpark != rawText.trim()) {
      _pendingSparkClarification = null;
      changed = true;
    }
    if (_stage1InlineError != null) {
      _stage1InlineError = null;
      changed = true;
    }
    if (!_userPinnedDimension &&
        (_conceptDraft == null || !_conceptDraft!.hasSpec)) {
      final detected = GodotProjectDimension.detectFromSpark(rawText);
      if (detected != projectDimension) {
        _conceptDraft = ProjectConceptBlueprint(
          sparkPrompt: rawText.trim(),
          gameTitle: _conceptDraft?.gameTitle ?? 'UNTITLED GODOT PROJECT',
          dimension: detected,
        );
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  void _ensureActiveProjectDocument(ProjectConceptBlueprint bp) {
    final String pid = _activeProjectId ??
        () {
          final baseMs = DateTime.now().millisecondsSinceEpoch;
          var candidate = 'proj_$baseMs';
          var suffix = 1;
          while (documents.containsKey(candidate)) {
            candidate = 'proj_${baseMs}_$suffix';
            suffix++;
          }
          return candidate;
        }();
    _activeProjectId = pid;
    _unpersistedNewProjectId = null;
    final existing = documents[pid];
    final nextSections = Map<String, String>.from(
      existing?.sections ?? const <String, String>{},
    );
    nextSections['concept_blueprint_json'] = jsonEncode(bp.toJson());
    nextSections['engine'] = bp.dimension.shortLabel;
    nextSections['dimension'] = bp.dimension.id;
    nextSections['current_stage'] = _currentStage.name;

    final updated = (existing ??
            TierDocument(
              id: pid,
              title: bp.normalizedTitle,
              tier: TierType.project,
              childrenIds: const <String>[],
            ))
        .copyWith(
          title: bp.normalizedTitle,
          tier: TierType.project,
          sections: nextSections,
        );
    documents[pid] = updated;
    _persistDocument(updated);
    _persistSettings();
  }

  void loadPresetSpark(String presetId) {
    final preset = GodotSparkPresets.byId(presetId);
    _userPinnedDimension = false;
    _clearStage1TransientState();
    _offlineErrorMessage = null;
    _conceptDraft = preset;
    _showingSparkPicker = false;
    _currentStage = WorkbenchStage.projectPitch;
    _ensureActiveProjectDocument(preset);
    notifyListeners();
  }

  Future<ProjectConceptBlueprint?> handleStage1SparkSubmit(
    String sparkPrompt,
  ) async {
    final cleanPrompt = sparkPrompt.trim();
    if (cleanPrompt.isEmpty || _isAgentBusy) return null;
    _stage1InlineError = null;
    _offlineErrorMessage = null;
    if (SparkClarificationDraft.isSparkVague(cleanPrompt)) {
      _pendingSparkClarification = SparkClarificationDraft.suggestFromSpark(
        cleanPrompt,
        pinnedDimension: _userPinnedDimension ? projectDimension : null,
      );
      notifyListeners();
      return null;
    }
    _pendingSparkClarification = null;
    return generateSpecFromSpark(cleanPrompt);
  }

  void updateSparkClarification({
    GodotProjectDimension? dimension,
    String? viewChoiceId,
    String? archetypeId,
    String? prototypeHookId,
  }) {
    final pending = _pendingSparkClarification;
    if (pending == null) return;
    if (dimension != null) {
      _userPinnedDimension = true;
      setProjectDimension(dimension);
    }
    _pendingSparkClarification = pending.copyWith(
      dimension: dimension,
      viewChoiceId: viewChoiceId,
      archetypeId: archetypeId,
      prototypeHookId: prototypeHookId,
    );
    notifyListeners();
  }

  void dismissSparkClarification() {
    if (_pendingSparkClarification == null) return;
    _pendingSparkClarification = null;
    notifyListeners();
  }

  Future<ProjectConceptBlueprint?> confirmSparkClarification({
    bool skipPicks = false,
  }) async {
    final pending = _pendingSparkClarification;
    if (pending == null || _isAgentBusy) return null;
    final savedPending = pending;
    _pendingSparkClarification = null;
    _stage1InlineError = null;
    notifyListeners();
    final ProjectConceptBlueprint? result = skipPicks
        ? await generateSpecFromSpark(
            savedPending.rawSpark,
            explicitDimension: _userPinnedDimension ? projectDimension : null,
          )
        : await generateSpecFromSpark(
            savedPending.buildEnrichedSpark(),
            explicitDimension: savedPending.dimension,
            archetypeId: savedPending.archetypeId,
            viewChoiceId: savedPending.viewChoiceId,
            prototypeHookId: savedPending.prototypeHookId,
          );
    if (result == null &&
        (_conceptDraft == null || !_conceptDraft!.hasSpec)) {
      _pendingSparkClarification = savedPending;
      notifyListeners();
    }
    return result;
  }

  Future<ProjectConceptBlueprint?> generateSpecFromSpark(
    String sparkPrompt, {
    GodotProjectDimension? explicitDimension,
    String? archetypeId,
    String? viewChoiceId,
    String? prototypeHookId,
  }) async {
    final cleanPrompt = sparkPrompt.trim();
    if (cleanPrompt.isEmpty) return null;

    _isAgentBusy = true;
    _agentProgressStep = 'Drafting Godot 4 Root Spec (PROJECT_SPEC.md)...';
    _offlineErrorMessage = null;
    _stage1InlineError = null;
    notifyListeners();

    try {
      final outcome = await ProjectConceptAgent.draftSpecWithStatus(
        sparkPrompt: cleanPrompt,
        apiKey: _apiKey,
        dimensionOverride:
            explicitDimension ?? (_userPinnedDimension ? projectDimension : null),
        archetypeId: archetypeId,
        viewChoiceId: viewChoiceId,
        prototypeHookId: prototypeHookId,
        preferredModel: _planningModel,
        thinkingLevel: _thinkingLevel,
      );
      if (outcome.blueprint == null) {
        final msg = outcome.errorMessage ??
            'Cloud Gemini did not return a valid Project Spec. Please retry.';
        _stage1InlineError = msg;
        _offlineErrorMessage = msg;
        return null;
      }
      _stage1UndoStack.clear();
      _lastStage1ChangedSections = const <String>{};
      _pendingSparkClarification = null;
      _stage1InlineError = null;
      _offlineErrorMessage = null;
      _conceptDraft = outcome.blueprint;
      _userPinnedDimension = false;
      _showingSparkPicker = false;
      _currentStage = WorkbenchStage.projectPitch;
      _ensureActiveProjectDocument(outcome.blueprint!);
      return outcome.blueprint;
    } catch (e) {
      final msg = 'Spec generation error: $e';
      _stage1InlineError = msg;
      _offlineErrorMessage = msg;
      return null;
    } finally {
      _isAgentBusy = false;
      _agentProgressStep = null;
      flushDeferredRemoteSnapshotIfIdle();
      notifyListeners();
    }
  }

  Future<ProjectConceptBlueprint?> applyStage1CoDesignInstruction(
    String instruction,
  ) async {
    final draft = _conceptDraft;
    final clean = instruction.trim();
    if (draft == null || clean.isEmpty) return null;

    _isAgentBusy = true;
    _agentProgressStep = 'Co-Designer updating ROOT_GODOT_CONTEXT...';
    _offlineErrorMessage = null;
    _stage1InlineError = null;
    notifyListeners();

    try {
      final outcome = await ProjectConceptAgent.applyCoDesignEditWithStatus(
        currentSpec: draft,
        instruction: clean,
        apiKey: _apiKey,
        preferredModel: _conversationModel,
        thinkingLevel: _thinkingLevel,
      );
      if (outcome.blueprint == null) {
        final msg = outcome.errorMessage ??
            'Co-Designer refine failed. Retry when ready.';
        _stage1InlineError = msg;
        _offlineErrorMessage = msg;
        return null;
      }
      _pushStage1UndoSnapshot();
      _stage1InlineError = null;
      _offlineErrorMessage = null;
      _lastStage1ChangedSections = outcome.changedSections;
      _conceptDraft = outcome.blueprint;
      _ensureActiveProjectDocument(outcome.blueprint!);
      return outcome.blueprint;
    } catch (e) {
      final msg = 'Co-Designer edit error: $e';
      _stage1InlineError = msg;
      _offlineErrorMessage = msg;
      return null;
    } finally {
      _isAgentBusy = false;
      _agentProgressStep = null;
      flushDeferredRemoteSnapshotIfIdle();
      notifyListeners();
    }
  }

  void setProjectDimension(GodotProjectDimension dim) {
    _userPinnedDimension = true;
    final draft = _conceptDraft;
    if (draft == null) {
      _conceptDraft = ProjectConceptBlueprint(dimension: dim);
    } else if (draft.hasSpec) {
      if (draft.dimension == dim) return;
      _pushStage1UndoSnapshot();
      final converted = ProjectConceptAgent.convertBlueprintDimension(draft, dim);
      converted.lastCoDesignNote =
          'Switched project dimension to ${dim.shortLabel}.';
      _conceptDraft = converted;
      _lastStage1ChangedSections = const <String>{'s02', 's05'};
    } else {
      _conceptDraft = ProjectConceptBlueprint(
        sparkPrompt: draft.sparkPrompt,
        gameTitle: draft.gameTitle,
        dimension: dim,
      );
    }
    if (_pendingSparkClarification != null) {
      _pendingSparkClarification =
          _pendingSparkClarification!.copyWith(dimension: dim);
    }
    if (activeProject != null && _conceptDraft != null) {
      _ensureActiveProjectDocument(_conceptDraft!);
    }
    notifyListeners();
  }

  void selectCameraDecisionOption(String optionId) {
    final draft = _conceptDraft;
    if (draft == null) return;
    for (final opt in draft.effectiveCameraDecisionOptions) {
      if (opt.id == optionId) {
        _pushStage1UndoSnapshot();
        draft.cameraChoiceId = opt.id;
        draft.cameraContract = opt.contractValue;
        ProjectConceptAgent.syncEpicCameraFraming(
          draft,
          optionId: opt.id,
          contractValue: opt.contractValue,
        );
        draft.lastCoDesignNote =
            'Camera contract & E01 look framing set to ${opt.label}.';
        _lastStage1ChangedSections = const <String>{'s02', 's05'};
        _ensureActiveProjectDocument(draft);
        notifyListeners();
        return;
      }
    }
  }

  void selectCoreFeelOption(String feelId) {
    final draft = _conceptDraft;
    if (draft == null) return;
    _pushStage1UndoSnapshot();
    final chosen = ProjectConceptBlueprint.coreFeelOptionById(feelId);
    ProjectConceptAgent.syncEpicCoreFeel(draft, feelId: chosen.id);
    draft.lastCoDesignNote =
        'Core feel & E01 locomotion set to ${chosen.label}.';
    _lastStage1ChangedSections = const <String>{'s03', 's05'};
    _ensureActiveProjectDocument(draft);
    notifyListeners();
  }

  /// Clears the active unapproved draft back to empty Stage 1 intake, or opens a fresh Stage 1
  /// project when existing approved Releases exist so saved project work is preserved.
  void resetStage1ToNewIdea() {
    final dim = projectDimension;
    _clearStage1TransientState();
    if (projectReleases.isNotEmpty) {
      createNewProject();
      _userPinnedDimension = false;
      _conceptDraft = ProjectConceptBlueprint(dimension: dim);
      notifyListeners();
      return;
    }
    final orphanId = _activeProjectId;
    if (orphanId != null) {
      _persistTimers.remove(orphanId)?.cancel();
      documents.remove(orphanId);
      LocalVaultService.deleteDocument(orphanId);
      final user = _authService.currentUser;
      if (user != null) {
        _firestoreService.deleteDocument(uid: user.uid, docId: orphanId);
      }
    }
    _activeProjectId = 'proj_${DateTime.now().millisecondsSinceEpoch}';
    _unpersistedNewProjectId = _activeProjectId;
    _activeReleaseId = null;
    _selectedEpicId = null;
    _selectedFeatureId = null;
    _expandedEpicIds.clear();
    _resetProgressiveDraftState();
    _executionLog.clear();
    _userPinnedDimension = false;
    _conceptDraft = ProjectConceptBlueprint(dimension: dim);
    _showingSparkPicker = true;
    _offlineErrorMessage = null;
    _currentStage = WorkbenchStage.projectPitch;
    _persistSettings();
    notifyListeners();
  }

  void _renumberInitialEpics(ProjectConceptBlueprint draft) {
    ProjectConceptAgent.normalizeSequentialEpicAndFeatureCodes(draft);
  }

  /// Reorders a Stage 1 `§05` prototype Epic (`delta = -1` up, `+1` down) while keeping `id` & `lineageKey`.
  void moveInitialEpic(int index, int delta) {
    final draft = _conceptDraft;
    if (draft == null) return;
    final newIndex = index + delta;
    if (index < 0 ||
        index >= draft.initialEpics.length ||
        newIndex < 0 ||
        newIndex >= draft.initialEpics.length ||
        newIndex == index) {
      return;
    }
    _pushStage1UndoSnapshot();
    final moved = draft.initialEpics.removeAt(index);
    draft.initialEpics.insert(newIndex, moved);
    _renumberInitialEpics(draft);
    draft.lastCoDesignNote =
        'Reordered §05 queue: ${moved.title} -> ${moved.code}.';
    _lastStage1ChangedSections = const <String>{'s05'};
    _ensureActiveProjectDocument(draft);
    notifyListeners();
  }

  /// Prunes a Stage 1 `§05` prototype Epic (keeping at least 1 Epic in `v0.1`).
  void removeInitialEpicAt(int index) {
    final draft = _conceptDraft;
    if (draft == null ||
        draft.initialEpics.length <= 1 ||
        index < 0 ||
        index >= draft.initialEpics.length) {
      return;
    }
    _pushStage1UndoSnapshot();
    final removed = draft.initialEpics.removeAt(index);
    _renumberInitialEpics(draft);
    draft.lastCoDesignNote = 'Removed ${removed.title} from Stage 1 §05.';
    _lastStage1ChangedSections = const <String>{'s05'};
    _ensureActiveProjectDocument(draft);
    notifyListeners();
  }

  void updateRootSpecSections({
    String? gameTitle,
    String? pitch,
    String? cameraContract,
    String? characterScale,
    String? inputContract,
    String? assetPolicy,
    String? releaseDoneWhen,
    List<String>? coreLoop,
    List<String>? pillars,
    List<String>? outOfScope,
  }) {
    final draft = _conceptDraft;
    if (draft == null) return;
    _pushStage1UndoSnapshot();
    final dim = draft.dimension;
    final changed = <String>{};
    if (gameTitle != null && gameTitle.trim().isNotEmpty) {
      draft.gameTitle = gameTitle.trim().toUpperCase();
      changed.add('s01');
    }
    if (pitch != null && pitch.trim().isNotEmpty) {
      draft.pitch = GodotSpecGuard.sanitizeLine(pitch, dimension: dim);
      changed.add('s01');
    }
    if (cameraContract != null) {
      draft.cameraContract =
          GodotSpecGuard.sanitizeLine(cameraContract, dimension: dim);
      changed.add('s02');
    }
    if (characterScale != null) {
      draft.characterScale =
          GodotSpecGuard.sanitizeLine(characterScale, dimension: dim);
      changed.add('s02');
    }
    if (inputContract != null) {
      draft.inputContract =
          GodotSpecGuard.sanitizeLine(inputContract, dimension: dim);
      changed.add('s02');
    }
    if (assetPolicy != null) {
      draft.assetPolicy =
          GodotSpecGuard.sanitizeLine(assetPolicy, dimension: dim);
      changed.add('s02');
    }
    if (releaseDoneWhen != null) {
      draft.releaseDoneWhen =
          GodotSpecGuard.sanitizeLine(releaseDoneWhen, dimension: dim);
      changed.add('s05');
    }
    if (coreLoop != null) {
      draft.coreLoop = [
        for (final b in coreLoop)
          if (GodotSpecGuard.sanitizeLine(b, dimension: dim).isNotEmpty)
            GodotSpecGuard.sanitizeLine(b, dimension: dim),
      ];
      changed.add('s01');
    }
    if (pillars != null) {
      draft.pillars = [
        for (final p in pillars)
          if (GodotSpecGuard.sanitizeLine(p, dimension: dim).isNotEmpty)
            GodotSpecGuard.sanitizeLine(p, dimension: dim),
      ];
      changed.add('s03');
    }
    if (outOfScope != null) {
      draft.outOfScope = [
        for (final cut in outOfScope)
          if (GodotSpecGuard.sanitizeExclusion(cut, dimension: dim).isNotEmpty)
            GodotSpecGuard.sanitizeExclusion(cut, dimension: dim),
      ];
      changed.add('s04');
    }
    if (changed.isNotEmpty) {
      draft.lastCoDesignNote = 'Edited Stage 1 spec inline.';
      _lastStage1ChangedSections = changed;
    }
    _ensureActiveProjectDocument(draft);
    notifyListeners();
  }

  void addStage1OutOfScopeCut(String rawCut) {
    final draft = _conceptDraft;
    if (draft == null) return;
    final item = GodotSpecGuard.sanitizeExclusion(
      rawCut,
      dimension: draft.dimension,
    );
    if (item.isEmpty || draft.outOfScope.contains(item)) return;
    _pushStage1UndoSnapshot();
    draft.outOfScope = [...draft.outOfScope, item];
    draft.lastCoDesignNote = 'Added §04 cut: $item';
    _lastStage1ChangedSections = const <String>{'s04'};
    _ensureActiveProjectDocument(draft);
    notifyListeners();
  }

  void removeStage1OutOfScopeCut(int index) {
    final draft = _conceptDraft;
    if (draft == null || index < 0 || index >= draft.outOfScope.length) {
      return;
    }
    _pushStage1UndoSnapshot();
    final updated = List<String>.from(draft.outOfScope);
    final removed = updated.removeAt(index);
    draft.outOfScope = updated;
    draft.lastCoDesignNote = 'Removed §04 cut: $removed';
    _lastStage1ChangedSections = const <String>{'s04'};
    _ensureActiveProjectDocument(draft);
    notifyListeners();
  }

  void renameStage1FeatureSlice(
    int epicIndex,
    String featureId,
    String newTitle,
  ) {
    final draft = _conceptDraft;
    if (draft == null ||
        epicIndex < 0 ||
        epicIndex >= draft.initialEpics.length) {
      return;
    }
    final clean = GodotSpecGuard.sanitizeLine(
      newTitle,
      dimension: draft.dimension,
    );
    if (clean.isEmpty) return;
    final ep = draft.initialEpics[epicIndex];
    final featIdx = ep.features.indexWhere((f) => f.id == featureId);
    if (featIdx < 0 || ep.features[featIdx].title == clean) return;
    _pushStage1UndoSnapshot();
    ep.features[featIdx].title = clean;
    draft.lastCoDesignNote = 'Renamed ${ep.features[featIdx].code} to $clean.';
    _lastStage1ChangedSections = const <String>{'s05'};
    _ensureActiveProjectDocument(draft);
    notifyListeners();
  }

  void removeStage1FeatureSlice(int epicIndex, String featureId) {
    final draft = _conceptDraft;
    if (draft == null ||
        epicIndex < 0 ||
        epicIndex >= draft.initialEpics.length) {
      return;
    }
    final ep = draft.initialEpics[epicIndex];
    if (ep.features.length <= 1) return;
    final featIdx = ep.features.indexWhere((f) => f.id == featureId);
    if (featIdx < 0) return;
    _pushStage1UndoSnapshot();
    final removed = ep.features.removeAt(featIdx);
    _renumberInitialEpics(draft);
    draft.lastCoDesignNote =
        'Removed ${removed.title} from ${ep.code} in Stage 1 §05.';
    _lastStage1ChangedSections = const <String>{'s05'};
    _ensureActiveProjectDocument(draft);
    notifyListeners();
  }

  /// Approves `PROJECT_SPEC.md` and materializes or non-destructively reconciles `v0.1 · Prototype` Epics,
  /// transitioning straight to Stage 2 (`2. Epic Specs`).
  String? approveRootSpecAndLaunchWorkbench() {
    var draft = _conceptDraft;
    if (draft == null) return null;
    draft = GodotSpecGuard.sanitizeConceptBlueprint(draft);
    draft.approved = true;
    _conceptDraft = draft;

    final pid = _activeProjectId ?? 'proj_${DateTime.now().millisecondsSinceEpoch}';
    _activeProjectId = pid;
    _ensureActiveProjectDocument(draft);
    final proj = documents[pid]!;

    // Reuse existing v0.1 release if present cleanly, or create fresh v0.1 Prototype
    TierDocument? v01Rel;
    for (final rid in proj.childrenIds) {
      final candidate = documents[rid];
      if (candidate != null &&
          candidate.tier == TierType.release &&
          releaseVersionTagFor(candidate) == 'v0.1') {
        v01Rel = candidate;
        break;
      }
    }

    final relId = v01Rel?.id ?? '${pid}_rel_v01';
    final epicIds = <String>[];
    final existingDocs = epicDocsForRelease(relId);

    final reservedCodesLower = <String>{
      for (final rel in projectReleases)
        if (rel.id != relId)
          for (final epDoc in epicDocsForRelease(rel.id))
            for (final f in EpicSpec.fromDocument(epDoc).features)
              if (f.code.trim().isNotEmpty) f.code.trim().toLowerCase(),
    };

    if (v01Rel == null || existingDocs.isEmpty) {
      final createdSpecs = <EpicSpec>[];
      for (int i = 0; i < draft.initialEpics.length; i++) {
        final rawEpic = draft.initialEpics[i];
        final epId = '${relId}_epic_${i + 1}';
        final cleanEpic = rawEpic.deepCopy(
          idOverride: epId,
          releaseVersionOverride: 'v0.1',
          lifecycleOverride:
              i == 0 ? EpicLifecycle.active : EpicLifecycle.queued,
        );
        cleanEpic.code = 'E${(i + 1).toString().padLeft(2, '0')}';
        cleanEpic.lineageKey = rawEpic.lineageKey.trim().isEmpty
            ? EpicSpec.formatLineageKey(i + 1)
            : rawEpic.lineageKey.trim();
        createdSpecs.add(cleanEpic);
      }
      _assignUniqueFeatureIdsAndCodes(
        createdSpecs,
        reservedCodesLower: reservedCodesLower,
      );
      for (final cleanEpic in createdSpecs) {
        final epDoc = cleanEpic.toTierDocument(
          docId: cleanEpic.id,
          parentReleaseId: relId,
        );
        documents[cleanEpic.id] = epDoc;
        _persistDocument(epDoc);
        epicIds.add(cleanEpic.id);
      }
    } else {
      final existingSpecs = [
        for (int i = 0; i < existingDocs.length; i++)
          EpicSpec.fromDocument(existingDocs[i], indexHint: i),
      ];
      final matched = List<bool>.filled(existingDocs.length, false);

      int? findMatchIdx(EpicSpec incoming) {
        final inKey = incoming.lineageKey.trim().toLowerCase();
        if (inKey.isNotEmpty) {
          for (int j = 0; j < existingSpecs.length; j++) {
            if (!matched[j] &&
                existingSpecs[j].lineageKey.trim().toLowerCase() == inKey) {
              return j;
            }
          }
        }
        for (int j = 0; j < existingDocs.length; j++) {
          if (!matched[j] && existingDocs[j].id == incoming.id) {
            return j;
          }
        }
        final inTitle = incoming.title.trim().toLowerCase();
        if (inTitle.isNotEmpty) {
          for (int j = 0; j < existingSpecs.length; j++) {
            if (!matched[j] &&
                existingSpecs[j].title.trim().toLowerCase() == inTitle) {
              return j;
            }
          }
        }
        return null;
      }

      final reconciledSpecs = <EpicSpec>[];
      final reconciledBaseDocs = <TierDocument?>[];

      for (int i = 0; i < draft.initialEpics.length; i++) {
        final incoming = draft.initialEpics[i];
        final matchIdx = findMatchIdx(incoming);
        if (matchIdx != null) {
          matched[matchIdx] = true;
          final existingDoc = existingDocs[matchIdx];
          final existingSpec = existingSpecs[matchIdx];
          if (existingSpec.isPassed) {
            reconciledSpecs.add(existingSpec.deepCopy(idOverride: existingDoc.id));
            reconciledBaseDocs.add(existingDoc);
          } else {
            final merged = incoming.deepCopy(
              idOverride: existingDoc.id,
              releaseVersionOverride: 'v0.1',
              lifecycleOverride: existingSpec.lifecycle,
            );
            merged.fixes = [for (final f in existingSpec.fixes) f.copyWith()];
            merged.baselineSummary = List<String>.from(existingSpec.baselineSummary);
            merged.upgradeDeltas = List<String>.from(existingSpec.upgradeDeltas);
            for (final check in merged.checks) {
              final wasPassed = existingSpec.checks.any(
                (old) =>
                    old.passed &&
                    (old.id == check.id ||
                        old.text.trim().toLowerCase() ==
                            check.text.trim().toLowerCase()),
              );
              if (wasPassed) check.passed = true;
            }
            merged.features = _reconcileFeatureSlices(
              incoming: merged.features,
              existing: existingSpec.features,
            );
            reconciledSpecs.add(merged);
            reconciledBaseDocs.add(existingDoc);
          }
        } else {
          final newEpId =
              '${relId}_epic_${DateTime.now().microsecondsSinceEpoch}_$i';
          final created = incoming.deepCopy(
            idOverride: newEpId,
            releaseVersionOverride: 'v0.1',
          );
          if (created.lineageKey.trim().isEmpty) {
            created.lineageKey = 'epic_${reconciledSpecs.length + 1}';
          }
          reconciledSpecs.add(created);
          reconciledBaseDocs.add(null);
        }
      }

      final user = _authService.currentUser;
      for (int j = 0; j < existingDocs.length; j++) {
        if (matched[j]) continue;
        final existingDoc = existingDocs[j];
        final existingSpec = existingSpecs[j];
        if (existingSpec.isPassed ||
            existingSpec.openFixes.isNotEmpty ||
            existingSpec.totalOpenFeatureFixes() > 0 ||
            existingSpec.passedChecksCount > 0 ||
            existingSpec.features.any(
              (f) => f.isPassed || f.checks.any((c) => c.passed),
            )) {
          reconciledSpecs.add(existingSpec.deepCopy(idOverride: existingDoc.id));
          reconciledBaseDocs.add(existingDoc);
        } else {
          documents.remove(existingDoc.id);
          LocalVaultService.deleteDocument(existingDoc.id);
          if (user != null) {
            _firestoreService.deleteDocument(
              uid: user.uid,
              docId: existingDoc.id,
            );
          }
        }
      }

      bool assignedActive = false;
      final usedLineageKeys = <String>{};
      int nextLineageOrd = 1;
      for (int i = 0; i < reconciledSpecs.length; i++) {
        final spec = reconciledSpecs[i];
        spec.code = 'E${(i + 1).toString().padLeft(2, '0')}';
        var lk = spec.lineageKey.trim().toLowerCase();
        if (lk.isEmpty || usedLineageKeys.contains(lk)) {
          while (usedLineageKeys.contains(EpicSpec.formatLineageKey(nextLineageOrd))) {
            nextLineageOrd++;
          }
          lk = EpicSpec.formatLineageKey(nextLineageOrd);
        }
        spec.lineageKey = lk;
        usedLineageKeys.add(lk);
        if (!spec.isPassed &&
            spec.lifecycle != EpicLifecycle.upgrading &&
            spec.lifecycle != EpicLifecycle.newEpic) {
          if (!assignedActive) {
            spec.lifecycle = EpicLifecycle.active;
            assignedActive = true;
          } else {
            spec.lifecycle = EpicLifecycle.queued;
          }
        }
      }

      _assignUniqueFeatureIdsAndCodes(
        reconciledSpecs,
        reservedCodesLower: reservedCodesLower,
      );
      for (int i = 0; i < reconciledSpecs.length; i++) {
        final spec = reconciledSpecs[i];
        final baseDoc = reconciledBaseDocs[i];
        final updatedDoc = baseDoc != null
            ? spec.applyToDocument(baseDoc)
            : spec.toTierDocument(docId: spec.id, parentReleaseId: relId);
        documents[updatedDoc.id] = updatedDoc;
        _persistDocument(updatedDoc);
        epicIds.add(updatedDoc.id);
      }

      draft.initialEpics = [for (final s in reconciledSpecs) s.deepCopy()];
      _conceptDraft = draft;
    }

    final relDoc = TierDocument(
      id: relId,
      title: v01Rel?.title ?? 'v0.1 · Prototype',
      tier: TierType.release,
      parentId: pid,
      childrenIds: epicIds,
      estimatedDuration: '${epicIds.length} Epics',
      sections: <String, String>{
        if (v01Rel != null) ...v01Rel.sections,
        'release_version': 'v0.1',
        'goal': draft.pitch,
        'doneWhen': draft.releaseDoneWhen,
      },
    );
    documents[relId] = relDoc;
    _persistDocument(relDoc);

    if (!proj.childrenIds.contains(relId)) {
      proj.childrenIds = [relId, ...proj.childrenIds];
    }
    final prevActiveRel =
        _activeReleaseId != null ? documents[_activeReleaseId!] : null;
    final keepExistingHigherRelease = prevActiveRel != null &&
        prevActiveRel.tier == TierType.release &&
        prevActiveRel.parentId == pid &&
        prevActiveRel.id != relId;
    if (keepExistingHigherRelease) {
      _activeReleaseId = prevActiveRel.id;
      final activeDocs = epicDocsForRelease(prevActiveRel.id);
      final keepsSelected = _selectedEpicId != null &&
          activeDocs.any((d) => d.id == _selectedEpicId);
      if (!keepsSelected) {
        final fallback = activeDocs.firstWhere(
          (d) => !EpicSpec.fromDocument(d).isPassed,
          orElse: () => activeDocs.isNotEmpty
              ? activeDocs.first
              : TierDocument(
                  id: '',
                  title: '',
                  tier: TierType.epic,
                ),
        );
        _selectedEpicId = fallback.id.isNotEmpty ? fallback.id : null;
        _selectedFeatureId = _defaultFeatureIdForEpicDoc(_selectedEpicId);
      } else if (_selectedFeatureId != null && _selectedEpicId != null) {
        final epDoc = documents[_selectedEpicId!];
        final epSpec = epDoc != null ? EpicSpec.fromDocument(epDoc) : null;
        final hasSelectedFeat = epSpec != null &&
            visibleFeaturesForEpic(epSpec).any((f) => f.id == _selectedFeatureId);
        if (!hasSelectedFeat) {
          _selectedFeatureId = _defaultFeatureIdForEpicDoc(_selectedEpicId);
        }
      }
    } else {
      _activeReleaseId = relId;
      final firstUnpassedId = epicIds.firstWhere(
        (id) {
          final d = documents[id];
          return d != null && !EpicSpec.fromDocument(d).isPassed;
        },
        orElse: () => epicIds.isNotEmpty ? epicIds.first : '',
      );
      _selectedEpicId = firstUnpassedId.isNotEmpty ? firstUnpassedId : null;
      _selectedFeatureId = _defaultFeatureIdForEpicDoc(
        _selectedEpicId,
        releaseVersion: 'v0.1',
      );
    }
    if (_selectedEpicId != null) {
      _expandedEpicIds.add(_selectedEpicId!);
    }
    _currentStage = WorkbenchStage.releaseWorkbench;
    _syncActiveProjectMetadata();
    notifyListeners();
    return relId;
  }

  void _assignUniqueFeatureIdsAndCodes(
    List<EpicSpec> specs, {
    Set<String> reservedCodesLower = const {},
  }) {
    final usedCodesLower = Set<String>.from(reservedCodesLower);
    final usedIds = <String>{};
    int maxNum = 0;
    final codeRx = RegExp(r'^F(\d+)$', caseSensitive: false);
    for (final cLower in usedCodesLower) {
      final m = codeRx.firstMatch(cLower);
      final n = int.tryParse(m?.group(1) ?? '') ?? 0;
      if (n > maxNum) maxNum = n;
    }
    for (final spec in specs) {
      for (final f in spec.features) {
        final m = codeRx.firstMatch(f.code.trim());
        final n = int.tryParse(m?.group(1) ?? '') ?? 0;
        if (n > maxNum) maxNum = n;
      }
    }
    String nextUnusedCode() {
      do {
        maxNum++;
      } while (usedCodesLower
          .contains(FeatureSpec.formatCode(maxNum).toLowerCase()));
      final next = FeatureSpec.formatCode(maxNum);
      usedCodesLower.add(next.toLowerCase());
      return next;
    }

    for (final spec in specs) {
      for (int i = 0; i < spec.features.length; i++) {
        var feat = spec.features[i];
        final cClean = feat.code.trim();
        if (cClean.isEmpty || !usedCodesLower.add(cClean.toLowerCase())) {
          feat.code = nextUnusedCode();
        }
        final fid = feat.id.trim();
        if (fid.isEmpty ||
            FeatureSpec.isPositionalFallbackFeatureId(fid) ||
            !usedIds.add(fid)) {
          var candId = '${spec.id}_${feat.code.toLowerCase()}';
          var sfx = 2;
          while (usedIds.contains(candId)) {
            candId = '${spec.id}_${feat.code.toLowerCase()}_$sfx';
            sfx++;
          }
          feat = feat.deepCopy(idOverride: candId);
          spec.features[i] = feat;
          usedIds.add(feat.id);
        }
      }
    }
  }

  List<FeatureSpec> _reconcileFeatureSlices({
    required List<FeatureSpec> incoming,
    required List<FeatureSpec> existing,
  }) {
    if (existing.isEmpty) return [for (final f in incoming) f.deepCopy()];
    final matched = List<bool>.filled(existing.length, false);
    int? findMatch(FeatureSpec inc) {
      if (inc.id.isNotEmpty &&
          !FeatureSpec.isPositionalFallbackFeatureId(inc.id)) {
        for (int i = 0; i < existing.length; i++) {
          if (!matched[i] && existing[i].id == inc.id) return i;
        }
      }
      final incTitle = inc.title.trim().toLowerCase();
      if (incTitle.isNotEmpty) {
        for (int i = 0; i < existing.length; i++) {
          if (!matched[i] &&
              existing[i].title.trim().toLowerCase() == incTitle) {
            return i;
          }
        }
      }
      final incCode = inc.code.trim().toLowerCase();
      if (incCode.isNotEmpty) {
        for (int i = 0; i < existing.length; i++) {
          if (!matched[i] &&
              existing[i].code.trim().toLowerCase() == incCode) {
            return i;
          }
        }
      }
      return null;
    }

    final result = <FeatureSpec>[];
    for (final inc in incoming) {
      final mIdx = findMatch(inc);
      if (mIdx == null) {
        result.add(inc.deepCopy());
        continue;
      }
      matched[mIdx] = true;
      final oldFeat = existing[mIdx];
      if (oldFeat.isPassed) {
        result.add(oldFeat.deepCopy());
        continue;
      }
      final mergedFeat = inc.deepCopy(
        idOverride: oldFeat.id,
        codeOverride: oldFeat.code,
        statusOverride: oldFeat.status,
      );
      mergedFeat.fixes = [for (final fx in oldFeat.fixes) fx.copyWith()];
      for (final chk in [...mergedFeat.checks, ...mergedFeat.releaseDeltaChecks]) {
        final wasPassed = [...oldFeat.checks, ...oldFeat.releaseDeltaChecks].any(
          (old) =>
              old.passed &&
              (old.id == chk.id ||
                  old.text.trim().toLowerCase() ==
                      chk.text.trim().toLowerCase()),
        );
        if (wasPassed) chk.passed = true;
      }
      result.add(mergedFeat);
    }

    // Preserve user-added custom slices created in Stage 2
    for (int i = 0; i < existing.length; i++) {
      if (!matched[i]) {
        result.add(existing[i].deepCopy());
      }
    }
    return result;
  }
}
