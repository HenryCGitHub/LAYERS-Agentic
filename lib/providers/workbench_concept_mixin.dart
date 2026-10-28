part of 'workbench_provider.dart';

/// Stage 1 Spark Idea Intake, GDD Extraction, and 10-Step Concept Blueprint orchestration
/// for [WorkbenchProvider].
extension WorkbenchConceptMixin on WorkbenchProvider {
  /// Ingests a raw game idea (or refines the existing ingested summary) on the New Project screen
  /// and populates the 3 Concept Expansion / Twist Cards below the input field.
  Future<void> ingestOrRefineSparkIdea(String userInput) async {
    final clean = userInput.trim();
    if (clean.isEmpty && _sparkIntake == null) return;
    if (_sparkIntake != null) {
      _sparkSuggestionVariantOffset++;
    }

    _isAgentBusy = true;
    _agentProgressStep =
        'Ingesting & summarizing idea ($_conversationModel · ${_thinkingLevel.toLowerCase()})...';
    notifyListeners();

    try {
      final result = await ProjectConceptAgent.ingestOrRefineSparkIdea(
        userInput: clean,
        existingIntake: _sparkIntake,
        suggestionVariantOffset: _sparkSuggestionVariantOffset,
        apiKey: _apiKey,
        modelName: _conversationModel,
        thinkingLevel: _thinkingLevel,
      );
      if (result != null) {
        _sparkIntake = result;
        _offlineErrorMessage = null;
      } else {
        _setOfflineState();
      }
    } finally {
      _isAgentBusy = false;
      _agentProgressStep = null;
      notifyListeners();
    }
  }

  /// Toggles one of the 3 Concept Expansion / Twist Cards on the New Project screen on or off,
  /// folding that mechanic into (or removing it from) the Agent's Idea Summary without auto-launching Stage 1B.
  void toggleSparkExpansionCard(int cardIndex) {
    final intake = _sparkIntake;
    if (intake == null) return;
    final cards = intake.expansionCards;
    if (cardIndex < 0 || cardIndex >= cards.length) return;
    cards[cardIndex].isSelected = !cards[cardIndex].isSelected;
    notifyListeners();
  }

  /// Cycles ONLY the 3 Concept Expansion / Twist Cards on the New Project screen to fresh suggestions,
  /// never overwriting `workingTitle`, `baseSummary`, or `mechanics`.
  Future<void> shuffleSparkExpansionCards() async {
    final currentIntake = _sparkIntake;
    if (currentIntake == null) return;
    _sparkSuggestionVariantOffset++;

    _isAgentBusy = true;
    _agentProgressStep =
        'Refreshing suggestions for ${currentIntake.workingTitle} ($_conversationModel · ${_thinkingLevel.toLowerCase()})...';
    notifyListeners();

    try {
      final freshCards = await ProjectConceptAgent.refreshSparkExpansionCards(
        existingIntake: currentIntake,
        suggestionVariantOffset: _sparkSuggestionVariantOffset,
        apiKey: _apiKey,
        modelName: _conversationModel,
        thinkingLevel: _thinkingLevel,
      );
      if (freshCards != null && freshCards.isNotEmpty) {
        if (_sparkIntake == currentIntake) {
          currentIntake.expansionCards = freshCards;
        }
        _offlineErrorMessage = null;
      } else {
        _setOfflineState();
      }
    } finally {
      _isAgentBusy = false;
      _agentProgressStep = null;
      notifyListeners();
    }
  }

  /// Clears the current pre-project Idea Summary so the user can start fresh.
  void clearSparkIdeaIntake() {
    _sparkIntake = null;
    notifyListeners();
  }

