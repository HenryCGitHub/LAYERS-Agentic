part of 'workbench_provider.dart';

/// Stage 2 Open-Canvas Release Workbench, Progressive AI Release Co-Pilot,
/// Live Playtest Triage, and Engine Step Synthesis for [WorkbenchProvider].
extension WorkbenchReleaseMixin on WorkbenchProvider {
  void _selectFirstIncompleteFeatureInActiveRelease() {
    final beats = activeReleaseBeats;
    if (beats.isEmpty) return;
    TierDocument? firstActiveIncompleteBeat;
    TierDocument? firstActiveIncompleteFeat;
    TierDocument? firstActiveBeat;
    TierDocument? firstActiveFeat;
    TierDocument? firstIncompleteBeat;
    TierDocument? firstIncompleteFeat;

    for (final b in beats) {
      for (final f in featuresForBeat(b.id)) {
        final isActive = isFeatureActiveInRelease(f);
        final isIncomplete = getDocumentProgress(f.id) < 100;
        if (isActive && isIncomplete) {
          firstActiveIncompleteBeat = b;
          firstActiveIncompleteFeat = f;
          break;
        }
        if (isActive && firstActiveFeat == null) {
          firstActiveBeat = b;
          firstActiveFeat = f;
        }
        if (isIncomplete && firstIncompleteFeat == null) {
          firstIncompleteBeat = b;
          firstIncompleteFeat = f;
        }
      }
      if (firstActiveIncompleteFeat != null) break;
    }

    final chosenBeat = firstActiveIncompleteBeat ??
        firstActiveBeat ??
        firstIncompleteBeat ??
        beats.first;
    final chosenFeat = firstActiveIncompleteFeat ??
        firstActiveFeat ??
        firstIncompleteFeat;

    _selectedBeatId = chosenBeat.id;
    final feats = featuresForBeat(_selectedBeatId!);
    _selectedFeatureId =
        (chosenFeat ?? (feats.isNotEmpty ? feats.first : null))?.id;
  }

  /// Option 4: Builds a Post-Release Retrospective & Auto-Carryover Summary for the active Release.
  ReleaseRetrospectiveSummary buildActiveReleaseRetrospective() {
    final rel = activeRelease;
    final activeVer = activeReleaseVersionTag;
    final beats = activeReleaseBeats;
    final allFeats = <TierDocument>[
      for (final b in beats) ...featuresForBeat(b.id),
    ];
    int verifiedCps = 0;
    int totalCps = 0;
    int fixTasks = 0;
    int playtestGuards = 0;
    final carryover = <String>[];
    final hardened = <String>[];

    for (final f in allFeats) {
      final isStable =
          f.sections['lifecycle'] == FeatureLifecycleStatus.stable.name;
      final states = FeatureStateNode.getStatesForDocument(f);
      final activeStates =
          states.where((s) => s.releaseVersion == activeVer).toList();
      final effectiveStates =
          activeStates.isNotEmpty ? activeStates : states;
      totalCps += effectiveStates.length;
      bool featHasIncomplete = false;
      bool featWasHardened = false;
      for (final s in effectiveStates) {
        if (s.isCompleted || isStable) {
          verifiedCps++;
        } else {
          featHasIncomplete = true;
        }
        for (final t in s.checklist) {
          if (t.text.startsWith('[FIX]')) {
            fixTasks++;
            featWasHardened = true;
          }
        }
        for (final g in s.edgeCases) {
          if (g.startsWith('[PLAYTEST GUARD]') ||
              g.startsWith('[SIMULATION GUARD]')) {
            playtestGuards++;
            featWasHardened = true;
          }
        }
      }
      if (featHasIncomplete && !isStable) {
        carryover.add(f.title);
      }
      if (featWasHardened) {
        hardened.add(f.title);
      }
    }

    return ReleaseRetrospectiveSummary(
      releaseTitle: rel?.title ?? 'v0.1 Prototype',
      totalFeatures: allFeats.length,
      verifiedCheckpoints: verifiedCps,
      totalCheckpoints: totalCps,
      fixTasksTriaged: fixTasks,
      playtestGuardsAdded: playtestGuards,
      carryoverFeatureTitles: carryover,
      hardenedFeatureTitles: hardened,
    );
  }

  /// Switches the Stage 2 Workbench in-place to an already-built Release (`rel.childrenIds.isNotEmpty`),
  /// or synthesizes and builds the target Release directly into `2. Workbench` if not built yet.
  Future<void> selectActiveRelease(String releaseId) async {
    final targetRel = documents[releaseId];
    if (targetRel == null) return;
    _syncCurrentPhaseFromRelease(targetRel);
    if (targetRel.childrenIds.isNotEmpty) {
      _activeReleaseId = releaseId;
      final savedBp = releaseBlueprintFor(releaseId);
      if (savedBp != null) {
        _releaseBlueprint = savedBp;
      }
      _releaseViewFilter = 'active';
      _currentStage = WorkbenchStage.releaseWorkbench;
      _selectFirstIncompleteFeatureInActiveRelease();
      _syncActiveProjectMetadata();
      notifyListeners();
      return;
    }
    await approveConceptAndBuildRelease(releaseId: releaseId);
  }

  /// 2-Stage Flow (`1. Concept` -> `2. Workbench`): Transitions immediately to `2. Workbench`,
  /// synthesizes the Release Blueprint, and executes it into the active Workbench.
  Future<void> approveConceptAndBuildRelease({String? releaseId}) async {
    if (_conceptDraft != null) {
      _commitConceptToVault(_conceptDraft!, syncBuiltWorkbench: false);
    }
    _releaseViewFilter = 'active';
    _currentStage = WorkbenchStage.releaseWorkbench;
    notifyListeners();

    if (GeminiAgentClient.testMockResponder == null) {
      await _buildInitialReleasePriorityFirst(releaseId: releaseId);
      return;
    }

    await openReleasePlanGate(
      releaseId: releaseId,
      transitionToGateStage: false,
    );
    if (_releaseBlueprint != null) {
      await approveAndExecuteReleasePlan();
    } else if (activeReleaseBeats.isEmpty) {
      _currentStage = WorkbenchStage.projectPitch;
      notifyListeners();
    }
  }

  /// Priority-First Section-by-Section Workbench Build (`1. System Epics E01..EN` -> `2. E01 Features` ->
  /// `3. Feature 1.1 Engine Steps` -> `4. Background E02..EN Features & Remaining Steps`).
  Future<void> _buildInitialReleasePriorityFirst({String? releaseId}) async {
    final proj = activeProject;
    if (proj == null || proj.childrenIds.isEmpty) {
      _currentStage = WorkbenchStage.projectPitch;
      notifyListeners();
      return;
    }
    if (!GeminiAgentClient.hasKey(_apiKey)) {
      _setOfflineState();
      _currentStage = WorkbenchStage.projectPitch;
      notifyListeners();
      return;
    }
    final targetRelId =
        releaseId ?? _activeReleaseId ?? proj.childrenIds.first;
    _activeReleaseId = targetRelId;
    final relDoc = documents[targetRelId];
    if (relDoc == null) return;
    final verTag = releaseVersionTagFor(relDoc);
    relDoc.sections['versionTag'] = verTag;

    _stepQueueGeneration++;
    final currentGen = _stepQueueGeneration;
    _pendingFeatureStepQueue.clear();
    _aiSynthesizedFeatureSteps.clear();
    _isAgentBusy = true;
    _agentProgressStep =
        'Determining Systems & Mechanics for $verTag ($_conversationModel)...';
    notifyListeners();

    try {
      // 1. Clear any old v0.1 Beats/Features if rebuilding v0.1
      final oldBeatIds = List<String>.from(relDoc.childrenIds);
      final oldFeatureIds = <String>{
        for (final bId in oldBeatIds)
          ...(documents[bId]?.childrenIds ?? const <String>[]),
      };
      final user = _authService.currentUser;
      for (final oldFeatId in oldFeatureIds) {
        documents.remove(oldFeatId);
        LocalVaultService.deleteDocument(oldFeatId);
        if (user != null) {
          _firestoreService.deleteDocument(uid: user.uid, docId: oldFeatId);
        }
      }
      for (final oldBeatId in oldBeatIds) {
        documents.remove(oldBeatId);
        LocalVaultService.deleteDocument(oldBeatId);
        if (user != null) {
          _firestoreService.deleteDocument(uid: user.uid, docId: oldBeatId);
        }
      }
      relDoc.childrenIds.clear();
      _selectedBeatId = null;
      _selectedFeatureId = null;
      notifyListeners();

      // Phase 1: Determine System Epics (E01..EN) needed to accomplish the Core Loop
      final systemBp = await ReleasePlannerAgent.planReleaseSystemEpics(
        projectDoc: proj,
        releaseDoc: relDoc,
        apiKey: _apiKey,
        modelName: _planningModel,
        thinkingLevel: _thinkingLevel,
      );
      if (systemBp == null) {
        final fallbackBp =
            ReleasePlannerAgent.buildImmediateInitialBaselineBlueprint(
          projectDoc: proj,
          releaseDoc: relDoc,
        );
        if (fallbackBp == null) {
          _setOfflineState();
          _currentStage = WorkbenchStage.projectPitch;
          return;
        }
        _releaseBlueprint = fallbackBp;
        await approveAndExecuteReleasePlan();
        return;
      }

      if (systemBp.releaseTitle.isNotEmpty &&
          systemBp.releaseTitle != relDoc.title) {
        relDoc.title = systemBp.releaseTitle;
      }
      _releaseBlueprint = systemBp;

      // Immediately materialize all System Epics (E01..EN) into the Left Outliner Rail
      final createdEpics = ReleaseExecutorAgent.createInitialSystemEpicDocs(
        releaseDoc: relDoc,
        blueprint: systemBp,
      );
      for (final epicDoc in createdEpics) {
        documents[epicDoc.id] = epicDoc;
        _persistDocument(epicDoc);
      }
      _persistDocument(relDoc);

      // Phase 2A: Determine Features for E01 FIRST so Feature 1.1 opens immediately
      final e01Bp = systemBp.beats.first;
      final e01Doc = createdEpics.first;
      _synthesizingBeatId = e01Doc.id;
      _agentProgressStep =
          'Planning E01 · ${e01Bp.title} features ($_conversationModel)...';
      notifyListeners();

      final e01Features = await ReleasePlannerAgent.planFeaturesForSingleEpic(
        projectDoc: proj,
        releaseDoc: relDoc,
        epicBlueprint: e01Bp,
        epicIndex: 0,
        allEpics: systemBp.beats,
        alreadyPlannedFeatures: const <String>[],
        apiKey: _apiKey,
        modelName: _planningModel,
        thinkingLevel: _thinkingLevel,
      );
      e01Bp.features = e01Features;

      final createdE01Features =
          ReleaseExecutorAgent.materializeFeaturesForSingleEpic(
        releaseDoc: relDoc,
        beatDoc: e01Doc,
        blueprint: systemBp,
        beatBp: e01Bp,
        epicIndex: 0,
        existingDocuments: documents,
      );
      for (final fDoc in createdE01Features) {
        documents[fDoc.id] = fDoc;
        _persistDocument(fDoc);
        if (!_pendingFeatureStepQueue.contains(fDoc.id)) {
          _pendingFeatureStepQueue.add(fDoc.id);
        }
      }
      _persistDocument(e01Doc);
      relDoc.sections['synced_engine_label'] = _activeEngineLabel;
      relDoc.sections['release_blueprint_json'] = jsonEncode(systemBp.toJson());
      _persistDocument(relDoc);
      _selectFirstIncompleteFeatureInActiveRelease();
      _syncActiveProjectMetadata();
    } finally {
      _synthesizingBeatId = null;
      _isAgentBusy = false;
      _agentProgressStep = null;
      notifyListeners();
    }

    final activeBp = _releaseBlueprint;
    if (activeBp == null || activeReleaseBeats.isEmpty) return;

    // Phase 3 & 4 (Background Priority-First):
    // Immediately synthesize Feature 1.1's Engine Steps FIRST, then populate E02..EN Features & remaining steps
    unawaited(
      _completePriorityFirstWorkbenchBuild(
        generation: currentGen,
        projectDoc: proj,
        releaseDoc: relDoc,
        blueprint: activeBp,
      ),
    );
  }

  Future<void> _completePriorityFirstWorkbenchBuild({
    required int generation,
    required TierDocument projectDoc,
    required TierDocument releaseDoc,
    required ReleaseBlueprint blueprint,
  }) async {
    final startProjectId = _activeProjectId;
    final startReleaseId = _activeReleaseId;
    bool isCancelled() =>
        _stepQueueGeneration != generation ||
        _activeProjectId != startProjectId ||
        _activeReleaseId != startReleaseId;

    final e01BeatDoc = activeReleaseBeats.firstOrNull;
    final e01FeatDocs = e01BeatDoc != null
        ? featuresForBeat(e01BeatDoc.id)
        : const <TierDocument>[];
    final firstFeatureId = e01FeatDocs.firstOrNull?.id;
    for (final f in e01FeatDocs.skip(1)) {
      if (!_pendingFeatureStepQueue.contains(f.id)) {
        _pendingFeatureStepQueue.add(f.id);
      }
    }

    // Step 3: Immediately synthesize Feature 1.1's 3-Area Engine Steps BEFORE E02..EN
    if (firstFeatureId != null && !isCancelled()) {
      await synthesizeFeatureHowToStepsWithAi(firstFeatureId);
    }

    // Step 4A: Populate E02..EN Features top-down one Epic at a time in the Outliner
    final plannedFeatureTitles = <String>[
      for (final f in blueprint.beats.first.features) f.title,
    ];

    for (int bIdx = 1; bIdx < blueprint.beats.length; bIdx++) {
      if (isCancelled()) break;
      final epicBp = blueprint.beats[bIdx];
      final targetBeatDoc = documents[epicBp.id] ??
          documents['epic_${releaseDoc.id}_${bIdx + 1}'];
      if (targetBeatDoc == null) continue;
      _synthesizingBeatId = targetBeatDoc.id;
      notifyListeners();
      try {
        final epicFeats = await ReleasePlannerAgent.planFeaturesForSingleEpic(
          projectDoc: projectDoc,
          releaseDoc: releaseDoc,
          epicBlueprint: epicBp,
          epicIndex: bIdx,
          allEpics: blueprint.beats,
          alreadyPlannedFeatures: plannedFeatureTitles,
          apiKey: _apiKey,
          modelName: _planningModel,
          thinkingLevel: _thinkingLevel,
        );
        if (isCancelled()) break;
        epicBp.features = epicFeats;
        for (final ef in epicFeats) {
          plannedFeatureTitles.add(ef.title);
        }

        final createdEpicFeatures =
            ReleaseExecutorAgent.materializeFeaturesForSingleEpic(
          releaseDoc: releaseDoc,
          beatDoc: targetBeatDoc,
          blueprint: blueprint,
          beatBp: epicBp,
          epicIndex: bIdx,
          existingDocuments: documents,
        );
        for (final fDoc in createdEpicFeatures) {
          documents[fDoc.id] = fDoc;
          _persistDocument(fDoc);
          if (!_pendingFeatureStepQueue.contains(fDoc.id)) {
            _pendingFeatureStepQueue.add(fDoc.id);
          }
        }
        _persistDocument(targetBeatDoc);
        releaseDoc.sections['release_blueprint_json'] =
            jsonEncode(blueprint.toJson());
        _persistDocument(releaseDoc);
        _syncActiveProjectMetadata();
      } finally {
        if (_synthesizingBeatId == targetBeatDoc.id) {
          _synthesizingBeatId = null;
        }
        notifyListeners();
      }
    }

    // Step 4B: Synthesize 3-Area Engine Steps for remaining Features (Feature 1.2, E02 Features, ...) one at a time
    if (_pendingFeatureStepQueue.isNotEmpty && !isCancelled()) {
      await _prefetchRemainingFeatureStepsInBackground(
        null,
        generation,
      );
    }
  }

  static final RegExp _minorVerRegex = RegExp(
    r'v0\.(\d+)',
    caseSensitive: false,
  );
  static final RegExp _noPrefixRegex = RegExp(
    r'^no\s+',
    caseSensitive: false,
  );
  static final RegExp _tuningVarDelimiterRegex = RegExp(r'[:=]');
  static final RegExp _leadingBracketTagsRegex =
      RegExp(r'^\s*(?:\[[^\]]+\]\s*)+');
  static final RegExp _treeGlyphPrefixRegex = RegExp(r'^[├└─│\s]+');
  static final RegExp _goalPrefixRegex = RegExp(
    r'^goal:\s*',
    caseSensitive: false,
  );
  static final RegExp _stepHeaderPrefixRegex = RegExp(
    r'^STEP\s+\d+(?:\.\d+)?\s*[·:\-]\s*',
    caseSensitive: false,
  );
  static final RegExp _trailingSemicolonRegex = RegExp(r';$');
  static final RegExp _floatSuffixRegex = RegExp(r'^(-?\d+(?:\.\d+)?)[fF]$');
  static final RegExp _attrFieldRegex = RegExp(
    r'(?:\[SerializeField[^\]]*\]|UPROPERTY\([^)]*\))\s*(?:(?:private|public|protected|internal|mutable|const)\s+)?[\w<>:*&]+\s+(\w+)\s*=\s*([^;\n]+);',
    multiLine: true,
  );
  static final RegExp _gdVarRegex = RegExp(
    r'@export(?:_[a-z_]+)?(?:\([^)]*\))?\s+var\s+(\w+)(?:\s*:\s*[\w.]+)?\s*=\s*([^\n#;]+)',
    multiLine: true,
  );
  static final RegExp _guardCommentRegex = RegExp(
    r'(?://|#)\s*\[?(?:PLAYTEST\s+)?GUARD\]?\s*:?\s*(.+)$',
    multiLine: true,
    caseSensitive: false,
  );
  static final RegExp _nonAlphaNumRegex = RegExp(r'[^a-z0-9]');
  static final RegExp _whitespaceRegex = RegExp(r'\s+');

  static String _stripExclusionPrefixes(
    String raw, {
    bool stripNoPrefix = true,
  }) =>
      LayersTextStyleGuide.stripExclusionPrefixes(
        raw,
        stripNoPrefix: stripNoPrefix,
      );

  void _updateSerializedReleaseBlueprintMetadata(
    TierDocument doc, {
    String? releaseDocId,
    required String versionTag,
    required String title,
  }) {
    final rawArchivedBp = doc.sections['release_blueprint_json'];
    if (rawArchivedBp == null || rawArchivedBp.trim().isEmpty) return;
    try {
      final archivedMap = Map<String, dynamic>.from(
        jsonDecode(rawArchivedBp) as Map,
      );
      if (releaseDocId != null) {
        archivedMap['releaseDocId'] = releaseDocId;
      }
      archivedMap['releaseVersionTag'] = versionTag;
      archivedMap['releaseTitle'] = title;
      doc.sections['release_blueprint_json'] = jsonEncode(archivedMap);
    } catch (_) {}
  }

  /// Evaluates how many Core Loop Epics (`activeReleaseBeats`) and `v0.1` Prototype Features
  /// have received functional `MVP` coverage across built `ProductionPhase.mvp` releases.
  /// An Epic only counts as complete (`coveredBeats++`) once ALL of its non-superseded
  /// `v0.1` features have been upgraded beyond `v0.1`.
  ({
    int coveredBeats,
    int totalBeats,
    int upgradedProtoFeatures,
    int totalProtoFeatures,
    List<String> uncoveredBeatTitles,
    List<String> unupgradedProtoFeatureTitles,
    List<String> completedBeatCodes,
    List<String> incompleteBeatCodes,
    bool isComplete,
  }) mvpBeatCoverage() {
    final builtReleases =
        projectReleases.where((r) => r.childrenIds.isNotEmpty).toList();
    final protoVerTags = <String>{
      'v0.1',
      for (final r in builtReleases)
        if (releasePhaseFor(r) == ProductionPhase.prototype)
          releaseVersionTagFor(r).toLowerCase(),
    };
    final mvpVerTags = <String>{
      for (final r in builtReleases)
        if (releasePhaseFor(r) == ProductionPhase.mvp)
          releaseVersionTagFor(r).toLowerCase(),
    };
    final beats = activeReleaseBeats;
    int coveredBeats = 0;
    int totalProtoFeatures = 0;
    int upgradedProtoFeatures = 0;
    final uncoveredBeatTitles = <String>[];
    final unupgradedProtoFeatureTitles = <String>[];
    final completedBeatCodes = <String>[];
    final incompleteBeatCodes = <String>[];

    bool featureHasMvpPass(TierDocument f) {
      final originVer = (f.sections['originVersion'] ?? 'v0.1').toLowerCase();
      final states = FeatureStateNode.getStatesForDocument(f);
      final hasMvpCheckpoint = mvpVerTags.contains(originVer) ||
          states.any(
            (s) => mvpVerTags.contains(s.releaseVersion.toLowerCase()),
          );
      final upgradedPostProto = !protoVerTags.contains(originVer) ||
          states.any(
            (s) => !protoVerTags.contains(s.releaseVersion.toLowerCase()),
          );
      return (upgradedPostProto || hasMvpCheckpoint) && states.isNotEmpty;
    }

    for (int bIdx = 0; bIdx < beats.length; bIdx++) {
      final b = beats[bIdx];
      if (b.isFullProductionEpic) continue;
      final eTag = 'E${(bIdx + 1).toString().padLeft(2, '0')}';
      final feats = featuresForBeat(b.id)
          .where(
            (f) =>
                f.sections['lifecycle'] !=
                FeatureLifecycleStatus.superseded.name,
          )
          .toList();
      final beatHasAnyMvpPass = feats.any(featureHasMvpPass);
      bool allFeaturesInBeatCovered = feats.isNotEmpty && beatHasAnyMvpPass;
      for (final f in feats) {
        totalProtoFeatures++;
        final hasMvpPass = featureHasMvpPass(f);
        final isStableCompletedInCoveredBeat =
            beatHasAnyMvpPass && getDocumentProgress(f.id) >= 100;
        if (hasMvpPass || isStableCompletedInCoveredBeat) {
          upgradedProtoFeatures++;
        } else {
          allFeaturesInBeatCovered = false;
          unupgradedProtoFeatureTitles.add('$eTag · ${f.title}');
        }
      }
      if (allFeaturesInBeatCovered) {
        coveredBeats++;
        completedBeatCodes.add(eTag);
      } else {
        uncoveredBeatTitles.add('$eTag · ${b.title}');
        incompleteBeatCodes.add(eTag);
      }
    }

    final totalBeats = beats.where((b) => !b.isFullProductionEpic).length;
    final isComplete = totalBeats > 0 && coveredBeats >= totalBeats;

    return (
      coveredBeats: coveredBeats,
      totalBeats: totalBeats,
      upgradedProtoFeatures: upgradedProtoFeatures,
      totalProtoFeatures: totalProtoFeatures,
      uncoveredBeatTitles: uncoveredBeatTitles,
      unupgradedProtoFeatureTitles: unupgradedProtoFeatureTitles,
      completedBeatCodes: completedBeatCodes,
      incompleteBeatCodes: incompleteBeatCodes,
      isComplete: isComplete,
    );
  }

  /// Evaluates how many Core Loop Epics (`activeReleaseBeats`) and live Features have received
  /// `Vertical Slice` polish coverage across built `ProductionPhase.verticalSlice` releases.
  /// An Epic counts as complete (`polishedBeats++`) once it has received a Vertical Slice polish
  /// checkpoint and all of its non-superseded features are either Vertical-Slice polished or
  /// `100%` complete `STABLE ✓` features.
  ({
    int polishedBeats,
    int totalBeats,
    int polishedFeatures,
    int totalFeatures,
    List<String> unpolishedBeatTitles,
    List<String> unpolishedFeatureTitles,
    List<String> completedBeatCodes,
    List<String> incompleteBeatCodes,
    bool isComplete,
  }) verticalSliceBeatCoverage() {
    final builtReleases =
        projectReleases.where((r) => r.childrenIds.isNotEmpty).toList();
    final vsVerTags = <String>{
      for (final r in builtReleases)
        if (releasePhaseFor(r) == ProductionPhase.verticalSlice)
          releaseVersionTagFor(r).toLowerCase(),
    };
    final beats = activeReleaseBeats;
    int polishedBeats = 0;
    int totalFeatures = 0;
    int polishedFeatures = 0;
    final unpolishedBeatTitles = <String>[];
    final unpolishedFeatureTitles = <String>[];
    final completedBeatCodes = <String>[];
    final incompleteBeatCodes = <String>[];

    bool featureHasVsPass(TierDocument f) {
      final originVer = (f.sections['originVersion'] ?? 'v0.1').toLowerCase();
      final states = FeatureStateNode.getStatesForDocument(f);
      return vsVerTags.contains(originVer) ||
          states.any(
            (s) => vsVerTags.contains(s.releaseVersion.toLowerCase()),
          );
    }

    for (int bIdx = 0; bIdx < beats.length; bIdx++) {
      final b = beats[bIdx];
      if (b.isFullProductionEpic) continue;
      final eTag = 'E${(bIdx + 1).toString().padLeft(2, '0')}';
      final feats = featuresForBeat(b.id)
          .where(
            (f) =>
                f.sections['lifecycle'] !=
                FeatureLifecycleStatus.superseded.name,
          )
          .toList();
      final beatHasAnyVsPass = feats.any(featureHasVsPass);
      bool allFeaturesInBeatPolished = feats.isNotEmpty && beatHasAnyVsPass;
      for (final f in feats) {
        totalFeatures++;
        final hasVsCheckpoint = featureHasVsPass(f);
        final isStableCompletedInPolishedBeat =
            beatHasAnyVsPass && getDocumentProgress(f.id) >= 100;
        if (hasVsCheckpoint || isStableCompletedInPolishedBeat) {
          polishedFeatures++;
        } else {
          allFeaturesInBeatPolished = false;
          unpolishedFeatureTitles.add('$eTag · ${f.title}');
        }
      }
      if (allFeaturesInBeatPolished) {
        polishedBeats++;
        completedBeatCodes.add(eTag);
      } else {
        unpolishedBeatTitles.add('$eTag · ${b.title}');
        incompleteBeatCodes.add(eTag);
      }
    }

    final totalBeats = beats.where((b) => !b.isFullProductionEpic).length;
    final isComplete = totalBeats > 0 && polishedBeats >= totalBeats;

    return (
      polishedBeats: polishedBeats,
      totalBeats: totalBeats,
      polishedFeatures: polishedFeatures,
      totalFeatures: totalFeatures,
      unpolishedBeatTitles: unpolishedBeatTitles,
      unpolishedFeatureTitles: unpolishedFeatureTitles,
      completedBeatCodes: completedBeatCodes,
      incompleteBeatCodes: incompleteBeatCodes,
      isComplete: isComplete,
    );
  }

  /// Version tag of the Act 2 Full-Game Skeleton release (`fpSkeleton: 'true'`), or `null` before it is built.
  String? get fullProductionSkeletonVersionTag {
    for (final r in projectReleases) {
      if (r.childrenIds.isNotEmpty && r.sections['fpSkeleton'] == 'true') {
        return releaseVersionTagFor(r).toLowerCase();
      }
    }
    return null;
  }

  /// Evaluates `04 · Full Production` progress.
  /// - Act 2 (Full Production Blueprint): counts only Full Production Epics (`act: fullProduction`).
  ///   An Epic is covered once it receives a Production Pass after the Skeleton (same STABLE-sibling rule as MVP).
  ///   `isReadyForLaunch` = Skeleton built and every Full Production Epic covered → next release is `v1.0` Launch.
  /// - Legacy projects (Full Production built before Act 2, no tagged Epics) keep the old all-Epic coverage.
  ({
    int coveredBeats,
    int totalBeats,
    int remainingDeferredCount,
    int openFixCount,
    List<String> uncoveredBeatTitles,
    List<String> remainingDeferredExclusions,
    List<String> completedBeatCodes,
    List<String> incompleteBeatCodes,
    bool skeletonBuilt,
    bool launchReleaseBuilt,
    bool isLegacy,
    bool isReadyForLaunch,
  }) fullProductionCoverage() {
    final builtReleases =
        projectReleases.where((r) => r.childrenIds.isNotEmpty).toList();
    final builtFullProd = builtReleases
        .where((r) => releasePhaseFor(r) == ProductionPhase.fullProduction)
        .toList();
    final skeletonVer = fullProductionSkeletonVersionTag;
    final launchReleaseBuilt =
        builtFullProd.any((r) => r.sections['launchRelease'] == 'true');
    final beats = activeReleaseBeats;
    final hasFpEpics = beats.any((b) => b.isFullProductionEpic);
    final isLegacy = builtFullProd.isNotEmpty && !hasFpEpics;
    final prodOrVsVerTags = <String>{
      for (final r in builtReleases)
        if (releasePhaseFor(r) == ProductionPhase.fullProduction ||
            releasePhaseFor(r) == ProductionPhase.verticalSlice ||
            releasePhaseFor(r) == ProductionPhase.postLaunch)
          releaseVersionTagFor(r).toLowerCase(),
    };
    int coveredBeats = 0;
    int totalBeats = 0;
    int openFixCount = 0;
    final uncoveredBeatTitles = <String>[];
    final completedBeatCodes = <String>[];
    final incompleteBeatCodes = <String>[];
    final activeFeatTitlesLower = <String>{};

    bool featureHasProductionPass(TierDocument f) {
      if (skeletonVer == null) return false;
      final originVer = (f.sections['originVersion'] ?? 'v0.1').toLowerCase();
      if (originVer != skeletonVer) return true;
      return FeatureStateNode.getStatesForDocument(f).any(
        (s) => s.releaseVersion.toLowerCase() != skeletonVer,
      );
    }

    for (int bIdx = 0; bIdx < beats.length; bIdx++) {
      final b = beats[bIdx];
      final eTag = 'E${(bIdx + 1).toString().padLeft(2, '0')}';
      final feats = featuresForBeat(b.id)
          .where(
            (f) =>
                f.sections['lifecycle'] !=
                FeatureLifecycleStatus.superseded.name,
          )
          .toList();
      for (final f in feats) {
        activeFeatTitlesLower.add(f.title.toLowerCase().trim());
        for (final s in FeatureStateNode.getStatesForDocument(f)) {
          for (final t in s.checklist) {
            if (t.text.startsWith('[FIX]') && !t.completed) {
              openFixCount++;
            }
          }
        }
      }

      final bool beatCovered;
      if (isLegacy) {
        beatCovered = feats.any((f) {
          final originVer =
              (f.sections['originVersion'] ?? 'v0.1').toLowerCase();
          final states = FeatureStateNode.getStatesForDocument(f);
          return prodOrVsVerTags.contains(originVer) ||
              states.any(
                (s) => prodOrVsVerTags.contains(s.releaseVersion.toLowerCase()),
              ) ||
              getDocumentProgress(f.id) >= 100;
        });
      } else {
        if (!b.isFullProductionEpic) continue;
        final beatHasAnyPass = feats.any(featureHasProductionPass);
        beatCovered = feats.isNotEmpty &&
            beatHasAnyPass &&
            feats.every(
              (f) =>
                  featureHasProductionPass(f) ||
                  getDocumentProgress(f.id) >= 100,
            );
      }
      totalBeats++;
      if (beatCovered) {
        coveredBeats++;
        completedBeatCodes.add(eTag);
      } else {
        uncoveredBeatTitles.add('$eTag · ${b.title}');
        incompleteBeatCodes.add(eTag);
      }
    }

    final remainingDeferredExclusions = <String>[];
    final proj = activeProject;
    final rawEx = (proj?.sections['exclusions'] ?? '').trim();
    if (rawEx.isNotEmpty) {
      for (final line in rawEx.split('\n')) {
        final clean = _stripExclusionPrefixes(line, stripNoPrefix: false);
        if (clean.isEmpty) continue;
        // Permanent exclusions stay excluded; deferred exclusions unlocked by Full Production count if not yet promoted
        if (ReleaseBlueprint.isDeferredExclusionUnlockedInPhase(
          clean,
          ProductionPhase.fullProduction,
        )) {
          final shortTitle = _stripExclusionPrefixes(clean)
              .split('—')
              .first
              .split(':')
              .first
              .toLowerCase()
              .trim();
          final alreadyPromoted = shortTitle.isNotEmpty &&
              activeFeatTitlesLower.any(
                (ft) => ft.contains(shortTitle) || shortTitle.contains(ft),
              );
          if (!alreadyPromoted) {
            remainingDeferredExclusions.add(clean);
          }
        }
      }
    }

    final allCovered = totalBeats > 0 && coveredBeats >= totalBeats;
    final isReadyForLaunch = isLegacy
        ? allCovered && openFixCount == 0
        : skeletonVer != null && allCovered;

    return (
      coveredBeats: coveredBeats,
      totalBeats: totalBeats,
      remainingDeferredCount: remainingDeferredExclusions.length,
      openFixCount: openFixCount,
      uncoveredBeatTitles: uncoveredBeatTitles,
      remainingDeferredExclusions: remainingDeferredExclusions,
      completedBeatCodes: completedBeatCodes,
      incompleteBeatCodes: incompleteBeatCodes,
      skeletonBuilt: skeletonVer != null,
      launchReleaseBuilt: launchReleaseBuilt,
      isLegacy: isLegacy,
      isReadyForLaunch: isReadyForLaunch,
    );
  }

  /// True once the Vertical Slice is done (or a draft release is set to Full Production)
  /// and the next step is defining the Act 2 Full Production Blueprint (no Full Production release built yet).
  bool get needsFullProductionBlueprint {
    final builtReleases =
        projectReleases.where((r) => r.childrenIds.isNotEmpty).toList();
    if (builtReleases.isEmpty) return false;
    if (builtReleases.any(
      (r) =>
          releasePhaseFor(r) == ProductionPhase.fullProduction ||
          releasePhaseFor(r) == ProductionPhase.postLaunch,
    )) {
      return false;
    }
    final activeDraftPhase =
        (activeRelease != null && activeRelease!.childrenIds.isEmpty)
            ? releasePhaseFor(activeRelease!)
            : null;
    return inferNextProgressivePhase() == ProductionPhase.fullProduction ||
        activeDraftPhase == ProductionPhase.fullProduction;
  }

  /// Infers the natural next `ProductionPhase` (`prototype` -> multi-release `mvp` -> multi-release `verticalSlice` -> `fullProduction` -> `postLaunch`).
  /// Act 2 stays in `fullProduction` (Skeleton -> Production Passes -> `v1.0` Launch) until the `v1.0` Launch Release
  /// is 100% verified with `0` open `[FIX]` tasks, then graduates to `v1.1+` Post-Launch & Live Ops.
  ProductionPhase inferNextProgressivePhase() {
    final releases = projectReleases;
    final builtReleases =
        releases.where((r) => r.childrenIds.isNotEmpty).toList();
    if (builtReleases.isEmpty) {
      return ProductionPhase.prototype;
    }
    if (builtReleases.any(
      (r) => releasePhaseFor(r) == ProductionPhase.postLaunch,
    )) {
      return ProductionPhase.postLaunch;
    }
    final builtFullProd = builtReleases
        .where((r) => releasePhaseFor(r) == ProductionPhase.fullProduction)
        .toList();
    if (builtFullProd.isNotEmpty) {
      final fpCov = fullProductionCoverage();
      if (fpCov.isLegacy) {
        final allFullProdVerified = builtFullProd.every(
          (r) => getDocumentProgress(r.id) >= 100,
        );
        if (allFullProdVerified || fpCov.isReadyForLaunch) {
          return ProductionPhase.postLaunch;
        }
        return ProductionPhase.fullProduction;
      }
      final launchRels =
          builtFullProd.where((r) => r.sections['launchRelease'] == 'true');
      if (launchRels.isNotEmpty &&
          launchRels.every((r) => getDocumentProgress(r.id) >= 100) &&
          fpCov.openFixCount == 0) {
        return ProductionPhase.postLaunch;
      }
      return ProductionPhase.fullProduction;
    }
    final vsCov = verticalSliceBeatCoverage();
    if (vsCov.isComplete) {
      return ProductionPhase.fullProduction;
    }
    if (builtReleases.any(
      (r) => releasePhaseFor(r) == ProductionPhase.verticalSlice,
    )) {
      return ProductionPhase.verticalSlice;
    }
    final mvpCov = mvpBeatCoverage();
    if (mvpCov.isComplete) {
      return ProductionPhase.verticalSlice;
    }
    return ProductionPhase.mvp;
  }

  /// True when the next Full Production release should be the `v1.0` Launch Release.
  bool get isNextReleaseV1Launch {
    if (inferNextProgressivePhase() != ProductionPhase.fullProduction) {
      return false;
    }
    final cov = fullProductionCoverage();
    return !cov.isLegacy && cov.isReadyForLaunch && !cov.launchReleaseBuilt;
  }

  /// Next Post-Launch version: highest existing `v1.N` minor + 1 (handles legacy `v1.x` Full Production tags).
  String get _nextPostLaunchVersionTag {
    int maxMinor = 0;
    final v1Regex = RegExp(r'^v1\.(\d+)$');
    for (final r in projectReleases) {
      if (r.childrenIds.isEmpty) continue;
      final m = v1Regex.firstMatch(releaseVersionTagFor(r).toLowerCase());
      if (m != null) {
        final minor = int.tryParse(m.group(1)!) ?? 0;
        if (minor > maxMinor) maxMinor = minor;
      }
    }
    return 'v1.${maxMinor + 1}';
  }

  ReleaseScope _releaseScopeForPhase(ProductionPhase phase) {
    switch (phase) {
      case ProductionPhase.prototype:
        return ReleaseScope.prototype;
      case ProductionPhase.mvp:
        return ReleaseScope.mvp;
      case ProductionPhase.verticalSlice:
        return ReleaseScope.verticalSlice;
      case ProductionPhase.fullProduction:
      case ProductionPhase.postLaunch:
        return ReleaseScope.fullProduction;
    }
  }

  /// Allows the developer to switch the target `ProductionPhase` (`MVP`, `Vertical Slice`, `Full Production`, `Post-Launch`)
  /// inside the Progressive Release Co-Pilot modal and re-synthesize the draft blueprint for that phase.
  Future<void> setDraftReleasePhase(ProductionPhase targetPhase) async {
    final relDoc = activeRelease;
    final proj = activeProject;
    if (relDoc == null || proj == null) return;
    _currentPhase = targetPhase;
    final targetScope = _releaseScopeForPhase(targetPhase);
    relDoc.sections['phase'] = targetPhase.name;
    relDoc.sections['releaseScope'] = targetScope.name;
    relDoc.sections['agentReasoned'] = 'true';
    relDoc.sections['phaseLockedByUser'] = 'true';
    if (targetPhase == ProductionPhase.postLaunch) {
      final existingPostCount = projectReleases
          .where(
            (r) =>
                r.id != relDoc.id &&
                releasePhaseFor(r) == ProductionPhase.postLaunch,
          )
          .length;
      relDoc.sections['versionTag'] = _nextPostLaunchVersionTag;
      relDoc.sections['postLaunchPass'] = '${existingPostCount + 1}';
      relDoc.sections.remove('launchRelease');
    } else if (targetPhase == ProductionPhase.fullProduction) {
      relDoc.sections.remove('postLaunchPass');
      final existingFullProdCount = projectReleases
          .where(
            (r) =>
                r.id != relDoc.id &&
                releasePhaseFor(r) == ProductionPhase.fullProduction,
          )
          .length;
      final pass = existingFullProdCount + 1;
      final idx = proj.childrenIds.indexOf(relDoc.id);
      final isLaunch = isNextReleaseV1Launch;
      relDoc.sections['versionTag'] = isLaunch
          ? 'v1.0'
          : 'v0.${idx >= 0 ? idx + 1 : proj.childrenIds.length}';
      if (isLaunch) {
        relDoc.sections['launchRelease'] = 'true';
      } else {
        relDoc.sections.remove('launchRelease');
      }
      relDoc.sections['fullProductionPass'] = '$pass';
    } else {
      relDoc.sections.remove('fullProductionPass');
      relDoc.sections.remove('postLaunchPass');
      relDoc.sections.remove('launchRelease');
      final idx = proj.childrenIds.indexOf(relDoc.id);
      if (idx >= 0) {
        relDoc.sections['versionTag'] = 'v0.${idx + 1}';
      }
    }
    final resolvedVerTag = relDoc.sections['versionTag'] ?? 'v0.2';
    relDoc.title = '$resolvedVerTag: ${targetPhase.label}';
    _persistDocument(relDoc);
    _syncActiveProjectMetadata();
    await openReleasePlanGate(
      releaseId: relDoc.id,
      transitionToGateStage: false,
    );
    if (_releaseBlueprint != null) {
      _initialProgressiveTrack0BlueprintJson =
          jsonEncode(_releaseBlueprint!.toJson());
    }
  }

  /// Prunes any leftover unbuilt draft releases (once the project has at least one built release)
  /// and sequentially re-packs all `v0.X` releases (`v0.1`, `v0.2`, ..., `v0.N`) so skipped
  /// version gaps never occur.
  void repackProjectReleasesSequentially(
    TierDocument proj, {
    bool pruneAllUnbuilt = false,
    String? keepReleaseId,
  }) {
    final user = _authService.currentUser;

    // 1. Deduplicate proj.childrenIds while keeping only existing release docs
    final deduped = <String>[];
    for (final id in proj.childrenIds) {
      if (!deduped.contains(id) && documents.containsKey(id)) {
        deduped.add(id);
      }
    }
    proj.childrenIds = deduped;

    // 2. If at least one built release exists, prune unbuilt draft releases
    final hasBuiltRelease = proj.childrenIds.any(
      (id) => documents[id]?.childrenIds.isNotEmpty ?? false,
    );
    if (hasBuiltRelease) {
      final toRemove = <String>[];
      for (final id in proj.childrenIds) {
        final relDoc = documents[id];
        if (relDoc == null) continue;
        if (relDoc.childrenIds.isEmpty) {
          final shouldKeep = !pruneAllUnbuilt && id == keepReleaseId;
          if (!shouldKeep) {
            toRemove.add(id);
          }
        }
      }
      for (final id in toRemove) {
        proj.childrenIds.remove(id);
        documents.remove(id);
        LocalVaultService.deleteDocument(id);
        if (user != null) {
          _firestoreService.deleteDocument(uid: user.uid, docId: id);
        }
      }
    }

    // Remove any orphaned TierType.release documents belonging to this project
    final activeSet = proj.childrenIds.toSet();
    final orphanRelIds = documents.values
        .where(
          (d) =>
              d.tier == TierType.release &&
              d.parentId == proj.id &&
              !activeSet.contains(d.id),
        )
        .map((d) => d.id)
        .toList();
    for (final orphanId in orphanRelIds) {
      documents.remove(orphanId);
      LocalVaultService.deleteDocument(orphanId);
      if (user != null) {
        _firestoreService.deleteDocument(uid: user.uid, docId: orphanId);
      }
    }

    // 3. Re-pack remaining v0.X releases sequentially (1..N)
    final versionRemap = <String, String>{};
    bool anyChanged = false;

    for (int i = 0; i < proj.childrenIds.length; i++) {
      final seqNum = i + 1;
      final oldRelId = proj.childrenIds[i];
      final relDoc = documents[oldRelId];
      if (relDoc == null) continue;

      final currentVerTag = releaseVersionTagFor(relDoc);
      final isActTwoOrLater =
          relDoc.sections['phase'] == ProductionPhase.fullProduction.name ||
          relDoc.sections['phase'] == ProductionPhase.postLaunch.name ||
          relDoc.releaseScope == ReleaseScope.fullProduction ||
          currentVerTag.toLowerCase().startsWith('v1.');
      if (isActTwoOrLater) continue;

      final expectedVer = 'v0.$seqNum';
      final expectedId = proj.id == 'proj_main'
          ? 'rel_v0_$seqNum'
          : '${proj.id}_rel_v0_$seqNum';

      bool docChanged = false;
      if (currentVerTag != expectedVer &&
          currentVerTag.toLowerCase().startsWith('v0.')) {
        versionRemap[currentVerTag] = expectedVer;
        docChanged = true;
      }
      if (relDoc.sections['versionTag'] != expectedVer) {
        relDoc.sections['versionTag'] = expectedVer;
        docChanged = true;
      }
      if (_minorVerRegex.hasMatch(relDoc.title)) {
        final updatedTitle = relDoc.title.replaceAll(
          _minorVerRegex,
          expectedVer,
        );
        if (updatedTitle != relDoc.title) {
          relDoc.title = updatedTitle;
          docChanged = true;
        }
      }
      final rawScope = relDoc.sections['scope'];
      if (rawScope != null && _minorVerRegex.hasMatch(rawScope)) {
        final updatedScope = rawScope.replaceAll(_minorVerRegex, expectedVer);
        if (updatedScope != rawScope) {
          relDoc.sections['scope'] = updatedScope;
          docChanged = true;
        }
      }

      if (oldRelId != expectedId &&
          (!documents.containsKey(expectedId) ||
              !proj.childrenIds.contains(expectedId))) {
        final movedDoc = relDoc.copyWith(
          id: expectedId,
          sections: Map<String, String>.from(relDoc.sections),
        );
        _updateSerializedReleaseBlueprintMetadata(
          movedDoc,
          releaseDocId: expectedId,
          versionTag: expectedVer,
          title: movedDoc.title,
        );
        documents.remove(oldRelId);
        LocalVaultService.deleteDocument(oldRelId);
        if (user != null) {
          _firestoreService.deleteDocument(uid: user.uid, docId: oldRelId);
        }
        documents[expectedId] = movedDoc;
        _persistDocument(movedDoc);
        proj.childrenIds[i] = expectedId;

        if (_activeReleaseId == oldRelId) {
          _activeReleaseId = expectedId;
        }
        if (proj.sections['active_release_id'] == oldRelId) {
          proj.sections['active_release_id'] = expectedId;
        }
        if (_releaseBlueprint != null &&
            _releaseBlueprint!.releaseDocId == oldRelId) {
          _releaseBlueprint = ReleaseBlueprint(
            releaseDocId: expectedId,
            releaseTitle: movedDoc.title,
            releaseVersionTag: expectedVer,
            preset: _releaseBlueprint!.preset,
            goal: _releaseBlueprint!.goal.replaceAll(
              _minorVerRegex,
              expectedVer,
            ),
            doneWhen: _releaseBlueprint!.doneWhen.replaceAll(
              _minorVerRegex,
              expectedVer,
            ),
            questions: _releaseBlueprint!.questions,
            beats: _releaseBlueprint!.beats,
            explicitExclusions: _releaseBlueprint!.explicitExclusions,
            builtSoFar: _releaseBlueprint!.builtSoFar,
            missingGaps: _releaseBlueprint!.missingGaps,
            lastAgentReply: _releaseBlueprint!.lastAgentReply,
          );
        }
        for (final doc in documents.values) {
          if (doc.parentId == oldRelId) {
            doc.parentId = expectedId;
            _persistDocument(doc);
          }
        }
        anyChanged = true;
      } else if (docChanged) {
        _updateSerializedReleaseBlueprintMetadata(
          relDoc,
          versionTag: expectedVer,
          title: relDoc.title,
        );
        if (_releaseBlueprint != null &&
            _releaseBlueprint!.releaseDocId == oldRelId) {
          _releaseBlueprint!.releaseVersionTag = expectedVer;
          _releaseBlueprint!.releaseTitle = relDoc.title;
        }
        _persistDocument(relDoc);
        anyChanged = true;
      }
    }

    // 3b. Deduplicate beatDoc.childrenIds across all Epics of the project so duplicate feature cards never appear
    final projectBeatIdsForDedup = <String>{
      for (final relId in proj.childrenIds)
        ...?documents[relId]?.childrenIds,
    };
    for (final bId in projectBeatIdsForDedup) {
      final beatDoc = documents[bId];
      if (beatDoc == null || beatDoc.childrenIds.length <= 1) continue;
      final dedupedFeatIds = <String>[];
      for (final fid in beatDoc.childrenIds) {
        if (!dedupedFeatIds.contains(fid) && documents.containsKey(fid)) {
          dedupedFeatIds.add(fid);
        }
      }
      if (dedupedFeatIds.length != beatDoc.childrenIds.length) {
        beatDoc.childrenIds = dedupedFeatIds;
        _persistDocument(beatDoc);
        anyChanged = true;
      }
    }

    // 4. Remap any FeatureStateNode checkpoint releaseVersion tags and blueprint items
    if (versionRemap.isNotEmpty) {
      final projectBeatIds = <String>{
        for (final relId in proj.childrenIds)
          ...?documents[relId]?.childrenIds,
      };
      for (final doc in documents.values) {
        if (doc.tier == TierType.feature &&
            doc.parentId != null &&
            projectBeatIds.contains(doc.parentId)) {
          final states = FeatureStateNode.getStatesForDocument(doc);
          bool featStatesChanged = false;
          for (final s in states) {
            final mappedVer = versionRemap[s.releaseVersion];
            if (mappedVer != null) {
              s.parameters['releaseVersion'] = mappedVer;
              featStatesChanged = true;
            }
          }
          if (featStatesChanged) {
            FeatureStateNode.saveStatesToDocument(doc, states);
            _persistDocument(doc);
          }
        }
      }
      if (_releaseBlueprint != null) {
        for (final beat in _releaseBlueprint!.beats) {
          for (final feat in beat.features) {
            final mappedOrigin = versionRemap[feat.originVersion];
            if (mappedOrigin != null) {
              feat.originVersion = mappedOrigin;
            }
            feat.checkpoints = [
              for (final cp in feat.checkpoints)
                versionRemap.containsKey(cp.releaseVersion)
                    ? ProposedCheckpointBlueprint(
                        title: cp.title,
                        playtestCriteria: cp.playtestCriteria,
                        tasks: cp.tasks,
                        coveredScope: cp.coveredScope,
                        tuningParams: cp.tuningParams,
                        edgeCases: cp.edgeCases,
                        releaseVersion: versionRemap[cp.releaseVersion]!,
                      )
                    : cp,
            ];
          }
        }
      }
    }

    if (proj.childrenIds.isNotEmpty &&
        (_activeReleaseId == null ||
            !proj.childrenIds.contains(_activeReleaseId))) {
      _activeReleaseId = proj.childrenIds.last;
      anyChanged = true;
    }

    if (anyChanged || versionRemap.isNotEmpty) {
      _persistDocument(proj);
    }
  }

  ({int index, String id}) _allocateNextReleaseIdAndIndex(TierDocument proj) {
    repackProjectReleasesSequentially(proj, pruneAllUnbuilt: true);
    final nextIndex = proj.childrenIds.length + 1;
    final candidateId = proj.id == 'proj_main'
        ? 'rel_v0_$nextIndex'
        : '${proj.id}_rel_v0_$nextIndex';
    return (index: nextIndex, id: candidateId);
  }

  /// Next progressive version tag (`v0.2`, `v0.3`, ... continuing through Act 2 Full Production,
  /// `v1.0` for the Launch Release, then `v1.1+` in Post-Launch).
  String get nextProgressiveVersionLabel {
    final releases = projectReleases;
    final builtReleases =
        releases.where((r) => r.childrenIds.isNotEmpty).toList();
    if (builtReleases.isNotEmpty) {
      final nextPhase = inferNextProgressivePhase();
      if (nextPhase == ProductionPhase.postLaunch) {
        return _nextPostLaunchVersionTag;
      }
      if (nextPhase == ProductionPhase.fullProduction) {
        if (isNextReleaseV1Launch) return 'v1.0';
        if (fullProductionCoverage().isLegacy) {
          return _nextPostLaunchVersionTag;
        }
      }
    }
    final builtCount = builtReleases.length;
    final baseCount = builtCount > 0 ? builtCount : releases.length;
    return 'v0.${baseCount + 1}';
  }

  // ===========================================================================
  // ACT 2 · FULL PRODUCTION BLUEPRINT (Blueprint -> v0.N Skeleton -> Passes -> v1.0 Launch)
  // ===========================================================================

  /// The approved or in-progress Act 2 Full Production Blueprint persisted on the active project.
  FullProductionBlueprint? get fullProductionBlueprint {
    final raw = activeProject?.sections[FullProductionBlueprint.storageKey];
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      return FullProductionBlueprint.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  bool get isDraftingFullProductionBlueprint =>
      _isDraftingFullProductionBlueprint;

  /// Saves edits to the Full Production Blueprint (before the Skeleton is built).
  void updateFullProductionBlueprint(FullProductionBlueprint bp) {
    final proj = activeProject;
    if (proj == null) return;
    proj.sections[FullProductionBlueprint.storageKey] = jsonEncode(bp.toJson());
    _persistDocument(proj);
    notifyListeners();
  }

  /// Inbox items scheduled for Full Production (not yet implemented).
  List<FeatureInboxItem> get _fullProductionScheduledInboxItems => featureInboxItems
      .where(
        (i) =>
            i.status != FeatureInboxStatus.implemented &&
            i.releaseTimingMode != InboxReleaseTimingMode.now &&
            i.targetFuturePhase.index <= ProductionPhase.fullProduction.index,
      )
      .toList();

  /// Drafts the 6-section Full Production Blueprint with `gemini-flash-latest` (single pass).
  Future<FullProductionBlueprint?> draftFullProductionBlueprint() async {
    final proj = activeProject;
    if (proj == null) return null;
    _isDraftingFullProductionBlueprint = true;
    notifyListeners();
    try {
      final conceptSummary = '''
Concept Blueprint:
- 01 Goal: "${SectionTextUtils.resolveGoal(proj.sections)}"
- 02 Game Spec: ${proj.sections['game_spec'] ?? ''}
- 03 Tech Spec: ${proj.sections['tech_spec'] ?? ''}
- 04 Design Pillars: ${(proj.sections['design_pillars'] ?? '').replaceAll('\n', ' | ')}
- 05 Trade-Offs: ${(proj.sections['trade_offs'] ?? '').replaceAll('\n', ' | ')}
- 07 Out of Scope: ${(proj.sections['exclusions'] ?? '').replaceAll('\n', ' | ')}
- 08 Done When: "${SectionTextUtils.resolveDoneWhen(proj.sections)}"''';
      final treeLines = <String>[];
      final beats = activeReleaseBeats;
      for (int bIdx = 0; bIdx < beats.length; bIdx++) {
        final feats = featuresForBeat(beats[bIdx].id).map((f) {
          final asset = (f.sections['primary_asset'] ?? '').trim();
          return asset.isNotEmpty ? '${f.title} [$asset]' : f.title;
        }).join(', ');
        treeLines.add(
          '- E${(bIdx + 1).toString().padLeft(2, '0')} ${beats[bIdx].title}: $feats',
        );
      }
      final unlockedDeferred = fullProductionCoverage().remainingDeferredExclusions;
      final drafted = await FullProductionBlueprintAgent.draft(
        projectTitle: proj.title,
        conceptSummary: conceptSummary,
        liveTreeSummary: treeLines.join('\n'),
        unlockedDeferredExclusions: unlockedDeferred,
        scheduledInboxTitles: [
          for (final i in _fullProductionScheduledInboxItems) i.featureTitle,
        ],
        apiKey: _apiKey,
        modelName: _planningModel,
        thinkingLevel: _thinkingLevel,
      );
      if (drafted == null) {
        _setOfflineState();
        return null;
      }
      _offlineErrorMessage = null;
      updateFullProductionBlueprint(drafted);
      return drafted;
    } finally {
      _isDraftingFullProductionBlueprint = false;
      notifyListeners();
    }
  }

  /// Approves the Full Production Blueprint and builds the `v0.N` Full-Game Skeleton release:
  /// core Epics stay `STABLE ✓`, new Full Production Epics are planned in one full-blueprint pass
  /// (always via `planRelease`, never section-by-section) and tagged `act: fullProduction` on execute.
  Future<bool> approveFullProductionBlueprintAndBuildSkeleton() async {
    final proj = activeProject;
    final fpBp = fullProductionBlueprint;
    if (proj == null || fpBp == null || !fpBp.isReadyToApprove) return false;
    if (!GeminiAgentClient.hasKey(_apiKey)) {
      _setOfflineState();
      notifyListeners();
      return false;
    }

    repackProjectReleasesSequentially(proj, pruneAllUnbuilt: true);
    final existingBeats = List<TierDocument>.from(activeReleaseBeats);
    final existingFeaturesByBeat = <String, List<TierDocument>>{
      for (final b in existingBeats)
        b.id: featuresForBeat(b.id, includeSuperseded: true),
    };
    final completedReleases = projectReleases
        .where((r) => r.childrenIds.isNotEmpty)
        .toList();
    final allocated = _allocateNextReleaseIdAndIndex(proj);
    final verTag = 'v0.${allocated.index}';
    final relDoc = TierDocument(
      id: allocated.id,
      title: '$verTag: Full-Game Skeleton - Full Production',
      tier: TierType.release,
      parentId: proj.id,
      sections: {
        'versionTag': verTag,
        'releaseScope': ReleaseScope.fullProduction.name,
        'phase': ProductionPhase.fullProduction.name,
        'fullProductionPass': '1',
        'fpSkeleton': 'true',
        'scope':
            'Goal: ${fpBp.goal}\n\nIn Scope:\n${fpBp.fullGameLoop.map((l) => '• $l').join('\n')}\n\nDone When: ${fpBp.doneWhen}',
      },
    );
    documents[relDoc.id] = relDoc;
    _persistDocument(relDoc);
    proj.childrenIds.add(relDoc.id);
    _activeReleaseId = relDoc.id;
    _currentPhase = ProductionPhase.fullProduction;
    _currentStage = WorkbenchStage.releaseWorkbench;
    _syncActiveProjectMetadata();

    _isAgentBusy = true;
    _agentProgressStep = 'Planning $verTag Full-Game Skeleton…';
    notifyListeners();
    ReleaseBlueprint? planned;
    try {
      planned = await ReleasePlannerAgent.planRelease(
        projectDoc: proj,
        releaseDoc: relDoc,
        completedReleases: completedReleases,
        existingBeats: existingBeats,
        existingFeaturesByBeat: existingFeaturesByBeat,
        apiKey: _apiKey,
        modelName: _planningModel,
        thinkingLevel: _thinkingLevel,
        fullProductionBlueprint: fpBp,
      );
    } finally {
      _isAgentBusy = false;
      _agentProgressStep = null;
    }
    if (planned == null ||
        !planned.beats.any(
          (b) => !existingBeats.any((eb) => eb.id == b.id) &&
              b.includedFeatures.isNotEmpty,
        )) {
      proj.childrenIds.remove(relDoc.id);
      documents.remove(relDoc.id);
      LocalVaultService.deleteDocument(relDoc.id);
      _activeReleaseId = completedReleases.isNotEmpty
          ? completedReleases.last.id
          : null;
      _syncActiveProjectMetadata();
      _setOfflineState();
      notifyListeners();
      return false;
    }
    planned.releaseVersionTag = verTag;
    relDoc.sections['release_blueprint_json'] = jsonEncode(planned.toJson());
    _persistDocument(relDoc);
    _releaseBlueprint = planned;
    _offlineErrorMessage = null;
    _markPromotedInboxItemsImplemented(fpBp.promotedSystems);
    await approveAndExecuteReleasePlan();
    return true;
  }

  /// Single source of truth: Inbox items promoted through `04 Promoted Systems` are marked implemented
  /// so they are never auto-injected a second time.
  void _markPromotedInboxItemsImplemented(List<String> promotedSystems) {
    final promotedLower = [
      for (final p in promotedSystems) p.toLowerCase().trim(),
    ].where((p) => p.isNotEmpty).toList();
    if (promotedLower.isEmpty) return;
    final items = List<FeatureInboxItem>.from(featureInboxItems);
    bool changed = false;
    for (final item in items) {
      if (item.status == FeatureInboxStatus.implemented) continue;
      if (item.targetFuturePhase.index > ProductionPhase.fullProduction.index) {
        continue;
      }
      final title = item.featureTitle.toLowerCase().trim();
      if (title.isEmpty) continue;
      if (promotedLower.any((p) => p == title || p.contains(title) || title.contains(p))) {
        item.status = FeatureInboxStatus.implemented;
        changed = true;
      }
    }
    if (changed) _saveFeatureInboxItems(items);
  }

  /// Deterministic `v1.0` Launch Release blueprint: every feature stays `STABLE ✓` (open `[FIX]` tasks are
  /// resolved in place) plus 1 `[NEW]` Release Build Export feature in the last Full Production Epic.
  ReleaseBlueprint? _buildLaunchReleaseBlueprint(
    TierDocument relDoc,
    String verTag,
    List<TierDocument> existingBeats,
  ) {
    if (existingBeats.isEmpty) return null;
    final fpBp = fullProductionBlueprint;
    final shipWhen = (fpBp?.doneWhen.trim().isNotEmpty ?? false)
        ? fpBp!.doneWhen.trim()
        : 'Launch standalone build → play from title screen to credits without crashes';
    final lastFpIdx = existingBeats.lastIndexWhere((b) => b.isFullProductionEpic);
    final hostIdx = lastFpIdx >= 0 ? lastFpIdx : existingBeats.length - 1;
    const exportTuning = <String>[
      'buildTargets: 1 platform',
      'fullRunThroughs: 2 runs',
    ];
    const exportGuards = <String>[
      '[STATE GUARD] Block ship while any [FIX] task is open',
    ];
    final beats = <ProposedBeatBlueprint>[];
    for (int bIdx = 0; bIdx < existingBeats.length; bIdx++) {
      final b = existingBeats[bIdx];
      final feats = <ProposedFeatureBlueprint>[
        for (final f in featuresForBeat(b.id, includeSuperseded: true))
          ProposedFeatureBlueprint(
            id: f.id,
            title: f.title,
            goal: SectionTextUtils.resolveGoal(f.sections),
            doneWhen: SectionTextUtils.resolveDoneWhen(f.sections),
            estimatedHours: 0,
            included: !isFeatureSuperseded(f),
            lifecycle: isFeatureSuperseded(f)
                ? FeatureLifecycleStatus.superseded
                : FeatureLifecycleStatus.stable,
            originVersion: f.sections['originVersion'] ?? 'v0.1',
            primarySharedScriptOrScene:
                (f.sections['primary_asset'] ?? '').trim().isNotEmpty
                    ? f.sections['primary_asset']!.trim()
                    : null,
            inScope: SectionTextUtils.resolveInScope(f.sections),
          ),
        if (bIdx == hostIdx)
          ProposedFeatureBlueprint(
            id: 'feat_${b.id}_${verTag.replaceAll('.', '_')}_release_export',
            title: 'Release Build Export',
            goal: '+Standalone export preset, +full run-through, +crash & save check',
            doneWhen: shipWhen,
            estimatedHours: 4,
            included: true,
            lifecycle: FeatureLifecycleStatus.newFeature,
            originVersion: verTag,
            inScope: const [
              '+Standalone export preset & icon',
              '+Full title-to-credits run-through',
              '+Crash & save check',
            ],
            tuningParams: exportTuning,
            edgeCases: exportGuards,
            checkpoints: [
              ProposedCheckpointBlueprint(
                title: 'Release Build Export',
                playtestCriteria: shipWhen,
                releaseVersion: verTag,
                tasks: const [
                  'Export Preset & Icon (1h)',
                  'Standalone Run-Through (2h)',
                  'Crash & Save Check (1h)',
                ],
                coveredScope: const ['+Standalone export & run-through'],
                tuningParams: exportTuning,
                edgeCases: exportGuards,
              ),
            ],
          ),
      ];
      beats.add(
        ProposedBeatBlueprint(
          id: b.id,
          title: b.title,
          goal: SectionTextUtils.resolveGoal(b.sections),
          doneWhen: SectionTextUtils.resolveDoneWhen(b.sections),
          features: feats,
        ),
      );
    }
    return ReleaseBlueprint(
      releaseDocId: relDoc.id,
      releaseTitle: '$verTag: Launch Release — Build Export & Ship Sweep',
      releaseVersionTag: verTag,
      preset: ReleaseScope.fullProduction,
      goal: 'v1.0 Launch — Export the standalone build and clear every open [FIX] task.',
      doneWhen: shipWhen,
      questions: const [],
      beats: beats,
      explicitExclusions: fpBp?.permanentCuts ?? const [],
    );
  }

  /// Prepares the next Progressive Release (`v0.2`, `v0.3+`) blueprint in-memory while keeping
  /// the user inside `2. Workbench`, optionally applying a natural-language directive from the
  /// Agentic Next-Release Co-Pilot.
  Future<ReleaseBlueprint?> prepareProgressiveNextReleaseDraft({
    String? agentDirective,
  }) async {
    _preModalReleaseIds = Set<String>.from(
      activeProject?.childrenIds ?? const <String>[],
    );
    _preModalReleaseBlueprint = _releaseBlueprint;
    _preModalFeatureInboxJson = activeProject?.sections['feature_inbox_json'];
    _preModalExclusions = activeProject?.sections['exclusions'];
    _preModalConceptExclusions = _conceptDraft != null
        ? List<String>.from(_conceptDraft!.exclusions)
        : null;
    _preModalFeatureLifecycles = {
      for (final d in documents.values.where((d) => d.tier == TierType.feature))
        d.id: d.sections['lifecycle'],
    };
    await advanceToNextRelease(
      transitionToGateStage: false,
      agentReasonedProgressive: true,
    );
    _currentStage = WorkbenchStage.releaseWorkbench;
    if (_releaseBlueprint == null ||
        _releaseBlueprint!.releaseDocId != _activeReleaseId) {
      notifyListeners();
      return null;
    }
    _initialProgressiveTrack0BlueprintJson =
        jsonEncode(_releaseBlueprint!.toJson());
    if (agentDirective != null && agentDirective.trim().isNotEmpty) {
      await sendReleasePlanChatMessage(agentDirective.trim());
    }
    notifyListeners();
    return _releaseBlueprint;
  }

  /// Restores the initial Option 0 (`(Recommended)`) draft `ReleaseBlueprint` when the user clicks
  /// back onto Option 0 after exploring Option 1 or Option 2 in the Progressive Release Co-Pilot.
  void restoreInitialProgressiveDraftBlueprint() {
    final raw = _initialProgressiveTrack0BlueprintJson;
    if (raw == null || raw.trim().isEmpty) return;
    try {
      final restored = ReleaseBlueprint.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
      _releaseBlueprint = restored;
      final proj = activeProject;
      if (proj != null) {
        if (_preModalFeatureInboxJson != null) {
          proj.sections['feature_inbox_json'] = _preModalFeatureInboxJson!;
        } else {
          proj.sections.remove('feature_inbox_json');
        }
        _cachedInboxRawHash = null;
        if (_preModalExclusions != null) {
          proj.sections['exclusions'] = _preModalExclusions!;
        } else {
          proj.sections.remove('exclusions');
        }
        _persistDocument(proj);
      }
      if (_conceptDraft != null && _preModalConceptExclusions != null) {
        _conceptDraft!.exclusions =
            List<String>.from(_preModalConceptExclusions!);
      }
      final preLifecycles = _preModalFeatureLifecycles;
      if (preLifecycles != null) {
        for (final entry in preLifecycles.entries) {
          final featDoc = documents[entry.key];
          if (featDoc == null) continue;
          if (entry.value != null) {
            featDoc.sections['lifecycle'] = entry.value!;
          } else {
            featDoc.sections.remove('lifecycle');
          }
          if (entry.value != FeatureLifecycleStatus.superseded.name) {
            featDoc.sections.remove('supersededInVersion');
          }
          _persistDocument(featDoc);
        }
      }
      final relDoc = activeRelease;
      if (relDoc != null && relDoc.id == restored.releaseDocId) {
        relDoc.sections['release_blueprint_json'] = raw;
        _persistDocument(relDoc);
      }
      _syncActiveProjectMetadata();
      notifyListeners();
    } catch (_) {}
  }

  static final RegExp _epicPrefixStripper = RegExp(
    r'^(?:epic\s*\d+|beat\s*\d+|e0?\d+)\s*[:·—\-]\s*',
    caseSensitive: false,
  );
  static final RegExp _leadingVerbStripper = RegExp(
    r'^(?:build|create|implement|add|upgrade|extend|configure|wire|setup|set up|enable|establish|allow|support)\s+(?:the|a|an)?\s*',
    caseSensitive: false,
  );
  static final RegExp _changelogInlineArticlesRegex = RegExp(
    r'\b(?:a|an|the|your|our)\s+',
    caseSensitive: false,
  );
  static final RegExp _changelogTrailingFillerRegex = RegExp(
    r'\s+(?:in\s+(?:the\s+)?(?:arena|scene|level|game|viewport)|for\s+(?:the\s+)?player|on\s+screen)$',
    caseSensitive: false,
  );

  String _shortBeatName(String rawTitle, int idx) {
    final cleaned = rawTitle.replaceFirst(_epicPrefixStripper, '').trim();
    return cleaned.isNotEmpty ? cleaned : 'Epic ${idx + 1}';
  }

  String _formatTelegraphicDeltaItem(String raw, {required bool isUpgrade}) {
    var cleaned = raw
        .trim()
        .replaceFirst(RegExp(r'^\+\s*'), '')
        .replaceFirst(_leadingVerbStripper, '')
        .replaceFirst(_changelogTrailingFillerRegex, '')
        .replaceAll(_changelogInlineArticlesRegex, '')
        .replaceAll(RegExp(r'\.$'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (cleaned.isEmpty) return '';
    cleaned = cleaned[0].toUpperCase() + cleaned.substring(1);
    return isUpgrade ? '+$cleaned' : cleaned;
  }

  /// Formats a feature's scope/goal into a concise **Telegraphic Changelog Delta (`+Delta`)** string for `UPGRADE`
  /// features or a clean telegraphic phrase for `NEW` features.
  String formatChangelogDeltaForFeature(ProposedFeatureBlueprint feat) {
    final isUpg = feat.lifecycle == FeatureLifecycleStatus.upgrade;
    final items = <String>[];
    for (final raw in feat.inScope) {
      final cleaned = _formatTelegraphicDeltaItem(raw, isUpgrade: isUpg);
      if (cleaned.isNotEmpty &&
          cleaned.replaceFirst('+', '').toLowerCase() !=
              feat.title.toLowerCase()) {
        items.add(cleaned);
      }
      if (items.length >= 2) break;
    }
    if (items.isNotEmpty) {
      return items.join(', ');
    }
    final cleanGoal = _formatTelegraphicDeltaItem(feat.goal, isUpgrade: isUpg);
    if (cleanGoal.isEmpty) {
      return isUpg ? '+MVP functional upgrade & tuning' : feat.title;
    }
    return cleanGoal;
  }

  /// Generates the 3 selectable **EPICS** option cards for the Progressive Release Co-Pilot
  /// directly from the remaining incomplete Epics (`E01..EN`), using:
  /// - **BLUF** card titles (`E02 + E03 · <Epic Titles>`)
  /// - **Telegraphic (`+`-joined)** card subtitles
  /// - **BLUF** `GOAL:` (`<Bold Payoff> — <Concise Epic Scope>`)
  /// - **Causal `Trigger → Result`** `✓ END GOAL:` (`<Action> → <Observable Screen Result>`)
  List<({
    String title,
    String subtitle,
    String blufHeadline,
    String blufDetail,
    String causalDoneWhen,
    List<int> targetBeatIndices,
    bool isRecommended,
  })> epicFocusOptionsForBlueprint(ReleaseBlueprint bp) {
    final totalBeats = bp.beats.length;
    if (totalBeats == 0) return const [];

    // Act 2 · v1.0 Launch Release: a single Launch Sweep card (no Epic slicing).
    if (documents[bp.releaseDocId]?.sections['launchRelease'] == 'true') {
      final hostIdx = bp.beats.indexWhere(
        (b) => b.features.any((f) => f.included && !f.isStable && !f.isSuperseded),
      );
      final openFixes = fullProductionCoverage().openFixCount;
      return [
        (
          title: 'v1.0 Launch Sweep',
          subtitle:
              'Release Build Export${openFixes > 0 ? ' + $openFixes open [FIX]' : ''}',
          blufHeadline: 'v1.0 Launch',
          blufDetail:
              'Export the standalone build and clear every open [FIX] task.',
          causalDoneWhen: bp.doneWhen,
          targetBeatIndices: <int>[if (hostIdx >= 0) hostIdx],
          isRecommended: true,
        ),
      ];
    }

    final phase = _currentPhase;
    final isVs = phase == ProductionPhase.verticalSlice;
    final isFp = phase == ProductionPhase.fullProduction;
    final mvpCov = mvpBeatCoverage();
    final vsCov = verticalSliceBeatCoverage();
    final fpCov = isFp ? fullProductionCoverage() : null;
    final incompleteCodes = (fpCov != null && !fpCov.isLegacy)
        ? fpCov.incompleteBeatCodes.toSet()
        : (isVs
            ? vsCov.incompleteBeatCodes.toSet()
            : mvpCov.incompleteBeatCodes.toSet());

    final incompleteIndices = <int>[];
    final initialActiveIndices = <int>[];
    for (int i = 0; i < totalBeats; i++) {
      final code = 'E${(i + 1).toString().padLeft(2, '0')}';
      if (incompleteCodes.contains(code)) {
        incompleteIndices.add(i);
      }
      final b = bp.beats[i];
      if (b.features.any((f) => f.included && !f.isStable && !f.isSuperseded)) {
        initialActiveIndices.add(i);
      }
    }

    final fpEpicIndices = <int>[
      if (fpCov != null && !fpCov.isLegacy)
        for (int i = 0; i < totalBeats; i++)
          if (documents[bp.beats[i].id]?.isFullProductionEpic ?? false) i,
    ];
    final availableIndices = incompleteIndices.isNotEmpty
        ? incompleteIndices
        : (fpEpicIndices.isNotEmpty
            ? fpEpicIndices
            : List<int>.generate(totalBeats, (i) => i));

    // Card 0 (Recommended): initial active incomplete Epics (or first 1-2 available incomplete Epics)
    final recIndices = initialActiveIndices.isNotEmpty
        ? initialActiveIndices
        : availableIndices.take(availableIndices.length >= 2 ? 2 : 1).toList();

    // Card 1: Focused single-Epic option on the first available incomplete Epic
    final firstSingleIdx = availableIndices.first;
    final opt1Indices = (recIndices.length == 1 &&
            recIndices.first == firstSingleIdx &&
            availableIndices.length >= 2)
        ? <int>[availableIndices[0], availableIndices[1]]
        : <int>[firstSingleIdx];

    // Card 2: Alternative incomplete Epic(s)
    List<int> opt2Indices;
    if (availableIndices.length >= 3) {
      opt2Indices = <int>[availableIndices[1], availableIndices[2]];
    } else if (availableIndices.length == 2) {
      opt2Indices = <int>[availableIndices[1]];
    } else if (totalBeats >= 2) {
      final otherIdx = (firstSingleIdx + 1) % totalBeats;
      opt2Indices = <int>[firstSingleIdx, otherIdx];
    } else {
      opt2Indices = <int>[0];
    }

    ({
      String title,
      String subtitle,
      String blufHeadline,
      String blufDetail,
      String causalDoneWhen,
      List<int> targetBeatIndices,
      bool isRecommended,
    }) buildCardConfig(
      List<int> indices, {
      required bool isRec,
      required bool forceSingleLabel,
    }) {
      final codes = [
        for (final i in indices) 'E${(i + 1).toString().padLeft(2, '0')}',
      ];
      final names = [
        for (final i in indices) _shortBeatName(bp.beats[i].title, i),
      ];
      final codePrefix = forceSingleLabel && codes.length == 1
          ? '${codes.first} Only'
          : codes.join(' + ');
      final joinedNames = names.take(2).join(' & ');
      final cardTitle = '$codePrefix · $joinedNames';

      final telegraphicTokens = <String>[];
      for (final i in indices) {
        for (final f in bp.beats[i].features) {
          if (f.isSuperseded) continue;
          telegraphicTokens.add(f.title);
          if (telegraphicTokens.length >= 3) break;
        }
        if (telegraphicTokens.length >= 3) break;
      }
      final subtitle = telegraphicTokens.isNotEmpty
          ? telegraphicTokens.join(' + ')
          : names.join(' + ');

      final phaseLabel = phase == ProductionPhase.verticalSlice
          ? 'Vertical Slice polish'
          : (phase == ProductionPhase.fullProduction
              ? 'Full Production'
              : 'MVP');
      final epicPairsText = [
        for (int k = 0; k < indices.length; k++) '${codes[k]} ${names[k]}',
      ].join(' and ');

      final blufHeadline = joinedNames;
      final blufDetail = 'Complete $epicPairsText for $phaseLabel.';

      final String causalDoneWhen;
      if (isRec && bp.doneWhen.trim().isNotEmpty && bp.doneWhen.contains('→')) {
        causalDoneWhen = bp.doneWhen.trim();
      } else if (telegraphicTokens.length >= 2) {
        causalDoneWhen =
            'Trigger ${telegraphicTokens.first} in Play mode → verify ${telegraphicTokens.skip(1).join(" + ")} on screen';
      } else {
        causalDoneWhen =
            'Playtest ${codes.join(" + ")} in Play mode → verify all $joinedNames mechanics respond without state locks';
      }

      return (
        title: cardTitle,
        subtitle: subtitle,
        blufHeadline: blufHeadline,
        blufDetail: blufDetail,
        causalDoneWhen: causalDoneWhen,
        targetBeatIndices: indices,
        isRecommended: isRec,
      );
    }

    return [
      buildCardConfig(
        recIndices,
        isRec: true,
        forceSingleLabel: false,
      ),
      buildCardConfig(
        opt1Indices,
        isRec: false,
        forceSingleLabel: opt1Indices.length == 1,
      ),
      buildCardConfig(
        opt2Indices,
        isRec: false,
        forceSingleLabel: opt2Indices.length == 1 && opt1Indices.length > 1,
      ),
    ];
  }

  /// Immediately switches the active whole Epics in `_releaseBlueprint` (`0ms`) when the user clicks
  /// one of the 3 Epic option cards in the Progressive Release Co-Pilot.
  void applyProgressiveEpicFocusOption(
    int optionIndex,
    List<int> targetBeatIndices,
  ) {
    if (optionIndex == 0) {
      restoreInitialProgressiveDraftBlueprint();
      return;
    }
    restoreInitialProgressiveDraftBlueprint();
    final bp = _releaseBlueprint;
    if (bp == null || bp.beats.isEmpty) return;

    final verTag = bp.releaseVersionTag;
    final targetSet = targetBeatIndices.toSet();
    final options = epicFocusOptionsForBlueprint(bp);
    final selectedOpt =
        (optionIndex >= 0 && optionIndex < options.length) ? options[optionIndex] : null;

    for (int bIdx = 0; bIdx < bp.beats.length; bIdx++) {
      final beat = bp.beats[bIdx];
      final isTarget = targetSet.contains(bIdx);
      for (final feat in beat.features) {
        if (feat.isSuperseded) continue;
        if (isTarget) {
          if (feat.lifecycle == FeatureLifecycleStatus.stable) {
            feat.lifecycle = FeatureLifecycleStatus.upgrade;
            feat.included = true;
            if (feat.estimatedHours <= 0) {
              feat.estimatedHours = 4;
            }
            if (feat.checkpoints.isEmpty) {
              feat.checkpoints = [
                ProposedCheckpointBlueprint(
                  title: '${feat.title} $verTag Upgrade',
                  playtestCriteria:
                      'Trigger ${feat.title} in Play mode → verify $verTag upgrade on screen',
                  tasks: [
                    '${feat.title} State Upgrade (2h)',
                    '${feat.title} Action & Feel Extension (1h)',
                    '${feat.title} Bounds & State Guard (1h)',
                  ],
                  coveredScope: feat.inScope.isNotEmpty
                      ? List<String>.from(feat.inScope)
                      : ['${feat.title} $verTag upgrade'],
                  tuningParams: List<String>.from(feat.tuningParams),
                  edgeCases: List<String>.from(feat.edgeCases),
                  releaseVersion: verTag,
                ),
              ];
            }
          } else {
            feat.included = true;
          }
        } else {
          if (feat.lifecycle == FeatureLifecycleStatus.upgrade) {
            feat.lifecycle = FeatureLifecycleStatus.stable;
            feat.estimatedHours = 0;
            feat.included = true;
          } else if (feat.lifecycle == FeatureLifecycleStatus.newFeature) {
            feat.included = false;
          }
        }
      }
    }

    if (selectedOpt != null) {
      bp.releaseTitle = '$verTag: ${selectedOpt.blufHeadline}';
      bp.goal = '${selectedOpt.blufHeadline} — ${selectedOpt.blufDetail}';
      bp.doneWhen = selectedOpt.causalDoneWhen;
      final relDoc = activeRelease;
      if (relDoc != null && relDoc.id == bp.releaseDocId) {
        relDoc.title = bp.releaseTitle;
        relDoc.sections['release_blueprint_json'] = jsonEncode(bp.toJson());
        _persistDocument(relDoc);
      }
    }
    _syncActiveProjectMetadata();
    notifyListeners();
  }

  /// Restores the active release, blueprint, and production phase if the user cancels (or fails offline in)
  /// the Progressive Next Release modal, and removes any newly created unbuilt draft release documents.
  void restoreActiveReleaseAfterCancel(
    String? previousReleaseId,
    ProductionPhase previousPhase,
  ) {
    _progressivePlanGeneration++;
    _isSynthesizingProgressiveFocus = false;
    _synthesizingProgressiveBeatId = null;
    _queuedProgressiveBeatIds.clear();
    final proj = activeProject;
    final preIds = _preModalReleaseIds;
    if (proj != null && preIds != null) {
      final addedUnbuiltIds = proj.childrenIds
          .where((id) {
            if (preIds.contains(id)) return false;
            final relDoc = documents[id];
            return relDoc != null && relDoc.childrenIds.isEmpty;
          })
          .toList();
      final user = _authService.currentUser;
      for (final id in addedUnbuiltIds) {
        proj.childrenIds.remove(id);
        documents.remove(id);
        LocalVaultService.deleteDocument(id);
        if (user != null) {
          _firestoreService.deleteDocument(uid: user.uid, docId: id);
        }
      }
    }
    if (proj != null) {
      if (_preModalFeatureInboxJson != null) {
        proj.sections['feature_inbox_json'] = _preModalFeatureInboxJson!;
      } else {
        proj.sections.remove('feature_inbox_json');
      }
      _cachedInboxRawHash = null;
      if (_preModalExclusions != null) {
        proj.sections['exclusions'] = _preModalExclusions!;
      } else {
        proj.sections.remove('exclusions');
      }
    }
    if (_conceptDraft != null && _preModalConceptExclusions != null) {
      _conceptDraft!.exclusions =
          List<String>.from(_preModalConceptExclusions!);
    }
    final preLifecycles = _preModalFeatureLifecycles;
    if (preLifecycles != null) {
      for (final entry in preLifecycles.entries) {
        final featDoc = documents[entry.key];
        if (featDoc == null) continue;
        if (entry.value != null) {
          featDoc.sections['lifecycle'] = entry.value!;
        } else {
          featDoc.sections.remove('lifecycle');
        }
        if (entry.value != FeatureLifecycleStatus.superseded.name) {
          featDoc.sections.remove('supersededInVersion');
        }
        _persistDocument(featDoc);
      }
    }
    if (_preModalReleaseBlueprint != null) {
      _releaseBlueprint = _preModalReleaseBlueprint;
    }
    _preModalReleaseIds = null;
    _preModalReleaseBlueprint = null;
    _preModalFeatureInboxJson = null;
    _preModalExclusions = null;
    _preModalConceptExclusions = null;
    _preModalFeatureLifecycles = null;
    if (previousReleaseId != null && documents.containsKey(previousReleaseId)) {
      _activeReleaseId = previousReleaseId;
    }
    if (proj != null) {
      repackProjectReleasesSequentially(
        proj,
        keepReleaseId: _activeReleaseId,
      );
    }
    _currentPhase = previousPhase;
    _syncActiveProjectMetadata();
    notifyListeners();
  }

  /// Executes the prepared (or newly synthesized) next Progressive Release (`v0.2`, `v0.3+`)
  /// directly into `2. Workbench`.
  Future<void> buildProgressiveNextRelease({String? agentDirective}) async {
    final currentBp = _releaseBlueprint;
    final activeRel = activeRelease;
    if (currentBp == null ||
        (activeRel != null &&
            currentBp.releaseDocId == activeRel.id &&
            activeRel.childrenIds.isNotEmpty)) {
      await prepareProgressiveNextReleaseDraft(agentDirective: agentDirective);
    } else if (agentDirective != null && agentDirective.trim().isNotEmpty) {
      await sendReleasePlanChatMessage(agentDirective.trim());
    }
    if (_releaseBlueprint != null) {
      await approveAndExecuteReleasePlan();
    }
  }

  /// Synthesizes the Release Blueprint for the active Release.
  Future<void> openReleasePlanGate({
    String? releaseId,
    bool transitionToGateStage = false,
  }) async {
    if (releaseId != null) {
      _activeReleaseId = releaseId;
    }
    final existingProj = activeProject;
    if (_conceptDraft != null &&
        (existingProj == null || existingProj.childrenIds.isEmpty)) {
      _commitConceptToVault(_conceptDraft!, syncBuiltWorkbench: false);
    }

    final proj = activeProject;
    if (proj == null) return;

    final targetRelId = releaseId ??
        _activeReleaseId ??
        (proj.childrenIds.isNotEmpty ? proj.childrenIds.first : null);
    if (targetRelId == null) return;
    _activeReleaseId = targetRelId;

    // Collect existing live Beats & Features from prior releases (never from targetRelId itself,
    // and never when planning the initial v0.1 release) so v0.1 starts clean at 0% and v0.2+ preserves the single live game tree!
    final isFirstPrototypeRelease =
        proj.childrenIds.isEmpty || proj.childrenIds.first == targetRelId;
    final existingBeats = <TierDocument>[];
    final existingFeaturesByBeat = <String, List<TierDocument>>{};
    if (!isFirstPrototypeRelease) {
      for (final rel in projectReleases) {
        if (rel.id == targetRelId) continue;
        if (rel.childrenIds.isNotEmpty) {
          for (final beatId in rel.childrenIds) {
            final bDoc = documents[beatId];
            if (bDoc != null && !existingBeats.any((b) => b.id == bDoc.id)) {
              existingBeats.add(bDoc);
              existingFeaturesByBeat[bDoc.id] = featuresForBeat(
                bDoc.id,
                includeSuperseded: true,
              );
            }
          }
        }
      }
    }

    // Capture any features deferred (unchecked) across all prior Release Plan Gates (not yet built)
    // so they automatically carry over into the next release's Beat, and archive the prior ReleaseBlueprint on its own Release doc!
    final deferredByBeatIndex = <int, List<ProposedFeatureBlueprint>>{};
    final priorBp = _releaseBlueprint;
    if (priorBp != null) {
      final priorRelDoc = documents[priorBp.releaseDocId];
      if (priorRelDoc != null) {
        priorRelDoc.sections['release_blueprint_json'] =
            _encodeCompactArchivedReleaseBlueprint(priorBp);
        _persistDocument(priorRelDoc);
      }
    }
    final builtFeatureTitleSet = <String>{
      for (final featList in existingFeaturesByBeat.values)
        for (final ef in featList) ef.title.toLowerCase().trim(),
    };
    final priorBlueprintsToScan = <ReleaseBlueprint>[
      for (final rel in projectReleases)
        if (rel.id != targetRelId && rel.childrenIds.isNotEmpty)
          if (releaseBlueprintFor(rel.id) != null) releaseBlueprintFor(rel.id)!,
      if (priorBp != null && priorBp.releaseDocId != targetRelId) priorBp,
    ];
    final seenDeferredByBeat = <int, Set<String>>{};
    for (final scannedBp in priorBlueprintsToScan) {
      for (int bIdx = 0; bIdx < scannedBp.beats.length; bIdx++) {
        final seenTitles = seenDeferredByBeat.putIfAbsent(bIdx, () => <String>{});
        final deferredInBeat = deferredByBeatIndex.putIfAbsent(
          bIdx,
          () => <ProposedFeatureBlueprint>[],
        );
        for (final df in scannedBp.beats[bIdx].deferredFeatures) {
          final normTitle = df.title.toLowerCase().trim();
          if (normTitle.isNotEmpty &&
              !builtFeatureTitleSet.contains(normTitle) &&
              seenTitles.add(normTitle)) {
            deferredInBeat.add(df);
          }
        }
      }
    }
    deferredByBeatIndex.removeWhere((_, list) => list.isEmpty);

    _activeReleaseId = targetRelId;
    final relDoc = documents[targetRelId];
    if (relDoc == null) return;
    _syncCurrentPhaseFromRelease(relDoc);

    _stepQueueGeneration++;
    _progressivePlanGeneration++;
    final int planGeneration = _progressivePlanGeneration;
    _pendingFeatureStepQueue.clear();
    final verTag = releaseVersionTagFor(relDoc);
    relDoc.sections['versionTag'] = verTag;

    // Fast Path 0: `v1.0` Launch Release is deterministic (no AI call): STABLE tree + Release Build Export.
    if (relDoc.sections['launchRelease'] == 'true' && existingBeats.isNotEmpty) {
      final launchBp = _buildLaunchReleaseBlueprint(relDoc, verTag, existingBeats);
      if (launchBp != null) {
        relDoc.title = launchBp.releaseTitle;
        relDoc.sections['release_blueprint_json'] = jsonEncode(launchBp.toJson());
        _persistDocument(relDoc);
        _releaseBlueprint = launchBp;
        _offlineErrorMessage = null;
        if (transitionToGateStage) {
          _currentStage = WorkbenchStage.releaseWorkbench;
        }
        _syncActiveProjectMetadata();
        notifyListeners();
        return;
      }
    }

    _releaseBlueprint = null;
    _isAgentBusy = true;
    final displayPlanModel = _planningModel;
    _agentProgressStep =
        'Synthesizing $verTag Release Architecture ($displayPlanModel)...';

    // Step 0 (`0ms` Live-Tree Skeleton): When opening a Progressive Release (`v0.2+`) in live mode,
    // immediately populate `_releaseBlueprint` with the existing `E01..EN` Epics and `STABLE` features
    // so the 3-Step Progressive Release canvas opens in `0ms` while Section 1 and Section 2 stream in.
    if (!isFirstPrototypeRelease &&
        existingBeats.isNotEmpty &&
        GeminiAgentClient.hasKey(_apiKey) &&
        GeminiAgentClient.testMockResponder == null) {
      final skeletonBp =
          ReleasePlannerAgent.buildProgressiveLiveTreeSkeletonBlueprint(
        projectDoc: proj,
        releaseDoc: relDoc,
        existingBeats: existingBeats,
        existingFeaturesByBeat: existingFeaturesByBeat,
        deferredByBeatIndex: deferredByBeatIndex,
      );
      if (skeletonBp != null) {
        _injectDueScheduledInboxItemsIntoBlueprint(skeletonBp, _currentPhase);
        _releaseBlueprint = skeletonBp;
        _isSynthesizingProgressiveFocus = false;
        _synthesizingProgressiveBeatId = null;
        _queuedProgressiveBeatIds.clear();
        final initialCards = epicFocusOptionsForBlueprint(skeletonBp);
        final initialRec = initialCards.isNotEmpty ? initialCards.first : null;
        final rawTargetEpicIdx = relDoc.sections['targetEpicIndex'];
        final isAgentReasoned = relDoc.sections['agentReasoned'] == 'true';
        final explicitIdx = !isAgentReasoned && rawTargetEpicIdx != null
            ? int.tryParse(rawTargetEpicIdx)
            : null;
        final initialTargetIndices = (explicitIdx != null &&
                explicitIdx >= 0 &&
                explicitIdx < existingBeats.length)
            ? <int>[explicitIdx]
            : (initialRec != null && initialRec.targetBeatIndices.isNotEmpty
                ? initialRec.targetBeatIndices
                : <int>[0]);
        for (final idx in initialTargetIndices) {
          if (idx >= 0 && idx < skeletonBp.beats.length) {
            _queuedProgressiveBeatIds.add(skeletonBp.beats[idx].id);
          }
        }
        _agentProgressStep = 'Planning $verTag Epic upgrades…';
      }
    }
    notifyListeners();

    try {
      final completedPriorReleases = projectReleases
          .where((r) => r.id != targetRelId && r.childrenIds.isNotEmpty)
          .toList();
      final ReleaseBlueprint? planned;
      if (!isFirstPrototypeRelease &&
          existingBeats.isNotEmpty &&
          GeminiAgentClient.testMockResponder == null) {
        planned = await planProgressiveReleaseSectionBySection(
          projectDoc: proj,
          releaseDoc: relDoc,
          completedReleases: completedPriorReleases,
          existingBeats: existingBeats,
          existingFeaturesByBeat: existingFeaturesByBeat,
          deferredByBeatIndex: deferredByBeatIndex,
          generation: planGeneration,
        );
      } else {
        planned = await ReleasePlannerAgent.planRelease(
          projectDoc: proj,
          releaseDoc: relDoc,
          completedReleases: completedPriorReleases,
          existingBeats: existingBeats,
          existingFeaturesByBeat: existingFeaturesByBeat,
          deferredByBeatIndex: deferredByBeatIndex,
          apiKey: _apiKey,
          modelName: _planningModel,
          thinkingLevel: _thinkingLevel,
        );
      }
      if (planGeneration != _progressivePlanGeneration) return;
      if (planned != null) {
        if (planned.releaseTitle.isNotEmpty &&
            planned.releaseTitle != relDoc.title) {
          relDoc.title = planned.releaseTitle;
        }
        relDoc.sections.remove('used_baseline_fallback');
        relDoc.sections['versionTag'] = verTag;
        _syncCurrentPhaseFromRelease(relDoc);
        if (!isFirstPrototypeRelease) {
          _injectDueScheduledInboxItemsIntoBlueprint(planned, _currentPhase);
        }
        relDoc.sections['release_blueprint_json'] =
            jsonEncode(planned.toJson());
        _persistDocument(relDoc);
        _releaseBlueprint = planned;
        _offlineErrorMessage = null;
        if (transitionToGateStage) {
          _currentStage = WorkbenchStage.releaseWorkbench;
        }
        _syncActiveProjectMetadata();
      } else {
        _releaseBlueprint = null;
        if (!isFirstPrototypeRelease && existingBeats.isNotEmpty) {
          final fallbackProgressive =
              ReleasePlannerAgent.buildImmediateProgressiveBaselineBlueprint(
            projectDoc: proj,
            releaseDoc: relDoc,
            existingBeats: existingBeats,
            existingFeaturesByBeat: existingFeaturesByBeat,
            deferredByBeatIndex: deferredByBeatIndex,
          );
          if (fallbackProgressive != null) {
            _injectDueScheduledInboxItemsIntoBlueprint(
              fallbackProgressive,
              _currentPhase,
            );
            relDoc.sections['used_baseline_fallback'] = 'true';
            relDoc.sections['release_blueprint_json'] =
                jsonEncode(fallbackProgressive.toJson());
            _persistDocument(relDoc);
            _releaseBlueprint = fallbackProgressive;
            _syncActiveProjectMetadata();
          }
        } else if (isFirstPrototypeRelease &&
            GeminiAgentClient.hasKey(_apiKey)) {
          final fallbackInitial =
              ReleasePlannerAgent.buildImmediateInitialBaselineBlueprint(
            projectDoc: proj,
            releaseDoc: relDoc,
          );
          if (fallbackInitial != null) {
            relDoc.sections['used_baseline_fallback'] = 'true';
            relDoc.sections['versionTag'] = verTag;
            relDoc.sections['release_blueprint_json'] =
                jsonEncode(fallbackInitial.toJson());
            _persistDocument(relDoc);
            _releaseBlueprint = fallbackInitial;
            _syncActiveProjectMetadata();
          }
        }
        if (_releaseBlueprint == null) {
          _setOfflineState();
        }
      }
    } finally {
      if (planGeneration == _progressivePlanGeneration) {
        _isSynthesizingProgressiveFocus = false;
        _synthesizingProgressiveBeatId = null;
        _queuedProgressiveBeatIds.clear();
        _isAgentBusy = false;
        _agentProgressStep = null;
        notifyListeners();
      }
    }
  }

  /// Section-by-Section Progressive Release Orchestrator (`Step 0: 0ms Live-Tree Skeleton & Deterministic Section 1` ->
  /// `Pass 2: Section 2 Target Epics One-by-One`).
  Future<ReleaseBlueprint?> planProgressiveReleaseSectionBySection({
    required TierDocument projectDoc,
    required TierDocument releaseDoc,
    required List<TierDocument> completedReleases,
    required List<TierDocument> existingBeats,
    required Map<String, List<TierDocument>> existingFeaturesByBeat,
    required Map<int, List<ProposedFeatureBlueprint>> deferredByBeatIndex,
    bool isBackgroundPrewarm = false,
    int? generation,
  }) async {
    if (!GeminiAgentClient.hasKey(_apiKey) || existingBeats.isEmpty) {
      return null;
    }
    bool isCancelled() =>
        !isBackgroundPrewarm &&
        generation != null &&
        generation != _progressivePlanGeneration;
    final verTag = releaseVersionTagFor(releaseDoc);
    final workingBp = (!isBackgroundPrewarm &&
            _releaseBlueprint != null &&
            _releaseBlueprint!.releaseDocId == releaseDoc.id)
        ? _releaseBlueprint!
        : ReleasePlannerAgent.buildProgressiveLiveTreeSkeletonBlueprint(
            projectDoc: projectDoc,
            releaseDoc: releaseDoc,
            existingBeats: existingBeats,
            existingFeaturesByBeat: existingFeaturesByBeat,
            deferredByBeatIndex: deferredByBeatIndex,
          );
    if (workingBp == null) return null;

    // Pass 1 (0ms Deterministic Section 1): Seed `1. Choose v0.X Focus`, `GOAL`, `END GOAL`, & 3 Epic Option Cards
    final epicCards = epicFocusOptionsForBlueprint(workingBp);
    final recCard = epicCards.isNotEmpty ? epicCards.first : null;
    final rawTargetEpicIdx = releaseDoc.sections['targetEpicIndex'];
    final isAgentReasoned = releaseDoc.sections['agentReasoned'] == 'true';
    final explicitIdx = !isAgentReasoned && rawTargetEpicIdx != null
        ? int.tryParse(rawTargetEpicIdx)
        : null;
    final targetEpicIndices = (explicitIdx != null &&
            explicitIdx >= 0 &&
            explicitIdx < existingBeats.length)
        ? <int>[explicitIdx]
        : (recCard != null && recCard.targetBeatIndices.isNotEmpty
            ? recCard.targetBeatIndices
            : <int>[0]);

    if (recCard != null) {
      workingBp.releaseTitle = '$verTag: ${recCard.blufHeadline}';
      releaseDoc.title = workingBp.releaseTitle;
      workingBp.goal = '${recCard.blufHeadline} — ${recCard.blufDetail}';
      workingBp.doneWhen = recCard.causalDoneWhen;
      workingBp.questions = [
        AgentQuestion(
          id: 'rel_q_1',
          question: 'Which available Epics should $verTag build?',
          options: [
            for (final c in epicCards)
              '${c.isRecommended ? "(Recommended) " : ""}${c.title}: ${c.subtitle}',
          ],
        ),
      ];
    }
    workingBp.missingGaps = [
      for (final idx in targetEpicIndices)
        if (idx >= 0 && idx < existingBeats.length)
          'E${(idx + 1).toString().padLeft(2, '0')}: Complete ${existingBeats[idx].title} for ${_currentPhase.shortName}',
    ];

    if (!isBackgroundPrewarm) {
      _releaseBlueprint = workingBp;
      _isSynthesizingProgressiveFocus = false;
      _synthesizingProgressiveBeatId = null;
      _queuedProgressiveBeatIds.clear();
      for (final idx in targetEpicIndices) {
        if (idx >= 0 && idx < workingBp.beats.length) {
          _queuedProgressiveBeatIds.add(workingBp.beats[idx].id);
        }
      }
      notifyListeners();
    }

    // Pass 2 (Epic-by-Epic): Synthesize Section 2 (`2. Epics & Features in v0.X`) one target Epic at a time
    final alreadyPlannedChanges = <String>[];
    for (final bIdx in targetEpicIndices) {
      if (isCancelled()) return null;
      if (bIdx < 0 ||
          bIdx >= existingBeats.length ||
          bIdx >= workingBp.beats.length) {
        continue;
      }
      final eb = existingBeats[bIdx];
      final eCode = 'E${(bIdx + 1).toString().padLeft(2, '0')}';
      if (!isBackgroundPrewarm) {
        _queuedProgressiveBeatIds.remove(eb.id);
        _synthesizingProgressiveBeatId = eb.id;
        _agentProgressStep = 'Synthesizing $eCode (${eb.title}) upgrades…';
        notifyListeners();
      }

      final updatedBeat = await ReleasePlannerAgent.planProgressiveEpicChanges(
        projectDoc: projectDoc,
        releaseDoc: releaseDoc,
        epicDoc: eb,
        epicIndex: bIdx,
        totalEpicsCount: existingBeats.length,
        existingFeaturesInEpic:
            existingFeaturesByBeat[eb.id] ?? const <TierDocument>[],
        queuedDeferredInEpic:
            deferredByBeatIndex[bIdx] ?? const <ProposedFeatureBlueprint>[],
        section1Goal: workingBp.goal,
        section1DoneWhen: workingBp.doneWhen,
        missingGaps: workingBp.missingGaps,
        alreadyPlannedChanges: alreadyPlannedChanges,
        apiKey: _apiKey,
        modelName: _conversationModel,
        thinkingLevel: 'LOW',
      );
      if (isCancelled()) return null;
      if (updatedBeat != null) {
        workingBp.beats[bIdx] = updatedBeat;
        for (final f in updatedBeat.features) {
          if (!f.isStable && !f.isSuperseded) {
            alreadyPlannedChanges.add(f.title);
          }
        }
        if (!isBackgroundPrewarm) {
          _injectDueScheduledInboxItemsIntoBlueprint(workingBp, _currentPhase);
          notifyListeners();
        }
      }
    }

    if (!isBackgroundPrewarm) {
      _synthesizingProgressiveBeatId = null;
      _queuedProgressiveBeatIds.clear();
    }

    final hasAnyActiveChange = workingBp.beats.any(
      (b) => b.features.any((f) => !f.isStable && !f.isSuperseded),
    );
    if (!hasAnyActiveChange) return null;
    final refreshedCards = epicFocusOptionsForBlueprint(workingBp);
    if (refreshedCards.isNotEmpty) {
      final refreshedRec = refreshedCards.first;
      workingBp.goal =
          '${refreshedRec.blufHeadline} — ${refreshedRec.blufDetail}';
      workingBp.doneWhen = refreshedRec.causalDoneWhen;
    }
    return workingBp;
  }

  /// Sends a user turn in the Stage 2 Release Plan Gate Chat to refine Beats, Features, or Scope.
  Future<void> sendReleasePlanChatMessage(String message) async {
    final bp = _releaseBlueprint;
    if (bp == null || message.trim().isEmpty) return;

    _isAgentBusy = true;
    _agentProgressStep =
        'Refining Release Plan ($_conversationModel)...';
    notifyListeners();

    try {
      final ok = await ReleasePlannerAgent.sendReleasePlanChatTurn(
        blueprint: bp,
        userMessage: message,
        projectDoc: activeProject,
        apiKey: _apiKey,
        modelName: _conversationModel,
        thinkingLevel: _thinkingLevel,
      );
      if (ok) {
        _injectDueScheduledInboxItemsIntoBlueprint(bp, _currentPhase);
        final relDoc = activeRelease;
        if (relDoc != null) {
          if (bp.releaseTitle.trim().isNotEmpty &&
              bp.releaseTitle != relDoc.title) {
            relDoc.title = bp.releaseTitle;
          }
          relDoc.sections['release_blueprint_json'] = jsonEncode(bp.toJson());
          _persistDocument(relDoc);
        }
        _offlineErrorMessage = null;
        _syncActiveProjectMetadata();
      } else {
        _setOfflineState();
      }
    } finally {
      _isAgentBusy = false;
      _agentProgressStep = null;
      notifyListeners();
    }
  }

  /// Toggles whether a proposed Feature in the Release Plan Gate is kept in scope or deferred to Out of Scope.
  void toggleProposedFeatureScope(
    String beatId,
    String featureId,
    bool included,
  ) {
    final bp = _releaseBlueprint;
    if (bp == null) return;
    for (final beat in bp.beats) {
      if (beat.id == beatId) {
        for (final feat in beat.features) {
          if (feat.id == featureId) {
            feat.included = included;
            _syncActiveProjectMetadata();
            notifyListeners();
            return;
          }
        }
      }
    }
  }

  /// Toggles an existing Feature in the Progressive Release Planner between `UPGRADE` (`+4h` delta checkpoint)
  /// and `STABLE ✓` (`0h`, locked at 100%).
  void toggleProposedFeatureUpgradeOrStable(
    String beatId,
    String featureId,
  ) {
    final bp = _releaseBlueprint;
    if (bp == null) return;
    final verTag = bp.releaseVersionTag;
    for (final beat in bp.beats) {
      if (beat.id == beatId) {
        for (final feat in beat.features) {
          if (feat.id == featureId) {
            if (feat.lifecycle == FeatureLifecycleStatus.upgrade) {
              feat.lifecycle = FeatureLifecycleStatus.stable;
              feat.estimatedHours = 0;
              feat.included = true;
            } else {
              feat.lifecycle = FeatureLifecycleStatus.upgrade;
              feat.included = true;
              if (feat.estimatedHours <= 0) {
                feat.estimatedHours = 4;
              }
              if (feat.checkpoints.isEmpty) {
                feat.checkpoints = [
                  ProposedCheckpointBlueprint(
                    title: '${feat.title} $verTag Upgrade',
                    playtestCriteria:
                        'Trigger ${feat.title} in playtest -> verify $verTag upgrade and polish',
                    tasks: [
                      'Component & State Upgrade (2h)',
                      'Logic & Feel Extension (1h)',
                      'State & Bounds Guard (1h)',
                    ],
                    coveredScope: feat.inScope.isNotEmpty
                        ? List<String>.from(feat.inScope)
                        : ['${feat.title} $verTag upgrade'],
                    tuningParams: List<String>.from(feat.tuningParams),
                    edgeCases: List<String>.from(feat.edgeCases),
                    releaseVersion: verTag,
                  ),
                ];
              }
            }
            _syncActiveProjectMetadata();
            notifyListeners();
            return;
          }
        }
      }
    }
  }

  /// Toggles an existing Feature in the Progressive Release Planner between `SUPERSEDED` (archived testbed)
  /// and `STABLE ✓` / `UPGRADE`.
  void toggleProposedFeatureSuperseded(
    String beatId,
    String featureId,
  ) {
    final bp = _releaseBlueprint;
    if (bp == null) return;
    for (final beat in bp.beats) {
      if (beat.id == beatId) {
        for (final feat in beat.features) {
          if (feat.id == featureId) {
            if (feat.lifecycle == FeatureLifecycleStatus.superseded) {
              feat.lifecycle = FeatureLifecycleStatus.stable;
              feat.included = true;
              feat.estimatedHours = 0;
            } else {
              feat.lifecycle = FeatureLifecycleStatus.superseded;
              feat.included = false;
              feat.estimatedHours = 0;
            }
            // Sync live document if already built
            final liveDoc = documents[featureId];
            if (liveDoc != null && liveDoc.tier == TierType.feature) {
              liveDoc.sections['lifecycle'] = feat.lifecycle.name;
              if (feat.lifecycle == FeatureLifecycleStatus.superseded) {
                liveDoc.sections['supersededInVersion'] = bp.releaseVersionTag;
              } else {
                liveDoc.sections.remove('supersededInVersion');
              }
              _persistDocument(liveDoc);
            }
            _syncActiveProjectMetadata();
            notifyListeners();
            return;
          }
        }
      }
    }
  }

  /// 1-Click Feature Pivot / Supersede (`01 Prototype` -> `02 MVP`+):
  /// Archives a live Feature into `Superseded Testbeds Archive` (`FeatureLifecycleStatus.superseded`)
  /// when a playtest proves the mechanic should be cut/pivoted, or restores an archived Feature back into active scope.
  bool toggleSupersedeFeature(
    String featureId, {
    String? pivotReason,
  }) {
    final featDoc = documents[featureId];
    if (featDoc == null || featDoc.tier != TierType.feature) return false;
    final activeVer = activeReleaseVersionTag;
    final wasSuperseded =
        featDoc.sections['lifecycle'] == FeatureLifecycleStatus.superseded.name;

    if (wasSuperseded) {
      final originVer = (featDoc.sections['originVersion'] ?? activeVer).trim();
      final restoredLifecycle = originVer == activeVer
          ? FeatureLifecycleStatus.newFeature
          : FeatureLifecycleStatus.upgrade;
      featDoc.sections['lifecycle'] = restoredLifecycle.name;
      featDoc.sections['activeReleaseVersion'] = activeVer;
      featDoc.sections.remove('supersededInVersion');
      featDoc.sections.remove('pivotReason');
      featDoc.sections.remove('pivot_reason');
      _persistDocument(featDoc);

      final parentBeatId = featDoc.parentId;
      if (parentBeatId != null) {
        final beatDoc = documents[parentBeatId];
        if (beatDoc != null && !beatDoc.childrenIds.contains(featureId)) {
          beatDoc.childrenIds.add(featureId);
          _persistDocument(beatDoc);
        }
      }

      final bp = _releaseBlueprint;
      if (bp != null) {
        for (final b in bp.beats) {
          for (final f in b.features) {
            if (f.id == featureId ||
                f.title.toLowerCase().trim() ==
                    featDoc.title.toLowerCase().trim()) {
              f.lifecycle = restoredLifecycle;
              f.included = true;
              if (f.estimatedHours <= 0) f.estimatedHours = 4;
            }
          }
        }
      }

      if (_releaseViewFilter == 'archived' && supersededFeatures.isEmpty) {
        _releaseViewFilter = 'active';
        _selectedFeatureId = featureId;
        if (featDoc.parentId != null) {
          _selectedBeatId = featDoc.parentId;
        }
      }
    } else {
      featDoc.sections['lifecycle'] = FeatureLifecycleStatus.superseded.name;
      featDoc.sections['supersededInVersion'] = activeVer;
      if (pivotReason != null && pivotReason.trim().isNotEmpty) {
        final cleanReason = pivotReason.trim();
        featDoc.sections['pivotReason'] = cleanReason;
        featDoc.sections['pivot_reason'] = cleanReason;
      }
      _persistDocument(featDoc);

      final bp = _releaseBlueprint;
      if (bp != null) {
        for (final b in bp.beats) {
          for (final f in b.features) {
            if (f.id == featureId ||
                f.title.toLowerCase().trim() ==
                    featDoc.title.toLowerCase().trim()) {
              f.lifecycle = FeatureLifecycleStatus.superseded;
              f.included = false;
              f.estimatedHours = 0;
            }
          }
        }
      }

      if (_selectedFeatureId == featureId && _releaseViewFilter != 'archived') {
        _selectFirstIncompleteFeatureInActiveRelease();
      }
    }

    _syncActiveProjectMetadata();
    notifyListeners();
    return !wasSuperseded;
  }

  /// Adds a custom `+ NEW` feature to a Beat inside the Progressive Release Planner (`_releaseBlueprint`).
  ProposedFeatureBlueprint? addCustomFeatureToProposedBeat(
    String beatId,
    String rawTitle, {
    String? customGoal,
  }) {
    final bp = _releaseBlueprint;
    final cleanTitle = rawTitle.replaceFirst(_noPrefixRegex, '').trim();
    if (bp == null || cleanTitle.isEmpty) return null;
    final verTag = bp.releaseVersionTag;
    for (int bIdx = 0; bIdx < bp.beats.length; bIdx++) {
      final beat = bp.beats[bIdx];
      if (beat.id == beatId) {
        final newFeatId =
            'feat_${verTag}_${bIdx + 1}_${beat.features.length + 1}';
        final goalText = (customGoal != null && customGoal.trim().isNotEmpty)
            ? customGoal.trim()
            : 'Build $cleanTitle inside ${beat.title} for $verTag.';
        final created = ProposedFeatureBlueprint(
          id: newFeatId,
          title: cleanTitle,
          goal: goalText,
          doneWhen: 'Playtester verifies $cleanTitle in the arena.',
          estimatedHours: 4,
          included: true,
          lifecycle: FeatureLifecycleStatus.newFeature,
          originVersion: verTag,
          inScope: ['$cleanTitle core setup & feedback'],
          outOfScope: const [],
          tuningParams: const ['responseWindowSec: 0.25 s'],
          edgeCases: const ['[STATE GUARD] Prevent duplicate trigger while active'],
          checkpoints: [
            ProposedCheckpointBlueprint(
              title: '$cleanTitle Core',
              playtestCriteria:
                  'Trigger $cleanTitle in playtest -> responds cleanly on screen',
              tasks: const [
                'Actor & Component Setup (2h)',
                'Input & Core Logic (1h)',
                'State & Cooldown Guard (1h)',
              ],
              coveredScope: ['$cleanTitle core setup & feedback'],
              tuningParams: const ['responseWindowSec: 0.25 s'],
              edgeCases: const [
                '[STATE GUARD] Prevent duplicate trigger while active',
              ],
              releaseVersion: verTag,
            ),
          ],
        );
        beat.features.add(created);
        _syncActiveProjectMetadata();
        notifyListeners();
        if (GeminiAgentClient.hasKey(_apiKey) ||
            GeminiAgentClient.testMockResponder != null) {
          _enrichProposedBlueprintFeatureWithAi(
            beatId: beat.id,
            featureId: created.id,
            beatTitle: beat.title,
            preserveCustomGoal:
                customGoal != null && customGoal.trim().isNotEmpty,
          );
        }
        return created;
      }
    }
    return null;
  }

  /// Builds a DRY, pre-formatted compact project spec context block (Game Spec, Tech Spec,
  /// 2D/3D Dimension Rule, Design Pillars, and Trade-Offs) shared across all Stage 2 Workbench AI tools.
  String _buildCompactWorkbenchSpecContext({
    bool singleLineProjectSpecsHeader = false,
    bool includeFullDimensionBanner = false,
    bool includeExclusions = false,
    String? targetEngineMode,
  }) {
    final proj = activeProject;
    final draft = _conceptDraft;
    final engineLabel = _activeEngineLabel;
    final gameSpec = (proj?.sections['game_spec'] ??
            proj?.sections['gameSpec'] ??
            draft?.gameSpec.join(' · ') ??
            '')
        .trim();
    final techSpec = (proj?.sections['tech_spec'] ??
            proj?.sections['techSpec'] ??
            draft?.techSpec.join(' · ') ??
            '')
        .trim();
    final pillars = (proj?.sections['design_pillars'] ??
            proj?.sections['designPillars'] ??
            draft?.designPillars.join(' | ') ??
            '')
        .replaceAll('\n', ' | ')
        .trim();
    final tradeOffs = (proj?.sections['trade_offs'] ??
            proj?.sections['tradeOffs'] ??
            draft?.tradeOffs.join(' | ') ??
            '')
        .replaceAll('\n', ' | ')
        .trim();
    final exclusions = (proj?.sections['exclusions'] ??
            draft?.exclusions.join(' | ') ??
            'None')
        .replaceAll('\n', ' | ')
        .trim();
    final specCorpusLower = '$gameSpec $techSpec'.toLowerCase();
    final is2d = specCorpusLower.contains('2d') ||
        specCorpusLower.contains('sprite') ||
        specCorpusLower.contains('pixel') ||
        specCorpusLower.contains('tilemap') ||
        (specCorpusLower.contains('top-down') &&
            !specCorpusLower.contains('3d')) ||
        (specCorpusLower.contains('side-scroll') &&
            !specCorpusLower.contains('3d'));

    if (includeFullDimensionBanner) {
      final modeLabel = targetEngineMode ?? engineLabel;
      final projectGoal = (proj != null
              ? SectionTextUtils.resolveGoal(proj.sections)
              : (draft?.goal ?? ''))
          .trim();
      final lines = <String>[
        if (projectGoal.isNotEmpty) 'Project Goal: "$projectGoal"',
        if (pillars.isNotEmpty) 'Design Pillars: $pillars',
        if (tradeOffs.isNotEmpty) 'Trade-Offs: $tradeOffs',
        is2d
            ? 'PROJECT DIMENSION & CAMERA SPEC: 2D GAME ($gameSpec | $techSpec)\n'
                '- STRICT 2D ENGINE NODE RULE: Use ONLY 2D scenes/nodes/Vector2 (Node2D, CharacterBody2D, Area2D, Sprite2D, CollisionShape2D; or Unity Rigidbody2D, Collider2D, SpriteRenderer). NEVER use 3D nodes or Vector3!'
            : 'PROJECT DIMENSION & CAMERA SPEC: 3D GAME ($gameSpec | $techSpec)\n'
                '- Use 3D actors/nodes/components and Vector3/FVector math matching $modeLabel.',
      ];
      return lines.join('\n');
    }

    if (singleLineProjectSpecsHeader) {
      final specLine = [
        if (gameSpec.isNotEmpty) 'Game Spec: $gameSpec',
        if (techSpec.isNotEmpty) 'Tech Spec: $techSpec',
        if (pillars.isNotEmpty) 'Design Pillars: $pillars',
        if (tradeOffs.isNotEmpty) 'Trade-Offs: $tradeOffs',
      ].join(' | ');
      final dimLine = is2d
          ? 'Dimension Rule: 2D ONLY (CharacterBody2D/Area2D/Sprite2D/Rigidbody2D/Vector2; NEVER 3D nodes or Vector3).\n'
          : (specLine.isNotEmpty
              ? 'Dimension Rule: 3D ($engineLabel 3D actors/nodes/Vector3).\n'
              : '');
      return '${specLine.isNotEmpty ? 'Project Specs (match exact 2D/3D classes and camera): $specLine\n' : ''}$dimLine';
    }

    final dimLine = is2d
        ? 'Dimension Rule: 2D ONLY (2D scenes/nodes/colliders/Vector2; NEVER 3D nodes or Vector3).\n'
        : (gameSpec.isNotEmpty || techSpec.isNotEmpty
            ? 'Dimension Rule: 3D ($engineLabel 3D actors/nodes/Vector3).\n'
            : '');
    final sb = StringBuffer();
    if (gameSpec.isNotEmpty) sb.writeln('Game Spec: $gameSpec');
    if (techSpec.isNotEmpty) sb.writeln('Tech Spec: $techSpec');
    sb.write(dimLine);
    if (pillars.isNotEmpty) sb.writeln('Design Pillars: $pillars');
    if (tradeOffs.isNotEmpty) sb.writeln('Trade-Offs: $tradeOffs');
    if (includeExclusions) sb.writeln('Out of Scope Rules: $exclusions');
    return sb.toString();
  }

  Future<void> _enrichProposedBlueprintFeatureWithAi({
    required String beatId,
    required String featureId,
    required String beatTitle,
    required bool preserveCustomGoal,
  }) async {
    final bp = _releaseBlueprint;
    if (bp == null) return;
    ProposedBeatBlueprint? targetBeat;
    ProposedFeatureBlueprint? targetFeat;
    for (final b in bp.beats) {
      if (b.id == beatId) {
        for (final f in b.features) {
          if (f.id == featureId) {
            targetBeat = b;
            targetFeat = f;
            break;
          }
        }
      }
    }
    if (targetBeat == null || targetFeat == null) return;
    final projTitle = activeProject?.title ?? 'Game Prototype';
    final engineLabel = _activeEngineLabel;
    final specContext = _buildCompactWorkbenchSpecContext();
    final siblingTitles = targetBeat.features
        .where((s) => s.id != featureId)
        .map((s) {
          final pAsset = (s.primarySharedScriptOrScene ?? '').trim();
          return pAsset.isNotEmpty
              ? '"${s.title}" [shared asset: $pAsset]'
              : '"${s.title}"';
        })
        .toList();

    final prompt = '''
You are the Systems Designer for "$projTitle" ($engineLabel).
Enrich this newly proposed Feature ("${targetFeat.title}" inside Epic "$beatTitle" for ${bp.releaseVersionTag}) so its tasks, numeric tuning parameters, and edge-case guards fit "$projTitle".
$specContext${siblingTitles.isNotEmpty ? 'Sibling Features in "$beatTitle" (reuse shared Epic script/scene when appropriate): ${siblingTitles.join(', ')}\n' : ''}${GeminiAgentClient.compactStyleRules}
- Return the exact number of tasks required: start with Scene/Entity/Collision foundation (never Input/Keybind), include 1..N middle tasks for core mechanic actions/math, finish with observable feedback & boundary clamp, and include 2–3 "paramName: numericValue unit" entries in tuningParams.
Call `commit_live_feature_enrichment` with the enriched feature details.''';

    final json = await GeminiAgentClient.generateJson(
      prompt: prompt,
      apiKey: _apiKey,
      preferredModel: _conversationModel,
      thinkingLevel: _thinkingLevel,
      temperature: 0.4,
      functionDeclarations: const [commitLiveFeatureEnrichmentTool],
    );
    if (json == null || _releaseBlueprint != bp) return;
    final aiGoal = json['goal']?.toString().trim() ?? '';
    final aiDoneWhen = json['doneWhen']?.toString().trim() ?? '';
    final aiPrimaryAsset =
        json['primarySharedScriptOrScene']?.toString().trim() ?? '';
    final aiCpTitle = json['checkpointTitle']?.toString().trim() ?? '';
    final aiGate = json['playtestGate']?.toString().trim() ?? '';
    final extractedTasks =
        ReleasePlannerAgent.extractCheckpointTasksFromMap(json);
    final rawInScope = json['inScope'];
    final rawTuning = json['tuningParams'];
    final rawGuards = json['edgeCases'];

    if (!preserveCustomGoal && aiGoal.isNotEmpty) {
      targetFeat.goal = aiGoal;
    }
    if (aiDoneWhen.isNotEmpty) {
      targetFeat.doneWhen = aiDoneWhen;
    }
    if (aiPrimaryAsset.isNotEmpty) {
      targetFeat.primarySharedScriptOrScene = aiPrimaryAsset;
    }
    if (rawInScope is List && rawInScope.isNotEmpty) {
      final scopeItems = rawInScope
          .map((e) => e.toString().trim())
          .where((s) => s.isNotEmpty)
          .toList();
      if (scopeItems.isNotEmpty) {
        targetFeat.inScope = scopeItems;
      }
    }
    if (rawTuning is List && rawTuning.isNotEmpty) {
      final tList = rawTuning
          .map((e) => e.toString().trim())
          .where((s) => s.isNotEmpty)
          .toList();
      if (tList.isNotEmpty) {
        targetFeat.tuningParams = tList;
      }
    }
    if (rawGuards is List && rawGuards.isNotEmpty) {
      final gList = rawGuards
          .map((e) => e.toString().trim())
          .where((s) => s.isNotEmpty)
          .toList();
      if (gList.isNotEmpty) {
        targetFeat.edgeCases = gList;
      }
    }
    final normalizedTasks = extractedTasks.isNotEmpty
        ? ReleasePlannerAgent.normalizeFoundationFirstTasks(
            extractedTasks,
            featureTitle: targetFeat.title,
            beatTitle: beatTitle,
          )
        : (targetFeat.checkpoints.isNotEmpty
            ? targetFeat.checkpoints.first.tasks
            : <String>[]);
    targetFeat.checkpoints = [
      ProposedCheckpointBlueprint(
        title: aiCpTitle.isNotEmpty ? aiCpTitle : '${targetFeat.title} Core',
        playtestCriteria: aiGate.isNotEmpty
            ? aiGate
            : 'Trigger ${targetFeat.title} in playtest -> responds cleanly on screen',
        tasks: normalizedTasks,
        coveredScope: targetFeat.inScope,
        tuningParams: targetFeat.tuningParams,
        edgeCases: targetFeat.edgeCases,
        releaseVersion: bp.releaseVersionTag,
      ),
    ];
    final relDoc = activeRelease;
    if (relDoc != null) {
      relDoc.sections['release_blueprint_json'] = jsonEncode(bp.toJson());
      _persistDocument(relDoc);
    }
    notifyListeners();
  }

  /// Promotes an Out-of-Scope exclusion item into a `+ NEW` feature in the Progressive Release Planner.
  ProposedFeatureBlueprint? promoteExclusionToNextRelease(
    String exclusionText, {
    String? targetBeatId,
  }) {
    final bp = _releaseBlueprint;
    if (bp == null || bp.beats.isEmpty) return null;
    final cleanEx = exclusionText.trim();
    if (cleanEx.isEmpty) return null;
    final shortTitle = _stripExclusionPrefixes(cleanEx)
        .split('—')
        .first
        .split(':')
        .first
        .trim();
    final targetBeat = targetBeatId != null
        ? bp.beats.firstWhere(
            (b) => b.id == targetBeatId,
            orElse: () => bp.beats.last,
          )
        : bp.beats.last;
    bp.explicitExclusions.removeWhere(
      (e) => e.toLowerCase().trim() == cleanEx.toLowerCase().trim(),
    );
    // Also remove from Stage 1 project exclusions so future Agent turns never treat this promoted item as banned
    final normShort = shortTitle.toLowerCase().trim();
    if (_conceptDraft != null) {
      _conceptDraft!.exclusions.removeWhere((e) {
        final normE = _stripExclusionPrefixes(e.toLowerCase());
        return e.toLowerCase().trim() == cleanEx.toLowerCase().trim() ||
            (normShort.isNotEmpty && normE.contains(normShort));
      });
    }
    final proj = activeProject;
    if (proj != null) {
      final rawEx = proj.sections['exclusions'] ?? '';
      final currentEx = rawEx
          .split('\n')
          .map((l) => _stripExclusionPrefixes(l, stripNoPrefix: false))
          .where((l) => l.isNotEmpty)
          .toList();
      currentEx.removeWhere((e) {
        final normE = _stripExclusionPrefixes(e.toLowerCase());
        return e.toLowerCase().trim() == cleanEx.toLowerCase().trim() ||
            (normShort.isNotEmpty && normE.contains(normShort));
      });
      proj.sections['exclusions'] =
          currentEx.map((e) => '• $e').join('\n');
      _persistDocument(proj, debounce: true);
    }
    return addCustomFeatureToProposedBeat(
      targetBeat.id,
      shortTitle.isNotEmpty ? shortTitle : cleanEx,
      customGoal: 'Promote "$shortTitle" into playable ${bp.releaseVersionTag} scope.',
    );
  }

  /// Compacts an archived `ReleaseBlueprint` JSON snapshot when shipping/advancing a release
  /// so browser `localStorage` (`5 MB` quota) does not accumulate redundant `questions`,
  /// `lastAgentReply`, or duplicate `stable` feature checkpoints across 10+ releases.
  String _encodeCompactArchivedReleaseBlueprint(ReleaseBlueprint bp) {
    final map = bp.toJson();
    map['questions'] = const <Map<String, dynamic>>[];
    map.remove('lastAgentReply');
    final rawBeats = map['beats'];
    if (rawBeats is List) {
      for (final b in rawBeats) {
        if (b is Map<String, dynamic>) {
          final rawFeats = b['features'];
          if (rawFeats is List) {
            for (final f in rawFeats) {
              if (f is Map<String, dynamic> && f['lifecycle'] == 'stable') {
                f['checkpoints'] = const <Map<String, dynamic>>[];
              }
            }
          }
        }
      }
    }
    return jsonEncode(map);
  }

  /// Adds a new Epic (`TierType.epic`) with a starter Playable Feature directly into the
  /// active release inside `2. Workbench` and returns the created Epic's document ID.
  String? addLiveEpicToActiveRelease(
    String rawTitle, {
    String? initialFeatureTitle,
  }) {
    final rel = activeRelease;
    final trimmed = rawTitle.trim();
    if (rel == null || trimmed.isEmpty) return null;

    String epicTitle = trimmed;
    String epicDesc = trimmed;
    final colonIdx = trimmed.indexOf(':');
    final dashIdx = trimmed.indexOf('—');
    int splitIdx = -1;
    if (colonIdx > 0 && (dashIdx < 0 || colonIdx < dashIdx)) {
      splitIdx = colonIdx;
    } else if (dashIdx > 0) {
      splitIdx = dashIdx;
    }
    if (splitIdx > 0) {
      final t = trimmed.substring(0, splitIdx).trim();
      final d = trimmed.substring(splitIdx + 1).trim();
      if (t.isNotEmpty) epicTitle = t;
      if (d.isNotEmpty) epicDesc = d;
    }

    final versionTag = activeReleaseVersionTag;
    final beatIndex = rel.childrenIds.length;
    final beatId =
        'beat_${rel.id}_${beatIndex + 1}_${DateTime.now().millisecondsSinceEpoch % 10000}';
    final featTitle = (initialFeatureTitle != null &&
            initialFeatureTitle.trim().isNotEmpty)
        ? initialFeatureTitle.trim()
        : ReleasePlannerAgent.disambiguateFeatureTitleFromBeat(
            epicTitle,
            beatTitle: epicTitle,
            featureGoal: epicDesc,
            beatIndex: beatIndex,
          );
    final featId = 'feat_${beatId}_1';
    final playtestGate =
        'Trigger $featTitle in the test scene -> $epicTitle responds cleanly';
    final starterTasks = <String>[
      'Create actor/node structure and base properties for $featTitle (2h)',
      'Implement core state transitions and player input for $featTitle (1h)',
      'Hook visual/audio feedback cues and state guard for $featTitle (1h)',
    ];
    final starterGuards = <String>[
      '[STATE GUARD] Block duplicate $featTitle activation while active',
    ];
    final stateNode = FeatureStateNode(
      id: '${featId}_${versionTag}_cp_1',
      name: 'Checkpoint 1: $featTitle',
      trigger: 'Playtest: $playtestGate',
      order: 0,
      checklist: [
        for (int tIdx = 0; tIdx < starterTasks.length; tIdx++)
          Subtask(
            id: '${featId}_t_${tIdx + 1}',
            text: starterTasks[tIdx],
            completed: false,
          ),
      ],
      coveredScope: [featTitle],
      tuningParams: const ['cooldown: 0.4 s', 'speed: 1.0 x'],
      edgeCases: starterGuards,
      parameters: {'releaseVersion': versionTag},
    );
    for (int tIdx = 0; tIdx < stateNode.checklist.length; tIdx++) {
      TaskHowToBlueprint.resolve(
        parentTask: stateNode.checklist[tIdx],
        taskIndex: tIdx,
        checkpointNode: stateNode,
        engineHint: _activeEngineHint,
        phase: _currentPhase,
      );
    }

    final featDoc = TierDocument(
      id: featId,
      title: featTitle,
      tier: TierType.feature,
      parentId: beatId,
      estimatedDuration: '4h',
      sections: {
        'originVersion': versionTag,
        'activeReleaseVersion': versionTag,
        'lifecycle': FeatureLifecycleStatus.newFeature.name,
        'scope':
            'Goal: +$featTitle\n\nIn Scope:\n• $featTitle\n\nDone When: $playtestGate',
        'variables': '• cooldown: 0.4 s\n• speed: 1.0 x',
        'tuning': '• cooldown: 0.4 s\n• speed: 1.0 x',
        'edge_cases': starterGuards.map((e) => '• $e').join('\n'),
      },
    );
    FeatureStateNode.saveStatesToDocument(featDoc, [stateNode]);
    documents[featId] = featDoc;
    _persistDocument(featDoc);

    final beatDoc = TierDocument(
      id: beatId,
      title: epicTitle,
      tier: TierType.epic,
      parentId: rel.id,
      estimatedDuration: '4h',
      childrenIds: [featId],
      sections: {
        'scope':
            'Goal: Build and playtest $epicDesc\n\nIn Scope:\n• $featTitle\n\nDone When: $playtestGate',
      },
    );
    documents[beatId] = beatDoc;
    _persistDocument(beatDoc);

    for (final r in projectReleases) {
      if (r.id == rel.id || r.childrenIds.isNotEmpty) {
        if (!r.childrenIds.contains(beatId)) {
          r.childrenIds.add(beatId);
          _persistDocument(r);
        }
      }
    }

    final bp = _releaseBlueprint;
    if (bp != null) {
      bp.beats.add(
        ProposedBeatBlueprint(
          id: beatId,
          title: epicTitle,
          goal: epicDesc,
          doneWhen: playtestGate,
          features: [
            ProposedFeatureBlueprint(
              id: featId,
              title: featTitle,
              goal: '+$featTitle',
              doneWhen: playtestGate,
              estimatedHours: 4,
              included: true,
              lifecycle: FeatureLifecycleStatus.newFeature,
              originVersion: versionTag,
              inScope: [featTitle],
              outOfScope: const [],
              tuningParams: const ['cooldown: 0.4 s', 'speed: 1.0 x'],
              edgeCases: starterGuards,
              checkpoints: [
                ProposedCheckpointBlueprint(
                  title: featTitle,
                  playtestCriteria: playtestGate,
                  tasks: starterTasks,
                  coveredScope: [featTitle],
                  tuningParams: const ['cooldown: 0.4 s', 'speed: 1.0 x'],
                  edgeCases: starterGuards,
                  releaseVersion: versionTag,
                ),
              ],
            ),
          ],
        ),
      );
      rel.sections['release_blueprint_json'] = jsonEncode(bp.toJson());
      _persistDocument(rel);
    }

    _selectedBeatId = beatId;
    selectFeature(featId, triggerAiSynthesis: false);
    _syncActiveProjectMetadata();
    if (GeminiAgentClient.hasKey(_apiKey) ||
        GeminiAgentClient.testMockResponder != null) {
      _enrichLiveFeatureWithAi(featId, epicTitle);
    } else {
      notifyListeners();
    }
    return beatId;
  }

  /// Adds a new Playable Feature directly into an active Epic (`beatId`) inside `2. Workbench`
  /// and enriches it via Gemini AI.
  String? addLiveFeatureToBeat(String beatId, String rawTitle) {
    final beatDoc = documents[beatId];
    final cleanTitle = rawTitle.trim();
    if (beatDoc == null || cleanTitle.isEmpty) return null;
    if (!GeminiAgentClient.hasKey(_apiKey) &&
        GeminiAgentClient.testMockResponder == null) {
      _setOfflineState();
      notifyListeners();
      return null;
    }

    final versionTag = activeReleaseVersionTag;
    final featId =
        'feat_${beatDoc.id}_${beatDoc.childrenIds.length + 1}_${DateTime.now().millisecondsSinceEpoch % 10000}';

    final featDoc = TierDocument(
      id: featId,
      title: cleanTitle,
      tier: TierType.feature,
      parentId: beatDoc.id,
      estimatedDuration: '4h',
      sections: {
        'originVersion': versionTag,
        'activeReleaseVersion': versionTag,
        'lifecycle': FeatureLifecycleStatus.newFeature.name,
        'scope': '',
        'variables': '',
        'tuning': '',
        'edge_cases': '',
      },
    );

    final starterTasks = <String>[
      'Create actor/node structure and base properties for $cleanTitle (2h)',
      'Implement core state transitions and player input for $cleanTitle (1h)',
      'Hook visual/audio feedback cues and state guard for $cleanTitle (1h)',
    ];
    final starterGuards = <String>[
      '[STATE GUARD] Block duplicate $cleanTitle activation while active',
    ];
    final stateNode = FeatureStateNode(
      id: '${featId}_${versionTag}_cp_1',
      name: 'Checkpoint 1: $cleanTitle',
      trigger: 'Playtest: Trigger $cleanTitle in the test arena',
      order: 0,
      checklist: [
        for (int tIdx = 0; tIdx < starterTasks.length; tIdx++)
          Subtask(
            id: '${featId}_t_${tIdx + 1}',
            text: starterTasks[tIdx],
            completed: false,
          ),
      ],
      coveredScope: [cleanTitle],
      tuningParams: const ['cooldown: 0.4 s', 'speed: 1.0 x'],
      edgeCases: starterGuards,
      parameters: {'releaseVersion': versionTag},
    );
    for (int tIdx = 0; tIdx < stateNode.checklist.length; tIdx++) {
      TaskHowToBlueprint.resolve(
        parentTask: stateNode.checklist[tIdx],
        taskIndex: tIdx,
        checkpointNode: stateNode,
        engineHint: _activeEngineHint,
        phase: _currentPhase,
      );
    }

    FeatureStateNode.saveStatesToDocument(featDoc, [stateNode]);
    documents[featId] = featDoc;
    beatDoc.childrenIds.add(featId);
    _persistDocument(featDoc);
    _persistDocument(beatDoc);

    // Keep _releaseBlueprint in sync if present
    final bp = _releaseBlueprint;
    if (bp != null) {
      for (final b in bp.beats) {
        if (b.id == beatId ||
            b.title.toLowerCase().trim() ==
                beatDoc.title.toLowerCase().trim()) {
          b.features.add(
            ProposedFeatureBlueprint(
              id: featId,
              title: cleanTitle,
              goal: '',
              doneWhen: '',
              estimatedHours: 4,
              included: true,
              lifecycle: FeatureLifecycleStatus.newFeature,
              originVersion: versionTag,
              inScope: const [],
              outOfScope: const [],
              tuningParams: const [],
              edgeCases: const [],
              checkpoints: [
                ProposedCheckpointBlueprint(
                  title: cleanTitle,
                  playtestCriteria: '',
                  tasks: const [],
                  coveredScope: const [],
                  tuningParams: const [],
                  edgeCases: const [],
                  releaseVersion: versionTag,
                ),
              ],
            ),
          );
          break;
        }
      }
    }

    selectFeature(featId, triggerAiSynthesis: false);
    _syncActiveProjectMetadata();
    _enrichLiveFeatureWithAi(featId, beatDoc.title);
    return featId;
  }

  Future<void> _enrichLiveFeatureWithAi(
    String featureId,
    String beatTitle,
  ) async {
    final featDoc = documents[featureId];
    if (featDoc == null) return;
    final states = FeatureStateNode.getStatesForDocument(featDoc);
    if (states.isEmpty) return;
    _synthesizingFeatureIds.add(featureId);
    notifyListeners();
    try {
      final projTitle = activeProject?.title ?? 'Game Prototype';
      final engineLabel = _activeEngineLabel;
      final specContext = _buildCompactWorkbenchSpecContext();
      final siblingTitles = featDoc.parentId == null
          ? const <String>[]
          : featuresForBeat(featDoc.parentId!)
              .where((s) => s.id != featureId)
              .map((s) {
                final pAsset = (s.sections['primary_asset'] ?? '').trim();
                return pAsset.isNotEmpty
                    ? '"${s.title}" [shared asset: $pAsset]'
                    : '"${s.title}"';
              })
              .toList();
      final prompt = '''
You are the Systems Designer for "$projTitle" ($engineLabel).
Tailor this newly added Feature ("${featDoc.title}" inside Epic "$beatTitle") so its tasks, numeric tuning parameters, and edge-case guards fit "$projTitle".
$specContext${siblingTitles.isNotEmpty ? 'Sibling Features in "$beatTitle" (reuse shared Epic script/scene when appropriate): ${siblingTitles.join(', ')}\n' : ''}${GeminiAgentClient.compactStyleRules}
- Return the exact number of tasks required: start with Scene/Entity/Collision foundation (never Input/Keybind), include 1..N middle tasks for core mechanic actions/math, finish with observable feedback & boundary clamp, and include 2–3 "paramName: numericValue unit" entries in tuningParams.
Call `commit_live_feature_enrichment` with the enriched feature details.''';
    final json = await GeminiAgentClient.generateJson(
      prompt: prompt,
      apiKey: _apiKey,
      preferredModel: _conversationModel,
      thinkingLevel: _thinkingLevel,
      temperature: 0.4,
      functionDeclarations: const [commitLiveFeatureEnrichmentTool],
    );
    if (json != null && documents.containsKey(featureId)) {
      final cp = states.first;
      final aiGoal = json['goal']?.toString().trim() ?? '';
      final aiDoneWhen = json['doneWhen']?.toString().trim() ?? '';
      final aiPrimaryAsset =
          json['primarySharedScriptOrScene']?.toString().trim() ?? '';
      if (aiPrimaryAsset.isNotEmpty) {
        featDoc.sections['primary_asset'] = aiPrimaryAsset;
        cp.parameters['primarySharedScriptOrScene'] = aiPrimaryAsset;
      }
      final rawInScope = json['inScope'];
      final parsedInScope = (rawInScope is List)
          ? rawInScope
              .map((e) => e.toString().trim())
              .where((s) => s.isNotEmpty)
              .toList()
          : const <String>[];
      final effectiveInScope =
          parsedInScope.isNotEmpty ? parsedInScope : <String>[featDoc.title];
      cp.coveredScope = effectiveInScope;
      final aiTitle = json['checkpointTitle']?.toString().trim() ?? '';
      final aiGate = json['playtestGate']?.toString().trim() ?? '';
      final extractedTasks =
          ReleasePlannerAgent.extractCheckpointTasksFromMap(json);
      final rawTuning = json['tuningParams'];
      final rawGuards = json['edgeCases'];
      if (aiGoal.isNotEmpty || aiDoneWhen.isNotEmpty || parsedInScope.isNotEmpty) {
        final effectiveGoal = aiGoal.isNotEmpty
            ? aiGoal
            : 'Build ${featDoc.title} inside $beatTitle.';
        final effectiveDoneWhen = aiDoneWhen.isNotEmpty
            ? aiDoneWhen
            : (aiGate.isNotEmpty
                ? aiGate
                : 'Playtester verifies ${featDoc.title} in the test arena.');
        final inScopeBullets =
            effectiveInScope.map((s) => '• $s').join('\n');
        featDoc.sections['scope'] =
            'Goal: $effectiveGoal\n\nIn Scope:\n$inScopeBullets\n\nDone When: $effectiveDoneWhen';
        _persistDocument(featDoc);
        final bp = _releaseBlueprint;
        if (bp != null) {
          for (final b in bp.beats) {
            for (final f in b.features) {
              if (f.id == featureId) {
                f.goal = effectiveGoal;
                f.inScope = List<String>.from(effectiveInScope);
                f.doneWhen = effectiveDoneWhen;
              }
            }
          }
        }
      }
      if (aiTitle.isNotEmpty) {
        cp.name = 'Checkpoint 1: $aiTitle';
      }
      if (aiGate.isNotEmpty) {
        cp.trigger = 'Playtest: $aiGate';
      }
      if (extractedTasks.isNotEmpty) {
        final normalizedTasks =
            ReleasePlannerAgent.normalizeFoundationFirstTasks(
          extractedTasks,
          featureTitle: featDoc.title,
          beatTitle: beatTitle,
        );
        cp.checklist = [
          for (int i = 0; i < normalizedTasks.length; i++)
            Subtask(
              id: '${featureId}_ai_t${i + 1}',
              text: normalizedTasks[i],
              completed: false,
            ),
        ];
      }
      if (rawTuning is List && rawTuning.isNotEmpty) {
        cp.tuningParams =
            rawTuning.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();
        final tuningText = cp.tuningParams.map((t) => '• $t').join('\n');
        featDoc.sections['tuning'] = tuningText;
        featDoc.sections['variables'] = tuningText;
      }
      if (rawGuards is List && rawGuards.isNotEmpty) {
        cp.edgeCases =
            rawGuards.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();
        featDoc.sections['edge_cases'] =
            cp.edgeCases.map((e) => '• $e').join('\n');
      }
      _persistDocument(featDoc);
      final bp = _releaseBlueprint;
      if (bp != null) {
        for (final b in bp.beats) {
          for (final f in b.features) {
            if (f.id == featureId) {
              if (aiPrimaryAsset.isNotEmpty) {
                f.primarySharedScriptOrScene = aiPrimaryAsset;
              }
              f.tuningParams = List<String>.from(cp.tuningParams);
              f.edgeCases = List<String>.from(cp.edgeCases);
              f.checkpoints = [
                ProposedCheckpointBlueprint(
                  title: aiTitle.isNotEmpty ? aiTitle : featDoc.title,
                  playtestCriteria: aiGate.isNotEmpty
                      ? aiGate
                      : cp.playtestCondition,
                  tasks: [for (final t in cp.checklist) t.text],
                  coveredScope: List<String>.from(cp.coveredScope),
                  tuningParams: List<String>.from(cp.tuningParams),
                  edgeCases: List<String>.from(cp.edgeCases),
                  releaseVersion: cp.releaseVersion,
                ),
              ];
            }
          }
        }
        final relDoc = activeRelease;
        if (relDoc != null) {
          relDoc.sections['release_blueprint_json'] = jsonEncode(bp.toJson());
          _persistDocument(relDoc);
        }
      }
      for (int tIdx = 0; tIdx < cp.checklist.length; tIdx++) {
        TaskHowToBlueprint.resolve(
          parentTask: cp.checklist[tIdx],
          taskIndex: tIdx,
          checkpointNode: cp,
          engineHint: _activeEngineHint,
          phase: _currentPhase,
        );
      }
      updateFeatureStates(featureId, states);
      }
    } finally {
      _synthesizingFeatureIds.remove(featureId);
    }
    await synthesizeFeatureHowToStepsWithAi(featureId, forceRefresh: true);
  }

  /// Appends a single new Build Task to a Checkpoint in `2. Workbench`, resolves its initial
  /// deterministic sub-steps, syncs `_releaseBlueprint`, and tailors ONLY the newly added task
  /// via `tailorTaskHowToSubSteps` so existing tasks `1..N-1` are never overwritten.
  int addBuildTaskToCheckpointWithAi({
    required String featureId,
    required List<FeatureStateNode> states,
    required int checkpointIndex,
    required String rawTaskTitle,
    bool unrealCppMode = false,
  }) {
    final trimmed = rawTaskTitle.trim();
    if (trimmed.isEmpty ||
        checkpointIndex < 0 ||
        checkpointIndex >= states.length) {
      return -1;
    }
    final hasExplicitHours =
        RegExp(r'\(\d+\s*h\)', caseSensitive: false).hasMatch(trimmed);
    final taskText = hasExplicitHours ? trimmed : '$trimmed (2h)';
    final cpNode = states[checkpointIndex];
    final newTask = Subtask(
      id: 'task_${DateTime.now().millisecondsSinceEpoch}',
      text: taskText,
      completed: false,
    );
    cpNode.checklist.add(newTask);
    final newIdx = cpNode.checklist.length - 1;
    TaskHowToBlueprint.resolve(
      parentTask: newTask,
      taskIndex: newIdx,
      checkpointNode: cpNode,
      engineHint: _activeEngineHint,
      unrealCppMode: unrealCppMode,
      phase: _currentPhase,
    );
    updateFeatureStates(featureId, states);

    final bp = _releaseBlueprint;
    if (bp != null) {
      for (final b in bp.beats) {
        for (final f in b.features) {
          if (f.id == featureId &&
              checkpointIndex < f.checkpoints.length) {
            final cpBp = f.checkpoints[checkpointIndex];
            f.checkpoints[checkpointIndex] = ProposedCheckpointBlueprint(
              title: cpBp.title,
              playtestCriteria: cpBp.playtestCriteria,
              tasks: [for (final t in cpNode.checklist) t.text],
              coveredScope: cpBp.coveredScope,
              tuningParams: cpBp.tuningParams,
              edgeCases: cpBp.edgeCases,
              releaseVersion: cpBp.releaseVersion,
            );
          }
        }
      }
      final relDoc = activeRelease;
      if (relDoc != null) {
        relDoc.sections['release_blueprint_json'] = jsonEncode(bp.toJson());
        _persistDocument(relDoc);
      }
    }

    if (GeminiAgentClient.hasKey(_apiKey) ||
        GeminiAgentClient.testMockResponder != null) {
      final featDoc = documents[featureId];
      final primaryAsset =
          (featDoc?.sections['primary_asset'] ?? '').trim();
      final contextDesc = primaryAsset.isNotEmpty
          ? 'Implement "$taskText" on shared asset $primaryAsset'
          : 'Implement "$taskText" for ${featDoc?.title ?? cpNode.cleanStageTitle}';
      tailorTaskHowToSubSteps(
        featureId: featureId,
        states: states,
        checkpointIndex: checkpointIndex,
        taskIndex: newIdx,
        userContext: contextDesc,
      );
    }
    return newIdx;
  }

  /// Renames an active Feature document directly inside `2. Workbench` and syncs `_releaseBlueprint`.
  void renameLiveFeature(String featureId, String newTitle) {
    final featDoc = documents[featureId];
    final cleanTitle = newTitle.trim();
    if (featDoc == null || cleanTitle.isEmpty) return;

    final oldTitle = featDoc.title;
    featDoc.title = cleanTitle;
    _persistDocument(featDoc);

    final bp = _releaseBlueprint;
    if (bp != null) {
      for (final b in bp.beats) {
        for (final f in b.features) {
          if (f.id == featureId ||
              f.title.toLowerCase().trim() == oldTitle.toLowerCase().trim()) {
            f.title = cleanTitle;
          }
        }
      }
    }
    _syncActiveProjectMetadata();
    notifyListeners();
  }

  /// Removes/defers a Feature document from its parent Epic inside `2. Workbench`
  /// and automatically selects the next available Feature.
  bool removeLiveFeature(String featureId) {
    final featDoc = documents[featureId];
    if (featDoc == null) return false;
    final parentBeatId = featDoc.parentId;
    final beatDoc = parentBeatId != null ? documents[parentBeatId] : null;
    final isArchivedFeat =
        featDoc.sections['lifecycle'] == FeatureLifecycleStatus.superseded.name;

    // Prevent deleting the very last feature in the entire release so the Workbench never empties
    final allFeats = <TierDocument>[
      for (final b in activeReleaseBeats) ...featuresForBeat(b.id),
    ];
    if (!isArchivedFeat && allFeats.length <= 1) return false;

    if (beatDoc != null) {
      beatDoc.childrenIds.remove(featureId);
      _persistDocument(beatDoc);
    }
    documents.remove(featureId);
    LocalVaultService.deleteDocument(featureId);
    final user = _authService.currentUser;
    if (user != null) {
      _firestoreService.deleteDocument(uid: user.uid, docId: featureId);
    }

    final bp = _releaseBlueprint;
    if (bp != null) {
      for (final b in bp.beats) {
        for (final f in b.features) {
          if (f.id == featureId ||
              f.title.toLowerCase().trim() ==
                  featDoc.title.toLowerCase().trim()) {
            f.included = false;
          }
        }
      }
    }

    if (_releaseViewFilter == 'archived') {
      final remainingArchived = supersededFeatures;
      if (remainingArchived.isNotEmpty) {
        if (_selectedFeatureId == featureId) {
          _selectedFeatureId = remainingArchived.first.id;
        }
      } else {
        _releaseViewFilter = 'active';
        _selectFirstIncompleteFeatureInActiveRelease();
      }
    } else if (_selectedFeatureId == featureId) {
      _selectFirstIncompleteFeatureInActiveRelease();
    }
    _syncActiveProjectMetadata();
    notifyListeners();
    return true;
  }

  /// Logs a Playtest Issue on a Checkpoint in `2. Workbench`:
  /// 1. Appends a `[FIX] <issueDescription> (1h)` Parent Task to `cpNode.checklist` with
  ///    3 checkable, engine-aware debug/fix How-To Sub-Steps.
  /// 2. Appends `[PLAYTEST GUARD] <issueDescription>` to `cpNode.edgeCases`.
  /// Returns the index of the newly created `[FIX]` Parent Task.
  int logPlaytestIssueOnCheckpoint({
    required String featureId,
    required List<FeatureStateNode> states,
    required int checkpointIndex,
    required String issueDescription,
  }) {
    final cleanIssue = issueDescription.trim();
    if (cleanIssue.isEmpty ||
        checkpointIndex < 0 ||
        checkpointIndex >= states.length) {
      return -1;
    }
    final cpNode = states[checkpointIndex];
    final newTaskIndex = cpNode.checklist.length;
    final taskNum = newTaskIndex + 1;
    final engineLabel = _activeEngineLabel;
    final engineUpper = engineLabel.toUpperCase();
    final isUnity = engineUpper.contains('UNITY');
    final isUnreal = engineUpper.contains('UNREAL');
    final defaultScriptPath = isUnity
        ? 'Assets/Scripts/PlaytestFixController.cs'
        : (isUnreal
            ? 'Source/PlaytestFixActor.cpp'
            : 'res://scripts/playtest_fix_controller.gd');
    final primaryTune = cpNode.tuningParams.isNotEmpty
        ? cpNode.tuningParams.first
        : 'threshold: 1.0';

    final fixTask = Subtask(
      id: generateUniqueId('fix_task'),
      text: '[FIX] $cleanIssue (1h)',
      completed: false,
      children: [
        Subtask(
          id: generateUniqueId('fix_sub_1'),
          text: 'STEP $taskNum.1 · REPRODUCE & INSPECT PLAYTEST ISSUE',
          specNotes:
              'Trigger "$cleanIssue" in the game viewport and inspect live state values ($primaryTune).',
          codeLanguage: defaultScriptPath,
          codeTargetFile: 'custom_snippet',
          codeSnippet: isUnity
              ? '// Inspect live state when "$cleanIssue" occurs\nDebug.LogWarning("[PLAYTEST FIX] $cleanIssue | $primaryTune");'
              : (isUnreal
                  ? '// Inspect live state when "$cleanIssue" occurs\nUE_LOG(LogTemp, Warning, TEXT("[PLAYTEST FIX] %s"), *GetName());'
                  : '# Inspect live state when "$cleanIssue" occurs\nprint("[PLAYTEST FIX] $cleanIssue | $primaryTune")'),
        ),
        Subtask(
          id: generateUniqueId('fix_sub_2'),
          text: 'STEP $taskNum.2 · APPLY FIX & CLAMP TUNING BOUNDS',
          specNotes:
              'Adjust the update/collision logic and clamp $primaryTune so "$cleanIssue" cannot happen.',
          codeLanguage: defaultScriptPath,
          codeTargetFile: 'custom_snippet',
          codeSnippet: isUnity
              ? '// Enforce boundary check for: $cleanIssue\n// Active tuning: $primaryTune'
              : (isUnreal
                  ? '// Enforce boundary check for: $cleanIssue\n// Active tuning: $primaryTune'
                  : '# Enforce boundary check for: $cleanIssue\n# Active tuning: $primaryTune'),
        ),
        Subtask(
          id: generateUniqueId('fix_sub_3'),
          text: 'STEP $taskNum.3 · VERIFY PLAYTEST GUARD IN VIEWPORT',
          specNotes:
              'Re-run the checkpoint playtest gate ("${cpNode.playtestCondition}") 3 times to confirm "$cleanIssue" is resolved.',
          codeLanguage: defaultScriptPath,
          codeTargetFile: 'custom_snippet',
          codeSnippet: isUnity
              ? '// Verify guard in Play mode: [PLAYTEST GUARD] $cleanIssue'
              : (isUnreal
                  ? '// Verify guard in Play mode: [PLAYTEST GUARD] $cleanIssue'
                  : '# Verify guard in Play mode: [PLAYTEST GUARD] $cleanIssue'),
        ),
      ],
    );

    cpNode.checklist.add(fixTask);
    final guardText = '[PLAYTEST GUARD] $cleanIssue';
    if (!cpNode.edgeCases.contains(guardText)) {
      cpNode.edgeCases = [...cpNode.edgeCases, guardText];
    }
    updateFeatureStates(featureId, states);
    if (GeminiAgentClient.hasKey(_apiKey) ||
        GeminiAgentClient.testMockResponder != null) {
      _enrichPlaytestFixWithAi(
        featureId: featureId,
        states: states,
        checkpointIndex: checkpointIndex,
        fixTaskIndex: newTaskIndex,
        issueDescription: cleanIssue,
      );
    } else {
      _setOfflineState();
      notifyListeners();
    }
    return newTaskIndex;
  }

  Future<void> _enrichPlaytestFixWithAi({
    required String featureId,
    required List<FeatureStateNode> states,
    required int checkpointIndex,
    required int fixTaskIndex,
    required String issueDescription,
  }) async {
    if (checkpointIndex < 0 || checkpointIndex >= states.length) return;
    final cpNode = states[checkpointIndex];
    if (fixTaskIndex < 0 || fixTaskIndex >= cpNode.checklist.length) return;
    final fixTask = cpNode.checklist[fixTaskIndex];
    final featTitle = documents[featureId]?.title ?? cpNode.cleanStageTitle;
    final engineLabel = _activeEngineLabel;
    final taskNum = fixTaskIndex + 1;

    _synthesizingFeatureIds.add(featureId);
    notifyListeners();
    try {
      final specContext = _buildCompactWorkbenchSpecContext(
        singleLineProjectSpecsHeader: true,
      );
      final existingTasksSummary = [
        for (int i = 0; i < fixTaskIndex; i++)
          () {
            final t = cpNode.checklist[i];
            final firstPath = t.children
                .map((s) => (s.codeLanguage ?? '').trim())
                .firstWhere(
                  (p) => p.isNotEmpty && p != 'custom_snippet',
                  orElse: () => '',
                );
            return 'Task ${i + 1}: "${t.text}"${firstPath.isNotEmpty ? ' ($firstPath)' : ''}';
          }(),
      ].join(' | ');

      final primaryAsset = (documents[featureId]?.sections['primary_asset'] ??
              cpNode.parameters['primarySharedScriptOrScene'] ??
              '')
          .trim();
      final primaryAssetLine = primaryAsset.isNotEmpty
          ? 'Primary Shared Asset (modify this exact script/scene): $primaryAsset\n'
          : '';
      final structuralSnapshot = _buildPriorCheckpointStructuralSnapshot(
        states,
        checkpointIndex + 1,
      );

      final prompt = '''
You are the Playtest Root-Cause Debugger for LAYERS-Agentic ($engineLabel).
Diagnose this reported playtest bug on Feature "$featTitle" (Checkpoint "${cpNode.cleanStageTitle}") and synthesize the exact number of concrete engine fix steps needed to resolve and verify it:
$specContext$primaryAssetLine${existingTasksSummary.isNotEmpty ? 'Existing Checkpoint Tasks & Scripts (patch these exact assets; do not invent duplicate scripts): $existingTasksSummary\n' : ''}${structuralSnapshot.isNotEmpty ? 'Existing Scene & Script Structure:\n$structuralSnapshot\n' : ''}Reported Bug: "$issueDescription"
Active Tuning Parameters: ${cpNode.tuningParams.join(', ')}
Active Guards: ${cpNode.edgeCases.join(', ')}

Call `commit_playtest_fix` with the sequential fix steps (Step $taskNum.1 through Step $taskNum.N).''';
      final json = await GeminiAgentClient.generateJson(
        prompt: prompt,
        apiKey: _apiKey,
        preferredModel: _planningModel,
        thinkingLevel: _thinkingLevel,
        temperature: 0.3,
        functionDeclarations: const [commitPlaytestFixTool],
      );
      if (json == null) return;
      final aiFixTitle = json['fixTaskTitle']?.toString().trim() ?? '';
      if (aiFixTitle.isNotEmpty) {
        final withPrefix = aiFixTitle.startsWith('[FIX]')
            ? aiFixTitle
            : '[FIX] $aiFixTitle';
        fixTask.text = RegExp(r'\(\s*\d+(?:\.\d+)?\s*[hm]\s*\)\s*$')
                .hasMatch(withPrefix)
            ? withPrefix
            : '$withPrefix (1h)';
      }
      final rawSteps = json['steps'];
      if (rawSteps is List && rawSteps.isNotEmpty) {
        final updatedSubs = <Subtask>[];
        for (int i = 0; i < rawSteps.length; i++) {
          final item = rawSteps[i];
          if (item is Map) {
            final title = item['title']?.toString().trim() ?? '';
            final path = item['stepPath']?.toString().trim() ?? '';
            final instr = item['instruction']?.toString().trim() ?? '';
            final area1 = item['area1Hierarchy']?.toString().trim() ?? '';
            final area2 = item['area2Inspector']?.toString().trim() ?? '';
            final code = item['codeFormula']?.toString().trim() ?? '';
            final verify = item['verifyResult']?.toString().trim() ?? '';
            final prevDone = i < fixTask.children.length
                ? fixTask.children[i].completed
                : false;
            final encodedNotes = TaskHowToBlueprint.encodeThreeAreaNotes(
              instruction: instr,
              area1Hierarchy: area1,
              area2Inspector: area2,
            );
            updatedSubs.add(
              Subtask(
                id: i < fixTask.children.length
                    ? fixTask.children[i].id
                    : generateUniqueId('fix_ai_sub_${i + 1}'),
                text: title.isNotEmpty
                    ? title
                    : 'STEP $taskNum.${i + 1} · APPLY ROOT-CAUSE FIX ${i + 1}',
                specNotes: encodedNotes,
                codeSnippet: code,
                codeLanguage: path,
                verification: verify,
                codeTargetFile: 'custom_snippet',
                completed: prevDone,
              ),
            );
          }
        }
        if (updatedSubs.isNotEmpty) {
          fixTask.children = updatedSubs;
        }
      }
      final rawTuningUpdates = json['tuningUpdates'];
      if (rawTuningUpdates is List && rawTuningUpdates.isNotEmpty) {
        final updatedTuning = List<String>.from(cpNode.tuningParams);
        for (final item in rawTuningUpdates) {
          if (item is Map) {
            final k = (item['variableName'] ?? item['name'] ?? '')
                .toString()
                .trim();
            final v = (item['value'] ?? '').toString().trim();
            if (k.isEmpty || v.isEmpty) continue;
            final normK = k.toLowerCase().replaceAll(_nonAlphaNumRegex, '');
            final existingIdx = updatedTuning.indexWhere(
              (p) =>
                  p
                      .split(':')
                      .first
                      .toLowerCase()
                      .replaceAll(_nonAlphaNumRegex, '') ==
                  normK,
            );
            if (existingIdx >= 0) {
              final canonicalKey =
                  updatedTuning[existingIdx].split(':').first.trim();
              updatedTuning[existingIdx] = '$canonicalKey: $v';
            } else {
              updatedTuning.add('$k: $v');
            }
          }
        }
        cpNode.tuningParams = updatedTuning;
      }
      final aiGuard = json['playtestGuard']?.toString().trim() ?? '';
      if (aiGuard.isNotEmpty) {
        final normGuard = aiGuard.startsWith('[PLAYTEST GUARD]')
            ? aiGuard
            : '[PLAYTEST GUARD] $aiGuard';
        final rawPlaceholderGuard = '[PLAYTEST GUARD] ${issueDescription.trim()}';
        final updatedGuards = cpNode.edgeCases
            .where((g) => g.trim() != rawPlaceholderGuard)
            .toList();
        if (!updatedGuards.contains(normGuard)) {
          updatedGuards.add(normGuard);
        }
        cpNode.edgeCases = updatedGuards;
      }
      TaskHowToBlueprint.clearCache();
      updateFeatureStates(featureId, states);
    } finally {
      _synthesizingFeatureIds.remove(featureId);
      notifyListeners();
      if (_synthesizingFeatureIds.isEmpty &&
          _pendingFeatureStepQueue.isNotEmpty &&
          !_isDrainingStepQueue) {
        _prefetchRemainingFeatureStepsInBackground(null, _stepQueueGeneration);
      }
    }
  }

  /// Tailors the checkable How-To sub-steps (`Step X.1` through `Step X.N`) for a specific
  /// Parent Task in `2. Workbench` using Gemini AI (`gemini-flash-latest`).
  /// Returns `true` if AI sub-steps were synthesized and applied, or `false` if offline/failed.
  Future<bool> tailorTaskHowToSubSteps({
    required String featureId,
    required List<FeatureStateNode> states,
    required int checkpointIndex,
    required int taskIndex,
    required String userContext,
  }) async {
    final cleanContext = userContext.trim();
    if (cleanContext.isEmpty ||
        checkpointIndex < 0 ||
        checkpointIndex >= states.length) {
      return false;
    }
    final cpNode = states[checkpointIndex];
    if (taskIndex < 0 || taskIndex >= cpNode.checklist.length) return false;
    final parentTask = cpNode.checklist[taskIndex];
    final featDoc = documents[featureId];
    final engineHint = _activeEngineHint;
    final engineLabel = _activeEngineLabel;
    final taskNum = taskIndex + 1;

    // Ensure children are initialized first
    TaskHowToBlueprint.resolve(
      parentTask: parentTask,
      taskIndex: taskIndex,
      checkpointNode: cpNode,
      engineHint: engineHint,
      phase: _currentPhase,
    );

    if (!GeminiAgentClient.hasKey(_apiKey)) {
      _setOfflineState();
      return false;
    }

    _synthesizingFeatureIds.add(featureId);
    notifyListeners();
    try {
      final specContext = _buildCompactWorkbenchSpecContext(
        singleLineProjectSpecsHeader: true,
      );
      final featGoal = featDoc != null
          ? SectionTextUtils.resolveGoal(featDoc.sections).trim()
          : '';
      final siblingTasksSummary = [
        for (int sIdx = 0; sIdx < cpNode.checklist.length; sIdx++)
          if (sIdx != taskIndex)
            () {
              final st = cpNode.checklist[sIdx];
              final firstPath = st.children
                  .map((s) => (s.codeLanguage ?? '').trim())
                  .firstWhere(
                    (p) => p.isNotEmpty && p != 'custom_snippet',
                    orElse: () => '',
                  );
              return 'Task ${sIdx + 1}: "${st.text}"${firstPath.isNotEmpty ? ' ($firstPath)' : ''}';
            }(),
      ].join(' | ');

      final primaryAsset = (cpNode.parameters['primarySharedScriptOrScene'] ??
              featDoc?.sections['primary_asset'] ??
              '')
          .trim();
      final primaryAssetLine = primaryAsset.isNotEmpty
          ? 'Primary Shared Asset (modify this exact script/scene): $primaryAsset\n'
          : '';
      final structuralSnapshot = _buildPriorCheckpointStructuralSnapshot(
        states,
        checkpointIndex + 1,
      );

      final prompt = '''
You are a senior game engine programmer assisting with a concrete implementation task.
Engine: $engineLabel
${specContext}Feature: "${featDoc?.title ?? cpNode.name}"${featGoal.isNotEmpty ? ' (Goal: $featGoal)' : ''}
Playtest Gate: "${cpNode.playtestCondition}"
Target Task ($taskNum of ${cpNode.checklist.length}): "${parentTask.text}"
$primaryAssetLine${siblingTasksSummary.isNotEmpty ? 'Sibling Tasks in Same Checkpoint (do not duplicate their work; stay on the same shared asset): $siblingTasksSummary\n' : ''}${structuralSnapshot.isNotEmpty ? 'Existing Scene & Script Structure:\n$structuralSnapshot\n' : ''}Active Tuning Parameters: ${cpNode.tuningParams.join(', ')}
Active Edge-Case Guards: ${cpNode.edgeCases.join(', ')}
Developer's Exact Scene / Node / Script Setup: "$cleanContext"

Break this task down into the exact number of checkable How-To Sub-Steps (Step $taskNum.1 through Step $taskNum.N — e.g., 3 steps for a simple hook/guard task or up to 6 steps for a multi-part mechanic) specifically using the developer's node/script names from "$cleanContext".
Call `commit_tailored_task_substeps` with the tailored sub-steps.
''';
      final json = await GeminiAgentClient.generateJson(
        prompt: prompt,
        apiKey: _apiKey,
        preferredModel: _conversationModel,
        thinkingLevel: _thinkingLevel,
        temperature: 0.25,
        functionDeclarations: const [commitTailoredTaskSubStepsTool],
      );
      final tailoredPrimaryAsset =
          (json?['primarySharedScriptOrScene'] ?? '').toString().trim();
      if (tailoredPrimaryAsset.isNotEmpty) {
        if (featDoc != null) {
          featDoc.sections['primary_asset'] = tailoredPrimaryAsset;
        }
        cpNode.parameters['primarySharedScriptOrScene'] = tailoredPrimaryAsset;
      }
      final rawSubs = json?['subSteps'];
      if (rawSubs is List && rawSubs.isNotEmpty) {
        final newChildren = <Subtask>[];
        for (int i = 0; i < rawSubs.length; i++) {
          final item = rawSubs[i];
          if (item is Map) {
            final t = (item['title'] ?? '').toString().trim();
            final path = (item['stepPath'] ?? '').toString().trim();
            final instr = (item['instruction'] ?? '').toString().trim();
            final area1 = (item['area1Hierarchy'] ?? '').toString().trim();
            final area2 = (item['area2Inspector'] ?? '').toString().trim();
            final code = (item['codeFormula'] ?? '').toString().trim();
            final verify = (item['verifyResult'] ?? '').toString().trim();
            final prevDone = i < parentTask.children.length
                ? parentTask.children[i].completed
                : parentTask.completed;
            final encodedNotes = TaskHowToBlueprint.encodeThreeAreaNotes(
              instruction: instr,
              area1Hierarchy: area1,
              area2Inspector: area2,
            );
            newChildren.add(
              Subtask(
                id: '${parentTask.id}_sub_${i + 1}',
                text: t.isNotEmpty
                    ? t
                    : 'STEP $taskNum.${i + 1} · IMPLEMENT STEP ${i + 1}',
                specNotes: encodedNotes,
                codeSnippet: code,
                codeLanguage: path,
                verification: verify,
                codeTargetFile: 'custom_snippet',
                completed: prevDone,
              ),
            );
          }
        }
        if (newChildren.isNotEmpty) {
          _offlineErrorMessage = null;
          parentTask.children = newChildren;
          TaskHowToBlueprint.clearCache();
          updateFeatureStates(featureId, states);
          return true;
        }
      }

      _setOfflineState();
      return false;
    } finally {
      _synthesizingFeatureIds.remove(featureId);
      notifyListeners();
      if (_synthesizingFeatureIds.isEmpty &&
          _pendingFeatureStepQueue.isNotEmpty &&
          !_isDrainingStepQueue) {
        _prefetchRemainingFeatureStepsInBackground(null, _stepQueueGeneration);
      }
    }
  }

  /// Stage 2 -> Stage 3: User approves the Release Plan Gate; Executor Agent builds or evolves the Release hierarchy.
  Future<void> approveAndExecuteReleasePlan() async {
    final bp = _releaseBlueprint;
    final relDoc = activeRelease;
    if (bp == null || relDoc == null) return;

    _stepQueueGeneration++;
    _pendingFeatureStepQueue.clear();
    _isAgentBusy = true;
    _executionLog.clear();
    _currentStage = WorkbenchStage.releaseWorkbench;
    _releaseViewFilter = 'active';
    notifyListeners();

    try {
      final isInitialV01Rebuild = bp.releaseVersionTag == 'v0.1' &&
          (relDoc.sections['prototypePart'] ?? '') != '2';
      final oldV01BeatIds = isInitialV01Rebuild
          ? List<String>.from(relDoc.childrenIds)
          : const <String>[];
      final oldV01FeatureIds = isInitialV01Rebuild
          ? <String>{
              for (final bId in oldV01BeatIds)
                ...(documents[bId]?.childrenIds ?? const <String>[]),
            }
          : const <String>{};
      if (isInitialV01Rebuild) {
        _aiSynthesizedFeatureSteps.clear();
      }

      final createdDocs = await ReleaseExecutorAgent.executeBlueprint(
        releaseDoc: relDoc,
        blueprint: bp,
        existingDocuments: documents,
        onProgress: (msg) {
          _agentProgressStep = msg;
          _executionLog.add(msg);
          notifyListeners();
        },
      );

      final createdDocIds = <String>{for (final d in createdDocs) d.id};
      for (final d in createdDocs) {
        documents[d.id] = d;
        _persistDocument(d);
      }
      if (isInitialV01Rebuild &&
          (oldV01BeatIds.isNotEmpty || oldV01FeatureIds.isNotEmpty)) {
        final otherReleaseBeatIds = <String>{
          for (final r in projectReleases)
            if (r.id != relDoc.id) ...r.childrenIds,
        };
        final user = _authService.currentUser;
        for (final oldFeatId in oldV01FeatureIds) {
          if (!createdDocIds.contains(oldFeatId)) {
            documents.remove(oldFeatId);
            LocalVaultService.deleteDocument(oldFeatId);
            if (user != null) {
              _firestoreService.deleteDocument(uid: user.uid, docId: oldFeatId);
            }
          }
        }
        for (final oldBeatId in oldV01BeatIds) {
          if (!createdDocIds.contains(oldBeatId) &&
              !otherReleaseBeatIds.contains(oldBeatId)) {
            documents.remove(oldBeatId);
            LocalVaultService.deleteDocument(oldBeatId);
            if (user != null) {
              _firestoreService.deleteDocument(uid: user.uid, docId: oldBeatId);
            }
          }
        }
      }
      final usedBaselineFallback =
          relDoc.sections.remove('used_baseline_fallback') == 'true';
      if (usedBaselineFallback) {
        for (final b in activeReleaseBeats) {
          for (final f in featuresForBeat(b.id)) {
            if (isFeatureActiveInRelease(f)) {
              f.sections['needs_ai_enrichment'] = 'true';
              _persistDocument(f);
            }
          }
        }
      }
      relDoc.sections['synced_engine_label'] = _activeEngineLabel;
      relDoc.sections['release_blueprint_json'] = jsonEncode(bp.toJson());
      _persistDocument(relDoc);
      _markExecutedInboxItemsImplemented(bp);

      // Auto-select the first Feature that has incomplete checkpoints (or Beat 1 / Feature 1)
      // before syncing project metadata so selected_beat_id / selected_feature_id are persisted together.
      _selectFirstIncompleteFeatureInActiveRelease();
      _syncActiveProjectMetadata();
      if (GeminiAgentClient.hasKey(_apiKey) ||
          GeminiAgentClient.testMockResponder != null) {
        final activeFeatureIds = <String>[
          for (final b in activeReleaseBeats)
            for (final f in featuresForBeat(b.id))
              if (isFeatureActiveInRelease(f)) f.id,
        ];
        if (activeFeatureIds.isNotEmpty) {
          final primaryFeatId = (_selectedFeatureId != null &&
                  activeFeatureIds.contains(_selectedFeatureId))
              ? _selectedFeatureId!
              : activeFeatureIds.first;
          final remainingFeatIds = activeFeatureIds
              .where((id) => id != primaryFeatId)
              .toList();
          final currentGen = ++_stepQueueGeneration;
          _pendingFeatureStepQueue.clear();
          if (GeminiAgentClient.testMockResponder == null) {
            final allOrderedFeatIds = <String>[
              primaryFeatId,
              ...remainingFeatIds,
            ];
            _pendingFeatureStepQueue.addAll(allOrderedFeatIds);
            unawaited(
              _prefetchRemainingFeatureStepsInBackground(
                allOrderedFeatIds,
                currentGen,
              ),
            );
          } else {
            final primaryTitle =
                documents[primaryFeatId]?.title ?? 'Feature 1';
            _agentProgressStep =
                'Synthesizing Feature #1 ($primaryTitle) so you can enter the Workarea immediately...';
            notifyListeners();

            await synthesizeFeatureHowToStepsWithAi(primaryFeatId);

            if (remainingFeatIds.isNotEmpty &&
                _stepQueueGeneration == currentGen) {
              _pendingFeatureStepQueue.addAll(remainingFeatIds);
              await _prefetchRemainingFeatureStepsInBackground(
                remainingFeatIds,
                currentGen,
              );
            }
          }
        }
      }
    } finally {
      _isAgentBusy = false;
      _agentProgressStep = null;
      notifyListeners();
    }
  }

  Future<void> _prefetchRemainingFeatureStepsInBackground([
    List<String>? initialFeatureIds,
    int? expectedGeneration,
  ]) async {
    final startGen = expectedGeneration ?? _stepQueueGeneration;
    if (initialFeatureIds != null) {
      _pendingFeatureStepQueue
        ..clear()
        ..addAll(
          initialFeatureIds.where(
            (id) => !_synthesizingFeatureIds.contains(id),
          ),
        );
      notifyListeners();
    }
    if (_isDrainingStepQueue) return;
    _isDrainingStepQueue = true;
    final startProjectId = _activeProjectId;
    final startReleaseId = _activeReleaseId;
    try {
      while (_pendingFeatureStepQueue.isNotEmpty) {
        if (_stepQueueGeneration != startGen ||
            _activeProjectId != startProjectId ||
            _activeReleaseId != startReleaseId) {
          if (_stepQueueGeneration == startGen) {
            _pendingFeatureStepQueue.clear();
            notifyListeners();
          }
          break;
        }
        final fId = _pendingFeatureStepQueue.removeAt(0);
        notifyListeners();
        final fDoc = documents[fId];
        if (fDoc == null) continue;
        if (fDoc.sections.remove('needs_ai_enrichment') == 'true') {
          final parentBeatTitle = (fDoc.parentId != null
                  ? documents[fDoc.parentId!]?.title
                  : null) ??
              'Core Loop Epic';
          await _enrichLiveFeatureWithAi(fId, parentBeatTitle);
        } else {
          await synthesizeFeatureHowToStepsWithAi(fId);
        }
      }
    } finally {
      _isDrainingStepQueue = false;
    }
  }

  bool isSynthesizingFeatureSteps(String featureId) =>
      _synthesizingFeatureIds.contains(featureId);

  bool isFeatureQueuedForSteps(String featureId) =>
      _pendingFeatureStepQueue.contains(featureId);

  bool hasSynthesizedFeatureStepsForActiveRelease(String featureId) {
    final feat = documents[featureId];
    if (feat == null || feat.sections['needs_ai_enrichment'] == 'true') {
      return false;
    }
    final engineLabel = _activeEngineLabel;
    final activeVer = activeReleaseVersionTag;
    final plainKey = '${featureId}_${activeVer}_$engineLabel';
    final bpKey = '${plainKey}_BP';
    final cppKey = '${plainKey}_CPP';
    if (_aiSynthesizedFeatureSteps.contains(plainKey) ||
        _aiSynthesizedFeatureSteps.contains(bpKey) ||
        _aiSynthesizedFeatureSteps.contains(cppKey)) {
      return true;
    }
    final states = FeatureStateNode.getStatesForDocument(feat);
    if (states.isEmpty) return false;
    final activeCp =
        states.where((s) => s.releaseVersion == activeVer).lastOrNull ??
            states.last;
    return activeCp.checklist.isNotEmpty &&
        activeCp.checklist.every(
          (t) =>
              t.children.isNotEmpty &&
              t.children.every((c) => c.codeTargetFile == 'custom_snippet'),
        );
  }

  bool isFeatureWaitingForStepsInLiveMode(String featureId) {
    if (GeminiAgentClient.testMockResponder != null) return false;
    if (hasSynthesizedFeatureStepsForActiveRelease(featureId)) return false;
    final feat = documents[featureId];
    return _pendingFeatureStepQueue.contains(featureId) ||
        feat?.sections['needs_ai_enrichment'] == 'true';
  }

  bool isFeatureBeingBuiltInLiveMode(String featureId) {
    if (GeminiAgentClient.testMockResponder != null) return false;
    return _synthesizingFeatureIds.contains(featureId) ||
        isFeatureWaitingForStepsInLiveMode(featureId);
  }

  int get backgroundStepSynthesisRemainingCount =>
      _pendingFeatureStepQueue.length + _synthesizingFeatureIds.length;

  static final RegExp _ledgerAssetTokenRegex = RegExp(
    r'\b(?:BP_[A-Za-z0-9_]+|IA_[A-Za-z0-9_]+|IMC_[A-Za-z0-9_]+|WBP_[A-Za-z0-9_]+|[A-Z][A-Za-z0-9_]+(?:Character|Controller|Pawn|Actor|Component|Spawner|Projectile|Weapon|Manager)\b|[A-Za-z0-9_]+\.(?:cs|gd|tscn|h|cpp))\b',
  );
  static final RegExp _scriptSymbolRegex = RegExp(
    r'\b(?:func|signal|void|IEnumerator)\s+([A-Za-z_][A-Za-z0-9_]*)\b',
  );

  /// Native Gemini Tool (`functionDeclarations`) for Stage 2 3-Area How-To synthesis (`synthesizeFeatureHowToStepsWithAi`).
  /// Enforces a single shared `primarySharedScriptOrScene` across all tasks and typed 3-Area sub-steps.
  static const Map<String, dynamic> commitFeatureHowToStepsTool = {
    'name': 'commit_feature_howto_steps',
    'description':
        'Commits the concrete, engine-specific 3-Area How-To sub-steps (Hierarchy, Inspector, Code, Verify) for every task in the active Feature checkpoint on one shared asset.',
    'parameters': {
      'type': 'OBJECT',
      'required': ['primarySharedScriptOrScene', 'tasks'],
      'properties': {
        'primarySharedScriptOrScene': {
          'type': 'STRING',
          'description':
              'The single shared Actor Blueprint, Prefab/MonoBehaviour, or Godot Scene/Script used across Task 1..N (e.g., "BP_PlayerCharacter", "PlayerController.cs", or "player.tscn / player.gd").',
        },
        'tasks': {
          'type': 'ARRAY',
          'items': {
            'type': 'OBJECT',
            'required': ['taskIndex', 'subSteps'],
            'properties': {
              'taskIndex': {'type': 'INTEGER'},
              'taskTitle': {
                'type': 'STRING',
                'description': LayersTextStyleGuide.taskGroupTitleSchemaDesc,
              },
              'subSteps': {
                'type': 'ARRAY',
                'items': {
                  'type': 'OBJECT',
                  'required': [
                    'title',
                    'stepPath',
                    'instruction',
                    'area1Hierarchy',
                    'area2Inspector',
                    'codeFormula',
                    'verifyResult',
                  ],
                  'properties': {
                    'title': {
                      'type': 'STRING',
                      'description':
                          LayersTextStyleGuide.runbookStepTitleSchemaDesc,
                    },
                    'stepPath': {
                      'type': 'STRING',
                      'description':
                          LayersTextStyleGuide.runbookStepPathSchemaDesc,
                    },
                    'instruction': {
                      'type': 'STRING',
                      'description':
                          LayersTextStyleGuide.runbookInstructionSchemaDesc,
                    },
                    'area1Hierarchy': {
                      'type': 'STRING',
                      'description':
                          'Optional Scene/Component hierarchy tree using ├─ / └─ when adding or modifying nodes/components (or "" if pure code step)',
                    },
                    'area2Inspector': {
                      'type': 'STRING',
                      'description':
                          'Inspector/Details bindings formatted as "Property: Value | Property2: Value2" using exact tuning parameter names',
                    },
                    'codeFormula': {
                      'type': 'STRING',
                      'description':
                          '2-6 lines of concrete engine code or node graph wiring using exact tuning variables and guard checks',
                    },
                    'verifyResult': {
                      'type': 'STRING',
                      'description':
                          LayersTextStyleGuide.causalTriggerResultSchemaDesc,
                    },
                  },
                },
              },
            },
          },
        },
      },
    },
  };

  /// Native Gemini Tool (`functionDeclarations`) for Stage 2 Single-Task "Tailor Steps" (`tailorTaskHowToSubSteps`).
  static const Map<String, dynamic> commitTailoredTaskSubStepsTool = {
    'name': 'commit_tailored_task_substeps',
    'description':
        'Commits tailored 3-Area How-To sub-steps for a single target task using the developer\'s exact scene/node/script names.',
    'parameters': {
      'type': 'OBJECT',
      'required': ['subSteps'],
      'properties': {
        'primarySharedScriptOrScene': {
          'type': 'STRING',
          'description':
              'Optional shared Actor Blueprint, Prefab/MonoBehaviour, or Godot Scene/Script specified by the developer.',
        },
        'subSteps': {
          'type': 'ARRAY',
          'items': {
            'type': 'OBJECT',
            'required': [
              'title',
              'stepPath',
              'instruction',
              'area1Hierarchy',
              'area2Inspector',
              'codeFormula',
              'verifyResult',
            ],
            'properties': {
              'title': {
                'type': 'STRING',
                'description': LayersTextStyleGuide.runbookStepTitleSchemaDesc,
              },
              'stepPath': {
                'type': 'STRING',
                'description': LayersTextStyleGuide.runbookStepPathSchemaDesc,
              },
              'instruction': {
                'type': 'STRING',
                'description':
                    LayersTextStyleGuide.runbookInstructionSchemaDesc,
              },
              'area1Hierarchy': {'type': 'STRING'},
              'area2Inspector': {'type': 'STRING'},
              'codeFormula': {'type': 'STRING'},
              'verifyResult': {
                'type': 'STRING',
                'description':
                    LayersTextStyleGuide.causalTriggerResultSchemaDesc,
              },
            },
          },
        },
      },
    },
  };

  /// Native Gemini Tool (`functionDeclarations`) for Stage 2 Playtest Bug Debugger (`_enrichPlaytestFixWithAi`).
  static const Map<String, dynamic> commitPlaytestFixTool = {
    'name': 'commit_playtest_fix',
    'description':
        'Commits a root-cause playtest bug fix with a concise [FIX] task title, optional tuning updates, a [PLAYTEST GUARD] rule, and sequential 3-Area engine fix steps.',
    'parameters': {
      'type': 'OBJECT',
      'required': ['playtestGuard', 'steps'],
      'properties': {
        'fixTaskTitle': {
          'type': 'STRING',
          'description':
              'Optional concise 2-4 word Title-Case fix task title (e.g., "[FIX] Wall Clip Clamp").',
        },
        'playtestGuard': {
          'type': 'STRING',
          'description': LayersTextStyleGuide.playtestGuardSchemaDesc,
        },
        'tuningUpdates': {
          'type': 'ARRAY',
          'description':
              'Optional updated numeric tuning parameters if the playtest issue requires clamping or retuning a variable.',
          'items': {
            'type': 'OBJECT',
            'required': ['variableName', 'value'],
            'properties': {
              'variableName': {'type': 'STRING'},
              'value': {'type': 'STRING'},
            },
          },
        },
        'steps': {
          'type': 'ARRAY',
          'items': {
            'type': 'OBJECT',
            'required': [
              'title',
              'stepPath',
              'instruction',
              'area1Hierarchy',
              'area2Inspector',
              'codeFormula',
              'verifyResult',
            ],
            'properties': {
              'title': {
                'type': 'STRING',
                'description': LayersTextStyleGuide.runbookStepTitleSchemaDesc,
              },
              'stepPath': {
                'type': 'STRING',
                'description': LayersTextStyleGuide.runbookStepPathSchemaDesc,
              },
              'instruction': {
                'type': 'STRING',
                'description':
                    LayersTextStyleGuide.runbookInstructionSchemaDesc,
              },
              'area1Hierarchy': {'type': 'STRING'},
              'area2Inspector': {'type': 'STRING'},
              'codeFormula': {'type': 'STRING'},
              'verifyResult': {
                'type': 'STRING',
                'description':
                    LayersTextStyleGuide.causalTriggerResultSchemaDesc,
              },
            },
          },
        },
      },
    },
  };

  /// Native Gemini Tool (`functionDeclarations`) for Stage 2 "+ Add Feature" in Left Outliner (`_enrichLiveFeatureWithAi`).
  static const Map<String, dynamic> commitLiveFeatureEnrichmentTool = {
    'name': 'commit_live_feature_enrichment',
    'description':
        'Enriches a newly added Feature card in the active Epic with its goal, doneWhen, checkpoint title, playtest gate, role-ordered tasks, numeric tuning parameters, and edge-case guards.',
    'parameters': {
      'type': 'OBJECT',
      'required': [
        'goal',
        'doneWhen',
        'checkpointTitle',
        'playtestGate',
        'tasks',
        'tuningParams',
        'edgeCases',
      ],
      'properties': {
        'goal': {
          'type': 'STRING',
          'description': LayersTextStyleGuide.changelogDeltaGoalSchemaDesc,
        },
        'inScope': {
          'type': 'ARRAY',
          'description': LayersTextStyleGuide.changelogDeltaInScopeSchemaDesc,
          'items': {'type': 'STRING'},
        },
        'doneWhen': {
          'type': 'STRING',
          'description': LayersTextStyleGuide.causalTriggerResultSchemaDesc,
        },
        'primarySharedScriptOrScene': {'type': 'STRING'},
        'checkpointTitle': {'type': 'STRING'},
        'playtestGate': {
          'type': 'STRING',
          'description': LayersTextStyleGuide.causalTriggerResultSchemaDesc,
        },
        'tasks': {
          'type': 'ARRAY',
          'description':
              'Sequential tasks ordered from stage_1_scene_or_data_foundation -> stage_2_mechanic_logic (1..N) -> stage_3_state_and_playtest_verify.',
          'items': {
            'type': 'OBJECT',
            'required': ['role', 'title'],
            'properties': {
              'role': {
                'type': 'STRING',
                'enum': [
                  'stage_1_scene_or_data_foundation',
                  'stage_2_mechanic_logic',
                  'stage_3_state_and_playtest_verify',
                ],
              },
              'title': {
                'type': 'STRING',
                'description': LayersTextStyleGuide.taskGroupTitleSchemaDesc,
              },
              'goal': {
                'type': 'STRING',
                'description': LayersTextStyleGuide.taskGroupGoalSchemaDesc,
              },
            },
          },
        },
        'tuningParams': {
          'type': 'ARRAY',
          'items': {
            'type': 'STRING',
            'description': LayersTextStyleGuide.tuningParamSchemaDesc,
          },
        },
        'edgeCases': {
          'type': 'ARRAY',
          'description': LayersTextStyleGuide.stateGuardSchemaDesc,
          'items': {'type': 'STRING'},
        },
      },
    },
  };

  /// Native Gemini Tool (`functionDeclarations`) for Stage 2 Feature Inbox `WHEN / WHERE / HOW` Triage (`_triageFeatureInboxItemWithAi`).
  static const Map<String, dynamic> commitInboxFeatureTriageTool = {
    'name': 'commit_inbox_feature_triage',
    'description':
        'Commits the 3-dimensional Feature Inbox triage (WHEN releaseTimingMode, WHERE integrationMode & targetBeatId, HOW tasks, tuningParams, edgeCases).',
    'parameters': {
      'type': 'OBJECT',
      'required': [
        'releaseTimingMode',
        'releaseTimingReasoning',
        'integrationMode',
        'targetBeatId',
        'placementReasoning',
        'featureTitle',
        'goal',
        'inScope',
        'doneWhen',
        'architectureHowSummary',
        'checkpointTitle',
        'playtestGate',
        'tasks',
        'tuningParams',
        'edgeCases',
      ],
      'properties': {
        'releaseTimingMode': {
          'type': 'STRING',
          'enum': ['now', 'splitNowAndFuture', 'futureRelease'],
        },
        'targetFuturePhase': {
          'type': 'STRING',
          'description':
              'Required ONLY when releaseTimingMode is splitNowAndFuture or futureRelease; omit when releaseTimingMode is now.',
          'enum': ['mvp', 'verticalSlice', 'fullProduction', 'postLaunch'],
        },
        'releaseTimingReasoning': {'type': 'STRING'},
        'integrationMode': {
          'type': 'STRING',
          'enum': [
            'newFeatureInEpic',
            'upgradeExistingFeature',
            'newEpicAndFeature',
          ],
        },
        'targetBeatId': {'type': 'STRING'},
        'targetFeatureId': {'type': 'STRING'},
        'newEpicTitle': {
          'type': 'STRING',
          'description': LayersTextStyleGuide.epicTitleSchemaDesc,
        },
        'placementReasoning': {'type': 'STRING'},
        'featureTitle': {
          'type': 'STRING',
          'description': LayersTextStyleGuide.featureTitleSchemaDesc,
        },
        'goal': {
          'type': 'STRING',
          'description': LayersTextStyleGuide.changelogDeltaGoalSchemaDesc,
        },
        'inScope': {
          'type': 'ARRAY',
          'description': LayersTextStyleGuide.changelogDeltaInScopeSchemaDesc,
          'items': {'type': 'STRING'},
        },
        'doneWhen': {
          'type': 'STRING',
          'description': LayersTextStyleGuide.causalTriggerResultSchemaDesc,
        },
        'primarySharedScriptOrScene': {'type': 'STRING'},
        'architectureHowSummary': {
          'type': 'ARRAY',
          'items': {'type': 'STRING'},
        },
        'checkpointTitle': {'type': 'STRING'},
        'playtestGate': {
          'type': 'STRING',
          'description': LayersTextStyleGuide.causalTriggerResultSchemaDesc,
        },
        'tasks': {
          'type': 'ARRAY',
          'description':
              'Sequential tasks ordered from stage_1_scene_or_data_foundation -> stage_2_mechanic_logic (1..N) -> stage_3_state_and_playtest_verify.',
          'items': {
            'type': 'OBJECT',
            'required': ['role', 'title'],
            'properties': {
              'role': {
                'type': 'STRING',
                'enum': [
                  'stage_1_scene_or_data_foundation',
                  'stage_2_mechanic_logic',
                  'stage_3_state_and_playtest_verify',
                ],
              },
              'title': {
                'type': 'STRING',
                'description': LayersTextStyleGuide.taskGroupTitleSchemaDesc,
              },
              'goal': {
                'type': 'STRING',
                'description': LayersTextStyleGuide.taskGroupGoalSchemaDesc,
              },
            },
          },
        },
        'tuningParams': {
          'type': 'ARRAY',
          'items': {
            'type': 'STRING',
            'description': LayersTextStyleGuide.tuningParamSchemaDesc,
          },
        },
        'edgeCases': {
          'type': 'ARRAY',
          'description': LayersTextStyleGuide.stateGuardSchemaDesc,
          'items': {'type': 'STRING'},
        },
        'futureCheckpointTitle': {'type': 'STRING'},
        'futureGoal': {
          'type': 'STRING',
          'description': LayersTextStyleGuide.changelogDeltaGoalSchemaDesc,
        },
        'futurePlaytestGate': {
          'type': 'STRING',
          'description': LayersTextStyleGuide.causalTriggerResultSchemaDesc,
        },
        'futureTasks': {
          'type': 'ARRAY',
          'description':
              'Future-phase upgrade tasks ordered from stage_1_scene_or_data_foundation -> stage_2_mechanic_logic (1..N) -> stage_3_state_and_playtest_verify.',
          'items': {
            'type': 'OBJECT',
            'required': ['role', 'title'],
            'properties': {
              'role': {
                'type': 'STRING',
                'enum': [
                  'stage_1_scene_or_data_foundation',
                  'stage_2_mechanic_logic',
                  'stage_3_state_and_playtest_verify',
                ],
              },
              'title': {
                'type': 'STRING',
                'description': LayersTextStyleGuide.taskGroupTitleSchemaDesc,
              },
              'goal': {
                'type': 'STRING',
                'description': LayersTextStyleGuide.taskGroupGoalSchemaDesc,
              },
            },
          },
        },
        'futureTuningParams': {
          'type': 'ARRAY',
          'items': {
            'type': 'STRING',
            'description': LayersTextStyleGuide.tuningParamSchemaDesc,
          },
        },
        'futureEdgeCases': {
          'type': 'ARRAY',
          'description': LayersTextStyleGuide.stateGuardSchemaDesc,
          'items': {'type': 'STRING'},
        },
      },
    },
  };

  /// Native Gemini Tool (`functionDeclarations`) for Stage 2 Code-to-Spec Reverse Sync (`syncFeatureTuningAndGuardsFromCode`).
  static const Map<String, dynamic> commitCodeToSpecSyncTool = {
    'name': 'commit_code_to_spec_sync',
    'description':
        'Extracts updated or newly exported tuning variables, primary script/scene asset, and [GUARD] rules from a pasted engine script so the feature spec stays in sync with code.',
    'parameters': {
      'type': 'OBJECT',
      'required': ['tuningUpdates', 'newGuards'],
      'properties': {
        'primarySharedScriptOrScene': {
          'type': 'STRING',
          'description':
              'Optional canonical class/script/scene identifier detected in the pasted code (e.g., "PlayerDashController (res://scripts/player_dash.gd)").',
        },
        'tuningUpdates': {
          'type': 'ARRAY',
          'items': {
            'type': 'OBJECT',
            'required': ['variableName', 'value'],
            'properties': {
              'variableName': {'type': 'STRING'},
              'value': {'type': 'STRING'},
            },
          },
        },
        'newGuards': {
          'type': 'ARRAY',
          'items': {
            'type': 'STRING',
            'description':
                'Safety/null/cooldown/bounds guard formatted as "[GUARD] condition — safe fallback".',
          },
        },
      },
    },
  };

  /// Builds a consolidated, deduplicated structural snapshot of `CP1..CP(upToIndex)`
  /// (short task badges, 1-line `area1Hierarchy` node tree, script functions/signals, and latest tuning vars)
  /// so `CP2..CP5+` upgrades, task tailoring, and playtest fixes extend existing nodes/scripts in-place
  /// without repeating verbose task sentences across releases.
  String _buildPriorCheckpointStructuralSnapshot(
    List<FeatureStateNode> states,
    int upToIndex,
  ) {
    final effectiveEnd = upToIndex < states.length ? upToIndex : states.length;
    if (effectiveEnd <= 0 || states.isEmpty) return '';

    final stageBadges = <String>[];
    final hierarchyNodes = <String>{};
    final scriptSymbols = <String>{};
    final latestTuningByKey = <String, String>{};
    final guardItems = <String>{};

    for (int i = 0; i < effectiveEnd; i++) {
      final cp = states[i];
      final shortTasks = cp.checklist
          .map((t) => LayersTextStyleGuide.formatConciseTaskTitle(t.text))
          .where((s) => s.isNotEmpty)
          .take(3)
          .join(', ');
      stageBadges.add(
        'CP${i + 1} (${cp.releaseVersion}: ${cp.cleanStageTitle}${shortTasks.isNotEmpty ? ' [$shortTasks]' : ''})',
      );

      for (final param in cp.tuningParams) {
        final clean = param.trim();
        if (clean.isEmpty) continue;
        final key = clean.split(':').first.trim().toLowerCase();
        if (key.isNotEmpty) {
          latestTuningByKey[key] = clean;
        }
      }
      for (final g in cp.edgeCases) {
        final cleanG = g.replaceAll(_leadingBracketTagsRegex, '').trim();
        if (cleanG.isNotEmpty) guardItems.add(cleanG);
      }

      for (final task in cp.checklist) {
        for (final sub in task.children) {
          final decoded =
              TaskHowToBlueprint.decodeThreeAreaNotes(sub.specNotes);
          final area1Text = decoded.area1Hierarchy?.trim() ?? '';
          if (area1Text.isNotEmpty) {
            for (final rawLine in area1Text.split('\n')) {
              final cleanNode =
                  rawLine.replaceAll(_treeGlyphPrefixRegex, '').trim();
              if (cleanNode.isNotEmpty) {
                hierarchyNodes.add(cleanNode);
              }
            }
          }
          final snippet = sub.codeSnippet ?? '';
          if (snippet.isNotEmpty) {
            for (final m in _scriptSymbolRegex.allMatches(snippet)) {
              final sym = m.group(1)?.trim() ?? '';
              if (sym.isNotEmpty) {
                scriptSymbols.add(sym);
              }
            }
          }
        }
      }
    }

    final lines = <String>[
      '- Built Checkpoints: ${stageBadges.join(' → ')}',
    ];
    if (hierarchyNodes.isNotEmpty) {
      final nodeList = hierarchyNodes.take(8).toList();
      final formattedTree = nodeList.length == 1
          ? nodeList.first
          : '${nodeList.first} > ${nodeList.skip(1).join(', ')}';
      lines.add(
        '- Existing Scene Hierarchy (extend in-place — do NOT recreate): $formattedTree',
      );
    }
    final symbolParts = <String>[
      if (scriptSymbols.isNotEmpty)
        'funcs=[${scriptSymbols.take(6).join(', ')}]',
      if (latestTuningByKey.isNotEmpty)
        'vars=[${latestTuningByKey.values.take(6).join(', ')}]',
      if (guardItems.isNotEmpty) 'guards=[${guardItems.take(4).join(', ')}]',
    ];
    if (symbolParts.isNotEmpty) {
      lines.add('- Existing Script Symbols & Vars: ${symbolParts.join(' | ')}');
    }
    return lines.join('\n');
  }

  /// Extracts a compact Cumulative Project Ledger entry for an already-synthesized feature
  /// so subsequent features reuse exact Actor/Scene/Script names and tuning variables without prose bloat.
  String _summarizeFeatureForProjectLedger(
    TierDocument featDoc,
    int orderNumber, {
    bool includeTuningVars = true,
    bool includePlannedScopeFallback = false,
  }) {
    final states = FeatureStateNode.getStatesForDocument(featDoc);
    final assetTokens = <String>{};
    final hierarchyNodes = <String>{};
    final primaryAsset = (featDoc.sections['primary_asset'] ?? '').trim();
    if (primaryAsset.isNotEmpty) {
      assetTokens.add(primaryAsset);
    }
    final pathTokens = <String>{};
    final tuningTokens = <String>{};

    for (final cp in states) {
      if (includeTuningVars) {
        for (final param in cp.tuningParams) {
          final clean = param.trim();
          if (clean.isNotEmpty) tuningTokens.add(clean);
        }
      }
      for (final task in cp.checklist) {
        for (final sub in task.children) {
          if (sub.codeTargetFile != 'custom_snippet') continue;
          final stepPath = (sub.codeLanguage ?? '').trim();
          if (stepPath.isNotEmpty && stepPath != 'custom_snippet') {
            pathTokens.add(stepPath);
            for (final m in _ledgerAssetTokenRegex.allMatches(stepPath)) {
              assetTokens.add(m.group(0)!);
            }
          }
          final decoded =
              TaskHowToBlueprint.decodeThreeAreaNotes(sub.specNotes);
          final area1Text = decoded.area1Hierarchy?.trim() ?? '';
          if (area1Text.isNotEmpty) {
            final areaLines = area1Text.split('\n');
            final rootLine = areaLines.first
                .replaceAll(_treeGlyphPrefixRegex, '')
                .trim();
            if (rootLine.isNotEmpty) {
              assetTokens.add(rootLine);
            }
            for (final rawLine in areaLines) {
              final cleanNode =
                  rawLine.replaceAll(_treeGlyphPrefixRegex, '').trim();
              if (cleanNode.isNotEmpty) {
                hierarchyNodes.add(cleanNode);
              }
            }
          }
          final combinedText =
              '${sub.text} ${decoded.cleanInstruction} ${sub.codeSnippet ?? ''}';
          for (final m in _ledgerAssetTokenRegex.allMatches(combinedText)) {
            assetTokens.add(m.group(0)!);
          }
        }
      }
    }

    if (assetTokens.isEmpty) {
      final firstTaskSource = (states.isNotEmpty &&
              states.first.checklist.isNotEmpty)
          ? '${states.first.checklist.first.text} ${featDoc.title}'
          : featDoc.title;
      final derivedAsset =
          TaskHowToBlueprint.deriveConcreteAssetName(firstTaskSource);
      if (derivedAsset.pascalName.isNotEmpty) {
        assetTokens.add(derivedAsset.pascalName);
      }
    }

    final parts = <String>[];
    if (assetTokens.isNotEmpty) {
      parts.add('assets=[${assetTokens.take(5).join(', ')}]');
    } else if (pathTokens.isNotEmpty) {
      parts.add('paths=[${pathTokens.take(2).join(', ')}]');
    }
    if (includePlannedScopeFallback && hierarchyNodes.length > 1) {
      final nodePreview = hierarchyNodes.take(4).toList();
      parts.add(
        'nodes=[${nodePreview.first} > ${nodePreview.skip(1).join(', ')}]',
      );
    }
    if (includePlannedScopeFallback) {
      final scopeItems = SectionTextUtils.resolveInScope(featDoc.sections)
          .take(2)
          .toList();
      if (scopeItems.isNotEmpty) {
        parts.add('scope=[${scopeItems.join(', ')}]');
      }
    }
    if (includeTuningVars && tuningTokens.isNotEmpty) {
      parts.add('vars=[${tuningTokens.take(5).join(', ')}]');
    }
    final summaryTail =
        parts.isNotEmpty ? parts.join(' | ') : 'foundation initialized';
    return '- Feature #$orderNumber "${featDoc.title}": $summaryTail';
  }

  /// Synthesizes bespoke, engine-specific 3-Area How-To Sub-Steps (`Hierarchy` -> `Inspector` -> `Code` -> `Verify`)
  /// for the active checkpoint of `featureId` using `_conversationModel` (`gemini-flash-latest`),
  /// reasoning through the project's cumulative asset state, same-Epic sibling boundaries, exact variable names, and previous checkpoints.
  Future<void> synthesizeFeatureHowToStepsWithAi(
    String featureId, {
    bool forceRefresh = false,
    bool unrealCppMode = false,
  }) async {
    _pendingFeatureStepQueue.remove(featureId);
    if (!GeminiAgentClient.hasKey(_apiKey) &&
        GeminiAgentClient.testMockResponder == null) {
      return;
    }
    final feat = documents[featureId];
    if (feat == null) return;
    final engineLabel = _activeEngineLabel;
    final engineHint = _activeEngineHint;
    final activeVer = activeReleaseVersionTag;
    final modeSuffix = engineLabel == 'UNREAL 5'
        ? (unrealCppMode ? '_CPP' : '_BP')
        : '';
    final synthKey = '${featureId}_${activeVer}_$engineLabel$modeSuffix';
    if (!forceRefresh &&
        (_aiSynthesizedFeatureSteps.contains(synthKey) ||
            _synthesizingFeatureIds.contains(featureId))) {
      return;
    }

    final states = FeatureStateNode.getStatesForDocument(feat);
    if (states.isEmpty) return;
    int cpIndex = states.indexWhere(
      (s) => s.releaseVersion == activeVer && !s.isCompleted,
    );
    if (cpIndex < 0) {
      cpIndex = states.lastIndexWhere((s) => s.releaseVersion == activeVer);
    }
    final effectiveCpIndex = cpIndex >= 0 ? cpIndex : 0;
    final cpNode = states[effectiveCpIndex];
    if (cpNode.checklist.isEmpty) return;

    // Skip if already customized with custom_snippet across tasks (unless forceRefresh)
    final alreadyCustom = cpNode.checklist.every(
      (t) =>
          t.children.isNotEmpty &&
          t.children.every((c) => c.codeTargetFile == 'custom_snippet'),
    );
    if (!forceRefresh && alreadyCustom) {
      _aiSynthesizedFeatureSteps.add(synthKey);
      return;
    }

    for (int tIdx = 0; tIdx < cpNode.checklist.length; tIdx++) {
      TaskHowToBlueprint.resolve(
        parentTask: cpNode.checklist[tIdx],
        taskIndex: tIdx,
        checkpointNode: cpNode,
        engineHint: engineHint,
        unrealCppMode: unrealCppMode,
        phase: _currentPhase,
      );
    }

    _synthesizingFeatureIds.add(featureId);
    notifyListeners();

    try {
      final projTitle = activeProject?.title ?? 'Game Prototype';
      final taskSummaries = <String>[];
      for (int tIdx = 0; tIdx < cpNode.checklist.length; tIdx++) {
        taskSummaries.add(
          'Task ${tIdx + 1} (taskIndex: $tIdx): "${cpNode.checklist[tIdx].text}"',
        );
      }

      // Determine project-wide feature build order so the agent knows what assets already exist vs. must be created first
      final allReleaseFeatures = <TierDocument>[
        for (final b in activeReleaseBeats) ...featuresForBeat(b.id),
      ];
      final featOrderIdx =
          allReleaseFeatures.indexWhere((f) => f.id == featureId);
      String classifyAssetArchetype(String title) {
        final lower = title.toLowerCase();
        if (RegExp(
          r'\b(?:hud|ui|widget|hotbar|menu|crosshair|selector|health\s*bar|inventory\s*bar|radar|minimap)\b',
        ).hasMatch(lower)) {
          return 'ui';
        }
        if (RegExp(
          r'\b(?:player|character|pawn|strafe|locomotion|dash|sprint|jump|crouch|slide|grapple|parry|aim|camera|footstep)\b',
        ).hasMatch(lower)) {
          return 'character';
        }
        if (RegExp(
          r'\b(?:arena|blockout|greybox|graybox|level|map|compound|sector|courtyard|room|world|stage|zone|biome|terrain)\b',
        ).hasMatch(lower)) {
          return 'level';
        }
        return 'actor';
      }

      final currentArchetype = classifyAssetArchetype(feat.title);
      final derivedAssetNames =
          TaskHowToBlueprint.deriveConcreteAssetName(feat.title);
      final featPascal = derivedAssetNames.pascalName.isNotEmpty
          ? derivedAssetNames.pascalName
          : 'GameplayFeature';
      final featSnake = derivedAssetNames.snakeName.isNotEmpty
          ? derivedAssetNames.snakeName
          : 'gameplay_feature';
      final hasPrecedingSameArchetype = featOrderIdx > 0 &&
          allReleaseFeatures
              .take(featOrderIdx)
              .any((f) => classifyAssetArchetype(f.title) == currentArchetype);
      final hasPrecedingCharacterFeature = featOrderIdx > 0 &&
          allReleaseFeatures
              .take(featOrderIdx)
              .any((f) => classifyAssetArchetype(f.title) == 'character');
      final isGreenfieldFirstFeature =
          (featOrderIdx <= 0 || !hasPrecedingSameArchetype) &&
              effectiveCpIndex == 0;
      final precedingFeatureTitles = featOrderIdx > 0
          ? allReleaseFeatures
              .take(featOrderIdx)
              .map((f) => '"${f.title}"')
              .toList()
          : const <String>[];
      final compactPrecedingSummary = precedingFeatureTitles.length <= 3
          ? precedingFeatureTitles.join(', ')
          : '${precedingFeatureTitles.first}, ..., ${precedingFeatureTitles.sublist(precedingFeatureTitles.length - 2).join(', ')} (${precedingFeatureTitles.length} total)';
      final engineAssetHint = switch (currentArchetype) {
        'character' => engineLabel == 'UNREAL 5'
            ? 'BP_PlayerCharacter (ACharacter) and IMC_Default'
            : (engineLabel == 'UNITY C#'
                ? 'PlayerController.cs / MonoBehaviour Prefab and CharacterController / Rigidbody'
                : 'player_character.tscn (CharacterBody) + player_character.gd and Project Input Map'),
        'ui' => engineLabel == 'UNREAL 5'
            ? 'WBP_$featPascal (UUserWidget) with CanvasPanel'
            : (engineLabel == 'UNITY C#'
                ? '${featPascal}Canvas.prefab / ${featPascal}UI.cs (PlayerController.cs / MonoBehaviour Prefab UI)'
                : '${featSnake}_hud.tscn (Control / CanvasLayer) + ${featSnake}_hud.gd'),
        'level' => engineLabel == 'UNREAL 5'
            ? (hasPrecedingCharacterFeature
                ? 'Level Map L_$featPascal (/Game/Maps/) with World Outliner Actors (Floor_*, Wall_*, BoxCollision / KillZVolume, and PlayerStart at (0, 0, 120) + BP_PlayerCharacter)'
                : 'Level Map L_$featPascal (/Game/Maps/) with World Outliner Actors (Floor_*, Wall_*, BoxCollision / KillZVolume, and PlayerStart at (0, 0, 120) with DefaultPawn in World Settings until BP_PlayerCharacter is built)')
            : (engineLabel == 'UNITY C#'
                ? (hasPrecedingCharacterFeature
                    ? 'Scene $featPascal.unity (Assets/Scenes/) with Floor/Wall GameObjects, Colliders, and PlayerController.cs / MonoBehaviour Prefab spawn at (0, 2, 0)'
                    : 'Scene $featPascal.unity (Assets/Scenes/) with Floor/Wall GameObjects, Colliders, and temporary test Capsule (Rigidbody + CapsuleCollider) at (0, 2, 0)')
                : (hasPrecedingCharacterFeature
                    ? 'Level Scene $featSnake.tscn (res://scenes/levels/) with StaticBody/CollisionShape floor/walls and player_character spawn at (0, 2, 0)'
                    : 'Level Scene $featSnake.tscn (res://scenes/levels/) with StaticBody/CollisionShape floor/walls and temporary test RigidBody + CollisionShape at (0, 2, 0)')),
        _ => engineLabel == 'UNREAL 5'
            ? 'BP_$featPascal (AActor) with StaticMeshComponent and Collision Component'
            : (engineLabel == 'UNITY C#'
                ? '$featPascal.prefab / ${featPascal}Controller.cs (PlayerController.cs / MonoBehaviour Prefab and Collider)'
                : '$featSnake.tscn (Node3D / Area3D / StaticBody3D) + $featSnake.gd'),
      };
      final needsFirstFeaturePlayerBootstrap =
          (currentArchetype == 'level' || currentArchetype == 'actor') &&
              !hasPrecedingCharacterFeature &&
              effectiveCpIndex == 0;
      final playerBootstrapLabel = engineLabel == 'UNREAL 5'
          ? (hasPrecedingCharacterFeature
              ? 'PlayerStart spawn point at (0, 0, 120) above the floor with BP_PlayerCharacter assigned in World Settings (do NOT make IMC_Default a floor component)'
              : 'PlayerStart spawn point at (0, 0, 120) above the floor with DefaultPawn assigned in World Settings so the map can be tested immediately before BP_PlayerCharacter exists (keep PlayerStart at (0, 0, 120); do NOT make IMC_Default a floor component)')
          : (engineLabel == 'UNITY C#'
              ? (hasPrecedingCharacterFeature
                  ? 'PlayerCharacter spawn point at (0, 2, 0) above the floor in the Scene Hierarchy'
                  : 'temporary test Capsule (Rigidbody + CapsuleCollider) at (0, 2, 0) above the floor in the Scene Hierarchy')
              : (hasPrecedingCharacterFeature
                  ? 'PlayerStart / player_character spawn node at (0, 2, 0) above the floor in the Main Scene'
                  : 'temporary test RigidBody + CollisionShape node at (0, 2, 0) above the floor in the Main Scene'));
      final projectBuildStateContext = isGreenfieldFirstFeature
          ? 'Project Build State: FIRST ${currentArchetype.toUpperCase()} FEATURE IN PROJECT (Greenfield Setup). On Task 1, explicitly instruct how to set up ${currentArchetype == 'level' ? 'the Level Map & World Outliner geometry' : (currentArchetype == 'character' ? 'the Character Blueprint / Prefab / Scene' : (currentArchetype == 'ui' ? 'the UI Widget / Canvas / Control Scene' : 'the Actor Blueprint / Prefab / Scene'))} ($engineAssetHint), specify its exact folder path, and ${needsFirstFeaturePlayerBootstrap ? 'include placing a $playerBootstrapLabel so pressing Play spawns the player landing on the floor.' : 'explain how to place or spawn it in the active level.'}'
          : 'Project Build State: Feature #${featOrderIdx + 1} in the release (preceded by: $compactPrecedingSummary). Reuse and extend existing project scenes/scripts ($engineAssetHint) for player-attached mechanics, or create this feature\'s dedicated scene/prefab/actor and connect it to the player.';

      // Build Epic-Scoped Cumulative Project Ledger:
      // 1) Root Project Anchor (`E01` foundational #1-#2 assets only, omitting cross-epic tuning vars)
      // 2) Same-Epic earlier siblings (with assets, scene nodes, planned scope fallback, and tuning vars)
      // Notice `featOrderIdx - 1` is NOT included when it belongs to a different Epic!
      final cumulativeLedgerLines = <String>[];
      if (featOrderIdx > 0) {
        final firstEpicParentId = allReleaseFeatures.first.parentId;
        final selectedPrecedingIndices = <int>{
          0,
          if (featOrderIdx > 1 &&
              allReleaseFeatures[1].parentId == firstEpicParentId)
            1,
          for (int pIdx = 0; pIdx < featOrderIdx; pIdx++)
            if (feat.parentId != null &&
                allReleaseFeatures[pIdx].parentId == feat.parentId)
              pIdx,
        }.toList()
          ..sort();
        final cappedIndices = selectedPrecedingIndices.length <= 5
            ? selectedPrecedingIndices
            : <int>[
                selectedPrecedingIndices[0],
                if (selectedPrecedingIndices.length > 1)
                  selectedPrecedingIndices[1],
                ...selectedPrecedingIndices
                    .sublist(selectedPrecedingIndices.length - 3),
              ];
        for (final pIdx in cappedIndices) {
          final isSameEpic = feat.parentId != null &&
              allReleaseFeatures[pIdx].parentId == feat.parentId;
          cumulativeLedgerLines.add(
            _summarizeFeatureForProjectLedger(
              allReleaseFeatures[pIdx],
              pIdx + 1,
              includeTuningVars: isSameEpic,
              includePlannedScopeFallback: isSameEpic,
            ),
          );
        }
      }

      // Build Consolidated Prior-Checkpoint Structural Snapshot (`CP1..CP(effectiveCpIndex)`)
      final priorCheckpointSnapshot = _buildPriorCheckpointStructuralSnapshot(
        states,
        effectiveCpIndex,
      );

      // Build Unified Same-Epic Multi-Feature Scope Boundaries (each sibling appears once)
      final sameEpicSiblingBoundaryLines = <String>[];
      if (feat.parentId != null) {
        final parentBeatDoc = documents[feat.parentId!];
        final beatSiblings = featuresForBeat(feat.parentId!);
        final selfBeatIdx = beatSiblings.indexWhere((s) => s.id == feat.id);
        if (beatSiblings.length > 1) {
          sameEpicSiblingBoundaryLines.add(
            'SAME-EPIC MULTI-FEATURE SCOPE BOUNDARIES (Epic "${parentBeatDoc?.title ?? 'Active Epic'}" contains ${beatSiblings.length} distinct Sibling Features — current is ${selfBeatIdx + 1} of ${beatSiblings.length}):',
          );
          for (int sIdx = 0; sIdx < beatSiblings.length; sIdx++) {
            final sib = beatSiblings[sIdx];
            if (sib.id == feat.id) continue;
            final isEarlierInEpic = selfBeatIdx >= 0 && sIdx < selfBeatIdx;
            if (isEarlierInEpic) {
              sameEpicSiblingBoundaryLines.add(
                '- Earlier Sibling in Same Epic (${sIdx + 1}/${beatSiblings.length}): "${sib.title}" -> ALREADY BUILT (reuse shared Actor/Script; see Ledger above).',
              );
            } else {
              final sibStates = FeatureStateNode.getStatesForDocument(sib);
              final sibScope = SectionTextUtils.resolveInScope(sib.sections)
                  .take(2)
                  .join(', ');
              final sibVars = <String>{
                for (final sibCp in sibStates) ...sibCp.tuningParams,
              }.take(3).join(', ');
              final details = <String>[
                if (sibScope.isNotEmpty) 'reserved scope=[$sibScope]',
                if (sibVars.isNotEmpty) 'reserved vars=[$sibVars]',
              ].join(', ');
              sameEpicSiblingBoundaryLines.add(
                '- Later Sibling in Same Epic (${sIdx + 1}/${beatSiblings.length}): "${sib.title}" -> QUEUED LATER IN THIS EPIC (do not implement here${details.isNotEmpty ? '; $details' : ''}).',
              );
            }
          }
        }
      }

      final cleanEdgeCases = cpNode.edgeCases
          .map((g) => g.replaceAll(_leadingBracketTagsRegex, '').trim())
          .where((g) => g.isNotEmpty)
          .toList();

      // Act 2: Full Production features see a compact Core Systems Reference (core Epic scripts & variable names)
      // so new content plugs into existing core systems instead of rebuilding them (Epic-Scoped Ledger hides them).
      final coreSystemsReferenceLines = <String>[];
      final parentEpicDoc =
          feat.parentId != null ? documents[feat.parentId!] : null;
      if (parentEpicDoc?.isFullProductionEpic ?? false) {
        for (final coreBeat
            in activeReleaseBeats.where((b) => !b.isFullProductionEpic)) {
          for (final coreFeat in featuresForBeat(coreBeat.id)) {
            final coreAsset = (coreFeat.sections['primary_asset'] ?? '').trim();
            final coreVarNames = <String>{
              for (final s in FeatureStateNode.getStatesForDocument(coreFeat))
                for (final tp in s.tuningParams)
                  tp.split(_tuningVarDelimiterRegex).first.trim(),
            }.where((n) => n.isNotEmpty).take(3).join(', ');
            if (coreAsset.isEmpty && coreVarNames.isEmpty) continue;
            coreSystemsReferenceLines.add(
              '- "${coreFeat.title}"${coreAsset.isNotEmpty ? ' -> $coreAsset' : ''}${coreVarNames.isNotEmpty ? ' (vars: $coreVarNames)' : ''}',
            );
          }
        }
      }

      final targetEngineMode = engineLabel == 'UNREAL 5'
          ? (unrealCppMode ? 'UNREAL 5 C++ (.h / .cpp)' : 'UNREAL 5 BLUEPRINTS')
          : (engineLabel == 'UNITY C#'
              ? 'UNITY C# (MonoBehaviour)'
              : 'GODOT 4 (GDScript 2.0)');

      final compactSpecBlock = _buildCompactWorkbenchSpecContext(
        includeFullDimensionBanner: true,
        targetEngineMode: targetEngineMode,
      );

      final phaseInstructionBlock = switch (_currentPhase) {
        ProductionPhase.prototype =>
          'ACTIVE PRODUCTION PHASE: 01 · PROTOTYPE (GREYBOX TESTBED)\n- Use primitive collision shapes, greybox shapes/sprites, and direct Inspector/Details variables.\n- Focus strictly on proving the core mechanic feel and playtest loop.\n- Keep greybox steps lean and cohesive (~2-3 sub-steps per task, ~6-9 total steps per feature; avoid 20-step bloat).',
        ProductionPhase.mvp =>
          'ACTIVE PRODUCTION PHASE: 02 · MVP (FUNCTIONAL DELTA UPGRADE)\n- Extend the existing v0.1 prototype script/Actor in-place (NEVER recreate from scratch).\n- Wire cross-system state, HUD counters, or progression loops.',
        ProductionPhase.verticalSlice =>
          'ACTIVE PRODUCTION PHASE: 03 · VERTICAL SLICE (GOLD STANDARD POLISH)\n- Attach Animation/VFX/SFX/Camera/UI feedback nodes and polish triggers to the existing mechanic without rewriting core movement/combat math.',
        ProductionPhase.fullProduction =>
          'ACTIVE PRODUCTION PHASE: 04 · FULL PRODUCTION (FULL-GAME BUILD-OUT)\n- Build the full-game feature on top of the finished core systems (reuse their scripts and variable names).\n- Match the Vertical Slice quality bar; use data-driven Resources / ScriptableObjects / DataAssets for content rosters.',
        ProductionPhase.postLaunch =>
          'ACTIVE PRODUCTION PHASE: 05 · POST-LAUNCH & LIVE OPS (PATCH & EXPANSION)\n- Apply surgical balance parameter adjustments, modular DLC/biome hooks, and regression guards without breaking existing save/state schemas.',
      };

      final featureGoalText = SectionTextUtils.resolveGoal(feat.sections);
      final featureInScopeItems =
          SectionTextUtils.resolveInScope(feat.sections);
      final existingPrimaryAsset = (cpNode.parameters['primarySharedScriptOrScene'] ??
              feat.sections['primary_asset'] ??
              '')
          .trim();
      final featureOwnScopeBlock = [
        if (featureGoalText.isNotEmpty) 'Feature Goal: "$featureGoalText"',
        if (featureInScopeItems.isNotEmpty)
          'Feature In Scope: ${featureInScopeItems.join(' | ')}',
        if (existingPrimaryAsset.isNotEmpty)
          'Existing Feature Primary Shared Asset (extend in-place across checkpoints): $existingPrimaryAsset',
        if (cpNode.playtestCondition.isNotEmpty)
          'Checkpoint Playtest Gate: "${cpNode.playtestCondition}"',
      ].join('\n');

      final codeFormulaModeGuide = currentArchetype == 'level'
          ? (engineLabel == 'UNREAL 5'
              ? '2-5 lines of World Outliner placement & Details Panel setup (e.g. `Place Actors → Cylinder ("Floor_Greenhouse")\\nStatic Mesh: /Engine/BasicShapes/Cylinder\\nTransform: Location = (0, 0, 0), Scale = (20.0, 20.0, 0.2)\\nCollision Preset: BlockAll`). NEVER wire `[Event BeginPlay] ──► [Set Actor Location / Set Actor Relative Scale3D]` to place static blockout floors/walls, NEVER prefix placed World Outliner Actor names with `SM_` (reserve `SM_` strictly for Static Mesh assets), pre-calculate literal numeric Location/Scale values from Active Tuning Parameters instead of undefined math expressions (`radius / 50.0`), and keep `PlayerStart` at `(0, 0, 120)` without conflicting coordinates'
              : '2-5 lines of Scene Hierarchy / Scene Tree placement & Inspector setup with literal numeric Position/Scale values derived from Active Tuning Parameters (do NOT write runtime Start()/_ready() code just to place static blockout floors/walls, and keep spawn at `(0, 2, 0)` without conflicting coordinates)')
          : (engineLabel == 'UNREAL 5'
              ? (unrealCppMode
                  ? '2-6 lines of concrete Unreal 5 C++ (.h / .cpp) code using `->`, `FTransform`, `FVector`, `CreateDefaultSubobject`, or `UPROPERTY` with the exact tuning variables and guard checks (NEVER Blueprint node arrows)'
                  : '2-6 lines of concrete Unreal 5 Blueprint Event Graph node wiring formatted as `[Event / Input Node] ──► [Function Node (Target: ..., Pin: Value)]` using `──►` / `└──►` arrows and exact tuning variables (NEVER C++ `->` pointer syntax or `FTransform`/`FVector` C++ constructors)')
              : '2-6 lines of concrete $targetEngineMode code using the exact tuning variables and guard checks');

      final prompt = '''
You are the Principal Game Engine Architect ($targetEngineMode) for "$projTitle".
Synthesize concrete, beginner-friendly 3-Area Engine How-To steps for Feature "${feat.title}" (Checkpoint "${cpNode.cleanStageTitle}").
${compactSpecBlock.isNotEmpty ? '$compactSpecBlock\n' : ''}${featureOwnScopeBlock.isNotEmpty ? '$featureOwnScopeBlock\n' : ''}$phaseInstructionBlock
$projectBuildStateContext
${cumulativeLedgerLines.isNotEmpty ? 'CUMULATIVE PROJECT LEDGER (Epic-Scoped & Root Project Anchors — reuse exact Actor/Scene/Script & Variable names):\n${cumulativeLedgerLines.join('\n')}' : ''}
${sameEpicSiblingBoundaryLines.isNotEmpty ? sameEpicSiblingBoundaryLines.join('\n') : ''}
${coreSystemsReferenceLines.isNotEmpty ? 'CORE SYSTEMS REFERENCE (finished STABLE core scripts — plug into these, NEVER rebuild them):\n${coreSystemsReferenceLines.join('\n')}' : ''}
Tasks:
${taskSummaries.join('\n')}
Active Tuning Parameters (MUST use exact variable names): ${cpNode.tuningParams.join(', ')}
Active Guards (MUST enforce in code without raw [TAG] brackets in prose): ${cleanEdgeCases.join(', ')}
${priorCheckpointSnapshot.isNotEmpty ? 'Previous Checkpoints Structural Snapshot (extend existing nodes & functions in-place):\n$priorCheckpointSnapshot' : ''}

CRITICAL MULTI-TASK CONTINUITY & ORDERING RULES:
- ONE SHARED ASSET ACROSS ALL TASKS: Choose ONE primary asset/class/scene for "${feat.title}" matching $targetEngineMode ($engineAssetHint). NEVER create a throwaway input/test actor in Task 1 just to replace it in Task 2, and NEVER use the word "canonical" in step titles or instructions.
- STRICT TASK-ROLE ALIGNMENT & NON-OVERLAPPING SLICES (ACROSS ALL ${cpNode.checklist.length} TASKS):
  * Each task MUST own a strictly non-overlapping slice of the feature—NEVER implement Task 2's perimeter walls or logic inside Task 1.
  * First Task (Task 1) builds ONLY the primary floor/scene/node/actor/prefab foundation in the level.
  * Middle Task(s) (Tasks 2..${cpNode.checklist.length > 2 ? cpNode.checklist.length - 1 : 2}) add secondary structural bounds or wire the core mechanic velocity, interaction, or simulation math inside that same asset using ${cpNode.tuningParams.join(', ')}.
  * Final Task (Task ${cpNode.checklist.length}) stays on that same asset to add a concrete trigger volume, state guard, clamp, or observable feedback cue (${cleanEdgeCases.join(', ')})—NEVER emit a passive "Verification" or "Testing" task title.

For each task (taskIndex: 0..${cpNode.checklist.length - 1}), include a concise mechanic-specific "taskTitle" (2-4 Title-Case words naming the exact scene node, UI widget, data resource, or gameplay calculation—never generic phrases like "Body & Collision", "Action & Math", "Cue & Boundary Clamp", or passive "Verification" titles) and return the sequential 3-Area sub-steps needed to implement and verify that task (zero artificial step count limits; in 01 · PROTOTYPE prefer 2-3 cohesive sub-steps per task so greybox features stay around 6-9 total steps):
- In `area2Inspector`, list ONLY the 1-3 properties modified in THIS specific task's component (never dump CharacterMovement properties onto a Capsule/Collider task).
- In `codeFormula`, emit $codeFormulaModeGuide.

Call `commit_feature_howto_steps` with the sequential 3-Area sub-steps for each task.''';

      final json = await GeminiAgentClient.generateJson(
        prompt: prompt,
        apiKey: _apiKey,
        preferredModel: _conversationModel,
        thinkingLevel: _thinkingLevel,
        temperature: 0.25,
        functionDeclarations: const [commitFeatureHowToStepsTool],
      );
      final primaryAsset =
          (json?['primarySharedScriptOrScene'] ?? '').toString().trim();
      if (primaryAsset.isNotEmpty) {
        feat.sections['primary_asset'] = primaryAsset;
        cpNode.parameters['primarySharedScriptOrScene'] = primaryAsset;
      } else if (existingPrimaryAsset.isNotEmpty) {
        cpNode.parameters['primarySharedScriptOrScene'] = existingPrimaryAsset;
      }
      final rawTasks = json?['tasks'];
      if (rawTasks is! List || rawTasks.isEmpty) return;

      final parsedTaskIndices = rawTasks
          .whereType<Map>()
          .map((t) => int.tryParse(t['taskIndex']?.toString() ?? '') ?? -1)
          .where((idx) => idx >= 0)
          .toList();
      final isOneBasedTaskIndexing = parsedTaskIndices.isNotEmpty &&
          !parsedTaskIndices.contains(0) &&
          parsedTaskIndices.every(
            (idx) => idx >= 1 && idx <= cpNode.checklist.length,
          );
      final useDirectPositionalMapping =
          rawTasks.length == cpNode.checklist.length;

      bool mutated = false;
      for (int listIdx = 0; listIdx < rawTasks.length; listIdx++) {
        final rawTask = rawTasks[listIdx];
        if (rawTask is! Map) continue;
        final rawIdx =
            int.tryParse(rawTask['taskIndex']?.toString() ?? '') ?? -1;
        final tIdx = useDirectPositionalMapping
            ? listIdx
            : (rawIdx < 0
                ? listIdx
                : (isOneBasedTaskIndexing ? rawIdx - 1 : rawIdx));
        if (tIdx < 0 || tIdx >= cpNode.checklist.length) continue;
        final parentTask = cpNode.checklist[tIdx];
        if (LayersTextStyleGuide.isLegacyTemplateTaskTitle(parentTask.text)) {
          final aiTaskTitle = LayersTextStyleGuide.stripLegacyTemplateTaskSuffix(
            (rawTask['taskTitle'] ?? '').toString().trim(),
          );
          final durMatch = RegExp(r'\(\d+h\)\s*$').firstMatch(parentTask.text);
          final durSuffix =
              durMatch != null ? ' ${durMatch.group(0)!.trim()}' : '';
          final withoutDur = durMatch != null
              ? parentTask.text.substring(0, durMatch.start).trim()
              : parentTask.text.trim();
          final dashIdx = withoutDur.indexOf(' — ');
          final existingGoalPart =
              dashIdx > 0 ? withoutDur.substring(dashIdx) : '';
          final cleanNewHead = aiTaskTitle.isNotEmpty
              ? aiTaskTitle
              : LayersTextStyleGuide.stripLegacyTemplateTaskSuffix(
                  dashIdx > 0
                      ? withoutDur.substring(0, dashIdx).trim()
                      : withoutDur,
                );
          parentTask.text = '$cleanNewHead$existingGoalPart$durSuffix';
          mutated = true;
        }
        final taskNum = tIdx + 1;
        final rawSubs = rawTask['subSteps'];
        if (rawSubs is! List || rawSubs.isEmpty) continue;

        final newChildren = <Subtask>[];
        for (int sIdx = 0; sIdx < rawSubs.length; sIdx++) {
          final item = rawSubs[sIdx];
          if (item is! Map) continue;
          final rawTitle = item['title']?.toString().trim() ?? '';
          final strippedTitle = rawTitle
              .replaceFirst(_stepHeaderPrefixRegex, '')
              .trim();
          final title = strippedTitle.isNotEmpty
              ? 'STEP $taskNum.${sIdx + 1} · $strippedTitle'
              : '';
          final path = item['stepPath']?.toString().trim() ?? '';
          final instr = item['instruction']?.toString().trim() ?? '';
          final area1 = item['area1Hierarchy']?.toString().trim() ?? '';
          final area2 = item['area2Inspector']?.toString().trim() ?? '';
          final code = item['codeFormula']?.toString().trim() ?? '';
          final verify = item['verifyResult']?.toString().trim() ?? '';
          if (instr.isEmpty && code.isEmpty) continue;
          final prevDone = sIdx < parentTask.children.length
              ? parentTask.children[sIdx].completed
              : parentTask.completed;
          final encodedNotes = TaskHowToBlueprint.encodeThreeAreaNotes(
            instruction: instr,
            area1Hierarchy: area1,
            area2Inspector: area2,
          );
          newChildren.add(
            Subtask(
              id: '${parentTask.id}_sub_${sIdx + 1}',
              text: title.isNotEmpty
                  ? title
                  : 'STEP $taskNum.${sIdx + 1} · IMPLEMENT STEP ${sIdx + 1}',
              specNotes: encodedNotes,
              codeSnippet: code,
              codeLanguage: path,
              verification: verify,
              codeTargetFile: 'custom_snippet',
              completed: prevDone,
            ),
          );
        }
        if (newChildren.isNotEmpty) {
          parentTask.children = newChildren;
          mutated = true;
        }
      }

      if (mutated) {
        _aiSynthesizedFeatureSteps.add(synthKey);
        TaskHowToBlueprint.clearCache();
        updateFeatureStates(featureId, states);
      }
    } finally {
      _synthesizingFeatureIds.remove(featureId);
      notifyListeners();
      if (_synthesizingFeatureIds.isEmpty &&
          _pendingFeatureStepQueue.isNotEmpty &&
          !_isDrainingStepQueue) {
        _prefetchRemainingFeatureStepsInBackground(null, _stepQueueGeneration);
      }
    }
  }

  /// Generates a drop-in `AGENTS.md` / `.cursorrules` context file for the Active Release (`v0.1`, `v0.2`, etc.)
  /// containing the release's engine architecture, Epic/Feature hierarchy, canonical tuning variable table,
  /// mandatory `[GUARD]` rules, and 3-Area implementation steps.
  String buildActiveReleaseCodingAgentMarkdown({bool unrealCppMode = false}) {
    final draft = _conceptDraft;
    final proj = activeProject;
    final rel = activeRelease;
    final activeVer = activeReleaseVersionTag;
    final engineHint = _activeEngineHint;
    final engineLabel = _activeEngineLabel;
    final effectiveEngineTarget = engineLabel == 'UNREAL 5'
        ? (unrealCppMode ? 'UNREAL 5 C++ (.h / .cpp)' : 'UNREAL 5 BLUEPRINTS')
        : (engineLabel == 'UNITY C#'
            ? 'UNITY C# (MonoBehaviour)'
            : 'GODOT 4 (GDScript 2.0)');
    final projectTitle = (draft != null && draft.title.trim().isNotEmpty)
        ? draft.title.trim()
        : (proj != null && proj.title.trim().isNotEmpty
            ? proj.title.trim()
            : 'LAYERS-Agentic Game Project');
    final relTitle = rel?.title ?? '$activeVer Prototype';

    final sb = StringBuffer();
    sb.writeln('# AGENTS.md — $projectTitle ($activeVer AI Coding Agent Context)');
    sb.writeln(
      '> Drop this file into your game repository root as `AGENTS.md` or `.cursorrules` so your AI coding agent builds strictly within the active release scope, variable names, and playtest guards.',
    );

    sb.writeln('\n## 1. Engine & Architecture Rules');
    sb.writeln('- **Project**: $projectTitle');
    sb.writeln('- **Active Release**: $relTitle (`$activeVer`)');
    sb.writeln('- **Target Engine**: $effectiveEngineTarget');
    final goalText = (draft != null && draft.goal.trim().isNotEmpty)
        ? draft.goal.trim()
        : (proj?.sections['goal'] ?? '').trim();
    if (goalText.isNotEmpty) {
      sb.writeln('- **Goal**: $goalText');
    }
    final gameSpecText = (draft != null && draft.gameSpec.isNotEmpty)
        ? draft.gameSpec.join(' · ')
        : (proj?.sections['game_spec'] ?? proj?.sections['gameSpec'] ?? '')
            .trim();
    if (gameSpecText.isNotEmpty) {
      sb.writeln('- **Game Spec**: $gameSpecText');
    }
    final pillarsText = (draft != null && draft.designPillars.isNotEmpty)
        ? draft.designPillars.join(' · ')
        : (proj?.sections['design_pillars'] ??
                proj?.sections['designPillars'] ??
                '')
            .replaceAll('\n', ' · ')
            .replaceAll('• ', '')
            .trim();
    if (pillarsText.isNotEmpty) {
      sb.writeln('- **Design Pillars**: $pillarsText');
    }
    final tradeOffsText = (draft != null && draft.tradeOffs.isNotEmpty)
        ? draft.tradeOffs.join(' · ')
        : (proj?.sections['trade_offs'] ?? proj?.sections['tradeOffs'] ?? '')
            .replaceAll('\n', ' · ')
            .replaceAll('• ', '')
            .trim();
    if (tradeOffsText.isNotEmpty) {
      sb.writeln('- **Engineering Trade-Offs**: $tradeOffsText');
    }
    final exclusionsText = (draft != null && draft.exclusions.isNotEmpty)
        ? draft.exclusions.join(' · ')
        : (proj?.sections['exclusions'] ?? '')
            .replaceAll('\n', ' · ')
            .replaceAll('• ', '')
            .trim();
    if (exclusionsText.isNotEmpty) {
      sb.writeln(
        '- **Explicitly Out of Scope (DO NOT BUILD IN $activeVer)**: $exclusionsText',
      );
    }
    final doneWhenText = (draft != null && draft.doneWhen.trim().isNotEmpty)
        ? draft.doneWhen.trim()
        : (proj?.sections['done_when'] ?? proj?.sections['doneWhen'] ?? '')
            .trim();
    if (doneWhenText.isNotEmpty) {
      sb.writeln('- **Release Done When**: $doneWhenText');
    }

    final beats = activeReleaseBeats;
    final allTuningRows = <({String feature, String variable, String value})>[];
    final allGuards = <({String feature, String guard})>[];

    sb.writeln('\n## 2. Active Release Hierarchy ($activeVer)');
    if (beats.isEmpty && _releaseBlueprint != null) {
      for (int bIdx = 0; bIdx < _releaseBlueprint!.beats.length; bIdx++) {
        final b = _releaseBlueprint!.beats[bIdx];
        final eNum = (bIdx + 1).toString().padLeft(2, '0');
        sb.writeln('- **E$eNum · ${b.title}**: ${b.goal}');
        for (final f in b.features.where((f) => f.included)) {
          final bpAsset = (f.primarySharedScriptOrScene ?? '').trim();
          final assetSuffix =
              bpAsset.isNotEmpty ? ' · Shared Asset: `$bpAsset`' : '';
          sb.writeln(
            '  - **${f.title}** (${f.estimatedHours}h$assetSuffix): ${f.goal}',
          );
        }
      }
    } else {
      for (int bIdx = 0; bIdx < beats.length; bIdx++) {
        final beat = beats[bIdx];
        final eNum = (bIdx + 1).toString().padLeft(2, '0');
        sb.writeln('- **E$eNum · ${beat.title}**');
        for (final feat in featuresForBeat(beat.id)) {
          final lc = (feat.sections['lifecycle'] ?? 'newFeature').toUpperCase();
          final p = getDocumentProgress(feat.id);
          final states = FeatureStateNode.getStatesForDocument(feat);
          final activeStates =
              states.where((s) => s.releaseVersion == activeVer).toList();
          final effectiveStates =
              activeStates.isNotEmpty ? activeStates : states;
          final featAsset = (feat.sections['primary_asset'] ??
                  (effectiveStates.isNotEmpty
                      ? effectiveStates
                          .last.parameters['primarySharedScriptOrScene']
                      : null) ??
                  '')
              .trim();
          final assetSuffix =
              featAsset.isNotEmpty ? ' · Shared Asset: `$featAsset`' : '';
          sb.writeln(
            '  - **${feat.title}** [`$lc` · $p% verified · ${feat.estimatedDuration}$assetSuffix]',
          );
          for (final cp in effectiveStates) {
            for (final t in cp.tuningParams) {
              final parts = t.split(':');
              final k = parts.first.trim();
              final v = parts.length > 1
                  ? parts.sublist(1).join(':').trim()
                  : '1.0';
              if (k.isNotEmpty) {
                allTuningRows.add((
                  feature: feat.title,
                  variable: k,
                  value: v,
                ));
              }
            }
            for (final g in cp.edgeCases) {
              if (g.trim().isNotEmpty) {
                allGuards.add((feature: feat.title, guard: g.trim()));
              }
            }
          }
        }
      }
    }

    sb.writeln('\n## 3. Canonical Tuning Variables & Inspector Bindings');
    sb.writeln(
      'Always use these exact variable identifiers across scripts, Inspector/Details panels, and scenes:',
    );
    if (allTuningRows.isEmpty) {
      sb.writeln('- *(No numeric tuning variables registered yet)*');
    } else {
      sb.writeln('| Feature | Variable Identifier | Default / Target Value |');
      sb.writeln('| :--- | :--- | :--- |');
      for (final row in allTuningRows) {
        sb.writeln('| ${row.feature} | `${row.variable}` | `${row.value}` |');
      }
    }

    sb.writeln('\n## 4. Mandatory Playtest & Edge-Case Guards');
    sb.writeln(
      'Enforce every guard below with an explicit early-return or clamp in your runtime update/input logic:',
    );
    if (allGuards.isEmpty) {
      sb.writeln('- *(No edge-case guards registered yet)*');
    } else {
      for (final g in allGuards) {
        sb.writeln('- **${g.feature}**: `${g.guard}`');
      }
    }

    sb.writeln('\n## 5. 3-Area Engine Implementation Blueprint ($effectiveEngineTarget)');
    for (int bIdx = 0; bIdx < beats.length; bIdx++) {
      final beat = beats[bIdx];
      final eNum = (bIdx + 1).toString().padLeft(2, '0');
      sb.writeln('\n### E$eNum · ${beat.title}');
      for (final feat in featuresForBeat(beat.id)) {
        final states = FeatureStateNode.getStatesForDocument(feat);
        final activeStates =
            states.where((s) => s.releaseVersion == activeVer).toList();
        final effectiveStates =
            activeStates.isNotEmpty ? activeStates : states;
        for (final cp in effectiveStates) {
          sb.writeln(
            '\n#### ${feat.title} — ${cp.cleanStageTitle} (${cp.releaseVersion})',
          );
          final cpAsset = (feat.sections['primary_asset'] ??
                  cp.parameters['primarySharedScriptOrScene'] ??
                  '')
              .trim();
          if (cpAsset.isNotEmpty) {
            sb.writeln('- **Primary Shared Asset**: `$cpAsset`');
          }
          sb.writeln('- **Playtest Gate**: ${cp.playtestCondition}');
          for (int tIdx = 0; tIdx < cp.checklist.length; tIdx++) {
            final task = cp.checklist[tIdx];
            final bp = TaskHowToBlueprint.resolve(
              parentTask: task,
              taskIndex: tIdx,
              checkpointNode: cp,
              engineHint: engineHint,
              unrealCppMode: unrealCppMode,
              phase: _currentPhase,
            );
            final doneMark = task.completed ? 'x' : ' ';
            sb.writeln(
              '- [$doneMark] **Task ${bp.numLabel}: ${bp.cleanTitle}** (`${bp.whereLocation}`)',
            );
            for (final sub in bp.subSteps) {
              final sMark = sub.subtask.completed ? 'x' : ' ';
              sb.writeln(
                '  - [$sMark] **${sub.stepNumberLabel}** — ${sub.instruction}',
              );
              if (sub.area1Hierarchy != null &&
                  sub.area1Hierarchy!.trim().isNotEmpty) {
                sb.writeln(
                  '    - **Area 1 (Hierarchy)**: `${sub.area1Hierarchy!.replaceAll('\n', ' / ')}`',
                );
              }
              if (sub.area2Inspector != null &&
                  sub.area2Inspector!.trim().isNotEmpty) {
                sb.writeln(
                  '    - **Area 2 (Inspector)**: `${sub.area2Inspector!.replaceAll('\n', ' | ')}`',
                );
              }
              if (sub.codeFormula.trim().isNotEmpty) {
                sb.writeln('    ```');
                for (final line in sub.codeFormula.trim().split('\n')) {
                  sb.writeln('    $line');
                }
                sb.writeln('    ```');
              }
              if (sub.verifyResult.trim().isNotEmpty) {
                sb.writeln('    - *Verify*: ${sub.verifyResult.trim()}');
              }
            }
          }
        }
      }
    }

    final evolutionLedger = buildCrossReleaseEvolutionLedger();
    if (evolutionLedger.isNotEmpty) {
      sb.writeln('\n## 6. Cross-Release Evolution & Tuning History');
      sb.writeln(
        '| Epic | Feature | Status | Checkpoint Progression | Tuning Evolution | Guards |',
      );
      sb.writeln('| :--- | :--- | :--- | :--- | :--- | :--- |');
      for (final row in evolutionLedger) {
        final cpText = row.checkpointProgression.isNotEmpty
            ? row.checkpointProgression.join(' → ')
            : row.originVersion;
        final tuneText = row.tuningDeltaSummary.isNotEmpty
            ? row.tuningDeltaSummary.join(', ')
            : '—';
        sb.writeln(
          '| ${row.epicCode} | **${row.featureTitle}** | `${row.lifecycle}` | $cpText | `$tuneText` | ${row.guardCount} |',
        );
      }
    }

    return sb.toString();
  }

  /// Builds a structured Cross-Release Evolution & Tuning Delta Ledger across all live and archived
  /// features in the project (`CP1 (v0.1)` -> `CP2 (v0.2)` -> `CP3 (v0.3)` -> `CP4 (v1.0+)`).
  List<
      ({
        String featureId,
        String featureTitle,
        String epicCode,
        String epicTitle,
        String lifecycle,
        String originVersion,
        String? pivotReason,
        List<String> checkpointProgression,
        List<String> tuningDeltaSummary,
        int guardCount,
      })> buildCrossReleaseEvolutionLedger() {
    final beats = activeReleaseBeats;
    final rows = <
        ({
          String featureId,
          String featureTitle,
          String epicCode,
          String epicTitle,
          String lifecycle,
          String originVersion,
          String? pivotReason,
          List<String> checkpointProgression,
          List<String> tuningDeltaSummary,
          int guardCount,
        })>[];

    for (int bIdx = 0; bIdx < beats.length; bIdx++) {
      final beat = beats[bIdx];
      final epicCode = 'E${(bIdx + 1).toString().padLeft(2, '0')}';
      for (final feat in featuresForBeat(beat.id, includeSuperseded: true)) {
        final lcRaw = feat.sections['lifecycle'] ?? 'newFeature';
        final lcBadge = switch (lcRaw) {
          'superseded' => 'ARCHIVED',
          'stable' => 'STABLE ✓',
          'upgrade' => 'UPGRADING',
          _ => 'NEW',
        };
        final originVer = (feat.sections['originVersion'] ?? 'v0.1').trim();
        final pivotReason = feat.sections['pivotReason']?.trim();
        final states = FeatureStateNode.getStatesForDocument(feat);
        final cpLabels = <String>[];
        final varHistory = <String, List<String>>{};
        final uniqueGuards = <String>{};

        for (int cpIdx = 0; cpIdx < states.length; cpIdx++) {
          final s = states[cpIdx];
          final ver = s.releaseVersion.trim().isNotEmpty
              ? s.releaseVersion.trim()
              : originVer;
          final checkGlyph = s.isCompleted ? '✓' : '○';
          cpLabels.add(
            'CP${cpIdx + 1} ($ver $checkGlyph: ${s.cleanStageTitle})',
          );
          for (final g in s.edgeCases) {
            if (g.trim().isNotEmpty) uniqueGuards.add(g.trim());
          }
          for (final param in s.tuningParams) {
            final colonIdx = param.indexOf(':');
            if (colonIdx > 0) {
              final k = param.substring(0, colonIdx).trim();
              final v = param.substring(colonIdx + 1).trim();
              if (k.isNotEmpty && v.isNotEmpty) {
                final list = varHistory.putIfAbsent(k, () => <String>[]);
                final entry = '$v ($ver)';
                if (list.isEmpty || list.last != entry) {
                  // Only append if value changed or first entry
                  final prevVal = list.isNotEmpty
                      ? list.last.split(' (').first.trim()
                      : null;
                  if (prevVal != v) {
                    list.add(entry);
                  }
                }
              }
            }
          }
        }

        final tuningDeltas = <String>[];
        for (final entry in varHistory.entries.take(4)) {
          if (entry.value.length > 1) {
            tuningDeltas.add('${entry.key}: ${entry.value.join(' → ')}');
          } else if (entry.value.isNotEmpty) {
            tuningDeltas.add(
              '${entry.key}: ${entry.value.first.split(' (').first}',
            );
          }
        }

        rows.add((
          featureId: feat.id,
          featureTitle: feat.title,
          epicCode: epicCode,
          epicTitle: beat.title,
          lifecycle: lcBadge,
          originVersion: originVer,
          pivotReason:
              (pivotReason != null && pivotReason.isNotEmpty) ? pivotReason : null,
          checkpointProgression: cpLabels,
          tuningDeltaSummary: tuningDeltas,
          guardCount: uniqueGuards.length,
        ));
      }
    }

    return rows;
  }

  /// Generates a focused, single-feature AI Coding Agent prompt (for Cursor, Claude Code, or Antigravity)
  /// containing only the selected Feature's 3-Area blueprint, exact tuning variable names, sibling variable
  /// references, mandatory `[GUARD]` rules, and Playtest Gate condition.
  String buildActiveFeatureCodingAgentPrompt(
    String featureId, {
    bool unrealCppMode = false,
  }) {
    final feat = documents[featureId];
    if (feat == null) return '';
    final draft = _conceptDraft;
    final proj = activeProject;
    final activeVer = activeReleaseVersionTag;
    final engineHint = _activeEngineHint;
    final engineLabel = _activeEngineLabel;
    final effectiveEngineTarget = engineLabel == 'UNREAL 5'
        ? (unrealCppMode ? 'UNREAL 5 C++ (.h / .cpp)' : 'UNREAL 5 BLUEPRINTS')
        : (engineLabel == 'UNITY C#'
            ? 'UNITY C# (MonoBehaviour)'
            : 'GODOT 4 (GDScript 2.0)');
    final projectTitle = (draft != null && draft.title.trim().isNotEmpty)
        ? draft.title.trim()
        : (proj != null && proj.title.trim().isNotEmpty
            ? proj.title.trim()
            : 'LAYERS-Agentic Game Project');

    final parentBeat =
        feat.parentId != null ? documents[feat.parentId!] : null;
    final beats = activeReleaseBeats;
    final beatIdx =
        parentBeat != null ? beats.indexWhere((b) => b.id == parentBeat.id) : 0;
    final eNum = ((beatIdx >= 0 ? beatIdx : 0) + 1).toString().padLeft(2, '0');
    final epicLabel = parentBeat != null
        ? 'E$eNum · ${parentBeat.title}'
        : 'E01 · Core Loop Epic';

    final states = FeatureStateNode.getStatesForDocument(feat);
    final activeStates =
        states.where((s) => s.releaseVersion == activeVer).toList();
    final cpNode = activeStates.isNotEmpty
        ? activeStates.last
        : (states.isNotEmpty ? states.last : null);

    final sb = StringBuffer();
    sb.writeln(
      '# AI CODING AGENT TASK PROMPT — ${feat.title} ($activeVer · $effectiveEngineTarget)',
    );
    sb.writeln(
      '> Implement this single feature in **$effectiveEngineTarget** using the exact variable names, scene hierarchy, and playtest guards below.',
    );

    sb.writeln('\n## 1. Feature Scope & Context');
    sb.writeln('- **Project**: $projectTitle (`$activeVer`)');
    sb.writeln('- **Target Engine**: $effectiveEngineTarget');
    sb.writeln('- **Epic**: $epicLabel');
    sb.writeln('- **Feature**: ${feat.title}');
    final featPrimaryAsset = (feat.sections['primary_asset'] ??
            cpNode?.parameters['primarySharedScriptOrScene'] ??
            '')
        .trim();
    if (featPrimaryAsset.isNotEmpty) {
      sb.writeln('- **Primary Shared Asset**: `$featPrimaryAsset`');
    }
    final rawGoal = (feat.sections['scope'] ?? feat.sections['goal'] ?? '').trim();
    if (rawGoal.isNotEmpty) {
      sb.writeln('- **Goal**: ${rawGoal.split('\n').first.replaceFirst(_goalPrefixRegex, '').trim()}');
    }
    if (cpNode != null && cpNode.coveredScope.isNotEmpty) {
      sb.writeln('- **In Scope**: ${cpNode.coveredScope.join(' · ')}');
    }
    if (cpNode != null && cpNode.playtestCondition.trim().isNotEmpty) {
      sb.writeln('- **Playtest Gate (Done When)**: ${cpNode.playtestCondition.trim()}');
    }
    final pillarsText = (draft != null && draft.designPillars.isNotEmpty)
        ? draft.designPillars.join(' · ')
        : (proj?.sections['design_pillars'] ??
                proj?.sections['designPillars'] ??
                '')
            .replaceAll('\n', ' · ')
            .replaceAll('• ', '')
            .trim();
    if (pillarsText.isNotEmpty) {
      sb.writeln('- **Design Pillars**: $pillarsText');
    }
    final tradeOffsText = (draft != null && draft.tradeOffs.isNotEmpty)
        ? draft.tradeOffs.join(' · ')
        : (proj?.sections['trade_offs'] ?? proj?.sections['tradeOffs'] ?? '')
            .replaceAll('\n', ' · ')
            .replaceAll('• ', '')
            .trim();
    if (tradeOffsText.isNotEmpty) {
      sb.writeln('- **Trade-Offs**: $tradeOffsText');
    }

    sb.writeln('\n## 2. Canonical Tuning Variables & Sibling Context');
    if (cpNode == null || cpNode.tuningParams.isEmpty) {
      sb.writeln('- *(No numeric tuning variables registered)*');
    } else {
      sb.writeln('### Active Feature Variables (`${feat.title}`)');
      for (final param in cpNode.tuningParams) {
        sb.writeln('- `$param`');
      }
    }
    if (parentBeat != null) {
      final siblingLines = <String>[];
      for (final sib in featuresForBeat(parentBeat.id)) {
        if (sib.id == feat.id) continue;
        final sibStates = FeatureStateNode.getStatesForDocument(sib);
        final sibAsset = (sib.sections['primary_asset'] ??
                (sibStates.isNotEmpty
                    ? sibStates.last.parameters['primarySharedScriptOrScene']
                    : null) ??
                '')
            .trim();
        final sibAssetSuffix =
            sibAsset.isNotEmpty ? ' `[shared asset: $sibAsset]`' : '';
        if (sibStates.isNotEmpty && sibStates.last.tuningParams.isNotEmpty) {
          siblingLines.add(
            '- **${sib.title}**$sibAssetSuffix: `${sibStates.last.tuningParams.join('`, `')}`',
          );
        } else if (sibAssetSuffix.isNotEmpty) {
          siblingLines.add('- **${sib.title}**$sibAssetSuffix');
        }
      }
      if (siblingLines.isNotEmpty) {
        sb.writeln('\n### Sibling Feature Variables in $epicLabel (Reuse Exact Identifiers)');
        for (final line in siblingLines) {
          sb.writeln(line);
        }
      }
    }

    sb.writeln('\n## 3. Mandatory Edge-Case & Playtest Guards');
    if (cpNode == null || cpNode.edgeCases.isEmpty) {
      sb.writeln('- *(No edge-case guards registered)*');
    } else {
      for (final g in cpNode.edgeCases) {
        sb.writeln('- `${g.trim()}`');
      }
    }

    if (cpNode != null) {
      sb.writeln('\n## 4. 3-Area Implementation Steps ($effectiveEngineTarget)');
      for (int tIdx = 0; tIdx < cpNode.checklist.length; tIdx++) {
        final task = cpNode.checklist[tIdx];
        final bp = TaskHowToBlueprint.resolve(
          parentTask: task,
          taskIndex: tIdx,
          checkpointNode: cpNode,
          engineHint: engineHint,
          unrealCppMode: unrealCppMode,
          phase: _currentPhase,
        );
        final doneMark = task.completed ? 'x' : ' ';
        sb.writeln(
          '- [$doneMark] **Task ${bp.numLabel}: ${bp.cleanTitle}** (`${bp.whereLocation}`)',
        );
        for (final sub in bp.subSteps) {
          final sMark = sub.subtask.completed ? 'x' : ' ';
          sb.writeln(
            '  - [$sMark] **${sub.stepNumberLabel}** — ${sub.instruction}',
          );
          if (sub.area1Hierarchy != null &&
              sub.area1Hierarchy!.trim().isNotEmpty) {
            sb.writeln(
              '    - **Area 1 (Hierarchy)**: `${sub.area1Hierarchy!.replaceAll('\n', ' / ')}`',
            );
          }
          if (sub.area2Inspector != null &&
              sub.area2Inspector!.trim().isNotEmpty) {
            sb.writeln(
              '    - **Area 2 (Inspector)**: `${sub.area2Inspector!.replaceAll('\n', ' | ')}`',
            );
          }
          if (sub.codeFormula.trim().isNotEmpty) {
            sb.writeln('    ```');
            for (final line in sub.codeFormula.trim().split('\n')) {
              sb.writeln('    $line');
            }
            sb.writeln('    ```');
          }
          if (sub.verifyResult.trim().isNotEmpty) {
            sb.writeln('    - *Verify*: ${sub.verifyResult.trim()}');
          }
        }
      }
    }

    return sb.toString();
  }

  /// Two-Way Engine Sync: Parses a developer's pasted GDScript, C#, or Unreal C++ script
  /// (using `gemini-flash-latest` when online + a deterministic multi-line regex parser fallback)
  /// to update changed numeric tuning variable values and append newly added `[GUARD]` checks
  /// directly onto the Feature's active checkpoint.
  Future<({int updatedVars, int addedGuards})>
      syncFeatureTuningAndGuardsFromCode(
    String featureId,
    String pastedCode,
  ) async {
    final feat = documents[featureId];
    final trimmedCode = pastedCode.trim();
    if (feat == null || trimmedCode.isEmpty) {
      return (updatedVars: 0, addedGuards: 0);
    }

    final states = FeatureStateNode.getStatesForDocument(feat);
    if (states.isEmpty) return (updatedVars: 0, addedGuards: 0);
    final activeVer = activeReleaseVersionTag;
    int cpIdx = states.lastIndexWhere((s) => s.releaseVersion == activeVer);
    if (cpIdx < 0) cpIdx = states.length - 1;
    final cpNode = states[cpIdx];

    final extractedTuning = <String, String>{};
    final extractedGuards = <String>[];
    String? extractedPrimaryAsset;

    // 1. Deterministic multi-line regex extraction FIRST (0 LLM tokens; handles Godot 4 @export, Unity [SerializeField], Unreal UPROPERTY across line breaks)
    String cleanNumericValue(String raw) {
      var val = raw
          .split('//')
          .first
          .split('#')
          .first
          .trim()
          .replaceAll(_trailingSemicolonRegex, '')
          .trim();
      // Strip trailing C#/C++ float 'f' suffix on numeric literals (e.g. 600.0f -> 600.0, 6f -> 6.0)
      final floatMatch = _floatSuffixRegex.firstMatch(val);
      if (floatMatch != null) {
        final numPart = floatMatch.group(1)!;
        val = numPart.contains('.') ? numPart : '$numPart.0';
      }
      return val;
    }

    // 1a. Multi-line Unity [SerializeField] / Unreal UPROPERTY(...) attribute on same or preceding line
    for (final m in _attrFieldRegex.allMatches(trimmedCode)) {
      final k = m.group(1)?.trim() ?? '';
      final v = cleanNumericValue(m.group(2) ?? '');
      if (k.isNotEmpty && v.isNotEmpty) {
        extractedTuning.putIfAbsent(k, () => v);
      }
    }

    // 1b. Godot 4 @export var / typed var declarations
    for (final m in _gdVarRegex.allMatches(trimmedCode)) {
      final k = m.group(1)?.trim() ?? '';
      final v = cleanNumericValue(m.group(2) ?? '');
      if (k.isNotEmpty && v.isNotEmpty) {
        extractedTuning.putIfAbsent(k, () => v);
      }
    }

    // 1c. Direct assignment match for any existing tuningParams keys
    for (final existing in cpNode.tuningParams) {
      final existingKey = existing.split(':').first.trim();
      if (existingKey.isEmpty) continue;
      final keyRegex = RegExp(
        r'\b' +
            RegExp.escape(existingKey) +
            r'\b(?:\s*:\s*[\w.]+)?\s*=\s*([^\n;#/]+)',
        multiLine: true,
        caseSensitive: false,
      );
      final match = keyRegex.firstMatch(trimmedCode);
      if (match != null) {
        final v = cleanNumericValue(match.group(1) ?? '');
        if (v.isNotEmpty) {
          extractedTuning[existingKey] = v;
        }
      }
    }

    // 1d. Guard comment extraction (// [GUARD] ..., # [GUARD] ..., // GUARD: ...)
    for (final m in _guardCommentRegex.allMatches(trimmedCode)) {
      final gText = m.group(1)?.trim() ?? '';
      if (gText.isNotEmpty) {
        final formatted = gText.startsWith('[') ? gText : '[GUARD] $gText';
        if (!extractedGuards.contains(formatted)) {
          extractedGuards.add(formatted);
        }
      }
    }

    // 2. AI fallback extraction pass via gemini-flash-latest ONLY when regex extracted 0 updates and 0 guards
    if (extractedTuning.isEmpty &&
        extractedGuards.isEmpty &&
        GeminiAgentClient.hasKey(_apiKey)) {
      final currentAsset = (feat.sections['primary_asset'] ??
              cpNode.parameters['primarySharedScriptOrScene'] ??
              '')
          .trim();
      final prompt = '''
You are a Game Engine Code-to-Spec Synchronizer ($_activeEngineLabel).
Compare the developer's pasted engine script against the Feature's current Tuning Parameters and Guards.
Feature: "${feat.title}"
${currentAsset.isNotEmpty ? 'Current Primary Shared Asset: $currentAsset\n' : ''}Current Tuning Parameters: ${cpNode.tuningParams.join(', ')}
Current Guards: ${cpNode.edgeCases.join(' | ')}

Pasted Engine Script:
```
$trimmedCode
```

Extract:
1. "primarySharedScriptOrScene": Optional canonical class/script/scene identifier detected in the pasted code.
2. "tuningUpdates": Any updated or newly exported numeric/boolean/string tuning variables from the script. Preserve existing variable names when they match.
3. "newGuards": Any new safety/null/cooldown/bounds guard checks in the script formatted as "[GUARD] condition — safe fallback".

Call `commit_code_to_spec_sync` with the extracted tuning updates and guards.''';
      final json = await GeminiAgentClient.generateJson(
        prompt: prompt,
        apiKey: _apiKey,
        preferredModel: _conversationModel,
        thinkingLevel: _thinkingLevel,
        temperature: 0.1,
        functionDeclarations: const [commitCodeToSpecSyncTool],
      );
      final rawAsset = json?['primarySharedScriptOrScene']?.toString().trim();
      if (rawAsset != null && rawAsset.isNotEmpty) {
        extractedPrimaryAsset = rawAsset;
      }
      final rawTuning = json?['tuningUpdates'];
      if (rawTuning is List) {
        for (final item in rawTuning) {
          if (item is Map) {
            final k = (item['variableName'] ?? item['name'] ?? '')
                .toString()
                .trim();
            final v = (item['value'] ?? '').toString().trim();
            if (k.isNotEmpty && v.isNotEmpty) {
              extractedTuning[k] = v;
            }
          } else {
            final text = item?.toString().trim() ?? '';
            final colonIdx = text.indexOf(':');
            if (colonIdx > 0) {
              final k = text.substring(0, colonIdx).trim();
              final v = text.substring(colonIdx + 1).trim();
              if (k.isNotEmpty && v.isNotEmpty) {
                extractedTuning[k] = v;
              }
            }
          }
        }
      }
      final rawGuards = json?['newGuards'];
      if (rawGuards is List) {
        for (final item in rawGuards) {
          final text = item?.toString().trim() ?? '';
          if (text.isNotEmpty) {
            extractedGuards.add(
              text.startsWith('[') ? text : '[GUARD] $text',
            );
          }
        }
      }
    }

    // 3. Apply extracted tuning updates and new guards to cpNode in-place
    int updatedVars = 0;
    int addedGuards = 0;

    final updatedTuningList = List<String>.from(cpNode.tuningParams);
    String normalizeVarKey(String k) =>
        k.toLowerCase().replaceAll(_nonAlphaNumRegex, '');

    for (final entry in extractedTuning.entries) {
      final normTarget = normalizeVarKey(entry.key);
      if (normTarget.isEmpty) continue;
      final existingIdx = updatedTuningList.indexWhere(
        (item) => normalizeVarKey(item.split(':').first) == normTarget,
      );
      if (existingIdx >= 0) {
        final canonicalKey =
            updatedTuningList[existingIdx].split(':').first.trim();
        final newEntry = '$canonicalKey: ${entry.value}';
        if (updatedTuningList[existingIdx] != newEntry) {
          updatedTuningList[existingIdx] = newEntry;
          updatedVars++;
        }
      } else {
        updatedTuningList.add('${entry.key}: ${entry.value}');
        updatedVars++;
      }
    }

    final updatedGuardsList = List<String>.from(cpNode.edgeCases);
    for (final g in extractedGuards) {
      final normG = g.toLowerCase().replaceAll(_whitespaceRegex, ' ').trim();
      final alreadyExists = updatedGuardsList.any(
        (existing) =>
            existing.toLowerCase().replaceAll(_whitespaceRegex, ' ').trim() ==
            normG,
      );
      if (!alreadyExists) {
        updatedGuardsList.add(g);
        addedGuards++;
      }
    }

    final hasNewPrimaryAsset = extractedPrimaryAsset != null &&
        extractedPrimaryAsset.isNotEmpty &&
        extractedPrimaryAsset !=
            (feat.sections['primary_asset'] ?? '').trim();

    if (updatedVars > 0 || addedGuards > 0 || hasNewPrimaryAsset) {
      cpNode.tuningParams = updatedTuningList;
      cpNode.edgeCases = updatedGuardsList;
      if (extractedPrimaryAsset != null && extractedPrimaryAsset.isNotEmpty) {
        feat.sections['primary_asset'] = extractedPrimaryAsset;
        cpNode.parameters['primarySharedScriptOrScene'] = extractedPrimaryAsset;
      }
      if (updatedTuningList.isNotEmpty) {
        final formattedTuning =
            updatedTuningList.map((t) => '• $t').join('\n');
        feat.sections['tuning'] = formattedTuning;
        feat.sections['variables'] = formattedTuning;
      }
      if (updatedGuardsList.isNotEmpty) {
        feat.sections['edge_cases'] =
            updatedGuardsList.map((e) => '• $e').join('\n');
      }
      TaskHowToBlueprint.clearCache();
      updateFeatureStates(featureId, states);
    }

    return (updatedVars: updatedVars, addedGuards: addedGuards);
  }

  void selectFeature(
    String featureId, {
    bool triggerAiSynthesis = true,
  }) {
    final feat = documents[featureId];
    if (feat == null) return;
    _selectedFeatureId = featureId;
    if (feat.parentId != null) {
      _selectedBeatId = feat.parentId;
    }
    if (_pendingFeatureStepQueue.remove(featureId)) {
      _pendingFeatureStepQueue.insert(0, featureId);
    }
    final proj = activeProject;
    if (proj != null) {
      proj.sections['selected_feature_id'] = featureId;
      if (_selectedBeatId != null) {
        proj.sections['selected_beat_id'] = _selectedBeatId!;
      }
      _persistDocument(proj, debounce: true);
    }
    notifyListeners();
    if (triggerAiSynthesis &&
        (GeminiAgentClient.hasKey(_apiKey) ||
            GeminiAgentClient.testMockResponder != null)) {
      if (_synthesizingFeatureIds.contains(featureId)) {
        return;
      }
      if (hasSynthesizedFeatureStepsForActiveRelease(featureId)) {
        _pendingFeatureStepQueue.remove(featureId);
        return;
      }
      if (_synthesizingFeatureIds.isNotEmpty) {
        _pendingFeatureStepQueue.remove(featureId);
        _pendingFeatureStepQueue.insert(0, featureId);
        notifyListeners();
        return;
      }
      if (feat.sections.remove('needs_ai_enrichment') == 'true') {
        final parentBeatTitle = (feat.parentId != null
                ? documents[feat.parentId!]?.title
                : null) ??
            'Core Loop Epic';
        _enrichLiveFeatureWithAi(featureId, parentBeatTitle);
        return;
      }
      final states = FeatureStateNode.getStatesForDocument(feat);
      final activeVer = activeReleaseVersionTag;
      final activeCp = states.isNotEmpty
          ? (states.where((s) => s.releaseVersion == activeVer).lastOrNull ??
              states.last)
          : null;
      final alreadySynthesized = activeCp != null &&
          activeCp.checklist.isNotEmpty &&
          activeCp.checklist.every(
            (t) =>
                t.children.isNotEmpty &&
                t.children.every((c) => c.codeTargetFile == 'custom_snippet'),
          );
      if (!alreadySynthesized) {
        synthesizeFeatureHowToStepsWithAi(featureId);
      }
    }
  }

  void updateFeatureStates(String featureId, List<FeatureStateNode> states) {
    final feat = documents[featureId];
    if (feat == null) return;
    if (states.any((s) => !s.isCompleted) &&
        feat.sections['lifecycle'] == FeatureLifecycleStatus.stable.name) {
      feat.sections['lifecycle'] = states.length > 1
          ? FeatureLifecycleStatus.upgrade.name
          : FeatureLifecycleStatus.newFeature.name;
      feat.sections['activeReleaseVersion'] = activeReleaseVersionTag;
    }
    FeatureStateNode.saveStatesToDocument(feat, states);
    if (states.isNotEmpty) {
      final activeVer = activeReleaseVersionTag;
      final activeCp = states.firstWhere(
        (s) => s.releaseVersion == activeVer && !s.isCompleted,
        orElse: () => states.lastWhere(
          (s) => s.releaseVersion == activeVer,
          orElse: () => states.firstWhere(
            (s) => !s.isCompleted,
            orElse: () => states.last,
          ),
        ),
      );
      if (activeCp.tuningParams.isNotEmpty) {
        final formattedTuning =
            activeCp.tuningParams.map((p) => '• $p').join('\n');
        feat.sections['tuning'] = formattedTuning;
        feat.sections['variables'] = formattedTuning;
      }
      if (activeCp.edgeCases.isNotEmpty) {
        feat.sections['edge_cases'] =
            activeCp.edgeCases.map((e) => '• $e').join('\n');
      }
      final bp = _releaseBlueprint;
      if (bp != null) {
        final primaryAsset = (feat.sections['primary_asset'] ?? '').trim();
        for (final b in bp.beats) {
          for (final f in b.features) {
            if (f.id == featureId ||
                (f.title.toLowerCase().trim() ==
                        feat.title.toLowerCase().trim() &&
                    b.id == feat.parentId)) {
              if (activeCp.tuningParams.isNotEmpty) {
                f.tuningParams = List<String>.from(activeCp.tuningParams);
              }
              if (activeCp.edgeCases.isNotEmpty) {
                f.edgeCases = List<String>.from(activeCp.edgeCases);
              }
              if (primaryAsset.isNotEmpty) {
                f.primarySharedScriptOrScene = primaryAsset;
              }
              if (f.checkpoints.isNotEmpty) {
                final cpIdx = f.checkpoints.lastIndexWhere(
                  (c) => c.releaseVersion == activeCp.releaseVersion,
                );
                final targetIdx = cpIdx >= 0 ? cpIdx : f.checkpoints.length - 1;
                final oldCp = f.checkpoints[targetIdx];
                final updatedCps =
                    List<ProposedCheckpointBlueprint>.from(f.checkpoints);
                updatedCps[targetIdx] = ProposedCheckpointBlueprint(
                  title: oldCp.title,
                  playtestCriteria: oldCp.playtestCriteria,
                  tasks: [for (final t in activeCp.checklist) t.text],
                  coveredScope: activeCp.coveredScope.isNotEmpty
                      ? List<String>.from(activeCp.coveredScope)
                      : oldCp.coveredScope,
                  tuningParams: List<String>.from(activeCp.tuningParams),
                  edgeCases: List<String>.from(activeCp.edgeCases),
                  releaseVersion: oldCp.releaseVersion,
                );
                f.checkpoints = updatedCps;
              }
              break;
            }
          }
        }
      }
    }
    TaskHowToBlueprint.clearCache();
    _persistDocument(feat, debounce: true);
    notifyListeners();
  }

  /// Propagates a variable identifier rename (`oldIdentifier` -> `newIdentifier`)
  /// across all Features, Checkpoints, Tuning Lists, Playtest Guards, and 3-Area
  /// Steps (`sub.text`, `sub.specNotes`, `sub.codeSnippet`, `sub.verification`)
  /// in the active project using exact word-boundary matching.
  /// Returns the number of Feature documents updated.
  int propagateVariableRenameAcrossProject(
    String oldIdentifier,
    String newIdentifier,
  ) {
    final oldId = oldIdentifier.trim();
    final newId = newIdentifier.trim();
    if (oldId.isEmpty || newId.isEmpty || oldId == newId) return 0;

    final idRegex = RegExp(r'\b' + RegExp.escape(oldId) + r'\b');
    int updatedFeatureCount = 0;

    bool replaceSubtaskTree(Subtask node) {
      var changed = false;
      if (idRegex.hasMatch(node.text)) {
        node.text = node.text.replaceAll(idRegex, newId);
        changed = true;
      }
      if (node.specNotes != null && idRegex.hasMatch(node.specNotes!)) {
        node.specNotes = node.specNotes!.replaceAll(idRegex, newId);
        changed = true;
      }
      if (node.codeSnippet != null && idRegex.hasMatch(node.codeSnippet!)) {
        node.codeSnippet = node.codeSnippet!.replaceAll(idRegex, newId);
        changed = true;
      }
      if (node.verification != null && idRegex.hasMatch(node.verification!)) {
        node.verification = node.verification!.replaceAll(idRegex, newId);
        changed = true;
      }
      for (final child in node.children) {
        if (replaceSubtaskTree(child)) {
          changed = true;
        }
      }
      return changed;
    }

    // Collect all feature documents in the active project
    final projectFeatureIds = <String>{};
    for (final rel in projectReleases) {
      for (final bId in rel.childrenIds) {
        final beat = documents[bId];
        if (beat == null) continue;
        for (final fId in beat.childrenIds) {
          if (documents[fId]?.tier == TierType.feature) {
            projectFeatureIds.add(fId);
          }
        }
      }
    }

    for (final fId in projectFeatureIds) {
      final feat = documents[fId];
      if (feat == null) continue;
      var featChanged = false;

      final states = FeatureStateNode.getStatesForDocument(feat);
      for (final cp in states) {
        for (int i = 0; i < cp.tuningParams.length; i++) {
          if (idRegex.hasMatch(cp.tuningParams[i])) {
            cp.tuningParams[i] = cp.tuningParams[i].replaceAll(idRegex, newId);
            featChanged = true;
          }
        }
        for (int i = 0; i < cp.edgeCases.length; i++) {
          if (idRegex.hasMatch(cp.edgeCases[i])) {
            cp.edgeCases[i] = cp.edgeCases[i].replaceAll(idRegex, newId);
            featChanged = true;
          }
        }
        if (idRegex.hasMatch(cp.trigger)) {
          cp.trigger = cp.trigger.replaceAll(idRegex, newId);
          featChanged = true;
        }
        for (final task in cp.checklist) {
          if (replaceSubtaskTree(task)) {
            featChanged = true;
          }
        }
      }

      for (final key in feat.sections.keys.toList()) {
        if (key == 'states' || key == 'feature_states_json') continue;
        final val = feat.sections[key];
        if (val != null && idRegex.hasMatch(val)) {
          feat.sections[key] = val.replaceAll(idRegex, newId);
          featChanged = true;
        }
      }

      if (featChanged) {
        FeatureStateNode.saveStatesToDocument(feat, states);
        _persistDocument(feat, debounce: true);
        updatedFeatureCount++;
      }
    }

    if (_releaseBlueprint != null) {
      var bpChanged = false;
      for (final b in _releaseBlueprint!.beats) {
        for (final f in b.features) {
          for (int i = 0; i < f.tuningParams.length; i++) {
            if (idRegex.hasMatch(f.tuningParams[i])) {
              f.tuningParams[i] = f.tuningParams[i].replaceAll(idRegex, newId);
              bpChanged = true;
            }
          }
          for (int i = 0; i < f.edgeCases.length; i++) {
            if (idRegex.hasMatch(f.edgeCases[i])) {
              f.edgeCases[i] = f.edgeCases[i].replaceAll(idRegex, newId);
              bpChanged = true;
            }
          }
          if (f.checkpoints.isNotEmpty) {
            final updatedCps = <ProposedCheckpointBlueprint>[];
            for (final cp in f.checkpoints) {
              var cpChanged = false;
              final newTuning = [
                for (final t in cp.tuningParams)
                  () {
                    if (idRegex.hasMatch(t)) {
                      cpChanged = true;
                      return t.replaceAll(idRegex, newId);
                    }
                    return t;
                  }(),
              ];
              final newEdges = [
                for (final g in cp.edgeCases)
                  () {
                    if (idRegex.hasMatch(g)) {
                      cpChanged = true;
                      return g.replaceAll(idRegex, newId);
                    }
                    return g;
                  }(),
              ];
              final newTasks = [
                for (final taskText in cp.tasks)
                  () {
                    if (idRegex.hasMatch(taskText)) {
                      cpChanged = true;
                      return taskText.replaceAll(idRegex, newId);
                    }
                    return taskText;
                  }(),
              ];
              var newCriteria = cp.playtestCriteria;
              if (idRegex.hasMatch(newCriteria)) {
                newCriteria = newCriteria.replaceAll(idRegex, newId);
                cpChanged = true;
              }
              if (cpChanged) {
                bpChanged = true;
                updatedCps.add(
                  ProposedCheckpointBlueprint(
                    title: cp.title,
                    playtestCriteria: newCriteria,
                    tasks: newTasks,
                    coveredScope: cp.coveredScope,
                    tuningParams: newTuning,
                    edgeCases: newEdges,
                    releaseVersion: cp.releaseVersion,
                  ),
                );
              } else {
                updatedCps.add(cp);
              }
            }
            f.checkpoints = updatedCps;
          }
        }
      }
      if (bpChanged) {
        _syncActiveProjectMetadata();
      }
    }

    TaskHowToBlueprint.clearCache();
    if (updatedFeatureCount > 0) {
      notifyListeners();
    }
    return updatedFeatureCount;
  }

  /// Advances to the next queued Release in the current Production Phase, or unlocks the
  /// next Production Phase once the current phase's releases are completed:
  /// - Phase 1 (Prototype) complete -> Phase 2 (MVP Track: 1 MVP Release per Core Loop Beat)
  /// - Phase 2 (MVP Track) complete -> Phase 3 (Vertical Slice: 1 Polished Gold Standard Level)
  /// - Phase 3 (Vertical Slice) complete -> Phase 4 (Full Production: World & Content Expansion)
  Future<void> advanceToNextRelease({
    bool transitionToGateStage = true,
    bool agentReasonedProgressive = false,
  }) async {
    final proj = activeProject;
    if (proj == null) return;
    repackProjectReleasesSequentially(proj, pruneAllUnbuilt: true);
    final releases = projectReleases;
    if (releases.isEmpty) return;

    _lastReleaseRetrospective = buildActiveReleaseRetrospective();

    Future<void> openGateAndRecordRetro(String targetRelId) async {
      await openReleasePlanGate(
        releaseId: targetRelId,
        transitionToGateStage: transitionToGateStage,
      );
      if (_releaseBlueprint != null) {
        notifyListeners();
      }
    }

    final currentIdx = releases.indexWhere((r) => r.id == _activeReleaseId);
    final nextIdx = currentIdx + 1;
    if (currentIdx >= 0 && nextIdx < releases.length) {
      final nextRel = releases[nextIdx];
      // When planning a progressive release from the Co-Pilot, only reuse a queued release if it is still unbuilt.
      if (!agentReasonedProgressive || nextRel.childrenIds.isEmpty) {
        final phaseStr = nextRel.sections['phase'];
        if (phaseStr != null && phaseStr.isNotEmpty) {
          for (final p in ProductionPhase.values) {
            if (p.name == phaseStr) {
              _currentPhase = p;
              break;
            }
          }
        }
        await openGateAndRecordRetro(nextRel.id);
        return;
      }
    }

    // Current Phase has no more queued releases — create ONLY 1 single next Release on demand!
    final currentRel = activeRelease ?? releases.last;
    final allocated = _allocateNextReleaseIdAndIndex(proj);
    final newIndex = allocated.index;
    final newRelId = allocated.id;

    if (_currentPhase == ProductionPhase.prototype &&
        currentRel.sections['prototypePart'] == '1') {
      final part2Title = currentRel.sections['splitPrototypePart2Title'] ??
          'v0.$newIndex: Prototype — Part 2: Progression & Loop Reset';
      final newRelDoc = TierDocument(
        id: newRelId,
        title: part2Title,
        tier: TierType.release,
        parentId: proj.id,
        sections: {
          'versionTag': 'v0.$newIndex',
          'releaseScope': ReleaseScope.prototype.name,
          'phase': ProductionPhase.prototype.name,
          'prototypePart': '2',
          'scope':
              'Goal: Complete the remaining Core Loop Epics for the ${proj.title} prototype.\n\nIn Scope:\n• Remaining Core Loop Epics from ${proj.title}\n\nDone When: Full prototype core loop connects end-to-end.',
        },
      );
      documents[newRelId] = newRelDoc;
      _persistDocument(newRelDoc);
      proj.childrenIds.add(newRelId);
      _syncActiveProjectMetadata();
      await openGateAndRecordRetro(newRelId);
      return;
    }

    if (agentReasonedProgressive) {
      final nextPhase = inferNextProgressivePhase();
      _currentPhase = nextPhase;
      final nextScope = _releaseScopeForPhase(nextPhase);
      final existingFullProdCount = releases
          .where((r) => releasePhaseFor(r) == ProductionPhase.fullProduction)
          .length;
      final existingPostLaunchCount = releases
          .where((r) => releasePhaseFor(r) == ProductionPhase.postLaunch)
          .length;
      final fullProdPass = existingFullProdCount + 1;
      final postLaunchPass = existingPostLaunchCount + 1;
      final isLaunch = nextPhase == ProductionPhase.fullProduction &&
          isNextReleaseV1Launch;
      final isLegacyFullProd = nextPhase == ProductionPhase.fullProduction &&
          fullProductionCoverage().isLegacy;
      final effectiveVer = nextPhase == ProductionPhase.postLaunch ||
              isLegacyFullProd
          ? _nextPostLaunchVersionTag
          : (isLaunch ? 'v1.0' : 'v0.$newIndex');
      final defaultTitle = nextPhase == ProductionPhase.verticalSlice
          ? '$effectiveVer: Gold Standard Polish Pass - Vertical Slice'
          : (nextPhase == ProductionPhase.fullProduction
              ? (isLaunch
                  ? '$effectiveVer: Launch Release — Build Export & Ship Sweep'
                  : '$effectiveVer: Full Production Pass $fullProdPass')
              : (nextPhase == ProductionPhase.postLaunch
                  ? '$effectiveVer: Live Ops Balance & Content Drop - Post-Launch'
                  : '$effectiveVer: Progressive Release'));
      final newRelDoc = TierDocument(
        id: newRelId,
        title: defaultTitle,
        tier: TierType.release,
        parentId: proj.id,
        sections: {
          'versionTag': effectiveVer,
          'releaseScope': nextScope.name,
          'phase': nextPhase.name,
          'agentReasoned': 'true',
          if (nextPhase == ProductionPhase.fullProduction)
            'fullProductionPass': '$fullProdPass',
          if (isLaunch) 'launchRelease': 'true',
          if (nextPhase == ProductionPhase.postLaunch)
            'postLaunchPass': '$postLaunchPass',
          'scope':
              'Goal: Synthesize the highest-impact $effectiveVer features and upgrades for ${proj.title}.\n\nIn Scope:\n• Agent-recommended $effectiveVer features and upgrades\n\nDone When: All $effectiveVer features pass playtest verification.',
        },
      );
      documents[newRelId] = newRelDoc;
      _persistDocument(newRelDoc);
      proj.childrenIds.add(newRelId);
      _syncActiveProjectMetadata();
      await openGateAndRecordRetro(newRelId);
      return;
    }

    final beatNames = <String>[];
    final existingBeats = activeReleaseBeats;
    if (existingBeats.isNotEmpty) {
      for (final b in existingBeats) {
        beatNames.add(b.title);
      }
    } else if (_conceptDraft != null &&
        _conceptDraft!.coreLoopBeats.isNotEmpty) {
      for (final raw in _conceptDraft!.coreLoopBeats) {
        final cleanTitle = raw.split(':').first.split('—').first.trim();
        beatNames.add(cleanTitle.isNotEmpty ? cleanTitle : raw);
      }
    }
    if (beatNames.isEmpty) {
      beatNames.add('Core Gameplay Systems');
    }

    final existingMvpCount = releases
        .where((r) => r.sections['phase'] == ProductionPhase.mvp.name)
        .length;

    if (_currentPhase == ProductionPhase.prototype ||
        (_currentPhase == ProductionPhase.mvp &&
            existingMvpCount < beatNames.length)) {
      _currentPhase = ProductionPhase.mvp;
      final i = existingMvpCount;
      final beatLabel = beatNames[i];
      final newRelDoc = TierDocument(
        id: newRelId,
        title: 'v0.$newIndex: MVP Epic ${i + 1} ($beatLabel) - MVP',
        tier: TierType.release,
        parentId: proj.id,
        sections: {
          'versionTag': 'v0.$newIndex',
          'releaseScope': ReleaseScope.mvp.name,
          'phase': ProductionPhase.mvp.name,
          'targetEpicIndex': '$i',
          'mvpEpicTotal': '${beatNames.length}',
          'scope':
              'Goal: Build and connect MVP systems for Epic ${i + 1} ($beatLabel).\n\nIn Scope:\n• $beatLabel\n\nDone When: Epic ${i + 1} is playable end-to-end inside the rough representative level.',
        },
      );
      documents[newRelId] = newRelDoc;
      _persistDocument(newRelDoc);
      proj.childrenIds.add(newRelId);
      _syncActiveProjectMetadata();
      await openGateAndRecordRetro(newRelId);
      return;
    } else if (_currentPhase == ProductionPhase.mvp) {
      _currentPhase = ProductionPhase.verticalSlice;
      final newRelDoc = TierDocument(
        id: newRelId,
        title:
            'v0.$newIndex: Gold Standard Level (Combined MVPs) - Vertical Slice',
        tier: TierType.release,
        parentId: proj.id,
        sections: {
          'versionTag': 'v0.$newIndex',
          'releaseScope': ReleaseScope.verticalSlice.name,
          'phase': ProductionPhase.verticalSlice.name,
          'scope':
              'Goal: Combine all completed MVP Epics into 1 fully polished Gold Standard level.\n\nIn Scope:\n• Final art, audio, UI, and game-feel pass on the representative level\n\nDone When: Playtester completes the polished Vertical Slice level at shippable quality.',
        },
      );
      documents[newRelId] = newRelDoc;
      _persistDocument(newRelDoc);
      proj.childrenIds.add(newRelId);
      _syncActiveProjectMetadata();
      await openGateAndRecordRetro(newRelId);
      return;
    }

    // Phase 4 / Phase 5: Full Production content drops or Post-Launch Live Ops
    final existingFullProdCount = releases
        .where((r) => r.sections['phase'] == ProductionPhase.fullProduction.name)
        .length;
    final existingPostLaunchCount = releases
        .where((r) => r.sections['phase'] == ProductionPhase.postLaunch.name)
        .length;
    if (_currentPhase == ProductionPhase.postLaunch ||
        (existingFullProdCount > 0 && inferNextProgressivePhase() == ProductionPhase.postLaunch)) {
      _currentPhase = ProductionPhase.postLaunch;
      final postPass = existingPostLaunchCount + 1;
      final postVersion = _nextPostLaunchVersionTag;
      final postTitle =
          '$postVersion: Post-Launch — Live Ops & Content Expansion (Pass $postPass) - Post-Launch';
      final newRelDoc = TierDocument(
        id: newRelId,
        title: postTitle,
        tier: TierType.release,
        parentId: proj.id,
        sections: {
          'versionTag': postVersion,
          'releaseScope': ReleaseScope.fullProduction.name,
          'phase': ProductionPhase.postLaunch.name,
          'postLaunchPass': '$postPass',
          'scope':
              'Goal: Deliver post-launch balance tuning, regression fixes, and modular content expansion for ${proj.title}.\n\nIn Scope:\n• Live telemetry & playtest balance adjustments\n• Post-launch content pack / biome expansion\n\nDone When: All $postVersion balance deltas and expansion features pass playtest verification.',
        },
      );
      documents[newRelId] = newRelDoc;
      _persistDocument(newRelDoc);
      proj.childrenIds.add(newRelId);
      _syncActiveProjectMetadata();
      await openGateAndRecordRetro(newRelId);
      return;
    }

    _currentPhase = ProductionPhase.fullProduction;
    final fullProdPass = existingFullProdCount + 1;
    final isLaunch = isNextReleaseV1Launch;
    final isLegacyFullProd = fullProductionCoverage().isLegacy;
    final fullProdVersion = isLaunch
        ? 'v1.0'
        : (isLegacyFullProd ? _nextPostLaunchVersionTag : 'v0.$newIndex');
    final fullProdTitle = isLaunch
        ? '$fullProdVersion: Launch Release — Build Export & Ship Sweep - Full Production'
        : '$fullProdVersion: Full Production Pass $fullProdPass - Full Production';
    final newRelDoc = TierDocument(
      id: newRelId,
      title: fullProdTitle,
      tier: TierType.release,
      parentId: proj.id,
      sections: {
        'versionTag': fullProdVersion,
        'releaseScope': ReleaseScope.fullProduction.name,
        'phase': ProductionPhase.fullProduction.name,
        'fullProductionPass': '$fullProdPass',
        if (isLaunch) 'launchRelease': 'true',
        'scope':
            'Goal: Bring Full Production Epics up to the Vertical Slice quality bar.\n\nIn Scope:\n• Full Production Epic depth & polish passes\n\nDone When: All Full Production features pass playtest verification at Vertical Slice quality.',
      },
    );
    documents[newRelId] = newRelDoc;
    _persistDocument(newRelDoc);
    proj.childrenIds.add(newRelId);
    _syncActiveProjectMetadata();
    await openGateAndRecordRetro(newRelId);
  }

  // ===========================================================================
  // AGENTIC FEATURE INBOX (`📥 Inbox` — Capture -> Triage WHEN/WHERE/HOW -> Route)
  // ===========================================================================

  /// All Feature Inbox items persisted on the active project (`feature_inbox_json`).
  /// Memoized by `(projectDoc.id, raw.hashCode)` to avoid repeated `jsonDecode` calls during UI rebuilds.
  List<FeatureInboxItem> get featureInboxItems {
    final proj = activeProject;
    if (proj == null) return const [];
    final raw = proj.sections['feature_inbox_json'];
    if (raw == null || raw.trim().isEmpty) {
      _cachedInboxProjectId = proj.id;
      _cachedInboxRawHash = 0;
      _cachedInboxItems = const [];
      return const [];
    }
    final rawHash = raw.hashCode;
    if (_cachedInboxProjectId == proj.id && _cachedInboxRawHash == rawHash) {
      return _cachedInboxItems;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final parsed = List<FeatureInboxItem>.unmodifiable(
        decoded
            .whereType<Map>()
            .map((m) => FeatureInboxItem.fromJson(Map<String, dynamic>.from(m))),
      );
      _cachedInboxProjectId = proj.id;
      _cachedInboxRawHash = rawHash;
      _cachedInboxItems = parsed;
      return parsed;
    } catch (_) {
      return const [];
    }
  }

  /// Newly captured Inbox items awaiting user confirmation (`triagePending`).
  List<FeatureInboxItem> get pendingFeatureInboxItems => featureInboxItems
      .where((i) => i.status == FeatureInboxStatus.triagePending)
      .toList();

  /// Inbox items confirmed and scheduled for a future `ProductionPhase` (`scheduledForFuture`).
  List<FeatureInboxItem> get scheduledFeatureInboxItems => featureInboxItems
      .where((i) => i.status == FeatureInboxStatus.scheduledForFuture)
      .toList();

  /// Total active Inbox badge count (`Needs Triage` + `Scheduled for Future Releases`).
  int get activeFeatureInboxCount => featureInboxItems
      .where((i) => i.status != FeatureInboxStatus.implemented)
      .length;

  /// Returns any scheduled future Inbox upgrades linked to [featureId].
  List<FeatureInboxItem> scheduledInboxUpgradesForFeature(String featureId) {
    final scheduled = scheduledFeatureInboxItems;
    if (scheduled.isEmpty) return const [];
    final featDoc = documents[featureId];
    final normTitle = featDoc?.title.toLowerCase().trim() ?? '';
    return scheduled.where((item) {
      if (item.targetFeatureId == featureId) return true;
      if (normTitle.isNotEmpty &&
          item.targetFeatureTitle != null &&
          item.targetFeatureTitle!.toLowerCase().trim() == normTitle) {
        return true;
      }
      return false;
    }).toList();
  }

  void _saveFeatureInboxItems(List<FeatureInboxItem> items) {
    final proj = activeProject;
    if (proj == null) return;
    final encoded = jsonEncode(items.map((i) => i.toJson()).toList());
    proj.sections['feature_inbox_json'] = encoded;
    _cachedInboxProjectId = proj.id;
    _cachedInboxRawHash = encoded.hashCode;
    _cachedInboxItems = List<FeatureInboxItem>.unmodifiable(items);
    _persistDocument(proj);
    notifyListeners();
  }

  static final RegExp _inboxStripPrefixRegex = RegExp(
    r'^(?:i\s+want\s+to\s+add|i\s+d\s+like\s+to\s+add|add\s+a|add\s+an|add|implement|create|build|we\s+need\s+a|we\s+need)\s+',
    caseSensitive: false,
  );
  static final RegExp _inboxClauseSplitRegex = RegExp(
    r'\b(?:that|which|so\s+that|with|when|where|for)\b',
    caseSensitive: false,
  );
  static final RegExp _inboxTrailingPunctRegex = RegExp(r'[.!?]+$');
  static final RegExp _inboxWhitespaceRegex = RegExp(r'\s+');
  static final RegExp _inboxNonAlnumSplitRegex = RegExp(r'[^a-z0-9]+');

  String _cleanShortFeatureTitle(String rawIdea) {
    var cleaned = rawIdea
        .trim()
        .replaceFirst(_inboxStripPrefixRegex, '')
        .split(_inboxClauseSplitRegex)
        .first
        .replaceAll(_inboxTrailingPunctRegex, '')
        .trim();
    if (cleaned.isEmpty) cleaned = rawIdea.trim();
    final words =
        cleaned.split(_inboxWhitespaceRegex).where((w) => w.isNotEmpty).toList();
    final capped = words.length > 4 ? words.take(4).join(' ') : words.join(' ');
    return capped
        .split(' ')
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  FeatureInboxItem _buildDeterministicInboxTriage(
    String rawIdea, {
    String? preferredBeatId,
  }) {
    final beats = activeReleaseBeats;
    final activeVer = activeReleaseVersionTag;
    final engineLabel = _activeEngineLabel;
    final lowerIdea = rawIdea.toLowerCase();
    final cleanTitle = _cleanShortFeatureTitle(rawIdea);

    // 1. WHERE: Match against existing Features (for UPGRADE) and Epics
    TierDocument? matchedBeat = preferredBeatId != null
        ? beats.where((b) => b.id == preferredBeatId).firstOrNull
        : null;
    TierDocument? matchedExistingFeature;

    final ideaTokens = lowerIdea
        .split(_inboxNonAlnumSplitRegex)
        .where((w) => w.length >= 3 && !const {'add', 'the', 'and', 'for', 'with', 'into', 'from', 'player', 'game'}.contains(w))
        .toSet();

    int bestFeatOverlap = 0;
    for (final b in beats) {
      for (final f in featuresForBeat(b.id)) {
        final fTokens = f.title
            .toLowerCase()
            .split(_inboxNonAlnumSplitRegex)
            .where((w) => w.length >= 3)
            .toSet();
        final overlap = ideaTokens.intersection(fTokens).length;
        if (overlap > bestFeatOverlap) {
          bestFeatOverlap = overlap;
          matchedExistingFeature = f;
          matchedBeat ??= b;
        }
      }
    }

    if (matchedBeat == null && beats.isNotEmpty) {
      int bestBeatScore = -1;
      for (final b in beats) {
        final bText = '${b.title} ${b.sections['scope'] ?? ''}'.toLowerCase();
        int score = 0;
        for (final tok in ideaTokens) {
          if (bText.contains(tok)) score += 2;
        }
        if ((lowerIdea.contains('move') ||
                lowerIdea.contains('jump') ||
                lowerIdea.contains('dash') ||
                lowerIdea.contains('climb') ||
                lowerIdea.contains('grapple')) &&
            (bText.contains('move') || bText.contains('control') || bText.contains('locomotion'))) {
          score += 3;
        }
        if ((lowerIdea.contains('attack') ||
                lowerIdea.contains('enemy') ||
                lowerIdea.contains('weapon') ||
                lowerIdea.contains('combat') ||
                lowerIdea.contains('damage') ||
                lowerIdea.contains('parry')) &&
            (bText.contains('combat') || bText.contains('enemy') || bText.contains('attack') || bText.contains('hazard'))) {
          score += 3;
        }
        if ((lowerIdea.contains('loot') ||
                lowerIdea.contains('shop') ||
                lowerIdea.contains('score') ||
                lowerIdea.contains('wave') ||
                lowerIdea.contains('upgrade') ||
                lowerIdea.contains('reward')) &&
            (bText.contains('reward') || bText.contains('loop') || bText.contains('progress') || bText.contains('reset'))) {
          score += 3;
        }
        if (score > bestBeatScore) {
          bestBeatScore = score;
          matchedBeat = b;
        }
      }
      matchedBeat ??= beats.first;
    }

    final targetBeatId = matchedBeat?.id ?? 'beat_1';
    final targetBeatTitle = matchedBeat?.title ?? 'Core Gameplay';
    final integrationMode = matchedExistingFeature != null
        ? InboxIntegrationMode.upgradeExistingFeature
        : InboxIntegrationMode.newFeatureInEpic;

    final placementReasoning = matchedExistingFeature != null
        ? 'Extends existing feature "${matchedExistingFeature.title}" in "$targetBeatTitle" with a version-stamped Delta Checkpoint (Single Source of Truth).'
        : 'Fits inside Core Loop Epic "$targetBeatTitle" as a dedicated playable mechanic.';

    // 2. WHEN: Evaluate Release Timing Mode & Target Future Phase
    InboxReleaseTimingMode timingMode = InboxReleaseTimingMode.now;
    ProductionPhase targetFuturePhase = inferNextProgressivePhase();
    String timingReasoning =
        'Directly supports $activeVer (${_currentPhase.label}) core gameplay verification; recommended to build in the active release.';

    final isPostLaunchCandidate = lowerIdea.contains('leaderboard') ||
        lowerIdea.contains('daily challenge') ||
        lowerIdea.contains('dlc') ||
        lowerIdea.contains('season') ||
        lowerIdea.contains('endless mode') ||
        lowerIdea.contains('new game+') ||
        lowerIdea.contains('telemetry');
    final isFullProdCandidate = lowerIdea.contains('achievement') ||
        lowerIdea.contains('steam') ||
        lowerIdea.contains('localization') ||
        lowerIdea.contains('accessibility') ||
        lowerIdea.contains('colorblind') ||
        lowerIdea.contains('save file') ||
        lowerIdea.contains('cloud save') ||
        lowerIdea.contains('multi-biome') ||
        lowerIdea.contains('campaign');
    final isVerticalSliceCandidate = lowerIdea.contains('boss') ||
        lowerIdea.contains('cutscene') ||
        lowerIdea.contains('shader') ||
        lowerIdea.contains('vfx') ||
        lowerIdea.contains('screen shake') ||
        lowerIdea.contains('audio mix') ||
        lowerIdea.contains('voiceover');
    final isSplitCandidate = _currentPhase == ProductionPhase.prototype &&
        (lowerIdea.contains('skill tree') ||
            lowerIdea.contains('shop') ||
            lowerIdea.contains('inventory') ||
            lowerIdea.contains('perk') ||
            lowerIdea.contains('crafting') ||
            lowerIdea.contains('progression') ||
            lowerIdea.contains('loadout'));

    if (isPostLaunchCandidate &&
        _currentPhase.index < ProductionPhase.postLaunch.index) {
      timingMode = InboxReleaseTimingMode.futureRelease;
      targetFuturePhase = ProductionPhase.postLaunch;
      timingReasoning =
          'Live-ops/endgame system belongs in 05 · Post-Launch & Live Ops so $activeVer (${_currentPhase.shortName}) stays focused on core loop completion.';
    } else if (isFullProdCandidate &&
        _currentPhase.index < ProductionPhase.fullProduction.index) {
      timingMode = InboxReleaseTimingMode.futureRelease;
      targetFuturePhase = ProductionPhase.fullProduction;
      timingReasoning =
          'Content scaling / platform readiness feature belongs in 04 · Full Production (v1.0) after the Vertical Slice quality bar is locked.';
    } else if (isVerticalSliceCandidate &&
        _currentPhase.index < ProductionPhase.verticalSlice.index) {
      timingMode = InboxReleaseTimingMode.futureRelease;
      targetFuturePhase = ProductionPhase.verticalSlice;
      timingReasoning =
          'High-polish presentation/encounter feature belongs in 03 · Vertical Slice once the 02 · MVP loop is playable end-to-end.';
    } else if (isSplitCandidate) {
      timingMode = InboxReleaseTimingMode.splitNowAndFuture;
      targetFuturePhase = ProductionPhase.mvp;
      timingReasoning =
          'Progressive Split: Build a lean 1-stat greybox pickup/modifier in $activeVer (01 · Prototype) now to prove feel, and schedule the full UI/persistence layer for 02 · MVP.';
    }

    // 3. HOW: Concrete Engine & Checkpoint Architecture
    final immediateTitle = timingMode == InboxReleaseTimingMode.splitNowAndFuture
        ? '$cleanTitle Core Modifier'
        : cleanTitle;
    final futureTitle = timingMode == InboxReleaseTimingMode.splitNowAndFuture
        ? '$cleanTitle Progression & UI'
        : '$cleanTitle (${targetFuturePhase.shortName})';

    return FeatureInboxItem(
      id: 'inbox_${DateTime.now().microsecondsSinceEpoch}',
      rawIdea: rawIdea.trim(),
      status: FeatureInboxStatus.triagePending,
      releaseTimingMode: timingMode,
      targetFuturePhase: targetFuturePhase,
      releaseTimingReasoning: timingReasoning,
      integrationMode: integrationMode,
      targetBeatId: targetBeatId,
      targetBeatTitle: targetBeatTitle,
      targetFeatureId: matchedExistingFeature?.id,
      targetFeatureTitle: matchedExistingFeature?.title,
      placementReasoning: placementReasoning,
      featureTitle: cleanTitle,
      goal: 'Build and verify $cleanTitle inside $targetBeatTitle.',
      inScope: [
        '$immediateTitle runtime trigger & state handler',
        'Immediate on-screen visual/audio feedback cue',
      ],
      doneWhen:
          'Trigger $cleanTitle in the playtest arena -> responds cleanly on screen without state lockups.',
      architectureHowSummary: [
        'Engine ($engineLabel): Attach $cleanTitle component/node to the $targetBeatTitle actor hierarchy.',
        'Signal & State: Wire input/overlap event to trigger $cleanTitle and emit HUD/feedback update.',
        'Guard: Enforce cooldown and state-lock checks before activating $cleanTitle.',
      ],
      checkpointTitle: immediateTitle,
      playtestGate:
          'Trigger $immediateTitle in playtest -> observable state change and feedback occur cleanly',
      tasks: [
        'Actor & Component Setup for $immediateTitle (2h)',
        'Core Trigger & State Logic for $immediateTitle (1h)',
        'Visual Feedback & Cooldown Guard for $immediateTitle (1h)',
      ],
      tuningParams: const [
        'activationWindowSec: 0.25 s',
        'effectMultiplier: 1.25 x',
      ],
      edgeCases: [
        '[STATE GUARD] Block duplicate $cleanTitle activation while active or on cooldown',
      ],
      futureCheckpointTitle: futureTitle,
      futureGoal:
          'Expand $cleanTitle with ${targetFuturePhase.shortName} progression, UI feedback, and persistence.',
      futurePlaytestGate:
          'Complete $futureTitle flow in playtest -> state persists and updates cleanly across runs',
      futureTasks: [
        'Data Resource & State Persistence for $futureTitle (2h)',
        'UI / Presentation Hookup for $futureTitle (1h)',
        'Edge-Case & Regression Guard for $futureTitle (1h)',
      ],
      futureTuningParams: const [
        'tierScalingFactor: 1.5 x',
        'maxStackCount: 3',
      ],
      futureEdgeCases: [
        '[STATE GUARD] Clamp $cleanTitle progression state within valid tier bounds',
      ],
    );
  }

  /// Captures a user's feature idea into the Agentic Feature Inbox (`📥 Inbox`),
  /// immediately computing a deterministic `WHEN` · `WHERE` · `HOW` triage and refining it via Gemini AI.
  Future<FeatureInboxItem?> submitFeatureIdeaToInbox(
    String rawIdea, {
    String? preferredBeatId,
  }) async {
    final trimmed = rawIdea.trim();
    if (trimmed.isEmpty) return null;

    final item = _buildDeterministicInboxTriage(
      trimmed,
      preferredBeatId: preferredBeatId,
    );
    final currentItems = List<FeatureInboxItem>.from(featureInboxItems);
    currentItems.insert(0, item);
    _saveFeatureInboxItems(currentItems);

    if (GeminiAgentClient.hasKey(_apiKey) ||
        GeminiAgentClient.testMockResponder != null) {
      await _refineFeatureInboxItemWithAi(item.id);
    }
    return featureInboxItems
        .where((i) => i.id == item.id)
        .firstOrNull ??
        item;
  }

  Future<void> _refineFeatureInboxItemWithAi(String inboxItemId) async {
    final items = List<FeatureInboxItem>.from(featureInboxItems);
    final idx = items.indexWhere((i) => i.id == inboxItemId);
    if (idx < 0) return;
    final item = items[idx];

    final proj = activeProject;
    final beats = activeReleaseBeats;
    final activeVer = activeReleaseVersionTag;
    final engineLabel = _activeEngineLabel;

    final beatCatalogLines = <String>[];
    for (int bIdx = 0; bIdx < beats.length; bIdx++) {
      final b = beats[bIdx];
      final feats = featuresForBeat(b.id);
      final featSummary = feats.isEmpty
          ? '(no features yet)'
          : feats.map((f) {
              final asset = (f.sections['primary_asset'] ?? '').trim();
              final assetSuffix =
                  asset.isNotEmpty ? ' [shared asset: $asset]' : '';
              return '${f.id}:"${f.title}"$assetSuffix';
            }).join(', ');
      beatCatalogLines.add(
        '- Epic E${(bIdx + 1).toString().padLeft(2, '0')} [id="${b.id}"]: "${b.title}" -> Features: [$featSummary]',
      );
    }

    final compactSpecBlock = _buildCompactWorkbenchSpecContext(
      includeExclusions: true,
    );

    final prompt = '''
You are the Principal Game Producer & Lead Systems Architect ($engineLabel) for "${proj?.title ?? 'Game Project'}".
Triage this developer feature request captured in the Feature Inbox across 3 dimensions:
1. WHEN (Release Timing): Does it belong in the CURRENT release ($activeVer · ${_currentPhase.label}), should it be SPLIT (lean 4h core slice in $activeVer now + deeper upgrade scheduled for a future ProductionPhase), or should it be SCHEDULED entirely for a future ProductionPhase (mvp, verticalSlice, fullProduction, postLaunch)?
2. WHERE (Single Live Tree Placement): Which existing Epic (or new Epic) owns it, and should it be a standalone NEW feature ("newFeatureInEpic") or an UPGRADE checkpoint on an existing Feature ("upgradeExistingFeature")?
3. HOW (Implementation Architecture): Plain 2-4 word functional title, Goal/In Scope/Done When, 3 Engine Architecture bullets ($engineLabel matching the project's 2D/3D spec), Playtest Gate, Foundation-First Build Tasks (stage_1_scene_or_data_foundation -> stage_2_mechanic_logic -> stage_3_state_and_playtest_verify), Tuning Params, and [STATE GUARD] rules.

Developer Request: "${item.rawIdea}"
Active Release: $activeVer (${_currentPhase.label})
$compactSpecBlock
Existing Epics & Live Features:
${beatCatalogLines.join('\n')}

${GeminiAgentClient.compactStyleRules}
- If `releaseTimingMode` is `"now"`, omit `"targetFuturePhase"`, `"futureCheckpointTitle"`, `"futureGoal"`, `"futurePlaytestGate"`, `"futureTasks"`, `"futureTuningParams"`, and `"futureEdgeCases"`.

Invoke `commit_inbox_feature_triage` with the structured triage recommendation.''';

    final json = await GeminiAgentClient.generateJson(
      prompt: prompt,
      apiKey: _apiKey,
      preferredModel: _conversationModel,
      thinkingLevel: _thinkingLevel,
      temperature: 0.25,
      functionDeclarations: const [commitInboxFeatureTriageTool],
    );
    if (json == null) return;

    final latestItems = List<FeatureInboxItem>.from(featureInboxItems);
    final latestIdx = latestItems.indexWhere((i) => i.id == inboxItemId);
    if (latestIdx < 0) return;
    final target = latestItems[latestIdx];

    final aiTiming = json['releaseTimingMode']?.toString().trim();
    if (aiTiming != null) {
      for (final m in InboxReleaseTimingMode.values) {
        if (m.name == aiTiming) {
          target.releaseTimingMode = m;
          break;
        }
      }
    }
    final aiPhase = json['targetFuturePhase']?.toString().trim();
    if (aiPhase != null) {
      for (final p in ProductionPhase.values) {
        if (p.name == aiPhase) {
          target.targetFuturePhase = p;
          break;
        }
      }
    }
    final aiTimingReason = json['releaseTimingReasoning']?.toString().trim() ?? '';
    if (aiTimingReason.isNotEmpty) {
      target.releaseTimingReasoning = aiTimingReason;
    }

    final aiIntMode = json['integrationMode']?.toString().trim();
    if (aiIntMode != null) {
      for (final m in InboxIntegrationMode.values) {
        if (m.name == aiIntMode) {
          target.integrationMode = m;
          break;
        }
      }
    }
    final aiBeatId = json['targetBeatId']?.toString().trim() ?? '';
    if (aiBeatId.isNotEmpty && documents[aiBeatId]?.tier == TierType.epic) {
      target.targetBeatId = aiBeatId;
      target.targetBeatTitle = documents[aiBeatId]!.title;
    }
    final aiFeatId = json['targetFeatureId']?.toString().trim() ?? '';
    if (aiFeatId.isNotEmpty && documents[aiFeatId]?.tier == TierType.feature) {
      target.targetFeatureId = aiFeatId;
      target.targetFeatureTitle = documents[aiFeatId]!.title;
    }
    final aiNewEpic = json['newEpicTitle']?.toString().trim() ?? '';
    if (aiNewEpic.isNotEmpty) {
      target.newEpicTitle = aiNewEpic;
    }
    final aiPlaceReason = json['placementReasoning']?.toString().trim() ?? '';
    if (aiPlaceReason.isNotEmpty) {
      target.placementReasoning = aiPlaceReason;
    }
    final aiTitle = json['featureTitle']?.toString().trim() ?? '';
    if (aiTitle.isNotEmpty) target.featureTitle = aiTitle;
    final aiGoal = json['goal']?.toString().trim() ?? '';
    if (aiGoal.isNotEmpty) target.goal = aiGoal;
    final aiDoneWhen = json['doneWhen']?.toString().trim() ?? '';
    if (aiDoneWhen.isNotEmpty) target.doneWhen = aiDoneWhen;
    final aiPrimaryAsset =
        json['primarySharedScriptOrScene']?.toString().trim() ?? '';
    if (aiPrimaryAsset.isNotEmpty) {
      target.primarySharedScriptOrScene = aiPrimaryAsset;
    }
    final aiCpTitle = json['checkpointTitle']?.toString().trim() ?? '';
    if (aiCpTitle.isNotEmpty) target.checkpointTitle = aiCpTitle;
    final aiGate = json['playtestGate']?.toString().trim() ?? '';
    if (aiGate.isNotEmpty) target.playtestGate = aiGate;

    List<String> readStrList(dynamic raw) {
      if (raw is! List) return const [];
      return raw
          .map((e) => e?.toString().trim() ?? '')
          .where((s) => s.isNotEmpty)
          .toList();
    }

    final aiInScope = readStrList(json['inScope']);
    if (aiInScope.isNotEmpty) target.inScope = aiInScope;
    final aiHow = readStrList(json['architectureHowSummary']);
    if (aiHow.isNotEmpty) target.architectureHowSummary = aiHow;
    final aiTasks = ReleasePlannerAgent.extractCheckpointTasksFromMap(json);
    if (aiTasks.isNotEmpty) {
      target.tasks = ReleasePlannerAgent.normalizeFoundationFirstTasks(
        aiTasks,
        featureTitle: target.featureTitle,
        beatTitle: target.targetBeatTitle,
      );
    }
    final aiTuning = readStrList(json['tuningParams']);
    if (aiTuning.isNotEmpty) target.tuningParams = aiTuning;
    final aiGuards = readStrList(json['edgeCases']);
    if (aiGuards.isNotEmpty) target.edgeCases = aiGuards;

    final aiFutCp = json['futureCheckpointTitle']?.toString().trim() ?? '';
    if (aiFutCp.isNotEmpty) target.futureCheckpointTitle = aiFutCp;
    final aiFutGoal = json['futureGoal']?.toString().trim() ?? '';
    if (aiFutGoal.isNotEmpty) target.futureGoal = aiFutGoal;
    final aiFutGate = json['futurePlaytestGate']?.toString().trim() ?? '';
    if (aiFutGate.isNotEmpty) target.futurePlaytestGate = aiFutGate;
    final aiFutTasks = ReleasePlannerAgent.extractCheckpointTasksFromMap({
      'tasks': json['futureTasks'],
    });
    if (aiFutTasks.isNotEmpty) {
      target.futureTasks = ReleasePlannerAgent.normalizeFoundationFirstTasks(
        aiFutTasks,
        featureTitle: target.futureCheckpointTitle.isNotEmpty
            ? target.futureCheckpointTitle
            : target.featureTitle,
        beatTitle: target.targetBeatTitle,
      );
    }
    final aiFutTuning = readStrList(json['futureTuningParams']);
    if (aiFutTuning.isNotEmpty) target.futureTuningParams = aiFutTuning;
    final aiFutGuards = readStrList(json['futureEdgeCases']);
    if (aiFutGuards.isNotEmpty) target.futureEdgeCases = aiFutGuards;

    _saveFeatureInboxItems(latestItems);
  }

  /// Updates the user's `WHEN` / `WHERE` overrides on a `FeatureInboxItem`.
  void updateFeatureInboxItemTriage(
    String inboxItemId, {
    InboxReleaseTimingMode? timingMode,
    ProductionPhase? targetFuturePhase,
    InboxIntegrationMode? integrationMode,
    String? targetBeatId,
    String? targetFeatureId,
  }) {
    final items = List<FeatureInboxItem>.from(featureInboxItems);
    final idx = items.indexWhere((i) => i.id == inboxItemId);
    if (idx < 0) return;
    final item = items[idx];
    if (timingMode != null) item.releaseTimingMode = timingMode;
    if (targetFuturePhase != null) item.targetFuturePhase = targetFuturePhase;
    if (integrationMode != null) item.integrationMode = integrationMode;
    if (targetBeatId != null && documents[targetBeatId]?.tier == TierType.epic) {
      item.targetBeatId = targetBeatId;
      item.targetBeatTitle = documents[targetBeatId]!.title;
    }
    if (targetFeatureId != null &&
        documents[targetFeatureId]?.tier == TierType.feature) {
      item.targetFeatureId = targetFeatureId;
      item.targetFeatureTitle = documents[targetFeatureId]!.title;
    } else if (item.integrationMode ==
        InboxIntegrationMode.upgradeExistingFeature) {
      final beatFeats = featuresForBeat(item.targetBeatId);
      final candidateFeats = beatFeats.isNotEmpty
          ? beatFeats
          : <TierDocument>[
              for (final b in activeReleaseBeats) ...featuresForBeat(b.id),
            ];
      if (candidateFeats.isNotEmpty &&
          !candidateFeats.any((f) => f.id == item.targetFeatureId)) {
        item.targetFeatureId = candidateFeats.first.id;
        item.targetFeatureTitle = candidateFeats.first.title;
      }
    }
    _saveFeatureInboxItems(items);
  }

  /// Removes an item from the Feature Inbox (`📥 Inbox`).
  void removeFeatureInboxItem(String inboxItemId) {
    final items = List<FeatureInboxItem>.from(featureInboxItems)
      ..removeWhere((i) => i.id == inboxItemId);
    _saveFeatureInboxItems(items);
  }

  /// Executes or schedules a triaged `FeatureInboxItem`:
  /// - `now` (or `forceBuildNow == true`): Materializes the Feature or Upgrade Checkpoint into the active release and synthesizes its 6-step `Do -> Copy -> Verify` guide.
  /// - `splitNowAndFuture`: Materializes the lean core slice into the active release right now AND transitions the item to `scheduledForFuture` (linked to the created Feature ID) for `targetFuturePhase`.
  /// - `futureRelease`: Transitions the item to `scheduledForFuture` for `targetFuturePhase` (`+0h` added to the active release).
  Future<String?> acceptFeatureInboxTriage(
    String inboxItemId, {
    bool forceBuildNow = false,
  }) async {
    final items = List<FeatureInboxItem>.from(featureInboxItems);
    final idx = items.indexWhere((i) => i.id == inboxItemId);
    if (idx < 0) return null;
    final item = items[idx];

    final effectiveTiming =
        forceBuildNow ? InboxReleaseTimingMode.now : item.releaseTimingMode;

    if (effectiveTiming == InboxReleaseTimingMode.futureRelease) {
      item.status = FeatureInboxStatus.scheduledForFuture;
      _saveFeatureInboxItems(items);
      return null;
    }

    // Materialize the immediate slice (`now` or `splitNowAndFuture`) into the active release
    final materializedFeatId = _materializeInboxSliceIntoActiveRelease(item);
    if (materializedFeatId == null) return null;

    if (effectiveTiming == InboxReleaseTimingMode.splitNowAndFuture) {
      // Transform the Inbox item into the linked Future Upgrade Checkpoint for targetFuturePhase!
      item.status = FeatureInboxStatus.scheduledForFuture;
      item.releaseTimingMode = InboxReleaseTimingMode.futureRelease;
      item.integrationMode = InboxIntegrationMode.upgradeExistingFeature;
      item.targetFeatureId = materializedFeatId;
      item.targetFeatureTitle = documents[materializedFeatId]?.title ?? item.featureTitle;
      if (item.futureCheckpointTitle.trim().isNotEmpty) {
        item.checkpointTitle = item.futureCheckpointTitle.trim();
      }
      if (item.futureGoal.trim().isNotEmpty) {
        item.goal = item.futureGoal.trim();
      }
      if (item.futurePlaytestGate.trim().isNotEmpty) {
        item.playtestGate = item.futurePlaytestGate.trim();
        item.doneWhen = item.futurePlaytestGate.trim();
      }
      if (item.futureTasks.isNotEmpty) {
        item.tasks = List<String>.from(item.futureTasks);
      }
      if (item.futureTuningParams.isNotEmpty) {
        item.tuningParams = List<String>.from(item.futureTuningParams);
      }
      if (item.futureEdgeCases.isNotEmpty) {
        item.edgeCases = List<String>.from(item.futureEdgeCases);
      }
    } else {
      item.status = FeatureInboxStatus.implemented;
    }

    _saveFeatureInboxItems(items);
    selectFeature(materializedFeatId, triggerAiSynthesis: false);
    await synthesizeFeatureHowToStepsWithAi(
      materializedFeatId,
      forceRefresh: true,
    );
    return materializedFeatId;
  }

  String? _materializeInboxSliceIntoActiveRelease(FeatureInboxItem item) {
    final activeVer = activeReleaseVersionTag;
    final relDoc = activeRelease;
    if (relDoc == null) return null;

    // 1. Resolve or create target Epic (`beatDoc`)
    TierDocument? beatDoc = documents[item.targetBeatId];
    if (item.integrationMode == InboxIntegrationMode.newEpicAndFeature ||
        beatDoc == null ||
        beatDoc.tier != TierType.epic) {
      if (item.integrationMode == InboxIntegrationMode.newEpicAndFeature) {
        final newBeatId =
            'beat_${relDoc.id}_inbox_${relDoc.childrenIds.length + 1}_${DateTime.now().millisecondsSinceEpoch % 10000}';
        final epicTitle = (item.newEpicTitle != null &&
                item.newEpicTitle!.trim().isNotEmpty)
            ? item.newEpicTitle!.trim()
            : item.featureTitle;
        beatDoc = TierDocument(
          id: newBeatId,
          title: epicTitle,
          tier: TierType.epic,
          parentId: relDoc.id,
          estimatedDuration: '4h',
          sections: {
            'scope':
                'Goal: ${item.goal}\n\nIn Scope:\n• ${item.featureTitle}\n\nDone When: ${item.doneWhen}',
          },
        );
        documents[newBeatId] = beatDoc;
        relDoc.childrenIds.add(newBeatId);
        _persistDocument(beatDoc);
        _persistDocument(relDoc);
        item.targetBeatId = newBeatId;
        item.targetBeatTitle = epicTitle;
        final bp = _releaseBlueprint;
        if (bp != null &&
            !bp.beats.any(
              (b) =>
                  b.id == newBeatId ||
                  b.title.toLowerCase().trim() ==
                      epicTitle.toLowerCase().trim(),
            )) {
          bp.beats.add(
            ProposedBeatBlueprint(
              id: newBeatId,
              title: epicTitle,
              goal: item.goal,
              doneWhen: item.doneWhen,
              features: [],
            ),
          );
        }
      } else {
        final fallbackBeats = activeReleaseBeats;
        if (fallbackBeats.isEmpty) return null;
        beatDoc = fallbackBeats.first;
      }
    }

    // 2. If upgrading an existing Feature, append a new version-stamped Delta Checkpoint
    if (item.integrationMode == InboxIntegrationMode.upgradeExistingFeature &&
        (item.targetFeatureId == null ||
            documents[item.targetFeatureId!]?.tier != TierType.feature)) {
      final beatFeats = featuresForBeat(beatDoc.id);
      if (beatFeats.isNotEmpty) {
        item.targetFeatureId = beatFeats.first.id;
        item.targetFeatureTitle = beatFeats.first.title;
      }
    }
    if (item.integrationMode == InboxIntegrationMode.upgradeExistingFeature &&
        item.targetFeatureId != null &&
        documents[item.targetFeatureId!]?.tier == TierType.feature) {
      final featDoc = documents[item.targetFeatureId!]!;
      final states = FeatureStateNode.getStatesForDocument(featDoc);
      final nextCpNum = states.length + 1;
      final cpTitle = item.checkpointTitle.trim().isNotEmpty
          ? item.checkpointTitle.trim()
          : '${item.featureTitle} ($activeVer)';
      final tasks = item.tasks.isNotEmpty
          ? item.tasks
          : <String>[
              'Component & State Upgrade for $cpTitle (2h)',
              'Core Logic & Signal Hookup for $cpTitle (1h)',
              'State & Bounds Guard for $cpTitle (1h)',
            ];
      final existingPrimaryAsset =
          (featDoc.sections['primary_asset'] ?? '').trim();
      final resolvedPrimaryAsset = existingPrimaryAsset.isNotEmpty
          ? existingPrimaryAsset
          : (item.primarySharedScriptOrScene ?? '').trim();
      if (existingPrimaryAsset.isEmpty && resolvedPrimaryAsset.isNotEmpty) {
        featDoc.sections['primary_asset'] = resolvedPrimaryAsset;
      }
      final newCp = FeatureStateNode(
        id: '${featDoc.id}_${activeVer}_cp_$nextCpNum',
        name: 'Checkpoint $nextCpNum: $cpTitle',
        trigger: 'Playtest: ${item.playtestGate}',
        order: states.length,
        checklist: [
          for (int i = 0; i < tasks.length; i++)
            Subtask(
              id: '${featDoc.id}_inbox_${nextCpNum}_t_${i + 1}',
              text: tasks[i],
              completed: false,
            ),
        ],
        coveredScope: item.inScope.isNotEmpty ? item.inScope : [cpTitle],
        tuningParams: item.tuningParams,
        edgeCases: item.edgeCases,
        parameters: {
          'releaseVersion': activeVer,
          if (resolvedPrimaryAsset.isNotEmpty)
            'primarySharedScriptOrScene': resolvedPrimaryAsset,
        },
      );
      for (int tIdx = 0; tIdx < newCp.checklist.length; tIdx++) {
        TaskHowToBlueprint.resolve(
          parentTask: newCp.checklist[tIdx],
          taskIndex: tIdx,
          checkpointNode: newCp,
          engineHint: _activeEngineHint,
          phase: _currentPhase,
        );
      }
      states.add(newCp);
      featDoc.sections['activeReleaseVersion'] = activeVer;
      if (featDoc.sections['originVersion'] != activeVer) {
        featDoc.sections['lifecycle'] = FeatureLifecycleStatus.upgrade.name;
      }
      updateFeatureStates(featDoc.id, states);
      _persistDocument(featDoc);
      final bp = _releaseBlueprint;
      if (bp != null) {
        for (final b in bp.beats) {
          for (final f in b.features) {
            if (f.id == featDoc.id ||
                f.title.toLowerCase().trim() ==
                    featDoc.title.toLowerCase().trim()) {
              f.lifecycle = FeatureLifecycleStatus.upgrade;
              f.included = true;
              f.estimatedHours = 4;
              f.checkpoints = [
                ...f.checkpoints,
                ProposedCheckpointBlueprint(
                  title: cpTitle,
                  playtestCriteria: item.playtestGate,
                  tasks: tasks,
                  coveredScope:
                      item.inScope.isNotEmpty ? item.inScope : [cpTitle],
                  tuningParams: item.tuningParams,
                  edgeCases: item.edgeCases,
                  releaseVersion: activeVer,
                ),
              ];
              break;
            }
          }
        }
        relDoc.sections['release_blueprint_json'] = jsonEncode(bp.toJson());
        _persistDocument(relDoc);
      }
      _syncActiveProjectMetadata();
      return featDoc.id;
    }

    // 3. Otherwise create a brand-new standalone Feature in `beatDoc`
    final featId =
        'feat_${beatDoc.id}_${beatDoc.childrenIds.length + 1}_${DateTime.now().millisecondsSinceEpoch % 10000}';
    final cpTitle = item.checkpointTitle.trim().isNotEmpty
        ? item.checkpointTitle.trim()
        : item.featureTitle;
    final tasks = item.tasks.isNotEmpty
        ? item.tasks
        : <String>[
            'Actor & Component Setup for ${item.featureTitle} (2h)',
            'Core Trigger & State Logic for ${item.featureTitle} (1h)',
            'Visual Feedback & Cooldown Guard for ${item.featureTitle} (1h)',
          ];
    final formattedTuning = item.tuningParams.map((p) => '• $p').join('\n');
    final formattedGuards = item.edgeCases.map((e) => '• $e').join('\n');
    final inScopeBullets = (item.inScope.isNotEmpty
            ? item.inScope
            : <String>[item.featureTitle])
        .map((s) => '• $s')
        .join('\n');

    final inboxPrimaryAsset =
        (item.primarySharedScriptOrScene ?? '').trim();
    final featDoc = TierDocument(
      id: featId,
      title: item.featureTitle,
      tier: TierType.feature,
      parentId: beatDoc.id,
      estimatedDuration: '4h',
      sections: {
        'originVersion': activeVer,
        'activeReleaseVersion': activeVer,
        'lifecycle': FeatureLifecycleStatus.newFeature.name,
        if (inboxPrimaryAsset.isNotEmpty) 'primary_asset': inboxPrimaryAsset,
        'scope':
            'Goal: ${item.goal}\n\nIn Scope:\n$inScopeBullets\n\nDone When: ${item.doneWhen}',
        'variables': formattedTuning,
        'tuning': formattedTuning,
        'edge_cases': formattedGuards,
      },
    );
    final cpNode = FeatureStateNode(
      id: '${featId}_${activeVer}_cp_1',
      name: 'Checkpoint 1: $cpTitle',
      trigger: 'Playtest: ${item.playtestGate}',
      order: 0,
      checklist: [
        for (int i = 0; i < tasks.length; i++)
          Subtask(
            id: '${featId}_inbox_t_${i + 1}',
            text: tasks[i],
            completed: false,
          ),
      ],
      coveredScope: item.inScope.isNotEmpty ? item.inScope : [item.featureTitle],
      tuningParams: item.tuningParams,
      edgeCases: item.edgeCases,
      parameters: {
        'releaseVersion': activeVer,
        if (inboxPrimaryAsset.isNotEmpty)
          'primarySharedScriptOrScene': inboxPrimaryAsset,
      },
    );
    for (int tIdx = 0; tIdx < cpNode.checklist.length; tIdx++) {
      TaskHowToBlueprint.resolve(
        parentTask: cpNode.checklist[tIdx],
        taskIndex: tIdx,
        checkpointNode: cpNode,
        engineHint: _activeEngineHint,
        phase: _currentPhase,
      );
    }
    FeatureStateNode.saveStatesToDocument(featDoc, [cpNode]);
    documents[featId] = featDoc;
    beatDoc.childrenIds.add(featId);
    _persistDocument(featDoc);
    _persistDocument(beatDoc);

    // Sync `_releaseBlueprint` if present
    final bp = _releaseBlueprint;
    if (bp != null) {
      for (final b in bp.beats) {
        if (b.id == beatDoc.id ||
            b.title.toLowerCase().trim() ==
                beatDoc.title.toLowerCase().trim()) {
          b.features.add(
            ProposedFeatureBlueprint(
              id: featId,
              title: item.featureTitle,
              goal: item.goal,
              doneWhen: item.doneWhen,
              estimatedHours: 4,
              included: true,
              lifecycle: FeatureLifecycleStatus.newFeature,
              originVersion: activeVer,
              primarySharedScriptOrScene:
                  inboxPrimaryAsset.isNotEmpty ? inboxPrimaryAsset : null,
              inScope:
                  item.inScope.isNotEmpty ? item.inScope : [item.featureTitle],
              outOfScope: const [],
              tuningParams: item.tuningParams,
              edgeCases: item.edgeCases,
              checkpoints: [
                ProposedCheckpointBlueprint(
                  title: cpTitle,
                  playtestCriteria: item.playtestGate,
                  tasks: tasks,
                  coveredScope: item.inScope.isNotEmpty
                      ? item.inScope
                      : [item.featureTitle],
                  tuningParams: item.tuningParams,
                  edgeCases: item.edgeCases,
                  releaseVersion: activeVer,
                ),
              ],
            ),
          );
          break;
        }
      }
      relDoc.sections['release_blueprint_json'] = jsonEncode(bp.toJson());
      _persistDocument(relDoc);
    }
    _syncActiveProjectMetadata();
    return featId;
  }

  /// Pulls a pending or later-phase Inbox item directly into the active Release Blueprint draft
  /// (e.g. inside the `+ New Release ✦` Co-Pilot) and marks it scheduled for the draft's phase.
  bool pullInboxItemIntoReleaseDraft(String inboxItemId) {
    final bp = _releaseBlueprint;
    if (bp == null) return false;
    final items = List<FeatureInboxItem>.from(featureInboxItems);
    final idx = items.indexWhere((i) => i.id == inboxItemId);
    if (idx == -1) return false;
    final item = items[idx];
    item.status = FeatureInboxStatus.scheduledForFuture;
    item.releaseTimingMode = InboxReleaseTimingMode.futureRelease;
    item.targetFuturePhase = _currentPhase;
    _saveFeatureInboxItems(items);
    _injectDueScheduledInboxItemsIntoBlueprint(bp, _currentPhase);
    final relDoc = activeRelease;
    if (relDoc != null) {
      relDoc.sections['release_blueprint_json'] = jsonEncode(bp.toJson());
      _persistDocument(relDoc);
    }
    _syncActiveProjectMetadata();
    notifyListeners();
    return true;
  }

  /// Automatically injects any `scheduledForFuture` (or pending-for-future-phase) Inbox items
  /// whose `targetFuturePhase.index <= targetPhase.index` into [bp] when a new release is planned.
  void _injectDueScheduledInboxItemsIntoBlueprint(
    ReleaseBlueprint bp,
    ProductionPhase targetPhase,
  ) {
    if (bp.beats.isEmpty) return;
    final dueItems = featureInboxItems.where((item) {
      if (item.status == FeatureInboxStatus.implemented) return false;
      if (item.status == FeatureInboxStatus.scheduledForFuture) {
        return item.targetFuturePhase.index <= targetPhase.index;
      }
      if (item.status == FeatureInboxStatus.triagePending &&
          item.releaseTimingMode == InboxReleaseTimingMode.futureRelease) {
        return item.targetFuturePhase.index <= targetPhase.index;
      }
      return false;
    }).toList();
    if (dueItems.isEmpty) return;

    final verTag = bp.releaseVersionTag;
    for (final item in dueItems) {
      final cpTitle = item.futureCheckpointTitle.trim().isNotEmpty
          ? item.futureCheckpointTitle.trim()
          : (item.checkpointTitle.trim().isNotEmpty
              ? item.checkpointTitle.trim()
              : '${item.featureTitle} ($verTag)');
      final goalText = item.futureGoal.trim().isNotEmpty
          ? item.futureGoal.trim()
          : item.goal;
      final gateText = item.futurePlaytestGate.trim().isNotEmpty
          ? item.futurePlaytestGate.trim()
          : item.playtestGate;
      final tasks = item.futureTasks.isNotEmpty
          ? item.futureTasks
          : (item.tasks.isNotEmpty
              ? item.tasks
              : <String>[
                  'Component & State Setup for $cpTitle (2h)',
                  'Core Logic & Signal Hookup for $cpTitle (1h)',
                  'State & Bounds Guard for $cpTitle (1h)',
                ]);

      ProposedBeatBlueprint targetBeat;
      if (item.integrationMode == InboxIntegrationMode.newEpicAndFeature) {
        final newEpicName = (item.newEpicTitle != null &&
                item.newEpicTitle!.trim().isNotEmpty)
            ? item.newEpicTitle!.trim()
            : item.featureTitle;
        final existingNewBeat = bp.beats
            .where(
              (b) =>
                  b.title.toLowerCase().trim() ==
                  newEpicName.toLowerCase().trim(),
            )
            .firstOrNull;
        if (existingNewBeat != null) {
          targetBeat = existingNewBeat;
        } else {
          targetBeat = ProposedBeatBlueprint(
            id: 'beat_${verTag}_inbox_${bp.beats.length + 1}',
            title: newEpicName,
            goal: goalText,
            doneWhen: gateText,
            features: [],
          );
          bp.beats.add(targetBeat);
        }
      } else {
        targetBeat = bp.beats.firstWhere(
          (b) =>
              b.id == item.targetBeatId ||
              b.title.toLowerCase().trim() ==
                  item.targetBeatTitle.toLowerCase().trim(),
          orElse: () => bp.beats.first,
        );
      }

      // Check if upgrading an existing feature in targetBeat
      ProposedFeatureBlueprint? existingFeat;
      if (item.integrationMode == InboxIntegrationMode.upgradeExistingFeature) {
        for (final b in bp.beats) {
          for (final f in b.features) {
            if (f.id == item.targetFeatureId ||
                (item.targetFeatureTitle != null &&
                    f.title.toLowerCase().trim() ==
                        item.targetFeatureTitle!.toLowerCase().trim())) {
              existingFeat = f;
              targetBeat = b;
              break;
            }
          }
          if (existingFeat != null) break;
        }
      }

      if (existingFeat != null) {
        final effectiveTuning = item.futureTuningParams.isNotEmpty
            ? item.futureTuningParams
            : item.tuningParams;
        final effectiveEdges = item.futureEdgeCases.isNotEmpty
            ? item.futureEdgeCases
            : item.edgeCases;
        existingFeat.lifecycle = FeatureLifecycleStatus.upgrade;
        existingFeat.included = true;
        existingFeat.estimatedHours = 4;
        existingFeat.goal = goalText;
        existingFeat.doneWhen = gateText;
        if ((existingFeat.primarySharedScriptOrScene ?? '').trim().isEmpty &&
            (item.primarySharedScriptOrScene ?? '').trim().isNotEmpty) {
          existingFeat.primarySharedScriptOrScene =
              item.primarySharedScriptOrScene!.trim();
        }
        if (effectiveTuning.isNotEmpty) {
          existingFeat.tuningParams = List<String>.from(effectiveTuning);
        }
        if (effectiveEdges.isNotEmpty) {
          existingFeat.edgeCases = List<String>.from(effectiveEdges);
        }
        existingFeat.checkpoints = [
          ProposedCheckpointBlueprint(
            title: cpTitle,
            playtestCriteria: gateText,
            tasks: tasks,
            coveredScope: [cpTitle],
            tuningParams: effectiveTuning,
            edgeCases: effectiveEdges,
            releaseVersion: verTag,
          ),
        ];
      } else {
        final alreadyAdded = targetBeat.features.any(
          (f) =>
              f.title.toLowerCase().trim() ==
              item.featureTitle.toLowerCase().trim(),
        );
        if (!alreadyAdded) {
          targetBeat.features.add(
            ProposedFeatureBlueprint(
              id: 'feat_${verTag}_inbox_${item.id}',
              title: item.featureTitle,
              goal: goalText,
              doneWhen: gateText,
              estimatedHours: 4,
              included: true,
              lifecycle: FeatureLifecycleStatus.newFeature,
              originVersion: verTag,
              primarySharedScriptOrScene:
                  (item.primarySharedScriptOrScene != null &&
                          item.primarySharedScriptOrScene!.trim().isNotEmpty)
                      ? item.primarySharedScriptOrScene!.trim()
                      : null,
              inScope:
                  item.inScope.isNotEmpty ? item.inScope : [item.featureTitle],
              outOfScope: const [],
              tuningParams: item.futureTuningParams.isNotEmpty
                  ? item.futureTuningParams
                  : item.tuningParams,
              edgeCases: item.futureEdgeCases.isNotEmpty
                  ? item.futureEdgeCases
                  : item.edgeCases,
              checkpoints: [
                ProposedCheckpointBlueprint(
                  title: cpTitle,
                  playtestCriteria: gateText,
                  tasks: tasks,
                  coveredScope: item.inScope.isNotEmpty
                      ? item.inScope
                      : [item.featureTitle],
                  tuningParams: item.futureTuningParams.isNotEmpty
                      ? item.futureTuningParams
                      : item.tuningParams,
                  edgeCases: item.futureEdgeCases.isNotEmpty
                      ? item.futureEdgeCases
                      : item.edgeCases,
                  releaseVersion: verTag,
                ),
              ],
            ),
          );
        }
      }
    }
  }

  void _markExecutedInboxItemsImplemented(ReleaseBlueprint bp) {
    final items = List<FeatureInboxItem>.from(featureInboxItems);
    if (items.isEmpty) return;
    bool changed = false;
    final includedFeatIds = <String>{};
    final includedFeatTitles = <String>{};
    for (final b in bp.beats) {
      for (final f in b.includedFeatures) {
        includedFeatIds.add(f.id);
        includedFeatTitles.add(f.title.toLowerCase().trim());
      }
    }
    for (final item in items) {
      if (item.status == FeatureInboxStatus.implemented) continue;
      final matchesById =
          includedFeatIds.contains('feat_${bp.releaseVersionTag}_inbox_${item.id}') ||
              (item.targetFeatureId != null &&
                  includedFeatIds.contains(item.targetFeatureId!) &&
                  item.targetFuturePhase.index <= _currentPhase.index);
      final matchesByTitle =
          includedFeatTitles.contains(item.featureTitle.toLowerCase().trim()) &&
              item.targetFuturePhase.index <= _currentPhase.index;
      if (matchesById || matchesByTitle) {
        item.status = FeatureInboxStatus.implemented;
        changed = true;
      }
    }
    if (changed) {
      _saveFeatureInboxItems(items);
    }
  }
}
