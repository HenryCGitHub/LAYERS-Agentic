part of 'workbench_provider.dart';

/// Persistence, Cloud Firestore real-time sync, authentication, and multi-project vault operations
/// for [WorkbenchProvider].
extension WorkbenchStorageMixin on WorkbenchProvider {
  static const Set<String> _legacyPlaceholderIds = {
    'proj_vanguard',
    'rel_01',
    'epic_01',
    'feat_01',
    'feat_02',
  };

  void _onAuthStateChanged() {
    final user = _authService.currentUser;
    if (user == null) {
      _isCloudSynced = false;
      _myAiAccessStatus = null;
      _aiAccessRecords = const [];
      _firestoreService.stopRealtimeSync();
      notifyListeners();
      return;
    }

    final email = (user.email ?? '').trim().toLowerCase();
    if (email == WorkbenchProvider.ownerAdminEmail) {
      _myAiAccessStatus = 'approved';
      _pendingUrlInviteToken = null;
      _pendingUrlInvitedEmail = null;
      _inviteFeedbackMessage = null;
      _startApprovedCloudSync(user.uid, isAdmin: true, userEmail: email);
      notifyListeners();
      return;
    }

    // Non-admin sign-in: verify or activate invite BEFORE touching Firestore `users/{uid}`
    unawaited(_verifyOrAcceptInvitedLogin(user.uid, email));
  }

  void _startApprovedCloudSync(
    String uid, {
    required bool isAdmin,
    required String userEmail,
  }) {
    GeminiAgentClient.lastErrorStatus = null;
    _offlineErrorMessage = null;
    _isCloudSynced = true;
    _lastCloudSyncAt = DateTime.now();

    if (isAdmin) {
      _firestoreService.watchAllAiAccessEntries(
        onEntries: (entries) {
          _aiAccessRecords = entries;
          notifyListeners();
        },
      );
    } else {
      _firestoreService.watchMyAiAccess(
        email: userEmail,
        onStatus: (status) {
          if (status == 'revoked') {
            _myAiAccessStatus = 'revoked';
            _isCloudSynced = false;
            _firestoreService.stopRealtimeSync();
            _offlineErrorMessage =
                'Access for $userEmail has been revoked by the workspace admin.';
            unawaited(_authService.signOut());
            notifyListeners();
          } else if (status != null) {
            _myAiAccessStatus = status;
            notifyListeners();
          }
        },
      );
    }

    bool initialLocalPushDone = false;
    () async {
      try {
        final remoteInitial = await _firestoreService.fetchAllDocuments(
          uid: uid,
        );
        final mergeRes = CloudInviteDeepLinkService.mergeRemoteDocumentMap(
          documents: documents,
          remoteDocs: remoteInitial,
        );
        final docsToPush = mergeRes.docsToPush;
        for (final winner in mergeRes.docsToSaveLocally) {
          documents[winner.id] = winner;
          LocalVaultService.saveDocument(winner);
        }
        if (mergeRes.docsToSaveLocally.isNotEmpty && !_isAgentBusy) {
          if (!_restorePostSyncSelection(createFallbackIfEmpty: false)) {
            notifyListeners();
          }
        }
        await Future.wait([
          for (final doc in docsToPush)
            _firestoreService.saveDocument(uid: uid, doc: doc),
        ]);
      } finally {
        initialLocalPushDone = true;
      }
    }();
    if (_activeProjectId != null) {
      _firestoreService.saveSettings(
        uid: uid,
        settings: {
          'activeDocumentId': _activeProjectId,
          'themeMode': _isDark ? 'dark' : 'light',
        },
      );
    } else {
      _firestoreService.fetchUserSettings(uid: uid).then((remoteSettings) {
        if (remoteSettings == null) return;
        final remoteTheme = remoteSettings['themeMode']?.toString();
        if (remoteTheme != null) {
          _isDark = remoteTheme != 'light';
        }
        final remoteActiveId = remoteSettings['activeDocumentId']?.toString();
        if (!_tryResolvePendingDeepLink() &&
            _activeProjectId == null &&
            remoteActiveId != null &&
            documents.containsKey(remoteActiveId)) {
          _restoreProjectState(remoteActiveId);
        }
        notifyListeners();
      });
    }
    _firestoreService.startRealtimeSync(
      uid: uid,
      onSync: (remoteDocs) {
        _lastCloudSyncAt = DateTime.now();
        if (!initialLocalPushDone) return;
        applyRemoteDocumentSnapshot(remoteDocs);
      },
    );
  }