  /// Imports an unstructured GDD, Notion note, or README document on Stage 1A,
  /// extracts all 8 Concept sections, and jumps straight to `Step 09 · Full Concept Review`.
  Future<void> importExistingGddAndJumpToReview(String rawGdd) async {
    final clean = rawGdd.trim();
    if (clean.isEmpty) return;

    _isAgentBusy = true;
    _agentProgressStep =
        'Extracting 8-section Concept Blueprint from GDD ($_conversationModel · ${_thinkingLevel.toLowerCase()})...';
    notifyListeners();

    try {
      final extracted = await ProjectConceptAgent.extractConceptFromGdd(
        clean,
        apiKey: _apiKey,
        modelName: _conversationModel,
        thinkingLevel: _thinkingLevel,
      );
      if (extracted != null) {
        _conceptDraft = extracted;
        _offlineErrorMessage = null;
        _commitConceptToVault(_conceptDraft!);
        _jumpToFullReviewPending = true;
      } else {
        _setOfflineState();
      }
    } finally {
      _isAgentBusy = false;
      _agentProgressStep = null;
      notifyListeners();
    }
  }

  /// Regenerates the 3 Option Playing Cards for a specific Stage 1 section (`01`..`08`).
  Future<void> regenerateStage1SectionOptions(String optionKey) async {
    final draft = _conceptDraft;
    if (draft == null) return;
    final title = draft.title;
    final previousOptions = List<String>.from(
      draft.sectionOptions[optionKey] ?? const <String>[],
    );

    _isAgentBusy = true;
    _agentProgressStep =
        'Refreshing $optionKey options for $title ($_conversationModel · ${_thinkingLevel.toLowerCase()})...';
    notifyListeners();
    try {
      final aiOptions =
          await ProjectConceptAgent.regenerateSectionOptionsWithAi(
        draft: draft,
        optionKey: optionKey,
        currentOptions: previousOptions,
        apiKey: _apiKey,
        modelName: _conversationModel,
        thinkingLevel: _thinkingLevel,
      );
      if (aiOptions != null && aiOptions.isNotEmpty && _conceptDraft == draft) {
        draft.sectionOptions[optionKey] = aiOptions;
        _offlineErrorMessage = null;
        _commitConceptToVault(draft);
      } else {
        _setOfflineState();
      }
    } finally {
      _isAgentBusy = false;
      _agentProgressStep = null;
      notifyListeners();
    }
  }

  /// Resets the current Concept Blueprint draft so the user returns to Step 1A (`The Spark` Playing Cards).
  void resetConceptToSpark() {
    createNewProject();
  }

  /// Step 1A -> 1B: User accepts their summarized idea (or submits a direct idea) and starts the 8-section Concept Blueprint.
  /// When [jumpToFullReview] is true (default), lands directly on the Single-Page Complete Concept Blueprint.
  Future<void> startConceptInterview([
    String sparkText = '',
    bool jumpToFullReview = true,
  ]) async {
    final cleanText = sparkText.trim();
    final effectiveSpark = cleanText.isNotEmpty
        ? cleanText
        : (_sparkIntake?.canonicalPrompt ?? '');
    if (effectiveSpark.isEmpty) return;

    _isAgentBusy = true;
    _agentProgressStep =
        'Drafting initial Concept Blueprint ($_conversationModel · ${_thinkingLevel.toLowerCase()})...';
    notifyListeners();

    try {
      final draft = await ProjectConceptAgent.startConceptInterview(
        effectiveSpark,
        apiKey: _apiKey,
        modelName: _conversationModel,
        thinkingLevel: _thinkingLevel,
      );
      if (draft != null) {
        _conceptDraft = draft;
        _offlineErrorMessage = null;
        if (jumpToFullReview) {
          _jumpToFullReviewPending = true;
        }
        _commitConceptToVault(_conceptDraft!);
      } else {
        _setOfflineState();
      }
    } finally {
      _isAgentBusy = false;
      _agentProgressStep = null;
      notifyListeners();
    }
  }

