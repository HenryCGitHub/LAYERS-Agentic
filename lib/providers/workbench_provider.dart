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

/// Top-level stage in the streamlined 2-stage Antigravity workflow.
enum WorkbenchStage {
  /// Stage 1: Spark -> Concept Blueprint & Release Train
  projectPitch,

  /// Stage 2: Open-Canvas Release Workbench (Epics -> Features -> Steps)
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
          // Skip intermediate snapshot reconciliation while local batch writes or agent operations are in flight
          if (_isAgentBusy || _pendingCloudWriteDocIds.isNotEmpty) return;
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
      if (loaded.modelName != null && loaded.modelName!.trim().isNotEmpty) {
        _conversationModel = loaded.modelName!.trim();
      }
      if (loaded.planningModel != null &&
          loaded.planningModel!.trim().isNotEmpty) {
        _planningModel = loaded.planningModel!.trim();
      }
      if (loaded.thinkingLevel != null &&
          loaded.thinkingLevel!.trim().isNotEmpty) {
        _thinkingLevel = loaded.thinkingLevel!.trim().toUpperCase();
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

  String? _offlineErrorMessage;
  String? get offlineErrorMessage => _offlineErrorMessage;
  bool get isOffline => _offlineErrorMessage != null;

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
    _offlineErrorMessage = null;
    _currentStage = WorkbenchStage.projectPitch;
    notifyListeners();
  }

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
      // Self-heal any cross-Epic duplicate feature ID collisions from prior builds
      final seenFeatIds = <String, String>{}; // featId -> first beatId
      for (int bIdx = 0; bIdx < beats.length; bIdx++) {
        final b = beats[bIdx];
        for (int cIdx = 0; cIdx < b.childrenIds.length; cIdx++) {
          final fid = b.childrenIds[cIdx];
          final firstBeatId = seenFeatIds[fid];
          if (firstBeatId == null) {
            seenFeatIds[fid] = b.id;
          } else if (firstBeatId != b.id) {
            final origDoc = documents[fid];
            if (origDoc != null) {
              final clonedId = 'feat_${b.id}_${cIdx + 1}';
              final distinctTitle =
                  MechanicArchetypeProfile.concreteFeatureTitleForBeat(
                origDoc.title,
                beatTitle: b.title,
                beatGoal: b.sections['scope'] ?? '',
                beatIndex: bIdx,
              );
              final clonedDoc = TierDocument(
                id: clonedId,
                title: distinctTitle,
                tier: TierType.feature,
                parentId: b.id,
                estimatedDuration: origDoc.estimatedDuration,
                sections: Map<String, String>.from(origDoc.sections),
              );
              documents[clonedId] = clonedDoc;
              b.childrenIds[cIdx] = clonedId;
            }
          }
        }
      }

