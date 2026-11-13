part of 'workbench_provider.dart';

extension WorkbenchInboxMixin on WorkbenchProvider {
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
      tasks: ReleasePlannerAgent.defaultDockStepTitles(
        subject: immediateTitle,
      ),
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
      futureTasks: ReleasePlannerAgent.defaultDockStepTitles(
        subject: futureTitle,
        isFuturePhase: true,
      ),
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
3. HOW (Implementation Architecture): Plain 2-4 word functional title, Goal/In Scope/Done When, 3 Engine Architecture bullets ($engineLabel matching the project's 2D/3D spec), Playtest Gate, Dock-Aligned Build Steps (editor_setup -> inspector_setup -> script_logic -> wire_and_verify), Tuning Params, and [STATE GUARD] rules.

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
      functionDeclarations: const [WorkbenchReleaseMixin.commitInboxFeatureTriageTool],
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
          : ReleasePlannerAgent.defaultDockStepTitles(subject: cpTitle);
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
        coveredScope: item.inScope.isNotEmpty ? item.inScope : [cpTitle],
        tuningParams: item.tuningParams,
        edgeCases: item.edgeCases,
        parameters: {
          'releaseVersion': activeVer,
          if (tasks.isNotEmpty) 'plannedSlices': tasks.join(' | '),
          if (resolvedPrimaryAsset.isNotEmpty)
            'primarySharedScriptOrScene': resolvedPrimaryAsset,
        },
      );
      TaskHowToBlueprint.populateDefaultUnifiedSteps(
        newCp,
        engineHint: _activeEngineHint,
        phase: _currentPhase,
      );
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
        : ReleasePlannerAgent.defaultDockStepTitles(subject: item.featureTitle);
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
      coveredScope: item.inScope.isNotEmpty ? item.inScope : [item.featureTitle],
      tuningParams: item.tuningParams,
      edgeCases: item.edgeCases,
      parameters: {
        'releaseVersion': activeVer,
        if (tasks.isNotEmpty) 'plannedSlices': tasks.join(' | '),
        if (inboxPrimaryAsset.isNotEmpty)
          'primarySharedScriptOrScene': inboxPrimaryAsset,
      },
    );
    TaskHowToBlueprint.populateDefaultUnifiedSteps(
      cpNode,
      engineHint: _activeEngineHint,
      phase: _currentPhase,
    );
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
              : ReleasePlannerAgent.defaultDockStepTitles(
                  subject: cpTitle,
                  isFuturePhase: true,
                ));

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