  /// 1-Click Express Build from Spark: Synthesizes the 8-section Concept Blueprint
  /// (if not yet drafted) and immediately builds the v0.1 Release Workbench in a single pass.
  Future<void> expressBuildReleaseFromSpark([String sparkText = '']) async {
    if (_conceptDraft == null || sparkText.trim().isNotEmpty) {
      await startConceptInterview(sparkText, true);
    }
    if (_conceptDraft != null) {
      await approveConceptAndBuildRelease();
    }
  }

  /// Sends a user turn in the Stage 1 Co-Design Chat and updates the live Project Concept Blueprint
  /// using the fast `_conversationModel` (`gemini-flash-latest`).
  Future<void> sendConceptChatMessage(String message) async {
    final clean = message.trim();
    if (clean.isEmpty) return;

    // If no concept exists yet, treat the first message as the opening Spark!
    if (_conceptDraft == null) {
      await startConceptInterview(clean);
      return;
    }

    _isAgentBusy = true;
    _agentProgressStep =
        'Updating Concept Blueprint ($_conversationModel · ${_thinkingLevel.toLowerCase()})...';
    notifyListeners();

    try {
      final ok = await ProjectConceptAgent.sendConceptChatTurn(
        _conceptDraft!,
        clean,
        apiKey: _apiKey,
        conversationModel: _conversationModel,
        planningModel: _planningModel,
        thinkingLevel: _thinkingLevel,
      );
      if (ok) {
        _offlineErrorMessage = null;
        _commitConceptToVault(_conceptDraft!);
      } else {
        _setOfflineState();
      }
    } finally {
      _isAgentBusy = false;
      _agentProgressStep = null;
      notifyListeners();
    }
  }

  /// Allows direct inline adjustments to the ProjectConceptBlueprint if needed.
  void updateConceptDraft(void Function(ProjectConceptBlueprint draft) mutator) {
    final draft = _conceptDraft;
    if (draft == null) return;
    mutator(draft);
    _commitConceptToVault(draft);
    notifyListeners();
  }

