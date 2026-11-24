import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../agents/gemini_agent_client.dart';
import '../agents/project_concept_agent.dart';
import '../agents/release_planner_agent.dart';
import '../agents/stage2_refine_agent.dart';
import '../constants/tiers.dart';
import '../models/agent_blueprints.dart';
import '../models/epic_spec.dart';
import '../models/tier_document.dart';
import '../services/auth_service.dart';
import '../services/cloud_invite_deep_link_service.dart';
import '../services/firestore_vault_service.dart';
import '../services/local_gdd_sync_service.dart';
import '../services/local_vault_service.dart';
import '../services/project_archive_codec.dart';
import '../services/v01_release_seeder.dart';
import '../utils/markdown_exporter.dart';
import '../utils/unreal_context_builder.dart';
import '../utils/unreal_spec_guard.dart';

export '../services/cloud_invite_deep_link_service.dart'
    show shouldPreferRemoteDocumentOnSync;
export '../services/local_gdd_sync_service.dart'
    show
        LocalGddFileBackend,
        LocalGddLinkResult,
        LocalGddSyncStatus,
        LocalGddWriteResult;

part 'workbench_storage_mixin.dart';
part 'workbench_concept_mixin.dart';
part 'workbench_release_mixin.dart';
part 'workbench_progressive_planner_mixin.dart';
part 'workbench_copilot_mixin.dart';
part 'workbench_stage2_refine_mixin.dart';
part 'workbench_spec_edit_mixin.dart';

/// Pure 2-Stage Antigravity Studio Workflow:
/// - [projectPitch]: `1. Project Spec` (`PROJECT_SPEC.md` -> `ROOT_UNREAL_CONTEXT`, Spark Onboarding, Co-Designer).
/// - [releaseWorkbench]: `2. Release Workbench` (Unreal Engine 5 Domain Epics & Feature Slices, `v0.1` -> `v0.2+`, CoPilot GDD & Prompts).
enum WorkbenchStage {
  projectPitch,
  releaseWorkbench,
}

class WorkbenchProvider extends ChangeNotifier {
  static const String ownerAdminEmail = 'henryyoungchoi@gmail.com';

  final bool enableAutoLoad;
  final AuthService _authService = AuthService();
  final FirestoreVaultService _firestoreService = FirestoreVaultService();

  bool _isDisposed = false;
  DateTime? _lastCloudSyncAt;
  DateTime? get lastCloudSyncAt => _lastCloudSyncAt;

  /// Test-only hook to simulate signed-in collaborator/admin identity in unit tests.
  String? testOverrideUserEmail;

  /// Test-only hooks for verifying cloud vault flushes without live Firebase Auth/Firestore.
  String? testOverrideUserUid;
  Future<void> Function(String uid, TierDocument doc)? testCloudDocumentSaver;
  Future<Map<String, TierDocument>?> Function(String uid)?
      testCloudDocumentsFetcher;

  bool _isCloudSynced = false;
  bool get isCloudSynced => _isCloudSynced;
  bool get isUserLoggedIn =>
      testOverrideUserEmail != null || _authService.isLoggedIn;
  String? get userEmail =>
      testOverrideUserEmail ?? _authService.currentUser?.email;
  String? get userDisplayName => _authService.currentUser?.displayName;
  String? get authLastError => _authService.lastError;
  bool get isAdminUser =>
      (userEmail ?? '').trim().toLowerCase() == ownerAdminEmail;

  String? _myAiAccessStatus;
  String? get myAiAccessStatus => isAdminUser ? 'approved' : _myAiAccessStatus;
  bool get isSessionApprovedForAi =>
      isAdminUser || _myAiAccessStatus == 'approved';

  List<AiAccessRecord> _aiAccessRecords = const [];
  List<AiAccessRecord> get aiAccessRecords =>
      List.unmodifiable(_aiAccessRecords);
  List<AiAccessRecord> get pendingInvites => _aiAccessRecords
      .where((r) => r.status == 'invited' || r.status == 'pending')
      .toList();
  List<AiAccessRecord> get activeApprovedMembers =>
      _aiAccessRecords.where((r) => r.status == 'approved').toList();
  List<AiAccessRecord> get revokedMembers =>
      _aiAccessRecords.where((r) => r.status == 'revoked').toList();