  /// Re-applies the latest queued Firestore snapshot once in-flight writes and agent turns finish.
  void flushDeferredRemoteSnapshotIfIdle() {
    if (_isDisposed || _isAgentBusy || _pendingCloudWriteDocIds.isNotEmpty) {
      return;
    }
    final queued = _deferredRemoteSnapshot;
    if (queued == null) return;
    _deferredRemoteSnapshot = null;
    applyRemoteDocumentSnapshot(queued);
  }

  bool _restorePostSyncSelection({required bool createFallbackIfEmpty}) {
    if (_tryResolvePendingDeepLink()) return false;
    final keepingNewProjectIntake = _activeProjectId != null &&
        _activeProjectId == _unpersistedNewProjectId &&
        !documents.containsKey(_activeProjectId);
    if (keepingNewProjectIntake) return false;
    if (_activeProjectId == null || !documents.containsKey(_activeProjectId)) {
      final projs = savedProjects;
      if (projs.isNotEmpty) {
        _restoreProjectState(projs.first.id);
      } else if (createFallbackIfEmpty) {
        createNewProject();
        return true;
      }
    } else {
      _restoreProjectState(
        _activeProjectId!,
        preserveProgressiveDraft:
            _isDraftingProgressive || _progressiveDraft != null,
        preserveSameProjectUi: true,
      );
    }
    return false;
  }

  /// Applies an incoming Firestore snapshot across `documents` while protecting
  /// active debounced keystrokes, in-flight Cloud writes, and live progressive release drafts.
  bool applyRemoteDocumentSnapshot(Map<String, TierDocument> remoteDocs) {
    if (_isAgentBusy || _pendingCloudWriteDocIds.isNotEmpty) {
      _deferredRemoteSnapshot = Map<String, TierDocument>.from(remoteDocs);
      return false;
    }
    _deferredRemoteSnapshot = null;
    final actions = CloudInviteDeepLinkService.computeSnapshotSyncActions(
      documents: documents,
      remoteDocs: remoteDocs,
      activePersistTimerIds: _persistTimers.keys.toSet(),
    );
    for (final removedId in actions.removedIds) {
      documents.remove(removedId);
      LocalVaultService.deleteDocument(removedId);
    }
    for (final nextDoc in actions.docsToApply) {
      documents[nextDoc.id] = nextDoc;
      LocalVaultService.saveDocument(nextDoc);
    }
    if (_restorePostSyncSelection(createFallbackIfEmpty: true)) {
      return true;
    }
    notifyListeners();
    return true;
  }

  Future<void> _verifyOrAcceptInvitedLogin(
    String uid,
    String signedInEmail,
  ) async {
    final result = await CloudInviteDeepLinkService.verifyOrAcceptInvitedLogin(
      signedInEmail: signedInEmail,
      inviteToken: _pendingUrlInviteToken,
      invitedEmail: _pendingUrlInvitedEmail,
    );
    _myAiAccessStatus = result.status;
    if (result.approved) {
      _pendingUrlInviteToken = null;
      _pendingUrlInvitedEmail = null;
      _inviteFeedbackMessage = null;
      _startApprovedCloudSync(uid, isAdmin: false, userEmail: signedInEmail);
      notifyListeners();
      return;
    }
    if (result.wrongAccount) {
      _inviteFeedbackMessage = result.feedbackMessage;
    } else {
      _offlineErrorMessage = result.offlineError;
    }
    await _authService.signOut();
    notifyListeners();
  }

  /// Sends (or resends) an email invite to [rawEmail] via `geminiProxy` `/sendInvite` (Admin-only).
  Future<({bool ok, bool emailSent, String? inviteUrl, String message})>
      sendUserInvite(
    String rawEmail, {
    bool resetStatus = false,
  }) async {
    final res = await CloudInviteDeepLinkService.sendUserInvite(
      rawEmail: rawEmail,
      ownerAdminEmail: WorkbenchProvider.ownerAdminEmail,
      currentRecords: _aiAccessRecords,
      resetStatus: resetStatus,
    );
    if (res.ok && res.updatedRecords != null) {
      _aiAccessRecords = res.updatedRecords!;
      notifyListeners();
    }
    return (
      ok: res.ok,
      emailSent: res.emailSent,
      inviteUrl: res.inviteUrl,
      message: res.message,
    );
  }

