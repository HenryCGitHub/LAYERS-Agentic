import 'package:flutter/foundation.dart';
import '../agents/gemini_agent_client.dart';
import '../agents/project_concept_agent.dart';
import '../agents/release_planner_agent.dart';
import '../constants/tiers.dart';
import '../models/agent_blueprints.dart';
import '../models/feature_state.dart';
import '../models/tier_document.dart';

/// Top-level stage in the streamlined 3-screen Antigravity workflow.
enum WorkbenchStage {
  /// Stage 1: Spark -> Concept Interview -> Project Concept & Release Train
  projectPitch,

  /// Stage 2: Antigravity Release Plan Gate (Questions + Beat/Feature Keep/Defer Toggles)
  releasePlanGate,

  /// Stage 3: Active Release Workbench (Beats -> Features -> 60/40 Checkpoints)
  releaseWorkbench,
}

/// Central state provider for LAYERS-Agentic.
/// Manages the 4-tier document hierarchy and orchestrates the 3-stage
/// Interview -> Plan Gate -> Execute workflow.
class WorkbenchProvider extends ChangeNotifier {
  final Map<String, TierDocument> documents = {};

  WorkbenchStage _currentStage = WorkbenchStage.projectPitch;
  WorkbenchStage get currentStage => _currentStage;

  bool _isDark = true;
  bool get isDark => _isDark;

  String _apiKey = GeminiAgentClient.resolveDefaultApiKey();
  String get apiKey => _apiKey;
  bool get hasLiveAiKey => GeminiAgentClient.hasKey(_apiKey);

  String _conversationModel = 'gemini-flash-latest';
  String get conversationModel => _conversationModel;

  String _planningModel = 'gemini-4-argon';
  String get planningModel => _planningModel;

  String _thinkingLevel = 'LOW';
  String get thinkingLevel => _thinkingLevel;

  /// Short label displayed in the top bar pill.
  String get modelBadgeLabel {
    final convShort = _conversationModel.replaceAll('gemini-', '');
    final planShort = _planningModel.replaceAll('gemini-', '');
    return '$convShort + $planShort · ${_thinkingLevel.toLowerCase()}';
  }

  static const List<String> availableConversationModels = [
    'gemini-flash-latest',
    'gemini-3.8-flash',
    'gemini-3.5-flash-lite',
  ];

  static const List<String> availablePlanningModels = [
    'gemini-4-argon',
    'gemini-flash-latest',
    'gemini-3.8-flash',
  ];

  static const List<String> availableThinkingLevels = [
    'LOW',
    'MEDIUM',
    'HIGH',
  ];

  void updateAiConfig({
    String? apiKey,
    String? conversationModel,
    String? planningModel,
    String? thinkingLevel,
  }) {
    if (apiKey != null) {
      _apiKey = apiKey.trim();
    }
    if (conversationModel != null && conversationModel.trim().isNotEmpty) {
      _conversationModel = conversationModel.trim();
    }
    if (planningModel != null && planningModel.trim().isNotEmpty) {
      _planningModel = planningModel.trim();
    }
    if (thinkingLevel != null && thinkingLevel.trim().isNotEmpty) {
      _thinkingLevel = thinkingLevel.trim().toUpperCase();
    }
    notifyListeners();
  }

  String? _activeProjectId;
  String? get activeProjectId => _activeProjectId;

  String? _activeReleaseId;
  String? get activeReleaseId => _activeReleaseId;

  String? _selectedBeatId;
  String? get selectedBeatId => _selectedBeatId;

  String? _selectedFeatureId;
  String? get selectedFeatureId => _selectedFeatureId;

  bool _focusMode = true;
  bool get focusMode => _focusMode;

  /// Filter for the compact Release Dropdown in Stage 3:
  /// - 'active': Active Milestone
  /// - 'all': All Live Game Features
  /// - 'archived': Superseded Testbeds Archive
  String _releaseViewFilter = 'active';
  String get releaseViewFilter => _releaseViewFilter;

