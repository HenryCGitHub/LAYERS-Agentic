import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../agents/gemini_agent_client.dart';
import '../agents/project_concept_agent.dart';
import '../agents/release_planner_agent.dart';
import '../constants/tiers.dart';
import '../models/agent_blueprints.dart';
import '../models/feature_state.dart';
import '../models/tier_document.dart';
import '../services/auth_service.dart';
import '../services/firestore_vault_service.dart';
import '../services/local_vault_service.dart';

part 'workbench_storage_mixin.dart';
part 'workbench_concept_mixin.dart';
part 'workbench_release_mixin.dart';

/// Top-level stage in the streamlined 2-stage Antigravity workflow.
enum WorkbenchStage {
  /// Stage 1: Spark -> Concept Blueprint & Release Train
  projectPitch,

  /// Stage 2: Open-Canvas Release Workbench (Epics -> Features -> Steps)
  releaseWorkbench,
}

/// Central state provider for LAYERS-Agentic.
/// Manages the 4-tier document hierarchy and orchestrates the 2-stage
/// Concept Blueprint -> Release Workbench workflow with Cloud Firestore + Local persistence.
class WorkbenchProvider extends ChangeNotifier {
  final Map<String, TierDocument> documents = {};

  final AuthService _authService = AuthService();
  final FirestoreVaultService _firestoreService = FirestoreVaultService();
  final bool enableAutoLoad;

  bool _isCloudSynced = false;
  bool get isCloudSynced => _isCloudSynced;
  bool get isUserLoggedIn => _authService.isLoggedIn;
  String? get userEmail => _authService.currentUser?.email;
  String? get userDisplayName => _authService.currentUser?.displayName;
  String? get authLastError => _authService.lastError;
  DateTime? _lastCloudSyncAt;
  DateTime? get lastCloudSyncAt => _lastCloudSyncAt;
  final Map<String, List<Map<String, String>>> _projectCollaborators = {};

  final Map<String, Timer> _persistTimers = {};
  final Set<String> _pendingCloudWriteDocIds = {};

  /// Pre-project AI Idea Intake & Summary state on the New Project screen (`Stage 1A`).
  SparkIdeaIntakeResult? _sparkIntake;
  SparkIdeaIntakeResult? get sparkIntake => _sparkIntake;
  int _sparkSuggestionVariantOffset = 0;

  String? _offlineErrorMessage;
  String? get offlineErrorMessage => _offlineErrorMessage;
  bool get isOffline => _offlineErrorMessage != null;

  WorkbenchStage _currentStage = WorkbenchStage.projectPitch;
  WorkbenchStage get currentStage => _currentStage;

  bool _isDark = true;
  bool get isDark => _isDark;

  String _apiKey = GeminiAgentClient.resolveDefaultApiKey();
  String get apiKey => _apiKey;
  bool get hasLiveAiKey =>
      GeminiAgentClient.hasKey(_apiKey) &&
      GeminiAgentClient.lastErrorStatus == null;
  String? get aiLastErrorStatus => GeminiAgentClient.lastErrorStatus;

  String _conversationModel = 'gemini-flash-latest';
  String get conversationModel => _conversationModel;

  String _planningModel = 'gemini-4-argon';
  String get planningModel => _planningModel;

  String _thinkingLevel = 'LOW';
  String get thinkingLevel => _thinkingLevel;

  static const List<String> availableConversationModels = [
    'gemini-flash-latest',
    'gemini-3.8-flash',
    'gemini-3.5-flash-lite',
  ];

  static const List<String> availablePlanningModels = [
    'gemini-4-argon',
    'gemini-flash-latest',
    'gemini-3.8-flash',
    'gemini-3.5-flash-lite',
  ];

  static const List<String> availableThinkingLevels = [
    'LOW',
    'MEDIUM',
    'HIGH',
  ];

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

  bool _jumpToFullReviewPending = false;
  bool get jumpToFullReviewPending => _jumpToFullReviewPending;