  /// Cancels a pending invite or revokes an active member's access (Admin-only).
  Future<bool> revokeUserInvite(String rawEmail) async {
    final updated = await CloudInviteDeepLinkService.revokeUserInvite(
      rawEmail: rawEmail,
      ownerAdminEmail: WorkbenchProvider.ownerAdminEmail,
      currentRecords: _aiAccessRecords,
    );
    if (updated != null) {
      _aiAccessRecords = updated;
      notifyListeners();
      return true;
    }
    return false;
  }

  /// Accepts a `?invite=<token>` link by signing in with Google and verifying via `/acceptInvite`.
  Future<bool> acceptPendingInviteWithGoogle() async {
    _inviteFeedbackMessage = null;
    notifyListeners();
    final cred = await _authService.signInWithGoogle();
    if (cred == null || cred.user == null) {
      notifyListeners();
      return false;
    }
    final uid = cred.user!.uid;
    final email = (cred.user!.email ?? '').trim().toLowerCase();
    if (email == WorkbenchProvider.ownerAdminEmail) {
      _myAiAccessStatus = 'approved';
      _pendingUrlInviteToken = null;
      _pendingUrlInvitedEmail = null;
      _startApprovedCloudSync(uid, isAdmin: true, userEmail: email);
      notifyListeners();
      return true;
    }
    await _verifyOrAcceptInvitedLogin(uid, email);
    return _myAiAccessStatus == 'approved';
  }

  void dismissPendingUrlInvite() {
    _pendingUrlInviteToken = null;
    _pendingUrlInvitedEmail = null;
    _inviteFeedbackMessage = null;
    notifyListeners();
  }