  String? _pendingUrlInviteToken;
  String? _pendingUrlInvitedEmail;
  String? _pendingUrlProjectId;
  String? _pendingUrlEpicId;
  String? _pendingUrlFeatureId;
  String? _inviteFeedbackMessage;
  bool _userPinnedMode = false;

  String? get pendingUrlInviteToken => _pendingUrlInviteToken;
  String? get pendingUrlInvitedEmail => _pendingUrlInvitedEmail;
  String? get inviteFeedbackMessage => _inviteFeedbackMessage;
  bool get hasPendingInviteLanding =>
      (_pendingUrlInviteToken != null &&
          _pendingUrlInviteToken!.trim().isNotEmpty) &&
      (!isUserLoggedIn || !isSessionApprovedForAi);

  String? _offlineErrorMessage;
  String? get offlineErrorMessage => _offlineErrorMessage;
  bool get isOffline => _offlineErrorMessage != null;

  WorkbenchStage _currentStage = WorkbenchStage.projectPitch;
  WorkbenchStage get currentStage => _currentStage;

  bool _isDark = true;
  bool get isDark => _isDark;

  String _apiKey = GeminiAgentClient.resolveDefaultApiKey();
  String get apiKey => _apiKey;
  bool get isUsingHostedGoogleAi =>
      isUserLoggedIn && isSessionApprovedForAi && _apiKey.trim().isEmpty;
  bool get hasLiveAiKey =>
      GeminiAgentClient.hasKey(_apiKey) || isUsingHostedGoogleAi;
  String? get aiLastErrorStatus => GeminiAgentClient.lastErrorStatus;
  String? get aiFallbackReason => GeminiAgentClient.lastFallbackReason;

  String _conversationModel = GeminiAgentClient.pinnedLiveFlashModel;
  String get conversationModel => _conversationModel;

  String _planningModel = GeminiAgentClient.pinnedArchitectModel;
  String get planningModel => _planningModel;

  String _thinkingLevel = GeminiAgentClient.defaultFastThinkingLevel;
  String get thinkingLevel => _thinkingLevel;

  int get totalInputTokens => GeminiAgentClient.totalInputTokens;
  int get totalOutputTokens => GeminiAgentClient.totalOutputTokens;
  int get totalThinkingTokens => GeminiAgentClient.totalThinkingTokens;
  double get totalEstimatedCostUsd => GeminiAgentClient.totalEstimatedCostUsd;

  String get tokenUsageCompactLabel {
    final total = totalInputTokens + totalOutputTokens;
    if (total <= 0) return '0 tok · \$0.000';
    final cost = totalEstimatedCostUsd < 0.01
        ? '\$${totalEstimatedCostUsd.toStringAsFixed(3)}'
        : '\$${totalEstimatedCostUsd.toStringAsFixed(2)}';
    return '${_formatCompactTokens(total)} · $cost';
  }

