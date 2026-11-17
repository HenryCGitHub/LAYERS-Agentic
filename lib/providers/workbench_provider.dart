import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../agents/gemini_agent_client.dart';
import '../agents/project_concept_agent.dart';
import '../agents/release_planner_agent.dart';
import '../constants/tiers.dart';
import '../models/agent_blueprints.dart';
import '../models/epic_spec.dart';
import '../models/tier_document.dart';
import '../services/auth_service.dart';
import '../services/firestore_vault_service.dart';
import '../services/local_vault_service.dart';
import '../utils/markdown_exporter.dart';
import '../utils/unreal_mcp_payload_builder.dart';
import '../utils/unreal_spec_guard.dart';

part 'workbench_storage_mixin.dart';
part 'workbench_concept_mixin.dart';
part 'workbench_release_mixin.dart';
part 'workbench_progressive_planner_mixin.dart';
part 'workbench_unreal_mixin.dart';

/// Pure 2-Stage Antigravity Studio Workflow:
/// - [projectPitch]: `1. Project Spec` (`PROJECT_SPEC.md` -> `ROOT_MCP_CONTEXT`, Spark Onboarding, Co-Designer).
/// - [releaseWorkbench]: `2. Epic Specs` (6-section Unreal MCP Spec Sheets, `v0.1` -> `v0.2+`, `LayersBridge` Sync).
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
  List<AiAccessRecord> get pendingInvites =>
      _aiAccessRecords.where((r) => r.status == 'pending').toList();
  List<AiAccessRecord> get activeApprovedMembers =>
      _aiAccessRecords.where((r) => r.status == 'approved').toList();
  List<AiAccessRecord> get revokedMembers =>
      _aiAccessRecords.where((r) => r.status == 'revoked').toList();

  String? _pendingUrlInviteToken;
  String? _pendingUrlInvitedEmail;
  String? _pendingUrlProjectId;
  String? _pendingUrlEpicId;
  String? _inviteFeedbackMessage;

  int? _pendingUnrealAuthPort;
  String? _pendingUnrealAuthState;
  String? _pendingUnrealUprojectName;
  String? _unrealAuthSelectedProjectId;
  bool _unrealAuthMinimized = false;
  bool _isCompletingUnrealAuth = false;
  String? _unrealAuthError;

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

  String _conversationModel = 'gemini-4-hydrogen';
  String get conversationModel => _conversationModel;

  String _planningModel = 'gemini-4-hydrogen';
  String get planningModel => _planningModel;

  String _thinkingLevel = 'LOW';
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
    );
    notifyListeners();
  }

  String get activeModelIndicatorLabel {
    final used = (GeminiAgentClient.lastResolvedModel ?? _conversationModel)
        .toLowerCase();
    if (used.contains('hydrogen')) return '⚡ Hydrogen';
    if (used.contains('flash')) return '⚡ Flash (Fallback)';
    return 'Gemini';
  }

  static const List<String> availableConversationModels = [
    'gemini-4-hydrogen',
    'gemini-flash-latest',
  ];

  static const List<String> availablePlanningModels = [
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
  final List<String> _executionLog = <String>[];
  final Map<String, String> _cachedUnrealLinkTokensByProjectId = {};

  String? _activeProjectId;
  String? get activeProjectId => _activeProjectId;

  String? _activeReleaseId;
  String? get activeReleaseId => _activeReleaseId;

  String? _selectedEpicId;
  String? get selectedEpicId => _selectedEpicId;

  bool _showingSparkPicker = true;
  bool get showingSparkPicker => _showingSparkPicker;

  bool _showRawRootContext = false;
  bool get showRawRootContext => _showRawRootContext;

  bool _showRawEpicPayload = false;
  bool get showRawEpicPayload => _showRawEpicPayload;

  ProjectConceptBlueprint? _conceptDraft;
  ProjectConceptBlueprint? get conceptDraft => _conceptDraft;

  ProgressiveReleaseDraft? _progressiveDraft;
  ProgressiveReleaseDraft? get progressiveDraft => _progressiveDraft;

  bool _isDraftingProgressive = false;
  bool get isDraftingProgressive => _isDraftingProgressive;

  bool _isAgentBusy = false;
  bool get isAgentBusy => _isAgentBusy;

  String? _agentProgressStep;
  String? get agentProgressStep => _agentProgressStep;

  Timer? _autoSyncDebounceTimer;

  String? get cachedUnrealLinkTokenForActiveProject => _activeProjectId != null
      ? _cachedUnrealLinkTokensByProjectId[_activeProjectId!]
      : null;

  void clearCachedUnrealLinkTokens() {
    _cachedUnrealLinkTokensByProjectId.clear();
  }

  void scheduleDebouncedAutoSync() {
    _autoSyncDebounceTimer?.cancel();
    if (!isUserLoggedIn) return;
    _autoSyncDebounceTimer = Timer(const Duration(seconds: 2), () async {
      await syncNowWithCloud();
    });
  }

  WorkbenchProvider({this.enableAutoLoad = true}) {
    _authService.addListener(_onAuthStateChanged);
    if (enableAutoLoad) {
      GeminiAgentClient.authTokenProvider =
          ({bool forceRefresh = false}) =>
              _authService.getValidIdToken(forceRefresh: forceRefresh);
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

  void toggleRawRootContext([bool? value]) {
    _showRawRootContext = value ?? !_showRawRootContext;
    notifyListeners();
  }

  void toggleRawEpicPayload([bool? value]) {
    _showRawEpicPayload = value ?? !_showRawEpicPayload;
    notifyListeners();
  }

  UnrealTargetEngine get targetEngine =>
      _conceptDraft?.targetEngine ?? UnrealTargetEngine.ue5Mcp;

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

  List<TierDocument> get projectReleases {
    final proj = activeProject;
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

  String get nextReleaseActionLabel =>
      '+ Plan ${ReleasePlannerAgent.nextMinorVersionTag(highestProjectReleaseVersionTag)} Release';

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
      }
    }
    _syncActiveProjectMetadata();
    notifyListeners();
  }
}
