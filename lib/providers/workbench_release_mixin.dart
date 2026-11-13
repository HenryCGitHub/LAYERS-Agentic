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
    _failedStepSynthesisFeatureIds.clear();
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
    // Carry each planned feature's shared script/scene & key tuning vars so later Epics wire directly into them.
    final firstEpicGeneratedAsset = (firstFeatureId != null
            ? (documents[firstFeatureId]?.sections['primary_asset'] ?? '')
            : '')
        .trim();
    if (firstEpicGeneratedAsset.isNotEmpty &&
        blueprint.beats.isNotEmpty &&
        blueprint.beats.first.features.isNotEmpty &&
        (blueprint.beats.first.features.first.primarySharedScriptOrScene ?? '')
            .trim()
            .isEmpty) {
      blueprint.beats.first.features.first.primarySharedScriptOrScene =
          firstEpicGeneratedAsset;
    }
    final plannedFeatureTitles = <String>[
      for (final f in blueprint.beats.first.features)
        ReleasePlannerAgent.formatFeatureContractForEpicPlanning(
          f,
          epicIndex: 0,
        ),
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
          plannedFeatureTitles.add(
            ReleasePlannerAgent.formatFeatureContractForEpicPlanning(
              ef,
              epicIndex: bIdx,
            ),
          );
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
                '- STRICT 2D GODOT NODE RULE: Use ONLY 2D scenes/nodes/Vector2 (Node2D, CharacterBody2D, Area2D, Sprite2D, CollisionShape2D, Camera2D). NEVER use 3D nodes or Vector3!'
            : 'PROJECT DIMENSION & CAMERA SPEC: 3D GAME ($gameSpec | $techSpec)\n'
                '- Use Godot 4 3D nodes (Node3D, CharacterBody3D, Area3D, MeshInstance3D, CollisionShape3D, Camera3D) and Vector3 math matching $modeLabel.',
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
          ? 'Dimension Rule: 2D ONLY (CharacterBody2D/Area2D/Sprite2D/CollisionShape2D/Vector2; NEVER 3D nodes or Vector3).\n'
          : (specLine.isNotEmpty
              ? 'Dimension Rule: 3D (Godot 4 Node3D/CharacterBody3D/CollisionShape3D/Vector3).\n'
              : '');
      return '${specLine.isNotEmpty ? 'Project Specs (match exact 2D/3D classes and camera): $specLine\n' : ''}$dimLine';
    }

    final dimLine = is2d
        ? 'Dimension Rule: 2D ONLY (2D Godot scenes/nodes/colliders/Vector2; NEVER 3D nodes or Vector3).\n'
        : (gameSpec.isNotEmpty || techSpec.isNotEmpty
            ? 'Dimension Rule: 3D (Godot 4 3D nodes/colliders/Vector3).\n'
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
      ...ReleasePlannerAgent.defaultDockStepTitles(subject: featTitle),
    ];
    final starterGuards = <String>[
      '[STATE GUARD] Block duplicate $featTitle activation while active',
    ];
    final stateNode = FeatureStateNode(
      id: '${featId}_${versionTag}_cp_1',
      name: 'Checkpoint 1: $featTitle',
      trigger: 'Playtest: $playtestGate',
      order: 0,
      coveredScope: [featTitle],
      tuningParams: const ['cooldown: 0.4 s', 'speed: 1.0 x'],
      edgeCases: starterGuards,
      parameters: {
        'releaseVersion': versionTag,
        'plannedSlices': starterTasks.join(' | '),
      },
    );
    TaskHowToBlueprint.populateDefaultUnifiedSteps(
      stateNode,
      engineHint: _activeEngineHint,
      phase: _currentPhase,
    );

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
      ...ReleasePlannerAgent.defaultDockStepTitles(subject: cleanTitle),
    ];
    final starterGuards = <String>[
      '[STATE GUARD] Block duplicate $cleanTitle activation while active',
    ];
    final stateNode = FeatureStateNode(
      id: '${featId}_${versionTag}_cp_1',
      name: 'Checkpoint 1: $cleanTitle',
      trigger: 'Playtest: Trigger $cleanTitle in the test arena',
      order: 0,
      coveredScope: [cleanTitle],
      tuningParams: const ['cooldown: 0.4 s', 'speed: 1.0 x'],
      edgeCases: starterGuards,
      parameters: {
        'releaseVersion': versionTag,
        'plannedSlices': starterTasks.join(' | '),
      },
    );
    TaskHowToBlueprint.populateDefaultUnifiedSteps(
      stateNode,
      engineHint: _activeEngineHint,
      phase: _currentPhase,
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
        cp.parameters['plannedSlices'] = normalizedTasks.join(' | ');
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
      cp.checklist = [];
      TaskHowToBlueprint.populateDefaultUnifiedSteps(
        cp,
        engineHint: _activeEngineHint,
        phase: _currentPhase,
      );
      updateFeatureStates(featureId, states);
      }
    } finally {
      _synthesizingFeatureIds.remove(featureId);
    }
    await synthesizeFeatureHowToStepsWithAi(featureId, forceRefresh: true);
  }

  /// Appends a single flat Unified Step onto a Checkpoint's Build Queue (`cpNode.checklist`),
  /// optionally tailoring ONLY that step via AI when online without disturbing existing steps.
  int addUnifiedStepToCheckpoint({
    required String featureId,
    required List<FeatureStateNode> states,
    required int checkpointIndex,
    required String title,
    GodotDockStage dockStage = GodotDockStage.code,
    String? instruction,
    String? stepPath,
    String? codeSnippet,
    String? verifyResult,
    bool tailorWithAi = true,
  }) {
    final trimmed = title.trim();
    if (trimmed.isEmpty ||
        checkpointIndex < 0 ||
        checkpointIndex >= states.length) {
      return -1;
    }
    final cpNode = states[checkpointIndex];
    cpNode.flattenLegacyNestedChecklistIfNeeded();
    final primaryAsset = (cpNode.parameters['primarySharedScriptOrScene'] ??
            documents[featureId]?.sections['primary_asset'] ??
            '')
        .trim();
    final step = Subtask(
      id: generateUniqueId('step'),
      text: trimmed,
      completed: false,
      codeTargetFile: 'custom_snippet',
      codeLanguage: stepPath?.trim().isNotEmpty == true
          ? stepPath!.trim()
          : (primaryAsset.isNotEmpty
              ? primaryAsset
              : (dockStage == GodotDockStage.scene
                  ? 'Scene Dock (.tscn)'
                  : dockStage == GodotDockStage.inspector
                      ? 'Inspector & Project Settings'
                      : dockStage == GodotDockStage.wire
                          ? 'Node Dock → Signals'
                          : 'GDScript Editor (.gd)')),
      codeSnippet: codeSnippet ?? '',
      verification: verifyResult?.trim().isNotEmpty == true
          ? verifyResult!.trim()
          : '$trimmed responds cleanly with 0 console errors.',
      specNotes: TaskHowToBlueprint.encodeThreeAreaNotes(
        instruction: instruction?.trim().isNotEmpty == true
            ? instruction!.trim()
            : 'Implement "$trimmed" inside the active Godot dock.',
        verifyMode: (dockStage == GodotDockStage.scene ||
                dockStage == GodotDockStage.inspector)
            ? 'editor'
            : 'playtest',
        stepRole: dockStage.stepRole,
      ),
    );
    cpNode.checklist.add(step);
    cpNode.parameters['manualStepOrder'] = 'true';
    final newIdx = cpNode.checklist.length - 1;
    TaskHowToBlueprint.clearCache();
    updateFeatureStates(featureId, states);

    if (tailorWithAi &&
        (GeminiAgentClient.hasKey(_apiKey) ||
            GeminiAgentClient.testMockResponder != null)) {
      final featDoc = documents[featureId];
      final contextDesc = primaryAsset.isNotEmpty
          ? 'Implement "$trimmed" on shared asset $primaryAsset'
          : 'Implement "$trimmed" for ${featDoc?.title ?? cpNode.cleanStageTitle}';
      tailorTaskHowToSubSteps(
        featureId: featureId,
        states: states,
        checkpointIndex: checkpointIndex,
        taskIndex: newIdx,
        userContext: contextDesc,
        preserveSingleStep: true,
      );
    }
    return newIdx;
  }

  /// Reorders a Unified Step cleanly inside a Checkpoint Build Queue (`cpNode.checklist`).
  bool reorderCheckpointStep({
    required String featureId,
    required List<FeatureStateNode> states,
    required int checkpointIndex,
    required int oldIndex,
    required int newIndex,
  }) {
    if (checkpointIndex < 0 || checkpointIndex >= states.length) return false;
    final cpNode = states[checkpointIndex];
    cpNode.flattenLegacyNestedChecklistIfNeeded();
    if (oldIndex < 0 ||
        oldIndex >= cpNode.checklist.length ||
        newIndex < 0 ||
        newIndex >= cpNode.checklist.length ||
        oldIndex == newIndex) {
      return false;
    }
    final moved = cpNode.checklist.removeAt(oldIndex);
    cpNode.checklist.insert(newIndex, moved);
    cpNode.parameters['manualStepOrder'] = 'true';
    TaskHowToBlueprint.clearCache();
    updateFeatureStates(featureId, states);
    return true;
  }

  /// Removes a step at [stepIndex] from a Checkpoint Build Queue.
  bool removeCheckpointStep({
    required String featureId,
    required List<FeatureStateNode> states,
    required int checkpointIndex,
    required int stepIndex,
  }) {
    if (checkpointIndex < 0 || checkpointIndex >= states.length) return false;
    final cpNode = states[checkpointIndex];
    cpNode.flattenLegacyNestedChecklistIfNeeded();
    if (stepIndex < 0 || stepIndex >= cpNode.checklist.length) return false;
    cpNode.checklist.removeAt(stepIndex);
    cpNode.parameters['manualStepOrder'] = 'true';
    TaskHowToBlueprint.clearCache();
    updateFeatureStates(featureId, states);
    return true;
  }

  /// Backwards-compatible wrapper that appends a new Unified Step directly to
  /// a Checkpoint Build Queue and tailors it via AI when available.
  int addBuildTaskToCheckpointWithAi({
    required String featureId,
    required List<FeatureStateNode> states,
    required int checkpointIndex,
    required String rawTaskTitle,
  }) {
    return addUnifiedStepToCheckpoint(
      featureId: featureId,
      states: states,
      checkpointIndex: checkpointIndex,
      title: rawTaskTitle,
      tailorWithAi: true,
    );
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

  /// Shared parser converting AI-emitted step objects into flat Unified [Subtask] items.
  List<Subtask> _buildUnifiedSubtasksFromRawMaps(
    List<dynamic> rawSteps, {
    required String idPrefix,
    required List<Subtask> existingSteps,
    Set<String>? seenScriptLines,
    String? forcedStepRole,
    String? defaultStepPath,
  }) {
    final orderedSteps =
        WorkbenchReleaseMixin.enforceIntraTaskEditorBeforeScriptOrder(rawSteps);
    final trackedLines = seenScriptLines ?? <String>{};
    final out = <Subtask>[];

    for (int i = 0; i < orderedSteps.length; i++) {
      final item = orderedSteps[i];
      final rawTitle =
          (item['title'] ?? item['shortTitle'] ?? '').toString().trim();
      var title = rawTitle.replaceFirst(_stepHeaderPrefixRegex, '').trim();
      if (forcedStepRole == 'fix' &&
          title.isNotEmpty &&
          !title.toUpperCase().startsWith('[FIX]')) {
        title = '[FIX] $title';
      }
      final path = (item['stepPath'] ?? '').toString().trim();
      final instr = (item['instruction'] ?? item['doInstruction'] ?? '')
          .toString()
          .trim();
      final area1 = (item['area1Hierarchy'] ?? '').toString().trim();
      final area2 = (item['area2Inspector'] ?? '').toString().trim();
      var code = (item['codeFormula'] ?? item['codeSnapshot'] ?? '')
          .toString()
          .trim();

      final rawPlacementRows = item['placementRows'];
      if (code.isEmpty && rawPlacementRows is List && rawPlacementRows.isNotEmpty) {
        final tbl = <String>[
          '| Node / Category | Property | Value |',
          '| --- | --- | --- |',
        ];
        for (final row in rawPlacementRows.whereType<Map>()) {
          final actor = (row['actor'] ?? row['target'] ?? '').toString().trim();
          final prop = (row['property'] ?? row['key'] ?? '').toString().trim();
          final val = (row['value'] ?? '').toString().trim();
          if (actor.isNotEmpty || prop.isNotEmpty || val.isNotEmpty) {
            tbl.add('| $actor | $prop | $val |');
          }
        }
        if (tbl.length > 2) code = tbl.join('\n');
      }

      if (code.isNotEmpty &&
          !code.startsWith('|') &&
          !code.contains('──►') &&
          !code.contains('-->')) {
        final rawLines = code.split('\n');
        final alreadyHasDiff = rawLines.any(
          (l) => l.startsWith('+') && !l.startsWith('++'),
        );
        if (!alreadyHasDiff) {
          final diffedLines = <String>[];
          final hadPriorLines = trackedLines.isNotEmpty;
          for (final l in rawLines) {
            final trimmedLine = l.trim();
            if (trimmedLine.isEmpty ||
                trimmedLine == '{' ||
                trimmedLine == '}' ||
                trimmedLine == '};' ||
                trimmedLine.startsWith('#') ||
                trimmedLine.startsWith('//')) {
              diffedLines.add(l);
              continue;
            }
            if (hadPriorLines && !trackedLines.contains(trimmedLine)) {
              diffedLines.add('+ $l');
            } else {
              diffedLines.add(l);
            }
            trackedLines.add(trimmedLine);
          }
          code = diffedLines.join('\n');
        } else {
          for (final l in rawLines) {
            final clean = l.startsWith('+') ? l.substring(1).trim() : l.trim();
            if (clean.isNotEmpty) trackedLines.add(clean);
          }
        }
      }

      final verify = (item['verifyResult'] ?? '').toString().trim();
      final verifyMode = item['verifyMode']?.toString().trim();
      final rawRole = TaskHowToBlueprint.normalizeStepRole(
        item['stepRole']?.toString(),
      );
      final rawDock = TaskHowToBlueprint.normalizeStepRole(
        item['dockStage']?.toString(),
      );
      final effectiveRole =
          (forcedStepRole != null && forcedStepRole.isNotEmpty)
              ? forcedStepRole
              : (rawRole.isNotEmpty ? rawRole : rawDock);
      if (instr.isEmpty && code.isEmpty && title.isEmpty) continue;

      final existingMatch = existingSteps.where(
        (s) =>
            title.isNotEmpty &&
            s.text.trim().toLowerCase() == title.toLowerCase(),
      );
      final prevDone = existingMatch.isNotEmpty
          ? existingMatch.first.completed
          : (i < existingSteps.length ? existingSteps[i].completed : false);
      final preservedId =
          i < existingSteps.length && existingSteps[i].id.isNotEmpty
              ? existingSteps[i].id
              : '${idPrefix}_s_${i + 1}';

      out.add(
        Subtask(
          id: preservedId,
          text: title.isNotEmpty ? title : 'Implement Step ${i + 1}',
          specNotes: TaskHowToBlueprint.encodeThreeAreaNotes(
            instruction: instr,
            area1Hierarchy: area1,
            area2Inspector: area2,
            verifyMode: verifyMode,
            stepRole: effectiveRole,
          ),
          codeSnippet: code,
          codeLanguage: path.isNotEmpty ? path : (defaultStepPath ?? ''),
          verification: verify,
          codeTargetFile: 'custom_snippet',
          completed: prevDone,
        ),
      );
    }
    return out;
  }

  /// Logs a Playtest Issue on a Checkpoint in `2. Workbench`:
  /// 1. Appends 1 cohesive flat `[FIX] <issueDescription>` Unified Step to `cpNode.checklist`.
  /// 2. Appends `[PLAYTEST GUARD] <issueDescription>` to `cpNode.edgeCases` and resets `isPlaytestPassed`.
  /// Returns the index of the newly appended `[FIX]` Unified Step.
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
    cpNode.flattenLegacyNestedChecklistIfNeeded();
    final newFixStepIndex = cpNode.checklist.length;
    final featDoc = documents[featureId];
    final featTitle = featDoc?.title ?? cpNode.cleanStageTitle;

    String explicitScript = '';
    for (final entry in FeatureStateNode.iterStepEntries(cpNode)) {
      final candidate = (entry.step.codeLanguage ?? '').trim();
      final extracted = extractPrimaryScriptResPath(candidate);
      if (extracted != null && extracted.isNotEmpty) {
        explicitScript = extracted;
        break;
      }
      if (candidate.isNotEmpty &&
          candidate != 'custom_snippet' &&
          !candidate.endsWith('.tscn') &&
          (candidate.endsWith('.gd') ||
              candidate.endsWith('.cpp') ||
              candidate.endsWith('.h') ||
              candidate.endsWith('.cs'))) {
        explicitScript = candidate;
        break;
      }
    }
    if (explicitScript.isEmpty) {
      final metaAsset = (featDoc?.sections['primary_asset'] ??
              cpNode.parameters['primarySharedScriptOrScene'] ??
              '')
          .trim();
      explicitScript = extractPrimaryScriptResPath(metaAsset) ?? '';
      if (explicitScript.isEmpty &&
          metaAsset.isNotEmpty &&
          !metaAsset.endsWith('.tscn') &&
          (metaAsset.endsWith('.gd') ||
              metaAsset.endsWith('.cpp') ||
              metaAsset.endsWith('.h') ||
              metaAsset.endsWith('.cs'))) {
        explicitScript = metaAsset;
      }
    }
    final traceMatch = GodotGdscriptGuard.parseDebuggerTrace(cleanIssue);
    final derivedAsset = TaskHowToBlueprint.deriveConcreteAssetName(featTitle);
    final snakeName = derivedAsset.snakeName.isNotEmpty
        ? derivedAsset.snakeName
        : 'gameplay_feature';
    final defaultScriptPath = traceMatch != null
        ? (traceMatch.lineNumber != null
            ? '${traceMatch.resPath}:${traceMatch.lineNumber}'
            : traceMatch.resPath)
        : (explicitScript.isNotEmpty
            ? explicitScript
            : 'res://scripts/$snakeName.gd');
    final primaryTune = cpNode.tuningParams.isNotEmpty
        ? cpNode.tuningParams.first
        : 'threshold: 1.0';

    final fixStep = Subtask(
      id: generateUniqueId('fix_step'),
      text: '[FIX] $cleanIssue',
      completed: false,
      codeLanguage: defaultScriptPath,
      codeTargetFile: 'custom_snippet',
      codeSnippet:
          '# Root-cause fix target: $cleanIssue\n+ push_warning("[PLAYTEST FIX] Clamp $primaryTune safely")',
      verification:
          'Re-run "${cpNode.playtestCondition}" with F6 -> $cleanIssue no longer reproduces.',
      specNotes: TaskHowToBlueprint.encodeThreeAreaNotes(
        instruction:
            'Inspect $defaultScriptPath and add a guard/clamp ($primaryTune) so "$cleanIssue" cannot happen.',
        verifyMode: 'playtest',
        stepRole: 'fix',
      ),
    );

    cpNode.checklist.add(fixStep);
    cpNode.isPlaytestPassed = false;
    final guardText = '[PLAYTEST GUARD] $cleanIssue';
    if (!cpNode.edgeCases.contains(guardText)) {
      cpNode.edgeCases = [...cpNode.edgeCases, guardText];
    }
    TaskHowToBlueprint.clearCache();
    updateFeatureStates(featureId, states);
    if (GeminiAgentClient.hasKey(_apiKey) ||
        GeminiAgentClient.testMockResponder != null) {
      _enrichPlaytestFixWithAi(
        featureId: featureId,
        states: states,
        checkpointIndex: checkpointIndex,
        fixTaskIndex: newFixStepIndex,
        issueDescription: cleanIssue,
      );
    } else {
      _setOfflineState();
      notifyListeners();
    }
    return newFixStepIndex;
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
    final fixStep = cpNode.checklist[fixTaskIndex];
    final featTitle = documents[featureId]?.title ?? cpNode.cleanStageTitle;
    final engineLabel = _activeEngineLabel;

    _synthesizingFeatureIds.add(featureId);
    notifyListeners();
    try {
      final specContext = _buildCompactWorkbenchSpecContext(
        singleLineProjectSpecsHeader: true,
      );
      final existingStepsSummary = [
        for (int i = 0; i < fixTaskIndex; i++)
          () {
            final s = cpNode.checklist[i];
            final path = (s.codeLanguage ?? '').trim();
            return 'Step ${i + 1}: "${s.text}"${path.isNotEmpty ? ' ($path)' : ''}';
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
      final codeExcerptLines = <String>[];
      for (int i = 0; i < fixTaskIndex && codeExcerptLines.length < 24; i++) {
        final rawCode = (cpNode.checklist[i].codeSnippet ?? '').trim();
        if (rawCode.isEmpty) continue;
        for (final line in rawCode.split('\n')) {
          final trimmedLine = line.trimRight();
          if (trimmedLine.trim().isEmpty) continue;
          codeExcerptLines.add(trimmedLine);
          if (codeExcerptLines.length >= 24) break;
        }
      }
      final existingCodeExcerptBlock = codeExcerptLines.isNotEmpty
          ? 'Current Feature Script / Graph Excerpt (patch exact functions & variables below):\n${codeExcerptLines.join('\n')}\n'
          : '';

      final traceMatch = GodotGdscriptGuard.parseDebuggerTrace(issueDescription);
      final godotFixContext = buildPromptGodotContext(
        primaryAssetHint: traceMatch?.resPath ?? primaryAsset,
        fallbackScriptPath: primaryAsset,
      );
      final traceHintLine = traceMatch != null
          ? 'Parsed Godot Debugger Trace: ${traceMatch.summaryChipLabel}\n'
          : '';

      final prompt = '''
You are the Playtest Root-Cause Debugger for LAYERS-Agentic ($engineLabel).
Diagnose this reported playtest bug on Feature "$featTitle" (Checkpoint "${cpNode.cleanStageTitle}") and return 1 cohesive root-cause [FIX] step (or 2 if Scene + Script both need edits):
$specContext$primaryAssetLine$traceHintLine${godotFixContext.isNotEmpty ? '$godotFixContext\n' : ''}${existingStepsSummary.isNotEmpty ? 'Existing Checkpoint Steps & Scripts (patch these exact assets): $existingStepsSummary\n' : ''}${structuralSnapshot.isNotEmpty ? 'Existing Scene & Script Structure:\n$structuralSnapshot\n' : ''}$existingCodeExcerptBlock
Reported Bug: "$issueDescription"
Active Tuning Parameters: ${cpNode.tuningParams.join(', ')}
Active Guards: ${cpNode.edgeCases.join(', ')}

Include surgical `scriptPatches` (`resPath`, `targetBlock`, `replaceBlock`) when modifying an existing `.gd` script. Call `commit_playtest_fix`.''';
      final json = await GeminiAgentClient.generateJson(
        prompt: prompt,
        apiKey: _apiKey,
        preferredModel: _planningModel,
        thinkingLevel: effectiveGodotCodeThinkingLevel,
        temperature: 0.3,
        functionDeclarations: const [commitPlaytestFixTool],
      );
      if (json == null) return;
      final aiFixTitle = json['fixTaskTitle']?.toString().trim() ?? '';
      final rawSteps = json['steps'];
      if (rawSteps is List && rawSteps.isNotEmpty) {
        final parsedFixSteps = _buildUnifiedSubtasksFromRawMaps(
          rawSteps,
          idPrefix: fixStep.id,
          existingSteps: [fixStep],
          forcedStepRole: 'fix',
          defaultStepPath: traceMatch?.resPath ?? primaryAsset,
        );
        if (parsedFixSteps.isNotEmpty) {
          if (aiFixTitle.isNotEmpty) {
            final cleanAiTitle = aiFixTitle.startsWith('[FIX]')
                ? aiFixTitle
                : '[FIX] $aiFixTitle';
            parsedFixSteps.first.text = cleanAiTitle;
          }
          cpNode.checklist.replaceRange(
            fixTaskIndex,
            fixTaskIndex + 1,
            parsedFixSteps,
          );
        }
      } else if (aiFixTitle.isNotEmpty) {
        fixStep.text =
            aiFixTitle.startsWith('[FIX]') ? aiFixTitle : '[FIX] $aiFixTitle';
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
      applyAiScriptPatchesResponse(
        json['scriptPatches'],
        fallbackResPath: traceMatch?.resPath ?? primaryAsset,
        featureId: featureId,
        releaseVersion: cpNode.releaseVersion,
      );
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

  /// Tailors a specific Unified Step (or splices refined steps) inside a Checkpoint's
  /// Single Feature Step List using Gemini AI.
  Future<bool> tailorTaskHowToSubSteps({
    required String featureId,
    required List<FeatureStateNode> states,
    required int checkpointIndex,
    required int taskIndex,
    required String userContext,
    bool preserveSingleStep = false,
  }) async {
    final cleanContext = userContext.trim();
    if (cleanContext.isEmpty ||
        checkpointIndex < 0 ||
        checkpointIndex >= states.length) {
      return false;
    }
    final cpNode = states[checkpointIndex];
    cpNode.flattenLegacyNestedChecklistIfNeeded();
    if (taskIndex < 0 || taskIndex >= cpNode.checklist.length) return false;
    final targetStep = cpNode.checklist[taskIndex];
    final featDoc = documents[featureId];
    final engineLabel = _activeEngineLabel;
    final stepNum = taskIndex + 1;

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
      final siblingStepsSummary = [
        for (int sIdx = 0; sIdx < cpNode.checklist.length; sIdx++)
          if (sIdx != taskIndex)
            'Step ${sIdx + 1}: "${cpNode.checklist[sIdx].text}"'
            '${(cpNode.checklist[sIdx].codeLanguage ?? '').trim().isNotEmpty ? ' (${cpNode.checklist[sIdx].codeLanguage!.trim()})' : ''}',
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
You are a senior game engine programmer assisting with a concrete implementation step.
Engine: $engineLabel
${specContext}Feature: "${featDoc?.title ?? cpNode.name}"${featGoal.isNotEmpty ? ' (Goal: $featGoal)' : ''}
Playtest Gate: "${cpNode.playtestCondition}"
Target Step ($stepNum of ${cpNode.checklist.length}): "${targetStep.text}"
$primaryAssetLine${siblingStepsSummary.isNotEmpty ? 'Sibling Steps in Same Feature (do not duplicate their work; stay on the same shared asset): $siblingStepsSummary\n' : ''}${structuralSnapshot.isNotEmpty ? 'Existing Scene & Script Structure:\n$structuralSnapshot\n' : ''}Active Tuning Parameters: ${cpNode.tuningParams.join(', ')}
Active Edge-Case Guards: ${cpNode.edgeCases.join(', ')}
Developer's Exact Scene / Node / Script Setup: "$cleanContext"

${preserveSingleStep ? 'Tailor this single step (return EXACTLY 1 refined step in subSteps[]) specifically using the developer\'s node/script names from "$cleanContext".' : 'Tailor this step (return 1 refined step, or 2–3 if splitting is clearer) specifically using the developer\'s node/script names from "$cleanContext".'}
Call `commit_tailored_task_substeps` with the tailored steps.
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
      final rawSubs = json?['subSteps'] ?? json?['steps'];
      if (rawSubs is List && rawSubs.isNotEmpty) {
        final effectiveRawSubs = preserveSingleStep
            ? [rawSubs.first]
            : rawSubs;
        final tailoredSteps = _buildUnifiedSubtasksFromRawMaps(
          effectiveRawSubs,
          idPrefix: targetStep.id,
          existingSteps: [targetStep],
          defaultStepPath: primaryAsset,
        );
        if (tailoredSteps.isNotEmpty) {
          _offlineErrorMessage = null;
          cpNode.checklist.replaceRange(
            taskIndex,
            taskIndex + 1,
            tailoredSteps,
          );
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
        _failedStepSynthesisFeatureIds.clear();
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
    return activeCp.hasAllStepsSynthesized;
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
    r'\b(?:res://[A-Za-z0-9_./-]+\.(?:gd|tscn|tres)|[A-Za-z0-9_]+\.(?:gd|tscn|tres|h|cpp)|CharacterBody[23]D|Area[23]D|RigidBody[23]D|StaticBody[23]D|CollisionShape[23]D|Camera[23]D|MeshInstance3D|Sprite2D|CanvasLayer|RayCast[23]D|[A-Z][A-Za-z0-9_]+(?:Character|Controller|Spawner|Projectile|Weapon|Manager))\b',
  );
  static final RegExp _scriptSymbolRegex = RegExp(
    r'\b(?:func|signal|void|IEnumerator)\s+([A-Za-z_][A-Za-z0-9_]*)\b',
  );
  static final RegExp _childTreeLeafNameRegex = RegExp(
    r'(?:├─|└─)\s*([A-Za-z_][A-Za-z0-9_]{2,})\b',
  );

  /// Enforces intra-task `editor_setup -> script_logic -> wire_and_verify` ordering:
  /// if within a single task an earlier pure-code step (`area1Hierarchy` empty) references
  /// a child node/component created in a later `area1Hierarchy` setup step of that same task,
  /// hoists the `area1Hierarchy` setup step ahead of the pure-code step before `STEP X.1..X.N` numbering.
  static List<Map<String, dynamic>> enforceIntraTaskEditorBeforeScriptOrder(
    List<dynamic> rawSubs,
  ) {
    final normalized = <Map<String, dynamic>>[
      for (final item in rawSubs)
        if (item is Map) Map<String, dynamic>.from(item),
    ];
    if (normalized.length <= 1) return normalized;

    Set<String> extractCreatedChildNodes(Map<String, dynamic> step) {
      final area1 = (step['area1Hierarchy'] ?? '').toString().trim();
      if (area1.isEmpty) return const <String>{};
      final names = <String>{};
      for (final m in _childTreeLeafNameRegex.allMatches(area1)) {
        final name = (m.group(1) ?? '').trim();
        if (name.length >= 3) names.add(name);
      }
      return names;
    }

    final result = List<Map<String, dynamic>>.from(normalized);
    int idx = 0;
    int guard = 0;
    while (idx < result.length && guard < result.length * result.length) {
      guard++;
      final current = result[idx];
      final currentArea1 = (current['area1Hierarchy'] ?? '').toString().trim();
      final currentRole = (current['stepRole'] ?? '').toString().trim();
      final isPureCodeOrWireStep =
          currentArea1.isEmpty || currentRole == 'script_logic';
      if (!isPureCodeOrWireStep) {
        idx++;
        continue;
      }
      final codeAndInstr =
          '${current['codeFormula'] ?? ''} ${current['instruction'] ?? current['doInstruction'] ?? ''}';
      int hoistFromIdx = -1;
      for (int laterIdx = idx + 1; laterIdx < result.length; laterIdx++) {
        final later = result[laterIdx];
        final createdNodes = extractCreatedChildNodes(later);
        if (createdNodes.isEmpty) continue;
        final referencesLaterNode = createdNodes.any(
          (nodeName) => RegExp(
            '(?:\\\$${RegExp.escape(nodeName)}\\b|GetNode[^\\n"\']*["\'][^"\']*${RegExp.escape(nodeName)}|\\b${RegExp.escape(nodeName)}\\b)',
          ).hasMatch(codeAndInstr),
        );
        if (referencesLaterNode) {
          hoistFromIdx = laterIdx;
          break;
        }
      }
      if (hoistFromIdx > idx) {
        final setupStep = result.removeAt(hoistFromIdx);
        result.insert(idx, setupStep);
        idx++;
      } else {
        idx++;
      }
    }
    return result;
  }

  /// Native Gemini Tool (`functionDeclarations`) for Stage 2 3-Area How-To synthesis (`synthesizeFeatureHowToStepsWithAi`).
  static const Map<String, dynamic> _scriptPatchesToolProperty = {
    'type': 'ARRAY',
    'description':
        'Optional surgical GDScript patch hunks applied to cumulative res:// .gd files. Use targetBlock="" to initialize a new script, or supply an exact existing targetBlock to replace/extend without rewriting unrelated code.',
    'items': {
      'type': 'OBJECT',
      'required': ['resPath', 'targetBlock', 'replaceBlock'],
      'properties': {
        'resPath': {'type': 'STRING'},
        'targetBlock': {'type': 'STRING'},
        'replaceBlock': {'type': 'STRING'},
        'note': {'type': 'STRING'},
      },
    },
  };

  static const Map<String, dynamic> _stepObjectToolProperty = {
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
      'stepRole': {
        'type': 'STRING',
        'enum': LayersTextStyleGuide.stepPhaseRoleEnum,
        'description': LayersTextStyleGuide.stepPhaseRoleSchemaDesc,
      },
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
        'description': LayersTextStyleGuide.runbookInstructionSchemaDesc,
      },
      'area1Hierarchy': {
        'type': 'STRING',
        'description':
            'Optional Godot Scene Tree hierarchy using ├─ / └─ ONLY when adding or editing nodes in this step ("" when unchanged).',
      },
      'area2Inspector': {
        'type': 'STRING',
        'description':
            'Godot Inspector property delta ONLY when modifying values in this step ("Property: Value | Property2: Value2"; "" when already in an Inspector pipe table).',
      },
      'codeFormula': {
        'type': 'STRING',
        'description':
            'Polymorphic Godot 4 payload by stepRole: (1) On stepRole="editor_setup" or "inspector_setup" (Scene Tree nodes, Inspector properties, Collision Layers/Masks, Input Map, Project Settings, Level placement), emit a Markdown pipe table ("| Node / Category | Property | Value |", e.g. "| DashTimer > Timer | Wait Time | 0.2 |"). (2) On stepRole="script_logic" or "fix", emit a Living Incremental GDScript (.gd) diff keeping existing extends/class_name/@export/func header lines plain for context and prefixing EVERY new/modified line with "+ ". (3) On stepRole="wire_and_verify", emit Node Signal Connections ("[Node.signal_name] ──► [_on_handler()]") or F6 Run Scene checks.',
      },
      'verifyMode': {
        'type': 'STRING',
        'enum': LayersTextStyleGuide.verifyModeEnum,
        'description': LayersTextStyleGuide.verifyModeSchemaDesc,
      },
      'verifyResult': {
        'type': 'STRING',
        'description': LayersTextStyleGuide.stepVerifyResultSchemaDesc,
      },
    },
  };

  /// Enforces a single shared `primarySharedScriptOrScene` and flat Godot-dock-ordered Build Queue (`steps[]`).
  static const Map<String, dynamic> commitFeatureHowToStepsTool = {
    'name': 'commit_feature_howto_steps',
    'description':
        'Commits ONE flat, Godot-dock-ordered Single Feature Step List (`steps[]`: SCENE -> INSP -> CODE -> WIRE) for the active Feature checkpoint on one shared scene/script.',
    'parameters': {
      'type': 'OBJECT',
      'required': ['primarySharedScriptOrScene', 'steps'],
      'properties': {
        'primarySharedScriptOrScene': {
          'type': 'STRING',
          'description':
              'The single shared Godot 4 scene (.tscn) and GDScript (.gd) used across the feature (e.g., "res://scenes/player_character.tscn · res://scripts/player_character.gd", "res://scenes/hud.tscn · res://scripts/hud.gd", or "res://scenes/levels/arena.tscn").',
        },
        'steps': {
          'type': 'ARRAY',
          'description':
              'Flat Single Feature Step List (3–7 cohesive steps) ordered by Godot dock workflow: editor_setup (SCENE) -> inspector_setup (INSP) -> script_logic (CODE) -> wire_and_verify (WIRE).',
          'items': _stepObjectToolProperty,
        },
        'scriptPatches': _scriptPatchesToolProperty,
      },
    },
  };

  /// Native Gemini Tool (`functionDeclarations`) for Stage 2 Single-Step "Tailor Steps" (`tailorTaskHowToSubSteps`).
  static const Map<String, dynamic> commitTailoredTaskSubStepsTool = {
    'name': 'commit_tailored_task_substeps',
    'description':
        'Commits tailored Godot 4 step(s) for a single target Build Queue step using the developer\'s exact scene/node/script names.',
    'parameters': {
      'type': 'OBJECT',
      'required': ['subSteps'],
      'properties': {
        'primarySharedScriptOrScene': {
          'type': 'STRING',
          'description':
              'Optional shared Godot 4 scene (.tscn) or script (.gd) specified by the developer.',
        },
        'subSteps': {
          'type': 'ARRAY',
          'items': _stepObjectToolProperty,
        },
      },
    },
  };

  /// Native Gemini Tool (`functionDeclarations`) for Stage 2 Playtest Bug Debugger (`_enrichPlaytestFixWithAi`).
  static const Map<String, dynamic> commitPlaytestFixTool = {
    'name': 'commit_playtest_fix',
    'description':
        'Commits a root-cause playtest bug fix with a concise [FIX] step title, optional tuning updates, a [PLAYTEST GUARD] rule, and sequential Godot 4 fix steps.',
    'parameters': {
      'type': 'OBJECT',
      'required': ['playtestGuard', 'steps'],
      'properties': {
        'fixTaskTitle': {
          'type': 'STRING',
          'description':
              'Optional concise 2-4 word Title-Case fix step title (e.g., "[FIX] Wall Clip Clamp").',
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
          'items': _stepObjectToolProperty,
        },
        'scriptPatches': _scriptPatchesToolProperty,
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
              'Sequential build steps ordered from editor_setup (Scene Tree) -> inspector_setup (Properties) -> script_logic (Code) -> wire_and_verify (Signals & F6 Playtest).',
          'items': {
            'type': 'OBJECT',
            'required': ['role', 'title'],
            'properties': {
              'role': {
                'type': 'STRING',
                'enum': [
                  'editor_setup',
                  'inspector_setup',
                  'script_logic',
                  'wire_and_verify',
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
              'Sequential build steps ordered from editor_setup (Scene Tree) -> inspector_setup (Properties) -> script_logic (Code) -> wire_and_verify (Signals & F6 Playtest).',
          'items': {
            'type': 'OBJECT',
            'required': ['role', 'title'],
            'properties': {
              'role': {
                'type': 'STRING',
                'enum': [
                  'editor_setup',
                  'inspector_setup',
                  'script_logic',
                  'wire_and_verify',
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
              'Future-phase build steps ordered from editor_setup (Scene Tree) -> inspector_setup (Properties) -> script_logic (Code) -> wire_and_verify (Signals & F6 Playtest).',
          'items': {
            'type': 'OBJECT',
            'required': ['role', 'title'],
            'properties': {
              'role': {
                'type': 'STRING',
                'enum': [
                  'editor_setup',
                  'inspector_setup',
                  'script_logic',
                  'wire_and_verify',
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
      final shortTasks = cp.flatSteps
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

      for (final sub in cp.flatSteps) {
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

  /// Extracts a compact Project-Wide Cross-Epic Asset & Symbol Registry entry (`< 220 tokens` across up to 12 features)
  /// so subsequent features in same or later Epics (`E01..EN`) reuse exact Actor/Scene/Script names, functions/signals, and tuning variables.
  String _summarizeFeatureForProjectLedger(
    TierDocument featDoc,
    int orderNumber, {
    bool includeTuningVars = true,
    bool includePlannedScopeFallback = false,
    bool isCrossEpicAnchor = false,
  }) {
    final states = FeatureStateNode.getStatesForDocument(featDoc);
    final assetTokens = <String>{};
    final hierarchyNodes = <String>{};
    final scriptSymbols = <String>{};
    final primaryAsset = (featDoc.sections['primary_asset'] ??
            (states.isNotEmpty
                ? states.last.parameters['primarySharedScriptOrScene']
                : null) ??
            '')
        .trim();
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
      for (final sub in cp.flatSteps) {
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
        final snippet = sub.codeSnippet ?? '';
        if (snippet.isNotEmpty) {
          for (final m in _scriptSymbolRegex.allMatches(snippet)) {
            final sym = (m.group(1) ?? '').trim();
            if (sym.isNotEmpty) scriptSymbols.add(sym);
          }
        }
        final combinedText =
            '${sub.text} ${decoded.cleanInstruction} $snippet';
        for (final m in _ledgerAssetTokenRegex.allMatches(combinedText)) {
          assetTokens.add(m.group(0)!);
        }
      }
    }

    if (assetTokens.isEmpty) {
      final firstEntries =
          states.isNotEmpty ? states.first.flatSteps : const <Subtask>[];
      final firstTaskSource = firstEntries.isNotEmpty
          ? '${firstEntries.first.text} ${featDoc.title}'
          : featDoc.title;
      final derivedAsset =
          TaskHowToBlueprint.deriveConcreteAssetName(firstTaskSource);
      if (derivedAsset.pascalName.isNotEmpty) {
        assetTokens.add(derivedAsset.pascalName);
      }
    }

    final parts = <String>[];
    final assetLimit = isCrossEpicAnchor ? 2 : 5;
    if (assetTokens.isNotEmpty) {
      parts.add('assets=[${assetTokens.take(assetLimit).join(', ')}]');
    } else if (pathTokens.isNotEmpty) {
      parts.add('paths=[${pathTokens.take(2).join(', ')}]');
    }
    if ((includePlannedScopeFallback || isCrossEpicAnchor) &&
        hierarchyNodes.length > 1) {
      final nodePreview =
          hierarchyNodes.take(isCrossEpicAnchor ? 3 : 4).toList();
      parts.add(
        'nodes=[${nodePreview.first} > ${nodePreview.skip(1).join(', ')}]',
      );
    }
    if (scriptSymbols.isNotEmpty) {
      parts.add(
        'funcs=[${scriptSymbols.take(isCrossEpicAnchor ? 3 : 5).join(', ')}]',
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
      final varList = isCrossEpicAnchor
          ? tuningTokens
              .map((tp) => tp.split(':').first.trim())
              .where((v) => v.isNotEmpty)
              .take(3)
          : tuningTokens.take(5);
      if (varList.isNotEmpty) {
        parts.add('vars=[${varList.join(', ')}]');
      }
    }
    final summaryTail =
        parts.isNotEmpty ? parts.join(' | ') : 'foundation initialized';
    return '- Feature #$orderNumber "${featDoc.title}": $summaryTail';
  }

  /// Synthesizes bespoke Godot 4 3-Area How-To Sub-Steps (`Scene Tree` -> `Inspector` -> `GDScript / Node Signals` -> `Run Scene`)
  /// for the active checkpoint of `featureId` using `_conversationModel`,
  /// reasoning through the project's cumulative asset state, same-Epic sibling boundaries, exact `@export` variable names, and previous checkpoints.
  Future<void> synthesizeFeatureHowToStepsWithAi(
    String featureId, {
    bool forceRefresh = false,
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
    final synthKey = '${featureId}_${activeVer}_$engineLabel';
    if (!forceRefresh && _synthesizingFeatureIds.contains(featureId)) {
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
    cpNode.flattenLegacyNestedChecklistIfNeeded();
    final rawPlannedSlices = (cpNode.parameters['plannedSlices'] ?? '').trim();
    if (cpNode.checklist.isEmpty && rawPlannedSlices.isEmpty) return;

    if (!forceRefresh && _aiSynthesizedFeatureSteps.contains(synthKey)) {
      return;
    }

    // Skip if already customized with custom_snippet across ALL steps (unless forceRefresh)
    final alreadyCustom = cpNode.hasAllStepsSynthesized;
    if (!forceRefresh && alreadyCustom) {
      _failedStepSynthesisFeatureIds.remove(featureId);
      _aiSynthesizedFeatureSteps.add(synthKey);
      return;
    }

    final existingStepHints = cpNode.flatSteps
        .map((s) => s.text.trim())
        .where((s) => s.isNotEmpty && !s.startsWith('STEP '))
        .toList();
    if (cpNode.flatSteps
        .where((s) => s.codeTargetFile == 'custom_snippet')
        .isEmpty) {
      TaskHowToBlueprint.populateDefaultUnifiedSteps(
        cpNode,
        engineHint: engineHint,
        phase: _currentPhase,
      );
    }

    _synthesizingFeatureIds.add(featureId);
    notifyListeners();

    try {
      final projTitle = activeProject?.title ?? 'Game Prototype';
      final sliceHints = rawPlannedSlices.isNotEmpty
          ? rawPlannedSlices
              .split('|')
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toList()
          : (existingStepHints.isNotEmpty
              ? existingStepHints
              : cpNode.coveredScope.take(4).toList());
      final sliceSummaries = <String>[
        for (int sIdx = 0; sIdx < sliceHints.length; sIdx++)
          '${sIdx + 1}. "${sliceHints[sIdx]}"',
      ];

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
        'character' =>
          'res://scenes/player_character.tscn (CharacterBody3D/2D) + res://scripts/player_character.gd and Project Input Map',
        'ui' =>
          'res://scenes/${featSnake}_hud.tscn (CanvasLayer / Control) + res://scripts/${featSnake}_hud.gd',
        'level' => hasPrecedingCharacterFeature
            ? 'res://scenes/levels/$featSnake.tscn (Node3D/2D with StaticBody floor/walls, Area bounds, and player_character.tscn instance at spawn)'
            : 'res://scenes/levels/$featSnake.tscn (Node3D/2D with StaticBody floor/walls and temporary RigidBody + CollisionShape test body at spawn)',
        _ =>
          'res://scenes/$featSnake.tscn (Node3D/2D / Area / StaticBody) + res://scripts/$featSnake.gd',
      };
      final needsFirstFeaturePlayerBootstrap =
          (currentArchetype == 'level' || currentArchetype == 'actor') &&
              !hasPrecedingCharacterFeature &&
              effectiveCpIndex == 0;
      final playerBootstrapLabel = hasPrecedingCharacterFeature
          ? 'PlayerSpawn Marker node above the floor instancing player_character.tscn'
          : 'temporary test RigidBody + CollisionShape node above the floor in the main scene so F6 Run Scene spawns a testable body';
      final projectBuildStateContext = isGreenfieldFirstFeature
          ? 'Project Build State: FIRST ${currentArchetype.toUpperCase()} FEATURE IN PROJECT (Greenfield Setup). On the first SCENE step, explicitly instruct how to set up ${currentArchetype == 'level' ? 'the Godot Level Scene (.tscn) & Scene Tree geometry' : (currentArchetype == 'character' ? 'the Player Character Scene (.tscn) & Script (.gd)' : (currentArchetype == 'ui' ? 'the Godot Control / CanvasLayer HUD Scene (.tscn)' : 'the Godot Feature Scene (.tscn) & Script (.gd)'))} ($engineAssetHint), specify its exact `res://` folder path, and ${needsFirstFeaturePlayerBootstrap ? 'include placing a $playerBootstrapLabel so pressing F6 spawns cleanly onto the floor.' : 'explain how to instance or attach it inside the main scene.'}'
          : 'Project Build State: Feature #${featOrderIdx + 1} in the release (preceded by: $compactPrecedingSummary). Reuse and extend existing `res://scenes/` & `res://scripts/` files ($engineAssetHint) for player-attached mechanics, or create this feature\'s dedicated `.tscn`/`.gd` and connect signals to the player.';

      // Build Project-Wide Cross-Epic Asset & Symbol Registry (`< 220 tokens`, max 12 entries):
      // 1) All same-Epic earlier siblings (full assets, scene nodes, functions/signals, planned scope fallback, and tuning vars)
      // 2) Cross-Epic earlier foundational features (`E01..E_{current-1}`: shared scripts/scenes, functions/signals, and tuning var names)
      //    so `E03` Weapons/Tools and `E04` Economy/HUD wire directly into `E01`/`E02` scripts instead of inventing duplicates!
      final cumulativeLedgerLines = <String>[];
      if (featOrderIdx > 0) {
        final sameEpicEarlier = <int>[
          for (int pIdx = 0; pIdx < featOrderIdx; pIdx++)
            if (feat.parentId != null &&
                allReleaseFeatures[pIdx].parentId == feat.parentId)
              pIdx,
        ];
        final crossEpicEarlier = <int>[
          for (int pIdx = 0; pIdx < featOrderIdx; pIdx++)
            if (feat.parentId == null ||
                allReleaseFeatures[pIdx].parentId != feat.parentId)
              pIdx,
        ];
        final maxTotalLedger = 12;
        final keptSameEpic = sameEpicEarlier.length <= 6
            ? sameEpicEarlier
            : sameEpicEarlier.sublist(sameEpicEarlier.length - 6);
        final remainingSlots = maxTotalLedger - keptSameEpic.length;
        final keptCrossEpic = crossEpicEarlier.length <= remainingSlots
            ? crossEpicEarlier
            : <int>[
                crossEpicEarlier.first,
                if (crossEpicEarlier.length > 1 && remainingSlots > 2)
                  crossEpicEarlier[1],
                ...crossEpicEarlier.sublist(
                  crossEpicEarlier.length -
                      (remainingSlots -
                          (crossEpicEarlier.length > 1 && remainingSlots > 2
                              ? 2
                              : 1)),
                ),
              ];
        final selectedPrecedingIndices = <int>{
          ...keptSameEpic,
          ...keptCrossEpic,
        }.toList()
          ..sort();
        for (final pIdx in selectedPrecedingIndices) {
          final isSameEpic = feat.parentId != null &&
              allReleaseFeatures[pIdx].parentId == feat.parentId;
          cumulativeLedgerLines.add(
            _summarizeFeatureForProjectLedger(
              allReleaseFeatures[pIdx],
              pIdx + 1,
              includeTuningVars: true,
              includePlannedScopeFallback: isSameEpic,
              isCrossEpicAnchor: !isSameEpic,
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

      final usesGdExtension = (engineHint ?? '').toLowerCase().contains('gdextension') ||
          (engineHint ?? '').toLowerCase().contains('c++');
      final targetEngineMode = usesGdExtension
          ? 'GODOT 4 (GDScript + GDExtension C++)'
          : 'GODOT 4 (GDScript)';

      final compactSpecBlock = _buildCompactWorkbenchSpecContext(
        includeFullDimensionBanner: true,
        targetEngineMode: targetEngineMode,
      );

      final phaseInstructionBlock = switch (_currentPhase) {
        ProductionPhase.prototype =>
          'ACTIVE PRODUCTION PHASE: 01 · PROTOTYPE (GREYBOX TESTBED)\n- Use primitive collision shapes (BoxShape3D / CapsuleShape3D / RectangleShape2D), greybox meshes/ColorRect sprites, and direct Inspector `@export` variables.\n- Focus strictly on proving the core mechanic feel and F6 Run Scene loop.\n- Keep greybox steps lean and cohesive (~3–6 total steps in 1 flat dock-ordered queue; avoid bloat).',
        ProductionPhase.mvp =>
          'ACTIVE PRODUCTION PHASE: 02 · MVP (FUNCTIONAL DELTA UPGRADE)\n- Extend the existing v0.1 `.tscn` scene and `.gd` script in-place (NEVER recreate from scratch).\n- Wire cross-system signals, HUD counters, or progression loops.',
        ProductionPhase.verticalSlice =>
          'ACTIVE PRODUCTION PHASE: 03 · VERTICAL SLICE (GOLD STANDARD POLISH)\n- Attach AnimationPlayer/GPUParticles/AudioStreamPlayer/Camera/Control feedback nodes and polish triggers to the existing mechanic without rewriting core movement/combat math.',
        ProductionPhase.fullProduction =>
          'ACTIVE PRODUCTION PHASE: 04 · FULL PRODUCTION (FULL-GAME BUILD-OUT)\n- Build the full-game feature on top of the finished core systems (reuse their `.gd` scripts and `@export` variable names).\n- Match the Vertical Slice quality bar; use data-driven Godot Custom `Resource` (`.tres`) files for content rosters.',
        ProductionPhase.postLaunch =>
          'ACTIVE PRODUCTION PHASE: 05 · POST-LAUNCH & LIVE OPS (PATCH & EXPANSION)\n- Apply surgical `@export` balance adjustments, modular DLC/biome `.tscn` hooks, and regression guards without breaking existing save/state schemas.',
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
          ? 'a clean Markdown Godot Level Scene Placement & Inspector Table (e.g.\n| Node (Type) | Property / Transform | Value |\n| --- | --- | --- |\n| ArenaFloor (StaticBody3D) | Position / Size | Vector3(0, 0, 0) / Vector3(20, 0.5, 20) |\n| PlayerSpawn (Marker3D) | Position | Vector3(0, 2, 0) |\n). Do NOT write runtime `_ready()` code just to place static blockout floors/walls, use meters/pixels matching 3D/2D dimension, and pre-calculate literal numeric Position/Size values from Active Tuning Parameters'
          : 'STRICT CONFIG vs. DIFF vs. SIGNAL SPLIT BY `stepRole`: (A) When `stepRole == "editor_setup"` or `"inspector_setup"` (creating `.tscn` child nodes, Inspector properties like `Motion Mode`, `Position`, `Radius`, Collision Layers/Masks, Project Settings, or `Input Map` actions), ALWAYS emit a clean Markdown Inspector / Input Map pipe table (`| Node / Category | Property | Value |`, e.g. `| CharacterBody3D > Motion Mode | Motion Mode | Grounded |` or `| DashTimer > Timer | Wait Time | 0.2 |` or `| Input Map > dash | Key | Shift |`) and NEVER emit runtime `_ready()` property setters! (B) When `stepRole == "script_logic"`, emit 3-8 lines of Living Incremental GDScript (`.gd`) keeping existing `extends` / `@export` / `func` signature context lines plain and prefixing EVERY new or modified line added in THIS step with `+ ` (e.g. `+ @export var dash_speed: float = 18.0\n+ func _trigger_dash() -> void:`${usesGdExtension ? '; for native performance hotspots show clean GDExtension C++ (.hpp/.cpp) with `+ ` on added lines' : ''}). (C) When `stepRole == "wire_and_verify"`, emit Godot Node Signal connections (`[Node.signal_name] ──► [_on_handler_method()]`) or concise F6 Run Scene debug checks';

      final godotStepContext = buildPromptGodotContext(
        primaryAssetHint: existingPrimaryAsset,
        fallbackScriptPath: engineAssetHint,
      );

      final prompt = '''
You are the Principal Godot 4 Architect ($targetEngineMode) for "$projTitle".
Synthesize ONE flat, Godot-dock-ordered Single Feature Step List (`steps[]`: 3–7 cohesive steps) using native Godot 4 terminology (`FileSystem`, `Scene Tree`, `Inspector`, `Node -> Signals`, `GDScript Editor`, `Input Map`, `Project Settings`, `@export`, `@onready`, `F6 Run Current Scene`) for Feature "${feat.title}" (Checkpoint "${cpNode.cleanStageTitle}").
${compactSpecBlock.isNotEmpty ? '$compactSpecBlock\n' : ''}${featureOwnScopeBlock.isNotEmpty ? '$featureOwnScopeBlock\n' : ''}$phaseInstructionBlock
$projectBuildStateContext
${godotStepContext.isNotEmpty ? '$godotStepContext\n' : ''}${cumulativeLedgerLines.isNotEmpty ? 'CUMULATIVE PROJECT LEDGER (Epic-Scoped & Root Project Anchors — reuse exact Scene/Script & `@export` Variable names):\n${cumulativeLedgerLines.join('\n')}' : ''}
${sameEpicSiblingBoundaryLines.isNotEmpty ? sameEpicSiblingBoundaryLines.join('\n') : ''}
${coreSystemsReferenceLines.isNotEmpty ? 'CORE SYSTEMS REFERENCE (finished STABLE core scripts — plug into these, NEVER rebuild them):\n${coreSystemsReferenceLines.join('\n')}' : ''}
Planned Feature Slices / Scope Targets:
${sliceSummaries.isNotEmpty ? sliceSummaries.join('\n') : '- "${feat.title}"'}
Active Tuning Parameters (MUST use exact variable names): ${cpNode.tuningParams.join(', ')}
Active Guards (MUST enforce in code and cover without raw [TAG] brackets in prose): ${cleanEdgeCases.join(', ')}
${priorCheckpointSnapshot.isNotEmpty ? 'Previous Checkpoints Structural Snapshot (extend existing nodes & functions in-place):\n$priorCheckpointSnapshot' : ''}

CRITICAL SINGLE FEATURE STEP LIST RULES (`SCENE -> INSP -> CODE -> WIRE`):
- ONE SHARED ASSET ACROSS ALL STEPS: Choose ONE primary scene/script pair for "${feat.title}" matching $targetEngineMode ($engineAssetHint). NEVER create a throwaway test scene/script in Step 1 just to replace it later, and NEVER use the word "canonical" in step titles or instructions.
- STRICT GODOT-DOCK GROUPED STEP ORDER (3–7 cohesive steps total — NEVER repeat `SCENE -> CODE -> WIRE` per micro-slice):
  1) `editor_setup` (`SCENE`) FIRST: Build/attach ALL needed `.tscn` child nodes (`area1Hierarchy`) BEFORE any Inspector tuning or GDScript references `\$NodeName` / `@onready`.
  2) `inspector_setup` (`INSP`) SECOND: Configure Collision Layers/Masks, Inspector properties (`area2Inspector`), or `Input Map` actions in 1 focused step.
  3) `script_logic` (`CODE`) THIRD: Declare `@export var` tuning variables (`${cpNode.tuningParams.join(', ')}`) and implement the core GDScript behavior & state guards (${cleanEdgeCases.join(', ')}) incrementally in 1–2 focused steps on the shared `.gd` script.
  4) `wire_and_verify` (`WIRE`) LAST: Connect Godot Node Signals (`[Node.signal_name] ──► [_on_handler()]`), hook visual/audio feedback cues or main-scene placement, and verify with `F6`.
- HONEST DUAL-MODE CHECKS (`verifyMode: "editor"` vs `"playtest"`):
  * Set `verifyMode: "editor"` on structural/Inspector/declaration steps where pressing F6 cannot yet test runtime behavior (`"Inspect Scene Tree → DashTimer appears under PlayerCharacter"`).
  * Set `verifyMode: "playtest"` once runtime wiring is runnable with `F6` (`"Press Shift in F6 → Player dashes forward"`).
- FORMATTING:
  * In `area2Inspector`, list ONLY the 1–3 properties modified in THIS step.
  * In `instruction` (DO), ALWAYS emit 2-4 short newline-separated imperative micro-actions (`- <Dock/Node> → <Command Verb + Exact Value>`), never a prose paragraph.
  * In `codeFormula`, emit $codeFormulaModeGuide.
  * Whenever modifying or initializing a `.gd` file, also emit `scriptPatches` (`resPath`, `targetBlock`, `replaceBlock`) so the cumulative script updates cleanly without overwriting unrelated code.

Call `commit_feature_howto_steps` with `primarySharedScriptOrScene`, the flat dock-ordered `steps[]` array, and `scriptPatches`.''';

      final json = await GeminiAgentClient.generateJson(
        prompt: prompt,
        apiKey: _apiKey,
        preferredModel: _conversationModel,
        thinkingLevel: effectiveGodotCodeThinkingLevel,
        temperature: 0.25,
        functionDeclarations: const [commitFeatureHowToStepsTool],
      );
      var primaryAsset =
          (json?['primarySharedScriptOrScene'] ?? '').toString().trim();
      if (primaryAsset.isNotEmpty) {
        feat.sections['primary_asset'] = primaryAsset;
        cpNode.parameters['primarySharedScriptOrScene'] = primaryAsset;
      } else if (existingPrimaryAsset.isNotEmpty) {
        primaryAsset = existingPrimaryAsset;
        cpNode.parameters['primarySharedScriptOrScene'] = existingPrimaryAsset;
      }
      applyAiScriptPatchesResponse(
        json?['scriptPatches'],
        fallbackResPath: primaryAsset.isNotEmpty ? primaryAsset : engineAssetHint,
        featureId: featureId,
        releaseVersion: cpNode.releaseVersion,
      );
      final rawStepMaps = <dynamic>[];
      final directSteps = json?['steps'];
      if (directSteps is List && directSteps.isNotEmpty) {
        rawStepMaps.addAll(directSteps);
      } else {
        // Backward compatibility for test mocks returning legacy `tasks[].subSteps[]`.
        final legacyTasks = json?['tasks'];
        if (legacyTasks is List && legacyTasks.isNotEmpty) {
          for (final rawTask in legacyTasks.whereType<Map>()) {
            final subs = rawTask['subSteps'];
            if (subs is List && subs.isNotEmpty) {
              rawStepMaps.addAll(subs);
            }
          }
        }
      }

      if (rawStepMaps.isEmpty) {
        _failedStepSynthesisFeatureIds.add(featureId);
        return;
      }

      final previousSteps = cpNode.flatSteps;
      final parsedSteps = _buildUnifiedSubtasksFromRawMaps(
        rawStepMaps,
        idPrefix: '${cpNode.id}_step',
        existingSteps: previousSteps,
        defaultStepPath:
            primaryAsset.isNotEmpty ? primaryAsset : engineAssetHint,
      );

      if (parsedSteps.isEmpty) {
        _failedStepSynthesisFeatureIds.add(featureId);
        return;
      }

      final finalSteps = cpNode.parameters['manualStepOrder'] == 'true'
          ? parsedSteps
          : TaskHowToBlueprint.orderSubtasksByGodotDock(parsedSteps);

      cpNode.checklist = finalSteps;
      cpNode.parameters.remove('needsAiStepSynthesis');

      if (cpNode.hasAllStepsSynthesized) {
        _failedStepSynthesisFeatureIds.remove(featureId);
        _aiSynthesizedFeatureSteps.add(synthKey);
      }
      seedCumulativeScriptFromStepsIfMissing(
        primaryAssetString:
            primaryAsset.isNotEmpty ? primaryAsset : engineAssetHint,
        states: states,
        featureId: featureId,
        releaseVersion: cpNode.releaseVersion,
      );
      TaskHowToBlueprint.clearCache();
      updateFeatureStates(featureId, states);
    } catch (_) {
      _failedStepSynthesisFeatureIds.add(featureId);
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
  String buildActiveReleaseCodingAgentMarkdown() {
    final draft = _conceptDraft;
    final proj = activeProject;
    final rel = activeRelease;
    final activeVer = activeReleaseVersionTag;
    final engineHint = _activeEngineHint;
    final usesGdExtension = (engineHint ?? '').toLowerCase().contains('gdextension') ||
        (engineHint ?? '').toLowerCase().contains('c++');
    final effectiveEngineTarget = usesGdExtension
        ? 'GODOT 4 (GDScript + GDExtension C++)'
        : 'GODOT 4 (GDScript)';
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

    final contract = activeGodotContract;
    final trackedFiles = activeProjectGodotFiles;
    if (contract.hasAnyEntries || trackedFiles.isNotEmpty) {
      sb.writeln('\n## 1B. Godot 4 Contract & Cumulative Cloud Scripts');
      sb.writeln(
        '- **Godot 4 Strict Idioms**: Always use `@export` (never `export var`), `@onready` (never `onready var`), `move_and_slide()` (zero positional velocity arg), `await` (never `yield`), and Godot 4 callable signal syntax `node.sig.connect(handler)`.',
      );
      if (contract.physicsLayers.isNotEmpty) {
        sb.writeln('\n### Physics Layers (${contract.is3D ? "3D" : "2D"})');
        sb.writeln('| Layer # | Bitmask Value | Name |');
        sb.writeln('| :--- | :--- | :--- |');
        final keys = contract.physicsLayers.keys.toList()..sort();
        for (final k in keys) {
          final maskVal = GodotProjectContract.bitmaskForLayerNumbers([k]);
          sb.writeln('| Layer $k | `$maskVal` | `${contract.physicsLayers[k]}` |');
        }
      }
      if (contract.inputActions.isNotEmpty) {
        sb.writeln(
          '\n- **InputMap Actions**: ${contract.inputActions.map((a) => '`$a`').join(', ')}',
        );
      }
      if (contract.autoloads.isNotEmpty) {
        sb.writeln(
          '- **Autoload Singletons**: ${contract.autoloads.map((a) => '`${a.name}` (`${a.resPath}`)').join(', ')}',
        );
      }
      if (contract.groups.isNotEmpty) {
        sb.writeln(
          '- **Node Groups**: ${contract.groups.map((g) => '`$g`').join(', ')}',
        );
      }
      if (trackedFiles.isNotEmpty) {
        sb.writeln('\n### Tracked Cumulative Godot Files (`TierType.codeFile`)');
        for (final vf in trackedFiles) {
          final lineCount = vf.content.trim().isEmpty
              ? 0
              : vf.content.split('\n').length;
          sb.writeln(
            '- `${vf.resPath}` (`${vf.releaseVersion}`, $lineCount lines)',
          );
        }
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
      'Always use these exact `@export` variable identifiers across GDScript files, Godot Inspector docks, and `.tscn` scenes:',
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
          final unifiedSteps = TaskHowToBlueprint.resolveUnifiedSteps(
            checkpointNode: cp,
            engineHint: engineHint,
            phase: _currentPhase,
          );
          _writeUnifiedStepsMarkdown(sb, unifiedSteps);
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
  String buildActiveFeatureCodingAgentPrompt(String featureId) {
    final feat = documents[featureId];
    if (feat == null) return '';
    final draft = _conceptDraft;
    final proj = activeProject;
    final activeVer = activeReleaseVersionTag;
    final engineHint = _activeEngineHint;
    final usesGdExtension = (engineHint ?? '').toLowerCase().contains('gdextension') ||
        (engineHint ?? '').toLowerCase().contains('c++');
    final effectiveEngineTarget = usesGdExtension
        ? 'GODOT 4 (GDScript + GDExtension C++)'
        : 'GODOT 4 (GDScript)';
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
      sb.writeln('\n## 4. Godot Dock Build Queue ($effectiveEngineTarget)');
      final unifiedSteps = TaskHowToBlueprint.resolveUnifiedSteps(
        checkpointNode: cpNode,
        engineHint: engineHint,
        phase: _currentPhase,
      );
      _writeUnifiedStepsMarkdown(sb, unifiedSteps);
    }

    return sb.toString();
  }

  void _writeUnifiedStepsMarkdown(
    StringBuffer sb,
    List<TaskHowToSubStep> unifiedSteps,
  ) {
    for (final sub in unifiedSteps) {
      final sMark = sub.subtask.completed ? 'x' : ' ';
      final dockTag = sub.resolvedDockStage.badge;
      sb.writeln(
        '- [$sMark] **${sub.stepNumberLabel} [$dockTag] — ${sub.shortTitle}** (${sub.instruction})',
      );
      if (sub.area1Hierarchy != null &&
          sub.area1Hierarchy!.trim().isNotEmpty) {
        sb.writeln(
          '  - **Node Hierarchy (`.tscn`)**: `${sub.area1Hierarchy!.replaceAll('\n', ' / ')}`',
        );
      }
      if (sub.area2Inspector != null &&
          sub.area2Inspector!.trim().isNotEmpty) {
        sb.writeln(
          '  - **Inspector / Layer**: `${sub.area2Inspector!.replaceAll('\n', ' | ')}`',
        );
      }
      if (sub.codeFormula.trim().isNotEmpty) {
        sb.writeln('  ```');
        for (final line in sub.codeFormula.trim().split('\n')) {
          sb.writeln('  $line');
        }
        sb.writeln('  ```');
      }
      if (sub.verifyResult.trim().isNotEmpty) {
        final verifyHeading =
            sub.isEditorCheck ? 'Check in Editor' : 'Verify';
        sb.writeln('  - *$verifyHeading*: ${sub.verifyResult.trim()}');
      }
    }
  }

  /// Two-Way Godot Sync: Parses a developer's pasted GDScript (`.gd`) or GDExtension C++ snippet
  /// (using `_conversationModel` when online + a deterministic multi-line regex parser fallback)
  /// to update changed numeric `@export var` values and append newly added `# [GUARD]` checks
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

    // 1. Deterministic regex extraction FIRST (0 LLM tokens; handles Godot 4 @export var across declarations)
    String cleanNumericValue(String raw) {
      var val = raw
          .split('//')
          .first
          .split('#')
          .first
          .trim()
          .replaceAll(_trailingSemicolonRegex, '')
          .trim();
      final floatMatch = _floatSuffixRegex.firstMatch(val);
      if (floatMatch != null) {
        final numPart = floatMatch.group(1)!;
        val = numPart.contains('.') ? numPart : '$numPart.0';
      }
      return val;
    }

    // 1a. Godot 4 @export var / typed var declarations
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
      final alreadySynthesized =
          activeCp != null && activeCp.hasAllStepsSynthesized;
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

}