  void toggleFocusMode() {
    _focusMode = !_focusMode;
    notifyListeners();
  }

  void setReleaseViewFilter(String filter) {
    _releaseViewFilter = filter;
    notifyListeners();
  }

  ProjectConceptBlueprint? _conceptDraft;
  ProjectConceptBlueprint? get conceptDraft => _conceptDraft;

  ReleaseBlueprint? _releaseBlueprint;
  ReleaseBlueprint? get releaseBlueprint => _releaseBlueprint;

  bool _isAgentBusy = false;
  bool get isAgentBusy => _isAgentBusy;

  String? _agentProgressStep;
  String? get agentProgressStep => _agentProgressStep;

  final List<String> _executionLog = [];
  List<String> get executionLog => List.unmodifiable(_executionLog);

  TierDocument? get activeProject =>
      _activeProjectId != null ? documents[_activeProjectId] : null;

  TierDocument? get activeRelease =>
      _activeReleaseId != null ? documents[_activeReleaseId] : null;

  TierDocument? get selectedBeat =>
      _selectedBeatId != null ? documents[_selectedBeatId] : null;

  TierDocument? get selectedFeature =>
      _selectedFeatureId != null ? documents[_selectedFeatureId] : null;

  List<TierDocument> get projectReleases {
    final proj = activeProject;
    if (proj == null) return const [];
    return proj.childrenIds
        .map((id) => documents[id])
        .whereType<TierDocument>()
        .toList();
  }

  List<TierDocument> get activeReleaseBeats {
    final rel = activeRelease;
    if (rel == null) return const [];
    return rel.childrenIds
        .map((id) => documents[id])
        .whereType<TierDocument>()
        .toList();
  }

  List<TierDocument> featuresForBeat(String beatId) {
    final beat = documents[beatId];
    if (beat == null) return const [];
    return beat.childrenIds
        .map((id) => documents[id])
        .whereType<TierDocument>()
        .toList();
  }

  /// All superseded/archived testbed features across the vault.
  List<TierDocument> get supersededFeatures {
    return documents.values
        .where(
          (d) =>
              d.tier == TierType.feature &&
              d.sections['lifecycle'] == FeatureLifecycleStatus.superseded.name,
        )
        .toList();
  }

  /// Next incomplete feature in the active Release after the currently selected feature.
  TierDocument? get nextIncompleteFeature {
    final allFeats = <TierDocument>[];
    for (final b in activeReleaseBeats) {
      allFeats.addAll(featuresForBeat(b.id));
    }
    if (allFeats.isEmpty) return null;
    final currentIdx =
        allFeats.indexWhere((f) => f.id == _selectedFeatureId);
    for (int offset = 1; offset <= allFeats.length; offset++) {
      final candidate = allFeats[(currentIdx + offset) % allFeats.length];
      if (candidate.id != _selectedFeatureId &&
          getDocumentProgress(candidate.id) < 100) {
        return candidate;
      }
    }
    return null;
  }

  void toggleTheme() {
    _isDark = !_isDark;
    notifyListeners();
  }

  void setStage(WorkbenchStage stage) {
    _currentStage = stage;
    notifyListeners();
  }

  /// Resets the current Concept Blueprint draft so the user returns to Step 1A (`The Spark` Playing Cards).
  void resetConceptToSpark() {
    _conceptDraft = null;
    _currentStage = WorkbenchStage.projectPitch;
    notifyListeners();
  }

