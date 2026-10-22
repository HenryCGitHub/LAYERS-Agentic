import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../agents/gemini_agent_client.dart';
import '../agents/project_concept_agent.dart';
import '../agents/release_planner_agent.dart';
import '../agents/workspace_agent_tools.dart';
import '../constants/tiers.dart';
import '../models/agent_blueprints.dart';
import '../models/feature_state.dart';
import '../models/tier_document.dart';
import '../services/auth_service.dart';
import '../services/firestore_vault_service.dart';
import '../services/local_vault_service.dart';

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
/// Interview -> Plan Gate -> Execute workflow with Cloud Firestore + Local persistence.
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

  List<Map<String, String>> collaboratorsForProject(String? projectId) {
    if (projectId == null) return const [];
    return List.unmodifiable(_projectCollaborators[projectId] ?? const []);
  }

  WorkbenchProvider({this.enableAutoLoad = false}) {
    _authService.addListener(_onAuthStateChanged);
    if (enableAutoLoad) {
      initVault();
    }
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

  void _onAuthStateChanged() {
    final user = _authService.currentUser;
    if (user != null) {
      _isCloudSynced = true;
      _lastCloudSyncAt = DateTime.now();
      bool initialLocalPushDone = false;
      // Push any existing local documents up to Firestore on login
      Future.wait([
        for (final doc in documents.values)
          _firestoreService.saveDocument(uid: user.uid, doc: doc),
      ]).then((_) {
        initialLocalPushDone = true;
      });
      if (_activeProjectId != null) {
        _firestoreService.saveSettings(
          uid: user.uid,
          settings: {
            'activeDocumentId': _activeProjectId,
            'themeMode': _isDark ? 'dark' : 'light',
          },
        );
      } else {
        _firestoreService.fetchUserSettings(uid: user.uid).then((remoteSettings) {
          if (remoteSettings == null) return;
          final remoteTheme = remoteSettings['themeMode']?.toString();
          if (remoteTheme != null) {
            _isDark = remoteTheme != 'light';
          }
          final remoteActiveId = remoteSettings['activeDocumentId']?.toString();
          if (remoteActiveId != null && documents.containsKey(remoteActiveId)) {
            _restoreProjectState(remoteActiveId);
          }
          notifyListeners();
        });
      }
      _firestoreService.startRealtimeSync(
        uid: user.uid,
        onSync: (remoteDocs) {
          _lastCloudSyncAt = DateTime.now();
          if (remoteDocs.isEmpty && !initialLocalPushDone) return;
          // Reconcile remote deletions once initial local push has finished
          if (initialLocalPushDone && remoteDocs.isNotEmpty) {
            final removedIds = documents.keys
                .where((localId) => !remoteDocs.containsKey(localId))
                .toList();
            for (final removedId in removedIds) {
              documents.remove(removedId);
              LocalVaultService.deleteDocument(removedId);
            }
          }
          for (final entry in remoteDocs.entries) {
            documents[entry.key] = entry.value;
            LocalVaultService.saveDocument(entry.value);
          }
          if (_activeProjectId == null || !documents.containsKey(_activeProjectId)) {
            final projs = savedProjects;
            if (projs.isNotEmpty) {
              _restoreProjectState(projs.first.id);
            }
          } else {
            _restoreProjectState(_activeProjectId!);
          }
          notifyListeners();
        },
      );
    } else {
      _isCloudSynced = false;
      _firestoreService.stopRealtimeSync();
    }
    notifyListeners();
  }

  /// Manually pushes all current local documents and settings to Cloud Firestore.
  Future<void> syncNowWithCloud() async {
    final user = _authService.currentUser;
    for (final doc in documents.values) {
      await LocalVaultService.saveDocument(doc);
      if (user != null) {
        await _firestoreService.saveDocument(uid: user.uid, doc: doc);
      }
    }
    _persistSettings();
    _lastCloudSyncAt = DateTime.now();
    notifyListeners();
  }

  /// Invites a collaborator by email (`editor` or `viewer`) to the active project and persists to Firestore.
  Future<bool> inviteProjectCollaborator({
    required String collaboratorEmail,
    String role = 'editor',
  }) async {
    final proj = activeProject;
    final cleanEmail = collaboratorEmail.trim().toLowerCase();
    if (proj == null || cleanEmail.isEmpty || !cleanEmail.contains('@')) {
      return false;
    }
    final list = _projectCollaborators.putIfAbsent(proj.id, () => []);
    list.removeWhere((c) => c['email'] == cleanEmail);
    list.add({'email': cleanEmail, 'role': role});
    proj.sections['collaborators_json'] = jsonEncode(list);
    _persistDocument(proj);

    final user = _authService.currentUser;
    if (user != null) {
      await _firestoreService.inviteCollaborator(
        projectId: proj.id,
        projectTitle: proj.title,
        ownerEmail: user.email ?? 'owner',
        collaboratorEmail: cleanEmail,
        role: role,
      );
    }
    notifyListeners();
    return true;
  }

  Future<bool> signInWithGoogle() async {
    final cred = await _authService.signInWithGoogle();
    notifyListeners();
    return cred != null;
  }

  Future<void> signOutFromCloud() async {
    await _authService.signOut();
    notifyListeners();
  }

  /// Loads saved projects from LocalStorage / SharedPreferences and starts Cloud Firestore sync if logged in.
  Future<void> initVault() async {
    try {
      final loaded = await LocalVaultService.loadVaultData();
      // Ignore legacy static placeholder docs (`proj_vanguard`) if they don't have a concept_blueprint_json
      for (final doc in loaded.documents.values) {
        if (doc.id == 'proj_vanguard' ||
            doc.id == 'rel_01' ||
            doc.id == 'epic_01' ||
            doc.id == 'feat_01' ||
            doc.id == 'feat_02') {
          continue;
        }
        documents[doc.id] = doc;
      }
      if (loaded.themeMode != null) {
        _isDark = loaded.themeMode != 'light';
      }
      if (loaded.apiKey != null && loaded.apiKey!.trim().isNotEmpty) {
        _apiKey = loaded.apiKey!.trim();
      }
      final projs = savedProjects;
      if (projs.isNotEmpty) {
        final targetId = (loaded.activeDocumentId != null &&
                documents.containsKey(loaded.activeDocumentId))
            ? loaded.activeDocumentId!
            : projs.first.id;
        _restoreProjectState(targetId);
      }
    } catch (e) {
      debugPrint('initVault error: $e');
    }
    _onAuthStateChanged();
    notifyListeners();
  }

  /// All user-created Tier 1 Project documents in the vault.
  List<TierDocument> get savedProjects {
    return documents.values
        .where((d) => d.tier == TierType.project)
        .toList();
  }

  /// Switches the active project and restores its Stage 1/2/3 blueprints and selection.
  void switchProject(String projectId) {
    if (!documents.containsKey(projectId)) return;
    _restoreProjectState(projectId);
    _persistSettings();
    notifyListeners();
  }

  /// Pre-project AI Idea Intake & Summary state on the New Project screen (`Stage 1A`).
  SparkIdeaIntakeResult? _sparkIntake;
  SparkIdeaIntakeResult? get sparkIntake => _sparkIntake;
  int _sparkSuggestionVariantOffset = 0;

  /// Starts a brand-new Project at Stage 1A (`New Project`) while keeping existing projects in the vault.
  void createNewProject() {
    _activeProjectId = 'proj_${DateTime.now().millisecondsSinceEpoch}';
    _activeReleaseId = null;
    _selectedBeatId = null;
    _selectedFeatureId = null;
    _conceptDraft = null;
    _releaseBlueprint = null;
    _sparkIntake = null;
    _sparkSuggestionVariantOffset = 0;
    _currentStage = WorkbenchStage.projectPitch;
    notifyListeners();
  }

  /// Ingests a raw game idea (or refines the existing ingested summary) on the New Project screen
  /// and populates the 3 Concept Expansion / Twist Cards below the input field.
  Future<void> ingestOrRefineSparkIdea(String userInput) async {
    final clean = userInput.trim();
    if (clean.isEmpty && _sparkIntake == null) return;

    _isAgentBusy = true;
    _agentProgressStep =
        'Ingesting & summarizing idea ($_conversationModel · ${_thinkingLevel.toLowerCase()})...';
    notifyListeners();

    try {
      _sparkIntake = await ProjectConceptAgent.ingestOrRefineSparkIdea(
        userInput: clean,
        existingIntake: _sparkIntake,
        suggestionVariantOffset: _sparkSuggestionVariantOffset,
        apiKey: _apiKey,
        modelName: _conversationModel,
        thinkingLevel: _thinkingLevel,
      );
    } finally {
      _isAgentBusy = false;
      _agentProgressStep = null;
      notifyListeners();
    }
  }

  /// Toggles one of the 3 Concept Expansion / Twist Cards on the New Project screen on or off,
  /// folding that mechanic into (or removing it from) the Agent's Idea Summary without auto-launching Stage 1B.
  void toggleSparkExpansionCard(int cardIndex) {
    // If the user hasn't entered an idea yet, initialize a base intake so the expansion cards can be toggled
    _sparkIntake ??= ProjectConceptAgent.buildDeterministicSparkIntake(
      rawIdea: 'High-speed grappling hook parkour roguelite',
      suggestionVariantOffset: _sparkSuggestionVariantOffset,
    );
    final cards = _sparkIntake!.expansionCards;
    if (cardIndex < 0 || cardIndex >= cards.length) return;
    cards[cardIndex].isSelected = !cards[cardIndex].isSelected;
    notifyListeners();
  }

  /// Cycles the 3 Concept Expansion / Twist Cards on the New Project screen to fresh suggestions.
  void shuffleSparkExpansionCards() {
    _sparkSuggestionVariantOffset++;
    if (_sparkIntake != null) {
      _sparkIntake = ProjectConceptAgent.buildDeterministicSparkIntake(
        rawIdea: _sparkIntake!.rawIdea,
        existingIntake: _sparkIntake,
        suggestionVariantOffset: _sparkSuggestionVariantOffset,
      );
    }
    notifyListeners();
  }

  /// Clears the current pre-project Idea Summary so the user can start fresh.
  void clearSparkIdeaIntake() {
    _sparkIntake = null;
    notifyListeners();
  }

  /// Renames a saved project in the vault (updating both its TierDocument title and Concept Blueprint).
  void renameProject(String projectId, String newTitle) {
    final clean = newTitle.trim();
    final proj = documents[projectId];
    if (proj == null || clean.isEmpty) return;

    proj.title = clean;
    final rawConcept = proj.sections['concept_blueprint_json'];
    if (rawConcept != null && rawConcept.isNotEmpty) {
      try {
        final bp = ProjectConceptBlueprint.fromJson(
          jsonDecode(rawConcept) as Map<String, dynamic>,
        );
        bp.title = clean;
        proj.sections['concept_blueprint_json'] = jsonEncode(bp.toJson());
        if (_activeProjectId == projectId && _conceptDraft != null) {
          _conceptDraft!.title = clean;
        }
      } catch (_) {}
    }
    _persistDocument(proj);
    notifyListeners();
  }

  /// Deep-clones an existing project across all 4 tiers (Project -> Release -> Beat -> Feature)
  /// including all Checkpoints and How-To Sub-Steps, persists to LocalStorage & Firestore, and switches to the copy.
  String? duplicateProject(String projectId) {
    final src = documents[projectId];
    if (src == null) return null;

    final newId = 'proj_${DateTime.now().microsecondsSinceEpoch}';
    final copyTitle = '${src.title} (Copy)';
    final copiedSections = Map<String, String>.from(src.sections);

    final rawConcept = copiedSections['concept_blueprint_json'];
    if (rawConcept != null && rawConcept.isNotEmpty) {
      try {
        final bp = ProjectConceptBlueprint.fromJson(
          jsonDecode(rawConcept) as Map<String, dynamic>,
        );
        bp.title = copyTitle;
        copiedSections['concept_blueprint_json'] = jsonEncode(bp.toJson());
      } catch (_) {}
    }

    final newReleaseIds = <String>[];
    String? mappedActiveReleaseId;
    for (int rIdx = 0; rIdx < src.childrenIds.length; rIdx++) {
      final oldRelId = src.childrenIds[rIdx];
      final oldRel = documents[oldRelId];
      if (oldRel == null) continue;
      final newRelId = '${newId}_rel_${rIdx + 1}';
      if (copiedSections['active_release_id'] == oldRelId) {
        mappedActiveReleaseId = newRelId;
      }

      // Deep-clone Tier 3 Beats and Tier 4 Features under this Release
      final newBeatIds = <String>[];
      for (int bIdx = 0; bIdx < oldRel.childrenIds.length; bIdx++) {
        final oldBeat = documents[oldRel.childrenIds[bIdx]];
        if (oldBeat == null) continue;
        final newBeatId = '${newRelId}_beat_${bIdx + 1}';

        final newFeatIds = <String>[];
        for (int fIdx = 0; fIdx < oldBeat.childrenIds.length; fIdx++) {
          final oldFeat = documents[oldBeat.childrenIds[fIdx]];
          if (oldFeat == null) continue;
          final newFeatId = '${newBeatId}_feat_${fIdx + 1}';
          final clonedFeat = oldFeat.copyWith(
            id: newFeatId,
            parentId: newBeatId,
            sections: Map<String, String>.from(oldFeat.sections),
            subtasks: oldFeat.subtasks.map((st) => st.copyWith()).toList(),
          );
          documents[newFeatId] = clonedFeat;
          _persistDocument(clonedFeat);
          newFeatIds.add(newFeatId);
        }

        final newBeatDoc = oldBeat.copyWith(
          id: newBeatId,
          parentId: newRelId,
          childrenIds: newFeatIds,
          sections: Map<String, String>.from(oldBeat.sections),
        );
        documents[newBeatId] = newBeatDoc;
        _persistDocument(newBeatDoc);
        newBeatIds.add(newBeatId);
      }

      final newRelDoc = oldRel.copyWith(
        id: newRelId,
        parentId: newId,
        childrenIds: newBeatIds,
        sections: Map<String, String>.from(oldRel.sections),
      );
      documents[newRelId] = newRelDoc;
      _persistDocument(newRelDoc);
      newReleaseIds.add(newRelId);
    }

    if (newReleaseIds.isNotEmpty) {
      copiedSections['active_release_id'] =
          mappedActiveReleaseId ?? newReleaseIds.first;
    }

    final copyDoc = TierDocument(
      id: newId,
      title: copyTitle,
      tier: TierType.project,
      childrenIds: newReleaseIds,
      sections: copiedSections,
    );
    documents[newId] = copyDoc;
    _persistDocument(copyDoc);
    switchProject(newId);
    return newId;
  }

  /// Deletes a project and its child documents from LocalVaultService and Cloud Firestore.
  void deleteProject(String projectId) {
    final proj = documents[projectId];
    if (proj == null) return;

    final idsToRemove = <String>{projectId};
    for (final relId in proj.childrenIds) {
      idsToRemove.add(relId);
      final relDoc = documents[relId];
      if (relDoc != null) {
        for (final beatId in relDoc.childrenIds) {
          idsToRemove.add(beatId);
          final beatDoc = documents[beatId];
          if (beatDoc != null) {
            idsToRemove.addAll(beatDoc.childrenIds);
          }
        }
      }
    }

    final user = _authService.currentUser;
    for (final id in idsToRemove) {
      documents.remove(id);
      LocalVaultService.deleteDocument(id);
      if (user != null) {
        _firestoreService.deleteDocument(uid: user.uid, docId: id);
      }
    }

    if (_activeProjectId == projectId) {
      final remaining = savedProjects;
      if (remaining.isNotEmpty) {
        switchProject(remaining.first.id);
      } else {
        createNewProject();
      }
    } else {
      notifyListeners();
    }
  }

  void _restoreProjectState(String projectId) {
    final proj = documents[projectId];
    if (proj == null) return;
    _activeProjectId = projectId;

    // Restore Collaborators
    final rawCollabs = proj.sections['collaborators_json'];
    if (rawCollabs != null && rawCollabs.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawCollabs) as List<dynamic>;
        _projectCollaborators[projectId] = [
          for (final item in decoded)
            if (item is Map)
              {
                'email': (item['email'] ?? '').toString(),
                'role': (item['role'] ?? 'editor').toString(),
              },
        ];
      } catch (_) {}
    }

    // Restore Concept Blueprint
    final rawConcept = proj.sections['concept_blueprint_json'];
    if (rawConcept != null && rawConcept.isNotEmpty) {
      try {
        _conceptDraft = ProjectConceptBlueprint.fromJson(
          jsonDecode(rawConcept) as Map<String, dynamic>,
        );
      } catch (e) {
        debugPrint('Restore concept_blueprint_json error: $e');
      }
    }

    // Restore Release Blueprint
    final rawRelBp = proj.sections['release_blueprint_json'];
    if (rawRelBp != null && rawRelBp.isNotEmpty) {
      try {
        _releaseBlueprint = ReleaseBlueprint.fromJson(
          jsonDecode(rawRelBp) as Map<String, dynamic>,
        );
      } catch (e) {
        debugPrint('Restore release_blueprint_json error: $e');
      }
    } else {
      _releaseBlueprint = null;
    }

    // Restore active release, beat, and feature
    final savedRelId = proj.sections['active_release_id'];
    if (savedRelId != null && documents.containsKey(savedRelId)) {
      _activeReleaseId = savedRelId;
    } else if (proj.childrenIds.isNotEmpty) {
      _activeReleaseId = proj.childrenIds.first;
    } else {
      _activeReleaseId = null;
    }

    final beats = activeReleaseBeats;
    if (beats.isNotEmpty) {
      final candidateFeatId = (projectId == _activeProjectId &&
              _selectedFeatureId != null &&
              documents.containsKey(_selectedFeatureId))
          ? _selectedFeatureId
          : proj.sections['selected_feature_id'];
      TierDocument? matchedBeat;
      TierDocument? matchedFeat;
      if (candidateFeatId != null) {
        for (final b in beats) {
          for (final f in featuresForBeat(b.id)) {
            if (f.id == candidateFeatId) {
              matchedBeat = b;
              matchedFeat = f;
              break;
            }
          }
          if (matchedFeat != null) break;
        }
      }
      if (matchedBeat != null && matchedFeat != null) {
        _selectedBeatId = matchedBeat.id;
        _selectedFeatureId = matchedFeat.id;
      } else {
        _selectedBeatId = beats.first.id;
        final feats = featuresForBeat(_selectedBeatId!);
        _selectedFeatureId = feats.isNotEmpty ? feats.first.id : null;
      }
    } else {
      _selectedBeatId = null;
      _selectedFeatureId = null;
    }

    // Restore Stage
    final savedStage = proj.sections['current_stage'];
    if (savedStage == WorkbenchStage.releaseWorkbench.name && beats.isNotEmpty) {
      _currentStage = WorkbenchStage.releaseWorkbench;
    } else if (savedStage == WorkbenchStage.releasePlanGate.name &&
        _releaseBlueprint != null) {
      _currentStage = WorkbenchStage.releasePlanGate;
    } else {
      _currentStage = WorkbenchStage.projectPitch;
    }
  }

  final Map<String, Timer> _persistTimers = {};

  void _persistDocument(TierDocument doc, {bool debounce = false}) {
    _persistTimers.remove(doc.id)?.cancel();
    void writeNow() {
      LocalVaultService.saveDocument(doc);
      final user = _authService.currentUser;
      if (user != null) {
        _firestoreService.saveDocument(uid: user.uid, doc: doc);
      }
    }

    if (debounce && enableAutoLoad) {
      _persistTimers[doc.id] = Timer(const Duration(milliseconds: 250), () {
        _persistTimers.remove(doc.id);
        writeNow();
      });
    } else {
      writeNow();
    }
  }

  void _persistSettings() {
    final activeId = _activeProjectId ?? 'proj_main';
    LocalVaultService.saveSettings(
      activeDocumentId: activeId,
      apiKey: _apiKey,
      modelName: _conversationModel,
      thinkingLevel: _thinkingLevel,
      themeMode: _isDark ? 'dark' : 'light',
    );
    final user = _authService.currentUser;
    if (user != null) {
      _firestoreService.saveSettings(
        uid: user.uid,
        settings: {
          'activeDocumentId': activeId,
          'themeMode': _isDark ? 'dark' : 'light',
        },
      );
    }
  }

  void _syncActiveProjectMetadata() {
    final proj = activeProject;
    if (proj == null) return;
    proj.sections['current_stage'] = _currentStage.name;
    if (_activeReleaseId != null) {
      proj.sections['active_release_id'] = _activeReleaseId!;
    }
    if (_selectedBeatId != null) {
      proj.sections['selected_beat_id'] = _selectedBeatId!;
    }
    if (_selectedFeatureId != null) {
      proj.sections['selected_feature_id'] = _selectedFeatureId!;
    }
    if (_conceptDraft != null) {
      proj.sections['concept_blueprint_json'] =
          jsonEncode(_conceptDraft!.toJson());
    }
    if (_releaseBlueprint != null) {
      proj.sections['release_blueprint_json'] =
          jsonEncode(_releaseBlueprint!.toJson());
    }
    _persistDocument(proj);
    _persistSettings();
  }

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
    _persistSettings();
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

  AgentRunTrace? _lastAgentTrace;
  AgentRunTrace? get lastAgentTrace => _lastAgentTrace;

  final List<AgentRunTrace> _agentTraceHistory = [];
  List<AgentRunTrace> get agentTraceHistory =>
      List.unmodifiable(_agentTraceHistory);

  final List<Map<String, dynamic>> _agentUndoStack = [];
  bool get canUndoLastAgentAction => _agentUndoStack.isNotEmpty;

  bool _jumpToFullReviewPending = false;
  bool get jumpToFullReviewPending => _jumpToFullReviewPending;

  void consumeJumpToFullReviewPending() {
    _jumpToFullReviewPending = false;
  }

  void _recordAgentTrace(AgentRunTrace trace) {
    _lastAgentTrace = trace;
    _agentTraceHistory.insert(0, trace);
    if (_agentTraceHistory.length > 25) {
      _agentTraceHistory.removeLast();
    }
  }

  void _pushAgentUndoSnapshot() {
    final docSnapshots = <String, String>{};
    for (final entry in documents.entries) {
      docSnapshots[entry.key] = jsonEncode(entry.value.toJson());
    }
    _agentUndoStack.add({
      'conceptJson':
          _conceptDraft != null ? jsonEncode(_conceptDraft!.toJson()) : null,
      'releaseBpJson': _releaseBlueprint != null
          ? jsonEncode(_releaseBlueprint!.toJson())
          : null,
      'docs': docSnapshots,
    });
    if (_agentUndoStack.length > 15) {
      _agentUndoStack.removeAt(0);
    }
  }

  /// Option 4: 1-Click Undo / Revert of the most recent Agent tool mutation.
  bool undoLastAgentAction() {
    if (_agentUndoStack.isEmpty) return false;
    final snap = _agentUndoStack.removeLast();
    final rawConcept = snap['conceptJson'] as String?;
    if (rawConcept != null) {
      _conceptDraft = ProjectConceptBlueprint.fromJson(
        jsonDecode(rawConcept) as Map<String, dynamic>,
      );
    }
    final rawRelBp = snap['releaseBpJson'] as String?;
    if (rawRelBp != null) {
      _releaseBlueprint = ReleaseBlueprint.fromJson(
        jsonDecode(rawRelBp) as Map<String, dynamic>,
      );
    }
    final rawDocs = snap['docs'] as Map<String, String>?;
    if (rawDocs != null) {
      documents.clear();
      for (final entry in rawDocs.entries) {
        final d = TierDocument.fromJson(
          jsonDecode(entry.value) as Map<String, dynamic>,
        );
        documents[entry.key] = d;
        _persistDocument(d);
      }
    }
    if (_agentTraceHistory.isNotEmpty) {
      _agentTraceHistory.removeAt(0);
    }
    _lastAgentTrace =
        _agentTraceHistory.isNotEmpty ? _agentTraceHistory.first : null;
    _syncActiveProjectMetadata();
    notifyListeners();
    return true;
  }

  /// Option 5: Imports an unstructured GDD, Notion note, or README document on Stage 1A,
  /// extracts all 9 Concept sections, and jumps straight to `Step 10 · Full Review`.
  Future<void> importExistingGddAndJumpToReview(String rawGdd) async {
    final clean = rawGdd.trim();
    if (clean.isEmpty) return;

    _pushAgentUndoSnapshot();
    _isAgentBusy = true;
    _agentProgressStep =
        'Extracting 9-section Concept Blueprint from GDD ($_conversationModel · ${_thinkingLevel.toLowerCase()})...';
    notifyListeners();

    try {
      _conceptDraft = await ProjectConceptAgent.extractConceptFromGdd(
        clean,
        apiKey: _apiKey,
        modelName: _conversationModel,
        thinkingLevel: _thinkingLevel,
      );
      if (_conceptDraft != null) {
        _commitConceptToVault(_conceptDraft!);
        _jumpToFullReviewPending = true;
        _recordAgentTrace(
          AgentRunTrace(
            agentRole: 'GDD Ingestion & Extraction Agent',
            userGoal: 'Import Existing GDD / Notes (${clean.length} chars)',
            reasoning:
                'Parsed "${_conceptDraft!.title}" into all 9 Concept sections (${_conceptDraft!.coreLoopBeats.length} Beats, ${_conceptDraft!.designPillars.length} Pillars, ${_conceptDraft!.exclusions.length} Exclusions) and jumped to Step 10 Full Review.',
            toolCalls: [
              AgentToolCall(
                toolName: 'extract_concept_from_gdd',
                targetTitle: _conceptDraft!.title,
                summary:
                    'Populated Sections 01–09 and opened Step 10 · Full Review',
              ),
            ],
          ),
        );
      }
    } finally {
      _isAgentBusy = false;
      _agentProgressStep = null;
      notifyListeners();
    }
  }

  /// Option 4: Executes a natural-language command from the Global Top-Bar Agent Command Palette
  /// in whichever stage (`Stage 1`, `Stage 2`, or `Stage 3`) is currently active.
  Future<String> runGlobalAgentCommand(String command) async {
    final clean = command.trim();
    if (clean.isEmpty) return 'No command entered.';

    if (_currentStage == WorkbenchStage.releaseWorkbench &&
        selectedFeature != null) {
      final feat = selectedFeature!;
      final states = FeatureStateNode.getStatesForDocument(feat);
      final trace = await runStage3AgentCoPilot(
        featureDoc: feat,
        states: states,
        activeCheckpointIndex: 0,
        directive: clean,
      );
      return trace.toolCalls.isNotEmpty
          ? trace.toolCalls.first.summary
          : trace.reasoning;
    } else if (_currentStage == WorkbenchStage.releasePlanGate &&
        _releaseBlueprint != null) {
      _pushAgentUndoSnapshot();
      await sendReleasePlanChatMessage(clean);
      _recordAgentTrace(
        AgentRunTrace(
          agentRole: 'Stage 2 Release Planner Agent',
          userGoal: clean,
          reasoning:
              'Applied global command "$clean" to ${_releaseBlueprint!.releaseTitle}.',
          toolCalls: [
            AgentToolCall(
              toolName: 'refine_release_blueprint',
              targetTitle: _releaseBlueprint!.releaseVersionTag,
              summary: 'Refined Release Blueprint via Global Command Palette',
            ),
          ],
        ),
      );
      return 'Updated ${_releaseBlueprint!.releaseTitle} ✓';
    } else {
      _pushAgentUndoSnapshot();
      await sendConceptChatMessage(clean);
      final title = _conceptDraft?.title ?? 'Project Concept';
      _recordAgentTrace(
        AgentRunTrace(
          agentRole: 'Stage 1 Concept Co-Design Agent',
          userGoal: clean,
          reasoning: 'Applied global command "$clean" to $title.',
          toolCalls: [
            AgentToolCall(
              toolName: 'update_concept_blueprint',
              targetTitle: title,
              summary: 'Updated Concept Blueprint via Global Command Palette',
            ),
          ],
        ),
      );
      return 'Updated $title ✓';
    }
  }

  void clearLastAgentTrace() {
    _lastAgentTrace = null;
    notifyListeners();
  }

  /// 0-Token Autonomous Concept Critic Interventions for Stage 1 (`ProjectConceptBlueprint`).
  List<AgentIntervention> get stage1Interventions {
    final draft = _conceptDraft;
    if (draft == null) return const [];
    return WorkspaceAgentOrchestrator.auditConceptBlueprint(draft);
  }

  /// 0-Token Autonomous Producer Scope-Guard Interventions for Stage 2 (`Release Plan Gate`).
  List<AgentIntervention> get stage2Interventions {
    final bp = _releaseBlueprint;
    if (bp == null) return const [];
    return WorkspaceAgentOrchestrator.auditReleaseBlueprint(
      blueprint: bp,
      concept: _conceptDraft,
    );
  }

  /// 0-Token Autonomous Producer & Engine Architect Interventions for Stage 3 (`Active Release Workbench`).
  List<AgentIntervention> stage3InterventionsForFeature(
    TierDocument featureDoc,
    List<FeatureStateNode> states,
    int activeCheckpointIndex,
  ) {
    return WorkspaceAgentOrchestrator.auditStage3Feature(
      featureDoc: featureDoc,
      states: states,
      activeCheckpointIndex: activeCheckpointIndex,
    );
  }

  /// Executes a 1-click `[Let Agent Fix ✦]` intervention from the Autonomous Producer / Engine Architect.
  Future<void> applyAgentIntervention(
    AgentIntervention intervention, {
    List<FeatureStateNode>? stage3States,
  }) async {
    _pushAgentUndoSnapshot();
    final bp = _releaseBlueprint;
    final payload = intervention.payload;

    switch (intervention.toolName) {
      case 'resolve_stage1_netcode_conflict':
        if (_conceptDraft != null) {
          _conceptDraft!.gameSpec = _conceptDraft!.gameSpec
              .map(
                (s) => (s.toLowerCase().contains('online') ||
                        s.toLowerCase().contains('multiplayer'))
                    ? 'Singleplayer (Local Shared-Screen Optional)'
                    : s,
              )
              .toList();
          _commitConceptToVault(_conceptDraft!);
          _recordAgentTrace(AgentRunTrace(
            agentRole: 'Stage 1 Concept Critic',
            userGoal: intervention.title,
            reasoning: intervention.reason,
            toolCalls: const [
              AgentToolCall(
                toolName: 'resolve_stage1_netcode_conflict',
                targetTitle: '02 · Game Spec',
                summary: 'Aligned Game Spec to Singleplayer to match Offline-Only Tech Spec',
              ),
            ],
          ));
          notifyListeners();
        }
        return;

      case 'resolve_stage1_dimension_conflict':
        if (_conceptDraft != null) {
          _conceptDraft!.techSpec = _conceptDraft!.techSpec
              .map((s) => s.replaceAll('2D', '3D'))
              .toList();
          _commitConceptToVault(_conceptDraft!);
          _recordAgentTrace(AgentRunTrace(
            agentRole: 'Stage 1 Concept Critic',
            userGoal: intervention.title,
            reasoning: intervention.reason,
            toolCalls: const [
              AgentToolCall(
                toolName: 'resolve_stage1_dimension_conflict',
                targetTitle: '03 · Tech Spec',
                summary: 'Aligned Tech Spec renderer & engine pipeline to 3D',
              ),
            ],
          ));
          notifyListeners();
        }
        return;

      case 'append_stage1_loop_reset_beat':
        if (_conceptDraft != null) {
          _conceptDraft!.coreLoopBeats = [
            ..._conceptDraft!.coreLoopBeats,
            'Run Summary & Loop Reset: tally run rewards and reset cleanly to the starting stage in 1 key press',
          ];
          _commitConceptToVault(_conceptDraft!);
          _recordAgentTrace(AgentRunTrace(
            agentRole: 'Stage 1 Concept Critic',
            userGoal: intervention.title,
            reasoning: intervention.reason,
            toolCalls: const [
              AgentToolCall(
                toolName: 'append_stage1_loop_reset_beat',
                targetTitle: '06 · Core Loop',
                summary: 'Appended "Run Summary & Loop Reset" beat to close the core loop',
              ),
            ],
          ));
          notifyListeners();
        }
        return;

      case 'populate_stage1_exclusions':
        if (_conceptDraft != null) {
          final updated = List<String>.from(_conceptDraft!.exclusions);
          for (final ex in const [
            'No online multiplayer or matchmaking in v0.1',
            'No procedural world generation or cutscene cinematics in v0.1',
          ]) {
            if (!updated.contains(ex)) updated.add(ex);
          }
          _conceptDraft!.exclusions = updated;
          _commitConceptToVault(_conceptDraft!);
          _recordAgentTrace(AgentRunTrace(
            agentRole: 'Stage 1 Concept Critic',
            userGoal: intervention.title,
            reasoning: intervention.reason,
            toolCalls: const [
              AgentToolCall(
                toolName: 'populate_stage1_exclusions',
                targetTitle: '07 · Out of Scope',
                summary: 'Added 2 explicit v0.1 Out-of-Scope guardrails',
              ),
            ],
          ));
          notifyListeners();
        }
        return;

      case 'defer_conflicting_feature':
        final beatId = payload['beatId']?.toString() ?? '';
        final featId = payload['featureId']?.toString() ?? '';
        final featTitle = payload['featureTitle']?.toString() ?? 'Feature';
        toggleProposedFeatureScope(beatId, featId, false);
        _recordAgentTrace(AgentRunTrace(
          agentRole: 'Producer Scope Guard',
          userGoal: intervention.title,
          reasoning: intervention.reason,
          toolCalls: [
            AgentToolCall(
              toolName: 'defer_conflicting_feature',
              targetTitle: featTitle,
              summary: 'Deferred "$featTitle" to Out of Scope to protect ${bp?.releaseVersionTag ?? "v0.1"} boundaries',
            ),
          ],
        ));
        notifyListeners();
        return;

      case 'trim_oversized_feature':
        final beatId = payload['beatId']?.toString() ?? '';
        final featId = payload['featureId']?.toString() ?? '';
        final featTitle = payload['featureTitle']?.toString() ?? 'Feature';
        if (bp != null) {
          for (final beat in bp.beats) {
            if (beat.id == beatId) {
              for (final feat in beat.features) {
                if (feat.id == featId) {
                  feat.estimatedHours = 5;
                  if (feat.checkpoints.length > 2) {
                    feat.checkpoints = feat.checkpoints.take(2).toList();
                  }
                  break;
                }
              }
            }
          }
          _recordAgentTrace(AgentRunTrace(
            agentRole: 'Producer Scope Guard',
            userGoal: intervention.title,
            reasoning:
                'Trimmed "$featTitle" to a 5h greybox core so playtesting is never blocked by a >8h ticket.',
            toolCalls: [
              AgentToolCall(
                toolName: 'trim_oversized_feature',
                targetTitle: featTitle,
                summary: 'Capped "$featTitle" at 5h and focused on 2 core playable checkpoints',
              ),
            ],
          ));
          _syncActiveProjectMetadata();
          notifyListeners();
        }
        return;

      case 'auto_prune_milestone_scope':
        if (bp != null) {
          final deferredTitles = <String>[];
          for (final beat in bp.beats) {
            if (beat.includedFeatures.length > 1) {
              final candidate = beat.includedFeatures.last;
              candidate.included = false;
              deferredTitles.add(candidate.title);
            }
          }
          _recordAgentTrace(AgentRunTrace(
            agentRole: 'Producer Scope Guard',
            userGoal: intervention.title,
            reasoning:
                'Auto-deferred secondary features (${deferredTitles.join(", ")}) to bring ${bp.releaseVersionTag} within budget.',
            toolCalls: [
              for (final t in deferredTitles)
                AgentToolCall(
                  toolName: 'defer_secondary_feature',
                  targetTitle: t,
                  summary: 'Deferred "$t" to Out of Scope',
                ),
            ],
          ));
          _syncActiveProjectMetadata();
          notifyListeners();
        }
        return;

      case 'split_overloaded_checkpoint':
        final featId = payload['featureId']?.toString() ?? _selectedFeatureId ?? '';
        final cpIdx = (payload['checkpointIndex'] as int?) ?? 0;
        final featDoc = documents[featId];
        if (featDoc != null && stage3States != null && cpIdx < stage3States.length) {
          final heavyCp = stage3States[cpIdx];
          if (heavyCp.checklist.length > 3) {
            final overflowTasks = heavyCp.checklist.sublist(3);
            heavyCp.checklist = heavyCp.checklist.sublist(0, 3);
            final splitCp = FeatureStateNode(
              id: generateUniqueId('cp_split'),
              name: 'Stage ${stage3States.length + 1}: ${heavyCp.cleanStageTitle} (Part 2)',
              trigger: heavyCp.trigger,
              parameters: Map<String, String>.from(heavyCp.parameters),
              tuningParams: List<String>.from(heavyCp.tuningParams),
              edgeCases: List<String>.from(heavyCp.edgeCases),
              checklist: overflowTasks,
            );
            stage3States.insert(cpIdx + 1, splitCp);
            updateFeatureStates(featId, stage3States);
            _recordAgentTrace(AgentRunTrace(
              agentRole: 'Producer Scope Guard',
              userGoal: intervention.title,
              reasoning:
                  'Split overloaded Checkpoint ${cpIdx + 1} into two focused 60/40 Playable Checkpoints.',
              toolCalls: [
                AgentToolCall(
                  toolName: 'split_overloaded_checkpoint',
                  targetTitle: featDoc.title,
                  summary: 'Moved ${overflowTasks.length} tasks into ${splitCp.name}',
                ),
              ],
            ));
          }
        }
        return;

      case 'rebalance_tuning_params':
      case 'add_edge_case_guards':
      default:
        final featId = payload['featureId']?.toString() ?? _selectedFeatureId ?? '';
        final cpIdx = (payload['checkpointIndex'] as int?) ?? 0;
        final featDoc = documents[featId];
        if (featDoc != null && stage3States != null) {
          await runStage3AgentCoPilot(
            featureDoc: featDoc,
            states: stage3States,
            activeCheckpointIndex: cpIdx,
            directive: intervention.toolName == 'rebalance_tuning_params'
                ? 'suggest_tuning'
                : 'add_edge_guards',
          );
        }
        return;
    }
  }

  /// Runs the Stage 3 Agentic Co-Pilot (`[ASK AGENT]` bar & Co-Pilot Cards) using
  /// low-token surgical Workspace Tool Calls (`WorkspaceAgentOrchestrator.runStage3CoPilotTools`).
  Future<AgentRunTrace> runStage3AgentCoPilot({
    required TierDocument featureDoc,
    required List<FeatureStateNode> states,
    required int activeCheckpointIndex,
    required String directive,
  }) async {
    _pushAgentUndoSnapshot();
    final engineHint = _conceptDraft?.techSpec.join(' ') ??
        activeProject?.sections['tech_spec'];
    final engineLabel = TaskHowToBlueprint.detectEngineLabel(engineHint);
    final releaseVer = activeRelease?.sections['versionTag'] ?? 'v0.1';
    final allReleaseFeats = <TierDocument>[
      for (final b in activeReleaseBeats) ...featuresForBeat(b.id),
    ];

    final trace = await WorkspaceAgentOrchestrator.runStage3CoPilotTools(
      userDirective: directive,
      activeFeature: featureDoc,
      activeStates: states,
      activeCheckpointIndex: activeCheckpointIndex,
      siblingFeatures: allReleaseFeats,
      engineLabel: engineLabel,
      releaseVersionTag: releaseVer,
      onSaveStates: (featId, updatedStates) {
        updateFeatureStates(featId, updatedStates);
      },
      apiKey: _apiKey,
      modelName: _conversationModel,
      thinkingLevel: _thinkingLevel,
    );

    _recordAgentTrace(trace);
    notifyListeners();
    return trace;
  }

  final Map<String, int> _sectionOptionRefreshOffsets = {};

  /// Option 2: Regenerates the 3 Option Playing Cards for a specific Stage 1 section (`01`..`09`).
  void regenerateStage1SectionOptions(String optionKey) {
    final draft = _conceptDraft;
    if (draft == null) return;
    _pushAgentUndoSnapshot();
    final offset = (_sectionOptionRefreshOffsets[optionKey] ?? 0) + 1;
    _sectionOptionRefreshOffsets[optionKey] = offset;
    final title = draft.title;

    List<String> fresh;
    switch (optionKey) {
      case 'goal':
        fresh = [
          'Speed & Precision Core ($offset): Build a responsive $title greybox loop focused on sub-second movement recovery.',
          'High-Tension Risk/Reward ($offset): Build a compact $title arena where aggressive positioning multiplies score.',
          'Tactile Sandbox Toy ($offset): Build a physics-driven $title testbed where core controls feel fun before adding enemies.',
        ];
        break;
      case 'gameSpec':
        fresh = [
          '2D Side-Scroller · Gamepad + Keyboard · Singleplayer · Tight Room-to-Room Stages',
          '3D Third-Person Action · Mouse + WASD · Singleplayer · Modular Arena Waves',
          '2D Isometric Top-Down · Twin-Stick Aim · Singleplayer · Compact Extraction Map',
        ];
        break;
      case 'techSpec':
        fresh = [
          'Godot 4 (2D/3D) · PC Desktop · Greybox Primitives + Particles · Local JSON Save',
          'Unity 6 (C#) · PC & Steam Deck · Stylized Low-Poly + VFX Graph · Local Binary Save',
          'Unreal Engine 5 · PC Desktop · Unlit Prototype Materials · Local SaveSlot',
        ];
        break;
      case 'designPillars':
        fresh = [
          'Aggression Is Recovery: Attacking or dashing forward is the fastest way to recover from a mistake · Readable Chaos: Every hazard telegraph is clear at a glance · Zero Dead Time: Restarting a run takes under 1 second',
          'Momentum Is Currency: Speed unlocks stronger moves and shortcuts · Tactile Impact: Every hit lands with crisp frame-freeze and audio punch · Learn by Doing: Mechanics teach themselves without text popups',
          'High-Stakes Positioning: Where you stand matters more than button mashing · Expressive Mastery: Simple inputs combine into high-ceiling movement tricks · Instant Feedback: Every action visibly changes the arena state',
        ];
        break;
      case 'tradeOffs':
        fresh = [
          'Snappy 1-frame input cancel over long realistic animation windups · Single-screen clarity over sprawling multi-zone maps in v0.1 · Hardcoded tuning constants over complex data tables',
          'Deterministic arcade physics over unpredictable ragdoll simulation · Fast greybox blockouts over final environment art in v0.1 · Instant restart loop over persistent save trees',
          'Deep core movement verb over having 10 shallow weapon types · Clear silhouette contrast over heavy post-processing shaders · Tight 3-minute run loop over marathon sessions',
        ];
        break;
      case 'coreLoop':
        fresh = [
          'Loadout Select: Pick primary movement rig in staging room · Arena Drop: Enter active hazard zone · High-Speed Objective: Clear 3 targets before timer expires · Extraction & Reset: Bank score and restart in 1 key press',
          'Scout & Aim: Survey obstacle layout from launch pad · Chain Movement: Grapple and vault across hazard gaps · Combat Burst: Defeat elite blocker to unlock exit · Upgrade & Loop: Pick 1 modifier and start next wave',
          'Warmup Room: Test controls in safe hub · Wave Escalation: Survive 3 escalating 45-second waves · Boss/Climax Check: Break core shield under pressure · Run Summary & Reset: Review best time and loop immediately',
        ];
        break;
      case 'exclusions':
        fresh = [
          'No online multiplayer or leaderboards in v0.1 · No branching dialogue or story cutscenes in v0.1 · No crafting or inventory weight menus in v0.1',
          'No procedural biome generation in v0.1 · No skill trees with >3 nodes in v0.1 · No custom shader pipelines before core loop sign-off',
          'No save-file migration or cloud profiles in v0.1 · No companion AI party members in v0.1 · No multi-floor minimap UI in v0.1',
        ];
        break;
      case 'doneWhen':
        fresh = [
          'A playtester completes 3 consecutive $title runs in under 5 minutes with zero physics clipping or state softlocks.',
          'A new player understands the primary $title control loop within 30 seconds without verbal instructions and asks for another run.',
          'All core loop beats transition cleanly at 60 FPS and resetting the arena restores 100% of dynamic objects.',
        ];
        break;
      case 'releaseTrain':
      default:
        fresh = [
          'v0.1: Greybox Core Controls & Loop Reset - Prototype · v0.2: Hazard Escalation & Combat Feel - MVP · v0.3: Gold Standard Vertical Slice Arena - Vertical Slice',
          'v0.1: Primary Mechanic & Physics Toy - Prototype · v0.2: Full 3-Beat Run Loop & Scoring - MVP · v0.3: Polished Audio/VFX Vertical Slice - Vertical Slice',
          'v0.1: Single-Room Core Loop Testbed - Prototype · v0.2: Enemy Archetypes & Upgrade Beat - MVP · v1.0: Launch Content & Balance Pass - Standard',
        ];
        break;
    }

    // Rotate list by offset so each click surfaces a new top recommendation
    final rotated = <String>[
      for (int i = 0; i < fresh.length; i++) fresh[(i + offset) % fresh.length],
    ];
    draft.sectionOptions[optionKey] = rotated;
    _commitConceptToVault(draft);
    _recordAgentTrace(AgentRunTrace(
      agentRole: 'Stage 1 Co-Design Agent',
      userGoal: 'Refresh options for $optionKey',
      reasoning:
          'Synthesized 3 fresh option cards tailored to $title ($optionKey variant #$offset).',
      toolCalls: [
        AgentToolCall(
          toolName: 'regenerate_section_options',
          targetTitle: 'Stage 1 · $optionKey',
          summary: 'Generated 3 fresh Option Playing Cards for $optionKey',
        ),
      ],
    ));
    notifyListeners();
  }

  /// Option 1: Generates a complete Starter Script Bundle (`.gd`, `.cs`, or `.cpp`) for a Stage 3 Feature.
  FeatureScriptBundle generateStarterScriptForFeature(
    TierDocument featureDoc,
    List<FeatureStateNode> states,
  ) {
    final engineHint = _conceptDraft?.techSpec.join(' ') ??
        activeProject?.sections['tech_spec'];
    final engineLabel = TaskHowToBlueprint.detectEngineLabel(engineHint);
    final bundle = WorkspaceAgentOrchestrator.generateFeatureScriptBundle(
      featureDoc: featureDoc,
      states: states,
      engineLabel: engineLabel,
    );
    _recordAgentTrace(AgentRunTrace(
      agentRole: 'Engine Architect Agent',
      userGoal: 'Generate Starter Script for ${featureDoc.title}',
      reasoning:
          'Compiled ${bundle.fileName} ($engineLabel) with ${bundle.exportedVariables.length} exported tuning variables and ${bundle.embeddedGuards.length} embedded guard clauses.',
      toolCalls: [
        AgentToolCall(
          toolName: 'generate_starter_script_bundle',
          targetTitle: bundle.fileName,
          summary: 'Generated ${bundle.fileName} (${bundle.exportedVariables.length} tuning vars, ${states.length} checkpoints)',
        ),
      ],
    ));
    notifyListeners();
    return bundle;
  }

  /// Option 3: Runs the Stage 3 AI Playtest Simulator / Dry-Run Stress Test on a Checkpoint.
  PlaytestSimulationResult simulateCheckpointPlaytest({
    required TierDocument featureDoc,
    required List<FeatureStateNode> states,
    required int checkpointIndex,
  }) {
    _pushAgentUndoSnapshot();
    final engineHint = _conceptDraft?.techSpec.join(' ') ??
        activeProject?.sections['tech_spec'];
    final engineLabel = TaskHowToBlueprint.detectEngineLabel(engineHint);
    final result = WorkspaceAgentOrchestrator.simulateCheckpointPlaytest(
      featureDoc: featureDoc,
      states: states,
      checkpointIndex: checkpointIndex,
      engineLabel: engineLabel,
      onSaveStates: (featId, updatedStates) {
        updateFeatureStates(featId, updatedStates);
      },
    );
    _recordAgentTrace(result.trace);
    notifyListeners();
    return result;
  }

  /// Option 4: Builds a Post-Release Retrospective & Auto-Carryover Summary for the active Release.
  ReleaseRetrospectiveSummary buildActiveReleaseRetrospective() {
    final rel = activeRelease;
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
      final states = FeatureStateNode.getStatesForDocument(f);
      totalCps += states.length;
      bool featHasIncomplete = false;
      bool featWasHardened = false;
      for (final s in states) {
        if (s.isCompleted) {
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
      if (featHasIncomplete) {
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
    _persistSettings();
    notifyListeners();
  }

  void setStage(WorkbenchStage stage) {
    _currentStage = stage;
    _syncActiveProjectMetadata();
    notifyListeners();
  }

  /// Resets the current Concept Blueprint draft so the user returns to Step 1A (`The Spark` Playing Cards).
  void resetConceptToSpark() {
    createNewProject();
  }

  /// Step 1A -> 1B: User accepts their summarized idea (or submits a direct idea) and starts the 9-section Concept Blueprint.
  Future<void> startConceptInterview([String sparkText = '']) async {
    final cleanText = sparkText.trim();
    final effectiveSpark = cleanText.isNotEmpty
        ? cleanText
        : (_sparkIntake?.canonicalPrompt ??
            'High-speed grappling hook parkour roguelite');

    _isAgentBusy = true;
    _agentProgressStep =
        'Drafting initial Concept Blueprint ($_conversationModel · ${_thinkingLevel.toLowerCase()})...';
    notifyListeners();

    try {
      _conceptDraft = await ProjectConceptAgent.startConceptInterview(
        effectiveSpark,
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
      final relId = projId == 'proj_main'
          ? 'rel_v0_${i + 1}'
          : '${projId}_rel_v0_${i + 1}';
      final relTitle = draft.releaseTrainTitles[i];
      final existingRel = documents[relId];

      if (existingRel != null) {
        existingRel.title = relTitle;
        if (existingRel.childrenIds.isEmpty && i == 0) {
          existingRel.sections['releaseScope'] = draft.firstReleasePreset.name;
          existingRel.sections['scope'] =
              'Goal: ${draft.goal}\n\nIn Scope:\n${draft.coreLoopBeats.map((b) => '• $b').join('\n')}\n\nOut of Scope:\n${draft.exclusions.map((e) => '• $e').join('\n')}\n\nDone When: ${draft.doneWhen}';
        }
        _persistDocument(existingRel);
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
      _persistDocument(relDoc);
      releaseIds.add(relId);
    }

    projDoc.childrenIds = releaseIds;
    documents[projId] = projDoc;
    _activeProjectId = projId;
    _activeReleaseId ??= releaseIds.isNotEmpty ? releaseIds.first : null;
    _syncActiveProjectMetadata();
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
      final bp = _releaseBlueprint;
      if (bp != null) {
        final totalFeats = bp.totalIncludedFeatures;
        _recordAgentTrace(AgentRunTrace(
          agentRole: '3-Agent Release Pipeline',
          userGoal: 'Plan ${bp.releaseTitle}',
          reasoning:
              'Systems Designer drafted ${bp.beats.length} Beats ($totalFeats Features) → Producer Scope Critic checked ${bp.explicitExclusions.length} exclusions → Engine Architect bound tuning & guards.',
          toolCalls: [
            AgentToolCall(
              toolName: 'draft_release_beats',
              targetTitle: bp.releaseVersionTag,
              summary: 'Generated ${bp.beats.length} Core Loop Beats & $totalFeats Playable Features (${bp.totalIncludedHours}h)',
            ),
            AgentToolCall(
              toolName: 'audit_scope_exclusions',
              targetTitle: 'Producer Scope Guard',
              summary: 'Verified against ${bp.explicitExclusions.length} Out-of-Scope boundaries',
            ),
            AgentToolCall(
              toolName: 'bind_engine_tuning_and_guards',
              targetTitle: 'Engine Architect',
              summary: 'Injected 60/40 Checkpoints, numeric tuning variables, and [GUARD] rules',
            ),
          ],
        ));
      }
      _currentStage = WorkbenchStage.releasePlanGate;
      _syncActiveProjectMetadata();
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
      _syncActiveProjectMetadata();
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
            _syncActiveProjectMetadata();
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
        _syncActiveProjectMetadata();
        notifyListeners();
        return;
      }
    }
  }

  /// Selects or unselects a Stage 2 Release Question Playing Card option and live-syncs
  /// the Release Blueprint's `doneWhen` and optional deferred feature scope immediately.
  /// Clicking an already-selected option card unselects it and restores the initial default.
  void selectReleaseQuestionOption(String questionId, String optionText) {
    final bp = _releaseBlueprint;
    if (bp == null) return;
    for (final q in bp.questions) {
      if (q.id == questionId) {
        final isUnselect = q.selectedOption == optionText;
        if (isUnselect) {
          q.selectedOption = '';
          if (questionId.contains('feel') || q == bp.questions.first) {
            final projTitle = activeProject?.title ?? bp.releaseTitle;
            bp.doneWhen =
                'A playtester can complete the full $projTitle core loop cycle and reset cleanly 3 times in a row.';
          } else if (questionId.contains('scope')) {
            for (final b in bp.beats) {
              for (final f in b.features) {
                if (!f.isSuperseded) {
                  f.included = !f.title.toLowerCase().contains('bonus');
                }
              }
            }
          }
          _syncActiveProjectMetadata();
          notifyListeners();
          return;
        }

        q.selectedOption = optionText;
        final clean = optionText
            .replaceFirst(RegExp(r'^\(Recommended\)\s*', caseSensitive: false), '')
            .trim();
        final colonIdx = clean.indexOf(':');
        final summary = (colonIdx > 0 && colonIdx < clean.length - 1)
            ? clean.substring(colonIdx + 1).trim()
            : clean;

        if (questionId.contains('feel') || q == bp.questions.first) {
          bp.doneWhen =
              'A playtester can complete the full ${bp.releaseVersionTag} core loop cycle 3 times in a row — prioritizing: $summary.';
        } else if (questionId.contains('scope')) {
          final lower = clean.toLowerCase();
          if (lower.contains('expanded')) {
            for (final b in bp.beats) {
              for (final f in b.features) {
                if (!f.isSuperseded) f.included = true;
              }
            }
          } else if (lower.contains('lean')) {
            for (final b in bp.beats) {
              for (final f in b.features) {
                if (f.title.toLowerCase().contains('bonus')) {
                  f.included = false;
                }
              }
            }
          }
        }
        _syncActiveProjectMetadata();
        notifyListeners();
        return;
      }
    }
  }

  /// Adds a custom Playable Feature directly into a Beat in Stage 2 with mechanic-specific
  /// Checkpoints, Tuning Variables, and Edge-Case Guards synthesized via [MechanicArchetypeProfile].
  void addProposedFeatureToBeat(String beatId, String rawTitle) {
    final bp = _releaseBlueprint;
    final cleanTitle = rawTitle.trim();
    if (bp == null || cleanTitle.isEmpty) return;
    _pushAgentUndoSnapshot();

    for (final beat in bp.beats) {
      if (beat.id == beatId) {
        final featId =
            'feat_${beat.id}_${beat.features.length + 1}_${DateTime.now().millisecondsSinceEpoch % 10000}';
        final archetype = MechanicArchetypeProfile.fromFeatureTitle(
          cleanTitle,
          beatTitle: beat.title,
          beatDescription: beat.goal,
        );
        beat.features.add(
          ProposedFeatureBlueprint(
            id: featId,
            title: cleanTitle,
            goal: archetype.goal,
            doneWhen: archetype.doneWhen,
            estimatedHours: 4,
            included: true,
            lifecycle: FeatureLifecycleStatus.newFeature,
            originVersion: bp.releaseVersionTag,
            inScope: archetype.inScope,
            outOfScope: archetype.outOfScope,
            tuningParams: archetype.tuningParams,
            edgeCases: archetype.edgeCases,
            checkpoints: [
              ProposedCheckpointBlueprint(
                title: archetype.cp1Title,
                playtestCriteria: archetype.cp1Playtest,
                tasks: archetype.cp1Tasks,
                coveredScope: [archetype.inScope.first],
                tuningParams: archetype.tuningParams,
                edgeCases: [archetype.edgeCases.first],
                releaseVersion: bp.releaseVersionTag,
              ),
              ProposedCheckpointBlueprint(
                title: archetype.cp2Title,
                playtestCriteria: archetype.cp2Playtest,
                tasks: archetype.cp2Tasks,
                coveredScope: archetype.inScope.length > 1
                    ? [archetype.inScope[1]]
                    : archetype.inScope,
                tuningParams: archetype.tuningParams,
                edgeCases: archetype.edgeCases.length > 1
                    ? [archetype.edgeCases[1]]
                    : archetype.edgeCases,
                releaseVersion: bp.releaseVersionTag,
              ),
            ],
          ),
        );
        _recordAgentTrace(AgentRunTrace(
          agentRole: 'Systems & Engine Architect',
          userGoal: 'Add Feature "$cleanTitle" to ${beat.title}',
          reasoning:
              'Synthesized 2 playable 60/40 Checkpoints, ${archetype.tuningParams.length} numeric tuning variables, and ${archetype.edgeCases.length} [GUARD] rules.',
          toolCalls: [
            AgentToolCall(
              toolName: 'create_feature_blueprint',
              targetTitle: cleanTitle,
              summary: 'Added "$cleanTitle" (4h) with ${archetype.cp1Title} & ${archetype.cp2Title}',
            ),
          ],
        ));
        _syncActiveProjectMetadata();
        notifyListeners();
        return;
      }
    }
  }

  /// Updates a proposed Feature's Title, Hours, Goal, Done When, Checkpoints, or Tuning
  /// parameters inline inside Stage 2 (`Release Plan Gate`).
  void updateProposedFeatureInBeat({
    required String beatId,
    required String featureId,
    String? title,
    String? goal,
    String? doneWhen,
    int? estimatedHours,
    List<ProposedCheckpointBlueprint>? checkpoints,
    List<String>? tuningParams,
    List<String>? edgeCases,
  }) {
    final bp = _releaseBlueprint;
    if (bp == null) return;
    for (final beat in bp.beats) {
      if (beat.id == beatId) {
        for (final feat in beat.features) {
          if (feat.id == featureId) {
            if (title != null && title.trim().isNotEmpty) {
              feat.title = title.trim();
            }
            if (goal != null && goal.trim().isNotEmpty) {
              feat.goal = goal.trim();
            }
            if (doneWhen != null && doneWhen.trim().isNotEmpty) {
              feat.doneWhen = doneWhen.trim();
            }
            if (estimatedHours != null && estimatedHours >= 0) {
              feat.estimatedHours = estimatedHours;
            }
            if (checkpoints != null && checkpoints.isNotEmpty) {
              feat.checkpoints = checkpoints;
            }
            if (tuningParams != null) {
              feat.tuningParams = tuningParams;
            }
            if (edgeCases != null) {
              feat.edgeCases = edgeCases;
            }
            _syncActiveProjectMetadata();
            notifyListeners();
            return;
          }
        }
      }
    }
  }

  /// Removes a proposed Feature card from a Beat in Stage 2 (`Release Plan Gate`).
  void removeProposedFeatureFromBeat(String beatId, String featureId) {
    final bp = _releaseBlueprint;
    if (bp == null) return;
    for (final beat in bp.beats) {
      if (beat.id == beatId) {
        beat.features.removeWhere((f) => f.id == featureId);
        _syncActiveProjectMetadata();
        notifyListeners();
        return;
      }
    }
  }

  /// Logs a Playtest Issue on a Checkpoint in Stage 3 (`Release Workbench`):
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
    _pushAgentUndoSnapshot();
    final cpNode = states[checkpointIndex];
    final newTaskIndex = cpNode.checklist.length;
    final taskNum = newTaskIndex + 1;
    final engineHint = _conceptDraft?.techSpec.join(' ') ??
        activeProject?.sections['tech_spec'];
    final engineLabel = TaskHowToBlueprint.detectEngineLabel(engineHint);
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
              'Trigger "$cleanIssue" in the game viewport and log the live state before applying changes.',
          codeTargetFile: 'custom_snippet',
          codeSnippet: isUnity
              ? '// Debug log state when "$cleanIssue" occurs\nDebug.LogWarning("[PLAYTEST FIX] Issue triggered | Tune: $primaryTune");'
              : (isUnreal
                  ? '// Log state when "$cleanIssue" occurs\nUE_LOG(LogTemp, Warning, TEXT("[PLAYTEST FIX] Issue triggered: %s"), *GetName());'
                  : '# Log state when "$cleanIssue" occurs\nprint("[PLAYTEST FIX] Issue triggered -> ", name, " | Tune: $primaryTune")'),
        ),
        Subtask(
          id: generateUniqueId('fix_sub_2'),
          text: 'STEP $taskNum.2 · APPLY FIX & CLAMP TUNING BOUNDS',
          specNotes:
              'Adjust the update/collision logic and clamp $primaryTune so "$cleanIssue" cannot happen.',
          codeTargetFile: 'custom_snippet',
          codeSnippet: isUnity
              ? '// Clamp and resolve: $cleanIssue\nif (!isValidState) { ResetStateSafely(); return; }'
              : (isUnreal
                  ? '// Clamp and resolve: $cleanIssue\nif (!bIsValidState) { ResetStateSafely(); return; }'
                  : '# Clamp and resolve: $cleanIssue\nif not is_valid_state:\n    reset_state_safely()\n    return'),
        ),
        Subtask(
          id: generateUniqueId('fix_sub_3'),
          text: 'STEP $taskNum.3 · VERIFY PLAYTEST GUARD IN VIEWPORT',
          specNotes:
              'Re-run the checkpoint playtest gate ("${cpNode.playtestCondition}") 3 times to confirm "$cleanIssue" is resolved.',
          codeTargetFile: 'custom_snippet',
          codeSnippet: isUnity
              ? 'Debug.Assert(isValidState, "[PLAYTEST GUARD] $cleanIssue");'
              : (isUnreal
                  ? 'checkf(bIsValidState, TEXT("[PLAYTEST GUARD] $cleanIssue"));'
                  : 'assert(is_valid_state, "[PLAYTEST GUARD] $cleanIssue")'),
        ),
      ],
    );

    cpNode.checklist.add(fixTask);
    final guardText = '[PLAYTEST GUARD] $cleanIssue';
    if (!cpNode.edgeCases.contains(guardText)) {
      cpNode.edgeCases = [...cpNode.edgeCases, guardText];
    }
    final featTitle = documents[featureId]?.title ?? cpNode.cleanStageTitle;
    _recordAgentTrace(AgentRunTrace(
      agentRole: 'Playtest Root-Cause Debugger',
      userGoal: 'Log Issue: $cleanIssue',
      reasoning:
          'Diagnosed "$cleanIssue" in $engineLabel ($primaryTune) and injected a 3-step root-cause fix + [PLAYTEST GUARD].',
      toolCalls: [
        AgentToolCall(
          toolName: 'diagnose_and_fix_playtest_bug',
          targetTitle: '$featTitle · Checkpoint ${checkpointIndex + 1}',
          summary: 'Added [FIX] $cleanIssue (1h) + [PLAYTEST GUARD] boundary rule',
        ),
      ],
    ));
    updateFeatureStates(featureId, states);
    return newTaskIndex;
  }

  /// Tailors the 3 checkable How-To sub-steps (`Step X.1`, `Step X.2`, `Step X.3`) for a specific
  /// Parent Task in Stage 3 using either Gemini AI (`gemini-flash-latest`) or deterministic
  /// Scene/Node context injection when offline.
  Future<void> tailorTaskHowToSubSteps({
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
      return;
    }
    final cpNode = states[checkpointIndex];
    if (taskIndex < 0 || taskIndex >= cpNode.checklist.length) return;
    final parentTask = cpNode.checklist[taskIndex];
    final featDoc = documents[featureId];
    final engineHint = _conceptDraft?.techSpec.join(' ') ??
        activeProject?.sections['tech_spec'];
    final engineLabel = TaskHowToBlueprint.detectEngineLabel(engineHint);
    final taskNum = taskIndex + 1;

    // Ensure children are initialized first
    TaskHowToBlueprint.resolve(
      parentTask: parentTask,
      taskIndex: taskIndex,
      checkpointNode: cpNode,
      engineHint: engineHint,
    );

    if (GeminiAgentClient.hasKey(_apiKey)) {
      final prompt = '''
You are a senior game engine programmer assisting with a concrete implementation task.
Engine: $engineLabel
Feature: "${featDoc?.title ?? cpNode.name}"
Checkpoint: "${cpNode.cleanStageTitle}"
Task ($taskNum): "${parentTask.text}"
Active Tuning Parameters: ${cpNode.tuningParams.join(', ')}
Active Edge-Case Guards: ${cpNode.edgeCases.join(', ')}
Developer's Exact Scene / Node / Script Setup: "$cleanContext"

Rewrite the 3 checkable How-To Sub-Steps (Step $taskNum.1 Setup/Input, Step $taskNum.2 Core Logic with Tuning Variable, Step $taskNum.3 Edge-Case Guard Check) specifically using the developer's node/script names from "$cleanContext".
Return ONLY a JSON object with this exact schema:
{
  "subSteps": [
    {
      "title": "STEP $taskNum.1 · SHORT LITERAL SUB-STEP TITLE",
      "instruction": "1-sentence literal instruction referencing the user's exact nodes/scripts",
      "codeFormula": "2-3 lines of $engineLabel code using the user's node/script names"
    },
    {
      "title": "STEP $taskNum.2 · SHORT LITERAL SUB-STEP TITLE",
      "instruction": "1-sentence literal instruction applying the tuning variable",
      "codeFormula": "2-3 lines of $engineLabel code applying the tuning variable"
    },
    {
      "title": "STEP $taskNum.3 · SHORT LITERAL GUARD TITLE",
      "instruction": "1-sentence literal instruction enforcing the edge-case guard",
      "codeFormula": "1-2 lines of $engineLabel guard check code"
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
        for (int i = 0; i < rawSubs.length && i < parentTask.children.length; i++) {
          final item = rawSubs[i];
          if (item is Map) {
            final t = (item['title'] ?? '').toString().trim();
            final instr = (item['instruction'] ?? '').toString().trim();
            final code = (item['codeFormula'] ?? '').toString().trim();
            if (t.isNotEmpty) parentTask.children[i].text = t;
            if (instr.isNotEmpty) parentTask.children[i].specNotes = instr;
            if (code.isNotEmpty) {
              parentTask.children[i].codeSnippet = code;
              parentTask.children[i].codeTargetFile = 'custom_snippet';
            }
          }
        }
        updateFeatureStates(featureId, states);
        return;
      }
    }

    // Deterministic Scene/Node Context Adapter
    TaskHowToBlueprint.tailorSubStepsForContext(
      parentTask: parentTask,
      taskIndex: taskIndex,
      checkpointNode: cpNode,
      userContext: cleanContext,
      engineHint: engineHint,
    );
    updateFeatureStates(featureId, states);
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
      _syncActiveProjectMetadata();

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
    final proj = activeProject;
    if (proj != null) {
      proj.sections['selected_beat_id'] = beatId;
      if (_selectedFeatureId != null) {
        proj.sections['selected_feature_id'] = _selectedFeatureId!;
      }
      LocalVaultService.saveDocument(proj);
    }
    notifyListeners();
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
      LocalVaultService.saveDocument(proj);
    }
    notifyListeners();
  }

  void updateFeatureStates(String featureId, List<FeatureStateNode> states) {
    final feat = documents[featureId];
    if (feat == null) return;
    FeatureStateNode.saveStatesToDocument(feat, states);
    _persistDocument(feat, debounce: true);
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

  ReleaseRetrospectiveSummary? _lastReleaseRetrospective;
  ReleaseRetrospectiveSummary? get lastReleaseRetrospective =>
      _lastReleaseRetrospective;

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

    _lastReleaseRetrospective = buildActiveReleaseRetrospective();
    final retro = _lastReleaseRetrospective!;

    Future<void> openGateAndRecordRetro(String targetRelId) async {
      await openReleasePlanGate(releaseId: targetRelId);
      if (_releaseBlueprint != null) {
        final carryoverNote = retro.carryoverFeatureTitles.isEmpty
            ? '100% of ${retro.totalCheckpoints} checkpoints verified'
            : 'Carried over ${retro.carryoverFeatureTitles.length} unfinished feature(s) (${retro.carryoverFeatureTitles.join(", ")}) as UPGRADING';
        _recordAgentTrace(AgentRunTrace(
          agentRole: 'Post-Release Retrospective & Carryover Agent',
          userGoal: 'Evolve from ${retro.releaseTitle} to ${_releaseBlueprint!.releaseTitle}',
          reasoning:
              '$carryoverNote · Preserved ${retro.fixTasksTriaged} playtest [FIX] tasks and ${retro.playtestGuardsAdded} [PLAYTEST GUARD] rules in the live tree.',
          toolCalls: [
            AgentToolCall(
              toolName: 'compile_release_retrospective',
              targetTitle: retro.releaseTitle,
              summary:
                  'Verified ${retro.verifiedCheckpoints}/${retro.totalCheckpoints} checkpoints (${retro.fixTasksTriaged} fixes, ${retro.playtestGuardsAdded} guards)',
            ),
            if (retro.carryoverFeatureTitles.isNotEmpty)
              AgentToolCall(
                toolName: 'auto_carryover_incomplete_features',
                targetTitle: _releaseBlueprint!.releaseVersionTag,
                summary:
                    'Carried over ${retro.carryoverFeatureTitles.join(", ")} into ${_releaseBlueprint!.releaseVersionTag}',
              ),
          ],
        ));
        notifyListeners();
      }
    }

    final currentIdx = releases.indexWhere((r) => r.id == _activeReleaseId);
    final nextIdx = currentIdx + 1;
    if (nextIdx < releases.length) {
      await openGateAndRecordRetro(releases[nextIdx].id);
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
        final newRelId = proj.id == 'proj_main'
            ? 'rel_v0_$newIndex'
            : '${proj.id}_rel_v0_$newIndex';
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
      _persistDocument(newRelDoc);
      proj.childrenIds.add(newRelId);
      _syncActiveProjectMetadata();
      await openGateAndRecordRetro(newRelId);
      return;
    }

    // Phase 4: Full Production content drops (reusing the Rough -> Polish pattern)
    _currentPhase = ProductionPhase.fullProduction;
    final newIndex = proj.childrenIds.length + 1;
    final newRelId = proj.id == 'proj_main'
        ? 'rel_v0_$newIndex'
        : '${proj.id}_rel_v0_$newIndex';
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
    _persistDocument(newRelDoc);
    proj.childrenIds.add(newRelId);
    _syncActiveProjectMetadata();
    await openGateAndRecordRetro(newRelId);
  }
}
