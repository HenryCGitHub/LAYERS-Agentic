part of 'workbench_provider.dart';

/// Cloud Firestore real-time sync, Google authentication, and team/collaborator
/// invite flows for [WorkbenchProvider].
extension WorkbenchCloudSyncMixin on WorkbenchProvider {
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
}