      // Self-heal any v0.1 features that suffered from the duplicate-checkpoint 50% completion bug
      final isInitialV01 = activeReleaseVersionTag == 'v0.1' &&
          (activeRelease?.sections['prototypePart'] ?? '') != '2';
      if (isInitialV01) {
        for (final b in beats) {
          for (final f in featuresForBeat(b.id)) {
            final states = FeatureStateNode.getStatesForDocument(f);
            if (states.length >= 2) {
              final cleanNode = !states.last.isCompleted
                  ? states.last
                  : states.first;
              final cleanedTitle = cleanNode.cleanStageTitle;
              final healedNode = FeatureStateNode(
                id: '${f.id}_v0.1_cp_1',
                name: 'Checkpoint 1: $cleanedTitle',
                trigger: cleanNode.trigger,
                order: 0,
                checklist: cleanNode.checklist,
                coveredScope: cleanNode.coveredScope,
                tuningParams: cleanNode.tuningParams,
                edgeCases: cleanNode.edgeCases,
                parameters: Map<String, String>.from(cleanNode.parameters)
                  ..['releaseVersion'] = 'v0.1',
              );
              FeatureStateNode.saveStatesToDocument(f, [healedNode]);
              _persistDocument(f);
            }
          }
        }
      }

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
        _selectFirstIncompleteFeatureInActiveRelease();
      }
    } else {
      _selectedBeatId = null;
      _selectedFeatureId = null;
    }

    // Restore Stage & Production Phase
    final activeRel = _activeReleaseId != null ? documents[_activeReleaseId] : null;
    _syncCurrentPhaseFromRelease(activeRel);

    final savedStage = proj.sections['current_stage'];
    if ((savedStage == WorkbenchStage.releaseWorkbench.name ||
            savedStage == 'releasePlanGate') &&
        beats.isNotEmpty) {
      _currentStage = WorkbenchStage.releaseWorkbench;
    } else {
      _currentStage = WorkbenchStage.projectPitch;
    }
  }

  void _syncCurrentPhaseFromRelease(TierDocument? relDoc) {
    if (relDoc == null) {
      _currentPhase = ProductionPhase.prototype;
      return;
    }
    final rawPhase = (relDoc.sections['phase'] ?? '').trim();
    if (rawPhase == ProductionPhase.mvp.name) {
      _currentPhase = ProductionPhase.mvp;
    } else if (rawPhase == ProductionPhase.verticalSlice.name) {
      _currentPhase = ProductionPhase.verticalSlice;
    } else if (rawPhase == ProductionPhase.fullProduction.name) {
      _currentPhase = ProductionPhase.fullProduction;
    } else if (rawPhase == ProductionPhase.prototype.name) {
      _currentPhase = ProductionPhase.prototype;
    } else {
      final scope = relDoc.releaseScope;
      if (scope == ReleaseScope.mvp) {
        _currentPhase = ProductionPhase.mvp;
      } else if (scope == ReleaseScope.verticalSlice) {
        _currentPhase = ProductionPhase.verticalSlice;
      } else if (scope == ReleaseScope.fullProduction) {
        _currentPhase = ProductionPhase.fullProduction;
      } else {
        _currentPhase = ProductionPhase.prototype;
      }
    }
  }

  final Map<String, Timer> _persistTimers = {};
  final Set<String> _pendingCloudWriteDocIds = {};

  void _persistDocument(TierDocument doc, {bool debounce = false}) {
    _persistTimers.remove(doc.id)?.cancel();
    void writeNow() {
      LocalVaultService.saveDocument(doc);
      final user = _authService.currentUser;
      if (user != null) {
        _pendingCloudWriteDocIds.add(doc.id);
        _firestoreService.saveDocument(uid: user.uid, doc: doc).whenComplete(() {
          _pendingCloudWriteDocIds.remove(doc.id);
        });
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
      planningModel: _planningModel,
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

  bool _jumpToFullReviewPending = false;
  bool get jumpToFullReviewPending => _jumpToFullReviewPending;

  void consumeJumpToFullReviewPending() {
    _jumpToFullReviewPending = false;
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

  String? get _activeEngineHint =>
      _conceptDraft?.techSpec.join(' ') ?? activeProject?.sections['tech_spec'];

  String get _activeEngineLabel =>
      TaskHowToBlueprint.detectEngineLabel(_activeEngineHint);

  void _selectFirstIncompleteFeatureInActiveRelease() {
    final beats = activeReleaseBeats;
    if (beats.isEmpty) return;
    TierDocument? firstActiveBeat;
    TierDocument? firstActiveFeat;

    // 1st Pass: Prioritize incomplete features with active-release work (`upgrade` or `newFeature`)
    for (final b in beats) {
      for (final f in featuresForBeat(b.id)) {
        final lc = f.sections['lifecycle'] ?? '';
        final isActiveLifecycle = lc == FeatureLifecycleStatus.upgrade.name ||
            lc == FeatureLifecycleStatus.newFeature.name;
        if (isActiveLifecycle && getDocumentProgress(f.id) < 100) {
          firstActiveBeat = b;
          firstActiveFeat = f;
          break;
        }
      }
      if (firstActiveFeat != null) break;
    }

    // 2nd Pass: Fall back to any incomplete feature
    if (firstActiveFeat == null) {
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
    }

    _selectedBeatId = (firstActiveBeat ?? beats.first).id;
    final feats = featuresForBeat(_selectedBeatId!);
    _selectedFeatureId =
        (firstActiveFeat ?? (feats.isNotEmpty ? feats.first : null))?.id;
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

  /// Step 1A -> 1B: User accepts their summarized idea (or submits a direct idea) and starts the 8-section Concept Blueprint.
  /// When [jumpToFullReview] is true, lands directly on Full Concept Review (`09 · Full Concept Review`).
  Future<void> startConceptInterview([
    String sparkText = '',
    bool jumpToFullReview = false,
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
    final trainTitles = draft.releaseTrainTitles.isNotEmpty
        ? draft.releaseTrainTitles
        : <String>[
            'v0.1: ${draft.title.trim().isEmpty ? "Game" : draft.title.trim()} Core Loop - Prototype',
          ];
    final isSplitPrototype = trainTitles.length > 1;
    for (int i = 0; i < trainTitles.length; i++) {
      final relId = projId == 'proj_main'
          ? 'rel_v0_${i + 1}'
          : '${projId}_rel_v0_${i + 1}';
      final relTitle = trainTitles[i];
      final existingRel = documents[relId];

      if (existingRel != null) {
        existingRel.title = relTitle;
        existingRel.sections['phase'] ??= ProductionPhase.prototype.name;
        if (isSplitPrototype) {
          existingRel.sections['prototypePart'] = '${i + 1}';
        } else {
          existingRel.sections.remove('prototypePart');
        }
        if (existingRel.childrenIds.isEmpty) {
          existingRel.sections['releaseScope'] = ReleaseScope.prototype.name;
          if (i == 0) {
            existingRel.sections['scope'] =
                'Goal: ${draft.goal}\n\nIn Scope:\n${draft.coreLoopBeats.map((b) => '• $b').join('\n')}\n\nOut of Scope:\n${draft.exclusions.map((e) => '• $e').join('\n')}\n\nDone When: ${draft.doneWhen}';
          }
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
          'releaseScope': ReleaseScope.prototype.name,
          'phase': ProductionPhase.prototype.name,
          if (isSplitPrototype) 'prototypePart': '${i + 1}',
          'scope': i == 0
              ? 'Goal: ${draft.goal}\n\nIn Scope:\n${draft.coreLoopBeats.map((b) => '• $b').join('\n')}\n\nOut of Scope:\n${draft.exclusions.map((e) => '• $e').join('\n')}\n\nDone When: ${draft.doneWhen}'
              : 'Goal: Complete the remaining Core Loop Epics for the ${draft.title} prototype.\n\nIn Scope:\n• Remaining Core Loop Epics from ${draft.title}\n\nDone When: Full prototype core loop connects end-to-end.',
        },
      );
      documents[relId] = relDoc;
      _persistDocument(relDoc);
      releaseIds.add(relId);
    }

    // Preserve any existing Phase 2 (MVP), Phase 3 (Vertical Slice), or Phase 4 (Full Production)
    // releases—or any subsequent release already built—so revisiting Stage 1 mid-project
    // never detaches unlocked phases.
    if (existingProj != null) {
      for (final existingRelId in existingProj.childrenIds) {
        if (releaseIds.contains(existingRelId)) continue;
        final existingRelDoc = documents[existingRelId];
        if (existingRelDoc == null) continue;
        final relPhase = existingRelDoc.sections['phase'] ?? '';
        final isNonPrototypePhase = relPhase.isNotEmpty &&
            relPhase != ProductionPhase.prototype.name;
        if (isNonPrototypePhase || existingRelDoc.childrenIds.isNotEmpty) {
          releaseIds.add(existingRelId);
        }
      }
    }

    projDoc.childrenIds = releaseIds;
    documents[projId] = projDoc;
    _activeProjectId = projId;
    _activeReleaseId ??= releaseIds.isNotEmpty ? releaseIds.first : null;
    _syncActiveProjectMetadata();
  }

  /// Switches the Stage 2 Workbench in-place to an already-built Release (`rel.childrenIds.isNotEmpty`),
  /// or synthesizes and builds the target Release directly into `2. Workbench` if not built yet.
  Future<void> selectActiveRelease(String releaseId) async {
    final targetRel = documents[releaseId];
    if (targetRel == null) return;
    _syncCurrentPhaseFromRelease(targetRel);
    if (targetRel.childrenIds.isNotEmpty) {
      _activeReleaseId = releaseId;
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
  /// synthesizes the Release Blueprint, and executes it into the active Workbench in one click.
  Future<void> approveConceptAndBuildRelease({String? releaseId}) async {
    if (_conceptDraft != null) {
      _commitConceptToVault(_conceptDraft!);
    }
    _releaseViewFilter = 'active';
    _currentStage = WorkbenchStage.releaseWorkbench;
    notifyListeners();

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

  /// Next progressive version tag (`v0.2`, `v0.3`, etc.) based on how many releases have been built.
  String get nextProgressiveVersionLabel {
    final builtCount = projectReleases.where((r) => r.childrenIds.isNotEmpty).length;
    return 'v0.${builtCount + 1}';
  }

  /// Prepares the next Progressive Release (`v0.2`, `v0.3+`) blueprint in-memory while keeping
  /// the user inside `2. Workbench`, optionally applying a natural-language directive from the
  /// Agentic Next-Release Co-Pilot.
  Future<ReleaseBlueprint?> prepareProgressiveNextReleaseDraft({
    String? agentDirective,
  }) async {
    await advanceToNextRelease(transitionToGateStage: false);
    _currentStage = WorkbenchStage.releaseWorkbench;
    if (agentDirective != null && agentDirective.trim().isNotEmpty) {
      await sendReleasePlanChatMessage(agentDirective.trim());
    }
    notifyListeners();
    return _releaseBlueprint;
  }

  /// Restores the active release and production phase if the user cancels the Progressive Next Release modal.
  void restoreActiveReleaseAfterCancel(
    String? previousReleaseId,
    ProductionPhase previousPhase,
  ) {
    if (previousReleaseId != null && documents.containsKey(previousReleaseId)) {
      _activeReleaseId = previousReleaseId;
    }
    _currentPhase = previousPhase;
    _syncActiveProjectMetadata();
    notifyListeners();
  }

  /// Executes the prepared (or newly synthesized) next Progressive Release (`v0.2`, `v0.3+`)
  /// directly into `2. Workbench`.
  Future<void> buildProgressiveNextRelease({String? agentDirective}) async {
    final currentBp = _releaseBlueprint;
    final activeRel = activeRelease;
    if (currentBp == null ||
        (activeRel != null &&
            currentBp.releaseDocId == activeRel.id &&
            activeRel.childrenIds.isNotEmpty)) {
      await prepareProgressiveNextReleaseDraft(agentDirective: agentDirective);
    } else if (agentDirective != null && agentDirective.trim().isNotEmpty) {
      await sendReleasePlanChatMessage(agentDirective.trim());
    }
    if (_releaseBlueprint != null) {
      await approveAndExecuteReleasePlan();
    }
  }

  /// Synthesizes the Release Blueprint for the active Release.
  Future<void> openReleasePlanGate({
    String? releaseId,
    bool transitionToGateStage = false,
  }) async {
    if (_conceptDraft != null) {
      _commitConceptToVault(_conceptDraft!);
    }

    final proj = activeProject;
    if (proj == null) return;

    final targetRelId = releaseId ??
        _activeReleaseId ??
        (proj.childrenIds.isNotEmpty ? proj.childrenIds.first : null);
    if (targetRelId == null) return;

    // Collect existing live Beats & Features from prior releases (never from targetRelId itself,
    // and never when planning the initial v0.1 release) so v0.1 starts clean at 0% and v0.2+ preserves the single live game tree!
    final isFirstPrototypeRelease =
        proj.childrenIds.isEmpty || proj.childrenIds.first == targetRelId;
    final existingBeats = <TierDocument>[];
    final existingFeaturesByBeat = <String, List<TierDocument>>{};
    if (!isFirstPrototypeRelease) {
      for (final rel in projectReleases) {
        if (rel.id == targetRelId) continue;
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
    }

    // Capture any features deferred (unchecked) in the prior Release Plan Gate
    // so they automatically carry over into the next release's Beat!
    final deferredByBeatIndex = <int, List<ProposedFeatureBlueprint>>{};
    final priorBp = _releaseBlueprint;
    if (priorBp != null) {
      for (int bIdx = 0; bIdx < priorBp.beats.length; bIdx++) {
        final deferredInBeat = priorBp.beats[bIdx].deferredFeatures.toList();
        if (deferredInBeat.isNotEmpty) {
          deferredByBeatIndex[bIdx] = deferredInBeat;
        }
      }
    }

    _activeReleaseId = targetRelId;
    final relDoc = documents[targetRelId];
    if (relDoc == null) return;
    _syncCurrentPhaseFromRelease(relDoc);

    _isAgentBusy = true;
    _agentProgressStep =
        'Drafting Release Blueprint for ${relDoc.title} ($_planningModel · ${_thinkingLevel.toLowerCase()})...';
    notifyListeners();

    try {
      final planned = await ReleasePlannerAgent.planRelease(
        projectDoc: proj,
        releaseDoc: relDoc,
        existingBeats: existingBeats,
        existingFeaturesByBeat: existingFeaturesByBeat,
        deferredByBeatIndex: deferredByBeatIndex,
        apiKey: _apiKey,
        modelName: _planningModel,
        thinkingLevel: _thinkingLevel,
      );
      if (planned != null) {
        _releaseBlueprint = planned;
        _offlineErrorMessage = null;
        if (transitionToGateStage) {
          _currentStage = WorkbenchStage.releaseWorkbench;
        }
        _syncActiveProjectMetadata();
      } else {
        _setOfflineState();
      }
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
        'Refining Release Plan ($_conversationModel · ${_thinkingLevel.toLowerCase()})...';
    notifyListeners();

    try {
      final ok = await ReleasePlannerAgent.sendReleasePlanChatTurn(
        blueprint: bp,
        userMessage: message,
        apiKey: _apiKey,
        modelName: _conversationModel,
        thinkingLevel: _thinkingLevel,
      );
      if (ok) {
        _offlineErrorMessage = null;
        _syncActiveProjectMetadata();
      } else {
        _setOfflineState();
      }
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

    final stateNode = FeatureStateNode(
      id: '${featId}_${versionTag}_cp_1',
      name: 'Checkpoint 1: $cleanTitle',
      trigger: '',
      order: 0,
      checklist: const [],
      coveredScope: const [],
      tuningParams: const [],
      edgeCases: const [],
      parameters: {'releaseVersion': versionTag},
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

    selectFeature(featId);
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
    final projTitle = activeProject?.title ?? 'Game Prototype';
    final engineLabel = _activeEngineLabel;
    final prompt = '''
You are the Systems Designer for "$projTitle" ($engineLabel).
Tailor this newly added Feature ("${featDoc.title}" inside Epic "$beatTitle") so its tasks, numeric tuning parameters, and edge-case guards fit "$projTitle".
Return ONLY a JSON object:
{
  "goal": "<1 plain-English sentence starting with Build/Implement>",
  "doneWhen": "<1 observable playtest completion condition>",
  "checkpointTitle": "<2-4 word playable checkpoint title>",
  "playtestGate": "<Action -> Observable result>",
  "tasks": [
    "<Task 1 title> (2h)",
    "<Task 2 title> (1h)",
    "<Task 3 title> (1h)"
  ],
  "tuningParams": [
    "<param1: numericValue unit>",
    "<param2: numericValue unit>"
  ],
  "edgeCases": [
    "[STATE GUARD] <concise guard rule>"
  ]
}''';
    final json = await GeminiAgentClient.generateJson(
      prompt: prompt,
      apiKey: _apiKey,
      preferredModel: _conversationModel,
      thinkingLevel: _thinkingLevel,
      temperature: 0.4,
    );
    if (json != null && documents.containsKey(featureId)) {
      final cp = states.first;
      final aiGoal = json['goal']?.toString().trim() ?? '';
      final aiDoneWhen = json['doneWhen']?.toString().trim() ?? '';
      final aiTitle = json['checkpointTitle']?.toString().trim() ?? '';
      final aiGate = json['playtestGate']?.toString().trim() ?? '';
      final rawTasks = json['tasks'];
      final rawTuning = json['tuningParams'];
      final rawGuards = json['edgeCases'];
      if (aiGoal.isNotEmpty || aiDoneWhen.isNotEmpty) {
        final effectiveGoal = aiGoal.isNotEmpty
            ? aiGoal
            : 'Build ${featDoc.title} inside $beatTitle.';
        final effectiveDoneWhen = aiDoneWhen.isNotEmpty
            ? aiDoneWhen
            : (aiGate.isNotEmpty
                ? aiGate
                : 'Playtester verifies ${featDoc.title} in the test arena.');
        featDoc.sections['scope'] =
            'Goal: $effectiveGoal\n\nIn Scope:\n• ${featDoc.title}\n\nDone When: $effectiveDoneWhen';
        _persistDocument(featDoc);
        final bp = _releaseBlueprint;
        if (bp != null) {
          for (final b in bp.beats) {
            for (final f in b.features) {
              if (f.id == featureId) {
                f.goal = effectiveGoal;
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
      if (rawTasks is List && rawTasks.isNotEmpty) {
        cp.checklist = [
          for (int i = 0; i < rawTasks.length; i++)
            Subtask(
              id: '${featureId}_ai_t${i + 1}',
              text: rawTasks[i].toString().trim(),
              completed: false,
            ),
        ];
      }
      if (rawTuning is List && rawTuning.isNotEmpty) {
        cp.tuningParams =
            rawTuning.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();
      }
      if (rawGuards is List && rawGuards.isNotEmpty) {
        cp.edgeCases =
            rawGuards.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();
      }
      updateFeatureStates(featureId, states);
    }
    await synthesizeFeatureHowToStepsWithAi(featureId, forceRefresh: true);
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

    // Prevent deleting the very last feature in the entire release so the Workbench never empties
    final allFeats = <TierDocument>[
      for (final b in activeReleaseBeats) ...featuresForBeat(b.id),
    ];
    if (allFeats.length <= 1) return false;

    if (beatDoc != null) {
      beatDoc.childrenIds.remove(featureId);
      _persistDocument(beatDoc);
    }
    documents.remove(featureId);

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

    if (_selectedFeatureId == featureId) {
      _selectFirstIncompleteFeatureInActiveRelease();
    }
    _syncActiveProjectMetadata();
    notifyListeners();
    return true;
  }

  /// Logs a Playtest Issue on a Checkpoint in `2. Workbench`:
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
    final cpNode = states[checkpointIndex];
    final newTaskIndex = cpNode.checklist.length;
    final taskNum = newTaskIndex + 1;
    final engineLabel = _activeEngineLabel;
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
              'Trigger "$cleanIssue" in the game viewport and inspect live state values ($primaryTune).',
          codeTargetFile: 'custom_snippet',
          codeSnippet: isUnity
              ? '// Inspect live state when "$cleanIssue" occurs\nDebug.LogWarning("[PLAYTEST FIX] $cleanIssue | $primaryTune");'
              : (isUnreal
                  ? '// Inspect live state when "$cleanIssue" occurs\nUE_LOG(LogTemp, Warning, TEXT("[PLAYTEST FIX] %s"), *GetName());'
                  : '# Inspect live state when "$cleanIssue" occurs\nprint("[PLAYTEST FIX] $cleanIssue | $primaryTune")'),
        ),
        Subtask(
          id: generateUniqueId('fix_sub_2'),
          text: 'STEP $taskNum.2 · APPLY FIX & CLAMP TUNING BOUNDS',
          specNotes:
              'Adjust the update/collision logic and clamp $primaryTune so "$cleanIssue" cannot happen.',
          codeTargetFile: 'custom_snippet',
          codeSnippet: isUnity
              ? '// Enforce boundary check for: $cleanIssue\n// Active tuning: $primaryTune'
              : (isUnreal
                  ? '// Enforce boundary check for: $cleanIssue\n// Active tuning: $primaryTune'
                  : '# Enforce boundary check for: $cleanIssue\n# Active tuning: $primaryTune'),
        ),
        Subtask(
          id: generateUniqueId('fix_sub_3'),
          text: 'STEP $taskNum.3 · VERIFY PLAYTEST GUARD IN VIEWPORT',
          specNotes:
              'Re-run the checkpoint playtest gate ("${cpNode.playtestCondition}") 3 times to confirm "$cleanIssue" is resolved.',
          codeTargetFile: 'custom_snippet',
          codeSnippet: isUnity
              ? '// Verify guard in Play mode: [PLAYTEST GUARD] $cleanIssue'
              : (isUnreal
                  ? '// Verify guard in Play mode: [PLAYTEST GUARD] $cleanIssue'
                  : '# Verify guard in Play mode: [PLAYTEST GUARD] $cleanIssue'),
        ),
      ],
    );

    cpNode.checklist.add(fixTask);
    final guardText = '[PLAYTEST GUARD] $cleanIssue';
    if (!cpNode.edgeCases.contains(guardText)) {
      cpNode.edgeCases = [...cpNode.edgeCases, guardText];
    }
    updateFeatureStates(featureId, states);
    if (GeminiAgentClient.hasKey(_apiKey) ||
        GeminiAgentClient.testMockResponder != null) {
      _enrichPlaytestFixWithAi(
        featureId: featureId,
        states: states,
        checkpointIndex: checkpointIndex,
        fixTaskIndex: newTaskIndex,
        issueDescription: cleanIssue,
      );
    } else {
      _setOfflineState();
      notifyListeners();
    }
    return newTaskIndex;
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
    final fixTask = cpNode.checklist[fixTaskIndex];
    final featTitle = documents[featureId]?.title ?? cpNode.cleanStageTitle;
    final engineLabel = _activeEngineLabel;
    final taskNum = fixTaskIndex + 1;

    _synthesizingFeatureIds.add(featureId);
    notifyListeners();
    try {
      final prompt = '''
You are the Playtest Root-Cause Debugger for LAYERS-Agentic ($engineLabel).
Diagnose this reported playtest bug on Feature "$featTitle" (Checkpoint "${cpNode.cleanStageTitle}") and synthesize a concrete 3-step engine fix:
Reported Bug: "$issueDescription"
Active Tuning Parameters: ${cpNode.tuningParams.join(', ')}
Active Guards: ${cpNode.edgeCases.join(', ')}

Return ONLY a JSON object with 3 concrete fix steps:
{
  "playtestGuard": "[PLAYTEST GUARD] <1 concise rule preventing this bug>",
  "steps": [
    {
      "title": "STEP $taskNum.1 · <SHORT LITERAL STEP TITLE>",
      "stepPath": "<Exact $engineLabel panel/inspector/script path>",
      "instruction": "<1 sentence concrete fix/inspection instruction>",
      "codeFormula": "<2-4 lines of $engineLabel code or node setup>",
      "verifyResult": "<1 sentence visual/console check in Play mode>"
    }
  ]
}''';
      final json = await GeminiAgentClient.generateJson(
        prompt: prompt,
        apiKey: _apiKey,
        preferredModel: _planningModel,
        thinkingLevel: _thinkingLevel,
        temperature: 0.3,
      );
      if (json == null) return;
      final rawSteps = json['steps'];
      if (rawSteps is List && rawSteps.isNotEmpty) {
        final updatedSubs = <Subtask>[];
        for (int i = 0; i < rawSteps.length; i++) {
          final item = rawSteps[i];
          if (item is Map) {
            final title = item['title']?.toString().trim() ?? '';
            final path = item['stepPath']?.toString().trim() ?? '';
            final instr = item['instruction']?.toString().trim() ?? '';
            final code = item['codeFormula']?.toString().trim() ?? '';
            final verify = item['verifyResult']?.toString().trim() ?? '';
            final prevDone = i < fixTask.children.length
                ? fixTask.children[i].completed
                : false;
            updatedSubs.add(
              Subtask(
                id: i < fixTask.children.length
                    ? fixTask.children[i].id
                    : generateUniqueId('fix_ai_sub_${i + 1}'),
                text: title.isNotEmpty
                    ? title
                    : 'STEP $taskNum.${i + 1} · APPLY ROOT-CAUSE FIX ${i + 1}',
                specNotes: instr,
                codeSnippet: code,
                codeLanguage: path,
                verification: verify,
                codeTargetFile: 'custom_snippet',
                completed: prevDone,
              ),
            );
          }
        }
        if (updatedSubs.isNotEmpty) {
          fixTask.children = updatedSubs;
        }
      }
      final aiGuard = json['playtestGuard']?.toString().trim() ?? '';
      if (aiGuard.isNotEmpty) {
        final normGuard = aiGuard.startsWith('[PLAYTEST GUARD]')
            ? aiGuard
            : '[PLAYTEST GUARD] $aiGuard';
        if (!cpNode.edgeCases.contains(normGuard)) {
          cpNode.edgeCases = [...cpNode.edgeCases, normGuard];
        }
      }
      TaskHowToBlueprint.clearCache();
      updateFeatureStates(featureId, states);
    } finally {
      _synthesizingFeatureIds.remove(featureId);
      notifyListeners();
    }
  }

  /// Tailors the checkable How-To sub-steps (`Step X.1` through `Step X.N`) for a specific
  /// Parent Task in Stage 3 using Gemini AI (`gemini-flash-latest`).
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
    final engineHint = _activeEngineHint;
    final engineLabel = _activeEngineLabel;
    final taskNum = taskIndex + 1;

    // Ensure children are initialized first
    TaskHowToBlueprint.resolve(
      parentTask: parentTask,
      taskIndex: taskIndex,
      checkpointNode: cpNode,
      engineHint: engineHint,
    );

    if (!GeminiAgentClient.hasKey(_apiKey)) {
      _setOfflineState();
      return;
    }

    final prompt = '''
You are a senior game engine programmer assisting with a concrete implementation task.
Engine: $engineLabel
Feature: "${featDoc?.title ?? cpNode.name}"
Task ($taskNum): "${parentTask.text}"
Active Tuning Parameters: ${cpNode.tuningParams.join(', ')}
Active Edge-Case Guards: ${cpNode.edgeCases.join(', ')}
Developer's Exact Scene / Node / Script Setup: "$cleanContext"

Break this task down into the exact number of checkable How-To Sub-Steps (Step $taskNum.1 through Step $taskNum.N — e.g., 3 steps for a simple hook/guard task or up to 6 steps for a multi-part mechanic) specifically using the developer's node/script names from "$cleanContext".
Return ONLY a JSON object with this schema:
{
  "subSteps": [
    {
      "title": "STEP $taskNum.1 · SHORT LITERAL SUB-STEP TITLE",
      "stepPath": "Exact $engineLabel editor panel/inspector/script path",
      "instruction": "1-sentence literal instruction referencing the user's exact nodes/scripts",
      "codeFormula": "2-4 lines of $engineLabel code or hierarchy setup using the user's node/script names",
      "verifyResult": "1-sentence observable verification check in Play mode"
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
      final newChildren = <Subtask>[];
      for (int i = 0; i < rawSubs.length; i++) {
        final item = rawSubs[i];
        if (item is Map) {
          final t = (item['title'] ?? '').toString().trim();
          final path = (item['stepPath'] ?? '').toString().trim();
          final instr = (item['instruction'] ?? '').toString().trim();
          final code = (item['codeFormula'] ?? '').toString().trim();
          final verify = (item['verifyResult'] ?? '').toString().trim();
          final prevDone = i < parentTask.children.length
              ? parentTask.children[i].completed
              : parentTask.completed;
          newChildren.add(
            Subtask(
              id: '${parentTask.id}_sub_${i + 1}',
              text: t.isNotEmpty
                  ? t
                  : 'STEP $taskNum.${i + 1} · IMPLEMENT STEP ${i + 1}',
              specNotes: instr,
              codeSnippet: code,
              codeLanguage: path,
              verification: verify,
              codeTargetFile: 'custom_snippet',
              completed: prevDone,
            ),
          );
        }
      }
      if (newChildren.isNotEmpty) {
        _offlineErrorMessage = null;
        parentTask.children = newChildren;
        TaskHowToBlueprint.clearCache();
        updateFeatureStates(featureId, states);
        return;
      }
    }

    _setOfflineState();
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

      // Auto-select the first Feature that has incomplete checkpoints (or Beat 1 / Feature 1)
      // before syncing project metadata so selected_beat_id / selected_feature_id are persisted together.
      _selectFirstIncompleteFeatureInActiveRelease();
      _syncActiveProjectMetadata();
      if (_selectedFeatureId != null && GeminiAgentClient.hasKey(_apiKey)) {
        synthesizeFeatureHowToStepsWithAi(_selectedFeatureId!);
      }
    } finally {
      _isAgentBusy = false;
      _agentProgressStep = null;
      notifyListeners();
    }
  }

  final Set<String> _aiSynthesizedFeatureSteps = <String>{};
  final Set<String> _synthesizingFeatureIds = <String>{};

  bool isSynthesizingFeatureSteps(String featureId) =>
      _synthesizingFeatureIds.contains(featureId);

  /// Synthesizes bespoke, engine-specific 3-Area How-To Sub-Steps (`Where` -> `Code / Action` -> `Verify`)
  /// for the active checkpoint of `featureId` using `_planningModel` (`gemini-4-argon`).
  Future<void> synthesizeFeatureHowToStepsWithAi(
    String featureId, {
    bool forceRefresh = false,
  }) async {
    if (!GeminiAgentClient.hasKey(_apiKey)) return;
    final feat = documents[featureId];
    if (feat == null) return;
    final engineLabel = _activeEngineLabel;
    final engineHint = _activeEngineHint;
    final synthKey = '${featureId}_$engineLabel';
    if (!forceRefresh &&
        (_aiSynthesizedFeatureSteps.contains(synthKey) ||
            _synthesizingFeatureIds.contains(featureId))) {
      return;
    }

    final states = FeatureStateNode.getStatesForDocument(feat);
    if (states.isEmpty) return;
    final activeVer = activeReleaseVersionTag;
    final cpIndex = states.indexWhere((s) => s.releaseVersion == activeVer);
    final cpNode = cpIndex >= 0 ? states[cpIndex] : states.first;
    if (cpNode.checklist.isEmpty) return;

    // Skip if already customized with custom_snippet across tasks (unless forceRefresh)
    final alreadyCustom = cpNode.checklist.every(
      (t) =>
          t.children.isNotEmpty &&
          t.children.every((c) => c.codeTargetFile == 'custom_snippet'),
    );
    if (!forceRefresh && alreadyCustom) {
      _aiSynthesizedFeatureSteps.add(synthKey);
      return;
    }

    for (int tIdx = 0; tIdx < cpNode.checklist.length; tIdx++) {
      TaskHowToBlueprint.resolve(
        parentTask: cpNode.checklist[tIdx],
        taskIndex: tIdx,
        checkpointNode: cpNode,
        engineHint: engineHint,
      );
    }

    _synthesizingFeatureIds.add(featureId);
    notifyListeners();

    try {
      final projTitle = activeProject?.title ?? 'Game Prototype';
      final taskSummaries = <String>[];
      for (int tIdx = 0; tIdx < cpNode.checklist.length; tIdx++) {
        taskSummaries.add('Task ${tIdx + 1}: "${cpNode.checklist[tIdx].text}"');
      }

      final prompt = '''
You are the Principal Game Engine Architect ($engineLabel) for "$projTitle".
Synthesize concrete, beginner-friendly 3-Area Engine How-To steps for Feature "${feat.title}" (Checkpoint "${cpNode.cleanStageTitle}").
Tasks:
${taskSummaries.join('\n')}
Active Tuning Parameters: ${cpNode.tuningParams.join(', ')}
Active Guards: ${cpNode.edgeCases.join(', ')}

For each task (1..${cpNode.checklist.length}), return 3 to 5 sequential sub-steps covering Scene/Hierarchy node setup, Inspector tuning property setup, and Script/Event Graph logic & guard checks:
1. "title": "STEP X.Y · SHORT LITERAL STEP TITLE"
2. "stepPath": Exact $engineLabel editor panel/menu/inspector path (e.g., "Scene Dock → + Add Child Node", "Inspector → Tuning Parameters", "Hierarchy → + Create Empty", "Components Panel → + Add", or script file path)
3. "instruction": 1-2 sentences explaining exactly what to click or type in $engineLabel
4. "codeFormula": 2-5 lines of concrete $engineLabel hierarchy tree (using ├─ / └─ for node setup steps) or executable code/property configuration using the feature's tuning parameters and guards
5. "verifyResult": 1 sentence observable verification check in the editor or Play mode

Return ONLY valid JSON:
{
  "tasks": [
    {
      "taskIndex": 0,
      "subSteps": [
        {
          "title": "STEP 1.1 · ...",
          "stepPath": "...",
          "instruction": "...",
          "codeFormula": "...",
          "verifyResult": "..."
        }
      ]
    }
  ]
}''';

      final json = await GeminiAgentClient.generateJson(
        prompt: prompt,
        apiKey: _apiKey,
        preferredModel: _planningModel,
        thinkingLevel: _thinkingLevel,
        temperature: 0.3,
      );
      final rawTasks = json?['tasks'];
      if (rawTasks is! List || rawTasks.isEmpty) return;

      bool mutated = false;
      for (final rawTask in rawTasks) {
        if (rawTask is! Map) continue;
        final tIdx = int.tryParse(rawTask['taskIndex']?.toString() ?? '') ?? -1;
        if (tIdx < 0 || tIdx >= cpNode.checklist.length) continue;
        final parentTask = cpNode.checklist[tIdx];
        final taskNum = tIdx + 1;
        final rawSubs = rawTask['subSteps'];
        if (rawSubs is! List || rawSubs.isEmpty) continue;

        final newChildren = <Subtask>[];
        for (int sIdx = 0; sIdx < rawSubs.length; sIdx++) {
          final item = rawSubs[sIdx];
          if (item is! Map) continue;
          final title = item['title']?.toString().trim() ?? '';
          final path = item['stepPath']?.toString().trim() ?? '';
          final instr = item['instruction']?.toString().trim() ?? '';
          final code = item['codeFormula']?.toString().trim() ?? '';
          final verify = item['verifyResult']?.toString().trim() ?? '';
          if (instr.isEmpty && code.isEmpty) continue;
          final prevDone = sIdx < parentTask.children.length
              ? parentTask.children[sIdx].completed
              : parentTask.completed;
          newChildren.add(
            Subtask(
              id: '${parentTask.id}_sub_${sIdx + 1}',
              text: title.isNotEmpty
                  ? title
                  : 'STEP $taskNum.${sIdx + 1} · IMPLEMENT STEP ${sIdx + 1}',
              specNotes: instr,
              codeSnippet: code,
              codeLanguage: path,
              verification: verify,
              codeTargetFile: 'custom_snippet',
              completed: prevDone,
            ),
          );
        }
        if (newChildren.isNotEmpty) {
          parentTask.children = newChildren;
          mutated = true;
        }
      }

      if (mutated) {
        _aiSynthesizedFeatureSteps.add(synthKey);
        TaskHowToBlueprint.clearCache();
        updateFeatureStates(featureId, states);
      }
    } finally {
      _synthesizingFeatureIds.remove(featureId);
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
    if (_selectedFeatureId != null && GeminiAgentClient.hasKey(_apiKey)) {
      synthesizeFeatureHowToStepsWithAi(_selectedFeatureId!);
    }
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
    if (GeminiAgentClient.hasKey(_apiKey)) {
      synthesizeFeatureHowToStepsWithAi(featureId);
    }
  }

  void updateFeatureStates(String featureId, List<FeatureStateNode> states) {
    final feat = documents[featureId];
    if (feat == null) return;
    FeatureStateNode.saveStatesToDocument(feat, states);
    if (states.isNotEmpty) {
      final activeCp = states.firstWhere(
        (s) => !s.isCompleted,
        orElse: () => states.first,
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
    }
    TaskHowToBlueprint.clearCache();
    _persistDocument(feat, debounce: true);
    notifyListeners();
  }

  static final RegExp _mvpEpicLabelRegex =
      RegExp(r'MVP Epic\s*\d+(?:\s*\([^)]+\))?', caseSensitive: false);

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

  /// Concise milestone subtitle for the Stage 3 Release Dropdown and header pill.
  String releaseConciseLabel(TierDocument relDoc) {
    final protoPart = relDoc.sections['prototypePart'] ?? '';
    if (protoPart == '1') return 'Prototype (Part 1)';
    if (protoPart == '2') return 'Prototype (Part 2)';
    final phase = relDoc.sections['phase'] ?? '';
    if (phase == ProductionPhase.mvp.name) {
      final match = _mvpEpicLabelRegex.firstMatch(relDoc.title);
      if (match != null) return match.group(0)!.trim();
      final idx =
          (int.tryParse(relDoc.sections['targetEpicIndex'] ?? '') ?? 0) + 1;
      return 'MVP Epic $idx';
    }
    if (phase == ProductionPhase.verticalSlice.name ||
        relDoc.releaseScope == ReleaseScope.verticalSlice) {
      return 'Vertical Slice';
    }
    if (phase == ProductionPhase.fullProduction.name ||
        relDoc.releaseScope == ReleaseScope.fullProduction) {
      final pass = relDoc.sections['fullProductionPass'] ?? '1';
      return 'Full Production (Pass $pass)';
    }
    return relDoc.releaseScope.label;
  }

  /// Rollup progress (0-100) for any document in the hierarchy, scoped to the active release's delta checkpoints.
  int getDocumentProgress(String docId) {
    final doc = documents[docId];
    if (doc == null) return 0;

    if (doc.tier == TierType.feature) {
      if (doc.sections['lifecycle'] == FeatureLifecycleStatus.stable.name) {
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
        return feats.any(
          (f) => f.sections['lifecycle'] != FeatureLifecycleStatus.stable.name,
        );
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
        return f != null &&
            f.sections['lifecycle'] != FeatureLifecycleStatus.stable.name;
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

  ProductionPhase _currentPhase = ProductionPhase.prototype;
  ProductionPhase get currentPhase => _currentPhase;

  /// Concise 4-Phase Release Train badge displayed in Stage 2 and Stage 3 headers.
  String get activePhaseBadgeLabel {
    final rel = activeRelease;
    final allRels = projectReleases;
    switch (_currentPhase) {
      case ProductionPhase.prototype:
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
        if (mvpRels.isNotEmpty && rel != null) {
          final idx = mvpRels.indexWhere((r) => r.id == rel.id);
          if (idx >= 0) {
            return 'PHASE 2 · MVP EPIC ${idx + 1} OF ${mvpRels.length}';
          }
        }
        return 'PHASE 2 · MVP TRACK';
      case ProductionPhase.verticalSlice:
        return 'PHASE 3 · VERTICAL SLICE';
      case ProductionPhase.fullProduction:
        final pass = rel?.sections['fullProductionPass'] ?? '1';
        return 'PHASE 4 · FULL PRODUCTION (PASS $pass)';
    }
  }

  /// Descriptive CTA label for the Stage 3 `Ship & Plan Next Release` button naming the exact next milestone or phase unlock.
  String get nextReleaseActionLabel {
    final releases = projectReleases;
    final currentIdx = releases.indexWhere((r) => r.id == _activeReleaseId);
    final nextIdx = currentIdx + 1;
    if (nextIdx >= 0 && nextIdx < releases.length) {
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
        return 'Ship & Unlock Phase 2 (MVP Epic 1) ✦';
      case ProductionPhase.mvp:
        return 'Ship & Unlock Phase 3 (Vertical Slice) ✦';
      case ProductionPhase.verticalSlice:
        return 'Ship & Unlock Phase 4 (Full Production) ✦';
      case ProductionPhase.fullProduction:
        return 'Ship & Plan Next Full Production Pass ✦';
    }
  }

  ReleaseRetrospectiveSummary? _lastReleaseRetrospective;
  ReleaseRetrospectiveSummary? get lastReleaseRetrospective =>
      _lastReleaseRetrospective;

  /// Advances to the next queued Release in the current Production Phase, or unlocks the
  /// next Production Phase once the current phase's releases are completed:
  /// - Phase 1 (Prototype) complete -> Phase 2 (MVP Track: 1 MVP Release per Core Loop Beat)
  /// - Phase 2 (MVP Track) complete -> Phase 3 (Vertical Slice: 1 Polished Gold Standard Level)
  /// - Phase 3 (Vertical Slice) complete -> Phase 4 (Full Production: World & Content Expansion)
  Future<void> advanceToNextRelease({bool transitionToGateStage = true}) async {
    final proj = activeProject;
    if (proj == null) return;
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
          title: 'v0.$newIndex: MVP Epic ${i + 1} ($beatLabel) - MVP',
          tier: TierType.release,
          parentId: proj.id,
          sections: {
            'releaseScope': ReleaseScope.mvp.name,
            'phase': ProductionPhase.mvp.name,
            'targetEpicIndex': '$i',
            'scope':
                'Goal: Build and connect MVP systems for Epic ${i + 1} ($beatLabel).\n\nIn Scope:\n• $beatLabel\n\nDone When: Epic ${i + 1} is playable end-to-end inside the rough representative level.',
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

    // Phase 4: Full Production content drops (reusing the Rough -> Polish pattern)
    _currentPhase = ProductionPhase.fullProduction;
    final existingFullProdCount = releases
        .where((r) => r.sections['phase'] == ProductionPhase.fullProduction.name)
        .length;
    final fullProdPass = existingFullProdCount + 1;
    final newIndex = proj.childrenIds.length + 1;
    final newRelId = proj.id == 'proj_main'
        ? 'rel_v0_$newIndex'
        : '${proj.id}_rel_v0_$newIndex';
    final fullProdVersion = 'v1.${fullProdPass - 1}';
    final fullProdTitle = fullProdPass == 1
        ? '$fullProdVersion: Full Production — Content, Levels & Deferred Systems - Full Production'
        : '$fullProdVersion: Full Production — World & Balance Expansion (Pass $fullProdPass) - Full Production';
    final newRelDoc = TierDocument(
      id: newRelId,
      title: fullProdTitle,
      tier: TierType.release,
      parentId: proj.id,
      sections: {
        'releaseScope': ReleaseScope.fullProduction.name,
        'phase': ProductionPhase.fullProduction.name,
        'fullProductionPass': '$fullProdPass',
        'scope':
            'Goal: Expand the verified Vertical Slice template across new levels, content waves, and previously deferred systems.\n\nIn Scope:\n• Content & level roster expansion\n• Promote deferred Out-of-Scope systems up to the Vertical Slice bar\n\nDone When: All new content and promoted systems pass playtest verification at Vertical Slice quality.',
      },
    );
    documents[newRelId] = newRelDoc;
    _persistDocument(newRelDoc);
    proj.childrenIds.add(newRelId);
    _syncActiveProjectMetadata();
    await openGateAndRecordRetro(newRelId);
  }
}
