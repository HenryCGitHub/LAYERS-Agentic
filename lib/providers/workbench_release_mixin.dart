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
  /// `3. Background E02..EN Features`).
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

    final currentGen = ++_progressivePlanGeneration;
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

    // Background Priority-First: Populate E02..EN Features in the Outliner immediately
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
        _progressivePlanGeneration != generation ||
        _activeProjectId != startProjectId ||
        _activeReleaseId != startReleaseId;

    // Populate E02..EN Features top-down one Epic at a time in the Outliner,
    // carrying each planned feature's key tuning vars so later Epics wire directly into them.
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
  }

  static final RegExp _minorVerRegex = RegExp(
    r'v0\.(\d+)',
    caseSensitive: false,
  );
  static final RegExp _noPrefixRegex = RegExp(
    r'^no\s+',
    caseSensitive: false,
  );
  static final RegExp _goalPrefixRegex = RegExp(
    r'^goal:\s*',
    caseSensitive: false,
  );

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
        .map((s) => '"${s.title}"')
        .toList();

    final prompt = '''
You are the Systems Designer for "$projTitle" ($engineLabel).
Enrich this newly proposed Feature ("${targetFeat.title}" inside Epic "$beatTitle" for ${bp.releaseVersionTag}) so its goal, scope, doneWhen criteria, numeric tuning parameters, and edge-case guards fit "$projTitle".
$specContext${siblingTitles.isNotEmpty ? 'Sibling Features in "$beatTitle": ${siblingTitles.join(', ')}\n' : ''}${GeminiAgentClient.compactStyleRules}
- Include 2–3 "paramName: numericValue unit" entries in tuningParams and 1–2 [STATE GUARD] rules in edgeCases.
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
    _enrichingFeatureIds.add(featureId);
    notifyListeners();
    try {
      final projTitle = activeProject?.title ?? 'Game Prototype';
      final engineLabel = _activeEngineLabel;
      final specContext = _buildCompactWorkbenchSpecContext();
      final siblingTitles = featDoc.parentId == null
          ? const <String>[]
          : featuresForBeat(featDoc.parentId!)
              .where((s) => s.id != featureId)
              .map((s) => '"${s.title}"')
              .toList();
      final prompt = '''
