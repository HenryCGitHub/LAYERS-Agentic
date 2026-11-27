part of 'workbench_provider.dart';

/// Stage 1 actions: Idea Workbench (`3-Angles Picker` + steer/reroll), Preset Packs,
/// Blueprint-First | C++ & BP Hybrid toggle, Co-Designer edits, Undo stack,
/// lean inline edits, and `Approve & Launch Release Workbench`.
extension WorkbenchConceptMixin on WorkbenchProvider {
  void _pushStage1UndoSnapshot() {
    final draft = _conceptDraft;
    if (draft == null || !draft.hasSpec) return;
    _stage1UndoStack.add(draft.deepCopy());
    if (_stage1UndoStack.length > 12) {
      _stage1UndoStack.removeAt(0);
    }
  }

  void _syncMaterializedEpicsArchitectureMode(UnrealArchitectureMode mode) {
    for (final rel in projectReleases) {
      for (final epDoc in epicDocsForRelease(rel.id)) {
        final spec = EpicSpec.fromDocument(epDoc);
        final converted = ProjectConceptAgent.convertEpicArchitectureMode(
          spec,
          mode,
        );
        final updatedDoc = converted.applyToDocument(epDoc);
        documents[epDoc.id] = updatedDoc;
        _persistDocument(updatedDoc);
      }
    }
  }

  bool undoStage1Edit() {
    if (_stage1UndoStack.isEmpty || _isAgentBusy) return false;
    final prevMode = _conceptDraft?.architectureMode;
    final restored = _stage1UndoStack.removeLast();
    restored.lastCoDesignNote = 'Reverted last Stage 1 change.';
    _conceptDraft = restored;
    _lastStage1ChangedSections = const <String>{};
    _stage1InlineError = null;
    _offlineErrorMessage = null;
    _ensureActiveProjectDocument(restored);
    if (prevMode != restored.architectureMode && projectReleases.isNotEmpty) {
      _syncMaterializedEpicsArchitectureMode(restored.architectureMode);
    }
    notifyListeners();
    return true;
  }

  void dismissStage1InlineError() {
    if (_stage1InlineError == null) return;
    _stage1InlineError = null;
    notifyListeners();
  }