  Set<String>? _preModalReleaseIds;
  ReleaseBlueprint? _preModalReleaseBlueprint;
  String? _initialProgressiveTrack0BlueprintJson;

  final Set<String> _aiSynthesizedFeatureSteps = <String>{};
  final Set<String> _synthesizingFeatureIds = <String>{};
  final List<String> _pendingFeatureStepQueue = <String>[];
  List<String> get pendingFeatureStepQueue =>
      List.unmodifiable(_pendingFeatureStepQueue);
  bool _isPrewarmingReleaseBlueprint = false;
  bool get isPrewarmingReleaseBlueprint => _isPrewarmingReleaseBlueprint;
  String? _prewarmedConceptSignature;

  ProductionPhase _currentPhase = ProductionPhase.prototype;
  ProductionPhase get currentPhase => _currentPhase;

  ReleaseRetrospectiveSummary? _lastReleaseRetrospective;
  ReleaseRetrospectiveSummary? get lastReleaseRetrospective =>
      _lastReleaseRetrospective;

  static final RegExp _mvpEpicLabelRegex =
      RegExp(r'MVP Epic\s*\d+(?:\s*\([^)]+\))?', caseSensitive: false);

  WorkbenchProvider({this.enableAutoLoad = false}) {
    _authService.addListener(_onAuthStateChanged);
    if (enableAutoLoad) {
      initVault();
    }
  }

  @override
  void notifyListeners() {
    super.notifyListeners();
  }

  @override
  void dispose() {
    for (final timer in _persistTimers.values) {
      timer.cancel();
    }
    _persistTimers.clear();
    _authService.removeListener(_onAuthStateChanged);
    _firestoreService.stopRealtimeSync();
    super.dispose();
  }

  List<Map<String, String>> collaboratorsForProject(String? projectId) {
    if (projectId == null) return const [];
    return List.unmodifiable(_projectCollaborators[projectId] ?? const []);
  }

  void clearOfflineError() {
    if (_offlineErrorMessage != null) {
      _offlineErrorMessage = null;
      notifyListeners();
    }
  }

  void _setOfflineState([String? customReason]) {
    final err = GeminiAgentClient.lastErrorStatus;
    _offlineErrorMessage = customReason ??
        'App is offline — Unable to reach Gemini AI${err != null ? " ($err)" : ""}. Check your connection or API key in AI Settings.';
  }

  void updateAiConfig({
    String? apiKey,
    String? conversationModel,
    String? planningModel,
    String? thinkingLevel,
  }) {
    if (apiKey != null) {
      _apiKey = apiKey.trim();
      GeminiAgentClient.lastErrorStatus = null;
      _offlineErrorMessage = null;
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
    _persistSettings();
    notifyListeners();
  }

  void toggleFocusMode() {
    _focusMode = !_focusMode;
    notifyListeners();
  }

  void setReleaseViewFilter(String filter) {
    _releaseViewFilter = filter;
    if (filter == 'archived') {
      final archived = supersededFeatures;
      if (archived.isNotEmpty &&
          !archived.any((f) => f.id == _selectedFeatureId)) {
        selectFeature(archived.first.id);
        return;
      }
    } else {
      final currentFeat =
          _selectedFeatureId != null ? documents[_selectedFeatureId] : null;
      if (currentFeat == null ||
          currentFeat.sections['lifecycle'] ==
              FeatureLifecycleStatus.superseded.name) {
        _selectFirstIncompleteFeatureInActiveRelease();
        _syncActiveProjectMetadata();
      }
    }
    notifyListeners();
  }

  void consumeJumpToFullReviewPending() {
    _jumpToFullReviewPending = false;
  }

  String? get _activeEngineHint =>
      _conceptDraft?.techSpec.join(' ') ?? activeProject?.sections['tech_spec'];

  String get _activeEngineLabel =>
      TaskHowToBlueprint.detectEngineLabel(_activeEngineHint);

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
    if (rel.childrenIds.isNotEmpty) {
      return rel.childrenIds
          .map((id) => documents[id])
          .whereType<TierDocument>()
          .toList();
    }
    // While drafting a new progressive release (before approveAndExecuteReleasePlan),
    // fall back to the most recent built release's Beats so the Left Outliner Rail stays populated.
    for (final priorRel in projectReleases.reversed) {
      if (priorRel.id != rel.id && priorRel.childrenIds.isNotEmpty) {
        return priorRel.childrenIds
            .map((id) => documents[id])
            .whereType<TierDocument>()
            .toList();
      }
    }
    return const [];
  }

