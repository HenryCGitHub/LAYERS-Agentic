part of 'workbench_provider.dart';

/// Stage 2 Open-Canvas Release Workbench, Progressive AI Release Co-Pilot,
/// Live Playtest Triage, and Engine Step Synthesis for [WorkbenchProvider].
extension WorkbenchReleaseMixin on WorkbenchProvider {
  void _selectFirstIncompleteFeatureInActiveRelease() {
    final beats = activeReleaseBeats;
    if (beats.isEmpty) return;
    TierDocument? firstActiveBeat;
    TierDocument? firstActiveFeat;

    // 1st Pass: Prioritize incomplete features with active-release work (`upgrade` or `newFeature`)
    for (final b in beats) {
      for (final f in featuresForBeat(b.id)) {
        final lc = f.sections['lifecycle'] ?? '';
        final isActiveLifecycle = lc == FeatureLifecycleStatus.upgrade.name ||
            lc == FeatureLifecycleStatus.newFeature.name;
        if (isActiveLifecycle && getDocumentProgress(f.id) < 100) {
          firstActiveBeat = b;
          firstActiveFeat = f;
          break;
        }
      }
      if (firstActiveFeat != null) break;
    }

    // 2nd Pass: Fall back to any incomplete feature
    if (firstActiveFeat == null) {
      for (final b in beats) {
        for (final f in featuresForBeat(b.id)) {
          if (getDocumentProgress(f.id) < 100) {
            firstActiveBeat = b;
            firstActiveFeat = f;
            break;
          }
        }
        if (firstActiveFeat != null) break;
      }
    }

    _selectedBeatId = (firstActiveBeat ?? beats.first).id;
    final feats = featuresForBeat(_selectedBeatId!);
    _selectedFeatureId =
        (firstActiveFeat ?? (feats.isNotEmpty ? feats.first : null))?.id;
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
  /// synthesizes the Release Blueprint, and executes it into the active Workbench in one click.
  Future<void> approveConceptAndBuildRelease({String? releaseId}) async {
    if (_conceptDraft != null) {
      _commitConceptToVault(_conceptDraft!, syncBuiltWorkbench: false);
    }
    _releaseViewFilter = 'active';
    _currentStage = WorkbenchStage.releaseWorkbench;
    notifyListeners();

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

  /// Next progressive version tag (`v0.2`, `v0.3`, etc.) based on how many releases have been built.
  String get nextProgressiveVersionLabel {
    final builtCount =
        projectReleases.where((r) => r.childrenIds.isNotEmpty).length;
    return 'v0.${builtCount + 1}';
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
    await advanceToNextRelease(transitionToGateStage: false);
    _currentStage = WorkbenchStage.releaseWorkbench;
    if (_releaseBlueprint == null ||
        _releaseBlueprint!.releaseDocId != _activeReleaseId) {
      notifyListeners();
      return null;
    }
    if (agentDirective != null && agentDirective.trim().isNotEmpty) {
      await sendReleasePlanChatMessage(agentDirective.trim());
    }
    notifyListeners();
    return _releaseBlueprint;
  }

  /// Restores the active release, blueprint, and production phase if the user cancels (or fails offline in)
  /// the Progressive Next Release modal, and removes any newly created unbuilt draft release documents.
  void restoreActiveReleaseAfterCancel(
    String? previousReleaseId,
    ProductionPhase previousPhase,
  ) {
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
    if (_preModalReleaseBlueprint != null) {
      _releaseBlueprint = _preModalReleaseBlueprint;
    }
    _preModalReleaseIds = null;
    _preModalReleaseBlueprint = null;
    if (previousReleaseId != null && documents.containsKey(previousReleaseId)) {
      _activeReleaseId = previousReleaseId;
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
    if (_conceptDraft != null) {
      _commitConceptToVault(_conceptDraft!, syncBuiltWorkbench: false);
    }

    final proj = activeProject;
    if (proj == null) return;

    final targetRelId = releaseId ??
        _activeReleaseId ??
        (proj.childrenIds.isNotEmpty ? proj.childrenIds.first : null);
    if (targetRelId == null) return;

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
              existingFeaturesByBeat[bDoc.id] = featuresForBeat(bDoc.id);
            }
          }
        }
      }
    }

    // Capture any features deferred (unchecked) in the prior Release Plan Gate
    // so they automatically carry over into the next release's Beat!
    final deferredByBeatIndex = <int, List<ProposedFeatureBlueprint>>{};
    final priorBp = _releaseBlueprint;
    if (priorBp != null) {
      for (int bIdx = 0; bIdx < priorBp.beats.length; bIdx++) {
        final deferredInBeat = priorBp.beats[bIdx].deferredFeatures.toList();
        if (deferredInBeat.isNotEmpty) {
          deferredByBeatIndex[bIdx] = deferredInBeat;
        }
      }
    }

    _activeReleaseId = targetRelId;
    final relDoc = documents[targetRelId];
    if (relDoc == null) return;
    _syncCurrentPhaseFromRelease(relDoc);

    _isAgentBusy = true;
    _agentProgressStep =
        'Drafting Release Blueprint for ${relDoc.title} ($_planningModel · ${_thinkingLevel.toLowerCase()})...';
    notifyListeners();

    try {
      final planned = await ReleasePlannerAgent.planRelease(
        projectDoc: proj,
        releaseDoc: relDoc,
        existingBeats: existingBeats,
        existingFeaturesByBeat: existingFeaturesByBeat,
        deferredByBeatIndex: deferredByBeatIndex,
        apiKey: _apiKey,
        modelName: _planningModel,
        thinkingLevel: _thinkingLevel,
      );
      if (planned != null) {
        _releaseBlueprint = planned;
        _offlineErrorMessage = null;
        if (transitionToGateStage) {
          _currentStage = WorkbenchStage.releaseWorkbench;
        }
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

  /// Sends a user turn in the Stage 2 Release Plan Gate Chat to refine Beats, Features, or Scope.
  Future<void> sendReleasePlanChatMessage(String message) async {
    final bp = _releaseBlueprint;
    if (bp == null || message.trim().isEmpty) return;

    _isAgentBusy = true;
    _agentProgressStep =
        'Refining Release Plan ($_conversationModel · ${_thinkingLevel.toLowerCase()})...';
    notifyListeners();

    try {
      final ok = await ReleasePlannerAgent.sendReleasePlanChatTurn(
        blueprint: bp,
        userMessage: message,
        apiKey: _apiKey,
        modelName: _conversationModel,
        thinkingLevel: _thinkingLevel,
      );
      if (ok) {
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

    final stateNode = FeatureStateNode(
      id: '${featId}_${versionTag}_cp_1',
      name: 'Checkpoint 1: $cleanTitle',
      trigger: '',
      order: 0,
      checklist: const [],
      coveredScope: const [],
      tuningParams: const [],
      edgeCases: const [],
      parameters: {'releaseVersion': versionTag},
    );

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

    selectFeature(featId);
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
    final projTitle = activeProject?.title ?? 'Game Prototype';
    final engineLabel = _activeEngineLabel;
    final prompt = '''
You are the Systems Designer for "$projTitle" ($engineLabel).
Tailor this newly added Feature ("${featDoc.title}" inside Epic "$beatTitle") so its tasks, numeric tuning parameters, and edge-case guards fit "$projTitle".
Return ONLY a JSON object:
{
  "goal": "<1 plain-English sentence starting with Build/Implement>",
  "doneWhen": "<1 observable playtest completion condition>",
  "checkpointTitle": "<2-4 word playable checkpoint title>",
  "playtestGate": "<Action -> Observable result>",
  "tasks": [
    "<Task 1 title> (2h)",
    "<Task 2 title> (1h)",
    "<Task 3 title> (1h)"
  ],
  "tuningParams": [
    "<param1: numericValue unit>",
    "<param2: numericValue unit>"
  ],
  "edgeCases": [
    "[STATE GUARD] <concise guard rule>"
  ]
}''';
    final json = await GeminiAgentClient.generateJson(
      prompt: prompt,
      apiKey: _apiKey,
      preferredModel: _conversationModel,
      thinkingLevel: _thinkingLevel,
      temperature: 0.4,
    );
    if (json != null && documents.containsKey(featureId)) {
      final cp = states.first;
      final aiGoal = json['goal']?.toString().trim() ?? '';
      final aiDoneWhen = json['doneWhen']?.toString().trim() ?? '';
      final aiTitle = json['checkpointTitle']?.toString().trim() ?? '';
      final aiGate = json['playtestGate']?.toString().trim() ?? '';
      final rawTasks = json['tasks'];
      final rawTuning = json['tuningParams'];
      final rawGuards = json['edgeCases'];
      if (aiGoal.isNotEmpty || aiDoneWhen.isNotEmpty) {
        final effectiveGoal = aiGoal.isNotEmpty
            ? aiGoal
            : 'Build ${featDoc.title} inside $beatTitle.';
        final effectiveDoneWhen = aiDoneWhen.isNotEmpty
            ? aiDoneWhen
            : (aiGate.isNotEmpty
                ? aiGate
                : 'Playtester verifies ${featDoc.title} in the test arena.');
        featDoc.sections['scope'] =
            'Goal: $effectiveGoal\n\nIn Scope:\n• ${featDoc.title}\n\nDone When: $effectiveDoneWhen';
        _persistDocument(featDoc);
        final bp = _releaseBlueprint;
        if (bp != null) {
          for (final b in bp.beats) {
            for (final f in b.features) {
              if (f.id == featureId) {
                f.goal = effectiveGoal;
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
      if (rawTasks is List && rawTasks.isNotEmpty) {
        cp.checklist = [
          for (int i = 0; i < rawTasks.length; i++)
            Subtask(
              id: '${featureId}_ai_t${i + 1}',
              text: rawTasks[i].toString().trim(),
              completed: false,
            ),
        ];
      }
      if (rawTuning is List && rawTuning.isNotEmpty) {
        cp.tuningParams =
            rawTuning.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();
      }
      if (rawGuards is List && rawGuards.isNotEmpty) {
        cp.edgeCases =
            rawGuards.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();
      }
      updateFeatureStates(featureId, states);
    }
    await synthesizeFeatureHowToStepsWithAi(featureId, forceRefresh: true);
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
    final isUnity = engineLabel.contains('Unity');
    final isUnreal = engineLabel.contains('Unreal');
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
      final prompt = '''
You are the Playtest Root-Cause Debugger for LAYERS-Agentic ($engineLabel).
Diagnose this reported playtest bug on Feature "$featTitle" (Checkpoint "${cpNode.cleanStageTitle}") and synthesize a concrete 3-step engine fix:
Reported Bug: "$issueDescription"
Active Tuning Parameters: ${cpNode.tuningParams.join(', ')}
Active Guards: ${cpNode.edgeCases.join(', ')}

Return ONLY a JSON object with 3 concrete fix steps:
{
  "playtestGuard": "[PLAYTEST GUARD] <1 concise rule preventing this bug>",
  "steps": [
    {
      "title": "STEP $taskNum.1 · <SHORT LITERAL STEP TITLE>",
      "stepPath": "<Exact $engineLabel panel/inspector/script path>",
      "instruction": "<1 sentence concrete fix/inspection instruction>",
      "codeFormula": "<2-4 lines of $engineLabel code or node setup>",
      "verifyResult": "<1 sentence visual/console check in Play mode>"
    }
  ]
}''';
      final json = await GeminiAgentClient.generateJson(
        prompt: prompt,
        apiKey: _apiKey,
        preferredModel: _planningModel,
        thinkingLevel: _thinkingLevel,
        temperature: 0.3,
      );
      if (json == null) return;
      final rawSteps = json['steps'];
      if (rawSteps is List && rawSteps.isNotEmpty) {
        final updatedSubs = <Subtask>[];
        for (int i = 0; i < rawSteps.length; i++) {
          final item = rawSteps[i];
          if (item is Map) {
            final title = item['title']?.toString().trim() ?? '';
            final path = item['stepPath']?.toString().trim() ?? '';
            final instr = item['instruction']?.toString().trim() ?? '';
            final code = item['codeFormula']?.toString().trim() ?? '';
            final verify = item['verifyResult']?.toString().trim() ?? '';
            final prevDone = i < fixTask.children.length
                ? fixTask.children[i].completed
                : false;
            updatedSubs.add(
              Subtask(
                id: i < fixTask.children.length
                    ? fixTask.children[i].id
                    : generateUniqueId('fix_ai_sub_${i + 1}'),
                text: title.isNotEmpty
                    ? title
                    : 'STEP $taskNum.${i + 1} · APPLY ROOT-CAUSE FIX ${i + 1}',
                specNotes: instr,
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
      final aiGuard = json['playtestGuard']?.toString().trim() ?? '';
      if (aiGuard.isNotEmpty) {
        final normGuard = aiGuard.startsWith('[PLAYTEST GUARD]')
            ? aiGuard
            : '[PLAYTEST GUARD] $aiGuard';
        if (!cpNode.edgeCases.contains(normGuard)) {
          cpNode.edgeCases = [...cpNode.edgeCases, normGuard];
        }
      }
      TaskHowToBlueprint.clearCache();
      updateFeatureStates(featureId, states);
    } finally {
      _synthesizingFeatureIds.remove(featureId);
      notifyListeners();
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
    );

    if (!GeminiAgentClient.hasKey(_apiKey)) {
      _setOfflineState();
      return false;
    }

    _synthesizingFeatureIds.add(featureId);
    notifyListeners();
    try {
      final prompt = '''
You are a senior game engine programmer assisting with a concrete implementation task.
Engine: $engineLabel
Feature: "${featDoc?.title ?? cpNode.name}"
Task ($taskNum): "${parentTask.text}"
Active Tuning Parameters: ${cpNode.tuningParams.join(', ')}
Active Edge-Case Guards: ${cpNode.edgeCases.join(', ')}
Developer's Exact Scene / Node / Script Setup: "$cleanContext"

Break this task down into the exact number of checkable How-To Sub-Steps (Step $taskNum.1 through Step $taskNum.N — e.g., 3 steps for a simple hook/guard task or up to 6 steps for a multi-part mechanic) specifically using the developer's node/script names from "$cleanContext".
Return ONLY a JSON object with this schema:
{
  "subSteps": [
    {
      "title": "STEP $taskNum.1 · SHORT LITERAL SUB-STEP TITLE",
      "stepPath": "Exact $engineLabel editor panel/inspector/script path",
      "instruction": "1-sentence literal instruction referencing the user's exact nodes/scripts",
      "codeFormula": "2-4 lines of $engineLabel code or hierarchy setup using the user's node/script names",
      "verifyResult": "1-sentence observable verification check in Play mode"
    }
  ]
}
''';
      final json = await GeminiAgentClient.generateJson(
        prompt: prompt,
        apiKey: _apiKey,
        preferredModel: _conversationModel,
        thinkingLevel: _thinkingLevel,
        temperature: 0.25,
      );
      final rawSubs = json?['subSteps'];
      if (rawSubs is List && rawSubs.isNotEmpty) {
        final newChildren = <Subtask>[];
        for (int i = 0; i < rawSubs.length; i++) {
          final item = rawSubs[i];
          if (item is Map) {
            final t = (item['title'] ?? '').toString().trim();
            final path = (item['stepPath'] ?? '').toString().trim();
            final instr = (item['instruction'] ?? '').toString().trim();
            final code = (item['codeFormula'] ?? '').toString().trim();
            final verify = (item['verifyResult'] ?? '').toString().trim();
            final prevDone = i < parentTask.children.length
                ? parentTask.children[i].completed
                : parentTask.completed;
            newChildren.add(
              Subtask(
                id: '${parentTask.id}_sub_${i + 1}',
                text: t.isNotEmpty
                    ? t
                    : 'STEP $taskNum.${i + 1} · IMPLEMENT STEP ${i + 1}',
                specNotes: instr,
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
    }
  }

  /// Stage 2 -> Stage 3: User approves the Release Plan Gate; Executor Agent builds or evolves the Release hierarchy.
  Future<void> approveAndExecuteReleasePlan() async {
    final bp = _releaseBlueprint;
    final relDoc = activeRelease;
    if (bp == null || relDoc == null) return;

    _isAgentBusy = true;
    _executionLog.clear();
    _currentStage = WorkbenchStage.releaseWorkbench;
    _releaseViewFilter = 'active';
    notifyListeners();

    try {
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

      for (final d in createdDocs) {
        documents[d.id] = d;
        _persistDocument(d);
      }
      _persistDocument(relDoc);

      // Auto-select the first Feature that has incomplete checkpoints (or Beat 1 / Feature 1)
      // before syncing project metadata so selected_beat_id / selected_feature_id are persisted together.
      _selectFirstIncompleteFeatureInActiveRelease();
      _syncActiveProjectMetadata();
      if (_selectedFeatureId != null && GeminiAgentClient.hasKey(_apiKey)) {
        synthesizeFeatureHowToStepsWithAi(_selectedFeatureId!);
      }
    } finally {
      _isAgentBusy = false;
      _agentProgressStep = null;
      notifyListeners();
    }
  }

  bool isSynthesizingFeatureSteps(String featureId) =>
      _synthesizingFeatureIds.contains(featureId);

  /// Synthesizes bespoke, engine-specific 3-Area How-To Sub-Steps (`Hierarchy` -> `Inspector` -> `Code` -> `Verify`)
  /// for the active checkpoint of `featureId` using on-demand `_conversationModel` (`gemini-flash-latest`),
  /// adapting directly to the project's exact variable names and previous checkpoints.
  Future<void> synthesizeFeatureHowToStepsWithAi(
    String featureId, {
    bool forceRefresh = false,
    bool unrealCppMode = false,
  }) async {
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
      );
    }

    _synthesizingFeatureIds.add(featureId);
    notifyListeners();

    try {
      final projTitle = activeProject?.title ?? 'Game Prototype';
      final taskSummaries = <String>[];
      for (int tIdx = 0; tIdx < cpNode.checklist.length; tIdx++) {
        taskSummaries.add('Task ${tIdx + 1}: "${cpNode.checklist[tIdx].text}"');
      }

      // Gather previous checkpoints & sibling features' exact variable names and guards
      final priorCheckpointsSummary = <String>[];
      for (int i = 0; i < effectiveCpIndex; i++) {
        final prev = states[i];
        priorCheckpointsSummary.add(
          '- ${prev.cleanStageTitle} (${prev.releaseVersion}): vars=[${prev.tuningParams.join(', ')}], guards=[${prev.edgeCases.join(', ')}]',
        );
      }
      if (feat.parentId != null) {
        for (final sib in featuresForBeat(feat.parentId!)) {
          if (sib.id == feat.id) continue;
          final sibStates = FeatureStateNode.getStatesForDocument(sib);
          for (final sibCp in sibStates) {
            if (sibCp.tuningParams.isNotEmpty) {
              priorCheckpointsSummary.add(
                '- Sibling Feature "${sib.title}" (${sibCp.releaseVersion}): vars=[${sibCp.tuningParams.join(', ')}]',
              );
            }
          }
        }
      }

      final targetEngineMode = engineLabel == 'UNREAL 5'
          ? (unrealCppMode ? 'UNREAL 5 C++ (.h / .cpp)' : 'UNREAL 5 BLUEPRINTS')
          : (engineLabel == 'UNITY C#'
              ? 'UNITY C# (MonoBehaviour)'
              : 'GODOT 4 (GDScript 2.0)');

      final prompt = '''
You are the Principal Game Engine Architect ($targetEngineMode) for "$projTitle".
Synthesize concrete, beginner-friendly 3-Area Engine How-To steps for Feature "${feat.title}" (Checkpoint "${cpNode.cleanStageTitle}").
Tasks:
${taskSummaries.join('\n')}
Active Tuning Parameters (MUST use exact variable names): ${cpNode.tuningParams.join(', ')}
Active Guards (MUST enforce in code): ${cpNode.edgeCases.join(', ')}
${priorCheckpointsSummary.isNotEmpty ? 'Previous Checkpoints & Project Variable Context (reuse exact identifiers):\n${priorCheckpointsSummary.join('\n')}' : ''}

For each task (1..${cpNode.checklist.length}), return 3 to 5 sequential sub-steps covering the 3 Engine Areas (1. Hierarchy/Components, 2. Inspector/Details Bindings, 3. Attached Script/Graph Code) and using the project's exact variable names:
1. "title": "STEP X.Y · SHORT LITERAL STEP TITLE"
2. "stepPath": Exact $targetEngineMode editor panel/menu/inspector/script path
3. "instruction": 1-2 sentences explaining what to click or type in $targetEngineMode
4. "area1Hierarchy": Optional Scene/Component hierarchy tree using ├─ / └─ when the step adds or modifies nodes/components (or "" if pure code step)
5. "area2Inspector": Inspector/Details bindings formatted as "Property: Value | Property2: Value2" using the exact tuning parameter names
6. "codeFormula": 2-6 lines of concrete $targetEngineMode code or node graph wiring using the exact tuning variables and guard checks
7. "verifyResult": 1 sentence observable verification check in the editor or Play mode

Return ONLY valid JSON:
{
  "tasks": [
    {
      "taskIndex": 0,
      "subSteps": [
        {
          "title": "STEP 1.1 · ...",
          "stepPath": "...",
          "instruction": "...",
          "area1Hierarchy": "...",
          "area2Inspector": "paramName: value | ...",
          "codeFormula": "...",
          "verifyResult": "..."
        }
      ]
    }
  ]
}''';

      final json = await GeminiAgentClient.generateJson(
        prompt: prompt,
        apiKey: _apiKey,
        preferredModel: _conversationModel,
        thinkingLevel: 'LOW',
        temperature: 0.25,
      );
      final rawTasks = json?['tasks'];
      if (rawTasks is! List || rawTasks.isEmpty) return;

      bool mutated = false;
      for (final rawTask in rawTasks) {
        if (rawTask is! Map) continue;
        final tIdx = int.tryParse(rawTask['taskIndex']?.toString() ?? '') ?? -1;
        if (tIdx < 0 || tIdx >= cpNode.checklist.length) continue;
        final parentTask = cpNode.checklist[tIdx];
        final taskNum = tIdx + 1;
        final rawSubs = rawTask['subSteps'];
        if (rawSubs is! List || rawSubs.isEmpty) continue;

        final newChildren = <Subtask>[];
        for (int sIdx = 0; sIdx < rawSubs.length; sIdx++) {
          final item = rawSubs[sIdx];
          if (item is! Map) continue;
          final title = item['title']?.toString().trim() ?? '';
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
    if (draft != null) {
      if (draft.goal.trim().isNotEmpty) {
        sb.writeln('- **Goal**: ${draft.goal.trim()}');
      }
      if (draft.designPillars.isNotEmpty) {
        sb.writeln('- **Design Pillars**: ${draft.designPillars.join(' · ')}');
      }
      if (draft.tradeOffs.isNotEmpty) {
        sb.writeln('- **Engineering Trade-Offs**: ${draft.tradeOffs.join(' · ')}');
      }
      if (draft.exclusions.isNotEmpty) {
        sb.writeln(
          '- **Explicitly Out of Scope (DO NOT BUILD IN $activeVer)**: ${draft.exclusions.join(' · ')}',
        );
      }
      if (draft.doneWhen.trim().isNotEmpty) {
        sb.writeln('- **Release Done When**: ${draft.doneWhen.trim()}');
      }
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
          sb.writeln('  - **${f.title}** (${f.estimatedHours}h): ${f.goal}');
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
          sb.writeln(
            '  - **${feat.title}** [`$lc` · $p% verified · ${feat.estimatedDuration}]',
          );
          final states = FeatureStateNode.getStatesForDocument(feat);
          final activeStates =
              states.where((s) => s.releaseVersion == activeVer).toList();
          final effectiveStates =
              activeStates.isNotEmpty ? activeStates : states;
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
          sb.writeln('- **Playtest Gate**: ${cp.playtestCondition}');
          for (int tIdx = 0; tIdx < cp.checklist.length; tIdx++) {
            final task = cp.checklist[tIdx];
            final bp = TaskHowToBlueprint.resolve(
              parentTask: task,
              taskIndex: tIdx,
              checkpointNode: cp,
              engineHint: engineHint,
              unrealCppMode: unrealCppMode,
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

    return sb.toString();
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
    final rawGoal = (feat.sections['scope'] ?? feat.sections['goal'] ?? '').trim();
    if (rawGoal.isNotEmpty) {
      sb.writeln('- **Goal**: ${rawGoal.split('\n').first.replaceFirst(RegExp(r'^Goal:\s*', caseSensitive: false), '').trim()}');
    }
    if (cpNode != null && cpNode.playtestCondition.trim().isNotEmpty) {
      sb.writeln('- **Playtest Gate (Done When)**: ${cpNode.playtestCondition.trim()}');
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
        if (sibStates.isNotEmpty && sibStates.last.tuningParams.isNotEmpty) {
          siblingLines.add(
            '- **${sib.title}**: `${sibStates.last.tuningParams.join('`, `')}`',
          );
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

    // 1. Fast AI extraction pass via gemini-flash-latest when key is available
    if (GeminiAgentClient.hasKey(_apiKey)) {
      final prompt = '''
You are a Game Engine Code-to-Spec Synchronizer.
Compare the developer's pasted engine script against the Feature's current Tuning Parameters and Guards.
Feature: "${feat.title}"
Current Tuning Parameters: ${cpNode.tuningParams.join(', ')}
Current Guards: ${cpNode.edgeCases.join(' | ')}

Pasted Engine Script:
```
$trimmedCode
```

Extract:
1. "tuningUpdates": Any updated or newly exported numeric/boolean/string tuning variables from the script formatted as "variableName: value". Preserve existing variable names when they match.
2. "newGuards": Any new safety/null/cooldown/bounds guard checks in the script formatted as "[GUARD] condition — safe fallback".

Return ONLY valid JSON:
{
  "tuningUpdates": ["moveSpeed: 650.0"],
  "newGuards": ["[GUARD] Prevent dash while stunned — early-return when isStunned is true"]
}''';
      final json = await GeminiAgentClient.generateJson(
        prompt: prompt,
        apiKey: _apiKey,
        preferredModel: _conversationModel,
        thinkingLevel: 'LOW',
        temperature: 0.1,
      );
      final rawTuning = json?['tuningUpdates'];
      if (rawTuning is List) {
        for (final item in rawTuning) {
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

    // 2. Deterministic multi-line regex extraction (handles Godot 4 @export, Unity [SerializeField], Unreal UPROPERTY across line breaks)
    String cleanNumericValue(String raw) {
      var val = raw
          .split('//')
          .first
          .split('#')
          .first
          .trim()
          .replaceAll(RegExp(r';$'), '')
          .trim();
      // Strip trailing C#/C++ float 'f' suffix on numeric literals (e.g. 600.0f -> 600.0, 6f -> 6.0)
      final floatMatch = RegExp(r'^(-?\d+(?:\.\d+)?)[fF]$').firstMatch(val);
      if (floatMatch != null) {
        final numPart = floatMatch.group(1)!;
        val = numPart.contains('.') ? numPart : '$numPart.0';
      }
      return val;
    }

    // 2a. Multi-line Unity [SerializeField] / Unreal UPROPERTY(...) attribute on same or preceding line
    final attrFieldRegex = RegExp(
      r'(?:\[SerializeField[^\]]*\]|UPROPERTY\([^)]*\))\s*(?:(?:private|public|protected|internal|mutable|const)\s+)?[\w<>:*&]+\s+(\w+)\s*=\s*([^;\n]+);',
      multiLine: true,
    );
    for (final m in attrFieldRegex.allMatches(trimmedCode)) {
      final k = m.group(1)?.trim() ?? '';
      final v = cleanNumericValue(m.group(2) ?? '');
      if (k.isNotEmpty && v.isNotEmpty) {
        extractedTuning.putIfAbsent(k, () => v);
      }
    }

    // 2b. Godot 4 @export var / typed var declarations
    final gdVarRegex = RegExp(
      r'@export(?:_[a-z_]+)?(?:\([^)]*\))?\s+var\s+(\w+)(?:\s*:\s*[\w.]+)?\s*=\s*([^\n#;]+)',
      multiLine: true,
    );
    for (final m in gdVarRegex.allMatches(trimmedCode)) {
      final k = m.group(1)?.trim() ?? '';
      final v = cleanNumericValue(m.group(2) ?? '');
      if (k.isNotEmpty && v.isNotEmpty) {
        extractedTuning.putIfAbsent(k, () => v);
      }
    }

    // 2c. Direct assignment match for any existing tuningParams keys
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

    // 2d. Guard comment extraction (// [GUARD] ..., # [GUARD] ..., // GUARD: ...)
    final guardCommentRegex = RegExp(
      r'(?://|#)\s*\[?(?:PLAYTEST\s+)?GUARD\]?\s*:?\s*(.+)$',
      multiLine: true,
      caseSensitive: false,
    );
    for (final m in guardCommentRegex.allMatches(trimmedCode)) {
      final gText = m.group(1)?.trim() ?? '';
      if (gText.isNotEmpty) {
        final formatted = gText.startsWith('[') ? gText : '[GUARD] $gText';
        if (!extractedGuards.contains(formatted)) {
          extractedGuards.add(formatted);
        }
      }
    }

    // 3. Apply extracted tuning updates and new guards to cpNode in-place
    int updatedVars = 0;
    int addedGuards = 0;

    final updatedTuningList = List<String>.from(cpNode.tuningParams);
    String normalizeVarKey(String k) =>
        k.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

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
      final normG = g.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
      final alreadyExists = updatedGuardsList.any(
        (existing) =>
            existing.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim() ==
            normG,
      );
      if (!alreadyExists) {
        updatedGuardsList.add(g);
        addedGuards++;
      }
    }

    if (updatedVars > 0 || addedGuards > 0) {
      cpNode.tuningParams = updatedTuningList;
      cpNode.edgeCases = updatedGuardsList;
      TaskHowToBlueprint.clearCache();
      updateFeatureStates(featureId, states);
    }

    return (updatedVars: updatedVars, addedGuards: addedGuards);
  }

  void selectFeature(String featureId) {
    final feat = documents[featureId];
    if (feat == null) return;
    _selectedFeatureId = featureId;
    if (feat.parentId != null) {
      _selectedBeatId = feat.parentId;
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
    if (GeminiAgentClient.hasKey(_apiKey)) {
      synthesizeFeatureHowToStepsWithAi(featureId);
    }
  }

  void updateFeatureStates(String featureId, List<FeatureStateNode> states) {
    final feat = documents[featureId];
    if (feat == null) return;
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
    }
    TaskHowToBlueprint.clearCache();
    _persistDocument(feat, debounce: true);
    notifyListeners();
  }

  /// Advances to the next queued Release in the current Production Phase, or unlocks the
  /// next Production Phase once the current phase's releases are completed:
  /// - Phase 1 (Prototype) complete -> Phase 2 (MVP Track: 1 MVP Release per Core Loop Beat)
  /// - Phase 2 (MVP Track) complete -> Phase 3 (Vertical Slice: 1 Polished Gold Standard Level)
  /// - Phase 3 (Vertical Slice) complete -> Phase 4 (Full Production: World & Content Expansion)
  Future<void> advanceToNextRelease({bool transitionToGateStage = true}) async {
    final proj = activeProject;
    if (proj == null) return;
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
    if (nextIdx < releases.length) {
      final nextRel = releases[nextIdx];
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

    // Current Phase has no more queued releases — unlock and define the next Production Phase!
    if (_currentPhase == ProductionPhase.prototype) {
      _currentPhase = ProductionPhase.mvp;
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

      String? firstNewMvpId;
      for (int i = 0; i < beatNames.length; i++) {
        final newIndex = proj.childrenIds.length + 1;
        final newRelId = proj.id == 'proj_main'
            ? 'rel_v0_$newIndex'
            : '${proj.id}_rel_v0_$newIndex';
        final beatLabel = beatNames[i];
        final newRelDoc = TierDocument(
          id: newRelId,
          title: 'v0.$newIndex: MVP Epic ${i + 1} ($beatLabel) - MVP',
          tier: TierType.release,
          parentId: proj.id,
          sections: {
            'releaseScope': ReleaseScope.mvp.name,
            'phase': ProductionPhase.mvp.name,
            'targetEpicIndex': '$i',
            'scope':
                'Goal: Build and connect MVP systems for Epic ${i + 1} ($beatLabel).\n\nIn Scope:\n• $beatLabel\n\nDone When: Epic ${i + 1} is playable end-to-end inside the rough representative level.',
          },
        );
        documents[newRelId] = newRelDoc;
        _persistDocument(newRelDoc);
        proj.childrenIds.add(newRelId);
        firstNewMvpId ??= newRelId;
      }
      _syncActiveProjectMetadata();

      if (firstNewMvpId != null) {
        await openGateAndRecordRetro(firstNewMvpId);
        return;
      }
    } else if (_currentPhase == ProductionPhase.mvp) {
      _currentPhase = ProductionPhase.verticalSlice;
      final newIndex = proj.childrenIds.length + 1;
      final newRelId = proj.id == 'proj_main'
          ? 'rel_v0_$newIndex'
          : '${proj.id}_rel_v0_$newIndex';
      final newRelDoc = TierDocument(
        id: newRelId,
        title:
            'v0.$newIndex: Gold Standard Level (Combined MVPs) - Vertical Slice',
        tier: TierType.release,
        parentId: proj.id,
        sections: {
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

    // Phase 4: Full Production content drops (reusing the Rough -> Polish pattern)
    _currentPhase = ProductionPhase.fullProduction;
    final existingFullProdCount = releases
        .where((r) => r.sections['phase'] == ProductionPhase.fullProduction.name)
        .length;
    final fullProdPass = existingFullProdCount + 1;
    final newIndex = proj.childrenIds.length + 1;
    final newRelId = proj.id == 'proj_main'
        ? 'rel_v0_$newIndex'
        : '${proj.id}_rel_v0_$newIndex';
    final fullProdVersion = 'v1.${fullProdPass - 1}';
    final fullProdTitle = fullProdPass == 1
        ? '$fullProdVersion: Full Production — Content, Levels & Deferred Systems - Full Production'
        : '$fullProdVersion: Full Production — World & Balance Expansion (Pass $fullProdPass) - Full Production';
    final newRelDoc = TierDocument(
      id: newRelId,
      title: fullProdTitle,
      tier: TierType.release,
      parentId: proj.id,
      sections: {
        'releaseScope': ReleaseScope.fullProduction.name,
        'phase': ProductionPhase.fullProduction.name,
        'fullProductionPass': '$fullProdPass',
        'scope':
            'Goal: Expand the verified Vertical Slice template across new levels, content waves, and previously deferred systems.\n\nIn Scope:\n• Content & level roster expansion\n• Promote deferred Out-of-Scope systems up to the Vertical Slice bar\n\nDone When: All new content and promoted systems pass playtest verification at Vertical Slice quality.',
      },
    );
    documents[newRelId] = newRelDoc;
    _persistDocument(newRelDoc);
    proj.childrenIds.add(newRelId);
    _syncActiveProjectMetadata();
    await openGateAndRecordRetro(newRelId);
  }
}