You are the Systems Designer for "$projTitle" ($engineLabel).
Tailor this newly added Feature ("${featDoc.title}" inside Epic "$beatTitle") so its goal, scope, doneWhen criteria, numeric tuning parameters, and edge-case guards fit "$projTitle".
$specContext${siblingTitles.isNotEmpty ? 'Sibling Features in "$beatTitle": ${siblingTitles.join(', ')}\n' : ''}${GeminiAgentClient.compactStyleRules}
- Include 2–3 "paramName: numericValue unit" entries in tuningParams and 1–2 [STATE GUARD] rules in edgeCases.
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
      updateFeatureStates(featureId, states);
      }
    } finally {
      _enrichingFeatureIds.remove(featureId);
      notifyListeners();
    }
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

  /// Logs a Playtest Issue on a Checkpoint in `2. Workbench` instantaneously (0 AI calls):
  /// 1. Appends 1 literal `[FIX] <issueDescription>` issue item to `cpNode.checklist`.
  /// 2. Appends `[PLAYTEST GUARD] <issueDescription>` to `cpNode.edgeCases` and resets `isPlaytestPassed`.
  /// Returns the index of the newly appended `[FIX]` issue item.
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
    final traceMatch = GodotGdscriptGuard.parseDebuggerTrace(cleanIssue);

    final fixStep = Subtask(
      id: generateUniqueId('fix_step'),
      text: '[FIX] $cleanIssue',
      completed: false,
      codeLanguage: traceMatch?.resPath ?? 'fix',
      codeTargetFile: 'playtest_fix',
      verification: 'Re-test: $cleanIssue is resolved with 0 console errors.',
    );

    cpNode.checklist = [...cpNode.checklist, fixStep];
    cpNode.isPlaytestPassed = false;
    final lowerIssue = cleanIssue.toLowerCase();
    final guardText = '[PLAYTEST GUARD] $cleanIssue';
    if (!cpNode.edgeCases.any((g) => g.toLowerCase().contains(lowerIssue))) {
      cpNode.edgeCases = [...cpNode.edgeCases, guardText];
    }
    updateFeatureStates(featureId, states);
    return newFixStepIndex;
  }

  /// Stage 2 -> Stage 3: User approves the Release Plan Gate; Executor Agent builds or evolves the Release hierarchy.
  Future<void> approveAndExecuteReleasePlan() async {
    final bp = _releaseBlueprint;
    final relDoc = activeRelease;
    if (bp == null || relDoc == null) return;

    _progressivePlanGeneration++;
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
    } finally {
      _isAgentBusy = false;
      _agentProgressStep = null;
      notifyListeners();
    }
  }

  /// Native Gemini Tool (`functionDeclarations`) for Stage 2 "+ Add Feature" in Left Outliner (`_enrichLiveFeatureWithAi`).
  static const Map<String, dynamic> commitLiveFeatureEnrichmentTool = {
    'name': 'commit_live_feature_enrichment',
    'description':
        'Enriches a newly added Feature card in the active Epic with its goal, inScope, doneWhen, checkpoint title, playtest gate, numeric tuning parameters, and edge-case guards.',
    'parameters': {
      'type': 'OBJECT',
      'required': [
        'goal',
        'doneWhen',
        'checkpointTitle',
        'playtestGate',
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
        'checkpointTitle': {'type': 'STRING'},
        'playtestGate': {
          'type': 'STRING',
          'description': LayersTextStyleGuide.causalTriggerResultSchemaDesc,
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
        'Commits the 3-dimensional Feature Inbox triage (WHEN releaseTimingMode, WHERE integrationMode & targetBeatId, HOW feature spec, tuningParams, edgeCases).',
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
        'architectureHowSummary': {
          'type': 'ARRAY',
          'items': {'type': 'STRING'},
        },
        'checkpointTitle': {'type': 'STRING'},
        'playtestGate': {
          'type': 'STRING',
          'description': LayersTextStyleGuide.causalTriggerResultSchemaDesc,
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

  /// Generates a drop-in `AGENTS.md` / `.cursorrules` specification file for the Active Release (`v0.1`, `v0.2`, etc.)
  /// containing the release's scope, Epic/Feature hierarchy, tuning variables, playtest guards, and open `[FIX]` issues.
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
          sb.writeln(
            '  - **${f.title}** (${f.estimatedHours}h): ${f.goal}',
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
          sb.writeln(
            '  - **${feat.title}** [`$lc` · $p% verified · ${feat.estimatedDuration}]',
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

    sb.writeln('\n## 3. Canonical Tuning Variables');
    sb.writeln(
      'Use these named tunable parameters and target values across features in this release:',
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
      'Verify every boundary condition and playtest guard below before marking a feature Passed:',
    );
    if (allGuards.isEmpty) {
      sb.writeln('- *(No edge-case guards registered yet)*');
    } else {
      for (final g in allGuards) {
        sb.writeln('- **${g.feature}**: `${g.guard}`');
      }
    }

    sb.writeln('\n## 5. Feature Specifications & Playtest Gates');
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
        final rawGoal =
            (feat.sections['scope'] ?? feat.sections['goal'] ?? '').trim();
        final goalLine = rawGoal.isEmpty
            ? ''
            : rawGoal
                .split('\n')
                .first
                .replaceFirst(_goalPrefixRegex, '')
                .trim();
        for (final cp in effectiveStates) {
          sb.writeln(
            '\n#### ${feat.title} — ${cp.cleanStageTitle} (${cp.releaseVersion})',
          );
          sb.writeln('- **Status**: ${cp.unifiedStatusLabel}');
          if (goalLine.isNotEmpty) {
            sb.writeln('- **Goal**: $goalLine');
          }
          if (cp.coveredScope.isNotEmpty) {
            sb.writeln('- **In Scope**:');
            for (final item in cp.coveredScope) {
              final clean = item.trim();
              if (clean.isNotEmpty) {
                sb.writeln('  - $clean');
              }
            }
          }
          if (cp.tuningParams.isNotEmpty) {
            sb.writeln(
              '- **Tuning Variables**: ${cp.tuningParams.map((t) => '`$t`').join(', ')}',
            );
          }
          if (cp.edgeCases.isNotEmpty) {
            sb.writeln('- **Playtest Guards**:');
            for (int gIdx = 0; gIdx < cp.edgeCases.length; gIdx++) {
              final g = cp.edgeCases[gIdx].trim();
              if (g.isEmpty) continue;
              final checked = cp.isGuardSignedOff(gIdx, g) ? 'x' : ' ';
              sb.writeln('  - [$checked] $g');
            }
          }
          final openFixes = cp.openFixItems;
          if (openFixes.isNotEmpty) {
            sb.writeln('- **Open Playtest Issues (`[FIX]`)**:');
            for (final fix in openFixes) {
              sb.writeln('  - [ ] ${fix.text.trim()}');
            }
          }
          sb.writeln('- **Done When**: ${cp.playtestCondition}');
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
      '# FEATURE SPECIFICATION — ${feat.title} ($activeVer · $effectiveEngineTarget)',
    );
    sb.writeln(
      '> Use this Feature Spec to build, wire, and playtest this single feature in **$effectiveEngineTarget**.',
    );

    sb.writeln('\n## 1. Feature Scope & Context');
    sb.writeln('- **Project**: $projectTitle (`$activeVer`)');
    sb.writeln('- **Target Engine**: $effectiveEngineTarget');
    sb.writeln('- **Epic**: $epicLabel');
    sb.writeln('- **Feature**: ${feat.title}');
    sb.writeln('- **Status**: ${cpNode?.unifiedStatusLabel ?? 'Queued'}');
    final resolvedGoal = SectionTextUtils.resolveGoal(feat.sections).trim();
    if (resolvedGoal.isNotEmpty) {
      sb.writeln('- **Goal**: $resolvedGoal');
    }
    final scopeItems = (cpNode != null && cpNode.coveredScope.isNotEmpty)
        ? cpNode.coveredScope
        : SectionTextUtils.resolveInScope(feat.sections);
    if (scopeItems.isNotEmpty) {
      sb.writeln('- **In Scope**:');
      for (final item in scopeItems) {
        final clean = item.trim();
        if (clean.isNotEmpty) {
          sb.writeln('  - $clean');
        }
      }
    }
    final cleanDone = SectionTextUtils.resolveCheckpointDoneWhen(
      playtestGoalParam: cpNode?.parameters['playtestGoal'],
      checkpointTrigger: cpNode?.trigger,
      checkpointFeedback: cpNode?.feedback,
      sections: feat.sections,
      fallback: cpNode?.playtestCondition ?? '',
    );
    if (cleanDone.isNotEmpty) {
      sb.writeln('- **Playtest Gate (Done When)**: $cleanDone');
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
    final activeTuning = (cpNode != null && cpNode.tuningParams.isNotEmpty)
        ? cpNode.tuningParams
        : SectionTextUtils.resolveTuningParams(feat.sections);
    if (activeTuning.isEmpty) {
      sb.writeln('- *(No numeric tuning variables registered)*');
    } else {
      sb.writeln('### Active Feature Variables (`${feat.title}`)');
      for (final param in activeTuning) {
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

    sb.writeln('\n## 3. Playtest & Edge-Case Guards');
    if (cpNode == null || cpNode.edgeCases.isEmpty) {
      sb.writeln('- *(No edge-case guards registered)*');
    } else {
      for (int gIdx = 0; gIdx < cpNode.edgeCases.length; gIdx++) {
        final g = cpNode.edgeCases[gIdx].trim();
        if (g.isEmpty) continue;
        final checked = cpNode.isGuardSignedOff(gIdx, g) ? 'x' : ' ';
        sb.writeln('- [$checked] `$g`');
      }
    }

    if (cpNode != null) {
      final openFixes = cpNode.openFixItems;
      sb.writeln('\n## 4. Open Playtest Issues ([FIX])');
      if (openFixes.isEmpty) {
        sb.writeln('- *(No open playtest issues)*');
      } else {
        for (final fix in openFixes) {
          sb.writeln('- [ ] ${fix.text.trim()}');
        }
      }
    }

    return sb.toString();
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
      if (_enrichingFeatureIds.contains(featureId)) {
        return;
      }
      if (feat.sections.remove('needs_ai_enrichment') == 'true') {
        final parentBeatTitle = (feat.parentId != null
                ? documents[feat.parentId!]?.title
                : null) ??
            'Core Loop Epic';
        _enrichLiveFeatureWithAi(featureId, parentBeatTitle);
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
      } else {
        feat.sections.remove('tuning');
        feat.sections.remove('variables');
      }
      if (activeCp.edgeCases.isNotEmpty) {
        feat.sections['edge_cases'] =
            activeCp.edgeCases.map((e) => '• $e').join('\n');
      } else {
        feat.sections.remove('edge_cases');
      }
      final bp = _releaseBlueprint;
      if (bp != null) {
        final resolvedDone = SectionTextUtils.resolveCheckpointDoneWhen(
          playtestGoalParam: activeCp.parameters['playtestGoal'],
          checkpointTrigger: activeCp.trigger,
          checkpointFeedback: activeCp.feedback,
          sections: feat.sections,
        );
        for (final b in bp.beats) {
          for (final f in b.features) {
            if (f.id == featureId ||
                (f.title.toLowerCase().trim() ==
                        feat.title.toLowerCase().trim() &&
                    b.id == feat.parentId)) {
              f.tuningParams = List<String>.from(activeCp.tuningParams);
              f.edgeCases = List<String>.from(activeCp.edgeCases);
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
                  playtestCriteria: resolvedDone.isNotEmpty
                      ? resolvedDone
                      : oldCp.playtestCriteria,
                  tasks: activeCp.checklist.isNotEmpty
                      ? [for (final t in activeCp.checklist) t.text]
                      : oldCp.tasks,
                  coveredScope: List<String>.from(activeCp.coveredScope),
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

  static final RegExp _guardPrefixStripRegex = RegExp(
    r'^[•\*\-\s]*(?:\[(?:STATE|PLAYTEST)?\s*GUARD\]\s*)?',
    caseSensitive: false,
  );
  static final RegExp _stateGuardTagRegex = RegExp(
    r'^\s*\[STATE\s+GUARD\]',
    caseSensitive: false,
  );
  static final RegExp _goalPrefixStripRegex = RegExp(
    r'^Goal\s*:\s*',
    caseSensitive: false,
  );
  static final RegExp _scopeBulletStripRegex = RegExp(r'^[•\*\-\s]+');
  static final RegExp _donePrefixStripRegex = RegExp(
    r'^(?:Done\s*(?:When|If)|Playtest(?:\s+Gate)?|End\s+Goal)\s*:\s*',
    caseSensitive: false,
  );
  static final RegExp _arrowNormalizeRegex = RegExp(r'\s*->\s*');

  void _rebuildSignedOffGuardsByExactKeys(
    FeatureStateNode activeNode,
    Set<int> signedOffIndices,
  ) {
    final next = <String>[];
    for (int i = 0; i < activeNode.edgeCases.length; i++) {
      if (!signedOffIndices.contains(i)) continue;
      final txt = activeNode.edgeCases[i].trim();
      if (txt.isNotEmpty) {
        next.add(txt);
      }
    }
    if (next.isEmpty) {
      activeNode.parameters.remove('signedOffGuards');
    } else {
      activeNode.parameters['signedOffGuards'] = jsonEncode(next);
    }
  }

  /// Updates the active Feature's `Goal`, `In Scope`, and `Done When` across
  /// `FeatureStateNode`, `feat.sections`, and `_releaseBlueprint` so Web Studio
  /// and Godot Cloud Sync remain 1:1 aligned.
  void updateActiveFeatureSpec({
    required String featureId,
    required List<FeatureStateNode> states,
    required FeatureStateNode activeNode,
    String? goal,
    List<String>? inScope,
    String? doneWhen,
  }) {
    final feat = documents[featureId];
    if (feat == null) return;

    final nextGoal = goal != null
        ? goal.replaceFirst(_goalPrefixStripRegex, '').trim()
        : SectionTextUtils.resolveGoal(feat.sections).trim();

    final rawScope = inScope ??
        (activeNode.coveredScope.isNotEmpty
            ? List<String>.from(activeNode.coveredScope)
            : SectionTextUtils.resolveInScope(feat.sections));
    final nextScope = [
      for (final s in rawScope)
        if (s.replaceFirst(_scopeBulletStripRegex, '').trim().isNotEmpty)
          s.replaceFirst(_scopeBulletStripRegex, '').trim(),
    ];

    final nextDone = doneWhen != null
        ? doneWhen
            .replaceFirst(_donePrefixStripRegex, '')
            .replaceAll(_arrowNormalizeRegex, ' → ')
            .trim()
        : SectionTextUtils.resolveCheckpointDoneWhen(
            playtestGoalParam: activeNode.parameters['playtestGoal'],
            checkpointTrigger: activeNode.trigger,
            checkpointFeedback: activeNode.feedback,
            sections: feat.sections,
          );

    final existingExcl = SectionTextUtils.resolveExclusions(
      feat.sections,
      splitSingleSentence: false,
    );

    if (nextGoal.isNotEmpty) {
      feat.sections['goal'] = nextGoal;
    }

    if (nextScope.isNotEmpty) {
      feat.sections['in_scope'] = nextScope.map((s) => '• $s').join('\n');
    } else {
      feat.sections.remove('in_scope');
      feat.sections.remove('inScope');
    }
    activeNode.coveredScope = List<String>.from(nextScope);

    if ((doneWhen != null || nextDone.isNotEmpty) && nextDone.isNotEmpty) {
      feat.sections['done_when'] = nextDone;
      feat.sections['doneWhen'] = nextDone;
      feat.sections['playtest_criteria'] = nextDone;
      activeNode.parameters['playtestGoal'] = nextDone;
      activeNode.trigger = 'Playtest: $nextDone';
      if (activeNode.feedback != null) {
        activeNode.feedback = nextDone;
      }
    }

    final composedScope = SectionTextUtils.composeStructuredScopeBlock(
      goal: nextGoal,
      inScope: nextScope,
      exclusions: existingExcl,
      doneWhen: nextDone,
    );
    if (composedScope.isNotEmpty) {
      feat.sections['scope'] = composedScope;
    }

    final bp = _releaseBlueprint;
    if (bp != null) {
      for (final b in bp.beats) {
        for (final f in b.features) {
          if (f.id == featureId ||
              (f.title.toLowerCase().trim() ==
                      feat.title.toLowerCase().trim() &&
                  b.id == feat.parentId)) {
            if (nextGoal.isNotEmpty) f.goal = nextGoal;
            f.inScope = List<String>.from(nextScope);
            if (nextDone.isNotEmpty) f.doneWhen = nextDone;
            break;
          }
        }
      }
    }

    updateFeatureStates(featureId, states);
  }

  /// Appends a `[PLAYTEST GUARD]` to the active checkpoint and syncs it 1:1.
  void addPlaytestGuard({
    required String featureId,
    required List<FeatureStateNode> states,
    required FeatureStateNode activeNode,
    required String rawText,
  }) {
    final clean = rawText.replaceFirst(_guardPrefixStripRegex, '').trim();
    if (clean.isEmpty) return;

    final checkedIndices = <int>{
      for (int i = 0; i < activeNode.edgeCases.length; i++)
        if (activeNode.isGuardSignedOff(i, activeNode.edgeCases[i])) i,
    };
    activeNode.edgeCases = [
      ...activeNode.edgeCases,
      '[PLAYTEST GUARD] $clean',
    ];
    _rebuildSignedOffGuardsByExactKeys(activeNode, checkedIndices);
    updateFeatureStates(featureId, states);
  }

  /// Edits a guard in place, resetting ONLY that guard to unchecked if its
  /// condition text changed while preserving all other checked guards.
  void editPlaytestGuard({
    required String featureId,
    required List<FeatureStateNode> states,
    required FeatureStateNode activeNode,
    required int guardIndex,
    required String rawText,
  }) {
    if (guardIndex < 0 || guardIndex >= activeNode.edgeCases.length) return;
    final oldRaw = activeNode.edgeCases[guardIndex];
    final oldClean = oldRaw.replaceFirst(_guardPrefixStripRegex, '').trim();
    final newClean = rawText.replaceFirst(_guardPrefixStripRegex, '').trim();
    if (newClean.isEmpty) return;

    final checkedIndices = <int>{
      for (int i = 0; i < activeNode.edgeCases.length; i++)
        if (activeNode.isGuardSignedOff(i, activeNode.edgeCases[i])) i,
    };
    final prefix = _stateGuardTagRegex.hasMatch(oldRaw)
        ? '[STATE GUARD]'
        : '[PLAYTEST GUARD]';
    final nextGuards = List<String>.from(activeNode.edgeCases);
    nextGuards[guardIndex] = '$prefix $newClean';
    activeNode.edgeCases = nextGuards;

    if (oldClean != newClean) {
      checkedIndices.remove(guardIndex);
    }
    _rebuildSignedOffGuardsByExactKeys(activeNode, checkedIndices);
    updateFeatureStates(featureId, states);
  }

  /// Removes a guard at [guardIndex] and rebuilds `signedOffGuards` without
  /// positional `#index` drift.
  void deletePlaytestGuard({
    required String featureId,
    required List<FeatureStateNode> states,
    required FeatureStateNode activeNode,
    required int guardIndex,
  }) {
    if (guardIndex < 0 || guardIndex >= activeNode.edgeCases.length) return;
    final nextGuards = <String>[];
    final survivingChecked = <int>{};
    for (int i = 0; i < activeNode.edgeCases.length; i++) {
      if (i == guardIndex) continue;
      if (activeNode.isGuardSignedOff(i, activeNode.edgeCases[i])) {
        survivingChecked.add(nextGuards.length);
      }
      nextGuards.add(activeNode.edgeCases[i]);
    }
    activeNode.edgeCases = nextGuards;
    _rebuildSignedOffGuardsByExactKeys(activeNode, survivingChecked);
    updateFeatureStates(featureId, states);
  }
}