  static String _formatCompactTokens(int count) {
    if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1)}M tok';
    }
    if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}k tok';
    }
    return '$count tok';
  }

  void resetTokenUsage() {
    GeminiAgentClient.resetUsage();
    notifyListeners();
  }

  void recordTokenUsage({
    required int inputTokens,
    required int outputTokens,
    int thinkingTokens = 0,
    String? modelUsed,
  }) {
    GeminiAgentClient.recordUsage(
      inputTokens: inputTokens,
      outputTokens: outputTokens,
      thinkingTokens: thinkingTokens,
      model: modelUsed,
    );
    notifyListeners();
  }

  String get activeModelIndicatorLabel {
    final used = (GeminiAgentClient.lastResolvedModel ?? _planningModel)
        .toLowerCase();
    if (used.contains('argon')) return '⚡ Argon';
    if (used.contains('neon')) return '⚡ Neon';
    if (used.contains('hydrogen')) return '⚡ Hydrogen';
    if (used.contains('flash')) return '⚡ Flash (Fallback)';
    return 'Gemini';
  }

  static const List<String> availableConversationModels = [
    'gemini-4-hydrogen',
    'gemini-4-argon',
    'gemini-flash-latest',
  ];

  static const List<String> availablePlanningModels = [
    'gemini-4-argon',
    'gemini-4-neon',
    'gemini-4-hydrogen',
    'gemini-flash-latest',
  ];

  static const List<String> availableThinkingLevels = [
    'LOW',
    'MEDIUM',
    'HIGH',
  ];

  final Map<String, TierDocument> documents = {};
  final Map<String, List<Map<String, String>>> _projectCollaborators = {};
  final Map<String, Timer> _persistTimers = {};
  final Set<String> _pendingCloudWriteDocIds = <String>{};
  Map<String, TierDocument>? _deferredRemoteSnapshot;
  String? _unpersistedNewProjectId;
  final List<String> _executionLog = <String>[];

  String? _activeProjectId;
  String? get activeProjectId => _activeProjectId;

  String? _activeReleaseId;
  String? get activeReleaseId => _activeReleaseId;

  String? _selectedEpicId;
  String? get selectedEpicId => _selectedEpicId;

  String? _selectedFeatureId;
  String? get selectedFeatureId => _selectedFeatureId;

  final Set<String> _expandedEpicIds = <String>{};
  Set<String> get expandedEpicIds => Set.unmodifiable(_expandedEpicIds);
  bool isEpicExpanded(String epicId) => _expandedEpicIds.contains(epicId);

  bool _showingSparkPicker = true;
  bool get showingSparkPicker => _showingSparkPicker;

  ProjectConceptBlueprint? _conceptDraft;
  ProjectConceptBlueprint? get conceptDraft => _conceptDraft;

  final List<ProjectConceptBlueprint> _stage1UndoStack =
      <ProjectConceptBlueprint>[];
  bool get canUndoStage1 => _stage1UndoStack.isNotEmpty;

  Set<String> _lastStage1ChangedSections = const <String>{};
  Set<String> get lastStage1ChangedSections =>
      Set.unmodifiable(_lastStage1ChangedSections);

  SparkClarificationDraft? _pendingSparkClarification;
  SparkClarificationDraft? get pendingSparkClarification =>
      _pendingSparkClarification;

  String? _stage1InlineError;
  String? get stage1InlineError => _stage1InlineError;

  void _clearStage1TransientState() {
    _stage1UndoStack.clear();
    _lastStage1ChangedSections = const <String>{};
    _pendingSparkClarification = null;
    _stage1InlineError = null;
    _clearStage2TransientState();
  }

  final List<_Stage2UndoEntry> _stage2UndoStack = <_Stage2UndoEntry>[];
  String? _stage2UndoProjectId;
  String? _stage2UndoReleaseId;
  bool _isRefiningStage2 = false;
  String? _lastStage2RefineSummary;
  String? _stage2RefineError;
  Set<String> _lastStage2ChangedSections = const <String>{};

  void _syncStage2UndoProjectScope() {
    if (_stage2UndoProjectId != _activeProjectId ||
        _stage2UndoReleaseId != _activeReleaseId) {
      _clearStage2TransientState();
      _stage2UndoProjectId = _activeProjectId;
      _stage2UndoReleaseId = _activeReleaseId;
    }
  }

  void _clearStage2TransientState() {
    _stage2UndoStack.clear();
    _lastStage2RefineSummary = null;
    _stage2RefineError = null;
    _lastStage2ChangedSections = const <String>{};
  }

  bool get isRefiningStage2 => _isRefiningStage2;
  String? get lastStage2RefineSummary => _lastStage2RefineSummary;
  String? get stage2RefineError => _stage2RefineError;
  Set<String> get lastStage2ChangedSections =>
      Set.unmodifiable(_lastStage2ChangedSections);
  bool get canUndoStage2Edit {
    _syncStage2UndoProjectScope();
    return _stage2UndoStack.isNotEmpty;
  }

  ProgressiveReleaseDraft? _progressiveDraft;
  ProgressiveReleaseDraft? get progressiveDraft => _progressiveDraft;

  bool _isDraftingProgressive = false;
  bool get isDraftingProgressive => _isDraftingProgressive;

  int _progressiveDraftRequestSeq = 0;

  void _resetProgressiveDraftState() {
    _progressiveDraftRequestSeq++;
    _isDraftingProgressive = false;
    _progressiveDraft = null;
  }

  bool _isAgentBusy = false;
  bool get isAgentBusy => _isAgentBusy;

  @visibleForTesting
  void setAgentBusyForTest(bool busy) {
    _isAgentBusy = busy;
    if (!busy) {
      flushDeferredRemoteSnapshotIfIdle();
    }
    notifyListeners();
  }

  String? _agentProgressStep;
  String? get agentProgressStep => _agentProgressStep;

  Timer? _autoSyncDebounceTimer;

  LocalGddSyncService _localGddSync = LocalGddSyncService();
  Timer? _localGddDebounceTimer;
  String? _linkedGddProjectId;
  String? _linkedGddFileName;
  LocalGddSyncStatus _gddSyncStatus = LocalGddSyncStatus.unlinked;
  DateTime? _lastGddSyncAt;
  String? _gddSyncError;

  bool get isLocalGddLinkSupported => _localGddSync.isSupported;
  String? get linkedGddFileName =>
      _linkedGddProjectId == _activeProjectId ? _linkedGddFileName : null;
  LocalGddSyncStatus get gddSyncStatus => _gddSyncStatus;
  DateTime? get lastGddSyncAt => _lastGddSyncAt;
  String? get gddSyncError => _gddSyncError;
  bool get isLocalGddLinked =>
      _linkedGddProjectId != null &&
      _linkedGddProjectId == _activeProjectId &&
      _linkedGddFileName != null &&
      _linkedGddFileName!.isNotEmpty &&
      (_gddSyncStatus == LocalGddSyncStatus.linked ||
          _gddSyncStatus == LocalGddSyncStatus.syncing ||
          _gddSyncStatus == LocalGddSyncStatus.synced ||
          _gddSyncStatus == LocalGddSyncStatus.permissionNeeded);

  @visibleForTesting
  void setLocalGddBackendForTest(LocalGddFileBackend backend) {
    _localGddDebounceTimer?.cancel();
    _localGddSync = LocalGddSyncService(backend: backend);
    _linkedGddProjectId = null;
    _linkedGddFileName = null;
    _gddSyncStatus = LocalGddSyncStatus.unlinked;
    _lastGddSyncAt = null;
    _gddSyncError = null;
  }

  void scheduleDebouncedAutoSync() {
    _autoSyncDebounceTimer?.cancel();
    if (!isUserLoggedIn) return;
    _autoSyncDebounceTimer = Timer(const Duration(seconds: 2), () async {
      await syncNowWithCloud();
    });
  }

  void bindHostedProxyAuth({
    Future<String?> Function({bool forceRefresh})? tokenProvider,
  }) {
    GeminiAgentClient.authTokenProvider = tokenProvider ??
        ({bool forceRefresh = false}) =>
            _authService.getValidIdToken(forceRefresh: forceRefresh);
    GeminiAgentClient.isProxyAuthenticated =
        () => isUserLoggedIn && isSessionApprovedForAi;
  }

  WorkbenchProvider({this.enableAutoLoad = true}) {
    _authService.addListener(_onAuthStateChanged);
    if (enableAutoLoad) {
      bindHostedProxyAuth();
      initVault();
    }
  }

  void setAiAccessRecordsForTest(
    List<AiAccessRecord> records, {
    String? overrideEmail,
  }) {
    if (overrideEmail != null) {
      testOverrideUserEmail = overrideEmail;
    }
    _aiAccessRecords = List.unmodifiable(records);
    final me = (userEmail ?? '').trim().toLowerCase();
    for (final rec in records) {
      if (rec.email.toLowerCase() == me) {
        _myAiAccessStatus = rec.status;
        break;
      }
    }
    notifyListeners();
  }

  void setPendingUrlInviteForTest({
    String? inviteToken,
    String? invitedEmail,
    String? projectId,
    String? epicId,
  }) {
    _pendingUrlInviteToken = inviteToken;
    _pendingUrlInvitedEmail = invitedEmail;
    _pendingUrlProjectId = projectId;
    _pendingUrlEpicId = epicId;
    notifyListeners();
  }

  @override
  void notifyListeners() {
    if (_isDisposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _autoSyncDebounceTimer?.cancel();
    _localGddDebounceTimer?.cancel();
    _deferredRemoteSnapshot = null;
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

  void updateAiConfig({
    String? apiKey,
    String? conversationModel,
    String? planningModel,
    String? thinkingLevel,
  }) {
    if (apiKey != null && apiKey.trim().isNotEmpty) {
      _apiKey = apiKey.trim();
    }
    if (conversationModel != null && conversationModel.trim().isNotEmpty) {
      _conversationModel = conversationModel.trim();
    }
    if (planningModel != null && planningModel.trim().isNotEmpty) {
      _planningModel = planningModel.trim();
    }
    if (thinkingLevel != null && thinkingLevel.trim().isNotEmpty) {
      _thinkingLevel = thinkingLevel.trim();
    }
    _persistSettings();
    notifyListeners();
  }

  void toggleTheme() {
    _isDark = !_isDark;
    _persistSettings();
    notifyListeners();
  }

  UnrealArchitectureMode get architectureMode => unrealArchitectureMode;

  TierDocument? get activeProject =>
      _activeProjectId != null ? documents[_activeProjectId] : null;

  TierDocument? get activeRelease =>
      _activeReleaseId != null ? documents[_activeReleaseId] : null;

  TierDocument? get selectedEpicDoc =>
      _selectedEpicId != null ? documents[_selectedEpicId] : null;

  EpicSpec? get selectedEpicSpec {
    final doc = selectedEpicDoc;
    if (doc == null || doc.tier != TierType.epic) return null;
    final epics = activeReleaseEpicDocs;
    final idx = epics.indexWhere((e) => e.id == doc.id);
    return EpicSpec.fromDocument(doc, indexHint: idx >= 0 ? idx : 0);
  }

  List<String> get projectReleaseOrder {
    final tags = <String>{};
    for (final rel in projectReleases) {
      tags.add(releaseVersionTagFor(rel));
    }
    if (tags.isEmpty) return const ['v0.1'];
    final ordered = tags.toList()..sort(ReleasePlannerAgent.compareVersionTags);
    return List.unmodifiable(ordered);
  }

  List<FeatureSpec> visibleFeaturesForEpic(
    EpicSpec epic, {
    String? releaseVersion,
  }) {
    final ver = releaseVersion ?? activeReleaseVersionTag;
    return epic.featuresForRelease(ver, projectReleaseOrder);
  }

  FeatureSpec? get selectedFeatureSpec {
    final fid = _selectedFeatureId;
    final epic = selectedEpicSpec;
    if (fid == null || epic == null) return null;
    for (final feat in visibleFeaturesForEpic(epic)) {
      if (feat.id == fid) return feat;
    }
    return null;
  }

  bool get isInspectingFeature => selectedFeatureSpec != null;

  bool get isInspectingEpicDomain =>
      selectedEpicSpec != null && selectedFeatureSpec == null;

  bool isFeatureLockedBaseline(
    FeatureSpec feature, {
    String? releaseVersion,
  }) {
    return feature.isLockedBaselineInRelease(
      releaseVersion ?? activeReleaseVersionTag,
    );
  }

  bool get isSelectedFeatureLockedBaseline {
    final feat = selectedFeatureSpec;
    return feat != null && isFeatureLockedBaseline(feat);
  }

  TierDocument? get v01BaselineRelease {
    for (final rel in projectReleases) {
      if (releaseVersionTagFor(rel) == 'v0.1') {
        return rel;
      }
    }
    return null;
  }

  ({int passed, int total, int openFixes}) epicFeatureRollup(
    EpicSpec epic, {
    String? releaseVersion,
  }) {
    final ver = releaseVersion ?? activeReleaseVersionTag;
    final visible = visibleFeaturesForEpic(epic, releaseVersion: ver);
    final passed = visible.where((f) => f.isPassedForRelease(ver)).length;
    final openFixes =
        visible.fold<int>(0, (sum, f) => sum + f.openFixesCount) +
        epic.openFixesCount;
    return (passed: passed, total: visible.length, openFixes: openFixes);
  }

  ({int passed, int total, int openFixes}) get activeReleaseFeatureRollup {
    int passed = 0;
    int total = 0;
    int openFixes = 0;
    for (final ep in activeReleaseEpics) {
      final r = epicFeatureRollup(ep);
      passed += r.passed;
      total += r.total;
      openFixes += r.openFixes;
    }
    return (passed: passed, total: total, openFixes: openFixes);
  }

  String activeFeatureBuildPrompt(EpicSpec epic, FeatureSpec feature) {
    final spec = _conceptDraft ??
        ProjectConceptBlueprint(
          gameTitle: activeProject?.title ?? 'LAYERS PROJECT',
        );
    return UnrealContextBuilder.buildCoPilotFeaturePrompt(
      rootSpec: spec,
      epic: epic,
      feature: feature,
      releaseVersion: activeReleaseVersionTag,
      releaseOrder: projectReleaseOrder,
      mode: unrealArchitectureMode,
    );
  }

  String activeFeatureReadablePrompt(EpicSpec epic, FeatureSpec feature) {
    final spec = _conceptDraft ??
        ProjectConceptBlueprint(
          gameTitle: activeProject?.title ?? 'LAYERS PROJECT',
        );
    return UnrealContextBuilder.buildCoPilotFeaturePrompt(
      rootSpec: spec,
      epic: epic,
      feature: feature,
      releaseVersion: activeReleaseVersionTag,
      releaseOrder: projectReleaseOrder,
      mode: unrealArchitectureMode,
      compact: false,
    );
  }

  String activeEpicArchitecturePrompt(EpicSpec epic) {
    final spec = _conceptDraft ??
        ProjectConceptBlueprint(
          gameTitle: activeProject?.title ?? 'LAYERS PROJECT',
        );
    return UnrealContextBuilder.buildEpicArchitectureContext(
      rootSpec: spec,
      epic: epic,
      releaseVersion: activeReleaseVersionTag,
      releaseOrder: projectReleaseOrder,
      mode: unrealArchitectureMode,
    );
  }

  String activeEpicReadableBrief(EpicSpec epic) {
    final spec = _conceptDraft ??
        ProjectConceptBlueprint(
          gameTitle: activeProject?.title ?? 'LAYERS PROJECT',
        );
    return UnrealContextBuilder.buildEpicArchitectureContext(
      rootSpec: spec,
      epic: epic,
      releaseVersion: activeReleaseVersionTag,
      releaseOrder: projectReleaseOrder,
      mode: unrealArchitectureMode,
      compact: false,
    );
  }

  String get selectedBuildPrompt {
    final epic = selectedEpicSpec;
    final feat = selectedFeatureSpec;
    if (epic != null && feat != null) {
      return activeFeatureBuildPrompt(epic, feat);
    }
    if (epic != null) {
      return activeEpicArchitecturePrompt(epic);
    }
    return activeRootUnrealMarkdown;
  }

  List<TierDocument> get savedProjects {
    final projs = documents.values
        .where((d) => d.tier == TierType.project)
        .toList();
    projs.sort((a, b) {
      final tA = int.tryParse(a.sections['updated_at_ms'] ?? '') ?? 0;
      final tB = int.tryParse(b.sections['updated_at_ms'] ?? '') ?? 0;
      if (tA != tB) return tB.compareTo(tA);
      return a.title.compareTo(b.title);
    });
    return projs;
  }

  List<TierDocument> releaseDocsForProject(String projectId) {
    final proj = documents[projectId];
    if (proj == null) return const [];
    final out = <TierDocument>[];
    final seen = <String>{};
    for (final rid in proj.childrenIds) {
      final d = documents[rid];
      if (d != null && d.tier == TierType.release && seen.add(d.id)) {
        out.add(d);
      }
    }
    for (final d in documents.values) {
      if (d.tier == TierType.release &&
          d.parentId == proj.id &&
          seen.add(d.id)) {
        out.add(d);
      }
    }
    return out;
  }

  List<TierDocument> get projectReleases => _activeProjectId != null
      ? releaseDocsForProject(_activeProjectId!)
      : const [];

  List<TierDocument> epicDocsForRelease(String releaseId) {
    final rel = documents[releaseId];
    if (rel == null) return const [];
    final out = <TierDocument>[];
    final seen = <String>{};
    for (final cid in rel.childrenIds) {
      final doc = documents[cid];
      if (doc != null && doc.tier == TierType.epic && seen.add(doc.id)) {
        out.add(doc);
      }
    }
    for (final doc in documents.values) {
      if (doc.tier == TierType.epic &&
          doc.parentId == releaseId &&
          seen.add(doc.id)) {
        out.add(doc);
      }
    }
    return out;
  }

  List<EpicSpec> epicsForRelease(String releaseId) {
    final docs = epicDocsForRelease(releaseId);
    return [
      for (int i = 0; i < docs.length; i++)
        EpicSpec.fromDocument(docs[i], indexHint: i),
    ];
  }

  List<TierDocument> get activeReleaseEpicDocs =>
      _activeReleaseId != null
          ? epicDocsForRelease(_activeReleaseId!)
          : const [];

  List<EpicSpec> get activeReleaseEpics =>
      _activeReleaseId != null
          ? epicsForRelease(_activeReleaseId!)
          : const [];

  String releaseVersionTagFor(TierDocument relDoc) {
    final explicit = relDoc.sections['release_version'];
    if (explicit != null && explicit.trim().isNotEmpty) {
      return ReleasePlannerAgent.extractReleaseVersionTag(explicit);
    }
    return ReleasePlannerAgent.extractReleaseVersionTag(relDoc.title);
  }

  String get activeReleaseVersionTag {
    final rel = activeRelease;
    if (rel == null) return 'v0.1';
    return releaseVersionTagFor(rel);
  }

  String releaseDisplayName(TierDocument relDoc) {
    final tag = releaseVersionTagFor(relDoc);
    final raw = relDoc.title.trim();
    if (raw.isEmpty) {
      return tag == 'v0.1' ? 'v0.1 · Prototype' : '$tag · Update';
    }
    if (raw.toLowerCase().startsWith(tag.toLowerCase())) {
      return raw;
    }
    return '$tag · $raw';
  }

  String releaseConciseLabel(TierDocument relDoc) => releaseDisplayName(relDoc);

  TierDocument? get latestProjectRelease {
    final releases = projectReleases;
    if (releases.isEmpty) return null;
    TierDocument best = releases.first;
    String bestTag = releaseVersionTagFor(best);
    for (int i = 1; i < releases.length; i++) {
      final candidate = releases[i];
      final candidateTag = releaseVersionTagFor(candidate);
      if (ReleasePlannerAgent.compareVersionTags(candidateTag, bestTag) >= 0) {
        best = candidate;
        bestTag = candidateTag;
      }
    }
    return best;
  }

  String get highestProjectReleaseVersionTag {
    final latest = latestProjectRelease;
    if (latest == null) return activeReleaseVersionTag;
    return releaseVersionTagFor(latest);
  }

  List<EpicSpec> get latestReleaseEpics {
    final latest = latestProjectRelease;
    if (latest == null) return activeReleaseEpics;
    return epicsForRelease(latest.id);
  }

  String get nextReleaseVersionTag =>
      ReleasePlannerAgent.nextMinorVersionTag(highestProjectReleaseVersionTag);

  String get nextReleaseActionLabel => '+ Plan $nextReleaseVersionTag Release';

  bool get isActiveReleaseComplete {
    final epics = activeReleaseEpics;
    return epics.isNotEmpty && epics.every((e) => e.isPassed);
  }

  int getDocumentProgress(String docId) {
    final doc = documents[docId];
    if (doc == null) return 0;
    if (doc.tier == TierType.epic) {
      return EpicSpec.fromDocument(doc).progressPercent;
    }
    if (doc.tier == TierType.release) {
      final epics = epicsForRelease(doc.id);
      if (epics.isEmpty) return doc.isCompleted ? 100 : 0;
      final sum = epics.fold<int>(0, (acc, e) => acc + e.progressPercent);
      return (sum / epics.length).round();
    }
    if (doc.tier == TierType.project) {
      final rel = activeReleaseId != null &&
              documents[activeReleaseId]?.parentId == doc.id
          ? documents[activeReleaseId]
          : (projectReleases.isNotEmpty ? projectReleases.first : null);
      if (rel == null) return 0;
      return getDocumentProgress(rel.id);
    }
    return 0;
  }

  void setStage(WorkbenchStage stage) {
    if (stage == WorkbenchStage.releaseWorkbench &&
        activeReleaseEpicDocs.isEmpty) {
      _currentStage = WorkbenchStage.projectPitch;
      notifyListeners();
      return;
    }
    _currentStage = stage;
    if (stage == WorkbenchStage.releaseWorkbench && _selectedEpicId == null) {
      final docs = activeReleaseEpicDocs;
      if (docs.isNotEmpty) {
        _selectedEpicId = docs.first.id;
        _expandedEpicIds.add(_selectedEpicId!);
        _selectedFeatureId = _defaultFeatureIdForEpicDoc(_selectedEpicId);
      }
    }
    _syncActiveProjectMetadata();
    notifyListeners();
  }
}

class _Stage2UndoEntry {
  final String epicDocId;
  final String? featureId;
  final String snapshotJson;
  final String summary;

  const _Stage2UndoEntry({
    required this.epicDocId,
    required this.featureId,
    required this.snapshotJson,
    required this.summary,
  });
}