  /// Step 1A -> 1B: User submits their 1-line Spark idea and starts the turn-by-turn Co-Design Chat.
  Future<void> startConceptInterview(String sparkText) async {
    _isAgentBusy = true;
    _agentProgressStep =
        'Drafting initial Concept Blueprint ($_conversationModel · ${_thinkingLevel.toLowerCase()})...';
    notifyListeners();

    try {
      _conceptDraft = await ProjectConceptAgent.startConceptInterview(
        sparkText,
        apiKey: _apiKey,
        modelName: _conversationModel,
        thinkingLevel: _thinkingLevel,
      );
      if (_conceptDraft != null) {
        _commitConceptToVault(_conceptDraft!);
      }
    } finally {
      _isAgentBusy = false;
      _agentProgressStep = null;
      notifyListeners();
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
      await ProjectConceptAgent.sendConceptChatTurn(
        _conceptDraft!,
        clean,
        apiKey: _apiKey,
        conversationModel: _conversationModel,
        planningModel: _planningModel,
        thinkingLevel: _thinkingLevel,
      );
      _commitConceptToVault(_conceptDraft!);
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

  /// Step 1B -> 1C: User completes the multiple-choice Concept Interview to generate the Project Blueprint.
  Future<void> completeConceptInterview() async {
    final draft = _conceptDraft;
    if (draft == null) return;

    _isAgentBusy = true;
    _agentProgressStep =
        'Synthesizing Project Concept Blueprint ($_conversationModel · ${_thinkingLevel.toLowerCase()})...';
    notifyListeners();

    try {
      await ProjectConceptAgent.synthesizeFromInterview(
        draft,
        apiKey: _apiKey,
        modelName: _conversationModel,
        thinkingLevel: _thinkingLevel,
      );
      _commitConceptToVault(draft);
    } finally {
      _isAgentBusy = false;
      _agentProgressStep = null;
      notifyListeners();
    }
  }

  void _commitConceptToVault(ProjectConceptBlueprint draft) {
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
    for (int i = 0; i < draft.releaseTrainTitles.length; i++) {
      final relId = 'rel_v0_${i + 1}';
      final relTitle = draft.releaseTrainTitles[i];
      final existingRel = documents[relId];

      if (existingRel != null) {
        existingRel.title = relTitle;
        if (existingRel.childrenIds.isEmpty && i == 0) {
          existingRel.sections['releaseScope'] = draft.firstReleasePreset.name;
          existingRel.sections['scope'] =
              'Goal: ${draft.goal}\n\nIn Scope:\n${draft.coreLoopBeats.map((b) => '• $b').join('\n')}\n\nOut of Scope:\n${draft.exclusions.map((e) => '• $e').join('\n')}\n\nDone When: ${draft.doneWhen}';
        }
        releaseIds.add(relId);
        continue;
      }

      final relDoc = TierDocument(
        id: relId,
        title: relTitle,
        tier: TierType.release,
        parentId: projId,
        sections: {
          'releaseScope': (i == 0 ? draft.firstReleasePreset : ReleaseScope.mvp).name,
          'scope': i == 0
              ? 'Goal: ${draft.goal}\n\nIn Scope:\n${draft.coreLoopBeats.map((b) => '• $b').join('\n')}\n\nOut of Scope:\n${draft.exclusions.map((e) => '• $e').join('\n')}\n\nDone When: ${draft.doneWhen}'
              : 'Goal: Queued future milestone.\n\nIn Scope:\n• Pending completion of prior release\n\nDone When: Prior release shipped.',
        },
      );
      documents[relId] = relDoc;
      releaseIds.add(relId);
    }

    projDoc.childrenIds = releaseIds;
    documents[projId] = projDoc;
    _activeProjectId = projId;
    _activeReleaseId ??= releaseIds.isNotEmpty ? releaseIds.first : null;
  }

  /// Step 1C -> Stage 2: Lock in the Project Concept and open the Release Plan Gate for the active Release.
  Future<void> openReleasePlanGate({String? releaseId}) async {
    if (_conceptDraft != null && _activeProjectId == null) {
      _commitConceptToVault(_conceptDraft!);
    }

    final proj = activeProject;
    if (proj == null) return;

    final targetRelId = releaseId ??
        _activeReleaseId ??
        (proj.childrenIds.isNotEmpty ? proj.childrenIds.first : null);
    if (targetRelId == null) return;

    // Collect existing live Beats & Features from the currently active (or prior) release
    // so evolving to v0.2+ preserves the single live game tree!
    final existingBeats = <TierDocument>[];
    final existingFeaturesByBeat = <String, List<TierDocument>>{};
    for (final rel in projectReleases) {
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

    _activeReleaseId = targetRelId;
    final relDoc = documents[targetRelId];
    if (relDoc == null) return;

    _isAgentBusy = true;
    _agentProgressStep =
        'Drafting Release Blueprint for ${relDoc.title} ($_planningModel · ${_thinkingLevel.toLowerCase()})...';
    notifyListeners();

    try {
      _releaseBlueprint = await ReleasePlannerAgent.planRelease(
        projectDoc: proj,
        releaseDoc: relDoc,
        existingBeats: existingBeats,
        existingFeaturesByBeat: existingFeaturesByBeat,
        apiKey: _apiKey,
        modelName: _planningModel,
        thinkingLevel: _thinkingLevel,
      );
      _currentStage = WorkbenchStage.releasePlanGate;
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
        'Refining Release Plan ($_planningModel · ${_thinkingLevel.toLowerCase()})...';
    notifyListeners();

    try {
      await ReleasePlannerAgent.sendReleasePlanChatTurn(
        blueprint: bp,
        userMessage: message,
        apiKey: _apiKey,
        modelName: _planningModel,
        thinkingLevel: _thinkingLevel,
      );
    } finally {
      _isAgentBusy = false;
      _agentProgressStep = null;
      notifyListeners();
    }
  }

  /// Toggles whether a proposed Feature in the Release Plan Gate is kept in scope or deferred to Out of Scope.
  void toggleProposedFeatureScope(String beatId, String featureId, bool included) {
    final bp = _releaseBlueprint;
    if (bp == null) return;
    for (final beat in bp.beats) {
      if (beat.id == beatId) {
        for (final feat in beat.features) {
          if (feat.id == featureId) {
            feat.included = included;
            notifyListeners();
            return;
          }
        }
      }
    }
  }

  /// Toggles all non-superseded Features inside a Beat on or off at once in Stage 2.
  void toggleProposedBeatScope(String beatId, bool included) {
    final bp = _releaseBlueprint;
    if (bp == null) return;
    for (final beat in bp.beats) {
      if (beat.id == beatId) {
        for (final feat in beat.features) {
          if (!feat.isSuperseded) {
            feat.included = included;
          }
        }
        notifyListeners();
        return;
      }
    }
  }

  /// Adds a custom Playable Feature stub directly into a Beat in Stage 2 without waiting for AI regeneration.
  void addProposedFeatureToBeat(String beatId, String rawTitle) {
    final bp = _releaseBlueprint;
    final cleanTitle = rawTitle.trim();
    if (bp == null || cleanTitle.isEmpty) return;

    for (final beat in bp.beats) {
      if (beat.id == beatId) {
        final featId = 'feat_${beat.id}_${beat.features.length + 1}_${DateTime.now().millisecondsSinceEpoch % 10000}';
        beat.features.add(
          ProposedFeatureBlueprint(
            id: featId,
            title: cleanTitle,
            goal: 'Build playable $cleanTitle mechanics and player feedback for ${beat.title}.',
            doneWhen: 'Player executes $cleanTitle in viewport with immediate visual response.',
            estimatedHours: 4,
            included: true,
            lifecycle: FeatureLifecycleStatus.newFeature,
            originVersion: bp.releaseVersionTag,
            inScope: [
              'Core $cleanTitle interaction & state',
              'Immediate visual & HUD feedback',
            ],
            outOfScope: [
              'Final production art polish',
            ],
            tuningParams: [
              'responseTime: 0.15s',
            ],
            edgeCases: [
              'Prevent duplicate trigger during active cooldown',
            ],
            checkpoints: [
              ProposedCheckpointBlueprint(
                title: '[BUILD PASS] $cleanTitle Core Execution',
                playtestCriteria: 'Trigger $cleanTitle in viewport and verify responsive state change and feedback.',
                tasks: [
                  'Implement core player interaction and state for $cleanTitle (2h)',
                  'Hook up immediate visual/audio cue and verify in viewport (2h)',
                ],
                coveredScope: [
                  'Core $cleanTitle interaction & state',
                  'Immediate visual & HUD feedback',
                ],
                tuningParams: [
                  'responseTime: 0.15s',
                ],
                edgeCases: [
                  'Prevent duplicate trigger during active cooldown',
                ],
                releaseVersion: bp.releaseVersionTag,
              ),
            ],
          ),
        );
        notifyListeners();
        return;
      }
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
      }

      // Auto-select the first Feature that has incomplete checkpoints (or Beat 1 / Feature 1)
      final beats = activeReleaseBeats;
      if (beats.isNotEmpty) {
        TierDocument? firstActiveBeat;
        TierDocument? firstActiveFeat;
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
        _selectedBeatId = (firstActiveBeat ?? beats.first).id;
        final feats = featuresForBeat(_selectedBeatId!);
        _selectedFeatureId =
            (firstActiveFeat ?? (feats.isNotEmpty ? feats.first : null))?.id;
      }
    } finally {
      _isAgentBusy = false;
      _agentProgressStep = null;
      notifyListeners();
    }
  }

  void selectBeat(String beatId) {
    if (!documents.containsKey(beatId)) return;
    _selectedBeatId = beatId;
    final feats = featuresForBeat(beatId);
    _selectedFeatureId = feats.isNotEmpty ? feats.first.id : null;
    notifyListeners();
  }

  void selectFeature(String featureId) {
    final feat = documents[featureId];
    if (feat == null) return;
    _selectedFeatureId = featureId;
    if (feat.parentId != null) {
      _selectedBeatId = feat.parentId;
    }
    notifyListeners();
  }

  void updateFeatureStates(String featureId, List<FeatureStateNode> states) {
    final feat = documents[featureId];
    if (feat == null) return;
    FeatureStateNode.saveStatesToDocument(feat, states);
    notifyListeners();
  }

  /// Rollup progress (0-100) for any document in the hierarchy.
  int getDocumentProgress(String docId) {
    final doc = documents[docId];
    if (doc == null) return 0;

    if (doc.tier == TierType.feature) {
      final states = FeatureStateNode.getStatesForDocument(doc);
      if (states.isEmpty) return doc.isCompleted ? 100 : 0;
      int total = 0;
      int done = 0;
      for (final s in states) {
        total += s.totalChecklistCount;
        done += s.completedChecklistCount;
      }
      if (total == 0) return 0;
      return ((done / total) * 100).round();
    }

    if (doc.childrenIds.isEmpty) return doc.isCompleted ? 100 : 0;
    int sum = 0;
    int count = 0;
    for (final childId in doc.childrenIds) {
      if (documents.containsKey(childId)) {
        sum += getDocumentProgress(childId);
        count++;
      }
    }
    return count == 0 ? 0 : (sum / count).round();
  }

  /// Returns true if all Checkpoints across all Features in the active Release are 100% verified.
  bool get isActiveReleaseComplete {
    final beats = activeReleaseBeats;
    if (beats.isEmpty) return false;
    for (final b in beats) {
      final feats = featuresForBeat(b.id);
      if (feats.isEmpty) return false;
      for (final f in feats) {
        if (getDocumentProgress(f.id) < 100) return false;
      }
    }
    return true;
  }

  ProductionPhase _currentPhase = ProductionPhase.prototype;
  ProductionPhase get currentPhase => _currentPhase;

  /// Advances to the next queued Release in the current Production Phase, or unlocks the
  /// next Production Phase once the current phase's releases are completed:
  /// - Phase 1 (Prototype) complete -> Phase 2 (MVP Track: 1 MVP Release per Core Loop Beat)
  /// - Phase 2 (MVP Track) complete -> Phase 3 (Vertical Slice: 1 Polished Gold Standard Level)
  /// - Phase 3 (Vertical Slice) complete -> Phase 4 (Full Production: World & Content Expansion)
  Future<void> advanceToNextRelease() async {
    final proj = activeProject;
    if (proj == null) return;
    final releases = projectReleases;
    if (releases.isEmpty) return;

    final currentIdx = releases.indexWhere((r) => r.id == _activeReleaseId);
    final nextIdx = currentIdx + 1;
    if (nextIdx < releases.length) {
      await openReleasePlanGate(releaseId: releases[nextIdx].id);
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
      } else if (_conceptDraft != null && _conceptDraft!.coreLoopBeats.isNotEmpty) {
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
        final newRelId = 'rel_v0_$newIndex';
        final beatLabel = beatNames[i];
        final newRelDoc = TierDocument(
          id: newRelId,
          title: 'v0.$newIndex: MVP Beat ${i + 1} ($beatLabel) - MVP',
          tier: TierType.release,
          parentId: proj.id,
          sections: {
            'releaseScope': ReleaseScope.mvp.name,
            'phase': ProductionPhase.mvp.name,
            'scope':
                'Goal: Build and connect MVP systems for Beat ${i + 1} ($beatLabel).\n\nIn Scope:\n• $beatLabel\n\nDone When: Beat ${i + 1} is playable end-to-end inside the rough representative level.',
          },
        );
        documents[newRelId] = newRelDoc;
        proj.childrenIds.add(newRelId);
        firstNewMvpId ??= newRelId;
      }

      if (firstNewMvpId != null) {
        await openReleasePlanGate(releaseId: firstNewMvpId);
        return;
      }
    } else if (_currentPhase == ProductionPhase.mvp) {
      _currentPhase = ProductionPhase.verticalSlice;
      final newIndex = proj.childrenIds.length + 1;
      final newRelId = 'rel_v0_$newIndex';
      final newRelDoc = TierDocument(
        id: newRelId,
        title: 'v0.$newIndex: Gold Standard Level (Combined MVPs) - Vertical Slice',
        tier: TierType.release,
        parentId: proj.id,
        sections: {
          'releaseScope': ReleaseScope.verticalSlice.name,
          'phase': ProductionPhase.verticalSlice.name,
          'scope':
              'Goal: Combine all completed MVP Beats into 1 fully polished Gold Standard level.\n\nIn Scope:\n• Final art, audio, UI, and game-feel pass on the representative level\n\nDone When: Playtester completes the polished Vertical Slice level at shippable quality.',
        },
      );
      documents[newRelId] = newRelDoc;
      proj.childrenIds.add(newRelId);
      await openReleasePlanGate(releaseId: newRelId);
      return;
    }

    // Phase 4: Full Production content drops (reusing the Rough -> Polish pattern)
    _currentPhase = ProductionPhase.fullProduction;
    final newIndex = proj.childrenIds.length + 1;
    final newRelId = 'rel_v0_$newIndex';
    final newRelDoc = TierDocument(
      id: newRelId,
      title: 'v0.$newIndex: Full Production World & Content Pass - Standard',
      tier: TierType.release,
      parentId: proj.id,
      sections: {
        'releaseScope': ReleaseScope.verticalSlice.name,
        'phase': ProductionPhase.fullProduction.name,
        'scope':
            'Goal: Expand the verified Vertical Slice template to the next world zone.\n\nIn Scope:\n• Rough layout pass followed by final polish for new content\n\nDone When: All checkpoints verified.',
      },
    );
    documents[newRelId] = newRelDoc;
    proj.childrenIds.add(newRelId);
    await openReleasePlanGate(releaseId: newRelId);
  }
}