  void _commitConceptToVault(
    ProjectConceptBlueprint draft, {
    bool syncBuiltWorkbench = true,
  }) {
    final projId = _activeProjectId ?? 'proj_main';
    final existingProj = documents[projId];
    final projDoc = existingProj ??
        TierDocument(
          id: projId,
          title: draft.title,
          tier: TierType.project,
        );
    projDoc.title = draft.title;
    projDoc.sections['scope'] = draft.toFormattedScopeSection();
    projDoc.sections['game_spec'] = draft.gameSpec.join(' · ');
    projDoc.sections['tech_spec'] = draft.techSpec.join(' · ');
    projDoc.sections['design_pillars'] =
        draft.designPillars.map((p) => '• $p').join('\n');
    projDoc.sections['trade_offs'] =
        draft.tradeOffs.map((t) => '• $t').join('\n');

    final releaseIds = <String>[];
    final trainTitles = draft.releaseTrainTitles.isNotEmpty
        ? draft.releaseTrainTitles
        : <String>[
            'v0.1: ${draft.title.trim().isEmpty ? "Game" : draft.title.trim()} Core Loop - Prototype',
          ];
    final isSplitPrototype = trainTitles.length > 1;
    final relId = projId == 'proj_main' ? 'rel_v0_1' : '${projId}_rel_v0_1';
    final relTitle = trainTitles.first;
    final existingRel = documents[relId];

    if (existingRel != null) {
      existingRel.title = relTitle;
      existingRel.sections['phase'] ??= ProductionPhase.prototype.name;
      if (isSplitPrototype) {
        existingRel.sections['prototypePart'] = '1';
        existingRel.sections['splitPrototypePart2Title'] = trainTitles[1];
      } else {
        existingRel.sections.remove('prototypePart');
        existingRel.sections.remove('splitPrototypePart2Title');
      }
      if (existingRel.childrenIds.isEmpty) {
        existingRel.sections['releaseScope'] = ReleaseScope.prototype.name;
        existingRel.sections['scope'] =
            'Goal: ${draft.goal}\n\nIn Scope:\n${draft.coreLoopBeats.map((b) => '• $b').join('\n')}\n\nOut of Scope:\n${draft.exclusions.map((e) => '• $e').join('\n')}\n\nDone When: ${draft.doneWhen}';
      }
      _persistDocument(existingRel);
      releaseIds.add(relId);
    } else {
      final relDoc = TierDocument(
        id: relId,
        title: relTitle,
        tier: TierType.release,
        parentId: projId,
        sections: {
          'releaseScope': ReleaseScope.prototype.name,
          'phase': ProductionPhase.prototype.name,
          if (isSplitPrototype) 'prototypePart': '1',
          if (isSplitPrototype) 'splitPrototypePart2Title': trainTitles[1],
          'scope':
              'Goal: ${draft.goal}\n\nIn Scope:\n${draft.coreLoopBeats.map((b) => '• $b').join('\n')}\n\nOut of Scope:\n${draft.exclusions.map((e) => '• $e').join('\n')}\n\nDone When: ${draft.doneWhen}',
        },
      );
      documents[relId] = relDoc;
      _persistDocument(relDoc);
      releaseIds.add(relDoc.id);
    }

    // Preserve only already-built subsequent releases (never pre-queue unbuilt future releases)
    // so revisiting Stage 1 mid-project keeps built releases intact without queuing unbuilt ones.
    if (existingProj != null) {
      for (final existingRelId in existingProj.childrenIds) {
        if (releaseIds.contains(existingRelId)) continue;
        final existingRelDoc = documents[existingRelId];
        if (existingRelDoc == null) continue;
        if (existingRelDoc.childrenIds.isNotEmpty ||
            existingRelId == _activeReleaseId) {
          releaseIds.add(existingRelId);
        }
      }
    }

    projDoc.childrenIds = releaseIds;
    documents[projId] = projDoc;
    _activeProjectId = projId;
    _activeReleaseId ??= releaseIds.isNotEmpty ? releaseIds.first : null;
    repackProjectReleasesSequentially(
      projDoc,
      keepReleaseId: _activeReleaseId,
    );
    if (syncBuiltWorkbench) {
      syncConceptChangesToBuiltWorkbench(draft);
    }
    _syncActiveProjectMetadata();
  }

  static final RegExp _beatTokenRegex = RegExp(r'[a-z0-9]+');
  static const Set<String> _beatStopWords = <String>{
    'the',
    'and',
    'for',
    'with',
    'into',
    'from',
    'that',
    'this',
    'EPIC',
    'epic',
    'beat',
    'loop',
    'player',
    'game',
  };

  Set<String> _extractBeatKeywords(String text) {
    final lower = text.toLowerCase();
    final tokens = <String>{};
    for (final m in _beatTokenRegex.allMatches(lower)) {
      final w = m.group(0)!;
      if (w.length >= 3 && !_beatStopWords.contains(w)) {
        tokens.add(w);
      }
    }
    return tokens;
  }

  double _beatKeywordOverlap(String a, String b) {
    final setA = _extractBeatKeywords(a);
    final setB = _extractBeatKeywords(b);
    if (setA.isEmpty || setB.isEmpty) return 0.0;
    final intersection = setA.intersection(setB).length;
    final minLen = setA.length < setB.length ? setA.length : setB.length;
    return intersection / minLen;
  }