  void previewArchitectureModeFromSparkText(String rawText) {
    var changed = false;
    if (_pendingAngleDeck != null &&
        _pendingAngleDeck!.rawSpark != rawText.trim()) {
      _pendingAngleDeck = null;
      changed = true;
    }
    if (_stage1InlineError != null) {
      _stage1InlineError = null;
      changed = true;
    }
    if (!_userPinnedMode &&
        (_conceptDraft == null || !_conceptDraft!.hasSpec)) {
      final detected = UnrealArchitectureMode.detectFromSpark(rawText);
      if (detected != unrealArchitectureMode) {
        _conceptDraft = ProjectConceptBlueprint(
          sparkPrompt: rawText.trim(),
          gameTitle: _conceptDraft?.gameTitle ?? 'UNTITLED UNREAL PROJECT',
          architectureMode: detected,
        );
        if (activeProject != null) {
          activeProject!.sections['unreal_arch_mode'] = detected.id;
        }
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
    nextSections['unreal_arch_mode'] = bp.architectureMode.id;
    nextSections['engine'] = bp.architectureMode.shortLabel;
    nextSections.remove('dimension');
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

  void _detachFromExistingReleasesIfFreshStart() {
    final existing = activeProject;
    if (existing != null &&
        projectReleases.isNotEmpty &&
        (_conceptDraft == null || !_conceptDraft!.hasSpec)) {
      final baseMs = DateTime.now().millisecondsSinceEpoch;
      var candidate = 'proj_$baseMs';
      var suffix = 1;
      while (documents.containsKey(candidate)) {
        candidate = 'proj_${baseMs}_$suffix';
        suffix++;
      }
      _activeProjectId = candidate;
      _unpersistedNewProjectId = candidate;
      _activeReleaseId = null;
      _selectedEpicId = null;
      _selectedFeatureId = null;
      _showingReleaseSpec = false;
      _showingPlanNextRelease = false;
      _expandedEpicIds.clear();
    }
  }

  void loadPresetSpark(String presetId) {
    _detachFromExistingReleasesIfFreshStart();
    final preset = UnrealSparkPresets.byId(presetId);
    _userPinnedMode = false;
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
    await exploreSparkAngles(sparkPrompt);
    return null;
  }

  /// Calls Hydrogen (`LOW`) to propose or steer/reroll 3 playable game angles for [rawSpark].
  Future<SparkAngleDeck?> exploreSparkAngles(
    String rawSpark, {
    String? steerNote,
    bool reroll = false,
  }) async {
    final cleanPrompt = rawSpark.trim();
    if (cleanPrompt.isEmpty || _isAgentBusy) return null;

    final savedDeck = _pendingAngleDeck;
    final matchingPrevious =
        savedDeck != null && savedDeck.rawSpark == cleanPrompt
            ? savedDeck
            : null;
    final cleanSteer = steerNote?.trim();
    final startProjectId = _activeProjectId;

    _isAgentBusy = true;
    _isExploringAngles = true;
    _lastStage1IntakeOp = 'explore';
    _lastAngleSteerNote =
        cleanSteer != null && cleanSteer.isNotEmpty ? cleanSteer : null;
    _lastAngleReroll = reroll;
    _stage1InlineError = null;
    _offlineErrorMessage = null;
    _agentProgressStep = reroll
        ? 'Hydrogen rerolling 3 angles...'
        : (_lastAngleSteerNote != null
            ? 'Hydrogen steering 3 angles...'
            : 'Hydrogen proposing 3 angles...');
    notifyListeners();

    try {
      final outcome = await SparkAngleAgent.proposeAngles(
        rawSpark: cleanPrompt,
        apiKey: _apiKey,
        mode: unrealArchitectureMode,
        steerNote: _lastAngleSteerNote,
        reroll: reroll,
        previousDeck: matchingPrevious,
        preferredModel: _conversationModel,
        thinkingLevel: GeminiAgentClient.defaultFastThinkingLevel,
      );
      if (_isDisposed || _activeProjectId != startProjectId) return null;
      if (outcome.deck == null) {
        final msg = outcome.errorMessage ??
            'Cloud Gemini could not propose game angles. Retry when ready.';
        _stage1InlineError = msg;
        _offlineErrorMessage = msg;
        _pendingAngleDeck = savedDeck;
        return null;
      }
      _pendingAngleDeck = outcome.deck;
      _stage1InlineError = null;
      _offlineErrorMessage = null;
      return outcome.deck;
    } catch (e) {
      if (_isDisposed || _activeProjectId != startProjectId) return null;
      final msg = 'Angle generation error: $e';
      _stage1InlineError = msg;
      _offlineErrorMessage = msg;
      _pendingAngleDeck = savedDeck;
      return null;
    } finally {
      if (!_isDisposed) {
        _isAgentBusy = false;
        _isExploringAngles = false;
        _agentProgressStep = null;
        flushDeferredRemoteSnapshotIfIdle();
        notifyListeners();
      }
    }
  }

  void selectSparkAngle(String angleId) {
    final deck = _pendingAngleDeck;
    if (deck == null || deck.selectedAngleId == angleId) return;
    if (!deck.angles.any((a) => a.id == angleId)) return;
    _pendingAngleDeck = deck.copyWith(selectedAngleId: angleId);
    notifyListeners();
  }

  void dismissSparkAngles() {
    if (_pendingAngleDeck == null) return;
    _pendingAngleDeck = null;
    _stage1InlineError = null;
    notifyListeners();
  }

  /// Locks the currently chosen angle and hands it to Argon (`MEDIUM`) to draft `PROJECT_SPEC.md`.
  Future<ProjectConceptBlueprint?> draftSpecFromSelectedAngle() async {
    final deck = _pendingAngleDeck;
    if (deck == null || _isAgentBusy) return null;
    _lastStage1IntakeOp = 'draft_angle';
    return generateSpecFromSpark(
      deck.buildSelectedHandoffPrompt(),
      explicitMode: deck.architectureMode,
      viewChoiceId: deck.selectedAngle.viewChoiceId,
    );
  }

  /// Bypasses the 3-Angles Picker and drafts `PROJECT_SPEC.md` directly from raw spark text.
  Future<ProjectConceptBlueprint?> draftSpecDirectlyFromSpark(
    String sparkPrompt,
  ) async {
    final clean = sparkPrompt.trim();
    if (clean.isEmpty || _isAgentBusy) return null;
    _pendingAngleDeck = null;
    _lastStage1IntakeOp = 'draft_direct';
    notifyListeners();
    return generateSpecFromSpark(
      clean,
      explicitMode: _userPinnedMode ? unrealArchitectureMode : null,
    );
  }

  /// Retries the most recent failed Stage 1 intake operation (`explore`, `draft_angle`, or `draft_direct`).
  Future<void> retryLastStage1Intake(String currentSparkText) async {
    if (_isAgentBusy) return;
    if (_lastStage1IntakeOp == 'draft_angle' && _pendingAngleDeck != null) {
      await draftSpecFromSelectedAngle();
      return;
    }
    if (_lastStage1IntakeOp == 'draft_direct') {
      await draftSpecDirectlyFromSpark(currentSparkText);
      return;
    }
    await exploreSparkAngles(
      currentSparkText,
      steerNote: _lastAngleSteerNote,
      reroll: _lastAngleReroll,
    );
  }

  Future<ProjectConceptBlueprint?> generateSpecFromSpark(
    String sparkPrompt, {
    UnrealArchitectureMode? explicitMode,
    String? archetypeId,
    String? viewChoiceId,
    String? prototypeHookId,
  }) async {
    final cleanPrompt = sparkPrompt.trim();
    if (cleanPrompt.isEmpty) return null;
    _detachFromExistingReleasesIfFreshStart();

    _isAgentBusy = true;
    _agentProgressStep = 'Drafting Unreal Engine 5 Root Spec (PROJECT_SPEC.md)...';
    _offlineErrorMessage = null;
    _stage1InlineError = null;
    notifyListeners();

    try {
      final archThinking =
          (_planningModel == GeminiAgentClient.pinnedArchitectModel ||
                  _planningModel == 'gemini-4-neon')
              ? GeminiAgentClient.defaultArchitectThinkingLevel
              : _thinkingLevel;
      final outcome = await ProjectConceptAgent.draftSpecWithStatus(
        sparkPrompt: cleanPrompt,
        apiKey: _apiKey,
        architectureModeOverride:
            explicitMode ?? (_userPinnedMode ? unrealArchitectureMode : null),
        archetypeId: archetypeId,
        viewChoiceId: viewChoiceId,
        prototypeHookId: prototypeHookId,
        preferredModel: _planningModel,
        thinkingLevel: archThinking,
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
      _pendingAngleDeck = null;
      _stage1InlineError = null;
      _offlineErrorMessage = null;
      _conceptDraft = outcome.blueprint;
      _userPinnedMode = false;
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
    final prevMode = draft.architectureMode;

    _isAgentBusy = true;
    _agentProgressStep = 'Co-Designer updating ROOT_UNREAL_CONTEXT...';
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
      if (outcome.blueprint!.architectureMode != prevMode &&
          projectReleases.isNotEmpty) {
        _syncMaterializedEpicsArchitectureMode(
          outcome.blueprint!.architectureMode,
        );
      }
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

  void setArchitectureMode(UnrealArchitectureMode mode) {
    _userPinnedMode = true;
    final draft = _conceptDraft;
    if (draft == null) {
      _conceptDraft = ProjectConceptBlueprint(architectureMode: mode);
      if (activeProject != null) {
        activeProject!.sections['unreal_arch_mode'] = mode.id;
      }
    } else if (draft.hasSpec) {
      if (draft.architectureMode == mode) return;
      _pushStage1UndoSnapshot();
      final converted = ProjectConceptAgent.convertBlueprintArchitectureMode(
        draft,
        mode,
      );
      converted.lastCoDesignNote =
          'Switched project mode to ${mode.pillLabel}.';
      _conceptDraft = converted;
      _lastStage1ChangedSections = const <String>{'s02', 's05'};
    } else {
      _conceptDraft = ProjectConceptBlueprint(
        sparkPrompt: draft.sparkPrompt,
        gameTitle: draft.gameTitle,
        architectureMode: mode,
      );
      if (activeProject != null) {
        activeProject!.sections['unreal_arch_mode'] = mode.id;
      }
    }
    if (_pendingAngleDeck != null) {
      _pendingAngleDeck = _pendingAngleDeck!.copyWith(architectureMode: mode);
    }
    if (activeProject != null && _conceptDraft != null) {
      _ensureActiveProjectDocument(_conceptDraft!);
    }
    if (projectReleases.isNotEmpty) {
      _syncMaterializedEpicsArchitectureMode(mode);
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
    final mode = unrealArchitectureMode;
    _clearStage1TransientState();
    if (projectReleases.isNotEmpty) {
      createNewProject();
      _userPinnedMode = false;
      _conceptDraft = ProjectConceptBlueprint(architectureMode: mode);
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
    _userPinnedMode = false;
    _conceptDraft = ProjectConceptBlueprint(architectureMode: mode);
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
    List<TradeOffRule>? tradeOffs,
    List<String>? outOfScope,
  }) {
    final draft = _conceptDraft;
    if (draft == null) return;
    _pushStage1UndoSnapshot();
    final mode = draft.architectureMode;
    final changed = <String>{};
    if (gameTitle != null && gameTitle.trim().isNotEmpty) {
      draft.gameTitle = gameTitle.trim().toUpperCase();
      changed.add('s01');
    }
    if (pitch != null && pitch.trim().isNotEmpty) {
      draft.pitch = UnrealSpecGuard.sanitizeLine(pitch, mode: mode);
      changed.add('s01');
    }
    if (cameraContract != null) {
      draft.cameraContract =
          UnrealSpecGuard.sanitizeLine(cameraContract, mode: mode);
      changed.add('s02');
    }
    if (characterScale != null) {
      draft.characterScale =
          UnrealSpecGuard.sanitizeLine(characterScale, mode: mode);
      changed.add('s02');
    }
    if (inputContract != null) {
      draft.inputContract =
          UnrealSpecGuard.sanitizeLine(inputContract, mode: mode);
      changed.add('s02');
    }
    if (assetPolicy != null) {
      draft.assetPolicy =
          UnrealSpecGuard.sanitizeLine(assetPolicy, mode: mode);
      changed.add('s02');
    }
    if (releaseDoneWhen != null) {
      draft.releaseDoneWhen =
          UnrealSpecGuard.sanitizeLine(releaseDoneWhen, mode: mode);
      changed.add('s05');
    }
    if (coreLoop != null) {
      draft.coreLoop = [
        for (final b in coreLoop)
          if (UnrealSpecGuard.sanitizeLine(b, mode: mode).isNotEmpty)
            UnrealSpecGuard.sanitizeLine(b, mode: mode),
      ];
      changed.add('s01');
    }
    if (pillars != null) {
      draft.pillars = [
        for (final p in pillars)
          if (UnrealSpecGuard.sanitizeLine(p, mode: mode).isNotEmpty)
            UnrealSpecGuard.sanitizeLine(p, mode: mode),
      ];
      changed.add('s03');
    }
    if (tradeOffs != null) {
      draft.tradeOffs = [
        for (final t in tradeOffs)
          if (UnrealSpecGuard.sanitizeLine(t.prefer, mode: mode).isNotEmpty &&
              UnrealSpecGuard.sanitizeLine(t.avoid, mode: mode).isNotEmpty)
            TradeOffRule(
              prefer: UnrealSpecGuard.sanitizeLine(t.prefer, mode: mode),
              avoid: UnrealSpecGuard.sanitizeLine(t.avoid, mode: mode),
            ),
      ];
      changed.add('s03');
    }
    if (outOfScope != null) {
      draft.outOfScope = [
        for (final cut in outOfScope)
          if (UnrealSpecGuard.sanitizeExclusion(cut, mode: mode).isNotEmpty)
            UnrealSpecGuard.sanitizeExclusion(cut, mode: mode),
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
    final item = UnrealSpecGuard.sanitizeExclusion(
      rawCut,
      mode: draft.architectureMode,
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
    final clean = UnrealSpecGuard.sanitizeLine(
      newTitle,
      mode: draft.architectureMode,
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
  /// transitioning straight to Stage 2 (`2. Release Workbench`).
  String? approveRootSpecAndLaunchWorkbench({bool openReleaseSpec = false}) {
    var draft = _conceptDraft;
    if (draft == null) return null;
    _previousProjectIdBeforeNewGame = null;
    _showingPlanNextRelease = false;
    _showingReleaseSpec = openReleaseSpec;
    draft = UnrealSpecGuard.sanitizeConceptBlueprint(
      raw: draft,
      modeOverride: draft.architectureMode,
    );
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

    final v01IdCandidate = v01Rel?.id ?? '${pid}_rel_v01';
    final existingDocs = epicDocsForRelease(v01IdCandidate);
    final reservedCodesLower = <String>{
      for (final rel in projectReleases)
        if (rel.id != v01IdCandidate)
          for (final epDoc in epicDocsForRelease(rel.id))
            for (final f in EpicSpec.fromDocument(epDoc).features)
              if (f.code.trim().isNotEmpty) f.code.trim().toLowerCase(),
    };

    final v01Result = V01ReleaseSeeder.buildOrReconcileV01Release(
      projectId: pid,
      draft: draft,
      existingV01Release: v01Rel,
      existingDocs: existingDocs,
      reservedCodesLower: reservedCodesLower,
    );
    final relId = v01Result.releaseId;
    final epicIds = <String>[
      for (final epDoc in v01Result.epicDocsToSave) epDoc.id,
    ];
    final user = _authService.currentUser;
    for (final removedId in v01Result.removedDocIds) {
      documents.remove(removedId);
      LocalVaultService.deleteDocument(removedId);
      if (user != null) {
        _firestoreService.deleteDocument(uid: user.uid, docId: removedId);
      }
    }
    for (final epDoc in v01Result.epicDocsToSave) {
      documents[epDoc.id] = epDoc;
      _persistDocument(epDoc);
    }
    if (v01Result.reconciledInitialEpics != null) {
      draft.initialEpics = v01Result.reconciledInitialEpics!;
      _conceptDraft = draft;
    }

    final relDoc = v01Result.releaseDoc;
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
}