  List<TierDocument> featuresForBeat(String beatId) {
    final beat = documents[beatId];
    if (beat == null) return const [];
    return beat.childrenIds
        .map((id) => documents[id])
        .whereType<TierDocument>()
        .toList();
  }

  /// All superseded/archived testbed features belonging to the active project.
  List<TierDocument> get supersededFeatures {
    final proj = activeProject;
    if (proj == null) return const [];
    final releaseIds = proj.childrenIds.toSet();
    final projectBeatIds = <String>{
      for (final relId in releaseIds)
        ...?documents[relId]?.childrenIds,
      for (final doc in documents.values)
        if (doc.tier == TierType.epic &&
            doc.parentId != null &&
            releaseIds.contains(doc.parentId))
          doc.id,
    };
    return documents.values
        .where(
          (d) =>
              d.tier == TierType.feature &&
              d.sections['lifecycle'] ==
                  FeatureLifecycleStatus.superseded.name &&
              (d.parentId != null && projectBeatIds.contains(d.parentId)),
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
    _persistSettings();
    notifyListeners();
  }

  void setStage(WorkbenchStage stage) {
    _currentStage = stage;
    _syncActiveProjectMetadata();
    notifyListeners();
  }

  /// Extracts or resolves the canonical version tag (`v0.1`, `v0.2`, `v1.0`) for a Release document.
  String releaseVersionTagFor(TierDocument relDoc) {
    final explicitTag = relDoc.sections['versionTag']?.trim();
    if (explicitTag != null && explicitTag.isNotEmpty) return explicitTag;
    return ReleasePlannerAgent.extractReleaseVersionTag(relDoc.title);
  }

  String get activeReleaseVersionTag {
    final rel = activeRelease;
    if (rel == null) return 'v0.1';
    return releaseVersionTagFor(rel);
  }

  /// Resolves the canonical `ProductionPhase` (`prototype`, `mvp`, `verticalSlice`, `fullProduction`) for a Release document.
  ProductionPhase releasePhaseFor(TierDocument relDoc) {
    final rawPhase = (relDoc.sections['phase'] ?? '').trim();
    if (rawPhase == ProductionPhase.fullProduction.name ||
        relDoc.releaseScope == ReleaseScope.fullProduction) {
      return ProductionPhase.fullProduction;
    }
    if (rawPhase == ProductionPhase.verticalSlice.name ||
        relDoc.releaseScope == ReleaseScope.verticalSlice) {
      return ProductionPhase.verticalSlice;
    }
    if (rawPhase == ProductionPhase.mvp.name ||
        relDoc.releaseScope == ReleaseScope.mvp) {
      return ProductionPhase.mvp;
    }
    return ProductionPhase.prototype;
  }

  /// Short uppercase phase badge (`PROTO`, `MVP`, `SLICE`, `PROD`) for compact header pills.
  String releasePhaseShortBadge(TierDocument relDoc) {
    switch (releasePhaseFor(relDoc)) {
      case ProductionPhase.prototype:
        return 'PROTO';
      case ProductionPhase.mvp:
        return 'MVP';
      case ProductionPhase.verticalSlice:
        return 'SLICE';
      case ProductionPhase.fullProduction:
        return 'PROD';
    }
  }

  /// Resolves a clean, descriptive human-readable name for a Release in the Release Selector Dropdown and Header Pill.
  /// Strips version/scope boilerplate and, if the stored title is generic (e.g. `"Prototype"`, `"MVP Epic 1"`),
  /// synthesizes a 2–4 word focus name from the actual Features built or upgraded in that release.
  String releaseDisplayName(TierDocument relDoc) {
    var clean = relDoc.title.trim();
    clean = clean
        .replaceFirst(
          RegExp(r'^v\d+\.\d+(?:\.\d+)?\s*[:\-–—]?\s*', caseSensitive: false),
          '',
        )
        .trim();
    clean = clean
        .replaceFirst(
          RegExp(
            r'\s*[\-–—]\s*(?:Feature\s+Prototype|Prototype|MVP|Vertical\s+Slice|Full\s+Production)\s*$',
            caseSensitive: false,
          ),
          '',
        )
        .trim();

    final mvpParenMatch = RegExp(
      r'^MVP\s+Epic\s*\d+\s*\(([^)]+)\)$',
      caseSensitive: false,
    ).firstMatch(clean);
    if (mvpParenMatch != null) {
      clean = mvpParenMatch.group(1)!.trim();
    }

    final protoPartMatch = RegExp(
      r'^Prototype\s*[\-–—]\s*Part\s*\d+\s*:\s*(.+)$',
      caseSensitive: false,
    ).firstMatch(clean);
    if (protoPartMatch != null) {
      clean = protoPartMatch.group(1)!.trim();
    }

    final lower = clean.toLowerCase();
    final projTitleLower = (activeProject?.title ?? '').toLowerCase().trim();
    final isGeneric = clean.isEmpty ||
        lower == 'prototype' ||
        lower == 'feature prototype' ||
        lower == 'prototype (part 1)' ||
        lower == 'prototype (part 2)' ||
        lower == 'progressive release' ||
        lower == 'mvp' ||
        lower == 'vertical slice' ||
        lower == 'full production' ||
        lower == 'core loop' ||
        (projTitleLower.isNotEmpty && lower == '$projTitleLower core loop') ||
        RegExp(r'^mvp\s+epic\s*\d+$', caseSensitive: false).hasMatch(clean);

    if (!isGeneric) {
      return clean;
    }

    final rVer = releaseVersionTagFor(relDoc).toLowerCase();
    final versionFeatTitles = <String>[];
    for (final beatId in relDoc.childrenIds) {
      for (final feat in featuresForBeat(beatId)) {
        final states = FeatureStateNode.getStatesForDocument(feat);
        final touchedInRel = states.any(
          (s) => s.releaseVersion.toLowerCase() == rVer,
        );
        if (touchedInRel && !versionFeatTitles.contains(feat.title)) {
          versionFeatTitles.add(feat.title);
        }
      }
    }
    if (versionFeatTitles.isNotEmpty) {
      return versionFeatTitles.take(2).join(' & ');
    }

    if (_releaseBlueprint != null &&
        _releaseBlueprint!.releaseDocId == relDoc.id) {
      final bpTitles = <String>[
        for (final b in _releaseBlueprint!.beats)
          for (final f in b.features)
            if (f.included && f.lifecycle != FeatureLifecycleStatus.stable)
              f.title,
      ];
      if (bpTitles.isNotEmpty) {
        return bpTitles.take(2).join(' & ');
      }
    }

    final savedBp = releaseBlueprintFor(relDoc.id);
    if (savedBp != null) {
      final savedTitles = <String>[
        for (final b in savedBp.beats)
          for (final f in b.features)
            if (f.included && f.lifecycle != FeatureLifecycleStatus.stable)
              f.title,
      ];
      if (savedTitles.isNotEmpty) {
        return savedTitles.take(2).join(' & ');
      }
    }

    final fallbackFeatTitles = <String>[];
    for (final beatId in relDoc.childrenIds) {
      for (final feat in featuresForBeat(beatId)) {
        if (!fallbackFeatTitles.contains(feat.title)) {
          fallbackFeatTitles.add(feat.title);
        }
      }
    }
    if (fallbackFeatTitles.isNotEmpty) {
      return fallbackFeatTitles.take(2).join(' & ');
    }

    return clean.isNotEmpty ? clean : releaseConciseLabel(relDoc);
  }

  /// Retrieves the persisted `ReleaseBlueprint` for any Release (`v0.1`, `v0.2`, ...)
  /// so previous release plans are never lost when advancing to later releases.
  ReleaseBlueprint? releaseBlueprintFor(String releaseId) {
    if (_releaseBlueprint != null &&
        _releaseBlueprint!.releaseDocId == releaseId) {
      return _releaseBlueprint;
    }
    final relDoc = documents[releaseId];
    if (relDoc == null) return null;
    final raw = relDoc.sections['release_blueprint_json'];
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      return ReleaseBlueprint.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  /// Concise milestone subtitle for the Stage 3 Release Dropdown and header pill.
  String releaseConciseLabel(TierDocument relDoc) {
    final protoPart = relDoc.sections['prototypePart'] ?? '';
    if (protoPart == '1') return 'Prototype (Part 1)';
    if (protoPart == '2') return 'Prototype (Part 2)';
    final phase = relDoc.sections['phase'] ?? '';
    if (phase == ProductionPhase.mvp.name) {
      final match = _mvpEpicLabelRegex.firstMatch(relDoc.title);
      if (match != null) return match.group(0)!.trim();
      final explicitEpicIdx =
          int.tryParse(relDoc.sections['targetEpicIndex'] ?? '');
      if (explicitEpicIdx != null) {
        return 'MVP Epic ${explicitEpicIdx + 1}';
      }
      final mvpRels = projectReleases
          .where((r) => releasePhaseFor(r) == ProductionPhase.mvp)
          .toList();
      final passIdx = mvpRels.indexWhere((r) => r.id == relDoc.id);
      if (passIdx >= 0 && mvpRels.length > 1) {
        return 'MVP (Pass ${passIdx + 1})';
      }
      return 'MVP';
    }
    if (phase == ProductionPhase.verticalSlice.name ||
        relDoc.releaseScope == ReleaseScope.verticalSlice) {
      final vsRels = projectReleases
          .where((r) => releasePhaseFor(r) == ProductionPhase.verticalSlice)
          .toList();
      final passIdx = vsRels.indexWhere((r) => r.id == relDoc.id);
      if (passIdx >= 0 && vsRels.length > 1) {
        return 'Vertical Slice (Pass ${passIdx + 1})';
      }
      return 'Vertical Slice';
    }
    if (phase == ProductionPhase.fullProduction.name ||
        relDoc.releaseScope == ReleaseScope.fullProduction) {
      final pass = relDoc.sections['fullProductionPass'] ?? '1';
      return 'Full Production (Pass $pass)';
    }
    return relDoc.releaseScope.label;
  }

  /// Returns true if [feat] is an active deliverable (`newFeature` or `upgrade`) in [releaseVersionTag]
  /// (defaults to [activeReleaseVersionTag]), rather than stabilized in a prior release or added in a future release.
  bool isFeatureActiveInRelease(
    TierDocument feat, [
    String? releaseVersionTag,
  ]) {
    final lc = feat.sections['lifecycle'] ?? '';
    if (lc == FeatureLifecycleStatus.superseded.name) {
      return false;
    }
    final targetVer = (releaseVersionTag ?? activeReleaseVersionTag).trim();
    final featActiveVer = feat.sections['activeReleaseVersion']?.trim();
    if (lc == FeatureLifecycleStatus.stable.name) {
      if (featActiveVer == targetVer ||
          (featActiveVer == null && projectReleases.length <= 1)) {
        return false;
      }
    }
    final states = FeatureStateNode.getStatesForDocument(feat);
    if (states.isNotEmpty) {
      final hasCheckpointInTarget =
          states.any((s) => s.releaseVersion == targetVer);
      if (hasCheckpointInTarget) return true;
      if (states.any((s) => s.releaseVersion.trim().isNotEmpty)) {
        return false;
      }
    }
    return lc != FeatureLifecycleStatus.stable.name;
  }

  /// Rollup progress (0-100) for any document in the hierarchy, scoped to the active release's delta checkpoints.
  int getDocumentProgress(String docId) {
    final doc = documents[docId];
    if (doc == null) return 0;

    if (doc.tier == TierType.feature) {
      if (!isFeatureActiveInRelease(doc)) {
        return 100;
      }
      final states = FeatureStateNode.getStatesForDocument(doc);
      if (states.isEmpty) return doc.isCompleted ? 100 : 0;
      final activeVer = activeReleaseVersionTag;
      final activeStates =
          states.where((s) => s.releaseVersion == activeVer).toList();
      final effectiveStates =
          activeStates.isNotEmpty ? activeStates : states;
      int total = 0;
      int done = 0;
      for (final s in effectiveStates) {
        total += s.totalChecklistCount;
        done += s.completedChecklistCount;
      }
      if (total == 0) return 0;
      return ((done / total) * 100).round();
    }

    if (doc.childrenIds.isEmpty) return doc.isCompleted ? 100 : 0;

    // For a Release document, scope progress to active (non-STABLE) Epics so new releases start at 0%
    if (doc.tier == TierType.release) {
      if (doc.id != _activeReleaseId) {
        final relVer = releaseVersionTagFor(doc);
        int relTotal = 0;
        int relDone = 0;
        for (final beatId in doc.childrenIds) {
          for (final feat in featuresForBeat(beatId)) {
            final states = FeatureStateNode.getStatesForDocument(feat);
            for (final s in states) {
              if (s.releaseVersion == relVer) {
                relTotal += s.totalChecklistCount;
                relDone += s.completedChecklistCount;
              }
            }
          }
        }
        if (relTotal > 0) {
          return ((relDone / relTotal) * 100).round();
        }
      }
      final activeBeatIds = doc.childrenIds.where((beatId) {
        final feats = featuresForBeat(beatId);
        return feats.any((f) => isFeatureActiveInRelease(f));
      }).toList();
      final targetBeatIds =
          activeBeatIds.isNotEmpty ? activeBeatIds : doc.childrenIds;
      int sum = 0;
      int count = 0;
      for (final childId in targetBeatIds) {
        if (documents.containsKey(childId)) {
          sum += getDocumentProgress(childId);
          count++;
        }
      }
      return count == 0 ? 0 : (sum / count).round();
    }

    if (doc.tier == TierType.epic) {
      final activeFeatIds = doc.childrenIds.where((featId) {
        final f = documents[featId];
        return f != null && isFeatureActiveInRelease(f);
      }).toList();
      final targetFeatIds =
          activeFeatIds.isNotEmpty ? activeFeatIds : doc.childrenIds;
      int sum = 0;
      int count = 0;
      for (final childId in targetFeatIds) {
        if (documents.containsKey(childId)) {
          sum += getDocumentProgress(childId);
          count++;
        }
      }
      return count == 0 ? 0 : (sum / count).round();
    }

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

  /// Concise 4-Phase Release Train badge displayed in Stage 2 and Stage 3 headers.
  String get activePhaseBadgeLabel {
    final rel = activeRelease;
    final allRels = projectReleases;
    switch (_currentPhase) {
      case ProductionPhase.prototype:
        final protoPart = rel?.sections['prototypePart'] ?? '';
        if (protoPart == '1' || protoPart == '2') {
          return 'PHASE 1 · PROTOTYPE ($protoPart/2)';
        }
        final protoRels = allRels
            .where(
              (r) =>
                  r.sections['phase'] == ProductionPhase.prototype.name ||
                  r.releaseScope == ReleaseScope.prototype ||
                  r.releaseScope == ReleaseScope.featurePrototype,
            )
            .toList();
        if (protoRels.length > 1 && rel != null) {
          final idx = protoRels.indexWhere((r) => r.id == rel.id);
          if (idx >= 0) {
            return 'PHASE 1 · PROTOTYPE (${idx + 1}/${protoRels.length})';
          }
        }
        return 'PHASE 1 · PROTOTYPE';
      case ProductionPhase.mvp:
        final mvpRels = allRels
            .where((r) => r.sections['phase'] == ProductionPhase.mvp.name)
            .toList();
        if (rel != null) {
          final isAgentReasoned = rel.sections['agentReasoned'] == 'true';
          final explicitIdx =
              int.tryParse(rel.sections['targetEpicIndex'] ?? '');
          final explicitTotal =
              int.tryParse(rel.sections['mvpEpicTotal'] ?? '');
          if (explicitIdx != null) {
            final total = explicitTotal ??
                (activeReleaseBeats.isNotEmpty
                    ? activeReleaseBeats.length
                    : mvpRels.length);
            if (explicitIdx >= 0 && total > 0) {
              return 'PHASE 2 · MVP EPIC ${explicitIdx + 1} OF $total';
            }
          } else if (!isAgentReasoned) {
            final idx = mvpRels.indexWhere((r) => r.id == rel.id);
            final total = activeReleaseBeats.isNotEmpty
                ? activeReleaseBeats.length
                : mvpRels.length;
            if (idx >= 0 && total > 0) {
              return 'PHASE 2 · MVP EPIC ${idx + 1} OF $total';
            }
          }
        }
        return 'PHASE 2 · MVP';
      case ProductionPhase.verticalSlice:
        return 'PHASE 3 · VERTICAL SLICE';
      case ProductionPhase.fullProduction:
        final pass = rel?.sections['fullProductionPass'] ?? '1';
        return 'PHASE 4 · FULL PRODUCTION (PASS $pass)';
    }
  }

  /// Descriptive CTA label for the Stage 3 `Ship & Plan Next Release` button naming the exact next milestone or phase unlock.
  String get nextReleaseActionLabel {
    final rel = activeRelease;
    final releases = projectReleases;
    final currentIdx = releases.indexWhere((r) => r.id == _activeReleaseId);
    final nextIdx = currentIdx + 1;
    if (currentIdx >= 0 && nextIdx < releases.length) {
      final nextRel = releases[nextIdx];
      final nextVer = releaseVersionTagFor(nextRel);
      if (nextRel.sections['phase'] == ProductionPhase.mvp.name) {
        final epicIdx =
            (int.tryParse(nextRel.sections['targetEpicIndex'] ?? '') ?? 0) + 1;
        return 'Ship & Plan $nextVer (MVP Epic $epicIdx) ✦';
      }
      if (nextRel.sections['prototypePart'] == '2') {
        return 'Ship & Plan $nextVer (Prototype Part 2) ✦';
      }
      return 'Ship & Plan $nextVer ✦';
    }
    switch (_currentPhase) {
      case ProductionPhase.prototype:
        if (rel?.sections['prototypePart'] == '1') {
          return 'Ship & Plan v0.2 (Prototype Part 2) ✦';
        }
        return 'Ship & Unlock Phase 2 (MVP Epic 1) ✦';
      case ProductionPhase.mvp:
        final explicitIdx =
            int.tryParse(rel?.sections['targetEpicIndex'] ?? '') ?? 0;
        final explicitTotal = int.tryParse(rel?.sections['mvpEpicTotal'] ?? '') ??
            (activeReleaseBeats.isNotEmpty ? activeReleaseBeats.length : 1);
        if ((explicitIdx + 1) < explicitTotal) {
          final nextVer = 'v0.${releases.length + 1}';
          return 'Ship & Plan $nextVer (MVP Epic ${explicitIdx + 2}) ✦';
        }
        return 'Ship & Unlock Phase 3 (Vertical Slice) ✦';
      case ProductionPhase.verticalSlice:
        return 'Ship & Unlock Phase 4 (Full Production) ✦';
      case ProductionPhase.fullProduction:
        return 'Ship & Plan Next Full Production Pass ✦';
    }
  }
}