  ({String title, String description}) _parseStage1CoreLoopBeat(
    String rawBeat,
    int index,
  ) {
    final trimmed = rawBeat.trim();
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
      return (
        title: t.isNotEmpty ? t : 'Core Loop Beat ${index + 1}',
        description: d.isNotEmpty ? d : trimmed,
      );
    }
    return (
      title: trimmed.isNotEmpty ? trimmed : 'Core Loop Beat ${index + 1}',
      description: trimmed,
    );
  }

  /// Non-destructively syncs Stage 1 edits (`06 Core Loop`, `07 Out of Scope`, `01 Goal`, `08 Done When`)
  /// into an already-built Stage 2 Release (`activeRelease.childrenIds.isNotEmpty`) without wiping
  /// existing `v0.1+` Feature checkpoints or completed subtask progress.
  void syncConceptChangesToBuiltWorkbench(ProjectConceptBlueprint draft) {
    final rel = activeRelease;
    if (rel == null || rel.childrenIds.isEmpty) return;

    // 1. Sync Release Scope (`01 Goal`, `06 Core Loop`, `07 Out of Scope`, `08 Done When`)
    rel.sections['scope'] =
        'Goal: ${draft.goal}\n\nIn Scope:\n${draft.coreLoopBeats.map((b) => '• $b').join('\n')}\n\nOut of Scope:\n${draft.exclusions.map((e) => '• $e').join('\n')}\n\nDone When: ${draft.doneWhen}';
    _persistDocument(rel);

    final bp = _releaseBlueprint;
    if (bp != null) {
      if (draft.goal.trim().isNotEmpty) {
        bp.goal = draft.goal.trim();
      }
      if (draft.doneWhen.trim().isNotEmpty) {
        bp.doneWhen = draft.doneWhen.trim();
      }
      bp.explicitExclusions = List<String>.from(draft.exclusions);
    }

    if (draft.coreLoopBeats.isEmpty) return;

    final existingBeats = <TierDocument>[
      for (final bid in rel.childrenIds)
        if (documents[bid] != null) documents[bid]!,
    ];
    if (existingBeats.isEmpty) return;

    final parsedStage1Beats = [
      for (int i = 0; i < draft.coreLoopBeats.length; i++)
        _parseStage1CoreLoopBeat(draft.coreLoopBeats[i], i),
    ];

    final matchedBeatForStage1Idx = <int, TierDocument>{};
    final claimedBeatIds = <String>{};

    // Pass 1: Global Exact & High-Similarity Match (`>= 0.45` keyword overlap) across all positions
    // so shifted beats (e.g., when a middle beat is deleted) claim their true Epic first.
    for (int i = 0; i < parsedStage1Beats.length; i++) {
      final sBeat = parsedStage1Beats[i];
      final normTitle = sBeat.title.toLowerCase().trim();
      TierDocument? bestMatch;
      double bestScore = 0.0;

      for (final candidate in existingBeats) {
        if (claimedBeatIds.contains(candidate.id)) continue;
        final candNorm = candidate.title.toLowerCase().trim();
        if (candNorm == normTitle ||
            (candNorm.length >= 4 &&
                normTitle.length >= 4 &&
                (candNorm.contains(normTitle) || normTitle.contains(candNorm)))) {
          bestMatch = candidate;
          bestScore = 1.0;
          break;
        }
        final overlap = _beatKeywordOverlap(
          '${sBeat.title} ${sBeat.description}',
          '${candidate.title} ${candidate.sections['scope'] ?? ''}',
        );
        if (overlap >= 0.45 && overlap > bestScore) {
          bestScore = overlap;
          bestMatch = candidate;
        }
      }

      if (bestMatch != null) {
        matchedBeatForStage1Idx[i] = bestMatch;
        claimedBeatIds.add(bestMatch.id);
      }
    }

    // Pass 2: Guarded Positional Rename Match (Edge Case 3 protection)
    // Only allow positional fallback (`index == index`) when either:
    // - Total count is unchanged AND only 1 single beat in the list was edited in-place, OR
    // - Keyword overlap between the new beat and the existing beat at `i` is `>= 0.20`.
    final unmatchedStage1Indices = [
      for (int i = 0; i < parsedStage1Beats.length; i++)
        if (!matchedBeatForStage1Idx.containsKey(i)) i,
    ];
    final isSingleInPlaceRename =
        parsedStage1Beats.length == existingBeats.length &&
            unmatchedStage1Indices.length == 1 &&
            (existingBeats.length - claimedBeatIds.length) == 1;

    for (final idx in unmatchedStage1Indices) {
      if (idx < existingBeats.length) {
        final positionalCandidate = existingBeats[idx];
        if (!claimedBeatIds.contains(positionalCandidate.id)) {
          final sBeat = parsedStage1Beats[idx];
          final overlap = _beatKeywordOverlap(
            '${sBeat.title} ${sBeat.description}',
            '${positionalCandidate.title} ${positionalCandidate.sections['scope'] ?? ''}',
          );
          if (isSingleInPlaceRename || overlap >= 0.20) {
            matchedBeatForStage1Idx[idx] = positionalCandidate;
            claimedBeatIds.add(positionalCandidate.id);
          }
        }
      }
    }

    // Pass 3: Reconstruct `rel.childrenIds` in Stage 1 order, updating matched Epics in-place,
    // creating playable Epics/Features for newly added beats, and archiving removed Epics.
    final activeVer = activeReleaseVersionTag;
    final newReleaseBeatIds = <String>[];
    final newBlueprintBeats = <ProposedBeatBlueprint>[];

    for (int i = 0; i < parsedStage1Beats.length; i++) {
      final sBeat = parsedStage1Beats[i];
      final existingBeat = matchedBeatForStage1Idx[i];

      if (existingBeat != null) {
        final oldTitle = existingBeat.title;
        existingBeat.title = sBeat.title;
        existingBeat.sections['scope'] =
            'Goal: Build and playtest ${sBeat.description}\n\nIn Scope:\n• ${sBeat.title}: ${sBeat.description}\n\nDone When: Playtester can trigger and complete ${sBeat.title} in the test scene.';
        _persistDocument(existingBeat);
        newReleaseBeatIds.add(existingBeat.id);

        if (bp != null) {
          final matchingBpBeat = bp.beats
              .where(
                (b) =>
                    b.id == existingBeat.id ||
                    b.title.toLowerCase().trim() ==
                        oldTitle.toLowerCase().trim(),
              )
              .firstOrNull;
          if (matchingBpBeat != null) {
            matchingBpBeat.title = sBeat.title;
            matchingBpBeat.goal = sBeat.description;
            newBlueprintBeats.add(matchingBpBeat);
          }
        }
      } else {
        // Brand-new Core Loop Beat added in Stage 1 — create Epic + starter Playable Feature
        final newBeatId =
            'beat_${rel.id}_sync_${i + 1}_${DateTime.now().millisecondsSinceEpoch % 10000}';
        final featTitle = MechanicArchetypeProfile.concreteFeatureTitleForBeat(
          sBeat.title,
          beatTitle: sBeat.title,
          beatGoal: sBeat.description,
          beatIndex: i,
        );
        final newFeatId = 'feat_${newBeatId}_1';
        final playtestGate =
            'Trigger $featTitle in the test scene -> ${sBeat.description} completes cleanly';
        final starterTasks = <String>[
          'Create actor/node structure and base properties for $featTitle (2h)',
          'Implement core state transitions and player input for $featTitle (1h)',
          'Hook visual/audio feedback cues and state guard for $featTitle (1h)',
        ];
        final starterTuning = <String>[
          'responseTime: 0.12 s',
          'cooldownDuration: 0.50 s',
        ];
        final starterGuards = <String>[
          '[STATE GUARD] Block duplicate $featTitle activation while active',
        ];
        final cpNode = FeatureStateNode(
          id: '${newFeatId}_${activeVer}_cp_1',
          name: 'Checkpoint 1: $featTitle',
          trigger: 'Playtest: $playtestGate',
          order: 0,
          checklist: [
            for (int tIdx = 0; tIdx < starterTasks.length; tIdx++)
              Subtask(
                id: '${newFeatId}_t_${tIdx + 1}',
                text: starterTasks[tIdx],
                completed: false,
              ),
          ],
          coveredScope: [featTitle],
          tuningParams: starterTuning,
          edgeCases: starterGuards,
          parameters: {'releaseVersion': activeVer},
        );
        final newFeatDoc = TierDocument(
          id: newFeatId,
          title: featTitle,
          tier: TierType.feature,
          parentId: newBeatId,
          estimatedDuration: '4h',
          sections: {
            'originVersion': activeVer,
            'activeReleaseVersion': activeVer,
            'lifecycle': FeatureLifecycleStatus.newFeature.name,
            'scope':
                'Goal: Build ${sBeat.description}\n\nIn Scope:\n• $featTitle\n\nDone When: $playtestGate',
            'tuning': starterTuning.map((p) => '• $p').join('\n'),
            'variables': starterTuning.map((p) => '• $p').join('\n'),
            'edge_cases': starterGuards.map((e) => '• $e').join('\n'),
          },
        );
        FeatureStateNode.saveStatesToDocument(newFeatDoc, [cpNode]);
        documents[newFeatId] = newFeatDoc;
        _persistDocument(newFeatDoc);

        final newBeatDoc = TierDocument(
          id: newBeatId,
          title: sBeat.title,
          tier: TierType.epic,
          parentId: rel.id,
          estimatedDuration: '4h',
          childrenIds: [newFeatId],
          sections: {
            'scope':
                'Goal: Build and playtest ${sBeat.description}\n\nIn Scope:\n• $featTitle\n\nDone When: $playtestGate',
          },
        );
        documents[newBeatId] = newBeatDoc;
        _persistDocument(newBeatDoc);
        newReleaseBeatIds.add(newBeatId);

        if (bp != null) {
          newBlueprintBeats.add(
            ProposedBeatBlueprint(
              id: newBeatId,
              title: sBeat.title,
              goal: sBeat.description,
              doneWhen: playtestGate,
              features: [
                ProposedFeatureBlueprint(
                  id: newFeatId,
                  title: featTitle,
                  goal: 'Build ${sBeat.description}',
                  doneWhen: playtestGate,
                  estimatedHours: 4,
                  included: true,
                  lifecycle: FeatureLifecycleStatus.newFeature,
                  originVersion: activeVer,
                  inScope: [featTitle],
                  outOfScope: const [],
                  tuningParams: starterTuning,
                  edgeCases: starterGuards,
                  checkpoints: [
                    ProposedCheckpointBlueprint(
                      title: featTitle,
                      playtestCriteria: playtestGate,
                      tasks: starterTasks,
                      coveredScope: [featTitle],
                      tuningParams: starterTuning,
                      edgeCases: starterGuards,
                      releaseVersion: activeVer,
                    ),
                  ],
                ),
              ],
            ),
          );
        }
      }
    }

    // Archive any removed Stage 1 Beats (without deleting historical feature progress)
    if (newReleaseBeatIds.isNotEmpty) {
      for (final oldBeat in existingBeats) {
        if (!claimedBeatIds.contains(oldBeat.id)) {
          for (final fid in oldBeat.childrenIds) {
            final fDoc = documents[fid];
            if (fDoc != null) {
              fDoc.sections['lifecycle'] =
                  FeatureLifecycleStatus.superseded.name;
              _persistDocument(fDoc);
            }
          }
        }
      }
      rel.childrenIds = newReleaseBeatIds;
      _persistDocument(rel);
      if (bp != null && newBlueprintBeats.isNotEmpty) {
        bp.beats = newBlueprintBeats;
      }
      if (_selectedBeatId == null ||
          !newReleaseBeatIds.contains(_selectedBeatId)) {
        _selectFirstIncompleteFeatureInActiveRelease();
      }
    }
  }
}