  /// Flushes pending debounced edits, merges remote-newer Cloud documents, and pushes
  /// local changes to Cloud Firestore without overwriting newer remote Cloud Vault edits.
  Future<void> syncNowWithCloud() async {
    if (_persistTimers.isNotEmpty) {
      final pendingIds = _persistTimers.keys.toList();
      for (final id in pendingIds) {
        _persistTimers.remove(id)?.cancel();
        final pendingDoc = documents[id];
        if (pendingDoc != null) {
          await LocalVaultService.saveDocument(pendingDoc);
        }
      }
    } else {
      for (final doc in documents.values) {
        await LocalVaultService.saveDocument(doc);
      }
    }

    final uid = (testOverrideUserUid ?? _authService.currentUser?.uid)?.trim();
    if (uid == null || uid.isEmpty || !isSessionApprovedForAi) {
      _persistSettings();
      _lastCloudSyncAt = DateTime.now();
      notifyListeners();
      return;
    }

    final remoteDocs = testCloudDocumentsFetcher != null
        ? await testCloudDocumentsFetcher!(uid)
        : await _firestoreService.fetchAllDocuments(uid: uid);

    final mergeRes = CloudInviteDeepLinkService.mergeRemoteDocumentMap(
      documents: documents,
      remoteDocs: remoteDocs,
    );
    final docsToPush = mergeRes.docsToPush;
    for (final winner in mergeRes.docsToSaveLocally) {
      documents[winner.id] = winner;
      await LocalVaultService.saveDocument(winner);
    }
    final mergedAny = mergeRes.docsToSaveLocally.isNotEmpty;

    final futures = <Future<void>>[];
    for (final doc in docsToPush) {
      _pendingCloudWriteDocIds.add(doc.id);
      final saveFuture = testCloudDocumentSaver != null
          ? testCloudDocumentSaver!(uid, doc)
          : _firestoreService.saveDocument(uid: uid, doc: doc);
      futures.add(
        saveFuture.whenComplete(() {
          _pendingCloudWriteDocIds.remove(doc.id);
          if (_pendingCloudWriteDocIds.isEmpty) {
            flushDeferredRemoteSnapshotIfIdle();
          }
        }),
      );
    }
    if (futures.isNotEmpty) {
      await Future.wait(futures);
    }
    if (_pendingCloudWriteDocIds.isEmpty) {
      flushDeferredRemoteSnapshotIfIdle();
    }

    if (mergedAny &&
        !_isAgentBusy &&
        _activeProjectId != null &&
        documents.containsKey(_activeProjectId)) {
      _restoreProjectState(
        _activeProjectId!,
        preserveProgressiveDraft:
            _isDraftingProgressive || _progressiveDraft != null,
        preserveSameProjectUi: true,
      );
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
    if (user != null && isSessionApprovedForAi) {
      await _firestoreService.inviteCollaborator(
        projectId: proj.id,
        projectTitle: proj.title,
        ownerEmail: user.email ?? 'owner',
        collaboratorEmail: cleanEmail,
        role: role,
      );
      if (isAdminUser) {
        unawaited(sendUserInvite(cleanEmail));
      }
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
    _autoSyncDebounceTimer?.cancel();
    _deferredRemoteSnapshot = null;
    _pendingCloudWriteDocIds.clear();
    await _authService.signOut();
    notifyListeners();
  }

  /// Applies Web Studio URL deep-link query params (`?project=<id>&epic=<id>`).
  void applyDeepLinkParams(Map<String, String> queryParams) {
    final parsed = CloudInviteDeepLinkService.parseDeepLinkQuery(queryParams);
    bool didUpdate = false;

    if (parsed.projectId != null) {
      _pendingUrlProjectId = parsed.projectId;
    }
    if (parsed.epicId != null) {
      _pendingUrlEpicId = parsed.epicId;
    }
    if (parsed.featureId != null) {
      _pendingUrlFeatureId = parsed.featureId;
    }
    if ((parsed.projectId != null ||
            parsed.epicId != null ||
            parsed.featureId != null) &&
        _tryResolvePendingDeepLink()) {
      didUpdate = true;
    }
    if (didUpdate) {
      notifyListeners();
    }
  }

  bool _tryResolvePendingDeepLink() {
    final target = CloudInviteDeepLinkService.resolvePendingDeepLinkTarget(
      documents: documents,
      savedProjects: savedProjects,
      pendingProjectId: _pendingUrlProjectId,
      pendingEpicId: _pendingUrlEpicId,
    );
    if (target == null) return false;

    final targetProjId = target.projectId;
    final matchedEpicDoc = target.matchedEpicDoc;
    if (_activeProjectId != targetProjId) {
      _restoreProjectState(targetProjId);
    }
    final proj = documents[targetProjId];
    if (proj != null && projectReleases.isNotEmpty) {
      _currentStage = WorkbenchStage.releaseWorkbench;
      proj.sections['current_stage'] = WorkbenchStage.releaseWorkbench.name;
    }

    final reqFeatureId = _pendingUrlFeatureId;
    final hasEpicReq = _pendingUrlEpicId != null && _pendingUrlEpicId!.isNotEmpty;
    var resolvedEpic = !hasEpicReq;
    if (hasEpicReq && matchedEpicDoc != null) {
      final parentRelId = matchedEpicDoc.parentId;
      if (parentRelId != null &&
          documents[parentRelId]?.tier == TierType.release) {
        _activeReleaseId = parentRelId;
        proj?.sections['active_release_id'] = parentRelId;
      }
      if (reqFeatureId != null && reqFeatureId.isNotEmpty) {
        selectFeature(matchedEpicDoc.id, reqFeatureId);
        _pendingUrlFeatureId = null;
      } else {
        selectEpic(matchedEpicDoc.id);
      }
      resolvedEpic = true;
    }

    _pendingUrlProjectId = null;
    if (resolvedEpic) {
      _pendingUrlEpicId = null;
    }
    _persistSettings();
    return true;
  }

  /// Loads saved projects from LocalStorage / SharedPreferences, detects `?invite=` & `?project=`/`?feature=` URL params,
  /// and starts Cloud Firestore sync if an approved Google account is logged in.
  Future<void> initVault() async {
    try {
      final qp = Uri.base.queryParameters;
      final urlInvite = qp['invite']?.trim();
      if (urlInvite != null && urlInvite.isNotEmpty) {
        _pendingUrlInviteToken = urlInvite;
        _pendingUrlInvitedEmail = qp['invited_email']?.trim().toLowerCase();
      }
      applyDeepLinkParams(qp);
    } catch (_) {}

    try {
      final loaded = await LocalVaultService.loadVaultData();
      // Ignore legacy static placeholder docs (`proj_vanguard`) if they don't have a concept_blueprint_json
      for (final doc in loaded.documents.values) {
        if (_legacyPlaceholderIds.contains(doc.id)) {
          continue;
        }
        documents[doc.id] = doc;
      }
      if (loaded.themeMode != null) {
        _isDark = loaded.themeMode != 'light';
      }
      // API keys are no longer loaded from browser localStorage; all live calls authenticate via Google Sign-In + geminiProxy.
      _apiKey = GeminiAgentClient.resolveDefaultApiKey();
      const pinned = GeminiAgentClient.pinnedLiveFlashModel;
      final hadSavedAiPrefs = loaded.modelName != null ||
          loaded.planningModel != null ||
          loaded.thinkingLevel != null;
      _conversationModel = pinned;
      _planningModel = pinned;
      _thinkingLevel = 'LOW';

      final needsAiPrefsMigration = hadSavedAiPrefs &&
          (loaded.modelName?.trim() != pinned ||
              loaded.planningModel?.trim() != pinned ||
              loaded.thinkingLevel?.trim().toUpperCase() != 'LOW');
      final projs = savedProjects;
      if (!_tryResolvePendingDeepLink() && projs.isNotEmpty) {
        final targetId = (loaded.activeDocumentId != null &&
                documents.containsKey(loaded.activeDocumentId))
            ? loaded.activeDocumentId!
            : projs.first.id;
        _restoreProjectState(targetId);
      }
      if (needsAiPrefsMigration) {
        await LocalVaultService.saveSettings(
          activeDocumentId: _activeProjectId ??
              loaded.activeDocumentId ??
              'proj_main',
          apiKey: '',
          modelName: _conversationModel,
          planningModel: _planningModel,
          thinkingLevel: _thinkingLevel,
          themeMode: _isDark ? 'dark' : 'light',
        );
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

  /// Starts a brand-new Project at Stage 1 (`1. Project Spec`) while keeping existing projects in the vault.
  void createNewProject() {
    _activeProjectId = 'proj_${DateTime.now().millisecondsSinceEpoch}';
    _unpersistedNewProjectId = _activeProjectId;
    _activeReleaseId = null;
    _selectedEpicId = null;
    _selectedFeatureId = null;
    _expandedEpicIds.clear();
    _userPinnedMode = false;
    _conceptDraft = null;
    _clearStage1TransientState();
    _resetProgressiveDraftState();
    _showingSparkPicker = true;
    _offlineErrorMessage = null;
    _executionLog.clear();
    _currentStage = WorkbenchStage.projectPitch;
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
        bp.gameTitle = clean.toUpperCase();
        proj.sections['concept_blueprint_json'] = jsonEncode(bp.toJson());
        if (_activeProjectId == projectId && _conceptDraft != null) {
          _conceptDraft!.gameTitle = clean.toUpperCase();
        }
      } catch (_) {}
    }
    _persistDocument(proj);
    notifyListeners();
  }

  /// Collects all document IDs belonging to [projectId]'s 3-tier tree (`Project -> Release -> Epic`).
  Set<String> _collectProjectDocumentTreeIds(String projectId) =>
      ProjectArchiveCodec.collectProjectTreeIds(documents, projectId);

  /// Cancels pending debounce timers and saves [projectId]'s full 3-tier tree
  /// (`Project -> Release -> Epic`) to Firestore when syncing active project hierarchy before
  /// tab unload.
  Future<void> flushProjectTreeToCloud(String projectId) async {
    final treeIds = _collectProjectDocumentTreeIds(projectId);
    if (treeIds.isEmpty) return;
    for (final id in treeIds) {
      final timer = _persistTimers.remove(id);
      if (timer != null) {
        timer.cancel();
      }
      final doc = documents[id];
      if (doc != null) {
        LocalVaultService.saveDocument(doc);
      }
    }
    final uid = (testOverrideUserUid ?? _authService.currentUser?.uid)?.trim();
    if (uid == null || uid.isEmpty || !isSessionApprovedForAi) return;
    final futures = <Future<void>>[];
    for (final id in treeIds) {
      final doc = documents[id];
      if (doc == null) continue;
      _pendingCloudWriteDocIds.add(id);
      final saveFuture = testCloudDocumentSaver != null
          ? testCloudDocumentSaver!(uid, doc)
          : _firestoreService.saveDocument(uid: uid, doc: doc);
      futures.add(
        saveFuture.whenComplete(() {
          _pendingCloudWriteDocIds.remove(id);
          if (_pendingCloudWriteDocIds.isEmpty) {
            flushDeferredRemoteSnapshotIfIdle();
          }
        }),
      );
    }
    if (futures.isNotEmpty) {
      await Future.wait(futures);
    }
  }

  /// Deep-clones an existing project across all 3 tiers (`Project -> Release -> Epic`),
  /// persists to LocalVault & Cloud Firestore, and switches to the copy.
  String? duplicateProject(String projectId) {
    final cloned = ProjectArchiveCodec.cloneProjectTree(
      documents: documents,
      projectId: projectId,
      releaseDocsForProject: releaseDocsForProject,
      epicDocsForRelease: epicDocsForRelease,
    );
    if (cloned == null) return null;
    for (final doc in cloned.docsToSave) {
      documents[doc.id] = doc;
      _persistDocument(doc);
    }
    switchProject(cloned.newProjectId);
    return cloned.newProjectId;
  }

  /// Exports the full interactive state of [projectId] (`Project -> Release -> Epic`,
  /// Concept Blueprint, and Epic Specs) as a portable `.layers.json` bundle.
  String exportProjectToJson([String? projectId]) {
    final targetId = projectId ?? _activeProjectId;
    if (targetId == null) return '';
    if (targetId == _activeProjectId) {
      _syncActiveProjectMetadata();
    }
    return ProjectArchiveCodec.encodeProjectJson(
      documents: documents,
      projectId: targetId,
    );
  }

  /// Imports a `.layers.json` project bundle into the vault, automatically remapping IDs
  /// if any document ID collides with an existing project, and switches to the imported project.
  String? importProjectFromJson(String rawJson) {
    final decoded = ProjectArchiveCodec.decodeProjectJson(
      rawJson: rawJson,
      existingDocIds: documents.keys.toSet(),
    );
    if (decoded == null) return null;
    for (final doc in decoded.docsToSave) {
      documents[doc.id] = doc;
      _persistDocument(doc);
    }
    switchProject(decoded.importedProjectId);
    return decoded.importedProjectId;
  }

  /// Deletes a project and its child documents from LocalVaultService and Cloud Firestore.
  void deleteProject(String projectId) {
    final idsToRemove = _collectProjectDocumentTreeIds(projectId);
    if (idsToRemove.isEmpty) return;

    _projectCollaborators.remove(projectId);
    final user = _authService.currentUser;
    for (final id in idsToRemove) {
      _persistTimers.remove(id)?.cancel();
      _pendingCloudWriteDocIds.remove(id);
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
    if (_pendingCloudWriteDocIds.isEmpty) {
      flushDeferredRemoteSnapshotIfIdle();
    }
  }

  void _restoreProjectState(
    String projectId, {
    bool preserveProgressiveDraft = false,
    bool preserveSameProjectUi = false,
  }) {
    final proj = documents[projectId];
    if (proj == null) return;
    final prevProjectId = _activeProjectId;
    final prevConceptJson =
        _conceptDraft != null ? jsonEncode(_conceptDraft!.toJson()) : null;
    _unpersistedNewProjectId = null;
    if (!preserveProgressiveDraft) {
      _executionLog.clear();
      _resetProgressiveDraftState();
    }
    _activeProjectId = projectId;

    // Restore Collaborators
    final collabs = ProjectArchiveCodec.decodeCollaborators(
      proj.sections['collaborators_json'],
    );
    if (collabs != null) {
      _projectCollaborators[projectId] = collabs;
    }

    // Restore Concept Blueprint
    final rawConcept = proj.sections['concept_blueprint_json'];
    final sameConceptUnchanged = preserveSameProjectUi &&
        prevProjectId == projectId &&
        ((rawConcept == null && prevConceptJson == null) ||
            (rawConcept != null && rawConcept == prevConceptJson));
    if (rawConcept != null && rawConcept.isNotEmpty) {
      try {
        _conceptDraft = ProjectConceptBlueprint.fromJson(
          jsonDecode(rawConcept) as Map<String, dynamic>,
        );
      } catch (e) {
        debugPrint('Restore concept_blueprint_json error: $e');
        _conceptDraft = null;
      }
    } else {
      _conceptDraft = null;
    }
    if (!sameConceptUnchanged) {
      _clearStage1TransientState();
    }
    _showingSparkPicker = _conceptDraft == null || !_conceptDraft!.hasSpec;

    // Restore active Release & Epic selection
    final savedRelId = proj.sections['active_release_id'];
    if (savedRelId != null && documents[savedRelId]?.tier == TierType.release) {
      _activeReleaseId = savedRelId;
    } else if (projectReleases.isNotEmpty) {
      _activeReleaseId = projectReleases.first.id;
    } else {
      _activeReleaseId = null;
    }

    final epicDocs = activeReleaseEpicDocs;
    final validEpicIds = epicDocs.map((d) => d.id).toSet();
    if (preserveSameProjectUi && prevProjectId == projectId) {
      _expandedEpicIds.retainWhere(validEpicIds.contains);
    } else {
      _expandedEpicIds.clear();
    }
    if (epicDocs.isNotEmpty) {
      final savedEpicId = proj.sections['selected_epic_id'];
      if (savedEpicId != null && epicDocs.any((d) => d.id == savedEpicId)) {
        _selectedEpicId = savedEpicId;
      } else {
        final firstUnpassed = epicDocs.firstWhere(
          (d) => !EpicSpec.fromDocument(d).isPassed,
          orElse: () => epicDocs.first,
        );
        _selectedEpicId = firstUnpassed.id;
      }
      if (_selectedEpicId != null) {
        _expandedEpicIds.add(_selectedEpicId!);
      }
      if (proj.sections.containsKey('selected_feature_id')) {
        final savedFeatureId =
            (proj.sections['selected_feature_id'] ?? '').trim();
        if (savedFeatureId.isEmpty) {
          _selectedFeatureId = null;
        } else {
          _selectedFeatureId = _defaultFeatureIdForEpicDoc(
            _selectedEpicId,
            preferredId: savedFeatureId,
          );
        }
      } else {
        _selectedFeatureId = _defaultFeatureIdForEpicDoc(_selectedEpicId);
      }
    } else {
      _selectedEpicId = null;
      _selectedFeatureId = null;
    }

    final savedStage = proj.sections['current_stage'];
    if ((savedStage == WorkbenchStage.releaseWorkbench.name ||
            savedStage == 'releasePlanGate') &&
        epicDocs.isNotEmpty) {
      _currentStage = WorkbenchStage.releaseWorkbench;
    } else {
      _currentStage = WorkbenchStage.projectPitch;
    }
  }

  void _persistDocument(TierDocument doc, {bool debounce = false}) {
    _persistTimers.remove(doc.id)?.cancel();
    doc.sections['updated_at_ms'] =
        DateTime.now().millisecondsSinceEpoch.toString();
    void writeNow() {
      LocalVaultService.saveDocument(doc);
      final uid = (testOverrideUserUid ?? _authService.currentUser?.uid)?.trim();
      if (uid != null && uid.isNotEmpty && isSessionApprovedForAi) {
        _pendingCloudWriteDocIds.add(doc.id);
        final saveFuture = testCloudDocumentSaver != null
            ? testCloudDocumentSaver!(uid, doc)
            : _firestoreService.saveDocument(uid: uid, doc: doc);
        saveFuture.then((_) {
          _lastCloudSyncAt = DateTime.now();
        }).whenComplete(() {
          _pendingCloudWriteDocIds.remove(doc.id);
          if (_pendingCloudWriteDocIds.isEmpty) {
            flushDeferredRemoteSnapshotIfIdle();
          }
        });
      }
    }

    if (debounce && enableAutoLoad) {
      _persistTimers[doc.id] = Timer(const Duration(milliseconds: 250), () {
        _persistTimers.remove(doc.id);
        if (!documents.containsKey(doc.id)) return;
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
      apiKey: '',
      modelName: _conversationModel,
      planningModel: _planningModel,
      thinkingLevel: _thinkingLevel,
      themeMode: _isDark ? 'dark' : 'light',
    );
    final user = _authService.currentUser;
    if (user != null && isSessionApprovedForAi) {
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
    if (_selectedEpicId != null) {
      proj.sections['selected_epic_id'] = _selectedEpicId!;
    }
    proj.sections['selected_feature_id'] = _selectedFeatureId ?? '';
    if (_conceptDraft != null) {
      proj.sections['concept_blueprint_json'] =
          jsonEncode(_conceptDraft!.toJson());
    }
    _persistDocument(proj);
    _persistSettings();
  }
}
