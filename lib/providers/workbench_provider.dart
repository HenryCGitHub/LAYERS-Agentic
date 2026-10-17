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

  String _modelName = 'gemini-2.5-flash';
  String get modelName => _modelName;

  static const List<String> availableModels = [
    'gemini-2.5-flash',
    'gemini-2.5-pro',
    'gemini-2.0-flash',
  ];

  void updateAiConfig({String? apiKey, String? modelName}) {
    if (apiKey != null) {
      _apiKey = apiKey.trim();
    }
    if (modelName != null && modelName.trim().isNotEmpty) {
      _modelName = modelName.trim();
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

  void toggleTheme() {
    _isDark = !_isDark;
    notifyListeners();
  }

  void setStage(WorkbenchStage stage) {
    _currentStage = stage;
    notifyListeners();
  }

  /// Step 1A -> 1B: User submits their 1-line Spark idea and starts the Concept Interview.
  Future<void> startConceptInterview(String sparkText) async {
    _isAgentBusy = true;
    _agentProgressStep = 'Preparing tailored Concept Interview...';
    notifyListeners();

    try {
      _conceptDraft = await ProjectConceptAgent.startConceptInterview(
        sparkText,
        apiKey: _apiKey,
        modelName: _modelName,
      );
    } finally {
      _isAgentBusy = false;
      _agentProgressStep = null;
      notifyListeners();
    }
  }

  /// Step 1B -> 1C: User completes the multiple-choice Concept Interview to generate the Project Blueprint.
  Future<void> completeConceptInterview() async {
    final draft = _conceptDraft;
    if (draft == null) return;

    _isAgentBusy = true;
    _agentProgressStep = 'Synthesizing Project Concept Blueprint & Release Train...';
    notifyListeners();

    try {
      await ProjectConceptAgent.synthesizeFromInterview(
        draft,
        apiKey: _apiKey,
        modelName: _modelName,
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
    final projDoc = TierDocument(
      id: projId,
      title: draft.title,
      tier: TierType.project,
      sections: {
        'scope': draft.toFormattedScopeSection(),
      },
    );

    final releaseIds = <String>[];
    for (int i = 0; i < draft.releaseTrainTitles.length; i++) {
      final relId = 'rel_v0_${i + 1}';
      final relTitle = draft.releaseTrainTitles[i];

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
    _activeReleaseId = releaseIds.isNotEmpty ? releaseIds.first : null;
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

    _activeReleaseId = targetRelId;
    final relDoc = documents[targetRelId];
    if (relDoc == null) return;

    _isAgentBusy = true;
    _agentProgressStep = 'Drafting Release Blueprint for ${relDoc.title}...';
    notifyListeners();

    try {
      _releaseBlueprint = await ReleasePlannerAgent.planRelease(
        projectDoc: proj,
        releaseDoc: relDoc,
        apiKey: _apiKey,
        modelName: _modelName,
      );
      _currentStage = WorkbenchStage.releasePlanGate;
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

  /// Stage 2 -> Stage 3: User approves the Release Plan Gate; Executor Agent builds the full Release hierarchy.
  Future<void> approveAndExecuteReleasePlan() async {
    final bp = _releaseBlueprint;
    final relDoc = activeRelease;
    if (bp == null || relDoc == null) return;

    _isAgentBusy = true;
    _executionLog.clear();
    _currentStage = WorkbenchStage.releaseWorkbench;
    notifyListeners();

    try {
      final createdDocs = await ReleaseExecutorAgent.executeBlueprint(
        releaseDoc: relDoc,
        blueprint: bp,
        onProgress: (msg) {
          _agentProgressStep = msg;
          _executionLog.add(msg);
          notifyListeners();
        },
      );

      for (final d in createdDocs) {
        documents[d.id] = d;
      }

      // Auto-select Beat 1 and Feature 1 so the user lands directly on Checkpoint 1 ready to work!
      final beats = activeReleaseBeats;
      if (beats.isNotEmpty) {
        _selectedBeatId = beats.first.id;
        final feats = featuresForBeat(beats.first.id);
        _selectedFeatureId = feats.isNotEmpty ? feats.first.id : null;
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

  /// Advances to the next queued Release in the Release Train and opens its Plan Gate.
  Future<void> advanceToNextRelease() async {
    final releases = projectReleases;
    if (releases.isEmpty) return;
    final currentIdx = releases.indexWhere((r) => r.id == _activeReleaseId);
    final nextIdx = currentIdx + 1;
    if (nextIdx < releases.length) {
      await openReleasePlanGate(releaseId: releases[nextIdx].id);
    }
  }
}
